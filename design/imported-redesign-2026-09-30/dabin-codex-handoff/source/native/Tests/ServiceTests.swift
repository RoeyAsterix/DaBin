import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
private final class FakeNotificationClient: ReminderNotificationClient {
    var authorizationValue: ReminderAuthorization = .undetermined
    var permit = false
    var permissionRequests = 0
    var requests: [String: ScheduledReminder] = [:]
    var additions: [ScheduledReminder] = []
    var removedDelivered: [String] = []
    var failAdd = false
    var blockNextAdd = false
    var blocked: CheckedContinuation<Void, Never>?

    func authorization() async -> ReminderAuthorization { authorizationValue }
    func requestAuthorization() async throws -> Bool {
        permissionRequests += 1
        authorizationValue = permit ? .allowed : .denied
        return permit
    }
    func pending() async -> [ScheduledReminder] { Array(requests.values) }
    func add(_ reminder: ScheduledReminder) async throws {
        if blockNextAdd {
            blockNextAdd = false
            await withCheckedContinuation { blocked = $0 }
        }
        if failAdd { throw NSError(domain: "FixtureNotificationFailure", code: 1) }
        additions.append(reminder)
        requests[reminder.identifier] = reminder
    }
    func removePending(_ identifiers: [String]) { for id in identifiers { requests.removeValue(forKey: id) } }
    func removeDelivered(_ identifiers: [String]) { removedDelivered.append(contentsOf: identifiers) }
    func unblock() { let continuation = blocked; blocked = nil; continuation?.resume() }
}

@MainActor
private final class PausedThumbnailWriter {
    var started = false
    var finished = false
    private var blockNext = true
    private var continuation: CheckedContinuation<Void, Never>?

    func write(_ png: Data, root: URL, id: UUID) async -> String? {
        if blockNext {
            blockNext = false
            started = true
            await withCheckedContinuation { continuation = $0 }
        }
        let result = await PreviewService.writeThumbnail(png, root: root, id: id)
        finished = true
        return result
    }

    func release() {
        let waiting = continuation
        continuation = nil
        waiting?.resume()
    }
}

@main struct ServiceTests {
    @MainActor static var checks = 0
    @MainActor static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        if !condition() { throw NSError(domain: "DaBinServiceTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    @MainActor static func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(8)
        while !predicate() && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try expect(predicate(), "Async operation completed within fixture deadline")
    }

    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinServiceTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root)
        let capture = try store.capture(text: "Service test private note")[0]
        let capturedAt = capture.capturedAt
        let capturedDay = capture.captureDay
        let original = capture.originalText
        let desired = Date().addingTimeInterval(3600)
        try store.update(capture, comment: "", reminderAt: desired, reminderTimeZoneID: "UTC")
        let fake = FakeNotificationClient()
        let reminders = ReminderService(store: store, client: fake)

        await reminders.reconcile()
        try expect(fake.permissionRequests == 0, "Launch reconciliation never requests notification permission")
        try expect(fake.requests.isEmpty && capture.notificationState == "pending", "Undetermined permission preserves desired reminder without scheduling")
        await reminders.saveReminder(for: capture)
        try expect(fake.permissionRequests == 1, "Explicit reminder save requests permission")
        try expect(capture.reminderAt == desired && capture.notificationState == "denied", "Denied permission retains saved reminder")

        fake.authorizationValue = .allowed
        await reminders.reconcile()
        try expect(fake.requests.count == 1 && capture.notificationState == "scheduled", "Authorization change schedules future reminder")
        let addCount = fake.additions.count
        await reminders.reconcile()
        try expect(fake.additions.count == addCount, "Identical revision reconciliation does not reschedule")

        let changed = desired.addingTimeInterval(1800)
        try store.update(capture, comment: "Comment", reminderAt: changed, reminderTimeZoneID: "UTC")
        fake.blockNextAdd = true
        let scheduling = Task { await reminders.saveReminder(for: capture) }
        try await waitUntil { fake.blocked != nil }
        let latest = changed.addingTimeInterval(1800)
        try store.update(capture, comment: "Comment", reminderAt: latest, reminderTimeZoneID: "UTC")
        fake.unblock()
        await scheduling.value
        let requestID = ReminderService.identifier(capture.id)
        try expect(fake.requests[requestID]?.date == latest && fake.requests[requestID]?.revision == capture.reminderRevision,
                   "An edit during async scheduling replaces the stale revision")

        try store.update(capture, comment: "Comment", reminderAt: latest.addingTimeInterval(1800), reminderTimeZoneID: "UTC")
        fake.blockNextAdd = true
        let staleSave = Task { await reminders.saveReminder(for: capture) }
        try await waitUntil { fake.blocked != nil }
        try store.update(capture, comment: "Comment", reminderAt: nil, reminderTimeZoneID: nil)
        let clear = Task { await reminders.clearForCapture(capture.id) }
        try await waitUntil { capture.reminderAt == nil }
        fake.unblock()
        await staleSave.value
        await clear.value
        try expect(fake.requests.isEmpty && capture.notificationState == "none", "Clear during scheduling cannot leave a stale notification")
        try expect(fake.removedDelivered.contains(requestID), "Clear removes delivered alerts")

        let recovered = desired.addingTimeInterval(120)
        try store.update(capture, comment: "Comment", reminderAt: recovered, reminderTimeZoneID: "UTC")
        await reminders.clearForCapture(capture.id)
        try expect(capture.reminderAt == recovered && fake.requests[requestID]?.date == recovered,
                   "Delayed clear honors a newer persisted reminder rather than erasing it")

        try store.update(capture, comment: "Comment", reminderAt: desired, reminderTimeZoneID: "UTC")
        fake.failAdd = true
        await reminders.saveReminder(for: capture)
        try expect(capture.reminderAt == desired && capture.notificationState == "failed", "Scheduler error preserves desired reminder")
        fake.failAdd = false
        try store.update(capture, comment: "Comment", reminderAt: Date().addingTimeInterval(-60), reminderTimeZoneID: "UTC")
        await reminders.reconcile()
        try expect(capture.notificationState == "past" && fake.requests.isEmpty, "Past reminders do not become catch-up alerts")
        try expect(capture.capturedAt == capturedAt && capture.captureDay == capturedDay && capture.originalText == original,
                   "Reminder operations preserve original and immutable capture stamp")

        let task = try store.createTask(text: "Send the studio brief", reminderAt: desired, reminderTimeZoneID: "UTC")
        let taskID = ReminderService.identifier(task.id)
        let taskReceipt = (task.capturedAt, task.captureDay, task.originalText)
        await reminders.saveReminder(for: task)
        try expect(fake.requests[taskID]?.date == desired, "New task schedules its optional reminder")
        let taskScheduledRevision = task.reminderRevision
        try store.setTaskCompleted(task, completed: true)
        let deliveredRemovalCount = fake.removedDelivered.count
        await reminders.clearForCapture(task.id)
        try expect(fake.requests[taskID] == nil && task.notificationState == "completed" && task.reminderAt == desired && task.reminderRevision > taskScheduledRevision, "Completion cancels a scheduled reminder without discarding its date")
        try expect(fake.removedDelivered.dropFirst(deliveredRemovalCount).contains(taskID), "Task completion also clears its already-delivered alert")
        fake.authorizationValue = .undetermined
        let requestsBeforeCompletedSave = fake.permissionRequests
        await reminders.saveReminder(for: task)
        try expect(fake.permissionRequests == requestsBeforeCompletedSave && fake.requests[taskID] == nil, "Completed tasks never request notification permission")
        // Completion takes precedence over both a retained future date and a now-past date.
        try store.update(task, comment: "Finished", reminderAt: Date().addingTimeInterval(-60), reminderTimeZoneID: "UTC")
        await reminders.reconcile()
        try expect(task.notificationState == "completed", "Completed historical reminders never become past or scheduled reminders")
        try store.setTaskCompleted(task, completed: false)
        await reminders.saveReminder(for: task)
        try expect(task.notificationState == "past" && fake.requests[taskID] == nil && fake.permissionRequests == requestsBeforeCompletedSave, "Reopening an overdue task does not send a catch-up alert")
        try store.update(task, comment: "Finished", reminderAt: desired, reminderTimeZoneID: "UTC")
        fake.authorizationValue = .allowed
        await reminders.saveReminder(for: task)
        try expect(fake.requests[taskID]?.revision == task.reminderRevision && fake.requests[taskID]?.date == desired, "Reopened task resumes a future reminder with its current revision")

        try store.update(task, comment: "Finished", reminderAt: desired.addingTimeInterval(120), reminderTimeZoneID: "UTC")
        fake.blockNextAdd = true
        let schedulingTask = Task { await reminders.saveReminder(for: task) }
        try await waitUntil { fake.blocked != nil }
        try store.setTaskCompleted(task, completed: true)
        let completingTask = Task { await reminders.clearForCapture(task.id) }
        fake.unblock()
        await schedulingTask.value
        await completingTask.value
        try expect(fake.requests[taskID] == nil && task.notificationState == "completed", "Completion while notification add is suspended removes the stale request")
        try store.setTaskCompleted(task, completed: false)
        // An older queued completion callback must read the reopened desired state.
        await reminders.clearForCapture(task.id)
        try expect(fake.requests[taskID]?.revision == task.reminderRevision, "Delayed completion synchronization honors an already-reopened task")
        try store.setTaskCompleted(task, completed: true)
        let relaunchedStore = try CaptureStore(root: root)
        let relaunchedReminders = ReminderService(store: relaunchedStore, client: fake)
        await relaunchedReminders.reconcile()
        try expect(fake.requests[taskID] == nil && relaunchedStore.captures.first(where: { $0.id == task.id })?.notificationState == "completed", "Launch reconciliation cancels a task completed before shutdown")
        try expect(task.capturedAt == taskReceipt.0 && task.captureDay == taskReceipt.1 && task.originalText == taskReceipt.2, "Reminder/completion races preserve task creation date and text")

        let preferences = UserDefaults.standard
        let oldPreference = preferences.object(forKey: PreviewService.linkPreviewPreference)
        defer {
            if let oldPreference { preferences.set(oldPreference, forKey: PreviewService.linkPreviewPreference) }
            else { preferences.removeObject(forKey: PreviewService.linkPreviewPreference) }
        }
        preferences.removeObject(forKey: PreviewService.linkPreviewPreference)
        let previews = PreviewService(store: store)
        try expect(!previews.enabled, "Website preview opt-in defaults off")
        let link = try store.capture(text: "https://example.invalid/private-path")[0]
        previews.process([link])
        try expect(link.previewState == "unavailable" && link.originalURL == "https://example.invalid/private-path", "Disabled website preview preserves saved URL without network")

        let context = CGContext(data: nil, width: 1200, height: 800, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.4, green: 0.2, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
        let bytes = NSMutableData()
        let destination = CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        try expect(CGImageDestinationFinalize(destination), "Local synthetic image fixture encodes")
        let picture = try await store.importData(bytes as Data, filename: "preview-fixture.png")
        let managedOriginal = store.managedURL(for: picture)!
        let originalBytes = try Data(contentsOf: managedOriginal)
        let captureCount = store.captures.count
        previews.process([picture])
        try await waitUntil { picture.previewState != "loading" }
        try expect(picture.previewState == "ready", "ImageIO generates a native image preview")
        let relativePath = picture.thumbnailRelativePath ?? ""
        try expect(relativePath.hasPrefix("Previews/") && !relativePath.hasPrefix("/"), "Thumbnail path is managed-store relative")
        let source = CGImageSourceCreateWithURL(root.appendingPathComponent(relativePath) as CFURL, nil)!
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)! as NSDictionary
        let width = (properties[kCGImagePropertyPixelWidth] as! NSNumber).intValue
        let height = (properties[kCGImagePropertyPixelHeight] as! NSNumber).intValue
        try expect(max(width, height) <= 600, "Preview is downsampled rather than a full-size decode")
        let remainingBytes = try Data(contentsOf: managedOriginal)
        try expect(remainingBytes == originalBytes && store.captures.count == captureCount, "Preview generation neither modifies nor recaptures original")

        // Exercise the queue's actual refresh decision without contacting a
        // website. Preferences are isolated from the app and other test suites.
        let suite = "DaBin.ServiceTests.PreviewRecovery.\(UUID().uuidString)"
        let isolatedDefaults = UserDefaults(suiteName: suite)!
        defer { isolatedDefaults.removePersistentDomain(forName: suite) }
        let recoveryPreviews = PreviewService(store: store, defaults: isolatedDefaults)
        link.previewState = "ready"
        link.previewError = nil
        link.title = "Previously fetched page"
        link.previewDescription = "Saved website metadata"
        link.thumbnailRelativePath = "Previews/\(link.id.uuidString)/thumbnail.png"
        try store.save(captures: [link])
        let linkCache = store.previewURL(for: link)!
        try expect(!FileManager.default.fileExists(atPath: linkCache.path), "Ready link fixture has lost its disposable image")
        try expect(!recoveryPreviews.needsPreview(for: link), "Missing website thumbnail never opts into network contact")
        recoveryPreviews.process([link])
        try expect(link.previewState == "ready" && link.previewDescription == "Saved website metadata",
                   "Disabled previews preserve already-saved link metadata after cache loss")
        isolatedDefaults.set(true, forKey: PreviewService.linkPreviewPreference)
        try expect(recoveryPreviews.needsPreview(for: link), "Enabled previews requeue a ready link whose old thumbnail is missing")
        try FileManager.default.createDirectory(at: linkCache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (bytes as Data).write(to: linkCache)
        try expect(!recoveryPreviews.needsPreview(for: link), "Ready link with an intact image does not fetch again")
        let linkModification = try linkCache.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        recoveryPreviews.process([link])
        let retainedLinkModification = try linkCache.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        try expect(link.previewState == "ready" && retainedLinkModification == linkModification,
                   "An intact ready link retains its cache without starting preview work")
        try FileManager.default.removeItem(at: linkCache)
        link.thumbnailRelativePath = nil
        try expect(!recoveryPreviews.needsPreview(for: link), "A valid metadata-only card does not fetch repeatedly")
        recoveryPreviews.process([link])
        try expect(link.previewState == "ready" && link.previewDescription == "Saved website metadata",
                   "Metadata-only link remains complete with website fetching enabled")
        try expect(!recoveryPreviews.needsPreview(for: picture), "Intact local image cache remains complete")
        try FileManager.default.removeItem(at: store.previewURL(for: picture)!)
        try expect(recoveryPreviews.needsPreview(for: picture), "Local image cache loss remains recoverable")
        isolatedDefaults.set(false, forKey: PreviewService.linkPreviewPreference)
        try expect(recoveryPreviews.needsPreview(for: picture), "Local cache recovery is independent of network permission")
        recoveryPreviews.process([picture])
        try await waitUntil { picture.previewState == "ready" && FileManager.default.fileExists(atPath: store.previewURL(for: picture)!.path) }
        let recoveredOriginalBytes = try Data(contentsOf: managedOriginal)
        try expect(recoveredOriginalBytes == originalBytes, "Recovering the image cache retains the exact original")

        let cancellingImage = try await store.importData(bytes as Data, filename: "cancelling-preview.png")
        let writer = PausedThumbnailWriter()
        let cancellablePreviews = PreviewService(store: store, defaults: isolatedDefaults) { png, root, id in
            await writer.write(png, root: root, id: id)
        }
        cancellablePreviews.process([cancellingImage])
        try await waitUntil { writer.started }
        var cancellationFinished = false
        let cancellation = Task { @MainActor in
            await cancellablePreviews.cancel(for: cancellingImage.id)
            cancellationFinished = true
        }
        try await Task.sleep(for: .milliseconds(20))
        try expect(!cancellationFinished, "Preview cancellation waits for in-flight thumbnail IO")
        // Settings or lifecycle work must not requeue this capture while its
        // first writer is being drained for a pending removal.
        cancellablePreviews.process([cancellingImage])
        writer.release()
        await cancellation.value
        let cancelledCache = root.appendingPathComponent("Previews/\(cancellingImage.id.uuidString)")
        try expect(writer.finished && FileManager.default.fileExists(atPath: cancelledCache.path),
                   "Cancellation drains thumbnail IO but retains files until removal commits")
        try expect(cancellingImage.previewState == "loading", "Cancelled preview cannot publish a stale ready update")
        cancellablePreviews.process([cancellingImage])
        try await waitUntil { cancellingImage.previewState == "ready" }
        try expect(store.previewURL(for: cancellingImage).map { FileManager.default.fileExists(atPath: $0.path) } == true,
                   "A capture can regenerate its preview after a failed removal resumes it")

        let removedImage = try await store.importData(bytes as Data, filename: "removed-during-preview.png")
        let removalWriter = PausedThumbnailWriter()
        let removalPreviews = PreviewService(store: store, defaults: isolatedDefaults) { png, root, id in
            await removalWriter.write(png, root: root, id: id)
        }
        removalPreviews.process([removedImage])
        try await waitUntil { removalWriter.started }
        // Bypass the normal cancellation order deliberately to verify the
        // defensive post-write membership guard against a removal race.
        _ = try store.remove(removedImage)
        removalWriter.release()
        let removedCache = root.appendingPathComponent("Previews/\(removedImage.id.uuidString)")
        try await waitUntil { removalWriter.finished && !FileManager.default.fileExists(atPath: removedCache.path) }
        try expect(!store.captures.contains(where: { $0.id == removedImage.id }),
                   "A thumbnail finishing after removal never resurrects the capture in memory")
        let removalReopen = try CaptureStore(root: root)
        try expect(!removalReopen.captures.contains(where: { $0.id == removedImage.id }),
                   "A thumbnail finishing after removal never recreates its durable metadata")
        try expect(!FileManager.default.fileExists(atPath: removedCache.path),
                   "A thumbnail written after removal is cleaned instead of leaving orphan preview bytes")
        removalPreviews.process([removedImage])
        try await Task.sleep(for: .milliseconds(20))
        try expect(!FileManager.default.fileExists(atPath: removedCache.path),
                   "A stale capture object cannot restart preview work after removal")
        print("PASS: \(checks) service checks (isolated store, fake notifications, no network).")
    }
}
