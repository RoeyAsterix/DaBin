import SwiftUI
import UniformTypeIdentifiers

/// The saved capture browser shares project, search, and selection across sizes.
/// Grouping changes the presentation; the inspector always shows the real path.
@MainActor struct ExplorerScreen: View {
    @ObservedObject var state: AppState
    @ObservedObject private var workspace: WorkspaceStore
    @ObservedObject private var store: CaptureStore
    @ObservedObject private var intake: ExplorerCaptureController
    @Environment(\.daBinAccent) private var accent
    @State private var targeted = false
    @State private var dailyFiles: [ProjectArchiveDay] = []
    @State private var documentID: String?
    @State private var documentError: String?
    @State private var exporting = false
    @FocusState private var keyboardSelection: UUID?

    init(state: AppState) {
        self.state = state
        _workspace = ObservedObject(wrappedValue: state.workspace)
        _store = ObservedObject(wrappedValue: state.store)
        _intake = ObservedObject(wrappedValue: state.explorerInput)
    }

    private var items: [Capture] {
        ExplorerQuery.items(store.captures, workspace: workspace, project: state.libraryProject,
                            filter: state.filter, pinnedOnly: state.libraryPinnedOnly)
    }
    private var sections: [ExplorerSection] { ExplorerQuery.sections(items, grouping: workspace.explorerGrouping) }
    private var selected: Capture? { items.first { $0.id == workspace.selectedCaptureID } }
    private var selectedDocument: ProjectArchiveDay? { visibleDailyFiles.first { $0.id == documentID } }
    private var scopeKey: String { (state.libraryProject ?? "") + ":" + String(workspace.explorerUnfiledOnly) }
    private var visibleDailyFiles: [ProjectArchiveDay] {
        let matching = Set(items.map { ProjectDayKey(projectName: ExplorerQuery.project(of: $0, in: store.captures), day: $0.captureDay) })
        return dailyFiles.filter { matching.contains(ProjectDayKey(projectName: $0.projectName, day: $0.captureDay)) }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if let error = documentError {
                HStack {
                    Label(error, systemImage: "exclamationmark.triangle").font(.system(size: 11)).foregroundStyle(Palette.task)
                    Button("Retry") { refreshDocuments() }.font(.system(size: 11))
                }.padding(.horizontal, 16).padding(.bottom, 6)
            }
            GeometryReader { geometry in
                let expanded = geometry.size.width >= 760
                HStack(spacing: 0) {
                    browser(expanded: expanded)
                        .frame(width: expanded ? min(400, geometry.size.width * 0.4) : nil)
                    if expanded {
                        Rectangle().fill(Palette.line).frame(width: 1)
                        inspector(height: geometry.size.height)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .accessibilityIdentifier("explorer-inspector")
                    }
                }
            }
            footer
        }
        .background(accent.opacity(targeted ? 0.055 : 0))
        .overlay { if targeted { RoundedRectangle(cornerRadius: 12).strokeBorder(accent, lineWidth: 2).allowsHitTesting(false) } }
        .onDrop(of: ExplorerTransfer.acceptedTypeIdentifiers, isTargeted: $targeted) {
            intake.receive($0, project: state.libraryProject)
        }
        .onCopyCommand {
            do {
                if workspace.explorerShowsDailyFiles, let day = selectedDocument {
                    return [try ExplorerTransfer.documentProvider(url: day.url)]
                }
                if !workspace.explorerShowsDailyFiles, let selected {
                    return [try ExplorerTransfer.itemProvider(for: selected, store: store, includeInternalReference: false)]
                }
            } catch { state.reportFailure(error.localizedDescription) }
            return []
        }
        .task(id: scopeKey) { refreshDocuments() }
        .onChange(of: keyboardSelection) { _, id in
            if let id { workspace.selectedCaptureID = id }
        }
        .onReceive(store.objectWillChange) { _ in
            Task { @MainActor in await Task.yield(); refreshDocuments() }
        }
        .accessibilityElement(children: .contain).accessibilityLabel("Explorer")
        .accessibilityIdentifier("explorer-browser")
    }

    private var toolbar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted).accessibilityHidden(true)
                TextField("Find in this project", text: Binding(get: { workspace.explorerQuery }, set: { workspace.explorerQuery = $0 }))
                    .textFieldStyle(.plain).font(.system(size: 12)).accessibilityLabel("Search Explorer")
                    .accessibilityIdentifier("explorer-search")
                if !workspace.explorerQuery.isEmpty {
                    Button { workspace.explorerQuery = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Palette.muted).accessibilityLabel("Clear Explorer search")
                }
            }.padding(8).background(Palette.surface, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Palette.line))
            HStack(spacing: 6) {
                Button("Paste", systemImage: "doc.on.clipboard") { intake.paste(project: state.libraryProject) }
                    .accessibilityIdentifier("explorer-paste")
                Button("Files", systemImage: "plus") { intake.chooseFiles(project: state.libraryProject) }
                    .accessibilityIdentifier("explorer-add-files")
                Spacer(minLength: 0)
                Button { workspace.explorerShowsDailyFiles.toggle() } label: {
                    Label("Daily files", systemImage: "doc.text")
                }.foregroundStyle(workspace.explorerShowsDailyFiles ? accent : Palette.muted)
                    .accessibilityAddTraits(workspace.explorerShowsDailyFiles ? .isSelected : [])
                    .accessibilityIdentifier("explorer-daily-files")
                    .buddyHelp("One dated file per project, with the full day’s captures, links, comments and tasks")
                Menu {
                    ForEach(ExplorerGrouping.allCases) { grouping in
                        Button { workspace.explorerGrouping = grouping } label: {
                            Label("Group by \(grouping.title.lowercased())", systemImage: workspace.explorerGrouping == grouping ? "checkmark" : grouping.symbol)
                        }
                    }
                } label: { Image(systemName: workspace.explorerGrouping.symbol).frame(width: 25, height: 26) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel("Group by \(workspace.explorerGrouping.title.lowercased())")
                    .buddyHelp("Group by type or date").disabled(workspace.explorerShowsDailyFiles)
            }.font(.system(size: 12, weight: .medium)).buttonStyle(.plain).foregroundStyle(accent)
                .disabled(intake.isBusy || state.isArchiveOperationRunning)
        }.padding(.horizontal, 16).padding(.bottom, 8)
    }

    private func browser(expanded: Bool) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if workspace.explorerShowsDailyFiles {
                        if visibleDailyFiles.isEmpty { empty }
                        ForEach(visibleDailyFiles) { day in
                            dailyRow(day, expanded: expanded)
                        }
                    } else if items.isEmpty { empty }
                    else {
                        ForEach(sections) { section in
                            HStack {
                                Label(section.title, systemImage: section.symbol)
                                Spacer()
                                Text("\(section.captures.count)")
                            }.font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.muted)
                                .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 5)
                            ForEach(section.captures) { capture in
                                ExplorerCaptureRow(state: state, workspace: workspace, capture: capture, focus: $keyboardSelection) {
                                    workspace.selectedCaptureID = capture.id
                                    if !expanded { state.openCapture(capture.id) }
                                }.id(capture.id)
                                    .onMoveCommand { direction in
                                        let ordered = sections.flatMap(\.captures)
                                        guard direction == .up || direction == .down,
                                              let index = ordered.firstIndex(where: { $0.id == (workspace.selectedCaptureID ?? capture.id) }) else { return }
                                        let target = min(ordered.count - 1, max(0, index + (direction == .down ? 1 : -1)))
                                        workspace.selectedCaptureID = ordered[target].id
                                        keyboardSelection = ordered[target].id
                                        proxy.scrollTo(ordered[target].id, anchor: .center)
                                    }
                                    .onKeyPress(.return) {
                                        state.openCapture(workspace.selectedCaptureID ?? capture.id)
                                        return .handled
                                    }
                            }
                        }
                    }
                }.padding(.horizontal, 8).padding(.bottom, 10).id("explorer-top")
            }.task(id: scopeKey) {
                await Task.yield()
                guard !Task.isCancelled else { return }
                if let id = workspace.selectedCaptureID, items.contains(where: { $0.id == id }) {
                    proxy.scrollTo(id, anchor: .center)
                } else { proxy.scrollTo("explorer-top", anchor: .top) }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var empty: some View {
        VStack(spacing: 8) {
            EmptyMessage(symbol: "folder", title: "A home for your next idea",
                message: "Drop files, paste a link or save a note. Your project’s files stay organized locally.")
            if state.filter != .all || !workspace.explorerQuery.isEmpty || state.libraryPinnedOnly || workspace.dateFilter != .anytime
                || workspace.sourceApplication != nil || workspace.originFilter != .all {
                Button("Clear filters and search") {
                    state.filter = .all; state.libraryPinnedOnly = false; workspace.explorerQuery = ""
                    workspace.dateFilter = .anytime; workspace.sourceApplication = nil; workspace.originFilter = .all
                }.font(.system(size: 12)).padding(.bottom, 10)
            }
        }.frame(maxWidth: .infinity)
    }

    private func dailyRow(_ day: ProjectArchiveDay, expanded: Bool) -> some View {
        Button {
            documentID = day.id
            if !expanded { openDocument(day) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.text").font(.system(size: 23)).foregroundStyle(accent).frame(width: 38)
                VStack(alignment: .leading, spacing: 4) {
                    Text(day.captureDay + " · Captures and Links").font(.system(size: 13, weight: .medium)).lineLimit(2)
                    Text("\(day.projectName ?? "Unfiled") · \(day.captureCount) actions")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(documentID == day.id ? accent.opacity(0.1) : Palette.surface, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).accessibilityLabel("Daily file, \(day.captureDay), \(day.projectName ?? "Unfiled")")
            .accessibilityIdentifier("explorer-day-\(day.id)")
            .onDrag { documentProvider(day) }
            .contextMenu {
                Button("Open daily file", systemImage: "doc.text") { openDocument(day) }
                Button("Copy daily file", systemImage: "doc.on.doc") { copyDocument(day) }
                Button("Reveal in Finder", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([day.url]) }
                Button("Copy path", systemImage: "link") { copyPath(day.url) }
            }
    }

    @ViewBuilder private func inspector(height: CGFloat) -> some View {
        if workspace.explorerShowsDailyFiles, let day = selectedDocument {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Label(day.captureDay, systemImage: "doc.text").font(.system(size: 20, weight: .semibold))
                    Text("\(day.projectName ?? "Unfiled") · Complete daily record").foregroundStyle(Palette.muted)
                    HStack {
                        Button("Open", systemImage: "arrow.up.forward.square") { openDocument(day) }
                        Button("Copy file", systemImage: "doc.on.doc") { copyDocument(day) }
                    }.font(.system(size: 12))
                    Text("Updates when you edit captures in DaBin. Outside edits are preserved before the file is refreshed.")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    Text(dailyPreview(day.url))
                        .font(.system(size: 13)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    Text(day.url.path).font(.system(size: 10)).foregroundStyle(Palette.muted).textSelection(.enabled)
                }.padding(20)
            }
        } else if !workspace.explorerShowsDailyFiles, let capture = selected {
            ExplorerInspector(state: state, workspace: workspace, capture: capture, height: height)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "sidebar.right").font(.system(size: 30, weight: .light)).foregroundStyle(accent)
                Text("Choose an item to preview").font(.system(size: 15, weight: .medium))
                Text("Drag a file, link or text straight into your working app.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
            }.padding(24)
        }
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Text(intake.isBusy ? "Saving…" : "\(items.count) items · Saved locally").font(.system(size: 10)).foregroundStyle(Palette.muted)
            if intake.canUndoMove { Button("Undo move") { intake.undoLastMove() }.font(.system(size: 11)) }
            Spacer(minLength: 0)
            BuddyIconButton(symbol: "arrow.down.doc", title: exporting ? "Creating ZIP" : "Export visible items as ZIP") { exportZIP() }
                .disabled((workspace.explorerShowsDailyFiles ? visibleDailyFiles.isEmpty : items.isEmpty) || exporting || intake.isBusy)
            BuddyIconButton(symbol: "folder", title: "Open this project in Finder") { revealScope() }
        }.padding(.horizontal, 12).padding(.vertical, 3).overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
    }

    private func refreshDocuments() {
        do {
            dailyFiles = try store.explorerDocuments(project: state.libraryProject, unfiledOnly: workspace.explorerUnfiledOnly)
            documentError = nil
        } catch { documentError = error.localizedDescription }
    }
    private func dailyPreview(_ url: URL) -> String {
        // Keep the inspector responsive for long days. Opening/copying transfers
        // the complete document, with no truncation of the saved file.
        do {
            try OriginalFileStorage.validateRegularFile(url)
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: 64_000) ?? Data()
            return String(decoding: data, as: UTF8.self) + (data.count == 64_000 ? "\n\nPreview shortened. Open the daily file to read everything." : "")
        } catch { return "The daily file is unavailable. Try refreshing the archive." }
    }
    private func revealScope() {
        do {
            let url = state.libraryProject == nil && !workspace.explorerUnfiledOnly ? store.explorerRootURL
                : try store.explorerFolderURL(project: state.libraryProject)
            if !NSWorkspace.shared.open(url) { state.reportFailure("Finder couldn’t open this folder.") }
        } catch { state.reportFailure(error.localizedDescription) }
    }
    private func openDocument(_ day: ProjectArchiveDay) {
        if !NSWorkspace.shared.open(day.url) { state.reportFailure("The daily file could not be opened.") }
    }
    private func copyDocument(_ day: ProjectArchiveDay) {
        do {
            try OriginalFileStorage.validateRegularFile(day.url)
            NSPasteboard.general.clearContents()
            guard NSPasteboard.general.writeObjects([day.url as NSURL]) else { throw CaptureClipboardError.writeFailed }
            state.status = AppStatusMessage(text: "Daily file copied.", severity: .success)
        } catch { state.reportFailure(error.localizedDescription) }
    }
    private func copyPath(_ url: URL) {
        do { try WorkspaceClipboard.write(url.path); state.status = AppStatusMessage(text: "Path copied.", severity: .success) }
        catch { state.reportFailure(error.localizedDescription) }
    }
    private func documentProvider(_ day: ProjectArchiveDay) -> NSItemProvider {
        do { return try ExplorerTransfer.documentProvider(url: day.url) }
        catch { state.reportFailure(error.localizedDescription); return NSItemProvider() }
    }
    private func exportZIP() {
        do {
            let entries = try workspace.explorerShowsDailyFiles
                ? visibleDailyFiles.map { day in
                    ShelfExportEntry(name: day.captureDay + " - " + (ProjectFileArchive.projectRelativePath(day.projectName) as NSString).lastPathComponent + ".md", source: day.url, text: nil)
                }
                : ShelfExport.entries(for: items, store: store)
            let panel = NSSavePanel(); panel.allowedContentTypes = [.zip]; panel.nameFieldStringValue = "DaBin-Explorer.zip"
            panel.message = "Copies the visible items into a ZIP. Choose a new filename."
            guard panel.runModal() == .OK, let url = panel.url else { return }
            exporting = true
            Task { @MainActor in
                defer { exporting = false }
                let scope = url.startAccessingSecurityScopedResource()
                defer { if scope { url.stopAccessingSecurityScopedResource() } }
                do {
                    try await Task.detached(priority: .utility) { try ShelfExport.write(entries, to: url) }.value
                    state.status = AppStatusMessage(text: "Explorer ZIP saved.", severity: .success)
                } catch { state.reportFailure(error.localizedDescription) }
            }
        } catch { state.reportFailure(error.localizedDescription) }
    }
}

private struct ProjectDayKey: Hashable {
    let projectName: String?
    let day: String
}
