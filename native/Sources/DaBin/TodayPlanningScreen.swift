import SwiftUI

@MainActor
struct TodayPlanningScreen: View {
    @Environment(\.workspaceZoom) private var zoom
    @ObservedObject var state: AppState
    private var scope: String {
        get { state.todayPlanningScope }
        nonmutating set { state.todayPlanningScope = newValue }
    }
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
                Picker("Task view", selection: Binding(get: { scope }, set: { scope = $0 })) {
                    Text("Today").tag("today")
                    Text("Upcoming").tag("later")
                    Text("Completed").tag("done")
                }.pickerStyle(.segmented).accessibilityIdentifier("task-view-scope")
            }.padding(14)
                .daBinTutorialAnchor(.todayControls)
            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: zoom.value(9)) {
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
                }.padding(.horizontal, 14).padding(.bottom, 14).frame(maxWidth: zoom.value(860)).frame(maxWidth: .infinity)
            }.background {
                WorkspaceScrollHistory(anchor: state.workspaceViewport, contextID: "today-" + scope,
                    onAnchor: { state.workspaceViewport = $0 }).allowsHitTesting(false).accessibilityHidden(true)
            }
            .onAppear { if let anchor = state.workspaceViewport { proxy.scrollTo(anchor.itemID, anchor: .top) } }
            .onChange(of: state.navigationRestorationRevision) { _, _ in
                if let anchor = state.workspaceViewport { proxy.scrollTo(anchor.itemID, anchor: .top) }
            }
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
                TodayTaskCard(state: state, capture: capture,
                              reorderIndex: reorderable ? items.firstIndex(where: { $0.id == capture.id }) : nil,
                              reorderCount: items.count,
                              onMove: { index, delta in move(index, by: delta) })
                    .id("capture:" + capture.id.uuidString)
            }
        }
    }
    private func move(_ index: Int, by delta: Int) {
        var ordered = planned
        guard ordered.indices.contains(index), ordered.indices.contains(index + delta) else { return }
        ordered.swapAt(index, index + delta)
        do { try state.store.reorderTasks(ordered, on: todayKey) }
        catch { state.reportFailure(error.localizedDescription) }
    }
}
