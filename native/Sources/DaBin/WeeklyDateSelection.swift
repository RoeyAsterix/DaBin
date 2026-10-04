import Foundation

/// Calendar-day semantics shared by the week picker, navigation and tests.
/// Explicit selections may be nonconsecutive, but always contain 1–7 dates.
struct WeeklyDateSelection: Equatable {
    static let maximumDays = 7
    let days: [Date]

    init?(days: [Date], calendar: Calendar = .current, now: Date = Date()) {
        guard days.allSatisfy({ $0.timeIntervalSinceReferenceDate.isFinite }) else { return nil }
        let normalized = Array(Set(days.map { calendar.startOfDay(for: $0) })).sorted()
        let today = calendar.startOfDay(for: now)
        guard !normalized.isEmpty, normalized.count <= Self.maximumDays,
              normalized.allSatisfy({ $0 <= today }) else { return nil }
        self.days = normalized
    }

    static func trailingWeek(ending day: Date, calendar: Calendar = .current, now: Date = Date()) -> [Date] {
        let end = calendar.startOfDay(for: min(day, now))
        return (-6...0).compactMap { calendar.date(byAdding: .day, value: $0, to: end) }
    }

    /// Shift the whole selection without filling gaps or collapsing dates at
    /// today's boundary. Calendar arithmetic also preserves local DST dates.
    func shifted(weeks amount: Int, calendar: Calendar = .current, now: Date = Date()) -> WeeklyDateSelection? {
        let delta = amount.multipliedReportingOverflow(by: 7)
        guard !delta.overflow, let last = days.last,
              let proposedEnd = calendar.date(byAdding: .day, value: delta.partialValue, to: last) else { return nil }
        let end = min(proposedEnd, calendar.startOfDay(for: now))
        guard let actualDelta = calendar.dateComponents([.day], from: last, to: end).day else { return nil }
        let shifted = days.compactMap { calendar.date(byAdding: .day, value: actualDelta, to: $0) }
        guard shifted.count == days.count else { return nil }
        return WeeklyDateSelection(days: shifted, calendar: calendar, now: now)
    }
}
