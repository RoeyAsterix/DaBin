import Foundation
import Combine
import UniformTypeIdentifiers

@MainActor final class CaptureStore: ObservableObject {
    @Published private(set) var captures: [Capture] = []
    @Published var error: String?
    let root: URL
    private let repository: CaptureRepository
    private let archive: DailyArchive
    private var lastArchiveWarning: String?
    private var archiveFailures: [UUID: String] = [:]
    var failureInjector: ((ImportCheckpoint) throws -> Void)?
    var removalFailureInjector: ((RemovalCheckpoint) throws -> Void)?
    private var pendingRemovalIDs: Set<UUID> = []

    init(root requestedRoot: URL? = nil) throws {
        let manager = FileManager.default
        let base = try requestedRoot ?? manager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true).appendingPathComponent("DaBin", isDirectory: true)
        try manager.createDirectory(at: base, withIntermediateDirectories: true)
        self.root = base.standardizedFileURL.resolvingSymlinksInPath()
        for directory in ["Originals", "Staging", "Imports", "Deletions"] {
            let url = self.root.appendingPathComponent(directory, isDirectory: true)
            if manager.fileExists(atPath: url.path) {
                let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
                guard values.isSymbolicLink != true, values.isDirectory == true else { throw CaptureStoreError.invalidManagedPath }
            } else { try manager.createDirectory(at: url, withIntermediateDirectories: true) }
        }
        self.repository = try CaptureRepository(root: self.root)
        self.archive = DailyArchive(root: self.root)
        try refresh()
        try recoverPendingRemovals()
        try recoverInterruptedImports()
        try refresh()
        migrateLegacyOriginals()
        synchronizeArchive(captures)
    }

    func capture(text: String, at: Date = Date(), timeZone: TimeZone = .current,
                 source: CaptureSource = .unknown,
                 receipt: CaptureReceiptContext = .manual,
                 commitGuard: () -> Bool = { true }) throws -> [Capture] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CaptureStoreError.emptyInput }
        let nonemptyLines = text.components(separatedBy: .newlines).filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let originals = nonemptyLines.count > 1 && nonemptyLines.allSatisfy({ CaptureClassifier.textKind($0) == .link })
            ? nonemptyLines : [text]
        let newCaptures = originals.map { original -> Capture in
            let value = original.trimmingCharacters(in: .whitespacesAndNewlines)
            let kind = CaptureClassifier.textKind(original)
            let title = kind == .link ? (URL(string: value)?.host ?? value) : String(value.prefix(100))
            return Capture(capturedAt: at, timeZone: timeZone, kind: kind,
                           originalURL: kind == .link ? value : nil, originalText: original, title: title,
                           sourceFilePath: source.filePath, sourceURL: source.url, receipt: receipt)
        }
        // URL-only multiline pastes commit as one transaction. Mixed prose remains one exact text original.
        guard commitGuard() else { throw CaptureStoreError.captureCancelled }
        try repository.save(newCaptures)
        captures.append(contentsOf: newCaptures)
        try refresh()
        synchronizeArchive(newCaptures)
        return newCaptures
    }

    func importFile(_ source: URL, at: Date = Date(), timeZone: TimeZone = .current,
                    originalName: String? = nil, source provenance: CaptureSource? = nil,
                    receipt: CaptureReceiptContext = .manual,
                    commitGuard: @escaping () -> Bool = { true }) async throws -> Capture {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        // Scope failure alone does not mean unreadable; resources already in the container need no grant.
        try OriginalFileStorage.validateRegularFile(source)
        let filename = originalName ?? source.lastPathComponent
        let type = (try? source.resourceValues(forKeys: [.contentTypeKey]).contentType) ?? UTType(filenameExtension: source.pathExtension)
        let origin = provenance ?? CaptureSource(filePath: source.standardizedFileURL.path)
        return try await importOriginal(filename: filename, contentType: type, at: at, timeZone: timeZone,
                                        source: origin, receipt: receipt, commitGuard: commitGuard) { destination in
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }

    func createTask(text: String, reminderAt: Date? = nil, reminderTimeZoneID: String? = nil,
                    at: Date = Date(), timeZone: TimeZone = .current) throws -> Capture {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CaptureStoreError.emptyInput }
        if let reminderAt, reminderAt <= Date() { throw CaptureStoreError.reminderNotFuture }
        let task = Capture(capturedAt: at, timeZone: timeZone, kind: .task,
                           originalText: trimmed, title: String(trimmed.prefix(100)))
        task.reminderAt = reminderAt
        task.reminderTimeZoneID = reminderAt == nil ? nil : (reminderTimeZoneID ?? timeZone.identifier)
        task.reminderRevision = reminderAt == nil ? 0 : 1
        task.notificationState = reminderAt == nil ? "none" : "pending"
        // The task and desired reminder are committed together before becoming visible.
        try failureInjector?(.beforeMetadataSave)
        try persist(task)
        captures.append(task)
        captures.sort { $0.capturedAt == $1.capturedAt ? $0.id.uuidString < $1.id.uuidString : $0.capturedAt > $1.capturedAt }
        return task
    }

    /// Converts in place. Content type and receipt identity stay immutable, so
    /// previews, originals, clipboard copies and reminders retain their meaning.
    func convertToTask(_ capture: Capture) throws {
        try requireCurrent(capture)
        guard !capture.isTask else { return }
        let previous = (capture.convertedToTask, capture.isCompleted, capture.updatedAt)
        capture.setConvertedToTask(true)
        capture.isCompleted = false
        capture.updatedAt = Date()
        do {
            try failureInjector?(.beforeMetadataSave)
            try persist(capture)
            objectWillChange.send()
        } catch {
            capture.setConvertedToTask(previous.0)
            capture.isCompleted = previous.1
            capture.updatedAt = previous.2
            throw error
        }
    }

    func setTaskCompleted(_ capture: Capture, completed: Bool) throws {
        guard capture.isTask, capture.isCompleted != completed else { return }
        guard captures.contains(where: { $0 === capture }) else {
            throw CaptureStoreError.invalidOriginal("This task is not in the current archive.")
        }
        let old = (capture.isCompleted, capture.reminderRevision, capture.notificationState, capture.updatedAt)
        capture.isCompleted = completed
        // Invalidate an in-flight schedule even when its reminder date is unchanged.
        capture.reminderRevision += 1
        capture.notificationState = completed ? "completed" : (capture.reminderAt == nil ? "none" : "pending")
        capture.updatedAt = Date()
        do { try failureInjector?(.beforeMetadataSave); try persist(capture); objectWillChange.send() }
        catch {
            capture.isCompleted = old.0; capture.reminderRevision = old.1
            capture.notificationState = old.2; capture.updatedAt = old.3
            throw error
        }
    }

    func setMinimized(_ capture: Capture, minimized: Bool) throws {
        try requireCurrent(capture)
        guard capture.isMinimized != minimized else { return }
        let previous = (capture.isMinimized, capture.updatedAt)
        capture.isMinimized = minimized
        capture.updatedAt = Date()
        do { try failureInjector?(.beforeMetadataSave); try persist(capture); objectWillChange.send() }
        catch {
            capture.isMinimized = previous.0
            capture.updatedAt = previous.1
            throw error
        }
    }

    /// The caller first cancels and awaits the capture's preview work. Notification
    /// cancellation follows this committed removal, so delayed schedules see no record.
    /// No owned files are removed until the database deletion has committed.
    func remove(_ capture: Capture) throws -> CaptureRemovalResult {
        try requireCurrent(capture)
        let journal = CaptureRemovalJournal(capture)
        let paths = try journal.ownedPaths()
        // Reject unsafe path components before modifying metadata or journal state.
        for path in paths { try validateRemovalPath(path) }
        try archive.ensureDirectory("Deletions")
        let journalURL = try safeURL("Deletions/\(capture.id.uuidString).json")
        guard !FileManager.default.fileExists(atPath: journalURL.path) else {
            throw CaptureStoreError.invalidOriginal("An earlier removal needs recovery. Reopen DaBin before trying again.")
        }
        let temporaryJournal = try safeURL("Deletions/.\(capture.id.uuidString)-\(UUID().uuidString).pending")
        do {
            try JSONEncoder().encode(journal).write(to: temporaryJournal, options: .atomic)
            try FileManager.default.moveItem(at: temporaryJournal, to: journalURL)
        } catch {
            try? FileManager.default.removeItem(at: temporaryJournal)
            throw error
        }
        pendingRemovalIDs.insert(capture.id)
        var committed = false
        do {
            try removalFailureInjector?(.afterJournal)
            try removalFailureInjector?(.beforeMetadataDelete)
            try repository.remove(id: capture.id)
            committed = true
            captures.removeAll { $0.id == capture.id }
            archiveFailures.removeValue(forKey: capture.id)
            synchronizeArchive([])
            try removalFailureInjector?(.afterMetadataDelete)
        } catch {
            // Simulated abrupt exit leaves intent for next-launch recovery.
            if case CaptureStoreError.injectedInterruption = error { throw error }
            if !committed {
                do {
                    try FileManager.default.removeItem(at: journalURL)
                    pendingRemovalIDs.remove(capture.id)
                } catch {
                    self.error = "The capture was kept. Removal preparation will be cleared when DaBin reopens."
                }
                throw error
            }
        }
        do {
            try removalFailureInjector?(.beforeFileCleanup)
            try finishRemoval(journal, journalURL: journalURL)
            try removalFailureInjector?(.afterFileCleanup)
            return CaptureRemovalResult(warning: nil)
        } catch {
            if case CaptureStoreError.injectedInterruption = error { throw error }
            let warning = "Capture removed. Some of its local files could not be removed and will be retried when DaBin opens. \(error.localizedDescription)"
            self.error = [self.error, warning].compactMap { $0 }.joined(separator: "\n")
            return CaptureRemovalResult(warning: warning)
        }
    }

    func importData(_ data: Data, filename: String, at: Date = Date(), timeZone: TimeZone = .current,
                    source: CaptureSource = .unknown,
                    receipt: CaptureReceiptContext = .manual,
                    commitGuard: @escaping () -> Bool = { true }) async throws -> Capture {
        try await importOriginal(filename: filename,
                                 contentType: UTType(filenameExtension: (filename as NSString).pathExtension),
                                 at: at, timeZone: timeZone, source: source, receipt: receipt,
                                 commitGuard: commitGuard) { destination in
            try data.write(to: destination, options: [.atomic])
        }
    }

    private func importOriginal(filename: String, contentType: UTType?, at: Date, timeZone: TimeZone,
                                source: CaptureSource, receipt: CaptureReceiptContext,
                                commitGuard: @escaping () -> Bool,
                                copy: @escaping @Sendable (URL) throws -> Void) async throws -> Capture {
        let id = UUID()
        let safeName = CaptureClassifier.storageFilename(filename)
        var journal = ImportJournal(id: id, capturedAt: at, captureDay: CaptureCalendar.dayString(at, timeZone: timeZone),
                                    timeZoneID: timeZone.identifier, utcOffset: timeZone.secondsFromGMT(for: at),
                                    originalFilename: filename, sourceFilePath: source.filePath, sourceURL: source.url,
                                    captureOriginRaw: receipt.origin.rawValue,
                                    automaticActionID: receipt.origin.isAutomatic ? receipt.automaticActionID : nil,
                                    sourceApplicationName: receipt.sourceApplicationName,
                                    sourceApplicationBundleIdentifier: receipt.sourceApplicationBundleIdentifier,
                                    relativePath: try DailyArchive.originalRelativePath(id: id, capturedAt: at, captureDay: CaptureCalendar.dayString(at, timeZone: timeZone), utcOffset: timeZone.secondsFromGMT(for: at), filename: safeName),
                                    stagingRelativePath: "Staging/\(id.uuidString)/\(safeName)",
                                    kind: CaptureClassifier.fileKind(filename: filename, contentType: contentType),
                                    contentType: contentType?.identifier, phase: "receiving")
        let staging = try safeURL(journal.stagingRelativePath)
        let original = try safeURL(journal.relativePath)
        let journalURL = root.appendingPathComponent("Imports/\(id.uuidString).json")
        var inserted: Capture?
        var committed = false
        do {
            try FileManager.default.createDirectory(at: staging.deletingLastPathComponent(), withIntermediateDirectories: false)
            try writeJournal(journal, at: journalURL)
            try failureInjector?(.beforeCopy)
            let verification = try await Task.detached(priority: .utility) {
                try copy(staging)
                return try OriginalFileStorage.verify(staging)
            }.value
            journal.byteCount = verification.byteCount
            journal.sha256 = verification.sha256
            journal.phase = "copied"
            try writeJournal(journal, at: journalURL)
            try failureInjector?(.afterCopy)
            try archive.ensureDirectory((journal.relativePath as NSString).deletingLastPathComponent)
            try FileManager.default.moveItem(at: staging, to: original)
            journal.phase = "moved"
            try writeJournal(journal, at: journalURL)
            try failureInjector?(.afterMove)
            guard commitGuard() else { throw CaptureStoreError.captureCancelled }
            let capture = model(for: journal)
            inserted = capture
            try failureInjector?(.beforeMetadataSave)
            try persist(capture)
            committed = true
            captures.append(capture)
            try failureInjector?(.afterMetadataSave)
            cleanupCompleted(journal, journalURL: journalURL)
            try refresh()
            return capture
        } catch {
            // An interruption fixture models abrupt process exit, leaving the journal for next launch.
            if case CaptureStoreError.injectedInterruption = error { throw error }
            if !committed {
                compensateOwnedImport(journal, journalURL: journalURL)
                throw error
            }
            // A committed original remains successful even if housekeeping fails afterwards.
            self.error = "The capture was saved. Import cleanup will be retried when DaBin opens."
            try refresh()
            return inserted!
        }
    }

    func update(_ capture: Capture, comment: String, reminderAt: Date?, reminderTimeZoneID: String?) throws {
        try requireCurrent(capture)
        let old = (capture.comment, capture.reminderAt, capture.reminderTimeZoneID,
                   capture.reminderRevision, capture.notificationState, capture.updatedAt)
        let zone = reminderAt == nil ? nil : reminderTimeZoneID
        if capture.reminderAt != reminderAt || capture.reminderTimeZoneID != zone {
            capture.reminderRevision += 1
            capture.notificationState = capture.isTask && capture.isCompleted ? "completed" : (reminderAt == nil ? "none" : "pending")
        }
        capture.comment = comment
        capture.reminderAt = reminderAt
        capture.reminderTimeZoneID = zone
        capture.updatedAt = Date()
        do { try persist(capture); objectWillChange.send() }
        catch {
            capture.comment = old.0; capture.reminderAt = old.1; capture.reminderTimeZoneID = old.2
            capture.reminderRevision = old.3; capture.notificationState = old.4; capture.updatedAt = old.5
            throw error
        }
    }

    func save() throws {
        try save(captures: captures)
    }

    /// Service updates touch only their changed records. Saving a preview or
    /// notification must not rewrite every capture in a long-lived archive.
    func save(captures records: [Capture]) throws {
        guard !records.isEmpty else { return }
        for capture in records { try requireCurrent(capture) }
        try repository.save(records)
        objectWillChange.send()
        synchronizeArchive(records)
    }

    private func persist(_ capture: Capture) throws {
        guard !pendingRemovalIDs.contains(capture.id) else {
            throw CaptureStoreError.invalidOriginal("This capture is being removed.")
        }
        try repository.save([capture])
        // Metadata is already durable. A folder-write failure is retryable and
        // must not turn a successful capture into a misleading failed save.
        synchronizeArchive([capture])
    }

    func refresh() throws {
        let existing = Dictionary(uniqueKeysWithValues: captures.map { ($0.id, $0) })
        captures = try repository.load().map { existing[$0.id] ?? Capture(snapshot: $0) }
            .sorted { $0.capturedAt == $1.capturedAt ? $0.id.uuidString < $1.id.uuidString : $0.capturedAt > $1.capturedAt }
    }

    var archiveRoot: URL { root.appendingPathComponent("Archive", isDirectory: true) }

    func prepareArchiveFolder(for capture: Capture? = nil) throws -> URL {
        if let capture {
            try requireCurrent(capture)
            try archive.synchronize(capture)
            guard let url = archiveURL(for: capture) else { throw CaptureStoreError.invalidManagedPath }
            return url
        }
        return try archive.ensureDirectory("Archive")
    }

    func archiveURL(for capture: Capture) -> URL? {
        guard let path = try? DailyArchive.captureRelativePath(id: capture.id, capturedAt: capture.capturedAt,
            captureDay: capture.captureDay, utcOffset: capture.captureUTCOffsetSeconds) else { return nil }
        return try? safeURL(path)
    }

    func managedURL(for capture: Capture) -> URL? {
        guard let relative = capture.attachmentRelativePath,
              isOwnedOriginalPath(relative, id: capture.id, capturedAt: capture.capturedAt,
                  captureDay: capture.captureDay, utcOffset: capture.captureUTCOffsetSeconds,
                  filename: capture.originalFilename ?? ""),
              let url = try? safeURL(relative), (try? OriginalFileStorage.validateRegularFile(url)) != nil else { return nil }
        return url
    }

    func previewURL(for capture: Capture) -> URL? {
        guard let relative = capture.thumbnailRelativePath,
              relative == "Previews/\(capture.id.uuidString)/thumbnail.png" else { return nil }
        return try? safeURL(relative)
    }

    private func isOwnedOriginalPath(_ relative: String, id: UUID, capturedAt: Date,
                                    captureDay: String, utcOffset: Int, filename: String) -> Bool {
        let legacy = "Originals/\(id.uuidString)/\(CaptureClassifier.storageFilename(filename))"
        let current = try? DailyArchive.originalRelativePath(id: id, capturedAt: capturedAt,
            captureDay: captureDay, utcOffset: utcOffset, filename: filename)
        return relative == legacy || relative == current
    }

    private func safeURL(_ relative: String) throws -> URL { try archive.safeURL(relative) }

    private func requireCurrent(_ capture: Capture) throws {
        guard captures.contains(where: { $0 === capture }), !pendingRemovalIDs.contains(capture.id) else {
            throw CaptureStoreError.invalidOriginal("This capture is no longer in the current archive.")
        }
    }

    /// Recovery runs before import recovery. A retained intent blocks any import
    /// receipt with the same ID even when file cleanup needs another retry.
    private func recoverPendingRemovals() throws {
        let directory = try safeURL("Deletions")
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        pendingRemovalIDs = Set(urls.compactMap { UUID(uuidString: $0.deletingPathExtension().lastPathComponent) })
        for url in urls {
            do {
                _ = try safeURL("Deletions/\(url.lastPathComponent)")
                try OriginalFileStorage.validateRegularFile(url)
                let journal = try JSONDecoder().decode(CaptureRemovalJournal.self, from: Data(contentsOf: url))
                guard url.lastPathComponent == "\(journal.id.uuidString).json" else { throw CaptureStoreError.invalidManagedPath }
                _ = try journal.ownedPaths()
                if captures.contains(where: { $0.id == journal.id }) {
                    // A crash before metadata commit leaves every file intact.
                    try FileManager.default.removeItem(at: url)
                    pendingRemovalIDs.remove(journal.id)
                } else {
                    try finishRemoval(journal, journalURL: url)
                }
            } catch {
                let warning = "A capture removal could not finish safely. Its remaining local files were preserved for retry. \(error.localizedDescription)"
                self.error = [self.error, warning].compactMap { $0 }.joined(separator: "\n")
            }
        }
    }

    private func finishRemoval(_ journal: CaptureRemovalJournal, journalURL: URL) throws {
        var firstFailure: Error?
        for relative in try journal.ownedPaths() {
            do {
                try validateRemovalPath(relative)
                let url = try safeURL(relative)
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
            } catch { if firstFailure == nil { firstFailure = error } }
        }
        if let firstFailure { throw firstFailure }
        _ = try safeURL("Deletions/\(journal.id.uuidString).json")
        try FileManager.default.removeItem(at: journalURL)
        pendingRemovalIDs.remove(journal.id)
    }

    private func validateRemovalPath(_ relative: String) throws {
        let url = try safeURL(relative)
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) else { return }
        if relative.hasPrefix("Imports/") {
            try OriginalFileStorage.validateRegularFile(url)
        } else if !directory.boolValue {
            // A file obstructing an owned folder is not a normal DaBin object.
            throw CaptureStoreError.invalidManagedPath
        }
    }

    private func synchronizeArchive(_ records: [Capture]) {
        for capture in records {
            do { try archive.synchronize(capture); archiveFailures.removeValue(forKey: capture.id) }
            catch { archiveFailures[capture.id] = error.localizedDescription }
        }
        if let previous = lastArchiveWarning, let current = error {
            let remaining = current.replacingOccurrences(of: previous, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            error = remaining.isEmpty ? nil : remaining
        }
        lastArchiveWarning = nil
        if let first = archiveFailures.values.first {
            let warning = "Saved locally. \(archiveFailures.count) capture folder(s) could not be refreshed and will be retried when DaBin opens. \(first)"
            lastArchiveWarning = warning
            error = [error, warning].compactMap { $0 }.joined(separator: "\n")
        }
    }

    private func migrateLegacyOriginals() {
        for capture in captures {
            guard let previous = capture.attachmentRelativePath, previous.hasPrefix("Originals/") else { continue }
            do {
                guard let source = managedURL(for: capture) else { throw CaptureStoreError.importVerificationFailed }
                let relative = try DailyArchive.originalRelativePath(id: capture.id, capturedAt: capture.capturedAt,
                    captureDay: capture.captureDay, utcOffset: capture.captureUTCOffsetSeconds,
                    filename: capture.originalFilename ?? source.lastPathComponent)
                let destination = try safeURL(relative)
                let verification = try OriginalFileStorage.verify(source)
                try archive.ensureDirectory((relative as NSString).deletingLastPathComponent)
                if !FileManager.default.fileExists(atPath: destination.path) {
                    // Copy before committing the new path. Original bytes stay in
                    // place as a safety copy, including across interrupted upgrades.
                    let temporaryDirectory = "MigrationStaging/\(capture.id.uuidString)"
                    try archive.ensureDirectory(temporaryDirectory)
                    let temporary = try safeURL(temporaryDirectory + "/" + UUID().uuidString + ".original")
                    try FileManager.default.copyItem(at: source, to: temporary)
                    let copied = try OriginalFileStorage.verify(temporary)
                    guard copied.byteCount == verification.byteCount, copied.sha256 == verification.sha256 else {
                        throw CaptureStoreError.importVerificationFailed
                    }
                    try FileManager.default.moveItem(at: temporary, to: destination)
                }
                let installed = try OriginalFileStorage.verify(destination)
                guard installed.byteCount == verification.byteCount, installed.sha256 == verification.sha256 else {
                    throw CaptureStoreError.invalidOriginal("A dated-folder destination conflicts with the original; both were preserved.")
                }
                capture.relocateManagedAttachment(to: relative)
                do { try repository.save([capture]) }
                catch { capture.relocateManagedAttachment(to: previous); throw error }
            } catch {
                let warning = "An original could not be organized into its date folder. Its existing copy was preserved. \(error.localizedDescription)"
                self.error = [self.error, warning].compactMap { $0 }.joined(separator: "\n")
            }
        }
    }

    private func writeJournal(_ journal: ImportJournal, at url: URL) throws {
        try JSONEncoder().encode(journal).write(to: url, options: .atomic)
    }

    private func model(for journal: ImportJournal) -> Capture {
        Capture(id: journal.id, capturedAt: journal.capturedAt,
                timeZone: TimeZone(identifier: journal.timeZoneID) ?? TimeZone(secondsFromGMT: journal.utcOffset) ?? TimeZone(secondsFromGMT: 0)!,
                kind: journal.kind, attachmentRelativePath: journal.relativePath,
                originalFilename: journal.originalFilename, contentType: journal.contentType,
                byteCount: journal.byteCount, title: journal.originalFilename,
                captureDay: journal.captureDay, captureTimeZoneID: journal.timeZoneID,
                captureUTCOffsetSeconds: journal.utcOffset,
                sourceFilePath: journal.sourceFilePath, sourceURL: journal.sourceURL,
                receipt: CaptureReceiptContext(
                    origin: CaptureOrigin(rawValue: journal.captureOriginRaw ?? "") ?? .manual,
                    automaticActionID: journal.automaticActionID,
                    sourceApplicationName: journal.sourceApplicationName,
                    sourceApplicationBundleIdentifier: journal.sourceApplicationBundleIdentifier))
    }

    private func cleanupCompleted(_ journal: ImportJournal, journalURL: URL) {
        if let staging = try? safeURL("Staging/\(journal.id.uuidString)") { try? FileManager.default.removeItem(at: staging) }
        try? FileManager.default.removeItem(at: journalURL)
    }

    private func compensateOwnedImport(_ journal: ImportJournal, journalURL: URL) {
        var cleanupFailed = false
        for relative in ["Staging/\(journal.id.uuidString)", (journal.relativePath as NSString).deletingLastPathComponent] {
            do {
                let url = try safeURL(relative)
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            } catch { cleanupFailed = true }
        }
        if !cleanupFailed { try? FileManager.default.removeItem(at: journalURL) }
        else { self.error = "An interrupted import was preserved for recovery. Your existing captures are unchanged." }
    }

    private func recoverInterruptedImports() throws {
        let manager = FileManager.default
        let journalFiles = try manager.contentsOfDirectory(at: root.appendingPathComponent("Imports"),
                                                            includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        var warnings: [String] = []
        for journalURL in journalFiles {
            do {
                if let id = UUID(uuidString: journalURL.deletingPathExtension().lastPathComponent), pendingRemovalIDs.contains(id) {
                    warnings.append("A pending removal blocks recovery of the deleted capture's import receipt.")
                    continue
                }
                try OriginalFileStorage.validateRegularFile(journalURL)
                let journal = try JSONDecoder().decode(ImportJournal.self, from: Data(contentsOf: journalURL))
                // Treat journal paths as untrusted persisted input; IDs bind ownership and filenames.
                guard journalURL.lastPathComponent == "\(journal.id.uuidString).json",
                      isOwnedOriginalPath(journal.relativePath, id: journal.id, capturedAt: journal.capturedAt,
                          captureDay: journal.captureDay, utcOffset: journal.utcOffset, filename: journal.originalFilename),
                      journal.stagingRelativePath == "Staging/\(journal.id.uuidString)/\(CaptureClassifier.storageFilename(journal.originalFilename))" else {
                    throw CaptureStoreError.invalidManagedPath
                }
                let original = try safeURL(journal.relativePath)
                let staging = try safeURL(journal.stagingRelativePath)
                if let capture = captures.first(where: { $0.id == journal.id }) {
                    guard capture.attachmentRelativePath == journal.relativePath,
                          managedURL(for: capture) != nil else { throw CaptureStoreError.importVerificationFailed }
                    cleanupCompleted(journal, journalURL: journalURL)
                    continue
                }
                guard let expectedSize = journal.byteCount, let expectedHash = journal.sha256 else {
                    warnings.append("An incomplete import remains in Staging; its bytes have been preserved.")
                    continue
                }
                let candidate = manager.fileExists(atPath: original.path) ? original : staging
                let verification = try OriginalFileStorage.verify(candidate)
                guard verification.byteCount == expectedSize, verification.sha256 == expectedHash else {
                    throw CaptureStoreError.importVerificationFailed
                }
                if candidate == staging {
                    try archive.ensureDirectory((journal.relativePath as NSString).deletingLastPathComponent)
                    try manager.moveItem(at: staging, to: original)
                }
                let capture = model(for: journal)
                try persist(capture)
                captures.append(capture)
                cleanupCompleted(journal, journalURL: journalURL)
            } catch {
                warnings.append("An interrupted import could not be recovered automatically. Its files were preserved. \(error.localizedDescription)")
            }
        }
        // Unknown files are never deleted. They may be the only surviving copy after an interrupted import.
        let remainingJournalIDs = Set((try manager.contentsOfDirectory(at: root.appendingPathComponent("Imports"), includingPropertiesForKeys: nil)).map { $0.deletingPathExtension().lastPathComponent })
        let savedIDs = Set(captures.map { $0.id.uuidString })
        for directory in ["Staging", "Originals"] {
            let children = try manager.contentsOfDirectory(at: root.appendingPathComponent(directory), includingPropertiesForKeys: nil)
            let unknown = children.filter {
                !remainingJournalIDs.contains($0.lastPathComponent) && (directory == "Staging" || !savedIDs.contains($0.lastPathComponent))
            }
            if !unknown.isEmpty {
                warnings.append("Unclaimed files in \(directory) were preserved for manual recovery.")
            }
        }
        if !warnings.isEmpty { error = [error, warnings.joined(separator: "\n")].compactMap { $0 }.joined(separator: "\n") }
    }
}
