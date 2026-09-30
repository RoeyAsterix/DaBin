import Foundation

@main
struct ClipboardRetentionTests {
    @MainActor private static var checks = 0
    @MainActor private static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        if try !value() { throw NSError(domain: "ClipboardRetentionTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinRetention-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root.appendingPathComponent("Live"))
        let workspace = WorkspaceStore(root: store.root)
        let service = ClipboardRetentionService(store: store, workspace: workspace)
        let now = Date()
        let old = now.addingTimeInterval(-95 * 86_400)
        func copy(_ text: String, at date: Date? = nil, origin: CaptureOrigin = .automaticClipboard) throws -> Capture {
            let stamp = date ?? old
            let capture = try store.capture(text: text, at: stamp, receipt: .automatic(origin))[0]
            capture.updatedAt = stamp
            try store.save(captures: [capture])
            return capture
        }
        let eligible = try copy("Unfiled old automatic text")
        let recent = try copy("A recent automatic copy", at: now)
        let task = try copy("A client commitment")
        try store.convertToTask(task)
        let attached = try copy("Task source material")
        try store.attachCapture(attached, to: task)
        let pinned = try copy("A pinned reply")
        try store.setOrganization(pinned, pinned: true, projectName: nil)
        let project = try copy("Client project resource")
        try store.setOrganization(project, pinned: false, projectName: "Client Example")
        let snippet = try copy("Named reusable reply")
        try workspace.setSnippetName("Reply", for: snippet.id)
        let shelf = try copy("Material waiting on the shelf")
        try workspace.setOnShelf([shelf.id], included: true)
        let intentionallyKept = try copy("A copy deliberately kept from Inbox")
        try workspace.markInboxProcessed([intentionallyKept.id])
        let reminder = try copy("Remind me about this copy")
        try store.update(reminder, comment: "", reminderAt: now.addingTimeInterval(86_400), reminderTimeZoneID: "UTC")
        let screenshot = try copy("Automatic screenshot fixture", origin: .automaticScreenshot)
        let manual = try store.capture(text: "Intentional manually saved note", at: old)[0]
        try expect(service.period == .never && service.retentionCandidates(at: now).isEmpty, "Retention is disabled by default")
        _ = await service.cleanup(at: now)
        try expect(store.trashedCaptures.isEmpty && !FileManager.default.fileExists(atPath: store.root.appendingPathComponent(ClipboardRetentionService.filename).path),
                   "Default startup cleanup does not move data or create a preference")
        try service.setPeriod(.days7)
        try expect(service.retentionCandidates(at: now).map(\.id) == [eligible.id], "Age-based cleanup excludes every protected kind of work")
        let result = await service.cleanup(at: now)
        try expect(result.movedCount == 1 && result.error == nil && store.trashedCaptures.contains { $0.id == eligible.id }, "Opt-in cleanup moves only eligible copies to recoverable trash")
        try expect([recent, task, attached, pinned, project, snippet, shelf, intentionallyKept, reminder, screenshot, manual].allSatisfy { expected in store.captures.contains { $0.id == expected.id } },
                   "Tasks, attachments, pins, projects, snippets, shelf, deliberately kept items, reminders, screenshots, and manual notes stay active")
        try store.restoreFromTrash(store.trashedCaptures.first { $0.id == eligible.id }!)
        try expect(service.retentionCandidates(at: now).isEmpty, "Restoring an old copy restarts retention instead of immediately trashing it again")
        try expect(ClipboardRetentionService(store: store, workspace: workspace).period == .days7, "Retention preference persists per local archive")
        let reopened = try CaptureStore(root: store.root)
        try expect(reopened.captures.contains { $0.id == eligible.id }, "Recovered copies survive restart")
        service.settingsFailureInjector = { throw CaptureStoreError.importVerificationFailed }
        do { try service.setPeriod(.days30); throw NSError(domain: "ExpectedFailure", code: 1) }
        catch CaptureStoreError.importVerificationFailed {}
        try expect(service.period == .days7 && ClipboardRetentionService(store: store, workspace: workspace).period == .days7,
                   "A failed settings write retains both in-memory and saved retention")
        service.settingsFailureInjector = nil

        let confirmed = service.clearCandidates.map(\.id)
        let arrivedLater = try copy("A copy arriving after confirmation", at: now)
        try store.setOrganization(recent, pinned: true, projectName: nil)
        let cleared = await service.clearUnfiledHistory(confirmedIDs: confirmed)
        try expect(cleared.movedCount == 1 && store.captures.contains { $0.id == arrivedLater.id } && store.captures.contains { $0.id == recent.id },
                   "Explicit clearing affects only confirmed IDs and rechecks protections")
        store.failureInjector = { if $0 == .beforeMetadataSave { throw CaptureStoreError.importVerificationFailed } }
        let failed = await service.clearUnfiledHistory(confirmedIDs: [arrivedLater.id])
        try expect(failed.error != nil && failed.movedCount == 0 && store.captures.contains { $0.id == arrivedLater.id },
                   "A failed trash write reports failure and keeps the copy active")
        store.failureInjector = nil

        let protectedDuringCancel = try copy("Protected while indexing is being cancelled")
        service.onWillTrash = { capture in
            try? store.setOrganization(capture, pinned: true, projectName: nil)
            await Task.yield()
        }
        let protectedResult = await service.clearUnfiledHistory(confirmedIDs: [protectedDuringCancel.id])
        try expect(protectedResult.movedCount == 0 && store.captures.contains { $0.id == protectedDuringCancel.id },
                   "A copy pinned while background work is cancelled stays active")
        service.onWillTrash = nil
        let editedDuringCancel = try copy("Edited while cleanup cancels indexing")
        service.onWillTrash = { capture in
            try? store.update(capture, comment: "Just edited", reminderAt: nil, reminderTimeZoneID: nil)
            await Task.yield()
        }
        let editedResult = await service.cleanup(at: now)
        try expect(editedResult.movedCount == 0 && store.captures.contains { $0.id == editedDuringCancel.id },
                   "Automatic retention rechecks last activity after cancellation")
        service.onWillTrash = nil
        let cancelledCopy = try copy("Kept when cleanup is cancelled while stopping indexing")
        service.onWillTrash = { _ in
            withUnsafeCurrentTask { $0?.cancel() }
            await Task.yield()
        }
        let cancelledOperation = Task { await service.clearUnfiledHistory(confirmedIDs: [cancelledCopy.id]) }
        let cancelledResult = await cancelledOperation.value
        try expect(cancelledResult.movedCount == 0 && cancelledResult.error != nil
                   && store.captures.contains { $0.id == cancelledCopy.id },
                   "Cancellation during an awaited callback prevents the pending trash commit")
        service.onWillTrash = nil

        let noteText = "  https://example.invalid/first\nhttps://example.invalid/second\n"
        let beforeNotes = store.captures.count
        let note = try store.createNote(text: noteText, projectName: "  Client A \n")
        try expect(store.captures.count == beforeNotes + 1 && note.kind == .text && note.originalText == noteText && note.originalURL == nil,
                   "An authored multi-link note stays one exact text record")
        try expect(note.projectName == "Client A", "A new note saves its normalized project in the same transaction")
        store.failureInjector = { if $0 == .beforeMetadataSave { throw CaptureStoreError.importVerificationFailed } }
        do { _ = try store.createNote(text: "Keep this failed draft", projectName: "Client A"); throw NSError(domain: "ExpectedFailure", code: 1) }
        catch CaptureStoreError.importVerificationFailed {}
        try expect(store.captures.count == beforeNotes + 1, "Failed note creation leaves no partial capture")
        do { _ = try store.createTask(text: "Failed project task", projectName: "Client A"); throw NSError(domain: "ExpectedFailure", code: 1) }
        catch CaptureStoreError.importVerificationFailed {}
        try expect(store.captures.count == beforeNotes + 1, "Failed project task creation leaves no unfiled partial task")
        store.failureInjector = nil
        let projectTask = try store.createTask(text: "Project task", projectName: "Client B")
        try expect(try CaptureStore(root: store.root).captures.first { $0.id == projectTask.id }?.projectName == "Client B",
                   "A new task's project survives reopening without a second organization save")

        let boundedStore = try CaptureStore(root: root.appendingPathComponent("Bounded"))
        let boundedWorkspace = WorkspaceStore(root: boundedStore.root)
        let batch = try boundedStore.capture(text: (0..<205).map { "https://example.invalid/item-\($0)" }.joined(separator: "\n"),
                                            at: old, receipt: .automatic(.automaticClipboard))
        batch.forEach { $0.updatedAt = old }
        try boundedStore.save(captures: batch)
        let bounded = ClipboardRetentionService(store: boundedStore, workspace: boundedWorkspace)
        try bounded.setPeriod(.days90)
        let boundedResult = await bounded.cleanup(at: now)
        try expect(boundedResult.movedCount == 200 && boundedResult.remainingCount == 5 && boundedStore.captures.count == 5,
                   "Automatic cleanup is bounded to 200 records per pass")
        try bounded.setPeriod(.never)
        _ = await bounded.cleanup(at: now)
        try expect(boundedStore.captures.count == 5, "Turning retention off immediately stops future automatic passes")

        let unsafeStore = try CaptureStore(root: root.appendingPathComponent("Unreadable"))
        let unsafeWorkspaceURL = unsafeStore.root.appendingPathComponent(WorkspaceStore.filename)
        try Data("unreadable workspace".utf8).write(to: unsafeWorkspaceURL)
        let unknownWorkspace = WorkspaceStore(root: unsafeStore.root)
        let unknown = ClipboardRetentionService(store: unsafeStore, workspace: unknownWorkspace)
        _ = try unsafeStore.capture(text: "Protected because references are unreadable", at: old, receipt: .automatic(.automaticClipboard))
        try expect(unknown.clearCandidates.isEmpty, "Unreadable workspace references fail closed and protect clipboard history")
        let unsafeSettingsURL = unsafeStore.root.appendingPathComponent(ClipboardRetentionService.filename)
        let bytes = Data("unknown settings".utf8)
        try bytes.write(to: unsafeSettingsURL)
        let unknownSettings = ClipboardRetentionService(store: unsafeStore, workspace: unknownWorkspace)
        try expect(unknownSettings.period == .never && unknownSettings.error != nil, "Unreadable retention settings disable cleanup with visible feedback")
        let unreadableError = unknownSettings.error
        let unreadableCleanup = await unknownSettings.cleanup(at: now)
        try expect(unreadableCleanup.error == unreadableError && unknownSettings.error == unreadableError
                   && unknownSettings.lastResult == nil && unsafeStore.trashedCaptures.isEmpty,
                   "Automatic startup cleanup preserves unreadable-settings feedback without suggesting successful cleanup")
        do { try unknownSettings.setPeriod(.days7); throw NSError(domain: "ExpectedFailure", code: 1) }
        catch WorkspaceError.invalidArchive {}
        try expect(try Data(contentsOf: unsafeSettingsURL) == bytes, "Unreadable retention settings are preserved")
        print("PASS: \(checks) clipboard retention, recovery, protected-work, and note-capture checks.")
    }
}
