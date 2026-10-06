import AppKit
import ApplicationServices
import Foundation
import SwiftUI

@MainActor private final class WeeklyLayoutFixtureWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override var backingScaleFactor: CGFloat { 2 }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor private final class WeeklyLayoutReminders: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .undetermined }
    func requestAuthorization() async throws -> Bool { false }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}

/// Reads public accessibility selectors only inside this process's fixture.
@MainActor private struct WeeklyLayoutAX {
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
        [value("accessibilityLabel"), value("accessibilityTitle"), value("accessibilityValue"),
         attribute("AXTitle"), attribute("AXDescription"), attribute("AXValue")]
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

/// Production weekly columns and empty states with fictional records, an isolated archive,
/// disabled link previews, and clipboard implementations that fail if called.
@main @MainActor private final class WeeklyLayoutTests: NSObject, NSApplicationDelegate {
    private static var checks = 0
    private static var reports: [[String: Any]] = []
    private static var diagnosticOutput: URL?
    private var result: Int32 = 0

    static func main() {
        let application = NSApplication.shared
        let delegate = WeeklyLayoutTests()
        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
        exit(delegate.result)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await Self.run() }
            catch { result = 1; fputs("Weekly layout QA failed: \(error)\n", stderr) }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "WeeklyLayoutTests", code: checks, userInfo: [NSLocalizedDescriptionKey: message])
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
    private static func nodes(_ view: NSView) -> [WeeklyLayoutAX] {
        var result: [WeeklyLayoutAX] = [], seen = Set<ObjectIdentifier>()
        func visit(_ candidate: Any, depth: Int) {
            guard depth < 60, let object = candidate as? NSObject,
                  seen.insert(ObjectIdentifier(object)).inserted else { return }
            let node = WeeklyLayoutAX(object: object)
            result.append(node)
            node.children.forEach { visit($0, depth: depth + 1) }
        }
        visit(view, depth: 0)
        NSAccessibility.unignoredChildren(from: [view]).forEach { visit($0, depth: 0) }
        return result
    }

    private static func withWeek(state: AppState, width: CGFloat, zoom: CGFloat, dark: Bool,
                                 body: (NSView, NSWindow) async throws -> Void) async throws {
        let size = CGSize(width: width, height: 960)
        let host = NSHostingView(rootView: WeeklyScreen(state: state)
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
        let window = WeeklyLayoutFixtureWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: width, height: size.height),
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
                   "Weekly fixture remains offscreen without taking focus")
        try expect(abs(host.bounds.width - width) < 1, "Native fixture keeps its requested width")
        try await body(host, window)
    }

    private static func snapshot(_ view: NSView, to url: URL) throws {
        let rect = view.bounds
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(rect.width * 2),
            pixelsHigh: Int(rect.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw failure("Cannot allocate native weekly bitmap")
        }
        bitmap.size = rect.size
        view.cacheDisplay(in: rect, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw failure("Cannot encode weekly PNG") }
        try png.write(to: url, options: .atomic)
    }

    private static func checkColumns(_ view: NSView, window: NSWindow, state: AppState,
                                     context: String, captures: [Capture]) throws -> [String: Any] {
        let all = nodes(view)
        let viewport = window.convertToScreen(view.convert(view.bounds, to: nil))
        // Retain a bounded diagnostic beside the already-saved PNG, including
        // when an assertion interrupts the first fixture before its report.
        if let diagnosticOutput {
            let diagnostic: [String: Any] = ["context": context, "viewport": NSStringFromRect(viewport),
                "totalNodes": all.count, "nodes": all.filter { $0.identifier != nil || !$0.label.isEmpty }.prefix(600).map {
                    ["identifier": $0.identifier ?? "", "label": String($0.label.prefix(240)),
                     "class": NSStringFromClass(type(of: $0.object)), "frame": NSStringFromRect($0.frame)]
                }]
            try JSONSerialization.data(withJSONObject: diagnostic, options: [.prettyPrinted, .sortedKeys])
                .write(to: diagnosticOutput.appendingPathComponent("week-\(context).ax.json"), options: .atomic)
        }
        var headers: [String: NSRect] = [:]
        var headerIdentifierFallbacks: [String] = []
        for day in state.weeklyVisibleDays {
            let key = CaptureCalendar.dayString(day)
            let headerLabel = "\(day.formatted(date: .complete, time: .omitted)), \(state.captures(for: day).count) captures, open Daily"
            // Parent accessibility identifiers may be inherited by SwiftUI's
            // virtual children on some macOS builds; the full date/action
            // label independently identifies exactly this real day button.
            let matchingHeaders = all.filter { $0.label == headerLabel && $0.frame.width > 0 }
            guard let header = matchingHeaders.first(where: { $0.identifier == "weekly-day-" + key }) ?? matchingHeaders.first else {
                throw failure("\(context): Missing rendered day header \(key)")
            }
            if header.identifier != "weekly-day-" + key { headerIdentifierFallbacks.append(key) }
            headers[key] = header.frame
            try expect(viewport.insetBy(dx: -1, dy: -1).contains(header.frame),
                       "\(context): Entire \(key) day header is visible: \(header.frame), viewport \(viewport)")
        }
        try expect(headers.count == state.weeklyVisibleDays.count, "\(context): Every visible day has a rendered header")
        for day in state.weeklyDays where !state.weeklyVisibleDays.contains(day) {
            let key = CaptureCalendar.dayString(day)
            let headerLabel = "\(day.formatted(date: .complete, time: .omitted)), 0 captures, open Daily"
            try expect(!all.contains { $0.identifier == "weekly-day-" + key || $0.label == headerLabel },
                       "\(context): Empty selected day \(key) has no rendered header")
        }
        let ordered = state.weeklyVisibleDays.compactMap { headers[CaptureCalendar.dayString($0)] }
        try expect(zip(ordered, ordered.dropFirst()).allSatisfy { $0.0.maxX <= $0.1.minX + 1 },
                   "\(context): Populated chronological day columns do not overlap")
        try expect(ordered.allSatisfy { abs($0.minY - ordered[0].minY) < 1 },
                   "\(context): Every day header stays in the same visible row")
        try expect(all.contains { $0.identifier == "weekly-columns" }, "\(context): The real weekly column container renders")

        // The same IDs belong to actual buttons and receipt metadata in both
        // ordinary cards and expanded collections. Inspect horizontal bounds
        // even for cards lower in a vertically scrollable day.
        let prefixes = ["weekly-card-", "capture-copy-", "capture-trash-", "capture-more-",
                        "capture-convert-to-task-", "capture-task-status-", "capture-receipt-time-",
                        "capture-receipt-category-"]
        var checkedControls = 0
        for capture in captures {
            guard let column = headers[capture.captureDay] else { continue }
            for prefix in prefixes {
                let identifier = prefix + capture.id.uuidString
                for node in all where node.identifier == identifier && node.frame.width > 0 && node.frame.height > 0 {
                    let frame = node.frame
                    try expect(frame.minX >= column.minX - 1 && frame.maxX <= column.maxX + 1,
                               "\(context): \(identifier) fits its date column: control \(frame), column \(column)")
                    checkedControls += 1
                }
            }
        }
        if !captures.isEmpty {
            try expect(checkedControls >= state.weeklyVisibleDays.count,
                       "\(context): Native inspection found real controls across the populated date columns")
        }
        for node in all where node.label == "Project" && node.frame.width > 0 && node.frame.height > 0 {
            let frame = node.frame
            try expect(ordered.contains { frame.minX >= $0.minX - 1 && frame.maxX <= $0.maxX + 1 },
                       "\(context): Long project label fits one date column: \(frame)")
        }
        let scrolls = nativeViews(view).compactMap { $0 as? NSScrollView }
        for scroll in scrolls {
            guard let document = scroll.documentView, scroll.contentView.bounds.width > 0 else { continue }
            try expect(document.bounds.width <= scroll.contentView.bounds.width + 1,
                       "\(context): Day content needs no horizontal scrolling: document \(document.bounds), viewport \(scroll.contentView.bounds)")
        }
        return ["context": context, "selectedDays": state.weeklyDays.map { CaptureCalendar.dayString($0) },
                "days": state.weeklyVisibleDays.map { CaptureCalendar.dayString($0) },
                "headers": ordered.map(NSStringFromRect), "checkedCardElements": checkedControls,
                "nativeScrollViews": scrolls.count, "headerIdentifierFallbacks": headerIdentifierFallbacks]
    }

    private static func checkEmptyState(_ view: NSView, state: AppState, title: String,
                                       context: String) throws {
        let all = nodes(view)
        try expect(all.contains { $0.identifier == "weekly-empty-state" },
                   "\(context): A single weekly empty-state container renders")
        try expect(all.contains { $0.label == title }, "\(context): Empty state explains the selected captures or filter")
        try expect(!all.contains { $0.identifier == "weekly-columns" || $0.identifier?.hasPrefix("weekly-day-") == true },
                   "\(context): No empty date columns or day headers render")
        reports.append(["context": context, "selectedDays": state.weeklyDays.count,
                        "visibleDays": state.weeklyVisibleDays.count, "emptyStateTitle": title])
    }

    private static func fixturePNG() throws -> Data {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 120, pixelsHigh: 90,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { throw failure("Fixture image allocation") }
        for y in 0..<90 {
            for x in 0..<120 {
                bitmap.setColor(NSColor(calibratedRed: CGFloat(x) / 120, green: 0.65,
                                        blue: CGFloat(y) / 90, alpha: 1), atX: x, y: y)
            }
        }
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw failure("Fixture image encoding") }
        return data
    }

    private static func immutableSnapshots(_ captures: [Capture]) throws -> [UUID: Data] {
        try Dictionary(uniqueKeysWithValues: captures.map { capture in
            var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(CaptureSnapshot(capture))) as! [String: Any]
            object.removeValue(forKey: "isMinimized"); object.removeValue(forKey: "updatedAt")
            return (capture.id, try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
        })
    }

    private static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinWeeklyLayout-\(UUID().uuidString)")
        let suite = "DaBinWeeklyLayout.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: PreviewService.linkPreviewPreference)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root)
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date()).addingTimeInterval(12 * 3_600)
        let days = (-6...0).map { calendar.date(byAdding: .day, value: $0, to: end)! }
        let note = try store.capture(text: "Fictional weekly planning note with a long readable title", at: days[0])[0]
        note.comment = "A locally generated fixture comment that wraps inside the narrow weekly card."
        let png = try fixturePNG()
        let image = try await store.importData(png, filename: "Fictional color reference.png", at: days[1])
        if let thumbnail = await PreviewService.writeThumbnail(png, root: root, id: image.id) {
            image.thumbnailRelativePath = thumbnail; image.previewState = "ready"
        }
        _ = try await store.importData(Data("Fictional local reference bytes".utf8), filename: "Fictional reference document.bin", at: days[2])
        var batch: [Capture] = []
        for index in 0..<2 {
            batch.append(try await store.importData(Data("Fictional batch original \(index)".utf8),
                filename: "Fictional grouped reference \(index).bin", at: days[3]))
        }
        var automatic: [Capture] = []
        for index in 0..<4 {
            automatic += try store.capture(text: "Fictional automatic action \(index) with its preserved original text",
                at: days[4].addingTimeInterval(Double(index * 120)),
                receipt: .automatic(.automaticClipboard, actionID: UUID(), sourceApplicationName: "Fictional Source Application"))
        }
        let projectCapture = try store.capture(text: "Fictional project capture whose title can wrap to several lines", at: days[5])[0]
        let task = try store.createTask(text: "Fictional task with a long title and focus controls", at: days[6])
        task.comment = "Task comment remains readable in the seven day view."
        try store.save(captures: [note, image, task])
        let previews = PreviewService(store: store, defaults: defaults)
        let auto = AutoCaptureService(settings: AutoCaptureSettings(defaults: defaults), input: InputService(store: store),
            pasteboardProvider: { fatalError("Weekly layout QA must not read the clipboard") }, sourceApplicationProvider: { nil })
        let state = AppState(store: store, previews: previews,
            reminders: ReminderService(store: store, client: WeeklyLayoutReminders()), autoCapture: auto,
            captureClipboard: CaptureClipboardService(writer: { _ in fatalError("Weekly layout QA must not write the clipboard") }),
            folderOpener: { _ in fatalError("Weekly layout QA must not open other applications") })
        defer {
            previews.shutdown(); auto.shutdown(); state.focusSessions.shutdown()
            state.shutdownNotificationPresentation(); store.cancelArchiveRepair()
        }
        let projectName = "Fictional reference project with a deliberately long name"
        try state.workspace.createProject(name: projectName, colorHex: "377EAF")
        try store.setOrganization(projectCapture, pinned: false, projectName: projectName)
        state.selectedDay = end; state.weekEndingDay = end; state.route = .weekly
        guard let hour = HourlyCaptureFeed.cards(from: automatic, filter: .all).compactMap({
            if case .automaticHour(let group) = $0 { return group }; return nil
        }).first else { throw failure("Fictional automatic actions did not form an hour") }
        try expect(state.weeklyDays.count == 7 && state.weeklyVisibleDays.count == 7,
                   "Populated fixture has activity on exactly seven selected dates")
        let baseline = try immutableSnapshots(store.captures)
        let output = ProcessInfo.processInfo.environment["DABIN_WEEK_LAYOUT_QA_OUTPUT"].map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/qa/week-layout")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        diagnosticOutput = output
        for dark in [false, true] {
            for width in [CGFloat(1024), 1280, 1440, 1920] {
                for zoom in [CGFloat(0.75), 1, 2] {
                    for capture in batch { try store.setMinimized(capture, minimized: true) }
                    if state.isHourlyGroupExpanded(hour.id) { state.toggleHourlyGroup(hour.id) }
                    state.weeklyColumnViewports = [:]
                    let context = "\(Int(width))-zoom\(Int(zoom * 100))-\(dark ? "dark" : "light")"
                    try await withWeek(state: state, width: width, zoom: zoom, dark: dark) { view, window in
                        try snapshot(view, to: output.appendingPathComponent("week-\(context)-collapsed@2x.png"))
                        reports.append(try checkColumns(view, window: window, state: state,
                            context: context + "-collapsed", captures: store.captures))
                        state.toggleHourlyGroup(hour.id)
                        state.toggleMinimized(batch)
                        await settle(view)
                        try snapshot(view, to: output.appendingPathComponent("week-\(context)-expanded@2x.png"))
                        reports.append(try checkColumns(view, window: window, state: state,
                            context: context + "-expanded", captures: store.captures))
                        let visible = nodes(view)
                        for collection in [automatic, batch] {
                            let identifiers = Set(collection.map { "weekly-card-" + $0.id.uuidString })
                            try expect(visible.contains { $0.identifier.map(identifiers.contains) ?? false },
                                       "\(context): Expanded collection exposes a real child capture card")
                        }
                    }
                }
            }
        }
        // Restoring or manually narrowing the window keeps usable card hit
        // targets. Only this narrow presentation may scroll horizontally.
        state.weeklyColumnViewports = [:]
        try await withWeek(state: state, width: 420, zoom: 2, dark: false) { view, window in
            try snapshot(view, to: output.appendingPathComponent("week-narrow-420-zoom200@2x.png"))
            let scrolls = nativeViews(view).compactMap { $0 as? NSScrollView }
            guard let horizontal = scrolls.first(where: {
                guard let document = $0.documentView else { return false }
                return document.bounds.width > $0.contentView.bounds.width + 1
            }), let document = horizontal.documentView else {
                throw failure("Restored 420-point week needs a real horizontal scroll viewport")
            }
            let overflow = document.bounds.width - horizontal.contentView.bounds.width
            try expect(overflow > 400, "Narrow week preserves column widths through native horizontal overflow")
            var headers: [NSRect] = []
            var checkedControls = 0
            let prefixes = ["weekly-card-", "capture-copy-", "capture-trash-", "capture-more-", "capture-task-status-"]
            // Inspect each day while it is visible. Native AX may omit fully
            // clipped descendants, so use real scrolling instead of requiring
            // an offscreen accessibility element to invent a visible frame.
            for (index, day) in state.weeklyDays.enumerated() {
                let x = overflow * CGFloat(index) / CGFloat(max(1, state.weeklyDays.count - 1))
                horizontal.contentView.scroll(to: CGPoint(x: x, y: horizontal.contentView.bounds.minY))
                horizontal.reflectScrolledClipView(horizontal.contentView)
                await settle(view)
                let all = nodes(view)
                let key = CaptureCalendar.dayString(day)
                let label = "\(day.formatted(date: .complete, time: .omitted)), \(state.captures(for: day).count) captures, open Daily"
                let matches = all.filter { $0.label == label && $0.frame.width > 0 }
                guard let header = matches.first(where: { $0.identifier == "weekly-day-" + key }) ?? matches.first else {
                    throw failure("Narrow week cannot scroll to selected day \(key)")
                }
                let contentFrame = document.convert(window.convertFromScreen(header.frame), from: nil)
                headers.append(contentFrame)
                try expect(document.bounds.insetBy(dx: -1, dy: -1).contains(contentFrame),
                           "Narrow week retains \(key)'s complete header in its scroll content")
                try expect(header.frame.width >= 130, "Restored week retains a usable day column for \(key)")
                let clipFrame = window.convertToScreen(horizontal.contentView.convert(horizontal.contentView.bounds, to: nil))
                try expect(clipFrame.insetBy(dx: -1, dy: -1).contains(header.frame),
                           "Native horizontal scrolling brings the whole \(key) header into view")
                var dayControls = 0
                for capture in state.allCaptures(for: day) {
                    for prefix in prefixes {
                        for node in all where node.identifier == prefix + capture.id.uuidString
                            && node.frame.width > 0 && node.frame.height > 0 {
                            try expect(node.frame.minX >= header.frame.minX - 1 && node.frame.maxX <= header.frame.maxX + 1,
                                       "Restored \(key) card/control fits its own column after horizontal scrolling: \(node.identifier ?? ""), \(node.frame)")
                            dayControls += 1
                        }
                    }
                }
                try expect(dayControls > 0, "Narrow \(key) column exposes its actual card controls")
                checkedControls += dayControls
            }
            try expect(headers.count == 7 && zip(headers, headers.dropFirst()).allSatisfy { $0.0.maxX <= $0.1.minX + 1 },
                       "All seven selected days remain in chronological, nonoverlapping scroll content")
            reports.append(["context": "narrow-420-zoom200", "headersInScrollContent": headers.map(NSStringFromRect),
                            "horizontalOverflowPoints": overflow, "checkedCardElements": checkedControls])
        }
        // Filters remove days without matching cards while preserving the
        // selected calendar range. Inspect the actual remaining native columns.
        for (filter, expectedIndices) in [(CaptureFilter.files, [2, 3]), (.media, [1])] {
            state.filter = filter
            state.weeklyColumnViewports = [:]
            try expect(state.weeklyDays.count == 7
                       && state.weeklyVisibleDays == expectedIndices.map { calendar.startOfDay(for: days[$0]) },
                       "\(filter.title) shows only its populated dates from the selected week")
            try await withWeek(state: state, width: 1024, zoom: 1, dark: false) { view, window in
                let context = "filtered-" + filter.rawValue
                try snapshot(view, to: output.appendingPathComponent("week-\(context)@2x.png"))
                reports.append(try checkColumns(view, window: window, state: state,
                    context: context, captures: store.captures.filter(filter.includes)))
            }
        }
        state.filter = .links
        try expect(state.weeklyDays.count == 7 && state.weeklyActiveDays.count == 7
                   && state.weeklyVisibleDays.isEmpty,
                   "A nonmatching filter hides every column without changing calendar or activity dates")
        try await withWeek(state: state, width: 1024, zoom: 1, dark: false) { view, _ in
            try checkEmptyState(view, state: state, title: "No links in these days", context: "filtered-empty")
            try snapshot(view, to: output.appendingPathComponent("week-filtered-empty@2x.png"))
        }

        // No record belongs to these earlier dates; open task carryover cannot
        // populate them. Render one clear empty state with no blank day columns.
        state.filter = .all
        state.weekEndingDay = calendar.date(byAdding: .day, value: -20, to: end)!
        state.weeklyColumnViewports = [:]
        try expect(state.weeklyDays.count == 7 && state.weeklyActiveDays.isEmpty
                   && state.weeklyVisibleDays.isEmpty, "Empty-week fixture retains selection without visible days")
        for dark in [false, true] {
            try await withWeek(state: state, width: 1024, zoom: 2, dark: dark) { view, _ in
                let context = "empty-week-" + (dark ? "dark" : "light")
                try checkEmptyState(view, state: state, title: "No captures in these days", context: context)
                try snapshot(view, to: output.appendingPathComponent("week-\(context)@2x.png"))
            }
        }
        try expect(try immutableSnapshots(store.captures) == baseline,
                   "Layout and collection expansion preserve all capture content and metadata")
        let report: [String: Any] = ["checks": checks, "fixtures": reports,
            "renderMethod": "Actual WeeklyScreen in offscreen non-key native 2x NSHostingViews",
            "widths": [1024, 1280, 1440, 1920], "zoomPercentages": [75, 100, 200],
            "restoredWindowFixture": ["width": 420, "zoomPercentage": 200],
            "scope": "Fictional local records only; no clipboard, network, personal archive or external applications"]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("weekly-layout-report.json"), options: .atomic)
        print("PASS: \(checks) native weekly layout, bounds, expanded collection and data preservation checks. \(output.path)")
    }
}
