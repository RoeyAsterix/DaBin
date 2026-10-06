import SwiftUI

@MainActor
struct TodayPlanningScreen: View {
    @Environment(\.workspaceZoom) private var zoom
    @Environment(\.daBinAccent) private var accent
    @ObservedObject var state: AppState
    private var scope: String {
        get { state.todayPlanningScope }
        nonmutating set { state.todayPlanningScope = newValue }
    }
    private var todayKey: String { state.currentDayKey }
    private var projects: [String] {
        Set(state.projectNames + state.workspace.projectNames).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    private var active: [Capture] {
        state.store.captures.filter { $0.parentTaskID == nil && (state.libraryProject == nil || $0.projectName == state.libraryProject) }
    }
    private var planned: [Capture] { TaskPlanningPolicy.sorted(active.filter { TaskPlanningPolicy.isPlanned($0, for: todayKey) }) }
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
            toolbar
                .padding(.horizontal, 14).padding(.vertical, 8)
                .daBinTutorialAnchor(.todayControls)
            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: zoom.value(9)) {
                    capturedToday
                    if scope == "today" {
                        if planned.isEmpty {
                            Text("Pick a few tasks for today. Deadlines and reminders stay separate.")
                                .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                        }
                        section("Today's plan", items: planned, reorderable: true)
                        section("Needs another look", items: unfinished)
                        section("Reminders", items: dueReminders)
                        section("Unplanned tasks", items: TaskPlanningPolicy.inbox(active).filter { item in !unfinished.contains { $0.id == item.id } })
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
                WorkspaceScrollHistory(anchor: state.workspaceViewport, contextID: "today-" + todayKey + "-" + scope,
                    onAnchor: { state.workspaceViewport = $0 }).allowsHitTesting(false).accessibilityHidden(true)
            }
            .onAppear { if let anchor = state.workspaceViewport { proxy.scrollTo(anchor.itemID, anchor: .top) } }
            .onChange(of: state.navigationRestorationRevision) { _, _ in
                if let anchor = state.workspaceViewport { proxy.scrollTo(anchor.itemID, anchor: .top) }
            }
            }
        }
    }
    private var toolbar: some View {
        HStack(spacing: 6) {
            Menu {
                Button("All projects", systemImage: state.libraryProject == nil ? "checkmark" : "square.stack.3d.up") {
                    state.libraryProject = nil
                }
                ForEach(projects, id: \.self) { project in
                    Button(project, systemImage: state.libraryProject == project ? "checkmark" : "folder") {
                        state.libraryProject = project
                    }
                }
            } label: {
                Image(systemName: "folder").frame(width: 32, height: 32)
                    .background(state.libraryProject == nil ? Color.clear : accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .foregroundStyle(state.libraryProject == nil ? Palette.muted : accent)
                .accessibilityLabel("Work plan project, \(state.libraryProject ?? "all projects")")
                .accessibilityIdentifier("today-project-picker")
                .buddyHelp(state.libraryProject ?? "Show tasks from all projects")
            HStack(spacing: 2) {
                scopeButton("Today", symbol: "sun.max", value: "today")
                scopeButton("Upcoming", symbol: "calendar.badge.clock", value: "later")
                scopeButton("Completed", symbol: "checkmark.circle", value: "done")
            }.fixedSize()
                .accessibilityElement(children: .contain).accessibilityLabel("Task views")
                .accessibilityIdentifier("task-view-scope")
            Text("\(planned.count) planned\(effortLabel)")
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityIdentifier("today-plan-summary")
            BuddyIconButton(symbol: "plus", title: "Add task for today") {
                state.openNewTask(); state.newTaskDraft.planning.plannedDay = todayKey
            }.background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityIdentifier("today-add-task")
        }.font(.system(size: 12))
            .accessibilityElement(children: .contain).accessibilityLabel("Task controls")
            .accessibilityIdentifier("today-toolbar")
    }

    private func scopeButton(_ title: String, symbol: String, value: String) -> some View {
        BuddyIconButton(symbol: symbol, title: title, isActive: scope == value) { scope = value }
            .accessibilityIdentifier("task-view-" + value)
    }

    @ViewBuilder private var capturedToday: some View {
        let receipts = state.currentTodayCaptures
        HStack {
            Text("Captured today").font(.system(size: 12, weight: .semibold))
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("today-receipts-heading")
            Spacer(minLength: 0)
            Text("\(receipts.count) \(receipts.count == 1 ? "item" : "items")").font(.system(size: 11)).foregroundStyle(Palette.muted)
                .accessibilityIdentifier("today-receipts-count")
        }.padding(.top, 8)
        if receipts.isEmpty {
            Text("Drop a file here, paste from the clipboard, or write a note.")
                .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
        } else {
            ForEach(receipts) { capture in
                let itemID = AppState.todayReceiptItemID(capture.id)
                CaptureRow(state: state, capture: capture, featured: false, navigationItemID: itemID, compactReceipt: true)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("today-receipt-card-" + capture.id.uuidString)
                    .id(itemID)
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
