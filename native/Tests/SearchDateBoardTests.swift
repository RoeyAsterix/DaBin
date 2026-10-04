import Foundation

@main struct SearchDateBoardTests {
    @MainActor private static var checks = 0
    @MainActor private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard condition() else {
            throw NSError(domain: "SearchDateBoardTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private static func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    @MainActor private static func capture(_ number: Int, at timestamp: String, day: String,
                                           kind: CaptureKind = .text) -> Capture {
        let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", number))!
        return Capture(id: id, capturedAt: date(timestamp), timeZone: TimeZone(secondsFromGMT: 0)!,
                       kind: kind, title: "Fictional result \(number)", captureDay: day)
    }

    private static func entry(_ capture: Capture, match: Bool = true, snippet: String? = nil) -> SearchEntry {
        SearchEntry(capture: capture, isMatch: match, indexedTextMatch: snippet)
    }

    @MainActor static func main() throws {
        let utc = TimeZone(secondsFromGMT: 0)!
        let early = capture(1, at: "2026-12-31T09:00:00Z", day: "2026-12-31")
        let late = capture(2, at: "2026-12-31T19:00:00Z", day: "2026-12-31")
        let nextYear = capture(3, at: "2027-01-01T01:00:00Z", day: "2027-01-01")
        let middleNote = WorkspaceScratchpad(text: "Fictional project return note", projectName: "Atlas",
                                            updatedAt: date("2026-12-31T12:00:00Z"))
        let newYearNote = WorkspaceScratchpad(text: "Fictional new year plan", projectName: "Northstar",
                                            updatedAt: date("2027-01-01T02:00:00Z"))
        let mixed = SearchDateBoard.groups(captureGroups: [
            SearchGroup(day: "2026-12-31", entries: [entry(early), entry(late)]),
            SearchGroup(day: "2027-01-01", entries: [entry(nextYear)])
        ], notes: [middleNote, newYearNote], timeZone: utc)
        try expect(mixed.map(\.day) == ["2027-01-01", "2026-12-31"],
                   "Matching dates remain newest first across month and year boundaries")
        try expect(mixed.map(\.matchCount) == [2, 3], "Notes and captures contribute to the matching day count")
        try expect(mixed[1].items.map(\.id) == [SearchDateItem.capture(entry(late)).id,
                   SearchDateItem.note(middleNote).id, SearchDateItem.capture(entry(early)).id],
                   "Notes are interleaved with captures by timestamp rather than placed in a separate section")
        try expect(mixed[1].captureEntries.map(\.id) == [late.id, early.id], "Captures within each day are newest first")
        try expect(mixed[1].items[1].scratchpad?.projectName == "Atlas"
                   && mixed[1].items[1].captureEntry == nil,
                   "A note retains its distinct edited-date semantics and project identity")
        try expect(mixed[0].items.first?.timestamp == newYearNote.updatedAt,
                   "The newest saved or edited item leads its date column")

        let completed = capture(4, at: "2026-03-01T11:00:00Z", day: "2026-03-01", kind: .task)
        completed.isCompleted = true
        completed.comment = "Fictional later comment edit"
        completed.updatedAt = date("2026-10-03T16:00:00Z")
        completed.setTaskPlanning(TaskPlanning(plannedDay: "2026-10-04",
            deadline: date("2026-10-05T17:00:00Z")))
        let immutable = SearchDateBoard.groups(captureGroups: [SearchGroup(day: "2099-01-01", entries: [entry(completed)])],
                                              notes: [], timeZone: utc)
        try expect(immutable.map(\.day) == ["2026-03-01"],
                   "A completed task uses its immutable receipt day, never its container label, comment edit or planned day")
        try expect(immutable.first?.matchCount == 1, "Completed matching tasks remain eligible")

        let east = TimeZone(secondsFromGMT: 2 * 3_600)!
        let editedNearMidnight = WorkspaceScratchpad(text: "Fictional midnight note", projectName: "Midnight",
                                                    updatedAt: date("2026-12-31T23:30:00Z"))
        let recordedElsewhere = capture(5, at: "2026-12-31T23:30:00Z", day: "2026-12-31")
        let midnight = SearchDateBoard.groups(captureGroups: [SearchGroup(day: "wrong", entries: [entry(recordedElsewhere)])],
                                             notes: [editedNearMidnight], timeZone: east)
        try expect(midnight.map(\.day) == ["2027-01-01", "2026-12-31"],
                   "Notes use local edited days while captures preserve their originally recorded calendar day")
        try expect(midnight[0].captureEntries.isEmpty && midnight[1].captureEntries.first?.id == recordedElsewhere.id,
                   "A time-zone change never re-dates capture receipts to match notes")

        let berlin = TimeZone(identifier: "Europe/Berlin")!
        let beforeDST = WorkspaceScratchpad(text: "Fictional early edit", projectName: "Before",
                                           updatedAt: date("2026-03-29T00:30:00Z"))
        let afterDST = WorkspaceScratchpad(text: "Fictional later edit", projectName: "After",
                                          updatedAt: date("2026-03-29T01:30:00Z"))
        let dst = SearchDateBoard.groups(captureGroups: [], notes: [beforeDST, afterDST], timeZone: berlin)
        try expect(dst.count == 1 && dst[0].day == "2026-03-29" && dst[0].matchCount == 2,
                   "Daylight-saving changes produce a calendar-day column, not a rolling 24-hour interval")
        try expect(dst[0].items.first?.scratchpad?.projectName == "After", "Edited instants keep their chronological order across DST")

        let neighbor = capture(6, at: "2026-12-31T20:00:00Z", day: "2026-12-31", kind: .pdf)
        let contextOnly = capture(7, at: "2026-12-30T20:00:00Z", day: "2026-12-30")
        let contexts = [SearchGroup(day: "2026-12-31", entries: [entry(late), entry(neighbor, match: false)]),
                        SearchGroup(day: "2026-12-30", entries: [entry(contextOnly, match: false)])]
        let matchesOnly = SearchDateBoard.groups(captureGroups: contexts, notes: [], timeZone: utc)
        try expect(matchesOnly.count == 1 && matchesOnly[0].captureEntries.map(\.id) == [late.id],
                   "Default presentation contains matching items only and hides context-only dates")
        let withContext = SearchDateBoard.groups(captureGroups: contexts, notes: [], includeContext: true, timeZone: utc)
        try expect(withContext.count == 1 && withContext[0].items.count == 2 && withContext[0].matchCount == 1,
                   "Explicit nearby context enriches a matching day without inflating totals or creating empty-match columns")
        try expect(withContext[0].items.first?.isMatch == false, "Chronology preserves context labels rather than promoting them to matches")

        let duplicates = SearchDateBoard.groups(captureGroups: [
            SearchGroup(day: "one", entries: [entry(late, match: false), entry(late)]),
            SearchGroup(day: "two", entries: [entry(late, snippet: "Fictional recognized match")])
        ], notes: [middleNote, middleNote], includeContext: true, timeZone: utc)
        try expect(duplicates.count == 1 && duplicates[0].items.count == 2 && duplicates[0].matchCount == 2,
                   "Overlapping match/context inputs and repeated project notes never duplicate rows or totals")
        try expect(duplicates[0].captureEntries.first?.isMatch == true
                   && duplicates[0].captureEntries.first?.indexedTextMatch == "Fictional recognized match",
                   "Duplicate receipt resolution preserves matching status and available extracted-text evidence")

        let deleted = capture(8, at: "2026-12-31T21:00:00Z", day: "2026-12-31")
        deleted.deletedAt = date("2026-12-31T22:00:00Z")
        let blank = WorkspaceScratchpad(text: " \n\t ", projectName: "Blank", updatedAt: middleNote.updatedAt)
        try expect(SearchDateBoard.groups(captureGroups: [SearchGroup(day: "2026-12-31", entries: [entry(deleted)])],
                                          notes: [blank], timeZone: utc).isEmpty,
                   "Deleted captures and empty project markers cannot become search-result dates")

        let malformedDays = ["2026-02-30", "2026-02-29", "2026-13-01", "2026-1-01", "", "undated", "0000-01-01"]
        let malformedEntries = malformedDays.enumerated().map {
            entry(capture(20 + $0.offset, at: "2027-01-02T01:00:00Z", day: $0.element))
        }
        let leapDay = capture(30, at: "2024-02-29T12:00:00Z", day: "2024-02-29")
        let invalidNote = WorkspaceScratchpad(text: "Fictional undated imported note", projectName: "Unknown",
                                             updatedAt: Date(timeIntervalSinceReferenceDate: .nan))
        let undated = SearchDateBoard.groups(captureGroups: [SearchGroup(day: "container", entries: malformedEntries + [entry(leapDay)])],
                                            notes: [invalidNote], timeZone: utc)
        try expect(undated.map(\.day) == ["2024-02-29", SearchDateBoard.undatedDay],
                   "Malformed and impossible dates form an honest final Undated column; valid leap days remain dated")
        try expect(undated.last?.matchCount == malformedDays.count + 1 && undated.last?.isUndated == true,
                   "Undated matches are retained and counted instead of assigned a fabricated saved day")

        let inboxNote = WorkspaceScratchpad(text: "Fictional inbox note", projectName: nil, updatedAt: middleNote.updatedAt)
        let namedInbox = WorkspaceScratchpad(text: "Fictional named project", projectName: "inbox:", updatedAt: middleNote.updatedAt)
        try expect(SearchDateItem.note(inboxNote).id != SearchDateItem.note(namedInbox).id,
                   "Inbox and named project notes cannot collide in row identity")
        var edited = middleNote; edited.text = "Fictional revised project note"; edited.updatedAt = newYearNote.updatedAt
        try expect(SearchDateItem.note(middleNote).id == SearchDateItem.note(edited).id,
                   "Editing a note retains selection identity even when its date changes")
        let latestNote = SearchDateBoard.groups(captureGroups: [], notes: [middleNote, edited], timeZone: utc)
        try expect(latestNote.count == 1 && latestNote[0].items.first?.scratchpad?.text == edited.text,
                   "Repeated project-note snapshots resolve to the newest edited note")

        try expect(SearchDateBoard.columnCount(width: 380) == 1, "Compact search uses one readable date column")
        try expect(SearchDateBoard.columnCount(width: 736) == 2, "An intermediate window uses two date columns")
        try expect(SearchDateBoard.columnCount(width: 1_060) == 3, "An expanded window uses three readable date columns")
        try expect(SearchDateBoard.columnCount(width: 639) == 1
                   && SearchDateBoard.columnCount(width: 640) == 2,
                   "Two date columns appear only when their content area provides at least 320 points each")
        try expect(SearchDateBoard.columnCount(width: 959) == 2
                   && SearchDateBoard.columnCount(width: 960) == 3,
                   "Three date columns appear at the native content-width boundary rather than the outer window width")
        try expect(SearchDateBoard.columnCount(width: 676) == 2
                   && SearchDateBoard.columnCount(width: 1_000) == 3
                   && SearchDateBoard.columnCount(width: 686) == 2,
                   "Native frame insets and a selected wide preview retain readable two- or three-column boards")
        try expect(SearchDateBoard.columnCount(width: -1) == 1
                   && SearchDateBoard.columnCount(width: .nan) == 1
                   && SearchDateBoard.columnCount(width: .infinity) == 1,
                   "Transient invalid geometry never creates zero columns or unbounded rendering")

        let reference = date("2026-10-03T12:00:00Z")
        let history = (0..<600).map { index -> SearchGroup in
            let timestamp = reference.addingTimeInterval(-Double(index) * 86_400)
            let saved = Capture(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", index + 100))!,
                                capturedAt: timestamp, timeZone: utc, kind: .text, title: "Fictional archive \(index)")
            return SearchGroup(day: saved.captureDay, entries: [entry(saved)])
        }
        let dates = SearchDateBoard.groups(captureGroups: history, notes: [], timeZone: utc)
        try expect(dates.count == 600 && dates.reduce(0) { $0 + $1.matchCount } == 600,
                   "Presentation paging searches and counts the entire history rather than truncating matches")
        let first = SearchDateBoard.page(groups: dates, anchorDay: nil, width: 1_060)
        try expect(first.groups.count == 3 && first.startIndex == 0 && first.endIndex == 3 && first.totalCount == 600,
                   "A large history materializes only the three visible date columns")
        try expect(first.rangeLabel == "Dates 1 to 3 of 600" && first.newerAnchor == nil && first.olderAnchor == dates[3].day,
                   "Page controls and range communicate dates outside the visible page")
        let older = SearchDateBoard.page(groups: dates, anchorDay: first.olderAnchor, width: 1_060)
        try expect(older.startIndex == 3 && older.newerAnchor == dates[0].day && older.olderAnchor == dates[6].day,
                   "Older and newer controls step through actual matching dates without empty calendar gaps")
        let offBoundary = dates[5].day
        let compactPage = SearchDateBoard.page(groups: dates, anchorDay: offBoundary, width: 380)
        let widePage = SearchDateBoard.page(groups: dates, anchorDay: offBoundary, width: 1_060)
        try expect(compactPage.startIndex == 5 && widePage.startIndex == 5
                   && compactPage.anchorDay == offBoundary && widePage.anchorDay == offBoundary,
                   "Resizing preserves the exact first visible date instead of snapping to a page boundary")
        let inserted = SearchDateBoard.groups(captureGroups: [SearchGroup(day: "2027-01-01", entries: [entry(nextYear)])] + history,
                                             notes: [], timeZone: utc)
        try expect(SearchDateBoard.page(groups: inserted, anchorDay: offBoundary, width: 1_060).anchorDay == offBoundary,
                   "A newer live result does not pull an older browsing page back to the top")
        let removedAnchor = dates.filter { $0.day != offBoundary }
        try expect(SearchDateBoard.page(groups: removedAnchor, anchorDay: offBoundary, width: 1_060).anchorDay == dates[6].day,
                   "Removing the anchored date continues at its next older matching date")
        let between = SearchDateBoard.page(groups: [mixed[0], immutable[0]], anchorDay: "2026-08-01", width: 380)
        try expect(between.anchorDay == "2026-03-01", "Missing anchors fall back by date rather than an unrelated stale array index")

        let last = SearchDateBoard.page(groups: dates, startIndex: Int.max, columns: Int.max)
        try expect(last.startIndex == 599 && last.groups.count == 1 && last.columnCount == 3
                   && !last.hasOlder && last.hasNewer && last.rangeLabel == "Dates 600 to 600 of 600",
                   "Out-of-range indices and column requests clamp safely without integer overflow")
        let negative = SearchDateBoard.page(groups: dates, startIndex: Int.min, columns: 0)
        try expect(negative.startIndex == 0 && negative.groups.count == 1 && negative.columnCount == 1,
                   "Negative indices and zero columns retain a usable first page")
        try expect(SearchDateBoard.page(groups: dates, startIndex: 0, columns: -7).groups.count == 1,
                   "Negative column counts remain a bounded one-column page")
        let empty = SearchDateBoard.page(groups: [], anchorDay: "2026-10-03", columns: 0)
        try expect(empty.groups.isEmpty && empty.startIndex == 0 && empty.endIndex == 0
                   && empty.totalCount == 0 && empty.rangeLabel == "No matching dates"
                   && !empty.hasOlder && !empty.hasNewer,
                   "An empty archive exposes no bogus navigation or date range")
        try expect(SearchDateBoard.anchorIndex(for: "not a date", in: dates) == 0,
                   "Malformed restored anchors safely begin at the newest actual matching date")
        try expect(SearchDateBoard.page(groups: undated, anchorDay: SearchDateBoard.undatedDay, width: 380).groups.first?.isUndated == true,
                   "The honest Undated column can be reached and restored with the same date navigation")

        print("PASS: \(checks) date search grouping, chronology, note semantics, context counts and bounded paging checks")
    }
}
