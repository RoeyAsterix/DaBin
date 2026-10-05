import SwiftUI

/// Explorer uses existing local thumbnails, including visual captures promoted
/// to tasks. Text-only notes remain compact rather than gaining an empty hero.
enum ExplorerCaptureCardPresentation {
    @MainActor static func hasLargePreview(capture: Capture, store: CaptureStore) -> Bool {
        [.image, .video, .pdf, .document, .ai].contains(capture.kind)
            || CapturePreviewFileReference.thumbnail(store: store, capture: capture) != nil
    }

    static func previewHeight(for width: CGFloat) -> CGFloat {
        guard width.isFinite, width > 0 else { return 160 }
        return min(300, max(160, width * 0.8))
    }
}

/// A real width-dependent height without GeometryReader state or a resize loop.
/// The single cached thumbnail fits its complete content inside this surface.
struct ExplorerCapturePreviewLayout: Layout {
    var factor: CGFloat = 1
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let proposedWidth = proposal.width ?? 320
        let width = proposedWidth.isFinite ? max(0, proposedWidth) : 320
        return CGSize(width: width, height: ExplorerCaptureCardPresentation.previewHeight(for: width / factor) * factor)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
        }
    }
}

/// Measure and place one set of controls. Alternate ViewThatFits branches
/// created separate trail/popover lifetimes inside the live lazy capture list.
struct ExplorerCaptureActionsLayout: Layout {
    private let spacing: CGFloat = 4

    private func arrangement(width proposedWidth: CGFloat?, subviews: Subviews)
        -> (width: CGFloat, sizes: [CGSize], stacked: Bool) {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified) }
        let intrinsic = ideal.reduce(0) { $0 + $1.width } + spacing * CGFloat(max(0, ideal.count - 1))
        let width = proposedWidth.flatMap { $0.isFinite ? max(0, $0) : nil } ?? intrinsic
        let stacked = ideal.count > 1 && intrinsic > width
        let sizes = subviews.enumerated().map { index, view in
            view.sizeThatFits(ProposedViewSize(width: stacked ? width : min(width, ideal[index].width), height: nil))
        }
        return (width, sizes, stacked)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let layout = arrangement(width: proposal.width, subviews: subviews)
        let height = layout.stacked
            ? layout.sizes.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, layout.sizes.count - 1))
            : layout.sizes.map(\.height).max() ?? 0
        return CGSize(width: layout.width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrangement(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for (index, view) in subviews.enumerated() {
            let size = layout.sizes[index]
            let x = index == 0 ? bounds.minX : bounds.maxX - size.width
            view.place(at: CGPoint(x: x, y: layout.stacked ? y : bounds.midY - size.height / 2),
                       anchor: .topLeading, proposal: ProposedViewSize(size))
            if layout.stacked { y += size.height + spacing }
        }
    }
}

@MainActor struct ExplorerCaptureRow: View {
    @Environment(\.workspaceZoom) private var zoom
    @ObservedObject var state: AppState
    @ObservedObject var workspace: WorkspaceStore
    @ObservedObject var capture: Capture
    var focus: FocusState<UUID?>.Binding
    let select: () -> Void
    @Environment(\.daBinAccent) private var accent
    private var projectName: String? { ExplorerQuery.project(of: capture, in: state.store.captures) }
    private var hasLargePreview: Bool {
        ExplorerCaptureCardPresentation.hasLargePreview(capture: capture, store: state.store)
    }
    private var title: String { capture.title.isEmpty ? "Untitled capture" : capture.title }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                CaptureProjectPriorityHeader(state: state, capture: capture)
                    .frame(maxWidth: .infinity, alignment: .leading)
                CaptureCopyButton(state: state, captures: [capture])
                CaptureTrashButton(state: state, capture: capture)
            }
            HStack(alignment: .top, spacing: 8) {
                if capture.isTask {
                    if !hasLargePreview { taskCompletion }
                }
                Button(action: select) {
                    VStack(alignment: .leading, spacing: 8) {
                        if hasLargePreview {
                            ExplorerCapturePreviewLayout(factor: zoom.factor) {
                                CaptureThumbnail(store: state.store, capture: capture)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.line, lineWidth: 0.5))
                            .accessibilityHidden(true)
                        }
                        HStack(alignment: .top, spacing: 8) {
                            if !hasLargePreview && !capture.isTask {
                                CaptureThumbnail(store: state.store, capture: capture)
                                    .frame(width: zoom.value(38), height: zoom.value(38)).clipShape(RoundedRectangle(cornerRadius: 7))
                            }
                            metadata
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).multilineTextAlignment(.leading)
                    .focusable()
                    .focused(focus, equals: capture.id)
                    .accessibilityLabel("Open \(title)")
                    .accessibilityValue(captureReceiptText(capture) + ", " + category)
                    .accessibilityIdentifier("workspace-item-\(capture.id.uuidString)")
                    .accessibilityAddTraits(workspace.selectedCaptureID == capture.id ? .isSelected : [])
                    .captureDragSource(state: state, capture: capture)
            }
            ExplorerCaptureActionsLayout {
                CaptureTrailView(state: state, capture: capture)
                quickAction
            }
            CaptureConversionUndo(state: state, capture: capture)
            if capture.isTask { TaskFocusControls(state: state, capture: capture) }
        }.padding(zoom.value(10))
            .projectCardBackground(workspace: workspace, projectName: projectName,
                                   baseColor: workspace.selectedCaptureID == capture.id ? Palette.soft : Palette.surface)
            .projectCardFrame(workspace: workspace, projectName: projectName, activeProject: state.libraryProject,
                              fallbackColor: workspace.selectedCaptureID == capture.id ? accent.opacity(0.45) : Palette.line,
                              fallbackWidth: 1)
            .contextMenu { ExplorerCaptureActions(state: state, workspace: workspace, capture: capture) }
    }

    private var category: String {
        capture.isTask ? (capture.isCompleted ? "Completed" : "Task") : captureTypeLabel(capture.kind)
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(title).font(.system(size: zoom.fontSize(15), weight: .semibold)).lineLimit(2)
                    .strikethrough(capture.isTask && capture.isCompleted)
                if capture.isPinned {
                    Image(systemName: "pin.fill").font(.system(size: zoom.fontSize(10))).foregroundStyle(accent)
                        .accessibilityLabel("Pinned")
                }
            }
            CaptureReceiptView(capture: capture, category: category)
            if capture.parentTaskID != nil {
                Label("Task attachment", systemImage: "paperclip")
                    .font(.system(size: zoom.fontSize(11))).foregroundStyle(Palette.muted)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var taskCompletion: some View {
        Button { state.toggleTaskCompletion(capture) } label: {
            Image(systemName: capture.isCompleted ? "checkmark.square.fill" : "square")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(capture.isCompleted ? Palette.completed : Palette.muted)
                .frame(width: 32, height: 32)
        }.buttonStyle(.plain).accessibilityLabel(capture.isCompleted ? "Reopen task" : "Complete task")
    }

    @ViewBuilder private var quickAction: some View {
        if capture.isTask {
            if hasLargePreview { taskCompletion }
        } else if capture.parentTaskID == nil {
                    BuddyIconButton(symbol: "checklist", title: "Turn into task") { state.convertToTask(capture) }
        }
    }
}

@MainActor struct ExplorerInspector: View {
    @ObservedObject var state: AppState
    @ObservedObject var workspace: WorkspaceStore
    @ObservedObject var capture: Capture
    let height: CGFloat
    var compactHeader = false
    @Environment(\.daBinAccent) private var accent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                CaptureProjectPickerButton(state: state, capture: capture)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(alignment: .top) {
                    Text(capture.title).font(.system(size: compactHeader ? 18 : 26, weight: .semibold, design: .rounded))
                        .lineLimit(compactHeader ? 3 : nil)
                        .accessibilityIdentifier("explorer-inspector-title")
                        .buddyHelp(capture.title)
                        .captureDragSource(state: state, capture: capture)
                    Spacer(minLength: 6)
                    Menu {
                        ExplorerCaptureActions(state: state, workspace: workspace, capture: capture,
                                               includesInspectorButtons: false)
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.system(size: 19)).frame(width: 28, height: 28)
                    }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .accessibilityLabel("Actions for selected capture").buddyHelp("Item actions")
                }
                CaptureTaskPriorityTag(capture: capture)
                HStack(spacing: 6) {
                    CaptureTrailView(state: state, capture: capture)
                    Spacer(minLength: 0)
                    Text(captureClock(capture))
                }.font(.system(size: 11)).foregroundStyle(Palette.muted)
                if capture.isTask { TaskFocusControls(state: state, capture: capture, compact: false) }
                if capture.attachmentRelativePath != nil {
                    if state.store.managedURL(for: capture) != nil {
                        DetailPreview(store: state.store, capture: capture, height: max(120, min(520, height * 0.6)),
                                      onOpenOriginal: { state.openOriginal(capture) })
                            .captureDragSource(state: state, capture: capture)
                    } else {
                        Label("Saved file unavailable. Your capture details are still here.", systemImage: "doc.badge.ellipsis")
                            .font(.system(size: 13)).foregroundStyle(Palette.muted)
                    }
                }
                if let text = WorkspaceQuery.plainText(capture) {
                    Text(text).font(.system(size: 14)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                if !capture.comment.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("Comment", systemImage: "text.bubble").font(.system(size: 11, weight: .semibold)).foregroundStyle(accent)
                        Text(capture.comment).font(.system(size: 13)).textSelection(.enabled)
                    }
                }
                HStack {
                    if capture.isTask { TaskStatusButton(state: state, capture: capture) }
                    Button("Details", systemImage: "slider.horizontal.3") { state.openCapture(capture.id) }
                        .accessibilityIdentifier("explorer-open-details")
                    Spacer(minLength: 0)
                    CaptureCopyButton(state: state, captures: [capture])
                }.font(.system(size: 12)).foregroundStyle(accent)
                if let reminder = capture.reminderAt {
                    Label(reminder.formatted(date: .abbreviated, time: .shortened), systemImage: "bell")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                if let parentID = capture.parentTaskID, let parent = state.store.captures.first(where: { $0.id == parentID }) {
                    Button { state.openCapture(parentID) } label: { Label("Attached to \(parent.title)", systemImage: "paperclip") }
                        .font(.system(size: 12)).lineLimit(2)
                }
                if let url = state.store.managedURL(for: capture) {
                    VStack(alignment: .leading, spacing: 5) {
                        Button("Reveal saved file", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                            .font(.system(size: 12))
                        DisclosureGroup("Saved location") {
                            Text(url.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted).textSelection(.enabled)
                                .accessibilityLabel("Saved path, \(url.path)")
                        }.font(.system(size: 12)).foregroundStyle(Palette.muted)
                    }
                }
                Text("Captured \(prettyDay(capture.captureDay))")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }.padding(compactHeader ? 14 : 20).frame(maxWidth: .infinity, alignment: .leading)
        }.id(capture.id)
    }
}

@MainActor struct ExplorerCaptureActions: View {
    @ObservedObject var state: AppState
    @ObservedObject var workspace: WorkspaceStore
    @ObservedObject var capture: Capture
    var includesInspectorButtons = true
    var taskConversion: (() -> Void)? = nil
    var body: some View {
        if includesInspectorButtons {
            Button("Open details", systemImage: "rectangle.and.text.magnifyingglass") { state.openCapture(capture.id) }
            Button("Copy", systemImage: "doc.on.doc") { state.copyCapturesToClipboard([capture]) }
        }
        if WorkspaceQuery.plainText(capture) != nil {
            Button("Copy as plain text", systemImage: "text.alignleft") {
                do { try WorkspaceClipboard.copyPlainText(capture); state.status = AppStatusMessage(text: "Plain text copied.", severity: .success) }
                catch { state.reportFailure(error.localizedDescription) }
            }
        }
        if capture.attachmentRelativePath != nil {
            Button("Open saved file", systemImage: "arrow.up.forward.square") { state.openOriginal(capture) }
            Button("Reveal saved file", systemImage: "folder") {
                guard let url = state.store.managedURL(for: capture) else {
                    state.reportFailure("The saved file is unavailable. Your capture details are kept."); return
                }
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            Button("Copy saved path", systemImage: "link") {
                do { try WorkspaceClipboard.copyManagedPath(capture, store: state.store); state.status = AppStatusMessage(text: "Saved path copied.", severity: .success) }
                catch { state.reportFailure(error.localizedDescription) }
            }
        }
        Divider()
        Button(capture.isPinned ? "Unpin" : "Pin", systemImage: capture.isPinned ? "pin.slash" : "pin") { state.togglePinned(capture) }
        CaptureReturnToInboxMenuItem(state: state, capture: capture)
        Button(workspace.shelfCaptureIDs.contains(capture.id) ? "Remove from shelf; keep capture" : "Add to shelf", systemImage: "tray") {
            do { try workspace.setOnShelf([capture.id], included: !workspace.shelfCaptureIDs.contains(capture.id)) }
            catch { state.reportFailure(error.localizedDescription) }
        }
        if !capture.isTask {
            Button("Turn into task", systemImage: "checkmark.circle") {
                if let taskConversion { taskConversion() } else { state.convertToTask(capture) }
            }
            if capture.parentTaskID == nil { Menu {
                ForEach(state.store.captures.filter { $0.isTask && !$0.isCompleted }) { task in
                    Button(task.title, systemImage: "paperclip") {
                        do { try state.store.attachCapture(capture, to: task) }
                        catch { state.reportFailure(error.localizedDescription) }
                    }
                }
            } label: { Label("Attach to task", systemImage: "paperclip") }
                .disabled(!state.store.captures.contains { $0.isTask && !$0.isCompleted })
            }
        }
        Divider()
        Button("Move to Recently Deleted…", systemImage: "trash", role: .destructive) { state.requestRemoval(capture) }
    }

}

@MainActor struct ExplorerProjectPicker: View {
    @ObservedObject var state: AppState
    @ObservedObject var workspace: WorkspaceStore
    @State private var summaryCache: ProjectWorkspaceSummaryCache
    @State private var presented = false
    @State private var dragHovered = false
    @FocusState private var focused: Bool
    private var title: String { state.libraryProject ?? (workspace.explorerUnfiledOnly ? "Unfiled" : "All projects") }
    private var symbol: String {
        state.libraryProject != nil ? "folder.fill" : workspace.explorerUnfiledOnly ? "tray" : "square.stack.3d.up"
    }
    init(state: AppState, workspace: WorkspaceStore) {
        self.state = state; self.workspace = workspace
        _summaryCache = State(initialValue: ProjectWorkspaceSummaryCache(store: state.store, workspace: workspace))
    }
    var body: some View {
        let summary = state.libraryProject.map { summaryCache.summary(for: $0) }
        let projectColor = summary.map { ProjectColorChoice.color(for: $0.colorHex) }
        let countLabel = workspace.mode == .collection ? summary.map {
            "\($0.itemCount.formatted()) \($0.itemCount == 1 ? "item" : "items")"
        } : nil
        Button { presented.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 14)).foregroundStyle(projectColor ?? Palette.muted)
                    .frame(width: 29, height: 29)
                    .background((projectColor ?? Palette.surface).opacity(projectColor == nil ? 1 : 0.14),
                                in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder((projectColor ?? Palette.line).opacity(projectColor == nil ? 1 : 0.7)))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(title).font(.system(size: 18, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.72)
                        Image(systemName: "chevron.down").font(.system(size: 9)).foregroundStyle(Palette.muted)
                    }
                    if let countLabel {
                        Text(countLabel).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                }
            }.frame(maxWidth: .infinity, minHeight: 36, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(Palette.foreground).focused($focused)
            .buddyHelp("Choose a project or drag items onto a project")
            .accessibilityLabel("Project, \(title)").accessibilityIdentifier("workspace-project-picker")
            .accessibilityValue(countLabel ?? "")
            .onDrop(of: ExplorerTransfer.acceptedTypeIdentifiers, isTargeted: $dragHovered) { _ in false }
            .task(id: dragHovered) {
                guard dragHovered else { return }
                try? await Task.sleep(for: .milliseconds(350))
                if !Task.isCancelled && dragHovered { presented = true }
            }
            .popover(isPresented: $presented, arrowEdge: .bottom) {
                ProjectPickerPanel(state: state, selectedProject: state.libraryProject, allowsAll: true,
                    allSelected: state.libraryProject == nil && !workspace.explorerUnfiledOnly, allowsDrop: true,
                    onSelect: { name, all in
                        state.navigateProject(name, unfiledOnly: name == nil && !all)
                        if let error = workspace.error { throw WorkspaceError.unavailable(error) }
                    }, onDismiss: { presented = false; focused = true })
                    .hoverTooltips()
            }
            .daBinTutorialAnchor(.projectPicker)
    }
}
