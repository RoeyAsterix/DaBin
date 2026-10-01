import AppKit
import ApplicationServices
import Foundation
import SwiftUI

@MainActor private final class ExplorerCardFixtureWindow: NSWindow {
    override var backingScaleFactor: CGFloat { 2 }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
@MainActor private final class ExplorerCardNotifications: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .undetermined }
    func requestAuthorization() async throws -> Bool { false }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}
@MainActor private final class ExplorerCardSelection { var calls = 0 }
@MainActor private struct ExplorerCardFixture: View {
    @ObservedObject var state: AppState
    let capture: Capture
    let selection: ExplorerCardSelection
    @FocusState private var focus: UUID?
    var body: some View {
        ExplorerCaptureRow(state: state, workspace: state.workspace, capture: capture, focus: $focus) {
            selection.calls += 1
            state.workspace.selectedCaptureID = capture.id
        }
    }
}
@MainActor private struct ExplorerCardAX {
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

/// Production Explorer cards, fictional local images and captures, native 2x
/// offscreen non-key windows. No clipboard, network, archive from the user,
/// desktop screenshots, application activation or global events.
@main @MainActor private final class ExplorerCaptureCardPresentationTests: NSObject, NSApplicationDelegate {
    private static var checks = 0
    private static var reports: [[String: Any]] = []
    private var result: Int32 = 0
    static func main() {
        let app = NSApplication.shared
        let delegate = ExplorerCaptureCardPresentationTests()
        app.setActivationPolicy(.accessory); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        exit(delegate.result)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await Self.run() }
            catch { result = 1; fputs("Explorer card QA failed: \(error)\n", stderr) }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "ExplorerCaptureCardPresentationTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        guard try condition() else { throw failure(message) }
    }
    private static func nodes(_ view: NSView) -> [ExplorerCardAX] {
        var seen = Set<ObjectIdentifier>(), result: [ExplorerCardAX] = []
        func visit(_ candidate: Any, depth: Int) {
            guard depth < 50, let object = candidate as? NSObject,
                  seen.insert(ObjectIdentifier(object)).inserted else { return }
            let node = ExplorerCardAX(object: object); result.append(node)
            node.children.forEach { visit($0, depth: depth + 1) }
        }
        visit(view, depth: 0)
        NSAccessibility.unignoredChildren(from: [view]).forEach { visit($0, depth: 0) }
        return result
    }
    private static func settle(_ view: NSView) async {
        for _ in 0..<6 { view.layoutSubtreeIfNeeded(); try? await Task.sleep(for: .milliseconds(35)) }
    }
    private static func find(_ view: NSView, id: String? = nil, label: String? = nil) async throws -> ExplorerCardAX {
        for _ in 0..<6 {
            if let node = nodes(view).first(where: { id != nil ? $0.identifier == id : $0.label == label }) { return node }
            await settle(view)
        }
        throw failure("Missing Explorer action \(id ?? label ?? "unknown"): \(nodes(view).map { $0.identifier ?? $0.label }.joined(separator: "; "))")
    }

    private static func fixturePNG(portrait: Bool) throws -> Data {
        let width = portrait ? 420 : 640, height = portrait ? 640 : 420
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw failure("Fixture image allocation failed") }
        context.setFillColor(CGColor(red: 0.10, green: 0.70, blue: 0.83, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let markerWidth = CGFloat(width) * 0.18, markerHeight = CGFloat(height) * 0.18
        let colors: [(CGFloat, CGFloat, CGFloat)] = [(0.95, 0.05, 0.07), (0.05, 0.90, 0.12), (0.08, 0.17, 0.95), (0.98, 0.75, 0.05)]
        for (index, color) in colors.enumerated() {
            context.setFillColor(CGColor(red: color.0, green: color.1, blue: color.2, alpha: 1))
            context.fill(CGRect(x: index % 2 == 0 ? 0 : CGFloat(width) - markerWidth,
                y: index < 2 ? 0 : CGFloat(height) - markerHeight, width: markerWidth, height: markerHeight))
        }
        guard let image = context.makeImage(), let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw failure("Fixture PNG encoding failed") }
        return png
    }
    private static func snapshots(_ captures: [Capture]) throws -> [UUID: Data] {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try Dictionary(uniqueKeysWithValues: captures.map { ($0.id, try encoder.encode(CaptureSnapshot($0))) })
    }
    private static func originalBytes(_ captures: [Capture], store: CaptureStore) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for capture in captures {
            for url in [store.managedURL(for: capture), store.previewURL(for: capture)].compactMap({ $0 }) {
                result[url.path] = try Data(contentsOf: url)
            }
        }
        return result
    }

    private static func render(state: AppState, capture: Capture, name: String, width: CGFloat, dark: Bool,
                               colorful: Bool, output: URL) async throws -> CGFloat {
        state.workspace.selectedCaptureID = nil
        let selection = ExplorerCardSelection()
        let size = CGSize(width: width + 24, height: 1_000)
        let root = VStack(alignment: .leading, spacing: 0) {
            ExplorerCardFixture(state: state, capture: capture, selection: selection)
                .fixedSize(horizontal: false, vertical: true).frame(width: width)
                .accessibilityElement(children: .contain).accessibilityIdentifier("fixture-explorer-card")
        }.padding(12).frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(Palette.background).environment(\.displayScale, 2)
            .environment(\.daBinTooltipsEnabled, false).preferredColorScheme(dark ? .dark : .light)
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: size); hosting.wantsLayer = true
        let window = ExplorerCardFixtureWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
                                               styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.appearance = appearance; hosting.appearance = appearance; window.contentView = hosting
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        window.orderFront(nil)
        await settle(hosting)
        let activation = await Task.detached {
            let process = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            AXUIElementSetMessagingTimeout(process, 3)
            var windows: CFTypeRef?
            return AXUIElementCopyAttributeValue(process, kAXWindowsAttribute as CFString, &windows)
        }.value
        try expect(activation == .success && window.frame.maxX < 0 && !window.isKeyWindow, "Only own offscreen non-key Explorer fixtures initialize")
        await settle(hosting)
        let card = try await find(hosting, id: "fixture-explorer-card")
        let open = try await find(hosting, id: "workspace-item-\(capture.id.uuidString)")
        let category = capture.isTask ? "Task" : captureTypeLabel(capture.kind)
        try expect(open.label == "Open \(capture.title.isEmpty ? "Untitled capture" : capture.title)"
            && open.valueText == captureReceiptText(capture) + ", " + category, "Single selection target preserves title, exact capture receipt and category")
        try expect(abs(card.frame.width - width) < 1 && card.frame.height > 80
            && window.frame.insetBy(dx: -1, dy: -1).contains(card.frame), "Actual Explorer card fits its complete narrow/normal window")
        let copy = try await find(hosting, id: "capture-copy-\(capture.id.uuidString)")
        let trash = try await find(hosting, id: "capture-trash-\(capture.id.uuidString)")
        let project = try await find(hosting, label: capture.parentTaskID == nil ? "Project" : "Parent task project")
        let trail = try await find(hosting, id: "capture-trail-\(capture.id.uuidString)")
        for control in [open, copy, trash, project, trail] {
            try expect(control.frame.width > 0 && control.frame.height > 0 && card.frame.insetBy(dx: -1, dy: -1).contains(control.frame),
                       "Explorer selection/header/trail controls remain visible and contained")
        }
        let expectedProject = ExplorerQuery.project(of: capture, in: state.store.captures) ?? "Unfiled"
        if let parentID = capture.parentTaskID, project.valueText.isEmpty {
            // A readonly SwiftUI group does not expose AXValue through these
            // in-process selectors on this SDK. Its inherited label/geometry
            // are real AX; check the exact effective ownership separately.
            try expect(project.label == "Parent task project"
                && state.store.captures.first(where: { $0.id == parentID })?.projectName == expectedProject,
                "Readonly inherited project keeps its accessible label and exact parent ownership")
        } else {
            try expect(project.valueText == expectedProject,
                       "Project-leading picker exposes its exact project; actual=\(project.valueText), expected=\(expectedProject)")
        }
        let visible = nodes(hosting).filter {
            $0.frame.width > 0 && $0.frame.height > 0 && card.frame.insetBy(dx: -1, dy: -1).contains($0.frame)
        }
        try expect(visible.filter { $0.identifier == "capture-trail-\(capture.id.uuidString)" }.count == 1,
                   "ViewThatFits exposes only one visible content-trail footer action")
        let quickLabel = capture.isTask ? "Complete task" : "Turn into task"
        let quickCount = visible.filter { $0.label == quickLabel }.count
        try expect(quickCount == (capture.isTask || capture.parentTaskID == nil ? 1 : 0),
                   "Footer exposes one task checkbox/conversion action, and no conversion for an attachment")
        if capture.isTask {
            _ = try await find(hosting, label: "Complete task")
            _ = try await find(hosting, label: "Set focus duration")
            if state.lastConvertedCaptureID == capture.id {
                _ = try await find(hosting, id: "capture-conversion-undo-\(capture.id.uuidString)")
            }
        } else if capture.parentTaskID == nil { _ = try await find(hosting, label: "Turn into task") }
        let large = ExplorerCaptureCardPresentation.hasLargePreview(capture: capture, store: state.store)
        let previewHeight = ExplorerCaptureCardPresentation.previewHeight(for: open.frame.width)
        try expect(large ? open.frame.height >= previewHeight + 25 : open.frame.height < 115,
                   "Visual preview dominates selection while text-only selection stays compact: \(open.frame)")
        let actual = hosting.convert(window.convertFromScreen(card.frame), from: nil)
        try expect(hosting.bounds.insetBy(dx: -1, dy: -1).contains(actual), "Actual card is fully contained before PNG crop")
        let rect = actual.intersection(hosting.bounds).integral
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(rect.width * 2), pixelsHigh: Int(rect.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { throw failure("Explorer 2x bitmap allocation failed") }
        bitmap.size = rect.size; hosting.cacheDisplay(in: rect, to: bitmap)
        var cornerCounts = [Int](repeating: 0, count: 4), minY = bitmap.pixelsHigh, maxY = -1
        if colorful {
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 4) {
                for x in stride(from: 0, to: bitmap.pixelsWide, by: 4) {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    let r = color.redComponent, g = color.greenComponent, b = color.blueComponent
                    var marker: Int?
                    if r > 0.75 && g < 0.30 && b < 0.30 { marker = 0 }
                    else if g > 0.65 && r < 0.35 && b < 0.35 { marker = 1 }
                    else if b > 0.70 && r < 0.30 && g < 0.40 { marker = 2 }
                    else if r > 0.75 && g > 0.50 && b < 0.25 { marker = 3 }
                    if let marker { cornerCounts[marker] += 1; minY = min(minY, y); maxY = max(maxY, y) }
                }
            }
            try expect(cornerCounts.allSatisfy { $0 > 10 }, "Landscape/portrait preview preserves all four actual image corners: \(cornerCounts)")
            try expect(CGFloat(maxY - minY) / 2 > previewHeight * 0.50, "Real cached image pixels occupy a large preview, not a miniature icon")
        }
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw failure("Explorer PNG encoding failed") }
        let filename = "\(name)-\(Int(width))-\(dark ? "dark" : "light")@2x.png"
        try png.write(to: output.appendingPathComponent(filename), options: .atomic)
        try expect(bitmap.pixelsWide == Int(rect.width * 2), "Explorer PNG is rendered at native 2x")
        try expect(open.press(), "Existing Explorer AX selection action activates")
        await settle(hosting)
        try expect(selection.calls == 1 && state.workspace.selectedCaptureID == capture.id,
                   "Single full-card AX press selects exactly once without opening any external file")
        _ = try await find(hosting, id: "workspace-item-\(capture.id.uuidString)")
        reports.append(["file": filename, "widthPoints": width, "heightPoints": rect.height, "largePreview": large,
                        "previewHeightPoints": previewHeight, "cornerMarkerSampleCounts": cornerCounts,
                        "receipt": open.valueText, "selectionCallbackCount": selection.calls])
        return card.frame.height
    }

    private static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinExplorerCardQA-\(UUID().uuidString)")
        let suite = "DaBinExplorerCardQA.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: PreviewService.linkPreviewPreference)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root), at = ISO8601DateFormatter().date(from: "2026-10-01T14:26:00Z")!, zone = TimeZone(secondsFromGMT: 0)!
        let landscape = try fixturePNG(portrait: false), portrait = try fixturePNG(portrait: true)
        func image(_ png: Data, _ name: String, parent: Capture? = nil, thumbnail: Bool = true) async throws -> Capture {
            let item = try await store.importData(png, filename: name, at: at, timeZone: zone, parentTask: parent)
            if thumbnail {
                guard let path = await PreviewService.writeThumbnail(png, root: root, id: item.id) else { throw failure("Local thumbnail write failed") }
                item.thumbnailRelativePath = path; item.previewState = "ready"; try store.save(captures: [item])
            }
            return item
        }
        let wide = try await image(landscape, "Landscape corner study.png")
        let tall = try await image(portrait, "Portrait corner study.png")
        let converted = try await image(landscape, "Converted image task.png")
        let missing = try await image(landscape, "Image awaiting its local thumbnail.png", thumbnail: false)
        let text = try store.capture(text: "A compact fictional text note", at: at, timeZone: zone)[0]
        let parent = try store.createTask(text: "Parent fictional reference task")
        parent.projectName = "A deliberately long fictional project name for narrow Explorer cards"; try store.save(captures: [parent])
        let child = try await image(portrait, "A deliberately long portrait attachment title for narrow cards.png", parent: parent)
        let file = try await store.importData(Data("Fictional generic file".utf8), filename: "Fixture.bin", at: at, timeZone: zone)
        let link = try store.capture(text: "https://example.invalid/fictional-card", at: at, timeZone: zone)[0]
        let previews = PreviewService(store: store, defaults: defaults)
        let auto = AutoCaptureService(settings: AutoCaptureSettings(defaults: defaults), input: InputService(store: store),
            pasteboardProvider: { fatalError("Explorer QA must not read clipboard") }, sourceApplicationProvider: { nil })
        defer { previews.shutdown(); auto.shutdown() }
        let state = AppState(store: store, previews: previews, reminders: ReminderService(store: store, client: ExplorerCardNotifications()),
            autoCapture: auto, captureClipboard: CaptureClipboardService(writer: { _ in fatalError("Explorer QA must not write clipboard") }))
        defer { state.focusSessions.shutdown() }
        state.convertToTask(converted)
        try expect(missing.thumbnailRelativePath == nil && store.previewURL(for: missing) == nil,
                   "Missing-derivative fixture starts without constructor-created preview work")
        try expect(converted.isTask && converted.kind == .image && state.canUndoTaskConversion, "Converted image task retains original visual kind and Undo")
        for kind in [CaptureKind.image, .video, .pdf, .document, .ai] {
            let capture = Capture(capturedAt: at, kind: kind, title: "Visual kind fixture")
            try expect(ExplorerCaptureCardPresentation.hasLargePreview(capture: capture, store: store), "Visual kind keeps large preview even before derivative exists")
        }
        try expect(!ExplorerCaptureCardPresentation.hasLargePreview(capture: text, store: store)
            && !ExplorerCaptureCardPresentation.hasLargePreview(capture: file, store: store)
            && !ExplorerCaptureCardPresentation.hasLargePreview(capture: link, store: store), "Text/file/link without local artwork do not gain an empty hero")
        for capture in [file, link] {
            capture.thumbnailRelativePath = await PreviewService.writeThumbnail(landscape, root: root, id: capture.id)
            capture.previewState = "ready"; try store.save(captures: [capture])
            try expect(ExplorerCaptureCardPresentation.hasLargePreview(capture: capture, store: store), "Existing file/link local thumbnail enables the large preview without network")
        }
        for (width, expected) in [(CGFloat(0), CGFloat(160)), (-1, 160), (.infinity, 160), (.nan, 160),
                                  (100, 160), (220, 176), (320, 256), (380, 300), (10_000, 300)] {
            try expect(ExplorerCaptureCardPresentation.previewHeight(for: width) == expected, "Preview height is finite and bounded for \(width)")
        }
        let all = store.captures, baseline = try snapshots(all), bytes = try originalBytes(all, store: store)
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("build/qa/explorer-capture-cards", isDirectory: true).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for width in [CGFloat(220), 320, 380] {
            for dark in [false, true] { _ = try await render(state: state, capture: wide, name: "landscape", width: width, dark: dark, colorful: true, output: output) }
        }
        for (capture, name, width, dark, colorful) in [
            (tall, "portrait", CGFloat(220), true, true), (tall, "portrait", 380, false, true),
            (converted, "image-task", 320, false, true), (converted, "image-task", 320, true, true),
            (text, "text", 220, true, false), (text, "text", 380, false, false),
            (missing, "missing-thumbnail", 220, false, false), (child, "child-long-labels", 220, true, true)
        ] { _ = try await render(state: state, capture: capture, name: name, width: width, dark: dark, colorful: colorful, output: output) }
        let after = try snapshots(all), afterBytes = try originalBytes(all, store: store)
        try expect(after == baseline && afterBytes == bytes,
                   "Rendering and selection change no captured identity, original, receipt, history, planning or file bytes")
        try expect(try snapshots(CaptureStore(root: root).captures) == baseline, "Fictional saved captures remain unchanged after reopening")
        try JSONSerialization.data(withJSONObject: ["checksPassed": checks, "fixtures": reports,
            "renderMethod": "Actual production ExplorerCaptureRow in native 2x offscreen NSHostingViews",
            "privacy": "Isolated fictional archive/preferences; locally drawn four-corner images; no clipboard, network, external applications, desktop capture or global events"], options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("explorer-capture-card-report.json"), options: .atomic)
        print("PASS: \(checks) Explorer native preview, complete-image corners, metadata, actions, selection and capture preservation checks. \(output.path)")
    }
}
