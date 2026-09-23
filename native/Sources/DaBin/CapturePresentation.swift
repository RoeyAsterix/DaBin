import Foundation

func kindSymbol(_ kind: CaptureKind) -> String {
    switch kind {
    case .link: return "link"
    case .text: return "text.alignleft"
    case .task: return "checkmark.circle"
    case .image: return "photo"
    case .video: return "video"
    case .pdf: return "doc.richtext"
    case .document: return "doc.text"
    case .ai: return "pencil.and.outline"
    case .file: return "doc"
    }
}

func kindLabel(_ kind: CaptureKind) -> String {
    switch kind {
    case .link: return "LINK"
    case .text: return "NOTE"
    case .task: return "TASK"
    case .image: return "IMAGE"
    case .video: return "VIDEO"
    case .pdf: return "PDF"
    case .document: return "DOC"
    case .ai: return "AI"
    case .file: return "FILE"
    }
}

func captureTypeLabel(_ kind: CaptureKind) -> String {
    switch kind {
    case .pdf: return "PDF"
    case .ai: return "AI"
    case .document: return "Document"
    default: return kindLabel(kind).capitalized
    }
}

func captureLinkHost(_ capture: Capture) -> String? {
    guard capture.kind == .link, let raw = capture.originalURL, let host = URL(string: raw)?.host else { return nil }
    return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
}

func captureClock(_ capture: Capture) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    formatter.timeZone = TimeZone(secondsFromGMT: capture.captureUTCOffsetSeconds)
    return formatter.string(from: capture.capturedAt)
}

func prettyDay(_ day: String, includeWeekday: Bool = true) -> String {
    let parser = DateFormatter()
    parser.locale = Locale(identifier: "en_US_POSIX")
    parser.timeZone = TimeZone(secondsFromGMT: 0)
    parser.dateFormat = "yyyy-MM-dd"
    guard let date = parser.date(from: day) else { return day }
    parser.locale = .current
    parser.dateFormat = includeWeekday ? "EEE, d MMM yyyy" : "d MMM yyyy"
    return parser.string(from: date)
}
