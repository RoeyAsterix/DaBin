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
                        Text("What needs doing?").font(.system(size: 13, weight: .medium))
                        TextEditor(text: $draft.text)
                            .font(.system(size: 14)).scrollContentBackground(.hidden)
                            .padding(8).frame(height: 116).background(Palette.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 11))
                            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Palette.line))
                            .focused($textFocused).accessibilityLabel("Task text")
                            .onChange(of: draft.text) { _, _ in draft.message = nil }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Reminder", isOn: $draft.reminderEnabled)
                            .toggleStyle(.switch).controlSize(.small)
                            .font(.system(size: 13, weight: .medium))
                            .onChange(of: draft.reminderEnabled) { _, _ in draft.message = nil }
                        if draft.reminderEnabled {
                            DatePicker("Remind me", selection: $draft.reminderDate, displayedComponents: [.date, .hourAndMinute])
                                .labelsHidden().datePickerStyle(.field).accessibilityLabel("Task reminder date and time")
                                .onChange(of: draft.reminderDate) { _, _ in draft.message = nil }
                            Text("\(TimeZone.current.identifier) · \(draft.reminderDate.formatted(.dateTime.timeZone(.iso8601(.long))))")
                                .font(.system(size: 11)).foregroundStyle(Palette.muted)
                        }
                    }
                    if let message = draft.message {
                        Text(message).font(.system(size: 12)).foregroundStyle(Palette.task)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(.horizontal, 16).padding(.bottom, 14)
            }
            HStack(spacing: 10) {
                Text("Saved to today").font(.system(size: 11)).foregroundStyle(Palette.muted)
                Spacer(minLength: 0)
                Button("Cancel") { state.cancelNewTask() }.buttonStyle(.bordered)
                Button("Add task") { state.saveNewTask() }.buttonStyle(.borderedProminent)
                    .disabled(isEmpty).keyboardShortcut(.return, modifiers: .command)
            }.controlSize(.regular).padding(13)
                .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
        }.onAppear { textFocused = true }
    }
}
