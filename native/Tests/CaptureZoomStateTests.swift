import AppKit
import Foundation

@main @MainActor
struct CaptureZoomStateTests {
    private static var checks = 0

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw NSError(domain: "CaptureZoomStateTests", code: checks + 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
        checks += 1
    }

    private static func close(_ lhs: CGFloat, _ rhs: CGFloat, tolerance: CGFloat = 0.001) -> Bool {
        abs(lhs - rhs) <= tolerance
    }

    static func main() throws {
        let state = CaptureZoomState()
        try expect(state.mode == .fit && close(state.scale, 1), "Zoom state begins fitted")

        state.updateGeometry(viewport: CGSize(width: 400, height: 300),
                             content: CGSize(width: 800, height: 400))
        try expect(close(state.scale, 0.5), "Fit uses the limiting viewport dimension")
        try expect(state.pan == .zero && !state.canPan, "Fit centers the complete uncropped content")
        state.adoptFittedScale(0.46)
        try expect(state.mode == .fit && close(state.scale, 0.46),
                   "A native PDF fit measurement remains in Fit mode")

        state.showNative100()
        try expect(state.mode == .native100 && close(state.scale, 1), "100 percent uses native scale")
        try expect(state.canPan, "Native content larger than the viewport can pan")
        state.setPan(CGSize(width: 1_000, height: -1_000))
        try expect(close(state.pan.width, 200) && close(state.pan.height, -50),
                   "Pan is clamped to reachable content edges")

        state.zoom(by: 2, anchor: CGPoint(x: 300, y: 150))
        try expect(state.mode == .custom && close(state.scale, 2), "Pointer zoom enters custom mode")
        try expect(close(state.pan.width, 300) && close(state.pan.height, -100),
                   "Pointer zoom retains the anchored content location within bounds")

        state.updateGeometry(viewport: CGSize(width: 1_200, height: 800),
                             content: CGSize(width: 800, height: 400))
        try expect(state.mode == .custom && close(state.scale, 2), "Resize retains custom zoom")
        try expect(close(state.pan.width, 200) && close(state.pan.height, 0),
                   "Resize clamps only unreachable pan axes")

        state.zoom(by: 1_000)
        try expect(close(state.scale, CaptureZoomState.maximumScale) && !state.canZoomIn,
                   "Zoom has a finite upper bound")
        state.zoom(by: 0.000_001)
        try expect(close(state.scale, CaptureZoomState.minimumScale) && !state.canZoomOut,
                   "Zoom has a finite lower bound")
        let bounded = state.scale
        state.zoom(by: .nan)
        state.zoom(by: -1)
        try expect(close(state.scale, bounded), "Invalid magnification is ignored")

        state.setPDFPageCount(4)
        state.showPDFPage(99)
        try expect(state.pdfPage == 3, "PDF pages clamp at the document end")
        state.previousPDFPage()
        try expect(state.pdfPage == 2, "PDF previous-page navigation is retained")
        state.showPDFPage(-5)
        try expect(state.pdfPage == 0, "PDF pages clamp at the document start")
        state.setPDFPageCount(0)
        try expect(state.pdfPage == 0 && state.pdfPageCount == 0, "Empty PDF state stays valid")

        state.setTextFontSize(80)
        try expect(close(state.textFontSize, CaptureZoomState.maximumTextFontSize),
                   "Vector text size has a readable upper bound")
        state.setTextFontSize(2)
        try expect(close(state.textFontSize, CaptureZoomState.minimumTextFontSize),
                   "Vector text size has a readable lower bound")
        state.setTextContent(true)
        try expect(state.isTextContent, "Text canvases expose native text-size controls")
        state.setTextContent(false)
        try expect(!state.isTextContent, "Non-text canvases hide text-only controls")

        state.setPDFPageCount(3)
        state.showPDFPage(2)
        state.setTextFontSize(25)
        state.reset()
        try expect(state.mode == .fit && state.pan == .zero, "Reset restores fitted centered content")
        try expect(state.pdfPage == 0 && close(state.textFontSize, CaptureZoomState.defaultTextFontSize),
                   "Reset restores page and native vector text size")

        state.updateGeometry(viewport: CGSize(width: 320, height: 240),
                             content: CGSize(width: 640, height: 480))
        state.toggleFitAnd100()
        try expect(state.mode == .native100 && close(state.scale, 1), "Double-click policy toggles fit to 100 percent")
        state.toggleFitAnd100()
        try expect(state.mode == .fit && close(state.scale, 0.5), "Double-click policy toggles 100 percent to fit")

        let mouseWheel = CaptureZoomNativeInput.wheelIntent(deltaX: 0, deltaY: 2, isPrecise: false)
        if case .zoom(let factor) = mouseWheel {
            try expect(factor > 1, "A mouse wheel notch maps to bounded zoom")
        } else { try expect(false, "A mouse wheel should zoom") }
        let trackpad = CaptureZoomNativeInput.wheelIntent(deltaX: 7, deltaY: -5, isPrecise: true)
        try expect(trackpad == .pan(CGSize(width: -7, height: -5)),
                   "Precise two-axis scrolling maps to canvas pan")
        let modifiedTrackpad = CaptureZoomNativeInput.wheelIntent(deltaX: 2, deltaY: -3,
                                                                  isPrecise: true, forceZoom: true)
        if case .zoom(let factor) = modifiedTrackpad {
            try expect(factor < 1, "Modified precise scrolling maps to zoom")
        } else { try expect(false, "Modified trackpad input should zoom") }

        state.updateGeometry(viewport: CGSize(width: CGFloat.infinity, height: CGFloat.nan),
                             content: CGSize(width: -10, height: CGFloat.infinity))
        try expect(state.viewportSize == .zero && state.contentSize == .zero,
                   "Non-finite geometry is safely normalized")

        print("PASS: \(checks) capture extended-canvas zoom, fit, pan, resize, PDF, text and native-input checks")
    }
}
