import Foundation

@MainActor private final class InboxReminderClient: ReminderNotificationClient {
    var requests: [String: ScheduledReminder] = [:]
    func authorization() async -> ReminderAuthorization { .allowed }
    func requestAuthorization() async throws -> Bool { fatalError("No system permission in tests") }
    func pending() async -> [ScheduledReminder] { Array(requests.values) }
    func add(_ reminder: ScheduledReminder) async throws { requests[reminder.identifier] = reminder }
    func removePending(_ identifiers: [String]) { identifiers.forEach { requests.removeValue(forKey: $0) } }
    func removeDelivered(_ identifiers: [String]) {}
}

@main struct WorkInboxTests {
    @MainActor static func main() async throws {
        var checks = 0
        func expect(_ value: Bool, _ message: String) throws {
            checks += 1
            if !value { throw NSError(domain: "WorkInboxTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinInbox-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let preferenceName = "DaBinInboxTests.\(UUID())"
        let defaults = UserDefaults(suiteName: preferenceName)!
        defer { defaults.removePersistentDomain(forName: preferenceName) }
        let store = try CaptureStore(root: root)
        let client = InboxReminderClient()
        let reminders = ReminderService(store: store, client: client)
        let previews = PreviewService(store: store, defaults: defaults)
        let state = AppState(store: store, previews: previews, reminders: reminders)
        defer { previews.shutdown() }
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let earlier = try store.capture(text: "Unrelated material", at: yesterday.addingTimeInterval(-10))[0]
        let reference = try store.capture(text: "Reference with searchable typography", at: yesterday)[0]
        let task = try store.createTask(text: "Review proposal", at: yesterday.addingTimeInterval(10))
        try expect(state.route == .inbox, "DaBin starts in the capture Inbox")
        state.openNewNote()
        state.newNoteText = "A thought from today"
        state.saveNewNote()
        try expect(state.newNoteText.isEmpty && state.route == .inbox, "New note saves, clears its draft and returns to Inbox")
        try expect(state.todayTimelineCaptures.count == 1 && !state.todayTimelineCaptures.contains(where: { $0.id == task.id }), "Today avoids carrying yesterday's tasks into receipt history")
        try expect(state.followUpCaptures.map(\.id) == [task.id], "Undated tasks remain available in Follow-ups")
        state.assignProject(reference, name: "  Website launch  ")
        state.assignProject(task, name: "Website launch")
        state.togglePinned(reference)
        state.openLibrary(); state.libraryProject = "Website launch"
        state.updateGlobalSearch("")
        try expect(state.route == .library, "An empty search-field write cannot hijack navigation")
        try expect(state.projectNames == ["Website launch"] && state.libraryCaptures.first?.id == reference.id, "Projects trim names and pins lead the collection")
        state.libraryPinnedOnly = true
        try expect(state.libraryCaptures.map(\.id) == [reference.id], "Pin filter only returns pinned project captures")
        state.filter = .text
        state.performSearchCommand(); state.updateGlobalSearch("typography")
        state.performSearchCommand()
        state.back()
        try expect(state.route == .library && state.filter == .text && state.libraryPinnedOnly && state.libraryProject == "Website launch",
                   "Leaving a repeated global search restores the Workspace project, pin and type context")
        try expect(state.libraryCaptures.map(\.id) == [reference.id], "Returning from search restores the same collection")
        state.openInbox(); state.openLibrary()
        try expect(state.libraryProject == "Website launch" && state.libraryPinnedOnly && state.filter == .text,
                   "Primary navigation preserves the Workspace selection")
        state.showReminders()
        try expect(state.route == .reminders, "Today opens the planning surface")
        state.openInbox()
        try expect(state.route == .inbox, "Inbox remains available independently of the Activity calendar")
        state.route = .weekly; state.filter = .files
        state.performSearchCommand(); state.query = "typography"
        try expect(state.route == .search && state.searchScope == .all && state.filter == .all && !state.weeklySearchActionsPresented, "Weekly/global search opens the whole archive without a scope prompt")
        try expect(state.searchGroups.flatMap(\.entries).map { $0.capture.id } == [reference.id], "Default search contains only matches")
        state.showSearchContext = true
        try expect(state.searchGroups.flatMap(\.entries).contains { $0.capture.id == earlier.id && !$0.isMatch }, "Neighbor context is available by deliberate opt-in")
        let focus = state.globalSearchFocusRequest
        state.performSearchCommand()
        try expect(state.globalSearchFocusRequest == focus + 1, "Search command refocuses an already-open search")
        state.query = "Website launch"
        try expect(state.searchGroups.flatMap(\.entries).filter(\.isMatch).count == 2, "Project names are searchable")
        state.back()
        try expect(state.route == .weekly && state.filter == .files, "Global search restores the weekly Activity filter")
        state.filter = .media
        state.openSearch(day: yesterday); state.back()
        try expect(state.route == .weekly && state.filter == .media, "Day-scoped search restores the current weekly filter")
        state.filter = .links
        state.openSearch(week: state.weeklyDays); state.back()
        try expect(state.route == .weekly && state.filter == .links, "Week-scoped search restores the current weekly filter")
        state.snoozeFollowUp(reference)
        await reminders.reconcile()
        let identifier = ReminderService.identifier(reference.id)
        try expect(reference.reminderAt != nil && state.followUpCaptures.contains { $0.id == reference.id }, "Any saved reference can become a snoozed follow-up")
        await state.removeCapture(reference)
        try expect(state.canUndoRemoval && store.trashedCaptures.contains { $0.id == reference.id }, "User removal is recoverable")
        try expect(client.requests[identifier] == nil && !state.libraryCaptures.contains { $0.id == reference.id }, "Trash hides the item and cancels its reminder")
        await state.undoLastRemoval()
        let restored = store.captures.first { $0.id == reference.id }!
        try expect(restored !== reference && restored.isPinned && restored.projectName == "Website launch", "Undo restores organization and a fresh canonical record")
        try expect(client.requests[identifier] != nil && !state.canUndoRemoval, "Undo reschedules using the restored record")
        state.openCapture(restored.id)
        let commentDraft = state.selectedDraft!
        commentDraft.comment = "Keep this unfinished thought"
        state.back(); state.showReminders()
        state.snoozeFollowUp(restored)
        await reminders.reconcile()
        state.openCapture(restored.id)
        try expect(state.selectedDraft === commentDraft && commentDraft.comment == "Keep this unfinished thought" && state.hasUnsavedDrafts && !commentDraft.reminderChanged,
                   "Snooze rebases the reminder while preserving unfinished comment edits")
        state.back(); state.showReminders()
        state.completeFollowUp(restored)
        await reminders.reconcile()
        try expect(restored.reminderAt == nil && store.captures.contains { $0.id == restored.id }, "Completing a reminder keeps the source capture")
        state.openCapture(restored.id)
        try expect(state.selectedDraft === commentDraft && commentDraft.comment == "Keep this unfinished thought" && state.hasUnsavedDrafts && !commentDraft.reminderEnabled && !commentDraft.reminderChanged,
                   "Complete removes the saved reminder without discarding the comment draft")
        let snapshotData = try JSONEncoder().encode(CaptureSnapshot(restored))
        var legacy = try JSONSerialization.jsonObject(with: snapshotData) as! [String: Any]
        legacy["schemaVersion"] = 6
        legacy.removeValue(forKey: "isPinned"); legacy.removeValue(forKey: "projectName"); legacy.removeValue(forKey: "deletedAt")
        let old = Capture(snapshot: try JSONDecoder().decode(CaptureSnapshot.self, from: JSONSerialization.data(withJSONObject: legacy)))
        try expect(!old.isPinned && old.projectName == nil && old.deletedAt == nil && old.originalText == restored.originalText, "Schema 6 defaults preserve old capture data")
        print("PASS: \(checks) work inbox checks")
    }
}
