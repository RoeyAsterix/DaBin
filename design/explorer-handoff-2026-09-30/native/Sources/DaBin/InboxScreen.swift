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
                HStack {
                    Text("Capture now. Organize later.").font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 0)
                    Button { state.openDaily() } label: { Label("Activity", systemImage: "calendar") }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(accent)
                        .buddyHelp("Browse everything by date").accessibilityIdentifier("inbox-activity")
                }
                HStack(spacing: 8) {
                    TextField("A thought or a next step…", text: $state.newNoteText, axis: .vertical)
                        .lineLimit(1...3).textFieldStyle(.plain).font(.system(size: 13))
                        .accessibilityLabel("Quick capture text").accessibilityIdentifier("inbox-quick-text")
                        .onSubmit { saveQuick(asTask: false) }
                    Menu {
                        Button("Save note", systemImage: "note.text") { saveQuick(asTask: false) }
                        Button("Create task", systemImage: "checkmark.circle") { saveQuick(asTask: true) }
                    } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 20)) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .disabled(state.newNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Save quick capture").buddyHelp("Save note or task")
                }.padding(10).background(Palette.surface, in: RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Palette.line))
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
                             message: "Paste, drop a file, or jot a note above. Filed items stay in Workspace and Activity.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 9) {
                        Text("\(items.count) to organize").font(.system(size: 11)).foregroundStyle(Palette.muted)
                        ForEach(items) { item in
                            VStack(alignment: .leading, spacing: 3) {
                                CaptureRow(state: state, capture: item, featured: false, embeddedInCard: true, showsDate: true)
                                HStack {
                                    Button { state.openCapture(item.id, focus: "project") } label: { Label("Project", systemImage: "folder.badge.plus") }
                                    if item.isTask {
                                        Button { planToday(item) } label: { Label("Today", systemImage: "sun.max") }
                                    } else {
                                        Button { state.convertToTask(item) } label: { Label("Make task", systemImage: "checkmark.circle") }
                                    }
                                    Spacer(minLength: 0)
                                    Button { keep(item) } label: { Image(systemName: "checkmark") }
                                        .accessibilityLabel("Keep in Workspace: \(item.title)").buddyHelp("Done organizing — keep in Workspace")
                                }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(accent).padding(.bottom, 9)
                            }.padding(.horizontal, 10).background(Palette.surface, in: RoundedRectangle(cornerRadius: 13))
                                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Palette.line, lineWidth: 0.7))
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
    private func keep(_ item: Capture) {
        do { try state.workspace.markInboxProcessed([item.id], processed: true) }
        catch { state.reportFailure(error.localizedDescription) }
    }
    private func planToday(_ item: Capture) {
        do { try state.store.planTask(item, on: CaptureCalendar.dayString(Date())) }
        catch { state.reportFailure(error.localizedDescription) }
    }
}
