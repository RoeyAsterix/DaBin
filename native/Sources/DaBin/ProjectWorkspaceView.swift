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

/// Grid columns have equal widths. Propose that final width directly to each
/// card so a native row resize does not negotiate complete card layouts at
/// multiple minimum/maximum widths. The tallest real card determines the row.
private struct ProjectWorkspaceRowLayout: Layout {
    let spacing: CGFloat
    let direction: LayoutDirection

    private func dimensions(proposedWidth: CGFloat?, subviews: Subviews) -> (width: CGFloat, columnWidth: CGFloat) {
        let gaps = spacing * CGFloat(max(0, subviews.count - 1))
        let width: CGFloat
        if let proposedWidth, proposedWidth.isFinite {
            width = max(gaps, proposedWidth)
        } else {
            let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }.filter(\.isFinite).max() ?? 0
            width = max(0, ideal) * CGFloat(subviews.count) + gaps
        }
        return (width, max(0, width - gaps) / CGFloat(max(1, subviews.count)))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let dimensions = dimensions(proposedWidth: proposal.width, subviews: subviews)
        let cardProposal = ProposedViewSize(width: dimensions.columnWidth, height: nil)
        let height = subviews.map { $0.sizeThatFits(cardProposal).height }.max() ?? 0
        return CGSize(width: dimensions.width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let dimensions = dimensions(proposedWidth: bounds.width, subviews: subviews)
        let cardProposal = ProposedViewSize(width: dimensions.columnWidth, height: nil)
        for index in subviews.indices {
            let offset = CGFloat(index) * (dimensions.columnWidth + spacing)
            let x = direction == .rightToLeft ? bounds.maxX - offset - dimensions.columnWidth : bounds.minX + offset
            subviews[index].place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading, proposal: cardProposal)
        }
    }
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
    private(set) var visibleRevision: UInt64 = 0
    private var visibleLookup: [String: ProjectWorkspaceItem] = [:]
    private var selectedIDs: Set<String>?
    private var selectedItems: [ProjectWorkspaceItem] = []
    private var layouts: [Int: ProjectWorkspaceRows] = [:]
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
            visibleRevision &+= 1
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
    func layout(columns: Int) -> ProjectWorkspaceRows {
        // Workspace column policy permits only these three variants. Bound
        // the cache even if a malformed future caller passes another number.
        let key = min(3, max(1, columns))
        if let cached = layouts[key] { return cached }
        let groups = ProjectWorkspaceOrdering.rows(ids: visibleIDs, columns: key, newestFirst: true)
        let rows = groups.map { group in
            ProjectWorkspaceRow(id: group[0], items: group.compactMap { visibleLookup[$0] })
        }
        let result = ProjectWorkspaceRows(rows: rows, rowIDs: rows.map(\.id), groups: groups)
        layouts[key] = result
        return result
    }
}

/// Actions resolve the latest project snapshot at invocation time. Keeping
/// this holder stable avoids rebuilding native List content just to replace
/// closures during a zoom. Bindings preserve the parent's focus and sheets;
/// the context does not retain the view or this holder through a callback.
@MainActor private final class ProjectWorkspaceBrowserActions {
    @MainActor private struct Context {
        let state: AppState
        let project: String
        let visible: [ProjectWorkspaceItem]
        let visibleIDs: [String]
        let focus: FocusState<String?>.Binding
        let notePresented: Binding<Bool>
        let undoReceipt: Binding<ProjectTaskConversionReceipt?>

        var presentation: ProjectNavigationPresentation {
            get { state.projectPresentation[project] ?? ProjectNavigationPresentation() }
            nonmutating set { state.projectPresentation[project] = newValue }
        }
    }

    private var context: Context?
    private var current: Context {
        guard let context else { preconditionFailure("Project browser actions must be configured before use") }
        return context
    }

    func update(state: AppState, project: String, visible: [ProjectWorkspaceItem], visibleIDs: [String],
                focus: FocusState<String?>.Binding, notePresented: Binding<Bool>,
                undoReceipt: Binding<ProjectTaskConversionReceipt?>) {
        context = Context(state: state, project: project, visible: visible, visibleIDs: visibleIDs,
                          focus: focus, notePresented: notePresented, undoReceipt: undoReceipt)
    }

    func select(_ item: ProjectWorkspaceItem) {
        let context = current
        var presentation = context.presentation
        if NSEvent.modifierFlags.contains(.shift), let anchor = presentation.selectionAnchor,
           let from = context.visibleIDs.firstIndex(of: anchor), let to = context.visibleIDs.firstIndex(of: item.id) {
            presentation.selectedIDs.formUnion(context.visibleIDs[min(from, to)...max(from, to)])
        } else {
            if !presentation.selectedIDs.insert(item.id).inserted { presentation.selectedIDs.remove(item.id) }
            presentation.selectionAnchor = item.id
        }
        context.presentation = presentation
        context.focus.wrappedValue = item.id
    }

    func open(_ item: ProjectWorkspaceItem) {
        if NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift) { select(item); return }
        let context = current
        guard let capture = item.capture else { context.notePresented.wrappedValue = true; return }
        context.state.workspace.selectedCaptureID = capture.id
        if capture.attachmentRelativePath != nil || capture.kind == .link { context.state.openOriginal(capture) }
        else { context.state.openCapture(capture.id) }
    }

    func details(_ item: ProjectWorkspaceItem) {
        let context = current
        if let capture = item.capture { context.state.openCapture(capture.id) }
        else { context.notePresented.wrappedValue = true }
    }

    func makeTasks(_ items: [ProjectWorkspaceItem]) {
        let context = current
        do {
            let receipt = try context.state.convertProjectItemsToTasks(items.compactMap(\.capture))
            context.undoReceipt.wrappedValue = receipt
            let count = receipt.count
            let hasNotes = items.contains { if case .note = $0 { return true }; return false }
            context.state.status = AppStatusMessage(text: (count == 1 ? "1 capture is now a task. Originals are kept." : "\(count) captures are now tasks. Originals are kept.")
                + (hasNotes ? " Live project notes remain notes." : ""), severity: .success)
        } catch { context.state.reportFailure(error.localizedDescription) }
    }

    func drag(_ item: ProjectWorkspaceItem) throws -> [NSPasteboardWriting] {
        let context = current
        let selection = context.presentation.selectedIDs
        let identities = selection.contains(item.id) ? selection : [item.id]
        // Selection and transfer order always come from the current visible
        // project, including after a filter, date or scratchpad change.
        let items = context.visible.filter { identities.contains($0.id) }
        let captures = items.compactMap(\.capture)
        let captureWriters = captures.isEmpty ? [] : try ExplorerTransfer.pasteboardWriters(for: captures, store: context.state.store)
        var iterator = captureWriters.makeIterator()
        return items.map { value in
            switch value {
            case .capture: return iterator.next()!
            case .note(let note): return note.text as NSString
            }
        }
    }

    func selectAll() {
        let context = current
        var presentation = context.presentation
        presentation.selectedIDs = Set(context.visibleIDs)
        presentation.selectionAnchor = context.visibleIDs.first
        context.presentation = presentation
    }

    func resetFilters() {
        let context = current
        var presentation = context.presentation
        presentation.filterRawValue = ProjectWorkspaceFilter.all.rawValue
        presentation.selectedDateRange = nil
        presentation.dateFilter = .anytime
        presentation.selectedIDs.removeAll()
        presentation.selectionAnchor = nil
        context.presentation = presentation
    }

    func recordHistory(_ anchor: NavigationViewportAnchor) { current.presentation.viewport = anchor }
}

/// These are all non-zoom inputs to the browser. The revision changes whenever
/// archive/workspace content is rebuilt, including replacement captures and
/// scratchpad text. Independent Capture observers still deliver live edits.
private struct ProjectWorkspaceBrowserInputs: Equatable {
    let actionsID: ObjectIdentifier
    let stateID: ObjectIdentifier
    let storeID: ObjectIdentifier
    let revision: UInt64
    let project: String
    let filter: String
    let dateFilter: String
    let columns: Int
    let compact: Bool
    let selection: Set<String>
    let selectionAnchor: String?
    let focusedItem: String?
    let historyAnchor: NavigationViewportAnchor?
    let color: Color
    let emptyProject: Bool
    let busy: Bool
    let navigationBlocked: Bool
}

/// Font/preview scaling remains inside ProjectWorkspaceCard. The equality
/// boundary only keeps the row's zoom spacing from replacing card callbacks
/// and focus controls that have otherwise retained the same content/state.
@MainActor private struct ProjectWorkspaceBrowserCard: View, Equatable {
    let item: ProjectWorkspaceItem
    let itemID: String
    let inputs: ProjectWorkspaceBrowserInputs
    let state: AppState
    let actions: ProjectWorkspaceBrowserActions
    let focus: FocusState<String?>.Binding

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.itemID == rhs.itemID && lhs.inputs == rhs.inputs
    }

    var body: some View {
        ProjectWorkspaceCard(state: state, item: item, selected: inputs.selection.contains(itemID),
            compact: inputs.compact, color: inputs.color, focus: focus,
            open: { actions.open(item) }, select: { actions.select(item) }, details: { actions.details(item) },
            makeTask: { actions.makeTasks([item]) }, drag: { try actions.drag(item) })
            .onKeyPress("a", phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                actions.selectAll(); return .handled
            }
    }
}

@MainActor private struct ProjectWorkspaceBrowserRow: View {
    let row: ProjectWorkspaceRow
    let inputs: ProjectWorkspaceBrowserInputs
    let state: AppState
    let actions: ProjectWorkspaceBrowserActions
    let focus: FocusState<String?>.Binding
    @Environment(\.workspaceZoom) private var zoom
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        ProjectWorkspaceRowLayout(spacing: zoom.value(12), direction: layoutDirection) {
            ForEach(row.items) { item in
                ProjectWorkspaceBrowserCard(item: item, itemID: item.id, inputs: inputs,
                    state: state, actions: actions, focus: focus).equatable().frame(maxWidth: .infinity)
            }
            ForEach(0..<max(0, inputs.columns - row.items.count), id: \.self) { _ in
                Color.clear.frame(maxWidth: .infinity)
            }
        }
    }
}

/// Native List structure is independent of each typography tick. Its children
/// and viewport bridge observe live zoom themselves, so automatic card height,
/// resize anchoring and the native focus/key loop continue to update normally.
@MainActor private struct ProjectWorkspaceBrowser: View, Equatable {
    let layout: ProjectWorkspaceRows
    let inputs: ProjectWorkspaceBrowserInputs
    let state: AppState
    let store: CaptureStore
    let actions: ProjectWorkspaceBrowserActions
    let focus: FocusState<String?>.Binding

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.inputs == rhs.inputs }

    var body: some View {
        List {
            if layout.rows.isEmpty {
                VStack(spacing: 8) {
                    EmptyMessage(symbol: "folder", title: inputs.emptyProject ? "Make room for your next idea" : "No matching items",
                        message: inputs.emptyProject ? "Drop a file or paste something into this project. Your notes, links and tasks will live here too." : "Try another filter or show the complete project.")
                    if !inputs.emptyProject {
                        Button("Show all items") { actions.resetFilters() }
                            .frame(minHeight: 32).accessibilityIdentifier("project-reset-filters")
                    }
                }.listRowSeparator(.hidden).listRowBackground(Color.clear)
            }
            ForEach(layout.rows) { row in
                ProjectWorkspaceBrowserRow(row: row, inputs: inputs, state: state, actions: actions, focus: focus)
                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 7, trailing: 16))
                    .listRowSeparator(.hidden).listRowBackground(Color.clear)
            }
        }.listStyle(.plain).scrollContentBackground(.hidden)
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
            .background {
                ExplorerViewport(store: store, rowIDs: layout.rowIDs,
                    context: ExplorerViewportContext(project: inputs.project, unfiledOnly: false, dailyFiles: false,
                        query: "", filter: inputs.filter, pinnedOnly: false, dateFilter: inputs.dateFilter,
                        source: nil, origin: "all", grouping: "project-\(inputs.columns)-\(inputs.compact)-newest", selectedID: nil), handlesZoom: false)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            .background {
                WorkspaceZoomViewport(groups: layout.groups, historyAnchor: inputs.historyAnchor,
                    onHistoryAnchor: { actions.recordHistory($0) })
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            .accessibilityIdentifier("project-items")
    }
}

@MainActor struct ProjectWorkspaceView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var workspace: WorkspaceStore
    @ObservedObject private var store: CaptureStore
    @ObservedObject private var intake: ExplorerCaptureController
    let project: String
    let showsSearchEntry: Bool
    private let chooseExportDestination: @MainActor (ProjectWorkspaceExportDocument) -> URL?
    private let pasteboard: NSPasteboard
    @Environment(\.workspaceZoom) private var zoom
    private var presentation: ProjectNavigationPresentation {
        get { state.projectPresentation[project] ?? ProjectNavigationPresentation() }
        nonmutating set { state.projectPresentation[project] = newValue }
    }
    private var filter: ProjectWorkspaceFilter {
        get { ProjectWorkspaceFilter(rawValue: presentation.filterRawValue) ?? .all }
        nonmutating set { presentation.filterRawValue = newValue.rawValue }
    }
    private var dateFilter: WorkspaceDateFilter { presentation.dateFilter }
    private var dateFilterTitle: String { presentation.selectedDateRange?.displayTitle ?? dateFilter.title }
    private var dateFilterKey: String { presentation.selectedDateRange?.cacheKey ?? dateFilter.rawValue }
    private var hasDateFilter: Bool { presentation.selectedDateRange != nil || dateFilter != .anytime }
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
    @State private var browserActions = ProjectWorkspaceBrowserActions()
    @State private var targeted = false
    @State private var exporting = false
    @State private var notePresented = false
    @State private var datePickerPresented = false
    @State private var undoReceipt: ProjectTaskConversionReceipt?
    @FocusState private var focusedItem: String?

    init(state: AppState, project: String, showsSearchEntry: Bool = true, pasteboard: NSPasteboard = .general,
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
        self.state = state; self.project = project; self.showsSearchEntry = showsSearchEntry
        _contentCache = State(initialValue: ProjectWorkspaceContentCache(store: state.store, workspace: state.workspace))
        self.chooseExportDestination = chooseExportDestination
        self.pasteboard = pasteboard
        _workspace = ObservedObject(wrappedValue: state.workspace)
        _store = ObservedObject(wrappedValue: state.store)
        _intake = ObservedObject(wrappedValue: state.explorerInput)
    }

    private var color: Color {
        ProjectColorChoice.color(for: workspace.projectColorHex(for: project) ?? WorkspaceStore.defaultProjectColorHex)
    }
    private var busy: Bool { exporting || intake.isBusy || state.isArchiveOperationRunning }
    private var allItems: [ProjectWorkspaceItem] {
        contentCache.items(key: project) { buildAllItems() }
    }
    private func buildAllItems() -> [ProjectWorkspaceItem] {
        var items = ProjectWorkspaceContents.captures(in: project, from: store.captures).map(ProjectWorkspaceItem.capture)
        let text = workspace.scratchpad(project: project)
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let saved = workspace.snapshot.scratchpads[WorkspaceSnapshot.projectKey(project)]
            items.append(.note(WorkspaceScratchpad(text: text, projectName: project, updatedAt: saved?.updatedAt ?? Date())))
        }
        items.sort { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
        return items
    }
    private func visibleItems(_ all: [ProjectWorkspaceItem]) -> [ProjectWorkspaceItem] {
        contentCache.visible(key: "\(filter.rawValue)-\(dateFilterKey)") {
            all.filter { item in
                let day = item.capture?.captureDay ?? CaptureCalendar.dayString(item.date)
                let included = presentation.selectedDateRange?.includes(day: day) ?? dateFilter.includes(day)
                return filter.includes(item) && included
            }
        }
    }

    var body: some View {
        let all = allItems
        let visible = visibleItems(all)
        let selected = contentCache.selected(selection)
        let visibleIDs = contentCache.visibleIDs
        browserActions.update(state: state, project: project, visible: visible, visibleIDs: visibleIDs,
                              focus: $focusedItem, notePresented: $notePresented, undoReceipt: $undoReceipt)
        return VStack(spacing: 0) {
            header(all: all, selected: selected)
            selectionBar(all: all, visible: visible, selected: selected)
            GeometryReader { geometry in
                let proposedColumns = WorkspaceZoomLayout(factor: zoom.factor).columns(for: geometry.size.width, compact: compact)
                let columns = compact ? 1 : zoom.isInteracting ? (gestureColumns ?? settledColumns) : proposedColumns
                let layout = contentCache.layout(columns: columns)
                browser(layout: layout, columns: columns, emptyProject: all.isEmpty)
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
                if intake.canUndoMove {
                    Button("Undo move") { intake.undoLastMove() }
                        .frame(minHeight: 32).disabled(busy)
                        .accessibilityLabel("Undo project move").accessibilityIdentifier("project-undo-move")
                }
                if let receipt = undoReceipt, state.canUndoProjectTaskConversion(receipt) {
                    Button("Undo tasks") { undoTasks() }.frame(minHeight: 32).disabled(busy)
                        .accessibilityLabel("Undo task conversion").accessibilityIdentifier("project-undo-tasks")
                }
            }.font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.horizontal, 18).padding(.vertical, 8)
        }
        .background(Palette.background)
        .overlay { if targeted { RoundedRectangle(cornerRadius: 12).strokeBorder(color, lineWidth: 2).allowsHitTesting(false) } }
        .onDrop(of: ExplorerTransfer.acceptedTypeIdentifiers, isTargeted: $targeted) { intake.receive($0, project: project) }
        .onChange(of: visibleIDs) { _, ids in
            let visible = Set(ids)
            selection.formIntersection(visible)
            if let anchor = selectionAnchor, !visible.contains(anchor) { selectionAnchor = nil }
        }
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
                HStack { Text("Project notes").font(.headline); Spacer(); Button("Done") { notePresented = false }.keyboardShortcut(.cancelAction).accessibilityIdentifier("project-notes-done") }.padding()
                ScratchpadView(state: state, workspace: workspace,
                    noteContext: WorkspaceScratchpad(text: workspace.scratchpad(project: project), projectName: project, updatedAt: Date()))
            }.frame(minWidth: 400, idealWidth: 560, minHeight: 450, idealHeight: 620)
                .environment(\.workspaceZoom, WorkspaceZoomLayout())
        }
        .accessibilityElement(children: .contain).accessibilityLabel("Project workspace")
        .accessibilityIdentifier("project-workspace")
    }

    private func header(all: [ProjectWorkspaceItem], selected: [ProjectWorkspaceItem]) -> some View {
        HStack(spacing: 6) {
            headerActions(selected: selected)
            projectActions(all: all, selected: selected)
        }.font(.system(size: 12)).controlSize(.regular)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .accessibilityElement(children: .contain).accessibilityIdentifier("project-toolbar")
    }

    private func projectActions(all: [ProjectWorkspaceItem], selected: [ProjectWorkspaceItem]) -> some View {
        let items = selected.isEmpty ? all : selected
        let scope: ProjectWorkspaceExportScope = selected.isEmpty ? .project : .selection
        let copyTitle = selected.isEmpty ? "Copy project items" : "Copy selected items"
        let summaryTitle = selected.isEmpty ? "Copy project summary" : "Copy selection summary"
        return Menu {
            Button("Add files…", systemImage: "folder.badge.plus") { intake.chooseFiles(project: project) }
            Button("Paste into project", systemImage: "doc.on.clipboard") { intake.paste(project: project, from: pasteboard) }
            Button("Project notes", systemImage: "note.text") { notePresented = true }
            Button("Open folder", systemImage: "folder") { state.showProjectFiles() }
            Divider()
            Button(copyTitle, systemImage: "doc.on.doc") { copy(items, summary: false, scope: scope) }
                .disabled(items.isEmpty)
            Button(summaryTitle, systemImage: "text.alignleft") { copy(items, summary: true, scope: scope) }
                .disabled(items.isEmpty)
            Divider()
            Button("Clipboard view") { state.navigateWorkspaceMode(.clipboard) }.disabled(state.isNavigationBlocked)
            Button("Shelf view") { state.navigateWorkspaceMode(.shelf) }.disabled(state.isNavigationBlocked)
        } label: { Image(systemName: "ellipsis").frame(width: 32, height: 32).contentShape(Rectangle()) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Project actions")
            .accessibilityIdentifier("project-actions")
            .disabled(busy)
    }

    private func headerActions(selected: [ProjectWorkspaceItem]) -> some View {
        let canExport = !selected.isEmpty && !busy
        return HStack(spacing: 6) {
            if showsSearchEntry {
                Button { state.performSearchCommand() } label: {
                    Image(systemName: "magnifyingglass").frame(width: 32, height: 32).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(Palette.muted).accessibilityLabel("Search everything saved in DaBin")
                    .accessibilityIdentifier("project-search").buddyHelp("Search across DaBin; refine by project in Filters")
            }
            filterMenu
            viewOptions
            Spacer(minLength: 0)
            Button { exportSelected(selected) } label: {
                Label(exporting ? "Exporting…" : "Export Selected", systemImage: "arrow.down.to.line")
                    .font(.system(size: 11, weight: .medium)).fixedSize()
                    .padding(.horizontal, 9).frame(height: 28)
                    .foregroundStyle(canExport ? color : Palette.muted)
                    .background(color.opacity(canExport ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(color.opacity(canExport ? 0.24 : 0.1), lineWidth: 1))
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(!canExport)
                .accessibilityLabel("Export Selected").accessibilityIdentifier("project-export")
                .buddyHelp(selected.isEmpty ? "Select items to export a ZIP" : "Save \(selected.count) selected \(selected.count == 1 ? "item" : "items") as a ZIP with original files, notes and task details")
        }
    }

    private var filterMenu: some View {
        Menu {
            ForEach(ProjectWorkspaceFilter.allCases) { value in
                Button { selectFilter(value) } label: {
                    Label(value.rawValue, systemImage: filter == value ? "checkmark" : "line.3.horizontal.decrease")
                }.accessibilityIdentifier("project-filter-\(value.id)")
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease").frame(width: 32, height: 32)
                .background(filter == .all ? Color.clear : color.opacity(0.13), in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .foregroundStyle(filter == .all ? Palette.muted : color)
            .accessibilityLabel("Project item type: \(filter.rawValue)")
            .accessibilityIdentifier("project-filter-menu").buddyHelp("Filter items: \(filter.rawValue)")
    }

    private var viewOptions: some View {
        HStack(spacing: 6) {
            Button { datePickerPresented.toggle() } label: {
                Image(systemName: "calendar").frame(width: 32, height: 32)
                    .background(hasDateFilter ? color.opacity(0.13) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).fixedSize()
                .foregroundStyle(hasDateFilter ? color : Palette.muted)
                .accessibilityLabel("Project date: \(presentation.selectedDateRange?.accessibilityLabel ?? dateFilter.title)")
                .accessibilityIdentifier("project-date-filter").buddyHelp("Date: \(dateFilterTitle)")
                .popover(isPresented: $datePickerPresented, arrowEdge: .bottom) {
                    ProjectDatePicker(selection: presentation.selectedDateRange, dateFilter: dateFilter,
                        activityDays: Set(allItems.map { $0.capture?.captureDay ?? CaptureCalendar.dayString($0.date) }),
                        onSelect: selectDate, onClear: clearDate,
                        dismiss: { datePickerPresented = false })
                        .environment(\.daBinAccent, color)
                        .hoverTooltips()
                }
            Button { compact.toggle() } label: {
                Image(systemName: compact ? "square.grid.2x2" : "list.bullet")
                    .frame(width: 32, height: 32).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(compact ? "Show preview grid" : "Show compact list")
                .accessibilityIdentifier("project-view-toggle").buddyHelp(compact ? "Show preview grid" : "Show compact list")
        }.font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize()
    }

    private func selectDate(_ range: ProjectDateSelection) {
        var next = presentation
        next.selectedDateRange = range
        next.dateFilter = .anytime
        next.selectedIDs.removeAll()
        next.selectionAnchor = nil
        presentation = next
    }

    private func clearDate() {
        var next = presentation
        next.selectedDateRange = nil
        next.dateFilter = .anytime
        next.selectedIDs.removeAll()
        next.selectionAnchor = nil
        presentation = next
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
                Button { selection.removeAll(); selectionAnchor = nil } label: { Image(systemName: "xmark.circle.fill").frame(width: 32, height: 32) }
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
            Button(selected.lazy.filter { $0.capture?.isTask == false }.count == 1 ? "Make task" : "Make tasks", systemImage: "checkmark.circle") { makeTasks(selected) }
                .disabled(busy || !selected.contains { $0.capture?.isTask == false })
                .buddyHelp("Keeps each capture and file. Edit live project notes before saving them as a task.")
                .accessibilityIdentifier("project-make-tasks")

        }
    }

    private func browser(layout: ProjectWorkspaceRows, columns: Int, emptyProject: Bool) -> some View {
        let inputs = ProjectWorkspaceBrowserInputs(actionsID: ObjectIdentifier(browserActions),
            stateID: ObjectIdentifier(state), storeID: ObjectIdentifier(store), revision: contentCache.visibleRevision,
            project: project, filter: filter.rawValue, dateFilter: dateFilterKey, columns: columns, compact: compact,
            selection: selection, selectionAnchor: selectionAnchor, focusedItem: focusedItem,
            historyAnchor: presentation.viewport, color: color, emptyProject: emptyProject,
            busy: busy, navigationBlocked: state.isNavigationBlocked)
        return ProjectWorkspaceBrowser(layout: layout, inputs: inputs, state: state, store: store,
            actions: browserActions, focus: $focusedItem).equatable()
    }
    private func selectFilter(_ value: ProjectWorkspaceFilter) {
        filter = value; selection.removeAll(); selectionAnchor = nil
    }
    private func makeTasks(_ items: [ProjectWorkspaceItem]) {
        browserActions.makeTasks(items)
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
                try WorkspaceClipboard.write(document.summary, to: pasteboard)
            } else {
                try ProjectWorkspaceExport.copyItems(captures: items.compactMap(\.capture), store: store, notes: notes(in: items),
                    orderedItemIDs: items.map(\.id), pasteboard: pasteboard)
            }
            state.status = AppStatusMessage(text: "\(items.count) items copied\(summary ? " as a summary" : "").", severity: .success)
        } catch { state.reportFailure(error.localizedDescription) }
    }
    private func exportSelected(_ items: [ProjectWorkspaceItem]) {
        guard !items.isEmpty && !busy else { return }
        do {
            let document = try ProjectWorkspaceExport.document(project: project, captures: items.compactMap(\.capture), store: store,
                notes: notes(in: items), scope: .selection, orderedItemIDs: items.map(\.id))
            guard let url = chooseExportDestination(document) else { return }
            exporting = true
            Task { @MainActor in
                defer { exporting = false }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    try await ProjectWorkspaceExport.export(document, to: url)
                    state.status = AppStatusMessage(text: "\(document.itemCount) selected \(document.itemCount == 1 ? "item" : "items") saved as ZIP.", severity: .success)
                } catch { state.reportFailure(error.localizedDescription) }
            }
        } catch { state.reportFailure(error.localizedDescription) }
    }
}
