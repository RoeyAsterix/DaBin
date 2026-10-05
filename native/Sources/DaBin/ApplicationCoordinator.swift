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
    let reminderAlerts: ReminderAlertCoordinator
    let extendedView: CaptureExtendedWindowController
    let state: AppState
    let theme: ThemeSettings
    let robotPlacement: RobotPlacementSettings
    let corners: CornerController
    let commands: ApplicationMenu
    let statusBar: StatusBarController
    let shortcuts: GlobalShortcutService
    private var quietSubscription: AnyCancellable?
    private var confirmationSubscription: AnyCancellable?
    private var captureToolObservers: [NSObjectProtocol] = []
    private var startupDerivativeTask: Task<Void, Never>?
    private(set) var pendingStartupDerivativeCount = 0
    private let lifecycle: ReminderLifecycle
    private let applicationEvents: NotificationCenter
    private let workspaceEvents: NotificationCenter
    private let defaults: UserDefaults
    private(set) var isStarted = false
    private(set) var isStopped = false

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
        let theme = ThemeSettings(defaults: defaults)
        let autoCaptureRobot = AutoCaptureRobotPresenter(
            accent: { [weak theme] in ThemeSettings.accentNSColor(for: theme?.selectedHex ?? ThemeSettings.defaultHex) },
            appearance: { [weak theme] in NSAppearance(named: theme?.darkModeEnabled == true ? .darkAqua : .aqua) })
        let robotPlacement = RobotPlacementSettings(defaults: defaults)
        let quickAccess = QuickAccessSettings(defaults: defaults)
        let taskTimerRobot = TaskTimerRobotPresenter(primaryScreen: taskTimerPrimaryScreen,
            reduceMotion: { [weak quickAccess] in
                quickAccess?.quietMode == true || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            })
        let state = AppState(store: store, previews: previews, contentIndex: contentIndex, reminders: reminders,
                             updates: updates, robotPlacement: robotPlacement,
                             autoCapture: autoCapture, quickAccessSettings: quickAccess,
                             workspaceZoom: WorkspaceZoomSettings(defaults: defaults))
        autoCapture.projectProvider = { [weak state] in
            state?.libraryProject
        }
        let corners = CornerController(state: state, input: input, placementDefaults: defaults, theme: theme)
        let reminderAlerts = ReminderAlertCoordinator(store: store)
        let extendedView = CaptureExtendedWindowController(state: state, theme: theme)
        self.reminderAlerts = reminderAlerts
        self.extendedView = extendedView
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
        state.onTaskTimerExpired = { [weak reminderAlerts] _ in reminderAlerts?.reconcile() }
        state.onOpenExtendedCapture = { [weak extendedView] capture, draft in
            extendedView?.show(capture: capture, draft: draft)
        }
        extendedView.onReturn = { [weak corners] in corners?.showBoard(immediate: true) }
        reminderAlerts.onAlertsChanged = { [weak taskTimerRobot] alerts, captureIDs in
            taskTimerRobot?.reconcile(validTaskIDs: captureIDs,
                validReminderReceiptIDs: Set(alerts.filter { $0.reminderRevision != nil }.map(\.id)),
                validFocusReceiptIDs: Set(alerts.filter { $0.reminderRevision == nil }.map(\.id)))
            for alert in alerts { _ = taskTimerRobot?.present(task: alert) }
        }
        taskTimerRobot.onAcknowledge = { [weak store, weak state] receipts in
            guard let store else { return false }
            let reminders = receipts.compactMap { receipt -> CaptureReminderOccurrence? in
                guard let revision = receipt.reminderRevision, let due = receipt.dueAt else { return nil }
                return CaptureReminderOccurrence(captureID: receipt.taskID, revision: revision, dueAt: due)
            }
            let focus = receipts.filter { $0.reminderRevision == nil }.map {
                CaptureFocusOccurrence(captureID: $0.taskID, completionID: $0.id)
            }
            do {
                _ = try store.acknowledgeAlerts(reminders: reminders, focus: focus)
                let remains = store.captures.contains { capture in
                    guard capture.deletedAt == nil, !capture.isTask || !capture.isCompleted else { return false }
                    let reminderPending = capture.reminderOccurrence.map { reminders.contains($0) } == true
                        && !capture.isReminderAcknowledged
                    let focusPending = capture.focusOccurrence.map { focus.contains($0) } == true
                        && capture.taskPlanning?.focusSession?.acknowledgedAt == nil
                    return reminderPending || focusPending
                }
                if remains { state?.reportFailure("The reminder could not be acknowledged yet. It remains available.") }
                return !remains
            } catch {
                state?.reportFailure("Could not acknowledge the reminder. Your alert is still available. \(error.localizedDescription)")
                return false
            }
        }
        taskTimerRobot.onAcknowledged = { [weak state, weak corners, weak extendedView] receipts in
            // The alert itself never activates the app. This follows an explicit click.
            guard let state, !receipts.isEmpty else { return }
            if receipts.count == 1 { state.openCapture(receipts[0].taskID) }
            corners?.showBoard(immediate: true)
            extendedView?.showCompletedReminders(receipts)
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
        autoCapture.onSaved = { [weak autoCaptureRobot, weak quickAccess, weak autoCapture] action in
            // One receipt is one action, including a grouped multi-file paste.
            guard quickAccess?.quietMode != true, let autoCapture,
                  autoCapture.isRunning, autoCapture.settings.isEnabled, !autoCapture.settings.isPaused,
                  let confirmation = AutoCaptureSignReceipt(savedAction: action) else { return }
            autoCaptureRobot?.setScreenCaptureInProgress(AutoCaptureScreenshotActivity.isSystemCaptureTool(
                NSWorkspace.shared.frontmostApplication?.bundleIdentifier))
            _ = autoCaptureRobot?.present(confirmation: confirmation)
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
            autoCapture: autoCapture, workspaceZoom: state.workspaceZoom
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
        confirmationSubscription = Publishers.CombineLatest4(autoCaptureSettings.$isEnabled,
            autoCaptureSettings.$isPaused, autoCapture.$isRunning, quickAccess.$quietMode)
            .sink { [weak autoCaptureRobot] enabled, paused, running, quiet in
                autoCaptureRobot?.setConfirmationEnabled(enabled && running && !paused && !quiet)
            }
    }

    /// Returns true once for this preference domain. AppDelegate uses the result
    /// to make a normal first launch discoverable; subsequent launches retain
    /// DaBin's quiet, corner-only behavior after the board is dismissed.
    func start(showDaily: Bool = false, installMenu: Bool = true, installStatusItem: Bool = true,
               pointerPosition: @escaping () -> NSPoint = { NSEvent.mouseLocation }) {
        guard !isStarted, !isStopped else { return }
        isStarted = true
        if installMenu { commands.install(); shortcuts.start() }
        if installStatusItem { statusBar.install() }
        corners.start(pointerPosition: pointerPosition)
        autoCapture.start()
        installCaptureToolObservers()
        lifecycle.start(applicationEvents: applicationEvents, workspaceEvents: workspaceEvents)
        reminderAlerts.start(applicationEvents: applicationEvents, workspaceEvents: workspaceEvents)
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
        reminderAlerts.stop()
        state.onOpenExtendedCapture = nil
        extendedView.shutdown()
        autoCapture.shutdown()
        shortcuts.stop()
        quietSubscription?.cancel(); quietSubscription = nil
        confirmationSubscription?.cancel(); confirmationSubscription = nil
        for observer in captureToolObservers { workspaceEvents.removeObserver(observer) }
        captureToolObservers.removeAll()
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

    private func installCaptureToolObservers() {
        guard captureToolObservers.isEmpty else { return }
        autoCaptureRobot.setScreenCaptureInProgress(AutoCaptureScreenshotActivity.isSystemCaptureTool(
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier))
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            let observer = workspaceEvents.addObserver(forName: name, object: nil, queue: .main) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self, !self.isStopped,
                          let app = event.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                    let isTool = AutoCaptureScreenshotActivity.isSystemCaptureTool(app.bundleIdentifier)
                    if name == NSWorkspace.didActivateApplicationNotification {
                        self.autoCaptureRobot.setScreenCaptureInProgress(isTool)
                    } else if isTool {
                        self.autoCaptureRobot.setScreenCaptureInProgress(name != NSWorkspace.didTerminateApplicationNotification)
                    }
                }
            }
            captureToolObservers.append(observer)
        }
    }
}
