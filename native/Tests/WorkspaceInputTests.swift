import AppKit
import Foundation

private final class WorkspaceTestEvent: NSEvent {
    let kind: NSEvent.EventType
    weak var target: NSWindow?
    let point: CGPoint
    let eventPhase: NSEvent.Phase
    let momentum: NSEvent.Phase
    let flags: NSEvent.ModifierFlags
    let dx: CGFloat
    let dy: CGFloat
    let magnificationValue: CGFloat
    let button: Int
    let precise: Bool
    let stamp: TimeInterval
    init(_ kind: NSEvent.EventType, window: NSWindow, point: CGPoint = CGPoint(x: 250, y: 150),
         phase: NSEvent.Phase = [], momentum: NSEvent.Phase = [], flags: NSEvent.ModifierFlags = [],
         x: CGFloat = 0, y: CGFloat = 0, magnification: CGFloat = 0, button: Int = 0, precise: Bool = true) {
        self.kind = kind; target = window; self.point = point; eventPhase = phase; self.momentum = momentum
        self.flags = flags; dx = x; dy = y; magnificationValue = magnification; self.button = button
        self.precise = precise; stamp = ProcessInfo.processInfo.systemUptime
        super.init()
    }
    required init?(coder: NSCoder) { fatalError("Unused fixture decoder") }
    override var type: NSEvent.EventType { kind }
    override var window: NSWindow? { target }
    override var windowNumber: Int { target?.windowNumber ?? 0 }
    override var locationInWindow: CGPoint { point }
    override var phase: NSEvent.Phase { eventPhase }
    override var momentumPhase: NSEvent.Phase { momentum }
    override var modifierFlags: NSEvent.ModifierFlags { flags }
    override var scrollingDeltaX: CGFloat { dx }
    override var scrollingDeltaY: CGFloat { dy }
    override var deltaX: CGFloat { dx }
    override var deltaY: CGFloat { dy }
    override var magnification: CGFloat { magnificationValue }
    override var buttonNumber: Int { button }
    override var hasPreciseScrollingDeltas: Bool { precise }
    override var timestamp: TimeInterval { stamp }
}

@MainActor private final class InputNotifications: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .allowed }
    func requestAuthorization() async throws -> Bool { fatalError("Input QA never requests permission") }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws {}
    func removePending(_ identifiers: [String]) {}
    func removeDelivered(_ identifiers: [String]) {}
}
@MainActor private final class InputHost: NSView { override var acceptsFirstResponder: Bool { true } }
@MainActor private final class InputDocument: NSView, DaBinDocumentGestureOwner {
    override var acceptsFirstResponder: Bool { true }
}
@MainActor private final class InputEditor: NSTextView {
    var claimsKey = true
    var hasComposition = false
    var equivalents = 0
    override func hasMarkedText() -> Bool { hasComposition }
    override func performKeyEquivalent(with event: NSEvent) -> Bool { equivalents += 1; return claimsKey }
}

/// Native windows and own-process synthetic events. No global event posting,
/// user archive, personal clipboard, hardware gesture simulation or permissions.
@main @MainActor private final class WorkspaceInputTests: NSObject, NSApplicationDelegate {
    private static var checks = 0
    private var result: Int32 = 0
    static func main() {
        let app = NSApplication.shared
        let delegate = WorkspaceInputTests()
        app.setActivationPolicy(.accessory); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        exit(delegate.result)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await Self.run() }
            catch { result = 1; fputs("Workspace input QA failed: \(error)\n", stderr) }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }
    private static func expect(_ pass: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard pass() else { throw NSError(domain: "WorkspaceInputTests", code: checks, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    private static func settle(_ milliseconds: Int = 50) async {
        await Task.yield(); try? await Task.sleep(for: .milliseconds(milliseconds))
    }
    private static func key(_ text: String, window: NSWindow, modifiers: NSEvent.ModifierFlags = .command,
                            repeatKey: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            characters: text, charactersIgnoringModifiers: text, isARepeat: repeatKey, keyCode: 42)!
    }

    private static func run() async throws {
        try expect(WorkspaceInputPolicy.command(characters: "[", modifiers: .command) == .back, "Command bracket goes Back")
        try expect(WorkspaceInputPolicy.command(characters: "]", modifiers: [.command, .capsLock]) == .forward, "Caps Lock does not remove Forward")
        try expect(WorkspaceInputPolicy.command(characters: "+", modifiers: [.command, .shift]) == .zoomIn, "Shifted plus supports layout-independent Zoom In")
        try expect(WorkspaceInputPolicy.command(characters: "=", modifiers: .command) == .zoomIn, "Equals supports Zoom In")
        try expect(WorkspaceInputPolicy.command(characters: "א", modifiers: .command) == nil, "Non-US characters are not mapped from a hard-coded keycode")
        try expect(WorkspaceInputPolicy.command(characters: "-", modifiers: [.command, .control]) == nil, "Control combinations remain system/editor input")
        for number in [0, 1, 2, 5, 8] { try expect(WorkspaceInputPolicy.auxiliaryButton(number) == nil, "Button \(number) retains native behavior") }
        try expect(WorkspaceInputPolicy.completedSwipe(amount: 1, cancelled: true) == nil, "Cancelled recognizer never commits")
        try expect(WorkspaceInputPolicy.completedSwipe(amount: 0.7, cancelled: false) == nil, "Incomplete recognizer never commits")
        try expect(WorkspaceInputPolicy.completedSwipe(amount: -.infinity, cancelled: false) == nil, "Nonfinite swipe is ignored")
        try expect(WorkspaceInputPolicy.completedSwipe(amount: -1, cancelled: false) == .forward, "Native semantic negative completion is Forward")
        try expect(!WorkspaceInputPolicy.qualifiesForWheelZoom(modifiers: [.command, .control], momentum: []), "Control-scroll cannot zoom workspace")
        try expect(!WorkspaceInputPolicy.qualifiesForWheelZoom(modifiers: .command, momentum: .changed), "Momentum cannot zoom workspace")

        let savedFocus = NativeNavigationFocus(identifier: "search", location: 2, length: 3)
        let decodedFocus = NativeNavigationFocus.decode(savedFocus.encoded!)
        try expect(decodedFocus.identifier == "search" && decodedFocus.selection(clampedTo: 10) == NSRange(location: 2, length: 3),
                   "Focus stores native insertion/selection offsets without text")
        try expect(decodedFocus.selection(clampedTo: 3) == NSRange(location: 2, length: 1), "Shorter current text clamps old selection")
        try expect(NativeNavigationFocus(identifier: "editor", location: -4, length: -2).selection(clampedTo: 8) == NSRange(location: 0, length: 0),
                   "Malformed negative offsets cannot select outside editor")
        try expect(NativeNavigationFocus.decode("legacy-control").identifier == "legacy-control", "Legacy focus identity remains readable")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinInputQA-\(UUID())")
        let defaultsName = "DaBinInputQA.\(UUID())"
        let defaults = UserDefaults(suiteName: defaultsName)!
        let pasteboard = NSPasteboard(name: .init(defaultsName))
        let store = try CaptureStore(root: root)
        let previews = PreviewService(store: store, defaults: defaults)
        let auto = AutoCaptureService(settings: AutoCaptureSettings(defaults: defaults), input: InputService(store: store),
            pasteboardProvider: { fatalError("Input QA never reads clipboard") }, sourceApplicationProvider: { nil })
        let state = AppState(store: store, previews: previews,
            reminders: ReminderService(store: store, client: InputNotifications()), autoCapture: auto,
            captureClipboard: CaptureClipboardService(pasteboard: pasteboard))
        let host = InputHost(frame: NSRect(x: 0, y: 0, width: 440, height: 360))
        let window = NSWindow(contentRect: NSRect(x: 180, y: 180, width: 440, height: 360),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.title = "DaBin isolated input QA"; window.contentView = host
        let region = WorkspaceInputRegionView(frame: host.bounds); host.addSubview(region)
        let input = WorkspaceInputController(state: state, host: host)
        input.attach(to: window); input.swipePreference = { true }
        defer {
            input.cancel(); input.attach(to: nil); window.orderOut(nil); window.contentView = nil; window.close()
            auto.shutdown(); state.focusSessions.shutdown(); state.shutdownNotificationPresentation(); previews.shutdown()
            pasteboard.releaseGlobally(); defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: root)
        }
        NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(host); await settle(100)
        try expect(window.isKeyWindow && window.isVisible, "Fixture obtains real own-process key window")
        state.openLibrary(); state.showReminders()
        let before = state.navigationHistory.index
        let back = key("[", window: window)
        try expect(input.key(back) && state.route == .library, "Native key dispatcher goes Back")
        try expect(input.key(back) && state.navigationHistory.index == before - 1, "Responder duplicate does not navigate twice")
        try expect(input.perform(.back, event: back) && state.navigationHistory.index == before - 1, "Menu duplicate shares suppression")
        try expect(input.key(key("]", window: window)) && state.route == .reminders, "Native Forward uses visited view")
        try expect(input.handle(WorkspaceTestEvent(.otherMouseUp, window: window, button: 3)) && state.route == .library, "Mouse Back uses same history")
        try expect(input.handle(WorkspaceTestEvent(.otherMouseUp, window: window, button: 4)) && state.route == .reminders, "Mouse Forward uses same history")
        try expect(!input.handle(WorkspaceTestEvent(.otherMouseUp, window: window, button: 2)), "Middle click is untouched")
        try expect(input.key(key("[", window: window, repeatKey: true)) && state.route == .reminders, "Held shortcut does not cascade")

        let editor = InputEditor(frame: NSRect(x: 20, y: 20, width: 100, height: 80)); host.addSubview(editor)
        window.makeFirstResponder(editor)
        let editorEvent = key("[", window: window)
        try expect(input.key(editorEvent) && editor.equivalents == 1 && state.route == .reminders, "Editor first refusal retains its command")
        try expect(input.key(editorEvent) && editor.equivalents == 1, "Claimed editor command is also deduplicated")
        editor.hasComposition = true
        try expect(!input.key(key("[", window: window)) && editor.equivalents == 1, "IME composition blocks navigation without invoking editor shortcut")
        editor.hasComposition = false; editor.claimsKey = false
        try expect(input.key(key("[", window: window)) && state.route == .library, "Unclaimed editor shortcut reaches shared history")
        window.makeFirstResponder(host); editor.removeFromSuperview()
        state.showReminders()
        let doc = InputDocument(frame: NSRect(x: 10, y: 10, width: 110, height: 90)); host.addSubview(doc)
        window.makeFirstResponder(doc)
        try expect(!input.key(key("+", window: window)), "Document owns generic zoom shortcuts")
        window.makeFirstResponder(host)
        try expect(!input.handle(WorkspaceTestEvent(.magnify, window: window, point: CGPoint(x: 50, y: 50), phase: .mayBegin)), "Document owns initial gesture surface")
        try expect(input.owner == .child, "Child owner latched at mayBegin")
        try expect(!input.handle(WorkspaceTestEvent(.magnify, window: window, phase: .began, magnification: 0.4))
                   && input.owner == .child && state.workspaceZoom.factor == 1, "Moved pointer on began cannot steal document gesture")
        _ = input.handle(WorkspaceTestEvent(.magnify, window: window, phase: .ended))
        try expect(input.owner == nil, "Child gesture clears when ended")
        doc.removeFromSuperview()

        let scroll = NSScrollView(frame: NSRect(x: 10, y: 10, width: 110, height: 90))
        scroll.hasHorizontalScroller = true; scroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 70))
        host.addSubview(scroll)
        try expect(!input.handle(WorkspaceTestEvent(.scrollWheel, window: window, point: CGPoint(x: 50, y: 50), phase: .began, x: 12))
                   && input.owner == .child, "Horizontal scroller retains swipe even at its edge")
        _ = input.handle(WorkspaceTestEvent(.scrollWheel, window: window, phase: .ended))
        _ = input.handle(WorkspaceTestEvent(.scrollWheel, window: window, point: CGPoint(x: 50, y: 50), phase: .mayBegin))
        try expect(input.handle(WorkspaceTestEvent(.magnify, window: window, phase: .began, magnification: 0.1)),
                   "A zero scroll preface over week columns does not reserve a later pinch")
        input.flush(); input.finish()
        try expect(abs(state.workspaceZoom.factor - 1.1) < 0.001, "Pinch over a horizontal scroller changes workspace content")
        _ = input.perform(.resetZoom)
        try expect(input.handle(WorkspaceTestEvent(.scrollWheel, window: window, point: CGPoint(x: 50, y: 50), flags: .command, y: 10)),
                   "Command wheel over a horizontal scroller belongs to workspace zoom")
        input.flush(); input.finish(); _ = input.perform(.resetZoom)
        scroll.removeFromSuperview()
        try expect(!input.handle(WorkspaceTestEvent(.scrollWheel, window: window, y: 12, precise: false)), "Ordinary wheel is never page navigation")
        try expect(!input.handle(WorkspaceTestEvent(.scrollWheel, window: window, phase: .began, y: 12))
                   && input.owner == .scrolling, "Vertical intent keeps scrolling ownership")
        try expect(!input.handle(WorkspaceTestEvent(.scrollWheel, window: window, phase: .changed, x: 50)), "Horizontal drift cannot reclassify existing vertical scroll")
        _ = input.handle(WorkspaceTestEvent(.scrollWheel, window: window, phase: .ended))
        input.cancel()

        try expect(input.handle(WorkspaceTestEvent(.magnify, window: window, phase: .began, magnification: 0.2)), "Workspace begins pinch")
        input.flush()
        try expect(abs(state.workspaceZoom.factor - 1.2) < 0.001 && state.workspaceZoom.isInteracting, "Pinch scales once after coalescing")
        let zoomIndex = state.navigationHistory.index
        try expect(input.handle(WorkspaceTestEvent(.swipe, window: window, x: 1)) && input.owner == .zoom
            && state.workspaceZoom.isInteracting, "Secondary swipe cannot clear the active pinch owner or leave zoom stuck")
        try expect(!input.perform(.back), "Navigation is rejected during zoom")
        state.openLibrary()
        try expect(state.navigationHistory.index == zoomIndex && state.route == .reminders, "Mouse navigation uses same zoom blocker")
        _ = input.handle(WorkspaceTestEvent(.magnify, window: window, phase: .cancelled, magnification: -0.8))
        try expect(abs(state.workspaceZoom.factor - 1.2) < 0.001 && !state.workspaceZoom.isInteracting && input.owner == nil,
                   "Cancelled pinch retains last visible factor, ends flags, ignores terminal delta")
        let writes = state.workspaceZoom.persistenceCount
        try expect(!input.handle(WorkspaceTestEvent(.magnify, window: window, phase: .ended)), "Stray terminal event does not begin gesture")
        try expect(state.workspaceZoom.persistenceCount == writes, "Empty end writes no preference")
        try expect(!input.handle(WorkspaceTestEvent(.scrollWheel, window: window, flags: [.control, .command], y: 20)), "Control-scroll stays system input")
        try expect(input.handle(WorkspaceTestEvent(.scrollWheel, window: window, flags: .command, y: 20)), "Command wheel starts workspace zoom")
        input.flush(); let wheelFactor = state.workspaceZoom.factor
        await settle(260)
        try expect(!state.workspaceZoom.isInteracting && input.owner == nil && wheelFactor > 1.2, "Wheel finishes after 200 ms inactivity")
        try expect(input.handle(WorkspaceTestEvent(.scrollWheel, window: window, momentum: .changed, flags: .command, y: 50))
                   && state.workspaceZoom.factor == wheelFactor, "Zoom momentum is consumed without zooming or falling through into panning")
        _ = input.handle(WorkspaceTestEvent(.scrollWheel, window: window, momentum: .ended))
        try expect(!input.handle(WorkspaceTestEvent(.scrollWheel, window: window, y: 5, precise: false)),
                   "A later independent plain wheel returns to native scrolling")
        try expect(input.perform(.resetZoom) && state.workspaceZoom.factor == 1, "Explicit workspace reset uses same controller")

        try expect(input.handle(WorkspaceTestEvent(.swipe, window: window, phase: .ended, x: 1)) && state.route == .library,
                   "Completed native swipe with terminal phase still navigates once")
        _ = input.handle(WorkspaceTestEvent(.otherMouseUp, window: window, button: 4))

        typealias Callback = (CGFloat, NSEvent.Phase, Bool, UnsafeMutablePointer<ObjCBool>) -> Void
        var tracked: Callback?
        var calls = 0
        input.trackSwipe = { _, _, _, callback in calls += 1; tracked = callback }
        state.workspaceZoom.trackpadNavigationEnabled = false
        try expect(!input.handle(WorkspaceTestEvent(.scrollWheel, window: window, phase: .began, x: 15)) && calls == 0,
                   "App preference disables native swipe tracking")
        input.cancel(); state.workspaceZoom.trackpadNavigationEnabled = true; input.swipePreference = { false }
        try expect(!input.handle(WorkspaceTestEvent(.scrollWheel, window: window, phase: .began, x: 15)) && calls == 0,
                   "User macOS preference remains authoritative")
        input.cancel(); input.swipePreference = { true }
        try expect(!input.handle(WorkspaceTestEvent(.scrollWheel, window: window, phase: .mayBegin, x: 15)) && calls == 0,
                   "mayBegin is not passed to recognizer requiring began/changed")
        try expect(input.handle(WorkspaceTestEvent(.scrollWheel, window: window, phase: .began, x: 15)) && calls == 1,
                   "Dominant horizontal began starts native recognizer")
        var stop = ObjCBool(false)
        tracked?(1, .cancelled, true, &stop)
        try expect(state.route == .reminders && input.owner == nil, "Cancelled native recognizer leaves route unchanged")
        try expect(input.handle(WorkspaceTestEvent(.scrollWheel, window: window, phase: .began, x: 15)), "Next gesture can start after cancellation")
        tracked?(1, .ended, true, &stop)
        let committed = state.navigationHistory.index
        try expect(state.route == .library, "Completed native recognizer commits Back")
        tracked?(1, .ended, true, &stop)
        try expect(state.navigationHistory.index == committed, "Repeated completion callback cannot commit twice")
        _ = input.handle(WorkspaceTestEvent(.scrollWheel, window: window, phase: .began, x: -15))
        let stale = tracked
        input.cancel(); stale?(-1, .ended, true, &stop)
        try expect(state.navigationHistory.index == committed, "Cancelled gesture generation rejects delayed callback")
        state.forward()
        state.showSettings()
        try expect(!input.handle(WorkspaceTestEvent(.magnify, window: window, phase: .began, magnification: 0.5)), "Settings does not inherit workspace zoom")
        try expect(input.handle(WorkspaceTestEvent(.scrollWheel, window: window, phase: .began, x: 15)), "Settings still allows native Back gesture")
        tracked?(1, .ended, true, &stop)
        try expect(state.route == .reminders, "Settings swipe restores previous route")
        _ = input.handle(WorkspaceTestEvent(.scrollWheel, window: window, phase: .began, x: 15))
        let interrupted = tracked
        let interruptionIndex = state.navigationHistory.index
        state.navigationValidationBlocked = true
        stop = false
        interrupted?(0.5, .changed, false, &stop)
        try expect(stop.boolValue && input.owner == nil && state.navigationHistory.index == interruptionIndex,
                   "A newly blocked swipe releases its owner when AppKit tracking is stopped")
        try expect(!input.key(key("[", window: window)), "Editor validation gate blocks commands")
        state.navigationValidationBlocked = false
        try expect(!input.handle(WorkspaceTestEvent(.scrollWheel, window: window, y: 5, precise: false)),
                   "Plain wheel works after an aborted swipe instead of remaining swallowed")
        _ = input.handle(WorkspaceTestEvent(.magnify, window: window, phase: .began, magnification: 0.05))
        interrupted?(1, .ended, true, &stop)
        try expect(input.owner == .zoom && state.workspaceZoom.isInteracting && state.navigationHistory.index == interruptionIndex,
                   "A stale aborted callback cannot clear a newer pinch or navigate")
        input.cancel()
        state.isDailyDropTargeted = true
        try expect(!input.perform(.back), "Active drop blocks navigation")
        state.isDailyDropTargeted = false
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 150, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        sheet.isReleasedWhenClosed = false
        window.beginSheet(sheet, completionHandler: { _ in })
        await settle()
        try expect(input.blocked && !input.perform(.back), "Attached sheet blocks window commands")
        window.endSheet(sheet); sheet.orderOut(nil); sheet.close(); window.makeKeyAndOrderFront(nil)
        await settle()
        _ = input.handle(WorkspaceTestEvent(.magnify, window: window, phase: .began, magnification: 0.1))
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        try expect(!state.workspaceZoom.isInteracting && input.owner == nil, "Focus loss resolves active interaction")
        input.cancel()
        print("PASS: \(checks) native workspace command, owner, cancellation, child precedence, IME, modal and dedup checks; synthetic device coverage only")
    }
}
