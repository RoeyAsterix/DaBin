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
        let robotPlacement = RobotPlacementSettings(defaults: placementDefaults)
        let state = AppState(store: store, previews: previews, reminders: reminders,
                             robotPlacement: robotPlacement)
        let input = InputService(store: store, stagingRoot: root.appendingPathComponent("Promises"))
        let theme = ThemeSettings(defaults: placementDefaults, systemDarkMode: false)
        let controller = CornerController(state: state, input: input, placementDefaults: placementDefaults,
                                          theme: theme, animateRobotTransitions: false)
        defer {
            controller.dismiss()
            controller.bin.orderOut(nil)
            controller.board.orderOut(nil)
            previews.cancelNetwork()
        }
        let ownedWindows = [controller.bin, controller.board]
        try expect(controller.board.appearance?.name == .aqua
                   && controller.captureHostingView.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua,
                   "The nested robot-frame host adopts the explicit light theme before presentation")
        theme.setDarkMode(true)
        try expect(controller.board.appearance?.name == .darkAqua
                   && controller.captureHostingView.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua,
                   "Changing theme updates both native window and nested hosting view immediately")
        theme.setDarkMode(false)
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

        let syntheticFrame = NSRect(x: 2560, y: 458, width: 1512, height: 982)
        let syntheticVisible = NSRect(x: 2560, y: 458, width: 1512, height: 950)
        let syntheticLeft = NSRect(x: 2560, y: 1408, width: 663, height: 32)
        let syntheticRight = NSRect(x: 3408, y: 1408, width: 664, height: 32)
        let syntheticIsland = CornerGeometry.cameraIslandRect(frame: syntheticFrame, safeAreaTop: 32,
                                                              auxiliaryLeft: syntheticLeft,
                                                              auxiliaryRight: syntheticRight)
        try expect(syntheticIsland == NSRect(x: 3223, y: 1408, width: 185, height: 32),
                   "Camera island is derived from the gap between macOS auxiliary menu-bar areas")
        if let syntheticIsland {
            let islandRobot = CornerGeometry.robotFrame(cameraIsland: syntheticIsland, visible: syntheticVisible)
            try expect(syntheticVisible.contains(islandRobot) && abs(islandRobot.midX - syntheticIsland.midX) <= 0.5,
                       "Camera-island robot is centered immediately below the cutout and stays visible")
            try expect(islandRobot.size == NSSize(width: 232, height: 150)
                       && islandRobot.maxY == syntheticIsland.minY,
                       "Manual island choreography has a wide stage attached to the real underside")
            let islandInteraction = CornerGeometry.robotInteractionFrame(in: islandRobot, target: .cameraIsland)
            let islandBody = CornerGeometry.robotBodyFrame(in: islandRobot, target: .cameraIsland)
            try expect(islandInteraction.size == NSSize(width: 128, height: 130)
                       && islandInteraction.midX == islandRobot.midX
                       && islandInteraction.maxY == islandRobot.maxY
                       && islandRobot.contains(islandInteraction),
                       "Island clicks and drops use a central top-aligned target inside the swept stage")
            try expect(islandBody.size == NSSize(width: 88, height: 108)
                       && islandBody.maxY == islandRobot.maxY - 8
                       && islandInteraction.contains(islandBody),
                       "Board expansion starts at the visible central body rather than the full stage")
            let islandBoard = CornerGeometry.panelFrame(robot: islandRobot, visible: syntheticVisible,
                                                        target: .cameraIsland)
            try expect(syntheticVisible.contains(islandBoard) && abs(islandBoard.midX - syntheticIsland.midX) <= 0.5,
                       "Camera-island Daily opens below the centered robot and stays on screen")
        }
        let smallIslandStage = NSRect(x: -80, y: -40, width: 60, height: 70)
        try expect(CornerGeometry.robotInteractionFrame(in: smallIslandStage, target: .cameraIsland) == smallIslandStage
                   && smallIslandStage.contains(CornerGeometry.robotBodyFrame(in: smallIslandStage, target: .cameraIsland)),
                   "Constrained stages keep both hit and transition geometry within their bounds")
        try expect(CornerGeometry.cameraIslandRect(frame: syntheticFrame, safeAreaTop: 0,
                                                   auxiliaryLeft: nil, auxiliaryRight: nil) == nil,
                   "A display without safe-area and auxiliary data is not guessed to have an island")
        try expect(CornerGeometry.cameraIslandRect(frame: syntheticFrame, safeAreaTop: 32,
                                                   auxiliaryLeft: syntheticRight,
                                                   auxiliaryRight: syntheticLeft) == nil,
                   "Overlapping or reversed auxiliary regions cannot form a camera island")
        let negativeNotchFrame = NSRect(x: -1728, y: -200, width: 1728, height: 1117)
        let negativeNotchVisible = NSRect(x: -1728, y: -200, width: 1728, height: 1085)
        let negativeLeft = NSRect(x: -1728, y: 885, width: 770, height: 32)
        let negativeRight = NSRect(x: -770, y: 885, width: 770, height: 32)
        let negativeIsland = CornerGeometry.cameraIslandRect(frame: negativeNotchFrame, safeAreaTop: 32,
                                                             auxiliaryLeft: negativeLeft,
                                                             auxiliaryRight: negativeRight)
        try expect(negativeIsland == NSRect(x: -958, y: 885, width: 188, height: 32),
                   "Camera-island geometry supports displays with negative coordinates")
        if let negativeIsland {
            try expect(negativeNotchVisible.contains(CornerGeometry.robotFrame(cameraIsland: negativeIsland,
                                                                               visible: negativeNotchVisible)),
                       "Negative-coordinate island robot remains inside its display")
        }

        if let islandScreen = screens.first(where: { CornerGeometry.cameraIslandRect(on: $0) != nil }),
           let trigger = CornerGeometry.cameraIslandTriggerFrame(on: islandScreen),
           let island = CornerGeometry.cameraIslandRect(on: islandScreen) {
            robotPlacement.setHome(.cameraIsland)
            let islandAway = NSPoint(x: islandScreen.visibleFrame.minX + 40,
                                     y: islandScreen.visibleFrame.midY)
            controller.pollPointer(at: islandAway, now: clock.addingTimeInterval(1))
            controller.pollPointer(at: NSPoint(x: trigger.midX, y: trigger.minY + 2),
                                   now: clock.addingTimeInterval(2))
            try expect(controller.bin.isVisible, "Camera-island preference reveals the robot from the top center")
            try expect(controller.bin.frame == CornerGeometry.robotFrame(cameraIsland: island,
                                                                          visible: islandScreen.visibleFrame),
                       "Live island reveal uses the detected cutout geometry")
            let transparentEdge = NSPoint(x: controller.bin.frame.minX + 3, y: controller.bin.frame.midY)
            controller.pollPointer(at: transparentEdge, now: clock.addingTimeInterval(2.1), pressedMouseButtons: 0)
            try expect(controller.bin.isVisible && controller.bin.ignoresMouseEvents && !controller.bin.isKeyWindow,
                       "The island animation margins pass clicks through and never take hover focus")
            let islandBodyPoint = NSPoint(x: controller.bin.frame.midX, y: controller.bin.frame.maxY - 60)
            controller.pollPointer(at: islandBodyPoint, now: clock.addingTimeInterval(2.2), pressedMouseButtons: 0)
            try expect(!controller.bin.ignoresMouseEvents && controller.bin.isKeyWindow,
                       "The central island robot remains an immediate hover-paste target")
            controller.robot.onDragState?(true)
            controller.pollPointer(at: transparentEdge, now: clock.addingTimeInterval(2.3), pressedMouseButtons: 1)
            try expect(!controller.bin.ignoresMouseEvents && controller.bin.isVisible,
                       "An accepted drag retains its destination until AppKit finishes the transfer")
            controller.robot.onDragState?(false)
            controller.pollPointer(at: transparentEdge, now: clock.addingTimeInterval(2.4), pressedMouseButtons: 0)
            try expect(controller.bin.ignoresMouseEvents && !controller.bin.isKeyWindow,
                       "Ending a drag restores transparent island margins and releases hover focus")
            controller.dismiss()
            controller.pollPointer(at: islandAway, now: clock.addingTimeInterval(3))
        }
        if let external = screens.first(where: { CornerGeometry.cameraIslandRect(on: $0) == nil }) {
            robotPlacement.setHome(.cameraIsland)
            let externalCorner = cornerPoint(.topRight, frame: external.frame)
            controller.pollPointer(at: NSPoint(x: external.visibleFrame.midX, y: external.visibleFrame.midY),
                                   now: clock.addingTimeInterval(4))
            controller.pollPointer(at: externalCorner, now: clock.addingTimeInterval(5))
            try expect(controller.bin.isVisible,
                       "A display without an island keeps corner reveal while island mode is selected")
            try expect(controller.bin.frame == CornerGeometry.robotFrame(corner: .topRight,
                                                                          visible: external.visibleFrame),
                       "External-display fallback uses normal corner geometry")
        }
        robotPlacement.setHome(.corners)

        let screen = screens[0]
        let corner = ScreenCorner.bottomRight
        let point = cornerPoint(corner, frame: screen.frame)
        let away = NSPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY)
        clock = clock.addingTimeInterval(3)
        controller.pollPointer(at: away, now: clock.addingTimeInterval(-0.1))
        controller.pollPointer(at: point, now: clock)
        try expect(controller.bin.isVisible, "Robot visible before opening Daily")
        try expect(!controller.bin.ignoresMouseEvents && !controller.robot.isIslandStage,
                   "Returning to a normal corner restores the compact interactive destination")
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
        // The Activity action selects Daily. Opening the buddy then resumes it.
        state.openDaily()
        controller.openDaily()
        try expect(controller.board.isVisible && !controller.bin.isVisible, "Double-click handler opens Daily and hides robot")
        try expect(state.route == .daily, "Opening the buddy preserves the explicitly selected Daily route")
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
        func dragSurfaces(in view: NSView) -> [WindowDragHandleView] {
            var result = view as? WindowDragHandleView == nil ? [] : [view as! WindowDragHandleView]
            for child in view.subviews { result.append(contentsOf: dragSurfaces(in: child)) }
            return result
        }
        let handles = controller.board.contentView.map(dragSurfaces(in:)) ?? []
        guard let logoHandle = handles.first(where: { abs($0.bounds.width - 68) <= 0.5 }),
              let flexibleHandle = handles.filter({ $0 !== logoHandle }).max(by: { $0.bounds.width < $1.bounds.width }) else {
            throw NSError(domain: "DaBinWindowTests", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Logo and flexible native header drag surfaces are mounted"])
        }
        try expect(logoHandle.bounds.width == 68 && logoHandle.bounds.height == 28,
                   "The labeled header keeps the complete 68-by-28 logo available for native dragging")
        try expect(handles.count >= 2 && flexibleHandle !== logoHandle
                   && flexibleHandle.bounds.width >= 28 && flexibleHandle.bounds.height >= 28,
                   "The blank first-row header area exposes a separate visible drag grip")
        func dragEvent(_ type: NSEvent.EventType, point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 10,
                              windowNumber: controller.board.windowNumber, context: nil,
                              eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        let chosenTopLeft = NSPoint(x: screen.visibleFrame.minX + 40, y: screen.visibleFrame.maxY - 35)
        let initialFrame = controller.board.frame
        let pointer = NSPoint(x: 50, y: initialFrame.height - 30)
        flexibleHandle.mouseDown(with: dragEvent(.leftMouseDown, point: pointer))
        flexibleHandle.mouseDragged(with: dragEvent(.leftMouseDragged,
            point: NSPoint(x: pointer.x + chosenTopLeft.x - initialFrame.minX,
                          y: pointer.y + chosenTopLeft.y - initialFrame.maxY)))
        let draggedFrame = controller.board.frame
        try expect(draggedFrame.minX == chosenTopLeft.x && draggedFrame.maxY == chosenTopLeft.y,
                   "Header mouse events move the actual native panel to the pointer destination")
        state.showSettings()
        controller.finishBoardDragIfReleased(pressedMouseButtons: 1)
        controller.showBoard()
        try expect(controller.board.frame == draggedFrame, "Content changes cannot snap the board during a native drag")
        flexibleHandle.mouseUp(with: dragEvent(.leftMouseUp, point: pointer))
        controller.finishBoardDragIfReleased(pressedMouseButtons: 0)
        let expectedSettings = CornerGeometry.movedPanelFrame(topLeft: chosenTopLeft, visible: screen.visibleFrame, preferredHeight: 670)
        try expect(controller.board.frame == expectedSettings, "Release keeps the chosen position and applies pending height changes")
        try expect(placementDefaults.array(forKey: CornerController.boardPlacementKey) as? [Double] == [Double(chosenTopLeft.x), Double(chosenTopLeft.y)], "Manual board position is saved separately from captures")
        state.openNewTask()
        let taskComposerResizeDeadline = Date().addingTimeInterval(1.5)
        while controller.board.frame.height != 490 && Date() < taskComposerResizeDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        try expect(controller.board.frame.minX == chosenTopLeft.x && controller.board.frame.maxY == chosenTopLeft.y, "Task composer preserves the moved header position")
        try expect(controller.board.frame.height == 490, "Moved task composer reserves 440 points of content plus its outer frame; actual=\(controller.board.frame)")
        state.newTaskDraft.reminderEnabled = true
        // The native resize follows a debounced model notification; wait for
        // that observable endpoint rather than assuming a fixed busy-run delay.
        let reminderResizeDeadline = Date().addingTimeInterval(1.5)
        while controller.board.frame.height != 550 && Date() < reminderResizeDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        try expect(controller.board.frame.height == 550 && controller.board.frame.maxY == chosenTopLeft.y,
                   "Live reminder expansion resizes below the moved header without jumping to a corner; actual=\(controller.board.frame)")
        state.cancelNewTask()
        controller.dismiss()
        controller.openDaily()
        try expect(controller.board.frame.minX == chosenTopLeft.x && controller.board.frame.maxY == chosenTopLeft.y, "Hide and reopen retain the user position")
        controller.dismiss()

        let reopenedState = AppState(store: store, previews: previews, reminders: reminders)
        let reopened = CornerController(state: reopenedState, input: InputService(store: store), placementDefaults: placementDefaults, animateRobotTransitions: false)
        let reopenedOrigin = reopenedState.route
        reopened.openDaily()
        try expect(reopenedState.route == reopenedOrigin, "A new controller opens the current view without resetting navigation")
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
        reopened.openDaily()
        let resizeScreen = reopened.board.screen ?? screen
        let chosenSize = NSSize(width: min(740, resizeScreen.visibleFrame.width), height: min(650, resizeScreen.visibleFrame.height))
        reopened.resizeBoardFromUser(to: NSRect(x: resizeScreen.visibleFrame.minX + 20,
            y: resizeScreen.visibleFrame.maxY - chosenSize.height, width: chosenSize.width, height: chosenSize.height))
        reopened.finishBoardResize()
        let userFrame = reopened.board.frame
        reopenedState.showSettings()
        reopened.showBoard(immediate: true)
        try expect(reopened.board.frame == userFrame,
                   "A manually stretched board keeps its chosen dimensions across routes")
        try expect(placementDefaults.array(forKey: CornerController.boardSizeKey) as? [Double]
                   == [Double(chosenSize.width), Double(chosenSize.height)],
                   "User-resized dimensions persist separately from the archive")
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let keyWindow = NSApp.keyWindow
        let presentedToUser = reopened.board.isVisible && !NSApp.isHidden
            && reopened.board.occlusionState.contains(.visible)
        let previousCelebrations = reopened.appFrame.taskCelebrationCount
        reopened.celebrateTaskCompletion()
        try expect(reopened.appFrame.taskCelebrationCount == previousCelebrations + (presentedToUser ? 1 : 0),
                   presentedToUser ? "A visible task completion celebrates in the existing frame"
                       : "An occluded task completion does not animate behind another surface or the lock screen")
        try expect(NSApp.keyWindow === keyWindow, "Task completion always preserves keyboard focus")
        let savedSizeBeforeExpansion = placementDefaults.array(forKey: CornerController.boardSizeKey) as? [Double]
        let savedPositionBeforeExpansion = placementDefaults.array(forKey: CornerController.boardPlacementKey) as? [Double]
        reopened.toggleExpandedWindow()
        try expect(reopened.board.frame == resizeScreen.visibleFrame,
                   "Expand fills the safe area on the interaction display without a new Space")
        try expect(placementDefaults.array(forKey: CornerController.boardSizeKey) as? [Double] == savedSizeBeforeExpansion
                   && placementDefaults.array(forKey: CornerController.boardPlacementKey) as? [Double] == savedPositionBeforeExpansion,
                   "Expansion never replaces the saved normal size or position with maximized geometry")
        reopenedState.openLibrary()
        reopenedState.libraryProject = "Window movement fixture"
        reopenedState.filter = .files
        reopened.showBoard(immediate: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        try expect(reopened.board.frame == resizeScreen.visibleFrame,
                   "Changing routes and content filters keeps the expanded safe-area frame")
        reopenedState.performSearchCommand()
        reopenedState.query = "resume this client"
        reopenedState.searchProject = "Window movement fixture"
        reopenedState.filter = .text
        reopened.showBoard(immediate: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        try expect(reopened.board.frame == resizeScreen.visibleFrame
                   && placementDefaults.array(forKey: CornerController.boardSizeKey) as? [Double] == savedSizeBeforeExpansion
                   && placementDefaults.array(forKey: CornerController.boardPlacementKey) as? [Double] == savedPositionBeforeExpansion,
                   "Expanded search updates preserve both the expanded frame and normal persisted geometry")
        reopened.toggleExpandedWindow()
        try expect(reopened.board.frame == userFrame,
                   "The second expand action restores the exact user frame even after route and filter changes")
        try expect(reopenedState.route == .search && reopenedState.query == "resume this client"
                   && reopenedState.searchProject == "Window movement fixture" && reopenedState.filter == .text,
                   "Expanding and restoring keeps the search, project and content filter")

        // Dragging a maximized board should restore normal dimensions under the
        // pointer before moving. These events are sent only to our own header.
        reopened.toggleExpandedWindow()
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        let expandedHandles = reopened.board.contentView.map(dragSurfaces(in:)) ?? []
        guard let expandedHandle = expandedHandles.max(by: { $0.bounds.width < $1.bounds.width }) else {
            throw NSError(domain: "DaBinWindowTests", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Expanded board keeps its native header drag surface"])
        }
        func reopenedDragEvent(_ type: NSEvent.EventType, screenPoint: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: reopened.board.convertPoint(fromScreen: screenPoint),
                              modifierFlags: [], timestamp: 20, windowNumber: reopened.board.windowNumber,
                              context: nil, eventNumber: 2, clickCount: 1, pressure: 1)!
        }
        let dragPointer = NSEvent.mouseLocation
        expandedHandle.mouseDown(with: reopenedDragEvent(.leftMouseDown, screenPoint: dragPointer))
        let normalDragStart = reopened.board.frame
        try expect(normalDragStart.size == userFrame.size && normalDragStart != resizeScreen.visibleFrame,
                   "Starting a header drag restores the expanded board to its normal movable dimensions")
        let requestedMoved = NSRect(x: resizeScreen.visibleFrame.minX + 65,
                                   y: resizeScreen.visibleFrame.maxY - userFrame.height - 70,
                                   width: userFrame.width, height: userFrame.height)
        let expectedMoved = BoardResizeGeometry.fitted(requestedMoved, visible: resizeScreen.visibleFrame)
        let destinationPointer = NSPoint(x: dragPointer.x + expectedMoved.minX - normalDragStart.minX,
                                        y: dragPointer.y + expectedMoved.minY - normalDragStart.minY)
        expandedHandle.mouseDragged(with: reopenedDragEvent(.leftMouseDragged, screenPoint: destinationPointer))
        try expect(reopened.board.frame == expectedMoved,
                   "An expanded-window header drag moves the real normal-sized panel to a new location")
        expandedHandle.mouseUp(with: reopenedDragEvent(.leftMouseUp, screenPoint: destinationPointer))
        reopened.finishBoardDragIfReleased(pressedMouseButtons: 0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        try expect(reopened.board.frame == expectedMoved
                   && placementDefaults.array(forKey: CornerController.boardPlacementKey) as? [Double]
                       == [Double(expectedMoved.minX), Double(expectedMoved.maxY)]
                   && placementDefaults.array(forKey: CornerController.boardSizeKey) as? [Double]
                       == [Double(userFrame.width), Double(userFrame.height)],
                   "Releasing an expanded-window drag persists the new normal position without snapping or saving full-screen size")
        reopened.dismiss()
        reopened.openDaily()
        try expect(reopened.board.frame == expectedMoved && reopenedState.route == .search
                   && reopenedState.query == "resume this client" && reopenedState.searchProject == "Window movement fixture"
                   && reopenedState.libraryProject == "Window movement fixture" && reopenedState.filter == .text,
                   "Reopening the buddy restores the moved window and the complete interrupted search/project context")
        reopened.dismiss()
        reopened.robot.onDaily?()
        try expect(reopened.board.frame == expectedMoved && reopenedState.route == .search
                   && reopenedState.query == "resume this client" && reopenedState.filter == .text,
                   "The actual robot open callback also resumes context instead of resetting to a corner or Daily")
        reopened.dismiss()
        let completedCelebrations = reopened.appFrame.taskCelebrationCount
        reopened.celebrateTaskCompletion()
        try expect(!reopened.board.isVisible && reopened.appFrame.taskCelebrationCount == completedCelebrations,
                   "A hidden completion never brings the board back")
        let recoveredPosition = CornerGeometry.movedPanelFrame(topLeft: NSPoint(x: -9000, y: 9000), visible: screen.visibleFrame, preferredHeight: 500)
        try expect(screen.visibleFrame.contains(recoveredPosition), "Removed-display saved coordinates recover onto an available screen")
        let smallMoved = CornerGeometry.movedPanelFrame(topLeft: NSPoint(x: 9000, y: -9000), visible: tinyVisible, preferredHeight: 500)
        try expect(tinyVisible.contains(smallMoved), "Saved position fits a small replacement display")
        placementDefaults.set(["invalid", "position"], forKey: CornerController.boardPlacementKey)
        let invalidState = AppState(store: store, previews: previews, reminders: reminders)
        let invalidPlacement = CornerController(state: invalidState, input: InputService(store: store), placementDefaults: placementDefaults, animateRobotTransitions: false)
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
