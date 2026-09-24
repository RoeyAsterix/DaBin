import Foundation

@main
struct HourlyGroupingTests {
    @MainActor private static var checks = 0

    @MainActor private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        if !condition() {
            throw NSError(domain: "HourlyGroupingTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private static func uuid(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", number))!
    }

    private static func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)!
    }

    @MainActor private static func automatic(
        id: Int,
        action: Int,
        stamp: String,
        kind: CaptureKind = .text,
        origin: CaptureOrigin = .automaticClipboard,
        captureDay: String = "2026-09-23",
        offset: Int = 10_800,
        attachment: Bool = false
    ) -> Capture {
        Capture(id: uuid(id), capturedAt: date(stamp),
                timeZone: TimeZone(secondsFromGMT: offset)!, kind: kind,
                originalText: kind == .text ? "Automatic \(id)" : nil,
                attachmentRelativePath: attachment ? "Archive/fixture/\(id)" : nil,
                originalFilename: attachment ? "fixture-\(id).dat" : nil,
                title: "Automatic \(id)", captureDay: captureDay,
                captureUTCOffsetSeconds: offset,
                receipt: .automatic(origin, actionID: uuid(action),
                                    sourceApplicationName: "Fixture App",
                                    sourceApplicationBundleIdentifier: "com.dabin.fixture"))
    }

    @MainActor private static func manual(id: Int, stamp: String,
                                          attachment: Bool = false) -> Capture {
        Capture(id: uuid(id), capturedAt: date(stamp),
                timeZone: TimeZone(secondsFromGMT: 10_800)!, kind: attachment ? .file : .text,
                originalText: attachment ? nil : "Manual \(id)",
                attachmentRelativePath: attachment ? "Archive/manual/\(id)" : nil,
                originalFilename: attachment ? "manual-\(id).dat" : nil,
                title: "Manual \(id)", captureDay: "2026-09-23",
                captureUTCOffsetSeconds: 10_800)
    }

    private static func groups(_ cards: [CaptureFeedCard]) -> [AutomaticHourGroup] {
        cards.compactMap { card in
            if case .automaticHour(let group) = card { return group }
            return nil
        }
    }

    private static func regular(_ cards: [CaptureFeedCard]) -> [CaptureCardGroup] {
        cards.compactMap { card in
            if case .capture(let capture) = card { return capture }
            return nil
        }
    }

    @MainActor static func main() throws {
        let today = date("2026-09-23T12:00:00Z")
        let todayZone = TimeZone(secondsFromGMT: 10_800)!
        func feed(_ captures: [Capture], filter: CaptureFilter = .all,
                  now: Date = today, zone: TimeZone = todayZone) -> [CaptureFeedCard] {
            HourlyCaptureFeed.cards(from: captures, filter: filter, today: now, calendarTimeZone: zone)
        }

        let first = automatic(id: 1, action: 101, stamp: "2026-09-23T11:52:00Z")
        let second = automatic(id: 2, action: 102, stamp: "2026-09-23T11:41:00Z")
        let third = automatic(id: 3, action: 103, stamp: "2026-09-23T11:20:00Z")
        let note = manual(id: 90, stamp: "2026-09-23T11:45:00Z")
        let three = feed([first, note, second, third])
        try expect(groups(three).isEmpty, "Three automatic actions remain individual")
        try expect(regular(three).count == 4, "A manual card remains independent among three automatic actions")
        try expect(three.flatMap(\.captures).map(\.id) == [first.id, note.id, second.id, third.id],
                   "Sub-threshold feed preserves the caller's newest-first order")

        let fourth = automatic(id: 4, action: 104, stamp: "2026-09-23T11:58:00Z")
        let four = feed([fourth, first, note, second, third])
        let fourGroups = groups(four)
        try expect(fourGroups.count == 1 && fourGroups[0].totalActionCount == 4,
                   "The fourth successfully saved action creates one hourly summary")
        try expect(fourGroups[0].visibleActionCount == 4 && fourGroups[0].captures.count == 4,
                   "The summary contains every action from its fixed hour")
        try expect(fourGroups[0].id.rangeLabel == "14:00–14:59",
                   "Hour range is reconstructed from the receipt offset")
        try expect(fourGroups[0].summaryTitle == "14:00–14:59 · 4 actions",
                   "Today's unfiltered summary uses the requested compact label")
        try expect(regular(four).count == 1 && regular(four)[0].primary.id == note.id,
                   "Manual content is never absorbed into an automatic summary")

        let fifth = automatic(id: 5, action: 105, stamp: "2026-09-23T11:59:00Z")
        let fiveGroup = groups(feed([fifth, fourth, first, note, second, third]))[0]
        try expect(fiveGroup.id == fourGroups[0].id,
                   "Adding an action updates the same stable hour-group identity")
        try expect(fiveGroup.totalActionCount == 5 && fiveGroup.summaryTitle.hasSuffix("5 actions"),
                   "A later action updates the existing count immediately")

        let sharedA = automatic(id: 11, action: 201, stamp: "2026-09-23T11:55:00Z")
        let sharedB = automatic(id: 12, action: 201, stamp: "2026-09-23T11:55:00Z", kind: .link)
        let otherA = automatic(id: 13, action: 202, stamp: "2026-09-23T11:40:00Z")
        let otherB = automatic(id: 14, action: 203, stamp: "2026-09-23T11:30:00Z")
        let multiThree = feed([sharedA, sharedB, otherA, otherB])
        try expect(groups(multiThree).isEmpty,
                   "Several capture records from one copy still count as one action")
        try expect(regular(multiThree).count == 4,
                   "Sub-threshold multi-item action preserves all of its existing individual cards")
        let otherC = automatic(id: 15, action: 204, stamp: "2026-09-23T11:10:00Z")
        let multiFour = groups(feed([sharedA, sharedB, otherA, otherB, otherC]))[0]
        try expect(multiFour.totalActionCount == 4 && multiFour.captures.count == 5,
                   "Four action IDs summarize even when they contain five capture records")
        try expect(multiFour.actions.first?.id == uuid(201)
                   && multiFour.actions.first?.cards.count == 2,
                   "Expanded content retains every card belonging to a multi-item action")

        let link = automatic(id: 21, action: 301, stamp: "2026-09-23T11:53:00Z", kind: .link)
        let image = automatic(id: 22, action: 302, stamp: "2026-09-23T11:43:00Z", kind: .image)
        let pdf = automatic(id: 23, action: 303, stamp: "2026-09-23T11:33:00Z", kind: .pdf)
        let text = automatic(id: 24, action: 304, stamp: "2026-09-23T11:23:00Z")
        let linksOnly = groups(feed([link, image, pdf, text], filter: .links))[0]
        try expect(linksOnly.totalActionCount == 4 && linksOnly.visibleActionCount == 1,
                   "Filtering never reverses a qualifying four-action hour")
        try expect(linksOnly.summaryTitle == "14:00–14:59 · 1 of 4 actions",
                   "Filtered summary distinguishes matching actions from the stable total")
        let textOnly = groups(feed([link, image, pdf, text], filter: .text))[0]
        try expect(textOnly.totalActionCount == 4 && textOnly.visibleActionCount == 1
                   && textOnly.captures.map(\.id) == [text.id],
                   "Text filter retains only copied plain text inside a qualifying automatic hour")
        try expect(feed([link, image, pdf, text], filter: .tasks).isEmpty,
                   "A qualifying hour is hidden when none of its actions match the filter")

        let yesterdayCaptures = [
            automatic(id: 31, action: 401, stamp: "2026-09-22T11:50:00Z", captureDay: "2026-09-22"),
            automatic(id: 32, action: 402, stamp: "2026-09-22T11:40:00Z", captureDay: "2026-09-22"),
            automatic(id: 33, action: 403, stamp: "2026-09-22T11:30:00Z", captureDay: "2026-09-22"),
            automatic(id: 34, action: 404, stamp: "2026-09-22T11:20:00Z", captureDay: "2026-09-22")
        ]
        let yesterday = groups(feed(yesterdayCaptures))[0]
        try expect(yesterday.displaysDate && yesterday.summaryTitle.contains("2026"),
                   "A previous-day summary includes its date")
        try expect(!fourGroups[0].displaysDate,
                   "A current-day summary omits the redundant date")

        let nextHour = [
            automatic(id: 41, action: 501, stamp: "2026-09-23T12:01:00Z"),
            automatic(id: 42, action: 502, stamp: "2026-09-23T12:11:00Z"),
            automatic(id: 43, action: 503, stamp: "2026-09-23T12:21:00Z"),
            automatic(id: 44, action: 504, stamp: "2026-09-23T12:31:00Z")
        ]
        let twoHours = groups(feed(nextHour + [fourth, first, second, third]))
        try expect(twoHours.count == 2 && Set(twoHours.map(\.id.rangeLabel)) == ["14:00–14:59", "15:00–15:59"],
                   "Fixed clock hours do not roll across their minute boundary")

        let dstFirst = automatic(id: 51, action: 601, stamp: "2026-11-01T05:30:00Z",
                                 captureDay: "2026-11-01", offset: -14_400)
        let dstSecond = automatic(id: 52, action: 602, stamp: "2026-11-01T06:30:00Z",
                                  captureDay: "2026-11-01", offset: -18_000)
        let firstKey = AutomaticHourKey(capture: dstFirst)
        let secondKey = AutomaticHourKey(capture: dstSecond)
        try expect(firstKey.rangeLabel == "01:00–01:59" && secondKey.rangeLabel == "01:00–01:59",
                   "Both repeated daylight-saving hours keep their local clock label")
        try expect(firstKey != secondKey,
                   "Receipt offsets keep repeated daylight-saving hours as distinct fixed groups")

        let legacyStamp = "2026-09-23T10:00:00Z"
        let legacyOne = manual(id: 61, stamp: legacyStamp, attachment: true)
        let legacyTwo = manual(id: 62, stamp: legacyStamp, attachment: true)
        let legacyCards = regular(feed([legacyOne, legacyTwo]))
        try expect(legacyCards.count == 1 && legacyCards[0].isImportedBatch
                   && legacyCards[0].captures.count == 2,
                   "Existing same-receipt attachment batching remains intact")

        let source = try String(contentsOfFile: "Sources/DaBin/HourlyCaptureCard.swift", encoding: .utf8)
        try expect(source.contains(".accessibilityLabel(\"Collapse actions\")"),
                   "The minus control has the exact required accessible label")
        try expect(source.contains("Image(systemName: \"minus\")"),
                   "The collapse affordance uses a minus icon rather than deletion imagery")

        print("PASS: \(checks) hourly grouping checks; action identity, fourth-action threshold, filters, fixed local hours, stable IDs and accessible collapse.")
    }
}
