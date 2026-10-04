import Foundation

/// An explicit nil project means Inbox; a missing envelope is a legacy draft.
struct ComposerDestination: Codable, Equatable {
    var projectName: String?
}

struct ComposerSnapshot: Codable {
    var text = ""
    var planning = TaskPlanning()
    var reminderEnabled = false
    var reminderMode = "date"
    var countdownHours = 0
    var countdownMinutes = 30
    var reminderDate = Date().addingTimeInterval(3600)
    var destination: ComposerDestination?
}
struct DetailDraftSnapshot: Codable {
    let captureID: UUID
    var title: String?
    let comment: String
    let planning: TaskPlanning
    /// Baseline for three-way recovery after an immediate timing save.
    var committedPlanning: TaskPlanning?
    /// Missing in legacy drafts; a newer committed reminder owns recovery.
    var committedReminderRevision: Int?
    let reminderEnabled: Bool
    let reminderMode: String
    let countdownHours: Int
    let countdownMinutes: Int
    let reminderDate: Date
    var commentComposer: String? = nil
    var editingCommentID: UUID? = nil
}
struct DraftArchiveSnapshot: Codable {
    var version = 1
    var note = ""
    var noteDestination: ComposerDestination?
    var task = ComposerSnapshot()
    var details: [DetailDraftSnapshot] = []
}

/// Drafts are private local recovery data, separate from committed captures.
/// Invalid files are preserved for recovery instead of being overwritten.
@MainActor final class DraftArchive {
    private let url: URL
    private let root: URL
    private(set) var recoveryError: String?
    init(root: URL) { self.root = root; url = root.appendingPathComponent("Drafts.json") }
    func load() -> DraftArchiveSnapshot? {
        do {
            _ = try DailyArchive(root: root).safeURL("Drafts.json")
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            try validateFile()
            let data = try Data(contentsOf: url)
            guard data.count <= 32_000_000 else { throw WorkspaceError.invalidArchive }
            let snapshot = try JSONDecoder().decode(DraftArchiveSnapshot.self, from: data)
            guard snapshot.version == 1, snapshot.details.count <= 10_000,
                  snapshot.details.allSatisfy({ ($0.title?.count ?? 0) <= 2_000 }) else { throw WorkspaceError.invalidArchive }
            return snapshot
        } catch { recoveryError = "Draft recovery needs attention. The original Drafts.json was kept. \(error.localizedDescription)"; return nil }
    }
    func save(_ snapshot: DraftArchiveSnapshot) throws {
        guard recoveryError == nil else { throw WorkspaceError.unavailable(recoveryError!) }
        _ = try DailyArchive(root: root).safeURL("Drafts.json")
        if FileManager.default.fileExists(atPath: url.path) { try validateFile() }
        let data = try JSONEncoder().encode(snapshot)
        guard data.count <= 32_000_000 else { throw WorkspaceError.invalidArchive }
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private func validateFile() throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw WorkspaceError.invalidArchive }
    }
}
