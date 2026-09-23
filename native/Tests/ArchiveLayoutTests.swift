import Foundation

@main struct ArchiveLayoutTests {
    @MainActor static var checks = 0
    @MainActor static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        if try !value() { throw NSError(domain: "DaBinArchiveTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    @MainActor static func rejects(_ action: () throws -> Void, _ message: String) throws {
        var rejected = false
        do { try action() } catch { rejected = true }
        try expect(rejected, message)
    }
    static func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    @MainActor static func main() throws {
        let files = FileManager.default
        let scratch = files.temporaryDirectory.appendingPathComponent("DaBinArchiveTests-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: scratch) }
        let root = scratch.appendingPathComponent("Library", isDirectory: true)
        let archive = DailyArchive(root: root)
        let id = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!
        let capturedAt = date("2026-09-22T08:04:05Z")
        let path = try DailyArchive.captureRelativePath(id: id, capturedAt: capturedAt, captureDay: "2026-09-22", utcOffset: 10_800)
        try expect(path == "Archive/2026/09 September/22 Tuesday September 2026/11-04-05 - \(id.uuidString)", "Readable year/month/day/time hierarchy")
        try expect(try DailyArchive.dayRelativePath(captureDay: "2024-02-29") == "Archive/2024/02 February/29 Thursday February 2024", "Leap day and weekday")
        try expect(try DailyArchive.dayRelativePath(captureDay: "2027-01-01") == "Archive/2027/01 January/01 Friday January 2027", "Year boundary and chronological prefixes")
        for invalid in ["2026-02-29", "2026-02-30", "2026-04-31", "2026-00-01", "2026-13-01", "2026-01-00", "2026-1-01", "26-01-01", "0000-01-01", "2026-09-22/../bad", "２０２６-０９-２２"] {
            try rejects({ _ = try DailyArchive.dayRelativePath(captureDay: invalid) }, "Reject invalid stored day \(invalid)")
        }
        try rejects({ _ = try DailyArchive.captureRelativePath(id: id, capturedAt: capturedAt, captureDay: "2026-09-22", utcOffset: 100_000) }, "Reject invalid UTC offset")
        let localYear = try DailyArchive.captureRelativePath(id: id, capturedAt: date("2026-01-01T00:30:00Z"), captureDay: "2025-12-31", utcOffset: -28_800)
        try expect(localYear.contains("Archive/2025/12 December/31 Wednesday December 2025/16-30-00"), "Stored day and offset survive a different current timezone")
        let dstFirst = try DailyArchive.captureRelativePath(id: id, capturedAt: date("2026-11-01T05:30:00Z"), captureDay: "2026-11-01", utcOffset: -14_400)
        let dstSecond = try DailyArchive.captureRelativePath(id: UUID(), capturedAt: date("2026-11-01T06:30:00Z"), captureDay: "2026-11-01", utcOffset: -18_000)
        try expect(dstFirst.contains("01-30-00") && dstSecond.contains("01-30-00") && dstFirst != dstSecond, "Repeated DST hour remains collision free")
        let originalPath = try DailyArchive.originalRelativePath(id: id, capturedAt: capturedAt, captureDay: "2026-09-22", utcOffset: 10_800, filename: "../../private:notes.pdf")
        try expect(originalPath == path + "/Original/_.._private_notes.pdf", "Original filename loses path semantics")
        for unsafe in ["", "/etc/passwd", "../outside", "Archive/../outside", "Archive//empty", "Archive/./item", "Archive/trailing/", "Archive\\outside", "Archive/nul\0", "Archive/line\nbreak"] {
            try rejects({ _ = try archive.safeURL(unsafe) }, "Reject unsafe relative path")
        }
        let original = try archive.ensureDirectory(path + "/Original").appendingPathComponent("notes.pdf")
        let originalBytes = Data("unchanged original".utf8)
        try originalBytes.write(to: original)
        let exactText = "  Copied text\nwith `literal` content, 🟣, and a final newline.\n"
        let capture = Capture(id: id, capturedAt: capturedAt, timeZone: TimeZone(secondsFromGMT: 10_800)!, kind: .text,
                              originalText: exactText, title: "Copied text", sourceFilePath: "/Users/demo/Notes/source.txt")
        try archive.synchronize(capture)
        let record = try archive.safeURL(path)
        let contentURL = record.appendingPathComponent("Content.txt")
        let jsonURL = record.appendingPathComponent("Capture.json")
        let markdownURL = record.appendingPathComponent("Capture.md")
        try expect(try Data(contentsOf: contentURL) == Data(exactText.utf8), "Content.txt preserves original bytes without whitespace normalization")
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(CaptureSnapshot.self, from: Data(contentsOf: jsonURL))
        try expect(snapshot.id == id && snapshot.originalText == exactText && snapshot.sourceFilePath == capture.sourceFilePath, "Snapshot metadata decodes independently")
        let markdown = try String(contentsOf: markdownURL, encoding: .utf8)
        try expect(markdown.contains("Captured time: 11:04:05") && markdown.contains("Source path: /Users/demo/Notes/source.txt"), "Readable capture time and source path")
        let fixedModificationDate = date("2020-01-01T00:00:00Z")
        try files.setAttributes([.modificationDate: fixedModificationDate], ofItemAtPath: jsonURL.path)
        try archive.synchronize(capture)
        try expect((try files.attributesOfItem(atPath: jsonURL.path))[.modificationDate] as? Date == fixedModificationDate, "Identical synchronization does not rewrite files")
        try expect(!files.fileExists(atPath: record.appendingPathComponent("Local edits").path), "Unchanged synchronization creates no edit backups")
        capture.comment = "A comment from DaBin"
        try archive.synchronize(capture)
        try expect(!files.fileExists(atPath: record.appendingPathComponent("Local edits").path), "Owned generated sidecars update without needless backups")
        try expect(try String(contentsOf: markdownURL, encoding: .utf8).contains(capture.comment), "Comment changes reach Markdown")
        let external = Data("An externally edited archive note".utf8)
        try external.write(to: markdownURL)
        try archive.synchronize(capture)
        let backups = record.appendingPathComponent("Local edits")
        let preserved = try files.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)
        try expect(preserved.count == 1 && (try Data(contentsOf: preserved[0])) == external, "External edit preserved before regenerated sidecar replacement")
        try archive.synchronize(capture)
        try expect(try files.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil).count == 1, "Repeated sync does not duplicate the same edit backup")
        let manifest = record.appendingPathComponent(".dabin-generated.json")
        let malformed = Data("user-created manifest text".utf8)
        try malformed.write(to: manifest)
        try archive.synchronize(capture)
        let afterMalformed = try files.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)
        try expect(afterMalformed.count == 2 && (try afterMalformed.contains { try Data(contentsOf: $0) == malformed }), "Unknown ownership manifest is preserved")
        try expect(try Data(contentsOf: original) == originalBytes, "Sidecar synchronization never changes originals")
        let task = Capture(capturedAt: capturedAt, timeZone: TimeZone(secondsFromGMT: 0)!, kind: .task, originalText: "Make something", title: "Make something")
        task.isCompleted = true; task.reminderAt = date("2026-09-23T10:00:00Z"); task.reminderTimeZoneID = "Asia/Jerusalem"; task.notificationState = "paused"
        try archive.synchronize(task)
        let taskPath = try DailyArchive.captureRelativePath(id: task.id, capturedAt: task.capturedAt, captureDay: task.captureDay, utcOffset: task.captureUTCOffsetSeconds)
        let taskMD = try String(contentsOf: archive.safeURL(taskPath + "/Capture.md"), encoding: .utf8)
        try expect(taskMD.contains("Status: Completed") && taskMD.contains("Reminder: 2026-09-23T10:00:00Z") && taskMD.contains("Reminder state: paused"), "Task completion and reminder remain readable")
        let link = Capture(capturedAt: capturedAt, kind: .link, originalURL: "https://example.test/page?a=1&b=2", originalText: " https://example.test/page?a=1&b=2 ", title: "Example")
        try archive.synchronize(link)
        let linkPath = try DailyArchive.captureRelativePath(id: link.id, capturedAt: link.capturedAt, captureDay: link.captureDay, utcOffset: link.captureUTCOffsetSeconds)
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: archive.safeURL(linkPath + "/Link.webloc")), format: nil) as? [String: String]
        try expect(plist?["URL"] == link.originalURL, "Link file is a valid XML web location preserving URL characters")
        try expect(try String(contentsOf: archive.safeURL(linkPath + "/Content.txt"), encoding: .utf8) == link.originalText, "Link capture also keeps exact text")
        let outside = scratch.appendingPathComponent("Outside", isDirectory: true)
        try files.createDirectory(at: outside, withIntermediateDirectories: true)
        try files.createSymbolicLink(at: root.appendingPathComponent("Escape"), withDestinationURL: outside)
        try rejects({ _ = try archive.safeURL("Escape/file") }, "Reject symlink ancestor escaping root")
        try rejects({ _ = try archive.ensureDirectory("Escape/new") }, "Directory creation cannot cross symlink")
        try expect(!files.fileExists(atPath: outside.appendingPathComponent("new").path), "Symlink rejection leaves external directory untouched")
        try files.createSymbolicLink(at: root.appendingPathComponent("Dangling"), withDestinationURL: scratch.appendingPathComponent("Missing"))
        try rejects({ _ = try archive.safeURL("Dangling") }, "Reject dangling symlink")
        let outsideText = outside.appendingPathComponent("external.txt")
        try external.write(to: outsideText)
        try files.removeItem(at: markdownURL)
        try files.createSymbolicLink(at: markdownURL, withDestinationURL: outsideText)
        try rejects({ try archive.synchronize(capture) }, "Reject generated sidecar replaced by symlink")
        try expect(try Data(contentsOf: outsideText) == external, "Sidecar symlink cannot overwrite external file")
        let rootLink = scratch.appendingPathComponent("RootLink")
        try files.createSymbolicLink(at: rootLink, withDestinationURL: root)
        try rejects({ _ = try DailyArchive(root: rootLink).safeURL("Archive") }, "Reject symbolic archive root")
        try Data("file occupies folder".utf8).write(to: root.appendingPathComponent("Occupied"))
        try rejects({ _ = try archive.ensureDirectory("Occupied/child") }, "Existing regular file cannot become parent directory")
        print("PASS: \(checks) archive layout, provenance, exact-content, edit preservation, and path safety checks")
    }
}
