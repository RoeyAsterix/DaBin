import AppKit
import Foundation

@MainActor
private final class WindowNotificationClient: ReminderNotificationClient {
    var permissionRequests = 0
    var additions = 0
    func authorization() async -> ReminderAuthorization { .undetermined }
    func requestAuthorization() async throws -> Bool { permissionRequests += 1; return false }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { additions += 1 }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}

/// Exercises real AppKit panels using injected pointer observations. It neither
/// moves the system cursor nor reads/writes the general pasteboard or other apps.
@main struct WindowTests {
    @MainActor private static var checks = 0
    @MainActor private static var failures: [String] = []

    @MainActor private static func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        if !value() {
            failures.append(message)
            fputs("FAIL: \(message)\n", stderr)
        }
    }

    private static func cornerPoint(_ corner: ScreenCorner, frame: NSRect) -> NSPoint {
        NSPoint(x: corner.isRight ? frame.maxX - 1 : frame.minX + 1,
                y: corner.isTop ? frame.maxY - 1 : frame.minY + 1)
    }

    @MainActor static func main() throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.finishLaunching()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinWindowTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let placementSuite = "DaBinWindowTests.\(UUID().uuidString)"
        let placementDefaults = UserDefaults(suiteName: placementSuite)!
        defer { placementDefaults.removePersistentDomain(forName: placementSuite) }
        let store = try CaptureStore(root: root)
        let notificationClient = WindowNotificationClient()
        let previews = PreviewService(store: store)
        let reminders = ReminderService(store: store, client: notificationClient)
        let state = AppState(store: store, previews: previews, reminders: reminders)
        let input = InputService(store: store, stagingRoot: root.appendingPathComponent("Promises"))
        let controller = CornerController(state: state, input: input, placementDefaults: placementDefaults)
        defer {
            controller.dismiss()
            controller.bin.orderOut(nil)
            controller.board.orderOut(nil)
            previews.cancelNetwork()
        }
        let ownedWindows = [controller.bin, controller.board]
        try expect(ownedWindows.filter(\.isVisible).isEmpty, "At launch both DaBin panels are hidden")
        try expect(application.windows.filter(\.isVisible).isEmpty, "Test process has zero visible windows at launch")
        try expect(controller.bin.backgroundColor == .clear && !controller.bin.isOpaque, "Robot panel has no opaque background")
        try expect(controller.bin.frame.width <= 72 && controller.bin.frame.height <= 88, "Hidden robot owns only its compact panel bounds")
        let screens = NSScreen.screens
        try expect(!screens.isEmpty, "Window checks require an attached screen")
        guard !screens.isEmpty else { exit(1) }
        var clock = Date().addingTimeInterval(10)

        for (screenIndex, screen) in screens.enumerated() {
            let away = NSPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY)
            for corner in ScreenCorner.allCases {
                controller.pollPointer(at: away, now: clock)
                let point = cornerPoint(corner, frame: screen.frame)
                clock = clock.addingTimeInterval(3)
                controller.pollPointer(at: point, now: clock)
                let label = "screen \(screenIndex), \(corner.rawValue)"
                try expect(controller.bin.isVisible, "\(label): corner reveals robot")
                try expect(!controller.board.isVisible, "\(label): corner does not open Daily")
                try expect(ownedWindows.filter(\.isVisible).count == 1, "\(label): only the robot is visible")
                let expected = CornerGeometry.robotFrame(corner: corner, visible: screen.visibleFrame)
                try expect(controller.bin.frame == expected, "\(label): robot appears at the matching visible-screen corner")

                // Deliberately take longer than the 0.8-second exit grace at each
                // sample. The protected path, including Dock/menu-bar insets, keeps it open.
                let target = NSPoint(x: controller.bin.frame.midX, y: controller.bin.frame.midY)
                for step in 1...6 {
                    let progress = CGFloat(step) / 6
                    let pointOnPath = NSPoint(x: point.x + (target.x - point.x) * progress,
                                              y: point.y + (target.y - point.y) * progress)
                    clock = clock.addingTimeInterval(2)
                    controller.pollPointer(at: pointOnPath, now: clock)
                    try expect(controller.bin.isVisible, "\(label): slow corner-to-robot path sample \(step) stays visible")
                    try expect(controller.bin.frame == expected, "\(label): corner-to-robot path does not reposition the target")
                }
                clock = clock.addingTimeInterval(3)
                controller.pollPointer(at: away, now: clock)
                try expect(ownedWindows.filter(\.isVisible).isEmpty, "\(label): pointer away for three seconds hides all DaBin UI")
            }
        }

        let screen = screens[0]
        let corner = ScreenCorner.bottomRight
        let point = cornerPoint(corner, frame: screen.frame)
        let away = NSPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY)
        clock = clock.addingTimeInterval(3)
        controller.pollPointer(at: point, now: clock)
        try expect(controller.bin.isVisible, "Robot visible before opening Daily")
        let hoverPoint = NSPoint(x: controller.bin.frame.midX, y: controller.bin.frame.midY)
        let frontmostBeforeHover = NSWorkspace.shared.frontmostApplication?.processIdentifier
        controller.pollPointer(at: hoverPoint, now: clock, pressedMouseButtons: 0)
        try expect(controller.bin.isKeyWindow, "Hover grants robot keyboard focus without a click")
        try expect(controller.bin.firstResponder === controller.robot, "Hovered robot is the paste responder")
        try expect(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmostBeforeHover,
                   "Hover preserves the frontmost application")
        let corridorPoint = NSPoint(x: controller.bin.frame.midX, y: controller.bin.frame.maxY + 2)
        controller.pollPointer(at: corridorPoint, now: clock, pressedMouseButtons: 0)
        try expect(controller.bin.isVisible && !controller.bin.isKeyWindow, "Leaving robot releases keys while retaining retreat grace")
        controller.pollPointer(at: hoverPoint, now: clock, pressedMouseButtons: 1)
        try expect(!controller.bin.isKeyWindow, "Pointer with a pressed mouse button cannot steal drag focus")
        controller.pollPointer(at: hoverPoint, now: clock, pressedMouseButtons: 0)
        try expect(controller.bin.isKeyWindow, "Returning to robot restores hover paste focus")
        controller.pollPointer(at: corridorPoint, now: clock, pressedMouseButtons: 0)
        controller.robot.onDragState?(true)
        controller.pollPointer(at: hoverPoint, now: clock, pressedMouseButtons: 0)
        try expect(!controller.bin.isKeyWindow, "Active file drag does not take keyboard focus")
        controller.robot.onDragState?(false)
        // Dispatch only to our own responder; never read the user's clipboard.
        let pasteHandler = controller.robot.onPaste
        var pasteCalls = 0
        controller.robot.onPaste = { pasteCalls += 1 }
        func shortcut(_ flags: NSEvent.ModifierFlags, time: TimeInterval, repeatKey: Bool = false,
                      characters: String = "v", ignoringModifiers: String = "v") -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: time,
                            windowNumber: controller.bin.windowNumber, context: nil, characters: characters,
                            charactersIgnoringModifiers: ignoringModifiers, isARepeat: repeatKey, keyCode: 9)!
        }
        let controlPaste = shortcut(.control, time: 1)
        controller.robot.keyDown(with: controlPaste)
        try expect(pasteCalls == 1, "Control V routes to paste without a robot click")
        try expect(controller.robot.performKeyEquivalent(with: controlPaste) && pasteCalls == 1,
                   "One event routed through both responder methods captures only once")
        let commandPaste = shortcut(.command, time: 2)
        try expect(controller.robot.performKeyEquivalent(with: commandPaste) && pasteCalls == 2,
                   "Command V remains supported")
        try expect(controller.robot.handlePasteShortcut(shortcut(.control, time: 3, repeatKey: true)) && pasteCalls == 2,
                   "Holding paste does not create repeated captures")
        controller.robot.keyDown(with: shortcut([.control, .capsLock], time: 4, characters: "V", ignoringModifiers: "V"))
        try expect(pasteCalls == 3, "Caps Lock does not disable hover paste")
        controller.robot.keyDown(with: shortcut(.control, time: 5, characters: "\u{16}", ignoringModifiers: "\u{16}"))
        try expect(pasteCalls == 4, "Control character representation also pastes")
        for flags: NSEvent.ModifierFlags in [[], [.shift, .control], [.option, .command], [.command, .control]] {
            try expect(!RobotView.isPasteShortcut(shortcut(flags, time: 6)), "Unrelated modifier combination does not paste")
        }
        controller.robot.onPaste = pasteHandler
        // openDaily is the exact handler wired to RobotView's double-click action.
        controller.openDaily()
        try expect(controller.board.isVisible && !controller.bin.isVisible, "Double-click handler opens Daily and hides robot")
        try expect(state.route == .daily, "Double-click handler selects the Daily route")
        try expect(screen.visibleFrame.contains(controller.board.frame), "Daily panel is constrained to its active visible screen")
        controller.pollPointer(at: away, now: clock.addingTimeInterval(30))
        try expect(controller.board.isVisible && !controller.bin.isVisible, "Daily remains usable after pointer leaves its corner")
        controller.dismiss()
        try expect(ownedWindows.filter(\.isVisible).isEmpty, "Dismissal returns to zero visible DaBin windows")
        controller.pollPointer(at: point, now: clock.addingTimeInterval(31))
        try expect(!controller.bin.isVisible, "Dismissal suppresses reappearance until pointer exits the corner")
        controller.pollPointer(at: away, now: clock.addingTimeInterval(32))
        controller.pollPointer(at: point, now: clock.addingTimeInterval(33))
        try expect(controller.bin.isVisible, "Returning to the corner after exit reveals robot again")
        controller.dismiss()

        let negativeDisplay = NSRect(x: -1920, y: -300, width: 1920, height: 1080)
        let negativeVisible = NSRect(x: -1920, y: -280, width: 1920, height: 1040)
        for corner in ScreenCorner.allCases {
            let point = cornerPoint(corner, frame: negativeDisplay)
            try expect(CornerGeometry.corner(at: point, in: negativeDisplay) == corner, "Negative-screen coordinates detect \(corner.rawValue)")
            let robot = CornerGeometry.robotFrame(corner: corner, visible: negativeVisible)
            try expect(negativeVisible.contains(robot), "Negative-screen \(corner.rawValue) robot stays inside visible area")
            let panel = CornerGeometry.panelFrame(robot: robot, visible: negativeVisible, corner: corner)
            try expect(negativeVisible.contains(panel), "Negative-screen \(corner.rawValue) Daily stays inside visible area")
            let replacementDisplay = NSRect(x: 0, y: 24, width: 1280, height: 696)
            let recovered = CornerGeometry.panelFrame(robot: robot, visible: replacementDisplay, corner: corner)
            try expect(replacementDisplay.contains(recovered), "Removed-display \(corner.rawValue) geometry clamps to remaining screen")
        }
        try expect(CornerGeometry.corner(at: NSPoint(x: -1000, y: 200), in: negativeDisplay) == nil,
                   "Display interior does not activate a corner")
        try expect(CornerGeometry.corner(at: NSPoint(x: -3000, y: -300), in: negativeDisplay) == nil,
                   "A point outside a display does not activate that display")
        let tinyVisible = NSRect(x: -50, y: -50, width: 180, height: 180)
        let clamped = CornerGeometry.panelFrame(robot: NSRect(x: 9000, y: -9000, width: 72, height: 88),
                                                visible: tinyVisible, corner: .topRight, preferredHeight: 500)
        try expect(tinyVisible.contains(clamped), "Oversized/offscreen Daily geometry clamps to a small replacement display")

        // Exercise the same drag lifecycle used by the native header, without
        // synthesizing OS mouse events or changing the user's window preferences.
        controller.openDaily()
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        func dragSurface(in view: NSView) -> WindowDragHandleView? {
            if let handle = view as? WindowDragHandleView { return handle }
            for child in view.subviews { if let handle = dragSurface(in: child) { return handle } }
            return nil
        }
        guard let handle = controller.board.contentView.flatMap({ dragSurface(in: $0) }) else {
            throw NSError(domain: "DaBinWindowTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Native header drag surface is mounted"])
        }
        try expect(handle.bounds.width > 30 && handle.bounds.height == 30, "Native header has a usable drag surface")
        func dragEvent(_ type: NSEvent.EventType, point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 10,
                              windowNumber: controller.board.windowNumber, context: nil,
                              eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        let chosenTopLeft = NSPoint(x: screen.visibleFrame.minX + 40, y: screen.visibleFrame.maxY - 35)
        let initialFrame = controller.board.frame
        let pointer = NSPoint(x: 50, y: initialFrame.height - 30)
        handle.mouseDown(with: dragEvent(.leftMouseDown, point: pointer))
        handle.mouseDragged(with: dragEvent(.leftMouseDragged,
            point: NSPoint(x: pointer.x + chosenTopLeft.x - initialFrame.minX,
                          y: pointer.y + chosenTopLeft.y - initialFrame.maxY)))
        let draggedFrame = controller.board.frame
        try expect(draggedFrame.minX == chosenTopLeft.x && draggedFrame.maxY == chosenTopLeft.y,
                   "Header mouse events move the actual native panel to the pointer destination")
        state.showSettings()
        controller.finishBoardDragIfReleased(pressedMouseButtons: 1)
        controller.showBoard()
        try expect(controller.board.frame == draggedFrame, "Content changes cannot snap the board during a native drag")
        handle.mouseUp(with: dragEvent(.leftMouseUp, point: pointer))
        controller.finishBoardDragIfReleased(pressedMouseButtons: 0)
        let expectedSettings = CornerGeometry.movedPanelFrame(topLeft: chosenTopLeft, visible: screen.visibleFrame, preferredHeight: 430)
        try expect(controller.board.frame == expectedSettings, "Release keeps the chosen position and applies pending height changes")
        try expect(placementDefaults.array(forKey: CornerController.boardPlacementKey) as? [Double] == [Double(chosenTopLeft.x), Double(chosenTopLeft.y)], "Manual board position is saved separately from captures")
        state.openNewTask()
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        try expect(controller.board.frame.minX == chosenTopLeft.x && controller.board.frame.maxY == chosenTopLeft.y, "Task composer preserves the moved header position")
        try expect(controller.board.frame.height == 310, "Moved board retains compact route sizing")
        state.newTaskDraft.reminderEnabled = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        try expect(controller.board.frame.height == 370 && controller.board.frame.maxY == chosenTopLeft.y,
                   "Live reminder expansion resizes below the moved header without jumping to a corner")
        state.cancelNewTask()
        controller.dismiss()
        controller.openDaily()
        try expect(controller.board.frame.minX == chosenTopLeft.x && controller.board.frame.maxY == chosenTopLeft.y, "Hide and reopen retain the user position")
        controller.dismiss()

        let reopenedState = AppState(store: store, previews: previews, reminders: reminders)
        let reopened = CornerController(state: reopenedState, input: InputService(store: store), placementDefaults: placementDefaults)
        reopened.openDaily()
        try expect(reopened.board.frame.minX == chosenTopLeft.x && reopened.board.frame.maxY == chosenTopLeft.y, "A new controller restores placement from local preferences")
        if screens.count > 1 {
            let otherScreen = screens[1]
            let otherPoint = NSPoint(x: otherScreen.visibleFrame.minX + 40, y: otherScreen.visibleFrame.maxY - 35)
            reopenedState.onBoardDragStarted?()
            reopened.board.setFrameTopLeftPoint(otherPoint)
            reopened.finishBoardDragIfReleased(pressedMouseButtons: 0)
            reopenedState.showSettings()
            reopened.showBoard()
            try expect(otherScreen.visibleFrame.contains(reopened.board.frame), "Dragging to another display keeps subsequent routes on that display")
            try expect(reopened.board.frame.minX == otherPoint.x && reopened.board.frame.maxY == otherPoint.y, "Second-display placement preserves the header anchor")
        }
        reopened.dismiss()
        let recoveredPosition = CornerGeometry.movedPanelFrame(topLeft: NSPoint(x: -9000, y: 9000), visible: screen.visibleFrame, preferredHeight: 500)
        try expect(screen.visibleFrame.contains(recoveredPosition), "Removed-display saved coordinates recover onto an available screen")
        let smallMoved = CornerGeometry.movedPanelFrame(topLeft: NSPoint(x: 9000, y: -9000), visible: tinyVisible, preferredHeight: 500)
        try expect(tinyVisible.contains(smallMoved), "Saved position fits a small replacement display")
        placementDefaults.set(["invalid", "position"], forKey: CornerController.boardPlacementKey)
        let invalidState = AppState(store: store, previews: previews, reminders: reminders)
        let invalidPlacement = CornerController(state: invalidState, input: InputService(store: store), placementDefaults: placementDefaults)
        invalidPlacement.openDaily()
        try expect(screens.contains { $0.visibleFrame.contains(invalidPlacement.board.frame) }, "Malformed saved placement safely falls back to a visible corner")
        invalidPlacement.dismiss()
        try expect(store.captures.isEmpty && !input.isBusy, "Window testing creates no captures or paste operations")
        try expect(notificationClient.permissionRequests == 0 && notificationClient.additions == 0,
                   "Window testing requests no real or fake notification permission/schedules")
        try expect(ownedWindows.filter(\.isVisible).isEmpty, "Window checks finish with every owned panel hidden")
        if !failures.isEmpty {
            fputs("FAIL: \(failures.count) of \(checks) window checks failed across \(screens.count) real screen(s). All independent checks were attempted.\n", stderr)
            exit(1)
        }
        print("PASS: \(checks) window checks across \(screens.count) real screen(s); no cursor synthesis, clipboard access, network or notification permission.")
    }
}
