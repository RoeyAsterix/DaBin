import SwiftUI

/// Inline presentation for an automatic hour. Its outer identity belongs to
/// `CaptureFeedCard`, so changing this body never replaces the scroll target.
@MainActor
struct HourlyCaptureCard: View {
    @Environment(\.daBinAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var state: AppState
    let group: AutomaticHourGroup
    var compact = false

    private var isExpanded: Bool { state.isHourlyGroupExpanded(group.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 7 : 10) {
            if isExpanded {
                expandedHeader
                VStack(spacing: compact ? 7 : 9) {
                    ForEach(group.actions) { action in
                        actionView(action)
                    }
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            } else {
                Button(action: toggleExpansion) {
                    HStack(spacing: compact ? 7 : 9) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: compact ? 11 : 13, weight: .semibold))
                            .foregroundStyle(accent)
                            .accessibilityHidden(true)
                        Text(group.summaryTitle)
                            .font(.system(size: compact ? 11 : 13, weight: .semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 6)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Palette.muted)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Expand actions, \(group.summaryTitle)")
                .accessibilityHint("Displays every automatic action saved during this hour")
            }
        }
        .padding(compact ? 9 : 11)
        .background(Palette.soft.opacity(compact ? 0.62 : 0.5),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(accent.opacity(0.3), lineWidth: 0.75)
        }
        .padding(.vertical, compact ? 0 : 6)
        .accessibilityElement(children: .contain)
    }

    private var expandedHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "clock.fill")
                .font(.system(size: compact ? 11 : 13, weight: .semibold))
                .foregroundStyle(accent)
                .accessibilityHidden(true)
            Text(group.summaryTitle)
                .font(.system(size: compact ? 11 : 13, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 6)
            Button(action: toggleExpansion) {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 26)
                    .background(accent.opacity(0.11),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(accent)
            .help("Collapse actions")
            .accessibilityLabel("Collapse actions")
            .accessibilityHint("Returns to the hourly summary without deleting any action")
        }
    }

    private func actionView(_ action: AutomaticCaptureAction) -> some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 5) {
            HStack(spacing: 6) {
                Image(systemName: action.primary.captureOrigin == .automaticScreenshot
                      ? "camera.viewfinder" : "doc.on.clipboard")
                    .font(.system(size: compact ? 9 : 10, weight: .medium))
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)
                Text(action.primary.captureOrigin.displayName)
                    .font(.system(size: compact ? 9 : 10, weight: .medium))
                    .foregroundStyle(Palette.muted)
                if let application = action.primary.sourceApplicationName {
                    Text("· \(application)")
                        .font(.system(size: compact ? 9 : 10))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(captureClock(action.primary))
                    .font(.system(size: compact ? 9 : 10))
                    .monospacedDigit()
                    .foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, compact ? 7 : 9)
            .padding(.top, compact ? 6 : 8)

            ForEach(action.cards) { card in
                if card.isImportedBatch {
                    GroupedCaptureCard(state: state, group: card, compact: compact)
                } else {
                    CaptureRow(state: state, capture: card.primary, featured: false,
                               embeddedInCard: true)
                        .padding(.horizontal, compact ? 7 : 9)
                }
            }
        }
        .background(Palette.surface.opacity(0.74),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Palette.line.opacity(0.76), lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(action.primary.captureOrigin.displayName) at \(captureClock(action.primary))")
    }

    private func toggleExpansion() {
        if reduceMotion {
            state.toggleHourlyGroup(group.id)
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                state.toggleHourlyGroup(group.id)
            }
        }
    }
}
