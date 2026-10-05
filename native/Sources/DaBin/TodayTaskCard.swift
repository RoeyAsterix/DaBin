import SwiftUI

/// A work card has one clear title, a compact summary and a small action rail.
/// Archive operations stay in the shared menu; task timing keeps its existing
/// coordinator, persistence and editor rather than introducing a second flow.
@MainActor
struct TodayTaskCard: View {
    @ObservedObject var state: AppState
    @ObservedObject var capture: Capture
    var reorderIndex: Int? = nil
    var reorderCount = 0
    var onMove: (Int, Int) -> Void = { _, _ in }
    @Environment(\.workspaceZoom) private var zoom
    @Environment(\.daBinAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dropTargeted = false
    @State private var copied = false

    private var plannedToday: Bool { capture.taskPlanning?.plannedDay == state.currentDayKey }
    private var running: Bool { capture.taskPlanning?.focusSession?.isRunning == true && !capture.isCompleted }
    private var checklist: [TaskChecklistItem] { capture.taskPlanning?.checklist ?? [] }
    private var attachments: [Capture] { state.store.attachments(for: capture) }
    private var title: String { capture.title.isEmpty ? "Untitled task" : capture.title }
    private var hasSummary: Bool {
        capture.taskPlanning?.deadline != nil || capture.reminderAt != nil || !checklist.isEmpty
            || !attachments.isEmpty || capture.taskPlanning?.plannedTime != nil
            || (capture.taskPlanning?.plannedDay != nil && !plannedToday)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                completion
                Button { state.openCapture(capture.id, focus: capture.isTask ? "task" : nil) } label: {
                    Text(title)
                        .font(.system(size: zoom.fontSize(15), weight: .semibold))
                        .foregroundStyle(capture.isCompleted ? Palette.muted : Palette.foreground)
                        .strikethrough(capture.isCompleted, color: Palette.muted)
                        .lineLimit(capture.isMinimized ? 1 : 2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, max(0, (32 - zoom.fontSize(15) * 1.2) / 2))
                        .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
                        .multilineTextAlignment(.leading).contentShape(Rectangle())
                }.buttonStyle(.plain).layoutPriority(1)
                    .accessibilityLabel("Open \(title), saved \(prettyDay(capture.captureDay)) at \(captureClock(capture))")
                    .accessibilityIdentifier("\(capture.isTask ? "today-plan-task" : "today-follow-up-open")-\(capture.id.uuidString)")
                    .captureDragSource(state: state, capture: capture).buddyHelp(title)
                more
            }
            CaptureProjectPriorityHeader(state: state, capture: capture)
            if !capture.isMinimized {
                if hasSummary { summary }
                if !capture.comment.isEmpty {
                    Button { state.openCapture(capture.id, focus: "comment") } label: {
                        Text(capture.comment).font(.system(size: zoom.fontSize(11)))
                            .foregroundStyle(Palette.muted).lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityLabel("Comment: \(capture.comment)")
                        .accessibilityIdentifier("capture-comment-\(capture.id.uuidString)")
                        .readableTextDragSource(text: capture.comment, label: "Comment for \(title)", state: state)
                }
                CaptureConversionUndo(state: state, capture: capture)
            }
            if !capture.isCompleted && (!capture.isMinimized || running || !capture.isTask) {
                actionRail
                    .padding(.top, 6)
                    .overlay(alignment: .top) { Rectangle().fill(Palette.line.opacity(0.7)).frame(height: 0.5) }
            }
        }
        .padding(12)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(dropTargeted ? accent : running ? accent.opacity(0.55) : Palette.line,
                              lineWidth: dropTargeted ? 1.5 : running ? 1 : 0.7)
        }
        .workspaceZoomItem("capture:" + capture.id.uuidString)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-task-card-\(capture.id.uuidString)")
        .contextMenu { menuItems }
        .onDrop(of: TaskAttachmentTypes.identifiers, isTargeted: $dropTargeted) { providers in
            guard capture.isTask else { return false }
            return state.receiveTaskAttachments(providers, to: capture)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: capture.isCompleted)
    }

    private var completion: some View {
        Button {
            if capture.isTask { state.toggleTaskCompletion(capture) }
            else { state.completeFollowUp(capture) }
        } label: {
            ZStack {
                Circle().fill(capture.isCompleted ? accent : Color.clear)
                Circle().strokeBorder(capture.isCompleted ? accent : Palette.muted.opacity(0.7), lineWidth: 1.4)
                if capture.isCompleted || !capture.isTask {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(capture.isCompleted ? Palette.surface : Palette.muted)
                }
            }.frame(width: 21, height: 21).frame(width: 32, height: 32).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel(capture.isTask ? "\(capture.isCompleted ? "Completed" : "Task"): \(title)" : "Complete follow-up: \(title)")
            .accessibilityHint(capture.isTask ? (capture.isCompleted ? "Mark incomplete" : "Mark completed") : "Clear this reminder")
            .accessibilityValue(capture.isCompleted ? "Completed" : "Open")
            .accessibilityIdentifier("\(capture.isTask ? "capture-task-status" : "today-follow-up-done")-\(capture.id.uuidString)")
            .buddyHelp(capture.isCompleted ? "Reopen task" : capture.isTask ? "Complete task" : "Complete follow-up")
    }

    private var summary: some View {
        BuddyActionFlow(spacing: 8) {
            if let deadline = capture.taskPlanning?.deadline {
                Text("Due \(deadline.formatted(date: .abbreviated, time: .omitted))")
                    .foregroundStyle(TaskPlanningPolicy.isOverdue(capture) ? .red : Palette.muted)
                    .lineLimit(1).fixedSize().frame(minHeight: 32)
                    .accessibilityIdentifier("today-task-deadline-\(capture.id.uuidString)")
            }
            if let day = capture.taskPlanning?.plannedDay, !plannedToday {
                Text("Planned \(prettyDay(day))\(capture.taskPlanning?.plannedTime.map { " · \($0)" } ?? "")")
                    .lineLimit(1).fixedSize().frame(minHeight: 32)
                    .accessibilityLabel("Planned for \(prettyDay(day))")
                    .accessibilityIdentifier("today-task-planned-day-\(capture.id.uuidString)")
            } else if let time = capture.taskPlanning?.plannedTime {
                Text("Today \(time)").lineLimit(1).fixedSize().frame(minHeight: 32)
                    .accessibilityLabel("Planned today at \(time)")
                    .accessibilityIdentifier("today-task-planned-time-\(capture.id.uuidString)")
            }
            if !checklist.isEmpty {
                summaryAction("\(checklist.filter(\.isCompleted).count)/\(checklist.count) steps", symbol: "checklist",
                              identifier: "today-task-checklist") { state.openCapture(capture.id, focus: "task") }
            }
            if let reminder = capture.reminderAt {
                summaryAction(reminder.formatted(date: .abbreviated, time: .shortened), symbol: "bell",
                              identifier: "today-task-reminder") { state.openCapture(capture.id, focus: "reminder") }
            }
            if !attachments.isEmpty {
                summaryAction("\(attachments.count) \(attachments.count == 1 ? "file" : "files")", symbol: "paperclip",
                              identifier: "today-task-attachments") { state.openCapture(capture.id, focus: "task") }
            }
        }.font(.system(size: zoom.fontSize(11))).foregroundStyle(Palette.muted)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("today-planning-metadata-\(capture.id.uuidString)")
    }

    private func summaryAction(_ text: String, symbol: String, identifier: String,
                               perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(spacing: 4) {
                Image(systemName: symbol).frame(width: 13)
                Text(text).lineLimit(1)
            }.frame(minHeight: 32).contentShape(Rectangle())
        }.buttonStyle(.plain).fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("\(symbol == "bell" ? "Reminder, " : "")\(text)")
            .accessibilityIdentifier("\(identifier)-\(capture.id.uuidString)")
    }

    private var actionRail: some View {
        ExplorerCaptureActionsLayout { focus; dayAction }.accessibilityElement(children: .contain)
            .accessibilityIdentifier("today-task-action-rail-\(capture.id.uuidString)")
    }

    @ViewBuilder private var focus: some View {
        if capture.isTask {
            TaskFocusControls(state: state, capture: capture, showsSchedule: false, taskCardStyle: true)
        }
    }

    private var dayAction: some View {
        Button {
            if capture.isTask { schedule(offset: plannedToday ? 1 : 0) }
            else { state.snoozeFollowUp(capture) }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "calendar").font(.system(size: 12)).frame(width: 14)
                Text(capture.isTask && !plannedToday ? "Today" : "Tomorrow")
                    .font(.system(size: zoom.fontSize(12), weight: .medium)).lineLimit(1)
            }.padding(.horizontal, 8).frame(height: 32)
                .background(Palette.soft.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).foregroundStyle(Palette.muted).fixedSize()
            .accessibilityLabel(capture.isTask && !plannedToday ? "Today" : "Tomorrow")
            .accessibilityHint(capture.isTask ? "Change the planned workday, keeping deadline and reminder" : "Snooze this follow-up until tomorrow")
            .accessibilityIdentifier("\(capture.isTask ? "today-plan-day" : "today-follow-up-tomorrow")-\(capture.id.uuidString)")
    }

    private var more: some View {
        Menu { menuItems } label: {
            Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold))
                .frame(width: 32, height: 32).contentShape(Rectangle())
        }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .foregroundStyle(Palette.muted).buddyHelp("More task actions")
            .accessibilityLabel("More actions for \(title)")
            .accessibilityIdentifier("capture-more-\(capture.id.uuidString)")
            .disabled(state.removingCaptureID == capture.id)
            .daBinTutorialAnchor(.captureActions)
    }

    @ViewBuilder private var menuItems: some View {
        Text("Captured \(captureReceiptText(capture)) · \(captureTypeLabel(capture.kind))")
        Button(copied ? "Copied" : "Copy \(capture.isTask ? "task" : "capture")", systemImage: "doc.on.doc") {
            if state.copyCapturesToClipboard([capture]) {
                copied = true
                Task { @MainActor in try? await Task.sleep(for: .seconds(1.25)); copied = false }
            }
        }.accessibilityIdentifier(CaptureCopyButton.accessibilityIdentifier(for: [capture]))
        if capture.isTask {
            if !capture.isCompleted {
                Button(plannedToday ? "Move to tomorrow" : "Plan for today", systemImage: "calendar") { schedule(offset: plannedToday ? 1 : 0) }
                Button("Remove from work plan", systemImage: "calendar.badge.minus") { _ = state.scheduleTask(capture, day: nil) }
                    .disabled(capture.taskPlanning?.plannedDay == nil)
                Button("Reset focus", systemImage: "arrow.counterclockwise") { _ = state.resetTaskFocus(capture) }
                    .disabled(capture.taskPlanning?.effortMinutes == nil)
                if let index = reorderIndex {
                    Button("Move up", systemImage: "arrow.up") { onMove(index, -1) }
                        .disabled(index == 0).accessibilityIdentifier("today-move-up-\(capture.id.uuidString)")
                    Button("Move down", systemImage: "arrow.down") { onMove(index, 1) }
                        .disabled(index >= reorderCount - 1).accessibilityIdentifier("today-move-down-\(capture.id.uuidString)")
                }
            }
            Divider()
        } else if capture.reminderAt != nil {
            Button("Snooze until tomorrow", systemImage: "bell.badge") { state.snoozeFollowUp(capture) }
            Divider()
        }
        CaptureActionMenuItems(state: state, capture: capture, includesRemoval: true,
                               openingLabel: capture.isTask ? "Edit task plan" : "Open capture")
    }

    private func schedule(offset: Int) {
        guard let today = TaskPlanningPolicy.date(for: state.currentDayKey),
              let day = Calendar.current.date(byAdding: .day, value: offset, to: today) else { return }
        _ = state.scheduleTask(capture, day: CaptureCalendar.dayString(day), time: capture.taskPlanning?.plannedTime)
    }
}
