import AppKit
import Foundation

@MainActor
private final class TaskNotificationClient: ReminderNotificationClient {
    var requests: [String: ScheduledReminder] = [:]
    var authorizationValue: ReminderAuthorization = .allowed
    var failScheduling = false
    var pauseAuthorization = false
    var authorizationContinuation: CheckedContinuation<Void, Never>?
    func authorization() async -> ReminderAuthorization {
        if pauseAuthorization {
            await withCheckedContinuation { authorizationContinuation = $0 }
        }
        return authorizationValue
    }

    func resumeAuthorization() {
        pauseAuthorization = false
        let continuation = authorizationContinuation
        authorizationContinuation = nil
        continuation?.resume()
    }
    func requestAuthorization() async throws -> Bool { fatalError("Task tests must not request notification permission") }
    func pending() async -> [ScheduledReminder] { Array(requests.values) }
    func add(_ reminder: ScheduledReminder) async throws {
        if failScheduling { throw NSError(domain: "TaskReminderFailure", code: 1) }
        requests[reminder.identifier] = reminder
    }
    func removePending(_ identifiers: [String]) { identifiers.forEach { requests.removeValue(forKey: $0) } }
    func removeDelivered(_ identifiers: [String]) {}
}

@main
struct TaskStateTests {
    @MainActor private static var checks = 0
    @MainActor private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        if !condition() { throw NSError(domain: "DaBinTaskTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    @MainActor private static func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !condition() && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        guard condition() else { throw NSError(domain: "DaBinTaskTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for reminder feedback"]) }
    }

    @MainActor private static func checkBuddyTaskIntegration(root: URL) async throws {
        let store = try CaptureStore(root: root)
        let client = TaskNotificationClient()
        let input = InputService(store: store)
        let previews = PreviewService(store: store)
        let state = AppState(store: store, previews: previews,
                             reminders: ReminderService(store: store, client: client), manualInput: input)
        defer { previews.cancelNetwork() }

        let task = try store.createTask(text: "Prepare the fictional launch checklist")
        var celebrations = 0
        var completionWasPersisted = false
        state.onTaskCompleted = {
            celebrations += 1
            completionWasPersisted = (try? CaptureStore(root: root))?.captures
                .first(where: { $0.id == task.id })?.isCompleted == true
        }
        state.toggleTaskCompletion(task)
        try expect(celebrations == 1 && completionWasPersisted,
                   "Robot happiness follows a successfully persisted incomplete-to-complete transition")
        state.completeFollowUp(task)
        try expect(celebrations == 1, "Completing an already-completed follow-up never repeats happiness")
        state.toggleTaskCompletion(task)
        try expect(!task.isCompleted && celebrations == 1, "Reopening a task never celebrates completion")
        store.failureInjector = { if $0 == .beforeMetadataSave { throw CaptureStoreError.importVerificationFailed } }
        state.toggleTaskCompletion(task)
        try expect(!task.isCompleted && celebrations == 1 && state.status?.severity == .error,
                   "A failed completion rolls back the task and never calls the robot celebration")
        store.failureInjector = nil

        state.openCapture(task.id)
        let draft = state.selectedDraft!
        draft.reminderEnabled = true
        draft.reminderMode = .countdown
        draft.countdownHours = 0
        draft.countdownMinutes = 0
        state.saveDetail()
        try expect(task.reminderAt == nil && draft.hasError && draft.hasChanges,
                   "An empty countdown leaves the task unchanged and preserves the editable draft")
        draft.countdownHours = 1
        draft.countdownMinutes = 7
        let startedSave = Date()
        state.saveDetail()
        let endedSave = Date()
        guard let absoluteReminder = task.reminderAt else {
            throw NSError(domain: "DaBinTaskTests", code: 8,
                          userInfo: [NSLocalizedDescriptionKey: "Countdown did not persist a reminder"])
        }
        try expect(absoluteReminder >= startedSave.addingTimeInterval(4_020)
                   && absoluteReminder <= endedSave.addingTimeInterval(4_020),
                   "Hour-minute countdown starts at Save, using the exact chosen duration")
        try expect(draft.reminderMode == .date && draft.reminderDate == absoluteReminder && !draft.hasChanges,
                   "After Save the countdown becomes a clean absolute-date draft")
        let revision = task.reminderRevision
        draft.comment = "Add the final review link"
        state.saveDetail()
        try expect(task.reminderAt == absoluteReminder && task.reminderRevision == revision
                   && task.comment == "Add the final review link",
                   "Editing a comment does not restart a saved countdown or reschedule its notification")
        let reopened = try CaptureStore(root: root)
        try expect(reopened.captures.first(where: { $0.id == task.id })?.reminderAt == absoluteReminder,
                   "Reopening the archive retains the absolute countdown deadline")

        let overdue = try store.capture(text: "An earlier reminder with new context")[0]
        let overdueDate = Date().addingTimeInterval(-3_600)
        try store.update(overdue, comment: "Before", reminderAt: overdueDate, reminderTimeZoneID: "Europe/London")
        let overdueRevision = overdue.reminderRevision
        state.openCapture(overdue.id)
        state.selectedDraft!.comment = "Keep this new context after the reminder elapsed"
        state.saveDetail()
        try expect(overdue.comment == "Keep this new context after the reminder elapsed"
                   && overdue.reminderAt == overdueDate && overdue.reminderRevision == overdueRevision
                   && overdue.reminderTimeZoneID == "Europe/London" && !state.selectedDraft!.hasError,
                   "An unchanged overdue reminder never prevents saving a comment or changes its date/time zone")

        state.openNewTask()
        state.newTaskDraft.text = "Countdown from the task composer"
        state.newTaskDraft.reminderEnabled = true
        state.newTaskDraft.reminderMode = .countdown
        state.newTaskDraft.countdownHours = 0
        state.newTaskDraft.countdownMinutes = 12
        let newTaskStarted = Date()
        state.saveNewTask()
        let newTaskEnded = Date()
        let countdownTask = store.captures.first { $0.title == "Countdown from the task composer" }
        try expect(countdownTask?.reminderAt.map {
            $0 >= newTaskStarted.addingTimeInterval(720) && $0 <= newTaskEnded.addingTimeInterval(720)
        } == true && !state.newTaskDraft.hasChanges && state.newTaskDraft.reminderMode == .date,
                   "New-task countdown persists once and clears the composer only after success")

        state.openCapture(task.id)
        let taskDraft = state.selectedDraft!
        taskDraft.comment = "Keep this unfinished task note"
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        func setPasteboardText(_ text: String) throws {
            pasteboard.clearContents()
            let item = NSPasteboardItem()
            item.setString(text, forType: .string)
            try expect(pasteboard.writeObjects([item]), "Isolated task fixture writes a private pasteboard")
        }
        try setPasteboardText("Fictional attachment copied for the launch task")
        let beforePaste = store.captures.count
        state.pasteAttachments(to: task, from: pasteboard)
        state.showSettings()
        try await waitUntil { !state.isImporting }
        let pasted = store.attachments(for: task)
        try expect(store.captures.count == beforePaste + 1 && pasted.count == 1
                   && pasted.first?.originalText == "Fictional attachment copied for the launch task",
                   "Task paste saves the original text as one owned attachment (records: \(store.captures.count - beforePaste), attachments: \(pasted.count), feedback: \(state.status?.text ?? "none"))")
        try expect(state.route == .settings && state.selectedDraft === taskDraft
                   && taskDraft.comment == "Keep this unfinished task note" && taskDraft.hasChanges,
                   "An attachment completing after navigation never jumps back or discards task edits")
        try expect(celebrations == 1, "Adding an attachment is not a task-completion celebration")

        let file = root.appendingPathComponent("Launch-notes.txt")
        try Data("A fictional local file for the task".utf8).write(to: file)
        pasteboard.clearContents()
        try expect(pasteboard.writeObjects([file as NSURL]), "Isolated file fixture writes a private pasteboard")
        state.openCapture(task.id)
        state.pasteAttachments(to: task, from: pasteboard)
        try await waitUntil { !state.isImporting }
        try expect(store.attachments(for: task).count == 2 && state.route == .detail
                   && state.selectedCapture === task && state.selectedDraft === taskDraft,
                   "Pasted files append inside the task workspace and retain its current draft")
        let attachment = store.attachments(for: task).first!
        state.openCapture(attachment.id)
        try expect(state.route == .detail && state.selectedCapture === attachment,
                   "Selecting a task attachment opens that attachment's actual details")
        state.back()
        try expect(state.route == .detail && state.selectedCapture === task && state.selectedDraft === taskDraft
                   && state.detailFocus == "task" && taskDraft.comment == "Keep this unfinished task note",
                   "Back from an attachment restores its parent workspace and unfinished task draft")
        let failedCount = store.captures.count
        store.failureInjector = { if $0 == .beforeMetadataSave { throw CaptureStoreError.importVerificationFailed } }
        try setPasteboardText("This attachment must fail")
        state.pasteAttachments(to: task, from: pasteboard)
        try await waitUntil { !state.isImporting }
        try expect(store.captures.count == failedCount && state.status?.severity == .error
                   && state.route == .detail && celebrations == 1,
                   "Failed task attachment reports failure without a false card, navigation, or celebration")
        store.failureInjector = nil
        await state.reminders.reconcile()
    }

    @MainActor private static func checkCarryover(root: URL) async throws {
        let store = try CaptureStore(root: root)
        let client = TaskNotificationClient()
        let reminders = ReminderService(store: store, client: client)
        let state = AppState(store: store, previews: PreviewService(store: store), reminders: reminders)
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = .current
        parser.dateFormat = "yyyy-MM-dd HH:mm"
        func date(_ value: String) -> Date { parser.date(from: value)! }
        func ids(_ captures: [Capture]) -> [UUID] { captures.map(\.id) }

        // All receipts are fictional, local and deliberately cross a year boundary.
        let noteID = try store.capture(text: "A note with a reminder", at: date("2023-12-31 09:00"))[0].id
        let sameDayNoteID = try store.capture(text: "New year notes", at: date("2024-01-01 13:00"))[0].id
        let linkID = try store.capture(text: "https://example.invalid/new-year", at: date("2024-01-01 15:00"))[0].id
        let older = try store.createTask(text: "Carryover anchor", at: date("2023-12-30 09:00"))
        let newer = try store.createTask(text: "Later unfinished task", at: date("2023-12-31 10:00"))
        let completed = try store.createTask(text: "Already finished task", at: date("2023-12-31 11:00"))
        let sameDayTask = try store.createTask(text: "New year task", at: date("2024-01-01 12:00"))
        let note = store.captures.first { $0.id == noteID }!
        let reminder = Date().addingTimeInterval(7200)
        try store.update(note, comment: "This stays a note", reminderAt: reminder, reminderTimeZoneID: TimeZone.current.identifier)
        try store.update(older, comment: "Keep the original context", reminderAt: nil, reminderTimeZoneID: nil)
        try store.setTaskCompleted(completed, completed: true)
        let original = CaptureSnapshot(older)
        let originalFolder = store.archiveURL(for: older)
        let persistedIDs = Set(store.captures.map(\.id))

        state.selectedDay = date("2024-01-01 12:00")
        let expected = [newer.id, older.id, linkID, sameDayNoteID, sameDayTask.id]
        try expect(ids(state.dailyCaptures) == expected,
                   "Carryovers precede all selected-day captures; both groups retain newest-first order across a year boundary")
        try expect(Set(ids(state.allCapturesForDay)) == Set(expected),
                   "Daily empty-state membership includes unfinished older tasks")
        try expect(state.isTaskAtTop(older) && state.isTaskAtTop(newer) && !state.isTaskAtTop(sameDayTask),
                   "Only earlier unfinished tasks receive carryover presentation")
        try expect(!state.dailyCaptures.contains { $0.id == noteID } && !state.isTaskAtTop(note),
                   "An ordinary capture with a reminder never becomes a carried task")
        try expect(!state.dailyCaptures.contains { $0.id == completed.id } && !state.isTaskAtTop(completed),
                   "Previously completed tasks do not carry forward")

        state.filter = .links
        try expect(ids(state.dailyCaptures) == [linkID], "Links filter excludes carried tasks")
        try expect(Set(ids(state.allCapturesForDay)) == Set(expected), "Filtering does not change unfiltered day membership")
        state.filter = .files
        try expect(state.dailyCaptures.isEmpty, "Files filter excludes carried tasks and ordinary text")
        state.filter = .media
        try expect(state.dailyCaptures.isEmpty, "Media filter excludes carried tasks")
        state.filter = .tasks
        try expect(ids(state.dailyCaptures) == [newer.id, older.id, sameDayTask.id],
                   "Tasks filter keeps unfinished carryovers above same-day tasks and removes ordinary captures")
        try expect(Set(ids(state.allCapturesForDay)) == Set(expected),
                   "Tasks filter preserves unfiltered daily membership")
        state.filter = .all

        state.selectedDay = date("2023-12-29 12:00")
        try expect(state.dailyCaptures.isEmpty && !state.isTaskAtTop(older), "A task cannot appear before its original creation day")
        state.selectedDay = date("2023-12-30 12:00")
        try expect(ids(state.dailyCaptures) == [older.id] && !state.isTaskAtTop(older),
                   "A task appears once without a carryover frame on its original day")
        state.selectedDay = date("2023-12-31 12:00")
        try expect(ids(state.dailyCaptures) == [older.id, completed.id, newer.id, noteID],
                   "Original-day records include completed tasks beneath any earlier carryovers")
        state.filter = .tasks
        try expect(ids(state.dailyCaptures) == [older.id, completed.id, newer.id],
                   "Tasks filter includes both completed and open tasks on their original day without losing carryover priority")
        state.filter = .all

        state.selectedDay = date("2024-01-03 12:00")
        try expect(ids(state.dailyCaptures) == [sameDayTask.id, newer.id, older.id],
                   "Unfinished tasks survive skipped dates even when the viewed day has no captures")
        state.toggleTaskCompletion(newer)
        await reminders.reconcile()
        try expect(newer.isCompleted && ids(state.dailyCaptures) == [sameDayTask.id, older.id],
                   "Completing a carried task removes it from the later daily board")
        state.selectedDay = date("2023-12-31 12:00")
        try expect(state.dailyCaptures.contains { $0.id == newer.id && $0.isCompleted },
                   "Completing a carried task preserves its completed record on the original day")
        state.toggleTaskCompletion(newer)
        await reminders.reconcile()
        state.selectedDay = date("2024-01-03 12:00")
        try expect(ids(state.dailyCaptures) == [sameDayTask.id, newer.id, older.id],
                   "Reopening a completed task restores one carried record on later days")
        try expect(older.capturedAt == original.capturedAt && older.captureDay == original.captureDay
                   && older.captureTimeZoneID == original.captureTimeZoneID && older.captureUTCOffsetSeconds == original.captureUTCOffsetSeconds,
                   "Browsing carryovers retains the original receipt timestamp, calendar date and time zone")
        try expect(older.comment == original.comment && older.reminderAt == original.reminderAt
                   && older.reminderTimeZoneID == original.reminderTimeZoneID && older.reminderRevision == original.reminderRevision,
                   "Carrying a task leaves its comment and scheduled reminder unchanged")
        try expect(store.archiveURL(for: older) == originalFolder && originalFolder != nil,
                   "A carried task keeps its original local archive folder")
        state.query = "Carryover anchor"
        state.filter = .tasks
        try expect(state.searchGroups.map(\.day) == ["2023-12-30"]
                   && state.searchGroups.flatMap(\.entries).filter { $0.capture.id == older.id }.count == 1,
                   "Tasks-filtered contextual search finds the task once under its original date")
        state.query = "note"
        try expect(state.searchGroups.isEmpty, "AppState passes the Tasks filter to search so ordinary note matches are excluded")
        state.query = "Carryover anchor"
        state.filter = .all
        let reopened = try CaptureStore(root: root)
        try expect(reopened.captures.count == persistedIDs.count && Set(reopened.captures.map(\.id)) == persistedIDs,
                   "Carryover never creates duplicate stored captures")
        let reopenedOlder = reopened.captures.first { $0.id == older.id }!
        try expect(reopenedOlder.captureDay == original.captureDay && reopenedOlder.comment == original.comment
                   && reopenedOlder.reminderAt == original.reminderAt && reopened.archiveURL(for: reopenedOlder) == originalFolder,
                   "Original date, context, reminder and archive location survive store reopening")

        // Seed the public day-change hook, then model midnight and a multi-day wake.
        let january31 = date("2024-01-31 23:59")
        state.refreshCurrentDay(at: january31)
        state.selectedDay = january31
        state.dailyScrollID = .capture(.capture(older.id))
        state.refreshCurrentDay(at: date("2024-02-01 00:01"))
        try expect(state.dayKey == "2024-02-01" && state.dailyScrollID == nil,
                   "Midnight advances an open current-day board across the month boundary and clears its old scroll anchor")
        try expect(ids(state.dailyCaptures) == [sameDayTask.id, newer.id, older.id],
                   "Automatic month rollover retains each unfinished task once at the top")
        state.dailyScrollID = .capture(.capture(older.id))
        state.refreshCurrentDay(at: date("2024-02-01 18:00"))
        try expect(state.dailyScrollID == .capture(.capture(older.id)), "A clock refresh within the same day preserves scrolling")
        state.refreshCurrentDay(at: date("2024-02-05 09:00"))
        try expect(state.dayKey == "2024-02-05" && state.dailyScrollID == nil,
                   "Waking after several days advances a previously current board directly to today")
        state.selectedDay = date("2023-12-31 12:00")
        state.dailyScrollID = .capture(.capture(newer.id))
        state.refreshCurrentDay(at: date("2024-02-06 09:00"))
        try expect(state.dayKey == "2023-12-31" && state.dailyScrollID == .capture(.capture(newer.id)),
                   "A day change preserves an intentionally browsed historical date and its scroll anchor")
        state.selectedDay = date("2024-02-06 12:00")
        state.refreshCurrentDay(at: date("2024-02-07 09:00"))
        try expect(state.dayKey == "2024-02-07", "Returning to the current day resumes automatic day advancement")

        let sourceZone = TimeZone(secondsFromGMT: 14 * 3600)!
        let zonedTask = try store.createTask(text: "A task received in another time zone",
            at: ISO8601DateFormatter().date(from: "2024-01-01T12:30:00Z")!, timeZone: sourceZone)
        state.selectedDay = date("2024-01-01 12:00")
        try expect(zonedTask.captureDay == "2024-01-02" && !state.dailyCaptures.contains { $0.id == zonedTask.id },
                   "A task uses its stored receipt day when source and current time zones differ")
        state.selectedDay = date("2024-01-02 12:00")
        try expect(state.dailyCaptures.contains { $0.id == zonedTask.id } && !state.isTaskAtTop(zonedTask),
                   "A different-zone receipt remains an ordinary record on its stored creation day")
        state.selectedDay = date("2024-01-03 12:00")
        try expect(state.isTaskAtTop(zonedTask), "A different-zone task carries only after its stored creation day")

        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        state.refreshCurrentDay(at: yesterday)
        state.selectedDay = yesterday
        state.dailyScrollID = .capture(.capture(older.id))
        NotificationCenter.default.post(name: .NSCalendarDayChanged, object: nil)
        try await waitUntil { state.dayKey == CaptureCalendar.dayString(now) }
        try expect(state.dailyScrollID == nil, "The real calendar-day notification refreshes the board and clears the old scroll anchor")
    }

    @MainActor private static func checkReminderDay(root: URL) throws {
        let store = try CaptureStore(root: root)
        let client = TaskNotificationClient()
        let reminders = ReminderService(store: store, client: client)
        let state = AppState(store: store, previews: PreviewService(store: store), reminders: reminders)
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = .current
        parser.dateFormat = "yyyy-MM-dd HH:mm"
        func date(_ value: String) -> Date { parser.date(from: value)! }
        func ids(_ captures: [Capture]) -> [UUID] { captures.map(\.id) }
        func schedule(_ capture: Capture, on value: String?) throws {
            try store.update(capture, comment: "Original task context", reminderAt: value.map(date),
                             reminderTimeZoneID: value == nil ? nil : TimeZone.current.identifier)
        }
        // Historical fixtures are written directly so no live notifications are requested.
        let scheduled = try store.createTask(text: "Review on the planned date", at: date("2023-12-30 09:00"))
        try schedule(scheduled, on: "2024-01-02 10:00")
        let ordinaryNote = try store.capture(text: "A note also has a reminder", at: date("2023-12-30 11:00"))[0]
        try schedule(ordinaryNote, on: "2024-01-02 10:00")
        let unplanned = try store.createTask(text: "Continue on following days", at: date("2023-12-31 10:00"))
        let completed = try store.createTask(text: "Finished before the reminder", at: date("2023-12-31 12:00"))
        try schedule(completed, on: "2024-01-02 11:00")
        try store.setTaskCompleted(completed, completed: true)
        let sameDay = try store.createTask(text: "Created and due on the same day", at: date("2024-01-02 09:00"))
        try schedule(sameDay, on: "2024-01-02 14:00")
        let note = try store.capture(text: "An afternoon capture", at: date("2024-01-02 17:00"))[0]
        let link = try store.capture(text: "https://example.invalid/planned-day", at: date("2024-01-02 18:00"))[0]
        let future = try store.createTask(text: "Created on a later date", at: date("2024-01-03 09:00"))
        try schedule(future, on: "2024-01-04 10:00")
        let original = CaptureSnapshot(scheduled)
        let originalFolder = store.archiveURL(for: scheduled)
        let storedIDs = Set(store.captures.map(\.id))

        state.selectedDay = date("2023-12-29 12:00")
        try expect(state.dailyCaptures.isEmpty && !state.isTaskAtTop(scheduled),
                   "A reminded task never appears before its original receipt day")
        state.selectedDay = date("2023-12-30 12:00")
        try expect(ids(state.dailyCaptures) == [ordinaryNote.id, scheduled.id] && !state.isTaskAtTop(scheduled),
                   "A future-reminder task remains an ordinary original-day record, in receipt order")
        state.selectedDay = date("2024-01-01 12:00")
        try expect(ids(state.dailyCaptures) == [unplanned.id] && !state.isTaskAtTop(scheduled),
                   "A reminder suppresses task carryover on days before its planned date")
        state.filter = .tasks
        try expect(ids(state.dailyCaptures) == [unplanned.id],
                   "Tasks filter does not reveal scheduled tasks before their reminder date")
        state.filter = .all
        state.selectedDay = date("2024-01-02 12:00")
        let plannedDay = [sameDay.id, unplanned.id, scheduled.id, link.id, note.id]
        try expect(ids(state.dailyCaptures) == plannedDay,
                   "Reminder-day tasks and unscheduled carryovers precede all ordinary captures, newest receipt first")
        try expect(state.isTaskAtTop(scheduled) && state.isTaskAtTop(sameDay) && state.isTaskAtTop(unplanned),
                   "Tasks created earlier and tasks created on their reminder day both receive the top-row presentation")
        try expect(state.dailyCaptures.filter { $0.id == sameDay.id }.count == 1,
                   "An original-day task with a same-day reminder appears exactly once")
        try expect(!state.isTaskAtTop(ordinaryNote) && !state.dailyCaptures.contains { $0.id == ordinaryNote.id },
                   "Adding a reminder to an ordinary capture does not promote it to other days")
        try expect(!state.isTaskAtTop(completed) && !state.dailyCaptures.contains { $0.id == completed.id },
                   "A completed task stays off the reminder day's top group")
        try expect(!state.dailyCaptures.contains { $0.id == future.id },
                   "A later original receipt cannot leak into an earlier reminder-day board")
        state.filter = .links
        try expect(ids(state.dailyCaptures) == [link.id] && Set(ids(state.allCapturesForDay)) == Set(plannedDay),
                   "Link filtering excludes promoted tasks while preserving unfiltered daily membership")
        state.filter = .files
        try expect(state.dailyCaptures.isEmpty, "File filtering excludes reminder-day tasks")
        state.filter = .media
        try expect(state.dailyCaptures.isEmpty, "Media filtering excludes reminder-day tasks")
        state.filter = .tasks
        try expect(ids(state.dailyCaptures) == [sameDay.id, unplanned.id, scheduled.id],
                   "Tasks filter includes reminder-day tasks and unscheduled carryovers in their established top-group order")
        try expect(Set(ids(state.allCapturesForDay)) == Set(plannedDay),
                   "Tasks filtering leaves the reminder day's unfiltered capture membership unchanged")
        state.filter = .all
        state.selectedDay = date("2024-01-03 12:00")
        try expect(ids(state.dailyCaptures) == [unplanned.id, future.id]
                   && !state.isTaskAtTop(scheduled) && !state.isTaskAtTop(sameDay),
                   "Unfinished overdue reminders do not carry to the next date; future reminders remain ordinary on their original day")
        state.filter = .tasks
        try expect(ids(state.dailyCaptures) == [unplanned.id, future.id],
                   "Tasks filter preserves next-day carryover rules and does not restore overdue reminders")
        state.filter = .all
        state.selectedDay = date("2024-02-01 12:00")
        try expect(ids(state.dailyCaptures) == [unplanned.id],
                   "Only tasks without reminders continue carrying across skipped days and month boundaries")
        try expect(scheduled.capturedAt == original.capturedAt && scheduled.captureDay == original.captureDay
                   && scheduled.captureTimeZoneID == original.captureTimeZoneID && scheduled.captureUTCOffsetSeconds == original.captureUTCOffsetSeconds,
                   "Reminder-day presentation preserves original receipt identity and date metadata")
        try expect(scheduled.reminderAt == original.reminderAt && scheduled.reminderRevision == original.reminderRevision
                   && scheduled.reminderTimeZoneID == original.reminderTimeZoneID && scheduled.notificationState == original.notificationState
                   && scheduled.comment == original.comment && client.requests.isEmpty,
                   "Browsing reminder days neither reschedules reminders nor rewrites saved context")
        try expect(originalFolder != nil && store.archiveURL(for: scheduled) == originalFolder,
                   "Reminder-day presentation keeps the original archive folder")
        state.query = "Review on the planned date"
        try expect(state.searchGroups.map(\.day) == ["2023-12-30"]
                   && state.searchGroups.flatMap(\.entries).filter { $0.capture.id == scheduled.id }.count == 1,
                   "Search still finds a reminded task once under its original capture date")

        state.selectedDay = date("2024-01-02 12:00")
        try store.setTaskCompleted(sameDay, completed: true)
        try expect(ids(state.dailyCaptures) == [unplanned.id, scheduled.id, link.id, note.id, sameDay.id]
                   && !state.isTaskAtTop(sameDay),
                   "Completing a same-day reminded task removes promotion but preserves its original-day row")
        state.filter = .tasks
        try expect(ids(state.dailyCaptures) == [unplanned.id, scheduled.id, sameDay.id] && sameDay.isCompleted,
                   "Tasks filter retains the completed original-day task below unfinished promoted tasks")
        state.filter = .all
        try store.setTaskCompleted(scheduled, completed: true)
        try expect(!state.dailyCaptures.contains { $0.id == scheduled.id },
                   "Completing an earlier reminded task removes it from the reminder-day board")
        state.selectedDay = date("2023-12-30 12:00")
        try expect(state.dailyCaptures.contains { $0.id == scheduled.id && $0.isCompleted },
                   "Completed reminded tasks remain in their original date's history")
        try store.setTaskCompleted(scheduled, completed: false)
        state.selectedDay = date("2024-01-02 12:00")
        try expect(state.isTaskAtTop(scheduled) && state.dailyCaptures.filter { $0.id == scheduled.id }.count == 1,
                   "Reopening a reminded task restores it only on its planned date")
        state.selectedDay = date("2024-01-03 12:00")
        try expect(!state.dailyCaptures.contains { $0.id == scheduled.id },
                   "Reopening does not turn an overdue reminder into daily carryover")

        try schedule(scheduled, on: "2024-01-03 10:00")
        try expect(state.isTaskAtTop(scheduled) && state.dailyCaptures.contains { $0.id == scheduled.id },
                   "Editing a reminder immediately promotes the task on the new reminder date")
        state.selectedDay = date("2024-01-02 12:00")
        try expect(!state.dailyCaptures.contains { $0.id == scheduled.id },
                   "Editing a reminder removes the task from the previous planned date")
        try schedule(scheduled, on: nil)
        try expect(state.isTaskAtTop(scheduled) && state.dailyCaptures.filter { $0.id == scheduled.id }.count == 1,
                   "Removing a reminder restores ordinary unfinished-task carryover without duplication")
        state.selectedDay = date("2023-12-30 12:00")
        try expect(!state.isTaskAtTop(scheduled) && state.dailyCaptures.filter { $0.id == scheduled.id }.count == 1,
                   "Removing a reminder keeps the original-day task unpromoted and unique")
        try schedule(scheduled, on: "2024-01-02 10:00")
        let reopened = try CaptureStore(root: root)
        let reopenedState = AppState(store: reopened, previews: PreviewService(store: reopened),
                                     reminders: ReminderService(store: reopened, client: TaskNotificationClient()))
        reopenedState.selectedDay = date("2024-01-02 12:00")
        let restored = reopened.captures.first { $0.id == scheduled.id }!
        try expect(reopenedState.isTaskAtTop(restored) && reopenedState.dailyCaptures.filter { $0.id == scheduled.id }.count == 1,
                   "Reminder-day promotion survives application storage reopening")
        reopenedState.selectedDay = date("2024-01-03 12:00")
        try expect(!reopenedState.dailyCaptures.contains { $0.id == scheduled.id },
                   "Storage reopening does not reintroduce overdue reminder carryover")
        try expect(Set(reopened.captures.map(\.id)) == storedIDs && reopened.captures.count == storedIDs.count,
                   "Reminder edits, completion, date browsing and reopening never create copied task records")
        try expect(restored.captureDay == original.captureDay && restored.capturedAt == original.capturedAt
                   && restored.comment == original.comment && restored.reminderAt == original.reminderAt
                   && reopened.archiveURL(for: restored) == originalFolder,
                   "Original context, reminder and archive path survive all reminder-day interactions")

        state.refreshCurrentDay(at: date("2024-01-01 23:59"))
        state.selectedDay = date("2024-01-01 23:59")
        state.refreshCurrentDay(at: date("2024-01-02 00:01"))
        try expect(state.dayKey == "2024-01-02" && state.isTaskAtTop(scheduled),
                   "An open current-day board automatically promotes a task when its reminder day begins")
        state.refreshCurrentDay(at: date("2024-01-03 00:01"))
        try expect(state.dayKey == "2024-01-03" && !state.dailyCaptures.contains { $0.id == scheduled.id },
                   "Midnight automatically removes an unfinished reminded task after its single planned day")
        try schedule(future, on: "2024-01-02 10:00")
        state.selectedDay = date("2024-01-02 12:00")
        try expect(!state.isTaskAtTop(future) && !state.dailyCaptures.contains { $0.id == future.id },
                   "Even inconsistent imported reminder dates cannot display a task before its original receipt day")

        // The board uses the same current local date as its displayed reminder time.
        let localMidnight = date("2024-01-02 00:15")
        let foreignZone = TimeZone(secondsFromGMT: TimeZone.current.secondsFromGMT(for: localMidnight) > -12 * 3600 ? -12 * 3600 : 14 * 3600)!
        try store.update(scheduled, comment: scheduled.comment, reminderAt: localMidnight, reminderTimeZoneID: foreignZone.identifier)
        try expect(CaptureCalendar.dayString(localMidnight, timeZone: foreignZone) != "2024-01-02",
                   "Time-zone fixture places the saved reminder zone on a different date from its displayed local date")
        state.selectedDay = date("2024-01-02 12:00")
        try expect(state.isTaskAtTop(scheduled),
                   "A reminder promotes on its displayed current-local date even when its saved time zone has another date")
        state.selectedDay = date("2024-01-01 12:00")
        try expect(!state.isTaskAtTop(scheduled), "A reminder cannot promote on the preceding local date")
        state.selectedDay = date("2024-01-03 12:00")
        try expect(!state.isTaskAtTop(scheduled), "A reminder cannot promote on the following local date")
    }

    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinTaskState-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root)
        let client = TaskNotificationClient()
        let reminders = ReminderService(store: store, client: client)
        let state = AppState(store: store, previews: PreviewService(store: store), reminders: reminders)

        let creationOrigin = state.route
        state.openNewTask()
        try expect(state.route == .newTask && !state.hasUnsavedDrafts, "Plus opens an empty task draft")
        state.newTaskDraft.text = "  \n "
        state.saveNewTask()
        try expect(store.captures.isEmpty && state.newTaskDraft.message != nil, "Empty task cannot create a capture")
        state.newTaskDraft.text = "Review the studio brief"
        state.newTaskDraft.reminderEnabled = true
        state.newTaskDraft.reminderDate = Date().addingTimeInterval(-60)
        state.saveNewTask()
        try expect(store.captures.isEmpty && state.route == .newTask, "Past reminder preserves the draft and reports a validation error")

        let reminder = Date().addingTimeInterval(7200)
        state.newTaskDraft.reminderDate = reminder
        state.back()
        try expect(state.hasUnsavedDrafts && state.newTaskDraft.text == "Review the studio brief", "Leaving the form retains its unfinished draft")
        state.openNewTask()
        let browsedDay = Date().addingTimeInterval(-86400)
        state.selectedDay = browsedDay
        state.filter = .media
        state.saveNewTask()
        try expect(store.captures.count == 1 && state.route == creationOrigin, "Saving adds exactly one task and returns to the originating view")
        guard let capture = store.captures.first else { throw NSError(domain: "DaBinTaskTests", code: 2) }
        let originalStamp = capture.capturedAt
        try expect(capture.kind == .task && !capture.isCompleted, "New task starts incomplete")
        try expect(state.filter == .media && state.selectedDay == browsedDay && capture.captureDay == CaptureCalendar.dayString(Date()),
                   "Task creation records today's receipt while preserving the browsed date and filter")
        try expect(!state.hasUnsavedDrafts && state.newTaskDraft.text.isEmpty, "Saved draft clears only after persistence")
        try expect(capture.reminderAt == reminder, "Task and reminder are saved together")
        state.openDaily()
        try expect(state.route == .daily && state.filter == .all && state.dailyCaptures.contains { $0.id == capture.id },
                   "Explicit Daily navigation shows the new task on today's All board")
        await reminders.reconcile()
        try expect(client.requests.count == 1, "New task reminder is scheduled through the existing service")

        state.toggleTaskCompletion(capture)
        await reminders.reconcile()
        try expect(capture.isCompleted && client.requests.isEmpty, "Completing from a capture row cancels its reminder")
        try expect(capture.reminderAt == reminder && capture.capturedAt == originalStamp, "Completion preserves the planned time and original capture day")
        state.toggleTaskCompletion(capture)
        await reminders.reconcile()
        try expect(!capture.isCompleted && client.requests.count == 1, "Switching back to Task resumes a future reminder")

        state.query = "studio brief"
        try expect(state.searchGroups.flatMap(\.entries).contains { $0.capture.id == capture.id }, "Tasks participate in contextual search")
        let reopened = try CaptureStore(root: root)
        try expect(reopened.captures.count == 1 && reopened.captures[0].kind == .task && !reopened.captures[0].isCompleted,
                   "Task state survives store reopening")

        state.openNewTask()
        state.newTaskDraft.text = "An unfinished task"
        store.failureInjector = { point in
            if point == .beforeMetadataSave { throw NSError(domain: "TaskWriteFailure", code: 1) }
        }
        state.saveNewTask()
        try expect(store.captures.count == 1 && state.route == .newTask && state.newTaskDraft.text == "An unfinished task",
                   "Failed creation keeps the draft and does not add a false capture")
        store.failureInjector = nil
        state.cancelNewTask()
        try expect(!state.hasUnsavedDrafts && state.route == .daily, "Explicit Cancel clears the new-task draft")

        state.reportCaptureResult([], errors: ["The source did not provide a readable item."])
        try expect(state.status?.severity == .error && state.status?.symbol == "exclamationmark.circle",
                   "A failed capture has explicit error feedback, never a success glyph")
        state.reportCaptureResult([capture], errors: ["One attachment could not be read."])
        try expect(state.status?.severity == .warning && state.status?.symbol == "exclamationmark.triangle",
                   "A partially saved batch reports a warning")
        state.reportCaptureResult([capture], errors: [])
        try expect(state.status?.severity == .success && state.status?.symbol == "checkmark.circle",
                   "A fully saved capture reports success")
        state.openCapture(UUID())
        try expect(state.status?.severity == .error, "An unavailable capture reports failure")

        client.authorizationValue = .denied
        state.openNewTask()
        state.newTaskDraft.text = "Task whose notification permission is denied"
        state.newTaskDraft.reminderEnabled = true
        state.newTaskDraft.reminderDate = Date().addingTimeInterval(7200)
        state.saveNewTask()
        let denied = store.captures.first { $0.title == "Task whose notification permission is denied" }!
        try await waitUntil { denied.notificationState == "denied" && state.status?.severity == .warning }
        try expect(state.route == .daily && state.status?.text.contains("System Settings") == true,
                   "Denied task reminder permission is visible on Daily immediately after creation")
        try expect(!state.hasUnsavedDrafts && denied.reminderAt != nil,
                   "Notification denial keeps the saved task and reminder")

        client.authorizationValue = .allowed
        client.failScheduling = true
        state.retryReminder(denied)
        try await waitUntil { denied.notificationState == "failed" && state.status?.severity == .error }
        try expect(state.route == .daily && state.status?.text.contains("retry") == true,
                   "A scheduling failure remains visible on Daily with a recovery action")
        client.failScheduling = false
        state.retryReminder(denied)
        try await waitUntil { denied.notificationState == "scheduled" && state.status?.severity == .success }
        try expect(state.status?.text == "Reminder scheduled.", "Successful retry replaces the obsolete failure message")

        client.failScheduling = true
        // Change the desired date so the existing request must be replaced.
        state.openCapture(denied.id)
        state.selectedDraft!.reminderDate = Date().addingTimeInterval(10800)
        state.saveDetail()
        try await waitUntil { denied.notificationState == "failed" && state.status?.severity == .error }
        state.selectedDraft!.reminderEnabled = false
        state.saveDetail()
        try expect(denied.reminderAt == nil && state.status == nil && reminders.status == nil,
                   "Committed reminder clear removes its obsolete banner and detail service failure")
        await reminders.reconcile()
        try expect(denied.notificationState == "none" && state.status == nil,
                   "Reminder clear remains clean after asynchronous notification cleanup")

        state.selectedDraft!.reminderEnabled = true
        state.selectedDraft!.reminderDate = Date().addingTimeInterval(10800)
        state.saveDetail()
        try await waitUntil { denied.notificationState == "failed" && state.status?.severity == .error }
        state.status = nil
        state.toggleTaskCompletion(denied)
        try expect(denied.isCompleted && state.status == nil && reminders.status == nil,
                   "Completion removes stale reminder service feedback even after its banner was dismissed")
        await reminders.reconcile()
        state.toggleTaskCompletion(denied)
        try await waitUntil { denied.notificationState == "failed" && state.status?.severity == .error }

        client.pauseAuthorization = true
        state.retryReminder(denied)
        try await waitUntil { client.authorizationContinuation != nil }
        state.selectedDraft!.reminderEnabled = false
        state.saveDetail()
        state.reportFailure("A separate capture could not be read.")
        client.resumeAuthorization()
        await reminders.reconcile()
        try expect(denied.notificationState == "none" && state.status?.text == "A separate capture could not be read.",
                   "A late reminder result cannot replace newer feedback after the reminder was cleared")

        state.reportFailure("An unrelated file could not be opened.")
        state.toggleTaskCompletion(denied)
        try expect(state.status?.text == "An unrelated file could not be opened.",
                   "Completing a task preserves unrelated capture error feedback")
        try await checkCarryover(root: root.appendingPathComponent("Carryover"))
        try checkReminderDay(root: root.appendingPathComponent("ReminderDay"))
        try await checkBuddyTaskIntegration(root: root.appendingPathComponent("BuddyTasks"))
        print("PASS: \(checks) task workflow checks; isolated store and fake notifications.")
    }
}
