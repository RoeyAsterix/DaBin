import SwiftUI

/// A draft editor shared by new tasks and captured-content tasks. Its host
/// commits the whole draft, so changing a deadline never silently sets a reminder.
@MainActor
struct TaskPlanningEditor: View {
    @Binding var planning: TaskPlanning
    @Environment(\.daBinAccent) private var accent
    @State private var checklistText = ""
    @State private var detailsExpanded: Bool
    private var trimmedChecklistText: String { checklistText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canAddChecklistItem: Bool {
        !trimmedChecklistText.isEmpty && trimmedChecklistText.count <= 500 && planning.checklist.count < 100
    }

    init(planning: Binding<TaskPlanning>) {
        _planning = planning
        let value = planning.wrappedValue
        _detailsExpanded = State(initialValue: value.deadline != nil || value.effortMinutes != nil
            || value.recurrence != .none || !value.checklist.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Work plan", systemImage: "calendar.badge.checkmark")
                .font(.system(size: 13, weight: .semibold)).accessibilityAddTraits(.isHeader)
            HStack(spacing: 8) {
                dayButton("Today", offset: 0)
                dayButton("Tomorrow", offset: 1)
                Button("Inbox") { planning.plannedDay = nil; planning.order = nil }
                    .buttonStyle(.bordered).controlSize(.small)
                    .accessibilityLabel("Move task to Inbox without a planned day")
            }
            Toggle("Plan a day", isOn: plannedEnabled).toggleStyle(.switch).controlSize(.small)
                .accessibilityIdentifier("task-plan-enabled")
            if planning.plannedDay != nil {
                DatePicker("Work on", selection: plannedDate, displayedComponents: .date)
                    .datePickerStyle(.field).controlSize(.small).accessibilityIdentifier("task-planned-day")
            }
            Text("Plan when to work. A deadline is when it must be finished.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            Divider()
            Picker("Priority", selection: $planning.priority) {
                ForEach(TaskPriority.allCases) { priority in
                    Label(priority.title, systemImage: priority.symbol).tag(priority)
                }
            }.pickerStyle(.menu).controlSize(.small).accessibilityIdentifier("task-priority")
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
            Toggle("Estimate effort", isOn: estimateEnabled).toggleStyle(.switch).controlSize(.small)
            if planning.effortMinutes != nil {
                HStack {
                    TextField("Minutes", value: effort, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder).frame(width: 72).accessibilityLabel("Estimated effort in minutes")
                    Text("minutes").foregroundStyle(Palette.muted)
                }
            }
            Picker("Repeat", selection: $planning.recurrence) {
                ForEach(TaskRecurrence.allCases) { recurrence in Text(recurrence.title).tag(recurrence) }
            }.pickerStyle(.menu).controlSize(.small).accessibilityIdentifier("task-recurrence")
            if planning.recurrence != .none {
                Text("Completing this task creates one next occurrence. Files stay with the completed occurrence.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
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
                Text("Use an estimate of 1–10,080 minutes and checklist steps of 1–500 characters.")
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
            planning.order = nil
        })
    }
    private var plannedDate: Binding<Date> {
        Binding(get: { planning.plannedDay.flatMap { TaskPlanningPolicy.date(for: $0) } ?? Date() }, set: {
            planning.plannedDay = CaptureCalendar.dayString($0)
            planning.order = nil
        })
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
