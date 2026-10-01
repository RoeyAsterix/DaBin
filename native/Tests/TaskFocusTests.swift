import AppKit
import Foundation

@MainActor private final class FocusNotifications: ReminderNotificationClient {
    var calls = 0
    func authorization() async -> ReminderAuthorization { calls += 1; return .denied }
    func requestAuthorization() async throws -> Bool { calls += 1; return false }
    func pending() async -> [ScheduledReminder] { calls += 1; return [] }
    func add(_ request: ScheduledReminder) async throws { calls += 1 }
    func removePending(_ identifiers: [String]) { calls += 1 }
    func removeDelivered(_ identifiers: [String]) { calls += 1 }
}

@main struct TaskFocusTests {
    @MainActor static func main() throws {
        var checks = 0
        func expect(_ value: Bool, _ message: String) throws {
            checks += 1
            if !value { throw NSError(domain: "TaskFocusTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinFocus-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root.appendingPathComponent("Live"))
        let preferences = UserDefaults(suiteName: "DaBinFocus.\(UUID())")!
        let previews = PreviewService(store: store, defaults: preferences)
        defer { previews.shutdown() }
        let notifications = FocusNotifications()
        let state = AppState(store: store, previews: previews, reminders: ReminderService(store: store, client: notifications))
        let now = Date().addingTimeInterval(86_400)
        for (hours, minutes, expected) in [(0, 1, 1), (0, 59, 59), (1, 0, 60), (167, 59, 10_079), (168, 0, 10_080)] {
            try expect(TaskFocusSession.duration(hours: hours, minutes: minutes) == expected, "Valid duration \(hours):\(minutes)")
        }
        for (hours, minutes) in [(0, 0), (-1, 30), (0, -1), (0, 60), (168, 1), (169, 0), (Int.max, Int.max)] {
            try expect(TaskFocusSession.duration(hours: hours, minutes: minutes) == nil, "Reject invalid duration before arithmetic")
        }
        try expect(TaskFocusSession.clock(3661.1) == "01:01:02" && TaskFocusSession.clock(604800) == "168:00:00", "Stable clock supports whole and fractional remaining seconds")
        let pure = TaskFocusSession(remainingSeconds: 60, endAt: now.addingTimeInterval(60))
        try expect(pure.remaining(at: now.addingTimeInterval(17.25)) == 42.75, "Pause can preserve fractional seconds")
        try expect(pure.remaining(at: now.addingTimeInterval(-300)) == 60, "Backward clock change never exceeds started duration")
        try expect(pure.remaining(at: now.addingTimeInterval(600)) == 0, "Sleep or a forward clock jump expires by persisted deadline")
        try expect(!TaskFocusSession(remainingSeconds: .infinity).isValid, "Nonfinite focus state is rejected")
        let task = try store.createTask(text: "Fictional research follow-up")
        try expect(state.configureTaskFocus(task, hours: 0, minutes: 25, start: true, at: now), "Start persists a configured duration")
        let end = now.addingTimeInterval(1500)
        try expect(task.taskPlanning?.focusSession?.endAt == end, "Running state stores absolute end timestamp")
        let second = try store.createTask(text: "Independent task")
        try expect(state.configureTaskFocus(second, hours: 0, minutes: 45, start: true, at: now), "Second task starts independently")
        try expect(task.taskPlanning?.focusSession?.endAt == end, "Starting another task preserves first session")
        try expect(state.toggleTaskFocus(task, at: now.addingTimeInterval(30.5)), "Pause saves once")
        try expect(task.taskPlanning?.focusSession == TaskFocusSession(remainingSeconds: 1469.5), "Pause preserves exact remaining time")
        try expect(state.toggleTaskFocus(task, at: now.addingTimeInterval(300)), "Resume succeeds")
        try expect(task.taskPlanning?.focusSession?.endAt == now.addingTimeInterval(1769.5), "Resume calculates new end date")
        let reopened = try CaptureStore(root: store.root)
        let reopenedTask = reopened.captures.first { $0.id == task.id }!
        try expect(reopenedTask.taskPlanning?.focusSession == task.taskPlanning?.focusSession, "Restart preserves countdown without resetting time")
        var expiryEvents = 0
        let lifecycle = TaskFocusCoordinator(store: store)
        lifecycle.onExpired = { expiryEvents += $0.count }
        lifecycle.reconcile(at: now.addingTimeInterval(1800))
        try expect(task.taskPlanning?.focusSession == TaskFocusSession(remainingSeconds: 0) && !task.isCompleted, "Expiry is durable and does not complete task")
        try expect(second.taskPlanning?.focusSession?.isRunning == true, "Independent longer task remains running")
        lifecycle.reconcile(at: now.addingTimeInterval(1801))
        try expect(expiryEvents == 1, "Repeated reconciliation does not write or announce expired sessions again")
        try expect(state.toggleTaskFocus(task, at: now.addingTimeInterval(1802)), "An elapsed timer restarts")
        try expect(task.taskPlanning?.focusSession?.remainingSeconds == 1500, "Restart restores configured full duration")
        let previous = task.taskPlanning
        store.failureInjector = { if $0 == .beforeMetadataSave { throw CaptureStoreError.importVerificationFailed } }
        try expect(!state.configureTaskFocus(task, hours: 1, minutes: 0, at: now), "Failed focus writes report failure")
        try expect(task.taskPlanning == previous, "Failed duration change restores active timer and duration")
        store.failureInjector = nil
        try expect(state.resetTaskFocus(task), "Reset succeeds")
        try expect(task.taskPlanning?.focusSession == TaskFocusSession(remainingSeconds: 1500), "Reset stops countdown without starting another")

        state.openCapture(task.id)
        let draft = state.selectedDraft!
        draft.title = "Edited task title"
        draft.comment = "Unsaved notes stay here"
        draft.planning.priority = .high
        draft.planning.checklist = [TaskChecklistItem(text: "Unsaved checklist")]
        draft.planning.deadline = now.addingTimeInterval(90000)
        try expect(state.scheduleTask(task, day: "2026-10-05", time: "09:30"), "Immediate local schedule persists")
        try expect(draft.title == "Edited task title" && draft.comment == "Unsaved notes stay here"
                   && draft.planning.priority == .high && draft.planning.checklist.count == 1 && draft.hasChanges,
                   "Scheduling retains every unrelated pending draft field")
        try expect(draft.planning.plannedTime == "09:30" && draft.planning.plannedDay == "2026-10-05", "Immediate schedule rebases draft-owned workday")
        try expect(state.configureTaskFocus(task, hours: 0, minutes: 45, start: true, at: now), "Immediate focus can coexist with unsaved task edits")
        try expect(draft.planning.effortMinutes == 45 && draft.planning.priority == .high && draft.hasChanges,
                   "Duration update preserves unsaved priority and checklist")
        let beforeTitle = task.title
        store.failureInjector = { if $0 == .beforeMetadataSave { throw CaptureStoreError.importVerificationFailed } }
        state.saveDetail()
        try expect(task.title == beforeTitle && draft.title == "Edited task title" && draft.hasChanges && draft.hasError,
                   "Failed task edit restores committed title and retains editable draft")
        store.failureInjector = nil
        state.persistDrafts()
        let recoveredState = AppState(store: store, previews: previews, reminders: ReminderService(store: store, client: notifications))
        recoveredState.openCapture(task.id)
        try expect(recoveredState.selectedDraft?.title == "Edited task title" && recoveredState.selectedDraft?.comment == "Unsaved notes stay here",
                   "Restart restores pending task title and notes after immediate timing actions")
        state.saveDetail()
        try expect(task.title == "Edited task title" && task.originalText == "Fictional research follow-up", "Saved title preserves original captured text")
        try expect(task.comment == "Unsaved notes stay here" && task.taskPlanning?.priority == .high && !draft.hasChanges, "Explicit save commits draft without losing immediate settings")
        try expect(task.taskPlanning?.focusSession?.endAt == now.addingTimeInterval(2700), "Explicit save cannot revert separately committed focus")
        try expect(task.taskPlanning?.plannedTime == "09:30" && task.reminderAt == nil && notifications.calls == 0, "Schedule and focus do not request notification permissions or add alarms")
        let plannedBefore = task.taskPlanning
        try expect(!state.scheduleTask(task, day: "2026-10-05", time: "24:00"), "Invalid local clock label is rejected")
        try expect(task.taskPlanning == plannedBefore, "Invalid scheduling preserves all fields")
        try expect(state.scheduleTask(task, day: nil), "Clear workday succeeds")
        try expect(task.taskPlanning?.plannedTime == nil && task.taskPlanning?.deadline != nil, "Clearing workday clears paired time and keeps deadline")
        for bad in ["9:30", "09:3", "12:60", "-1:00", "１２:００"] { try expect(!TaskPlanningPolicy.isValidLocalTime(bad), "Reject malformed local time \(bad)") }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let dst = TaskPlanningPolicy.scheduledDate(day: "2026-03-08", time: "02:30", calendar: calendar)!
        try expect(calendar.component(.hour, from: dst) == 3, "DST gap advances to valid local clock time")
        let repeated = TaskPlanningPolicy.scheduledDate(day: "2026-11-01", time: "01:30", calendar: calendar)!
        try expect(calendar.timeZone.secondsFromGMT(for: repeated) == -14400, "Repeated DST hour resolves first occurrence")
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(CaptureSnapshot(task))) as! [String: Any]
        legacy["schemaVersion"] = 9; legacy.removeValue(forKey: "pasteHistory")
        var legacyPlan = legacy["taskPlanning"] as! [String: Any]
        legacyPlan.removeValue(forKey: "focusSession"); legacyPlan.removeValue(forKey: "plannedTime"); legacy["taskPlanning"] = legacyPlan
        let old = Capture(snapshot: try JSONDecoder().decode(CaptureSnapshot.self, from: JSONSerialization.data(withJSONObject: legacy)))
        try expect(old.taskPlanning?.focusSession == nil && old.taskPlanning?.plannedTime == nil && old.pasteHistory.isEmpty, "Old payloads decode absent timing and trail safely")
        var routine = task.taskPlanning!
        routine.recurrence = .daily; routine.plannedDay = CaptureCalendar.dayString(now); routine.plannedTime = "10:00"
        try store.setTaskPlanning(task, planning: routine)
        let next = try store.setTaskCompleted(task, completed: true, at: now.addingTimeInterval(20))!
        try expect(task.taskPlanning?.focusSession?.isRunning == false, "Completing a task stops its active timer")
        try expect(next.taskPlanning?.focusSession == nil && next.pasteHistory.isEmpty && next.taskPlanning?.plannedTime == "10:00", "Recurrence retains local plan, starts no timer and invents no paste history")
        try expect(!state.toggleTaskFocus(task, at: now), "Completed tasks cannot restart timers")

        let sourceReceipt = CaptureReceiptContext.automatic(.automaticClipboard,
            sourceApplicationName: "Safari", sourceApplicationBundleIdentifier: "com.apple.Safari")
        let sourced = try store.capture(text: "https://example.invalid/client-brief", at: now,
            source: CaptureSource(filePath: "/Fictional/brief.txt", url: "https://example.invalid/client"), receipt: sourceReceipt)[0]
        try store.convertToTask(sourced)
        try store.setTaskPlanning(sourced, planning: TaskPlanning(plannedDay: CaptureCalendar.dayString(now), recurrence: .daily))
        try store.setTaskFocus(sourced, session: TaskFocusSession(remainingSeconds: 60, endAt: now.addingTimeInterval(60)), durationMinutes: 1)
        try store.recordPasteDestination(for: sourced, applicationName: "Mail", applicationBundleIdentifier: "com.apple.mail", at: now)
        let sourcedNext = try store.setTaskCompleted(sourced, completed: true, at: now)!
        try expect(sourcedNext.sourceApplicationName == "Safari" && sourcedNext.sourceApplicationBundleIdentifier == "com.apple.Safari"
                   && sourcedNext.sourceURL == sourced.sourceURL && sourcedNext.sourceFilePath == sourced.sourceFilePath,
                   "Recurring occurrence retains known source application, URL and file path")
        try expect(sourcedNext.captureOrigin == .manual && sourcedNext.automaticActionID == nil
                   && sourcedNext.pasteHistory.isEmpty && sourcedNext.taskPlanning?.focusSession == nil,
                   "Source provenance does not duplicate automatic action, destinations or focus session")
        try expect(sourcedNext.originalURL == sourced.originalURL && sourcedNext.attachmentRelativePath == nil,
                   "Recurring link stays reusable without duplicating file ownership")
        let reopenedSourced = try CaptureStore(root: store.root).captures.first { $0.id == sourcedNext.id }!
        try expect(reopenedSourced.sourceApplicationBundleIdentifier == "com.apple.Safari" && reopenedSourced.sourceURL == sourced.sourceURL
                   && reopenedSourced.captureOrigin == .manual && reopenedSourced.pasteHistory.isEmpty,
                   "Recurring source and reset lifecycle survive restart")

        let capture = try store.capture(text: "Client feedback remains original")[0]
        state.route = .inbox
        state.convertToTask(capture)
        try expect(capture.isTask && state.route == .inbox && state.canUndoTaskConversion, "Card conversion stays in place with Undo")
        try store.update(capture, comment: "A new annotation survives Undo", reminderAt: nil, reminderTimeZoneID: nil, planning: TaskPlanning(), title: "Edited after conversion")
        state.undoTaskConversion()
        try expect(!capture.isTask && capture.comment == "A new annotation survives Undo" && capture.title == "Edited after conversion", "Undo preserves unrelated post-conversion edits")
        state.convertToTask(capture)
        state.openCapture(capture.id)
        state.selectedDraft?.title = "A pending title is still work"
        state.undoTaskConversion()
        try expect(capture.isTask && state.selectedDraft?.title == "A pending title is still work", "Undo refuses to strand an unsaved task title")
        state.selectedDraft?.title = capture.title
        try store.planTask(capture, on: "2026-10-06")
        state.undoTaskConversion()
        try expect(capture.isTask && capture.taskPlanning?.plannedDay == "2026-10-06", "Undo refuses to discard newer task work")
        // Interrupt after durable immediate actions but before the debounced
        // draft sidecar catches up. Only synthetic recovery files are touched.
        let recoveryStore = try CaptureStore(root: root.appendingPathComponent("Recovery"))
        let recoveryPreviews = PreviewService(store: recoveryStore, defaults: preferences)
        defer { recoveryPreviews.shutdown() }
        func recoveryState() -> AppState {
            AppState(store: recoveryStore, previews: recoveryPreviews,
                reminders: ReminderService(store: recoveryStore, client: notifications))
        }
        let recoveryTask = try recoveryStore.createTask(text: "Recovery fixture",
            planning: TaskPlanning(plannedDay: "2026-10-05", plannedTime: "09:00", effortMinutes: 25))
        let editing = recoveryState()
        editing.openCapture(recoveryTask.id)
        editing.selectedDraft?.comment = "Keep unsaved notes through an interrupted timing save"
        editing.selectedDraft?.planning.priority = .high
        editing.persistDrafts()
        let draftURL = recoveryStore.root.appendingPathComponent("Drafts.json")
        let beforeImmediate = try Data(contentsOf: draftURL)
        try expect(editing.configureTaskFocus(recoveryTask, hours: 0, minutes: 45, start: true, at: now), "Durable timer write precedes sidecar update")
        try expect(editing.scheduleTask(recoveryTask, day: "2026-10-06", time: "10:30"), "Durable schedule write precedes sidecar update")
        try expect(try Data(contentsOf: draftURL) == beforeImmediate, "Fixture models the real debounce crash window with an unchanged sidecar")
        let afterCrash = recoveryState()
        afterCrash.openCapture(recoveryTask.id)
        try expect(afterCrash.selectedDraft?.planning.plannedDay == "2026-10-06"
                   && afterCrash.selectedDraft?.planning.plannedTime == "10:30"
                   && afterCrash.selectedDraft?.planning.effortMinutes == 45,
                   "Stale recovery sidecar rebases timing to separately committed metadata")
        try expect(afterCrash.selectedDraft?.comment == "Keep unsaved notes through an interrupted timing save"
                   && afterCrash.selectedDraft?.planning.priority == .high,
                   "Three-way recovery retains unrelated unsaved notes and priority")
        afterCrash.saveDetail()
        try expect(recoveryTask.taskPlanning?.plannedDay == "2026-10-06"
                   && recoveryTask.taskPlanning?.plannedTime == "10:30"
                   && recoveryTask.taskPlanning?.effortMinutes == 45,
                   "Saving recovered edits cannot roll back committed timing")
        let otherOrder = try recoveryStore.createTask(text: "Other order fixture", planning: TaskPlanning(plannedDay: "2026-10-06"))
        try recoveryStore.reorderTasks([recoveryTask, otherOrder], on: "2026-10-06")
        let orderEditor = recoveryState()
        orderEditor.openCapture(recoveryTask.id)
        orderEditor.selectedDraft?.comment = "Unsaved note before a Today reorder"
        try recoveryStore.reorderTasks([otherOrder, recoveryTask], on: "2026-10-06")
        orderEditor.saveDetail()
        try expect(recoveryTask.taskPlanning?.order == 1 && otherOrder.taskPlanning?.order == 0,
                   "Saving an older detail draft preserves the newer Today order")
        try expect(orderEditor.selectedDraft?.planning.order == 1 && orderEditor.selectedDraft?.hasChanges == false,
                   "Successful detail save adopts committed order in its clean baseline")
        var legacyRecovery = DraftArchiveSnapshot()
        var pendingLegacy = recoveryTask.taskPlanning!
        pendingLegacy.plannedDay = "2026-10-09"; pendingLegacy.plannedTime = "11:15"; pendingLegacy.effortMinutes = 90
        legacyRecovery.details = [DetailDraftSnapshot(captureID: recoveryTask.id, comment: "Legacy pending notes", planning: pendingLegacy,
            reminderEnabled: false, reminderMode: "date", countdownHours: 0, countdownMinutes: 30, reminderDate: now)]
        try DraftArchive(root: recoveryStore.root).save(legacyRecovery)
        let legacyEditor = recoveryState()
        legacyEditor.openCapture(recoveryTask.id)
        try expect(legacyEditor.selectedDraft?.planning.plannedDay == "2026-10-09"
                   && legacyEditor.selectedDraft?.planning.plannedTime == "11:15"
                   && legacyEditor.selectedDraft?.planning.effortMinutes == 90,
                   "Legacy recovery without a baseline retains pending planning edits")
        legacyEditor.persistDrafts()
        let migratedLegacy = recoveryState()
        migratedLegacy.openCapture(recoveryTask.id)
        try expect(migratedLegacy.selectedDraft?.planning.plannedDay == "2026-10-09"
                   && migratedLegacy.selectedDraft?.planning.effortMinutes == 90,
                   "Adding a baseline does not lose legacy pending timing on a second restart")
        print("PASS: \(checks) task focus, local schedule, lifecycle, recovery and draft checks; synthetic archive only.")
    }
}
