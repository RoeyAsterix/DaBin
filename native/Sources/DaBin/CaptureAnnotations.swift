import Foundation

/// A reply's identity and original posting date survive edits. Legacy captures
/// did not record comment dates; nil deliberately avoids inventing one.
struct CaptureCommentEntry: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let createdAt: Date?
    var text: String
    var editedAt: Date?

    init(id: UUID = UUID(), createdAt: Date?, text: String, editedAt: Date? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.text = text
        self.editedAt = editedAt
    }
}

enum CaptureCommentThread {
    static let maximumEntries = 1_000
    static let maximumNewCommentCharacters = 100_000

    static func ordered(_ entries: [CaptureCommentEntry]) -> [CaptureCommentEntry] {
        entries.sorted {
            if $0.createdAt != $1.createdAt { return ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    static func text(_ entries: [CaptureCommentEntry]) -> String {
        ordered(entries).map(\.text).joined(separator: "\n\n")
    }

    /// Public `comment` remains writable for existing callers. An explicit old
    /// aggregate edit is treated as one legacy annotation instead of exposing
    /// a thread whose text disagrees with the cards/search/export consumers.
    static func resolved(_ entries: [CaptureCommentEntry], legacyText: String, captureID: UUID) -> [CaptureCommentEntry] {
        if !entries.isEmpty, text(entries) == legacyText { return ordered(entries) }
        guard !legacyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return [CaptureCommentEntry(id: captureID, createdAt: nil, text: legacyText)]
    }

    static func isValid(_ entries: [CaptureCommentEntry]?, aggregate: String) -> Bool {
        guard let entries else { return true } // Additive payload; old archives remain readable.
        guard entries.count <= maximumEntries, Set(entries.map(\.id)).count == entries.count,
              entries.filter({ $0.createdAt == nil }).count <= 1,
              entries.allSatisfy({ entry in
                  !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  && (entry.createdAt?.timeIntervalSinceReferenceDate.isFinite ?? true)
                  && (entry.editedAt?.timeIntervalSinceReferenceDate.isFinite ?? true)
                  && (entry.createdAt == nil || entry.editedAt == nil || entry.editedAt! >= entry.createdAt!)
              }) else { return false }
        // Whitespace-only legacy comments have no visible thread entries, but
        // retain their exact old bytes for backward-compatible exports.
        return entries.isEmpty ? aggregate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : text(entries) == aggregate
    }
}

/// An immutable reference captured when an alert is presented. Keeping this
/// value prevents an old popup from acknowledging a rescheduled reminder.
struct CaptureReminderOccurrence: Hashable, Sendable {
    let captureID: UUID
    let revision: Int
    let dueAt: Date
}

struct CaptureFocusOccurrence: Hashable, Sendable {
    let captureID: UUID
    let completionID: UUID
}

struct CaptureReminderAcknowledgment: Codable, Equatable, Sendable {
    let revision: Int
    let dueAt: Date
    let acknowledgedAt: Date

    var isValid: Bool {
        revision >= 0 && dueAt.timeIntervalSinceReferenceDate.isFinite
            && acknowledgedAt.timeIntervalSinceReferenceDate.isFinite && acknowledgedAt >= dueAt
    }
}
