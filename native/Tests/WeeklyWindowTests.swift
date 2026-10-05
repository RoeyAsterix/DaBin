import AppKit
import Foundation

@MainActor
private final class WeeklyWindowNotificationClient: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .denied }
    func requestAuthorization() async throws -> Bool { false }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}

/// Own-process panel geometry and events only: no OS mouse events, clipboard,
/// existing records, notification permission, or user window preferences.
@main struct WeeklyWindowTests {
    @MainActor private static var checks = 0
    @MainActor private static var failures: [String] = []

    @MainActor private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() { failures.append(message); fputs("FAIL: \(message)\n", stderr) }
    }

    @MainActor private static func settle() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.40))
    }

    @MainActor private static func render(_ window: NSWindow, name: String) throws {
        guard let view = window.contentView else { throw CocoaError(.fileWriteUnknown) }
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.fileWriteUnknown) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/qa/week-calendar")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(name + ".png"))
    }

    @MainActor private static func checkEmptyWeeklyPanel(root: URL, defaults: UserDefaults, screen: NSScreen) throws {
        let store = try CaptureStore(root: root.appendingPathComponent("Empty"))
        let previews = PreviewService(store: store)
        let state = AppState(store: store, previews: previews,
                             reminders: ReminderService(store: store, client: WeeklyWindowNotificationClient()))
        let controller = CornerController(state: state, input: InputService(store: store), placementDefaults: defaults, animateRobotTransitions: false)
        defer { controller.dismiss(); previews.cancelNetwork() }
        state.openDaily()
        controller.openDaily()
        state.selectedDay = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        settle()
        let compact = controller.board.frame
        let historicalDay = state.selectedDay
        state.selectTimelineMode(.weekly)
        settle()
        expect(state.route == .weekly
               && Calendar.current.isDate(state.weekEndingDay, inSameDayAs: historicalDay)
               && Calendar.current.isDate(state.selectedDay, inSameDayAs: historicalDay),
               "The toggle opens a seven-day view ending on the selected historical day")
        let expanded = controller.board.frame
        expect(expanded == screen.visibleFrame,
               "A completely empty week opens the full visible display")
        for filter in CaptureFilter.allCases {
            state.filter = filter
            settle()
            expect(state.weeklyDays.count == 7 && state.weeklyVisibleDays.count == 7,
                   "An empty \(filter.title) week renders all seven selected date columns")
            expect(controller.board.frame == expanded,
                   "Filtering an empty \(filter.title) week keeps the full view")
        }
        state.selectTimelineMode(.daily)
        settle()
        expect(state.route == .daily && state.dailyCaptures.isEmpty && state.filter == .tasks
               && Calendar.current.isDate(state.selectedDay, inSameDayAs: historicalDay),
               "The Daily segment preserves the selected day and Tasks filter")
        expect(controller.board.frame.width == compact.width && controller.board.frame.height == compact.height,
               "The Daily segment folds the panel back to its compact dimensions")
        state.selectTimelineMode(.weekly)
        settle()
        let chosenDay = state.weeklyDays[2]
        state.selectWeeklyDay(chosenDay)
        settle()
        expect(state.route == .daily && state.dailyCaptures.isEmpty && state.filter == .tasks
               && Calendar.current.isDate(state.selectedDay, inSameDayAs: chosenDay),
               "Selecting an empty weekly day returns to its Daily view while preserving the Tasks filter")
        expect(controller.board.frame.width == compact.width && controller.board.frame.height == compact.height,
               "Selecting an empty weekly day folds the panel back to its compact Daily dimensions")
        let reopened = try CaptureStore(root: root.appendingPathComponent("Empty"))
        expect(store.captures.isEmpty && reopened.captures.isEmpty,
               "Empty native weekly navigation never adds or persists captures")
    }

    @MainActor private static func checkSelectedDateSizing(root: URL, screen: NSScreen, coupledSizing: Bool = false) throws {
        let store = try CaptureStore(root: root.appendingPathComponent(coupledSizing ? "ZoomSelectedDates" : "SelectedDates"))
        let days = (-6...0).map { Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: $0, to: Date())!) }
        for index in [0, 2, 4, 6] {
            _ = try store.capture(text: "Selected-day window fixture \(index)", at: days[index].addingTimeInterval(60))
        }
        let suite = "DaBinWeeklySelectedDates.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        // Use this fixture's display before opening. NSScreen.main can be a
        // different monitor after another native test window becomes key.
        defaults.set([Double(screen.visibleFrame.minX + 20), Double(screen.visibleFrame.maxY - 35)],
                     forKey: CornerController.boardPlacementKey)
        if coupledSizing {
            defaults.set([640.0, 560.0], forKey: CornerController.boardSizeKey)
            defaults.set(true, forKey: CornerController.boardZoomSizeKey)
        }
        let previews = PreviewService(store: store)
        let state = AppState(store: store, previews: previews,
            reminders: ReminderService(store: store, client: WeeklyWindowNotificationClient()))
        let controller = CornerController(state: state, input: InputService(store: store),
            placementDefaults: defaults, animateRobotTransitions: false)
        defer { controller.dismiss(); previews.cancelNetwork() }
        state.openDaily()
        controller.showBoard(immediate: true)
        settle()
        let requested = NSRect(x: screen.visibleFrame.minX + 20, y: screen.visibleFrame.maxY - 620,
                               width: min(740, screen.visibleFrame.width - 40), height: 600)
        controller.resizeBoardFromUser(to: requested)
        controller.finishBoardResize()
        settle()
        let normal = controller.board.frame
        let savedSize = defaults.array(forKey: CornerController.boardSizeKey) as? [Double]
        state.openWeekly()
        controller.showBoard()
        settle()
        let expanded = screen.visibleFrame
        expect(state.weeklyVisibleDays.count == 7 && controller.board.frame == expanded,
               "Entering Week opens full view with all seven selected dates, including empty dates")
        expect(defaults.array(forKey: CornerController.boardSizeKey) as? [Double] == savedSize,
               "Automatic Week expansion preserves the normal saved window dimensions")
        try render(controller.board, name: coupledSizing ? "week-seven-days-from-zoom" : "week-seven-days-full-view")
        controller.toggleExpandedWindow()
        settle()
        expect(controller.board.frame == normal,
               "Restore returns from automatic Week full view to the exact preceding Daily geometry")
        controller.toggleExpandedWindow()
        settle()
        expect(controller.board.frame == expanded,
               "Expand returns the restored Week to the full display safe area")

        expect(state.setWeeklyDays([days[0], days[5], days[6]]), "Three selected dates are accepted")
        settle()
        expect(state.weeklyDays.count == 3 && state.weeklyVisibleDays.count == 3
               && controller.board.frame == expanded,
               "A custom three-date selection includes its empty date and retains full view")
        expect(controller.board.frame.maxY == screen.visibleFrame.maxY,
               "Changing the selection retains the expanded header position")
        try render(controller.board, name: coupledSizing ? "week-three-days-from-zoom" : "week-three-selected-days")
        let inserted = try store.capture(text: "A newly populated selected day", at: days[5].addingTimeInterval(60))[0]
        settle()
        expect(state.weeklyVisibleDays.count == 3 && controller.board.frame == expanded,
               "Saving the first capture on an empty date leaves its existing column and full view in place")
        _ = try store.remove(inserted)
        settle()
        expect(state.weeklyVisibleDays.count == 3 && controller.board.frame == expanded,
               "Removing the last capture keeps the selected date visible in full view")

        state.filter = .files
        settle()
        expect(controller.board.frame == expanded,
               "Content filters do not collapse populated date columns or move the header")
        controller.resizeBoardFromUser(to: NSRect(x: normal.minX, y: normal.maxY - 570,
                                                  width: 700, height: 570))
        controller.finishBoardResize()
        settle()
        let stretchedWeek = controller.board.frame
        state.filter = .all
        settle()
        expect(controller.board.frame == stretchedWeek,
               "A deliberate Week resize remains usable while filters change")
        expect(defaults.array(forKey: CornerController.boardSizeKey) as? [Double] == savedSize,
               "A temporary Week resize never overwrites the normal saved size")
        state.showSettings()
        settle()
        state.back()
        settle()
        expect(controller.board.frame == stretchedWeek,
               "Returning from Settings preserves the current Week's deliberate size")
        state.selectTimelineMode(.daily)
        settle()
        expect(controller.board.frame.size == normal.size,
               "Leaving a manually resized Week restores the normal window size")
        state.selectTimelineMode(.weekly)
        settle()
        expect(controller.board.frame == expanded,
               "Choosing Week again opens full view even when its dates have not changed")
        controller.resizeBoardFromUser(to: NSRect(x: normal.minX, y: normal.maxY - 570,
                                                  width: 700, height: 570))
        controller.finishBoardResize()
        settle()
        expect(state.setWeeklyDays([days[0], days[2], days[4], days[6]]), "Four custom populated dates are accepted")
        settle()
        expect(controller.board.frame == expanded,
               "Choosing other dates restores full view after a manual Week resize")
        state.selectTimelineMode(.daily)
        settle()
        expect(controller.board.frame.size == normal.size,
               "Returning to Daily restores its exact user-selected size")
        expect(defaults.array(forKey: CornerController.boardSizeKey) as? [Double] == savedSize,
               "Date selection and Weekly resize leave persisted normal dimensions intact")
    }

    @MainActor static func main() throws {
        let visible = NSRect(x: 0, y: 24, width: 1920, height: 1056)
        let nearLeft = NSRect(x: 30, y: 700, width: 400, height: 290)
        let nearRight = NSRect(x: 1510, y: 700, width: 400, height: 290)
        expect(CornerGeometry.weeklyExpansionDirection(compact: nearLeft, visible: visible) == .right,
               "A board near the left edge opens its week to the right")
        expect(CornerGeometry.weeklyExpansionDirection(compact: nearRight, visible: visible) == .left,
               "A board near the right edge opens its week to the left")
        let draggedWeek = NSRect(x: 380, y: 330, width: 740, height: 570)
        expect(CornerGeometry.compactTopLeft(weeklyFrame: draggedWeek, compactWidth: 400, direction: .left)
               == NSPoint(x: 720, y: 900), "Left-expanded movement maps to a compact right anchor")
        expect(CornerGeometry.compactTopLeft(weeklyFrame: draggedWeek, compactWidth: 400, direction: .right)
               == NSPoint(x: 380, y: 900), "Right-expanded movement maps to a compact left anchor")
        expect(CornerGeometry.shouldAnimateWeeklyTransition(from: .daily, to: .weekly, visible: true, reduceMotion: false),
               "Opening the week animates when motion is enabled")
        expect(CornerGeometry.shouldAnimateWeeklyTransition(from: .weekly, to: .daily, visible: true, reduceMotion: false),
               "Closing the week animates when motion is enabled")
        expect(!CornerGeometry.shouldAnimateWeeklyTransition(from: .daily, to: .weekly, visible: true, reduceMotion: true),
               "Reduce Motion bypasses expanding panel animation")
        expect(!CornerGeometry.shouldAnimateWeeklyTransition(from: .daily, to: .weekly, visible: false, reduceMotion: false),
               "Hidden panels are placed immediately")
        expect(!CornerGeometry.shouldAnimateWeeklyTransition(from: .weekly, to: .weekly, visible: true, reduceMotion: false),
               "Week navigation does not replay a window expansion")
        expect(!CornerGeometry.shouldAnimateWeeklyTransition(from: .daily, to: .settings, visible: true, reduceMotion: false),
               "Unrelated compact routes retain their existing sizing behavior")

        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.finishLaunching()
        guard let screen = NSScreen.screens.first else {
            fputs("FAIL: An attached screen is required for native panel checks\n", stderr)
            exit(1)
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinWeeklyWindows-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "DaBinWeeklyWindows.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = try CaptureStore(root: root)
        let notes = try (-6...0).map { offset in
            let stamp = Calendar.current.date(byAdding: .day, value: offset, to: Date())!
            return try store.capture(text: "Isolated weekly window fixture \(offset)", at: stamp)[0]
        }
        let note = notes.last!
        let previews = PreviewService(store: store)
        let reminders = ReminderService(store: store, client: WeeklyWindowNotificationClient())

        for expectedDirection: WeeklyExpansionDirection in [.right, .left] {
            let anchor = NSPoint(x: expectedDirection == .right ? screen.visibleFrame.minX + 30 : screen.visibleFrame.maxX - 410,
                                 y: screen.visibleFrame.maxY - 35)
            let saved = [Double(anchor.x), Double(anchor.y)]
            defaults.set(saved, forKey: CornerController.boardPlacementKey)
            let state = AppState(store: store, previews: previews, reminders: reminders)
            let controller = CornerController(state: state, input: InputService(store: store), placementDefaults: defaults, animateRobotTransitions: false)
            state.openDaily()
            controller.openDaily()
            settle()
            let compact = controller.board.frame
            expect(state.weeklyExpansionDirection == expectedDirection, "The opening direction is prepared before changing routes")
            var expansionFrames: [NSRect] = []
            let resizeObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification,
                object: controller.board, queue: nil) { _ in
                MainActor.assumeIsolated { expansionFrames.append(controller.board.frame) }
            }
            state.openWeekly()
            controller.showBoard()
            settle()
            NotificationCenter.default.removeObserver(resizeObserver)
            let expanded = controller.board.frame
            expect(expanded == screen.visibleFrame, "The actual native panel fills its current display safe area")
            expect(!controller.board.styleMask.contains(.fullScreen), "Week stays in the current macOS Space")
            let intermediateFrames = expansionFrames.filter { $0.width > compact.width && $0.width < expanded.width }
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                expect(intermediateFrames.isEmpty, "Actual panel expansion skips intermediate frames with Reduce Motion")
            } else {
                expect(!intermediateFrames.isEmpty, "Actual native expansion renders intermediate panel frames")
            }
            expect(defaults.array(forKey: CornerController.boardPlacementKey) as? [Double] == saved,
                   "Animation frames do not overwrite the user's compact placement")
            state.moveWeek(-1)
            settle()
            expect(state.weeklyVisibleDays.count == 7 && controller.board.frame == expanded
                   && state.weeklyExpansionDirection == expectedDirection,
                   "Browsing an empty week retains seven selected columns in the full view")
            state.moveWeek(1)
            settle()
            expect(state.weeklyVisibleDays.count == 7 && controller.board.frame == expanded,
                   "Returning to an active week retains all seven columns in the full view")
            state.openCapture(note.id)
            controller.showBoard()
            settle()
            expect(controller.board.frame.width == compact.width, "Opening a weekly capture returns to a compact detail panel")
            expect(controller.board.frame.minX == compact.minX && controller.board.frame.maxY == compact.maxY,
                   "Weekly details preserve the compact header anchor")
            state.back()
            controller.showBoard()
            settle()
            expect(controller.board.frame == expanded && state.weeklyExpansionDirection == expectedDirection,
                   "Returning from details restores the same expanded weekly panel")
            state.back()
            controller.showBoard()
            settle()
            expect(state.route == .weekly && controller.board.frame == expanded,
                   "Back through the previous date visit retains Week's full view")
            state.selectTimelineMode(.daily)
            controller.showBoard()
            settle()
            expect(state.route == .daily && controller.board.frame == compact,
                   "Closing the week restores the original compact frame without drift")
            state.openWeekly()
            controller.showBoard()
            RunLoop.main.run(until: Date().addingTimeInterval(0.08))
            state.back()
            controller.showBoard()
            RunLoop.main.run(until: Date().addingTimeInterval(0.04))
            state.openWeekly()
            controller.showBoard()
            settle()
            expect(controller.board.frame == expanded, "Rapid open-close-open does not adopt an intermediate animation position")
            state.back()
            controller.showBoard()
            settle()
            expect(state.route == .daily && controller.board.frame == compact,
                   "Rapid transition reversal retains the original compact anchor")

            state.openWeekly()
            controller.showBoard()
            settle()
            controller.beginBoardDrag(pointer: NSPoint(x: expanded.midX, y: expanded.maxY - 42))
            let dragged = controller.board.frame.offsetBy(dx: expectedDirection == .right ? 12 : -12, dy: -10)
            controller.board.setFrame(dragged, display: true)
            controller.finishBoardDragIfReleased(pressedMouseButtons: 0)
            let movedAnchor = CornerGeometry.compactTopLeft(weeklyFrame: dragged, compactWidth: compact.width,
                                                          direction: expectedDirection)
            expect(defaults.array(forKey: CornerController.boardPlacementKey) as? [Double]
                   == [Double(movedAnchor.x), Double(movedAnchor.y)], "Dragging a week saves its matching compact anchor")
            state.back()
            controller.showBoard()
            settle()
            let movedCompact = CornerGeometry.movedPanelFrame(topLeft: movedAnchor, visible: screen.visibleFrame,
                                                              preferredHeight: compact.height)
            expect(state.route == .daily && controller.board.frame == movedCompact,
                   "Closing a dragged week uses the newly chosen compact position")
            controller.dismiss()
            expect(!controller.board.isVisible && !controller.bin.isVisible, "Weekly checks leave no visible test panels")
        }
        try checkEmptyWeeklyPanel(root: root, defaults: defaults, screen: screen)
        try checkSelectedDateSizing(root: root, screen: screen)
        try checkSelectedDateSizing(root: root, screen: screen, coupledSizing: true)
        previews.cancelNetwork()
        print("Weekly window checks: \(checks), failures: \(failures.count)")
        if !failures.isEmpty { exit(1) }
    }
}
