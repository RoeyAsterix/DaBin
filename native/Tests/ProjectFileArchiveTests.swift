import Foundation

/// Disposable fixtures only. Never opens the installed DaBin archive.
@main struct ProjectFileArchiveTests {
    @MainActor static var checks = 0
    static let files = FileManager.default
    static func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    @MainActor static func expect(_ value: @autoclosure () throws -> Bool, _ reason: String) throws {
        checks += 1
        if try !value() { throw NSError(domain: "ProjectFileArchiveTests", code: 1, userInfo: [NSLocalizedDescriptionKey: reason]) }
    }
    @MainActor static func rejects(_ body: () throws -> Void, _ reason: String) throws {
        var failed = false
        do { try body() } catch { failed = true }
        try expect(failed, reason)
    }
    static func text(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }
    static func bytes(_ url: URL) throws -> Data { try Data(contentsOf: url) }
    @MainActor static func recoveredEdits(_ store: CaptureStore) -> [URL] {
        let names = (files.enumerator(atPath: store.archiveRoot.path)?.allObjects as? [String]) ?? []
        return names.filter { $0.contains("/Local edits/Explorer/") && $0.hasSuffix(".md") }
            .map { store.archiveRoot.appendingPathComponent($0) }
    }

    @MainActor static func main() async throws {
        let root = files.temporaryDirectory.appendingPathComponent("DaBinProjectFileArchive-\(UUID())")
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }
        try paths(root.appendingPathComponent("Paths"))
        try await liveLifecycle(root.appendingPathComponent("Live"), scratch: root)
        try moves(root.appendingPathComponent("Moves"))
        try blockedMove(root.appendingPathComponent("Blocked"))
        print("PASS: \(checks) project file layout, daily records, move recovery, file ownership, trash, and backup checks")
    }

    @MainActor static func paths(_ root: URL) throws {
        let id = UUID()
        let archive = ProjectFileArchive(root: root)
        let relative = try ProjectFileArchive.originalRelativePath(id: id, project: "Northstar", day: "2026-09-30", kind: .pdf, filename: "Proposal.pdf")
        try expect(relative.contains("Projects/Northstar — ") && relative.contains("/2026/09 September/30 Wednesday September 2026/Files/Proposal — \(id).pdf"), "Physical hierarchy is project/year/month/day/type with readable original name")
        try expect(ProjectFileArchive.projectRelativePath("Client") != ProjectFileArchive.projectRelativePath("client"), "Case-only projects have stable distinct names on case-insensitive disks")
        try expect(ProjectFileArchive.projectRelativePath("é") != ProjectFileArchive.projectRelativePath("e\u{301}"), "Unicode-normalization project collisions are separated")
        try expect(ProjectFileArchive.projectRelativePath("../a:b/c") != ProjectFileArchive.projectRelativePath(".._a_b_c"), "Sanitized project name collisions remain distinct")
        try expect(!ProjectFileArchive.projectRelativePath("../../Escape").contains("../"), "Project labels cannot traverse folders")
        let longProject = String(repeating: "日本語", count: 40)
        let longName = String(repeating: "資料", count: 60) + ".pdf"
        let multilingual = try ProjectFileArchive.originalRelativePath(id: id, project: longProject,
            day: "2026-09-30", kind: .pdf, filename: longName)
        try expect(multilingual.split(separator: "/").allSatisfy { $0.utf8.count <= 255 }, "Long multilingual project and file names fit macOS component byte limits")
        try expect(multilingual.hasSuffix("\(id).pdf") && ProjectFileArchive.ownsOriginal(multilingual, id: id,
            day: "2026-09-30", kind: .pdf, filename: longName), "Byte-limited Unicode paths retain extension and verifiable capture identity")
        let safeArchive = DailyArchive(root: root)
        _ = try safeArchive.ensureDirectory((multilingual as NSString).deletingLastPathComponent)
        let multilingualURL = try safeArchive.safeURL(multilingual)
        try Data("Multilingual filename fixture".utf8).write(to: multilingualURL)
        try expect(try text(multilingualURL) == "Multilingual filename fixture", "Long multilingual names create real readable files without truncating original metadata")
        try expect(ProjectFileArchive.ownsOriginal(relative, id: id, day: "2026-09-30", kind: .pdf, filename: "Proposal.pdf"), "A generated path proves receipt ownership")
        try expect(!ProjectFileArchive.ownsOriginal(relative, id: UUID(), day: "2026-09-30", kind: .pdf, filename: "Proposal.pdf"), "A different capture cannot claim a neighboring file")
        try expect(!ProjectFileArchive.ownsOriginal(relative, id: id, day: "2026-09-29", kind: .pdf, filename: "Proposal.pdf"), "Receipt date is part of file ownership")
        try expect(!ProjectFileArchive.ownsOriginal(relative, id: id, day: "2026-09-30", kind: .image, filename: "Proposal.pdf"), "File type directory is validated")
        try rejects({ _ = try archive.dayURL(project: nil, day: "../../unsafe") }, "Invalid day rejected")
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        try files.removeItem(at: root.appendingPathComponent("Projects"))
        let outside = root.deletingLastPathComponent().appendingPathComponent("Outside")
        try files.createDirectory(at: outside, withIntermediateDirectories: true)
        try files.createSymbolicLink(at: root.appendingPathComponent("Projects"), withDestinationURL: outside)
        try rejects({ _ = try archive.folderURL(project: "Northstar") }, "A symbolic project root is never followed")
        try expect(try files.contentsOfDirectory(atPath: outside.path).isEmpty, "Path rejection writes nothing outside the archive")
    }

    @MainActor static func liveLifecycle(_ root: URL, scratch: URL) async throws {
        let store = try CaptureStore(root: root)
        let morning = date("2026-09-30T08:00:00Z")
        let zone = TimeZone(secondsFromGMT: 0)!
        let note = try store.capture(text: "  Client feedback\nKeep the original wording.\n", at: morning, timeZone: zone)[0]
        try store.setOrganization(note, pinned: true, projectName: "Northstar")
        let noteDay = try store.explorerDayURL(project: "Northstar", day: note.captureDay)
        try expect(try text(noteDay).contains(note.originalText!), "Daily document preserves exact multiline capture text")
        try expect(!files.fileExists(atPath: try store.explorerDayURL(project: nil, day: note.captureDay).path), "Moving the last capture removes its empty former daily document")
        let link = try store.capture(text: "https://example.invalid/project", at: morning.addingTimeInterval(3_600), timeZone: zone)[0]
        try store.setOrganization(link, pinned: false, projectName: "Northstar")
        let source = scratch.appendingPathComponent("original-proposal.pdf")
        let payload = Data("Synthetic PDF bytes unchanged".utf8)
        try payload.write(to: source)
        let file = try await store.importFile(source, at: morning.addingTimeInterval(60), timeZone: zone, originalName: "Proposal.pdf")
        try store.setOrganization(file, pinned: false, projectName: "Northstar")
        let managed = store.managedURL(for: file)!
        try expect(try bytes(managed) == payload && bytes(source) == payload, "Project migration retains managed bytes and never changes the outside source")
        try expect(managed.path.contains("/Files/Proposal — ") && managed.path.contains(file.id.uuidString), "Files are placed in the physical project/day/type folder")
        try expect(store.explorerFileURL(for: file) == managed, "Explorer and normal copy/open use the same managed file")
        let image = try await store.importData(Data([1, 2, 3]), filename: "Photo.png", at: morning.addingTimeInterval(90), timeZone: zone)
        try expect(store.managedURL(for: image)!.path.contains("/Media/"), "Images use Media even without a preview")
        try store.convertToTask(note)
        try store.attachCapture(file, to: note)
        try store.update(note, comment: "Ask the client about delivery.", reminderAt: date("2099-10-01T14:00:00Z"), reminderTimeZoneID: "UTC",
            planning: TaskPlanning(plannedDay: "2026-10-02", deadline: date("2099-10-02T00:00:00Z"), priority: .high,
                checklist: [TaskChecklistItem(text: "Reply to client")]))
        let daily = try text(noteDay)
        try expect(daily.contains("Status: Open") && daily.contains("Planned day: 2026-10-02") && daily.contains("Ask the client") && daily.contains("- [ ] Reply to client"), "Task, planning, checklist, and comment remain connected in the daily document")
        try expect(daily.contains("https://example.invalid/project") && daily.contains("[Proposal.pdf](Files/"), "The same daily document includes links and relative saved-file references")
        try expect(daily.range(of: "## 08:00:00")!.lowerBound < daily.range(of: "## 08:01:00")!.lowerBound
            && daily.range(of: "## 08:01:00")!.lowerBound < daily.range(of: "## 09:00:00")!.lowerBound, "Daily output is chronological, not feed order")
        try expect(daily.contains("Attached to task:"), "Attached capture remains a receipt linked to its parent task")
        let full = try store.explorerDocuments(project: "Northstar")
        try expect(full.count == 1 && full[0].captureCount == 3, "Daily document count includes every project capture, including task attachments")
        try expect(try store.explorerDocuments(unfiledOnly: true).count == 1, "Unfiled is a real independent collection")
        try store.setOrganization(note, pinned: true, projectName: "Other client")
        try expect(store.explorerProject(for: file) == "Other client" && store.managedURL(for: file)!.path.contains("Projects/Other client — "), "Moving a parent task moves its attached receipt's effective project without copying it")
        try expect(file.captureDay == "2026-09-30" && file.parentTaskID == note.id, "Task moves retain receipt date and attachment identity")
        try expect(try text(noteDay).contains(link.originalURL!) && !text(noteDay).contains("Client feedback"), "Former project daily record retains other captures and removes moved task family")
        let otherDay = try store.explorerDayURL(project: "Other client", day: note.captureDay)
        let outsideEdit = Data("User-authored daily document edit\n".utf8)
        try outsideEdit.write(to: otherDay)
        try store.update(note, comment: "App edit after an outside change", reminderAt: note.reminderAt, reminderTimeZoneID: "UTC")
        let localEdits = try files.contentsOfDirectory(at: otherDay.deletingLastPathComponent().appendingPathComponent("Local edits"), includingPropertiesForKeys: nil)
        try expect(localEdits.contains { (try? bytes($0)) == outsideEdit }, "External daily edits are preserved before regeneration")
        try expect(recoveredEdits(store).contains { (try? bytes($0)) == outsideEdit }, "External edits have an owned backup recovery copy")
        let justBeforeBackup = Data("An outside edit immediately before backup".utf8)
        try justBeforeBackup.write(to: otherDay)
        let backup = scratch.appendingPathComponent("Explorer.dabinbackup")
        try store.exportBackup(to: backup)
        let target = try CaptureStore(root: scratch.appendingPathComponent("Restored"))
        let restored = try target.restoreBackup(from: backup)
        let restoredFile = target.captures.first { $0.id == file.id }!
        try expect(restored.addedCount == 4 && (try bytes(target.managedURL(for: restoredFile)!)) == payload, "Backup and restore retain project originals and all receipt identities")
        try expect(try text(target.explorerDayURL(project: "Other client", day: note.captureDay)).contains("App edit after an outside change"), "Restore regenerates complete daily documents")
        try expect(recoveredEdits(target).contains { (try? bytes($0)) == outsideEdit }, "Backup restores authored external edits")
        try expect(recoveredEdits(target).contains { (try? bytes($0)) == justBeforeBackup }, "Direct external edit then backup preserves authored text without an intervening app save")
        try store.moveToTrash(note)
        try expect(store.captures.allSatisfy { $0.id != file.id && $0.id != note.id }, "Trash removes a task family together")
        let trashed = store.trashedCaptures.first { $0.id == file.id }!
        try expect(store.managedURL(for: trashed)!.path.contains("/.Recently Deleted/") && (try bytes(store.managedURL(for: trashed)!)) == payload, "Trash retains exact bytes outside visible project folders")
        try expect(!files.fileExists(atPath: otherDay.path), "Trash removes the last project's generated daily record")
        try store.restoreFromTrash(store.trashedCaptures.first { $0.id == note.id }!)
        let taskAgain = store.captures.first { $0.id == note.id }!
        let fileAgain = store.captures.first { $0.id == file.id }!
        try expect(store.managedURL(for: fileAgain)!.path.contains("Projects/Other client — ") && files.fileExists(atPath: otherDay.path), "Restore returns the task family and its real project files")
        try store.moveToTrash(taskAgain)
        _ = try store.permanentlyRemove(store.trashedCaptures.first { $0.id == note.id }!)
        try expect(store.trashedCaptures.allSatisfy { $0.id != note.id && $0.id != file.id } && (try bytes(source)) == payload, "Permanent removal deletes owned task-family files while leaving original source untouched")
        try expect(store.managedURL(for: image) != nil && (try text(noteDay)).contains(link.originalURL!), "Deleting one family does not remove neighboring files or another project record")
        let reopened = try CaptureStore(root: root)
        try expect(reopened.captures.count == 2 && reopened.error == nil, "Project library reopens without duplicate receipts or unfinished moves")
    }

    @MainActor static func moves(_ root: URL) throws {
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        let capture = Capture(capturedAt: date("2026-09-30T08:00:00Z"), timeZone: .gmt, kind: .pdf,
            originalFilename: "Legacy.pdf", title: "Legacy.pdf")
        let legacy = try DailyArchive.originalRelativePath(id: capture.id, capturedAt: capture.capturedAt,
            captureDay: capture.captureDay, utcOffset: 0, filename: "Legacy.pdf")
        capture.relocateManagedAttachment(to: legacy)
        capture.projectName = "Client"
        let source = root.appendingPathComponent(legacy)
        try files.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        let payload = Data("Only surviving fixture copy".utf8)
        try payload.write(to: source)
        let service = ProjectFileArchive(root: root)
        var committed = false
        service.afterMoveCommit = { throw CaptureStoreError.injectedInterruption }
        try rejects({ try service.synchronize([capture], records: [capture]) { _ in committed = true } }, "Injected interruption stops after durable path commit")
        let newURL = root.appendingPathComponent(capture.attachmentRelativePath!)
        try expect(committed && newURL != source && (try bytes(newURL)) == payload && (try bytes(source)) == payload, "Interrupted committed move retains both verified copies")
        let restart = ProjectFileArchive(root: root)
        try restart.synchronize([capture], records: [capture]) { _ in throw CaptureStoreError.injectedInterruption }
        try expect(!files.fileExists(atPath: source.path) && (try bytes(newURL)) == payload, "Recovery recognizes committed metadata and deletes only the unchanged former copy")
        try expect(try files.contentsOfDirectory(atPath: root.appendingPathComponent("ExplorerMoves").path).isEmpty, "Successful recovery clears its durable move intent")
        capture.projectName = "New client"
        let previous = capture.attachmentRelativePath!
        try rejects({ try restart.synchronize([capture], records: [capture]) { _ in throw CaptureStoreError.injectedInterruption } }, "Failed metadata relocation remains retryable")
        try expect(capture.attachmentRelativePath == previous && (try bytes(newURL)) == payload, "Metadata failure retains the current original path and bytes")
        try restart.synchronize([capture], records: [capture]) { _ in }
        try expect(capture.attachmentRelativePath != previous && !files.fileExists(atPath: newURL.path), "Retry completes one move without losing receipt identity")
        let day = try restart.dayURL(project: capture.projectName, day: capture.captureDay)
        capture.comment = "A new annotation"
        let raced = Data("Concurrent editor's newest text".utf8)
        restart.beforeDocumentWrite = { try raced.write(to: day) }
        try rejects({ try restart.synchronize([capture], records: [capture]) { _ in } }, "A daily editor changing the file during regeneration aborts replacement")
        try expect(try bytes(day) == raced, "Concurrent outside edits remain untouched")
        restart.beforeDocumentWrite = nil
        try restart.synchronize([capture], records: [capture]) { _ in }
        try expect(try text(day).contains("A new annotation"), "Retry preserves the outside edit and refreshes the generated document")
    }

    @MainActor static func blockedMove(_ root: URL) throws {
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        let capture = Capture(capturedAt: date("2026-09-30T08:00:00Z"), timeZone: .gmt, kind: .file,
            originalFilename: "same.bin", title: "same.bin")
        let legacy = "Originals/\(capture.id.uuidString)/same.bin"
        capture.relocateManagedAttachment(to: legacy)
        let source = root.appendingPathComponent(legacy)
        try files.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("Original".utf8).write(to: source)
        let target = root.appendingPathComponent(try ProjectFileArchive.originalRelativePath(id: capture.id,
            project: nil, day: capture.captureDay, kind: .file, filename: "same.bin"))
        try files.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("Outside edit".utf8).write(to: target)
        let service = ProjectFileArchive(root: root)
        try rejects({ try service.synchronize([capture], records: [capture]) { _ in } }, "Conflicting destination refuses migration")
        try expect(capture.attachmentRelativePath == legacy && (try text(source)) == "Original" && (try text(target)) == "Outside edit", "Conflict preserves both byte streams and keeps the usable metadata path")
        try files.removeItem(at: target)
        try service.synchronize([capture], records: [capture]) { _ in }
        try expect((try text(target)) == "Original" && !files.fileExists(atPath: source.path), "Removing the obstruction allows safe recovery")
    }
}
