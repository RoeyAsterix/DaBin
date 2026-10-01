import Foundation

struct CaptureRemovalResult {
    let warning: String?
    var cleanupPending: Bool { warning != nil }
}

enum RemovalCheckpoint {
    case afterJournal, beforeMetadataDelete, afterMetadataDelete, beforeFileCleanup, afterFileCleanup
}

/// Contains only identity and archive-location facts, never capture contents.
/// Paths are recomputed and validated on recovery rather than trusted from disk.
struct CaptureRemovalJournal: Codable {
    let version: Int
    let id: UUID
    let capturedAt: Date
    let captureDay: String
    let utcOffset: Int

    init(_ capture: Capture) {
        version = 1
        id = capture.id
        capturedAt = capture.capturedAt
        captureDay = capture.captureDay
        utcOffset = capture.captureUTCOffsetSeconds
    }

    func ownedPaths() throws -> [String] {
        guard version == 1 else { throw CaptureStoreError.invalidManagedPath }
        let archive = try DailyArchive.captureRelativePath(id: id, capturedAt: capturedAt,
                                                          captureDay: captureDay, utcOffset: utcOffset)
        return ["Imports/\(id.uuidString).json", archive, "Originals/\(id.uuidString)",
                "Previews/\(id.uuidString)", "Staging/\(id.uuidString)", "MigrationStaging/\(id.uuidString)"]
    }
}
