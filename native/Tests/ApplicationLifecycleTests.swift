import AppKit
import Foundation

@MainActor
private final class SessionReminderClient: ReminderNotificationClient {
    var authorizationCalls = 0
    var requests: [String: ScheduledReminder] = [:]
    func authorization() async -> ReminderAuthorization { authorizationCalls += 1; return .allowed }
    func requestAuthorization() async throws -> Bool { fatalError("Lifecycle QA must not ask for real permission") }
    func pending() async -> [ScheduledReminder] { Array(requests.values) }
    func add(_ reminder: ScheduledReminder) async throws { requests[reminder.identifier] = reminder }
    func removePending(_ identifiers: [String]) { identifiers.forEach { requests.removeValue(forKey: $0) } }
    func removeDelivered(_ identifiers: [String]) {}
}

private final class WeakReference<Value: AnyObject> {
    weak var value: Value?
    init(_ value: Value?) { self.value = value }
}

/// Runs the real composition root and native panels without showing a window,
/// reading the user's clipboard, moving the pointer, or taking keyboard focus.
@main
@MainActor
private final class ApplicationLifecycleTests: NSObject, NSApplicationDelegate {
    private var checks = 0
    private var result = 0
    static func main() {
        let app = NSApplication.shared
        let delegate = ApplicationLifecycleTests()
        app.setActivationPolicy(.prohibited)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        exit(Int32(delegate.result))
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await run() }
            catch { result = 1; fputs("Application lifecycle QA failed: \(error)\n", stderr) }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }
    private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard condition() else { throw NSError(domain: "ApplicationLifecycleTests", code: 1,
                                               userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    private func wait(_ message: String, until condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(4)
        while !condition() && Date() < end { try await Task.sleep(for: .milliseconds(10)) }
        try expect(condition(), message)
    }
    private func unwrap<Value>(_ value: Value?, _ message: String) throws -> Value {
        checks += 1
        guard let value else {
            throw NSError(domain: "ApplicationLifecycleTests", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
        return value
    }
    private func hasRedPixels(_ image: NSImage, appearance: NSAppearance.Name) -> Bool {
        var found = false
        NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
            guard let data = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: data) else { return }
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    if color.alphaComponent > 0.5 && color.redComponent > 0.7
                        && color.redComponent - max(color.greenComponent, color.blueComponent) > 0.25 {
                        found = true
                        return
                    }
                }
            }
        }
        return found
    }
    private func run() async throws {
        // Other applications may legitimately become active while this suite
        // runs. Observe this process taking focus instead of requiring the
        // user's foreground application to stay unchanged for the whole run.
        var activatedFixture = NSApp.isActive
        var acquiredKeyWindow = NSApp.keyWindow != nil
        let activation = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: NSApp, queue: .main
        ) { _ in MainActor.assumeIsolated { activatedFixture = true } }
        let keyWindow = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { acquiredKeyWindow = true } }
        defer {
            NotificationCenter.default.removeObserver(activation)
            NotificationCenter.default.removeObserver(keyWindow)
        }
        var reopenRequests = 0
        let appDelegate = AppDelegate { reopenRequests += 1 }
        try expect(!appDelegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: true),
                   "A reopen event is handled without asking AppKit to create another window")
        try expect(!appDelegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false),
                   "A reopen event handles a fully hidden window through the same path")
        try expect(reopenRequests == 2,
                   "Every explicit reopen restores Daily even when AppKit reports a visible panel")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinSessionQA-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "DaBinSessionQA.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = try CaptureStore(root: root)
        let capture = try store.createTask(text: "Fictional reminder survives normal quit", reminderAt: Date().addingTimeInterval(7200))
        let identifier = ReminderService.identifier(capture.id)
        let client = SessionReminderClient()
        let appEvents = NotificationCenter(), workspaceEvents = NotificationCenter()
        var coordinator: ApplicationCoordinator? = ApplicationCoordinator(store: store, defaults: defaults,
            notificationClient: client, applicationEvents: appEvents, workspaceEvents: workspaceEvents)
        let weakCoordinator = WeakReference(coordinator)
        let weakCorners = WeakReference(coordinator?.corners)
        let weakState = WeakReference(coordinator?.state)
        try expect(coordinator?.store === store && coordinator?.input.store === store,
                   "The app has one shared archive across capture and presentation")
        try expect(coordinator?.updates === coordinator?.state.updates,
                   "The app has one shared update service across commands and settings")
        coordinator!.state.libraryProject = "Fictional Atlas"
        try expect(coordinator!.autoCapture.projectProvider() == "Fictional Atlas",
                   "The composition root routes Auto Capture to the project selected in Projects")
        coordinator!.state.workspace.failureInjector = { throw CaptureStoreError.injectedInterruption }
        coordinator!.state.libraryProject = "Live unsaved selection"
        try expect(coordinator!.state.workspace.selectedProject == "Fictional Atlas"
                   && coordinator!.autoCapture.projectProvider() == "Live unsaved selection",
                   "Auto Capture follows the live project shown in the footer even when preference persistence fails")
        coordinator!.state.workspace.failureInjector = nil
        coordinator!.state.libraryProject = nil
        try expect(coordinator!.autoCapture.projectProvider() == nil,
                   "Clearing the selected project returns Auto Capture to Unfiled")
        try expect(coordinator?.isStarted == false && coordinator?.isStopped == false,
                   "Construction does not start observers or pointer monitoring")
        try expect(!coordinator!.corners.board.isVisible && !coordinator!.corners.bin.isVisible,
                   "Construction keeps both native panels hidden")
        coordinator!.theme.select(.teal)
        try expect(ThemeSettings(defaults: defaults).selectedHex == ThemePreset.teal.hex,
                   "The composition root shares injected local preferences with theme state")
        var reads = 0
        coordinator!.start(installMenu: false, installStatusItem: false,
                           pointerPosition: { reads += 1; return NSPoint(x: -100_000, y: -100_000) })
        try await wait("Start reconciles a saved reminder") { client.requests[identifier] != nil }
        try await wait("Pointer timer uses the supplied native boundary") { reads >= 2 }
        try expect(coordinator!.isStarted && !coordinator!.isStopped, "Session enters running state")
        try expect(!coordinator!.corners.board.isVisible && !coordinator!.corners.bin.isVisible,
                   "Idle startup has no visible footprint")
        let initialCalls = client.authorizationCalls
        coordinator!.start(showDaily: true, installMenu: false, pointerPosition: { fatalError("Duplicate startup created a second pointer timer") })
        try await Task.sleep(for: .milliseconds(150))
        try expect(client.authorizationCalls == initialCalls && !coordinator!.corners.board.isVisible,
                   "Repeated startup does not duplicate services or reopen the board")
        appEvents.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        try await wait("Private lifecycle event reaches the app's reminder service") { client.authorizationCalls > initialCalls }
        try expect(coordinator!.terminationBlock == nil, "Normal idle session has no quit block")

        // Exercise native command dispatch while panels remain prohibited from
        // activation. Edit commands stay untargeted for first-responder routing.
        let oldMenu = NSApp.mainMenu
        var daily = 0, settings = 0, updateChecks = 0
        let menu = ApplicationMenu(openDaily: { daily += 1 }, openSearch: {}, focusRobot: {},
                                   checkForUpdates: { updateChecks += 1 }, showSettings: { settings += 1 })
        menu.install()
        let appMenu = NSApp.mainMenu!.items[0].submenu!
        let open = appMenu.items.first { $0.title == "Open DaBin" }!
        let preference = appMenu.items.first { $0.title == "Settings…" }!
        try expect(NSApp.sendAction(open.action!, to: open.target, from: open), "Native Open DaBin command dispatches")
        #if DABIN_DIRECT_UPDATES
        let checkUpdates = appMenu.items.first { $0.title == "Check for Updates…" }!
        try expect(NSApp.sendAction(checkUpdates.action!, to: checkUpdates.target, from: checkUpdates),
                   "Native Check for Updates command dispatches")
        try expect(updateChecks == 1, "Direct-distribution update check invokes its action once")
        #else
        try expect(!appMenu.items.contains { $0.title == "Check for Updates…" } && updateChecks == 0,
                   "Store-managed builds do not expose an update command with no available action")
        #endif
        try expect(NSApp.sendAction(preference.action!, to: preference.target, from: preference), "Native Settings command dispatches")
        try expect(daily == 1 && settings == 1, "Menu commands invoke their intended actions once")
        let edit = NSApp.mainMenu!.items[1].submenu!
        try expect(edit.items.first { $0.title == "Paste" }?.target == nil, "Paste resolves through the native responder chain")
        try expect(appMenu.items.contains { $0.title == "About DaBin" } && appMenu.items.contains { $0.title == "Hide DaBin" },
                   "App menu provides standard macOS About and Hide commands")
        let installed = NSApp.mainMenu
        menu.install()
        try expect(NSApp.mainMenu === installed, "Menu installation is idempotent")
        menu.uninstall()
        NSApp.mainMenu = oldMenu

        var statusDaily = 0, statusSettings = 0, statusQuit = 0
        let statusBar = StatusBarController(
            openDaily: { statusDaily += 1 },
            showSettings: { statusSettings += 1 },
            quit: { statusQuit += 1 },
            autoCapture: coordinator!.autoCapture
        )
        statusBar.install()
        defer { statusBar.uninstall() }
        let statusMenu = try unwrap(statusBar.statusItem?.menu, "Status item installs its native menu")
        try expect(statusBar.statusItem?.isVisible == true && statusBar.presentation.indicator == .off,
                   "The persistent menu bar icon starts visible with Auto Capture off")
        try expect(statusBar.statusMenuItem?.isEnabled == false
                   && statusBar.statusMenuItem?.title == "Auto Capture: Off",
                   "The menu presents a noninteractive Auto Capture status row")
        try expect(statusBar.pauseMenuItem?.isHidden == true,
                   "Pause and Resume stay absent while Auto Capture is disabled")
        let ready = StatusBarController.Presentation.make(enabled: true, paused: false, status: .ready)
        try expect(ready.indicator == .ready && ready.statusTitle == "Auto Capture: Ready to start"
                   && ready.indicator.symbolName != statusBar.presentation.indicator.symbolName,
                   "Ready is visually distinct from Off and does not claim that monitoring is running")
        let recording = StatusBarController.Presentation.make(enabled: true, paused: false, status: .monitoring)
        try expect(recording.indicator == .recording && recording.accessibilityValue == "Recording"
                   && recording.indicator.symbolName != ready.indicator.symbolName,
                   "A running monitor has a dedicated recording symbol and an explicit accessible label")
        let excluded = StatusBarController.Presentation.make(enabled: true, paused: false,
                                                             status: .sourceApplicationExcluded("Fictional Passwords"))
        try expect(excluded.indicator == .recording && excluded.accessibilityValue == "Recording · skipping Fictional Passwords",
                   "Excluding the active application does not conceal the ongoing monitor")
        for indicator in [StatusBarController.Indicator.off, .ready, .paused, .attention] {
            try expect(indicator.image()?.isTemplate == true,
                       "Inactive, waiting and attention symbols keep the system's menu-bar appearance")
        }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let image = try unwrap(StatusBarController.Indicator.recording.image(), "The native recording symbol is available")
            try expect(!image.isTemplate && hasRedPixels(image, appearance: appearance),
                       "Recording remains visibly red in both menu-bar appearances, without relying on hover or motion")
        }
        let partialSuite = "DaBinPartialMonitorQA.\(UUID())"
        let partialDefaults = UserDefaults(suiteName: partialSuite)!
        defer { partialDefaults.removePersistentDomain(forName: partialSuite) }
        let partialSettings = AutoCaptureSettings(defaults: partialDefaults)
        partialSettings.setClipboardEnabled(true)
        partialSettings.setScreenshotsEnabled(true)
        partialSettings.setScreenshotFolderBookmark(Data([1]))
        let partialPasteboard = NSPasteboard(name: .init("DaBinPartialMonitorQA.\(UUID())"))
        defer { partialPasteboard.releaseGlobally() }
        let partialMonitor = AutoCaptureService(settings: partialSettings, input: InputService(store: store),
            pasteboardProvider: { partialPasteboard }, sourceApplicationProvider: { nil },
            bookmarkResolver: { _ in (url: root, isStale: true) })
        defer { partialMonitor.shutdown() }
        partialMonitor.start()
        try expect(partialMonitor.isClipboardRunning && !partialMonitor.isScreenshotsRunning
                   && partialMonitor.screenshotStatus == .permissionRevoked
                   && StatusBarController.Presentation.make(enabled: partialSettings.isEnabled,
                        paused: partialSettings.isPaused, status: partialSettings.status).indicator == .recording,
                   "Revoked screenshot permission never hides recording while the actual clipboard channel remains active")
        partialSettings.setScreenshotFolderBookmark(nil)
        partialMonitor.start()
        try expect(partialMonitor.isClipboardRunning && partialMonitor.screenshotStatus == .permissionRequired
                   && StatusBarController.Presentation.make(enabled: partialSettings.isEnabled,
                        paused: partialSettings.isPaused, status: partialSettings.status).indicator == .recording,
                   "A screenshot channel waiting for a folder also retains the active clipboard recording indication")
        try expect(statusMenu.items.map(\.title).contains("Open DaBin")
                   && statusMenu.items.map(\.title).contains("Settings…")
                   && statusMenu.items.map(\.title).contains("Quit DaBin"),
                   "The status menu exposes Daily, Settings and complete Quit actions")
        let statusOpen = statusMenu.items.first { $0.title == "Open DaBin" }!
        let statusSettingsItem = statusMenu.items.first { $0.title == "Settings…" }!
        let statusQuitItem = statusMenu.items.first { $0.title == "Quit DaBin" }!
        try expect(NSApp.sendAction(statusOpen.action!, to: statusOpen.target, from: statusOpen)
                   && NSApp.sendAction(statusSettingsItem.action!, to: statusSettingsItem.target, from: statusSettingsItem)
                   && NSApp.sendAction(statusQuitItem.action!, to: statusQuitItem.target, from: statusQuitItem),
                   "Every status-menu command dispatches through an explicit target")
        try expect(statusDaily == 1 && statusSettings == 1 && statusQuit == 1,
                   "Status-menu commands invoke their intended actions once")

        coordinator!.autoCapture.settings.setClipboardEnabled(true)
        coordinator!.autoCapture.settings.setStatus(.monitoring)
        try await wait("Status item updates live when Auto Capture is enabled") {
            statusBar.presentation.indicator == .recording
                && statusBar.statusMenuItem?.title == "Auto Capture: Recording"
                && statusBar.pauseMenuItem?.isHidden == false
        }
        try expect(statusBar.statusItem?.button?.toolTip == "DaBin — Recording",
                   "The enabled menu bar icon exposes its state without opening DaBin")
        let activeImage = try unwrap(statusBar.statusItem?.button?.image, "The installed status item displays its recording image")
        try expect(!coordinator!.corners.board.isVisible && !activeImage.isTemplate && hasRedPixels(activeImage, appearance: .aqua),
                   "The real installed menu-bar button uses the colored recording image while the board stays closed")
        let pause = statusBar.pauseMenuItem!
        try expect(NSApp.sendAction(pause.action!, to: pause.target, from: pause),
                   "The enabled status menu dispatches Pause Auto Capture")
        try await wait("Pausing updates the menu bar status and action") {
            statusBar.presentation.indicator == .paused
                && statusBar.statusMenuItem?.title == "Auto Capture: Paused"
                && statusBar.pauseMenuItem?.title == "Resume Auto Capture"
        }
        coordinator!.autoCapture.settings.setPaused(false)
        coordinator!.autoCapture.settings.setStatus(.permissionRevoked)
        try await wait("Permission problems become visible in the persistent status") {
            statusBar.presentation.indicator == .attention
                && statusBar.statusMenuItem?.title == "Auto Capture: Permission needs attention"
        }
        let installedStatusItem = statusBar.statusItem
        statusBar.uninstall()
        try expect(statusBar.statusItem == nil && installedStatusItem?.menu == nil,
                   "Status item teardown removes its menu and subscriptions")

        var settingsQuitRequests = 0
        let settingsQuitSection = SettingsQuitSection { settingsQuitRequests += 1 }
        try expect(SettingsQuitSection.buttonTitle == "Quit DaBin"
                   && SettingsQuitSection.accessibilityLabel == "Quit DaBin completely",
                   "Settings exposes a clearly named complete-quit action")
        try expect(SettingsQuitSection.accessibilityHint.contains("Stops Auto Capture")
                   && SettingsQuitSection.accessibilityHint.contains("no longer running in the background"),
                   "The complete-quit control explains its background-monitoring effect")
        settingsQuitSection.quitApplication()
        try expect(settingsQuitRequests == 1,
                   "The Settings complete-quit control invokes its injected termination request exactly once")

        coordinator!.shutdown()
        let readCount = reads, callCount = client.authorizationCalls
        try expect(coordinator!.isStopped && !coordinator!.isStarted && coordinator!.corners.isShutDown,
                   "Shutdown closes the running session")
        try expect(!coordinator!.autoCapture.isRunning,
                   "Shutdown leaves Auto Capture and its background monitors stopped")
        try expect(coordinator!.input.onResult == nil && coordinator!.input.onBusy == nil && coordinator!.reminders.onOpenCapture == nil,
                   "Shutdown disconnects import and notification callbacks")
        try expect(coordinator!.state.onDismiss == nil && coordinator!.state.onBoardDragStarted == nil,
                   "Shutdown disconnects view callbacks")
        try expect(!coordinator!.corners.board.isVisible && !coordinator!.corners.bin.isVisible,
                   "Shutdown closes both native panels")
        coordinator!.shutdown()
        if let screen = NSScreen.screens.first {
            coordinator!.corners.reveal(on: screen, corner: .topLeft, focus: true)
            try expect(!coordinator!.corners.bin.isVisible && !coordinator!.corners.board.isVisible,
                       "A stale direct reveal cannot reopen a shut down native panel")
        }
        coordinator!.start(showDaily: true)
        appEvents.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        workspaceEvents.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(250))
        try expect(reads == readCount && client.authorizationCalls == callCount,
                   "No timer or lifecycle work runs after shutdown")
        try expect(!coordinator!.corners.board.isVisible, "A stopped session cannot restart its panels")
        try expect(client.requests[identifier]?.date == capture.reminderAt,
                   "Normal quit preserves the user's scheduled reminder")
        try expect(store.captures.count == 1 && store.captures.first?.id == capture.id,
                   "Shutdown does not delete or reset the archive")
        coordinator = nil
        try await wait("Application and panel owner are released after shutdown") { weakCoordinator.value == nil && weakCorners.value == nil }
        try await wait("Presentation state is released after native view teardown") { weakState.value == nil }
        try await startupDerivatives(root: root.appendingPathComponent("StartupDerivatives"), defaults: defaults)
        try expect(!activatedFixture && !acquiredKeyWindow && !NSApp.isActive && NSApp.keyWindow == nil,
                   "Native lifecycle QA never activates itself or takes keyboard focus")
        print("PASS: \(checks) application lifecycle checks; isolated preferences, events, pointer samples and fake notifications, no focus or personal data.")
    }

    @MainActor private func startupDerivatives(root: URL, defaults: UserDefaults) async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let records = (0..<40).map { index in
            Capture(kind: .text, originalText: "Synthetic startup text \(index)", title: "Startup text \(index)")
        }
        try CaptureRepository(root: root).save(records)
        let store = try CaptureStore(root: root, repairArchiveOnOpen: false)
        let coordinator = ApplicationCoordinator(store: store, defaults: defaults,
            notificationClient: SessionReminderClient(), applicationEvents: NotificationCenter(), workspaceEvents: NotificationCenter())
        coordinator.start(installMenu: false, installStatusItem: false,
                          pointerPosition: { NSPoint(x: -100_000, y: -100_000) })
        try expect(coordinator.pendingStartupDerivativeCount == 40 && store.captures.allSatisfy { $0.previewState == "idle" },
                   "Application start returns ready metadata before bulk preview writes")
        try await wait("Startup derivative checks progress in bounded batches") { coordinator.pendingStartupDerivativeCount < 40 }
        coordinator.shutdown()
        let readyBeforeWait = store.captures.filter { $0.previewState == "ready" }.count
        try await Task.sleep(for: .milliseconds(100))
        try expect(coordinator.pendingStartupDerivativeCount == 0 && store.captures.filter { $0.previewState == "ready" }.count == readyBeforeWait,
                   "Shutdown cancels future derivative batches instead of continuing archive writes")
        let restarted = ApplicationCoordinator(store: store, defaults: defaults,
            notificationClient: SessionReminderClient(), applicationEvents: NotificationCenter(), workspaceEvents: NotificationCenter())
        restarted.start(installMenu: false, installStatusItem: false,
                        pointerPosition: { NSPoint(x: -100_000, y: -100_000) })
        try await wait("New session finishes remaining derivative work") { restarted.pendingStartupDerivativeCount == 0 }
        try expect(store.captures.allSatisfy { $0.previewState == "ready" }, "Interrupted startup previews recover on the next session")
        restarted.shutdown()
    }
}
