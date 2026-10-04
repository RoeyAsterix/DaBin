import AppKit
import Foundation

/// Injected clocks/event centers and temporary archives exercise due monitoring
/// without notification permission, the user's store, or visible robot windows.
@main struct ReminderAlertCoordinatorTests {
    @MainActor private static var checks = 0
    private static let base = Date(timeIntervalSince1970: 1_700_000_000)
    @MainActor private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard condition() else { throw NSError(domain: "ReminderAlertCoordinatorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    @MainActor private static func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !predicate(), Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try expect(predicate(), "The synthetic event was handled before the fixture deadline")
    }
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinReminderAlertTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try await scheduled(root.appendingPathComponent("Scheduled"))
        try await lifecycle(root.appendingPathComponent("Lifecycle"))
        try focusRestart(root.appendingPathComponent("Focus"))
        print("PASS: \(checks) reminder alert coordinator checks; scheduled delivery, wake/clock refresh, occurrence identity, filtering, restart and durable focus receipts.")
    }

    @MainActor private static func scheduled(_ root: URL) async throws {
        let store = try CaptureStore(root: root)
        let note = try store.createNote(text: "Scheduled fixture")
        let deadline = Date().addingTimeInterval(0.2)
        try store.update(note, comment: "", reminderAt: deadline, reminderTimeZoneID: "UTC")
        var receipts: [TaskTimerCompletion] = []
        var callbacks = 0
        let coordinator = ReminderAlertCoordinator(store: store)
        defer { coordinator.stop() }
        coordinator.onAlertsChanged = { value, _ in receipts = value; callbacks += 1 }
        coordinator.start(applicationEvents: NotificationCenter(), workspaceEvents: NotificationCenter())
        try expect(receipts.isEmpty && callbacks == 1, "A future reminder schedules a wakeup without showing an early alert")
        try await waitUntil { receipts.count == 1 }
        try expect(receipts[0].taskID == note.id && receipts[0].dueAt == deadline, "The nearest timer publishes the exact due occurrence")
        try expect(note.reminderAcknowledgment == nil, "Passive presentation never acknowledges an alert")
        let count = callbacks
        coordinator.stop()
        coordinator.reconcile()
        try await Task.sleep(for: .milliseconds(80))
        try expect(callbacks == count && !coordinator.isStarted, "Stop immediately disables scheduled work and presentation callbacks")
    }

    @MainActor private static func lifecycle(_ root: URL) async throws {
        let store = try CaptureStore(root: root)
        let first = try store.createNote(text: "Older reminder", at: base)
        let second = try store.createTask(text: "Later reminder", at: base)
        let third = try store.createTask(text: "Completed reminder", at: base)
        for (capture, offset) in [(first, 5.0), (second, 10.0), (third, 1.0)] {
            try store.update(capture, comment: "Context stays", reminderAt: base.addingTimeInterval(offset), reminderTimeZoneID: "UTC")
        }
        try store.setTaskCompleted(third, completed: true, at: base)
        var clock = base
        var receipts: [TaskTimerCompletion] = []
        var active = Set<UUID>()
        var callbacks = 0
        let appEvents = NotificationCenter(), workspaceEvents = NotificationCenter()
        let coordinator = ReminderAlertCoordinator(store: store, now: { clock })
        defer { coordinator.stop() }
        coordinator.onAlertsChanged = { values, ids in receipts = values; active = ids; callbacks += 1 }
        coordinator.start(applicationEvents: appEvents, workspaceEvents: workspaceEvents)
        coordinator.start(applicationEvents: appEvents, workspaceEvents: workspaceEvents)
        try expect(callbacks == 1 && receipts.isEmpty, "Starting twice installs a single monitoring lifecycle")
        try expect(active == Set([first.id, second.id]), "Completed tasks are excluded from the active presentation set")
        clock = base.addingTimeInterval(8)
        workspaceEvents.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await waitUntil { receipts.count == 1 }
        let firstReceipt = receipts[0]
        try expect(firstReceipt.taskID == first.id && firstReceipt.reminderRevision == first.reminderRevision, "Wake restores the overdue reminder's exact revision")
        coordinator.reconcile()
        try expect(receipts == [firstReceipt], "Repeated reconciliation reuses the same receipt identity")
        clock = base.addingTimeInterval(12)
        appEvents.post(name: Notification.Name.NSSystemClockDidChange, object: nil)
        try await waitUntil { receipts.count == 2 }
        try expect(receipts.map(\.taskID) == [first.id, second.id], "Clock changes reveal every due alert in chronological order")
        try expect(ReminderAlertCoordinator.receiptID(captureID: first.id, revision: first.reminderRevision, date: first.reminderAt!) == firstReceipt.id,
                   "Receipt identity is stable for the same persisted occurrence")
        let oldToken = first.reminderOccurrence!
        try store.update(first, comment: first.comment, reminderAt: base.addingTimeInterval(6), reminderTimeZoneID: "UTC")
        coordinator.reconcile()
        let rescheduled = receipts.first { $0.taskID == first.id }!
        try expect(rescheduled.id != firstReceipt.id && rescheduled.reminderRevision != firstReceipt.reminderRevision,
                   "Rescheduling produces a new receipt rather than reusing an acknowledged identity")
        _ = try store.acknowledgeReminders([oldToken], at: clock)
        coordinator.reconcile()
        try expect(receipts.contains { $0.id == rescheduled.id }, "An old popup cannot silence a newer reminder")
        _ = try store.acknowledgeReminders([first.reminderOccurrence!], at: clock)
        coordinator.reconcile()
        try expect(receipts.map(\.taskID) == [second.id], "Acknowledging removes only the matched occurrence")
        coordinator.stop()
        let reopened = try CaptureStore(root: root)
        let restart = ReminderAlertCoordinator(store: reopened, now: { clock })
        defer { restart.stop() }
        restart.onAlertsChanged = { values, ids in receipts = values; active = ids }
        restart.start(applicationEvents: NotificationCenter(), workspaceEvents: NotificationCenter())
        try expect(receipts.map(\.taskID) == [second.id], "Restart restores unacknowledged overdue reminders without repeating acknowledged ones")
        let current = reopened.captures.first { $0.id == second.id }!
        try reopened.moveToTrash(current)
        restart.reconcile()
        try expect(receipts.isEmpty && !active.contains(second.id), "Removing a capture suppresses its pending robot alert")
        let before = callbacks
        appEvents.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        workspaceEvents.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(80))
        try expect(callbacks == before, "Stopped coordinators ignore later application and workspace events")
    }

    @MainActor private static func focusRestart(_ root: URL) throws {
        let store = try CaptureStore(root: root)
        let task = try store.createTask(text: "Synthetic focus task", at: base)
        try store.setTaskFocus(task, session: TaskFocusSession(remainingSeconds: 60, endAt: base.addingTimeInterval(60)), durationMinutes: 1)
        let focus = TaskFocusCoordinator(store: store)
        defer { focus.shutdown() }
        focus.reconcile(at: base.addingTimeInterval(65))
        let session = task.taskPlanning!.focusSession!
        try expect(session.completedAlertID != nil && session.completedAt == base.addingTimeInterval(60) && session.acknowledgedAt == nil,
                   "Focus expiry creates a durable unacknowledged occurrence at its deadline")
        let reopened = try CaptureStore(root: root)
        let restored = reopened.captures[0]
        var receipts: [TaskTimerCompletion] = []
        var focusClock = base.addingTimeInterval(70)
        let coordinator = ReminderAlertCoordinator(store: reopened, now: { focusClock })
        defer { coordinator.stop() }
        coordinator.onAlertsChanged = { values, _ in receipts = values }
        coordinator.start(applicationEvents: NotificationCenter(), workspaceEvents: NotificationCenter())
        try expect(receipts.count == 1 && receipts[0].id == session.completedAlertID && receipts[0].reminderRevision == nil,
                   "Restart restores the exact completed focus receipt without inventing a reminder revision")
        focusClock = base.addingTimeInterval(59)
        coordinator.reconcile()
        try expect(receipts.isEmpty, "A backwards clock defers future focus completion rather than presenting an unacknowledgeable receipt")
        focusClock = base.addingTimeInterval(70)
        coordinator.reconcile()
        try expect(receipts.count == 1, "Focus completion returns when the clock reaches its persisted deadline")
        let token = restored.focusOccurrence!
        reopened.failureInjector = { if $0 == .beforeMetadataSave { throw CaptureStoreError.importVerificationFailed } }
        var failed = false
        do { _ = try reopened.acknowledgeAlerts(reminders: [], focus: [token], at: base.addingTimeInterval(70)) } catch { failed = true }
        coordinator.reconcile()
        try expect(failed && receipts.count == 1 && restored.taskPlanning?.focusSession?.acknowledgedAt == nil,
                   "A failed acknowledgment leaves the persisted focus occurrence visible for retry")
        reopened.failureInjector = nil
        _ = try reopened.acknowledgeAlerts(reminders: [], focus: [token], at: base.addingTimeInterval(70))
        coordinator.reconcile()
        try expect(receipts.isEmpty && !restored.isCompleted, "Acknowledgment hides the focus receipt without completing its task")
        let finalStore = try CaptureStore(root: root)
        let final = ReminderAlertCoordinator(store: finalStore, now: { base.addingTimeInterval(80) })
        defer { final.stop() }
        final.onAlertsChanged = { values, _ in receipts = values }
        final.start(applicationEvents: NotificationCenter(), workspaceEvents: NotificationCenter())
        try expect(receipts.isEmpty, "An acknowledged focus completion never reappears after restart")
    }
}
