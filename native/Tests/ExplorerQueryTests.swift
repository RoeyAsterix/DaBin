import Foundation

@main struct ExplorerQueryTests {
    @MainActor static func main() async throws {
        var checks = 0
        func expect(_ value: Bool, _ message: String) throws {
            checks += 1
            if !value { throw NSError(domain: "ExplorerQueryTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBin-ExplorerQuery-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = WorkspaceStore(root: root)
        let now = Date()
        let file = Capture(capturedAt: now, kind: .pdf, originalFilename: "Proposal.pdf", title: "Proposal.pdf")
        file.projectName = "Northstar"
        let text = Capture(capturedAt: now.addingTimeInterval(-60), kind: .text, originalText: "Client feedback مرحبا", title: "Feedback")
        text.comment = "Change the deadline"; text.projectName = "Northstar"
        let task = Capture(capturedAt: now.addingTimeInterval(-120), kind: .task, originalText: "Follow up", title: "Follow up")
        task.projectName = "Northstar"
        let attached = Capture(capturedAt: now.addingTimeInterval(-180), kind: .image, originalFilename: "Mood.png", title: "Mood.png", parentTaskID: task.id)
        attached.projectName = "Former client"
        let unfiled = Capture(capturedAt: now.addingTimeInterval(-240), kind: .link, originalURL: "https://example.com", title: "Reference")
        let deleted = Capture(capturedAt: now, kind: .text, originalText: "Deleted", title: "Deleted")
        deleted.deletedAt = now
        let all = [file, text, task, attached, unfiled, deleted]
        func items(_ project: String? = nil, _ filter: CaptureFilter = .all) -> [Capture] {
            ExplorerQuery.items(all, workspace: workspace, project: project, filter: filter, pinnedOnly: false, now: now)
        }
        try expect(items().map(\.id) == [file.id, text.id, task.id, attached.id, unfiled.id], "Newest first, attachments visible, trash excluded")
        try expect(items("Northstar").count == 4, "Parent project includes task attachments without copying files")
        try expect(items("Former client").isEmpty, "An attached item's old project does not override its task")
        try expect(ExplorerQuery.project(of: attached, in: all) == "Northstar", "Presentation resolves effective project")
        task.projectName = nil
        workspace.explorerUnfiledOnly = true
        try expect(Set(items().map(\.id)) == Set([task.id, attached.id, unfiled.id]), "Unfiled includes children of an unfiled task")
        try expect(ExplorerQuery.project(of: attached, in: all) == nil, "Nil parent project remains unfiled")
        task.projectName = "Northstar"; workspace.explorerUnfiledOnly = false
        workspace.explorerQuery = "deadline مرحبا"
        try expect(items().map(\.id) == [text.id], "Search spans mixed language content and comments")
        workspace.explorerQuery = "Proposal"
        try expect(items().map(\.id) == [file.id], "Filename search returns the saved file")
        try expect(ExplorerQuery.items(all, workspace: workspace, project: "Northstar", filter: .all,
            pinnedOnly: false, now: now, query: "").count == 4 && workspace.explorerQuery == "Proposal",
            "The unified-search browser ignores a legacy hidden query while retaining its optional project scope")
        workspace.explorerQuery = "feedback deadline"
        try expect(items().map(\.id) == [text.id], "Search words can span cached original content and editable metadata")
        text.comment = "A revised milestone"
        workspace.explorerQuery = "feedback milestone"
        try expect(items().map(\.id) == [text.id], "Metadata edits remain immediately searchable beside cached immutable content")
        workspace.explorerQuery = ""
        try expect(items(nil, .tasks).map(\.id) == [task.id], "Tasks filter remains available")
        let grouped = ExplorerQuery.sections(items(), grouping: .type)
        try expect(Set(grouped.flatMap(\.captures).map(\.id)).count == items().count, "Each capture occurs once across type groups")
        try expect(grouped.map(\.id) == ["files", "media", "links", "text", "tasks"], "Recognizable stable group order")
        try expect(ExplorerQuery.sections(items(), grouping: .date).flatMap(\.captures).count == 5, "Date grouping retains all items")
        let archive = DailyArchive(root: root)
        let snapshot = ExplorerQuery.projectDays(all, in: all)
        let documents = try await Task.detached {
            try ExplorerQuery.dailyDocuments(snapshot, archive: archive, project: nil, unfiledOnly: false)
        }.value
        let expectedDocuments = try ProjectFileArchive(root: root).documents(records: all, project: nil, unfiledOnly: false)
        try expect(documents.map(\.id) == expectedDocuments.map(\.id)
                   && documents.map(\.url) == expectedDocuments.map(\.url)
                   && documents.map(\.captureCount) == expectedDocuments.map(\.captureCount),
                   "Background daily listing preserves canonical grouping, validated paths, counts and order")
        task.projectName = "Moved project"
        let oldProjectDocuments = try await Task.detached {
            try ExplorerQuery.dailyDocuments(snapshot, archive: archive, project: "Northstar", unfiledOnly: false)
        }.value
        try expect(oldProjectDocuments.reduce(0) { $0 + $1.captureCount } == 4,
                   "Daily workers read immutable ownership snapshots rather than mutable captures")
        let currentDays = ExplorerQuery.projectDays(all, in: all)
        try expect(currentDays.filter { $0.projectName == "Moved project" }.count == 2,
                   "A fresh daily snapshot follows the parent and its attachment after a project move")
        let unfiledDocuments = try ExplorerQuery.dailyDocuments(currentDays, archive: archive, project: nil, unfiledOnly: true)
        try expect(unfiledDocuments.count == 1 && unfiledDocuments[0].captureCount == 1,
                   "Background listing retains an independent Unfiled scope")
        task.projectName = "Northstar"
        let foreign = root.appendingPathComponent("Foreign")
        try FileManager.default.createDirectory(at: foreign, withIntermediateDirectories: true)
        let projectsLink = root.appendingPathComponent("Projects")
        try FileManager.default.createSymbolicLink(at: projectsLink, withDestinationURL: foreign)
        do {
            _ = try ExplorerQuery.dailyDocuments(snapshot, archive: archive, project: "Northstar", unfiledOnly: false)
            try expect(false, "Background listing must reject a project path replaced by a symlink")
        } catch is DailyArchive.ArchiveError {
            try expect(true, "Background listing retains canonical symlink rejection")
        }
        try FileManager.default.removeItem(at: projectsLink)
        workspace.selectedProject = "Northstar"; workspace.selectedCaptureID = file.id
        workspace.explorerGrouping = .date; workspace.explorerShowsDailyFiles = true
        workspace.explorerQuery = "Proposal"; workspace.explorerUnfiledOnly = true
        let reloaded = WorkspaceStore(root: root)
        try expect(reloaded.explorerGrouping == .date && reloaded.explorerShowsDailyFiles, "Explorer view preferences survive restart")
        try expect(reloaded.explorerQuery == "Proposal" && reloaded.selectedCaptureID == file.id, "Search and selection survive restart")
        try expect(reloaded.explorerUnfiledOnly, "Unfiled preference survives restart")
        let old = Data("{\"schemaVersion\":1,\"scratchpads\":{},\"shelfCaptureIDs\":[],\"snippetNames\":{},\"processedInboxIDs\":[],\"mode\":\"collection\",\"dateFilter\":\"anytime\",\"originFilter\":\"all\",\"snippetsOnly\":false}".utf8)
        let legacy = try JSONDecoder().decode(WorkspaceSnapshot.self, from: old)
        try expect(try legacy.validated().explorerGrouping == nil, "Older workspace preferences remain readable")
        print("PASS: \(checks) Explorer filtering, grouping and persistence checks")
    }
}
