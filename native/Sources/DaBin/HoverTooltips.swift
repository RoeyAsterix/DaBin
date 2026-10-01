import AppKit
import SwiftUI

/// Resolve real control bounds at the board's overlay, not stale row offsets.
struct HoverTooltipAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(value: inout [String: Anchor<CGRect>],
                       nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

@MainActor
struct HoverTooltipOverlay: View {
    @ObservedObject var controller: TimelineTooltipController
    let anchors: [String: Anchor<CGRect>]
    let isEnabled: Bool

    var body: some View {
        GeometryReader { geometry in
            if isEnabled, let tooltip = controller.visible,
               let anchor = anchors[tooltip.id],
               let layout = HoverTooltipLayout.make(text: tooltip.text, anchor: geometry[anchor],
                                                     containerSize: geometry.size) {
                HoverTooltipBubble(text: tooltip.text, layout: layout)
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

@MainActor
private struct HoverTooltipScope: ViewModifier {
    @Environment(\.daBinTooltipsEnabled) private var enabled
    @StateObject private var controller = TimelineTooltipController()

    func body(content: Content) -> some View {
        content
            .environment(\.timelineTooltipController, controller)
            .overlayPreferenceValue(HoverTooltipAnchorKey.self) { anchors in
                HoverTooltipOverlay(controller: controller, anchors: anchors, isEnabled: enabled)
            }
            .onChange(of: enabled, initial: true) { _, value in controller.setEnabled(value) }
            .onAppear { controller.setPresentationActive(true) }
            .onDisappear { controller.setPresentationActive(false) }
    }
}

extension View {
    /// Presented content has its own hosting tree and needs a local anchor
    /// resolver. The global Settings preference still flows into this scope.
    @MainActor
    func hoverTooltips() -> some View { modifier(HoverTooltipScope()) }
}

struct HoverTooltipLayout {
    let frame: CGRect
    let pointsUp: Bool
    let pointerX: CGFloat
    let textHeight: CGFloat

    static func make(text: String, anchor: CGRect, containerSize: CGSize) -> Self? {
        let board = CGRect(origin: .zero, size: containerSize)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              [containerSize.width, containerSize.height, anchor.minX, anchor.minY,
               anchor.width, anchor.height].allSatisfy(\.isFinite),
              containerSize.width >= 48, containerSize.height >= 48,
              !anchor.isInfinite, !anchor.isNull,
              anchor.width > 0, anchor.height > 0, anchor.intersects(board) else { return nil }
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let maximumWidth = min(280, containerSize.width - 16)
        let natural = (text as NSString).size(withAttributes: [.font: font]).width
        let width = min(maximumWidth, max(28, ceil(natural) + 14))
        let measured = (text as NSString).boundingRect(
            with: CGSize(width: width - 14, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let textHeight = max(lineHeight, min(lineHeight * 3,
            min(ceil(measured.height), containerSize.height - 29)))
        let height = textHeight + 8 + 5
        let pointsUp = anchor.maxY + 6 + height <= containerSize.height - 8
        let wantedY = pointsUp ? anchor.maxY + 6 : anchor.minY - 6 - height
        let origin = CGPoint(x: min(max(8, anchor.midX - width / 2), containerSize.width - 8 - width),
                             y: min(max(8, wantedY), containerSize.height - 8 - height))
        return Self(frame: CGRect(origin: origin, size: CGSize(width: width, height: height)),
                    pointsUp: pointsUp, pointerX: min(max(8, anchor.midX - origin.x), width - 8),
                    textHeight: textHeight)
    }
}

/// One noninteractive, bounded label for every SwiftUI hover-help control.
/// It never opens a window or changes the content's measured size.
@MainActor
struct HoverTooltipBubble: View {
    let text: String
    let layout: HoverTooltipLayout

    private var pointer: some View {
        HoverTooltipPointer(pointsUp: layout.pointsUp)
            .fill(Palette.surface)
            .overlay(HoverTooltipPointer(pointsUp: layout.pointsUp).stroke(Palette.line, lineWidth: 0.75))
            .frame(width: 10, height: 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, layout.pointerX - 5)
    }

    private var label: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Palette.foreground)
            .lineLimit(3)
            .frame(width: layout.frame.width - 14, height: layout.textHeight)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 7))
            .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.line, lineWidth: 0.75) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if layout.pointsUp { pointer }
            label
            if !layout.pointsUp { pointer }
        }
        .frame(width: layout.frame.width, height: layout.frame.height)
        .shadow(color: .black.opacity(0.16), radius: 5, y: 2)
        .position(x: layout.frame.midX, y: layout.frame.midY)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct HoverTooltipPointer: Shape {
    let pointsUp: Bool

    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: pointsUp ? rect.minY : rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: pointsUp ? rect.maxY : rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: pointsUp ? rect.maxY : rect.minY))
            path.closeSubpath()
        }
    }
}
