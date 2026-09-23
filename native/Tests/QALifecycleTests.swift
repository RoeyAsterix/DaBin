import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
private final class LifecycleNotificationClient: ReminderNotificationClient {
    var authorizationValue: ReminderAuthorization = .denied
    var permissionRequests = 0
    var requests: [String: ScheduledReminder] = [:]
    func authorization() async -> ReminderAuthorization { authorizationValue }
    func requestAuthorization() async throws -> Bool { permissionRequests += 1; return false }
    func pending() async -> [ScheduledReminder] { Array(requests.values) }
    func add(_ reminder: ScheduledReminder) async throws { requests[reminder.identifier] = reminder }
    func removePending(_ identifiers: [String]) { for id in identifiers { requests.removeValue(forKey: id) } }
    func removeDelivered(_ identifiers: [String]) { }
}

@main
struct QALifecycleTests {
    @MainActor private static var checks = 0
    @MainActor private static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        if try !value() { throw NSError(domain: "DaBinLifecycleTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    @MainActor private static func waitUntil(_ message: String, _ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !predicate() && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try expect(predicate(), message)
    }

    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinLifecycleTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root)
        let desired = Date().addingTimeInterval(3600)
        let capture = try store.createTask(text: "Synthetic lifecycle reminder", reminderAt: desired)
        let client = LifecycleNotificationClient()
        let reminders = ReminderService(store: store, client: client)
        let appEvents = NotificationCenter()
        let workspaceEvents = NotificationCenter()
        var runs = 0
        var active = 0
        var maximumActive = 0
        var blockNext = false
        var blocked: CheckedContinuation<Void, Never>?
        let lifecycle = ReminderLifecycle {
            runs += 1
            active += 1
            maximumActive = max(maximumActive, active)
            if blockNext {
                blockNext = false
                await withCheckedContinuation { blocked = $0 }
            }
            await reminders.reconcile()
            active -= 1
        }
        defer { lifecycle.stop() }
        lifecycle.start(applicationEvents: appEvents, workspaceEvents: workspaceEvents)
        try await waitUntil("Launch reconciliation finishes") { runs == 1 && active == 0 }
        try expect(capture.notificationState == "denied" && client.requests.isEmpty, "Launch respects denied notification permission")
        try expect(client.permissionRequests == 0, "Launch never presents a permission prompt")

        client.authorizationValue = .allowed
        appEvents.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        try await waitUntil("Returning from System Settings reconciles authorization") { client.requests.count == 1 && active == 0 }
        try expect(client.requests[ReminderService.identifier(capture.id)]?.date == desired, "Activation schedules the original future reminder after permission becomes allowed")
        try expect(client.permissionRequests == 0, "Activation never requests notification permission")

        client.authorizationValue = .denied
        workspaceEvents.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await waitUntil("Wake reconciles changed authorization") { client.requests.isEmpty && active == 0 }
        try expect(capture.notificationState == "denied", "Wake removes a pending request after permission is revoked")
        try expect(client.permissionRequests == 0, "Wake never requests notification permission")

        let beforeBurst = runs
        blockNext = true
        appEvents.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        try await waitUntil("Reconciliation fixture suspends") { blocked != nil }
        for _ in 0..<20 {
            appEvents.post(name: NSApplication.didBecomeActiveNotification, object: nil)
            workspaceEvents.post(name: NSWorkspace.didWakeNotification, object: nil)
        }
        // Let observer-delivery tasks reach the coalescer while the first run is suspended.
        try await Task.sleep(for: .milliseconds(50))
        try expect(runs == beforeBurst + 1, "A lifecycle burst does not start concurrent work")
        blocked?.resume(); blocked = nil
        try await waitUntil("One coalesced follow-up finishes") { runs == beforeBurst + 2 && active == 0 }
        try await Task.sleep(for: .milliseconds(50))
        try expect(runs == beforeBurst + 2 && maximumActive == 1, "Forty lifecycle events add only one follow-up with no overlap")

        let beforeDuplicateStart = runs
        lifecycle.start(applicationEvents: appEvents, workspaceEvents: workspaceEvents)
        try await Task.sleep(for: .milliseconds(30))
        try expect(runs == beforeDuplicateStart, "Starting twice does not duplicate observers or work")
        lifecycle.stop()
        appEvents.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        workspaceEvents.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(30))
        try expect(runs == beforeDuplicateStart, "Stopping removes both lifecycle observers")

        // A ready local preview is disposable: launch must pass it to process() so
        // a removed thumbnail is rebuilt from the unchanged managed original.
        let context = CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.45, green: 0.2, blue: 0.75, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        let bytes = NSMutableData()
        let destination = CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        try expect(CGImageDestinationFinalize(destination), "Synthetic local preview fixture encodes")
        let image = try await store.importData(bytes as Data, filename: "Lifecycle preview.png")
        let previews = PreviewService(store: store)
        previews.process([image])
        try await waitUntil("Initial image preview finishes") { image.previewState != "loading" }
        let thumbnail = try unwrap(store.previewURL(for: image), "A thumbnail was cached")
        try expect(image.previewState == "ready" && FileManager.default.fileExists(atPath: thumbnail.path), "Image has a ready local thumbnail")
        try FileManager.default.removeItem(at: thumbnail)
        let reopened = try CaptureStore(root: root)
        let reopenedImage = try unwrap(reopened.captures.first(where: { $0.id == image.id }), "Image survives relaunch")
        try expect(reopenedImage.previewState == "ready", "Metadata remains ready when disposable cache is removed")
        let relaunchedPreviews = PreviewService(store: reopened)
        relaunchedPreviews.process(reopened.captures)
        try await waitUntil("Relaunch recreates a missing thumbnail") {
            reopenedImage.previewState == "ready" && FileManager.default.fileExists(atPath: thumbnail.path)
        }
        try expect(try Data(contentsOf: reopened.managedURL(for: reopenedImage)!) == bytes as Data, "Thumbnail regeneration preserves original bytes")
        let modification = try thumbnail.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        relaunchedPreviews.process(reopened.captures)
        try await Task.sleep(for: .milliseconds(30))
        try expect(try thumbnail.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == modification,
                   "Intact ready thumbnail is not regenerated on another lifecycle pass")
        print("PASS: \(checks) lifecycle/cache checks; isolated event centers, store and fake notifications, no network.")
    }

    private static func unwrap<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw NSError(domain: "DaBinLifecycleTests", code: 2, userInfo: [NSLocalizedDescriptionKey: message]) }
        return value
    }
}
