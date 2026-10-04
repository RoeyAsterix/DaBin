import Foundation

/// A result keeps its original identity when the window changes column count.
/// Notes use the workspace's project identity; capture receipts retain their UUID.
enum SearchDateItem: Identifiable {
    case capture(SearchEntry)
    case note(WorkspaceScratchpad)

    var id: String {
        switch self {
        case .capture(let entry): return "capture:" + entry.id.uuidString
        case .note(let note): return note.projectName.map { "note:project:" + $0 } ?? "note:inbox:"
        }
    }

    var timestamp: Date {
        switch self {
        case .capture(let entry): return entry.capture.capturedAt
        case .note(let note): return note.updatedAt
        }
    }

    var isMatch: Bool {
        switch self {
        case .capture(let entry): return entry.isMatch
        case .note: return true
        }
    }

    var captureEntry: SearchEntry? {
        if case .capture(let entry) = self { return entry }
        return nil
    }

    var scratchpad: WorkspaceScratchpad? {
        if case .note(let note) = self { return note }
        return nil
    }
}

struct SearchDateGroup: Identifiable {
    let day: String
    let items: [SearchDateItem]
    let matchCount: Int
    var id: String { day }
    var isUndated: Bool { day == SearchDateBoard.undatedDay }
    var captureEntries: [SearchEntry] { items.compactMap(\.captureEntry) }

    init(day: String, items: [SearchDateItem]) {
        self.day = day
        self.items = items
        matchCount = items.reduce(0) { $0 + ($1.isMatch ? 1 : 0) }
    }
}

/// A page contains only the visible date columns, not a second copy of the archive.
/// Indices are zero-based, and endIndex is exclusive, like an Array slice.
struct SearchDatePage {
    let groups: [SearchDateGroup]
    let startIndex: Int
    let totalCount: Int
    let columnCount: Int
    let olderAnchor: String?
    let newerAnchor: String?

    var endIndex: Int { startIndex + groups.count }
    var anchorDay: String? { groups.first?.day }
    var hasOlder: Bool { olderAnchor != nil }
    var hasNewer: Bool { newerAnchor != nil }
    var rangeLabel: String {
        groups.isEmpty ? "No matching dates" : "Dates \(startIndex + 1) to \(endIndex) of \(totalCount)"
    }
}

/// Presentation only: grouping never edits receipts, task schedules or workspace notes.
enum SearchDateBoard {
    static let undatedDay = "Undated"
    static let maximumColumns = 3

    @MainActor
    static func groups(captureGroups: [SearchGroup], notes: [WorkspaceScratchpad],
                       includeContext: Bool = false, timeZone: TimeZone = .current) -> [SearchDateGroup] {
        // Upstream groups normally contain one receipt each. De-duplicate
        // defensively so overlapping context can never inflate match counts.
        var entries: [UUID: SearchEntry] = [:]
        for group in captureGroups {
            for entry in group.entries where entry.capture.deletedAt == nil {
                if let previous = entries[entry.id] {
                    if (!previous.isMatch && entry.isMatch)
                        || (previous.isMatch == entry.isMatch && previous.indexedTextMatch == nil
                            && entry.indexedTextMatch != nil) {
                        entries[entry.id] = entry
                    }
                } else {
                    entries[entry.id] = entry
                }
            }
        }

        var days: [String: [SearchDateItem]] = [:]
        for entry in entries.values where includeContext || entry.isMatch {
            // The container label, last edit, deadline and current time zone
            // cannot move a capture away from its immutable saved calendar day.
            let day = validDay(entry.capture.captureDay) ?? undatedDay
            days[day, default: []].append(.capture(entry))
        }

        var projectNotes: [String: WorkspaceScratchpad] = [:]
        for note in notes where !note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let id = SearchDateItem.note(note).id
            if let previous = projectNotes[id], sortDate(previous.updatedAt) >= sortDate(note.updatedAt) { continue }
            projectNotes[id] = note
        }
        for note in projectNotes.values {
            let day = note.updatedAt.timeIntervalSinceReferenceDate.isFinite
                ? validDay(CaptureCalendar.dayString(note.updatedAt, timeZone: timeZone)) ?? undatedDay
                : undatedDay
            days[day, default: []].append(.note(note))
        }

        return days.compactMap { day, items in
            let sorted = items.sorted {
                let left = sortDate($0.timestamp), right = sortDate($1.timestamp)
                return left == right ? $0.id < $1.id : left > right
            }
            let group = SearchDateGroup(day: day, items: sorted)
            // Context can enrich a matching day, but does not create a date
            // column with no matches of its own.
            return group.matchCount > 0 ? group : nil
        }.sorted {
            if $0.isUndated != $1.isUndated { return !$0.isUndated }
            return $0.day > $1.day
        }
    }

    static func columnCount(width: CGFloat) -> Int {
        guard width.isFinite, width >= 0 else { return 1 }
        // The native frame and board padding are already excluded from width.
        // Leave at least 320 points per date rather than using window breakpoints.
        if width >= 960 { return 3 }
        if width >= 640 { return 2 }
        return 1
    }

    static func page(groups: [SearchDateGroup], anchorDay: String?, width: CGFloat) -> SearchDatePage {
        page(groups: groups, anchorDay: anchorDay, columns: columnCount(width: width))
    }

    static func page(groups: [SearchDateGroup], anchorDay: String?, columns: Int) -> SearchDatePage {
        page(groups: groups, startIndex: anchorIndex(for: anchorDay, in: groups), columns: columns)
    }

    static func page(groups: [SearchDateGroup], startIndex: Int, columns: Int) -> SearchDatePage {
        let count = min(maximumColumns, max(1, columns))
        guard !groups.isEmpty else {
            return SearchDatePage(groups: [], startIndex: 0, totalCount: 0, columnCount: count,
                                  olderAnchor: nil, newerAnchor: nil)
        }
        let start = min(max(0, startIndex), groups.count - 1)
        let end = start + min(count, groups.count - start)
        return SearchDatePage(groups: Array(groups[start..<end]), startIndex: start,
                              totalCount: groups.count, columnCount: count,
                              olderAnchor: end < groups.count ? groups[end].day : nil,
                              newerAnchor: start > 0 ? groups[max(0, start - count)].day : nil)
    }

    /// Keep the exact first visible date across resizing. If a live deletion
    /// removes that date, continue at the closest older date instead of jumping
    /// to the newest result or rounding to a whole-page boundary.
    static func anchorIndex(for anchorDay: String?, in groups: [SearchDateGroup]) -> Int {
        guard !groups.isEmpty, let anchorDay else { return 0 }
        if let index = groups.firstIndex(where: { $0.day == anchorDay }) { return index }
        if anchorDay == undatedDay { return groups.count - 1 }
        guard validDay(anchorDay) != nil else { return 0 }
        return groups.firstIndex(where: { $0.isUndated || $0.day < anchorDay }) ?? groups.count - 1
    }

    private static func sortDate(_ date: Date) -> Date {
        date.timeIntervalSinceReferenceDate.isFinite ? date : .distantPast
    }

    private static func validDay(_ day: String) -> String? {
        let pieces = day.split(separator: "-", omittingEmptySubsequences: false)
        guard day.utf8.count == 10, pieces.count == 3,
              pieces[0].utf8.count == 4, pieces[1].utf8.count == 2, pieces[2].utf8.count == 2,
              pieces.allSatisfy({ $0.utf8.allSatisfy { (48...57).contains($0) } }),
              let year = Int(pieces[0]), let month = Int(pieces[1]), let number = Int(pieces[2]),
              (1...9_999).contains(year), (1...12).contains(month), (1...31).contains(number) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: number)),
              calendar.component(.year, from: date) == year,
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == number else { return nil }
        return day
    }
}
