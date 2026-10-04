import SwiftUI

@MainActor
struct NewNoteScreen: View {
    @Environment(\.workspaceZoom) private var zoom
    @ObservedObject var state: AppState
    @FocusState private var textFocused: Bool
    @Environment(\.daBinAccent) private var accent
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Catch a thought").font(.system(size: zoom.fontSize(20), weight: .semibold, design: .rounded))
                .accessibilityAddTraits(.isHeader)
            TextEditor(text: $state.newNoteText).font(.system(size: zoom.fontSize(14))).lineSpacing(zoom.lineSpacing(4)).scrollContentBackground(.hidden)
                .background(NavigationEditorRegion(target: .newNote))
                .padding(12).frame(minHeight: 80).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.line, lineWidth: 0.75))
                .focused($textFocused).accessibilityLabel("New note text")
                .accessibilityIdentifier("new-note-text")
            HStack {
                Label(state.newNoteProject ?? "Inbox", systemImage: state.newNoteProject == nil ? "tray" : "folder")
                    .font(.system(size: zoom.fontSize(12))).foregroundStyle(Palette.muted).lineLimit(2)
                    .accessibilityLabel("Save note to \(state.newNoteProject ?? "Inbox")")
                    .buddyHelp("Save note to \(state.newNoteProject ?? "Inbox")")
                Spacer(minLength: 0)
                Button("Cancel") { state.cancelNewNote() }.buttonStyle(.bordered)
                Button("Save note") { state.saveNewNote() }.buttonStyle(.borderedProminent)
                    .tint(accent).accessibilityIdentifier("new-note-save")
                    .disabled(state.newNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }.frame(maxWidth: zoom.value(860)).padding(16).frame(maxWidth: .infinity)
            .onAppear { textFocused = true }
    }
}
