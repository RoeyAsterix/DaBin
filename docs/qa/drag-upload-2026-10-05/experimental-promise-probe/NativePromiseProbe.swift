import AppKit
import Darwin
import Foundation
import UniformTypeIdentifiers

final class ProbeEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []
    private var results: [(String, Data?, String?)] = []
    func record(_ event: String) {
        lock.lock(); events.append(event); lock.unlock()
        print("EVENT: " + event)
    }
    func complete(_ url: URL, _ bytes: Data?, _ error: String?) {
        lock.lock(); results.append((url.path, bytes, error)); lock.unlock()
    }
    func snapshot() -> ([String], [(String, Data?, String?)]) {
        lock.lock(); defer { lock.unlock() }; return (events, results)
    }
}

final class ProbeDelegate: NSObject, NSFilePromiseProviderDelegate {
    let source: URL
    let coordinated: Bool
    let events: ProbeEvents
    let queue: OperationQueue
    init(source: URL, coordinated: Bool, events: ProbeEvents) {
        self.source = source; self.coordinated = coordinated; self.events = events
        queue = OperationQueue(); queue.name = "DaBin.IsolatedPromiseProbe.writer"
        queue.maxConcurrentOperationCount = 1
    }
    func filePromiseProvider(_ provider: NSFilePromiseProvider, fileNameForType type: String) -> String {
        events.record("delegate.filename " + type)
        return "Fixture.txt"
    }
    func operationQueue(for provider: NSFilePromiseProvider) -> OperationQueue {
        events.record("delegate.operationQueue"); return queue
    }
    func filePromiseProvider(_ provider: NSFilePromiseProvider, writePromiseTo url: URL,
                             completionHandler: @escaping (Error?) -> Void) {
        events.record("delegate.write.enter " + url.lastPathComponent)
        var writeError: Error?
        if coordinated {
            var coordinationError: NSError?
            events.record("delegate.coordinator.before")
            NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: [], error: &coordinationError) { destination in
                events.record("delegate.coordinator.accessor")
                do { try FileManager.default.copyItem(at: source, to: destination) }
                catch { writeError = error }
            }
            events.record("delegate.coordinator.after")
            if let coordinationError { writeError = coordinationError }
        } else {
            do { try FileManager.default.copyItem(at: source, to: url) }
            catch { writeError = error }
        }
        events.record("delegate.completion " + (writeError?.localizedDescription ?? "nil"))
        completionHandler(writeError)
    }
}

final class ComposedWriter: NSObject, NSPasteboardWriting {
    let provider: NSFilePromiseProvider
    let fileDelegate: ProbeDelegate
    let nativeURL: NSURL
    let events: ProbeEvents
    let routed: Bool
    init(provider: NSFilePromiseProvider, fileDelegate: ProbeDelegate, url: URL, events: ProbeEvents, routed: Bool) {
        self.provider = provider; self.fileDelegate = fileDelegate
        nativeURL = url as NSURL; self.events = events; self.routed = routed
    }
    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        var types = nativeURL.writableTypes(for: pasteboard)
        for type in provider.writableTypes(for: pasteboard) where !types.contains(type) { types.append(type) }
        events.record("wrapper.types " + types.map(\.rawValue).joined(separator: ","))
        return types
    }
    func writingOptions(forType type: NSPasteboard.PasteboardType, pasteboard: NSPasteboard) -> NSPasteboard.WritingOptions {
        if nativeURL.writableTypes(for: pasteboard).contains(type) {
            return nativeURL.writingOptions(forType: type, pasteboard: pasteboard)
        }
        return provider.writingOptions(forType: type, pasteboard: pasteboard)
    }
    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        events.record("wrapper.property " + type.rawValue)
        let result: Any?
        if routed {
            if type == .fileURL {
                result = nativeURL.pasteboardPropertyList(forType: type)
            } else { result = provider.pasteboardPropertyList(forType: type) }
        } else { result = nativeURL.pasteboardPropertyList(forType: type) ?? provider.pasteboardPropertyList(forType: type) }
        events.record("wrapper.result " + type.rawValue + " = " + String(describing: result))
        return result
    }
}

final class ProbeOwnership {
    let provider: NSFilePromiseProvider
    let fileDelegate: ProbeDelegate
    let writer: NSPasteboardWriting
    init(source: URL, coordinated: Bool, wrapped: Bool, routed: Bool, events: ProbeEvents) {
        fileDelegate = ProbeDelegate(source: source, coordinated: coordinated, events: events)
        provider = NSFilePromiseProvider(fileType: UTType.plainText.identifier, delegate: fileDelegate)
        writer = wrapped ? ComposedWriter(provider: provider, fileDelegate: fileDelegate, url: source, events: events, routed: routed) : provider
    }
}

@main @MainActor final class NativePromiseProbe: NSObject, NSApplicationDelegate {
    var result: Int32 = 1
    static func main() {
        setbuf(stdout, nil)
        let app = NSApplication.shared, delegate = NativePromiseProbe()
        app.setActivationPolicy(CommandLine.arguments.contains("--accessory") ? .accessory : .prohibited); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        exit(delegate.result)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { result = try await run() ? 0 : 2 }
            catch { print("PROBE_ERROR: \(error)"); result = 3 }
            print("COMPLETE: result=\(result)")
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }
    func run() async throws -> Bool {
        let name = CommandLine.arguments.dropFirst().first ?? "direct-plain"
        guard ["direct-plain", "direct-coordinated", "wrapped-plain", "wrapped-coordinated"].contains(name) else {
            throw NSError(domain: "NativePromiseProbe", code: 1)
        }
        let release = CommandLine.arguments.contains("--release")
        let routed = CommandLine.arguments.contains("--routed")
        let caseName = name + (release ? "-released" : "-retained") + (routed ? "-routed" : "")
            + (CommandLine.arguments.contains("--accessory") ? "-accessory" : "")
            + (CommandLine.arguments.contains("--bundle") ? "-bundle" : "")
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("runtime-" + caseName)
        let expectedRoot = URL(fileURLWithPath: "/private/tmp/dabin-native-file-promise-probe-20261005").standardizedFileURL
        guard root.deletingLastPathComponent().standardizedFileURL == expectedRoot else {
            throw NSError(domain: "NativePromiseProbe", code: 2)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let source = root.appendingPathComponent("Fictional.txt")
        let bytes = Data("Exact fictional isolated promise bytes — 資料 café.\n".utf8)
        try bytes.write(to: source, options: .withoutOverwriting)
        let destination = root.appendingPathComponent("receiver")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        let board = NSPasteboard(name: .init("DaBin.IsolatedFilePromiseProbe." + UUID().uuidString))
        defer { board.clearContents(); board.releaseGlobally() }
        let events = ProbeEvents()
        var ownership: ProbeOwnership? = ProbeOwnership(source: source, coordinated: name.hasSuffix("coordinated"),
            wrapped: name.hasPrefix("wrapped"), routed: routed, events: events)
        weak var observedProvider = ownership?.provider
        weak var observedDelegate = ownership?.fileDelegate
        weak var observedWriter = ownership?.writer as AnyObject?
        events.record("case " + caseName)
        events.record("direct.types " + ownership!.provider.writableTypes(for: board).map(\.rawValue).joined(separator: ","))
        let written = autoreleasepool { board.writeObjects([ownership!.writer]) }
        events.record("board.written \(written)")
        if release { autoreleasepool { ownership = nil } }
        events.record("ownership provider=\(observedProvider != nil) delegate=\(observedDelegate != nil) writer=\(observedWriter != nil)")
        let receivers = board.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver] ?? []
        events.record("receivers \(receivers.count)")
        let queue = OperationQueue(); queue.name = "DaBin.IsolatedPromiseProbe.reader"; queue.maxConcurrentOperationCount = 1
        for receiver in receivers {
            receiver.receivePromisedFiles(atDestination: destination, options: [:], operationQueue: queue) { url, error in
                events.record("receiver.callback " + (error?.localizedDescription ?? "nil"))
                events.complete(url, try? Data(contentsOf: url), error?.localizedDescription)
            }
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while events.snapshot().1.isEmpty && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        let observation = events.snapshot()
        let passed = written && receivers.count == 1 && observation.1.count == 1
            && observation.1[0].1 == bytes && observation.1[0].2 == nil
        let report: [String: Any] = ["case": caseName, "passed": passed, "privatePasteboard": true, "windows": 0,
            "receiverCount": receivers.count, "callbackCount": observation.1.count, "events": observation.0,
            "callbacks": observation.1.map { ["path": $0.0, "bytesExact": $0.1 == bytes, "error": $0.2 ?? ""] },
            "sourceBytesUnchanged": try Data(contentsOf: source) == bytes]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: root.appendingPathComponent("report.json"), options: .atomic)
        print("PROBE_RESULT: " + caseName + " passed=\(passed) callbacks=\(observation.1.count)")
        withExtendedLifetime(ownership) { }
        return passed
    }
}
