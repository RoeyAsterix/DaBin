import Foundation

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

    private struct ExportAction {
        let captures: [Capture]
        let tieBreaker: String

        var primary: Capture { captures[0] }
    }

    static func make(captures: [Capture], selectedDate: Date,
                     now: Date = Date(), calendarTimeZone: TimeZone = .current) -> DayExportDocument {
        let day = CaptureCalendar.dayString(selectedDate, timeZone: calendarTimeZone)
        let today = CaptureCalendar.dayString(now, timeZone: calendarTimeZone)
        let eligible = captures.filter { capture in
            guard capture.captureDay == day else { return false }
            return day != today || capture.capturedAt <= now
        }.sorted { lhs, rhs in
            if lhs.capturedAt != rhs.capturedAt { return lhs.capturedAt < rhs.capturedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        let actions = groupedActions(from: eligible)

        var lines = [
            "DaBin Day Export",
            "Date: \(day)",
            "Actions: \(actions.count)"
        ]
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
        return DayExportDocument(day: day, actionCount: actions.count,
                                 text: lines.joined(separator: "\n") + "\n")
    }

    /// Mirrors the board's action boundaries: one manual multi-file receipt is
    /// one action, and every record carrying the same automatic action ID is
    /// one action. All item content remains present in the exported text.
    private static func groupedActions(from captures: [Capture]) -> [ExportAction] {
        let manual = captures.filter { !$0.captureOrigin.isAutomatic }
        var actions = CaptureCardGroup.cards(from: manual).map { card in
            let ordered = orderedCaptures(card.captures)
            return ExportAction(captures: ordered, tieBreaker: ordered[0].id.uuidString)
        }

        var automaticByID: [UUID: [Capture]] = [:]
        for capture in captures where capture.captureOrigin.isAutomatic {
            automaticByID[capture.automaticActionID ?? capture.id, default: []].append(capture)
        }
        actions += automaticByID.map { actionID, members in
            ExportAction(captures: orderedCaptures(members), tieBreaker: actionID.uuidString)
        }

        return actions.sorted { lhs, rhs in
            if lhs.primary.capturedAt != rhs.primary.capturedAt {
                return lhs.primary.capturedAt < rhs.primary.capturedAt
            }
            return lhs.tieBreaker < rhs.tieBreaker
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
