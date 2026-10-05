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

/// A deliberately small palette keeps project identity recognizable in both
/// appearances. WorkspaceStore persists only the canonical six-digit RGB value;
/// the display name is intentionally localizable presentation, not stored data.
struct ProjectColorChoice: Identifiable, Hashable {
    let name: String
    let hex: String
    var id: String { hex }

    static let palette: [ProjectColorChoice] = [
        .init(name: "Violet", hex: "7568D8"),
        .init(name: "Blue", hex: "3478D4"),
        .init(name: "Teal", hex: "198F91"),
        .init(name: "Green", hex: "3C8B5F"),
        .init(name: "Amber", hex: "C47A16"),
        .init(name: "Coral", hex: "C65F4B"),
        .init(name: "Rose", hex: "B9537A"),
        .init(name: "Slate", hex: "657083")
    ]

    static func nsColor(for hex: String) -> NSColor {
        let canonical = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted).uppercased()
        let fallback = UInt32(WorkspaceStore.defaultProjectColorHex, radix: 16) ?? 0x7568D8
        let value = canonical.count == 6 ? (UInt32(canonical, radix: 16) ?? fallback) : fallback
        return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                       green: CGFloat((value >> 8) & 255) / 255,
                       blue: CGFloat(value & 255) / 255,
                       alpha: 1)
    }

    static func color(for hex: String) -> Color { Color(nsColor: nsColor(for: hex)) }
}

@MainActor
struct ProjectChipLabel: View {
    @Environment(\.workspaceZoom) private var zoom
    let name: String?
    let colorHex: String?
    var inherited = false

    private var title: String { name ?? "Unfiled" }
    private var color: Color { colorHex.map(ProjectColorChoice.color(for:)) ?? Palette.muted }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: name == nil ? "tray" : "folder.fill")
                .font(.system(size: zoom.fontSize(11), weight: .semibold)).foregroundStyle(color)
            Text(title).font(.system(size: zoom.fontSize(12), weight: .semibold)).lineLimit(1)
            if inherited {
                Image(systemName: "link").font(.system(size: zoom.fontSize(8), weight: .semibold)).foregroundStyle(Palette.muted)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(Palette.foreground)
        .padding(.horizontal, 9).frame(minHeight: 28)
        .background(color.opacity(name == nil ? 0.06 : 0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(name == nil ? 0.3 : 0.62), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(inherited ? "Parent task project" : "Project")
        .accessibilityValue(title)
    }
}

@MainActor
private struct ProjectCardBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var workspace: WorkspaceStore
    let projectName: String?
    let cornerRadius: CGFloat
    let baseColor: Color
    let enabled: Bool

    func body(content: Content) -> some View {
        content.background {
            if enabled {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(baseColor)
                    .overlay {
                        if let projectName {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(ProjectColorChoice.color(for: workspace.projectColorHex(for: projectName)
                                    ?? WorkspaceStore.defaultProjectColorHex)
                                    .opacity(colorScheme == .dark ? 0.10 : 0.08))
                        }
                    }
                    .allowsHitTesting(false)
            }
        }
    }
}

@MainActor
private struct ProjectCardFrameModifier: ViewModifier {
    @ObservedObject var workspace: WorkspaceStore
    let projectName: String?
    let activeProject: String?
    let cornerRadius: CGFloat
    let fallbackColor: Color
    let fallbackWidth: CGFloat

    func body(content: Content) -> some View {
        let projectIsActive = projectName != nil && projectName == activeProject
        let frameColor = projectIsActive
            ? ProjectColorChoice.color(for: workspace.projectColorHex(for: projectName!)
                ?? WorkspaceStore.defaultProjectColorHex)
            : fallbackColor
        content.overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(frameColor, lineWidth: projectIsActive ? 1.8 : fallbackWidth)
        }
    }
}

extension View {
    /// Color belongs to the capture's project, including inherited task filing,
    /// independently of the browsing scope. Keep the tint behind all content.
    @MainActor
    func projectCardBackground(workspace: WorkspaceStore, projectName: String?,
                               cornerRadius: CGFloat = 14, baseColor: Color = Palette.surface,
                               enabled: Bool = true) -> some View {
        modifier(ProjectCardBackgroundModifier(workspace: workspace, projectName: projectName,
                                               cornerRadius: cornerRadius, baseColor: baseColor,
                                               enabled: enabled))
    }

    @MainActor
    func projectCardFrame(workspace: WorkspaceStore, projectName: String?, activeProject: String?,
                          cornerRadius: CGFloat = 14, fallbackColor: Color = Palette.line,
                          fallbackWidth: CGFloat = 0.7) -> some View {
        modifier(ProjectCardFrameModifier(workspace: workspace, projectName: projectName,
                                          activeProject: activeProject, cornerRadius: cornerRadius,
                                          fallbackColor: fallbackColor, fallbackWidth: fallbackWidth))
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
    let validateSelection: () throws -> Void
    let onSelect: (String?, Bool) throws -> Void
    let onDismiss: () -> Void
    @State private var query = ""
    @State private var creating: Bool
    @State private var name = ""
    @State private var colorHex = WorkspaceStore.defaultProjectColorHex
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
         validateSelection: @escaping () throws -> Void = {},
         onSelect: @escaping (String?, Bool) throws -> Void, onDismiss: @escaping () -> Void) {
        self.state = state; _workspace = ObservedObject(wrappedValue: state.workspace)
        self.selectedProject = selectedProject; self.allowsAll = allowsAll
        self.allSelected = allSelected; self.allowsDrop = allowsDrop
        self.validateSelection = validateSelection
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
                                    colorHex: choice.project.flatMap { workspace.projectColorHex(for: $0) }
                                        ?? choice.project.map { _ in WorkspaceStore.defaultProjectColorHex },
                                    select: { select(choice) },
                                    setColor: choice.project.map { project in
                                        { hex in
                                            do { try workspace.setProjectColor(hex: hex, for: project) }
                                            catch { self.error = error.localizedDescription }
                                        }
                                    },
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
            VStack(alignment: .leading, spacing: 7) {
                Text("Project color").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted)
                HStack(spacing: 4) {
                    ForEach(ProjectColorChoice.palette) { choice in
                        Button { colorHex = choice.hex } label: {
                            Circle().fill(ProjectColorChoice.color(for: choice.hex)).frame(width: 22, height: 22)
                                .overlay {
                                    if colorHex == choice.hex {
                                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                                    }
                                }
                                .frame(width: 28, height: 28).contentShape(Circle())
                        }.buttonStyle(.plain)
                            .accessibilityLabel("\(choice.name) project color")
                            .accessibilityAddTraits(colorHex == choice.hex ? .isSelected : [])
                    }
                }.accessibilityElement(children: .contain)
            }
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
        do { try validateSelection(); try onSelect(choice.project, choice.all); onDismiss() }
        catch { self.error = error.localizedDescription }
    }
    private func create() {
        if let message = ProjectNamePolicy.validationMessage(name, existing: projects) { error = message; return }
        let value = ProjectNamePolicy.normalized(name)
        do {
            // Browsing can become blocked while this panel is already open.
            // Refuse before creating a marker; filing panels keep their own policy.
            try validateSelection()
            try workspace.createProject(name: value, colorHex: colorHex)
            do { try validateSelection(); try onSelect(value, false); onDismiss() }
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
    let colorHex: String?
    let select: () -> Void
    let setColor: ((String) -> Void)?
    let receive: (([NSItemProvider]) -> Bool)?
    @State private var targeted = false
    @Environment(\.daBinAccent) private var accent
    var body: some View {
        HStack(spacing: 4) {
            Button(action: select) {
                HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 28, height: 28)
                        .foregroundStyle(colorHex.map(ProjectColorChoice.color(for:)) ?? Palette.muted)
                        .background((colorHex.map(ProjectColorChoice.color(for:)) ?? Palette.background).opacity(colorHex == nil ? 1 : 0.13),
                                    in: RoundedRectangle(cornerRadius: 7))
                Text(name).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                if selected { Image(systemName: "checkmark").foregroundStyle(accent) }
                }.frame(maxWidth: .infinity, minHeight: 36).padding(6).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel("Project \(name)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            if let setColor, let colorHex {
                Menu {
                    ForEach(ProjectColorChoice.palette) { choice in
                        Button { setColor(choice.hex) } label: {
                            Label(choice.name, systemImage: choice.hex == colorHex ? "checkmark.circle.fill" : "circle.fill")
                        }
                    }
                } label: {
                    Image(systemName: "paintpalette").font(.system(size: 12, weight: .medium))
                        .frame(width: 28, height: 32).contentShape(Rectangle())
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .foregroundStyle(ProjectColorChoice.color(for: colorHex))
                    .accessibilityLabel("Change color for project \(name)")
            }
        }
            .background(targeted ? accent.opacity(0.12) : selected || highlighted ? Palette.soft : Color.clear,
                        in: RoundedRectangle(cornerRadius: 9))
            .onDrop(of: receive == nil ? [] : ExplorerTransfer.acceptedTypeIdentifiers, isTargeted: $targeted) { receive?($0) ?? false }
    }
}

/// Project and priority form one identity row. The project can truncate while
/// the priority keeps its readable label, including in narrow task cards.
@MainActor struct CaptureProjectPriorityHeader: View {
    @ObservedObject var state: AppState
    @ObservedObject var capture: Capture

    var body: some View {
        HStack(spacing: 6) {
            CaptureProjectPickerButton(state: state, capture: capture)
                .layoutPriority(-1)
                .accessibilityIdentifier("capture-project-picker-\(capture.id.uuidString)")
            CaptureTaskPriorityTag(capture: capture).fixedSize()
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture-project-priority-\(capture.id.uuidString)")
    }
}

@MainActor struct CaptureProjectPickerButton: View {
    @ObservedObject var state: AppState
    @ObservedObject var capture: Capture
    @ObservedObject private var workspace: WorkspaceStore
    @State private var presented = false
    @FocusState private var focused: Bool

    init(state: AppState, capture: Capture) {
        self.state = state
        self.capture = capture
        _workspace = ObservedObject(wrappedValue: state.workspace)
    }

    private var projectName: String? { ExplorerQuery.project(of: capture, in: state.store.captures) }
    private var colorHex: String? {
        projectName.map { workspace.projectColorHex(for: $0) ?? WorkspaceStore.defaultProjectColorHex }
    }

    @ViewBuilder
    var body: some View {
        if capture.parentTaskID != nil {
            ProjectChipLabel(name: projectName, colorHex: colorHex, inherited: true)
                .buddyHelp("Inherited from the parent task")
        } else {
            Button { presented.toggle() } label: {
                HStack(spacing: 5) {
                    ProjectChipLabel(name: projectName, colorHex: colorHex)
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(Palette.muted)
                }.frame(minWidth: 32, minHeight: 32).contentShape(Rectangle())
            }.buttonStyle(.plain).focused($focused)
                .accessibilityLabel("Project").accessibilityValue(projectName ?? "Unfiled")
                .buddyHelp("File this capture to a project")
                .popover(isPresented: $presented, arrowEdge: .bottom) {
                    ProjectPickerPanel(state: state, selectedProject: capture.projectName, onSelect: { name, _ in
                        try state.store.setOrganization(capture, pinned: capture.isPinned, projectName: name)
                    }, onDismiss: { presented = false; focused = true })
                        .hoverTooltips()
                }
        }
    }
}
