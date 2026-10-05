import Foundation
import Combine

@MainActor private final class InboxReminderClient: ReminderNotificationClient {
    var requests: [String: ScheduledReminder] = [:]
    private(set) var removedPendingIDs: Set<String> = []
    func authorization() async -> ReminderAuthorization { .allowed }
    func requestAuthorization() async throws -> Bool { fatalError("No system permission in tests") }
    func pending() async -> [ScheduledReminder] { Array(requests.values) }
    func add(_ reminder: ScheduledReminder) async throws { requests[reminder.identifier] = reminder }
    func removePending(_ identifiers: [String]) {
        removedPendingIDs.formUnion(identifiers)
        identifiers.forEach { requests.removeValue(forKey: $0) }
    }
    func removeDelivered(_ identifiers: [String]) {}
}

@main struct WorkInboxTests {
    @MainActor private static func checkReturnToInbox() async throws -> Int {
        var checks = 0
        func expect(_ value: Bool, _ message: String) throws {
            checks += 1
            if !value { throw NSError(domain: "WorkInboxTests", code: 4, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        func bytes(_ capture: Capture) throws -> Data {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            return try encoder.encode(CaptureSnapshot(capture))
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinInboxReturn-\(UUID())")
        let suite = "DaBinInboxReturn.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let store = try CaptureStore(root: root)
        let previews = PreviewService(store: store, defaults: defaults)
        let state = AppState(store: store, previews: previews,
            reminders: ReminderService(store: store, client: InboxReminderClient()))
        defer {
            previews.shutdown(); state.focusSessions.shutdown(); state.shutdownNotificationPresentation()
            defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root)
        }
        let receivedAt = Date().addingTimeInterval(-86_400)
        let payload = Data("Fictional kept original bytes".utf8)
        let kept = try await store.importData(payload, filename: "Kept.txt", at: receivedAt)
        let task = try store.createTask(text: "Kept unplanned task", at: receivedAt)
        let child = try store.capture(text: "Independent task attachment", at: receivedAt, parentTask: task)[0]
        let filed = try store.createNote(text: "Already filed", at: receivedAt, projectName: "Example project")
        let scheduled = try store.createTask(text: "Scheduled work", at: receivedAt)
        try store.planTask(scheduled, on: CaptureCalendar.dayString(Date()))
        let completed = try store.createTask(text: "Finished work", at: receivedAt)
        _ = try store.setTaskCompleted(completed, completed: true)
        let fresh = try store.createNote(text: "Already in Inbox", at: receivedAt)
        let removed = try store.createNote(text: "Recently Deleted", at: receivedAt)
        try state.workspace.markInboxProcessed([kept, task, child, filed, scheduled, completed, removed].map(\.id))
        try store.moveToTrash(removed)
        try expect(state.canReturnCaptureToInbox(kept) && state.canReturnCaptureToInbox(task),
                   "Kept unfiled originals and unplanned tasks can return to Inbox")
        for (capture, reason) in [(child, "task attachment"), (filed, "filed capture"),
                                  (scheduled, "scheduled task"), (completed, "completed task"),
                                  (fresh, "already-unprocessed capture"), (removed, "deleted capture"),
                                  (Capture(snapshot: CaptureSnapshot(kept)), "stale matching UUID")] {
            try expect(!state.canReturnCaptureToInbox(capture), "Return to Inbox excludes a \(reason)")
            let processed = state.workspace.processedInboxIDs
            try expect(!state.returnCaptureToInbox(capture) && state.workspace.processedInboxIDs == processed,
                       "An ineligible \(reason) cannot change Inbox processing")
        }
        state.assignProject(kept, name: "Temporary project")
        try expect(!state.canReturnCaptureToInbox(kept), "A kept capture is ineligible while filed")
        state.assignProject(kept, name: nil)
        try expect(state.canReturnCaptureToInbox(kept), "Choosing Unfiled makes a kept capture eligible for the explicit return action")
        state.openLibrary(); state.filter = .links
        let before = try bytes(kept)
        let workspaceURL = root.appendingPathComponent(WorkspaceStore.filename)
        let workspaceBefore = try Data(contentsOf: workspaceURL)
        state.workspace.failureInjector = { throw CocoaError(.fileWriteNoPermission) }
        try expect(!state.returnCaptureToInbox(kept), "A failed workspace write rejects Return to Inbox")
        try expect(state.route == .library && state.filter == .links && state.workspace.processedInboxIDs.contains(kept.id)
                   && state.status?.severity == .error,
                   "Failure retains the current view, filter and processed bit and reports feedback")
        try expect(try Data(contentsOf: workspaceURL) == workspaceBefore && bytes(kept) == before,
                   "A failed return preserves workspace and capture bytes")
        try expect(WorkspaceStore(root: root).processedInboxIDs.contains(kept.id),
                   "Restart after a failed write keeps the capture processed")
        state.workspace.failureInjector = nil
        state.setTutorialPresented(true)
        try expect(!state.returnCaptureToInbox(kept) && state.workspace.processedInboxIDs.contains(kept.id),
                   "Blocked navigation cannot partially apply Return to Inbox")
        state.setTutorialPresented(false)
        state.openCapture(kept.id)
        guard let draft = state.selectedDraft, let managed = store.managedURL(for: kept) else {
            throw NSError(domain: "WorkInboxTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Missing fictional return draft or original"])
        }
        draft.comment = "Keep this unfinished comment"
        state.openLibrary(); state.filter = .links
        try expect(state.returnCaptureToInbox(kept), "Returning a kept original succeeds through the shared action")
        try expect(state.route == .inbox && state.filter == .all && !state.workspace.processedInboxIDs.contains(kept.id),
                   "Success opens Inbox with a visible returned item rather than a hiding type filter")
        try expect(try bytes(kept) == before && Data(contentsOf: managed) == payload,
                   "Return preserves the capture identity, original content, receipt, project and annotations")
        try expect(!WorkspaceStore(root: root).processedInboxIDs.contains(kept.id),
                   "Restart preserves the successful return to Inbox")
        state.openCapture(kept.id)
        try expect(state.selectedDraft === draft && draft.comment == "Keep this unfinished comment" && draft.hasChanges,
                   "Returning to Inbox preserves the exact pending comment draft")
        state.back()
        let taskBefore = try bytes(task), childBefore = try bytes(child)
        try expect(state.returnCaptureToInbox(task), "A previously kept unplanned task can return")
        try expect(try bytes(task) == taskBefore && bytes(child) == childBefore && store.attachments(for: task).map(\.id) == [child.id],
                   "Returning a task preserves its task planning and attachment family")
        let restarted = try CaptureStore(root: root)
        let workspace = WorkspaceStore(root: root)
        let visible = restarted.captures.filter {
            $0.parentTaskID == nil && $0.projectName == nil && !$0.isCompleted
                && !workspace.processedInboxIDs.contains($0.id) && (!$0.isTask || $0.taskPlanning?.plannedDay == nil)
        }
        try expect(Set(visible.map(\.id)) == Set([kept.id, task.id, fresh.id]),
                   "The actual Inbox eligibility contract survives restart without exposing filed, scheduled, completed or attached captures")
        return checks
    }

    @MainActor private static func checkTodayReceipts() async throws -> Int {
        var checks = 0
        func expect(_ value: Bool, _ message: String) throws {
            checks += 1
            if !value { throw NSError(domain: "WorkInboxTests", code: 3, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinTodayReceipts-\(UUID())")
        let suite = "DaBinTodayReceipts.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let store = try CaptureStore(root: root)
        let previews = PreviewService(store: store, defaults: defaults)
        let state = AppState(store: store, previews: previews,
            reminders: ReminderService(store: store, client: InboxReminderClient()))
        defer {
            previews.shutdown(); state.focusSessions.shutdown(); state.shutdownNotificationPresentation()
            defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root)
        }
        let now = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        let todayKey = CaptureCalendar.dayString(now)
        state.showReminders()
        state.refreshCurrentDay(at: now)
        let note = try store.createNote(text: "Today's authored note", at: now)
        let link = try store.capture(text: "https://example.invalid/today", at: now.addingTimeInterval(1))[0]
        let automatic = try store.capture(text: "Today's copied text", at: now.addingTimeInterval(2),
            receipt: .automatic(.automaticClipboard))[0]
        let dropped = try await store.importData(Data("Today's file bytes".utf8), filename: "Receipt.txt", at: now.addingTimeInterval(3))
        try store.setOrganization(dropped, pinned: true, projectName: "Other project")
        let completed = try store.createTask(text: "A completed task remains a receipt", at: now.addingTimeInterval(4))
        _ = try store.setTaskCompleted(completed, completed: true, at: now.addingTimeInterval(5))
        let later = try store.createTask(text: "Created today, planned tomorrow", at: now.addingTimeInterval(6))
        try store.planTask(later, on: CaptureCalendar.dayString(tomorrow))
        let earlierTask = try store.createTask(text: "Created yesterday, planned today", at: yesterday)
        try store.planTask(earlierTask, on: todayKey)
        let attachment = try store.capture(text: "Today's independently received attachment", at: now.addingTimeInterval(7), parentTask: earlierTask)[0]
        _ = try store.capture(text: "Yesterday's receipt", at: yesterday.addingTimeInterval(1))
        let removed = try store.capture(text: "A removed receipt", at: now.addingTimeInterval(8))[0]
        try store.moveToTrash(removed)
        try state.workspace.markInboxProcessed([note.id, dropped.id])
        state.libraryProject = "Unrelated selected project"
        state.libraryPinnedOnly = true; state.filter = .links
        state.selectedDay = yesterday; state.weekEndingDay = yesterday
        let expected = Set([note, link, automatic, dropped, completed, later, attachment].map(\.id))
        for scope in ["today", "later", "done"] {
            state.todayPlanningScope = scope
            try expect(Set(state.currentTodayCaptures.map(\.id)) == expected,
                "Today receipts retain every captured item across task scope, project, type, pins, processing and completion: \(scope)")
        }
        try expect(!state.currentTodayCaptures.contains { $0.id == earlierTask.id || $0.id == removed.id },
            "Today's receipt feed excludes older scheduled tasks and Recently Deleted originals")
        try expect(TaskPlanningPolicy.today(store.captures, at: now).contains { $0.id == earlierTask.id },
            "An older task planned for today remains available separately in planning")
        try expect(state.currentTodayCaptures.map(\.id) == [attachment, later, completed, dropped, automatic, link, note].map(\.id),
            "Today receipts use descending capture time rather than task order or completion time")
        let receiptID = AppState.todayReceiptItemID(later.id)
        try expect(receiptID != ProjectWorkspaceIdentity.capture(later.id), "Receipt and planning instances have distinct workspace markers")
        state.workspaceViewport = NavigationViewportAnchor(itemID: receiptID, offset: 21,
            neighbors: [AppState.todayReceiptItemID(completed.id)])
        state.openCapture(later.id); state.reconcileNavigationHistory(); state.back()
        try expect(state.route == .reminders && state.workspaceViewport?.itemID == receiptID
            && state.workspaceViewport?.offset == 21 && state.todayPlanningScope == "done",
            "Detail Back restores the distinct Today receipt anchor and task scope")
        state.workspaceViewport = NavigationViewportAnchor(itemID: ProjectWorkspaceIdentity.capture(earlierTask.id), offset: 9)
        state.openCapture(earlierTask.id); state.reconcileNavigationHistory(); state.back()
        try expect(state.workspaceViewport?.itemID == ProjectWorkspaceIdentity.capture(earlierTask.id),
            "Existing planning anchors stay compatible")
        let nextReceipt = try store.createNote(text: "Tomorrow's receipt", at: tomorrow)
        var publishedDays: [String] = []
        let subscription = state.$currentDayKey.dropFirst().sink { publishedDays.append($0) }
        state.refreshCurrentDay(at: tomorrow)
        try expect(publishedDays == [CaptureCalendar.dayString(tomorrow)] && state.currentTodayCaptures.map(\.id) == [nextReceipt.id],
            "Midnight publishes the new Today receipt membership even when history is browsed")
        try expect(state.selectedDay == yesterday && state.weekEndingDay == yesterday && state.filter == .links,
            "Midnight leaves deliberately browsed history and filters intact")
        state.refreshCurrentDay(at: tomorrow.addingTimeInterval(60))
        try expect(publishedDays.count == 1, "Wake or activation on the same day does not publish a second day transition")
        withExtendedLifetime(subscription) {}
        return checks
    }
    @MainActor private static func checkReminderRecovery() async throws -> Int {
        var checks = 0
        func expect(_ value: Bool, _ message: String) throws {
            checks += 1
            if !value { throw NSError(domain: "WorkInboxTests", code: 2, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinReminderRecovery-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "DaBinReminderRecovery.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = try CaptureStore(root: root)
        let previews = PreviewService(store: store, defaults: defaults)
        defer { previews.shutdown() }
        func makeState(client: InboxReminderClient? = nil) -> AppState {
            AppState(store: store, previews: previews,
                     reminders: ReminderService(store: store, client: client ?? InboxReminderClient()))
        }
        func waitForReminderWork(_ predicate: () -> Bool) async throws {
            let deadline = Date().addingTimeInterval(3)
            while !predicate() && Date() < deadline {
                try await Task.sleep(for: .milliseconds(5))
            }
            try expect(predicate(), "Queued reminder work completes before its fixture archive is removed")
        }
        let sidecar = root.appendingPathComponent("Drafts.json")
        for clear in [true, false] {
            var archiveStates = ["before capture: \(store.error ?? "<nil>")"]
            let capture = try store.capture(text: clear ? "Clear recovery fixture" : "Snooze recovery fixture")[0]
            archiveStates.append("after capture: \(store.error ?? "<nil>")")
            try store.update(capture, comment: "", reminderAt: Date().addingTimeInterval(3600), reminderTimeZoneID: TimeZone.current.identifier)
            archiveStates.append("after initial reminder: \(store.error ?? "<nil>")")
            let editorClient = InboxReminderClient()
            let editor = makeState(client: editorClient)
            editor.openCapture(capture.id)
            editor.selectedDraft!.comment = "Keep the unfinished recovery comment"
            editor.selectedDraft!.reminderMode = .countdown
            editor.selectedDraft!.countdownMinutes = 12
            editor.persistDrafts()
            let before = try Data(contentsOf: sidecar)
            if clear { editor.completeFollowUp(capture) } else { editor.snoozeFollowUp(capture) }
            archiveStates.append("after immediate action: \(store.error ?? "<nil>")")
            let committed = capture.reminderAt
            try expect(try Data(contentsOf: sidecar) == before,
                       "Reminder recovery fixture reproduces the unchanged sidecar before its debounced save")
            try expect(clear ? committed == nil : committed != nil,
                       "The immediate reminder action commits before recovery")
            let identifier = ReminderService.identifier(capture.id)
            try expect(editorClient.requests.isEmpty && editorClient.removedPendingIDs.isEmpty,
                       "The synchronous recovery setup has queued reminder work that still owns the live archive")
            let recovered = makeState()
            recovered.openCapture(capture.id)
            let draft = recovered.selectedDraft!
            try expect(draft.comment == "Keep the unfinished recovery comment" && draft.hasChanges,
                       "Newer reminder revisions retain unrelated unfinished comments")
            try expect(draft.reminder == committed && draft.reminderMode == .date && !draft.reminderChanged,
                       "Recovery adopts the committed clear or snooze instead of reviving an older countdown")
            recovered.saveDetail()
            archiveStates.append("after recovered save: \(store.error ?? "<nil>")")
            try expect(capture.reminderAt == committed && capture.comment == "Keep the unfinished recovery comment"
                       && !draft.hasChanges && !draft.hasError,
                       "Saving the recovered comment cannot replace the newer reminder")
            // AppState's immediate actions launch MainActor tasks. Do not delete
            // their database while those tasks are still waiting to begin.
            try await waitForReminderWork {
                if clear { return editorClient.removedPendingIDs.contains(identifier) }
                return editorClient.requests[identifier]?.revision == capture.reminderRevision
                    && capture.notificationState == "scheduled"
            }
            archiveStates.append("after queued completion: \(store.error ?? "<nil>")")
            let rootExists = FileManager.default.fileExists(atPath: root.path)
            try expect(store.error == nil && rootExists,
                       "Reminder completion persists against the live fixture without archive errors. clear=\(clear); rootExists=\(rootExists); notificationState=\(capture.notificationState); stages=\(archiveStates.joined(separator: " | "))")
            editor.focusSessions.shutdown(); editor.shutdownNotificationPresentation()
            recovered.focusSessions.shutdown(); recovered.shutdownNotificationPresentation()
        }

        let pending = try store.capture(text: "Pending reminder recovery fixture")[0]
        let editor = makeState()
        editor.openCapture(pending.id)
        editor.selectedDraft!.comment = "Keep the intentional pending reminder"
        editor.selectedDraft!.reminderEnabled = true
        editor.selectedDraft!.reminderMode = .countdown
        editor.selectedDraft!.countdownMinutes = 17
        editor.persistDrafts()
        let recovered = makeState()
        recovered.openCapture(pending.id)
        try expect(recovered.selectedDraft!.reminderEnabled && recovered.selectedDraft!.reminderMode == .countdown
                   && recovered.selectedDraft!.countdownMinutes == 17 && recovered.selectedDraft!.reminderChanged,
                   "An unchanged committed revision preserves the user's pending countdown")

        var legacy = DraftArchiveSnapshot()
        legacy.details = [DetailDraftSnapshot(captureID: pending.id, comment: "Legacy reminder draft", planning: TaskPlanning(),
            reminderEnabled: true, reminderMode: "countdown", countdownHours: 0, countdownMinutes: 23, reminderDate: Date())]
        try DraftArchive(root: root).save(legacy)
        try store.update(pending, comment: "", reminderAt: Date().addingTimeInterval(7200), reminderTimeZoneID: TimeZone.current.identifier)
        let legacyEditor = makeState()
        legacyEditor.openCapture(pending.id)
        try expect(legacyEditor.selectedDraft!.comment == "Legacy reminder draft"
                   && legacyEditor.selectedDraft!.reminderMode == .countdown && legacyEditor.selectedDraft!.countdownMinutes == 23,
                   "Legacy sidecars without a reminder baseline retain their pending reminder edits")
        legacyEditor.persistDrafts()
        let migrated = makeState()
        migrated.openCapture(pending.id)
        try expect(migrated.selectedDraft!.countdownMinutes == 23 && migrated.selectedDraft!.reminderChanged,
                   "Adding the reminder revision baseline preserves legacy edits on the next restart")
        return checks
    }

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
        let weeklyDates = state.weeklyDays.map { CaptureCalendar.dayString($0) }
        state.performSearchCommand(); state.query = "typography"
        try expect(state.route == .search && state.searchScope == .all && state.filter == .all
            && state.searchProject == nil && state.searchSource == nil && !state.showSearchContext
            && state.libraryProject == "Website launch" && !state.weeklySearchActionsPresented
            && state.weeklyDays.map { CaptureCalendar.dayString($0) } == weeklyDates,
            "Fresh Weekly Search starts globally while preserving its dates and project destination")
        state.filter = .files
        try expect(state.searchGroups.isEmpty, "A selected Files filter does not silently return text captures")
        state.filter = .all
        try expect(state.searchGroups.flatMap(\.entries).map { $0.capture.id } == [reference.id], "Default search contains only matches")
        state.selectSearchProject("Website launch")
        state.showSearchContext = true
        try expect(!state.searchGroups.flatMap(\.entries).contains { $0.capture.id == earlier.id },
                   "Opt-in nearby context never leaks a capture outside the selected project")
        let focus = state.globalSearchFocusRequest
        state.performSearchCommand()
        try expect(state.globalSearchFocusRequest == focus + 1, "Search command refocuses an already-open search")
        state.query = "Website launch"
        try expect(state.searchGroups.flatMap(\.entries).filter(\.isMatch).count == 2, "Project names are searchable")
        state.back()
        try expect(state.route == .weekly && state.filter == .files, "Global search restores the weekly Activity filter")
        state.filter = .media
        state.openSearch(day: yesterday)
        state.filter = .media
        state.searchProject = "Website launch"; state.searchSource = "Notes"
        state.searchScrollID = reference.id
        let submitFocus = state.globalSearchFocusRequest
        state.submitSearch()
        try expect(state.route == .search && state.searchScope == .day(CaptureCalendar.dayString(yesterday))
            && state.filter == .media && state.searchProject == "Website launch" && state.searchSource == "Notes"
            && state.query == "Website launch" && state.searchScrollID == reference.id
            && state.globalSearchFocusRequest == submitFocus + 1,
            "Submitting a live search preserves its date, project, app, type, query and position")
        state.back()
        try expect(state.route == .weekly && state.filter == .media, "Day-scoped search restores the current weekly filter")
        state.filter = .links
        state.openSearch(week: state.weeklyDays)
        state.filter = .links
        let scope = state.searchScope
        state.submitSearch()
        try expect(state.searchScope == scope && state.filter == .links, "Return also preserves an explicitly scoped week search")
        state.back()
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
        checks += try await checkReminderRecovery()
        checks += try await checkTodayReceipts()
        checks += try await checkReturnToInbox()
        print("PASS: \(checks) work inbox checks")
    }
}
