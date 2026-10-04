import AppKit
import SwiftUI

/// Stable identities belong to the production editor, independently of its
/// text, accessibility label or SwiftUI's private native view identifiers.
enum NavigationEditorTarget: String {
    case newTask = "navigation-editor:new-task"
    case newNote = "navigation-editor:new-note"
    case detailTitle = "navigation-editor:detail-title"
    case recoveredComment = "navigation-editor:recovered-comment"
    case commentComposer = "navigation-editor:comment-composer"
}

@MainActor struct NavigationEditorRegion: NSViewRepresentable {
    let target: NavigationEditorTarget
    func makeNSView(context: Context) -> NavigationEditorRegionView { NavigationEditorRegionView(target: target) }
    func updateNSView(_ view: NavigationEditorRegionView, context: Context) { view.target = target }
}

/// The region is attached directly to one editor. SwiftUI does not copy its
/// virtual accessibility identifiers to NSTextView/NSTextField, so match that
/// region's native control by its actual layout. Never identify an editor from
/// user text, a translated label, or its position in a list of controls.
@MainActor final class NavigationEditorRegionView: NSView {
    var target: NavigationEditorTarget
    init(target: NavigationEditorTarget) { self.target = target; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    static func regions(in view: NSView) -> [NavigationEditorRegionView] {
        (view as? NavigationEditorRegionView).map { [$0] } ?? view.subviews.flatMap { regions(in: $0) }
    }

    func editor(in root: NSView) -> NSView? {
        let region = convert(bounds, to: root)
        guard region.width > 0, region.height > 0, !isHiddenOrHasHiddenAncestor else { return nil }
        func controls(in view: NSView) -> [NSView] {
            if let field = view as? NSTextField, field.isEditable { return [field] }
            if let text = view as? NSTextView, text.isEditable, !text.isFieldEditor { return [text] }
            return view.subviews.flatMap { controls(in: $0) }
        }
        let matches = controls(in: root).compactMap { view -> (NSView, CGFloat)? in
            guard !view.isHiddenOrHasHiddenAncestor else { return nil }
            let surface = view is NSTextView ? (view.enclosingScrollView ?? view) : view
            let frame = surface.convert(surface.bounds, to: root)
            let intersection = region.intersection(frame)
            let area = min(region.width * region.height, frame.width * frame.height)
            guard area > 0, !intersection.isNull,
                  intersection.width * intersection.height / area > 0.75 else { return nil }
            return (view, abs(region.midX - frame.midX) + abs(region.midY - frame.midY))
        }
        return matches.min { $0.1 < $1.1 }?.0
    }
}

/// A native destination around the existing board. Normal child hit testing
/// stays intact, so captures, filters and the movable header remain interactive.
@MainActor
final class DailyCaptureHostingView: NSHostingView<BoardView> {
    private weak var state: AppState?
    private(set) var workspaceInput: WorkspaceInputController!
    var onPaste: (() -> Void)?
    var onDrop: ((NSPasteboard) -> Void)?
    var onDragState: ((Bool) -> Void)?
    var searchPasteboardProvider: () -> NSPasteboard = { .general }
    private var lastPasteEvent: NSEvent?
    private var lastSearchPasteEvent: NSEvent?
    private var navigationFocusRequestRevision: UInt = 0

    init(state: AppState, theme: ThemeSettings? = nil) {
        self.state = state
        super.init(rootView: BoardView(state: state, theme: theme))
        workspaceInput = WorkspaceInputController(state: state, host: self)
        sizingOptions = []
        registerForDraggedTypes(InputService.dragTypes)
    }

    @MainActor required init(rootView: BoardView) { fatalError("Use init(state:)") }
    @MainActor required dynamic init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var acceptsCapture: Bool {
        state?.route == .daily || state?.route == .inbox
            || (state?.route == .library && state?.workspace.mode == .collection)
            || (state?.route == .detail && state?.selectedCapture?.isTask == true)
    }
    private var isEditingText: Bool {
        if let text = window?.firstResponder as? NSTextView { return text.isEditable }
        if let field = window?.firstResponder as? NSTextField { return field.isEditable }
        return false
    }
    var canPasteCapture: Bool { acceptsCapture && !isEditingText && onPaste != nil }
    var canPasteSearch: Bool {
        state?.route == .search && !isEditingText && window?.attachedSheet == nil
            && searchTextField != nil
    }

    private var searchTextField: NSTextField? {
        func find(in view: NSView) -> NSTextField? {
            // SwiftUI keeps the accessibility identifier on its virtual
            // element, while the native text field retains its placeholder.
            if let field = view as? NSTextField, field.isEditable,
               field.placeholderString == BoardView.searchPlaceholder { return field }
            for child in view.subviews {
                if let field = find(in: child) { return field }
            }
            return nil
        }
        return find(in: self)
    }

    /// Recover the query editor when a result or header control owns focus.
    /// Native editors keep their normal selection-aware responder-chain paste.
    @discardableResult
    func pasteSearch(_ sender: Any?) -> Bool {
        guard canPasteSearch, let field = searchTextField, let window else { return false }
        let pasteboard = searchPasteboardProvider()
        guard pasteboard.string(forType: .string) != nil,
              window.makeFirstResponder(field), let editor = field.currentEditor() as? NSTextView else { return true }
        _ = editor.readSelection(from: pasteboard, type: .string)
        return true
    }

    @discardableResult
    func handleSearchPasteShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
        guard state?.route == .search, let window, event.windowNumber == window.windowNumber,
              event.type == .keyDown, modifiers == .command,
              event.charactersIgnoringModifiers?.lowercased() == "v" else { return false }
        if let previous = lastSearchPasteEvent,
           previous === event || (previous.timestamp == event.timestamp && previous.windowNumber == event.windowNumber
                && previous.keyCode == event.keyCode && previous.modifierFlags == event.modifierFlags) { return true }
        guard canPasteSearch else { return false }
        guard !event.isARepeat else { return true }
        lastSearchPasteEvent = event
        return pasteSearch(nil)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        navigationFocusRequestRevision &+= 1
        workspaceInput?.attach(to: window)
        state?.onCaptureNavigationFocus = { [weak self] in
            guard let self, let view = self.window?.firstResponder as? NSView else { return nil }
            let editor = view as? NSTextView
            let field = editor?.delegate as? NSTextField
            let control = field ?? view
            let boundTarget = NavigationEditorRegionView.regions(in: self).first { $0.editor(in: self) === control }?.target
            let identifier = boundTarget?.rawValue ?? control.identifier?.rawValue
                ?? (field?.placeholderString == BoardView.searchPlaceholder ? "global-search" : nil)
            guard let identifier else { return nil }
            let focus = NativeNavigationFocus(identifier: identifier, location: editor?.selectedRange().location,
                                              length: editor?.selectedRange().length)
            return focus.encoded
        }
        state?.onRestoreNavigationFocus = { [weak self] encoded in
            guard let self else { return }
            self.navigationFocusRequestRevision &+= 1
            guard let encoded, let state = self.state, let targetWindow = self.window else { return }
            let requestRevision = self.navigationFocusRequestRevision
            let transitionRevision = state.navigationTransitionRevision
            let focus = NativeNavigationFocus.decode(encoded)
            DispatchQueue.main.async { [weak self, weak targetWindow] in
                guard let self, let window = self.window, window === targetWindow, window.isKeyWindow,
                      self.navigationFocusRequestRevision == requestRevision,
                      self.state?.navigationTransitionRevision == transitionRevision else { return }
                self.layoutSubtreeIfNeeded()
                func find(_ view: NSView) -> NSView? {
                    if view.identifier?.rawValue == focus.identifier { return view }
                    for child in view.subviews { if let found = find(child) { return found } }
                    return nil
                }
                let boundTarget = NavigationEditorTarget(rawValue: focus.identifier).flatMap { target in
                    NavigationEditorRegionView.regions(in: self).first { $0.target == target }?.editor(in: self)
                }
                let target = boundTarget ?? (focus.identifier == "global-search" ? self.searchTextField : find(self))
                if let target, window.makeFirstResponder(target),
                   self.state?.navigationTransitionRevision == transitionRevision,
                   let editor = window.firstResponder as? NSTextView,
                   editor === target || (target as? NSTextField)?.currentEditor() === editor {
                    editor.setSelectedRange(focus.selection(clampedTo: (editor.string as NSString).length))
                }
            }
        }
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @discardableResult
    func handlePasteShortcut(_ event: NSEvent) -> Bool {
        guard canPasteCapture, RobotView.isPasteShortcut(event) else { return false }
        // AppKit may dispatch the same gesture via the panel, hosting view and
        // Edit menu. Only the first dispatch saves a capture.
        guard !event.isARepeat else { return true }
        if let lastPasteEvent,
           lastPasteEvent === event ||
           (lastPasteEvent.timestamp == event.timestamp &&
            lastPasteEvent.windowNumber == event.windowNumber &&
            lastPasteEvent.keyCode == event.keyCode &&
            lastPasteEvent.modifierFlags == event.modifierFlags) { return true }
        lastPasteEvent = event
        onPaste?()
        return true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleSearchPasteShortcut(event) || handlePasteShortcut(event) || workspaceInput.key(event) || super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if !handleSearchPasteShortcut(event), !handlePasteShortcut(event), !workspaceInput.key(event) { super.keyDown(with: event) }
    }

    func pasteCapture(_ sender: Any?) {
        guard canPasteCapture else { return }
        if let event = NSApp.currentEvent, handlePasteShortcut(event) { return }
        onPaste?()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { updateDrop(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { updateDrop(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { clearDropTarget() }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { updateDrop(sender) == .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { clearDropTarget() }
        guard acceptsDrop(sender), let onDrop else { return false }
        // Keep native file URL transfer grants alive by consuming the
        // pasteboard synchronously inside AppKit's accepted drop callback.
        onDrop(sender.draggingPasteboard)
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) { clearDropTarget() }
    override func draggingEnded(_ sender: NSDraggingInfo) { clearDropTarget() }

    func clearDropTarget() { setDropActive(false) }

    private func acceptsDrop(_ sender: NSDraggingInfo) -> Bool {
        acceptsCapture && !isEditingText && onDrop != nil &&
            sender.draggingSourceOperationMask.contains(.copy) &&
            InputService.canReceive(sender.draggingPasteboard)
    }

    private func updateDrop(_ sender: NSDraggingInfo) -> NSDragOperation {
        let accepted = acceptsDrop(sender)
        setDropActive(accepted)
        return accepted ? .copy : []
    }

    private func setDropActive(_ active: Bool) {
        // The route can clear the visible highlight between drag callbacks.
        // Reconcile it on every update; the state owner suppresses duplicates.
        if active { workspaceInput.cancel() }
        onDragState?(active)
    }
}

/// Panel fallback handles paste with a button or the window itself focused.
/// Native text editors continue to receive their own normal paste actions.
@MainActor
final class DailyCapturePanel: DaBinPanel {
    var onRequestClose: (() -> Void)?
    weak var captureHostingView: DailyCaptureHostingView?
    private var captureView: DailyCaptureHostingView? {
        captureHostingView ?? contentView as? DailyCaptureHostingView
    }

    override func sendEvent(_ event: NSEvent) {
        if captureView?.workspaceInput.handle(event) == true { return }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
        if event.type == .keyDown, modifiers == .command,
           event.charactersIgnoringModifiers?.lowercased() == "w", let onRequestClose {
            onRequestClose()
            return true
        }
        return captureView?.handleSearchPasteShortcut(event) == true
            || captureView?.handlePasteShortcut(event) == true
            || captureView?.workspaceInput.key(event) == true || super.performKeyEquivalent(with: event)
    }

    override func performClose(_ sender: Any?) {
        if let onRequestClose { onRequestClose() }
        else { super.performClose(sender) }
    }

    override func keyDown(with event: NSEvent) {
        if captureView?.handleSearchPasteShortcut(event) != true,
           captureView?.handlePasteShortcut(event) != true,
           captureView?.workspaceInput.key(event) != true { super.keyDown(with: event) }
    }

    @objc func navigateBack(_ sender: Any?) { dispatch(.back) }
    @objc func navigateForward(_ sender: Any?) { dispatch(.forward) }
    @objc func zoomWorkspaceIn(_ sender: Any?) { dispatch(.zoomIn) }
    @objc func zoomWorkspaceOut(_ sender: Any?) { dispatch(.zoomOut) }
    @objc func resetWorkspaceZoom(_ sender: Any?) { dispatch(.resetZoom) }
    func dispatch(_ command: WorkspaceCommand) {
        let event = NSApp.currentEvent
        let commandEvent = event?.type == .keyDown && WorkspaceInputPolicy.command(
            characters: event?.charactersIgnoringModifiers ?? "", modifiers: event?.modifierFlags ?? []) == command ? event : nil
        _ = captureView?.workspaceInput.perform(command, event: commandEvent)
    }
    func canPerformWorkspaceCommand(_ command: WorkspaceCommand) -> Bool { captureView?.workspaceInput.enabled(command) == true }
    private func command(for action: Selector?) -> WorkspaceCommand? {
        switch action {
        case #selector(navigateBack(_:)): return .back
        case #selector(navigateForward(_:)): return .forward
        case #selector(zoomWorkspaceIn(_:)): return .zoomIn
        case #selector(zoomWorkspaceOut(_:)): return .zoomOut
        case #selector(resetWorkspaceZoom(_:)): return .resetZoom
        default: return nil
        }
    }

    @objc func paste(_ sender: Any?) {
        if captureView?.pasteSearch(sender) != true { captureView?.pasteCapture(sender) }
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if let command = command(for: item.action) { return captureView?.workspaceInput.enabled(command) == true }
        if item.action == #selector(paste(_:)) {
            return captureView?.canPasteSearch == true || captureView?.canPasteCapture == true
        }
        return super.validateUserInterfaceItem(item)
    }
}

/// Stores only a control identity and UTF-16 selection offsets, never editor
/// text. Returning to a field must not select or overwrite its contents.
struct NativeNavigationFocus: Codable {
    var identifier: String
    var location: Int?
    var length: Int?
    var encoded: String? { try? String(data: JSONEncoder().encode(self), encoding: .utf8) }
    static func decode(_ value: String) -> Self {
        guard let data = value.data(using: .utf8), let decoded = try? JSONDecoder().decode(Self.self, from: data) else {
            return Self(identifier: value)
        }
        return decoded
    }
    func selection(clampedTo count: Int) -> NSRange {
        let location = min(max(0, location ?? count), count)
        return NSRange(location: location, length: min(max(0, length ?? 0), count - location))
    }
}
