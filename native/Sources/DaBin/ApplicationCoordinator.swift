import AppKit
import Foundation

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
    let state: AppState
    let theme: ThemeSettings
    let robotPlacement: RobotPlacementSettings
    let corners: CornerController
    let commands: ApplicationMenu
    private let lifecycle: ReminderLifecycle
    private let applicationEvents: NotificationCenter
    private let workspaceEvents: NotificationCenter
    private(set) var isStarted = false
    private(set) var isStopped = false

    convenience init() throws {
        try self.init(store: CaptureStore())
    }

    init(store: CaptureStore, defaults: UserDefaults = .standard,
         notificationClient: ReminderNotificationClient? = nil,
         applicationEvents: NotificationCenter = .default,
         workspaceEvents: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        self.store = store
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
        let state = AppState(store: store, previews: previews, contentIndex: contentIndex, reminders: reminders,
                             updates: updates, robotPlacement: robotPlacement,
                             autoCapture: autoCapture)
        let theme = ThemeSettings(defaults: defaults)
        let corners = CornerController(state: state, input: input, placementDefaults: defaults, theme: theme)
        self.previews = previews
        self.contentIndex = contentIndex
        self.reminders = reminders
        self.updates = updates
        self.input = input
        self.autoCapture = autoCapture
        self.autoCaptureRobot = autoCaptureRobot
        self.state = state
        self.theme = theme
        self.robotPlacement = robotPlacement
        self.corners = corners
        lifecycle = ReminderLifecycle { await reminders.reconcile() }
        autoCapture.onCommitted = { [weak state] action in
            state?.didAutoCapture(action.captures)
        }
        autoCapture.onSaved = { [weak autoCaptureRobot] _ in
            _ = autoCaptureRobot?.present(additionalCaptureCount: 1)
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
    }

    func start(showDaily: Bool = false, installMenu: Bool = true,
               pointerPosition: @escaping () -> NSPoint = { NSEvent.mouseLocation }) {
        guard !isStarted, !isStopped else { return }
        isStarted = true
        if installMenu { commands.install() }
        corners.start(pointerPosition: pointerPosition)
        autoCapture.start()
        lifecycle.start(applicationEvents: applicationEvents, workspaceEvents: workspaceEvents)
        previews.process(store.captures)
        contentIndex.process(store.captures)
        if showDaily { corners.openDaily() }
    }

    /// A stopped session cannot reopen UI through stale notification callbacks
    /// or timer events. Scheduled reminders intentionally survive normal quit.
    func shutdown() {
        guard !isStopped else { return }
        isStopped = true
        isStarted = false
        lifecycle.stop()
        autoCapture.shutdown()
        autoCaptureRobot.shutdown()
        corners.shutdown()
        previews.shutdown()
        contentIndex.shutdown()
        updates.cancel()
        commands.uninstall()
    }

    var terminationBlock: String? {
        state.removingCaptureID == nil ? nil : "The capture and its reminder are being removed. Give DaBin a moment to finish, then quit again."
    }
}
