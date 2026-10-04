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
        VStack(alignment: .leading, spacing: compact ? 7 : 9) {
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
                                .padding(.leading, compact ? 44 : 54)
                        }
                    }
                }
                .projectCardBackground(workspace: state.workspace, projectName: resolvedProject,
                                       cornerRadius: 10, baseColor: Palette.surface.opacity(0.72))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Palette.line.opacity(0.75), lineWidth: 0.5))
            }

            if !primary.comment.isEmpty {
                Text(primary.comment).font(.system(size: zoom.fontSize(compact ? 11 : 12)))
                    .foregroundStyle(Palette.muted).lineLimit(2)
                    .accessibilityIdentifier("capture-comment-\(primary.id.uuidString)")
                    .readableTextDragSource(text: primary.comment, label: "Comment for \(primary.title)", state: state)
            }

            HStack {
                if group.isMinimized {
                    if showsCopyButton {
                        CaptureCopyButton(state: state, captures: group.captures, compact: compact)
                    }
                } else {
                    Button { state.toggleMinimized(group.captures) } label: {
                        Label("Collapse", systemImage: "minus").frame(minHeight: 32)
                    }.accessibilityLabel("Collapse batch items")
                }
                Spacer(minLength: 0)
                BuddyIconButton(symbol: "trash", title: "Move batch to Recently Deleted") { confirmsRemoval = true }
                    .accessibilityIdentifier("capture-trash-batch-\(primary.id.uuidString)")
                    .disabled(state.removingCaptureID != nil || state.isArchiveOperationRunning)
                Menu {
                    Button(primary.comment.isEmpty ? "Add note" : "Edit note", systemImage: "text.bubble") { state.openCapture(primary.id, focus: "comment") }
                    Button(primary.reminderAt == nil ? "Add reminder" : "Edit reminder", systemImage: "clock") { state.openCapture(primary.id, focus: "reminder") }
                } label: { Image(systemName: "ellipsis").frame(width: 32, height: 32) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("More batch actions").buddyHelp("More batch actions")
            }.font(.system(size: zoom.fontSize(11))).buttonStyle(.plain).foregroundStyle(accent)

            if let reminder = primary.reminderAt {
                Text("Remind \(reminder.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: zoom.fontSize(11))).foregroundStyle(Palette.muted)
            }
        }
        .padding(compact ? 6 : 16)
        .projectCardBackground(workspace: state.workspace, projectName: resolvedProject)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Palette.line, lineWidth: 0.7))
        .padding(.vertical, compact ? 0 : 6)
        .alert("Move this batch to Recently Deleted?", isPresented: $confirmsRemoval) {
            Button("Cancel", role: .cancel) { }
            Button("Move \(group.captures.count) items", role: .destructive) {
                Task { await state.removeCaptures(group.captures) }
            }
        } message: {
            Text("You can restore these captures from Recently Deleted. Files at their original locations are kept.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Batch of \(group.captures.count) captured items")
    }

    private var collapsedOverview: some View {
        Button { state.toggleMinimized(group.captures) } label: {
            VStack(alignment: .leading, spacing: compact ? 8 : 11) {
                CollectionPreviewMosaic(store: state.store, captures: group.captures, compact: compact)
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: compact ? 3 : 4) {
                        Text(title)
                            .font(.system(size: zoom.fontSize(compact ? 13 : 16), weight: .semibold))
                            .foregroundStyle(Palette.foreground)
                            .accessibilityIdentifier("collection-batch-count")
                        CaptureReceiptView(capture: primary, category: "Batch", fontSize: compact ? 10 : 11)
                            .accessibilityIdentifier("collection-batch-time")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(.system(size: zoom.fontSize(11), weight: .semibold))
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
                    batchSymbol(size: 13, width: 18)
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
                    batchSymbol(size: 15, width: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.system(size: zoom.fontSize(16), weight: .semibold))
                            .accessibilityIdentifier("collection-batch-title")
                        if group.isMinimized {
                            Text(group.captures.map(\.title).joined(separator: " · "))
                                .font(.system(size: zoom.fontSize(10))).foregroundStyle(Palette.muted).lineLimit(1)
                        } else {
                            Text("Saved together in one drop or paste")
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

    private func batchSymbol(size: CGFloat, width: CGFloat) -> some View {
        Image(systemName: "square.stack.3d.up.fill")
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(accent)
            .frame(width: width, height: 22)
            .accessibilityHidden(true)
    }

    private func batchIcon(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 28, height: 26)
                .background(accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buddyHelp(label).accessibilityLabel(label)
        .disabled(state.removingCaptureID != nil)
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
                           embeddedInCard: true, showsProject: false).padding(8)
            }
        }
        .projectCardBackground(workspace: state.workspace,
                               projectName: ExplorerQuery.project(of: capture, in: state.store.captures),
                               cornerRadius: 8, baseColor: Palette.surface.opacity(0.72),
                               enabled: showsProjectBackground)
    }

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button { state.openCapture(capture.id) } label: {
                VStack(alignment: .leading, spacing: 8) {
                    if !compact {
                        CaptureThumbnail(store: state.store, capture: capture)
                            .frame(height: zoom.value(132)).clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                HStack(spacing: compact ? 7 : 10) {
                    if compact {
                        CaptureThumbnail(store: state.store, capture: capture)
                            .frame(width: zoom.value(44), height: zoom.value(48)).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(capture.title.isEmpty ? "Untitled item" : capture.title)
                            .font(.system(size: zoom.fontSize(compact ? 11 : 13), weight: .medium)).lineLimit(compact ? 2 : 1)
                            .strikethrough(capture.isTask && capture.isCompleted, color: Palette.muted)
                            .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                        CaptureReceiptView(capture: capture,
                            category: capture.isTask ? (capture.isCompleted ? "Completed" : "Task") : captureTypeLabel(capture.kind),
                            fontSize: compact ? 9 : 10)
                    }
                    Image(systemName: "chevron.right").font(.system(size: zoom.fontSize(9), weight: .semibold))
                        .foregroundStyle(Palette.muted).accessibilityHidden(true)
                }
                .contentShape(Rectangle())
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(capture.title), \(capture.isTask ? "Task" : captureTypeLabel(capture.kind))")
            .captureDragSource(state: state, capture: capture)
            CaptureTaskPriorityTag(capture: capture)
            if capture.isTask {
                HStack {
                    TaskStatusButton(state: state, capture: capture)
                    Spacer(minLength: 0)
                    CaptureTrashButton(state: state, capture: capture)
                }
                TaskFocusControls(state: state, capture: capture)
            } else {
                HStack(spacing: 2) {
                    CaptureTaskConversionButton(state: state, capture: capture)
                    Spacer(minLength: 0)
                    CaptureCopyButton(state: state, captures: [capture], compact: true)
                    CaptureTrashButton(state: state, capture: capture)
                }
            }
        }
        .padding(.horizontal, compact ? 1 : 9).padding(.vertical, compact ? 6 : 7)
        .contextMenu {
            CaptureTaskConversionMenu(state: state, capture: capture)
        }
    }
}
