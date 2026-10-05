import AppKit
import ApplicationServices
import Darwin
import Foundation
import SwiftUI

@MainActor private final class DeletionFixtureWindow: NSWindow {
    override var backingScaleFactor: CGFloat { 2 }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor private final class DeletionFixtureNotifications: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .undetermined }
    func requestAuthorization() async throws -> Bool { false }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}

@MainActor private struct DeletionAX {
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
    var role: String { (value("accessibilityRole") as? String) ?? (attribute("AXRole") as? String) ?? "" }
    var frame: NSRect {
        let selector = NSSelectorFromString("accessibilityFrame")
        guard object.responds(to: selector) else { return .zero }
        typealias Getter = @convention(c) (AnyObject, Selector) -> NSRect
        return unsafeBitCast(object.method(for: selector), to: Getter.self)(object, selector)
    }
    var interactionFrame: NSRect {
        if let cell = object as? NSCell, let view = cell.controlView as? NSControl, view.cell === cell, let window = view.window {
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
    func showMenu() -> Bool {
        let selector = NSSelectorFromString("accessibilityPerformShowMenu")
        guard object.responds(to: selector) else { return false }
        typealias Action = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(object.method(for: selector), to: Action.self)(object, selector)
    }
    var actions: [String] { (value("accessibilityActionNames") as? [String]) ?? [] }
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

@MainActor private final class DeletionMenuTracking {
    let deadline = ProcessInfo.processInfo.systemUptime + 2
    weak var window: NSWindow?
    private(set) var menus: [NSMenu] = []
    private(set) var ended = Set<ObjectIdentifier>()
    private(set) var timedOut = false
    init(window: NSWindow?) { self.window = window }
    func began(_ menu: NSMenu) {
        if !menus.contains(where: { $0 === menu }) { menus.append(menu) }
        fputs("MENU tracking began: \(menu.items.map(\.title))\n", stderr)
    }
    func didEnd(_ menu: NSMenu) {
        ended.insert(ObjectIdentifier(menu)); fputs("MENU tracking ended\n", stderr)
    }
    func cancel() {
        menus.forEach { $0.cancelTrackingWithoutAnimation() }
        guard ProcessInfo.processInfo.systemUptime >= deadline else { return }
        timedOut = true
        // A bounded fallback for a menu implementation that hasn't delivered
        // its notification yet. This event is queued only in the test process
        // and carries the fixture's own window number; no global input is sent.
        guard let window, let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53) else { return }
        NSApp.postEvent(escape, atStart: true)
    }
}


@MainActor private struct DeletionSearchFixture: View {
    let state: AppState
    let item: SearchDateItem
    @FocusState private var focus: String?
    var body: some View { SearchResultCard(state: state, item: item, expanded: false, focus: $focus) }
}

@MainActor private struct DeletionProjectFixture: View {
    let state: AppState
    let note: WorkspaceScratchpad
    @FocusState private var focus: String?
    var body: some View {
        ProjectWorkspaceCard(state: state, item: .note(note), selected: false, compact: false,
            color: .purple, focus: $focus, open: {}, select: {}, details: {}, makeTask: {},
            earlier: {}, later: {}, canReorder: false, drag: { [] })
    }
}

/// Only fictional content, own-process native menus and offscreen fixture windows.
/// A retained delegate and explicit completion marker make partial exits fail QA.
@main @MainActor private final class CardDeletionInteractionTests: NSObject, NSApplicationDelegate {
    private static var checks = 0
    private var result: Int32 = 1
    static func main() {
        let app = NSApplication.shared, delegate = CardDeletionInteractionTests()
        app.setActivationPolicy(.accessory); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        exit(delegate.result)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do {
                try await Self.run()
                print("COMPLETE: CardDeletionInteractionTests finished every fixture and cleanup")
                result = 0
            } catch { fputs("FAIL: Card deletion QA: \(error)\n", stderr) }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "CardDeletionInteractionTests", code: checks, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        guard try condition() else { throw failure(message) }
    }

    private static func settle(_ view: NSView) async throws {
        let started = ContinuousClock.now
        for _ in 0..<6 { view.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(35)) }
        try expect(ContinuousClock.now - started < .seconds(4), "Project workspace settles without starving the run loop")
    }

    private static func table(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        return view.subviews.lazy.compactMap { table(in: $0) }.first
    }

    /// A table's complete accessibility children can materialize offscreen rows.
    /// Enumerate only native views that AppKit has already made, never force one.
    private static func nodes(in view: NSView) -> [DeletionAX] {
        var result: [DeletionAX] = [], seen = Set<ObjectIdentifier>()
        func visit(_ candidate: Any, depth: Int) {
            guard depth < 45, let object = candidate as? NSObject,
                  seen.insert(ObjectIdentifier(object)).inserted else { return }
            if let table = object as? NSTableView {
                table.enumerateAvailableRowViews { row, _ in visit(row, depth: depth + 1) }
                return
            }
            let node = DeletionAX(object: object)
            // SwiftUI may expose an AX proxy instead of the native table.
            // Inspect its already-materialized row views separately below.
            if ["AXTable", "AXOutline", "AXList"].contains(node.role) { return }
            result.append(node)
            node.children.forEach { visit($0, depth: depth + 1) }
        }
        visit(view, depth: 0)
        NSAccessibility.unignoredChildren(from: [view]).forEach { visit($0, depth: 0) }
        if let table = table(in: view) { table.enumerateAvailableRowViews { row, _ in visit(row, depth: 0) } }
        return result
    }

    private static func find(_ identifier: String, in view: NSView) async throws -> DeletionAX {
        for _ in 0..<6 {
            if let node = nodes(in: view).first(where: { $0.identifier == identifier }) { return node }
            try await settle(view)
        }
        let visible = nodes(in: view)
        let diagnostic = visible.prefix(15).map { "\(type(of: $0.object)) [\($0.role)] \($0.label)" }.joined(separator: "; ")
        throw failure("Missing project control \(identifier); visible: \(visible.compactMap(\.identifier).joined(separator: ", ")); tree: \(diagnostic)")
    }

    private static func menuItems(_ menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { [$0] + ($0.submenu.map(menuItems) ?? []) }
    }
    private static func nativeMenu(_ host: NSView, id: String, containing title: String) async throws -> NSMenu {
        let target = try await find(id, in: host), tracking = DeletionMenuTracking(window: host.window)
        let center = NotificationCenter.default
        let began = center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { notification in
            guard let menu = notification.object as? NSMenu else { return }
            MainActor.assumeIsolated { tracking.began(menu) }
        }
        let ended = center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: nil) { notification in
            guard let menu = notification.object as? NSMenu else { return }
            MainActor.assumeIsolated { tracking.didEnd(menu) }
        }
        let timer = Timer(timeInterval: 0.02, repeats: true) { _ in MainActor.assumeIsolated { tracking.cancel() } }
        RunLoop.main.add(timer, forMode: .common); RunLoop.main.add(timer, forMode: .eventTracking)
        defer { timer.invalidate(); center.removeObserver(began); center.removeObserver(ended) }
        var accepted = target.actions.contains("AXShowMenu") ? target.showMenu() : false
        if !accepted && tracking.menus.isEmpty && target.actions.contains("AXPress") { accepted = target.press() }
        if !accepted && tracking.menus.isEmpty {
            guard let window = host.window else { throw NSError(domain: "CardDeletionInteractionTests", code: 8) }
            let frame = target.interactionFrame, point = window.convertPoint(fromScreen: NSPoint(x: frame.midX, y: frame.midY))
            try expect(frame.width > 0 && frame.height > 0 && window.convertToScreen(host.bounds).insetBy(dx: -1, dy: -1).contains(frame), "Menu fits its fixture window: \(frame)")
            let timestamp = ProcessInfo.processInfo.systemUptime
            guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
                timestamp: timestamp, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1),
                  let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [],
                timestamp: timestamp + 0.02, windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0) else {
                throw NSError(domain: "CardDeletionInteractionTests", code: 9)
            }
            NSApp.postEvent(up, atStart: true); window.sendEvent(down)
            if let remaining = NSApp.nextEvent(matching: .leftMouseUp, until: Date(), inMode: .default, dequeue: true) {
                try expect(remaining.windowNumber == window.windowNumber, "Native menu release belongs only to the fixture")
                window.sendEvent(remaining)
            }
        }
        try await settle(host)
        guard let menu = tracking.menus.first(where: { menuItems($0).contains { $0.title == title } }) else {
            throw NSError(domain: "CardDeletionInteractionTests", code: 10,
                userInfo: [NSLocalizedDescriptionKey: "\(id) must expose the real native menu containing \(title)"])
        }
        try expect(!tracking.timedOut && tracking.ended.contains(ObjectIdentifier(menu)), "Actual \(id) menu closes before item dispatch")
        try expect(!menuItems(menu).contains { $0.title == "Pin" || $0.title == "Unpin" },
                   "Native \(id) menu omits the retired Pin action while keeping \(title) available")
        return menu
    }
    private static func selectMenu(_ host: NSView, id: String, title: String) async throws {
        let menu = try await nativeMenu(host, id: id, containing: title)
        guard let item = menuItems(menu).first(where: { $0.title == title }), let owner = item.menu else {
            throw NSError(domain: "CardDeletionInteractionTests", code: 11)
        }
        try expect(item.isEnabled && !item.isHidden && item.action != nil, "Native menu destination \(title) remains actionable")
        owner.performActionForItem(at: owner.index(of: item)); try await settle(host)
    }

    private static func press(_ id: String, in host: NSView) async throws {
        let node = try await find(id, in: host)
        try expect(node.press(), "Actual card control \(id) performs its action")
        try await settle(host)
    }
    private static func alertButton(_ title: String, window: NSWindow) async throws -> DeletionAX {
        for _ in 0..<12 {
            // A card can have the same label as its confirmation. Search only
            // the active alert sheet, never the still-visible parent controls.
            var sheets: [NSWindow] = []
            var current = window.attachedSheet
            while let sheet = current { sheets.append(sheet); current = sheet.attachedSheet }
            for sheet in sheets.reversed() {
                if let view = sheet.contentView {
                    let matches = nodes(in: view).filter {
                        $0.label == title && $0.role == "AXButton" && $0.frame.width > 0 && $0.frame.height > 0
                    }
                    if let node = matches.first(where: { $0.object is NSButton }) ?? matches.first { return node }
                }
            }
            try await Task.sleep(for: .milliseconds(35))
        }
        throw failure("Missing actual alert button \(title)")
    }
    private static func answer(_ title: String, host: NSView) async throws {
        guard let window = host.window else { throw failure("Missing owned alert window") }
        let button = try await alertButton(title, window: window)
        if let native = button.object as? NSButton {
            try expect(native.isEnabled && !native.isHiddenOrHasHiddenAncestor, "Native alert button is available")
            native.performClick(nil)
        } else {
            // SwiftUI's alert proxy can advertise AXPress while returning false.
            // Send normal mouse events solely to this fixture's actual sheet.
            let frame = button.frame
            let candidates = (window.attachedSheet.map { [$0] } ?? []) + [window]
            guard let owner = candidates.first(where: { candidate in
                candidate.contentView.map { candidate.convertToScreen($0.convert($0.bounds, to: nil)).contains(frame) } == true
            }) else { throw failure("Alert control must belong to the fixture window or its sheet") }
            let point = owner.convertPoint(fromScreen: NSPoint(x: frame.midX, y: frame.midY))
            let stamp = ProcessInfo.processInfo.systemUptime
            guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
                timestamp: stamp, windowNumber: owner.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1),
                let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [],
                timestamp: stamp + 0.02, windowNumber: owner.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0)
            else { throw failure("Missing native alert event") }
            NSApp.postEvent(up, atStart: true); owner.sendEvent(down)
            if let remaining = NSApp.nextEvent(matching: .leftMouseUp, until: Date(), inMode: .default, dequeue: true) {
                try expect(remaining.windowNumber == owner.windowNumber, "Alert release belongs solely to this fixture")
                owner.sendEvent(remaining)
            }
        }
        print("ALERT action: \(title)")
        try await settle(host)
    }
    private static func mount<V: View>(_ view: V, in host: NSHostingView<AnyView>) async throws {
        host.rootView = AnyView(view.environment(\.daBinTooltipsEnabled, false)
            .transaction { $0.animation = nil; $0.disablesAnimations = true })
        try await settle(host)
    }
    private static func snapshot(_ host: NSView, name: String) throws {
        let path = ProcessInfo.processInfo.environment["DABIN_CARD_DELETION_QA_OUTPUT"]
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("DaBinCardDeletionRenders").path
        let directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw failure("Missing card bitmap") }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw failure("Missing PNG") }
        let output = directory.appendingPathComponent(name + ".png")
        try data.write(to: output, options: .atomic)
        print("FIXTURE: \(output.path)")
    }

    private static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinCardDeletionQA-" + UUID().uuidString)
        let suite = "DaBinCardDeletionQA." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: PreviewService.linkPreviewPreference)
        let board = NSPasteboard(name: .init(suite))
        let store = try CaptureStore(root: root)
        let previews = PreviewService(store: store, defaults: defaults)
        let auto = AutoCaptureService(settings: AutoCaptureSettings(defaults: defaults), input: InputService(store: store),
            pasteboardProvider: { fatalError("Deletion QA never reads the clipboard") }, sourceApplicationProvider: { nil })
        let state = AppState(store: store, previews: previews,
            reminders: ReminderService(store: store, client: DeletionFixtureNotifications()), autoCapture: auto,
            captureClipboard: CaptureClipboardService(pasteboard: board))
        let host = NSHostingView(rootView: AnyView(EmptyView()))
        host.frame = NSRect(x: 0, y: 0, width: 980, height: 900); host.sizingOptions = []
        let window = DeletionFixtureWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 980, height: 900),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer {
            window.orderOut(nil); window.contentView = nil; window.close()
            auto.shutdown(); state.focusSessions.shutdown(); state.shutdownNotificationPresentation(); previews.shutdown()
            board.releaseGlobally(); defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let initialized = await Task.detached {
            let process = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(process, kAXWindowsAttribute as CFString, &value)
        }.value
        try expect(initialized == .success, "Only own-process accessibility initializes")
        try expect(window.frame.maxX < 0 && !window.isMainWindow, "Fictional content stays in the offscreen fixture")

        let project = "Fictional delete project"
        let text = "Exact live note, with a second line.\nKeep projects and saved copies."
        try state.workspace.setScratchpad(text: text, project: project)
        let note = state.workspace.snapshot.scratchpads[WorkspaceSnapshot.projectKey(project)]!
        try await mount(DeletionProjectFixture(state: state, note: note).frame(width: 360), in: host)
        try snapshot(host, name: "project-note-delete")
        try await selectMenu(host, id: "project-more-note:project:" + project, title: "Delete notes…")
        try expect(state.pendingScratchpadRemoval?.text == text && !state.workspace.scratchpad(project: project).isEmpty,
            "Project note More requests confirmation without deleting")
        state.pendingScratchpadRemoval = nil
        try await mount(DeletionSearchFixture(state: state, item: .note(note)).frame(width: 360), in: host)
        try snapshot(host, name: "search-note-delete")
        try await selectMenu(host, id: "search-more-note:project:" + project, title: "Delete note…")
        try expect(state.pendingScratchpadRemoval?.text == text, "Search note has a visible working Delete action")
        state.pendingScratchpadRemoval = nil

        state.openLibrary()
        try await mount(BoardView(state: state, theme: ThemeSettings(defaults: defaults)), in: host)
        state.requestScratchpadRemoval(note); try await settle(host)
        try await answer("Cancel", host: host)
        try expect(state.workspace.scratchpad(project: project) == text && state.workspace.deletedScratchpads.isEmpty,
            "Note confirmation Cancel preserves exact note")
        state.requestScratchpadRemoval(note); try await settle(host)
        try await answer("Delete notes", host: host)
        try expect(state.workspace.scratchpad(project: project).isEmpty && state.workspace.deletedScratchpads.count == 1,
            "Note confirmation moves exact live note to persisted trash")
        try await press("card-delete-undo", in: host)
        try expect(state.workspace.scratchpad(project: project) == text && state.workspace.deletedScratchpads.isEmpty,
            "Shared Undo restores live notes")

        var capture = try store.createNote(text: "Exact saved capture is recoverable", projectName: project)
        state.requestRemoval(capture); try await settle(host)
        try await answer("Cancel", host: host)
        try expect(store.captures.contains { $0 === capture }, "Capture alert still works after adding note alert")
        state.requestRemoval(capture); try await settle(host)
        try await answer("Move to Recently Deleted", host: host)
        try expect(store.trashedCaptures.contains { $0.id == capture.id }, "Capture confirmation still moves capture to trash")
        try await press("card-delete-undo", in: host)
        try expect(store.captures.contains { $0.id == capture.id }, "Shared Undo still restores saved captures")
        capture = store.captures.first { $0.id == capture.id }!

        state.libraryProject = project
        try await mount(ProjectWorkspaceView(state: state, project: project, pasteboard: board, chooseExportDestination: { _ in
            fatalError("Deletion QA must not open an export panel")
        }), in: host)
        try await selectMenu(host, id: "project-actions", title: "Project notes")
        var sheetView: NSView?
        for _ in 0..<12 {
            if let value = window.attachedSheet?.contentView { sheetView = value; break }
            try await Task.sleep(for: .milliseconds(35))
        }
        guard let sheetView else { throw failure("Project notes must open its actual native sheet") }
        try await settle(sheetView)
        try await press("scratchpad-delete", in: sheetView)
        try await answer("Cancel", host: sheetView)
        try expect(state.workspace.scratchpad(project: project) == text, "Project note editor Cancel preserves autosaved content")
        try await press("scratchpad-delete", in: sheetView)
        try await answer("Delete notes", host: sheetView)
        let receipt = state.workspace.deletedScratchpads[0]
        try expect(store.captures.contains { $0 === capture }, "Project note sheet Delete keeps saved captures")
        try await press("project-notes-done", in: sheetView)
        try await settle(host)
        try expect(window.attachedSheet == nil, "Note deletion leaves the project sheet with a working Done action")
        try await mount(TrashScreen(state: state), in: host)
        try await press("trash-note-delete-" + receipt.id.uuidString, in: host)
        try await answer("Cancel", host: host)
        try expect(state.workspace.deletedScratchpads.contains { $0.id == receipt.id }, "Permanent note Delete Cancel preserves receipt")
        try await press("trash-note-restore-" + receipt.id.uuidString, in: host)
        try expect(state.workspace.scratchpad(project: project) == text, "Recently Deleted card Restore restores exact note")

        state.requestScratchpadRemoval(note); try expect(state.confirmScratchpadRemoval(), "Second removed note gets its own receipt")
        let permanent = state.workspace.deletedScratchpads[0]
        try state.workspace.setScratchpad(text: "New live note must survive permanent deletion", project: project)
        try await settle(host)
        try await press("trash-note-delete-" + permanent.id.uuidString, in: host)
        try await answer("Delete permanently", host: host)
        try expect(!state.workspace.deletedScratchpads.contains { $0.id == permanent.id }
            && state.workspace.scratchpad(project: project) == "New live note must survive permanent deletion",
            "Permanent note Delete removes only the trash copy and preserves new live notes")

        try await mount(DeletionSearchFixture(state: state, item: .capture(SearchEntry(capture: capture, isMatch: true, indexedTextMatch: nil))), in: host)
        try await selectMenu(host, id: "search-more-capture:" + capture.id.uuidString, title: "Move to Recently Deleted…")
        try expect(state.pendingRemoval === capture, "Search saved capture visible More exposes existing safe Delete")
        state.pendingRemoval = nil

        try await commentChecks(state: state, host: host, capture: capture)
        try await groupChecks(state: state, host: host)
        print("Card deletion interaction QA passed \(checks) checks.")
    }

    private static func commentChecks(state: AppState, host: NSHostingView<AnyView>, capture: Capture) async throws {
        let entry = try state.store.appendComment(capture, text: "Fictional saved comment")
        let later = try state.store.appendComment(capture, text: "Second comment stays saved")
        let draft = CaptureDraft(capture: capture)
        draft.commentComposer = "Unsaved new comment remains exactly as typed"
        draft.title = "Unsaved title remains"
        try await mount(CaptureDetailPanels(state: state, capture: capture, draft: draft, selection: .constant(.comments)), in: host)
        try snapshot(host, name: "comment-delete")
        try await press("delete-comment-" + entry.id.uuidString, in: host)
        try await answer("Cancel", host: host)
        try expect(capture.commentThread.contains { $0.id == entry.id }, "Saved comment Cancel preserves entry")
        try await press("delete-comment-" + entry.id.uuidString, in: host)
        try await answer("Delete comment", host: host)
        try await settle(host)
        try expect(!capture.commentThread.contains { $0.id == entry.id } && capture.commentThread.contains { $0.id == later.id },
            "Comment deletion removes only chosen exact entry")
        try expect(draft.commentComposer == "Unsaved new comment remains exactly as typed" && draft.title == "Unsaved title remains",
            "Comment deletion preserves pending composer and unrelated draft edits")
        _ = try state.store.appendComment(capture, text: "Later arrival preserved by Undo")
        // Adopt baseline as an external save would, retaining the unsent composer.
        let composer = draft.commentComposer
        draft.adoptSavedComments(from: capture); draft.commentComposer = composer
        try await press("capture-undo-comment-delete", in: host)
        try expect(capture.commentThread.contains { $0 == entry } && capture.commentThread.count == 3,
            "Comment Undo restores exact saved entry while retaining later comments")
        draft.editingCommentID = later.id; draft.commentComposer = "Unsent edit to deleted comment"
        try await press("delete-comment-" + later.id.uuidString, in: host)
        try await answer("Delete comment", host: host)
        try await settle(host)
        try expect(draft.editingCommentID == nil && draft.commentComposer == "Unsent edit to deleted comment",
            "Deleting edited comment keeps typed content as a new unsent comment")
    }

    private static func groupChecks(state: AppState, host: NSHostingView<AnyView>) async throws {
        let at = Calendar.current.startOfDay(for: Date()).addingTimeInterval(12 * 3600)
        let zone = TimeZone.current
        let captures = try (0..<5).map { index in
            try state.store.capture(text: index < 3 ? "Fictional automatic action \(index)" : "https://fictional.example/hidden/\(index)",
                at: at.addingTimeInterval(Double(index)), timeZone: zone,
                receipt: .automatic(.automaticClipboard, actionID: UUID(), sourceApplicationName: "Fictional App",
                    sourceApplicationBundleIdentifier: "com.dabin.fixture"))[0]
        }
        try expect(captures.count == 5, "Automatic fixtures use live repository identities")
        let key = AutomaticHourKey(capture: captures[0])
        func group(_ values: [Capture]) -> AutomaticHourGroup {
            .init(id: key, actions: values.map { .init(id: $0.automaticActionID!, cards: [.init(id: .capture($0.id), captures: [$0])]) },
                totalActionCount: max(5, values.count + 2), totalCaptureCount: max(5, values.count + 2), displaysDate: false)
        }
        var visible = Array(captures.prefix(3))
        let hidden = Array(captures.suffix(2))
        try await mount(HourlyCaptureCard(state: state, group: group(visible)).frame(width: 430), in: host)
        try snapshot(host, name: "hour-delete")
        let id = "capture-more-hour-\(key.captureDay)-\(key.hour)-\(key.utcOffsetSeconds)"
        try await selectMenu(host, id: id, title: "Delete 3 visible captures…")
        try await answer("Cancel", host: host)
        try expect(visible.allSatisfy { value in state.store.captures.contains { $0 === value } },
            "Hourly confirmation Cancel preserves every shown capture")
        try await selectMenu(host, id: id, title: "Delete 3 visible captures…")
        let arriving = try state.store.capture(text: "Capture arriving after confirmation",
            at: at.addingTimeInterval(50), timeZone: zone,
            receipt: .automatic(.automaticClipboard, actionID: UUID(), sourceApplicationName: "Fictional App",
                sourceApplicationBundleIdentifier: "com.dabin.fixture"))[0]
        try await mount(HourlyCaptureCard(state: state, group: group(visible + [arriving])).frame(width: 430), in: host)
        try await answer("Delete 3 visible captures", host: host)
        try expect(visible.allSatisfy { removed in state.store.trashedCaptures.contains { $0.id == removed.id } },
            "Hourly Delete removes only frozen visible capture identities")
        try expect((hidden + [arriving]).allSatisfy { kept in state.store.captures.contains { $0 === kept } },
            "Hourly Delete keeps hidden captures and new arrivals")
        await state.undoLastRemoval()
        try expect(visible.allSatisfy { restored in state.store.captures.contains { $0.id == restored.id } }, "Hourly Delete supports shared Undo")
        // Trash/restore intentionally replace objects to reject stale writers.
        // The UI must follow the same immutable IDs through fresh live objects.
        visible = visible.map { value in state.store.captures.first { $0.id == value.id }! }
        state.toggleHourlyGroup(key)
        try await mount(HourlyCaptureCard(state: state, group: group(visible)).frame(width: 430), in: host)
        let action = visible[0]
        try await selectMenu(host, id: "capture-more-action-" + action.automaticActionID!.uuidString, title: "Delete 1 visible capture…")
        try await answer("Delete 1 visible capture", host: host)
        try expect(state.store.trashedCaptures.contains { $0.id == action.id } && visible.dropFirst().allSatisfy { value in
            state.store.captures.contains { $0 === value }
        }, "Automatic action Delete keeps other actions in the hour")
        await state.undoLastRemoval()
        visible = visible.map { value in state.store.captures.first { $0.id == value.id }! }
        state.filter = .text
        state.selectedDay = at
        state.selectTimelineMode(.weekly)
        state.toggleHourlyGroup(key)
        try await mount(WeeklyScreen(state: state), in: host)
        try await selectMenu(host, id: id, title: "Delete 4 visible captures…")
        let weeklyArrival = try state.store.capture(text: "Automatic arrival changes the weekly primary",
            at: at.addingTimeInterval(100), timeZone: zone,
            receipt: .automatic(.automaticClipboard, actionID: UUID(), sourceApplicationName: "Fictional App",
                sourceApplicationBundleIdentifier: "com.dabin.fixture"))[0]
        try await settle(host)
        try await answer("Delete 4 visible captures", host: host)
        try expect((visible + [arriving]).allSatisfy { removed in state.store.trashedCaptures.contains { $0.id == removed.id } }
            && state.store.captures.contains { $0 === weeklyArrival },
            "Weekly hourly confirmation survives a new primary and keeps its frozen deletion scope")
        await state.undoLastRemoval()
    }
}
