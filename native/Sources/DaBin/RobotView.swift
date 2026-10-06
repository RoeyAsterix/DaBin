import AppKit
import QuartzCore

@MainActor
final class RobotView: NSView {
    private static let interactionTooltip = "Click to open DaBin · drop here · hover then ⌃V or ⌘V to paste"
    var showTooltips = true {
        didSet { toolTip = showTooltips ? Self.interactionTooltip : nil }
    }
    var onPaste: (() -> Void)?
    var onDaily: (() -> Void)?
    var onDrop: ((NSPasteboard) -> Void)?
    var onDragState: ((Bool) -> Void)?
    var onFocus: (() -> Void)?
    var onHoverChange: (() -> Void)?
    private let character: RobotCharacterView
    private let indicator = NSTextField(labelWithString: "")
    private let recordingSign: RobotProjectSignView
    /// The controller can reserve a readable board without scaling the robot.
    var cornerCharacterFrame: CGRect? {
        didSet { needsLayout = true; layoutSubtreeIfNeeded(); updateTrackingAreas() }
    }
    /// Extra stage space leaves the physical camera and its mouse targets fixed.
    var orbitContentOffset = CGPoint.zero {
        didSet { needsLayout = true; layoutSubtreeIfNeeded(); updateTrackingAreas() }
    }
    var recordingProjectName: String? { recordingSign.projectName }
    var recordingStatusLabel: String? { recordingSign.projectName == nil ? nil : recordingSign.statusText }
    var recordingSignIsVisible: Bool { !recordingSign.isHidden }
    var recordingSignFrame: CGRect { recordingSign.boardFrame }
    var recordingSignFontSize: CGFloat { recordingSign.fontSize }
    private var feedbackTask: Task<Void, Never>?
    private var hoverTrackingArea: NSTrackingArea?
    private var lastPasteEvent: NSEvent?
    private(set) var orbitLayout: QuietOrbitLayout?
    private(set) var orbitPerch: QuietOrbitPerch = .bottom
    private var requestedOrbitPerch: QuietOrbitPerch = .bottom
    private(set) var isOrbitRetreating = false
    private var orbitGeneration: UInt64 = 0
    private var orbitTask: Task<Void, Never>?
    private let orbitMask = CAShapeLayer()
    private let reduceMotion: RobotCharacterView.ReduceMotionProvider
    private var companionEntrance: RobotEntrance?
    private(set) var companionProgress: CGFloat = 0
    private var companionPointer = CGPoint.zero
    private(set) var isPresented = false
    private var isCapturePaused = false
    private(set) var isIslandStage = false
    var interactionBounds: NSRect {
        if let orbitLayout {
            return orbitLayout.interactionRegions(for: orbitPerch, local: true).map(offsetOrbitFrame)
                .reduce(.null) { $0.union($1) }
        }
        if let cornerCharacterFrame { return cornerCharacterFrame }
        return CornerGeometry.robotInteractionFrame(in: bounds, target: isIslandStage ? .cameraIsland : .corner(.topRight))
    }
    var bodyBounds: NSRect {
        if let orbitLayout { return offsetOrbitFrame(orbitLayout.visibleRobotFrame(for: orbitPerch, local: true)) }
        if let cornerCharacterFrame { return cornerCharacterFrame }
        return CornerGeometry.robotBodyFrame(in: bounds, target: isIslandStage ? .cameraIsland : .corner(.topRight))
    }
    var transitionBodyBounds: NSRect {
        let rendererFrame = character.layer?.presentation()?.frame ?? character.frame
        return RobotCharacterView.transitionArtworkFrame(in: rendererFrame,
            mirrored: orbitLayout != nil && orbitPerch.isMirrored)
    }
    var hoverBounds: NSRect { isIslandStage || cornerCharacterFrame != nil ? interactionBounds : bounds.insetBy(dx: 4, dy: 4) }
    var mood: RobotMood { character.mood }
    var motionState: RobotMotionState { character.motionState }
    var hasActiveAmbientMotion: Bool { character.hasActiveAmbientMotion }
    var isSaving = false {
        didSet {
            updateIndicator()
            if isSaving { companionEntrance = nil; companionProgress = 0; settleOrbitForCapture() }
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
        self.reduceMotion = reduceMotion
        let sign = RobotProjectSignView()
        recordingSign = sign
        // A held-prop pose has one rigid body. The whole native stage can still
        // reveal/retreat together, while a greeting or digest cannot pull the
        // robot's shoulders away from its hands and board.
        character = RobotCharacterView(frame: frameRect.insetBy(dx: 4, dy: 4), reduceMotion: {
            reduceMotion() || sign.projectName != nil
        })
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true
        addSubview(character)
        addSubview(recordingSign)
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
        setAccessibilityHelp("Click once or press Return to open DaBin, even while the robot moves. Drop onto him, or hover and press Control V or Command V to paste. Escape hides DaBin.")
        toolTip = Self.interactionTooltip
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        if let orbitLayout {
            if orbitTask == nil { character.frame = offsetOrbitFrame(orbitLayout.robotFrame(for: orbitPerch, local: true)) }
            orbitMask.frame = bounds
            let path = CGMutablePath()
            path.addRect(bounds)
            path.addRect(offsetOrbitFrame(orbitLayout.cameraFrameInPanel))
            orbitMask.path = path
            orbitMask.fillRule = .evenOdd
            layer?.mask = orbitMask
        } else {
            layer?.mask = nil
            character.frame = cornerCharacterFrame ?? (isIslandStage ? bounds : bounds.insetBy(dx: 4, dy: 4))
        }
        recordingSign.frame = bounds
        updateRecordingSignAttachment()
        if let orbitLayout {
            indicator.font = .systemFont(ofSize: 11, weight: .semibold)
            let body = bodyBounds
            var badge = NSRect(x: orbitPerch.isMirrored ? body.minX - 10 : body.maxX - 7,
                               y: body.minY - 3, width: 18, height: 18)
            badge.origin.x = min(max(badge.minX, 0), max(0, bounds.width - badge.width))
            badge.origin.y = min(max(badge.minY, 0), max(0, bounds.height - badge.height))
            let camera = offsetOrbitFrame(orbitLayout.cameraFrameInPanel)
            if badge.intersects(camera) {
                badge.origin.y = max(0, camera.minY - badge.height - 2)
            }
            indicator.frame = badge
            indicator.layer?.cornerRadius = 9
        } else {
            indicator.font = .systemFont(ofSize: 14, weight: .semibold)
            indicator.layer?.cornerRadius = 10
            indicator.frame = isIslandStage
            ? NSRect(x: bodyBounds.maxX - 22, y: bodyBounds.maxY - 23, width: 25, height: 22)
            : NSRect(x: (cornerCharacterFrame?.minX ?? 0) + 43,
                     y: (cornerCharacterFrame?.minY ?? 0) + 61, width: 25, height: 22)
        }
    }

    /// Only active monitoring holds a destination sign; Pause removes it.
    func setProjectRecording(projectName: String?, color: NSColor?, isEnabled: Bool,
                             isPaused: Bool = false, statusText: String? = nil) {
        isCapturePaused = isPaused
        character.isHidden = isPaused
        if isPaused { stopFeedback(); hideCharacter() }
        if isEnabled && !isPaused && projectName != nil, companionEntrance != nil {
            companionEntrance = nil; companionProgress = 0
            character.send(.reveal(.top))
        }
        recordingSign.configure(projectName: isEnabled ? projectName : nil, color: color,
                                isPaused: isPaused, statusText: statusText)
        character.refreshMotionPreference()
        character.setNativeArmsHidden(recordingSign.projectName != nil)
        let destination = recordingSign.projectName.map {
            ", \(recordingSign.statusText.lowercased()) \($0)"
        } ?? ""
        setAccessibilityLabel("DaBin purple robot" + destination)
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    private func offsetOrbitFrame(_ frame: CGRect) -> CGRect {
        frame.offsetBy(dx: orbitContentOffset.x, dy: orbitContentOffset.y)
    }

    private func updateRecordingSignAttachment(rendererFrame: CGRect? = nil,
                                               duration: TimeInterval = 0) {
        guard recordingSign.projectName != nil else { recordingSign.isHidden = true; return }
        recordingSign.isHidden = !isPresented
        character.setNativeArmsHidden(true)
        let renderer = rendererFrame ?? character.frame
        let mirrored = orbitLayout != nil && orbitPerch.isMirrored
        let artwork = RobotCharacterView.transitionArtworkFrame(in: renderer, mirrored: mirrored)
        let size = recordingSign.preferredSize(maximumWidth:
            min(RobotProjectSignView.preferredSize.width, max(0, bounds.width - 8)))
        var board = CGRect(x: min(max(4, artwork.midX - size.width / 2), max(4, bounds.width - size.width - 4)),
                           y: max(4, artwork.minY - size.height + 3), width: size.width, height: size.height)
        if let orbitLayout {
            let camera = offsetOrbitFrame(orbitLayout.cameraFrameInPanel)
            if board.intersects(camera) { board.origin.y = max(4, camera.minY - size.height - 2) }
        }
        let scale = min(renderer.width / 64, renderer.height / 78)
        // These are the canonical vector renderer's shoulder anchors, transformed
        // into y-up stage coordinates. Only their positions mirror, never text.
        let shoulderY = renderer.midY + (39 - 40.58) * scale
        let offset = 19.74 * scale
        let left = CGPoint(x: renderer.midX - offset, y: shoulderY)
        let right = CGPoint(x: renderer.midX + offset, y: shoulderY)
        recordingSign.updateAttachment(boardFrame: board, leftShoulder: left, rightShoulder: right,
                                       armWidth: max(2.4, 4.62 * scale), duration: duration)
    }

    // The artwork and badge are decoration. Keep one stable destination around
    // the robot, while the extra island animation space stays click-through.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        guard containsInteraction(localPoint), super.hitTest(point) != nil else { return nil }
        return self
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: hoverBounds,
                                  options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
                                  owner: self, userInfo: nil)
        hoverTrackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        updatePointerMotion(for: event)
        onHoverChange?()
    }
    override func mouseMoved(with event: NSEvent) {
        updatePointerMotion(for: event)
    }
    override func mouseExited(with event: NSEvent) {
        if companionEntrance == nil { character.send(.hover(false)) }
        onHoverChange?()
    }

    override func mouseDown(with event: NSEvent) {
        guard event.clickCount == 1 else { return }
        onFocus?()
        window?.makeKey()
        window?.makeFirstResponder(self)
        onDaily?()
    }

    private func updatePointerMotion(for event: NSEvent) {
        if companionEntrance != nil {
            companionPointer = normalizedPointer(for: event)
            applyCompanionPose()
        } else {
            character.send(.hover(containsInteraction(convert(event.locationInWindow, from: nil)), pointer: normalizedPointer(for: event)))
        }
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
        containsInteraction(convert(sender.draggingLocation, from: nil))
            && onDrop != nil && sender.draggingSourceOperationMask.contains(.copy)
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
        if active { companionEntrance = nil; companionProgress = 0; settleOrbitForCapture() }
        character.send(.acceptedDrag(active))
        onDragState?(active)
    }

    func present(from entrance: RobotEntrance) {
        guard !isCapturePaused else { return }
        companionEntrance = nil
        cancelOrbitTransition()
        orbitLayout = nil
        character.layer?.setAffineTransform(.identity)
        configureIslandStage(false)
        isPresented = true
        character.send(.reveal(entrance))
        updateRecordingSignAttachment()
    }

    func hideCharacter() {
        companionEntrance = nil
        companionProgress = 0
        cancelOrbitTransition()
        isPresented = false
        character.send(.hide)
        recordingSign.isHidden = true
    }

    @discardableResult
    func peekFromIsland() -> TimeInterval {
        guard !isCapturePaused else { return 0 }
        configureIslandStage(true)
        isPresented = true
        let duration = character.playIslandPeek()
        updateRecordingSignAttachment()
        return duration
    }

    func climbFromIsland() {
        guard !isCapturePaused else { return }
        if let orbitLayout {
            revealOrbit(in: orbitLayout, at: orbitPerch)
            return
        }
        configureIslandStage(true)
        isPresented = true
        _ = character.playIslandClimb()
        updateRecordingSignAttachment()
    }

    private func configureIslandStage(_ enabled: Bool) {
        isIslandStage = enabled
        character.configureIslandStage(enabled)
        needsLayout = true
        layoutSubtreeIfNeeded()
        updateTrackingAreas()
    }

    func refreshMotionPreference() {
        if companionEntrance != nil { applyCompanionPose() }
        else { character.refreshMotionPreference() }
    }

    /// The encounter moves artwork layers inside a fixed native destination.
    /// The same target remains clickable from the first peek to the last retreat.
    func presentCompanion(from entrance: RobotEntrance, orbit: QuietOrbitLayout? = nil,
                          perch: QuietOrbitPerch = .bottom) {
        guard !isCapturePaused else { return }
        if let orbit {
            configureOrbit(orbit, perch: perch)
            character.frame = offsetOrbitFrame(orbit.robotFrame(for: perch, local: true))
        } else { present(from: entrance) }
        let sidePerches: Set<QuietOrbitPerch> = [.upperLeft, .left, .right, .upperRight]
        companionEntrance = orbit != nil && sidePerches.contains(perch) ? .left : entrance
        companionProgress = 0
        companionPointer = .zero
        isPresented = true
        applyCompanionPose()
    }

    func updateCompanion(_ snapshot: RobotCompanionEncounter.Snapshot) {
        guard companionEntrance != nil else { return }
        companionProgress = snapshot.progress
        companionPointer = snapshot.pointer
        applyCompanionPose()
    }

    private func applyCompanionPose() {
        guard let entrance = companionEntrance else { return }
        var pointer = companionPointer
        var grip: CGPoint?
        if let orbitLayout {
            let camera = offsetOrbitFrame(orbitLayout.cameraFrameInPanel)
            let renderer = character.frame
            let scale = min(renderer.width / 64, renderer.height / 78)
            if scale > 0 {
                let gripOffset: CGFloat = entrance == .top ? (orbitPerch.isMirrored ? 20 : -20) * scale : 0
                let contact = CGPoint(x: min(camera.maxX, max(camera.minX, renderer.midX + gripOffset)),
                                      y: min(camera.maxY, max(camera.minY, renderer.midY)))
                let designX = 32 + (contact.x - renderer.midX) / scale
                grip = CGPoint(x: orbitPerch.isMirrored ? 64 - designX : designX,
                               y: 39 - (contact.y - renderer.midY) / scale)
            }
            if orbitPerch.isMirrored { pointer.x = -pointer.x }
        }
        character.applyCompanionPose(revealProgress: companionProgress, pointer: pointer,
            entrance: entrance, expressionOnly: reduceMotion(), duration: reduceMotion() ? 0 : 0.12,
            gripPoint: grip)
    }

    func stopFeedback() {
        companionEntrance = nil
        cancelOrbitTransition()
        feedbackTask?.cancel(); feedbackTask = nil
        feedback = nil; isSaving = false; isOverDrop = false
        isPresented = false
        character.stopMotion()
        recordingSign.isHidden = true
        updateIndicator()
    }

    func digest(success: Bool, partial: Bool = false) {
        guard !isCapturePaused else { return }
        companionEntrance = nil; companionProgress = 0
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

    /// Only the small usable target accepts input; measured hardware is excluded.
    func containsInteraction(_ localPoint: NSPoint) -> Bool {
        guard !isCapturePaused else { return false }
        if let orbitLayout {
            let point = CGPoint(x: localPoint.x - orbitContentOffset.x, y: localPoint.y - orbitContentOffset.y)
            return orbitLayout.containsInteraction(point, perch: orbitPerch, local: true)
        }
        return interactionBounds.contains(localPoint)
    }

    func configureOrbit(_ layout: QuietOrbitLayout, perch: QuietOrbitPerch) {
        companionEntrance = nil
        cancelOrbitTransition()
        orbitLayout = layout
        orbitPerch = perch
        requestedOrbitPerch = perch
        isIslandStage = true
        character.configureIslandStage(false)
        character.configureQuietOrbit(true)
        character.layer?.setAffineTransform(CGAffineTransform(scaleX: perch.isMirrored ? -1 : 1, y: 1))
        needsLayout = true
        layoutSubtreeIfNeeded()
        updateTrackingAreas()
    }

    func revealOrbit(in layout: QuietOrbitLayout, at perch: QuietOrbitPerch) {
        guard !isCapturePaused else { return }
        configureOrbit(layout, perch: perch)
        isPresented = true
        character.send(.reveal(.top))
        character.frame = offsetOrbitFrame(layout.robotFrame(for: perch, hidden: !reduceMotion(), local: true))
        character.alphaValue = reduceMotion() ? 0 : 1
        updateRecordingSignAttachment()
        recordingSign.alphaValue = character.alphaValue
        animateOrbit(to: offsetOrbitFrame(layout.robotFrame(for: perch, local: true)), alpha: 1,
                     duration: reduceMotion() ? 0.15 : 0.48)
    }

    /// Duck behind the housing before moving to a deliberate new perch.
    func relocateOrbit(to perch: QuietOrbitPerch) {
        guard let layout = orbitLayout, perch != requestedOrbitPerch, !isSaving, !isOverDrop else { return }
        cancelOrbitTransition()
        requestedOrbitPerch = perch
        let generation = orbitGeneration
        let oldPerch = orbitPerch
        let reduced = reduceMotion()
        animateOrbit(to: reduced ? character.frame : offsetOrbitFrame(layout.robotFrame(for: oldPerch, hidden: true, local: true)),
                     alpha: 0, duration: reduced ? 0.15 : 0.32)
        orbitTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(reduced ? 0.15 : 0.32))
            guard let self, !Task.isCancelled, self.orbitGeneration == generation else { return }
            self.orbitTask = nil
            self.orbitPerch = perch
            self.character.layer?.setAffineTransform(CGAffineTransform(scaleX: perch.isMirrored ? -1 : 1, y: 1))
            self.character.frame = self.offsetOrbitFrame(layout.robotFrame(for: perch, hidden: !reduced, local: true))
            self.updateRecordingSignAttachment()
            self.animateOrbit(to: self.offsetOrbitFrame(layout.robotFrame(for: perch, local: true)), alpha: 1,
                              duration: reduced ? 0.15 : 0.48)
            // Receipt feedback is laid out by the destination view, rather
            // than by its animated character. Keep that badge attached to the
            // new perch before the next save exposes it.
            self.needsLayout = true
            self.layoutSubtreeIfNeeded()
            self.updateTrackingAreas()
        }
    }

    func retreatOrbit(completion: @escaping () -> Void) {
        guard let layout = orbitLayout, !isOrbitRetreating else { return }
        cancelOrbitTransition()
        isOrbitRetreating = true
        let generation = orbitGeneration
        let duration = reduceMotion() ? 0.15 : 0.44
        animateOrbit(to: reduceMotion() ? character.frame : offsetOrbitFrame(layout.robotFrame(for: orbitPerch, hidden: true, local: true)),
                     alpha: 0, duration: duration)
        orbitTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self, !Task.isCancelled, self.orbitGeneration == generation else { return }
            self.orbitTask = nil
            self.isOrbitRetreating = false
            self.isPresented = false
            self.character.send(.hide)
            self.recordingSign.isHidden = true
            completion()
        }
    }

    private func animateOrbit(to frame: NSRect, alpha: CGFloat, duration: TimeInterval) {
        updateRecordingSignAttachment(rendererFrame: frame, duration: duration)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            character.animator().frame = frame
            character.animator().alphaValue = alpha
            recordingSign.animator().alphaValue = alpha
        }
    }

    private func cancelOrbitTransition() {
        orbitGeneration &+= 1
        orbitTask?.cancel(); orbitTask = nil
        isOrbitRetreating = false
        character.layer?.removeAllAnimations()
        character.alphaValue = 1
        recordingSign.cancelAttachmentMotion()
        recordingSign.alphaValue = 1
    }

    private func settleOrbitForCapture() {
        guard let layout = orbitLayout else { return }
        cancelOrbitTransition()
        requestedOrbitPerch = orbitPerch
        character.frame = offsetOrbitFrame(layout.robotFrame(for: orbitPerch, local: true))
        updateRecordingSignAttachment()
    }

    private func normalizedPointer(for event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        let area = interactionBounds
        guard area.width > 0, area.height > 0 else { return .zero }
        return CGPoint(x: min(1, max(-1, (point.x - area.midX) / (area.width / 2))),
                       y: min(1, max(-1, (area.midY - point.y) / (area.height / 2))))
    }

    private func updateIndicator() {
        indicator.stringValue = feedback ?? (isSaving ? "…" : (isOverDrop ? "↓" : ""))
        indicator.isHidden = indicator.stringValue.isEmpty
        needsDisplay = true
    }
}
