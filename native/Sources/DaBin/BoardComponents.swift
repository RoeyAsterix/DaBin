import AppKit
import SwiftUI

/// Shared geometry for the two compact timeline icon rows. The rows have a
/// different number of controls, so each one distributes its fixed-size
/// buttons between the same leading and trailing edges.
enum TimelineIconRowMetrics {
    static let rowWidth: CGFloat = 280
    static let controlWidth: CGFloat = 40
    static let controlHeight: CGFloat = 34
    static let symbolCanvasSize: CGFloat = 18
    static let symbolPointSize: CGFloat = 15
    static let stateSurfaceDiameter: CGFloat = 30
    static let focusRingDiameter: CGFloat = 31

    static func spacing(itemCount: Int) -> CGFloat {
        guard itemCount > 1 else { return 0 }
        return (rowWidth - CGFloat(itemCount) * controlWidth) / CGFloat(itemCount - 1)
    }
}

enum Palette {
    static let background = adaptive(light: 0xFDFCFE, dark: 0x1D1C21)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x252328)
    static let foreground = adaptive(light: 0x2B2731, dark: 0xEBEAED)
    static let muted = adaptive(light: 0x615A69, dark: 0xA9A6AE)
    static let line = adaptive(light: 0xE3E0E6, dark: 0x3C3940)
    static let soft = adaptive(light: 0xF3F1F5, dark: 0x2D2A30)
    static let task = adaptive(light: 0xB43D45, dark: 0xF28D99)
    static let completed = adaptive(light: 0x287447, dark: 0x7CCD99)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((value >> 16) & 255) / 255,
                           green: Double((value >> 8) & 255) / 255,
                           blue: Double(value & 255) / 255, alpha: 1)
        })
    }
}

@MainActor
struct FilterBar: View {
    @Binding var selection: CaptureFilter
    var body: some View {
        HStack(spacing: TimelineIconRowMetrics.spacing(itemCount: CaptureFilter.allCases.count)) {
            ForEach(CaptureFilter.allCases) { filter in
                AccentIconButton(symbol: symbol(for: filter), label: label(for: filter),
                                 selected: selection == filter,
                                 accessibilityIdentifier: "filter-\(filter.rawValue)") {
                    selection = filter
                }
            }
        }
        .frame(width: TimelineIconRowMetrics.rowWidth,
               height: TimelineIconRowMetrics.controlHeight)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 0.5) }
    }

    private func symbol(for filter: CaptureFilter) -> String {
        switch filter {
        case .all: return "square.grid.2x2"
        case .text: return "text.alignleft"
        case .links: return "link"
        case .files: return "doc.text"
        case .media: return "photo.on.rectangle"
        case .tasks: return "checkmark"
        }
    }

    private func label(for filter: CaptureFilter) -> String {
        filter == .text ? "Copy/paste text" : filter.title
    }
}

/// The shared visual language for the two centered icon rows. Every control
/// keeps the same hit target while hover, press and keyboard focus remain
/// visible against either board appearance.
@MainActor
struct AccentIconButton: View {
    @Environment(\.daBinAccent) private var accent
    let symbol: String
    let label: String
    var selected = false
    var accessibilityIdentifier: String? = nil
    let action: () -> Void
    @State private var hovered = false
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: TimelineIconRowMetrics.symbolPointSize, weight: .regular))
                .accessibilityHidden(true)
                .frame(width: TimelineIconRowMetrics.symbolCanvasSize,
                       height: TimelineIconRowMetrics.symbolCanvasSize)
                .frame(width: TimelineIconRowMetrics.controlWidth,
                       height: TimelineIconRowMetrics.controlHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(AccentIconButtonStyle(accent: accent, selected: selected,
                                           hovered: hovered, focused: focused))
        .focused($focused)
        .onHover { hovered = $0 }
        .help(label)
        .accessibilityLabel(label)
        .accessibilityIdentifier(accessibilityIdentifier ?? label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityRemoveTraits(selected ? [] : .isSelected)
    }
}

private struct AccentIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let accent: Color
    let selected: Bool
    let hovered: Bool
    let focused: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(accent.opacity(isEnabled ? (selected ? 1 : 0.82) : 0.35))
            .background {
                if selected {
                    Circle().fill(accent.opacity(configuration.isPressed ? 0.20 : 0.13))
                        .frame(width: TimelineIconRowMetrics.stateSurfaceDiameter,
                               height: TimelineIconRowMetrics.stateSurfaceDiameter)
                } else if hovered || configuration.isPressed {
                    Circle().fill(accent.opacity(configuration.isPressed ? 0.18 : 0.09))
                        .frame(width: TimelineIconRowMetrics.stateSurfaceDiameter,
                               height: TimelineIconRowMetrics.stateSurfaceDiameter)
                }
            }
            .overlay {
                if focused {
                    Circle().stroke(accent.opacity(0.82), lineWidth: 1.5)
                        .frame(width: TimelineIconRowMetrics.focusRingDiameter,
                               height: TimelineIconRowMetrics.focusRingDiameter)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A label for the Settings menu, whose native menu behavior cannot use a
/// ButtonStyle. Its hover and focus surfaces match AccentIconButton.
@MainActor
struct AccentIconMenuLabel: View {
    @Environment(\.daBinAccent) private var accent
    let symbol: String
    @Binding var hovered: Bool
    let focused: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: TimelineIconRowMetrics.symbolPointSize, weight: .regular))
            .foregroundStyle(accent.opacity(0.82))
            .frame(width: TimelineIconRowMetrics.symbolCanvasSize,
                   height: TimelineIconRowMetrics.symbolCanvasSize)
            .frame(width: TimelineIconRowMetrics.controlWidth,
                   height: TimelineIconRowMetrics.controlHeight)
            .contentShape(Rectangle())
            .background {
                if hovered {
                    Circle().fill(accent.opacity(0.09))
                        .frame(width: TimelineIconRowMetrics.stateSurfaceDiameter,
                               height: TimelineIconRowMetrics.stateSurfaceDiameter)
                }
            }
            .overlay {
                if focused {
                    Circle().stroke(accent.opacity(0.82), lineWidth: 1.5)
                        .frame(width: TimelineIconRowMetrics.focusRingDiameter,
                               height: TimelineIconRowMetrics.focusRingDiameter)
                }
            }
            .onHover { hovered = $0 }
    }
}

@MainActor
struct SmallIcon: View {
    let symbol: String
    let label: String
    var tint: Color = Palette.muted
    var size: CGFloat = 30
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 13)).frame(width: size, height: 30).contentShape(Rectangle()) }
            .buttonStyle(.plain).foregroundStyle(tint).help(label).accessibilityLabel(label)
    }
}

@MainActor
struct TimelineModePicker: View {
    @Environment(\.daBinAccent) private var accent
    @ObservedObject var state: AppState
    var width: CGFloat = 108
    var compact = false

    private var selection: Binding<BoardTimelineMode> {
        Binding(get: { state.timelineMode }, set: { state.selectTimelineMode($0) })
    }

    var body: some View {
        Picker("Board view", selection: selection) {
            Text("Daily").tag(BoardTimelineMode.daily)
            Text("Weekly").tag(BoardTimelineMode.weekly)
        }
        .pickerStyle(.segmented)
        .controlSize(compact ? .mini : .small)
        .tint(accent)
        .frame(width: width)
        .help("Switch between one day and seven days")
        .accessibilityLabel("Board view")
    }
}

@MainActor
struct EmptyMessage: View {
    @Environment(\.daBinAccent) private var accent
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 8)
            Image(systemName: symbol).font(.system(size: 26, weight: .light)).foregroundStyle(accent).padding(.bottom, 3)
            Text(title).font(.system(size: 17, weight: .medium))
            Text(message).font(.system(size: 12)).foregroundStyle(Palette.muted).multilineTextAlignment(.center).lineSpacing(3).frame(maxWidth: 265).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
        }.padding(.horizontal, 18).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
