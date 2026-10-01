import Foundation

struct ShelfExportEntry: Sendable {
    let name: String
    let source: URL?
    let text: String?
}

enum ShelfExportError: LocalizedError {
    case existingDestination, changedOriginal, failed(String)
    var errorDescription: String? {
        switch self {
        case .existingDestination: return "A file already has this name. Choose a new ZIP filename."
        case .changedOriginal: return "A saved original changed during export. Your source files were kept; please try again."
        case .failed(let message): return "Couldn’t create the ZIP. " + message
        }
    }
}

enum ShelfExport {
    enum Checkpoint { case beforePublish }
    @MainActor static func entries(for captures: [Capture], store: CaptureStore) throws -> [ShelfExportEntry] {
        guard !captures.isEmpty else { throw WorkspaceError.emptyCollection }
        var used = Set<String>()
        return try captures.map { capture in
            let source = store.managedURL(for: capture)
            if capture.attachmentRelativePath != nil, source == nil {
                throw CaptureClipboardError.missingSavedOriginal(capture.originalFilename ?? capture.title)
            }
            let plain = WorkspaceQuery.plainText(capture) ?? capture.title
            let suggested = source == nil ? String(capture.title.prefix(70)) + ".txt" : capture.originalFilename ?? source!.lastPathComponent
            let base = CaptureClassifier.storageFilename(suggested)
            let stem = (base as NSString).deletingPathExtension
            let ext = (base as NSString).pathExtension
            var name = base
            var suffix = 2
            while !used.insert(name.lowercased()).inserted {
                name = stem + " (\(suffix))" + (ext.isEmpty ? "" : "." + ext)
                suffix += 1
            }
            return ShelfExportEntry(name: name, source: source, text: source == nil ? plain : nil)
        }
    }

    /// Works on immutable values in a utility task. ZIP contains copies of saved
    /// originals and UTF-8 text, without private absolute source paths or deletion.
    static func write(_ entries: [ShelfExportEntry], to destination: URL,
                      checkpoint: ((Checkpoint) throws -> Void)? = nil) throws {
        guard !entries.isEmpty else { throw WorkspaceError.emptyCollection }
        let files = FileManager.default
        guard !files.fileExists(atPath: destination.path) else { throw ShelfExportError.existingDestination }
        let directory = files.temporaryDirectory.appendingPathComponent("DaBin-ShelfExport-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: directory) }
        let contents = directory.appendingPathComponent("DaBin collection", isDirectory: true)
        try files.createDirectory(at: contents, withIntermediateDirectories: false)
        for entry in entries {
            guard entry.name == (entry.name as NSString).lastPathComponent, !entry.name.isEmpty,
                  entry.name != ".", entry.name != ".." else { throw ShelfExportError.failed("An item has an invalid name.") }
            let target = contents.appendingPathComponent(entry.name)
            if let source = entry.source {
                let before = try OriginalFileStorage.verify(source)
                try files.copyItem(at: source, to: target)
                let copied = try OriginalFileStorage.verify(target)
                let after = try OriginalFileStorage.verify(source)
                guard before.sha256 == copied.sha256, before.sha256 == after.sha256,
                      before.byteCount == copied.byteCount, before.byteCount == after.byteCount else { throw ShelfExportError.changedOriginal }
            } else { try Data((entry.text ?? "").utf8).write(to: target, options: .withoutOverwriting) }
        }
        let zip = directory.appendingPathComponent("Collection.zip")
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
        // Stage on the destination volume, then rename a verified ZIP. A failed
        // copy cannot leave a partial file at the user-visible destination.
        // NSSavePanel grants the chosen file, not arbitrary siblings. Foundation
        // supplies a temporary directory on that volume that the sandbox allows.
        let publication = try files.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                        appropriateFor: destination, create: true)
        defer { try? files.removeItem(at: publication) }
        let pending = publication.appendingPathComponent("Collection.zip")
        let expected = try OriginalFileStorage.verify(zip)
        try files.copyItem(at: zip, to: pending)
        let copied = try OriginalFileStorage.verify(pending)
        guard expected.sha256 == copied.sha256, expected.byteCount == copied.byteCount else { throw ShelfExportError.changedOriginal }
        try checkpoint?(.beforePublish)
        // moveItem refuses a destination concurrently created by another app.
        try files.moveItem(at: pending, to: destination)
    }
}
