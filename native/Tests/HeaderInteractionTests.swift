import AppKit
import Foundation
import SwiftUI

@MainActor
private final class HeaderReminderClient: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .undetermined }
    func requestAuthorization() async throws -> Bool { false }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws {}
    func removePending(_ identifiers: [String]) {}
    func removeDelivered(_ identifiers: [String]) {}
}

@MainActor
private final class HeaderScreenshotMonitor: ScreenshotFolderMonitoring {
    var sourceApplicationAtDirectoryActivity: (() -> AutoCaptureSourceApplication?)?
    var onNewScreenshot: ((URL, AutoCaptureSourceApplication?) -> Void)?
    var onFailure: ((Error) -> Void)?
    private(set) var isRunning = false

    func start() throws { isRunning = true }
    func stop() { isRunning = false }
}

/// Sends mouse/key events only to this suite's own isolated AppKit window. It
/// never moves the system pointer, reads the clipboard or opens a save panel.
@main
private enum HeaderInteractionTests {
    @MainActor private static var checks = 0

    @MainActor private static func expect(_ condition: @autoclosure () -> Bool,
                                          _ message: String) throws {
        checks += 1
        guard condition() else {
            throw NSError(domain: "HeaderInteractionTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    @MainActor private static func settle(_ seconds: TimeInterval = 0.12) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    @MainActor private static func click(_ window: NSWindow, x: CGFloat, topY: CGFloat) {
        let point = NSPoint(x: x, y: window.contentLayoutRect.height - topY)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                           timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil,
                                           eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
            window.sendEvent(event)
        }
        settle()
    }

    @MainActor private static func key(_ window: NSWindow, keyCode: UInt16,
                                       characters: String,
                                       modifiers: NSEvent.ModifierFlags = []) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers,
                                         timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: window.windowNumber, context: nil,
                                         characters: characters, charactersIgnoringModifiers: characters,
                                         isARepeat: false, keyCode: keyCode)!
            window.sendEvent(event)
        }
        settle()
    }

    /// Sends through NSApplication so production menu key equivalents get the
    /// first chance to handle the command, exactly as they do in the app.
    @MainActor private static func applicationKey(_ application: NSApplication, window: NSWindow,
                                                  keyCode: UInt16, characters: String,
                                                  modifiers: NSEvent.ModifierFlags) {
        window.makeKey()
        let eventCharacters = modifiers.contains(.shift) ? characters.uppercased() : characters
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers,
                                         timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: window.windowNumber, context: nil,
                                         characters: eventCharacters, charactersIgnoringModifiers: characters.lowercased(),
                                         isARepeat: false, keyCode: keyCode)!
            application.sendEvent(event)
        }
        settle(0.18)
    }

    @MainActor private static func newPopover(in application: NSApplication, board: NSWindow,
                                               excluding existing: Set<Int>) -> NSWindow? {
        application.windows.first {
            $0 !== board && $0.isVisible && !existing.contains($0.windowNumber)
        }
    }

    @MainActor
    static func main() throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.finishLaunching()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DaBinHeaderInteractions-\(UUID().uuidString)")
        let suite = "DaBinHeaderInteractions.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let store = try CaptureStore(root: root)
        let previews = PreviewService(store: store, defaults: defaults)
        defer { previews.cancelNetwork() }
        let input = InputService(store: store)
        let autoCaptureSettings = AutoCaptureSettings(defaults: defaults)
        autoCaptureSettings.acknowledgePrivacyExplanation()
        autoCaptureSettings.setScreenshotFolderBookmark(Data("header-fixture".utf8),
                                                        displayName: root.lastPathComponent)
        let screenshotMonitor = HeaderScreenshotMonitor()
        let autoCapture = AutoCaptureService(
            settings: autoCaptureSettings,
            input: input,
            screenshotMonitorFactory: { _ in screenshotMonitor },
            bookmarkResolver: { _ in (root, false) },
            pollInterval: 60
        )
        defer { autoCapture.shutdown() }
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let exportCapture = try store.capture(text: "TODAY UNIQUE keyboard export fixture", at: now)[0]
        let priorExportCapture = try store.capture(text: "YESTERDAY UNIQUE weekly picker fixture", at: yesterday)[0]
        var fixtureIDs = Set([exportCapture.id, priorExportCapture.id])
        var copiedDay: String?
        var destinationChoices = 0
        var chosenExportPeriod: TimelineExportPeriod?
        var chosenExportFilename: String?
        let exportController = DayExportActionController(pasteboardWriter: {
            copiedDay = $0
            return true
        }, destinationChooser: { period, filename in
            destinationChoices += 1
            chosenExportPeriod = period
            chosenExportFilename = filename
            return .cancelled
        }, fileWriter: { _, _ in })
        let state = AppState(store: store, previews: previews,
                             reminders: ReminderService(store: store, client: HeaderReminderClient()),
                             robotPlacement: RobotPlacementSettings(defaults: defaults),
                             autoCapture: autoCapture)
        let theme = ThemeSettings(defaults: defaults)
        let tooltipController = TimelineTooltipController(delay: 0.02)
        var dismissals = 0
        state.onDismiss = { dismissals += 1 }
        state.isBoardVisible = true

        let size = NSSize(width: 380, height: 500)
        let hosting = NSHostingView(rootView: BoardView(state: state, theme: theme,
                                                        dayExportController: exportController,
                                                        tooltipController: tooltipController)
            .frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        application.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        let previousMenu = application.mainMenu
        let commandMenu = ApplicationMenu(
            openDaily: { state.openDaily() },
            openSearch: { state.performSearchCommand() },
            focusRobot: {}, showSettings: { state.showSettings() }
        )
        commandMenu.install()
        defer {
            commandMenu.uninstall()
            application.mainMenu = previousMenu
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        settle(0.25)

        // The compact 380-point contract keeps both icon rows at 280 × 34,
        // with equal 40-point targets distributed between shared outer edges.
        let primarySpacing = TimelineIconRowMetrics.spacing(itemCount: TimelinePrimaryAction.allCases.count)
        let filterSpacing = TimelineIconRowMetrics.spacing(itemCount: CaptureFilter.allCases.count)
        let primaryWidth = CGFloat(TimelinePrimaryAction.allCases.count) * TimelineIconRowMetrics.controlWidth
            + CGFloat(TimelinePrimaryAction.allCases.count - 1) * primarySpacing
        let filterWidth = CGFloat(CaptureFilter.allCases.count) * TimelineIconRowMetrics.controlWidth
            + CGFloat(CaptureFilter.allCases.count - 1) * filterSpacing
        try expect(TimelineIconRowMetrics.iconScale == 1.10
                   && TimelineIconRowMetrics.symbolCanvasSize == 26
                   && abs(TimelineIconRowMetrics.symbolPointSize - 16.5) < 0.001
                   && abs(TimelineIconRowMetrics.navigationSymbolPointSize - 14.3) < 0.001
                   && TimelineIconRowMetrics.controlWidth == 40
                   && TimelineIconRowMetrics.controlHeight == 34,
                   "Header icons render 10% larger inside the same 40 by 34 point targets")
        try expect(abs(primaryWidth - TimelineIconRowMetrics.rowWidth) < 0.01
                   && abs(filterWidth - TimelineIconRowMetrics.rowWidth) < 0.01,
                   "Primary actions and filters occupy identical 280-point rows")
        try expect(TimelineNavigationMetrics.modeGroupWidth == 80,
                   "Daily and Weekly use two compact 40-point icon targets")
        try expect(abs(TimelineNavigationMetrics.modeAnchorX(weekly: false, index: 0) - 204) < 0.01
                   && abs(TimelineNavigationMetrics.modeAnchorX(weekly: false, index: 1) - 244) < 0.01
                   && abs(TimelineNavigationMetrics.modeAnchorX(weekly: true, index: 0) - 228) < 0.01
                   && abs(TimelineNavigationMetrics.modeAnchorX(weekly: true, index: 1) - 268) < 0.01,
                   "Mode icons and their tooltips remain aligned in narrow Daily and Weekly headers")
        try expect(abs(TimelineNavigationMetrics.autoCaptureAnchorX(weekly: false) - 286) < 0.01
                   && abs(TimelineNavigationMetrics.autoCaptureAnchorX(weekly: true) - 310) < 0.01
                   && TimelineNavigationMetrics.fixedContentWidth(weekly: true)
                        <= size.width - TimelineNavigationMetrics.horizontalPadding * 2,
                   "Auto Capture sits immediately right of 7 Days without clipping the narrow header")
        try expect(NSImage(systemSymbolName: "1.calendar", accessibilityDescription: nil) != nil
                   && NSImage(systemSymbolName: "7.calendar", accessibilityDescription: nil) != nil
                   && NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil) != nil,
                   "Daily, Weekly and Auto Capture symbols are available on the deployment target")
        try expect(AutoCaptureHeaderAnimation.angle(isOn: false, reduceMotion: false, phase: true) == 0
                   && AutoCaptureHeaderAnimation.angle(isOn: true, reduceMotion: true, phase: true) == 0
                   && AutoCaptureHeaderAnimation.angle(isOn: true, reduceMotion: false, phase: true)
                        == AutoCaptureHeaderAnimation.maximumTiltDegrees
                   && AutoCaptureHeaderAnimation.angle(isOn: true, reduceMotion: false, phase: false)
                        == -AutoCaptureHeaderAnimation.maximumTiltDegrees,
                   "Auto Capture tilts around center only while on and respects Reduce Motion")

        let primaryTooltipLabels = TimelinePrimaryAction.allCases.map(\.tooltipLabel)
        let filterTooltipLabels = CaptureFilter.allCases.map(\.tooltipLabel)
        try expect(primaryTooltipLabels == ["Add task", "Search", "Export", "Notifications", "Settings"],
                   "Every primary icon has concise hover text")
        try expect(filterTooltipLabels == ["All", "Text", "Links", "Files", "Media", "Tasks"],
                   "Every filter icon has concise hover text")
        let firstPrimaryTooltip = TimelineTooltipDescriptor(
            id: "primary-tooltip-add", text: primaryTooltipLabels[0], index: 0,
            itemCount: TimelinePrimaryAction.allCases.count
        )
        let lastFilterTooltip = TimelineTooltipDescriptor(
            id: "filter-tooltip-tasks", text: filterTooltipLabels[5], index: 5,
            itemCount: CaptureFilter.allCases.count, row: .filters
        )
        let weeklyModeTooltip = TimelineTooltipDescriptor(
            id: "timeline-mode-tooltip-weekly", text: "Weekly", index: 1,
            itemCount: 2, row: .navigation,
            fixedAnchorX: TimelineNavigationMetrics.modeAnchorX(weekly: false, index: 1)
        )
        let autoCaptureTooltip = TimelineTooltipDescriptor(
            id: "timeline-auto-capture-tooltip", text: "Auto Capture off", index: 2,
            itemCount: 3, row: .navigation,
            fixedAnchorX: TimelineNavigationMetrics.autoCaptureAnchorX(weekly: false)
        )
        try expect(abs(firstPrimaryTooltip.anchorX(in: size.width) - 70) < 0.01
                   && abs(lastFilterTooltip.anchorX(in: size.width) - 310) < 0.01,
                   "Tooltip anchors follow the shared row geometry at both edges")
        try expect(weeklyModeTooltip.text == "Weekly"
                   && abs(weeklyModeTooltip.anchorX(in: size.width) - 244) < 0.01,
                   "The Weekly icon has concise hover text anchored beneath the navigation control")
        try expect(abs(autoCaptureTooltip.anchorX(in: size.width) - 286) < 0.01,
                   "Auto Capture has a coordinated tooltip immediately right of 7 Days")
        tooltipController.begin(firstPrimaryTooltip)
        settle(0.04)
        try expect(tooltipController.visible == firstPrimaryTooltip,
                   "Hover delay reveals one coordinated tooltip")
        tooltipController.end(id: firstPrimaryTooltip.id)
        try expect(tooltipController.visible == nil,
                   "Leaving an icon dismisses its tooltip immediately")
        tooltipController.begin(weeklyModeTooltip)
        settle(0.04)
        try expect(tooltipController.visible == weeklyModeTooltip,
                   "The navigation icons share the same delayed tooltip controller")
        tooltipController.end(id: weeklyModeTooltip.id)
        tooltipController.begin(autoCaptureTooltip)
        settle(0.04)
        try expect(tooltipController.visible == autoCaptureTooltip,
                   "Auto Capture uses the same delayed navigation tooltip")
        tooltipController.end(id: autoCaptureTooltip.id)
        tooltipController.begin(lastFilterTooltip)
        tooltipController.end(id: lastFilterTooltip.id)
        settle(0.04)
        try expect(tooltipController.visible == nil,
                   "Leaving before the delay cancels tooltip presentation")
        tooltipController.begin(firstPrimaryTooltip, immediate: true)
        try expect(tooltipController.visible == firstPrimaryTooltip,
                   "Keyboard focus uses the immediate tooltip presentation path")
        tooltipController.activate(id: firstPrimaryTooltip.id)
        try expect(tooltipController.visible == nil,
                   "Activating an icon clears its tooltip before navigation or a popover")
        tooltipController.end(id: firstPrimaryTooltip.id)

        click(window, x: 70, topY: 55)
        try expect(state.route == .newTask, "Add opens the task composer from the compact primary row")
        state.route = .daily; settle()

        click(window, x: 130, topY: 55)
        try expect(state.route == .search, "Search opens from the second primary action")
        state.route = .daily; settle()

        let otherWindowsBeforeExport = Set(application.windows.filter { $0 !== window && $0.isVisible }.map(\.windowNumber))
        click(window, x: 190, topY: 55)
        let exportWindow = application.windows.first {
            $0 !== window && $0.isVisible && !otherWindowsBeforeExport.contains($0.windowNumber)
        }
        try expect(exportWindow != nil, "Export Day opens an anchored native action popover")
        if let exportWindow {
            let anchorX = window.frame.minX + 190
            let actionY = window.frame.maxY - 55
            try expect(abs(exportWindow.frame.midX - anchorX) < 55
                       && exportWindow.frame.maxY <= actionY + 12,
                       "The Export Day popover is anchored beneath its icon")
        }
        try expect(state.route == .daily, "Opening Export Day leaves the selected timeline route intact")
        if let exportWindow {
            let lateCapture = try store.capture(text: "LATE UNIQUE action saved after opening export", at: Date())[0]
            fixtureIDs.insert(lateCapture.id)
            settle(0.3)
            let refreshedExportWindow = application.windows.first {
                $0 !== window && $0.isVisible
            } ?? exportWindow
            applicationKey(application, window: refreshedExportWindow, keyCode: 18, characters: "1",
                           modifiers: .command)
            let expected = DayExportDocument.make(captures: store.captures,
                                                  selectedDate: state.selectedDay).text
            try expect(copiedDay == expected && copiedDay?.contains("LATE UNIQUE") == true
                       && exportController.feedback == .copied(.day),
                       "Command 1 copies the current day, including actions saved after the popover opened")
            let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                          timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: refreshedExportWindow.windowNumber, context: nil,
                                          characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                                          isARepeat: false, keyCode: 53)!
            refreshedExportWindow.sendEvent(escape)
            settle(0.2)
            try expect(!refreshedExportWindow.isVisible, "Escape closes only the Export Day popover")
            try expect(window.isVisible && dismissals == 0,
                       "Escape from Export Day preserves the board window")
        }

        click(window, x: 190, topY: 55)
        if let reopenedPopover = application.windows.first(where: { $0 !== window && $0.isVisible }) {
            reopenedPopover.makeKey()
            settle()
            applicationKey(application, window: reopenedPopover, keyCode: 19, characters: "2",
                           modifiers: .command)
            try expect(destinationChoices == 1,
                       "Command 2 activates Export Text File without a pointer")
            exportController.dismiss()
            settle(0.2)
        } else {
            try expect(false, "Export Day reopens for keyboard navigation")
        }

        state.selectedDay = yesterday
        settle()
        let windowsBeforeDailyReset = Set(application.windows.filter { $0 !== window && $0.isVisible }.map(\.windowNumber))
        click(window, x: 190, topY: 55)
        if let resetPopover = newPopover(in: application, board: window, excluding: windowsBeforeDailyReset) {
            applicationKey(application, window: resetPopover, keyCode: 31, characters: "o",
                           modifiers: .command)
            try expect(Calendar.current.isDateInToday(state.selectedDay) && state.route == .daily
                       && !exportController.isPresented,
                       "The production Open Daily command closes a stale day export popover")
        } else {
            try expect(false, "Export Day opens before testing date-reset dismissal")
        }

        click(window, x: 250, topY: 55)
        try expect(state.route == .reminders, "Notifications preserves its existing reminders destination")
        state.route = .daily; settle()

        let windowsBeforeSettings = Set(application.windows.filter { $0 !== window && $0.isVisible }.map(\.windowNumber))
        click(window, x: 310, topY: 55)
        settle()
        let windowsAfterSettings = Set(application.windows.filter { $0 !== window && $0.isVisible }.map(\.windowNumber))
        try expect(state.route == .settings && windowsAfterSettings == windowsBeforeSettings,
                   "Settings opens its page directly without an intermediate submenu")
        state.route = .daily; settle()

        click(window, x: 118, topY: 90)
        try expect(state.filter == .text, "Copy/paste Text is the second centered filter")
        click(window, x: 166, topY: 90)
        try expect(state.filter == .links, "The filter row remains interactive beneath primary actions")
        click(window, x: 70, topY: 90)
        try expect(state.filter == .all, "The All filter remains the first centered filter")

        let initialDay = CaptureCalendar.dayString(state.selectedDay)
        try expect(!autoCaptureSettings.isEnabled && !autoCapture.isRunning,
                   "Auto Capture starts off before using its header toggle")
        click(window, x: 286, topY: 22)
        try expect(autoCaptureSettings.isEnabled && autoCapture.isRunning
                   && autoCaptureSettings.status == .monitoring,
                   "The button right of 7 Days turns Auto Capture on")
        click(window, x: 286, topY: 22)
        try expect(!autoCaptureSettings.isEnabled && !autoCapture.isRunning
                   && autoCaptureSettings.status == .disabled,
                   "The same header button turns Auto Capture off immediately")

        click(window, x: 94, topY: 22)
        try expect(CaptureCalendar.dayString(state.selectedDay) < initialDay,
                   "Previous-day navigation remains interactive beside the logo")
        click(window, x: 170, topY: 22)
        try expect(Calendar.current.isDateInToday(state.selectedDay),
                   "Next-day navigation returns to today and then disables")
        click(window, x: 244, topY: 22)
        try expect(state.route == .weekly && state.timelineMode == .weekly,
                   "The purple Weekly icon opens the seven-day view")
        click(window, x: 228, topY: 22)
        try expect(state.route == .daily && state.timelineMode == .daily,
                   "The purple Daily icon returns to the selected day")
        click(window, x: 132, topY: 22)
        try expect(state.route == .weekly, "The selected date still opens the Weekly view")

        let windowsBeforeMenuSearch = Set(application.windows.filter { $0 !== window && $0.isVisible }.map(\.windowNumber))
        applicationKey(application, window: window, keyCode: 40, characters: "k", modifiers: .command)
        let menuSearchWindow = newPopover(in: application, board: window, excluding: windowsBeforeMenuSearch)
        try expect(state.route == .weekly && state.weeklySearchActionsPresented && menuSearchWindow != nil,
                   "The production Command-K menu opens Weekly's scoped Search popover")
        if let menuSearchWindow {
            key(menuSearchWindow, keyCode: 53, characters: "\u{1b}")
        }

        let windowsBeforeWeeklySearch = Set(application.windows.filter { $0 !== window && $0.isVisible }.map(\.windowNumber))
        click(window, x: 130, topY: 55)
        let weeklySearchWindow = newPopover(in: application, board: window, excluding: windowsBeforeWeeklySearch)
        try expect(weeklySearchWindow != nil,
                   "Weekly Search opens an anchored day-or-week action popover")
        if let weeklySearchWindow {
            weeklySearchWindow.makeKey(); settle()
            applicationKey(application, window: weeklySearchWindow, keyCode: 18, characters: "1",
                           modifiers: .command)
            try expect(state.route == .search
                       && state.searchScope == .day(CaptureCalendar.dayString(state.selectedDay)),
                       "Command 1 chooses Search Day from the Weekly popover")
            let scopedSearch = state.searchScope
            applicationKey(application, window: window, keyCode: 40, characters: "k", modifiers: .command)
            try expect(state.route == .search && state.searchScope == scopedSearch,
                       "Command K preserves an active scoped Search and its Weekly return route")
            state.back(); settle()
        }

        let windowsBeforeWeekSearch = Set(application.windows.filter { $0 !== window && $0.isVisible }.map(\.windowNumber))
        click(window, x: 130, topY: 55)
        if let weeklySearchWindow = newPopover(in: application, board: window, excluding: windowsBeforeWeekSearch) {
            applicationKey(application, window: weeklySearchWindow, keyCode: 26, characters: "7",
                           modifiers: .command)
            try expect(state.route == .search
                       && state.searchScope == .week(Set(state.weeklyDays.map { CaptureCalendar.dayString($0) })),
                       "Command 7 chooses Search Week from the Weekly popover")
            state.back(); settle()
        } else {
            try expect(false, "Weekly Search reopens for keyboard scope selection")
        }

        let windowsBeforeWeeklyDayCopy = Set(application.windows.filter { $0 !== window && $0.isVisible }.map(\.windowNumber))
        click(window, x: 190, topY: 55)
        if let weeklyExportWindow = newPopover(in: application, board: window, excluding: windowsBeforeWeeklyDayCopy) {
            state.selectWeeklyActionDay(yesterday); settle(0.3)
            let refreshedExportWindow = application.windows.first {
                $0 !== window && $0.isVisible
            } ?? weeklyExportWindow
            applicationKey(application, window: refreshedExportWindow, keyCode: 18, characters: "1",
                           modifiers: .command)
            let expectedDay = DayExportDocument.make(captures: store.captures,
                                                     selectedDate: yesterday)
            try expect(copiedDay == expectedDay.text && copiedDay?.contains("YESTERDAY UNIQUE") == true
                       && copiedDay?.contains("TODAY UNIQUE") == false,
                       "Weekly Copy Day follows a day-picker change made after the popover opens")
            exportController.dismiss(); settle(0.2)
        } else {
            try expect(false, "Weekly Download opens for the selected-day copy action")
        }

        let windowsBeforeWeeklyDayDownload = Set(application.windows.filter { $0 !== window && $0.isVisible }.map(\.windowNumber))
        click(window, x: 190, topY: 55)
        if let weeklyExportWindow = newPopover(in: application, board: window, excluding: windowsBeforeWeeklyDayDownload) {
            applicationKey(application, window: weeklyExportWindow, keyCode: 19, characters: "2",
                           modifiers: .command)
            let expectedDay = DayExportDocument.make(captures: store.captures,
                                                     selectedDate: yesterday)
            try expect(destinationChoices == 2 && chosenExportPeriod == .day
                       && chosenExportFilename == expectedDay.filename,
                       "Weekly Download Day uses the selected day and its ISO filename")
            exportController.dismiss(); settle(0.2)
        } else {
            try expect(false, "Weekly Download reopens for the selected-day file action")
        }

        let windowsBeforeWeeklyCopy = Set(application.windows.filter { $0 !== window && $0.isVisible }.map(\.windowNumber))
        click(window, x: 190, topY: 55)
        if let weeklyExportWindow = newPopover(in: application, board: window, excluding: windowsBeforeWeeklyCopy) {
            applicationKey(application, window: weeklyExportWindow, keyCode: 26, characters: "7",
                           modifiers: .command)
            let expectedWeek = WeekExportDocument.make(captures: store.captures,
                                                       weekEndingDate: state.weekEndingDay)
            try expect(copiedDay == expectedWeek.text && exportController.feedback == .copied(.week),
                       "Command 7 copies the complete displayed week")
            exportController.dismiss(); settle()
        } else {
            try expect(false, "Weekly Download opens its anchored action popover")
        }

        let windowsBeforeWeeklyDownload = Set(application.windows.filter { $0 !== window && $0.isVisible }.map(\.windowNumber))
        click(window, x: 190, topY: 55)
        if let weeklyExportWindow = newPopover(in: application, board: window, excluding: windowsBeforeWeeklyDownload) {
            applicationKey(application, window: weeklyExportWindow, keyCode: 28, characters: "8",
                           modifiers: .command)
            let expectedWeek = WeekExportDocument.make(captures: store.captures,
                                                       weekEndingDate: state.weekEndingDay)
            try expect(destinationChoices == 3 && chosenExportPeriod == .week
                       && chosenExportFilename == expectedWeek.filename,
                       "Command 8 opens Download Week with the ISO range filename")
            exportController.dismiss(); settle()
        } else {
            try expect(false, "Weekly Download reopens for keyboard file export")
        }

        click(window, x: 228, topY: 22)
        try expect(state.route == .daily,
                   "The Daily icon remains usable when Weekly is laid out at 380 points")

        autoCaptureSettings.setPrivacyExplanationAcknowledged(false)
        autoCaptureSettings.setScreenshotFolderBookmark(nil)
        click(window, x: 286, topY: 22)
        try expect(state.route == .settings && !autoCaptureSettings.isEnabled,
                   "First use opens the required local privacy and folder setup instead of monitoring silently")
        state.route = .daily
        settle()

        click(window, x: 360, topY: 22)
        try expect(dismissals == 1 && state.route == .daily,
                   "The neutral X remains an independent close control")
        try expect(Set(store.captures.map(\.id)) == fixtureIDs,
                   "Header interaction QA leaves its isolated fixtures unchanged")
        print("PASS: \(checks) compact header interaction checks; native Add, Search, Export, Notifications, filters, dates, Escape and close controls.")
    }
}
