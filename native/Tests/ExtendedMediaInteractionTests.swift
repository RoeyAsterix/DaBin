import AppKit
import ApplicationServices
import ImageIO
import PDFKit
import QuickLookUI
import SwiftUI

/// End-to-end media canvas coverage using only synthetic files and events inside
/// this process. No external application, network request, or global input is used.
private final class SyntheticCanvasEvent: NSEvent {
    private let eventType: NSEvent.EventType
    private weak var targetWindow: NSWindow?
    private let point: NSPoint
    private let zoomDelta: CGFloat
    private let scrollX: CGFloat
    private let scrollY: CGFloat
    private let precise: Bool
    private let clicks: Int
    private let movementX: CGFloat
    private let movementY: CGFloat
    private let flags: NSEvent.ModifierFlags

    init(type: NSEvent.EventType, window: NSWindow?, location: NSPoint,
         magnification: CGFloat = 0, scrollX: CGFloat = 0, scrollY: CGFloat = 0,
         precise: Bool = false, clickCount: Int = 0, deltaX: CGFloat = 0,
         deltaY: CGFloat = 0, flags: NSEvent.ModifierFlags = []) {
        eventType = type
        targetWindow = window
        point = location
        zoomDelta = magnification
        self.scrollX = scrollX
        self.scrollY = scrollY
        self.precise = precise
        clicks = clickCount
        movementX = deltaX
        movementY = deltaY
        self.flags = flags
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used by this fixture") }
    override var type: NSEvent.EventType { eventType }
    override var window: NSWindow? { targetWindow }
    override var windowNumber: Int { targetWindow?.windowNumber ?? 0 }
    override var timestamp: TimeInterval { ProcessInfo.processInfo.systemUptime }
    override var locationInWindow: NSPoint { point }
    override var magnification: CGFloat { zoomDelta }
    override var scrollingDeltaX: CGFloat { scrollX }
    override var scrollingDeltaY: CGFloat { scrollY }
    override var hasPreciseScrollingDeltas: Bool { precise }
    override var clickCount: Int { clicks }
    override var deltaX: CGFloat { movementX }
    override var deltaY: CGFloat { movementY }
    override var modifierFlags: NSEvent.ModifierFlags { flags }
}

@MainActor
private struct MediaAXNode {
    let object: NSObject

    private func value(_ selectorName: String) -> Any? {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue()
    }

    private func attribute(_ name: String) -> Any? {
        let selector = NSSelectorFromString("accessibilityAttributeValue:")
        guard object.responds(to: selector),
              (value("accessibilityAttributeNames") as? [String])?.contains(name) == true else { return nil }
        return object.perform(selector, with: name as NSString)?.takeUnretainedValue()
    }

    var identifier: String? {
        (value("accessibilityIdentifier") as? String) ?? (attribute("AXIdentifier") as? String)
    }

    var label: String {
        [value("accessibilityLabel"), value("accessibilityTitle"), attribute("AXTitle"),
         attribute("AXDescription"), attribute("AXValue")]
            .compactMap { $0 as? String }.first { !$0.isEmpty } ?? ""
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

    func press() -> Bool {
        let selector = NSSelectorFromString("accessibilityPerformPress")
        guard object.responds(to: selector) else { return false }
        typealias Action = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(object.method(for: selector), to: Action.self)(object, selector)
    }
}

@main @MainActor
private final class ExtendedMediaInteractionTests: NSObject, NSApplicationDelegate {
    private static var checks = 0
    private var result = 0

    static func main() {
        let application = NSApplication.shared
        let delegate = ExtendedMediaInteractionTests()
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
                fputs("Extended media interaction QA failed: \(error)\n", stderr)
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
            throw NSError(domain: "ExtendedMediaInteractionTests", code: checks,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private static func close(_ lhs: CGFloat, _ rhs: CGFloat, tolerance: CGFloat = 0.02) -> Bool {
        abs(lhs - rhs) <= tolerance
    }

    private static func settle(_ view: NSView, rounds: Int = 5) async {
        for _ in 0..<rounds {
            view.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(45))
        }
    }

    private static func waitUntil(_ view: NSView, _ predicate: () -> Bool) async -> Bool {
        for _ in 0..<40 {
            view.layoutSubtreeIfNeeded()
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return predicate()
    }

    private static func descendants<T: NSView>(of type: T.Type, in view: NSView) -> [T] {
        var result = view as? T == nil ? [] : [view as! T]
        for child in view.subviews { result += descendants(of: type, in: child) }
        return result
    }

    private static func view(named fragment: String, in root: NSView) -> NSView? {
        if String(describing: type(of: root)).contains(fragment) { return root }
        return root.subviews.lazy.compactMap { view(named: fragment, in: $0) }.first
    }

    private static func nodes(_ view: NSView) -> [MediaAXNode] {
        var seen = Set<ObjectIdentifier>()
        var result: [MediaAXNode] = []
        func visit(_ value: Any, depth: Int) {
            guard depth < 40, let object = value as? NSObject,
                  seen.insert(ObjectIdentifier(object)).inserted else { return }
            let node = MediaAXNode(object: object)
            result.append(node)
            node.children.forEach { visit($0, depth: depth + 1) }
        }
        visit(view, depth: 0)
        NSAccessibility.unignoredChildren(from: [view]).forEach { visit($0, depth: 0) }
        return result
    }

    private static func node(_ id: String, in view: NSView) async -> MediaAXNode? {
        for _ in 0..<12 {
            if let match = nodes(view).first(where: { $0.identifier == id }) { return match }
            await settle(view, rounds: 1)
        }
        return nil
    }

    private static func withCanvas(store: CaptureStore, capture: Capture, zoom: CaptureZoomState,
                                   size: CGSize = CGSize(width: 680, height: 520),
                                   body: (NSHostingView<AnyView>, NSWindow) async throws -> Void) async throws {
        let root = AnyView(VStack(spacing: 8) {
            CaptureZoomControls(zoom: zoom)
            ExtendedCaptureCanvas(store: store, capture: capture, zoom: zoom)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(8)
        .frame(width: size.width, height: size.height))
        let hosting = NSHostingView(rootView: root)
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.wantsLayer = true
        let window = NSWindow(contentRect: CGRect(x: -9_000, y: -9_000,
                                                  width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFront(nil)
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        await settle(hosting)
        // SwiftUI creates several button accessibility proxies only after an
        // accessibility client requests this process's window hierarchy.
        let accessibility = await Task.detached {
            let application = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            AXUIElementSetMessagingTimeout(application, 3)
            var windows: CFTypeRef?
            return AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &windows)
        }.value
        try expect(accessibility == .success,
                   "The ordered fixture exposes its own native accessibility hierarchy")
        await settle(hosting)
        try await body(hosting, window)
    }

    private static func fixture(store: CaptureStore, kind: CaptureKind, filename: String,
                                data: Data, contentType: String) throws -> Capture {
        let id = UUID()
        let relative = "Originals/\(id.uuidString)/\(CaptureClassifier.storageFilename(filename))"
        let capture = Capture(id: id, kind: kind, attachmentRelativePath: relative,
                              originalFilename: filename, contentType: contentType,
                              byteCount: Int64(data.count), title: filename)
        let url = store.root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: url)
        return capture
    }

    private static func imageData() throws -> Data {
        let width = 800, height = 500
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw NSError(domain: "ExtendedMediaInteractionTests", code: 100)
        }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let markers: [(CGColor, CGRect)] = [
            (markerColors[0].cgColor, CGRect(x: 0, y: 0, width: 110, height: 110)),
            (markerColors[1].cgColor, CGRect(x: width - 110, y: 0, width: 110, height: 110)),
            (markerColors[2].cgColor, CGRect(x: 0, y: height - 110, width: 110, height: 110)),
            (markerColors[3].cgColor, CGRect(x: width - 110, y: height - 110, width: 110, height: 110))
        ]
        for (color, rect) in markers { context.setFillColor(color); context.fill(rect) }
        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(x: width / 2 - 30, y: height / 2 - 30, width: 60, height: 60))
        guard let image = context.makeImage() else { throw NSError(domain: "ExtendedMediaInteractionTests", code: 101) }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else {
            throw NSError(domain: "ExtendedMediaInteractionTests", code: 102)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "ExtendedMediaInteractionTests", code: 103)
        }
        return output as Data
    }

    private static var markerColors: [NSColor] {
        [NSColor(srgbRed: 0.92, green: 0.08, blue: 0.10, alpha: 1),
         NSColor(srgbRed: 0.08, green: 0.76, blue: 0.20, alpha: 1),
         NSColor(srgbRed: 0.08, green: 0.30, blue: 0.92, alpha: 1),
         NSColor(srgbRed: 0.96, green: 0.78, blue: 0.05, alpha: 1)]
    }

    private static func pdfData() throws -> Data {
        let document = PDFDocument()
        for (index, size) in [CGSize(width: 640, height: 900), CGSize(width: 900, height: 640)].enumerated() {
            let image = NSImage(size: size, flipped: false) { bounds in
                NSColor.white.setFill(); bounds.fill()
                let colors: [NSColor] = [.systemRed, .systemGreen, .systemBlue, .systemYellow]
                let points = [CGPoint(x: 0, y: 0), CGPoint(x: bounds.width - 72, y: 0),
                              CGPoint(x: 0, y: bounds.height - 72),
                              CGPoint(x: bounds.width - 72, y: bounds.height - 72)]
                for (color, point) in zip(colors, points) {
                    color.setFill(); CGRect(origin: point, size: CGSize(width: 72, height: 72)).fill()
                }
                let label = "MEDIA BOX PAGE \(index + 1)"
                label.draw(at: CGPoint(x: 90, y: bounds.midY),
                           withAttributes: [.font: NSFont.boldSystemFont(ofSize: 32),
                                            .foregroundColor: NSColor.black])
                return true
            }
            guard let page = PDFPage(image: image) else {
                throw NSError(domain: "ExtendedMediaInteractionTests", code: 104)
            }
            page.setBounds(CGRect(origin: .zero, size: size), for: .mediaBox)
            page.setBounds(CGRect(x: 42, y: 54, width: size.width - 84, height: size.height - 108),
                           for: .cropBox)
            document.insert(page, at: document.pageCount)
        }
        guard let data = document.dataRepresentation() else {
            throw NSError(domain: "ExtendedMediaInteractionTests", code: 105)
        }
        return data
    }

    private static func rtfData() throws -> Data {
        let text = NSAttributedString(string: "LOCAL RTF PREVIEW\n\nSelectable native document text.",
            attributes: [.font: NSFont.systemFont(ofSize: 24),
                         .foregroundColor: NSColor.systemPurple])
        return try text.data(from: NSRange(location: 0, length: text.length),
                             documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }

    @discardableResult
    private static func render(_ view: NSView, name: String) throws -> NSBitmapImageRep {
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw NSError(domain: "ExtendedMediaInteractionTests", code: 106,
                          userInfo: [NSLocalizedDescriptionKey: "Could not allocate render for \(name)"])
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DABIN_EXTENDED_MEDIA_QA_OUTPUT"]
                            ?? "/private/tmp/dabin-extended-media-qa", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "ExtendedMediaInteractionTests", code: 107)
        }
        try png.write(to: directory.appendingPathComponent(name + ".png"), options: .atomic)
        return bitmap
    }

    private static func markerPixelCounts(in bitmap: NSBitmapImageRep) throws -> [Int] {
        guard let image = bitmap.cgImage,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw NSError(domain: "ExtendedMediaInteractionTests", code: 115,
                          userInfo: [NSLocalizedDescriptionKey: "The evidence render has no CGImage"])
        }
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else {
            throw NSError(domain: "ExtendedMediaInteractionTests", code: 116,
                          userInfo: [NSLocalizedDescriptionKey: "Could not normalize the render to 8-bit sRGB"])
        }
        let expected: [(Int, Int, Int)] = markerColors.map { color in
            let converted = color.usingColorSpace(.sRGB) ?? color
            return (Int((converted.redComponent * 255).rounded()),
                    Int((converted.greenComponent * 255).rounded()),
                    Int((converted.blueComponent * 255).rounded()))
        }
        var counts = [Int](repeating: 0, count: expected.count)
        for offset in stride(from: 0, to: pixels.count, by: 4) where pixels[offset + 3] > 220 {
            let red = Int(pixels[offset])
            let green = Int(pixels[offset + 1])
            let blue = Int(pixels[offset + 2])
            var nearest = -1
            var nearestDistance = Int.max
            for (index, target) in expected.enumerated() {
                let dr = red - target.0
                let dg = green - target.1
                let db = blue - target.2
                let distance = dr * dr + dg * dg + db * db
                if distance < nearestDistance { nearest = index; nearestDistance = distance }
            }
            // Marker interiors are exact. This tolerance includes only their
            // antialiased boundary, not similarly colored application chrome.
            if nearestDistance <= 32 * 32 { counts[nearest] += 1 }
        }
        return counts
    }

    private static func centerInWindow(_ view: NSView) -> NSPoint {
        view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
    }

    private static func checkImage(store: CaptureStore, capture: Capture) async throws {
        let zoom = CaptureZoomState()
        try await withCanvas(store: store, capture: capture, zoom: zoom) { hosting, window in
            let imageLoaded = await waitUntil(hosting) {
                close(zoom.contentSize.width, 800, tolerance: 0.5) &&
                    close(zoom.contentSize.height, 500, tolerance: 0.5)
            }
            try expect(imageLoaded,
                "The image canvas decodes the complete 800 by 500 original")
            let expectedFit = min(zoom.viewportSize.width / 800, zoom.viewportSize.height / 500)
            try expect(zoom.mode == .fit && close(zoom.scale, expectedFit),
                       "Fit uses the complete original extent")
            try expect(zoom.scaledContentSize.width <= zoom.viewportSize.width + 1 &&
                       zoom.scaledContentSize.height <= zoom.viewportSize.height + 1,
                       "Fit never crops either image axis")
            let fit = try render(hosting, name: "image-fit-complete")
            let markerCounts = try markerPixelCounts(in: fit)
            try expect(markerCounts.allSatisfy { $0 > 500 },
                       "Fit render retains a substantial area from every colored corner marker: \(markerCounts)")
            let smallestMarker = markerCounts.min() ?? 0
            let largestMarker = markerCounts.max() ?? 0
            try expect(smallestMarker > 0 && CGFloat(largestMarker) / CGFloat(smallestMarker) <= 1.10,
                       "Fit renders all four equal corner markers without clipping an edge: \(markerCounts)")

            guard let interaction = descendants(of: CaptureZoomInteractionView.self, in: hosting).first else {
                throw NSError(domain: "ExtendedMediaInteractionTests", code: 108,
                              userInfo: [NSLocalizedDescriptionKey: "Missing image interaction surface"])
            }
            let center = centerInWindow(interaction)
            let wheel = SyntheticCanvasEvent(type: .scrollWheel, window: window, location: center,
                                             scrollY: 2, precise: false)
            let beforeWheel = zoom.scale
            interaction.scrollWheel(with: wheel)
            try expect(zoom.scale > beforeWheel && zoom.mode == .custom,
                       "A native mouse wheel event zooms the image")
            let beforePinch = zoom.scale
            interaction.magnify(with: SyntheticCanvasEvent(type: .magnify, window: window,
                location: center, magnification: 0.2))
            try expect(zoom.scale > beforePinch, "A native magnify event zooms around the pointer")

            interaction.mouseDown(with: SyntheticCanvasEvent(type: .leftMouseDown, window: window,
                location: center, clickCount: 2))
            try expect(zoom.mode == .fit, "Double-click returns a custom image view to Fit")
            interaction.mouseDown(with: SyntheticCanvasEvent(type: .leftMouseDown, window: window,
                location: center, clickCount: 2))
            try expect(zoom.mode == .native100 && close(zoom.scale, 1),
                       "A second double-click shows the original at 100 percent")
            try expect(zoom.canPan, "The complete original can pan at 100 percent when larger than the viewport")
            interaction.mouseDown(with: SyntheticCanvasEvent(type: .leftMouseDown, window: window,
                location: center, clickCount: 1))
            interaction.mouseDragged(with: SyntheticCanvasEvent(type: .leftMouseDragged, window: window,
                location: NSPoint(x: center.x + 44, y: center.y + 28), deltaX: 44, deltaY: 28))
            interaction.mouseUp(with: SyntheticCanvasEvent(type: .leftMouseUp, window: window,
                location: NSPoint(x: center.x + 44, y: center.y + 28)))
            try expect(abs(zoom.pan.width) > 1 || abs(zoom.pan.height) > 1,
                       "A native mouse drag pans the 100 percent image")
            _ = try render(hosting, name: "image-native-100-panned")
        }
    }

    private static func checkPDF(store: CaptureStore, capture: Capture) async throws {
        let zoom = CaptureZoomState()
        try await withCanvas(store: store, capture: capture, zoom: zoom) { hosting, _ in
            let pdfLoaded = await waitUntil(hosting) {
                zoom.pdfPageCount == 2 && descendants(of: PDFView.self, in: hosting).first?.document?.pageCount == 2
            }
            try expect(pdfLoaded,
                "The native PDF canvas loads both pages")
            guard let pdf = descendants(of: PDFView.self, in: hosting).first,
                  let document = pdf.document, let first = document.page(at: 0) else {
                throw NSError(domain: "ExtendedMediaInteractionTests", code: 109)
            }
            try expect(pdf.displayBox == .mediaBox, "PDFKit displays the complete media box")
            try expect(first.bounds(for: .mediaBox) != first.bounds(for: .cropBox),
                       "The fixture proves media-box rendering is distinct from the crop box")
            try expect(close(first.bounds(for: .mediaBox).width, 640, tolerance: 1) &&
                       close(first.bounds(for: .mediaBox).height, 900, tolerance: 1),
                       "The first complete PDF page keeps its authored extent")
            try expect(pdf.autoScales && zoom.mode == .fit, "PDF starts in native Fit mode")
            _ = try render(hosting, name: "pdf-page-1-media-box-fit")

            zoom.nextPDFPage()
            await settle(hosting)
            try expect(zoom.pdfPage == 1 && pdf.currentPage === document.page(at: 1),
                       "PDF page navigation keeps state and PDFKit on page two")
            try expect(close(zoom.contentSize.width, 900, tolerance: 1) &&
                       close(zoom.contentSize.height, 640, tolerance: 1),
                       "Page two Fit geometry uses its landscape media box")
            let beforeZoom = pdf.scaleFactor
            guard let zoomIn = await node("capture-zoom-in", in: hosting) else {
                throw NSError(domain: "ExtendedMediaInteractionTests", code: 114,
                              userInfo: [NSLocalizedDescriptionKey: "Missing PDF zoom control"])
            }
            try expect(zoomIn.press(), "The PDF zoom control is a native actionable button")
            await settle(hosting, rounds: 2)
            try expect(!pdf.autoScales && pdf.scaleFactor > beforeZoom && zoom.mode == .custom,
                       "Native PDF zoom leaves Fit and increases the rendered page scale")
            try expect(close(zoom.scale, pdf.scaleFactor, tolerance: 0.03),
                       "The durable zoom state follows PDFKit magnification")
            _ = try render(hosting, name: "pdf-page-2-native-zoom")
        }
    }

    private static func sendPassive(_ event: NSEvent) {
        NSApplication.shared.sendEvent(event)
    }

    private static func checkText(store: CaptureStore) async throws {
        let sentinel = "VECTOR TEXT TAIL 9173"
        let text = (["Native vector text remains selectable and reflows while zooming."] +
                    Array(repeating: "A complete line with שלום and 日本語.", count: 22) + [sentinel])
            .joined(separator: "\n")
        let capture = Capture(kind: .text, originalText: text, title: "Native text fixture")
        let zoom = CaptureZoomState()
        try await withCanvas(store: store, capture: capture, zoom: zoom) { hosting, window in
            let textLoaded = await waitUntil(hosting) { zoom.isTextContent && zoom.viewportSize.width > 0 }
            try expect(textLoaded,
                       "Text canvas identifies native textual content")
            try expect(nodes(hosting).contains { $0.identifier == "capture-extended-text" ||
                $0.label.contains("Capture text") }, "The native text surface is accessible")
            guard let passive = view(named: "CaptureZoomPassiveInputView", in: hosting) else {
                throw NSError(domain: "ExtendedMediaInteractionTests", code: 110,
                              userInfo: [NSLocalizedDescriptionKey: "Missing text input monitor surface"])
            }
            let center = centerInWindow(passive)
            let beforeWheel = zoom.scale
            sendPassive(SyntheticCanvasEvent(type: .scrollWheel, window: window, location: center,
                                             scrollY: 2, precise: false))
            await settle(hosting, rounds: 1)
            try expect(zoom.scale > beforeWheel && zoom.mode == .custom,
                       "A native wheel event zooms reflowed text")
            let beforePinch = zoom.scale
            sendPassive(SyntheticCanvasEvent(type: .magnify, window: window, location: center,
                                             magnification: 0.15))
            await settle(hosting, rounds: 1)
            try expect(zoom.scale > beforePinch, "A native pinch event zooms text without a screenshot")
            let clickTime = ProcessInfo.processInfo.systemUptime
            guard let doubleClick = NSEvent.mouseEvent(with: .leftMouseDown, location: center,
                modifierFlags: [], timestamp: clickTime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 91,
                clickCount: 2, pressure: 1),
                  let mouseUp = NSEvent.mouseEvent(with: .leftMouseUp, location: center,
                modifierFlags: [], timestamp: clickTime + 0.02,
                windowNumber: window.windowNumber, context: nil, eventNumber: 92,
                clickCount: 2, pressure: 0) else {
                throw NSError(domain: "ExtendedMediaInteractionTests", code: 113)
            }
            // NSTextView enters a native tracking loop for the forwarded
            // double-click. Queue its matching release before dispatching the
            // down event so that loop cannot block the fixture run.
            NSApplication.shared.postEvent(mouseUp, atStart: true)
            sendPassive(doubleClick)
            if let remaining = NSApplication.shared.nextEvent(matching: .leftMouseUp, until: Date(),
                                                               inMode: .default, dequeue: true) {
                try expect(remaining.windowNumber == window.windowNumber,
                           "The text double-click release belongs to its fixture window")
                window.sendEvent(remaining)
            }
            await settle(hosting, rounds: 1)
            try expect(zoom.mode == .fit && close(zoom.scale, 1),
                       "Double-click returns vector text to Fit")

            guard let largerText = await node("capture-text-size-increase", in: hosting) else {
                throw NSError(domain: "ExtendedMediaInteractionTests", code: 111,
                              userInfo: [NSLocalizedDescriptionKey: "Missing text-size control"])
            }
            let beforeFont = zoom.textFontSize
            try expect(largerText.press(), "The native A+ text-size control is actionable")
            await settle(hosting, rounds: 1)
            try expect(zoom.textFontSize == beforeFont + 1,
                       "Text size changes native font metrics independently of image pixels")
            try expect(nodes(hosting).contains { $0.label.contains(sentinel) || $0.label.contains("Native vector text") },
                       "The complete text remains represented in the native accessibility tree")
            _ = try render(hosting, name: "text-native-font-and-zoom")
        }
    }

    private static func checkQuickLook(store: CaptureStore, capture: Capture) async throws {
        let zoom = CaptureZoomState()
        try await withCanvas(store: store, capture: capture, zoom: zoom) { hosting, _ in
            let quickLookLoaded = await waitUntil(hosting) {
                !descendants(of: QLPreviewView.self, in: hosting).isEmpty
            }
            try expect(quickLookLoaded,
                       "A local RTF uses the native Quick Look document surface")
            guard let preview = descendants(of: QLPreviewView.self, in: hosting).first else {
                throw NSError(domain: "ExtendedMediaInteractionTests", code: 112)
            }
            let initial = preview.frame.size
            zoom.zoomIn()
            await settle(hosting)
            try expect(preview.frame.width > initial.width && preview.frame.height > initial.height,
                       "Quick Look redraws a larger native document surface when zooming")
            try expect(zoom.mode == .custom && zoom.scale > 1,
                       "Quick Look zoom is retained in the shared capture state")
        }
    }

    private static func run() async throws {
        fputs("Extended media QA: fixtures\n", stderr)
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("DaBinExtendedMedia-\(UUID().uuidString)", isDirectory: true)
        let store = try CaptureStore(root: temporaryRoot, repairArchiveOnOpen: false)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let image = try fixture(store: store, kind: .image, filename: "complete-corners.png",
                                data: imageData(), contentType: "image/png")
        let pdf = try fixture(store: store, kind: .pdf, filename: "two-media-box-pages.pdf",
                              data: pdfData(), contentType: "application/pdf")
        let rtf = try fixture(store: store, kind: .document, filename: "local-preview.rtf",
                              data: rtfData(), contentType: "application/rtf")

        fputs("Extended media QA: image\n", stderr)
        try await checkImage(store: store, capture: image)
        fputs("Extended media QA: PDF\n", stderr)
        try await checkPDF(store: store, capture: pdf)
        fputs("Extended media QA: text\n", stderr)
        try await checkText(store: store)
        fputs("Extended media QA: Quick Look\n", stderr)
        try await checkQuickLook(store: store, capture: rtf)
        print("Extended media interaction QA passed (\(checks) checks); renders: /private/tmp/dabin-extended-media-qa")
    }
}
