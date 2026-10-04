import Foundation

struct ProjectTaskConversionReceipt {
    fileprivate struct Entry {
        let id: UUID
        let parentID: UUID?
        let projectName: String?
        let completed: Bool
        let planning: TaskPlanning?
        let promotedProject: String?
        let revision: Date
    }
    fileprivate let entries: [Entry]
    var captureIDs: [UUID] { entries.map(\.id) }
    var count: Int { entries.count }
    var isEmpty: Bool { entries.isEmpty }
}

@MainActor extension CaptureStore {
    /// One metadata transaction for the entire selection. Original text, bytes,
    /// kinds, receipt times, reminders and identities are never replaced.
    @discardableResult
    func convertProjectItemsToTasks(_ items: [Capture]) throws -> ProjectTaskConversionReceipt {
        let current = Dictionary(uniqueKeysWithValues: captures.map { ($0.id, $0) })
        var seen = Set<UUID>()
        var changed: [Capture] = []
        for item in items {
            guard current[item.id] === item, item.deletedAt == nil else {
                throw CaptureStoreError.invalidOriginal("A selected item is no longer in this archive. Select the current items and try again.")
            }
            if seen.insert(item.id).inserted, !item.isTask { changed.append(item) }
        }
        guard !changed.isEmpty else { return ProjectTaskConversionReceipt(entries: []) }
        let before = changed.map { TaskConversionFields($0) }
        let revision = Date()
        // Resolve every inherited project before any parent relationship changes.
        let entries = try changed.map { item -> ProjectTaskConversionReceipt.Entry in
            let promotedProject: String?
            if let parentID = item.parentTaskID {
                guard let parent = current[parentID], parent.isTask, parent.deletedAt == nil else {
                    throw CaptureStoreError.invalidOriginal("The parent task of a selected attachment is unavailable.")
                }
                promotedProject = parent.projectName
            } else { promotedProject = item.projectName }
            return ProjectTaskConversionReceipt.Entry(id: item.id, parentID: item.parentTaskID,
                projectName: item.projectName, completed: item.isCompleted, planning: item.taskPlanning,
                promotedProject: promotedProject, revision: revision)
        }
        for (item, entry) in zip(changed, entries) {
            item.projectName = entry.promotedProject
            item.setParentTaskID(nil)
            item.setConvertedToTask(true)
            item.isCompleted = false
            item.updatedAt = revision
        }
        do {
            try failureInjector?(.beforeMetadataSave)
            try save(captures: changed)
        } catch {
            for (item, fields) in zip(changed, before) { fields.restore(item) }
            throw error
        }
        return ProjectTaskConversionReceipt(entries: entries)
    }

    func canUndoProjectTaskConversion(_ receipt: ProjectTaskConversionReceipt) -> Bool {
        !receipt.isEmpty && (try? projectTaskUndoItems(receipt)) != nil
    }

    /// Undo is independent of project ordering. New task work, changed project
    /// ownership, or edits after conversion block the whole undo rather than
    /// discarding work or partially restoring the selection.
    func undoProjectTaskConversion(_ receipt: ProjectTaskConversionReceipt) throws {
        let items = try projectTaskUndoItems(receipt)
        guard !items.isEmpty else { return }
        let before = items.map { TaskConversionFields($0) }
        let now = Date()
        for (item, entry) in zip(items, receipt.entries) {
            item.setConvertedToTask(false)
            item.setParentTaskID(entry.parentID)
            item.projectName = entry.projectName
            item.isCompleted = entry.completed
            item.updatedAt = now
        }
        do {
            try failureInjector?(.beforeMetadataSave)
            try save(captures: items)
        } catch {
            for (item, fields) in zip(items, before) { fields.restore(item) }
            throw error
        }
    }

    private func projectTaskUndoItems(_ receipt: ProjectTaskConversionReceipt) throws -> [Capture] {
        let current = Dictionary(uniqueKeysWithValues: captures.map { ($0.id, $0) })
        let parentIDs = Set((captures + trashedCaptures).compactMap(\.parentTaskID))
        return try receipt.entries.map { entry in
            guard let item = current[entry.id], item.deletedAt == nil, item.kind != .task,
                  item.convertedToTask, !item.isCompleted, item.parentTaskID == nil,
                  item.updatedAt == entry.revision, item.projectName == entry.promotedProject,
                  item.taskPlanning == entry.planning, !parentIDs.contains(item.id) else {
                throw CaptureStoreError.invalidOriginal("These tasks have changed since conversion. Keep them as tasks to preserve your work.")
            }
            if let parentID = entry.parentID {
                guard let parent = current[parentID], parent.isTask, parent.deletedAt == nil,
                      parent.parentTaskID == nil, parent.projectName == entry.promotedProject else {
                    throw CaptureStoreError.invalidOriginal("The original parent task has moved or is unavailable. Keep this item as an independent task.")
                }
            }
            return item
        }
    }
}

/// Rollback touches exactly the mutable fields owned by this transaction.
@MainActor private struct TaskConversionFields {
    let promoted: Bool
    let completed: Bool
    let parentID: UUID?
    let projectName: String?
    let updatedAt: Date
    init(_ item: Capture) {
        promoted = item.convertedToTask; completed = item.isCompleted
        parentID = item.parentTaskID; projectName = item.projectName; updatedAt = item.updatedAt
    }
    func restore(_ item: Capture) {
        item.setConvertedToTask(promoted); item.isCompleted = completed
        item.setParentTaskID(parentID); item.projectName = projectName; item.updatedAt = updatedAt
    }
}
