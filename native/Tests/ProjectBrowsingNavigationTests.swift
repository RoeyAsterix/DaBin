import AppKit
import ApplicationServices
import SwiftUI

@MainActor private final class ProjectBrowsingReminderClient: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .denied }
    func requestAuthorization() async throws -> Bool { fatalError("Project browsing QA never requests permission") }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}

@MainActor private struct ProjectBrowsingAXNode {
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



/// Real Board/picker actions on an owned window and fictional UUID archive.
/// No user clipboard, capture permissions, Finder, network or global events.
@main private enum ProjectBrowsingNavigationTests {
    @MainActor private static var checks = 0
    @MainActor private static func expect(_ condition: Bool, _ message: String) throws {
        checks += 1
        if !condition { throw NSError(domain: "ProjectBrowsingNavigationTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    @MainActor private static func settle() async {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(100))
        pumpRunLoop()
    }
    @MainActor private static func pumpRunLoop() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
    }
    @MainActor private static func nodes(_ view: NSView) -> [ProjectBrowsingAXNode] {
        view.layoutSubtreeIfNeeded()
        var seen = Set<ObjectIdentifier>(), result: [ProjectBrowsingAXNode] = []
        func visit(_ value: Any, depth: Int) {
            guard depth < 50, let object = value as? NSObject,
                  seen.insert(ObjectIdentifier(object)).inserted else { return }
            let node = ProjectBrowsingAXNode(object: object)
            result.append(node); node.children.forEach { visit($0, depth: depth + 1) }
        }
        visit(view, depth: 0)
        NSAccessibility.unignoredChildren(from: [view]).forEach { visit($0, depth: 0) }
        return result
    }
    @MainActor private static func allNodes() -> [ProjectBrowsingAXNode] {
        NSApp.windows.filter(\.isVisible).compactMap(\.contentView).flatMap(nodes)
    }
    @MainActor private static func find(id: String? = nil, label: String? = nil) async throws -> ProjectBrowsingAXNode {
        for _ in 0..<10 {
            let matches = allNodes().filter { node in
                if let id { return node.identifier == id }
                return node.label == label || (node.object as? NSTextField)?.placeholderString == label
            }
            if let match = matches.first(where: { $0.object is NSTextField })
                ?? matches.first(where: { $0.object.responds(to: NSSelectorFromString("accessibilityPerformPress")) })
                ?? matches.first { return match }
            await settle()
        }
        throw NSError(domain: "ProjectBrowsingNavigationTests", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Missing owned native control \(id ?? label ?? "unknown"); \(allNodes().compactMap { $0.identifier ?? $0.label }.joined(separator: "; "))"])
    }
    @MainActor private static func press(id: String? = nil, label: String? = nil) async throws {
        let node = try await find(id: id, label: label)
        try expect(node.isEnabled && node.press(), "Enabled real native action activates: \(id ?? label ?? "")")
        await settle()
    }
    @MainActor private static func type(_ text: String, placeholder: String) async throws {
        let field = try await find(label: placeholder)
        try expect(field.object is NSTextField && field.setText(text), "Native field editor accepts \(placeholder)")
        await settle()
    }
    @MainActor private static func install(_ view: AnyView, in window: NSWindow) async {
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        window.contentView = hosting; window.makeKeyAndOrderFront(nil)
        await settle()
        _ = await Task.detached {
            let process = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            AXUIElementSetMessagingTimeout(process, 3)
            var windows: CFTypeRef?
            return AXUIElementCopyAttributeValue(process, kAXWindowsAttribute as CFString, &windows)
        }.value
        await settle()
    }
    @MainActor private static func choose(_ title: String) async throws {
        try await press(id: "workspace-project-picker")
        try await press(label: "Project " + title)
        try expect(!allNodes().contains { $0.identifier == "project-picker-search" },
            "Successful project selection closes only its own picker")
    }
    @MainActor private static func boardNavigation(_ state: AppState, window: NSWindow, defaults: UserDefaults) async throws {
        state.workspace.mode = .collection
        state.openLibrary(); state.navigateProject("Fictional Alpha")
        await install(AnyView(BoardView(state: state, theme: ThemeSettings(defaults: defaults))), in: window)
        let initial = state.navigationHistory.index
        try await choose("All projects")
        try expect(state.libraryProject == nil && !state.workspace.explorerUnfiledOnly,
            "Actual Board picker opens All projects, distinct from Unfiled")
        try await choose("Unfiled")
        try expect(state.libraryProject == nil && state.workspace.explorerUnfiledOnly,
            "Actual Board picker opens the explicit Unfiled scope")
        try await choose("Fictional Beta")
        try expect(state.libraryProject == "Fictional Beta" && !state.workspace.explorerUnfiledOnly
            && state.workspace.selectedProject == "Fictional Beta" && state.workspace.mode == .collection,
            "Named selection keeps collection mode and matches persisted project preference")
        try expect(state.navigationHistory.index == initial + 3,
            "All, Unfiled and named choices each add exactly one deliberate history visit")
        try await press(id: "board-back")
        try expect(state.libraryProject == nil && state.workspace.explorerUnfiledOnly,
            "Real Back restores the distinct Unfiled destination")
        try await press(id: "board-back")
        try expect(state.libraryProject == nil && !state.workspace.explorerUnfiledOnly,
            "Second real Back restores All projects")
        try await press(id: "board-forward")
        try expect(state.libraryProject == nil && state.workspace.explorerUnfiledOnly,
            "Real Forward restores Unfiled without conflating it with All projects")
        try await press(id: "board-forward")
        try expect(state.libraryProject == "Fictional Beta", "Second real Forward restores the named project")

        for blocked in [true, false] {
            state.navigationWindowInteractionBlocked = blocked; await settle()
            try expect(try await find(id: "workspace-project-picker").isEnabled == !blocked,
                "Browsing picker exposes navigation-blocked state to native accessibility")
        }
        try await press(id: "workspace-project-picker")
        _ = try await find(label: "Project Fictional Alpha")
        let previousHistory = state.navigationHistory
        state.navigationWindowInteractionBlocked = true; await settle()
        // The already open panel may inherit disabled state; an explicit press
        // must still never be interpreted as a successful choice/dismissal.
        _ = try await find(label: "Project Fictional Alpha").press()
        await settle()
        try expect(state.libraryProject == "Fictional Beta" && state.navigationHistory.entries == previousHistory.entries
            && state.navigationHistory.index == previousHistory.index,
            "A blocker appearing after opening cannot change scope or record navigation")
        _ = try await find(id: "project-picker-search")
        state.navigationWindowInteractionBlocked = false; await settle()
        try await press(label: "Project Fictional Alpha")
        try expect(state.libraryProject == "Fictional Alpha" && state.navigationHistory.index == previousHistory.index + 1,
            "The same open picker selects exactly once after the blocker clears")

        let savedScope = state.workspace.snapshot
        let savedHistory = state.navigationHistory
        let transition = state.navigationTransitionRevision
        state.workspace.failureInjector = { throw CocoaError(.fileWriteNoPermission) }
        try await press(id: "workspace-project-picker")
        try await press(label: "Project Fictional Beta")
        _ = try await find(id: "project-picker-error")
        try expect(state.libraryProject == "Fictional Alpha" && state.workspace.snapshot == savedScope
            && state.navigationHistory.entries == savedHistory.entries && state.navigationHistory.index == savedHistory.index
            && state.navigationTransitionRevision == transition,
            "Failed native scope persistence changes no visible/persisted scope, history branch or transition")
        state.workspace.failureInjector = nil
        try await press(label: "Project Fictional Beta")
        try expect(state.libraryProject == "Fictional Beta" && state.workspace.selectedProject == "Fictional Beta"
            && state.navigationHistory.index == savedHistory.index + 1,
            "The still-open picker retries its failed scope selection exactly once")
        try expect(WorkspaceStore(root: state.store.root).selectedProject == "Fictional Beta",
            "Retried selection survives a fresh workspace reopen")

        state.workspace.failureInjector = { throw CocoaError(.fileWriteNoPermission) }
        do { try state.workspace.setScratchpad(text: "Pending synthetic notes remain recoverable", project: "Fictional Beta") }
        catch { }
        state.workspace.failureInjector = nil
        try expect(state.workspace.error != nil, "No-op selection fixture retains an unrelated failed note-save error")
        let beforeNoOp = state.navigationHistory.index
        try await choose("Fictional Beta")
        try expect(state.navigationHistory.index == beforeNoOp && state.libraryProject == "Fictional Beta"
            && state.workspace.scratchpad(project: "Fictional Beta") == "Pending synthetic notes remain recoverable",
            "Successful same-scope choice dismisses despite an older error and keeps the pending note")
        try state.workspace.setScratchpad(text: state.workspace.scratchpad(project: "Fictional Beta"), project: "Fictional Beta")
        try await choose("Fictional Alpha")
    }

    @MainActor private static func noteEditor(in window: NSWindow, expected: String) async throws -> NSTextView {
        for _ in 0..<10 {
            if let content = window.contentView,
               let editor = nodes(content).compactMap({ $0.object as? NSTextView }).first(where: {
                   $0.isEditable && !$0.isFieldEditor && $0.window === window && $0.string == expected
               }) { return editor }
            await settle()
        }
        throw NSError(domain: "ProjectBrowsingNavigationTests", code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Missing owned editable project notes with the expected text"])
    }
    @MainActor private static func editNotes(_ text: String, state: AppState, window: NSWindow) async throws {
        let editor = try await noteEditor(in: window, expected: state.workspace.scratchpad(project: state.libraryProject))
        try expect(window.makeFirstResponder(editor), "The owned native project-note editor accepts focus")
        editor.insertText(text, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        await settle()
        try expect(state.workspace.scratchpad(project: state.libraryProject) == text,
            "Native note typing updates only the selected project's live text")
    }
    @MainActor private static func notesAcrossProjects(_ state: AppState, window: NSWindow) async throws {
        state.navigateProject("Fictional Alpha")
        state.navigateWorkspaceMode(.scratchpad)
        await settle()
        let alpha = "Alpha project native notes — שלום 日本語"
        let beta = "Beta project native notes remain separate"
        try await editNotes(alpha, state: state, window: window)
        try await choose("Fictional Beta")
        try await editNotes(beta, state: state, window: window)
        try await press(id: "board-back")
        try expect(state.libraryProject == "Fictional Alpha" && state.workspace.mode == .scratchpad,
            "Native Back from Notes restores the preceding project and editor mode")
        _ = try await noteEditor(in: window, expected: alpha)
        try expect(state.workspace.scratchpad(project: "Fictional Beta") == beta
            && WorkspaceStore(root: state.store.root).scratchpad(project: "Fictional Alpha") == alpha,
            "Both typed project notes remain separate and durable after navigation")

        let pending = "Alpha unsaved edit survives failed scope change and retry"
        state.workspace.failureInjector = { throw CocoaError(.fileWriteNoPermission) }
        try await editNotes(pending, state: state, window: window)
        try expect(state.workspace.pendingScratchpads[WorkspaceSnapshot.projectKey("Fictional Alpha")] == pending
            && WorkspaceStore(root: state.store.root).scratchpad(project: "Fictional Alpha") == alpha,
            "Failed native autosave retains exact pending text without overwriting the prior disk note")
        let history = state.navigationHistory
        try await press(id: "workspace-project-picker")
        try await press(label: "Project Fictional Beta")
        _ = try await find(id: "project-picker-error")
        try expect(state.libraryProject == "Fictional Alpha" && state.navigationHistory.entries == history.entries
            && state.navigationHistory.index == history.index && state.workspace.scratchpad(project: "Fictional Alpha") == pending,
            "Failed picker persistence preserves both pending note owner and history position")
        state.workspace.failureInjector = nil
        try await press(label: "Project Fictional Beta")
        _ = try await noteEditor(in: window, expected: beta)
        try expect(state.workspace.pendingScratchpads[WorkspaceSnapshot.projectKey("Fictional Alpha")] == pending,
            "Retrying project navigation never silently commits or discards the other project's failed note")
        try await press(id: "board-back")
        _ = try await noteEditor(in: window, expected: pending)
        try await press(label: "Retry save")
        try expect(state.workspace.pendingScratchpads[WorkspaceSnapshot.projectKey("Fictional Alpha")] == nil
            && WorkspaceStore(root: state.store.root).scratchpad(project: "Fictional Alpha") == pending
            && state.workspace.scratchpad(project: "Fictional Beta") == beta,
            "Visible Retry save commits the restored pending note and preserves the neighboring project")
    }

    @MainActor private static func panelPrecommit(_ state: AppState, window: NSWindow) async throws {
        var selections = 0, dismissals = 0
        let panel = ProjectPickerPanel(state: state, selectedProject: "Fictional Alpha", allowsAll: true,
            validateSelection: {
                guard !state.isNavigationBlocked else {
                    throw WorkspaceError.unavailable("Finish the current interaction before choosing a project.")
                }
            }, onSelect: { _, _ in selections += 1 }, onDismiss: { dismissals += 1 })
        await install(AnyView(panel.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)), in: window)
        state.navigationWindowInteractionBlocked = true; await settle()
        try await press(label: "Project Fictional Beta")
        _ = try await find(id: "project-picker-error")
        try expect(selections == 0 && dismissals == 0 && state.libraryProject == "Fictional Alpha",
            "Shared panel rejects a late browsing blocker before invoking selection or dismissal")
        state.navigationWindowInteractionBlocked = false; await settle()
        try await press(id: "project-picker-new")
        try await type("Fictional guarded creation", placeholder: "Client or project name")
        let before = state.workspace.snapshot
        state.navigationWindowInteractionBlocked = true; await settle()
        try await press(id: "project-picker-create")
        _ = try await find(id: "project-picker-error")
        try expect(state.workspace.snapshot == before && selections == 0 && dismissals == 0,
            "Late blocked creation publishes no marker, color, workspace edit, selection or dismissal")
        let typed = try await find(label: "Client or project name")
        try expect((typed.object as? NSTextField)?.stringValue == "Fictional guarded creation",
            "Rejected creation keeps the user's typed project name for retry")
        state.navigationWindowInteractionBlocked = false; await settle()
        try await press(id: "project-picker-create")
        try expect(state.workspace.projectNames.filter { $0 == "Fictional guarded creation" }.count == 1
            && selections == 1 && dismissals == 1,
            "Unblocked retry creates one marker and invokes selection and dismissal exactly once")
        let reopened = WorkspaceStore(root: state.store.root)
        try expect(reopened.projectNames.contains("Fictional guarded creation")
            && reopened.projectColorHex(for: "Fictional guarded creation") == state.workspace.projectColorHex(for: "Fictional guarded creation"),
            "Successful retry persists its project marker and color across reopen")

        selections = 0; dismissals = 0
        state.navigationWindowInteractionBlocked = true
        // Capture filing has no browsing guard by default: metadata editing is
        // intentionally separate from route navigation and remains available.
        await install(AnyView(ProjectPickerPanel(state: state, selectedProject: nil,
            onSelect: { _, _ in selections += 1 }, onDismiss: { dismissals += 1 })
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)), in: window)
        try await press(label: "Project Fictional Beta")
        try expect(selections == 1 && dismissals == 1,
            "The optional browsing policy does not globally disable metadata filing panels")
        state.navigationWindowInteractionBlocked = false
    }

    @MainActor static func main() async throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory); application.finishLaunching()
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("DaBin-ProjectBrowsing-\(UUID())")
        let suite = "DaBinProjectBrowsing.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let store = try CaptureStore(root: root)
        let previews = PreviewService(store: store, defaults: defaults)
        let auto = AutoCaptureService(settings: AutoCaptureSettings(defaults: defaults), input: InputService(store: store),
            pasteboardProvider: { fatalError("Project browsing QA never reads user clipboard") }, sourceApplicationProvider: { nil })
        let state = AppState(store: store, previews: previews,
            reminders: ReminderService(store: store, client: ProjectBrowsingReminderClient()), autoCapture: auto,
            captureClipboard: CaptureClipboardService(writer: { _ in fatalError("Project browsing QA never writes user clipboard") }),
            folderOpener: { _ in fatalError("Project browsing QA never opens Finder") })
        defer {
            state.shutdownNotificationPresentation(); state.focusSessions.shutdown(); store.cancelArchiveRepair()
            auto.shutdown(); previews.shutdown(); defaults.removePersistentDomain(forName: suite)
            try? files.removeItem(at: root)
        }
        try state.workspace.createProject(name: "Fictional Alpha", colorHex: "7568D8")
        try state.workspace.createProject(name: "Fictional Beta", colorHex: "3478D4")
        _ = try store.createNote(text: "Synthetic alpha note", projectName: "Fictional Alpha")
        _ = try store.createNote(text: "Synthetic beta note", projectName: "Fictional Beta")
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 380, height: 680),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        application.activate(ignoringOtherApps: true)
        try await boardNavigation(state, window: window, defaults: defaults)
        try await notesAcrossProjects(state, window: window)
        try await panelPrecommit(state, window: window)
        state.isBoardVisible = false
        print("PASS: \(checks) native project browsing checks; real Board All/Unfiled/named history, native cross-project Notes/retry, late-blocked selection/creation and metadata-filing isolation")
    }
}
