import Foundation
import CryptoKit

/// All data is synthetic and contained in one disposable temporary directory.
@main struct ArchiveRecoveryTests {
    @MainActor private static var checks = 0
    private static let files = FileManager.default

    @MainActor private static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        if try !value() { throw NSError(domain: "ArchiveRecoveryTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    @MainActor private static func rejected(_ action: () throws -> Void, _ message: String) throws {
        var didFail = false
        do { try action() } catch { didFail = true }
        try expect(didFail, message)
    }
    private static func write(_ data: Data, to url: URL) throws {
        try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
    private static func contents(_ url: URL) throws -> Data { try Data(contentsOf: url) }
    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private static func inventory(_ root: URL) -> Set<String> {
        let enumerator = files.enumerator(atPath: root.path)
        var paths = Set<String>()
        while let path = enumerator?.nextObject() as? String { paths.insert(path) }
        return paths
    }

    @MainActor static func main() async throws {
        let root = files.temporaryDirectory.appendingPathComponent("DaBinArchiveRecoveryTests-\(UUID())")
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }
        try await trashLifecycle(root.appendingPathComponent("trash"))
        try await trashJournalRecovery(root.appendingPathComponent("journals"))
        try await backupRoundTrip(root.appendingPathComponent("backups"))
        print("PASS: \(checks) recoverable-trash and archive backup/restore assertions")
    }

    @MainActor private static func trashLifecycle(_ root: URL) async throws {
        var store: CaptureStore? = try CaptureStore(root: root)
        let bytes = Data([0, 1, 255, 100, 0, 24])
        let file = try await store!.importData(bytes, filename: "reference.bin")
        let reminder = Date().addingTimeInterval(86_400)
        try store!.update(file, comment: "Keep this annotation", reminderAt: reminder, reminderTimeZoneID: "UTC")
        try store!.convertToTask(file)
        try store!.setOrganization(file, pinned: true, projectName: "  Client research \n")
        try expect(file.projectName == "Client research" && file.isPinned, "Organization trims names")
        let oldRevision = file.reminderRevision
        let original = store!.managedURL(for: file)!
        store!.failureInjector = { if $0 == .beforeMetadataSave { throw CaptureStoreError.importVerificationFailed } }
        try rejected({ try store!.moveToTrash(file) }, "Failed trash save throws")
        try expect(file.deletedAt == nil && file.reminderRevision == oldRevision && store!.captures.count == 1,
                   "Failed trash save rolls back metadata and visibility")
        store!.failureInjector = nil
        try store!.moveToTrash(file)
        try expect(store!.captures.isEmpty && store!.trashedCaptures.count == 1, "Trash leaves active captures")
        try expect(file.reminderRevision > oldRevision && file.deletedAt != nil, "Trash invalidates delayed notification schedules")
        try expect(try contents(original) == bytes, "Trash preserves saved original bytes")
        try rejected({ try store!.save(captures: [file]) }, "Stale service saves cannot revive trash")
        try rejected({ try store!.setOrganization(file, pinned: false, projectName: nil) }, "Stale organization edit is rejected")
        file.comment = "late stale worker mutation"
        try store!.refresh()
        try expect(store!.trashedCaptures[0].comment == "Keep this annotation", "Trash uses a separate canonical object")
        let identity = file.id
        store = nil
        store = try CaptureStore(root: root)
        let trashed = store!.trashedCaptures[0]
        try expect(store!.captures.isEmpty && trashed.id == identity && trashed.reminderAt == reminder,
                   "Trash and reminder metadata survive reopening without becoming active")
        try expect(trashed.isTask && trashed.isPinned && trashed.projectName == "Client research", "Trash retains task and organization")
        store!.failureInjector = { if $0 == .beforeMetadataSave { throw CaptureStoreError.importVerificationFailed } }
        try rejected({ try store!.restoreFromTrash(trashed) }, "Failed restore throws")
        try expect(trashed.deletedAt != nil && store!.captures.isEmpty, "Failed restore stays in trash")
        store!.failureInjector = nil
        try store!.restoreFromTrash(trashed)
        let restored = store!.captures[0]
        try expect(restored.id == identity && restored.deletedAt == nil && store!.trashedCaptures.isEmpty,
                   "Restore preserves identity and returns to active captures")
        try expect(restored.comment == "Keep this annotation" && restored.notificationState == "pending", "Restored annotations and scheduling intent remain attached")
        try rejected({ try store!.save(captures: [trashed]) }, "An old trash object cannot overwrite the restored object")
        let project = restored.projectName
        store!.failureInjector = { if $0 == .beforeMetadataSave { throw CaptureStoreError.importVerificationFailed } }
        try rejected({ try store!.setOrganization(restored, pinned: false, projectName: "Different") }, "Organization failure throws")
        try expect(restored.isPinned && restored.projectName == project, "Organization failure rolls back")
        store!.failureInjector = nil
        try store!.setOrganization(restored, pinned: true, projectName: String(repeating: "x", count: 150))
        try expect(restored.projectName?.count == 120, "Project names are bounded")
        try store!.moveToTrash(restored)
        _ = try store!.permanentlyRemove(store!.trashedCaptures[0])
        try expect(store!.trashedCaptures.isEmpty && !files.fileExists(atPath: original.path), "Explicit permanent removal cleans trash originals")
        store = nil
        let empty = try CaptureStore(root: root)
        try expect(empty.captures.isEmpty && empty.trashedCaptures.isEmpty, "Permanent removal survives reopening")
    }

    @MainActor private static func trashJournalRecovery(_ root: URL) async throws {
        var store: CaptureStore? = try CaptureStore(root: root)
        store!.failureInjector = { if $0 == .afterMetadataSave { throw CaptureStoreError.injectedInterruption } }
        do { _ = try await store!.importData(Data("saved import".utf8), filename: "saved.txt") }
        catch CaptureStoreError.injectedInterruption { }
        store!.failureInjector = nil
        let imported = store!.captures[0]
        try rejected({ try store!.exportBackup(to: root.deletingLastPathComponent().appendingPathComponent("busy.dabinbackup")) },
                     "Backup waits for an unfinished import journal rather than publishing a partial archive")
        try store!.moveToTrash(imported)
        store = nil
        store = try CaptureStore(root: root)
        try expect(store!.captures.isEmpty && store!.trashedCaptures.count == 1, "Interrupted import receipt never revives a trashed capture")
        try expect(try files.contentsOfDirectory(atPath: root.appendingPathComponent("Imports").path).isEmpty,
                   "Recovered existing trash clears completed import receipt")
        store!.removalFailureInjector = { if $0 == .beforeMetadataDelete { throw CaptureStoreError.injectedInterruption } }
        do { _ = try store!.permanentlyRemove(store!.trashedCaptures[0]) }
        catch CaptureStoreError.injectedInterruption { }
        store = nil
        store = try CaptureStore(root: root)
        try expect(store!.trashedCaptures.count == 1 && store!.managedURL(for: store!.trashedCaptures[0]) != nil,
                   "Interrupted permanent deletion before commit preserves trash and its original")
    }

    @MainActor private static func backupRoundTrip(_ root: URL) async throws {
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        let source = try CaptureStore(root: root.appendingPathComponent("source"))
        let note = try source.capture(text: "A reusable research note 🟣")[0]
        try source.setOrganization(note, pinned: true, projectName: "Website")
        try source.update(note, comment: "Keep the useful context", reminderAt: Date().addingTimeInterval(172_800), reminderTimeZoneID: "UTC")
        let activeFile = try await source.importData(Data("Active document original\n".utf8), filename: "reference.txt")
        let trashedFile = try await source.importData(Data([0, 255, 12, 99]), filename: "discarded.bin")
        try source.moveToTrash(trashedFile)
        let edited = source.archiveURL(for: note)!.appendingPathComponent("Local edits/preserved.md")
        try write(Data("My hand edited version".utf8), to: edited)
        let backup = root.appendingPathComponent("Complete.dabinbackup")
        try source.exportBackup(to: backup)
        try expect(!inventory(backup).contains(where: { $0.contains("metadata.store") }), "Backup contains no live SQLite copy")
        try rejected({ try source.exportBackup(to: backup) }, "Backup export never replaces an existing package")
        try rejected({ try source.exportBackup(to: source.root.appendingPathComponent("unsafe.dabinbackup")) }, "Backup cannot be nested in live storage")
        let targetURL = root.appendingPathComponent("target")
        var target: CaptureStore? = try CaptureStore(root: targetURL)
        let neighbor = try target!.capture(text: "Existing capture must survive")[0]
        let result = try target!.restoreBackup(from: backup)
        try expect(result.addedCount == 3 && result.existingCount == 0, "Restore merges all active and trashed records")
        try expect(target!.captures.count == 3 && target!.trashedCaptures.count == 1, "Restore keeps trash out of active captures")
        let restoredNote = target!.captures.first { $0.id == note.id }!
        try expect(restoredNote.comment == note.comment && restoredNote.projectName == "Website" && restoredNote.isPinned,
                   "Backup roundtrip preserves annotations, reminders and organization")
        try expect(try contents(target!.archiveURL(for: restoredNote)!.appendingPathComponent("Local edits/preserved.md")) == contents(edited),
                   "Backup preserves user-edited sidecar safety copies")
        let restoredFile = target!.captures.first { $0.id == activeFile.id }!
        try expect(try contents(target!.managedURL(for: restoredFile)!) == contents(source.managedURL(for: activeFile)!),
                   "Restored original is byte-identical")
        let repeated = try target!.restoreBackup(from: backup)
        try expect(repeated.addedCount == 0 && repeated.existingCount == 3, "Identical restore is idempotent")
        try expect(target!.captures.contains { $0.id == neighbor.id }, "Unrelated capture is retained")
        target = nil
        target = try CaptureStore(root: targetURL)
        try expect(target!.captures.count == 3 && target!.trashedCaptures.count == 1, "Merged restore survives reopening")
        let changed = target!.captures.first { $0.id == note.id }!
        try target!.update(changed, comment: "A newer comment", reminderAt: changed.reminderAt, reminderTimeZoneID: changed.reminderTimeZoneID)
        try rejected({ _ = try target!.restoreBackup(from: backup) }, "Conflicting metadata never overwrites an existing capture")
        try expect(changed.comment == "A newer comment", "Conflicting restore preserves current annotations")

        for point in [ArchiveRestoreCheckpoint.afterFileCopy, .beforeMetadataSave] {
            let failed = try CaptureStore(root: root.appendingPathComponent("rollback-\(UUID())"))
            let keeper = try failed.capture(text: "Keep this one")[0]
            let before = inventory(failed.root)
            failed.backupFailureInjector = { if $0 == point { throw CaptureStoreError.importVerificationFailed } }
            try rejected({ _ = try failed.restoreBackup(from: backup) }, "Injected restore failure is reported")
            try expect(failed.captures.map(\.id) == [keeper.id] && failed.trashedCaptures.isEmpty,
                       "Failed restore does not partially commit metadata")
            try expect(inventory(failed.root) == before, "Failed restore removes only its newly copied files/directories")
        }

        let packageManifest = try JSONDecoder().decode(ArchiveBackup.Manifest.self,
            from: contents(backup.appendingPathComponent("Manifest.json")))
        let firstCopiedPath = packageManifest.files[0].relativePath
        for replacement in ["parent-symlink", "new-leaf", "edited-leaf"] {
            let failed = try CaptureStore(root: root.appendingPathComponent("changed-path-\(replacement)"))
            let keeper = try failed.capture(text: "Current metadata survives unsafe cleanup")[0]
            let created = failed.root.appendingPathComponent(firstCopiedPath)
            let sentinelBytes = Data("New user-owned bytes must survive rollback".utf8)
            let external = root.appendingPathComponent("outside-\(replacement)", isDirectory: true)
            try files.createDirectory(at: external, withIntermediateDirectories: true)
            let sentinel = external.appendingPathComponent(created.lastPathComponent)
            try sentinelBytes.write(to: sentinel)
            failed.backupFailureInjector = { checkpoint in
                guard checkpoint == .afterFileCopy else { return }
                if replacement == "parent-symlink" {
                    try files.moveItem(at: created.deletingLastPathComponent(),
                                       to: external.appendingPathComponent("displaced-created-directory"))
                    try files.createSymbolicLink(at: created.deletingLastPathComponent(), withDestinationURL: external)
                } else if replacement == "new-leaf" {
                    try files.removeItem(at: created)
                    try sentinelBytes.write(to: created)
                } else {
                    let handle = try FileHandle(forWritingTo: created)
                    try handle.truncate(atOffset: 0)
                    try handle.write(contentsOf: sentinelBytes)
                    try handle.close()
                }
                throw CaptureStoreError.importVerificationFailed
            }
            var reportedPreservation = false
            do { _ = try failed.restoreBackup(from: backup) }
            catch ArchiveBackupError.rollbackIncomplete(_) { reportedPreservation = true }
            try expect(reportedPreservation, "Changed \(replacement) reports preserved files instead of claiming full cleanup")
            try expect(try contents(replacement == "parent-symlink" ? sentinel : created) == sentinelBytes,
                       "Rollback preserves \(replacement) user-owned bytes")
            try expect(failed.captures.map(\.id) == [keeper.id] && failed.trashedCaptures.isEmpty,
                       "Changed-path restore never commits partial metadata")
        }

        let fresh = try CaptureStore(root: root.appendingPathComponent("rejections"))
        let manifestPath = backup.appendingPathComponent("Manifest.json")
        let cleanManifest = try contents(manifestPath)
        var manifest = try JSONSerialization.jsonObject(with: cleanManifest) as! [String: Any]
        let entries = manifest["files"] as! [[String: Any]]
        let originalPath = activeFile.attachmentRelativePath!
        let packageOriginal = backup.appendingPathComponent("Files/" + originalPath)
        let originalBytes = try contents(packageOriginal)
        try Data("tampered".utf8).write(to: packageOriginal)
        try rejected({ _ = try fresh.restoreBackup(from: backup) }, "Tampered original checksum is rejected")
        try originalBytes.write(to: packageOriginal)
        try files.removeItem(at: packageOriginal)
        try rejected({ _ = try fresh.restoreBackup(from: backup) }, "Missing original is rejected")
        let outside = root.appendingPathComponent("outside.txt")
        try originalBytes.write(to: outside)
        try files.createSymbolicLink(at: packageOriginal, withDestinationURL: outside)
        try rejected({ _ = try fresh.restoreBackup(from: backup) }, "Symbolic link inside backup is rejected")
        try files.removeItem(at: packageOriginal)
        try originalBytes.write(to: packageOriginal)
        var maliciousEntries = entries
        maliciousEntries[0]["relativePath"] = "../outside.txt"
        manifest["files"] = maliciousEntries
        let malicious = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        try malicious.write(to: manifestPath)
        try Data((digest(malicious) + "\n").utf8).write(to: backup.appendingPathComponent("Manifest.sha256"))
        try rejected({ _ = try fresh.restoreBackup(from: backup) }, "Traversal is rejected even with a recomputed manifest checksum")
        try expect(fresh.captures.isEmpty && fresh.trashedCaptures.isEmpty, "Rejected packages never write capture metadata")
        try expect(try contents(outside) == originalBytes, "Rejected package never modifies external files")
        try cleanManifest.write(to: manifestPath)
        try Data((digest(cleanManifest) + "\n").utf8).write(to: backup.appendingPathComponent("Manifest.sha256"))
        try files.removeItem(at: source.managedURL(for: activeFile)!)
        let incomplete = root.appendingPathComponent("Incomplete.dabinbackup")
        try rejected({ try source.exportBackup(to: incomplete) }, "Export rejects a missing required original")
        try expect(!files.fileExists(atPath: incomplete.path), "Failed export never publishes an incomplete package")
    }
}
