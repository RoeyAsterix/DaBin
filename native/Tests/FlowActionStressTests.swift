import AppKit
import Foundation

/// Semantic stress only: real public action handlers and real disposable local
/// persistence. Native hit targets, gesture routing, rendering and animation are
/// deliberately verified by the separate window/input/render suites.
@MainActor private final class FlowStressNotifications: ReminderNotificationClient {
    var requests: [String: ScheduledReminder] = [:]
    private(set) var permissionRequests = 0
    func authorization() async -> ReminderAuthorization { .allowed }
    func requestAuthorization() async throws -> Bool {
        permissionRequests += 1
        throw NSError(domain: "FlowActionStressTests", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Stress fixtures must never request system permission"])
    }
    func pending() async -> [ScheduledReminder] { Array(requests.values) }
    func add(_ reminder: ScheduledReminder) async throws { requests[reminder.identifier] = reminder }
    func removePending(_ identifiers: [String]) { identifiers.forEach { requests.removeValue(forKey: $0) } }
    func removeDelivered(_ identifiers: [String]) { }
}

@main struct FlowActionStressTests {
    @MainActor private static var checks = 0
    @MainActor private static var actions: [String: Int] = [:]
    @MainActor private static var routes: [String: Int] = [:]
    @MainActor private static var restarts = 0
    private static let seed: UInt64 = 0xDAB1_2026_1005
    private static let navigationCycles = 64
    private static let transactionCycles = 32

    @MainActor private final class Fixture {
        let root: URL
        let suite: String
        let defaults: UserDefaults
        let pasteboard: NSPasteboard
        let store: CaptureStore
        let previews: PreviewService
        let notifications = FlowStressNotifications()
        let reminders: ReminderService
        let auto: AutoCaptureService
        let state: AppState
        init(root: URL) throws {
            self.root = root
            suite = "DaBinFlowStress.\(UUID())"
            defaults = UserDefaults(suiteName: suite)!
            pasteboard = NSPasteboard(name: .init(suite))
            store = try CaptureStore(root: root, repairArchiveOnOpen: false)
            previews = PreviewService(store: store, defaults: defaults)
            reminders = ReminderService(store: store, client: notifications)
            auto = AutoCaptureService(settings: AutoCaptureSettings(defaults: defaults), input: InputService(store: store),
                pasteboardProvider: { fatalError("Stress must not read the system clipboard") },
                sourceApplicationProvider: { nil })
            state = AppState(store: store, previews: previews, reminders: reminders, autoCapture: auto,
                captureClipboard: CaptureClipboardService(pasteboard: pasteboard),
                folderOpener: { _ in fatalError("Stress must not open Finder or external files") })
        }
        func close() {
            auto.shutdown(); state.focusSessions.shutdown(); state.shutdownNotificationPresentation()
            previews.shutdown(); store.cancelArchiveRepair(); pasteboard.releaseGlobally()
            defaults.removePersistentDomain(forName: suite)
        }
        func drainReminders() async {
            // Join the service's real serial queue, including action Tasks that
            // were enqueued on the preceding actor turn. The client is local.
            for _ in 0..<3 { await Task.yield() }
            await reminders.reconcile()
        }
    }

    /// Immutable receipt/content identity must survive every editable action.
    private struct Receipt: Equatable {
        let id: UUID
        let capturedAt: Date
        let day: String
        let timeZone: String
        let offset: Int
        let originalText: String?
        let originalURL: String?
        let originalFilename: String?
        let sourceFilePath: String?
        let sourceURL: String?
        let origin: String
        let automaticActionID: UUID?
        let parentID: UUID?
        @MainActor init(_ capture: Capture) {
            id = capture.id; capturedAt = capture.capturedAt; day = capture.captureDay
            timeZone = capture.captureTimeZoneID; offset = capture.captureUTCOffsetSeconds
            originalText = capture.originalText; originalURL = capture.originalURL
            originalFilename = capture.originalFilename; sourceFilePath = capture.sourceFilePath
            sourceURL = capture.sourceURL; origin = capture.captureOriginRaw
            automaticActionID = capture.automaticActionID; parentID = capture.parentTaskID
        }
    }

    @MainActor private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        guard try condition() else {
            throw NSError(domain: "FlowActionStressTests", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
    @MainActor @discardableResult
    private static func action<T>(_ name: String, _ operation: () throws -> T) rethrows -> T {
        actions[name, default: 0] += 1
        return try operation()
    }
    @MainActor @discardableResult
    private static func asyncAction<T>(_ name: String, _ operation: () async throws -> T) async rethrows -> T {
        actions[name, default: 0] += 1
        return try await operation()
    }
    @MainActor private static func snapshot(_ capture: Capture) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(CaptureSnapshot(capture))
    }
    @MainActor private static func records(_ store: CaptureStore) throws -> [UUID: Data] {
        try Dictionary(uniqueKeysWithValues: (store.captures + store.trashedCaptures).map { ($0.id, try snapshot($0)) })
    }
    @MainActor private static func rejectMetadata(_ fixture: Fixture) {
        fixture.store.failureInjector = { checkpoint in
            if checkpoint == .beforeMetadataSave { throw CaptureStoreError.importVerificationFailed }
        }
    }
    @MainActor private static func visit(_ route: BoardRoute, state: AppState, _ operation: () -> Void) throws {
        action("route.\(route)", operation)
        try expect(state.route == route, "The actual route command reaches \(route)")
        routes[String(describing: route), default: 0] += 1
        try expect(state.navigationHistory.entries.count <= NavigationHistory.maximumEntries
            && state.navigationHistory.entries.indices.contains(state.navigationHistory.index),
            "Every route command leaves bounded history with a valid current index")
    }
    @MainActor private static func presentation(_ expected: NavigationSnapshot, state: AppState) throws {
        try expect(state.route == expected.route && state.libraryProject == expected.project
            && state.workspace.mode == expected.workspace.mode && state.filter == expected.filter,
            "History restores the exact route, project, workspace mode and type filter")
        try expect(state.selectedCapture?.id == expected.selectedCaptureID && state.detailFocus == expected.focus
            && state.workspaceViewport == expected.workspaceViewport,
            "History restores capture identity, section and stable viewport rather than a replacement draft")
        if expected.belongsToSearchSession {
            try expect(state.query == expected.query && state.searchProject == expected.searchProject
                && state.searchScope == expected.searchScope && state.searchColumnViewports == expected.searchColumnViewports,
                "History restores the refined Search session and chronological positions")
        }
        if expected.route == .searchNote {
            try expect(state.selectedSearchNote.map { WorkspaceSnapshot.projectKey($0.projectName) } == expected.selectedNoteProjectKey,
                "The Search note route resolves the exact persisted project note")
        }
    }

    @MainActor private static func navigationStress(_ fixture: Fixture) throws {
        let state = fixture.state, store = fixture.store
        try action("workspace.createProject") { try state.workspace.createProject(name: "Northstar", colorHex: "7568D8") }
        try action("workspace.createProject") { try state.workspace.createProject(name: "Southstar", colorHex: "38A58D") }
        try action("workspace.setScratchpad") { try state.workspace.setScratchpad(text: "Persistent stress project note", project: "Northstar") }
        let note = state.workspace.scratchpads.first { $0.projectName == "Northstar" }!
        let task = try action("store.createTask") { try store.createTask(text: "Navigation stress task", projectName: "Northstar") }
        let child = try action("store.captureAttachment") { try store.capture(text: "Independent navigation attachment", parentTask: task)[0] }
        let receiptBytes = try records(store)
        action("openLibrary") { state.openLibrary() }
        action("navigateProject") { state.navigateProject("Northstar") }
        action("openNewNote") { state.openNewNote() }
        state.newNoteText = "Pending note survives all routes — 雪"
        action("back") { state.back() }
        action("openNewTask") { state.openNewTask() }
        state.newTaskDraft.text = "Pending new task survives all routes"
        state.newTaskDraft.pendingChecklistText = "Pending new-task step"
        action("back") { state.back() }
        action("openCapture") { state.openCapture(task.id, focus: "task") }
        let draft = state.selectedDraft!
        draft.title = "Pending existing-task title"
        draft.planning.priority = .high
        draft.pendingChecklistText = "Pending existing-task step"
        draft.commentComposer = "Pending reply survives all routes"
        action("back") { state.back() }

        for cycle in 0..<navigationCycles {
            try visit(.library, state: state) { state.openLibrary() }
            let project = cycle.isMultiple(of: 2) ? "Northstar" : "Southstar"
            action("navigateProject") { state.navigateProject(project) }
            for mode in WorkspaceMode.allCases {
                let before = state.navigationHistory.current!
                action("navigateWorkspaceMode") { state.navigateWorkspaceMode(mode) }
                try expect(state.workspace.mode == mode && state.libraryProject == project,
                    "Cycle\(cycle): changing workspace mode preserves the selected project")
                if before.workspace.mode != mode {
                    let destination = state.navigationHistory.current!
                    action("back") { state.back() }; try presentation(before, state: state)
                    action("forward") { state.forward() }; try presentation(destination, state: state)
                }
            }
            let anchor = ProjectWorkspaceIdentity.capture(task.id)
            state.workspaceViewport = NavigationViewportAnchor(itemID: anchor, offset: Double(cycle % 19),
                neighbors: [ProjectWorkspaceIdentity.capture(child.id)])
            try visit(.detail, state: state) { state.openCapture(task.id, focus: "comment") }
            action("openCapture.attachment") { state.openCapture(child.id) }
            action("back") { state.back() }
            try expect(state.selectedCapture === task && state.selectedDraft === draft,
                "Cycle\(cycle): attachment Back restores the exact pending task owner")
            action("back") { state.back() }
            try expect(state.route == .library && state.workspaceViewport?.itemID == anchor
                && state.workspaceViewport?.offset == Double(cycle % 19),
                "Cycle\(cycle): Detail Back restores its actual project viewport")
            try visit(.inbox, state: state) { state.openInbox() }
            try visit(.daily, state: state) { state.openDaily() }
            action("moveDay") { state.moveDay(-(cycle % 6)) }
            try visit(.weekly, state: state) { state.openWeekly() }
            try visit(.reminders, state: state) { state.showReminders() }
            try visit(.search, state: state) { state.openSearch() }
            state.query = "stress \(cycle % 7)"
            action("selectSearchProject") { state.selectSearchProject("Northstar") }
            state.searchColumnViewports[task.captureDay] = NavigationViewportAnchor(itemID: anchor, offset: Double(cycle))
            try visit(.searchNote, state: state) { state.openSearchNote(note) }
            action("back") { state.back() }
            try expect(state.route == .search && state.query == "stress \(cycle % 7)"
                && state.searchProject == "Northstar" && state.searchColumnViewports[task.captureDay]?.offset == Double(cycle),
                "Cycle\(cycle): editable note Back preserves the same Search refinement and viewport")
            try visit(.detail, state: state) { state.openCapture(task.id, focus: "task") }
            try visit(.settings, state: state) { state.showSettings() }
            try visit(.newTask, state: state) { state.openNewTask() }
            try visit(.newNote, state: state) { state.openNewNote() }
            try visit(.trash, state: state) { state.showTrash() }
            try visit(.inbox, state: state) { state.openInbox() }
            let previous = state.navigationHistory.entries[state.navigationHistory.index - 1]
            let end = state.navigationHistory.current!
            action("back") { state.back() }; try presentation(previous, state: state)
            action("forward") { state.forward() }; try presentation(end, state: state)
            action("back") { state.back() }
            try visit(.settings, state: state) { state.showSettings() }
            try expect(!state.canGoForward, "Cycle\(cycle): deliberate new navigation cuts the old Forward branch")
            try expect(draft.title == "Pending existing-task title" && draft.pendingChecklistText == "Pending existing-task step"
                && draft.commentComposer == "Pending reply survives all routes" && draft.planning.priority == .high,
                "Cycle\(cycle): navigation never saves, resets or transfers the pending existing-task draft")
            try expect(state.newNoteText == "Pending note survives all routes — 雪" && state.newNoteProject == "Northstar"
                && state.newTaskDraft.text == "Pending new task survives all routes"
                && state.newTaskDraft.pendingChecklistText == "Pending new-task step" && state.newTaskProject == "Northstar",
                "Cycle\(cycle): both pending composers retain exact text, checklist and original destination")
            if cycle % 8 == 7 {
                let entries = state.navigationHistory.entries
                for expected in entries.dropLast().reversed() {
                    action("back") { state.back() }; try presentation(expected, state: state)
                }
                let rootIndex = state.navigationHistory.index
                for _ in 0..<5 { action("back.boundary") { state.back() } }
                try expect(rootIndex == 0 && state.navigationHistory.index == 0 && !state.canGoBack,
                    "Repeated Back at the bounded history root never invents another route")
                for expected in entries.dropFirst() {
                    action("forward") { state.forward() }; try presentation(expected, state: state)
                }
                let endIndex = state.navigationHistory.index
                for _ in 0..<5 { action("forward.boundary") { state.forward() } }
                try expect(state.navigationHistory.index == endIndex && !state.canGoForward,
                    "Repeated Forward at the history end is idempotent")
                state.persistDrafts()
                let reopened = try Fixture(root: fixture.root); restarts += 1
                defer { reopened.close() }
                action("restart.openCapture") { reopened.state.openCapture(task.id) }
                let restored = reopened.state.selectedDraft!
                try expect(restored.title == draft.title && restored.planning == draft.planning
                    && restored.pendingChecklistText == draft.pendingChecklistText && restored.commentComposer == draft.commentComposer,
                    "Actual AppState restart recovers the task draft after repeated history churn")
                try expect(reopened.state.newNoteText == state.newNoteText && reopened.state.newNoteProject == "Northstar"
                    && reopened.state.newTaskDraft.text == state.newTaskDraft.text
                    && reopened.state.newTaskDraft.pendingChecklistText == state.newTaskDraft.pendingChecklistText,
                    "Actual restart recovers both separate composer owners and their destination")
            }
        }
        try expect(try records(store) == receiptBytes, "All navigation/history stress leaves every committed record byte-for-byte unchanged")
        try expect(Set(routes.keys) == Set(["inbox", "daily", "weekly", "library", "search", "searchNote", "detail",
            "reminders", "settings", "newTask", "newNote", "trash"]), "The route workload actually visited all12 production routes")
        try expect(state.navigationHistory.entries.count == NavigationHistory.maximumEntries,
            "Long repeated navigation exercises the real100-entry history bound")
    }

    @MainActor private static func transactionStress(_ fixture: Fixture) async throws {
        let state = fixture.state, store = fixture.store
        try action("workspace.createProject") { try state.workspace.createProject(name: "Northstar", colorHex: "7568D8") }
        try action("workspace.createProject") { try state.workspace.createProject(name: "Southstar", colorHex: "38A58D") }
        let payload = Data(("Owned stress original\n" + String(repeating: "abc123", count: 64)).utf8)
        let file = try await asyncAction("store.importData") { try await store.importData(payload, filename: "Stress-original.bin") }
        let fileReceipt = Receipt(file)
        var receipts: [UUID: Receipt] = [file.id: fileReceipt]
        var selector = seed
        for cycle in 0..<transactionCycles {
            selector = selector &* 6_364_136_223_846_793_005 &+ 1
            let project = selector & 1 == 0 ? "Northstar" : "Southstar"
            action("openLibrary") { state.openLibrary() }
            action("navigateProject") { state.navigateProject(project) }
            action("openNewNote") { state.openNewNote() }
            let noteText = "Stress note\(cycle) — whitespace\n    indentation 雪"
            state.newNoteText = noteText
            let countBeforeNote = store.captures.count
            rejectMetadata(fixture)
            action("saveNewNote.failed") { state.saveNewNote() }
            try expect(state.route == .newNote && state.newNoteText == noteText && state.newNoteProject == project
                && store.captures.count == countBeforeNote && state.status?.severity == .error,
                "Cycle\(cycle): failed note save retains exact draft, destination and committed record count")
            store.failureInjector = nil
            action("saveNewNote.retry") { state.saveNewNote() }
            let note = store.captures.first { $0.originalText == noteText }!
            receipts[note.id] = Receipt(note)
            try expect(state.route == .library && state.newNoteText.isEmpty && note.projectName == project
                && store.captures.count == countBeforeNote + 1, "Cycle\(cycle): note retry commits exactly one record to the original destination")
            action("saveNewNote.empty") { state.saveNewNote() }
            try expect(store.captures.count == countBeforeNote + 1, "Repeated empty note Save cannot duplicate a committed note")

            action("openNewTask") { state.openNewTask() }
            let taskText = "Stress task\(cycle)"
            let typedStep = "Typed next step\(cycle)"
            state.newTaskDraft.text = taskText
            state.newTaskDraft.planning.priority = TaskPriority.allCases[Int((selector >> 8) % UInt64(TaskPriority.allCases.count))]
            state.newTaskDraft.planning.checklist = [TaskChecklistItem(text: "Existing first step\(cycle)")]
            state.newTaskDraft.pendingChecklistText = String(repeating: "x", count: 501)
            let countBeforeTask = store.captures.count
            action("saveNewTask.invalidChecklist") { state.saveNewTask() }
            try expect(state.newTaskDraft.hasUnresolvedValidation && state.newTaskDraft.pendingChecklistText.count == 501
                && store.captures.count == countBeforeTask, "Oversized pending checklist text is retained without a partial task")
            action("showSettings.blocked") { state.showSettings() }
            try expect(state.route == .newTask, "Actual invalid task input blocks unrelated navigation")
            state.newTaskDraft.pendingChecklistText = typedStep
            state.newTaskDraft.reminderEnabled = true
            state.newTaskDraft.reminderDate = Date().addingTimeInterval(-60)
            action("saveNewTask.pastReminder") { state.saveNewTask() }
            try expect(state.newTaskDraft.hasUnresolvedValidation && store.captures.count == countBeforeTask
                && state.newTaskDraft.pendingChecklistText == typedStep, "Past reminder rejection cannot consume a valid pending step")
            state.newTaskDraft.reminderEnabled = false
            rejectMetadata(fixture)
            action("saveNewTask.failed") { state.saveNewTask() }
            try expect(state.route == .newTask && state.newTaskDraft.text == taskText
                && state.newTaskDraft.pendingChecklistText == typedStep && state.newTaskDraft.planning.checklist.count == 1
                && store.captures.count == countBeforeTask, "Failed task storage leaves the candidate step only in its draft owner")
            store.failureInjector = nil
            action("saveNewTask.retry") { state.saveNewTask() }
            let task = store.captures.first { $0.originalText == taskText }!
            receipts[task.id] = Receipt(task)
            try expect(state.route == .library && task.projectName == project && task.taskPlanning?.checklist.map(\.text)
                == ["Existing first step\(cycle)", typedStep] && state.newTaskDraft.pendingChecklistText.isEmpty
                && store.captures.count == countBeforeTask + 1, "Task retry commits its pending checklist exactly once and clears only its own composer")
            let child = try action("store.captureAttachment") { try store.capture(text: "Independent attachment\(cycle)", parentTask: task)[0] }
            receipts[child.id] = Receipt(child)
            action("openCapture") { state.openCapture(task.id, focus: "task") }
            let draft = state.selectedDraft!
            draft.title = "Edited stress task\(cycle)"
            draft.planning.priority = .high
            draft.pendingChecklistText = "Detail pending step\(cycle)"
            draft.commentComposer = "Reply\(cycle)"
            let beforeComment = try snapshot(task)
            rejectMetadata(fixture)
            try expect(!action("postDetailComment.failed", { state.postDetailComment(task, draft: draft) })
                && draft.commentComposer == "Reply\(cycle)" && draft.hasError,
                "Failed comment posting retains the exact composer and reports feedback")
            try expect(try snapshot(task) == beforeComment, "Failed comment write restores the complete committed record")
            store.failureInjector = nil
            try expect(action("postDetailComment.retry", { state.postDetailComment(task, draft: draft) }) && task.commentCount == 1,
                "Comment retry appends one reply through the actual posting action")
            let comment = task.commentThread[0]
            draft.editingCommentID = comment.id; draft.commentComposer = "Edited reply\(cycle)"
            try expect(action("postDetailComment.edit", { state.postDetailComment(task, draft: draft) })
                && task.commentCount == 1 && task.commentThread[0].id == comment.id
                && task.commentThread[0].createdAt == comment.createdAt && task.commentThread[0].text == "Edited reply\(cycle)",
                "Editing a reply preserves its identity/date and never appends a duplicate")
            try expect(!action("postDetailComment.empty", { state.postDetailComment(task, draft: draft) }) && task.commentCount == 1,
                "Repeated empty Post cannot duplicate the edited reply")

            draft.reminderEnabled = true; draft.reminderMode = .countdown
            draft.countdownHours = 0; draft.countdownMinutes = 15
            let commitTime = Date(), reminder = try draft.resolvedReminder(at: commitTime)!
            try expect(reminder.timeIntervalSince(commitTime) == 900, "Countdown resolves relative to its explicit commit time")
            try expect(action("setDetailReminder", { state.setDetailReminder(task, date: reminder) }), "Immediate reminder Apply succeeds")
            try expect(draft.title == "Edited stress task\(cycle)" && draft.pendingChecklistText == "Detail pending step\(cycle)"
                && draft.planning.priority == .high && draft.hasChanges && !draft.reminderChanged,
                "Applying a reminder preserves pending title, priority and checklist instead of globally saving them")
            await fixture.drainReminders()
            let scheduled = fixture.notifications.requests[ReminderService.identifier(task.id)]
            try expect(scheduled?.date == task.reminderAt && scheduled?.revision == task.reminderRevision,
                "The fake notification queue represents the latest actually committed reminder revision")
            let beforeDetail = try snapshot(task)
            rejectMetadata(fixture)
            action("saveDetail.failed") { state.saveDetail() }
            try expect(draft.hasError && draft.pendingChecklistText == "Detail pending step\(cycle)"
                && draft.planning.checklist.count == 2, "Failed global Save retains the unsubmitted step outside the committed plan")
            try expect(try snapshot(task) == beforeDetail, "Failed global Save rolls back the entire committed task and reminder")
            store.failureInjector = nil
            draft.reminderMode = .date; draft.reminderDate = Date().addingTimeInterval(-60)
            action("saveDetail.pastReminder") { state.saveDetail() }
            try expect(draft.validationIssue == .reminder && draft.hasUnresolvedValidation
                && draft.pendingChecklistText == "Detail pending step\(cycle)", "Past reminder rejection retains every unrelated pending field")
            try expect(try snapshot(task) == beforeDetail, "Past reminder validation happens before any metadata mutation")
            draft.reminderDate = reminder
            action("saveDetail.retry") { state.saveDetail() }
            let stepIDs = task.taskPlanning!.checklist.map(\.id)
            try expect(task.title == "Edited stress task\(cycle)" && task.taskPlanning?.checklist.count == 3
                && task.taskPlanning?.checklist.last?.text == "Detail pending step\(cycle)"
                && draft.pendingChecklistText.isEmpty && !draft.hasChanges && !draft.hasError,
                "A valid retry commits all task edits and the pending step exactly once")
            action("saveDetail.repeat") { state.saveDetail() }
            try expect(task.taskPlanning?.checklist.map(\.id) == stepIDs, "Repeated Save preserves checklist identities and cannot append the consumed pending step again")

            draft.pendingChecklistText = "Keep through immediate timing\(cycle)"
            draft.commentComposer = "Keep through immediate timing reply\(cycle)"
            let timingStart = Date().addingTimeInterval(60)
            try expect(action("configureTaskFocus", { state.configureTaskFocus(task, hours: 0, minutes: 25, at: timingStart) }), "Focus duration config commits")
            try expect(action("toggleTaskFocus.start", { state.toggleTaskFocus(task, at: timingStart) })
                && task.taskPlanning?.focusSession?.isRunning == true, "Focus Play starts its saved session")
            try expect(action("toggleTaskFocus.pause", { state.toggleTaskFocus(task, at: timingStart.addingTimeInterval(17)) })
                && task.taskPlanning?.focusSession?.isRunning == false, "Focus Pause retains a paused session")
            try expect(action("resetTaskFocus", { state.resetTaskFocus(task) })
                && task.taskPlanning?.focusSession?.remainingSeconds == 1_500, "Focus Reset restores the configured duration")
            let planned = CaptureCalendar.dayString(Date().addingTimeInterval(86_400))
            try expect(action("scheduleTask", { state.scheduleTask(task, day: planned, time: "09:30") })
                && task.taskPlanning?.plannedDay == planned && task.taskPlanning?.plannedTime == "09:30", "Immediate scheduling commits its work date/time")
            try expect(draft.pendingChecklistText == "Keep through immediate timing\(cycle)"
                && draft.commentComposer == "Keep through immediate timing reply\(cycle)", "Focus and scheduling never consume other pending draft fields")
            let beforeCompletion = try snapshot(task)
            rejectMetadata(fixture)
            action("toggleTaskCompletion.failed") { state.toggleTaskCompletion(task) }
            try expect(!task.isCompleted && snapshot(task) == beforeCompletion, "Failed completion rolls back lifecycle, reminder revision and plan")
            store.failureInjector = nil
            action("toggleTaskCompletion.complete") { state.toggleTaskCompletion(task) }
            await fixture.drainReminders()
            try expect(task.isCompleted && fixture.notifications.requests[ReminderService.identifier(task.id)] == nil
                && draft.pendingChecklistText == "Keep through immediate timing\(cycle)", "Completion clears its notification and preserves unfinished checklist text")
            action("toggleTaskCompletion.reopen") { state.toggleTaskCompletion(task) }
            action("completeFollowUp.task") { state.completeFollowUp(task) }
            try expect(task.isCompleted, "Task follow-up Complete uses task lifecycle rather than merely deleting its reminder")
            action("toggleTaskCompletion.reopen") { state.toggleTaskCompletion(task) }

            let convertible = try action("store.capture") { try store.capture(text: "Convertible stress capture\(cycle)")[0] }
            receipts[convertible.id] = Receipt(convertible)
            let beforeConversion = try snapshot(convertible)
            rejectMetadata(fixture)
            action("convertToTask.failed") { state.convertToTask(convertible) }
            try expect(!convertible.isTask && snapshot(convertible) == beforeConversion, "Failed conversion preserves the ordinary capture completely")
            store.failureInjector = nil
            action("openCapture.convertible") { state.openCapture(convertible.id) }
            action("convertToTask") { state.convertToTask(convertible) }
            action("convertToTask.repeat") { state.convertToTask(convertible) }
            let conversionDraft = state.selectedDraft!
            try expect(convertible.isTask && state.canUndoTaskConversion && Receipt(convertible) == receipts[convertible.id],
                "Repeated conversion preserves one original identity and a valid clean Undo")
            conversionDraft.pendingChecklistText = "Protect conversion draft\(cycle)"
            action("undoTaskConversion.blocked") { state.undoTaskConversion() }
            try expect(convertible.isTask && !state.canUndoTaskConversion
                && conversionDraft.pendingChecklistText == "Protect conversion draft\(cycle)", "Conversion Undo cannot discard pending task work")
            conversionDraft.pendingChecklistText = ""
            action("undoTaskConversion") { state.undoTaskConversion() }
            try expect(!convertible.isTask && Receipt(convertible) == receipts[convertible.id], "Clean Undo returns the same immutable capture")

            action("openLibrary") { state.openLibrary() }
            let beforePin = try snapshot(file)
            rejectMetadata(fixture)
            action("togglePinned.failed") { state.togglePinned(file) }
            try expect(try snapshot(file) == beforePin && state.status?.severity == .error, "Failed organization action restores all committed file metadata")
            store.failureInjector = nil
            action("togglePinned") { state.togglePinned(file) }; action("togglePinned") { state.togglePinned(file) }
            action("toggleMinimized") { state.toggleMinimized(file) }; action("toggleMinimized") { state.toggleMinimized(file) }
            try action("workspace.markInboxProcessed") { try state.workspace.markInboxProcessed([file.id]) }
            action("assignProject.filed") { state.assignProject(file, name: project) }
            try expect(!state.canReturnCaptureToInbox(file), "Filed originals cannot promise a return to visible Inbox")
            action("assignProject.unfiled") { state.assignProject(file, name: nil) }
            try expect(state.canReturnCaptureToInbox(file), "An unfiled kept original exposes its conditional return action")
            state.filter = .links
            let workspaceBefore = state.workspace.snapshot
            state.workspace.failureInjector = { throw CocoaError(.fileWriteNoPermission) }
            try expect(!action("returnCaptureToInbox.failed", { state.returnCaptureToInbox(file) })
                && state.route == .library && state.filter == .links && state.workspace.snapshot == workspaceBefore,
                "Failed Inbox return preserves workspace, filter and originating route atomically")
            let failedRestart = WorkspaceStore(root: fixture.root); restarts += 1
            try expect(failedRestart.processedInboxIDs.contains(file.id), "Restart after a failed return still treats the original as kept")
            state.workspace.failureInjector = nil
            try expect(action("returnCaptureToInbox", { state.returnCaptureToInbox(file) })
                && state.route == .inbox && state.filter == .all && !state.workspace.processedInboxIDs.contains(file.id),
                "Successful return opens a visible Inbox and clears only its processed bit")
            let returnIndex = state.navigationHistory.index
            try expect(!action("returnCaptureToInbox.repeat", { state.returnCaptureToInbox(file) })
                && state.navigationHistory.index == returnIndex, "Already-visible Inbox returns cannot repeat a transition")
            try action("workspace.setOnShelf") { try state.workspace.setOnShelf([file.id, file.id], included: true) }
            try expect(state.workspace.shelfCaptureIDs == [file.id], "Repeated collection inclusion has one identity")
            try action("workspace.setSnippetName") { try state.workspace.setSnippetName("Stress snippet\(cycle)", for: file.id) }
            try action("workspace.setScratchpad") { try state.workspace.setScratchpad(text: "Committed project note\(cycle)", project: project) }
            let projectNote = state.workspace.scratchpads.first { $0.projectName == project }!
            try expect(action("copyCapturesToClipboard", { state.copyCapturesToClipboard([task]) })
                && fixture.pasteboard.string(forType: .string) == taskText, "Copy writes the task's original content only to the private fixture pasteboard")
            try expect(action("copySearchNote", { state.copySearchNote(projectNote) })
                && fixture.pasteboard.string(forType: .string) == "Committed project note\(cycle)", "Note Copy uses the currently committed project scratchpad")
            state.workspace.failureInjector = { throw CocoaError(.fileWriteNoPermission) }
            let pendingNote = "Retained failed scratchpad\(cycle)"
            var rejected = false
            do { try action("workspace.setScratchpad.failed") { try state.workspace.setScratchpad(text: pendingNote, project: project) } }
            catch { rejected = true }
            try expect(rejected && state.workspace.scratchpad(project: project) == pendingNote && state.workspace.hasUnsavedChanges,
                "Failed project-note persistence keeps recoverable pending text in its proper owner")
            state.workspace.failureInjector = nil
            try action("workspace.setScratchpad.retry") { try state.workspace.setScratchpad(text: pendingNote, project: project) }
            try action("workspace.setOnShelf.remove") { try state.workspace.setOnShelf([file.id], included: false) }
            try expect(!state.workspace.shelfCaptureIDs.contains(file.id) && store.captures.contains { $0 === file },
                "Removing a collection reference cannot remove its archived original")
            try expect(Receipt(file) == fileReceipt && Data(contentsOf: store.managedURL(for: file)!) == payload,
                "Organization, collection, copying and Inbox triage preserve the original receipt and owned bytes")

            action("openCapture.removal") { state.openCapture(convertible.id) }
            await asyncAction("removeCapture") { await state.removeCapture(convertible) }
            try expect(!store.captures.contains { $0.id == convertible.id } && state.selectedCapture?.id != convertible.id
                && state.route != .detail, "Soft removal prunes the displayed capture instead of leaving an unreachable Detail")
            let removed = store.trashedCaptures.first { $0.id == convertible.id }!
            try expect(Receipt(removed) == receipts[convertible.id], "Recently Deleted keeps the original identity and receipt")
            action("showTrash") { state.showTrash() }
            await asyncAction("restoreCapture") { await state.restoreCapture(removed) }
            let restored = store.captures.first { $0.id == convertible.id }!
            try expect(restored.deletedAt == nil && Receipt(restored) == receipts[convertible.id], "Restore returns the same capture to its original receipt")
            state.persistDrafts()
            await fixture.drainReminders()
            let committed = try records(store), workspace = state.workspace.snapshot
            let reopened = try Fixture(root: fixture.root); restarts += 1
            defer { reopened.close() }
            try expect(try records(reopened.store) == committed && reopened.state.workspace.snapshot == workspace,
                "Cycle\(cycle): clean reopen recovers every committed capture and workspace value exactly")
            for capture in reopened.store.captures {
                try expect(Receipt(capture) == receipts[capture.id], "Cycle\(cycle): restart retains each original content/receipt identity")
            }
            action("restart.openCapture") { reopened.state.openCapture(task.id) }
            let recoveredDraft = reopened.state.selectedDraft!
            try expect(recoveredDraft.pendingChecklistText == "Keep through immediate timing\(cycle)"
                && recoveredDraft.commentComposer == "Keep through immediate timing reply\(cycle)"
                && recoveredDraft.planning == task.taskPlanning && recoveredDraft.reminder == task.reminderAt,
                "Cycle\(cycle): restart keeps unfinished editors while adopting committed lifecycle, schedule and reminder revisions")
            try expect(reopened.notifications.permissionRequests == 0, "Restart uses no real or fake permission prompt")
        }
        await fixture.drainReminders()
        try expect(store.trashedCaptures.isEmpty && store.captures.count == 1 + transactionCycles * 4,
            "All repeated save/conversion/remove/restore cycles have their exact expected final record count")
        try expect(fixture.notifications.permissionRequests == 0, "All reminder scheduling remained within the injected client without permission requests")
    }

    @MainActor static func main() async throws {
        let started = ProcessInfo.processInfo.systemUptime
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinFlowActionStress-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let navigation = try Fixture(root: root.appendingPathComponent("Navigation"))
        defer { navigation.close() }
        try navigationStress(navigation)
        let transactions = try Fixture(root: root.appendingPathComponent("Transactions"))
        defer { transactions.close() }
        try await transactionStress(transactions)
        try expect(navigation.notifications.permissionRequests == 0 && transactions.notifications.permissionRequests == 0,
            "Semantic stress never requests notification permission")
        let seconds = ProcessInfo.processInfo.systemUptime - started
        let operationTotal = actions.values.reduce(0, +)
        let ledger = actions.keys.sorted().map { "\($0)=\(actions[$0]!)" }.joined(separator: ", ")
        print("SEED: \(String(seed, radix: 16)); navigationCycles=\(navigationCycles); transactionalCycles=\(transactionCycles); actualHandlerInvocations=\(operationTotal); restartChecks=\(restarts); seconds=\(String(format: "%.3f", seconds))")
        print("ACTION_COUNTS: \(ledger)")
        print("ROUTE_COUNTS: \(routes.keys.sorted().map { "\($0)=\(routes[$0]!)" }.joined(separator: ", "))")
        print("PASS: \(checks) flow/action stress checks; all12 routes, bounded branch/history churn, pending draft ownership, atomic failed-save retries, comments/checklists, timing/lifecycle, private copying, Inbox/organization, removal/restore and repeated local restart. Semantic handlers only; native activation, system dialogs, rendering and animation are separate coverage.")
    }
}
