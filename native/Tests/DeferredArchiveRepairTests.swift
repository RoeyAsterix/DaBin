import Foundation

@main
struct DeferredArchiveRepairTests {
    @MainActor private static var checks = 0
    private static let files = FileManager.default
    @MainActor private static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        if try !value() { throw NSError(domain: "DeferredArchiveRepairTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    @MainActor private static func seed(_ root: URL, count: Int) throws -> [Capture] {
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        let captures = (0..<count).map { index in
            Capture(capturedAt: Date().addingTimeInterval(-Double(index)), kind: .text,
                    originalText: "Synthetic startup item \(index)", title: "Startup item \(index)")
        }
        try CaptureRepository(root: root).save(captures)
        return captures
    }
    private static func inventory(_ root: URL) -> Set<String> {
        Set((files.enumerator(atPath: root.path)?.allObjects as? [String]) ?? [])
    }

    @MainActor static func main() async throws {
        let root = files.temporaryDirectory.appendingPathComponent("DaBinDeferredArchive-\(UUID())")
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }
        let coldRoot = root.appendingPathComponent("Cold")
        let seeded = try seed(coldRoot, count: 8)
        let store = try CaptureStore(root: coldRoot, repairArchiveOnOpen: false)
        try expect(store.captures.count == seeded.count && store.pendingArchiveRepairCount == seeded.count,
                   "Metadata is fully available before readable-folder maintenance starts")
        try expect(!files.fileExists(atPath: store.archiveRoot.path), "Deferred initialization writes no readable mirrors")
        try expect(CaptureSearch.groups(captures: store.captures, query: "startup", filter: .all).flatMap(\.entries).count == seeded.count,
                   "Search works immediately before mirror creation")
        store.startArchiveRepair()
        await store.waitForArchiveRepair()
        try expect(store.pendingArchiveRepairCount == 0 && store.captures.allSatisfy {
            files.fileExists(atPath: store.archiveURL(for: $0)!.appendingPathComponent("Capture.json").path)
        }, "Background maintenance eventually creates every readable folder")

        let synchronousRoot = root.appendingPathComponent("Synchronous")
        _ = try seed(synchronousRoot, count: 1)
        let synchronous = try CaptureStore(root: synchronousRoot)
        try expect(files.fileExists(atPath: synchronous.archiveURL(for: synchronous.captures[0])!.appendingPathComponent("Capture.json").path),
                   "The existing synchronous initializer contract remains available to explicit callers")

        let cancelRoot = root.appendingPathComponent("Cancel")
        _ = try seed(cancelRoot, count: 12)
        let cancellable = try CaptureStore(root: cancelRoot, repairArchiveOnOpen: false)
        cancellable.startArchiveRepair()
        cancellable.cancelArchiveRepair()
        try await Task.sleep(for: .milliseconds(60))
        try expect(!files.fileExists(atPath: cancellable.archiveRoot.path) && cancellable.pendingArchiveRepairCount == 12,
                   "Cancellation before first slice prevents all post-shutdown mirror writes")
        cancellable.startArchiveRepair()
        let limit = Date().addingTimeInterval(3)
        while cancellable.pendingArchiveRepairCount == 12 && Date() < limit { try await Task.sleep(for: .milliseconds(5)) }
        try expect(cancellable.pendingArchiveRepairCount < 12, "A cancelled sweep can resume")
        cancellable.cancelArchiveRepair()
        let afterCancel = inventory(cancelRoot)
        try await Task.sleep(for: .milliseconds(80))
        try expect(inventory(cancelRoot) == afterCancel, "No queued repair writes after cancellation completes")
        let resumed = try CaptureStore(root: cancelRoot, repairArchiveOnOpen: false)
        resumed.startArchiveRepair()
        await resumed.waitForArchiveRepair()
        try expect(resumed.pendingArchiveRepairCount == 0, "A new session repairs work left by interrupted shutdown")

        let editRoot = root.appendingPathComponent("Edits")
        _ = try seed(editRoot, count: 3)
        let editable = try CaptureStore(root: editRoot, repairArchiveOnOpen: false)
        let changed = editable.captures[0]
        let deleted = editable.captures[1]
        let deletedFolder = editable.archiveURL(for: deleted)!
        try editable.update(changed, comment: "Latest user edit", reminderAt: nil, reminderTimeZoneID: nil)
        try expect(editable.pendingArchiveRepairCount == 2, "An immediate scoped save removes redundant queued maintenance")
        _ = try editable.remove(deleted)
        editable.startArchiveRepair()
        await editable.waitForArchiveRepair()
        let markdown = try String(contentsOf: editable.archiveURL(for: changed)!.appendingPathComponent("Capture.md"), encoding: .utf8)
        try expect(markdown.contains("Latest user edit"), "Deferred repair never restores a stale launch snapshot over an edit")
        try expect(!files.fileExists(atPath: deletedFolder.path) && !editable.captures.contains { $0.id == deleted.id },
                   "A queued deleted capture cannot recreate its folder or metadata")

        let preserveRoot = root.appendingPathComponent("Preserve")
        let originalStore = try CaptureStore(root: preserveRoot)
        let original = try originalStore.createNote(text: "Original note")
        let folder = originalStore.archiveURL(for: original)!
        let externalEdit = "A synthetic external edit to preserve"
        try Data(externalEdit.utf8).write(to: folder.appendingPathComponent("Capture.md"))
        let preserving = try CaptureStore(root: preserveRoot, repairArchiveOnOpen: false)
        try expect(try String(contentsOf: folder.appendingPathComponent("Capture.md"), encoding: .utf8) == externalEdit,
                   "Metadata-ready startup leaves existing readable files untouched")
        preserving.startArchiveRepair()
        await preserving.waitForArchiveRepair()
        let editURLs = try files.contentsOfDirectory(at: folder.appendingPathComponent("Local edits"), includingPropertiesForKeys: nil)
        try expect(editURLs.contains { (try? String(contentsOf: $0, encoding: .utf8)) == externalEdit },
                   "Deferred mirror repair retains edited sidecars using the original safety-copy policy")

        let failureRoot = root.appendingPathComponent("Failure")
        _ = try seed(failureRoot, count: 1)
        try Data("A synthetic obstruction".utf8).write(to: failureRoot.appendingPathComponent("Archive"))
        let obstructed = try CaptureStore(root: failureRoot, repairArchiveOnOpen: false)
        obstructed.startArchiveRepair()
        await obstructed.waitForArchiveRepair()
        try expect(obstructed.captures.count == 1 && obstructed.error != nil, "A mirror failure keeps authoritative metadata and surfaces retryable feedback")
        try files.removeItem(at: failureRoot.appendingPathComponent("Archive"))
        let repaired = try CaptureStore(root: failureRoot, repairArchiveOnOpen: false)
        repaired.startArchiveRepair()
        await repaired.waitForArchiveRepair()
        try expect(repaired.error == nil && files.fileExists(atPath: repaired.archiveURL(for: repaired.captures[0])!.path),
                   "The next launch retries an interrupted or obstructed readable-folder repair")
        print("PASS: \(checks) deferred archive readiness, cancellation, recovery, edit, and deletion checks.")
    }
}
