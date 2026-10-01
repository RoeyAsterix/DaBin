import AppKit
import Foundation
import ImageIO

private final class DecodeProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var mainThreadCalls = 0
    let release: DispatchSemaphore?
    init(block: Bool = false) { release = block ? DispatchSemaphore(value: 0) : nil }
    var counts: (calls: Int, mainThreadCalls: Int) {
        lock.lock(); defer { lock.unlock() }; return (calls, mainThreadCalls)
    }
    func decode(_ url: URL, size: Int) -> DecodedCapturePreview? {
        lock.lock(); calls += 1; if Thread.isMainThread { mainThreadCalls += 1 }; lock.unlock()
        release?.wait()
        return CapturePreviewImageCache.decode(url, maximumPixelSize: size)
    }
}

@main @MainActor struct CapturePreviewPerformanceTests {
    private static var checks = 0
    private static func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        if !value() { throw NSError(domain: "CapturePreviewPerformanceTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    static func main() async throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("DaBinPreviewPerformance-\(UUID())")
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }
        let url = root.appendingPathComponent("fixture.png")
        try png(width: 2_400, height: 1_600).write(to: url)
        let file = CapturePreviewFileReference(root: root, relativePath: "fixture.png")
        let request = CapturePreviewImageRequest(file: file, maximumPixelSize: 600, revision: "ready")
        let probe = DecodeProbe()
        let cache = CapturePreviewImageCache(decoder: { url, size in probe.decode(url, size: size) })

        let first = await cache.image(for: request)
        try expect(first?.image.width == 600 && first?.image.height == 400,
                   "Large originals are downsampled to the card's bounded pixel size")
        let repeated = await cache.image(for: request)
        try expect(first === repeated && probe.counts.calls == 1,
                   "Repeated card render requests reuse the same decoded image")
        let concurrent = await withTaskGroup(of: DecodedCapturePreview?.self) { group in
            for _ in 0..<24 { group.addTask { await cache.image(for: request) } }
            var count = 0
            for await image in group { if image === first { count += 1 } }
            return count
        }
        try expect(concurrent == 24 && probe.counts.calls == 1,
                   "Many visible cards share one decode for the same file version")
        try expect(probe.counts.mainThreadCalls == 0, "Image decoding never executes on the UI thread")

        let detail = await cache.image(for: CapturePreviewImageRequest(file: file,
            maximumPixelSize: 1_600, revision: "original"))
        try expect(detail?.image.width == 1_600 && [1_066, 1_067].contains(detail?.image.height ?? 0),
                   "Detail images retain a larger bounded decode without allocating the full original")

        // Preserve mtime to prove an atomic replacement still invalidates by inode.
        let modification = try files.attributesOfItem(atPath: url.path)[.modificationDate]!
        try png(width: 1_600, height: 2_400).write(to: url, options: .atomic)
        try files.setAttributes([.modificationDate: modification], ofItemAtPath: url.path)
        let replaced = await cache.image(for: request)
        try expect(replaced?.image.width == 400 && replaced?.image.height == 600 && replaced !== first,
                   "An atomically regenerated thumbnail reloads even when its path and mtime are unchanged")

        let orientedURL = root.appendingPathComponent("orientation.jpg")
        try png(width: 300, height: 100, orientation: 6).write(to: orientedURL)
        let oriented = await cache.image(for: CapturePreviewImageRequest(
            file: CapturePreviewFileReference(root: root, relativePath: "orientation.jpg"),
            maximumPixelSize: 150, revision: "ready"))
        try expect(oriented?.image.width == 50 && oriented?.image.height == 150,
                   "Downsampling honors the image's recorded orientation")

        let svgURL = root.appendingPathComponent("robot.svg")
        guard let svgResource = Bundle.main.url(forResource: "robot", withExtension: "svg") else {
            throw NSError(domain: "Fixture", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "The bundled robot.svg regression fixture is missing"])
        }
        try files.copyItem(at: svgResource, to: svgURL)
        let svg = await cache.image(for: CapturePreviewImageRequest(
            file: CapturePreviewFileReference(root: root, relativePath: "robot.svg"),
            maximumPixelSize: 32, revision: "original"))
        try expect(svg?.image.width == 26 && svg?.image.height == 32,
                   "AppKit-supported SVG originals retain a bounded detail preview when ImageIO cannot thumbnail them")
        let hasPaintedPixels: Bool
        if let data = svg?.image.dataProvider?.data, let pixels = CFDataGetBytePtr(data) {
            hasPaintedPixels = stride(from: 3, to: CFDataGetLength(data), by: 4).contains { pixels[$0] > 0 }
        } else { hasPaintedPixels = false }
        try expect(hasPaintedPixels && probe.counts.mainThreadCalls == 0,
                   "The SVG fallback rasterizes visible pixels off the UI thread")

        try files.createSymbolicLink(at: root.appendingPathComponent("link.png"), withDestinationURL: url)
        let unsafe = await cache.image(for: CapturePreviewImageRequest(
            file: CapturePreviewFileReference(root: root, relativePath: "link.png"),
            maximumPixelSize: 600, revision: "ready"))
        try expect(unsafe == nil, "Moving preview reads to a worker preserves archive symlink rejection")
        let traversal = await cache.resolvedURL(for: CapturePreviewFileReference(root: root, relativePath: "../fixture.png"))
        try expect(traversal == nil, "Background resolution preserves archive traversal rejection")
        let missing = await cache.image(for: CapturePreviewImageRequest(
            file: CapturePreviewFileReference(root: root, relativePath: "missing.png"),
            maximumPixelSize: 600, revision: "ready"))
        try expect(missing == nil, "Unavailable images return a stable placeholder result")

        let heldProbe = DecodeProbe(block: true)
        let heldCache = CapturePreviewImageCache(decoder: { url, size in heldProbe.decode(url, size: size) })
        let worker = Task { await heldCache.image(for: request) }
        let deadline = Date().addingTimeInterval(3)
        while heldProbe.counts.calls == 0 && Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        let started = heldProbe.counts.calls == 1
        heldProbe.release?.signal()
        let completed = await worker.value
        try expect(started && heldProbe.counts.mainThreadCalls == 0 && completed != nil,
                   "The main actor remains free to respond while a decoder is deliberately suspended")

        let cancelled = Task { await cache.image(for: request) }
        cancelled.cancel()
        let cancelledImage = await cancelled.value
        try expect(cancelledImage == nil, "An offscreen canceled request cannot publish an image")
        try files.removeItem(at: url)
        let removedImage = await cache.image(for: request)
        try expect(removedImage == nil, "A missing original cannot return its stale decoded cache entry")
        print("PASS: \(checks) bounded background preview/cache checks; no main-thread decode")
    }

    private static func png(width: Int, height: Int, orientation: Int? = nil) throws -> Data {
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw NSError(domain: "Fixture", code: 1)
        }
        context.setFillColor(CGColor(red: 0.1, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        guard let image = context.makeImage(), let destination = CGImageDestinationCreateWithData(
            data, (orientation == nil ? "public.png" : "public.jpeg") as CFString, 1, nil) else {
            throw NSError(domain: "Fixture", code: 2)
        }
        let properties = orientation.map { [kCGImagePropertyOrientation: $0] as CFDictionary }
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "Fixture", code: 3) }
        return data as Data
    }
}
