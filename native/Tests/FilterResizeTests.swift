import AppKit
import Foundation

@MainActor
private final class FilterResizeNotificationClient: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .denied }
    func requestAuthorization() async throws -> Bool { false }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}

/// Own-process panels, fictional temporary records, and isolated preferences.
/// These checks do not move the system pointer, read the clipboard, send
/// notifications, or open the user's archive.
@main struct FilterResizeTests {
    private struct FrameSample {
        let elapsed: TimeInterval
        let frame: NSRect
    }

    @MainActor private static var checks = 0
    @MainActor private static var failures: [String] = []

    @MainActor private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() { failures.append(message); fputs("FAIL: \(message)\n", stderr) }
    }

    private static func near(_ first: CGFloat, _ second: CGFloat, tolerance: CGFloat = 1.01) -> Bool {
        abs(first - second) <= tolerance
    }

    @MainActor private static func settle(_ seconds: TimeInterval = 0.55) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    @MainActor private static func sample(_ board: NSWindow, for seconds: TimeInterval = 0.55,
                                          action: () -> Void) -> [FrameSample] {
        let started = ProcessInfo.processInfo.systemUptime
        var frames = [FrameSample(elapsed: 0, frame: board.frame)]
        let observer = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification,
            object: board, queue: nil) { _ in
            MainActor.assumeIsolated {
                frames.append(FrameSample(elapsed: ProcessInfo.processInfo.systemUptime - started,
                                          frame: board.frame))
            }
        }
        action()
        settle(seconds)
        NotificationCenter.default.removeObserver(observer)
        frames.append(FrameSample(elapsed: ProcessInfo.processInfo.systemUptime - started, frame: board.frame))
        return frames
    }

    @MainActor private static func expectFixedHeader(_ frames: [FrameSample], anchor: NSRect, label: String) {
        expect(frames.allSatisfy { near($0.frame.maxY, anchor.maxY) }, "\(label): the header stays at the same height in every sampled frame")
        expect(frames.allSatisfy { near($0.frame.minX, anchor.minX) }, "\(label): the panel does not shift horizontally")
        expect(frames.allSatisfy { near($0.frame.width, anchor.width) }, "\(label): the panel keeps its width")
    }

    @MainActor private static func expectTransition(_ frames: [FrameSample], from start: NSRect, to end: NSRect,
                                                    reducedMotion: Bool, label: String) {
        expectFixedHeader(frames, anchor: start, label: label)
        let low = min(start.height, end.height), high = max(start.height, end.height)
        let intermediate = frames.filter { $0.frame.height > low + 1 && $0.frame.height < high - 1 }
        expect(frames.allSatisfy { $0.frame.height >= low - 1 && $0.frame.height <= high + 1 },
               "\(label): resizing does not overshoot either endpoint")
        if reducedMotion {
            expect(intermediate.isEmpty, "\(label): Reduce Motion skips intermediate panel frames")
        } else {
            expect(intermediate.count >= 3, "\(label): resizing visibly passes through intermediate native frames")
            if let first = intermediate.first, let last = intermediate.last {
                expect(last.elapsed - first.elapsed >= 0.24, "\(label): the bottom edge has a deliberate transition instead of snapping")
            }
        }
        expect(near(frames.last!.frame.height, end.height), "\(label): resizing reaches the intended content height")
    }

    @MainActor static func main() throws {
        let visible = NSRect(x: -1440, y: -100, width: 1440, height: 900)
        let full = NSRect(x: -430, y: 100, width: 380, height: 500)
        let compact = CornerGeometry.filterPanelFrame(current: full, visible: visible, preferredHeight: 273)
        expect(compact == NSRect(x: -430, y: 327, width: 380, height: 273),
               "Filter shrink retains the existing top edge on a display with negative coordinates")
        expect(CornerGeometry.filterPanelFrame(current: compact, visible: visible, preferredHeight: 500) == full,
               "Filter growth returns to the original frame without header drift")
        let low = NSRect(x: -430, y: -73, width: 380, height: 273)
        let constrained = CornerGeometry.filterPanelFrame(current: low, visible: visible, preferredHeight: 500)
        expect(constrained.maxY == low.maxY && constrained.minY == visible.minY && constrained.height == 300,
               "Growth stops at the display bottom and leaves scrolling to the board")
        expect(constrained.minX == low.minX && constrained.width == low.width,
               "Constrained growth preserves horizontal placement and width")

        for route: BoardRoute in [.daily, .search] {
            expect(CornerGeometry.shouldAnimateFilterTransition(from: route, to: route,
                previousFilter: .all, filter: .tasks, visible: true, reduceMotion: false),
                   "A visible \(route) filter change animates")
            expect(!CornerGeometry.shouldAnimateFilterTransition(from: route, to: route,
                previousFilter: .all, filter: .tasks, visible: true, reduceMotion: true),
                   "A \(route) filter change respects Reduce Motion")
            expect(!CornerGeometry.shouldAnimateFilterTransition(from: route, to: route,
                previousFilter: .all, filter: .tasks, visible: false, reduceMotion: false),
                   "A hidden \(route) panel does not animate")
            expect(!CornerGeometry.shouldAnimateFilterTransition(from: route, to: route,
                previousFilter: .tasks, filter: .tasks, visible: true, reduceMotion: false),
                   "An unchanged \(route) filter does not start a new animation")
        }
        expect(!CornerGeometry.shouldAnimateFilterTransition(from: nil, to: .daily,
            previousFilter: nil, filter: .all, visible: true, reduceMotion: false), "First presentation does not animate as a filter change")
        expect(!CornerGeometry.shouldAnimateFilterTransition(from: .daily, to: .search,
            previousFilter: .all, filter: .tasks, visible: true, reduceMotion: false), "Changing routes is not treated as a filter resize")
        expect(!CornerGeometry.shouldAnimateFilterTransition(from: .weekly, to: .weekly,
            previousFilter: .all, filter: .tasks, visible: true, reduceMotion: false), "Week filters keep the established weekly frame")

        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.finishLaunching()
        guard let screen = NSScreen.screens.first else {
            fputs("FAIL: An attached screen is required for native filter resize checks\n", stderr)
            exit(1)
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinFilterResize-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "DaBinFilterResize.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = try CaptureStore(root: root)
        let now = Date()
        for number in 1...4 { _ = try store.capture(text: "Filter fixture note \(number)", at: now) }
        _ = try store.createTask(text: "Filter fixture task")
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        _ = try store.capture(text: "https://example.invalid/fixture", at: yesterday)
        let previews = PreviewService(store: store)
        let reminders = ReminderService(store: store, client: FilterResizeNotificationClient())
        let state = AppState(store: store, previews: previews, reminders: reminders)
        let controller = CornerController(state: state, input: InputService(store: store), placementDefaults: defaults, animateRobotTransitions: false)
        defer { controller.dismiss(); previews.cancelNetwork() }
        let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        // Reproduce the original issue without any remembered user placement:
        // the robot first appears at a bottom corner, then opens a full Daily.
        let corner = NSPoint(x: screen.frame.maxX - 1, y: screen.frame.minY + 1)
        controller.pollPointer(at: corner, now: now, pressedMouseButtons: 0)
        controller.openDaily()
        settle()
        let initial = controller.board.frame
        expect(state.dailyCaptures.count == 5, "Daily starts with five fictional records")
        expect(near(initial.height, 550), "The unplaced bottom-corner Daily starts at full content height")
        expect(defaults.object(forKey: CornerController.boardPlacementKey) == nil, "Opening an unplaced Daily does not persist a user drag")

        let shrink = sample(controller.board) { state.filter = .tasks }
        let taskFrame = controller.board.frame
        expect(state.dailyCaptures.count == 1 && near(taskFrame.height, 335), "Tasks leaves one framed record and the compact content height")
        expectTransition(shrink, from: initial, to: taskFrame, reducedMotion: reducedMotion, label: "Daily shrink")
        expect(defaults.object(forKey: CornerController.boardPlacementKey) == nil, "Filter animation does not become a saved user placement")

        let task = state.dailyCaptures[0]
        // Give collapse a meaningful travel distance. A plain task only shrinks
        // 18 points; pixel rounding makes the filter helper's 1-point endpoint
        // exclusion inappropriate for its visible-duration assertion.
        try store.update(task, comment: "Keep this detailed context visible while reviewing the workshop notes and the next steps for tomorrow.",
                         reminderAt: nil, reminderTimeZoneID: nil)
        settle()
        let expandedTaskFrame = controller.board.frame
        let collapsed = sample(controller.board) { state.toggleMinimized(task) }
        let minimizedFrame = controller.board.frame
        expect(task.isMinimized && minimizedFrame.height < expandedTaskFrame.height,
               "Minimizing a capture reduces the actual Daily panel height")
        expectTransition(collapsed, from: expandedTaskFrame, to: minimizedFrame, reducedMotion: reducedMotion, label: "Capture minimize")
        let expanded = sample(controller.board) { state.toggleMinimized(task) }
        expect(!task.isMinimized && near(controller.board.frame.height, expandedTaskFrame.height),
               "Expanding restores the actual Daily content height")
        expectTransition(expanded, from: minimizedFrame, to: expandedTaskFrame, reducedMotion: reducedMotion, label: "Capture expand")
        expect(defaults.object(forKey: CornerController.boardPlacementKey) == nil,
               "Minimizing a capture never overwrites the user's window placement")
        try store.update(task, comment: "", reminderAt: nil, reminderTimeZoneID: nil)
        settle()

        let empty = sample(controller.board) { state.filter = .files }
        expect(state.dailyCaptures.isEmpty && near(controller.board.frame.height, 340), "An empty filter reserves room for the bored robot")
        expectFixedHeader(empty, anchor: initial, label: "Empty Daily filter")
        let beforeGrowth = controller.board.frame
        let growth = sample(controller.board) { state.filter = .all }
        expectTransition(growth, from: beforeGrowth, to: initial, reducedMotion: reducedMotion, label: "Daily growth")
        expect(near(controller.board.frame.minY, initial.minY), "Returning to All restores the original bottom edge")

        if !reducedMotion {
            let rapid = sample(controller.board, for: 0.65) {
                state.filter = .tasks
                settle(0.16)
                let partial = controller.board.frame
                expect(partial.height < initial.height - 1 && partial.height > taskFrame.height + 1,
                       "Rapid reversal starts while the previous resize is in flight")
                state.filter = .all
                expect(controller.board.frame == partial, "Reversing a filter does not snap synchronously to an endpoint")
            }
            expectFixedHeader(rapid, anchor: initial, label: "Rapid filter reversal")
            expect(near(controller.board.frame.height, initial.height), "Rapid reversal reaches the latest selected filter height")
            let deltas = zip(rapid, rapid.dropFirst()).map { abs($0.frame.height - $1.frame.height) }
            expect((deltas.max() ?? 0) < 90, "Rapid reversal continues through native frames without a large endpoint jump")
        }

        // Dismissing must cancel the pending frame timer rather than continue
        // moving an invisible window or save its intermediate location.
        state.filter = .tasks
        settle(0.16)
        controller.dismiss()
        let dismissed = controller.board.frame
        settle()
        expect(controller.board.frame == dismissed, "Dismissal stops all pending filter frame updates")
        expect(!controller.board.isVisible, "Dismissed filter panel stays hidden")
        expect(defaults.object(forKey: CornerController.boardPlacementKey) == nil, "Dismissal does not persist an animation frame")

        controller.openDaily()
        settle()
        state.query = "fixture"
        controller.openSearch()
        settle()
        let searchFull = controller.board.frame
        expect(near(searchFull.height, 550), "Search starts with enough matches for a full panel")
        let searchShrink = sample(controller.board) { state.filter = .links }
        let searchLink = controller.board.frame
        expect(state.searchGroups.count == 1 && state.searchGroups.first?.entries.count == 1,
               "Search Links finds the isolated previous-day link with no adjacent fixtures")
        expect(near(searchLink.height, 355), "Single-entry search has the intended compact height")
        expectTransition(searchShrink, from: searchFull, to: searchLink, reducedMotion: reducedMotion, label: "Search shrink")
        let searchEmpty = sample(controller.board) { state.filter = .media }
        expectFixedHeader(searchEmpty, anchor: searchFull, label: "Empty Search filter")
        expect(state.searchGroups.isEmpty && near(controller.board.frame.height, 340), "Empty Search fits its status without moving the header")
        let searchBeforeGrowth = controller.board.frame
        let searchGrowth = sample(controller.board) { state.filter = .all }
        expectTransition(searchGrowth, from: searchBeforeGrowth, to: searchFull, reducedMotion: reducedMotion, label: "Search growth")

        controller.openDaily()
        settle()
        state.filter = .tasks
        settle(0.16)
        state.onBoardDragStarted?()
        let dragged = controller.board.frame.offsetBy(dx: -25, dy: 20)
        controller.board.setFrame(dragged, display: true)
        controller.finishBoardDragIfReleased(pressedMouseButtons: 0)
        let afterDrag = sample(controller.board) { }
        expectFixedHeader(afterDrag, anchor: dragged, label: "Header drag interrupts filter motion")
        expect(defaults.array(forKey: CornerController.boardPlacementKey) as? [Double]
               == [Double(dragged.minX), Double(dragged.maxY)], "Only the actual header drag persists the chosen position")

        // Put the compact board near the display bottom, then ask for more
        // content. Its header should remain where it was deliberately placed.
        let lowTop = screen.visibleFrame.minY + 370
        state.onBoardDragStarted?()
        let lowFrame = NSRect(x: controller.board.frame.minX,
                              y: lowTop - controller.board.frame.height,
                              width: controller.board.frame.width, height: controller.board.frame.height)
        controller.board.setFrame(lowFrame, display: true)
        controller.finishBoardDragIfReleased(pressedMouseButtons: 0)
        settle()
        let lowAnchor = controller.board.frame
        let constrainedGrowth = sample(controller.board) { state.filter = .all }
        expectFixedHeader(constrainedGrowth, anchor: lowAnchor, label: "Growth near the screen bottom")
        expect(near(controller.board.frame.minY, screen.visibleFrame.minY), "Available height stops at the screen bottom")
        expect(near(controller.board.frame.height, 370), "Overflowing records use a constrained panel instead of moving its header")
        expect(defaults.array(forKey: CornerController.boardPlacementKey) as? [Double]
               == [Double(lowFrame.minX), Double(lowFrame.maxY)], "Constrained animation preserves the saved user anchor")

        // A drag is allowed to cross the screen edge while held, but releasing
        // there must restore a usable panel rather than retain a zero-height
        // or header-only result from the filter geometry path.
        state.filter = .tasks
        settle()
        for topOffset: CGFloat in [24, -30] {
            state.onBoardDragStarted?()
            let offscreen = NSRect(x: controller.board.frame.minX,
                                   y: screen.visibleFrame.minY + topOffset - controller.board.frame.height,
                                   width: controller.board.frame.width, height: controller.board.frame.height)
            controller.board.setFrame(offscreen, display: true)
            controller.finishBoardDragIfReleased(pressedMouseButtons: 1)
            expect(controller.board.frame == offscreen,
                   "A held header drag remains under pointer control with its top \(topOffset)pt from the screen bottom")
            controller.finishBoardDragIfReleased(pressedMouseButtons: 0)
            settle()
            expect(screen.visibleFrame.contains(controller.board.frame),
                   "Releasing the header near the bottom recovers the entire panel on screen (\(topOffset)pt); visible=\(screen.visibleFrame), board=\(controller.board.frame)")
            expect(near(controller.board.frame.height, 335),
                   "Offscreen drag recovery restores the full one-task height (\(topOffset)pt)")
            expect(controller.board.frame.maxY >= screen.visibleFrame.minY + 335,
                   "Offscreen drag recovery leaves an accessible header and usable content (\(topOffset)pt)")
        }

        if !reducedMotion {
            // Interrupt a weekly collapse while it is still wider than Daily.
            // The manual drag must not leave the compact route permanently
            // stretched to an intermediate animation width.
            state.onBoardDragStarted?()
            let safeCompact = NSRect(x: screen.visibleFrame.maxX - 410,
                                     y: screen.visibleFrame.maxY - 35 - controller.board.frame.height,
                                     width: controller.board.frame.width, height: controller.board.frame.height)
            controller.board.setFrame(safeCompact, display: true)
            controller.finishBoardDragIfReleased(pressedMouseButtons: 0)
            settle()
            state.openWeekly()
            controller.showBoard()
            settle()
            let fullWeek = controller.board.frame
            state.back()
            controller.showBoard()
            settle(0.10)
            let folding = controller.board.frame
            expect(folding.width > 401 && folding.width < fullWeek.width - 1,
                   "Weekly-collapse drag regression begins at an actual intermediate width")
            state.onBoardDragStarted?()
            controller.board.setFrame(folding.offsetBy(dx: 0, dy: -10), display: true)
            controller.finishBoardDragIfReleased(pressedMouseButtons: 0)
            settle()
            expect(near(controller.board.frame.width, 400),
                   "Dragging during a weekly collapse restores the standard compact width")
            expect(screen.visibleFrame.contains(controller.board.frame),
                   "The interrupted weekly collapse recovers a fully visible Daily panel")
            expect(near(controller.board.frame.height, 335),
                   "The interrupted weekly collapse retains the selected Tasks content height")
        }
        expect(store.captures.count == 6, "Filtering and resizing leave all six archived fixtures intact")

        print("Filter resize checks: \(checks), failures: \(failures.count)")
        if !failures.isEmpty { exit(1) }
    }
}
