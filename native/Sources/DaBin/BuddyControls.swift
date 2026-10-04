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
    @Environment(\.timelineTooltipController) private var tooltipController
    let symbol: String
    let title: String
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
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .frame(width: 32, height: 32)
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
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
