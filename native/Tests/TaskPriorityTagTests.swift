import AppKit
import ApplicationServices
import Foundation
import SwiftUI

@MainActor private final class PriorityTagReminderClient: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .undetermined }
    func requestAuthorization() async throws -> Bool { false }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}

@MainActor private final class PriorityTagFixtureWindow: NSWindow {
    override var backingScaleFactor: CGFloat { 2 }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// SwiftUI virtual nodes expose public AppKit accessibility selectors without
/// always conforming to the whole NSAccessibility protocol. Inspect only the
/// hierarchy retained by this test's own isolated hosting view.
@MainActor private struct PriorityTagAX {
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
    var accessibleValue: String? { (value("accessibilityValue") as? String) ?? (attribute("AXValue") as? String) }
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
            if let values = value(name) as? [Any] { result += values }
        }
        if let values = attribute("AXChildren") as? [Any] { result += values }
        if let view = object as? NSView { result += view.subviews }
        return result
    }
}

@MainActor private struct PriorityTagExplorerFixture: View {
    @ObservedObject var state: AppState
    let capture: Capture
    @FocusState private var focus: UUID?
    var body: some View {
        ExplorerCaptureRow(state: state, workspace: state.workspace, capture: capture, focus: $focus) {
            state.workspace.selectedCaptureID = capture.id
        }
    }
}

/// Real production priority choices, detail save and mounted cards. Fictional
/// temporary archive; all windows are offscreen and non-key. No personal data,
/// clipboard, notification authorization, network or global pointer events.
@main @MainActor private final class TaskPriorityTagTests: NSObject, NSApplicationDelegate {
    private static var checks = 0
    private var result: Int32 = 0
    private struct Fixture {
        let hosting: NSHostingView<AnyView>
        let window: NSWindow
        func close() { window.orderOut(nil); window.contentView = nil; window.close() }
    }

    static func main() {
        let app = NSApplication.shared
        let delegate = TaskPriorityTagTests()
        app.setActivationPolicy(.accessory); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        exit(delegate.result)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await Self.run() }
            catch { result = 1; fputs("Task priority tag QA failed: \(error)\n", stderr) }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "TaskPriorityTagTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        guard try condition() else { throw failure(message) }
    }
    private static func nodes(_ view: NSView) -> [PriorityTagAX] {
        var seen = Set<ObjectIdentifier>(), result: [PriorityTagAX] = []
        func visit(_ candidate: Any, depth: Int) {
            guard depth < 50, let object = candidate as? NSObject,
                  seen.insert(ObjectIdentifier(object)).inserted else { return }
            let node = PriorityTagAX(object: object); result.append(node)
            node.children.forEach { visit($0, depth: depth + 1) }
        }
        visit(view, depth: 0)
        NSAccessibility.unignoredChildren(from: [view]).forEach { visit($0, depth: 0) }
        return result
    }
    private static func settle(_ view: NSView) async {
        for _ in 0..<5 { view.layoutSubtreeIfNeeded(); try? await Task.sleep(for: .milliseconds(35)) }
    }
    private static func find(_ view: NSView, id: String) async throws -> PriorityTagAX {
        for _ in 0..<6 {
            if let node = nodes(view).first(where: { $0.identifier == id }) { return node }
            await settle(view)
        }
        throw failure("Missing task priority control \(id): \(nodes(view).map { $0.identifier ?? $0.label }.joined(separator: "; "))")
    }
    private static func fixture<V: View>(_ root: V, size: NSSize, dark: Bool = false) async throws -> Fixture {
        let content = root.frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(Palette.background).environment(\.displayScale, 2)
            .environment(\.daBinTooltipsEnabled, false).preferredColorScheme(dark ? .dark : .light)
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
        let hosting = NSHostingView(rootView: AnyView(content))
        hosting.frame = NSRect(origin: .zero, size: size); hosting.wantsLayer = true
        let window = PriorityTagFixtureWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
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
        try expect(window.frame.maxX < 0 && !window.isKeyWindow, "Priority fixtures remain offscreen and non-key")
        return Fixture(hosting: hosting, window: window)
    }
    private static func bitmap(_ view: NSView, rect: NSRect) throws -> NSBitmapImageRep {
        let bounds = rect.intersection(view.bounds).integral
        guard bounds.width > 0, bounds.height > 0,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2),
                pixelsHigh: Int(bounds.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw failure("Cannot allocate priority evidence bitmap: \(rect)")
        }
        bitmap.size = bounds.size; view.cacheDisplay(in: bounds, to: bitmap)
        return bitmap
    }
    private static func snapshot(_ view: NSView, at url: URL) throws {
        guard let png = try bitmap(view, rect: view.bounds).representation(using: .png, properties: [:]) else {
            throw failure("Cannot encode task priority PNG")
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

    private static func assertBadge(_ capture: Capture, priority: TaskPriority, fixture: Fixture,
                                    cardID: String? = nil, checkColor: Bool = false) async throws {
        let badge = try await find(fixture.hosting, id: "task-priority-tag-\(capture.id.uuidString)")
        try expect(badge.label == "\(priority.title) priority", "Task badge explains its level without decoding color or an icon")
        try expect(badge.frame.width > 0 && badge.frame.height > 0
            && fixture.window.frame.insetBy(dx: -1, dy: -1).contains(badge.frame), "Task badge is rendered inside its viewport")
        if let cardID {
            let card = try await find(fixture.hosting, id: cardID)
            try expect(card.frame.insetBy(dx: -1, dy: -1).contains(badge.frame), "Priority is shown on the task's own card")
        }
        let glyphWidth = (priority.title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold)]).width
        try expect(badge.frame.width >= glyphWidth + 10 && badge.frame.height >= 12,
                   "Complete \(priority.title) label has room for its rendered glyphs and pill padding")
        if checkColor {
            let rect = fixture.hosting.convert(fixture.window.convertFromScreen(badge.frame), from: nil)
            let image = try bitmap(fixture.hosting, rect: rect)
            var coloredPixels = 0
            for y in 0..<image.pixelsHigh {
                for x in 0..<image.pixelsWide {
                    guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    let r = color.redComponent, g = color.greenComponent, b = color.blueComponent
                    let matches: Bool
                    switch priority {
                    case .low: matches = g > r + 0.025 && g > b + 0.025
                    case .medium: matches = r > b + 0.06 && g > b + 0.04 && r >= g
                    case .high: matches = r > g + 0.06 && r > b + 0.06
                    case .none: matches = false
                    }
                    if matches { coloredPixels += 1 }
                }
            }
            try expect(coloredPixels >= 40, "Actual \(priority.title) badge pixels have the expected green/amber/red hue")
        }
    }

    private static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinPriorityTagQA-\(UUID().uuidString)")
        let suite = "DaBinPriorityTagQA.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root)
        let autoCapture = AutoCaptureService(settings: AutoCaptureSettings(defaults: defaults), input: InputService(store: store),
            pasteboardProvider: { fatalError("Priority QA must not access the clipboard") }, sourceApplicationProvider: { nil })
        defer { autoCapture.shutdown() }
        let state = AppState(store: store, previews: PreviewService(store: store, defaults: defaults),
            reminders: ReminderService(store: store, client: PriorityTagReminderClient()), autoCapture: autoCapture)
        let evidence: URL
        if let argument = CommandLine.arguments.dropFirst().first { evidence = URL(fileURLWithPath: argument, isDirectory: true) }
        else {
            evidence = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("build/qa/task-priority-tags", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        let task = try store.createTask(text: "Fictional priority editing example", planning: TaskPlanning(
            plannedDay: "2026-10-03", deadline: ISO8601DateFormatter().date(from: "2026-11-02T17:00:00Z"),
            effortMinutes: 45, checklist: [TaskChecklistItem(text: "Keep this original next step")]))
        let receipt = (task.capturedAt, task.captureDay, task.originalText, task.title)
        state.openCapture(task.id)
        guard let draft = state.selectedDraft else { throw failure("Task detail draft was not created") }
        let originalPlan = draft.planning
        let detail = try await fixture(DetailScreen(state: state, capture: task, draft: draft), size: NSSize(width: 380, height: 1_100))
        defer { detail.close() }
        let mountedCard = try await fixture(CaptureRow(state: state, capture: task, featured: false), size: NSSize(width: 380, height: 480))
        defer { mountedCard.close() }
        try expect(!nodes(mountedCard.hosting).contains { $0.identifier == "task-priority-tag-\(task.id.uuidString)" },
                   "A task with no priority begins without a colored badge")

        for priority in TaskPriority.allCases {
            let choice = try await find(detail.hosting, id: "task-priority-choice-\(priority.rawValue)")
            let label = priority == .none ? "No priority" : "\(priority.title) priority"
            try expect(choice.label == label, "Priority choices use readable level names")
            try expect(choice.frame.width > 0 && choice.frame.height >= 30
                && detail.window.frame.insetBy(dx: -1, dy: -1).contains(choice.frame), "All four priority choices fit the 380-point editor")
            let textWidth = (priority.title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold)]).width
            try expect(choice.frame.width > textWidth + 10, "Priority choice labels have room to render completely")
        }
        // Press the actual production SwiftUI buttons, then the actual detail
        // save button. Keep the card mounted throughout, so this proves the
        // observed badge changes without replacing its view or capture object.
        for priority in [TaskPriority.low, .medium, .high, .none] {
            let choice = try await find(detail.hosting, id: "task-priority-choice-\(priority.rawValue)")
            try expect(choice.press(), "\(priority.title) dispatches its real priority binding action")
            await settle(detail.hosting)
            try expect(draft.planning.priority == priority && draft.hasChanges,
                       "The editor updates the retained task draft")
            let save = try await find(detail.hosting, id: "detail-save")
            try expect(save.press(), "Save changes dispatches the production task commit action")
            await settle(detail.hosting); await settle(mountedCard.hosting)
            try expect(task.taskPlanning?.priority == priority && !draft.hasChanges && !draft.hasError,
                       "Selected priority commits and clears the edited draft")
            let reloaded = try CaptureStore(root: root)
            try expect(reloaded.captures.first(where: { $0.id == task.id })?.taskPlanning?.priority == priority,
                       "Task priority survives reopening the isolated archive")
            if priority == .none {
                try expect(!nodes(mountedCard.hosting).contains { $0.identifier == "task-priority-tag-\(task.id.uuidString)" },
                           "No priority removes the mounted card badge")
            } else { try await assertBadge(task, priority: priority, fixture: mountedCard, checkColor: true) }
            try expect(task.capturedAt == receipt.0 && task.captureDay == receipt.1 && task.originalText == receipt.2 && task.title == receipt.3,
                       "Changing priority preserves the original capture receipt and task text")
            try expect(task.taskPlanning?.deadline == originalPlan.deadline && task.taskPlanning?.plannedDay == originalPlan.plannedDay
                && task.taskPlanning?.effortMinutes == originalPlan.effortMinutes && task.taskPlanning?.checklist == originalPlan.checklist,
                       "Priority edits preserve scheduling, effort and checklist")
            try snapshot(detail.hosting, at: evidence.appendingPathComponent("editor-\(priority.rawValue)-380-light.png"))
        }

        let shortProject = "Fictional Atlas"
        let longProject = "Fictional international client — " + String(repeating: "Design 日本語 ", count: 12)
        try state.workspace.createProject(name: shortProject, colorHex: "198F91")
        try state.workspace.createProject(name: longProject, colorHex: "7568D8")
        var captures: [Capture] = []
        for priority in [TaskPriority.low, .medium, .high, .none] {
            let item = try store.createTask(text: "\(priority == .none ? "Unprioritized" : priority.title) fictional task with a title that wraps in a compact card",
                                           planning: TaskPlanning(priority: priority))
            item.isMinimized = priority == .low
            let project = priority == .medium || priority == .none ? longProject : shortProject
            try store.setOrganization(item, pinned: false, projectName: project)
            captures.append(item)
        }
        let plain = try store.capture(text: "Fictional saved note, not a task")[0]
        captures.append(plain)
        for width in [CGFloat(380), CGFloat(760)] {
            for dark in [false, true] {
                for explorer in [false, true] {
                    let cards = VStack(alignment: .leading, spacing: 8) {
                        ForEach(captures) { capture in
                            Group {
                                if explorer { PriorityTagExplorerFixture(state: state, capture: capture) }
                                else { CaptureRow(state: state, capture: capture, featured: false) }
                            }.fixedSize(horizontal: false, vertical: true)
                                .accessibilityElement(children: .contain)
                                .accessibilityIdentifier("priority-fixture-card-\(capture.id.uuidString)")
                        }
                    }.padding(12)
                    let rendered = try await fixture(cards, size: NSSize(width: width, height: 1_800), dark: dark)
                    defer { rendered.close() }
                    for capture in captures {
                        try await assertProjectPriority(capture, fixture: rendered)
                        let priority = capture.taskPlanning?.priority ?? .none
                        if capture.isTask && priority != .none {
                            try await assertBadge(capture, priority: priority, fixture: rendered,
                                cardID: "priority-fixture-card-\(capture.id.uuidString)", checkColor: true)
                        } else {
                            try expect(!nodes(rendered.hosting).contains { $0.identifier == "task-priority-tag-\(capture.id.uuidString)" },
                                       "Unprioritized tasks and ordinary notes have no priority tag")
                        }
                    }
                    let name = "\(explorer ? "explorer" : "task-cards")-\(Int(width))-\(dark ? "dark" : "light").png"
                    try snapshot(rendered.hosting, at: evidence.appendingPathComponent(name))
                }
            }
        }
        print("PASS: \(checks) task priority tag checks; real choices/save/persistence, adjacent project/priority geometry and green–amber–red cards at 380/760 in light/dark; fictional local archive only. PNG evidence: \(evidence.path)")
    }
}
