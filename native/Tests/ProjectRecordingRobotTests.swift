import AppKit
import Foundation

@MainActor private final class ProjectRecordingFixtureNotifications: ReminderNotificationClient {
    private(set) var permissionRequests = 0
    func authorization() async -> ReminderAuthorization { .undetermined }
    func requestAuthorization() async throws -> Bool { permissionRequests += 1; return false }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}

@MainActor private final class ProjectRecordingFixtureScreenshotMonitor: ScreenshotFolderMonitoring {
    var sourceApplicationAtDirectoryActivity: (() -> AutoCaptureSourceApplication?)?
    var projectAtDirectoryActivity: (() -> String?)?
    var onNewScreenshot: ((URL, AutoCaptureSourceApplication?, String?) -> Void)?
    var onFailure: ((Error) -> Void)?
    private(set) var isRunning = false
    func start() throws { isRunning = true }
    func stop() { isRunning = false }
}

/// Real native panels with a fictional, empty archive, isolated preferences and
/// a private pasteboard. A brief runtime check observes only that empty private
/// pasteboard. No general clipboard, permissions or notifications are used.
@main @MainActor private final class ProjectRecordingRobotTests: NSObject, NSApplicationDelegate {
    private static var checks = 0
    private var result: Int32 = 0

    static func main() {
        let application = NSApplication.shared
        let delegate = ProjectRecordingRobotTests()
        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
        exit(delegate.result)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do { try await Self.runChecks() }
            catch {
                result = 1
                fputs("Project recording robot QA failed: \(error)\n", stderr)
            }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard condition() else {
            throw NSError(domain: "ProjectRecordingRobotTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private static func settle() async {
        // Preferences and selected destinations are observed after their
        // published will-set notifications have finished on the main run loop.
        try? await Task.sleep(for: .milliseconds(160))
    }

    private static func runChecks() async throws {
        guard let screen = NSScreen.screens.first else {
            throw NSError(domain: "ProjectRecordingRobotTests", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "An unlocked display is required"])
        }
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("DaBinProjectRecording-\(UUID().uuidString)")
        let suite = "DaBinProjectRecording.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let board = NSPasteboard(name: NSPasteboard.Name("DaBinProjectRecording.\(UUID().uuidString)"))
        let store = try CaptureStore(root: fixtureRoot)
        let settings = AutoCaptureSettings(defaults: defaults)
        let autoInput = InputService(store: store)
        let healthySource = AutoCaptureSourceApplication(name: "Fictional Editor", bundleIdentifier: "example.dabin.fixture-editor")
        var source = healthySource
        var staleBookmark = false
        let screenshotMonitor = ProjectRecordingFixtureScreenshotMonitor()
        let service = AutoCaptureService(settings: settings, input: autoInput,
            pasteboardProvider: { board }, sourceApplicationProvider: { source },
            screenshotMonitorFactory: { _ in screenshotMonitor },
            bookmarkCreator: { _ in Data([0x42]) },
            bookmarkResolver: { _ in (fixtureRoot.appendingPathComponent("Fictional Screenshots"), staleBookmark) },
            pollInterval: 60)
        let previews = PreviewService(store: store, defaults: defaults)
        let notifications = ProjectRecordingFixtureNotifications()
        let reminders = ReminderService(store: store, client: notifications)
        let quickAccess = QuickAccessSettings(defaults: defaults)
        let placement = RobotPlacementSettings(defaults: defaults)
        placement.setHome(.cameraIsland)
        let state = AppState(store: store, previews: previews, reminders: reminders,
            robotPlacement: placement, autoCapture: service, quickAccessSettings: quickAccess)
        let theme = ThemeSettings(defaults: defaults, systemDarkMode: false)
        let controller = CornerController(state: state, input: InputService(store: store),
            placementDefaults: defaults, theme: theme, animateRobotTransitions: false,
            robotReduceMotion: { true })
        let timerRobot = TaskTimerRobotView(frame: CGRect(origin: .zero, size: TaskTimerRobotView.stageSize),
                                           reduceMotion: { true })
        controller.onProjectRecordingChanged = { project, paused in
            timerRobot.setProjectRecording(projectName: project, isPaused: paused)
        }
        defer {
            controller.shutdown()
            service.shutdown()
            previews.shutdown()
            state.focusSessions.shutdown()
            state.shutdownNotificationPresentation()
            board.releaseGlobally()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: fixtureRoot)
        }

        let away = NSPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY)
        controller.start(pointerPosition: { away })
        await settle()
        try expect(!controller.hasPersistentProjectRecording && !controller.bin.isVisible,
                   "An off capture preference does not reveal a recording robot")
        try expect(!controller.robot.recordingSignIsVisible && !controller.appFrame.recordingSignIsVisible,
                   "Both native surfaces start without a recording sign")

        try state.workspace.createProject(name: "Fictional Atlas", colorHex: "318C9C")
        state.libraryProject = "Fictional Atlas"
        // A saved channel choice can exist before launch starts its service.
        settings.setClipboardEnabled(true)
        service.shutdown()
        await settle()
        try expect(settings.isEnabled && settings.status == .ready && !service.isRunning,
                   "The selected channel remains ready before its runtime starts")
        try expect(!controller.hasPersistentProjectRecording && !controller.bin.isVisible
                   && !controller.robot.recordingSignIsVisible && !controller.appFrame.recordingSignIsVisible
                   && timerRobot.recordingProjectName == nil,
                   "An enabled preference without an active runtime never displays a recording sign")
        try expect(state.libraryProject == "Fictional Atlas",
                   "Suppressing a ready sign retains the selected project preference")

        service.setEnabled(true)
        await settle()
        try expect(controller.hasPersistentProjectRecording && controller.bin.isVisible,
                   "A selected project and active monitoring reveal a persistent robot without a save")
        try expect(controller.robot.recordingSignIsVisible
                   && controller.robot.recordingProjectName == "Fictional Atlas",
                   "The ordinary robot displays the current capture destination")
        try expect(controller.robot.recordingSignFontSize == 12,
                   "The project name uses the requested twelve-point font")
        try expect(!controller.robot.recordingSignFrame.isEmpty
                   && controller.robot.bounds.contains(controller.robot.recordingSignFrame),
                   "The held sign has usable bounds within the robot's native stage")
        try expect(service.isRunning && settings.status == .monitoring
                   && controller.robot.recordingStatusLabel == "Capturing to"
                   && timerRobot.recordingProjectName == "Fictional Atlas",
                   "The injected private-pasteboard runtime activates the capturing label")
        service.shutdown()
        await settle()
        try expect(!service.isRunning && settings.status == .ready
                   && !controller.hasPersistentProjectRecording
                   && !controller.robot.recordingSignIsVisible && !controller.appFrame.recordingSignIsVisible
                   && timerRobot.recordingProjectName == nil && state.libraryProject == "Fictional Atlas",
                   "Stopping monitoring hides every project sign while retaining the destination")
        service.setEnabled(true)
        await settle()

        source = AutoCaptureSourceApplication(name: "Fictional Password Manager", bundleIdentifier: "com.bitwarden.desktop")
        try expect(settings.isExcluded(bundleIdentifier: source.bundleIdentifier), "The privacy fixture uses an excluded source")
        service.applicationDidActivate(source)
        await settle()
        try expect(service.isRunning && settings.status == .sourceApplicationExcluded("Fictional Password Manager")
                   && !controller.hasPersistentProjectRecording
                   && !controller.robot.recordingSignIsVisible && !controller.appFrame.recordingSignIsVisible
                   && timerRobot.recordingProjectName == nil,
                   "An excluded source hides project signs even while the monitor runtime is running")
        source = healthySource
        service.applicationDidActivate(source)
        await settle()
        try expect(settings.status == .monitoring && controller.robot.recordingSignIsVisible
                   && controller.robot.recordingProjectName == "Fictional Atlas",
                   "Returning to an allowed source restores the existing project sign")

        service.setClipboardEnabled(false)
        service.setScreenshotsEnabled(true)
        await settle()
        try expect(!service.isRunning && settings.status == .permissionRequired
                   && !controller.hasPersistentProjectRecording
                   && !controller.robot.recordingSignIsVisible && !controller.appFrame.recordingSignIsVisible,
                   "Screenshot-only monitoring without folder access has no recording sign")
        service.setClipboardEnabled(true)
        await settle()
        try expect(service.isClipboardRunning && !service.isScreenshotsRunning
                   && service.screenshotStatus == .permissionRequired && settings.status == .monitoring
                   && controller.robot.recordingSignIsVisible,
                   "A healthy clipboard channel keeps the sign while screenshots await access")
        service.setClipboardEnabled(false)
        staleBookmark = true
        try service.authorizeScreenshotFolder(fixtureRoot.appendingPathComponent("Fictional Screenshots"))
        await settle()
        try expect(!service.isRunning && settings.status == .permissionRevoked
                   && !controller.hasPersistentProjectRecording
                   && !controller.robot.recordingSignIsVisible && !controller.appFrame.recordingSignIsVisible
                   && timerRobot.recordingProjectName == nil && state.libraryProject == "Fictional Atlas",
                   "Revoked screenshot-only access hides all signs and retains the selected project")
        service.setClipboardEnabled(true)
        await settle()
        try expect(service.isClipboardRunning && !service.isScreenshotsRunning
                   && service.screenshotStatus == .permissionRevoked && settings.status == .monitoring
                   && controller.robot.recordingSignIsVisible,
                   "Clipboard monitoring remains visibly active when screenshot access was revoked")
        service.removeScreenshotFolderAuthorization()
        service.setScreenshotsEnabled(false)
        await settle()

        controller.pollPointer(at: away, now: Date().addingTimeInterval(5), pressedMouseButtons: 0)
        await settle()
        try expect(controller.bin.isVisible && controller.robot.recordingSignIsVisible,
                   "Moving away beyond the ordinary retreat grace keeps the destination visible")
        try expect(!controller.bin.isKeyWindow,
                   "A passive recording robot does not take keyboard focus")

        try state.workspace.createProject(name: "Fictional Beacon", colorHex: "C06B48")
        state.libraryProject = "Fictional Beacon"
        await settle()
        try expect(controller.robot.recordingProjectName == "Fictional Beacon"
                   && controller.appFrame.recordingProjectName == "Fictional Beacon",
                   "Changing the selected destination updates both surfaces without a new capture")
        service.pause()
        await settle()
        try expect(!service.isRunning && settings.isPaused && settings.status == .paused
                   && !controller.bin.isVisible && !controller.hasPersistentProjectRecording
                   && !controller.robot.recordingSignIsVisible && !controller.appFrame.recordingSignIsVisible
                   && timerRobot.recordingProjectName == nil,
                   "Pausing stops monitoring and removes every recording sign")
        try expect(state.libraryProject == "Fictional Beacon",
                   "Pausing preserves the selected capture destination")
        service.resume()
        await settle()
        try expect(service.isRunning && settings.status == .monitoring
                   && controller.robot.recordingSignIsVisible
                   && controller.robot.recordingProjectName == "Fictional Beacon"
                   && controller.appFrame.recordingProjectName == "Fictional Beacon"
                   && timerRobot.recordingProjectName == "Fictional Beacon",
                   "Resuming restores the same project across every recording surface")

        quickAccess.setQuietMode(true)
        await settle()
        try expect(controller.bin.isVisible && controller.robot.recordingSignIsVisible,
                   "Quiet mode retains the persistent destination instead of suppressing information")
        quickAccess.setQuietMode(false)
        await settle()

        var timerOwnsRobot = true
        controller.isTaskTimerRobotVisible = { timerOwnsRobot }
        controller.refreshProjectRecording()
        await settle()
        try expect(!controller.bin.isVisible,
                   "A task-timer acknowledgement owns the robot without a duplicate recording window")
        timerOwnsRobot = false
        controller.refreshProjectRecording()
        await settle()
        try expect(controller.bin.isVisible && controller.robot.recordingProjectName == "Fictional Beacon",
                   "Acknowledging the timer restores the persistent destination")

        var captureOwnsRobot = true
        controller.isCaptureRobotVisible = { captureOwnsRobot }
        controller.refreshProjectRecording()
        await settle()
        try expect(!controller.bin.isVisible,
                   "A saved-capture performance temporarily owns the robot")
        captureOwnsRobot = false
        controller.refreshProjectRecording()
        await settle()
        try expect(controller.bin.isVisible && controller.robot.recordingSignIsVisible,
                   "Finishing saved-capture feedback restores the persistent sign")

        controller.showBoard(immediate: true)
        await settle()
        try expect(controller.board.isVisible && !controller.bin.isVisible,
                   "Opening the board uses one native surface")
        try expect(controller.appFrame.recordingSignIsVisible
                   && controller.appFrame.recordingProjectName == "Fictional Beacon",
                   "The expanded robot frame retains the current destination")
        try expect(controller.appFrame.recordingSignFontSize == 12,
                   "The expanded frame retains the twelve-point project-name font")
        try expect(!controller.appFrame.recordingSignFrame.isEmpty
                   && !controller.appFrame.recordingSignFrame.intersects(
                    RobotAppFrameView.contentRect(in: controller.appFrame.bounds)),
                   "The expanded sign stays outside the application's content and controls")
        service.pause()
        await settle()
        try expect(controller.board.isVisible && !controller.appFrame.recordingSignIsVisible
                   && !controller.robot.recordingSignIsVisible && timerRobot.recordingProjectName == nil
                   && state.libraryProject == "Fictional Beacon",
                   "Pausing an open workspace hides signs without closing content or clearing its project")
        service.resume()
        await settle()
        try expect(controller.board.isVisible && controller.appFrame.recordingSignIsVisible
                   && controller.appFrame.recordingProjectName == "Fictional Beacon",
                   "Resuming an open workspace restores the compact frame sign")
        let rememberedRoute = state.route
        controller.dismiss()
        await settle()
        try expect(!controller.board.isVisible && controller.bin.isVisible
                   && controller.robot.recordingProjectName == "Fictional Beacon",
                   "Closing the board restores the persistent recording robot")
        try expect(state.route == rememberedRoute && state.libraryProject == "Fictional Beacon",
                   "Recording presentation does not reset navigation or the selected project")

        state.libraryProject = nil
        await settle()
        try expect(!controller.hasPersistentProjectRecording
                   && !controller.robot.recordingSignIsVisible
                   && !controller.appFrame.recordingSignIsVisible,
                   "Unfiled capture has no named-project recording sign")
        state.libraryProject = "Fictional Atlas"
        await settle()
        try expect(controller.bin.isVisible && controller.robot.recordingProjectName == "Fictional Atlas",
                   "Selecting a named project restores the enabled sign")
        service.setEnabled(false)
        await settle()
        try expect(!controller.hasPersistentProjectRecording && !controller.bin.isVisible
                   && !controller.robot.recordingSignIsVisible
                   && !controller.appFrame.recordingSignIsVisible,
                   "Turning Auto Capture off removes the sign and persistent window")
        try expect(!service.isRunning && store.captures.isEmpty && notifications.permissionRequests == 0,
                   "The private monitor is stopped, no content was captured and no permission was requested")

        controller.shutdown()
        service.setClipboardEnabled(true)
        state.libraryProject = "Fictional Beacon"
        await settle()
        try expect(!controller.bin.isVisible && !controller.board.isVisible,
                   "Shutdown subscriptions cannot reveal a stale recording surface")
        print("PASS: \(checks) project recording robot checks passed")
    }
}
