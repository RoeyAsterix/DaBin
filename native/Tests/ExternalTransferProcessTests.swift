import AppKit
import CryptoKit
import Darwin
import Foundation
import UniformTypeIdentifiers

private struct ExternalTransferManifest: Codable {
    struct Item: Codable {
        let kind: String
        let text: String?
        let fileURL: URL?
        let imageType: String?
        let byteCount: Int?
        let sha256: String?
    }
    let producerPID: Int32
    let pasteboardName: String
    let items: [Item]
}

private struct ExternalTransferReport: Codable {
    let consumerPID: Int32
    let checks: Int
    let itemCount: Int
    let promisedImageReads: Int
    let publicTypes: [[String]]
}

/// A separate consumer reads the production writers through a uniquely named
/// native pasteboard. This tests cross-process data delivery, not WindowServer
/// dragging, sandbox extensions, browser behavior, or physical drop completion.
/// Both processes use fictional local files and never write the general board.
@main @MainActor private final class ExternalTransferProcessTests: NSObject, NSApplicationDelegate {
    private static let fixturePrefix = "DaBinExternalTransferQA-"
    private static let pasteboardPrefix = "DaBin.ExternalTransferQA."
    private static var checks = 0
    private var result: Int32 = 0

    static func main() {
        setbuf(stdout, nil)
        if CommandLine.arguments.dropFirst().first == "--consumer" {
            // A stalled owner cannot leave an orphaned consumer indefinitely.
            alarm(20)
            do { try consume(); alarm(0); exit(0) }
            catch { fputs("External consumer failed: \(error)\n", stderr); exit(1) }
        }
        let app = NSApplication.shared
        let delegate = ExternalTransferProcessTests()
        app.setActivationPolicy(.prohibited)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        exit(delegate.result)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await Self.produce() }
            catch { result = 1; fputs("External transfer process QA failed: \(error)\n", stderr) }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "ExternalTransferProcessTests", code: checks,
                userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        guard try value() else { throw failure(message) }
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func syntheticImage(_ format: NSBitmapImageRep.FileType) throws -> Data {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 3,
            bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let bytes = bitmap.bitmapData else {
            throw failure("Cannot allocate the fictional image fixture")
        }
        for y in 0..<3 {
            for x in 0..<4 {
                let offset = y * bitmap.bytesPerRow + x * 3
                bytes[offset] = UInt8(30 + x * 45)
                bytes[offset + 1] = UInt8(40 + y * 70)
                bytes[offset + 2] = 170
            }
        }
        guard let data = bitmap.representation(using: format, properties: [:]) else {
            throw failure("Cannot encode the fictional image fixture")
        }
        return data
    }

    private static func produce() async throws {
        let clipboardRevision = NSPasteboard.general.changeCount
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent(fixturePrefix + UUID().uuidString,
                                                                   isDirectory: true)
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }
        let store = try CaptureStore(root: root.appendingPathComponent("archive", isDirectory: true))
        defer { store.cancelArchiveRepair() }
        let exactText = "  Fictional note: café, שלום, 日本語, 👩🏽‍💻.\nSecond line\r\nThird line.  "
        let exactTask = "Fictional task — résumé\nKeep this full task body."
        let exactURL = "https://example.invalid/fixture?q=caf%C3%A9&mode=qa#second-part"
        let note = try store.capture(text: exactText)[0]
        let task = try store.createTask(text: exactTask)
        let link = try store.capture(text: exactURL)[0]
        let fixtures: [(String, Data)] = [
            ("Fictional-colors.png", try syntheticImage(.png)),
            ("Fictional-colors.jpg", try syntheticImage(.jpeg)),
            ("Fictional-document.bin", Data([0, 1, 2, 127, 128, 254, 255]) + Data("\nFictional bytes\n".utf8))
        ]
        var imported: [Capture] = []
        var inputHashes: [URL: String] = [:]
        for (name, bytes) in fixtures {
            let source = root.appendingPathComponent(name)
            try bytes.write(to: source)
            inputHashes[source] = hash(bytes)
            imported.append(try await store.importFile(source))
        }
        // Interleave types so a consumer cannot pass by grouping all files/text.
        let captures = [note, imported[0], link, imported[2], imported[1], task]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let snapshots = try captures.map { try encoder.encode(CaptureSnapshot($0)) }
        var managedHashes: [URL: String] = [:]
        let expected: [ExternalTransferManifest.Item] = try captures.map { capture in
            if let file = store.managedURL(for: capture) {
                let bytes = try Data(contentsOf: file)
                managedHashes[file] = hash(bytes)
                let type = UTType(filenameExtension: file.pathExtension)
                return .init(kind: "file", text: nil, fileURL: file,
                    imageType: type?.conforms(to: .image) == true ? type?.identifier : nil,
                    byteCount: bytes.count, sha256: hash(bytes))
            }
            if capture === link {
                return .init(kind: "url", text: exactURL, fileURL: nil, imageType: nil, byteCount: nil, sha256: nil)
            }
            return .init(kind: "text", text: capture === note ? exactText : exactTask,
                         fileURL: nil, imageType: nil, byteCount: nil, sha256: nil)
        }
        let pasteboard = NSPasteboard(name: .init(pasteboardPrefix + UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        let writers = try ExplorerTransfer.pasteboardWriters(for: captures, store: store)
        defer { withExtendedLifetime(writers) {} }
        try expect(writers.count == expected.count, "Production emits one native writer per selected capture")
        for (writer, item) in zip(writers, expected) {
            if let imageType = item.imageType {
                try expect(writer.writingOptions?(forType: .init(imageType), pasteboard: pasteboard) == .promised,
                           "Production defers original image bytes until a receiving process requests them")
            }
        }
        try expect(pasteboard.writeObjects(writers), "Private pasteboard accepts the actual production writers")
        // No image data(forType:) or property-list read occurs in the producer.
        let manifest = ExternalTransferManifest(producerPID: getpid(), pasteboardName: pasteboard.name.rawValue,
                                                items: expected)
        let manifestURL = root.appendingPathComponent("manifest.json")
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
        let logURL = root.appendingPathComponent("consumer.log")
        try Data().write(to: logURL)
        let log = try FileHandle(forWritingTo: logURL)
        defer { try? log.close() }
        let child = Process()
        child.executableURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        child.arguments = ["--consumer", manifestURL.path]
        child.standardOutput = log
        child.standardError = log
        defer {
            // Only the exact child launched here can be signalled, never a
            // process discovered by name or another app's window/process.
            if child.isRunning { child.terminate(); _ = kill(child.processIdentifier, SIGKILL) }
        }
        try child.run()
        try expect(child.processIdentifier != getpid(), "The receiving process has a distinct process ID")
        let deadline = Date().addingTimeInterval(15)
        while child.isRunning && Date() < deadline {
            // Yield MainActor so AppKit can service promised pasteboard data.
            // waitUntilExit() here would deadlock a cross-process image request.
            try await Task.sleep(for: .milliseconds(20))
        }
        if child.isRunning {
            child.terminate()
            let grace = Date().addingTimeInterval(1)
            while child.isRunning && Date() < grace { try await Task.sleep(for: .milliseconds(20)) }
            if child.isRunning { _ = kill(child.processIdentifier, SIGKILL) }
            throw failure("Consumer exceeded its 15-second deadline; its owned process was stopped")
        }
        let output = String(decoding: try Data(contentsOf: logURL).prefix(16_384), as: UTF8.self)
        try expect(child.terminationReason == .exit && child.terminationStatus == 0,
                   "Separate consumer completed successfully: \(output)")
        let report = try JSONDecoder().decode(ExternalTransferReport.self,
            from: Data(contentsOf: root.appendingPathComponent("consumer-report.json")))
        try expect(report.consumerPID == child.processIdentifier && report.consumerPID != getpid(),
                   "Only the launched external consumer produced the report")
        try expect(report.itemCount == captures.count && report.promisedImageReads == 2 && report.checks > 0,
                   "The consumer checked the complete mixed selection and both original image encodings")
        for (capture, snapshot) in zip(captures, snapshots) {
            try expect(try encoder.encode(CaptureSnapshot(capture)) == snapshot,
                       "Cross-process reads preserve every capture record")
        }
        for (file, expectedHash) in inputHashes.merging(managedHashes, uniquingKeysWith: { first, _ in first }) {
            try expect(try hash(Data(contentsOf: file)) == expectedHash,
                       "Cross-process reads preserve fixture input and saved-original hashes")
        }
        try expect(NSPasteboard.general.changeCount == clipboardRevision,
                   "Neither process replaces the general clipboard")
        print("PASS: \(checks + report.checks) external transfer process checks; \(captures.count) mixed production items, exact Unicode text/URL, PNG/JPEG promised bytes and file hashes. Cross-process data availability only; physical drops, sandboxed destinations and browsers are not exercised.")
    }

    private static func consume() throws {
        guard CommandLine.arguments.count == 3 else { throw failure("Consumer requires exactly one fixture manifest") }
        let manifestURL = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL
        let root = manifestURL.deletingLastPathComponent().resolvingSymlinksInPath()
        let suffix = String(root.lastPathComponent.dropFirst(fixturePrefix.count))
        guard manifestURL.lastPathComponent == "manifest.json", root.lastPathComponent.hasPrefix(fixturePrefix),
              UUID(uuidString: suffix) != nil,
              root.deletingLastPathComponent() == FileManager.default.temporaryDirectory.resolvingSymlinksInPath() else {
            throw failure("Consumer only reads this test's UUID-scoped temporary fixture")
        }
        let manifest = try JSONDecoder().decode(ExternalTransferManifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.producerPID == getppid(), manifest.pasteboardName.hasPrefix(pasteboardPrefix),
              UUID(uuidString: String(manifest.pasteboardName.dropFirst(pasteboardPrefix.count))) != nil else {
            throw failure("Consumer requires its producer's uniquely named private pasteboard")
        }
        let clipboardRevision = NSPasteboard.general.changeCount
        let pasteboard = NSPasteboard(name: .init(manifest.pasteboardName))
        let items = pasteboard.pasteboardItems ?? []
        try expect(items.count == manifest.items.count, "External process sees every native item in the mixed selection")
        var promisedReads = 0
        for (index, pair) in zip(items, manifest.items).enumerated() {
            let (item, expected) = pair
            switch expected.kind {
            case "text":
                try expect(item.string(forType: .string) == expected.text,
                           "External item \(index) retains exact multiline Unicode text in selection order")
                try expect(item.string(forType: .fileURL) == nil, "Plain text is not replaced with an archive filename")
            case "url":
                try expect(item.string(forType: .URL) == expected.text, "External link preserves URL query and fragment")
                try expect(item.string(forType: .string) == expected.text, "External link also supplies exact plain text")
            case "file":
                guard let expectedURL = expected.fileURL,
                      let raw = item.string(forType: .fileURL), let url = URL(string: raw), url.isFileURL else {
                    throw failure("External file item \(index) has no native file URL")
                }
                try expect(url == expectedURL, "External item \(index) resolves the saved original in selection order")
                guard url.resolvingSymlinksInPath().path.hasPrefix(root.path + "/") else {
                    throw failure("Consumer refuses files outside its synthetic fixture")
                }
                let bytes = try Data(contentsOf: url)
                try expect(bytes.count == expected.byteCount && hash(bytes) == expected.sha256,
                           "External file reader receives the saved original byte count and SHA-256")
                if let type = expected.imageType {
                    try expect(item.types.contains(.init(type)), "Original image encoding is advertised to the other process")
                    guard let promised = item.data(forType: .init(type)) else {
                        throw failure("External process could not materialize promised \(type) bytes")
                    }
                    promisedReads += 1
                    try expect(promised == bytes && hash(promised) == expected.sha256,
                               "External promised image data exactly matches the saved original encoding")
                }
            default: throw failure("Unsupported synthetic manifest kind")
            }
        }
        let fileReaders = pasteboard.readObjects(forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        try expect(fileReaders == manifest.items.compactMap(\.fileURL),
                   "Native NSURL readers in the external process preserve file selection order")
        try expect(NSPasteboard.general.changeCount == clipboardRevision, "External reads leave the general clipboard unchanged")
        let report = ExternalTransferReport(consumerPID: getpid(), checks: checks, itemCount: items.count,
            promisedImageReads: promisedReads, publicTypes: items.map { $0.types.map(\.rawValue).filter { !$0.hasPrefix("com.dabin.") } })
        try JSONEncoder().encode(report).write(to: root.appendingPathComponent("consumer-report.json"), options: .atomic)
    }
}
