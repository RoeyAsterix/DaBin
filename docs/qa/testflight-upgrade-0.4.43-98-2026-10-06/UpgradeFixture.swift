import Foundation
import CryptoKit
import Darwin
@testable import DaBinTestCore

/// Separate processes link the exact historical/current cached production cores.
/// Every store URL is supplied by the runner beneath its owned /private/tmp root.
@main struct UpgradeFixture {
    @MainActor static var checks = 0
    static let files = FileManager.default
    static func instant(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    static func hash(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    static func json<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
    }
    static func write(_ value: [String: Any], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
    }
    @MainActor static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        guard try condition() else { throw NSError(domain: "DaBinUpgradeFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static func canonicalExistingPath(_ url: URL) throws -> String {
        guard let result = url.path.withCString({ Darwin.realpath($0, nil) }) else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { Darwin.free(result) }
        return String(cString: result)
    }
    @MainActor static func requireLeaf(_ url: URL, type: mode_t, mayBeAbsent: Bool) throws {
        var info = stat()
        let result = url.path.withCString { Darwin.lstat($0, &info) }
        if result == 0 {
            try expect((info.st_mode & mode_t(S_IFMT)) == type, "Reject symlink or unexpected fixture leaf type: \(url.lastPathComponent)")
        } else if mayBeAbsent && errno == ENOENT {
            return
        } else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
    /// Compare every field actually emitted by the old writer, allowing additive new fields.
    @MainActor static func preserves(_ old: Any, _ new: Any, path: String) throws {
        if let old = old as? [String: Any], let new = new as? [String: Any] {
            for key in old.keys.sorted() where key != "schemaVersion" {
                guard let actual = new[key] else { try expect(false, "Missing legacy field \(path).\(key)"); return }
                try preserves(old[key]!, actual, path: path + "." + key)
            }
        } else if let old = old as? [Any], let new = new as? [Any] {
            try expect(old.count == new.count, "Retain array length at \(path)")
            for (index, item) in old.enumerated() { try preserves(item, new[index], path: path + "[\(index)]") }
        } else {
            try expect((old as! NSObject).isEqual(new), "Retain old-writer value at \(path)")
        }
    }
    @MainActor static func main() async throws {
        guard CommandLine.arguments.count == 4 else { fatalError("mode root receipt required") }
        let mode = CommandLine.arguments[1]
        // Foundation maps the existing /private/tmp directory back to /tmp.
        // Canonicalize only existing parents with POSIX realpath, then append
        // permitted leaves. Do not canonicalize a not-yet-created archive.
        let requestedRoot = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let requestedOutput = URL(fileURLWithPath: CommandLine.arguments[3])
        let requestedParent = requestedRoot.deletingLastPathComponent()
        try requireLeaf(requestedParent, type: mode_t(S_IFDIR), mayBeAbsent: false)
        try requireLeaf(requestedOutput.deletingLastPathComponent(), type: mode_t(S_IFDIR), mayBeAbsent: false)
        let ownedPath = try canonicalExistingPath(requestedParent)
        let temporaryPath = try canonicalExistingPath(URL(fileURLWithPath: "/private/tmp", isDirectory: true))
        let receiptParent = try canonicalExistingPath(requestedOutput.deletingLastPathComponent())
        let receipts: [String: Set<String>] = ["write": ["old-write.json"], "upgrade": ["current-upgrade.json"],
            "reopen": ["current-reopen-1.json", "current-reopen-2.json"], "reject-downgrade": ["old-downgrade-rejection.json"]]
        try expect((ownedPath as NSString).deletingLastPathComponent == temporaryPath
            && (ownedPath as NSString).lastPathComponent.hasPrefix("DaBin-Upgrade-")
            && requestedRoot.lastPathComponent == (mode == "reject-downgrade" ? "Downgrade-probe" : "Archive")
            && receiptParent == ownedPath
            && receipts[mode]?.contains(requestedOutput.lastPathComponent) == true,
            "Use an owned synthetic temporary archive and receipt")
        try requireLeaf(requestedRoot, type: mode_t(S_IFDIR), mayBeAbsent: mode == "write")
        try requireLeaf(requestedOutput, type: mode_t(S_IFREG), mayBeAbsent: true)
        let ownedRoot = URL(fileURLWithPath: ownedPath, isDirectory: true)
        let root = ownedRoot.appendingPathComponent(requestedRoot.lastPathComponent, isDirectory: true)
        let output = ownedRoot.appendingPathComponent(requestedOutput.lastPathComponent)
        let attributes = try files.attributesOfItem(atPath: ownedPath)
        try expect((attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid()
            && (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700,
            "Owned fixture root is private to the current process user")
        let ownerURL = ownedRoot.appendingPathComponent("FixtureOwner.json")
        try requireLeaf(ownerURL, type: mode_t(S_IFREG), mayBeAbsent: false)
        let ownerData = try Data(contentsOf: ownerURL)
        try expect(ownerData.count < 4096, "Bound fixture-owner receipt")
        let owner = try JSONSerialization.jsonObject(with: ownerData) as! [String: String]
        let token = ProcessInfo.processInfo.environment["DABIN_UPGRADE_FIXTURE_TOKEN"]
        try expect(token != nil && owner["token"] == token, "Runner token identifies this exact synthetic root")
        let expectedURL = root.deletingLastPathComponent().appendingPathComponent("expected.json")
        #if OLD_BUILD
        if mode == "write" {
            let store = try CaptureStore(root: root)
            let at = instant("2026-09-21T22:12:34Z")
            let zone = TimeZone(secondsFromGMT: 10_800)!
            let note = try store.capture(text: "  Violet idea\r\nSecond line\tעברית 🟣\n\n", at: at, timeZone: zone,
                source: CaptureSource(filePath: "/Fictional/Studio notes.txt", url: "https://example.invalid/notes"), projectName: "Fictional Violet")[0]
            try store.setOrganization(note, pinned: true, projectName: "Fictional Violet")
            var planning = TaskPlanning()
            planning.plannedDay = "2099-01-02"; planning.plannedTime = "09:30"
            planning.priority = .high; planning.effortMinutes = 25; planning.recurrence = .weekly
            planning.deadline = instant("2099-01-03T12:00:00Z")
            planning.checklist = [TaskChecklistItem(text: "Review fictional palette"), TaskChecklistItem(text: "Keep original", isCompleted: true)]
            let task = try store.createTask(text: "Prepare fictional launch", reminderAt: instant("2099-01-02T10:00:00Z"),
                reminderTimeZoneID: "UTC", at: at, timeZone: zone, planning: planning, projectName: "Fictional Violet")
            try store.update(task, comment: "  Spruce legacy comment\nSecond aggregate line\n", reminderAt: task.reminderAt, reminderTimeZoneID: "UTC")
            try store.reorderTasks([task], on: "2099-01-02")
            let original = Data("Exact fictional file\r\nQuartz Ω\t\n".utf8)
            let source = root.deletingLastPathComponent().appendingPathComponent("fictional-original.txt")
            try original.write(to: source)
            let file = try await store.importFile(source, at: at, timeZone: zone, projectName: "Fictional Violet", parentTask: task)
            let automatic = try store.capture(text: "Fictional automatic receipt", at: at, timeZone: zone,
                receipt: .automatic(.automaticClipboard, sourceApplicationName: "Fixture Editor", sourceApplicationBundleIdentifier: "invalid.fixture.editor"))[0]
            let workspace = WorkspaceStore(root: root)
            try workspace.createProject(name: "Fictional Violet", colorHex: "34A853")
            try workspace.setScratchpad(text: "  Project scratchpad\nRetain spacing\t\n", project: "Fictional Violet")
            try workspace.setOnShelf([note.id, file.id], included: true)
            workspace.selectedProject = "Fictional Violet"; workspace.selectedCaptureID = note.id
            var workspaceValue = workspace.snapshot
            workspaceValue.projectItemOrders = [WorkspaceSnapshot.projectKey("Fictional Violet"): [ProjectWorkspaceIdentity.capture(task.id), ProjectWorkspaceIdentity.capture(note.id), ProjectWorkspaceIdentity.note(project: "Fictional Violet")]]
            try workspace.save(workspaceValue)
            var draft = DraftArchiveSnapshot()
            draft.note = "  Unsaved fictional note\n"; draft.noteDestination = ComposerDestination(projectName: "Fictional Violet")
            draft.task.text = "Unfinished fictional task"; draft.task.planning = planning
            draft.task.destination = ComposerDestination(projectName: "Fictional Violet")
            draft.details = [DetailDraftSnapshot(captureID: task.id, title: "Draft task title", comment: "Uncommitted comment", planning: planning,
                committedPlanning: task.taskPlanning, committedReminderRevision: task.reminderRevision, reminderEnabled: true,
                reminderMode: "date", countdownHours: 0, countdownMinutes: 30, reminderDate: instant("2099-01-02T10:00:00Z"))]
            try DraftArchive(root: root).save(draft)
            try store.save()
            let snapshots = try CaptureRepository(root: root).load()
            try expect(snapshots.count == 4 && snapshots.allSatisfy { $0.schemaVersion == 10 }, "Real old core writes schema 10 metadata")
            let expected: [String: Any] = ["captures": try snapshots.map { try json($0) }, "workspace": try json(workspace.snapshot),
                "draft": try json(draft), "fileID": file.id.uuidString, "originalSHA256": hash(original),
                "noteID": note.id.uuidString, "taskID": task.id.uuidString, "automaticID": automatic.id.uuidString]
            try write(expected, to: expectedURL)
            try write(["status": "passed", "checks": checks, "writer": "0.4.31 (86)", "snapshotSchema": 10, "captureCount": snapshots.count], to: output)
        } else if mode == "reject-downgrade" {
            // The repository initializer must succeed; only its schema validation may reject.
            let repository = try CaptureRepository(root: root)
            var reason: String?
            do { _ = try repository.load() } catch { reason = error.localizedDescription }
            try expect(reason?.contains("metadata schema or identity is unsupported") == true, "Old reader explicitly rejects schema 11")
            try write(["status": "passed", "checks": checks, "downgradeSupported": false, "reason": reason!], to: output)
        } else { fatalError("Unsupported old mode") }
        #else
        guard mode == "upgrade" || mode == "reopen" else { fatalError("Unsupported current mode") }
        let expected = try JSONSerialization.jsonObject(with: Data(contentsOf: expectedURL)) as! [String: Any]
        let before = try CaptureRepository(root: root).load()
        let schema = mode == "upgrade" ? 10 : 11
        try expect(before.allSatisfy { $0.schemaVersion == schema }, "Expected metadata schema before \(mode)")
        let store = try CaptureStore(root: root, repairArchiveOnOpen: false)
        let oldRecords = expected["captures"] as! [[String: Any]]
        try expect(store.captures.count == oldRecords.count && store.trashedCaptures.isEmpty, "Keep capture count without duplicate or missing records")
        for old in oldRecords {
            let capture = store.captures.first { $0.id.uuidString == old["id"] as? String }
            try expect(capture != nil, "Retain immutable capture UUID")
            try preserves(old, json(CaptureSnapshot(capture!)), path: "capture")
        }
        let file = store.captures.first { $0.id.uuidString == expected["fileID"] as? String }!
        let managed = store.managedURL(for: file)
        print("Fictional fixture original: archive=\(root.path), managed=\(managed?.path ?? "nil")")
        try expect(managed != nil, "Managed original remains resolvable after upgrade")
        try requireLeaf(managed!, type: mode_t(S_IFREG), mayBeAbsent: false)
        let canonicalArchive = try canonicalExistingPath(root)
        let canonicalManaged = try canonicalExistingPath(managed!)
        let archiveComponents = canonicalArchive.split(separator: "/")
        let originalComponents = canonicalManaged.split(separator: "/")
        print("Fictional fixture canonical original: archive=\(canonicalArchive), managed=\(canonicalManaged)")
        try expect(originalComponents.count > archiveComponents.count
            && Array(originalComponents.prefix(archiveComponents.count)) == archiveComponents,
            "Existing managed original remains inside the canonical owned archive")
        try expect(try hash(Data(contentsOf: URL(fileURLWithPath: canonicalManaged))) == expected["originalSHA256"] as? String,
            "Original file bytes retain exact SHA256")
        let workspace = WorkspaceStore(root: root)
        try expect(workspace.error == nil, "Workspace remains readable")
        try preserves(expected["workspace"]!, json(workspace.snapshot), path: "workspace")
        let archive = DraftArchive(root: root)
        let draft = archive.load()
        try expect(draft != nil && archive.recoveryError == nil, "Old draft remains recoverable")
        try preserves(expected["draft"]!, json(draft!), path: "draft")
        let task = store.captures.first { $0.id.uuidString == expected["taskID"] as? String }!
        try expect(task.commentThread.count == 1 && task.commentThread[0].text == task.comment, "Legacy aggregate comment becomes one preserved thread entry")
        try expect(task.reminderAcknowledgment == nil && draft!.task.pendingChecklistText == nil, "Missing additive fields retain their defaults")
        let results = CaptureSearch.groups(captures: store.captures, query: "spruce", filter: .all, includeContext: false).flatMap(\.entries)
        try expect(results.map(\.id) == [task.id], "Local search finds preserved aggregate comment")
        if mode == "upgrade" {
            try store.save()
            try workspace.save(workspace.snapshot)
            try archive.save(draft!)
            let after = try CaptureRepository(root: root).load()
            try expect(after.count == oldRecords.count && after.allSatisfy { $0.schemaVersion == 11 }, "Current save writes schema 11 with every old identity")
        }
        let readerIdentity = ProcessInfo.processInfo.environment["DABIN_UPGRADE_CURRENT_IDENTITY"]
        try expect(readerIdentity != nil, "Record the runner-pinned current reader identity")
        try write(["status": "passed", "checks": checks, "reader": readerIdentity!, "mode": mode,
            "captureCount": store.captures.count, "snapshotSchema": 11, "originalSHA256": expected["originalSHA256"]!], to: output)
        #endif
    }
}
