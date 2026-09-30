import Foundation
import Combine
import UniformTypeIdentifiers

@MainActor final class CaptureStore: ObservableObject {
    @Published private(set) var captures: [Capture] = []
    @Published private(set) var trashedCaptures: [Capture] = []
    @Published var error: String?
    let root: URL
    private let repository: CaptureRepository
    private let archive: DailyArchive
    private var lastArchiveWarning: String?
    private var archiveFailures: [UUID: String] = [:]
    var failureInjector: ((ImportCheckpoint) throws -> Void)?
    var removalFailureInjector: ((RemovalCheckpoint) throws -> Void)?
    var backupFailureInjector: ((ArchiveRestoreCheckpoint) throws -> Void)?
    private var pendingRemovalIDs: Set<UUID> = []
    private var archiveRepairTask: Task<Void, Never>?
    private var archiveRepairGeneration: UInt = 0
    private var archiveRepairIDs: [UUID] = []
    private var pendingArchiveRepairIDs: Set<UUID> = []
    var pendingArchiveRepairCount: Int { pendingArchiveRepairIDs.count }

    init(root requestedRoot: URL? = nil, repairArchiveOnOpen: Bool = true) throws {
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
        if repairArchiveOnOpen {
            synchronizeArchive(captures + trashedCaptures)
        } else {
            let records = captures + trashedCaptures
            archiveRepairIDs = records.reversed().map(\.id)
            pendingArchiveRepairIDs = Set(archiveRepairIDs)
        }
    }

    /// Metadata and original files are ready before this maintenance begins.
    /// Each short slice uses the current record so UI edits, trash, and deletion
    /// cannot be overwritten by a stale launch snapshot.
    func startArchiveRepair() {
        guard archiveRepairTask == nil, !pendingArchiveRepairIDs.isEmpty else { return }
        archiveRepairGeneration &+= 1
        let generation = archiveRepairGeneration
        archiveRepairTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                // Let the first window present, then leave time for interaction
                // between individual folders instead of blocking on the archive.
                do { try await Task.sleep(for: .milliseconds(20)) }
                catch { break }
                guard !Task.isCancelled, let self, self.archiveRepairGeneration == generation else { break }
                guard self.repairNextArchiveFolder() else { break }
            }
            guard let self, self.archiveRepairGeneration == generation else { return }
            self.archiveRepairTask = nil
        }
    }

    func cancelArchiveRepair() {
        archiveRepairGeneration &+= 1
        archiveRepairTask?.cancel()
        archiveRepairTask = nil
    }

    /// Tests and explicit maintenance can wait without blocking the main actor.
    func waitForArchiveRepair() async { await archiveRepairTask?.value }

    private func repairNextArchiveFolder() -> Bool {
        while let id = archiveRepairIDs.popLast() {
            guard pendingArchiveRepairIDs.remove(id) != nil else { continue }
            guard !pendingRemovalIDs.contains(id),
                  let capture = captures.first(where: { $0.id == id }) ?? trashedCaptures.first(where: { $0.id == id }) else { continue }
            synchronizeArchive([capture])
            return true
        }
        return false
    }

    func capture(text: String, at: Date = Date(), timeZone: TimeZone = .current,
                 source: CaptureSource = .unknown,
                 receipt: CaptureReceiptContext = .manual, parentTask: Capture? = nil,
                 commitGuard: () -> Bool = { true }) throws -> [Capture] {
        try requireAttachmentParent(parentTask)
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
                           sourceFilePath: source.filePath, sourceURL: source.url, receipt: receipt,
                           parentTaskID: parentTask?.id)
        }
        // URL-only multiline pastes commit as one transaction. Mixed prose remains one exact text original.
        guard commitGuard() else { throw CaptureStoreError.captureCancelled }
        try requireAttachmentParent(parentTask)
        try failureInjector?(.beforeMetadataSave)
        try repository.save(newCaptures)
        captures.append(contentsOf: newCaptures)
        try refresh()
        synchronizeArchive(newCaptures)
        return newCaptures
    }

    func importFile(_ source: URL, at: Date = Date(), timeZone: TimeZone = .current,
                    originalName: String? = nil, source provenance: CaptureSource? = nil,
                    receipt: CaptureReceiptContext = .manual, parentTask: Capture? = nil,
                    commitGuard: @escaping () -> Bool = { true }) async throws -> Capture {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        // Scope failure alone does not mean unreadable; resources already in the container need no grant.
        try OriginalFileStorage.validateRegularFile(source)
        let filename = originalName ?? source.lastPathComponent
        let type = (try? source.resourceValues(forKeys: [.contentTypeKey]).contentType) ?? UTType(filenameExtension: source.pathExtension)
        let origin = provenance ?? CaptureSource(filePath: source.standardizedFileURL.path)
        return try await importOriginal(filename: filename, contentType: type, at: at, timeZone: timeZone,
                                        source: origin, receipt: receipt, parentTask: parentTask, commitGuard: commitGuard) { destination in
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }

    /// Authored notes remain one exact text original even when every line is a URL.
    func createNote(text: String, at: Date = Date(), projectName: String? = nil) throws -> Capture {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CaptureStoreError.emptyInput }
        let note = Capture(capturedAt: at, kind: .text, originalText: text, title: String(trimmed.prefix(100)))
        note.projectName = normalizedProjectName(projectName)
        try failureInjector?(.beforeMetadataSave)
        try persist(note)
        captures.append(note)
        captures.sort { $0.capturedAt == $1.capturedAt ? $0.id.uuidString < $1.id.uuidString : $0.capturedAt > $1.capturedAt }
        return note
    }

    func createTask(text: String, reminderAt: Date? = nil, reminderTimeZoneID: String? = nil,
                    at: Date = Date(), timeZone: TimeZone = .current, planning: TaskPlanning? = nil,
                    projectName: String? = nil) throws -> Capture {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CaptureStoreError.emptyInput }
        if let reminderAt, reminderAt <= Date() { throw CaptureStoreError.reminderNotFuture }
        guard planning?.isValid ?? true else { throw CaptureStoreError.invalidOriginal("Check the task dates, estimate, and checklist before saving.") }
        let task = Capture(capturedAt: at, timeZone: timeZone, kind: .task,
                           originalText: trimmed, title: String(trimmed.prefix(100)))
        task.reminderAt = reminderAt
        task.reminderTimeZoneID = reminderAt == nil ? nil : (reminderTimeZoneID ?? timeZone.identifier)
        task.reminderRevision = reminderAt == nil ? 0 : 1
        task.notificationState = reminderAt == nil ? "none" : "pending"
        task.projectName = normalizedProjectName(projectName)
        if let planning { task.setTaskPlanning(normalizedPlanning(planning, for: task)) }
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
        let previous = (capture.convertedToTask, capture.isCompleted, capture.updatedAt, capture.parentTaskID)
        // Promoting an attached item makes it independently actionable; nesting tasks is not supported.
        capture.setParentTaskID(nil)
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
            capture.setParentTaskID(previous.3)
            throw error
        }
    }

    @discardableResult
    func setTaskCompleted(_ capture: Capture, completed: Bool, at now: Date = Date()) throws -> Capture? {
        guard capture.isTask, capture.isCompleted != completed else { return nil }
        try requireCurrent(capture)
        let old = (capture.isCompleted, capture.reminderRevision, capture.notificationState, capture.updatedAt, capture.taskPlanning)
        let successor = completed ? recurrenceSuccessor(for: capture, at: now) : nil
        var planning = capture.taskPlanning ?? TaskPlanning()
        planning.completedAt = completed ? now : nil
        if let successor { planning.nextOccurrenceID = successor.id }
        capture.setTaskPlanning(planning)
        capture.isCompleted = completed
        // Invalidate an in-flight schedule even when its reminder date is unchanged.
        capture.reminderRevision += 1
        capture.notificationState = completed ? "completed" : (capture.reminderAt == nil ? "none" : "pending")
        capture.updatedAt = now
        do {
            try failureInjector?(.beforeMetadataSave)
            let changed = [capture] + (successor.map { [$0] } ?? [])
            // Completion and its next occurrence are one transaction. A failed
            // write can never leave a completed routine without its next task.
            try repository.save(changed)
            if let successor {
                captures.append(successor)
                captures.sort { $0.capturedAt == $1.capturedAt ? $0.id.uuidString < $1.id.uuidString : $0.capturedAt > $1.capturedAt }
            }
            synchronizeArchive(changed)
            objectWillChange.send()
            return successor
        }
        catch {
            capture.isCompleted = old.0; capture.reminderRevision = old.1
            capture.notificationState = old.2; capture.updatedAt = old.3
            capture.setTaskPlanning(old.4)
            throw error
        }
    }

    /// Change the work plan without changing receipt dates, originals, or reminders.
    func setTaskPlanning(_ capture: Capture, planning: TaskPlanning) throws {
        try requireCurrent(capture)
        guard capture.isTask, planning.isValid else {
            throw CaptureStoreError.invalidOriginal("Check the task dates, estimate, and checklist before saving.")
        }
        var value = normalizedPlanning(planning, for: capture)
        // Completion history and occurrence identity are store-owned, not editable fields.
        value.completedAt = capture.taskPlanning?.completedAt
        value.previousOccurrenceID = capture.taskPlanning?.previousOccurrenceID
        value.nextOccurrenceID = capture.taskPlanning?.nextOccurrenceID
        guard capture.taskPlanning != value else { return }
        let old = (capture.taskPlanning, capture.updatedAt)
        capture.setTaskPlanning(value)
        capture.updatedAt = Date()
        do { try failureInjector?(.beforeMetadataSave); try persist(capture); objectWillChange.send() }
        catch { capture.setTaskPlanning(old.0); capture.updatedAt = old.1; throw error }
    }

    func planTask(_ capture: Capture, on day: String?) throws {
        var planning = capture.taskPlanning ?? TaskPlanning()
        planning.plannedDay = day
        planning.order = nil
        try setTaskPlanning(capture, planning: planning)
    }

    /// A project-filtered reorder preserves the positions of other projects.
    func reorderTasks(_ tasks: [Capture], on day: String) throws {
        guard TaskPlanningPolicy.date(for: day) != nil,
              Set(tasks.map(\.id)).count == tasks.count else {
            throw CaptureStoreError.invalidOriginal("The task order could not be saved.")
        }
        for task in tasks {
            try requireCurrent(task)
            guard TaskPlanningPolicy.isPlanned(task, for: day) else {
                throw CaptureStoreError.invalidOriginal("Only open tasks planned for this day can be reordered.")
            }
        }
        guard !tasks.isEmpty else { return }
        let ids = Set(tasks.map(\.id))
        var ordered = tasks.makeIterator()
        let all = TaskPlanningPolicy.sorted(captures.filter { TaskPlanningPolicy.isPlanned($0, for: day) })
            .map { ids.contains($0.id) ? ordered.next()! : $0 }
        let previous = all.map { ($0, $0.taskPlanning, $0.updatedAt) }
        for (index, task) in all.enumerated() {
            var planning = task.taskPlanning ?? TaskPlanning()
            planning.order = index
            task.setTaskPlanning(planning)
            task.updatedAt = Date()
        }
        do {
            try failureInjector?(.beforeMetadataSave)
            try repository.save(all)
            synchronizeArchive(all)
            objectWillChange.send()
        } catch {
            for (task, planning, updatedAt) in previous { task.setTaskPlanning(planning); task.updatedAt = updatedAt }
            throw error
        }
    }

    private func recurrenceSuccessor(for capture: Capture, at now: Date) -> Capture? {
        guard let previous = capture.taskPlanning, previous.recurrence != .none,
              previous.nextOccurrenceID == nil else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: capture.captureTimeZoneID) ?? .current
        let plannedDate = previous.plannedDay.flatMap { TaskPlanningPolicy.date(for: $0, calendar: calendar) }
        let currentAnchor = plannedDate
            ?? previous.deadline ?? capture.reminderAt ?? capture.capturedAt
        let anchor = previous.recurrenceAnchor ?? currentAnchor
        // A completed occurrence represents its entire planned day. An afternoon
        // cadence must not recreate that same day when the user finishes at noon.
        let occurrenceEnd = plannedDate.flatMap {
            calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0))?.addingTimeInterval(-0.001)
        } ?? currentAnchor
        guard let nextDate = previous.recurrence.nextDate(after: anchor, notBefore: max(now, occurrenceEnd), calendar: calendar) else { return nil }
        let dayOffset = calendar.dateComponents([.day], from: calendar.startOfDay(for: currentAnchor),
                                                to: calendar.startOfDay(for: nextDate)).day ?? 1
        func shifted(_ date: Date?) -> Date? { date.flatMap { calendar.date(byAdding: .day, value: dayOffset, to: $0) } }
        var next = previous
        next.plannedDay = CaptureCalendar.dayString(nextDate, timeZone: calendar.timeZone)
        next.deadline = shifted(previous.deadline)
        next.order = nil
        next.completedAt = nil
        next.previousOccurrenceID = capture.id
        next.nextOccurrenceID = nil
        next.recurrenceAnchor = anchor
        next.checklist = previous.checklist.map { TaskChecklistItem(text: $0.text) }
        let successor = Capture(capturedAt: now, timeZone: calendar.timeZone, kind: .task,
                                originalText: capture.originalText ?? capture.title, title: capture.title)
        successor.comment = capture.comment
        successor.projectName = capture.projectName
        successor.setTaskPlanning(next)
        let reminder = shifted(capture.reminderAt)
        successor.reminderAt = reminder.flatMap { $0 > now ? $0 : nil }
        successor.reminderTimeZoneID = successor.reminderAt == nil ? nil : capture.reminderTimeZoneID
        successor.reminderRevision = successor.reminderAt == nil ? 0 : 1
        successor.notificationState = successor.reminderAt == nil ? "none" : "pending"
        return successor
    }

    private func normalizedPlanning(_ planning: TaskPlanning, for capture: Capture) -> TaskPlanning {
        var value = planning
        if value.recurrence == .none { value.recurrenceAnchor = nil }
        else if capture.taskPlanning?.recurrence != value.recurrence
            || capture.taskPlanning?.plannedDay != value.plannedDay
            || capture.taskPlanning?.recurrenceAnchor == nil {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: capture.captureTimeZoneID) ?? .current
            value.recurrenceAnchor = value.plannedDay.flatMap { TaskPlanningPolicy.date(for: $0, calendar: calendar) }
                ?? value.deadline ?? capture.reminderAt ?? capture.capturedAt
        } else { value.recurrenceAnchor = capture.taskPlanning?.recurrenceAnchor }
        return value
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

    func setOrganization(_ capture: Capture, pinned: Bool, projectName: String?) throws {
        try requireCurrent(capture)
        let project = normalizedProjectName(projectName)
        guard capture.isPinned != pinned || capture.projectName != project else { return }
        let old = (capture.isPinned, capture.projectName, capture.updatedAt)
        capture.isPinned = pinned
        capture.projectName = project
        capture.updatedAt = Date()
        do {
            try failureInjector?(.beforeMetadataSave)
            try persist(capture)
            objectWillChange.send()
        } catch {
            capture.isPinned = old.0
            capture.projectName = old.1
            capture.updatedAt = old.2
            throw error
        }
    }

    private func normalizedProjectName(_ name: String?) -> String? {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : String(trimmed.prefix(120))
    }

    /// A logical snapshot and verified owned files, never a copy of live SQLite.
    func exportBackup(to destination: URL) throws {
        let scoped = destination.startAccessingSecurityScopedResource()
        defer { if scoped { destination.stopAccessingSecurityScopedResource() } }
        try requireStableArchiveForBackup()
        let snapshots = try repository.load()
        try repository.validateSnapshots(snapshots)
        try ArchiveBackup.export(snapshots: snapshots, archiveRoot: root, to: destination)
    }

    func restoreBackup(from source: URL) throws -> ArchiveRestoreResult {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        try requireStableArchiveForBackup()
        let result = try ArchiveBackup.restore(from: source, into: root,
            existing: repository.load(), validate: repository.validateSnapshots,
            checkpoint: { try self.backupFailureInjector?($0) },
            commit: { try self.repository.saveSnapshots($0) })
        let restored = result.addedSnapshots.map(Capture.init(snapshot:))
        captures.append(contentsOf: restored.filter { $0.deletedAt == nil })
        trashedCaptures.append(contentsOf: restored.filter { $0.deletedAt != nil })
        captures.sort { $0.capturedAt == $1.capturedAt ? $0.id.uuidString < $1.id.uuidString : $0.capturedAt > $1.capturedAt }
        trashedCaptures.sort { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
        synchronizeArchive(restored)
        return ArchiveRestoreResult(addedCount: restored.count, existingCount: result.existingCount)
    }

    private func requireStableArchiveForBackup() throws {
        let imports = try FileManager.default.contentsOfDirectory(at: safeURL("Imports"), includingPropertiesForKeys: nil)
        guard pendingRemovalIDs.isEmpty, !imports.contains(where: { $0.pathExtension == "json" }) else {
            throw ArchiveBackupError.busy
        }
    }

    /// The caller first cancels and awaits the capture's preview and local text-index
    /// work. Notification cancellation follows this committed removal, so delayed schedules see no record.
    /// No owned files are removed until the database deletion has committed.
    func remove(_ capture: Capture) throws -> CaptureRemovalResult {
        try requireCurrent(capture)
        return try removeOwnedCapture(capture)
    }

    /// Recoverable removal retains all originals and annotations. Replace the
    /// visible object after commit so a delayed service cannot mutate the trash.
    func moveToTrash(_ capture: Capture) throws {
        try requireCurrent(capture)
        let family = captureFamily(for: capture)
        let before = family.map(CaptureSnapshot.init)
        let timestamp = Date()
        for member in family {
            member.deletedAt = timestamp
            member.reminderRevision += 1
            member.notificationState = "trashed"
            member.updatedAt = timestamp
        }
        do {
            try failureInjector?(.beforeMetadataSave)
            try repository.save(family)
        } catch {
            rollbackTrashState(family, snapshots: before)
            throw error
        }
        let ids = Set(family.map(\.id))
        let retained = family.map { Capture(snapshot: CaptureSnapshot($0)) }
        captures.removeAll { ids.contains($0.id) }
        trashedCaptures.append(contentsOf: retained)
        trashedCaptures.sort { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
        synchronizeArchive(retained)
    }

    func restoreFromTrash(_ capture: Capture) throws {
        try requireTrashed(capture)
        if let parentID = capture.parentTaskID {
            guard let parent = captures.first(where: { $0.id == parentID }) else {
                throw CaptureStoreError.invalidOriginal("Restore the task before restoring its attachment.")
            }
            try requireAttachmentParent(parent)
        }
        // Only restore children trashed together with this task. Earlier individual
        // removals remain in Recently Deleted until the user restores them.
        let family = [capture] + trashedCaptures.filter {
            $0.parentTaskID == capture.id && $0.deletedAt == capture.deletedAt
        }
        let before = family.map(CaptureSnapshot.init)
        for member in family {
            member.deletedAt = nil
            member.reminderRevision += 1
            member.notificationState = member.isTask && member.isCompleted ? "completed"
                : (member.reminderAt == nil ? "none" : "pending")
            member.updatedAt = Date()
        }
        do {
            try failureInjector?(.beforeMetadataSave)
            try repository.save(family)
        } catch {
            rollbackTrashState(family, snapshots: before)
            throw error
        }
        let ids = Set(family.map(\.id))
        let restored = family.map { Capture(snapshot: CaptureSnapshot($0)) }
        trashedCaptures.removeAll { ids.contains($0.id) }
        captures.append(contentsOf: restored)
        captures.sort { $0.capturedAt == $1.capturedAt ? $0.id.uuidString < $1.id.uuidString : $0.capturedAt > $1.capturedAt }
        synchronizeArchive(restored)
    }

    private func rollbackTrashState(_ family: [Capture], snapshots: [CaptureSnapshot]) {
        for (member, previous) in zip(family, snapshots) {
            member.deletedAt = previous.deletedAt
            member.reminderRevision = previous.reminderRevision
            member.notificationState = previous.notificationState
            member.updatedAt = previous.updatedAt
        }
    }

    /// Destructive deletion is available only for an explicitly selected trash
    /// record. Legacy remove() retains its existing active-record semantics.
    func permanentlyRemove(_ capture: Capture) throws -> CaptureRemovalResult {
        try requireTrashed(capture)
        return try removeOwnedCapture(capture)
    }

    private func removeOwnedCapture(_ capture: Capture) throws -> CaptureRemovalResult {
        let family = captureFamily(for: capture, includingTrashed: true)
        let journals = family.map(CaptureRemovalJournal.init)
        let ids = Set(family.map(\.id))
        try archive.ensureDirectory("Deletions")
        var prepared: [(CaptureRemovalJournal, URL)] = []
        do {
            // Every deletion intent is durable before the one metadata transaction.
            // A crash during preparation retains the entire task and all originals.
            for journal in journals {
                for path in try journal.ownedPaths() { try validateRemovalPath(path) }
                let journalURL = try safeURL("Deletions/\(journal.id.uuidString).json")
                guard !FileManager.default.fileExists(atPath: journalURL.path) else {
                    throw CaptureStoreError.invalidOriginal("An earlier removal needs recovery. Reopen DaBin before trying again.")
                }
                let temporary = try safeURL("Deletions/.\(journal.id.uuidString)-\(UUID().uuidString).pending")
                do {
                    try JSONEncoder().encode(journal).write(to: temporary, options: .atomic)
                    try FileManager.default.moveItem(at: temporary, to: journalURL)
                } catch {
                    try? FileManager.default.removeItem(at: temporary)
                    throw error
                }
                prepared.append((journal, journalURL))
                pendingRemovalIDs.insert(journal.id)
            }
        } catch {
            for (journal, url) in prepared {
                if (try? FileManager.default.removeItem(at: url)) != nil { pendingRemovalIDs.remove(journal.id) }
            }
            throw error
        }
        var committed = false
        do {
            try removalFailureInjector?(.afterJournal)
            try removalFailureInjector?(.beforeMetadataDelete)
            try repository.remove(ids: ids)
            committed = true
            captures.removeAll { ids.contains($0.id) }
            trashedCaptures.removeAll { ids.contains($0.id) }
            ids.forEach { archiveFailures.removeValue(forKey: $0) }
            synchronizeArchive([])
            try removalFailureInjector?(.afterMetadataDelete)
        } catch {
            if case CaptureStoreError.injectedInterruption = error { throw error }
            if !committed {
                for (journal, url) in prepared {
                    do {
                        try FileManager.default.removeItem(at: url)
                        pendingRemovalIDs.remove(journal.id)
                    } catch {
                        self.error = "The capture was kept. Removal preparation will be cleared when DaBin reopens."
                    }
                }
                throw error
            }
        }
        do {
            try removalFailureInjector?(.beforeFileCleanup)
            for (journal, url) in prepared { try finishRemoval(journal, journalURL: url) }
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
                    receipt: CaptureReceiptContext = .manual, parentTask: Capture? = nil,
                    commitGuard: @escaping () -> Bool = { true }) async throws -> Capture {
        try await importOriginal(filename: filename,
                                 contentType: UTType(filenameExtension: (filename as NSString).pathExtension),
                                 at: at, timeZone: timeZone, source: source, receipt: receipt,
                                 parentTask: parentTask, commitGuard: commitGuard) { destination in
            try data.write(to: destination, options: [.atomic])
        }
    }

    private func importOriginal(filename: String, contentType: UTType?, at: Date, timeZone: TimeZone,
                                source: CaptureSource, receipt: CaptureReceiptContext, parentTask: Capture?,
                                commitGuard: @escaping () -> Bool,
                                copy: @escaping @Sendable (URL) throws -> Void) async throws -> Capture {
        try requireAttachmentParent(parentTask)
        let id = UUID()
        let safeName = CaptureClassifier.storageFilename(filename)
        var journal = ImportJournal(id: id, capturedAt: at, captureDay: CaptureCalendar.dayString(at, timeZone: timeZone),
                                    timeZoneID: timeZone.identifier, utcOffset: timeZone.secondsFromGMT(for: at),
                                    originalFilename: filename, sourceFilePath: source.filePath, sourceURL: source.url,
                                    parentTaskID: parentTask?.id,
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
            try requireAttachmentParent(parentTask)
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

    func update(_ capture: Capture, comment: String, reminderAt: Date?, reminderTimeZoneID: String?,
                planning: TaskPlanning? = nil) throws {
        try requireCurrent(capture)
        guard planning == nil || (capture.isTask && planning!.isValid) else {
            throw CaptureStoreError.invalidOriginal("Check the task dates, estimate, and checklist before saving.")
        }
        let old = (capture.comment, capture.reminderAt, capture.reminderTimeZoneID,
                   capture.reminderRevision, capture.notificationState, capture.updatedAt, capture.taskPlanning)
        let zone = reminderAt == nil ? nil : reminderTimeZoneID
        if capture.reminderAt != reminderAt || capture.reminderTimeZoneID != zone {
            capture.reminderRevision += 1
            capture.notificationState = capture.isTask && capture.isCompleted ? "completed" : (reminderAt == nil ? "none" : "pending")
        }
        capture.comment = comment
        capture.reminderAt = reminderAt
        capture.reminderTimeZoneID = zone
        if var planning {
            planning = normalizedPlanning(planning, for: capture)
            planning.completedAt = capture.taskPlanning?.completedAt
            planning.previousOccurrenceID = capture.taskPlanning?.previousOccurrenceID
            planning.nextOccurrenceID = capture.taskPlanning?.nextOccurrenceID
            capture.setTaskPlanning(planning)
        }
        capture.updatedAt = Date()
        do { try failureInjector?(.beforeMetadataSave); try persist(capture); objectWillChange.send() }
        catch {
            capture.comment = old.0; capture.reminderAt = old.1; capture.reminderTimeZoneID = old.2
            capture.reminderRevision = old.3; capture.notificationState = old.4; capture.updatedAt = old.5
            capture.setTaskPlanning(old.6)
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
        guard !pendingRemovalIDs.contains(capture.id), capture.deletedAt == nil,
              !trashedCaptures.contains(where: { $0.id == capture.id }) else {
            throw CaptureStoreError.invalidOriginal("This capture is being removed.")
        }
        if let parentID = capture.parentTaskID {
            guard let parent = captures.first(where: { $0.id == parentID }) else {
                throw CaptureStoreError.invalidOriginal("The task is no longer available for this attachment.")
            }
            try requireAttachmentParent(parent)
        }
        try repository.save([capture])
        // Metadata is already durable. A folder-write failure is retryable and
        // must not turn a successful capture into a misleading failed save.
        synchronizeArchive([capture])
    }

    func refresh() throws {
        let existing = Dictionary(uniqueKeysWithValues: (captures + trashedCaptures).map { ($0.id, $0) })
        let records = try repository.load().map { existing[$0.id] ?? Capture(snapshot: $0) }
        captures = records.filter { $0.deletedAt == nil }
            .sorted { $0.capturedAt == $1.capturedAt ? $0.id.uuidString < $1.id.uuidString : $0.capturedAt > $1.capturedAt }
        trashedCaptures = records.filter { $0.deletedAt != nil }
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
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

    /// Excludes the task's original: that content stays on the task itself.
    func attachments(for task: Capture, includingTrashed: Bool = false) -> [Capture] {
        let records = includingTrashed ? captures + trashedCaptures : captures
        return records.filter { $0.parentTaskID == task.id }
            .sorted { $0.capturedAt == $1.capturedAt ? $0.id.uuidString < $1.id.uuidString : $0.capturedAt < $1.capturedAt }
    }

    /// Callers cancel preview/index/reminder jobs for these records before removing a task.
    func captureFamily(for capture: Capture, includingTrashed: Bool = false) -> [Capture] {
        [capture] + attachments(for: capture, includingTrashed: includingTrashed)
    }

    /// Attach an existing receipt without recopying its file or changing source history.
    /// Moving an existing task attachment requires explicit detachment first.
    func attachCapture(_ capture: Capture, to task: Capture) throws {
        try requireCurrent(capture)
        try requireAttachmentParent(task)
        guard !capture.isTask, capture.id != task.id, capture.parentTaskID == nil else {
            throw CaptureStoreError.invalidOriginal("Choose an independent capture to attach to this task.")
        }
        let previous = (capture.parentTaskID, capture.projectName, capture.updatedAt)
        capture.setParentTaskID(task.id)
        if capture.projectName == nil { capture.projectName = task.projectName }
        capture.updatedAt = Date()
        do { try failureInjector?(.beforeMetadataSave); try persist(capture); objectWillChange.send() }
        catch {
            capture.setParentTaskID(previous.0)
            capture.projectName = previous.1
            capture.updatedAt = previous.2
            throw error
        }
    }

    private func requireAttachmentParent(_ task: Capture?) throws {
        guard let task else { return }
        try requireCurrent(task)
        guard task.isTask, task.parentTaskID == nil else {
            throw CaptureStoreError.invalidOriginal("Choose an existing task before adding attachments.")
        }
    }

    private func requireCurrent(_ capture: Capture) throws {
        guard capture.deletedAt == nil, captures.contains(where: { $0 === capture }), !pendingRemovalIDs.contains(capture.id) else {
            throw CaptureStoreError.invalidOriginal("This capture is no longer in the current archive.")
        }
    }

    private func requireTrashed(_ capture: Capture) throws {
        guard capture.deletedAt != nil, trashedCaptures.contains(where: { $0 === capture }),
              !pendingRemovalIDs.contains(capture.id) else {
            throw CaptureStoreError.invalidOriginal("This capture is no longer in Recently Deleted.")
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
                if (captures + trashedCaptures).contains(where: { $0.id == journal.id }) {
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
            do {
                try archive.synchronize(capture)
                archiveFailures.removeValue(forKey: capture.id)
                pendingArchiveRepairIDs.remove(capture.id)
            }
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
        for capture in captures + trashedCaptures {
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
                    sourceApplicationBundleIdentifier: journal.sourceApplicationBundleIdentifier),
                parentTaskID: journal.parentTaskID)
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
                if let capture = (captures + trashedCaptures).first(where: { $0.id == journal.id }) {
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
        let savedIDs = Set((captures + trashedCaptures).map { $0.id.uuidString })
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
