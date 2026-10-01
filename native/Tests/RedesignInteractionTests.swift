import AppKit
import ApplicationServices
import SwiftUI

@MainActor private final class RedesignReminderClient: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .allowed }
    func requestAuthorization() async throws -> Bool { false }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}

@MainActor private struct RedesignAXNode {
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


@MainActor private final class RedesignSelection {
    var project: String?
    var all = false
    var dismissals = 0
}

/// Native, own-process controls only. This harness uses fictional captures,
/// temporary storage and an injected clipboard writer/notification client.
@main private enum RedesignInteractionTests {
    @MainActor private static var checks = 0
    @MainActor private static func expect(_ condition: Bool, _ message: String) throws {
        checks += 1
        if !condition { throw NSError(domain: "RedesignInteractionTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    @MainActor private static func settle() async {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(140))
        pumpRunLoop()
    }
    @MainActor private static func pumpRunLoop() { RunLoop.main.run(until: Date().addingTimeInterval(0.08)) }
    @MainActor private static func nodes(_ view: NSView) -> [RedesignAXNode] {
        view.layoutSubtreeIfNeeded()
        var seen = Set<ObjectIdentifier>(); var result: [RedesignAXNode] = []
        func visit(_ value: Any, depth: Int) {
            guard depth < 50, let object = value as? NSObject, seen.insert(ObjectIdentifier(object)).inserted else { return }
            let node = RedesignAXNode(object: object); result.append(node)
            node.children.forEach { visit($0, depth: depth + 1) }
        }
        visit(view, depth: 0)
        NSAccessibility.unignoredChildren(from: [view]).forEach { visit($0, depth: 0) }
        return result
    }
    @MainActor private static func allNodes() -> [RedesignAXNode] {
        // Popovers are separate native windows owned by this test process.
        NSApp.windows.filter(\.isVisible).compactMap(\.contentView).flatMap(nodes)
    }
    @MainActor private static func find(id: String) async throws -> RedesignAXNode {
        for _ in 0..<8 {
            if let value = allNodes().first(where: { $0.identifier == id }) { return value }
            await settle()
        }
        throw missing(id)
    }
    @MainActor private static func find(label: String) async throws -> RedesignAXNode {
        for _ in 0..<8 {
            let available = allNodes()
            if let field = available.first(where: { ($0.object as? NSTextField)?.placeholderString == label }) { return field }
            if let value = available.first(where: { $0.label == label && $0.object.responds(to: NSSelectorFromString("accessibilityPerformPress")) }) { return value }
            if let value = available.first(where: { $0.label == label }) { return value }
            await settle()
        }
        throw missing(label)
    }
    @MainActor private static func missing(_ name: String) -> NSError {
        fputs("Redesign controls: \(allNodes().compactMap { $0.identifier ?? $0.label }.joined(separator: "; "))\n", stderr)
        return NSError(domain: "RedesignInteractionTests", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Missing native redesign control: \(name)"])
    }
    @MainActor private static func press(id: String) async throws {
        try expect(try await find(id: id).press(), "Native action activates: \(id)")
        await settle()
    }
    @MainActor private static func press(label: String) async throws {
        try expect(try await find(label: label).press(), "Native action activates: \(label)")
        await settle()
    }
    @MainActor private static func type(_ text: String, label: String) async throws {
        try expect(try await find(label: label).setText(text), "Native editor accepts \(label)")
        await settle()
    }
    @MainActor private static func key(_ characters: String, code: UInt16, in window: NSWindow) async throws {
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: code) else { throw missing("synthetic own-window key event") }
        window.sendEvent(event)
        await settle()
    }
    @MainActor private static func snapshot(_ view: NSView, at url: URL) throws {
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw missing("snapshot bitmap") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw missing("snapshot PNG") }
        try data.write(to: url, options: .atomic)
    }
    @MainActor private static func install(_ view: AnyView, in window: NSWindow) async -> NSHostingView<AnyView> {
        let hosting = NSHostingView(rootView: view)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        await settle()
        // Request our own application AX windows to initialize SwiftUI's virtual
        // accessibility children alongside native NSTextField subviews.
        _ = await Task.detached {
            let process = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            AXUIElementSetMessagingTimeout(process, 3)
            var windows: CFTypeRef?
            return AXUIElementCopyAttributeValue(process, kAXWindowsAttribute as CFString, &windows)
        }.value
        await settle()
        return hosting
    }

    @MainActor private static func projectPanel(state: AppState, result: RedesignSelection,
                                                startCreating: Bool = false) -> AnyView {
        AnyView(ProjectPickerPanel(state: state, selectedProject: nil, startCreating: startCreating,
            onSelect: { name, all in result.project = name; result.all = all },
            onDismiss: { result.dismissals += 1 })
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).padding(8)
            .background(Palette.background))
    }

    @MainActor private static func checkProjectPicker(state: AppState, window: NSWindow, evidence: URL) async throws {
        try state.workspace.setScratchpad(text: "", project: "Client Alpha")
        try state.workspace.setScratchpad(text: "", project: "Client Beta")
        let chosen = RedesignSelection()
        let hosting = await install(projectPanel(state: state, result: chosen), in: window)
        try await type("Client", label: "Find a project")
        let matches = allNodes().contains { $0.label == "Project Client Alpha" }
            && allNodes().contains { $0.label == "Project Client Beta" }
        if !matches { fputs("Project search diagnostics: \(allNodes().compactMap(\.label).joined(separator: "; "))\n", stderr) }
        try snapshot(hosting, at: evidence.appendingPathComponent("project-picker-search.png"))
        try expect(matches, "Project search shows matching projects")
        try await key("\u{F701}", code: 125, in: window)
        try await key("\r", code: 36, in: window)
        try expect(chosen.project == "Client Beta" && chosen.dismissals == 1,
            "Arrow Down and Return choose the next matching project and dismiss")
        try snapshot(hosting, at: evidence.appendingPathComponent("project-picker-keyboard.png"))

        let created = RedesignSelection()
        _ = await install(projectPanel(state: state, result: created), in: window)
        try await press(id: "project-picker-new")
        try await type("  Client Gamma  ", label: "Client or project name")
        try await press(id: "project-picker-create")
        try expect(created.project == "Client Gamma" && state.workspace.projectNames.contains("Client Gamma"),
            "Inline creation trims the name, persists the project and selects it")
        try expect(created.dismissals == 1, "Successful project creation dismisses exactly once")

        let duplicate = RedesignSelection()
        let duplicateView = await install(projectPanel(state: state, result: duplicate, startCreating: true), in: window)
        try await type("client ALPHA", label: "Client or project name")
        try await press(id: "project-picker-create")
        _ = try await find(id: "project-picker-error")
        try expect(duplicate.dismissals == 0 && duplicate.project == nil,
            "Duplicate names show inline feedback without selecting or closing")
        try snapshot(duplicateView, at: evidence.appendingPathComponent("project-picker-duplicate.png"))
        try await press(label: "Cancel")
        _ = try await find(id: "project-picker-search")
        try expect(duplicate.dismissals == 0, "Cancel creation returns to project search")
        try await press(id: "project-picker-new")
        try await key("\u{1b}", code: 53, in: window)
        _ = try await find(id: "project-picker-search")
        try expect(duplicate.dismissals == 0, "Escape dismisses the inner creation form first")
        try await key("\u{1b}", code: 53, in: window)
        try expect(duplicate.dismissals == 1, "Escape closes project search after its inner form (dismissals: \(duplicate.dismissals), responder: \(String(describing: window.firstResponder)))")
    }

    @MainActor private static func checkNoManualPasteAddition(context: String) throws {
        let controls = allNodes()
        try expect(!controls.contains { $0.identifier?.hasPrefix("capture-trail-add-") == true
            || $0.identifier == "capture-trail-custom-app" },
            "\(context) has no manual-paste plus button or custom destination editor")
        try expect(!controls.contains {
            guard let label = $0.label else { return false }
            return label.hasPrefix("Record a paste") || label.hasPrefix("Record paste to ")
                || label == "Record custom paste destination" || label.hasPrefix("Another app or product")
        }, "\(context) has no Record-paste action or destination picker")
    }

    @MainActor private static func encodedSnapshot(_ capture: Capture) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(CaptureSnapshot(capture))
    }

    @MainActor private static func checkCapture(state: AppState, window: NSWindow, evidence: URL,
                                               clipboardWrites: () -> [CaptureClipboardPayload]) async throws {
        let capture = try state.store.createNote(text: "Review the fictional client’s design feedback", projectName: nil)
        let original = (id: capture.id, originalText: capture.originalText, captureDay: capture.captureDay)
        state.openInbox(); state.isBoardVisible = true
        let route = state.route
        let hosting = await install(AnyView(ScrollView {
            CaptureRow(state: state, capture: capture, featured: false).padding(12)
        }.background(Palette.background)), in: window)
        try checkNoManualPasteAddition(context: "The ordinary capture card")
        try snapshot(hosting, at: evidence.appendingPathComponent("capture-before-conversion-380.png"))
        try await press(id: "capture-convert-to-task-\(capture.id.uuidString)")
        try expect(capture.isTask && capture.id == original.id && capture.originalText == original.originalText
            && capture.captureDay == original.captureDay && state.route == route,
            "Task conversion preserves capture identity, original content, receipt and current route")
        try expect(window.contentLayoutRect.width == 380 && window.contentLayoutRect.height == 430,
            "In-place conversion leaves window geometry unchanged")
        _ = try await find(id: "capture-conversion-undo-\(capture.id.uuidString)")
        try expect(state.configureTaskFocus(capture, hours: 1, minutes: 30, start: false), "Saved duration fixture commits")
        try await press(id: "task-focus-duration-\(capture.id.uuidString)")
        let initialHours = try await find(label: "Hours").object as? NSTextField
        let initialMinutes = try await find(label: "Minutes").object as? NSTextField
        try expect(initialHours?.stringValue == "1" && initialMinutes?.stringValue == "30",
            "First duration opening shows the persisted hours and minutes")
        try await type("0", label: "Hours")
        try await type("2", label: "Minutes")
        try await press(label: "Save")
        try expect(capture.taskPlanning?.effortMinutes == 2 && capture.taskPlanning?.focusSession?.isRunning != true,
            "Duration setup saves without starting a timer")
        try await press(id: "task-focus-play-\(capture.id.uuidString)")
        try expect(capture.taskPlanning?.focusSession?.isRunning == true, "Task play starts the persisted focus session")
        try await press(id: "task-focus-play-\(capture.id.uuidString)")
        try expect(capture.taskPlanning?.focusSession?.isRunning == false
            && (capture.taskPlanning?.focusSession?.remainingSeconds ?? 0) > 0,
            "Task pause stores remaining time without completing the task")
        try expect(!capture.isCompleted && capture.reminderAt == nil, "Focus controls do not complete work or create a reminder")
        let workday = CaptureCalendar.dayString(Date().addingTimeInterval(2 * 86_400))
        try expect(state.scheduleTask(capture, day: workday, time: "09:30"), "Saved schedule fixture commits")
        try await press(id: "task-focus-schedule-\(capture.id.uuidString)")
        let plannedTime = try await find(label: "HH:MM · optional").object as? NSTextField
        try expect(plannedTime?.stringValue == "09:30", "First schedule opening shows the persisted local time")
        try await press(label: "Cancel")
        try expect(capture.taskPlanning?.plannedDay == workday && capture.taskPlanning?.plannedTime == "09:30",
            "Cancelling the schedule form preserves the saved plan")
        try snapshot(hosting, at: evidence.appendingPathComponent("task-after-conversion-380.png"))

        try expect(capture.pasteHistory.isEmpty, "A capture begins without fabricated paste history")
        try checkNoManualPasteAddition(context: "The task card")
        let manual = try state.store.recordPasteDestination(for: capture,
            applicationName: "Fictional proofing tool", at: capture.capturedAt.addingTimeInterval(1))
        // Seed historical confirmed evidence directly in this fictional fixture.
        // The user-facing record API remains unable to fabricate confirmation.
        let confirmed = CapturePasteEvent(applicationName: "Notes",
            applicationBundleIdentifier: "com.apple.Notes", recordedAt: capture.capturedAt.addingTimeInterval(2),
            evidence: .confirmed)
        capture.setPasteHistory(capture.pasteHistory + [confirmed])
        try state.store.save(captures: [capture])
        let existingHistory = capture.pasteHistory
        let existingSnapshot = try encodedSnapshot(capture)
        try await press(id: "capture-trail-\(capture.id.uuidString)")
        for (index, visible) in NSApp.windows.filter(\.isVisible).enumerated() {
            if let content = visible.contentView { try snapshot(content, at: evidence.appendingPathComponent("trail-history-window-\(index).png")) }
        }
        try checkNoManualPasteAddition(context: "The content-trail history")
        try expect(allNodes().contains { $0.label == CaptureSourcePresentation.origin(for: capture).name },
            "Opening the content trail still displays the capture's recorded source")
        try expect(allNodes().contains { $0.label?.contains("Recorded by you") == true }
            && allNodes().contains { $0.label?.contains("Confirmed paste") == true },
            "History retains both legacy manual and confirmed evidence labels")
        try expect(capture.pasteHistory == existingHistory && (try encodedSnapshot(capture)) == existingSnapshot,
            "Viewing history does not add, remove or rewrite existing capture receipts")
        try await press(label: "Close content trail")
        let reopened = try CaptureStore(root: state.store.root)
        guard let persisted = reopened.captures.first(where: { $0.id == capture.id }) else {
            throw missing("Persisted read-only trail fixture")
        }
        try expect(persisted.pasteHistory == existingHistory && (try encodedSnapshot(persisted)) == existingSnapshot,
            "Opening and closing history leaves the complete persisted capture record untouched")

        try await press(id: "capture-trail-\(capture.id.uuidString)")
        try expect(!allNodes().contains { $0.label == "Remove recorded paste to Notes" },
            "Confirmed evidence cannot be removed through the manual receipt action")
        try await press(label: "Remove recorded paste to Fictional proofing tool")
        try expect(capture.pasteHistory == [confirmed] && !capture.pasteHistory.contains(manual),
            "Removing an old manual receipt preserves the confirmed paste")
        _ = try await find(id: "capture-trail-success")
        try checkNoManualPasteAddition(context: "The history after a manual receipt removal")
        try await press(label: "Close content trail")
        let remainingHistory = capture.pasteHistory
        let writesBeforeCopy = clipboardWrites().count
        try await press(id: CaptureCopyButton.accessibilityIdentifier(for: [capture]))
        try expect(clipboardWrites().count == writesBeforeCopy + 1
            && clipboardWrites().last?.items == [.text(original.originalText ?? "")],
            "The card's normal Copy button still copies its original content exactly once")
        try expect(capture.pasteHistory == remainingHistory,
            "Copying content does not fabricate a paste destination receipt")
        window.setContentSize(NSSize(width: 1000, height: 700)); await settle()
        try expect(capture.pasteHistory == remainingHistory && capture.isTask && !capture.isCompleted,
            "Expanding the card preserves task and provenance state")
        try snapshot(hosting, at: evidence.appendingPathComponent("task-expanded-1000.png"))
        window.setContentSize(NSSize(width: 380, height: 430)); await settle()
        try expect(window.contentLayoutRect.width == 380, "Resizing back restores compact content width")

        for (minimized, showsCopy) in [(false, true), (true, true), (false, false)] {
            if capture.isMinimized != minimized { state.toggleMinimized(capture) }
            _ = await install(AnyView(ScrollView {
                CaptureRow(state: state, capture: capture, featured: false,
                           showsCopyButton: showsCopy).padding(12)
            }.background(Palette.background)), in: window)
            let trash = try await find(id: "capture-trash-\(capture.id.uuidString)")
            try expect(trash.isEnabled && trash.interactionFrame.width > 0 && trash.interactionFrame.height > 0,
                "Trash stays directly reachable; minimized=\(minimized), copy=\(showsCopy)")
            try await press(id: "capture-trash-\(capture.id.uuidString)")
            try expect(state.pendingRemoval === capture && state.store.captures.contains { $0 === capture },
                "The visible trash button only requests confirmation and retains the selected capture")
            state.pendingRemoval = nil
            await settle()
            try expect(state.store.captures.contains { $0 === capture } && capture.deletedAt == nil,
                "Cancelling removal keeps the capture intact")
        }
        let otherIDs = Set(state.store.captures.map(\.id)).subtracting([capture.id])
        try await press(id: "capture-trash-\(capture.id.uuidString)")
        state.confirmRemoval()
        for _ in 0..<12 {
            if state.removingCaptureID == nil && !state.store.captures.contains(where: { $0.id == capture.id }) { break }
            await settle()
        }
        try expect(Set(state.store.captures.map(\.id)) == otherIDs
            && state.store.trashedCaptures.contains { $0.id == capture.id } && state.canUndoRemoval,
            "Confirming visible-button removal moves only the selected record to recoverable trash")
        await state.undoLastRemoval()
        await settle()
        let restored = state.store.captures.first { $0.id == capture.id }
        try expect(restored?.originalText == original.originalText && restored?.isTask == true
            && restored?.pasteHistory == remainingHistory && restored?.deletedAt == nil
            && !state.store.trashedCaptures.contains { $0.id == capture.id },
            "Undo restores the removed task with its original content and remaining confirmed provenance")
    }

    @MainActor static func main() async throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory); application.finishLaunching()
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("DaBin-Redesign-\(UUID())")
        let suite = "DaBinRedesign.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? files.removeItem(at: root) }
        let store = try CaptureStore(root: root)
        let previews = PreviewService(store: store, defaults: defaults)
        defer { previews.shutdown() }
        var clipboardPayloads: [CaptureClipboardPayload] = []
        let state = AppState(store: store, previews: previews,
            reminders: ReminderService(store: store, client: RedesignReminderClient()),
            captureClipboard: CaptureClipboardService(writer: { clipboardPayloads.append($0); return true }))
        let evidence = URL(fileURLWithPath: files.currentDirectoryPath)
            .appendingPathComponent("build/qa/redesign-interactions", isDirectory: true)
        try files.createDirectory(at: evidence, withIntermediateDirectories: true)
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 380, height: 430),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        application.activate(ignoringOtherApps: true)
        try await checkProjectPicker(state: state, window: window, evidence: evidence)
        try await checkCapture(state: state, window: window, evidence: evidence,
                               clipboardWrites: { clipboardPayloads })
        state.isBoardVisible = false
        print("PASS: \(checks) native redesign interaction checks")
        print("Redesign screenshots: \(evidence.path)")
    }
}
