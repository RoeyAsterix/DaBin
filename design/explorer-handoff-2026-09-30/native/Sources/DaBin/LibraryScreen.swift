import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct LibraryScreen: View {
    @ObservedObject var state: AppState
    @ObservedObject private var workspace: WorkspaceStore
    @StateObject private var shelfCapture: ShelfCaptureController
    @Environment(\.daBinAccent) private var accent
    @State private var showingProjectName = false
    @State private var newProjectName = ""
    @State private var targeted = false
    @State private var exporting = false

    private struct ScrollContext: Equatable {
        let project: String?
        let mode: WorkspaceMode
    }

    init(state: AppState) {
        self.state = state
        _workspace = ObservedObject(wrappedValue: state.workspace)
        _shelfCapture = StateObject(wrappedValue: ShelfCaptureController(state: state))
    }

    private var items: [Capture] {
        WorkspaceQuery.items(state.store.captures, workspace: workspace, project: state.libraryProject,
            filter: state.filter, query: "", pinnedOnly: state.libraryPinnedOnly)
    }
    private var projects: [String] { Set(state.projectNames + workspace.projectNames).sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
    private var applications: [String] { Set(state.store.captures.compactMap(WorkspaceQuery.sourceName)).sorted() }
    private var shelfItems: [Capture] {
        state.store.captures.filter { workspace.shelfCaptureIDs.contains($0.id)
            && (state.libraryProject == nil || $0.projectName == state.libraryProject) }
            .sorted { $0.capturedAt < $1.capturedAt }
    }
    private var hasMetadataFilters: Bool {
        workspace.sourceApplication != nil || workspace.dateFilter != .anytime || workspace.originFilter != .all
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            if let error = workspace.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11)).foregroundStyle(Palette.task)
                    .padding(.horizontal, 16).padding(.bottom, 8)
            }
            if workspace.mode == .scratchpad {
                ScratchpadView(state: state, workspace: workspace)
            } else if workspace.mode == .collection {
                ExplorerScreen(state: state)
            } else {
                itemList
            }
        }
        .alert("New project", isPresented: $showingProjectName) {
            TextField("Client or project name", text: $newProjectName)
            Button("Cancel", role: .cancel) { newProjectName = "" }
            Button("Create") { createProject() }
                .disabled(newProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: { Text("Keep related captures, tasks and notes together. You can file items later.") }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if workspace.mode == .collection {
                    ExplorerProjectPicker(state: state, workspace: workspace, onCreate: { showingProjectName = true })
                } else { Menu {
                    Button("All projects", systemImage: "square.stack.3d.up") { state.libraryProject = nil }
                    ForEach(projects, id: \.self) { project in
                        Button(project, systemImage: "folder") { state.libraryProject = project }
                    }
                    Divider()
                    Button("New project…", systemImage: "folder.badge.plus") { showingProjectName = true }
                } label: {
                    Label(state.libraryProject ?? "All projects", systemImage: "folder")
                        .font(.system(size: 14, weight: .semibold)).lineLimit(1)
                }.menuStyle(.borderlessButton).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Project, \(state.libraryProject ?? "all projects")")
                    .accessibilityIdentifier("workspace-project-picker")
                    .buddyHelp(state.libraryProject ?? "Show captures from all projects")
                }
                if workspace.mode != .scratchpad && workspace.mode != .collection {
                    Text("\(items.count) \(items.count == 1 ? "item" : "items")")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize()
                }
                BuddyIconButton(symbol: "folder.badge.plus", title: "Create project") { showingProjectName = true }
            }
            HStack(spacing: 4) {
                ForEach(WorkspaceMode.allCases) { mode in
                    Button { workspace.mode = mode } label: {
                        HStack(spacing: 4) {
                            Image(systemName: mode.symbol).font(.system(size: 13, weight: .medium)).accessibilityHidden(true)
                            Text(mode.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                        }.frame(maxWidth: .infinity, minHeight: 32)
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                        .foregroundStyle(workspace.mode == mode ? accent : Palette.muted)
                        .background(workspace.mode == mode ? accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(workspace.mode == mode ? accent.opacity(0.28) : .clear))
                        .accessibilityLabel(mode.title).accessibilityIdentifier("workspace-mode-\(mode.rawValue)")
                        .accessibilityAddTraits(workspace.mode == mode ? .isSelected : [])
                        .buddyHelp(mode == .scratchpad ? "Autosaving notes for this project" : "Open \(mode.title)")
                }
            }
            if workspace.mode != .scratchpad {
                HStack(spacing: 4) {
                    ForEach(CaptureFilter.allCases) { filter in
                        BuddyIconButton(symbol: filter.buddySymbol,
                            title: filter == .text ? "Copy/paste text" : filter.title,
                            isActive: state.filter == filter) { state.filter = filter }
                            .accessibilityIdentifier("capture-filter-\(filter.rawValue)")
                            .accessibilityAddTraits(state.filter == filter ? .isSelected : [])
                    }
                    Spacer(minLength: 0)
                    filtersMenu.labelStyle(.iconOnly).menuIndicator(.hidden)
                        .frame(width: 32, height: 32)
                        .background(hasMetadataFilters ? accent.opacity(0.13) : .clear, in: Circle())
                        .buddyHelp("Filter by date, source or capture origin")
                    if workspace.mode == .clipboard {
                        BuddyIconButton(symbol: workspace.snippetsOnly ? "text.badge.star" : "clock.arrow.circlepath",
                            title: workspace.snippetsOnly ? "Show recent clipboard items" : "Show named snippets",
                            isActive: workspace.snippetsOnly) { workspace.snippetsOnly.toggle() }
                            .accessibilityIdentifier("workspace-snippets-toggle")
                    }
                    BuddyIconButton(symbol: "pin", title: "Show pinned captures", isActive: state.libraryPinnedOnly) { state.libraryPinnedOnly.toggle() }
                }
            }
        }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 10)
    }

    private var filtersMenu: some View {
        Menu {
            Menu {
                ForEach(WorkspaceDateFilter.allCases) { value in
                    Button { workspace.dateFilter = value } label: {
                        Label(value.title, systemImage: workspace.dateFilter == value ? "checkmark" : "calendar")
                    }
                }
            } label: { Label("Date: \(workspace.dateFilter.title)", systemImage: "calendar") }
            Menu {
                Button("All applications", systemImage: "square.grid.2x2") { workspace.sourceApplication = nil }
                ForEach(applications, id: \.self) { application in
                    Button { workspace.sourceApplication = application } label: {
                        Label(application, systemImage: workspace.sourceApplication == application ? "checkmark" : "app")
                    }
                }
            } label: { Label(workspace.sourceApplication ?? "Source application", systemImage: "app") }
            Menu {
                ForEach(WorkspaceOriginFilter.allCases) { origin in
                    Button { workspace.originFilter = origin } label: {
                        Label(origin.title, systemImage: workspace.originFilter == origin ? "checkmark" : "arrow.down.doc")
                    }
                }
            } label: { Label(workspace.originFilter.title, systemImage: "arrow.down.doc") }
            if hasMetadataFilters {
                Divider()
                Button("Clear extra filters", systemImage: "line.3.horizontal.decrease.circle") { clearFilters() }
            }
        } label: {
            Label(hasMetadataFilters ? "Filtered" : "Date & source", systemImage: "line.3.horizontal.decrease.circle")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(accent)
        }.menuStyle(.borderlessButton).fixedSize()
            .accessibilityLabel("Filter by date, source application or capture origin")
            .accessibilityIdentifier("workspace-extra-filters")
    }

    private var shelfToolbar: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 12) {
                Button("Paste", systemImage: "doc.on.clipboard") { shelfCapture.paste() }
                Button("Files", systemImage: "plus") { shelfCapture.chooseFiles() }
                Spacer(minLength: 0)
                Button { exportShelf() } label: { Label(exporting ? "Exporting…" : "ZIP", systemImage: "arrow.down.doc") }
                    .disabled(shelfItems.isEmpty || exporting)
                    .buddyHelp("Export \(shelfItems.count) shelf items for this project as a ZIP")
            }.font(.system(size: 12)).disabled(shelfCapture.isBusy)
            Text(shelfCapture.isBusy ? "Saving your items…" : "Drop materials here. Shelf items are saved locally until you remove them from the shelf.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
        }.padding(12).background(accent.opacity(targeted ? 0.13 : 0.04), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(accent.opacity(targeted ? 0.7 : 0.2), style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
            .padding(.horizontal, 16).padding(.bottom, 8)
            .onDrop(of: TaskAttachmentTypes.identifiers, isTargeted: $targeted) { shelfCapture.receive($0) }
            .accessibilityLabel("Collection shelf. Drop, paste or add files.")
    }

    private var itemList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if workspace.mode == .shelf { shelfToolbar }
                    if items.isEmpty {
                        VStack(spacing: 8) {
                            EmptyMessage(symbol: workspace.mode.symbol, title: emptyTitle, message: emptyMessage)
                            if hasMetadataFilters || state.filter != .all || state.libraryPinnedOnly {
                                Button("Clear filters") { clearFilters(); state.filter = .all; state.libraryPinnedOnly = false }
                                    .font(.system(size: 12))
                            }
                        }.padding(.bottom, 14)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12, alignment: .top)], alignment: .leading, spacing: 10) {
                            ForEach(items) { capture in
                                WorkspaceItemCard(state: state, workspace: workspace, capture: capture).id(capture.id)
                            }
                        }.padding(.horizontal, 16).padding(.bottom, 14)
                    }
                }.id("workspace-list-top")
            }.task(id: ScrollContext(project: state.libraryProject, mode: workspace.mode)) {
                // Restore only when navigating. Background copies must not pull
                // the user back to the selected card while they browse elsewhere.
                await Task.yield()
                guard !Task.isCancelled else { return }
                if let selected = workspace.selectedCaptureID, items.contains(where: { $0.id == selected }) {
                    proxy.scrollTo(selected, anchor: .center)
                } else {
                    proxy.scrollTo("workspace-list-top", anchor: .top)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTitle: String {
        if hasMetadataFilters || state.filter != .all || state.libraryPinnedOnly { return "No items match these filters" }
        switch workspace.mode {
        case .collection: return state.libraryProject == nil ? "Your work, easy to find" : "Give this project a home"
        case .clipboard: return workspace.snippetsOnly ? "Keep your best words handy" : "Ready for your next copy"
        case .shelf: return "Gather first. Organize later."
        case .scratchpad: return ""
        }
    }
    private var emptyMessage: String {
        if hasMetadataFilters || state.filter != .all || state.libraryPinnedOnly { return "Clear filters to see the rest of your saved work." }
        switch workspace.mode {
        case .collection: return "Capture a note, file or link, then choose its project. Projects are always optional."
        case .clipboard: return workspace.snippetsOnly ? "Choose Save as snippet on any text or link. Name it once, copy it whenever you need it."
                : "Paste text into DaBin, or enable Auto Capture to save future copies. Existing clipboard contents are never imported at startup."
        case .shelf: return "Paste or add files above, or use Add to shelf on a saved item. Removing a shelf item keeps its library capture."
        case .scratchpad: return ""
        }
    }

    private func clearFilters() { workspace.dateFilter = .anytime; workspace.sourceApplication = nil; workspace.originFilter = .all }
    private func createProject() {
        let name = String(newProjectName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        guard !name.isEmpty else { return }
        do {
            if !projects.contains(name) { try workspace.setScratchpad(text: "", project: name) }
            state.libraryProject = name
            workspace.explorerUnfiledOnly = false
            newProjectName = ""
        } catch { state.reportFailure(error.localizedDescription) }
    }
    private func exportShelf() {
        do {
            let entries = try ShelfExport.entries(for: shelfItems, store: state.store)
            let picker = NSSavePanel()
            picker.allowedContentTypes = [.zip]
            picker.nameFieldStringValue = "DaBin-Collection.zip"
            picker.message = "Exports the full shelf for this project. Your saved items and original files are kept. Choose a new filename."
            guard picker.runModal() == .OK, let destination = picker.url else { return }
            exporting = true
            Task { @MainActor in
                defer { exporting = false }
                let scope = destination.startAccessingSecurityScopedResource()
                defer { if scope { destination.stopAccessingSecurityScopedResource() } }
                do {
                    try await Task.detached(priority: .utility) { try ShelfExport.write(entries, to: destination) }.value
                    state.status = AppStatusMessage(text: "Collection ZIP saved.", severity: .success)
                } catch { state.reportFailure(error.localizedDescription) }
            }
        } catch { state.reportFailure(error.localizedDescription) }
    }
}
