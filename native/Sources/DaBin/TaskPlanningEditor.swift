import SwiftUI

/// Priority is readable without interpreting a symbol or relying on color alone.
struct TaskPriorityTag: View {
    @Environment(\.workspaceZoom) private var zoom
    let priority: TaskPriority
    var isSelected = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var color: Color {
        let dark = colorScheme == .dark
        switch priority {
        case .none: return Palette.muted
        case .low: return dark ? Color(red: 0.49, green: 0.80, blue: 0.59) : Color(red: 0.13, green: 0.43, blue: 0.24)
        case .medium: return dark ? Color(red: 1.0, green: 0.73, blue: 0.28) : Color(red: 0.55, green: 0.31, blue: 0.01)
        case .high: return dark ? Color(red: 1.0, green: 0.55, blue: 0.51) : Color(red: 0.71, green: 0.16, blue: 0.14)
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            if priority != .none { Circle().fill(color).frame(width: 6, height: 6).accessibilityHidden(true) }
            Text(priority.title).font(.system(size: zoom.fontSize(11), weight: .semibold)).lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 4).fixedSize()
        .foregroundStyle(color)
        .background(color.opacity(isSelected ? 0.20 : 0.10), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(isSelected || contrast == .increased ? 1 : 0.35),
                                       lineWidth: isSelected ? 1.5 : 0.75))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(priority == .none ? priority.title : "\(priority.title) priority")
    }
}

/// Observe the task so saving a changed priority updates every mounted card.
@MainActor
struct CaptureTaskPriorityTag: View {
    @ObservedObject var capture: Capture

    var body: some View {
        if capture.isTask, let priority = capture.taskPlanning?.priority, priority != .none {
            TaskPriorityTag(priority: priority)
                .accessibilityIdentifier("task-priority-tag-\(capture.id.uuidString)")
        }
    }
}

/// A draft editor shared by new tasks and captured-content tasks. Its host
/// commits the whole draft, so changing a deadline never silently sets a reminder.
@MainActor
struct TaskPlanningEditor: View {
    @Binding var planning: TaskPlanning
    var showsSchedule: Bool
    var showsFocusDuration: Bool
    @Environment(\.daBinAccent) private var accent
    private let pendingChecklistText: Binding<String>?
    @State private var standaloneChecklistText = ""
    @FocusState private var checklistFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var checklistText: Binding<String> { pendingChecklistText ?? $standaloneChecklistText }
    private var trimmedChecklistText: String { checklistText.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canAddChecklistItem: Bool {
        !trimmedChecklistText.isEmpty && trimmedChecklistText.count <= 500 && planning.checklist.count < 100
    }

    init(planning: Binding<TaskPlanning>, pendingChecklistText: Binding<String>? = nil,
         showsSchedule: Bool = true, showsFocusDuration: Bool = true) {
        self.showsSchedule = showsSchedule
        self.showsFocusDuration = showsFocusDuration
        _planning = planning
        self.pendingChecklistText = pendingChecklistText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if showsSchedule {
            BuddyActionFlow(spacing: 6) {
                Text("Work on").foregroundStyle(Palette.muted).frame(minHeight: 32)
                dayButton("Today", offset: 0)
                dayButton("Tomorrow", offset: 1)
                Button("Unplanned") { planning.plannedDay = nil; planning.plannedTime = nil; planning.order = nil }
                    .buttonStyle(.plain).padding(.horizontal, 5).frame(minHeight: 32)
                    .background(planning.plannedDay == nil ? accent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                    .accessibilityLabel("Move task to Inbox without a planned day")
                    .accessibilityIdentifier("task-plan-enabled")
            }
            if planning.plannedDay != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { plannedDateField; plannedTimeField }
                    VStack(alignment: .leading, spacing: 5) { plannedDateField; plannedTimeField }
                }
            }
            }
            BuddyActionFlow(spacing: 5) {
                Text("Priority").foregroundStyle(Palette.muted).frame(minHeight: 32)
                ForEach(TaskPriority.allCases) { priority in
                    Button { planning.priority = priority } label: {
                        TaskPriorityTag(priority: priority, isSelected: planning.priority == priority)
                            .frame(minHeight: 32).contentShape(Capsule())
                    }.buttonStyle(.plain)
                        .accessibilityLabel(priority == .none ? priority.title : "\(priority.title) priority")
                        .accessibilityIdentifier("task-priority-choice-\(priority.rawValue)")
                        .accessibilityAddTraits(planning.priority == priority ? .isSelected : [])
                        .buddyHelp(priority.title)
                }
            }.accessibilityElement(children: .contain).accessibilityIdentifier("task-priority")
            planningDetails
            if showsFocusDuration {
                HStack(spacing: 8) {
                    Text("Focus").foregroundStyle(Palette.muted)
                    Spacer(minLength: 0)
                    if planning.effortMinutes == nil {
                        ForEach([25, 45, 60], id: \.self) { value in
                            Button("\(value)m") { planning.effortMinutes = value }
                                .buttonStyle(.bordered).controlSize(.small).frame(minHeight: 32)
                                .accessibilityLabel("Set focus duration to \(value) minutes")
                        }
                    } else {
                        Button("Clear", systemImage: "xmark") { planning.effortMinutes = nil }
                            .buttonStyle(.plain).frame(minHeight: 32).foregroundStyle(Palette.muted)
                            .accessibilityLabel("Clear focus duration")
                    }
                }
                if planning.effortMinutes != nil { TaskDurationDraftFields(minutes: effort) }
            }
            checklistSection
        }.font(.system(size: 12)).padding(10)
            .background(Palette.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(accent.opacity(0.17), lineWidth: 0.8))
            .accessibilityElement(children: .contain).accessibilityLabel("Work plan")
    }

    private var plannedDateField: some View {
                DatePicker("Work on", selection: plannedDate, displayedComponents: .date)
                    .datePickerStyle(.field).controlSize(.small).accessibilityIdentifier("task-planned-day")
    }

    private var plannedTimeField: some View {
                TextField("Time (optional)", text: plannedTime).textFieldStyle(.roundedBorder).frame(width: 106)
                        .accessibilityLabel("Optional planned local time in HH:MM")
                    .buddyHelp("Optional local work time, HH:MM")
    }

    private var planningDetails: some View {
        VStack(alignment: .leading, spacing: 6) {
            BuddyActionFlow(spacing: 6) {
                if planning.deadline == nil {
                    Button { planning.deadline = Date().addingTimeInterval(3_600) } label: {
                        Label("Add deadline", systemImage: "flag")
                            .padding(.horizontal, 8).frame(minHeight: 32).contentShape(RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain).foregroundStyle(Palette.muted)
                        .background(Palette.soft, in: RoundedRectangle(cornerRadius: 7))
                        .accessibilityIdentifier("task-deadline-add")
                        .buddyHelp("Choose when this task must be finished")
                } else {
                    Label("Deadline", systemImage: "flag").foregroundStyle(Palette.muted)
                        .padding(.horizontal, 8).frame(minHeight: 32, alignment: .leading)
                }
                Menu {
                    ForEach(TaskRecurrence.allCases) { recurrence in
                        Button { planning.recurrence = recurrence } label: {
                            if planning.recurrence == recurrence { Label(recurrence.title, systemImage: "checkmark") }
                            else { Text(recurrence.title) }
                        }.accessibilityIdentifier("task-recurrence-choice-" + recurrence.rawValue)
                    }
                } label: {
                    Label(planning.recurrence == .none ? "No repeat" : planning.recurrence.title, systemImage: "repeat")
                        .lineLimit(1).padding(.horizontal, 8).frame(minHeight: 32)
                }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                    .foregroundStyle(planning.recurrence == .none ? Palette.muted : accent)
                    .background(Palette.soft, in: RoundedRectangle(cornerRadius: 7))
                    .accessibilityLabel("Repeat: " + planning.recurrence.title).accessibilityIdentifier("task-recurrence")
            }
            if planning.deadline != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { deadlineField; removeDeadline }
                    VStack(alignment: .leading, spacing: 4) { deadlineField; removeDeadline }
                }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("task-planning-details")
    }

    private var deadlineField: some View {
                DatePicker("Finish by", selection: deadlineDate, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.field).controlSize(.small).accessibilityIdentifier("task-deadline")
                    .buddyHelp("Finish-by date; separate from work time and reminders")
    }

    private var removeDeadline: some View {
        Button { planning.deadline = nil } label: {
            Image(systemName: "xmark").frame(width: 32, height: 32).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(Palette.muted)
            .accessibilityLabel("Remove deadline").accessibilityIdentifier("task-deadline-remove")
            .buddyHelp("Remove deadline")
    }

    private var checklistSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack {
                Label("Steps", systemImage: "checklist").font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                if !planning.checklist.isEmpty {
                    Text("\(planning.checklist.filter(\.isCompleted).count)/\(planning.checklist.count)")
                        .font(.system(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(accent)
                        .padding(.horizontal, 7).padding(.vertical, 3).background(accent.opacity(0.10), in: Capsule())
                }
            }
            HStack(spacing: 6) {
                TextField("Add a next step", text: checklistText)
                    .textFieldStyle(.plain).onSubmit(addChecklistItem).focused($checklistFocused)
                    .padding(.horizontal, 8).frame(minHeight: 32)
                    .background(Palette.soft, in: RoundedRectangle(cornerRadius: 7))
                    .accessibilityIdentifier("task-checklist-new")
                    .accessibilityLabel("New checklist step")
                Button(action: addChecklistItem) { Label("Add step", systemImage: "plus").frame(minHeight: 32) }
                    .buttonStyle(.plain).foregroundStyle(accent).disabled(!canAddChecklistItem)
                    .accessibilityLabel("Add checklist step").buddyHelp("Add step, or press Return")
                    .accessibilityIdentifier("task-checklist-add")
            }
            if !planning.checklist.isEmpty {
                ProgressView(value: Double(planning.checklist.filter(\.isCompleted).count), total: Double(planning.checklist.count))
                    .tint(accent).controlSize(.small)
                    .accessibilityLabel("Checklist progress")
                    .accessibilityValue("\(planning.checklist.filter(\.isCompleted).count) of \(planning.checklist.count) complete")
            }
            ForEach($planning.checklist) { $item in
                HStack(alignment: .top, spacing: 5) {
                    Toggle(item.text, isOn: $item.isCompleted).labelsHidden().toggleStyle(.checkbox)
                        .frame(width: 32, height: 32).contentShape(Rectangle())
                        .accessibilityLabel("Complete checklist step: \(item.text)")
                        .accessibilityIdentifier("task-checklist-complete-" + item.id.uuidString)
                    TextField("Step", text: $item.text, axis: .vertical).lineLimit(1...3).textFieldStyle(.plain)
                        .frame(minHeight: 32).foregroundStyle(item.isCompleted ? Palette.muted : Palette.foreground)
                        .strikethrough(item.isCompleted)
                        .accessibilityLabel("Checklist step")
                        .accessibilityIdentifier("task-checklist-text-" + item.id.uuidString)
                    Button { let id = item.id; planning.checklist.removeAll { $0.id == id } } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .medium))
                            .frame(width: 32, height: 32).contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(Palette.muted)
                        .accessibilityLabel("Remove checklist step: \(item.text)")
                        .accessibilityIdentifier("task-checklist-remove-" + item.id.uuidString)
                        .buddyHelp("Remove step")
                }.padding(.horizontal, 3).background(item.isCompleted ? accent.opacity(0.035) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
            }
            if trimmedChecklistText.count > 500 {
                Text("Keep this step within 500 characters (\(trimmedChecklistText.count)/500).")
                    .font(.system(size: 11)).foregroundStyle(Palette.task)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("task-checklist-input-error")
            } else if planning.checklist.count >= 100 {
                Text("This checklist has 100 steps. Remove a step before adding another.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("task-checklist-input-error")
            }
            if !planning.isValid {
                Text("Check the local time (HH:MM), duration (1 minute–168 hours) and checklist steps (1–500 characters).")
                    .font(.system(size: 11)).foregroundStyle(Palette.task).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func dayButton(_ title: String, offset: Int) -> some View {
        Button(title) {
            let date = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
            planning.plannedDay = CaptureCalendar.dayString(date)
            planning.order = nil
        }.buttonStyle(.plain).padding(.horizontal, 6).frame(minHeight: 32)
            .background(planning.plannedDay == CaptureCalendar.dayString(Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()) ? accent.opacity(0.12) : Palette.soft,
                        in: RoundedRectangle(cornerRadius: 7))
            .accessibilityLabel("Plan task for \(title.lowercased())")
            .accessibilityIdentifier("task-plan-" + title.lowercased())
    }

    private var plannedDate: Binding<Date> {
        Binding(get: { planning.plannedDay.flatMap { TaskPlanningPolicy.date(for: $0) } ?? Date() }, set: {
            planning.plannedDay = CaptureCalendar.dayString($0)
            planning.order = nil
        })
    }
    private var plannedTime: Binding<String> {
        Binding(get: { planning.plannedTime ?? "" }, set: { planning.plannedTime = $0.isEmpty ? nil : $0 })
    }
    private var deadlineDate: Binding<Date> {
        Binding(get: { planning.deadline ?? Date() }, set: { planning.deadline = $0 })
    }
    private var effort: Binding<Int> {
        Binding(get: { planning.effortMinutes ?? 30 }, set: { planning.effortMinutes = $0 })
    }
    private func addChecklistItem() {
        guard canAddChecklistItem else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.12)) {
            planning.checklist.append(TaskChecklistItem(text: trimmedChecklistText))
        }
        checklistText.wrappedValue = ""
        checklistFocused = true
    }
}


/// New-task duration entry keeps hours and minutes readable without truncating
/// invalid edits. Validation blocks save until the whole positive duration fits.
@MainActor
struct TaskDurationDraftFields: View {
    @Binding var minutes: Int
    @State private var hoursText: String
    @State private var minutesText: String
    init(minutes: Binding<Int>) {
        _minutes = minutes
        _hoursText = State(initialValue: String(max(0, minutes.wrappedValue) / 60))
        _minutesText = State(initialValue: String(max(0, minutes.wrappedValue) % 60))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                field("Hours", text: $hoursText)
                Text(":").font(.system(size: 16, design: .monospaced)).foregroundStyle(Palette.muted)
                field("Minutes", text: $minutesText)
            }
            BuddyActionFlow(spacing: 6) {
                ForEach([25, 45, 60], id: \.self) { value in
                    Button("\(value)m") { hoursText = String(value / 60); minutesText = String(value % 60); update() }
                        .buttonStyle(.plain).padding(.horizontal, 7).frame(minHeight: 32)
                        .background(Palette.soft, in: RoundedRectangle(cornerRadius: 7))
                }
            }
        }.onChange(of: hoursText) { _, _ in update() }.onChange(of: minutesText) { _, _ in update() }
    }
    private func field(_ title: String, text: Binding<String>) -> some View {
        HStack(spacing: 5) {
            TextField(title, text: text).font(.system(size: 16, design: .monospaced)).textFieldStyle(.roundedBorder)
                .frame(width: 50).accessibilityLabel("Focus duration \(title.lowercased())")
            Text(title.lowercased()).font(.system(size: 11)).foregroundStyle(Palette.muted)
        }
    }
    private func update() {
        guard let hours = Int(hoursText), let part = Int(minutesText),
              let duration = TaskFocusSession.duration(hours: hours, minutes: part) else { minutes = 0; return }
        minutes = duration
    }
}
