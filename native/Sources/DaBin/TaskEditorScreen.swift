import SwiftUI

@MainActor
struct NewTaskScreen: View {
    @ObservedObject var state: AppState
    @ObservedObject var draft: NewTaskDraft
    @FocusState private var textFocused: Bool

    private var isEmpty: Bool { draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("What needs doing?", systemImage: "checkmark.square").font(.system(size: 14, weight: .semibold))
                        TextEditor(text: $draft.text)
                            .font(.system(size: 20, weight: .medium, design: .rounded)).scrollContentBackground(.hidden)
                            .padding(8).frame(height: 116).background(Palette.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 11))
                            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Palette.line))
                            .focused($textFocused).accessibilityLabel("Task text")
                            .onChange(of: draft.text) { _, _ in draft.message = nil }
                    }
                    TaskPlanningEditor(planning: $draft.planning)
                    ReminderClockEditor(enabled: $draft.reminderEnabled, mode: $draft.reminderMode,
                        date: $draft.reminderDate, hours: $draft.countdownHours, minutes: $draft.countdownMinutes)
                        .onChange(of: draft.reminderEnabled) { _, _ in draft.message = nil }
                        .onChange(of: draft.reminderMode) { _, _ in draft.message = nil }
                        .onChange(of: draft.reminderDate) { _, _ in draft.message = nil }
                        .onChange(of: draft.countdownHours) { _, _ in draft.message = nil }
                        .onChange(of: draft.countdownMinutes) { _, _ in draft.message = nil }
                    if let message = draft.message {
                        Text(message).font(.system(size: 12)).foregroundStyle(Palette.task)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(.horizontal, 16).padding(.bottom, 14)
            }
            HStack(spacing: 10) {
                Label(state.newTaskProject ?? "Inbox", systemImage: state.newTaskProject == nil ? "tray" : "folder")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(2)
                    .accessibilityLabel("Save task to \(state.newTaskProject ?? "Inbox")")
                    .buddyHelp("Save task to \(state.newTaskProject ?? "Inbox")")
                Spacer(minLength: 0)
                Button("Cancel") { state.cancelNewTask() }.buttonStyle(.bordered)
                Button("Add task") { state.saveNewTask() }.buttonStyle(.borderedProminent)
                    .disabled(isEmpty || !draft.planning.isValid).keyboardShortcut(.return, modifiers: .command)
            }.controlSize(.regular).padding(13)
                .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
        }.onAppear { textFocused = true }
    }
}
