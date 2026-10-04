import SwiftUI
import UniformTypeIdentifiers

extension View {
    /// Resolve the live saved content when dragging begins. The native session
    /// owns its pasteboard; starting a drag never replaces the user's clipboard.
    @MainActor
    func captureDragSource(state: AppState, capture: Capture) -> some View {
        captureDragSource(state: state, captures: [capture], label: capture.title)
    }

    @MainActor
    func captureDragSource(state: AppState, captures: [Capture], label: String) -> some View {
        nativeContentDrag(label: label, items: {
            try ExplorerTransfer.pasteboardWriters(for: captures, store: state.store)
        }, onError: { state.reportFailure($0.localizedDescription) })
    }

    /// Static captions transfer their exact text independently of the saved
    /// capture. Resolving a drag does not replace the general clipboard.
    @MainActor
    func readableTextDragSource(text: String, label: String, state: AppState) -> some View {
        nativeContentDrag(label: label, items: {
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [text as NSString]
        }, onError: { state.reportFailure($0.localizedDescription) })
    }
}

@MainActor
struct CaptureRow: View {
    @Environment(\.daBinAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var state: AppState
    @ObservedObject var capture: Capture
    let featured: Bool
    var isMatch: Bool? = nil
    var indexedTextMatch: String? = nil
    var taskAtTop = false
    var showsCopyButton = true
    var embeddedInCard = false
    var showsProject = true
    @State private var copied = false
    @State private var copyGeneration = 0
    @State private var dropTargeted = false

    private var attachments: [Capture] { state.store.attachments(for: capture) }
    private var projectName: String? { ExplorerQuery.project(of: capture, in: state.store.captures) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsProject {
                CaptureProjectPickerButton(state: state, capture: capture)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            header
            if let isMatch {
                Label(isMatch ? "Match" : "Nearby capture", systemImage: isMatch ? "magnifyingglass" : "clock")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(isMatch ? accent : Palette.muted)
            }
            if !capture.isTask { content }
            if !capture.isMinimized {
                if let indexedTextMatch {
                    Label(indexedTextMatch, systemImage: "text.viewfinder")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(2)
                        .accessibilityLabel("Matched recognized text: \(indexedTextMatch)")
                        .accessibilityIdentifier("capture-indexed-match-\(capture.id.uuidString)")
                        .captureDragSource(state: state, capture: capture)
                }
                if !capture.comment.isEmpty {
                    Label(capture.comment, systemImage: "text.bubble")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted).lineLimit(2)
                        .accessibilityIdentifier("capture-comment-\(capture.id.uuidString)")
                        .readableTextDragSource(text: capture.comment, label: "Comment for \(capture.title)", state: state)
                }
                if let reminder = capture.reminderAt {
                    Label(reminder.formatted(date: .abbreviated, time: .shortened), systemImage: capture.isCompleted ? "bell.slash" : "bell")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted).lineLimit(1)
                }
                if !attachments.isEmpty {
                    Label("\(attachments.count) attachments", systemImage: "paperclip")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                if capture.isTask { CaptureTrailView(state: state, capture: capture) }
                if let parentID = capture.parentTaskID {
                    Button { state.openCapture(parentID, focus: "task") } label: { Label("Task attachment", systemImage: "arrow.turn.up.left") }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(accent)
                }
                if capture.isTask {
                    TaskFocusControls(state: state, capture: capture)
                        .padding(.top, 10)
                        .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 0.7) }
                }
                primaryActions
                CaptureConversionUndo(state: state, capture: capture)
            }
            secondaryActions
        }
        .padding(embeddedInCard ? 4 : 16)
        .projectCardBackground(workspace: state.workspace, projectName: projectName,
                               enabled: !embeddedInCard)
        .projectCardFrame(workspace: state.workspace, projectName: projectName, activeProject: nil,
                          fallbackColor: embeddedInCard ? .clear : dropTargeted ? accent : taskAtTop ? accent.opacity(0.55) : Palette.line,
                          fallbackWidth: embeddedInCard ? 0 : dropTargeted ? 1.5 : 0.7)
        .padding(.vertical, embeddedInCard ? 0 : 6)
        .contextMenu { CaptureActionMenuItems(state: state, capture: capture, includesRemoval: true) }
        .onDrop(of: TaskAttachmentTypes.identifiers, isTargeted: $dropTargeted) { providers in
            guard capture.isTask else { return false }
            return state.receiveTaskAttachments(providers, to: capture)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: capture.isTask)
    }

    private var header: some View {
        HStack(alignment: capture.isTask ? .top : .center, spacing: 8) {
            if capture.isTask { TaskStatusButton(state: state, capture: capture) }
            VStack(alignment: .leading, spacing: 4) {
                if capture.isTask {
                    Text(capture.isCompleted ? "COMPLETED" : "TASK")
                        .font(.system(size: 10, weight: .medium)).tracking(0.7).foregroundStyle(Palette.muted)
                    title
                    CaptureTaskPriorityTag(capture: capture)
                    CaptureReceiptView(capture: capture, category: captureTypeLabel(capture.kind))
                } else {
                    CaptureTrailView(state: state, capture: capture)
                    CaptureReceiptView(capture: capture, category: captureTypeLabel(capture.kind))
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if capture.isPinned { Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(accent).accessibilityLabel("Pinned") }
            if showsCopyButton {
                BuddyIconButton(symbol: copied ? "checkmark" : "doc.on.doc", title: copied ? "Copied" : "Copy \(capture.title)") { copy() }
                    .accessibilityIdentifier(CaptureCopyButton.accessibilityIdentifier(for: [capture]))
            }
            CaptureTrashButton(state: state, capture: capture)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !capture.isMinimized, ![CaptureKind.text, .task].contains(capture.kind) {
                Button { state.openCapture(capture.id) } label: {
                    CaptureThumbnail(store: state.store, capture: capture)
                        .frame(height: capture.kind == .link ? 164 : 208)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).accessibilityLabel("Preview \(capture.title)")
                    .captureDragSource(state: state, capture: capture)
            }
            title
            if !capture.isMinimized, !capture.previewDescription.isEmpty {
                Text(capture.previewDescription).font(.system(size: 13)).foregroundStyle(Palette.muted).lineSpacing(3).lineLimit(3)
                    .captureDragSource(state: state, capture: capture)
            }
        }
    }

    private var title: some View {
        Button { state.openCapture(capture.id) } label: {
            Text(capture.title.isEmpty ? "Untitled capture" : capture.title)
                .font(.system(size: 16, weight: .semibold))
                .strikethrough(capture.isTask && capture.isCompleted, color: Palette.muted)
                .foregroundStyle(capture.isCompleted ? Palette.muted : Palette.foreground)
                .lineLimit(capture.isMinimized ? 1 : 4).frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel("Open \(capture.title), \(capture.isTask ? "task" : captureTypeLabel(capture.kind)), saved \(prettyDay(capture.captureDay)) at \(captureClock(capture))")
            .captureDragSource(state: state, capture: capture)
    }

    private var primaryActions: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            if !capture.isTask { CaptureTaskConversionButton(state: state, capture: capture) }
            if !capture.isTask, capture.parentTaskID == nil { CaptureKeepButton(state: state, capture: capture) }
        }
    }

    private var secondaryActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 2) {
                if !capture.isMinimized {
                    BuddyIconButton(symbol: "text.bubble", title: "Comment") { state.openCapture(capture.id, focus: "comment") }
                    BuddyIconButton(symbol: "bell", title: "Reminder") { state.openCapture(capture.id, focus: "reminder") }
                    if capture.isTask {
                        BuddyIconButton(symbol: "paperclip", title: "Add task attachments") { state.openCapture(capture.id, focus: "task") }
                    }
                }
                Spacer(minLength: 0)
                collapseAndMore
            }
            HStack {
                Spacer(minLength: 0)
                collapseAndMore
            }
        }
    }

    private var collapseAndMore: some View {
        HStack(spacing: 2) {
            BuddyIconButton(symbol: capture.isMinimized ? "chevron.down" : "chevron.up", title: capture.isMinimized ? "Expand capture" : "Minimize capture") { state.toggleMinimized(capture) }
            CaptureControls(state: state, capture: capture)
        }
    }

    private func copy() {
        guard state.copyCapturesToClipboard([capture]) else { return }
        copied = true
        copyGeneration &+= 1
        let generation = copyGeneration
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.25))
            guard generation == copyGeneration else { return }
            copied = false
        }
    }
}

/// Keep the capture date and time to the left of its category on every card.
/// Keep the category intact; the receipt may wrap in narrow columns instead of
/// dropping the date or replacing it with an edit timestamp.
@MainActor
struct CaptureReceiptView: View {
    @ObservedObject var capture: Capture
    let category: String
    var fontSize: CGFloat = 11

    var body: some View {
        ViewThatFits(in: .horizontal) {
            receiptRow(stacked: false)
            receiptRow(stacked: true)
        }
        .font(.system(size: fontSize)).foregroundStyle(Palette.muted)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture-receipt-\(capture.id.uuidString)")
    }

    private func receiptRow(stacked: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Group {
                if stacked {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(prettyDay(capture.captureDay, includeWeekday: false))
                        Text(captureClock(capture))
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(captureReceiptText(capture))
                } else {
                    Text(captureReceiptText(capture)).fixedSize()
                }
            }
                .monospacedDigit().layoutPriority(1)
                .accessibilityIdentifier("capture-receipt-time-\(capture.id.uuidString)")
            Text("·").accessibilityHidden(true)
            Text(category).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .accessibilityIdentifier("capture-receipt-category-\(capture.id.uuidString)")
        }
    }
}

/// Every card uses the same recoverable removal and confirmation flow.
@MainActor
struct CaptureTrashButton: View {
    @ObservedObject var state: AppState
    @ObservedObject var capture: Capture

    var body: some View {
        BuddyIconButton(symbol: "trash", title: "Move to Recently Deleted") {
            state.requestRemoval(capture)
        }
        .accessibilityLabel("Move \(capture.title.isEmpty ? "capture" : capture.title) to Recently Deleted")
        .accessibilityHint("You can restore this capture. Files at their original locations are kept.")
        .accessibilityIdentifier("capture-trash-\(capture.id.uuidString)")
        .disabled(state.removingCaptureID != nil || state.isArchiveOperationRunning)
    }
}

/// Feedback stays with the same capture identity so conversion does not navigate
/// away or replace the user's selected card.
@MainActor
struct CaptureConversionUndo: View {
    @ObservedObject var state: AppState
    @ObservedObject var capture: Capture
    var body: some View {
        if state.lastConvertedCaptureID == capture.id, state.canUndoTaskConversion {
            HStack {
                Label("Task ready", systemImage: "checkmark").foregroundStyle(Palette.muted)
                Spacer(minLength: 0)
                Button("Undo") { state.undoTaskConversion() }.buttonStyle(.plain)
            }.font(.system(size: 11)).accessibilityIdentifier("capture-conversion-undo-\(capture.id.uuidString)")
        }
    }
}

@MainActor
struct CaptureKeepButton: View {
    @ObservedObject var state: AppState
    @ObservedObject var capture: Capture
    @ObservedObject private var workspace: WorkspaceStore
    private var kept: Bool { workspace.processedInboxIDs.contains(capture.id) }

    init(state: AppState, capture: Capture) {
        self.state = state
        self.capture = capture
        self.workspace = state.workspace
    }

    var body: some View {
        if state.route == .inbox, capture.parentTaskID == nil, !kept {
            BuddyIconButton(symbol: "checkmark", title: "Keep in Projects") {
                do {
                    try workspace.markInboxProcessed([capture.id], processed: true)
                    state.status = AppStatusMessage(text: "Kept in Projects. Your original capture day stays the same.", severity: .success)
                } catch { state.reportFailure(error.localizedDescription) }
            }.accessibilityLabel("Keep in Projects: \(capture.title)")
        }
    }
}

@MainActor
struct CaptureControls: View {
    @Environment(\.daBinAccent) private var accent
    @ObservedObject var state: AppState
    @ObservedObject var capture: Capture
    var includesRemoval = false

    var body: some View {
        Menu { CaptureActionMenuItems(state: state, capture: capture, includesRemoval: includesRemoval) } label: {
            Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold)).frame(width: 32, height: 32)
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().foregroundStyle(accent).buddyHelp("More capture actions")
            .accessibilityLabel("More actions for \(capture.title)")
            .disabled(state.removingCaptureID == capture.id)
    }
}

@MainActor
private struct CaptureActionMenuItems: View {
    @ObservedObject var state: AppState
    @ObservedObject var capture: Capture
    let includesRemoval: Bool
    var body: some View {
        Button("Open capture", systemImage: "arrow.up.forward.square") { state.openCapture(capture.id) }
        Button(capture.comment.isEmpty ? "Add note" : "Edit note", systemImage: "text.bubble") { state.openCapture(capture.id, focus: "comment") }
        Button(capture.reminderAt == nil ? "Add reminder" : "Edit reminder", systemImage: "bell") { state.openCapture(capture.id, focus: "reminder") }
        Button(capture.isPinned ? "Unpin" : "Pin", systemImage: capture.isPinned ? "pin.slash" : "pin") { state.togglePinned(capture) }
        CaptureTaskConversionMenu(state: state, capture: capture)
        if capture.isTask {
            Button("Add task attachments", systemImage: "paperclip") { state.openCapture(capture.id, focus: "task") }
            Button(capture.isCompleted ? "Mark incomplete" : "Complete task", systemImage: "checkmark.circle") { state.toggleTaskCompletion(capture) }
        }
        Divider()
        Button(capture.isMinimized ? "Expand capture" : "Minimize capture", systemImage: capture.isMinimized ? "chevron.down" : "chevron.up") { state.toggleMinimized(capture) }
        Button("Show capture day", systemImage: "calendar") { state.showCaptureDay(capture) }
        if includesRemoval {
            Button("Move to Recently Deleted", systemImage: "trash", role: .destructive) { state.requestRemoval(capture) }
        }
    }
}

@MainActor
struct CaptureTaskConversionButton: View {
    @Environment(\.daBinAccent) private var accent
    @ObservedObject var state: AppState
    @ObservedObject var capture: Capture
    var body: some View {
        BuddyIconButton(symbol: "checkmark.square", title: "Turn into task") { state.convertToTask(capture) }
            .accessibilityLabel("Turn \(capture.title) into a task")
            .accessibilityHint("Keeps the captured content, note and reminder")
            .accessibilityIdentifier("capture-convert-to-task-\(capture.id.uuidString)")
            .disabled(state.removingCaptureID == capture.id)
    }
}

@MainActor
struct CaptureTaskConversionMenu: View {
    @ObservedObject var state: AppState
    @ObservedObject var capture: Capture
    var body: some View {
        if !capture.isTask {
            Button { state.convertToTask(capture) } label: { Label("Turn into task", systemImage: "checkmark.circle") }
                .accessibilityLabel("Turn \(capture.title) into a task")
                .accessibilityIdentifier("capture-convert-to-task-menu-\(capture.id.uuidString)")
                .disabled(state.removingCaptureID == capture.id)
        }
    }
}

@MainActor
struct TaskStatusButton: View {
    @ObservedObject var state: AppState
    @ObservedObject var capture: Capture
    @Environment(\.daBinAccent) private var accent
    private var label: String { capture.isCompleted ? "Completed" : "Task" }
    var body: some View {
        Button { state.toggleTaskCompletion(capture) } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(capture.isCompleted ? Palette.foreground : Color.clear)
                RoundedRectangle(cornerRadius: 6).strokeBorder(capture.isCompleted ? Palette.foreground : Palette.muted, lineWidth: 1.3)
                if capture.isCompleted {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.surface)
                }
            }.frame(width: 21, height: 21).frame(width: 34, height: 36).contentShape(Rectangle())
        }.buttonStyle(.plain).buddyHelp(capture.isCompleted ? "Mark incomplete" : "Mark completed")
            .accessibilityLabel("\(label): \(capture.title)")
            .accessibilityHint(capture.isCompleted ? "Mark this task incomplete" : "Mark this task completed")
            .accessibilityValue(label).accessibilityIdentifier("capture-task-status-\(capture.id.uuidString)")
            .accessibilityAddTraits(capture.isCompleted ? .isSelected : [])
    }
}
