import AppKit
import Foundation

@MainActor private final class HistoryNotifications: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .allowed }
    func requestAuthorization() async throws -> Bool { fatalError("History QA never requests permission") }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { fatalError("History QA never schedules notifications") }
    func removePending(_ identifiers: [String]) {}
    func removeDelivered(_ identifiers: [String]) {}
}

@main struct NavigationHistoryTests {
    @MainActor private static var checks = 0
    @MainActor private static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        guard try value() else { throw NSError(domain: "NavigationHistoryTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    @MainActor private static func modelTests() throws {
        var history = NavigationHistory()
        try expect(!history.canGoBack && !history.canGoForward && history.back() == nil && history.forward() == nil,
                   "Empty history never invents a destination")
        var first = NavigationSnapshot(); first.route = .library; first.project = "Example"
        history.updateCurrent(first)
        var detail = first; detail.route = .detail; detail.selectedCaptureID = UUID()
        history.visit(detail)
        try expect(history.canGoBack && !history.canGoForward && history.entries.count == 2, "A detail is a visit")
        _ = history.back()
        var refined = first; refined.query = "metadata query"; refined.filter = .tasks
        history.updateCurrent(refined)
        try expect(history.canGoForward && history.entries.count == 2, "A current refinement retains Forward")
        history.visit(refined)
        try expect(history.canGoForward && history.entries.count == 2, "Reselecting same destination is a no-op")
        try expect(history.forward()?.selectedCaptureID == detail.selectedCaptureID, "Forward restores actual visited capture")
        _ = history.back()
        var other = first; other.project = "Other"
        history.visit(other)
        try expect(!history.canGoForward && history.entries.count == 2 && history.current?.project == "Other", "New navigation cuts Forward")
        for _ in 0..<240 { var item = detail; item.selectedCaptureID = UUID(); history.visit(item) }
        try expect(history.entries.count == 100 && history.index == 99, "History bounds include the current entry")
        for _ in 0..<150 { _ = history.back() }
        try expect(history.index == 0 && !history.canGoBack, "Rapid Back stops at root")
        for _ in 0..<150 { _ = history.forward() }
        try expect(history.index == 99 && !history.canGoForward, "Rapid Forward stops at end")
        let survivingID = history.entries[25].selectedCaptureID!
        history.reconcile { snapshot in snapshot.selectedCaptureID == survivingID ? snapshot : nil }
        try expect(history.entries.count == 1 && history.current?.selectedCaptureID == survivingID, "Pruning keeps an exact identity")
        var anchor = NavigationViewportAnchor(itemID: "removed", offset: 12, neighbors: ["nearest", "further"])
        try expect(anchor.resolving(against: ["nearest", "further"])?.itemID == "nearest", "Vanished anchor follows surviving neighbor")
        anchor.offset = .nan
        try expect(anchor.resolving(against: ["nearest"])?.offset == 0, "Nonfinite viewport offset is sanitized")
        try expect(anchor.resolving(against: []) == nil, "No surviving anchor is a safe nil")
        let fields = Set(Mirror(reflecting: NavigationSnapshot()).children.compactMap(\.label))
        try expect(fields.isDisjoint(with: ["capture", "draft", "comment", "text", "content", "fileBody", "zoom", "frame"]),
                   "Snapshot excludes content, draft copies, zoom and geometry")
    }

    @MainActor private static func projectPersistenceTests() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinProjectScopeQA-\(UUID())")
        let defaultsName = "DaBinProjectScopeQA.\(UUID())"
        let defaults = UserDefaults(suiteName: defaultsName)!
        let board = NSPasteboard(name: .init(defaultsName))
        let store = try CaptureStore(root: root)
        let previews = PreviewService(store: store, defaults: defaults)
        let auto = AutoCaptureService(settings: AutoCaptureSettings(defaults: defaults), input: InputService(store: store),
            pasteboardProvider: { fatalError("Project scope QA never reads the clipboard") }, sourceApplicationProvider: { nil })
        let state = AppState(store: store, previews: previews,
            reminders: ReminderService(store: store, client: HistoryNotifications()), autoCapture: auto,
            captureClipboard: CaptureClipboardService(pasteboard: board))
        defer {
            auto.shutdown(); state.focusSessions.shutdown(); state.shutdownNotificationPresentation(); previews.shutdown()
            board.releaseGlobally(); defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: root)
        }
        let first = try store.capture(text: "First project scope original", projectName: "First")[0]
        let second = try store.capture(text: "Second project scope original", projectName: "Second")[0]
        state.openLibrary()
        try expect(state.navigateProject("First"), "A successfully persisted named scope reports success")
        state.workspace.selectedCaptureID = first.id
        let before = state.workspace.snapshot
        let beforeEntries = state.navigationHistory.entries
        let beforeIndex = state.navigationHistory.index
        let beforeRevision = state.navigationTransitionRevision
        state.workspace.failureInjector = { throw CaptureStoreError.injectedInterruption }
        try expect(!state.navigateProject(nil, unfiledOnly: true), "A failed Unfiled scope reports failure to its picker")
        try expect(state.libraryProject == "First" && state.workspace.snapshot == before
            && state.workspace.selectedCaptureID == first.id && state.workspace.error != nil
            && state.status?.severity == .error,
                   "A failed project change keeps displayed and persisted scope and selected item together")
        try expect(state.navigationHistory.entries == beforeEntries && state.navigationHistory.index == beforeIndex
            && state.navigationTransitionRevision == beforeRevision,
                   "A failed project change neither moves history nor replaces its current destination")
        try expect(try WorkspaceStore.readSnapshot(at: root) == before,
                   "A failed project change preserves the saved workspace exactly")
        state.libraryProject = "Second"
        try expect(state.libraryProject == "First" && state.workspace.snapshot == before,
                   "Direct project filtering also commits before publishing and remains unchanged after a failed write")
        state.workspace.failureInjector = nil
        var writes = 0
        state.workspace.failureInjector = { writes += 1 }
        try expect(state.navigateProject(nil, unfiledOnly: true) && writes == 1,
                   "Retry commits project and Unfiled together in one save")
        try expect(state.libraryProject == nil && state.workspace.selectedProject == nil
            && state.workspace.explorerUnfiledOnly && state.navigationHistory.entries.count == beforeEntries.count + 1,
                   "Successful retry creates one new destination after the unchanged old visit")
        try expect(state.navigateProject("Second") && state.libraryProject == "Second"
            && !state.workspace.explorerUnfiledOnly, "Selecting a named project clears the Unfiled scope atomically")
        state.workspace.selectedCaptureID = second.id
        state.workspace.failureInjector = nil
        let beforeBack = state.workspace.snapshot
        let backEntries = state.navigationHistory.entries
        let backIndex = state.navigationHistory.index
        let backRevision = state.navigationRestorationRevision
        state.workspace.failureInjector = { throw CaptureStoreError.injectedInterruption }
        state.back()
        try expect(state.route == .library && state.libraryProject == "Second"
            && state.workspace.snapshot == beforeBack && state.workspace.selectedCaptureID == second.id,
                   "Failed Back restoration keeps the displayed project and selected capture unchanged")
        try expect(state.navigationHistory.entries == backEntries && state.navigationHistory.index == backIndex
            && state.navigationRestorationRevision == backRevision && state.canGoBack,
                   "Failed Back retains exact history and remains retryable")
        state.workspace.failureInjector = nil
        state.back()
        try expect(state.libraryProject == nil && state.workspace.selectedProject == nil
            && state.workspace.explorerUnfiledOnly && state.navigationHistory.index == backIndex - 1,
                   "Retrying Back restores the Unfiled destination after its scope write succeeds")
        let beforeForward = state.workspace.snapshot
        let forwardEntries = state.navigationHistory.entries
        let forwardIndex = state.navigationHistory.index
        state.workspace.failureInjector = { throw CaptureStoreError.injectedInterruption }
        state.forward()
        try expect(state.libraryProject == nil && state.workspace.snapshot == beforeForward
            && state.navigationHistory.entries == forwardEntries && state.navigationHistory.index == forwardIndex
            && state.canGoForward, "Failed Forward retains its old scope and branch without publishing the target")
        state.workspace.failureInjector = nil
        state.forward()
        try expect(state.libraryProject == "Second" && state.workspace.selectedProject == "Second"
            && !state.workspace.explorerUnfiledOnly && state.workspace.selectedCaptureID == second.id,
                   "Retrying Forward restores its project's own selected identity")
        let reopened = WorkspaceStore(root: root)
        try expect(reopened.snapshot == state.workspace.snapshot && reopened.selectedProject == "Second"
            && reopened.selectedCaptureID == second.id, "Restart sees the same destination that successful Forward displays")
        state.back(); state.back()
        try expect(state.libraryProject == "First" && !state.workspace.explorerUnfiledOnly
            && state.workspace.selectedCaptureID == first.id,
                   "Back through Unfiled restores the first project's original per-project selection")
        let currentEntries = state.navigationHistory.entries
        let currentIndex = state.navigationHistory.index
        state.navigationWindowInteractionBlocked = true
        try expect(!state.navigateProject("Second") && state.libraryProject == "First"
            && state.navigationHistory.entries == currentEntries && state.navigationHistory.index == currentIndex,
                   "A blocked project command reports failure without writing or creating a visit")
        state.navigationWindowInteractionBlocked = false
    }

    @MainActor private static func removalReturnPersistenceTests() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinRemovalReturnQA-\(UUID())")
        let defaultsName = "DaBinRemovalReturnQA.\(UUID())"
        let defaults = UserDefaults(suiteName: defaultsName)!
        let board = NSPasteboard(name: .init(defaultsName))
        let store = try CaptureStore(root: root)
        let previews = PreviewService(store: store, defaults: defaults)
        let auto = AutoCaptureService(settings: AutoCaptureSettings(defaults: defaults), input: InputService(store: store),
            pasteboardProvider: { fatalError("Removal return QA never reads the clipboard") }, sourceApplicationProvider: { nil })
        let state = AppState(store: store, previews: previews,
            reminders: ReminderService(store: store, client: HistoryNotifications()), autoCapture: auto,
            captureClipboard: CaptureClipboardService(pasteboard: board))
        defer {
            auto.shutdown(); state.focusSessions.shutdown(); state.shutdownNotificationPresentation(); previews.shutdown()
            board.releaseGlobally(); defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: root)
        }
        let task = try store.createTask(text: "Surviving project task", projectName: "Fixture")
        let child = try store.capture(text: "Attachment to remove safely", parentTask: task)[0]
        state.openLibrary(); state.navigateProject("Fixture")
        state.openCapture(task.id, focus: "comment")
        let taskDraft = state.selectedDraft!
        taskDraft.commentComposer = "Pending parent comment survives child removal"
        taskDraft.pendingChecklistText = "Pending parent checklist survives child removal"
        let taskViewport = NavigationViewportAnchor(itemID: ProjectWorkspaceIdentity.capture(task.id), offset: -18)
        state.workspaceViewport = taskViewport
        state.openCapture(child.id)
        let before = state.workspace.snapshot
        state.workspace.failureInjector = { throw CaptureStoreError.injectedInterruption }
        await state.removeCapture(child)
        try expect(!store.captures.contains { $0.id == child.id } && store.trashedCaptures.contains { $0.id == child.id }
            && store.captures.contains { $0 === task }, "A failed return does not pretend the successfully trashed attachment was restored")
        try expect(state.route == .library && state.libraryProject == "Fixture" && state.workspace.snapshot == before
            && state.selectedCapture == nil && state.selectedDraft == nil && state.detailFocus == nil,
                   "Failed removal return leaves deleted Detail through a coherent Library in the actual persisted scope")
        try expect(state.navigationHistory.current?.route == .library
            && state.navigationHistory.current?.project == state.workspace.selectedProject
            && !state.navigationHistory.entries.contains { $0.selectedCaptureID == child.id }
            && state.navigationHistory.entries.contains { $0.route == .detail && $0.selectedCaptureID == task.id },
                   "History prunes the deleted visit, aligns fallback scope, and retains the surviving parent for Back retry")
        try expect(state.status?.severity == .warning && state.status?.text.contains("Moved to Recently Deleted") == true
            && state.status?.text.contains("Use Back to try again") == true,
                   "Successful trash and failed workspace return have one specific warning rather than a false success")
        let failedEntries = state.navigationHistory.entries
        let failedIndex = state.navigationHistory.index
        state.back()
        try expect(state.route == .library && state.navigationHistory.entries == failedEntries
            && state.navigationHistory.index == failedIndex && state.workspace.snapshot == before,
                   "Retry while storage is still unavailable keeps the safe fallback and original parent history")
        let reread = try CaptureStore(root: root)
        try expect(reread.trashedCaptures.contains { $0.id == child.id }
            && reread.captures.first { $0.id == task.id }?.originalText == task.originalText,
                   "Restart confirms committed trash and unchanged surviving parent content")
        state.workspace.failureInjector = nil
        state.back()
        try expect(state.route == .detail && state.selectedCapture === task && state.selectedDraft === taskDraft
            && state.detailFocus == "comment" && state.workspaceViewport == taskViewport
            && state.workspace.selectedCaptureID == task.id,
                   "Recovered storage lets Back restore the exact surviving parent's draft, focus, viewport and selection")
        try expect(taskDraft.commentComposer == "Pending parent comment survives child removal"
            && taskDraft.pendingChecklistText == "Pending parent checklist survives child removal"
            && task.comment.isEmpty && task.taskPlanning?.checklist.isEmpty != false,
                   "Return retry preserves unfinished comment and checklist without silently committing either")
        let reopenedWorkspace = WorkspaceStore(root: root)
        try expect(reopenedWorkspace.snapshot == state.workspace.snapshot && reopenedWorkspace.selectedCaptureID == task.id,
                   "Successful retry persists the same parent scope that the UI now displays")
        let nextChild = try store.capture(text: "Batch attachment to remove", parentTask: task)[0]
        let other = try store.capture(text: "Another batch item", projectName: "Fixture")[0]
        state.openCapture(nextChild.id)
        state.workspace.failureInjector = { throw CaptureStoreError.injectedInterruption }
        await state.removeCaptures([nextChild, other])
        try expect([nextChild, other].allSatisfy { item in store.trashedCaptures.contains { $0.id == item.id } }
            && state.route == .library && state.status?.severity == .warning
            && state.status?.text.contains("couldn’t restore the previous workspace") == true,
                   "Batch success preserves its newly generated failed-return warning after later items trash successfully")
        state.workspace.failureInjector = nil
        state.back()
        try expect(state.selectedCapture === task && state.selectedDraft === taskDraft
            && taskDraft.pendingChecklistText == "Pending parent checklist survives child removal",
                   "Batch fallback retains the same surviving parent and unfinished draft for Back retry")
        state.openLibrary()
        let ordinary = try store.capture(text: "Ordinary batch removal", projectName: "Fixture")[0]
        state.status = AppStatusMessage(text: "An unrelated earlier warning", severity: .warning)
        await state.removeCaptures([ordinary])
        try expect(state.status?.severity == .success && state.status?.text == "Moved 1 items to Recently Deleted.",
                   "An unrelated old warning is not mistaken for a new batch return failure")
    }

    @MainActor private static func integrationTests() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinHistoryQA-\(UUID())")
        let defaultsName = "DaBinHistoryQA.\(UUID())"
        let defaults = UserDefaults(suiteName: defaultsName)!
        let board = NSPasteboard(name: .init(defaultsName))
        let store = try CaptureStore(root: root)
        let previews = PreviewService(store: store, defaults: defaults)
        let auto = AutoCaptureService(settings: AutoCaptureSettings(defaults: defaults), input: InputService(store: store),
            pasteboardProvider: { fatalError("History QA never reads the clipboard") }, sourceApplicationProvider: { nil })
        let state = AppState(store: store, previews: previews,
            reminders: ReminderService(store: store, client: HistoryNotifications()), autoCapture: auto,
            captureClipboard: CaptureClipboardService(pasteboard: board))
        defer {
            auto.shutdown(); state.focusSessions.shutdown(); state.shutdownNotificationPresentation(); previews.shutdown()
            board.releaseGlobally(); defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: root)
        }
        let task = try store.createTask(text: "Fictional feedback task")
        try store.setOrganization(task, pinned: false, projectName: "Example Client")
        let attachment = try store.capture(text: "Fictional source note", parentTask: task)[0]
        let other = try store.capture(text: "Other fictional capture")[0]
        try state.workspace.createProject(name: "Example Client", colorHex: "7568D8")
        state.openLibrary(); state.navigateProject("Example Client")
        let itemID = ProjectWorkspaceIdentity.capture(task.id)
        let neighbor = ProjectWorkspaceIdentity.capture(attachment.id)
        state.projectPresentation["Example Client"] = ProjectNavigationPresentation(filterRawValue: "Tasks",
            dateFilter: .lastSevenDays, compact: true, selectedIDs: [itemID],
            selectionAnchor: itemID, focusedID: itemID,
            viewport: NavigationViewportAnchor(itemID: itemID, offset: -14, neighbors: [neighbor]))
        state.openCapture(task.id, focus: "comment")
        let draft = state.selectedDraft!
        draft.commentComposer = "Unsaved private comment stays in its owner"
        draft.hasError = true; draft.message = "Fictional save failure"
        state.openCapture(attachment.id)
        state.back()
        try expect(state.route == .detail && state.selectedCapture?.id == task.id && state.selectedDraft === draft,
                   "Task attachment returns to same live task draft")
        try expect(draft.commentComposer.contains("Unsaved") && draft.hasError && draft.message == "Fictional save failure",
                   "Back preserves draft text and error without copying either into history")
        state.back()
        try expect(state.route == .library && state.libraryProject == "Example Client", "Second Back restores project")
        let presentation = state.projectPresentation["Example Client"]!
        try expect(presentation.filterRawValue == "Tasks" && presentation.dateFilter == .lastSevenDays
            && presentation.compact && presentation.selectedIDs == [itemID]
            && presentation.viewport?.itemID == itemID && presentation.viewport?.offset == -14,
                   "Project refinements, selection and stable viewport return intact")
        state.forward()
        try expect(state.selectedDraft === draft && state.selectedCapture?.id == task.id, "Forward returns the same task owner")
        state.back()
        let entryCount = state.navigationHistory.entries.count
        state.didAutoCapture([other])
        try expect(state.canGoForward && state.navigationHistory.entries.count == entryCount, "Automatic arrival preserves Forward")
        state.showSettings()
        try expect(!state.canGoForward, "New Settings visit cuts old Forward branch")
        state.back(); state.forward()
        try expect(state.route == .settings, "Settings shares true Forward")
        state.back()
        state.performSearchCommand(); state.query = "Fictional"
        state.selectSearchProject("Example Client"); state.searchSource = "Test Editor"
        state.searchDateAnchor = task.captureDay; state.searchSelectedResultID = itemID
        state.searchColumnScrollIDs = [task.captureDay: itemID]
        state.searchColumnViewports = [task.captureDay: NavigationViewportAnchor(itemID: itemID, offset: 17, neighbors: [neighbor])]
        state.searchSelectedResultID = neighbor
        state.openCapture(task.id); state.back()
        try expect(state.searchSelectedResultID == itemID, "Details icon commits the clicked result selection before leaving Search")
        state.forward(); state.showSettings(); state.performSearchCommand()
        try expect(state.route == .search && state.query == "Fictional" && state.searchProject == "Example Client"
            && state.searchDateAnchor == task.captureDay && state.searchColumnScrollIDs[task.captureDay] == itemID
            && state.searchColumnViewports[task.captureDay]?.offset == 17,
                   "Search reopens the same refined session through result Settings")
        state.back()
        try expect(state.route == .library, "Reopened Search returns to origin without parent loop")
        state.openNewNote(); state.newNoteText = "Unsaved fictional note"
        state.showTrash(); state.back()
        try expect(state.route == .newNote && state.newNoteText == "Unsaved fictional note", "Auxiliary return preserves composer")
        state.back(); state.forward()
        try expect(state.route == .newNote && state.newNoteText == "Unsaved fictional note", "Forward retains composer draft owner")
        state.back(); state.openCapture(other.id); state.showSettings()
        await state.removeCapture(other)
        try expect(state.route == .settings, "Removal after leaving a detail does not navigate away from the current page")
        state.back()
        try expect(state.route == .library && state.selectedCapture == nil, "Deleted detail resolves to parent, never resurrects data")
        state.openCapture(task.id); state.back()
        let index = state.navigationHistory.index
        state.navigationValidationBlocked = true; state.forward()
        try expect(state.navigationHistory.index == index, "Unresolved editor validation blocks history navigation")
        state.navigationValidationBlocked = false
        state.navigationWindowInteractionBlocked = true; state.forward()
        try expect(state.navigationHistory.index == index, "Window interaction blocks history navigation")
        state.navigationWindowInteractionBlocked = false
        state.forward()
        try expect(state.selectedCapture?.id == task.id, "Navigation resumes after blocker ends")
        state.back(); state.selectWeeklyDay(Date().addingTimeInterval(-172800))
        let beforeDay = state.selectedDay
        state.moveDay(-1); state.back()
        try expect(Calendar.current.isDate(state.selectedDay, inSameDayAs: beforeDay), "Day navigation records deliberate calendar destination")
        state.forward()
        try expect(Calendar.current.dateComponents([.day], from: state.selectedDay, to: beforeDay).day == 1,
                   "Forward returns visited day rather than inventing tomorrow")
        state.performSearchCommand(); state.query = "Latest remembered words"
        _ = state.workspaceZoom.beginInteraction()
        state.updateGlobalSearch("Words typed during a pinch")
        try expect(state.query == "Words typed during a pinch", "Refinement edits are not discarded during zoom on the same route")
        state.workspaceZoom.finishInteraction(); state.back()
        state.performSearchCommand()
        try expect(state.query == "Words typed during a pinch" && state.searchScope == .all,
                   "Fresh Search retains latest query rather than stale unrelated workspace snapshot")
        state.openCapture(task.id)
        draft.title = "   "
        state.saveDetail()
        let validationIndex = state.navigationHistory.index
        state.back()
        try expect(draft.validationIssue == .title && state.navigationHistory.index == validationIndex,
                   "Actual rejected title Save blocks navigation until the field is corrected")
        let originalPlan = draft.planning
        let committedPlan = task.taskPlanning
        draft.planning.priority = .high
        draft.pendingChecklistText = "Uncommitted next step kept with the invalid title"
        let retainedPlan = draft.planning
        try expect(state.canKeepDetailDraftAndGoBack,
                   "An invalid Detail draft has an explicit recovery return without unlocking ordinary Back")
        state.navigationValidationBlocked = true
        try expect(!state.canKeepDetailDraftAndGoBack && !state.keepDetailDraftAndGoBack(),
                   "Detail recovery cannot waive global editor validation")
        state.navigationValidationBlocked = false
        state.navigationWindowInteractionBlocked = true
        try expect(!state.canKeepDetailDraftAndGoBack && !state.keepDetailDraftAndGoBack(),
                   "Detail recovery cannot interrupt a window interaction")
        state.navigationWindowInteractionBlocked = false
        state.setTutorialPresented(true)
        try expect(!state.canKeepDetailDraftAndGoBack && !state.keepDetailDraftAndGoBack(),
                   "Detail recovery cannot leave an active tutorial")
        state.setTutorialPresented(false)
        state.pendingRemoval = task
        try expect(!state.canKeepDetailDraftAndGoBack && !state.keepDetailDraftAndGoBack(),
                   "Detail recovery cannot bypass a pending removal")
        state.pendingRemoval = nil
        state.isDailyDropTargeted = true
        try expect(!state.canKeepDetailDraftAndGoBack && !state.keepDetailDraftAndGoBack(),
                   "Detail recovery cannot interrupt a drop")
        state.isDailyDropTargeted = false
        _ = state.workspaceZoom.beginInteraction()
        try expect(!state.canKeepDetailDraftAndGoBack && !state.keepDetailDraftAndGoBack(),
                   "Detail recovery cannot interrupt workspace zoom")
        state.workspaceZoom.finishInteraction()
        try expect(state.route == .detail && state.navigationHistory.index == validationIndex
            && state.selectedDraft === draft && draft.validationIssue == .title,
                   "Refused recovery actions retain the exact invalid draft and history position")
        let recoveryURL = root.appendingPathComponent("Drafts.json")
        try? FileManager.default.removeItem(at: recoveryURL)
        try FileManager.default.createDirectory(at: recoveryURL, withIntermediateDirectories: false)
        try expect(!state.keepDetailDraftAndGoBack() && state.draftPersistenceError != nil
            && state.route == .detail && state.navigationHistory.index == validationIndex
            && state.selectedDraft === draft && draft.title == "   " && draft.validationIssue == .title
            && draft.pendingChecklistText == "Uncommitted next step kept with the invalid title",
                   "Failed recovery persistence leaves invalid text and checklist in their Detail owner")
        try FileManager.default.removeItem(at: recoveryURL)
        try expect(state.keepDetailDraftAndGoBack() && state.route == .search
            && state.navigationHistory.index == validationIndex - 1 && state.draftPersistenceError == nil,
                   "Explicit recovery persists before returning to the preceding refined Search")
        let savedRecovery = DraftArchive(root: root).load()?.details.first { $0.captureID == task.id }
        try expect(savedRecovery?.title == "   " && savedRecovery?.planning == retainedPlan
            && savedRecovery?.commentComposer == draft.commentComposer
            && savedRecovery?.pendingChecklistText == draft.pendingChecklistText,
                   "Recovery storage contains the complete invalid draft and pending comment and checklist")
        try expect(task.title == "Fictional feedback task" && task.taskPlanning == committedPlan && task.comment.isEmpty,
                   "Keeping the invalid draft never applies its title, plan or comment to the capture")
        state.forward()
        try expect(state.route == .detail && state.selectedCapture === task && state.selectedDraft === draft
            && draft.title == "   " && draft.planning == retainedPlan && draft.validationIssue == .title
            && draft.hasUnresolvedValidation && draft.pendingChecklistText == "Uncommitted next step kept with the invalid title",
                   "Forward restores the same invalid draft with its validation and pending work intact")
        state.back()
        try expect(state.navigationHistory.index == validationIndex,
                   "Explicit recovery does not weaken subsequent ordinary Back validation")
        draft.title = task.title
        draft.planning = originalPlan
        draft.pendingChecklistText = ""
        state.back()
        try expect(state.navigationHistory.index == validationIndex - 1,
                   "Correcting validation input immediately restores navigation without saving draft text")
        for parent in [BoardRoute.library, .reminders] {
            if parent == .library { state.openLibrary(); state.navigateProject("Example Client") }
            else { state.showReminders() }
            state.openCapture(task.id)
            draft.title = String(repeating: "x", count: 2_001)
            state.saveDetail()
            try expect(state.keepDetailDraftAndGoBack() && state.route == parent,
                       "Invalid Detail recovery returns to its actual Projects or Today parent")
            state.forward()
            try expect(state.selectedDraft === draft && draft.title.count == 2_001 && draft.validationIssue == .title,
                       "Projects and Today recovery preserve an overlong title for later correction")
            draft.title = task.title
            state.back()
        }
        try expect(!state.canKeepDetailDraftAndGoBack && !state.keepDetailDraftAndGoBack(),
                   "Detail recovery is unavailable on ordinary non-Detail routes")
        state.openNewTask(); state.newTaskDraft.text = ""
        state.saveNewTask()
        try expect(state.newTaskDraft.hasUnresolvedValidation && state.isNavigationBlocked,
                   "Actual empty-task Save blocks history while invalid")
        state.newTaskDraft.text = "Valid fictional draft"
        try expect(!state.isNavigationBlocked, "Corrected task draft unlocks navigation without an implicit save")
        state.cancelNewTask()
        try state.workspace.setScratchpad(text: "Original fictional note", project: "Old Notes")
        state.performSearchCommand()
        state.openSearchNote(state.workspace.snapshot.scratchpads[WorkspaceSnapshot.projectKey("Old Notes")]!)
        state.back()
        try expect(state.searchSelectedResultID == "note:" + WorkspaceSnapshot.projectKey("Old Notes"),
                   "Note edit action preserves clicked note selection on Back")
        state.forward(); state.showSettings()
        try state.workspace.setScratchpad(text: "Current fictional note", project: "Renamed Notes")
        state.projectWasRenamed(from: "Old Notes", to: "Renamed Notes")
        state.back()
        try expect(state.route == .searchNote && state.selectedSearchNote?.projectName == "Renamed Notes"
            && state.selectedSearchNote?.text == "Current fictional note",
                   "Explicit project rename resolves note history to current owner instead of stale note content")
        state.openLibrary()
        state.openCapture(task.id, focus: "comment")
        let survivingTaskViewport = NavigationViewportAnchor(itemID: itemID, offset: -29)
        state.workspaceViewport = survivingTaskViewport
        state.openCapture(attachment.id)
        await state.removeCapture(attachment)
        try expect(state.route == .detail && state.selectedCapture === task && state.selectedDraft === draft
            && state.detailFocus == "comment" && state.workspaceViewport == survivingTaskViewport
            && draft.commentComposer.contains("Unsaved"),
            "Deleting the displayed attachment restores its surviving task's own focus, viewport and unfinished draft")
        try expect(!state.navigationHistory.entries.contains { $0.route == .detail && $0.selectedCaptureID == attachment.id },
            "Removed detail visits are pruned rather than replacing their parent's presentation")
        state.back()
        try expect(state.route == .library, "Back after attachment removal reaches the task's preceding Library")
        state.forward()
        try expect(state.selectedCapture === task && state.selectedDraft === draft && !state.canGoForward,
            "Forward after removal returns only the surviving task, never the deleted attachment")
        let reread = try CaptureStore(root: root)
        try expect(reread.captures.contains { $0.id == task.id } && task.comment.isEmpty,
                   "History does not save unfinished draft content to captures")
    }

    @MainActor private static func scratchpadRemovalFlowTests() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinNoteRemovalQA-\(UUID())")
        let defaultsName = "DaBinNoteRemovalQA.\(UUID())"
        let defaults = UserDefaults(suiteName: defaultsName)!
        let board = NSPasteboard(name: .init(defaultsName))
        let store = try CaptureStore(root: root)
        let previews = PreviewService(store: store, defaults: defaults)
        let auto = AutoCaptureService(settings: AutoCaptureSettings(defaults: defaults), input: InputService(store: store),
            pasteboardProvider: { fatalError("Note removal QA never reads the clipboard") }, sourceApplicationProvider: { nil })
        let state = AppState(store: store, previews: previews,
            reminders: ReminderService(store: store, client: HistoryNotifications()), autoCapture: auto,
            captureClipboard: CaptureClipboardService(pasteboard: board))
        defer {
            auto.shutdown(); state.focusSessions.shutdown(); state.shutdownNotificationPresentation(); previews.shutdown()
            board.releaseGlobally(); defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: root)
        }
        let project = "Fictional note project"
        let key = WorkspaceSnapshot.projectKey(project)
        let text = "Current live note\nעברית 日本語 📝\n  spacing  "
        let copy = try store.capture(text: text, projectName: project)[0]
        try state.workspace.setScratchpad(text: text, project: project)
        state.openLibrary()
        let stale = WorkspaceScratchpad(text: "Stale search result", projectName: project, updatedAt: .distantPast)
        let note = state.workspace.snapshot.scratchpads[key]!
        state.requestScratchpadRemoval(stale)
        try expect(state.pendingScratchpadRemoval == note && state.isNavigationBlocked,
                   "Note confirmation freezes the actual current project text/date rather than a stale card's excerpt")
        let history = state.navigationHistory.entries
        state.showSettings(); state.requestRemoval(copy)
        try expect(state.route == .library && state.navigationHistory.entries == history && state.pendingRemoval == nil,
                   "Pending note deletion blocks navigation and cannot overlap a capture confirmation")
        state.pendingScratchpadRemoval = nil
        state.requestRemoval(copy); state.requestScratchpadRemoval(note)
        try expect(state.pendingRemoval === copy && state.pendingScratchpadRemoval == nil,
                   "A capture confirmation also blocks a second note confirmation")
        state.pendingRemoval = nil
        state.requestScratchpadRemoval(note)
        try state.workspace.setScratchpad(text: text + "\nLater edit", project: project)
        try expect(!state.confirmScratchpadRemoval() && state.pendingScratchpadRemoval == nil
            && state.workspace.deletedScratchpads.isEmpty && state.workspace.scratchpad(project: project) == text + "\nLater edit"
            && state.status?.severity == .error,
                   "A changed note refuses stale confirmation, preserves later edits and reports a retryable error")
        try state.workspace.setScratchpad(text: text, project: project)
        state.requestScratchpadRemoval(stale)
        let before = state.workspace.snapshot
        state.workspace.failureInjector = { throw CaptureStoreError.injectedInterruption }
        try expect(!state.confirmScratchpadRemoval() && state.workspace.snapshot == before
            && state.workspace.scratchpad(project: project) == text && !state.canUndoRemoval && state.status?.severity == .error,
                   "Failed confirmed deletion leaves live text, durable receipt set and Undo unchanged")
        state.workspace.failureInjector = nil
        state.requestScratchpadRemoval(stale)
        try expect(state.confirmScratchpadRemoval() && state.canUndoRemoval && state.workspace.scratchpad(project: project).isEmpty,
                   "Retry atomically deletes the current live note and exposes shared Undo")
        let receipt = state.workspace.deletedScratchpads.first!
        try expect(copy.originalText == text && store.captures.contains { $0 === copy },
                   "Deleting the live note never deletes its independent saved capture copy")
        state.workspace.failureInjector = { throw CaptureStoreError.injectedInterruption }
        await state.undoLastRemoval()
        try expect(state.canUndoRemoval && state.workspace.deletedScratchpads == [receipt] && state.workspace.scratchpad(project: project).isEmpty,
                   "Failed note Undo retains the same receipt and remains retryable")
        state.workspace.failureInjector = nil
        await state.undoLastRemoval()
        try expect(!state.canUndoRemoval && state.workspace.snapshot.scratchpads[key] == receipt.note && state.workspace.deletedScratchpads.isEmpty,
                   "Retrying shared Undo restores exact content/date once")
        state.performSearchCommand()
        state.openSearchNote(state.workspace.snapshot.scratchpads[key]!)
        try expect(state.route == .searchNote, "The deletion fixture actually opens the Search note editor")
        state.requestScratchpadRemoval(stale)
        try expect(state.confirmScratchpadRemoval() && state.route == .library && state.selectedSearchNote == nil,
                   "Deleting the active Search note returns safely to Library and releases its editor context")
        let searchReceipt = state.workspace.deletedScratchpads.first!
        state.back()
        try expect(state.route == .search && state.selectedSearchNote == nil && state.workspace.scratchpad(project: project).isEmpty
            && state.searchSelectedResultID != "note:" + key
            && !state.navigationHistory.entries.contains { $0.route == .searchNote || $0.selectedNoteProjectKey == key },
                   "Back after deletion returns to Search, clearing the deleted note visit and selection instead of opening a blank editor")
        try expect(state.workspace.projectNames.contains(project), "Pruning deleted note navigation retains its empty project marker")
        try expect(state.restoreScratchpad(searchReceipt) && state.workspace.scratchpad(project: project) == text,
                   "Explicit restoration makes the recovered text available to the original project")
        if state.route == .searchNote {
            try expect(state.selectedSearchNote == searchReceipt.note, "An active restored Search editor receives the restored current note/date")
        }
        state.openLibrary()
        state.requestScratchpadRemoval(stale)
        try expect(state.confirmScratchpadRemoval(), "Prepare a note receipt for capture/note Undo exclusivity")
        let exclusiveNote = state.workspace.deletedScratchpads.first!
        await state.removeCapture(copy)
        await state.undoLastRemoval()
        try expect(store.captures.contains { $0.id == copy.id } && state.workspace.deletedScratchpads.contains { $0.id == exclusiveNote.id }
            && state.workspace.scratchpad(project: project).isEmpty,
                   "A later capture deletion makes Undo restore only that capture while retaining older note recovery")
        try expect(state.restoreScratchpad(exclusiveNote), "Restore the live note for reverse Undo ordering")
        let restoredCopy = store.captures.first { $0.id == copy.id }!
        await state.removeCapture(restoredCopy)
        state.requestScratchpadRemoval(stale)
        try expect(state.confirmScratchpadRemoval(), "A later note deletion supersedes the older capture Undo")
        await state.undoLastRemoval()
        try expect(state.workspace.scratchpad(project: project) == text && store.trashedCaptures.contains { $0.id == copy.id },
                   "A later note deletion makes Undo restore only the note while the older capture remains in trash")
        state.requestScratchpadRemoval(stale)
        try expect(state.confirmScratchpadRemoval(), "Prepare shared note Undo for failed/stale batch regression")
        let batchReceipt = state.workspace.deletedScratchpads.first!
        let failedCapture = try store.capture(text: "Capture whose trash commit fails")[0]
        store.failureInjector = { if $0 == .beforeMetadataSave { throw CaptureStoreError.injectedInterruption } }
        await state.removeCaptures([failedCapture])
        try expect(state.canUndoRemoval && state.workspace.deletedScratchpads == [batchReceipt]
            && store.captures.contains { $0 === failedCapture } && state.status?.severity == .error,
                   "An all-failed capture batch preserves the preceding note Undo and reports the actual failure")
        store.failureInjector = nil
        let staleCapture = store.trashedCaptures.first { $0.id == copy.id }!
        await state.removeCaptures([staleCapture])
        try expect(state.canUndoRemoval && state.workspace.deletedScratchpads == [batchReceipt] && state.status?.severity == .warning,
                   "An already-deleted batch does not replace a meaningful note Undo with stale capture IDs")
        await state.undoLastRemoval()
        try expect(state.workspace.scratchpad(project: project) == text && state.workspace.deletedScratchpads.isEmpty,
                   "Undo still restores the exact preceding note after both unsuccessful batch attempts")
        state.requestScratchpadRemoval(stale)
        try expect(state.confirmScratchpadRemoval(), "Prepare recovery-versus-newer-text conflict")
        let conflict = state.workspace.deletedScratchpads.first!
        try state.workspace.setScratchpad(text: "New live note must survive", project: project)
        try expect(!state.canUndoRemoval && !state.restoreScratchpad(conflict)
            && state.workspace.scratchpad(project: project) == "New live note must survive"
            && state.workspace.deletedScratchpads == [conflict],
                   "Shared Undo eligibility and explicit restore agree on preserving newer live text")
        let restarted = WorkspaceStore(root: root)
        try expect(restarted.deletedScratchpads == [conflict] && restarted.scratchpad(project: project) == "New live note must survive",
                   "Restart preserves both newer live content and older recoverable note without merging their text")
        state.workspace.failureInjector = { throw CaptureStoreError.injectedInterruption }
        try expect(!state.permanentlyDeleteScratchpad(conflict) && state.workspace.deletedScratchpads == [conflict],
                   "Failed permanent deletion preserves the receipt for retry")
        state.workspace.failureInjector = nil
        try expect(state.permanentlyDeleteScratchpad(conflict) && state.workspace.deletedScratchpads.isEmpty
            && state.workspace.scratchpad(project: project) == "New live note must survive"
            && store.trashedCaptures.contains { $0.id == copy.id },
                   "Permanent note deletion removes only recovery, leaving newer notes and independent capture trash untouched")
    }

    @MainActor static func main() async throws {
        try modelTests()
        try projectPersistenceTests()
        try await removalReturnPersistenceTests()
        try await scratchpadRemovalFlowTests()
        try await integrationTests()
        print("PASS: \(checks) bounded history, branch, project, draft, search, deletion and navigation safety checks")
    }
}
