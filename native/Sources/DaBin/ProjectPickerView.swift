import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum ProjectNamePolicy {
    static let maximumLength = 180
    static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
    }
    static func validationMessage(_ value: String, existing: [String]) -> String? {
        let name = normalized(value)
        guard !name.isEmpty else { return "Give this project a name." }
        guard name.count <= maximumLength else { return "Use 180 characters or fewer." }
        guard !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            return "Use a name without line breaks or control characters."
        }
        let key = name.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        if ["all projects", "unfiled"].contains(key) { return "That name is used for a browsing scope. Choose another." }
        if existing.contains(where: {
            normalized($0).folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX")) == key
        }) { return "A project with that name already exists." }
        return nil
    }
}

/// One searchable project panel for browsing and filing. Creating a project
/// never rewrites existing project names or their managed folder identities.
@MainActor
struct ProjectPickerPanel: View {
    @ObservedObject var state: AppState
    @ObservedObject private var workspace: WorkspaceStore
    let selectedProject: String?
    var allowsAll = false
    var allSelected = false
    var allowsDrop = false
    let onSelect: (String?, Bool) throws -> Void
    let onDismiss: () -> Void
    @State private var query = ""
    @State private var creating: Bool
    @State private var name = ""
    @State private var error: String?
    @State private var highlighted: String?
    @FocusState private var field: Field?
    @Environment(\.daBinAccent) private var accent
    private enum Field: Hashable { case search, name }
    private struct Choice: Identifiable {
        let id: String
        let name: String
        let project: String?
        let all: Bool
    }

    init(state: AppState, selectedProject: String?, allowsAll: Bool = false,
         allSelected: Bool = false, allowsDrop: Bool = false, startCreating: Bool = false,
         onSelect: @escaping (String?, Bool) throws -> Void, onDismiss: @escaping () -> Void) {
        self.state = state; _workspace = ObservedObject(wrappedValue: state.workspace)
        self.selectedProject = selectedProject; self.allowsAll = allowsAll
        self.allSelected = allSelected; self.allowsDrop = allowsDrop
        self.onSelect = onSelect; self.onDismiss = onDismiss
        _creating = State(initialValue: startCreating)
    }

    private var projects: [String] {
        Set(state.projectNames + workspace.projectNames).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    private var choices: [Choice] {
        var values = allowsAll ? [Choice(id: "all", name: "All projects", project: nil, all: true)] : []
        values.append(Choice(id: "unfiled", name: "Unfiled", project: nil, all: false))
        values += projects.map { Choice(id: "project:" + $0, name: $0, project: $0, all: false) }
        return values.filter { query.isEmpty || $0.name.localizedStandardContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if creating { creation }
            else {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                    ProjectSearchField(text: $query, wantsFocus: true,
                        move: moveHighlight, submit: selectHighlighted, cancel: onDismiss)
                        .frame(height: 22)
                }.padding(8)
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(choices) { choice in
                                ProjectPickerChoice(name: choice.name,
                                    selected: choice.all ? allSelected : !allSelected && choice.project == selectedProject,
                                    highlighted: highlighted == choice.id,
                                    symbol: choice.all ? "square.stack.3d.up" : choice.project == nil ? "tray" : "folder",
                                    select: { select(choice) },
                                    receive: allowsDrop && !choice.all ? { state.explorerInput.receive($0, project: choice.project) } : nil)
                                    .id(choice.id)
                            }
                            if choices.isEmpty {
                                Text("No matching projects").foregroundStyle(Palette.muted)
                                    .frame(maxWidth: .infinity).padding(.vertical, 18)
                            }
                        }
                    }.frame(maxHeight: 238)
                        .onChange(of: highlighted) { _, id in if let id { proxy.scrollTo(id) } }
                }
                Divider()
                Button { name = query; creating = true; error = nil; field = .name } label: {
                    Label("New project", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                }.buttonStyle(.plain).accessibilityIdentifier("project-picker-new")
            }
            if let error {
                Text(error).font(.system(size: 12)).foregroundStyle(Palette.task)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("project-picker-error")
            }
        }.font(.system(size: 13)).foregroundStyle(Palette.foreground)
            .padding(12).frame(width: 288).background(Palette.surface)
            .onAppear { field = creating ? .name : .search; highlighted = choices.first(where: { $0.all ? allSelected : !allSelected && $0.project == selectedProject })?.id ?? choices.first?.id }
            .onChange(of: query) { _, _ in highlighted = choices.first?.id }
            .onMoveCommand { direction in
                guard !creating, direction == .up || direction == .down, !choices.isEmpty else { return }
                moveHighlight(direction == .down ? 1 : -1)
            }
            .onExitCommand { if creating { creating = false; error = nil; field = .search } else { onDismiss() } }
            .accessibilityElement(children: .contain).accessibilityLabel("Choose project")
    }

    private var creation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New project").font(.system(size: 18, weight: .semibold, design: .rounded))
            TextField("Client or project name", text: $name).textFieldStyle(.roundedBorder)
                .focused($field, equals: .name).onSubmit(create)
                .accessibilityLabel("New project name").accessibilityIdentifier("project-picker-name")
            HStack {
                Button("Cancel") { creating = false; error = nil; field = .search }
                Spacer()
                Button("Create project", action: create).buttonStyle(.borderedProminent).tint(accent)
                    .accessibilityIdentifier("project-picker-create")
            }
        }.padding(4)
    }
    private func moveHighlight(_ step: Int) {
        guard !creating, !choices.isEmpty else { return }
        let index = choices.firstIndex(where: { $0.id == highlighted }) ?? 0
        highlighted = choices[min(choices.count - 1, max(0, index + step))].id
    }
    private func selectHighlighted() {
        if let choice = choices.first(where: { $0.id == highlighted }) ?? choices.first { select(choice) }
    }
    private func select(_ choice: Choice) {
        do { try onSelect(choice.project, choice.all); onDismiss() }
        catch { self.error = error.localizedDescription }
    }
    private func create() {
        if let message = ProjectNamePolicy.validationMessage(name, existing: projects) { error = message; return }
        let value = ProjectNamePolicy.normalized(name)
        do {
            try workspace.setScratchpad(text: "", project: value)
            do { try onSelect(value, false); onDismiss() }
            catch {
                creating = false; query = value; highlighted = "project:" + value; field = .search
                self.error = "Project created. Filing needs another try: " + error.localizedDescription
            }
        } catch { self.error = error.localizedDescription }
    }
}

/// AppKit's field editor consumes arrow keys before SwiftUI's onMoveCommand.
/// Handle only picker navigation commands here; ordinary editing and Tab retain
/// the native responder chain and never require global keyboard monitoring.
@MainActor private struct ProjectSearchField: NSViewRepresentable {
    @Binding var text: String
    let wantsFocus: Bool
    let move: (Int) -> Void
    let submit: () -> Void
    let cancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> SearchField {
        let field = SearchField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.textColor = .labelColor
        field.placeholderString = "Find a project"
        field.setAccessibilityLabel("Search projects")
        field.setAccessibilityIdentifier("project-picker-search")
        field.delegate = context.coordinator
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: SearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        field.wantsSearchFocus = wantsFocus
        field.requestInitialFocusIfNeeded()
    }

    final class SearchField: NSTextField {
        var wantsSearchFocus = false
        private var requestedFocus = false
        private var queuedFocus = false
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            requestInitialFocusIfNeeded()
        }
        func requestInitialFocusIfNeeded() {
            guard wantsSearchFocus else { requestedFocus = false; return }
            guard !requestedFocus, !queuedFocus, window != nil else { return }
            queuedFocus = true
            // SwiftUI ends the removed creation field's editing after mounting
            // this view. Request once after that cleanup, never on each update.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.queuedFocus = false
                guard self.wantsSearchFocus, !self.requestedFocus, let window = self.window,
                      window.isVisible else { return }
                self.requestedFocus = window.makeFirstResponder(self)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ProjectSearchField
        init(parent: ProjectSearchField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch NSStringFromSelector(commandSelector) {
            case "moveDown:": parent.move(1); return true
            case "moveUp:": parent.move(-1); return true
            case "insertNewline:": parent.submit(); return true
            case "cancelOperation:": parent.cancel(); return true
            default: return false
            }
        }
    }
}

@MainActor private struct ProjectPickerChoice: View {
    let name: String
    let selected: Bool
    let highlighted: Bool
    let symbol: String
    let select: () -> Void
    let receive: (([NSItemProvider]) -> Bool)?
    @State private var targeted = false
    @Environment(\.daBinAccent) private var accent
    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 28, height: 28)
                    .background(Palette.background, in: RoundedRectangle(cornerRadius: 7))
                Text(name).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                if selected { Image(systemName: "checkmark").foregroundStyle(accent) }
            }.frame(minHeight: 36).padding(6).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .background(targeted ? accent.opacity(0.12) : selected || highlighted ? Palette.soft : .clear,
                        in: RoundedRectangle(cornerRadius: 9))
            .onDrop(of: receive == nil ? [] : ExplorerTransfer.acceptedTypeIdentifiers, isTargeted: $targeted) { receive?($0) ?? false }
            .accessibilityLabel("Project \(name)").accessibilityAddTraits(selected ? .isSelected : [])
    }
}

@MainActor struct CaptureProjectPickerButton: View {
    @ObservedObject var state: AppState
    @ObservedObject var capture: Capture
    @State private var presented = false
    @FocusState private var focused: Bool
    var body: some View {
        Button { presented.toggle() } label: {
            Label(capture.projectName ?? "Project", systemImage: "folder")
                .font(.system(size: 12)).lineLimit(1).frame(minHeight: 32)
        }.buttonStyle(.plain).foregroundStyle(Palette.muted).focused($focused)
            .accessibilityLabel("Project").accessibilityValue(capture.projectName ?? "Unfiled")
            .buddyHelp("File this capture to a project")
            .disabled(capture.parentTaskID != nil)
            .popover(isPresented: $presented, arrowEdge: .bottom) {
                ProjectPickerPanel(state: state, selectedProject: capture.projectName, onSelect: { name, _ in
                    try state.store.setOrganization(capture, pinned: capture.isPinned, projectName: name)
                }, onDismiss: { presented = false; focused = true })
            }
    }
}
