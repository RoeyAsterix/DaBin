import AppKit
import QuartzCore

@MainActor
final class RobotView: NSView {
    var onPaste: (() -> Void)?
    var onDaily: (() -> Void)?
    var onDrop: ((NSPasteboard) -> Void)?
    var onDragState: ((Bool) -> Void)?
    var onFocus: (() -> Void)?
    var onHoverChange: (() -> Void)?
    private let character: RobotCharacterView
    private let indicator = NSTextField(labelWithString: "")
    private var feedbackTask: Task<Void, Never>?
    private var hoverTrackingArea: NSTrackingArea?
    private var lastPasteEvent: NSEvent?
    private(set) var isPresented = false
    var mood: RobotMood { character.mood }
    var motionState: RobotMotionState { character.motionState }
    var hasActiveAmbientMotion: Bool { character.hasActiveAmbientMotion }
    var isSaving = false {
        didSet {
            updateIndicator()
            if isSaving != oldValue { character.send(.saving(isSaving)) }
        }
    }
    private var isOverDrop = false { didSet { updateIndicator() } }
    private var feedback: String?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(frame frameRect: NSRect, reduceMotion: @escaping RobotCharacterView.ReduceMotionProvider = {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }) {
        character = RobotCharacterView(frame: frameRect.insetBy(dx: 4, dy: 4), reduceMotion: reduceMotion)
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(character)
        indicator.frame = NSRect(x: 43, y: 61, width: 25, height: 22)
        indicator.font = .systemFont(ofSize: 14, weight: .semibold)
        indicator.alignment = .center
        indicator.textColor = .white
        indicator.wantsLayer = true
        indicator.layer?.backgroundColor = NSColor(calibratedRed: 0.42, green: 0.31, blue: 0.55, alpha: 1).cgColor
        indicator.layer?.cornerRadius = 10
        indicator.isHidden = true
        addSubview(indicator)
        registerForDraggedTypes(InputService.dragTypes)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("DaBin purple robot")
        setAccessibilityHelp("Drop onto the robot, or hover over it and press Control V or Command V to paste. Clicking also focuses the robot. Double-click or press Return to open Daily. Escape hides DaBin.")
        toolTip = "Drop here · hover then ⌃V or ⌘V to paste · double-click for Daily"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() { super.layout(); character.frame = bounds.insetBy(dx: 4, dy: 4) }

    // The image and feedback badge are decoration. Keep the entire compact
    // robot one destination, including where the badge covers the artwork.
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: bounds.insetBy(dx: 4, dy: 4),
                                  options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
                                  owner: self, userInfo: nil)
        hoverTrackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        character.send(.hover(true, pointer: normalizedPointer(for: event)))
        onHoverChange?()
    }
    override func mouseMoved(with event: NSEvent) {
        character.send(.hover(true, pointer: normalizedPointer(for: event)))
    }
    override func mouseExited(with event: NSEvent) {
        character.send(.hover(false))
        onHoverChange?()
    }

    override func mouseDown(with event: NSEvent) {
        onFocus?()
        window?.makeKey()
        window?.makeFirstResponder(self)
        if event.clickCount == 2 { onDaily?() }
    }

    override func keyDown(with event: NSEvent) {
        if handlePasteShortcut(event) { return }
        if event.charactersIgnoringModifiers == "\r" || event.charactersIgnoringModifiers == " " { onDaily?() }
        else if event.keyCode == 53 { window?.orderOut(nil) }
        else { super.keyDown(with: event) }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handlePasteShortcut(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    static func isPasteShortcut(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
        guard modifiers == .control || modifiers == .command else { return false }
        // Some layouts report Control-V as its literal control character.
        return event.charactersIgnoringModifiers?.lowercased() == "v" ||
            (modifiers == .control && event.characters == "\u{16}")
    }

    @discardableResult
    func handlePasteShortcut(_ event: NSEvent) -> Bool {
        guard Self.isPasteShortcut(event) else { return false }
        // Consume repeats without capturing, and share one path with Edit > Paste.
        // AppKit can route the same event through more than one responder method.
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

    @objc func paste(_ sender: Any?) {
        if let event = NSApp.currentEvent, handlePasteShortcut(event) { return }
        onPaste?()
    }
    @objc private func showDaily(_ sender: Any?) { onDaily?() }
    override func accessibilityPerformPress() -> Bool { onDaily?(); return true }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let paste = menu.addItem(withTitle: "Paste into DaBin", action: #selector(paste(_:)), keyEquivalent: "")
        paste.target = self
        let daily = menu.addItem(withTitle: "Open Daily", action: #selector(showDaily(_:)), keyEquivalent: "")
        daily.target = self
        return menu
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDropTarget(sender)
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDropTarget(sender)
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { setDropActive(false) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        updateDropTarget(sender) == .copy
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { setDropActive(false) }
        guard acceptsDrop(sender), let onDrop else { return false }
        // Read the representations synchronously while AppKit still owns the
        // transfer. InputService then imports them asynchronously into the archive.
        onDrop(sender.draggingPasteboard)
        return true
    }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) { setDropActive(false) }
    override func draggingEnded(_ sender: NSDraggingInfo) { setDropActive(false) }

    private func acceptsDrop(_ sender: NSDraggingInfo) -> Bool {
        onDrop != nil && sender.draggingSourceOperationMask.contains(.copy)
            && InputService.canReceive(sender.draggingPasteboard)
    }

    private func updateDropTarget(_ sender: NSDraggingInfo) -> NSDragOperation {
        let accepted = acceptsDrop(sender)
        setDropActive(accepted)
        return accepted ? .copy : []
    }

    private func setDropActive(_ active: Bool) {
        guard isOverDrop != active else { return }
        isOverDrop = active
        character.send(.acceptedDrag(active))
        onDragState?(active)
    }

    func present(from entrance: RobotEntrance) {
        isPresented = true
        character.send(.reveal(entrance))
    }

    func hideCharacter() {
        isPresented = false
        character.send(.hide)
    }

    func refreshMotionPreference() { character.refreshMotionPreference() }

    func stopFeedback() {
        feedbackTask?.cancel(); feedbackTask = nil
        feedback = nil; isSaving = false; isOverDrop = false
        isPresented = false
        character.stopMotion()
        updateIndicator()
    }

    func digest(success: Bool, partial: Bool = false) {
        feedbackTask?.cancel()
        feedback = success ? (partial ? "!" : "✓") : "!"
        updateIndicator()
        character.send(.result(success ? (partial ? .partialSuccess : .success) : .failure))
        NSAccessibility.post(element: self, notification: .announcementRequested, userInfo: [
            .announcement: success ? (partial ? "Some captures saved; some items failed" : "Capture saved") : "Capture failed",
            .priority: NSAccessibilityPriorityLevel.medium.rawValue
        ])
        feedbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.3))
            guard !Task.isCancelled else { return }
            self?.feedback = nil
            self?.character.send(.feedbackExpired)
            self?.updateIndicator()
        }
    }

    private func normalizedPointer(for event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.width > 0, bounds.height > 0 else { return .zero }
        return CGPoint(x: min(1, max(-1, (point.x - bounds.midX) / (bounds.width / 2))),
                       y: min(1, max(-1, (bounds.midY - point.y) / (bounds.height / 2))))
    }

    private func updateIndicator() {
        indicator.stringValue = feedback ?? (isSaving ? "…" : (isOverDrop ? "↓" : ""))
        indicator.isHidden = indicator.stringValue.isEmpty
        needsDisplay = true
    }
}
