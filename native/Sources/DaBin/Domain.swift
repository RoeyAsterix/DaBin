import Foundation
import Combine
import UniformTypeIdentifiers

enum CaptureKind: String, Codable, CaseIterable {
    case link, text, image, video, pdf, document, ai, file, task
}

/// How an immutable capture receipt entered DaBin. Manual is the safe legacy
/// default; automatic origins are only assigned by the opt-in monitor.
enum CaptureOrigin: String, Codable, CaseIterable, Sendable {
    case manual
    case automaticClipboard
    case automaticScreenshot

    var isAutomatic: Bool { self != .manual }

    var displayName: String {
        switch self {
        case .manual: return "Manual capture"
        case .automaticClipboard: return "Copied content"
        case .automaticScreenshot: return "Screenshot"
        }
    }
}

/// Metadata shared by every saved item produced by one user action. Keeping the
/// action ID separate from Capture.id lets an automatic multi-item copy count as
/// one action in the hourly feed.
struct CaptureReceiptContext: Sendable {
    let origin: CaptureOrigin
    let automaticActionID: UUID?
    let sourceApplicationName: String?
    let sourceApplicationBundleIdentifier: String?

    static let manual = CaptureReceiptContext(origin: .manual, automaticActionID: nil,
                                               sourceApplicationName: nil,
                                               sourceApplicationBundleIdentifier: nil)

    static func automatic(_ origin: CaptureOrigin, actionID: UUID = UUID(),
                          sourceApplicationName: String? = nil,
                          sourceApplicationBundleIdentifier: String? = nil) -> CaptureReceiptContext {
        precondition(origin.isAutomatic)
        return CaptureReceiptContext(origin: origin, automaticActionID: actionID,
                                     sourceApplicationName: sourceApplicationName,
                                     sourceApplicationBundleIdentifier: sourceApplicationBundleIdentifier)
    }
}

/// Provenance explicitly supplied by a transfer, never inferred from surrounding apps.
struct CaptureSource: Sendable {
    let filePath: String?
    let url: String?
    static let unknown = CaptureSource()

    init(filePath: String? = nil, url: String? = nil) {
        self.filePath = filePath
        self.url = url
    }
}

enum CaptureFilter: String, CaseIterable, Identifiable {
    case all, text, links, files, media, tasks
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    func includes(_ kind: CaptureKind) -> Bool {
        switch self {
        case .all: return true
        case .text: return kind == .text
        case .links: return kind == .link
        case .media: return kind == .image || kind == .video
        case .files: return [.pdf, .document, .ai, .file].contains(kind)
        case .tasks: return kind == .task
        }
    }
}

final class Capture: ObservableObject, Identifiable {
    private(set) var id: UUID
    private(set) var capturedAt: Date
    private(set) var captureDay: String
    private(set) var captureTimeZoneID: String
    private(set) var captureUTCOffsetSeconds: Int
    private(set) var kindRaw: String
    private(set) var originalURL: String?
    private(set) var originalText: String?
    private(set) var sourceFilePath: String?
    private(set) var sourceURL: String?
    private(set) var attachmentRelativePath: String?
    private(set) var originalFilename: String?
    private(set) var contentType: String?
    private(set) var byteCount: Int64?
    private(set) var captureOriginRaw: String
    private(set) var automaticActionID: UUID?
    private(set) var sourceApplicationName: String?
    private(set) var sourceApplicationBundleIdentifier: String?
    @Published var title: String
    @Published var previewDescription: String
    @Published var thumbnailRelativePath: String?
    @Published var previewState: String
    @Published var previewError: String?
    @Published var comment: String
    @Published var isCompleted: Bool
    @Published var isMinimized: Bool
    @Published var reminderAt: Date?
    @Published var reminderTimeZoneID: String?
    @Published var reminderRevision: Int
    @Published var notificationState: String
    private(set) var createdAt: Date
    @Published var updatedAt: Date
    var kind: CaptureKind { CaptureKind(rawValue: kindRaw) ?? .file }
    var isTask: Bool { kind == .task }
    var captureOrigin: CaptureOrigin { CaptureOrigin(rawValue: captureOriginRaw) ?? .manual }

    init(id: UUID = UUID(), capturedAt: Date = Date(), timeZone: TimeZone = .current,
         kind: CaptureKind, originalURL: String? = nil, originalText: String? = nil,
         attachmentRelativePath: String? = nil, originalFilename: String? = nil,
         contentType: String? = nil, byteCount: Int64? = nil, title: String,
         captureDay: String? = nil, captureTimeZoneID: String? = nil,
         captureUTCOffsetSeconds: Int? = nil, sourceFilePath: String? = nil, sourceURL: String? = nil,
         receipt: CaptureReceiptContext = .manual) {
        self.id = id
        self.capturedAt = capturedAt
        self.captureDay = captureDay ?? CaptureCalendar.dayString(capturedAt, timeZone: timeZone)
        self.captureTimeZoneID = captureTimeZoneID ?? timeZone.identifier
        self.captureUTCOffsetSeconds = captureUTCOffsetSeconds ?? timeZone.secondsFromGMT(for: capturedAt)
        self.kindRaw = kind.rawValue
        self.originalURL = originalURL
        self.originalText = originalText
        self.sourceFilePath = sourceFilePath
        self.sourceURL = sourceURL ?? (kind == .link ? originalURL : nil)
        self.attachmentRelativePath = attachmentRelativePath
        self.originalFilename = originalFilename
        self.contentType = contentType
        self.byteCount = byteCount
        self.captureOriginRaw = receipt.origin.rawValue
        self.automaticActionID = receipt.origin.isAutomatic ? receipt.automaticActionID : nil
        self.sourceApplicationName = receipt.sourceApplicationName
        self.sourceApplicationBundleIdentifier = receipt.sourceApplicationBundleIdentifier
        self.title = title
        self.previewDescription = ""
        self.previewState = "idle"
        self.comment = ""
        self.isCompleted = false
        self.isMinimized = false
        self.reminderRevision = 0
        self.notificationState = "none"
        self.createdAt = Date()
        self.updatedAt = self.createdAt
    }

    // Repository-coordinated relocation changes only managed storage, never provenance.
    func relocateManagedAttachment(to relativePath: String) { attachmentRelativePath = relativePath }

    convenience init(snapshot: CaptureSnapshot) {
        self.init(id: snapshot.id, capturedAt: snapshot.capturedAt,
                  timeZone: TimeZone(identifier: snapshot.captureTimeZoneID) ?? TimeZone(secondsFromGMT: snapshot.captureUTCOffsetSeconds) ?? TimeZone(secondsFromGMT: 0)!,
                  kind: CaptureKind(rawValue: snapshot.kindRaw) ?? .file, originalURL: snapshot.originalURL,
                  originalText: snapshot.originalText, attachmentRelativePath: snapshot.attachmentRelativePath,
                  originalFilename: snapshot.originalFilename, contentType: snapshot.contentType,
                  byteCount: snapshot.byteCount, title: snapshot.title, captureDay: snapshot.captureDay,
                  captureTimeZoneID: snapshot.captureTimeZoneID, captureUTCOffsetSeconds: snapshot.captureUTCOffsetSeconds,
                  sourceFilePath: snapshot.sourceFilePath, sourceURL: snapshot.sourceURL,
                  receipt: CaptureReceiptContext(
                    origin: CaptureOrigin(rawValue: snapshot.captureOriginRaw ?? "") ?? .manual,
                    automaticActionID: snapshot.automaticActionID,
                    sourceApplicationName: snapshot.sourceApplicationName,
                    sourceApplicationBundleIdentifier: snapshot.sourceApplicationBundleIdentifier))
        self.previewDescription = snapshot.previewDescription
        self.thumbnailRelativePath = snapshot.thumbnailRelativePath
        self.previewState = snapshot.previewState
        self.previewError = snapshot.previewError
        self.comment = snapshot.comment
        self.isCompleted = self.isTask && (snapshot.isCompleted ?? false)
        self.isMinimized = snapshot.isMinimized ?? false
        self.reminderAt = snapshot.reminderAt
        self.reminderTimeZoneID = snapshot.reminderTimeZoneID
        self.reminderRevision = snapshot.reminderRevision
        self.notificationState = snapshot.notificationState
        self.createdAt = snapshot.createdAt
        self.updatedAt = snapshot.updatedAt
    }
}

// Versioned payload in the local Core Data record. Receipt fields have no public setters.
struct CaptureSnapshot: Codable {
    let schemaVersion: Int
    let id: UUID
    let capturedAt: Date
    let captureDay: String
    let captureTimeZoneID: String
    let captureUTCOffsetSeconds: Int
    let kindRaw: String
    let originalURL: String?
    let originalText: String?
    // Optional fields decode as nil in v1 records, preserving existing databases.
    let sourceFilePath: String?
    let sourceURL: String?
    let attachmentRelativePath: String?
    let originalFilename: String?
    let contentType: String?
    let byteCount: Int64?
    // Optional in versions 1–3. Older records remain manual captures.
    let captureOriginRaw: String?
    let automaticActionID: UUID?
    let sourceApplicationName: String?
    let sourceApplicationBundleIdentifier: String?
    let title: String
    let previewDescription: String
    let thumbnailRelativePath: String?
    let previewState: String
    let previewError: String?
    let comment: String
    // Older payloads omit task state; ordinary captures remain ordinary captures.
    let isCompleted: Bool?
    // Optional for existing version 3 records; the capture stays searchable.
    let isMinimized: Bool?
    let reminderAt: Date?
    let reminderTimeZoneID: String?
    let reminderRevision: Int
    let notificationState: String
    let createdAt: Date
    let updatedAt: Date

    init(_ capture: Capture) {
        schemaVersion = 4
        id = capture.id
        capturedAt = capture.capturedAt
        captureDay = capture.captureDay
        captureTimeZoneID = capture.captureTimeZoneID
        captureUTCOffsetSeconds = capture.captureUTCOffsetSeconds
        kindRaw = capture.kindRaw
        originalURL = capture.originalURL
        originalText = capture.originalText
        sourceFilePath = capture.sourceFilePath
        sourceURL = capture.sourceURL
        attachmentRelativePath = capture.attachmentRelativePath
        originalFilename = capture.originalFilename
        contentType = capture.contentType
        byteCount = capture.byteCount
        captureOriginRaw = capture.captureOriginRaw
        automaticActionID = capture.automaticActionID
        sourceApplicationName = capture.sourceApplicationName
        sourceApplicationBundleIdentifier = capture.sourceApplicationBundleIdentifier
        title = capture.title
        previewDescription = capture.previewDescription
        thumbnailRelativePath = capture.thumbnailRelativePath
        previewState = capture.previewState
        previewError = capture.previewError
        comment = capture.comment
        isCompleted = capture.isCompleted
        isMinimized = capture.isMinimized
        reminderAt = capture.reminderAt
        reminderTimeZoneID = capture.reminderTimeZoneID
        reminderRevision = capture.reminderRevision
        notificationState = capture.notificationState
        createdAt = capture.createdAt
        updatedAt = capture.updatedAt
    }
}

enum CaptureCalendar {
    static func dayString(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", locale: Locale(identifier: "en_US_POSIX"),
                      parts.year!, parts.month!, parts.day!)
    }
}

enum CaptureClassifier {
    static func textKind(_ text: String) -> CaptureKind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: { $0.isWhitespace }),
              let parts = URLComponents(string: trimmed),
              let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = parts.host, !host.isEmpty,
              let url = parts.url, url.scheme != nil else { return .text }
        return .link
    }

    static func fileKind(filename: String, contentType: UTType? = nil) -> CaptureKind {
        let ext = (filename as NSString).pathExtension.lowercased()
        // Specialist formats precede broad conformance (Illustrator may conform to PDF).
        if ext == "ai" { return .ai }
        if ext == "pdf" || contentType?.conforms(to: .pdf) == true { return .pdf }
        if contentType?.conforms(to: .image) == true ||
            ["png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "avif", "tiff", "tif", "bmp"].contains(ext) { return .image }
        if contentType?.conforms(to: .movie) == true ||
            ["mov", "mp4", "webm", "m4v", "avi", "mkv"].contains(ext) { return .video }
        if ["doc", "docx", "ppt", "pptx", "xls", "xlsx", "txt", "md", "rtf", "csv", "pages", "numbers", "key"].contains(ext) { return .document }
        return .file
    }

    static func storageFilename(_ original: String) -> String {
        // Metadata retains the verbatim name. The on-disk leaf has no path semantics.
        let forbidden = CharacterSet(charactersIn: "/\\:\0").union(.controlCharacters)
        var name = original.unicodeScalars.map { forbidden.contains($0) ? "_" : String($0) }.joined()
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") { name.removeFirst() }
        if name.isEmpty { return "Untitled" }
        // A conservative UTF-8 budget also leaves room for a filesystem suffix.
        while name.utf8.count > 200 { name.removeLast() }
        return name
    }
}

struct SearchGroup: Identifiable {
    let day: String
    let entries: [SearchEntry]
    var id: String { day }
}

struct SearchEntry: Identifiable {
    let capture: Capture
    let isMatch: Bool
    var id: UUID { capture.id }
}

/// Limits a search to immutable receipt dates. A week is represented by its
/// exact local calendar-day keys so month, year and daylight-saving boundaries
/// cannot turn it into a rolling duration.
enum CaptureSearchScope: Hashable {
    case all
    case day(String)
    case week(Set<String>)

    func includes(captureDay: String) -> Bool {
        switch self {
        case .all:
            return true
        case .day(let day):
            return captureDay == day
        case .week(let days):
            return days.contains(captureDay)
        }
    }
}

enum CaptureSearch {
    static func ordered(_ captures: [Capture]) -> [Capture] {
        captures.sorted {
            $0.capturedAt == $1.capturedAt ? $0.id.uuidString < $1.id.uuidString : $0.capturedAt < $1.capturedAt
        }
    }

    static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    static func groups(captures: [Capture], query: String, filter: CaptureFilter,
                       scope: CaptureSearchScope = .all) -> [SearchGroup] {
        let words = normalized(query).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return [] }
        let days = Dictionary(grouping: captures.filter { scope.includes(captureDay: $0.captureDay) },
                              by: \.captureDay)
        return days.keys.sorted(by: >).compactMap { day in
            let items = ordered(days[day]!)
            let hits = Set(items.indices.filter { index in
                let item = items[index]
                guard filter.includes(item.kind) else { return false }
                let haystack = normalized([item.title, item.previewDescription, item.originalURL ?? "",
                                           item.originalText ?? "", item.originalFilename ?? "", item.comment,
                                           item.kind.rawValue, item.captureDay,
                                           item.sourceApplicationName ?? "",
                                           item.sourceApplicationBundleIdentifier ?? "",
                                           item.captureOrigin.displayName,
                                           item.captureOrigin == .automaticClipboard ? "copied clipboard" : "",
                                           item.captureOrigin == .automaticScreenshot ? "screenshot screen capture" : ""].joined(separator: " "))
                return words.allSatisfy(haystack.contains)
            })
            guard !hits.isEmpty else { return nil }
            var included = hits
            for index in hits {
                if index > 0 { included.insert(index - 1) }
                if index + 1 < items.count { included.insert(index + 1) }
            }
            return SearchGroup(day: day, entries: included.sorted().map {
                SearchEntry(capture: items[$0], isMatch: hits.contains($0))
            })
        }
    }
}
