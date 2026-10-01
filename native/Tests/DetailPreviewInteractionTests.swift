import AppKit
import ApplicationServices
import ImageIO
import PDFKit
import SwiftUI

@MainActor private final class DetailPreviewReminderClient: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .undetermined }
    func requestAuthorization() async throws -> Bool { false }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}

/// Uses only own-process accessibility actions and synthetic window-local
/// clicks in offscreen fixture windows. It never opens an external app.
@MainActor private struct DetailPreviewAXNode {
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
    var help: String {
        [value("accessibilityHelp"), attribute("AXHelp")].compactMap { $0 as? String }.first { !$0.isEmpty } ?? ""
    }
    var role: String { (value("accessibilityRole") as? String) ?? (attribute("AXRole") as? String) ?? "" }
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

@main @MainActor private final class DetailPreviewInteractionTests: NSObject, NSApplicationDelegate {
    private static var checks = 0
    private var result = 0

    static func main() {
        let application = NSApplication.shared
        let delegate = DetailPreviewInteractionTests()
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
                fputs("Detail preview interaction QA failed: \(error)\n", stderr)
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
            throw NSError(domain: "DetailPreviewInteractionTests", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private static func nodes(_ view: NSView) -> [DetailPreviewAXNode] {
        view.layoutSubtreeIfNeeded()
        var seen = Set<ObjectIdentifier>()
        var result: [DetailPreviewAXNode] = []
        func visit(_ value: Any, depth: Int) {
            guard depth < 50, let object = value as? NSObject,
                  seen.insert(ObjectIdentifier(object)).inserted else { return }
            let node = DetailPreviewAXNode(object: object)
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

    private static func pdfView(in view: NSView) -> PDFView? {
        if let pdf = view as? PDFView { return pdf }
        return view.subviews.lazy.compactMap { pdfView(in: $0) }.first
    }

    private static func find(_ view: NSView, id: String) async throws -> DetailPreviewAXNode {
        for _ in 0..<12 {
            if let node = nodes(view).first(where: { $0.identifier == id }) { return node }
            await settle(view)
        }
        throw NSError(domain: "DetailPreviewInteractionTests", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Missing native preview control \(id): \(nodes(view).map { $0.identifier ?? $0.label }.joined(separator: "; "))"])
    }

    private static func find(_ view: NSView, label: String) async throws -> DetailPreviewAXNode {
        for _ in 0..<12 {
            if let node = nodes(view).first(where: { $0.label == label }) { return node }
            await settle(view)
        }
        throw NSError(domain: "DetailPreviewInteractionTests", code: 8,
            userInfo: [NSLocalizedDescriptionKey: "Missing native preview control \(label)"])
    }

    private static func withPreview(store: CaptureStore, capture: Capture, opener: (() -> Void)?,
                                    body: (NSView, NSWindow) async throws -> Void) async throws {
        let hosting = NSHostingView(rootView: DetailPreview(store: store, capture: capture, height: 220,
                                                            onOpenOriginal: opener)
            .frame(width: 360, height: 240))
        hosting.frame = NSRect(x: 0, y: 0, width: 360, height: 240)
        hosting.wantsLayer = true
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 360, height: 240),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        // SwiftUI materializes native accessibility only for an ordered window.
        // Render offscreen without makeKey, activation, or a global pointer event.
        window.orderFront(nil)
        await settle(hosting)
        // SwiftUI exposes virtual AX nodes lazily, after a client requests the
        // application hierarchy. Ask only this test process while the AppKit
        // run loop remains available to serve that own-process request.
        let accessibility = await Task.detached {
            let process = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            AXUIElementSetMessagingTimeout(process, 3)
            var windows: CFTypeRef?
            return AXUIElementCopyAttributeValue(process, kAXWindowsAttribute as CFString, &windows)
        }.value
        try expect(accessibility == .success,
                   "The offscreen fixture exposes its own native accessibility hierarchy")
        await settle(hosting)
        try expect(window.frame.maxX < 0 && !window.isKeyWindow && !NSApplication.shared.isActive,
                   "Preview fixtures stay offscreen, non-key and inactive")
        try await body(hosting, window)
    }

    private static func click(_ button: DetailPreviewAXNode, in window: NSWindow) throws {
        let screenPoint = NSPoint(x: button.frame.midX, y: button.frame.midY)
        let point = window.convertPoint(fromScreen: screenPoint)
        let timestamp = ProcessInfo.processInfo.systemUptime
        guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
            timestamp: timestamp, windowNumber: window.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1),
              let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [],
            timestamp: timestamp + 0.02, windowNumber: window.windowNumber, context: nil,
            eventNumber: 2, clickCount: 1, pressure: 0) else {
            throw NSError(domain: "DetailPreviewInteractionTests", code: 9)
        }
        // Native NSButton tracking can consume the matching mouse-up while
        // mouseDown runs. Queue it only in this test process, for this window;
        // otherwise dispatch the unconsumed event directly to the same window.
        NSApplication.shared.postEvent(up, atStart: true)
        window.sendEvent(down)
        if let remaining = NSApplication.shared.nextEvent(matching: .leftMouseUp, until: Date(),
                                                          inMode: .default, dequeue: true) {
            try expect(remaining.windowNumber == window.windowNumber,
                       "The synthetic preview click belongs only to its own fixture window")
            window.sendEvent(remaining)
        }
    }

    private static func fixture(store: CaptureStore, kind: CaptureKind, filename: String,
                                data: Data, thumbnail: Data? = nil) throws -> Capture {
        let id = UUID()
        let path = "Originals/\(id.uuidString)/\(CaptureClassifier.storageFilename(filename))"
        let capture = Capture(id: id, kind: kind, attachmentRelativePath: path,
                              originalFilename: filename, title: filename)
        let url = store.root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        if let thumbnail {
            let path = "Previews/\(id.uuidString)/thumbnail.png"
            let url = store.root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try thumbnail.write(to: url)
            capture.thumbnailRelativePath = path
            capture.previewState = "ready"
        }
        return capture
    }

    private static func png() throws -> Data {
        guard let context = CGContext(data: nil, width: 120, height: 80, bitsPerComponent: 8,
            bytesPerRow: 480, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw NSError(domain: "DetailPreviewInteractionTests", code: 3)
        }
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        let data = NSMutableData()
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
            throw NSError(domain: "DetailPreviewInteractionTests", code: 4)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "DetailPreviewInteractionTests", code: 5) }
        return data as Data
    }

    private static func pdf() throws -> Data {
        let document = PDFDocument()
        for color in [NSColor.systemPurple, .systemBlue] {
            let image = NSImage(size: NSSize(width: 300, height: 420), flipped: false) { bounds in
                NSColor.white.setFill(); bounds.fill()
                color.setFill(); bounds.insetBy(dx: 20, dy: 20).fill()
                return true
            }
            guard let page = PDFPage(image: image) else { throw NSError(domain: "DetailPreviewInteractionTests", code: 6) }
            document.insert(page, at: document.pageCount)
        }
        guard let data = document.dataRepresentation() else { throw NSError(domain: "DetailPreviewInteractionTests", code: 7) }
        return data
    }

    private static func checkOpener(store: CaptureStore, capture: Capture, label: String) async throws {
        var opens = 0
        try await withPreview(store: store, capture: capture, opener: { opens += 1 }) { hosting, window in
            let container = try await find(hosting, id: "detail-preview")
            let button = try await find(hosting, id: "detail-preview-open-original")
            try expect(container.frame.width > 0 && container.frame.height > 0,
                       "\(label) keeps the existing preview geometry identifier")
            try expect(button.role == NSAccessibility.Role.button.rawValue && button.frame.width > 0 && button.frame.height > 0,
                       "\(label) exposes its visible preview as a real native accessible button")
            try expect(button.label.localizedCaseInsensitiveContains("open")
                && button.label.localizedCaseInsensitiveContains("original"),
                       "\(label) describes the open-original action to assistive technology")
            try expect(button.help.localizedCaseInsensitiveContains("open"),
                       "\(label) provides discoverable open-file hover help")
            try expect(opens == 0, "Rendering the \(label) preview does not open a file")
            try expect(button.press(), "\(label) preview supports the native accessibility press action")
            await settle(hosting)
            try expect(opens == 1, "One \(label) preview press invokes its opener exactly once")
            opens = 0
            try click(button, in: window)
            await settle(hosting)
            try expect(opens == 1, "One \(label) preview mouse click invokes its opener exactly once")
            try expect(!window.isKeyWindow && !NSApplication.shared.isActive,
                       "The \(label) fixture click never activates the app or takes focus")
        }
    }

    private static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinDetailPreviewInteraction-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "DaBinDetailPreviewInteraction.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let store = try CaptureStore(root: root.appendingPathComponent("Archive"))
        let thumbnail = try png()
        let image = try fixture(store: store, kind: .image, filename: "Synthetic preview.png", data: thumbnail)
        let document = try fixture(store: store, kind: .document, filename: "Synthetic document.rtf",
                                   data: Data("{\\rtf1 A synthetic document}".utf8), thumbnail: thumbnail)
        let generic = try fixture(store: store, kind: .file, filename: "Synthetic original.bin",
                                  data: Data([0, 1, 2, 3]))
        let pdfCapture = try fixture(store: store, kind: .pdf, filename: "Synthetic two-page.pdf", data: pdf())
        let illustrator = try fixture(store: store, kind: .ai, filename: "Synthetic vector.ai",
                                      data: Data("A synthetic vector placeholder".utf8), thumbnail: thumbnail)
        let video = try fixture(store: store, kind: .video, filename: "Synthetic thumbnail.mov",
                                data: Data([0, 1, 2, 3]), thumbnail: thumbnail)

        try await checkOpener(store: store, capture: image, label: "Image")
        try await checkOpener(store: store, capture: document, label: "Document thumbnail")
        try await checkOpener(store: store, capture: generic, label: "Generic file placeholder")
        try await checkOpener(store: store, capture: pdfCapture, label: "PDF")
        try await checkOpener(store: store, capture: illustrator, label: "Vector document thumbnail")
        try await checkOpener(store: store, capture: video, label: "Video thumbnail")

        try await withPreview(store: store, capture: pdfCapture, opener: {}) { hosting, _ in
            let pageControls = nodes(hosting).filter { ["Previous PDF page", "Next PDF page"].contains($0.label) }
            try expect(pageControls.isEmpty,
                       "The open-file PDF preview has no inaccessible inline pagination buttons")
        }
        try await withPreview(store: store, capture: pdfCapture, opener: nil) { hosting, _ in
            let next = try await find(hosting, label: "Next PDF page")
            let controls = nodes(hosting)
            try expect(!controls.contains { $0.identifier == "detail-preview-open-original" },
                       "An unconfigured PDF preview remains passive instead of inventing an open action")
            try expect(controls.contains { $0.label == "Previous PDF page" } && next.press(),
                       "Passive PDF previews retain usable native page navigation")
            await settle(hosting)
            let pdf = pdfView(in: hosting)
            let pageIndex = pdf?.currentPage.flatMap { pdf?.document?.index(for: $0) }
            try expect(pageIndex == 1,
                       "Passive PDF navigation still reaches the next page")
        }
        try await withPreview(store: store, capture: image, opener: nil) { hosting, _ in
            try expect(!nodes(hosting).contains { $0.identifier == "detail-preview-open-original" },
                       "A preview without an opener callback does not expose a dead button")
        }

        var invalidOpens = 0
        let note = Capture(kind: .text, originalText: "A synthetic plain note", title: "Plain note")
        let noOriginal = Capture(kind: .image, title: "Thumbnail without original")
        noOriginal.thumbnailRelativePath = "Previews/\(noOriginal.id.uuidString)/thumbnail.png"
        let invalidOriginal = Capture(kind: .image, attachmentRelativePath: "../outside.png",
                                      originalFilename: "outside.png", title: "Invalid attachment")
        for capture in [note, noOriginal, invalidOriginal] {
            try await withPreview(store: store, capture: capture, opener: { invalidOpens += 1 }) { hosting, _ in
                try expect(!nodes(hosting).contains { $0.identifier == "detail-preview-open-original" },
                           "\(capture.title) has no actionable file preview without an owned original")
            }
        }
        try expect(invalidOpens == 0, "Missing and invalid attachment metadata cannot invoke the file opener")

        // File existence is checked by the open action, not by view-body I/O.
        // An owned original that vanished still offers an action so AppState can
        // show its normal missing-file message rather than silently doing nothing.
        try FileManager.default.removeItem(at: store.root.appendingPathComponent(image.attachmentRelativePath!))
        try await checkOpener(store: store, capture: image, label: "Missing owned image")
        let previews = PreviewService(store: store, defaults: defaults)
        defer { previews.shutdown() }
        let state = AppState(store: store, previews: previews,
            reminders: ReminderService(store: store, client: DetailPreviewReminderClient()))
        try await withPreview(store: store, capture: image, opener: { state.openOriginal(image) }) { hosting, _ in
            let button = try await find(hosting, id: "detail-preview-open-original")
            try expect(button.press(), "A missing-file preview still reaches the normal open-original action")
            await settle(hosting)
            try expect(state.status?.severity == .error && !(state.status?.text.isEmpty ?? true),
                       "The normal open-original action reports a missing file instead of silently doing nothing")
            try expect(image.attachmentRelativePath != nil && image.title == "Synthetic preview.png",
                       "A failed open preserves the capture and its original metadata")
        }
        print("PASS: \(checks) detail-preview native open-action checks; no external app launched")
    }
}
