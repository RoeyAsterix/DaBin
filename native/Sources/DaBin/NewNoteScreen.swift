import SwiftUI

@MainActor
struct NewNoteScreen: View {
    @ObservedObject var state: AppState
    @FocusState private var textFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Catch a thought").font(.system(size: 13, weight: .medium))
            TextEditor(text: $state.newNoteText).font(.system(size: 14)).scrollContentBackground(.hidden)
                .padding(9).background(Palette.surface, in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Palette.line))
                .focused($textFocused).accessibilityLabel("New note text")
            HStack {
                Label(state.newNoteProject ?? "Inbox", systemImage: state.newNoteProject == nil ? "tray" : "folder")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(2)
                    .accessibilityLabel("Save note to \(state.newNoteProject ?? "Inbox")")
                    .buddyHelp("Save note to \(state.newNoteProject ?? "Inbox")")
                Spacer(minLength: 0)
                Button("Cancel") { state.cancelNewNote() }
                Button("Save note") { state.saveNewNote() }.buttonStyle(.borderedProminent)
                    .disabled(state.newNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }.padding(16).onAppear { textFocused = true }
    }
}
