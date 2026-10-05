import SwiftUI

@MainActor
struct WorkspaceItemCard: View {
    @Environment(\.workspaceZoom) private var zoom
    @ObservedObject var state: AppState
    @ObservedObject var workspace: WorkspaceStore
    @ObservedObject var capture: Capture
    @Environment(\.daBinAccent) private var accent
    @State private var namingSnippet = false
    @State private var snippetName = ""
    @State private var snippetError: String?
    @FocusState private var snippetNameFocused: Bool
    @State private var copied = false
    @State private var copyGeneration = 0

    private var alias: String? { workspace.snippetName(for: capture.id) }
    private var onShelf: Bool { workspace.shelfCaptureIDs.contains(capture.id) }
    private var hasFile: Bool { capture.attachmentRelativePath != nil }
    private var isSelected: Bool { workspace.selectedCaptureID == capture.id }
    private var projectName: String? { ExplorerQuery.project(of: capture, in: state.store.captures) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CaptureCardHeaderLayout(minimumLeadingWidth: 120 + (capture.isTask ? 38 : 0) + (capture.isPinned ? 16 : 0)) {
                HStack(alignment: .top, spacing: 4) {
                    if capture.isTask { TaskStatusButton(state: state, capture: capture) }
                    Button {
                        workspace.selectedCaptureID = capture.id
                        state.openCapture(capture.id)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(alias ?? (capture.title.isEmpty ? "Untitled capture" : capture.title))
                                .font(.system(size: zoom.fontSize(15), weight: .semibold))
                                .foregroundStyle(capture.isCompleted ? Palette.muted : Palette.foreground)
                                .strikethrough(capture.isTask && capture.isCompleted).lineLimit(2)
                            if capture.isPinned {
                                Image(systemName: "pin.fill").font(.system(size: zoom.fontSize(10)))
                                    .foregroundStyle(accent).accessibilityLabel("Pinned")
                            }
                        }.padding(.top, max(0, (32 - zoom.fontSize(15) * 1.2) / 2))
                            .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
                            .multilineTextAlignment(.leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Open \(alias ?? capture.title)")
                        .accessibilityIdentifier("workspace-item-\(capture.id.uuidString)")
                        .captureDragSource(state: state, capture: capture)
                }
                HStack(alignment: .top, spacing: 4) {
                    BuddyIconButton(symbol: copied ? "checkmark" : "doc.on.doc", title: copied ? "Copied" : "Copy \(capture.title)") { copy() }
                        .accessibilityIdentifier("workspace-copy-\(capture.id.uuidString)")
                    CaptureTrashButton(state: state, capture: capture)
                    Menu { itemActions(includesRemoval: false, includesCardButtons: false) } label: {
                        Image(systemName: "ellipsis").font(.system(size: 14, weight: .medium))
                            .frame(width: 32, height: 32).contentShape(Rectangle())
                    }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                        .foregroundStyle(Palette.muted).accessibilityLabel("Actions for \(capture.title)")
                        .accessibilityIdentifier("workspace-more-\(capture.id.uuidString)").buddyHelp("Item actions")
                }
            }
            CaptureProjectPriorityHeader(state: state, capture: capture)
                .frame(maxWidth: .infinity, alignment: .leading)
            ExplorerCaptureActionsLayout {
                CaptureReceiptView(capture: capture, category: capture.isTask ? (capture.isCompleted ? "Completed" : "Task") : captureTypeLabel(capture.kind))
                CaptureTrailView(state: state, capture: capture)
            }
            if let alias, alias != capture.title {
                Label(capture.title, systemImage: "text.badge.star")
                    .font(.system(size: zoom.fontSize(11))).foregroundStyle(Palette.muted).lineLimit(1)
            }
            if !capture.isMinimized {
                if CapturePreviewFileReference.thumbnail(store: state.store, capture: capture) != nil {
                    Button { workspace.selectedCaptureID = capture.id; state.openCapture(capture.id) } label: {
                        ExplorerCapturePreviewLayout(factor: zoom.factor) {
                            CaptureThumbnail(store: state.store, capture: capture)
                        }.clipShape(RoundedRectangle(cornerRadius: 8)).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Preview \(capture.title)")
                        .captureDragSource(state: state, capture: capture)
                }
                if !capture.isTask, capture.kind == .text,
                   let content = capture.originalText, content.count > capture.title.count {
                    Text(content).font(.system(size: zoom.fontSize(12))).foregroundStyle(Palette.muted)
                        .lineSpacing(zoom.lineSpacing(2)).lineLimit(3)
                        .captureDragSource(state: state, capture: capture)
                }
            }
            if capture.isTask, !capture.isMinimized || capture.taskPlanning?.focusSession?.isRunning == true {
                TaskFocusControls(state: state, capture: capture, taskCardStyle: true)
            }
            CaptureConversionUndo(state: state, capture: capture)
            BuddyActionFlow(spacing: 6) {
                if !capture.isTask { CaptureTaskConversionButton(state: state, capture: capture) }
                BuddyIconButton(symbol: onShelf ? "tray.full.fill" : "tray.and.arrow.down",
                    title: onShelf ? "Remove from shelf; keep capture" : "Add to shelf",
                    visualLabel: onShelf ? "On shelf" : "Keep", isActive: onShelf) { toggleShelf() }
            }
        }.padding(12)
            .workspaceZoomItem("capture:" + capture.id.uuidString)
            .projectCardBackground(workspace: workspace, projectName: projectName, cornerRadius: 12)
            .projectCardFrame(workspace: workspace, projectName: projectName, activeProject: state.libraryProject,
                              cornerRadius: 12, fallbackColor: isSelected ? accent.opacity(0.55) : Palette.line,
                              fallbackWidth: isSelected ? 1 : 0.7)
            .contextMenu { itemActions(includesRemoval: true, includesCardButtons: true) }
            .sheet(isPresented: $namingSnippet, onDismiss: resetSnippetNaming) {
                snippetNamingForm
            }
    }

    @ViewBuilder private func itemActions(includesRemoval: Bool, includesCardButtons: Bool) -> some View {
        Button("Open details", systemImage: "rectangle.and.text.magnifyingglass") { workspace.selectedCaptureID = capture.id; state.openCapture(capture.id) }
        if includesCardButtons {
            Button("Copy", systemImage: "doc.on.doc") { copy() }
        }
        if WorkspaceQuery.plainText(capture) != nil {
            Button("Copy as plain text", systemImage: "text.alignleft") {
                do { try WorkspaceClipboard.copyPlainText(capture); markCopied(); state.status = AppStatusMessage(text: "Plain text copied. Paste it into your working app.", severity: .success) }
                catch { state.reportFailure(error.localizedDescription) }
            }
            Button(alias == nil ? "Save as snippet…" : "Rename snippet…", systemImage: "text.badge.star") {
                snippetName = alias ?? String(capture.title.prefix(60))
                snippetError = nil
                namingSnippet = true
            }
        }
        if alias != nil {
            Button("Remove snippet name", systemImage: "text.badge.minus") {
                do { try workspace.setSnippetName(nil, for: capture.id) }
                catch { state.reportFailure(error.localizedDescription) }
            }
        }
        Button(capture.isPinned ? "Unpin" : "Pin", systemImage: capture.isPinned ? "pin.slash" : "pin") { state.togglePinned(capture) }
        CaptureReturnToInboxMenuItem(state: state, capture: capture)
        if includesCardButtons {
            Button(onShelf ? "Remove from shelf; keep capture" : "Add to shelf", systemImage: onShelf ? "tray" : "tray.and.arrow.down") { toggleShelf() }
        }
        if !capture.isTask {
            if includesCardButtons {
                Button("Turn into task", systemImage: "checkmark.circle") { state.convertToTask(capture) }
            }
            if capture.parentTaskID == nil { Menu {
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
        if includesRemoval {
            Button("Move to Recently Deleted…", systemImage: "trash", role: .destructive) { state.requestRemoval(capture) }
        }
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
    private var snippetNamingForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(alias == nil ? "Save as snippet" : "Rename snippet")
                .font(.system(size: 17, weight: .semibold))
            Text("Give this reusable content a name. Its original capture stays intact and is searchable.")
                .font(.system(size: 12)).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Snippet name", text: $snippetName)
                .textFieldStyle(.roundedBorder).focused($snippetNameFocused).frame(minHeight: 32)
                .accessibilityLabel("Snippet name")
                .accessibilityIdentifier("workspace-snippet-name-\(capture.id.uuidString)")
                .onSubmit(saveSnippet)
            if let snippetError {
                Text(snippetError).font(.system(size: 12)).foregroundStyle(Palette.task)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("workspace-snippet-error-\(capture.id.uuidString)")
            }
            HStack(spacing: 8) {
                Button(role: .cancel) { namingSnippet = false } label: {
                    Text("Cancel").frame(minHeight: 32).contentShape(Rectangle())
                }.keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("workspace-snippet-cancel-\(capture.id.uuidString)")
                Spacer(minLength: 0)
                Button(action: saveSnippet) {
                    Text(snippetError == nil ? "Save" : "Retry save").frame(minHeight: 32).contentShape(Rectangle())
                }.buttonStyle(.borderedProminent).tint(accent).keyboardShortcut(.defaultAction)
                    .disabled(snippetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("workspace-snippet-save-\(capture.id.uuidString)")
            }
        }.padding(20).frame(width: 320)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("workspace-snippet-editor-\(capture.id.uuidString)")
            .onAppear { snippetNameFocused = true }
            .onChange(of: snippetName) { _, _ in snippetError = nil }
    }

    private func resetSnippetNaming() {
        snippetName = ""
        snippetError = nil
        snippetNameFocused = false
    }

    private func saveSnippet() {
        guard namingSnippet, !snippetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            try workspace.setSnippetName(snippetName, for: capture.id)
            state.status = AppStatusMessage(text: "Snippet saved. Find it in Projects → Clipboard → Snippets.", severity: .success)
            namingSnippet = false
        } catch {
            snippetError = "Couldn’t save this snippet name: " + error.localizedDescription
            state.reportFailure(error.localizedDescription)
        }
    }
}
