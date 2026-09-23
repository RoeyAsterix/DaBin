import AppKit
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

struct AutoCaptureFingerprint: Hashable, Sendable {
    let digest: String

    static func image(on pasteboard: NSPasteboard) -> AutoCaptureFingerprint? {
        let imageItems = (pasteboard.pasteboardItems ?? []).compactMap { item -> Data? in
            // Match InputService's precedence. A Finder file item may also offer
            // an image preview, but its durable payload is the file URL.
            if item.string(forType: .fileURL) != nil { return nil }
            return item.data(forType: .png) ?? item.data(forType: .tiff)
        }
        guard imageItems.count == 1 else { return nil }
        return normalizedImage(data: imageItems[0])
    }

    static func image(at url: URL) -> AutoCaptureFingerprint? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return normalizedImage(source: source)
    }

    private static func normalizedImage(data: Data) -> AutoCaptureFingerprint? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return normalizedImage(source: source)
    }

    /// Hash a bounded, decoded RGBA representation so PNG and TIFF versions of
    /// the same screenshot compare equal without retaining full-size pixels.
    private static func normalizedImage(source: CGImageSource) -> AutoCaptureFingerprint? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        let bytesPerRow = width * 4
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ), let pixels = context.data else { return nil }
        context.interpolationQuality = .high
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var hasher = SHA256()
        var encodedWidth = UInt32(width).bigEndian
        var encodedHeight = UInt32(height).bigEndian
        withUnsafeBytes(of: &encodedWidth) { hasher.update(bufferPointer: $0) }
        withUnsafeBytes(of: &encodedHeight) { hasher.update(bufferPointer: $0) }
        hasher.update(bufferPointer: UnsafeRawBufferPointer(start: pixels, count: bytesPerRow * height))
        return AutoCaptureFingerprint(digest: hasher.finalize().map { String(format: "%02x", $0) }.joined())
    }
}

/// Suppresses only an opposite-channel repeat inside a short interval. Copying
/// the same image twice through one channel still creates two user actions.
struct AutoCaptureFingerprintHistory {
    private struct Entry {
        let origin: CaptureOrigin
        let savedAt: Date
    }

    private var entries: [AutoCaptureFingerprint: Entry] = [:]
    let interval: TimeInterval

    init(interval: TimeInterval = 4) {
        self.interval = max(0, interval)
    }

    mutating func isOppositeChannelDuplicate(_ fingerprint: AutoCaptureFingerprint,
                                             origin: CaptureOrigin,
                                             at date: Date) -> Bool {
        prune(at: date)
        guard let entry = entries[fingerprint] else { return false }
        return entry.origin != origin && date.timeIntervalSince(entry.savedAt) <= interval
    }

    mutating func record(_ fingerprint: AutoCaptureFingerprint,
                         origin: CaptureOrigin,
                         at date: Date) {
        prune(at: date)
        entries[fingerprint] = Entry(origin: origin, savedAt: date)
    }

    mutating func reset() {
        entries.removeAll()
    }

    private mutating func prune(at date: Date) {
        entries = entries.filter { date.timeIntervalSince($0.value.savedAt) <= interval }
    }
}
