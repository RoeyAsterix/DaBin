import AppKit
import ApplicationServices
import Foundation
import Darwin
import SwiftUI

@MainActor private final class TodayCardReminderClient: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .undetermined }
    func requestAuthorization() async throws -> Bool { false }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}

@MainActor private final class TodayCardFixtureWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override var backingScaleFactor: CGFloat { 2 }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// SwiftUI virtual nodes expose public AppKit accessibility selectors without
/// always conforming to the whole NSAccessibility protocol. Inspect only the
/// hierarchy retained by this test's own isolated hosting view.
@MainActor private struct TodayCardAX {
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
    var role: String { (value("accessibilityRole") as? String) ?? (attribute("AXRole") as? String) ?? "" }
    var accessibleValue: String? { (value("accessibilityValue") as? String) ?? (attribute("AXValue") as? String) }
    /// Native static-text nodes put their displayed text in AXValue. Labels
    /// may instead expose the phrase on a contained text child.
    var readableText: String {
        var seen = Set<ObjectIdentifier>()
        func collect(_ node: TodayCardAX, depth: Int) -> [String] {
            guard depth < 6, seen.insert(ObjectIdentifier(node.object)).inserted else { return [] }
            return [node.label, node.accessibleValue ?? ""] + node.children.flatMap { child in
                guard let object = child as? NSObject else { return [String]() }
                return collect(TodayCardAX(object: object), depth: depth + 1)
            }
        }
        return collect(self, depth: 0).filter { !$0.isEmpty }.joined(separator: " · ")
    }
    var frame: NSRect {
        let selector = NSSelectorFromString("accessibilityFrame")
        guard object.responds(to: selector) else { return .zero }
        typealias Getter = @convention(c) (AnyObject, Selector) -> NSRect
        return unsafeBitCast(object.method(for: selector), to: Getter.self)(object, selector)
    }
    /// SwiftUI Menu bridges to an NSPopUpButtonCell. Its AX frame encloses the
    /// glyph; the backing control view owns the complete clickable target.
    var interactionFrame: NSRect {
        if let cell = object as? NSCell, let view = cell.controlView, let window = view.window {
            return window.convertToScreen(view.convert(view.bounds, to: nil))
        }
        return frame
    }
    var actions: [String] { (value("accessibilityActionNames") as? [String]) ?? [] }
    func showMenu() -> Bool {
        let selector = NSSelectorFromString("accessibilityPerformShowMenu")
        guard object.responds(to: selector) else { return false }
        typealias Action = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(object.method(for: selector), to: Action.self)(object, selector)
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
            if let values = value(name) as? [Any] { result += values }
        }
        if let values = attribute("AXChildren") as? [Any] { result += values }
        if let view = object as? NSView { result += view.subviews }
        return result
    }
}

/// Real Today planning actions, compact card geometry and persistence. Fictional
/// temporary archive; all windows are offscreen and non-key. Native More menus use bounded own-process
/// tracking; Copy is routed to a private payload writer. No personal data,
/// general clipboard, notification authorization, network or global pointer events.
@main @MainActor private final class TodayTaskCardTests: NSObject, NSApplicationDelegate {
    private static var checks = 0
    private static var geometry: [[String: Any]] = []
    private var result: Int32 = 0
    @MainActor private struct Fixture {
        let hosting: NSHostingView<AnyView>
        let window: NSWindow
        func close() { window.orderOut(nil); window.contentView = nil; window.close() }
    }

    static func main() {
        let watchdog = DispatchSource.makeTimerSource(queue: .global())
        watchdog.schedule(deadline: .now() + 90)
        watchdog.setEventHandler { fputs("Today task card QA exceeded 90 seconds\n", stderr); Darwin._exit(2) }
        watchdog.resume()
        defer { watchdog.cancel() }
        let app = NSApplication.shared
        let delegate = TodayTaskCardTests()
        app.setActivationPolicy(.accessory); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        exit(delegate.result)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await Self.run() }
            catch { result = 1; fputs("Today task card QA failed: \(error)\n", stderr) }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "TodayTaskCardTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        guard try condition() else { throw failure(message) }
    }
    private static func nodes(_ view: NSView) -> [TodayCardAX] {
        var seen = Set<ObjectIdentifier>(), result: [TodayCardAX] = []
        func visit(_ candidate: Any, depth: Int) {
            guard depth < 50, let object = candidate as? NSObject,
                  seen.insert(ObjectIdentifier(object)).inserted else { return }
            let node = TodayCardAX(object: object); result.append(node)
            node.children.forEach { visit($0, depth: depth + 1) }
        }
        visit(view, depth: 0)
        NSAccessibility.unignoredChildren(from: [view]).forEach { visit($0, depth: 0) }
        return result
    }
    private static func settle(_ view: NSView) async {
        for _ in 0..<5 { view.layoutSubtreeIfNeeded(); try? await Task.sleep(for: .milliseconds(35)) }
    }
    private static func find(_ view: NSView, id: String) async throws -> TodayCardAX {
        for _ in 0..<6 {
            if let node = nodes(view).first(where: { $0.identifier == id }) { return node }
            await settle(view)
        }
        throw failure("Missing Today card control \(id): \(nodes(view).map { $0.identifier ?? $0.label }.joined(separator: "; "))")
    }
    private static func fixture<V: View>(_ root: V, size: NSSize, dark: Bool = false) async throws -> Fixture {
        let content = root.frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(Palette.background).environment(\.displayScale, 2)
            .environment(\.daBinTooltipsEnabled, false).preferredColorScheme(dark ? .dark : .light)
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
        let hosting = NSHostingView(rootView: AnyView(content))
        hosting.frame = NSRect(origin: .zero, size: size); hosting.wantsLayer = true
        let window = TodayCardFixtureWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
                                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.appearance = appearance; hosting.appearance = appearance; window.contentView = hosting
        window.orderFront(nil)
        await settle(hosting)
        let activation = await Task.detached {
            let process = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            AXUIElementSetMessagingTimeout(process, 3)
            var windows: CFTypeRef?
            return AXUIElementCopyAttributeValue(process, kAXWindowsAttribute as CFString, &windows)
        }.value
        if activation != .success {
            window.orderOut(nil); window.contentView = nil; window.close()
            throw failure("Own-process accessibility activation failed: \(activation.rawValue)")
        }
        await settle(hosting)
        try expect(window.frame.maxX < 0 && !window.isKeyWindow, "Today fixtures remain offscreen and non-key")
        return Fixture(hosting: hosting, window: window)
    }
    private static func bitmap(_ view: NSView, rect: NSRect) throws -> NSBitmapImageRep {
        let bounds = rect.intersection(view.bounds).integral
        guard bounds.width > 0, bounds.height > 0,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2),
                pixelsHigh: Int(bounds.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw failure("Cannot allocate Today evidence bitmap: \(rect)")
        }
        bitmap.size = bounds.size; view.cacheDisplay(in: bounds, to: bitmap)
        return bitmap
    }
    private static func snapshot(_ view: NSView, at url: URL) throws {
        guard let png = try bitmap(view, rect: view.bounds).representation(using: .png, properties: [:]) else {
            throw failure("Cannot encode Today card PNG")
        }
        try png.write(to: url, options: .atomic)
    }
    /// Test the live geometry, not a source-level HStack declaration: priority
    /// must remain adjacent to the project after real SwiftUI compression. This
    /// catches row wrapping, hidden labels and accidental flexible spacers.
    private static func assertProjectPriority(_ capture: Capture, fixture: Fixture) async throws {
        let project = try await find(fixture.hosting, id: "capture-project-picker-\(capture.id.uuidString)")
        let header = try await find(fixture.hosting, id: "capture-project-priority-\(capture.id.uuidString)")
        try expect(project.accessibleValue == (capture.projectName ?? "Unfiled"),
                   "Project remains fully named to accessibility even when visually truncated")
        try expect(project.frame.width > 24 && project.frame.height >= 28 && project.frame.height <= 32,
                   "Project chip has a usable target and stays on one compact line")
        try expect(header.frame.insetBy(dx: -1, dy: -1).contains(project.frame),
                   "Project stays inside its metadata row at compact and expanded widths")
        let priority = capture.taskPlanning?.priority ?? .none
        if capture.isTask && priority != .none {
            let badge = try await find(fixture.hosting, id: "task-priority-tag-\(capture.id.uuidString)")
            try expect(abs(project.frame.midY - badge.frame.midY) <= 2,
                       "Priority and project share one row rather than adding card height")
            let gap = badge.frame.minX - project.frame.maxX
            try expect(gap >= -0.5 && gap <= 12,
                       "Priority follows the project immediately without overlap or flexible empty space; gap \(gap)")
            try expect(header.frame.insetBy(dx: -1, dy: -1).contains(badge.frame),
                       "Long project names reserve room for the complete priority label")
            try expect(header.frame.height <= 32,
                       "Project and priority do not inflate the compact card header")
        } else {
            try expect(!nodes(fixture.hosting).contains { $0.identifier == "task-priority-tag-\(capture.id.uuidString)" },
                       "No priority and ordinary captures add no inactive priority target")
            try expect(header.frame.height <= 32,
                       "Absent priority leaves no blank metadata row or placeholder")
        }
        if let name = capture.projectName, name.count > 100 {
            let intrinsic = (name as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)]).width
            try expect(intrinsic > project.frame.width,
                       "Long-project fixture exercises genuine horizontal compression while retaining its accessible name")
        }
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
    private static func menuItems(_ menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { [$0] + ($0.submenu.map(menuItems) ?? []) }
    }
    private static func nativeMenu(_ fixture: Fixture, id: String, containing title: String) async throws -> NSMenu {
        let target = try await find(fixture.hosting, id: id), tracking = MenuTracking(window: fixture.window)
        let center = NotificationCenter.default
        let began = center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { note in
            guard let menu = note.object as? NSMenu else { return }
            MainActor.assumeIsolated { tracking.began(menu) }
        }
        let ended = center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: nil) { note in
            guard let menu = note.object as? NSMenu else { return }
            MainActor.assumeIsolated { tracking.didEnd(menu) }
        }
        let timer = Timer(timeInterval: 0.02, repeats: true) { _ in MainActor.assumeIsolated { tracking.cancel() } }
        RunLoop.main.add(timer, forMode: .common); RunLoop.main.add(timer, forMode: .eventTracking)
        defer { timer.invalidate(); center.removeObserver(began); center.removeObserver(ended) }
        var accepted = target.actions.contains("AXShowMenu") ? target.showMenu() : false
        if !accepted && tracking.menus.isEmpty && target.actions.contains("AXPress") { accepted = target.press() }
        if !accepted && tracking.menus.isEmpty {
            let frame = target.interactionFrame
            try expect(fixture.window.frame.insetBy(dx: -1, dy: -1).contains(frame), "More tracking starts inside its own window")
            let point = fixture.window.convertPoint(fromScreen: NSPoint(x: frame.midX, y: frame.midY))
            let stamp = ProcessInfo.processInfo.systemUptime
            guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: stamp,
                windowNumber: fixture.window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1),
                  let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [], timestamp: stamp + 0.02,
                windowNumber: fixture.window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0) else {
                throw failure("Cannot create the owned More menu click")
            }
            NSApp.postEvent(up, atStart: true); fixture.window.sendEvent(down)
            if let remaining = NSApp.nextEvent(matching: .leftMouseUp, until: Date(), inMode: .default, dequeue: true) {
                try expect(remaining.windowNumber == fixture.window.windowNumber, "More release belongs only to its fixture")
                fixture.window.sendEvent(remaining)
            }
        }
        await settle(fixture.hosting)
        guard let menu = tracking.menus.first(where: { menuItems($0).contains { $0.title == title } }) else {
            throw failure("Actual More control must expose the native menu containing \(title)")
        }
        try expect(!tracking.timedOut && tracking.ended.contains(ObjectIdentifier(menu)), "More menu closes before item dispatch")
        return menu
    }
    private static func selectMenu(_ fixture: Fixture, id: String, title: String) async throws {
        let menu = try await nativeMenu(fixture, id: id, containing: title)
        guard let item = menuItems(menu).first(where: { $0.title == title }), let owner = item.menu else {
            throw failure("Native More menu is missing \(title)")
        }
        try expect(item.isEnabled && !item.isHidden && item.action != nil, "Native \(title) menu item remains actionable")
        owner.performActionForItem(at: owner.index(of: item)); await settle(fixture.hosting)
    }
    private static func assertGeometry(_ task: Capture, fixture: Fixture, width: CGFloat, factor: CGFloat) async throws {
        let ids = ["capture-task-status", "today-plan-task", "capture-more", "task-focus-duration", "task-focus-play",
                   "today-plan-day", "today-task-checklist"].map { $0 + "-" + task.id.uuidString }
        var controls: [TodayCardAX] = []
        for id in ids {
            let node = try await find(fixture.hosting, id: id), target = node.interactionFrame
            try expect(target.width >= 31.5 && target.height >= 31.5,
                       "\(id) keeps a 32-point native target at \(Int(width)) / \(Int(factor * 100))%: \(target)")
            try expect(target.origin.x.isFinite && target.origin.y.isFinite
                && fixture.window.frame.insetBy(dx: -1, dy: -1).contains(target), "\(id) is finite and fully inside its viewport")
            controls.append(node)
        }
        for index in controls.indices { for other in controls.indices where other > index {
            let overlap = controls[index].interactionFrame.intersection(controls[other].interactionFrame)
            try expect(overlap.isNull || overlap.width <= 1 || overlap.height <= 1,
                       "Visible task targets never overlap: \(ids[index]), \(ids[other]), \(overlap)")
        } }
        let title = controls[1]
        try expect(title.readableText.contains(task.title), "The clickable title retains its complete accessible text")
        try expect(title.interactionFrame.height <= 2 * WorkspaceZoomLayout(factor: factor).fontSize(16) * 1.6 + 4,
                   "Long task title is bounded to two readable lines")
        let visible = nodes(fixture.hosting)
        for id in ["today-move-up-", "today-move-down-", "capture-collapse-", "capture-trash-"].map({ $0 + task.id.uuidString })
            + [CaptureCopyButton.accessibilityIdentifier(for: [task])] {
            try expect(!visible.contains { $0.identifier == id }, "Secondary control \(id) is not duplicated on the card surface")
        }
        try expect(visible.filter { $0.identifier == ids[1] && $0.role == "AXButton" }.count == 1, "The title is the single visible Task-plan entry point")
        try await assertProjectPriority(task, fixture: fixture)
        let due = try await find(fixture.hosting, id: "today-task-deadline-\(task.id.uuidString)")
        let date = task.taskPlanning!.deadline!.formatted(date: .abbreviated, time: .omitted)
        try expect(due.readableText.contains("Due") && due.readableText.contains(date), "Due date retains its explicit deadline meaning")
        let plannedTime = try await find(fixture.hosting, id: "today-task-planned-time-\(task.id.uuidString)")
        let time = task.taskPlanning!.plannedTime!
        let plannedTimeSemantic = "Planned today at \(time)"
        try expect(plannedTime.label == plannedTimeSemantic || plannedTime.accessibleValue == plannedTimeSemantic,
                   "Planned-today time retains its complete semantic accessibility label: label=\(plannedTime.label), value=\(plannedTime.accessibleValue ?? "nil"), role=\(plannedTime.role), frame=\(plannedTime.frame), id=\(plannedTime.identifier ?? "nil")")
        let metadataOverlap = plannedTime.frame.intersection(due.frame)
        try expect(plannedTime.role == "AXStaticText" && due.role == "AXStaticText"
                   && plannedTime.identifier != due.identifier
                   && (metadataOverlap.isNull || metadataOverlap.width <= 1 || metadataOverlap.height <= 1),
                   "Planned time and deadline remain separate, non-overlapping metadata roles")
        try expect(plannedTime.frame.width > 0 && plannedTime.frame.height > 0
                   && fixture.window.frame.insetBy(dx: -1, dy: -1).contains(plannedTime.frame),
                   "Explicit planned-today time remains fully readable inside every viewport")
        try expect(title.label.contains(prettyDay(task.captureDay)) && title.label.contains(captureClock(task)),
                   "Open title retains the original receipt date and time in accessibility")
        let container = try await find(fixture.hosting, id: "today-task-card-\(task.id.uuidString)")
        let budget: CGFloat = factor <= 1 ? 245 : 330
        try expect(container.frame.height > 0 && container.frame.height <= budget,
                   "Populated task card stays within its \(Int(budget))-point density budget: \(container.frame)")
        geometry.append(["width": width, "zoom": factor, "card": NSStringFromRect(container.frame),
                         "title": NSStringFromRect(title.interactionFrame), "heightBudget": budget,
                         "controls": Dictionary(uniqueKeysWithValues: zip(ids, controls).map { ($0.0, NSStringFromRect($0.1.interactionFrame)) })])
    }


    private static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinTodayCards-\(UUID())", isDirectory: true)
        let suite = "DaBinTodayCards.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        let store = try CaptureStore(root: root, repairArchiveOnOpen: false)
        let previews = PreviewService(store: store, defaults: defaults)
        let auto = AutoCaptureService(settings: AutoCaptureSettings(defaults: defaults), input: InputService(store: store),
            pasteboardProvider: { fatalError("Today QA must not access the clipboard") }, sourceApplicationProvider: { nil })
        var copied: [CaptureClipboardPayload] = []
        let state = AppState(store: store, previews: previews,
            reminders: ReminderService(store: store, client: TodayCardReminderClient()), autoCapture: auto,
            captureClipboard: CaptureClipboardService(writer: { copied.append($0); return true }))
        defer {
            auto.shutdown(); previews.shutdown(); state.focusSessions.shutdown(); state.shutdownNotificationPresentation()
            store.cancelArchiveRepair(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root)
        }
        let evidence = ProcessInfo.processInfo.environment["DABIN_TODAY_CARD_QA_OUTPUT"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? root.appendingPathComponent("renders", isDirectory: true)
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        let today = CaptureCalendar.dayString(Date())
        let tomorrow = CaptureCalendar.dayString(Calendar.current.date(byAdding: .day, value: 1, to: Date())!)
        let deadline = Date().addingTimeInterval(7 * 24 * 60 * 60)
        let captured = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let task = try store.createTask(text: "Review the client’s final presentation and send the approved artwork", at: captured, planning: TaskPlanning(
            plannedDay: today, plannedTime: "09:30", deadline: deadline, priority: .high, effortMinutes: 25,
            checklist: [TaskChecklistItem(text: "Check the final captions"), TaskChecklistItem(text: "Approve the export")]))
        try store.setOrganization(task, pinned: false,
            projectName: "Fictional North Studio — International client launch, approvals, campaign deliverables and follow-up with the creative team")
        let receipt = (task.capturedAt, task.captureDay, task.originalText)
        let second = try store.createTask(text: "Prepare the project handover", at: captured, planning: TaskPlanning(plannedDay: today))
        try store.reorderTasks([task, second], on: today)

        for width in [CGFloat(320), 380, 760] { for factor in [CGFloat(0.75), 1, 2] { for dark in [false, true] {
            let card = TodayTaskCard(state: state, capture: task, reorderIndex: 0, reorderCount: 2)
                .padding(.horizontal, 14).environment(\.workspaceZoom, WorkspaceZoomLayout(factor: factor))
            let rendered = try await fixture(card, size: NSSize(width: width, height: 620), dark: dark)
            do {
                try snapshot(rendered.hosting, at: evidence.appendingPathComponent("today-card-\(Int(width))-zoom\(Int(factor * 100))-\(dark ? "dark" : "light")@2x.png"))
                try await assertGeometry(task, fixture: rendered, width: width, factor: factor)
                if width == 380 && factor == 1 {
                    let container = try await find(rendered.hosting, id: "today-task-card-\(task.id.uuidString)")
                    let nativeRect = rendered.hosting.convert(rendered.window.convertFromScreen(container.frame), from: nil)
                    guard let png = try bitmap(rendered.hosting, rect: nativeRect).representation(using: .png, properties: [:]) else {
                        throw failure("Cannot capture the actual native card bounds")
                    }
                    try png.write(to: evidence.appendingPathComponent("task-card-preview-380-\(dark ? "dark" : "light").png"), options: .atomic)
                }
                rendered.close()
            } catch { rendered.close(); throw error }
        } } }

        let unknown = try await fixture(TodayTaskCard(state: state, capture: second).padding(14)
            .environment(\.workspaceZoom, WorkspaceZoomLayout(factor: 2)), size: NSSize(width: 320, height: 380), dark: true)
        do {
            let duration = try await find(unknown.hosting, id: "task-focus-duration-\(second.id.uuidString)")
            try expect(duration.label == "Set focus time" && duration.role == "AXButton"
                && duration.object.responds(to: NSSelectorFromString("accessibilityPerformPress")),
                       "Unconfigured focus has one clearly labeled accessible native duration action")
            try expect(duration.interactionFrame.width >= 31.5 && duration.interactionFrame.height >= 31.5
                && unknown.window.frame.insetBy(dx: -1, dy: -1).contains(duration.interactionFrame),
                       "Set focus time remains reachable within the 320-point card at200%")
            try expect(!nodes(unknown.hosting).contains { $0.identifier == "task-focus-play-\(second.id.uuidString)" },
                       "Unconfigured task avoids a second play action for the same duration editor")
            try expect(second.taskPlanning?.effortMinutes == nil && second.taskPlanning?.focusSession == nil,
                       "Rendering Set focus time never configures or starts a focus session")
            try snapshot(unknown.hosting, at: evidence.appendingPathComponent("task-card-unconfigured-320-zoom200-dark@2x.png"))
            unknown.close()
        } catch { unknown.close(); throw error }

        let actions = try await fixture(TodayTaskCard(state: state, capture: task).padding(14), size: NSSize(width: 380, height: 640))
        defer { actions.close() }
        let moreID = "capture-more-\(task.id.uuidString)"
        let reschedule = try await find(actions.hosting, id: "today-plan-day-\(task.id.uuidString)")
        try expect(reschedule.label == "Tomorrow" && reschedule.press(), "Today’s task keeps direct one-click rescheduling")
        await settle(actions.hosting)
        try expect(task.taskPlanning?.plannedDay == tomorrow && task.taskPlanning?.plannedTime == "09:30", "Rescheduling preserves local work time")
        try expect(task.taskPlanning?.deadline == deadline && task.taskPlanning?.priority == .high, "Workday change preserves deadline and priority")
        let planned = try await find(actions.hosting, id: "today-task-planned-day-\(task.id.uuidString)")
        try expect(planned.readableText.contains("Planned") && !planned.readableText.contains("Due"), "Future workday stays distinct from a deadline")
        let bringBack = try await find(actions.hosting, id: "today-plan-day-\(task.id.uuidString)")
        try expect(bringBack.label == "Today" && bringBack.press(), "A future task can be brought back to Today directly")
        await settle(actions.hosting)
        try expect(task.taskPlanning?.plannedDay == today, "The Today action persists its workday")
        let title = try await find(actions.hosting, id: "today-plan-task-\(task.id.uuidString)")
        try expect(title.press(), "The actual title opens the task editor")
        await settle(actions.hosting)
        try expect(state.route == .detail && state.selectedCapture?.id == task.id && state.detailFocus == "task", "Title enters the selected Task pane")
        let checklist = try await find(actions.hosting, id: "today-task-checklist-\(task.id.uuidString)")
        try expect(checklist.press(), "Checklist progress supports direct native activation")
        await settle(actions.hosting)
        try expect(state.selectedCapture?.id == task.id && state.detailFocus == "task", "Checklist progress opens this same retained task editor")
        let archiveMenu = try await nativeMenu(actions, id: moreID, containing: "Copy task")
        let receiptText = "Captured \(captureReceiptText(task)) · Task"
        try expect(menuItems(archiveMenu).contains { $0.title == receiptText }, "More preserves the immutable capture receipt and Task category")
        guard let copy = menuItems(archiveMenu).first(where: { $0.title == "Copy task" }), let copyOwner = copy.menu else {
            throw failure("Copy task must be present in the actual native menu")
        }
        try expect(copy.isEnabled && !copy.isHidden && copy.action != nil, "Copy task stays actionable in More")
        copyOwner.performActionForItem(at: copyOwner.index(of: copy)); await settle(actions.hosting)
        try expect(copied.count == 1 && copied[0].items == [.text(task.originalText!)], "More copies the saved task through the private writer exactly once")
        let play = try await find(actions.hosting, id: "task-focus-play-\(task.id.uuidString)")
        try expect(play.readableText.contains("Start") && play.press(), "Idle task has a labeled native Start action")
        await settle(actions.hosting)
        try expect(task.taskPlanning?.focusSession?.isRunning == true && !task.isCompleted, "Starting focus keeps the task open")
        try await selectMenu(actions, id: moreID, title: "Minimize capture")
        try expect(task.isMinimized, "More preserves saved capture minimization")
        for prefix in ["today-plan-task", "capture-more", "capture-project-picker", "task-focus-duration", "task-focus-play"] {
            let node = try await find(actions.hosting, id: prefix + "-" + task.id.uuidString)
            try expect(node.interactionFrame.width > 0 && node.interactionFrame.height > 0, "Minimized running task retains \(prefix)")
        }
        let pause = try await find(actions.hosting, id: "task-focus-play-\(task.id.uuidString)")
        try expect(pause.readableText.contains("Pause") && pause.press(), "Minimized running task retains an explicit Pause action")
        await settle(actions.hosting)
        let paused = task.taskPlanning?.focusSession?.remainingSeconds ?? 0
        try expect(task.taskPlanning?.focusSession?.isRunning == false && paused > 0 && paused < 1500,
                   "Pausing the minimized task retains its remaining time without completing it")
        try await selectMenu(actions, id: moreID, title: "Expand capture")
        try expect(!task.isMinimized, "More expands this same saved task")
        let resume = try await find(actions.hosting, id: "task-focus-play-\(task.id.uuidString)")
        try expect(resume.readableText.contains("Resume") && resume.press(), "Expanded paused task exposes a labeled Resume action")
        await settle(actions.hosting)
        try expect(task.taskPlanning?.focusSession?.isRunning == true && !task.isCompleted,
                   "Resuming continues the saved focus without completing the task")
        try await selectMenu(actions, id: moreID, title: "Reset focus")
        try expect(task.taskPlanning?.focusSession?.remainingSeconds == 1500 && task.taskPlanning?.focusSession?.isRunning == false,
                   "Reset focus returns to the configured duration without completing the task")
        let complete = try await find(actions.hosting, id: "capture-task-status-\(task.id.uuidString)")
        try expect(complete.press(), "Native completion remains on the task header")
        await settle(actions.hosting)
        try expect(task.isCompleted && !nodes(actions.hosting).contains { $0.identifier == "today-plan-day-\(task.id.uuidString)" },
                   "Completed task removes its inapplicable rescheduling control")
        _ = try await find(actions.hosting, id: "today-plan-task-\(task.id.uuidString)")
        let reopen = try await find(actions.hosting, id: "capture-task-status-\(task.id.uuidString)")
        try expect(reopen.press(), "Completed task can be reopened through its original control")
        await settle(actions.hosting)
        try expect(!task.isCompleted, "Reopening restores its active task state")

        // Remove today's receipt duplicates from this fixture by anchoring these
        // synthetic tasks to yesterday; planning remains today's explicit date.
        let screen = try await fixture(TodayPlanningScreen(state: state), size: NSSize(width: 380, height: 1400))
        defer { screen.close() }
        state.showReminders(); try store.reorderTasks([task, second], on: today); await settle(screen.hosting)
        let firstMenu = try await nativeMenu(screen, id: moreID, containing: "Move down")
        let up = menuItems(firstMenu).first { $0.title == "Move up" }
        let down = menuItems(firstMenu).first { $0.title == "Move down" }
        try expect(up?.isEnabled == false && down?.isEnabled == true, "Native reorder menu preserves the first-task boundary")
        guard let down, let owner = down.menu else { throw failure("Native Move down item is missing") }
        owner.performActionForItem(at: owner.index(of: down)); await settle(screen.hosting)
        try expect(TaskPlanningPolicy.today(store.captures).map(\.id) == [second.id, task.id], "Actual Today More callback durably reorders tasks")
        try await selectMenu(screen, id: moreID, title: "Move up")
        try expect(TaskPlanningPolicy.today(store.captures).map(\.id) == [task.id, second.id], "Move up restores the actual Today order")
        let restored = try CaptureStore(root: root, repairArchiveOnOpen: false)
        try expect(TaskPlanningPolicy.today(restored.captures).map(\.id) == [task.id, second.id], "Native reorder survives archive reopening")
        restored.cancelArchiveRepair()
        try expect(task.capturedAt == receipt.0 && task.captureDay == receipt.1 && task.originalText == receipt.2,
                   "Every planning/focus/menu action preserves the immutable capture receipt and content")
        let followup = try store.capture(text: "Fictional review follow-up", at: captured)[0]
        try store.update(followup, comment: "Keep the original note", reminderAt: Date().addingTimeInterval(3600),
                         reminderTimeZoneID: TimeZone.current.identifier)
        try store.setMinimized(followup, minimized: true)
        let followupReceipt = (followup.capturedAt, followup.captureDay, followup.originalText)
        let followupFixture = try await fixture(TodayTaskCard(state: state, capture: followup).padding(14),
                                               size: NSSize(width: 320, height: 280), dark: true)
        defer { followupFixture.close() }
        let doneID = "today-follow-up-done-\(followup.id.uuidString)"
        let followupMore = "capture-more-\(followup.id.uuidString)"
        for id in [doneID, followupMore, "today-follow-up-open-\(followup.id.uuidString)"] {
            let node = try await find(followupFixture.hosting, id: id)
            try expect(node.interactionFrame.width >= 31.5 && node.interactionFrame.height >= 31.5
                && followupFixture.window.frame.insetBy(dx: -1, dy: -1).contains(node.interactionFrame),
                       "Minimized follow-up keeps its actual title, Done and More targets visible at320: \(id)")
        }
        try await selectMenu(followupFixture, id: followupMore, title: "Snooze until tomorrow")
        let snoozed = followup.reminderAt!
        let clock = Calendar.current.dateComponents([.hour, .minute], from: snoozed)
        try expect(CaptureCalendar.dayString(snoozed) == tomorrow && clock.hour == 9 && clock.minute == 0
            && followup.reminderTimeZoneID == TimeZone.current.identifier,
                   "Minimized follow-up More snoozes to tomorrow at9local without navigation")
        let done = try await find(followupFixture.hosting, id: doneID)
        try expect(done.press(), "Minimized follow-up Done invokes its native header action")
        await settle(followupFixture.hosting)
        try expect(followup.reminderAt == nil && !followup.isTask && !followup.isCompleted,
                   "Follow-up Done clears its reminder without converting or completing a task")
        try expect(followup.capturedAt == followupReceipt.0 && followup.captureDay == followupReceipt.1
            && followup.originalText == followupReceipt.2 && followup.comment == "Keep the original note",
                   "Follow-up snooze/Done preserve the original note, comment and receipt")
        try snapshot(followupFixture.hosting, at: evidence.appendingPathComponent("follow-up-minimized-320-dark@2x.png"))
        try JSONSerialization.data(withJSONObject: ["checks": checks, "fixtures": geometry,
            "scope": "Fictional own-process native task cards; private copy writer; bounded owned More menu tracking; no general clipboard, global input or notifications"], options: [.prettyPrinted, .sortedKeys])
            .write(to: evidence.appendingPathComponent("today-card-geometry.json"), options: .atomic)
        print("PASS: \(checks) modern task card checks; 320/380/760,75/100/200%,light/dark,compact hierarchy,focus/minimization,title/checklist,native More dispatch,receipt and reorder persistence. Evidence: \(evidence.path)")
    }
}
