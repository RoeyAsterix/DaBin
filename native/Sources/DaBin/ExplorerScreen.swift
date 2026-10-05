import SwiftUI
import UniformTypeIdentifiers

private struct ExplorerBrowserScope: Equatable {
    let project: String?
    let unfiledOnly: Bool
    let dailyFiles: Bool
    let grouping: ExplorerGrouping
}

/// The saved capture browser shares project, search, and selection across sizes.
/// Grouping changes the presentation; the inspector always shows the real path.
@MainActor struct ExplorerScreen: View {
    @ObservedObject var state: AppState
    let showsSearchEntry: Bool
    @ObservedObject private var workspace: WorkspaceStore
    @ObservedObject private var store: CaptureStore
    @ObservedObject private var intake: ExplorerCaptureController
    @Environment(\.daBinAccent) private var accent
    @State private var targeted = false
    @State private var dailyFiles: [ProjectArchiveDay] = []
    @State private var documentID: String?
    @State private var documentError: String?
    @State private var documentRefreshRevision: UInt = 0
    @State private var exporting = false
    @State private var lastBrowserScope: ExplorerBrowserScope?
    @State private var lastBrowserRestorationRevision: UInt = 0
    @FocusState private var keyboardSelection: UUID?

    init(state: AppState, showsSearchEntry: Bool = true) {
        self.state = state
        self.showsSearchEntry = showsSearchEntry
        _workspace = ObservedObject(wrappedValue: state.workspace)
        _store = ObservedObject(wrappedValue: state.store)
        _intake = ObservedObject(wrappedValue: state.explorerInput)
    }

    private var scopeKey: String {
        (state.libraryProject ?? "") + ":" + String(workspace.explorerUnfiledOnly)
            + ":" + workspace.explorerGrouping.rawValue + ":" + String(state.navigationRestorationRevision)
            + ":" + String(workspace.explorerShowsDailyFiles)
    }
    private var browserScope: ExplorerBrowserScope {
        ExplorerBrowserScope(project: state.libraryProject, unfiledOnly: workspace.explorerUnfiledOnly,
            dailyFiles: workspace.explorerShowsDailyFiles, grouping: workspace.explorerGrouping)
    }
    private var isDeliberateBrowserChange: Bool {
        lastBrowserScope.map { $0 != browserScope } == true
            && lastBrowserRestorationRevision == state.navigationRestorationRevision
    }
    private var documentRefreshKey: ExplorerDocumentRefreshKey {
        ExplorerDocumentRefreshKey(project: state.libraryProject, unfiledOnly: workspace.explorerUnfiledOnly,
            enabled: workspace.explorerShowsDailyFiles, revision: documentRefreshRevision)
    }
    private var presentation: ExplorerPresentation {
        let items = ExplorerQuery.items(store.captures, workspace: workspace, project: state.libraryProject,
            filter: state.filter, pinnedOnly: state.libraryPinnedOnly, query: "")
        let sections = workspace.explorerShowsDailyFiles ? [] : ExplorerQuery.sections(items, grouping: workspace.explorerGrouping)
        let matchingDays = workspace.explorerShowsDailyFiles ? Set(ExplorerQuery.projectDays(items, in: store.captures)) : []
        let visibleDays = dailyFiles.filter { matchingDays.contains(ExplorerProjectDay(projectName: $0.projectName, day: $0.captureDay)) }
        return ExplorerPresentation(items: items, sections: sections, orderedItems: sections.flatMap(\.captures),
            selected: items.first { $0.id == workspace.selectedCaptureID }, dailyFiles: visibleDays,
            selectedDocument: visibleDays.first { $0.id == documentID })
    }

    var body: some View {
        let presentation = presentation
        return VStack(spacing: 0) {
            toolbar
            if let error = documentError {
                HStack {
                    Label(error, systemImage: "exclamationmark.triangle").font(.system(size: 11)).foregroundStyle(Palette.task)
                    Button("Retry") { documentRefreshRevision &+= 1 }.font(.system(size: 11))
                }.padding(.horizontal, 16).padding(.bottom, 6)
            }
            GeometryReader { geometry in
                let expanded = geometry.size.width > 700
                HStack(spacing: 0) {
                    browser(expanded: expanded, presentation: presentation)
                        .frame(width: expanded ? min(400, geometry.size.width * 0.4) : nil)
                    if expanded {
                        Rectangle().fill(Palette.line).frame(width: 1)
                        inspector(height: geometry.size.height, presentation: presentation)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .accessibilityIdentifier("explorer-inspector")
                    }
                }
            }
            footer(presentation: presentation)
        }
        .background(accent.opacity(targeted ? 0.055 : 0))
        .overlay { if targeted { RoundedRectangle(cornerRadius: 12).strokeBorder(accent, lineWidth: 2).allowsHitTesting(false) } }
        .onDrop(of: ExplorerTransfer.acceptedTypeIdentifiers, isTargeted: $targeted) {
            intake.receive($0, project: state.libraryProject)
        }
        .onCopyCommand {
            do {
                if workspace.explorerShowsDailyFiles, let day = presentation.selectedDocument {
                    return [try ExplorerTransfer.documentProvider(url: day.url)]
                }
                if !workspace.explorerShowsDailyFiles, let selected = presentation.selected {
                    return [try ExplorerTransfer.itemProvider(for: selected, store: store, includeInternalReference: false)]
                }
            } catch { state.reportFailure(error.localizedDescription) }
            return []
        }
        .task(id: documentRefreshKey) { await refreshDocuments() }
        .onChange(of: keyboardSelection) { _, id in
            if let id { workspace.selectedCaptureID = id }
        }
        .onReceive(store.objectWillChange.debounce(for: .milliseconds(100), scheduler: RunLoop.main)) { _ in
            if workspace.explorerShowsDailyFiles { documentRefreshRevision &+= 1 }
        }
        .accessibilityElement(children: .contain).accessibilityLabel("Explorer")
        .accessibilityIdentifier("explorer-browser")
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            if showsSearchEntry {
                Button { state.performSearchCommand() } label: {
                    Label("Search everything", systemImage: "magnifyingglass")
                        .font(.system(size: 13)).foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Search everything saved in DaBin")
                    .accessibilityIdentifier("explorer-search")
                    .padding(8).background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.line))
            }
            BuddyIconButton(symbol: "doc.on.clipboard", title: "Paste") { intake.paste(project: state.libraryProject) }
                .accessibilityIdentifier("explorer-paste")
            BuddyIconButton(symbol: "folder", title: "Open folder") { state.showProjectFiles() }
                .accessibilityIdentifier("explorer-open-files")
            BuddyIconButton(symbol: "folder.badge.plus", title: "Add files") { intake.chooseFiles(project: state.libraryProject) }
                .accessibilityIdentifier("explorer-add-files")
        }.disabled(intake.isBusy || state.isArchiveOperationRunning)
            .padding(.horizontal, 16).padding(.bottom, 8)
    }

    private var groupingMenu: some View {
        Menu {
            ForEach(ExplorerGrouping.allCases) { grouping in
                Button { workspace.explorerGrouping = grouping } label: {
                    Label("Group by \(grouping.title.lowercased())", systemImage: workspace.explorerGrouping == grouping ? "checkmark" : grouping.symbol)
                }
            }
        } label: { Image(systemName: workspace.explorerGrouping.symbol).frame(width: 28, height: 32) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().foregroundStyle(Palette.muted)
            .accessibilityLabel("Group by \(workspace.explorerGrouping.title.lowercased())")
            .buddyHelp("Group by type or date")
    }

    private func browser(expanded: Bool, presentation: ExplorerPresentation) -> some View {
        ScrollViewReader { proxy in
            // Native list rows keep rich card subtrees scoped to the viewport.
            // Each identity has one fixed root, even when switching grouping.
            List {
                Group {
                    if workspace.explorerShowsDailyFiles {
                        if presentation.dailyFiles.isEmpty { empty }
                        ForEach(presentation.dailyFiles) { day in
                            dailyRow(day, expanded: expanded)
                        }
                    } else if presentation.items.isEmpty { empty }
                    else {
                        // Each lazy-list identity owns exactly one visible row.
                        // A section must not expand into a changing number of
                        // sibling views while automatic captures are prepended.
                        ForEach(presentation.browserRows) { row in
                            VStack(alignment: .leading, spacing: 0) {
                                switch row {
                                case .section(let section):
                                    HStack {
                                        Label(section.title, systemImage: section.symbol)
                                        Spacer()
                                        Text("\(section.captures.count)")
                                    }.font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.muted)
                                        .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 5)
                                case .capture(let capture):
                                    ExplorerCaptureRow(state: state, workspace: workspace, capture: capture, focus: $keyboardSelection) {
                                        workspace.selectedCaptureID = capture.id
                                        // A plain button inside macOS List can
                                        // select without becoming a keyboard
                                        // responder. Keep arrows/Return on the
                                        // chosen card instead of the window.
                                        keyboardSelection = capture.id
                                        if !expanded { state.openCapture(capture.id) }
                                    }
                                        .onMoveCommand { direction in
                                            let ordered = presentation.orderedItems
                                            guard direction == .up || direction == .down,
                                                  let index = ordered.firstIndex(where: { $0.id == (workspace.selectedCaptureID ?? capture.id) }) else { return }
                                            let target = min(ordered.count - 1, max(0, index + (direction == .down ? 1 : -1)))
                                            workspace.selectedCaptureID = ordered[target].id
                                            keyboardSelection = ordered[target].id
                                            proxy.scrollTo(ExplorerBrowserRow.captureID(ordered[target].id), anchor: .center)
                                        }
                                        .onKeyPress(.return) {
                                            state.openCapture(workspace.selectedCaptureID ?? capture.id)
                                            return .handled
                                        }
                                }
                            }
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            // Incoming captures must not animate estimated native row heights
            // while the user reads an existing card away from the list's top.
            // Keep this local to the browser; robot/window motion is unaffected.
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
            .background {
                ExplorerViewport(store: store, rowIDs: workspace.explorerShowsDailyFiles
                    ? presentation.dailyFiles.map(\.id) : presentation.browserRows.map(\.id),
                    context: ExplorerViewportContext(project: state.libraryProject,
                        unfiledOnly: workspace.explorerUnfiledOnly, dailyFiles: workspace.explorerShowsDailyFiles,
                        query: "", filter: state.filter.rawValue,
                        pinnedOnly: state.libraryPinnedOnly, dateFilter: workspace.dateFilter.rawValue,
                        source: workspace.sourceApplication, origin: workspace.originFilter.rawValue,
                        grouping: workspace.explorerGrouping.rawValue, selectedID: workspace.selectedCaptureID),
                    historyAnchor: isDeliberateBrowserChange ? nil : state.workspaceViewport,
                    onHistoryAnchor: { state.workspaceViewport = $0 })
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            .task(id: scopeKey) {
                // An explicit project/grouping change keeps its remembered
                // selected item in view. Back
                // and Forward restore their own item/offset instead, including
                // when that snapshot also changes the grouping.
                let changed = isDeliberateBrowserChange
                lastBrowserScope = browserScope
                lastBrowserRestorationRevision = state.navigationRestorationRevision
                if changed { state.workspaceViewport = nil }
                await Task.yield()
                guard !Task.isCancelled, changed || state.workspaceViewport == nil else { return }
                if !workspace.explorerShowsDailyFiles, let id = workspace.selectedCaptureID,
                   presentation.items.contains(where: { $0.id == id }) {
                    proxy.scrollTo(ExplorerBrowserRow.captureID(id), anchor: .center)
                } else if let first = workspace.explorerShowsDailyFiles
                    ? presentation.dailyFiles.first?.id : presentation.browserRows.first?.id {
                    proxy.scrollTo(first, anchor: .top)
                }
            }
            // Regrouping deliberately changes the whole row order. Recreate
            // the native table (and viewport coordinator) instead of asking
            // AppKit to move every variable-height row inside its delegate.
            // Normal capture insertions keep the same table and stable IDs.
            .id(workspace.explorerGrouping)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var empty: some View {
        VStack(spacing: 8) {
            EmptyMessage(symbol: "folder", title: "A home for your next idea",
                message: "Drop files, paste a link or save a note. Your project’s files stay organized locally.")
            if state.filter != .all || state.libraryPinnedOnly || workspace.dateFilter != .anytime
                || workspace.sourceApplication != nil || workspace.originFilter != .all {
                Button("Clear filters") {
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
                .projectCardFrame(workspace: workspace, projectName: day.projectName,
                                  activeProject: state.libraryProject, cornerRadius: 10,
                                  fallbackColor: .clear, fallbackWidth: 0)
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

    @ViewBuilder private func inspector(height: CGFloat, presentation: ExplorerPresentation) -> some View {
        if workspace.explorerShowsDailyFiles, let day = presentation.selectedDocument {
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
                    ExplorerDailyPreview(url: day.url, revision: documentRefreshRevision)
                    Text(day.url.path).font(.system(size: 10)).foregroundStyle(Palette.muted).textSelection(.enabled)
                }.padding(20)
            }
        } else if !workspace.explorerShowsDailyFiles, let capture = presentation.selected {
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

    private func footer(presentation: ExplorerPresentation) -> some View {
        HStack(spacing: 7) {
            Text(intake.isBusy ? "Saving…" : "\(presentation.items.count) items").font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
            Button { workspace.explorerShowsDailyFiles.toggle() } label: {
                Label("Daily files", systemImage: "doc.text").font(.system(size: 11)).frame(minHeight: 32)
            }.buttonStyle(.plain).foregroundStyle(workspace.explorerShowsDailyFiles ? accent : Palette.muted)
                .accessibilityAddTraits(workspace.explorerShowsDailyFiles ? .isSelected : [])
                .accessibilityIdentifier("explorer-daily-files")
                .buddyHelp("One complete dated file for each project day")
            if !workspace.explorerShowsDailyFiles { groupingMenu }
            if intake.canUndoMove {
                BuddyIconButton(symbol: "arrow.uturn.backward", title: "Undo move") { intake.undoLastMove() }
                    .accessibilityIdentifier("explorer-undo-move")
            }
            Spacer(minLength: 0)
            Button { exportZIP(presentation: presentation) } label: {
                Label(exporting ? "Exporting…" : "Export visible", systemImage: "arrow.down.to.line")
                    .font(.system(size: 11)).lineLimit(1).fixedSize().frame(minHeight: 32)
            }.buttonStyle(.plain).foregroundStyle(accent)
                .accessibilityLabel("Export visible items as ZIP")
                .accessibilityIdentifier("explorer-export-visible")
                .buddyHelp("Save the items shown by your current filters as a ZIP")
                .disabled((workspace.explorerShowsDailyFiles ? presentation.dailyFiles.isEmpty : presentation.items.isEmpty) || exporting || intake.isBusy)
        }.padding(.horizontal, 12).padding(.vertical, 3).background(Palette.surface).overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
    }

    private func refreshDocuments() async {
        guard workspace.explorerShowsDailyFiles else { documentError = nil; return }
        let project = state.libraryProject
        let unfiledOnly = workspace.explorerUnfiledOnly
        let days = ExplorerQuery.projectDays(store.captures, in: store.captures)
        let archive = DailyArchive(root: store.root)
        do {
            let documents = try await Task.detached(priority: .userInitiated) {
                try ExplorerQuery.dailyDocuments(days, archive: archive, project: project, unfiledOnly: unfiledOnly)
            }.value
            guard !Task.isCancelled else { return }
            dailyFiles = documents
            documentError = nil
        } catch { if !Task.isCancelled { documentError = error.localizedDescription } }
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
    private func exportZIP(presentation: ExplorerPresentation) {
        do {
            let entries = try workspace.explorerShowsDailyFiles
                ? presentation.dailyFiles.map { day in
                    ShelfExportEntry(name: day.captureDay + " - " + (ProjectFileArchive.projectRelativePath(day.projectName) as NSString).lastPathComponent + ".md", source: day.url, text: nil)
                }
                : ShelfExport.entries(for: presentation.items, store: store)
            let panel = NSSavePanel(); panel.allowedContentTypes = [.zip]; panel.nameFieldStringValue = "DaBin-Explorer.zip"
            panel.title = "Export visible items"
            panel.prompt = "Save ZIP"
            panel.message = "Visible items only · \(entries.count) \(entries.count == 1 ? "item" : "items"). Current filters apply."
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

private struct ExplorerPresentation {
    let items: [Capture]
    let sections: [ExplorerSection]
    let orderedItems: [Capture]
    let selected: Capture?
    let dailyFiles: [ProjectArchiveDay]
    let selectedDocument: ProjectArchiveDay?

    var browserRows: [ExplorerBrowserRow] {
        sections.flatMap { [.section($0)] + $0.captures.map(ExplorerBrowserRow.capture) }
    }
}

private enum ExplorerBrowserRow: Identifiable {
    case section(ExplorerSection)
    case capture(Capture)

    var id: String {
        switch self {
        case .section(let section): "section:\(section.id)"
        case .capture(let capture): Self.captureID(capture.id)
        }
    }

    static func captureID(_ id: UUID) -> String { "capture:\(id.uuidString)" }
}

private struct ExplorerDocumentRefreshKey: Hashable {
    let project: String?
    let unfiledOnly: Bool
    let enabled: Bool
    let revision: UInt
}

private struct ExplorerDailyPreview: View {
    let url: URL
    let revision: UInt
    @State private var text = "Loading daily file…"

    var body: some View {
        Text(text).font(.system(size: 13)).textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .task(id: url.path + ":" + String(revision)) {
                text = "Loading daily file…"
                let preview = await Task.detached(priority: .userInitiated) { Self.load(url) }.value
                guard !Task.isCancelled else { return }
                text = preview
            }
    }

    /// Read only when the selection or saved document changes, with a bounded
    /// preview. Opening/copying still transfers the complete daily document.
    private nonisolated static func load(_ url: URL) -> String {
        do {
            try OriginalFileStorage.validateRegularFile(url)
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: 64_000) ?? Data()
            return String(decoding: data, as: UTF8.self) + (data.count == 64_000 ? "\n\nPreview shortened. Open the daily file to read everything." : "")
        } catch { return "The daily file is unavailable. Try refreshing the archive." }
    }
}
