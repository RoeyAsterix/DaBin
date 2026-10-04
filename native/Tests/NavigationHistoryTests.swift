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
    @MainActor private static func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard value() else { throw NSError(domain: "NavigationHistoryTests", code: 1,
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
            dateFilter: .lastSevenDays, newestFirst: true, compact: true, selectedIDs: [itemID],
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
            && presentation.compact && presentation.newestFirst && presentation.selectedIDs == [itemID]
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
        draft.title = task.title
        state.back()
        try expect(state.navigationHistory.index == validationIndex - 1,
                   "Correcting validation input immediately restores navigation without saving draft text")
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

    @MainActor static func main() async throws {
        try modelTests()
        try await integrationTests()
        print("PASS: \(checks) bounded history, branch, project, draft, search, deletion and navigation safety checks")
    }
}
