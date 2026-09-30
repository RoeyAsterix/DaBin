import Foundation

@main
struct TaskPlanningTests {
    @MainActor private static var checks = 0
    @MainActor private static func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard value() else { throw NSError(domain: "TaskPlanningTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    private static func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    @MainActor static func main() throws {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinTaskPlanning-\(UUID().uuidString)")
        let root = workspace.appendingPathComponent("Live")
        defer { try? FileManager.default.removeItem(at: workspace) }
        let store = try CaptureStore(root: root)
        let now = date("2026-09-30T12:00:00Z")
        let zone = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        var plan = TaskPlanning(plannedDay: "2026-09-30", deadline: date("2026-10-02T17:00:00Z"),
                                priority: .high, effortMinutes: 45, recurrence: .weekly,
                                checklist: [TaskChecklistItem(text: "Review the client notes"), TaskChecklistItem(text: "Send a reply")])
        let task = try store.createTask(text: "Fictional client follow-up", at: now, timeZone: zone, planning: plan)
        try store.setOrganization(task, pinned: false, projectName: "Studio Example")
        let reminder = Date().addingTimeInterval(86_400)
        try store.update(task, comment: "Keep original feedback", reminderAt: reminder, reminderTimeZoneID: zone.identifier)
        let receipt = (task.capturedAt, task.captureDay, task.originalText)
        try expect(task.taskPlanning?.plannedDay == plan.plannedDay && task.taskPlanning?.deadline == plan.deadline
                   && task.reminderAt == reminder, "Planned day, deadline, and reminder are independent")
        try expect(TaskPlanningPolicy.today(store.captures, at: now, calendar: calendar).map(\.id) == [task.id], "Today contains the chosen work date")
        let inbox = try store.createTask(text: "Unplanned commitment", at: now, timeZone: zone)
        try expect(TaskPlanningPolicy.inbox(store.captures).map(\.id) == [inbox.id], "Legacy and unplanned tasks remain in the task inbox")
        let gathered = try store.capture(text: "Collected project research", at: now)[0]
        let gatheredReceipt = CaptureSnapshot(gathered)
        store.failureInjector = { if $0 == .beforeMetadataSave { throw CaptureStoreError.importVerificationFailed } }
        do { try store.attachCapture(gathered, to: task); throw NSError(domain: "ExpectedFailure", code: 1) }
        catch CaptureStoreError.importVerificationFailed {}
        try expect(gathered.parentTaskID == nil && gathered.projectName == nil, "A failed attachment preserves its independent identity and project")
        store.failureInjector = nil
        try store.attachCapture(gathered, to: task)
        try expect(gathered.parentTaskID == task.id && gathered.projectName == task.projectName
                   && gathered.id == gatheredReceipt.id && gathered.capturedAt == gatheredReceipt.capturedAt
                   && gathered.originalText == gatheredReceipt.originalText,
                   "Attaching a collection item keeps its original receipt and inherits an unset project")
        do { try store.attachCapture(gathered, to: inbox); throw NSError(domain: "ExpectedFailure", code: 1) }
        catch CaptureStoreError.invalidOriginal {}
        try expect(gathered.parentTaskID == task.id, "An existing attachment cannot be silently moved between tasks")
        try store.planTask(task, on: "2026-10-01")
        try expect(task.taskPlanning?.plannedDay == "2026-10-01" && task.taskPlanning?.deadline == plan.deadline && task.reminderAt == reminder,
                   "Rescheduling work never silently changes a deadline or reminder")
        try expect(task.capturedAt == receipt.0 && task.captureDay == receipt.1 && task.originalText == receipt.2, "Rescheduling preserves the immutable receipt")
        try store.planTask(task, on: "2026-09-30")
        try store.planTask(inbox, on: "2026-09-30")
        try store.reorderTasks([inbox, task], on: "2026-09-30")
        try expect(TaskPlanningPolicy.today(store.captures, at: now, calendar: calendar).map(\.id) == [inbox.id, task.id], "Today follows a persisted manual order")

        let priorPlan = task.taskPlanning
        store.failureInjector = { if $0 == .beforeMetadataSave { throw CaptureStoreError.importVerificationFailed } }
        do { try store.planTask(task, on: "2026-10-05"); throw NSError(domain: "ExpectedFailure", code: 1) }
        catch CaptureStoreError.importVerificationFailed {}
        try expect(task.taskPlanning == priorPlan, "A failed reschedule restores the plan")
        do { try store.reorderTasks([task, inbox], on: "2026-09-30"); throw NSError(domain: "ExpectedFailure", code: 1) }
        catch CaptureStoreError.importVerificationFailed {}
        try expect(TaskPlanningPolicy.today(store.captures, at: now, calendar: calendar).map(\.id) == [inbox.id, task.id], "A failed reorder rolls back every task")
        plan.plannedDay = "2026-10-10"
        do {
            try store.update(task, comment: "Do not persist", reminderAt: nil, reminderTimeZoneID: nil, planning: plan)
            throw NSError(domain: "ExpectedFailure", code: 1)
        } catch CaptureStoreError.importVerificationFailed {}
        try expect(task.comment == "Keep original feedback" && task.reminderAt == reminder && task.taskPlanning == priorPlan,
                   "Task detail saves comment, reminder, and plan atomically")
        let countBeforeCompletion = store.captures.count
        do { try store.setTaskCompleted(task, completed: true, at: now); throw NSError(domain: "ExpectedFailure", code: 1) }
        catch CaptureStoreError.importVerificationFailed {}
        try expect(!task.isCompleted && task.taskPlanning == priorPlan && store.captures.count == countBeforeCompletion,
                   "Failed recurring completion creates no successor and restores the task")
        store.failureInjector = nil

        let attachment = try store.capture(text: "A linked brief stays with its original occurrence", at: now, parentTask: task)[0]
        var checked = task.taskPlanning!
        checked.checklist[0].isCompleted = true
        try store.setTaskPlanning(task, planning: checked)
        guard let next = try store.setTaskCompleted(task, completed: true, at: now) else {
            throw NSError(domain: "MissingNextOccurrence", code: 1)
        }
        try expect(task.isCompleted && task.taskPlanning?.nextOccurrenceID == next.id, "Completion atomically connects the next occurrence")
        try expect(next.taskPlanning?.plannedDay == "2026-10-07" && next.taskPlanning?.deadline == date("2026-10-09T17:00:00Z"),
                   "Weekly recurrence advances the work date and relative deadline")
        try expect(next.projectName == task.projectName && next.comment == task.comment && next.originalText == task.originalText,
                   "Recurring routines retain the client's text, project, and notes")
        try expect(next.taskPlanning?.previousOccurrenceID == task.id && store.attachments(for: next).isEmpty && attachment.parentTaskID == task.id,
                   "Recurrence links the previous occurrence and never duplicates attachment originals")
        try expect(next.taskPlanning?.checklist.allSatisfy { !$0.isCompleted } == true, "A new occurrence starts with unchecked steps")
        let countAfterCompletion = store.captures.count
        try store.setTaskCompleted(task, completed: false, at: now)
        try store.setTaskCompleted(task, completed: true, at: now)
        try expect(store.captures.count == countAfterCompletion, "Reopening and completing an occurrence cannot duplicate its successor")

        let reopened = try CaptureStore(root: root)
        let restored = reopened.captures.first { $0.id == next.id }!
        try expect(restored.taskPlanning == next.taskPlanning && restored.projectName == "Studio Example", "Plans, recurrence, estimates, and checklist survive restart")
        let backup = workspace.appendingPathComponent("TaskPlanningBackup.dabinbackup", isDirectory: true)
        try store.exportBackup(to: backup)
        let backupStore = try CaptureStore(root: workspace.appendingPathComponent("RestoredBackup"))
        _ = try backupStore.restoreBackup(from: backup)
        try expect(backupStore.captures.first { $0.id == next.id }?.taskPlanning == next.taskPlanning,
                   "Portable backup and restore preserve the complete work plan and recurrence lineage")
        let snapshot = CaptureSnapshot(task)
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as! [String: Any]
        legacy.removeValue(forKey: "taskPlanning")
        for version in 1...8 {
            legacy["schemaVersion"] = version
            let decoded = try JSONDecoder().decode(CaptureSnapshot.self, from: JSONSerialization.data(withJSONObject: legacy))
            try expect(Capture(snapshot: decoded).taskPlanning == nil, "Schema \(version) opens without a planning migration")
        }
        try expect(TaskPlanningPolicy.date(for: "2026-02-31") == nil && TaskPlanningPolicy.date(for: "2026-9-30") == nil,
                   "Invalid or ambiguous work dates are rejected")
        try expect(TaskPlanning(plannedDay: "2026-09-30", effortMinutes: 0).isValid == false, "Invalid estimates do not persist")
        try expect(TaskPlanning(checklist: [TaskChecklistItem(text: "   ")]).isValid == false, "Empty checklist steps do not persist")
        let friday = date("2026-10-02T12:00:00Z")
        try expect(TaskRecurrence.weekdays.nextDate(after: friday, notBefore: friday, calendar: calendar) == date("2026-10-05T12:00:00Z"),
                   "Weekday routines skip the weekend")
        try expect(TaskRecurrence.weekly.nextDate(after: now, notBefore: date("2026-11-10T12:00:00Z"), calendar: calendar) == date("2026-11-11T12:00:00Z"),
                   "Late completion produces one future occurrence, not a backlog")
        let january = date("2026-01-31T12:00:00Z")
        try expect(TaskRecurrence.monthly.nextDate(after: january, notBefore: date("2026-03-01T12:00:00Z"), calendar: calendar) == date("2026-03-31T12:00:00Z"),
                   "Monthly recurrence preserves the anchor day after short months")
        let monthly = try store.createTask(text: "Monthly invoice routine", at: january, timeZone: zone,
            planning: TaskPlanning(plannedDay: "2026-01-31", recurrence: .monthly))
        let february = try store.setTaskCompleted(monthly, completed: true, at: january)!
        let march = try store.setTaskCompleted(february, completed: true, at: date("2026-02-28T12:00:00Z"))!
        try expect(february.taskPlanning?.plannedDay == "2026-02-28" && march.taskPlanning?.plannedDay == "2026-03-31",
                   "Successive stored occurrences preserve the original monthly cadence")
        let april = try store.setTaskCompleted(march, completed: true, at: date("2026-03-01T12:00:00Z"))!
        try expect(april.taskPlanning?.plannedDay == "2026-04-30", "Early completion advances beyond the occurrence that was completed")
        let afternoon = try store.createTask(text: "Friday afternoon review", at: now, timeZone: zone,
            planning: TaskPlanning(deadline: date("2026-10-02T17:00:00Z"), recurrence: .weekly))
        let firstFriday = try store.setTaskCompleted(afternoon, completed: true, at: date("2026-10-02T12:00:00Z"))!
        let secondFriday = try store.setTaskCompleted(firstFriday, completed: true, at: date("2026-10-09T12:00:00Z"))!
        try expect(firstFriday.taskPlanning?.plannedDay == "2026-10-09"
                   && secondFriday.taskPlanning?.plannedDay == "2026-10-16"
                   && secondFriday.taskPlanning?.deadline == date("2026-10-16T17:00:00Z"),
                   "Finishing before an afternoon cadence advances to the next day occurrence without duplicating today's task")
        var dstCalendar = calendar
        dstCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        let beforeDST = date("2026-03-07T14:00:00Z")
        try expect(TaskRecurrence.daily.nextDate(after: beforeDST, notBefore: beforeDST, calendar: dstCalendar) == date("2026-03-08T13:00:00Z"),
                   "Recurrence retains the local time through daylight-saving changes")
        print("PASS: \(checks) task planning checks; synthetic local archive only.")
    }
}
