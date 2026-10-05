import Foundation

@MainActor private final class CommentDraftNotifications: ReminderNotificationClient {
    private(set) var calls = 0
    func authorization() async -> ReminderAuthorization { calls += 1; return .denied }
    func requestAuthorization() async throws -> Bool { calls += 1; return false }
    func pending() async -> [ScheduledReminder] { calls += 1; return [] }
    func add(_ reminder: ScheduledReminder) async throws { calls += 1 }
    func removePending(_ identifiers: [String]) { calls += 1 }
    func removeDelivered(_ identifiers: [String]) { calls += 1 }
}

@main struct CommentDraftArchiveTests {
    @MainActor private static var checks = 0
    @MainActor private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard condition() else { throw NSError(domain: "CommentDraftArchiveTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinCommentDraftTests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try archiveCompatibility(root.appendingPathComponent("Archive"))
        try composerIntegration(root.appendingPathComponent("AppState"))
        try pendingChecklistIntegration(root.appendingPathComponent("Checklist"))
        print("PASS: \(checks) comment draft checks; legacy compatibility, recoverable composer/edit identity, posting/failure and unrelated task-draft preservation.")
    }

    @MainActor private static func archiveCompatibility(_ root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let id = UUID(), commentID = UUID()
        var snapshot = DraftArchiveSnapshot()
        snapshot.task.pendingChecklistText = "Pending composer step"
        snapshot.details = [DetailDraftSnapshot(captureID: id, title: "Pending title", comment: "Saved aggregate", planning: TaskPlanning(),
            reminderEnabled: false, reminderMode: "date", countdownHours: 0, countdownMinutes: 30, reminderDate: Date(),
            commentComposer: "  Unsaved reply\n    with indentation", editingCommentID: commentID,
            pendingChecklistText: "  Pending detail step\n")]
        let archive = DraftArchive(root: root)
        try archive.save(snapshot)
        let loaded = DraftArchive(root: root).load()!
        try expect(loaded.details[0].commentComposer == snapshot.details[0].commentComposer && loaded.details[0].editingCommentID == commentID,
                   "Pending reply text and edited-entry identity survive draft restart")
        try expect(loaded.details[0].comment == "Saved aggregate" && loaded.details[0].title == "Pending title", "New draft fields retain existing pending data")
        try expect(loaded.task.pendingChecklistText == "Pending composer step"
            && loaded.details[0].pendingChecklistText == "  Pending detail step\n", "Both checklist composers recover exact unsubmitted text")
        let file = root.appendingPathComponent("Drafts.json")
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        var detail = (json["details"] as! [[String: Any]])[0]
        detail.removeValue(forKey: "commentComposer"); detail.removeValue(forKey: "editingCommentID")
        detail.removeValue(forKey: "pendingChecklistText")
        var task = json["task"] as! [String: Any]
        task.removeValue(forKey: "pendingChecklistText"); json["task"] = task
        json["details"] = [detail]
        try JSONSerialization.data(withJSONObject: json).write(to: file)
        let legacy = DraftArchive(root: root).load()!
        try expect(legacy.details[0].commentComposer == nil && legacy.details[0].editingCommentID == nil && legacy.details[0].comment == "Saved aggregate",
                   "Legacy drafts decode absent composer fields without changing the aggregate")
        try expect(legacy.task.pendingChecklistText == nil && legacy.details[0].pendingChecklistText == nil,
            "Legacy checklist drafts decode missing pending text without changing saved steps")
        snapshot.details[0].title = String(repeating: "x", count: 2_001)
        snapshot.details.append(DetailDraftSnapshot(captureID: UUID(), title: "Other pending task", comment: "Other draft remains readable", planning: TaskPlanning(),
            reminderEnabled: false, reminderMode: "date", countdownHours: 0, countdownMinutes: 30, reminderDate: Date(),
            pendingChecklistText: "Other pending step"))
        try archive.save(snapshot)
        let invalidTypedTitle = DraftArchive(root: root).load()!
        try expect(invalidTypedTitle.details[0].title?.count == 2_001
            && invalidTypedTitle.details[1].pendingChecklistText == "Other pending step"
            && invalidTypedTitle.task.pendingChecklistText == "Pending composer step",
            "An invalid 2001-character typed title recovers alongside every unrelated draft")
        let broken = Data("{preserve this damaged fixture".utf8)
        try broken.write(to: file)
        let damaged = DraftArchive(root: root)
        try expect(damaged.load() == nil && damaged.recoveryError != nil, "Damaged drafts report recovery failure")
        var rejected = false
        do { try damaged.save(snapshot) } catch { rejected = true }
        let preserved = try Data(contentsOf: file)
        try expect(rejected && preserved == broken, "A failed recovery cannot overwrite the original draft file")
    }

    @MainActor private static func pendingChecklistIntegration(_ root: URL) throws {
        let store = try CaptureStore(root: root, repairArchiveOnOpen: false)
        defer { store.cancelArchiveRepair() }
        let task = try store.createTask(text: "Fictional checklist draft task")
        let preferencesName = "DaBinChecklistDraft.\(UUID())"
        let preferences = UserDefaults(suiteName: preferencesName)!
        defer { preferences.removePersistentDomain(forName: preferencesName) }
        let previews = PreviewService(store: store, defaults: preferences)
        defer { previews.shutdown() }
        let notifications = CommentDraftNotifications()
        func makeState() -> AppState {
            AppState(store: store, previews: previews, reminders: ReminderService(store: store, client: notifications))
        }
        let state = makeState()
        defer { state.focusSessions.shutdown(); state.shutdownNotificationPresentation() }
        state.openCapture(task.id)
        let draft = state.selectedDraft!
        draft.pendingChecklistText = "  Pending detail step\n"
        state.newTaskDraft.pendingChecklistText = "Pending new task step"
        try expect(draft.hasChanges && state.newTaskDraft.hasChanges, "Unsubmitted checklist text makes each owner a recoverable changed draft")
        state.persistDrafts()
        let recovered = makeState()
        defer { recovered.focusSessions.shutdown(); recovered.shutdownNotificationPresentation() }
        recovered.openCapture(task.id)
        let restored = recovered.selectedDraft!
        try expect(restored.pendingChecklistText == draft.pendingChecklistText
            && recovered.newTaskDraft.pendingChecklistText == "Pending new task step", "Both owning models restore unsubmitted checklist text after restart")
        restored.pendingChecklistText = String(repeating: "x", count: 501)
        recovered.saveDetail()
        try expect(restored.validationIssue == .planning && restored.hasUnresolvedValidation
            && restored.pendingChecklistText.count == 501 && task.taskPlanning?.checklist.isEmpty != false,
            "Oversized pending Detail step is rejected without mutation or lost input")
        restored.pendingChecklistText = "  Pending detail step\n"
        restored.title = String(repeating: "x", count: 2_001)
        recovered.saveDetail()
        try expect(restored.validationIssue == .title && restored.pendingChecklistText == "  Pending detail step\n",
            "Unrelated invalid task title never consumes the pending checklist entry")
        restored.title = task.title
        store.failureInjector = { if $0 == .beforeMetadataSave { throw CaptureStoreError.importVerificationFailed } }
        recovered.saveDetail()
        try expect(restored.hasError && restored.pendingChecklistText == "  Pending detail step\n"
            && restored.planning.checklist.isEmpty && task.taskPlanning?.checklist.isEmpty != false,
            "Failed Detail persistence retains pending text without inserting a candidate into either plan")
        store.failureInjector = nil
        recovered.saveDetail()
        let firstID = task.taskPlanning!.checklist[0].id
        try expect(task.taskPlanning?.checklist.map(\.text) == ["Pending detail step"]
            && restored.pendingChecklistText.isEmpty && !restored.hasChanges, "Successful Detail save includes and clears exactly one pending step")
        recovered.saveDetail()
        try expect(task.taskPlanning?.checklist.count == 1 && task.taskPlanning?.checklist[0].id == firstID,
            "Repeated Detail save cannot duplicate a previously included pending step")
        restored.pendingChecklistText = "Keep this pending through immediate focus"
        _ = recovered.configureTaskFocus(task, hours: 0, minutes: 25)
        try expect(restored.pendingChecklistText == "Keep this pending through immediate focus"
            && task.taskPlanning?.checklist.count == 1, "Immediate focus saves do not consume or commit pending checklist text")
        recovered.openNewTask(); recovered.newTaskDraft.text = "Fictional task with pending step"
        recovered.newTaskDraft.pendingChecklistText = "Pending new task step"
        let before = store.captures.count
        store.failureInjector = { if $0 == .beforeMetadataSave { throw CaptureStoreError.importVerificationFailed } }
        recovered.saveNewTask()
        try expect(store.captures.count == before && recovered.newTaskDraft.pendingChecklistText == "Pending new task step"
            && recovered.newTaskDraft.planning.checklist.isEmpty, "Failed Add task preserves its unsubmitted step without mutating the candidate plan")
        store.failureInjector = nil
        recovered.saveNewTask()
        let created = store.captures.first { $0.originalText == "Fictional task with pending step" }!
        try expect(store.captures.count == before + 1 && created.taskPlanning?.checklist.map(\.text) == ["Pending new task step"]
            && recovered.newTaskDraft.pendingChecklistText.isEmpty, "Successful Add task includes the typed pending step exactly once")
        let converted = try store.capture(text: "Fictional capture to promote")[0]
        recovered.openCapture(converted.id); recovered.convertToTask(converted)
        let convertedDraft = recovered.selectedDraft!
        try expect(recovered.canUndoTaskConversion, "Clean conversion offers Undo")
        convertedDraft.pendingChecklistText = "Pending conversion step"
        try expect(!recovered.canUndoTaskConversion, "A pending step makes conversion Undo unavailable")
        recovered.undoTaskConversion()
        try expect(converted.isTask && convertedDraft.pendingChecklistText == "Pending conversion step",
            "Direct conversion Undo cannot silently discard unsubmitted checklist text")
        convertedDraft.pendingChecklistText = ""; convertedDraft.title = "Pending converted title"
        try expect(!recovered.canUndoTaskConversion, "A pending title makes conversion Undo unavailable")
        convertedDraft.title = converted.title; convertedDraft.planning.priority = .high
        try expect(!recovered.canUndoTaskConversion, "A pending work plan makes conversion Undo unavailable")
        convertedDraft.planning = TaskPlanning()
        try expect(recovered.canUndoTaskConversion, "Returning to the committed conversion restores valid Undo availability")
        try expect(notifications.calls == 0, "Checklist commit and recovery never request or schedule notifications")
    }

    @MainActor private static func composerIntegration(_ root: URL) throws {
        let store = try CaptureStore(root: root)
        let task = try store.createTask(text: "Comment fixture task")
        _ = try store.appendComment(task, text: "Existing reply")
        let preferencesName = "DaBinCommentDraft.\(UUID())"
        let preferences = UserDefaults(suiteName: preferencesName)!
        defer { preferences.removePersistentDomain(forName: preferencesName) }
        let previews = PreviewService(store: store, defaults: preferences)
        defer { previews.shutdown() }
        let notifications = CommentDraftNotifications()
        func makeState() -> AppState {
            AppState(store: store, previews: previews, reminders: ReminderService(store: store, client: notifications))
        }
        let state = makeState()
        defer { state.focusSessions.shutdown(); state.shutdownNotificationPresentation() }
        state.openCapture(task.id)
        let draft = state.selectedDraft!
        draft.commentComposer = "Pending reply only"
        try expect(!draft.hasChanges, "Reply composer is independent of the task's Save edits operation")
        state.persistDrafts()
        let recovered = makeState()
        defer { recovered.focusSessions.shutdown(); recovered.shutdownNotificationPresentation() }
        recovered.openCapture(task.id)
        let recoveredDraft = recovered.selectedDraft!
        try expect(recoveredDraft.commentComposer == "Pending reply only" && recoveredDraft.editingCommentID == nil,
                   "A reply-only draft is persisted and restored even without other edits")
        recoveredDraft.title = "Unrelated pending task title"
        recoveredDraft.planning.priority = .high
        store.failureInjector = { if $0 == .beforeMetadataSave { throw CaptureStoreError.importVerificationFailed } }
        let count = task.commentCount
        try expect(!recovered.postDetailComment(task, draft: recoveredDraft), "A failed reply save is surfaced")
        try expect(recoveredDraft.commentComposer == "Pending reply only" && recoveredDraft.hasError && task.commentCount == count,
                   "Failure preserves the composer and every committed reply")
        store.failureInjector = nil
        try expect(recovered.postDetailComment(task, draft: recoveredDraft), "Posting a valid reply succeeds")
        try expect(task.commentCount == count + 1 && recoveredDraft.commentComposer.isEmpty && recoveredDraft.editingCommentID == nil,
                   "Successful posting updates the thread and clears only the composer")
        try expect(recoveredDraft.title == "Unrelated pending task title" && recoveredDraft.planning.priority == .high && recoveredDraft.hasChanges,
                   "Posting retains unrelated pending task title and planning edits")
        let entry = task.commentThread[0]
        recoveredDraft.editingCommentID = entry.id
        recoveredDraft.commentComposer = "Edited but not yet posted"
        recovered.persistDrafts()
        let editingState = makeState()
        defer { editingState.focusSessions.shutdown(); editingState.shutdownNotificationPresentation() }
        editingState.openCapture(task.id)
        let editingDraft = editingState.selectedDraft!
        try expect(editingDraft.editingCommentID == entry.id && editingDraft.commentComposer == "Edited but not yet posted", "Pending per-entry edit survives restart with its target identity")
        try expect(editingState.postDetailComment(task, draft: editingDraft), "Recovered per-entry edit can be posted")
        try expect(task.commentCount == count + 1 && task.commentThread[0].id == entry.id && task.commentThread[0].createdAt == entry.createdAt
                   && task.commentThread[0].text == "Edited but not yet posted", "Editing updates one reply without appending or changing its original identity/date")
        editingDraft.comment = "Pending legacy aggregate edit"
        editingDraft.commentComposer = "Separate reply waiting"
        try expect(!editingState.postDetailComment(task, draft: editingDraft) && editingDraft.commentComposer == "Separate reply waiting", "An unresolved legacy aggregate edit is retained rather than silently overwritten")
        try expect(notifications.calls == 0, "Comment actions never request or schedule system notifications")
    }
}
