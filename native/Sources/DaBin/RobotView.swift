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
    private let imageView = NSImageView()
    private let indicator = NSTextField(labelWithString: "")
    private var feedbackTask: Task<Void, Never>?
    private var hoverTrackingArea: NSTrackingArea?
    private var lastPasteEvent: NSEvent?
    var isSaving = false { didSet { updateIndicator() } }
    private var isOverDrop = false { didSet { updateIndicator() } }
    private var feedback: String?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        imageView.image = Bundle.main.url(forResource: "robot", withExtension: "svg").flatMap(NSImage.init(contentsOf:))
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.frame = NSRect(x: 4, y: 4, width: 64, height: 78)
        imageView.wantsLayer = true
        addSubview(imageView)
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
    override func layout() { super.layout(); imageView.frame = bounds.insetBy(dx: 4, dy: 4) }

    // The image and feedback badge are decoration. Keep the entire compact
    // robot one destination, including where the badge covers the artwork.
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: bounds.insetBy(dx: 4, dy: 4),
                                  options: [.mouseEnteredAndExited, .activeAlways],
                                  owner: self, userInfo: nil)
        hoverTrackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) { onHoverChange?() }
    override func mouseExited(with event: NSEvent) { onHoverChange?() }

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
        onDragState?(active)
    }

    func stopFeedback() {
        feedbackTask?.cancel(); feedbackTask = nil
        imageView.layer?.removeAnimation(forKey: "digest")
        feedback = nil; isSaving = false; isOverDrop = false
        updateIndicator()
    }

    func digest(success: Bool, partial: Bool = false) {
        feedbackTask?.cancel()
        feedback = success ? (partial ? "!" : "✓") : "!"
        updateIndicator()
        if success && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let chew = CAKeyframeAnimation(keyPath: "transform")
            chew.values = [CATransform3DIdentity,
                           CATransform3DMakeScale(1.08, 0.86, 1),
                           CATransform3DMakeScale(0.96, 1.07, 1),
                           CATransform3DMakeScale(1.04, 0.94, 1), CATransform3DIdentity].map { NSValue(caTransform3D: $0) }
            chew.duration = 0.56
            chew.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            imageView.layer?.add(chew, forKey: "digest")
        }
        NSAccessibility.post(element: self, notification: .announcementRequested, userInfo: [
            .announcement: success ? (partial ? "Some captures saved; some items failed" : "Capture saved") : "Capture failed",
            .priority: NSAccessibilityPriorityLevel.medium.rawValue
        ])
        feedbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.3))
            guard !Task.isCancelled else { return }
            self?.feedback = nil; self?.updateIndicator()
        }
    }

    private func updateIndicator() {
        indicator.stringValue = feedback ?? (isSaving ? "…" : (isOverDrop ? "↓" : ""))
        indicator.isHidden = indicator.stringValue.isEmpty
        needsDisplay = true
    }
}
