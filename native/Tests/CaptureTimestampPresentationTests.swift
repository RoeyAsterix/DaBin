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
                                      category: String, context: String) async throws -> CGFloat {
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
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let completeHeight = (receipt as NSString).boundingRect(
            with: NSSize(width: time.frame.width + 0.5, height: 1_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font]).height
        try expect(time.frame.height + 1 >= completeHeight,
                   "\(context): complete date/time has enough rendered height, not a clipped line (\(time.frame), required \(completeHeight))")
        return time.frame.height
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
        let evidence = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("build/qa/capture-timestamp", isDirectory: true)
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
        print("Capture timestamp presentation QA passed: \(checks) checks; original receipt formatting, compact date-before-category cards, enlarged detail date navigation. Evidence: \(evidence.path)")
    }
}
