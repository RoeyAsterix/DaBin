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

private struct BuddyHelpModifier: ViewModifier {
    @Environment(\.daBinTooltipsEnabled) private var enabled
    let title: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled { content.help(title) }
        else { content }
    }
}

extension View {
    /// Applies hover help while preserving the control's own accessibility semantics.
    func buddyHelp(_ title: String) -> some View {
        modifier(BuddyHelpModifier(title: title))
    }
}

/// One compact icon vocabulary for capture actions and supporting controls.
@MainActor
struct BuddyIconButton: View {
    @Environment(\.daBinAccent) private var accent
    let symbol: String
    let title: String
    var isActive = false
    let action: () -> Void
    @State private var hovered = false
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
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
        .buddyHelp(title)
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
