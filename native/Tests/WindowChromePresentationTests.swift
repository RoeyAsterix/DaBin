import AppKit
import Foundation
import QuartzCore
import SwiftUI

@MainActor private final class ChromeFixtureWindow: NSWindow {
    var fixtureScale: CGFloat = 2
    override var backingScaleFactor: CGFloat { fixtureScale }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
@MainActor private final class ChromeFixtureReminders: ReminderNotificationClient {
    var writes = 0
    func authorization() async -> ReminderAuthorization { .undetermined }
    func requestAuthorization() async throws -> Bool { writes += 1; return false }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { writes += 1 }
    func removePending(_ identifiers: [String]) { writes += identifiers.count }
    func removeDelivered(_ identifiers: [String]) { writes += identifiers.count }
}

/// Production chrome and direct own-window input only. No global events, mouse
/// movement, app activation, desktop screenshots, personal archive or clipboard.
@main @MainActor private final class WindowChromePresentationTests: NSObject, NSApplicationDelegate {
    private static var checks = 0
    private static var evidence: [[String: Any]] = []
    private var result: Int32 = 0
    static func main() {
        let app = NSApplication.shared, delegate = WindowChromePresentationTests()
        app.setActivationPolicy(.accessory); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        exit(delegate.result)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await Self.run() }
            catch { result = 1; fputs("Window chrome QA failed: \(error)\n", stderr) }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }
    private static func failure(_ text: String) -> NSError {
        NSError(domain: "WindowChromePresentationTests", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
    private static func expect(_ value: @autoclosure () -> Bool, _ text: String) throws {
        checks += 1
        guard value() else { throw failure(text) }
    }
    private static func settle(_ view: NSView) async {
        for _ in 0..<4 { view.layoutSubtreeIfNeeded(); try? await Task.sleep(for: .milliseconds(35)) }
        view.displayIfNeeded(); CATransaction.flush()
    }
    private static var handles: [BoardResizeGeometry.Edge] {
        [.left, .right, .bottom, .top, [.left, .top], [.right, .top], [.left, .bottom], [.right, .bottom]]
    }
    private static func point(_ edge: BoardResizeGeometry.Edge, in rect: CGRect) -> CGPoint {
        CGPoint(x: edge.contains(.left) ? rect.minX : edge.contains(.right) ? rect.maxX : rect.midX,
                y: edge.contains(.bottom) ? rect.minY : edge.contains(.top) ? rect.maxY : rect.midY)
    }
    private static func inward(_ edge: BoardResizeGeometry.Edge, distance: CGFloat) -> CGPoint {
        CGPoint(x: edge.contains(.left) ? distance : edge.contains(.right) ? -distance : 0,
                y: edge.contains(.bottom) ? distance : edge.contains(.top) ? -distance : 0)
    }
    private static func geometryChecks() throws {
        try expect(BoardResizeGeometry.innerGrabWidth == 6 && BoardResizeGeometry.cornerReach == 12,
                   "Visible edge padding has a six-point grip and corners retain twelve-point padding reach")
        for bounds in [CGRect(x: 0, y: 0, width: 400, height: 550), CGRect(x: -37, y: 54, width: 1220, height: 850)] {
            let content = RobotAppFrameView.contentRect(in: bounds)
            let regions = BoardResizeGeometry.edgeRegions(in: bounds) + BoardResizeGeometry.cornerRegions(in: bounds)
            try expect(regions.count == 9 && regions.allSatisfy { !$0.rect.isEmpty && bounds.contains($0.rect) },
                       "Five edge bands and four corner grips stay inside offset native bounds")
            for edge in handles {
                let visiblePoint = point(edge, in: content), shallow = inward(edge, distance: 5.5)
                let inside = CGPoint(x: visiblePoint.x + shallow.x, y: visiblePoint.y + shallow.y)
                let outer = CGPoint(x: visiblePoint.x - shallow.x, y: visiblePoint.y - shallow.y)
                for candidate in [visiblePoint, inside, outer] {
                    try expect(BoardResizeGeometry.interactionEdge(at: candidate, in: bounds) == edge,
                               "Visible handle \(edge.rawValue) accepts exact, shallow-inner and shallow-outer hits: \(candidate)")
                    try expect(regions.contains { $0.edge == edge && $0.rect.contains(candidate) },
                               "Hit-tested handle is represented by the same native cursor-region geometry")
                }
                if edge.rawValue.nonzeroBitCount == 2 {
                    let deeper = inward(edge, distance: 11)
                    try expect(BoardResizeGeometry.interactionEdge(at: CGPoint(x: visiblePoint.x + deeper.x, y: visiblePoint.y + deeper.y), in: bounds) == edge,
                               "Rounded corner \(edge.rawValue) remains grabbable eleven points inside without covering header controls")
                    let physical = point(edge, in: bounds.insetBy(dx: 0.5, dy: 0.5))
                    try expect(BoardResizeGeometry.interactionEdge(at: physical, in: bounds) == edge,
                               "Physical outer corner \(edge.rawValue) keeps both resize axes")
                }
            }
            for candidate in [CGPoint(x: content.minX + 7, y: content.midY), CGPoint(x: content.maxX - 7, y: content.midY),
                              CGPoint(x: content.midX, y: content.minY + 7), CGPoint(x: content.midX, y: content.maxY - 7)] {
                try expect(BoardResizeGeometry.interactionEdge(at: candidate, in: bounds).isEmpty,
                           "Controls beyond the shallow grip padding keep their ordinary hit area")
            }
            let drag = BoardResizeGeometry.dragRegion(in: bounds)
            try expect(!drag.isEmpty && BoardResizeGeometry.interactionEdge(at: CGPoint(x: drag.midX, y: drag.midY), in: bounds).isEmpty,
                       "Chrome movement has an independent nonoverlapping drag band")
            for candidate in [CGPoint(x: bounds.minX - 0.1, y: bounds.midY), CGPoint(x: bounds.maxX + 0.1, y: bounds.midY),
                              CGPoint(x: CGFloat.nan, y: bounds.midY), CGPoint(x: bounds.midX, y: CGFloat.infinity)] {
                try expect(BoardResizeGeometry.interactionEdge(at: candidate, in: bounds).isEmpty,
                           "Resize rejects out-of-window and nonfinite points")
            }
        }
        for bounds in [CGRect.zero, CGRect(x: 3, y: -8, width: 10, height: 10)] {
            try expect(BoardResizeGeometry.edgeRegions(in: bounds).isEmpty && BoardResizeGeometry.cornerRegions(in: bounds).isEmpty,
                       "Invalid/tiny surfaces do not install phantom cursor or resize regions")
        }
    }
    private static func event(_ type: NSEvent.EventType, screen: CGPoint, window: NSWindow, clicks: Int = 1) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: window.convertPoint(fromScreen: screen), modifierFlags: [],
            timestamp: 1, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: clicks, pressure: 1)!
    }
    private static func screenPoint(_ local: CGPoint, view: NSView, window: NSWindow) -> CGPoint {
        window.convertPoint(toScreen: view.convert(local, to: nil))
    }
    private static func interactionChecks() async throws {
        guard let display = NSScreen.screens.first(where: {
            $0.visibleFrame.width >= 520 && $0.visibleFrame.height >= 650
        }) else { throw failure("A display large enough for the supported compact board is required") }
        let visible = display.visibleFrame
        let compact = CGRect(x: floor(visible.midX - 200), y: floor(visible.midY - 275), width: 400, height: 550)
        let content = NSView(frame: .zero)
        let button = NSButton(title: "Fictional content control", target: nil, action: nil)
        content.addSubview(button)
        let frame = RobotAppFrameView(contentView: content)
        let window = ChromeFixtureWindow(contentRect: compact, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.isOpaque = false; window.backgroundColor = .clear
        window.contentView = frame; frame.autoresizingMask = [.width, .height]
        window.orderFront(nil); frame.setVisible(true)
        defer { frame.cancelWindowInteraction(); window.orderOut(nil); window.contentView = nil; window.close() }
        var starts = 0, ends = 0, changes = 0, dragEnds = 0, toggles = 0
        frame.onResizeStarted = { starts += 1 }
        frame.onResize = { rect in changes += 1; window.setFrame(rect, display: true) }
        frame.onResizeEnded = { ends += 1 }
        frame.onDragStarted = {}
        frame.onDragEnded = { _ in dragEnds += 1 }
        frame.onToggleExpanded = { toggles += 1 }
        await settle(frame)
        try expect(!window.isKeyWindow && !window.canBecomeKey && window.screen != nil,
                   "Direct-event fixture has a measured display but cannot steal keyboard focus")
        for (name, original) in [("compact", compact), ("expanded-safe-area", visible)] {
            for edge in handles {
                window.setFrame(original, display: true); frame.layoutSubtreeIfNeeded()
                let contentRect = RobotAppFrameView.contentRect(in: frame.bounds)
                let local = point(edge, in: contentRect), start = screenPoint(local, view: frame, window: window)
                let delta = inward(edge, distance: name == "compact" ? -24 : 24)
                let end = CGPoint(x: start.x + delta.x, y: start.y + delta.y)
                let expected = BoardResizeGeometry.resized(original, edge: edge, delta: delta, visible: visible)
                let hit = frame.superview.map { frame.convert(local, to: $0) } ?? local
                try expect(frame.hitTest(hit) === frame, "\(name) visible handle \(edge.rawValue) routes native hit testing to resize")
                let shallow = inward(edge, distance: 5.5)
                var probes = [CGPoint(x: local.x + shallow.x, y: local.y + shallow.y),
                              CGPoint(x: local.x - shallow.x, y: local.y - shallow.y)]
                if edge.rawValue.nonzeroBitCount == 2 {
                    probes.append(point(edge, in: frame.bounds.insetBy(dx: 0.5, dy: 0.5)))
                }
                for probe in probes {
                    let hit = frame.superview.map { frame.convert(probe, to: $0) } ?? probe
                    try expect(frame.hitTest(hit) === frame, "\(name) shallow/physical grip \(edge.rawValue) is an actual native hit target: \(probe)")
                }
                let initialStarts = starts, initialEnds = ends, initialChanges = changes
                frame.mouseDown(with: event(.leftMouseDown, screen: start, window: window))
                frame.mouseDragged(with: event(.leftMouseDragged, screen: end, window: window))
                try expect(window.frame == expected && window.frame != original && changes == initialChanges + 1,
                           "\(name) handle \(edge.rawValue) actually resizes: actual=\(window.frame), expected=\(expected)")
                try expect((!edge.contains(.left) || window.frame.maxX == original.maxX)
                    && (!edge.contains(.right) || window.frame.minX == original.minX)
                    && (!edge.contains(.top) || window.frame.minY == original.minY)
                    && (!edge.contains(.bottom) || window.frame.maxY == original.maxY),
                    "\(name) handle \(edge.rawValue) retains every opposite anchor")
                frame.mouseUp(with: event(.leftMouseUp, screen: end, window: window))
                try expect(starts == initialStarts + 1 && ends == initialEnds + 1, "Native resize begins and releases exactly once")
                frame.mouseDragged(with: event(.leftMouseDragged, screen: CGPoint(x: end.x + 80, y: end.y + 80), window: window))
                try expect(window.frame == expected, "Released handle ignores stale drag events")
            }
        }
        window.setFrame(compact, display: true); frame.layoutSubtreeIfNeeded()
        button.frame = CGRect(x: 14, y: content.bounds.height - 50, width: 140, height: 28)
        let controlPoint = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: frame)
        let controlHit = frame.superview.map { frame.convert(controlPoint, to: $0) } ?? controlPoint
        try expect(frame.hitTest(controlHit) === button, "Enlarged edge/corner grips leave padded content controls clickable")
        let close = NSButton(title: "Fictional close", target: nil, action: nil)
        close.frame = CGRect(x: content.bounds.width - 40, y: content.bounds.height - 34, width: 28, height: 28)
        let project = NSButton(title: "Fictional project", target: nil, action: nil)
        project.frame = CGRect(x: 12, y: content.bounds.height - 38, width: 124, height: 32)
        content.addSubview(close); content.addSubview(project)
        for (control, probe) in [(close, CGPoint(x: close.bounds.maxX - 1, y: close.bounds.maxY - 1)),
                                 (project, CGPoint(x: project.bounds.minX + 1, y: project.bounds.maxY - 1))] {
            let local = control.convert(probe, to: frame)
            let hit = frame.superview.map { frame.convert(local, to: $0) } ?? local
            try expect(BoardResizeGeometry.interactionEdge(at: local, in: frame.bounds).isEmpty
                && frame.hitTest(hit) === control,
                "Header control's outward top corner retains its complete padded click area: \(control.title), \(local)")
        }
        let band = BoardResizeGeometry.dragRegion(in: frame.bounds), local = CGPoint(x: band.midX, y: band.midY)
        let start = screenPoint(local, view: frame, window: window), end = CGPoint(x: start.x + 18, y: start.y - 14)
        frame.mouseDown(with: event(.leftMouseDown, screen: start, window: window))
        frame.mouseDragged(with: event(.leftMouseDragged, screen: end, window: window))
        frame.mouseUp(with: event(.leftMouseUp, screen: end, window: window))
        try expect(window.frame == compact.offsetBy(dx: 18, dy: -14) && dragEnds == 1,
                   "Reserved robot chrome still moves the window and releases normally")
        let moved = window.frame
        frame.mouseDown(with: event(.leftMouseDown, screen: screenPoint(local, view: frame, window: window), window: window, clicks: 2))
        try expect(toggles == 1 && window.frame == moved, "Chrome double-click still dispatches expansion once without beginning a move")
        frame.onResize = nil; frame.onDragStarted = nil
        let decorative = CGPoint(x: frame.bounds.midX, y: frame.bounds.maxY - 1)
        let decorativeHit = frame.superview.map { frame.convert(decorative, to: $0) } ?? decorative
        try expect(frame.hitTest(decorativeHit) == nil,
                   "Unconfigured decorative robot chrome remains click-through")
    }

    private static func layers(_ layer: CALayer?) -> [CALayer] {
        guard let layer else { return [] }
        return [layer] + (layer.sublayers ?? []).flatMap { layers($0) } + layers(layer.mask)
    }
    private static func named(_ name: String, in layer: CALayer?) throws -> CALayer {
        guard let result = layers(layer).first(where: { $0.name == name }) else { throw failure("Missing actual chrome layer \(name)") }
        return result
    }
    private static func pathRecords(_ path: CGPath) -> [(Int, [CGFloat])] {
        var result: [(Int, [CGFloat])] = []
        path.applyWithBlock { item in
            let element = item.pointee, count: Int
            switch element.type {
            case .moveToPoint, .addLineToPoint: count = 1
            case .addQuadCurveToPoint: count = 2
            case .addCurveToPoint: count = 3
            case .closeSubpath: count = 0
            @unknown default: count = 0
            }
            result.append((Int(element.type.rawValue), (0..<count).flatMap { [element.points[$0].x, element.points[$0].y] }))
        }
        return result
    }
    private static func pathMatches(_ actual: CGPath?, _ expected: CGPath) -> Bool {
        guard let actual else { return false }
        let a = pathRecords(actual), b = pathRecords(expected)
        return a.count == b.count && zip(a, b).allSatisfy { lhs, rhs in
            lhs.0 == rhs.0 && lhs.1.count == rhs.1.count
                && zip(lhs.1, rhs.1).allSatisfy { abs($0 - $1) < 0.000_01 }
        }
    }
    private static func bitmap(_ view: NSView, scale: CGFloat) throws -> NSBitmapImageRep {
        let size = view.bounds.size
        guard let result = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0) else { throw failure("Native chrome bitmap allocation failed") }
        result.size = size; view.cacheDisplay(in: view.bounds, to: result)
        return result
    }
    private static func save(_ bitmap: NSBitmapImageRep, filename: String, output: URL) throws {
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw failure("Native chrome PNG encoding failed") }
        try data.write(to: output.appendingPathComponent(filename), options: .atomic)
    }
    private static func maskPixels(_ mask: CAShapeLayer, scale: CGFloat) throws -> (bitmap: NSBitmapImageRep, fractional: [Int]) {
        let size = mask.bounds.size, width = Int(size.width * scale), height = Int(size.height * scale)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let path = mask.path else {
            throw failure("Actual reveal mask could not be rendered")
        }
        context.scaleBy(x: scale, y: scale)
        mask.render(in: context)
        guard let image = context.makeImage() else { throw failure("Actual reveal mask image could not be read") }
        let bitmap = NSBitmapImageRep(cgImage: image)
        bitmap.size = size
        var fractional = [Int](repeating: 0, count: 4)
        let reach = Int(ceil((BoardWindowChrome.cornerRadius + 6) * scale))
        for corner in 0..<4 {
            for dy in 0..<reach {
                for dx in 0..<reach {
                    let x = corner % 2 == 0 ? dx : width - 1 - dx
                    let y = corner < 2 ? dy : height - 1 - dy
                    let alpha = bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
                    if alpha > 0.02 && alpha < 0.98 { fractional[corner] += 1 }
                    // Curves are symmetric, so CG/bitmap vertical orientation
                    // does not affect this corner sample's expected coverage.
                    let p = CGPoint(x: (CGFloat(x) + 0.5) / scale, y: (CGFloat(y) + 0.5) / scale)
                    let probes = [CGPoint(x: p.x - 1.5, y: p.y), CGPoint(x: p.x + 1.5, y: p.y),
                                  CGPoint(x: p.x, y: p.y - 1.5), CGPoint(x: p.x, y: p.y + 1.5)]
                    if probes.allSatisfy({ path.contains($0) }) {
                        try expect(alpha > 0.95, "Continuous mask has no transparent gaps inside corner \(corner): \(p), alpha=\(alpha)")
                    } else if probes.allSatisfy({ !path.contains($0) }) {
                        try expect(alpha < 0.05, "Continuous mask has no opaque square steps outside corner \(corner): \(p), alpha=\(alpha)")
                    }
                }
            }
            try expect(fractional[corner] > 4, "Native \(Int(scale))x corner \(corner) has antialiased curve coverage, not a hard square/stair-step")
        }
        return (bitmap, fractional)
    }

    private static func visualChecks(output: URL) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinChromeQA-\(UUID().uuidString)")
        let suite = "DaBinChromeQA.\(UUID().uuidString)", defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: PreviewService.linkPreviewPreference)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root)
        _ = try store.capture(text: "Fictional corner review. Preserve this original capture.")
        let previews = PreviewService(store: store, defaults: defaults), client = ChromeFixtureReminders()
        let auto = AutoCaptureService(settings: AutoCaptureSettings(defaults: defaults), input: InputService(store: store),
            pasteboardProvider: { fatalError("Chrome QA must not read the clipboard") }, sourceApplicationProvider: { nil })
        let state = AppState(store: store, previews: previews,
            reminders: ReminderService(store: store, client: client), autoCapture: auto,
            captureClipboard: CaptureClipboardService(writer: { _ in fatalError("Chrome QA must not write the clipboard") }))
        defer { state.shutdownNotificationPresentation(); state.focusSessions.shutdown(); auto.shutdown(); previews.shutdown() }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let baseline = try store.captures.map { try encoder.encode(CaptureSnapshot($0)) }
        state.openDaily(); state.isBoardVisible = true
        let theme = ThemeSettings(defaults: defaults, systemDarkMode: false)
        theme.setBoardOpacity(1); theme.setShowTooltips(false)
        try expect(BoardWindowChrome.cornerRadius == 21 && BoardWindowChrome.rimWidth == 2.25,
                   "Shared board chrome uses the agreed continuous corner and thin rim")
        for size in [CGSize(width: 380, height: 500), CGSize(width: 1200, height: 800)] {
            for dark in [false, true] {
                theme.setDarkMode(dark)
                for scale in [CGFloat(1), CGFloat(2)] {
                    let name = "\(Int(size.width))x\(Int(size.height))-\(dark ? "dark" : "light")@\(Int(scale))x"
                    let export = DayExportActionController(pasteboardWriter: { _ in false }, destinationChooser: { _, _ in .cancelled }, fileWriter: { _, _ in })
                    let hosting = NSHostingView(rootView: BoardView(state: state, theme: theme, dayExportController: export)
                        .environment(\.displayScale, scale).transaction { $0.animation = nil; $0.disablesAnimations = true })
                    let frame = RobotAppFrameView(contentView: hosting), outer = RobotAppFrameView.outerSize(forContentSize: size)
                    frame.frame = CGRect(origin: .zero, size: outer)
                    let window = ChromeFixtureWindow(contentRect: CGRect(x: -10_000, y: -10_000, width: outer.width, height: outer.height),
                        styleMask: [.borderless], backing: .buffered, defer: false)
                    window.fixtureScale = scale; window.isReleasedWhenClosed = false; window.isOpaque = false; window.backgroundColor = .clear
                    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua); hosting.appearance = window.appearance
                    window.contentView = frame; frame.autoresizingMask = [.width, .height]
                    window.orderFront(nil); frame.setVisible(true); frame.viewDidChangeBackingProperties()
                    defer { window.orderOut(nil); window.contentView = nil; window.close() }
                    await settle(frame)
                    guard let container = hosting.superview, let reveal = container.layer?.mask as? CAShapeLayer,
                          let outline = try named("robotFrame.outline", in: frame.layer) as? CAShapeLayer,
                          let rim = try named("robotFrame.continuousRim", in: frame.layer) as? CAShapeLayer else {
                        throw failure("Actual Board content/mask/outline/rim are not mounted")
                    }
                    let content = RobotAppFrameView.contentRect(in: frame.bounds)
                    try expect(pathMatches(reveal.path, BoardWindowChrome.path(in: container.bounds))
                        && pathMatches(reveal.path, BoardWindowChrome.shape.path(in: container.bounds).cgPath),
                        "\(name): native reveal mask exactly matches the SwiftUI continuous board shape")
                    try expect(container.layer?.cornerRadius == 0 && container.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))?.alphaComponent == 0,
                               "\(name): no mismatched circular clip or opaque host backing hides user transparency")
                    try expect(pathMatches(outline.path, BoardWindowChrome.path(in: content, outset: 0.75))
                        && pathMatches(rim.path, BoardWindowChrome.rimPath(in: content)) && rim.fillRule == .evenOdd && rim.mask == nil,
                        "\(name): finishing outline and thin hollow rim ride the identical shared continuous curve")
                    let customRoots: [CALayer] = [try named("robotFrame.outline", in: frame.layer),
                        try named("robotFrame.continuousRim", in: frame.layer), reveal]
                    let custom: [CALayer] = customRoots.reduce(into: []) { result, root in
                        result.append(contentsOf: layers(root))
                    }
                    try expect(custom.allSatisfy { $0.contentsScale == scale && $0.rasterizationScale == scale && $0.allowsEdgeAntialiasing && !$0.shouldRasterize },
                               "\(name): custom vectors and masks track backing scale without rasterizing the interactive board")
                    let pixels = try maskPixels(reveal, scale: scale)
                    let full = try bitmap(frame, scale: scale)
                    try expect(full.pixelsWide == Int(outer.width * scale) && full.pixelsHigh == Int(outer.height * scale)
                        && window.frame.maxX < 0 && !window.isKeyWindow, "\(name): actual Board PNG has the requested density in an offscreen non-key fixture")
                    try save(full, filename: "board-\(name).png", output: output)
                    try save(pixels.bitmap, filename: "content-mask-\(name).png", output: output)
                    let oldPath = reveal.path
                    window.fixtureScale = scale == 1 ? 2 : 1
                    frame.viewDidChangeBackingProperties()
                    try expect(custom.allSatisfy { $0.contentsScale == window.fixtureScale && $0.rasterizationScale == window.fixtureScale }
                        && pathMatches(reveal.path, oldPath!), "Backing-scale notification updates vectors immediately without changing corner geometry")
                    evidence.append(["file": "board-\(name).png", "maskFile": "content-mask-\(name).png",
                        "contentWidth": size.width, "contentHeight": size.height, "scale": scale,
                        "fractionalAlphaPixelsByCorner": pixels.fractional])
                }
            }
        }
        let after = try store.captures.map { try encoder.encode(CaptureSnapshot($0)) }
        try expect(after == baseline && client.writes == 0, "Window/corner presentation preserves full fictional capture originals and never requests notification access")
    }

    private static func run() async throws {
        try geometryChecks()
        try await interactionChecks()
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("build/qa/window-chrome/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try await visualChecks(output: output)
        let report: [String: Any] = ["checks": checks, "fixtures": evidence,
            "privacy": "Fictional isolated captures/preferences, own non-key windows, direct native events, no global cursor, clipboard, network or desktop capture."]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("report.json"), options: .atomic)
        print("PASS: \(checks) window chrome checks; visible/physical resize grips, direct native drags, smooth shared corner masks and 1x/2x appearance. Evidence: \(output.path)")
    }
}
