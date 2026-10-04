@testable import DaBinTestCore
import AppKit
import ApplicationServices
import Foundation
import QuartzCore
import SwiftUI

/// Marketing-guide fixtures only: no personal data, clipboard, global input,
/// notification delivery, network requests, or standard preference mutations.
@MainActor private final class GuideNotificationClient: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .undetermined }
    func requestAuthorization() async throws -> Bool { fatalError("Guide export cannot request permissions") }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { fatalError("Guide export cannot deliver notifications") }
    func removePending(_ identifiers: [String]) {}
    func removeDelivered(_ identifiers: [String]) {}
}

@MainActor private final class GuideWindow: NSWindow {
    var fixtureScale: CGFloat = 2
    override var backingScaleFactor: CGFloat { fixtureScale }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor private struct GuideAXNode {
    let object: NSObject
    func value(_ name: String) -> Any? {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue()
    }
    var identifier: String? { value("accessibilityIdentifier") as? String }
    var label: String? { value("accessibilityLabel") as? String }
    var frame: CGRect {
        let selector = NSSelectorFromString("accessibilityFrame")
        guard object.responds(to: selector) else { return .zero }
        typealias Getter = @convention(c) (AnyObject, Selector) -> CGRect
        return unsafeBitCast(object.method(for: selector), to: Getter.self)(object, selector)
    }
    var children: [Any] {
        var result: [Any] = []
        for name in ["accessibilityChildren", "accessibilityChildrenInNavigationOrder", "accessibilityContents"] {
            if let values = value(name) as? [Any] { result += values }
        }
        if let view = object as? NSView { result += view.subviews }
        return result
    }
}

@main @MainActor private final class ExportGuide: NSObject, NSApplicationDelegate {
    private var result: Int32 = 0
    private var records: [[String: Any]] = []
    static func main() {
        let app = NSApplication.shared, delegate = ExportGuide()
        app.setActivationPolicy(.prohibited)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        exit(delegate.result)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await run() }
            catch { result = 1; fputs("Guide asset export failed: \(error)\n", stderr) }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }
    private func run() async throws {
        guard CommandLine.arguments.count == 2 else { throw failure("Pass the guide asset output directory") }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinGuideExport-\(UUID().uuidString)", isDirectory: true)
        let suite = "DaBin.GuideExport.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw failure("Isolated preferences unavailable") }
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        defaults.set(false, forKey: PreviewService.linkPreviewPreference)
        let store = try CaptureStore(root: root)
        let stamp = ISO8601DateFormatter().date(from: "2026-10-04T06:40:00Z")!
        let project = "Weekend ideas"
        let note = try store.createNote(text: "A little fresh air\nPack a snack, pick a quiet path, and leave time to explore.",
            at: stamp.addingTimeInterval(-172800), projectName: project)
        note.title = "A little fresh air for the weekend"
        var planning = TaskPlanning(); planning.priority = .medium; planning.effortMinutes = 25
        let task = try store.createTask(text: "Plan a weekend walk", at: stamp.addingTimeInterval(-120),
            planning: planning, projectName: project)
        let image = try await store.importData(landscapePNG(), filename: "Weekend trail.png", at: stamp)
        image.title = "A weekend trail worth saving"
        image.previewDescription = "A quiet path, a bright morning, and a little room to wander."
        try store.setOrganization(image, pinned: false, projectName: project)
        image.thumbnailRelativePath = "Previews/\(image.id.uuidString)/thumbnail.png"
        let thumbnail = root.appendingPathComponent(image.thumbnailRelativePath!)
        try FileManager.default.createDirectory(at: thumbnail.deletingLastPathComponent(), withIntermediateDirectories: true)
        try landscapePNG().write(to: thumbnail, options: .atomic)
        image.previewState = "ready"
        _ = try store.createNote(text: "Weekend idea: try the riverside path on Saturday.", at: stamp.addingTimeInterval(-86400))
        try store.save()
        let previews = PreviewService(store: store, defaults: defaults)
        let auto = AutoCaptureService(settings: AutoCaptureSettings(defaults: defaults), input: InputService(store: store),
            pasteboardProvider: { fatalError("Guide export cannot read the clipboard") }, sourceApplicationProvider: { nil })
        let state = AppState(store: store, previews: previews,
            reminders: ReminderService(store: store, client: GuideNotificationClient()),
            robotPlacement: RobotPlacementSettings(defaults: defaults), autoCapture: auto,
            captureClipboard: CaptureClipboardService(writer: { _ in fatalError("Guide export cannot write the clipboard") }),
            quickAccessSettings: QuickAccessSettings(defaults: defaults))
        defer { state.shutdownNotificationPresentation(); state.focusSessions.shutdown(); auto.shutdown(); previews.shutdown() }
        let theme = ThemeSettings(defaults: defaults, systemDarkMode: false)
        theme.setBoardOpacity(1); theme.setDarkMode(false); theme.select(.teal); theme.setShowTooltips(false)
        state.isBoardVisible = true
        state.openLibrary(); state.libraryProject = project; state.workspace.mode = .collection
        try state.workspace.setProjectColor(hex: "198F91", for: project)
        state.workspace.selectedCaptureID = image.id
        state.workspace.explorerShowsDailyFiles = false
        state.status = nil
        try await board(state, theme: theme, filename: "DABIN__GUIDE__PROJECTS.png", contentSize: CGSize(width: 800, height: 600), output: output)
        state.clearNewNoteDraft(); state.openInbox(); state.newNoteText = "An idea for the weekend…"; state.status = nil
        try await board(state, theme: theme, filename: "DABIN__GUIDE__INBOX.png", contentSize: CGSize(width: 380, height: 430), output: output)
        state.clearNewNoteDraft(); state.openSearch(); state.query = "weekend"; state.status = nil
        try await board(state, theme: theme, filename: "DABIN__GUIDE__SEARCH.png", contentSize: CGSize(width: 900, height: 540), output: output)
        _ = state.configureTaskFocus(task, hours: 0, minutes: 25)
        state.openCapture(task.id); state.detailFocus = nil; state.status = nil
        try await board(state, theme: theme, filename: "DABIN__GUIDE__TASK.png", contentSize: CGSize(width: 380, height: 560), output: output)
        try await robot(output: output)
        try JSONSerialization.data(withJSONObject: [
            "fixturePrivacy": "Fictional temporary archive and isolated preferences only. No personal captures, clipboard access, network, installed-app actions, global input, notification delivery, or permission prompts.",
            "renderMethod": "Current production native BoardView and RobotAppFrameView at 2x; canonical native RobotCharacterView at 8x. Native cacheDisplay, no pixel resampling.",
            "assets": records
        ], options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("guide-native-renders.json"), options: .atomic)
        print("PASS: \(records.count) current-production fictional guide assets exported")
    }
    private func failure(_ text: String) -> NSError {
        NSError(domain: "DaBinGuideExport", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
    private func bitmap(_ view: NSView, scale: Int) throws -> NSBitmapImageRep {
        let size = view.bounds.size
        guard let result = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale,
            pixelsHigh: Int(size.height) * scale, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { throw failure("Bitmap allocation failed") }
        if let bytes = result.bitmapData { bytes.initialize(repeating: 0, count: result.bytesPerRow * result.pixelsHigh) }
        result.size = size; view.cacheDisplay(in: view.bounds, to: result)
        return result
    }
    private func save(_ bitmap: NSBitmapImageRep, filename: String, output: URL) throws {
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw failure("PNG encoding failed") }
        try png.write(to: output.appendingPathComponent(filename), options: .atomic)
    }
    private func anchors(in view: NSView, window: NSWindow) -> [[String: Any]] {
        var seen = Set<ObjectIdentifier>(), result: [[String: Any]] = []
        func walk(_ any: Any) {
            guard let object = any as? NSObject, seen.insert(ObjectIdentifier(object)).inserted else { return }
            let node = GuideAXNode(object: object)
            if let id = node.identifier, !node.frame.isEmpty {
                let frame = window.convertFromScreen(node.frame)
                result.append(["id": id, "label": node.label ?? "", "logicalRectFromTopLeft": [frame.minX, view.bounds.height - frame.maxY, frame.width, frame.height]])
            }
            for child in node.children { walk(child) }
        }
        walk(view)
        for child in NSAccessibility.unignoredChildren(from: [view]) { walk(child) }
        return result
    }
    private func board(_ state: AppState, theme: ThemeSettings, filename: String, contentSize: CGSize, output: URL) async throws {
        let export = DayExportActionController(pasteboardWriter: { _ in false }, destinationChooser: { _, _ in .cancelled }, fileWriter: { _, _ in })
        let hosting = NSHostingView(rootView: BoardView(state: state, theme: theme, dayExportController: export)
            .environment(\.displayScale, 2).transaction { $0.animation = nil; $0.disablesAnimations = true })
        let view = RobotAppFrameView(contentView: hosting)
        let size = RobotAppFrameView.outerSize(forContentSize: contentSize)
        view.frame = CGRect(origin: .zero, size: size)
        let window = GuideWindow(contentRect: CGRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.fixtureScale = 2; window.isReleasedWhenClosed = false; window.isOpaque = false; window.backgroundColor = .clear
        window.contentView = view; view.autoresizingMask = [.width, .height]
        CornerController.applyBoardAppearance(darkMode: false, to: window, frame: view, hosting: hosting)
        window.orderFront(nil); view.cancelTransition(open: true); view.viewDidChangeBackingProperties()
        defer { view.setVisible(false); window.orderOut(nil); window.contentView = nil; window.close() }
        for _ in 0..<6 { view.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(90)) }
        if state.route == .library, let scroll = scrollViews(in: hosting).first,
           let document = scroll.documentView {
            let top = document.isFlipped ? CGFloat(0) : max(0, document.bounds.height - scroll.contentView.bounds.height)
            scroll.contentView.scroll(to: CGPoint(x: 0, y: top)); scroll.reflectScrolledClipView(scroll.contentView)
            for _ in 0..<3 { view.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(75)) }
        }
        // Request only this export process's virtual native accessibility tree.
        // No permission dialog, other-process query, global input or activation.
        _ = await Task.detached {
            let process = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            AXUIElementSetMessagingTimeout(process, 3)
            var windows: CFTypeRef?
            return AXUIElementCopyAttributeValue(process, kAXWindowsAttribute as CFString, &windows).rawValue
        }.value
        try await Task.sleep(for: .milliseconds(120))
        view.displayIfNeeded(); CATransaction.flush()
        let rendered = try bitmap(view, scale: 2)
        try save(rendered, filename: filename, output: output)
        records.append(["file": filename, "logicalWidth": Int(size.width), "logicalHeight": Int(size.height),
            "pixelWidth": rendered.pixelsWide, "pixelHeight": rendered.pixelsHigh, "pixelScale": 2,
            "route": String(describing: state.route), "anchors": anchors(in: view, window: window)])
    }
    private func scrollViews(in view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
    }
    private func robot(output: URL) async throws {
        let size = CGSize(width: 64, height: 78)
        let view = RobotCharacterView(frame: CGRect(origin: .zero, size: size), reduceMotion: { true })
        let window = GuideWindow(contentRect: CGRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.fixtureScale = 8; window.isReleasedWhenClosed = false; window.isOpaque = false; window.backgroundColor = .clear
        window.contentView = view; window.orderFront(nil)
        defer { view.stopMotion(); window.orderOut(nil); window.contentView = nil; window.close() }
        view.send(.reveal(.right)); view.layoutSubtreeIfNeeded(); view.viewDidChangeBackingProperties()
        try await Task.sleep(for: .milliseconds(160))
        view.displayIfNeeded(); CATransaction.flush()
        let rendered = try bitmap(view, scale: 8), filename = "DABIN__GUIDE__ROBOT.png"
        try save(rendered, filename: filename, output: output)
        records.append(["file": filename, "logicalWidth": 64, "logicalHeight": 78,
            "pixelWidth": rendered.pixelsWide, "pixelHeight": rendered.pixelsHigh, "pixelScale": 8,
            "artwork": "Canonical RobotCharacterView Quiet Orbit idle pose; transparent background; Reduce Motion injected only for this native instance."])
    }
    private func landscapePNG() throws -> Data {
        let size = CGSize(width: 1000, height: 650)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw failure("Landscape fixture allocation failed") }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSColor(red: 0.87, green: 0.96, blue: 0.94, alpha: 1).setFill(); NSRect(origin: .zero, size: size).fill()
        NSColor(red: 0.99, green: 0.77, blue: 0.40, alpha: 1).setFill()
        NSBezierPath(ovalIn: CGRect(x: 720, y: 450, width: 100, height: 100)).fill()
        func hill(_ color: NSColor, _ points: [CGPoint]) {
            let path = NSBezierPath(); path.move(to: points[0])
            for point in points.dropFirst() { path.line(to: point) }
            path.close(); color.setFill(); path.fill()
        }
        hill(NSColor(red: 0.47, green: 0.70, blue: 0.64, alpha: 1), [CGPoint(x: 0,y: 0), CGPoint(x: 0,y: 340), CGPoint(x: 250,y: 520), CGPoint(x: 540,y: 310), CGPoint(x: 770,y: 430), CGPoint(x: 1000,y: 280), CGPoint(x: 1000,y: 0)])
        hill(NSColor(red: 0.22, green: 0.53, blue: 0.46, alpha: 1), [CGPoint(x: 0,y: 0), CGPoint(x: 0,y: 190), CGPoint(x: 240,y: 300), CGPoint(x: 550,y: 190), CGPoint(x: 810,y: 290), CGPoint(x: 1000,y: 180), CGPoint(x: 1000,y: 0)])
        hill(NSColor(red: 0.12, green: 0.36, blue: 0.32, alpha: 1), [CGPoint(x: 0,y: 0), CGPoint(x: 0,y: 100), CGPoint(x: 330,y: 180), CGPoint(x: 640,y: 80), CGPoint(x: 1000,y: 130), CGPoint(x: 1000,y: 0)])
        let trail = NSBezierPath(); trail.move(to: CGPoint(x: 515,y: 0)); trail.curve(to: CGPoint(x: 650,y: 190), controlPoint1: CGPoint(x: 280,y: 135), controlPoint2: CGPoint(x: 660,y: 120)); trail.lineWidth = 38
        NSColor(red: 0.96, green: 0.87, blue: 0.65, alpha: 1).setStroke(); trail.stroke()
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw failure("Landscape PNG failed") }
        return png
    }
}
