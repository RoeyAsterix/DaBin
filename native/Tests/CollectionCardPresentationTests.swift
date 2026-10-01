import AppKit
import ApplicationServices
import Foundation
import SwiftUI

@MainActor private final class CollectionFixtureWindow: NSWindow {
    override var backingScaleFactor: CGFloat { 2 }
    // This fixture is deliberately taller than the physical display so the
    // expanded production card can be captured without scrolling or clipping.
    // Only our offscreen test window bypasses AppKit's visible-screen limit.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor private final class CollectionFixtureReminders: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .undetermined }
    func requestAuthorization() async throws -> Bool { false }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}

/// Public accessibility selectors, restricted to controls in our own windows.
@MainActor private struct CollectionAXNode {
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
    var valueText: String {
        (value("accessibilityValue") as? String) ?? (attribute("AXValue") as? String) ?? ""
    }
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

/// Actual production cards rendered at native 2x. Every original, thumbnail,
/// preference and receipt is fictional and lives in this fixture's temp store.
/// No user archive, external application, clipboard, global event or network.
@main @MainActor private final class CollectionCardPresentationTests: NSObject, NSApplicationDelegate {
    private static var checks = 0
    private static var reports: [[String: Any]] = []
    private var result: Int32 = 0

    static func main() {
        let application = NSApplication.shared
        let delegate = CollectionCardPresentationTests()
        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
        exit(delegate.result)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await Self.run() }
            catch { result = 1; fputs("Collection presentation QA failed: \(error)\n", stderr) }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "CollectionCardPresentationTests", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
    private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        guard try condition() else { throw failure(message) }
    }
    private static func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    private static func checkSelectionAndGeometry() throws {
        let kinds: [CaptureKind] = [.text, .file, .video, .pdf, .image, .document, .link, .task]
        let items = kinds.enumerated().map { index, kind in
            Capture(capturedAt: date("2026-10-01T14:00:00Z"), kind: kind,
                    originalText: "Fictional selection \(index)", title: "Selection \(index)")
        }
        let selection = CollectionPreviewSelection(captures: items + [items[2], items[0]])
        try expect(selection.totalCount == 8 && selection.omittedCount == 4,
                   "Selection counts unique captures, not duplicate references or action receipts")
        try expect(selection.previews.map(\.id) == [items[2], items[4], items[3], items[5]].map(\.id),
                   "Four actual previews prefer visual types and preserve input order within each priority")
        try expect(Set(selection.previews.map(\.id)).count == CollectionPreviewSelection.maximumCount,
                   "Preview maximum is four distinct captures")
        for count in 0...4 {
            let subset = Array(items.prefix(count))
            let selected = CollectionPreviewSelection(captures: subset)
            try expect(selected.previews.count == count && selected.totalCount == count && selected.omittedCount == 0,
                       "Small and empty collections do not invent preview contents")
        }
        for compact in [false, true] {
            let height = CollectionPreviewLayout.previewHeight(compact: compact)
            try expect(height == (compact ? 152 : 220), "The actual collection preview has a large fixed height")
            for width in [CGFloat(1), 20, 172, 318, 618] {
                for count in 1...4 {
                    let bounds = CGRect(x: 0, y: 0, width: width, height: height)
                    let layout = CollectionPreviewMosaicLayout(count: count, size: bounds.size, compact: compact)
                    try expect(layout.frames.count == count, "Mosaic has exactly one tile per selected capture")
                    try expect(layout.frames.allSatisfy { $0.width > 0 && $0.height > 0 && bounds.contains($0) },
                               "Every narrow/normal tile is positive and contained: \(width), \(count)")
                    for left in layout.frames.indices {
                        for right in layout.frames.indices where right > left {
                            let intersection = layout.frames[left].intersection(layout.frames[right])
                            try expect(intersection.isNull || intersection.isEmpty,
                                       "Mosaic tiles never overlap at any supported width")
                        }
                    }
                }
            }
            for size in [CGSize.zero, CGSize(width: -1, height: 152), CGSize(width: 200, height: 0),
                         CGSize(width: CGFloat.infinity, height: 152), CGSize(width: 200, height: CGFloat.nan)] {
                try expect(CollectionPreviewMosaicLayout(count: 4, size: size, compact: compact).frames.isEmpty,
                           "Invalid geometry has no unsafe or nonfinite tiles")
            }
            try expect(CollectionPreviewMosaicLayout(count: 0, size: CGSize(width: 200, height: height), compact: compact).frames.isEmpty,
                       "Empty collection has no fabricated tile")
            try expect(CollectionPreviewMosaicLayout(count: 20, size: CGSize(width: 200, height: height), compact: compact).frames.count == 4,
                       "Geometry enforces the same four-preview bound as selection")
        }
    }

    private static func nodes(_ view: NSView) -> [CollectionAXNode] {
        view.layoutSubtreeIfNeeded()
        var seen = Set<ObjectIdentifier>()
        var result: [CollectionAXNode] = []
        func visit(_ candidate: Any, depth: Int) {
            guard depth < 50, let object = candidate as? NSObject,
                  seen.insert(ObjectIdentifier(object)).inserted else { return }
            let node = CollectionAXNode(object: object)
            result.append(node)
            node.children.forEach { visit($0, depth: depth + 1) }
        }
        visit(view, depth: 0)
        NSAccessibility.unignoredChildren(from: [view]).forEach { visit($0, depth: 0) }
        return result
    }
    private static func settle(_ view: NSView) async {
        // The production hourly action uses an explicit 200ms withAnimation.
        // Let that transaction finish before inspecting static AX/render bounds.
        for _ in 0..<8 { view.layoutSubtreeIfNeeded(); try? await Task.sleep(for: .milliseconds(35)) }
    }
    private static func find(_ view: NSView, id: String? = nil, label: String? = nil) async throws -> CollectionAXNode {
        for _ in 0..<8 {
            if let node = nodes(view).first(where: { node in
                if let id { return node.identifier == id }
                return node.label == label
            }) { return node }
            await settle(view)
        }
        throw failure("Missing collection control \(id ?? label ?? "unknown"): \(nodes(view).map { $0.identifier ?? $0.label }.joined(separator: "; "))")
    }

    private static func withCard<V: View>(_ card: V, width: CGFloat, dark: Bool,
                                         body: (NSView, NSWindow) async throws -> Void) async throws {
        let size = NSSize(width: width + 24, height: 2_400)
        let root = VStack(alignment: .leading, spacing: 0) {
            card.fixedSize(horizontal: false, vertical: true).frame(width: width)
                .accessibilityIdentifier("fixture-collection-card")
        }
        .padding(12)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(Palette.background)
        .environment(\.displayScale, 2)
        .transaction { $0.animation = nil; $0.disablesAnimations = true }
        .environment(\.daBinTooltipsEnabled, false)
        .preferredColorScheme(dark ? .dark : .light)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.wantsLayer = true
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let window = CollectionFixtureWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
                                             styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        hosting.appearance = appearance
        window.contentView = hosting
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        window.orderFront(nil)
        window.setFrame(NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height), display: true)
        await settle(hosting)
        let activated = await Task.detached {
            let process = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            AXUIElementSetMessagingTimeout(process, 3)
            var windows: CFTypeRef?
            return AXUIElementCopyAttributeValue(process, kAXWindowsAttribute as CFString, &windows)
        }.value
        try expect(activated == .success, "Own-process collection AX initializes")
        await settle(hosting)
        try expect(window.frame.maxX < 0 && !window.isKeyWindow, "Fictional collection windows remain offscreen and non-key")
        try expect(abs(hosting.bounds.height - size.height) < 1 && abs(hosting.bounds.width - size.width) < 1,
                   "Tall offscreen fixture keeps its requested content size instead of physical-screen constraints")
        try await body(hosting, window)
    }

    private static func snapshot(_ view: NSView, window: NSWindow, to url: URL) async throws -> NSBitmapImageRep {
        let card = try await find(view, id: "fixture-collection-card")
        let actual = view.convert(window.convertFromScreen(card.frame), from: nil)
        print("Collection snapshot geometry: file=\(url.lastPathComponent), window=\(window.frame), content=\(window.contentView?.frame ?? .zero), hosting.frame=\(view.frame), hosting.bounds=\(view.bounds), flipped=\(view.isFlipped), cardAX=\(card.frame), converted=\(actual)")
        try expect(actual.width > 100 && actual.height > 100 && view.bounds.insetBy(dx: -1, dy: -1).contains(actual),
                   "Actual card is visible and fully contained before rendering: \(actual)")
        let rect = actual.intersection(view.bounds).integral
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(rect.width * 2),
            pixelsHigh: Int(rect.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw failure("Native collection bitmap allocation failed")
        }
        bitmap.size = rect.size
        view.cacheDisplay(in: rect, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw failure("Collection PNG encoding failed") }
        try png.write(to: url, options: .atomic)
        try expect(bitmap.pixelsWide == Int(rect.width * 2) && bitmap.pixelsHigh == Int(rect.height * 2),
                   "Evidence is an actual native 2x card, not a scaled screenshot")
        return bitmap
    }

    private struct PixelMetrics {
        let fraction: Double
        let width: CGFloat
        let height: CGFloat
        let neutralBrightness: Double
    }
    private static func pixels(_ bitmap: NSBitmapImageRep) -> PixelMetrics {
        var samples = 0, vivid = 0, neutral = 0
        var brightness: Double = 0
        var minX = bitmap.pixelsWide, maxX = -1, minY = bitmap.pixelsHigh, maxY = -1
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 4) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 4) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let channels = [color.redComponent, color.greenComponent, color.blueComponent]
                let delta = (channels.max() ?? 0) - (channels.min() ?? 0)
                samples += 1
                if delta > 0.38 && (channels.max() ?? 0) > 0.60 {
                    vivid += 1; minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                } else if delta < 0.10 {
                    neutral += 1; brightness += Double(channels.reduce(0, +) / 3)
                }
            }
        }
        return PixelMetrics(fraction: Double(vivid) / Double(max(1, samples)),
            width: maxX >= minX ? CGFloat(maxX - minX + 4) / 2 : 0,
            height: maxY >= minY ? CGFloat(maxY - minY + 4) / 2 : 0,
            neutralBrightness: brightness / Double(max(1, neutral)))
    }

    private static func assertCollapsed(_ view: NSView, window: NSWindow, kind: String, width: CGFloat,
                                        dark: Bool, count: String, time: String, output: URL) async throws -> Double {
        let summary = try await find(view, id: kind == "hour" ? "collection-hour-summary" : "collection-batch-summary")
        try expect(summary.frame.width > width * 0.75 && summary.frame.height > 100,
                   "The entire preview is the accessible collection expansion target")
        let semantics = summary.label + " " + summary.valueText
        try expect(semantics.contains(count) && semantics.contains(time), "Collection count and original capture time are exposed: \(semantics)")
        try expect(kind == "hour" ? summary.label.hasPrefix("Expand actions,") : summary.label == "Expand batch items",
                   "Collection expansion preserves its established accessible action")
        let expectedHeight = CollectionPreviewLayout.previewHeight(compact: width == 200)
        try expect(summary.frame.height >= expectedHeight + 28 && expectedHeight / summary.frame.height >= 0.60,
                   "The large preview dominates the actual summary and leaves room for visible count/time: \(summary.frame)")
        let card = try await find(view, id: "fixture-collection-card")
        try expect(card.frame.width >= width - 1 && card.frame.width <= width + 1,
                   "Collection fits the requested weekly/normal width without horizontal overflow")
        for suffix in ["count", "time"] {
            if let metadata = nodes(view).first(where: { $0.identifier == "collection-\(kind)-\(suffix)" }) {
                try expect(metadata.frame.width > 0 && metadata.frame.height >= 9 && card.frame.insetBy(dx: -1, dy: -1).contains(metadata.frame),
                           "Visible collection \(suffix) glyphs fit the card")
            }
        }
        // Combined button AX intentionally hides decorative thumbnail children.
        // Validate real cached-image pixels rather than requiring those children.
        let filename = "\(kind)-collapsed-\(Int(width))-\(dark ? "dark" : "light")@2x.png"
        let bitmap = try await snapshot(view, window: window, to: output.appendingPathComponent(filename))
        let metric = pixels(bitmap)
        try expect(metric.fraction > 0.10 && metric.width > width * 0.55 && metric.height > expectedHeight * 0.55,
                   "Real colored previews span most of the collection, not a small decorative icon: \(metric)")
        reports.append(["file": filename, "widthPoints": width, "heightPoints": bitmap.size.height,
                        "previewHeightPoints": expectedHeight, "vividPixelFraction": metric.fraction,
                        "vividExtentWidthPoints": metric.width, "vividExtentHeightPoints": metric.height,
                        "neutralBrightness": metric.neutralBrightness, "count": count, "receipt": time])
        return metric.neutralBrightness
    }

    private static func fixturePNG(index: Int) throws -> Data {
        let width = 600, height = 420
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw failure("Generic fixture image allocation failed")
        }
        let colors: [(CGFloat, CGFloat, CGFloat)] = [(0.04, 0.78, 0.93), (0.94, 0.09, 0.55), (0.97, 0.64, 0.04)]
        let color = colors[index % colors.count]
        context.setFillColor(CGColor(red: color.0, green: color.1, blue: color.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
        context.fill(CGRect(x: 70, y: 70, width: 90 + index * 35, height: 90))
        guard let image = context.makeImage(), let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw failure("Generic fixture image encoding failed")
        }
        return data
    }

    private static func immutableSnapshots(_ captures: [Capture], allowingPresentation: Bool) throws -> [UUID: Data] {
        try Dictionary(uniqueKeysWithValues: captures.map { capture in
            let encoded = try JSONEncoder().encode(CaptureSnapshot(capture))
            var object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
            if allowingPresentation { object.removeValue(forKey: "isMinimized"); object.removeValue(forKey: "updatedAt") }
            return (capture.id, try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
        })
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

    private static func run() async throws {
        try checkSelectionAndGeometry()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinCollectionQA-\(UUID().uuidString)")
        let suite = "DaBinCollectionQA.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: PreviewService.linkPreviewPreference)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root)
        let zone = TimeZone(secondsFromGMT: 0)!
        let pngs = try (0..<3).map { try fixturePNG(index: $0) }
        var automatic: [Capture] = []
        var batch: [Capture] = []
        func receipt(_ origin: CaptureOrigin, _ action: UUID) -> CaptureReceiptContext {
            .automatic(origin, actionID: action, sourceApplicationName: "Fixture Studio", sourceApplicationBundleIdentifier: "com.dabin.fixture")
        }
        func image(_ index: Int, name: String, at: Date, receipt: CaptureReceiptContext) async throws -> Capture {
            let capture = try await store.importData(pngs[index], filename: name, at: at, timeZone: zone, receipt: receipt)
            guard let thumbnail = await PreviewService.writeThumbnail(pngs[index], root: root, id: capture.id) else {
                throw failure("Own local thumbnail could not be written")
            }
            capture.thumbnailRelativePath = thumbnail; capture.previewState = "ready"
            try store.save(captures: [capture])
            return capture
        }
        let first = UUID(), second = UUID(), third = UUID(), fourth = UUID()
        automatic.append(try await image(0, name: "Cyan study.png", at: date("2026-10-01T14:06:00Z"), receipt: receipt(.automaticScreenshot, first)))
        automatic.append(try await image(1, name: "Magenta study.png", at: date("2026-10-01T14:06:00Z"), receipt: receipt(.automaticScreenshot, first)))
        automatic.append(try await store.importData(Data("Fictional measured file A".utf8), filename: "Measurements.bin",
            at: date("2026-10-01T14:12:00Z"), timeZone: zone, receipt: receipt(.automaticClipboard, second)))
        automatic += try store.capture(text: "Studio note: compare the three colored samples.", at: date("2026-10-01T14:18:00Z"),
            timeZone: zone, receipt: receipt(.automaticClipboard, third))
        automatic.append(try await image(2, name: "Golden study.png", at: date("2026-10-01T14:24:00Z"), receipt: receipt(.automaticClipboard, fourth)))
        automatic += try store.capture(text: "Final fictional note: keep the originals unchanged.", at: date("2026-10-01T14:24:00Z"),
            timeZone: zone, receipt: receipt(.automaticClipboard, fourth))
        let batchAt = date("2026-10-01T16:20:00Z")
        for index in 0..<3 { batch.append(try await image(index, name: "Batch sample \(index + 1).png", at: batchAt, receipt: .manual)) }
        for index in 0..<2 {
            batch.append(try await store.importData(Data("Fictional batch file \(index)".utf8), filename: "Batch record \(index + 1).bin", at: batchAt, timeZone: zone))
        }
        for capture in automatic + batch { try store.setMinimized(capture, minimized: true) }
        let previews = PreviewService(store: store, defaults: defaults)
        let auto = AutoCaptureService(settings: AutoCaptureSettings(defaults: defaults), input: InputService(store: store),
            pasteboardProvider: { fatalError("Collection QA must not read the clipboard") }, sourceApplicationProvider: { nil })
        defer { previews.shutdown(); auto.shutdown() }
        let state = AppState(store: store, previews: previews, reminders: ReminderService(store: store, client: CollectionFixtureReminders()),
            robotPlacement: RobotPlacementSettings(defaults: nil), autoCapture: auto,
            captureClipboard: CaptureClipboardService(writer: { _ in fatalError("Collection expansion must not write the clipboard") }),
            quickAccessSettings: QuickAccessSettings(defaults: nil))
        state.selectedDay = date("2026-10-01T12:00:00Z")
        let groups = HourlyCaptureFeed.cards(from: automatic, filter: .all, today: state.selectedDay, calendarTimeZone: zone)
        guard groups.count == 1, case .automaticHour(let hour) = groups[0],
              let batchGroup = CaptureCardGroup.cards(from: batch).first else { throw failure("Fictional collection fixtures did not group") }
        try expect(hour.totalActionCount == 4 && hour.totalCaptureCount == 6 && batchGroup.captures.count == 5,
                   "Fixtures contain multi-capture actions and an actual five-file batch")
        let all = automatic + batch
        let baseline = try immutableSnapshots(all, allowingPresentation: true)
        let hourlyBaseline = try immutableSnapshots(automatic, allowingPresentation: false)
        let bytes = try originalBytes(all, store: store)
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("build/qa/collection-card-presentation", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let hourTime = "\(prettyDay(hour.id.captureDay, includeWeekday: false)) · \(hour.id.rangeLabel)"
        var brightness: [String: Double] = [:]
        for width in [CGFloat(200), 350] {
            for dark in [false, true] {
                try await withCard(HourlyCaptureCard(state: state, group: hour, compact: width == 200), width: width, dark: dark) { view, window in
                    let value = try await assertCollapsed(view, window: window, kind: "hour", width: width, dark: dark,
                        count: "6 captures", time: hourTime, output: output)
                    brightness["hour-\(Int(width))-\(dark)"] = value
                }
                try await withCard(GroupedCaptureCard(state: state, group: batchGroup, compact: width == 200), width: width, dark: dark) { view, window in
                    let value = try await assertCollapsed(view, window: window, kind: "batch", width: width, dark: dark,
                        count: "5 captures", time: captureReceiptText(batchGroup.primary), output: output)
                    brightness["batch-\(Int(width))-\(dark)"] = value
                    try expect(!nodes(view).contains { $0.label == "Show items" || $0.label == "Show batch items" },
                               "Minimized batch has no redundant second expansion control")
                }
            }
            for kind in ["hour", "batch"] {
                try expect((brightness["\(kind)-\(Int(width))-false"] ?? 0) - (brightness["\(kind)-\(Int(width))-true"] ?? 0) > 0.20,
                           "Actual light and dark card pixels exercise distinct native themes")
            }
        }
        for dark in [false, true] {
            try await withCard(HourlyCaptureCard(state: state, group: hour), width: 650, dark: dark) { view, window in
                let expand = try await find(view, id: "collection-hour-summary")
                try expect(expand.press(), "Accessible full-preview activation opens the hourly collection")
                await settle(view)
                try expect(state.isHourlyGroupExpanded(hour.id), "Hourly expansion state is real, not only a changed label")
                let collapse = try await find(view, label: "Collapse actions")
                try expect(collapse.frame.width > 0 && collapse.frame.height > 0,
                           "Expanded hour offers a visible accessible collapse action")
                _ = try await snapshot(view, window: window, to: output.appendingPathComponent("hour-expanded-650-\(dark ? "dark" : "light")@2x.png"))
                try expect(try immutableSnapshots(automatic, allowingPresentation: false) == hourlyBaseline,
                           "Opening an hour changes no saved capture, receipt or edit timestamp")
                try expect(collapse.press(), "Hourly collection can be collapsed through its real control")
                await settle(view)
                try expect(!state.isHourlyGroupExpanded(hour.id), "Hourly collection restores its summary state")
                _ = try await find(view, id: "collection-hour-summary")
            }
            try await withCard(GroupedCaptureCard(state: state, group: batchGroup), width: 650, dark: dark) { view, window in
                let expand = try await find(view, id: "collection-batch-summary")
                try expect(expand.press(), "Accessible full-preview activation opens the batch")
                await settle(view)
                try expect(batch.allSatisfy { !$0.isMinimized }, "Batch expansion changes every member's presentation flag")
                let collapse = try await find(view, label: "Collapse batch items")
                try expect(!nodes(view).contains { $0.identifier == "collection-batch-summary" || $0.identifier == "collection-preview-mosaic" },
                           "Expanded batch shows item details without a duplicate overview mosaic")
                let reopened = try CaptureStore(root: root)
                try expect(reopened.captures.filter { Set(batch.map(\.id)).contains($0.id) }.allSatisfy { !$0.isMinimized },
                           "Existing batch expansion semantics persist in the isolated archive")
                _ = try await snapshot(view, window: window, to: output.appendingPathComponent("batch-expanded-650-\(dark ? "dark" : "light")@2x.png"))
                try expect(collapse.press(), "Expanded batch can be restored through its real collapse control")
                await settle(view)
                try expect(batch.allSatisfy(\.isMinimized), "Batch returns to the minimized preview-led overview")
                _ = try await find(view, id: "collection-batch-summary")
            }
        }
        try expect(try immutableSnapshots(all, allowingPresentation: true) == baseline,
                   "Only established batch presentation flags/edit times change; identities, titles, originals, receipts and history survive")
        try expect(try immutableSnapshots(automatic, allowingPresentation: false) == hourlyBaseline,
                   "Repeated hourly expansion and collapse remain entirely transient")
        try expect(try originalBytes(all, store: store) == bytes, "All original and thumbnail file bytes remain untouched")
        let reopened = try CaptureStore(root: root)
        try expect(Set(reopened.captures.map(\.id)) == Set(all.map(\.id)), "No expansion creates or deletes saved captures")
        try expect(reopened.captures.filter { Set(batch.map(\.id)).contains($0.id) }.allSatisfy(\.isMinimized),
                   "Final collapsed batch state remains persisted")
        let report: [String: Any] = ["checksPassed": checks, "fixtures": reports,
            "privacy": "Fictional temporary archive/preferences; local geometric images; own-process offscreen non-key AX; no clipboard/network/global input",
            "renderMethod": "Production HourlyCaptureCard and GroupedCaptureCard in native 2x NSHostingViews",
            "hourActionCount": hour.totalActionCount, "hourCaptureCount": hour.totalCaptureCount, "batchCaptureCount": batch.count]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("collection-card-presentation-report.json"), options: .atomic)
        print("PASS: \(checks) collection selection, layout, native preview, theme, AX expansion and data preservation checks. \(output.path)")
    }
}
