import AppKit
import Foundation
import Combine

/// The application's composition root. One session owns the archive, services,
/// state, native panels and event observers; SwiftUI views never create storage.
@MainActor
final class ApplicationCoordinator {
    let store: CaptureStore
    let previews: PreviewService
    let contentIndex: ContentIndexService
    let reminders: ReminderService
    let updates: SoftwareUpdateService
    let input: InputService
    let autoCapture: AutoCaptureService
    let autoCaptureRobot: AutoCaptureRobotPresenter
    let taskTimerRobot: TaskTimerRobotPresenter
    let state: AppState
    let theme: ThemeSettings
    let robotPlacement: RobotPlacementSettings
    let corners: CornerController
    let commands: ApplicationMenu
    let statusBar: StatusBarController
    let shortcuts: GlobalShortcutService
    private var quietSubscription: AnyCancellable?
    private var startupDerivativeTask: Task<Void, Never>?
    private(set) var pendingStartupDerivativeCount = 0
    private let lifecycle: ReminderLifecycle
    private let applicationEvents: NotificationCenter
    private let workspaceEvents: NotificationCenter
    private let defaults: UserDefaults
    private(set) var isStarted = false
    private(set) var isStopped = false
    nonisolated static let firstLaunchDailyPresentedKey = "DaBin.launch.didPresentDaily.v1"

    convenience init() throws {
        try self.init(store: CaptureStore(repairArchiveOnOpen: false))
    }

    init(store: CaptureStore, defaults: UserDefaults = .standard,
         notificationClient: ReminderNotificationClient? = nil,
         applicationEvents: NotificationCenter = .default,
         workspaceEvents: NotificationCenter = NSWorkspace.shared.notificationCenter,
         taskTimerPrimaryScreen: @escaping TaskTimerRobotPresenter.PrimaryScreenProvider = { AutoCaptureRobotGeometry.livePrimaryScreen() }) {
        self.store = store
        self.defaults = defaults
        self.applicationEvents = applicationEvents
        self.workspaceEvents = workspaceEvents
        let previews = PreviewService(store: store, defaults: defaults)
        let contentIndex = ContentIndexService(store: store)
        let reminders = notificationClient.map { ReminderService(store: store, client: $0) }
            ?? ReminderService(store: store)
        let updates = SoftwareUpdateService()
        let input = InputService(store: store)
        let autoInput = InputService(store: store)
        let autoCaptureSettings = AutoCaptureSettings(defaults: defaults)
        let autoCapture = AutoCaptureService(settings: autoCaptureSettings, input: autoInput)
        let autoCaptureRobot = AutoCaptureRobotPresenter()
        let robotPlacement = RobotPlacementSettings(defaults: defaults)
        let quickAccess = QuickAccessSettings(defaults: defaults)
        let taskTimerRobot = TaskTimerRobotPresenter(primaryScreen: taskTimerPrimaryScreen,
            reduceMotion: { [weak quickAccess] in
                quickAccess?.quietMode == true || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            })
        let state = AppState(store: store, previews: previews, contentIndex: contentIndex, reminders: reminders,
                             updates: updates, robotPlacement: robotPlacement,
                             autoCapture: autoCapture, quickAccessSettings: quickAccess)
        autoCapture.projectProvider = { [weak state] in
            state?.libraryProject
        }
        let theme = ThemeSettings(defaults: defaults)
        let corners = CornerController(state: state, input: input, placementDefaults: defaults, theme: theme)
        self.previews = previews
        self.contentIndex = contentIndex
        self.reminders = reminders
        self.updates = updates
        self.input = input
        self.autoCapture = autoCapture
        self.autoCaptureRobot = autoCaptureRobot
        self.taskTimerRobot = taskTimerRobot
        self.state = state
        self.theme = theme
        self.robotPlacement = robotPlacement
        self.corners = corners
        autoCaptureRobot.setProjectRecordingActive(false)
        corners.onProjectRecordingChanged = { [weak taskTimerRobot, weak autoCaptureRobot] project, paused in
            taskTimerRobot?.content.setProjectRecording(projectName: project, isPaused: paused)
            autoCaptureRobot?.setProjectRecordingActive(project != nil && !paused)
        }
        state.onTaskCompleted = { [weak corners] in corners?.celebrateTaskCompletion() }
        state.onTaskTimerExpired = { [weak taskTimerRobot] captures in
            for capture in captures {
                _ = taskTimerRobot?.present(task: TaskTimerCompletion(taskID: capture.id, title: capture.title))
            }
        }
        state.onToggleExpandedWindow = { [weak corners] in corners?.toggleExpandedWindow() }
        lifecycle = ReminderLifecycle { await reminders.reconcile() }
        corners.onWillOpenBoard = { [weak autoCaptureRobot] in autoCaptureRobot?.suspendForBoard() }
        corners.onDidCloseBoard = { [weak autoCaptureRobot] in autoCaptureRobot?.resumeAfterBoard() }
        autoCaptureRobot.onPresentationChanged = { [weak corners] visible in
            if visible { corners?.captureAnimationWillAppear() }
            else { corners?.refreshProjectRecording() }
        }
        corners.onRobotInteractionBegan = { [weak autoCaptureRobot, weak taskTimerRobot] in
            autoCaptureRobot?.suspendForInteraction()
            taskTimerRobot?.suspendForInteraction()
        }
        corners.onRobotInteractionEnded = { [weak autoCaptureRobot, weak taskTimerRobot] in
            taskTimerRobot?.resumeAfterInteraction()
            autoCaptureRobot?.resumeAfterInteraction()
        }
        corners.isCaptureRobotVisible = { [weak autoCaptureRobot] in autoCaptureRobot?.panel.isVisible == true }
        corners.isTaskTimerRobotVisible = { [weak taskTimerRobot] in taskTimerRobot?.panel.isVisible == true }
        taskTimerRobot.onPresentationChanged = { [weak autoCaptureRobot, weak corners] visible in
            if visible {
                autoCaptureRobot?.suspendForTaskTimer()
                corners?.captureAnimationWillAppear()
            } else {
                autoCaptureRobot?.resumeAfterTaskTimer()
                corners?.refreshProjectRecording()
            }
        }
        autoCapture.onCommitted = { [weak state] action in
            state?.didAutoCapture(action.captures)
        }
        autoCapture.onSaved = { [weak autoCaptureRobot, weak quickAccess,
                                 weak corners,
                                 weak workspace = state.workspace] action in
            // One receipt is one action, including a grouped multi-file paste.
            guard quickAccess?.quietMode != true else { return }
            // The held destination board owns project recording sessions. A
            // temporary receipt must not dismiss it or replace its live label.
            if corners?.hasPersistentProjectRecording == true {
                if corners?.bin.isVisible == true { corners?.robot.digest(success: true) }
                if let project = action.projectName { AccessibilityAnnouncement.post("Saved to \(project)") }
                return
            }
            let projectColor = action.projectName
                .flatMap { workspace?.projectColorHex(for: $0) }
                .map { ProjectColorChoice.nsColor(for: $0) }
            _ = autoCaptureRobot?.present(additionalCaptureCount: 1,
                                          projectName: action.projectName,
                                          projectColor: projectColor)
            if let project = action.projectName {
                AccessibilityAnnouncement.post("Saved to \(project)")
            }
        }
        autoCapture.onFailure = { [weak state] message in
            state?.status = AppStatusMessage(text: "Auto Capture: \(message)", severity: .warning)
        }
        commands = ApplicationMenu(
            openDaily: { [weak corners] in corners?.openDaily() },
            openSearch: { [weak corners] in corners?.openSearch() },
            focusRobot: { [weak corners] in corners?.focusRobot() },
            checkForUpdates: { [weak state, weak corners] in
                state?.showSettings()
                corners?.showBoard()
                state?.updates.checkForUpdates()
            },
            showSettings: { [weak state, weak corners] in state?.showSettings(); corners?.showBoard() },
            autoCapture: autoCapture
        )
        statusBar = StatusBarController(
            openDaily: { [weak corners] in corners?.openDaily() },
            showSettings: { [weak state, weak corners] in state?.showSettings(); corners?.showBoard() },
            quit: { NSApplication.shared.terminate(nil) },
            autoCapture: autoCapture,
            theme: theme
        )
        shortcuts = GlobalShortcutService(settings: quickAccess,
            search: { [weak corners] in corners?.openSearch() },
            capture: { [weak state, weak corners] in
                state?.openDaily()
                corners?.showBoard(immediate: true)
                state?.pasteClipboard()
            })
        quietSubscription = quickAccess.$quietMode.sink { [weak autoCaptureRobot, weak taskTimerRobot] quiet in
            if quiet {
                autoCaptureRobot?.dismiss()
                taskTimerRobot?.refreshMotionPreference()
            }
        }
    }

    /// Returns true once for this preference domain. AppDelegate uses the result
    /// to make a normal first launch discoverable; subsequent launches retain
    /// DaBin's quiet, corner-only behavior after the board is dismissed.
    func claimFirstLaunchDailyPresentation() -> Bool {
        guard !defaults.bool(forKey: Self.firstLaunchDailyPresentedKey) else { return false }
        defaults.set(true, forKey: Self.firstLaunchDailyPresentedKey)
        return true
    }

    func start(showDaily: Bool = false, installMenu: Bool = true, installStatusItem: Bool = true,
               pointerPosition: @escaping () -> NSPoint = { NSEvent.mouseLocation }) {
        guard !isStarted, !isStopped else { return }
        isStarted = true
        if installMenu { commands.install(); shortcuts.start() }
        if installStatusItem { statusBar.install() }
        corners.start(pointerPosition: pointerPosition)
        autoCapture.start()
        lifecycle.start(applicationEvents: applicationEvents, workspaceEvents: workspaceEvents)
        if showDaily { corners.openDaily() }
        prepareStartupDerivatives()
        store.startArchiveRepair()
    }

    /// Showing saved metadata does not wait for thousands of derivative checks.
    /// Normal capture/save paths still process their changed records immediately.
    private func prepareStartupDerivatives() {
        let ids = store.captures.map(\.id)
        pendingStartupDerivativeCount = ids.count
        guard !ids.isEmpty else { return }
        startupDerivativeTask = Task { @MainActor [weak self] in
            var offset = 0
            while offset < ids.count {
                do { try await Task.sleep(for: .milliseconds(20)) }
                catch { return }
                guard !Task.isCancelled, let self, self.isStarted, !self.isStopped else { return }
                let end = min(ids.count, offset + 8)
                let batchIDs = Set(ids[offset..<end])
                let current = self.store.captures.filter { batchIDs.contains($0.id) }
                self.previews.process(current)
                self.contentIndex.process(current)
                offset = end
                self.pendingStartupDerivativeCount = ids.count - offset
            }
            self?.startupDerivativeTask = nil
        }
    }

    /// A stopped session cannot reopen UI through stale notification callbacks
    /// or timer events. Scheduled reminders intentionally survive normal quit.
    func shutdown() {
        guard !isStopped else { return }
        isStopped = true
        isStarted = false
        startupDerivativeTask?.cancel()
        startupDerivativeTask = nil
        pendingStartupDerivativeCount = 0
        store.cancelArchiveRepair()
        lifecycle.stop()
        autoCapture.shutdown()
        shortcuts.stop()
        quietSubscription?.cancel(); quietSubscription = nil
        state.onTaskTimerExpired = nil
        state.onTaskCompleted = nil
        state.focusSessions.shutdown()
        state.shutdownNotificationPresentation()
        taskTimerRobot.onPresentationChanged = nil
        taskTimerRobot.shutdown()
        autoCaptureRobot.shutdown()
        corners.shutdown()
        previews.shutdown()
        contentIndex.shutdown()
        updates.cancel()
        commands.uninstall()
        statusBar.uninstall()
    }

    var terminationBlock: String? {
        if state.isArchiveOperationRunning || state.isImporting { return "DaBin is saving your archive. Give it a moment to finish, then quit again." }
        return state.removingCaptureID == nil ? nil : "The capture and its reminder are being updated. Give DaBin a moment to finish, then quit again."
    }
}
