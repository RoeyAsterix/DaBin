import Foundation

/// A fixed civil-clock hour reconstructed from the immutable capture receipt.
/// The UTC offset distinguishes the two repeated hours during a daylight-saving
/// fallback while keeping the user-facing label in the local time they saw.
struct AutomaticHourKey: Hashable, Comparable {
    let captureDay: String
    let hour: Int
    let utcOffsetSeconds: Int

    init(capture: Capture) {
        captureDay = capture.captureDay
        utcOffsetSeconds = capture.captureUTCOffsetSeconds
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: capture.captureUTCOffsetSeconds)
            ?? TimeZone(secondsFromGMT: 0)!
        hour = calendar.component(.hour, from: capture.capturedAt)
    }

    static func < (lhs: AutomaticHourKey, rhs: AutomaticHourKey) -> Bool {
        if lhs.captureDay != rhs.captureDay { return lhs.captureDay < rhs.captureDay }
        if lhs.hour != rhs.hour { return lhs.hour < rhs.hour }
        return lhs.utcOffsetSeconds < rhs.utcOffsetSeconds
    }

    var rangeLabel: String {
        String(format: "%02d:00–%02d:59", locale: Locale(identifier: "en_US_POSIX"), hour, hour)
    }
}

/// One successfully saved automatic user action. An action can contain several
/// capture records, while its stable ID contributes exactly one to the hour.
struct AutomaticCaptureAction: Identifiable {
    let id: UUID
    let cards: [CaptureCardGroup]

    var captures: [Capture] { cards.flatMap(\.captures) }
    var primary: Capture { cards[0].primary }
}

/// The visible portion of a qualifying hour. `totalActionCount` is calculated
/// before filtering, so changing a filter never turns a four-action hour back
/// into unrelated individual cards.
struct AutomaticHourGroup: Identifiable {
    let id: AutomaticHourKey
    let actions: [AutomaticCaptureAction]
    let totalActionCount: Int
    let displaysDate: Bool

    var visibleActionCount: Int { actions.count }
    var captures: [Capture] { actions.flatMap(\.captures) }

    var summaryTitle: String {
        let count: String
        if visibleActionCount == totalActionCount {
            count = "\(totalActionCount) actions"
        } else {
            count = "\(visibleActionCount) of \(totalActionCount) actions"
        }
        let hourAndCount = "\(id.rangeLabel) · \(count)"
        return displaysDate
            ? "\(prettyDay(id.captureDay, includeWeekday: false)) · \(hourAndCount)"
            : hourAndCount
    }
}

enum CaptureFeedCardID: Hashable {
    case capture(CaptureCardGroup.ID)
    case automaticHour(AutomaticHourKey)
}

/// A stable outer feed boundary. The automatic-hour identity is the same while
/// collapsed and expanded, allowing SwiftUI to retain its scroll anchor.
enum CaptureFeedCard: Identifiable {
    case capture(CaptureCardGroup)
    case automaticHour(AutomaticHourGroup)

    var id: CaptureFeedCardID {
        switch self {
        case .capture(let card): return .capture(card.id)
        case .automaticHour(let group): return .automaticHour(group.id)
        }
    }

    var captures: [Capture] {
        switch self {
        case .capture(let card): return card.captures
        case .automaticHour(let group): return group.captures
        }
    }
}

enum HourlyCaptureFeed {
    static let summaryThreshold = 4

    /// Builds feed cards from an unfiltered day's captures. Callers must supply
    /// the complete day membership and pass the active filter separately; this
    /// preserves the fourth-action threshold under Links, Files and Media.
    static func cards(from captures: [Capture], filter: CaptureFilter,
                      today: Date = Date(), calendarTimeZone: TimeZone = .current) -> [CaptureFeedCard] {
        let indexed = captures.enumerated().map { IndexedCapture(position: $0.offset, capture: $0.element) }
        let positionByID = Dictionary(uniqueKeysWithValues: indexed.map { ($0.capture.id, $0.position) })

        // Tasks need an individual status control and carryover position even
        // when their original receipt belonged to an automatic hour.
        let individualCaptures = indexed.filter { !$0.capture.captureOrigin.isAutomatic || $0.capture.isTask }.map(\.capture)
        var seeds = CaptureCardGroup.cards(from: individualCaptures).map { card -> FeedSeed in
            let position = card.captures.compactMap { positionByID[$0.id] }.min() ?? Int.max
            return .manual(card: card, position: position)
        }

        var automaticByID: [UUID: [IndexedCapture]] = [:]
        for item in indexed where item.capture.captureOrigin.isAutomatic {
            let actionID = item.capture.automaticActionID ?? item.capture.id
            automaticByID[actionID, default: []].append(item)
        }
        let automaticActions = automaticByID.map { actionID, members -> RawAutomaticAction in
            let ordered = members.sorted { lhs, rhs in
                if lhs.position != rhs.position { return lhs.position < rhs.position }
                return lhs.capture.id.uuidString < rhs.capture.id.uuidString
            }
            return RawAutomaticAction(id: actionID, captures: ordered.map(\.capture),
                                      position: ordered.first(where: { !$0.capture.isTask })?.position ?? ordered[0].position,
                                      hour: AutomaticHourKey(capture: ordered[0].capture))
        }
        // Retain every receipt in hour counts, but anchor the summary only to
        // remaining non-task content so it cannot overtake a promoted task.
        seeds += automaticActions.filter { $0.captures.contains(where: { !$0.isTask }) }
            .map { .automatic(action: $0) }
        seeds.sort {
            if $0.position != $1.position { return $0.position < $1.position }
            return $0.tieBreaker < $1.tieBreaker
        }

        let actionsByHour = Dictionary(grouping: automaticActions, by: \.hour)
            .mapValues { actions in
                actions.sorted {
                    if $0.position != $1.position { return $0.position < $1.position }
                    return $0.id.uuidString < $1.id.uuidString
                }
            }
        let qualifyingHours = Set(actionsByHour.compactMap { key, actions in
            actions.count >= summaryThreshold ? key : nil
        })
        let todayKey = CaptureCalendar.dayString(today, timeZone: calendarTimeZone)
        var emittedHours = Set<AutomaticHourKey>()
        var result: [CaptureFeedCard] = []

        for seed in seeds {
            switch seed {
            case .manual(let card, _):
                result += visibleCards(in: card.captures, filter: filter).map(CaptureFeedCard.capture)
            case .automatic(let action):
                guard qualifyingHours.contains(action.hour) else {
                    result += visibleCards(in: action.captures.filter { !$0.isTask }, filter: filter).map(CaptureFeedCard.capture)
                    continue
                }
                guard emittedHours.insert(action.hour).inserted,
                      let allActions = actionsByHour[action.hour] else { continue }
                let visibleActions = allActions.compactMap { item -> AutomaticCaptureAction? in
                    let cards = visibleCards(in: item.captures.filter { !$0.isTask }, filter: filter)
                    return cards.isEmpty ? nil : AutomaticCaptureAction(id: item.id, cards: cards)
                }
                guard !visibleActions.isEmpty else { continue }
                result.append(.automaticHour(AutomaticHourGroup(
                    id: action.hour,
                    actions: visibleActions,
                    totalActionCount: allActions.count,
                    displaysDate: action.hour.captureDay != todayKey
                )))
            }
        }
        return result
    }

    private static func visibleCards(in captures: [Capture], filter: CaptureFilter) -> [CaptureCardGroup] {
        CaptureCardGroup.cards(from: captures.filter { filter.includes($0) })
    }
}

private struct IndexedCapture {
    let position: Int
    let capture: Capture
}

private struct RawAutomaticAction {
    let id: UUID
    let captures: [Capture]
    let position: Int
    let hour: AutomaticHourKey
}

private enum FeedSeed {
    case manual(card: CaptureCardGroup, position: Int)
    case automatic(action: RawAutomaticAction)

    var position: Int {
        switch self {
        case .manual(_, let position): return position
        case .automatic(let action): return action.position
        }
    }

    var tieBreaker: String {
        switch self {
        case .manual(let card, _): return "manual-\(card.primary.id.uuidString)"
        case .automatic(let action): return "automatic-\(action.id.uuidString)"
        }
    }
}
