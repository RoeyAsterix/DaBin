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

/// Title, selection and completion are independent 32-point targets. Real
/// media has a bounded preview; text grows only to the lines it actually uses.
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
    var canMoveEarlier: Bool = true
    var canMoveLater: Bool = true

    private var role: ProjectCardRole { ProjectCardRole(item: item) }
    private var completed: Bool { item.capture?.isTask == true && item.capture?.isCompleted == true }
    private var roleAccent: Color {
        switch role {
        case .task: return completed ? Palette.completed : Palette.task
        case .note: return Color(nsColor: .systemOrange)
        case .capture: return Palette.muted
        }
    }
    private var projectName: String? {
        switch item {
        case .capture(let capture): return ExplorerQuery.project(of: capture, in: state.store.captures)
        case .note(let note): return note.projectName
        }
    }
    private var hasMedia: Bool {
        item.capture.map { CapturePreviewFileReference.thumbnail(store: state.store, capture: $0) != nil } ?? false
    }
    private var excerpt: String {
        let text: String
        switch item {
        case .note(let note): text = note.text
        case .capture(let capture):
            let original = capture.originalText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let title = capture.title.trimmingCharacters(in: .whitespacesAndNewlines)
            // The stored title is often the first 100 characters of this same
            // text. Keep those words in the title instead of repeating them.
            if original == title { text = "" }
            else if !title.isEmpty, original.hasPrefix(title) {
                let remainder = original.dropFirst(title.count)
                // A truncated stored title can end in the middle of a word.
                // Never render an orphaned suffix as the supporting sentence.
                text = remainder.first?.isWhitespace == true ? String(remainder) : original
            } else { text = original }
        }
        return String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(800))
    }
    private var checklist: [TaskChecklistItem] {
        item.capture?.isTask == true ? Array((item.capture?.taskPlanning?.checklist ?? []).prefix(2)) : []
    }
    private var hasBodyPreview: Bool { !compact && (hasMedia || !excerpt.isEmpty || !checklist.isEmpty) }

    var body: some View {
        Group {
            if let capture = item.capture { ObservedProjectCaptureCard(capture: capture, card: self) }
            else { content }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project-card-\(item.id)")
    }

    fileprivate var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                selectionButton
                Button(action: details) {
                    Text(item.title).font(.system(size: zoom.fontSize(15), weight: .semibold))
                        .lineSpacing(zoom.lineSpacing(2)).lineLimit(2)
                        .strikethrough(completed, color: Palette.muted)
                        .foregroundStyle(completed ? Palette.muted : Palette.foreground)
                        .padding(.top, max(0, (32 - zoom.fontSize(15) * 1.2) / 2))
                        .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
                        .multilineTextAlignment(.leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Details for \(item.title)")
                    .accessibilityIdentifier("project-details-\(item.id)").buddyHelp(item.title)
                    .nativeContentDrag(label: item.title, items: drag,
                        onError: { state.reportFailure($0.localizedDescription) }, onEnd: dragEnded)
                if let capture = item.capture, capture.isTask { taskCompletionButton(capture) }
                actionsMenu
            }
            if let capture = item.capture, capture.isTask { taskProjectLine(capture) }
            else if let projectName, !projectName.isEmpty {
                Label(projectName, systemImage: "folder.fill")
                    .font(.system(size: zoom.fontSize(11), weight: .medium)).foregroundStyle(color)
                    .lineLimit(1).truncationMode(.middle).buddyHelp(projectName)
            }
            if hasBodyPreview { preview }
            HStack(alignment: .center, spacing: 8) {
                if !hasBodyPreview { preview }
                VStack(alignment: .leading, spacing: 6) {
                    roleBadge
                    Text(receipt).font(.system(size: zoom.fontSize(10))).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(receipt).buddyHelp(receipt)
                        .accessibilityIdentifier("project-receipt-\(item.id)")
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(role == .task ? "project-task-content-\(item.id)" : "project-content-\(item.id)")
        .background(selected ? color.opacity(0.055) : Palette.surface)
        .overlay(alignment: .leading) {
            if role == .task { Rectangle().fill(roleAccent).frame(width: 3).allowsHitTesting(false).accessibilityHidden(true) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(color.opacity(selected ? 0.9 : 0.22), lineWidth: selected ? 2 : 0.8))
        .contextMenu { itemActions }
    }

    private var receipt: String {
        if let capture = item.capture {
            return captureReceiptText(capture) + " · " + (capture.kind == .text ? "Text" : captureTypeLabel(capture.kind))
        }
        return item.date.formatted(date: .abbreviated, time: .shortened) + " · Notes"
    }

    private func taskProjectLine(_ capture: Capture) -> some View {
        HStack(spacing: 6) {
            if let name = ExplorerQuery.project(of: capture, in: state.store.captures), !name.isEmpty {
                Label(name, systemImage: "folder.fill")
                    .font(.system(size: zoom.fontSize(11), weight: .medium)).foregroundStyle(color)
                    .lineLimit(1).truncationMode(.middle)
                    .accessibilityIdentifier("project-task-project-\(item.id)").buddyHelp(name)
            }
            CaptureTaskPriorityTag(capture: capture).layoutPriority(1)
            Spacer(minLength: 0)
        }.accessibilityElement(children: .contain)
    }

    private var selectionButton: some View {
        Button(action: select) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 19, weight: .medium)).foregroundStyle(selected ? color : Palette.muted)
                .frame(width: 32, height: 32).contentShape(Rectangle())
        }.buttonStyle(.plain).focusable().focused(focus, equals: item.id)
            .accessibilityLabel("Select \(item.title)").accessibilityValue(selected ? "Selected" : "Not selected")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("project-select-\(item.id)")
            .buddyHelp(selected ? "Deselect item" : "Select item · Shift-click for a range")
    }

    private var preview: some View {
        Button(action: open) {
            Group {
                if hasMedia, let capture = item.capture {
                    if compact {
                        CaptureThumbnail(store: state.store, capture: capture)
                            .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        ExplorerCapturePreviewLayout(factor: zoom.factor) {
                            CaptureThumbnail(store: state.store, capture: capture)
                        }.clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                } else if hasBodyPreview {
                    VStack(alignment: .leading, spacing: 6) {
                        if !excerpt.isEmpty {
                            Text(excerpt).font(.system(size: zoom.fontSize(12)))
                                .foregroundStyle(Palette.muted).lineSpacing(zoom.lineSpacing(2)).lineLimit(3)
                        }
                        ForEach(checklist) { entry in
                            Label(entry.text, systemImage: entry.isCompleted ? "checkmark.square" : "square")
                                .font(.system(size: zoom.fontSize(11))).foregroundStyle(Palette.muted).lineLimit(1)
                        }
                    }.frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                        .multilineTextAlignment(.leading)
                } else {
                    Image(systemName: completed ? "checkmark.square" : role.symbol)
                        .font(.system(size: 18, weight: .medium)).foregroundStyle(roleAccent)
                        .frame(width: 36, height: 36)
                        .background(roleAccent.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel("Open \(role.title.lowercased()), \(item.title)\(completed ? ", completed" : "")")
            .accessibilityIdentifier("project-preview-\(item.id)")
            .buddyHelp(item.capture?.attachmentRelativePath != nil ? "Open saved file" : "Open item")
            .nativeContentDrag(label: item.title, items: drag,
                onError: { state.reportFailure($0.localizedDescription) }, onEnd: dragEnded)
    }

    private var roleBadge: some View {
        Label(completed ? "Task · Done" : role.title, systemImage: completed ? "checkmark.square.fill" : role.symbol)
            .font(.system(size: zoom.fontSize(10), weight: .medium)).foregroundStyle(roleAccent)
            .lineLimit(1).fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .ignore).accessibilityLabel(role.title)
            .accessibilityValue(role == .task ? (completed ? "Completed" : "To do") : "")
            .accessibilityIdentifier("project-kind-\(item.id)").allowsHitTesting(false)
    }

    private func taskCompletionButton(_ capture: Capture) -> some View {
        Button { state.toggleTaskCompletion(capture) } label: {
            Image(systemName: capture.isCompleted ? "checkmark.square.fill" : "square")
                .font(.system(size: 18)).frame(width: 32, height: 32).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(capture.isCompleted ? Palette.completed : color)
            .accessibilityLabel(capture.isCompleted ? "Reopen task" : "Complete task")
            .accessibilityIdentifier("project-task-toggle-\(item.id)")
            .buddyHelp(capture.isCompleted ? "Reopen task" : "Complete task")
    }

    private var actionsMenu: some View {
        Menu {
            Button("Move earlier", systemImage: "arrow.up", action: earlier).disabled(!canReorder || !canMoveEarlier)
            Button("Move later", systemImage: "arrow.down", action: later).disabled(!canReorder || !canMoveLater)
            Divider()
            itemActions
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 14, weight: .medium))
                .frame(width: 32, height: 32).contentShape(Rectangle())
        }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).foregroundStyle(Palette.muted)
            .accessibilityLabel("Actions for \(item.title)").accessibilityIdentifier("project-more-\(item.id)")
            .buddyHelp("Item actions · Move earlier or later")
            .nativeContentDrag(label: item.title, items: drag,
                onError: { state.reportFailure($0.localizedDescription) }, onEnd: dragEnded)
    }

    @ViewBuilder private var itemActions: some View {
        if let capture = item.capture {
            ExplorerCaptureActions(state: state, workspace: state.workspace, capture: capture, taskConversion: makeTask)
        } else { Button("Edit project notes", systemImage: "note.text", action: details) }
    }
}

@MainActor private struct ObservedProjectCaptureCard: View {
    @ObservedObject var capture: Capture
    let card: ProjectWorkspaceCard
    var body: some View { card.content }
}
