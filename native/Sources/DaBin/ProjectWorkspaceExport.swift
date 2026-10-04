import AppKit
import Foundation

enum ProjectWorkspaceExportScope: String, Codable, Sendable {
    case project, selection
    var title: String { self == .project ? "Entire project" : "Selected items" }
}

enum ProjectWorkspaceExportError: LocalizedError {
    case invalidSelection, incompleteProject
    var errorDescription: String? {
        switch self {
        case .invalidSelection: return "Some selected items have changed or are no longer in this project. Select them again."
        case .incompleteProject: return "The project changed before export. Try again to include every item."
        }
    }
}

/// Value-only export facts. No mutable Capture crosses into the file worker, and
/// no absolute source paths, index text, or private archive internals are exported.
struct ProjectWorkspaceExportItem: Codable, Sendable {
    let id: UUID
    let order: Int
    let title: String
    let kind: CaptureKind
    let capturedAt: Date
    let captureDay: String
    let captureTimeZoneID: String
    let captureUTCOffsetSeconds: Int
    let projectName: String?
    let originalFilename: String?
    let originalText: String?
    let originalURL: String?
    let comment: String
    let isTask: Bool
    let isCompleted: Bool
    let parentTaskID: UUID?
    let planning: TaskPlanning?
    let reminderAt: Date?
    let reminderTimeZoneID: String?
    let contentPath: String
}

struct ProjectWorkspaceExportDocument: Sendable {
    let project: String?
    let scope: ProjectWorkspaceExportScope
    let createdAt: Date
    let items: [ProjectWorkspaceExportItem]
    let notes: String?
    let orderedItemIDs: [String]
    fileprivate let notesItemID: String?
    fileprivate let sourceArchive: DailyArchive
    fileprivate let originalPaths: [UUID: String]

    var itemCount: Int { items.count + (notes == nil ? 0 : 1) }
    var suggestedFilename: String {
        ProjectWorkspaceExport.safeName(project ?? "DaBin workspace", byteLimit: 180)
            + (scope == .selection ? " - Selected items" : "") + ".zip"
    }

    /// Captures and the live project scratchpad follow the same unified order
    /// as the workspace. Legacy callers default to captures followed by notes.
    var summary: String {
        let formatter = ISO8601DateFormatter()
        var lines = ["# \(project ?? "DaBin workspace")", "", "Scope: \(scope.title)",
                     "Exported: \(formatter.string(from: createdAt))", "Items: \(itemCount)", ""]
        let byID = Dictionary(uniqueKeysWithValues: items.map { ("capture:" + $0.id.uuidString, $0) })
        for (index, identity) in orderedItemIDs.enumerated() {
            if identity == notesItemID, let notes {
                lines += ["## \(index + 1). Project notes", "", notes, ""]
                continue
            }
            guard let item = byID[identity] else { continue }
            lines += ["## \(item.order). \(item.title)", "", "Type: \(item.kind.rawValue.capitalized)",
                      "Captured: \(formatter.string(from: item.capturedAt))",
                      "Receipt day: \(item.captureDay) (\(item.captureTimeZoneID), UTC offset \(item.captureUTCOffsetSeconds) seconds)"]
            if let project = item.projectName { lines.append("Project: \(project)") }
            if item.isTask { lines.append("Task: \(item.isCompleted ? "Completed" : "Open")") }
            if let parent = item.parentTaskID { lines.append("Attached to task: \(parent.uuidString)") }
            if let planning = item.planning {
                if let day = planning.plannedDay { lines.append("Planned: \(day)\(planning.plannedTime.map { " at " + $0 } ?? "")") }
                if let deadline = planning.deadline { lines.append("Deadline: \(formatter.string(from: deadline))") }
                lines.append("Priority: \(planning.priority.title)")
                if let effort = planning.effortMinutes { lines.append("Estimate: \(effort) minutes") }
                if planning.recurrence != .none { lines.append("Repeats: \(planning.recurrence.title)") }
                if let completed = planning.completedAt { lines.append("Completed: \(formatter.string(from: completed))") }
                for entry in planning.checklist { lines.append("- [\(entry.isCompleted ? "x" : " ")] \(entry.text)") }
            }
            if let reminder = item.reminderAt { lines.append("Reminder: \(formatter.string(from: reminder))") }
            // Paths are generated locally, never based on a source application's path.
            lines += ["Saved content: \(item.contentPath)", ""]
            if let text = item.originalText { lines += [text, ""] }
            if let url = item.originalURL, url != item.originalText { lines += [url, ""] }
            if !item.comment.isEmpty { lines += ["Comment:", item.comment, ""] }
        }
        return lines.joined(separator: "\n")
    }
}

enum ProjectWorkspaceExport {
    enum Checkpoint { case beforePublish }
    private struct VerifiedContent: Codable {
        let itemID: UUID
        let path: String
        let byteCount: Int64
        let sha256: String
    }
    private struct Manifest: Codable {
        let schemaVersion: Int
        let project: String?
        let scope: ProjectWorkspaceExportScope
        let createdAt: Date
        let items: [ProjectWorkspaceExportItem]
        let orderedItemIDs: [String]
        let notesPath: String?
        let content: [VerifiedContent]
    }

    @MainActor static func document(project: String?, captures: [Capture], store: CaptureStore,
                                    notes: String? = nil, scope: ProjectWorkspaceExportScope = .project,
                                    orderedItemIDs: [String]? = nil) throws -> ProjectWorkspaceExportDocument {
        let current = Dictionary(uniqueKeysWithValues: store.captures.map { ($0.id, $0) })
        // A parent with no project must not fall back to an attachment's former project.
        func projectOf(_ capture: Capture) -> String? {
            if let parentID = capture.parentTaskID, let parent = current[parentID] { return parent.projectName }
            return capture.projectName
        }
        let ids = Set(captures.map(\.id))
        guard ids.count == captures.count, captures.allSatisfy({
            current[$0.id] === $0 && $0.deletedAt == nil && (project == nil || projectOf($0) == project)
        }) else { throw ProjectWorkspaceExportError.invalidSelection }
        if scope == .project {
            let projectIDs = Set(store.captures.filter { $0.deletedAt == nil && (project == nil || projectOf($0) == project) }.map(\.id))
            guard ids == projectIDs else { throw ProjectWorkspaceExportError.incompleteProject }
        }
        let includedNotes = notes.flatMap { $0.isEmpty ? nil : $0 }
        guard !captures.isEmpty || includedNotes != nil else { throw WorkspaceError.emptyCollection }
        let noteID = includedNotes == nil ? nil : "note:" + WorkspaceSnapshot.projectKey(project)
        let orderedIDs = try validatedOrder(captureIDs: captures.map { "capture:" + $0.id.uuidString },
                                           noteID: noteID, requested: orderedItemIDs)
        let orderedCaptures = orderedIDs.compactMap { identity -> Capture? in
            guard identity.hasPrefix("capture:"), let id = UUID(uuidString: String(identity.dropFirst(8))) else { return nil }
            return current[id]
        }
        let positions = Dictionary(uniqueKeysWithValues: orderedIDs.enumerated().map { ($0.element, $0.offset + 1) })
        var originalPaths: [UUID: String] = [:]
        let items = try orderedCaptures.map { capture in
            let position = positions["capture:" + capture.id.uuidString]!
            let isFile = [.image, .video, .pdf, .document, .ai, .file].contains(capture.kind)
            if isFile || capture.attachmentRelativePath != nil {
                guard let relative = capture.attachmentRelativePath, store.managedURL(for: capture) != nil else {
                    throw CaptureClipboardError.missingSavedOriginal(capture.originalFilename ?? capture.title)
                }
                originalPaths[capture.id] = relative
            }
            let fileName = originalPaths[capture.id] == nil
                ? safeName(capture.title, byteLimit: 160) + ".txt"
                : safeFileName(capture.originalFilename ?? capture.title)
            let path = "Items/" + String(format: "%05d-", position) + fileName
            return ProjectWorkspaceExportItem(id: capture.id, order: position, title: capture.title,
                kind: capture.kind, capturedAt: capture.capturedAt, captureDay: capture.captureDay,
                captureTimeZoneID: capture.captureTimeZoneID, captureUTCOffsetSeconds: capture.captureUTCOffsetSeconds,
                projectName: projectOf(capture), originalFilename: capture.originalFilename,
                originalText: capture.originalText, originalURL: capture.originalURL, comment: capture.comment,
                isTask: capture.isTask, isCompleted: capture.isCompleted, parentTaskID: capture.parentTaskID,
                planning: capture.taskPlanning, reminderAt: capture.reminderAt,
                reminderTimeZoneID: capture.reminderTimeZoneID, contentPath: path)
        }
        return ProjectWorkspaceExportDocument(project: project, scope: scope, createdAt: Date(), items: items,
            notes: includedNotes, orderedItemIDs: orderedIDs, notesItemID: noteID,
            // Managed relative paths are based at the store root. archiveRoot
            // is only the dated receipt subtree, not the original-file base.
            sourceArchive: DailyArchive(root: store.root), originalPaths: originalPaths)
    }

    /// The native Copy action retains file URLs, web URLs, and text, with project
    /// notes in their workspace position. Preparation succeeds before clearing the
    /// pasteboard. Tests supply their own private pasteboard, never .general.
    @MainActor static func copyItems(captures: [Capture], store: CaptureStore, notes: String? = nil,
                                     orderedItemIDs: [String]? = nil, pasteboard: NSPasteboard = .general) throws {
        let live = Dictionary(uniqueKeysWithValues: store.captures.map { ($0.id, $0) })
        guard Set(captures.map(\.id)).count == captures.count,
              captures.allSatisfy({ live[$0.id] === $0 && $0.deletedAt == nil }) else {
            throw ProjectWorkspaceExportError.invalidSelection
        }
        var objects: [String: NSPasteboardWriting] = [:]
        let captureIDs = captures.map { "capture:" + $0.id.uuidString }
        let includedNotes = notes.flatMap { $0.isEmpty ? nil : $0 }
        let noteID = includedNotes == nil ? nil : orderedItemIDs?.first(where: { $0.hasPrefix("note:") }) ?? "note:inbox:"
        let order = try validatedOrder(captureIDs: captureIDs, noteID: noteID, requested: orderedItemIDs)
        if !captures.isEmpty {
            let payload = try CaptureClipboardService(writer: { _ in true }).payload(for: captures, managedURL: store.managedURL(for:))
            for (identity, item) in zip(captureIDs, payload.items) {
                switch item {
                case .text(let text): objects[identity] = text as NSString
                case .file(let url): objects[identity] = url as NSURL
                case .webURL(let url):
                    let item = NSPasteboardItem()
                    item.setString(url, forType: .URL)
                    item.setString(url, forType: .string)
                    objects[identity] = item
                }
            }
        }
        if let includedNotes, let noteID { objects[noteID] = includedNotes as NSString }
        guard !objects.isEmpty else { throw CaptureClipboardError.noContent }
        pasteboard.clearContents()
        guard pasteboard.writeObjects(order.compactMap { objects[$0] }) else { throw CaptureClipboardError.writeFailed }
    }

    static func export(_ document: ProjectWorkspaceExportDocument, to destination: URL) async throws {
        let worker = Task.detached(priority: .utility) { try write(document, to: destination) }
        try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    }

    /// All byte copies, streamed hashing, and ZIP creation occur in the utility
    /// worker. An unavailable or changed original aborts the entire export: a
    /// partial project is never presented as a successful complete download.
    static func write(_ document: ProjectWorkspaceExportDocument, to destination: URL,
                      checkpoint: ((Checkpoint) throws -> Void)? = nil) throws {
        guard document.itemCount > 0 else { throw WorkspaceError.emptyCollection }
        guard destination.isFileURL else { throw ShelfExportError.failed("Choose a local ZIP destination.") }
        let files = FileManager.default
        guard !files.fileExists(atPath: destination.path) else { throw ShelfExportError.existingDestination }
        let access = destination.startAccessingSecurityScopedResource()
        defer { if access { destination.stopAccessingSecurityScopedResource() } }
        let directory = files.temporaryDirectory.appendingPathComponent("DaBin-ProjectExport-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: directory) }
        let contents = directory.appendingPathComponent("DaBin project", isDirectory: true)
        try files.createDirectory(at: contents, withIntermediateDirectories: false)
        try files.createDirectory(at: contents.appendingPathComponent("Items"), withIntermediateDirectories: false)
        let sourceArchive = document.sourceArchive
        var verifications: [VerifiedContent] = []
        for item in document.items {
            try Task.checkCancellation()
            let target = try safeOutputURL(item.contentPath, root: contents)
            if let path = document.originalPaths[item.id] {
                let source = try sourceArchive.safeURL(path)
                let before = try OriginalFileStorage.verify(source)
                // Re-resolve the managed path immediately before and after IO.
                try files.copyItem(at: sourceArchive.safeURL(path), to: target)
                let copied = try OriginalFileStorage.verify(target)
                let after = try OriginalFileStorage.verify(sourceArchive.safeURL(path))
                guard before.sha256 == copied.sha256, before.sha256 == after.sha256,
                      before.byteCount == copied.byteCount, before.byteCount == after.byteCount else { throw ShelfExportError.changedOriginal }
            } else {
                let text = item.originalText ?? item.originalURL ?? item.title
                try Data(text.utf8).write(to: target, options: .withoutOverwriting)
            }
            let value = try OriginalFileStorage.verify(target)
            verifications.append(VerifiedContent(itemID: item.id, path: item.contentPath,
                byteCount: value.byteCount, sha256: value.sha256))
        }
        try Data(document.summary.utf8).write(to: contents.appendingPathComponent("Project.md"), options: .withoutOverwriting)
        if let notes = document.notes {
            try Data(notes.utf8).write(to: contents.appendingPathComponent("Notes.md"), options: .withoutOverwriting)
        }
        let manifest = Manifest(schemaVersion: 1, project: document.project, scope: document.scope, createdAt: document.createdAt,
            items: document.items, orderedItemIDs: document.orderedItemIDs,
            notesPath: document.notes == nil ? nil : "Notes.md", content: verifications)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: contents.appendingPathComponent("manifest.json"), options: .withoutOverwriting)
        try Task.checkCancellation()
        let zip = directory.appendingPathComponent("Project.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--norsrc", "--keepParent", contents.path, zip.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ShelfExportError.failed(String(data: errorData, encoding: .utf8) ?? "Archive creation failed.")
        }
        try Task.checkCancellation()
        // Same-volume staging provides atomic, non-overwriting publication and
        // works with the file access granted by NSSavePanel in a sandbox.
        let publication = try files.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                        appropriateFor: destination, create: true)
        defer { try? files.removeItem(at: publication) }
        let pending = publication.appendingPathComponent("Project.zip")
        let expected = try OriginalFileStorage.verify(zip)
        try files.copyItem(at: zip, to: pending)
        let copied = try OriginalFileStorage.verify(pending)
        guard expected.sha256 == copied.sha256, expected.byteCount == copied.byteCount else { throw ShelfExportError.changedOriginal }
        try checkpoint?(.beforePublish)
        try Task.checkCancellation()
        try files.moveItem(at: pending, to: destination)
    }

    fileprivate static func safeName(_ value: String, byteLimit: Int) -> String {
        var name = CaptureClassifier.storageFilename(value)
        while name.utf8.count > byteLimit { name.removeLast() }
        if name.isEmpty || name == "." || name == ".." { name = "Untitled" }
        return name
    }

    private static func safeFileName(_ value: String) -> String {
        let ext = (value as NSString).pathExtension
        guard !ext.isEmpty else { return safeName(value, byteLimit: 180) }
        return safeName((value as NSString).deletingPathExtension, byteLimit: 140)
            + "." + safeName(ext, byteLimit: 32)
    }

    private static func validatedOrder(captureIDs: [String], noteID: String?, requested: [String]?) throws -> [String] {
        let available = captureIDs + (noteID.map { [$0] } ?? [])
        guard let requested else { return available }
        guard requested.count == available.count, Set(requested).count == requested.count,
              Set(requested) == Set(available) else { throw ProjectWorkspaceExportError.invalidSelection }
        return requested
    }

    /// The worker created this private, empty Items directory. Only a single
    /// generated leaf is accepted; no caller-supplied nested path can escape it.
    private static func safeOutputURL(_ relative: String, root: URL) throws -> URL {
        let parts = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0] == "Items", !parts[1].isEmpty,
              parts[1] != ".", parts[1] != "..", parts[1].utf8.count <= 255,
              !relative.contains("\\"),
              !relative.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw CaptureStoreError.invalidManagedPath
        }
        return root.appendingPathComponent(relative)
    }
}
