import AppKit
import Combine
import Foundation

enum BoardRoute: Equatable {
    case inbox, daily, weekly, library, search, searchNote, detail, reminders, settings, newTask, newNote, trash
}

enum BoardTimelineMode: Hashable {
    case daily, weekly
}

enum WeeklyExpansionDirection: Equatable { case left, right }

struct AppStatusMessage: Equatable {
    enum Severity { case success, warning, error }
    let text: String
    let severity: Severity
    let reminderCaptureID: UUID?

    init(text: String, severity: Severity, reminderCaptureID: UUID? = nil) {
        self.text = text
        self.severity = severity
        self.reminderCaptureID = reminderCaptureID
    }

    var symbol: String {
        switch severity {
        case .success: return "checkmark.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "exclamationmark.circle"
        }
    }
}

private struct SearchCacheKey: Equatable {
    let query: String
    let filter: CaptureFilter
    let scope: CaptureSearchScope
    let context: Bool
    let project: String?
    let unfiledOnly: Bool
    let source: String?
    let timeZoneIdentifier: String
    let revision: UInt
}

/// A typed next step is part of its owner's draft until an explicit Add or
/// successful primary save. Build a candidate so failed writes cannot eat it.
enum ChecklistDraftPolicy {
    static func isValid(_ text: String, planning: TaskPlanning) -> Bool {
        let step = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return step.isEmpty || (step.count <= 500 && planning.checklist.count < 100)
    }
    static func committing(_ text: String, to planning: TaskPlanning) throws -> TaskPlanning {
        let step = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !step.isEmpty else { return planning }
        guard step.count <= 500 else {
            throw NSError(domain: "ChecklistDraft", code: 1, userInfo: [NSLocalizedDescriptionKey: "Keep the new step within 500 characters."])
        }
        guard planning.checklist.count < 100 else {
            throw NSError(domain: "ChecklistDraft", code: 2, userInfo: [NSLocalizedDescriptionKey: "This checklist has 100 steps. Remove a step before adding another."])
        }
        var committed = planning
        committed.checklist.append(TaskChecklistItem(text: step))
        return committed
    }
}

@MainActor
final class NewTaskDraft: ObservableObject {
    @Published var text = ""
    @Published var planning = TaskPlanning()
    @Published var pendingChecklistText = ""
    @Published var reminderEnabled = false
    @Published var reminderMode: ReminderScheduleMode = .date
    @Published var countdownHours = 0
    @Published var countdownMinutes = 30
    @Published var reminderDate = Date().addingTimeInterval(3600)
    @Published var message: String?
    @Published var destination: ComposerDestination?
    @Published var validationFailed = false

    var hasUnresolvedValidation: Bool {
        guard validationFailed else { return false }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !planning.isValid
            || !ChecklistDraftPolicy.isValid(pendingChecklistText, planning: planning) { return true }
        if reminderEnabled {
            return (try? ReminderSchedule.resolve(mode: reminderMode, date: reminderDate,
                hours: countdownHours, minutes: countdownMinutes)) == nil
        }
        return false
    }

    var hasChanges: Bool { !text.isEmpty || !pendingChecklistText.isEmpty || reminderEnabled || planning != TaskPlanning() }

    func reset() {
        text = ""
        planning = TaskPlanning()
        pendingChecklistText = ""
        reminderEnabled = false
        reminderMode = .date
        countdownHours = 0
        countdownMinutes = 30
        reminderDate = Date().addingTimeInterval(3600)
        message = nil
        destination = nil
        validationFailed = false
    }
}

/// Drafts live outside the view hierarchy, so closing the panel never loses an edit.
@MainActor
final class CaptureDraft: ObservableObject {
    @Published var title: String
    private var savedTitle: String
    @Published var comment: String
    @Published var commentComposer = ""
    @Published var editingCommentID: UUID?
    @Published var reminderEnabled: Bool
    @Published var reminderMode: ReminderScheduleMode = .date
    @Published var countdownHours = 0
    @Published var countdownMinutes = 30
    @Published var reminderDate: Date
    @Published var message: String? {
        didSet { feedback.present(message) }
    }
    @Published var hasError = false
    enum ValidationIssue { case title, planning, reminder }
    @Published var validationIssue: ValidationIssue?
    var hasUnresolvedValidation: Bool {
        switch validationIssue {
        case .title:
            let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty || name.count > 2_000
        case .planning: return !planning.isValid || !ChecklistDraftPolicy.isValid(pendingChecklistText, planning: planning)
        case .reminder:
            guard reminderChanged else { return false }
            do { _ = try resolvedReminder(); return false } catch { return true }
        case nil: return false
        }
    }
    let feedback = TransientMessagePresentation<String>()
    private var feedbackSubscription: AnyCancellable?
    @Published var planning: TaskPlanning
    @Published var pendingChecklistText = ""
    private var savedPlanning: TaskPlanning
    private var savedComment: String
    private var savedReminder: Date?
    private(set) var committedReminderRevisionForRecovery: Int

    init(capture: Capture) {
        title = capture.title; savedTitle = capture.title
        planning = capture.taskPlanning ?? TaskPlanning()
        savedPlanning = capture.taskPlanning ?? TaskPlanning()
        comment = capture.comment
        reminderEnabled = capture.reminderAt != nil
        reminderDate = capture.reminderAt ?? Date().addingTimeInterval(3600)
        savedComment = capture.comment
        savedReminder = capture.reminderAt
        committedReminderRevisionForRecovery = capture.reminderRevision
        feedbackSubscription = feedback.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    var visibleMessage: String? { hasError ? message : feedback.visibleMessage }

    var committedPlanningForRecovery: TaskPlanning { savedPlanning }
    var reminder: Date? { reminderEnabled ? reminderDate : nil }
    var hasChanges: Bool { title != savedTitle || comment != savedComment || reminderChanged || planning != savedPlanning || !pendingChecklistText.isEmpty }
    var reminderChanged: Bool { (reminderEnabled && reminderMode == .countdown) || reminder != savedReminder }

    func resolvedReminder(at now: Date = Date()) throws -> Date? {
        guard reminderEnabled else { return nil }
        return try ReminderSchedule.resolve(mode: reminderMode, date: reminderDate,
            hours: countdownHours, minutes: countdownMinutes, now: now)
    }

    func didSave() {
        savedTitle = title
        savedPlanning = planning
        savedComment = comment
        savedReminder = reminder
        message = "Changes saved."
        hasError = false
        validationIssue = nil
    }

    func adoptSavedComments(from capture: Capture) {
        comment = capture.comment
        savedComment = capture.comment
        commentComposer = ""
        editingCommentID = nil
        message = "Comment saved."
        hasError = false
    }

    func adoptSavedPlanning(from capture: Capture) {
        let committed = capture.taskPlanning ?? TaskPlanning()
        if planning == savedPlanning { planning = committed }
        else {
            // Completing from the card owns lifecycle fields only. Keep the
            // user's unfinished deadline/checklist/priority edits in the draft.
            planning.completedAt = committed.completedAt
            planning.previousOccurrenceID = committed.previousOccurrenceID
            planning.nextOccurrenceID = committed.nextOccurrenceID
            planning.focusSession = committed.focusSession
            planning.order = committed.order
        }
        savedPlanning = committed
        committedReminderRevisionForRecovery = capture.reminderRevision
    }

    /// A crash can leave Drafts.json older than a successful immediate action.
    /// Compare its committed baseline with live metadata before recovering edits.
    /// Legacy recovery files omit the baseline and retain their pending work plan.
    func restorePlanning(_ recovered: TaskPlanning, baseline: TaskPlanning?, from capture: Capture) {
        let committed = capture.taskPlanning ?? TaskPlanning()
        planning = recovered
        if let baseline {
            if baseline.plannedDay != committed.plannedDay || baseline.plannedTime != committed.plannedTime {
                planning.plannedDay = committed.plannedDay
                planning.plannedTime = committed.plannedTime
            }
            if baseline.effortMinutes != committed.effortMinutes { planning.effortMinutes = committed.effortMinutes }
        }
        planning.focusSession = committed.focusSession
        planning.order = committed.order
        planning.recurrenceAnchor = committed.recurrenceAnchor
        planning.completedAt = committed.completedAt
        planning.previousOccurrenceID = committed.previousOccurrenceID
        planning.nextOccurrenceID = committed.nextOccurrenceID
        savedPlanning = committed
    }

    /// Immediate timing actions own only their fields. Pending notes, priority,
    /// deadline, repeat and checklist edits remain in this recoverable draft.
    func adoptImmediateTiming(from capture: Capture, schedule: Bool, duration: Bool) {
        let committed = capture.taskPlanning ?? TaskPlanning()
        planning.focusSession = committed.focusSession
        savedPlanning.focusSession = committed.focusSession
        if schedule {
            planning.plannedDay = committed.plannedDay; planning.plannedTime = committed.plannedTime
            planning.order = committed.order; planning.recurrenceAnchor = committed.recurrenceAnchor
            savedPlanning.plannedDay = committed.plannedDay; savedPlanning.plannedTime = committed.plannedTime
            savedPlanning.order = committed.order; savedPlanning.recurrenceAnchor = committed.recurrenceAnchor
        }
        if duration {
            planning.effortMinutes = committed.effortMinutes
            savedPlanning.effortMinutes = committed.effortMinutes
        }
    }

    /// A newer Complete/Snooze action owns the reminder, while an unfinished
    /// comment remains the user's draft until they save or discard it.
    func adoptSavedReminder(from capture: Capture) {
        reminderEnabled = capture.reminderAt != nil
        reminderMode = .date
        if let date = capture.reminderAt { reminderDate = date }
        savedReminder = capture.reminderAt
        committedReminderRevisionForRecovery = capture.reminderRevision
        message = nil
        hasError = false
    }
}

@MainActor
final class AppState: ObservableObject {
    let store: CaptureStore
    let previews: PreviewService
    let contentIndex: ContentIndexService?
    let reminders: ReminderService
    let updates: SoftwareUpdateService
    let robotPlacement: RobotPlacementSettings
    let autoCapture: AutoCaptureService
    let captureClipboard: CaptureClipboardService
    let quickAccessSettings: QuickAccessSettings
    let workspaceZoom: WorkspaceZoomSettings
    let workspace: WorkspaceStore
    lazy var explorerInput: ExplorerCaptureController = {
        let input = ExplorerCaptureController(state: self, input: manualInput)
        input.onResult = { [weak self] captures, project in
            guard let self, self.route == .library, self.workspace.mode == .collection,
                  self.libraryProject == project, let first = captures.first else { return }
            self.workspace.selectedCaptureID = first.id
        }
        input.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        return input
    }()
    let clipboardRetention: ClipboardRetentionService
    let focusSessions: TaskFocusCoordinator
    @Published private(set) var lastConvertedCaptureID: UUID?
    private var lastConversionParentID: UUID?
    private let draftArchive: DraftArchive
    @Published private(set) var draftPersistenceError: String?
    private let manualInput: InputService
    private let folderOpener: (URL) -> Bool
    let newTaskDraft = NewTaskDraft()
    @Published var newNoteText = "" {
        didSet {
            // Replacing all text briefly yields an empty value. Keep the
            // draft's destination until it is saved or explicitly canceled.
            if !newNoteText.isEmpty && newNoteDestination == nil {
                newNoteDestination = ComposerDestination(projectName: composerProjectContext)
            }
        }
    }
    @Published private var newNoteDestination: ComposerDestination?
    var newNoteProject: String? { newNoteDestination?.projectName }
    var newTaskProject: String? { newTaskDraft.destination?.projectName }
    @Published var libraryProject: String? {
        didSet { if workspace.selectedProject != libraryProject { workspace.selectedProject = libraryProject } }
    }
    @Published var todayPlanningScope = "today"
    @Published var workspaceViewport: NavigationViewportAnchor?
    @Published var projectPresentation: [String: ProjectNavigationPresentation] = [:]
    @Published private(set) var navigationHistory = NavigationHistory()
    @Published var navigationWindowInteractionBlocked = false
    @Published var navigationValidationBlocked = false
    @Published private(set) var navigationRestorationRevision: UInt = 0
    private(set) var navigationTransitionRevision: UInt = 0
    var onCaptureNavigationFocus: (() -> String?)?
    var onRestoreNavigationFocus: ((String?) -> Void)?
    private var navigationFocusTarget: String?
    private var navigationDepth = 0
    private var isRestoringNavigation = false
    private var projectRenames: [String: String] = [:]
    @Published var libraryPinnedOnly = false
    @Published var showSearchContext = false {
        didSet { if showSearchContext != oldValue { resetSearchPosition() } }
    }
    @Published var globalSearchFocusRequest = 0
    @Published private(set) var isArchiveOperationRunning = false
    @Published private var isFileImporting = false
    var isImporting: Bool { isFileImporting || manualInput.isBusy || explorerInput.isBusy }
    @Published private var undoRemovalIDs: [UUID] = []
    @Published var route: BoardRoute = .inbox {
        didSet {
            if route != oldValue { captureNavigationRevision &+= 1 }
            if route != .daily && route != .reminders { isDailyDropTargeted = false }
            if route != .weekly { weeklySearchActionsPresented = false }
        }
    }
    @Published var selectedDay = Date() {
        didSet { if selectedDay != oldValue { captureNavigationRevision &+= 1 } }
    }
    @Published var weekEndingDay = Date()
    @Published private(set) var customWeeklyDays: [Date]?
    @Published var weeklyExpansionDirection: WeeklyExpansionDirection = .right
    @Published var filter: CaptureFilter = .all {
        didSet {
            if filter != oldValue {
                captureNavigationRevision &+= 1
                resetSearchPosition()
            }
        }
    }
    @Published var query = "" {
        didSet { if query != oldValue { resetSearchPosition() } }
    }
    @Published var searchProject: String? {
        didSet {
            let changed = searchProject != oldValue || searchUnfiledOnly
            searchUnfiledOnly = false
            if changed { resetSearchPosition() }
        }
    }
    @Published private(set) var searchUnfiledOnly = false
    @Published var searchSource: String? {
        didSet { if searchSource != oldValue { resetSearchPosition() } }
    }
    @Published private(set) var searchScope: CaptureSearchScope = .all {
        didSet { if searchScope != oldValue { resetSearchPosition() } }
    }
    @Published private(set) var searchDay = Date()
    @Published private(set) var searchWeekEndingDay = Date()
    @Published private(set) var searchRangeStartDay = Date()
    @Published private(set) var searchRangeEndDay = Date()
    @Published var weeklySearchActionsPresented = false
    @Published private(set) var autoCaptureSetupRequested = false
    @Published var selectedCapture: Capture?
    @Published var pendingRemoval: Capture?
    @Published private(set) var removingCaptureID: UUID?
    @Published private(set) var captureLayoutRevision: UInt = 0
    @Published var status: AppStatusMessage? {
        didSet {
            if let status {
                notificationSource = .status
                notifications.present(status)
            } else if notificationSource == .status {
                notificationSource = nil
                notifications.dismiss()
            }
        }
    }
    let notifications = TransientMessagePresentation<AppStatusMessage>()
    private enum NotificationSource { case status, storeError }
    private var notificationSource: NotificationSource?
    var notificationMessage: AppStatusMessage? { notifications.visibleMessage }
    @Published var detailFocus: String?
    @Published var selectedDraft: CaptureDraft?
    @Published var dailyScrollID: CaptureFeedCardID?
    @Published var searchScrollID: UUID?
    /// The leftmost date currently presented by the chronological Search board.
    /// It is search-session state, so resizing and result-detail round trips do
    /// not jump back to the newest day.
    @Published var searchDateAnchor: String?
    /// Search result IDs are presentation IDs (for example capture:<UUID> and
    /// note:<project key>) because captures and scratchpads share one board.
    @Published var searchSelectedResultID: String?
    /// Each date column retains its own vertical position while paging or
    /// opening a result. Values use the same presentation IDs as selection.
    @Published var searchColumnScrollIDs: [String: String] = [:]
    @Published var searchColumnViewports: [String: NavigationViewportAnchor] = [:]
    @Published var weeklyColumnViewports: [String: NavigationViewportAnchor] = [:]
    private(set) var searchPositionRevision: UInt = 0
    @Published private(set) var selectedSearchNote: WorkspaceScratchpad?
    @Published private(set) var expandedAutomaticHours: Set<AutomaticHourKey> = []
    @Published var isBoardVisible = false
    @Published private(set) var isTutorialPresented = false
    @Published var isDailyDropTargeted = false
    private(set) var captureNavigationRevision: UInt = 0
    private var attachmentReturnTaskID: UUID?
    var onDismiss: (() -> Void)?
    var onTaskCompleted: (() -> Void)?
    var onTaskTimerExpired: (([Capture]) -> Void)?
    var onToggleExpandedWindow: (() -> Void)?
    var onOpenExtendedCapture: ((Capture, CaptureDraft) -> Void)?
    var onBoardDragStarted: (() -> Void)?
    var onBoardDragEnded: ((CGPoint) -> Void)?
    var onTutorialEscape: (() -> Bool)?
    private var origin: BoardRoute = .daily
    private var searchReturnRoute: BoardRoute = .daily
    private var searchSessionEnded = false
    private var searchReturnFilter: CaptureFilter = .all
    private var searchReturnCreationRoute: BoardRoute = .inbox
    private var searchReturnAuxiliaryRoute: BoardRoute = .inbox
    private var searchReturnCaptureID: UUID?
    private struct SearchDetailContext {
        let captureID: UUID
        let origin: BoardRoute
        let attachmentReturnTaskID: UUID?
        let focus: String?
    }
    private var searchDetailContext: SearchDetailContext?
    private var creationReturnRoute: BoardRoute = .inbox
    private var auxiliaryReturnRoute: BoardRoute = .inbox
    private var drafts: [UUID: CaptureDraft] = [:]
    private var subscriptions = Set<AnyCancellable>()
    private var reminderServiceFeedback: (captureID: UUID, message: String?)?
    @Published private(set) var currentDayKey = CaptureCalendar.dayString(Date())
    private var searchRevision: UInt = 0
    private var searchCacheKey: SearchCacheKey?
    private var searchCache: [SearchGroup] = []
    private var searchDateCacheKey: SearchCacheKey?
    private var searchDateCache: [SearchDateGroup] = []

    init(store: CaptureStore, previews: PreviewService, contentIndex: ContentIndexService? = nil,
         reminders: ReminderService,
         updates: SoftwareUpdateService? = nil, robotPlacement: RobotPlacementSettings? = nil,
         autoCapture: AutoCaptureService? = nil,
         captureClipboard: CaptureClipboardService? = nil,
         quickAccessSettings: QuickAccessSettings? = nil,
         workspaceZoom: WorkspaceZoomSettings? = nil,
         manualInput: InputService? = nil,
         folderOpener: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
        self.store = store
        self.previews = previews
        self.contentIndex = contentIndex
        self.reminders = reminders
        self.updates = updates ?? SoftwareUpdateService()
        self.robotPlacement = robotPlacement ?? RobotPlacementSettings(defaults: nil)
        self.autoCapture = autoCapture ?? AutoCaptureService(
            settings: AutoCaptureSettings(defaults: nil), input: InputService(store: store))
        self.captureClipboard = captureClipboard ?? CaptureClipboardService()
        self.quickAccessSettings = quickAccessSettings ?? QuickAccessSettings(defaults: nil)
        self.workspaceZoom = workspaceZoom ?? WorkspaceZoomSettings(defaults: nil)
        self.workspace = WorkspaceStore(root: store.root)
        self.clipboardRetention = ClipboardRetentionService(store: store, workspace: self.workspace)
        self.focusSessions = TaskFocusCoordinator(store: store)
        self.draftArchive = DraftArchive(root: store.root)
        self.libraryProject = self.workspace.selectedProject
        self.manualInput = manualInput ?? InputService(store: store)
        self.folderOpener = folderOpener
        self.clipboardRetention.onWillTrash = { [weak previews, weak contentIndex] capture in
            await previews?.cancel(for: capture.id)
            await contentIndex?.cancel(for: capture.id)
        }
        focusSessions.onExpired = { [weak self] captures in
            guard let self else { return }
            for capture in captures { self.drafts[capture.id]?.adoptImmediateTiming(from: capture, schedule: false, duration: false) }
            if self.isBoardVisible {
                self.status = AppStatusMessage(text: captures.count == 1 ? "Time’s up. Your task stays open." : "\(captures.count) focus sessions finished. Tasks stay open.", severity: .success)
            }
            self.onTaskTimerExpired?(captures)
        }
        focusSessions.onFailure = { [weak self] message in self?.reportFailure(message) }
        restoreDrafts()
        $newNoteText.dropFirst().debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.persistDrafts() }.store(in: &subscriptions)
        newTaskDraft.objectWillChange.debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.persistDrafts() }.store(in: &subscriptions)
        self.manualInput.onBusy = { [weak self] _ in self?.objectWillChange.send() }
        notifications.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &subscriptions)
        store.$error.sink { [weak self] error in
            guard let self else { return }
            if let error {
                self.notificationSource = .storeError
                self.notifications.present(AppStatusMessage(text: error, severity: .error))
            } else if self.notificationSource == .storeError {
                self.notificationSource = nil
                self.notifications.dismiss()
            }
        }.store(in: &subscriptions)
        store.objectWillChange.sink { [weak self] _ in
            self?.searchRevision &+= 1
            self?.objectWillChange.send()
        }.store(in: &subscriptions)
        workspace.objectWillChange.sink { [weak self] _ in
            self?.searchRevision &+= 1
            self?.objectWillChange.send()
        }.store(in: &subscriptions)
        contentIndex?.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &subscriptions)
        reminders.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &subscriptions)
        self.autoCapture.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &subscriptions)
        self.autoCapture.settings.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &subscriptions)
        newTaskDraft.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &subscriptions)
        self.workspaceZoom.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        self.quickAccessSettings.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &subscriptions)
        // Advance a board left on Today across midnight or sleep without moving
        // a day the user deliberately chose to browse.
        for name in [Notification.Name.NSCalendarDayChanged,
                     NSApplication.didBecomeActiveNotification,
                     Notification.Name.NSSystemTimeZoneDidChange] {
            NotificationCenter.default.publisher(for: name)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.refreshCurrentDay() }
                .store(in: &subscriptions)
        }
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshCurrentDay() }
            .store(in: &subscriptions)
        Task { [weak self] in _ = await self?.clipboardRetention.cleanup() }
    }

    var dayKey: String { CaptureCalendar.dayString(selectedDay) }

    func dismissNotification() { notifications.dismiss() }

    func shutdownNotificationPresentation() {
        notifications.shutdown()
        reminders.shutdownPresentation()
        clipboardRetention.feedback.shutdown()
        for draft in drafts.values { draft.feedback.shutdown() }
    }

    func persistDrafts() {
        var snapshot = DraftArchiveSnapshot()
        snapshot.note = newNoteText
        snapshot.noteDestination = newNoteDestination
        snapshot.task = ComposerSnapshot(text: newTaskDraft.text, planning: newTaskDraft.planning,
            reminderEnabled: newTaskDraft.reminderEnabled, reminderMode: newTaskDraft.reminderMode.rawValue,
            countdownHours: newTaskDraft.countdownHours, countdownMinutes: newTaskDraft.countdownMinutes,
            reminderDate: newTaskDraft.reminderDate,
            destination: newTaskDraft.destination ?? ComposerDestination(projectName: composerProjectContext),
            pendingChecklistText: newTaskDraft.pendingChecklistText)
        snapshot.details = drafts.compactMap { id, draft in
            guard draft.hasChanges || !draft.commentComposer.isEmpty || draft.editingCommentID != nil else { return nil }
            return DetailDraftSnapshot(captureID: id, title: draft.title, comment: draft.comment, planning: draft.planning,
                committedPlanning: draft.committedPlanningForRecovery,
                committedReminderRevision: draft.committedReminderRevisionForRecovery,
                reminderEnabled: draft.reminderEnabled, reminderMode: draft.reminderMode.rawValue,
                countdownHours: draft.countdownHours, countdownMinutes: draft.countdownMinutes, reminderDate: draft.reminderDate,
                commentComposer: draft.commentComposer, editingCommentID: draft.editingCommentID,
                pendingChecklistText: draft.pendingChecklistText)
        }
        do { try draftArchive.save(snapshot); draftPersistenceError = nil }
        catch { draftPersistenceError = "Drafts are still in memory. \(error.localizedDescription)" }
    }

    private func restoreDrafts() {
        guard let snapshot = draftArchive.load() else { draftPersistenceError = draftArchive.recoveryError; return }
        // Older recovery files followed the selected Workspace project. Keep
        // that destination on migration and disclose it in the composer.
        newNoteDestination = snapshot.noteDestination ?? ComposerDestination(projectName: libraryProject)
        newNoteText = snapshot.note
        newTaskDraft.destination = snapshot.task.destination ?? ComposerDestination(projectName: libraryProject)
        newTaskDraft.text = snapshot.task.text
        newTaskDraft.planning = snapshot.task.planning
        newTaskDraft.pendingChecklistText = snapshot.task.pendingChecklistText ?? ""
        newTaskDraft.reminderEnabled = snapshot.task.reminderEnabled
        newTaskDraft.reminderMode = ReminderScheduleMode(rawValue: snapshot.task.reminderMode) ?? .date
        newTaskDraft.countdownHours = snapshot.task.countdownHours
        newTaskDraft.countdownMinutes = snapshot.task.countdownMinutes
        newTaskDraft.reminderDate = snapshot.task.reminderDate
        for saved in snapshot.details {
            guard let capture = store.captures.first(where: { $0.id == saved.captureID }) else { continue }
            let draft = CaptureDraft(capture: capture)
            draft.title = saved.title ?? capture.title
            draft.comment = saved.comment
            draft.commentComposer = saved.commentComposer ?? ""
            draft.editingCommentID = saved.editingCommentID
            draft.pendingChecklistText = saved.pendingChecklistText ?? ""
            draft.restorePlanning(saved.planning, baseline: saved.committedPlanning, from: capture)
            // Clear and Snooze commit before the debounced draft sidecar. A
            // stale sidecar must not turn that successful action back into an
            // unsaved reminder edit. Legacy drafts retain their pending values.
            if saved.committedReminderRevision == nil || saved.committedReminderRevision == capture.reminderRevision {
                draft.reminderEnabled = saved.reminderEnabled
                draft.reminderMode = ReminderScheduleMode(rawValue: saved.reminderMode) ?? .date
                draft.countdownHours = saved.countdownHours; draft.countdownMinutes = saved.countdownMinutes
                draft.reminderDate = saved.reminderDate
            }
            drafts[saved.captureID] = draft
            observeDraft(draft)
        }
    }

    private func observeDraft(_ draft: CaptureDraft) {
        draft.objectWillChange.sink { [weak self, weak draft] _ in
            guard let self, let draft, let id = self.lastConvertedCaptureID,
                  self.drafts[id] === draft else { return }
            self.objectWillChange.send()
        }.store(in: &subscriptions)
        draft.objectWillChange.debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.persistDrafts() }.store(in: &subscriptions)
    }
    var dailyCaptures: [Capture] { captures(for: selectedDay) }
    var weeklyDays: [Date] {
        customWeeklyDays ?? WeeklyDateSelection.trailingWeek(ending: weekEndingDay)
    }
    var isCustomWeekSelection: Bool { customWeeklyDays != nil }
    /// Keep the chosen calendar dates visible even when a filter or an empty
    /// day has no cards. Week is a stable overview of the complete selection.
    var weeklyVisibleDays: [Date] { weeklyDays }
    var weeklyActiveDays: [Date] { weeklyDays.filter { !allCaptures(for: $0).isEmpty } }

    func allCaptures(for day: Date) -> [Capture] {
        let key = CaptureCalendar.dayString(day)
        return store.captures.filter {
            $0.captureDay == key || isTaskAtTop($0, dayKey: key)
        }.sorted {
            let lhsAtTop = isTaskAtTop($0, dayKey: key), rhsAtTop = isTaskAtTop($1, dayKey: key)
            if lhsAtTop != rhsAtTop { return lhsAtTop }
            return $0.capturedAt == $1.capturedAt ? $0.id.uuidString < $1.id.uuidString : $0.capturedAt > $1.capturedAt
        }
    }
    func captures(for day: Date) -> [Capture] { allCaptures(for: day).filter { filter.includes($0) } }
    var allCapturesForDay: [Capture] { allCaptures(for: selectedDay) }
    func isTaskAtTop(_ capture: Capture) -> Bool {
        isTaskAtTop(capture, on: selectedDay)
    }
    func isTaskAtTop(_ capture: Capture, on day: Date) -> Bool {
        isTaskAtTop(capture, dayKey: CaptureCalendar.dayString(day))
    }
    private func isTaskAtTop(_ capture: Capture, dayKey: String) -> Bool {
        guard capture.isTask, !capture.isCompleted, capture.captureDay <= dayKey else { return false }
        if let reminder = capture.reminderAt {
            // Match the local day shown by the reminder label, including tasks
            // created on that day. A reminder replaces automatic daily carryover.
            return CaptureCalendar.dayString(reminder) == dayKey
        }
        return capture.captureDay < dayKey
    }

    func refreshCurrentDay(at now: Date = Date()) {
        let nextDay = CaptureCalendar.dayString(now)
        guard nextDay != currentDayKey else { return }
        if dayKey == currentDayKey || dayKey > nextDay {
            selectedDay = now
            dailyScrollID = nil
        }
        let weekEnd = CaptureCalendar.dayString(weekEndingDay)
        if customWeeklyDays == nil && (weekEnd == currentDayKey || weekEnd > nextDay) { weekEndingDay = now }
        currentDayKey = nextDay
    }

    /// Results may change without user intent while extraction or capture
    /// indexing finishes. Only a changed query or refinement calls this helper;
    /// store revisions deliberately leave the user's board position intact.
    private func resetSearchPosition() {
        searchPositionRevision &+= 1
        searchDateAnchor = nil
        searchSelectedResultID = nil
        searchColumnScrollIDs.removeAll(keepingCapacity: true)
        searchColumnViewports.removeAll(keepingCapacity: true)
        searchScrollID = nil
    }

    private var currentSearchCacheKey: SearchCacheKey {
        SearchCacheKey(query: query, filter: filter, scope: searchScope, context: showSearchContext,
                       project: searchProject, unfiledOnly: searchUnfiledOnly,
                       source: searchSource, timeZoneIdentifier: TimeZone.current.identifier,
                       revision: searchRevision)
    }

    var searchGroups: [SearchGroup] {
        let key = currentSearchCacheKey
        if searchCacheKey == key { return searchCache }
        let capturesByID = Dictionary(uniqueKeysWithValues: store.captures.map { ($0.id, $0) })
        // A task owns its attachments' project. Resolve against the live parent
        // rather than trusting a child's organization snapshot after a move.
        let effectiveProjects = Dictionary(uniqueKeysWithValues: store.captures.map { capture in
            let parent = capture.parentTaskID.flatMap { capturesByID[$0] }
            let project = parent?.isTask == true ? parent?.projectName : capture.projectName
            return (capture.id, project ?? "")
        })
        let groups = CaptureSearch.groups(captures: store.captures.filter { capture in
            let project = effectiveProjects[capture.id] ?? ""
            return (searchProject == nil || project == searchProject)
                && (!searchUnfiledOnly || project.isEmpty)
                && (searchSource == nil || WorkspaceQuery.sourceName(capture) == searchSource)
        }, query: query, filter: filter,
                             scope: searchScope, includeContext: showSearchContext,
                             includeEmptyQuery: true,
                             additionalText: Dictionary(workspace.snapshot.snippetNames.compactMap {
                                 guard let id = UUID(uuidString: $0.key) else { return nil }; return (id, $0.value)
                             }, uniquingKeysWith: { first, _ in first }),
                             effectiveProjectNames: effectiveProjects)
        searchCacheKey = key
        searchCache = groups
        return groups
    }

    /// Captures and project scratchpads share the chronological Search board.
    /// The model keeps notes on their edited day and captures on their immutable
    /// receipt day while preserving match/context semantics.
    var searchDateGroups: [SearchDateGroup] {
        let captureGroups = searchGroups
        let key = currentSearchCacheKey
        if searchDateCacheKey == key { return searchDateCache }
        let groups = SearchDateBoard.groups(captureGroups: captureGroups, notes: searchScratchpads,
                                            includeContext: showSearchContext)
        searchDateCacheKey = key
        searchDateCache = groups
        return groups
    }

    var searchScratchpads: [WorkspaceScratchpad] {
        let words = CaptureSearch.normalized(query).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard searchSource == nil, filter == .all || filter == .text else { return [] }
        return workspace.scratchpads.filter { note in
            (searchProject == nil || note.projectName == searchProject)
                && (!searchUnfiledOnly || note.projectName == nil)
                && searchScope.includes(captureDay: CaptureCalendar.dayString(note.updatedAt))
                && words.allSatisfy { CaptureSearch.normalized(note.text + " " + (note.projectName ?? "")).contains($0) }
        }
    }
    var searchScopeTitle: String {
        switch searchScope {
        case .all:
            return "All dates"
        case .day(let day):
            return prettyDay(day)
        case .week(let days):
            let ordered = days.sorted()
            guard let first = ordered.first, let last = ordered.last else { return "Selected week" }
            if first == last { return prettyDay(first) }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            if let start = TaskPlanningPolicy.date(for: first, calendar: calendar),
               let end = TaskPlanningPolicy.date(for: last, calendar: calendar),
               calendar.dateComponents([.day], from: start, to: end).day != ordered.count - 1 {
                return "\(ordered.count) selected days"
            }
            return "\(prettyDay(first, includeWeekday: false))–\(prettyDay(last, includeWeekday: false))"
        case .range(let start, let end):
            let first = min(start, end), last = max(start, end)
            if first == last { return prettyDay(first) }
            return "\(prettyDay(first, includeWeekday: false))–\(prettyDay(last, includeWeekday: false))"
        }
    }

    /// The day used by Weekly's day-scoped Search and Export actions. Keep a
    /// preserved in-range selection; after range navigation, fall back to the
    /// visible week end so the action never silently targets an off-screen day.
    var weeklyActionDay: Date {
        let selectedKey = CaptureCalendar.dayString(selectedDay)
        return weeklyDays.first(where: { CaptureCalendar.dayString($0) == selectedKey })
            ?? weeklyDays.last
            ?? weekEndingDay
    }
    var hasUnsavedDrafts: Bool {
        workspace.hasUnsavedChanges || !newNoteText.isEmpty || newTaskDraft.hasChanges || drafts.values.contains(where: \.hasChanges)
    }

    /// Receipt membership is independent of organization, task scheduling and
    /// the filters on other workspaces.
    func receiptCaptures(for day: Date) -> [Capture] {
        receiptCaptures(dayKey: CaptureCalendar.dayString(day))
    }
    private func receiptCaptures(dayKey key: String) -> [Capture] {
        return store.captures.filter { $0.captureDay == key }
            .sorted { $0.capturedAt == $1.capturedAt ? $0.id.uuidString < $1.id.uuidString : $0.capturedAt > $1.capturedAt }
    }
    var currentTodayCaptures: [Capture] { receiptCaptures(dayKey: currentDayKey) }
    static func todayReceiptItemID(_ id: UUID) -> String { "today-receipt:" + id.uuidString }
    var todayTimelineCaptures: [Capture] { receiptCaptures(for: selectedDay).filter { filter.includes($0) } }
    var projectNames: [String] {
        Set(store.captures.compactMap(\.projectName) + workspace.projectNames).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    var libraryCaptures: [Capture] {
        store.captures.filter {
            $0.parentTaskID == nil && (libraryProject == nil || $0.projectName == libraryProject)
                && (!libraryPinnedOnly || $0.isPinned) && filter.includes($0)
        }.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.capturedAt == $1.capturedAt ? $0.id.uuidString < $1.id.uuidString : $0.capturedAt > $1.capturedAt
        }
    }
    var followUpCaptures: [Capture] {
        store.captures.filter { ($0.isTask && !$0.isCompleted) || ($0.reminderAt != nil && !($0.isTask && $0.isCompleted)) }
            .sorted {
                let lhs = $0.reminderAt ?? .distantFuture, rhs = $1.reminderAt ?? .distantFuture
                if lhs != rhs { return lhs < rhs }
                return $0.capturedAt == $1.capturedAt ? $0.id.uuidString < $1.id.uuidString : $0.capturedAt > $1.capturedAt
            }
    }
    var canUndoRemoval: Bool { store.trashedCaptures.contains { undoRemovalIDs.contains($0.id) } }

    func setTutorialPresented(_ presented: Bool) { isTutorialPresented = presented }

    func openLibrary() { navigate(to: .library) }
    func openInbox() { navigate(to: .inbox) }
    func showTrash() {
        guard !isNavigationBlocked else { return }
        beginNavigation(); defer { endNavigation() }
        guard !isTutorialPresented else { return }
        if !returnRouteChain(from: route).contains(where: { $0 == .settings || $0 == .trash }) { auxiliaryReturnRoute = route }
        route = .trash
    }

    func openDaily() {
        guard !isNavigationBlocked else { return }
        beginNavigation(); defer { endNavigation() }
        guard !isTutorialPresented else { return }
        refreshCurrentDay()
        selectedDay = Date()
        filter = .all
        dailyScrollID = nil
        route = .daily
    }

    func openWeekly() {
        guard !isNavigationBlocked else { return }
        beginNavigation(); defer { endNavigation() }
        guard !isTutorialPresented else { return }
        if customWeeklyDays == nil { weekEndingDay = min(selectedDay, Date()) }
        route = .weekly
    }

    var timelineMode: BoardTimelineMode { route == .weekly ? .weekly : .daily }

    /// Inbox owns capture triage and both calendar presentations. Keep the
    /// routes distinct so search, detail return paths and window sizing survive.
    var isInboxRoute: Bool { route == .inbox || route == .daily || route == .weekly }

    func selectTimelineMode(_ mode: BoardTimelineMode) {
        guard !isNavigationBlocked else { return }
        beginNavigation(); defer { endNavigation() }
        guard !isTutorialPresented else { return }
        switch (route, mode) {
        case (.inbox, .weekly), (.daily, .weekly):
            openWeekly()
        case (.inbox, .daily), (.weekly, .daily):
            route = .daily
        default:
            break
        }
    }

    func selectWeeklyDay(_ day: Date) {
        guard !isNavigationBlocked else { return }
        beginNavigation(); defer { endNavigation() }
        guard !isTutorialPresented else { return }
        selectedDay = min(day, Date())
        dailyScrollID = nil
        route = .daily
    }

    func selectWeeklyActionDay(_ day: Date) {
        let key = CaptureCalendar.dayString(day)
        guard let selected = weeklyDays.first(where: { CaptureCalendar.dayString($0) == key }) else { return }
        selectedDay = selected
    }

    func setWeekEndingDay(_ day: Date) {
        guard !isNavigationBlocked else { return }
        beginNavigation(); defer { endNavigation() }
        customWeeklyDays = nil
        weekEndingDay = min(day, Date())
    }

    /// Apply the picker atomically. A rejected empty, oversized or future
    /// selection leaves the existing board and its scroll context untouched.
    @discardableResult
    func setWeeklyDays(_ days: [Date]) -> Bool {
        guard !isNavigationBlocked else { return false }
        beginNavigation(); defer { endNavigation() }
        guard !isTutorialPresented, let selection = WeeklyDateSelection(days: days),
              let last = selection.days.last else { return false }
        customWeeklyDays = selection.days
        weekEndingDay = last
        return true
    }

    func moveWeek(_ amount: Int) {
        guard !isNavigationBlocked else { return }
        beginNavigation(); defer { endNavigation() }
        if let days = customWeeklyDays {
            guard let selection = WeeklyDateSelection(days: days),
                  let shifted = selection.shifted(weeks: amount) else { return }
            customWeeklyDays = shifted.days
            if let last = shifted.days.last { weekEndingDay = last }
            return
        }
        let delta = amount.multipliedReportingOverflow(by: 7)
        guard !delta.overflow,
              let end = Calendar.current.date(byAdding: .day, value: delta.partialValue, to: weekEndingDay) else { return }
        setWeekEndingDay(end)
    }

    func showCurrentWeek() {
        guard !isNavigationBlocked else { return }
        beginNavigation(); defer { endNavigation() }
        guard !isTutorialPresented else { return }
        refreshCurrentDay()
        let today = Date()
        selectedDay = today
        customWeeklyDays = nil
        weekEndingDay = today
        route = .weekly
    }

    /// Follow existing return slots without looping if an older route was
    /// already replaced. Search remains one session across temporary pages.
    private func returnRouteChain(from start: BoardRoute) -> [BoardRoute] {
        var visited: [BoardRoute] = []
        var current = start
        while !visited.contains(current) {
            visited.append(current)
            switch current {
            case .detail: current = origin
            case .searchNote: current = .search
            case .settings, .trash: current = auxiliaryReturnRoute
            case .newTask, .newNote: current = creationReturnRoute
            default: return visited
            }
        }
        return visited
    }

    func openSearch() {
        guard !isNavigationBlocked else { return }
        beginNavigation(); defer { endNavigation() }
        guard !isTutorialPresented else { return }
        // Returning to Search from a result is part of the same search session.
        // Keep the original working context instead of creating a detail/search loop.
        // This also applies to composers and auxiliary pages over that result.
        let returnChain = returnRouteChain(from: route)
        if searchSessionEnded || !returnChain.contains(.search) {
            if !returnChain.contains(.search) {
                searchReturnRoute = route
                searchReturnFilter = filter
                searchReturnCreationRoute = creationReturnRoute
                searchReturnAuxiliaryRoute = auxiliaryReturnRoute
                searchReturnCaptureID = workspace.selectedCaptureID
                searchDetailContext = returnChain.contains(.detail) ? selectedCapture.map {
                    SearchDetailContext(captureID: $0.id, origin: origin,
                        attachmentReturnTaskID: attachmentReturnTaskID, focus: detailFocus)
                } : nil
            }
            // A newly opened Search is global regardless of the project,
            // timeline, source or type currently visible. Those views remain
            // untouched so Back restores the exact originating context and
            // capture/composer destinations do not change.
            clearSearchRefinements()
            selectedSearchNote = nil
            resetSearchPosition()
        }
        searchSessionEnded = false
        weeklySearchActionsPresented = false
        if returnChain.contains(.search) {
            selectedSearchNote = nil
            if route != .search { navigationHistory.returnToPreviousSearch() }
        }
        route = .search
    }

    /// A general command starts a global search, or refocuses the current
    /// session without broadening its deliberate refinements.
    func performSearchCommand() {
        guard !isNavigationBlocked else { return }
        guard !isTutorialPresented else { return }
        openSearch()
        globalSearchFocusRequest &+= 1
    }

    /// Normal window close ends refinements; occlusion, resizing and result
    /// navigation do not. Keep the original Back destination for the next
    /// search command even when the hidden window still has a Search route.
    func endSearchSession() { searchSessionEnded = true }

    /// Results are live. Return keeps deliberate refinements.
    func submitSearch() {
        guard !isTutorialPresented, route == .search else { return }
        globalSearchFocusRequest &+= 1
    }

    func searchAllDates() {
        searchScope = .all
    }

    /// Keep the current words while removing every deliberate refinement.
    func searchEverything() {
        guard !isTutorialPresented else { return }
        openSearch()
        clearSearchFilters()
        globalSearchFocusRequest &+= 1
    }

    /// Clear visible Search chips without navigating or changing the query.
    /// This is used by the filters UI inside an existing search session.
    func clearSearchFilters() {
        clearSearchRefinements()
    }

    private func clearSearchRefinements() {
        // Assigning nil also exits the distinct Unfiled refinement through the
        // searchProject observer without touching the selected Library project.
        searchProject = nil
        searchSource = nil
        filter = .all
        searchScope = .all
        showSearchContext = false
    }

    func selectSearchProject(_ project: String?) {
        searchProject = project
    }

    func searchUnfiledProject() {
        if searchProject != nil { searchProject = nil }
        guard !searchUnfiledOnly else { return }
        searchUnfiledOnly = true
        resetSearchPosition()
    }

    func setSearchDay(_ day: Date, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        searchDay = calendar.startOfDay(for: day)
        searchScope = .day(CaptureCalendar.dayString(day, timeZone: timeZone))
    }

    func setSearchWeek(ending day: Date, calendar: Calendar = .current) {
        var civilCalendar = Calendar(identifier: .gregorian)
        civilCalendar.timeZone = calendar.timeZone
        let end = civilCalendar.startOfDay(for: day)
        searchWeekEndingDay = end
        let days = (-6...0).compactMap { civilCalendar.date(byAdding: .day, value: $0, to: end) }
        searchScope = .week(Set(days.map { CaptureCalendar.dayString($0, timeZone: civilCalendar.timeZone) }))
    }

    func setSearchRange(start: Date, end: Date, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        searchRangeStartDay = calendar.startOfDay(for: min(start, end))
        searchRangeEndDay = calendar.startOfDay(for: max(start, end))
        searchScope = .range(startDay: CaptureCalendar.dayString(searchRangeStartDay, timeZone: timeZone),
                             endDay: CaptureCalendar.dayString(searchRangeEndDay, timeZone: timeZone))
    }

    func updateGlobalSearch(_ text: String) {
        guard route == .search || !isNavigationBlocked else { return }
        guard !isTutorialPresented else { return }
        // SwiftUI can write a field's empty display value when it mounts or
        // loses focus. Navigating between views must not initiate a search.
        guard route == .search || !text.isEmpty else { return }
        if route != .search { openSearch() }
        query = text
    }

    func openSearch(day: Date) {
        guard !isNavigationBlocked else { return }
        beginNavigation(); defer { endNavigation() }
        guard !isTutorialPresented else { return }
        openSearch()
        setSearchDay(day)
    }

    func openSearch(week days: [Date]) {
        guard !isNavigationBlocked else { return }
        beginNavigation(); defer { endNavigation() }
        guard !isTutorialPresented else { return }
        openSearch()
        if let end = days.max() { searchWeekEndingDay = end }
        searchScope = .week(Set(days.map { CaptureCalendar.dayString($0) }))
    }

    /// Open an editable scratchpad result without changing the Library project,
    /// Workspace selection, or any capture/composer destination. Back returns
    /// to the same Search session and chronological board position.
    func openSearchNote(_ note: WorkspaceScratchpad) {
        guard !isNavigationBlocked else { return }
        beginNavigation(); defer { endNavigation() }
        guard route == .search else { return }
        searchSelectedResultID = SearchDateItem.note(note).id
        navigationHistory.updateCurrent(navigationSnapshot())
        selectedSearchNote = note
        route = .searchNote
    }
    func showReminders() { refreshCurrentDay(); navigate(to: .reminders) }
    func showSettings() {
        guard !isNavigationBlocked else { return }
        beginNavigation(); defer { endNavigation() }
        guard !isTutorialPresented else { return }
        if !returnRouteChain(from: route).contains(where: { $0 == .settings || $0 == .trash }) { auxiliaryReturnRoute = route }
        route = .settings
    }

    func toggleAutoCaptureFromHeader() {
        guard !isTutorialPresented else { return }
        let settings = autoCapture.settings
        if settings.isEnabled {
            autoCapture.setPaused(!settings.isPaused)
        } else {
            autoCaptureSetupRequested = true
            showSettings()
        }
    }

    func consumeAutoCaptureSetupRequest() -> Bool {
        guard autoCaptureSetupRequested else { return false }
        autoCaptureSetupRequested = false
        return true
    }

    private var composerProjectContext: String? {
        let chain = returnRouteChain(from: route)
        return chain.contains(.library) || chain.contains(.reminders) ? libraryProject : nil
    }

    func openNewTask() {
        guard !isNavigationBlocked else { return }
        beginNavigation(); defer { endNavigation() }
        guard !isTutorialPresented else { return }
        if !newTaskDraft.hasChanges || newTaskDraft.destination == nil {
            newTaskDraft.destination = ComposerDestination(projectName: composerProjectContext)
        }
        if !returnRouteChain(from: route).contains(where: { $0 == .newTask || $0 == .newNote }) { creationReturnRoute = route }
        status = nil
        newTaskDraft.message = nil
        route = .newTask
    }

    func openNewNote() {
        guard !isNavigationBlocked else { return }
        beginNavigation(); defer { endNavigation() }
        guard !isTutorialPresented else { return }
        if newNoteDestination == nil || (newNoteText.isEmpty && !returnRouteChain(from: route).contains(.newNote)) {
            newNoteDestination = ComposerDestination(projectName: composerProjectContext)
        }
        if !returnRouteChain(from: route).contains(where: { $0 == .newTask || $0 == .newNote }) { creationReturnRoute = route }
        status = nil
        route = .newNote
    }
    func clearNewNoteDraft() {
        newNoteText = ""
        newNoteDestination = nil
    }
    func cancelNewNote() { beginNavigation(); defer { endNavigation() }; clearNewNoteDraft(); route = creationReturnRoute }
    func saveNewNote() {
        beginNavigation(); defer { endNavigation() }
        do {
            let saved = try store.createNote(text: newNoteText, projectName: newNoteProject)
            clearNewNoteDraft()
            route = creationReturnRoute
            didCapture([saved])
        } catch { reportFailure("Could not save the note: \(error.localizedDescription)") }
    }

    func pasteClipboard(from pasteboard: NSPasteboard = .general) {
        guard !isTutorialPresented, !isImporting, !isArchiveOperationRunning else { return }
        if route == .library, workspace.mode == .collection {
            explorerInput.paste(project: libraryProject, from: pasteboard)
            return
        }
        let navigation = captureNavigationRevision
        manualInput.receive(pasteboard, completion: { [weak self] captures, failures in
            guard let self else { return }
            if !captures.isEmpty, self.captureNavigationRevision == navigation,
               self.route != .inbox && self.route != .reminders { self.openDaily() }
            self.reportCaptureResult(captures, errors: failures)
        })
    }

    func importFiles() {
        guard !isTutorialPresented, !isImporting, !isArchiveOperationRunning else { return }
        if route == .library, workspace.mode == .collection {
            explorerInput.chooseFiles(project: libraryProject)
            return
        }
        let picker = NSOpenPanel()
        picker.title = "Add files to DaBin"
        picker.prompt = "Add files"
        picker.canChooseDirectories = false
        picker.allowsMultipleSelection = true
        guard picker.runModal() == .OK else { return }
        let urls = picker.urls
        let receivedAt = Date()
        let navigation = captureNavigationRevision
        isFileImporting = true
        Task {
            var saved: [Capture] = [], failures: [String] = []
            for url in urls {
                do { saved.append(try await store.importFile(url, at: receivedAt)) }
                catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            }
            isFileImporting = false
            if !saved.isEmpty, captureNavigationRevision == navigation,
               route != .inbox && route != .reminders { openDaily() }
            reportCaptureResult(saved, errors: failures)
        }
    }

    @discardableResult
    func receiveTaskAttachments(_ providers: [NSItemProvider], to task: Capture) -> Bool {
        guard task.isTask, !isImporting, !isArchiveOperationRunning, !providers.isEmpty else { return false }
        if providers.contains(where: ExplorerTransfer.containsInternalReference) {
            return explorerInput.receive(providers, attachingTo: task)
        }
        manualInput.receiveProviders(providers, attachingTo: task) { [weak self] captures, failures in
            self?.finishTaskAttachments(captures, failures: failures)
        }
        return true
    }

    func pasteAttachments(to task: Capture, from pasteboard: NSPasteboard = .general) {
        guard task.isTask, !isImporting, !isArchiveOperationRunning else { return }
        manualInput.receive(pasteboard, attachingTo: task, completion: { [weak self] captures, failures in
            self?.finishTaskAttachments(captures, failures: failures)
        })
    }

    func importTaskAttachments(to task: Capture) {
        guard task.isTask, !isImporting, !isArchiveOperationRunning else { return }
        let picker = NSOpenPanel()
        picker.title = "Add files to task"
        picker.prompt = "Attach"
        picker.canChooseDirectories = false
        picker.allowsMultipleSelection = true
        guard picker.runModal() == .OK else { return }
        let urls = picker.urls
        isFileImporting = true
        Task {
            var saved: [Capture] = [], failures: [String] = []
            for url in urls {
                do { saved.append(try await store.importFile(url, parentTask: task)) }
                catch { failures.append(error.localizedDescription) }
            }
            isFileImporting = false
            finishTaskAttachments(saved, failures: failures)
        }
    }

    private func finishTaskAttachments(_ captures: [Capture], failures: [String]) {
        previews.process(captures)
        contentIndex?.process(captures)
        captureLayoutRevision &+= 1
        if !failures.isEmpty { reportFailure(failures.joined(separator: "\n")) }
        else if !captures.isEmpty {
            status = AppStatusMessage(text: "Added \(captures.count) \(captures.count == 1 ? "item" : "items") to task.", severity: .success)
        }
    }

    func togglePinned(_ capture: Capture) {
        do { try store.setOrganization(capture, pinned: !capture.isPinned, projectName: capture.projectName) }
        catch { reportFailure("Could not update the pin: \(error.localizedDescription)") }
    }
    func assignProject(_ capture: Capture, name: String?) {
        do { try store.setOrganization(capture, pinned: capture.isPinned, projectName: name) }
        catch { reportFailure("Could not update the project: \(error.localizedDescription)") }
    }
    func completeFollowUp(_ capture: Capture) {
        if capture.isTask { if !capture.isCompleted { toggleTaskCompletion(capture) }; return }
        do {
            try store.update(capture, comment: capture.comment, reminderAt: nil, reminderTimeZoneID: nil)
            drafts[capture.id]?.adoptSavedReminder(from: capture)
            clearReminderFeedback(for: capture)
            Task { await reminders.clearForCapture(capture.id) }
        } catch { reportFailure("Could not complete this follow-up: \(error.localizedDescription)") }
    }
    func snoozeFollowUp(_ capture: Capture) {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date().addingTimeInterval(86400)
        let morning = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        do {
            try store.update(capture, comment: capture.comment, reminderAt: morning, reminderTimeZoneID: TimeZone.current.identifier)
            drafts[capture.id]?.adoptSavedReminder(from: capture)
            Task { await saveReminderAndReport(for: capture) }
        } catch { reportFailure("Could not snooze this follow-up: \(error.localizedDescription)") }
    }

    func cancelNewTask() {
        beginNavigation(); defer { endNavigation() }
        newTaskDraft.reset()
        route = creationReturnRoute
    }

    func saveNewTask() {
        beginNavigation(); defer { endNavigation() }
        guard !newTaskDraft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            newTaskDraft.message = "Give your task a name."
            newTaskDraft.validationFailed = true
            return
        }
        let committedPlanning: TaskPlanning
        do { committedPlanning = try ChecklistDraftPolicy.committing(newTaskDraft.pendingChecklistText, to: newTaskDraft.planning) }
        catch { newTaskDraft.message = error.localizedDescription; newTaskDraft.validationFailed = true; return }
        let reminder: Date?
        do {
            reminder = newTaskDraft.reminderEnabled ? try ReminderSchedule.resolve(
                mode: newTaskDraft.reminderMode, date: newTaskDraft.reminderDate,
                hours: newTaskDraft.countdownHours, minutes: newTaskDraft.countdownMinutes, now: Date()) : nil
        } catch { newTaskDraft.message = error.localizedDescription; newTaskDraft.validationFailed = true; return }
        if let reminder, reminder <= Date() {
            newTaskDraft.message = "Choose a reminder time in the future."
            newTaskDraft.validationFailed = true
            return
        }
        guard committedPlanning.isValid else {
            newTaskDraft.message = "Check the task dates, estimate, and checklist before saving."
            newTaskDraft.validationFailed = true
            return
        }
        newTaskDraft.validationFailed = false
        do {
            let project = newTaskProject
            let capture = try store.createTask(text: newTaskDraft.text, reminderAt: reminder,
                reminderTimeZoneID: reminder == nil ? nil : TimeZone.current.identifier,
                planning: committedPlanning, projectName: project)
            newTaskDraft.reset()
            route = creationReturnRoute
            status = AppStatusMessage(text: project.map { "Task saved in \($0)." } ?? "Task saved to Inbox.", severity: .success)
            dailyScrollID = feedID(for: capture, on: selectedDay)
            if reminder != nil {
                Task { await saveReminderAndReport(for: capture) }
            }
        } catch {
            newTaskDraft.message = "Could not add this task: \(error.localizedDescription)"
        }
    }

    func convertToTask(_ capture: Capture, openDetails: Bool = false) {
        guard removingCaptureID != capture.id else { return }
        do {
            let wasTask = capture.isTask
            let previousParent = capture.parentTaskID
            try store.convertToTask(capture)
            guard !wasTask else { return }
            captureLayoutRevision &+= 1
            // Conversion can split a file batch or an automatic-hour summary.
            // Keep the converted card as the return-to-Daily scroll target.
            dailyScrollID = feedID(for: capture, on: selectedDay)
            lastConvertedCaptureID = capture.id
            lastConversionParentID = previousParent
            status = AppStatusMessage(text: "Turned into a task. You can undo this.", severity: .success)
            if openDetails { openCapture(capture.id, focus: "task") }
            else if route == .detail && selectedCapture?.id == capture.id { detailFocus = "task" }
        } catch {
            reportFailure("Couldn’t turn this capture into a task: \(error.localizedDescription)")
        }
    }

    var canUndoTaskConversion: Bool {
        guard let id = lastConvertedCaptureID, let capture = store.captures.first(where: { $0.id == id }) else { return false }
        return capture.convertedToTask && !capture.isCompleted && (capture.taskPlanning == nil || capture.taskPlanning == TaskPlanning())
            && store.attachments(for: capture).isEmpty
            && conversionDraftAllowsUndo(capture)
    }

    private func conversionDraftAllowsUndo(_ capture: Capture) -> Bool {
        guard let draft = drafts[capture.id] else { return true }
        return draft.planning == TaskPlanning() && draft.title == capture.title && draft.pendingChecklistText.isEmpty
    }

    func undoTaskConversion() {
        guard let id = lastConvertedCaptureID, let capture = store.captures.first(where: { $0.id == id }) else { return }
        // An unfinished task draft is work too; do not silently discard it.
        guard conversionDraftAllowsUndo(capture) else {
            reportFailure("Save or discard task edits before undoing the conversion."); return
        }
        do {
            try store.undoTaskConversion(capture, previousParentID: lastConversionParentID)
            lastConvertedCaptureID = nil; lastConversionParentID = nil
            captureLayoutRevision &+= 1
            status = AppStatusMessage(text: "Kept as a capture.", severity: .success)
        } catch { reportFailure(error.localizedDescription) }
    }

    /// Bulk undo must also respect unfinished detail edits, not just saved
    /// metadata. Reordering the project does not invalidate this receipt.
    @discardableResult
    func undoProjectTaskConversion(_ receipt: ProjectTaskConversionReceipt) -> Bool {
        guard !receipt.captureIDs.contains(where: { drafts[$0]?.hasChanges == true }) else {
            reportFailure("Save or discard task edits before undoing the conversion.")
            return false
        }
        do {
            try store.undoProjectTaskConversion(receipt)
            captureLayoutRevision &+= 1
            status = AppStatusMessage(text: "Kept as captures.", severity: .success)
            return true
        } catch { reportFailure(error.localizedDescription); return false }
    }

    func convertProjectItemsToTasks(_ captures: [Capture]) throws -> ProjectTaskConversionReceipt {
        let receipt = try store.convertProjectItemsToTasks(captures)
        if !receipt.isEmpty { captureLayoutRevision &+= 1 }
        return receipt
    }

    @discardableResult
    func configureTaskFocus(_ capture: Capture, hours: Int, minutes: Int, start: Bool = false, at now: Date = Date()) -> Bool {
        guard let duration = TaskFocusSession.duration(hours: hours, minutes: minutes) else {
            reportFailure("Choose a duration from 1 minute to 168 hours. Minutes must be 0–59."); return false
        }
        let session = TaskFocusSession(remainingSeconds: TimeInterval(duration * 60),
            endAt: start ? now.addingTimeInterval(TimeInterval(duration * 60)) : nil)
        return commitTaskFocus(capture, session: session, duration: duration)
    }

    @discardableResult
    func toggleTaskFocus(_ capture: Capture, at now: Date = Date()) -> Bool {
        guard let duration = capture.taskPlanning?.effortMinutes, !capture.isCompleted else { return false }
        let session = capture.taskPlanning?.focusSession ?? TaskFocusSession(remainingSeconds: TimeInterval(duration * 60))
        return commitTaskFocus(capture, session: session.isRunning && session.remaining(at: now) > 0
            ? session.paused(at: now) : session.started(at: now, durationMinutes: duration))
    }

    @discardableResult
    func resetTaskFocus(_ capture: Capture) -> Bool {
        guard let duration = capture.taskPlanning?.effortMinutes else { return false }
        return commitTaskFocus(capture, session: TaskFocusSession(remainingSeconds: TimeInterval(duration * 60)))
    }

    @discardableResult
    private func commitTaskFocus(_ capture: Capture, session: TaskFocusSession, duration: Int? = nil) -> Bool {
        do {
            try store.setTaskFocus(capture, session: session, durationMinutes: duration)
            drafts[capture.id]?.adoptImmediateTiming(from: capture, schedule: false, duration: duration != nil)
            return true
        } catch { reportFailure("Could not save the focus session: \(error.localizedDescription)"); return false }
    }

    @discardableResult
    func scheduleTask(_ capture: Capture, day: String?, time: String? = nil) -> Bool {
        do {
            try store.planTask(capture, on: day, time: time)
            drafts[capture.id]?.adoptImmediateTiming(from: capture, schedule: true, duration: false)
            return true
        } catch { reportFailure("Could not save the work schedule: \(error.localizedDescription)"); return false }
    }

    func toggleTaskCompletion(_ capture: Capture) {
        guard capture.isTask else { return }
        do {
            let successor = try store.setTaskCompleted(capture, completed: !capture.isCompleted)
            drafts[capture.id]?.adoptSavedPlanning(from: capture)
            if capture.isCompleted { clearReminderFeedback(for: capture); onTaskCompleted?() }
            objectWillChange.send()
            Task {
                if capture.isCompleted { await reminders.clearForCapture(capture.id) }
                else { await saveReminderAndReport(for: capture) }
                if let successor, successor.reminderAt != nil { await saveReminderAndReport(for: successor) }
            }
        } catch {
            reportFailure("Could not update the task: \(error.localizedDescription)")
        }
    }

    func toggleMinimized(_ capture: Capture) {
        guard removingCaptureID != capture.id else { return }
        do {
            try store.setMinimized(capture, minimized: !capture.isMinimized)
            captureLayoutRevision &+= 1
        }
        catch { reportFailure("Could not resize this capture: \(error.localizedDescription)") }
    }

    func toggleMinimized(_ captures: [Capture]) {
        let current = captures.filter { capture in
            store.captures.contains(where: { $0 === capture })
        }
        guard !current.isEmpty, removingCaptureID == nil else { return }
        let minimized = !current.allSatisfy(\.isMinimized)
        do {
            for capture in current where capture.isMinimized != minimized {
                try store.setMinimized(capture, minimized: minimized)
            }
            captureLayoutRevision &+= 1
        } catch {
            reportFailure("Could not resize this batch: \(error.localizedDescription)")
        }
    }

    func isHourlyGroupExpanded(_ key: AutomaticHourKey) -> Bool {
        expandedAutomaticHours.contains(key)
    }

    func toggleHourlyGroup(_ key: AutomaticHourKey) {
        if expandedAutomaticHours.remove(key) == nil { expandedAutomaticHours.insert(key) }
        captureLayoutRevision &+= 1
    }

    @discardableResult
    func copyCapturesToClipboard(_ captures: [Capture]) -> Bool {
        let currentIDs = Set(store.captures.map(\.id))
        guard !captures.isEmpty, captures.allSatisfy({ currentIDs.contains($0.id) }) else {
            reportFailure("Couldn’t copy this action because it is no longer in the archive.")
            return false
        }
        do {
            try captureClipboard.copy(captures, managedURL: store.managedURL(for:))
            return true
        } catch {
            reportFailure("Couldn’t copy this action: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func copySearchNote(_ note: WorkspaceScratchpad) -> Bool {
        do {
            try captureClipboard.copyText(workspace.scratchpad(project: note.projectName))
            return true
        } catch {
            reportFailure("Couldn’t copy this note: \(error.localizedDescription)")
            return false
        }
    }

    func requestRemoval(_ capture: Capture) {
        guard removingCaptureID == nil, store.captures.contains(where: { $0 === capture }) else { return }
        pendingRemoval = capture
    }

    func confirmRemoval() {
        guard let capture = pendingRemoval else { return }
        pendingRemoval = nil
        Task { await removeCapture(capture) }
    }

    /// Quiesce background writes before moving the record to Recently Deleted.
    /// Its files and annotations stay available until explicit permanent removal.
    func removeCapture(_ capture: Capture) async {
        guard removingCaptureID == nil, store.captures.contains(where: { $0 === capture }) else { return }
        removingCaptureID = capture.id
        defer { removingCaptureID = nil }
        let family = store.captureFamily(for: capture)
        let familyIDs = Set(family.map(\.id))
        for item in family {
            await contentIndex?.cancel(for: item.id)
            await previews.cancel(for: item.id)
        }
        // Cancellation can yield while the user visits another page. Only
        // restore a destination if the removed detail is still being shown.
        let removesDisplayedDetail = route == .detail && selectedCapture.map { familyIDs.contains($0.id) } == true
        var removalParent: NavigationSnapshot?
        if removesDisplayedDetail {
            var parent = navigationSnapshot()
            let taskID = attachmentReturnTaskID.flatMap { id in
                !familyIDs.contains(id) && store.captures.contains(where: { $0.id == id }) ? id : nil
            }
            parent.route = taskID == nil ? (origin == .detail ? .inbox : origin) : .detail
            parent.selectedCaptureID = taskID
            parent.workspace.selectedID = taskID
            parent.focus = taskID == nil ? nil : "task"
            parent.focusTarget = nil
            parent.workspaceViewport = nil
            parent.returnContext.attachmentTaskID = nil
            removalParent = parent
        }
        do {
            try store.moveToTrash(capture)
            undoRemovalIDs = [capture.id]
            captureLayoutRevision &+= 1
            for item in family { drafts.removeValue(forKey: item.id); clearReminderFeedback(for: item) }
            if let pendingID = pendingRemoval?.id, familyIDs.contains(pendingID) { pendingRemoval = nil }
            // Removing an action can dissolve a four-action summary, so a prior
            // feed anchor may no longer exist.
            dailyScrollID = nil
            if let scrollID = searchScrollID, familyIDs.contains(scrollID) { searchScrollID = nil }
            if let selectedID = selectedCapture?.id, familyIDs.contains(selectedID) {
                selectedCapture = nil
                selectedDraft = nil
                detailFocus = nil
            }
            reconcileNavigationHistory()
            if removesDisplayedDetail, let destination = navigationHistory.current ?? removalParent {
                // A removed visit is pruned, so the surviving task keeps its
                // own viewport, focus and live draft rather than the deleted
                // attachment's presentation. Direct opens use their parent.
                navigationHistory.updateCurrent(destination)
                restoreNavigation(destination)
            }
            status = AppStatusMessage(text: "Moved to Recently Deleted. You can undo this.", severity: .success)
            for item in family { await reminders.clearForCapture(item.id) }
        } catch {
            reportFailure("Could not remove this capture: \(error.localizedDescription)")
            previews.process(family)
            contentIndex?.process(family)
        }
    }

    func removeCaptures(_ captures: [Capture]) async {
        let ids = Set(captures.map(\.id))
        guard !ids.isEmpty, removingCaptureID == nil else { return }
        for capture in captures where store.captures.contains(where: { $0 === capture }) {
            await removeCapture(capture)
        }
        let remaining = store.captures.filter { ids.contains($0.id) }
        undoRemovalIDs = store.trashedCaptures.filter { ids.contains($0.id) }.map(\.id)
        if remaining.isEmpty {
            status = AppStatusMessage(text: "Moved \(ids.count) items to Recently Deleted.", severity: .success)
        } else if status?.severity != .error {
            reportFailure("Could not remove every item in this batch.")
        }
    }

    func restoreCapture(_ capture: Capture) async {
        guard removingCaptureID == nil, !isArchiveOperationRunning else { return }
        removingCaptureID = capture.id
        defer { removingCaptureID = nil }
        do {
            try store.restoreFromTrash(capture)
            guard let restored = store.captures.first(where: { $0.id == capture.id }) else {
                throw CaptureStoreError.invalidOriginal("The restored record could not be found.")
            }
            undoRemovalIDs.removeAll { $0 == capture.id }
            captureLayoutRevision &+= 1
            let family = store.captureFamily(for: restored)
            previews.process(family)
            contentIndex?.process(family)
            for item in family {
                if let due = item.reminderAt, due > Date(), !(item.isTask && item.isCompleted) {
                    await reminders.saveReminder(for: item)
                }
            }
            status = AppStatusMessage(text: "Capture restored to its original date and project.", severity: .success)
        } catch { reportFailure("Could not restore this capture: \(error.localizedDescription)") }
    }

    func undoLastRemoval() async {
        let ids = undoRemovalIDs
        for id in ids {
            if let capture = store.trashedCaptures.first(where: { $0.id == id }) { await restoreCapture(capture) }
        }
    }

    func permanentlyRemoveCapture(_ capture: Capture) async {
        guard removingCaptureID == nil, !isArchiveOperationRunning,
              store.trashedCaptures.contains(where: { $0 === capture }) else { return }
        removingCaptureID = capture.id
        defer { removingCaptureID = nil }
        let family = store.captureFamily(for: capture, includingTrashed: true)
        for item in family {
            await contentIndex?.cancel(for: item.id)
            await previews.cancel(for: item.id)
        }
        do {
            let result = try store.permanentlyRemove(capture)
            undoRemovalIDs.removeAll { $0 == capture.id }
            status = AppStatusMessage(text: result.warning ?? "Capture permanently deleted.",
                                     severity: result.cleanupPending ? .warning : .success)
            for item in family { await reminders.clearForCapture(item.id) }
        } catch { reportFailure("Could not permanently remove this capture: \(error.localizedDescription)") }
    }

    func exportArchiveBackup() {
        guard !workspace.hasUnsavedChanges else { reportFailure("Save or retry the scratchpad before backing up."); return }
        guard !isArchiveOperationRunning, !isImporting, removingCaptureID == nil else { return }
        let picker = NSSavePanel()
        picker.title = "Back up your DaBin archive"
        picker.prompt = "Create backup"
        picker.message = "Includes your captures, original files, projects, notes, reminders and Recently Deleted. Choose a local folder for a private backup."
        picker.nameFieldStringValue = "DaBin-\(CaptureCalendar.dayString(Date())).dabinbackup"
        picker.canCreateDirectories = true
        guard picker.runModal() == .OK, let url = picker.url else { return }
        isArchiveOperationRunning = true
        defer { isArchiveOperationRunning = false }
        do {
            try store.exportBackup(to: url)
            status = AppStatusMessage(text: "Backup saved to \(url.lastPathComponent).", severity: .success)
        } catch { reportFailure("Could not create the backup: \(error.localizedDescription)") }
    }

    func restoreArchiveBackup() {
        guard !workspace.hasUnsavedChanges else { reportFailure("Save or retry the scratchpad before restoring a backup."); return }
        guard !isArchiveOperationRunning, !isImporting, removingCaptureID == nil else { return }
        let picker = NSOpenPanel()
        picker.title = "Restore a DaBin backup"
        picker.prompt = "Restore backup"
        picker.message = "Choose a .dabinbackup folder. Missing captures are added; existing captures are never overwritten."
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.allowsMultipleSelection = false
        picker.treatsFilePackagesAsDirectories = true
        guard picker.runModal() == .OK, let url = picker.url else { return }
        isArchiveOperationRunning = true
        defer { isArchiveOperationRunning = false }
        do {
            let result = try store.restoreBackup(from: url)
            try workspace.reload()
            previews.process(store.captures)
            contentIndex?.process(store.captures)
            Task { await reminders.reconcile() }
            captureLayoutRevision &+= 1
            status = AppStatusMessage(text: "Restored \(result.addedCount) captures; \(result.existingCount) already present.", severity: .success)
        } catch { reportFailure("Could not restore the backup: \(error.localizedDescription)") }
    }

    func openCapture(_ id: UUID, focus: String? = nil) {
        guard !isNavigationBlocked else { return }
        guard !isTutorialPresented else { return }
        guard let capture = store.captures.first(where: { $0.id == id }) else {
            reportFailure("This capture could not be found.")
            return
        }
        beginNavigation(); defer { endNavigation() }
        if route == .search {
            searchSelectedResultID = "capture:" + id.uuidString
            navigationHistory.updateCurrent(navigationSnapshot())
        }
        if route == .detail, let current = selectedCapture, current.isTask, capture.parentTaskID == current.id {
            attachmentReturnTaskID = current.id
        } else { attachmentReturnTaskID = nil }
        if route == .search || !returnRouteChain(from: route).contains(.detail) { origin = route }
        selectedCapture = capture
        workspace.selectedCaptureID = id
        if drafts[id] == nil {
            let draft = CaptureDraft(capture: capture)
            drafts[id] = draft
            observeDraft(draft)
        }
        selectedDraft = drafts[id]
        // An explicit section request starts in that pane. History restoration
        // assigns its saved viewport separately and never comes through here.
        if route == .detail, let focus, detailFocus != focus {
            workspaceViewport = nil
        }
        detailFocus = focus
        route = .detail
    }

    func openExtendedCapture(_ id: UUID) {
        guard !isNavigationBlocked else { return }
        guard !isTutorialPresented else { return }
        if selectedCapture?.id != id || route != .detail { openCapture(id) }
        guard route == .detail, let capture = selectedCapture, capture.id == id,
              let draft = selectedDraft else { return }
        onOpenExtendedCapture?(capture, draft)
    }

    @discardableResult
    func postDetailComment(_ capture: Capture, draft: CaptureDraft) -> Bool {
        guard !draft.commentComposer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard draft.comment == capture.comment else {
            draft.message = "Save your recovered comment edit before posting a new comment."
            draft.hasError = true
            return false
        }
        do {
            if let id = draft.editingCommentID {
                try store.updateComment(capture, id: id, text: draft.commentComposer)
            } else {
                _ = try store.appendComment(capture, text: draft.commentComposer)
            }
            draft.adoptSavedComments(from: capture)
            persistDrafts()
            return true
        } catch {
            draft.message = "Could not save the comment: \(error.localizedDescription)"
            draft.hasError = true
            return false
        }
    }

    @discardableResult
    func setDetailReminder(_ capture: Capture, date: Date?) -> Bool {
        do {
            try store.update(capture, comment: capture.comment, reminderAt: date,
                             reminderTimeZoneID: date == nil ? nil : TimeZone.current.identifier)
            drafts[capture.id]?.adoptSavedReminder(from: capture)
            drafts[capture.id]?.message = date == nil ? "Reminder removed." : "Reminder saved."
            drafts[capture.id]?.hasError = false
            if date == nil { clearReminderFeedback(for: capture) }
            Task {
                if date == nil { await reminders.clearForCapture(capture.id) }
                else { await saveReminderAndReport(for: capture) }
            }
            return true
        } catch {
            let message = "Could not update this reminder: \(error.localizedDescription)"
            drafts[capture.id]?.message = message
            drafts[capture.id]?.hasError = true
            reportFailure(message)
            return false
        }
    }

    var canGoBack: Bool {
        navigationHistory.canGoBack || (navigationHistory.entries.isEmpty && route == .detail && selectedCapture != nil)
    }
    var canGoForward: Bool { navigationHistory.canGoForward }
    private var hasWorkspaceNavigationBlocker: Bool {
        isTutorialPresented || pendingRemoval != nil || isArchiveOperationRunning || isDailyDropTargeted
            || navigationWindowInteractionBlocked || navigationValidationBlocked
    }
    var isWorkspaceInputBlocked: Bool {
        hasWorkspaceNavigationBlocker
            || (route == .detail && selectedDraft?.hasUnresolvedValidation == true)
            || (route == .newTask && newTaskDraft.hasUnresolvedValidation)
    }
    var isNavigationBlocked: Bool { isWorkspaceInputBlocked || workspaceZoom.isInteracting }
    var navigationInputBlocked: Bool { isNavigationBlocked }

    /// The single navigation command path. Native input adds responder/modal
    /// protection; views use these same methods and enabled state.
    func back() { moveInHistory(forward: false) }
    func forward() { moveInHistory(forward: true) }

    /// Explicit recovery can leave an invalid Detail draft without applying it.
    /// Ordinary history and route commands keep their validation gate.
    var canKeepDetailDraftAndGoBack: Bool {
        guard route == .detail, selectedDraft?.hasUnresolvedValidation == true, canGoBack,
              navigationDepth == 0, !hasWorkspaceNavigationBlocker, !workspaceZoom.isInteracting else { return false }
        let window = NSApp?.keyWindow
        return window?.attachedSheet == nil && window?.sheetParent == nil && NSApp?.modalWindow == nil
            && (window?.firstResponder as? NSTextView)?.hasMarkedText() != true
            && NSEvent.pressedMouseButtons & 1 == 0
    }

    @discardableResult
    func keepDetailDraftAndGoBack() -> Bool {
        guard canKeepDetailDraftAndGoBack else { return false }
        persistDrafts()
        guard draftPersistenceError == nil else { return false }
        return moveInHistory(forward: false, keepingInvalidDetailDraft: true)
    }

    func navigate(to destination: BoardRoute) {
        guard !isNavigationBlocked, destination != route else { return }
        beginNavigation(); defer { endNavigation() }
        route = destination
    }

    func navigateProject(_ project: String?, unfiledOnly: Bool = false) {
        guard !isNavigationBlocked else { return }
        beginNavigation(); defer { endNavigation() }
        libraryProject = project
        workspace.explorerUnfiledOnly = unfiledOnly
    }

    func navigateWorkspaceMode(_ mode: WorkspaceMode) {
        guard !isNavigationBlocked else { return }
        beginNavigation(); defer { endNavigation() }
        workspace.mode = mode
    }

    /// Nestable so an explicit date action that opens Search records one visit.
    func beginNavigation() {
        guard !isRestoringNavigation else { return }
        if navigationDepth == 0 {
            navigationTransitionRevision &+= 1
            WorkspaceZoomViewport.flushHistory()
            navigationFocusTarget = onCaptureNavigationFocus?()
            navigationHistory.updateCurrent(navigationSnapshot())
        }
        navigationDepth += 1
    }

    func endNavigation() {
        guard !isRestoringNavigation, navigationDepth > 0 else { return }
        navigationDepth -= 1
        if navigationDepth == 0 {
            navigationFocusTarget = nil
            var destination = navigationSnapshot()
            if navigationHistory.current?.hasSameDestination(as: destination) == false {
                workspaceViewport = nil
                destination.workspaceViewport = nil
                if destination.route == .weekly {
                    weeklyColumnViewports = [:]
                    destination.weeklyColumnViewports = [:]
                }
            }
            navigationHistory.visit(destination)
        }
    }

    @discardableResult
    private func moveInHistory(forward: Bool, keepingInvalidDetailDraft: Bool = false) -> Bool {
        if keepingInvalidDetailDraft {
            guard !forward, canKeepDetailDraftAndGoBack else { return false }
        } else {
            guard !isNavigationBlocked, navigationDepth == 0 else { return false }
        }
        WorkspaceZoomViewport.flushHistory()
        navigationFocusTarget = onCaptureNavigationFocus?()
        // A system/direct-open detail has one known parent. Never fabricate a
        // next day or a Forward destination at an otherwise empty root.
        if navigationHistory.entries.isEmpty, route == .detail {
            var parent = navigationSnapshot()
            parent.route = origin == .detail ? .inbox : origin
            parent.selectedCaptureID = nil
            parent.focus = nil
            navigationHistory.updateCurrent(parent)
            navigationHistory.visit(navigationSnapshot())
        } else { navigationHistory.updateCurrent(navigationSnapshot()) }
        reconcileNavigationHistory()
        guard let snapshot = forward ? navigationHistory.forward() : navigationHistory.back() else { return false }
        restoreNavigation(snapshot)
        return true
    }

    /// Call only after a successful rename. Projects currently use exact names
    /// as identity; never guess which new project replaced a missing name.
    func projectWasRenamed(from oldName: String, to newName: String) {
        guard oldName != newName else { return }
        projectRenames[oldName] = newName
        if let presentation = projectPresentation.removeValue(forKey: oldName) {
            projectPresentation[newName] = presentation
        }
        if libraryProject == oldName { libraryProject = newName }
        if searchProject == oldName { searchProject = newName }
        reconcileNavigationHistory()
    }

    private struct NavigationLiveIdentities {
        var captureIDs: Set<UUID>
        var projects: Set<String>
        var presentationIDs: Set<String>
        var todayReceiptIDs: Set<String>
        var noteKeys: Set<String>
        var projectItemIDs: [String: Set<String>]
    }

    func reconcileNavigationHistory() {
        // Resolve the live archive once per command, not once per history
        // entry. A hundred visits over a large archive remain one linear scan.
        let captures = store.captures
        let byID = Dictionary(uniqueKeysWithValues: captures.map { ($0.id, $0) })
        let captureIDs = Set(byID.keys)
        let noteKeys = Set(workspace.snapshot.scratchpads.keys).union(workspace.pendingScratchpads.keys)
        var projectItemIDs: [String: Set<String>] = [:]
        for capture in captures {
            let parent = capture.parentTaskID.flatMap { byID[$0] }
            let project = parent == nil ? capture.projectName : parent?.projectName
            projectItemIDs[WorkspaceSnapshot.projectKey(project), default: []].insert(ProjectWorkspaceIdentity.capture(capture.id))
        }
        for key in noteKeys {
            let text = workspace.pendingScratchpads[key] ?? workspace.snapshot.scratchpads[key]?.text ?? ""
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                projectItemIDs[key, default: []].insert("note:" + key)
            }
        }
        let live = NavigationLiveIdentities(captureIDs: captureIDs,
            projects: Set(captures.compactMap(\.projectName)).union(workspace.projectNames),
            presentationIDs: Set(captureIDs.map(ProjectWorkspaceIdentity.capture)).union(noteKeys.map { "note:" + $0 }),
            todayReceiptIDs: Set(captures.filter { $0.captureDay == currentDayKey }.map { Self.todayReceiptItemID($0.id) }),
            noteKeys: noteKeys, projectItemIDs: projectItemIDs)
        navigationHistory.reconcile { resolveNavigation($0, live: live) }
    }

    private func navigationSnapshot() -> NavigationSnapshot {
        var result = NavigationSnapshot()
        result.route = route; result.project = libraryProject
        result.selectedCaptureID = selectedCapture?.id
        result.selectedNoteProjectKey = selectedSearchNote.map { WorkspaceSnapshot.projectKey($0.projectName) }
        result.day = selectedDay; result.weekEndingDay = weekEndingDay; result.weeklyDays = customWeeklyDays
        result.filter = filter; result.pinnedOnly = libraryPinnedOnly
        result.query = String(query.prefix(2_000)); result.searchProject = searchProject
        result.searchUnfiledOnly = searchUnfiledOnly; result.searchSource = searchSource
        result.searchScope = searchScope; result.searchDay = searchDay
        result.searchWeekEndingDay = searchWeekEndingDay; result.searchRangeStartDay = searchRangeStartDay
        result.searchRangeEndDay = searchRangeEndDay; result.searchContext = showSearchContext
        result.dailyScrollID = dailyScrollID; result.searchScrollID = searchScrollID
        result.searchDateAnchor = searchDateAnchor; result.searchSelectedResultID = searchSelectedResultID
        result.searchColumnScrollIDs = searchColumnScrollIDs; result.expandedHours = expandedAutomaticHours
        result.searchColumnViewports = searchColumnViewports; result.weeklyColumnViewports = weeklyColumnViewports
        result.focus = detailFocus; result.focusTarget = navigationFocusTarget
        result.workspace = NavigationWorkspacePresentation(mode: workspace.mode,
            selectedID: workspace.selectedCaptureID, source: workspace.sourceApplication,
            dateFilter: workspace.dateFilter, originFilter: workspace.originFilter,
            snippetsOnly: workspace.snippetsOnly, unfiledOnly: workspace.explorerUnfiledOnly,
            grouping: workspace.explorerGrouping, query: workspace.explorerQuery,
            dailyFiles: workspace.explorerShowsDailyFiles)
        result.workspaceViewport = workspaceViewport; result.todayPlanningScope = todayPlanningScope
        result.projectPresentation = libraryProject.flatMap { projectPresentation[$0] }
        result.returnContext = NavigationReturnContext(origin: origin, attachmentTaskID: attachmentReturnTaskID,
            creation: creationReturnRoute, auxiliary: auxiliaryReturnRoute, search: searchReturnRoute,
            searchFilter: searchReturnFilter, searchCreation: searchReturnCreationRoute,
            searchAuxiliary: searchReturnAuxiliaryRoute, searchCaptureID: searchReturnCaptureID,
            searchDetailID: searchDetailContext?.captureID, searchDetailOrigin: searchDetailContext?.origin ?? .daily,
            searchDetailAttachmentID: searchDetailContext?.attachmentReturnTaskID, searchDetailFocus: searchDetailContext?.focus)
        return result
    }

    private func resolveNavigation(_ snapshot: NavigationSnapshot, live: NavigationLiveIdentities) -> NavigationSnapshot? {
        var next = snapshot
        let captureIDs = live.captureIDs
        let projects = live.projects
        func project(_ name: String?) -> String? {
            guard var name else { return nil }
            var seen = Set<String>()
            while let renamed = projectRenames[name], seen.insert(name).inserted { name = renamed }
            return projects.contains(name) ? name : nil
        }
        func noteKey(_ key: String) -> String {
            guard key.hasPrefix("project:"), let name = project(String(key.dropFirst(8))) else { return key }
            return WorkspaceSnapshot.projectKey(name)
        }
        func itemID(_ id: String) -> String {
            guard id.hasPrefix("note:") else { return id }
            return "note:" + noteKey(String(id.dropFirst(5)))
        }
        func anchor(_ value: NavigationViewportAnchor) -> NavigationViewportAnchor {
            NavigationViewportAnchor(itemID: itemID(value.itemID), offset: value.offset, neighbors: value.neighbors.map(itemID))
        }
        next.project = project(next.project); next.searchProject = project(next.searchProject)
        next.selectedNoteProjectKey = next.selectedNoteProjectKey.map(noteKey)
        next.searchSelectedResultID = next.searchSelectedResultID.map(itemID)
        next.searchColumnScrollIDs = next.searchColumnScrollIDs.mapValues(itemID)
        next.workspaceViewport = next.workspaceViewport.map(anchor)
        next.searchColumnViewports = next.searchColumnViewports.mapValues(anchor)
        next.weeklyColumnViewports = next.weeklyColumnViewports.mapValues(anchor)
        if var presentation = next.projectPresentation {
            presentation.selectedIDs = Set(presentation.selectedIDs.map(itemID))
            presentation.selectionAnchor = presentation.selectionAnchor.map(itemID)
            presentation.focusedID = presentation.focusedID.map(itemID)
            presentation.viewport = presentation.viewport.map(anchor)
            next.projectPresentation = presentation
        }
        if let id = next.selectedCaptureID, !captureIDs.contains(id) {
            if next.route == .detail { return nil }
            next.selectedCaptureID = nil; next.focus = nil
        }
        if let id = next.workspace.selectedID, !captureIDs.contains(id) { next.workspace.selectedID = nil }
        if let id = next.searchScrollID, !captureIDs.contains(id) { next.searchScrollID = nil }
        let presentationIDs = live.presentationIDs
        if let selected = next.searchSelectedResultID, !presentationIDs.contains(selected) { next.searchSelectedResultID = nil }
        next.searchColumnScrollIDs = next.searchColumnScrollIDs.filter { presentationIDs.contains($0.value) }
        next.searchColumnViewports = next.searchColumnViewports.compactMapValues { $0.resolving(against: presentationIDs) }
        next.weeklyColumnViewports = next.weeklyColumnViewports.compactMapValues { $0.resolving(against: presentationIDs) }
        next.workspaceViewport = next.workspaceViewport?.resolving(against: presentationIDs.union(live.todayReceiptIDs))
        if let key = next.selectedNoteProjectKey, !live.noteKeys.contains(key) {
            next.selectedNoteProjectKey = nil
            if next.route == .searchNote { next.route = .search }
        }
        if var presentation = next.projectPresentation {
            let projectIDs = live.projectItemIDs[WorkspaceSnapshot.projectKey(next.project)] ?? []
            presentation.selectedIDs.formIntersection(projectIDs)
            if let id = presentation.selectionAnchor, !projectIDs.contains(id) { presentation.selectionAnchor = nil }
            if let id = presentation.focusedID, !projectIDs.contains(id) { presentation.focusedID = nil }
            presentation.viewport = presentation.viewport?.resolving(against: projectIDs)
            next.projectPresentation = presentation
        }
        return next
    }

    private func restoreNavigation(_ snapshot: NavigationSnapshot) {
        isRestoringNavigation = true
        defer {
            isRestoringNavigation = false
            navigationTransitionRevision &+= 1
            navigationRestorationRevision &+= 1
            onRestoreNavigationFocus?(snapshot.focusTarget)
        }
        libraryProject = snapshot.project; libraryPinnedOnly = snapshot.pinnedOnly
        selectedDay = snapshot.day; weekEndingDay = snapshot.weekEndingDay; customWeeklyDays = snapshot.weeklyDays
        filter = snapshot.filter
        if snapshot.belongsToSearchSession {
            query = snapshot.query; searchProject = snapshot.searchProject
            searchUnfiledOnly = snapshot.searchUnfiledOnly; searchSource = snapshot.searchSource
            searchScope = snapshot.searchScope; searchDay = snapshot.searchDay
            searchWeekEndingDay = snapshot.searchWeekEndingDay; searchRangeStartDay = snapshot.searchRangeStartDay
            searchRangeEndDay = snapshot.searchRangeEndDay; showSearchContext = snapshot.searchContext
            // Restore positions last: refinement observers intentionally clear them.
            searchScrollID = snapshot.searchScrollID
            searchDateAnchor = snapshot.searchDateAnchor; searchSelectedResultID = snapshot.searchSelectedResultID
            searchColumnScrollIDs = snapshot.searchColumnScrollIDs
            searchColumnViewports = snapshot.searchColumnViewports
        }
        dailyScrollID = snapshot.dailyScrollID; expandedAutomaticHours = snapshot.expandedHours
        weeklyColumnViewports = snapshot.weeklyColumnViewports
        workspace.mode = snapshot.workspace.mode; workspace.sourceApplication = snapshot.workspace.source
        workspace.dateFilter = snapshot.workspace.dateFilter; workspace.originFilter = snapshot.workspace.originFilter
        workspace.snippetsOnly = snapshot.workspace.snippetsOnly; workspace.explorerUnfiledOnly = snapshot.workspace.unfiledOnly
        workspace.explorerGrouping = snapshot.workspace.grouping; workspace.explorerQuery = snapshot.workspace.query
        workspace.explorerShowsDailyFiles = snapshot.workspace.dailyFiles
        workspace.selectedCaptureID = snapshot.workspace.selectedID
        workspaceViewport = snapshot.workspaceViewport; todayPlanningScope = snapshot.todayPlanningScope
        if let project = snapshot.project, let presentation = snapshot.projectPresentation { projectPresentation[project] = presentation }
        selectedCapture = snapshot.selectedCaptureID.flatMap { id in store.captures.first { $0.id == id } }
        selectedDraft = selectedCapture.flatMap { drafts[$0.id] }
        selectedSearchNote = snapshot.selectedNoteProjectKey.flatMap { workspace.snapshot.scratchpads[$0] }
        detailFocus = snapshot.focus; navigationFocusTarget = snapshot.focusTarget
        let context = snapshot.returnContext
        origin = context.origin; attachmentReturnTaskID = context.attachmentTaskID
        creationReturnRoute = context.creation; auxiliaryReturnRoute = context.auxiliary
        searchReturnRoute = context.search; searchReturnFilter = context.searchFilter
        searchReturnCreationRoute = context.searchCreation; searchReturnAuxiliaryRoute = context.searchAuxiliary
        searchReturnCaptureID = context.searchCaptureID
        searchDetailContext = context.searchDetailID.map { SearchDetailContext(captureID: $0,
            origin: context.searchDetailOrigin, attachmentReturnTaskID: context.searchDetailAttachmentID,
            focus: context.searchDetailFocus) }
        route = snapshot.route
    }

    func showCaptureDay(_ capture: Capture) {
        guard !isNavigationBlocked else { return }
        beginNavigation(); defer { endNavigation() }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        parser.timeZone = .current
        selectedDay = parser.date(from: capture.captureDay) ?? capture.capturedAt
        filter = .all
        route = .daily
        if capture.captureOrigin.isAutomatic && !capture.isTask {
            let hour = AutomaticHourKey(capture: capture)
            if automaticActionCount(in: hour, on: selectedDay) >= HourlyCaptureFeed.summaryThreshold {
                expandedAutomaticHours.insert(hour)
            }
        }
        dailyScrollID = feedID(for: capture, on: selectedDay)
    }

    func moveDay(_ amount: Int) {
        guard !isNavigationBlocked else { return }
        beginNavigation(); defer { endNavigation() }
        guard let day = Calendar.current.date(byAdding: .day, value: amount, to: selectedDay),
              Calendar.current.startOfDay(for: day) <= Calendar.current.startOfDay(for: Date()) else { return }
        selectedDay = day
        dailyScrollID = nil
    }

    func didCapture(_ captures: [Capture]) {
        guard !captures.isEmpty else { return }
        let days = Set(captures.map(\.captureDay)).sorted()
        status = AppStatusMessage(text: "Saved \(captures.count == 1 ? "capture" : "\(captures.count) captures") · \(days.joined(separator: ", "))", severity: .success)
        previews.process(captures)
        contentIndex?.process(captures)
    }

    func didAutoCapture(_ captures: [Capture]) {
        guard !captures.isEmpty else { return }
        // The passive robot confirms automatic saves. Keep the board calm while
        // still scheduling local previews and publishing the live feed update.
        previews.process(captures)
        contentIndex?.process(captures)
        objectWillChange.send()
        Task { [weak self] in _ = await self?.clipboardRetention.cleanup() }
    }

    func retryContentIndex(_ capture: Capture) {
        contentIndex?.retry(capture)
    }

    func rebuildContentIndex() {
        guard let contentIndex else { return }
        Task {
            if await contentIndex.rebuildAll() {
                status = AppStatusMessage(text: "Rebuilding local text search in the background.", severity: .success)
            } else {
                status = AppStatusMessage(text: "Local text search is already running.", severity: .warning)
            }
        }
    }

    func reportFailure(_ message: String) {
        status = AppStatusMessage(text: message, severity: .error)
    }

    func reportCaptureResult(_ captures: [Capture], errors: [String]) {
        didCapture(captures)
        guard !errors.isEmpty else { return }
        let summary = (captures.isEmpty ? "Couldn’t save this capture. " : "Saved \(captures.count); some items failed. ") + errors.joined(separator: "\n")
        status = AppStatusMessage(text: summary, severity: captures.isEmpty ? .error : .warning)
    }

    /// The task form returns to Daily before macOS resolves notification permission.
    /// Keep failures visible there, even if the user never opens the task detail.
    private func saveReminderAndReport(for capture: Capture) async {
        let revision = capture.reminderRevision
        let desiredDate = capture.reminderAt
        await reminders.saveReminder(for: capture)
        // A permission dialog or scheduling request may finish after a later
        // clear/edit/completion. Only the still-current request may show feedback.
        guard capture.reminderRevision == revision, capture.reminderAt == desiredDate,
              desiredDate != nil, !(capture.isTask && capture.isCompleted),
              store.captures.contains(where: { $0 === capture }) else { return }
        switch capture.notificationState {
        case "scheduled":
            status = AppStatusMessage(text: "Reminder scheduled.", severity: .success, reminderCaptureID: capture.id)
        case "denied", "pending":
            status = AppStatusMessage(text: "Reminder saved. Enable DaBin notifications in System Settings to receive alerts.", severity: .warning, reminderCaptureID: capture.id)
        case "failed":
            status = AppStatusMessage(text: "Reminder saved, but its notification could not be scheduled. Open the capture to retry.", severity: .error, reminderCaptureID: capture.id)
        default: return
        }
        reminderServiceFeedback = (capture.id, reminders.status)
    }

    private func clearReminderFeedback(for capture: Capture) {
        if status?.reminderCaptureID == capture.id { status = nil }
        if let feedback = reminderServiceFeedback, feedback.captureID == capture.id {
            // Do not erase service feedback that a newer operation replaced.
            if reminders.status == feedback.message { reminders.status = nil }
            reminderServiceFeedback = nil
        }
    }

    func saveDetail() {
        guard let capture = selectedCapture, let draft = selectedDraft else { return }
        saveDetail(capture: capture, draft: draft)
    }

    func saveDetail(capture: Capture, draft: CaptureDraft) {
        guard store.captures.contains(where: { $0 === capture }) else {
            draft.message = "This capture is no longer available."
            draft.hasError = true
            return
        }
        var committedPlanning = draft.planning
        if capture.isTask {
            let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty || title.count > 2_000 {
                draft.validationIssue = .title
                draft.message = "Use a task title of 1–2,000 characters."
                draft.hasError = true
                return
            }
            do { committedPlanning = try ChecklistDraftPolicy.committing(draft.pendingChecklistText, to: draft.planning) }
            catch { draft.validationIssue = .planning; draft.message = error.localizedDescription; draft.hasError = true; return }
            guard committedPlanning.isValid else {
                draft.validationIssue = .planning
                draft.message = "Check the task dates, estimate, and checklist before saving."
                draft.hasError = true
                return
            }
        }
        let resolvedReminder: Date?
        do { resolvedReminder = draft.reminderChanged ? try draft.resolvedReminder() : draft.reminder }
        catch { draft.validationIssue = .reminder; draft.message = error.localizedDescription; draft.hasError = true; return }
        if draft.reminderChanged, let reminder = resolvedReminder, reminder <= Date() {
            draft.validationIssue = .reminder
            draft.message = "Choose a reminder time in the future."
            draft.hasError = true
            return
        }
        draft.validationIssue = nil
        let changedReminder = draft.reminderChanged
        do {
            try store.update(capture, comment: draft.comment, reminderAt: resolvedReminder,
                             reminderTimeZoneID: resolvedReminder == nil ? nil : (changedReminder ? TimeZone.current.identifier : capture.reminderTimeZoneID),
                             planning: capture.isTask ? committedPlanning : nil, title: capture.isTask ? draft.title : nil)
            draft.adoptSavedReminder(from: capture)
            draft.title = capture.title
            if capture.isTask {
                draft.planning = committedPlanning
                draft.pendingChecklistText = ""
            }
            draft.adoptSavedPlanning(from: capture)
            draft.didSave()
            if changedReminder {
                if capture.reminderAt == nil { clearReminderFeedback(for: capture) }
                Task {
                    if capture.reminderAt == nil { await reminders.clearForCapture(capture.id) }
                    else { await saveReminderAndReport(for: capture) }
                }
            }
        } catch {
            draft.message = "Could not save changes: \(error.localizedDescription)"
            draft.hasError = true
        }
    }

    func openOriginal(_ capture: Capture) {
        let url: URL?
        if let original = capture.originalURL, let parsed = URL(string: original),
           ["https", "http"].contains(parsed.scheme?.lowercased() ?? "") {
            url = parsed
        } else {
            url = store.managedURL(for: capture)
            if let file = url, !FileManager.default.fileExists(atPath: file.path) {
                reportFailure("The saved original is missing. Its capture and annotations are still available.")
                return
            }
        }
        guard let url else { reportFailure("No original file or link is available for this capture."); return }
        if !NSWorkspace.shared.open(url) { reportFailure("macOS could not open this original. Choose a compatible application in Finder.") }
    }

    func showArchiveFolder(for capture: Capture? = nil) {
        do {
            let folder = try store.localArchiveFolderURL(for: capture)
            if !folderOpener(folder) { reportFailure("macOS could not open the local archive folder.") }
        } catch { reportFailure("Could not open the local archive: \(error.localizedDescription)") }
    }

    func showProjectFiles() {
        do {
            let folder = libraryProject == nil && !workspace.explorerUnfiledOnly
                ? try store.localArchiveFolderURL() : try store.explorerFolderURL(project: libraryProject)
            if !folderOpener(folder) { reportFailure("Finder couldn’t open this project folder.") }
        } catch { reportFailure("Could not open project files: \(error.localizedDescription)") }
    }

    func retryReminder(_ capture: Capture) {
        Task { await saveReminderAndReport(for: capture) }
    }

    func setLinkPreviews(_ enabled: Bool) {
        previews.enabled = enabled
        if enabled { previews.process(store.captures.filter { $0.kind == .link && !$0.captureOrigin.isAutomatic }) }
        else { previews.cancelNetwork() }
        objectWillChange.send()
    }

    func feedID(for capture: Capture, on day: Date) -> CaptureFeedCardID {
        HourlyCaptureFeed.cards(from: allCaptures(for: day), filter: .all)
            .first { $0.captures.contains(where: { $0.id == capture.id }) }?.id
            ?? .capture(.capture(capture.id))
    }

    private func automaticActionCount(in hour: AutomaticHourKey, on day: Date) -> Int {
        Set(allCaptures(for: day).filter {
            $0.captureOrigin.isAutomatic && AutomaticHourKey(capture: $0) == hour
        }.map { $0.automaticActionID ?? $0.id }).count
    }
}
