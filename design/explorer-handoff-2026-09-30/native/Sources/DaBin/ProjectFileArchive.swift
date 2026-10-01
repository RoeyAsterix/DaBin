import Foundation
import CryptoKit

struct ProjectArchiveDay: Identifiable {
    let projectName: String?
    let captureDay: String
    let url: URL
    let captureCount: Int
    var id: String { (projectName.map { "project:" + $0 } ?? "unfiled:") + "/" + captureDay }
}

/// The Finder-facing library. The database and per-receipt sidecars remain the
/// index of record; this layer owns verified file moves and generated daily notes.
@MainActor final class ProjectFileArchive {
    private struct Scope: Hashable { let project: String?; let day: String }
    private struct Move: Codable {
        let version: Int
        let id: UUID
        let from: String
        let to: String
        let byteCount: Int64
        let sha256: String
    }
    private struct DocumentManifest: Codable { let version: Int; let sha256: String }
    private let archive: DailyArchive
    private let files = FileManager.default
    let root: URL
    /// Tests inject a process interruption after the new path has been committed.
    var afterMoveCommit: (() throws -> Void)?
    var beforeDocumentWrite: (() throws -> Void)?

    init(root: URL) { self.root = root; archive = DailyArchive(root: root) }

    nonisolated static func projectRelativePath(_ project: String?) -> String {
        guard let project else { return "Unfiled" }
        let safe = CaptureClassifier.storageFilename(project)
        // Stable suffixes also separate case-only and Unicode-normalization
        // collisions on the default case-insensitive macOS filesystem.
        return "Projects/\(boundedName(safe, characters: 72, bytes: 160, fallback: "Project")) — \(digest(Data(project.utf8)).prefix(12))"
    }

    nonisolated static func dayRelativePath(project: String?, day: String) throws -> String {
        let dated = try DailyArchive.dayRelativePath(captureDay: day)
        return projectRelativePath(project) + "/" + dated.dropFirst("Archive/".count)
    }

    nonisolated static func filename(id: UUID, original: String) -> String {
        let rawExtension = (original as NSString).pathExtension
        let ext = rawExtension.isEmpty ? "" : CaptureClassifier.storageFilename(rawExtension)
        let stem = CaptureClassifier.storageFilename((original as NSString).deletingPathExtension)
        let boundedExtension = boundedName(ext, characters: 24, bytes: 40, fallback: "")
        return boundedName(stem, characters: 100, bytes: 140, fallback: "Capture") + " — " + id.uuidString
            + (boundedExtension.isEmpty ? "" : "." + boundedExtension)
    }

    /// Filesystem limits apply to UTF-8 bytes, while truncation must preserve a
    /// complete user-visible character. Budgets leave room for identity suffixes.
    private nonisolated static func boundedName(_ value: String, characters: Int, bytes: Int, fallback: String) -> String {
        var result = String(value.prefix(characters))
        while result.utf8.count > bytes { result.removeLast() }
        return result.isEmpty ? fallback : result
    }

    nonisolated static func originalRelativePath(id: UUID, project: String?, day: String,
                                                kind: CaptureKind, filename original: String,
                                                deleted: Bool = false) throws -> String {
        let name = filename(id: id, original: original)
        if deleted { return ".Recently Deleted/\(id.uuidString)/\(name)" }
        let category = kind == .image || kind == .video ? "Media" : "Files"
        return try dayRelativePath(project: project, day: day) + "/\(category)/\(name)"
    }

    /// Location may still describe the former project after a retryable failed
    /// move. Ownership is bound to UUID, exact receipt date, and original filename.
    nonisolated static func ownsOriginal(_ relative: String, id: UUID, day: String,
                                        kind: CaptureKind, filename original: String) -> Bool {
        let name = filename(id: id, original: original)
        if relative == ".Recently Deleted/\(id.uuidString)/\(name)" { return true }
        guard let dated = try? DailyArchive.dayRelativePath(captureDay: day) else { return false }
        let tail = String(dated.dropFirst("Archive/".count)) + "/"
            + (kind == .image || kind == .video ? "Media" : "Files") + "/" + name
        if relative == "Unfiled/" + tail { return true }
        let components = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 7, components[0] == "Projects",
              !components[1].isEmpty, components[1] != ".", components[1] != "..",
              !components[1].contains("\\"),
              !components[1].unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return false }
        return components.dropFirst(2).joined(separator: "/") == tail
    }

    func folderURL(project: String?) throws -> URL { try archive.ensureDirectory(Self.projectRelativePath(project)) }
    func dayURL(project: String?, day: String) throws -> URL {
        try archive.safeURL(Self.dayRelativePath(project: project, day: day) + "/\(day) - Captures and Links.md")
    }

    func effectiveProject(for capture: Capture, records: [Capture]) -> String? {
        guard let parentID = capture.parentTaskID, let parent = records.first(where: { $0.id == parentID }) else { return capture.projectName }
        return parent.projectName
    }

    func documents(records: [Capture], project: String?, unfiledOnly: Bool) throws -> [ProjectArchiveDay] {
        let live = records.filter { $0.deletedAt == nil }
        let grouped = Dictionary(grouping: live) { Scope(project: effectiveProject(for: $0, records: records), day: $0.captureDay) }
        return try grouped.compactMap { scope, values in
            guard (!unfiledOnly || scope.project == nil), project == nil || scope.project == project else { return nil }
            return ProjectArchiveDay(projectName: scope.project, captureDay: scope.day,
                url: try dayURL(project: scope.project, day: scope.day), captureCount: values.count)
        }.sorted { $0.captureDay == $1.captureDay ? ($0.projectName ?? "") < ($1.projectName ?? "") : $0.captureDay > $1.captureDay }
    }

    /// Caller only overwrites its private receipt sidecars after this succeeds,
    /// leaving former project/date facts available after interruption or failure.
    func synchronize(_ changed: [Capture], records: [Capture], removingIDs: Set<UUID> = [], commit: (Capture) throws -> Void) throws {
        let failures = synchronizeResults(changed, records: records, removingIDs: removingIDs, commit: commit)
        if let failure = failures.values.first { throw CaptureStoreError.invalidOriginal(failure) }
    }

    /// Independent projects continue repairing when one destination is blocked.
    func synchronizeResults(_ changed: [Capture], records: [Capture], removingIDs: Set<UUID> = [],
                            commit: (Capture) throws -> Void) -> [UUID: String] {
        var scopes: [Scope: Capture] = [:]
        var scopeIDs: [Scope: Set<UUID>] = [:]
        var failures: [UUID: String] = [:]
        let context = Array(Dictionary((records + changed).map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest }).values)
        func addScope(_ scope: Scope, capture: Capture) {
            if let owner = scopes[scope] {
                let candidateRank = (capture.parentTaskID == nil ? 0 : 1, capture.id.uuidString)
                let ownerRank = (owner.parentTaskID == nil ? 0 : 1, owner.id.uuidString)
                if candidateRank < ownerRank { scopes[scope] = capture }
            } else { scopes[scope] = capture }
            scopeIDs[scope, default: []].insert(capture.id)
        }
        for capture in changed {
            let project = effectiveProject(for: capture, records: context)
            let current = Scope(project: project, day: capture.captureDay)
            addScope(current, capture: capture)
            do {
                if let previous = try previousSnapshot(capture) {
                    var oldProject = previous.projectName
                    if let parentID = previous.parentTaskID,
                       let parent = context.first(where: { $0.id == parentID }),
                       let oldParent = try previousSnapshot(parent) { oldProject = oldParent.projectName }
                    let old = Scope(project: oldProject, day: previous.captureDay)
                    addScope(old, capture: capture)
                }
                if !removingIDs.contains(capture.id) { try synchronizeOriginal(capture, project: project, commit: commit) }
            } catch { failures[capture.id] = error.localizedDescription }
        }
        // Include removals explicitly in changed, but obtain content exclusively
        // from the current live repository snapshot.
        for scope in scopes.keys.sorted(by: { ($0.day, $0.project ?? "") < ($1.day, $1.project ?? "") }) {
            let dayRecords = records.filter {
                $0.deletedAt == nil && !removingIDs.contains($0.id) && $0.captureDay == scope.day
                    && effectiveProject(for: $0, records: context) == scope.project
            }
            do { try writeDay(scope, records: dayRecords, allRecords: records, editOwner: scopes[scope]!) }
            catch { for id in scopeIDs[scope] ?? [] { failures[id] = error.localizedDescription } }
        }
        return failures
    }

    private func previousSnapshot(_ capture: Capture) throws -> CaptureSnapshot? {
        let relative = try DailyArchive.captureRelativePath(id: capture.id, capturedAt: capture.capturedAt,
            captureDay: capture.captureDay, utcOffset: capture.captureUTCOffsetSeconds) + "/Capture.json"
        let url = try archive.safeURL(relative)
        guard files.fileExists(atPath: url.path) else { return nil }
        try OriginalFileStorage.validateRegularFile(url)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        // A user-edited sidecar cannot become authority for file operations.
        guard let previous = try? decoder.decode(CaptureSnapshot.self, from: Data(contentsOf: url)),
              previous.id == capture.id, previous.captureDay == capture.captureDay else { return nil }
        return previous
    }

    private func owned(_ path: String, capture: Capture) -> Bool {
        let filename = capture.originalFilename ?? ""
        let old = try? DailyArchive.originalRelativePath(id: capture.id, capturedAt: capture.capturedAt,
            captureDay: capture.captureDay, utcOffset: capture.captureUTCOffsetSeconds, filename: filename)
        return path == old || path == "Originals/\(capture.id.uuidString)/\(CaptureClassifier.storageFilename(filename))"
            || Self.ownsOriginal(path, id: capture.id, day: capture.captureDay, kind: capture.kind, filename: filename)
    }

    private func synchronizeOriginal(_ capture: Capture, project: String?, commit: (Capture) throws -> Void) throws {
        guard let original = capture.originalFilename, capture.attachmentRelativePath != nil else { return }
        let journalRelative = "ExplorerMoves/\(capture.id.uuidString).json"
        let journalURL = try archive.safeURL(journalRelative)
        if files.fileExists(atPath: journalURL.path) {
            try OriginalFileStorage.validateRegularFile(journalURL)
            let move = try JSONDecoder().decode(Move.self, from: Data(contentsOf: journalURL))
            guard move.version == 1, move.id == capture.id, move.from != move.to,
                  owned(move.from, capture: capture), owned(move.to, capture: capture),
                  move.byteCount >= 0, move.sha256.count == 64,
                  move.sha256.allSatisfy(\.isHexDigit),
                  capture.attachmentRelativePath == move.from || capture.attachmentRelativePath == move.to else {
                throw CaptureStoreError.invalidManagedPath
            }
            try finish(move, capture: capture, commit: commit)
            try files.removeItem(at: journalURL)
        }
        let target = try Self.originalRelativePath(id: capture.id, project: project, day: capture.captureDay,
            kind: capture.kind, filename: original, deleted: capture.deletedAt != nil)
        guard let current = capture.attachmentRelativePath, current != target else { return }
        guard owned(current, capture: capture) else { throw CaptureStoreError.invalidManagedPath }
        let verification = try OriginalFileStorage.verify(archive.safeURL(current))
        let move = Move(version: 1, id: capture.id, from: current, to: target,
                        byteCount: verification.byteCount, sha256: verification.sha256)
        _ = try archive.ensureDirectory("ExplorerMoves")
        try JSONEncoder().encode(move).write(to: journalURL, options: .withoutOverwriting)
        try finish(move, capture: capture, commit: commit)
        try files.removeItem(at: journalURL)
    }

    private func finish(_ move: Move, capture: Capture, commit: (Capture) throws -> Void) throws {
        let source = try archive.safeURL(move.from)
        let destination = try archive.safeURL(move.to)
        let alreadyCommitted = capture.attachmentRelativePath == move.to
        if !files.fileExists(atPath: destination.path) {
            guard !alreadyCommitted, try matches(source, move) else { throw CaptureStoreError.importVerificationFailed }
            _ = try archive.ensureDirectory((move.to as NSString).deletingLastPathComponent)
            let stagingRelative = "ExplorerMoves/\(move.id.uuidString)-\(UUID().uuidString).staged"
            let staged = try archive.safeURL(stagingRelative)
            defer { try? files.removeItem(at: staged) }
            try files.copyItem(at: source, to: staged)
            guard try matches(staged, move), try matches(source, move) else { throw CaptureStoreError.importVerificationFailed }
            try files.moveItem(at: staged, to: destination)
        }
        guard try matches(destination, move) else {
            throw CaptureStoreError.invalidOriginal("A project destination contains different bytes. Both copies were preserved.")
        }
        if !alreadyCommitted {
            guard try matches(source, move) else { throw CaptureStoreError.importVerificationFailed }
            capture.relocateManagedAttachment(to: move.to)
            do { try commit(capture) }
            catch { capture.relocateManagedAttachment(to: move.from); throw error }
            try afterMoveCommit?()
        }
        if files.fileExists(atPath: source.path) {
            guard try matches(source, move) else {
                throw CaptureStoreError.invalidOriginal("The former copy changed during its move and was preserved for recovery.")
            }
            // Exact file only: never delete a shared Files/Media/project folder.
            try files.removeItem(at: archive.safeURL(move.from))
        }
    }

    private func matches(_ url: URL, _ move: Move) throws -> Bool {
        let value = try OriginalFileStorage.verify(url)
        return value.byteCount == move.byteCount && value.sha256 == move.sha256
    }

    private func writeDay(_ scope: Scope, records: [Capture], allRecords: [Capture], editOwner: Capture) throws {
        let directory = try Self.dayRelativePath(project: scope.project, day: scope.day)
        let relative = directory + "/\(scope.day) - Captures and Links.md"
        let manifestRelative = directory + "/.dabin-daily.json"
        let output = try archive.safeURL(relative)
        let manifestURL = try archive.safeURL(manifestRelative)
        let existing = try read(output)
        let priorManifest = try read(manifestURL)
        let known = priorManifest.flatMap { try? JSONDecoder().decode(DocumentManifest.self, from: $0) }
        guard !records.isEmpty || existing != nil else { return }
        _ = try archive.ensureDirectory(directory)
        let contents = Data(markdown(project: scope.project, day: scope.day, records: records,
                                     allRecords: allRecords, directory: directory).utf8)
        if let existing, existing != contents, known?.version != 1 || known?.sha256 != Self.digest(existing) {
            let edits = directory + "/Local edits"
            _ = try archive.ensureDirectory(edits)
            let saved = try archive.safeURL(edits + "/\(scope.day) - \(UUID().uuidString) - Captures and Links.md")
            try existing.write(to: saved, options: .withoutOverwriting)
            // Backups already preserve each receipt's private sidecars. Keep an
            // additional owned recovery copy there, including when this was the
            // final capture moved away from its former project/day.
            let privateEdits = try DailyArchive.captureRelativePath(id: editOwner.id,
                capturedAt: editOwner.capturedAt, captureDay: editOwner.captureDay,
                utcOffset: editOwner.captureUTCOffsetSeconds) + "/Local edits/Explorer"
            _ = try archive.ensureDirectory(privateEdits)
            try existing.write(to: archive.safeURL(privateEdits + "/" + saved.lastPathComponent), options: .withoutOverwriting)
        }
        if records.isEmpty {
            // A project move or deletion must not leave a ghost daily record.
            // An outside edit has already been preserved above before removal.
            if let existing {
                guard try read(output) == existing else { throw CaptureStoreError.invalidOriginal("The daily document changed during refresh; its contents were preserved.") }
                try files.removeItem(at: archive.safeURL(relative))
            }
            if let priorManifest, try read(manifestURL) == priorManifest { try files.removeItem(at: manifestURL) }
            return
        }
        if existing != contents {
            try beforeDocumentWrite?()
            var coordinationError: NSError?
            var writeError: Error?
            NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: output, options: .forReplacing, error: &coordinationError) { _ in
                do {
                    guard try read(output) == existing else {
                        throw CaptureStoreError.invalidOriginal("The daily document changed during refresh; retry after finishing the outside edit.")
                    }
                    try contents.write(to: archive.safeURL(relative), options: .atomic)
                } catch { writeError = error }
            }
            if let coordinationError { throw coordinationError }
            if let writeError { throw writeError }
        }
        let manifest = try JSONEncoder().encode(DocumentManifest(version: 1, sha256: Self.digest(contents)))
        if priorManifest != manifest { try manifest.write(to: archive.safeURL(manifestRelative), options: .atomic) }
    }

    private func read(_ url: URL) throws -> Data? {
        guard files.fileExists(atPath: url.path) else { return nil }
        try OriginalFileStorage.validateRegularFile(url)
        return try Data(contentsOf: url)
    }

    private func markdown(project: String?, day: String, records: [Capture], allRecords: [Capture], directory: String) -> String {
        let iso = ISO8601DateFormatter()
        var lines = ["# \(day) · \(line(project ?? "Unfiled"))", "", "Generated by DaBin. Edit captures in DaBin; outside edits are preserved in Local edits.", "",
                     "\(records.count) capture\(records.count == 1 ? "" : "s")", ""]
        for capture in records.sorted(by: { $0.capturedAt == $1.capturedAt ? $0.id.uuidString < $1.id.uuidString : $0.capturedAt < $1.capturedAt }) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: capture.captureUTCOffsetSeconds) ?? .gmt
            let clock = calendar.dateComponents([.hour, .minute, .second], from: capture.capturedAt)
            let time = String(format: "%02d:%02d:%02d", clock.hour ?? 0, clock.minute ?? 0, clock.second ?? 0)
            lines += ["## \(time) · \(line(capture.title))", "", "- Type: \(capture.kind.rawValue)\(capture.isTask ? " · Task" : "")",
                      "- Receipt: \(iso.string(from: capture.capturedAt)) · \(capture.captureTimeZoneID)", "- ID: \(capture.id.uuidString)"]
            if let app = capture.sourceApplicationName { lines.append("- Source application: \(line(app))") }
            if let path = capture.sourceFilePath { lines.append("- Source path: \(line(path))") }
            if let url = capture.sourceURL { lines.append("- Source URL: \(line(url))") }
            if let parentID = capture.parentTaskID {
                let parent = allRecords.first { $0.id == parentID }
                lines.append("- Attached to task: \(line(parent?.title ?? parentID.uuidString)) (\(parentID.uuidString))")
            }
            if let relative = capture.attachmentRelativePath {
                let components = relative.split(separator: "/").map(String.init)
                let base = directory.split(separator: "/").map(String.init)
                let common = zip(components, base).prefix { $0 == $1 }.count
                let link = Array(repeating: "..", count: base.count - common) + components.dropFirst(common)
                let encoded = link.map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "#?%()"))) ?? $0 }.joined(separator: "/")
                lines.append("- Saved file: [\(line(capture.originalFilename ?? capture.title).replacingOccurrences(of: "]", with: "\\]"))](\(encoded))")
            }
            if capture.isTask {
                lines.append("- Status: \(capture.isCompleted ? "Completed" : "Open")")
                if let plan = capture.taskPlanning {
                    if let day = plan.plannedDay { lines.append("- Planned day: \(day)") }
                    if let deadline = plan.deadline { lines.append("- Deadline: \(iso.string(from: deadline))") }
                    lines += ["- Priority: \(plan.priority.title)", "- Repeat: \(plan.recurrence.title)"]
                    if let effort = plan.effortMinutes { lines.append("- Estimate: \(effort) minutes") }
                    for step in plan.checklist { lines.append("- [\(step.isCompleted ? "x" : " ")] \(line(step.text))") }
                }
            }
            if let reminder = capture.reminderAt { lines.append("- Reminder: \(iso.string(from: reminder))") }
            if let link = capture.originalURL { lines += ["", "### Link", "", fenced(link)] }
            if let text = capture.originalText { lines += ["", "### Content", "", fenced(text)] }
            if !capture.indexedText.isEmpty { lines += ["", "### Extracted text", "", fenced(capture.indexedText)] }
            if !capture.comment.isEmpty { lines += ["", "### Comment", "", fenced(capture.comment)] }
            lines += ["", "---", ""]
        }
        if records.isEmpty { lines += ["No captures remain in this project for this day.", ""] }
        return lines.joined(separator: "\n")
    }

    private func line(_ value: String) -> String { value.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ") }
    private func fenced(_ text: String) -> String {
        let longest = text.split(whereSeparator: { $0 != "`" }).map(\.count).max() ?? 0
        let fence = String(repeating: "`", count: max(3, longest + 1))
        return "\(fence)text\n\(text)\n\(fence)"
    }
    private nonisolated static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
