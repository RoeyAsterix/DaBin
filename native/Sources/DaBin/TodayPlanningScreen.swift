import SwiftUI

@MainActor
struct TodayPlanningScreen: View {
    @ObservedObject var state: AppState
    @Environment(\.daBinAccent) private var accent
    @State private var scope = "today"
    private var todayKey: String { CaptureCalendar.dayString(Date()) }
    private var projects: [String] {
        Set(state.projectNames + state.workspace.projectNames).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    private var active: [Capture] {
        state.store.captures.filter { $0.parentTaskID == nil && (state.libraryProject == nil || $0.projectName == state.libraryProject) }
    }
    private var planned: [Capture] { TaskPlanningPolicy.today(active) }
    private var unfinished: [Capture] {
        TaskPlanningPolicy.sorted(active.filter { $0.isTask && !$0.isCompleted
            && (($0.taskPlanning?.plannedDay.map { $0 < todayKey } ?? false) || TaskPlanningPolicy.isOverdue($0))
            && $0.taskPlanning?.plannedDay != todayKey })
    }
    private var later: [Capture] {
        TaskPlanningPolicy.sorted(active.filter { $0.isTask && !$0.isCompleted
            && (($0.taskPlanning?.plannedDay ?? "") > todayKey
                || ($0.taskPlanning?.deadline ?? .distantPast) > Date()
                || ($0.reminderAt ?? .distantPast) > Date()) })
    }
    private var completed: [Capture] {
        active.filter { $0.isTask && $0.isCompleted }.sorted {
            ($0.taskPlanning?.completedAt ?? $0.updatedAt) > ($1.taskPlanning?.completedAt ?? $1.updatedAt)
        }
    }
    private var dueReminders: [Capture] {
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        let taskIDs = Set((planned + unfinished + TaskPlanningPolicy.inbox(active)).map(\.id))
        return active.filter { !$0.isCompleted && ($0.reminderAt.map { $0 < nextDay } ?? false) && !taskIDs.contains($0.id) }
    }
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Make room for what matters").font(.system(size: 14, weight: .semibold))
                    Spacer(minLength: 0)
                    BuddyIconButton(symbol: "plus.circle", title: "Add task for today") {
                        state.openNewTask(); state.newTaskDraft.planning.plannedDay = todayKey
                    }.accessibilityIdentifier("today-add-task")
                }
                HStack {
                    Menu {
                        Button("All projects", systemImage: "square.stack.3d.up") { state.libraryProject = nil }
                        ForEach(projects, id: \.self) { project in Button(project, systemImage: "folder") { state.libraryProject = project } }
                    } label: {
                        Label(state.libraryProject ?? "All projects", systemImage: "folder")
                            .lineLimit(1).truncationMode(.tail)
                    }
                        .menuStyle(.borderlessButton).font(.system(size: 12))
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Project, \(state.libraryProject ?? "all projects")")
                        .accessibilityIdentifier("today-project-picker")
                        .buddyHelp(state.libraryProject ?? "Show tasks from all projects")
                    Spacer(minLength: 0)
                    Text("\(planned.count) planned\(effortLabel)").font(.system(size: 11)).foregroundStyle(Palette.muted)
                        .fixedSize().accessibilityIdentifier("today-plan-summary")
                }
                Picker("Task view", selection: $scope) {
                    Text("Today").tag("today")
                    Text("Upcoming").tag("later")
                    Text("Completed").tag("done")
                }.pickerStyle(.segmented).accessibilityIdentifier("task-view-scope")
            }.padding(14)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 9) {
                    if scope == "today" {
                        if planned.isEmpty {
                            Text("Pick a few tasks for today. Deadlines and reminders stay separate.")
                                .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                        }
                        section("Today's plan", items: planned, reorderable: true)
                        section("Needs another look", items: unfinished)
                        section("Reminders", items: dueReminders)
                        section("Choose from Inbox", items: TaskPlanningPolicy.inbox(active).filter { item in !unfinished.contains { $0.id == item.id } })
                    } else if scope == "later" {
                        section("Coming up", items: later)
                        section("Upcoming reminders", items: active.filter { !$0.isCompleted && ($0.reminderAt ?? .distantPast) > Date() && !$0.isTask })
                        if later.isEmpty { Text("Plan a future workday from a task's details.").font(.system(size: 12)).foregroundStyle(Palette.muted) }
                    } else {
                        section("Completed", items: completed)
                        if completed.isEmpty { Text("Your finished tasks will appear here.").font(.system(size: 12)).foregroundStyle(Palette.muted) }
                    }
                }.padding(.horizontal, 14).padding(.bottom, 14).frame(maxWidth: 860).frame(maxWidth: .infinity)
            }
        }
    }
    private var effortLabel: String {
        let minutes = planned.compactMap { $0.taskPlanning?.effortMinutes }.reduce(0, +)
        return minutes > 0 ? " · \(minutes) min" : ""
    }
    @ViewBuilder private func section(_ title: String, items: [Capture], reorderable: Bool = false) -> some View {
        if !items.isEmpty {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.muted)
                .padding(.top, 8).accessibilityAddTraits(.isHeader)
            ForEach(items) { capture in
                VStack(alignment: .leading, spacing: 5) {
                    CaptureRow(state: state, capture: capture, featured: false, embeddedInCard: true, showsDate: false)
                    if let plan = capture.taskPlanning {
                        HStack(spacing: 8) {
                            if plan.priority != .none { Label(plan.priority.title, systemImage: plan.priority.symbol) }
                            if let due = plan.deadline { Label(due.formatted(date: .abbreviated, time: .omitted), systemImage: "flag") }
                            if let day = plan.plannedDay, day != todayKey { Label(prettyDay(day), systemImage: "calendar") }
                        }.font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }
                    if !capture.isCompleted {
                        HStack(spacing: 12) {
                            if capture.isTask {
                                Button { plan(capture, offset: capture.taskPlanning?.plannedDay == todayKey ? 1 : 0) } label: {
                                    Label(capture.taskPlanning?.plannedDay == todayKey ? "Tomorrow" : "Today", systemImage: "calendar.badge.clock")
                                        .frame(minHeight: 28).contentShape(Rectangle())
                                }
                                Button { state.openCapture(capture.id, focus: "task") } label: {
                                    Label("Plan", systemImage: "slider.horizontal.3").frame(minHeight: 28).contentShape(Rectangle())
                                }
                            } else {
                                Button("Done") { state.completeFollowUp(capture) }
                                Button("Tomorrow") { state.snoozeFollowUp(capture) }
                            }
                            Spacer(minLength: 0)
                            if reorderable, let index = items.firstIndex(where: { $0.id == capture.id }) {
                                BuddyIconButton(symbol: "arrow.up", title: "Move task up: \(capture.title)") { move(index, by: -1) }
                                    .disabled(index == 0).accessibilityIdentifier("today-move-up-\(capture.id.uuidString)")
                                BuddyIconButton(symbol: "arrow.down", title: "Move task down: \(capture.title)") { move(index, by: 1) }
                                    .disabled(index == items.count - 1).accessibilityIdentifier("today-move-down-\(capture.id.uuidString)")
                            }
                        }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(accent)
                    }
                }.padding(16).background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.line, lineWidth: 0.7))
            }
        }
    }
    private func plan(_ task: Capture, offset: Int) {
        guard let day = Calendar.current.date(byAdding: .day, value: offset, to: Date()) else { return }
        state.scheduleTask(task, day: CaptureCalendar.dayString(day), time: task.taskPlanning?.plannedTime)
    }
    private func move(_ index: Int, by delta: Int) {
        var ordered = planned
        guard ordered.indices.contains(index), ordered.indices.contains(index + delta) else { return }
        ordered.swapAt(index, index + delta)
        do { try state.store.reorderTasks(ordered, on: todayKey) }
        catch { state.reportFailure(error.localizedDescription) }
    }
}
