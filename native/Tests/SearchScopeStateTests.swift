import AppKit
import Foundation

@MainActor private final class ScopedSearchNotifications: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .allowed }
    func requestAuthorization() async throws -> Bool { fatalError("Search QA never asks for permission") }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { fatalError("Search QA never schedules notifications") }
    func removePending(_ identifiers: [String]) {}
    func removeDelivered(_ identifiers: [String]) {}
}

/// Fictional archives, isolated preferences and a named (not general) clipboard.
/// No windows, clipboard reads, permission prompts, network or installed app.
@main struct SearchScopeStateTests {
    @MainActor private static var checks = 0

    @MainActor private static func expect(_ pass: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard pass() else { throw NSError(domain: "SearchScopeStateTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    private static func date(_ day: String, time: String = "12:00", zone: TimeZone = .current) -> Date {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = zone
        parser.dateFormat = "yyyy-MM-dd HH:mm"
        return parser.date(from: day + " " + time)!
    }

    @MainActor private static func matches(_ state: AppState) -> Set<UUID> {
        Set(state.searchGroups.flatMap(\.entries).filter(\.isMatch).map { $0.capture.id })
    }

    @MainActor private static func entries(_ state: AppState) -> Set<UUID> {
        Set(state.searchGroups.flatMap(\.entries).map { $0.capture.id })
    }

    @MainActor private static func calendarCases(_ state: AppState) throws {
        let cases: [(String, String, [String])] = [
            ("UTC", "2024-01-03", ["2023-12-28", "2023-12-29", "2023-12-30", "2023-12-31", "2024-01-01", "2024-01-02", "2024-01-03"]),
            ("UTC", "2024-03-03", ["2024-02-26", "2024-02-27", "2024-02-28", "2024-02-29", "2024-03-01", "2024-03-02", "2024-03-03"]),
            ("America/New_York", "2024-03-10", ["2024-03-04", "2024-03-05", "2024-03-06", "2024-03-07", "2024-03-08", "2024-03-09", "2024-03-10"]),
            ("America/New_York", "2024-11-03", ["2024-10-28", "2024-10-29", "2024-10-30", "2024-10-31", "2024-11-01", "2024-11-02", "2024-11-03"]),
            ("Asia/Jerusalem", "2024-03-31", ["2024-03-25", "2024-03-26", "2024-03-27", "2024-03-28", "2024-03-29", "2024-03-30", "2024-03-31"]),
            ("Europe/Berlin", "2024-10-27", ["2024-10-21", "2024-10-22", "2024-10-23", "2024-10-24", "2024-10-25", "2024-10-26", "2024-10-27"])
        ]
        let navigationDay = state.selectedDay, navigationWeek = state.weekEndingDay
        state.searchProject = "Alpha"
        state.searchSource = "Editor"
        state.filter = .files
        state.query = "archive beacon"
        for (zoneName, ending, expected) in cases {
            let zone = TimeZone(identifier: zoneName)!
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            state.searchScrollID = UUID()
            state.searchDateAnchor = "2024-01-01"
            state.setSearchWeek(ending: date(ending, zone: zone), calendar: calendar)
            try expect(state.searchScope == .week(Set(expected)), "\(zoneName) week ending \(ending) has seven unique civil days")
            try expect(CaptureCalendar.dayString(state.searchWeekEndingDay, timeZone: zone) == ending
                && state.searchScrollID == nil && state.searchDateAnchor == nil,
                "The week picker retains its scope anchor and discards stale result positions")
            try expect(state.query == "archive beacon" && state.searchProject == "Alpha"
                && state.searchSource == "Editor" && state.filter == .files,
                "Changing a week during a live query preserves every other refinement")
            if zoneName != "UTC" {
                let start = calendar.date(byAdding: .day, value: -6, to: state.searchWeekEndingDay)!
                // Spring New York changes after midnight on the final day.
                let afterEnd = calendar.date(byAdding: .day, value: 1, to: state.searchWeekEndingDay)!
                try expect(abs(afterEnd.timeIntervalSince(start) - 7 * 86400) > 1,
                    "\(zoneName) test crosses an actual daylight-saving transition without fixed-second arithmetic")
            }
        }
        try expect(state.selectedDay == navigationDay && state.weekEndingDay == navigationWeek,
            "Search pickers never change the Daily or Weekly return date")
        let zone = TimeZone(identifier: "Asia/Jerusalem")!
        state.setSearchRange(start: date("2024-03-31", zone: zone), end: date("2024-03-25", zone: zone), timeZone: zone)
        try expect(state.searchScope == .range(startDay: "2024-03-25", endDay: "2024-03-31")
            && state.searchRangeStartDay <= state.searchRangeEndDay, "A reversed range normalizes both civil bounds and picker dates")
        try expect(state.searchScope.includes(captureDay: "2024-03-25") && state.searchScope.includes(captureDay: "2024-03-31")
            && !state.searchScope.includes(captureDay: "2024-03-24") && !state.searchScope.includes(captureDay: "2024-04-01"),
            "Custom range boundaries are inclusive, including a DST week")
        state.setSearchRange(start: date("2024-02-29", zone: zone), end: date("2024-02-29", time: "23:59", zone: zone), timeZone: zone)
        try expect(state.searchScope == .range(startDay: "2024-02-29", endDay: "2024-02-29")
            && state.searchScopeTitle.contains("2024"), "A one-day custom range includes a leap day and has a readable title")
        state.searchAllDates()
        try expect(state.searchScope == .all && state.query == "archive beacon" && state.searchProject == "Alpha"
            && state.searchSource == "Editor" && state.filter == .files, "All dates only broadens the time window")
    }

    @MainActor private static func projectAndDateCases(_ state: AppState, root: URL) async throws {
        let store = state.store
        let anchor = date("2024-03-09", time: "10:00")
        let receipt = CaptureReceiptContext.automatic(.automaticClipboard, sourceApplicationName: "Editor",
            sourceApplicationBundleIdentifier: "test.editor")
        let before = try store.capture(text: "Quiet neighboring material", at: anchor.addingTimeInterval(-2), receipt: receipt, projectName: "Alpha")[0]
        let alpha = try store.capture(text: "Scope beacon", at: anchor, receipt: receipt, projectName: "Alpha")[0]
        let beta = try store.capture(text: "Scope beacon", at: anchor.addingTimeInterval(1), receipt: receipt, projectName: "Beta")[0]
        let unfiled = try store.capture(text: "Scope beacon", at: anchor.addingTimeInterval(2), receipt: receipt)[0]
        let after = try store.capture(text: "A second quiet neighbor", at: anchor.addingTimeInterval(3), receipt: receipt, projectName: "Alpha")[0]
        let otherSource = try store.capture(text: "Scope beacon", at: anchor.addingTimeInterval(4),
            receipt: .automatic(.automaticClipboard, sourceApplicationName: "Other", sourceApplicationBundleIdentifier: "test.other"), projectName: "Alpha")[0]
        var dates: [String: Capture] = [:]
        for day in ["2024-03-07", "2024-03-08", "2024-03-10", "2024-03-11"] {
            dates[day] = try store.capture(text: "Scope beacon", at: date(day), receipt: receipt, projectName: "Alpha")[0]
        }
        state.libraryProject = "Alpha"
        state.route = .library
        state.workspace.sourceApplication = "Editor"
        state.filter = .text
        state.query = "scope beacon"
        state.showSearchContext = true
        state.openSearch()
        try expect(state.searchProject == nil && !state.searchUnfiledOnly && state.searchSource == nil
            && state.filter == .all && state.searchScope == .all && !state.showSearchContext,
            "Fresh Projects search clears implicit project, source, type, date and nearby context")
        try expect(matches(state).isSuperset(of: [alpha.id, beta.id, unfiled.id, otherSource.id]
            + dates.values.map(\.id)), "The first query finds its words across projects, sources and stored dates")
        try expect(state.libraryProject == "Alpha" && state.workspace.sourceApplication == "Editor",
            "Global entry keeps the browsing project and its source preference for return")
        state.selectSearchProject("Alpha")
        state.searchSource = "Editor"
        state.filter = .text
        state.setSearchDay(anchor)
        try expect(matches(state) == [alpha.id], "Identical words in other projects, dates and sources are excluded")
        state.showSearchContext = true
        try expect(entries(state) == [before.id, alpha.id, after.id], "Nearby context remains inside the eligible project, date and source")
        let neighborFile = root.appendingPathComponent("quiet neighboring document.txt")
        try Data("Unrelated document context".utf8).write(to: neighborFile)
        let otherType = try await store.importFile(neighborFile, at: anchor.addingTimeInterval(-1), receipt: receipt, projectName: "Alpha")
        try expect(entries(state).contains(otherType.id) && !matches(state).contains(otherType.id)
            && state.searchGroups.flatMap(\.entries).contains { $0.capture.id == otherType.id && !$0.isMatch },
            "An eligible different-type neighbor can appear as explicitly labeled nearby context, never as a Text match")
        state.showSearchContext = false
        try expect(!entries(state).contains(otherType.id), "Different-type context disappears when nearby context is off")
        state.setSearchRange(start: date("2024-03-10"), end: date("2024-03-08"))
        try expect(matches(state) == [dates["2024-03-08"]!.id, alpha.id, dates["2024-03-10"]!.id],
            "Live reversed custom ranges include both endpoints and omit every outside receipt")
        try store.update(dates["2024-03-07"]!, comment: "Edited today, captured earlier", reminderAt: nil, reminderTimeZoneID: nil)
        try expect(!matches(state).contains(dates["2024-03-07"]!.id), "Editing a capture cannot move its immutable receipt into a selected range")
        state.setSearchDay(anchor)
        state.searchUnfiledProject()
        try expect(matches(state) == [unfiled.id] && state.searchUnfiledOnly, "Unfiled is a real project scope, distinct from every project")
        state.selectSearchProject(nil)
        try expect(matches(state) == [alpha.id, beta.id, unfiled.id] && !state.searchUnfiledOnly, "All projects deliberately includes every matching project")
        state.searchUnfiledProject()
        state.searchProject = "Beta"
        try expect(matches(state) == [beta.id] && !state.searchUnfiledOnly, "Direct named-project selection clears an earlier Unfiled refinement")
        state.searchEverything()
        try expect(state.searchScope == .all && state.searchProject == nil && !state.searchUnfiledOnly
            && state.searchSource == nil && state.filter == .all && state.query == "scope beacon",
            "Search Everything explicitly resets refinements without losing the query")
        try expect(matches(state).contains(otherSource.id), "Search Everything really includes a formerly excluded source")

        let file = root.appendingPathComponent("identical brief.txt")
        try Data("An archive beacon lives inside this file.".utf8).write(to: file)
        let parent = try store.createTask(text: "Parent obligation", at: anchor, projectName: "Alpha")
        let child = try await store.importFile(file, at: anchor, receipt: receipt, projectName: "Beta")
        let betaFile = try await store.importFile(file, at: anchor, receipt: receipt, projectName: "Beta")
        try store.attachCapture(child, to: parent)
        // Synthetic already-indexed body, independent of document extraction.
        child.indexedText = "An archive beacon lives inside this file."
        betaFile.indexedText = child.indexedText
        try store.update(child, comment: "", reminderAt: nil, reminderTimeZoneID: nil)
        state.selectSearchProject("Alpha")
        state.searchSource = "Editor"
        state.filter = .files
        state.query = "archive beacon"
        state.setSearchDay(anchor)
        try expect(child.projectName == "Beta" && child.parentTaskID == parent.id, "The fixture retains a stale child project to exercise live inheritance")
        try expect(matches(state) == [child.id] && state.searchGroups.flatMap(\.entries).first?.indexedTextMatch != nil,
            "Project-only file search finds indexed attachment text, not a same-name file from another project")
        state.query = "Alpha archive beacon"
        try expect(matches(state) == [child.id], "Attachment project-name search uses the parent's effective project")
        state.query = "Beta archive beacon"
        try expect(matches(state).isEmpty, "A stale attachment project name is not searchable metadata")
        state.query = "archive beacon"
        try store.setOrganization(parent, pinned: false, projectName: "Beta")
        try expect(matches(state).isEmpty, "Moving a parent invalidates cached search membership immediately")
        state.selectSearchProject("Beta")
        try expect(matches(state) == [child.id, betaFile.id], "A moved task carries all attachment results into its new project")
        try store.setOrganization(parent, pinned: false, projectName: nil)
        state.searchUnfiledProject()
        try expect(matches(state) == [child.id], "An unfiled parent overrides a child's stale named project")
        state.query = "Beta archive beacon"
        try expect(matches(state).isEmpty, "Explicit unfiled metadata also suppresses a stale project name")
        state.query = "archive beacon"
        try store.moveToTrash(parent)
        try expect(matches(state).isEmpty, "Trashing a task removes the task's attachment results from cached search")
        let trashedParent = store.trashedCaptures.first { $0.id == parent.id }!
        try store.restoreFromTrash(trashedParent)
        try expect(matches(state) == [child.id], "Restoring the task restores attachment search membership")
        state.filter = .text
        state.showSearchContext = true
        state.selectSearchProject("Alpha")
        state.query = "scope beacon"
        try expect(!entries(state).contains(child.id) && !entries(state).contains(betaFile.id),
            "Nearby text context never returns file neighbors outside the selected project")

        let safari = try store.capture(text: "Bundle only source beacon", at: anchor,
            receipt: .automatic(.automaticClipboard, sourceApplicationName: nil, sourceApplicationBundleIdentifier: "com.apple.Safari"), projectName: "Alpha")[0]
        state.searchSource = "Safari"
        state.query = "source beacon"
        try expect(matches(state) == [safari.id], "Source filtering uses the same friendly bundle-ID fallback as Explorer")
        let planning = TaskPlanning(plannedDay: "2024-03-10")
        let scheduled = try store.createTask(text: "Scheduled receipt beacon", at: anchor, planning: planning, projectName: "Alpha")
        state.searchSource = nil
        state.filter = .tasks
        state.query = "scheduled receipt"
        try expect(matches(state) == [scheduled.id], "Task search uses its immutable receipt day, not its scheduled day")
        state.setSearchDay(date("2024-03-10"))
        try expect(matches(state).isEmpty, "A scheduled task is not repeated in search on its planned day")

        let receiptZone = TimeZone(identifier: "Pacific/Honolulu")!
        let acrossMidnight = date("2024-06-02", time: "00:30", zone: TimeZone(secondsFromGMT: 0)!)
        let receiptDay = try store.capture(text: "Timezone receipt beacon", at: acrossMidnight, timeZone: receiptZone, projectName: "Alpha")[0]
        state.filter = .text
        state.query = "timezone receipt"
        state.setSearchDay(acrossMidnight, timeZone: receiptZone)
        try expect(state.searchScope == .day("2024-06-01") && matches(state) == [receiptDay.id],
            "Search retains the stored captureDay even when the absolute receipt is on another UTC date")
        state.setSearchDay(acrossMidnight, timeZone: TimeZone(secondsFromGMT: 0)!)
        try expect(matches(state).isEmpty, "Changing search timezone does not recalculate immutable capture-day membership")
        state.showSearchContext = false

        let bodyFile = root.appendingPathComponent("plain original.txt")
        let bodyBytes = Data("A starlight document beacon is buried in the original body.\nIts filename is deliberately unrelated.".utf8)
        try bodyBytes.write(to: bodyFile)
        let bodyAlpha = try await store.importFile(bodyFile, at: anchor, receipt: receipt, projectName: "Alpha")
        let bodyBeta = try await store.importFile(bodyFile, at: anchor, receipt: receipt, projectName: "Beta")
        let bodyAnotherDay = try await store.importFile(bodyFile, at: date("2024-03-10"), receipt: receipt, projectName: "Alpha")
        state.selectSearchProject("Alpha")
        state.searchSource = "Editor"
        state.filter = .files
        state.query = "starlight document beacon"
        state.setSearchDay(anchor)
        try expect(matches(state).isEmpty, "An unrelated document filename cannot satisfy a body-only query before indexing")
        let indexing = ContentIndexService(store: store)
        defer { indexing.shutdown() }
        indexing.process([bodyAlpha, bodyBeta, bodyAnotherDay])
        let deadline = Date().addingTimeInterval(8)
        while indexing.isBusy && Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try expect(!indexing.isBusy && [bodyAlpha, bodyBeta, bodyAnotherDay].allSatisfy { $0.contentIndexState == "ready" },
            "The real local TXT extractor indexes each fictional managed document without network access")
        try expect(matches(state) == [bodyAlpha.id] && state.searchGroups.flatMap(\.entries).first?.indexedTextMatch?.contains("starlight") == true,
            "Index completion invalidates the cached query and only the selected project's selected-day file body is returned")
        let retainedBytes = try Data(contentsOf: store.managedURL(for: bodyAlpha)!)
        try expect(retainedBytes == bodyBytes,
            "Indexing and scoped search leave the original file bytes unchanged")
        state.setSearchRange(start: anchor, end: date("2024-03-10"))
        try expect(matches(state) == [bodyAlpha.id, bodyAnotherDay.id], "Expanding a live range includes matching file bodies at both boundaries")
        state.selectSearchProject("Beta")
        try expect(matches(state) == [bodyBeta.id], "Changing project during a body query excludes identical text in other projects")

        state.back()
        state.showSearchContext = true
        state.openSearch()
        try expect(state.searchProject == nil && state.searchSource == nil && state.filter == .all
            && state.searchScope == .all && !state.showSearchContext
            && matches(state) == [bodyAlpha.id, bodyBeta.id, bodyAnotherDay.id],
            "A fresh first-pass global query finds indexed document bodies outside the old project and day")
        try expect(state.libraryProject == "Alpha" && state.workspace.sourceApplication == "Editor",
            "Finding a body in another project leaves capture routing and Explorer preferences unchanged")

        let completed = try store.createTask(text: "Completed retrieval beacon", at: date("2022-04-11"), projectName: "Beta")
        try store.setTaskCompleted(completed, completed: true)
        state.query = "completed retrieval beacon"
        try expect(matches(state) == [completed.id], "Completed tasks remain globally findable on their original saved date")
        let removed = try store.capture(text: "Deleted retrieval beacon", at: anchor, projectName: "Beta")[0]
        state.query = "deleted retrieval beacon"
        try expect(matches(state) == [removed.id], "The deleted-result fixture first matches globally")
        try store.moveToTrash(removed)
        try expect(matches(state).isEmpty, "Deleted items immediately leave global results")
        state.query = " \t "
        try expect(matches(state) == Set(store.captures.filter { $0.deletedAt == nil }.map(\.id)),
            "An empty global query browses every eligible saved capture, including attachments and completed tasks")
        try expect(state.searchGroups.map(\.day) == state.searchGroups.map(\.day).sorted(by: >),
            "Empty-query browsing keeps newest saved dates first")
    }

    @MainActor private static func scratchpadCases(_ state: AppState) throws {
        var snapshot = state.workspace.snapshot
        let notes = [WorkspaceScratchpad(text: "Shared scratchpad beacon", projectName: "Alpha", updatedAt: date("2024-03-08")),
            WorkspaceScratchpad(text: "Shared scratchpad beacon", projectName: "Beta", updatedAt: date("2024-03-09")),
            WorkspaceScratchpad(text: "Shared scratchpad beacon", projectName: nil, updatedAt: date("2024-03-10"))]
        for note in notes { snapshot.scratchpads[WorkspaceSnapshot.projectKey(note.projectName)] = note }
        try JSONEncoder().encode(snapshot).write(to: state.store.root.appendingPathComponent(WorkspaceStore.filename))
        try state.workspace.reload()
        state.query = "SCRÁTCHPAD beacon"
        state.filter = .text
        state.searchSource = nil
        state.selectSearchProject("Alpha")
        state.setSearchRange(start: date("2024-03-08"), end: date("2024-03-10"))
        try expect(state.searchScratchpads == [notes[0]], "Scratchpads AND project and range using their last-updated day and normalized words")
        state.setSearchDay(date("2024-03-09"))
        try expect(state.searchScratchpads.isEmpty, "Scratchpad dates do not borrow matching capture dates")
        state.searchAllDates()
        try expect(state.searchScratchpads == [notes[0]], "All dates preserves the selected scratchpad project")
        state.selectSearchProject(nil)
        try expect(state.searchScratchpads.count == 3, "All projects includes each matching scratchpad")
        state.searchUnfiledProject()
        try expect(state.searchScratchpads == [notes[2]], "Unfiled only includes the Inbox scratchpad")
        state.filter = .files
        try expect(state.searchScratchpads.isEmpty, "The Files type never leaks scratchpads")
        state.filter = .all
        state.searchSource = "Editor"
        try expect(state.searchScratchpads.isEmpty, "Scratchpads have no application source and cannot bypass a selected source")
        state.searchSource = nil
        state.query = "  "
        try expect(state.searchScratchpads == [notes[2]],
            "Empty-query browsing retains the explicit Unfiled refinement for project notes")
        state.selectSearchProject(nil)
        try expect(Set(state.searchScratchpads.map { WorkspaceSnapshot.projectKey($0.projectName) })
            == Set(notes.map { WorkspaceSnapshot.projectKey($0.projectName) }),
            "Empty-query global browsing includes each nonempty saved project note")
        let dateGroups = state.searchDateGroups
        try expect(dateGroups.reduce(0) { $0 + $1.matchCount }
            == matches(state).count + state.searchScratchpads.count,
            "The unified date board counts captures and project notes exactly once")
        for note in notes {
            try expect(dateGroups.first { $0.day == CaptureCalendar.dayString(note.updatedAt) }?.items
                .contains { $0.scratchpad == note } == true, "A project note belongs to its own Edited day")
        }
        state.query = "scratchpad beacon"
        state.selectSearchProject("Alpha")
        try state.workspace.setScratchpad(text: "A freshly edited scratchpad beacon", project: "Alpha")
        state.setSearchDay(Date())
        try expect(state.searchScratchpads.count == 1, "Editing an older scratchpad makes it searchable on its updated day")
        let note = state.searchScratchpads[0]
        let destination = state.libraryProject
        let selected = state.workspace.selectedCaptureID
        let dayAnchor = CaptureCalendar.dayString(note.updatedAt)
        state.searchDateAnchor = dayAnchor
        state.openSearchNote(note)
        try expect(state.route == .searchNote && state.selectedSearchNote?.projectName == "Alpha"
            && state.libraryProject == destination && state.workspace.selectedCaptureID == selected,
            "Opening a global note result uses its editor without changing the capture destination or project selection")
        try state.workspace.setScratchpad(text: "Updated again: scratchpad beacon", project: state.selectedSearchNote?.projectName)
        state.back()
        try expect(state.route == .search && state.query == "scratchpad beacon" && state.searchProject == "Alpha"
            && state.filter == .all && state.searchDateAnchor == dayAnchor
            && state.searchScratchpads.first?.text == "Updated again: scratchpad beacon"
            && state.libraryProject == destination,
            "An autosaved note returns to the same live query, date anchor and capture destination")
        state.setSearchDay(date("2024-03-08"))
        try expect(state.searchScratchpads.isEmpty, "An edited scratchpad is not incorrectly repeated under its previous update day")
    }

    @MainActor private static func navigationCases(_ state: AppState) async throws {
        let alpha = state.store.captures.first {
            $0.originalText == "Scope beacon" && $0.projectName == "Alpha" && $0.captureDay == "2024-03-09"
        }!
        let beta = state.store.captures.first { $0.originalText == "Scope beacon" && $0.projectName == "Beta" }!
        let navigationDay = date("2024-03-09")
        let navigationWeek = date("2024-03-10")
        state.selectedDay = navigationDay
        state.weekEndingDay = navigationWeek
        state.libraryProject = "Alpha"
        state.workspace.sourceApplication = nil
        state.workspace.selectedCaptureID = alpha.id
        state.route = .library
        state.filter = .text
        state.query = "scope beacon"
        state.showSearchContext = true
        state.performSearchCommand()
        try expect(state.searchScope == .all && state.searchProject == nil && !state.searchUnfiledOnly
            && state.searchSource == nil && state.filter == .all && !state.showSearchContext
            && state.libraryProject == "Alpha" && state.autoCapture.projectProvider() == "Alpha",
            "Command K starts global without changing the active capture destination")
        state.selectSearchProject("Beta")
        state.filter = .files
        state.searchSource = "Editor"
        state.setSearchRange(start: date("2024-03-08"), end: navigationWeek)
        state.searchScrollID = beta.id
        state.searchDateAnchor = beta.captureDay
        state.searchSelectedResultID = "capture:" + beta.id.uuidString
        state.searchColumnScrollIDs = [beta.captureDay: "capture:" + beta.id.uuidString]
        let unchangedQuery = state.query, unchangedSource = state.searchSource
        let unchangedProject = state.searchProject, unchangedFilter = state.filter
        state.query = unchangedQuery; state.searchSource = unchangedSource
        state.selectSearchProject(unchangedProject); state.filter = unchangedFilter
        try expect(state.searchDateAnchor == beta.captureDay && state.searchScrollID == beta.id
            && state.searchSelectedResultID == "capture:" + beta.id.uuidString
            && state.searchColumnScrollIDs[beta.captureDay] == "capture:" + beta.id.uuidString,
            "Same-value refinement updates preserve the selected result, date page and column scroll position")
        _ = try state.store.capture(text: "New unrelated arrival", at: date("2024-03-12"), projectName: "Alpha")
        try expect(state.searchDateAnchor == beta.captureDay && state.searchSelectedResultID == "capture:" + beta.id.uuidString
            && state.searchColumnScrollIDs[beta.captureDay] == "capture:" + beta.id.uuidString,
            "A new saved arrival invalidates search data without resetting the user's date page or selection")
        let focus = state.globalSearchFocusRequest
        state.performSearchCommand()
        state.submitSearch()
        try expect(state.globalSearchFocusRequest == focus + 2 && state.searchProject == "Beta" && state.filter == .files
            && state.searchSource == "Editor" && state.searchScrollID == beta.id
            && state.searchDateAnchor == beta.captureDay
            && state.searchSelectedResultID == "capture:" + beta.id.uuidString
            && state.searchColumnScrollIDs[beta.captureDay] == "capture:" + beta.id.uuidString
            && state.searchScope == .range(startDay: "2024-03-08", endDay: "2024-03-10"),
            "Cmd-K and Return preserve all refinements and the current result position")
        state.openCapture(beta.id, focus: "comment")
        let resultDraft = state.selectedDraft!
        resultDraft.comment = "Keep this unfinished result comment"
        state.showSettings()
        state.performSearchCommand()
        try expect(state.route == .search && state.searchProject == "Beta" && state.searchSource == "Editor"
            && state.searchScope == .range(startDay: "2024-03-08", endDay: "2024-03-10") && state.filter == .files
            && state.searchDateAnchor == beta.captureDay,
            "Search reopened through a result's Settings keeps the original search session")
        state.back()
        try expect(state.route == .library && state.filter == .text && state.libraryProject == "Alpha"
            && state.workspace.selectedCaptureID == alpha.id && state.selectedDay == navigationDay && state.weekEndingDay == navigationWeek,
            "Back restores the original Projects selection, type and calendar context without a detail/search loop")
        state.openCapture(beta.id, focus: "comment")
        try expect(state.selectedDraft === resultDraft && state.selectedDraft?.comment == "Keep this unfinished result comment",
            "Revisiting a result preserves its unsaved editor draft")
        state.showSettings()
        state.performSearchCommand()
        try expect(state.searchProject == nil && !state.searchUnfiledOnly && state.searchSource == nil
            && state.searchScope == .all && state.filter == .all && state.searchDateAnchor == nil,
            "A fresh search above non-search details clears old refinements instead of inheriting that capture's project")
        state.openCapture(alpha.id)
        state.back()
        state.back()
        try expect(state.route == .settings && state.selectedCapture?.id == beta.id && state.selectedDraft === resultDraft
            && state.detailFocus == "comment", "Returning from search restores the original detail underneath Settings")
        state.back()
        try expect(state.route == .detail && state.selectedCapture?.id == beta.id, "Settings Back still returns to its original detail")
        state.back()
        try expect(state.route == .library, "Detail Back reaches Projects without resurrecting Search")

        state.route = .daily
        state.filter = .text
        state.performSearchCommand()
        try expect(state.searchScope == .all && state.searchProject == nil && state.filter == .all
            && state.libraryProject == "Alpha" && state.selectedDay == navigationDay,
            "Fresh Daily Search starts globally while retaining its calendar and destination for Back")
        state.searchDateAnchor = "2024-03-09"
        state.searchSelectedResultID = "capture:" + alpha.id.uuidString
        state.searchColumnScrollIDs = ["2024-03-09": "capture:" + alpha.id.uuidString]
        state.updateGlobalSearch("scope beacon changed")
        try expect(state.searchDateAnchor == nil && state.searchSelectedResultID == nil && state.searchColumnScrollIDs.isEmpty,
            "Changing query words discards stale selected-result and date-column anchors")
        state.updateGlobalSearch("scope beacon")
        state.searchDateAnchor = alpha.captureDay
        state.searchSelectedResultID = "capture:" + alpha.id.uuidString
        state.searchColumnScrollIDs = [alpha.captureDay: "capture:" + alpha.id.uuidString]
        state.searchSource = "Editor"
        try expect(state.searchDateAnchor == nil && state.searchSelectedResultID == nil && state.searchColumnScrollIDs.isEmpty,
            "Changing a deliberate source refinement discards stale result positions")
        state.searchSource = nil
        state.setSearchRange(start: date("2024-03-01"), end: date("2024-03-31"))
        state.back()
        try expect(state.route == .daily && state.selectedDay == navigationDay && state.filter == .text,
            "A custom search range does not alter Daily's date on Back")
        state.route = .weekly
        state.filter = .tasks
        state.performSearchCommand()
        try expect(state.searchScope == .all && state.searchProject == nil && state.filter == .all,
            "Fresh Weekly Search clears implicit week, project and task filters")
        state.openSearch(day: date("2024-02-29"))
        try expect(state.searchScope == .day("2024-02-29"),
            "An explicit day action still applies its deliberate civil-date scope")
        state.back()
        try expect(state.route == .weekly && state.weekEndingDay == navigationWeek && state.filter == .tasks,
            "Changing the day in a live Weekly search restores the original Weekly anchor")
        state.route = .inbox
        state.filter = .all
        state.performSearchCommand()
        try expect(state.searchProject == nil && !state.searchUnfiledOnly && state.searchScope == .all
            && state.libraryProject == "Alpha" && state.autoCapture.projectProvider() == "Alpha",
            "Inbox search is global and never uses its capture destination as a hidden search filter")
        state.back()
        state.libraryProject = nil
        state.workspace.explorerUnfiledOnly = true
        state.route = .library
        state.performSearchCommand()
        try expect(!state.searchUnfiledOnly && state.searchProject == nil && state.workspace.explorerUnfiledOnly,
            "Global Search ignores Projects' Unfiled browse filter while preserving it for return")
        state.back()
        state.workspace.explorerUnfiledOnly = false
        state.performSearchCommand()
        try expect(!state.searchUnfiledOnly && state.searchProject == nil, "Projects with no selection and no Unfiled refinement means all projects")
        state.back()
        state.route = .daily
        state.openNewNote()
        state.newNoteText = "Unfinished scoped-search note"
        state.performSearchCommand()
        state.searchEverything()
        state.back()
        try expect(state.route == .newNote && state.newNoteText == "Unfinished scoped-search note",
            "Search Back restores the untouched composer draft")
        state.back()
        try expect(state.route == .daily, "Restored composer Back reaches its original Daily route")
        state.openNewTask()
        state.newTaskDraft.text = "Unfinished scoped-search task"
        state.openSearch(week: [date("2024-02-28"), date("2024-02-29")])
        try expect(state.searchScope == .week(["2024-02-28", "2024-02-29"]), "Explicit week entry keeps the supplied civil dates exactly")
        state.back()
        try expect(state.route == .newTask && state.newTaskDraft.text == "Unfinished scoped-search task",
            "Explicit week Search does not hard-code a Weekly return route over a task composer")
        state.back()
        try expect(state.route == .daily, "Restored task composer retains its original Back route")

        let parent = state.store.captures.first { $0.originalText == "Parent obligation" }!
        let child = state.store.captures.first { $0.parentTaskID == parent.id }!
        state.libraryProject = "Alpha"
        state.route = .library
        state.filter = .files
        state.openCapture(parent.id)
        state.openCapture(child.id, focus: "comment")
        let childDraft = state.selectedDraft!
        childDraft.comment = "Keep the unfinished attachment annotation"
        state.showTrash()
        state.performSearchCommand()
        try expect(!state.searchUnfiledOnly && state.searchProject == nil && state.searchScope == .all
            && state.filter == .all && state.libraryProject == "Alpha",
            "Fresh Search above an attachment is global and does not inherit its parent or stale child project")
        state.openCapture(beta.id)
        state.back()
        state.back()
        try expect(state.route == .trash && state.selectedCapture?.id == child.id && state.selectedDraft === childDraft
            && state.detailFocus == "comment", "Search restores an attachment detail and its draft underneath Recently Deleted")
        state.back()
        state.back()
        try expect(state.route == .detail && state.selectedCapture?.id == parent.id,
            "An attachment's restored Back action still returns to its parent task")
        state.back()
        try expect(state.route == .library, "The restored parent task returns to Projects without a search loop")

        state.route = .daily
        state.filter = .text
        state.openCapture(alpha.id)
        state.performSearchCommand()
        try expect(matches(state).contains(alpha.id), "The deletion fixture starts as a matching receipt in global Search")
        await state.removeCapture(alpha)
        try expect(!matches(state).contains(alpha.id), "Removing a currently searched capture invalidates its match immediately")
        state.back()
        try expect(state.route == .daily && state.selectedCapture == nil && state.selectedDraft == nil
            && state.workspace.selectedCaptureID == nil, "Back falls through safely when the original detail was deleted during search")
    }

    @MainActor private static func closedSessionCases(_ state: AppState) throws {
        state.route = .library
        state.libraryProject = "Alpha"
        state.filter = .text
        state.performSearchCommand()
        state.query = "scope beacon"
        state.selectSearchProject("Beta")
        state.filter = .tasks
        state.searchSource = "Editor"
        state.setSearchDay(date("2024-03-09"))
        state.searchDateAnchor = "2024-03-09"
        state.endSearchSession()
        state.performSearchCommand()
        try expect(state.query == "scope beacon" && state.searchProject == nil && state.searchSource == nil
            && state.searchScope == .all && state.filter == .all && state.searchDateAnchor == nil,
            "A new search after window close retains words and clears every prior refinement")
        state.back()
        try expect(state.route == .library && state.libraryProject == "Alpha" && state.filter == .text,
            "Reopening a closed Search retains the original Back destination without a Search loop")
        state.performSearchCommand()
        state.selectSearchProject("Beta")
        let note = WorkspaceScratchpad(text: "Close note fixture", projectName: "Beta", updatedAt: Date())
        state.openSearchNote(note)
        state.endSearchSession()
        state.performSearchCommand()
        try expect(state.route == .search && state.searchProject == nil && state.selectedSearchNote == nil,
            "Closing while editing a search note also ends refinements for a fresh command")
        state.back()
        try expect(state.route == .library && state.libraryProject == "Alpha", "A closed note session preserves its project return context")
    }

    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinSearchScopeQA-\(UUID())")
        let preferencesName = "DaBinSearchScopeQA.\(UUID())"
        let preferences = UserDefaults(suiteName: preferencesName)!
        let pasteboard = NSPasteboard(name: .init("DaBinSearchScopeQA.\(UUID())"))
        defer {
            pasteboard.releaseGlobally()
            preferences.removePersistentDomain(forName: preferencesName)
            try? FileManager.default.removeItem(at: root)
        }
        let store = try CaptureStore(root: root.appendingPathComponent("Archive"))
        let previews = PreviewService(store: store, defaults: preferences)
        let auto = AutoCaptureService(settings: AutoCaptureSettings(defaults: preferences), input: InputService(store: store),
            pasteboardProvider: { fatalError("Search QA must not read a clipboard") }, sourceApplicationProvider: { nil })
        let state = AppState(store: store, previews: previews,
            reminders: ReminderService(store: store, client: ScopedSearchNotifications()),
            autoCapture: auto, captureClipboard: CaptureClipboardService(pasteboard: pasteboard))
        auto.projectProvider = { [weak state] in state?.libraryProject }
        defer {
            auto.shutdown(); state.focusSessions.shutdown()
            state.shutdownNotificationPresentation(); previews.shutdown()
        }
        try calendarCases(state)
        try await projectAndDateCases(state, root: root)
        try scratchpadCases(state)
        try await navigationCases(state)
        try closedSessionCases(state)
        try state.workspace.setScratchpad(text: "Original note", project: "Alpha")
        let note = WorkspaceScratchpad(text: "Original note", projectName: "Alpha", updatedAt: Date())
        try state.workspace.setScratchpad(text: "  Current note ✨\nsecond line  ", project: "Alpha")
        try expect(state.copySearchNote(note) && pasteboard.string(forType: .string) == "  Current note ✨\nsecond line  ",
            "Copy note uses exact current edited text through the isolated clipboard, not a stale result snapshot")
        try expect(state.libraryProject == "Alpha", "Copying a note does not change the capture destination")
        print("PASS: \(checks) scoped-search checks; project/type/source intersection, live attachment inheritance, capture-day ranges, scratchpads, DST and Back restoration")
    }
}
