import Foundation

@main
private enum DayExportTests {
    @MainActor private static var checks = 0

    @MainActor private static func expect(_ condition: @autoclosure () -> Bool,
                                          _ message: String) throws {
        checks += 1
        guard condition() else {
            throw NSError(domain: "DayExportTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private static let plusTwo = TimeZone(secondsFromGMT: 7_200)!

    private static func date(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = plusTwo
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: value)!
    }

    private static func uuid(_ suffix: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", suffix))!
    }

    private static func capture(id: Int, at stamp: String, day: String = "2026-09-24",
                                kind: CaptureKind = .text, title: String,
                                text: String? = nil, url: String? = nil,
                                filename: String? = nil,
                                origin: CaptureOrigin = .manual,
                                sourceName: String? = nil,
                                sourceBundle: String? = nil,
                                attachmentRelativePath: String? = nil,
                                actionID: UUID? = nil) -> Capture {
        let receipt: CaptureReceiptContext = origin == .manual ? .manual : .automatic(
            origin, actionID: actionID ?? uuid(10_000 + id), sourceApplicationName: sourceName,
            sourceApplicationBundleIdentifier: sourceBundle)
        return Capture(id: uuid(id), capturedAt: date(stamp), timeZone: plusTwo,
                       kind: kind, originalURL: url, originalText: text,
                       attachmentRelativePath: attachmentRelativePath,
                       originalFilename: filename, title: title, captureDay: day,
                       captureTimeZoneID: plusTwo.identifier,
                       captureUTCOffsetSeconds: 7_200, receipt: receipt)
    }

    @MainActor static func main() throws {
        try checkExactFormattingAndOrder()
        try checkSelectedDateAndCurrentDayCutoff()
        try checkIgnoresActiveFilter()
        try checkHistoricalDayIsComplete()
        try checkImageContentAndSourceFallback()
        try checkMultiItemActionGrouping()
        try checkEmptyAndByteEquivalence()
        try checkWeekRangeAndChronology()
        try checkWeekCutoffAndActionGrouping()
        try checkWeekFilterIndependenceAndEmptyOutput()
        print("PASS: \(checks) day/week export checks; deterministic content, fixed date scopes, cutoff, grouping and UTF-8 identity.")
    }

    @MainActor private static func checkExactFormattingAndOrder() throws {
        let later = capture(id: 3, at: "2026-09-24 16:20:04", kind: .link,
                            title: "DaBin reference", url: "https://example.com/dabin")
        let earlier = capture(id: 2, at: "2026-09-24 08:05:06", title: "Morning note",
                              text: "First line\r\nSecond line", origin: .automaticClipboard,
                              sourceName: "Notes", sourceBundle: "com.apple.Notes")
        earlier.comment = "Review this later"
        let document = DayExportDocument.make(
            captures: [later, earlier], selectedDate: date("2026-09-24 12:00:00"),
            now: date("2026-09-24 23:59:59"), calendarTimeZone: plusTwo)
        let expected = """
        DaBin Day Export
        Date: 2026-09-24
        Actions: 2

        1. 2026-09-24 08:05:06 +02:00
        Type: Note
        Source: Notes (com.apple.Notes)
        Title: Morning note
        Text:
          First line
          Second line
        Comment: Review this later

        2. 2026-09-24 16:20:04 +02:00
        Type: Link
        Title: DaBin reference
        URL: https://example.com/dabin

        """
        try expect(document.text == expected, "Export formatting is stable and chronological")
        try expect(document.actionCount == 2 && !document.isEmpty,
                   "The export reports its complete action count")

        let tiedFirst = capture(id: 10, at: "2026-09-24 18:00:00", title: "First UUID", text: "A")
        let tiedSecond = capture(id: 11, at: "2026-09-24 18:00:00", title: "Second UUID", text: "B")
        let tied = DayExportDocument.make(captures: [tiedSecond, tiedFirst],
                                          selectedDate: date("2026-09-24 18:00:00"),
                                          now: date("2026-09-24 23:59:59"), calendarTimeZone: plusTwo)
        try expect(tied.text.range(of: "First UUID")!.lowerBound < tied.text.range(of: "Second UUID")!.lowerBound,
                   "Equal timestamps use stable UUID ordering")
    }

    @MainActor private static func checkSelectedDateAndCurrentDayCutoff() throws {
        let previous = capture(id: 20, at: "2026-09-23 22:00:00", day: "2026-09-23",
                               title: "Previous day", text: "Old")
        let beforeNow = capture(id: 21, at: "2026-09-24 11:59:59", title: "Already recorded", text: "Now")
        let afterNow = capture(id: 22, at: "2026-09-24 12:00:01", title: "Future record", text: "Later")
        let carriedTask = capture(id: 23, at: "2026-09-23 08:00:00", day: "2026-09-23",
                                  kind: .task, title: "Open carried task", text: "Open carried task")
        let document = DayExportDocument.make(captures: [afterNow, carriedTask, previous, beforeNow],
                                              selectedDate: date("2026-09-24 09:00:00"),
                                              now: date("2026-09-24 12:00:00"), calendarTimeZone: plusTwo)
        try expect(document.actionCount == 1 && document.text.contains("Already recorded"),
                   "Today includes records through the current moment")
        try expect(!document.text.contains("Previous day") && !document.text.contains("Future record"),
                   "Selected-date membership and today's cutoff exclude unrelated records")
        try expect(!document.text.contains("Open carried task"),
                   "A task carried onto the board is exported only on its recorded capture day")
    }

    @MainActor private static func checkIgnoresActiveFilter() throws {
        let note = capture(id: 24, at: "2026-09-24 13:00:00", title: "Unfiltered note", text: "Note body")
        let link = capture(id: 25, at: "2026-09-24 13:01:00", kind: .link,
                           title: "Unfiltered link", url: "https://example.com/all")
        let allCaptures = [note, link]
        let activeFilter = CaptureFilter.links
        try expect(allCaptures.filter { activeFilter.includes($0.kind) }.map(\.id) == [link.id],
                   "The fixture's visible board filter excludes the note")
        let document = DayExportDocument.make(captures: allCaptures,
                                              selectedDate: date("2026-09-24 13:00:00"),
                                              now: date("2026-09-24 14:00:00"), calendarTimeZone: plusTwo)
        try expect(document.actionCount == 2 && document.text.contains("Unfiltered note")
                   && document.text.contains("Unfiltered link"),
                   "Day export receives the complete archive and ignores the active content filter")
    }

    @MainActor private static func checkHistoricalDayIsComplete() throws {
        let historicalFutureClock = capture(id: 30, at: "2026-09-23 23:59:59", day: "2026-09-23",
                                            title: "End of past day", text: "Still included")
        let document = DayExportDocument.make(captures: [historicalFutureClock],
                                              selectedDate: date("2026-09-23 08:00:00"),
                                              now: date("2026-09-24 09:00:00"), calendarTimeZone: plusTwo)
        try expect(document.actionCount == 1 && document.text.contains("23:59:59"),
                   "A past date exports its complete stored day")
    }

    @MainActor private static func checkImageContentAndSourceFallback() throws {
        let placeholder = capture(id: 40, at: "2026-09-24 09:00:00", kind: .image,
                                  title: "Screenshot 2026-09-24", filename: "shot.png",
                                  origin: .automaticScreenshot, sourceBundle: "com.apple.screencapture")
        placeholder.previewDescription = "1440 × 900"
        let ocr = capture(id: 41, at: "2026-09-24 09:01:00", kind: .image,
                          title: "Whiteboard", text: "OCR: launch checklist")
        let captioned = capture(id: 42, at: "2026-09-24 09:02:00", kind: .image,
                                title: "Sketch")
        captioned.comment = "Purple robot concept"
        let document = DayExportDocument.make(captures: [ocr, captioned, placeholder],
                                              selectedDate: date("2026-09-24 09:00:00"),
                                              now: date("2026-09-24 10:00:00"), calendarTimeZone: plusTwo)
        try expect(document.text.contains("Type: Screenshot") && document.text.contains("Content: [Screenshot]"),
                   "An image-only screenshot has an explicit type and placeholder")
        try expect(document.text.contains("Source: com.apple.screencapture"),
                   "The source bundle identifies an app when no display name exists")
        try expect(document.text.contains("Text: OCR: launch checklist")
                   && document.text.contains("Comment: Purple robot concept"),
                   "Image OCR and caption text are exported when available")
        try expect(document.text.components(separatedBy: "Content: [Image]").count == 1,
                   "OCR and captioned images do not receive misleading empty-image placeholders")
    }

    @MainActor private static func checkMultiItemActionGrouping() throws {
        let receipt = date("2026-09-24 14:30:00")
        let firstFile = capture(id: 50, at: "2026-09-24 14:30:00", kind: .document,
                                title: "Project brief", text: "First attachment text",
                                filename: "brief.txt", attachmentRelativePath: "Items/brief.txt")
        let secondFile = capture(id: 51, at: "2026-09-24 14:30:00", kind: .pdf,
                                 title: "Research PDF", filename: "research.pdf",
                                 attachmentRelativePath: "Items/research.pdf")
        try expect(firstFile.capturedAt == receipt && secondFile.capturedAt == receipt,
                   "The manual batch fixture shares one immutable receipt")

        let automaticActionID = uuid(52_000)
        let copiedText = capture(id: 52, at: "2026-09-24 15:00:00", title: "Copied note",
                                 text: "Automatic text", origin: .automaticClipboard,
                                 sourceName: "Notes", sourceBundle: "com.apple.Notes",
                                 actionID: automaticActionID)
        let copiedLink = capture(id: 53, at: "2026-09-24 15:00:00", kind: .link,
                                 title: "Copied link", url: "https://example.com/grouped",
                                 origin: .automaticClipboard, sourceName: "Notes",
                                 sourceBundle: "com.apple.Notes", actionID: automaticActionID)
        let document = DayExportDocument.make(
            captures: [copiedLink, secondFile, copiedText, firstFile],
            selectedDate: date("2026-09-24 12:00:00"),
            now: date("2026-09-24 23:59:59"), calendarTimeZone: plusTwo)

        try expect(document.actionCount == 2 && document.text.contains("Actions: 2"),
                   "A multi-file receipt and a multi-item automatic receipt each count as one action")
        try expect(document.text.components(separatedBy: "Items: 2").count == 3,
                   "Each grouped action clearly identifies its member count")
        try expect(document.text.contains("File: brief.txt")
                   && document.text.contains("File: research.pdf")
                   && document.text.contains("Text: First attachment text")
                   && document.text.contains("Text: Automatic text")
                   && document.text.contains("URL: https://example.com/grouped"),
                   "Grouping retains every exported item's available content")
        try expect(document.text.components(separatedBy: "Source: Notes (com.apple.Notes)").count == 2,
                   "A source application shared by an automatic action is written once")
        try expect(document.text.range(of: "Project brief")!.lowerBound
                   < document.text.range(of: "Copied note")!.lowerBound,
                   "Grouped actions remain chronological")
    }

    @MainActor private static func checkEmptyAndByteEquivalence() throws {
        let document = DayExportDocument.make(captures: [],
                                              selectedDate: date("2026-09-24 12:00:00"),
                                              now: date("2026-09-24 12:00:00"), calendarTimeZone: plusTwo)
        try expect(document.isEmpty && document.actionCount == 0,
                   "An empty selected date is explicit to the action popover")
        try expect(document.text == "DaBin Day Export\nDate: 2026-09-24\nActions: 0\n",
                   "An empty document remains deterministic")
        try expect(document.filename == "DaBin-2026-09-24.txt",
                   "The file uses the required ISO calendar-day name")
        try expect(String(data: document.utf8Data, encoding: .utf8) == document.text,
                   "Clipboard text and file bytes represent exactly the same output")
        try expect(document.utf8Data == Data(document.text.utf8),
                   "The file payload is unambiguously UTF-8")
    }

    @MainActor private static func checkWeekRangeAndChronology() throws {
        let outsideBefore = capture(id: 60, at: "2026-12-26 23:59:59", day: "2026-12-26",
                                    title: "Outside before", text: "Excluded")
        let weekStart = capture(id: 61, at: "2026-12-27 07:00:00", day: "2026-12-27",
                                title: "Week start", text: "First")
        let yearEnd = capture(id: 62, at: "2026-12-31 18:30:00", day: "2026-12-31",
                              kind: .link, title: "Year-end link",
                              url: "https://example.com/year-end")
        let weekEnd = capture(id: 63, at: "2027-01-02 23:59:59", day: "2027-01-02",
                              title: "Week end", text: "Last")
        let outsideAfter = capture(id: 64, at: "2027-01-03 00:00:00", day: "2027-01-03",
                                   title: "Outside after", text: "Excluded")
        let document = WeekExportDocument.make(
            captures: [outsideAfter, weekEnd, yearEnd, weekStart, outsideBefore],
            weekEndingDate: date("2027-01-02 12:00:00"),
            now: date("2027-01-03 12:00:00"), calendarTimeZone: plusTwo)
        let expected = """
        DaBin Week Export
        Week: 2026-12-27 to 2027-01-02
        Actions: 3

        1. 2026-12-27 07:00:00 +02:00
        Type: Note
        Title: Week start
        Text: First

        2. 2026-12-31 18:30:00 +02:00
        Type: Link
        Title: Year-end link
        URL: https://example.com/year-end

        3. 2027-01-02 23:59:59 +02:00
        Type: Note
        Title: Week end
        Text: Last

        """
        try expect(document.startDay == "2026-12-27" && document.endDay == "2027-01-02",
                   "Week export spans exactly seven local calendar dates across month and year")
        try expect(document.actionCount == 3 && document.text == expected,
                   "Week export excludes adjacent dates and formats in chronological order")
        try expect(!document.text.contains("Outside before") && !document.text.contains("Outside after"),
                   "Stored captureDay membership controls both week boundaries")
        try expect(document.filename == "DaBin-Week-2026-12-27-to-2027-01-02.txt",
                   "Week export filename contains its exact ISO date range")
    }

    @MainActor private static func checkWeekCutoffAndActionGrouping() throws {
        let batchStamp = "2026-09-20 10:00:00"
        let firstFile = capture(id: 70, at: batchStamp, day: "2026-09-20", kind: .document,
                                title: "Weekly brief", filename: "brief.txt",
                                attachmentRelativePath: "Items/brief.txt")
        let secondFile = capture(id: 71, at: batchStamp, day: "2026-09-20", kind: .pdf,
                                 title: "Weekly research", filename: "research.pdf",
                                 attachmentRelativePath: "Items/research.pdf")
        let copiedActionID = uuid(72_000)
        let copiedText = capture(id: 72, at: "2026-09-24 11:59:00", title: "Copied before now",
                                 text: "Saved text", origin: .automaticClipboard,
                                 sourceName: "Notes", sourceBundle: "com.apple.Notes",
                                 actionID: copiedActionID)
        let copiedLink = capture(id: 73, at: "2026-09-24 11:59:00", kind: .link,
                                 title: "Copied link before now", url: "https://example.com/today",
                                 origin: .automaticClipboard, sourceName: "Notes",
                                 sourceBundle: "com.apple.Notes", actionID: copiedActionID)
        let afterNow = capture(id: 74, at: "2026-09-24 12:00:01",
                               title: "Today after now", text: "Excluded")
        let futureStoredDay = capture(id: 75, at: "2026-09-25 08:00:00", day: "2026-09-25",
                                      title: "Future stored day", text: "Excluded")
        let document = WeekExportDocument.make(
            captures: [afterNow, copiedLink, secondFile, futureStoredDay, copiedText, firstFile],
            weekEndingDate: date("2026-09-24 09:00:00"),
            now: date("2026-09-24 12:00:00"), calendarTimeZone: plusTwo)

        try expect(document.actionCount == 2,
                   "A manual multi-file receipt and automatic multi-item receipt each count as one week action")
        try expect(document.text.components(separatedBy: "Items: 2").count == 3
                   && document.text.contains("Weekly brief")
                   && document.text.contains("Weekly research")
                   && document.text.contains("Copied before now")
                   && document.text.contains("Copied link before now"),
                   "Week action grouping retains every member and its available content")
        try expect(!document.text.contains("Today after now")
                   && !document.text.contains("Future stored day"),
                   "A current week stops at now and never imports a future stored day")
        try expect(document.text.range(of: "Weekly brief")!.lowerBound
                   < document.text.range(of: "Copied before now")!.lowerBound,
                   "Grouped week actions remain chronological across dates")
    }

    @MainActor private static func checkWeekFilterIndependenceAndEmptyOutput() throws {
        let note = capture(id: 80, at: "2026-09-21 09:00:00", day: "2026-09-21",
                           title: "Unfiltered weekly note", text: "Note body")
        let link = capture(id: 81, at: "2026-09-22 09:00:00", day: "2026-09-22", kind: .link,
                           title: "Unfiltered weekly link", url: "https://example.com/week")
        let captures = [note, link]
        try expect(captures.filter { CaptureFilter.links.includes($0.kind) }.map(\.id) == [link.id],
                   "The fixture's visible Links filter excludes the weekly note")
        let document = WeekExportDocument.make(
            captures: captures, weekEndingDate: date("2026-09-24 09:00:00"),
            now: date("2026-09-24 12:00:00"), calendarTimeZone: plusTwo)
        try expect(document.actionCount == 2 && document.text.contains("Unfiltered weekly note")
                   && document.text.contains("Unfiltered weekly link"),
                   "Week export receives the complete archive and ignores active content filters")

        let empty = WeekExportDocument.make(
            captures: [], weekEndingDate: date("2027-01-02 12:00:00"),
            now: date("2027-01-03 12:00:00"), calendarTimeZone: plusTwo)
        try expect(empty.isEmpty && empty.actionCount == 0
                   && empty.text == "DaBin Week Export\nWeek: 2026-12-27 to 2027-01-02\nActions: 0\n",
                   "An empty fixed week has deterministic explicit output")
        try expect(String(data: document.utf8Data, encoding: .utf8) == document.text
                   && document.utf8Data == Data(document.text.utf8)
                   && String(data: empty.utf8Data, encoding: .utf8) == empty.text,
                   "Week downloads are exact UTF-8 representations of copied text")
    }
}
