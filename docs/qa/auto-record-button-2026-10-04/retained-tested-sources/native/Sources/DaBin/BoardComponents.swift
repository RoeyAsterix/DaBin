import AppKit
import SwiftUI

/// Shared geometry for the two compact timeline icon rows. The rows have a
/// different number of controls, so each one distributes its fixed-size
/// buttons between the same leading and trailing edges.
enum TimelineIconRowMetrics {
    static let iconScale: CGFloat = 1.10
    static let rowWidth: CGFloat = 280
    static let controlWidth: CGFloat = 40
    static let controlHeight: CGFloat = 34
    static let symbolCanvasSize: CGFloat = 26
    static let symbolPointSize: CGFloat = 15 * iconScale
    static let navigationSymbolPointSize: CGFloat = 13 * iconScale
    static let stateSurfaceDiameter: CGFloat = 30
    static let focusRingDiameter: CGFloat = 31

    static func spacing(itemCount: Int) -> CGFloat {
        guard itemCount > 1 else { return 0 }
        return (rowWidth - CGFloat(itemCount) * controlWidth) / CGFloat(itemCount - 1)
    }
}

/// Compact first-row measurements. The mode pair stays within the former
/// segmented control's width while using the same targets as the icon rows.
enum TimelineNavigationMetrics {
    static let horizontalPadding: CGFloat = 8
    static let itemSpacing: CGFloat = 2
    static let logoWidth: CGFloat = 72
    static let navigationButtonWidth: CGFloat = 24
    static let closeButtonWidth: CGFloat = 24
    static let dailyDateWidth: CGFloat = 48
    static let weeklyDateWidth: CGFloat = 72
    static let modeGroupWidth = TimelineIconRowMetrics.controlWidth * 2

    static func modeAnchorX(weekly: Bool, index: Int) -> CGFloat {
        let dateWidth = weekly ? weeklyDateWidth : dailyDateWidth
        let modeLeading = horizontalPadding
            + logoWidth + itemSpacing
            + navigationButtonWidth + itemSpacing
            + dateWidth + itemSpacing
            + navigationButtonWidth + itemSpacing
        return modeLeading + TimelineIconRowMetrics.controlWidth / 2
            + CGFloat(index) * TimelineIconRowMetrics.controlWidth
    }

    static func autoCaptureAnchorX(weekly: Bool) -> CGFloat {
        modeAnchorX(weekly: weekly, index: 1)
            + TimelineIconRowMetrics.controlWidth + itemSpacing
    }

    static func fixedContentWidth(weekly: Bool) -> CGFloat {
        let dateWidth = weekly ? weeklyDateWidth : dailyDateWidth
        let fixedWidths = logoWidth + navigationButtonWidth + dateWidth
            + navigationButtonWidth + modeGroupWidth
            + TimelineIconRowMetrics.controlWidth + closeButtonWidth
        // Eight visible controls create seven fixed inter-item gaps. The
        // remaining width belongs to the flexible drag area before Close.
        return fixedWidths + itemSpacing * 7
    }
}

/// The compact hover label is coordinated at header level so it can draw
/// below both icon rows without changing either row's measured size.
struct TimelineTooltipDescriptor: Equatable, Identifiable {
    enum Row: Equatable { case navigation, primary, filters }

    let id: String
    let text: String
    let index: Int
    let itemCount: Int
    var row: Row = .primary
    var fixedAnchorX: CGFloat? = nil

    func anchorX(in containerWidth: CGFloat) -> CGFloat {
        if let fixedAnchorX { return fixedAnchorX }
        let leading = max(0, (containerWidth - TimelineIconRowMetrics.rowWidth) / 2)
        let step = TimelineIconRowMetrics.controlWidth
            + TimelineIconRowMetrics.spacing(itemCount: itemCount)
        return leading + TimelineIconRowMetrics.controlWidth / 2 + CGFloat(index) * step
    }
}

@MainActor
final class TimelineTooltipController: ObservableObject {
    @Published private(set) var visible: TimelineTooltipDescriptor?
    private(set) var isEnabled = true
    private(set) var isPresentationActive = true

    private let delayNanoseconds: UInt64
    private var pending: Task<Void, Never>?
    private var activeID: String?
    private var activeDescriptor: TimelineTooltipDescriptor?
    private var suppressedID: String?

    init(delay: TimeInterval = 0.22) {
        delayNanoseconds = UInt64(max(0, delay) * 1_000_000_000)
    }

    deinit { pending?.cancel() }

    func begin(_ descriptor: TimelineTooltipDescriptor, immediate: Bool = false) {
        guard isEnabled && isPresentationActive else { return }
        activeDescriptor = descriptor
        if activeID == descriptor.id, suppressedID != descriptor.id {
            if visible != nil { visible = descriptor; return }
            if pending != nil, !immediate { return }
        }
        if visible?.id != descriptor.id { visible = nil }
        activeID = descriptor.id
        pending?.cancel()
        guard suppressedID != descriptor.id else { return }
        guard !immediate, delayNanoseconds > 0 else {
            visible = descriptor
            return
        }
        pending = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: self?.delayNanoseconds ?? 0) }
            catch { return }
            guard let self, self.isEnabled, self.isPresentationActive, self.activeID == descriptor.id,
                  self.suppressedID != descriptor.id else { return }
            self.pending = nil
            self.visible = self.activeDescriptor
        }
    }

    func end(id: String) {
        if visible?.id == id { visible = nil }
        if suppressedID == id { suppressedID = nil }
        guard activeID == id else { return }
        pending?.cancel()
        pending = nil
        activeID = nil
        activeDescriptor = nil
    }

    /// Hide a label before its action opens a route, popover, or menu. It stays
    /// hidden until the pointer and keyboard focus leave that control.
    func activate(id: String) {
        pending?.cancel()
        pending = nil
        suppressedID = id
        if visible?.id == id { visible = nil }
    }

    func dismiss() {
        pending?.cancel()
        pending = nil
        activeID = nil
        activeDescriptor = nil
        suppressedID = nil
        visible = nil
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled { dismiss() }
    }

    func setPresentationActive(_ active: Bool) {
        isPresentationActive = active
        if !active { dismiss() }
    }

    /// Deterministic visual QA hook; production hover still uses `begin`.
    func presentImmediately(_ descriptor: TimelineTooltipDescriptor) {
        dismiss()
        guard isEnabled && isPresentationActive else { return }
        activeID = descriptor.id
        activeDescriptor = descriptor
        visible = descriptor
    }
}

private struct TimelineTooltipControllerKey: EnvironmentKey {
    static let defaultValue: TimelineTooltipController? = nil
}

extension EnvironmentValues {
    var timelineTooltipController: TimelineTooltipController? {
        get { self[TimelineTooltipControllerKey.self] }
        set { self[TimelineTooltipControllerKey.self] = newValue }
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
            ForEach(Array(CaptureFilter.allCases.enumerated()), id: \.element.id) { index, filter in
                AccentIconButton(symbol: symbol(for: filter), label: label(for: filter),
                                 tooltip: TimelineTooltipDescriptor(
                                    id: "filter-tooltip-\(filter.rawValue)",
                                    text: filter.tooltipLabel,
                                    index: index,
                                    itemCount: CaptureFilter.allCases.count,
                                    row: .filters
                                 ),
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

extension CaptureFilter {
    var tooltipLabel: String {
        switch self {
        case .all: return "All"
        case .text: return "Text"
        case .links: return "Links"
        case .files: return "Files"
        case .media: return "Media"
        case .tasks: return "Tasks"
        }
    }
}

/// The shared visual language for the two centered icon rows. Every control
/// keeps the same hit target while hover, press and keyboard focus remain
/// visible against either board appearance.
@MainActor
struct AccentIconButton: View {
    @Environment(\.daBinAccent) private var accent
    @Environment(\.timelineTooltipController) private var tooltipController
    let symbol: String
    let label: String
    var tooltip: TimelineTooltipDescriptor? = nil
    var selected = false
    var emphasized = false
    var symbolRotationDegrees = 0.0
    var accessibilityIdentifier: String? = nil
    let action: () -> Void
    @State private var hovered = false
    @State private var helpID = UUID().uuidString
    @FocusState private var focused: Bool

    private var effectiveTooltipID: String { tooltip?.id ?? helpID }

    var body: some View {
        Button {
            tooltipController?.activate(id: effectiveTooltipID)
            action()
        } label: {
            Image(systemName: symbol)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: TimelineIconRowMetrics.symbolPointSize, weight: .medium))
                .rotationEffect(.degrees(symbolRotationDegrees), anchor: .center)
                .accessibilityHidden(true)
                .frame(width: TimelineIconRowMetrics.symbolCanvasSize,
                       height: TimelineIconRowMetrics.symbolCanvasSize)
                .frame(width: TimelineIconRowMetrics.controlWidth,
                       height: TimelineIconRowMetrics.controlHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(AccentIconButtonStyle(accent: accent, selected: selected,
                                           emphasized: emphasized,
                                           hovered: hovered, focused: focused))
        .buddyHelp(tooltip?.text ?? label, id: effectiveTooltipID, isFocused: focused)
        .focused($focused)
        .onHover { isHovering in
            hovered = isHovering
        }
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
    let emphasized: Bool
    let hovered: Bool
    let focused: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(accent.opacity(isEnabled ? (selected || emphasized ? 1 : 0.92) : 0.35))
            .background {
                if selected {
                    Circle().fill(accent.opacity(configuration.isPressed ? 0.20 : 0.13))
                        .frame(width: TimelineIconRowMetrics.stateSurfaceDiameter,
                               height: TimelineIconRowMetrics.stateSurfaceDiameter)
                        .shadow(color: emphasized ? accent.opacity(0.42) : .clear,
                                radius: emphasized ? 3 : 0)
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
            .opacity(configuration.isPressed ? 0.90 : 1)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

@MainActor
struct SmallIcon: View {
    @Environment(\.timelineTooltipController) private var tooltipController
    @State private var helpID = UUID().uuidString
    let symbol: String
    let label: String
    var tint: Color = Palette.muted
    var size: CGFloat = 30
    let action: () -> Void
    var body: some View {
        Button {
            tooltipController?.activate(id: helpID)
            action()
        } label: {
            Image(systemName: symbol)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: TimelineIconRowMetrics.navigationSymbolPointSize,
                              weight: .medium))
                .frame(width: size, height: 30)
                .contentShape(Rectangle())
        }
            .buttonStyle(.plain).foregroundStyle(tint).buddyHelp(label, id: helpID).accessibilityLabel(label)
    }
}

@MainActor
struct TimelineModeControl: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 0) {
            modeButton(.daily, symbol: "1.calendar", index: 0)
            modeButton(.weekly, symbol: "7.calendar", index: 1)
        }
        .frame(width: TimelineNavigationMetrics.modeGroupWidth,
               height: TimelineIconRowMetrics.controlHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Board view")
        .onMoveCommand { direction in
            switch direction {
            case .left: state.selectTimelineMode(.daily)
            case .right: state.selectTimelineMode(.weekly)
            default: break
            }
        }
    }

    private func modeButton(_ mode: BoardTimelineMode, symbol: String,
                            index: Int) -> some View {
        let daily = mode == .daily
        let title = daily ? "Daily" : "Weekly"
        let label = daily ? "Daily view" : "Weekly view"
        let tooltip = TimelineTooltipDescriptor(
            id: "timeline-mode-tooltip-\(daily ? "daily" : "weekly")",
            text: title,
            index: index,
            itemCount: 2,
            row: .navigation,
            fixedAnchorX: TimelineNavigationMetrics.modeAnchorX(
                weekly: state.timelineMode == .weekly,
                index: index
            )
        )
        return AccentIconButton(
            symbol: symbol,
            label: label,
            tooltip: tooltip,
            selected: state.timelineMode == mode,
            accessibilityIdentifier: "timeline-mode-\(daily ? "daily" : "weekly")"
        ) {
            state.selectTimelineMode(mode)
        }
    }
}

@MainActor
struct AutoCaptureHeaderButton: View {
    @ObservedObject private var service: AutoCaptureService
    @ObservedObject private var settings: AutoCaptureSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.timelineTooltipController) private var tooltipController
    let weekly: Bool
    let statusText: String
    let isVisible: Bool
    let action: () -> Void
    @State private var hovered = false
    @FocusState private var focused: Bool

    init(service: AutoCaptureService, weekly: Bool, statusText: String, isVisible: Bool = true,
         action: @escaping () -> Void) {
        self.service = service
        settings = service.settings
        self.weekly = weekly
        self.statusText = statusText
        self.isVisible = isVisible
        self.action = action
    }

    private var isOn: Bool { settings.isEnabled && !settings.isPaused }
    private var presentation: AutoRecordPresentation {
        AutoRecordPresentation(runtimeIsRunning: service.isRunning,
                               isEnabled: settings.isEnabled, isPaused: settings.isPaused,
                               isVisible: isVisible, reduceMotion: reduceMotion)
    }
    private var label: String {
        isOn ? "Pause Auto Capture" : (settings.isEnabled ? "Resume Auto Capture" : "Set up Auto Capture")
    }
    private let tooltipID = "timeline-auto-capture-tooltip"

    var body: some View {
        Button {
            tooltipController?.activate(id: tooltipID)
            action()
        } label: {
            AutoRecordIndicator(presentation: presentation)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
                .frame(width: TimelineIconRowMetrics.controlWidth,
                       height: TimelineIconRowMetrics.controlHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(AccentIconButtonStyle(accent: .red, selected: false,
                                           emphasized: false, hovered: hovered, focused: focused))
        .buddyHelp(statusText, id: tooltipID, isFocused: focused)
        .focused($focused)
        .onHover { hovered = $0 }
        .accessibilityLabel(label)
        .accessibilityIdentifier("timeline-auto-capture")
        .accessibilityValue(presentation.isRecording ? "Recording · \(statusText)" : statusText)
        .accessibilityAddTraits(presentation.isRecording ? .isSelected : [])
        .accessibilityRemoveTraits(presentation.isRecording ? [] : .isSelected)
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
