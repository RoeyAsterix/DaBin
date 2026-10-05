import AppKit
import ApplicationServices
import SwiftUI
import Darwin

@MainActor private final class TaskPlanReminderClient: ReminderNotificationClient {
    private(set) var requests = 0
    private(set) var additions = 0
    func authorization() async -> ReminderAuthorization { .denied }
    func requestAuthorization() async throws -> Bool { requests += 1; return false }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { additions += 1 }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}

@MainActor private final class TaskPlanBindingFixture: ObservableObject {
    @Published var planning: TaskPlanning
    @Published var enabled = false
    @Published var mode: ReminderScheduleMode = .date
    @Published var date = Date().addingTimeInterval(3_600)
    @Published var hours = 0
    @Published var minutes = 30
    init(planning: TaskPlanning = TaskPlanning()) { self.planning = planning }
}

@MainActor private struct TaskPlanBoundEditor: View {
    @ObservedObject var fixture: TaskPlanBindingFixture
    var reminderOnly = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if reminderOnly {
                    ReminderClockEditor(enabled: $fixture.enabled, mode: $fixture.mode,
                        date: $fixture.date, hours: $fixture.hours, minutes: $fixture.minutes)
                } else {
                    TaskPlanningEditor(planning: $fixture.planning)
                }
            }.padding(12).frame(maxWidth: .infinity, alignment: .topLeading)
        }.background(Palette.background)
    }
}

@MainActor private struct TaskPlanAXNode {
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
    var rawAccessibilityLabel: String? { value("accessibilityLabel") as? String }
    var supportsAccessibilityLabel: Bool { object.responds(to: NSSelectorFromString("accessibilityLabel")) }
    var label: String {
        [value("accessibilityLabel"), value("accessibilityTitle"), attribute("AXTitle"), attribute("AXDescription"),
         value("accessibilityValue"), attribute("AXValue")]
            .compactMap { ($0 as? String) ?? ($0 as? NSAttributedString)?.string }.first { !$0.isEmpty } ?? ""
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
    func showMenu() -> Bool {
        let selector = NSSelectorFromString("accessibilityPerformShowMenu")
        guard object.responds(to: selector) else { return false }
        typealias Action = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(object.method(for: selector), to: Action.self)(object, selector)
    }
    var actions: [String] { (value("accessibilityActionNames") as? [String]) ?? [] }
    var children: [Any] {
        var result: [Any] = []
        for name in ["accessibilityChildren", "accessibilityChildrenInNavigationOrder", "accessibilityContents"] {
            if let values = value(name) as? [Any] { result += values }
        }
        if let values = attribute("AXChildren") as? [Any] { result += values }
        return result
    }
}

@MainActor private final class TaskPlanMenuTracking {
    let deadline = ProcessInfo.processInfo.systemUptime + 2
    weak var window: NSWindow?
    private(set) var menus: [NSMenu] = []
    private(set) var ended = Set<ObjectIdentifier>()
    private(set) var timedOut = false
    init(window: NSWindow?) { self.window = window }
    func began(_ menu: NSMenu) {
        if !menus.contains(where: { $0 === menu }) { menus.append(menu) }
        fputs("MENU tracking began: \(menu.items.map(\.title))\n", stderr)
    }
    func didEnd(_ menu: NSMenu) {
        ended.insert(ObjectIdentifier(menu)); fputs("MENU tracking ended\n", stderr)
    }
    func cancel() {
        menus.forEach { $0.cancelTrackingWithoutAnimation() }
        guard ProcessInfo.processInfo.systemUptime >= deadline else { return }
        timedOut = true
        // A bounded fallback for a menu implementation that hasn't delivered
        // its notification yet. This event is queued only in the test process
        // and carries the fixture's own window number; no global input is sent.
        guard let window, let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53) else { return }
        NSApp.postEvent(escape, atStart: true)
    }
}

/// Runs only disposable native fixtures. Input goes through controls belonging
/// to this process; the production AppState is observed rather than substituted
/// for UI actions. A watchdog bounds even a stuck native menu tracking loop.
@main @MainActor private final class TaskPlanInteractionTests: NSObject, NSApplicationDelegate {
    private static var checks = 0
    private static var evidence: [[String: Any]] = []
    private var result = 0

    @MainActor private final class Services {
        let root: URL
        let preferencesName = "DaBinTaskPlanInteractionQA.\(UUID().uuidString)"
        let defaults: UserDefaults
        let store: CaptureStore
        let previews: PreviewService
        let auto: AutoCaptureService
        let notifications = TaskPlanReminderClient()
        let state: AppState
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinTaskPlanInteractionQA-\(UUID().uuidString)")
            defaults = UserDefaults(suiteName: preferencesName)!
            defaults.set(false, forKey: PreviewService.linkPreviewPreference)
            store = try CaptureStore(root: root, repairArchiveOnOpen: false)
            previews = PreviewService(store: store, defaults: defaults)
            auto = AutoCaptureService(settings: AutoCaptureSettings(defaults: defaults), input: InputService(store: store),
                pasteboardProvider: { fatalError("Task plan QA must not read the clipboard") },
                sourceApplicationProvider: { nil })
            state = AppState(store: store, previews: previews,
                reminders: ReminderService(store: store, client: notifications), autoCapture: auto,
                captureClipboard: CaptureClipboardService(writer: { _ in fatalError("Task plan QA must not write the clipboard") }),
                folderOpener: { _ in fatalError("Task plan QA must not open Finder") })
        }
        func close() {
            previews.shutdown(); auto.shutdown(); state.focusSessions.shutdown()
            state.shutdownNotificationPresentation(); store.cancelArchiveRepair()
            defaults.removePersistentDomain(forName: preferencesName)
            try? FileManager.default.removeItem(at: root)
        }
    }

    static func main() {
        let watchdog = DispatchSource.makeTimerSource(queue: .global())
        watchdog.schedule(deadline: .now() + 150)
        watchdog.setEventHandler {
            fputs("Task plan interaction QA exceeded its own 150-second bound\n", stderr)
            Darwin._exit(2)
        }
        watchdog.resume()
        let application = NSApplication.shared, delegate = TaskPlanInteractionTests()
        application.setActivationPolicy(.accessory); application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
        watchdog.cancel()
        exit(Int32(delegate.result))
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await Self.run() }
            catch { result = 1; fputs("Task plan interaction QA failed: \(error)\n", stderr) }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }
    private static func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard value() else { throw NSError(domain: "TaskPlanInteractionTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    private static func nodes(_ view: NSView, native: Bool = false) -> [TaskPlanAXNode] {
        view.layoutSubtreeIfNeeded()
        var seen = Set<ObjectIdentifier>(), result: [TaskPlanAXNode] = []
        func visit(_ value: Any, depth: Int) {
            guard depth < 60, let object = value as? NSObject,
                  seen.insert(ObjectIdentifier(object)).inserted else { return }
            let node = TaskPlanAXNode(object: object); result.append(node)
            node.children.forEach { visit($0, depth: depth + 1) }
            if native, let nativeView = object as? NSView {
                nativeView.subviews.forEach { visit($0, depth: depth + 1) }
            }
        }
        visit(view, depth: 0)
        NSAccessibility.unignoredChildren(from: [view]).forEach { visit($0, depth: 0) }
        return result
    }
    private static func settle(_ view: NSView) async {
        for _ in 0..<3 { view.layoutSubtreeIfNeeded(); try? await Task.sleep(for: .milliseconds(35)) }
    }
    private static func find(_ view: NSView, id: String) async throws -> TaskPlanAXNode {
        for _ in 0..<8 {
            if let result = nodes(view).first(where: { $0.identifier == id }) { return result }
            await settle(view)
        }
        throw NSError(domain: "TaskPlanInteractionTests", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Missing accessible control \(id): \(nodes(view).map { $0.identifier ?? $0.label }.joined(separator: "; "))"])
    }
    private static func findLabel(_ view: NSView, label: String) async throws -> TaskPlanAXNode {
        for _ in 0..<8 {
            if let result = nodes(view).first(where: { $0.label == label && $0.object.responds(to: NSSelectorFromString("accessibilityPerformPress")) }) { return result }
            await settle(view)
        }
        throw NSError(domain: "TaskPlanInteractionTests", code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Missing accessible action \(label)"])
    }
    private static func enabled(_ node: TaskPlanAXNode) -> Bool {
        if let control = node.object as? NSControl { return control.isEnabled }
        for name in ["isAccessibilityEnabled", "accessibilityEnabled"] {
            let selector = NSSelectorFromString(name)
            guard node.object.responds(to: selector) else { continue }
            typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
            return unsafeBitCast(node.object.method(for: selector), to: Getter.self)(node.object, selector)
        }
        return false
    }
    private static func press(_ view: NSView, id: String) async throws {
        let node = try await find(view, id: id)
        try expect(enabled(node) && node.press(), "\(id) accepts an enabled native accessibility activation")
        await settle(view)
    }
    private static func pressLabel(_ view: NSView, label: String) async throws {
        let node = try await findLabel(view, label: label)
        try expect(enabled(node) && node.press(), "\(label) accepts an enabled native accessibility activation")
        await settle(view)
    }
    private static func screenFrame(_ view: NSView) -> NSRect {
        guard let window = view.window else { return .zero }
        return window.convertToScreen(view.convert(view.bounds, to: nil))
    }
    private static func nativeControl<T: NSView>(_ node: TaskPlanAXNode, in host: NSView, type: T.Type) throws -> T {
        if let direct = node.object as? T { return direct }
        let candidates = nodes(host, native: true).compactMap { $0.object as? T }.filter { control in
            if control.isHiddenOrHasHiddenAncestor { return false }
            if let field = control as? NSTextField { return field.isEditable && field.isEnabled }
            if let text = control as? NSTextView { return text.isEditable && !text.isFieldEditor }
            return true
        }.compactMap { control -> (T, CGFloat)? in
            let frame = screenFrame(control), intersection = frame.intersection(node.frame)
            let area = min(frame.width * frame.height, node.frame.width * node.frame.height)
            guard area > 0, !intersection.isNull, intersection.width * intersection.height / area > 0.5 else { return nil }
            return (control, abs(frame.midX - node.frame.midX) + abs(frame.midY - node.frame.midY))
        }
        guard let result = candidates.min(by: { $0.1 < $1.1 })?.0 else {
            throw NSError(domain: "TaskPlanInteractionTests", code: 4,
                userInfo: [NSLocalizedDescriptionKey: "\(node.identifier ?? node.label) must map to its mounted native \(type)"])
        }
        return result
    }
    /// Replace text through the real editor and let SwiftUI's binding/delegate
    /// consume it. Neither draft properties nor app-state commands implement an
    /// asserted UI action here.
    private static func enter(_ text: String, id: String, in host: NSView, submit: Bool = false) async throws {
        let node = try await find(host, id: id)
        try await edit(text, node: node, in: host, submit: submit)
    }
    private static func enterLabel(_ text: String, label: String, in host: NSView) async throws {
        guard let node = nodes(host).first(where: { $0.label == label }) else {
            throw NSError(domain: "TaskPlanInteractionTests", code: 14,
                userInfo: [NSLocalizedDescriptionKey: "Missing native editable field \(label)"])
        }
        try await edit(text, node: node, in: host)
    }
    private static func edit(_ text: String, node: TaskPlanAXNode, in host: NSView, submit: Bool = false) async throws {
        let id = node.identifier ?? node.label
        let field = try nativeControl(node, in: host, type: NSTextField.self)
        _ = field.scrollToVisible(field.bounds); await settle(host)
        guard let window = host.window else { throw NSError(domain: "TaskPlanInteractionTests", code: 5) }
        try expect(window.makeFirstResponder(field), "\(id) accepts own-window native editing focus")
        guard let editor = field.currentEditor() as? NSTextView else {
            throw NSError(domain: "TaskPlanInteractionTests", code: 6,
                userInfo: [NSLocalizedDescriptionKey: "\(id) must expose its current native field editor"])
        }
        editor.insertText(text, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        await settle(host)
        if submit {
            let timestamp = ProcessInfo.processInfo.systemUptime
            for eventType in [NSEvent.EventType.keyDown, .keyUp] {
                guard let event = NSEvent.keyEvent(with: eventType, location: .zero, modifierFlags: [],
                    timestamp: timestamp, windowNumber: window.windowNumber, context: nil,
                    characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36) else {
                    throw NSError(domain: "TaskPlanInteractionTests", code: 7)
                }
                window.sendEvent(event)
            }
        } else { try expect(window.makeFirstResponder(nil), "\(id) finishes native editing without blocking navigation") }
        await settle(host)
    }
    private static func setDate(_ date: Date, id: String, in host: NSView) async throws {
        let node = try await find(host, id: id)
        let picker = try nativeControl(node, in: host, type: NSDatePicker.self)
        try expect(picker.isEnabled && picker.action != nil, "\(id) exposes an enabled native date-picker action")
        picker.dateValue = date
        try expect(picker.sendAction(picker.action, to: picker.target), "\(id) dispatches its actual native date binding action")
        await settle(host)
    }
    private static func withHost(_ view: AnyView, size: CGSize, factor: CGFloat = 1,
        body: (NSHostingView<AnyView>, NSWindow) async throws -> Void) async throws {
        let host = NSHostingView(rootView: AnyView(view
            .environment(\.workspaceZoom, WorkspaceZoomLayout(factor: factor))
            .environment(\.displayScale, 2).environment(\.daBinTooltipsEnabled, false)
            .preferredColorScheme(factor == 2 ? .dark : .light)))
        host.sizingOptions = []; host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        window.orderFront(nil); await settle(host)
        let status = await Task.detached {
            let process = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            AXUIElementSetMessagingTimeout(process, 3)
            var windows: CFTypeRef?
            return AXUIElementCopyAttributeValue(process, kAXWindowsAttribute as CFString, &windows)
        }.value
        try expect(status == .success, "Only this fixture process exposes its accessibility hierarchy")
        try expect(abs(host.bounds.width - size.width) < 1 && abs(host.bounds.height - size.height) < 1
            && abs(window.contentLayoutRect.width - size.width) < 1 && abs(window.contentLayoutRect.height - size.height) < 1,
            "Host and native window retain the actual requested \(Int(size.width))×\(Int(size.height)) viewport")
        try expect(window.frame.maxX < 0 && !window.isKeyWindow && !NSApp.isActive,
            "Native fixture stays offscreen, non-key and inactive")
        try await body(host, window)
        try expect(!window.isKeyWindow && !NSApp.isActive, "Native editing and menu actions preserve inactive own-window scope")
    }
    private static func contained(_ node: TaskPlanAXNode, window: NSWindow, horizontalOnly: Bool = false) throws {
        let viewport = window.convertToScreen(window.contentLayoutRect).insetBy(dx: -1, dy: -1), frame = node.frame
        try expect(frame.width > 0 && frame.height > 0 && frame.minX >= viewport.minX && frame.maxX <= viewport.maxX
            && (horizontalOnly || (frame.minY >= viewport.minY && frame.maxY <= viewport.maxY)),
            "\(node.identifier ?? node.label) fits the actual \(Int(viewport.width - 2))-point viewport: \(NSStringFromRect(frame))")
    }
    private static func menuItems(_ menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { [$0] + ($0.submenu.map(menuItems) ?? []) }
    }
    private static func nativeMenu(_ host: NSView, id: String, containing title: String) async throws -> NSMenu {
        let target = try await find(host, id: id), tracking = TaskPlanMenuTracking(window: host.window)
        let center = NotificationCenter.default
        let began = center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { notification in
            guard let menu = notification.object as? NSMenu else { return }
            MainActor.assumeIsolated { tracking.began(menu) }
        }
        let ended = center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: nil) { notification in
            guard let menu = notification.object as? NSMenu else { return }
            MainActor.assumeIsolated { tracking.didEnd(menu) }
        }
        let timer = Timer(timeInterval: 0.02, repeats: true) { _ in MainActor.assumeIsolated { tracking.cancel() } }
        RunLoop.main.add(timer, forMode: .common); RunLoop.main.add(timer, forMode: .eventTracking)
        defer { timer.invalidate(); center.removeObserver(began); center.removeObserver(ended) }
        var accepted = target.actions.contains("AXShowMenu") ? target.showMenu() : false
        if !accepted && tracking.menus.isEmpty && target.actions.contains("AXPress") { accepted = target.press() }
        if !accepted && tracking.menus.isEmpty {
            guard let window = host.window else { throw NSError(domain: "TaskPlanInteractionTests", code: 8) }
            let frame = target.frame, point = window.convertPoint(fromScreen: NSPoint(x: frame.midX, y: frame.midY))
            try contained(target, window: window)
            let timestamp = ProcessInfo.processInfo.systemUptime
            guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
                timestamp: timestamp, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1),
                  let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [],
                timestamp: timestamp + 0.02, windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0) else {
                throw NSError(domain: "TaskPlanInteractionTests", code: 9)
            }
            NSApp.postEvent(up, atStart: true); window.sendEvent(down)
            if let remaining = NSApp.nextEvent(matching: .leftMouseUp, until: Date(), inMode: .default, dequeue: true) {
                try expect(remaining.windowNumber == window.windowNumber, "Native menu release belongs only to the fixture")
                window.sendEvent(remaining)
            }
        }
        await settle(host)
        guard let menu = tracking.menus.first(where: { menuItems($0).contains { $0.title == title } }) else {
            throw NSError(domain: "TaskPlanInteractionTests", code: 10,
                userInfo: [NSLocalizedDescriptionKey: "\(id) must expose the real native menu containing \(title)"])
        }
        try expect(!tracking.timedOut && tracking.ended.contains(ObjectIdentifier(menu)), "Actual \(id) menu closes before item dispatch")
        return menu
    }
    private static func selectMenu(_ host: NSView, id: String, title: String) async throws {
        let menu = try await nativeMenu(host, id: id, containing: title)
        guard let item = menuItems(menu).first(where: { $0.title == title }), let owner = item.menu else {
            throw NSError(domain: "TaskPlanInteractionTests", code: 11)
        }
        try expect(item.isEnabled && !item.isHidden && item.action != nil, "Native menu destination \(title) remains actionable")
        owner.performActionForItem(at: owner.index(of: item)); await settle(host)
    }
    private static func render(_ view: NSView, name: String, output: URL) throws {
        let size = view.bounds.size
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2),
            pixelsHigh: Int(size.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw NSError(domain: "TaskPlanInteractionTests", code: 12)
        }
        bitmap.size = size; view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain: "TaskPlanInteractionTests", code: 13) }
        try png.write(to: output.appendingPathComponent(name + "@2x.png"))
    }

    private static func planningActions(output: URL) async throws {
        let fixture = TaskPlanBindingFixture()
        try await withHost(AnyView(TaskPlanBoundEditor(fixture: fixture)), size: CGSize(width: 760, height: 680)) { host, window in
            for priority in TaskPriority.allCases {
                let node = try await find(host, id: "task-priority-choice-" + priority.rawValue)
                try contained(node, window: window)
                try expect(node.label == (priority == .none ? priority.title : "\(priority.title) priority"),
                    "Each compact priority retains its descriptive accessible label")
                try await press(host, id: "task-priority-choice-" + priority.rawValue)
                try expect(fixture.planning.priority == priority, "Priority \(priority.title) edits the actual bound plan")
            }
            try await press(host, id: "task-plan-today")
            try expect(fixture.planning.plannedDay == CaptureCalendar.dayString(Date()), "Today directly selects the local work day")
            try await enterLabel("09:35", label: "Optional planned local time in HH:MM", in: host)
            try expect(fixture.planning.plannedTime == "09:35", "Native optional time entry updates the local work-time binding")
            try await press(host, id: "task-plan-tomorrow")
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
            try expect(fixture.planning.plannedDay == CaptureCalendar.dayString(tomorrow), "Tomorrow changes work day without scheduling a reminder")
            let pickedDay = Calendar.current.date(byAdding: .day, value: 4, to: Date())!
            try await setDate(pickedDay, id: "task-planned-day", in: host)
            try expect(fixture.planning.plannedDay == CaptureCalendar.dayString(pickedDay), "Native day picker binds an exact work date")
            try await press(host, id: "task-plan-enabled")
            try expect(fixture.planning.plannedDay == nil && fixture.planning.plannedTime == nil && fixture.planning.order == nil,
                "Unplanned directly clears the work day, its optional time and manual order")

            try await press(host, id: "task-deadline-add")
            try expect(fixture.planning.deadline != nil, "Add deadline directly reveals a bound date control")
            let deadline = Date().addingTimeInterval(86_400 * 5)
            try await setDate(deadline, id: "task-deadline", in: host)
            try expect(abs(fixture.planning.deadline!.timeIntervalSince(deadline)) < 1,
                "Native deadline entry binds the date and time without changing the planned day")
            try await press(host, id: "task-deadline-remove")
            try expect(fixture.planning.deadline == nil && fixture.planning.plannedDay == nil,
                "Removing a deadline keeps the task unplanned")
            try await selectMenu(host, id: "task-recurrence", title: TaskRecurrence.weekly.title)
            try expect(fixture.planning.recurrence == .weekly, "Actual native Repeat menu selects weekly recurrence")

            for title in ["Fictional first next step", "Fictional second next step", "Fictional third next step"] {
                let prior = fixture.planning.checklist.count
                try await enter(title, id: "task-checklist-new", in: host, submit: true)
                try expect(fixture.planning.checklist.count == prior + 1 && fixture.planning.checklist.last?.text == title,
                    "Own-window Return adds exactly one next step through the composer")
                let composer = try nativeControl(try await find(host, id: "task-checklist-new"), in: host, type: NSTextField.self)
                try expect(composer.stringValue.isEmpty && composer.currentEditor() != nil,
                    "Return clears the composer and keeps native focus ready for the next step")
            }
            let first = fixture.planning.checklist[0], second = fixture.planning.checklist[1]
            let composer = try await find(host, id: "task-checklist-new")
            let firstText = try await find(host, id: "task-checklist-text-" + first.id.uuidString)
            try expect(composer.frame.minY >= firstText.frame.maxY,
                "The next-step composer precedes the existing checklist in actual rendered geometry")
            try await press(host, id: "task-checklist-complete-" + first.id.uuidString)
            try expect(fixture.planning.checklist[0].isCompleted && !fixture.planning.checklist[1].isCompleted,
                "Native checkbox completes only its own checklist step")
            try expect(nodes(host).contains { $0.label == "Checklist progress" }, "Checklist progress has a descriptive accessible control")
            let multiline = "Fictional edited step with a second line\nRésumé · 日本語 · שלום"
            try await enter(multiline, id: "task-checklist-text-" + first.id.uuidString, in: host)
            try expect(fixture.planning.checklist[0].text == multiline && fixture.planning.checklist[0].isCompleted,
                "Native multiline step editing preserves its completion state and Unicode content")
            let remove = try await find(host, id: "task-checklist-remove-" + second.id.uuidString)
            try expect(remove.frame.width >= 30 && remove.frame.height >= 30,
                "Removing a checklist step retains a usable native pointer target")
            try await press(host, id: "task-checklist-remove-" + second.id.uuidString)
            try expect(fixture.planning.checklist.count == 2 && !fixture.planning.checklist.contains { $0.id == second.id }
                && fixture.planning.checklist[0].id == first.id && fixture.planning.checklist[0].text == multiline,
                "Removal changes only its selected step, preserving sibling identity and edited text")
            try render(host, name: "plan-760-native-actions", output: output)
            evidence.append(["context": "native-planning-actions", "stepCount": fixture.planning.checklist.count,
                "priority": fixture.planning.priority.rawValue, "recurrence": fixture.planning.recurrence.rawValue])
        }
    }

    private static func checklistBoundaries() async throws {
        let fixture = TaskPlanBindingFixture()
        try await withHost(AnyView(TaskPlanBoundEditor(fixture: fixture)), size: CGSize(width: 760, height: 680)) { host, _ in
            let tooLong = String(repeating: "x", count: 501)
            try await enter(tooLong, id: "task-checklist-new", in: host)
            let add = try await find(host, id: "task-checklist-add")
            try expect(!enabled(add) && fixture.planning.checklist.isEmpty,
                "A 501-character native draft disables Add without changing the checklist")
            let lengthError = try await find(host, id: "task-checklist-input-error")
            try expect(lengthError.label.contains("500"),
                "The long-step error identifies the 500-character limit adjacent to the draft")
            let exact = String(repeating: "x", count: 500)
            try await enter(exact, id: "task-checklist-new", in: host)
            try await press(host, id: "task-checklist-add")
            try expect(fixture.planning.checklist.count == 1 && fixture.planning.checklist[0].text == exact,
                "Exactly 500 characters remain valid through the native Add action")
        }
        let steps = (0..<100).map { TaskChecklistItem(text: "Fictional seeded step \($0 + 1)") }
        let full = TaskPlanBindingFixture(planning: TaskPlanning(checklist: steps))
        try await withHost(AnyView(TaskPlanBoundEditor(fixture: full)), size: CGSize(width: 380, height: 680)) { host, _ in
            try await enter("Fictional blocked next step", id: "task-checklist-new", in: host)
            let add = try await find(host, id: "task-checklist-add")
            try expect(!enabled(add) && full.planning.checklist.count == 100,
                "A full 100-step checklist disables Add before exceeding its persisted limit")
            let error = try await find(host, id: "task-checklist-input-error")
            try expect(error.label.contains("100"), "Full-checklist feedback describes how to make room")
            try await press(host, id: "task-checklist-remove-" + steps[0].id.uuidString)
            try await press(host, id: "task-checklist-add")
            try expect(full.planning.checklist.count == 100 && full.planning.checklist.last?.text == "Fictional blocked next step",
                "Removing one existing step immediately permits the pending native composer draft")
        }
    }

    private static func compactEditorMatrix(output: URL) async throws {
        for width in [CGFloat(380), 760] {
            let fixture = TaskPlanBindingFixture(planning: TaskPlanning(priority: .medium, checklist: [
                TaskChecklistItem(text: "Fictional step that wraps naturally on a compact desktop pane without requiring horizontal scrolling"),
                TaskChecklistItem(text: "Résumé · 日本語 · שלום", isCompleted: true)]))
            try await withHost(AnyView(TaskPlanBoundEditor(fixture: fixture)), size: CGSize(width: width, height: 680)) { host, window in
                for id in ["task-plan-today", "task-plan-tomorrow", "task-plan-enabled", "task-deadline-add", "task-recurrence", "task-checklist-new", "task-checklist-add"] {
                    try contained(try await find(host, id: id), window: window)
                }
                for priority in TaskPriority.allCases {
                    try contained(try await find(host, id: "task-priority-choice-" + priority.rawValue), window: window)
                }
                for step in fixture.planning.checklist {
                    for prefix in ["task-checklist-text-", "task-checklist-complete-", "task-checklist-remove-"] {
                        try contained(try await find(host, id: prefix + step.id.uuidString), window: window, horizontalOnly: true)
                    }
                }
                try render(host, name: "plan-\(Int(width))-default", output: output)
                try await press(host, id: "task-deadline-add")
                try contained(try await find(host, id: "task-deadline"), window: window)
                try contained(try await find(host, id: "task-deadline-remove"), window: window)
                try render(host, name: "plan-\(Int(width))-deadline", output: output)
                evidence.append(["context": "plan-layout", "width": width, "height": 680,
                    "stepCount": fixture.planning.checklist.count, "draftValid": fixture.planning.isValid])
            }
            let reminder = TaskPlanBindingFixture()
            try await withHost(AnyView(TaskPlanBoundEditor(fixture: reminder, reminderOnly: true)), size: CGSize(width: width, height: 380)) { host, window in
                for id in ["reminder-preset-15", "reminder-preset-60", "reminder-preset-tomorrow", "reminder-enabled"] {
                    try contained(try await find(host, id: id), window: window)
                }
                try await press(host, id: "reminder-preset-15")
                try expect(reminder.enabled && reminder.mode == .countdown && reminder.hours == 0 && reminder.minutes == 15,
                    "15-minute preset enables the relative reminder draft in one real action")
                try await enter("2", id: "reminder-countdown-hours", in: host)
                try await enter("7", id: "reminder-countdown-minutes", in: host)
                try expect(reminder.hours == 2 && reminder.minutes == 7, "Native custom countdown fields update both duration bindings")
                try render(host, name: "reminder-\(Int(width))-countdown", output: output)
                try await press(host, id: "reminder-preset-60")
                try expect(reminder.enabled && reminder.mode == .countdown && reminder.hours == 1 && reminder.minutes == 0,
                    "One-hour preset replaces custom duration without adding a date or commit")
                try await press(host, id: "reminder-preset-tomorrow")
                let calendar = Calendar.current, tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!
                try expect(reminder.enabled && reminder.mode == .date && calendar.isDate(reminder.date, inSameDayAs: tomorrow)
                    && calendar.component(.hour, from: reminder.date) == 9 && calendar.component(.minute, from: reminder.date) == 0,
                    "Tomorrow selects 9 AM in the current civil calendar and enables only the draft")
                for id in ["reminder-date-time", "reminder-time", "reminder-mode-countdown", "reminder-mode-date", "reminder-editor"] {
                    try contained(try await find(host, id: id), window: window)
                }
                try render(host, name: "reminder-\(Int(width))-date", output: output)
                let preserved = reminder.date
                try await press(host, id: "reminder-enabled")
                try expect(!reminder.enabled && reminder.date == preserved, "Disabling a reminder preserves the chosen date draft")
                try await press(host, id: "reminder-preset-60")
                try expect(reminder.enabled && reminder.hours == 1 && reminder.minutes == 0,
                    "A preset re-enables a disabled reminder without an extra switch step")
            }
        }
    }

    private static func detailSaveAndReminder(output: URL) async throws {
        let services = try Services(); defer { services.close() }
        let originalPlanning = TaskPlanning(checklist: [TaskChecklistItem(text: "Fictional persisted step")])
        let capture = try services.store.createTask(text: "Fictional task before editing", planning: originalPlanning)
        let originalReceipt = (capture.capturedAt, capture.captureDay, capture.originalText)
        services.state.openCapture(capture.id, focus: "task")
        let draft = services.state.selectedDraft!
        try await withHost(AnyView(DetailScreen(state: services.state, capture: capture, draft: draft)),
            size: CGSize(width: 380, height: 680)) { host, window in
            for id in ["detail-title", "detail-section-navigation", "detail-save", "task-checklist-new", "task-checklist-add"] {
                try contained(try await find(host, id: id), window: window)
            }
            try await enter("Fictional pending task title", id: "detail-title", in: host)
            try await press(host, id: "task-plan-tomorrow")
            try await enterLabel("10:20", label: "Optional planned local time in HH:MM", in: host)
            try expect(draft.planning.plannedDay == CaptureCalendar.dayString(Calendar.current.date(byAdding: .day, value: 1, to: Date())!)
                && draft.planning.plannedTime == "10:20" && capture.taskPlanning?.plannedDay == nil,
                "Direct Detail work-day/time controls edit only the pending plan until explicit Save")
            try await press(host, id: "task-priority-choice-high")
            try await enter("Fictional pending checklist step", id: "task-checklist-new", in: host, submit: true)
            try expect(draft.pendingChecklistText.isEmpty, "Native Return clears the owning pending-step draft after adding one row")
            let second = draft.planning.checklist.last!
            try await press(host, id: "task-checklist-complete-" + second.id.uuidString)
            let stepField = try nativeControl(try await find(host, id: "task-checklist-text-" + second.id.uuidString), in: host, type: NSTextField.self)
            _ = stepField.scrollToVisible(stepField.bounds); await settle(host)
            try expect(window.makeFirstResponder(stepField), "Visible native checklist field accepts own-window editing focus")
            guard let stepEditor = stepField.currentEditor() as? NSTextView else { throw NSError(domain: "TaskPlanInteractionTests", code: 15) }
            stepEditor.setSelectedRange(NSRange(location: 2, length: 6))
            let pendingTitle = draft.title, pendingPlan = draft.planning
            try render(host, name: "detail-380-task-pending", output: output)

            try await press(host, id: "detail-section-reminder")
            try expect(stepField.currentEditor() == nil || window.firstResponder !== stepEditor,
                "Navigating to Reminder releases the hidden native checklist editor")
            try expect(draft.title == pendingTitle && draft.planning == pendingPlan,
                "Section navigation preserves pending task title, checklist and priority")
            try await press(host, id: "reminder-preset-15")
            try expect(draft.reminderEnabled && draft.reminderMode == .countdown && draft.countdownHours == 0 && draft.countdownMinutes == 15,
                "Detail reminder preset changes only the recoverable reminder draft")
            try expect(capture.reminderAt == nil && capture.title != pendingTitle && capture.taskPlanning == originalPlanning,
                "Reminder preset does not prematurely persist reminder or pending task edits")
            await settle(host)
            let beforeCommit = Date()
            try await press(host, id: "capture-save-reminder")
            let afterCommit = Date()
            try expect(capture.reminderAt != nil && capture.reminderAt! >= beforeCommit.addingTimeInterval(900)
                && capture.reminderAt! <= afterCommit.addingTimeInterval(900),
                "Relative countdown resolves from actual Apply time instead of preset-selection time")
            try expect(draft.title == pendingTitle && draft.planning == pendingPlan && draft.hasChanges
                && capture.title != pendingTitle && capture.taskPlanning == originalPlanning,
                "Apply reminder saves only the reminder and retains all pending task edits")
            try expect(draft.reminderMode == .date && !draft.reminderChanged,
                "Applied countdown adopts the saved absolute reminder as its clean baseline")
            let committedReminder = capture.reminderAt, committedRevision = capture.reminderRevision
            try render(host, name: "detail-380-reminder-applied", output: output)

            try await press(host, id: "reminder-mode-date")
            let past = Date().addingTimeInterval(-172_800)
            try await setDate(past, id: "reminder-date-time", in: host)
            try await setDate(past, id: "reminder-time", in: host)
            try expect(draft.reminderDate < Date(), "Actual date/time controls can retain a rejected past-date draft")
            try await press(host, id: "capture-save-reminder")
            try expect(draft.hasError && draft.reminderDate < Date() && capture.reminderAt == committedReminder
                && capture.reminderRevision == committedRevision && draft.title == pendingTitle && draft.planning == pendingPlan,
                "Past-date Apply rejects persistence without losing failed reminder input or pending task edits")
            try await press(host, id: "reminder-preset-60")
            try await press(host, id: "capture-save-reminder")
            let newestReminder = capture.reminderAt
            try await selectMenu(host, id: "detail-section-picker", title: "Task")
            try expect(draft.title == pendingTitle && draft.planning == pendingPlan,
                "Returning through the actual compact section menu resumes unchanged task edits")
            try await press(host, id: "detail-save")
            try expect(capture.title == pendingTitle && capture.taskPlanning == pendingPlan && capture.reminderAt == newestReminder
                && !draft.hasChanges, "Explicit Save commits pending checklist and planning without reverting the separately applied reminder")
            try expect(capture.capturedAt == originalReceipt.0 && capture.captureDay == originalReceipt.1
                && capture.originalText == originalReceipt.2, "Editing a task preserves the immutable original capture receipt")
            let reopened = try CaptureStore(root: services.root, repairArchiveOnOpen: false)
            defer { reopened.cancelArchiveRepair() }
            let restored = reopened.captures.first { $0.id == capture.id }!
            try expect(restored.title == pendingTitle && restored.taskPlanning == pendingPlan && restored.reminderAt == newestReminder
                && restored.taskPlanning?.checklist.last?.isCompleted == true,
                "Title, checklist text/completion, priority and applied reminder survive reopening the disposable archive")
        }
        try expect(services.notifications.requests == 0 && services.notifications.additions == 0,
            "Denied fake reminder authorization never requests permission or schedules an OS notification")
    }

    private static func pendingChecklistNavigation() async throws {
        let services = try Services(); defer { services.close() }
        let capture = try services.store.createTask(text: "Fictional pending step navigation")
        services.state.openLibrary(); services.state.openCapture(capture.id, focus: "task")
        let draft = services.state.selectedDraft!
        let theme = ThemeSettings(defaults: services.defaults); theme.setShowTooltips(false)
        try await withHost(AnyView(BoardView(state: services.state, theme: theme)), size: CGSize(width: 760, height: 760)) { host, _ in
            try await enter("Fictional unsubmitted navigation step", id: "task-checklist-new", in: host)
            try expect(draft.pendingChecklistText == "Fictional unsubmitted navigation step" && draft.hasChanges
                && draft.planning.checklist.isEmpty, "Actual native composer binds pending text to its owner before Return or Add")
            services.state.showSettings(); await settle(host)
            try expect(services.state.route == .settings, "Pending valid step does not block leaving the task")
            services.state.back(); await settle(host)
            let returnedField = try nativeControl(try await find(host, id: "task-checklist-new"), in: host, type: NSTextField.self)
            try expect(services.state.selectedDraft === draft && returnedField.stringValue == "Fictional unsubmitted navigation step",
                "Back remounts the actual checklist composer with its unsubmitted text")
            services.state.forward(); await settle(host); services.state.back(); await settle(host)
            let forwardField = try nativeControl(try await find(host, id: "task-checklist-new"), in: host, type: NSTextField.self)
            try expect(forwardField.stringValue == draft.pendingChecklistText, "Forward then Back preserves the same typed pending step")
            try await press(host, id: "detail-section-reminder")
            try await press(host, id: "reminder-preset-15")
            try await press(host, id: "capture-save-reminder")
            try expect(draft.pendingChecklistText == "Fictional unsubmitted navigation step"
                && capture.taskPlanning?.checklist.isEmpty != false, "Reminder-only Apply neither consumes nor prematurely commits a typed pending step")
            try await press(host, id: "detail-section-task")
            try await press(host, id: "detail-save")
            let first = capture.taskPlanning!.checklist[0]
            try expect(first.text == "Fictional unsubmitted navigation step" && draft.pendingChecklistText.isEmpty
                && !draft.hasChanges, "Actual primary Save includes and clears one pending checklist step")
            let cleanSave = try await find(host, id: "detail-save")
            try expect(!enabled(cleanSave), "A clean primary Save cannot append the pending step again")
            try await enter("Fictional retained after failed Save", id: "task-checklist-new", in: host)
            services.store.failureInjector = { if $0 == .beforeMetadataSave { throw CaptureStoreError.importVerificationFailed } }
            try await press(host, id: "detail-save")
            let failedField = try nativeControl(try await find(host, id: "task-checklist-new"), in: host, type: NSTextField.self)
            try expect(draft.hasError && failedField.stringValue == "Fictional retained after failed Save"
                && draft.pendingChecklistText == failedField.stringValue && capture.taskPlanning?.checklist.count == 1,
                "A real failed primary Save leaves native pending text and committed checklist intact")
            services.store.failureInjector = nil
            try await press(host, id: "detail-save")
            try expect(capture.taskPlanning?.checklist.count == 2 && capture.taskPlanning?.checklist[0].id == first.id
                && draft.pendingChecklistText.isEmpty, "Retrying primary Save commits the retained typed step once")
            try await enter(String(repeating: "x", count: 501), id: "task-checklist-new", in: host)
            try await press(host, id: "detail-save")
            try expect(draft.hasUnresolvedValidation && draft.pendingChecklistText.count == 501,
                "Actual primary Save retains an oversized pending step with unresolved validation")
            let escape = try await find(host, id: "detail-keep-draft-back")
            try contained(escape, window: host.window!)
            try await press(host, id: "detail-keep-draft-back")
            try expect(services.state.route == .library && draft.pendingChecklistText.count == 501
                && draft.hasUnresolvedValidation && capture.taskPlanning?.checklist.count == 2,
                "Actual Keep draft and go back leaves Detail without consuming invalid input or changing the capture")
            services.state.forward(); await settle(host)
            let keptField = try nativeControl(try await find(host, id: "task-checklist-new"), in: host, type: NSTextField.self)
            try expect(services.state.selectedDraft === draft && keptField.stringValue.count == 501
                && draft.hasUnresolvedValidation, "Forward restores the same invalid owner and its actual typed checklist input")
            try await enter("Fictional corrected retained step", id: "task-checklist-new", in: host)
            try await press(host, id: "detail-save")
            try expect(!draft.hasUnresolvedValidation && !nodes(host).contains { $0.identifier == "detail-keep-draft-back" }
                && capture.taskPlanning?.checklist.count == 3,
                "Correcting and saving the kept draft removes the error-only escape control")
            services.state.openLibrary(); services.state.openNewTask()
            services.state.newTaskDraft.text = "Fictional native task with pending step"
            await settle(host)
            try await enter("Fictional new-task pending step", id: "task-checklist-new", in: host)
            services.state.showSettings(); await settle(host); services.state.back(); await settle(host)
            let newField = try nativeControl(try await find(host, id: "task-checklist-new"), in: host, type: NSTextField.self)
            try expect(services.state.route == .newTask && newField.stringValue == "Fictional new-task pending step",
                "New-task Back remounts its native pending-step composer without losing typed text")
            try await pressLabel(host, label: "Add task")
            let created = services.store.captures.first { $0.originalText == "Fictional native task with pending step" }!
            try expect(created.taskPlanning?.checklist.map(\.text) == ["Fictional new-task pending step"]
                && services.state.newTaskDraft.pendingChecklistText.isEmpty,
                "Actual Add task includes its unsubmitted native checklist step exactly once")
        }
    }

    private static func completedReminderRetry() async throws {
        let services = try Services(); defer { services.close() }
        let capture = try services.store.createTask(text: "Fictional completed reminder retry",
            reminderAt: Date().addingTimeInterval(86_400))
        capture.notificationState = "failed"
        services.state.openCapture(capture.id, focus: "reminder")
        let draft = services.state.selectedDraft!
        try await withHost(AnyView(DetailScreen(state: services.state, capture: capture, draft: draft)), size: CGSize(width: 600, height: 680)) { host, _ in
            _ = try await find(host, id: "capture-retry-reminder")
            services.state.toggleTaskCompletion(capture); await settle(host)
            try expect(capture.isCompleted && !nodes(host).contains { $0.identifier == "capture-retry-reminder" },
                "Completed task reminder pane hides Retry while notifications are paused")
            try expect(nodes(host).contains { $0.identifier == "capture-remove-reminder" },
                "Completed task still supports explicitly removing its saved reminder")
            services.state.toggleTaskCompletion(capture); await settle(host)
            _ = try await find(host, id: "capture-retry-reminder")
            try expect(!capture.isCompleted, "Reopening the task restores its valid notification retry flow")
        }
        try expect(services.notifications.requests == 0 && services.notifications.additions == 0,
            "Completed-task retry fixture never requests permission or schedules an OS notification")
    }

    private static func fullBoardMatrix(output: URL) async throws {
        for factor in [CGFloat(1), 2] {
            let services = try Services(); defer { services.close() }
            let plan = TaskPlanning(priority: .high, checklist: [
                TaskChecklistItem(text: "Fictional multiline planning step that remains readable while the desktop window is narrow"),
                TaskChecklistItem(text: "Fictional completed step", isCompleted: true)])
            let capture = try services.store.createTask(text: "Fictional longer task title for a narrow desktop companion window with readable planning controls", planning: plan)
            try services.store.setOrganization(capture, pinned: false, projectName: "Fictional project with a deliberately descriptive name")
            services.state.openCapture(capture.id, focus: "task"); services.state.workspaceZoom.setFactor(factor)
            let theme = ThemeSettings(defaults: services.defaults)
            theme.setShowTooltips(false); theme.setDarkMode(factor == 2)
            try await withHost(AnyView(BoardView(state: services.state, theme: theme)), size: CGSize(width: 380, height: 680), factor: factor) { host, window in
                for id in ["detail-title", "detail-section-navigation", "detail-save", "detail-actions"] {
                    try contained(try await find(host, id: id), window: window)
                }
                let pane = try await find(host, id: "detail-pane-task")
                try expect(pane.frame.height >= 180, "Full narrow Board at \(Int(factor * 100))% leaves meaningful task-editing height")
                for id in ["task-checklist-new", "task-checklist-add", "task-recurrence", "task-deadline-add"] {
                    try contained(try await find(host, id: id), window: window, horizontalOnly: true)
                }
                for priority in TaskPriority.allCases {
                    try contained(try await find(host, id: "task-priority-choice-" + priority.rawValue), window: window, horizontalOnly: true)
                }
                let titleNode = try await find(host, id: "detail-title")
                let titleField = try nativeControl(titleNode, in: host, type: NSTextField.self)
                try expect(window.makeFirstResponder(nil), "Unfocused task-title raster is captured outside field editing")
                await settle(host)
                let titleFrame = titleField.convert(titleField.bounds, to: host)
                let titleTop = host.isFlipped ? titleFrame.minY : host.bounds.height - titleFrame.maxY
                let titleLine = ceil(NSLayoutManager().defaultLineHeight(for: titleField.font!))
                let titleDiagnostic: [String: Any] = ["zoom": factor, "fieldClass": String(describing: type(of: titleField)),
                    "frame": NSStringFromRect(titleField.frame), "bounds": NSStringFromRect(titleField.bounds),
                    "preferredWidth": titleField.preferredMaxLayoutWidth, "lineHeight": titleLine,
                    "alignmentRect": NSStringFromRect(titleField.alignmentRect(forFrame: titleField.frame)),
                    "alignmentInsets": ["left": titleField.alignmentRectInsets.left, "right": titleField.alignmentRectInsets.right,
                        "top": titleField.alignmentRectInsets.top, "bottom": titleField.alignmentRectInsets.bottom],
                    "drawingRect": NSStringFromRect(titleField.cell!.drawingRect(forBounds: titleField.bounds)),
                    "fontSize": titleField.font!.pointSize, "intrinsicSize": NSStringFromSize(titleField.intrinsicContentSize),
                    "fitSize": NSStringFromSize(titleField.sizeThatFits(NSSize(width: titleField.bounds.width, height: .greatestFiniteMagnitude))),
                    "titleFrameTopLeft": ["x": titleFrame.minX, "y": titleTop, "width": titleFrame.width, "height": titleFrame.height],
                    "text": titleField.stringValue, "maximumLines": titleField.maximumNumberOfLines,
                    "hostFlipped": host.isFlipped]
                try JSONSerialization.data(withJSONObject: titleDiagnostic, options: [.prettyPrinted, .sortedKeys])
                    .write(to: output.appendingPathComponent("title-geometry-zoom\(Int(factor * 100)).json"))
                try render(host, name: "title-geometry-zoom\(Int(factor * 100))", output: output)
                try expect(titleField.maximumNumberOfLines == 2 && titleField.cell?.wraps == true
                    && titleField.cell?.truncatesLastVisibleLine == true && titleField.cell?.isScrollable == false,
                    "Task title uses native bounded wrapping and a visible final-line truncation")
                try expect(abs(titleField.preferredMaxLayoutWidth - titleField.bounds.width) < 1
                    && titleField.bounds.height <= titleLine * 2 + 4.5,
                    "Task title measures at its real available width and never reserves a third line")
                try expect(titleField.stringValue == capture.title && titleField.currentEditor() == nil,
                    "Unfocused bounded title retains the complete task title")
                let titleRender = "full-board-380-task-zoom\(Int(factor * 100))"
                try render(host, name: titleRender, output: output)
                evidence.append(["context": "unfocused-title-raster", "file": titleRender + "@2x.png",
                    "pixelScale": 2, "zoom": factor, "theme": factor == 2 ? "dark" : "light",
                    "titleFrameTopLeft": ["x": titleFrame.minX, "y": titleTop,
                        "width": titleFrame.width, "height": titleFrame.height], "lineHeight": titleLine,
                    "fontSize": titleField.font!.pointSize, "completeTitleRetained": true])
                try await press(host, id: "detail-section-reminder")
                try await press(host, id: "reminder-preset-15")
                for id in ["reminder-preset-15", "reminder-preset-60", "reminder-preset-tomorrow", "reminder-countdown-hours", "reminder-countdown-minutes", "capture-save-reminder", "detail-save"] {
                    try contained(try await find(host, id: id), window: window)
                }
                try render(host, name: "full-board-380-reminder-zoom\(Int(factor * 100))", output: output)
                try await press(host, id: "reminder-preset-tomorrow")
                try contained(try await find(host, id: "reminder-date-time"), window: window)
                try contained(try await find(host, id: "reminder-time"), window: window)
                try render(host, name: "full-board-380-reminder-date-zoom\(Int(factor * 100))", output: output)
                try expect(capture.reminderAt == nil && capture.taskPlanning == plan,
                    "Rendering and selecting drafts do not persist planning or reminder changes")
                evidence.append(["context": "full-board-layout", "width": 380, "height": 680,
                    "zoom": factor, "taskPaneHeight": pane.frame.height])
            }
            try expect(services.notifications.requests == 0 && services.notifications.additions == 0,
                "Responsive fixtures do not ask for permission or deliver notifications")
        }
    }

    private static func nativeTitleEditing(output: URL) async throws {
        let services = try Services(); defer { services.close() }
        let original = "Fictional long native title for a compact desktop workspace that needs two readable lines"
        let capture = try services.store.createTask(text: original)
        services.state.openCapture(capture.id, focus: "title")
        let draft = services.state.selectedDraft!, theme = ThemeSettings(defaults: services.defaults)
        theme.setDarkMode(false); theme.setShowTooltips(false)
        try await withHost(AnyView(BoardView(state: services.state, theme: theme)), size: CGSize(width: 380, height: 680)) { host, window in
            let field = try nativeControl(try await find(host, id: "detail-title"), in: host, type: NSTextField.self)
            try expect(field.currentEditor() != nil, "Explicit task-title focus enters the native field editor")
            let edited = "Fictional Δ title 日本語 with a recoverable native selection and readable wrapping"
            try await enter(edited, id: "detail-title", in: host)
            try expect(draft.title == edited && draft.hasChanges && capture.title == original,
                "Native title typing updates the existing recoverable draft and leaves the stored task unchanged")
            try expect(window.makeFirstResponder(field), "Native task title reopens the same field editor")
            guard let editor = field.currentEditor() as? NSTextView else { throw NSError(domain: "TaskPlanInteractionTests", code: 21) }
            editor.setSelectedRange(NSRange(location: 11, length: 6))
            let identity = ObjectIdentifier(field), selection = editor.selectedRange()
            for width in [CGFloat(600), 1200, 380] {
                window.setContentSize(CGSize(width: width, height: 680))
                host.frame = NSRect(x: 0, y: 0, width: width, height: 680); await settle(host)
                let resized = try nativeControl(try await find(host, id: "detail-title"), in: host, type: NSTextField.self)
                let resizeDiagnostic: [String: Any] = ["width": width,
                    "originalFieldID": String(describing: identity), "resizedFieldID": String(describing: ObjectIdentifier(resized)),
                    "sameField": ObjectIdentifier(resized) == identity, "sameEditor": resized.currentEditor() === editor,
                    "firstResponderIsEditor": window.firstResponder === editor,
                    "firstResponderClass": window.firstResponder.map { String(describing: type(of: $0)) } ?? "nil",
                    "originalEditorID": String(describing: ObjectIdentifier(editor)),
                    "currentEditorID": resized.currentEditor().map { String(describing: ObjectIdentifier($0)) } ?? "nil",
                    "expectedSelection": NSStringFromRange(selection), "originalEditorSelection": NSStringFromRange(editor.selectedRange()),
                    "currentEditorSelection": (resized.currentEditor() as? NSTextView).map { NSStringFromRange($0.selectedRange()) } ?? "nil",
                    "originalEditorText": editor.string, "resizedText": resized.stringValue,
                    "fieldWindowPresent": field.window === window, "resizedWindowPresent": resized.window === window,
                    "bounds": NSStringFromRect(resized.bounds), "preferredWidth": resized.preferredMaxLayoutWidth]
                try JSONSerialization.data(withJSONObject: resizeDiagnostic, options: [.prettyPrinted, .sortedKeys])
                    .write(to: output.appendingPathComponent("title-resize-\(Int(width)).json"))
                try render(host, name: "title-resize-\(Int(width))", output: output)
                try expect(ObjectIdentifier(resized) == identity && resized.currentEditor() === editor
                    && window.firstResponder === editor && editor.selectedRange() == selection,
                    "Continuous native title resize to\(Int(width)) preserves field/editor identity and UTF16 selection")
                try expect(resized.stringValue == edited && draft.title == edited
                    && abs(resized.preferredMaxLayoutWidth - resized.bounds.width) < 1,
                    "Native title resize rewraps the complete draft at the actual available width")
            }
            editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
            let time = ProcessInfo.processInfo.systemUptime
            for eventType in [NSEvent.EventType.keyDown, .keyUp] {
                let event = NSEvent.keyEvent(with: eventType, location: .zero, modifierFlags: [], timestamp: time,
                    windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
                    isARepeat: false, keyCode: 36)!
                window.sendEvent(event)
            }
            await settle(host)
            try expect(draft.title == edited + "\n" && field.currentEditor() === editor && capture.title == original,
                "Focused Return stays native multiline title input and cannot commit unrelated drafts")
            try expect(window.makeFirstResponder(nil), "Native title ends editing without losing its pending text")
            await settle(host)
            try expect(draft.title == edited + "\n", "Ending native title editing keeps the complete pending value")
            try await press(host, id: "detail-save")
            try expect(capture.title == edited && draft.title == edited && !draft.hasChanges,
                "Explicit Save commits the native title through existing normalized task-draft validation")
            try render(host, name: "native-title-edit-resize-save", output: output)
        }
    }

    private static func run() async throws {
        let repository = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).deletingLastPathComponent()
        let output = ProcessInfo.processInfo.environment["DABIN_TASK_PLAN_QA_OUTPUT"].map { URL(fileURLWithPath: $0) }
            ?? repository.appendingPathComponent("docs/qa/task-plan-redesign-2026-10-05/native")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try await planningActions(output: output)
        try await checklistBoundaries()
        try await compactEditorMatrix(output: output)
        try await detailSaveAndReminder(output: output)
        try await pendingChecklistNavigation()
        try await completedReminderRetry()
        try await fullBoardMatrix(output: output)
        try await nativeTitleEditing(output: output)
        let report: [String: Any] = ["suite": "TaskPlanInteractionTests", "checks": checks, "fixtures": evidence,
            "privacy": "Disposable fictional task metadata, private preferences, own-process native bindings and menus; no real archive, clipboard, Finder, notification permission or OS notification access."]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("native-task-plan-report.json"))
        print("PASS: \(checks) native task-plan/checklist/reminder binding, focus, persistence, validation and responsive checks; renders: \(output.path)")
    }
}
