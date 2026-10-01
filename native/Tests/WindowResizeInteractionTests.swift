import AppKit
import Foundation

@MainActor private final class ResizeReminderClient: ReminderNotificationClient {
    private(set) var permissionRequests = 0
    private(set) var additions = 0
    func authorization() async -> ReminderAuthorization { .undetermined }
    func requestAuthorization() async throws -> Bool { permissionRequests += 1; return false }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { additions += 1 }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}

/// Events are delivered directly to this process's real frame view. This suite
/// never posts system input, moves the cursor, opens user archives, or accesses
/// the general clipboard. --preview leaves only the isolated, empty QA board.
@main private enum WindowResizeInteractionTests {
    @MainActor private static var checks = 0

    @MainActor private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard condition() else {
            throw NSError(domain: "WindowResizeInteractionTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    @MainActor private static func event(_ type: NSEvent.EventType, at screenPoint: CGPoint,
                                        in window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: window.convertPoint(fromScreen: screenPoint),
            modifierFlags: [], timestamp: 10, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
    }

    @MainActor private static func screenPoint(_ point: CGPoint, in view: NSView) -> CGPoint {
        view.window!.convertPoint(toScreen: view.convert(point, to: nil))
    }

    private static func area(_ frame: CGRect) -> CGFloat {
        frame.isNull ? 0 : max(0, frame.width) * max(0, frame.height)
    }

    @MainActor private static func baseFrame(on screen: NSScreen) -> CGRect {
        let visible = screen.visibleFrame
        let width = min(600, visible.width - 120)
        let height = min(560, visible.height - 120)
        return CGRect(x: visible.midX - width / 2, y: visible.midY - height / 2,
                      width: width, height: height)
    }

    @MainActor private static func settle() {
        let end = Date().addingTimeInterval(0.10)
        while Date() < end {
            _ = RunLoop.main.run(mode: .default, before: min(end, Date().addingTimeInterval(0.01)))
        }
    }

    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("DaBin-Resize-QA-\(UUID())")
        let suite = "DaBinResizeQA.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? files.removeItem(at: root) }
        let store = try CaptureStore(root: root)
        let previews = PreviewService(store: store, defaults: defaults)
        let reminders = ResizeReminderClient()
        let input = InputService(store: store, stagingRoot: root.appendingPathComponent("Promises"))
        let state = AppState(store: store, previews: previews,
            reminders: ReminderService(store: store, client: reminders),
            robotPlacement: RobotPlacementSettings(defaults: defaults),
            captureClipboard: CaptureClipboardService(writer: { _ in true }),
            quickAccessSettings: QuickAccessSettings(defaults: defaults), manualInput: input)
        let controller = CornerController(state: state, input: input, placementDefaults: defaults,
            theme: ThemeSettings(defaults: defaults, systemDarkMode: false),
            animateRobotTransitions: false, robotReduceMotion: { true })
        defer { controller.shutdown(); previews.shutdown() }
        let screens = NSScreen.screens.filter {
            $0.visibleFrame.width >= BoardResizeGeometry.minimumSize.width + 120
                && $0.visibleFrame.height >= BoardResizeGeometry.minimumSize.height + 120
        }
        guard let screen = screens.first else {
            throw NSError(domain: "WindowResizeInteractionTests", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "A display with room around the minimum window size is required"])
        }
        controller.reveal(on: screen, corner: .topRight)
        state.openDaily()
        controller.openDaily()
        controller.board.title = "DaBin resize QA"
        controller.resizeBoardFromUser(to: baseFrame(on: screen))
        controller.finishBoardResize()
        settle()

        if CommandLine.arguments.contains("--preview") || Bundle.main.bundleIdentifier == "com.dabin.mac.qa.resize" {
            print("PREVIEW: isolated empty DaBin resize QA window; archive=\(root.path)")
            fflush(stdout)
            app.run()
            return
        }

        let frame = controller.appFrame
        let board = controller.board
        let initial = baseFrame(on: screen)
        let corners: [BoardResizeGeometry.Edge] = [[.left, .top], [.right, .top], [.left, .bottom], [.right, .bottom]]
        for (index, corner) in corners.enumerated() {
            state.openDaily()
            controller.resizeBoardFromUser(to: initial)
            controller.finishBoardResize()
            frame.layoutSubtreeIfNeeded()
            let content = RobotAppFrameView.contentRect(in: frame.bounds)
            let local = CGPoint(x: corner.contains(.left) ? content.minX : content.maxX,
                                y: corner.contains(.top) ? content.maxY : content.minY)
            let start = screenPoint(local, in: frame)
            let change = CGPoint(x: corner.contains(.left) ? -25 : 25,
                                 y: corner.contains(.top) ? 20 : -20)
            let finish = CGPoint(x: start.x + change.x, y: start.y + change.y)
            let expected = BoardResizeGeometry.resized(initial, edge: corner, delta: change, visible: screen.visibleFrame)
            let hitPoint = frame.superview.map { frame.convert(local, to: $0) } ?? local
            try expect(frame.hitTest(hitPoint) === frame, "Visible corner \(index) is a native resize target")
            frame.mouseDown(with: event(.leftMouseDown, at: start, in: board))
            frame.mouseDragged(with: event(.leftMouseDragged, at: finish, in: board))
            try expect(board.frame == expected && expected.width > initial.width && expected.height > initial.height,
                       "Corner \(index) changes both dimensions through actual native drag events")
            try expect((corner.contains(.left) ? board.frame.maxX == initial.maxX : board.frame.minX == initial.minX)
                       && (corner.contains(.top) ? board.frame.minY == initial.minY : board.frame.maxY == initial.maxY),
                       "Corner \(index) retains its opposite anchor")
            if index == 0 {
                state.showSettings()
                settle()
                controller.showBoard(immediate: true)
                try expect(board.frame == expected, "A route change during resize cannot reposition or resize the active gesture")
            }
            frame.mouseUp(with: event(.leftMouseUp, at: finish, in: board))
            try expect(defaults.array(forKey: CornerController.boardSizeKey) as? [Double]
                       == [Double(expected.width), Double(expected.height)], "Corner \(index) persists the released size")
            try expect(defaults.array(forKey: CornerController.boardPlacementKey) as? [Double]
                       == [Double(expected.minX), Double(expected.maxY)], "Corner \(index) persists its final top-left position")
            let released = board.frame
            frame.mouseDragged(with: event(.leftMouseDragged,
                at: CGPoint(x: finish.x + 50, y: finish.y + 50), in: board))
            try expect(board.frame == released, "Released corner \(index) ignores stale drag events")
        }

        // Deliver a continuous chrome drag without yielding to the fallback
        // OS-button polling timer: no physical mouse button is held by tests.
        state.openDaily()
        controller.resizeBoardFromUser(to: initial)
        controller.finishBoardResize()
        frame.layoutSubtreeIfNeeded()
        let band = BoardResizeGeometry.dragRegion(in: frame.bounds)
        let start = screenPoint(CGPoint(x: band.midX, y: band.midY), in: frame)
        let finish = CGPoint(x: start.x + 24, y: start.y - 18)
        frame.mouseDown(with: event(.leftMouseDown, at: start, in: board))
        frame.mouseDragged(with: event(.leftMouseDragged, at: finish, in: board))
        let moved = initial.offsetBy(dx: 24, dy: -18)
        try expect(board.frame == moved, "The robot's top chrome moves the actual window in both axes")
        state.showSettings()
        controller.showBoard(immediate: true)
        try expect(board.frame == moved, "A route change during top-chrome drag stays under pointer control")
        frame.mouseUp(with: event(.leftMouseUp, at: finish, in: board))
        settle()
        try expect(board.frame == moved && state.route == .settings,
                   "Releasing a chrome drag preserves the moved frame and requested route")
        try expect(defaults.array(forKey: CornerController.boardPlacementKey) as? [Double]
                   == [Double(moved.minX), Double(moved.maxY)], "Top-chrome release persists the moved position")

        try verifyDisplayCancellation(controller: controller, screen: screen)
        try verifyCrossDisplayRelease(controller: controller, screens: screens, defaults: defaults)
        try expect(store.captures.isEmpty && reminders.permissionRequests == 0 && reminders.additions == 0,
                   "Window interactions neither mutate captures nor request notification access")
        print("PASS: \(checks) native window resize and movement interaction checks; \(NSScreen.screens.count) attached displays")
    }

    @MainActor private static func verifyDisplayCancellation(controller: CornerController, screen: NSScreen) throws {
        let frame = controller.appFrame
        let board = controller.board
        controller.resizeBoardFromUser(to: baseFrame(on: screen))
        controller.finishBoardResize()
        frame.layoutSubtreeIfNeeded()
        let content = RobotAppFrameView.contentRect(in: frame.bounds)
        let start = screenPoint(CGPoint(x: content.maxX, y: content.minY), in: frame)
        let moved = CGPoint(x: start.x + 12, y: start.y - 10)
        frame.mouseDown(with: event(.leftMouseDown, at: start, in: board))
        frame.mouseDragged(with: event(.leftMouseDragged, at: moved, in: board))
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
        let afterChange = board.frame
        frame.mouseDragged(with: event(.leftMouseDragged, at: CGPoint(x: moved.x + 40, y: moved.y - 40), in: board))
        frame.mouseUp(with: event(.leftMouseUp, at: moved, in: board))
        try expect(board.frame == afterChange && screen.visibleFrame.contains(board.frame),
                   "A display configuration notification cancels an active corner gesture without stale movement")

        frame.layoutSubtreeIfNeeded()
        let band = BoardResizeGeometry.dragRegion(in: frame.bounds)
        let dragStart = screenPoint(CGPoint(x: band.midX, y: band.midY), in: frame)
        let dragFinish = CGPoint(x: dragStart.x + 12, y: dragStart.y - 8)
        frame.mouseDown(with: event(.leftMouseDown, at: dragStart, in: board))
        frame.mouseDragged(with: event(.leftMouseDragged, at: dragFinish, in: board))
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
        let afterDragChange = board.frame
        frame.mouseDragged(with: event(.leftMouseDragged,
            at: CGPoint(x: dragFinish.x + 60, y: dragFinish.y + 60), in: board))
        frame.mouseUp(with: event(.leftMouseUp, at: dragFinish, in: board))
        try expect(board.frame == afterDragChange && screen.visibleFrame.contains(board.frame),
                   "A display change cancels top-chrome movement and clears the pending drag session")
    }

    @MainActor private static func verifyCrossDisplayRelease(controller: CornerController,
                                                             screens: [NSScreen], defaults: UserDefaults) throws {
        guard screens.count > 1 else {
            print("SKIP: physical cross-display gesture requires two attached displays; geometry remains unit-tested")
            return
        }
        // Find a real shared-boundary arrangement where the pointer has crossed
        // but most of the board still overlaps its old display. This handles
        // negative coordinates and vertically stacked displays as well.
        var candidate: (source: NSScreen, destination: NSScreen, grabX: CGFloat, pointer: CGPoint, raw: CGRect)?
        for source in screens {
            let size = baseFrame(on: source).size
            let localY = BoardResizeGeometry.dragRegion(in: CGRect(origin: .zero, size: size)).midY
            for destination in screens where destination !== source {
                let visible = destination.visibleFrame
                for x in [visible.minX + 12, visible.midX, visible.maxX - 12] {
                    for y in [visible.minY + 12, visible.midY, visible.maxY - 50] {
                        for grabX in [CGFloat(40), size.width / 2, size.width - 40] {
                            let raw = CGRect(x: x - grabX, y: y - localY, width: size.width, height: size.height)
                            let oldArea = area(raw.intersection(source.frame))
                            let newArea = area(raw.intersection(destination.frame))
                            if oldArea > newArea && newArea > 0 {
                                candidate = (source, destination, grabX, CGPoint(x: x, y: y), raw)
                                break
                            }
                        }
                        if candidate != nil { break }
                    }
                    if candidate != nil { break }
                }
                if candidate != nil { break }
            }
            if candidate != nil { break }
        }
        guard let candidate else {
            print("SKIP: attached display gaps do not permit an overlapping top-chrome gesture; geometry remains unit-tested")
            return
        }
        let board = controller.board
        let frame = controller.appFrame
        let base = baseFrame(on: candidate.source)
        // Establish the source display using the same release routing callback.
        frame.onDragStarted?()
        board.setFrame(base, display: true)
        frame.onDragEnded?(CGPoint(x: base.midX, y: base.maxY - 16))
        controller.resizeBoardFromUser(to: base)
        controller.finishBoardResize()
        frame.layoutSubtreeIfNeeded()
        let localY = BoardResizeGeometry.dragRegion(in: frame.bounds).midY
        let start = screenPoint(CGPoint(x: candidate.grabX, y: localY), in: frame)
        frame.mouseDown(with: event(.leftMouseDown, at: start, in: board))
        frame.mouseDragged(with: event(.leftMouseDragged, at: candidate.pointer, in: board))
        try expect(board.frame == candidate.raw, "A cross-display chrome drag is not clamped while held")
        try expect(area(board.frame.intersection(candidate.source.frame))
                   > area(board.frame.intersection(candidate.destination.frame)),
                   "Cross-display regression fixture leaves most of the actual board on its original screen")
        frame.mouseUp(with: event(.leftMouseUp, at: candidate.pointer, in: board))
        let expected = BoardResizeGeometry.fitted(candidate.raw, visible: candidate.destination.visibleFrame)
        try expect(board.frame == expected && candidate.destination.visibleFrame.contains(board.frame),
                   "Release follows the pointer's destination display despite majority overlap with the old screen")
        try expect(defaults.array(forKey: CornerController.boardPlacementKey) as? [Double]
                   == [Double(expected.minX), Double(expected.maxY)],
                   "Cross-display release saves the fitted destination position")
        controller.showBoard(immediate: true)
        try expect(board.frame == expected, "Later layout preserves the destination display instead of snapping back")
    }
}
