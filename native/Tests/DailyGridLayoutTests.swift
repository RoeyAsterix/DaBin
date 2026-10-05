import AppKit
import ApplicationServices
import Foundation
import SwiftUI

@MainActor private final class DailyGridLayoutFixtureWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override var backingScaleFactor: CGFloat { 2 }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor private final class DailyGridLayoutReminders: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .undetermined }
    func requestAuthorization() async throws -> Bool { false }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}

/// Reads public accessibility selectors only inside this process's fixture.
@MainActor private struct DailyGridLayoutAX {
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
    var frame: NSRect {
        let selector = NSSelectorFromString("accessibilityFrame")
        guard object.responds(to: selector) else { return .zero }
        typealias Getter = @convention(c) (AnyObject, Selector) -> NSRect
        return unsafeBitCast(object.method(for: selector), to: Getter.self)(object, selector)
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

/// Actual DailyScreen rendered with an isolated fictional archive. This process
/// never reads personal captures, clipboard contents, or remote link previews.
@main @MainActor private final class DailyGridLayoutTests: NSObject, NSApplicationDelegate {
    private static var checks = 0
    private static var reports: [[String: Any]] = []
    private static var diagnosticOutput: URL?
    private var result: Int32 = 0

    static func main() {
        let application = NSApplication.shared
        let delegate = DailyGridLayoutTests()
        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
        exit(delegate.result)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await Self.run() }
            catch { result = 1; fputs("Daily grid layout QA failed: \(error)\n", stderr) }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "DailyGridLayoutTests", code: checks, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        guard try condition() else { throw failure(message) }
    }
    private static func settle(_ view: NSView) async {
        for _ in 0..<6 { view.layoutSubtreeIfNeeded(); try? await Task.sleep(for: .milliseconds(35)) }
    }
    private static func nativeViews(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { nativeViews($0) }
    }
    private static func nodes(_ view: NSView) -> [DailyGridLayoutAX] {
        var result: [DailyGridLayoutAX] = [], seen = Set<ObjectIdentifier>()
        func visit(_ candidate: Any, depth: Int) {
            guard depth < 60, let object = candidate as? NSObject,
                  seen.insert(ObjectIdentifier(object)).inserted else { return }
            let node = DailyGridLayoutAX(object: object)
            result.append(node)
            node.children.forEach { visit($0, depth: depth + 1) }
        }
        visit(view, depth: 0)
        NSAccessibility.unignoredChildren(from: [view]).forEach { visit($0, depth: 0) }
        return result
    }

    private static func withDay(state: AppState, width: CGFloat, zoom: CGFloat, dark: Bool,
                                 body: (NSView, NSWindow) async throws -> Void) async throws {
        let size = CGSize(width: width, height: 960)
        let host = NSHostingView(rootView: DailyScreen(state: state)
            .environment(\.workspaceZoom, WorkspaceZoomLayout(factor: zoom))
            .environment(\.displayScale, 2)
            .environment(\.daBinTooltipsEnabled, false)
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
            .preferredColorScheme(dark ? .dark : .light)
            .background(Palette.background))
        host.frame = NSRect(origin: .zero, size: size)
        host.sizingOptions = []; host.autoresizingMask = [.width, .height]
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.appearance = appearance
        let window = DailyGridLayoutFixtureWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: width, height: size.height),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.appearance = appearance; window.contentView = host
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        window.orderBack(nil)
        window.setFrame(NSRect(x: -20_000, y: -20_000, width: width, height: size.height), display: true)
        await settle(host)
        let activation = await Task.detached {
            let process = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            AXUIElementSetMessagingTimeout(process, 3)
            var windows: CFTypeRef?
            return AXUIElementCopyAttributeValue(process, kAXWindowsAttribute as CFString, &windows)
        }.value
        try expect(activation == .success, "Only the fixture process's accessibility tree initializes")
        await settle(host)
        try expect(window.frame.maxX < 0 && !window.isKeyWindow && !window.isMainWindow,
                   "Daily fixture remains offscreen without taking focus")
        try expect(abs(host.bounds.width - width) < 1, "Native fixture keeps its requested width")
        try await body(host, window)
    }

    private static func snapshot(_ view: NSView, to url: URL) throws {
        let rect = view.bounds
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(rect.width * 2),
            pixelsHigh: Int(rect.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw failure("Cannot allocate native daily grid bitmap")
        }
        bitmap.size = rect.size
        view.cacheDisplay(in: rect, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw failure("Cannot encode daily grid PNG") }
        try png.write(to: url, options: .atomic)
    }

    private static func feed(_ state: AppState) -> [CaptureFeedCard] {
        HourlyCaptureFeed.cards(from: state.receiptCaptures(for: state.selectedDay), filter: state.filter)
    }

    private static func primary(_ card: CaptureFeedCard) -> Capture {
        switch card {
        case .capture(let group): return group.primary
        case .automaticHour(let group): return group.captures[0]
        }
    }

    private static func cardFrame(_ card: CaptureFeedCard, in all: [DailyGridLayoutAX]) -> NSRect? {
        let identifier = "daily-card-" + primary(card).id.uuidString
        // SwiftUI can inherit a containing element's identifier onto a virtual
        // child. The largest matching frame is the real containing card.
        return all.filter { $0.identifier == identifier && $0.frame.width > 0 && $0.frame.height > 0 }
            .map(\.frame).max { $0.width * $0.height < $1.width * $1.height }
    }

    @discardableResult
    private static func checkGrid(_ view: NSView, window: NSWindow, state: AppState,
                                  context: String, expectedColumns: Int? = nil) throws -> [String: Any] {
        let all = nodes(view), cards = feed(state)
        let viewport = window.convertToScreen(view.convert(view.bounds, to: nil))
        if let diagnosticOutput {
            let diagnostic: [String: Any] = ["context": context, "viewport": NSStringFromRect(viewport),
                "nodes": all.filter { $0.identifier != nil || !$0.label.isEmpty }.prefix(500).map {
                    ["identifier": $0.identifier ?? "", "label": String($0.label.prefix(200)),
                     "frame": NSStringFromRect($0.frame), "class": NSStringFromClass(type(of: $0.object))]
                }]
            try JSONSerialization.data(withJSONObject: diagnostic, options: [.prettyPrinted, .sortedKeys])
                .write(to: diagnosticOutput.appendingPathComponent("day-\(context).ax.json"), options: .atomic)
        }
        try expect(all.contains { $0.identifier == "daily-grid" }, "\(context): Real daily grid has an accessible container")
        guard let first = cards.first, let firstFrame = cardFrame(first, in: all) else {
            throw failure("\(context): Newest capture renders as a real grid card")
        }
        // LazyVGrid exposes estimated AX placeholders for rows it has not
        // laid out yet. Those offscreen estimates can share the same origin;
        // only real frames intersecting this viewport establish visual order.
        let rendered = cards.compactMap { card -> (CaptureFeedCard, NSRect)? in
            guard let frame = cardFrame(card, in: all), frame.intersects(viewport) else { return nil }
            return (card, frame)
        }
        let row = rendered.filter { abs($0.1.maxY - firstFrame.maxY) < 2 }
        if let expectedColumns {
            try expect(row.count == min(cards.count, expectedColumns),
                       "\(context): Expected \(expectedColumns) top-aligned cards in first row, found \(row.count)")
        }
        try expect(!row.isEmpty, "\(context): At least one card occupies the visible first row")
        if view.bounds.width >= 800 {
            try expect(row.count >= 2, "\(context): Expanded Daily uses side-by-side cards")
        } else if view.bounds.width <= 420 {
            try expect(row.count == 1, "\(context): Compact Daily stays readable as one column")
        }
        try expect(row.map { $0.0.id } == Array(cards.prefix(row.count)).map(\.id),
                   "\(context): Newest-first feed order follows the first row without regrouping content")
        try expect(zip(row, row.dropFirst()).allSatisfy { $0.0.1.maxX <= $0.1.1.minX - 1 },
                   "\(context): Adjacent cards are separated and never overlap")
        try expect(row.allSatisfy { abs($0.1.width - firstFrame.width) < 2 },
                   "\(context): Responsive columns have equal widths")
        try expect(row.allSatisfy { $0.1.width >= 270 || view.bounds.width < 350 },
                   "\(context): Cards retain readable widths")
        for (_, frame) in rendered {
            try expect(frame.minX >= viewport.minX - 1 && frame.maxX <= viewport.maxX + 1,
                       "\(context): Rendered card stays in the horizontal viewport: \(frame)")
        }
        // Native frames are bottom-origin. The next visual row must sit below
        // the preceding row, while every card within a row shares its top edge.
        for index in 1..<rendered.count {
            let previous = rendered[index - 1].1, current = rendered[index].1
            try expect(abs(previous.maxY - current.maxY) < 2
                ? current.minX > previous.minX
                : current.maxY < previous.maxY,
                "\(context): Visual card order follows the chronological feed from left to right, then down")
        }
        let prefixes = ["capture-copy-", "capture-trash-", "capture-more-", "capture-collapse-",
                        "capture-task-status-", "capture-receipt-time-", "capture-receipt-category-"]
        var checkedControls = 0
        for (card, frame) in rendered {
            for capture in card.captures {
                for prefix in prefixes {
                    for node in all where node.identifier == prefix + capture.id.uuidString
                        && node.frame.width > 0 && node.frame.height > 0 {
                        try expect(node.frame.minX >= frame.minX - 1 && node.frame.maxX <= frame.maxX + 1,
                                   "\(context): \(prefix) control fits its own card: \(node.frame), card \(frame)")
                        checkedControls += 1
                    }
                }
            }
        }
        try expect(checkedControls >= 2, "\(context): Real visible copy, remove, or task controls are inspected")
        let scrolls = nativeViews(view).compactMap { $0 as? NSScrollView }
        try expect(!scrolls.isEmpty, "\(context): Daily retains a native vertical scroll view")
        for scroll in scrolls {
            guard let document = scroll.documentView, scroll.contentView.bounds.width > 0 else { continue }
            try expect(document.bounds.width <= scroll.contentView.bounds.width + 1,
                       "\(context): Grid never needs horizontal scrolling")
        }
        return ["context": context, "columns": row.count, "cardWidth": firstFrame.width,
                "visibleCardFrames": rendered.map { NSStringFromRect($0.1) },
                "firstRowIDs": row.map { primary($0.0).id.uuidString }, "checkedCardElements": checkedControls]
    }

    private static func fixturePNG() throws -> Data {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 180, pixelsHigh: 120,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { throw failure("Fixture image allocation") }
        for y in 0..<120 {
            for x in 0..<180 {
                bitmap.setColor(NSColor(calibratedRed: 0.3 + CGFloat(x) / 360, green: 0.48,
                                        blue: 0.45 + CGFloat(y) / 240, alpha: 1), atX: x, y: y)
            }
        }
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw failure("Fixture image encoding") }
        return data
    }

    private static func snapshots(_ captures: [Capture]) throws -> [UUID: Data] {
        try Dictionary(uniqueKeysWithValues: captures.map { capture in
            var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(CaptureSnapshot(capture))) as! [String: Any]
            // Deliberately exercising collapse controls changes presentation only.
            object.removeValue(forKey: "isMinimized"); object.removeValue(forKey: "updatedAt")
            return (capture.id, try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
        })
    }

    private static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinDailyGridLayout-\(UUID().uuidString)")
        let suite = "DaBinDailyGridLayout.\(UUID().uuidString)"
        // Keep all preference writes inside this fixture's isolated suite.
        let fixtureDefaults = UserDefaults(suiteName: suite)!
        fixtureDefaults.set(false, forKey: PreviewService.linkPreviewPreference)
        defer { fixtureDefaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root)
        let day = Calendar.current.startOfDay(for: Date()).addingTimeInterval(9 * 3_600)
        for index in 0..<6 {
            _ = try store.capture(text: "Fictional work note \(index): keep the original source and continue after a break.",
                                  at: day.addingTimeInterval(Double(index * 120)))
        }
        var automatic: [Capture] = []
        for index in 0..<4 {
            automatic += try store.capture(text: "Fictional automatic capture \(index) — locally preserved words.",
                at: day.addingTimeInterval(3_600 + Double(index * 60)),
                receipt: .automatic(.automaticClipboard, actionID: UUID(), sourceApplicationName: "Fictional Editor"))
        }
        var batch: [Capture] = []
        for index in 0..<2 {
            batch.append(try await store.importData(Data("Fictional reference bytes \(index)".utf8),
                filename: "Fictional reference document with a long filename \(index).bin",
                at: day.addingTimeInterval(7_200)))
        }
        let note = try store.capture(text: "Fictional client feedback — a deliberately long title with multilingual text שלום 世界 and a concrete next step",
                                     at: day.addingTimeInterval(7_500))[0]
        note.comment = "Confirm the next review with the fictional client; this text remains readable and draggable."
        let png = try fixturePNG()
        let image = try await store.importData(png, filename: "Fictional color reference.png", at: day.addingTimeInterval(7_800))
        if let thumbnail = await PreviewService.writeThumbnail(png, root: root, id: image.id) {
            image.thumbnailRelativePath = thumbnail; image.previewState = "ready"
        }
        let task = try store.createTask(text: "Review fictional client feedback and send a clear follow-up", at: day.addingTimeInterval(8_100))
        task.comment = "Keep the capture and its controls together while the window changes size."
        try store.save(captures: [note, image, task])
        let previews = PreviewService(store: store, defaults: fixtureDefaults)
        let auto = AutoCaptureService(settings: AutoCaptureSettings(defaults: fixtureDefaults), input: InputService(store: store),
            pasteboardProvider: { fatalError("Daily grid QA must not read the clipboard") }, sourceApplicationProvider: { nil })
        let state = AppState(store: store, previews: previews,
            reminders: ReminderService(store: store, client: DailyGridLayoutReminders()), autoCapture: auto,
            captureClipboard: CaptureClipboardService(writer: { _ in fatalError("Daily grid QA must not write the clipboard") }),
            folderOpener: { _ in fatalError("Daily grid QA must not open other applications") })
        defer {
            previews.shutdown(); auto.shutdown(); state.focusSessions.shutdown()
            state.shutdownNotificationPresentation(); store.cancelArchiveRepair()
        }
        let project = "Fictional client project with a long descriptive name"
        try state.workspace.createProject(name: project, colorHex: "7867A8")
        for capture in [note, image, task] { try store.setOrganization(capture, pinned: false, projectName: project) }
        state.openDaily(); state.selectedDay = day
        guard let hour = HourlyCaptureFeed.cards(from: automatic, filter: .all).compactMap({
            if case .automaticHour(let group) = $0 { return group }; return nil
        }).first else { throw failure("Fictional automatic actions did not form an hour") }
        for capture in batch { try store.setMinimized(capture, minimized: true) }
        let baseline = try snapshots(store.captures)
        let output = ProcessInfo.processInfo.environment["DABIN_DAY_LAYOUT_QA_OUTPUT"].map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/qa/day-grid")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        diagnosticOutput = output
        let fixtures: [(CGFloat, CGFloat, Bool, Int?, Bool)] = [
            (380, 1, true, 1, true), (380, 2, false, 1, false),
            (800, 0.75, false, 2, false), (800, 1, true, 2, false),
            (1024, 0.75, true, 3, false), (1024, 1, false, 3, true), (1024, 2, true, nil, false),
            (1440, 1, true, 4, false), (1440, 2, false, nil, true),
            (1920, 0.75, false, 5, false), (1920, 1, true, 5, true), (1920, 2, true, nil, false)
        ]
        for (width, zoom, dark, count, render) in fixtures {
            state.dailyScrollID = nil; state.workspaceViewport = nil
            let context = "\(Int(width))-zoom\(Int(zoom * 100))-\(dark ? "dark" : "light")"
            try await withDay(state: state, width: width, zoom: zoom, dark: dark) { view, window in
                if render { try snapshot(view, to: output.appendingPathComponent("day-\(context)@2x.png")) }
                reports.append(try checkGrid(view, window: window, state: state, context: context, expectedColumns: count))
            }
        }
        // Changing only the native window's width reflows the same mounted view.
        // The captured content, date, filter and card identities remain intact.
        state.dailyScrollID = nil; state.workspaceViewport = nil
        try await withDay(state: state, width: 380, zoom: 1, dark: false) { view, window in
            let ids = feed(state).map(\.id), selectedDay = state.selectedDay
            for (width, count) in [(CGFloat(1024), 3), (1440, 4), (800, 2), (1920, 5)] {
                window.setContentSize(CGSize(width: width, height: 960))
                await settle(view)
                reports.append(try checkGrid(view, window: window, state: state,
                    context: "continuous-resize-\(Int(width))", expectedColumns: count))
                try expect(feed(state).map(\.id) == ids && state.selectedDay == selectedDay && state.filter == .all,
                           "Resize preserves the selected date, filter and stable capture identities")
            }
            state.toggleHourlyGroup(hour.id); state.toggleMinimized(batch)
            await settle(view)
            reports.append(try checkGrid(view, window: window, state: state, context: "expanded-collections", expectedColumns: 5))
            let expandedNodes = nodes(view)
            for collection in [automatic, batch] {
                try expect(collection.contains { capture in
                    expandedNodes.contains {
                        $0.identifier == "capture-trash-" + capture.id.uuidString
                            || $0.label.contains(capture.title) && $0.frame.width > 0
                    }
                }, "Expanded collection exposes an individual capture without escaping its grid column")
                let renderedIDs = Set(feed(state).flatMap(\.captures).map(\.id))
                try expect(Set(collection.map(\.id)).isSubset(of: renderedIDs),
                           "All expanded collection members remain in the feed, including those below the viewport")
            }
            state.filter = .text; state.dailyScrollID = nil; state.workspaceViewport = nil
            await settle(view)
            reports.append(try checkGrid(view, window: window, state: state, context: "text-filter", expectedColumns: 5))
            try expect(feed(state).flatMap(\.captures).allSatisfy { CaptureFilter.text.includes($0) },
                       "Text filtering preserves the existing capture-type behavior in the grid")
            state.filter = .all
            state.toggleHourlyGroup(hour.id); state.toggleMinimized(batch)
            await settle(view)
            try expect(feed(state).map(\.id) == ids, "Clearing the filter restores every original stable card")
        }
        // Details keep their existing history contract: returning restores the
        // selected date, filter and stable item anchor, not an old row number.
        state.filter = .text
        guard let anchorCard = feed(state).dropFirst().first else { throw failure("Daily scroll history fixture needs two cards") }
        let anchorCapture = primary(anchorCard)
        state.dailyScrollID = anchorCard.id
        let anchor = NavigationViewportAnchor(itemID: "capture:" + anchorCapture.id.uuidString, offset: 12)
        state.workspaceViewport = anchor
        state.openCapture(anchorCapture.id, focus: "comment")
        try expect(state.route == .detail && state.selectedCapture?.id == anchorCapture.id,
                   "A card still opens its capture detail page")
        state.back()
        try expect(state.route == .daily && state.filter == .text && state.dailyScrollID == anchorCard.id
            && state.workspaceViewport == anchor && Calendar.current.isDate(state.selectedDay, inSameDayAs: day),
                   "Returning from detail restores the day, filter and stable scroll anchor")
        try expect(try snapshots(store.captures) == baseline,
                   "Grid resizing, filters, collection expansion and detail return preserve capture content and metadata")
        let report: [String: Any] = ["checks": checks, "fixtures": reports,
            "renderMethod": "Actual DailyScreen in offscreen non-key native 2x NSHostingViews",
            "fixtureWidths": [380, 800, 1024, 1440, 1920], "zoomPercentages": [75, 100, 200],
            "scope": "Fictional local records only; no personal archive, clipboard, network or other applications"]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("daily-grid-layout-report.json"), options: .atomic)
        print("PASS: \(checks) native Daily grid, bounds, resizing, filter, history and data-preservation checks. \(output.path)")
    }
}
