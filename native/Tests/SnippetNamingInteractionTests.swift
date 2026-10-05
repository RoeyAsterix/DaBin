import AppKit
import ApplicationServices
import Darwin
import Foundation
import SwiftUI

@MainActor private final class SnippetFixtureReminderClient: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .undetermined }
    func requestAuthorization() async throws -> Bool { fatalError("Snippet QA must not request notification permission") }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}

@MainActor private struct SnippetAX {
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
    var textValue: String? { (value("accessibilityValue") as? String) ?? (attribute("AXValue") as? String) }
    var role: String { (value("accessibilityRole") as? String) ?? (attribute("AXRole") as? String) ?? "" }
    var enabled: Bool {
        if let control = object as? NSControl { return control.isEnabled }
        for name in ["isAccessibilityEnabled", "accessibilityEnabled"] {
            let selector = NSSelectorFromString(name)
            guard object.responds(to: selector) else { continue }
            typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
            return unsafeBitCast(object.method(for: selector), to: Getter.self)(object, selector)
        }
        return false
    }
    var actions: [String] { (value("accessibilityActionNames") as? [String]) ?? [] }
    var frame: NSRect {
        let selector = NSSelectorFromString("accessibilityFrame")
        guard object.responds(to: selector) else { return .zero }
        typealias Getter = @convention(c) (AnyObject, Selector) -> NSRect
        return unsafeBitCast(object.method(for: selector), to: Getter.self)(object, selector)
    }
    var interactionFrame: NSRect {
        if let cell = object as? NSCell, let view = cell.controlView, let window = view.window {
            return window.convertToScreen(view.convert(view.bounds, to: nil))
        }
        return frame
    }
    private func action(_ name: String) -> Bool {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else { return false }
        typealias Action = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(object.method(for: selector), to: Action.self)(object, selector)
    }
    func press() -> Bool { action("accessibilityPerformPress") }
    func showMenu() -> Bool { action("accessibilityPerformShowMenu") }
    var children: [Any] {
        var result: [Any] = []
        for name in ["accessibilityChildren", "accessibilityChildrenInNavigationOrder", "accessibilityContents"] {
            if let children = value(name) as? [Any] { result += children }
        }
        if let children = attribute("AXChildren") as? [Any] { result += children }
        if let view = object as? NSView { result += view.subviews }
        return result
    }
    var diagnostic: String { "id=\(identifier ?? "nil") role=\(role) label=\(label) value=\(textValue ?? "nil") frame=\(frame)" }
}

/// Real Projects Clipboard/Shelf More menus and native naming sheets. Only this
/// process's fictional archive, dedicated preferences and window receive input.
/// No general clipboard, network, external opening or notification permission.
@main @MainActor private final class SnippetNamingInteractionTests: NSObject, NSApplicationDelegate {
    private static var checks = 0
    private var result: Int32 = 0
    static func main() {
        let watchdog = DispatchSource.makeTimerSource(queue: .global())
        watchdog.schedule(deadline: .now() + 60)
        watchdog.setEventHandler { fputs("Snippet naming QA exceeded 60 seconds\n", stderr); Darwin._exit(2) }
        watchdog.resume(); defer { watchdog.cancel() }
        let app = NSApplication.shared, delegate = SnippetNamingInteractionTests()
        app.setActivationPolicy(.accessory); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        exit(delegate.result)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await Self.run() }
            catch { result = 1; fputs("Snippet naming QA failed: \(error)\n", stderr) }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "SnippetNamingInteractionTests", code: checks, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        guard try value() else { throw failure(message) }
    }
    private static func nodes(_ view: NSView) -> [SnippetAX] {
        var result: [SnippetAX] = [], seen = Set<ObjectIdentifier>()
        func visit(_ candidate: Any, depth: Int) {
            guard depth < 50, let object = candidate as? NSObject, seen.insert(ObjectIdentifier(object)).inserted else { return }
            let node = SnippetAX(object: object); result.append(node)
            node.children.forEach { visit($0, depth: depth + 1) }
        }
        visit(view, depth: 0)
        NSAccessibility.unignoredChildren(from: [view]).forEach { visit($0, depth: 0) }
        return result
    }
    private static func settle(_ view: NSView) async {
        for _ in 0..<4 { view.layoutSubtreeIfNeeded(); try? await Task.sleep(for: .milliseconds(30)) }
    }
    private static func find(_ view: NSView, id: String) async throws -> SnippetAX {
        for _ in 0..<8 {
            if let node = nodes(view).first(where: { $0.identifier == id && $0.frame.width > 0 && $0.frame.height > 0 }) { return node }
            await settle(view)
        }
        throw failure("Missing native \(id):\n" + nodes(view).map(\.diagnostic).joined(separator: "\n"))
    }
    private static func press(_ view: NSView, id: String) async throws {
        let node = try await find(view, id: id)
        try expect(node.enabled && node.press(), "\(id) accepts its real enabled native action")
        await settle(view)
    }
    private static func namingSheet(_ window: NSWindow) async throws -> (NSWindow, NSView) {
        for _ in 0..<12 {
            if let sheet = window.attachedSheet, let view = sheet.contentView { await settle(view); return (sheet, view) }
            if let view = window.contentView { await settle(view) }
        }
        throw failure("The actual More naming action presents its own native sheet")
    }
    private static func nativeField(_ node: SnippetAX, in view: NSView) throws -> NSTextField {
        if let field = node.object as? NSTextField { return field }
        let candidates = nodes(view).compactMap { $0.object as? NSTextField }.filter { $0.isEditable && $0.isEnabled && !$0.isHiddenOrHasHiddenAncestor }
        guard let field = candidates.first(where: { field in
            guard let window = field.window else { return false }
            let frame = window.convertToScreen(field.convert(field.bounds, to: nil))
            let intersection = frame.intersection(node.frame), area = min(frame.width * frame.height, node.frame.width * node.frame.height)
            return area > 0 && !intersection.isNull && intersection.width * intersection.height / area > 0.5
        }) else { throw failure("The identified snippet name maps to a mounted native text field: \(node.diagnostic)") }
        return field
    }
    private static func enter(_ text: String, id: String, in view: NSView) async throws -> NSTextField {
        let field = try nativeField(try await find(view, id: id), in: view)
        guard let window = field.window else { throw failure("Snippet editor belongs to its naming sheet") }
        try expect(window.makeFirstResponder(field), "Snippet name accepts own-sheet native editing focus")
        guard let editor = field.currentEditor() as? NSTextView else { throw failure("Snippet name exposes its real native field editor") }
        editor.insertText(text, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        await settle(view)
        try expect(field.stringValue == text, "Native typing updates the actual visible snippet name")
        return field
    }
    private static func snapshot(_ view: NSView, to url: URL) throws {
        let rect = view.bounds.integral
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(rect.width * 2), pixelsHigh: Int(rect.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw failure("Cannot allocate naming-sheet native render")
        }
        bitmap.size = rect.size; view.cacheDisplay(in: rect, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw failure("Cannot encode native sheet") }
        try png.write(to: url, options: .atomic)
    }
    @MainActor private final class MenuTracking {
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        weak var window: NSWindow?
        private(set) var menus: [NSMenu] = []
        private(set) var ended = Set<ObjectIdentifier>()
        private(set) var timedOut = false
        init(window: NSWindow?) { self.window = window }
        func began(_ menu: NSMenu) { if !menus.contains(where: { $0 === menu }) { menus.append(menu) } }
        func didEnd(_ menu: NSMenu) { ended.insert(ObjectIdentifier(menu)) }
        func cancel() {
            menus.forEach { $0.cancelTrackingWithoutAnimation() }
            guard ProcessInfo.processInfo.systemUptime >= deadline else { return }
            timedOut = true
            guard let window, let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53) else { return }
            NSApp.postEvent(escape, atStart: true)
        }
    }
    private static func menuItems(_ menu: NSMenu) -> [NSMenuItem] { menu.items.flatMap { [$0] + ($0.submenu.map(menuItems) ?? []) } }
    private static func selectMore(_ view: NSView, window: NSWindow, id: String, title: String) async throws {
        let target = try await find(view, id: id), tracking = MenuTracking(window: window), center = NotificationCenter.default
        let began = center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { note in
            guard let menu = note.object as? NSMenu else { return }; MainActor.assumeIsolated { tracking.began(menu) }
        }
        let ended = center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: nil) { note in
            guard let menu = note.object as? NSMenu else { return }; MainActor.assumeIsolated { tracking.didEnd(menu) }
        }
        let timer = Timer(timeInterval: 0.02, repeats: true) { _ in MainActor.assumeIsolated { tracking.cancel() } }
        RunLoop.main.add(timer, forMode: .common); RunLoop.main.add(timer, forMode: .eventTracking)
        defer { timer.invalidate(); center.removeObserver(began); center.removeObserver(ended) }
        var accepted = target.actions.contains("AXShowMenu") ? target.showMenu() : false
        if !accepted && tracking.menus.isEmpty && target.actions.contains("AXPress") { accepted = target.press() }
        if !accepted && tracking.menus.isEmpty {
            let frame = target.interactionFrame
            try expect(window.frame.insetBy(dx: -1, dy: -1).contains(frame), "More input remains within this fixture window")
            let point = window.convertPoint(fromScreen: NSPoint(x: frame.midX, y: frame.midY)), stamp = ProcessInfo.processInfo.systemUptime
            guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: stamp,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1),
                  let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [], timestamp: stamp + 0.02,
                windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0) else { throw failure("Cannot create own-window More input") }
            NSApp.postEvent(up, atStart: true); window.sendEvent(down)
            if let event = NSApp.nextEvent(matching: .leftMouseUp, until: Date(), inMode: .default, dequeue: true) {
                try expect(event.windowNumber == window.windowNumber, "More release belongs only to this fixture")
                window.sendEvent(event)
            }
        }
        await settle(view)
        guard let menu = tracking.menus.first(where: { menuItems($0).contains { $0.title == title } }),
              let item = menuItems(menu).first(where: { $0.title == title }), let owner = item.menu else {
            throw failure("The actual native More menu contains \(title)")
        }
        try expect(!tracking.timedOut && tracking.ended.contains(ObjectIdentifier(menu)), "Native More closes before dispatch")
        try expect(item.isEnabled && !item.isHidden && item.action != nil, "\(title) is an actionable native menu item")
        owner.performActionForItem(at: owner.index(of: item)); await settle(view)
    }
    private static func run() async throws {
        let files = FileManager.default, root = files.temporaryDirectory.appendingPathComponent("DaBinSnippetQA-\(UUID())", isDirectory: true)
        let suite = "DaBinSnippetQA.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: PreviewService.linkPreviewPreference)
        let store = try CaptureStore(root: root, repairArchiveOnOpen: false)
        let capture = try store.createNote(text: "Fictional reusable client response. Original text must remain unchanged.", projectName: "Fictional snippets")
        let receipt = (capture.capturedAt, capture.captureDay, capture.originalText, capture.title)
        let previews = PreviewService(store: store, defaults: defaults)
        let auto = AutoCaptureService(settings: AutoCaptureSettings(defaults: defaults), input: InputService(store: store),
            pasteboardProvider: { fatalError("Snippet QA must not read the clipboard") }, sourceApplicationProvider: { nil })
        let state = AppState(store: store, previews: previews,
            reminders: ReminderService(store: store, client: SnippetFixtureReminderClient()), autoCapture: auto,
            captureClipboard: CaptureClipboardService(writer: { _ in fatalError("Snippet QA must not write the clipboard") }),
            folderOpener: { _ in fatalError("Snippet QA must not open external folders") })
        defer {
            state.workspace.failureInjector = nil; auto.shutdown(); previews.shutdown(); state.focusSessions.shutdown()
            state.shutdownNotificationPresentation(); store.cancelArchiveRepair()
            defaults.removePersistentDomain(forName: suite); try? files.removeItem(at: root)
        }
        state.libraryProject = "Fictional snippets"; state.openLibrary(); state.workspace.mode = .clipboard
        try state.workspace.setOnShelf([capture.id], included: true)
        let evidence = ProcessInfo.processInfo.environment["DABIN_SNIPPET_NAMING_QA_OUTPUT"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? root.appendingPathComponent("renders", isDirectory: true)
        try files.createDirectory(at: evidence, withIntermediateDirectories: true)
        let hosting = NSHostingView(rootView: LibraryScreen(state: state))
        let available = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        let window = NSWindow(contentRect: NSRect(x: available.minX + 24, y: available.maxY - 724, width: 380, height: 680),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "DaBin fictional snippet QA"; window.isReleasedWhenClosed = false; window.contentView = hosting
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        defer {
            if let sheet = window.attachedSheet { window.endSheet(sheet); sheet.orderOut(nil) }
            window.orderOut(nil); window.contentView = nil; window.close()
        }
        let activation = await Task.detached {
            let process = AXUIElementCreateApplication(getpid()); var windows: CFTypeRef?
            return AXUIElementCopyAttributeValue(process, kAXWindowsAttribute as CFString, &windows)
        }.value
        try expect(activation == .success, "Own-process native accessibility initializes")
        for _ in 0..<20 {
            if window.isKeyWindow { break }
            await settle(hosting)
        }
        try expect(window.isKeyWindow, "Only the fixture window accepts native text editing")
        for (mode, name) in [(WorkspaceMode.clipboard, "Client response — תודה"), (.shelf, "Approved client response — תודה")] {
            state.workspace.mode = mode; await settle(hosting)
            let before = state.workspace.snippetName(for: capture.id)
            let menuTitle = before == nil ? "Save as snippet…" : "Rename snippet…"
            try await selectMore(hosting, window: window, id: "workspace-more-\(capture.id.uuidString)", title: menuTitle)
            let (sheet, sheetView) = try await namingSheet(window)
            _ = try await enter(name, id: "workspace-snippet-name-\(capture.id.uuidString)", in: sheetView)
            var attempts = 0
            state.workspace.failureInjector = { attempts += 1; throw WorkspaceError.invalidArchive }
            try await press(sheetView, id: "workspace-snippet-save-\(capture.id.uuidString)")
            try expect(attempts == 1 && window.attachedSheet === sheet, "One failed naming save retains its native sheet")
            let retainedField = try nativeField(try await find(sheetView, id: "workspace-snippet-name-\(capture.id.uuidString)"), in: sheetView)
            try expect(retainedField.stringValue == name, "Failed save retains the exact typed naming draft in its mounted native field")
            let error = try await find(sheetView, id: "workspace-snippet-error-\(capture.id.uuidString)")
            try expect(error.label.contains("Couldn’t save") || error.textValue?.contains("Couldn’t save") == true,
                       "Naming failure is visibly explained next to the retained draft: \(error.diagnostic)")
            let retry = try await find(sheetView, id: "workspace-snippet-save-\(capture.id.uuidString)")
            try expect(retry.label == "Retry save" && retry.enabled, "Failed naming draft has an explicit enabled retry")
            try expect(state.workspace.snippetName(for: capture.id) == before
                && WorkspaceStore(root: root).snippetName(for: capture.id) == before, "Failure leaves the saved alias unchanged in memory and after restart")
            try snapshot(sheetView, to: evidence.appendingPathComponent("snippet-\(mode.rawValue)-failed-native@2x.png"))
            state.workspace.failureInjector = { attempts += 1 }
            try await press(sheetView, id: "workspace-snippet-save-\(capture.id.uuidString)")
            await settle(hosting)
            try expect(attempts == 2 && window.attachedSheet == nil, "Retry commits exactly once and closes only after success")
            state.workspace.failureInjector = nil
            try expect(state.workspace.snippetName(for: capture.id) == name
                && WorkspaceStore(root: root).snippetName(for: capture.id) == name, "Retry persists the exact typed alias across restart")
            try expect(store.captures.count == 1 && capture.capturedAt == receipt.0 && capture.captureDay == receipt.1
                && capture.originalText == receipt.2 && capture.title == receipt.3
                && state.workspace.shelfCaptureIDs == Set([capture.id]), "Naming never duplicates or changes the saved capture, receipt, title or shelf membership")
        }
        try await selectMore(hosting, window: window, id: "workspace-more-\(capture.id.uuidString)", title: "Rename snippet…")
        let (_, cancelView) = try await namingSheet(window)
        _ = try await enter("Discard this unsaved naming draft", id: "workspace-snippet-name-\(capture.id.uuidString)", in: cancelView)
        let savedName = state.workspace.snippetName(for: capture.id)
        try await press(cancelView, id: "workspace-snippet-cancel-\(capture.id.uuidString)")
        await settle(hosting)
        try expect(window.attachedSheet == nil && state.workspace.snippetName(for: capture.id) == savedName,
                   "Explicit Cancel closes the form without changing the saved alias")
        try await selectMore(hosting, window: window, id: "workspace-more-\(capture.id.uuidString)", title: "Rename snippet…")
        let (_, reopenedView) = try await namingSheet(window)
        let reopened = try nativeField(try await find(reopenedView, id: "workspace-snippet-name-\(capture.id.uuidString)"), in: reopenedView)
        try expect(reopened.stringValue == savedName, "Reopening after intentional Cancel starts from the saved alias")
        _ = try await enter("   ", id: "workspace-snippet-name-\(capture.id.uuidString)", in: reopenedView)
        let emptySave = try await find(reopenedView, id: "workspace-snippet-save-\(capture.id.uuidString)")
        try expect(!emptySave.enabled, "An empty trimmed name cannot be saved")
        try await press(reopenedView, id: "workspace-snippet-cancel-\(capture.id.uuidString)")
        print("PASS: \(checks) native Projects Clipboard/Shelf naming checks; real More dispatch, native text entry, retained failed drafts, visible retry, exactly-once save, restart, cancellation, and immutable capture; no general clipboard or external access")
    }
}
