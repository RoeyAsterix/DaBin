import Foundation

private struct TextExportAction {
    let captures: [Capture]
    let tieBreaker: String

    var primary: Capture { captures[0] }
}

/// Shared formatting keeps day and week downloads byte-for-byte consistent at
/// the action level. Date membership is resolved before this formatter runs.
private enum CaptureTextExport {
    static func actions(from captures: [Capture]) -> [TextExportAction] {
        let orderedInput = orderedCaptures(captures)
        let manual = orderedInput.filter { !$0.captureOrigin.isAutomatic }
        var actions = CaptureCardGroup.cards(from: manual, separateTasks: false).map { card in
            let ordered = orderedCaptures(card.captures)
            return TextExportAction(captures: ordered, tieBreaker: ordered[0].id.uuidString)
        }

        var automaticByID: [UUID: [Capture]] = [:]
        for capture in orderedInput where capture.captureOrigin.isAutomatic {
            automaticByID[capture.automaticActionID ?? capture.id, default: []].append(capture)
        }
        actions += automaticByID.map { actionID, members in
            TextExportAction(captures: orderedCaptures(members), tieBreaker: actionID.uuidString)
        }

        return actions.sorted { lhs, rhs in
            if lhs.primary.capturedAt != rhs.primary.capturedAt {
                return lhs.primary.capturedAt < rhs.primary.capturedAt
            }
            return lhs.tieBreaker < rhs.tieBreaker
        }
    }

    static func append(_ actions: [TextExportAction], to lines: inout [String]) {
        for (index, action) in actions.enumerated() {
            lines.append("")
            lines.append("\(index + 1). \(timestamp(action.primary))")
            if action.captures.count == 1 {
                let capture = action.primary
                lines.append("Type: \(typeLabel(capture))")
                if let source = sourceLabel(capture) { lines.append("Source: \(source)") }
                appendCaptureDetails(capture, to: &lines)
            } else {
                lines.append("Type: \(actionTypeLabel(action.captures))")
                let sharedSource = commonSourceLabel(action.captures)
                if let sharedSource { lines.append("Source: \(sharedSource)") }
                lines.append("Items: \(action.captures.count)")
                for (itemIndex, capture) in action.captures.enumerated() {
                    lines.append("")
                    lines.append("  Item \(itemIndex + 1)")
                    lines.append("  Type: \(typeLabel(capture))")
                    if sharedSource == nil, let source = sourceLabel(capture) {
                        lines.append("  Source: \(source)")
                    }
                    appendCaptureDetails(capture, to: &lines, indent: "  ")
                }
            }
        }
    }

    private static func orderedCaptures(_ captures: [Capture]) -> [Capture] {
        captures.sorted { lhs, rhs in
            if lhs.capturedAt != rhs.capturedAt { return lhs.capturedAt < rhs.capturedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func actionTypeLabel(_ captures: [Capture]) -> String {
        let labels = Set(captures.map(typeLabel))
        return labels.count == 1 ? "\(labels.first!) batch" : "Multiple items"
    }

    private static func commonSourceLabel(_ captures: [Capture]) -> String? {
        let sources = captures.map(sourceLabel)
        guard let first = sources.first ?? nil,
              sources.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    private static func appendCaptureDetails(_ capture: Capture, to lines: inout [String],
                                             indent: String = "") {
        append("Title", capture.title, to: &lines, indent: indent)
        if capture.isTask {
            append("Status", capture.isCompleted ? "Completed" : "Task", to: &lines, indent: indent)
        }
        if let filename = capture.originalFilename {
            append("File", filename, to: &lines, indent: indent)
        }
        if let originalText = capture.originalText {
            append("Text", originalText, to: &lines, indent: indent)
        }
        if let originalURL = capture.originalURL {
            append("URL", originalURL, to: &lines, indent: indent)
        }
        if !capture.previewDescription.isEmpty {
            append("Details", capture.previewDescription, to: &lines, indent: indent)
        }
        if !capture.comment.isEmpty {
            append("Comment", capture.comment, to: &lines, indent: indent)
        }
        // Original text is the stored text/OCR channel and Comment is the
        // user's caption. Preview details are commonly dimensions or file
        // metadata, so they do not suppress an honest image placeholder.
        if capture.kind == .image,
           cleaned(capture.originalText ?? "").isEmpty,
           cleaned(capture.comment).isEmpty {
            lines.append(indent + (capture.captureOrigin == .automaticScreenshot
                                   ? "Content: [Screenshot]" : "Content: [Image]"))
        }
    }

    private static func timestamp(_ capture: Capture) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: capture.captureUTCOffsetSeconds)
            ?? TimeZone(secondsFromGMT: 0)!
        formatter.dateFormat = "HH:mm:ss"
        return "\(capture.captureDay) \(formatter.string(from: capture.capturedAt)) \(offsetLabel(capture.captureUTCOffsetSeconds))"
    }

    private static func offsetLabel(_ seconds: Int) -> String {
        let sign = seconds < 0 ? "-" : "+"
        let absolute = abs(seconds)
        return String(format: "%@%02d:%02d", locale: Locale(identifier: "en_US_POSIX"),
                      sign, absolute / 3_600, absolute % 3_600 / 60)
    }

    private static func typeLabel(_ capture: Capture) -> String {
        if capture.captureOrigin == .automaticScreenshot { return "Screenshot" }
        return captureTypeLabel(capture.kind)
    }

    private static func sourceLabel(_ capture: Capture) -> String? {
        let name = cleaned(capture.sourceApplicationName ?? "")
        let bundle = cleaned(capture.sourceApplicationBundleIdentifier ?? "")
        if !name.isEmpty && !bundle.isEmpty { return "\(name) (\(bundle))" }
        if !name.isEmpty { return name }
        return bundle.isEmpty ? nil : bundle
    }

    private static func append(_ label: String, _ value: String, to lines: inout [String],
                               indent: String = "") {
        let value = cleaned(value)
        guard !value.isEmpty else { return }
        let parts = value.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if parts.count == 1 {
            lines.append("\(indent)\(label): \(parts[0])")
        } else {
            lines.append("\(indent)\(label):")
            lines.append(contentsOf: parts.map { "\(indent)  \($0)" })
        }
    }

    private static func cleaned(_ value: String) -> String {
        value.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A deterministic, shareable representation of one recorded calendar day.
/// Callers provide the complete capture archive; this boundary deliberately has
/// no filter input, so a visible board filter cannot change exported history.
struct DayExportDocument: Equatable {
    let day: String
    let actionCount: Int
    let text: String

    var isEmpty: Bool { actionCount == 0 }
    var filename: String { "DaBin-\(day).txt" }
    var utf8Data: Data { Data(text.utf8) }

    static func make(captures: [Capture], selectedDate: Date,
                     now: Date = Date(), calendarTimeZone: TimeZone = .current) -> DayExportDocument {
        let day = CaptureCalendar.dayString(selectedDate, timeZone: calendarTimeZone)
        let today = CaptureCalendar.dayString(now, timeZone: calendarTimeZone)
        let eligible = captures.filter { capture in
            guard capture.captureDay == day else { return false }
            return day != today || capture.capturedAt <= now
        }
        let actions = CaptureTextExport.actions(from: eligible)

        var lines = [
            "DaBin Day Export",
            "Date: \(day)",
            "Actions: \(actions.count)"
        ]
        CaptureTextExport.append(actions, to: &lines)
        return DayExportDocument(day: day, actionCount: actions.count,
                                 text: lines.joined(separator: "\n") + "\n")
    }
}

/// A deterministic export of seven fixed local calendar days ending on the
/// selected date. Only immutable stored receipt dates determine membership;
/// carried tasks and active board filters cannot add or remove actions.
struct WeekExportDocument: Equatable {
    let startDay: String
    let endDay: String
    let actionCount: Int
    let text: String

    var isEmpty: Bool { actionCount == 0 }
    var filename: String { "DaBin-Week-\(startDay)-to-\(endDay).txt" }
    var utf8Data: Data { Data(text.utf8) }

    static func make(captures: [Capture], weekEndingDate: Date,
                     now: Date = Date(), calendarTimeZone: TimeZone = .current) -> WeekExportDocument {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = calendarTimeZone
        let end = calendar.startOfDay(for: weekEndingDate)
        let dates = (-6...0).compactMap { calendar.date(byAdding: .day, value: $0, to: end) }
        let dayKeys = dates.map { CaptureCalendar.dayString($0, timeZone: calendarTimeZone) }
        let startDay = dayKeys.first ?? CaptureCalendar.dayString(end, timeZone: calendarTimeZone)
        let endDay = dayKeys.last ?? startDay
        let allowedDays = Set(dayKeys)
        let today = CaptureCalendar.dayString(now, timeZone: calendarTimeZone)
        let eligible = captures.filter { capture in
            guard allowedDays.contains(capture.captureDay) else { return false }
            if capture.captureDay == today { return capture.capturedAt <= now }
            return capture.captureDay < today
        }
        let actions = CaptureTextExport.actions(from: eligible)

        var lines = [
            "DaBin Week Export",
            "Week: \(startDay) to \(endDay)",
            "Actions: \(actions.count)"
        ]
        CaptureTextExport.append(actions, to: &lines)
        return WeekExportDocument(startDay: startDay, endDay: endDay,
                                  actionCount: actions.count,
                                  text: lines.joined(separator: "\n") + "\n")
    }
}
