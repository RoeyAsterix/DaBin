import Foundation

/// Synthetic temporary archives only; no clipboard, notifications or user files.
@main struct ProjectWorkspaceStateTests {
    @MainActor private static var checks = 0
    @MainActor private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        if try !condition() { throw NSError(domain: "ProjectWorkspaceStateTests", code: 1,
                                            userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    @MainActor private static func rejects(_ action: () throws -> Void, _ message: String) throws {
        var failed = false
        do { try action() } catch { failed = true }
        try expect(failed, message)
    }

    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinProjectWorkspaceQA-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try ordering()
        try rowAnchors()
        try selection()
        try contents()
        try dateSelection()
        try summaryCache(root.appendingPathComponent("summary-cache"))
        try persistence(root.appendingPathComponent("workspace"))
        try conversion(root.appendingPathComponent("captures"))
        print("PASS: \(checks) project-workspace checks; stable ordering, scoped selection, calendar day/week filters, complete project counts, backup-compatible persistence, atomic task conversion, inherited ownership and guarded undo.")
    }

    @MainActor private static func dateSelection() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.locale = Locale(identifier: "en_US")
        calendar.firstWeekday = 1
        func date(_ day: String) -> Date {
            ProjectDateSelection.date(for: day, calendar: calendar)!
        }
        let exact = ProjectDateSelection(date: date("2026-10-05"), mode: .day, calendar: calendar)
        try expect(exact.startDay == "2026-10-05" && exact.endDay == "2026-10-05",
                   "Day selection uses the local Gregorian civil day")
        try expect(exact.includes(day: "2026-10-05") && !exact.includes(day: "2026-10-04")
            && !exact.includes(day: "2026-10-06"), "A day filter includes exactly its selected day")
        let late = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: date("2026-10-05"))!
        try expect(ProjectDateSelection(date: late, mode: .day, calendar: calendar) == exact,
                   "A day's filter identity ignores incidental receipt time")
        let sundayWeek = ProjectDateSelection(date: date("2026-10-05"), mode: .week, calendar: calendar)
        try expect(sundayWeek.startDay == "2026-10-04" && sundayWeek.endDay == "2026-10-10",
                   "A Sunday-first locale selects its complete calendar week")
        calendar.locale = Locale(identifier: "en_GB")
        calendar.firstWeekday = 2
        let mondayWeek = ProjectDateSelection(date: date("2026-10-05"), mode: .week, calendar: calendar)
        try expect(mondayWeek.startDay == "2026-10-05" && mondayWeek.endDay == "2026-10-11",
                   "A Monday-first locale starts on Monday and ends on Sunday")
        try expect(mondayWeek.includes(day: mondayWeek.startDay) && mondayWeek.includes(day: mondayWeek.endDay)
            && !mondayWeek.includes(day: "2026-10-04") && !mondayWeek.includes(day: "2026-10-12"),
                   "Calendar-week filtering includes both boundaries and excludes neighboring days")
        try expect(ProjectDateSelection(date: date("2026-10-11"), mode: .week, calendar: calendar) == mondayWeek,
                   "Choosing another day in the same calendar week retains one filter identity")
        let monthSpan = ProjectDateSelection(date: date("2026-10-01"), mode: .week, calendar: calendar)
        try expect(monthSpan.startDay == "2026-09-28" && monthSpan.endDay == "2026-10-04",
                   "A week filter spans months rather than stopping at the visible month's edge")
        let yearSpan = ProjectDateSelection(date: date("2026-01-01"), mode: .week, calendar: calendar)
        try expect(yearSpan.startDay == "2025-12-29" && yearSpan.endDay == "2026-01-04",
                   "A week filter includes dates on both sides of a year boundary")
        try expect(yearSpan.includes(day: "2025-12-31") && yearSpan.includes(day: "2026-01-01"),
                   "Civil date keys sort correctly across a year boundary")
        for (chosen, start, end) in [("2026-03-08", "2026-03-02", "2026-03-08"),
                                      ("2026-11-01", "2026-10-26", "2026-11-01")] {
            let week = ProjectDateSelection(date: date(chosen), mode: .week, calendar: calendar)
            try expect(week.startDay == start && week.endDay == end,
                       "DST transition week \(chosen) retains all seven civil days")
            let anchor = week.date(calendar: calendar)!
            let days = (0..<7).map { CaptureCalendar.dayString(calendar.date(byAdding: .day, value: $0, to: anchor)!,
                                                              timeZone: calendar.timeZone) }
            try expect(days.first == start && days.last == end && Set(days).count == 7 && days.allSatisfy(week.includes),
                       "Reopening a DST week provides a valid anchor for every included civil day")
        }
        for invalid in ["", "2026-2-01", "2026-02-31", "2026-02-29", "2026-13-01", "2026-00-01",
                        "0000-01-01", "2026-01-00", "2026-01-32", "2026-01-01x", "２０２６-01-01", "+026-01-01"] {
            try expect(ProjectDateSelection.date(for: invalid, calendar: calendar) == nil,
                       "Calendar anchors reject malformed or impossible civil date: \(invalid)")
        }
        try expect(ProjectDateSelection.date(for: "2024-02-29", calendar: calendar) != nil,
                   "Calendar anchors accept a valid leap day")
        var nonGregorian = Calendar(identifier: .hebrew)
        nonGregorian.timeZone = calendar.timeZone
        try expect(CaptureCalendar.dayString(exact.date(calendar: nonGregorian)!, timeZone: nonGregorian.timeZone) == exact.startDay,
                   "Stored Gregorian civil dates reopen correctly with a non-Gregorian presentation calendar")
        var apia = Calendar(identifier: .gregorian)
        apia.timeZone = TimeZone(identifier: "Pacific/Apia")!
        try expect(ProjectDateSelection.date(for: "2011-12-30", calendar: apia) == nil,
                   "A time zone's skipped civil day is rejected rather than normalized to a neighbor")
        let locale = Locale(identifier: "en_US")
        let now = date("2026-10-05")
        let sameYearTitle = exact.displayTitle(calendar: calendar, locale: locale, now: now)
        try expect(sameYearTitle.contains("Oct") && sameYearTitle.contains("5") && !sameYearTitle.contains("2026"),
                   "A current-year day has a compact unambiguous month/day title")
        let oldDay = ProjectDateSelection(date: date("2025-10-05"), mode: .day, calendar: calendar)
        try expect(oldDay.displayTitle(calendar: calendar, locale: locale, now: now).contains("2025"),
                   "A day outside this year includes its year")
        let spanTitle = yearSpan.displayTitle(calendar: calendar, locale: locale, now: now)
        try expect(spanTitle.contains("2025") && spanTitle.contains("2026"),
                   "A year-spanning week title includes both years")
        let fullLabel = mondayWeek.accessibilityLabel(calendar: calendar, locale: locale)
        try expect(fullLabel.contains("Monday") && fullLabel.contains("Sunday") && fullLabel.contains("2026"),
                   "A calendar-week accessibility label speaks both full date boundaries")
        try expect(exact.cacheKey != mondayWeek.cacheKey && sundayWeek.cacheKey != mondayWeek.cacheKey,
                   "Filter cache identities distinguish mode and locale-specific week boundaries")

        var project = ProjectNavigationPresentation()
        try expect(project.selectedDateRange == nil && project.dateFilter == .anytime,
                   "New project sessions start with all dates")
        project.selectedDateRange = mondayWeek
        var other = project
        other.selectedDateRange = exact
        try expect(project != other, "Project navigation equality includes its explicit date range")
        var history = NavigationHistory()
        var workspace = NavigationSnapshot()
        workspace.route = .library
        workspace.project = "Calendar QA"
        workspace.projectPresentation = project
        history.visit(workspace)
        var settings = workspace
        settings.route = .settings
        history.visit(settings)
        try expect(history.back()?.projectPresentation?.selectedDateRange == mondayWeek,
                   "Returning from Settings preserves the project's chosen calendar week")
        try expect(history.forward()?.projectPresentation?.selectedDateRange == mondayWeek,
                   "Forward history preserves the same session-only project date filter")
        project.selectedDateRange = nil
        project.dateFilter = .anytime
        try expect(project == ProjectNavigationPresentation(), "Clearing the date range restores an unfiltered project session")
    }

    @MainActor private static func ordering() throws {
        let ids = ["a", "b", "c", "d", "e"]
        try expect(ProjectWorkspaceOrdering.ordered(ids, saved: ["c", "deleted", "a", "c"]) == ["c", "a", "b", "d", "e"],
                   "Ordering removes unavailable and duplicate saved IDs and appends new items")
        try expect(ProjectWorkspaceOrdering.ordered(["a", "a", "b"], saved: []) == ["a", "b"], "Available duplicates never render twice")
        try expect(ProjectWorkspaceOrdering.move(ids, selected: ["b", "c"], direction: .earlier) == ["b", "c", "a", "d", "e"],
                   "A selected block moves earlier without reversing its items")
        try expect(ProjectWorkspaceOrdering.move(ids, selected: ["b", "c"], direction: .later) == ["a", "d", "b", "c", "e"],
                   "A selected block moves later without reversing its items")
        try expect(ProjectWorkspaceOrdering.move(ids, selected: ["a", "c", "e"], direction: .earlier) == ["a", "c", "b", "e", "d"],
                   "Noncontiguous blocks move independently and the first block stays at the boundary")
        try expect(ProjectWorkspaceOrdering.move(ids, selected: Set(ids), direction: .later) == ids, "Selecting everything is a stable no-op")
        try expect(ProjectWorkspaceOrdering.move([], selected: ["a"], direction: .earlier).isEmpty, "Empty reorder is safe")
        try expect(ProjectWorkspaceOrdering.moving(ids, selected: ["b", "d"], before: "a") == ["b", "d", "a", "c", "e"],
                   "A drag inserts the selected block before a valid target")
        try expect(ProjectWorkspaceOrdering.moving(ids, selected: ["b", "d"], before: nil) == ["a", "c", "e", "b", "d"],
                   "A drag to the end preserves relative order")
        try expect(ProjectWorkspaceOrdering.moving(ids, selected: ["b", "d"], before: "b") == ids, "Dropping on the selection is a no-op")
        try expect(ProjectWorkspaceOrdering.moving(ids, selected: ["b"], before: "missing") == ids, "Stale drag targets cannot reorder")
        let large = (0..<100_000).map(String.init)
        try expect(ProjectWorkspaceOrdering.ordered(large, saved: Array(large.reversed())) == Array(large.reversed()),
                   "Large project order resolves with stable linear membership lookups")
    }

    @MainActor private static func rowAnchors() throws {
        for columns in 1...3 {
            for count in [12, 13, 14] {
                let existing = (0..<count).map { "capture:existing-\($0)" }
                let before = ProjectWorkspaceOrdering.rows(ids: existing, columns: columns, newestFirst: true)
                let fullRows = before.filter { $0.count == columns }
                for addedCount in 1...6 {
                    let added = (0..<addedCount).map { "capture:new-\($0)" }
                    let after = ProjectWorkspaceOrdering.rows(ids: added + existing, columns: columns, newestFirst: true)
                    try expect(after.flatMap { $0 } == added + existing,
                               "New capture row grouping preserves the exact displayed order")
                    try expect(fullRows.allSatisfy { after.contains($0) },
                               "Prepending \(addedCount) captures retains every full-row anchor at \(columns) columns")
                    try expect(after.dropFirst().allSatisfy { $0.count == columns } && after.allSatisfy { !$0.isEmpty && $0.count <= columns },
                               "Only the leading newest-first row may be partial")
                }
                let manual = ProjectWorkspaceOrdering.rows(ids: existing, columns: columns, newestFirst: false)
                let appended = ProjectWorkspaceOrdering.rows(ids: existing + ["capture:new"], columns: columns, newestFirst: false)
                try expect(manual.filter { $0.count == columns }.allSatisfy { appended.contains($0) },
                           "Appending into a manual order retains its complete-row anchors")
                try expect(manual.dropLast().allSatisfy { $0.count == columns }, "Manual order uses only a trailing partial row")
            }
        }
        try expect(ProjectWorkspaceOrdering.rows(ids: [], columns: 3, newestFirst: true).isEmpty, "An empty project has no artificial rows")
        try expect(ProjectWorkspaceOrdering.rows(ids: ["a", "b"], columns: 0, newestFirst: true) == [["a"], ["b"]],
                   "An invalid column count safely becomes a single-column list")
        try expect(ProjectWorkspaceOrdering.rows(ids: ["a", "b"], columns: Int.max, newestFirst: false) == [["a", "b"]],
                   "An oversized column count does not overflow row calculations")
    }

    @MainActor private static func selection() throws {
        let visible = ["a", "b", "c", "d", "e"]
        var selection = ProjectWorkspaceSelection()
        try expect(selection.ids.isEmpty && selection.anchorID == nil, "Workspace starts without a preselection")
        selection.toggle("b", visible: visible)
        selection.toggle("e", visible: visible, extending: true)
        try expect(selection.ids == ["b", "c", "d", "e"], "Shift selection includes the visible range")
        selection.toggle("c", visible: visible)
        try expect(selection.ids == ["b", "d", "e"], "Checkbox toggles one item independently")
        selection.reconcile(visible: ["a", "b"])
        try expect(selection.ids == ["b"] && selection.anchorID == nil, "Filtering clears hidden selection and hidden anchor")
        selection.toggle("hidden", visible: ["a", "b"])
        try expect(selection.ids == ["b"], "An unavailable checkbox cannot add hidden selection")
        selection.selectAll(visible: ["a", "b"])
        try expect(selection.ids == ["a", "b"], "Select all is scoped to visible items")
        selection.clear()
        try expect(selection.ids.isEmpty && selection.anchorID == nil, "Clear removes all selection state")
    }

    @MainActor private static func contents() throws {
        // In-memory fictional records cover ownership edge cases without
        // touching an archive, preview service, clipboard or network.
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let note = Capture(capturedAt: now, kind: .text, originalText: "Project reference", title: "Reference")
        note.projectName = "Launch"
        let parent = Capture(capturedAt: now.addingTimeInterval(-86_400 * 30), kind: .task,
                             originalText: "Review project", title: "Review project")
        parent.projectName = "Launch"
        let attachment = Capture(capturedAt: now.addingTimeInterval(-60), kind: .pdf,
                                 originalFilename: "Proposal.pdf", title: "Proposal.pdf", parentTaskID: parent.id)
        attachment.projectName = "Former project"
        let orphan = Capture(capturedAt: now.addingTimeInterval(-120), kind: .text,
                             originalText: "Retained attachment", title: "Retained attachment", parentTaskID: UUID())
        orphan.projectName = "Launch"
        let unrelated = Capture(capturedAt: now, kind: .link,
                                originalURL: "https://example.invalid/reference", title: "Other reference")
        unrelated.projectName = "Other"
        let deletedChild = Capture(capturedAt: now, kind: .image, originalFilename: "Deleted.png",
                                   title: "Deleted attachment", parentTaskID: parent.id)
        deletedChild.projectName = "Launch"
        deletedChild.deletedAt = now
        let records = [note, parent, attachment, orphan, unrelated, deletedChild]

        try expect(Set(ProjectWorkspaceContents.captures(in: "Launch", from: records).map(\.id))
            == Set([note.id, parent.id, attachment.id, orphan.id]),
            "Project contents include all dates and types, inherited attachments and missing-parent fallback, excluding trash and unrelated projects")
        try expect(ProjectWorkspaceContents.captures(in: "Former project", from: records).isEmpty,
                   "An attachment's stale stored project never overrides its existing parent's project")
        try expect(ProjectWorkspaceContents.captures(in: "Other", from: records).map(\.id) == [unrelated.id],
                   "Another project's content remains separate")
        try expect(!ProjectWorkspaceContents.captures(in: "Launch", from: records).contains { $0.id == deletedChild.id },
                   "A deleted attachment is never counted even when its live parent belongs to the project")
        for scratchpad in ["", " \n\t\r ", "\u{00a0}\u{2003}\n"] {
            try expect(ProjectWorkspaceContents.itemCount(in: "Launch", captures: records, scratchpad: scratchpad) == 4,
                       "Empty and whitespace-only live notes do not add a project item")
        }
        try expect(ProjectWorkspaceContents.itemCount(in: "Launch", captures: records,
            scratchpad: "  Unsaved live note\nWith another line  ") == 5,
            "A nonempty current scratchpad contributes exactly one item, regardless of its lines")
        try expect(ProjectWorkspaceContents.itemCount(in: "Launch", captures: Array(records.reversed()), scratchpad: "Live note") == 5,
                   "Changing item order does not change the complete project count")
        try expect(ProjectWorkspaceContents.itemCount(in: "Empty", captures: records, scratchpad: "") == 0,
                   "A project without captures or a note has zero items")
        try expect(ProjectWorkspaceContents.itemCount(in: "Notes only", captures: records, scratchpad: "One live note") == 1,
                   "A notes-only project has the singular numeric count of one")
        try expect(ProjectWorkspaceContents.itemCount(in: "Launch", captures: [note], scratchpad: "") == 1,
                   "One captured item with no live note has the singular numeric count of one")

        parent.projectName = nil
        try expect(Set(ProjectWorkspaceContents.captures(in: "Launch", from: records).map(\.id)) == Set([note.id, orphan.id]),
                   "An existing unfiled parent removes itself and its attachment from the former project")
        try expect(ProjectWorkspaceContents.captures(in: "Former project", from: records).isEmpty,
                   "A nil parent project does not fall back to the attachment's stale project")
        try expect(ProjectWorkspaceContents.itemCount(in: "Launch", captures: records, scratchpad: "Live note") == 3,
                   "Project total follows a parent's live ownership change while retaining the note")
        parent.projectName = "Other"
        try expect(Set(ProjectWorkspaceContents.captures(in: "Other", from: records).map(\.id))
            == Set([parent.id, attachment.id, unrelated.id]),
            "Moving a parent moves its active attachment into the new project's contents")
        try expect(ProjectWorkspaceContents.itemCount(in: "Other", captures: records, scratchpad: "") == 3,
                   "A moved task and attachment are counted exactly once in their new project")
    }

    @MainActor private static func summaryCache(_ root: URL) throws {
        let store = try CaptureStore(root: root)
        let workspace = WorkspaceStore(root: root)
        let cache = ProjectWorkspaceSummaryCache(store: store, workspace: workspace)
        try expect(cache.summary(for: "Launch").itemCount == 0, "The summary starts with the current empty project")
        let initialBuilds = cache.buildCount
        for _ in 0..<200 { _ = cache.summary(for: "Launch") }
        try expect(cache.buildCount == initialBuilds,
                   "Repeated layout reads never traverse the archive again without a data change")
        let note = try store.createNote(text: "Original feedback", projectName: "Launch")
        try expect(cache.summary(for: "Launch").itemCount == 1, "A saved capture invalidates the cached count")
        try workspace.setScratchpad(text: "Follow up", project: "Launch")
        try expect(cache.summary(for: "Launch").itemCount == 2, "A live project note invalidates the cached count")
        try workspace.setProjectColor(hex: "8257E5", for: "Launch")
        try expect(cache.summary(for: "Launch").colorHex == "8257E5", "A project color edit refreshes the cached appearance")
        let parent = try store.createTask(text: "Proposal", projectName: "Launch")
        _ = try store.capture(text: "Attachment", parentTask: parent)
        try expect(cache.summary(for: "Launch").itemCount == 4, "Task attachments contribute to the project summary")
        try store.setOrganization(parent, pinned: false, projectName: "Other")
        try expect(cache.summary(for: "Launch").itemCount == 2, "Moving a parent invalidates inherited attachment counts")
        try expect(cache.summary(for: "Other").itemCount == 2, "Switching projects rebuilds the single bounded cache entry")
        try expect(cache.summary(for: "Launch").itemCount == 2, "Returning to a project restores its own summary")
        try store.moveToTrash(note)
        try expect(cache.summary(for: "Launch").itemCount == 1, "Moving a capture to trash updates the header count")
        guard let trashedNote = store.trashedCaptures.first(where: { $0.id == note.id }) else {
            throw NSError(domain: "ProjectWorkspaceStateTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "The saved note must be present in Recently Deleted"])
        }
        try store.restoreFromTrash(trashedNote)
        try expect(cache.summary(for: "Launch").itemCount == 2, "Restoring a capture updates the header count")
        try workspace.setScratchpad(text: " \n ", project: "Launch")
        try expect(cache.summary(for: "Launch").itemCount == 1, "Clearing a live note removes its summary item")
    }

    @MainActor private static func persistence(_ root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let workspace = WorkspaceStore(root: root)
        let first = ProjectWorkspaceIdentity.capture(UUID()), second = ProjectWorkspaceIdentity.capture(UUID())
        let third = ProjectWorkspaceIdentity.capture(UUID()), note = ProjectWorkspaceIdentity.note(project: "Launch")
        try workspace.saveProjectItemOrder([second, note, first], project: "Launch")
        try expect(workspace.orderedProjectItemIDs([first, second, note, third], project: "Launch") == [second, note, first, third],
                   "Capture and scratchpad identities share one persisted order")
        let reopened = WorkspaceStore(root: root)
        try expect(reopened.orderedProjectItemIDs([first, second, note], project: "Launch") == [second, note, first],
                   "Project order survives workspace reopening")
        try expect(reopened.orderedProjectItemIDs([first, second], project: "Other") == [first, second], "Project order never leaks into another project")
        let saved = workspace.snapshot
        try rejects({ try workspace.saveProjectItemOrder([first, first], project: "Launch") }, "Duplicate persisted identities are rejected")
        try rejects({ try workspace.saveProjectItemOrder(["capture:invalid"], project: "Launch") }, "Invalid capture identities are rejected")
        try rejects({ try workspace.saveProjectItemOrder([ProjectWorkspaceIdentity.note(project: "Other")], project: "Launch") },
                    "A project cannot save another project's scratchpad identity")
        try expect(workspace.snapshot == saved, "Failed order validation leaves the existing snapshot unchanged")
        workspace.failureInjector = { throw WorkspaceError.invalidArchive }
        try rejects({ try workspace.saveProjectItemOrder([first, second, note], project: "Launch") }, "Order write failures reach the caller")
        try expect(workspace.snapshot == saved, "Failed order persistence rolls back visible state")
        workspace.failureInjector = nil
        var incoming = WorkspaceSnapshot()
        incoming.projectItemOrders = [WorkspaceSnapshot.projectKey("Launch"): [first, third, second]]
        let merged = try WorkspaceSnapshot.merging(incoming, into: saved)
        try expect(merged.projectItemOrders?[WorkspaceSnapshot.projectKey("Launch")] == [second, note, first, third],
                   "Backup restore retains local order and appends only incoming new identities")
        var oldJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as! [String: Any]
        oldJSON.removeValue(forKey: "projectItemOrders")
        let old = try JSONDecoder().decode(WorkspaceSnapshot.self, from: JSONSerialization.data(withJSONObject: oldJSON)).validated()
        try expect(old.projectItemOrders == nil, "Pre-upgrade workspace files remain readable")
    }

    @MainActor private static func conversion(_ root: URL) throws {
        let store = try CaptureStore(root: root)
        let parent = try store.createTask(text: "Parent task", projectName: "Old")
        let child = try store.capture(text: "Keep the original attachment words", parentTask: parent)[0]
        try store.setOrganization(parent, pinned: false, projectName: "Launch")
        let note = try store.capture(text: "A project note", projectName: "Launch")[0]
        let link = try store.capture(text: "https://example.invalid/reference", projectName: "Launch")[0]
        let source = CaptureSnapshot(child)
        let receipt = try store.convertProjectItemsToTasks([child, note, note, link, parent])
        try expect(receipt.count == 3 && Set(receipt.captureIDs) == [child.id, note.id, link.id], "Batch conversion ignores duplicates and existing tasks")
        try expect(child.isTask && note.isTask && link.isTask && parent.isTask, "All chosen ordinary captures become tasks")
        try expect(child.projectName == "Launch" && child.parentTaskID == nil,
                   "Attachment promotion keeps inherited current project instead of reverting to stale stored ownership")
        try expect(child.kind == .text && child.originalText == source.originalText && child.capturedAt == source.capturedAt,
                   "Task conversion preserves immutable original content, kind and receipt time")
        try expect(link.kind == .link && link.originalURL == "https://example.invalid/reference", "A link task retains its link representation")
        try expect(store.canUndoProjectTaskConversion(receipt), "An untouched batch is undoable")
        store.failureInjector = { if $0 == .beforeMetadataSave { throw CaptureStoreError.importVerificationFailed } }
        try rejects({ try store.undoProjectTaskConversion(receipt) }, "Undo reports a failed transaction")
        try expect(child.isTask && note.isTask && link.isTask && child.parentTaskID == nil
            && child.projectName == "Launch" && store.canUndoProjectTaskConversion(receipt),
                   "Failed undo restores the complete converted batch and remains retryable")
        store.failureInjector = nil
        let workspace = WorkspaceStore(root: root)
        try workspace.saveProjectItemOrder([ProjectWorkspaceIdentity.capture(link.id), ProjectWorkspaceIdentity.capture(child.id)], project: "Launch")
        try store.undoProjectTaskConversion(receipt)
        try expect(!child.isTask && !note.isTask && !link.isTask && parent.isTask, "Batch undo restores only promoted items")
        try expect(child.parentTaskID == parent.id && child.projectName == source.projectName,
                   "Undo restores the original attachment relationship and underlying stored ownership")
        try expect(ExplorerQuery.project(of: child, in: store.captures) == "Launch", "Undo still displays the attachment in the parent's project")
        try expect(workspace.orderedProjectItemIDs([ProjectWorkspaceIdentity.capture(child.id), ProjectWorkspaceIdentity.capture(link.id)], project: "Launch").first == ProjectWorkspaceIdentity.capture(link.id),
                   "Task undo does not undo a later custom project order")
        try expect(!store.canUndoProjectTaskConversion(receipt), "An already-undone receipt cannot run twice")

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let snapshots = try store.captures.map { try encoder.encode(CaptureSnapshot($0)) }
        store.failureInjector = { if $0 == .beforeMetadataSave { throw CaptureStoreError.importVerificationFailed } }
        try rejects({ _ = try store.convertProjectItemsToTasks([child, note, link]) }, "Batch conversion surfaces a failed transaction")
        try expect(try store.captures.map { try encoder.encode(CaptureSnapshot($0)) } == snapshots,
                   "A failed conversion restores every touched field in memory")
        store.failureInjector = nil
        let reopened = try CaptureStore(root: root)
        try expect(reopened.captures.filter { $0.isTask }.map(\.id) == [parent.id], "A failed conversion cannot leak to persisted records")
        let stale = Capture(snapshot: CaptureSnapshot(note))
        try rejects({ _ = try store.convertProjectItemsToTasks([child, stale]) }, "A stale object aborts the entire batch before mutation")
        try expect(!child.isTask, "Earlier selected items stay unchanged when validation fails")

        let next = try store.convertProjectItemsToTasks([note, link])
        try store.setOrganization(note, pinned: true, projectName: "Launch")
        try expect(!store.canUndoProjectTaskConversion(next), "Later capture edits disable the batch undo")
        try rejects({ try store.undoProjectTaskConversion(next) }, "Undo refuses to discard later work")
        try expect(note.isTask && link.isTask && note.isPinned, "Guarded undo leaves the complete batch intact")
        let childReceipt = try store.convertProjectItemsToTasks([child])
        try store.setOrganization(parent, pinned: false, projectName: "Another")
        try rejects({ try store.undoProjectTaskConversion(childReceipt) }, "Undo refuses to silently move a child into a now-different parent project")
        try expect(child.isTask && child.projectName == "Launch", "A moved-parent undo failure keeps the independent task in its intended project")
    }
}
