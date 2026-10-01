import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

private final class RequestProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var starts = 0
    private var stops = 0
    private var callback: (@Sendable (String) -> Void)?
    let gate: DispatchSemaphore?
    let callbackDuringStop: Bool
    init(blockStart: Bool = false, callbackDuringStop: Bool = false) {
        gate = blockStart ? DispatchSemaphore(value: 0) : nil
        self.callbackDuringStop = callbackDuringStop
    }
    var counts: (started: Int, stopped: Int) {
        lock.lock(); defer { lock.unlock() }; return (starts, stops)
    }
    func start(_ callback: @escaping @Sendable (String) -> Void) -> @Sendable () -> Void {
        lock.lock(); starts += 1; self.callback = callback; lock.unlock()
        gate?.wait()
        return { [self] in
            lock.lock(); stops += 1; let callback = self.callback; lock.unlock()
            if callbackDuringStop { callback?("provider cancellation callback") }
        }
    }
    func finish(_ value: String) {
        lock.lock(); let callback = self.callback; lock.unlock(); callback?(value)
    }
}

@MainActor private final class ShutdownWriter {
    private var holds: [CheckedContinuation<Void, Never>] = []
    var started: [UUID] = []
    var completed: [UUID] = []
    func write(_ data: Data, root: URL, id: UUID) async -> String? {
        started.append(id)
        await withCheckedContinuation { holds.append($0) }
        let result = await PreviewService.writeThumbnail(data, root: root, id: id)
        completed.append(id)
        return result
    }
    func release() { let pending = holds; holds.removeAll(); pending.forEach { $0.resume() } }
}

@main @MainActor struct PreviewLifecycleTests {
    private static var checks = 0
    private static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        if try !value() { throw NSError(domain: "PreviewLifecycleTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    private static func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try expect(condition(), "Asynchronous fixture completed without timing out")
    }
    private static func request(_ probe: RequestProbe, timeout: TimeInterval = 2) async -> String {
        await PreviewRequest.perform(timeout: timeout, timeoutValue: "timeout", cancelledValue: "cancelled") { probe.start($0) }
    }

    static func main() async throws {
        try await bridgeChecks()
        try await directoryChecks()
        try await shutdownChecks()
        print("PASS: \(checks) preview cancellation/shutdown checks; isolated callbacks, preferences and archive only")
    }

    private static func directoryChecks() async throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("DaBinPreviewDirectories-\(UUID())")
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }
        let archive = DailyArchive(root: root)
        for round in 0..<8 {
            let created = try await withThrowingTaskGroup(of: URL.self) { group in
                for worker in 0..<24 {
                    group.addTask { try archive.ensureDirectory("Parent\(round)/Shared/Preview\(worker)") }
                }
                var result: [URL] = []
                for try await url in group { result.append(url) }
                return result
            }
            try expect(created.count == 24 && created.allSatisfy { files.fileExists(atPath: $0.path) },
                       "Concurrent preview writers safely share newly-created parents in round \(round)")
        }
        let outside = root.appendingPathComponent("outside")
        try files.createDirectory(at: outside, withIntermediateDirectories: true)
        try files.createSymbolicLink(at: root.appendingPathComponent("UnsafeLink"), withDestinationURL: outside)
        var rejectedLink = false
        do { try archive.ensureDirectory("UnsafeLink/Preview") } catch { rejectedLink = true }
        try expect(rejectedLink && !files.fileExists(atPath: outside.appendingPathComponent("Preview").path),
                   "Concurrent-directory tolerance never follows a symlink parent")
        try Data("Keep me".utf8).write(to: root.appendingPathComponent("BlockingFile"))
        var rejectedFile = false
        do { try archive.ensureDirectory("BlockingFile/Preview") } catch { rejectedFile = true }
        try expect(rejectedFile && (try Data(contentsOf: root.appendingPathComponent("BlockingFile"))) == Data("Keep me".utf8),
                   "Concurrent-directory tolerance preserves a conflicting regular file")
    }

    private static func bridgeChecks() async throws {
        let normal = RequestProbe()
        let work = Task { await request(normal, timeout: 0.03) }
        try await waitUntil { normal.counts.started == 1 }
        normal.finish("ready")
        let normalResult = await work.value
        try expect(normalResult == "ready", "Successful provider result is returned")
        normal.finish("duplicate")
        try await Task.sleep(for: .milliseconds(60))
        try expect(normal.counts.stopped == 0, "Normal completion cancels the timeout without canceling the successful provider")

        let preCancelled = RequestProbe()
        let beforeStart = Task { await request(preCancelled) }
        beforeStart.cancel()
        let beforeStartResult = await beforeStart.value
        try expect(beforeStartResult == "cancelled", "Cancellation before provider startup returns promptly")
        try expect(preCancelled.counts.started == 0 && preCancelled.counts.stopped == 0,
                   "An already-canceled request never starts provider work")

        let inflight = RequestProbe(callbackDuringStop: true)
        let cancelling = Task { await request(inflight) }
        try await waitUntil { inflight.counts.started == 1 }
        let startedCancel = Date()
        cancelling.cancel()
        let inflightResult = await cancelling.value
        try expect(inflightResult == "cancelled", "In-flight cancellation wins over its synchronous provider callback")
        try expect(Date().timeIntervalSince(startedCancel) < 0.5 && inflight.counts.stopped == 1,
                   "Cancellation stops native provider promptly instead of waiting for its timeout")
        inflight.finish("late ready")
        cancelling.cancel()
        try expect(inflight.counts.stopped == 1, "Late completion and repeated task cancellation do not stop/resume twice")

        let timed = RequestProbe()
        let timedResult = await request(timed, timeout: 0.02)
        try expect(timedResult == "timeout", "Unresponsive provider gets a bounded timeout result")
        try expect(timed.counts.stopped == 1, "Timeout cancels provider work exactly once")
        timed.finish("too late")

        let duringStart = RequestProbe(blockStart: true)
        let blocked = Task.detached {
            await PreviewRequest.perform(timeout: 2, timeoutValue: "timeout", cancelledValue: "cancelled") { duringStart.start($0) }
        }
        try await waitUntil { duringStart.counts.started == 1 }
        blocked.cancel()
        duringStart.gate?.signal()
        let blockedResult = await blocked.value
        try expect(blockedResult == "cancelled", "Cancellation during provider registration returns the cancellation result")
        try expect(duringStart.counts.stopped == 1, "A stop handler registered after cancellation is invoked once")

        for index in 0..<30 {
            let probe = RequestProbe()
            let task = Task { await request(probe) }
            try await waitUntil { probe.counts.started == 1 }
            DispatchQueue.global(qos: .utility).async { probe.finish("ready") }
            task.cancel()
            let value = await task.value
            try expect(["ready", "cancelled"].contains(value), "Completion/cancellation race \(index) returns one valid result")
            try expect(probe.counts.stopped <= 1, "Completion/cancellation race \(index) never cancels twice")
        }
    }

    private static func shutdownChecks() async throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("DaBinPreviewShutdown-\(UUID())")
        let suite = "DaBin.PreviewShutdown.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? files.removeItem(at: root); defaults.removePersistentDomain(forName: suite) }
        let store = try CaptureStore(root: root)
        let data = png()
        var captures: [Capture] = []
        for index in 0..<3 { captures.append(try await store.importData(data, filename: "Fixture \(index).png")) }
        let writer = ShutdownWriter()
        let previews = PreviewService(store: store, defaults: defaults) { data, root, id in
            await writer.write(data, root: root, id: id)
        }
        previews.process(captures)
        try await waitUntil { writer.started.count == 2 }
        let sidecars = try captures.map { try Data(contentsOf: store.archiveURL(for: $0)!.appendingPathComponent("Capture.json")) }
        previews.shutdown()
        previews.shutdown()
        previews.enabled = true
        previews.cancelNetwork()
        previews.process(captures)
        try expect(defaults.object(forKey: PreviewService.linkPreviewPreference) == nil, "Shutdown never changes preview consent preferences")
        writer.release()
        try await waitUntil { writer.completed.count == 2 }
        try await Task.sleep(for: .milliseconds(40))
        try expect(writer.started.count == 2, "Shutdown drops queued preview work and refuses restart")
        try expect(captures.allSatisfy { $0.previewState == "loading" && $0.thumbnailRelativePath == nil },
                   "Late thumbnail IO cannot publish metadata after shutdown")
        for (index, capture) in captures.enumerated() {
            try expect(try Data(contentsOf: store.archiveURL(for: capture)!.appendingPathComponent("Capture.json")) == sidecars[index],
                       "Shutdown leaves capture \(index) metadata unchanged")
            try expect(try Data(contentsOf: store.managedURL(for: capture)!) == data, "Shutdown preserves original \(index)")
        }
        for id in writer.completed {
            try expect(files.fileExists(atPath: root.appendingPathComponent("Previews/\(id)/thumbnail.png").path),
                       "Shutdown preserves already-written cache bytes")
        }
        let newer = try await store.importData(data, filename: "After stop.png")
        previews.process([newer])
        try expect(newer.previewState == "idle" && writer.started.count == 2, "Stopped service does not accept newly supplied captures")
        let fresh = PreviewService(store: store, defaults: defaults)
        fresh.process(captures)
        try await waitUntil { captures.allSatisfy { $0.previewState == "ready" } }
        try expect(captures.allSatisfy { store.previewURL(for: $0) != nil }, "Fresh service resumes unfinished previews after a later launch")
        fresh.shutdown()
    }

    private static func png() -> Data {
        let context = CGContext(data: nil, width: 32, height: 24, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.4, green: 0.2, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
