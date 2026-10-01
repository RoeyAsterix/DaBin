import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct CaptureRow: View {
    @Environment(\.daBinAccent) private var accent
    @ObservedObject var state: AppState
    @ObservedObject var capture: Capture
    let featured: Bool
    var isMatch: Bool? = nil
    var indexedTextMatch: String? = nil
    var taskAtTop = false
    var showsCopyButton = true
    var embeddedInCard = false
    var showsDate = false
    @State private var copied = false
    @State private var copyGeneration = 0
    @State private var dropTargeted = false

    private var taskColor: Color { capture.isCompleted ? Palette.completed : accent }
    private var attachments: [Capture] { state.store.attachments(for: capture) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                CaptureSourceIcon(capture: capture)
                VStack(alignment: .leading, spacing: 2) {
                    Text(showsDate ? "\(prettyDay(capture.captureDay, includeWeekday: false)) · \(captureClock(capture))" : captureClock(capture))
                        .font(.system(size: 12, weight: .medium)).monospacedDigit()
                    if !capture.isTask {
                        Text(captureLinkHost(capture) ?? captureTypeLabel(capture.kind))
                            .font(.system(size: 10)).lineLimit(1)
                    }
                }.foregroundStyle(Palette.muted)
                if capture.isPinned { Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(accent).accessibilityLabel("Pinned") }
                Spacer(minLength: 0)
                if capture.isTask { TaskStatusButton(state: state, capture: capture) }
                if showsCopyButton {
                    BuddyIconButton(symbol: copied ? "checkmark" : "doc.on.doc", title: copied ? "Copied" : "Copy \(capture.title)") { copy() }
                        .accessibilityIdentifier(CaptureCopyButton.accessibilityIdentifier(for: [capture]))
                }
            }
            if let isMatch {
                Label(isMatch ? "Match" : "Nearby capture", systemImage: isMatch ? "magnifyingglass" : "clock")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(isMatch ? accent : Palette.muted)
            }
            Button { state.openCapture(capture.id) } label: {
                VStack(alignment: .leading, spacing: 10) {
                    if !capture.isMinimized, ![CaptureKind.text, .task].contains(capture.kind) {
                        CaptureThumbnail(store: state.store, capture: capture)
                            .frame(height: capture.kind == .link ? 132 : 172)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    Text(capture.title.isEmpty ? "Untitled capture" : capture.title)
                        .font(.system(size: 16, weight: .semibold))
                        .strikethrough(capture.isTask && capture.isCompleted, color: Palette.muted)
                        .foregroundStyle(capture.isCompleted ? Palette.muted : Palette.foreground)
                        .lineLimit(capture.isMinimized ? 1 : 4).frame(maxWidth: .infinity, alignment: .leading)
                    if !capture.isMinimized, !capture.previewDescription.isEmpty {
                        Text(capture.previewDescription).font(.system(size: 13)).foregroundStyle(Palette.muted).lineLimit(3)
                    }
                    if let indexedTextMatch {
                        Label(indexedTextMatch, systemImage: "text.viewfinder")
                            .font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(2)
                            .accessibilityLabel("Matched recognized text: \(indexedTextMatch)")
                    }
                }.multilineTextAlignment(.leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel("Open \(capture.title), \(capture.isTask ? "task" : captureTypeLabel(capture.kind)), saved \(prettyDay(capture.captureDay)) at \(captureClock(capture))")
            if !capture.isMinimized {
                if !capture.comment.isEmpty {
                    Label(capture.comment, systemImage: "text.bubble")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted).lineLimit(2)
                }
                if let reminder = capture.reminderAt {
                    Label(reminder.formatted(date: .abbreviated, time: .shortened), systemImage: capture.isCompleted ? "bell.slash" : "clock")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(taskColor).lineLimit(1)
                }
                if !attachments.isEmpty {
                    Label("\(attachments.count) attachments", systemImage: "paperclip")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                if let project = capture.projectName {
                    Label(project, systemImage: "folder").font(.system(size: 11)).foregroundStyle(accent).lineLimit(1)
                }
                if let parentID = capture.parentTaskID {
                    Button { state.openCapture(parentID, focus: "task") } label: { Label("Task attachment", systemImage: "arrow.turn.up.left") }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(accent)
                }
                HStack(spacing: 2) {
                    BuddyIconButton(symbol: "text.bubble", title: "Comment") { state.openCapture(capture.id, focus: "comment") }
                    BuddyIconButton(symbol: "clock", title: "Reminder") { state.openCapture(capture.id, focus: "reminder") }
                    if capture.isTask {
                        BuddyIconButton(symbol: "paperclip", title: "Add task attachments") { state.openCapture(capture.id, focus: "task") }
                    } else {
                        CaptureTaskConversionButton(state: state, capture: capture)
                    }
                    Spacer(minLength: 0)
                    BuddyIconButton(symbol: "chevron.up", title: "Minimize capture") { state.toggleMinimized(capture) }
                    CaptureControls(state: state, capture: capture)
                }
            } else {
                HStack {
                    Spacer(minLength: 0)
                    BuddyIconButton(symbol: "chevron.down", title: "Expand capture") { state.toggleMinimized(capture) }
                    CaptureControls(state: state, capture: capture)
                }
            }
        }
        .padding(embeddedInCard ? 4 : 13)
        .background {
            if !embeddedInCard {
                RoundedRectangle(cornerRadius: 16).fill(Palette.surface)
                if capture.isTask { RoundedRectangle(cornerRadius: 16).fill(taskColor.opacity(capture.isCompleted ? 0.035 : 0.055)) }
            }
        }
        .overlay {
            if !embeddedInCard {
                RoundedRectangle(cornerRadius: 16).strokeBorder(dropTargeted ? accent : capture.isTask ? taskColor.opacity(0.40) : Palette.line, lineWidth: dropTargeted ? 1.5 : 0.7)
            }
        }
        .padding(.vertical, embeddedInCard ? 0 : 6)
        .contextMenu { CaptureActionMenuItems(state: state, capture: capture) }
        .onDrop(of: TaskAttachmentTypes.identifiers, isTargeted: $dropTargeted) { providers in
            guard capture.isTask else { return false }
            return state.receiveTaskAttachments(providers, to: capture)
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

@MainActor
struct CaptureControls: View {
    @Environment(\.daBinAccent) private var accent
    @ObservedObject var state: AppState
    @ObservedObject var capture: Capture

    var body: some View {
        Menu { CaptureActionMenuItems(state: state, capture: capture) } label: {
            Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold)).frame(width: 28, height: 32)
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().foregroundStyle(accent).buddyHelp("More capture actions")
            .accessibilityLabel("More actions for \(capture.title)")
            .disabled(state.removingCaptureID == capture.id)
    }
}

@MainActor
private struct CaptureActionMenuItems: View {
    @ObservedObject var state: AppState
    @ObservedObject var capture: Capture
    var body: some View {
        Button("Open capture", systemImage: "arrow.up.forward.square") { state.openCapture(capture.id) }
        Button(capture.comment.isEmpty ? "Add note" : "Edit note", systemImage: "text.bubble") { state.openCapture(capture.id, focus: "comment") }
        Button(capture.reminderAt == nil ? "Add reminder" : "Edit reminder", systemImage: "bell") { state.openCapture(capture.id, focus: "reminder") }
        Button(capture.isPinned ? "Unpin" : "Pin", systemImage: capture.isPinned ? "pin.slash" : "pin") { state.togglePinned(capture) }
        Button("Set project…", systemImage: "folder") { state.openCapture(capture.id, focus: "project") }
        CaptureTaskConversionMenu(state: state, capture: capture)
        if capture.isTask {
            Button(capture.isCompleted ? "Mark incomplete" : "Complete task", systemImage: "checkmark.circle") { state.toggleTaskCompletion(capture) }
        }
        Divider()
        Button(capture.isMinimized ? "Expand capture" : "Minimize capture", systemImage: capture.isMinimized ? "chevron.down" : "chevron.up") { state.toggleMinimized(capture) }
        Button("Show capture day", systemImage: "calendar") { state.showCaptureDay(capture) }
        Button("Move to Recently Deleted", systemImage: "trash", role: .destructive) { state.requestRemoval(capture) }
    }
}

@MainActor
struct CaptureTaskConversionButton: View {
    @Environment(\.daBinAccent) private var accent
    @ObservedObject var state: AppState
    @ObservedObject var capture: Capture
    var body: some View {
        BuddyIconButton(symbol: "checkmark.circle", title: "Turn into task") { state.convertToTask(capture) }
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
    private var color: Color { capture.isCompleted ? Palette.completed : Palette.task }
    private var label: String { capture.isCompleted ? "Completed" : "Task" }
    var body: some View {
        Button { state.toggleTaskCompletion(capture) } label: {
            Label(label, systemImage: capture.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(color)
                .padding(.horizontal, 8).padding(.vertical, 5).background(color.opacity(0.1), in: Capsule())
                .contentShape(Capsule())
        }.buttonStyle(.plain).buddyHelp(capture.isCompleted ? "Mark incomplete" : "Mark completed")
            .accessibilityLabel("\(label): \(capture.title)")
            .accessibilityHint(capture.isCompleted ? "Mark this task incomplete" : "Mark this task completed")
            .accessibilityValue(label).accessibilityIdentifier("capture-task-status-\(capture.id.uuidString)")
    }
}
