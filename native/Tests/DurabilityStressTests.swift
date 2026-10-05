import Foundation
import CryptoKit
import Darwin

/// All archives, originals and killed subprocesses belong to one marked
/// temporary fixture. This suite never opens the default store or a GUI.
@main @MainActor struct DurabilityStressTests {
    private static let files = FileManager.default
    private static let seed: UInt64 = 0xDA_B1_2026_1005
    private static var checks = 0
    private static var timings: [String: Double] = [:]
    private static var counts: [String: Int] = [:]
    private static var boundaries: [[String: String]] = []

    private struct Generator {
        var value: UInt64
        mutating func next(_ bound: Int) -> Int {
            value = value &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((value >> 32) % UInt64(bound))
        }
    }
    private struct Receipt: Equatable {
        let id: UUID
        let capturedAt: Date
        let day: String
        let zone: String
        let offset: Int
        let kind: String
        let text: String?
        let url: String?
        let filename: String?
        let bytes: Int64?
        let origin: String
        let actionID: UUID?
        let sourceFile: String?
        let sourceURL: String?
        init(_ capture: Capture) {
            id = capture.id; capturedAt = capture.capturedAt; day = capture.captureDay
            zone = capture.captureTimeZoneID; offset = capture.captureUTCOffsetSeconds
            kind = capture.kindRaw; text = capture.originalText; url = capture.originalURL
            filename = capture.originalFilename; bytes = capture.byteCount
            origin = capture.captureOriginRaw; actionID = capture.automaticActionID
            sourceFile = capture.sourceFilePath; sourceURL = capture.sourceURL
        }
    }
    private static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        if try !value() { throw NSError(domain: "DurabilityStressTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    private static func rejected(_ action: () throws -> Void, _ message: String) throws {
        var failed = false
        do { try action() } catch { failed = true }
        try expect(failed, message)
    }
    private static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    private static func snapshots(_ store: CaptureStore) throws -> [UUID: Data] {
        try Dictionary(uniqueKeysWithValues: (store.captures + store.trashedCaptures).map {
            ($0.id, try encoded(CaptureSnapshot($0)))
        })
    }
    private static func durableSnapshots(_ root: URL) throws -> [UUID: Data] {
        try Dictionary(uniqueKeysWithValues: CaptureRepository(root: root).load().map { ($0.id, try encoded($0)) })
    }
    private static func digest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    private static func identifier(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012llx", UInt64(index + 1)))!
    }
    private static func write(_ data: Data, to url: URL) throws {
        try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
    private static func fixtureBytes(_ index: Int) -> Data {
        Data((0..<8_192).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ index) })
    }

    static func main() async throws {
        if CommandLine.arguments.dropFirst().first == "--durability-child" {
            try await child()
            throw NSError(domain: "DurabilityStressTests", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "The guarded child did not reach its kill boundary"])
        }
        let started = Date()
        let token = UUID().uuidString
        let root = files.temporaryDirectory.appendingPathComponent("DaBinDurabilityStress-" + token).standardizedFileURL
        try files.createDirectory(at: root, withIntermediateDirectories: false)
        try write(Data(token.utf8), to: root.appendingPathComponent(".durability-owner"))
        defer { try? files.removeItem(at: root) }
        try await mixedOperations(root)
        try await interruptedRecovery(root)
        try await processKillRecovery(root, token: token)
        timings["totalSeconds"] = Date().timeIntervalSince(started)
        let report: [String: Any] = ["status": "passed", "seed": String(seed), "checks": checks,
            "counts": counts, "seconds": timings, "processBoundaries": boundaries,
            "scope": "Synthetic temporary archives; no GUI, real archive, network, clipboard or notifications"]
        let evidence = URL(fileURLWithPath: files.currentDirectoryPath).deletingLastPathComponent()
            .appendingPathComponent("docs/qa/full-certification-2026-10-05/durability-stress-report.json")
        try write(JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), to: evidence)
        print("PASS: \(checks) durability checks; 1000 seeded records, 320 mixed operations, \(counts["restarts", default: 0]) restart comparisons, backup/restore and 4 real SIGKILL boundaries.")
        print(String(format: "DURABILITY measured wall time %.3f seconds; no timing threshold asserted", timings["totalSeconds"]!))
    }

    private static func mixedOperations(_ fixture: URL) async throws {
        let started = Date()
        let root = fixture.appendingPathComponent("scale")
        try files.createDirectory(at: root, withIntermediateDirectories: false)
        let base = Date(timeIntervalSince1970: 1_790_000_000)
        let zones = [TimeZone(secondsFromGMT: 0)!, TimeZone(secondsFromGMT: 10_800)!, TimeZone(secondsFromGMT: -28_800)!]
        let seeded = (0..<1_000).map { index -> Capture in
            let kind: CaptureKind = index % 5 == 0 ? .task : index % 5 == 2 ? .link : .text
            let text = kind == .link ? "https://example.invalid/fixture/\(index)" : "  Synthetic receipt \(index)\nעברית · العربية · 日本語 · 🦉\n"
            let receipt: CaptureReceiptContext = index % 5 == 3
                ? .automatic(.automaticClipboard, actionID: identifier(10_000 + index), sourceApplicationName: "Fixture Editor") : .manual
            let capture = Capture(id: identifier(index), capturedAt: base.addingTimeInterval(Double(index * 71)),
                timeZone: zones[index % zones.count], kind: kind, originalURL: kind == .link ? text : nil,
                originalText: text, title: "Fixture \(index)", receipt: receipt,
                parentTaskID: index % 5 == 1 ? identifier(index - 1) : nil)
            capture.projectName = "Project \((index / 5) % 8)"
            if kind == .task { capture.setTaskPlanning(TaskPlanning(plannedDay: capture.captureDay, effortMinutes: 25)) }
            if kind != .link { capture.previewState = "ready" }
            return capture
        }
        try CaptureRepository(root: root).save(seeded)
        var store: CaptureStore? = try CaptureStore(root: root, repairArchiveOnOpen: false)
        var originalHashes: [UUID: String] = [:]
        var sources: [URL: Data] = [:]
        for index in 0..<8 {
            let bytes = fixtureBytes(index)
            let source = fixture.appendingPathComponent("Sources/original-\(index).bin")
            try write(bytes, to: source); sources[source] = bytes
            let capture = try await store!.importFile(source, at: base.addingTimeInterval(Double(100_000 + index)), projectName: "Project \(index)")
            originalHashes[capture.id] = digest(bytes)
        }
        var workspace = WorkspaceStore(root: root)
        for index in 0..<8 { try workspace.createProject(name: "Project \(index)", colorHex: "7568D8") }
        let receipts = Dictionary(uniqueKeysWithValues: (store!.captures + store!.trashedCaptures).map { ($0.id, Receipt($0)) })
        var expected = try snapshots(store!)
        let baselineCount = expected.count
        try expect(baselineCount == 1_008 && expected == durableSnapshots(root), "The complete mixed seed and eight originals are committed before stress")
        var generator = Generator(value: seed)
        var operations: [String: Int] = [:]
        for operation in 0..<320 {
            let candidates = store!.captures.filter { $0.parentTaskID == nil && $0.id.uuidString.hasPrefix("00000000-") }.sorted { $0.id.uuidString < $1.id.uuidString }
            let capture = candidates[generator.next(candidates.count)]
            let choice = generator.next(8)
            operations[String(choice), default: 0] += 1
            switch choice {
            case 0:
                try store!.setOrganization(capture, pinned: !capture.isPinned, projectName: "Project \(generator.next(8))")
            case 1:
                let target = !capture.isMinimized
                try store!.setMinimized(capture, minimized: target)
                try expect(capture.isMinimized == target, "Minimize keeps its explicit requested value")
            case 2:
                let tasks = candidates.filter(\.isTask)
                let task = tasks[generator.next(tasks.count)]
                let completed = !task.isCompleted
                let successor = try store!.setTaskCompleted(task, completed: completed, at: base.addingTimeInterval(Double(200_000 + operation)))
                try expect(task.isCompleted == completed && successor == nil, "Completion changes only the requested nonrecurring task")
            case 3:
                let text = "Reply \(operation): exact\nעברית 🦉"
                _ = try store!.appendComment(capture, text: text, at: base.addingTimeInterval(Double(300_000 + operation)))
                try expect(capture.commentThread.last?.text == text, "Posted comments retain their exact Unicode and line breaks")
            case 4:
                try store!.convertToTask(capture)
                var planning = capture.taskPlanning ?? TaskPlanning()
                planning.priority = TaskPriority.allCases[generator.next(TaskPriority.allCases.count)]
                planning.effortMinutes = 1 + generator.next(240)
                try store!.setTaskPlanning(capture, planning: planning)
                try expect(capture.isTask && capture.taskPlanning?.effortMinutes == planning.effortMinutes, "Conversion and planning retain the requested effort")
            case 5:
                let family = Set(store!.captureFamily(for: capture).map(\.id))
                try store!.moveToTrash(capture)
                try expect(family.isDisjoint(with: Set(store!.captures.map(\.id))) && family.isSubset(of: Set(store!.trashedCaptures.map(\.id))),
                    "Task trash moves the entire family atomically")
            case 6:
                if let retained = store!.trashedCaptures.filter({ $0.parentTaskID == nil }).sorted(by: { $0.id.uuidString < $1.id.uuidString }).first {
                    try store!.restoreFromTrash(retained)
                    try expect(store!.captures.contains { $0.id == retained.id }, "Restoring retains the selected capture identity")
                }
            default:
                try workspace.setOnShelf([capture.id], included: true)
                try workspace.markInboxProcessed([capture.id])
                try workspace.setSnippetName("Reusable \(operation)", for: capture.id)
                try expect(workspace.shelfCaptureIDs.contains(capture.id) && workspace.processedInboxIDs.contains(capture.id), "Organization references the existing receipt")
            }
            expected = try snapshots(store!)
            if operation % 17 == 0 {
                let target = store!.captures.first { $0.parentTaskID == nil }!
                let before = try encoded(CaptureSnapshot(target))
                store!.failureInjector = { if $0 == .beforeMetadataSave { throw CaptureStoreError.importVerificationFailed } }
                try rejected({ try store!.setOrganization(target, pinned: !target.isPinned, projectName: "Rejected fixture move") }, "Injected metadata failure is reported")
                store!.failureInjector = nil
                try expect(try encoded(CaptureSnapshot(target)) == before && durableSnapshots(root) == expected, "A failed mutation rolls back both live and durable metadata")
                counts["failedMutations", default: 0] += 1
            }
            if (operation + 1) % 40 == 0 {
                try workspace.setScratchpad(text: "Exact notes at operation \(operation)\nעברית 🦉", project: "Project \(operation % 8)")
                let expectedWorkspace = workspace.snapshot
                var recovery = DraftArchiveSnapshot()
                recovery.note = "Unsubmitted note \(operation)"
                recovery.noteDestination = ComposerDestination(projectName: "Project 2")
                recovery.task.text = "Unsaved task \(operation)"; recovery.task.pendingChecklistText = "Unsubmitted next step"
                let owner = store!.captures.first { $0.isTask && $0.parentTaskID == nil }!
                recovery.details = [DetailDraftSnapshot(captureID: owner.id, title: String(repeating: "x", count: 2_001),
                    comment: "Unsubmitted legacy annotation", planning: owner.taskPlanning ?? TaskPlanning(),
                    reminderEnabled: false, reminderMode: "date", countdownHours: 0, countdownMinutes: 30,
                    reminderDate: base, commentComposer: "Pending reply \(operation)", pendingChecklistText: String(repeating: "z", count: 501))]
                try DraftArchive(root: root).save(recovery)
                store!.cancelArchiveRepair(); store = nil
                store = try CaptureStore(root: root, repairArchiveOnOpen: false)
                workspace = WorkspaceStore(root: root)
                try expect(store!.captures.count + store!.trashedCaptures.count == baselineCount && snapshots(store!) == expected
                    && durableSnapshots(root) == expected, "Restart retains every exact active and trashed snapshot")
                try expect(workspace.snapshot == expectedWorkspace && workspace.error == nil, "Workspace notes and references survive every restart")
                let recovered = DraftArchive(root: root).load()
                try expect(try recovered.map(encoded) == encoded(recovery), "Recovery preserves invalid uncommitted text, destination, pending reply and checklist")
                for item in store!.captures + store!.trashedCaptures { try expect(receipts[item.id] == Receipt(item), "Editing and restart preserve immutable original content, kind and receipt") }
                for (id, hash) in originalHashes {
                    let item = (store!.captures + store!.trashedCaptures).first { $0.id == id }!
                    try expect(try store!.managedURL(for: item).map { digest(try Data(contentsOf: $0)) } == hash, "Restart retains the exact managed original bytes")
                }
                for (source, bytes) in sources { try expect(try Data(contentsOf: source) == bytes, "No organization or restart changes a source file") }
                counts["restarts", default: 0] += 1
            }
        }
        counts["seededRecords"] = 1_000; counts["originalFiles"] = originalHashes.count; counts["mixedOperations"] = 320
        for (kind, total) in operations { counts["operationKind" + kind] = total }
        try workspaceFailureAndRetry(workspace, root: root)
        try batchRollback(store!, expected: expected)
        let backupStarted = Date()
        let editedID = originalHashes.keys.sorted { $0.uuidString < $1.uuidString }[0]
        let editedCapture = store!.captures.first { $0.id == editedID }!
        let editedText = Data("External readable note must survive the backup refresh\nעברית 🦉".utf8)
        try editedText.write(to: store!.archiveURL(for: editedCapture)!.appendingPathComponent("Capture.md"))
        let backup = fixture.appendingPathComponent("Scale.dabinbackup")
        try store!.exportBackup(to: backup)
        let manifestBytes = try Data(contentsOf: backup.appendingPathComponent("Manifest.json"))
        try rejected({ try store!.exportBackup(to: backup) }, "Backup export refuses to replace the existing complete package")
        try expect(try Data(contentsOf: backup.appendingPathComponent("Manifest.json")) == manifestBytes, "Rejected replacement leaves the backup manifest unchanged")
        let targetRoot = fixture.appendingPathComponent("restored-scale")
        var target: CaptureStore? = try CaptureStore(root: targetRoot, repairArchiveOnOpen: false)
        let result = try target!.restoreBackup(from: backup)
        try expect(result.addedCount == baselineCount && result.existingCount == 0 && snapshots(target!) == expected,
            "A full thousand-record portable backup restores exact active and trashed metadata")
        let restoredWorkspace = WorkspaceStore(root: targetRoot)
        for (key, note) in workspace.snapshot.scratchpads { try expect(restoredWorkspace.snapshot.scratchpads[key] == note, "Portable backup preserves every authored workspace note") }
        try expect(restoredWorkspace.shelfCaptureIDs == workspace.shelfCaptureIDs && restoredWorkspace.processedInboxIDs == workspace.processedInboxIDs
            && restoredWorkspace.snapshot.snippetNames == workspace.snapshot.snippetNames, "Portable backup preserves shelf, Inbox processing and reusable names")
        let repeated = try target!.restoreBackup(from: backup)
        try expect(repeated.addedCount == 0 && repeated.existingCount == baselineCount && snapshots(target!) == expected, "Repeating the identical restore is idempotent")
        target!.cancelArchiveRepair(); target = nil
        target = try CaptureStore(root: targetRoot, repairArchiveOnOpen: false)
        try expect(try snapshots(target!) == expected, "The full restored archive survives another process-style reopen")
        for (id, hash) in originalHashes {
            let item = (target!.captures + target!.trashedCaptures).first { $0.id == id }!
            try expect(try target!.managedURL(for: item).map { digest(try Data(contentsOf: $0)) } == hash, "Portable backup restores byte-identical originals")
        }
        let restoredEdited = target!.captures.first { $0.id == editedID }!
        let edits = target!.archiveURL(for: restoredEdited)!.appendingPathComponent("Local edits")
        let recoveredEdits = try files.contentsOfDirectory(at: edits, includingPropertiesForKeys: nil)
        try expect(try recoveredEdits.contains { try Data(contentsOf: $0) == editedText }, "Portable backup retains the exact external readable-file edit in recovery copies")
        counts["backupRecords"] = result.addedCount; counts["restarts", default: 0] += 1
        timings["backupRestoreSeconds"] = Date().timeIntervalSince(backupStarted)
        timings["mixedStressSeconds"] = Date().timeIntervalSince(started)
    }

    private static func workspaceFailureAndRetry(_ workspace: WorkspaceStore, root: URL) throws {
        let before = workspace.snapshot
        let durable = try Data(contentsOf: root.appendingPathComponent(WorkspaceStore.filename))
        let exact = "Pending workspace text survives a failed write\nעברית 🦉"
        workspace.failureInjector = { throw CaptureStoreError.injectedInterruption }
        try rejected({ try workspace.setScratchpad(text: exact, project: "Project 3") }, "Workspace failures report the rejected write")
        try expect(workspace.snapshot == before && workspace.scratchpad(project: "Project 3") == exact && workspace.hasUnsavedChanges
            && Data(contentsOf: root.appendingPathComponent(WorkspaceStore.filename)) == durable, "A failed workspace write retains pending text without replacing the durable snapshot")
        workspace.failureInjector = nil
        try workspace.setScratchpad(text: exact, project: "Project 3")
        try expect(!workspace.hasUnsavedChanges && WorkspaceStore(root: root).scratchpad(project: "Project 3") == exact, "Retry durably stores the exact pending workspace text")
        counts["workspaceWriteRetries"] = 1
    }

    private static func batchRollback(_ store: CaptureStore, expected: [UUID: Data]) throws {
        let first = store.captures[0], second = store.captures[1]
        let title = first.title, updated = second.updatedAt
        first.title = "Earlier candidate must roll back when a later record fails"
        second.updatedAt = Date(timeIntervalSinceReferenceDate: .infinity)
        try rejected({ try store.save(captures: [first, second]) }, "An unencodable later record rejects the entire metadata batch")
        first.title = title; second.updatedAt = updated
        try expect(try durableSnapshots(store.root) == expected, "A failed multi-record transaction cannot partially replace any durable record")
        counts["repositoryBatchRollbacks"] = 1
    }

    private static func interruptedRecovery(_ fixture: URL) async throws {
        let started = Date()
        for point in [ImportCheckpoint.afterCopy, .afterMove, .afterMetadataSave] {
            let root = fixture.appendingPathComponent("import-" + point.rawValue)
            var store: CaptureStore? = try CaptureStore(root: root)
            let bytes = fixtureBytes(40)
            store!.failureInjector = { if $0 == point { throw CaptureStoreError.injectedInterruption } }
            var interrupted = false
            do { _ = try await store!.importData(bytes, filename: "recover.bin") }
            catch CaptureStoreError.injectedInterruption { interrupted = true }
            try expect(interrupted, "The import interruption reaches the requested checkpoint")
            store = nil; store = try CaptureStore(root: root)
            try expect(store!.captures.count == 1 && store!.error == nil
                && Data(contentsOf: store!.managedURL(for: store!.captures[0])!) == bytes,
                "Verified interrupted import completes once with exact bytes")
            try expect(try files.contentsOfDirectory(atPath: root.appendingPathComponent("Imports").path).isEmpty, "Import recovery clears its completed journal")
            let committed = try snapshots(store!)
            store = nil; store = try CaptureStore(root: root)
            try expect(try snapshots(store!) == committed, "Repeated import recovery cannot duplicate the saved receipt")
            counts["importInterruptionChecks", default: 0] += 1
            counts["restarts", default: 0] += 2
        }
        let backupSource = fixture.appendingPathComponent("restore-source")
        let source = try CaptureStore(root: backupSource)
        _ = try await source.importData(fixtureBytes(50), filename: "backup.bin")
        let sourceWorkspace = WorkspaceStore(root: backupSource)
        try sourceWorkspace.setScratchpad(text: "Authored backup note", project: "Restored Project")
        let backup = fixture.appendingPathComponent("Rollback.dabinbackup")
        try source.exportBackup(to: backup)
        for (index, point) in [ArchiveRestoreCheckpoint.afterFileCopy, .beforeMetadataSave].enumerated() {
            let root = fixture.appendingPathComponent("restore-failure-\(index)")
            let target = try CaptureStore(root: root)
            let keeper = try target.capture(text: "Retain the unrelated receipt")[0]
            let workspace = WorkspaceStore(root: root)
            try workspace.setScratchpad(text: "Unrelated destination text", project: "Existing Project")
            let before = try snapshots(target), priorWorkspace = workspace.snapshot
            target.backupFailureInjector = { if $0 == point { throw CaptureStoreError.importVerificationFailed } }
            try rejected({ _ = try target.restoreBackup(from: backup) }, "Backup restore failure is reported at its transaction checkpoint")
            let reopened = try CaptureStore(root: root)
            try expect(try snapshots(reopened) == before && reopened.captures[0].id == keeper.id
                && WorkspaceStore(root: root).snapshot == priorWorkspace, "Failed restore retains all existing metadata and rolls back the installed workspace")
            counts["restoreRollbackChecks", default: 0] += 1
            counts["restarts", default: 0] += 1
        }
        timings["injectedRecoverySeconds"] = Date().timeIntervalSince(started)
    }

    private static func validateOwner(_ root: URL, token: String) throws {
        let temporary = files.temporaryDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let checked = root.standardizedFileURL.resolvingSymlinksInPath()
        let rootAttributes = try files.attributesOfItem(atPath: root.path)
        let markerAttributes = try files.attributesOfItem(atPath: checked.appendingPathComponent(".durability-owner").path)
        guard UUID(uuidString: token) != nil, checked.deletingLastPathComponent() == temporary,
              checked.lastPathComponent == "DaBinDurabilityStress-" + token,
              rootAttributes[.type] as? FileAttributeType == .typeDirectory,
              markerAttributes[.type] as? FileAttributeType == .typeRegular,
              try String(contentsOf: checked.appendingPathComponent(".durability-owner"), encoding: .utf8) == token else {
            throw NSError(domain: "DurabilityStressTests", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Refusing an unowned subprocess fixture path"])
        }
    }

    private static func child() async throws {
        guard CommandLine.arguments.count == 5 else { throw CaptureStoreError.invalidManagedPath }
        let mode = CommandLine.arguments[2], root = URL(fileURLWithPath: CommandLine.arguments[3])
        try validateOwner(root, token: CommandLine.arguments[4])
        guard ["import-moved", "import-committed", "delete-precommit", "delete-committed"].contains(mode) else { throw CaptureStoreError.invalidManagedPath }
        let store = try CaptureStore(root: root.appendingPathComponent("kill-" + mode), repairArchiveOnOpen: false)
        func killAtCheckpoint() throws {
            try write(Data(mode.utf8), to: root.appendingPathComponent("checkpoint-" + mode))
            // No parent PID or arbitrary process identifier is accepted.
            guard Darwin.kill(Darwin.getpid(), SIGKILL) == 0 else { throw CaptureStoreError.injectedInterruption }
            _exit(99)
        }
        if mode.hasPrefix("import-") {
            let point: ImportCheckpoint = mode == "import-moved" ? .afterMove : .afterMetadataSave
            store.failureInjector = { if $0 == point { try killAtCheckpoint() } }
            _ = try await store.importFile(root.appendingPathComponent("Sources/kill-original.bin"))
        } else {
            let point: RemovalCheckpoint = mode == "delete-precommit" ? .beforeMetadataDelete : .afterMetadataDelete
            store.removalFailureInjector = { if $0 == point { try killAtCheckpoint() } }
            guard let victim = store.captures.first(where: { $0.originalFilename == "victim.bin" }) else { throw CaptureStoreError.invalidOriginal("Missing owned child victim") }
            _ = try store.remove(victim)
        }
    }

    private nonisolated static func waitForTermination(_ semaphore: DispatchSemaphore, seconds: Double) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: semaphore.wait(timeout: .now() + seconds) == .success)
            }
        }
    }

    private static func processKillRecovery(_ root: URL, token: String) async throws {
        let started = Date()
        try validateOwner(root, token: token)
        let source = root.appendingPathComponent("Sources/kill-original.bin"), bytes = fixtureBytes(60)
        try write(bytes, to: source)
        for mode in ["import-moved", "import-committed", "delete-precommit", "delete-committed"] {
            let childRoot = root.appendingPathComponent("kill-" + mode)
            var initial: CaptureStore? = try CaptureStore(root: childRoot)
            let sentinel = try initial!.capture(text: "Unrelated committed sentinel")[0]
            let sentinelSnapshot = try encoded(CaptureSnapshot(sentinel))
            var victimID: UUID?
            if mode.hasPrefix("delete-") { victimID = try await initial!.importData(bytes, filename: "victim.bin").id }
            initial = nil
            let process = Process(), terminated = DispatchSemaphore(value: 0), errorPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
            process.arguments = ["--durability-child", mode, root.path, token]
            process.standardOutput = FileHandle.nullDevice; process.standardError = errorPipe
            process.terminationHandler = { _ in terminated.signal() }
            try process.run(); try errorPipe.fileHandleForWriting.close()
            if !(await waitForTermination(terminated, seconds: 25)) {
                // The Process handle proves ownership of this one child.
                if process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
                _ = await waitForTermination(terminated, seconds: 5)
                throw NSError(domain: "DurabilityStressTests", code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Owned child timed out before " + mode])
            }
            let diagnostic = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            try expect(process.terminationReason == .uncaughtSignal && process.terminationStatus == SIGKILL,
                "Owned child must terminate by real SIGKILL at \(mode), received \(process.terminationStatus): \(diagnostic.prefix(1_000))")
            try expect(try String(contentsOf: root.appendingPathComponent("checkpoint-" + mode), encoding: .utf8) == mode,
                "The child reached its exact named production checkpoint before being killed")
            var recovered: CaptureStore? = try CaptureStore(root: childRoot)
            try expect(try recovered!.captures.first { $0.id == sentinel.id }.map { try encoded(CaptureSnapshot($0)) } == sentinelSnapshot,
                "Real process termination never changes the unrelated committed receipt")
            if mode.hasPrefix("import-") {
                let imported = recovered!.captures.filter { $0.originalFilename == "kill-original.bin" }
                try expect(imported.count == 1 && recovered!.captures.count == 2
                    && Data(contentsOf: recovered!.managedURL(for: imported[0])!) == bytes,
                    "Real killed import recovers exactly one receipt and its original bytes")
            } else {
                let shouldRemain = mode == "delete-precommit"
                try expect(recovered!.captures.contains { $0.id == victimID } == shouldRemain,
                    "Real killed deletion follows the metadata commit boundary")
                if shouldRemain {
                    let victim = recovered!.captures.first { $0.id == victimID }!
                    try expect(try Data(contentsOf: recovered!.managedURL(for: victim)!) == bytes, "A precommit kill retains the complete victim original")
                }
            }
            try expect(try files.contentsOfDirectory(atPath: childRoot.appendingPathComponent("Imports").path).isEmpty
                && files.contentsOfDirectory(atPath: childRoot.appendingPathComponent("Deletions").path).isEmpty,
                "Real crash recovery completes all owned import and deletion journals")
            let after = try snapshots(recovered!)
            recovered = nil; recovered = try CaptureStore(root: childRoot)
            try expect(try snapshots(recovered!) == after && Data(contentsOf: source) == bytes,
                "A second crash-recovery reopen is idempotent and preserves the source file")
            boundaries.append(["mode": mode, "termination": "SIGKILL", "checkpoint": "reached", "recovery": "passed"])
            counts["processKillBoundaries", default: 0] += 1
            counts["restarts", default: 0] += 2
        }
        timings["processKillRecoverySeconds"] = Date().timeIntervalSince(started)
    }
}
