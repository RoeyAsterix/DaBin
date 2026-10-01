import SwiftUI

@MainActor
struct WorkspaceItemCard: View {
    @ObservedObject var state: AppState
    @ObservedObject var workspace: WorkspaceStore
    @ObservedObject var capture: Capture
    @Environment(\.daBinAccent) private var accent
    @State private var namingSnippet = false
    @State private var snippetName = ""
    @State private var copied = false
    @State private var copyGeneration = 0

    private var alias: String? { workspace.snippetName(for: capture.id) }
    private var onShelf: Bool { workspace.shelfCaptureIDs.contains(capture.id) }
    private var hasFile: Bool { capture.attachmentRelativePath != nil }
    private var isSelected: Bool { workspace.selectedCaptureID == capture.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 4) {
                CaptureTrailView(state: state, capture: capture)
                Spacer(minLength: 0)
                if capture.isPinned { Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(accent).accessibilityLabel("Pinned") }
                BuddyIconButton(symbol: copied ? "checkmark" : "doc.on.doc", title: copied ? "Copied" : "Copy \(capture.title)") { copy() }
                CaptureTrashButton(state: state, capture: capture)
            }
            HStack(spacing: 5) {
                Text(captureTypeLabel(capture.kind)).lineLimit(1)
                Spacer(minLength: 0)
                Text("\(prettyDay(capture.captureDay, includeWeekday: false)) · \(captureClock(capture))").monospacedDigit().lineLimit(1)
            }.font(.system(size: 11)).foregroundStyle(Palette.muted)
            HStack(alignment: .top, spacing: 8) {
                if capture.isTask { TaskStatusButton(state: state, capture: capture) }
                Button {
                    workspace.selectedCaptureID = capture.id
                    state.openCapture(capture.id)
                } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        if !capture.isMinimized, !capture.isTask, ![CaptureKind.text, .task].contains(capture.kind) {
                            CaptureThumbnail(store: state.store, capture: capture)
                                .frame(height: workspace.mode == .clipboard ? 164 : 208)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        if let alias {
                            Label(alias, systemImage: "text.badge.star")
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(accent).lineLimit(2)
                        }
                        if capture.isTask {
                            Text(capture.isCompleted ? "COMPLETED" : "TASK")
                                .font(.system(size: 10, weight: .medium)).tracking(0.7).foregroundStyle(Palette.muted)
                        }
                        Text(capture.title.isEmpty ? "Untitled capture" : capture.title)
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(capture.isCompleted ? Palette.muted : Palette.foreground)
                            .strikethrough(capture.isTask && capture.isCompleted)
                            .lineLimit(capture.isMinimized ? 1 : 4)
                        if !capture.isMinimized, !capture.isTask, capture.kind == .text,
                           let content = capture.originalText, content.count > capture.title.count {
                            Text(content).font(.system(size: 14)).foregroundStyle(Palette.muted).lineSpacing(3).lineLimit(4)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Open \(alias ?? capture.title)")
                    .accessibilityIdentifier("workspace-item-\(capture.id.uuidString)")
            }
            if capture.isTask, !capture.isMinimized { TaskFocusControls(state: state, capture: capture) }
            CaptureConversionUndo(state: state, capture: capture)
            HStack(spacing: 4) {
                CaptureProjectPickerButton(state: state, capture: capture)
                Spacer(minLength: 0)
                if !capture.isTask {
                    CaptureTaskConversionButton(state: state, capture: capture)
                    CaptureKeepButton(state: state, capture: capture)
                }
                BuddyIconButton(symbol: onShelf ? "tray.full.fill" : "tray.and.arrow.down", title: onShelf ? "Remove from shelf; keep capture" : "Add to shelf", isActive: onShelf) { toggleShelf() }
                Menu { itemActions } label: {
                    Image(systemName: "ellipsis").font(.system(size: 16, weight: .medium)).frame(width: 32, height: 32)
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().foregroundStyle(Palette.muted)
                    .accessibilityLabel("Actions for \(capture.title)").buddyHelp("Item actions")
            }.padding(.top, 8).overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 0.7) }
        }.padding(16)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(isSelected ? accent.opacity(0.55) : Palette.line, lineWidth: isSelected ? 1 : 0.7))
            .contextMenu { itemActions }
            .alert(alias == nil ? "Save as snippet" : "Rename snippet", isPresented: $namingSnippet) {
                TextField("Snippet name", text: $snippetName)
                Button("Cancel", role: .cancel) { }
                Button("Save") { saveSnippet() }.disabled(snippetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } message: { Text("Give this reusable content a name. Its original capture stays intact and is searchable.") }
    }

    @ViewBuilder private var itemActions: some View {
        Button("Open details", systemImage: "rectangle.and.text.magnifyingglass") { workspace.selectedCaptureID = capture.id; state.openCapture(capture.id) }
        Button("Copy", systemImage: "doc.on.doc") { copy() }
        if WorkspaceQuery.plainText(capture) != nil {
            Button("Copy as plain text", systemImage: "text.alignleft") {
                do { try WorkspaceClipboard.copyPlainText(capture); markCopied(); state.status = AppStatusMessage(text: "Plain text copied. Paste it into your working app.", severity: .success) }
                catch { state.reportFailure(error.localizedDescription) }
            }
            Button(alias == nil ? "Save as snippet…" : "Rename snippet…", systemImage: "text.badge.star") {
                snippetName = alias ?? String(capture.title.prefix(60)); namingSnippet = true
            }
        }
        if alias != nil {
            Button("Remove snippet name", systemImage: "text.badge.minus") {
                do { try workspace.setSnippetName(nil, for: capture.id) }
                catch { state.reportFailure(error.localizedDescription) }
            }
        }
        Button(capture.isPinned ? "Unpin" : "Pin", systemImage: capture.isPinned ? "pin.slash" : "pin") { state.togglePinned(capture) }
        Button(onShelf ? "Remove from shelf; keep capture" : "Add to shelf", systemImage: onShelf ? "tray" : "tray.and.arrow.down") { toggleShelf() }
        Menu {
            Button("No project", systemImage: "tray") { state.assignProject(capture, name: nil) }
            ForEach(Set(state.projectNames + workspace.projectNames).sorted(), id: \.self) { project in
                Button(project, systemImage: "folder") { state.assignProject(capture, name: project) }
            }
        } label: { Label("Move to project", systemImage: "folder") }
        if !capture.isTask {
            Button("Turn into task", systemImage: "checkmark.circle") { state.convertToTask(capture) }
            Menu {
                ForEach(state.store.captures.filter { $0.isTask && !$0.isCompleted }) { task in
                    Button(task.title, systemImage: "paperclip") {
                        do {
                            try state.store.attachCapture(capture, to: task)
                            try workspace.setOnShelf([capture.id], included: false)
                            state.status = AppStatusMessage(text: "Attached to \(task.title).", severity: .success)
                        } catch { state.reportFailure(error.localizedDescription) }
                    }
                }
            } label: { Label("Attach to task", systemImage: "paperclip") }
                .disabled(!state.store.captures.contains { $0.isTask && !$0.isCompleted })
        }
        if hasFile {
            Divider()
            Button("Open saved file", systemImage: "arrow.up.forward.square") { state.openOriginal(capture) }
            Button("Reveal saved file", systemImage: "folder") {
                guard let url = state.store.managedURL(for: capture) else { state.reportFailure("The saved original is unavailable. Your capture details are still kept."); return }
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            Button("Copy saved file path", systemImage: "link") {
                do { try WorkspaceClipboard.copyManagedPath(capture, store: state.store); markCopied() }
                catch { state.reportFailure(error.localizedDescription) }
            }
        }
        Divider()
        Button(capture.isMinimized ? "Expand capture" : "Minimize capture", systemImage: capture.isMinimized ? "chevron.down" : "chevron.up") { state.toggleMinimized(capture) }
        Button("Comment", systemImage: "text.bubble") { state.openCapture(capture.id, focus: "comment") }
        Button("Reminder", systemImage: "bell") { state.openCapture(capture.id, focus: "reminder") }
        Button("Move to Recently Deleted…", systemImage: "trash", role: .destructive) { state.requestRemoval(capture) }
    }

    private func copy() { if state.copyCapturesToClipboard([capture]) { markCopied() } }
    private func markCopied() {
        copied = true; copyGeneration &+= 1
        let generation = copyGeneration
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            if generation == copyGeneration { copied = false }
        }
    }
    private func toggleShelf() {
        do { try workspace.setOnShelf([capture.id], included: !onShelf) }
        catch { state.reportFailure(error.localizedDescription) }
    }
    private func saveSnippet() {
        do {
            try workspace.setSnippetName(snippetName, for: capture.id)
            state.status = AppStatusMessage(text: "Snippet saved. Find it in Workspace → Clipboard → Snippets.", severity: .success)
        } catch { state.reportFailure(error.localizedDescription) }
    }
}
