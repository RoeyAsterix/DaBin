import AppKit
import ApplicationServices
import Foundation
import SwiftUI

@MainActor private final class TimestampReminderClient: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .undetermined }
    func requestAuthorization() async throws -> Bool { false }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}

/// Inspect only the public accessibility methods of our own fixture windows.
@MainActor private struct TimestampAXNode {
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
    var stringValue: String {
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
        var children: [Any] = []
        for name in ["accessibilityChildren", "accessibilityChildrenInNavigationOrder", "accessibilityContents"] {
            if let values = value(name) as? [Any] { children += values }
        }
        if let values = attribute("AXChildren") as? [Any] { children += values }
        if let view = object as? NSView { children += view.subviews }
        return children
    }
}

@MainActor private struct TimestampSearchCardFixture: View {
    @ObservedObject var state: AppState
    let item: SearchDateItem
    @FocusState private var selected: String?

    var body: some View {
        SearchResultCard(state: state, item: item, expanded: true, focus: $selected)
    }
}

/// No user archive, clipboard, global pointer events, external applications or
/// app activation. UI checks use offscreen production views with their real AX
/// geometry, including compact cards and the detail date navigation button.
@main @MainActor private final class CaptureTimestampPresentationTests: NSObject, NSApplicationDelegate {
    private static var checks = 0
    private var result = 0

    static func main() {
        let application = NSApplication.shared
        let delegate = CaptureTimestampPresentationTests()
        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
        exit(Int32(delegate.result))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await Self.run() }
            catch {
                result = 1
                fputs("Capture timestamp presentation QA failed: \(error)\n", stderr)
            }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }

    private static func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard value() else {
            throw NSError(domain: "CaptureTimestampPresentationTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private static func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    private static func nodes(_ view: NSView) -> [TimestampAXNode] {
        view.layoutSubtreeIfNeeded()
        var seen = Set<ObjectIdentifier>()
        var result: [TimestampAXNode] = []
        func visit(_ candidate: Any, depth: Int) {
            guard depth < 50, let object = candidate as? NSObject,
                  seen.insert(ObjectIdentifier(object)).inserted else { return }
            let node = TimestampAXNode(object: object)
            result.append(node)
            node.children.forEach { visit($0, depth: depth + 1) }
        }
        visit(view, depth: 0)
        NSAccessibility.unignoredChildren(from: [view]).forEach { visit($0, depth: 0) }
        return result
    }

    private static func settle(_ view: NSView) async {
        for _ in 0..<4 {
            view.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(35))
        }
    }

    private static func find(_ view: NSView, id: String) async throws -> TimestampAXNode {
        for _ in 0..<8 {
            if let node = nodes(view).first(where: { $0.identifier == id }) { return node }
            await settle(view)
        }
        throw NSError(domain: "CaptureTimestampPresentationTests", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Missing native timestamp \(id): \(nodes(view).map { $0.identifier ?? $0.label }.joined(separator: "; "))"])
    }

    private static func withView<V: View>(_ root: V, size: NSSize,
                                         body: (NSView, NSWindow) async throws -> Void) async throws {
        let hosting = NSHostingView(rootView: root.frame(width: size.width, height: size.height, alignment: .topLeading))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.wantsLayer = true
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        window.orderFront(nil)
        await settle(hosting)
        // SwiftUI's virtual AX tree materializes only after an own-process
        // hierarchy request. Leave the main actor free to answer that request.
        let activation = await Task.detached {
            let process = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            AXUIElementSetMessagingTimeout(process, 3)
            var windows: CFTypeRef?
            return AXUIElementCopyAttributeValue(process, kAXWindowsAttribute as CFString, &windows)
        }.value
        try expect(activation == .success, "Own-process timestamp accessibility initializes")
        await settle(hosting)
        try expect(window.frame.maxX < 0 && !window.isKeyWindow,
                   "Timestamp fixtures stay offscreen and non-key")
        try await body(hosting, window)
    }

    private static func assertReceipt(_ capture: Capture, in view: NSView, window: NSWindow,
                                      category: String, context: String, fontSize: CGFloat = 11) async throws -> CGFloat {
        let time = try await find(view, id: "capture-receipt-time-\(capture.id.uuidString)")
        let kind = try await find(view, id: "capture-receipt-category-\(capture.id.uuidString)")
        let receipt = captureReceiptText(capture)
        try expect(time.label == receipt, "\(context): full original capture date and clock are exposed")
        try expect(kind.label == category, "\(context): category remains alongside the receipt")
        let frames = [time.frame, kind.frame]
        try expect(frames.allSatisfy { $0.width > 0 && $0.height > 0 }, "\(context): timestamp and category are rendered")
        try expect(time.frame.maxX <= kind.frame.minX + 1,
                   "\(context): date and time are to the left of category without overlap: \(frames)")
        try expect(frames.allSatisfy { $0.minX >= window.frame.minX - 1 && $0.maxX <= window.frame.maxX + 1
            && $0.minY >= window.frame.minY - 1 && $0.maxY <= window.frame.maxY + 1 },
                   "\(context): timestamp and category fit inside the visible compact fixture: \(frames)")
        // AX exposes full strings even when Text visually truncates. Comparing
        // the real frame against the complete string's wrapped glyph height
        // catches a clipped one-line date or a two-line receipt that needs more.
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
        let completeHeight = (receipt as NSString).boundingRect(
            with: NSSize(width: time.frame.width + 0.5, height: 1_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font]).height
        try expect(time.frame.height + 1 >= completeHeight,
                   "\(context): complete date/time has enough rendered height, not a clipped line (\(time.frame), required \(completeHeight))")
        return time.frame.height
    }

    private static func assertTarget(_ view: NSView, window: NSWindow, id: String,
                                     context: String) async throws -> TimestampAXNode {
        let node = try await find(view, id: id)
        try expect(node.frame.width >= 31.5 && node.frame.height >= 31.5,
                   "\(context): actual native control retains a 32-point target: \(node.frame)")
        try expect(node.frame.minX >= window.frame.minX - 1 && node.frame.maxX <= window.frame.maxX + 1
            && node.frame.minY >= window.frame.minY - 1 && node.frame.maxY <= window.frame.maxY + 1,
                   "\(context): control fits the narrow visible fixture: \(node.frame)")
        return node
    }

    private static func checkCollectionsAndSearch(_ state: AppState, evidence: URL) async throws {
        let stamp = date("2026-09-30T22:17:00Z")
        let zone = TimeZone(secondsFromGMT: 10_800)!
        let first = try await state.store.importData(Data("Fictional first batch original".utf8),
            filename: "Fictional first batch.dat", at: stamp, timeZone: zone)
        let second = try await state.store.importData(Data("Fictional second batch original".utf8),
            filename: "Fictional second batch.dat", at: stamp, timeZone: zone)
        for item in [first, second] { try state.store.setMinimized(item, minimized: true) }
        guard let batch = CaptureCardGroup.cards(from: [first, second]).first else {
            throw NSError(domain: "CaptureTimestampPresentationTests", code: 6)
        }
        let automatic = (0..<4).map { index in
            Capture(capturedAt: stamp.addingTimeInterval(Double(index * 60)), timeZone: zone, kind: .text,
                    originalText: "Fictional hourly observation \(index)", title: "Fictional hourly observation \(index)",
                    receipt: .automatic(.automaticClipboard, actionID: UUID(), sourceApplicationName: "Fixture App",
                                        sourceApplicationBundleIdentifier: "com.dabin.fixture"))
        }
        guard case .automaticHour(let hour)? = HourlyCaptureFeed.cards(from: automatic, filter: .all,
            today: stamp, calendarTimeZone: zone).first else {
            throw NSError(domain: "CaptureTimestampPresentationTests", code: 7)
        }
        let body = "Fictional orbit observations " + String(repeating: "with useful matching context and decisions ", count: 12)
        let searchCapture = try state.store.capture(text: body, at: stamp, timeZone: zone,
            projectName: "Fictional long project name for responsive search action wrapping")[0]
        let searchItem = SearchDateItem.capture(SearchEntry(capture: searchCapture, isMatch: true, indexedTextMatch: nil))
        let note = WorkspaceScratchpad(text: body,
            projectName: "Fictional long project notes for responsive actions", updatedAt: stamp)
        let noteItem = SearchDateItem.note(note)
        let original = (searchCapture.capturedAt, searchCapture.captureDay, searchCapture.originalText, searchCapture.projectName)

        for width in [CGFloat(260), CGFloat(380)] {
            for factor in [CGFloat(1), CGFloat(2)] {
                let zoom = WorkspaceZoomLayout(factor: factor)
                let suffix = "\(Int(width))-\(Int(factor * 100))"
                let size = NSSize(width: width, height: 550)
                try await withView(GroupedCaptureCard(state: state, group: batch, compact: true)
                    .environment(\.workspaceZoom, zoom), size: size) { view, window in
                    let summary = try await assertTarget(view, window: window, id: "collection-batch-summary", context: "Batch expand \(suffix)")
                    // The native summary Button combines its label children.
                    // Its exact action label supplies the batch category, and
                    // its value must retain the complete original receipt.
                    try expect(summary.label == "Expand batch items", "Batch category remains accessible on its actual expansion action")
                    try expect(summary.stringValue == "\(batch.captures.count) captures, \(captureReceiptText(first))",
                               "Collapsed batch \(suffix) exposes its exact count and complete saved date/clock")
                    _ = try await assertTarget(view, window: window, id: "capture-copy-batch-\(first.id.uuidString)", context: "Batch copy \(suffix)")
                    _ = try await assertTarget(view, window: window, id: "capture-more-batch-\(first.id.uuidString)", context: "Batch More \(suffix)")
                    try snapshot(view, to: evidence.appendingPathComponent("batch-\(suffix).png"))
                    try expect(summary.press(), "Collapsed batch expands through its real native control")
                    await settle(view)
                    try expect([first, second].allSatisfy { !$0.isMinimized },
                               "Batch expansion changes each persisted presentation flag")
                    let childLabel = "Open \(second.title), \(captureTypeLabel(second.kind))"
                    guard let child = nodes(view).first(where: { $0.label == childLabel }) else {
                        throw NSError(domain: "CaptureTimestampPresentationTests", code: 9,
                            userInfo: [NSLocalizedDescriptionKey: "Missing compact expanded native item \(childLabel)"])
                    }
                    try expect(child.label == childLabel && child.stringValue == captureReceiptText(second),
                               "Compact expanded item exposes its exact full title/category and original date/clock")
                    try expect(child.frame.width >= 31.5 && child.frame.height >= 31.5,
                               "Compact expanded item keeps its real native 32-point activation target")
                    try expect(child.frame.minX >= window.frame.minX - 1 && child.frame.maxX <= window.frame.maxX + 1
                        && child.frame.minY >= window.frame.minY - 1 && child.frame.maxY <= window.frame.maxY + 1,
                               "Compact expanded item remains inside the narrow/high-zoom fixture: \(child.frame)")
                }
                try await withView(GroupedCaptureCard(state: state, group: batch)
                    .environment(\.workspaceZoom, zoom), size: NSSize(width: width, height: 680)) { view, window in
                    // Use the non-primary child: the group header legitimately
                    // reuses the primary receipt with its Batch category.
                    _ = try await assertReceipt(second, in: view, window: window, category: captureTypeLabel(second.kind),
                        context: "Expanded batch child \(suffix)", fontSize: zoom.fontSize(11))
                    guard let collapse = nodes(view).first(where: { $0.label == "Collapse batch items" }) else {
                        throw NSError(domain: "CaptureTimestampPresentationTests", code: 8,
                            userInfo: [NSLocalizedDescriptionKey: "Expanded batch has no native Collapse action"])
                    }
                    try expect(collapse.frame.width >= 31.5 && collapse.frame.height >= 31.5,
                               "Expanded batch retains its native 32-point Collapse target")
                    try snapshot(view, to: evidence.appendingPathComponent("batch-expanded-\(suffix).png"))
                    try expect(collapse.press(), "Expanded batch collapses through its real native control")
                    await settle(view)
                    try expect([first, second].allSatisfy(\.isMinimized),
                               "Batch Collapse returns every member to the saved summary state")
                    let restored = try await find(view, id: "collection-batch-summary")
                    try expect(restored.stringValue == "\(batch.captures.count) captures, \(captureReceiptText(first))",
                               "Collapsing preserves the exact saved receipt and count")
                }
                try await withView(HourlyCaptureCard(state: state, group: hour, compact: true)
                    .environment(\.workspaceZoom, zoom), size: size) { view, window in
                    let summary = try await assertTarget(view, window: window, id: "collection-hour-summary", context: "Hour expand \(suffix)")
                    let title = hour.displaysDate ? hour.summaryTitle
                        : "\(prettyDay(hour.id.captureDay, includeWeekday: false)) · \(hour.summaryTitle)"
                    try expect(summary.label == "Expand actions, \(title)",
                               "Combined hourly summary exposes its exact action, original local date and complete hour range")
                    try expect(summary.stringValue == hour.captureCountLabel,
                               "Combined hourly summary exposes its exact visible capture count")
                    try snapshot(view, to: evidence.appendingPathComponent("hour-\(suffix).png"))
                }
                state.openSearch()
                state.query = "orbit"
                state.searchSelectedResultID = nil
                try await withView(TimestampSearchCardFixture(state: state, item: searchItem)
                    .environment(\.workspaceZoom, zoom), size: size) { view, window in
                    let select = try await assertTarget(view, window: window, id: "search-select-\(searchCapture.id.uuidString)", context: "Search select \(suffix)")
                    try expect(select.stringValue.contains("orbit"), "Search \(suffix) preserves matching evidence in its accessible value")
                    let open = try await assertTarget(view, window: window, id: "search-open-\(searchCapture.id.uuidString)", context: "Search Open \(suffix)")
                    _ = try await assertTarget(view, window: window, id: "capture-copy-\(searchCapture.id.uuidString)", context: "Search Copy \(suffix)")
                    try snapshot(view, to: evidence.appendingPathComponent("search-capture-\(suffix).png"))
                    try expect(select.press(), "Search selection is a real native action")
                    await settle(view)
                    try expect(state.route == .search && state.searchSelectedResultID == searchItem.id,
                               "Selecting an expanded search result preserves the Search route and selects its identity")
                    try expect(open.press(), "Search Open remains a real native supporting action")
                    await settle(view)
                    try expect(state.route == .detail && state.selectedCapture?.id == searchCapture.id,
                               "Search Open reaches the same capture details after layout refinement")
                }
                state.openSearch()
                try await withView(TimestampSearchCardFixture(state: state, item: noteItem)
                    .environment(\.workspaceZoom, zoom), size: size) { view, window in
                    let edit = try await assertTarget(view, window: window, id: "search-edit-\(noteItem.id)", context: "Search note Edit \(suffix)")
                    let copy = try await assertTarget(view, window: window, id: "search-copy-\(noteItem.id)", context: "Search note Copy \(suffix)")
                    try expect(copy.label == "Copy \(note.projectName!) notes to clipboard", "Note copy retains its full contextual label")
                    try snapshot(view, to: evidence.appendingPathComponent("search-note-\(suffix).png"))
                    try expect(edit.press(), "Search note Edit remains a real native action")
                    await settle(view)
                    try expect(state.route == .searchNote && state.selectedSearchNote?.projectName == note.projectName,
                               "Note Edit opens the existing note destination")
                }
            }
        }
        try expect(searchCapture.capturedAt == original.0 && searchCapture.captureDay == original.1
            && searchCapture.originalText == original.2 && searchCapture.projectName == original.3,
                   "Card selection and navigation preserve original content, receipt and project")
        try expect([first, second].allSatisfy(\.isMinimized), "Geometry checks never alter saved batch presentation")
    }

    private static func snapshot(_ view: NSView, to url: URL) throws {
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw NSError(domain: "CaptureTimestampPresentationTests", code: 3)
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "CaptureTimestampPresentationTests", code: 4)
        }
        try data.write(to: url, options: .atomic)
    }

    private static func run() async throws {
        let originalZone = NSTimeZone.default
        defer { NSTimeZone.default = originalZone }
        let cases: [(String, String, String, Int, String)] = [
            ("2026-09-30T22:17:00Z", "2026-10-01", "Asia/Jerusalem", 10_800, "01:17"),
            ("2026-11-01T05:45:00Z", "2026-11-01", "America/New_York", -14_400, "01:45"),
            ("2026-11-01T06:45:00Z", "2026-11-01", "America/New_York", -18_000, "01:45"),
            ("2026-09-30T20:44:00Z", "2026-10-01", "Asia/Kolkata", 19_800, "02:14")
        ]
        for (stamp, day, zoneID, offset, clock) in cases {
            let capture = Capture(capturedAt: date(stamp), kind: .text, originalText: "Timestamp fixture",
                                  title: "Timestamp fixture", captureDay: day, captureTimeZoneID: zoneID,
                                  captureUTCOffsetSeconds: offset)
            let original = (capture.capturedAt, capture.captureDay, capture.captureTimeZoneID, capture.captureUTCOffsetSeconds)
            for viewingZone in ["Pacific/Auckland", "America/Los_Angeles", "UTC"] {
                NSTimeZone.default = TimeZone(identifier: viewingZone)!
                try expect(captureClock(capture) == clock, "Receipt clock uses its saved offset after travel: \(stamp)/\(viewingZone)")
                try expect(captureReceiptText(capture) == "\(prettyDay(day, includeWeekday: false)) · \(clock)",
                           "Card receipt uses original capture day and time")
                try expect(captureReceiptText(capture, includeWeekday: true) == "\(prettyDay(day)) · \(clock)",
                           "Detail receipt retains its weekday and original clock")
            }
            capture.title = "Edited title"; capture.comment = "Edited later"; capture.projectName = "Edited project"
            capture.updatedAt = date("2026-12-30T23:59:00Z")
            try expect(captureReceiptText(capture).hasSuffix(" · \(clock)"), "Receipt never uses an edit timestamp")
            try expect(capture.capturedAt == original.0 && capture.captureDay == original.1
                       && capture.captureTimeZoneID == original.2 && capture.captureUTCOffsetSeconds == original.3,
                       "Presentation preserves every immutable receipt field")
        }
        NSTimeZone.default = originalZone

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinTimestampQA-\(UUID().uuidString)")
        let suite = "DaBinTimestampQA.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root)
        let capture = try store.capture(text: "Original capture receipt", at: date("2026-09-30T22:17:00Z"),
                                        timeZone: TimeZone(secondsFromGMT: 10_800)!)[0]
        let autoCapture = AutoCaptureService(settings: AutoCaptureSettings(defaults: defaults), input: InputService(store: store),
            pasteboardProvider: { fatalError("Timestamp QA must not access the clipboard") }, sourceApplicationProvider: { nil })
        defer { autoCapture.shutdown() }
        let state = AppState(store: store, previews: PreviewService(store: store, defaults: defaults),
            reminders: ReminderService(store: store, client: TimestampReminderClient()), autoCapture: autoCapture)
        let evidence = ProcessInfo.processInfo.environment["DABIN_TIMESTAMP_QA_DIR"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("build/qa/capture-timestamp-density", isDirectory: true)
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        var smallestCardHeight: CGFloat = .greatestFiniteMagnitude

        for width in [CGFloat(260), CGFloat(380)] {
            for kind in [CaptureKind.text, .task, .pdf] {
                let item = Capture(capturedAt: capture.capturedAt, kind: kind, originalText: "Timestamp fixture",
                                   title: "Timestamp fixture", captureDay: capture.captureDay,
                                   captureTimeZoneID: capture.captureTimeZoneID,
                                   captureUTCOffsetSeconds: capture.captureUTCOffsetSeconds)
                item.isMinimized = true
                try await withView(CaptureRow(state: state, capture: item, featured: false), size: NSSize(width: width, height: 450)) { view, window in
                    let height = try await assertReceipt(item, in: view, window: window,
                        category: captureTypeLabel(kind), context: "\(kind.rawValue) card at \(Int(width))")
                    smallestCardHeight = min(smallestCardHeight, height)
                    try snapshot(view, to: evidence.appendingPathComponent("card-\(kind.rawValue)-\(Int(width)).png"))
                }
            }
            try await withView(WorkspaceItemCard(state: state, workspace: state.workspace, capture: capture),
                               size: NSSize(width: width, height: 450)) { view, window in
                _ = try await assertReceipt(capture, in: view, window: window,
                    category: captureTypeLabel(capture.kind), context: "Project card at \(Int(width))")
                try snapshot(view, to: evidence.appendingPathComponent("project-card-\(Int(width)).png"))
            }
        }

        try await checkCollectionsAndSearch(state, evidence: evidence)

        for width in [CGFloat(260), CGFloat(380), CGFloat(900)] {
            state.openCapture(capture.id)
            guard let draft = state.selectedDraft else { throw NSError(domain: "CaptureTimestampPresentationTests", code: 5) }
            try await withView(DetailScreen(state: state, capture: capture, draft: draft),
                               size: NSSize(width: width, height: 680)) { view, window in
                let time = try await find(view, id: "detail-captured-at")
                try expect(time.label == "Captured \(prettyDay(capture.captureDay)) at \(captureClock(capture))",
                           "Detail exposes full original capture date and clock at \(Int(width))")
                try expect(time.frame.height >= 18 && time.frame.height > smallestCardHeight + 3,
                           "Detail timestamp is visibly larger than the 11-point card receipt: \(time.frame.height)/\(smallestCardHeight)")
                try expect(time.frame.minX >= window.frame.minX - 1 && time.frame.maxX <= window.frame.maxX + 1
                    && time.frame.minY >= window.frame.minY && time.frame.maxY <= window.frame.maxY,
                           "Larger detail timestamp fits the viewport at \(Int(width))")
                try snapshot(view, to: evidence.appendingPathComponent("detail-\(Int(width)).png"))
                state.filter = .media
                try expect(time.press(), "The enlarged detail timestamp preserves its native day-navigation action")
                await settle(view)
                try expect(state.route == .daily && state.filter == .all
                    && CaptureCalendar.dayString(state.selectedDay) == capture.captureDay,
                           "Clicking capture date returns to the original day, not today or the edit date")
            }
        }
        print("Capture timestamp presentation QA passed: \(checks) checks; original receipt formatting, narrow/high-zoom collection and search actions, compact date-before-category cards, enlarged detail date navigation. Evidence: \(evidence.path)")
    }
}
