import Foundation

@MainActor private final class FoundationNotifications: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .allowed }
    func requestAuthorization() async throws -> Bool { true }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ request: ScheduledReminder) async throws {}
    func removePending(_ identifiers: [String]) {}
    func removeDelivered(_ identifiers: [String]) {}
}

@main struct ProductFoundationTests {
    @MainActor static func main() async throws {
        var checks = 0
        func expect(_ pass: Bool, _ text: String) throws {
            checks += 1
            if !pass { throw NSError(domain: "ProductFoundationTests", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinProduct-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root)
        let preferenceName = "DaBinProduct.\(UUID())"
        let preferences = UserDefaults(suiteName: preferenceName)!
        defer { preferences.removePersistentDomain(forName: preferenceName) }
        let previews = PreviewService(store: store, defaults: preferences)
        defer { previews.shutdown() }
        let reminders = ReminderService(store: store, client: FoundationNotifications())
        let state = AppState(store: store, previews: previews, reminders: reminders)
        try expect(state.route == .inbox, "New sessions begin at the discoverable Inbox")
        let feedback = try store.capture(text: "Please deliver the revised client brief")[0]
        state.assignProject(feedback, name: "Client Amber")
        state.libraryProject = "Client Amber"; state.filter = .text; state.openLibrary()
        state.showSettings(); state.back()
        try expect(state.route == .library && state.libraryProject == "Client Amber" && state.filter == .text,
                   "Settings returns to the current workspace context")
        state.openCapture(feedback.id)
        state.selectedDraft?.comment = "Keep the original feedback in context"
        state.back()
        try expect(state.route == .library && state.libraryProject == "Client Amber" && state.filter == .text,
                   "Details return to the same project and filter")
        state.performSearchCommand(); state.query = "revised"
        try expect(state.searchGroups.flatMap(\.entries).contains { $0.capture.id == feedback.id }, "Global search finds project feedback")
        state.back()
        try expect(state.route == .library && state.filter == .text && state.libraryProject == "Client Amber",
                   "Search returns to project and type filter")
        try state.workspace.setSnippetName("Client signoff template", for: feedback.id)
        state.performSearchCommand(); state.query = "signoff template"
        try expect(state.searchGroups.flatMap(\.entries).count == 1, "Named snippets are in universal search")
        state.query = "unfindable"
        try expect(state.searchGroups.isEmpty, "Search cache invalidates for query changes")
        state.query = "signoff"; state.searchProject = "Other client"
        try expect(state.searchGroups.isEmpty, "Explicit project filter constrains results")
        state.searchProject = nil
        try expect(state.searchGroups.flatMap(\.entries).count == 1, "Clearing project scope restores results")
        state.newNoteText = "Unfinished idea — שלום — 日本語"
        state.newTaskDraft.text = "Follow up after lunch"
        state.newTaskDraft.planning.priority = .high
        state.newTaskDraft.planning.plannedDay = CaptureCalendar.dayString(Date())
        state.persistDrafts()
        try expect(state.draftPersistenceError == nil, "Drafts commit locally without becoming captures")
        let restarted = AppState(store: store, previews: previews, reminders: reminders)
        try expect(restarted.newNoteText == state.newNoteText && restarted.newTaskDraft.text == state.newTaskDraft.text,
                   "Restart restores both composer drafts")
        try expect(restarted.newTaskDraft.planning.priority == .high && restarted.libraryProject == "Client Amber",
                   "Restart restores task planning and active project")
        restarted.openCapture(feedback.id)
        try expect(restarted.selectedDraft?.comment == "Keep the original feedback in context" && restarted.selectedDraft?.hasChanges == true,
                   "Unsaved detail edits recover without silently committing")
        restarted.saveDetail()
        try expect(feedback.comment == "Keep the original feedback in context", "Recovered detail commits through normal Save")
        restarted.persistDrafts()
        let restartedAgain = AppState(store: store, previews: previews, reminders: reminders)
        restartedAgain.openCapture(feedback.id)
        try expect(restartedAgain.selectedDraft?.hasChanges == false, "Committed drafts do not reappear as unsaved")
        state.convertToTask(feedback)
        state.openCapture(feedback.id)
        let completionDraft = state.selectedDraft!
        let savedCommentBeforeCompletion = feedback.comment
        completionDraft.comment = "Unsaved comment survives completion"
        state.toggleTaskCompletion(feedback)
        try expect(state.selectedDraft === completionDraft && completionDraft.hasChanges
            && completionDraft.comment == "Unsaved comment survives completion"
            && feedback.comment == savedCommentBeforeCompletion,
            "Completing a task retains its dirty draft and cannot commit the unsaved comment")
        let planningTask = try store.createTask(text: "A planning-only draft")
        state.openCapture(planningTask.id)
        let unfinishedDeadline = Date().addingTimeInterval(172_800)
        state.selectedDraft?.planning.priority = .high
        state.selectedDraft?.planning.deadline = unfinishedDeadline
        state.selectedDraft?.planning.checklist = [TaskChecklistItem(text: "Review before sending")]
        state.toggleTaskCompletion(planningTask)
        try expect(planningTask.isCompleted && state.selectedDraft?.comment == planningTask.comment
            && state.selectedDraft?.planning.priority == .high && state.selectedDraft?.planning.deadline == unfinishedDeadline
            && state.selectedDraft?.planning.checklist.first?.text == "Review before sending"
            && state.selectedDraft?.planning.completedAt == planningTask.taskPlanning?.completedAt
            && state.selectedDraft?.hasChanges == true && planningTask.taskPlanning?.priority != .high,
            "Completion preserves a dirty planning-only draft while adopting only saved lifecycle fields")
        let unfinishedStep = TaskChecklistItem(text: "")
        state.newTaskDraft.text = "An unfinished checklist draft"
        state.newTaskDraft.planning.checklist = [unfinishedStep]
        state.persistDrafts()
        let resumedPlanning = AppState(store: store, previews: previews, reminders: reminders)
        resumedPlanning.openCapture(planningTask.id)
        try expect(resumedPlanning.selectedDraft?.planning.priority == .high
            && resumedPlanning.selectedDraft?.planning.deadline == unfinishedDeadline
            && resumedPlanning.selectedDraft?.hasChanges == true,
            "Restart recovers unfinished planning after task completion without committing it")
        try expect(resumedPlanning.newTaskDraft.text == "An unfinished checklist draft"
            && resumedPlanning.newTaskDraft.planning.checklist == [unfinishedStep]
            && !resumedPlanning.newTaskDraft.planning.isValid && resumedPlanning.draftPersistenceError == nil
            && !store.captures.contains { $0.originalText == "An unfinished checklist draft" },
            "Restart preserves an incomplete invalid checklist as an editable draft, not a committed capture")
        resumedPlanning.openNewTask()
        resumedPlanning.performSearchCommand(); resumedPlanning.query = "revised"
        resumedPlanning.openCapture(feedback.id); resumedPlanning.back(); resumedPlanning.back()
        try expect(resumedPlanning.route == .newTask && resumedPlanning.newTaskDraft.planning.checklist == [unfinishedStep]
            && resumedPlanning.selectedCapture?.id == planningTask.id,
            "Inspecting search results returns to an unfinished task composer with its checklist and originating task intact")
        resumedPlanning.back()
        resumedPlanning.openNewNote(); resumedPlanning.newNoteText = "A note paused for a lookup"
        resumedPlanning.performSearchCommand(); resumedPlanning.back()
        try expect(resumedPlanning.route == .newNote && resumedPlanning.newNoteText == "A note paused for a lookup",
            "A quick lookup returns to the same unfinished note composer")
        let navigation = AppState(store: store, previews: previews, reminders: reminders)
        func openResultFromTask() {
            navigation.openLibrary()
            navigation.openCapture(planningTask.id)
            navigation.selectedDraft?.comment = "Keep this edit while browsing nested search"
            navigation.performSearchCommand()
            navigation.openCapture(feedback.id)
        }
        for useTrash in [false, true] {
            openResultFromTask()
            if useTrash { navigation.showTrash() } else { navigation.showSettings() }
            navigation.performSearchCommand(); navigation.back()
            try expect(navigation.route == .detail && navigation.selectedCapture?.id == planningTask.id
                && navigation.selectedDraft?.comment == "Keep this edit while browsing nested search"
                && navigation.selectedDraft?.hasChanges == true,
                "Search from an auxiliary page over a result resumes the original task and dirty draft")
            navigation.back()
            try expect(navigation.route == .library, "Nested auxiliary search retains the original task's back destination without a loop")
        }
        for useNote in [false, true] {
            openResultFromTask()
            if useNote { navigation.openNewNote(); navigation.newNoteText = "Keep the nested note draft" }
            else { navigation.openNewTask(); navigation.newTaskDraft.text = "Keep the nested task draft" }
            navigation.performSearchCommand(); navigation.back()
            try expect(navigation.route == .detail && navigation.selectedCapture?.id == planningTask.id
                && (useNote ? navigation.newNoteText == "Keep the nested note draft"
                    : navigation.newTaskDraft.text == "Keep the nested task draft"),
                "Search from a composer over a result resumes the original task while preserving its composer draft")
            navigation.back()
            try expect(navigation.route == .library, "Nested composer search cannot cycle back into its old search session")
        }
        navigation.showSettings(); navigation.showTrash(); navigation.showSettings(); navigation.back()
        try expect(navigation.route == .trash, "Back retraces the most recently visited auxiliary page")
        navigation.back()
        try expect(navigation.route == .settings, "Back retains the earlier Settings visit")
        navigation.back()
        try expect(navigation.route == .library, "The auxiliary history returns to its original library")
        navigation.openCapture(planningTask.id)
        let navigationTaskDraft = navigation.selectedDraft!
        navigation.showTrash(); navigation.showSettings(); navigation.showTrash(); navigation.back()
        try expect(navigation.route == .settings, "Task auxiliary history retraces Settings")
        navigation.back()
        try expect(navigation.route == .trash, "Task auxiliary history retraces Recently Deleted")
        navigation.back()
        try expect(navigation.route == .detail && navigation.selectedCapture?.id == planningTask.id,
            "The auxiliary history returns to its original task")
        try expect(navigation.selectedDraft === navigationTaskDraft && navigationTaskDraft.hasChanges,
            "Retracing auxiliary pages preserves the same dirty task draft")
        for useTrash in [false, true] {
            navigation.openLibrary(); navigation.performSearchCommand()
            if useTrash { navigation.showTrash() } else { navigation.showSettings() }
            navigation.performSearchCommand(); navigation.back()
            try expect(navigation.route == .library,
                "Search opened directly from an auxiliary page over Search returns to the original library")
        }
        for useNote in [false, true] {
            navigation.openLibrary(); navigation.performSearchCommand()
            if useNote { navigation.openNewNote() } else { navigation.openNewTask() }
            navigation.performSearchCommand(); navigation.back()
            try expect(navigation.route == .library,
                "Search opened directly from a composer over Search returns to the original library")
        }
        for composerFirst in [false, true] {
            openResultFromTask()
            if composerFirst { navigation.openNewTask(); navigation.showSettings() }
            else { navigation.showSettings(); navigation.openNewTask() }
            navigation.performSearchCommand(); navigation.back()
            try expect(navigation.route == .detail && navigation.selectedCapture?.id == planningTask.id,
                "A composer and Settings layered over a search result still resume the original task")
            navigation.back()
            try expect(navigation.route == .library, "A nested return-route chain leaves search without cycling")
        }
        navigation.openLibrary(); navigation.showSettings(); navigation.openNewTask(); navigation.showSettings(); navigation.back()
        try expect(navigation.route == .newTask, "Settings retraces the task composer that opened it")
        navigation.back()
        try expect(navigation.route == .settings, "The task composer retains its preceding Settings visit")
        navigation.back()
        try expect(navigation.route == .library, "Composer and auxiliary history returns to Library")
        navigation.openNewTask(); navigation.showSettings(); navigation.openNewNote(); navigation.back()
        try expect(navigation.route == .settings, "Note composer retraces its preceding Settings visit")
        navigation.back()
        try expect(navigation.route == .newTask, "Switching composers retains the earlier task composer visit")
        navigation.back()
        try expect(navigation.route == .library, "Both composer visits return to the original work destination")
        navigation.openNewTask(); navigation.openNewNote(); navigation.back()
        try expect(navigation.route == .newTask, "Back from Note retraces the visited Task composer")
        navigation.back()
        try expect(navigation.route == .library, "Composer history reaches Library without a self-return loop")
        navigation.openCapture(planningTask.id); navigation.showSettings(); navigation.openCapture(feedback.id); navigation.back()
        try expect(navigation.route == .settings, "A capture opened through Settings returns to that visited page")
        navigation.back()
        try expect(navigation.route == .detail && navigation.selectedCapture?.id == planningTask.id
            && navigation.selectedDraft === navigationTaskDraft && navigationTaskDraft.hasChanges,
            "Back restores the original task and its same unfinished draft")
        navigation.back()
        try expect(navigation.route == .library, "The capture and Settings history returns to its original Library")
        navigation.openNewTask(); navigation.newTaskDraft.text = "Original composer before a lookup"
        navigation.performSearchCommand(); navigation.openCapture(feedback.id)
        navigation.openNewNote(); navigation.newNoteText = "New idea during the lookup"
        navigation.performSearchCommand(); navigation.back()
        try expect(navigation.route == .newTask && navigation.newTaskDraft.text == "Original composer before a lookup"
            && navigation.newNoteText == "New idea during the lookup",
            "Search restores its original composer and retains an additional composer draft opened while browsing")
        navigation.back()
        try expect(navigation.route == .library, "Search restores the original creation return slot after result navigation replaces it")
        navigation.showSettings(); navigation.performSearchCommand(); navigation.openCapture(feedback.id)
        navigation.showTrash(); navigation.performSearchCommand(); navigation.back()
        try expect(navigation.route == .settings, "An auxiliary page opened while browsing does not replace the original search return page")
        navigation.back()
        try expect(navigation.route == .library, "Search restores the original auxiliary return slot after result navigation replaces it")
        // Composer destinations belong to the draft, not the last project
        // visited elsewhere. Use an independent synthetic archive for recovery.
        let composerStore = try CaptureStore(root: root.appendingPathComponent("ComposerDestinations"))
        let composerPreviews = PreviewService(store: composerStore, defaults: preferences)
        defer { composerPreviews.shutdown() }
        let composerReminders = ReminderService(store: composerStore, client: FoundationNotifications())
        let composer = AppState(store: composerStore, previews: composerPreviews, reminders: composerReminders)
        composer.libraryProject = "Client Amber"; composer.openLibrary(); composer.openInbox()
        composer.openNewTask(); composer.newTaskDraft.text = "An unassigned Inbox task"
        try expect(composer.newTaskProject == nil, "Inbox task composer ignores a remembered Workspace project")
        composer.saveNewTask()
        try expect(composerStore.captures.first?.projectName == nil && composer.route == .inbox,
            "Inbox task stays discoverable in Inbox after save")
        composer.openNewNote(); composer.newNoteText = "An unassigned Inbox note"
        try expect(composer.newNoteProject == nil, "Inbox note composer ignores a remembered Workspace project")
        composer.saveNewNote()
        try expect(composerStore.captures.first { $0.originalText == "An unassigned Inbox note" }?.projectName == nil,
            "Inbox note saves without a hidden client assignment")
        composer.openLibrary(); composer.openNewNote(); composer.newNoteText = "Amber draft"
        composer.back(); composer.libraryProject = "Client Blue"; composer.openNewNote()
        try expect(composer.newNoteProject == "Client Amber", "Returning to an unfinished note cannot retarget its project")
        composer.newNoteText = ""; composer.openNewNote()
        try expect(composer.newNoteProject == "Client Amber", "An empty intermediate edit or repeated New note action keeps the open draft's destination")
        composer.newNoteText = "Amber draft"
        try expect(composer.newNoteProject == "Client Amber", "Replacing an entire note after browsing another project cannot retarget it")
        composer.openNewTask(); composer.newTaskDraft.text = "Blue draft"
        try expect(composer.newTaskProject == "Client Blue", "A separate task composer freezes its own project")
        composer.openInbox(); composer.openNewTask()
        try expect(composer.newTaskProject == "Client Blue", "Returning to an unfinished task from Inbox preserves its destination")
        composer.persistDrafts()
        let recoveredComposer = AppState(store: composerStore, previews: composerPreviews, reminders: composerReminders)
        try expect(recoveredComposer.newNoteProject == "Client Amber" && recoveredComposer.newTaskProject == "Client Blue",
            "Restart restores independent note and task destinations")
        recoveredComposer.libraryProject = "Client Green"
        recoveredComposer.openNewNote(); recoveredComposer.saveNewNote()
        recoveredComposer.openNewTask(); recoveredComposer.saveNewTask()
        try expect(composerStore.captures.first { $0.originalText == "Amber draft" }?.projectName == "Client Amber"
            && composerStore.captures.first { $0.originalText == "Blue draft" }?.projectName == "Client Blue",
            "Recovered drafts save to their original projects after navigation changes")
        recoveredComposer.showReminders(); recoveredComposer.openNewNote()
        recoveredComposer.newNoteText = "Cancel this project note"; recoveredComposer.cancelNewNote()
        recoveredComposer.openInbox(); recoveredComposer.openNewNote()
        try expect(recoveredComposer.newNoteProject == nil, "Cancel clears a note's former destination before a fresh Inbox composer")
        recoveredComposer.showReminders(); recoveredComposer.openNewTask()
        try expect(recoveredComposer.newTaskProject == "Client Green", "Today uses its visible selected project for a fresh task")
        recoveredComposer.newTaskDraft.text = "Canceled"; recoveredComposer.cancelNewTask()
        recoveredComposer.openInbox(); recoveredComposer.openNewTask()
        try expect(recoveredComposer.newTaskProject == nil, "Cancel clears the old task destination before an Inbox composer")
        recoveredComposer.newTaskDraft.text = "Inbox recovery"
        recoveredComposer.newNoteText = "Inbox inline recovery"
        recoveredComposer.persistDrafts()
        let recoveredInbox = AppState(store: composerStore, previews: composerPreviews, reminders: composerReminders)
        try expect(recoveredInbox.newNoteProject == nil && recoveredInbox.newTaskProject == nil
            && recoveredInbox.libraryProject == "Client Green",
            "Explicit Inbox destinations remain unassigned after restart despite a saved selected project")
        var legacyDraft = DraftArchiveSnapshot()
        legacyDraft.note = "Legacy note"; legacyDraft.task.text = "Legacy task"
        try DraftArchive(root: composerStore.root).save(legacyDraft)
        let migratedComposer = AppState(store: composerStore, previews: composerPreviews, reminders: composerReminders)
        try expect(migratedComposer.newNoteProject == "Client Green" && migratedComposer.newTaskProject == "Client Green",
            "Version-one drafts without destination metadata preserve their former selected-project behavior")
        let broken = root.appendingPathComponent("CorruptDrafts")
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        let corruptData = Data("invalid preserved data".utf8)
        try corruptData.write(to: broken.appendingPathComponent("Drafts.json"))
        let recovery = DraftArchive(root: broken)
        try expect(recovery.load() == nil && recovery.recoveryError != nil, "Corrupt recovery data is reported")
        do { try recovery.save(DraftArchiveSnapshot()); throw NSError(domain: "UnexpectedWrite", code: 1) }
        catch { try expect(try Data(contentsOf: broken.appendingPathComponent("Drafts.json")) == corruptData, "Invalid draft file is never overwritten") }
        print("PASS: \(checks) connected product foundation checks")
    }
}
