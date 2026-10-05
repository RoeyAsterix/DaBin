import AppKit
import ApplicationServices
import SwiftUI

@MainActor private final class ReadabilityReminderClient: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .undetermined }
    func requestAuthorization() async throws -> Bool { false }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}

/// Native fixtures use only synthetic records, own-process accessibility and
/// window-local events. No archive, clipboard or external application is read.
@MainActor private struct ReadabilityAXNode {
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
        [value("accessibilityLabel"), value("accessibilityTitle"), attribute("AXTitle"), attribute("AXDescription"),
         value("accessibilityValue"), attribute("AXValue")]
            .compactMap { ($0 as? String) ?? ($0 as? NSAttributedString)?.string }.first { !$0.isEmpty } ?? ""
    }
    var role: String { (value("accessibilityRole") as? String) ?? (attribute("AXRole") as? String) ?? "" }
    func accessibilityText(_ name: String) -> String? {
        guard name == "accessibilityLabel" || name == "accessibilityTitle" else { return nil }
        let raw = value(name)
        return (raw as? String) ?? (raw as? NSAttributedString)?.string
    }
    func diagnosticValues() -> [String: Any] {
        var result: [String: Any] = ["resolvedIdentifier": identifier ?? "", "resolvedLabel": label, "role": role]
        for name in ["accessibilityIdentifier", "accessibilityLabel", "accessibilityTitle"] {
            result[name + "Supported"] = object.responds(to: NSSelectorFromString(name))
            let raw = value(name)
            result[name] = (raw as? String) ?? (raw as? NSAttributedString)?.string ?? ""
        }
        for name in ["AXIdentifier", "AXTitle", "AXDescription"] {
            let raw = attribute(name)
            result[name] = (raw as? String) ?? (raw as? NSAttributedString)?.string ?? ""
        }
        return result
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
            if let children = value(name) as? [Any] { result += children }
        }
        if let children = attribute("AXChildren") as? [Any] { result += children }
        if let view = object as? NSView { result += view.subviews }
        return result
    }
}

@MainActor private struct ReadabilityCaptureSnapshot: Equatable {
    let id: UUID
    let capturedAt: Date
    let captureDay: String
    let title: String
    let kind: String
    let originalText: String?
    let originalURL: String?
    let attachment: String?
    let indexedText: String
    let indexState: String
    let indexVersion: Int
    let comment: String
    let project: String?
    let completed: Bool
    let updatedAt: Date

    init(_ capture: Capture) {
        id = capture.id; capturedAt = capture.capturedAt; captureDay = capture.captureDay
        title = capture.title; kind = capture.kindRaw; originalText = capture.originalText
        originalURL = capture.originalURL; attachment = capture.attachmentRelativePath
        indexedText = capture.indexedText; indexState = capture.contentIndexState
        indexVersion = capture.contentIndexVersion; comment = capture.comment
        project = capture.projectName; completed = capture.isCompleted; updatedAt = capture.updatedAt
    }
}

@main @MainActor private final class CaptureDetailReadabilityTests: NSObject, NSApplicationDelegate {
    private static var checks = 0
    private static var evidence: [[String: Any]] = []
    private var result = 0

    static func main() {
        let application = NSApplication.shared
        let delegate = CaptureDetailReadabilityTests()
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
                fputs("Capture detail readability QA failed: \(error)\n", stderr)
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
            throw NSError(domain: "CaptureDetailReadabilityTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private static func nodes(_ view: NSView) -> [ReadabilityAXNode] {
        view.layoutSubtreeIfNeeded()
        var seen = Set<ObjectIdentifier>(), result: [ReadabilityAXNode] = []
        func visit(_ value: Any, depth: Int) {
            guard depth < 50, let object = value as? NSObject,
                  seen.insert(ObjectIdentifier(object)).inserted else { return }
            let node = ReadabilityAXNode(object: object)
            result.append(node)
            node.children.forEach { visit($0, depth: depth + 1) }
        }
        visit(view, depth: 0)
        NSAccessibility.unignoredChildren(from: [view]).forEach { visit($0, depth: 0) }
        return result
    }

    private static func settle(_ view: NSView) async {
        for _ in 0..<6 {
            view.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(40))
        }
    }

    private static func find(_ view: NSView, id: String) async throws -> ReadabilityAXNode {
        for _ in 0..<8 {
            if let node = nodes(view).first(where: { $0.identifier == id }) { return node }
            await settle(view)
        }
        throw NSError(domain: "CaptureDetailReadabilityTests", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Missing native control \(id): \(nodes(view).map { $0.identifier ?? $0.label }.joined(separator: "; "))"])
    }

    private static func withFixture(_ content: AnyView, size: CGSize, allowResize: Bool = false,
                                    body: (NSView, NSWindow) async throws -> Void) async throws {
        let root = allowResize ? content : AnyView(content.frame(width: size.width, height: size.height,
                                                                alignment: .topLeading))
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        window.orderFront(nil)
        await settle(host)
        let accessibility = await Task.detached {
            let process = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            AXUIElementSetMessagingTimeout(process, 3)
            var windows: CFTypeRef?
            return AXUIElementCopyAttributeValue(process, kAXWindowsAttribute as CFString, &windows)
        }.value
        try expect(accessibility == .success, "Fixture exposes only its own process accessibility hierarchy")
        await settle(host)
        try expect(window.frame.maxX < 0 && !window.isKeyWindow && !NSApp.isActive,
                   "Readability fixture remains offscreen, non-key and inactive")
        try await body(host, window)
    }

    /// The right-hand region is the visible text label, outside the icon's
    /// original 32-point canvas. Events are dispatched to this fixture only.
    private static func clickLabel(_ node: ReadabilityAXNode, in window: NSWindow) throws {
        let screenPoint = NSPoint(x: node.frame.maxX - 8, y: node.frame.midY)
        try click(screenPoint, in: window)
    }

    private static func click(_ screenPoint: NSPoint, in window: NSWindow) throws {
        let point = window.convertPoint(fromScreen: screenPoint)
        let timestamp = ProcessInfo.processInfo.systemUptime
        guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
            timestamp: timestamp, windowNumber: window.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1),
              let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [],
            timestamp: timestamp + 0.02, windowNumber: window.windowNumber, context: nil,
            eventNumber: 2, clickCount: 1, pressure: 0) else {
            throw NSError(domain: "CaptureDetailReadabilityTests", code: 3)
        }
        NSApp.postEvent(up, atStart: true)
        window.sendEvent(down)
        if let remaining = NSApp.nextEvent(matching: .leftMouseUp, until: Date(), inMode: .default, dequeue: true) {
            try expect(remaining.windowNumber == window.windowNumber,
                       "Label click mouse-up belongs only to the fixture window")
            window.sendEvent(remaining)
        }
    }

    private static func render(_ view: NSView, name: String, output: URL) throws {
        let size = view.bounds.size
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2),
            pixelsHigh: Int(size.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw NSError(domain: "CaptureDetailReadabilityTests", code: 4)
        }
        bitmap.size = size
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "CaptureDetailReadabilityTests", code: 5)
        }
        try data.write(to: output.appendingPathComponent(name + "@2x.png"))
    }

    private static func checkButtons(output: URL) async throws {
        var labeledActions = 0, iconActions = 0
        let content = AnyView(HStack(spacing: 16) {
            BuddyIconButton(symbol: "doc.on.doc", title: "Copy capture", visualLabel: "Copy") { labeledActions += 1 }
                .accessibilityIdentifier("readability-labeled-copy")
            BuddyIconButton(symbol: "doc.on.doc", title: "Icon-only copy") { iconActions += 1 }
                .accessibilityIdentifier("readability-icon-copy")
            Spacer(minLength: 0)
        }.padding(16).environment(\.daBinTooltipsEnabled, false).background(Palette.background))
        try await withFixture(content, size: CGSize(width: 380, height: 96)) { host, window in
            let labeled = try await find(host, id: "readability-labeled-copy")
            let iconOnly = try await find(host, id: "readability-icon-copy")
            try expect(labeled.role == NSAccessibility.Role.button.rawValue && labeled.label == "Copy capture",
                       "Visible Copy label retains the full accessible action name")
            try expect(labeled.frame.width > 48 && labeled.frame.height >= 32,
                       "Labeled action includes a readable label beyond the icon canvas and a 32-point target")
            try expect(abs(iconOnly.frame.width - 32) < 1 && abs(iconOnly.frame.height - 32) < 1,
                       "Default icon-only controls retain their existing 32 by 32 geometry")
            try expect(labeledActions == 0 && iconActions == 0, "Rendering controls never invokes copy actions")
            try clickLabel(labeled, in: window)
            await settle(host)
            try expect(labeledActions == 1 && iconActions == 0,
                       "Clicking the visible label region invokes only its own action exactly once")
            try expect(labeled.press(), "Labeled action supports native accessibility press")
            await settle(host)
            try expect(labeledActions == 2 && iconActions == 0, "Accessibility press activates the same labeled action once")
            try expect(iconOnly.press(), "Default icon-only action retains accessibility press")
            await settle(host)
            try expect(iconActions == 1, "Icon-only callback still activates exactly once")
            try expect(!window.isKeyWindow && !NSApp.isActive, "Local button events do not activate another application")
            try render(host, name: "labeled-copy-and-icon-default", output: output)
        }
    }

    private static func checkReminderLabel(output: URL) async throws {
        var enabled = false, bindingWrites = 0
        let content = AnyView(VStack(alignment: .leading) {
            ReminderClockEditor(enabled: Binding(get: { enabled }, set: { enabled = $0; bindingWrites += 1 }),
                mode: .constant(.countdown), date: .constant(Date(timeIntervalSince1970: 1_791_108_660)),
                hours: .constant(0), minutes: .constant(30))
            Spacer(minLength: 0)
        }.padding(16).environment(\.daBinTooltipsEnabled, false).background(Palette.background))
        try await withFixture(content, size: CGSize(width: 380, height: 280)) { host, window in
            let toggle = try await find(host, id: "reminder-enabled")
            let label = try await find(host, id: "reminder-label-toggle")
            try render(host, name: "reminder-before-label-click", output: output)
            try expect(label.role == NSAccessibility.Role.button.rawValue && label.label == "Reminder"
                && label.frame.height >= 32,
                       "The visible Reminder label is a named native button with a 32-point target")
            // Click the text within the label button, never the nearby switch.
            let point = NSPoint(x: label.frame.minX + 40, y: label.frame.midY)
            try expect(label.frame.contains(point) && !toggle.frame.contains(point),
                       "Reminder fixture clicks actual visible text, outside the native switch target")
            try expect(!enabled && bindingWrites == 0, "Rendering Reminder does not change its binding")
            try click(point, in: window)
            await settle(host)
            try expect(enabled && bindingWrites == 1,
                       "Clicking the Reminder text label changes its own binding exactly once")
            try expect(toggle.label.contains("Reminder"),
                       "Reminder's native switch retains the visible label as its accessible name")
            let updated = try await find(host, id: "reminder-enabled")
            try expect(updated.label.contains("Reminder") && updated.press(),
                       "Reminder retains its identifier, accessible label and native press after enabling")
            await settle(host)
            try expect(!enabled && bindingWrites == 2, "Reminder accessibility press toggles the same binding exactly once")
            try expect(!window.isKeyWindow && !NSApp.isActive, "Reminder label events remain confined to the inactive fixture")
            try render(host, name: "reminder-label-target", output: output)
        }
    }

    private static func checkPanel(_ capture: Capture, width: CGFloat, factor: CGFloat,
                                   dark: Bool, output: URL) async throws {
        let viewport = CGSize(width: width, height: 680)
        let layout = DetailLayout(viewport: viewport, factor: factor)
        let before = ReadabilityCaptureSnapshot(capture)
        let fullText = capture.indexedText
        let expectedPreview = String(fullText.prefix(2_000))
        var copies: [String] = []
        let content = AnyView(VStack(alignment: .leading, spacing: 0) {
            CaptureRecognizedTextPanel(capture: capture, layout: layout, copied: false,
                                      onCopy: { copies.append(capture.indexedText) })
                .frame(width: layout.contentWidth, alignment: .leading)
            Spacer(minLength: 0)
        }.padding(.horizontal, layout.horizontalInset).padding(.top, 16)
            .environment(\.workspaceZoom, WorkspaceZoomLayout(factor: factor))
            .environment(\.daBinTooltipsEnabled, false).environment(\.displayScale, 2)
            .preferredColorScheme(dark ? .dark : .light).background(Palette.background))
        let context = "recognized-\(Int(width))-zoom\(Int(factor * 100))-\(dark ? "dark" : "light")"
        try await withFixture(content, size: viewport) { host, window in
            let panel = try await find(host, id: "recognized-text-panel")
            let body = try await find(host, id: "recognized-text-body")
            guard let reader = body.object as? NSTextView, let scroll = reader.enclosingScrollView else {
                throw NSError(domain: "CaptureDetailReadabilityTests", code: 6,
                              userInfo: [NSLocalizedDescriptionKey: "\(context): recognized text must expose its native text reader"])
            }
            let readerIdentity = ObjectIdentifier(reader)
            try expect(reader.string == expectedPreview, "\(context): preview shows the first 2,000 original characters exactly")
            try expect(!reader.isEditable && reader.isSelectable, "\(context): recognized text is selectable and read-only")
            try expect(abs((reader.font?.pointSize ?? 0) - layout.bodySize) < 0.05 && layout.bodySize >= 14,
                       "\(context): native reader uses the responsive readable body font")
            try expect(!scroll.hasHorizontalScroller && reader.frame.width <= scroll.contentView.bounds.width + 1,
                       "\(context): recognized text wraps within its native viewport without a horizontal scroller")
            try expect(panel.frame.width > 0 && abs(panel.frame.width - layout.contentWidth) < 2
                && panel.frame.height > 80 && panel.frame.height < viewport.height - 32,
                       "\(context): recognized panel has the available responsive width and a bounded height")
            try expect(body.frame.minX >= panel.frame.minX - 1 && body.frame.maxX <= panel.frame.maxX + 1,
                       "\(context): even a long text document stays horizontally inside its panel")
            try expect(window.frame.insetBy(dx: -1, dy: -1).contains(panel.frame),
                       "\(context): bounded panel stays inside the fixture viewport")
            try expect(copies.isEmpty, "\(context): rendering recognized text never invokes copy")
            reader.setSelectedRange(NSRange(location: 40, length: 20))
            try render(host, name: context + "-preview", output: output)
            let copy = try await find(host, id: "recognized-text-copy")
            try expect(copy.frame.width > 32 && copy.frame.height >= 32,
                       "\(context): recognized-text copy offers a visible text label and full target")
            try expect(copy.press(), "\(context): recognized-text copy supports native accessibility activation")
            await settle(host)
            try expect(copies == [fullText], "\(context): copying the preview calls through with all 5,000 original characters available")
            let toggle = try await find(host, id: "recognized-text-toggle")
            try expect(toggle.press(), "\(context): full recognized text can be revealed accessibly")
            await settle(host)
            let expanded = try await find(host, id: "recognized-text-body")
            guard let expandedReader = expanded.object as? NSTextView else {
                throw NSError(domain: "CaptureDetailReadabilityTests", code: 7)
            }
            try expect(ObjectIdentifier(expandedReader) == readerIdentity,
                       "\(context): expansion retains the native reader identity")
            try expect(expandedReader.string == fullText && expandedReader.string.count == 5_000,
                       "\(context): expansion reveals every original multilingual character including the final marker")
            try expect(expandedReader.selectedRange() == NSRange(location: 40, length: 20),
                       "\(context): expansion preserves the existing text selection")
            let previousPosition = scroll.contentView.bounds.origin
            if let container = expandedReader.textContainer { expandedReader.layoutManager?.ensureLayout(for: container) }
            let fullUTF16Count = (fullText as NSString).length
            expandedReader.scrollRangeToVisible(NSRange(location: fullUTF16Count - 20, length: 20))
            await settle(host)
            try expect(scroll.contentView.bounds.origin.y > 0
                && expandedReader.frame.height > scroll.contentView.bounds.height,
                       "\(context): the final recognized-text characters can be reached by native vertical scrolling")
            let expandedPanel = try await find(host, id: "recognized-text-panel")
            try expect(abs(expandedPanel.frame.height - panel.frame.height) < 2,
                       "\(context): expansion scrolls within the same bounded panel height")
            let expandedCopy = try await find(host, id: "recognized-text-copy")
            try clickLabel(expandedCopy, in: window)
            await settle(host)
            try expect(copies == [fullText, fullText], "\(context): clicking the copy label activates once and keeps complete text available")
            try render(host, name: context + "-expanded", output: output)
            expandedReader.setSelectedRange(NSRange(location: 40, length: 20))
            scroll.contentView.scroll(to: previousPosition)
            scroll.reflectScrolledClipView(scroll.contentView)
            await settle(host)
            let collapse = try await find(host, id: "recognized-text-toggle")
            try expect(collapse.press(), "\(context): expanded recognized text can return to preview")
            await settle(host)
            try expect(reader.string == expectedPreview && reader.selectedRange() == NSRange(location: 40, length: 20),
                       "\(context): collapse restores the bounded preview without discarding an in-range selection")
            try expect(ReadabilityCaptureSnapshot(capture) == before,
                       "\(context): reading, selecting, expanding and copying never mutate capture content or receipt metadata")
            try expect(!window.isKeyWindow && !NSApp.isActive, "\(context): panel actions remain confined to the inactive fixture")
            evidence.append(["context": context, "viewportWidth": width, "zoom": factor,
                "panelFrame": NSStringFromRect(panel.frame), "bodyFrame": NSStringFromRect(body.frame),
                "readerFontPoints": reader.font?.pointSize ?? 0,
                "previewCharacters": expectedPreview.count, "fullCharacters": fullText.count,
                "copyCallbacks": copies.count])
        }
    }

    private static func checkContinuousResize(_ capture: Capture, factor: CGFloat,
                                              dark: Bool, output: URL) async throws {
        let before = ReadabilityCaptureSnapshot(capture)
        let preview = String(capture.indexedText.prefix(2_000))
        var copies = 0
        let content = AnyView(GeometryReader { geometry in
            let layout = DetailLayout(viewport: geometry.size, factor: factor)
            VStack(alignment: .leading, spacing: 0) {
                CaptureRecognizedTextPanel(capture: capture, layout: layout, onCopy: { copies += 1 })
                    .frame(width: layout.contentWidth, alignment: .leading)
                Spacer(minLength: 0)
            }.padding(.horizontal, layout.horizontalInset).padding(.top, 16)
        }.environment(\.workspaceZoom, WorkspaceZoomLayout(factor: factor))
            .environment(\.daBinTooltipsEnabled, false).environment(\.displayScale, 2)
            .preferredColorScheme(dark ? .dark : .light).background(Palette.background))
        try await withFixture(content, size: CGSize(width: 380, height: 680), allowResize: true) { host, window in
            let initial = try await find(host, id: "recognized-text-body")
            guard let reader = initial.object as? NSTextView else {
                throw NSError(domain: "CaptureDetailReadabilityTests", code: 8)
            }
            let identity = ObjectIdentifier(reader), selection = NSRange(location: 40, length: 20)
            reader.setSelectedRange(selection)
            for width in [CGFloat(380), 1_200, 600] {
                window.setContentSize(CGSize(width: width, height: 680))
                await settle(host)
                let layout = DetailLayout(viewport: host.bounds.size, factor: factor)
                let body = try await find(host, id: "recognized-text-body")
                let panel = try await find(host, id: "recognized-text-panel")
                guard let resized = body.object as? NSTextView, let scroll = resized.enclosingScrollView,
                      let container = resized.textContainer else {
                    throw NSError(domain: "CaptureDetailReadabilityTests", code: 9)
                }
                let context = "continuous-\(Int(width))-zoom\(Int(factor * 100))-\(dark ? "dark" : "light")"
                try expect(abs(host.bounds.width - width) < 1, "\(context): the existing fixture actually resized")
                try expect(ObjectIdentifier(resized) == identity && resized.selectedRange() == selection,
                           "\(context): resizing retains the native reader and existing selection")
                try expect(resized.string == preview && abs((resized.font?.pointSize ?? 0) - layout.bodySize) < 0.05,
                           "\(context): the existing reader updates responsive typography without changing original text")
                try expect(abs(resized.frame.width - scroll.contentView.bounds.width) < 1
                    && container.containerSize.width.isFinite && container.containerSize.width > 0
                    && container.containerSize.width <= scroll.contentView.bounds.width + 1,
                           "\(context): native resize gives text a finite width within the actual scroll viewport")
                try expect(!scroll.hasHorizontalScroller && abs(panel.frame.width - layout.contentWidth) < 2
                    && body.frame.minX >= panel.frame.minX - 1 && body.frame.maxX <= panel.frame.maxX + 1,
                           "\(context): the existing panel and document stay horizontally contained after resize")
                try expect(window.frame.insetBy(dx: -1, dy: -1).contains(panel.frame),
                           "\(context): the bounded panel remains inside its resized window")
                try render(host, name: context, output: output)
                evidence.append(["context": context, "viewportWidth": width, "zoom": factor,
                    "panelFrame": NSStringFromRect(panel.frame), "bodyFrame": NSStringFromRect(body.frame),
                    "readerFontPoints": resized.font?.pointSize ?? 0,
                    "textContainerWidth": container.containerSize.width,
                    "nativeViewportWidth": scroll.contentView.bounds.width, "selectionPreserved": true])
            }
            try expect(copies == 0 && ReadabilityCaptureSnapshot(capture) == before,
                       "Continuous resizing never copies or mutates the capture")
        }
    }

    private static func checkDetailIntegration(_ capture: Capture, output: URL) async throws {
        @MainActor final class MenuTracking {
            let deadline = ProcessInfo.processInfo.systemUptime + 2
            weak var window: NSWindow?
            private(set) var menus: [NSMenu] = []
            private(set) var ended = Set<ObjectIdentifier>()
            private(set) var timedOut = false
            init(window: NSWindow) { self.window = window }
            func began(_ menu: NSMenu) {
                if !menus.contains(where: { $0 === menu }) { menus.append(menu) }
            }
            func didEnd(_ menu: NSMenu) { ended.insert(ObjectIdentifier(menu)) }
            func cancel() {
                menus.forEach { $0.cancelTrackingWithoutAnimation() }
                guard ProcessInfo.processInfo.systemUptime >= deadline else { return }
                timedOut = true
                guard let window, let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                    characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53) else { return }
                NSApp.postEvent(escape, atStart: true)
            }
        }
        func nativeMore(_ target: ReadabilityAXNode, host: NSView, window: NSWindow) async throws -> NSMenu {
            let tracking = MenuTracking(window: window)
            let center = NotificationCenter.default
            let began = center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { notification in
                guard let menu = notification.object as? NSMenu else { return }
                MainActor.assumeIsolated { tracking.began(menu) }
            }
            let ended = center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: nil) { notification in
                guard let menu = notification.object as? NSMenu else { return }
                MainActor.assumeIsolated { tracking.didEnd(menu) }
            }
            // SwiftUI's virtual menu button creates NSMenu on a label click.
            // Cancel from tracking-mode timers, after didBegin has returned.
            let timer = Timer(timeInterval: 0.02, repeats: true) { _ in
                MainActor.assumeIsolated { tracking.cancel() }
            }
            RunLoop.main.add(timer, forMode: .common)
            RunLoop.main.add(timer, forMode: .eventTracking)
            defer { timer.invalidate(); center.removeObserver(began); center.removeObserver(ended) }
            let point = NSPoint(x: target.frame.midX, y: target.frame.midY)
            try expect(target.frame.width > 0 && target.frame.height > 0 && window.frame.contains(point),
                       "More menu label click targets only the fixture's visible native label")
            try click(point, in: window)
            await settle(host)
            guard let menu = tracking.menus.first(where: { menu in
                menu.items.contains { $0.title == "Saved folder" || $0.title == "Show saved folder" }
                    && menu.items.contains { $0.title == "Trash" || $0.title.contains("Recently Deleted") }
            }) else {
                throw NSError(domain: "CaptureDetailReadabilityTests", code: 11,
                    userInfo: [NSLocalizedDescriptionKey: "Full Detail More label must open its real native action menu: \(tracking.menus.map { $0.items.map(\.title) })"])
            }
            try expect(!tracking.timedOut && tracking.ended.contains(ObjectIdentifier(menu)),
                       "More's native menu tracking ends before inspecting its real actions")
            try expect(!window.isKeyWindow && !NSApp.isActive,
                       "Own-process More label activation preserves the inactive, non-key fixture")
            return menu
        }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinReadabilityQA-\(UUID().uuidString)")
        let suite = "DaBinReadabilityQA.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: PreviewService.linkPreviewPreference)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: temporary) }
        let store = try CaptureStore(root: temporary, repairArchiveOnOpen: false)
        let previews = PreviewService(store: store, defaults: defaults)
        let auto = AutoCaptureService(settings: AutoCaptureSettings(defaults: defaults), input: InputService(store: store),
            pasteboardProvider: { fatalError("Readability QA must never read the clipboard") }, sourceApplicationProvider: { nil })
        let state = AppState(store: store, previews: previews,
            reminders: ReminderService(store: store, client: ReadabilityReminderClient()), autoCapture: auto,
            captureClipboard: CaptureClipboardService(writer: { _ in fatalError("Readability QA must never write the clipboard") }),
            folderOpener: { _ in fatalError("Readability QA must never open Finder") })
        defer { previews.shutdown(); auto.shutdown(); state.focusSessions.shutdown(); store.cancelArchiveRepair() }
        let before = ReadabilityCaptureSnapshot(capture)
        for (width, factor, dark) in [(CGFloat(380), CGFloat(1), false), (600, 2, true), (1_200, 1, false)] {
            // Narrow layouts expose Text through the section menu. Exercise its
            // production deep-link route; wide layouts use the visible button.
            let wideSections = DetailLayout(viewport: CGSize(width: width, height: 900), factor: factor).contentWidth / factor >= 610
            state.detailFocus = wideSections ? "capture-preview" : "recognized-text"
            let content = AnyView(DetailScreen(state: state, capture: capture, draft: CaptureDraft(capture: capture))
                .environment(\.workspaceZoom, WorkspaceZoomLayout(factor: factor))
                .environment(\.daBinTooltipsEnabled, false).environment(\.displayScale, 2)
                .preferredColorScheme(dark ? .dark : .light).background(Palette.background))
            try await withFixture(content, size: CGSize(width: width, height: 900)) { host, window in
                if wideSections {
                    let textSection = try await find(host, id: "detail-section-text")
                    try expect(textSection.press(), "Wide Full Detail opens recognized text through its visible section button")
                } else {
                    let picker = try await find(host, id: "detail-section-picker")
                    try expect(picker.label == "Capture section: Recognized text",
                               "Narrow Full Detail restores the recognized-text section through its deep-link focus")
                }
                await settle(host)
                try expect(state.detailFocus == "recognized-text", "Full Detail selects the recognized-text reading pane")
                let body = try await find(host, id: "recognized-text-body")
                guard let reader = body.object as? NSTextView, let scroll = reader.enclosingScrollView else {
                    throw NSError(domain: "CaptureDetailReadabilityTests", code: 10)
                }
                let layout = DetailLayout(viewport: host.bounds.size, factor: factor)
                let viewport = window.convertToScreen(host.convert(host.bounds, to: nil))
                let contentBounds = viewport.insetBy(dx: layout.horizontalInset, dy: 0)
                let nativeScrollFrame = window.convertToScreen(scroll.convert(scroll.bounds, to: nil))
                // Native geometry remains authoritative in the selected pane.
                // The panel owns exactly 12 zoom-scaled points on either side.
                let panelHorizontalBounds = nativeScrollFrame.insetBy(dx: -WorkspaceZoomLayout(factor: factor).value(12), dy: 0)
                try expect(panelHorizontalBounds.width > 0
                    && panelHorizontalBounds.minX >= contentBounds.minX - 1
                    && panelHorizontalBounds.maxX <= contentBounds.maxX + 1
                    && panelHorizontalBounds.minX >= window.frame.minX - 1
                    && panelHorizontalBounds.maxX <= window.frame.maxX + 1,
                           "Full Detail at \(Int(width)) points contains the native reader and panel padding inside its reading pane")
                try expect(reader.string == String(capture.indexedText.prefix(2_000))
                    && body.frame.minX >= nativeScrollFrame.minX - 1 && body.frame.maxX <= nativeScrollFrame.maxX + 1
                    && reader.frame.width <= scroll.contentView.bounds.width + 1 && !scroll.hasHorizontalScroller,
                           "Full Detail's native recognized-text document wraps within the actual reading-pane width")
                let copy = try await find(host, id: "detail-action-copy")
                let convert = try await find(host, id: "capture-convert-to-task-" + capture.id.uuidString)
                try expect(copy.label == "Copy capture" && convert.label == "Turn \(capture.title) into a task",
                           "Full Detail retains labeled Copy and Make task actions in its fixed header")
                for action in [copy, convert] {
                    try expect(action.frame.width > 32 && action.frame.height >= 32
                        && action.frame.minX >= contentBounds.minX - 1 && action.frame.maxX <= contentBounds.maxX + 1
                        && viewport.insetBy(dx: -1, dy: -1).contains(action.frame),
                               "Full Detail labeled action \(action.label) stays visible inside its fixed action rail")
                }
                let more = try await find(host, id: "detail-actions-more")
                let moreFrame = more.frame
                try expect(more.label == "More capture actions" && moreFrame.width > 32 && moreFrame.height >= 32
                    && moreFrame.minX >= contentBounds.minX - 1 && moreFrame.maxX <= contentBounds.maxX + 1
                    && viewport.insetBy(dx: -1, dy: -1).contains(moreFrame),
                           "Full Detail More has a visible labeled native target in its fixed action rail")
                let menu = try await nativeMore(more, host: host, window: window)
                let expectedMenuActions = [("detail-action-open-original", "Open original", "Open original"),
                    ("detail-action-folder", "Saved folder", "Show saved folder"),
                    ("capture-trash-" + capture.id.uuidString, "Trash", "Move \(capture.title) to Recently Deleted")]
                for (id, title, label) in expectedMenuActions {
                    guard let item = menu.items.first(where: {
                        ReadabilityAXNode(object: $0).identifier == id || $0.identifier?.rawValue == id
                    }) else {
                        throw NSError(domain: "CaptureDetailReadabilityTests", code: 12,
                            userInfo: [NSLocalizedDescriptionKey: "Missing native More menu action \(id): \(menu.items.map(\.title))"])
                    }
                    let node = ReadabilityAXNode(object: item)
                    let visibleLabelMatches = item.title == title && node.accessibilityText("accessibilityLabel") == title
                    let semanticTitleMatches = node.accessibilityText("accessibilityTitle") == label
                    let reachable = item.isEnabled && !item.isHidden && item.action != nil && menu.index(of: item) >= 0
                    if !visibleLabelMatches || !semanticTitleMatches || !reachable {
                        for nativeItem in menu.items {
                            var diagnostic = ReadabilityAXNode(object: nativeItem).diagnosticValues()
                            diagnostic.merge(["expectedID": id, "expectedTitle": title, "expectedLabel": label,
                                "expectedVisibleLabel": title, "expectedSemanticTitle": label,
                                "title": nativeItem.title, "nativeIdentifier": nativeItem.identifier?.rawValue ?? "",
                                "isEnabled": nativeItem.isEnabled, "isHidden": nativeItem.isHidden,
                                "action": nativeItem.action.map { NSStringFromSelector($0) } ?? "",
                                "menuIndex": menu.index(of: nativeItem)]) { _, new in new }
                            if let data = try? JSONSerialization.data(withJSONObject: diagnostic, options: [.sortedKeys]),
                               let message = String(data: data, encoding: .utf8) { fputs("MORE diagnostic: " + message + "\n", stderr) }
                        }
                    }
                    try expect(visibleLabelMatches,
                               "Full Detail retains exact native and visible accessibility labels for \(title)")
                    try expect(semanticTitleMatches,
                               "Full Detail retains the exact semantic accessibility title \(label)")
                    try expect(reachable,
                               "Full Detail retains reachable labeled \(label) through its native More menu")
                }
                let actionCount = 2 + expectedMenuActions.count
                try expect(actionCount == 5, "Full Detail retains all five capture actions through its compact header and More menu")
                try render(host, name: "detail-integration-\(Int(width))-zoom\(Int(factor * 100))-\(dark ? "dark" : "light")", output: output)
                evidence.append(["context": "detail-integration", "viewportWidth": width, "zoom": factor,
                    "inferredPanelHorizontalBounds": NSStringFromRect(panelHorizontalBounds),
                    "nativeScrollFrame": NSStringFromRect(nativeScrollFrame),
                    "detailFrame": NSStringFromRect(viewport), "contentBounds": NSStringFromRect(contentBounds),
                    "readerFontPoints": reader.font?.pointSize ?? 0, "actionCount": actionCount,
                    "moreActionIDs": expectedMenuActions.map { $0.0 }, "moreFrame": NSStringFromRect(moreFrame)])
            }
        }
        try expect(ReadabilityCaptureSnapshot(capture) == before, "Selecting Full Detail sections never mutates capture metadata or original text")
    }

    private static func run() async throws {
        // The runner executes from native/ and copies source into qa-cache;
        // its working directory is the stable native repository location.
        let repository = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).deletingLastPathComponent()
        let output = ProcessInfo.processInfo.environment["DABIN_CAPTURE_DETAIL_READABILITY_QA_OUTPUT"].map { URL(fileURLWithPath: $0) }
            ?? repository.appendingPathComponent("docs/qa/capture-detail-fix-2026-10-04")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let paragraph = "Fictional recognized text. Keep the original wording readable. שלום · 日本語 · Résumé · مرحبا.\n"
        let tail = "\nEND OF COMPLETE RECOGNIZED TEXT · שלום · 日本語"
        let full = String(String(repeating: paragraph, count: 100).prefix(5_000 - tail.count)) + tail
        try expect(full.count == 5_000, "Long multilingual fixture has exactly 5,000 characters")
        let capture = Capture(capturedAt: Date(timeIntervalSince1970: 1_791_108_660),
                              timeZone: TimeZone(secondsFromGMT: 0)!, kind: .image,
                              originalText: "Fictional immutable original", title: "Fictional recognized text image")
        capture.indexedText = full; capture.contentIndexState = "ready"; capture.projectName = "Fictional North Studio"
        try await checkButtons(output: output)
        try await checkReminderLabel(output: output)
        for width in [CGFloat(380), 600, 1_200] {
            var previousFont: CGFloat = 0
            for factor in [CGFloat(0.75), 1, 2] {
                let size = DetailLayout(viewport: CGSize(width: width, height: 680), factor: factor).bodySize
                try expect(size >= previousFont, "\(width)-point viewport never shrinks body typography when zoom increases")
                previousFont = size
                for dark in [false, true] {
                    try await checkPanel(capture, width: width, factor: factor, dark: dark, output: output)
                }
            }
        }
        try await checkContinuousResize(capture, factor: 1, dark: false, output: output)
        try await checkContinuousResize(capture, factor: 2, dark: true, output: output)
        try await checkDetailIntegration(capture, output: output)
        let report: [String: Any] = ["suite": "CaptureDetailReadabilityTests", "checks": checks,
            "fixtures": evidence, "privacy": "Synthetic records, own-process accessibility and window-local clicks only; no clipboard or personal archive access."]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("native-readability-report.json"))
        print("PASS: \(checks) capture-detail readability and labeled-action checks; \(evidence.count) native panel fixtures. Renders: \(output.path)")
    }
}
