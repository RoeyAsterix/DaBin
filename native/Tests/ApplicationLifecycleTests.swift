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
    private func run() async throws {
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
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
        try expect(coordinator?.isStarted == false && coordinator?.isStopped == false,
                   "Construction does not start observers or pointer monitoring")
        try expect(!coordinator!.corners.board.isVisible && !coordinator!.corners.bin.isVisible,
                   "Construction keeps both native panels hidden")
        coordinator!.theme.select(.teal)
        try expect(ThemeSettings(defaults: defaults).selectedHex == ThemePreset.teal.hex,
                   "The composition root shares injected local preferences with theme state")
        var reads = 0
        coordinator!.start(installMenu: false, pointerPosition: { reads += 1; return NSPoint(x: -100_000, y: -100_000) })
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
        let open = appMenu.items.first { $0.title == "Open Daily" }!
        let checkUpdates = appMenu.items.first { $0.title == "Check for Updates…" }!
        let preference = appMenu.items.first { $0.title == "Settings…" }!
        try expect(NSApp.sendAction(open.action!, to: open.target, from: open), "Native Open Daily command dispatches")
        try expect(NSApp.sendAction(checkUpdates.action!, to: checkUpdates.target, from: checkUpdates),
                   "Native Check for Updates command dispatches")
        try expect(NSApp.sendAction(preference.action!, to: preference.target, from: preference), "Native Settings command dispatches")
        try expect(daily == 1 && updateChecks == 1 && settings == 1, "Menu commands invoke their intended actions once")
        let edit = NSApp.mainMenu!.items[1].submenu!
        try expect(edit.items.first { $0.title == "Paste" }?.target == nil, "Paste resolves through the native responder chain")
        try expect(appMenu.items.contains { $0.title == "About DaBin" } && appMenu.items.contains { $0.title == "Hide DaBin" },
                   "App menu provides standard macOS About and Hide commands")
        let installed = NSApp.mainMenu
        menu.install()
        try expect(NSApp.mainMenu === installed, "Menu installation is idempotent")
        menu.uninstall()
        NSApp.mainMenu = oldMenu

        coordinator!.shutdown()
        let readCount = reads, callCount = client.authorizationCalls
        try expect(coordinator!.isStopped && !coordinator!.isStarted && coordinator!.corners.isShutDown,
                   "Shutdown closes the running session")
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
        try expect(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmost,
                   "Native lifecycle QA never changes the foreground application")
        print("PASS: \(checks) application lifecycle checks; isolated preferences, events, pointer samples and fake notifications, no focus or personal data.")
    }
}
