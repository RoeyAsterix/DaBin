import Foundation
import CryptoKit

struct ArchiveRestoreResult {
    let addedCount: Int
    let existingCount: Int
}

enum ArchiveRestoreCheckpoint { case afterFileCopy, beforeMetadataSave }

enum ArchiveBackupError: LocalizedError {
    case busy, invalid(String), conflict(String), rollbackIncomplete(String)
    var errorDescription: String? {
        switch self {
        case .busy: return "A capture import or removal must finish before backing up or restoring. Wait for it to finish, or reopen DaBin to recover interrupted work."
        case .invalid(let reason): return "The DaBin backup could not be verified. \(reason)"
        case .conflict(let reason): return "Restore stopped without replacing your saved captures. \(reason)"
        case .rollbackIncomplete(let reason): return "Restore stopped; your current captures were kept. Some restore files changed while it ran and were preserved instead of removed. \(reason)"
        }
    }
}

/// Versioned directory package. Only capture-scoped originals, readable records,
/// saved local edits and previews accompany the committed metadata snapshot.
/// Workspace notes and references are included. Live SQLite, credentials and
/// transient import jobs are excluded.
@MainActor enum ArchiveBackup {
    struct FileRecord: Codable {
        let captureID: UUID
        let relativePath: String
        let byteCount: Int64
        let sha256: String
    }
    struct Manifest: Codable {
        let version: Int
        let createdAt: Date
        let captures: [CaptureSnapshot]
        let files: [FileRecord]
        /// Optional for archives created before workspace notes, shelf, and snippets.
        let workspace: WorkspaceSnapshot?
    }
    struct RestoreOutcome {
        let addedSnapshots: [CaptureSnapshot]
        let existingCount: Int
    }
    private struct FileIdentity: Equatable {
        let device: UInt64
        let inode: UInt64
        let type: FileAttributeType
    }
    private struct CreatedPath {
        let relative: String
        var identity: FileIdentity?
        let verification: OriginalVerification?
    }
    private struct WorkspaceRestore {
        let original: Data?
        let originalIdentity: FileIdentity?
        let replacement: Data
        var installedIdentity: FileIdentity?
        var wasWritten = false
    }
    private static let files = FileManager.default
    private static let manifestName = "Manifest.json"
    private static let checksumName = "Manifest.sha256"

    static func export(snapshots: [CaptureSnapshot], archiveRoot: URL, to destination: URL) throws {
        guard destination.isFileURL, archiveRoot.isFileURL else { throw ArchiveBackupError.invalid("Choose a local folder.") }
        let target = destination.standardizedFileURL
        guard !target.resolvingSymlinksInPath().path.hasPrefix(archiveRoot.path + "/") else {
            throw ArchiveBackupError.invalid("Choose a backup destination outside DaBin's live archive.")
        }
        guard !entryExists(target) else { throw ArchiveBackupError.conflict("The backup destination already exists. Choose a new name.") }
        try validateDirectory(target.deletingLastPathComponent())
        let staging = target.deletingLastPathComponent().appendingPathComponent(".DaBin-backup-\(UUID().uuidString)", isDirectory: true)
        // A backup contains authored text and originals. Keep the staging
        // package private even when the user selected a shared parent folder;
        // the final same-directory move retains these permissions.
        try files.createDirectory(at: staging, withIntermediateDirectories: false,
                                  attributes: [.posixPermissions: 0o700])
        defer { try? files.removeItem(at: staging) }
        let sourceArchive = DailyArchive(root: archiveRoot)
        _ = try sourceArchive.safeURL(WorkspaceStore.filename)
        let workspace = try WorkspaceStore.readSnapshot(at: archiveRoot)
        let package = DailyArchive(root: staging)
        var records: [FileRecord] = []
        let ordered = snapshots.sorted { $0.id.uuidString < $1.id.uuidString }
        for snapshot in ordered {
            try validateCapture(snapshot)
            let scopes = try ownedScopes(snapshot)
            var paths = Set<String>()
            for scope in scopes {
                let directory = try sourceArchive.safeURL(scope)
                if entryExists(directory) {
                    try validateDirectory(directory)
                    for path in try regularFiles(below: directory, relativeTo: archiveRoot) { paths.insert(path) }
                }
            }
            if let original = snapshot.attachmentRelativePath {
                if ProjectFileArchive.ownsOriginal(original, id: snapshot.id, day: snapshot.captureDay,
                    kind: CaptureKind(rawValue: snapshot.kindRaw) ?? .file, filename: snapshot.originalFilename ?? "") {
                    paths.insert(original)
                }
                guard paths.contains(original) else { throw ArchiveBackupError.invalid("A saved original is missing for \(snapshot.title).") }
            }
            for path in paths.sorted() {
                let source = try sourceArchive.safeURL(path)
                let expected = try OriginalFileStorage.verify(source)
                if path == snapshot.attachmentRelativePath, let expectedSize = snapshot.byteCount,
                   expected.byteCount != expectedSize {
                    throw ArchiveBackupError.invalid("A saved original's size no longer matches its receipt.")
                }
                let packagedPath = "Files/" + path
                try package.ensureDirectory((packagedPath as NSString).deletingLastPathComponent)
                let copied = try package.safeURL(packagedPath)
                try files.copyItem(at: source, to: copied)
                let verification = try OriginalFileStorage.verify(copied)
                let afterCopy = try OriginalFileStorage.verify(source)
                guard same(expected, verification), same(expected, afterCopy) else {
                    throw ArchiveBackupError.invalid("A file changed while the backup was being made. Try again.")
                }
                records.append(FileRecord(captureID: snapshot.id, relativePath: path,
                                          byteCount: verification.byteCount, sha256: verification.sha256))
            }
        }
        let manifest = Manifest(version: 1, createdAt: Date(), captures: ordered, files: records, workspace: workspace)
        let data = try encoded(manifest)
        try data.write(to: staging.appendingPathComponent(manifestName), options: .withoutOverwriting)
        try Data((digest(data) + "\n").utf8).write(to: staging.appendingPathComponent(checksumName), options: .withoutOverwriting)
        // Publish only a complete verified package. An existing destination is
        // never removed or replaced, including a file created during the copy.
        try files.moveItem(at: staging, to: target)
    }

    static func restore(from source: URL, into archiveRoot: URL, existing: [CaptureSnapshot],
                        validate: ([CaptureSnapshot]) throws -> Void,
                        checkpoint: (ArchiveRestoreCheckpoint) throws -> Void,
                        commit: ([CaptureSnapshot]) throws -> Void) throws -> RestoreOutcome {
        guard source.isFileURL, archiveRoot.isFileURL else { throw ArchiveBackupError.invalid("Choose a local backup.") }
        try validateDirectory(source)
        let package = DailyArchive(root: source)
        let manifestURL = try package.safeURL(manifestName)
        let checksumURL = try package.safeURL(checksumName)
        try OriginalFileStorage.validateRegularFile(manifestURL)
        try OriginalFileStorage.validateRegularFile(checksumURL)
        let data = try Data(contentsOf: manifestURL)
        let checksum = try String(contentsOf: checksumURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        guard checksum == digest(data) else { throw ArchiveBackupError.invalid("The manifest checksum does not match.") }
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        guard manifest.version == 1 else { throw ArchiveBackupError.invalid("This backup version is not supported.") }
        try validate(manifest.captures)
        for snapshot in manifest.captures { try validateCapture(snapshot) }
        let captureMap = Dictionary(uniqueKeysWithValues: manifest.captures.map { ($0.id, $0) })
        let current = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let destination = DailyArchive(root: archiveRoot)
        // Validate all authored-text conflicts before creating any capture files.
        var workspaceRestore: WorkspaceRestore?
        if let incoming = manifest.workspace {
            let workspaceURL = try destination.safeURL(WorkspaceStore.filename)
            let saved = try WorkspaceStore.readSnapshot(at: archiveRoot)
            let merged = try WorkspaceSnapshot.merging(incoming, into: saved ?? WorkspaceSnapshot())
            if merged != saved {
                let original = saved == nil ? nil : try Data(contentsOf: workspaceURL)
                workspaceRestore = WorkspaceRestore(original: original,
                    originalIdentity: saved == nil ? nil : try identity(of: workspaceURL),
                    replacement: try encoded(merged))
            }
        }
        var fileMap: [String: FileRecord] = [:]
        for record in manifest.files {
            guard let snapshot = captureMap[record.captureID],
                  (try ownedScopes(snapshot).contains(where: { record.relativePath.hasPrefix($0 + "/") })
                    || record.relativePath == snapshot.attachmentRelativePath),
                  fileMap[record.relativePath] == nil,
                  record.byteCount >= 0, record.sha256.count == 64,
                  record.sha256.allSatisfy({ $0.isHexDigit }) else {
                throw ArchiveBackupError.invalid("A file's ownership or identity is invalid.")
            }
            let original = try package.safeURL("Files/" + record.relativePath)
            let verification = try OriginalFileStorage.verify(original)
            guard verification.byteCount == record.byteCount, verification.sha256 == record.sha256 else {
                throw ArchiveBackupError.invalid("A file checksum does not match: \(record.relativePath)")
            }
            fileMap[record.relativePath] = record
        }
        for snapshot in manifest.captures {
            if let path = snapshot.attachmentRelativePath {
                guard let original = fileMap[path], original.captureID == snapshot.id,
                      snapshot.byteCount.map({ $0 == original.byteCount }) ?? true else {
                    throw ArchiveBackupError.invalid("A capture is missing its saved original.")
                }
            }
        }
        let expectedPaths = Set([manifestName, checksumName] + manifest.files.map { "Files/" + $0.relativePath })
        guard Set(try regularFiles(below: source, relativeTo: source)) == expectedPaths else {
            throw ArchiveBackupError.invalid("The package contains unlisted files or missing data.")
        }
        // Preflight ALL identities before creating even one archive directory.
        var added: [CaptureSnapshot] = []
        var unchanged = 0
        for snapshot in manifest.captures {
            if let saved = current[snapshot.id] {
                guard try normalizedSnapshot(saved) == normalizedSnapshot(snapshot) else {
                    throw ArchiveBackupError.conflict("A capture with the same identity has different metadata: \(snapshot.title)")
                }
                unchanged += 1
            } else { added.append(snapshot) }
        }
        let addedIDs = Set(added.map(\.id))
        var toCopy: [(FileRecord, URL, URL)] = []
        for record in manifest.files {
            let target = try destination.safeURL(record.relativePath)
            if entryExists(target) {
                let saved = try OriginalFileStorage.verify(target)
                guard saved.byteCount == record.byteCount, saved.sha256 == record.sha256 else {
                    throw ArchiveBackupError.conflict("A saved file differs from the backup: \(record.relativePath)")
                }
            } else if addedIDs.contains(record.captureID) {
                toCopy.append((record, try package.safeURL("Files/" + record.relativePath), target))
            } else if current[record.captureID]?.attachmentRelativePath == record.relativePath {
                // An existing capture missing its original requires explicit
                // repair, not silently redefining an idempotent restore.
                throw ArchiveBackupError.conflict("An existing capture's original is missing.")
            }
        }
        guard !added.isEmpty || workspaceRestore != nil else { return RestoreOutcome(addedSnapshots: [], existingCount: unchanged) }
        var createdFiles: [CreatedPath] = []
        var stagingFiles: [CreatedPath] = []
        var createdDirectories: [CreatedPath] = []
        do {
            for (record, original, _) in toCopy {
                try createParents(for: record.relativePath, archive: destination, created: &createdDirectories)
                // Verify a sibling staging file before its same-directory move.
                // A process interruption cannot leave a half-copied final original.
                let stagedRelative = (record.relativePath as NSString).deletingLastPathComponent
                    + "/.dabin-restore-\(UUID().uuidString).pending"
                let staged = try destination.safeURL(stagedRelative)
                let expected = OriginalVerification(byteCount: record.byteCount, sha256: record.sha256)
                // A failed copy may leave a partial file. Without a captured
                // identity we preserve that path and report incomplete cleanup.
                stagingFiles.append(CreatedPath(relative: stagedRelative, identity: nil, verification: expected))
                try files.copyItem(at: original, to: staged)
                let copiedIdentity = try identity(of: destination.safeURL(stagedRelative))
                stagingFiles[stagingFiles.count - 1].identity = copiedIdentity
                let copied = try OriginalFileStorage.verify(destination.safeURL(stagedRelative))
                guard copied.byteCount == record.byteCount, copied.sha256 == record.sha256 else {
                    throw ArchiveBackupError.invalid("A restored file did not pass verification.")
                }
                // moveItem refuses replacement if another file appeared.
                try files.moveItem(at: destination.safeURL(stagedRelative), to: destination.safeURL(record.relativePath))
                createdFiles.append(CreatedPath(relative: record.relativePath, identity: copiedIdentity, verification: expected))
                try checkpoint(.afterFileCopy)
            }
            if var workspace = workspaceRestore {
                let url = try destination.safeURL(WorkspaceStore.filename)
                if let original = workspace.original, let expected = workspace.originalIdentity {
                    guard try identity(of: url) == expected, try Data(contentsOf: url) == original else {
                        throw ArchiveBackupError.conflict("Workspace notes changed during restore. Try again.")
                    }
                } else if entryExists(url) {
                    throw ArchiveBackupError.conflict("Workspace notes appeared during restore. Try again.")
                }
                try workspace.replacement.write(to: url, options: .atomic)
                workspace.wasWritten = true
                workspaceRestore = workspace
                workspace.installedIdentity = try identity(of: destination.safeURL(WorkspaceStore.filename))
                workspaceRestore = workspace
                try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            }
            try checkpoint(.beforeMetadataSave)
            try commit(added)
        } catch {
            // No existing file is removed. Metadata commits as one transaction;
            // unsuccessful restores leave the current archive authoritative.
            let filesCleaned = cleanup(Array(stagingFiles.reversed()) + Array(createdFiles.reversed()), archive: destination)
            let directoriesCleaned = cleanup(Array(createdDirectories.reversed()), archive: destination)
            let workspaceCleaned = rollbackWorkspace(workspaceRestore, archive: destination)
            if !filesCleaned || !directoriesCleaned || !workspaceCleaned {
                throw ArchiveBackupError.rollbackIncomplete(error.localizedDescription)
            }
            throw error
        }
        return RestoreOutcome(addedSnapshots: added, existingCount: unchanged)
    }

    private static func validateCapture(_ snapshot: CaptureSnapshot) throws {
        guard snapshot.capturedAt.timeIntervalSinceReferenceDate.isFinite,
              snapshot.createdAt.timeIntervalSinceReferenceDate.isFinite,
              snapshot.updatedAt.timeIntervalSinceReferenceDate.isFinite,
              snapshot.deletedAt.map({ $0.timeIntervalSinceReferenceDate.isFinite }) ?? true,
              snapshot.reminderAt.map({ $0.timeIntervalSinceReferenceDate.isFinite }) ?? true,
              (0...1_000_000_000).contains(snapshot.reminderRevision) else {
            throw ArchiveBackupError.invalid("A capture has an invalid timestamp.")
        }
        _ = try ownedScopes(snapshot)
        if let path = snapshot.attachmentRelativePath {
            guard let filename = snapshot.originalFilename, !filename.isEmpty else {
                throw ArchiveBackupError.invalid("An original has no filename.")
            }
            let dated = try DailyArchive.originalRelativePath(id: snapshot.id, capturedAt: snapshot.capturedAt,
                captureDay: snapshot.captureDay, utcOffset: snapshot.captureUTCOffsetSeconds, filename: filename)
            let legacy = "Originals/\(snapshot.id.uuidString)/\(CaptureClassifier.storageFilename(filename))"
            guard path == dated || path == legacy || ProjectFileArchive.ownsOriginal(path, id: snapshot.id,
                day: snapshot.captureDay, kind: CaptureKind(rawValue: snapshot.kindRaw) ?? .file, filename: filename)
            else { throw ArchiveBackupError.invalid("An attachment path is not owned by its capture.") }
        } else if !["text", "link", "task"].contains(snapshot.kindRaw) {
            throw ArchiveBackupError.invalid("A file capture has no saved original.")
        }
        if let thumbnail = snapshot.thumbnailRelativePath,
           thumbnail != "Previews/\(snapshot.id.uuidString)/thumbnail.png" {
            throw ArchiveBackupError.invalid("A thumbnail path is not owned by its capture.")
        }
    }

    /// Restore only the exact workspace bytes installed by this attempt. An
    /// external editor's changes are preserved and reported as incomplete rollback.
    private static func rollbackWorkspace(_ workspace: WorkspaceRestore?, archive: DailyArchive) -> Bool {
        guard let workspace, workspace.wasWritten else { return true }
        do {
            let url = try archive.safeURL(WorkspaceStore.filename)
            guard let installed = workspace.installedIdentity,
                  try identity(of: url) == installed,
                  try Data(contentsOf: url) == workspace.replacement else { return false }
            if let original = workspace.original {
                try original.write(to: archive.safeURL(WorkspaceStore.filename), options: .atomic)
                try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            } else {
                try files.removeItem(at: archive.safeURL(WorkspaceStore.filename))
            }
            return true
        } catch { return false }
    }

    private static func ownedScopes(_ snapshot: CaptureSnapshot) throws -> [String] {
        [try DailyArchive.captureRelativePath(id: snapshot.id, capturedAt: snapshot.capturedAt,
            captureDay: snapshot.captureDay, utcOffset: snapshot.captureUTCOffsetSeconds),
         "Originals/\(snapshot.id.uuidString)", "Previews/\(snapshot.id.uuidString)"]
    }

    private static func regularFiles(below directory: URL, relativeTo root: URL) throws -> [String] {
        try validateDirectory(directory)
        var result: [String] = []
        for entry in try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            let attributes = try files.attributesOfItem(atPath: entry.path)
            switch attributes[.type] as? FileAttributeType {
            case .typeDirectory:
                result += try regularFiles(below: entry, relativeTo: root)
            case .typeRegular:
                try OriginalFileStorage.validateRegularFile(entry)
                // Foundation enumerates /var paths as /private/var on macOS.
                // Resolve system aliases above the already-validated root;
                // entry symlinks are still rejected by the type checks above.
                let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
                let entryPath = entry.standardizedFileURL.resolvingSymlinksInPath().path
                guard entryPath.hasPrefix(rootPath + "/") else { throw ArchiveBackupError.invalid("A file escaped the package.") }
                result.append(String(entryPath.dropFirst(rootPath.count + 1)))
            default: throw ArchiveBackupError.invalid("Symbolic links, aliases and special files are not supported in backups.")
            }
        }
        return result.sorted()
    }

    private static func createParents(for path: String, archive: DailyArchive, created: inout [CreatedPath]) throws {
        var relative = ""
        for component in path.split(separator: "/").dropLast() {
            relative += (relative.isEmpty ? "" : "/") + component
            let url = try archive.safeURL(relative)
            if !entryExists(url) {
                created.append(CreatedPath(relative: relative, identity: nil, verification: nil))
                try files.createDirectory(at: url, withIntermediateDirectories: false)
                created[created.count - 1].identity = try identity(of: archive.safeURL(relative))
            } else { try validateDirectory(url) }
        }
    }
    private static func identity(of url: URL) throws -> FileIdentity {
        let attributes = try files.attributesOfItem(atPath: url.path)
        guard let device = attributes[.systemNumber] as? NSNumber,
              let inode = attributes[.systemFileNumber] as? NSNumber,
              let type = attributes[.type] as? FileAttributeType,
              type == .typeRegular || type == .typeDirectory else {
            throw ArchiveBackupError.invalid("A restore path changed while it was being written.")
        }
        return FileIdentity(device: device.uint64Value, inode: inode.uint64Value, type: type)
    }
    /// Re-resolve each path at cleanup time and require the exact filesystem
    /// object we created. A replaced parent/leaf or edited file belongs to its
    /// new owner and must survive rollback, even when its pathname is unchanged.
    private static func cleanup(_ paths: [CreatedPath], archive: DailyArchive) -> Bool {
        var complete = true
        for item in paths {
            do {
                let url = try archive.safeURL(item.relative)
                guard entryExists(url) else { continue }
                guard let expectedIdentity = item.identity,
                      try identity(of: url) == expectedIdentity else {
                    complete = false
                    continue
                }
                if let expected = item.verification {
                    guard same(try OriginalFileStorage.verify(url), expected) else {
                        complete = false
                        continue
                    }
                } else {
                    guard try files.contentsOfDirectory(atPath: url.path).isEmpty else {
                        complete = false
                        continue
                    }
                }
                // Recheck identity after hashing/listing, immediately before the
                // unlink; do not reuse the preflight's absolute URL unchecked.
                let checked = try archive.safeURL(item.relative)
                guard try identity(of: checked) == expectedIdentity else {
                    complete = false
                    continue
                }
                try files.removeItem(at: checked)
            } catch { complete = false }
        }
        return complete
    }
    private static func entryExists(_ url: URL) -> Bool {
        (try? files.attributesOfItem(atPath: url.path)) != nil
    }
    private static func validateDirectory(_ url: URL) throws {
        guard (try files.attributesOfItem(atPath: url.path))[.type] as? FileAttributeType == .typeDirectory else {
            throw ArchiveBackupError.invalid("The selected package or folder is not a regular directory.")
        }
    }
    private static func same(_ lhs: OriginalVerification, _ rhs: OriginalVerification) -> Bool {
        lhs.byteCount == rhs.byteCount && lhs.sha256 == rhs.sha256
    }
    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
    private static func normalizedSnapshot(_ snapshot: CaptureSnapshot) throws -> Data {
        try encoded(CaptureSnapshot(Capture(snapshot: snapshot)))
    }
}
