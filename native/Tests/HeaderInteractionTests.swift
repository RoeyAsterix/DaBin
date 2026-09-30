import AppKit
import ApplicationServices
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

/// SwiftUI's virtual accessibility nodes implement AppKit selectors without
/// always declaring conformance to the complete NSAccessibility protocol.
/// Invoke the documented own-process methods after checking each selector;
/// requiring protocol conformance here silently discards those real controls.
@MainActor
private struct HeaderAccessibilityNode {
    let object: NSObject

    private func value(_ selectorName: String) -> Any? {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue()
    }

    private func attribute(_ name: String) -> Any? {
        let selector = NSSelectorFromString("accessibilityAttributeValue:")
        guard object.responds(to: selector),
              (value("accessibilityAttributeNames") as? [String])?.contains(name) == true else { return nil }
        return object.perform(selector, with: name as NSString)?.takeUnretainedValue()
    }

    func accessibilityIdentifier() -> String? {
        (value("accessibilityIdentifier") as? String) ?? (attribute("AXIdentifier") as? String)
    }
    func accessibilityLabel() -> String? {
        (value("accessibilityLabel") as? String) ?? (attribute("AXTitle") as? String)
            ?? (attribute("AXDescription") as? String)
    }
    func accessibilityFrame() -> NSRect {
        let selector = NSSelectorFromString("accessibilityFrame")
        if object.responds(to: selector) {
            typealias FrameGetter = @convention(c) (AnyObject, Selector) -> NSRect
            let getter = unsafeBitCast(object.method(for: selector), to: FrameGetter.self)
            return getter(object, selector)
        }
        if let position = attribute("AXPosition") as? NSValue,
           let size = attribute("AXSize") as? NSValue {
            return NSRect(origin: position.pointValue, size: size.sizeValue)
        }
        return .zero
    }
    func accessibilityPerformPress() -> Bool {
        let selector = NSSelectorFromString("accessibilityPerformPress")
        if object.responds(to: selector) {
            typealias PressAction = @convention(c) (AnyObject, Selector) -> Bool
            let action = unsafeBitCast(object.method(for: selector), to: PressAction.self)
            return action(object, selector)
        }
        let legacySelector = NSSelectorFromString("accessibilityPerformAction:")
        guard (value("accessibilityActionNames") as? [String])?.contains("AXPress") == true,
              object.responds(to: legacySelector) else { return false }
        _ = object.perform(legacySelector, with: "AXPress" as NSString)
        return true
    }
    var children: [Any] {
        var results: [Any] = []
        for selector in ["accessibilityChildren", "accessibilityChildrenInNavigationOrder", "accessibilityContents"] {
            if let values = value(selector) as? [Any] { results.append(contentsOf: values) }
        }
        if let values = attribute("AXChildren") as? [Any] { results.append(contentsOf: values) }
        // Some AppKit bridge views are ignored accessibility containers and
        // reveal their SwiftUI virtual tree only below a physical subview.
        if let view = object as? NSView { results.append(contentsOf: view.subviews) }
        return results
    }
}

/// Interacts only with an isolated production window, through its accessibility
/// elements and application menu. No global pointer, clipboard or user archive.
@main
private enum HeaderInteractionTests {
    @MainActor private static var checks = 0

    @MainActor private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard condition() else {
            throw NSError(domain: "HeaderInteractionTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
    @MainActor private static func settle(_ seconds: TimeInterval = 0.18) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
    @MainActor private static func elements(in view: NSView) -> [HeaderAccessibilityNode] {
        view.layoutSubtreeIfNeeded()
        var result: [HeaderAccessibilityNode] = []
        var visited = Set<ObjectIdentifier>()
        func visit(_ candidate: Any, depth: Int) {
            guard depth < 40, let object = candidate as? NSObject,
                  visited.insert(ObjectIdentifier(object)).inserted else { return }
            let node = HeaderAccessibilityNode(object: object)
            result.append(node)
            for child in node.children { visit(child, depth: depth + 1) }
        }
        visit(view, depth: 0)
        for child in NSAccessibility.unignoredChildren(from: [view]) { visit(child, depth: 0) }
        return result
    }
    @MainActor private static func element(_ hosting: NSView, identifier: String) throws -> HeaderAccessibilityNode {
        var nodes = elements(in: hosting)
        for _ in 0..<5 {
            if let result = nodes.first(where: { $0.accessibilityIdentifier() == identifier }) { return result }
            settle(0.1)
            nodes = elements(in: hosting)
        }
        let inventory = nodes.map {
            "\(String(describing: type(of: $0.object))): \($0.accessibilityIdentifier() ?? "no identifier") / \($0.accessibilityLabel() ?? "no label")"
        }.joined(separator: "; ")
        throw NSError(domain: "HeaderInteractionTests", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Missing accessible control: \(identifier). Own-window accessibility inventory: \(inventory)"])
    }
    @MainActor private static func press(_ hosting: NSView, identifier: String) throws {
        let control = try element(hosting, identifier: identifier)
        try expect(control.accessibilityPerformPress(), "\(identifier) exposes a native press action")
        settle()
    }
    @MainActor private static func key(_ application: NSApplication, window: NSWindow,
                                      code: UInt16, text: String, modifiers: NSEvent.ModifierFlags = []) {
        window.makeKey()
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers,
                                        timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: window.windowNumber, context: nil, characters: text,
                                        charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
            application.sendEvent(event)
        }
        settle()
    }

    @MainActor static func main() async throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.finishLaunching()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinHeaderInteractions-\(UUID().uuidString)")
        let suite = "DaBinHeaderInteractions.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root)
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let current = try store.capture(text: "Today header fixture", at: now)[0]
        let older = try store.capture(text: "Earlier global search fixture", at: yesterday)[0]
        let settings = AutoCaptureSettings(defaults: defaults)
        let autoCapture = AutoCaptureService(settings: settings, input: InputService(store: store),
                                             pasteboardProvider: { fatalError("Header QA must not access the clipboard") },
                                             sourceApplicationProvider: { nil })
        defer { autoCapture.shutdown() }
        let previews = PreviewService(store: store, defaults: defaults)
        let state = AppState(store: store, previews: previews,
                             reminders: ReminderService(store: store, client: HeaderReminderClient()),
                             autoCapture: autoCapture)
        var expansions = 0
        state.onToggleExpandedWindow = { expansions += 1 }
        var dismissals = 0
        state.onDismiss = { dismissals += 1 }
        let size = NSSize(width: 380, height: 560)
        let hosting = NSHostingView(rootView: BoardView(state: state, theme: ThemeSettings(defaults: defaults))
            .frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        application.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        let previousMenu = application.mainMenu
        let commandMenu = ApplicationMenu(openDaily: { state.openDaily() }, openSearch: { state.performSearchCommand() },
                                           focusRobot: {}, showSettings: { state.showSettings() })
        commandMenu.install()
        defer {
            commandMenu.uninstall(); application.mainMenu = previousMenu
            window.orderOut(nil); window.contentView = nil; window.close()
        }
        settle(0.3)

        // SwiftUI creates its virtual accessibility nodes lazily when an
        // accessibility client first requests this process's window hierarchy.
        // Keep the main actor available to service that request, then inspect
        // only our retained hosting view. This uses the public AX API and does
        // not request access to other applications or change system settings.
        let accessibilityActivation = await Task.detached {
            let process = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            AXUIElementSetMessagingTimeout(process, 3)
            var windows: CFTypeRef?
            return AXUIElementCopyAttributeValue(process, kAXWindowsAttribute as CFString, &windows)
        }.value
        try expect(accessibilityActivation == .success,
                   "Own-process accessibility activation succeeds (AX error \(accessibilityActivation.rawValue))")
        settle()

        for id in ["primary-today", "primary-library", "primary-follow-ups", "global-search", "timeline-action-add", "board-more", "board-settings", "timeline-auto-capture", "window-expand", "timeline-date", "window-close"] {
            let control = try element(hosting, identifier: id)
            let frame = control.accessibilityFrame()
            try expect(frame.width > 0 && frame.height > 0, "\(id) has an accessible visible target")
            try expect(frame.minX >= window.frame.minX - 1 && frame.maxX <= window.frame.maxX + 1,
                       "\(id) fits the compact 380-point window")
        }
        var filterFrames: [NSRect] = []
        for filter in CaptureFilter.allCases {
            let icon = try element(hosting, identifier: "capture-filter-\(filter.rawValue)")
            let frame = icon.accessibilityFrame()
            filterFrames.append(frame)
            try expect(frame.width >= 30 && frame.height >= 30, "Icon filter has a usable hit target")
            try expect(!(icon.accessibilityLabel() ?? "").isEmpty, "Icon filter retains an accessible label")
        }
        try expect(filterFrames.allSatisfy { abs($0.midY - filterFrames[0].midY) < 1 }, "All filter icons align on one row")
        try press(hosting, identifier: "capture-filter-text")
        try expect(state.filter == .text, "Text icon filters copied text")
        try press(hosting, identifier: "capture-filter-all")
        try press(hosting, identifier: "window-expand")
        try expect(expansions == 1 && dismissals == 0, "Expand remains independent of Close")
        try press(hosting, identifier: "board-settings")
        try expect(state.route == .settings, "Gear opens Settings directly")
        state.openDaily(); settle()
        let add = try element(hosting, identifier: "timeline-action-add")
        try expect(add.accessibilityLabel() == "Add capture", "Add describes capture choices instead of pretending to create only tasks")
        let search = try element(hosting, identifier: "global-search")
        try expect(search.accessibilityLabel() == "Search all captures across all dates", "Persistent search states its archive scope")
        try press(hosting, identifier: "primary-library")
        try expect(state.route == .library, "Library tab opens the archive")
        try press(hosting, identifier: "primary-follow-ups")
        try expect(state.route == .reminders, "Follow-ups tab opens the action queue")
        try press(hosting, identifier: "primary-today")
        try expect(state.route == .daily && Calendar.current.isDateInToday(state.selectedDay), "Today returns to the current receipt day")

        let existingWindows = Set(application.windows.filter(\.isVisible).map(\.windowNumber))
        try press(hosting, identifier: "timeline-date")
        let calendar = application.windows.first { $0.isVisible && !existingWindows.contains($0.windowNumber) }
        try expect(calendar != nil && state.route == .daily, "Day date opens a calendar without switching to Week")
        if let calendar { key(application, window: calendar, code: 53, text: "\u{1b}") }
        try expect(dismissals == 0, "Closing the calendar leaves the board available")
        state.openWeekly(); settle()
        let weeklyLabel = try element(hosting, identifier: "timeline-date").accessibilityLabel() ?? ""
        try expect(weeklyLabel.hasPrefix("Choose date"), "Week uses the same date-picker control as Day")
        state.filter = .files
        key(application, window: window, code: 40, text: "k", modifiers: .command)
        try expect(state.route == .search && state.searchScope == .all && state.filter == .all,
                   "Command K searches the entire archive from Week and clears stale type filters")
        let firstFocusRequest = state.globalSearchFocusRequest
        key(application, window: window, code: 40, text: "k", modifiers: .command)
        try expect(state.globalSearchFocusRequest > firstFocusRequest, "Command K focuses an already-open search")
        state.updateGlobalSearch("Earlier")
        try expect(state.searchGroups.flatMap(\.entries).contains(where: { $0.capture.id == older.id && $0.isMatch }),
                   "Global search finds captures outside today")
        state.openDaily(); settle()
        if let setup = elements(in: hosting).first(where: { $0.accessibilityLabel() == "Set up" }) {
            try expect(setup.accessibilityPerformPress(), "Capture setup exposes a labeled action")
            settle()
            try expect(state.route == .settings && !settings.isEnabled && !autoCapture.isRunning,
                       "Setup opens Settings without implicitly enabling capture")
        } else { try expect(false, "Disabled automatic capture has a visible Set up control") }
        try press(hosting, identifier: "window-close")
        try expect(dismissals == 1, "Hide remains independently accessible")
        try expect(Set(store.captures.map(\.id)) == Set([current.id, older.id]), "Header checks do not mutate captured data")
        print("PASS: \(checks) native labeled-header accessibility and interaction checks")
    }
}
