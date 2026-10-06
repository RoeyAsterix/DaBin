import Foundation

/// A session-only project filter. Civil date keys keep the selected day or
/// calendar week stable when a week crosses a month, year or DST boundary.
struct ProjectDateSelection: Equatable {
    enum Mode: String, CaseIterable {
        case day, week

        var title: String { self == .day ? "Day" : "Week" }
    }

    let mode: Mode
    let startDay: String
    let endDay: String

    init(date: Date, mode: Mode, calendar: Calendar = .current) {
        self.mode = mode
        if mode == .week, let interval = calendar.dateInterval(of: .weekOfYear, for: date),
           let lastDay = calendar.date(byAdding: .day, value: -1, to: interval.end) {
            startDay = CaptureCalendar.dayString(interval.start, timeZone: calendar.timeZone)
            endDay = CaptureCalendar.dayString(lastDay, timeZone: calendar.timeZone)
        } else {
            let day = CaptureCalendar.dayString(date, timeZone: calendar.timeZone)
            startDay = day
            endDay = day
        }
    }

    func includes(day: String) -> Bool { day >= startDay && day <= endDay }

    var cacheKey: String { "\(mode.rawValue):\(startDay):\(endDay)" }

    /// Reopen the calendar at the selected civil day rather than a saved epoch.
    func date(calendar: Calendar = .current) -> Date? {
        Self.date(for: startDay, calendar: calendar)
    }

    /// Keys are Gregorian even if the user's presentation calendar is not.
    /// Local noon avoids midnight transitions; round-tripping rejects normalized
    /// invalid dates and any civil day that did not exist in this time zone.
    static func date(for day: String, calendar: Calendar = .current) -> Date? {
        let pieces = day.split(separator: "-", omittingEmptySubsequences: false)
        guard day.utf8.count == 10, pieces.count == 3, pieces[0].utf8.count == 4,
              pieces[1].utf8.count == 2, pieces[2].utf8.count == 2,
              pieces.allSatisfy({ $0.utf8.allSatisfy { (48...57).contains($0) } }),
              let year = Int(pieces[0]), let month = Int(pieces[1]), let number = Int(pieces[2]),
              (1...9999).contains(year), (1...12).contains(month), (1...31).contains(number) else { return nil }
        var civilCalendar = Calendar(identifier: .gregorian)
        civilCalendar.timeZone = calendar.timeZone
        guard let date = civilCalendar.date(from: DateComponents(year: year, month: month, day: number, hour: 12)),
              CaptureCalendar.dayString(date, timeZone: calendar.timeZone) == day else { return nil }
        return date
    }

    var displayTitle: String { displayTitle(calendar: .current) }

    func displayTitle(calendar: Calendar = .current, locale: Locale = .current, now: Date = Date()) -> String {
        guard let start = date(calendar: calendar), let end = Self.date(for: endDay, calendar: calendar) else {
            return startDay == endDay ? startDay : "\(startDay) – \(endDay)"
        }
        var civilCalendar = Calendar(identifier: .gregorian)
        civilCalendar.timeZone = calendar.timeZone
        let currentYear = civilCalendar.component(.year, from: now)
        let showYear = civilCalendar.component(.year, from: start) != currentYear
            || civilCalendar.component(.year, from: end) != currentYear
        let template = showYear ? "yMMMd" : "MMMd"
        if startDay == endDay {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.calendar = civilCalendar
            formatter.timeZone = calendar.timeZone
            formatter.setLocalizedDateFormatFromTemplate(template)
            return formatter.string(from: start)
        }
        let formatter = DateIntervalFormatter()
        formatter.locale = locale
        formatter.calendar = civilCalendar
        formatter.timeZone = calendar.timeZone
        formatter.dateTemplate = template
        return formatter.string(from: start, to: end)
    }

    var accessibilityLabel: String { accessibilityLabel(calendar: .current) }

    func accessibilityLabel(calendar: Calendar = .current, locale: Locale = .current) -> String {
        guard let start = date(calendar: calendar), let end = Self.date(for: endDay, calendar: calendar) else {
            return "\(mode.title): \(startDay) – \(endDay)"
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        var civilCalendar = Calendar(identifier: .gregorian)
        civilCalendar.timeZone = calendar.timeZone
        formatter.calendar = civilCalendar
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        if startDay == endDay { return "Day: \(formatter.string(from: start))" }
        return "Week: \(formatter.string(from: start)) through \(formatter.string(from: end))"
    }
}
