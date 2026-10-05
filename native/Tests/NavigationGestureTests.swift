import AppKit
import Foundation

/// Events go only to the fixture's own panel; no monitor or global posting.
private final class NavigationGestureEvent: NSEvent {
    let kind: NSEvent.EventType
    weak var target: NSWindow?
    let point: NSPoint
    let eventPhase: NSEvent.Phase
    let dx: CGFloat
    let button: Int
    let stamp = ProcessInfo.processInfo.systemUptime
    init(_ kind: NSEvent.EventType, window: NSWindow, point: NSPoint,
         phase: NSEvent.Phase = [], x: CGFloat = 0, button: Int = 0) {
        self.kind = kind; target = window; self.point = point
        eventPhase = phase; dx = x; self.button = button
        super.init()
    }
    required init?(coder: NSCoder) { fatalError("Unused fixture decoder") }
    override var type: NSEvent.EventType { kind }
    override var window: NSWindow? { target }
    override var windowNumber: Int { target?.windowNumber ?? 0 }
    override var locationInWindow: NSPoint { point }
    override var phase: NSEvent.Phase { eventPhase }
    override var momentumPhase: NSEvent.Phase { [] }
    override var modifierFlags: NSEvent.ModifierFlags { [] }
    override var deltaX: CGFloat { dx }
    override var deltaY: CGFloat { 0 }
    override var scrollingDeltaX: CGFloat { dx }
    override var scrollingDeltaY: CGFloat { 0 }
    override var hasPreciseScrollingDeltas: Bool { true }
    override var buttonNumber: Int { button }
    override var timestamp: TimeInterval { stamp }
}

@MainActor private final class GestureNotifications: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .allowed }
    func requestAuthorization() async throws -> Bool { fatalError("Gesture QA never requests permission") }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { fatalError("Gesture QA never schedules notifications") }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}

/// Exercises the real BoardView region, hosting responder chain and panel
/// dispatcher with fictional captures and an isolated archive/preferences.
@main @MainActor private final class NavigationGestureTests: NSObject, NSApplicationDelegate {
    private static var checks = 0
    private var result: Int32 = 0
    static func main() {
        let app = NSApplication.shared
        let delegate = NavigationGestureTests()
        app.setActivationPolicy(.accessory); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        exit(delegate.result)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await Self.run() }
            catch { result = 1; fputs("Navigation gesture QA failed: \(error)\n", stderr) }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }
    private static func expect(_ pass: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard pass() else { throw NSError(domain: "NavigationGestureTests", code: checks,
            userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    private static func settle(_ host: NSView) async {
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded(); await Task.yield()
            try? await Task.sleep(for: .milliseconds(25))
        }
    }
    private enum Surface: String { case header, body, footer }
    private static func point(_ surface: Surface, host: NSView) -> NSPoint {
        let rect = host.bounds
        let y: CGFloat
        switch surface {
        case .header: y = host.isFlipped ? rect.minY + 16 : rect.maxY - 16
        case .body: y = rect.midY
        case .footer: y = host.isFlipped ? rect.maxY - 8 : rect.minY + 8
        }
        return host.convert(NSPoint(x: rect.midX, y: y), to: nil)
    }
    private static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinGestureQA-\(UUID())")
        let defaultsName = "DaBinGestureQA.\(UUID())"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defaults.set(false, forKey: PreviewService.linkPreviewPreference)
        let store = try CaptureStore(root: root, repairArchiveOnOpen: false)
        let previews = PreviewService(store: store, defaults: defaults)
        let auto = AutoCaptureService(settings: AutoCaptureSettings(defaults: defaults), input: InputService(store: store),
            pasteboardProvider: { fatalError("Gesture QA never reads clipboard") }, sourceApplicationProvider: { nil })
        let state = AppState(store: store, previews: previews,
            reminders: ReminderService(store: store, client: GestureNotifications()), autoCapture: auto,
            captureClipboard: CaptureClipboardService(writer: { _ in fatalError("Gesture QA never copies content") }),
            workspaceZoom: WorkspaceZoomSettings(defaults: defaults),
            folderOpener: { _ in fatalError("Gesture QA never opens another application") })
        let theme = ThemeSettings(defaults: defaults)
        theme.setShowTooltips(false); theme.setDarkMode(false)
        let task = try store.createTask(text: "Fictional gesture task")
        let note = try store.capture(text: "Fictional gesture source note")[0]
        try state.workspace.createProject(name: "Gesture Example", colorHex: "7568D8")
        try state.workspace.setScratchpad(text: "Fictional gesture project note", project: "Gesture Example")
        let scratchpad = state.workspace.snapshot.scratchpads[WorkspaceSnapshot.projectKey("Gesture Example")]!
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let savedCaptures = try encoder.encode([CaptureSnapshot(task), CaptureSnapshot(note)])
        let host = DailyCaptureHostingView(state: state, theme: theme)
        host.frame = NSRect(x: 0, y: 0, width: 760, height: 760)
        host.searchPasteboardProvider = { fatalError("Gesture QA never reads search clipboard") }
        let panel = DailyCapturePanel(contentRect: NSRect(x: -10_000, y: -10_000, width: 760, height: 760),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.cameraStageDisplayFrame = NSRect(x: -12_000, y: -12_000, width: 4_000, height: 4_000)
        panel.isReleasedWhenClosed = false; panel.contentView = host; panel.captureHostingView = host
        panel.title = "DaBin isolated navigation gesture QA"
        state.isBoardVisible = true
        defer {
            host.workspaceInput.cancel(); host.workspaceInput.attach(to: nil)
            panel.orderOut(nil); panel.contentView = nil; panel.close()
            auto.shutdown(); state.focusSessions.shutdown(); state.shutdownNotificationPresentation()
            previews.shutdown(); store.cancelArchiveRepair()
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: root)
        }
        NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(host); await settle(host)
        try expect(panel.isKeyWindow && panel.isVisible && panel.contentView === host
            && panel.captureHostingView === host, "Actual native panel and Board hosting view own the test window")
        let input = host.workspaceInput!
        input.swipePreference = { false }
        state.workspaceZoom.trackpadNavigationEnabled = true
        func swipe(_ x: CGFloat, _ surface: Surface, phase: NSEvent.Phase = []) -> NavigationGestureEvent {
            NavigationGestureEvent(.swipe, window: panel, point: point(surface, host: host), phase: phase, x: x)
        }
        func mouse(_ kind: NSEvent.EventType, _ button: Int, _ surface: Surface) -> NavigationGestureEvent {
            NavigationGestureEvent(kind, window: panel, point: point(surface, host: host), button: button)
        }
        func roundTrip(_ surface: Surface) async throws {
            let route = state.route; let index = state.navigationHistory.index
            let previous = state.navigationHistory.entries[index - 1].route
            let back = swipe(-1, surface)
            panel.sendEvent(back); await settle(host)
            try expect(state.route == previous && state.navigationHistory.index == index - 1,
                "Recognized negative swipe goes Back from actual \(surface.rawValue)")
            panel.sendEvent(back)
            try expect(state.navigationHistory.index == index - 1, "Duplicate \(surface.rawValue) swipe commits once")
            let forward = swipe(1, surface)
            panel.sendEvent(forward); await settle(host)
            try expect(state.route == route && state.navigationHistory.index == index,
                "Recognized positive swipe goes Forward from actual \(surface.rawValue)")
            panel.sendEvent(forward)
            try expect(state.navigationHistory.index == index, "Duplicate Forward swipe commits once")
        }
        state.openLibrary(); state.openInbox(); state.showReminders(); await settle(host)
        for surface in [Surface.header, .body, .footer] { try await roundTrip(surface) }
        let disabledIndex = state.navigationHistory.index
        state.workspaceZoom.trackpadNavigationEnabled = false
        try expect(!input.handle(swipe(-1, .header)) && input.owner == nil
            && state.navigationHistory.index == disabledIndex, "App navigation preference still disables recognized swipes")
        state.workspaceZoom.trackpadNavigationEnabled = true
        var trackingCalls = 0
        var completion: ((CGFloat, NSEvent.Phase, Bool, UnsafeMutablePointer<ObjCBool>) -> Void)?
        input.trackSwipe = { _, _, _, callback in trackingCalls += 1; completion = callback }
        let raw = NavigationGestureEvent(.scrollWheel, window: panel, point: point(.header, host: host), phase: .began, x: 25)
        try expect(!input.handle(raw) && trackingCalls == 0 && state.navigationHistory.index == disabledIndex,
            "System fluid-tracking preference false prevents raw scroll navigation")
        input.cancel(); input.swipePreference = { true }
        try expect(input.handle(NavigationGestureEvent(.scrollWheel, window: panel,
            point: point(.header, host: host), phase: .began, x: 25)) && input.owner == .swipe && trackingCalls == 1,
            "Opted-in raw gesture obtains one actual fluid recognizer")
        panel.sendEvent(swipe(-1, .header, phase: .began))
        try expect(input.owner == .swipe && trackingCalls == 1 && state.navigationHistory.index == disabledIndex,
            "Recognized began duplicate cannot reset a fluid owner or commit early")
        var stop = ObjCBool(false)
        completion?(1, .ended, true, &stop)
        try expect(state.navigationHistory.index == disabledIndex - 1, "Fluid completion shares the same Back history")
        completion?(1, .ended, true, &stop)
        try expect(state.navigationHistory.index == disabledIndex - 1, "Repeated fluid completion commits once")
        panel.sendEvent(swipe(1, .header)); await settle(host)
        input.swipePreference = { false }

        let mouseIndex = state.navigationHistory.index
        let down = mouse(.otherMouseDown, 3, .header)
        panel.sendEvent(down); panel.sendEvent(down); panel.sendEvent(mouse(.otherMouseDown, 3, .header))
        try expect(state.navigationHistory.index == mouseIndex - 1, "Native panel Back Down and held duplicates commit once")
        let up = mouse(.otherMouseUp, 3, .header)
        state.navigationValidationBlocked = true
        panel.sendEvent(up); panel.sendEvent(up)
        try expect(state.navigationHistory.index == mouseIndex - 1, "Panel consumes paired Up during a new validation blocker")
        state.navigationValidationBlocked = false
        let forwardDown = mouse(.otherMouseDown, 4, .footer)
        panel.sendEvent(forwardDown); panel.sendEvent(forwardDown)
        let forwardUp = mouse(.otherMouseUp, 4, .footer)
        panel.sendEvent(forwardUp); panel.sendEvent(forwardUp)
        try expect(state.navigationHistory.index == mouseIndex, "Native panel Forward Down and release commit once")
        let upOnlyBack = mouse(.otherMouseUp, 3, .body)
        panel.sendEvent(upOnlyBack); panel.sendEvent(upOnlyBack)
        try expect(state.navigationHistory.index == mouseIndex - 1, "Up-only Back driver works through native panel")
        let upOnlyForward = mouse(.otherMouseUp, 4, .body)
        panel.sendEvent(upOnlyForward); panel.sendEvent(upOnlyForward)
        try expect(state.navigationHistory.index == mouseIndex, "Up-only Forward driver works through native panel")
        // Rejected synthetic events stay at the controller boundary. AppKit's
        // mouseEvent factory does not provide an auxiliary button argument.
        for kind in [NSEvent.EventType.otherMouseDown, .otherMouseUp] {
            let middle = mouse(kind, 2, .body)
            try expect(!input.handle(middle), "Middle button is left to native AppKit dispatch")
            try expect(state.navigationHistory.index == mouseIndex, "Middle button retains native behavior without navigation")
        }

        let routes: [BoardRoute] = [.inbox, .daily, .weekly, .library, .search, .searchNote, .detail,
            .reminders, .settings, .newTask, .newNote, .trash]
        for route in routes {
            state.openLibrary(); await settle(host)
            switch route {
            case .inbox: state.openInbox()
            case .daily: state.openDaily()
            case .weekly: state.openWeekly()
            case .library: state.openInbox(); state.openLibrary()
            case .search: state.performSearchCommand()
            case .searchNote: state.performSearchCommand(); state.openSearchNote(scratchpad)
            case .detail: state.openCapture(task.id, focus: "title")
            case .reminders: state.showReminders()
            case .settings: state.showSettings()
            case .newTask: state.openNewTask()
            case .newNote: state.openNewNote()
            case .trash: state.showTrash()
            }
            await settle(host)
            try expect(state.route == route && state.canGoBack, "Production \(route) is reachable with recorded history")
            let index = state.navigationHistory.index
            let count = state.navigationHistory.entries.count
            let previous = state.navigationHistory.entries[index - 1].route
            panel.sendEvent(swipe(-1, .header)); await settle(host)
            try expect(state.route == previous && state.navigationHistory.index == index - 1,
                "Actual \(route) header participates in Back")
            panel.sendEvent(swipe(1, .footer)); await settle(host)
            try expect(state.route == route && state.navigationHistory.index == index
                && state.navigationHistory.entries.count == count, "Actual \(route) footer restores visited route without a new entry")
            if route == .detail { try expect(state.selectedCapture?.id == task.id, "Detail Forward restores capture identity") }
            if route == .searchNote { try expect(state.selectedSearchNote?.projectName == scratchpad.projectName, "Search-note Forward restores project identity") }
        }

        state.openLibrary(); state.openCapture(task.id, focus: "title"); await settle(host)
        let draft = state.selectedDraft!
        draft.title = "Unsaved fictional task title"
        draft.commentComposer = "Unsaved fictional comment"
        draft.planning.priority = .high
        draft.planning.checklist = [TaskChecklistItem(text: "Fictional unsaved checklist row")]
        await settle(host)
        guard let region = NavigationEditorRegionView.regions(in: host).first(where: { $0.target == .detailTitle }),
              let editor = region.editor(in: host) else {
            throw NSError(domain: "NavigationGestureTests", code: checks, userInfo: [NSLocalizedDescriptionKey: "Actual task title editor missing"])
        }
        if let field = editor as? NSTextField { panel.makeFirstResponder(field); field.selectText(nil) }
        else { panel.makeFirstResponder(editor) }
        guard let text = panel.firstResponder as? NSTextView else {
            throw NSError(domain: "NavigationGestureTests", code: checks, userInfo: [NSLocalizedDescriptionKey: "Title field has no native selected-text responder"])
        }
        let selection = NSRange(location: 2, length: 5)
        text.setSelectedRange(selection)
        state.showSettings(); await settle(host)
        let taskBack = mouse(.otherMouseDown, 3, .header)
        panel.sendEvent(taskBack); panel.sendEvent(mouse(.otherMouseUp, 3, .header)); await settle(host)
        try expect(state.route == .detail && state.selectedCapture?.id == task.id && state.selectedDraft === draft,
            "Mouse Back restores the original live task draft owner")
        try expect(draft.title == "Unsaved fictional task title" && draft.commentComposer == "Unsaved fictional comment"
            && draft.planning.priority == .high && draft.planning.checklist.first?.text == "Fictional unsaved checklist row",
            "Gesture history preserves pending task title, comments, priority and checklist")
        try expect((panel.firstResponder as? NSTextView)?.selectedRange() == selection,
            "Shared native history restores actual title editor selection after mouse Back")
        panel.sendEvent(swipe(1, .header)); await settle(host)
        try expect(state.route == .settings, "Recognized Forward after mouse Back uses the same history")
        panel.sendEvent(swipe(-1, .footer)); await settle(host)
        try expect(state.selectedDraft === draft && draft.title == "Unsaved fictional task title",
            "Recognized Back retains the same unsaved task owner across input methods")
        let afterCaptures = try encoder.encode([CaptureSnapshot(task), CaptureSnapshot(note)])
        try expect(afterCaptures == savedCaptures,
            "Navigation never commits or mutates the isolated captures")
        print("PASS NavigationGestureTests \(checks) checks; real panel dispatch, 12 routes, header/body/footer, both swipe directions, mouse pairing and task draft/focus restoration")
    }
}
