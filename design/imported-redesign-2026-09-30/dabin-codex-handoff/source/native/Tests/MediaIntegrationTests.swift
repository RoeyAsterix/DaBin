import AppKit
@preconcurrency import AVFoundation
import CoreVideo
import PDFKit
import SwiftUI

/// Actual system-media integration, using only freshly generated temporary files.
/// No notifications, general pasteboard, user archive, or persistent preferences.
@main
@MainActor
struct MediaIntegrationTests {
    static var checks = 0
    static var failures: [String] = []

    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if value() { print("PASS: \(message)") }
        else { failures.append(message); print("FAIL: \(message)") }
    }

    static func error(_ message: String) -> NSError {
        NSError(domain: "DaBinMediaIntegration", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    static func waitForPreview(_ capture: Capture, timeout: TimeInterval = 25) async {
        let deadline = Date().addingTimeInterval(timeout)
        while capture.previewState == "loading" && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    static func thumbnail(_ capture: Capture, store: CaptureStore, label: String) throws -> NSBitmapImageRep? {
        check(capture.previewState == "ready", "\(label) system preview completed (\(capture.previewState); \(capture.previewError ?? "no error"))")
        guard let url = store.previewURL(for: capture), let image = NSBitmapImageRep(data: try Data(contentsOf: url)) else {
            check(false, "\(label) produced a readable cached PNG")
            return nil
        }
        check(image.pixelsWide > 0 && image.pixelsHigh > 0 && max(image.pixelsWide, image.pixelsHigh) <= 600,
              "\(label) PNG is nonempty and bounded to 600 pixels")
        var colors = Set<String>()
        for y in stride(from: 0, to: image.pixelsHigh, by: max(1, image.pixelsHigh / 30)) {
            for x in stride(from: 0, to: image.pixelsWide, by: max(1, image.pixelsWide / 30)) {
                if let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) {
                    colors.insert("\(Int(color.redComponent * 255))/\(Int(color.greenComponent * 255))/\(Int(color.blueComponent * 255))")
                }
            }
        }
        check(colors.count >= 3, "\(label) thumbnail contains rendered content, not a uniform blank image")
        return image
    }

    static func makePDF(at url: URL) throws {
        let document = PDFDocument()
        for size in [NSSize(width: 600, height: 800), NSSize(width: 800, height: 600)] {
            let image = NSImage(size: size, flipped: false) { bounds in
                NSColor.white.setFill(); bounds.fill()
                for (index, color) in [NSColor.systemPurple, .systemRed, .systemBlue, .systemGreen].enumerated() {
                    color.setFill()
                    NSRect(x: index % 2 == 0 ? 10 : bounds.width - 70,
                           y: index < 2 ? 10 : bounds.height - 70, width: 60, height: 60).fill()
                }
                NSColor.systemPurple.setFill()
                NSRect(x: 80, y: bounds.height / 2, width: bounds.width - 160, height: 40).fill()
                return true
            }
            guard let page = PDFPage(image: image) else { throw error("PDF fixture page creation failed") }
            document.insert(page, at: document.pageCount)
        }
        guard document.write(to: url) else { throw error("PDF fixture write failed") }
    }

    static func makeRTF(at url: URL) throws {
        let text = NSAttributedString(string: "DaBin media integration\n\nA completely synthetic document.\nA purple heading and several lines exercise QuickLook's document renderer.\nNo personal content is used.",
            attributes: [.font: NSFont.systemFont(ofSize: 24), .foregroundColor: NSColor.systemPurple])
        let data = try text.data(from: NSRange(location: 0, length: text.length),
                                 documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        try data.write(to: url)
    }

    static func makeVideo(at url: URL) async throws {
        let width = 320, height = 180
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                                         kCVPixelBufferWidthKey as String: width,
                                         kCVPixelBufferHeightKey as String: height])
        guard writer.canAdd(input) else { throw error("AVAssetWriter cannot add H.264 input") }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? error("Video writer could not start") }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<60 {
            let deadline = Date().addingTimeInterval(10)
            while !input.isReadyForMoreMediaData && writer.status == .writing && Date() < deadline {
                try await Task.sleep(for: .milliseconds(5))
            }
            guard input.isReadyForMoreMediaData, writer.status == .writing else {
                throw writer.error ?? error("Video writer timed out waiting for input")
            }
            var optionalBuffer: CVPixelBuffer?
            let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary,
                &optionalBuffer)
            guard status == kCVReturnSuccess, let buffer = optionalBuffer else { throw error("Pixel buffer allocation failed") }
            CVPixelBufferLockBaseAddress(buffer, [])
            guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw error("Pixel buffer has no base address") }
            let stride = CVPixelBufferGetBytesPerRow(buffer)
            let bytes = base.assumingMemoryBound(to: UInt8.self)
            for y in 0..<height {
                for x in 0..<width {
                    let offset = y * stride + x * 4
                    bytes[offset] = UInt8((x + frame * 3) % 256)
                    bytes[offset + 1] = UInt8(y % 256)
                    bytes[offset + 2] = UInt8((frame * 4) % 256)
                    bytes[offset + 3] = 255
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30)) else {
                throw writer.error ?? error("Video writer refused a frame")
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? error("Video writer did not finish") }
    }

    static func pdfView(in view: NSView) -> PDFView? {
        if let pdf = view as? PDFView { return pdf }
        for child in view.subviews { if let pdf = pdfView(in: child) { return pdf } }
        return nil
    }

    static func settle(_ view: NSView) async {
        for _ in 0..<5 {
            view.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(40))
        }
    }

    static func checkPDFGeometry(_ url: URL) async throws {
        let host = NSHostingView(rootView: FittedPDFPreview(url: url))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 230),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        // Intentionally no orderFront/makeKey/activation; this window stays hidden.
        await settle(host)
        guard let pdf = pdfView(in: host), let document = pdf.document else {
            throw error("Production FittedPDFPreview did not instantiate PDFKit")
        }
        check(!window.isVisible && !window.isKeyWindow, "PDF geometry integration window stays hidden and never takes focus")
        check(document.pageCount == 2, "Production PDF view loads both synthetic pages")
        for (size, pageIndex, label) in [(NSSize(width: 340, height: 230), 0, "portrait"),
                                         (NSSize(width: 340, height: 230), 1, "landscape"),
                                         (NSSize(width: 170, height: 150), 1, "narrow landscape"),
                                         (NSSize(width: 170, height: 150), 0, "narrow portrait")] {
            window.setContentSize(size)
            guard let page = document.page(at: pageIndex) else { throw error("Missing fixture PDF page") }
            pdf.go(to: page)
            await settle(host)
            let bounds = pdf.convert(page.bounds(for: .cropBox), from: page)
            check(bounds.width > 0 && bounds.width <= pdf.bounds.width + 1,
                  "\(label) complete PDF width fits the production preview")
            check(bounds.height > 0 && bounds.height <= pdf.bounds.height + 1,
                  "\(label) complete PDF height fits the production preview")
            check(pdf.autoScales && pdf.displayMode == .singlePage && pdf.currentPage == page,
                  "\(label) retains fitted single-page navigation")
        }
    }

    static func main() async {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinMediaIntegration-\(UUID().uuidString)")
        let defaults = UserDefaults.standard
        let previousArguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        var arguments = previousArguments
        arguments[PreviewService.linkPreviewPreference] = false
        defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        defer {
            defaults.setVolatileDomain(previousArguments, forName: UserDefaults.argumentDomain)
            try? FileManager.default.removeItem(at: root)
        }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let fixtures = root.appendingPathComponent("Fixtures")
            try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
            let pdfURL = fixtures.appendingPathComponent("Synthetic-pages.pdf")
            let rtfURL = fixtures.appendingPathComponent("Synthetic-document.rtf")
            let videoURL = fixtures.appendingPathComponent("Synthetic-motion.mov")
            try makePDF(at: pdfURL)
            try makeRTF(at: rtfURL)
            try await makeVideo(at: videoURL)
            let sources = [pdfURL, rtfURL, videoURL]
            let originals = try sources.map { try Data(contentsOf: $0) }
            let store = try CaptureStore(root: root.appendingPathComponent("Archive"))
            var captures: [Capture] = []
            for source in sources { captures.append(try await store.importFile(source)) }
            check(captures.map(\.kind) == [.pdf, .document, .video], "PDF, RTF and MOV imports receive their correct types")
            let previews = PreviewService(store: store)
            check(!previews.enabled, "Local-media tests keep website requests disabled")
            previews.process(captures)
            for capture in captures { await waitForPreview(capture) }
            let pdfThumbnail = try thumbnail(captures[0], store: store, label: "PDFKit PDF")
            if let pdfThumbnail { check(pdfThumbnail.pixelsHigh > pdfThumbnail.pixelsWide, "PDF thumbnail keeps first-page portrait proportions") }
            check(captures[0].previewDescription == "2 pages · PDF", "PDF preview records the actual two-page count")
            _ = try thumbnail(captures[1], store: store, label: "QuickLook RTF")
            let videoThumbnail = try thumbnail(captures[2], store: store, label: "AVFoundation MOV")
            if let videoThumbnail { check(abs(Double(videoThumbnail.pixelsWide) / Double(videoThumbnail.pixelsHigh) - 16.0 / 9.0) < 0.05,
                                           "Video thumbnail retains the source aspect ratio") }
            check(captures[2].previewDescription.contains("0:02"), "Video card records the actual two-second duration")
            for (index, source) in sources.enumerated() {
                let sourceData = try Data(contentsOf: source)
                check(sourceData == originals[index], "\(source.pathExtension.uppercased()) source bytes stay unchanged")
                if let managed = store.managedURL(for: captures[index]) {
                    let managedData = try Data(contentsOf: managed)
                    check(managedData == originals[index], "\(source.pathExtension.uppercased()) managed original matches source exactly")
                } else { check(false, "Managed original is available") }
            }
            let asset = AVURLAsset(url: videoURL)
            let generator = AVAssetImageGenerator(asset: asset)
            let first = try await generator.image(at: .zero).image
            let later = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 30)).image
            check(first.width == 320 && first.height == 180 && later.width == first.width, "AVFoundation decodes early and later frames at the expected size")
            guard let firstBytes = first.dataProvider?.data, let laterBytes = later.dataProvider?.data else {
                throw error("Decoded video images have no pixel data")
            }
            check(firstBytes as Data != laterBytes as Data, "Decoded video frames differ over time")
            try await checkPDFGeometry(pdfURL)
            let reopened = try CaptureStore(root: store.root)
            check(reopened.captures.count == 3 && reopened.captures.allSatisfy { $0.previewState == "ready" },
                  "All three successful preview records survive an archive reopen")
            check(store.error == nil, "Real-media processing leaves no storage error")

            if CommandLine.arguments.contains("--link-smoke") {
                arguments[PreviewService.linkPreviewPreference] = true
                defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
                let link = try store.capture(text: "https://www.apple.com/")[0]
                previews.process([link])
                await waitForPreview(link, timeout: 25)
                check(link.previewState == "ready", "Opt-in generic Apple homepage metadata fetched (\(link.previewState); \(link.previewError ?? "no error"))")
                check(!link.title.isEmpty && link.originalURL == "https://www.apple.com/", "Link preview keeps the original URL and a usable title")
                previews.cancelNetwork()
            } else {
                print("NOT RUN: External website preview; use --link-smoke for the generic Apple homepage only")
            }
        } catch {
            check(false, "Integration runner error: \(error.localizedDescription)")
        }
        print("\(checks - failures.count)/\(checks) media integration checks passed; \(failures.count) failed")
        if !failures.isEmpty { exit(1) }
    }
}
