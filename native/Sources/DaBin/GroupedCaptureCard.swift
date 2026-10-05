import SwiftUI

@MainActor
struct GroupedCaptureCard: View {
    @Environment(\.workspaceZoom) private var zoom
    @Environment(\.daBinAccent) private var accent
    @ObservedObject var state: AppState
    let group: CaptureCardGroup
    var compact = false
    var showsCopyButton = true
    var showsProject = true
    @State private var confirmsRemoval = false
    @State private var removalCaptures: [Capture] = []

    private var primary: Capture { group.primary }
    private var title: String { "\(group.captures.count) captures" }
    private var resolvedProjects: [String?] {
        group.captures.map { ExplorerQuery.project(of: $0, in: state.store.captures) }
    }
    private var hasMixedProjects: Bool { Set(resolvedProjects).count > 1 }
    private var resolvedProject: String? { hasMixedProjects ? nil : (resolvedProjects.first ?? nil) }
    private var resolvedProjectColor: String? {
        resolvedProject.map { state.workspace.projectColorHex(for: $0) ?? WorkspaceStore.defaultProjectColorHex }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsProject {
                ProjectChipLabel(name: hasMixedProjects ? "Multiple projects" : resolvedProject,
                                 colorHex: hasMixedProjects ? nil : resolvedProjectColor)
            }
            if group.isMinimized {
                collapsedOverview
            } else {
                cardHeader
                VStack(spacing: 0) {
                    ForEach(Array(group.captures.enumerated()), id: \.element.id) { index, capture in
                        GroupedCaptureItem(state: state, capture: capture, compact: compact,
                                           showsProjectBackground: hasMixedProjects)
                        if index < group.captures.count - 1 {
                            Rectangle().fill(Palette.line).frame(height: 0.5)
                                .padding(.horizontal, 6)
                        }
                    }
                }
            }

            if !primary.comment.isEmpty {
                Text(primary.comment).font(.system(size: zoom.fontSize(compact ? 11 : 12)))
                    .foregroundStyle(Palette.muted).lineLimit(2)
                    .accessibilityIdentifier("capture-comment-\(primary.id.uuidString)")
                    .readableTextDragSource(text: primary.comment, label: "Comment for \(primary.title)", state: state)
            }

            BuddyActionFlow(spacing: 6) {
                if group.isMinimized {
                    if showsCopyButton {
                        CaptureCopyButton(state: state, captures: group.captures, compact: compact)
                    }
                } else {
                    Button { state.toggleMinimized(group.captures) } label: {
                        Label("Collapse", systemImage: "minus")
                            .padding(.horizontal, 6).frame(minWidth: 32, minHeight: 32)
                            .contentShape(Rectangle())
                    }.accessibilityLabel("Collapse batch items")
                }
                BuddyIconButton(symbol: "trash", title: "Move batch to Recently Deleted", action: requestRemoval)
                    .accessibilityIdentifier("capture-trash-batch-\(primary.id.uuidString)")
                    .disabled(state.removingCaptureID != nil || state.isArchiveOperationRunning)
                Menu {
                    Button(primary.comment.isEmpty ? "Add comment" : "Edit comment", systemImage: "text.bubble") { state.openCapture(primary.id, focus: "comment") }
                    Button(primary.reminderAt == nil ? "Add reminder" : "Edit reminder", systemImage: "clock") { state.openCapture(primary.id, focus: "reminder") }
                } label: {
                    Text("More").padding(.horizontal, 6).frame(minWidth: 32, minHeight: 32)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("More batch actions").buddyHelp("More batch actions")
                .accessibilityIdentifier("capture-more-batch-\(primary.id.uuidString)")
            }.font(.system(size: zoom.fontSize(11))).buttonStyle(.plain).foregroundStyle(accent)

            if let reminder = primary.reminderAt {
                Text("Remind \(reminder.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: zoom.fontSize(11))).foregroundStyle(Palette.muted)
            }
        }
        .padding(compact ? 10 : 12)
        .projectCardBackground(workspace: state.workspace, projectName: resolvedProject, cornerRadius: 12)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Palette.line, lineWidth: 0.7))
        .alert("Delete \(removalCaptures.count) visible \(removalCaptures.count == 1 ? "capture" : "captures") from this batch?", isPresented: $confirmsRemoval) {
            Button("Cancel", role: .cancel) { removalCaptures = [] }
            Button("Delete \(removalCaptures.count) visible \(removalCaptures.count == 1 ? "capture" : "captures")", role: .destructive) {
                let captures = removalCaptures
                removalCaptures = []
                Task { await state.removeCaptures(captures) }
            }.disabled(state.removingCaptureID != nil || state.isArchiveOperationRunning || removalCaptures.isEmpty)
        } message: {
            Text("Only these captures will move to Recently Deleted, where you can restore them. Hidden and newly saved captures are kept. Files at their original locations are kept.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Batch of \(group.captures.count) captured items")
    }

    private func requestRemoval() {
        guard state.removingCaptureID == nil, !state.isArchiveOperationRunning else { return }
        let liveIDs = Set(state.store.captures.map(\.id))
        removalCaptures = group.captures.filter { liveIDs.contains($0.id) }
        guard !removalCaptures.isEmpty else { return }
        confirmsRemoval = true
    }

    private var collapsedOverview: some View {
        Button { state.toggleMinimized(group.captures) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: compact ? 3 : 4) {
                        Text(title)
                            .font(.system(size: zoom.fontSize(compact ? 13 : 14), weight: .semibold))
                            .foregroundStyle(Palette.foreground)
                            .accessibilityIdentifier("collection-batch-count")
                        CaptureReceiptView(capture: primary, category: "Batch", fontSize: compact ? 10 : 11)
                            .accessibilityIdentifier("collection-batch-time")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
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
        .accessibilityLabel("Expand batch items")
        .accessibilityValue("\(title), \(captureReceiptText(primary))")
        .accessibilityHint("Shows every saved item without changing the originals")
        .accessibilityIdentifier("collection-batch-summary")
        .captureDragSource(state: state, captures: group.captures, label: title)
        .buddyHelp("Open collection")
    }

    @ViewBuilder
    private var cardHeader: some View {
        if compact {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(title)
                        .font(.system(size: zoom.fontSize(13), weight: .semibold))
                        .lineLimit(1)
                        .layoutPriority(1)
                        .accessibilityIdentifier("collection-batch-title")
                        .captureDragSource(state: state, captures: group.captures, label: title)
                    Spacer(minLength: 2)
                    if showsCopyButton {
                        CaptureCopyButton(state: state, captures: group.captures, compact: true)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(group.isMinimized
                         ? group.captures.map(\.title).joined(separator: " · ")
                         : "Saved together")
                        .lineLimit(1)
                        .accessibilityIdentifier("collection-batch-caption")
                        .captureDragSource(state: state, captures: group.captures, label: title)
                }
                .font(.system(size: zoom.fontSize(9)))
                .foregroundStyle(Palette.muted)
                CaptureReceiptView(capture: primary, category: "Batch", fontSize: 9)
            }
        } else {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top, spacing: 9) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.system(size: zoom.fontSize(14), weight: .semibold))
                            .accessibilityIdentifier("collection-batch-title")
                        if group.isMinimized {
                            Text(group.captures.map(\.title).joined(separator: " · "))
                                .font(.system(size: zoom.fontSize(10))).foregroundStyle(Palette.muted).lineLimit(1)
                        } else {
                            Text("Saved together")
                                .font(.system(size: zoom.fontSize(11))).foregroundStyle(Palette.muted).lineLimit(1)
                                .accessibilityIdentifier("collection-batch-caption")
                        }
                    }
                    .captureDragSource(state: state, captures: group.captures, label: title)
                    Spacer(minLength: 5)
                    if showsCopyButton {
                        CaptureCopyButton(state: state, captures: group.captures)
                    }
                }
                CaptureReceiptView(capture: primary, category: "Batch")
            }
        }
    }
}

@MainActor
private struct GroupedCaptureItem: View {
    @Environment(\.workspaceZoom) private var zoom
    @ObservedObject var state: AppState
    @ObservedObject var capture: Capture
    let compact: Bool
    var showsProjectBackground = false

    var body: some View {
        Group {
            if compact { compactContent }
            else {
                CaptureRow(state: state, capture: capture, featured: false,
                           embeddedInCard: true, showsProject: false).padding(6)
            }
        }
        .projectCardBackground(workspace: state.workspace,
                               projectName: ExplorerQuery.project(of: capture, in: state.store.captures),
                               cornerRadius: 8, baseColor: Palette.surface.opacity(0.72),
                               enabled: showsProjectBackground)
    }

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { state.openCapture(capture.id) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if CapturePreviewFileReference.thumbnail(store: state.store, capture: capture) != nil {
                            CaptureThumbnail(store: state.store, capture: capture)
                                .frame(width: min(zoom.value(44), 56), height: min(zoom.value(48), 60))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        Text(capture.title.isEmpty ? "Untitled item" : capture.title)
                            .font(.system(size: zoom.fontSize(11), weight: .medium)).lineLimit(2)
                            .strikethrough(capture.isTask && capture.isCompleted, color: Palette.muted)
                            .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                            .font(.system(size: zoom.fontSize(9), weight: .semibold))
                            .foregroundStyle(Palette.muted).accessibilityHidden(true)
                    }
                    CaptureReceiptView(capture: capture,
                        category: capture.isTask ? (capture.isCompleted ? "Completed" : "Task") : captureTypeLabel(capture.kind),
                        fontSize: 10)
                }
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(capture.title.isEmpty ? "Untitled item" : capture.title), \(capture.isTask ? "Task" : captureTypeLabel(capture.kind))")
            .accessibilityValue(captureReceiptText(capture))
            .captureDragSource(state: state, capture: capture)
            CaptureTaskPriorityTag(capture: capture)
            if capture.isTask {
                BuddyActionFlow(spacing: 6) {
                    TaskStatusButton(state: state, capture: capture)
                    CaptureTrashButton(state: state, capture: capture)
                }
                TaskFocusControls(state: state, capture: capture)
            } else {
                BuddyActionFlow(spacing: 6) {
                    CaptureTaskConversionButton(state: state, capture: capture)
                    CaptureCopyButton(state: state, captures: [capture], compact: true)
                    CaptureTrashButton(state: state, capture: capture)
                }
            }
        }
        .padding(6)
        .contextMenu {
            CaptureTaskConversionMenu(state: state, capture: capture)
        }
    }
}
