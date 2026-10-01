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
    private var resolvedProjects: [String?] {
        group.actions.flatMap(\.captures).map {
            ExplorerQuery.project(of: $0, in: state.store.captures)
        }
    }
    private var hasMixedProjects: Bool { Set(resolvedProjects).count > 1 }
    private var resolvedProject: String? { hasMixedProjects ? nil : (resolvedProjects.first ?? nil) }
    private var resolvedProjectColor: String? {
        resolvedProject.map { state.workspace.projectColorHex(for: $0) ?? WorkspaceStore.defaultProjectColorHex }
    }
    private var summaryTitle: String {
        group.displaysDate ? group.summaryTitle
            : "\(prettyDay(group.id.captureDay, includeWeekday: false)) · \(group.summaryTitle)"
    }
    private var receiptTime: String {
        "\(prettyDay(group.id.captureDay, includeWeekday: false)) · \(group.id.rangeLabel)"
    }
    private var showsActionCount: Bool {
        group.visibleCaptureCount != group.visibleActionCount || group.totalCaptureCount != group.totalActionCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 7 : 10) {
            ProjectChipLabel(name: hasMixedProjects ? "Multiple projects" : resolvedProject,
                             colorHex: hasMixedProjects ? nil : resolvedProjectColor)
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
                    VStack(alignment: .leading, spacing: compact ? 8 : 11) {
                        CollectionPreviewMosaic(store: state.store, captures: group.captures, compact: compact)
                        HStack(alignment: .center, spacing: 8) {
                            collectionMetadata
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(accent)
                                .frame(width: compact ? 26 : 30, height: compact ? 26 : 30)
                                .background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Expand actions, \(summaryTitle)")
                .accessibilityValue(group.captureCountLabel)
                .accessibilityHint("Displays every automatic action saved during this hour")
                .accessibilityIdentifier("collection-hour-summary")
                .buddyHelp("Open collection")
            }
        }
        .padding(compact ? 8 : 14)
        .background(Palette.surface,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 0.7)
        }
        .padding(.vertical, compact ? 0 : 6)
        .accessibilityElement(children: .contain)
    }

    private var expandedHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            collectionMetadata
            Spacer(minLength: 6)
            Button(action: toggleExpansion) {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(accent.opacity(0.11),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(accent)
            .buddyHelp("Collapse actions")
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
                CaptureReceiptView(capture: action.primary,
                    category: action.primary.captureOrigin == .automaticClipboard ? "Copied" : action.primary.captureOrigin.displayName,
                    fontSize: compact ? 9 : 10)
                Spacer(minLength: 4)
                CaptureCopyButton(state: state, captures: action.captures, compact: true)
            }
            .padding(.horizontal, compact ? 2 : 9)
            .padding(.top, compact ? 6 : 8)
            if let application = action.primary.sourceApplicationName {
                Text(application)
                    .font(.system(size: compact ? 9 : 10))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                    .padding(.horizontal, compact ? 2 : 9)
            }

            ForEach(action.cards) { card in
                if card.isImportedBatch {
                    GroupedCaptureCard(state: state, group: card, compact: compact,
                                       showsCopyButton: false, showsProject: hasMixedProjects)
                } else {
                    CaptureRow(state: state, capture: card.primary, featured: false,
                               showsCopyButton: false, embeddedInCard: true,
                               showsProject: hasMixedProjects)
                        .padding(.horizontal, compact ? 2 : 9)
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

    private var collectionMetadata: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 4) {
            Text(group.captureCountLabel)
                .font(.system(size: compact ? 13 : 16, weight: .semibold))
                .foregroundStyle(Palette.foreground)
                .lineLimit(2)
                .accessibilityIdentifier("collection-hour-count")
            Text(receiptTime)
                .font(.system(size: compact ? 10 : 11, weight: .medium))
                .foregroundStyle(Palette.muted)
                .monospacedDigit()
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("collection-hour-time")
            if showsActionCount {
                Text(group.actionCountLabel)
                    .font(.system(size: compact ? 9 : 10))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(2)
            }
        }
        .multilineTextAlignment(.leading)
    }
}
