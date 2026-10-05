import SwiftUI

/// Inline presentation for an automatic hour. Its outer identity belongs to
/// `CaptureFeedCard`, so changing this body never replaces the scroll target.
@MainActor
struct HourlyCaptureCard: View {
    @Environment(\.workspaceZoom) private var zoom
    @Environment(\.daBinAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var state: AppState
    let group: AutomaticHourGroup
    var compact = false
    @State private var confirmsRemoval = false
    @State private var removalCaptures: [Capture] = []
    @State private var removalScope = "hour"

    private var isExpanded: Bool { state.isHourlyGroupExpanded(group.id) }
    private var hourIdentity: String {
        "\(group.id.captureDay)-\(group.id.hour)-\(group.id.utcOffsetSeconds)"
    }
    private var removalUnavailable: Bool { state.removingCaptureID != nil || state.isArchiveOperationRunning }
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 6) {
                ProjectChipLabel(name: hasMixedProjects ? "Multiple projects" : resolvedProject,
                                 colorHex: hasMixedProjects ? nil : resolvedProjectColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Menu {
                    Button("Delete \(group.visibleCaptureCount) visible \(group.visibleCaptureCount == 1 ? "capture" : "captures")…", systemImage: "trash", role: .destructive) {
                        requestRemoval(group.captures, scope: "hour")
                    }.disabled(removalUnavailable)
                        .accessibilityIdentifier("capture-delete-hour-\(hourIdentity)")
                } label: { moreLabel }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                    .foregroundStyle(accent).accessibilityLabel("More actions for \(summaryTitle)")
                    .accessibilityIdentifier("capture-more-hour-\(hourIdentity)")
            }
            if isExpanded {
                expandedHeader
                VStack(spacing: 8) {
                    ForEach(group.actions) { action in
                        actionView(action)
                    }
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            } else {
                Button(action: toggleExpansion) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center, spacing: 8) {
                            collectionMetadata
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.down")
                                .font(.system(size: zoom.fontSize(11), weight: .semibold))
                                .foregroundStyle(accent)
                                .frame(width: 32, height: 32)
                                .background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                                .accessibilityHidden(true)
                        }
                        CollectionPreviewMosaic(store: state.store, captures: group.captures, compact: compact)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Expand actions, \(summaryTitle)")
                .accessibilityValue(group.captureCountLabel)
                .accessibilityHint("Displays every automatic action saved during this hour")
                .accessibilityIdentifier("collection-hour-summary")
                .captureDragSource(state: state, captures: group.captures, label: summaryTitle)
                .buddyHelp("Open collection")
            }
        }
        .padding(compact ? 10 : 12)
        .projectCardBackground(workspace: state.workspace, projectName: resolvedProject, cornerRadius: 12)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 0.7)
        }
        .accessibilityElement(children: .contain)
        .alert("Delete \(removalCaptures.count) visible \(removalCaptures.count == 1 ? "capture" : "captures") from this \(removalScope)?", isPresented: $confirmsRemoval) {
            Button("Cancel", role: .cancel) { removalCaptures = [] }
            Button("Delete \(removalCaptures.count) visible \(removalCaptures.count == 1 ? "capture" : "captures")", role: .destructive) {
                let captures = removalCaptures
                removalCaptures = []
                Task { await state.removeCaptures(captures) }
            }.disabled(removalUnavailable || removalCaptures.isEmpty)
        } message: {
            Text("Only these captures will move to Recently Deleted, where you can restore them. Hidden captures, other tasks and newly saved captures are kept. Files at their original locations are kept.")
        }
    }

    private var expandedHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            collectionMetadata
                .captureDragSource(state: state, captures: group.captures, label: summaryTitle)
            Spacer(minLength: 6)
            Button(action: toggleExpansion) {
                Image(systemName: "minus")
                    .font(.system(size: zoom.fontSize(11), weight: .semibold))
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
        VStack(alignment: .leading, spacing: 6) {
            BuddyActionFlow(spacing: 6) {
                CaptureReceiptView(capture: action.primary,
                    category: action.primary.captureOrigin == .automaticClipboard ? "Copied" : action.primary.captureOrigin.displayName,
                    fontSize: compact ? 9 : 10)
                CaptureCopyButton(state: state, captures: action.captures, compact: true)
                Menu {
                    Button("Delete \(action.captures.count) visible \(action.captures.count == 1 ? "capture" : "captures")…", systemImage: "trash", role: .destructive) {
                        requestRemoval(action.captures, scope: "action")
                    }.disabled(removalUnavailable)
                        .accessibilityIdentifier("capture-delete-action-\(action.id.uuidString)")
                } label: { moreLabel }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                    .foregroundStyle(accent)
                    .accessibilityLabel("More actions for \(action.primary.captureOrigin.displayName) at \(captureClock(action.primary))")
                    .accessibilityIdentifier("capture-more-action-\(action.id.uuidString)")
            }
            .padding(.horizontal, 6)
            .padding(.top, 6)
            if let application = action.primary.sourceApplicationName {
                Text(application)
                    .font(.system(size: zoom.fontSize(compact ? 9 : 10)))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
            }

            ForEach(action.cards) { card in
                if card.isImportedBatch {
                    GroupedCaptureCard(state: state, group: card, compact: compact,
                                       showsCopyButton: false, showsProject: hasMixedProjects)
                } else {
                    CaptureRow(state: state, capture: card.primary, featured: false,
                               showsCopyButton: false, embeddedInCard: true,
                               showsProject: hasMixedProjects)
                        .padding(.horizontal, 6)
                }
            }
        }
        .projectCardBackground(workspace: state.workspace, projectName: project(for: action),
                               cornerRadius: 12, baseColor: Palette.surface.opacity(0.74))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Palette.line.opacity(0.76), lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(action.primary.captureOrigin.displayName) at \(captureClock(action.primary))")
    }

    private func project(for action: AutomaticCaptureAction) -> String? {
        let projects = Set(action.captures.map { ExplorerQuery.project(of: $0, in: state.store.captures) })
        return projects.count == 1 ? (projects.first ?? nil) : nil
    }

    private var moreLabel: some View {
        Text("More").font(.system(size: zoom.fontSize(11)))
            .padding(.horizontal, 6).frame(minWidth: 32, minHeight: 32).contentShape(Rectangle())
    }

    private func requestRemoval(_ captures: [Capture], scope: String) {
        guard !removalUnavailable else { return }
        let liveIDs = Set(state.store.captures.map(\.id))
        removalCaptures = captures.filter { liveIDs.contains($0.id) }
        guard !removalCaptures.isEmpty else { return }
        removalScope = scope
        confirmsRemoval = true
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
                .font(.system(size: zoom.fontSize(compact ? 13 : 14), weight: .semibold))
                .foregroundStyle(Palette.foreground)
                .lineLimit(2)
                .accessibilityIdentifier("collection-hour-count")
            Text(receiptTime)
                .font(.system(size: zoom.fontSize(compact ? 10 : 11), weight: .medium))
                .foregroundStyle(Palette.muted)
                .monospacedDigit()
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("collection-hour-time")
            if showsActionCount {
                Text(group.actionCountLabel)
                    .font(.system(size: zoom.fontSize(compact ? 9 : 10)))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(2)
            }
        }
        .multilineTextAlignment(.leading)
    }
}
