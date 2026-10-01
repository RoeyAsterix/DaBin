import Foundation

/// Countdown intent is resolved once, when Save is pressed. Only the resulting
/// absolute date is persisted and handed to macOS notifications.
enum ReminderScheduleMode: String, CaseIterable, Identifiable {
    case date, countdown
    var id: String { rawValue }
}

enum ReminderSchedule {
    static let maximumCountdownHours = 99

    static func countdownDate(hours: Int, minutes: Int, from now: Date = Date()) throws -> Date {
        guard (0...maximumCountdownHours).contains(hours), (0...59).contains(minutes),
              hours > 0 || minutes > 0, now.timeIntervalSinceReferenceDate.isFinite else {
            throw ReminderScheduleError.invalidCountdown
        }
        return now.addingTimeInterval(TimeInterval(hours * 3_600 + minutes * 60))
    }

    static func resolve(mode: ReminderScheduleMode, date: Date, hours: Int, minutes: Int,
                        now: Date = Date()) throws -> Date {
        let result = mode == .countdown ? try countdownDate(hours: hours, minutes: minutes, from: now) : date
        guard result.timeIntervalSinceReferenceDate.isFinite, result > now else {
            throw CaptureStoreError.reminderNotFuture
        }
        return result
    }
}

enum ReminderScheduleError: LocalizedError {
    case invalidCountdown
    var errorDescription: String? { "Choose a countdown from 00:01 to 99:59." }
}
