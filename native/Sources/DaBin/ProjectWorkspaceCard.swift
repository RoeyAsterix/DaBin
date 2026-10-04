import SwiftUI

/// Visual role is separate from the immutable file/content type. A PDF turned
/// into a task stays a PDF; pasted text is not inferred to be an authored note.
enum ProjectCardRole: String {
    case task, note, capture

    @MainActor init(item: ProjectWorkspaceItem) {
        switch item {
        case .note: self = .note
        case .capture(let capture): self = capture.isTask ? .task : .capture
        }
    }

    var title: String {
        switch self { case .task: return "Task"; case .note: return "Note"; case .capture: return "Capture" }
    }

    var symbol: String {
        switch self { case .task: return "checklist"; case .note: return "square.and.pencil"; case .capture: return "viewfinder" }
    }
}

/// A lightweight native paper texture, with no image allocation or animation.
private struct ProjectNoteRules: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for y in stride(from: CGFloat(84), to: rect.height, by: 26) {
            path.move(to: CGPoint(x: 20, y: y))
            path.addLine(to: CGPoint(x: max(20, rect.width - 20), y: y))
        }
        return path
    }
}

/// One set of controls adapts to logical width, so resizing never creates
/// duplicate menu/focus/drag targets. At large zoom in a narrow window the
/// selection/preview/actions become a short header and text uses the full row.
private struct ProjectCompactCardLayout: Layout {
    var zoom: WorkspaceZoomLayout
    var previewWidth: CGFloat
    var textTask: Bool
    private var spacing: CGFloat { 8 }
    private func sizes(_ proposal: ProposedViewSize, _ subviews: Subviews) -> (CGFloat, Bool, [CGSize]) {
        let width = max(0, proposal.width ?? 320)
        let stacked = width / zoom.factor < 260
        let selection = subviews[0].sizeThatFits(.unspecified)
        let actions = subviews[3].sizeThatFits(.unspecified)
        let preview = CGSize(width: stacked ? min(textTask ? 48 : 96, zoom.value(previewWidth)) : zoom.value(previewWidth),
                             height: stacked ? min(textTask ? 48 : 96, zoom.value(80)) : zoom.value(80))
        let metadataWidth = stacked ? width : max(0, width - selection.width - actions.width - preview.width - spacing * 3)
        let metadata = subviews[2].sizeThatFits(ProposedViewSize(width: metadataWidth, height: nil))
        return (width, stacked, [selection, preview, metadata, actions])
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let (width, stacked, sizes) = sizes(proposal, subviews)
        let height = stacked ? max(max(sizes[0].height, sizes[1].height), sizes[3].height) + zoom.value(8) + sizes[2].height
            : sizes.map(\.height).max() ?? 0
        return CGSize(width: width, height: height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (_, stacked, sizes) = sizes(ProposedViewSize(width: bounds.width, height: nil), subviews)
        if stacked {
            let headerHeight = max(max(sizes[0].height, sizes[1].height), sizes[3].height)
            for index in [0, 1, 3] {
                let x = index == 0 ? bounds.minX : index == 1 ? bounds.minX + sizes[0].width + spacing : bounds.maxX - sizes[3].width
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + (headerHeight - sizes[index].height) / 2),
                    anchor: .topLeading, proposal: ProposedViewSize(sizes[index]))
            }
            subviews[2].place(at: CGPoint(x: bounds.minX, y: bounds.minY + headerHeight + zoom.value(8)),
                anchor: .topLeading, proposal: ProposedViewSize(sizes[2]))
        } else {
            var x = bounds.minX
            for index in subviews.indices {
                subviews[index].place(at: CGPoint(x: x, y: bounds.midY - sizes[index].height / 2),
                    anchor: .topLeading, proposal: ProposedViewSize(sizes[index]))
                x += sizes[index].width + spacing
            }
        }
    }
}

/// Opening, selecting and reordering are separate targets. Only cached local
/// preview images are loaded; text previews are bounded before layout.
@MainActor struct ProjectWorkspaceCard: View {
    @Environment(\.workspaceZoom) private var zoom
    let state: AppState
    let item: ProjectWorkspaceItem
    let selected: Bool
    let compact: Bool
    let color: Color
    var focus: FocusState<String?>.Binding
    let open: () -> Void
    let select: () -> Void
    let details: () -> Void
    let makeTask: () -> Void
    let earlier: () -> Void
    let later: () -> Void
    let canReorder: Bool
    let drag: () throws -> [NSPasteboardWriting]
    var dragEnded: () -> Void = {}

    private var role: ProjectCardRole { ProjectCardRole(item: item) }
    private var completed: Bool { item.capture?.isTask == true && item.capture?.isCompleted == true }
    private var compactPreviewWidth: CGFloat {
        guard role == .task, let capture = item.capture else { return 96 }
        return [CaptureKind.text, .task].contains(capture.kind) ? 36 : 64
    }
    private var roleAccent: Color {
        switch role {
        case .task: return completed ? Palette.completed : Palette.task
        case .note: return Color(nsColor: .systemOrange)
        case .capture: return Palette.muted
        }
    }

    var body: some View {
        Group {
            if let capture = item.capture {
                ObservedProjectCaptureCard(capture: capture, card: self)
            } else { content }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project-card-\(item.id)")
    }

    fileprivate var content: some View {
        Group {
            if compact {
                ProjectCompactCardLayout(zoom: zoom, previewWidth: compactPreviewWidth,
                    textTask: role == .task && item.capture.map { [CaptureKind.text, .task].contains($0.kind) } == true) {
                    selectionButton
                    preview.clipped()
                    metadata.frame(maxWidth: .infinity, alignment: .leading)
                    actions
                }.padding(zoom.value(8)).frame(minHeight: zoom.value(96))
            } else if let capture = item.capture, capture.isTask {
                taskCard(capture)
            } else {
                VStack(spacing: 0) {
                    preview.frame(height: zoom.value(214)).clipped()
                        .overlay(alignment: .topLeading) { selectionButton.padding(4) }
                        .overlay(alignment: .topTrailing) { roleBadge.padding(12) }
                    HStack(alignment: .center, spacing: 4) {
                        metadata.frame(maxWidth: .infinity, alignment: .leading)
                        actions
                    }.padding(.horizontal, zoom.value(12)).frame(minHeight: zoom.value(70))
                }
            }
        }
        .background(selected ? color.opacity(0.055) : Palette.surface)
        .overlay(alignment: .leading) {
            if role == .task { Rectangle().fill(roleAccent).frame(width: 3).allowsHitTesting(false).accessibilityHidden(true) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(color.opacity(selected ? 0.9 : 0.22), lineWidth: selected ? 2 : 0.8))
        .contextMenu {
            if let capture = item.capture {
                ExplorerCaptureActions(state: state, workspace: state.workspace, capture: capture, taskConversion: makeTask)
            }
            else { Button("Edit project notes", systemImage: "note.text", action: details) }
        }
    }

    /// Tasks read as compact pieces of work instead of fixed-height preview
    /// tiles. Their content determines the height; media still has a useful
    /// thumbnail, and its original remains available through the same target.
    private func taskCard(_ capture: Capture) -> some View {
        VStack(alignment: .leading, spacing: zoom.value(8)) {
            HStack(spacing: 2) {
                selectionButton
                roleBadge
                Spacer(minLength: 4)
                taskCompletionButton(capture)
                reorderMenu
            }.padding(.horizontal, 4)
            taskProjectLine(capture).padding(.horizontal, zoom.value(12))
            Button(action: open) {
                VStack(alignment: .leading, spacing: zoom.value(9)) {
                    if ![CaptureKind.text, .task].contains(capture.kind) {
                        CaptureThumbnail(store: state.store, capture: capture)
                            .frame(height: zoom.value(136)).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    Text(taskHeadline(capture))
                        .font(.system(size: zoom.fontSize(15), weight: .semibold))
                        .foregroundStyle(completed ? Palette.muted : Palette.foreground)
                        .strikethrough(completed, color: Palette.muted)
                        .lineSpacing(zoom.lineSpacing(2)).lineLimit(3)
                    if let text = capture.originalText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
                       !text.hasPrefix(capture.title.trimmingCharacters(in: .whitespacesAndNewlines)) {
                        Text(String(text.prefix(600)))
                            .font(.system(size: zoom.fontSize(12))).foregroundStyle(Palette.muted)
                            .lineSpacing(zoom.lineSpacing(2)).lineLimit(2)
                    }
                    if let planning = capture.taskPlanning, !planning.checklist.isEmpty {
                        ForEach(Array(planning.checklist.prefix(2))) { entry in
                            Label(entry.text, systemImage: entry.isCompleted ? "checkmark.square" : "square")
                                .font(.system(size: zoom.fontSize(11))).foregroundStyle(Palette.muted).lineLimit(1)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel("Open task, \(item.title)\(completed ? ", completed" : "")")
                .accessibilityIdentifier("project-preview-\(item.id)")
                .buddyHelp(capture.attachmentRelativePath != nil ? "Open saved file" : "Open task")
                .nativeContentDrag(label: item.title, items: drag,
                                   onError: { state.reportFailure($0.localizedDescription) }, onEnd: dragEnded)
                .padding(.horizontal, zoom.value(12))
            HStack(spacing: 6) {
                Text(captureReceiptText(capture))
                    .font(.system(size: zoom.fontSize(10))).foregroundStyle(Palette.muted)
                    .lineLimit(1).minimumScaleFactor(0.85)
                Text("· \(capture.kind == .text ? "Text" : captureTypeLabel(capture.kind))")
                    .font(.system(size: zoom.fontSize(10))).foregroundStyle(Palette.muted).lineLimit(1)
                Spacer(minLength: 0)
                Button(action: details) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .medium)).frame(width: 28, height: 28)
                }.buttonStyle(.plain).foregroundStyle(color)
                    .accessibilityLabel("Details for \(item.title)")
                    .accessibilityIdentifier("project-details-\(item.id)")
                    .buddyHelp("Open task details")
            }.padding(.horizontal, zoom.value(12))
        }.padding(.top, 2).padding(.bottom, 6)
            .background(color.opacity(0.025))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("project-task-content-\(item.id)")
    }

    private func taskHeadline(_ capture: Capture) -> String {
        let text = capture.originalText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = capture.title.trimmingCharacters(in: .whitespacesAndNewlines)
        // Task titles are a stored 100-character excerpt. Show the complete
        // bounded sentence once, rather than repeating it as supporting text.
        return !text.isEmpty && text.hasPrefix(title) ? String(text.prefix(800)) : item.title
    }

    private func taskProjectLine(_ capture: Capture) -> some View {
        HStack(spacing: 6) {
            if let name = ExplorerQuery.project(of: capture, in: state.store.captures), !name.isEmpty {
                Label(name, systemImage: "folder.fill")
                    .font(.system(size: zoom.fontSize(11), weight: .medium)).foregroundStyle(color)
                    .lineLimit(1).truncationMode(.middle)
                    .accessibilityIdentifier("project-task-project-\(item.id)")
                    .buddyHelp(name)
            }
            CaptureTaskPriorityTag(capture: capture).layoutPriority(1)
            Spacer(minLength: 0)
        }.accessibilityElement(children: .contain)
    }

    private var selectionButton: some View {
        Button(action: select) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(selected ? color : Palette.muted)
                .padding(3).background(Palette.surface.opacity(0.96), in: Circle())
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).focusable().focused(focus, equals: item.id)
            .accessibilityLabel("Select \(item.title)").accessibilityValue(selected ? "Selected" : "Not selected")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("project-select-\(item.id)")
            .buddyHelp(selected ? "Deselect item" : "Select item · Shift-click for a range")
    }

    private var preview: some View {
        Button(action: open) {
            Group {
                switch item {
                case .capture(let capture):
                    if compact, capture.isTask, [.text, .task].contains(capture.kind) {
                        Image(systemName: completed ? "checkmark.circle" : "checklist")
                            .font(.system(size: zoom.fontSize(21), weight: .medium)).foregroundStyle(completed ? Palette.completed : color)
                            .frame(width: min(48, zoom.value(36)), height: min(48, zoom.value(36)))
                            .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityHidden(true)
                    } else if [.text, .task].contains(capture.kind) {
                        textPreview(capture.originalText ?? capture.title, planning: capture.isTask ? capture.taskPlanning : nil)
                    } else {
                        CaptureThumbnail(store: state.store, capture: capture)
                    }
                case .note(let note): textPreview(note.text, planning: nil)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("Open \(role.title.lowercased()), \(item.title)\(completed ? ", completed" : "")")
            .accessibilityIdentifier("project-preview-\(item.id)")
            .buddyHelp(item.capture?.attachmentRelativePath != nil ? "Open saved file" : "Open item")
            .nativeContentDrag(label: item.title,
                               excluding: compact ? [] : [CGRect(x: 4, y: 4, width: 44, height: 44)], items: drag,
                               onError: { state.reportFailure($0.localizedDescription) }, onEnd: dragEnded)
    }

    private var roleBadge: some View {
        Label(completed ? "Task · Done" : role.title, systemImage: completed ? "checkmark.square.fill" : role.symbol)
            .font(.system(size: zoom.fontSize(10), weight: .semibold)).foregroundStyle(Palette.foreground)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, compact ? 6 : 9).padding(.vertical, compact ? 3 : 5)
            .background(Palette.surface.opacity(0.97), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(roleAccent.opacity(0.35), lineWidth: 0.7))
            .accessibilityElement(children: .ignore).accessibilityLabel(role.title)
            .accessibilityValue(role == .task ? (completed ? "Completed" : "To do") : "")
            .accessibilityIdentifier("project-kind-\(item.id)")
            .allowsHitTesting(false)
    }

    private var textBackground: some View {
        ZStack {
            role == .capture ? Palette.soft : Palette.surface
            if role != .capture { roleAccent.opacity(role == .note ? 0.07 : 0.045) }
            if role == .note, !compact {
                ProjectNoteRules().stroke(roleAccent.opacity(0.13), lineWidth: 0.6)
            }
        }.accessibilityHidden(true).allowsHitTesting(false)
    }

    private func textPreview(_ text: String, planning: TaskPlanning?) -> some View {
        VStack(alignment: .leading, spacing: zoom.value(8)) {
            if role == .capture, !compact {
                Image(systemName: "quote.opening").font(.system(size: zoom.fontSize(18), weight: .medium))
                    .foregroundStyle(Palette.muted.opacity(0.7)).accessibilityHidden(true)
            }
            Text(String(text.prefix(800)))
                .font(.system(size: zoom.fontSize(compact ? 11 : role == .capture ? 15 : 17),
                              weight: role == .task ? .medium : .regular, design: role == .note ? .serif : .default))
                .strikethrough(completed, color: Palette.muted)
                .lineSpacing(zoom.lineSpacing(4)).lineLimit(compact ? 3 : planning?.checklist.isEmpty == false ? 3 : 5)
                .multilineTextAlignment(.leading).foregroundStyle(Palette.foreground)
            if !compact, let planning, !planning.checklist.isEmpty {
                ForEach(Array(planning.checklist.prefix(2))) { entry in
                    Label(entry.text, systemImage: entry.isCompleted ? "checkmark.square" : "square")
                        .font(.system(size: zoom.fontSize(11))).foregroundStyle(Palette.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }.padding(.horizontal, zoom.value(compact ? 8 : 20)).padding(.top, zoom.value(compact ? 8 : 54)).padding(.bottom, zoom.value(compact ? 8 : 16))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(textBackground)
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: compact && role == .task ? 2 : 5) {
            if compact {
                roleBadge
                if let capture = item.capture, capture.isTask { taskProjectLine(capture) }
            }
            Button(action: details) {
                Text(item.title).font(.system(size: zoom.fontSize(13), weight: .semibold)).lineLimit(compact && zoom.factor > 1.25 ? 3 : 1)
                    .strikethrough(completed, color: Palette.muted)
                    .foregroundStyle(Palette.foreground).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Details for \(item.title)")
                .accessibilityIdentifier("project-details-\(item.id)")
                .nativeContentDrag(label: item.title, items: drag,
                                   onError: { state.reportFailure($0.localizedDescription) }, onEnd: dragEnded)
            HStack(spacing: 4) {
                if let capture = item.capture {
                    Text(captureReceiptText(capture)).lineLimit(1).minimumScaleFactor(0.85)
                    Text("·").accessibilityHidden(true)
                    Text(capture.kind == .text ? "Text" : captureTypeLabel(capture.kind)).lineLimit(1).fixedSize()
                } else {
                    Text(item.date.formatted(date: .abbreviated, time: .shortened)).lineLimit(1)
                    Text("· Notes").fixedSize()
                }
            }.font(.system(size: zoom.fontSize(10))).foregroundStyle(Palette.muted)
        }
    }

    private var actions: some View {
        VStack(spacing: 0) {
            if let capture = item.capture, capture.isTask {
                taskCompletionButton(capture)
            }
            reorderMenu
        }
    }

    private func taskCompletionButton(_ capture: Capture) -> some View {
        Button { state.toggleTaskCompletion(capture) } label: {
            Image(systemName: capture.isCompleted ? "checkmark.square.fill" : "square")
                .font(.system(size: 16)).frame(width: 28, height: 28)
        }.buttonStyle(.plain).foregroundStyle(capture.isCompleted ? Palette.completed : color)
            .accessibilityLabel(capture.isCompleted ? "Reopen task" : "Complete task")
            .accessibilityIdentifier("project-task-toggle-\(item.id)")
            .buddyHelp(capture.isCompleted ? "Reopen task" : "Complete task")
    }

    private var reorderMenu: some View {
        Menu {
                Button("Move earlier", systemImage: "arrow.up", action: earlier)
                Button("Move later", systemImage: "arrow.down", action: later)
            } label: { Image(systemName: "line.3.horizontal").font(.system(size: 11)).frame(width: 28, height: 28) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().foregroundStyle(Palette.muted)
                .disabled(!canReorder).accessibilityLabel("Reorder \(item.title)")
                .buddyHelp("Drag to reorder, or choose Move earlier / later")
                .nativeContentDrag(label: item.title, items: drag,
                                   onError: { state.reportFailure($0.localizedDescription) }, onEnd: dragEnded)
    }
}

@MainActor private struct ObservedProjectCaptureCard: View {
    @ObservedObject var capture: Capture
    let card: ProjectWorkspaceCard
    var body: some View { card.content }
}
