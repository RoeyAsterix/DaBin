import Foundation

@MainActor
private final class ActionReminderClient: ReminderNotificationClient {
    var requests: [String: ScheduledReminder] = [:]
    var delivered: Set<String> = []
    var pauseAdd = false
    var addition: CheckedContinuation<Void, Never>?
    func authorization() async -> ReminderAuthorization { .allowed }
    func requestAuthorization() async throws -> Bool { fatalError("No real notification permission in QA") }
    func pending() async -> [ScheduledReminder] { Array(requests.values) }
    func add(_ reminder: ScheduledReminder) async throws {
        if pauseAdd { await withCheckedContinuation { addition = $0 } }
        requests[reminder.identifier] = reminder
    }
    func removePending(_ identifiers: [String]) { identifiers.forEach { requests.removeValue(forKey: $0) } }
    func removeDelivered(_ identifiers: [String]) { identifiers.forEach { delivered.remove($0) } }
    func resume() { pauseAdd = false; let callback = addition; addition = nil; callback?.resume() }
}

@main
struct CaptureActionTests {
    @MainActor private static var checks = 0
    @MainActor private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        if !condition() { throw NSError(domain: "CaptureActionTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    @MainActor private static func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try expect(condition(), "Asynchronous action completed before timeout")
    }

    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinCaptureActions-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "DaBinCaptureActions.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = try CaptureStore(root: root)
        let client = ActionReminderClient()
        let previews = PreviewService(store: store, defaults: defaults)
        let reminders = ReminderService(store: store, client: client)
        let state = AppState(store: store, previews: previews, reminders: reminders)
        let capture = try store.capture(text: "Fictional note with searchable detail")[0]
        let other = try store.createTask(text: "Keep unrelated task", reminderAt: Date().addingTimeInterval(7200))
        await reminders.saveReminder(for: other)
        try store.update(capture, comment: "Remember this context", reminderAt: Date().addingTimeInterval(3600), reminderTimeZoneID: TimeZone.current.identifier)
        await reminders.saveReminder(for: capture)
        let identifier = ReminderService.identifier(capture.id)
        client.delivered.insert(identifier)
        let original = CaptureSnapshot(capture)
        let revision = state.captureLayoutRevision
        state.toggleMinimized(capture)
        try expect(capture.isMinimized, "Minimize changes presentation")
        try expect(state.captureLayoutRevision == revision + 1, "A size change requests bottom-only panel transition")
        try expect(capture.capturedAt == original.capturedAt && capture.captureDay == original.captureDay && capture.comment == original.comment && capture.reminderAt == original.reminderAt,
                   "Minimize preserves receipt, content, comment and reminder")
        try expect(client.requests[identifier] != nil, "Minimize leaves a scheduled reminder active")
        try expect(state.dailyCaptures.contains { $0.id == capture.id }, "Minimized capture remains in Daily")
        state.query = "searchable detail"
        try expect(!state.searchGroups.isEmpty, "Hidden body remains searchable")
        state.openCapture(capture.id)
        try expect(state.selectedCapture === capture && state.route == .detail, "A minimized capture opens full detail")
        state.toggleMinimized(capture)
        try expect(!capture.isMinimized, "Expand restores full row")
        state.requestRemoval(capture)
        try expect(state.pendingRemoval === capture && store.captures.contains { $0.id == capture.id }, "Requesting removal only opens confirmation")
        state.pendingRemoval = nil
        try expect(store.captures.contains { $0.id == capture.id } && client.requests[identifier] != nil, "Cancelling confirmation preserves capture and reminder")
        state.selectedDraft?.comment = "An unsaved edit to discard with this capture"
        try expect(state.hasUnsavedDrafts, "Deletion fixture has an unsaved draft")
        await state.removeCapture(capture)
        try expect(state.route == .daily && state.selectedCapture == nil && state.selectedDraft == nil, "Removing open detail returns to its origin")
        try expect(!state.hasUnsavedDrafts, "Removed capture leaves no orphan unsaved draft")
        try expect(state.removingCaptureID == nil && state.pendingRemoval == nil, "Removal finishes UI progress state")
        try expect(!store.captures.contains { $0.id == capture.id } && state.searchGroups.isEmpty, "Removal clears board and contextual search")
        try expect(client.requests[identifier] == nil && !client.delivered.contains(identifier), "Removal clears pending and delivered reminders")
        try expect(client.requests[ReminderService.identifier(other.id)] != nil, "Other reminders remain untouched")
        try expect(state.status?.severity == .success, "Successful removal reports success")
        let savedCount = store.captures.count
        await state.removeCapture(capture)
        try expect(store.captures.count == savedCount, "Repeated stale removal is harmless")
        state.requestRemoval(capture)
        try expect(state.pendingRemoval == nil, "Deleted objects cannot reopen confirmation")

        let failed = try store.capture(text: "Retain capture after database failure")[0]
        previews.process([failed])
        store.removalFailureInjector = { stage in
            if stage == .beforeMetadataDelete { throw NSError(domain: "QAExpectedRemovalFailure", code: 1) }
        }
        state.openCapture(failed.id)
        await state.removeCapture(failed)
        try expect(store.captures.contains { $0 === failed } && state.route == .detail, "Failed removal preserves capture and open detail")
        try expect(state.status?.severity == .error && state.removingCaptureID == nil, "Failed removal reports actionable error and clears busy state")
        try expect(failed.previewState == "ready", "Failed removal restores preview processing")
        store.removalFailureInjector = nil

        let raced = try store.createTask(text: "Delete during delayed notification scheduling", reminderAt: Date().addingTimeInterval(7200))
        client.pauseAdd = true
        let schedule = Task { await reminders.saveReminder(for: raced) }
        try await waitUntil { client.addition != nil }
        let removal = Task { await state.removeCapture(raced) }
        try await waitUntil { !store.captures.contains { $0.id == raced.id } }
        try expect(state.removingCaptureID == raced.id, "Quit protection remains active until delayed notification cleanup finishes")
        client.resume()
        await schedule.value
        await removal.value
        try expect(client.requests[ReminderService.identifier(raced.id)] == nil, "Delayed scheduling cannot restore a deleted reminder")
        try expect(!store.captures.contains { $0.id == raced.id }, "Delayed scheduling cannot recreate a removed capture")
        try expect(state.removingCaptureID == nil, "Quit protection ends after removal and notification cleanup complete")
        let reopened = try CaptureStore(root: root)
        try expect(Set(reopened.captures.map(\.id)) == Set([other.id, failed.id]), "Only retained captures survive relaunch")
        print("PASS: \(checks) capture action checks; confirmation, minimize, search, draft cleanup and delayed reminder deletion in an isolated archive.")
    }
}
