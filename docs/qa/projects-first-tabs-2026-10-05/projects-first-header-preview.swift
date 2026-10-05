@testable import DaBinTestCore
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
    func accessibilityRole() -> String? {
        (value("accessibilityRole") as? String) ?? (attribute("AXRole") as? String)
    }
    func accessibilityLabel() -> String? {
        for candidate in [value("accessibilityLabel") as? String,
                          attribute("AXTitle") as? String,
                          attribute("AXDescription") as? String] {
            if let candidate, !candidate.isEmpty { return candidate }
        }
        return nil
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
    /// Native popup cells expose their rendered symbol through AXFrame. Their
    /// actual clickable region belongs to the backing NSPopUpButton view.
    func interactionFrame() -> NSRect {
        if let cell = object as? NSCell, let view = cell.controlView, let window = view.window {
            return window.convertToScreen(view.convert(view.bounds, to: nil))
        }
        return accessibilityFrame()
    }
    func supportsAccessiblePress() -> Bool {
        object.responds(to: NSSelectorFromString("accessibilityPerformPress"))
            || ((value("accessibilityActionNames") as? [String])?.contains("AXPress") == true
                && object.responds(to: NSSelectorFromString("accessibilityPerformAction:")))
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
    @MainActor private static func waitForSearchEditor(in hosting: NSView, window: NSWindow) async -> Bool {
        func hasSearchEditor(_ view: NSView) -> Bool {
            if let field = view as? NSTextField, field.placeholderString == BoardView.searchPlaceholder,
               let editor = field.currentEditor() as? NSTextView {
                return editor.isFieldEditor && window.firstResponder === editor
            }
            return view.subviews.contains(where: hasSearchEditor)
        }
        // The production field yields once after mounting before restoring its
        // FocusState. A nested synchronous RunLoop cannot reliably release this
        // fixture's current main-actor job for that task to continue.
        let deadline = Date().addingTimeInterval(1)
        repeat {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(10))
            settle(0.01)
            if hasSearchEditor(hosting) { return true }
        } while Date() < deadline
        return false
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
    @MainActor private static func choose(_ title: String, in hosting: NSView, identifier: String) throws {
        let control = try element(hosting, identifier: identifier).object
        let popups = elements(in: hosting).compactMap { node in
            (node.object as? NSPopUpButton) ?? ((node.object as? NSCell)?.controlView as? NSPopUpButton)
        }
        let popup = (control as? NSPopUpButton) ?? ((control as? NSCell)?.controlView as? NSPopUpButton)
            ?? popups.first { $0.item(withTitle: title) != nil }
        guard let popup, let item = popup.item(withTitle: title) else {
            let inventory = elements(in: hosting).map { "\(type(of: $0.object)): \($0.accessibilityLabel() ?? "")" }
            throw NSError(domain: "HeaderInteractionTests", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "Date mode must expose its real native popup and \(title) action. Node: \(type(of: control)); popups: \(popups.map { $0.itemTitles }); nodes: \(inventory)"])
        }
        if let action = popup.action {
            popup.select(item)
            try expect(NSApplication.shared.sendAction(action, to: popup.target, from: popup),
                       "Date mode dispatches its real native selection action")
        } else {
            // SwiftUI's native popup owns the binding action on each NSMenuItem,
            // not on NSPopUpButton. Dispatch that actual item, not an AppState setter.
            try expect(item.action != nil && popup.menu != nil, "Date mode exposes a native menu-item binding action")
            popup.menu?.performActionForItem(at: popup.index(of: item))
        }
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

    @MainActor private static func click(_ screenPoint: NSPoint, in window: NSWindow) throws {
        let point = window.convertPoint(fromScreen: screenPoint)
        try expect(window.contentView?.bounds.contains(point) == true,
                   "The synthetic record-button click stays inside its own fixture window")
        let timestamp = ProcessInfo.processInfo.systemUptime
        guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
            timestamp: timestamp, windowNumber: window.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1),
              let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [],
            timestamp: timestamp + 0.02, windowNumber: window.windowNumber, context: nil,
            eventNumber: 2, clickCount: 1, pressure: 0) else {
            throw NSError(domain: "HeaderInteractionTests", code: 7,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create the own-window record-button click"])
        }
        // A native button may consume mouse-up while tracking mouse-down.
        // Keep both events in this process and target only this retained window.
        NSApplication.shared.postEvent(up, atStart: true)
        window.sendEvent(down)
        if let remaining = NSApplication.shared.nextEvent(matching: .leftMouseUp, until: Date(),
                                                          inMode: .default, dequeue: true) {
            try expect(remaining.windowNumber == window.windowNumber,
                       "The remaining record-button mouse-up belongs to this fixture")
            window.sendEvent(remaining)
        }
        settle()
    }

    @MainActor private static func recordButtonInteractions(_ hosting: NSView, window: NSWindow,
                                                             state: AppState) throws {
        let settings = state.autoCapture.settings
        let captureIDs = Set(state.store.captures.map(\.id))
        try expect(!settings.isEnabled && !state.autoCapture.isRunning,
                   "Record-button interaction starts with capture disabled and its runtime stopped")
        state.openDaily(); settle()

        func indicators(in view: NSView) -> [AutoRecordIndicatorView] {
            if let indicator = view as? AutoRecordIndicatorView { return [indicator] }
            return view.subviews.flatMap { indicators(in: $0) }
        }
        for interaction in ["dot center", "target edge", "accessibility press"] {
            let buttons = elements(in: hosting).filter {
                $0.accessibilityIdentifier() == "timeline-auto-capture"
                    && $0.accessibilityRole() == NSAccessibility.Role.button.rawValue
            }
            try expect(buttons.count == 1,
                       "\(interaction): the record control exposes exactly one header accessibility button")
            let button = buttons[0]
            let frame = button.interactionFrame()
            try expect(abs(frame.width - 40) <= 1 && abs(frame.height - 34) <= 1,
                       "\(interaction): the record button retains its 40×34-point target")
            try expect(button.accessibilityLabel() == "Set up Auto Capture" && button.supportsAccessiblePress(),
                       "\(interaction): the record button retains its setup label and accessibility action")
            if interaction == "accessibility press" {
                try press(hosting, identifier: "timeline-auto-capture")
            } else {
                let nativeIndicators = indicators(in: hosting)
                try expect(nativeIndicators.count == 1 && nativeIndicators[0].window === window,
                           "\(interaction): the production native dot belongs to this fixture window")
                let indicator = nativeIndicators[0]
                let drawing = window.convertToScreen(indicator.convert(indicator.bounds, to: nil))
                let point = interaction == "dot center"
                    ? NSPoint(x: drawing.midX, y: drawing.midY)
                    : NSPoint(x: frame.minX + 2, y: frame.midY)
                try expect(frame.contains(point) && (interaction != "target edge" || !drawing.contains(point)),
                           "\(interaction): the click probes the intended dot or padded button region")
                try click(point, in: window)
            }
            try expect(state.route == .settings,
                       "\(interaction): activating the disabled record control opens Auto Capture setup")
            _ = try element(hosting, identifier: "settings-capture-clipboard")
            _ = try element(hosting, identifier: "settings-capture-screenshots")
            try expect(!settings.isEnabled && !settings.isClipboardEnabled && !settings.isScreenshotsEnabled
                        && !state.autoCapture.isRunning && Set(state.store.captures.map(\.id)) == captureIDs,
                       "\(interaction): opening setup starts no capture channel and preserves saved data")
            try press(hosting, identifier: "board-back")
            try expect(state.route == .daily, "\(interaction): Back restores the daily board")
        }
        // SwiftUI button keyboard focus follows macOS Keyboard navigation.
        // Do not change that user preference or substitute AXPress for Space.
        print("NOT TESTED: Record-button Space activation depends on macOS Keyboard navigation; this fixture leaves that preference unchanged.")
    }

    @MainActor private static func snapshot(_ view: NSView, at url: URL) throws {
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw NSError(domain: "HeaderInteractionTests", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot render the isolated Inbox fixture"])
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "HeaderInteractionTests", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot encode the isolated Inbox fixture"])
        }
        try data.write(to: url, options: .atomic)
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
        _ = (current, older)
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
        let theme = ThemeSettings(defaults: defaults)
        let hosting = NSHostingView(rootView: BoardView(state: state, theme: theme)
            .frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = DaBinPanel(contentRect: NSRect(x: 80, y: 80, width: size.width, height: size.height),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.becomesKeyOnlyIfNeeded = false
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

        for id in ["primary-inbox", "primary-today", "primary-workspace", "inbox-organize", "timeline-mode-daily", "timeline-mode-weekly", "board-search", "timeline-action-add", "board-more", "board-settings", "timeline-auto-capture", "window-expand", "window-close", "auto-capture-status"] {
            let control = try element(hosting, identifier: id)
            let frame = control.accessibilityFrame()
            try expect(frame.width > 0 && frame.height > 0, "\(id) has an accessible visible target")
            try expect(frame.minX >= window.frame.minX - 1 && frame.maxX <= window.frame.maxX + 1,
                       "\(id) fits the compact 380-point window")
        }
        // Measure the actual visible control envelope at three window sizes. A
        // flexible drag handle previously absorbed hundreds of vertical points
        // before the feed; checking only intrinsic view sizes missed that bug.
        // Keep search one action away without reserving an unused field row.
        let toolbarIDs = ["timeline-auto-capture", "timeline-action-add", "board-search", "board-settings", "board-more", "window-expand", "window-close"]
        let menuIDs: Set<String> = ["board-more"]
        let primaryIDs = ["primary-inbox", "primary-today", "primary-workspace"]
        for layoutSize in [NSSize(width: 380, height: 430), size, NSSize(width: 760, height: 760)] {
            hosting.rootView = BoardView(state: state, theme: theme)
                .frame(width: layoutSize.width, height: layoutSize.height)
            window.setContentSize(layoutSize)
            hosting.frame = NSRect(origin: .zero, size: layoutSize)
            settle()
            for route in [BoardRoute.inbox, .reminders, .library] {
                switch route {
                case .inbox: state.openInbox()
                case .reminders: state.showReminders()
                default: state.openLibrary()
                }
                settle()
                // AX frames describe the visible controls. Native popup backing
                // views also contain an invisible left inset, which must not be
                // confused with an overlap between rendered header controls.
                let toolbarFrames = try toolbarIDs.map { try element(hosting, identifier: $0).accessibilityFrame() }
                let navigationFrames = try primaryIDs.map { try element(hosting, identifier: $0).accessibilityFrame() }
                let headerFrames = toolbarFrames + navigationFrames
                let envelope = headerFrames.reduce(NSRect.null) { $0.union($1) }
                let layoutDescription = "\(route) at \(Int(layoutSize.width))×\(Int(layoutSize.height))"
                try expect(envelope.height <= 74, "Two-row header stays compact for \(layoutDescription) (actual \(envelope.height))")
                try expect(headerFrames.allSatisfy { $0.minX >= window.frame.minX - 1 && $0.maxX <= window.frame.maxX + 1 },
                           "All header controls fit for \(layoutDescription)")
                // Native borderless menu cells keep their preexisting intrinsic
                // symbol-sized hosts. Check the minimum target on icon Buttons
                // and the menu's real native bounds/action separately.
                let iconFrames = zip(toolbarIDs, toolbarFrames).filter { !menuIDs.contains($0.0) }.map(\.1)
                try expect(iconFrames.allSatisfy { $0.width >= 28 && $0.height >= 28 },
                           "Compaction preserves icon button hit targets for \(layoutDescription)")
                for id in menuIDs {
                    let menu = try element(hosting, identifier: id)
                    let frame = menu.interactionFrame()
                    try expect(frame.width > 0 && frame.height > 0 && menu.supportsAccessiblePress(),
                               "\(id) remains a visible native menu with an accessible press action for \(layoutDescription)")
                }
                try expect(toolbarFrames.allSatisfy { abs($0.midY - toolbarFrames[0].midY) < 1 },
                           "Toolbar controls stay on one aligned row for \(layoutDescription)")
                try expect(navigationFrames.allSatisfy { abs($0.midY - navigationFrames[0].midY) < 1 },
                           "Primary navigation stays on one aligned row for \(layoutDescription)")
                try expect(zip(toolbarFrames, toolbarFrames.dropFirst()).allSatisfy { $0.0.maxX <= $0.1.minX + 1 },
                           "Toolbar actions never overlap for \(layoutDescription)")
                try expect(!elements(in: hosting).contains { $0.accessibilityIdentifier() == "global-search" },
                           "An inactive search field does not reserve a third header row for \(layoutDescription)")
            }
        }
        state.openInbox()
        hosting.rootView = BoardView(state: state, theme: theme).frame(width: size.width, height: size.height)
        window.setContentSize(size); hosting.frame = NSRect(origin: .zero, size: size); settle()
        try expect(state.route == .inbox, "Initial route is the capture Inbox")
        let evidence = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("build/qa/inbox-calendar", isDirectory: true)
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        let tabEvidence = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("../docs/qa/projects-first-tabs-2026-10-05/previews", isDirectory: true)
        try FileManager.default.createDirectory(at: tabEvidence, withIntermediateDirectories: true)
        for previewSize in [NSSize(width: 380, height: 560), NSSize(width: 760, height: 760)] {
            hosting.rootView = BoardView(state: state, theme: theme).frame(width: previewSize.width, height: previewSize.height)
            window.setContentSize(previewSize); hosting.frame = NSRect(origin: .zero, size: previewSize); settle()
            for route in [BoardRoute.library, .reminders, .inbox] {
                switch route {
                case .library: state.openLibrary()
                case .reminders: state.showReminders()
                default: state.openInbox()
                }
                settle()
                try snapshot(hosting, at: tabEvidence.appendingPathComponent("tabs-\(route)-\(Int(previewSize.width)).png"))
            }
        }
        print("PASS: \(checks) existing native header visibility/layout checks; tab previews: \(tabEvidence.path)")
    }
}
