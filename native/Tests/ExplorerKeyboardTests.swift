import AppKit
import ApplicationServices
import Darwin
import Foundation
import SwiftUI

@MainActor private final class ExplorerKeyboardWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor private final class ExplorerKeyboardNotifications: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .undetermined }
    func requestAuthorization() async throws -> Bool { false }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}

@MainActor private struct ExplorerKeyboardAX {
    let object: NSObject
    func value(_ name: String) -> Any? {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue()
    }
    var identifier: String? {
        if let value = value("accessibilityIdentifier") as? String { return value }
        let selector = NSSelectorFromString("accessibilityAttributeValue:")
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector, with: "AXIdentifier" as NSString)?.takeUnretainedValue() as? String
    }
    var frame: NSRect {
        let selector = NSSelectorFromString("accessibilityFrame")
        guard object.responds(to: selector) else { return .zero }
        typealias Getter = @convention(c) (AnyObject, Selector) -> NSRect
        return unsafeBitCast(object.method(for: selector), to: Getter.self)(object, selector)
    }
    var children: [Any] {
        var result: [Any] = []
        for name in ["accessibilityChildren", "accessibilityChildrenInNavigationOrder", "accessibilityContents"] {
            if let values = value(name) as? [Any] { result += values }
        }
        if let view = object as? NSView { result += view.subviews }
        return result
    }
}

/// Native List keyboard integration, not direct state/handler invocation.
/// The only key/mouse events are sent to this process's synthetic window. All
/// captures/preferences are temporary; no real clipboard or user archive.
@main @MainActor private final class ExplorerKeyboardTests: NSObject, NSApplicationDelegate {
    private static var checks = 0
    private var result: Int32 = 0

    static func main() {
        let app = NSApplication.shared
        let delegate = ExplorerKeyboardTests()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        exit(delegate.result)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await Self.run() }
            catch { result = 1; fputs("Explorer keyboard QA failed: \(error)\n", stderr) }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard condition() else {
            throw NSError(domain: "ExplorerKeyboardTests", code: checks,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private static func settle(_ view: NSView, milliseconds: Int = 120) async throws {
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(milliseconds))
        view.layoutSubtreeIfNeeded()
    }

    private static func findTable(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        return view.subviews.lazy.compactMap { findTable(in: $0) }.first
    }

    private static func nodes(in view: NSView) -> [ExplorerKeyboardAX] {
        var seen = Set<ObjectIdentifier>()
        var result: [ExplorerKeyboardAX] = []
        func visit(_ value: Any, depth: Int) {
            guard depth < 36, let object = value as? NSObject,
                  seen.insert(ObjectIdentifier(object)).inserted else { return }
            let node = ExplorerKeyboardAX(object: object)
            result.append(node)
            for child in node.children { visit(child, depth: depth + 1) }
        }
        visit(view, depth: 0)
        NSAccessibility.unignoredChildren(from: [view]).forEach { visit($0, depth: 0) }
        return result
    }

    /// Only inspect rows AppKit has already materialized; traversing the whole
    /// table's AX children can create the offscreen rows under test.
    private static func control(for id: UUID, in table: NSTableView) -> ExplorerKeyboardAX? {
        var result: ExplorerKeyboardAX?
        table.enumerateAvailableRowViews { row, _ in
            guard result == nil else { return }
            result = nodes(in: row).first { $0.identifier == "workspace-item-\(id.uuidString)" }
        }
        return result
    }

    private static func visible(_ id: UUID, in table: NSTableView, window: NSWindow) -> Bool {
        guard let control = control(for: id, in: table), !control.frame.isEmpty else { return false }
        let viewport = window.convertToScreen(table.convert(table.visibleRect, to: nil))
        return viewport.intersects(control.frame)
    }

    private static func click(_ control: ExplorerKeyboardAX, in window: NSWindow) throws {
        let point = window.convertPoint(fromScreen: NSPoint(x: control.frame.midX, y: control.frame.midY))
        let now = ProcessInfo.processInfo.systemUptime
        guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
            timestamp: now, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1),
              let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [],
            timestamp: now + 0.01, windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0) else {
            throw NSError(domain: "ExplorerKeyboardTests", code: 900)
        }
        // Native button tracking may consume mouse-up synchronously.
        NSApp.postEvent(up, atStart: true)
        NSApp.sendEvent(down)
        if let remaining = NSApp.nextEvent(matching: .leftMouseUp, until: Date(), inMode: .default, dequeue: true) {
            NSApp.sendEvent(remaining)
        }
    }

    private static func key(_ characters: String, code: UInt16, in window: NSWindow) throws {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) else {
                throw NSError(domain: "ExplorerKeyboardTests", code: 901)
            }
            // Deliberately use the application dispatch path: it executes the
            // viewport helper's local input monitor before native key handling.
            NSApp.sendEvent(event)
        }
    }

    private static func ordered(_ state: AppState) -> [Capture] {
        ExplorerQuery.sections(ExplorerQuery.items(state.store.captures, workspace: state.workspace,
            project: state.libraryProject, filter: state.filter, pinnedOnly: state.libraryPinnedOnly),
            grouping: state.workspace.explorerGrouping).flatMap(\.captures)
    }

    private static func run() async throws {
        let watchdog = DispatchWorkItem {
            FileHandle.standardError.write(Data("FAIL: Explorer keyboard regression exceeded 45 seconds\n".utf8))
            _exit(124)
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 45, execute: watchdog)
        defer { watchdog.cancel() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinExplorerKeyboard-\(UUID().uuidString)")
        let suite = "DaBinExplorerKeyboard.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: PreviewService.linkPreviewPreference)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let date = Date(timeIntervalSince1970: 1_791_000_000)
        let fixtures = (0..<96).map { index in
            let link = index < 16
            let capture = Capture(capturedAt: date.addingTimeInterval(Double(96 - index)),
                timeZone: TimeZone(secondsFromGMT: 0)!, kind: link ? .link : .text,
                originalURL: link ? "https://example.invalid/keyboard/\(index)" : nil,
                originalText: "Fictional keyboard receipt \(index)", title: "Keyboard fixture \(index)")
            capture.projectName = "Keyboard fixture project"
            capture.previewState = link ? "unavailable" : "ready"
            return capture
        }
        try CaptureRepository(root: root).save(fixtures)
        let store = try CaptureStore(root: root, repairArchiveOnOpen: false)
        let previews = PreviewService(store: store, defaults: defaults)
        let auto = AutoCaptureService(settings: AutoCaptureSettings(defaults: defaults), input: InputService(store: store),
            pasteboardProvider: { fatalError("Keyboard QA must not read a clipboard") }, sourceApplicationProvider: { nil })
        let state = AppState(store: store, previews: previews,
            reminders: ReminderService(store: store, client: ExplorerKeyboardNotifications()), autoCapture: auto,
            captureClipboard: CaptureClipboardService(writer: { _ in fatalError("Keyboard QA must not write a clipboard") }))
        defer { state.focusSessions.shutdown(); state.shutdownNotificationPresentation(); previews.shutdown(); auto.shutdown() }
        state.route = .library
        state.isBoardVisible = true
        state.libraryProject = "Keyboard fixture project"
        state.workspace.explorerGrouping = .type
        state.workspace.explorerShowsDailyFiles = false
        let initialOrder = ordered(state)
        let restored = initialOrder[38]
        let initial = initialOrder[39]
        state.workspace.selectedCaptureID = restored.id
        let hosting = NSHostingView(rootView: ExplorerScreen(state: state))
        hosting.sizingOptions = []
        hosting.frame = NSRect(x: 0, y: 0, width: 1_000, height: 560)
        let window = ExplorerKeyboardWindow(contentRect: NSRect(x: 100, y: 100, width: 1_000, height: 560),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        try await settle(hosting, milliseconds: 250)
        let accessibility = await Task.detached {
            let process = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            AXUIElementSetMessagingTimeout(process, 3)
            var windows: CFTypeRef?
            return AXUIElementCopyAttributeValue(process, kAXWindowsAttribute as CFString, &windows)
        }.value
        try expect(accessibility == .success, "Own-process native row accessibility initializes")
        try await settle(hosting)
        window.makeKey()
        try await settle(hosting)
        try expect(window.isKeyWindow, "The synthetic fixture receives keyboard focus (active: \(NSApp.isActive), responder: \(String(describing: window.firstResponder)))")
        guard let table = findTable(in: hosting), let scroll = table.enclosingScrollView,
              let initialControl = control(for: initial.id, in: table) else {
            throw NSError(domain: "ExplorerKeyboardTests", code: 902,
                          userInfo: [NSLocalizedDescriptionKey: "Project restoration did not materialize its selected capture in the native List"])
        }
        try expect(visible(restored.id, in: table, window: window), "Restored project selection is visible")
        try click(initialControl, in: window)
        try await settle(hosting)
        try expect(state.workspace.selectedCaptureID == initial.id && state.route == .library,
                   "Clicking the expanded row selects it without opening details")
        print("FOCUS after click: \(String(describing: window.firstResponder)); active \(NSApp.isActive); native selection \(table.selectedRowIndexes); selected \(state.workspace.selectedCaptureID?.uuidString ?? "none")")

        for index in 40...59 {
            try key("\u{F701}", code: 125, in: window)
            try await settle(hosting, milliseconds: 70)
            try expect(state.workspace.selectedCaptureID == initialOrder[index].id,
                       "Arrow Down selects logical capture \(index) through the actual native responder (selected: \(state.workspace.selectedCaptureID?.uuidString ?? "none"), expected: \(initialOrder[index].id), responder: \(String(describing: window.firstResponder)), native selection: \(table.selectedRowIndexes))")
            try expect(visible(initialOrder[index].id, in: table, window: window),
                       "Arrow Down scrolls capture \(index) into the recycled native viewport")
        }
        try expect(control(for: initial.id, in: table) == nil,
                   "The original row is truly recycled after keyboard navigation, not retained offscreen")
        for index in stride(from: 58, through: 39, by: -1) {
            try key("\u{F700}", code: 126, in: window)
            try await settle(hosting, milliseconds: 70)
            try expect(state.workspace.selectedCaptureID == initialOrder[index].id,
                       "Arrow Up restores logical capture \(index), including a previously recycled row")
        }
        try expect(visible(initial.id, in: table, window: window), "Returning with Arrow Up rematerializes and reveals the original row")

        // A store mutation arms viewport preservation. A subsequent real local
        // key event must cancel it so the requested row stays in view after the
        // entire 0.6-second restoration window, not snap back to the old anchor.
        let beforeMoveY = scroll.contentView.bounds.minY
        _ = try store.capture(text: "An automatic fixture arriving during keyboard reading", at: date.addingTimeInterval(200),
                              receipt: .automatic(.automaticClipboard), projectName: state.libraryProject)
        let currentOrder = ordered(state)
        let selectedIndex = currentOrder.firstIndex { $0.id == initial.id }!
        let afterInsertionTarget = currentOrder[selectedIndex + 5]
        // Move farther than the entire former viewport, during the guard's
        // 0.6-second lifetime. macOS List need not center its native row exactly;
        // the real contract is honoring navigation without snapping back.
        for offset in 1...5 {
            try key("\u{F701}", code: 125, in: window)
            try await settle(hosting, milliseconds: 70)
            try expect(state.workspace.selectedCaptureID == currentOrder[selectedIndex + offset].id,
                       "A real keyboard move wins over the pending insertion anchor (step \(offset))")
        }
        try await settle(hosting, milliseconds: 750)
        try expect(state.workspace.selectedCaptureID == afterInsertionTarget.id
                   && visible(afterInsertionTarget.id, in: table, window: window),
                   "Intentional keyboard selection remains visible after the viewport guard expires")
        try expect(scroll.contentView.bounds.minY - beforeMoveY > scroll.contentView.bounds.height
                   && !visible(initial.id, in: table, window: window),
                   "After guard expiry navigation stays beyond the entire former viewport, with the former selection offscreen")
        try key("\r", code: 36, in: window)
        try await settle(hosting)
        try expect(state.route == .detail && state.selectedCapture?.id == afterInsertionTarget.id,
                   "Return opens the keyboard-selected recycled capture, not a stale row")
        var availableRows = 0
        table.enumerateAvailableRowViews { _, _ in availableRows += 1 }
        try expect(availableRows < 30 && table.numberOfRows >= 97,
                   "Keyboard traversal keeps native rows bounded while preserving every logical item")
        print("PASS: \(checks) native Explorer keyboard checks; 45 Up/Down transitions, recycled rows, project restoration, incoming capture, viewport-guard cancellation, and Return. Available rows: \(availableRows).")
    }
}
