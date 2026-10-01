import SwiftUI

@MainActor struct ExplorerCaptureRow: View {
    @ObservedObject var state: AppState
    @ObservedObject var workspace: WorkspaceStore
    @ObservedObject var capture: Capture
    var focus: FocusState<UUID?>.Binding
    let select: () -> Void
    @Environment(\.daBinAccent) private var accent

    var body: some View {
        HStack(spacing: 6) {
            Button(action: select) {
                HStack(spacing: 10) {
                    CaptureThumbnail(store: state.store, capture: capture)
                        .frame(width: 46, height: 46).clipShape(RoundedRectangle(cornerRadius: 7))
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text(capture.title.isEmpty ? "Untitled capture" : capture.title)
                                .font(.system(size: 13, weight: .medium)).lineLimit(2)
                                .strikethrough(capture.isTask && capture.isCompleted)
                            if capture.isPinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(accent).accessibilityLabel("Pinned") }
                        }
                        HStack(spacing: 4) {
                            CaptureSourceIcon(capture: capture, size: 12)
                            Text(capture.isTask ? (capture.isCompleted ? "Completed" : "Task") : captureTypeLabel(capture.kind))
                            Text("· " + prettyDay(capture.captureDay, includeWeekday: false))
                        }.font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1)
                        if capture.parentTaskID != nil {
                            Label("Task attachment", systemImage: "paperclip").font(.system(size: 10)).foregroundStyle(accent)
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
        }.padding(8)
            .background(workspace.selectedCaptureID == capture.id ? accent.opacity(0.1) : Palette.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(workspace.selectedCaptureID == capture.id ? accent.opacity(0.4) : Palette.line, lineWidth: 0.7))
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
                    Text(capture.title).font(.system(size: 20, weight: .semibold)).textSelection(.enabled)
                    Spacer(minLength: 6)
                    Menu { ExplorerCaptureActions(state: state, workspace: workspace, capture: capture) } label: {
                        Image(systemName: "ellipsis.circle").font(.system(size: 19)).frame(width: 28, height: 28)
                    }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .accessibilityLabel("Actions for selected capture").buddyHelp("Item actions")
                }
                HStack(spacing: 6) {
                    CaptureSourceIcon(capture: capture, size: 16)
                    Text(WorkspaceQuery.sourceName(capture) ?? captureTypeLabel(capture.kind))
                    Spacer(minLength: 0)
                    Text(captureClock(capture))
                }.font(.system(size: 11)).foregroundStyle(Palette.muted)
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
                        Text(url.path).font(.system(size: 10)).foregroundStyle(Palette.muted).textSelection(.enabled)
                            .accessibilityLabel("Saved path, \(url.path)")
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
    @Environment(\.daBinAccent) private var accent
    private var title: String { state.libraryProject ?? (workspace.explorerUnfiledOnly ? "Unfiled" : "All projects") }
    var body: some View {
        Button { presented.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: "folder")
                Text(title).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9))
            }.font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(.plain).foregroundStyle(accent).buddyHelp("Choose a project or drag items onto a project")
            .accessibilityLabel("Project, \(title)").accessibilityIdentifier("workspace-project-picker")
            .onDrop(of: ExplorerTransfer.acceptedTypeIdentifiers, isTargeted: $dragHovered) { _ in false }
            .task(id: dragHovered) {
                guard dragHovered else { return }
                try? await Task.sleep(for: .milliseconds(350))
                if !Task.isCancelled && dragHovered { presented = true }
            }
            .popover(isPresented: $presented, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 5) {
                    Button("All projects", systemImage: "square.stack.3d.up") {
                        workspace.explorerUnfiledOnly = false; state.libraryProject = nil; presented = false
                    }.padding(8)
                    ScrollView {
                        VStack(spacing: 3) {
                            projectTarget(nil)
                            ForEach(Set(state.projectNames + workspace.projectNames).sorted(), id: \.self) { project in projectTarget(project) }
                        }
                    }.frame(maxHeight: 260)
                    Divider()
                    Button("New project…", systemImage: "folder.badge.plus") { presented = false; onCreate() }.padding(8)
                    Text("Drop a DaBin item onto a project to move it.").font(.system(size: 10)).foregroundStyle(Palette.muted).padding(.horizontal, 8)
                }.padding(8).frame(width: 260).buttonStyle(.plain)
            }
    }
    private func projectTarget(_ name: String?) -> some View {
        ExplorerProjectTarget(title: name ?? "Unfiled", selected: name == state.libraryProject && (name != nil || workspace.explorerUnfiledOnly),
            select: { workspace.explorerUnfiledOnly = name == nil; state.libraryProject = name; presented = false },
            receive: { state.explorerInput.receive($0, project: name) })
    }
}

@MainActor private struct ExplorerProjectTarget: View {
    let title: String
    let selected: Bool
    let select: () -> Void
    let receive: ([NSItemProvider]) -> Bool
    @State private var targeted = false
    @Environment(\.daBinAccent) private var accent
    var body: some View {
        Button(action: select) {
            Label(title, systemImage: selected ? "checkmark" : "folder").font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading).padding(9).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .background(accent.opacity(targeted ? 0.18 : selected ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 8))
            .onDrop(of: ExplorerTransfer.acceptedTypeIdentifiers, isTargeted: $targeted, perform: receive)
            .accessibilityLabel("Project \(title)").accessibilityAddTraits(selected ? .isSelected : [])
    }
}
