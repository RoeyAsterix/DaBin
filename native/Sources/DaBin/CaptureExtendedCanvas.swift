import AppKit
import AVKit
import PDFKit
import QuickLookUI
import SwiftUI

enum CaptureZoomMode: String, Sendable {
    case fit
    case native100
    case custom
}

/// Durable, content-independent state for the extended capture canvas. The owner
/// keeps one instance for as long as the capture tab should retain its position.
@MainActor
final class CaptureZoomState: ObservableObject {
    static let minimumScale: CGFloat = 0.05
    static let maximumScale: CGFloat = 16
    static let defaultTextFontSize: CGFloat = 16
    static let minimumTextFontSize: CGFloat = 11
    static let maximumTextFontSize: CGFloat = 40

    @Published private(set) var mode: CaptureZoomMode
    @Published private(set) var scale: CGFloat
    @Published private(set) var pan: CGSize = .zero
    @Published private(set) var viewportSize: CGSize = .zero
    @Published private(set) var contentSize: CGSize = .zero
    @Published private(set) var pdfPage = 0
    @Published private(set) var pdfPageCount = 0
    @Published private(set) var textFontSize: CGFloat
    @Published private(set) var isTextContent = false
    var quickLookDisplayState: Any?

    init(mode: CaptureZoomMode = .fit, textFontSize: CGFloat = 16) {
        self.mode = mode
        self.scale = 1
        self.textFontSize = Self.clampTextFont(textFontSize)
    }

    var zoomPercent: Int { Int((scale * 100).rounded()) }
    var canZoomIn: Bool { scale < Self.maximumScale }
    var canZoomOut: Bool { scale > Self.minimumScale }
    var canPan: Bool {
        scaledContentSize.width > viewportSize.width + 0.5 ||
            scaledContentSize.height > viewportSize.height + 0.5
    }
    var scaledContentSize: CGSize {
        CGSize(width: contentSize.width * scale, height: contentSize.height * scale)
    }

    /// Geometry can change while a tab is hidden or the board is resized. Fit
    /// follows the new viewport; custom and 100% views retain their zoom and
    /// clamp only the now-unreachable part of their pan.
    func updateGeometry(viewport: CGSize, content: CGSize) {
        viewportSize = Self.validSize(viewport)
        contentSize = Self.validSize(content)
        switch mode {
        case .fit:
            scale = fittedScale
            pan = .zero
        case .native100:
            scale = 1
            pan = clampedPan(pan)
        case .custom:
            scale = Self.clampScale(scale)
            pan = clampedPan(pan)
        }
    }

    func fitToScreen() {
        mode = .fit
        scale = fittedScale
        pan = .zero
    }

    func showNative100() {
        mode = .native100
        scale = 1
        pan = .zero
    }

    func reset() {
        pdfPage = 0
        textFontSize = Self.defaultTextFontSize
        fitToScreen()
    }

    func toggleFitAnd100() {
        if mode == .fit { showNative100() }
        else { fitToScreen() }
    }

    func zoomIn(anchor: CGPoint? = nil) { zoom(by: 1.25, anchor: anchor) }
    func zoomOut(anchor: CGPoint? = nil) { zoom(by: 0.8, anchor: anchor) }

    /// `anchor` uses viewport coordinates with a top-left origin, matching AppKit
    /// input events after their coordinate conversion. The content under that
    /// point stays under the pointer while zoom changes.
    func zoom(by factor: CGFloat, anchor: CGPoint? = nil) {
        guard factor.isFinite, factor > 0 else { return }
        let oldScale = max(Self.minimumScale, scale)
        let nextScale = Self.clampScale(oldScale * factor)
        mode = .custom
        guard nextScale != oldScale else {
            scale = nextScale
            pan = clampedPan(pan)
            return
        }
        if let anchor, viewportSize.width > 0, viewportSize.height > 0 {
            let relative = CGPoint(x: anchor.x - viewportSize.width / 2,
                                   y: anchor.y - viewportSize.height / 2)
            let ratio = nextScale / oldScale
            pan = CGSize(width: relative.x - (relative.x - pan.width) * ratio,
                         height: relative.y - (relative.y - pan.height) * ratio)
        }
        scale = nextScale
        pan = clampedPan(pan)
    }

    /// Keeps native PDFKit magnification in the same durable state as toolbar
    /// and image-canvas zoom without replacing the user's current page.
    func adoptNativeScale(_ value: CGFloat) {
        guard value.isFinite, value > 0 else { return }
        let next = Self.clampScale(value)
        guard abs(next - scale) > 0.0001 || mode != .custom else { return }
        mode = .custom
        scale = next
        pan = clampedPan(pan)
    }

    /// PDFKit computes fit using its own page insets. Keep that exact native
    /// result visible in the toolbar without turning Fit into custom zoom.
    func adoptFittedScale(_ value: CGFloat) {
        guard mode == .fit, value.isFinite, value > 0 else { return }
        let next = Self.clampScale(value)
        guard abs(next - scale) > 0.0001 else { return }
        scale = next
        pan = .zero
    }

    func setPan(_ value: CGSize) {
        guard value.width.isFinite, value.height.isFinite else { return }
        pan = clampedPan(value)
    }

    func pan(by translation: CGSize) {
        guard translation.width.isFinite, translation.height.isFinite else { return }
        setPan(CGSize(width: pan.width + translation.width,
                      height: pan.height + translation.height))
    }

    func setPDFPageCount(_ count: Int) {
        pdfPageCount = max(0, count)
        pdfPage = clampedPDFPage(pdfPage)
    }

    func showPDFPage(_ page: Int) { pdfPage = clampedPDFPage(page) }
    func previousPDFPage() { showPDFPage(pdfPage - 1) }
    func nextPDFPage() { showPDFPage(pdfPage + 1) }

    func setTextFontSize(_ value: CGFloat) { textFontSize = Self.clampTextFont(value) }
    func increaseTextSize() { setTextFontSize(textFontSize + 1) }
    func decreaseTextSize() { setTextFontSize(textFontSize - 1) }
    func setTextContent(_ value: Bool) { isTextContent = value }

    private var fittedScale: CGFloat {
        guard viewportSize.width > 0, viewportSize.height > 0,
              contentSize.width > 0, contentSize.height > 0 else { return 1 }
        return Self.clampScale(min(viewportSize.width / contentSize.width,
                                   viewportSize.height / contentSize.height))
    }

    private func clampedPan(_ candidate: CGSize) -> CGSize {
        let xLimit = max(0, (contentSize.width * scale - viewportSize.width) / 2)
        let yLimit = max(0, (contentSize.height * scale - viewportSize.height) / 2)
        return CGSize(width: min(xLimit, max(-xLimit, candidate.width)),
                      height: min(yLimit, max(-yLimit, candidate.height)))
    }

    private func clampedPDFPage(_ page: Int) -> Int {
        guard pdfPageCount > 0 else { return 0 }
        return min(pdfPageCount - 1, max(0, page))
    }

    private static func validSize(_ size: CGSize) -> CGSize {
        CGSize(width: size.width.isFinite ? max(0, size.width) : 0,
               height: size.height.isFinite ? max(0, size.height) : 0)
    }

    private static func clampScale(_ value: CGFloat) -> CGFloat {
        min(maximumScale, max(minimumScale, value.isFinite ? value : 1))
    }

    private static func clampTextFont(_ value: CGFloat) -> CGFloat {
        min(maximumTextFontSize, max(minimumTextFontSize, value.isFinite ? value : defaultTextFontSize))
    }
}

enum CaptureZoomWheelIntent: Equatable {
    case zoom(CGFloat)
    case pan(CGSize)
}

/// Pure mapping kept separate from NSEvent so both pointer behavior and bounds
/// can be covered without synthesizing global input.
struct CaptureZoomNativeInput {
    static func wheelIntent(deltaX: CGFloat, deltaY: CGFloat, isPrecise: Bool,
                            forceZoom: Bool = false) -> CaptureZoomWheelIntent {
        if forceZoom || !isPrecise {
            let exponent = min(4, max(-4, deltaY)) * 0.08
            return .zoom(exp(exponent))
        }
        return .pan(CGSize(width: -deltaX, height: deltaY))
    }
}

@MainActor
struct CaptureZoomControls: View {
    @ObservedObject var zoom: CaptureZoomState

    var body: some View {
        HStack(spacing: 6) {
            Button(action: { zoom.zoomOut() }) { Image(systemName: "minus") }
                .disabled(!zoom.canZoomOut)
                .accessibilityLabel("Zoom out")
                .accessibilityIdentifier("capture-zoom-out")
            Text("\(zoom.zoomPercent)%")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .frame(minWidth: 44)
                .accessibilityLabel("Zoom \(zoom.zoomPercent) percent")
                .accessibilityIdentifier("capture-zoom-value")
            Button(action: { zoom.zoomIn() }) { Image(systemName: "plus") }
                .disabled(!zoom.canZoomIn)
                .accessibilityLabel("Zoom in")
                .accessibilityIdentifier("capture-zoom-in")
            Divider().frame(height: 18)
            Button { zoom.fitToScreen() } label: {
                ViewThatFits(in: .horizontal) {
                    Text("Fit to Screen")
                    Text("Fit")
                }
            }
                .accessibilityLabel("Fit to Screen")
                .accessibilityIdentifier("capture-zoom-fit")
            Button("100%") { zoom.showNative100() }
                .accessibilityLabel("Show at 100 percent")
                .accessibilityIdentifier("capture-zoom-100")
            Button("Reset") { zoom.reset() }
                .accessibilityLabel("Reset View")
                .accessibilityIdentifier("capture-zoom-reset")
            if zoom.isTextContent {
                Divider().frame(height: 18)
                Button(action: { zoom.decreaseTextSize() }) { Text("A−") }
                    .disabled(zoom.textFontSize <= CaptureZoomState.minimumTextFontSize)
                    .accessibilityLabel("Decrease text size")
                    .accessibilityIdentifier("capture-text-size-decrease")
                Button(action: { zoom.increaseTextSize() }) { Text("A+") }
                    .disabled(zoom.textFontSize >= CaptureZoomState.maximumTextFontSize)
                    .accessibilityLabel("Increase text size")
                    .accessibilityIdentifier("capture-text-size-increase")
            }
            if zoom.pdfPageCount > 1 {
                Divider().frame(height: 18)
                Button(action: { zoom.previousPDFPage() }) { Image(systemName: "chevron.left") }
                    .disabled(zoom.pdfPage == 0)
                    .accessibilityLabel("Previous PDF page")
                    .accessibilityIdentifier("capture-pdf-previous")
                Text("\(zoom.pdfPage + 1) / \(zoom.pdfPageCount)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .accessibilityLabel("Page \(zoom.pdfPage + 1) of \(zoom.pdfPageCount)")
                    .accessibilityIdentifier("capture-pdf-page")
                Button(action: { zoom.nextPDFPage() }) { Image(systemName: "chevron.right") }
                    .disabled(zoom.pdfPage + 1 >= zoom.pdfPageCount)
                    .accessibilityLabel("Next PDF page")
                    .accessibilityIdentifier("capture-pdf-next")
            }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Capture zoom controls")
    }
}

@MainActor
struct ExtendedCaptureCanvas: View {
    let store: CaptureStore
    @ObservedObject var capture: Capture
    @ObservedObject var zoom: CaptureZoomState

    var body: some View {
        Group {
            switch capture.kind {
            case .image:
                if let file = CapturePreviewFileReference.original(store: store, capture: capture) {
                    ExtendedCaptureImage(file: file, title: capture.title, zoom: zoom)
                } else { unavailable }
            case .pdf:
                if let url = store.managedURL(for: capture) {
                    ExtendedCapturePDF(url: url, zoom: zoom)
                } else { unavailable }
            case .video:
                if let url = store.managedURL(for: capture) {
                    ExtendedCaptureVideo(url: url, zoom: zoom)
                } else { unavailable }
            case .document, .ai, .file:
                if let url = store.managedURL(for: capture) {
                    ExtendedCaptureQuickLook(url: url, zoom: zoom)
                } else { unavailable }
            case .text, .task, .link:
                ExtendedCaptureText(text: displayedText, zoom: zoom)
            }
        }
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Extended capture: \(capture.title)")
        .accessibilityIdentifier("capture-extended-canvas")
        .onAppear { zoom.setTextContent(isTextual) }
        .onDisappear { zoom.setTextContent(false) }
    }

    private var isTextual: Bool { capture.kind == .text || capture.kind == .task || capture.kind == .link }

    private var displayedText: String {
        if capture.kind == .link {
            return [capture.title, capture.originalURL].compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }.joined(separator: "\n\n")
        }
        return capture.originalText.flatMap { $0.isEmpty ? nil : $0 }
            ?? (capture.indexedText.isEmpty ? nil : capture.indexedText)
            ?? (capture.previewDescription.isEmpty ? capture.title : capture.previewDescription)
    }

    private var unavailable: some View {
        ContentUnavailableView("Original unavailable", systemImage: "doc.questionmark",
                               description: Text("The saved capture details are still available."))
            .accessibilityIdentifier("capture-extended-unavailable")
    }
}

@MainActor
private struct ExtendedCaptureImage: View {
    let file: CapturePreviewFileReference
    let title: String
    @ObservedObject var zoom: CaptureZoomState
    @State private var image: NSImage?
    @State private var imageSize = CGSize.zero

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Palette.soft
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: imageSize.width, height: imageSize.height)
                        .scaleEffect(zoom.scale)
                        .offset(zoom.pan)
                        .accessibilityLabel(title)
                } else {
                    ProgressView().controlSize(.small).accessibilityLabel("Loading full image")
                }
                CaptureZoomInteractionSurface(zoom: zoom)
                    .accessibilityHidden(true)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .clipped()
            .onAppear { updateGeometry(geometry.size) }
            .onChange(of: geometry.size) { _, size in updateGeometry(size) }
            .onChange(of: imageSize) { _, _ in updateGeometry(geometry.size) }
        }
        .task(id: file) {
            image = nil
            imageSize = .zero
            let request = CapturePreviewImageRequest(file: file, maximumPixelSize: 8_192,
                                                     revision: "extended-original")
            guard let decoded = await CapturePreviewImageCache.shared.image(for: request),
                  !Task.isCancelled else { return }
            imageSize = CGSize(width: decoded.image.width, height: decoded.image.height)
            image = NSImage(cgImage: decoded.image, size: imageSize)
        }
    }

    private func updateGeometry(_ viewport: CGSize) {
        zoom.updateGeometry(viewport: viewport, content: imageSize)
    }
}

@MainActor
private struct ExtendedCapturePDF: View {
    let url: URL
    @ObservedObject var zoom: CaptureZoomState
    @State private var document: PDFDocument?
    @State private var pageSize = CGSize.zero

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let document {
                    ExtendedPDFView(document: document, zoom: zoom)
                } else {
                    ProgressView().controlSize(.small).accessibilityLabel("Loading PDF")
                }
            }
            .background(CaptureZoomPassiveInputSurface(zoom: zoom,
                handlesMagnification: false, preciseScrollPansState: false,
                passesDoubleClickThrough: true))
            .onAppear { updateGeometry(geometry.size) }
            .onChange(of: geometry.size) { _, size in updateGeometry(size) }
            .onChange(of: pageSize) { _, _ in updateGeometry(geometry.size) }
        }
        .task(id: url) {
            let loaded = PDFDocument(url: url)
            guard !Task.isCancelled else { return }
            document = loaded
            zoom.setPDFPageCount(loaded?.pageCount ?? 0)
            updatePageSize(loaded)
        }
        .onChange(of: zoom.pdfPage) { _, _ in updatePageSize(document) }
    }

    private func updatePageSize(_ document: PDFDocument?) {
        guard let document, let page = document.page(at: zoom.pdfPage) else {
            pageSize = .zero
            return
        }
        pageSize = page.bounds(for: .mediaBox).size
    }

    private func updateGeometry(_ viewport: CGSize) {
        zoom.updateGeometry(viewport: viewport, content: pageSize)
    }
}

@MainActor
private struct ExtendedPDFView: NSViewRepresentable {
    let document: PDFDocument
    @ObservedObject var zoom: CaptureZoomState

    func makeCoordinator() -> Coordinator { Coordinator(zoom: zoom) }

    func makeNSView(context: Context) -> ExtendedNativePDFView {
        let view = ExtendedNativePDFView()
        view.zoom = zoom
        view.displayMode = .singlePage
        view.displayBox = .mediaBox
        view.displaysPageBreaks = false
        view.backgroundColor = .clear
        view.minScaleFactor = CaptureZoomState.minimumScale
        view.maxScaleFactor = CaptureZoomState.maximumScale
        view.document = document
        context.coordinator.connect(view)
        apply(to: view)
        return view
    }

    func updateNSView(_ view: ExtendedNativePDFView, context: Context) {
        context.coordinator.zoom = zoom
        view.zoom = zoom
        if view.document !== document { view.document = document }
        apply(to: view)
    }

    private func apply(to view: PDFView) {
        if zoom.mode == .fit {
            view.autoScales = true
        } else {
            view.autoScales = false
            if abs(view.scaleFactor - zoom.scale) > 0.001 { view.scaleFactor = zoom.scale }
        }
        guard let page = document.page(at: zoom.pdfPage), view.currentPage !== page else { return }
        view.go(to: page)
    }

    @MainActor
    final class Coordinator: NSObject {
        var zoom: CaptureZoomState
        private weak var view: PDFView?
        private var observers: [NSObjectProtocol] = []

        init(zoom: CaptureZoomState) { self.zoom = zoom }

        func connect(_ view: PDFView) {
            self.view = view
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) {
                [weak self, weak view] _ in
                guard let self, let view else { return }
                Task { @MainActor in
                    guard let document = view.document, let page = view.currentPage else { return }
                    let index = document.index(for: page)
                    if index != NSNotFound { self.zoom.showPDFPage(index) }
                }
            })
        }

        deinit {
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
        }
    }
}

@MainActor
private final class ExtendedNativePDFView: PDFView, DaBinDocumentGestureOwner {
    weak var zoom: CaptureZoomState?
    private var lastReportedFit: CGFloat = 0

    override func layout() {
        super.layout()
        guard let zoom, zoom.mode == .fit, scaleFactor.isFinite, scaleFactor > 0,
              abs(scaleFactor - lastReportedFit) > 0.0001 else { return }
        lastReportedFit = scaleFactor
        let fitted = scaleFactor
        DispatchQueue.main.async { [weak zoom] in zoom?.adoptFittedScale(fitted) }
    }

    override func magnify(with event: NSEvent) {
        autoScales = false
        super.magnify(with: event)
        zoom?.adoptNativeScale(scaleFactor)
    }
}

@MainActor
private struct ExtendedCaptureText: View {
    let text: String
    @ObservedObject var zoom: CaptureZoomState

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                Text(text)
                    .font(.system(size: zoom.textFontSize * zoom.scale))
                    .lineSpacing(max(3, zoom.textFontSize * zoom.scale * 0.28))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(24)
            }
            .background(CaptureZoomPassiveInputSurface(zoom: zoom,
                handlesMagnification: true, preciseScrollPansState: false,
                passesDoubleClickThrough: true))
            .onAppear { updateGeometry(geometry.size) }
            .onChange(of: geometry.size) { _, size in updateGeometry(size) }
        }
        .accessibilityLabel("Capture text")
        .accessibilityIdentifier("capture-extended-text")
    }

    private func updateGeometry(_ viewport: CGSize) {
        // Text remains vector and reflows to the current viewport. Zoom changes
        // its native font metrics rather than scaling a bitmap snapshot.
        zoom.updateGeometry(viewport: viewport, content: viewport)
    }
}

@MainActor
private struct ExtendedCaptureVideo: View {
    let url: URL
    @ObservedObject var zoom: CaptureZoomState
    @State private var player: AVPlayer?
    @State private var dragStart: CGSize?

    var body: some View {
        GeometryReader { geometry in
            VideoPlayer(player: player)
                .scaleEffect(zoom.scale)
                .offset(zoom.pan)
                .clipped()
                .simultaneousGesture(panGesture)
                .background(CaptureZoomPassiveInputSurface(zoom: zoom,
                    handlesMagnification: true, preciseScrollPansState: true,
                    passesDoubleClickThrough: false))
                .onAppear {
                    player = AVPlayer(url: url)
                    zoom.updateGeometry(viewport: geometry.size, content: geometry.size)
                }
                .onChange(of: geometry.size) { _, size in
                    zoom.updateGeometry(viewport: size, content: size)
                }
                .onDisappear {
                    player?.pause()
                    player = nil
                }
        }
        .accessibilityLabel("Video capture")
        .accessibilityIdentifier("capture-extended-video")
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragStart == nil { dragStart = zoom.pan }
                guard let start = dragStart else { return }
                zoom.setPan(CGSize(width: start.width + value.translation.width,
                                   height: start.height + value.translation.height))
            }
            .onEnded { _ in dragStart = nil }
    }
}

@MainActor
private struct ExtendedCaptureQuickLook: View {
    let url: URL
    @ObservedObject var zoom: CaptureZoomState

    var body: some View {
        GeometryReader { geometry in
            QuickLookCaptureView(url: url, viewport: geometry.size, zoom: zoom)
                // The local monitor only consumes zoom gestures. Precise
                // scrolling still reaches the native scroll view and text
                // selection remains owned by Quick Look.
                .background(CaptureZoomPassiveInputSurface(zoom: zoom,
                    handlesMagnification: true, preciseScrollPansState: false,
                    passesDoubleClickThrough: false))
                .onAppear { zoom.updateGeometry(viewport: geometry.size, content: geometry.size) }
                .onChange(of: geometry.size) { _, size in
                    zoom.updateGeometry(viewport: size, content: size)
                }
        }
        .accessibilityLabel("Document preview")
        .accessibilityIdentifier("capture-extended-document")
    }
}

@MainActor
private struct QuickLookCaptureView: NSViewRepresentable {
    let url: URL
    let viewport: CGSize
    @ObservedObject var zoom: CaptureZoomState

    func makeNSView(context: Context) -> ExtendedQuickLookScrollView {
        let view = ExtendedQuickLookScrollView()
        view.configure(url: url, viewport: viewport, zoom: zoom)
        return view
    }

    func updateNSView(_ view: ExtendedQuickLookScrollView, context: Context) {
        view.configure(url: url, viewport: viewport, zoom: zoom)
    }

    static func dismantleNSView(_ view: ExtendedQuickLookScrollView, coordinator: ()) {
        view.stop()
    }
}

/// Quick Look has no public scale setter. Resizing its native preview surface
/// asks the generator to redraw at the requested size, avoiding a bitmap
/// `scaleEffect`; the enclosing native scroll view owns panning and scrollers.
@MainActor
private final class ExtendedQuickLookScrollView: NSScrollView, DaBinDocumentGestureOwner {
    private let documentHost = NSView()
    private let preview: QLPreviewView
    private weak var zoom: CaptureZoomState?
    private var loadedURL: URL?
    private var viewport = CGSize.zero
    private var applyingBounds = false
    private var stopped = false

    override init(frame frameRect: NSRect) {
        guard let preview = QLPreviewView(frame: .zero, style: .normal) else {
            fatalError("Quick Look preview is unavailable")
        }
        self.preview = preview
        super.init(frame: frameRect)
        drawsBackground = false
        borderType = .noBorder
        hasHorizontalScroller = true
        hasVerticalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay
        contentView.postsBoundsChangedNotifications = true
        documentView = documentHost
        documentHost.addSubview(preview)
        preview.autostarts = false
        preview.shouldCloseWithWindow = false
        NotificationCenter.default.addObserver(self, selector: #selector(boundsChanged),
            name: NSView.boundsDidChangeNotification, object: contentView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    func configure(url: URL, viewport: CGSize, zoom: CaptureZoomState) {
        guard !stopped else { return }
        self.zoom = zoom
        self.viewport = CGSize(width: max(0, viewport.width), height: max(0, viewport.height))
        if loadedURL != url {
            loadedURL = url
            preview.previewItem = url as NSURL
            if let displayState = zoom.quickLookDisplayState { preview.displayState = displayState }
        }
        layoutDocument()
    }

    override func layout() {
        super.layout()
        layoutDocument()
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        zoom?.quickLookDisplayState = preview.displayState
        NotificationCenter.default.removeObserver(self)
        preview.close()
        zoom = nil
    }

    private func layoutDocument() {
        guard !stopped, let zoom, viewport.width > 0, viewport.height > 0 else { return }
        let scaled = CGSize(width: max(1, viewport.width * zoom.scale),
                            height: max(1, viewport.height * zoom.scale))
        let hostSize = CGSize(width: max(viewport.width, scaled.width),
                              height: max(viewport.height, scaled.height))
        if documentHost.frame.size != hostSize { documentHost.frame = CGRect(origin: .zero, size: hostSize) }
        let previewFrame = CGRect(x: (hostSize.width - scaled.width) / 2,
                                  y: (hostSize.height - scaled.height) / 2,
                                  width: scaled.width, height: scaled.height)
        if preview.frame != previewFrame { preview.frame = previewFrame }
        let center = CGPoint(x: max(0, (hostSize.width - viewport.width) / 2),
                             y: max(0, (hostSize.height - viewport.height) / 2))
        let origin = CGPoint(x: center.x - zoom.pan.width, y: center.y + zoom.pan.height)
        if abs(contentView.bounds.origin.x - origin.x) > 0.5 ||
            abs(contentView.bounds.origin.y - origin.y) > 0.5 {
            applyingBounds = true
            contentView.scroll(to: origin)
            reflectScrolledClipView(contentView)
            applyingBounds = false
        }
    }

    @objc private func boundsChanged(_ notification: Notification) {
        guard !stopped, !applyingBounds, let zoom else { return }
        let hostSize = documentHost.frame.size
        let center = CGPoint(x: max(0, (hostSize.width - viewport.width) / 2),
                             y: max(0, (hostSize.height - viewport.height) / 2))
        zoom.setPan(CGSize(width: center.x - contentView.bounds.origin.x,
                           height: contentView.bounds.origin.y - center.y))
    }
}

/// Observes only events that occur over its own visible canvas while returning
/// native text/PDF/Quick Look scrolling and selection events unchanged. The
/// monitor is removed as soon as SwiftUI detaches this surface from a window.
@MainActor
private struct CaptureZoomPassiveInputSurface: NSViewRepresentable {
    @ObservedObject var zoom: CaptureZoomState
    let handlesMagnification: Bool
    let preciseScrollPansState: Bool
    let passesDoubleClickThrough: Bool

    func makeNSView(context: Context) -> CaptureZoomPassiveInputView {
        let view = CaptureZoomPassiveInputView()
        view.configure(zoom: zoom, handlesMagnification: handlesMagnification,
                       preciseScrollPansState: preciseScrollPansState,
                       passesDoubleClickThrough: passesDoubleClickThrough)
        return view
    }

    func updateNSView(_ view: CaptureZoomPassiveInputView, context: Context) {
        view.configure(zoom: zoom, handlesMagnification: handlesMagnification,
                       preciseScrollPansState: preciseScrollPansState,
                       passesDoubleClickThrough: passesDoubleClickThrough)
    }

    static func dismantleNSView(_ view: CaptureZoomPassiveInputView, coordinator: ()) { view.stop() }
}

@MainActor
private final class CaptureZoomPassiveInputView: NSView, DaBinDocumentGestureOwner {
    private weak var zoom: CaptureZoomState?
    private var handlesMagnification = true
    private var preciseScrollPansState = false
    private var passesDoubleClickThrough = true
    private var monitor: Any?
    private var stopped = false
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(zoom: CaptureZoomState, handlesMagnification: Bool,
                   preciseScrollPansState: Bool, passesDoubleClickThrough: Bool) {
        self.zoom = zoom
        self.handlesMagnification = handlesMagnification
        self.preciseScrollPansState = preciseScrollPansState
        self.passesDoubleClickThrough = passesDoubleClickThrough
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitor()
        guard window != nil, !stopped else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify, .leftMouseDown]) {
            [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    func stop() {
        stopped = true
        removeMonitor()
        zoom = nil
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard !stopped, event.window === window, window?.isVisible == true,
              bounds.width > 0, bounds.height > 0, !hasHiddenAncestor,
              bounds.contains(convert(event.locationInWindow, from: nil)), let zoom else { return event }
        switch event.type {
        case .scrollWheel:
            let forceZoom = !event.modifierFlags.intersection([.command, .option]).isEmpty
            switch CaptureZoomNativeInput.wheelIntent(deltaX: event.scrollingDeltaX,
                                                      deltaY: event.scrollingDeltaY,
                                                      isPrecise: event.hasPreciseScrollingDeltas,
                                                      forceZoom: forceZoom) {
            case .zoom(let factor):
                zoom.zoom(by: factor, anchor: convert(event.locationInWindow, from: nil))
                return nil
            case .pan(let translation):
                guard preciseScrollPansState else { return event }
                zoom.pan(by: translation)
                return nil
            }
        case .magnify where handlesMagnification:
            zoom.zoom(by: max(0.05, 1 + event.magnification),
                      anchor: convert(event.locationInWindow, from: nil))
            return nil
        case .leftMouseDown where event.clickCount == 2:
            zoom.toggleFitAnd100()
            return passesDoubleClickThrough ? event : nil
        default:
            return event
        }
    }

    private var hasHiddenAncestor: Bool {
        var candidate: NSView? = self
        while let view = candidate {
            if view.isHidden { return true }
            candidate = view.superview
        }
        return false
    }
}

@MainActor
private struct CaptureZoomInteractionSurface: NSViewRepresentable {
    @ObservedObject var zoom: CaptureZoomState

    func makeNSView(context: Context) -> CaptureZoomInteractionView {
        let view = CaptureZoomInteractionView()
        view.zoom = zoom
        return view
    }

    func updateNSView(_ view: CaptureZoomInteractionView, context: Context) { view.zoom = zoom }
}

@MainActor
final class CaptureZoomInteractionView: NSView, DaBinDocumentGestureOwner {
    weak var zoom: CaptureZoomState?
    private var dragStart: CGSize?
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isFlipped: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        guard let zoom else { return }
        let forceZoom = !event.modifierFlags.intersection([.command, .option]).isEmpty
        switch CaptureZoomNativeInput.wheelIntent(deltaX: event.scrollingDeltaX,
                                                  deltaY: event.scrollingDeltaY,
                                                  isPrecise: event.hasPreciseScrollingDeltas,
                                                  forceZoom: forceZoom) {
        case .zoom(let factor):
            zoom.zoom(by: factor, anchor: convert(event.locationInWindow, from: nil))
        case .pan(let translation):
            zoom.pan(by: translation)
        }
    }

    override func magnify(with event: NSEvent) {
        guard let zoom else { return }
        zoom.zoom(by: max(0.05, 1 + event.magnification),
                  anchor: convert(event.locationInWindow, from: nil))
    }

    override func mouseDown(with event: NSEvent) {
        guard let zoom else { return }
        if event.clickCount == 2 {
            zoom.toggleFitAnd100()
            dragStart = nil
        } else {
            dragStart = zoom.pan
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let zoom, let start = dragStart else { return }
        let current = convert(event.locationInWindow, from: nil)
        let initial = convert(event.locationInWindow.applying(
            CGAffineTransform(translationX: -event.deltaX, y: -event.deltaY)), from: nil)
        zoom.setPan(CGSize(width: start.width + current.x - initial.x,
                           height: start.height + current.y - initial.y))
        dragStart = zoom.pan
    }

    override func mouseUp(with event: NSEvent) { dragStart = nil }
}
