import AppKit
import Foundation

/// Synthetic project archives and a private pasteboard only. The installed
/// archive, global clipboard, and network are never accessed by this suite.
@main struct ProjectWorkspaceExportTests {
    @MainActor static var checks = 0
    static let files = FileManager.default

    @MainActor static func expect(_ value: @autoclosure () throws -> Bool, _ reason: String) throws {
        checks += 1
        if try !value() { throw NSError(domain: "ProjectWorkspaceExportTests", code: 1, userInfo: [NSLocalizedDescriptionKey: reason]) }
    }
    @MainActor static func rejects(_ action: () throws -> Void, _ reason: String) throws {
        var rejected = false
        do { try action() } catch { rejected = true }
        try expect(rejected, reason)
    }
    static func read(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

    @MainActor static func selectedBundle(_ document: ProjectWorkspaceExportDocument, name: String, root: URL) async throws -> URL {
        let destination = root.appendingPathComponent(name + ".zip")
        try await ProjectWorkspaceExport.export(document, to: destination)
        let unpacked = root.appendingPathComponent(name + "-unpacked")
        let extract = Process()
        extract.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        extract.arguments = ["-x", "-k", destination.path, unpacked.path]
        try extract.run(); extract.waitUntilExit()
        try expect(extract.terminationStatus == 0, "The \(name) selection ZIP opens with the native ZIP reader")
        let bundle = unpacked.appendingPathComponent("DaBin project")
        let expectedEntries: Set<String> = document.notes == nil
            ? ["Items", "Project.md", "manifest.json"] : ["Items", "Project.md", "Notes.md", "manifest.json"]
        try expect(Set(try files.contentsOfDirectory(atPath: bundle.path)) == expectedEntries,
                   "The \(name) selection ZIP has exactly the selected content and portable metadata entries")
        let expectedFiles = Set(document.items.map { URL(fileURLWithPath: $0.contentPath).lastPathComponent })
        try expect(Set(try files.contentsOfDirectory(atPath: bundle.appendingPathComponent("Items").path)) == expectedFiles,
                   "The \(name) selection ZIP includes no extra capture files")
        try expect(try read(bundle.appendingPathComponent("Project.md")) == document.summary,
                   "The \(name) selection ZIP keeps its selected summary")
        return bundle
    }

    static func readManifest(_ bundle: URL) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: bundle.appendingPathComponent("manifest.json"))) as! [String: Any]
    }

    @MainActor static func main() async throws {
        let root = files.temporaryDirectory.appendingPathComponent("DaBinProjectExportQA-\(UUID().uuidString)")
        try files.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: root) }
        let store = try CaptureStore(root: root.appendingPathComponent("Archive"))
        let project = "Launch / test: kit"
        let otherProject = "Unrelated project"
        let date = ISO8601DateFormatter().date(from: "2026-10-03T11:22:33Z")!
        let zone = TimeZone(secondsFromGMT: 7_200)!
        let note = try store.capture(text: "  Exact original words ✨\nKeep the line break.  ", at: date, timeZone: zone)[0]
        let link = try store.capture(text: "https://example.invalid/reference?q=two#anchor", at: date, timeZone: zone)[0]
        let task = try store.createTask(text: "Review first draft", at: date, timeZone: zone)
        let original = Data("Synthetic saved original bytes; not a real PDF".utf8)
        let first = try await store.importData(original, filename: "Brief.pdf", at: date, timeZone: zone)
        let second = try await store.importData(Data("Second PDF fixture".utf8), filename: "Brief.pdf", at: date, timeZone: zone)
        let longName = String(repeating: "資料", count: 100) + ".pdf"
        let longFile = try await store.importData(Data("Long name fixture".utf8), filename: longName, at: date, timeZone: zone)
        let unrelated = try store.capture(text: "This must never enter the exported project", at: date, timeZone: zone)[0]
        try store.setOrganization(unrelated, pinned: false, projectName: otherProject)
        let ordered = [second, link, note, first, task, longFile]
        for capture in ordered { try store.setOrganization(capture, pinned: false, projectName: project) }
        try store.convertToTask(first)
        try store.update(task, comment: "Preserve this comment", reminderAt: nil, reminderTimeZoneID: nil,
                         planning: TaskPlanning(plannedDay: "2026-10-04", priority: .high, effortMinutes: 25,
                            checklist: [TaskChecklistItem(text: "Check preview", isCompleted: true), TaskChecklistItem(text: "Send notes")]))
        try store.setTaskCompleted(task, completed: true, at: date.addingTimeInterval(60))
        try store.setOrganization(second, pinned: false, projectName: otherProject)
        try store.attachCapture(second, to: task)
        let notes = "# Working notes\n\nProject-only scratchpad.\n"
        var unifiedOrder = ordered.map { "capture:" + $0.id.uuidString }
        unifiedOrder.insert("note:" + WorkspaceSnapshot.projectKey(project), at: 2)
        let document = try ProjectWorkspaceExport.document(project: project, captures: ordered, store: store, notes: notes,
                                                           orderedItemIDs: unifiedOrder)
        try expect(document.itemCount == 7 && document.items.map(\.id) == ordered.map(\.id), "Snapshot retains custom capture order and includes project notes")
        try expect(document.orderedItemIDs == unifiedOrder && document.items[2].order == 4, "Unified order includes the scratchpad at its exact workspace position")
        try expect(document.items.first?.parentTaskID == task.id, "Task attachment identity survives export")
        try expect(document.items.first?.projectName == project, "Attachments use their parent task's effective project")
        try expect(document.items[3].kind == .pdf && document.items[3].isTask, "A converted file remains a PDF and a task")
        try expect(document.items[4].isCompleted && document.items[4].planning?.checklist[0].isCompleted == true, "Completed task and checklist state survive")
        try expect(document.items[4].planning?.effortMinutes == 25, "Task effort survives in the portable manifest")
        try expect(document.items[0].contentPath != document.items[3].contentPath, "Identical original filenames remain distinct in custom order")
        try expect(document.items.last!.contentPath.hasSuffix(".pdf") && document.items.last!.contentPath.utf8.count < 230, "Long Unicode original names retain extensions and fit the filesystem")
        try expect(!document.suggestedFilename.contains("/") && !document.suggestedFilename.contains(":"), "Suggested ZIP name is a safe local filename")
        try expect(document.summary.contains(note.originalText!) && document.summary.contains(notes), "Summary preserves exact capture and scratchpad wording")
        try expect(document.summary.range(of: "## 3. Project notes")!.lowerBound < document.summary.range(of: "## 4.")!.lowerBound,
                   "Readable summary places project notes inside the ordered sequence")
        try expect(document.summary.contains("Task: Completed") && document.summary.contains("- [x] Check preview"), "Readable summary includes task completion and checklist")
        try expect(document.summary.contains("Scope: Entire project") && !document.summary.contains(unrelated.originalText!), "Whole-project summary is explicitly scoped and excludes other projects")
        try rejects({ _ = try ProjectWorkspaceExport.document(project: project, captures: [first], store: store) }, "Filtered subset cannot masquerade as a whole-project export")
        try rejects({ _ = try ProjectWorkspaceExport.document(project: project, captures: [unrelated], store: store, scope: .selection) }, "Cross-project selection is refused")
        try rejects({ _ = try ProjectWorkspaceExport.document(project: project, captures: [first, first], store: store, scope: .selection) }, "Duplicate identities are refused")
        try rejects({ _ = try ProjectWorkspaceExport.document(project: project, captures: ordered, store: store, notes: notes,
            orderedItemIDs: ordered.map { "capture:" + $0.id.uuidString }) }, "Explicit order cannot silently omit included project notes")
        let selection = try ProjectWorkspaceExport.document(project: project, captures: [link, first], store: store, scope: .selection)
        try expect(selection.items.map(\.id) == [link.id, first.id] && selection.notes == nil && selection.scope == .selection, "Selected export contains only chosen items and preserves their order")
        try rejects({ _ = try ProjectWorkspaceExport.document(project: project, captures: [], store: store, scope: .selection) },
                    "An empty selection cannot fall back to the complete project")
        let onlyNotes = try ProjectWorkspaceExport.document(project: "Empty project", captures: [], store: store, notes: notes)
        try expect(onlyNotes.itemCount == 1 && onlyNotes.items.isEmpty, "A notes-only project is exportable")

        // Selecting one workspace card never implicitly includes its parent,
        // attachments, other captures, or the unselected live project notes.
        let noteSelection = try ProjectWorkspaceExport.document(project: project, captures: [], store: store,
            notes: notes, scope: .selection, orderedItemIDs: ["note:" + WorkspaceSnapshot.projectKey(project)])
        let noteBundle = try await selectedBundle(noteSelection, name: "Only-selected-notes", root: root)
        let noteManifest = try readManifest(noteBundle)
        try expect(try read(noteBundle.appendingPathComponent("Notes.md")) == notes,
                   "A notes-only selection exports the exact selected live note")
        try expect(noteManifest["scope"] as? String == "selection"
            && (noteManifest["items"] as? [[String: Any]])?.isEmpty == true
            && (noteManifest["content"] as? [[String: Any]])?.isEmpty == true
            && noteManifest["notesPath"] as? String == "Notes.md",
                   "A notes-only selected manifest contains no capture metadata or originals")
        try expect(noteManifest["orderedItemIDs"] as? [String] == noteSelection.orderedItemIDs
            && !noteSelection.summary.contains(task.originalText!) && !noteSelection.summary.contains(note.originalText!),
                   "A notes-only selected ZIP excludes unselected task and capture text")

        let taskSelection = try ProjectWorkspaceExport.document(project: project, captures: [task], store: store,
            scope: .selection, orderedItemIDs: ["capture:" + task.id.uuidString])
        let taskBundle = try await selectedBundle(taskSelection, name: "Only-selected-task", root: root)
        let taskManifest = try readManifest(taskBundle)
        let taskItems = taskManifest["items"] as! [[String: Any]]
        let taskContent = taskManifest["content"] as! [[String: Any]]
        try expect(taskManifest["scope"] as? String == "selection"
            && taskItems.map { $0["id"] as! String } == [task.id.uuidString]
            && taskContent.map { $0["itemID"] as! String } == [task.id.uuidString]
            && taskManifest["notesPath"] == nil,
                   "Selecting a task exports only that task, without its unselected attachment or project notes")
        try expect(try read(taskBundle.appendingPathComponent(taskSelection.items[0].contentPath)) == task.originalText,
                   "A selected task ZIP keeps its exact original task text")
        try expect(!taskSelection.summary.contains(second.id.uuidString)
            && !taskSelection.summary.contains(notes) && !taskSelection.summary.contains(note.originalText!),
                   "A selected task summary excludes unselected attachment identity, live note, and capture text")

        let attachmentSelection = try ProjectWorkspaceExport.document(project: project, captures: [second], store: store,
            scope: .selection, orderedItemIDs: ["capture:" + second.id.uuidString])
        let attachmentBundle = try await selectedBundle(attachmentSelection, name: "Only-selected-attachment", root: root)
        let attachmentManifest = try readManifest(attachmentBundle)
        let attachmentItems = attachmentManifest["items"] as! [[String: Any]]
        let attachmentContent = attachmentManifest["content"] as! [[String: Any]]
        try expect(attachmentManifest["scope"] as? String == "selection"
            && attachmentItems.map { $0["id"] as! String } == [second.id.uuidString]
            && attachmentContent.map { $0["itemID"] as! String } == [second.id.uuidString]
            && attachmentItems[0]["parentTaskID"] as? String == task.id.uuidString
            && attachmentItems[0]["projectName"] as? String == project,
                   "Selecting an attachment retains its parent identity and effective project without exporting the parent")
        try expect(try Data(contentsOf: attachmentBundle.appendingPathComponent(attachmentSelection.items[0].contentPath))
            == Data("Second PDF fixture".utf8), "An attachment-only selected ZIP preserves exact original file bytes")
        try expect(!attachmentSelection.summary.contains(task.originalText!)
            && !attachmentSelection.summary.contains(task.comment)
            && !attachmentSelection.summary.contains(notes) && attachmentManifest["notesPath"] == nil,
                   "An attachment-only ZIP excludes the unselected parent body, parent comment, and live project notes")

        let destination = root.appendingPathComponent("Launch.zip")
        try await ProjectWorkspaceExport.export(document, to: destination)
        try expect(files.fileExists(atPath: destination.path), "Background export publishes a ZIP")
        let unpacked = root.appendingPathComponent("Unpacked")
        let extract = Process()
        extract.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        extract.arguments = ["-x", "-k", destination.path, unpacked.path]
        try extract.run(); extract.waitUntilExit()
        try expect(extract.terminationStatus == 0, "The ZIP opens using macOS's native ZIP reader")
        let bundle = unpacked.appendingPathComponent("DaBin project")
        try expect(try Data(contentsOf: bundle.appendingPathComponent(document.items[3].contentPath)) == original, "ZIP saved-original bytes match the managed copy")
        try expect(try read(bundle.appendingPathComponent(document.items[2].contentPath)) == note.originalText, "Individual capture text preserves whitespace and line endings")
        try expect(try read(bundle.appendingPathComponent(document.items[1].contentPath)) == link.originalURL, "Individual link preserves query and fragment")
        try expect(try read(bundle.appendingPathComponent("Notes.md")) == notes, "Scratchpad is also a separately editable Markdown file")
        try expect(try read(bundle.appendingPathComponent("Project.md")) == document.summary, "ZIP summary equals the copy-as-summary document")
        let manifestData = try Data(contentsOf: bundle.appendingPathComponent("manifest.json"))
        let manifest = try JSONSerialization.jsonObject(with: manifestData) as! [String: Any]
        let items = manifest["items"] as! [[String: Any]]
        let content = manifest["content"] as! [[String: Any]]
        try expect(items.map { $0["id"] as! String } == ordered.map { $0.id.uuidString }, "Manifest records exact capture order")
        try expect(manifest["orderedItemIDs"] as? [String] == unifiedOrder, "Manifest includes complete interleaved capture and note order")
        try expect(content.count == ordered.count && content.allSatisfy { ($0["sha256"] as? String)?.count == 64 }, "Every original or text file has a portable byte hash")
        try expect(!String(decoding: manifestData, as: UTF8.self).contains(store.root.path), "Manifest never exposes private absolute archive paths")
        let zipBefore = try Data(contentsOf: destination)
        try rejects({ try ProjectWorkspaceExport.write(document, to: destination) }, "Existing ZIP is not overwritten")
        try expect(try Data(contentsOf: destination) == zipBefore, "Failed overwrite preserves the user's existing ZIP bytes")
        let collision = root.appendingPathComponent("Collision.zip")
        try rejects({ try ProjectWorkspaceExport.write(selection, to: collision, checkpoint: { _ in try Data("Concurrent user file".utf8).write(to: collision) }) }, "A destination created during export is not replaced")
        try expect(try read(collision) == "Concurrent user file", "Atomic publication preserves a concurrent user's file")

        let board = NSPasteboard(name: .init("DaBin.ProjectExportQA.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        try ProjectWorkspaceExport.copyItems(captures: [first, link, note], store: store, notes: notes, pasteboard: board)
        try expect(board.pasteboardItems?.count == 4, "Native copy includes file, link, capture text, and notes as separate items")
        try expect(board.pasteboardItems?[0].string(forType: .fileURL) != nil, "Native file representation remains usable by Finder")
        try expect(board.pasteboardItems?[1].string(forType: .URL) == link.originalURL, "Native link representation remains a URL")
        try expect(board.pasteboardItems?[3].string(forType: .string) == notes, "Project notes are included in native copy")
        let copyOrder = ["capture:" + note.id.uuidString, "note:" + WorkspaceSnapshot.projectKey(project),
                         "capture:" + first.id.uuidString, "capture:" + link.id.uuidString]
        try ProjectWorkspaceExport.copyItems(captures: [first, link, note], store: store, notes: notes,
                                             orderedItemIDs: copyOrder, pasteboard: board)
        try expect(board.pasteboardItems?[0].string(forType: .string) == note.originalText
            && board.pasteboardItems?[1].string(forType: .string) == notes
            && board.pasteboardItems?[2].string(forType: .fileURL) != nil
            && board.pasteboardItems?[3].string(forType: .URL) == link.originalURL, "Native copy preserves the exact unified order, including project notes")
        let previousChange = board.changeCount
        try rejects({ try ProjectWorkspaceExport.copyItems(captures: [], store: store, pasteboard: board) }, "Empty copy is rejected before touching the pasteboard")
        try expect(board.changeCount == previousChange, "Failed preparation preserves private clipboard contents")
        let managed = store.managedURL(for: first)!
        try files.removeItem(at: managed)
        try rejects({ _ = try ProjectWorkspaceExport.document(project: project, captures: [first], store: store, scope: .selection) }, "Missing saved original is reported before presenting an incomplete export")
        let missing = root.appendingPathComponent("Missing.zip")
        try rejects({ try ProjectWorkspaceExport.write(selection, to: missing) }, "A file disappearing after the snapshot aborts the entire export")
        try expect(!files.fileExists(atPath: missing.path), "Failed export leaves no partial ZIP destination")
        try rejects({ try ProjectWorkspaceExport.copyItems(captures: [first], store: store, pasteboard: board) }, "Missing-file native copy fails before clearing the clipboard")
        try expect(board.changeCount == previousChange, "Missing-file failure preserves clipboard contents")
        let outside = root.appendingPathComponent("Outside.txt")
        try Data("Never export this symlink target".utf8).write(to: outside)
        try files.createSymbolicLink(at: managed, withDestinationURL: outside)
        try rejects({ try ProjectWorkspaceExport.write(selection, to: missing) }, "A substituted symbolic original is never followed")
        try expect(try read(outside) == "Never export this symlink target" && !files.fileExists(atPath: missing.path), "Rejected path preserves external target and destination")
        print("PASS: \(checks) project ZIP, ordering, metadata, notes, scope, safe publication, missing-original, and private clipboard checks")
    }
}
