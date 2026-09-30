import Foundation

/// Backup fixtures are synthetic; no application-support archive is opened.
@main
struct ArchiveBackupTests {
    @MainActor private static var checks = 0
    private static let files = FileManager.default
    @MainActor private static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        if try !value() { throw NSError(domain: "ArchiveBackupTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    @MainActor private static func rejected(_ body: () throws -> Void, _ message: String) throws {
        var failed = false
        do { try body() } catch { failed = true }
        try expect(failed, message)
    }
    private static func inventory(_ root: URL) -> Set<String> {
        Set((files.enumerator(atPath: root.path)?.allObjects as? [String]) ?? [])
    }

    @MainActor static func main() throws {
        let root = files.temporaryDirectory.appendingPathComponent("DaBinWorkspaceBackup-\(UUID())")
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }
        let source = try CaptureStore(root: root.appendingPathComponent("Source"))
        let capture = try source.capture(text: "Reusable fictional client reply")[0]
        let workspace = WorkspaceStore(root: source.root)
        try workspace.setScratchpad(text: "A proposal to finish after lunch", project: "Client A")
        try workspace.setOnShelf([capture.id], included: true)
        try workspace.setSnippetName("Proposal reply", for: capture.id)
        try workspace.markInboxProcessed([capture.id])
        workspace.selectedProject = "Client A"
        let backup = root.appendingPathComponent("Complete.dabinbackup")
        try source.exportBackup(to: backup)
        let manifest = try JSONDecoder().decode(ArchiveBackup.Manifest.self,
            from: Data(contentsOf: backup.appendingPathComponent("Manifest.json")))
        try expect(manifest.workspace == workspace.snapshot, "Backup records scratchpads, shelf references, snippet names, and processed Inbox IDs")

        let target = try CaptureStore(root: root.appendingPathComponent("Target"))
        let targetWorkspace = WorkspaceStore(root: target.root)
        try targetWorkspace.setScratchpad(text: "Keep my existing client work", project: "Client B")
        targetWorkspace.selectedProject = "Client B"
        let result = try target.restoreBackup(from: backup)
        try targetWorkspace.reload()
        try expect(result.addedCount == 1 && targetWorkspace.scratchpad(project: "Client A") == "A proposal to finish after lunch",
                   "Restore brings notes back with their project captures")
        try expect(targetWorkspace.scratchpad(project: "Client B") == "Keep my existing client work" && targetWorkspace.selectedProject == "Client B",
                   "Restore preserves unrelated authored text and the active workspace")
        try expect(targetWorkspace.shelfCaptureIDs.contains(capture.id)
                   && targetWorkspace.snippetName(for: capture.id) == "Proposal reply"
                   && targetWorkspace.processedInboxIDs.contains(capture.id), "Restored references point to the same capture identity")
        let beforeRepeat = targetWorkspace.snapshot
        let repeated = try target.restoreBackup(from: backup)
        try targetWorkspace.reload()
        try expect(repeated.addedCount == 0 && targetWorkspace.snapshot == beforeRepeat, "Workspace restoration is idempotent")
        try expect(WorkspaceStore(root: target.root).snapshot == beforeRepeat, "Restored workspace survives reopening")

        let notesOnlySource = try CaptureStore(root: root.appendingPathComponent("NotesOnlySource"))
        let notes = WorkspaceStore(root: notesOnlySource.root)
        try notes.setScratchpad(text: "A scratchpad survives without any captures", project: nil)
        let notesBackup = root.appendingPathComponent("NotesOnly.dabinbackup")
        try notesOnlySource.exportBackup(to: notesBackup)
        let notesOnlyTarget = try CaptureStore(root: root.appendingPathComponent("NotesOnlyTarget"))
        let notesResult = try notesOnlyTarget.restoreBackup(from: notesBackup)
        try expect(notesResult.addedCount == 0 && WorkspaceStore(root: notesOnlyTarget.root).scratchpad(project: nil) == notes.scratchpad(project: nil),
                   "A workspace-only backup restores even with zero new capture records")

        let conflicting = try CaptureStore(root: root.appendingPathComponent("Conflicting"))
        let conflictWorkspace = WorkspaceStore(root: conflicting.root)
        try conflictWorkspace.setScratchpad(text: "Newer authored text must survive", project: "Client A")
        let beforeConflict = inventory(conflicting.root)
        let conflictBytes = try Data(contentsOf: conflicting.root.appendingPathComponent(WorkspaceStore.filename))
        try rejected({ _ = try conflicting.restoreBackup(from: backup) }, "Different scratchpad contents require conflict resolution")
        try expect(conflicting.captures.isEmpty && inventory(conflicting.root) == beforeConflict
                   && (try Data(contentsOf: conflicting.root.appendingPathComponent(WorkspaceStore.filename))) == conflictBytes,
                   "Workspace conflict is found before files or metadata are written")
        let aliasConflict = try CaptureStore(root: root.appendingPathComponent("AliasConflict"))
        let aliasWorkspace = WorkspaceStore(root: aliasConflict.root)
        try aliasWorkspace.setSnippetName("My current name", for: capture.id)
        try rejected({ _ = try aliasConflict.restoreBackup(from: backup) }, "A backup never replaces a different named snippet")
        try expect(WorkspaceStore(root: aliasConflict.root).snippetName(for: capture.id) == "My current name", "The current snippet name remains intact")

        for hasExistingWorkspace in [false, true] {
            let failed = try CaptureStore(root: root.appendingPathComponent("Failure-\(hasExistingWorkspace)"))
            if hasExistingWorkspace { try WorkspaceStore(root: failed.root).setScratchpad(text: "Keep current text", project: "Client B") }
            let workspaceURL = failed.root.appendingPathComponent(WorkspaceStore.filename)
            let originalBytes = try? Data(contentsOf: workspaceURL)
            let before = inventory(failed.root)
            failed.backupFailureInjector = { if $0 == .beforeMetadataSave { throw CaptureStoreError.importVerificationFailed } }
            try rejected({ _ = try failed.restoreBackup(from: backup) }, "A failure after writing workspace data is reported")
            try expect(failed.captures.isEmpty && inventory(failed.root) == before && (try? Data(contentsOf: workspaceURL)) == originalBytes,
                       "Failed restore rolls back workspace bytes and capture files together")
        }
        let failedCommit = try CaptureStore(root: root.appendingPathComponent("FailedCommit"))
        let originalInventory = inventory(failedCommit.root)
        try rejected({
            _ = try ArchiveBackup.restore(from: backup, into: failedCommit.root, existing: [], validate: { _ in },
                checkpoint: { _ in }, commit: { _ in throw CaptureStoreError.importVerificationFailed })
        }, "A metadata transaction failure is reported after workspace staging")
        try expect(inventory(failedCommit.root) == originalInventory && (try WorkspaceStore.readSnapshot(at: failedCommit.root)) == nil,
                   "A failed metadata commit removes only this attempt's workspace data")

        let editedDuringRestore = try CaptureStore(root: root.appendingPathComponent("EditedDuringRestore"))
        editedDuringRestore.backupFailureInjector = { point in
            if point == .beforeMetadataSave {
                try WorkspaceStore(root: editedDuringRestore.root).setScratchpad(text: "An external edit must survive rollback", project: "Client A")
                throw CaptureStoreError.importVerificationFailed
            }
        }
        var preservedChange = false
        do { _ = try editedDuringRestore.restoreBackup(from: backup) }
        catch ArchiveBackupError.rollbackIncomplete(_) { preservedChange = true }
        try expect(preservedChange && WorkspaceStore(root: editedDuringRestore.root).scratchpad(project: "Client A") == "An external edit must survive rollback",
                   "Rollback preserves and reports workspace edits made after restore wrote its version")

        let legacySource = try CaptureStore(root: root.appendingPathComponent("LegacySource"))
        _ = try legacySource.capture(text: "A capture without a workspace")
        let legacyBackup = root.appendingPathComponent("Legacy.dabinbackup")
        try legacySource.exportBackup(to: legacyBackup)
        let legacyManifest = try JSONSerialization.jsonObject(with: Data(contentsOf: legacyBackup.appendingPathComponent("Manifest.json"))) as! [String: Any]
        try expect(legacyManifest["workspace"] == nil, "Legacy backup manifest may omit workspace data")
        let beforeLegacy = targetWorkspace.snapshot
        _ = try target.restoreBackup(from: legacyBackup)
        try expect(try WorkspaceStore.readSnapshot(at: target.root) == beforeLegacy, "An older backup leaves all workspace notes and preferences untouched")

        let unsafe = try CaptureStore(root: root.appendingPathComponent("Unsafe"))
        let outside = root.appendingPathComponent("Outside.json")
        try Data("private outside text".utf8).write(to: outside)
        try files.createSymbolicLink(at: unsafe.root.appendingPathComponent(WorkspaceStore.filename), withDestinationURL: outside)
        try rejected({ _ = try unsafe.restoreBackup(from: backup) }, "Restore rejects a symbolic-link workspace")
        try rejected({ try unsafe.exportBackup(to: root.appendingPathComponent("Unsafe.dabinbackup")) }, "Export rejects a symbolic-link workspace")
        try expect(try String(contentsOf: outside, encoding: .utf8) == "private outside text", "Workspace backup never reads or changes the external link target")
        let dangling = try CaptureStore(root: root.appendingPathComponent("Dangling"))
        try files.createSymbolicLink(at: dangling.root.appendingPathComponent(WorkspaceStore.filename), withDestinationURL: root.appendingPathComponent("Missing.json"))
        try rejected({ _ = try dangling.restoreBackup(from: backup) }, "Restore rejects dangling workspace links before writing")
        print("PASS: \(checks) workspace backup, conflict, rollback, restart, and legacy checks.")
    }
}
