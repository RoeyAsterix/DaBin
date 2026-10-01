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
    let attachmentRelativePath: String?
    let originalFilename: String?
    let kindRaw: String?
    let projectName: String?

    init(_ capture: Capture, projectName: String?) {
        version = 2
        id = capture.id
        capturedAt = capture.capturedAt
        captureDay = capture.captureDay
        utcOffset = capture.captureUTCOffsetSeconds
        attachmentRelativePath = capture.attachmentRelativePath
        originalFilename = capture.originalFilename
        kindRaw = capture.kindRaw
        self.projectName = projectName
    }

    func ownedPaths() throws -> [String] {
        guard version == 1 || version == 2 else { throw CaptureStoreError.invalidManagedPath }
        let archive = try DailyArchive.captureRelativePath(id: id, capturedAt: capturedAt,
                                                          captureDay: captureDay, utcOffset: utcOffset)
        var paths = ["Imports/\(id.uuidString).json", archive, "Originals/\(id.uuidString)",
                "Previews/\(id.uuidString)", "Staging/\(id.uuidString)", "MigrationStaging/\(id.uuidString)"]
        if let path = attachmentRelativePath,
           let filename = originalFilename, let kind = kindRaw.flatMap(CaptureKind.init(rawValue:)),
           ProjectFileArchive.ownsOriginal(path, id: id, day: captureDay, kind: kind, filename: filename) {
            paths.append(path)
        }
        // A damaged receipt can reference another capture's attachment. Ignore
        // that unproven path; the immutable identity still owns its private
        // archive/cache folders, and the neighboring original must survive.
        return paths
    }
}
