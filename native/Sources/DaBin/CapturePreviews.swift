import AppKit
import AVKit
import ImageIO
import SwiftUI

/// Immutable inputs keep archive validation and image decoding out of view bodies.
struct CapturePreviewFileReference: Hashable, Sendable {
    let root: URL
    let relativePath: String

    @MainActor static func thumbnail(store: CaptureStore, capture: Capture) -> Self? {
        guard let path = capture.thumbnailRelativePath,
              path == "Previews/\(capture.id.uuidString)/thumbnail.png" else { return nil }
        return Self(root: store.root, relativePath: path)
    }

    @MainActor static func original(store: CaptureStore, capture: Capture) -> Self? {
        guard let path = capture.attachmentRelativePath else { return nil }
        let filename = capture.originalFilename ?? ""
        let legacy = "Originals/\(capture.id.uuidString)/\(CaptureClassifier.storageFilename(filename))"
        let current = try? DailyArchive.originalRelativePath(id: capture.id, capturedAt: capture.capturedAt,
            captureDay: capture.captureDay, utcOffset: capture.captureUTCOffsetSeconds, filename: filename)
        guard path == legacy || path == current || ProjectFileArchive.ownsOriginal(path, id: capture.id,
            day: capture.captureDay, kind: capture.kind, filename: filename) else { return nil }
        return Self(root: store.root, relativePath: path)
    }
}

struct CapturePreviewImageRequest: Hashable, Sendable {
    let file: CapturePreviewFileReference
    let maximumPixelSize: Int
    /// A regenerated thumbnail keeps its path, but changes preview state.
    let revision: String
}

/// CGImage is immutable after decoding, and can cross back to the view safely.
final class DecodedCapturePreview: @unchecked Sendable {
    let image: CGImage
    init(image: CGImage) { self.image = image }
    var cost: Int { image.bytesPerRow * image.height }
}

/// Serial background decoding avoids both repeated main-thread reads during
/// scrolling and a burst of full-size image allocations when a grid appears.
actor CapturePreviewImageCache {
    typealias Decoder = @Sendable (URL, Int) -> DecodedCapturePreview?
    static let shared = CapturePreviewImageCache()
    private let images = NSCache<NSString, DecodedCapturePreview>()
    private let decoder: Decoder
    private var archives: [URL: DailyArchive] = [:]

    init(byteLimit: Int = 32 * 1_024 * 1_024, countLimit: Int = 128, decoder: Decoder? = nil) {
        images.totalCostLimit = byteLimit
        images.countLimit = countLimit
        self.decoder = decoder ?? { url, size in Self.decode(url, maximumPixelSize: size) }
    }

    func resolvedURL(for file: CapturePreviewFileReference) async -> URL? {
        guard !Task.isCancelled else { return nil }
        let archive: DailyArchive
        if let existing = archives[file.root] { archive = existing }
        else {
            archive = await DailyArchive(root: file.root)
            archives[file.root] = archive
        }
        guard !Task.isCancelled, let url = try? archive.safeURL(file.relativePath),
              (try? OriginalFileStorage.validateRegularFile(url)) != nil else { return nil }
        return url
    }

    func image(for request: CapturePreviewImageRequest) async -> DecodedCapturePreview? {
        guard let url = await resolvedURL(for: request.file), !Task.isCancelled,
              let stamp = Self.fileStamp(url) else { return nil }
        let key = "\(url.path)|\(request.maximumPixelSize)|\(stamp)" as NSString
        if let cached = images.object(forKey: key) { return cached }
        let decoded = autoreleasepool { decoder(url, request.maximumPixelSize) }
        guard !Task.isCancelled, let decoded, Self.fileStamp(url) == stamp else { return nil }
        images.setObject(decoded, forKey: key, cost: decoded.cost)
        return decoded
    }

    private nonisolated static func fileStamp(_ url: URL) -> String? {
        guard let values = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = values[.modificationDate] as? Date,
              let size = values[.size] as? NSNumber else { return nil }
        // Atomic replacements can share a path and size. Include the inode and
        // creation date as well as modification time before reusing a decode.
        return "\(modified.timeIntervalSince1970):\(size):\(values[.systemFileNumber] ?? ""):\(values[.creationDate] ?? "")"
    }

    nonisolated static func decode(_ url: URL, maximumPixelSize: Int) -> DecodedCapturePreview? {
        guard maximumPixelSize > 0 else { return nil }
        if let source = CGImageSourceCreateWithURL(url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary) {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
            ]
            if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                return DecodedCapturePreview(image: image)
            }
        }
        return drawAppKitPreview(url, maximumPixelSize: maximumPixelSize)
    }

    private nonisolated static func drawAppKitPreview(_ url: URL, maximumPixelSize: Int) -> DecodedCapturePreview? {
        // AppKit also understands vector formats such as SVG that ImageIO cannot
        // thumbnail. Rasterize the local image here, while still on the worker;
        // the main actor receives only the finished, bounded CGImage.
        guard let image = NSImage(contentsOf: url), image.size.width.isFinite, image.size.height.isFinite,
              image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(1, CGFloat(maximumPixelSize) / max(image.size.width, image.size.height))
        let width = max(1, Int((image.size.width * scale).rounded(.down)))
        let height = max(1, Int((image.size.height * scale).rounded(.down)))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        let previousContext = NSGraphicsContext.current
        defer { NSGraphicsContext.current = previousContext }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)),
                   from: .zero, operation: .copy, fraction: 1, respectFlipped: false, hints: nil)
        guard let rendered = context.makeImage() else { return nil }
        return DecodedCapturePreview(image: rendered)
    }
}

@MainActor
private struct CachedCapturePreviewImage<Placeholder: View>: View {
    let request: CapturePreviewImageRequest?
    @ViewBuilder let placeholder: () -> Placeholder
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image { FittedPreviewImage(image: image) }
            else { placeholder() }
        }
        .task(id: request) {
            image = nil
            guard let request, let decoded = await CapturePreviewImageCache.shared.image(for: request),
                  !Task.isCancelled else { return }
            image = NSImage(cgImage: decoded.image,
                size: NSSize(width: CGFloat(decoded.image.width), height: CGFloat(decoded.image.height)))
        }
    }
}

@MainActor
struct CaptureThumbnail: View {
    @Environment(\.workspaceZoom) private var zoom
    let store: CaptureStore
    @ObservedObject var capture: Capture
    var body: some View {
        ZStack {
            Palette.soft
            CachedCapturePreviewImage(request: CapturePreviewFileReference.thumbnail(store: store, capture: capture).map {
                CapturePreviewImageRequest(file: $0, maximumPixelSize: 600, revision: capture.previewState)
            }, placeholder: { placeholder })
            if capture.kind == .video {
                Image(systemName: "play.circle.fill").font(.system(size: zoom.fontSize(25))).foregroundStyle(.white).shadow(radius: 3)
            }
        }.accessibilityHidden(true)
    }

    @ViewBuilder private var placeholder: some View {
        if [.text, .task].contains(capture.kind), let text = capture.originalText, !text.isEmpty {
            Text(String(text.prefix(2_000))).font(.system(size: zoom.fontSize(12), weight: .medium)).lineSpacing(zoom.lineSpacing(3)).lineLimit(12)
                .foregroundStyle(Palette.foreground).multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(zoom.value(12)).clipped()
        } else {
            VStack(spacing: 5) {
                Image(systemName: kindSymbol(capture.kind)).font(.system(size: zoom.fontSize(22), weight: .light))
                Text(kindLabel(capture.kind)).font(.system(size: zoom.fontSize(9), weight: .medium)).lineLimit(1)
            }.foregroundStyle(Palette.muted)
        }
    }
}

@MainActor
private struct FittedPreviewImage: View {
    let image: NSImage

    var body: some View {
        GeometryReader { geometry in
            Image(nsImage: image).resizable().scaledToFit()
                .frame(width: max(0, geometry.size.width - 8), height: max(0, geometry.size.height - 8))
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

@MainActor
struct DetailPreview: View {
    let store: CaptureStore
    @ObservedObject var capture: Capture
    var height: CGFloat? = nil
    var onOpenOriginal: (() -> Void)? = nil
    var openLabel: String? = nil
    var body: some View {
        Group {
            if let file = CapturePreviewFileReference.original(store: store, capture: capture),
               [.image, .video, .pdf, .document, .ai, .file].contains(capture.kind) {
                if let onOpenOriginal {
                    Button(action: onOpenOriginal) {
                        preview(file: file).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(openLabel ?? "Open original file: \(capture.title)")
                    .accessibilityIdentifier(openLabel == nil ? "detail-preview-open-original" : "detail-preview-open-extended")
                    .buddyHelp(openLabel ?? "Open original file")
                } else {
                    preview(file: file)
                }
            } else if capture.thumbnailRelativePath != nil {
                CaptureThumbnail(store: store, capture: capture).frame(height: height ?? 250).clipShape(RoundedRectangle(cornerRadius: 11))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Capture preview")
        .accessibilityIdentifier("detail-preview")
    }

    @ViewBuilder private func preview(file: CapturePreviewFileReference) -> some View {
        switch capture.kind {
        case .image:
            CachedCapturePreviewImage(request: CapturePreviewImageRequest(file: file,
                maximumPixelSize: 1_600, revision: "original"),
                placeholder: { CaptureThumbnail(store: store, capture: capture) })
                .frame(height: height ?? 310).background(Palette.soft)
                .clipShape(RoundedRectangle(cornerRadius: 11)).accessibilityLabel(capture.title)
        case .video, .pdf:
            Group {
                if capture.kind == .video, onOpenOriginal != nil {
                    // The preview opens the full player in the file's normal
                    // application; it must not display inactive controls.
                    CaptureThumbnail(store: store, capture: capture)
                } else {
                    ResolvedCaptureMediaPreview(file: file, kind: capture.kind,
                        showsPDFPageControls: onOpenOriginal == nil,
                        placeholder: { CaptureThumbnail(store: store, capture: capture) })
                }
            }
            .frame(height: height ?? (capture.kind == .video ? 280 : 310))
            .background(Palette.soft).clipShape(RoundedRectangle(cornerRadius: 11))
        case .document, .ai, .file:
            // The cached page thumbnail fits the complete document preview.
            CaptureThumbnail(store: store, capture: capture).frame(height: height ?? 280)
                .clipShape(RoundedRectangle(cornerRadius: 11))
        default: EmptyView()
        }
    }
}

@MainActor
private struct ResolvedCaptureMediaPreview<Placeholder: View>: View {
    let file: CapturePreviewFileReference
    let kind: CaptureKind
    var showsPDFPageControls = true
    @ViewBuilder let placeholder: () -> Placeholder
    @State private var url: URL?

    var body: some View {
        Group {
            if let url {
                if kind == .video { NativeVideo(url: url) }
                else { FittedPDFPreview(url: url, showsPageControls: showsPDFPageControls) }
            } else { placeholder() }
        }
        .task(id: file) {
            url = nil
            let resolved = await CapturePreviewImageCache.shared.resolvedURL(for: file)
            guard !Task.isCancelled else { return }
            url = resolved
        }
    }
}

@MainActor
private struct NativeVideo: View {
    let url: URL
    @State private var player: AVPlayer?
    var body: some View {
        VideoPlayer(player: player).onAppear { player = AVPlayer(url: url) }.onDisappear { player?.pause(); player = nil }
    }
}
