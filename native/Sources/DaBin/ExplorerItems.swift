import SwiftUI

@MainActor struct ExplorerCaptureRow: View {
    @ObservedObject var state: AppState
    @ObservedObject var workspace: WorkspaceStore
    @ObservedObject var capture: Capture
    var focus: FocusState<UUID?>.Binding
    let select: () -> Void
    @Environment(\.daBinAccent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                if capture.isTask {
                    Button { state.toggleTaskCompletion(capture) } label: {
                        Image(systemName: capture.isCompleted ? "checkmark.square.fill" : "square")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(capture.isCompleted ? Palette.completed : Palette.muted)
                            .frame(width: 32, height: 32)
                    }.buttonStyle(.plain).accessibilityLabel(capture.isCompleted ? "Reopen task" : "Complete task")
                }
                Button(action: select) {
                    HStack(spacing: 10) {
                        if !capture.isTask {
                            CaptureThumbnail(store: state.store, capture: capture)
                                .frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            Text(capture.title.isEmpty ? "Untitled capture" : capture.title)
                                .font(.system(size: 15, weight: .semibold)).lineLimit(2)
                                .strikethrough(capture.isTask && capture.isCompleted)
                            HStack(spacing: 4) {
                                Text(capture.isTask ? (capture.isCompleted ? "Completed" : "Task") : captureTypeLabel(capture.kind))
                                Text("· " + prettyDay(capture.captureDay, includeWeekday: false))
                                if capture.isPinned { Image(systemName: "pin.fill").accessibilityLabel("Pinned") }
                            }.font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
                            if capture.parentTaskID != nil {
                                Label("Task attachment", systemImage: "paperclip").font(.system(size: 11)).foregroundStyle(Palette.muted)
                            }
                        }
                        Spacer(minLength: 0)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).multilineTextAlignment(.leading)
                    .focused(focus, equals: capture.id)
                    .accessibilityLabel("Open \(capture.title)")
                    .accessibilityIdentifier("workspace-item-\(capture.id.uuidString)")
                    .accessibilityAddTraits(workspace.selectedCaptureID == capture.id ? .isSelected : [])
                CaptureCopyButton(state: state, captures: [capture])
                CaptureTrashButton(state: state, capture: capture)
            }
            CaptureTrailView(state: state, capture: capture)
            CaptureConversionUndo(state: state, capture: capture)
            if capture.isTask { TaskFocusControls(state: state, capture: capture) }
            else if capture.parentTaskID == nil {
                HStack(spacing: 6) {
                    CaptureProjectPickerButton(state: state, capture: capture)
                    Spacer(minLength: 0)
                    BuddyIconButton(symbol: "checklist", title: "Turn into task") { state.convertToTask(capture) }
                    CaptureKeepButton(state: state, capture: capture)
                }
            }
        }.padding(12)
            .background(workspace.selectedCaptureID == capture.id ? Palette.soft : Palette.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(workspace.selectedCaptureID == capture.id ? accent.opacity(0.45) : Palette.line, lineWidth: 1))
            .contextMenu { ExplorerCaptureActions(state: state, workspace: workspace, capture: capture) }
            .onDrag {
                do { return try ExplorerTransfer.itemProvider(for: capture, store: state.store) }
                catch { state.reportFailure(error.localizedDescription); return NSItemProvider() }
            }
    }
}

@MainActor struct ExplorerInspector: View {
    @ObservedObject var state: AppState
    @ObservedObject var workspace: WorkspaceStore
    @ObservedObject var capture: Capture
    let height: CGFloat
    @Environment(\.daBinAccent) private var accent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    Text(capture.title).font(.system(size: 26, weight: .semibold, design: .rounded)).textSelection(.enabled)
                    Spacer(minLength: 6)
                    Menu { ExplorerCaptureActions(state: state, workspace: workspace, capture: capture) } label: {
                        Image(systemName: "ellipsis.circle").font(.system(size: 19)).frame(width: 28, height: 28)
                    }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .accessibilityLabel("Actions for selected capture").buddyHelp("Item actions")
                }
                HStack(spacing: 6) {
                    CaptureTrailView(state: state, capture: capture)
                    Spacer(minLength: 0)
                    Text(captureClock(capture))
                }.font(.system(size: 11)).foregroundStyle(Palette.muted)
                if capture.isTask { TaskFocusControls(state: state, capture: capture, compact: false) }
                if capture.attachmentRelativePath != nil {
                    if state.store.managedURL(for: capture) != nil {
                        DetailPreview(store: state.store, capture: capture, height: max(120, min(520, height * 0.6)))
                    } else {
                        Label("Saved file unavailable. Your capture details are still here.", systemImage: "doc.badge.ellipsis")
                            .font(.system(size: 13)).foregroundStyle(Palette.muted)
                    }
                }
                if let text = WorkspaceQuery.plainText(capture) {
                    Text(text).font(.system(size: 14)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                if !capture.comment.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("Comment", systemImage: "text.bubble").font(.system(size: 11, weight: .semibold)).foregroundStyle(accent)
                        Text(capture.comment).font(.system(size: 13)).textSelection(.enabled)
                    }
                }
                HStack {
                    if capture.isTask { TaskStatusButton(state: state, capture: capture) }
                    Button("Details", systemImage: "slider.horizontal.3") { state.openCapture(capture.id) }
                        .accessibilityIdentifier("explorer-open-details")
                    Spacer(minLength: 0)
                    CaptureCopyButton(state: state, captures: [capture])
                    CaptureTrashButton(state: state, capture: capture)
                }.font(.system(size: 12)).foregroundStyle(accent)
                if let reminder = capture.reminderAt {
                    Label(reminder.formatted(date: .abbreviated, time: .shortened), systemImage: "bell")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                if let parentID = capture.parentTaskID, let parent = state.store.captures.first(where: { $0.id == parentID }) {
                    Button { state.openCapture(parentID) } label: { Label("Attached to \(parent.title)", systemImage: "paperclip") }
                        .font(.system(size: 12)).lineLimit(2)
                }
                if let url = state.store.managedURL(for: capture) {
                    VStack(alignment: .leading, spacing: 5) {
                        Button("Reveal saved file", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                            .font(.system(size: 12))
                        DisclosureGroup("Saved location") {
                            Text(url.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted).textSelection(.enabled)
                                .accessibilityLabel("Saved path, \(url.path)")
                        }.font(.system(size: 12)).foregroundStyle(Palette.muted)
                    }
                }
                Text("Captured \(prettyDay(capture.captureDay)) · \(ExplorerQuery.project(of: capture, in: state.store.captures) ?? "Unfiled")")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }.id(capture.id)
    }
}

@MainActor struct ExplorerCaptureActions: View {
    @ObservedObject var state: AppState
    @ObservedObject var workspace: WorkspaceStore
    @ObservedObject var capture: Capture
    var body: some View {
        Button("Open details", systemImage: "rectangle.and.text.magnifyingglass") { state.openCapture(capture.id) }
        Button("Copy", systemImage: "doc.on.doc") { state.copyCapturesToClipboard([capture]) }
        if WorkspaceQuery.plainText(capture) != nil {
            Button("Copy as plain text", systemImage: "text.alignleft") {
                do { try WorkspaceClipboard.copyPlainText(capture); state.status = AppStatusMessage(text: "Plain text copied.", severity: .success) }
                catch { state.reportFailure(error.localizedDescription) }
            }
        }
        if capture.attachmentRelativePath != nil {
            Button("Open saved file", systemImage: "arrow.up.forward.square") { state.openOriginal(capture) }
            Button("Reveal saved file", systemImage: "folder") {
                guard let url = state.store.managedURL(for: capture) else {
                    state.reportFailure("The saved file is unavailable. Your capture details are kept."); return
                }
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            Button("Copy saved path", systemImage: "link") {
                do { try WorkspaceClipboard.copyManagedPath(capture, store: state.store); state.status = AppStatusMessage(text: "Saved path copied.", severity: .success) }
                catch { state.reportFailure(error.localizedDescription) }
            }
        }
        Divider()
        if capture.parentTaskID == nil {
            Menu {
                Button("Unfiled", systemImage: "tray") { move(to: nil) }
                ForEach(Set(state.projectNames + workspace.projectNames).sorted(), id: \.self) { project in
                    Button(project, systemImage: "folder") { move(to: project) }
                }
            } label: { Label("Move to project", systemImage: "folder") }
        }
        Button(capture.isPinned ? "Unpin" : "Pin", systemImage: capture.isPinned ? "pin.slash" : "pin") { state.togglePinned(capture) }
        Button(workspace.shelfCaptureIDs.contains(capture.id) ? "Remove from shelf; keep capture" : "Add to shelf", systemImage: "tray") {
            do { try workspace.setOnShelf([capture.id], included: !workspace.shelfCaptureIDs.contains(capture.id)) }
            catch { state.reportFailure(error.localizedDescription) }
        }
        if !capture.isTask {
            Button("Turn into task", systemImage: "checkmark.circle") { state.convertToTask(capture) }
            if capture.parentTaskID == nil { Menu {
                ForEach(state.store.captures.filter { $0.isTask && !$0.isCompleted }) { task in
                    Button(task.title, systemImage: "paperclip") {
                        do { try state.store.attachCapture(capture, to: task) }
                        catch { state.reportFailure(error.localizedDescription) }
                    }
                }
            } label: { Label("Attach to task", systemImage: "paperclip") }
                .disabled(!state.store.captures.contains { $0.isTask && !$0.isCompleted })
            }
        }
        Divider()
        Button("Move to Recently Deleted…", systemImage: "trash", role: .destructive) { state.requestRemoval(capture) }
    }

    private func move(to project: String?) {
        do {
            let provider = try ExplorerTransfer.itemProvider(for: capture, store: state.store)
            _ = state.explorerInput.receive([provider], project: project)
        } catch { state.reportFailure(error.localizedDescription) }
    }
}

@MainActor struct ExplorerProjectPicker: View {
    @ObservedObject var state: AppState
    @ObservedObject var workspace: WorkspaceStore
    let onCreate: () -> Void
    @State private var presented = false
    @State private var dragHovered = false
    @FocusState private var focused: Bool
    private var title: String { state.libraryProject ?? (workspace.explorerUnfiledOnly ? "Unfiled" : "All projects") }
    var body: some View {
        Button { presented.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder").font(.system(size: 14)).foregroundStyle(Palette.muted)
                    .frame(width: 29, height: 29).background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.line))
                Text(title).font(.system(size: 18, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.72)
                Image(systemName: "chevron.down").font(.system(size: 9)).foregroundStyle(Palette.muted)
            }.frame(maxWidth: .infinity, minHeight: 36, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(Palette.foreground).focused($focused)
            .buddyHelp("Choose a project or drag items onto a project")
            .accessibilityLabel("Project, \(title)").accessibilityIdentifier("workspace-project-picker")
            .onDrop(of: ExplorerTransfer.acceptedTypeIdentifiers, isTargeted: $dragHovered) { _ in false }
            .task(id: dragHovered) {
                guard dragHovered else { return }
                try? await Task.sleep(for: .milliseconds(350))
                if !Task.isCancelled && dragHovered { presented = true }
            }
            .popover(isPresented: $presented, arrowEdge: .bottom) {
                ProjectPickerPanel(state: state, selectedProject: state.libraryProject, allowsAll: true,
                    allSelected: state.libraryProject == nil && !workspace.explorerUnfiledOnly, allowsDrop: true,
                    onSelect: { name, all in
                        state.libraryProject = name; workspace.explorerUnfiledOnly = name == nil && !all
                        if let error = workspace.error { throw WorkspaceError.unavailable(error) }
                    }, onDismiss: { presented = false; focused = true })
            }
    }
}
