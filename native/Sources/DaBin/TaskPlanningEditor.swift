import SwiftUI

/// A draft editor shared by new tasks and captured-content tasks. Its host
/// commits the whole draft, so changing a deadline never silently sets a reminder.
@MainActor
struct TaskPlanningEditor: View {
    @Binding var planning: TaskPlanning
    var showsSchedule: Bool
    @Environment(\.daBinAccent) private var accent
    @State private var checklistText = ""
    @State private var detailsExpanded: Bool
    private var trimmedChecklistText: String { checklistText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canAddChecklistItem: Bool {
        !trimmedChecklistText.isEmpty && trimmedChecklistText.count <= 500 && planning.checklist.count < 100
    }

    init(planning: Binding<TaskPlanning>, showsSchedule: Bool = true) {
        self.showsSchedule = showsSchedule
        _planning = planning
        let value = planning.wrappedValue
        _detailsExpanded = State(initialValue: value.deadline != nil || value.effortMinutes != nil
            || value.recurrence != .none || !value.checklist.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Work plan", systemImage: "calendar.badge.checkmark")
                .font(.system(size: 13, weight: .semibold)).accessibilityAddTraits(.isHeader)
            if showsSchedule {
            HStack(spacing: 8) {
                dayButton("Today", offset: 0)
                dayButton("Tomorrow", offset: 1)
                Button("Inbox") { planning.plannedDay = nil; planning.plannedTime = nil; planning.order = nil }
                    .buttonStyle(.bordered).controlSize(.small)
                    .accessibilityLabel("Move task to Inbox without a planned day")
            }
            Toggle("Plan a day", isOn: plannedEnabled).toggleStyle(.switch).controlSize(.small)
                .accessibilityIdentifier("task-plan-enabled")
            if planning.plannedDay != nil {
                DatePicker("Work on", selection: plannedDate, displayedComponents: .date)
                    .datePickerStyle(.field).controlSize(.small).accessibilityIdentifier("task-planned-day")
                HStack {
                    Text("Optional local time").foregroundStyle(Palette.muted)
                    TextField("HH:MM", text: plannedTime).textFieldStyle(.roundedBorder).frame(width: 80)
                        .accessibilityLabel("Optional planned local time in HH:MM")
                }
            }
            Text("Plan when to work. A deadline is when it must be finished.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack(spacing: 6) {
                Text("Priority").foregroundStyle(Palette.muted)
                Spacer(minLength: 0)
                ForEach(TaskPriority.allCases) { priority in
                    Button { planning.priority = priority } label: {
                        Image(systemName: priority.symbol).font(.system(size: 15))
                            .frame(width: 32, height: 32)
                            .background(planning.priority == priority ? accent.opacity(0.13) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(planning.priority == priority ? accent : Color.clear, lineWidth: 0.7))
                    }.buttonStyle(.plain).foregroundStyle(planning.priority == priority ? accent : Palette.muted)
                        .accessibilityLabel(priority.title)
                        .accessibilityAddTraits(planning.priority == priority ? .isSelected : [])
                        .buddyHelp(priority.title)
                }
            }.accessibilityIdentifier("task-priority")
            if showsSchedule {
                Toggle("Focus duration", isOn: estimateEnabled).toggleStyle(.switch).controlSize(.small)
                if planning.effortMinutes != nil {
                    TaskDurationDraftFields(minutes: effort)
                }
            }
            checklistSection
            DisclosureGroup("Details & repeat", isExpanded: $detailsExpanded) {
                advancedDetails.padding(.top, 10)
            }.accessibilityIdentifier("task-planning-details")
        }.font(.system(size: 12)).padding(12)
            .background(accent.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(accent.opacity(0.12), lineWidth: 0.7))
    }

    private var advancedDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Deadline", isOn: deadlineEnabled).toggleStyle(.switch).controlSize(.small)
                .accessibilityIdentifier("task-deadline-enabled")
            if planning.deadline != nil {
                DatePicker("Finish by", selection: deadlineDate, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.field).controlSize(.small).accessibilityIdentifier("task-deadline")
            }
            Label("Repeat", systemImage: "repeat").foregroundStyle(Palette.muted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 7)], spacing: 7) {
                ForEach(TaskRecurrence.allCases) { recurrence in
                    Button { planning.recurrence = recurrence } label: {
                        HStack(spacing: 5) {
                            if planning.recurrence == recurrence { Image(systemName: "checkmark") }
                            Text(recurrence.title).font(.system(size: 11)).lineLimit(2)
                        }.frame(maxWidth: .infinity, minHeight: 32).padding(.horizontal, 5)
                            .background(planning.recurrence == recurrence ? accent.opacity(0.12) : Palette.surface, in: RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain).accessibilityLabel(recurrence.title)
                        .accessibilityAddTraits(planning.recurrence == recurrence ? .isSelected : [])
                }
            }.accessibilityIdentifier("task-recurrence")
            if planning.recurrence != .none {
                Text("Completing this task creates one next occurrence. Files stay with the completed occurrence.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var checklistSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            HStack {
                Label("Checklist", systemImage: "checklist").font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
                if !planning.checklist.isEmpty {
                    Text("\(planning.checklist.filter(\.isCompleted).count)/\(planning.checklist.count)")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
            }
            ForEach($planning.checklist) { $item in
                HStack(spacing: 7) {
                    Toggle(item.text, isOn: $item.isCompleted).labelsHidden().toggleStyle(.checkbox)
                        .accessibilityLabel("Complete checklist step: \(item.text)")
                    TextField("Step", text: $item.text).textFieldStyle(.plain)
                        .accessibilityLabel("Checklist step")
                    Button { let id = item.id; planning.checklist.removeAll { $0.id == id } } label: {
                        Image(systemName: "minus.circle")
                    }.buttonStyle(.plain).foregroundStyle(Palette.muted)
                        .accessibilityLabel("Remove checklist step: \(item.text)")
                        .buddyHelp("Remove step")
                }
            }
            HStack(spacing: 7) {
                TextField("Add a small next step", text: $checklistText)
                    .textFieldStyle(.roundedBorder).onSubmit(addChecklistItem)
                    .accessibilityIdentifier("task-checklist-new")
                Button(action: addChecklistItem) { Image(systemName: "plus.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(accent)
                    .disabled(!canAddChecklistItem)
                    .accessibilityLabel("Add checklist step").buddyHelp("Add step")
                    .accessibilityIdentifier("task-checklist-add")
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
        }.buttonStyle(.bordered).controlSize(.small)
            .accessibilityLabel("Plan task for \(title.lowercased())")
    }

    private var plannedEnabled: Binding<Bool> {
        Binding(get: { planning.plannedDay != nil }, set: {
            planning.plannedDay = $0 ? CaptureCalendar.dayString(Date()) : nil
            if !$0 { planning.plannedTime = nil }
            planning.order = nil
        })
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
    private var deadlineEnabled: Binding<Bool> {
        Binding(get: { planning.deadline != nil }, set: { planning.deadline = $0 ? Date().addingTimeInterval(3_600) : nil })
    }
    private var deadlineDate: Binding<Date> {
        Binding(get: { planning.deadline ?? Date() }, set: { planning.deadline = $0 })
    }
    private var estimateEnabled: Binding<Bool> {
        Binding(get: { planning.effortMinutes != nil }, set: { planning.effortMinutes = $0 ? 30 : nil })
    }
    private var effort: Binding<Int> {
        Binding(get: { planning.effortMinutes ?? 30 }, set: { planning.effortMinutes = $0 })
    }
    private func addChecklistItem() {
        guard canAddChecklistItem else { return }
        planning.checklist.append(TaskChecklistItem(text: trimmedChecklistText))
        checklistText = ""
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                field("Hours", text: $hoursText)
                Text(":").font(.system(size: 24, design: .monospaced)).foregroundStyle(Palette.muted)
                field("Minutes", text: $minutesText)
            }
            HStack(spacing: 8) {
                ForEach([25, 45, 60], id: \.self) { value in
                    Button("\(value)m") { hoursText = String(value / 60); minutesText = String(value % 60); update() }
                        .buttonStyle(.bordered).controlSize(.small).frame(minHeight: 32)
                }
            }
        }.onChange(of: hoursText) { _, _ in update() }.onChange(of: minutesText) { _, _ in update() }
    }
    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11)).foregroundStyle(Palette.muted)
            TextField(title, text: text).font(.system(size: 24, design: .monospaced)).textFieldStyle(.roundedBorder)
                .frame(width: 82).accessibilityLabel("Focus duration \(title.lowercased())")
        }
    }
    private func update() {
        guard let hours = Int(hoursText), let part = Int(minutesText),
              let duration = TaskFocusSession.duration(hours: hours, minutes: part) else { minutes = 0; return }
        minutes = duration
    }
}
