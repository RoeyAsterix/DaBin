import SwiftUI

@MainActor
struct InboxScreen: View {
    @Environment(\.workspaceZoom) private var zoom
    @ObservedObject var state: AppState
    @Environment(\.daBinAccent) private var accent
    @Environment(\.daBinTutorialTargets) private var tutorialTargets
    var showsNewTaskEntry = true
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
                BuddyActionFlow(spacing: 13) {
                    Button { state.pasteClipboard() } label: { Label("Paste", systemImage: "doc.on.clipboard").frame(minHeight: 32) }
                    Button { state.importFiles() } label: { Label("Add files", systemImage: "folder.badge.plus").frame(minHeight: 32) }
                    Button { state.openNewNote() } label: { Label("Note editor", systemImage: "square.and.pencil").frame(minHeight: 32) }
                        .accessibilityLabel("Open note editor").accessibilityIdentifier("inbox-note-editor")
                    if showsNewTaskEntry {
                        Button { state.openNewTask() } label: { Label("Task", systemImage: "plus.circle").frame(minHeight: 32) }
                    }
                    Spacer(minLength: 0)
                    CaptureFilterMenu(selection: $state.filter)
                }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(accent)
                    .daBinTutorialAnchor(.inboxActions)
                if let project = state.newNoteProject, !state.newNoteText.isEmpty {
                    Label("Draft for \(project)", systemImage: "folder")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
                        .buddyHelp("This unfinished draft will be saved to \(project)")
                } else {
                    Text("Drop items here. Everything stays on this Mac.")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
            }.padding(14)
                .daBinTutorialAnchor(.inboxComposer)
            Group {
                if items.isEmpty {
                    if tutorialTargets.contains(.captureActions) {
                        DaBinTutorialSampleCaptureCard()
                    } else {
                        EmptyMessage(symbol: "tray", title: state.filter == .all ? "Room for your next idea" : "No matching items",
                                     message: "Paste, drop a file, or jot a note above. Day and Week show everything you captured by date.")
                    }
                } else {
                    ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: zoom.value(9)) {
                            Text("\(items.count) to organize").font(.system(size: 11)).foregroundStyle(Palette.muted)
                            ForEach(items) { item in
                                CaptureRow(state: state, capture: item, featured: false)
                                    .id("capture:" + item.id.uuidString)

                            }
                        }.padding(.horizontal, 14).padding(.bottom, 14).frame(maxWidth: zoom.value(860)).frame(maxWidth: .infinity)
                    }.background {
                        WorkspaceScrollHistory(anchor: state.workspaceViewport, contextID: "inbox",
                            onAnchor: { state.workspaceViewport = $0 }).allowsHitTesting(false).accessibilityHidden(true)
                    }
                    .onAppear { if let anchor = state.workspaceViewport { proxy.scrollTo(anchor.itemID, anchor: .top) } }
                    .onChange(of: state.navigationRestorationRevision) { _, _ in
                        if let anchor = state.workspaceViewport { proxy.scrollTo(anchor.itemID, anchor: .top) }
                    }
                    }
                }
            }.daBinTutorialAnchor(.captureFeed)
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
            let destination = project ?? "Captions"
            state.status = AppStatusMessage(text: asTask ? "Task added to \(destination)." : "Note saved to \(destination).", severity: .success)
        } catch { state.reportFailure(error.localizedDescription) }
    }
}

@MainActor
private struct DaBinTutorialSampleCaptureCard: View {
    @Environment(\.daBinAccent) private var accent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 18, weight: .medium)).foregroundStyle(accent)
                .frame(width: 34, height: 34).background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Tutorial example · not saved").font(.system(size: 13, weight: .semibold))
                Text("Every saved capture gets a More menu for its next action.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 6)
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(accent)
                .frame(width: 32, height: 32)
                .background(Palette.soft, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("Example More capture actions")
                .daBinTutorialAnchor(.captureActions)
        }
        .padding(14)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.line, lineWidth: 0.7))
        .padding(.horizontal, 14)
        .accessibilityElement(children: .contain)
    }
}
