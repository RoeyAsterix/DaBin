import AppKit
import Foundation

@MainActor private final class ZoomReminderClient: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .denied }
    func requestAuthorization() async throws -> Bool { false }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ request: ScheduledReminder) async throws { }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}

/// Isolated geometry/preferences and native panels; never imports clipboard
/// contents, touches a user archive, or posts input to another application.
@main private enum WorkspaceZoomTests {
    @MainActor private static var checks = 0
    @MainActor private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard condition() else { throw NSError(domain: "WorkspaceZoomTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    private static func near(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) < 1.1 && abs(lhs.minY - rhs.minY) < 1.1
            && abs(lhs.width - rhs.width) < 1.1 && abs(lhs.height - rhs.height) < 1.1
    }
    @MainActor private static func settle() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.13))
    }
    @MainActor static func main() throws {
        let suite = "DaBin.WorkspaceZoomTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let zoom = WorkspaceZoomSettings(defaults: defaults)
        try expect(zoom.factor == 1 && zoom.trackpadNavigationEnabled && zoom.resizeWindowWithZoom,
                   "Zoom starts at 100 percent with both optional input settings enabled")
        var callbacks: [String] = []
        zoom.onInteractionBegan = { callbacks.append("begin"); return true }
        zoom.onWillChangeFactor = { _ in callbacks.append("before") }
        zoom.onFactorChanged = { _ in callbacks.append("geometry") }
        zoom.onFactorApplied = { _ in callbacks.append("after") }
        zoom.onInteractionEnded = { callbacks.append("end") }
        try expect(zoom.beginInteraction() && zoom.beginInteraction(), "One accepted session can receive many ticks")
        for factor in [1.03, 1.12, 1.27] { zoom.update(to: factor) }
        try expect(defaults.object(forKey: WorkspaceZoomSettings.factorKey) == nil,
                   "Continuous zoom never persists per tick")
        try expect(callbacks == ["begin", "before", "geometry", "after", "before", "geometry", "after", "before", "geometry", "after"],
                   "Anchor capture precedes scale and geometry; one begin occurs")
        zoom.update(to: .nan); zoom.update(to: .infinity); zoom.update(to: -.infinity); zoom.update(to: 0)
        try expect(zoom.factor == 1.27, "Invalid events retain the last valid zoom")
        zoom.finishInteraction(); zoom.finishInteraction()
        try expect(!zoom.isInteracting && zoom.persistenceCount == 1 && defaults.double(forKey: WorkspaceZoomSettings.factorKey) == 1.27,
                   "Cancellation/completion persists the last visible scale exactly once")
        zoom.stepIn(); try expect(zoom.factor == 1.5, "In-between zoom steps up to the next configured stop")
        zoom.setFactor(1.27); zoom.stepOut(); try expect(zoom.factor == 1.25, "In-between zoom steps down to previous stop")
        zoom.setFactor(999); try expect(zoom.factor == 2 && !zoom.canZoomIn, "Upper scale limit is independent of window bounds")
        zoom.setFactor(0.001); try expect(zoom.factor == 0.75 && !zoom.canZoomOut, "Lower scale limit clamps finite input")
        zoom.reset(); try expect(zoom.factor == 1 && zoom.percentage == 100, "Reset uses 100 percent")
        zoom.onInteractionBegan = { false }
        zoom.stepIn(); try expect(zoom.factor == 1 && !zoom.isInteracting, "Busy window rejects commands without queued changes")
        zoom.onInteractionBegan = nil
        zoom.trackpadNavigationEnabled = false; zoom.resizeWindowWithZoom = false
        let restored = WorkspaceZoomSettings(defaults: defaults)
        try expect(restored.factor == 1 && !restored.trackpadNavigationEnabled && !restored.resizeWindowWithZoom,
                   "Only local validated preferences are restored")
        defaults.set(Double.nan, forKey: WorkspaceZoomSettings.factorKey)
        try expect(WorkspaceZoomSettings(defaults: defaults).factor == 1, "Invalid saved values recover a safe default")
        defaults.set("broken", forKey: WorkspaceZoomSettings.factorKey)
        try expect(WorkspaceZoomSettings(defaults: defaults).factor == 1, "Wrong persisted types are ignored")

        let visible = CGRect(x: -1280, y: 30, width: 1280, height: 800)
        let initial = CGRect(x: -1150, y: 240, width: 600, height: 540)
        var geometry = WorkspaceZoomGeometry(frame: initial, factor: 1)!
        let high = geometry.frame(at: 2, visible: visible)!
        try expect(visible.contains(high), "Growth fits an offset display's menu bar and Dock safe area")
        try expect(high.height == visible.height, "Fixture actually reaches the screen clamp")
        for cycle in 0..<50 {
            _ = geometry.frame(at: 2, visible: visible)
            try expect(geometry.frame(at: 1, visible: visible) == initial, "Clamp reversal has no drift at cycle \(cycle)")
        }
        let intermediate = geometry.frame(at: 1.5, visible: visible)!
        try expect(intermediate.width == (initial.width - RobotAppFrameView.extraWidth) * 1.5 + RobotAppFrameView.extraWidth,
                   "Scale changes the content, leaving robot chrome unscaled")
        let unclamped = geometry.frame(at: 1.1, visible: visible)!
        try expect(unclamped.minX == initial.minX && unclamped.maxY == initial.maxY,
                   "A zoom with sufficient room preserves the exact top-left")
        let expectedHeight = (initial.height - RobotAppFrameView.extraHeight) * 1.5 + RobotAppFrameView.extraHeight
        try expect(intermediate.minX == initial.minX && intermediate.minY == visible.minY
                   && intermediate.maxY == visible.minY + expectedHeight,
                   "Bottom-edge pressure shifts upward only enough to fit, without snapping to the display top")
        let minimum = geometry.frame(at: 0.75, visible: visible)!
        try expect(minimum.height >= BoardResizeGeometry.minimumSize.height, "Minimum size stops the window, not the scale")
        let verySmall = CGRect(x: 100, y: 100, width: 310, height: 270)
        try expect(geometry.frame(at: 2, visible: verySmall) == verySmall, "Small displays keep all controls on the surviving screen")
        try expect(geometry.frame(at: .nan, visible: visible) == nil
                   && geometry.frame(at: 1, visible: .zero) == nil
                   && WorkspaceZoomGeometry(frame: CGRect(x: CGFloat.infinity, y: 0, width: 2, height: 2), factor: 1) == nil,
                   "Malformed geometry cannot reach native setFrame")
        let extreme = WorkspaceZoomGeometry(frame: CGRect(x: -1e308, y: -1e308, width: 1e308, height: 1e308), factor: 1)!
        try expect(extreme.frame(at: 2, visible: visible) == nil,
                   "Finite but corrupt huge dimensions cannot overflow during zoom multiplication")
        geometry.move(to: CGPoint(x: -1200, y: 750))
        let moved = geometry.frame(at: 1, visible: visible)!
        try expect(moved.size == initial.size && moved.minX == -1200 && moved.maxY == 750,
                   "Manual movement changes the position reference without changing size calibration")
        let manual = CGRect(x: -1250, y: 120, width: 700, height: 650)
        geometry.rebase(frame: manual, factor: 1.5)
        try expect(geometry.frame(at: 1.5, visible: visible) == manual, "Manual resize rebases at the current content factor")
        try expect(geometry.frame(at: 1, visible: visible)!.width == (manual.width - 20) / 1.5 + 20,
                   "Reset after manual sizing uses its new reference")
        let otherScreen = CGRect(x: 1280, y: -240, width: 900, height: 650)
        let relocated = geometry.frame(at: 1.5, visible: otherScreen)!
        geometry.rebase(frame: relocated, factor: 1.5)
        try expect(otherScreen.contains(relocated) && geometry.frame(at: 1.5, visible: otherScreen) == relocated,
                   "Display loss safely fits and rebases at unchanged zoom")

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory); app.finishLaunching()
        guard let screen = NSScreen.screens.first else { throw NSError(domain: "WorkspaceZoomTests", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Native window checks require an active display"] ) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBin-Zoom-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root)
        let previews = PreviewService(store: store, defaults: defaults)
        let input = InputService(store: store, stagingRoot: root.appendingPathComponent("Staging"))
        let nativeZoom = WorkspaceZoomSettings(defaults: nil)
        let state = AppState(store: store, previews: previews,
            reminders: ReminderService(store: store, client: ZoomReminderClient()),
            workspaceZoom: nativeZoom, manualInput: input)
        let controller = CornerController(state: state, input: input, placementDefaults: defaults,
            theme: ThemeSettings(defaults: defaults, systemDarkMode: false),
            animateRobotTransitions: false, robotReduceMotion: { true })
        defer { controller.shutdown(); previews.shutdown() }
        controller.reveal(on: screen, corner: .topRight); state.openDaily(); controller.showBoard(immediate: true); settle()
        let automatic = controller.board.frame
        try expect(nativeZoom.beginInteraction(), "A visible board accepts a dedicated workspace gesture")
        try expect(controller.board.frame == automatic, "Gesture begin does not enforce the manual minimum")
        nativeZoom.finishInteraction()
        nativeZoom.setFactor(1.1); settle()
        try expect(controller.board.frame.height >= min(BoardResizeGeometry.minimumSize.height, screen.visibleFrame.height),
                   "First actual coupled change adopts a usable manual minimum")
        try expect(defaults.bool(forKey: CornerController.boardZoomSizeKey), "Completed coupled zoom preserves explicit normal sizing")
        let normal = controller.board.frame
        controller.toggleExpandedWindow(); let expanded = controller.board.frame
        nativeZoom.setFactor(1.5); settle()
        try expect(near(controller.board.frame, expanded), "Expanded zoom remains expanded")
        controller.toggleExpandedWindow(); settle()
        try expect(near(controller.board.frame, normal) && nativeZoom.factor == 1.5,
                   "Restore returns the exact saved frame and retains current zoom")
        nativeZoom.setFactor(1.75); settle()
        try expect(controller.board.frame.width >= normal.width, "Restored geometry becomes the new reference without a jump")
        nativeZoom.resizeWindowWithZoom = false; let uncoupled = controller.board.frame
        nativeZoom.setFactor(0.9); settle()
        try expect(near(controller.board.frame, uncoupled), "Uncoupled zoom changes content only")
        nativeZoom.resizeWindowWithZoom = true
        try expect(near(controller.board.frame, uncoupled), "Enabling coupling does not immediately resize")
        let snapshot = WorkspaceZoomGeometry(frame: uncoupled, factor: 0.9)!
        nativeZoom.setFactor(1); settle()
        try expect(near(controller.board.frame, snapshot.frame(at: 1, visible: screen.visibleFrame)!),
                   "Next coupled command uses the current geometry and scale")
        let chosen = controller.board.frame
        state.showSettings(); settle()
        try expect(near(controller.board.frame, chosen), "Route-driven fitting retains an explicit coupled window size")
        state.openDaily(); settle()
        controller.beginBoardDrag(pointer: CGPoint(x: chosen.midX, y: chosen.maxY - 40))
        try expect(!nativeZoom.beginInteraction() && state.navigationWindowInteractionBlocked,
                   "Manual window movement blocks zoom and history")
        controller.finishBoardDragIfReleased(pressedMouseButtons: 0)
        try expect(!state.navigationWindowInteractionBlocked, "Finishing movement clears the busy state")
        try expect(nativeZoom.beginInteraction(), "A fresh session is accepted after movement")
        nativeZoom.update(to: 1.25)
        controller.dismiss()
        try expect(!nativeZoom.isInteracting && nativeZoom.factor == 1.25, "Closing retains the last valid factor and ends zoom")
        controller.showBoard(immediate: true); settle()
        try expect(nativeZoom.factor == 1.25, "Collapsing into and reopening from the robot preserves workspace zoom")
        print("Workspace zoom: \(checks) checks passed")
    }
}
