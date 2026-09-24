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
    /// Automatic-hour actions already provide their own rounded card surface.
    /// Keep the row content unframed there to avoid a competing nested outline.
    var embeddedInCard = false

    private let cardCornerRadius: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let isMatch {
                Text(isMatch ? "Match" : "Nearby capture")
                    .font(.system(size: 11, weight: isMatch ? .semibold : .regular))
                    .foregroundStyle(isMatch ? accent : Palette.muted)
            }
            if featured && !capture.isMinimized {
                Button { state.openCapture(capture.id) } label: {
                    CaptureThumbnail(store: state.store, capture: capture)
                        .frame(height: 120).clipped().clipShape(RoundedRectangle(cornerRadius: 11))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Open preview for \(capture.title)")
            }
            HStack(alignment: .top, spacing: 11) {
                Button { state.openCapture(capture.id) } label: {
                    HStack(alignment: .top, spacing: 11) {
                        if !capture.isMinimized && !featured && capture.kind != .text && capture.kind != .task {
                            CaptureThumbnail(store: state.store, capture: capture).frame(width: 56, height: 62).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            if taskAtTop {
                                Text("Created \(prettyDay(capture.captureDay))")
                                    .font(.system(size: 11)).foregroundStyle(accent).lineLimit(1)
                            } else if !capture.isMinimized, let host = captureLinkHost(capture) {
                                Text(host).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
                            }
                            Text(capture.title.isEmpty ? "Untitled capture" : capture.title)
                                .strikethrough(capture.isTask && capture.isCompleted, color: Palette.muted)
                                .font(.system(size: featured && !capture.isMinimized ? 19.55 : 16.1, weight: .medium)).lineLimit(capture.isMinimized ? 1 : 3)
                                .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                            if !capture.isMinimized && !capture.previewDescription.isEmpty {
                                Text(capture.previewDescription).font(.system(size: 12)).foregroundStyle(Palette.muted)
                                    .lineLimit(2).multilineTextAlignment(.leading)
                            }
                            if let indexedTextMatch {
                                HStack(alignment: .firstTextBaseline, spacing: 5) {
                                    Image(systemName: "text.viewfinder").foregroundStyle(accent)
                                    Text(indexedTextMatch).foregroundStyle(Palette.muted)
                                        .multilineTextAlignment(.leading)
                                }
                                .font(.system(size: 11)).lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityLabel("Matched recognized text: \(indexedTextMatch)")
                            }
                        }
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel(taskAtTop
                        ? "Open unfinished task \(capture.title), created \(prettyDay(capture.captureDay)) at \(captureClock(capture))"
                        : "Open \(capture.title), captured at \(captureClock(capture))")
                    .accessibilityHint(indexedTextMatch.map { "Matched recognized text: \($0)" } ?? "")
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(captureClock(capture)).font(.system(size: 12.65)).monospacedDigit()
                            .foregroundStyle(Palette.muted)
                        if showsCopyButton {
                            CaptureCopyButton(state: state, captures: [capture])
                        }
                    }
                    if capture.isTask {
                        TaskStatusButton(state: state, capture: capture)
                    } else {
                        Text(captureTypeLabel(capture.kind)).font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }
                }.fixedSize(horizontal: true, vertical: false)
            }
            if !capture.isMinimized && !capture.comment.isEmpty {
                Text(capture.comment).font(.system(size: 12)).foregroundStyle(Palette.muted).lineLimit(2)
            }
            HStack(spacing: 18) {
                Button { state.openCapture(capture.id, focus: "comment") } label: {
                    Label("Comment", systemImage: capture.comment.isEmpty ? "text.bubble" : "text.bubble.fill")
                }.accessibilityLabel("Comment on \(capture.title)")
                Button { state.openCapture(capture.id, focus: "reminder") } label: {
                    Label("Reminder", systemImage: capture.reminderAt == nil ? "bell" : "bell.fill")
                }.accessibilityLabel("Reminder for \(capture.title)")
                Spacer(minLength: 0)
                CaptureControls(state: state, capture: capture)
            }.font(.system(size: 12)).buttonStyle(.plain).foregroundStyle(accent).padding(.vertical, 4)
            if !capture.isMinimized, let reminder = capture.reminderAt {
                Text("\(capture.isTask && capture.isCompleted ? "Paused" : "Remind") \(reminder.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
        }
        .padding(.vertical, capture.isMinimized ? 8 : 12)
        .padding(.horizontal, embeddedInCard ? 0 : 10)
        .background {
            if !embeddedInCard {
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .fill(Palette.surface.opacity(0.42))
            }
        }
        .overlay {
            if !embeddedInCard {
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .strokeBorder(taskAtTop ? accent.opacity(0.7) : Palette.line.opacity(0.88),
                                  lineWidth: taskAtTop ? 1 : 0.75)
            }
        }
        .padding(.vertical, embeddedInCard ? 0 : 6)
        .contextMenu {
            CaptureTaskConversionMenu(state: state, capture: capture)
        }
    }
}

@MainActor
struct CaptureControls: View {
    @Environment(\.daBinAccent) private var accent
    @ObservedObject var state: AppState
    @ObservedObject var capture: Capture

    var body: some View {
        HStack(spacing: 5) {
            Button { state.toggleMinimized(capture) } label: {
                Image(systemName: capture.isMinimized ? "chevron.down" : "chevron.up")
                    .frame(width: 28, height: 26)
                    .background(accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .contentShape(Rectangle())
            }
            .help(capture.isMinimized ? "Expand capture" : "Minimize capture")
            .accessibilityLabel("\(capture.isMinimized ? "Expand" : "Minimize") \(capture.title)")
            Button { state.requestRemoval(capture) } label: {
                Image(systemName: "trash")
                    .frame(width: 28, height: 26)
                    .background(accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .contentShape(Rectangle())
            }
            .help("Remove capture")
            .accessibilityLabel("Remove \(capture.title)")
        }
        .font(.system(size: 11, weight: .medium)).foregroundStyle(accent).buttonStyle(.plain)
        .disabled(state.removingCaptureID == capture.id)
    }
}

@MainActor
struct CaptureTaskConversionButton: View {
    @Environment(\.daBinAccent) private var accent
    @ObservedObject var state: AppState
    @ObservedObject var capture: Capture

    var body: some View {
        Button { state.convertToTask(capture) } label: {
            Label("Turn into task", systemImage: "checkmark.circle")
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(accent.opacity(0.11), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain).foregroundStyle(accent)
        .help("Turn this capture into a task")
        .accessibilityLabel("Turn \(capture.title) into a task")
        .accessibilityHint("Keeps the captured content, comment and reminder")
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
            Button { state.convertToTask(capture) } label: {
                Label("Turn into task", systemImage: "checkmark.circle")
            }
            .help("Turn this capture into a task")
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
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(color.opacity(0.1), in: Capsule())
                .contentShape(Capsule())
        }.buttonStyle(.plain)
            .help(capture.isCompleted ? "Mark as task" : "Mark completed")
            .accessibilityLabel("\(label): \(capture.title)")
            .accessibilityHint(capture.isCompleted ? "Mark this task incomplete" : "Mark this task completed")
            .accessibilityValue(label)
            .accessibilityIdentifier("capture-task-status-\(capture.id.uuidString)")
    }
}
