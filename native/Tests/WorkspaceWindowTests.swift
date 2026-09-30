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
    private func attribute(_ name: String) -> Any? {
        let selector = NSSelectorFromString("accessibilityAttributeValue:")
        guard object.responds(to: selector),
              (value("accessibilityAttributeNames") as? [String])?.contains(name) == true else { return nil }
        return object.perform(selector, with: name as NSString)?.takeUnretainedValue()
    }
    var identifier: String? { (value("accessibilityIdentifier") as? String) ?? (attribute("AXIdentifier") as? String) }
    var label: String? {
        [value("accessibilityLabel"), value("accessibilityTitle"), attribute("AXTitle"), attribute("AXDescription"),
         value("accessibilityValue"), attribute("AXValue")].compactMap { $0 as? String }.first { !$0.isEmpty }
    }
    var frame: NSRect {
        let selector = NSSelectorFromString("accessibilityFrame")
        guard object.responds(to: selector) else { return .zero }
        typealias Getter = @convention(c) (AnyObject, Selector) -> NSRect
        return unsafeBitCast(object.method(for: selector), to: Getter.self)(object, selector)
    }
    var interactionFrame: NSRect {
        if let cell = object as? NSCell, let view = cell.controlView, let window = view.window {
            return window.convertToScreen(view.convert(view.bounds, to: nil))
        }
        return frame
    }
    var isEnabled: Bool {
        let selector = NSSelectorFromString("isAccessibilityEnabled")
        guard object.responds(to: selector) else { return false }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(object.method(for: selector), to: Getter.self)(object, selector)
    }
    func setText(_ text: String) -> Bool {
        if let field = object as? NSTextField {
            // Editing through AppKit's field editor sends the same change
            // notifications as typing. A bare AX value setter may only change
            // the backing value without notifying SwiftUI's text binding.
            field.selectText(nil)
            guard let editor = field.currentEditor() as? NSTextView else { return false }
            editor.insertText(text, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
            return true
        }
        let selector = NSSelectorFromString("setAccessibilityValue:")
        guard object.responds(to: selector) else { return false }
        _ = object.perform(selector, with: text as NSString)
        return true
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

@MainActor private struct WorkspacePlanningHarness: View {
    @ObservedObject var draft: NewTaskDraft
    var body: some View { TaskPlanningEditor(planning: $draft.planning).padding(16) }
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
    @MainActor private static func settleNavigation() async {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(120))
        settle()
    }
    @MainActor private static func listScrollView(in view: NSView) throws -> NSScrollView {
        if let scroll = view as? NSScrollView, !scroll.isHiddenOrHasHiddenAncestor, scroll.bounds.height > 80 { return scroll }
        for child in view.subviews {
            if let scroll = try? listScrollView(in: child) { return scroll }
        }
        throw NSError(domain: "WorkspaceWindowTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Workspace list has no native scroll view"])
    }
    @MainActor private static func selectedCardIsVisible(_ id: UUID, in view: NSView, window: NSWindow) throws -> Bool {
        let scroll = try listScrollView(in: view)
        let visible = window.convertToScreen(scroll.contentView.convert(scroll.contentView.bounds, to: nil))
        let card = try find(view, id: "workspace-item-\(id.uuidString)")
        return card.frame.width > 0 && card.frame.height > 0 && visible.contains(NSPoint(x: card.frame.midX, y: card.frame.midY))
    }
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
        fputs("Workspace controls at failure: \(nodes(view).compactMap { $0.identifier ?? $0.label }.joined(separator: "; "))\n", stderr)
        throw NSError(domain: "WorkspaceWindowTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing workspace control \(id)"])
    }
    @MainActor private static func findLabeled(_ view: NSView, label: String) throws -> WorkspaceAXNode {
        for _ in 0..<6 {
            let available = nodes(view)
            if let field = available.first(where: { ($0.object as? NSTextField)?.placeholderString == label }) { return field }
            if let node = available.first(where: {
                $0.label == label || ($0.object as? NSTextField)?.placeholderString == label
            }) { return node }
            settle()
        }
        fputs("Editor controls at failure: \(nodes(view).compactMap { $0.label }.joined(separator: "; "))\n", stderr)
        throw NSError(domain: "WorkspaceWindowTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "Missing labeled control \(label)"])
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

        // A long client name must never push the task count or actions out of
        // the minimum window. Notes-only projects remain first-class choices.
        let longProject = "Fictional International Creative Studio — Quarterly launch materials, client approvals and follow-up work"
        try state.workspace.setScratchpad(text: "A project can begin with a note before its first task.", project: longProject)
        state.libraryProject = longProject
        theme.setDarkMode(false)
        for size in [NSSize(width: 380, height: 430), NSSize(width: 760, height: 680)] {
            window.setContentSize(size); state.openLibrary(); settle()
            state.workspace.mode = .scratchpad; settle()
            let visible = window.convertToScreen(hosting.convert(hosting.bounds, to: nil))
            let projectPicker = try find(hosting, id: "workspace-project-picker")
            try expect(visible.insetBy(dx: -1, dy: -1).contains(projectPicker.interactionFrame), "Long Workspace project remains inside the \(Int(size.width))-point window")
            try expect(projectPicker.label?.contains(longProject) == true, "Truncated project keeps its full accessible name")
            try expect(visible.contains(try find(hosting, id: "workspace-scratchpad-save-status").frame),
                "Scratchpad save status stays visible beside a long project name")
            try saveImage(hosting, to: evidence.appendingPathComponent("workspace-long-project-notes-\(Int(size.width))x\(Int(size.height))-light.png"))
            state.showReminders(); settle()
            let todayProject = try find(hosting, id: "today-project-picker")
            try expect(visible.insetBy(dx: -1, dy: -1).contains(todayProject.interactionFrame), "Long Today project remains inside the \(Int(size.width))-point window")
            try expect(todayProject.label?.contains(longProject) == true, "Today exposes the full project name to accessibility")
            try expect(visible.contains(try find(hosting, id: "today-plan-summary").frame), "Today's task count stays visible beside a long project name")
            let add = try find(hosting, id: "today-add-task")
            try expect(add.frame.width >= 28 && add.frame.height >= 28 && visible.contains(add.frame), "Today Add has a visible usable hit target")
            try saveImage(hosting, to: evidence.appendingPathComponent("today-long-project-\(Int(size.width))x\(Int(size.height))-light.png"))
        }
        let addToday = try find(hosting, id: "today-add-task")
        try expect(addToday.press(), "Today Add supports accessible activation")
        settle()
        try expect(state.route == .newTask && state.newTaskDraft.planning.plannedDay == CaptureCalendar.dayString(Date()),
            "Today Add opens a composer planned for today")
        state.libraryProject = "Client A"
        try store.planTask(task, on: CaptureCalendar.dayString(Date()))
        let nextTask = try store.createTask(text: "Confirm the project delivery date")
        try store.setOrganization(nextTask, pinned: false, projectName: "Client A")
        try store.planTask(nextTask, on: CaptureCalendar.dayString(Date()))
        try store.reorderTasks([task, nextTask], on: CaptureCalendar.dayString(Date()))
        window.setContentSize(NSSize(width: 380, height: 680)); state.showReminders(); settle()
        for direction in ["up", "down"] {
            let action = try find(hosting, id: "today-move-\(direction)-\(task.id.uuidString)")
            try expect(action.frame.width >= 28 && action.frame.height >= 28, "Task reorder \(direction) has a usable hit target")
        }
        try expect(try find(hosting, id: "today-move-down-\(task.id.uuidString)").press(), "Task reorder works through accessibility")
        settle()
        try expect(TaskPlanningPolicy.today(store.captures).filter { $0.projectName == "Client A" }.map(\.id) == [nextTask.id, task.id],
            "Accessible reorder persists the intended task order")

        // Navigation restores the remembered card. Incoming copies are not
        // navigation and must not force the viewport back to it or to the top.
        var scrollA: [Capture] = []
        var scrollB: [Capture] = []
        for index in 0..<16 {
            let capturedAt = Date().addingTimeInterval(Double(index - 100))
            let first = try store.capture(text: "Scroll client A: fictional material \(index)", at: capturedAt)[0]
            try store.setOrganization(first, pinned: false, projectName: "Scroll client A")
            scrollA.append(first)
            let second = try store.capture(text: "Scroll client B: fictional material \(index)", at: capturedAt)[0]
            try store.setOrganization(second, pinned: false, projectName: "Scroll client B")
            scrollB.append(second)
        }
        state.libraryProject = "Scroll client A"; state.workspace.selectedCaptureID = scrollA[1].id
        state.libraryProject = "Scroll client B"; state.workspace.selectedCaptureID = scrollB[14].id
        state.workspace.mode = .collection; state.openLibrary(); await settleNavigation()
        state.libraryProject = "Scroll client A"; await settleNavigation()
        try expect(try selectedCardIsVisible(scrollA[1].id, in: hosting, window: window),
            "Changing project in place brings its remembered deep card into view")
        state.libraryProject = "Scroll client B"; await settleNavigation()
        try expect(try selectedCardIsVisible(scrollB[14].id, in: hosting, window: window),
            "Returning to another project restores its own selected card")
        let scrollTask = try store.createTask(text: "A task excluded from Clipboard")
        try store.setOrganization(scrollTask, pinned: false, projectName: "Scroll client B")
        state.workspace.selectedCaptureID = scrollTask.id
        state.workspace.mode = .clipboard; await settleNavigation()
        let list = try listScrollView(in: hosting)
        guard let document = list.documentView else { throw NSError(domain: "WorkspaceWindowTests", code: 6) }
        let topOffset = document.isFlipped ? list.contentView.bounds.minY : document.bounds.maxY - list.contentView.bounds.maxY
        try expect(abs(topOffset) <= 1, "Changing mode with an excluded selection returns to the top")
        let browsingY: CGFloat = document.isFlipped ? 500 : max(0, document.bounds.height - list.contentView.bounds.height - 500)
        list.contentView.scroll(to: NSPoint(x: 0, y: browsingY)); list.reflectScrolledClipView(list.contentView)
        await settleNavigation()
        let browsingOrigin = list.contentView.bounds.origin
        let browsingViewport = window.convertToScreen(list.contentView.convert(list.contentView.bounds, to: nil))
        let browsingCards = nodes(hosting).filter {
            $0.identifier?.hasPrefix("workspace-item-") == true && $0.frame.height > 0 && browsingViewport.contains(NSPoint(x: $0.frame.midX, y: $0.frame.midY))
        }.map { ($0.identifier!, $0.frame) }
        try expect(!browsingCards.isEmpty, "The clipboard stability check starts with visible content away from the top")
        let incoming = try store.capture(text: "An incoming clipboard item while browsing", receipt: .automatic(.automaticClipboard))[0]
        try store.setOrganization(incoming, pinned: false, projectName: "Scroll client B")
        await settleNavigation()
        let currentCards = nodes(hosting)
        let positionsPreserved = browsingCards.allSatisfy { identifier, before in
            guard let after = currentCards.first(where: { $0.identifier == identifier })?.frame else { return false }
            return abs(after.minY - before.minY) <= 1 && abs(after.minX - before.minX) <= 1
                && abs(after.height - before.height) <= 1 && abs(after.width - before.width) <= 1
        }
        // AppKit changes the raw offset by the inserted row's height to keep
        // the content visually stationary. Test what the user is reading.
        fputs("Clipboard raw offset \(browsingOrigin.y) → \(list.contentView.bounds.origin.y); \(browsingCards.count) visible card positions preserved=\(positionsPreserved)\n", stderr)
        try expect(positionsPreserved && state.workspace.selectedCaptureID == scrollTask.id,
            "A new clipboard capture preserves visible card positions and the current selection")

        // Exercise the shared editor's actual field and button, not a second
        // copy of its validation policy. All text is fictional and local.
        let editorDraft = NewTaskDraft()
        editorDraft.planning.checklist = [TaskChecklistItem(text: "An existing next step")]
        let editor = NSHostingView(rootView: WorkspacePlanningHarness(draft: editorDraft))
        window.contentView = editor; window.setContentSize(NSSize(width: 380, height: 800)); await settleNavigation()
        try saveImage(editor, to: evidence.appendingPathComponent("checklist-editor-before-validation.png"))
        // DisclosureGroup can propagate its AX identifier to descendants on
        // macOS. Locate these real controls by their semantic labels instead.
        let checklistInput = try findLabeled(editor, label: "Add a small next step")
        try expect(checklistInput.setText(String(repeating: "x", count: 501)), "Checklist input supports accessible editing")
        settle()
        try expect(!(try findLabeled(editor, label: "Add checklist step").isEnabled), "A 501-character step cannot activate Add")
        try expect(nodes(editor).contains { $0.label?.contains("500 characters") == true },
            "An oversized step explains the 500-character limit")
        try expect(editorDraft.planning.checklist.count == 1, "Invalid input preserves the existing checklist")
        try expect(checklistInput.setText("  " + String(repeating: "x", count: 500) + "  "), "Checklist text can be corrected without losing it")
        settle()
        let addStep = try findLabeled(editor, label: "Add checklist step")
        try expect(addStep.isEnabled && addStep.press(), "A corrected 500-character step can be added")
        settle()
        try expect(editorDraft.planning.checklist.count == 2 && editorDraft.planning.checklist.last?.text.count == 500,
            "A maximum-length valid step is stored exactly after trimming outer spaces")
        print("PASS: \(checks) native workspace interaction and responsive layout checks")
        print("Workspace screenshots: \(evidence.path)")
    }
}
