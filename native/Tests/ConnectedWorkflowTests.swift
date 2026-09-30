import AppKit
import Foundation

@MainActor private final class WorkflowNotifications: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .allowed }
    func requestAuthorization() async throws -> Bool { true }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ request: ScheduledReminder) async throws {}
    func removePending(_ identifiers: [String]) {}
    func removeDelivered(_ identifiers: [String]) {}
}

/// A working day across capture, projects, clipboard, planning and recovery.
/// Files, notifications, preferences and clipboard are all isolated fixtures.
@main struct ConnectedWorkflowTests {
    @MainActor static func main() async throws {
        var checks = 0
        func expect(_ pass: Bool, _ description: String) throws {
            checks += 1
            if !pass { throw NSError(domain: "ConnectedWorkflowTests", code: 1,
                userInfo: [NSLocalizedDescriptionKey: description]) }
        }
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("DaBinConnectedWorkflows-\(UUID())")
        let preferencesName = "DaBinConnectedWorkflows.\(UUID())"
        let preferences = UserDefaults(suiteName: preferencesName)!
        let pasteboard = NSPasteboard(name: .init("DaBinConnectedWorkflows.\(UUID())"))
        defer {
            pasteboard.releaseGlobally()
            preferences.removePersistentDomain(forName: preferencesName)
            try? files.removeItem(at: root)
        }
        let store = try CaptureStore(root: root.appendingPathComponent("Archive"))
        let previews = PreviewService(store: store, defaults: preferences)
        defer { previews.shutdown() }
        let quickAccess = QuickAccessSettings(defaults: preferences)
        let state = AppState(store: store, previews: previews,
            reminders: ReminderService(store: store, client: WorkflowNotifications()),
            captureClipboard: CaptureClipboardService(pasteboard: pasteboard), quickAccessSettings: quickAccess)
        let workspace = state.workspace
        let now = Date()
        let calendar = Calendar.current
        let today = CaptureCalendar.dayString(now)
        let tomorrowDate = calendar.date(byAdding: .day, value: 1, to: now)!
        let tomorrow = CaptureCalendar.dayString(tomorrowDate)
        let deadline = calendar.date(byAdding: .day, value: 3, to: now)!

        // Capture feedback from Mail, file it, promote it, and attach a brief.
        let feedbackText = "Client Amber: please revise the opening and send a follow-up."
        let feedback = try store.capture(text: feedbackText, at: now,
            receipt: .automatic(.automaticClipboard, sourceApplicationName: "Mail",
                sourceApplicationBundleIdentifier: "com.apple.mail"))[0]
        let originalReceipt = (feedback.id, feedback.capturedAt, feedback.captureDay)
        state.assignProject(feedback, name: "Client Amber")
        state.libraryProject = "Client Amber"
        state.convertToTask(feedback)
        try expect(feedback.isTask && feedback.id == originalReceipt.0 && feedback.capturedAt == originalReceipt.1
            && feedback.captureDay == originalReceipt.2 && feedback.originalText == feedbackText
            && feedback.sourceApplicationName == "Mail" && feedback.projectName == "Client Amber"
            && state.selectedCapture?.id == feedback.id, "Client feedback becomes an actionable task without losing its receipt, source or project")
        let externalBrief = root.appendingPathComponent("Client Amber brief — שלום.txt")
        let briefBytes = Data("An exact client brief with 日本語 and line breaks.\nSecond line.".utf8)
        try briefBytes.write(to: externalBrief)
        let brief = try await store.importFile(externalBrief, at: now)
        try store.attachCapture(brief, to: feedback)
        try files.removeItem(at: externalBrief)
        try expect(store.attachments(for: feedback).map(\.id) == [brief.id]
            && brief.projectName == "Client Amber" && (try Data(contentsOf: store.managedURL(for: brief)!)) == briefBytes,
            "Attaching a brief retains an independent managed original even if its external source disappears")

        // Gather materials from two applications without mixing the clients.
        let research = try store.capture(text: "https://example.invalid/amber/reference", at: now,
            receipt: .automatic(.automaticClipboard, sourceApplicationName: "Safari",
                sourceApplicationBundleIdentifier: "com.apple.Safari"))[0]
        let blueNote = try store.createNote(text: "Client Blue: the launch is next month.", projectName: "Client Blue")
        state.assignProject(research, name: "Client Amber")
        try workspace.setOnShelf([research.id, blueNote.id], included: true)
        workspace.mode = .shelf
        try expect(WorkspaceQuery.items(store.captures, workspace: workspace, project: "Client Amber", filter: .all, query: "").map(\.id) == [research.id]
            && WorkspaceQuery.items(store.captures, workspace: workspace, project: "Client Blue", filter: .all, query: "").map(\.id) == [blueNote.id],
            "One collection shelf keeps gathered materials connected to the right client")
        try workspace.setScratchpad(text: "Resume: compare the references, then send revision two.", project: "Client Amber")
        try workspace.setScratchpad(text: "Resume: confirm next month's launch date.", project: "Client Blue")
        let savedNote = try store.createNote(text: workspace.scratchpad(project: "Client Amber"), projectName: "Client Amber")
        try expect(savedNote.originalText == workspace.scratchpad(project: "Client Amber")
            && savedNote.projectName == "Client Amber" && workspace.scratchpad(project: "Client Blue").contains("launch date"),
            "A project scratchpad becomes a saved resource without copying or altering the other client's notes")

        // Reuse an earlier reply through universal search and return to the task.
        let reply = try store.capture(text: "Thanks for the feedback. I will send an updated draft shortly.",
            at: now.addingTimeInterval(-86_400), receipt: .automatic(.automaticClipboard,
                sourceApplicationName: "Mail", sourceApplicationBundleIdentifier: "com.apple.mail"))[0]
        state.assignProject(reply, name: "Client Amber")
        state.togglePinned(reply)
        try workspace.setSnippetName("Friendly client acknowledgement", for: reply.id)
        state.openLibrary()
        state.openCapture(feedback.id)
        state.selectedDraft?.comment = "Unsaved: confirm the closing line before sending."
        let activeDraft = state.selectedDraft
        state.performSearchCommand()
        state.query = "friendly acknowledgement"
        let results = state.searchGroups.flatMap(\.entries).filter(\.isMatch)
        try expect(results.map { $0.capture.id } == [reply.id], "A named snippet is found across the complete archive by its reusable name")
        try expect(state.copyCapturesToClipboard([reply]) && pasteboard.string(forType: .string) == reply.originalText,
            "Reusing a search result copies the original text to the isolated clipboard")
        state.openCapture(reply.id)
        // Reinvoking global Search from a result must not replace the original
        // return context with a search/detail cycle.
        state.performSearchCommand()
        state.openCapture(reply.id)
        state.back()
        try expect(state.route == .search && state.query == "friendly acknowledgement",
            "Inspecting another search result returns to the same query")
        state.back()
        try expect(state.route == .detail && state.selectedCapture?.id == feedback.id && state.selectedDraft === activeDraft
            && state.selectedDraft?.hasChanges == true && state.libraryProject == "Client Amber",
            "Searching and copying preserves the current task, unfinished edit and project context")
        state.back()
        try expect(state.route == .library && state.libraryProject == "Client Amber",
            "After restoring a task from search, its original back destination remains the client library")
        state.openCapture(feedback.id)

        state.libraryProject = "Client Blue"
        state.openCapture(blueNote.id)
        state.libraryProject = "Client Amber"
        try expect(workspace.selectedCaptureID == feedback.id, "Returning from another client restores Amber's selected task")
        state.libraryProject = "Client Blue"
        try expect(workspace.selectedCaptureID == blueNote.id, "Each client retains an independent selected resource")
        state.libraryProject = "Client Amber"
        state.openCapture(feedback.id)

        // Plan actual work separately from deadlines, then finish and reschedule.
        state.selectedDraft?.planning = TaskPlanning(plannedDay: today, deadline: deadline,
            priority: .high, effortMinutes: 30, checklist: [TaskChecklistItem(text: "Revise opening"), TaskChecklistItem(text: "Send follow-up")])
        state.saveDetail()
        let admin = try store.createTask(text: "Review invoices", at: now,
            planning: TaskPlanning(plannedDay: today, priority: .medium), projectName: "Client Amber")
        try store.reorderTasks([admin, feedback], on: today)
        try expect(TaskPlanningPolicy.today(store.captures, at: now).map(\.id) == [admin.id, feedback.id]
            && feedback.taskPlanning?.deadline == deadline && feedback.reminderAt == nil && feedback.taskPlanning?.effortMinutes == 30,
            "Today's chosen order, effort and deadline persist without inventing a reminder")
        var happyRobotCount = 0
        state.onTaskCompleted = { happyRobotCount += 1 }
        state.toggleTaskCompletion(admin)
        try expect(admin.isCompleted && happyRobotCount == 1
            && TaskPlanningPolicy.today(store.captures, at: now).map(\.id) == [feedback.id],
            "Completing today's task removes it from open work and triggers one happy-robot acknowledgement")
        try store.planTask(feedback, on: tomorrow)
        try expect(TaskPlanningPolicy.today(store.captures, at: now).isEmpty
            && TaskPlanningPolicy.today(store.captures, at: tomorrowDate).map(\.id) == [feedback.id]
            && feedback.taskPlanning?.deadline == deadline && feedback.capturedAt == originalReceipt.1
            && store.attachments(for: feedback).map(\.id) == [brief.id],
            "Rescheduling unfinished work keeps its deadline, source receipt and attachments intact")
        let recurring = try store.createTask(text: "Daily client check-in", at: now,
            planning: TaskPlanning(plannedDay: today, recurrence: .daily,
                checklist: [TaskChecklistItem(text: "Review messages", isCompleted: true)]), projectName: "Client Blue")
        let successor = try store.setTaskCompleted(recurring, completed: true, at: now)!
        try expect(recurring.isCompleted && recurring.taskPlanning?.nextOccurrenceID == successor.id
            && successor.taskPlanning?.plannedDay == tomorrow && successor.projectName == "Client Blue"
            && successor.taskPlanning?.checklist.first?.isCompleted == false,
            "Completing an administrative routine creates one planned next occurrence with reset steps")

        // Restart recovers committed work, scratchpads, collection references and settings.
        try state.clipboardRetention.setPeriod(.days30)
        quickAccess.setQuietMode(true)
        quickAccess.setShortcutStyle(.controlOptionShift)
        let appearance = ThemeSettings(defaults: preferences, systemDarkMode: false)
        appearance.setDarkMode(true); appearance.setBoardOpacity(0.75)
        workspace.mode = .collection
        let reopenedStore = try CaptureStore(root: store.root)
        let reopenedWorkspace = WorkspaceStore(root: store.root)
        let reopenedTask = reopenedStore.captures.first { $0.id == feedback.id }!
        try expect(reopenedTask.taskPlanning == feedback.taskPlanning && reopenedTask.comment == feedback.comment
            && reopenedStore.attachments(for: reopenedTask).map(\.id) == [brief.id]
            && reopenedStore.captures.first { $0.id == admin.id }?.isCompleted == true
            && reopenedStore.captures.contains { $0.id == successor.id },
            "Restart recovers task plans, completed work, recurring successors and attached files")
        try expect(reopenedWorkspace.selectedProject == "Client Amber" && reopenedWorkspace.selectedCaptureID == feedback.id
            && reopenedWorkspace.shelfCaptureIDs == [research.id, blueNote.id]
            && reopenedWorkspace.snippetName(for: reply.id) == "Friendly client acknowledgement"
            && reopenedWorkspace.scratchpad(project: "Client Amber") == workspace.scratchpad(project: "Client Amber"),
            "Restart restores the project, selection, collection, named snippet and saved scratchpad")
        let reopenedQuickAccess = QuickAccessSettings(defaults: preferences)
        let reopenedAppearance = ThemeSettings(defaults: preferences, systemDarkMode: false)
        try expect(ClipboardRetentionService(store: reopenedStore, workspace: reopenedWorkspace).period == .days30
            && reopenedQuickAccess.quietMode && reopenedQuickAccess.shortcutStyle == .controlOptionShift
            && reopenedAppearance.darkModeEnabled && reopenedAppearance.boardOpacity == 0.75,
            "Restart restores privacy, quick-access and appearance preferences from isolated stores")

        let backup = root.appendingPathComponent("Working-day.dabinbackup", isDirectory: true)
        try store.exportBackup(to: backup)
        let restoredStore = try CaptureStore(root: root.appendingPathComponent("Restored"))
        _ = try restoredStore.restoreBackup(from: backup)
        let restoredWorkspace = WorkspaceStore(root: restoredStore.root)
        let restoredBrief = restoredStore.captures.first { $0.id == brief.id }!
        try expect(restoredStore.captures.count == store.captures.count
            && restoredStore.captures.first { $0.id == feedback.id }?.taskPlanning == feedback.taskPlanning
            && (try Data(contentsOf: restoredStore.managedURL(for: restoredBrief)!)) == briefBytes
            && restoredWorkspace.shelfCaptureIDs == workspace.shelfCaptureIDs
            && restoredWorkspace.snippetName(for: reply.id) == workspace.snippetName(for: reply.id)
            && restoredWorkspace.scratchpad(project: "Client Amber") == workspace.scratchpad(project: "Client Amber")
            && restoredWorkspace.scratchpad(project: "Client Blue") == workspace.scratchpad(project: "Client Blue"),
            "Portable backup restores the connected working day, both clients' notes and exact managed file bytes")
        print("PASS: \(checks) connected capture, client collection, clipboard reuse, task planning, restart and backup scenarios")
    }
}
