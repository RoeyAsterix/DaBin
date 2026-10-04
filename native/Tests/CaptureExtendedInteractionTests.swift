import AppKit
import ApplicationServices
import ImageIO
import PDFKit
import SwiftUI

@MainActor private final class ExtendedReminderClient: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .undetermined }
    func requestAuthorization() async throws -> Bool { false }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}

/// Uses only own-process accessibility actions and synthetic window-local
/// clicks in offscreen fixture windows. It never opens an external app.
@MainActor private struct ExtendedAXNode {
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
    var help: String {
        [value("accessibilityHelp"), attribute("AXHelp")].compactMap { $0 as? String }.first { !$0.isEmpty } ?? ""
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
    var children: [Any] {
        var result: [Any] = []
        for name in ["accessibilityChildren", "accessibilityChildrenInNavigationOrder", "accessibilityContents"] {
            if let children = value(name) as? [Any] { result += children }
        }
        if let children = attribute("AXChildren") as? [Any] { result += children }
        if let view = object as? NSView { result += view.subviews }
        return result
    }
}

@main @MainActor private final class CaptureExtendedInteractionTests: NSObject, NSApplicationDelegate {
    private static var checks = 0
    private var result = 0

    static func main() {
        let application = NSApplication.shared
        let delegate = CaptureExtendedInteractionTests()
        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
        exit(Int32(delegate.result))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await Self.run() }
            catch {
                result = 1
                fputs("Detail preview interaction QA failed: \(error)\n", stderr)
            }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }

    private static func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard value() else {
            throw NSError(domain: "CaptureExtendedInteractionTests", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private static func nodes(_ view: NSView) -> [ExtendedAXNode] {
        view.layoutSubtreeIfNeeded()
        var seen = Set<ObjectIdentifier>()
        var result: [ExtendedAXNode] = []
        func visit(_ value: Any, depth: Int) {
            guard depth < 50, let object = value as? NSObject,
                  seen.insert(ObjectIdentifier(object)).inserted else { return }
            let node = ExtendedAXNode(object: object)
            result.append(node)
            node.children.forEach { visit($0, depth: depth + 1) }
        }
        visit(view, depth: 0)
        NSAccessibility.unignoredChildren(from: [view]).forEach { visit($0, depth: 0) }
        return result
    }

    private static func settle(_ view: NSView) async {
        for _ in 0..<6 {
            view.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(40))
        }
    }

    private static func pdfView(in view: NSView) -> PDFView? {
        if let pdf = view as? PDFView { return pdf }
        return view.subviews.lazy.compactMap { pdfView(in: $0) }.first
    }

    private static func find(_ view: NSView, id: String) async throws -> ExtendedAXNode {
        for _ in 0..<12 {
            if let node = nodes(view).first(where: { $0.identifier == id }) { return node }
            await settle(view)
        }
        throw NSError(domain: "CaptureExtendedInteractionTests", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Missing native preview control \(id): \(nodes(view).map { $0.identifier ?? $0.label }.joined(separator: "; "))"])
    }

    private static func find(_ view: NSView, label: String) async throws -> ExtendedAXNode {
        for _ in 0..<12 {
            if let node = nodes(view).first(where: { $0.label == label }) { return node }
            await settle(view)
        }
        throw NSError(domain: "CaptureExtendedInteractionTests", code: 8,
            userInfo: [NSLocalizedDescriptionKey: "Missing native preview control \(label)"])
    }

    private static func withPreview(store: CaptureStore, capture: Capture, opener: (() -> Void)?,
                                    body: (NSView, NSWindow) async throws -> Void) async throws {
        let hosting = NSHostingView(rootView: DetailPreview(store: store, capture: capture, height: 220,
                                                            onOpenOriginal: opener)
            .frame(width: 360, height: 240))
        hosting.frame = NSRect(x: 0, y: 0, width: 360, height: 240)
        hosting.wantsLayer = true
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 360, height: 240),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        // SwiftUI materializes native accessibility only for an ordered window.
        // Render offscreen without makeKey, activation, or a global pointer event.
        window.orderFront(nil)
        await settle(hosting)
        // SwiftUI exposes virtual AX nodes lazily, after a client requests the
        // application hierarchy. Ask only this test process while the AppKit
        // run loop remains available to serve that own-process request.
        let accessibility = await Task.detached {
            let process = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            AXUIElementSetMessagingTimeout(process, 3)
            var windows: CFTypeRef?
            return AXUIElementCopyAttributeValue(process, kAXWindowsAttribute as CFString, &windows)
        }.value
        try expect(accessibility == .success,
                   "The offscreen fixture exposes its own native accessibility hierarchy")
        await settle(hosting)
        try expect(window.frame.maxX < 0 && !window.isKeyWindow && !NSApplication.shared.isActive,
                   "Preview fixtures stay offscreen, non-key and inactive")
        try await body(hosting, window)
    }

    private static func click(_ button: ExtendedAXNode, in window: NSWindow) throws {
        let screenPoint = NSPoint(x: button.frame.midX, y: button.frame.midY)
        let point = window.convertPoint(fromScreen: screenPoint)
        let timestamp = ProcessInfo.processInfo.systemUptime
        guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
            timestamp: timestamp, windowNumber: window.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1),
              let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [],
            timestamp: timestamp + 0.02, windowNumber: window.windowNumber, context: nil,
            eventNumber: 2, clickCount: 1, pressure: 0) else {
            throw NSError(domain: "CaptureExtendedInteractionTests", code: 9)
        }
        // Native NSButton tracking can consume the matching mouse-up while
        // mouseDown runs. Queue it only in this test process, for this window;
        // otherwise dispatch the unconsumed event directly to the same window.
        NSApplication.shared.postEvent(up, atStart: true)
        window.sendEvent(down)
        if let remaining = NSApplication.shared.nextEvent(matching: .leftMouseUp, until: Date(),
                                                          inMode: .default, dequeue: true) {
            try expect(remaining.windowNumber == window.windowNumber,
                       "The synthetic preview click belongs only to its own fixture window")
            window.sendEvent(remaining)
        }
    }


    private static func render(_ view: NSView, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["DABIN_EXTENDED_QA_OUTPUT"] else { return }
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let root = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try bitmap.representation(using: .png, properties: [:])?.write(to: root.appendingPathComponent(name + ".png"))
    }

    private static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinExtendedQA-\(UUID())")
        let suite = "DaBinExtendedQA.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let store = try CaptureStore(root: root)
        let coordinator = ApplicationCoordinator(store: store, defaults: defaults,
            notificationClient: ExtendedReminderClient(), taskTimerPrimaryScreen: { nil })
        let state = coordinator.state
        defer {
            coordinator.shutdown()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let note = try store.createNote(text: "Client feedback\n\nPlease keep the complete original and review the final artwork.\n\n" + String(repeating: "A longer capture stays readable and can be reused. שלום · 日本語\n", count: 18))
        try store.save(captures: [note])
        _ = try store.appendComment(note, text: "First review is ready.")
        state.openCapture(note.id)
        let draft = state.selectedDraft!
        let detail = NSHostingView(rootView: DetailScreen(state: state, capture: note, draft: draft))
        let page = NSWindow(contentRect: CGRect(x: -10_000, y: -10_000, width: 660, height: 820),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        page.isReleasedWhenClosed = false
        page.contentView = detail
        page.orderFront(nil)
        defer { page.orderOut(nil); page.contentView = nil; page.close() }
        await settle(detail)
        _ = await Task.detached {
            let process = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            var windows: CFTypeRef?
            return AXUIElementCopyAttributeValue(process, kAXWindowsAttribute as CFString, &windows)
        }.value
        await settle(detail)
        try expect(!nodes(detail).contains { $0.label == "Pin" || $0.label == "Unpin" || $0.help == "Pin capture" },
                   "Capture page has no dead pin target or tooltip")
        let preview = try await find(detail, id: "detail-preview-open-extended")
        try expect(preview.press(), "Preview opens Extended View using native accessible press")
        await settle(detail)
        let extended = coordinator.extendedView
        try expect(extended.window.isVisible && extended.captureID == note.id,
                   "Production callback presents a separate Extended View for the selected capture")
        try expect(state.route == .detail && state.selectedCapture?.id == note.id && state.selectedDraft === draft,
                   "Opening Extended View preserves mounted detail and its draft")
        guard let host = extended.window.contentView else { throw NSError(domain: "ExtendedQA", code: 1) }
        await settle(host)
        extended.window.setContentSize(CGSize(width: 1020, height: 760))
        await settle(host)
        let plus = try await find(host, id: "capture-zoom-in")
        try expect(plus.press(), "Zoom-in is keyboard and accessibility actionable")
        await settle(host)
        let scale = extended.zoom.scale
        try expect(scale > 1, "Text zoom increases native typography scale")
        let commentTab = try await find(host, id: "capture-tab-comments")
        let reminderTab = try await find(host, id: "capture-tab-reminder")
        try expect(commentTab.frame.height >= 44 && reminderTab.frame.height >= 44,
                   "Both section tabs have prominent click targets")
        try expect(commentTab.label.contains("1"), "Comments tab announces saved comment count")
        try expect(reminderTab.press(), "Reminder tab is accessible")
        await settle(host)
        try expect(extended.zoom.scale == scale && nodes(host).contains { $0.identifier == "capture-reminder-panel" },
                   "Reminder selection preserves zoom while revealing scheduling controls")
        try render(host, name: "extended-wide-reminder")
        try expect(commentTab.press(), "Comments tab is accessible")
        await settle(host)
        try expect(extended.zoom.scale == scale, "Returning to Comments preserves zoom")
        draft.commentComposer = "Second reply from Extended View."
        await settle(host)
        try render(host, name: "extended-wide-comments")
        let post = try await find(host, id: "capture-post-comment")
        try expect(post.press(), "Post comment uses real native action")
        await settle(host)
        try expect(note.commentCount == 2 && draft.commentComposer.isEmpty,
                   "Posting appends to the thread without losing the first reply")
        draft.editingCommentID = note.commentThread[1].id
        draft.commentComposer = "Edited second reply."
        try expect(state.postDetailComment(note, draft: draft) && note.commentCount == 2,
                   "Editing preserves reply count and identity")
        let due = Date().addingTimeInterval(3600)
        try expect(state.setDetailReminder(note, date: due) && note.reminderAt == due,
                   "Scheduling saves the selected capture reminder independently of comments")
        await settle(host)
        _ = try await find(host, id: "capture-tab-reminder").press()
        await settle(host)
        let remove = try await find(host, id: "capture-remove-reminder")
        try expect(remove.press(), "Remove reminder is a native accessible action")
        await settle(host)
        try expect(note.reminderAt == nil && note.commentCount == 2, "Removing the reminder preserves the comment thread")
        extended.window.setContentSize(CGSize(width: 480, height: 570))
        await settle(host)
        try expect(host.bounds.width >= 480 && nodes(host).contains { $0.identifier == "capture-tab-reminder" },
                   "Narrow Extended View keeps the accessible bottom panel")
        try render(host, name: "extended-narrow-reminder")
        _ = try await find(host, id: "capture-tab-comments").press()
        await settle(host)
        try render(host, name: "extended-narrow-comments")
        try expect(extended.zoom.scale == scale, "Responsive reflow preserves custom zoom")
        let rememberedFrame = extended.window.frame
        extended.window.cancelOperation(nil)
        await settle(detail)
        try expect(!extended.window.isVisible && state.route == .detail && state.selectedDraft === draft,
                   "Escape closes Extended View and retains the originating capture page")
        state.openExtendedCapture(note.id)
        await settle(extended.window.contentView!)
        try expect(extended.zoom.scale == scale && extended.window.frame.size == rememberedFrame.size,
                   "Reopening the same capture retains its zoom and chosen window size")
        extended.window.performClose(nil)
        try render(detail, name: "capture-detail")
        let other = try store.createNote(text: "A second reminder")
        extended.showCompletedReminders([
            TaskTimerCompletion(taskID: note.id, title: note.title),
            TaskTimerCompletion(taskID: other.id, title: other.title)])
        await settle(extended.window.contentView!)
        try expect(extended.window.isVisible && extended.captureID == nil,
                   "Multiple acknowledged reminders open one list instead of losing a receipt")
        extended.window.performClose(nil)
        try expect(store.captures.count == 2, "Extended View never deletes captures")
        print("Capture Extended View QA passed (\(checks) checks)")
    }
}
