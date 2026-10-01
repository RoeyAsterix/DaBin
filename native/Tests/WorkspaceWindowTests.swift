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

    @MainActor private static func checkExplorer(state: AppState, hosting: NSView, window: NSWindow, evidence: URL) async throws {
        window.contentView = hosting
        state.libraryProject = "Explorer review"
        let first = try state.store.createNote(text: "A client follow-up with a clear next step", projectName: "Explorer review")
        _ = try state.store.createNote(text: "A second reference", projectName: "Explorer review")
        state.workspace.mode = .collection; state.workspace.explorerShowsDailyFiles = false
        state.filter = .all; state.libraryPinnedOnly = false
        state.workspace.explorerQuery = ""; state.workspace.dateFilter = .anytime
        state.workspace.sourceApplication = nil; state.workspace.originFilter = .all
        state.openLibrary(); window.setContentSize(NSSize(width: 1000, height: 720)); await settleNavigation()
        try expect(try find(hosting, id: "explorer-search").frame.width > 100, "Explorer search is available in its project")
        try expect(try find(hosting, id: "workspace-item-\(first.id.uuidString)").press(), "Explorer row accessible action activates")
        await settleNavigation()
        try expect(state.route == .library && state.workspace.selectedCaptureID == first.id,
            "Expanded selection previews in place without leaving the project")
        try expect(try find(hosting, id: "explorer-open-details").isEnabled, "Inspector exposes full details")
        try expect(try find(hosting, id: "explorer-inspector").frame.width > 400, "Expanded preview uses available width")
        let search = try findLabeled(hosting, label: "Find in this project")
        try expect(search.setText("follow-up"), "Explorer search accepts keyboard text")
        await settleNavigation()
        try expect(state.workspace.explorerQuery == "follow-up", "Project search binding updates")
        try expect(try find(hosting, id: "explorer-daily-files").press(), "Daily files action is keyboard accessible")
        await settleNavigation()
        let days = try state.store.explorerDocuments(project: "Explorer review")
        try expect(days.count == 1, "One daily document groups a project's day")
        try expect(try find(hosting, id: "explorer-day-\(days[0].id)").press(), "Daily document selects in place")
        await settleNavigation()
        try expect(state.route == .library, "Wide daily file preview remains in Explorer")
        try saveImage(hosting, to: evidence.appendingPathComponent("explorer-expanded-daily.png"))
        state.workspace.explorerShowsDailyFiles = false
        window.setContentSize(NSSize(width: 380, height: 430)); await settleNavigation()
        try expect(state.workspace.selectedCaptureID == first.id && state.workspace.explorerQuery == "follow-up",
            "Compact resize preserves selection and query")
        try expect(try find(hosting, id: "explorer-paste").isEnabled && find(hosting, id: "explorer-add-files").isEnabled,
            "Compact Explorer keeps accessible paste and import alternatives")
        try saveImage(hosting, to: evidence.appendingPathComponent("explorer-compact.png"))
        try expect(try find(hosting, id: "workspace-item-\(first.id.uuidString)").press(), "Compact row opens details")
        await settleNavigation()
        try expect(state.route == .detail && state.selectedCapture?.id == first.id, "Compact selection opens the complete capture")
        state.back(); await settleNavigation()
        try expect(state.route == .library && state.libraryProject == "Explorer review" && state.workspace.explorerQuery == "follow-up",
            "Back restores Explorer project and search")
        state.workspace.explorerQuery = ""
    }

    @MainActor private static func checkDetailResizing(state: AppState, hosting: NSView,
                                                       window: NSWindow, evidence: URL) async throws {
        let compactSize = NSSize(width: 380, height: 680)
        let expandedSize = NSSize(width: 1200, height: 900)
        let shortSize = NSSize(width: 1200, height: 430)
        let compact = DetailLayout(viewport: compactSize)
        let expanded = DetailLayout(viewport: expandedSize)
        let short = DetailLayout(viewport: shortSize)
        try expect(expanded.contentWidth > 860 && expanded.contentWidth > compact.contentWidth * 2,
            "Expanded capture detail uses the available width beyond the former 860-point ceiling")
        try expect(expanded.previewHeight > compact.previewHeight + 100 && short.previewHeight < expanded.previewHeight,
            "Preview sizing grows for a larger viewport and adapts to a short window")
        try expect(expanded.commentHeight > compact.commentHeight && expanded.titleSize > compact.titleSize,
            "The note editor and title grow with expanded detail")
        try expect(!compact.usesTaskColumns && expanded.usesTaskColumns && short.usesTaskColumns,
            "Task regions share wide layouts while compact details retain one column")
        try expect(expanded.attachmentMinimumWidth > compact.attachmentMinimumWidth
            && expanded.attachmentHeight > compact.attachmentHeight,
            "Expanded task attachments receive larger tiles and previews")

        // Use the production image preview in the same hosting tree throughout
        // the resize. Recreating BoardView here would conceal lost view state.
        let image = NSImage(size: NSSize(width: 1000, height: 640), flipped: false) { bounds in
            NSColor.systemPurple.setFill(); bounds.fill()
            NSColor.white.setFill(); bounds.insetBy(dx: 90, dy: 90).fill()
            NSColor.systemBlue.setFill()
            NSRect(x: 170, y: 240, width: 660, height: 160).fill()
            return true
        }
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "WorkspaceWindowTests", code: 8,
                userInfo: [NSLocalizedDescriptionKey: "Could not create the isolated detail image fixture"])
        }
        let capture = try await state.store.importData(png, filename: "Fictional resize reference.png")
        window.setContentSize(compactSize)
        state.openCapture(capture.id)
        await settleNavigation()
        var compactPreview = NSRect.zero
        var expandedPreview = NSRect.zero
        for size in [compactSize, expandedSize, shortSize, compactSize] {
            window.setContentSize(size)
            await settleNavigation()
            let preview = try find(hosting, id: "detail-preview").frame
            let visible = window.convertToScreen(hosting.convert(hosting.bounds, to: nil))
            let save = try find(hosting, id: "detail-save").frame
            try expect(preview.width > 0 && preview.height > 0,
                "Image preview has real native geometry at \(Int(size.width))×\(Int(size.height))")
            try expect(save.width > 0 && save.height > 0 && visible.insetBy(dx: -1, dy: -1).contains(save),
                "Save remains in the viewport at \(Int(size.width))×\(Int(size.height))")
            if size == compactSize {
                if compactPreview == .zero { compactPreview = preview }
                else {
                    try expect(abs(preview.width - compactPreview.width) < 2 && abs(preview.height - compactPreview.height) < 2,
                        "Returning from an expanded window restores compact preview geometry")
                }
            } else if size == expandedSize {
                expandedPreview = preview
                try expect(preview.width > compactPreview.width + 300 && preview.height > compactPreview.height + 80,
                    "The rendered image preview actually enlarges with its window")
                let content = try find(hosting, id: "detail-content").frame
                try expect(content.width > 860 && content.width <= hosting.bounds.width + 2,
                    "Rendered detail content grows beyond its old width cap without overflowing")
            } else {
                try expect(preview.height < expandedPreview.height,
                    "The rendered preview gives vertical space back in a wide, short window")
            }
            try saveImage(hosting, to: evidence.appendingPathComponent("detail-image-\(Int(size.width))x\(Int(size.height))-light.png"))
        }

        var planning = TaskPlanning()
        planning.checklist = [TaskChecklistItem(text: "A saved next step")]
        let savedReminder = Date().addingTimeInterval(7200)
        let task = try state.store.createTask(text: "Fictional responsive task", reminderAt: savedReminder, planning: planning)
        try state.store.update(task, comment: "Saved task context", reminderAt: savedReminder,
                               reminderTimeZoneID: TimeZone.current.identifier)
        _ = try state.store.capture(text: "A related fictional reference", parentTask: task)
        state.openCapture(task.id, focus: "task")
        await settleNavigation()
        guard let draft = state.selectedDraft else { throw NSError(domain: "WorkspaceWindowTests", code: 9) }
        draft.comment = "Unsaved note survives every resize"
        draft.reminderDate = savedReminder.addingTimeInterval(3600)
        let pendingStep = "A next step that has not been added yet"
        let input = try findLabeled(hosting, label: "Add a small next step")
        try expect(input.setText(pendingStep), "Task detail accepts an unfinished checklist entry before resizing")
        await settleNavigation()
        let focusedEditor = window.firstResponder as? NSTextView
        for size in [expandedSize, shortSize, compactSize] {
            window.setContentSize(size)
            await settleNavigation()
            let currentInput = try findLabeled(hosting, label: "Add a small next step")
            let currentText = (currentInput.object as? NSTextField)?.stringValue
                ?? (currentInput.value("accessibilityValue") as? String)
            try expect(currentText == pendingStep,
                "An unfinished checklist entry survives the layout change to \(Int(size.width))×\(Int(size.height))")
            try expect(state.selectedDraft === draft && draft.comment == "Unsaved note survives every resize"
                && draft.reminderDate == savedReminder.addingTimeInterval(3600) && draft.hasChanges,
                "Resizing preserves the same unsaved note and reminder draft")
            try expect(nodes(hosting).contains { $0.identifier == "detail-comment-editor" }
                && nodes(hosting).contains { $0.identifier == "reminder-mode-date" || $0.label == "Date" },
                "Open note and reminder disclosures retain their editors during resize")
            let visible = window.convertToScreen(hosting.convert(hosting.bounds, to: nil))
            let save = try find(hosting, id: "detail-save")
            try expect(save.isEnabled && visible.insetBy(dx: -1, dy: -1).contains(save.frame),
                "Unsaved task changes retain a visible enabled Save action in every window shape")
            if let focusedEditor, focusedEditor.isFieldEditor, window.isKeyWindow {
                try expect(window.firstResponder === focusedEditor,
                    "Task layout changes preserve the active checklist field editor")
            }
            try saveImage(hosting, to: evidence.appendingPathComponent("detail-task-editing-\(Int(size.width))x\(Int(size.height))-light.png"))
        }
        try expect(task.comment == "Saved task context" && task.reminderAt == savedReminder
            && task.taskPlanning?.checklist.count == 1 && draft.planning.checklist.count == 1,
            "Window resizing neither commits draft edits nor adds unfinished checklist input")
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

        try await checkDetailResizing(state: state, hosting: hosting, window: window, evidence: evidence)

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
        try await checkExplorer(state: state, hosting: hosting, window: window, evidence: evidence)
        print("PASS: \(checks) native workspace interaction and responsive layout checks")
        print("Workspace screenshots: \(evidence.path)")
    }
}
