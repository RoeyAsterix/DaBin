import AppKit
import ApplicationServices
import Darwin
import Foundation
import SwiftUI

// Also permits verifying these cards against a retained, source-bound QA
// module while unrelated work is actively changing the shared source tree.
#if canImport(DaBinTestCore)
@testable import DaBinTestCore
#endif

@MainActor private final class ProjectCardFixtureWindow: NSWindow {
    override var backingScaleFactor: CGFloat { 2 }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor private final class ProjectCardNotifications: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .undetermined }
    func requestAuthorization() async throws -> Bool { false }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}

@MainActor private final class ProjectCardActions {
    var opened = 0
    var selected = 0
    var detailed = 0
}

@MainActor private struct ProjectCardFixture: View {
    let state: AppState
    let item: ProjectWorkspaceItem
    let compact: Bool
    let actions: ProjectCardActions
    @State private var selected = false
    @FocusState private var focus: String?

    var body: some View {
        ProjectWorkspaceCard(state: state, item: item, selected: selected, compact: compact,
            color: ProjectColorChoice.color(for: "7568D8"), focus: $focus,
            open: { actions.opened += 1 },
            select: { selected.toggle(); actions.selected += 1 },
            details: { actions.detailed += 1 }, makeTask: {}, earlier: {}, later: {},
            canReorder: false, drag: { [] })
    }
}

@MainActor private struct ProjectCardComparison: View {
    let state: AppState
    let items: [ProjectWorkspaceItem]
    let compact: Bool
    let actions: ProjectCardActions

    var body: some View {
        let columns = compact ? 1 : min(3, items.count)
        let rows = (items.count + columns - 1) / columns
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(alignment: .top, spacing: 12) {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = row * columns + column
                        if index < items.count {
                            ProjectCardFixture(state: state, item: items[index], compact: compact, actions: actions)
                                .frame(width: compact ? 296 : 320)
                        }
                    }
                }
            }
        }.padding(12).background(Palette.background)
    }
}

@MainActor private struct ProjectCardAX {
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
    var valueText: String { (value("accessibilityValue") as? String) ?? (attribute("AXValue") as? String) ?? "" }
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

/// Production cards with fictional local data, offscreen non-key windows and
/// injected open/clipboard/notification behavior. Never reads the user's archive.
@main @MainActor private final class ProjectWorkspaceCardTests: NSObject, NSApplicationDelegate {
    private static var checks = 0
    private var result: Int32 = 0

    static func main() {
        let app = NSApplication.shared
        let delegate = ProjectWorkspaceCardTests()
        app.setActivationPolicy(.accessory); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        exit(delegate.result)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await Self.run() }
            catch { result = 1; fputs("Project card QA failed: \(error)\n", stderr) }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "ProjectWorkspaceCardTests", code: checks, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        guard try condition() else { throw failure(message) }
    }
    private static func settle(_ view: NSView) async throws {
        let started = ContinuousClock.now
        for _ in 0..<6 { view.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(35)) }
        try expect(ContinuousClock.now - started < .seconds(4), "Card updates leave the run loop responsive")
    }
    private static func nodes(_ view: NSView) -> [ProjectCardAX] {
        var result: [ProjectCardAX] = [], seen = Set<ObjectIdentifier>()
        func visit(_ candidate: Any, depth: Int) {
            guard depth < 45, let object = candidate as? NSObject,
                  seen.insert(ObjectIdentifier(object)).inserted else { return }
            let node = ProjectCardAX(object: object); result.append(node)
            node.children.forEach { visit($0, depth: depth + 1) }
        }
        visit(view, depth: 0)
        NSAccessibility.unignoredChildren(from: [view]).forEach { visit($0, depth: 0) }
        return result
    }
    private static func find(_ id: String, in view: NSView) async throws -> ProjectCardAX {
        for _ in 0..<6 {
            if let node = nodes(view).first(where: { $0.identifier == id && $0.frame.width > 0 && $0.frame.height > 0 }) { return node }
            try await settle(view)
        }
        throw failure("Missing visible card control \(id): \(nodes(view).map { $0.identifier ?? $0.label }.joined(separator: "; "))")
    }

    private static func bitmap(_ view: NSView, rect: NSRect? = nil) throws -> NSBitmapImageRep {
        let bounds = (rect ?? view.bounds).integral
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2),
            pixelsHigh: Int(bounds.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw failure("Could not allocate fictional card image")
        }
        bitmap.size = bounds.size; view.cacheDisplay(in: bounds, to: bitmap)
        return bitmap
    }

    private static func saveFixture(_ view: NSView, name: String, output: URL) throws {
        guard let png = try bitmap(view).representation(using: .png, properties: [:]) else {
            throw failure("Could not encode fictional card image")
        }
        let destination = output.appendingPathComponent(name + "@2x.png")
        try png.write(to: destination, options: .atomic)
        print("FIXTURE: \(destination.path)")
    }

    private static func syntheticPNG() throws -> Data {
        guard let context = CGContext(data: nil, width: 600, height: 400, bitsPerComponent: 8, bytesPerRow: 2_400,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw failure("Could not allocate synthetic thumbnail")
        }
        context.setFillColor(CGColor(red: 0.10, green: 0.70, blue: 0.84, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
        context.setFillColor(CGColor(red: 0.97, green: 0.65, blue: 0.12, alpha: 1))
        context.fill(CGRect(x: 80, y: 60, width: 200, height: 250))
        guard let image = context.makeImage(), let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw failure("Could not encode synthetic thumbnail")
        }
        return data
    }

    private static func checkImagePreview(_ item: ProjectWorkspaceItem, in view: NSView) async throws {
        let preview = try await find("project-preview-" + item.id, in: view)
        guard let window = view.window else { throw failure("Image preview needs its isolated window") }
        let rect = view.convert(window.convertFromScreen(preview.frame), from: nil).intersection(view.bounds)
        try expect(rect.width > 0 && rect.height > 0, "Synthetic image preview remains on the card")
        var cyan = 0, orange = 0
        for attempt in 0..<6 {
            let image = try bitmap(view, rect: rect)
            cyan = 0; orange = 0
            for y in stride(from: 0, to: image.pixelsHigh, by: 4) {
                for x in stride(from: 0, to: image.pixelsWide, by: 4) {
                    guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    let r = color.redComponent, g = color.greenComponent, b = color.blueComponent
                    if r < 0.30 && g > 0.55 && b > 0.65 { cyan += 1 }
                    if r > 0.80 && g > 0.45 && g < 0.80 && b < 0.30 { orange += 1 }
                }
            }
            if cyan > 30 && orange > 15 { break }
            if attempt < 5 { try await settle(view) }
        }
        try expect(cyan > 30 && orange > 15,
                   "Real saved image colors remain visible, including for image tasks (cyan \(cyan), orange \(orange))")
    }

    private static func withFixture(state: AppState, items: [ProjectWorkspaceItem], compact: Bool,
                                    dark: Bool, actions: ProjectCardActions,
                                    operation: (NSView) async throws -> Void) async throws {
        let columns = compact ? 1 : min(3, items.count)
        let rows = (items.count + columns - 1) / columns
        let size = CGSize(width: compact ? 320 : CGFloat(columns * 320 + (columns - 1) * 12 + 24),
                          height: CGFloat(rows * (compact ? 96 : 284) + (rows - 1) * 12 + 24))
        let root = ProjectCardComparison(state: state, items: items, compact: compact, actions: actions)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .environment(\.daBinTooltipsEnabled, false).environment(\.displayScale, 2)
            .preferredColorScheme(dark ? .dark : .light)
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: size); hosting.sizingOptions = []
        let window = ProjectCardFixtureWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.appearance = appearance; hosting.appearance = appearance; window.contentView = hosting
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        window.orderFront(nil)
        try await settle(hosting)
        let activation = await Task.detached {
            let process = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            AXUIElementSetMessagingTimeout(process, 3)
            var windows: CFTypeRef?
            return AXUIElementCopyAttributeValue(process, kAXWindowsAttribute as CFString, &windows)
        }.value
        try expect(activation == .success && window.frame.maxX < 0 && !window.isKeyWindow && !window.isMainWindow,
                   "Only own-process offscreen, non-key card fixtures initialize")
        try await settle(hosting)
        try await operation(hosting)
    }

    private static func checkRoles(_ items: [ProjectWorkspaceItem], in view: NSView, compact: Bool) async throws {
        guard let window = view.window else { throw failure("Card role needs its fixture window") }
        let bounds = window.convertToScreen(view.bounds).insetBy(dx: -1, dy: -1)
        for item in items {
            let badge = try await find("project-kind-" + item.id, in: view)
            let role = ProjectCardRole(item: item)
            try expect(badge.label == role.title, "Accessible role is explicit: \(role.title), not color alone")
            let status = item.capture?.isTask == true ? (item.capture?.isCompleted == true ? "Completed" : "To do") : ""
            // SwiftUI static labels may omit AXValue or repeat the label. The
            // preview and actionable completion control must expose task state
            // independently below; do not require a native control-only value.
            try expect(badge.valueText.isEmpty || badge.valueText == status || badge.valueText == role.title,
                       "Role badge never exposes a conflicting state: '\(badge.valueText)' for \(role.title)")
            try expect(bounds.contains(badge.frame), "Role badge fits \(compact ? "320-point compact" : "grid") fixture")
            let select = try await find("project-select-" + item.id, in: view)
            try expect(!badge.frame.intersects(select.frame), "Role badge does not overlap the independent selection target")
            let preview = try await find("project-preview-" + item.id, in: view)
            if compact {
                try expect((70...110).contains(preview.frame.height), "Compact cards retain a usable preview target")
                if let capture = item.capture, capture.isTask {
                    let textTask = [CaptureKind.text, .task].contains(capture.kind)
                    try expect(abs(preview.frame.width - (textTask ? 36 : 64)) < 2,
                               "Compact text tasks reserve only a 36-point icon; saved media retains its 64-point preview")
                }
            } else if item.capture?.isTask == true {
                try expect(preview.frame.height > 12 && preview.frame.height < 220,
                           "Task content sizes to its text, checklist, or media rather than a 214-point empty tile")
            } else {
                try expect(preview.frame.height >= 200, "Non-task notes and captures retain their large preview geometry")
            }
            if item.capture?.isTask == true {
                try expect(preview.label.hasSuffix(", completed") == (item.capture?.isCompleted == true),
                           "Task preview announces completion without relying on color or an optional AXValue")
                let toggle = try await find("project-task-toggle-" + item.id, in: view)
                try expect(toggle.label == (item.capture?.isCompleted == true ? "Reopen task" : "Complete task"),
                           "Only tasks have the correct actionable completion state")
                if let capture = item.capture, let taskPriority = capture.taskPlanning?.priority,
                   taskPriority != .none {
                    let project = try await find("project-task-project-" + item.id, in: view)
                    let priority = try await find("task-priority-tag-" + capture.id.uuidString, in: view)
                    try expect(abs(project.frame.midY - priority.frame.midY) <= 2,
                               "Task priority shares the project-name line")
                    try expect(!project.frame.intersects(priority.frame) && bounds.contains(priority.frame),
                               "Project and priority stay separate and fully inside the card at compact widths")
                    if compact, [CaptureKind.text, .task].contains(capture.kind) {
                        let details = try await find("project-details-" + item.id, in: view)
                        let frames = "project=\(project.frame), priority=\(priority.frame), title=\(details.frame)"
                        try expect(project.frame.width >= 60,
                                   "Compact project name retains readable room beside even the longer Medium priority label: \(frames)")
                        try expect(project.frame.width + priority.frame.width >= details.frame.width - 18,
                                   "Compact project and priority use the available title width instead of reserving dead space: \(frames)")
                    }
                }
            } else {
                try expect(!nodes(view).contains { $0.identifier == "project-task-toggle-" + item.id },
                           "Notes and captures do not inherit a task completion control")
            }
        }
    }

    private static func run() async throws {
        let watchdog = DispatchWorkItem {
            FileHandle.standardError.write(Data("FAIL: Project card QA exceeded 90 seconds\n".utf8)); _exit(124)
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 90, execute: watchdog)
        defer { watchdog.cancel() }

        for kind in CaptureKind.allCases {
            let capture = Capture(kind: kind, originalText: "Fictional captured original", title: "Fictional \(kind.rawValue)")
            let expected: ProjectCardRole = kind == .task ? .task : .capture
            try expect(ProjectCardRole(item: .capture(capture)) == expected,
                       "Unconverted \(kind.rawValue) has its actual semantic role")
            capture.setConvertedToTask(true)
            try expect(ProjectCardRole(item: .capture(capture)) == .task,
                       "Task status takes precedence over original \(kind.rawValue) content type")
            try expect(capture.kind == kind, "Role classification never mutates immutable capture kind")
        }
        for origin in CaptureOrigin.allCases {
            let receipt = origin == .manual ? CaptureReceiptContext.manual : .automatic(origin)
            let capture = Capture(kind: .text, originalText: "Fictional copied words", title: "Fictional text", receipt: receipt)
            try expect(ProjectCardRole(item: .capture(capture)) == .capture,
                       "\(origin.rawValue) text is not falsely inferred to be an editable project note")
        }
        let note = WorkspaceScratchpad(text: "Launch notes\nKeep the introduction friendly.\nUse the latest artwork.",
                                       projectName: "Fictional launch", updatedAt: Date(timeIntervalSince1970: 1_791_000_000))
        try expect(ProjectCardRole(item: .note(note)) == .note, "The explicit editable project scratchpad is a note")
        try expect([ProjectCardRole.task.title, ProjectCardRole.note.title, ProjectCardRole.capture.title] == ["Task", "Note", "Capture"],
                   "User-facing role labels remain short and distinct")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinProjectCardQA-\(UUID().uuidString)")
        let suite = "DaBinProjectCardQA.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: PreviewService.linkPreviewPreference)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root, repairArchiveOnOpen: false)
        let previews = PreviewService(store: store, defaults: defaults)
        let auto = AutoCaptureService(settings: AutoCaptureSettings(defaults: defaults), input: InputService(store: store),
            pasteboardProvider: { fatalError("Project card QA must not read the clipboard") }, sourceApplicationProvider: { nil })
        let state = AppState(store: store, previews: previews,
            reminders: ReminderService(store: store, client: ProjectCardNotifications()), autoCapture: auto,
            captureClipboard: CaptureClipboardService(writer: { _ in fatalError("Project card QA must not write the clipboard") }),
            folderOpener: { _ in fatalError("Project card QA must not open Finder") })
        defer { previews.shutdown(); auto.shutdown(); state.focusSessions.shutdown(); store.cancelArchiveRepair() }
        let task = try store.createTask(text: "Review the launch artwork", planning: TaskPlanning(priority: .high, checklist: [
            TaskChecklistItem(text: "Check the final colors", isCompleted: true),
            TaskChecklistItem(text: "Approve the cover")]), projectName: note.projectName)
        let text = try store.capture(text: "A useful captured paragraph stays a capture, even when it is text.", projectName: note.projectName)[0]
        let automatic = try store.capture(text: "Fictional automatically copied research. Keep this source text intact.",
            receipt: .automatic(.automaticClipboard), projectName: note.projectName)[0]
        let png = try syntheticPNG()
        let imageTask = try await store.importData(png, filename: "Fictional artwork to review.png", projectName: note.projectName)
        let imageCapture = try await store.importData(png, filename: "Fictional saved reference.png", projectName: note.projectName)
        for image in [imageTask, imageCapture] {
            guard let thumbnail = await PreviewService.writeThumbnail(png, root: root, id: image.id) else {
                throw failure("Could not save the fictional local thumbnail")
            }
            image.thumbnailRelativePath = thumbnail; image.previewState = "ready"
            try store.save(captures: [image])
        }
        guard let originalURL = store.managedURL(for: imageTask) else { throw failure("Synthetic image has no managed original") }
        let originalBytes = try Data(contentsOf: originalURL)
        let imageItem = ProjectWorkspaceItem.capture(imageTask)
        let actions = ProjectCardActions()
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("build/qa/project-workspace-card/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        try await withFixture(state: state, items: [imageItem], compact: false, dark: false, actions: actions) { view in
            try await checkRoles([imageItem], in: view, compact: false)
            try await checkImagePreview(imageItem, in: view)
            let select = try await find("project-select-" + imageItem.id, in: view)
            try expect(select.press(), "Independent card selection activates")
            try await settle(view)
            let selected = try await find("project-select-" + imageItem.id, in: view)
            try expect(selected.valueText == "Selected" && actions.selected == 1 && actions.opened == 0 && actions.detailed == 0,
                       "Selection does not open the original, navigate to details, or convert the capture")
            try expect(!imageTask.isTask, "Selecting a capture does not make it a task")
            try store.convertToTask(imageTask)
            try await settle(view)
            try await checkRoles([imageItem], in: view, compact: false)
            try await checkImagePreview(imageItem, in: view)
            try expect(imageTask.kind == .image && imageTask.isTask, "Live task conversion preserves the image's original kind")
            let complete = try await find("project-task-toggle-" + imageItem.id, in: view)
            try expect(complete.press(), "Task completion uses the real AppState action")
            try await settle(view)
            try expect(imageTask.isCompleted, "The injected isolated store persists task completion")
            try await checkRoles([imageItem], in: view, compact: false)
            try saveFixture(view, name: "completed-image-task-light", output: output)
            let reopen = try await find("project-task-toggle-" + imageItem.id, in: view)
            try expect(reopen.press(), "Completed image task can be reopened")
            try await settle(view)
            try expect(!imageTask.isCompleted, "Reopening restores the task's To do state")
            try await checkRoles([imageItem], in: view, compact: false)
            let preview = try await find("project-preview-" + imageItem.id, in: view)
            try expect(preview.press(), "Image-task preview retains its independent original-opening action")
            try expect(actions.opened == 1 && actions.selected == 1 && actions.detailed == 0,
                       "Opening the preview does not toggle selection or completion")
        }

        let items: [ProjectWorkspaceItem] = [.capture(task), .note(note), .capture(text),
                                             imageItem, .capture(imageCapture), .capture(automatic)]
        for dark in [false, true] {
            for compact in [false, true] {
                try await withFixture(state: state, items: items, compact: compact, dark: dark, actions: actions) { view in
                    try await checkRoles(items, in: view, compact: compact)
                    try await checkImagePreview(imageItem, in: view)
                    try await checkImagePreview(.capture(imageCapture), in: view)
                    try saveFixture(view, name: "project-types-\(compact ? "compact-320" : "grid")-\(dark ? "dark" : "light")", output: output)
                }
            }
        }
        let shortTask = try store.createTask(text: "Send the estimate", planning: TaskPlanning(priority: .medium), projectName: note.projectName)
        let longTask = try store.createTask(text: "Review the complete launch presentation and confirm the final artwork with the client before sending",
            planning: TaskPlanning(priority: .low, checklist: [
                TaskChecklistItem(text: "Review the opening slides"),
                TaskChecklistItem(text: "Confirm the client's changes")]), projectName: note.projectName)
        let denseTasks: [ProjectWorkspaceItem] = [.capture(shortTask), .capture(task), .capture(longTask)]
        let denseActions = ProjectCardActions()
        for dark in [false, true] {
            try await withFixture(state: state, items: denseTasks, compact: false, dark: dark, actions: denseActions) { view in
                try await checkRoles(denseTasks, in: view, compact: false)
                let short = try await find("project-task-content-" + denseTasks[0].id, in: view)
                let checklist = try await find("project-task-content-" + denseTasks[1].id, in: view)
                let long = try await find("project-task-content-" + denseTasks[2].id, in: view)
                try expect(short.frame.height < 175 && short.frame.height >= 120,
                           "A short project task uses less than 175 points while preserving independent controls")
                try expect(checklist.frame.height > short.frame.height + 20 && long.frame.height > checklist.frame.height + 10,
                           "Project task height grows only when checklist or long-title content needs the room")
                try expect(long.frame.height < 270, "Long-title task stays denser than the previous fixed 284-point tile")
                let select = try await find("project-select-" + denseTasks[0].id, in: view)
                let preview = try await find("project-preview-" + denseTasks[0].id, in: view)
                let details = try await find("project-details-" + denseTasks[0].id, in: view)
                let toggle = try await find("project-task-toggle-" + denseTasks[0].id, in: view)
                for frame in [select.frame, details.frame, toggle.frame] {
                    try expect(!preview.frame.intersects(frame), "Task open/drag preview never covers selection, details, or completion")
                }
                try saveFixture(view, name: "project-tasks-content-height-\(dark ? "dark" : "light")", output: output)
                if !dark {
                    try expect(details.press(), "Compact task's separate details target remains actionable")
                    try await settle(view)
                    try expect(denseActions.detailed == 1 && denseActions.opened == 0 && denseActions.selected == 0,
                               "Task details do not invoke original opening or selection")
                    try expect(preview.press(), "Task preview's original open action remains actionable")
                    try await settle(view)
                    try expect(denseActions.opened == 1 && denseActions.detailed == 1 && denseActions.selected == 0,
                               "Task preview remains independent from details, selection, and completion")
                }
            }
        }
        let compactActions = ProjectCardActions()
        try await withFixture(state: state, items: [.capture(shortTask)], compact: true, dark: false, actions: compactActions) { view in
            let item = ProjectWorkspaceItem.capture(shortTask)
            try saveFixture(view, name: "project-task-compact-medium-light", output: output)
            try await checkRoles([item], in: view, compact: true)
            let preview = try await find("project-preview-" + item.id, in: view)
            let details = try await find("project-details-" + item.id, in: view)
            let select = try await find("project-select-" + item.id, in: view)
            try expect(!preview.frame.intersects(details.frame) && !preview.frame.intersects(select.frame),
                       "Compact checklist icon has an independent open target beside details and selection")
            try expect(preview.press(), "Compact text-task icon opens the same original task as its previous preview")
            try await settle(view)
            try expect(compactActions.opened == 1 && compactActions.detailed == 0 && compactActions.selected == 0,
                       "Compact text-task icon preserves its independent action")
            try expect(details.press(), "Compact task title still opens details")
            try await settle(view)
            try expect(compactActions.opened == 1 && compactActions.detailed == 1 && compactActions.selected == 0,
                       "Compact task details remain separate from the new icon")
        }
        try expect(try Data(contentsOf: originalURL) == originalBytes && originalBytes == png,
                   "Classification, rendering, conversion and completion preserve every original image byte")
        try expect(text.kind == .text && !text.isTask && automatic.kind == .text && !automatic.isTask,
                   "Presentation does not convert either manual or automatic captured text")
        try expect(actions.opened == 1 && actions.selected == 1 && actions.detailed == 0,
                   "Passive light/dark and compact rendering invokes no capture actions")
        print("PASS: \(checks) project card checks; Task/Note/Capture semantics, real live task updates, light/dark/grid/320-point compact fixtures, original previews and independent selection; no personal archive, clipboard, network, or external opening.")
    }
}
