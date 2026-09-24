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

    /// AppKit tracking controls synchronously wait for their mouse-up event.
    /// Queue that event before delivering mouse-down so the native segmented
    /// control can complete without depending on a running NSApplication loop.
    @MainActor private static func clickTrackingControl(_ window: NSWindow,
                                                        x: CGFloat, topY: CGFloat) {
        let point = NSPoint(x: x, y: window.contentLayoutRect.height - topY)
        let stamp = ProcessInfo.processInfo.systemUptime
        let mouseUp = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [],
                                         timestamp: stamp + 0.01, windowNumber: window.windowNumber,
                                         context: nil, eventNumber: 2, clickCount: 1, pressure: 0)!
        NSApp.postEvent(mouseUp, atStart: false)
        let mouseDown = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
                                           timestamp: stamp, windowNumber: window.windowNumber,
                                           context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        window.sendEvent(mouseDown)
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
        let autoCapture = AutoCaptureService(settings: AutoCaptureSettings(defaults: defaults),
                                             input: input)
        let exportCapture = try store.capture(text: "Keyboard export fixture")[0]
        var copiedDay: String?
        var destinationChoices = 0
        let exportController = DayExportActionController(pasteboardWriter: {
            copiedDay = $0
            return true
        }, destinationChooser: { _ in
            destinationChoices += 1
            return .cancelled
        }, fileWriter: { _, _ in })
        let state = AppState(store: store, previews: previews,
                             reminders: ReminderService(store: store, client: HeaderReminderClient()),
                             robotPlacement: RobotPlacementSettings(defaults: defaults),
                             autoCapture: autoCapture)
        let theme = ThemeSettings(defaults: defaults)
        var dismissals = 0
        state.onDismiss = { dismissals += 1 }
        state.isBoardVisible = true

        let size = NSSize(width: 380, height: 500)
        let hosting = NSHostingView(rootView: BoardView(state: state, theme: theme,
                                                        dayExportController: exportController)
            .frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        application.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        settle(0.25)

        // The fixed header geometry is also the compact 380-point render
        // contract: row 1 center 22, row 2 center 55, filters center 90.
        click(window, x: 94, topY: 55)
        try expect(state.route == .newTask, "Add opens the task composer from the compact primary row")
        state.route = .daily; settle()

        click(window, x: 142, topY: 55)
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
            exportWindow.makeKey()
            settle()
            key(exportWindow, keyCode: 8, characters: "c", modifiers: .command)
            let expected = DayExportDocument.make(captures: store.captures,
                                                  selectedDate: state.selectedDay).text
            try expect(copiedDay == expected && exportController.feedback == .copied,
                       "Command C activates Copy Day without a pointer")
            let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                          timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: exportWindow.windowNumber, context: nil,
                                          characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                                          isARepeat: false, keyCode: 53)!
            exportWindow.sendEvent(escape)
            settle(0.2)
            try expect(!exportWindow.isVisible, "Escape closes only the Export Day popover")
            try expect(window.isVisible && dismissals == 0,
                       "Escape from Export Day preserves the board window")
        }

        click(window, x: 190, topY: 55)
        if let reopenedPopover = application.windows.first(where: { $0 !== window && $0.isVisible }) {
            reopenedPopover.makeKey()
            settle()
            key(reopenedPopover, keyCode: 1, characters: "s", modifiers: .command)
            try expect(destinationChoices == 1,
                       "Command S activates Export Text File without a pointer")
            exportController.dismiss()
            settle(0.2)
        } else {
            try expect(false, "Export Day reopens for keyboard navigation")
        }

        click(window, x: 238, topY: 55)
        try expect(state.route == .reminders, "Notifications preserves its existing reminders destination")
        state.route = .daily; settle()

        click(window, x: 118, topY: 90)
        try expect(state.filter == .text, "Copy/paste Text is the second centered filter")
        click(window, x: 166, topY: 90)
        try expect(state.filter == .links, "The filter row remains interactive beneath primary actions")
        click(window, x: 70, topY: 90)
        try expect(state.filter == .all, "The All filter remains the first centered filter")

        let initialDay = CaptureCalendar.dayString(state.selectedDay)
        click(window, x: 110, topY: 22)
        try expect(CaptureCalendar.dayString(state.selectedDay) < initialDay,
                   "Previous-day navigation remains interactive beside the logo")
        click(window, x: 194, topY: 22)
        try expect(Calendar.current.isDateInToday(state.selectedDay),
                   "Next-day navigation returns to today and then disables")
        click(window, x: 152, topY: 22)
        try expect(state.route == .weekly, "The selected date still opens the Weekly view")
        clickTrackingControl(window, x: 265, topY: 22)
        try expect(state.route == .daily,
                   "The Daily segment remains usable when Weekly is laid out at 380 points")

        click(window, x: 354, topY: 22)
        try expect(dismissals == 1 && state.route == .daily,
                   "The neutral X remains an independent close control")
        try expect(store.captures.map(\.id) == [exportCapture.id],
                   "Header interaction QA leaves its one isolated fixture unchanged")
        print("PASS: \(checks) compact header interaction checks; native Add, Search, Export, Notifications, filters, dates, Escape and close controls.")
    }
}
