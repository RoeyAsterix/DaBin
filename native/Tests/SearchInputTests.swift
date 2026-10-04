import AppKit
import ApplicationServices
import Foundation
import SwiftUI

@MainActor private final class SearchInputReminderClient: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .undetermined }
    func requestAuthorization() async throws -> Bool { fatalError("Search input QA must not request notification permission") }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}

/// The unrelated editable control has its own Paste action, which deliberately
/// never consults the general clipboard. Production Search must defer to it.
@MainActor private final class SearchInputEditorProbe: NSTextView {
    var pastes = 0
    var pasteValidations = 0
    var keyEvents = 0
    var equivalents = 0
    override func paste(_ sender: Any?) { pastes += 1 }
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        // NSTextView's standard Paste validation reads NSPasteboard.general.
        // This probe has a deliberately private Paste action instead.
        if item.action == #selector(NSText.paste(_:)) { pasteValidations += 1; return true }
        return super.validateUserInterfaceItem(item)
    }
    override func keyDown(with event: NSEvent) { keyEvents += 1; super.keyDown(with: event) }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        equivalents += 1
        // Receiving this own-process event is the routing assertion. Execute
        // the probe's private action instead of NSTextView's clipboard reader.
        if event.type == .keyDown, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "v" {
            paste(nil); return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor private struct SearchInputAX {
    let object: NSObject
    func value(_ name: String) -> Any? {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue()
    }
    var label: String {
        [value("accessibilityLabel"), value("accessibilityTitle"), value("accessibilityDescription")]
            .compactMap { $0 as? String }.first { !$0.isEmpty } ?? ""
    }
    var children: [Any] {
        var result: [Any] = []
        for name in ["accessibilityChildren", "accessibilityChildrenInNavigationOrder", "accessibilityContents"] {
            if let children = value(name) as? [Any] { result += children }
        }
        if let view = object as? NSView { result += view.subviews }
        return result
    }
    func press() -> Bool {
        let selector = NSSelectorFromString("accessibilityPerformPress")
        guard object.responds(to: selector) else { return false }
        typealias Action = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(object.method(for: selector), to: Action.self)(object, selector)
    }
}

/// Actual production controller, panel, host and Search field editor. Native
/// key events stay in this process; paste fallback reads a named private
/// pasteboard. No global events, personal store, user clipboard, network or
/// permission prompts. Lack of native focus is a failure, never a skipped pass.
@main @MainActor private final class SearchInputTests: NSObject, NSApplicationDelegate {
    private static var checks = 0
    private static var timestamp: TimeInterval = 10_000
    private static var lastKeyDown: NSEvent?
    private var result: Int32 = 0

    static func main() {
        let app = NSApplication.shared
        let delegate = SearchInputTests()
        app.setActivationPolicy(.accessory); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        exit(delegate.result)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await Self.run() }
            catch { result = 1; fputs("Search input QA failed: \(error)\n", stderr) }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "SearchInputTests", code: checks, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard condition() else { throw failure(message) }
    }
    private static func settle(_ milliseconds: Int = 100) async {
        await Task.yield(); try? await Task.sleep(for: .milliseconds(milliseconds))
    }
    private static func wait(_ message: String, until condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline { await settle(30) }
        try expect(condition(), message)
    }
    private static func textFields(in view: NSView) -> [NSTextField] {
        (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap { textFields(in: $0) }
    }
    private static func searchField(_ controller: CornerController) throws -> NSTextField {
        guard let field = textFields(in: controller.captureHostingView).first(where: {
            $0.placeholderString == "Search everything saved in DaBin"
        }) else { throw failure("Production Search has no mounted native query NSTextField") }
        return field
    }
    private static func hasSearchEditor(_ controller: CornerController) -> Bool {
        guard let field = try? searchField(controller), let editor = field.currentEditor() as? NSTextView else { return false }
        return editor.isFieldEditor && controller.board.firstResponder === editor
    }
    private static func requireSearchFocus(_ controller: CornerController, _ context: String) async throws {
        try await wait("\(context) focuses the mounted production Search field editor") { hasSearchEditor(controller) }
        try expect(NSApp.isActive && NSApp.keyWindow === controller.board && controller.board.isKeyWindow,
                   "\(context) owns real native keyboard focus; active=\(NSApp.isActive), firstResponder=\(String(describing: controller.board.firstResponder))")
    }
    private static func key(_ window: NSWindow, text: String, code: UInt16, modifiers: NSEvent.ModifierFlags = []) async {
        timestamp += 1
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers,
                timestamp: timestamp, windowNumber: window.windowNumber, context: nil,
                characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
            if type == .keyDown { lastKeyDown = event }
            NSApp.sendEvent(event)
        }
        await settle(45)
    }
    private static func type(_ text: String, in controller: CornerController) async {
        // Character events exercise AppKit's text-input path and SwiftUI's
        // binding; no AppState query assignment or direct insertText shortcut.
        for character in text { await key(controller.board, text: String(character), code: 0) }
        await settle()
    }
    private static func clear(_ controller: CornerController) async throws {
        var seen = Set<ObjectIdentifier>()
        func find(_ candidate: Any, depth: Int) -> SearchInputAX? {
            guard depth < 35, let object = candidate as? NSObject,
                  seen.insert(ObjectIdentifier(object)).inserted else { return nil }
            let node = SearchInputAX(object: object)
            if node.label == "Clear search", object.responds(to: NSSelectorFromString("accessibilityPerformPress")) { return node }
            for child in node.children { if let match = find(child, depth: depth + 1) { return match } }
            return nil
        }
        guard let clear = find(controller.captureHostingView, depth: 0) else { throw failure("Production Search has no native Clear search action") }
        try expect(clear.press(), "Clear search exposes its real native press action")
        await settle()
        try expect(controller.state.query.isEmpty, "The production Clear search action clears the query")
    }
    private static func loseFocus(_ controller: CornerController) throws {
        try expect(controller.board.makeFirstResponder(controller.captureHostingView), "Production host can receive non-editor focus")
        try expect(!hasSearchEditor(controller), "Paste regression starts without an active Search editor")
    }

    private static func run() async throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinSearchInputQA-\(UUID().uuidString)")
        let suite = "DaBinSearchInputQA.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let privateBoard = NSPasteboard(name: .init("DaBin.SearchInputQA.\(UUID().uuidString)"))
        let previousMenu = NSApp.mainMenu
        defer {
            NSApp.mainMenu = previousMenu; privateBoard.releaseGlobally()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: scratch)
        }
        let store = try CaptureStore(root: scratch)
        _ = try store.createNote(text: "atlas northstar fictional search content", projectName: "Northstar")
        let originalIDs = Set(store.captures.map(\.id))
        let previews = PreviewService(store: store, defaults: defaults)
        let input = InputService(store: store)
        let autoCapture = AutoCaptureService(settings: AutoCaptureSettings(defaults: defaults), input: input,
            pasteboardProvider: { fatalError("Search input QA must not read the general clipboard") }, sourceApplicationProvider: { nil })
        let state = AppState(store: store, previews: previews,
            reminders: ReminderService(store: store, client: SearchInputReminderClient()), autoCapture: autoCapture,
            manualInput: input)
        defer { autoCapture.shutdown(); previews.shutdown(); state.shutdownNotificationPresentation(); store.cancelArchiveRepair() }
        let controller = CornerController(state: state, input: input, placementDefaults: defaults,
            theme: ThemeSettings(defaults: defaults), animateRobotTransitions: false, robotReduceMotion: { false })
        defer { controller.shutdown() }
        var privateReads = 0, capturePastes = 0
        controller.captureHostingView.searchPasteboardProvider = { privateReads += 1; return privateBoard }
        controller.captureHostingView.onPaste = { capturePastes += 1 }
        let menu = ApplicationMenu(openDaily: { controller.openDaily() }, openSearch: { controller.openSearch() },
            focusRobot: {}, showSettings: { state.showSettings() })
        menu.install(); defer { menu.uninstall() }
        NSApp.activate(ignoringOtherApps: true)
        controller.openSearch()
        await settle(200)
        let accessibilityActivation = await Task.detached {
            let process = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            AXUIElementSetMessagingTimeout(process, 3)
            var windows: CFTypeRef?
            return AXUIElementCopyAttributeValue(process, kAXWindowsAttribute as CFString, &windows)
        }.value
        try expect(accessibilityActivation == .success, "Own-process accessibility activates the production Clear search action")
        try await requireSearchFocus(controller, "Initial Search entry")
        await type("atlas", in: controller)
        try expect(state.query == "atlas", "Real character key events update the query immediately")

        try loseFocus(controller)
        await key(controller.board, text: "k", code: 40, modifiers: .command)
        try await requireSearchFocus(controller, "Repeated native Search command")
        try expect(state.query == "atlas", "Refocusing Search preserves the existing query")
        try await clear(controller)
        try await requireSearchFocus(controller, "Clear search")
        await type("north", in: controller)
        try expect(state.query == "north", "Typing after Clear does not require clicking the field")

        state.selectSearchProject("Northstar"); state.filter = .text
        let retained = (state.query, state.searchProject, state.filter, state.searchScope)
        controller.dismiss(); await settle()
        try expect(!controller.board.isVisible, "Immediate close hides the production panel")
        controller.openDaily(); await settle(200)
        try await requireSearchFocus(controller, "Immediate resume of retained Search")
        try expect(state.query == retained.0 && state.searchProject == retained.1 && state.filter == retained.2 && state.searchScope == retained.3,
                   "Immediate hide/reopen retains the query and deliberate search refinements")
        try await clear(controller)
        await type("resume", in: controller)
        try expect(state.query == "resume", "Resumed Search receives actual typing without a manual focus repair")

        try await clear(controller)
        try expect(privateBoard.setString("private direct paste", forType: .string), "Private direct-paste fixture is written")
        try loseFocus(controller)
        let beforeDirect = privateReads
        controller.board.paste(nil)
        await settle(200)
        try expect(state.query == "private direct paste" && privateReads == beforeDirect + 1,
                   "Native direct Paste without an editor focuses Search and reads its private text once; query=\(state.query), reads=\(privateReads - beforeDirect), canPaste=\(controller.captureHostingView.canPasteSearch), fieldID=\(String(describing: try? searchField(controller).accessibilityIdentifier()))")
        try await requireSearchFocus(controller, "Direct Search paste")
        try expect(capturePastes == 0 && Set(store.captures.map(\.id)) == originalIDs,
                   "Search Paste creates no capture and never reaches capture intake")

        try await clear(controller)
        privateBoard.clearContents()
        try expect(privateBoard.setString("private shortcut paste", forType: .string), "Private shortcut-paste fixture is written")
        try loseFocus(controller)
        let beforeShortcut = privateReads
        await key(controller.board, text: "v", code: 9, modifiers: .command)
        await settle(150)
        try expect(state.query == "private shortcut paste" && privateReads == beforeShortcut + 1,
                   "A real Command V event without an editor pastes into Search exactly once")
        try await requireSearchFocus(controller, "Command V Search paste")
        try expect(capturePastes == 0 && Set(store.captures.map(\.id)) == originalIDs,
                   "Command V changes only Search text, never archive records")

        guard let handledShortcut = lastKeyDown else { throw failure("Search shortcut event was not retained") }
        let guardedReads = privateReads
        state.route = .weekly
        try expect(!controller.captureHostingView.handleSearchPasteShortcut(handledShortcut),
                   "A previously handled Search event is rejected after navigating to another route")
        try expect(privateReads == guardedReads && capturePastes == 0,
                   "Wrong-route event rejection never reads Search or captures content")
        state.route = .search; await settle(150)
        let foreignWindow = DaBinPanel(contentRect: NSRect(x: -5_000, y: -5_000, width: 80, height: 80),
            styleMask: [.borderless], backing: .buffered, defer: false)
        foreignWindow.isReleasedWhenClosed = false
        defer { foreignWindow.close() }
        let foreignEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: handledShortcut.timestamp, windowNumber: foreignWindow.windowNumber, context: nil,
            characters: "v", charactersIgnoringModifiers: "v", isARepeat: false, keyCode: 9)!
        try expect(!controller.captureHostingView.handleSearchPasteShortcut(foreignEvent),
                   "Another native window's Command V never reaches this Search host")
        try expect(privateReads == guardedReads && capturePastes == 0,
                   "Wrong-window event rejection leaves Search's private pasteboard untouched")

        let otherEditor = SearchInputEditorProbe(frame: NSRect(x: 8, y: 8, width: 180, height: 36))
        otherEditor.isEditable = true; otherEditor.string = "Another editor keeps its own text"
        controller.captureHostingView.addSubview(otherEditor)
        defer { otherEditor.removeFromSuperview() }
        try expect(controller.board.makeFirstResponder(otherEditor), "An unrelated editable native control can own focus")
        let beforeOther = (state.query, privateReads, capturePastes)
        let pasteSelector = #selector(NSText.paste(_:))
        try expect(NSApp.target(forAction: pasteSelector, to: nil, from: nil) as? NSTextView === otherEditor,
                   "Native Paste target stays with the active unrelated editor")
        try expect(NSApp.sendAction(pasteSelector, to: nil, from: nil), "Native direct Paste dispatches through the actual responder chain")
        let editMenu = NSApp.mainMenu?.items.first { $0.title == "Edit" }?.submenu
        editMenu?.update()
        let pasteMenuItem = editMenu?.items.first { $0.action == pasteSelector }
        let afterDirectOther = "pastes=\(otherEditor.pastes), text=\(String(reflecting: otherEditor.string)), query=\(String(reflecting: state.query)), reads=\(privateReads), captures=\(capturePastes), first=\(String(describing: controller.board.firstResponder)), key=\(String(describing: NSApp.keyWindow))"
        await key(controller.board, text: "v", code: 9, modifiers: .command)
        try expect(otherEditor.pastes == 2 && otherEditor.equivalents == 1 && otherEditor.string == "Another editor keeps its own text",
                   "Direct Paste and Command V remain the unrelated editor's own actions. After direct: \(afterDirectOther). After Cmd V: pastes=\(otherEditor.pastes), pasteValidations=\(otherEditor.pasteValidations), keyEvents=\(otherEditor.keyEvents), equivalents=\(otherEditor.equivalents), menuEnabled=\(String(describing: pasteMenuItem?.isEnabled)), menuKey=\(String(describing: pasteMenuItem?.keyEquivalent)), menuModifiers=\(String(describing: pasteMenuItem?.keyEquivalentModifierMask)), text=\(String(reflecting: otherEditor.string)), query=\(String(reflecting: state.query)), reads=\(privateReads), captures=\(capturePastes), first=\(String(describing: controller.board.firstResponder)), key=\(String(describing: NSApp.keyWindow))")
        try expect(state.query == beforeOther.0 && privateReads == beforeOther.1 && capturePastes == beforeOther.2,
                   "Other-editor Paste never reads Search text or creates a capture")
        otherEditor.removeFromSuperview()
        controller.shutdown()

        let animated = CornerController(state: state, input: input, placementDefaults: defaults,
            theme: ThemeSettings(defaults: defaults), animateRobotTransitions: true, robotReduceMotion: { false })
        defer { animated.shutdown() }
        animated.captureHostingView.searchPasteboardProvider = { privateReads += 1; return privateBoard }
        animated.captureHostingView.onPaste = { capturePastes += 1 }
        state.performSearchCommand(); animated.openDaily()
        try await wait("Animated Search opening completes") { animated.robotLifecycle.state == .fullScreen && !animated.appFrame.isTransitioning }
        try await requireSearchFocus(animated, "Animated Search opening")
        state.selectSearchProject("Northstar"); state.filter = .text
        let beforeAnimated = (state.query, state.searchProject, state.filter, state.searchScope)
        animated.dismiss()
        try await wait("Animated Search closing completes") { !animated.board.isVisible && animated.robotLifecycle.state == .hidden }
        animated.openDaily()
        try await wait("Animated retained Search reopens") { animated.robotLifecycle.state == .fullScreen && !animated.appFrame.isTransitioning }
        try await requireSearchFocus(animated, "Animated resume of retained Search")
        try expect(state.query == beforeAnimated.0 && state.searchProject == beforeAnimated.1 && state.filter == beforeAnimated.2 && state.searchScope == beforeAnimated.3,
                   "Animated hide/reopen retains the query and deliberate search refinements")
        try await clear(animated)
        await type("animated", in: animated)
        try expect(state.query == "animated", "Actual character events still type after the native transition stage is removed")
        try await clear(animated)
        privateBoard.clearContents(); _ = privateBoard.setString("animated private paste", forType: .string)
        try loseFocus(animated)
        await key(animated.board, text: "v", code: 9, modifiers: .command)
        try expect(state.query == "animated private paste", "Command V also routes to Search after animated reopen and focus loss")
        try expect(capturePastes == 0 && Set(store.captures.map(\.id)) == originalIDs,
                   "Every typing and paste scenario leaves the capture archive unchanged")
        print("PASS: \(checks) production Search typing, focus, clear, private direct/Cmd V paste, unrelated-editor and immediate/animated reopen checks")
    }
}
