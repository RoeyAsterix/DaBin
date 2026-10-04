import AppKit
import ApplicationServices
import Foundation
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
/// temporary archive; all windows are offscreen and non-key. No personal data,
/// clipboard, notification authorization, network or global pointer events.
@main @MainActor private final class TodayTaskCardTests: NSObject, NSApplicationDelegate {
    private static var checks = 0
    private var result: Int32 = 0
    private struct Fixture {
        let hosting: NSHostingView<AnyView>
        let window: NSWindow
        func close() { window.orderOut(nil); window.contentView = nil; window.close() }
    }

    static func main() {
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


    private static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinTodayCards-\(UUID())", isDirectory: true)
        let suite = "DaBinTodayCards.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root)
        let autoCapture = AutoCaptureService(settings: AutoCaptureSettings(defaults: defaults), input: InputService(store: store),
            pasteboardProvider: { fatalError("Today QA must not access the clipboard") }, sourceApplicationProvider: { nil })
        defer { autoCapture.shutdown() }
        let state = AppState(store: store, previews: PreviewService(store: store, defaults: defaults),
            reminders: ReminderService(store: store, client: TodayCardReminderClient()), autoCapture: autoCapture)
        let evidence = ProcessInfo.processInfo.environment["DABIN_TODAY_CARD_QA_OUTPUT"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? root.appendingPathComponent("renders", isDirectory: true)
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        let today = CaptureCalendar.dayString(Date())
        let tomorrow = CaptureCalendar.dayString(Calendar.current.date(byAdding: .day, value: 1, to: Date())!)
        let deadline = Date().addingTimeInterval(7 * 24 * 60 * 60)
        let task = try store.createTask(text: "Review the client’s final presentation and send the approved artwork", planning: TaskPlanning(
            plannedDay: today, deadline: deadline, priority: .high, effortMinutes: 25,
            checklist: [TaskChecklistItem(text: "Check the final captions")]))
        try store.setOrganization(task, pinned: false,
            projectName: "Fictional North Studio — International client launch, approvals and follow-up")
        let receipt = (task.capturedAt, task.captureDay, task.originalText)
        let second = try store.createTask(text: "Prepare the project handover", planning: TaskPlanning(plannedDay: today))
        try store.reorderTasks([task, second], on: today)

        for width in [CGFloat(380), CGFloat(760)] {
            for dark in [false, true] {
                let card = TodayTaskCard(state: state, capture: task, reorderIndex: 0, reorderCount: 2)
                    .padding(.horizontal, 14)
                let rendered = try await fixture(card, size: NSSize(width: width, height: 620), dark: dark)
                defer { rendered.close() }
                let ids = ["today-plan-day", "today-plan-task", "today-move-up", "today-move-down", "capture-collapse", "capture-more"]
                var actions: [TodayCardAX] = []
                for prefix in ids {
                    let node = try await find(rendered.hosting, id: "\(prefix)-\(task.id.uuidString)")
                    let target = node.interactionFrame
                    try expect(target.width >= 28 && target.height >= 28,
                        "\(prefix) retains at least a 28-point keyboard and pointer target at \(Int(width)): \(target), AX=\(node.frame)")
                    try expect(rendered.window.frame.insetBy(dx: -1, dy: -1).contains(target),
                        "\(prefix) remains inside the \(Int(width))-point card")
                    actions.append(node)
                }
                let row = actions.map { $0.interactionFrame.midY }
                try expect((row.max()! - row.min()!) <= 3,
                    "Planning, reordering, collapse and More share exactly one row at \(Int(width))")
                for pair in zip(actions, actions.dropFirst()) {
                    try expect(pair.0.interactionFrame.maxX <= pair.1.interactionFrame.minX + 2,
                        "Adjacent Today footer controls do not overlap at \(Int(width))")
                }
                let priority = try await find(rendered.hosting, id: "task-priority-tag-\(task.id.uuidString)")
                let project = try await find(rendered.hosting, id: "capture-project-picker-\(task.id.uuidString)")
                try expect(priority.label == "High priority", "Priority is understandable without color")
                try expect(abs(priority.frame.midY - project.frame.midY) <= 4
                    && project.frame.maxX <= priority.frame.minX + 1,
                    "Priority is immediately beside the project on the same row")
                let deadlineNode = try await find(rendered.hosting, id: "today-task-deadline-\(task.id.uuidString)")
                let displayedDeadline = deadline.formatted(date: .abbreviated, time: .omitted)
                try expect(deadlineNode.readableText.contains("Due") && deadlineNode.readableText.contains(displayedDeadline),
                    "The workday and task deadline stay clearly distinguished: label=\(deadlineNode.label), value=\(deadlineNode.accessibleValue ?? "nil"), content=\(deadlineNode.readableText), expected=Due \(displayedDeadline)")
                try expect(!nodes(rendered.hosting).contains { $0.label == "TASK" },
                    "A separate redundant TASK heading does not add vertical space")
                let container = try await find(rendered.hosting, id: "today-task-card-\(task.id.uuidString)")
                try expect(container.frame.height < 340,
                    "A long-title task with priority, deadline, focus and all footer actions remains compact")
                try snapshot(rendered.hosting, at: evidence.appendingPathComponent("today-card-\(Int(width))-\(dark ? "dark" : "light").png"))
            }
        }

        let actions = try await fixture(TodayTaskCard(state: state, capture: task).padding(14), size: NSSize(width: 380, height: 640))
        defer { actions.close() }
        let reschedule = try await find(actions.hosting, id: "today-plan-day-\(task.id.uuidString)")
        try expect(reschedule.label == "Tomorrow" && reschedule.press(), "Today’s task has an accessible move-to-tomorrow action")
        await settle(actions.hosting)
        try expect(task.taskPlanning?.plannedDay == tomorrow, "The footer action saves tomorrow as the workday")
        try expect(task.taskPlanning?.deadline == deadline && task.taskPlanning?.priority == .high,
            "Rescheduling preserves the real deadline and priority")
        try expect(task.capturedAt == receipt.0 && task.captureDay == receipt.1 && task.originalText == receipt.2,
            "Rescheduling preserves the original capture receipt and content")
        let bringBack = try await find(actions.hosting, id: "today-plan-day-\(task.id.uuidString)")
        try expect(bringBack.label == "Today" && bringBack.press(), "Tomorrow’s card can be brought back to Today with one action")
        await settle(actions.hosting)
        try expect(task.taskPlanning?.plannedDay == today, "The Today shortcut persists its planned workday")
        let plan = try await find(actions.hosting, id: "today-plan-task-\(task.id.uuidString)")
        try expect(plan.press(), "The Plan action supports native accessibility activation")
        await settle(actions.hosting)
        try expect(state.selectedCapture?.id == task.id && state.selectedDraft != nil,
            "Plan opens the existing capture’s retained task editor")
        let collapse = try await find(actions.hosting, id: "capture-collapse-\(task.id.uuidString)")
        try expect(collapse.press(), "Collapse works from the shared planning row")
        await settle(actions.hosting)
        try expect(task.isMinimized, "Collapsing keeps the capture minimized")
        try expect(nodes(actions.hosting).contains { $0.identifier == "today-plan-task-\(task.id.uuidString)" },
            "Plan stays available on a minimized task")
        let expand = try await find(actions.hosting, id: "capture-collapse-\(task.id.uuidString)")
        try expect(expand.press(), "The same control expands the minimized task")
        await settle(actions.hosting)
        let complete = try await find(actions.hosting, id: "capture-task-status-\(task.id.uuidString)")
        try expect(complete.press(), "The native task completion control remains available")
        await settle(actions.hosting)
        try expect(task.isCompleted && !nodes(actions.hosting).contains { $0.identifier == "today-plan-task-\(task.id.uuidString)" },
            "Completion updates the card and removes inapplicable scheduling actions")
        let reopen = try await find(actions.hosting, id: "capture-task-status-\(task.id.uuidString)")
        try expect(reopen.press(), "A completed task can be reopened from its card")
        await settle(actions.hosting)
        try expect(!task.isCompleted, "Reopening restores the task’s active state")

        let screen = try await fixture(TodayPlanningScreen(state: state), size: NSSize(width: 380, height: 860))
        defer { screen.close() }
        try store.reorderTasks([task, second], on: today)
        await settle(screen.hosting)
        let moveDown = try await find(screen.hosting, id: "today-move-down-\(task.id.uuidString)")
        try expect(moveDown.press(), "Actual Today list exposes accessible reordering")
        await settle(screen.hosting)
        try expect(TaskPlanningPolicy.today(store.captures).map(\.id) == [second.id, task.id],
            "Today reordering persists the intended order through its production callback")
        let reopenedStore = try CaptureStore(root: root)
        let savedTask = reopenedStore.captures.first { $0.id == task.id }
        try expect(savedTask?.taskPlanning?.plannedDay == today && savedTask?.taskPlanning?.deadline == deadline
            && savedTask?.taskPlanning?.priority == .high && savedTask?.isCompleted == false,
            "Planning, priority and completion survive archive reopening")
        print("PASS: \(checks) Today task card checks; same-row planning/controls at 380/760 in light/dark, priority beside project, real rescheduling/completion/reorder and persistence. Evidence: \(evidence.path)")
    }
}
