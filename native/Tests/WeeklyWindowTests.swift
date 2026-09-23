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

    @MainActor private static func checkEmptyWeeklyPanel(root: URL, defaults: UserDefaults) throws {
        let store = try CaptureStore(root: root.appendingPathComponent("Empty"))
        let previews = PreviewService(store: store)
        let state = AppState(store: store, previews: previews,
                             reminders: ReminderService(store: store, client: WeeklyWindowNotificationClient()))
        let controller = CornerController(state: state, input: InputService(store: store), placementDefaults: defaults)
        defer { controller.dismiss(); previews.cancelNetwork() }
        controller.openDaily()
        state.selectedDay = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        settle()
        let compact = controller.board.frame
        state.showCurrentWeek()
        settle()
        expect(state.route == .weekly && Calendar.current.isDateInToday(state.weekEndingDay)
               && Calendar.current.isDateInToday(state.selectedDay),
               "The Today navigation action opens the current week from a historical empty Daily")
        let expanded = controller.board.frame
        expect(expanded.width > compact.width && expanded.height > compact.height,
               "An empty weekly panel still expands to a full weekly layout")
        for filter in CaptureFilter.allCases {
            state.filter = filter
            settle()
            expect(state.weeklyDays.count == 7 && state.weeklyDays.allSatisfy { state.captures(for: $0).isEmpty },
                   "An empty \(filter.title) week preserves seven empty day columns")
            expect(controller.board.frame == expanded && state.weeklyDays.count == 7,
                   "Filtering an empty \(filter.title) week keeps its full weekly dimensions and dates")
        }
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

    @MainActor static func main() throws {
        let visible = NSRect(x: 0, y: 24, width: 1920, height: 1056)
        let nearLeft = NSRect(x: 30, y: 700, width: 380, height: 290)
        let nearRight = NSRect(x: 1510, y: 700, width: 380, height: 290)
        expect(CornerGeometry.weeklyExpansionDirection(compact: nearLeft, visible: visible) == .right,
               "A board near the left edge opens its week to the right")
        expect(CornerGeometry.weeklyExpansionDirection(compact: nearRight, visible: visible) == .left,
               "A board near the right edge opens its week to the left")
        let rightWeek = CornerGeometry.weeklyPanelFrame(compact: nearLeft, visible: visible, direction: .right)
        let leftWeek = CornerGeometry.weeklyPanelFrame(compact: nearRight, visible: visible, direction: .left)
        expect(rightWeek.width == 1440 && rightWeek.height == 560, "A large screen uses the intended weekly size")
        expect(rightWeek.minX == nearLeft.minX && rightWeek.maxY == nearLeft.maxY,
               "Right expansion retains the compact left edge and header height")
        expect(leftWeek.maxX == nearRight.maxX && leftWeek.maxY == nearRight.maxY,
               "Left expansion retains the compact right edge and header height")
        expect(visible.contains(leftWeek) && visible.contains(rightWeek), "Both directions stay inside the usable display")
        expect(CornerGeometry.compactTopLeft(weeklyFrame: leftWeek, compactWidth: 380, direction: .left)
               == NSPoint(x: nearRight.minX, y: nearRight.maxY), "Left-expanded movement maps to a compact right anchor")
        expect(CornerGeometry.compactTopLeft(weeklyFrame: rightWeek, compactWidth: 380, direction: .right)
               == NSPoint(x: nearLeft.minX, y: nearLeft.maxY), "Right-expanded movement maps to a compact left anchor")
        let middle = NSRect(x: 770, y: 80, width: 380, height: 290)
        let centeredWeek = CornerGeometry.weeklyPanelFrame(compact: middle, visible: visible,
            direction: CornerGeometry.weeklyExpansionDirection(compact: middle, visible: visible))
        expect(visible.contains(centeredWeek), "A center board with insufficient room is clamped into the screen")
        for screen in [NSRect(x: -1920, y: -300, width: 1920, height: 1056),
                       NSRect(x: -50, y: -50, width: 180, height: 180),
                       NSRect(x: 0, y: 24, width: 1280, height: 696)] {
            for direction: WeeklyExpansionDirection in [.left, .right] {
                let frame = CornerGeometry.weeklyPanelFrame(
                    compact: NSRect(x: -9000, y: 9000, width: 380, height: 500), visible: screen, direction: direction)
                expect(screen.contains(frame), "Offscreen anchor recovers on \(screen.width)pt display in \(direction) direction")
                expect(frame.width == min(1440, screen.width - 16), "Weekly width adapts to the visible display")
                expect(frame.height <= screen.height - 16, "Weekly height adapts to the visible display")
            }
        }
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
        let note = try store.capture(text: "Isolated weekly window fixture")[0]
        let previews = PreviewService(store: store)
        let reminders = ReminderService(store: store, client: WeeklyWindowNotificationClient())

        for expectedDirection: WeeklyExpansionDirection in [.right, .left] {
            let anchor = NSPoint(x: expectedDirection == .right ? screen.visibleFrame.minX + 30 : screen.visibleFrame.maxX - 410,
                                 y: screen.visibleFrame.maxY - 35)
            let saved = [Double(anchor.x), Double(anchor.y)]
            defaults.set(saved, forKey: CornerController.boardPlacementKey)
            let state = AppState(store: store, previews: previews, reminders: reminders)
            let controller = CornerController(state: state, input: InputService(store: store), placementDefaults: defaults)
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
            let expected = CornerGeometry.weeklyPanelFrame(compact: compact, visible: screen.visibleFrame, direction: expectedDirection)
            expect(expanded == expected, "The actual native panel expands in \(expectedDirection) direction")
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
            expect(controller.board.frame == expanded && state.weeklyExpansionDirection == expectedDirection,
                   "Browsing another week keeps the same panel frame and expansion side")
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
            expect(controller.board.frame == compact, "Closing the week restores the original compact frame without drift")
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
            expect(controller.board.frame == compact, "Rapid transition reversal retains the original compact anchor")

            state.openWeekly()
            controller.showBoard()
            settle()
            state.onBoardDragStarted?()
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
            expect(controller.board.frame == movedCompact, "Closing a dragged week uses the newly chosen compact position")
            controller.dismiss()
            expect(!controller.board.isVisible && !controller.bin.isVisible, "Weekly checks leave no visible test panels")
        }
        try checkEmptyWeeklyPanel(root: root, defaults: defaults)
        previews.cancelNetwork()
        print("Weekly window checks: \(checks), failures: \(failures.count)")
        if !failures.isEmpty { exit(1) }
    }
}
