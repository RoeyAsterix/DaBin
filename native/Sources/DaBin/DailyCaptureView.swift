import AppKit
import SwiftUI

/// A native destination around the existing board. Normal child hit testing
/// stays intact, so captures, filters and the movable header remain interactive.
@MainActor
final class DailyCaptureHostingView: NSHostingView<BoardView> {
    private weak var state: AppState?
    var onPaste: (() -> Void)?
    var onDrop: ((NSPasteboard) -> Void)?
    var onDragState: ((Bool) -> Void)?
    private var lastPasteEvent: NSEvent?

    init(state: AppState, theme: ThemeSettings? = nil) {
        self.state = state
        super.init(rootView: BoardView(state: state, theme: theme))
        sizingOptions = []
        registerForDraggedTypes(InputService.dragTypes)
    }

    @MainActor required init(rootView: BoardView) { fatalError("Use init(state:)") }
    @MainActor required dynamic init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var acceptsCapture: Bool { state?.route == .daily }
    private var isEditingText: Bool {
        if let text = window?.firstResponder as? NSTextView { return text.isEditable }
        if let field = window?.firstResponder as? NSTextField { return field.isEditable }
        return false
    }
    var canPasteCapture: Bool { acceptsCapture && !isEditingText && onPaste != nil }

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
        handlePasteShortcut(event) || super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if !handlePasteShortcut(event) { super.keyDown(with: event) }
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

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
        if event.type == .keyDown, modifiers == .command,
           event.charactersIgnoringModifiers?.lowercased() == "w", let onRequestClose {
            onRequestClose()
            return true
        }
        return captureView?.handlePasteShortcut(event) == true || super.performKeyEquivalent(with: event)
    }

    override func performClose(_ sender: Any?) {
        if let onRequestClose { onRequestClose() }
        else { super.performClose(sender) }
    }

    override func keyDown(with event: NSEvent) {
        if captureView?.handlePasteShortcut(event) != true { super.keyDown(with: event) }
    }

    @objc func paste(_ sender: Any?) { captureView?.pasteCapture(sender) }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(paste(_:)) { return captureView?.canPasteCapture == true }
        return super.validateUserInterfaceItem(item)
    }
}
