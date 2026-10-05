import AppKit
import ApplicationServices
import SwiftUI

@MainActor private final class DetailNavigationReminderClient: ReminderNotificationClient {
    private(set) var requests = 0
    private(set) var additions = 0
    func authorization() async -> ReminderAuthorization { .undetermined }
    func requestAuthorization() async throws -> Bool { requests += 1; return false }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { additions += 1 }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}

/// Reads native objects belonging to this test process. Raw NSView traversal is
/// used only to verify that inactive editors remain mounted; reachability uses
/// the accessibility tree, so hidden panes cannot masquerade as visible ones.
@MainActor private struct DetailNavigationAXNode {
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
    var rawAccessibilityLabel: String? { value("accessibilityLabel") as? String }
    var supportsAccessibilityLabel: Bool { object.responds(to: NSSelectorFromString("accessibilityLabel")) }
    var label: String {
        [value("accessibilityLabel"), value("accessibilityTitle"), attribute("AXTitle"), attribute("AXDescription"),
         value("accessibilityValue"), attribute("AXValue")]
            .compactMap { ($0 as? String) ?? ($0 as? NSAttributedString)?.string }.first { !$0.isEmpty } ?? ""
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
        return result
    }
}

@MainActor private struct DetailNavigationDraftSnapshot: Equatable {
    let title: String
    let comment: String
    let composer: String
    let editingID: UUID?
    let planning: TaskPlanning
    let reminderEnabled: Bool
    let reminderMode: String
    let countdownHours: Int
    let countdownMinutes: Int
    let reminderDate: Date
    init(_ draft: CaptureDraft) {
        title = draft.title; comment = draft.comment; composer = draft.commentComposer
        editingID = draft.editingCommentID; planning = draft.planning
        reminderEnabled = draft.reminderEnabled; reminderMode = draft.reminderMode.rawValue
        countdownHours = draft.countdownHours; countdownMinutes = draft.countdownMinutes
        reminderDate = draft.reminderDate
    }
}

@MainActor private final class DetailNavigationMenuTracking {
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

/// Disposable fictional records, private preferences, own-window events and
/// injected action spies. Never activates an app, accesses the real clipboard,
/// reads the user's archive, opens Finder, or invokes the notification system.
@main @MainActor private final class CaptureDetailNavigationTests: NSObject, NSApplicationDelegate {
    private static var checks = 0
    private static var evidence: [[String: Any]] = []
    private var result = 0
    private static let sections = ["preview", "task", "comments", "reminder", "text", "details"]
    private static let titles = ["preview": "Preview", "task": "Task", "comments": "Comments",
                                 "reminder": "Reminder", "text": "Recognized text", "details": "Details"]

    @MainActor private final class Services {
        let root: URL
        let preferencesName = "DaBinDetailNavigationQA.\(UUID().uuidString)"
        let defaults: UserDefaults
        let store: CaptureStore
        let previews: PreviewService
        let auto: AutoCaptureService
        let notifications = DetailNavigationReminderClient()
        var state: AppState!
        var copies: [CaptureClipboardPayload] = []
        var openedFolders: [URL] = []

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinDetailNavigationQA-\(UUID().uuidString)")
            defaults = UserDefaults(suiteName: preferencesName)!
            defaults.set(false, forKey: PreviewService.linkPreviewPreference)
            store = try CaptureStore(root: root, repairArchiveOnOpen: false)
            previews = PreviewService(store: store, defaults: defaults)
            auto = AutoCaptureService(settings: AutoCaptureSettings(defaults: defaults), input: InputService(store: store),
                pasteboardProvider: { fatalError("Detail navigation QA must not read the clipboard") },
                sourceApplicationProvider: { nil })
            state = AppState(store: store, previews: previews,
                reminders: ReminderService(store: store, client: notifications), autoCapture: auto,
                captureClipboard: CaptureClipboardService(writer: { [weak self] payload in
                    self?.copies.append(payload); return true
                }), folderOpener: { [weak self] url in self?.openedFolders.append(url); return true })
        }
        func close() {
            previews.shutdown(); auto.shutdown(); state.focusSessions.shutdown()
            state.shutdownNotificationPresentation(); store.cancelArchiveRepair()
            defaults.removePersistentDomain(forName: preferencesName)
            try? FileManager.default.removeItem(at: root)
        }
        func image(task: Bool) throws -> Capture {
            let id = UUID()
            let capture = Capture(id: id, capturedAt: Date(timeIntervalSince1970: 1_791_108_660),
                timeZone: TimeZone(secondsFromGMT: 0)!, kind: .image,
                originalText: "Fictional immutable source text", attachmentRelativePath: "Originals/\(id.uuidString)/fixture.png",
                originalFilename: "fixture.png", title: "Fictional compact capture")
            capture.indexedText = String(repeating: "Fictional OCR · שלום · 日本語 · Résumé · مرحبا.\n", count: 110)
            capture.contentIndexState = "ready"
            capture.contentIndexVersion = ContentIndexService.currentVersion
            capture.previewState = "ready"
            // Use a disposable owned file so converting the synthetic image does
            // not produce an unrelated archive-error banner in visual fixtures.
            let original = root.appendingPathComponent(capture.attachmentRelativePath!)
            try FileManager.default.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("Fictional synthetic image bytes".utf8).write(to: original)
            try CaptureRepository(root: root).save([capture]); try store.refresh()
            let current = store.captures.first { $0.id == id }!
            if task { try store.convertToTask(current) }
            return current
        }
    }

    static func main() {
        let application = NSApplication.shared
        let delegate = CaptureDetailNavigationTests()
        application.setActivationPolicy(.accessory); application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
        exit(Int32(delegate.result))
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await Self.run() }
            catch { result = 1; fputs("Capture detail navigation QA failed: \(error)\n", stderr) }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }
    private static func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard value() else { throw NSError(domain: "CaptureDetailNavigationTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    private static func nodes(_ view: NSView, includeSubviews: Bool = false) -> [DetailNavigationAXNode] {
        view.layoutSubtreeIfNeeded()
        var seen = Set<ObjectIdentifier>(), result: [DetailNavigationAXNode] = []
        func visit(_ value: Any, depth: Int) {
            guard depth < 60, let object = value as? NSObject,
                  seen.insert(ObjectIdentifier(object)).inserted else { return }
            let node = DetailNavigationAXNode(object: object); result.append(node)
            node.children.forEach { visit($0, depth: depth + 1) }
            if includeSubviews, let nativeView = object as? NSView {
                nativeView.subviews.forEach { visit($0, depth: depth + 1) }
            }
        }
        visit(view, depth: 0)
        NSAccessibility.unignoredChildren(from: [view]).forEach { visit($0, depth: 0) }
        return result
    }
    private static func settle(_ view: NSView) async {
        for _ in 0..<3 { view.layoutSubtreeIfNeeded(); try? await Task.sleep(for: .milliseconds(40)) }
    }
    private static func find(_ view: NSView, id: String) async throws -> DetailNavigationAXNode {
        for _ in 0..<8 {
            if let node = nodes(view).first(where: { $0.identifier == id }) { return node }
            await settle(view)
        }
        throw NSError(domain: "CaptureDetailNavigationTests", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Missing accessible control \(id): \(nodes(view).map { $0.identifier ?? $0.label }.joined(separator: "; "))"])
    }
    private static func findLabel(_ view: NSView, label: String) async throws -> DetailNavigationAXNode {
        for _ in 0..<8 {
            if let node = nodes(view).first(where: { $0.label == label && $0.object.responds(to: NSSelectorFromString("accessibilityPerformPress")) }) { return node }
            await settle(view)
        }
        throw NSError(domain: "CaptureDetailNavigationTests", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "Missing accessible action \(label)"])
    }
    private static func withFixture(_ services: Services, capture: Capture, size: CGSize, factor: CGFloat, board: Bool = false,
                                    entryFocus: String? = nil,
                                    body: (NSHostingView<AnyView>, NSWindow, CaptureDraft) async throws -> Void) async throws {
        services.state.openCapture(capture.id, focus: entryFocus)
        let draft = services.state.selectedDraft!
        let content: AnyView
        if board {
            services.state.workspaceZoom.setFactor(factor)
            let theme = ThemeSettings(defaults: services.defaults)
            theme.setShowTooltips(false); theme.setDarkMode(factor == 2)
            content = AnyView(BoardView(state: services.state, theme: theme).environment(\.displayScale, 2))
        } else {
            content = AnyView(DetailScreen(state: services.state, capture: capture, draft: draft)
                .environment(\.workspaceZoom, WorkspaceZoomLayout(factor: factor))
                .environment(\.daBinTooltipsEnabled, false).environment(\.displayScale, 2)
                .preferredColorScheme(factor == 2 ? .dark : .light).background(Palette.background))
        }
        let host = NSHostingView(rootView: content)
        // The app's window controls the viewport. Intrinsic NSHostingView sizing
        // must not silently grow a nominal 680-point fixture to its scroll size.
        host.sizingOptions = []; host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        window.orderFront(nil); await settle(host)
        let accessibility = await Task.detached {
            let process = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            AXUIElementSetMessagingTimeout(process, 3)
            var windows: CFTypeRef?
            return AXUIElementCopyAttributeValue(process, kAXWindowsAttribute as CFString, &windows)
        }.value
        try expect(accessibility == .success, "Fixture exposes its own process accessibility hierarchy")
        await settle(host)
        try expect(abs(host.bounds.width - size.width) < 1 && abs(host.bounds.height - size.height) < 1
            && abs(window.contentLayoutRect.width - size.width) < 1 && abs(window.contentLayoutRect.height - size.height) < 1,
                   "Native fixture's actual host and window match its requested \(Int(size.width))×\(Int(size.height)) viewport")
        try expect(window.frame.maxX < 0 && !window.isKeyWindow && !NSApp.isActive,
                   "Navigation fixture stays offscreen, non-key and inactive")
        try await body(host, window, draft)
        try expect(!window.isKeyWindow && !NSApp.isActive, "Native navigation does not activate another application")
    }
    private static func nativeMenu(_ host: NSView, id: String) async throws -> NSMenu {
        let target = try await find(host, id: id)
        let tracking = DetailNavigationMenuTracking(window: host.window)
        let center = NotificationCenter.default
        let began = center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { notification in
            guard let menu = notification.object as? NSMenu else { return }
            MainActor.assumeIsolated { tracking.began(menu) }
        }
        let ended = center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: nil) { notification in
            guard let menu = notification.object as? NSMenu else { return }
            MainActor.assumeIsolated { tracking.didEnd(menu) }
        }
        // SwiftUI's .menuStyle(.button) has a virtual accessibility button and
        // builds its NSMenu only when pressed. A timer in both relevant run-loop
        // modes closes its own menu if immediate cancellation precedes tracking.
        let timer = Timer(timeInterval: 0.02, repeats: true) { _ in
            MainActor.assumeIsolated { tracking.cancel() }
        }
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
        defer { timer.invalidate(); center.removeObserver(began); center.removeObserver(ended) }
        fputs("MENU activating \(id), role=\(target.role), actions=\(target.actions), frame=\(NSStringFromRect(target.frame))\n", stderr)
        var accepted = target.actions.contains("AXShowMenu") ? target.showMenu() : false
        if !accepted && tracking.menus.isEmpty && target.actions.contains("AXPress") { accepted = target.press() }
        if !accepted && tracking.menus.isEmpty {
            fputs("MENU using own-window visible-label click\n", stderr)
            guard let window = host.window else { throw NSError(domain: "CaptureDetailNavigationTests", code: 12) }
            try clickLabel(target, in: window)
        }
        await settle(host)
        let menu = tracking.menus.first { menu in
            let items = menuItems(menu)
            if id == "detail-section-picker" {
                return items.contains { $0.title == "Preview" } && items.contains { $0.title == "Comments" }
                    && items.contains { $0.title == "Reminder" }
            }
            return items.contains { $0.title == "Saved folder" || $0.title == "Show saved folder" }
                && items.contains { $0.title == "Trash" || $0.title.contains("Recently Deleted") }
        }
        guard let menu else { throw NSError(domain: "CaptureDetailNavigationTests", code: 4,
            userInfo: [NSLocalizedDescriptionKey: "\(id) must materialize its real native menu from AX or its visible label; role: \(target.role), actions: \(target.actions), menus: \(tracking.menus.map { $0.items.map(\.title) })"] ) }
        try expect(!tracking.timedOut && tracking.ended.contains(ObjectIdentifier(menu)),
                   "\(id) native menu tracking ends before dispatching a menu-item action")
        try expect(host.window?.isKeyWindow == false && !NSApp.isActive,
                   "Own-process menu activation preserves the fixture's inactive, non-key state")
        return menu
    }
    private static func clickLabel(_ node: DetailNavigationAXNode, in window: NSWindow) throws {
        let screenPoint = NSPoint(x: node.frame.midX, y: node.frame.midY)
        try expect(node.frame.width > 0 && node.frame.height > 0 && window.frame.contains(screenPoint),
                   "Menu label click targets only the fixture's visible native label")
        let point = window.convertPoint(fromScreen: screenPoint)
        let timestamp = ProcessInfo.processInfo.systemUptime
        guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
            timestamp: timestamp, windowNumber: window.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1),
              let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [],
            timestamp: timestamp + 0.02, windowNumber: window.windowNumber, context: nil,
            eventNumber: 2, clickCount: 1, pressure: 0) else { throw NSError(domain: "CaptureDetailNavigationTests", code: 13) }
        NSApp.postEvent(up, atStart: true); window.sendEvent(down)
        if let remaining = NSApp.nextEvent(matching: .leftMouseUp, until: Date(), inMode: .default, dequeue: true) {
            try expect(remaining.windowNumber == window.windowNumber, "Menu click mouse-up belongs only to the fixture window")
            window.sendEvent(remaining)
        }
    }
    private static func menuItems(_ menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { item in [item] + (item.submenu.map(menuItems) ?? []) }
    }
    private static func perform(_ item: NSMenuItem) throws {
        guard let menu = item.menu else { throw NSError(domain: "CaptureDetailNavigationTests", code: 5) }
        try expect(item.isEnabled && item.action != nil, "Native menu item \(item.title) exposes an enabled action")
        menu.performActionForItem(at: menu.index(of: item))
    }
    private static func select(_ section: String, in host: NSView) async throws {
        if let button = nodes(host).first(where: { $0.identifier == "detail-section-" + section }) {
            try expect(button.press(), "\(section) section supports native accessibility activation")
        } else {
            let menu = try await nativeMenu(host, id: "detail-section-picker")
            let expected = titles[section]!
            guard let item = menuItems(menu).first(where: {
                $0.identifier?.rawValue == "detail-section-option-" + section
                    || DetailNavigationAXNode(object: $0).identifier == "detail-section-option-" + section
                    || $0.title == expected || $0.title.hasPrefix(expected + " ")
            }) else { throw NSError(domain: "CaptureDetailNavigationTests", code: 6,
                userInfo: [NSLocalizedDescriptionKey: "Compact section menu has no \(expected) destination"] ) }
            try perform(item)
        }
        await settle(host)
        _ = try await find(host, id: "detail-pane-" + section)
        let exposed = Set(nodes(host).compactMap(\.identifier).filter { $0.hasPrefix("detail-pane-") })
        try expect(exposed == ["detail-pane-" + section], "Only selected \(section) pane is exposed to accessibility")
    }
    private static func contained(_ node: DetailNavigationAXNode, in viewport: NSRect, context: String) throws {
        try expect(node.frame.width > 0 && node.frame.height > 0
            && viewport.insetBy(dx: -1, dy: -1).contains(node.frame),
                   "\(context): \(node.identifier ?? node.label) fits inside the visible window")
    }
    private static func fixedControls(_ host: NSView, window: NSWindow, context: String) async throws -> [String: NSRect] {
        let viewport = window.convertToScreen(host.convert(host.bounds, to: nil))
        var frames: [String: NSRect] = [:]
        for id in ["detail-title", "detail-section-navigation", "detail-actions-more", "detail-save"] {
            let node = try await find(host, id: id)
            try contained(node, in: viewport, context: context); frames[id] = node.frame
        }
        let copy = try await findLabel(host, label: "Copy capture")
        try contained(copy, in: viewport, context: context)
        try expect(copy.frame.width > 32 && copy.frame.height >= 32,
                   "\(context): primary Copy keeps a readable label and pointer target")
        frames["copy"] = copy.frame
        return frames
    }
    private static func captureData(_ capture: Capture) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(CaptureSnapshot(capture))
    }
    private static func render(_ view: NSView, name: String, output: URL) throws {
        let size = view.bounds.size
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2),
            pixelsHigh: Int(size.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw NSError(domain: "CaptureDetailNavigationTests", code: 7)
        }
        bitmap.size = size; view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "CaptureDetailNavigationTests", code: 8)
        }
        try data.write(to: output.appendingPathComponent(name + "@2x.png"))
    }
    private static func layoutMatrix(output: URL) async throws {
        for width in [CGFloat(380), 600, 1_200] {
            for factor in [CGFloat(0.75), 1, 2] {
                let services = try Services(); defer { services.close() }
                let capture = try services.image(task: true)
                let before = try captureData(capture)
                let context = "navigation-\(Int(width))-zoom\(Int(factor * 100))"
                try await withFixture(services, capture: capture, size: CGSize(width: width, height: 680), factor: factor) { host, window, _ in
                    let initial = try await fixedControls(host, window: window, context: context)
                    if width == 380 { try render(host, name: context + "-before-menu", output: output) }
                    for section in sections {
                        try await select(section, in: host)
                        let current = try await fixedControls(host, window: window, context: context + "-" + section)
                        let fixed = ["detail-title", "detail-actions-more", "detail-save", "copy"]
                        try expect(fixed.allSatisfy { current[$0] == initial[$0] },
                                   "\(context): changing to \(section) keeps header, actions and Save fixed: \(current.mapValues(NSStringFromRect)) versus \(initial.mapValues(NSStringFromRect))")
                        let navigation = current["detail-section-navigation"]!, previous = initial["detail-section-navigation"]!
                        // Selected text changes weight and intrinsic label width.
                        // The navigation remains pinned to the same window row.
                        try expect(abs(navigation.midX - previous.midX) < 1
                            && abs(navigation.minY - previous.minY) < 1 && abs(navigation.height - previous.height) < 1,
                                   "\(context): changing to \(section) keeps navigation pinned while its selected label changes: \(NSStringFromRect(navigation)) versus \(NSStringFromRect(previous))")
                        if factor == 1 && [CGFloat(380), 1_200].contains(width)
                            && ["task", "comments", "reminder", "text"].contains(section) {
                            try render(host, name: context + "-" + section, output: output)
                        }
                    }
                    try await select("preview", in: host)
                    try render(host, name: context, output: output)
                    evidence.append(["context": context, "width": width, "height": 680, "zoom": factor,
                        "destinations": sections, "fixedControlFrames": initial.mapValues(NSStringFromRect)])
                }
                let after = try captureData(capture)
                try expect(after == before && services.copies.isEmpty && services.openedFolders.isEmpty
                    && services.notifications.requests == 0 && services.notifications.additions == 0,
                           "\(context): rendering and navigation have no capture, clipboard, Finder or notification side effects")
            }
        }
    }
    private static func persistenceAndRoutes(output: URL) async throws {
        let services = try Services(); defer { services.close() }
        let capture = try services.image(task: true), before = try captureData(capture)
        try await withFixture(services, capture: capture, size: CGSize(width: 600, height: 680), factor: 1) { host, window, draft in
            draft.title = "Pending fictional title"; draft.planning.priority = .high
            draft.reminderEnabled = true; draft.reminderMode = .countdown
            draft.countdownHours = 1; draft.countdownMinutes = 17
            services.state.detailFocus = "comment"; await settle(host)
            _ = try await find(host, id: "detail-pane-comments")
            let composerNode = try await find(host, id: "capture-comment-composer")
            let composer = (composerNode.object as? NSTextView)
                ?? nodes(host, includeSubviews: true).compactMap { $0.object as? NSTextView }.first { $0.isEditable }
            guard let composer else { throw NSError(domain: "CaptureDetailNavigationTests", code: 9,
                userInfo: [NSLocalizedDescriptionKey: "Comments must retain a real native editable text view"] ) }
            let pendingComment = "Unposted fictional reply · שלום"
            composer.insertText(pendingComment, replacementRange: NSRange(location: 0, length: composer.string.utf16.count))
            await settle(host)
            try expect(draft.commentComposer == pendingComment, "Native comment editing updates the recoverable composer draft")
            let composerID = ObjectIdentifier(composer), commentSelection = NSRange(location: 3, length: 8)
            composer.setSelectedRange(commentSelection)
            let pending = DetailNavigationDraftSnapshot(draft)

            try await select("text", in: host)
            let readerNode = try await find(host, id: "recognized-text-body")
            guard let reader = readerNode.object as? NSTextView else { throw NSError(domain: "CaptureDetailNavigationTests", code: 10) }
            let readerID = ObjectIdentifier(reader), readerSelection = NSRange(location: 40, length: 20)
            reader.setSelectedRange(readerSelection)
            let toggle = try await find(host, id: "recognized-text-toggle")
            try expect(toggle.press(), "Text pane supports native expansion of complete recognized text")
            await settle(host)
            try expect(reader.string == capture.indexedText, "Text expansion displays the complete synthetic index")
            reader.enclosingScrollView?.contentView.scroll(to: NSPoint(x: 0, y: 60))
            reader.enclosingScrollView?.reflectScrolledClipView(reader.enclosingScrollView!.contentView)
            let readerScroll = reader.enclosingScrollView?.contentView.bounds.origin

            for destination in ["reminder", "comments"] {
                try await select("text", in: host)
                try expect(window.makeFirstResponder(reader) && window.firstResponder === reader,
                           "Visible native OCR reader can receive the fixture's own first responder")
                let action = try await find(host, id: "detail-section-" + destination)
                try expect(action.press(), "\(destination) shortcut supports actual AX navigation away from focused OCR")
                await settle(host)
                _ = try await find(host, id: "detail-pane-" + destination)
                try expect(window.firstResponder !== reader,
                           "Navigating to \(destination) releases the hidden OCR reader as first responder")
                try expect(reader.selectedRange() == readerSelection
                    && reader.enclosingScrollView?.contentView.bounds.origin == readerScroll,
                           "Releasing hidden OCR focus preserves its selected text and reading position")
            }

            for (focus, section) in [("reminder", "reminder"), ("task", "task"), ("comment", "comments")] {
                services.state.detailFocus = focus; await settle(host)
                _ = try await find(host, id: "detail-pane-" + section)
                let exposed = Set(nodes(host).compactMap(\.identifier).filter { $0.hasPrefix("detail-pane-") })
                try expect(exposed == ["detail-pane-" + section], "Existing detail route \(focus) directly reveals only its destination")
            }
            for section in ["details", "preview", "task", "reminder", "comments"] { try await select(section, in: host) }
            try expect(ObjectIdentifier(composer) == composerID && composer.string == pendingComment
                && composer.selectedRange() == commentSelection,
                       "Comment editor identity, unposted reply and selection survive section navigation")
            try expect(DetailNavigationDraftSnapshot(draft) == pending,
                       "Section changes preserve unsaved title, comment, reminder and task planning fields")
            try await select("text", in: host)
            let returnedReader = try await find(host, id: "recognized-text-body")
            try expect((returnedReader.object as? NSTextView).map(ObjectIdentifier.init) == readerID
                && reader.string == capture.indexedText && reader.selectedRange() == readerSelection
                && reader.enclosingScrollView?.contentView.bounds.origin == readerScroll,
                       "Returning to Text preserves native reader identity, expansion, selection and scroll position")
            for width in [CGFloat(380), 1_200, 600] {
                window.setContentSize(CGSize(width: width, height: 680)); host.frame.size = CGSize(width: width, height: 680)
                await settle(host)
                _ = try await fixedControls(host, window: window, context: "resize-\(Int(width))")
                try await select("comments", in: host)
                if width == 1_200 {
                    try expect(window.makeFirstResponder(composer) && window.firstResponder === composer,
                               "Visible native comment editor can receive the fixture's own first responder")
                    let textAction = try await find(host, id: "detail-section-text")
                    try expect(textAction.press(), "Wide Text button supports actual AX navigation away from focused Comments")
                    await settle(host)
                    _ = try await find(host, id: "detail-pane-text")
                    try expect(window.firstResponder !== composer && composer.string == pendingComment
                        && composer.selectedRange() == commentSelection,
                               "Navigating to Text releases the hidden Comments editor while retaining its unfinished reply and selection")
                }
                try await select("text", in: host)
                let resizedReader = try await find(host, id: "recognized-text-body")
                try expect((resizedReader.object as? NSTextView).map(ObjectIdentifier.init) == readerID
                    && reader.selectedRange() == readerSelection && DetailNavigationDraftSnapshot(draft) == pending,
                           "Resizing through compact and wide navigation preserves reader and unfinished work")
            }
            try render(host, name: "navigation-drafts-and-ocr-resume", output: output)
        }
        let after = try captureData(capture)
        try expect(after == before && services.copies.isEmpty && services.openedFolders.isEmpty
            && services.notifications.requests == 0 && services.notifications.additions == 0,
                   "Editing and revisiting panes never commits capture changes or triggers external services")
    }
    private static func actionsAndConditionalSections() async throws {
        let services = try Services(); defer { services.close() }
        let capture = try services.image(task: false)
        try await withFixture(services, capture: capture, size: CGSize(width: 380, height: 680), factor: 1) { host, window, _ in
            let viewport = window.convertToScreen(host.convert(host.bounds, to: nil))
            let makeTask = try await findLabel(host, label: "Turn \(capture.title) into a task")
            try contained(makeTask, in: viewport, context: "compact-nontask")
            let menu = try await nativeMenu(host, id: "detail-section-picker")
            try expect(!menuItems(menu).contains { $0.title == "Task" }, "Ordinary capture does not offer an empty Task destination")
            let copy = try await findLabel(host, label: "Copy capture")
            try expect(copy.press(), "Fixed primary Copy is a real accessible action")
            await settle(host)
            try expect(services.copies.count == 1 && services.copies[0].items.count == 1,
                       "One Copy activation writes exactly one synthetic payload through the injected spy")
            let more = try await nativeMenu(host, id: "detail-actions-more")
            evidence.append(["context": "native-more-menu-metadata", "items": menuItems(more).map { item in
                let node = DetailNavigationAXNode(object: item)
                return ["title": item.title, "identifier": item.identifier?.rawValue ?? "",
                    "accessibilityIdentifier": node.identifier ?? "", "accessibilityLabel": node.rawAccessibilityLabel ?? "",
                    "supportsAccessibilityLabel": node.supportsAccessibilityLabel,
                    "resolvedAccessibilityLabel": node.label, "role": node.role, "enabled": item.isEnabled,
                    "hidden": item.isHidden, "hasAction": item.action != nil] as [String: Any]
            }])
            let original = menuItems(more).first { $0.title == "Open original" }
            let folder = menuItems(more).first { $0.title == "Show saved folder" || $0.title == "Saved folder" }
            let trash = menuItems(more).first { $0.title == "Trash" || $0.title.contains("Recently Deleted") }
            try expect(original != nil && folder != nil && trash != nil,
                       "More preserves original, saved folder and reversible trash destinations")
            try perform(folder!); await settle(host)
            try expect(services.openedFolders.count == 1 && services.openedFolders[0].path.hasPrefix(services.root.path),
                       "Saved folder menu action uses only the disposable archive and injected opener once")
            let originalURL = services.store.managedURL(for: capture)!
            try FileManager.default.removeItem(at: originalURL)
            try perform(original!); await settle(host)
            try expect(services.state.status?.severity == .error && capture.attachmentRelativePath != nil,
                       "Open original's safe missing-file error preserves the capture's original metadata")
            try Data("Fictional synthetic image bytes".utf8).write(to: originalURL)
            try perform(trash!); await settle(host)
            try expect(services.state.pendingRemoval?.id == capture.id && services.store.trashedCaptures.isEmpty,
                       "Trash menu action requests confirmation without deleting the fixture")
            services.state.pendingRemoval = nil
            try expect(makeTask.press(), "Fixed Make task activates the real conversion action")
            await settle(host)
            try expect(capture.isTask, "Make task converts the selected synthetic capture")
            try await select("task", in: host)
            try expect(services.store.captures.count == 1 && capture.originalText == "Fictional immutable source text",
                       "Task conversion keeps the original capture and adds a reachable Task workspace")
        }
        let note = try services.store.createNote(text: "Fictional plain note")
        try await withFixture(services, capture: note, size: CGSize(width: 380, height: 680), factor: 1) { host, _, _ in
            let menu = try await nativeMenu(host, id: "detail-section-picker")
            try expect(!menuItems(menu).contains { $0.title == "Text" || $0.title == "Recognized text" || $0.title == "Task" },
                       "Plain notes omit unavailable OCR and task destinations rather than dead panes")
            for section in ["preview", "comments", "reminder", "details"] { try await select(section, in: host) }
        }
        try expect(services.notifications.requests == 0 && services.notifications.additions == 0,
                   "Capture actions and navigation never request notification permissions")
    }
    private static func explicitSectionHistory() throws {
        let services = try Services(); defer { services.close() }
        let first = try services.image(task: true)
        let second = try services.store.createNote(text: "Fictional second capture for section history")
        let firstBefore = try captureData(first), secondBefore = try captureData(second)
        let state = services.state!
        state.openCapture(first.id, focus: "comment")
        let firstDraft = state.selectedDraft!
        firstDraft.commentComposer = "Unposted fictional history reply"
        let commentAnchor = NavigationViewportAnchor(itemID: "capture:" + first.id.uuidString, offset: -57)
        state.workspaceViewport = commentAnchor
        state.openCapture(first.id, focus: "reminder")
        try expect(state.selectedCapture?.id == first.id && state.detailFocus == "reminder"
            && state.workspaceViewport == nil && state.selectedDraft === firstDraft,
                   "Explicit different section focus on the same capture clears its outgoing pane anchor and retains the live draft")
        let reminderAnchor = NavigationViewportAnchor(itemID: "capture:" + first.id.uuidString, offset: -23)
        state.workspaceViewport = reminderAnchor
        state.openCapture(first.id, focus: "reminder")
        try expect(state.workspaceViewport == reminderAnchor,
                   "Repeated explicit focus on the same section retains its current reading position")
        state.openCapture(second.id, focus: "comment")
        try expect(state.workspaceViewport == nil, "Opening a different capture starts with its own destination viewport")
        let secondDraft = state.selectedDraft!
        secondDraft.commentComposer = "Second unposted fictional reply"
        let secondAnchor = NavigationViewportAnchor(itemID: "capture:" + second.id.uuidString, offset: -41)
        state.workspaceViewport = secondAnchor
        state.back()
        try expect(state.route == .detail && state.selectedCapture?.id == first.id && state.detailFocus == "reminder"
            && state.workspaceViewport == reminderAnchor && state.selectedDraft === firstDraft,
                   "Back restores the destination capture's saved section and viewport instead of applying explicit-focus clearing")
        state.forward()
        try expect(state.route == .detail && state.selectedCapture?.id == second.id && state.detailFocus == "comment"
            && state.workspaceViewport == secondAnchor && state.selectedDraft === secondDraft,
                   "Forward restores the other destination's saved section and viewport")
        try expect(firstDraft.commentComposer == "Unposted fictional history reply"
            && secondDraft.commentComposer == "Second unposted fictional reply",
                   "Section deep links and history retain each capture's independent unfinished reply")
        let firstAfter = try captureData(first), secondAfter = try captureData(second)
        try expect(firstAfter == firstBefore && secondAfter == secondBefore && services.copies.isEmpty
            && services.openedFolders.isEmpty && services.notifications.requests == 0 && services.notifications.additions == 0,
                   "Explicit section history changes presentation only, with no committed metadata or external effects")
    }
    private static func boardBudgetAndValidation(output: URL) async throws {
        let services = try Services(); defer { services.close() }
        let capture = try services.image(task: true)
        capture.title = String(repeating: "Fictional capture with a long descriptive task title ", count: 5)
        capture.projectName = String(repeating: "Fictional Northstar Studio ", count: 5)
        services.state.openCapture(capture.id)
        let draft = services.state.selectedDraft!
        draft.planning.priority = .high
        let before = try captureData(capture)
        try await withFixture(services, capture: capture, size: CGSize(width: 380, height: 680), factor: 2, board: true,
                              entryFocus: "capture-preview") { host, window, draft in
            try expect(services.state.workspaceZoom.factor == 2, "Full BoardView fixture uses the real 200% workspace zoom")
            _ = try await find(host, id: "detail-pane-preview")
            _ = try await fixedControls(host, window: window, context: "full-board-380-zoom200-long-title")
            let viewport = window.convertToScreen(host.convert(host.bounds, to: nil))
            let pane = try await find(host, id: "detail-pane-preview")
            try contained(pane, in: viewport, context: "full-board-reading-budget")
            // At the capped 17-point reading size, 180 points permits roughly ten
            // lines of content after both the app chrome and capture controls.
            try expect(pane.frame.height >= 180,
                       "Global header, long capture title, project and priority leave a meaningful visible reading pane at 380×680 and 200%")
            let date = try await find(host, id: "detail-captured-at")
            try contained(date, in: viewport, context: "full-board-capture-metadata")
            try render(host, name: "full-board-380-zoom200-long-title", output: output)
            evidence.append(["context": "full-board-380-zoom200-long-title", "width": 380, "height": 680,
                "zoom": 2, "readingPaneHeight": pane.frame.height, "readingPaneFrame": NSStringFromRect(pane.frame)])

            draft.commentComposer = "Unposted reply survives a failed save"
            draft.title = ""
            let invalidTitle = DetailNavigationDraftSnapshot(draft)
            try await select("details", in: host)
            let saveTitle = try await find(host, id: "detail-save")
            try expect(saveTitle.press(), "Save from Details accepts a native activation")
            await settle(host)
            _ = try await find(host, id: "detail-pane-task")
            try expect(draft.hasError && draft.validationIssue == .title && DetailNavigationDraftSnapshot(draft) == invalidTitle,
                       "Invalid title saved from another pane reveals Task and preserves every unfinished field")

            draft.title = "Pending fictional task title"
            draft.planning.plannedDay = "invalid-local-date"
            let invalidPlanning = DetailNavigationDraftSnapshot(draft)
            try await select("comments", in: host)
            let savePlanning = try await find(host, id: "detail-save")
            try expect(savePlanning.press(), "Save invalid task planning from Comments accepts a native activation")
            await settle(host)
            _ = try await find(host, id: "detail-pane-task")
            try expect(draft.hasError && draft.validationIssue == .planning && DetailNavigationDraftSnapshot(draft) == invalidPlanning,
                       "Invalid planning saved from another pane reveals Task and retains the failed draft")

            draft.planning.plannedDay = nil
            draft.reminderEnabled = true; draft.reminderMode = .date
            draft.reminderDate = Date(timeIntervalSince1970: 1_000)
            let invalidReminder = DetailNavigationDraftSnapshot(draft)
            try await select("preview", in: host)
            let saveReminder = try await find(host, id: "detail-save")
            try expect(saveReminder.press(), "Save invalid reminder from Preview accepts a native activation")
            await settle(host)
            _ = try await find(host, id: "detail-pane-reminder")
            try expect(draft.hasError && draft.validationIssue == .reminder && DetailNavigationDraftSnapshot(draft) == invalidReminder,
                       "Invalid reminder saved from another pane reveals Reminder and retains the failed draft")
            _ = try await find(host, id: "detail-save-feedback")
            _ = try await fixedControls(host, window: window, context: "full-board-invalid-reminder-feedback")
        }
        let after = try captureData(capture)
        try expect(after == before && services.copies.isEmpty && services.openedFolders.isEmpty
            && services.notifications.requests == 0 && services.notifications.additions == 0,
                   "Global BoardView rendering and rejected saves preserve committed capture metadata and have no external effects")
    }
    private static func run() async throws {
        let repository = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).deletingLastPathComponent()
        let output = ProcessInfo.processInfo.environment["DABIN_CAPTURE_DETAIL_NAVIGATION_QA_OUTPUT"].map { URL(fileURLWithPath: $0) }
            ?? repository.appendingPathComponent("docs/qa/capture-detail-redesign-2026-10-04/navigation")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try await boardBudgetAndValidation(output: output)
        try await layoutMatrix(output: output)
        try await persistenceAndRoutes(output: output)
        try await actionsAndConditionalSections()
        try explicitSectionHistory()
        let report: [String: Any] = ["suite": "CaptureDetailNavigationTests", "checks": checks, "fixtures": evidence,
            "privacy": "Synthetic metadata, private preferences, own-process accessibility and native menu-item actions; no personal archive, general clipboard, Finder, external app or notification permission access."]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("native-navigation-report.json"))
        print("PASS: \(checks) capture-detail navigation, fixed-control, draft-resumption and action checks; renders: \(output.path)")
    }
}
