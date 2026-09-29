import SwiftUI

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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let isMatch {
                Text(isMatch ? "Match" : "Nearby capture").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isMatch ? accent : Palette.muted)
            }
            Button { state.openCapture(capture.id) } label: {
                HStack(alignment: .top, spacing: 10) {
                    if !capture.isMinimized && capture.kind != .text && capture.kind != .task {
                        CaptureThumbnail(store: state.store, capture: capture)
                            .frame(width: 48, height: 52).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            if capture.isPinned {
                                Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(accent)
                                    .accessibilityLabel("Pinned")
                            }
                            Text(capture.title.isEmpty ? "Untitled capture" : capture.title)
                                .strikethrough(capture.isTask && capture.isCompleted, color: Palette.muted)
                                .font(.system(size: 14, weight: .medium)).lineLimit(capture.isMinimized ? 1 : 3)
                                .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if !capture.isMinimized && !capture.previewDescription.isEmpty {
                            Text(capture.previewDescription).font(.system(size: 12)).foregroundStyle(Palette.muted)
                                .lineLimit(2).multilineTextAlignment(.leading)
                        }
                        if let indexedTextMatch {
                            Label(indexedTextMatch, systemImage: "text.viewfinder")
                                .font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .accessibilityLabel("Matched recognized text: \(indexedTextMatch)")
                        }
                    }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel("Open \(capture.title), \(capture.isTask ? "task" : captureTypeLabel(capture.kind)), saved \(prettyDay(capture.captureDay)) at \(captureClock(capture))")

            if !capture.comment.isEmpty {
                Label(capture.comment, systemImage: "text.bubble")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).lineLimit(2)
            }
            if let reminder = capture.reminderAt {
                Label("\(capture.isTask && capture.isCompleted ? "Paused" : "Remind") \(reminder.formatted(date: .abbreviated, time: .shortened))", systemImage: "bell")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(2)
            }
            if let project = capture.projectName {
                Label(project, systemImage: "folder").font(.system(size: 11)).foregroundStyle(accent).lineLimit(1)
            }
            HStack(spacing: 9) {
                Text(metadata).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
                Spacer(minLength: 0)
                if showsCopyButton {
                    Button {
                        guard state.copyCapturesToClipboard([capture]) else { return }
                        copied = true
                        copyGeneration &+= 1
                        let generation = copyGeneration
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(1.25))
                            guard generation == copyGeneration else { return }
                            copied = false
                        }
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(accent)
                        .accessibilityLabel("Copy \(capture.title)")
                        .accessibilityIdentifier(CaptureCopyButton.accessibilityIdentifier(for: [capture]))
                }
                CaptureControls(state: state, capture: capture)
            }
        }
        .padding(.vertical, capture.isMinimized ? 9 : 12).padding(.horizontal, embeddedInCard ? 0 : 11)
        .background {
            if !embeddedInCard { RoundedRectangle(cornerRadius: 12).fill(Palette.surface) }
        }
        .overlay {
            if !embeddedInCard { RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.line, lineWidth: 0.75) }
        }
        .padding(.vertical, embeddedInCard ? 0 : 5)
        .contextMenu { CaptureActionMenuItems(state: state, capture: capture) }
    }

    private var metadata: String {
        let kind = capture.isTask ? (capture.isCompleted ? "Completed" : "Task") : (captureLinkHost(capture) ?? captureTypeLabel(capture.kind))
        return showsDate ? "\(prettyDay(capture.captureDay, includeWeekday: false)) · \(kind)" : "\(captureClock(capture)) · \(kind)"
    }
}

@MainActor
struct CaptureControls: View {
    @Environment(\.daBinAccent) private var accent
    @ObservedObject var state: AppState
    @ObservedObject var capture: Capture

    var body: some View {
        Menu { CaptureActionMenuItems(state: state, capture: capture) } label: {
            Text("More").font(.system(size: 11))
        }.menuStyle(.borderlessButton).fixedSize().foregroundStyle(accent)
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
        Button { state.convertToTask(capture) } label: {
            Label("Turn into task", systemImage: "checkmark.circle").font(.system(size: 12, weight: .medium))
        }.buttonStyle(.plain).foregroundStyle(accent)
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
        }.buttonStyle(.plain).help(capture.isCompleted ? "Mark incomplete" : "Mark completed")
            .accessibilityLabel("\(label): \(capture.title)")
            .accessibilityHint(capture.isCompleted ? "Mark this task incomplete" : "Mark this task completed")
            .accessibilityValue(label).accessibilityIdentifier("capture-task-status-\(capture.id.uuidString)")
    }
}
