import AppKit
import ApplicationServices
import Foundation
import QuartzCore
import SwiftUI

@MainActor private final class TooltipReminderClient: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .undetermined }
    func requestAuthorization() async throws -> Bool { false }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}

@MainActor private struct TooltipAXNode {
    let object: NSObject

    private func value(_ name: String) -> Any? {
        let selector = NSSelectorFromString(name)
        return object.responds(to: selector) ? object.perform(selector)?.takeUnretainedValue() : nil
    }

    private func attribute(_ name: String) -> Any? {
        let selector = NSSelectorFromString("accessibilityAttributeValue:")
        guard object.responds(to: selector),
              (value("accessibilityAttributeNames") as? [String])?.contains(name) == true else { return nil }
        return object.perform(selector, with: name as NSString)?.takeUnretainedValue()
    }

    var identifier: String? { (value("accessibilityIdentifier") as? String) ?? (attribute("AXIdentifier") as? String) }
    var label: String {
        [value("accessibilityLabel"), attribute("AXTitle"), attribute("AXDescription")]
            .compactMap { $0 as? String }.first { !$0.isEmpty } ?? ""
    }
    var help: String {
        [value("accessibilityHelp"), value("accessibilityHint"), attribute("AXHelp")]
            .compactMap { $0 as? String }.first { !$0.isEmpty } ?? ""
    }
    var role: String { (value("accessibilityRole") as? String) ?? (attribute("AXRole") as? String) ?? "" }
    var actions: [String] { (value("accessibilityActionNames") as? [String]) ?? [] }
    var frame: NSRect {
        let selector = NSSelectorFromString("accessibilityFrame")
        guard object.responds(to: selector) else { return .zero }
        typealias Getter = @convention(c) (AnyObject, Selector) -> NSRect
        return unsafeBitCast(object.method(for: selector), to: Getter.self)(object, selector)
    }
    func press() -> Bool {
        let selector = NSSelectorFromString("accessibilityPerformPress")
        if object.responds(to: selector) {
            typealias Action = @convention(c) (AnyObject, Selector) -> Bool
            if unsafeBitCast(object.method(for: selector), to: Action.self)(object, selector) { return true }
        }
        let legacy = NSSelectorFromString("accessibilityPerformAction:")
        guard actions.contains("AXPress"), object.responds(to: legacy) else { return false }
        _ = object.perform(legacy, with: "AXPress" as NSString)
        return true
    }
    var children: [Any] {
        var children: [Any] = []
        for name in ["accessibilityChildren", "accessibilityChildrenInNavigationOrder", "accessibilityContents"] {
            if let values = value(name) as? [Any] { children += values }
        }
        if let values = attribute("AXChildren") as? [Any] { children += values }
        if let view = object as? NSView { children += view.subviews }
        return children
    }
}

@MainActor private final class TooltipFocusModel: ObservableObject {
    @Published var isFocused = false
    @Published var isEnabled = true
    @Published var controlEnabled = true
    var targetButton: NSButton?
    var targetPresses = 0
}

@MainActor private struct TooltipNativeButton: NSViewRepresentable {
    let title: String
    let action: () -> Void
    var onCreated: ((NSButton) -> Void)? = nil

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func press(_ sender: Any?) { action() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.press(_:)))
        button.bezelStyle = .rounded
        onCreated?(button)
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.isEnabled = context.environment.isEnabled
    }
}

@MainActor private struct TooltipFocusFixture: View {
    @ObservedObject var model: TooltipFocusModel
    @ObservedObject var controller: TimelineTooltipController

    var body: some View {
        ZStack(alignment: .topLeading) {
            TooltipNativeButton(title: "Help anchor", action: {})
                .frame(width: 100, height: 32)
                .buddyHelp("Focus tooltip", id: "fixture-focused-help", isFocused: model.isFocused)
                .disabled(!model.controlEnabled)
                .position(x: 160, y: 36)
            TooltipNativeButton(title: "Underlying action", action: { model.targetPresses += 1 },
                                onCreated: { model.targetButton = $0 })
                .frame(width: 120, height: 28).position(x: 160, y: 72)
        }
        .frame(width: 320, height: 180)
        .background(Palette.background)
        .environment(\.timelineTooltipController, controller)
        .environment(\.daBinTooltipsEnabled, model.isEnabled)
        .overlayPreferenceValue(HoverTooltipAnchorKey.self) { anchors in
            HoverTooltipOverlay(controller: controller, anchors: anchors, isEnabled: model.isEnabled)
        }
    }
}

/// Production views hosted inside synthetic nonactivating floating panels.
/// Only own-process AX methods and an own-window native control are exercised.
@main @MainActor private final class TooltipPresentationTests: NSObject, NSApplicationDelegate {
    private static var checks = 0
    private static var renderedFiles: [String] = []
    private static var evidence: [[String: Any]] = []
    private var result: Int32 = 0

    static func main() {
        let application = NSApplication.shared
        let delegate = TooltipPresentationTests()
        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
        exit(delegate.result)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do { try await Self.run() }
            catch { result = 1; fputs("FAIL: \(error)\n", stderr) }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }

    private static func failure(_ text: String) -> NSError {
        NSError(domain: "DaBinTooltipPresentationTests", code: 1,
                userInfo: [NSLocalizedDescriptionKey: text])
    }

    private static func expect(_ value: @autoclosure () -> Bool, _ text: String) throws {
        checks += 1
        guard value() else { throw failure(text) }
    }

    private static func settle(_ view: NSView) async {
        for _ in 0..<4 {
            view.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(40))
        }
    }

    private static func nodes(in view: NSView) -> [TooltipAXNode] {
        var result: [TooltipAXNode] = []
        var visited = Set<ObjectIdentifier>()
        func visit(_ value: Any, depth: Int) {
            guard depth < 50, let object = value as? NSObject,
                  visited.insert(ObjectIdentifier(object)).inserted else { return }
            let node = TooltipAXNode(object: object)
            result.append(node)
            node.children.forEach { visit($0, depth: depth + 1) }
        }
        visit(view, depth: 0)
        NSAccessibility.unignoredChildren(from: [view]).forEach { visit($0, depth: 0) }
        return result
    }

    private static func node(_ view: NSView, id: String) async throws -> TooltipAXNode {
        for _ in 0..<8 {
            if let found = nodes(in: view).first(where: { $0.identifier == id }) { return found }
            await settle(view)
        }
        throw failure("Missing own-window accessible control \(id)")
    }

    /// Reveal the exact identified switch before sending an own-window click.
    /// Direct AXPress on SwiftUI's clipped PlatformSwitch can advertise success
    /// without delivering its binding action in an offscreen test window.
    private static func clickSettingsSwitch(_ element: TooltipAXNode, hosting: NSView,
                                            window: NSWindow) async throws {
        var candidates: [TooltipAXNode] = []
        var visited = Set<ObjectIdentifier>()
        func visit(_ candidate: TooltipAXNode, depth: Int) {
            guard depth < 20, visited.insert(ObjectIdentifier(candidate.object)).inserted else { return }
            candidates.append(candidate)
            for child in candidate.children {
                if let object = child as? NSObject { visit(TooltipAXNode(object: object), depth: depth + 1) }
            }
        }
        visit(element, depth: 0)
        let diagnostics = candidates.map {
            "\(type(of: $0.object)) role=\($0.role) actions=\($0.actions) label=\($0.label)"
        }.joined(separator: "; ")
        print("Settings switch accessibility: \(diagnostics)")
        let switches = candidates.filter { $0.role == "AXSwitch" || $0.role == "AXCheckBox" || $0.object is NSSwitch }
        guard let control = switches.compactMap({ $0.object as? NSView }).first else {
            throw failure("The exact identified Settings switch must have a mounted native control: \(diagnostics)")
        }
        try expect(control.window === window && !control.isHiddenOrHasHiddenAncestor,
                   "The Settings switch is mounted in the retained own fixture window")
        if let scroll = control.enclosingScrollView, let document = scroll.documentView {
            let target = control.convert(control.bounds, to: document).insetBy(dx: -12, dy: -24)
            let visible = scroll.documentVisibleRect
            var origin = visible.origin
            if target.minY < visible.minY { origin.y = target.minY }
            if target.maxY > visible.maxY { origin.y = target.maxY - visible.height }
            origin.y = max(document.bounds.minY, min(origin.y, document.bounds.maxY - visible.height))
            scroll.contentView.scroll(to: origin)
            scroll.reflectScrolledClipView(scroll.contentView)
            await settle(hosting)
        }
        let target = control.convert(control.bounds, to: hosting)
        let center = CGPoint(x: target.midX, y: target.midY)
        try expect(!target.isEmpty && hosting.bounds.contains(center) && !control.visibleRect.isEmpty,
                   "The exact Show tooltips switch is scrolled into the visible board before clicking: \(target)")
        let hostPoint = hosting.superview.map { hosting.convert(center, to: $0) } ?? center
        let hit = hosting.hitTest(hostPoint)
        try expect(hit != nil, "The visible native Settings switch receives own-window hit routing")
        print("Settings switch native click: frame=\(target) hit=\(hit.map { String(describing: type(of: $0)) } ?? "nil")")
        try click(hosting.convert(center, to: nil), in: window)
        await settle(hosting)
        evidence.append(["fixture": "settings-switch", "nativeClass": String(describing: type(of: control)),
                         "visibleControlFrame": NSStringFromRect(target),
                         "hitClass": hit.map { String(describing: type(of: $0)) } ?? "nil"])
    }

    private static func activateOwnAccessibility() async throws {
        let error = await Task.detached {
            let app = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            AXUIElementSetMessagingTimeout(app, 3)
            var windows: CFTypeRef?
            return AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows)
        }.value
        try expect(error == .success, "Own-process accessibility initializes without accessing another application")
    }

    private static func panel(_ view: NSView) -> DaBinPanel {
        let window = DaBinPanel(contentRect: CGRect(x: -10000, y: -10000,
            width: view.frame.width, height: view.frame.height),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.level = .floating
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = false
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.sharingType = .none
        window.contentView = view
        window.orderFront(nil)
        return window
    }

    private static func render(_ view: NSView) throws -> NSBitmapImageRep {
        view.layoutSubtreeIfNeeded()
        CATransaction.flush()
        view.displayIfNeeded()
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(view.bounds.width * 2), pixelsHigh: Int(view.bounds.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let bytes = bitmap.bitmapData else { throw failure("Could not allocate the native tooltip bitmap") }
        bitmap.size = view.bounds.size
        bytes.initialize(repeating: 0, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap
    }

    private static func bytes(_ bitmap: NSBitmapImageRep) -> Data {
        Data(bytes: bitmap.bitmapData!, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    }

    private static func changedRegion(_ first: NSBitmapImageRep, _ second: NSBitmapImageRep) -> (Int, CGRect) {
        guard first.pixelsWide == second.pixelsWide, first.pixelsHigh == second.pixelsHigh,
              let lhs = first.bitmapData, let rhs = second.bitmapData else { return (0, .null) }
        var count = 0
        var box = CGRect.null
        for y in 0..<first.pixelsHigh {
            for x in 0..<first.pixelsWide {
                let a = y * first.bytesPerRow + x * 4
                let b = y * second.bytesPerRow + x * 4
                if (0..<4).contains(where: { lhs[a + $0] != rhs[b + $0] }) {
                    count += 1
                    box = box.union(CGRect(x: CGFloat(x) / 2, y: CGFloat(y) / 2, width: 0.5, height: 0.5))
                }
            }
        }
        return (count, box)
    }

    private static func save(_ bitmap: NSBitmapImageRep, name: String, output: URL) throws {
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw failure("Could not encode tooltip evidence") }
        let filename = "\(name)@2x.png"
        try data.write(to: output.appendingPathComponent(filename), options: .atomic)
        renderedFiles.append(filename)
    }

    private static func swiftUIBounds(_ screen: CGRect, hosting: NSView, window: NSWindow) -> CGRect {
        let rect = hosting.convert(window.convertFromScreen(screen), from: nil)
        return hosting.isFlipped ? rect : CGRect(x: rect.minX, y: hosting.bounds.height - rect.maxY,
                                               width: rect.width, height: rect.height)
    }

    /// Dispatches only to this process's retained, offscreen fixture window.
    /// NSButton can consume its matching mouse-up in its own tracking loop.
    private static func click(_ point: CGPoint, in window: NSWindow) throws {
        let timestamp = ProcessInfo.processInfo.systemUptime
        guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
            timestamp: timestamp, windowNumber: window.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1),
              let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [],
            timestamp: timestamp + 0.02, windowNumber: window.windowNumber, context: nil,
            eventNumber: 2, clickCount: 1, pressure: 0) else { throw failure("Could not form an own-window mouse click") }
        NSApp.postEvent(up, atStart: true)
        window.sendEvent(down)
        if let remaining = NSApp.nextEvent(matching: .leftMouseUp, until: Date(), inMode: .default, dequeue: true) {
            try expect(remaining.windowNumber == window.windowNumber, "Synthetic clicks remain confined to the own fixture window")
            window.sendEvent(remaining)
        }
    }

    private static func boardChecks(size: CGSize, dark: Bool, output: URL) async throws {
        let name = "\(Int(size.width))-\(dark ? "dark" : "light")"
        let fixtureRoot = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinTooltip-\(UUID().uuidString)", isDirectory: true)
        let suite = "DaBinTooltip.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = try CaptureStore(root: fixtureRoot)
        _ = try store.capture(text: "Fictional tooltip review capture")
        let previews = PreviewService(store: store, defaults: defaults)
        let captureSettings = AutoCaptureSettings(defaults: defaults)
        let autoCapture = AutoCaptureService(settings: captureSettings, input: InputService(store: store),
            pasteboardProvider: { fatalError("Tooltip QA must not read the clipboard") },
            sourceApplicationProvider: { nil })
        let state = AppState(store: store, previews: previews,
            reminders: ReminderService(store: store, client: TooltipReminderClient()), autoCapture: autoCapture)
        let theme = ThemeSettings(defaults: defaults, systemDarkMode: dark)
        theme.setDarkMode(dark)
        let controller = TimelineTooltipController(delay: 0.035)
        state.openDaily()
        state.isBoardVisible = true
        var expansions = 0
        state.onToggleExpandedWindow = { expansions += 1 }
        let hosting = NSHostingView(rootView: BoardView(state: state, theme: theme, tooltipController: controller)
            .environment(\.displayScale, 2).frame(width: size.width, height: size.height))
        let frame = RobotAppFrameView(contentView: hosting)
        frame.frame = CGRect(origin: .zero, size: RobotAppFrameView.outerSize(forContentSize: size))
        let window = panel(frame)
        CornerController.applyBoardAppearance(darkMode: dark, to: window, frame: frame, hosting: hosting)
        frame.setVisible(true)
        defer {
            controller.dismiss(); frame.setVisible(false)
            window.orderOut(nil); window.contentView = nil; window.close()
            autoCapture.shutdown(); previews.cancelNetwork()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: fixtureRoot)
        }
        await settle(frame)
        try await activateOwnAccessibility()
        try expect(window.styleMask.contains(.nonactivatingPanel) && window.level == .floating && !window.isKeyWindow,
                   "Tooltip fixtures retain the production nonactivating floating-panel behavior")
        try expect(hosting.frame.size == size, "The tooltip overlay does not change the production board's size")
        let appearance: NSAppearance.Name = dark ? .darkAqua : .aqua
        try expect(hosting.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == appearance,
                   "Actual nested production content uses the intended appearance")
        let baseline = try render(hosting)
        try save(baseline, name: "board-\(name)-baseline", output: output)
        let initialSettings = try await node(hosting, id: "board-settings")
        let settingsHelp = initialSettings.help
        try expect(!settingsHelp.isEmpty, "The actual Settings icon exposes useful accessibility help independently of the bubble")
        let cases = [("board-settings", "board-settings-tooltip", "Settings"),
                     ("board-search", "board-search-tooltip", "Search all captures"),
                     ("window-expand", "window-expand-tooltip", "Expand or restore window"),
                     ("capture-filter-tasks", "filter-tooltip-tasks", "Tasks")]
        for (controlID, tooltipID, text) in cases {
            let control = try await node(hosting, id: controlID)
            try expect(!control.label.isEmpty && control.frame.width > 0 && control.frame.height > 0,
                       "\(controlID) keeps its accessible name and usable target")
            let anchor = swiftUIBounds(control.frame, hosting: hosting, window: window)
            guard let layout = HoverTooltipLayout.make(text: text, anchor: anchor, containerSize: size) else {
                throw failure("Actual \(controlID) geometry must resolve a tooltip layout")
            }
            controller.presentImmediately(TimelineTooltipDescriptor(id: tooltipID, text: text, index: 0, itemCount: 1))
            await settle(hosting)
            let shown = try render(hosting)
            let changed = changedRegion(baseline, shown)
            try expect(changed.0 > 80, "\(tooltipID) produces actual visible tooltip pixels, not just controller metadata")
            try expect(layout.frame.insetBy(dx: -9, dy: -9).contains(changed.1),
                       "\(tooltipID) renders beside its real control rather than an obsolete header position (\(changed.1), expected \(layout.frame))")
            try save(shown, name: "board-\(name)-\(tooltipID)", output: output)
            evidence.append(["fixture": name, "controlID": controlID, "tooltipID": tooltipID,
                "actualAnchor": NSStringFromRect(anchor), "expectedTooltip": NSStringFromRect(layout.frame),
                "changedPixels": changed.0, "changedRegion": NSStringFromRect(changed.1)])
            controller.dismiss()
            await settle(hosting)
        }

        let longText = "Tooltip-only sentinel: " + Array(repeating: "A longer explanation of this icon and its behavior", count: 8).joined(separator: " ")
        controller.presentImmediately(TimelineTooltipDescriptor(id: "board-settings-tooltip", text: longText, index: 0, itemCount: 1))
        await settle(hosting)
        let longSnapshot = try render(hosting)
        let longChange = changedRegion(baseline, longSnapshot)
        try expect(longChange.0 > 200 && CGRect(origin: .zero, size: size).contains(longChange.1),
                   "Long tooltip text wraps and remains inside the board")
        try expect(!nodes(in: hosting).contains { $0.label.contains("Tooltip-only sentinel") },
                   "Visual help stays hidden from the accessibility tree while real controls remain available")
        try save(longSnapshot, name: "board-\(name)-long-help", output: output)
        theme.setShowTooltips(false)
        await settle(hosting)
        try expect(!controller.isEnabled && controller.visible == nil,
                   "The Settings preference immediately disables and dismisses shown help")
        let disabled = try render(hosting)
        try expect(bytes(disabled) == bytes(baseline), "Disabling tooltips renders the actual no-tooltip baseline")
        let disabledSettings = try await node(hosting, id: "board-settings")
        try expect(disabledSettings.label == initialSettings.label && disabledSettings.help == settingsHelp,
                   "Disabling visual help preserves the real header control's accessible name and help")
        try save(disabled, name: "board-\(name)-disabled", output: output)
        controller.begin(TimelineTooltipDescriptor(id: "board-settings-tooltip", text: "Settings", index: 0, itemCount: 1))
        await settle(hosting)
        try expect(controller.visible == nil, "Disabled production help cannot reappear after dwell")
        theme.setShowTooltips(true)
        await settle(hosting)
        controller.begin(TimelineTooltipDescriptor(id: "board-settings-tooltip", text: "Settings", index: 0, itemCount: 1))
        theme.setShowTooltips(false)
        await settle(hosting)
        try expect(controller.visible == nil, "Disabling the board's preference cancels a pending tooltip too")
        theme.setShowTooltips(true)
        await settle(hosting)
        controller.presentImmediately(TimelineTooltipDescriptor(id: "window-expand-tooltip", text: "Expand or restore window", index: 0, itemCount: 1))
        await settle(hosting)
        let expand = try await node(hosting, id: "window-expand")
        try expect(expand.press(), "An actual header action remains accessible while a tooltip is present")
        await settle(hosting)
        try expect(expansions == 1, "The real header callback fires exactly once with help visible")
        try expect(controller.visible == nil, "Keyboard or accessibility activation dismisses its primary-icon tooltip")
        controller.presentImmediately(TimelineTooltipDescriptor(id: "board-settings-tooltip", text: "Settings", index: 0, itemCount: 1))
        state.showSettings()
        await settle(hosting)
        try expect(controller.visible == nil, "Changing the production route dismisses a shown tooltip")
        if size.width == 380 && !dark {
            let toggle = try await node(hosting, id: "settings-show-tooltips")
            try await clickSettingsSwitch(toggle, hosting: hosting, window: window)
            try expect(!theme.showTooltips && !controller.isEnabled
                && defaults.object(forKey: ThemeSettings.showTooltipsKey) as? Bool == false,
                       "Clicking the real Settings switch disables live help and persists its value (theme=\(theme.showTooltips), controller=\(controller.isEnabled), persisted=\(String(describing: defaults.object(forKey: ThemeSettings.showTooltipsKey))))")
            try save(render(hosting), name: "board-\(name)-settings-tooltips-disabled", output: output)
            let restore = try await node(hosting, id: "settings-show-tooltips")
            try await clickSettingsSwitch(restore, hosting: hosting, window: window)
            try expect(theme.showTooltips && controller.isEnabled
                && defaults.object(forKey: ThemeSettings.showTooltipsKey) as? Bool == true,
                       "The actual Settings switch restores and persists enabled help")
            try save(render(hosting), name: "board-\(name)-settings-tooltips-enabled", output: output)
        }
        state.openDaily()
        await settle(hosting)
        controller.presentImmediately(TimelineTooltipDescriptor(id: "board-settings-tooltip", text: "Settings", index: 0, itemCount: 1))
        state.isBoardVisible = false
        await settle(hosting)
        try expect(controller.visible == nil, "Hiding a still-mounted board dismisses its tooltip")
    }

    private static func focusedNativeChecks(output: URL) async throws {
        let model = TooltipFocusModel()
        let controller = TimelineTooltipController(delay: 0.5)
        let hosting = NSHostingView(rootView: TooltipFocusFixture(model: model, controller: controller)
            .environment(\.displayScale, 2).preferredColorScheme(.light))
        hosting.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
        let window = panel(hosting)
        defer { controller.dismiss(); window.orderOut(nil); window.contentView = nil; window.close() }
        await settle(hosting)
        guard let target = model.targetButton else { throw failure("The underlying native button must remain mounted") }
        let center = target.convert(CGPoint(x: target.bounds.midX, y: target.bounds.midY), to: hosting)
        let hostPoint = hosting.superview.map { hosting.convert(center, to: $0) } ?? center
        let windowPoint = hosting.convert(center, to: nil)
        let initialHit = hosting.hitTest(hostPoint)
        try expect(initialHit != nil, "The no-tooltip fixture already routes native hits at the target button")
        try click(windowPoint, in: window)
        await settle(hosting)
        try expect(model.targetPresses == 1, "The no-tooltip fixture delivers a real own-window click to its underlying native button")
        let baselineHit = hosting.hitTest(hostPoint)
        let baseline = try render(hosting)
        model.isFocused = true
        await settle(hosting)
        try expect(controller.visible?.id == "fixture-focused-help",
                   "The reusable modifier shows keyboard-focus help immediately without waiting for its half-second hover delay")
        let shown = try render(hosting)
        let changed = changedRegion(baseline, shown)
        try expect(changed.0 > 80, "Focused reusable help produces visible pixels")
        try save(shown, name: "native-focused-hit-through", output: output)
        let swiftUIPoint = CGPoint(x: center.x, y: hosting.isFlipped ? center.y : hosting.bounds.height - center.y)
        try expect(changed.1.contains(swiftUIPoint), "The visible bubble actually covers the clicked native button's center")
        let shownHit = hosting.hitTest(hostPoint)
        let hitClass = shownHit.map { String(describing: type(of: $0)) } ?? "nil"
        try expect(baselineHit != nil && shownHit === baselineHit,
                   "The bubble preserves the exact baseline native hit route (\(hitClass)), including any SwiftUI representable wrapper")
        try click(windowPoint, in: window)
        await settle(hosting)
        try expect(model.targetPresses == 2, "A real own-window click through the visible bubble invokes the underlying button exactly once")
        evidence.append(["fixture": "focused-native", "baselineHitClass": baselineHit.map { String(describing: type(of: $0)) } ?? "nil",
                         "shownHitClass": hitClass, "targetFrame": NSStringFromRect(target.frame),
                         "changedRegion": NSStringFromRect(changed.1), "clickedCenter": NSStringFromPoint(swiftUIPoint),
                         "deliveredNativeCallbacks": model.targetPresses])
        model.isEnabled = false
        await settle(hosting)
        try expect(controller.visible == nil && !controller.isEnabled, "The reusable modifier removes focused help when disabled")
        model.isEnabled = true
        await settle(hosting)
        try expect(controller.visible?.id == "fixture-focused-help",
                   "Re-enabling help while focus stays stationary restores the same control's tooltip")
        model.controlEnabled = false
        await settle(hosting)
        try expect(controller.visible == nil, "A disabled control cannot retain a focused tooltip")
        model.controlEnabled = true
        await settle(hosting)
        try expect(controller.visible?.id == "fixture-focused-help", "A re-enabled focused control can show help again")
        model.isFocused = false
        await settle(hosting)
        try expect(controller.visible == nil, "Leaving the reusable control's focus removes its tooltip")
    }

    private static func run() async throws {
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("build/qa/tooltips", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for size in [CGSize(width: 380, height: 560), CGSize(width: 760, height: 680)] {
            for dark in [false, true] { try await boardChecks(size: size, dark: dark, output: output) }
        }
        try await focusedNativeChecks(output: output)
        let report: [String: Any] = ["schemaVersion": 1, "checksPassed": checks,
            "renderedFiles": renderedFiles, "actualAnchorEvidence": evidence,
            "renderMethod": "Production BoardView in offscreen nonactivating floating panels and canonical RobotAppFrameView at native 2x",
            "privacy": "Fictional text-only captures, isolated preferences; no personal archive, clipboard, network, global input, system preferences or installed app accessed",
            "limitations": "Presentation, focus-state inputs, native hit testing, own-window synthetic clicks and own-process accessibility actions; actual desktop pointer dwell is separate"]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("tooltip-presentation-report.json"), options: .atomic)
        print("PASS: \(checks) native tooltip visibility, actual anchors, preference, focus and click-through checks. \(output.path)")
    }
}
