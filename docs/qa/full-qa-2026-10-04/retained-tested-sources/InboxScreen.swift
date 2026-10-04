import SwiftUI

@MainActor
struct InboxScreen: View {
    @ObservedObject var state: AppState
    @Environment(\.daBinAccent) private var accent
    private var items: [Capture] {
        state.store.captures.filter {
            $0.parentTaskID == nil && $0.projectName == nil && !$0.isCompleted
            && !state.workspace.processedInboxIDs.contains($0.id)
            && (!$0.isTask || $0.taskPlanning?.plannedDay == nil) && state.filter.includes($0)
        }.sorted { $0.capturedAt > $1.capturedAt }
    }
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 9) {
                Text("Capture now. Organize later.").font(.system(size: 14, weight: .medium))
                HStack(spacing: 8) {
                    TextField("A thought or a next step…", text: $state.newNoteText, axis: .vertical)
                        .lineLimit(1...3).textFieldStyle(.plain).font(.system(size: 14))
                        .accessibilityLabel("Quick capture text").accessibilityIdentifier("inbox-quick-text")
                        .onSubmit { saveQuick(asTask: false) }
                    Menu {
                        Button("Save note", systemImage: "note.text") { saveQuick(asTask: false) }
                        Button("Create task", systemImage: "checkmark.circle") { saveQuick(asTask: true) }
                    } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 20)) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .disabled(state.newNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Save quick capture").buddyHelp("Save note or task")
                }.padding(12).background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.line, lineWidth: 0.7))
                HStack(spacing: 13) {
                    Button { state.pasteClipboard() } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                    Button { state.importFiles() } label: { Label("Files", systemImage: "folder.badge.plus") }
                    Button { state.openNewTask() } label: { Label("Task", systemImage: "plus.circle") }
                    Spacer(minLength: 0)
                    CaptureFilterMenu(selection: $state.filter)
                }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(accent)
                if let project = state.newNoteProject, !state.newNoteText.isEmpty {
                    Label("Draft for \(project)", systemImage: "folder")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
                        .buddyHelp("This unfinished draft will be saved to \(project)")
                } else {
                    Text("Drop items here. Everything stays on this Mac.")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
            }.padding(14)
            if items.isEmpty {
                EmptyMessage(symbol: "tray", title: state.filter == .all ? "Room for your next idea" : "No matching items",
                             message: "Paste, drop a file, or jot a note above. Day and Week show everything you captured by date.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 9) {
                        Text("\(items.count) to organize").font(.system(size: 11)).foregroundStyle(Palette.muted)
                        ForEach(items) { item in
                            CaptureRow(state: state, capture: item, featured: false)

                        }
                    }.padding(.horizontal, 14).padding(.bottom, 14).frame(maxWidth: 860).frame(maxWidth: .infinity)
                }
            }
        }
    }
    private func saveQuick(asTask: Bool) {
        let text = state.newNoteText
        let project = state.newNoteProject
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            if asTask { _ = try state.store.createTask(text: text, reminderAt: nil, projectName: project) }
            else { let capture = try state.store.createNote(text: text, projectName: project); state.didCapture([capture]) }
            state.clearNewNoteDraft()
            let destination = project ?? "Inbox"
            state.status = AppStatusMessage(text: asTask ? "Task added to \(destination)." : "Note saved to \(destination).", severity: .success)
        } catch { state.reportFailure(error.localizedDescription) }
    }
}
