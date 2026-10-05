import SwiftUI

private struct DaBinTooltipsEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// A visual preference only. Accessibility labels never depend on this value.
    var daBinTooltipsEnabled: Bool {
        get { self[DaBinTooltipsEnabledKey.self] }
        set { self[DaBinTooltipsEnabledKey.self] = newValue }
    }
}

@MainActor
private struct BuddyHelpModifier: ViewModifier {
    @Environment(\.daBinTooltipsEnabled) private var enabled
    @Environment(\.isEnabled) private var controlEnabled
    @Environment(\.timelineTooltipController) private var controller
    @Environment(\.hoverTooltipActiveID) private var visibleTooltipID
    @State private var generatedID = UUID().uuidString
    @State private var hovered = false
    let title: String
    var explicitID: String?
    var isFocused: Bool

    private var id: String { explicitID ?? generatedID }
    private var descriptor: TimelineTooltipDescriptor {
        TimelineTooltipDescriptor(id: id, text: title, index: 0, itemCount: 1)
    }
    private var publishesAnchor: Bool {
        HoverTooltipAnchorPolicy.shouldPublish(id: id, visibleID: visibleTooltipID,
            enabled: enabled, controlEnabled: controlEnabled, hovered: hovered, focused: isFocused)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if let controller {
            content
                .accessibilityHint(title)
                // Idle lazy rows do not contribute bounds to the board's
                // global overlay. Hover/focus publishes before the dwell
                // finishes; the visible descriptor keeps explicit QA/show
                // requests working without materializing every row's anchor.
                .anchorPreference(key: HoverTooltipAnchorKey.self, value: .bounds) {
                    publishesAnchor ? [id: $0] : [:]
                }
                .onHover { hovered = $0; update(controller) }
                .onChange(of: isFocused) { _, _ in update(controller) }
                .onChange(of: enabled) { _, _ in update(controller) }
                .onChange(of: controlEnabled) { _, _ in update(controller) }
                .onChange(of: title) { _, _ in update(controller) }
                .onDisappear { controller.end(id: id) }
                .simultaneousGesture(TapGesture().onEnded { controller.activate(id: id) })
        } else if enabled {
            content.accessibilityHint(title).help(title)
        } else {
            content.accessibilityHint(title)
        }
    }

    private func update(_ controller: TimelineTooltipController) {
        // The root and descendants receive the same preference. Synchronize
        // before beginning so re-enabling under a stationary pointer works
        // regardless of SwiftUI's parent/child change-delivery order.
        controller.setEnabled(enabled)
        if enabled && controlEnabled && (hovered || isFocused) {
            controller.begin(descriptor, immediate: isFocused && !hovered)
        } else {
            controller.end(id: id)
        }
    }
}

extension View {
    /// Applies hover help while preserving the control's own accessibility semantics.
    @MainActor
    func buddyHelp(_ title: String, id: String? = nil, isFocused: Bool = false) -> some View {
        modifier(BuddyHelpModifier(title: title, explicitID: id, isFocused: isFocused))
    }
}

/// One compact icon vocabulary for capture actions and supporting controls.
@MainActor
struct BuddyIconButton: View {
    @Environment(\.daBinAccent) private var accent
    @Environment(\.workspaceZoom) private var zoom
    @Environment(\.timelineTooltipController) private var tooltipController
    let symbol: String
    let title: String
    var visualLabel: String? = nil
    var isActive = false
    var tooltipID: String? = nil
    let action: () -> Void
    @State private var hovered = false
    @State private var helpID = UUID().uuidString
    @FocusState private var focused: Bool

    private var effectiveTooltipID: String { tooltipID ?? helpID }

    var body: some View {
        Button {
            tooltipController?.activate(id: effectiveTooltipID)
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)
                if let visualLabel {
                    Text(visualLabel).font(.system(size: zoom.fontSize(13), weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, visualLabel == nil ? 0 : 8)
            .padding(.vertical, visualLabel == nil ? 0 : 5)
            .frame(minWidth: 32, minHeight: 32)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(BuddyIconButtonStyle(accent: accent, isActive: isActive,
                                          hovered: hovered, focused: focused))
        .focused($focused)
        .onHover { hovered = $0 }
        .buddyHelp(title, id: effectiveTooltipID, isFocused: focused)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityRemoveTraits(isActive ? [] : .isSelected)
    }
}

/// Keep one set of labeled actions alive while moving whole buttons onto new
/// rows. The label and symbol remain inside the same native button hit region.
struct BuddyActionFlow: Layout {
    var spacing: CGFloat = 6

    private func frames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        var result: [CGRect] = [], x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let ideal = view.sizeThatFits(.unspecified)
            let size = view.sizeThatFits(ProposedViewSize(width: min(width, ideal.width), height: nil))
            if x > 0 && x + size.width > width {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            result.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
        return result
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let intrinsic = subviews.reduce(CGFloat(0)) { $0 + $1.sizeThatFits(.unspecified).width }
            + spacing * CGFloat(max(0, subviews.count - 1))
        let width = proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil } ?? intrinsic
        return CGSize(width: width, height: frames(width: width, subviews: subviews).map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, frame) in frames(width: bounds.width, subviews: subviews).enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                                 anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }
}

private struct BuddyIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    let accent: Color
    let isActive: Bool
    let hovered: Bool
    let focused: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle((isActive ? accent : Palette.muted).opacity(enabled ? 1 : 0.38))
            .background {
                RoundedRectangle(cornerRadius: 8).fill(!enabled ? Color.clear : configuration.isPressed ? Palette.line
                                            : isActive || hovered ? Palette.soft : Color.clear)
            }
            .overlay {
                if focused {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(accent.opacity(0.85), lineWidth: 1.5)
                }
            }
    }
}
