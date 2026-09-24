import Foundation

@MainActor
private final class WeeklyNotificationClient: ReminderNotificationClient {
    private(set) var permissionRequests = 0
    private(set) var scheduled: [ScheduledReminder] = []
    func authorization() async -> ReminderAuthorization { .allowed }
    func requestAuthorization() async throws -> Bool {
        permissionRequests += 1
        throw NSError(domain: "UnexpectedWeeklyPermissionRequest", code: 1)
    }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { scheduled.append(reminder) }
    func removePending(_ identifiers: [String]) {}
    func removeDelivered(_ identifiers: [String]) {}
}

@main
struct WeeklyStateTests {
    @MainActor private static var checks = 0

    @MainActor private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard condition() else {
            throw NSError(domain: "DaBinWeeklyStateTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private static func date(_ value: String) -> Date {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = .current
        parser.dateFormat = "yyyy-MM-dd HH:mm"
        return parser.date(from: value)!
    }

    private static func ids(_ values: [Capture]) -> [UUID] { values.map(\.id) }
    private static func keys(_ values: [Date]) -> [String] { values.map { CaptureCalendar.dayString($0) } }

    @MainActor private static func encodedCaptures(_ store: CaptureStore) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(store.captures.sorted { $0.id.uuidString < $1.id.uuidString }.map(CaptureSnapshot.init))
    }

    @MainActor private static func checkCalendar(_ state: AppState) throws {
        let ranges: [(String, [String])] = [
            ("2024-01-03", ["2023-12-28", "2023-12-29", "2023-12-30", "2023-12-31", "2024-01-01", "2024-01-02", "2024-01-03"]),
            ("2024-03-03", ["2024-02-26", "2024-02-27", "2024-02-28", "2024-02-29", "2024-03-01", "2024-03-02", "2024-03-03"]),
            ("2024-03-31", ["2024-03-25", "2024-03-26", "2024-03-27", "2024-03-28", "2024-03-29", "2024-03-30", "2024-03-31"]),
            ("2024-10-27", ["2024-10-21", "2024-10-22", "2024-10-23", "2024-10-24", "2024-10-25", "2024-10-26", "2024-10-27"])
        ]
        for (ending, expected) in ranges {
            state.selectedDay = date("\(ending) 12:00")
            state.openWeekly()
            let days = state.weeklyDays
            try expect(state.route == .weekly && keys(days) == expected,
                       "Week ending \(ending) has exactly seven local dates in oldest-to-newest order")
            try expect(Set(keys(days)).count == 7 && CaptureCalendar.dayString(state.weekEndingDay) == ending,
                       "Week ending \(ending) has no repeated dates and retains its selected date anchor")
            if TimeZone.current.secondsFromGMT(for: days.first!) != TimeZone.current.secondsFromGMT(for: days.last!) {
                let intervals = zip(days, days.dropFirst()).map { $1.timeIntervalSince($0) }
                try expect(intervals.contains { abs($0 - 86400) > 1 },
                           "A local daylight-saving boundary uses calendar days rather than fixed 24-hour increments")
            }
        }
    }

    @MainActor private static func checkNavigation(_ state: AppState, capture: Capture) throws {
        let originalDay = date("2024-01-03 12:00")
        state.selectedDay = originalDay
        state.filter = .tasks
        state.dailyScrollID = .capture(.capture(capture.id))
        let hour = AutomaticHourKey(capture: capture)
        state.toggleHourlyGroup(hour)
        try expect(state.isHourlyGroupExpanded(hour)
                   && state.dailyScrollID == .capture(.capture(capture.id)),
                   "Expanding an hourly summary preserves the existing Daily scroll anchor")
        state.toggleHourlyGroup(hour)
        try expect(!state.isHourlyGroupExpanded(hour)
                   && state.dailyScrollID == .capture(.capture(capture.id)),
                   "Collapsing an hourly summary preserves the existing Daily scroll anchor")
        state.newTaskDraft.text = "An unfinished weekly task draft"
        state.selectTimelineMode(.daily)
        try expect(state.timelineMode == .daily, "The board starts with Daily selected")
        state.selectTimelineMode(.weekly)
        try expect(state.route == .weekly && state.timelineMode == .weekly
                   && state.selectedDay == originalDay && state.filter == .tasks,
                   "Selecting Weekly preserves the selected date and active filter")
        try expect(state.newTaskDraft.text == "An unfinished weekly task draft" && state.hasUnsavedDrafts,
                   "Selecting Weekly preserves an existing new-task draft")
        state.moveWeek(-1)
        try expect(keys(state.weeklyDays) == ["2023-12-21", "2023-12-22", "2023-12-23", "2023-12-24", "2023-12-25", "2023-12-26", "2023-12-27"],
                   "Previous week moves the seven-day range backward by seven calendar days")
        try expect(state.selectedDay == originalDay, "Browsing a week does not silently change the Daily date")
        state.moveWeek(1)
        try expect(CaptureCalendar.dayString(state.weekEndingDay) == "2024-01-03",
                   "Next week reverses a previous-week step exactly")
        state.selectTimelineMode(.daily)
        try expect(state.route == .daily && state.timelineMode == .daily
                   && state.selectedDay == originalDay && state.filter == .tasks
                   && state.dailyScrollID == .capture(.capture(capture.id)),
                   "Selecting Daily restores the same date, filter and scroll target")
        state.selectTimelineMode(.daily)
        try expect(state.route == .daily && state.selectedDay == originalDay,
                   "Selecting the active Daily segment is idempotent")
        state.selectTimelineMode(.weekly)
        try expect(state.route == .weekly && CaptureCalendar.dayString(state.weekEndingDay) == "2024-01-03",
                   "Selecting Weekly again anchors seven days to the preserved Daily date")
        state.openCapture(capture.id, focus: "comment")
        let draft = state.selectedDraft!
        draft.comment = "A comment not saved yet"
        try expect(state.route == .detail && state.detailFocus == "comment", "A weekly record opens its real detail editor")
        state.back()
        try expect(state.route == .weekly && CaptureCalendar.dayString(state.weekEndingDay) == "2024-01-03",
                   "Back from a weekly record restores the same weekly range")
        state.openCapture(capture.id)
        try expect(state.selectedDraft === draft && state.selectedDraft?.comment == "A comment not saved yet",
                   "Reopening a weekly record retains its unsaved comment draft")
        state.back()
        state.back()
        try expect(state.route == .daily && state.selectedDay == originalDay && state.filter == .tasks,
                   "Back from Weekly returns to the original Daily date and filter")
        state.selectTimelineMode(.weekly)
        state.dailyScrollID = .capture(.capture(capture.id))
        let chosenDay = state.weeklyDays[2]
        state.selectWeeklyDay(chosenDay)
        try expect(state.route == .daily && state.dayKey == "2023-12-30" && state.dailyScrollID == nil,
                   "Choosing a column opens that day and clears an unrelated Daily scroll target")
        try expect(state.filter == .tasks && draft.comment == "A comment not saved yet" && state.newTaskDraft.hasChanges,
                   "Selecting a weekly day preserves both drafts and the active filter")
        state.openWeekly()
        state.showCurrentWeek()
        let todayKey = CaptureCalendar.dayString(Date())
        try expect(CaptureCalendar.dayString(state.weekEndingDay) == todayKey && keys(state.weeklyDays).last == todayKey,
                   "This week shows the seven dates ending today")
        state.moveWeek(1)
        try expect(CaptureCalendar.dayString(state.weekEndingDay) == todayKey,
                   "Advancing from the current week cannot reveal a future week")
        state.weekEndingDay = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        state.moveWeek(1)
        try expect(CaptureCalendar.dayString(state.weekEndingDay) == todayKey,
                   "An advance that would cross today clamps the range to today")
        let futureDay = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        state.selectWeeklyDay(futureDay)
        try expect(state.dayKey <= todayKey, "A direct weekly day selection cannot open a future Daily date")
    }

    @MainActor private static func checkRollover(_ state: AppState) throws {
        state.refreshCurrentDay(at: date("2024-01-31 23:58"))
        state.selectedDay = date("2024-01-31 12:00")
        state.openWeekly()
        state.refreshCurrentDay(at: date("2024-02-01 00:01"))
        try expect(state.route == .weekly && state.dayKey == "2024-02-01"
                   && keys(state.weeklyDays) == ["2024-01-26", "2024-01-27", "2024-01-28", "2024-01-29", "2024-01-30", "2024-01-31", "2024-02-01"],
                   "An open current week advances at midnight across a month boundary")
        state.refreshCurrentDay(at: date("2024-02-05 09:00"))
        try expect(state.dayKey == "2024-02-05" && CaptureCalendar.dayString(state.weekEndingDay) == "2024-02-05",
                   "Waking after several days advances a previously current weekly view")
        state.moveWeek(-1)
        let historicalRange = keys(state.weeklyDays)
        state.refreshCurrentDay(at: date("2024-02-06 09:00"))
        try expect(keys(state.weeklyDays) == historicalRange && state.route == .weekly,
                   "Midnight does not replace an intentionally browsed historical week")
        state.selectedDay = date("2023-12-31 12:00")
        state.weekEndingDay = date("2024-02-06 12:00")
        state.refreshCurrentDay(at: date("2024-02-07 09:00"))
        try expect(state.dayKey == "2023-12-31" && CaptureCalendar.dayString(state.weekEndingDay) == "2024-02-07",
                   "A current weekly range can advance without changing a historical Daily return date")
    }

    @MainActor private static func checkEmptyWeek() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinEmptyWeek-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root)
        let client = WeeklyNotificationClient()
        let state = AppState(store: store, previews: PreviewService(store: store),
                             reminders: ReminderService(store: store, client: client))
        let before = try encodedCaptures(store)
        let today = CaptureCalendar.dayString(Date())
        let expected = (0..<7).reversed().map {
            CaptureCalendar.dayString(Calendar.current.date(byAdding: .day, value: -$0, to: Date())!)
        }
        state.newTaskDraft.text = "Unsubmitted empty-week draft"
        for filter in CaptureFilter.allCases {
            state.route = .daily
            state.selectedDay = date("2024-01-03 12:00")
            state.weekEndingDay = date("2024-01-03 12:00")
            state.filter = filter
            state.selectTimelineMode(.weekly)
            try expect(state.route == .weekly && state.dayKey == "2024-01-03",
                       "The toggle opens Weekly from a historical empty Daily with \(filter.title) selected")
            let historicalExpected = (0..<7).reversed().map {
                CaptureCalendar.dayString(Calendar.current.date(byAdding: .day, value: -$0,
                    to: date("2024-01-03 12:00"))!)
            }
            try expect(keys(state.weeklyDays) == historicalExpected
                       && CaptureCalendar.dayString(state.weekEndingDay) == "2024-01-03",
                       "An empty \(filter.title) toggle keeps seven dates ending on the selected day")
            try expect(state.filter == filter && state.weeklyDays.count == 7 && state.weeklyVisibleDays.isEmpty,
                       "An empty \(filter.title) week keeps its seven-date range without rendering empty days")
            let emptyDay = state.weeklyDays[2]
            state.selectWeeklyDay(emptyDay)
            try expect(state.route == .daily && Calendar.current.isDate(state.selectedDay, inSameDayAs: emptyDay)
                       && state.dailyCaptures.isEmpty && state.filter == filter,
                       "Selecting an empty \(filter.title) day returns to its empty Daily view")
        }
        state.route = .daily
        state.refreshCurrentDay(at: date("2024-01-03 23:59"))
        state.showCurrentWeek()
        try expect(state.dayKey == today && keys(state.weeklyDays) == expected,
                   "The current-week command refreshes a stale clock before opening the empty current week")
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        state.refreshCurrentDay(at: tomorrow)
        try expect(state.dayKey == CaptureCalendar.dayString(tomorrow)
                   && CaptureCalendar.dayString(state.weekEndingDay) == CaptureCalendar.dayString(tomorrow),
                   "The current week opened from a stale clock still advances at the next midnight")
        try expect(state.newTaskDraft.text == "Unsubmitted empty-week draft" && state.newTaskDraft.hasChanges,
                   "Opening and selecting empty days preserves an unsaved task draft")
        let after = try encodedCaptures(store)
        let reopened = try CaptureStore(root: root)
        try expect(after == before && reopened.captures.isEmpty,
                   "Empty weekly navigation creates no records or persisted capture changes")
        try expect(client.permissionRequests == 0 && client.scheduled.isEmpty,
                   "Empty weekly navigation never requests or schedules notifications")
    }

    @MainActor private static func checkSparseWeek(root: URL) throws {
        let store = try CaptureStore(root: root)
        _ = try store.capture(text: "Sparse first note", at: date("2023-12-28 09:00"))
        _ = try store.capture(text: "Sparse middle note", at: date("2024-01-01 09:00"))
        let task = try store.createTask(text: "Sparse completed task", at: date("2024-01-03 09:00"))
        try store.setTaskCompleted(task, completed: true)
        let state = AppState(store: store, previews: PreviewService(store: store),
                             reminders: ReminderService(store: store, client: WeeklyNotificationClient()))
        state.selectedDay = date("2024-01-03 12:00")
        state.openWeekly()
        try expect(keys(state.weeklyDays) == ["2023-12-28", "2023-12-29", "2023-12-30", "2023-12-31", "2024-01-01", "2024-01-02", "2024-01-03"],
                   "A sparse week retains the complete seven-date navigation range")
        let active = ["2023-12-28", "2024-01-01", "2024-01-03"]
        try expect(keys(state.weeklyVisibleDays) == active,
                   "A sparse week renders only its three nonconsecutive active dates")
        for filter in CaptureFilter.allCases {
            state.filter = filter
            try expect(keys(state.weeklyVisibleDays) == active,
                       "The \(filter.title) filter does not reintroduce empty dates or hide active dates")
        }
    }

    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinWeeklyState-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root)
        let client = WeeklyNotificationClient()
        let reminders = ReminderService(store: store, client: client)
        let state = AppState(store: store, previews: PreviewService(store: store), reminders: reminders)
        let dayKeys = ["2023-12-28", "2023-12-29", "2023-12-30", "2023-12-31", "2024-01-01", "2024-01-02", "2024-01-03"]
        let notes = try dayKeys.map { try store.capture(text: "Weekly fictional note for \($0)", at: date("\($0) 17:00"))[0] }
        let carry = try store.createTask(text: "Unscheduled unfinished weekly task", at: date("2023-12-27 09:00"))
        let scheduled = try store.createTask(text: "Task due only on New Year's Day", at: date("2023-12-28 09:00"))
        try store.update(scheduled, comment: "Original planned context", reminderAt: date("2024-01-01 10:00"), reminderTimeZoneID: TimeZone.current.identifier)
        let completed = try store.createTask(text: "Completed weekly task", at: date("2023-12-29 10:00"))
        try store.setTaskCompleted(completed, completed: true)
        let sameDay = try store.createTask(text: "Created and due on the same day", at: date("2024-01-01 12:00"))
        try store.update(sameDay, comment: "Same-day context", reminderAt: date("2024-01-01 14:00"), reminderTimeZoneID: TimeZone.current.identifier)
        let laterTask = try store.createTask(text: "Task after the viewed range", at: date("2024-01-04 09:00"))
        let link = try store.capture(text: "https://example.invalid/weekly", at: date("2023-12-30 16:00"))[0]
        let document = try await store.importData(Data("Fictional weekly document".utf8), filename: "Weekly-fixture.txt", at: date("2023-12-31 16:00"))
        let imageBytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6pAAAAABJRU5ErkJggg==")!
        let image = try await store.importData(imageBytes, filename: "Weekly-fixture.png", at: date("2024-01-02 16:00"))
        let expected: [[UUID]] = [
            [carry.id, notes[0].id, scheduled.id],
            [carry.id, notes[1].id, completed.id],
            [carry.id, notes[2].id, link.id],
            [carry.id, notes[3].id, document.id],
            [sameDay.id, scheduled.id, carry.id, notes[4].id],
            [carry.id, notes[5].id, image.id],
            [carry.id, notes[6].id]
        ]
        let savedSnapshots = try encodedCaptures(store)
        let folders = Dictionary(uniqueKeysWithValues: store.captures.map { ($0.id, store.archiveURL(for: $0)) })
        let archivedRecords = try Dictionary(uniqueKeysWithValues: store.captures.map { capture in
            (capture.id, try Data(contentsOf: store.archiveURL(for: capture)!.appendingPathComponent("Capture.json")))
        })
        state.selectedDay = date("2024-01-03 12:00")
        state.openWeekly()
        try expect(keys(state.weeklyVisibleDays) == dayKeys,
                   "A fully active week renders all seven dates")
        let selectedBeforeReading = state.selectedDay
        let rangeBeforeReading = state.weekEndingDay
        for (index, day) in state.weeklyDays.enumerated() {
            let captures = state.captures(for: day)
            try expect(ids(captures) == expected[index], "Weekly \(dayKeys[index]) has the correct records and task-first ordering")
            try expect(Set(ids(captures)).count == captures.count, "Weekly \(dayKeys[index]) never duplicates a record within a column")
            try expect(state.isTaskAtTop(carry, on: day), "An unfinished unscheduled task carries to \(dayKeys[index])")
            try expect(state.isTaskAtTop(scheduled, on: day) == (dayKeys[index] == "2024-01-01"),
                       "The scheduled task is promoted only on its reminder date")
            try expect(!captures.contains { $0.id == laterTask.id } && !state.isTaskAtTop(completed, on: day),
                       "Weekly columns exclude later receipts and never promote completed tasks")
        }
        try expect(state.selectedDay == selectedBeforeReading && state.weekEndingDay == rangeBeforeReading,
                   "Reading all seven columns does not mutate Daily or Weekly navigation")
        for filter in CaptureFilter.allCases {
            state.filter = filter
            try expect(keys(state.weeklyVisibleDays) == dayKeys,
                       "The \(filter.title) filter preserves the active-date columns")
            let values = state.weeklyDays.flatMap { state.captures(for: $0) }
            switch filter {
            case .all: try expect(values.count == expected.flatMap { $0 }.count, "All filter restores all seven columns")
            case .text: try expect(ids(values) == notes.map(\.id), "Text filter applies across the whole week")
            case .links: try expect(ids(values) == [link.id], "Links filter applies across the whole week")
            case .files: try expect(ids(values) == [document.id], "Files filter applies across the whole week")
            case .media: try expect(ids(values) == [image.id], "Media filter applies across the whole week")
            case .tasks:
                try expect(values.allSatisfy(\.isTask) && values.contains { $0.id == completed.id }
                           && values.filter { $0.id == scheduled.id }.count == 2 && values.filter { $0.id == sameDay.id }.count == 1,
                           "Tasks filter retains original-day completed records and reminder-day visibility without same-day duplicates")
            }
        }
        state.filter = .all
        try checkCalendar(state)
        try checkNavigation(state, capture: scheduled)
        try checkRollover(state)
        try checkEmptyWeek()
        try checkSparseWeek(root: root.appendingPathComponent("Sparse"))
        let snapshotsAfterBrowsing = try encodedCaptures(store)
        try expect(snapshotsAfterBrowsing == savedSnapshots, "Weekly browsing leaves every persisted capture field unchanged")
        try expect(store.captures.allSatisfy { store.archiveURL(for: $0) == folders[$0.id]! },
                   "Weekly browsing never relocates original archive folders")
        let recordsAfterBrowsing = try Dictionary(uniqueKeysWithValues: store.captures.map { capture in
            (capture.id, try Data(contentsOf: store.archiveURL(for: capture)!.appendingPathComponent("Capture.json")))
        })
        try expect(recordsAfterBrowsing == archivedRecords, "Weekly browsing leaves readable archive records byte-for-byte unchanged")
        let reopened = try CaptureStore(root: root)
        let reopenedSnapshots = try encodedCaptures(reopened)
        try expect(reopenedSnapshots == savedSnapshots, "Reopening storage confirms Weekly created no duplicates or mutations")
        try expect(client.permissionRequests == 0 && client.scheduled.isEmpty,
                   "Weekly browsing never asks for notifications or schedules an alert")
        print("PASS: \(checks) weekly state checks; isolated store, local calendar, fake notifications.")
    }
}
