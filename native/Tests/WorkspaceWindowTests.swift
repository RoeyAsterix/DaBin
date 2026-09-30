import AppKit
import ApplicationServices
import SwiftUI

@MainActor private final class WorkspaceWindowReminderClient: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .allowed }
    func requestAuthorization() async throws -> Bool { false }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}

@MainActor private struct WorkspaceAXNode {
    let object: NSObject
    func value(_ name: String) -> Any? {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue()
    }
    var identifier: String? { value("accessibilityIdentifier") as? String }
    var label: String? { (value("accessibilityLabel") as? String) ?? (value("accessibilityTitle") as? String) }
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
        if let view = object as? NSView { result += view.subviews }
        return result
    }
}

/// Exercises the production workspace using native accessible actions in an
/// isolated window. Fixtures never use the user's archive or system clipboard.
@main private enum WorkspaceWindowTests {
    @MainActor private static var checks = 0
    @MainActor private static func expect(_ condition: Bool, _ message: String) throws {
        checks += 1
        if !condition { throw NSError(domain: "WorkspaceWindowTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    @MainActor private static func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
    @MainActor private static func nodes(_ view: NSView) -> [WorkspaceAXNode] {
        view.layoutSubtreeIfNeeded()
        var seen = Set<ObjectIdentifier>()
        var result: [WorkspaceAXNode] = []
        func visit(_ value: Any, depth: Int) {
            guard depth < 50, let object = value as? NSObject, seen.insert(ObjectIdentifier(object)).inserted else { return }
            let node = WorkspaceAXNode(object: object); result.append(node)
            node.children.forEach { visit($0, depth: depth + 1) }
        }
        visit(view, depth: 0)
        NSAccessibility.unignoredChildren(from: [view]).forEach { visit($0, depth: 0) }
        return result
    }
    @MainActor private static func find(_ view: NSView, id: String) throws -> WorkspaceAXNode {
        for _ in 0..<6 {
            if let node = nodes(view).first(where: { $0.identifier == id }) { return node }
            settle()
        }
        throw NSError(domain: "WorkspaceWindowTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing workspace control \(id)"])
    }
    @MainActor private static func saveImage(_ view: NSView, to url: URL) throws {
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw NSError(domain: "WorkspaceWindowTests", code: 3)
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "WorkspaceWindowTests", code: 4)
        }
        try data.write(to: url, options: .atomic)
    }

    @MainActor static func main() async throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.finishLaunching()
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("DaBin-WorkspaceWindow-\(UUID())")
        let suite = "DaBinWorkspaceWindow.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? files.removeItem(at: root) }
        let store = try CaptureStore(root: root)
        let capture = try store.capture(text: "Client A: please send the revised proposal with the updated timeline.\nשלום / 日本語 — keep the original feedback.")[0]
        try store.setOrganization(capture, pinned: false, projectName: "Client A")
        let old = try store.capture(text: "Thanks for your feedback. I will send the next revision tomorrow.", at: Date().addingTimeInterval(-3600))[0]
        try store.setOrganization(old, pinned: true, projectName: "Client A")
        let second = try store.capture(text: "Client B brief: keep this project separate.")[0]
        try store.setOrganization(second, pinned: false, projectName: "Client B")
        let task = try store.createTask(text: "Review the client proposal")
        try store.setOrganization(task, pinned: false, projectName: "Client A")
        let previews = PreviewService(store: store, defaults: defaults)
        defer { previews.shutdown() }
        var copiedPayloads: [CaptureClipboardPayload] = []
        let state = AppState(store: store, previews: previews,
            reminders: ReminderService(store: store, client: WorkspaceWindowReminderClient()),
            captureClipboard: CaptureClipboardService(writer: { copiedPayloads.append($0); return true }))
        state.libraryProject = "Client A"; state.openLibrary()
        try state.workspace.setSnippetName("Friendly follow-up", for: old.id)
        try state.workspace.setOnShelf([capture.id, old.id], included: true)
        try state.workspace.setScratchpad(text: "Client A resume note\nNext: revise the proposal and confirm the deadline.", project: "Client A")
        try state.workspace.setScratchpad(text: "Client B resume note", project: "Client B")
        let theme = ThemeSettings(defaults: defaults)
        theme.setDarkMode(false)
        let hosting = NSHostingView(rootView: BoardView(state: state, theme: theme))
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 380, height: 650),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        application.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        settle()
        let accessibility = await Task.detached {
            let process = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            AXUIElementSetMessagingTimeout(process, 3)
            var windows: CFTypeRef?
            return AXUIElementCopyAttributeValue(process, kAXWindowsAttribute as CFString, &windows)
        }.value
        try expect(accessibility == .success, "Native own-window accessibility tree is available")
        settle()
        for mode in WorkspaceMode.allCases {
            let button = try find(hosting, id: "workspace-mode-\(mode.rawValue)")
            try expect(button.frame.width >= 28 && button.frame.height >= 28, "Workspace mode \(mode.title) has a usable hit target")
            try expect(button.press(), "Workspace mode \(mode.title) supports accessible activation")
            settle()
            try expect(state.workspace.mode == mode && state.libraryProject == "Client A", "Mode change keeps the selected project")
        }
        try expect(try find(hosting, id: "workspace-scratchpad").frame.height >= 100, "Scratchpad remains writable in the compact window")
        let clipboard = try find(hosting, id: "workspace-mode-clipboard")
        try expect(clipboard.press(), "Clipboard mode opens")
        settle()
        let snippets = try find(hosting, id: "workspace-snippets-toggle")
        try expect(snippets.press(), "Snippets filter is an accessible action")
        settle()
        try expect(state.workspace.snippetsOnly, "Snippets filter displays named content")
        let open = try find(hosting, id: "workspace-item-\(old.id.uuidString)")
        try expect(open.press(), "A clipboard item opens using the native accessible action")
        settle()
        try expect(state.route == .detail && state.selectedCapture?.id == old.id && state.workspace.selectedCaptureID == old.id,
            "Opening retains the selected clipboard identity")
        state.back(); settle()
        _ = try store.capture(text: "New automatic copy during lookup", receipt: .automatic(.automaticClipboard))
        settle()
        try expect(state.route == .library && state.libraryProject == "Client A" && state.workspace.mode == .clipboard
            && state.workspace.selectedCaptureID == old.id && state.workspace.snippetsOnly,
            "Returning after a new capture restores the exact project, mode, filter and selection")
        try expect(state.copyCapturesToClipboard([old]) && copiedPayloads.last?.items == [.text(old.originalText!)],
            "Reusable content copies its original text without changing the current task context")
        window.selectNextKeyView(nil); settle()
        try expect(window.firstResponder != nil, "Workspace controls participate in the native keyboard focus chain")
        state.workspace.snippetsOnly = false
        let evidence = URL(fileURLWithPath: files.currentDirectoryPath).appendingPathComponent("build/qa/workspace-window-evidence")
        try files.createDirectory(at: evidence, withIntermediateDirectories: true)
        for size in [NSSize(width: 380, height: 430), NSSize(width: 620, height: 680), NSSize(width: 1280, height: 850)] {
            window.setContentSize(size); settle()
            for mode in WorkspaceMode.allCases {
                state.workspace.mode = mode; settle()
                for modeButton in WorkspaceMode.allCases {
                    let frame = try find(hosting, id: "workspace-mode-\(modeButton.rawValue)").frame
                    try expect(frame.minX >= window.frame.minX - 1 && frame.maxX <= window.frame.maxX + 1,
                        "Workspace mode fits \(Int(size.width))-point width")
                }
                let visibleContent = window.convertToScreen(hosting.convert(hosting.bounds, to: nil))
                if mode != .scratchpad {
                    for filter in CaptureFilter.allCases {
                        let frame = try find(hosting, id: "capture-filter-\(filter.rawValue)").frame
                        try expect(frame.width >= 28 && frame.height >= 28 && visibleContent.contains(frame),
                            "\(filter.title) filter remains visible and usable at \(Int(size.width))×\(Int(size.height))")
                    }
                } else {
                    for title in ["Save note", "Make task"] {
                        let action = nodes(hosting).first { $0.label == title && $0.frame.width > 0 }
                        try expect(action.map { visibleContent.contains($0.frame) } == true,
                            "\(title) is visible above the scratchpad editor at \(Int(size.width))×\(Int(size.height))")
                    }
                }
                try saveImage(hosting, to: evidence.appendingPathComponent("workspace-\(mode.rawValue)-\(Int(size.width))x\(Int(size.height))-light.png"))
            }
        }
        window.setContentSize(NSSize(width: 380, height: 650)); theme.setDarkMode(true); settle()
        for mode in WorkspaceMode.allCases {
            state.workspace.mode = mode; settle()
            try saveImage(hosting, to: evidence.appendingPathComponent("workspace-\(mode.rawValue)-380x650-dark.png"))
        }
        print("PASS: \(checks) native workspace interaction and responsive layout checks")
        print("Workspace screenshots: \(evidence.path)")
    }
}
