import SwiftUI

/// Today contributes its planning actions to the shared card's bottom row.
/// Keeping one card surface avoids nested padding and preserves the same
/// completion, project, copy, attachment and context-menu behavior everywhere.
@MainActor
struct TodayTaskCard: View {
    @ObservedObject var state: AppState
    @ObservedObject var capture: Capture
    var reorderIndex: Int? = nil
    var reorderCount = 0
    var onMove: (Int, Int) -> Void = { _, _ in }
    @Environment(\.daBinAccent) private var accent

    private var todayKey: String { CaptureCalendar.dayString(Date()) }
    private var plannedToday: Bool { capture.taskPlanning?.plannedDay == todayKey }

    var body: some View {
        CaptureRow(state: state, capture: capture, featured: false,
                   planningActions: AnyView(planningActions), planningMetadata: planningMetadata)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("today-task-card-\(capture.id.uuidString)")
    }

    @ViewBuilder private var planningActions: some View {
        if !capture.isCompleted {
            HStack(spacing: 4) {
                if capture.isTask {
                    action(plannedToday ? "Tomorrow" : "Today", symbol: "calendar.badge.clock",
                           help: plannedToday ? "Move this task to tomorrow" : "Plan this task for today",
                           identifier: "today-plan-day-\(capture.id.uuidString)") {
                        schedule(offset: plannedToday ? 1 : 0)
                    }
                    action("Plan", symbol: "slider.horizontal.3", help: "Plan priority, deadline and next steps",
                           identifier: "today-plan-task-\(capture.id.uuidString)") {
                        state.openCapture(capture.id, focus: "task")
                    }
                } else {
                    action("Done", symbol: "checkmark", help: "Complete this follow-up",
                           identifier: "today-follow-up-done-\(capture.id.uuidString)") {
                        state.completeFollowUp(capture)
                    }
                    action("Tomorrow", symbol: "calendar.badge.clock", help: "Snooze this follow-up until tomorrow",
                           identifier: "today-follow-up-tomorrow-\(capture.id.uuidString)") {
                        state.snoozeFollowUp(capture)
                    }
                }
                if let index = reorderIndex {
                    BuddyIconButton(symbol: "arrow.up", title: "Move task up: \(capture.title)") { onMove(index, -1) }
                        .disabled(index == 0).accessibilityIdentifier("today-move-up-\(capture.id.uuidString)")
                    BuddyIconButton(symbol: "arrow.down", title: "Move task down: \(capture.title)") { onMove(index, 1) }
                        .disabled(index == reorderCount - 1).accessibilityIdentifier("today-move-down-\(capture.id.uuidString)")
                }
            }.fixedSize(horizontal: true, vertical: false)
        }
    }

    private func action(_ title: String, symbol: String, help: String,
                        identifier: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .medium)).lineLimit(1)
                .padding(.horizontal, 7).frame(minHeight: 32)
                .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).foregroundStyle(accent)
            .accessibilityLabel(title).accessibilityHint(help)
            .accessibilityIdentifier(identifier).buddyHelp(help)
    }

    private var planningMetadata: AnyView? {
        let deadline = capture.taskPlanning?.deadline
        let plannedDay = capture.taskPlanning?.plannedDay
        let displayedDay = plannedDay != todayKey ? plannedDay : nil
        guard deadline != nil || displayedDay != nil else { return nil }
        return AnyView(
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { metadataLabels(deadline: deadline, day: displayedDay) }
                VStack(alignment: .leading, spacing: 4) { metadataLabels(deadline: deadline, day: displayedDay) }
            }
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("today-planning-metadata-\(capture.id.uuidString)")
        )
    }

    @ViewBuilder private func metadataLabels(deadline: Date?, day: String?) -> some View {
        if let deadline {
            Label("Due \(deadline.formatted(date: .abbreviated, time: .omitted))", systemImage: "flag")
                .lineLimit(1).fixedSize()
                .accessibilityLabel("Due \(deadline.formatted(date: .abbreviated, time: .omitted))")
                .accessibilityIdentifier("today-task-deadline-\(capture.id.uuidString)")
        }
        if let day {
            Label(prettyDay(day), systemImage: "calendar")
                .lineLimit(1).fixedSize()
                .accessibilityLabel("Planned for \(prettyDay(day))")
                .accessibilityIdentifier("today-task-planned-day-\(capture.id.uuidString)")
        }
    }

    private func schedule(offset: Int) {
        guard let day = Calendar.current.date(byAdding: .day, value: offset, to: Date()) else { return }
        state.scheduleTask(capture, day: CaptureCalendar.dayString(day), time: capture.taskPlanning?.plannedTime)
    }
}
