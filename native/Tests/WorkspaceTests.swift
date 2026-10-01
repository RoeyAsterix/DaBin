import AppKit
import Foundation
import UniformTypeIdentifiers

@main struct WorkspaceTests {
    @MainActor static func main() async throws {
        var checks = 0
        func expect(_ value: Bool, _ message: String) throws {
            checks += 1
            if !value { throw NSError(domain: "WorkspaceTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let files = FileManager.default
        for symbol in ["square.stack", "doc.on.clipboard", "tray.full", "note.text", "text.badge.star", "tray.and.arrow.down", "rectangle.and.text.magnifyingglass"] {
            try expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil,
                "Workspace symbol \(symbol) is available in macOS")
        }
        let root = files.temporaryDirectory.appendingPathComponent("DaBin-WorkspaceTests-\(UUID())")
        defer { try? files.removeItem(at: root) }
        let store = try CaptureStore(root: root.appendingPathComponent("archive"))
        let workspace = WorkspaceStore(root: store.root)
        try expect(workspace.error == nil && workspace.mode == .collection && workspace.shelfCaptureIDs.isEmpty,
            "An old capture archive opens with a clean optional workspace")
        try workspace.setScratchpad(text: "A client commitment", project: "Client A")
        try workspace.setScratchpad(text: "A separate brief", project: "Client B")
        try workspace.setScratchpad(text: "Unfiled thought", project: nil)
        try expect(workspace.scratchpad(project: "Client A") == "A client commitment"
            && workspace.scratchpad(project: "Client B") == "A separate brief" && workspace.scratchpad(project: nil) == "Unfiled thought",
            "Project scratchpads stay independent")

        workspace.failureInjector = { throw CaptureStoreError.injectedInterruption }
        do { try workspace.setScratchpad(text: "Unsaved commitment", project: "Client A"); try expect(false, "Injected save must fail") }
        catch CaptureStoreError.injectedInterruption { }
        try expect(workspace.hasUnsavedChanges && workspace.scratchpad(project: "Client A") == "Unsaved commitment",
            "Failed autosave keeps the actual edit available across navigation")
        try expect(try WorkspaceStore.readSnapshot(at: store.root)?.scratchpads[WorkspaceSnapshot.projectKey("Client A")]?.text == "A client commitment",
            "Failed autosave does not overwrite prior persisted text")
        workspace.failureInjector = nil
        try workspace.setScratchpad(text: workspace.scratchpad(project: "Client A"), project: "Client A")
        try expect(!workspace.hasUnsavedChanges && workspace.error == nil, "Retry commits the pending scratchpad")

        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let old = try store.capture(text: "A reusable reply", at: yesterday,
            receipt: .automatic(.automaticClipboard, sourceApplicationName: "Mail", sourceApplicationBundleIdentifier: "com.apple.mail"))[0]
        let recent = try store.capture(text: "Feedback from Client A", at: now,
            receipt: .automatic(.automaticClipboard, sourceApplicationName: "Safari", sourceApplicationBundleIdentifier: "com.apple.Safari"))[0]
        let other = try store.capture(text: "Feedback from Client B", at: now.addingTimeInterval(-10))[0]
        let task = try store.createTask(text: "Call client", at: now)
        try store.setOrganization(old, pinned: true, projectName: "Client A")
        try store.setOrganization(recent, pinned: false, projectName: "Client A")
        try store.setOrganization(other, pinned: false, projectName: "Client B")
        try workspace.setOnShelf([recent.id, old.id, recent.id], included: true)
        try workspace.setSnippetName("Standard response", for: old.id)
        try workspace.markInboxProcessed([old.id])
        workspace.mode = .clipboard
        workspace.selectedProject = "Client A"
        workspace.selectedCaptureID = old.id
        try expect(WorkspaceQuery.items(store.captures, workspace: workspace, project: nil, filter: .all, query: "").first?.id == recent.id,
            "Recent clipboard content stays above old pinned snippets")
        try expect(!WorkspaceQuery.items(store.captures, workspace: workspace, project: nil, filter: .all, query: "").contains { $0.id == task.id },
            "Standalone tasks do not clutter clipboard history")
        try expect(WorkspaceQuery.items(store.captures, workspace: workspace, project: "Client A", filter: .all, query: "standard").map(\.id) == [old.id],
            "Snippet aliases are searchable without replacing original text")
        workspace.sourceApplication = "Safari"
        try expect(WorkspaceQuery.items(store.captures, workspace: workspace, project: "Client A", filter: .text, query: "").map(\.id) == [recent.id],
            "Clipboard source, content-type and project filters intersect")
        workspace.sourceApplication = nil
        workspace.dateFilter = .today
        try expect(WorkspaceQuery.items(store.captures, workspace: workspace, project: "Client A", filter: .all, query: "", now: now).map(\.id) == [recent.id],
            "Today excludes earlier clipboard receipts")
        workspace.dateFilter = .anytime
        workspace.originFilter = .clipboard
        try expect(WorkspaceQuery.items(store.captures, workspace: workspace, project: nil, filter: .all, query: "").count == 2,
            "Origin filtering does not mislabel manual notes as automatic copies")
        workspace.originFilter = .all
        workspace.snippetsOnly = true
        try expect(WorkspaceQuery.items(store.captures, workspace: workspace, project: nil, filter: .all, query: "").map(\.id) == [old.id],
            "Named snippets use their own quick-access filter")
        try expect(workspace.selectedCaptureID == old.id, "Arrival and filtering preserve the selected item")

        let reopened = WorkspaceStore(root: store.root)
        try expect(reopened.mode == .clipboard && reopened.selectedProject == "Client A" && reopened.selectedCaptureID == old.id
            && reopened.snippetsOnly && reopened.snippetName(for: old.id) == "Standard response"
            && reopened.shelfCaptureIDs == [old.id, recent.id] && reopened.processedInboxIDs == [old.id]
            && reopened.scratchpad(project: "Client A") == "Unsaved commitment", "Restart restores all workspace context and saved material")
        reopened.selectedProject = "Client B"; reopened.selectedCaptureID = other.id
        reopened.selectedProject = "Client A"
        try expect(reopened.selectedCaptureID == old.id, "Switching clients restores that project's own selection")
        let projectReload = WorkspaceStore(root: store.root)
        projectReload.selectedProject = "Client B"
        try expect(projectReload.selectedCaptureID == other.id, "Every project's selection survives restart")
        try reopened.setOnShelf([old.id], included: false)
        try expect(store.captures.contains { $0.id == old.id } && old.originalText == "A reusable reply",
            "Removing a shelf reference keeps its source capture intact")
        reopened.mode = .shelf
        try store.moveToTrash(recent)
        try expect(WorkspaceQuery.items(store.captures, workspace: reopened, project: nil, filter: .all, query: "").isEmpty,
            "Trashed captures cannot reappear through stale shelf IDs")
        let multilingual = String(repeating: "שלום — client notes / 日本語\n", count: 2000)
        try reopened.setScratchpad(text: multilingual, project: "Long notes")
        try expect(WorkspaceStore(root: store.root).scratchpad(project: "Long notes") == multilingual,
            "Long mixed-language scratchpads survive byte-exactly")

        let pasteboard = NSPasteboard(name: .init("DaBinWorkspaceTests.\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        try WorkspaceClipboard.copyPlainText(old, to: pasteboard)
        let writtenTypes = pasteboard.types ?? []
        // AppKit publishes the legacy NSStringPboardType alias alongside the
        // modern plain-text UTI. Neither representation carries rich formatting.
        try expect(writtenTypes.contains(.string) && writtenTypes.allSatisfy {
            $0.rawValue == "NSStringPboardType" || UTType($0.rawValue)?.conforms(to: .plainText) == true
        } && !writtenTypes.contains(.html) && !writtenTypes.contains(.rtf) && !writtenTypes.contains(.rtfd)
            && pasteboard.string(forType: .string) == old.originalText,
            "Copy as plain text writes exact text using only macOS plain-text representations")
        let source = root.appendingPathComponent("Client brief.txt")
        try Data("Client file bytes".utf8).write(to: source)
        let file = try await store.importFile(source)
        try files.removeItem(at: source)
        try WorkspaceClipboard.copyManagedPath(file, store: store, to: pasteboard)
        try expect(pasteboard.string(forType: .string) == store.managedURL(for: file)?.path
            && pasteboard.string(forType: .string) != source.path, "Copy path uses the readable managed copy after external source disappears")
        let duplicate = try store.capture(text: "A reusable reply")[0]
        let entries = try ShelfExport.entries(for: [old, duplicate, file], store: store)
        try expect(Set(entries.map { $0.name.lowercased() }).count == entries.count,
            "Collection export disambiguates equal filenames")
        let destination = root.appendingPathComponent("Collection.zip")
        let interrupted = root.appendingPathComponent("Interrupted.zip")
        let siblingsBeforeExport = Set(try files.contentsOfDirectory(atPath: root.path))
        do {
            try ShelfExport.write(entries, to: interrupted, checkpoint: { _ in
                try expect(Set(try files.contentsOfDirectory(atPath: root.path)) == siblingsBeforeExport,
                    "ZIP staging does not require creating an unselected sibling beside the Save Panel destination")
                throw CaptureStoreError.injectedInterruption
            })
            try expect(false, "Interrupted ZIP publication must fail")
        } catch CaptureStoreError.injectedInterruption { }
        try expect(!files.fileExists(atPath: interrupted.path)
            && !(try files.contentsOfDirectory(atPath: root.path)).contains { $0.hasPrefix(".DaBin-Collection-") },
            "Interrupted ZIP publication leaves no partial destination or staging directory")
        try await Task.detached { try ShelfExport.write(entries, to: destination) }.value
        let output = root.appendingPathComponent("unpacked")
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", destination.path, output.path]
        try unzip.run(); unzip.waitUntilExit()
        try expect(unzip.terminationStatus == 0, "Export produces a standard macOS-readable ZIP")
        let unpacked = output.appendingPathComponent("DaBin collection")
        for entry in entries {
            let expected = try entry.source.map { try Data(contentsOf: $0) } ?? Data((entry.text ?? "").utf8)
            try expect(try Data(contentsOf: unpacked.appendingPathComponent(entry.name)) == expected,
                "ZIP entry retains exact original or UTF-8 text bytes")
        }
        let before = try Data(contentsOf: destination)
        do { try ShelfExport.write(entries, to: destination); try expect(false, "Existing ZIP must not be silently replaced") }
        catch ShelfExportError.existingDestination { }
        try expect(try Data(contentsOf: destination) == before, "A refused replacement keeps the prior ZIP unchanged")
        let racingDestination = root.appendingPathComponent("Created by another app.zip")
        let racingContent = Data("Preserve the file created while export was running".utf8)
        do {
            try ShelfExport.write(entries, to: racingDestination, checkpoint: { _ in
                try racingContent.write(to: racingDestination, options: .withoutOverwriting)
            })
            try expect(false, "ZIP publication must refuse a concurrently created destination")
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError { }
        try expect(try Data(contentsOf: racingDestination) == racingContent,
            "ZIP publication leaves a concurrently created destination unchanged")

        let shelfParent = try store.createTask(text: "Shelf attachment parent", projectName: "Attachment project")
        let shelfChild = try store.capture(text: "Explicit shelf attachment")[0]
        try store.setOrganization(shelfChild, pinned: false, projectName: "Former attachment project")
        try store.attachCapture(shelfChild, to: shelfParent)
        let unselectedChild = try store.capture(text: "Attachment outside the shelf")[0]
        try store.attachCapture(unselectedChild, to: shelfParent)
        try reopened.setOnShelf([shelfChild.id], included: true)
        reopened.mode = .shelf
        func visibleShelf(_ project: String? = nil, query: String = "") -> [Capture] {
            WorkspaceQuery.items(store.captures, workspace: reopened, project: project, filter: .all, query: query)
        }
        let selectedShelf = WorkspaceQuery.shelfItems(store.captures, workspace: reopened, project: "Attachment project")
        try expect(visibleShelf("Attachment project").map(\.id) == [shelfChild.id]
            && selectedShelf.map(\.id) == [shelfChild.id],
            "Shelf and ZIP selection include explicitly shelved attachments under the parent project")
        try expect(!visibleShelf().contains { $0.id == unselectedChild.id },
            "Shelving one attachment does not include its parent or other attachments")
        try expect(visibleShelf("Former attachment project").isEmpty
            && visibleShelf(query: "Attachment project").map(\.id) == [shelfChild.id]
            && visibleShelf(query: "Former").isEmpty,
            "Shelf filters and search use the parent project instead of the child's former project")
        let childEntries = try ShelfExport.entries(for: selectedShelf, store: store)
        try expect(childEntries.count == 1 && childEntries[0].text == shelfChild.originalText,
            "Shelf ZIP entries include the same attachment and preserve its original content")
        try store.setOrganization(shelfParent, pinned: false, projectName: nil)
        reopened.explorerUnfiledOnly = true
        try expect(visibleShelf().contains { $0.id == shelfChild.id }
            && WorkspaceQuery.shelfItems(store.captures, workspace: reopened, project: nil).contains { $0.id == shelfChild.id },
            "An unfiled parent's shelved attachment remains visible and exportable as unfiled")
        try store.setOrganization(shelfParent, pinned: false, projectName: "Another attachment project")
        try expect(!visibleShelf().contains { $0.id == shelfChild.id }
            && visibleShelf("Another attachment project").map(\.id) == [shelfChild.id],
            "Changing the parent project moves shelf scope without copying or detaching the attachment")
        reopened.explorerUnfiledOnly = false
        reopened.mode = .clipboard
        try expect(!WorkspaceQuery.items(store.captures, workspace: reopened, project: nil, filter: .all, query: "").contains { $0.id == shelfChild.id },
            "Explicit attachment shelf membership does not change clipboard filtering")
        reopened.mode = .shelf
        try reopened.setOnShelf([shelfChild.id], included: false)
        try expect(!visibleShelf().contains { $0.id == shelfChild.id }
            && shelfChild.parentTaskID == shelfParent.id && store.captures.contains { $0.id == shelfChild.id },
            "Removing a shelved attachment keeps its parent relationship and original capture")
        try reopened.setOnShelf([shelfChild.id], included: true)
        try store.moveToTrash(shelfChild)
        try expect(!visibleShelf().contains { $0.id == shelfChild.id }
            && !WorkspaceQuery.shelfItems(store.captures + store.trashedCaptures, workspace: reopened, project: nil).contains { $0.id == shelfChild.id },
            "Stale shelf membership never displays or exports a trashed attachment")

        let badRoot = root.appendingPathComponent("bad")
        try files.createDirectory(at: badRoot, withIntermediateDirectories: true)
        let badURL = badRoot.appendingPathComponent(WorkspaceStore.filename)
        let bad = Data("not json".utf8)
        try bad.write(to: badURL)
        let broken = WorkspaceStore(root: badRoot)
        do { try broken.setSnippetName("Do not overwrite", for: old.id); try expect(false, "Unreadable workspace must be protected") }
        catch WorkspaceError.invalidArchive { }
        try expect(broken.error != nil && (try Data(contentsOf: badURL)) == bad, "Corrupted workspace remains preserved for recovery")
        try files.removeItem(at: badURL)
        let external = root.appendingPathComponent("untouched.json")
        try files.createSymbolicLink(at: badURL, withDestinationURL: external)
        do { try WorkspaceStore.writeSnapshot(WorkspaceSnapshot(), at: badRoot); try expect(false, "Dangling link must be rejected") }
        catch WorkspaceError.invalidArchive { }
        try expect(!files.fileExists(atPath: external.path), "A workspace symlink cannot create an external file")
        print("PASS: \(checks) workspace, clipboard, scratchpad, collection and ZIP checks")
    }
}
