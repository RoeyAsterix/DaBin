import AppKit
import ApplicationServices
import SwiftUI

@MainActor private final class CalendarReminderClient: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .denied }
    func requestAuthorization() async throws -> Bool { false }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws {}
    func removePending(_ identifiers: [String]) {}
    func removeDelivered(_ identifiers: [String]) {}
}

@MainActor private struct CalendarAXNode {
    let object: NSObject

    private func value(_ name: String) -> Any? {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue()
    }

    private func attribute(_ name: String) -> Any? {
        let selector = NSSelectorFromString("accessibilityAttributeValue:")
        guard object.responds(to: selector),
              (value("accessibilityAttributeNames") as? [String])?.contains(name) == true else { return nil }
        return object.perform(selector, with: name as NSString)?.takeUnretainedValue()
    }

    var identifier: String? { (value("accessibilityIdentifier") as? String) ?? (attribute("AXIdentifier") as? String) }
    var label: String {
        [value("accessibilityLabel"), value("accessibilityTitle"), attribute("AXTitle"), attribute("AXDescription")]
            .compactMap { $0 as? String }.first { !$0.isEmpty } ?? ""
    }
    var textValue: String { (value("accessibilityValue") as? String) ?? (attribute("AXValue") as? String) ?? "" }
    var help: String {
        [value("accessibilityHelp"), attribute("AXHelp")].compactMap { $0 as? String }.first { !$0.isEmpty } ?? ""
    }
    var role: String { (value("accessibilityRole") as? String) ?? (attribute("AXRole") as? String) ?? "" }
    var frame: NSRect {
        let selector = NSSelectorFromString("accessibilityFrame")
        guard object.responds(to: selector) else { return .zero }
        typealias Getter = @convention(c) (AnyObject, Selector) -> NSRect
        return unsafeBitCast(object.method(for: selector), to: Getter.self)(object, selector)
    }
    func press() -> Bool {
        let selector = NSSelectorFromString("accessibilityPerformPress")
        guard object.responds(to: selector) else { return false }
        typealias Action = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(object.method(for: selector), to: Action.self)(object, selector)
    }
    var children: [Any] {
        var result: [Any] = []
        for name in ["accessibilityChildren", "accessibilityChildrenInNavigationOrder", "accessibilityContents"] {
            if let children = value(name) as? [Any] { result += children }
        }
        if let children = attribute("AXChildren") as? [Any] { result += children }
        if let view = object as? NSView { result += view.subviews }
        return result
    }
}

@main @MainActor private final class TimelineCalendarTests: NSObject, NSApplicationDelegate {
    private static var checks = 0
    private var result = 0
    static func main() {
        let application = NSApplication.shared
        let delegate = TimelineCalendarTests()
        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
        exit(Int32(delegate.result))
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await Self.run() }
            catch { result = 1; fputs("FAIL: \(error)\n", stderr) }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }
    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        if !condition() { throw NSError(domain: "TimelineCalendarTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    private static func settle() async { try? await Task.sleep(for: .milliseconds(180)) }
    private static func nodes(_ view: NSView) -> [CalendarAXNode] {
        view.layoutSubtreeIfNeeded()
        var found: [CalendarAXNode] = []
        var seen = Set<ObjectIdentifier>()
        func visit(_ value: Any, _ depth: Int) {
            guard depth < 50, let object = value as? NSObject, seen.insert(ObjectIdentifier(object)).inserted else { return }
            let node = CalendarAXNode(object: object)
            found.append(node)
            node.children.forEach { visit($0, depth + 1) }
        }
        visit(view, 0)
        NSAccessibility.unignoredChildren(from: [view]).forEach { visit($0, 0) }
        return found
    }
    private static func find(_ view: NSView, _ id: String) async throws -> CalendarAXNode {
        for _ in 0..<12 {
            if let node = nodes(view).first(where: { $0.identifier == id }) { return node }
            await settle()
        }
        throw NSError(domain: "TimelineCalendarTests", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Missing \(id): \(nodes(view).map { $0.identifier ?? $0.label })"])
    }
    private static func press(_ view: NSView, _ id: String) async throws {
        let node = try await find(view, id)
        try expect(node.press(), "Accessible action for \(id)")
        await settle()
    }
    private static func render(_ view: NSView, _ name: String) throws {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("build/qa/week-calendar")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.fileWriteUnknown) }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: directory.appendingPathComponent(name + ".png"))
    }
    private static func run() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.firstWeekday = 2
        let leap = calendar.date(from: DateComponents(year: 2024, month: 2, day: 1))!
        let cells = TimelineCalendarLayout.cells(in: leap, calendar: calendar)
        try expect(cells.count == 35 && cells.compactMap { $0 }.count == 29, "Leap month fits its five occupied weeks without a blank row")
        try expect(cells.firstIndex(where: { $0 != nil }) == 3, "Grid honors Monday as local week start")
        try expect(TimelineCalendarLayout.weekdays(calendar: calendar).first == calendar.veryShortStandaloneWeekdaySymbols[1],
                   "Weekday headings follow calendar firstWeekday")
        let march = calendar.date(from: DateComponents(year: 2024, month: 3, day: 1))!
        let marchDays = TimelineCalendarLayout.cells(in: march, calendar: calendar).compactMap { $0 }
        try expect(marchDays.count == 31 && Set(marchDays).count == 31,
                   "DST month has one cell per local calendar day")
        try expect(marchDays.allSatisfy { calendar.component(.hour, from: $0) == 0 }, "DST preserves midnight dates")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinCalendar-\(UUID())")
        let suite = "DaBinCalendar.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root)
        let previews = PreviewService(store: store)
        defer { previews.cancelNetwork() }
        let state = AppState(store: store, previews: previews,
            reminders: ReminderService(store: store, client: CalendarReminderClient()))
        let local = Calendar.current
        func day(_ value: Int) -> Date { local.date(from: DateComponents(year: 2025, month: 3, day: value))! }
        for value in [1, 5, 15] { _ = try store.capture(text: "Calendar fixture \(value)", at: day(value)) }
        state.selectWeeklyDay(day(15)); state.openWeekly()
        let original = state.weeklyDays
        var dismissals = 0
        let view = NSHostingView(rootView: TimelineCalendarPicker(state: state, weekly: true) { dismissals += 1 }
            .environment(\.daBinAccent, Color.purple).preferredColorScheme(.dark))
        view.frame = NSRect(x: 0, y: 0, width: 308, height: 500)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 308, height: 500),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view; window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        await settle()
        let accessibility = await Task.detached {
            let app = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            AXUIElementSetMessagingTimeout(app, 3)
            var windows: CFTypeRef?
            return AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows)
        }.value
        try expect(accessibility == .success, "Native calendar exposes its own accessibility hierarchy")
        let initial = try await find(view, "calendar-selection-count")
        try expect(initial.textValue == "7 of 7 days selected", "Calendar communicates the seven-day cap (label=\(initial.label), value=\(initial.textValue), role=\(initial.role), stateDays=\(state.weeklyDays.count))")
        let cell = try await find(view, "calendar-day-2025-03-15")
        try expect(cell.frame.width >= 36 && cell.frame.height >= 36, "Date controls have 36-point native targets")
        try await press(view, "calendar-clear")
        try expect(state.weeklyDays == original && dismissals == 0, "Draft selection does not resize or change the live week")
        try await press(view, "calendar-day-2025-03-01")
        try await press(view, "calendar-day-2025-03-03")
        try await press(view, "calendar-day-2025-03-05")
        try render(view, "calendar-selected-dark")
        try await press(view, "calendar-apply")
        try expect(dismissals == 1 && state.weeklyDays == [day(1), day(3), day(5)], "Apply commits exactly the chosen nonconsecutive days")
        try expect(state.weeklyVisibleDays == [day(1), day(5)], "Applying selected dates renders only populated columns while retaining the empty selected date")
        try expect(state.weeklyActiveDays == [day(1), day(5)], "The active-day count includes only chosen populated dates")
        for value in [7, 9, 11, 13] { try await press(view, "calendar-day-2025-03-\(String(format: "%02d", value))") }
        let atCap = try await find(view, "calendar-selection-count")
        try expect(atCap.textValue == "7 of 7 days selected", "Seven additions reach the cap")
        let eighth = try await find(view, "calendar-day-2025-03-15")
        _ = eighth.press(); await settle()
        let stillCapped = try await find(view, "calendar-selection-count")
        try expect(stillCapped.textValue == "7 of 7 days selected", "An eighth date cannot enter the selection")
        try await press(view, "calendar-cancel")
        try expect(state.weeklyDays == [day(1), day(3), day(5)], "Cancel preserves the previously applied week")
        try await press(view, "calendar-previous-month")
        _ = try await find(view, "calendar-day-2025-02-28")
        try await press(view, "calendar-next-month")
        try await press(view, "calendar-today")
        try await press(view, "calendar-apply")
        try expect(state.weeklyDays.count == 7 && local.isDateInToday(state.weeklyDays.last!) && !state.isCustomWeekSelection,
                   "Last 7 days restores the rolling current week")

        let daily = NSHostingView(rootView: TimelineCalendarPicker(state: state, weekly: false) { dismissals += 1 }
            .environment(\.daBinAccent, Color.purple).preferredColorScheme(.light))
        window.contentView = daily; daily.frame = view.frame; await settle()
        try expect(!nodes(daily).contains { $0.identifier == "calendar-apply" }, "Daily mode does not require an extra Apply step")
        try render(daily, "calendar-daily-light")
        try await press(daily, "calendar-today")
        try expect(state.route == .daily && local.isDateInToday(state.selectedDay), "Daily Today opens the date immediately")
        print("PASS: Timeline calendar \(checks) checks passed")
    }
}
