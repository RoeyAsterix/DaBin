import SwiftUI
import Combine
import UniformTypeIdentifiers

/// One project, including task attachments and its live scratchpad. The grid
/// uses recycled native List rows; no hidden inspector or offscreen thumbnails.
enum ProjectWorkspaceItem: Identifiable {
    case capture(Capture), note(WorkspaceScratchpad)
    var id: String {
        switch self {
        case .capture(let capture): return "capture:" + capture.id.uuidString
        case .note(let note): return "note:" + WorkspaceSnapshot.projectKey(note.projectName)
        }
    }
    var date: Date {
        switch self { case .capture(let capture): return capture.capturedAt; case .note(let note): return note.updatedAt }
    }
    var capture: Capture? { if case .capture(let capture) = self { return capture }; return nil }
    var title: String {
        switch self {
        case .capture(let capture): return capture.title.isEmpty ? "Untitled capture" : capture.title
        case .note: return "Project notes"
        }
    }
}

private enum ProjectWorkspaceFilter: String, CaseIterable, Identifiable {
    case all = "All", files = "Files", captures = "Captures & notes", links = "Links", tasks = "Tasks"
    var id: String { rawValue }
    @MainActor func includes(_ item: ProjectWorkspaceItem) -> Bool {
        guard self != .all else { return true }
        guard let capture = item.capture else { return self == .captures }
        switch self {
        case .all: return true
        case .files: return ![CaptureKind.text, .task, .link].contains(capture.kind)
        case .captures: return capture.kind == .text
        case .links: return capture.kind == .link
        case .tasks: return capture.isTask
        }
    }
}

private struct ProjectWorkspaceRow: Identifiable {
    let id: String
    let items: [ProjectWorkspaceItem]
}

private struct ProjectWorkspaceRows {
    let rows: [ProjectWorkspaceRow]
    let rowIDs: [String]
    let groups: [[String]]
}

/// Keep sorting/filtering work tied to archive/workspace changes, not every
/// magnification tick. Cached rows retain Capture identities and native List
/// virtualization; thumbnail requests remain independent of layout scale.
@MainActor private final class ProjectWorkspaceContentCache {
    private var subscriptions: [AnyCancellable] = []
    private var key: String?
    private var value: [ProjectWorkspaceItem] = []
    private var visibleKey: String?
    private var visibleValue: [ProjectWorkspaceItem] = []
    private(set) var visibleIDs: [String] = []
    private var visibleLookup: [String: ProjectWorkspaceItem] = [:]
    private var selectedIDs: Set<String>?
    private var selectedItems: [ProjectWorkspaceItem] = []
    private struct RowKey: Hashable { var columns: Int; var newestFirst: Bool }
    private var layouts: [RowKey: ProjectWorkspaceRows] = [:]
    init(store: CaptureStore, workspace: WorkspaceStore) {
        subscriptions = [store.objectWillChange.sink { [weak self] _ in self?.invalidate() },
                         workspace.objectWillChange.sink { [weak self] _ in self?.invalidate() }]
    }
    private func invalidate() { key = nil; visibleKey = nil }
    func items(key: String, build: () -> [ProjectWorkspaceItem]) -> [ProjectWorkspaceItem] {
        if self.key != key { value = build(); self.key = key; visibleKey = nil }
        return value
    }
    func visible(key: String, build: () -> [ProjectWorkspaceItem]) -> [ProjectWorkspaceItem] {
        if visibleKey != key {
            visibleValue = build(); visibleKey = key
            // UUID string formatting is surprisingly expensive at archive
            // scale. Build identity/lookup storage once, not for every pinch.
            visibleIDs = visibleValue.map(\.id)
            visibleLookup = Dictionary(uniqueKeysWithValues: zip(visibleIDs, visibleValue))
            layouts.removeAll(keepingCapacity: true)
            selectedIDs = nil; selectedItems = []
        }
        return visibleValue
    }
    func selected(_ ids: Set<String>) -> [ProjectWorkspaceItem] {
        guard !ids.isEmpty else { return [] }
        if selectedIDs != ids {
            selectedIDs = ids
            selectedItems = visibleIDs.compactMap { ids.contains($0) ? visibleLookup[$0] : nil }
        }
        return selectedItems
    }
    func layout(columns: Int, newestFirst: Bool) -> ProjectWorkspaceRows {
        // Workspace column policy permits only these three variants. Bound
        // the cache even if a malformed future caller passes another number.
        let key = RowKey(columns: min(3, max(1, columns)), newestFirst: newestFirst)
        if let cached = layouts[key] { return cached }
        let groups = ProjectWorkspaceOrdering.rows(ids: visibleIDs, columns: key.columns, newestFirst: newestFirst)
        let rows = groups.map { group in
            ProjectWorkspaceRow(id: group[0], items: group.compactMap { visibleLookup[$0] })
        }
        let result = ProjectWorkspaceRows(rows: rows, rowIDs: rows.map(\.id), groups: groups)
        layouts[key] = result
        return result
    }
}

/// A local reorder marker supplements the first item's public content. It must
/// never replace that content or leak the project name into an external drop.
private final class ProjectReorderWriter: NSObject, NSPasteboardWriting {
    let content: NSPasteboardWriting
    let marker: NSPasteboard.PasteboardType
    init(content: NSPasteboardWriting, type: String) {
        self.content = content; self.marker = .init(type)
    }
    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        content.writableTypes(for: pasteboard) + [marker]
    }
    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        type == marker ? Data("reorder".utf8) : content.pasteboardPropertyList(forType: type)
    }
    func writingOptions(forType type: NSPasteboard.PasteboardType, pasteboard: NSPasteboard) -> NSPasteboard.WritingOptions {
        type == marker ? [] : content.writingOptions?(forType: type, pasteboard: pasteboard) ?? []
    }
}

@MainActor struct ProjectWorkspaceView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var workspace: WorkspaceStore
    @ObservedObject private var store: CaptureStore
    @ObservedObject private var intake: ExplorerCaptureController
    let project: String
    private let chooseExportDestination: @MainActor (ProjectWorkspaceExportDocument) -> URL?
    @Environment(\.workspaceZoom) private var zoom
    private var presentation: ProjectNavigationPresentation {
        get { state.projectPresentation[project] ?? ProjectNavigationPresentation() }
        nonmutating set { state.projectPresentation[project] = newValue }
    }
    private var filter: ProjectWorkspaceFilter {
        get { ProjectWorkspaceFilter(rawValue: presentation.filterRawValue) ?? .all }
        nonmutating set { presentation.filterRawValue = newValue.rawValue }
    }
    private var dateFilter: WorkspaceDateFilter {
        get { presentation.dateFilter }
        nonmutating set { presentation.dateFilter = newValue }
    }
    private var newestFirst: Bool {
        get { presentation.newestFirst }
        nonmutating set { presentation.newestFirst = newValue }
    }
    private var compact: Bool {
        get { presentation.compact }
        nonmutating set { presentation.compact = newValue }
    }
    private var selection: Set<String> {
        get { presentation.selectedIDs }
        nonmutating set { presentation.selectedIDs = newValue }
    }
    private var selectionAnchor: String? {
        get { presentation.selectionAnchor }
        nonmutating set { presentation.selectionAnchor = newValue }
    }
    @State private var gestureColumns: Int?
    @State private var settledColumns = 1
    @State private var contentCache: ProjectWorkspaceContentCache
    @State private var dragging = Set<String>()
    @State private var targeted = false
    @State private var exporting = false
    @State private var notePresented = false
    @State private var undoReceipt: ProjectTaskConversionReceipt?
    @FocusState private var focusedItem: String?
    private static let reorderType = "com.dabin.project-item-order"

    init(state: AppState, project: String,
         chooseExportDestination: @escaping @MainActor (ProjectWorkspaceExportDocument) -> URL? = { document in
             let panel = NSSavePanel()
             panel.allowedContentTypes = [.zip]
             panel.nameFieldStringValue = document.suggestedFilename
             panel.title = document.scope == .project ? "Export project" : "Export selected items"
             panel.prompt = "Save ZIP"
             let count = document.itemCount
             panel.message = "\(document.scope.title) · \(count) \(count == 1 ? "item" : "items") from \(document.project ?? "DaBin").\nIncludes original files, text, links, notes and task details."
             return panel.runModal() == .OK ? panel.url : nil
         }) {
        self.state = state; self.project = project
        _contentCache = State(initialValue: ProjectWorkspaceContentCache(store: state.store, workspace: state.workspace))
        self.chooseExportDestination = chooseExportDestination
        _workspace = ObservedObject(wrappedValue: state.workspace)
        _store = ObservedObject(wrappedValue: state.store)
        _intake = ObservedObject(wrappedValue: state.explorerInput)
    }

    private var color: Color {
        ProjectColorChoice.color(for: workspace.projectColorHex(for: project) ?? WorkspaceStore.defaultProjectColorHex)
    }
    private var busy: Bool { exporting || intake.isBusy || state.isArchiveOperationRunning }
    private var canReorder: Bool { !newestFirst && filter == .all && dateFilter == .anytime && !busy }
    private var allItems: [ProjectWorkspaceItem] {
        contentCache.items(key: "\(project)-\(newestFirst)") { buildAllItems() }
    }
    private func buildAllItems() -> [ProjectWorkspaceItem] {
        var items = ProjectWorkspaceContents.captures(in: project, from: store.captures).map(ProjectWorkspaceItem.capture)
        let text = workspace.scratchpad(project: project)
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let saved = workspace.snapshot.scratchpads[WorkspaceSnapshot.projectKey(project)]
            items.append(.note(WorkspaceScratchpad(text: text, projectName: project, updatedAt: saved?.updatedAt ?? Date())))
        }
        items.sort { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
        guard !newestFirst else { return items }
        let lookup = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return workspace.orderedProjectItemIDs(items.map(\.id), project: project).compactMap { lookup[$0] }
    }
    private func visibleItems(_ all: [ProjectWorkspaceItem]) -> [ProjectWorkspaceItem] {
        contentCache.visible(key: "\(filter.rawValue)-\(dateFilter.rawValue)") {
            all.filter { filter.includes($0) && dateFilter.includes($0.capture?.captureDay ?? CaptureCalendar.dayString($0.date)) }
        }
    }

    var body: some View {
        let all = allItems
        let visible = visibleItems(all)
        let selected = contentCache.selected(selection)
        let visibleIDs = contentCache.visibleIDs
        return VStack(spacing: 0) {
            header(all: all, selected: selected)
            filters
            selectionBar(all: all, visible: visible, selected: selected)
            GeometryReader { geometry in
                let proposedColumns = WorkspaceZoomLayout(factor: zoom.factor).columns(for: geometry.size.width, compact: compact)
                let columns = compact ? 1 : zoom.isInteracting ? (gestureColumns ?? settledColumns) : proposedColumns
                let layout = contentCache.layout(columns: columns,
                    newestFirst: newestFirst || workspace.snapshot.projectItemOrders?[WorkspaceSnapshot.projectKey(project)] == nil)
                browser(layout: layout, visible: visible, columns: columns, emptyProject: all.isEmpty)
                    .onAppear { settledColumns = proposedColumns }
                    .onChange(of: proposedColumns) { _, value in if !zoom.isInteracting { settledColumns = value } }
                    .onChange(of: zoom.isInteracting) { _, active in
                        gestureColumns = active ? settledColumns : nil
                        if !active { settledColumns = proposedColumns }
                    }
            }
            HStack(spacing: 6) {
                Image(systemName: "lock").accessibilityHidden(true)
                Text(intake.isBusy ? "Saving into \(project)…" : "Saved on this Mac")
                Spacer(minLength: 0)
                if undoReceipt != nil {
                    Button("Undo task conversion") { undoTasks() }.accessibilityIdentifier("project-undo-tasks")
                }
            }.font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.horizontal, 18).padding(.vertical, 8)
        }
        .background(Palette.background)
        .overlay { if targeted { RoundedRectangle(cornerRadius: 12).strokeBorder(color, lineWidth: 2).allowsHitTesting(false) } }
        .onDrop(of: ExplorerTransfer.acceptedTypeIdentifiers, isTargeted: $targeted) { intake.receive($0, project: project) }
        .onChange(of: visibleIDs) { _, ids in selection.formIntersection(Set(ids)) }
        .onAppear { focusedItem = presentation.focusedID }
        .onChange(of: focusedItem) { _, value in presentation.focusedID = value }
        .onChange(of: presentation.focusedID) { _, value in if focusedItem != value { focusedItem = value } }
        .onCopyCommand {
            do { return try visible.filter { selection.contains($0.id) }.map { item in
                switch item {
                case .capture(let capture): return try ExplorerTransfer.itemProvider(for: capture, store: store, includeInternalReference: false)
                case .note(let note): return NSItemProvider(object: note.text as NSString)
                }
            } } catch { state.reportFailure(error.localizedDescription); return [] }
        }
        .sheet(isPresented: $notePresented) {
            VStack(spacing: 8) {
                HStack { Text("Project notes").font(.headline); Spacer(); Button("Done") { notePresented = false }.keyboardShortcut(.cancelAction) }.padding()
                ScratchpadView(state: state, workspace: workspace,
                    noteContext: WorkspaceScratchpad(text: workspace.scratchpad(project: project), projectName: project, updatedAt: Date()))
            }.frame(minWidth: 400, idealWidth: 560, minHeight: 450, idealHeight: 620)
                .environment(\.workspaceZoom, WorkspaceZoomLayout())
        }
        .accessibilityElement(children: .contain).accessibilityLabel("Project workspace")
        .accessibilityIdentifier("project-workspace")
    }

    private func header(all: [ProjectWorkspaceItem], selected: [ProjectWorkspaceItem]) -> some View {
        HStack(spacing: 8) {
            headerActions(all: all, selected: selected)
            projectActions(all: all, selected: selected)
        }.font(.system(size: 12)).controlSize(.regular)
            .padding(.horizontal, 18).padding(.vertical, 12)
    }

    private func projectActions(all: [ProjectWorkspaceItem], selected: [ProjectWorkspaceItem]) -> some View {
        let items = selected.isEmpty ? all : selected
        let scope: ProjectWorkspaceExportScope = selected.isEmpty ? .project : .selection
        let copyTitle = selected.isEmpty ? "Copy project items" : "Copy selected items"
        let summaryTitle = selected.isEmpty ? "Copy project summary" : "Copy selection summary"
        return Menu {
            Button("Add files…", systemImage: "folder.badge.plus") { intake.chooseFiles(project: project) }
            Button("Paste into project", systemImage: "doc.on.clipboard") { intake.paste(project: project) }
            Button("Project notes", systemImage: "note.text") { notePresented = true }
            Button("Open project folder", systemImage: "folder") { state.showProjectFiles() }
            Divider()
            Button(copyTitle, systemImage: "doc.on.doc") { copy(items, summary: false, scope: scope) }
                .disabled(items.isEmpty)
            Button(summaryTitle, systemImage: "text.alignleft") { copy(items, summary: true, scope: scope) }
                .disabled(items.isEmpty)
            Divider()
            Button("Clipboard view") { state.navigateWorkspaceMode(.clipboard) }
            Button("Shelf view") { state.navigateWorkspaceMode(.shelf) }
        } label: { Image(systemName: "ellipsis").frame(width: 32, height: 32) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Project actions")
            .accessibilityIdentifier("project-actions")
            .disabled(busy)
    }

    private func headerActions(all: [ProjectWorkspaceItem], selected: [ProjectWorkspaceItem]) -> some View {
        let items = selected.isEmpty ? all : selected
        let scope: ProjectWorkspaceExportScope = selected.isEmpty ? .project : .selection
        let title = selected.isEmpty ? "Export project" : "Export selected (\(selected.count))"
        return HStack(spacing: 8) {
            Button { state.performSearchCommand() } label: {
                ViewThatFits(in: .horizontal) {
                    Label("Search everything", systemImage: "magnifyingglass").fixedSize()
                    Image(systemName: "magnifyingglass").frame(width: 32, height: 32)
                }
            }.buttonStyle(.plain).foregroundStyle(Palette.muted).accessibilityLabel("Search everything saved in DaBin")
                .accessibilityIdentifier("project-search").buddyHelp("Search across DaBin; refine by project in Filters")
            Spacer(minLength: 4)
            Button { export(items, scope: scope) } label: {
                Label(exporting ? "Exporting…" : title, systemImage: "arrow.down.to.line")
                    .lineLimit(1).fixedSize()
            }.buttonStyle(.borderedProminent).tint(color).disabled(items.isEmpty || busy)
                .accessibilityLabel(title).accessibilityIdentifier("project-export")
                .buddyHelp("Save \(scope.title.lowercased()) as a ZIP with original files, notes and task details")
        }
    }

    private var filters: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { filterChips; Spacer(minLength: 4); viewOptions }
            VStack(alignment: .leading, spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 6) { filterChips } }
                HStack { viewOptions; Spacer(minLength: 0) }
            }
        }.padding(.horizontal, 18).padding(.bottom, 8)
    }

    private var filterChips: some View {
        ForEach(ProjectWorkspaceFilter.allCases) { value in
            Button { filter = value; selection.removeAll(); selectionAnchor = nil } label: {
                Text(value.rawValue).font(.system(size: 12, weight: filter == value ? .semibold : .regular))
                    .padding(.horizontal, 10).frame(height: 30)
                    .background(filter == value ? color.opacity(0.13) : Palette.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(filter == value ? color.opacity(0.32) : Palette.line, lineWidth: 0.6))
            }.buttonStyle(.plain).foregroundStyle(filter == value ? color : Palette.muted)
                .accessibilityAddTraits(filter == value ? .isSelected : [])
                .accessibilityIdentifier("project-filter-\(value.id)")
        }
    }

    private var viewOptions: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(WorkspaceDateFilter.allCases) { date in
                    Button { dateFilter = date; selection.removeAll(); selectionAnchor = nil } label: {
                        Label(date.title, systemImage: dateFilter == date ? "checkmark" : "calendar")
                    }
                }
            } label: { Label(dateFilter.title, systemImage: "calendar") }.fixedSize()
            Menu {
                Button { newestFirst = false } label: { Label("My order", systemImage: newestFirst ? "line.3.horizontal" : "checkmark") }
                    .accessibilityIdentifier("project-sort-custom")
                Button { newestFirst = true } label: { Label("Newest first", systemImage: newestFirst ? "checkmark" : "clock") }
                    .accessibilityIdentifier("project-sort-newest")
            } label: { Text(newestFirst ? "Newest first" : "My order") }.fixedSize().accessibilityLabel("Project sort order")
            Button { compact.toggle() } label: {
                Image(systemName: compact ? "square.grid.2x2" : "list.bullet").frame(width: 30, height: 30)
            }.buttonStyle(.plain).accessibilityLabel(compact ? "Show preview grid" : "Show compact list")
                .accessibilityIdentifier("project-view-toggle")
        }.font(.system(size: 11)).foregroundStyle(Palette.muted).menuStyle(.borderlessButton)
    }

    private func selectionBar(all: [ProjectWorkspaceItem], visible: [ProjectWorkspaceItem], selected: [ProjectWorkspaceItem]) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { selectionLabel(visible: visible, allCount: all.count); Spacer(minLength: 4); selectionActions(selected, visible: visible) }
            VStack(alignment: .leading, spacing: 6) {
                HStack { selectionLabel(visible: visible, allCount: all.count); Spacer(minLength: 0) }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { selectionActions(selected, visible: visible); Spacer(minLength: 0) }
                    HStack(spacing: 8) { selectionActions(selected, visible: visible); Spacer(minLength: 0) }.labelStyle(.iconOnly)
                }
            }
        }.font(.system(size: 12)).frame(minHeight: 38)
            .padding(.horizontal, 18).padding(.bottom, 8)
    }

    private func selectionLabel(visible: [ProjectWorkspaceItem], allCount: Int) -> some View {
        HStack(spacing: 6) {
            Text(selection.isEmpty ? (visible.count == allCount ? "\(allCount) items" : "\(visible.count) of \(allCount) items") : "\(selection.count) selected")
                .foregroundStyle(selection.isEmpty ? Palette.muted : Palette.foreground)
                .accessibilityIdentifier("project-selection-count")
            if !selection.isEmpty {
                Button { selection.removeAll(); selectionAnchor = nil } label: { Image(systemName: "xmark.circle.fill").frame(width: 28, height: 28) }
                    .buttonStyle(.plain).foregroundStyle(Palette.muted).accessibilityLabel("Clear selection")
                    .accessibilityIdentifier("project-clear-selection")
            }
        }
    }

    @ViewBuilder private func selectionActions(_ selected: [ProjectWorkspaceItem], visible: [ProjectWorkspaceItem]) -> some View {
        if selected.isEmpty {
            Button("Select all") { selection = Set(visible.map(\.id)); selectionAnchor = visible.first?.id }
                .buttonStyle(.plain).foregroundStyle(color).disabled(visible.isEmpty)
                .accessibilityIdentifier("project-select-all")
        } else {
            Button("Make tasks", systemImage: "checkmark.circle") { makeTasks(selected) }
                .disabled(busy || !selected.contains { $0.capture?.isTask == false })
                .buddyHelp("Keeps each capture and file. Edit live project notes before saving them as a task.")
                .accessibilityIdentifier("project-make-tasks")
            Menu {
                Button("Move earlier", systemImage: "arrow.up") { moveSelection(earlier: true) }
                Button("Move later", systemImage: "arrow.down") { moveSelection(earlier: false) }
            } label: { Image(systemName: "arrow.up.arrow.down").frame(width: 24, height: 24) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().disabled(!canReorder)
                .accessibilityLabel("Reorder selected items").buddyHelp("Reorder in All items, Any date, My order")
        }
    }

    private func browser(layout: ProjectWorkspaceRows, visible: [ProjectWorkspaceItem], columns: Int, emptyProject: Bool) -> some View {
        List {
            if layout.rows.isEmpty {
                EmptyMessage(symbol: "folder", title: emptyProject ? "Make room for your next idea" : "No matching items",
                    message: emptyProject ? "Drop a file or paste something into this project. Your notes, links and tasks will live here too." : "Choose All and Any date to see the complete project.")
                    .listRowSeparator(.hidden).listRowBackground(Color.clear)
            }
            ForEach(layout.rows) { row in
                HStack(alignment: .top, spacing: zoom.value(12)) {
                    ForEach(row.items) { item in
                        card(item, visible: visible).frame(maxWidth: .infinity)
                    }
                    ForEach(0..<max(0, columns - row.items.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                }.listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 7, trailing: 16))
                    .listRowSeparator(.hidden).listRowBackground(Color.clear)
            }
        }.listStyle(.plain).scrollContentBackground(.hidden)
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
            .background {
                ExplorerViewport(store: store, rowIDs: layout.rowIDs,
                    context: ExplorerViewportContext(project: project, unfiledOnly: false, dailyFiles: false,
                        query: "", filter: filter.rawValue, pinnedOnly: false, dateFilter: dateFilter.rawValue,
                        source: nil, origin: "all", grouping: "project-\(columns)-\(compact)-\(newestFirst)", selectedID: nil), handlesZoom: false)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            .background {
                WorkspaceZoomViewport(groups: layout.groups,
                    historyAnchor: presentation.viewport, onHistoryAnchor: { presentation.viewport = $0 })
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            .accessibilityIdentifier("project-items")
    }

    private func card(_ item: ProjectWorkspaceItem, visible: [ProjectWorkspaceItem]) -> some View {
        ProjectWorkspaceCard(state: state, item: item, selected: selection.contains(item.id), compact: compact,
            color: color, focus: $focusedItem, open: { open(item) }, select: { select(item, visible: visible) },
            details: { if let capture = item.capture { state.openCapture(capture.id) } else { notePresented = true } },
            makeTask: { makeTasks([item]) },
            earlier: { selection = [item.id]; moveSelection(earlier: true) },
            later: { selection = [item.id]; moveSelection(earlier: false) }, canReorder: canReorder,
            drag: {
                let identities = selection.contains(item.id) ? selection : [item.id]
                // The visible project order also determines multi-item drop order.
                // Resolve the complete selection before starting a native session.
                let items = visible.filter { identities.contains($0.id) }
                let captures = items.compactMap(\.capture)
                let captureWriters = captures.isEmpty ? [] : try ExplorerTransfer.pasteboardWriters(for: captures, store: store)
                var iterator = captureWriters.makeIterator()
                var writers: [NSPasteboardWriting] = items.map { value in
                    switch value {
                    case .capture: return iterator.next()!
                    case .note(let note): return note.text as NSString
                    }
                }
                dragging = canReorder ? identities : []
                if canReorder, let first = writers.first {
                    writers[0] = ProjectReorderWriter(content: first, type: Self.reorderType)
                }
                return writers
            }, dragEnded: { dragging.removeAll() })
            .onDrop(of: [Self.reorderType], isTargeted: nil) { _ in
                guard canReorder, !dragging.isEmpty, !dragging.contains(item.id) else { return false }
                saveOrder(ProjectWorkspaceOrdering.moving(allItems.map(\.id), selected: dragging, before: item.id))
                selection = dragging; dragging.removeAll(); return true
            }
            .onKeyPress("a", phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                selection = Set(visible.map(\.id)); return .handled
            }
    }

    private func select(_ item: ProjectWorkspaceItem, visible: [ProjectWorkspaceItem]) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.shift), let anchor = selectionAnchor,
           let from = visible.firstIndex(where: { $0.id == anchor }), let to = visible.firstIndex(where: { $0.id == item.id }) {
            selection.formUnion(visible[min(from, to)...max(from, to)].map(\.id))
        } else {
            if !selection.insert(item.id).inserted { selection.remove(item.id) }
            selectionAnchor = item.id
        }
        focusedItem = item.id
    }
    private func open(_ item: ProjectWorkspaceItem) {
        if NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift) {
            select(item, visible: visibleItems(allItems)); return
        }
        guard let capture = item.capture else { notePresented = true; return }
        workspace.selectedCaptureID = capture.id
        if capture.attachmentRelativePath != nil || capture.kind == .link { state.openOriginal(capture) }
        else { state.openCapture(capture.id) }
    }
    private func moveSelection(earlier: Bool) {
        guard canReorder else { return }
        saveOrder(ProjectWorkspaceOrdering.move(allItems.map(\.id), selected: selection,
            direction: earlier ? .earlier : .later))
    }
    private func saveOrder(_ ids: [String]) {
        do { try workspace.saveProjectItemOrder(ids, project: project) }
        catch { state.reportFailure(error.localizedDescription) }
    }
    private func makeTasks(_ items: [ProjectWorkspaceItem]) {
        do {
            undoReceipt = try state.convertProjectItemsToTasks(items.compactMap(\.capture))
            state.status = AppStatusMessage(text: "\(undoReceipt?.count ?? 0) captures are now tasks. Originals are kept."
                + (notes(in: items) == nil ? "" : " Live project notes remain notes."), severity: .success)
        } catch { state.reportFailure(error.localizedDescription) }
    }
    private func undoTasks() {
        guard let receipt = undoReceipt else { return }
        if state.undoProjectTaskConversion(receipt) { undoReceipt = nil }
    }

    private func notes(in items: [ProjectWorkspaceItem]) -> String? {
        items.compactMap { if case .note(let note) = $0 { return note.text }; return nil }.first
    }
    private func copy(_ items: [ProjectWorkspaceItem], summary: Bool, scope: ProjectWorkspaceExportScope) {
        do {
            if summary {
                let document = try ProjectWorkspaceExport.document(project: project, captures: items.compactMap(\.capture), store: store,
                    notes: notes(in: items), scope: scope, orderedItemIDs: items.map(\.id))
                try WorkspaceClipboard.write(document.summary)
            } else {
                try ProjectWorkspaceExport.copyItems(captures: items.compactMap(\.capture), store: store, notes: notes(in: items),
                    orderedItemIDs: items.map(\.id))
            }
            state.status = AppStatusMessage(text: "\(items.count) items copied\(summary ? " as a summary" : "").", severity: .success)
        } catch { state.reportFailure(error.localizedDescription) }
    }
    private func export(_ items: [ProjectWorkspaceItem], scope: ProjectWorkspaceExportScope) {
        do {
            let document = try ProjectWorkspaceExport.document(project: project, captures: items.compactMap(\.capture), store: store,
                notes: notes(in: items), scope: scope, orderedItemIDs: items.map(\.id))
            guard let url = chooseExportDestination(document) else { return }
            exporting = true
            Task { @MainActor in
                defer { exporting = false }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    try await ProjectWorkspaceExport.export(document, to: url)
                    state.status = AppStatusMessage(text: scope == .project ? "Project ZIP saved." : "\(document.itemCount) selected items saved as ZIP.", severity: .success)
                } catch { state.reportFailure(error.localizedDescription) }
            }
        } catch { state.reportFailure(error.localizedDescription) }
    }
}
