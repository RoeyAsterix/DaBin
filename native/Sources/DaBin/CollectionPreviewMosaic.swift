import SwiftUI

/// A bounded, stable selection of actual captures, never synthetic thumbnails
/// or action counts. Loading a thumbnail does not reorder an existing mosaic.
@MainActor
struct CollectionPreviewSelection {
    nonisolated static let maximumCount = 4
    let previews: [Capture]
    let totalCount: Int
    var omittedCount: Int { max(0, totalCount - previews.count) }

    init(captures: [Capture]) {
        var seen = Set<UUID>()
        let unique = captures.filter { seen.insert($0.id).inserted }
        totalCount = unique.count
        previews = unique.enumerated().sorted { lhs, rhs in
            let left = Self.priority(lhs.element.kind)
            let right = Self.priority(rhs.element.kind)
            return left == right ? lhs.offset < rhs.offset : left < right
        }.prefix(Self.maximumCount).map(\.element)
    }

    private static func priority(_ kind: CaptureKind) -> Int {
        switch kind {
        case .image, .video: return 0
        case .pdf, .document, .ai: return 1
        case .file: return 2
        case .link: return 3
        case .text, .task: return 4
        }
    }
}

enum CollectionPreviewLayout {
    static func previewHeight(compact: Bool) -> CGFloat { compact ? 112 : 144 }

    /// Grow readable tiles with workspace zoom without turning a collection
    /// back into an oversized hero. Explicit weekly heights remain supported.
    static func previewHeight(compact: Bool, zoom: WorkspaceZoomLayout) -> CGFloat {
        min(compact ? 152 : 192, zoom.value(previewHeight(compact: compact)))
    }

    /// File and text fallbacks need readable labels rather than a media hero.
    /// Keep two-row grids tall enough for an icon and two filename lines even
    /// at reduced zoom; stored thumbnails keep the original artwork budget.
    static func previewHeight(compact: Bool, zoom: WorkspaceZoomLayout,
                              count: Int, hasThumbnail: Bool) -> CGFloat {
        guard !hasThumbnail else { return previewHeight(compact: compact, zoom: zoom) }
        let twoRows = count > 2
        let nominal: CGFloat = twoRows ? (compact ? 132 : 144) : (compact ? 72 : 80)
        let maximum: CGFloat = twoRows ? (compact ? 144 : 160) : (compact ? 88 : 96)
        return max(nominal, min(maximum, zoom.value(nominal)))
    }
}

/// Logical, top-down frames are also available to layout regression tests.
/// Three captures use a hero with two supporting tiles; four use a quiet grid.
struct CollectionPreviewMosaicLayout {
    let frames: [CGRect]

    init(count: Int, size: CGSize, compact: Bool, fallbackOnly: Bool = false) {
        guard size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0, count > 0 else {
            frames = []
            return
        }
        let count = min(CollectionPreviewSelection.maximumCount, count)
        let gap = min(compact ? CGFloat(4) : CGFloat(6), min(size.width, size.height) / 4)
        let halfWidth = max(0, (size.width - gap) / 2)
        let halfHeight = max(0, (size.height - gap) / 2)
        switch count {
        case 1:
            frames = [CGRect(origin: .zero, size: size)]
        case 2:
            frames = [CGRect(x: 0, y: 0, width: halfWidth, height: size.height),
                      CGRect(x: halfWidth + gap, y: 0, width: halfWidth, height: size.height)]
        case 3:
            if fallbackOnly {
                frames = [CGRect(x: 0, y: 0, width: halfWidth, height: halfHeight),
                          CGRect(x: halfWidth + gap, y: 0, width: halfWidth, height: halfHeight),
                          CGRect(x: 0, y: halfHeight + gap, width: size.width, height: halfHeight)]
            } else {
                let heroWidth = max(0, (size.width - gap) * 0.64)
                let supportingWidth = max(0, size.width - gap - heroWidth)
                frames = [CGRect(x: 0, y: 0, width: heroWidth, height: size.height),
                          CGRect(x: heroWidth + gap, y: 0, width: supportingWidth, height: halfHeight),
                          CGRect(x: heroWidth + gap, y: halfHeight + gap,
                                 width: supportingWidth, height: halfHeight)]
            }
        default:
            frames = [CGRect(x: 0, y: 0, width: halfWidth, height: halfHeight),
                      CGRect(x: halfWidth + gap, y: 0, width: halfWidth, height: halfHeight),
                      CGRect(x: 0, y: halfHeight + gap, width: halfWidth, height: halfHeight),
                      CGRect(x: halfWidth + gap, y: halfHeight + gap,
                             width: halfWidth, height: halfHeight)]
        }
    }
}

/// Only already-generated local thumbnails are decoded by CaptureThumbnail's
/// bounded background cache. This surface has no buttons, players or IO of its
/// own, so a parent collection can make the whole preview its expansion target.
@MainActor
struct CollectionPreviewMosaic: View {
    @Environment(\.workspaceZoom) private var zoom
    let store: CaptureStore
    let captures: [Capture]
    var compact = false
    var height: CGFloat? = nil

    private var selection: CollectionPreviewSelection { CollectionPreviewSelection(captures: captures) }

    var body: some View {
        let selection = self.selection
        // Canonical saved references only; image decoding remains in the
        // bounded background thumbnail cache.
        let hasThumbnail = selection.previews.contains {
            CapturePreviewFileReference.thumbnail(store: store, capture: $0) != nil
        }
        let hasFallback = selection.previews.contains {
            CapturePreviewFileReference.thumbnail(store: store, capture: $0) == nil
        }
        let naturalHeight = CollectionPreviewLayout.previewHeight(compact: compact, zoom: zoom,
            count: selection.previews.count, hasThumbnail: hasThumbnail)
        // Weekly artwork keeps its explicit height. Generic tiles may need a
        // larger useful minimum to show both filename lines in two-row grids.
        let gridHeight = hasThumbnail ? (height ?? naturalHeight) : max(height ?? 0, naturalHeight)
        if !selection.previews.isEmpty {
            VStack(alignment: .trailing, spacing: 4) {
                if hasFallback && selection.omittedCount > 0 {
                    Text("+\(selection.omittedCount) more")
                        .font(.system(size: zoom.fontSize(10), weight: .semibold))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                        .accessibilityHidden(true)
                }
                GeometryReader { geometry in
                    let layout = CollectionPreviewMosaicLayout(count: selection.previews.count,
                                                              size: geometry.size, compact: compact,
                                                              fallbackOnly: !hasThumbnail)
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(selection.previews.enumerated()), id: \.element.id) { index, capture in
                            if layout.frames.indices.contains(index) {
                                let rect = layout.frames[index]
                                CollectionPreviewCell(store: store, capture: capture,
                                                      size: rect.size, compact: compact)
                                    .frame(width: rect.width, height: rect.height)
                                    .position(x: rect.midX, y: rect.midY)
                                    .accessibilityIdentifier("collection-preview-cell-\(capture.id.uuidString)")
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .overlay(alignment: .bottomTrailing) {
                        if !hasFallback && selection.omittedCount > 0 {
                            Text("+\(selection.omittedCount) more")
                                .font(.system(size: zoom.fontSize(compact ? 10 : 11), weight: .semibold))
                                .foregroundStyle(Palette.foreground)
                                .padding(.horizontal, compact ? 7 : 9).padding(.vertical, 5)
                                .background(Palette.surface.opacity(0.96),
                                            in: Capsule(style: .continuous))
                                .overlay(Capsule(style: .continuous).strokeBorder(Palette.line, lineWidth: 0.5))
                                .padding(7)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .frame(height: gridHeight)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Collection contents preview")
            .accessibilityIdentifier("collection-preview-mosaic")
        }
    }
}

@MainActor
private struct CollectionPreviewCell: View {
    @Environment(\.workspaceZoom) private var zoom
    @Environment(\.daBinAccent) private var accent
    let store: CaptureStore
    @ObservedObject var capture: Capture
    let size: CGSize
    let compact: Bool

    private var small: Bool { size.width < 110 || size.height < 100 }
    private var title: String {
        if !capture.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return capture.title }
        if let filename = capture.originalFilename, !filename.isEmpty { return filename }
        return "Untitled \(captureTypeLabel(capture.kind).lowercased())"
    }
    private var excerpt: String {
        let content = capture.originalText ?? capture.previewDescription
        return String(content.prefix(600)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var hasStoredThumbnail: Bool {
        CapturePreviewFileReference.thumbnail(store: store, capture: capture) != nil
    }

    var body: some View {
        ZStack {
            Palette.soft
            if hasStoredThumbnail {
                CaptureThumbnail(store: store, capture: capture)
                    .overlay(alignment: .bottom) { thumbnailCaption }
            } else {
                fallback
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Palette.line.opacity(0.65), lineWidth: 0.5))
        .clipped()
    }

    private var thumbnailCaption: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: zoom.fontSize(small ? 9 : 11), weight: .medium))
                .lineLimit(1).truncationMode(.middle)
            if !small {
                Text(captureTypeLabel(capture.kind)).font(.system(size: zoom.fontSize(9)))
                    .foregroundStyle(Palette.muted).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, small ? 6 : 9).padding(.vertical, small ? 5 : 7)
        .foregroundStyle(Palette.foreground)
        .background(Palette.surface.opacity(0.94))
    }

    @ViewBuilder private var fallback: some View {
        if size.height < 64 {
            // Mixed weekly grids can give a file just a 34pt supporting row.
            // Keep its icon beside the filename so both lines fit the row.
            let lines = size.height < 32 ? 1 : 2
            let fontSize = min(zoom.fontSize(10), max(9.5, (size.height - 6) / (CGFloat(lines) * 1.3)))
            HStack(alignment: .top, spacing: 4) {
                Image(systemName: kindSymbol(capture.kind))
                    .font(.system(size: zoom.fontSize(11), weight: .medium))
                    .foregroundStyle(accent)
                Text(title)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(Palette.foreground)
                    .lineLimit(lines).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack(alignment: .leading, spacing: small ? 4 : 8) {
                HStack(spacing: 4) {
                    Image(systemName: kindSymbol(capture.kind))
                        .font(.system(size: zoom.fontSize(small ? 11 : 16), weight: .medium))
                    if !small {
                        Text(captureTypeLabel(capture.kind))
                            .font(.system(size: zoom.fontSize(9), weight: .semibold)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(accent)
                Text(title)
                    .font(.system(size: zoom.fontSize(small ? 10 : 13), weight: .semibold))
                    .foregroundStyle(Palette.foreground)
                    .lineLimit(small ? 2 : 3).truncationMode(.middle)
                if !small && !excerpt.isEmpty {
                    Text(excerpt).font(.system(size: zoom.fontSize(compact ? 10 : 11)))
                        .lineSpacing(zoom.lineSpacing(2)).foregroundStyle(Palette.muted)
                        .lineLimit(size.height > 170 ? 7 : 3)
                } else if !small, let url = capture.originalURL, !url.isEmpty {
                    Text(url).font(.system(size: zoom.fontSize(10))).foregroundStyle(Palette.muted).lineLimit(3)
                }
                Spacer(minLength: 0)
            }
            .padding(small ? 7 : 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
