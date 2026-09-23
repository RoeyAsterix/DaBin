import AppKit
import AVKit
import SwiftUI

@MainActor
struct CaptureThumbnail: View {
    let store: CaptureStore
    @ObservedObject var capture: Capture
    var body: some View {
        ZStack {
            Palette.soft
            if let url = store.previewURL(for: capture),
               let image = NSImage(contentsOf: url) {
                FittedPreviewImage(image: image)
            } else {
                VStack(spacing: 5) {
                    Image(systemName: kindSymbol(capture.kind)).font(.system(size: 22, weight: .light))
                    Text(kindLabel(capture.kind)).font(.system(size: 9, weight: .medium)).lineLimit(1)
                }.foregroundStyle(Palette.muted)
            }
            if capture.kind == .video {
                Image(systemName: "play.circle.fill").font(.system(size: 25)).foregroundStyle(.white).shadow(radius: 3)
            }
        }.accessibilityHidden(true)
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
    var body: some View {
        if let url = store.managedURL(for: capture), FileManager.default.fileExists(atPath: url.path) {
            switch capture.kind {
            case .image:
                if let image = NSImage(contentsOf: url) {
                    FittedPreviewImage(image: image).frame(height: 230)
                        .background(Palette.soft).clipShape(RoundedRectangle(cornerRadius: 11)).accessibilityLabel(capture.title)
                }
            case .video: NativeVideo(url: url).frame(height: 205).clipShape(RoundedRectangle(cornerRadius: 11))
            case .pdf: FittedPDFPreview(url: url).frame(height: 230).clipShape(RoundedRectangle(cornerRadius: 11))
            case .document, .ai, .file:
                // Quick Look's embedded viewer has no public fit control. Its
                // cached page thumbnail gives compact previews a full-page fit;
                // Open original remains available for the complete document.
                CaptureThumbnail(store: store, capture: capture).frame(height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
            default: EmptyView()
            }
        } else if capture.thumbnailRelativePath != nil {
            CaptureThumbnail(store: store, capture: capture).frame(height: 165).clipShape(RoundedRectangle(cornerRadius: 11))
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
