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
    @Environment(\.workspaceZoom) private var zoom
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
    var planningActions: AnyView? = nil
    var planningMetadata: AnyView? = nil
    var navigationItemID: String? = nil
    /// A receipt summary for Today; it never changes saved minimization state.
    var compactReceipt = false
    @State private var copied = false
    @State private var copyGeneration = 0
    @State private var dropTargeted = false

    private var attachments: [Capture] { state.store.attachments(for: capture) }
    private var projectName: String? { ExplorerQuery.project(of: capture, in: state.store.captures) }

    private var showsTrail: Bool {
        !capture.isTask || planningActions == nil || capture.kind != .task
            || capture.sourceApplicationName != nil || capture.sourceApplicationBundleIdentifier != nil
            || !capture.pasteHistory.isEmpty
    }
    private var hasPreview: Bool {
        !capture.isTask && ![CaptureKind.text, .task].contains(capture.kind) && !capture.isMinimized
            && CapturePreviewFileReference.thumbnail(store: state.store, capture: capture) != nil
    }

    var body: some View {
        Group {
            if compactReceipt {
                compactReceiptContent
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    header
                    if showsProject {
                        CaptureProjectPriorityHeader(state: state, capture: capture)
                    } else {
                        CaptureTaskPriorityTag(capture: capture)
                    }
                    receiptAndTrail
                    if let isMatch {
                        Label(isMatch ? "Match" : "Nearby capture", systemImage: isMatch ? "magnifyingglass" : "clock")
                            .font(.system(size: zoom.fontSize(11), weight: .medium))
                            .foregroundStyle(isMatch ? accent : Palette.muted)
                    }
                    if !capture.isTask { content }
                    if !capture.isMinimized {
                        if let indexedTextMatch {
                            Label(indexedTextMatch, systemImage: "text.viewfinder")
                                .font(.system(size: zoom.fontSize(11))).foregroundStyle(Palette.muted).lineLimit(2)
                                .accessibilityLabel("Matched recognized text: \(indexedTextMatch)")
                                .accessibilityIdentifier("capture-indexed-match-\(capture.id.uuidString)")
                                .captureDragSource(state: state, capture: capture)
                        }
                        if !capture.comment.isEmpty {
                            Button { state.openCapture(capture.id, focus: "comment") } label: {
                                Label(capture.comment, systemImage: "text.bubble")
                                    .font(.system(size: zoom.fontSize(12))).foregroundStyle(Palette.muted).lineLimit(2)
                                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                                    .contentShape(Rectangle()).multilineTextAlignment(.leading)
                            }.buttonStyle(.plain)
                                .accessibilityLabel("Comment: \(capture.comment)")
                                .accessibilityIdentifier("capture-comment-\(capture.id.uuidString)")
                                .readableTextDragSource(text: capture.comment, label: "Comment for \(capture.title)", state: state)
                        }
                        if capture.reminderAt != nil || !attachments.isEmpty || capture.parentTaskID != nil {
                            supportingActions
                        }
                        if let planningMetadata { planningMetadata }
                        if let planningActions {
                            planningActions
                                .accessibilityElement(children: .contain)
                                .accessibilityIdentifier("capture-planning-actions-\(capture.id.uuidString)")
                        }
                        if !capture.isTask { primaryActions }
                        CaptureConversionUndo(state: state, capture: capture)
                    }
                    if capture.isTask && (!capture.isMinimized
                        || (capture.taskPlanning?.focusSession?.isRunning == true && !capture.isCompleted)) {
                        TaskFocusControls(state: state, capture: capture, showsSchedule: planningActions == nil,
                                          taskCardStyle: true)
                            .padding(.top, 6)
                            .overlay(alignment: .top) { Rectangle().fill(Palette.line.opacity(0.7)).frame(height: 0.5) }
                    }
                }
            }
        }
        .padding(embeddedInCard ? 2 : compactReceipt ? 8 : 12)
        .workspaceZoomItem(navigationItemID ?? "capture:" + capture.id.uuidString)
        .projectCardBackground(workspace: state.workspace, projectName: projectName,
                               cornerRadius: 12, enabled: !embeddedInCard)
        .projectCardFrame(workspace: state.workspace, projectName: projectName, activeProject: nil,
                          cornerRadius: 12,
                          fallbackColor: embeddedInCard ? .clear : dropTargeted ? accent : taskAtTop ? accent.opacity(0.55) : Palette.line,
                          fallbackWidth: embeddedInCard ? 0 : dropTargeted ? 1.5 : 0.7)
        .padding(.vertical, embeddedInCard ? 0 : 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture-card-\(capture.id.uuidString)")
        .contextMenu { CaptureActionMenuItems(state: state, capture: capture, includesRemoval: true, allowsMinimization: !compactReceipt, showsParentTask: compactReceipt) }
        .onDrop(of: TaskAttachmentTypes.identifiers, isTargeted: $dropTargeted) { providers in
            guard capture.isTask else { return false }
            return state.receiveTaskAttachments(providers, to: capture)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: capture.isTask)
    }

    private var receiptAndTrail: some View {
        ExplorerCaptureActionsLayout {
            CaptureReceiptView(capture: capture, category: captureTypeLabel(capture.kind))
            if showsTrail { CaptureTrailView(state: state, capture: capture) }
        }
    }

    private var supportingActions: some View {
        BuddyActionFlow(spacing: 8) {
            if let reminder = capture.reminderAt {
                Button { state.openCapture(capture.id, focus: "reminder") } label: {
                    Label(reminder.formatted(date: .abbreviated, time: .shortened),
                          systemImage: capture.isCompleted ? "bell.slash" : "bell")
                        .lineLimit(1).frame(minHeight: 32).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Reminder, \(reminder.formatted(date: .complete, time: .shortened))")
            }
            if !attachments.isEmpty {
                Button { state.openCapture(capture.id, focus: "task") } label: {
                    Label("\(attachments.count) \(attachments.count == 1 ? "attachment" : "attachments")", systemImage: "paperclip")
                        .frame(minHeight: 32).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("capture-attachments-\(capture.id.uuidString)")
            }
            if let parentID = capture.parentTaskID {
                Button { state.openCapture(parentID, focus: "task") } label: {
                    Label("Task attachment", systemImage: "arrow.turn.up.left").frame(minHeight: 32)
                }.buttonStyle(.plain)
            }
        }.font(.system(size: zoom.fontSize(11))).foregroundStyle(Palette.muted)
    }

    private var compactReceiptContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                if capture.isTask { TaskStatusButton(state: state, capture: capture) }
                Button { state.openCapture(capture.id) } label: {
                    Text(capture.title.isEmpty ? "Untitled capture" : capture.title)
                        .font(.system(size: zoom.fontSize(15), weight: .semibold))
                        .strikethrough(capture.isTask && capture.isCompleted, color: Palette.muted)
                        .foregroundStyle(capture.isCompleted ? Palette.muted : Palette.foreground)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                        .multilineTextAlignment(.leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel("Open \(capture.title), \(capture.isTask ? "task" : captureTypeLabel(capture.kind)), saved \(prettyDay(capture.captureDay)) at \(captureClock(capture))")
                    .accessibilityIdentifier("capture-compact-open-\(capture.id.uuidString)")
                    .captureDragSource(state: state, capture: capture)
                    .buddyHelp(capture.title)
                    .layoutPriority(1)
                if capture.isPinned {
                    Image(systemName: "pin.fill").font(.system(size: zoom.fontSize(10)))
                        .foregroundStyle(accent).accessibilityLabel("Pinned")
                }
                if showsCopyButton {
                    Button(action: copy) {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: min(15, max(12, zoom.fontSize(13))), weight: .medium))
                            .padding(.horizontal, 6).frame(minHeight: 32).contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(accent)
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityLabel(copied ? "Copied" : "Copy \(capture.title)")
                        .accessibilityIdentifier(CaptureCopyButton.accessibilityIdentifier(for: [capture]))
                        .buddyHelp(copied ? "Copied" : "Copy \(capture.title)")
                }
                Menu { CaptureActionMenuItems(state: state, capture: capture, includesRemoval: true, allowsMinimization: false, showsParentTask: true) } label: {
                    Label("More", systemImage: "ellipsis")
                        .font(.system(size: min(15, max(12, zoom.fontSize(13))), weight: .medium))
                        .padding(.horizontal, 6).frame(minHeight: 32).contentShape(Rectangle())
                }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                    .foregroundStyle(accent).buddyHelp("More capture actions")
                    .accessibilityLabel("More actions for \(capture.title)")
                    .accessibilityIdentifier("capture-more-\(capture.id.uuidString)")
                    .disabled(state.removingCaptureID == capture.id)
                    .daBinTutorialAnchor(.captureActions)
            }
            if showsProject {
                CaptureProjectPriorityHeader(state: state, capture: capture)
            } else {
                CaptureTaskPriorityTag(capture: capture)
            }
            CaptureReceiptView(capture: capture, category: captureTypeLabel(capture.kind))
            CaptureConversionUndo(state: state, capture: capture)
        }.accessibilityElement(children: .contain)
            .accessibilityIdentifier("capture-compact-receipt-\(capture.id.uuidString)")
    }

    private var header: some View {
        CaptureCardHeaderLayout(minimumLeadingWidth: 120 + (capture.isTask ? 38 : 0) + (capture.isPinned ? 16 : 0)) {
            HStack(alignment: .top, spacing: 6) {
                if capture.isTask { TaskStatusButton(state: state, capture: capture) }
                title.layoutPriority(1)
                if capture.isPinned {
                    Image(systemName: "pin.fill").font(.system(size: zoom.fontSize(10)))
                        .foregroundStyle(accent).frame(height: 32).accessibilityLabel("Pinned")
                }
            }
            HStack(spacing: 6) {
                if showsCopyButton {
                    BuddyIconButton(symbol: copied ? "checkmark" : "doc.on.doc", title: copied ? "Copied" : "Copy \(capture.title)") { copy() }
                        .accessibilityIdentifier(CaptureCopyButton.accessibilityIdentifier(for: [capture]))
                }
                CaptureTrashButton(state: state, capture: capture)
                CaptureControls(state: state, capture: capture)
            }
        }
    }

    @ViewBuilder private var content: some View {
        if hasPreview {
            Button { state.openCapture(capture.id) } label: {
                CaptureThumbnail(store: state.store, capture: capture)
                    .frame(height: min(176, zoom.value(capture.kind == .link ? 104 : 132)))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain).accessibilityLabel("Preview \(capture.title)")
                .captureDragSource(state: state, capture: capture)
        }
        if !capture.isMinimized, !capture.previewDescription.isEmpty {
            Text(capture.previewDescription).font(.system(size: zoom.fontSize(12)))
                .foregroundStyle(Palette.muted).lineSpacing(zoom.lineSpacing(2)).lineLimit(3)
                .captureDragSource(state: state, capture: capture)
        }
    }

    private var title: some View {
        Button { state.openCapture(capture.id) } label: {
            Text(capture.title.isEmpty ? "Untitled capture" : capture.title)
                .font(.system(size: zoom.fontSize(15), weight: .semibold))
                .strikethrough(capture.isTask && capture.isCompleted, color: Palette.muted)
                .foregroundStyle(capture.isCompleted ? Palette.muted : Palette.foreground)
                .lineLimit(capture.isMinimized ? 1 : 2).fixedSize(horizontal: false, vertical: true)
                .padding(.top, max(0, (32 - zoom.fontSize(15) * 1.2) / 2))
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
                .multilineTextAlignment(.leading).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel("Open \(capture.title), \(capture.isTask ? "task" : captureTypeLabel(capture.kind)), saved \(prettyDay(capture.captureDay)) at \(captureClock(capture))")
            .accessibilityIdentifier("capture-open-\(capture.id.uuidString)")
            .captureDragSource(state: state, capture: capture)
            .buddyHelp(capture.title)
    }

    private var primaryActions: some View {
        BuddyActionFlow(spacing: 6) {
            CaptureTaskConversionButton(state: state, capture: capture, visualLabel: "Task")
            if capture.parentTaskID == nil {
                CaptureKeepButton(state: state, capture: capture, visualLabel: "Keep")
            }
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
    @Environment(\.workspaceZoom) private var zoom
    @ObservedObject var capture: Capture
    let category: String
    var fontSize: CGFloat = 11

    var body: some View {
        ViewThatFits(in: .horizontal) {
            receiptRow(stacked: false)
            receiptRow(stacked: true)
        }
        .font(.system(size: zoom.fontSize(fontSize))).foregroundStyle(Palette.muted)
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
    var visualLabel: String? = nil

    var body: some View {
        BuddyIconButton(symbol: "trash", title: "Move to Recently Deleted", visualLabel: visualLabel) {
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
            ExplorerCaptureActionsLayout {
                Label("Task ready", systemImage: "checkmark").foregroundStyle(Palette.muted)
                Button { state.undoTaskConversion() } label: {
                    Text("Undo").frame(minWidth: 32, minHeight: 32).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityIdentifier("capture-conversion-undo-action-\(capture.id.uuidString)")
            }.font(.system(size: 11))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("capture-conversion-undo-\(capture.id.uuidString)")
        }
    }
}

@MainActor
struct CaptureKeepButton: View {
    @ObservedObject var state: AppState
    @ObservedObject var capture: Capture
    var visualLabel: String? = nil
    @ObservedObject private var workspace: WorkspaceStore
    private var kept: Bool { workspace.processedInboxIDs.contains(capture.id) }

    init(state: AppState, capture: Capture, visualLabel: String? = nil) {
        self.state = state
        self.capture = capture
        self.visualLabel = visualLabel
        self.workspace = state.workspace
    }

    var body: some View {
        if state.route == .inbox, capture.parentTaskID == nil, !kept {
            BuddyIconButton(symbol: "checkmark", title: "Keep in Projects", visualLabel: visualLabel) {
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
            Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold))
                .frame(width: 32, height: 32).contentShape(Rectangle())
        // The borderless native menu shrinks its hit target to the ellipsis
        // glyph. A plain button menu retains the full matching icon target.
        }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .foregroundStyle(accent).buddyHelp("More capture actions")
            .accessibilityLabel("More actions for \(capture.title)")
            .accessibilityIdentifier("capture-more-\(capture.id.uuidString)")
            .disabled(state.removingCaptureID == capture.id)
            .daBinTutorialAnchor(.captureActions)
    }
}

@MainActor
struct CaptureActionMenuItems: View {
    @ObservedObject var state: AppState
    @ObservedObject var capture: Capture
    let includesRemoval: Bool
    var allowsMinimization = true
    var showsParentTask = false
    var openingLabel = "Open capture"
    var body: some View {
        Button(openingLabel, systemImage: "arrow.up.forward.square") { state.openCapture(capture.id) }
        Button(capture.comment.isEmpty ? "Add comment" : "Edit comment", systemImage: "text.bubble") { state.openCapture(capture.id, focus: "comment") }
        Button(capture.reminderAt == nil ? "Add reminder" : "Edit reminder", systemImage: "bell") { state.openCapture(capture.id, focus: "reminder") }
        Button(capture.isPinned ? "Unpin" : "Pin", systemImage: capture.isPinned ? "pin.slash" : "pin") { state.togglePinned(capture) }
        CaptureReturnToInboxMenuItem(state: state, capture: capture)
        CaptureTaskConversionMenu(state: state, capture: capture)
        if capture.isTask {
            Button("Add task attachments", systemImage: "paperclip") { state.openCapture(capture.id, focus: "task") }
            Button(capture.isCompleted ? "Mark incomplete" : "Complete task", systemImage: "checkmark.circle") { state.toggleTaskCompletion(capture) }
        }
        Divider()
        if showsParentTask, let parentID = capture.parentTaskID {
            Button("Open parent task", systemImage: "arrow.turn.up.left") { state.openCapture(parentID, focus: "task") }
                .accessibilityIdentifier("capture-parent-task-menu-\(capture.id.uuidString)")
        }
        if allowsMinimization {
            Button(capture.isMinimized ? "Expand capture" : "Minimize capture", systemImage: capture.isMinimized ? "chevron.down" : "chevron.up") { state.toggleMinimized(capture) }
        }
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
    var visualLabel: String? = nil
    var body: some View {
        BuddyIconButton(symbol: "checkmark.square", title: "Turn into task", visualLabel: visualLabel) { state.convertToTask(capture) }
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
            }.frame(width: 21, height: 21).frame(width: 32, height: 32).contentShape(Rectangle())
        }.buttonStyle(.plain).buddyHelp(capture.isCompleted ? "Mark incomplete" : "Mark completed")
            .accessibilityLabel("\(label): \(capture.title)")
            .accessibilityHint(capture.isCompleted ? "Mark this task incomplete" : "Mark this task completed")
            .accessibilityValue(label).accessibilityIdentifier("capture-task-status-\(capture.id.uuidString)")
            .accessibilityAddTraits(capture.isCompleted ? .isSelected : [])
    }
}
