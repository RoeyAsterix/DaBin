import Foundation
import CryptoKit

/// Integration checks use only disposable stores. No user archive, clipboard,
/// network, notification permission, or GUI is involved.
@main struct ArchiveStoreTests {
    @MainActor static var checks = 0
    static let files = FileManager.default

    @MainActor static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        if try !value() {
            throw NSError(domain: "DaBinArchiveStoreTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    static func instant(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    static func bytes(_ url: URL) throws -> Data { try Data(contentsOf: url) }
    static func hash(_ value: Data) -> String { SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined() }

    @MainActor static func folder(_ store: CaptureStore, _ capture: Capture) throws -> URL {
        guard let url = store.archiveURL(for: capture) else {
            throw NSError(domain: "DaBinArchiveStoreTests", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Capture has no safe archive folder"])
        }
        return url
    }

    @MainActor static func readable(_ store: CaptureStore, _ capture: Capture) throws -> CaptureSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CaptureSnapshot.self,
                                  from: bytes(folder(store, capture).appendingPathComponent("Capture.json")))
    }

    @MainActor static func main() async throws {
        let root = files.temporaryDirectory.appendingPathComponent("DaBinArchiveStoreTests-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }
        try await currentArchive(root.appendingPathComponent("current"))
        try legacyMigration(root.appendingPathComponent("legacy"), conflictingDestination: false)
        try legacyMigration(root.appendingPathComponent("legacy-conflict"), conflictingDestination: true)
        try await journalRecovery(root.appendingPathComponent("journals"))
        try mirrorFailure(root.appendingPathComponent("mirror-failure"))
        print("PASS: \(checks) archive-store integration assertions; dated originals, readable records, updates, migration, legacy/current recovery, and retryable mirror failure.")
    }

    @MainActor static func currentArchive(_ root: URL) async throws {
        var store: CaptureStore? = try CaptureStore(root: root)
        // The instant is still Monday in UTC; this capture belongs to Tuesday in its receipt zone.
        let receipt = instant("2026-09-21T22:12:34Z")
        let zone = TimeZone(secondsFromGMT: 10_800)!
        let content = "  First line\r\nSecond line\tעברית 🟣\n\n"
        let source = CaptureSource(filePath: "/Users/example/Research/Studio notes.docx", url: "https://example.invalid/research")
        let note = try store!.capture(text: content, at: receipt, timeZone: zone, source: source)[0]
        let noteFolder = try folder(store!, note)
        try expect(note.captureDay == "2026-09-22", "Receipt date is retained across UTC midnight")
        try expect(noteFolder.path.contains("/Archive/2026/09 September/"), "Year and chronological named month contain the primary archive")
        try expect(noteFolder.lastPathComponent == "01-12-34 - \(note.id.uuidString)", "Record folder uses the receipt clock and unique ID")
        try expect(try bytes(noteFolder.appendingPathComponent("Content.txt")) == Data(content.utf8), "Text sidecar preserves exact whitespace, newlines, Unicode, and bytes")
        let initial = try readable(store!, note)
        try expect(initial.originalText == content && initial.sourceFilePath == source.filePath && initial.sourceURL == source.url,
                   "Readable record preserves original content and supplied provenance")

        let reminder = instant("2099-01-02T03:04:05Z")
        try store!.update(note, comment: "Remember the lighting\nSecond comment line", reminderAt: reminder, reminderTimeZoneID: "Asia/Jerusalem")
        let updated = try readable(store!, note)
        try expect(updated.comment == note.comment && updated.reminderAt == reminder && updated.reminderTimeZoneID == "Asia/Jerusalem",
                   "Comment and desired reminder are mirrored immediately")
        try expect(updated.captureDay == initial.captureDay && updated.capturedAt == initial.capturedAt && noteFolder == folder(store!, note),
                   "Editing and reminders never refile a capture")
        note.notificationState = "scheduled"
        note.previewState = "ready"
        note.previewDescription = "A local preview description"
        try store!.save()
        let serviced = try readable(store!, note)
        try expect(serviced.notificationState == "scheduled" && serviced.previewState == "ready" && serviced.previewDescription == note.previewDescription,
                   "Generic service saves also mirror notification and preview changes")

        let linkText = "  https://example.invalid/notes?q=purple  "
        let link = try store!.capture(text: linkText, at: receipt, timeZone: zone)[0]
        let linkFolder = try folder(store!, link)
        let bookmark = try PropertyListSerialization.propertyList(from: bytes(linkFolder.appendingPathComponent("Link.webloc")), options: [], format: nil) as! [String: String]
        try expect(bookmark["URL"] == "https://example.invalid/notes?q=purple", "Local link bookmark retains the original URL")
        try expect(try bytes(linkFolder.appendingPathComponent("Content.txt")) == Data(linkText.utf8), "Link capture also retains the exact pasted text")

        let original = Data("{\"the-user-original\":true}\n".utf8)
        let file = try await store!.importData(original, filename: "Capture.json", at: receipt, timeZone: zone, source: source)
        let fileFolder = try folder(store!, file)
        guard let managed = store!.managedURL(for: file) else { throw CaptureStoreError.importVerificationFailed }
        try expect(managed == fileFolder.appendingPathComponent("Original/Capture.json"), "An original named Capture.json is isolated from its metadata")
        try expect(try bytes(managed) == original && readable(store!, file).id == file.id, "Original and generated record retain independent valid content")
        let duplicate = try await store!.importData(original, filename: "Capture.json", at: receipt, timeZone: zone)
        try expect(file.id != duplicate.id && store!.managedURL(for: duplicate) != managed, "Identical filenames and receipt times never overwrite each other")
        try expect(file.sourceFilePath == source.filePath && file.sourceFilePath != managed.path, "Storage location does not replace source provenance")

        let task = try store!.createTask(text: "Prepare tomorrow’s notes", reminderAt: reminder, reminderTimeZoneID: "UTC", at: receipt, timeZone: zone)
        try store!.setTaskCompleted(task, completed: true)
        let finished = try readable(store!, task)
        try expect(finished.isCompleted == true && finished.notificationState == "completed" && finished.reminderAt == reminder,
                   "Completed task and retained reminder are represented in readable metadata")
        let taskMarkdown = try String(contentsOf: folder(store!, task).appendingPathComponent("Capture.md"), encoding: .utf8)
        try expect(taskMarkdown.contains("- Status: Completed"), "Human-readable task record displays completion")
        try store!.setTaskCompleted(task, completed: false)
        try expect(try readable(store!, task).isCompleted == false, "Reopening a task refreshes its readable state")

        // User edits to generated files must be preserved before a later app save replaces them.
        let edited = Data("My hand-edited daily note\n".utf8)
        try edited.write(to: noteFolder.appendingPathComponent("Capture.md"), options: .atomic)
        try store!.update(note, comment: "App comment after a local edit", reminderAt: reminder, reminderTimeZoneID: "UTC")
        let editCopies = try files.contentsOfDirectory(at: noteFolder.appendingPathComponent("Local edits"), includingPropertiesForKeys: nil)
        try expect(try editCopies.contains { try bytes($0) == edited }, "Externally edited sidecar survives replacement as a local backup")
        try expect(try readable(store!, note).comment == "App comment after a local edit", "Metadata remains current after preserving an edited sidecar")

        let ids = Set(store!.captures.map(\.id))
        store = nil
        let reopened = try CaptureStore(root: root)
        try expect(Set(reopened.captures.map(\.id)) == ids, "Reopening mirrors records without duplicates")
        let reopenedNote = reopened.captures.first { $0.id == note.id }!
        let reopenedFile = reopened.captures.first { $0.id == file.id }!
        try expect(reopenedNote.originalText == content && (try readable(reopened, reopenedNote)).comment == reopenedNote.comment,
                   "Original and edited text survive the transactional-store reopen")
        try expect(try bytes(reopened.managedURL(for: reopenedFile)!) == original, "Dated original remains readable after relaunch")
    }

    @MainActor static func legacyMigration(_ root: URL, conflictingDestination: Bool) throws {
        let id = UUID()
        let receipt = instant("2026-12-31T23:30:00Z")
        let zone = TimeZone(secondsFromGMT: 7200)!
        let relative = "Originals/\(id.uuidString)/saved.pdf"
        let original = Data("legacy original bytes\n".utf8)
        let legacyURL = root.appendingPathComponent(relative)
        try files.createDirectory(at: legacyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try original.write(to: legacyURL)
        let legacy = Capture(id: id, capturedAt: receipt, timeZone: zone, kind: .pdf,
                             attachmentRelativePath: relative, originalFilename: "saved.pdf", byteCount: Int64(original.count),
                             title: "Saved PDF", sourceFilePath: "/Users/example/Legacy/saved.pdf")
        legacy.comment = "Retain this legacy comment"
        let datedRelative = try DailyArchive.originalRelativePath(id: id, capturedAt: receipt, captureDay: legacy.captureDay,
                                                                 utcOffset: legacy.captureUTCOffsetSeconds, filename: "saved.pdf")
        let datedURL = root.appendingPathComponent(datedRelative)
        let conflict = Data("a distinct edited destination\n".utf8)
        if conflictingDestination {
            try files.createDirectory(at: datedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try conflict.write(to: datedURL)
        }
        do { try CaptureRepository(root: root).save([legacy]) }
        var migrated: CaptureStore? = try CaptureStore(root: root)
        let capture = migrated!.captures[0]
        try expect(migrated!.captures.count == 1 && capture.id == id, "Legacy migration retains capture identity")
        try expect(try hash(bytes(legacyURL)) == hash(original), "Legacy safety original remains byte-identical")
        try expect(capture.captureDay == "2027-01-01" && capture.capturedAt == receipt && capture.sourceFilePath == legacy.sourceFilePath && capture.comment == legacy.comment,
                   "Migration preserves day, instant, provenance, and comments")
        if conflictingDestination {
            try expect(capture.attachmentRelativePath == relative && migrated!.managedURL(for: capture) == legacyURL,
                       "Conflicting destination never commits a false attachment relocation")
            try expect(try bytes(datedURL) == conflict && migrated!.error != nil, "Conflicting destination is preserved and surfaced")
            try expect(try readable(migrated!, capture).attachmentRelativePath == relative, "Readable metadata continues to reference the usable legacy original")
        } else {
            try expect(capture.attachmentRelativePath == datedRelative && migrated!.managedURL(for: capture) == datedURL,
                       "Legacy record commits its verified dated attachment path")
            try expect(try hash(bytes(datedURL)) == hash(original), "Migrated dated original matches the source SHA-256")
            try expect(try readable(migrated!, capture).attachmentRelativePath == datedRelative, "Readable metadata uses the migrated primary path")
        }
        migrated = nil
        let reopened = try CaptureStore(root: root)
        try expect(reopened.captures.count == 1 && reopened.captures[0].attachmentRelativePath == (conflictingDestination ? relative : datedRelative),
                   "Migration and conflicts remain idempotent across relaunch")
        try expect(try bytes(legacyURL) == original, "Repeated migration never removes the retained original")
        if conflictingDestination { try expect(try bytes(datedURL) == conflict, "Repeated conflict handling never replaces the edited destination") }
    }

    @MainActor static func journalRecovery(_ parent: URL) async throws {
        for legacyLayout in [false, true] {
            for checkpoint in [ImportCheckpoint.afterCopy, .afterMove] {
                let root = parent.appendingPathComponent("\(legacyLayout ? "legacy" : "dated")-\(checkpoint.rawValue)")
                var interrupted: CaptureStore? = try CaptureStore(root: root)
                interrupted!.failureInjector = { if $0 == checkpoint { throw CaptureStoreError.injectedInterruption } }
                let original = Data("recover one original safely\n".utf8)
                do {
                    _ = try await interrupted!.importData(original, filename: "receipt.txt", at: instant("2026-09-21T22:12:34Z"),
                                                         timeZone: TimeZone(secondsFromGMT: 10_800)!, source: CaptureSource(filePath: "/Users/example/receipt.txt"))
                    throw NSError(domain: "Expected interruption", code: 1)
                } catch CaptureStoreError.injectedInterruption { }
                interrupted = nil
                let journalFiles = try files.contentsOfDirectory(at: root.appendingPathComponent("Imports"), includingPropertiesForKeys: nil)
                try expect(journalFiles.count == 1, "Interrupted import retains exactly one journal")
                let journalURL = journalFiles[0]
                var journal = try JSONSerialization.jsonObject(with: bytes(journalURL)) as! [String: Any]
                let id = journal["id"] as! String
                if legacyLayout {
                    let newPath = journal["relativePath"] as! String
                    let oldPath = "Originals/\(id)/receipt.txt"
                    let oldURL = root.appendingPathComponent(oldPath)
                    let newURL = root.appendingPathComponent(newPath)
                    if files.fileExists(atPath: newURL.path) {
                        try files.createDirectory(at: oldURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try files.moveItem(at: newURL, to: oldURL)
                    }
                    journal["relativePath"] = oldPath
                    // The initial app's journal omitted provenance fields.
                    journal.removeValue(forKey: "sourceFilePath")
                    journal.removeValue(forKey: "sourceURL")
                    try JSONSerialization.data(withJSONObject: journal).write(to: journalURL, options: .atomic)
                }
                var recovered: CaptureStore? = try CaptureStore(root: root)
                try expect(recovered!.captures.count == 1 && recovered!.captures[0].id.uuidString == id, "\(legacyLayout ? "Legacy" : "Dated") \(checkpoint) recovery commits one identity")
                let capture = recovered!.captures[0]
                try expect(capture.captureDay == "2026-09-22" && capture.attachmentRelativePath?.hasPrefix("Archive/2026/") == true,
                           "Recovered import uses its immutable receipt day in dated storage")
                try expect(try bytes(recovered!.managedURL(for: capture)!) == original, "Journal recovery verifies and retains original bytes")
                try expect(capture.sourceFilePath == (legacyLayout ? nil : "/Users/example/receipt.txt"), "Journal recovery preserves known provenance without inventing missing history")
                try expect(try readable(recovered!, capture).id == capture.id, "Recovery also creates the readable record")
                try expect(try files.contentsOfDirectory(atPath: root.appendingPathComponent("Imports").path).isEmpty, "Successful recovery removes its completed journal")
                recovered = nil
                let reopened = try CaptureStore(root: root)
                try expect(reopened.captures.count == 1 && reopened.captures[0].id.uuidString == id, "Second recovery launch does not duplicate the capture")
            }
        }
    }

    @MainActor static func mirrorFailure(_ root: URL) throws {
        var store: CaptureStore? = try CaptureStore(root: root)
        let obstruction = root.appendingPathComponent("Archive")
        let preserved = Data("Do not delete this conflicting user file".utf8)
        try preserved.write(to: obstruction)
        let note = try store!.capture(text: "The database commit still succeeds")[0]
        try expect(store!.captures.count == 1 && store!.error != nil, "Mirror failure keeps a successful capture and reports a warning")
        try store!.update(note, comment: "Persist this comment despite the obstruction", reminderAt: nil, reminderTimeZoneID: nil)
        note.notificationState = "none"
        note.previewDescription = "Generic service change survives"
        try store!.save()
        let task = try store!.createTask(text: "Keep this completed task")
        try store!.setTaskCompleted(task, completed: true)
        try expect(task.isCompleted && store!.captures.count == 2, "Mirror failure does not falsely roll back a committed task or completion")
        try expect(try bytes(obstruction) == preserved, "Mirror failure never replaces the conflicting user file")
        let ids = Set(store!.captures.map(\.id))
        store = nil
        var blockedReopen: CaptureStore? = try CaptureStore(root: root)
        try expect(Set(blockedReopen!.captures.map(\.id)) == ids && blockedReopen!.error != nil, "Blocked relaunch retains all committed identities and exposes the unresolved archive warning")
        let saved = blockedReopen!.captures.first { $0.id == note.id }!
        try expect(saved.comment == "Persist this comment despite the obstruction" && saved.previewDescription == "Generic service change survives",
                   "Edits and generic saves were durable despite readable-file failure")
        try expect(blockedReopen!.captures.first { $0.id == task.id }!.isCompleted, "Task completion remains durable despite mirror failure")
        blockedReopen = nil
        try files.moveItem(at: obstruction, to: root.appendingPathComponent("preserved-user-file.txt"))
        let repaired = try CaptureStore(root: root)
        try expect(Set(repaired.captures.map(\.id)) == ids && repaired.error == nil, "Removing the obstruction repairs the archive without duplicates or stale warning")
        let repairedNote = repaired.captures.first { $0.id == note.id }!
        let repairedTask = repaired.captures.first { $0.id == task.id }!
        try expect(try readable(repaired, repairedNote).comment == saved.comment, "Relaunch regenerates the latest readable comment")
        try expect(try readable(repaired, repairedTask).isCompleted == true, "Relaunch regenerates the completed task record")
        try expect(try bytes(root.appendingPathComponent("preserved-user-file.txt")) == preserved, "Repair leaves the conflicting user's file intact")
    }
}
