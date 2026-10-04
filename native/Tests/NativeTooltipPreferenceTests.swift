import AppKit
import Foundation
import SwiftUI

@MainActor private final class NativeTooltipReminderClient: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .undetermined }
    func requestAuthorization() async throws -> Bool { fatalError("Tooltip QA never requests notification permission") }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}

@MainActor private struct NativeDragTooltipFixture: View {
    @ObservedObject var theme: ThemeSettings
    let onDragStarted: () -> Void

    var body: some View {
        WindowDragHandle(onDragStarted: onDragStarted)
            .environment(\.daBinTooltipsEnabled, theme.showTooltips)
            .frame(width: 160, height: 36)
    }
}

/// Own-process native controls only. Services are constructed but never started;
/// no real clipboard, archive, notification permission, global pointer events,
/// application activation or installed DaBin is involved.
@main @MainActor
private final class NativeTooltipPreferenceTests: NSObject, NSApplicationDelegate {
    private static var checks = 0
    private var result: Int32 = 0

    static func main() {
        let app = NSApplication.shared
        let delegate = NativeTooltipPreferenceTests()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        exit(delegate.result)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do { try await Self.runChecks() }
            catch { result = 1; fputs("FAIL: \(error)\n", stderr) }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard condition() else { throw failure(message) }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "NativeTooltipPreferenceTests", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func axText(_ object: NSObject, _ name: String) -> String {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else { return "" }
        return object.perform(selector)?.takeUnretainedValue() as? String ?? ""
    }

    private static func dragHandle(in view: NSView) -> WindowDragHandleView? {
        if let handle = view as? WindowDragHandleView { return handle }
        return view.subviews.lazy.compactMap { dragHandle(in: $0) }.first
    }

    private static func wait(_ message: String, until condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try expect(condition(), message)
    }

    private static func runChecks() async throws {
        let defaultRobot = RobotView(frame: CGRect(x: 0, y: 0, width: 72, height: 88),
                                     reduceMotion: { true })
        let robotHelp = axText(defaultRobot, "accessibilityHelp")
        let robotLabel = axText(defaultRobot, "accessibilityLabel")
        let robotTooltip = defaultRobot.toolTip
        try expect(defaultRobot.showTooltips && !(robotTooltip ?? "").isEmpty,
                   "A standalone robot preserves default-enabled native hover help")
        try expect(!robotHelp.isEmpty && !robotLabel.isEmpty,
                   "Robot instructions and label remain independently accessible")
        defaultRobot.showTooltips = false
        try expect(defaultRobot.toolTip == nil,
                   "Disabling robot hover help removes its native tooltip")
        try expect(axText(defaultRobot, "accessibilityHelp") == robotHelp
            && axText(defaultRobot, "accessibilityLabel") == robotLabel,
                   "The visual tooltip preference never removes robot accessibility instructions")
        defaultRobot.showTooltips = true
        try expect(defaultRobot.toolTip == robotTooltip,
                   "Re-enabling hover help restores the same useful robot instructions")

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DaBinNativeTooltip-\(UUID().uuidString)", isDirectory: true)
        let suite = "DaBinNativeTooltipTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw failure("Isolated tooltip preferences are required") }
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let store = try CaptureStore(root: root.appendingPathComponent("Initial", isDirectory: true))
        let coordinator = ApplicationCoordinator(store: store, defaults: defaults,
            notificationClient: NativeTooltipReminderClient(),
            applicationEvents: NotificationCenter(), workspaceEvents: NotificationCenter())
        defer { coordinator.shutdown() }
        try expect(!coordinator.isStarted && !coordinator.corners.board.isVisible
            && !coordinator.corners.bin.isVisible,
                   "Tooltip preference wiring never starts capture services or reveals native panels")
        try expect(coordinator.theme.showTooltips && coordinator.corners.robot.showTooltips,
                   "The composition root starts with one shared, enabled tooltip preference")
        coordinator.statusBar.install()
        // Hide this test's own status item immediately; never modify another
        // application's item or the running user's DaBin.
        coordinator.statusBar.statusItem?.isVisible = false
        guard let statusButton = coordinator.statusBar.statusItem?.button else {
            throw failure("An own-process native status button is required")
        }
        let statusLabel = axText(statusButton, "accessibilityLabel")
        let statusHelp = axText(statusButton, "accessibilityHelp")
        try expect(statusButton.toolTip == "DaBin — Off",
                   "The shared status item has enabled hover help before Auto Capture starts")
        try expect(!statusLabel.isEmpty && !statusHelp.isEmpty,
                   "The status item's accessibility label and instructions exist independently")
        let sharedRobotHelp = axText(coordinator.corners.robot, "accessibilityHelp")
        let sharedRobotLabel = axText(coordinator.corners.robot, "accessibilityLabel")

        coordinator.theme.setShowTooltips(false)
        try expect(!coordinator.corners.robot.showTooltips && coordinator.corners.robot.toolTip == nil,
                   "The same live theme preference disables the native island robot immediately")
        try expect(statusButton.toolTip == nil,
                   "The same live theme preference disables the native menu-bar tooltip immediately")
        try expect(axText(coordinator.corners.robot, "accessibilityHelp") == sharedRobotHelp
            && axText(coordinator.corners.robot, "accessibilityLabel") == sharedRobotLabel
            && axText(statusButton, "accessibilityHelp") == statusHelp
            && axText(statusButton, "accessibilityLabel") == statusLabel,
                   "Disabling visual help preserves native robot and status accessibility semantics")
        coordinator.autoCapture.settings.setClipboardEnabled(true)
        coordinator.autoCapture.settings.setStatus(.monitoring)
        try expect(coordinator.statusBar.presentation.indicator == .recording
            && coordinator.statusBar.statusMenuItem?.title == "Auto Capture: Recording",
                   "Updating status metadata remains functional while hover help is disabled")
        try expect(statusButton.toolTip == nil,
                   "An Auto Capture refresh cannot silently re-enable disabled native tooltips")
        try expect(statusButton.image?.isTemplate == false,
                   "The active menu-bar recording symbol retains its color while tooltips are disabled")
        try expect(axText(statusButton, "accessibilityValue") == "Recording",
                   "Status accessibility still reports the current capture state while tooltips are off")
        coordinator.theme.setShowTooltips(true)
        try expect(coordinator.corners.robot.showTooltips
            && coordinator.corners.robot.toolTip == robotTooltip
            && statusButton.toolTip == "DaBin — Recording",
                   "Re-enabling the single shared preference restores current native hover help")
        coordinator.autoCapture.settings.setStatus(.permissionRevoked)
        try expect(statusButton.toolTip == "DaBin — Permission needs attention",
                   "Enabled hover help continues to follow status changes")

        try await checkNativeDragHandle(theme: coordinator.theme)

        coordinator.theme.setShowTooltips(false)
        try expect(defaults.object(forKey: ThemeSettings.showTooltipsKey) as? Bool == false,
                   "The shared disabled tooltip preference is persisted in its isolated domain")
        let reopenedStore = try CaptureStore(root: root.appendingPathComponent("Reopened", isDirectory: true))
        let reopened = ApplicationCoordinator(store: reopenedStore, defaults: defaults,
            notificationClient: NativeTooltipReminderClient(),
            applicationEvents: NotificationCenter(), workspaceEvents: NotificationCenter())
        defer { reopened.shutdown() }
        try expect(!reopened.theme.showTooltips && !reopened.corners.robot.showTooltips
            && reopened.corners.robot.toolTip == nil,
                   "A newly composed session restores disabled native robot help before showing any UI")
        reopened.statusBar.install()
        reopened.statusBar.statusItem?.isVisible = false
        try expect(reopened.statusBar.statusItem?.button?.toolTip == nil,
                   "A newly composed session restores disabled menu-bar help on installation")
        reopened.statusBar.uninstall()
        reopened.theme.setShowTooltips(true)
        try expect(reopened.statusBar.statusItem == nil,
                   "Preference changes cannot resurrect an uninstalled native status item")

        // Existing non-production call sites may omit a shared theme. The
        // optional injection retains their documented default-enabled behavior.
        let legacyStatus = StatusBarController(openDaily: {}, showSettings: {}, quit: {},
                                               autoCapture: coordinator.autoCapture)
        legacyStatus.install()
        legacyStatus.statusItem?.isVisible = false
        defer { legacyStatus.uninstall() }
        try expect(!(legacyStatus.statusItem?.button?.toolTip ?? "").isEmpty,
                   "A status controller without theme injection keeps backwards-compatible enabled help")
        legacyStatus.uninstall()

        coordinator.shutdown()
        try expect(coordinator.statusBar.statusItem == nil && coordinator.corners.isShutDown,
                   "Normal teardown removes native status UI and stops robot preference observation")
        coordinator.theme.setShowTooltips(true)
        try expect(!coordinator.corners.robot.showTooltips && coordinator.corners.robot.toolTip == nil,
                   "A stale preference notification cannot mutate a stopped robot controller")
        try expect(coordinator.statusBar.statusItem == nil,
                   "A stale preference notification cannot recreate a stopped status item")
        print("PASS: \(checks) native tooltip preference, persistence, accessibility, drag interaction, and lifecycle checks")
    }

    private static func checkNativeDragHandle(theme: ThemeSettings) async throws {
        var dragStarts = 0
        theme.setShowTooltips(true)
        let hosting = NSHostingView(rootView: NativeDragTooltipFixture(theme: theme,
                                                                      onDragStarted: { dragStarts += 1 }))
        hosting.frame = CGRect(x: 0, y: 0, width: 160, height: 36)
        let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 160, height: 36),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        try await wait("The real native window drag handle mounts in its own offscreen SwiftUI fixture") {
            hosting.layoutSubtreeIfNeeded()
            return dragHandle(in: hosting) != nil
        }
        try expect(dragHandle(in: hosting)?.toolTip == "Drag to move DaBin between screens",
                   "An enabled native drag surface shows its useful movement instruction")
        theme.setShowTooltips(false)
        try await wait("The same preference removes an already-mounted native drag tooltip") {
            hosting.layoutSubtreeIfNeeded()
            return dragHandle(in: hosting)?.toolTip == nil
        }
        guard let handle = dragHandle(in: hosting) else { throw failure("Disabled help must not remove the drag surface") }
        let point = handle.convert(CGPoint(x: handle.bounds.midX, y: handle.bounds.midY), to: nil)
        guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1),
              let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 2, clickCount: 1, pressure: 0) else {
            throw failure("Own-window drag events are required")
        }
        handle.mouseDown(with: down)
        handle.mouseUp(with: up)
        try expect(dragStarts == 1,
                   "Turning off hover help preserves the native drag action without global pointer events")
        theme.setShowTooltips(true)
        try await wait("Re-enabling restores help on the mounted native drag surface") {
            hosting.layoutSubtreeIfNeeded()
            return dragHandle(in: hosting)?.toolTip == "Drag to move DaBin between screens"
        }
    }
}
