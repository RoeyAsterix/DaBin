import AppKit
import ApplicationServices
import Foundation
import QuartzCore
import SwiftUI
import Darwin

@MainActor private final class VisualStressReminders: ReminderNotificationClient {
    private(set) var writes = 0
    func authorization() async -> ReminderAuthorization { .denied }
    func requestAuthorization() async throws -> Bool { writes += 1; return false }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { writes += 1 }
    func removePending(_ identifiers: [String]) { writes += identifiers.count }
    func removeDelivered(_ identifiers: [String]) { writes += identifiers.count }
}

@MainActor private final class VisualStressWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor private final class VisualStressWeakController {
    weak var value: CornerController?
    init(_ value: CornerController) { self.value = value }
}

/// Seeded interruptions of actual production views in own-process offscreen
/// windows. This checks bounded geometry, renderability, stale completions and
/// controller disposal; it does not claim a GPU frame-rate or general leak audit.
@main @MainActor private final class VisualAnimationStressTests: NSObject, NSApplicationDelegate {
    private struct Generator {
        var value: UInt64 = 0xDA_B1_2026_1005
        mutating func next(_ count: Int) -> Int {
            value = value &* 6_364_136_223_846_793_005 &+ 1
            return Int((value >> 32) % UInt64(count))
        }
    }
    private struct Profile {
        let name: String
        let dark: Bool
        let contrast: Bool
        let reduced: Bool
    }
    @MainActor private final class Fixture {
        let suite = "DaBinVisualStress.\(UUID().uuidString)"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinVisualStress-\(UUID())")
        let defaults: UserDefaults
        let store: CaptureStore
        let previews: PreviewService
        let auto: AutoCaptureService
        let reminders = VisualStressReminders()
        let state: AppState
        let theme: ThemeSettings
        let task: Capture
        init() throws {
            defaults = UserDefaults(suiteName: suite)!
            defaults.set(false, forKey: PreviewService.linkPreviewPreference)
            store = try CaptureStore(root: root, repairArchiveOnOpen: false)
            task = try store.createTask(text: "Fictional native animation stress task", planning: TaskPlanning(priority: .high,
                checklist: [TaskChecklistItem(text: "Fictional first step"), TaskChecklistItem(text: "Fictional second step")]))
            _ = try store.createNote(text: "Fictional isolated graphics fixture", projectName: nil)
            previews = PreviewService(store: store, defaults: defaults)
            auto = AutoCaptureService(settings: AutoCaptureSettings(defaults: defaults), input: InputService(store: store),
                pasteboardProvider: { fatalError("Visual stress must not read a clipboard") }, sourceApplicationProvider: { nil })
            state = AppState(store: store, previews: previews, reminders: ReminderService(store: store, client: reminders),
                autoCapture: auto, captureClipboard: CaptureClipboardService(writer: { _ in fatalError("Visual stress must not write a clipboard") }),
                quickAccessSettings: QuickAccessSettings(defaults: defaults), workspaceZoom: WorkspaceZoomSettings(defaults: defaults),
                folderOpener: { _ in fatalError("Visual stress must not open an external application") })
            theme = ThemeSettings(defaults: defaults, systemDarkMode: false)
            theme.setShowTooltips(false)
        }
        func close() {
            previews.shutdown(); auto.shutdown(); state.focusSessions.shutdown()
            state.shutdownNotificationPresentation(); store.cancelArchiveRepair()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
    }
    @MainActor private struct Node {
        let object: NSObject
        func value(_ name: String) -> Any? {
            let selector = NSSelectorFromString(name)
            guard object.responds(to: selector) else { return nil }
            return object.perform(selector)?.takeUnretainedValue()
        }
        func attribute(_ name: String) -> Any? {
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
        var frame: CGRect {
            let selector = NSSelectorFromString("accessibilityFrame")
            guard object.responds(to: selector) else { return .zero }
            typealias Getter = @convention(c) (AnyObject, Selector) -> CGRect
            return unsafeBitCast(object.method(for: selector), to: Getter.self)(object, selector)
        }
        var children: [Any] {
            var result = ["accessibilityChildren", "accessibilityChildrenInNavigationOrder", "accessibilityContents"]
                .flatMap { value($0) as? [Any] ?? [] }
            result += attribute("AXChildren") as? [Any] ?? []
            return result
        }
    }
    private static var checks = 0
    private static var evidence: [[String: Any]] = []
    private var result: Int32 = 0
    static func main() {
        let watchdog = DispatchSource.makeTimerSource(queue: .global())
        watchdog.schedule(deadline: .now() + 60)
        watchdog.setEventHandler { fputs("Visual animation stress exceeded 60 seconds\n", stderr); Darwin._exit(2) }
        watchdog.resume()
        let app = NSApplication.shared, delegate = VisualAnimationStressTests()
        app.setActivationPolicy(.accessory); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        watchdog.cancel(); exit(delegate.result)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await Self.run() }
            catch { result = 1; fputs("Visual animation stress failed: \(error)\n", stderr) }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }
    private static func expect(_ condition: @autoclosure () -> Bool, _ text: String) throws {
        checks += 1
        guard condition() else { throw NSError(domain: "VisualAnimationStressTests", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
    }
    private static func finite(_ rect: CGRect) -> Bool {
        [rect.origin.x, rect.origin.y, rect.width, rect.height].allSatisfy(\.isFinite) && rect.width >= 0 && rect.height >= 0
    }
    private static func validateGeometry(_ root: NSView) throws {
        var views = [root]
        while let view = views.popLast() {
            try expect(finite(view.frame) && finite(view.bounds), "Native view geometry remains finite during repeated interruption")
            views += view.subviews
        }
        var layers = [CALayer]()
        if let layer = root.layer { layers.append(layer) }
        while let model = layers.popLast() {
            for layer in [model, model.presentation()].compactMap({ $0 }) {
                let t = layer.transform
                try expect(finite(layer.bounds) && layer.position.x.isFinite && layer.position.y.isFinite
                    && layer.opacity.isFinite && layer.opacity >= 0 && layer.opacity <= 1
                    && [t.m11, t.m12, t.m13, t.m14, t.m21, t.m22, t.m23, t.m24, t.m31, t.m32, t.m33, t.m34,
                        t.m41, t.m42, t.m43, t.m44].allSatisfy(\.isFinite),
                    "Model and available presentation-layer transforms remain finite")
            }
            layers += model.sublayers ?? []
        }
    }
    private static func nodes(_ view: NSView) -> [Node] {
        var seen = Set<ObjectIdentifier>(), result: [Node] = []
        func visit(_ value: Any, _ depth: Int) {
            guard depth < 60, let object = value as? NSObject, seen.insert(ObjectIdentifier(object)).inserted else { return }
            let node = Node(object: object); result.append(node)
            node.children.forEach { visit($0, depth + 1) }
            if let native = object as? NSView { native.subviews.forEach { visit($0, depth + 1) } }
        }
        visit(view, 0); NSAccessibility.unignoredChildren(from: [view]).forEach { visit($0, 0) }
        if let wrapper = view.window?.contentView, wrapper !== view {
            visit(wrapper, 0); NSAccessibility.unignoredChildren(from: [wrapper]).forEach { visit($0, 0) }
        }
        return result
    }
    private static func settle(_ view: NSView, milliseconds: Int = 40) async {
        view.layoutSubtreeIfNeeded(); try? await Task.sleep(for: .milliseconds(milliseconds))
        view.layoutSubtreeIfNeeded(); CATransaction.flush(); view.displayIfNeeded()
    }
    private static func render(_ view: NSView, name: String, output: URL) throws {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * 2),
            pixelsHigh: Int(view.bounds.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw NSError(domain: "VisualAnimationStressTests", code: 2)
        }
        bitmap.size = view.bounds.size; view.cacheDisplay(in: view.bounds, to: bitmap)
        var painted = 0
        for row in 1...7 { for column in 1...7 {
            if (bitmap.colorAt(x: bitmap.pixelsWide * column / 8, y: bitmap.pixelsHigh * row / 8)?.alphaComponent ?? 0) > 0.1 { painted += 1 }
        } }
        try expect(painted > 24, "Settled production board paints a nonempty native render after its transition burst")
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain: "VisualAnimationStressTests", code: 3) }
        try png.write(to: output.appendingPathComponent(name + "@2x.png"), options: .atomic)
    }
    private static func applyAppearance(_ profile: Profile, dark: Bool, window: NSWindow, frame: RobotAppFrameView, host: NSView) {
        CornerController.applyBoardAppearance(darkMode: dark, to: window, frame: frame, hosting: host)
        if profile.contrast {
            let appearance = NSAppearance(named: dark ? .accessibilityHighContrastDarkAqua : .accessibilityHighContrastAqua)
            window.appearance = appearance; frame.appearance = appearance; host.appearance = appearance
        }
    }
    private static func burst(profile: Profile, width: CGFloat, output: URL, random: inout Generator) async throws {
        let fixture = try Fixture(); defer { fixture.close() }
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let originalTask = try encoder.encode(CaptureSnapshot(fixture.task))
        fixture.theme.setDarkMode(profile.dark); fixture.theme.setBoardOpacity(0.65)
        fixture.state.workspaceZoom.setFactor(width == 380 ? 2 : 0.75)
        fixture.state.openCapture(fixture.task.id, focus: "task")
        let host = NSHostingView(rootView: BoardView(state: fixture.state, theme: fixture.theme)
            .environment(\.displayScale, 2))
        host.sizingOptions = []
        let frame = RobotAppFrameView(contentView: host)
        let size = RobotAppFrameView.outerSize(forContentSize: CGSize(width: width, height: 680))
        frame.frame = CGRect(origin: .zero, size: size)
        let window = VisualStressWindow(contentRect: CGRect(origin: CGPoint(x: -10000, y: -10000), size: size),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.sharingType = .none; window.backgroundColor = .clear; window.isOpaque = false
        window.contentView = frame; window.orderFront(nil)
        defer { frame.cancelTransition(open: false); window.orderOut(nil); window.contentView = nil; window.close() }
        applyAppearance(profile, dark: profile.dark, window: window, frame: frame, host: host)
        frame.setVisible(true); await settle(frame, milliseconds: 100)
        let source = window.convertToScreen(CGRect(x: 10, y: size.height - 90, width: 64, height: 78))
        var completed: [Int] = [], cancelled = Set<Int>(), previous: Int?
        for step in 0..<12 {
            if let previous, frame.isTransitioning { cancelled.insert(previous) }
            fixture.theme.setDarkMode(random.next(2) == 0)
            applyAppearance(profile, dark: fixture.theme.darkModeEnabled, window: window, frame: frame, host: host)
            switch random.next(4) {
            case 0: fixture.state.openInbox()
            case 1: fixture.state.openLibrary()
            case 2: fixture.state.showSettings()
            default: fixture.state.openCapture(fixture.task.id, focus: "task")
            }
            let adjusted = RobotAppFrameView.outerSize(forContentSize: CGSize(width: width + CGFloat(random.next(3) * 20), height: 680))
            window.setContentSize(adjusted); frame.frame = CGRect(origin: .zero, size: adjusted)
            if step.isMultiple(of: 2) {
                frame.animateClose(to: source, island: true, reduceMotion: profile.reduced) { completed.append(step) }
            } else {
                frame.animateOpen(from: source, island: true, reduceMotion: profile.reduced) { completed.append(step) }
            }
            previous = step; frame.layoutSubtreeIfNeeded(); CATransaction.flush()
            try validateGeometry(frame)
            try expect(frame.contentView === host, "Every interruption retains the same production hosting view")
            await settle(frame, milliseconds: 16)
        }
        if let previous, frame.isTransitioning { cancelled.insert(previous) }
        fixture.theme.setDarkMode(profile.dark)
        applyAppearance(profile, dark: profile.dark, window: window, frame: frame, host: host)
        fixture.state.openCapture(fixture.task.id, focus: "task")
        window.setContentSize(size); frame.frame = CGRect(origin: .zero, size: size)
        var finalCompletions = 0
        frame.animateOpen(from: source, island: true, reduceMotion: profile.reduced) { finalCompletions += 1 }
        await settle(frame, milliseconds: Int((RobotAppFrameView.openDuration + 0.2) * 1000))
        try expect(finalCompletions == 1 && frame.isFrameVisible && !frame.isTransitioning,
            "The newest opening completes once at a visible, stable endpoint")
        try expect(cancelled.isDisjoint(with: completed), "An interrupted generation never later executes its stale completion")
        try expect(host.superview != nil && abs(host.frame.width - width) < 1 && abs(host.frame.height - 680) < 1,
            "The mounted board restores exact final content dimensions after repeated resize and reversal")
        if profile.reduced { try expect(!frame.hasActiveEyeMotion, "Reduced-motion settled frame has no gaze or blink animation") }
        try render(frame, name: "burst-\(profile.name)-\(Int(width))", output: output)
        let axStatus = await Task.detached {
            let process = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            AXUIElementSetMessagingTimeout(process, 3)
            var ownedWindows: CFTypeRef?
            return AXUIElementCopyAttributeValue(process, kAXWindowsAttribute as CFString, &ownedWindows)
        }.value
        try expect(axStatus == .success, "Only this fixture process exposes its native accessibility hierarchy")
        await settle(frame, milliseconds: 60)
        try expect(window.frame.maxX < 0 && !window.isKeyWindow && !NSApp.isActive,
            "Accessibility setup retains offscreen, non-key and inactive own-window scope")
        let visible = window.convertToScreen(window.contentView!.bounds)
        for id in ["board-settings", "window-expand", "window-close", "detail-section-navigation", "detail-save"] {
            guard let control = nodes(host).first(where: { $0.identifier == id }) else {
                throw NSError(domain: "VisualAnimationStressTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Missing settled control \(id); exposed nodes: \(nodes(host).map { ($0.identifier ?? $0.label) + ":" + NSStringFromRect($0.frame) }.filter { !$0.hasPrefix(":") }.joined(separator: "; "))"])
            }
            try expect(finite(control.frame) && !control.frame.isEmpty && visible.insetBy(dx: -1, dy: -1).contains(control.frame),
                "Settled \(id) remains visible inside the real native window")
        }
        try validateGeometry(frame)
        let finalTask = try encoder.encode(CaptureSnapshot(fixture.task))
        try expect(finalTask == originalTask, "Graphics interruptions do not change the saved task")
        try expect(fixture.reminders.writes == 0, "Graphics interruptions do not request or schedule system notifications")
        evidence.append(["profile": profile.name, "contentWidth": width, "contentHeight": 680,
            "zoom": fixture.state.workspaceZoom.factor, "interruptions": 12,
            "nativeAppearance": window.effectiveAppearance.name.rawValue, "nativeAnimationReduceMotion": profile.reduced, "cancelledGenerations": cancelled.count,
            "finalCompletions": finalCompletions, "render": "burst-\(profile.name)-\(Int(width))@2x.png"])
    }
    private static func disposal() async throws {
        let fixture = try Fixture(); defer { fixture.close() }
        var owners: [VisualStressWeakController] = [], frames: [RobotAppFrameView] = [], windows: [NSWindow] = []
        var staleCompletions = 0
        for index in 0..<4 {
            var controller: CornerController? = CornerController(state: fixture.state, input: InputService(store: fixture.store),
                placementDefaults: fixture.defaults, theme: fixture.theme, robotReduceMotion: { index.isMultiple(of: 2) })
            let value = controller!
            owners.append(VisualStressWeakController(value)); frames.append(value.appFrame); windows += [value.board, value.bin]
            value.start(pointerPosition: { CGPoint(x: -100000, y: -100000) })
            value.appFrame.animateOpen(from: CGRect(x: 0, y: 0, width: 64, height: 78), island: true,
                reduceMotion: index.isMultiple(of: 2)) { staleCompletions += 1 }
            value.shutdown(); value.shutdown()
            try expect(value.isShutDown && !value.board.isVisible && !value.bin.isVisible && !value.appFrame.isTransitioning,
                "Repeated disposal cancels timers, native surfaces and active transitions immediately")
            controller = nil
        }
        // Retain native surfaces deliberately to detect resurrection even after
        // their owning controller has been released. No system preference changes.
        fixture.theme.setDarkMode(true); fixture.state.showSettings()
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        try? await Task.sleep(for: .seconds(RobotAppFrameView.openDuration + 0.2))
        try expect(owners.allSatisfy { $0.value == nil }, "Disposed controllers are released despite their former timers, observers and subscriptions")
        try expect(staleCompletions == 0 && windows.allSatisfy { !$0.isVisible }
            && frames.allSatisfy { !$0.isTransitioning && !$0.isFrameVisible },
            "Late notifications and animation deadlines cannot revive disposed windows or callbacks")
        try expect(fixture.reminders.writes == 0, "Disposal stress has no notification side effects")
        evidence.append(["context": "controller-disposal", "controllers": owners.count, "retainedNativeWindows": windows.count,
            "releasedControllers": owners.filter { $0.value == nil }.count, "staleCompletions": staleCompletions])
    }
    private static func run() async throws {
        let repository = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).deletingLastPathComponent()
        let output = ProcessInfo.processInfo.environment["DABIN_VISUAL_ANIMATION_STRESS_OUTPUT"].map { URL(fileURLWithPath: $0) }
            ?? repository.appendingPathComponent("docs/qa/stability-stress-2026-10-05/graphics")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let profiles = [Profile(name: "light", dark: false, contrast: false, reduced: false),
            Profile(name: "dark", dark: true, contrast: false, reduced: false),
            Profile(name: "appkit-contrast-light-reduced", dark: false, contrast: true, reduced: true),
            Profile(name: "appkit-contrast-dark-reduced", dark: true, contrast: true, reduced: true)]
        var random = Generator()
        for profile in profiles { for width in [CGFloat(380), 760] {
            try await burst(profile: profile, width: width, output: output, random: &random)
        } }
        try await disposal()
        let report: [String: Any] = ["schemaVersion": 1, "seed": "0xDAB120261005", "checks": checks, "fixtures": evidence,
            "systemAccessibility": ["reduceMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                "reduceTransparency": NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
                "increaseContrast": NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast],
            "scope": "Own-process offscreen production BoardView/RobotAppFrameView, isolated archives/preferences and CornerController disposal; no global input, clipboard, external apps or system preference changes",
            "limits": "Read-only SwiftUI accessibility environment follows actual OS settings; high-contrast profiles exercise AppKit NSAppearance and native reduced motion is passed explicitly. Renderability and finite geometry are not physical refresh-rate, GPU scheduling, subjective smoothness or exhaustive heap leak measurements"]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("visual-animation-stress-report.json"), options: .atomic)
        print("PASS: \(checks) seeded native graphics, animation interruption, visible-control and disposal checks; \(output.path)")
    }
}
