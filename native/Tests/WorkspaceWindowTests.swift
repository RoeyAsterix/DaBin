import AppKit
import ApplicationServices
import Darwin
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
    var role: String { (value("accessibilityRole") as? String) ?? (attribute("AXRole") as? String) ?? "" }
    var label: String? {
        [value("accessibilityLabel"), value("accessibilityTitle"), attribute("AXTitle"), attribute("AXDescription"),
         value("accessibilityValue"), attribute("AXValue")].compactMap { $0 as? String }.first { !$0.isEmpty }
    }
    var valueText: String { (value("accessibilityValue") as? String) ?? (attribute("AXValue") as? String) ?? "" }
    var help: String? { (value("accessibilityHelp") as? String) ?? (attribute("AXHelp") as? String) }
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
    var actions: [String] { (value("accessibilityActionNames") as? [String]) ?? [] }
    func showMenu() -> Bool {
        let selector = NSSelectorFromString("accessibilityPerformShowMenu")
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
        return result
    }
}

/// Capture and close only native menus opened by this fixture. Cancellation
/// occurs on the tracking run loop, never reentrantly in the begin observer.
@MainActor private final class WorkspaceWindowMenuTracking {
    private let deadline = ProcessInfo.processInfo.systemUptime + 2
    private weak var window: NSWindow?
    private(set) var menus: [NSMenu] = []
    private(set) var ended = Set<ObjectIdentifier>()
    private(set) var timedOut = false
    init(window: NSWindow?) { self.window = window }
    func began(_ menu: NSMenu) {
        if !menus.contains(where: { $0 === menu }) { menus.append(menu) }
    }
    func didEnd(_ menu: NSMenu) { ended.insert(ObjectIdentifier(menu)) }
    func cancel() {
        menus.forEach { $0.cancelTrackingWithoutAnimation() }
        guard ProcessInfo.processInfo.systemUptime >= deadline else { return }
        timedOut = true
        guard let window, let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53) else { return }
        NSApp.postEvent(escape, atStart: true)
    }
}

@MainActor private struct WorkspacePlanningHarness: View {
    @ObservedObject var draft: NewTaskDraft
    var body: some View { TaskPlanningEditor(planning: $draft.planning).padding(16) }
}

/// Exercises the production workspace using native accessible actions in an
/// isolated window. Fixtures never use the user's archive or system clipboard.
@main @MainActor private final class WorkspaceWindowTests: NSObject, NSApplicationDelegate {
    private var result: Int32 = 1
    @MainActor private static var checks = 0

    static func main() {
        let application = NSApplication.shared
        let delegate = WorkspaceWindowTests()
        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
        exit(delegate.result)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do {
                try await Self.run()
                print("COMPLETE: WorkspaceWindowTests finished every fixture and cleanup")
                result = 0
            } catch {
                result = 1
                fputs("Workspace window QA failed: \(error)\n", stderr)
            }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }
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
    @MainActor private static func nativeListDescription(_ scroll: NSScrollView) -> String {
        let geometry = "offset=\(scroll.contentView.bounds.origin), viewport=\(scroll.contentView.bounds.size), document=\(String(describing: scroll.documentView?.frame))"
        guard let table = scroll.documentView as? NSTableView else { return geometry }
        var rows: [String] = []
        // Diagnostics must not instantiate offscreen rows or request their AX trees.
        table.enumerateAvailableRowViews { row, index in
            rows.append("\(index):\(row.frame)")
        }
        return geometry + ", logicalRows=\(table.numberOfRows), visibleRange=\(table.rows(in: table.visibleRect)), availableRows=[\(rows.joined(separator: "; "))]"
    }
    @MainActor private static func nodes(_ view: NSView, includeSubviews: Bool = true) -> [WorkspaceAXNode] {
        view.layoutSubtreeIfNeeded()
        var seen = Set<ObjectIdentifier>()
        var result: [WorkspaceAXNode] = []
        func visit(_ value: Any, depth: Int) {
            guard depth < 50, let object = value as? NSObject, seen.insert(ObjectIdentifier(object)).inserted else { return }
            let node = WorkspaceAXNode(object: object); result.append(node)
            node.children.forEach { visit($0, depth: depth + 1) }
            if includeSubviews, let native = object as? NSView {
                native.subviews.forEach { visit($0, depth: depth + 1) }
            }
        }
        visit(view, depth: 0)
        NSAccessibility.unignoredChildren(from: [view]).forEach { visit($0, depth: 0) }
        return result
    }
    @MainActor private static func scrollControlIntoView(_ view: NSView, id: String, window: NSWindow) async throws -> WorkspaceAXNode {
        let scroll = try listScrollView(in: view)
        guard let document = scroll.documentView else {
            throw NSError(domain: "WorkspaceWindowTests", code: 10,
                userInfo: [NSLocalizedDescriptionKey: "Today scroll view has no native document"])
        }
        // Lazy receipt rows precede the plan. Materialize the real plan by
        // scrolling its native viewport; an AX lookup alone cannot reveal it.
        for _ in 0..<48 {
            view.layoutSubtreeIfNeeded()
            let viewport = window.convertToScreen(scroll.contentView.convert(scroll.contentView.bounds, to: nil))
            if let target = nodes(view, includeSubviews: false).first(where: { $0.identifier == id }),
               target.frame.width > 0 && target.frame.height > 0 {
                if viewport.insetBy(dx: -1, dy: -1).contains(target.frame) { return target }
                let targetRect = document.convert(window.convertFromScreen(target.frame), from: nil)
                _ = document.scrollToVisible(targetRect.insetBy(dx: -2, dy: -6))
            } else {
                let maximum = max(0, document.bounds.maxY - scroll.contentView.bounds.height)
                let direction: CGFloat = document.isFlipped ? 1 : -1
                let next = min(maximum, max(0, scroll.contentView.bounds.minY + direction * scroll.contentView.bounds.height * 0.7))
                scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.minX, y: next))
            }
            scroll.reflectScrolledClipView(scroll.contentView)
            await settleNavigation()
        }
        throw NSError(domain: "WorkspaceWindowTests", code: 11,
            userInfo: [NSLocalizedDescriptionKey: "Could not reveal native Today control \(id); \(nativeListDescription(scroll))"])
    }
    @MainActor private static func find(_ view: NSView, id: String) throws -> WorkspaceAXNode {
        for _ in 0..<6 {
            if let node = nodes(view).first(where: { $0.identifier == id }) { return node }
            settle()
        }
        fputs("Workspace controls at failure: \(nodes(view).compactMap { $0.identifier ?? $0.label }.joined(separator: "; "))\n", stderr)
        throw NSError(domain: "WorkspaceWindowTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing workspace control \(id)"])
    }
    @MainActor private static func menuItems(_ menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { [$0] + ($0.submenu.map(menuItems) ?? []) }
    }
    @MainActor private static func nativeWorkspaceMenu(_ host: NSView, id: String = "project-filter-menu", containing title: String) async throws -> NSMenu {
        let target = try find(host, id: id)
        guard let window = host.window else {
            throw NSError(domain: "WorkspaceWindowTests", code: 14,
                userInfo: [NSLocalizedDescriptionKey: "Project filter menu needs its owned fixture window"])
        }
        let visible = window.convertToScreen(host.convert(host.bounds, to: nil))
        // An AX cell can outlive/recycle its former control view. Only use a
        // native control's hit rectangle when it still owns this exact cell
        // and belongs to the current fixture; otherwise retain the AX frame.
        let nativeControl: NSControl? = {
            let control: NSControl?
            if let cell = target.object as? NSCell, let candidate = cell.controlView as? NSControl,
               candidate.cell === cell { control = candidate }
            else { control = target.object as? NSControl }
            guard let control, control.window === window, control.isDescendant(of: host),
                  !control.isHiddenOrHasHiddenAncestor else { return nil }
            return control
        }()
        let frame = nativeControl.map { window.convertToScreen($0.convert($0.bounds, to: nil)) } ?? target.frame
        let advertisedAXEnabled: Bool? = target.object.responds(to: NSSelectorFromString("isAccessibilityEnabled"))
            ? target.isEnabled : nil
        let enabled = nativeControl?.isEnabled ?? (target.object as? NSCell)?.isEnabled ?? advertisedAXEnabled
        let cell = target.object as? NSCell
        let formerControl = cell?.controlView
        let detail = "type=\(String(describing: type(of: target.object))) role=\(target.role) "
            + "AX=\(NSStringFromRect(target.frame)) interaction=\(NSStringFromRect(frame)) visible=\(NSStringFromRect(visible)) "
            + "AXEnabled=\(String(describing: advertisedAXEnabled)) nativeEnabled=\(String(describing: nativeControl?.isEnabled)) cellEnabled=\(String(describing: cell?.isEnabled)) "
            + "cellControl=\(String(describing: formerControl.map { String(describing: type(of: $0)) })) "
            + "sameCell=\(cell != nil && (formerControl as? NSControl)?.cell === cell) ownWindow=\(formerControl?.window === window) "
            + "actions=\(target.actions)"
        fputs("Project filter native target: \(detail)\n", stderr)
        // Native borderless menus retain intrinsic hosts inside SwiftUI's
        // 32-point layout frame. Test the real native bounds and action, as the
        // existing header fixture does, without inventing larger AX geometry.
        try expect(enabled != false && frame.width > 0 && frame.height > 0
            && visible.insetBy(dx: -1, dy: -1).contains(frame),
            "Narrow project filter menu has a visible owned native target without a disabled state: " + detail)
        let tracking = WorkspaceWindowMenuTracking(window: window)
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
            let point = window.convertPoint(fromScreen: NSPoint(x: frame.midX, y: frame.midY))
            let timestamp = ProcessInfo.processInfo.systemUptime
            guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
                timestamp: timestamp, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1),
                  let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [],
                timestamp: timestamp + 0.02, windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0) else {
                throw NSError(domain: "WorkspaceWindowTests", code: 15)
            }
            NSApp.postEvent(up, atStart: true); window.sendEvent(down)
            if let release = NSApp.nextEvent(matching: .leftMouseUp, until: Date(), inMode: .default, dequeue: true) {
                try expect(release.windowNumber == window.windowNumber, "Native filter-menu release belongs only to the fixture")
                window.sendEvent(release)
            }
        }
        await settleNavigation()
        guard let menu = tracking.menus.first(where: { menuItems($0).contains { $0.title == title } }) else {
            throw NSError(domain: "WorkspaceWindowTests", code: 16,
                userInfo: [NSLocalizedDescriptionKey: "Project filter exposes a real native menu containing \(title)"])
        }
        try expect(!tracking.timedOut && tracking.ended.contains(ObjectIdentifier(menu)),
            "Actual project filter menu closes before item dispatch")
        return menu
    }
    @MainActor private static func selectProjectFilter(_ title: String, in host: NSView, message: String) async throws {
        if nodes(host).contains(where: { $0.identifier == "project-filter-menu" && $0.frame.width > 0 && $0.frame.height > 0 }) {
            let menu = try await nativeWorkspaceMenu(host, containing: title)
            let identifier = "project-filter-" + title
            guard let item = menuItems(menu).first(where: {
                $0.identifier?.rawValue == identifier || WorkspaceAXNode(object: $0).identifier == identifier
            }), let owner = item.menu else {
                throw NSError(domain: "WorkspaceWindowTests", code: 17,
                    userInfo: [NSLocalizedDescriptionKey: "Native project filter keeps exact menu item identity \(identifier)"])
            }
            try expect(item.title == title && item.isEnabled && !item.isHidden && item.action != nil, message)
            owner.performActionForItem(at: owner.index(of: item))
            await settleNavigation()
        } else {
            try expect(try find(host, id: "project-filter-" + title).press(), message)
            settle()
        }
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

    @MainActor private static func checkCaptions(state: AppState, theme: ThemeSettings, hosting: NSView,
                                               window: NSWindow, evidence: URL) async throws {
        state.workspaceZoom.reset()
        state.filter = .all
        state.clearNewNoteDraft()
        state.libraryProject = "Fictional captions project A"
        state.openInbox()
        window.setContentSize(NSSize(width: 380, height: 680))
        theme.setDarkMode(false)
        await settleNavigation()

        func checkPlaceholder(_ project: String) throws {
            let expected = "An Idea/Task for " + project
            let field = try findLabeled(hosting, label: expected)
            try expect((field.object as? NSTextField)?.placeholderString == expected,
                "The actual quick text field names its full saved destination: \(expected)")
            let quickText = try find(hosting, id: "inbox-quick-text")
            try expect(quickText.help?.contains(project) == true,
                "Quick capture accessibility describes the complete destination \(project)")
        }
        func saveQuick(_ title: String) async throws {
            let menu = try await nativeWorkspaceMenu(hosting, id: "inbox-quick-save", containing: title)
            guard let item = menuItems(menu).first(where: { $0.title == title }), let owner = item.menu else {
                throw NSError(domain: "WorkspaceWindowTests", code: 18,
                    userInfo: [NSLocalizedDescriptionKey: "Quick save menu needs its native \(title) action"])
            }
            try expect(item.isEnabled && !item.isHidden && item.action != nil,
                "\(title) is available through the quick capture's real native save menu")
            owner.performActionForItem(at: owner.index(of: item))
            await settleNavigation()
        }
        func typeQuick(_ text: String, project: String, message: String) async throws {
            // The ID may belong to SwiftUI's synthetic AX element. Its bare
            // value setter changes the display without an editing notification.
            // Resolve the actual field by its native placeholder so insertion
            // follows the same AppKit field-editor path as keyboard typing.
            let input = try findLabeled(hosting, label: "An Idea/Task for " + project)
            try expect((input.object as? NSTextField)?.window === window,
                "Quick capture typing uses the actual field owned by the fixture window")
            try expect(input.setText(text), message)
            await settleNavigation()
            fputs("Quick capture native typing: target=\(String(describing: type(of: input.object))) route=\(state.route) expectedCharacters=\(text.count) actualCharacters=\(state.newNoteText.count) draftProject=\(state.newNoteProject ?? "Unfiled") selectedProject=\(state.libraryProject ?? "Unfiled")\n", stderr)
        }
        try checkPlaceholder("Fictional captions project A")
        let noteText = "A fictional idea that retains its original project while typing"
        try await typeQuick(noteText, project: "Fictional captions project A",
            message: "Captions accepts real native field-editor text")
        try expect(state.newNoteText == noteText && state.newNoteProject == "Fictional captions project A",
            "Typing captures the selected project as the draft destination")
        state.libraryProject = "Fictional captions project B"
        await settleNavigation()
        try checkPlaceholder("Fictional captions project A")
        try await saveQuick("Save note")
        try expect(state.store.captures.contains { $0.originalText == noteText && $0.projectName == "Fictional captions project A" && !$0.isTask },
            "The native Save note action saves to the displayed draft project after the selection changes")
        try expect(state.newNoteText.isEmpty && state.newNoteProject == nil && state.route == .inbox,
            "Saving clears only the quick draft and leaves Captions open")
        try checkPlaceholder("Fictional captions project B")
        let taskText = "A fictional next task for the latest selected project"
        try await typeQuick(taskText, project: "Fictional captions project B",
            message: "A fresh quick draft accepts a task in the newly selected project")
        try await saveQuick("Create task")
        try expect(state.store.captures.contains { $0.originalText == taskText && $0.projectName == "Fictional captions project B" && $0.isTask },
            "The native Create task action saves the quick draft to the project named in its placeholder")

        // An explicitly unfiled draft is distinct from having no draft. A
        // later project selection must not silently change where it is saved.
        state.libraryProject = nil
        state.openInbox()
        await settleNavigation()
        try checkPlaceholder("Unfiled")
        let unfiledText = "A fictional unfiled idea that must stay unfiled"
        try await typeQuick(unfiledText, project: "Unfiled",
            message: "Quick capture can begin explicitly unfiled")
        state.libraryProject = "Fictional captions project A"
        await settleNavigation()
        try checkPlaceholder("Unfiled")
        try await saveQuick("Save note")
        try expect(state.store.captures.contains { $0.originalText == unfiledText && $0.projectName == nil },
            "An explicitly unfiled draft stays unfiled after selecting another project")
        try checkPlaceholder("Fictional captions project A")

        _ = try state.store.capture(text: "Fictional unfiled caption text")
        _ = try state.store.capture(text: "https://example.invalid/fictional-caption-reference")
        _ = try state.store.createTask(text: "Fictional unfiled caption task")
        _ = try await state.store.importData(Data("Fictional caption attachment".utf8), filename: "Fictional-caption.dat")
        let image = NSImage(size: NSSize(width: 24, height: 24), flipped: false) { bounds in
            NSColor.systemPurple.setFill(); bounds.fill(); return true
        }
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "WorkspaceWindowTests", code: 19)
        }
        _ = try await state.store.importData(png, filename: "Fictional-caption.png")
        state.libraryProject = nil
        state.clearNewNoteDraft()
        state.selectedDay = Date()
        state.setWeekEndingDay(Date())
        let rowIDs = ["timeline-mode-daily", "timeline-mode-weekly"]
            + CaptureFilter.allCases.map { "capture-filter-" + $0.rawValue }
        for dark in [false, true] {
            theme.setDarkMode(dark)
            for width in [CGFloat(320), 380, 760] {
                window.setContentSize(NSSize(width: width, height: 680))
                for route in [BoardRoute.inbox, .daily, .weekly] {
                    state.route = route
                    state.filter = .all
                    await settleNavigation()
                    let viewport = window.convertToScreen(hosting.convert(hosting.bounds, to: nil)).insetBy(dx: -1, dy: -1)
                    let row = try find(hosting, id: "captions-toolbar")
                    let controls = try rowIDs.map { try find(hosting, id: $0) }
                    try expect(row.frame.width > 0 && row.frame.height > 0 && viewport.contains(row.frame),
                        "Captions has a wholly visible toolbar on \(route) at \(Int(width)) points in \(dark ? "dark" : "light") mode")
                    for control in controls {
                        try expect(control.isEnabled && control.frame.width >= 28 && control.frame.height >= 28
                            && viewport.contains(control.frame),
                            "\(control.identifier ?? "Captions control") has a visible usable target on \(route) at \(Int(width)) points")
                        try expect(abs(control.frame.midY - controls[0].frame.midY) <= 2,
                            "Day, Week and every caption filter share one aligned row on \(route) at \(Int(width)) points")
                    }
                    for index in 1..<controls.count {
                        try expect(controls[index - 1].frame.maxX <= controls[index].frame.minX + 0.5,
                            "Adjacent caption controls do not overlap on \(route) at \(Int(width)) points")
                    }
                    if route != .inbox {
                        let date = try find(hosting, id: "timeline-date")
                        try expect(viewport.contains(date.frame) && date.frame.minY >= row.frame.maxY - 1,
                            "Date navigation remains above the shared caption control row")
                    } else {
                        let available = nodes(hosting)
                        try expect(!available.contains { $0.frame.width > 0 && $0.frame.height > 0
                            && (["Paste", "Add files", "Add items"].contains($0.label ?? "")
                                || $0.label?.contains("Drop items here.") == true) },
                            "Captions no longer renders the removed Paste, add-items controls or drop-items hint")
                        try checkPlaceholder("Unfiled")
                    }
                    try saveImage(hosting, to: evidence.appendingPathComponent("captions-\(route)-\(Int(width))x680-\(dark ? "dark" : "light").png"))
                    if !dark && width == 760 {
                        for filter in CaptureFilter.allCases {
                            try expect(try find(hosting, id: "capture-filter-" + filter.rawValue).press(),
                                "The real \(filter.title) caption filter activates on \(route)")
                            await settleNavigation()
                            let filtered = state.store.captures.filter { filter.includes($0) }
                            try expect(state.filter == filter && !filtered.isEmpty,
                                "Native \(filter.title) filtering has matching archived fixture content on \(route)")
                            if route == .daily {
                                try expect(!state.dailyCaptures.isEmpty && state.dailyCaptures.allSatisfy { filter.includes($0) },
                                    "Daily content obeys its selected native caption filter")
                            } else if route == .weekly {
                                let weekly = state.weeklyVisibleDays.flatMap { state.captures(for: $0) }
                                try expect(!weekly.isEmpty && weekly.allSatisfy { filter.includes($0) },
                                    "Weekly content obeys its selected native caption filter")
                            }
                        }
                        state.filter = .all
                    }
                }
            }
        }
        theme.setDarkMode(false)
        state.route = .inbox
        state.filter = .all
        window.setContentSize(NSSize(width: 380, height: 680))
        await settleNavigation()
        try expect(try find(hosting, id: "timeline-mode-daily").press(), "Day activates from the unified Captions row")
        await settleNavigation()
        try expect(state.route == .daily, "The real Day control opens the daily caption view")
        try expect(try find(hosting, id: "timeline-mode-weekly").press(), "Week activates from the same caption row")
        await settleNavigation()
        try expect(state.route == .weekly, "The real Week control opens the weekly caption view")
        state.openInbox()
        await settleNavigation()
    }

    @MainActor private static func checkExplorer(state: AppState, hosting boardHosting: NSView, window: NSWindow, evidence: URL) async throws {
        // The global Explorer remains a supported production view. Mount it
        // directly here so its inspector/viewport regressions stay covered
        // independently of the new named-project workspace presentation.
        let hosting = NSHostingView(rootView: ExplorerScreen(state: state))
        window.contentView = hosting
        defer { window.contentView = boardHosting }
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
        try expect(try find(hosting, id: "explorer-search").press(), "Explorer search opens through its accessible button")
        await settleNavigation()
        try expect(state.route == .search && state.searchProject == nil && state.libraryProject == "Explorer review",
            "Explorer's Search everything button starts global Search without changing its project")
        state.query = "follow-up"
        state.back(); await settleNavigation()
        try expect(state.route == .library && state.workspace.explorerQuery.isEmpty
            && state.workspace.selectedCaptureID == first.id,
            "Back from global Search retains the Explorer selection without adding a hidden project query")
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
        try expect(state.workspace.selectedCaptureID == first.id && state.workspace.explorerQuery.isEmpty,
            "Compact resize preserves selection without introducing a hidden search filter")
        try expect(try find(hosting, id: "explorer-paste").isEnabled && find(hosting, id: "explorer-add-files").isEnabled,
            "Compact Explorer keeps accessible paste and import alternatives")
        try saveImage(hosting, to: evidence.appendingPathComponent("explorer-compact.png"))
        try expect(try find(hosting, id: "workspace-item-\(first.id.uuidString)").press(), "Compact row opens details")
        await settleNavigation()
        try expect(state.route == .detail && state.selectedCapture?.id == first.id, "Compact selection opens the complete capture")
        state.back(); await settleNavigation()
        try expect(state.route == .library && state.libraryProject == "Explorer review" && state.workspace.explorerQuery.isEmpty,
            "Back restores Explorer project and selection without stale search refinements")
        state.workspace.explorerQuery = ""

        // Keep this in collection mode: the similar Clipboard checks below use
        // a different browser and cannot validate Explorer's native List IDs.
        window.setContentSize(NSSize(width: 1000, height: 720))
        var projectA: [Capture] = [], projectB: [Capture] = []
        for index in 0..<24 {
            let at = Date(timeIntervalSince1970: 1_790_000_000 + Double(index))
            for project in ["Explorer scroll A", "Explorer scroll B"] {
                let capture = try state.store.capture(text: "Fictional Explorer scrolling \(project) \(index)", at: at)[0]
                try state.store.setOrganization(capture, pinned: false, projectName: project)
                if project == "Explorer scroll A" { projectA.append(capture) }
                else { projectB.append(capture) }
            }
        }
        state.libraryProject = "Explorer scroll A"; state.workspace.selectedCaptureID = projectA[2].id
        state.libraryProject = "Explorer scroll B"; state.workspace.selectedCaptureID = projectB[4].id
        await settleNavigation()
        state.libraryProject = "Explorer scroll A"; await settleNavigation()
        fputs("Explorer project return A: selected=\(String(describing: state.workspace.selectedCaptureID)), expected=\(projectA[2].id), savedViewport=\(String(describing: state.workspaceViewport)); \(nativeListDescription(try listScrollView(in: hosting)))\n", stderr)
        try expect(state.workspace.mode == .collection && state.workspace.selectedCaptureID == projectA[2].id
            && (try selectedCardIsVisible(projectA[2].id, in: hosting, window: window)),
            "Explorer restores its remembered deep capture into the native List viewport after switching project")
        state.libraryProject = "Explorer scroll B"; await settleNavigation()
        fputs("Explorer project return B: selected=\(String(describing: state.workspace.selectedCaptureID)), expected=\(projectB[4].id), savedViewport=\(String(describing: state.workspaceViewport)); \(nativeListDescription(try listScrollView(in: hosting)))\n", stderr)
        try expect(state.workspace.selectedCaptureID == projectB[4].id
            && (try selectedCardIsVisible(projectB[4].id, in: hosting, window: window)),
            "Explorer restores another project's distinct deep selection without opening details")
        let list = try listScrollView(in: hosting)
        guard let document = list.documentView else {
            throw NSError(domain: "WorkspaceWindowTests", code: 8,
                userInfo: [NSLocalizedDescriptionKey: "Explorer List has no document view"])
        }
        let browsingY: CGFloat = document.isFlipped ? 500 : max(0, document.bounds.height - list.contentView.bounds.height - 500)
        list.contentView.scroll(to: NSPoint(x: 0, y: browsingY)); list.reflectScrolledClipView(list.contentView)
        await settleNavigation()
        let viewport = window.convertToScreen(list.contentView.convert(list.contentView.bounds, to: nil))
        let before = nodes(hosting).filter {
            $0.identifier?.hasPrefix("workspace-item-") == true && $0.frame.height > 0
                && viewport.contains(NSPoint(x: $0.frame.midX, y: $0.frame.midY))
        }.map { ($0.identifier!, $0.frame) }
        try expect(!before.isEmpty, "Explorer insertion check starts with visible cards away from the top")
        let geometryBefore = nativeListDescription(list)
        let selectionBefore = state.workspace.selectedCaptureID
        let incoming = try state.store.capture(text: "Incoming fictional automatic Explorer capture",
            receipt: .automatic(.automaticClipboard))[0]
        try state.store.setOrganization(incoming, pinned: false, projectName: "Explorer scroll B")
        await settleNavigation()
        let after = nodes(hosting)
        let geometryAfter = nativeListDescription(list)
        let stationary = before.allSatisfy { identifier, frame in
            guard let current = after.first(where: { $0.identifier == identifier })?.frame else { return false }
            return abs(current.minY - frame.minY) <= 1 && abs(current.minX - frame.minX) <= 1
                && abs(current.height - frame.height) <= 1 && abs(current.width - frame.width) <= 1
        }
        fputs("Explorer native List insertion: \(before.count) visible card positions preserved=\(stationary)\n", stderr)
        fputs("Explorer List before: \(geometryBefore)\nExplorer List after: \(geometryAfter)\n", stderr)
        fputs("Explorer List selection: \(String(describing: selectionBefore)) → \(String(describing: state.workspace.selectedCaptureID)); grouping=\(state.workspace.explorerGrouping.rawValue), route=\(state.route)\n", stderr)
        for (identifier, previous) in before {
            guard let current = after.first(where: { $0.identifier == identifier })?.frame else {
                fputs("Explorer card \(identifier): old=\(previous), new=MISSING\n", stderr)
                continue
            }
            fputs("Explorer card \(identifier): old=\(previous), new=\(current), delta=(x:\(current.minX - previous.minX), y:\(current.minY - previous.minY), w:\(current.width - previous.width), h:\(current.height - previous.height))\n", stderr)
        }
        if !stationary {
            try saveImage(hosting, to: evidence.appendingPathComponent("explorer-insertion-failure.png"))
            // Diagnose a delayed native height correction without making the
            // original strict settled-position assertion weaker or retrying it.
            await settleNavigation()
            let later = nodes(hosting)
            fputs("Explorer List diagnostic later: \(nativeListDescription(list))\n", stderr)
            for (identifier, previous) in before {
                let current = later.first(where: { $0.identifier == identifier })?.frame
                fputs("Explorer card later \(identifier): old=\(previous), new=\(String(describing: current))\n", stderr)
            }
        }
        try expect(stationary && state.workspace.selectedCaptureID == projectB[4].id && state.route == .library,
            "An incoming Explorer capture preserves the cards being read and the remembered selection")
        // Sample again after the viewport guard's 600ms lifetime, not only
        // while it is correcting native estimated-height insertion frames.
        try await Task.sleep(for: .milliseconds(500))
        let settled = nodes(hosting)
        let stationaryAfterExpiry = before.allSatisfy { identifier, frame in
            guard let current = settled.first(where: { $0.identifier == identifier })?.frame else { return false }
            return abs(current.minY - frame.minY) <= 1 && abs(current.minX - frame.minX) <= 1
                && abs(current.height - frame.height) <= 1 && abs(current.width - frame.width) <= 1
        }
        fputs("Explorer List after anchor expiry: positions preserved=\(stationaryAfterExpiry); \(nativeListDescription(list))\n", stderr)
        for (identifier, previous) in before {
            let current = settled.first(where: { $0.identifier == identifier })?.frame
            fputs("Explorer card after anchor expiry \(identifier): old=\(previous), new=\(String(describing: current))\n", stderr)
        }
        try expect(stationaryAfterExpiry && state.workspace.selectedCaptureID == projectB[4].id && state.route == .library,
            "Explorer visible cards remain within one point after the bounded viewport guard has expired")
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
        draft.commentComposer = "An unposted reply survives every resize"
        draft.reminderDate = savedReminder.addingTimeInterval(3600)
        let pendingStep = "A next step that has not been added yet"
        let input = try findLabeled(hosting, label: "Add a next step")
        if let field = input.object as? NSTextField { _ = field.scrollToVisible(field.bounds); await settleNavigation() }
        try expect(input.setText(pendingStep), "Task detail accepts an unfinished checklist entry before resizing")
        await settleNavigation()
        let focusedEditor = window.firstResponder as? NSTextView
        for size in [expandedSize, shortSize, compactSize] {
            window.setContentSize(size)
            await settleNavigation()
            let currentInput = try findLabeled(hosting, label: "Add a next step")
            if let field = currentInput.object as? NSTextField { _ = field.scrollToVisible(field.bounds); await settleNavigation() }
            let currentText = (currentInput.object as? NSTextField)?.stringValue
                ?? (currentInput.value("accessibilityValue") as? String)
            try expect(currentText == pendingStep,
                "An unfinished checklist entry survives the layout change to \(Int(size.width))×\(Int(size.height))")
            try expect(state.selectedDraft === draft && draft.comment == "Unsaved note survives every resize"
                && draft.commentComposer == "An unposted reply survives every resize"
                && draft.reminderDate == savedReminder.addingTimeInterval(3600) && draft.hasChanges,
                "Resizing preserves the same unsaved comment, composer and reminder draft")
            let detailNodes = nodes(hosting, includeSubviews: false)
            try expect(state.detailFocus == "task" && detailNodes.contains { $0.identifier == "detail-pane-task" }
                && detailNodes.contains { $0.identifier == "task-checklist-new" }
                && detailNodes.contains { $0.identifier == "detail-section-reminder" }
                && !detailNodes.contains { $0.identifier == "capture-comment-composer" || $0.identifier == "capture-reminder-panel" },
                "Resizing retains the exclusive Task pane and native checklist; Comments and Reminder remain separate sections")
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
        // Comments and Reminder are mutually exclusive tabs, not simultaneous
        // disclosures. Exercise their real actions after the resize/focus checks
        // and verify neither selecting a tab nor resizing implicitly saves.
        try expect(try find(hosting, id: "detail-section-reminder").press(),
            "The retained Reminder section opens its actual scheduling panel")
        await settleNavigation()
        for size in [expandedSize, compactSize] {
            window.setContentSize(size)
            await settleNavigation()
            let detailNodes = nodes(hosting, includeSubviews: false)
            try expect(state.detailFocus == "reminder" && detailNodes.contains { $0.identifier == "capture-reminder-panel" }
                && detailNodes.contains { $0.identifier == "reminder-mode-date" || $0.label == "Date" }
                && !detailNodes.contains { $0.identifier == "capture-comment-composer" },
                "The selected Reminder panel and date controls survive compact/expanded resizing")
            try expect(state.selectedDraft === draft && draft.comment == "Unsaved note survives every resize"
                && draft.commentComposer == "An unposted reply survives every resize"
                && draft.reminderDate == savedReminder.addingTimeInterval(3600) && draft.hasChanges,
                "Tab selection and resizing retain all unpublished changes in the original draft")
        }
        try expect(try find(hosting, id: "detail-section-comments").press(),
            "Comments can be opened without saving or removing the reminder")
        await settleNavigation()
        try expect(nodes(hosting, includeSubviews: false).contains { $0.identifier == "capture-comment-composer" }
            && !nodes(hosting, includeSubviews: false).contains { $0.identifier == "capture-reminder-panel" }
            && draft.commentComposer == "An unposted reply survives every resize",
            "Returning to Comments restores its unposted composer")
        window.setContentSize(expandedSize); await settleNavigation()
        try expect(try find(hosting, id: "detail-section-task").press(),
            "The real Task section action returns to the retained checklist")
        await settleNavigation()
        window.setContentSize(compactSize); await settleNavigation()
        let retainedInput = try findLabeled(hosting, label: "Add a next step")
        if let field = retainedInput.object as? NSTextField { _ = field.scrollToVisible(field.bounds); await settleNavigation() }
        let retainedInputText = (retainedInput.object as? NSTextField)?.stringValue
            ?? (retainedInput.value("accessibilityValue") as? String)
        try expect(retainedInputText == pendingStep,
            "Switching annotation tabs preserves the unfinished task checklist input")
        try expect(task.comment == "Saved task context" && task.reminderAt == savedReminder
            && task.taskPlanning?.checklist.count == 1 && draft.planning.checklist.count == 1,
            "Window resizing and annotation tabs neither commit draft edits nor add unfinished checklist input")
    }

    @MainActor private static func run() async throws {
        let application = NSApplication.shared
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
        try expect(try find(hosting, id: "project-workspace").frame.width > 0,
            "A named project opens the new unified workspace")
        let initialProjectViewport = try find(hosting, id: "project-items").frame
        try expect(nodes(hosting).contains {
            $0.identifier?.hasPrefix("project-preview-") == true && $0.frame.width >= 32 && $0.frame.height >= 32
                && initialProjectViewport.insetBy(dx: -1, dy: -1).contains($0.frame)
        }, "The named-project workspace exposes a reachable 32-point native content-opening target")
        // Project view intentionally removes redundant mode tabs. Enter an
        // auxiliary view, then retain real accessible tab coverage there.
        state.workspace.mode = .clipboard; settle()
        for mode in [WorkspaceMode.clipboard, .shelf, .scratchpad, .collection] {
            let previousMode = state.workspace.mode
            let historyIndex = state.navigationHistory.index
            let button = try find(hosting, id: "workspace-mode-\(mode.rawValue)")
            try expect(button.frame.width >= 28 && button.frame.height >= 28, "Workspace mode \(mode.title) has a usable hit target")
            try expect(button.press(), "Workspace mode \(mode.title) supports accessible activation")
            settle()
            try expect(state.workspace.mode == mode && state.libraryProject == "Client A", "Mode change keeps the selected project")
            try expect(state.navigationHistory.index == historyIndex + (previousMode == mode ? 0 : 1),
                "The real \(mode.title) tab records exactly one deliberate destination, while reselecting the current tab records none")
        }
        let collectionHistoryIndex = state.navigationHistory.index
        try expect(try find(hosting, id: "board-back").press(), "Back activates after the real workspace mode tabs")
        await settleNavigation()
        try expect(state.route == .library && state.workspace.mode == .scratchpad && state.libraryProject == "Client A"
            && state.navigationHistory.index == collectionHistoryIndex - 1
            && state.workspace.scratchpad(project: "Client A").contains("Client A resume note"),
            "Real tab Back restores the preceding Scratchpad, project and existing note without skipping to Inbox")
        try expect(try find(hosting, id: "board-forward").press(), "Forward activates after restoring the preceding workspace mode")
        await settleNavigation()
        try expect(state.route == .library && state.workspace.mode == .collection && state.libraryProject == "Client A"
            && state.navigationHistory.index == collectionHistoryIndex,
            "Real tab Forward restores the visited project collection without making another history entry")
        try expect(try find(hosting, id: "project-workspace").frame.width > 0,
            "Explorer mode returns a named project to the unified preview workspace")
        state.workspace.mode = .scratchpad; settle()
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
        let evidence = ProcessInfo.processInfo.environment["DABIN_WORKSPACE_WINDOW_QA_OUTPUT"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? URL(fileURLWithPath: files.currentDirectoryPath).appendingPathComponent("build/qa/workspace-window-evidence")
        try files.createDirectory(at: evidence, withIntermediateDirectories: true)
        for size in [NSSize(width: 380, height: 430), NSSize(width: 620, height: 680), NSSize(width: 1280, height: 850)] {
            window.setContentSize(size); settle()
            for mode in WorkspaceMode.allCases {
                state.workspace.mode = mode; settle()
                let visibleContent = window.convertToScreen(hosting.convert(hosting.bounds, to: nil))
                if mode == .collection {
                    let picker = try find(hosting, id: "workspace-project-picker")
                    try expect(picker.valueText == "4 items", "Project dropdown includes captures and live notes in its total")
                    try expect(visibleContent.insetBy(dx: -1, dy: -1).contains(picker.interactionFrame),
                        "Project name and count remain inside the \(Int(size.width))-point header")
                    // Card identity belongs to the item viewport. Scope this
                    // compact-header regression above that viewport rather than
                    // rejecting the project names intentionally shown on cards.
                    let projectItems = try find(hosting, id: "project-items")
                    let headerBottom = projectItems.frame.maxY
                    try expect(projectItems.frame.width > 0 && projectItems.frame.height > 0
                        && picker.interactionFrame.minY >= headerBottom - 1,
                        "Project header is above the populated item viewport")
                    let visibleHeader = nodes(hosting).filter {
                        $0.frame.width > 0 && $0.frame.height > 0
                            && $0.frame.minY >= headerBottom - 1
                            && visibleContent.intersects($0.frame)
                    }
                    try expect(!visibleHeader.contains { $0.label == "Client A" || $0.label?.contains("One place for your project") == true },
                        "Project header has no duplicate name or tagline; cards may show their project")
                    try expect(try find(hosting, id: "project-workspace").frame.width > 0,
                        "Named-project workspace is available at \(Int(size.width))-point width")
                    try expect(nodes(hosting).contains {
                        $0.identifier?.hasPrefix("project-preview-") == true && $0.frame.width >= 32 && $0.frame.height >= 32
                            && projectItems.frame.insetBy(dx: -1, dy: -1).contains($0.frame)
                    }, "Project content retains a fully visible 32-point open target at \(Int(size.width))-point width")
                    for id in ["board-search", "project-export", "project-actions"] {
                        let action = try find(hosting, id: id)
                        try expect(action.frame.width > 0 && visibleContent.insetBy(dx: -1, dy: -1).contains(action.frame),
                            "\(id) remains inside the \(Int(size.width))×\(Int(size.height)) project workspace")
                    }
                    try expect(!nodes(hosting).contains { ["project-search", "explorer-search"].contains($0.identifier ?? "") },
                        "Projects retains header Search without a duplicate inner entry at \(Int(size.width))-point width")
                    try expect(try find(hosting, id: "project-export").label == "Export Selected",
                        "Selection export keeps its explicit text at \(Int(size.width))-point width")
                    try expect(!nodes(hosting).contains {
                        $0.frame.width > 0 && (["project-export-all", "project-export-selection"].contains($0.identifier ?? "")
                            || ["Export", "Copy project", "Copy", "Export ZIP"].contains($0.label ?? ""))
                    }, "Projects avoids duplicate day/week export and standalone copy menus at \(Int(size.width))-point width")
                    try await selectProjectFilter("Files", in: hosting, message: "Project Files filter is usable below the compact header")
                    try expect(state.projectPresentation["Client A"]?.filterRawValue == "Files",
                        "The real Files filter action updates the current project's visible type scope")
                    try expect(try find(hosting, id: "workspace-project-picker").valueText == "4 items",
                        "Filtering the grid never changes the dropdown's whole-project total")
                    try await selectProjectFilter("All", in: hosting, message: "Restore all project items")
                    try expect(state.projectPresentation["Client A"]?.filterRawValue == "All",
                        "The real All filter action restores the complete project's visible type scope")
                } else {
                    for modeButton in WorkspaceMode.allCases {
                        let frame = try find(hosting, id: "workspace-mode-\(modeButton.rawValue)").frame
                        try expect(frame.minX >= window.frame.minX - 1 && frame.maxX <= window.frame.maxX + 1,
                            "Workspace mode fits \(Int(size.width))-point width")
                    }
                }
                if mode == .clipboard || mode == .shelf {
                    for filter in CaptureFilter.allCases {
                        let frame = try find(hosting, id: "capture-filter-\(filter.rawValue)").frame
                        try expect(frame.width >= 28 && frame.height >= 28 && visibleContent.contains(frame),
                            "\(filter.title) filter remains visible and usable at \(Int(size.width))×\(Int(size.height))")
                    }
                    if mode == .shelf {
                        let export = try find(hosting, id: "workspace-export-shelf")
                        try expect(export.label == "Export shelf as ZIP" && export.role == "AXButton",
                            "Shelf export states its ZIP scope through one direct button at \(Int(size.width))-point width")
                        try expect(export.frame.width > 0 && export.frame.height > 0
                            && visibleContent.insetBy(dx: -1, dy: -1).contains(export.frame),
                            "The labeled Shelf export stays wholly within the \(Int(size.width))×\(Int(size.height)) workspace: \(export.frame) in \(visibleContent)")
                    }
                } else if mode == .scratchpad {
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
            state.workspace.mode = .collection; settle()
            let projectContent = window.convertToScreen(hosting.convert(hosting.bounds, to: nil))
            let collectionPicker = try find(hosting, id: "workspace-project-picker")
            try expect(collectionPicker.valueText == "1 item", "A notes-only project has the singular item count")
            try expect(collectionPicker.label?.contains(longProject) == true
                && projectContent.insetBy(dx: -1, dy: -1).contains(collectionPicker.interactionFrame),
                "Long project name and count fit together at \(Int(size.width))-point width")
            try saveImage(hosting, to: evidence.appendingPathComponent("workspace-long-project-collection-\(Int(size.width))x\(Int(size.height))-light.png"))
            let incoming = try store.capture(text: "Fictional incoming project capture", projectName: longProject)[0]
            settle()
            try expect(try find(hosting, id: "workspace-project-picker").valueText == "2 items", "Incoming captures refresh the dropdown count immediately")
            try store.setOrganization(incoming, pinned: false, projectName: "Other count fixture")
            settle()
            try expect(try find(hosting, id: "workspace-project-picker").valueText == "1 item", "Moving a capture refreshes the project count")
            state.workspace.mode = .scratchpad; settle()
            let visible = window.convertToScreen(hosting.convert(hosting.bounds, to: nil))
            let projectPicker = try find(hosting, id: "workspace-project-picker")
            try expect(visible.insetBy(dx: -1, dy: -1).contains(projectPicker.interactionFrame), "Long Workspace project remains inside the \(Int(size.width))-point window")
            try expect(projectPicker.label?.contains(longProject) == true, "Truncated project keeps its full accessible name")
            try expect(visible.contains(try find(hosting, id: "workspace-scratchpad-save-status").frame),
                "Scratchpad save status stays visible beside a long project name")
            try saveImage(hosting, to: evidence.appendingPathComponent("workspace-long-project-notes-\(Int(size.width))x\(Int(size.height))-light.png"))
            state.showReminders(); await settleNavigation()
            for scope in ["today", "later", "done"] {
                state.todayPlanningScope = scope; settle()
                let receiptsHeading = try find(hosting, id: "today-receipts-heading")
                try expect(visible.contains(receiptsHeading.frame), "Captured today remains visible before the \(scope) work plan at \(Int(size.width))-point width")
                try expect(visible.contains(try find(hosting, id: "today-receipts-count").frame),
                    "Today's receipt count stays visible for the \(scope) work plan at \(Int(size.width))-point width")
            }
            state.todayPlanningScope = "today"; settle()
            guard let receipt = state.currentTodayCaptures.first, let receiptText = receipt.originalText else {
                throw NSError(domain: "WorkspaceWindowTests", code: 12,
                    userInfo: [NSLocalizedDescriptionKey: "Today compact receipt fixture is missing its current text capture"])
            }
            try expect(receiptText == "Fictional incoming project capture" && state.workspaceZoom.factor == 1,
                "Compact receipt geometry uses the first actual short receipt at 100 percent zoom")
            let receiptCard = try find(hosting, id: "today-receipt-card-\(receipt.id.uuidString)")
            let compactReceipt = try find(hosting, id: "capture-compact-receipt-\(receipt.id.uuidString)")
            try expect(receiptCard.frame.width > 0 && receiptCard.frame.height > 0 && receiptCard.frame.height <= 140
                && compactReceipt.frame.width > 0 && compactReceipt.frame.height > 0
                && visible.insetBy(dx: -1, dy: -1).contains(receiptCard.frame),
                "The first compact receipt fits wholly inside the \(Int(size.width))×\(Int(size.height)) viewport and stays at most 140 points tall: \(receiptCard.frame)")
            let copyReceipt = try find(hosting, id: CaptureCopyButton.accessibilityIdentifier(for: [receipt]))
            let openReceipt = try find(hosting, id: "capture-compact-open-\(receipt.id.uuidString)")
            let moreReceipt = try find(hosting, id: "capture-more-\(receipt.id.uuidString)")
            for action in [copyReceipt, openReceipt, moreReceipt] {
                try expect(action.isEnabled && action.interactionFrame.width > 0 && action.interactionFrame.height >= 28
                    && visible.insetBy(dx: -1, dy: -1).contains(action.interactionFrame),
                    "Compact receipt action \(action.identifier ?? "unknown") has a visible usable native target at \(Int(size.width))-point width")
            }
            let copiesBefore = copiedPayloads.count
            try expect(copyReceipt.press(), "Compact receipt Copy supports direct accessible activation")
            await settleNavigation()
            try expect(copiedPayloads.count == copiesBefore + 1 && copiedPayloads.last?.items == [.text(receiptText)]
                && state.route == .reminders,
                "Compact receipt Copy writes its full original text through the private clipboard handler and keeps Today open")
            try expect(openReceipt.press(), "Compact receipt title supports direct accessible activation")
            await settleNavigation()
            try expect(state.route == .detail && state.selectedCapture?.id == receipt.id,
                "The compact receipt title opens the exact captured item")
            state.back(); await settleNavigation()
            try expect(state.route == .reminders && state.todayPlanningScope == "today"
                && state.libraryProject == longProject && state.currentTodayCaptures.first?.id == receipt.id,
                "Back from a receipt restores Today, its work plan scope and project without changing receipt membership")
            let todayProject = try find(hosting, id: "today-project-picker")
            try expect(visible.insetBy(dx: -1, dy: -1).contains(todayProject.interactionFrame), "Long Today project remains inside the \(Int(size.width))-point window")
            try expect(todayProject.label?.contains(longProject) == true, "Today exposes the full project name to accessibility")
            try expect(visible.contains(try find(hosting, id: "today-plan-summary").frame), "Today's task count stays visible beside a long project name")
            let add = try find(hosting, id: "today-add-task")
            try expect(add.frame.width >= 28 && add.frame.height >= 28 && visible.contains(add.frame), "Today Add has a visible usable hit target")
            try saveImage(hosting, to: evidence.appendingPathComponent("today-long-project-\(Int(size.width))x\(Int(size.height))-light.png"))
        }
        // Keep the actual compact Board fixed at minimum width while its
        // receipt content grows. Window coupling must not mask a clipped action.
        window.setContentSize(NSSize(width: 380, height: 680)); await settleNavigation()
        guard let zoomReceipt = state.currentTodayCaptures.first, let zoomReceiptText = zoomReceipt.originalText else {
            throw NSError(domain: "WorkspaceWindowTests", code: 13,
                userInfo: [NSLocalizedDescriptionKey: "Today zoom fixture is missing its current text receipt"])
        }
        for factor in [CGFloat(1.5), 2] {
            state.workspaceZoom.setFactor(factor); await settleNavigation()
            let scroll = try listScrollView(in: hosting)
            let viewport = window.convertToScreen(scroll.contentView.convert(scroll.contentView.bounds, to: nil))
            let receiptCard = try find(hosting, id: "today-receipt-card-\(zoomReceipt.id.uuidString)")
            let compactReceipt = try find(hosting, id: "capture-compact-receipt-\(zoomReceipt.id.uuidString)")
            try expect(state.workspaceZoom.factor == factor && abs(hosting.bounds.width - 380) <= 1,
                "Today zoom check renders \(Int(factor * 100)) percent in the actual 380-point Board")
            for surface in [receiptCard, compactReceipt] {
                try expect(surface.frame.width > 0 && surface.frame.height > 0
                    && viewport.insetBy(dx: -1, dy: -1).contains(surface.frame),
                    "The first receipt surface stays fully inside the native Today viewport at \(Int(factor * 100)) percent: \(surface.frame) in \(viewport)")
            }
            let copyReceipt = try find(hosting, id: CaptureCopyButton.accessibilityIdentifier(for: [zoomReceipt]))
            let moreReceipt = try find(hosting, id: "capture-more-\(zoomReceipt.id.uuidString)")
            for action in [copyReceipt, moreReceipt] {
                try expect(action.isEnabled && action.interactionFrame.width > 0 && action.interactionFrame.height >= 28
                    && viewport.insetBy(dx: -1, dy: -1).contains(action.interactionFrame),
                    "Compact receipt \(action.identifier ?? "unknown") remains visible inside the native content width at \(Int(factor * 100)) percent: \(action.interactionFrame) in \(viewport)")
            }
            try saveImage(hosting, to: evidence.appendingPathComponent("today-compact-receipt-380x680-zoom-\(Int(factor * 100))-light.png"))
            let copiesBefore = copiedPayloads.count
            try expect(copyReceipt.press(), "Compact receipt Copy activates at \(Int(factor * 100)) percent")
            await settleNavigation()
            try expect(copiedPayloads.count == copiesBefore + 1 && copiedPayloads.last?.items == [.text(zoomReceiptText)]
                && state.route == .reminders,
                "Zoomed Copy writes the full receipt text through the private handler without navigating")
        }
        state.workspaceZoom.reset(); await settleNavigation()
        try expect(state.workspaceZoom.factor == 1, "Today zoom fixture restores 100 percent before subsequent task checks")
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
        let planCard = try await scrollControlIntoView(hosting, id: "today-task-card-\(task.id.uuidString)", window: window)
        guard let taskMore = nodes(hosting).first(where: {
            $0.identifier == "capture-more-\(task.id.uuidString)" && planCard.frame.contains($0.frame)
        }) else { throw NSError(domain: "WorkspaceWindowTests", code: 12,
                                 userInfo: [NSLocalizedDescriptionKey: "The planned task card needs its own More control"]) }
        let moreTarget: NSRect
        if let cell = taskMore.object as? NSCell, let view = cell.controlView {
            moreTarget = window.convertToScreen(view.convert(view.bounds, to: nil))
        } else { moreTarget = taskMore.frame }
        try expect(moreTarget.width >= 32 && moreTarget.height >= 32,
                   "Task actions remain reachable through one aligned More target")
        // Real native menu reordering and restart persistence are exercised by
        // TodayTaskCardTests. This full-board fixture verifies the action stays
        // reachable without restoring separate always-visible reorder arrows.
        try expect(TaskPlanningPolicy.today(store.captures).filter { $0.projectName == "Client A" }.map(\.id) == [task.id, nextTask.id],
                   "Rendering the simplified card leaves planned task order unchanged")

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
        state.workspace.mode = .clipboard; state.openLibrary(); await settleNavigation()
        state.libraryProject = "Scroll client A"; await settleNavigation()
        try expect(try selectedCardIsVisible(scrollA[1].id, in: hosting, window: window),
            "Changing project in place brings its remembered deep card into view")
        state.libraryProject = "Scroll client B"; await settleNavigation()
        try expect(try selectedCardIsVisible(scrollB[14].id, in: hosting, window: window),
            "Returning to another project restores its own selected card")
        let scrollTask = try store.createTask(text: "A task excluded from Clipboard")
        try store.setOrganization(scrollTask, pinned: false, projectName: "Scroll client B")
        state.workspace.selectedCaptureID = scrollTask.id
        state.workspace.mode = .collection; await settleNavigation()
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
        let checklistInput = try findLabeled(editor, label: "Add a next step")
        try expect(checklistInput.setText(String(repeating: "x", count: 501)), "Checklist input supports accessible editing")
        settle()
        try expect(!(try find(editor, id: "task-checklist-add").isEnabled), "A 501-character step cannot activate Add")
        try expect(nodes(editor).contains { $0.label?.contains("500 characters") == true },
            "An oversized step explains the 500-character limit")
        try expect(editorDraft.planning.checklist.count == 1, "Invalid input preserves the existing checklist")
        try expect(checklistInput.setText("  " + String(repeating: "x", count: 500) + "  "), "Checklist text can be corrected without losing it")
        settle()
        let addStep = try find(editor, id: "task-checklist-add")
        try expect(addStep.isEnabled && addStep.press(), "A corrected 500-character step can be added")
        settle()
        try expect(editorDraft.planning.checklist.count == 2 && editorDraft.planning.checklist.last?.text.count == 500,
            "A maximum-length valid step is stored exactly after trimming outer spaces")
        try await checkExplorer(state: state, hosting: hosting, window: window, evidence: evidence)
        try await checkCaptions(state: state, theme: theme, hosting: hosting, window: window, evidence: evidence)
        print("PASS: \(checks) native workspace interaction and responsive layout checks")
        print("Workspace screenshots: \(evidence.path)")
    }
}
