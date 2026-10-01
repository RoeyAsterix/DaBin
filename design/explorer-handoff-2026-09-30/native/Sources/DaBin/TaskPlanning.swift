import Foundation

enum TaskPriority: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, low, medium, high
    var id: String { rawValue }
    var title: String { self == .none ? "No priority" : rawValue.capitalized }
    var symbol: String {
        switch self {
        case .none: return "minus.circle"
        case .low: return "arrow.down.circle"
        case .medium: return "equal.circle"
        case .high: return "exclamationmark.circle"
        }
    }
    var rank: Int {
        switch self { case .none: return 0; case .low: return 1; case .medium: return 2; case .high: return 3 }
    }
}

enum TaskRecurrence: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, daily, weekdays, weekly, monthly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "Does not repeat"
        case .daily: return "Every day"
        case .weekdays: return "Every weekday"
        case .weekly: return "Every week"
        case .monthly: return "Every month"
        }
    }

    /// One future occurrence after completion. Missed periods never produce a backlog.
    /// Calendar arithmetic preserves local clock time across daylight-saving changes.
    func nextDate(after anchor: Date, notBefore now: Date, calendar: Calendar = .current) -> Date? {
        guard self != .none else { return nil }
        let component: Calendar.Component = self == .weekly ? .weekOfYear : self == .monthly ? .month : .day
        let elapsed = max(0, calendar.dateComponents([component], from: anchor, to: now).value(for: component) ?? 0)
        // Start near now even for a years-old imported task. Eight candidates
        // cover calendar rounding and weekends without unbounded background work.
        let first = max(1, elapsed)
        for increment in first...(first + 8) {
            guard let candidate = calendar.date(byAdding: component, value: increment, to: anchor) else { return nil }
            if self == .weekdays && calendar.isDateInWeekend(candidate) { continue }
            if candidate > now { return candidate }
        }
        return nil
    }
}

struct TaskChecklistItem: Codable, Equatable, Identifiable, Sendable {
    var id: UUID = UUID()
    var text: String
    var isCompleted = false
}

struct TaskPlanning: Codable, Equatable, Sendable {
    var plannedDay: String?
    var deadline: Date?
    var priority: TaskPriority = .none
    var effortMinutes: Int?
    var order: Int?
    var recurrence: TaskRecurrence = .none
    var checklist: [TaskChecklistItem] = []
    var completedAt: Date?
    var previousOccurrenceID: UUID?
    var nextOccurrenceID: UUID?
    /// Retains the original cadence, so a January 31 routine returns to March 31 after February.
    var recurrenceAnchor: Date?

    var isValid: Bool {
        (plannedDay.map { TaskPlanningPolicy.date(for: $0) != nil } ?? true)
        && (deadline.map { $0.timeIntervalSinceReferenceDate.isFinite } ?? true)
        && (effortMinutes.map { (1...10_080).contains($0) } ?? true)
        && (order.map { (0...1_000_000).contains($0) } ?? true)
        && checklist.count <= 100
        && Set(checklist.map(\.id)).count == checklist.count
        && checklist.allSatisfy { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.text.count <= 500 }
        && (completedAt.map { $0.timeIntervalSinceReferenceDate.isFinite } ?? true)
        && (recurrenceAnchor.map { $0.timeIntervalSinceReferenceDate.isFinite } ?? true)
    }
}

enum TaskPlanningPolicy {
    /// Strict parsing avoids accepting normalized invalid dates such as February 31.
    static func date(for day: String, calendar: Calendar = .current) -> Date? {
        let pieces = day.split(separator: "-", omittingEmptySubsequences: false)
        guard day.count == 10, pieces.count == 3, pieces[0].count == 4,
              pieces[1].count == 2, pieces[2].count == 2,
              let year = Int(pieces[0]), let month = Int(pieces[1]), let dayNumber = Int(pieces[2]),
              (1...9999).contains(year), (1...12).contains(month), (1...31).contains(dayNumber) else { return nil }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        guard let date = gregorian.date(from: DateComponents(year: year, month: month, day: dayNumber, hour: 12)),
              CaptureCalendar.dayString(date, timeZone: calendar.timeZone) == day else { return nil }
        return date
    }

    static func isPlanned(_ capture: Capture, for day: String) -> Bool {
        capture.isTask && !capture.isCompleted && capture.deletedAt == nil
        && capture.parentTaskID == nil && capture.taskPlanning?.plannedDay == day
    }

    static func isOverdue(_ capture: Capture, at now: Date = Date()) -> Bool {
        capture.isTask && !capture.isCompleted && capture.deletedAt == nil
        && (capture.taskPlanning?.deadline.map { $0 < now } ?? false)
    }

    static func today(_ captures: [Capture], at now: Date = Date(), calendar: Calendar = .current) -> [Capture] {
        let day = CaptureCalendar.dayString(now, timeZone: calendar.timeZone)
        return sorted(captures.filter { isPlanned($0, for: day) })
    }

    static func inbox(_ captures: [Capture]) -> [Capture] {
        sorted(captures.filter { $0.isTask && !$0.isCompleted && $0.deletedAt == nil
            && $0.parentTaskID == nil && $0.taskPlanning?.plannedDay == nil })
    }

    static func sorted(_ captures: [Capture]) -> [Capture] {
        captures.sorted {
            let first = $0.taskPlanning ?? TaskPlanning()
            let second = $1.taskPlanning ?? TaskPlanning()
            if first.order != second.order { return (first.order ?? Int.max) < (second.order ?? Int.max) }
            if first.priority != second.priority { return first.priority.rank > second.priority.rank }
            if first.deadline != second.deadline { return (first.deadline ?? .distantFuture) < (second.deadline ?? .distantFuture) }
            if $0.capturedAt != $1.capturedAt { return $0.capturedAt > $1.capturedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
