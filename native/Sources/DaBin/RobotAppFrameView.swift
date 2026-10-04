import AppKit
import QuartzCore

/// A character-shaped frame around DaBin's real Daily view.
///
/// The controller keeps the destination window at its final size during a
/// transition. This view therefore performs the robot-to-application reveal
/// entirely with GPU-backed layers while the hosted view remains mounted at its
/// final, interactive geometry.
@MainActor
public final class RobotAppFrameView: NSView {
    public static let contentInsets = NSEdgeInsets(top: 32, left: 10, bottom: 18, right: 10)
    public static let extraWidth: CGFloat = contentInsets.left + contentInsets.right
    public static let extraHeight: CGFloat = contentInsets.top + contentInsets.bottom
    public static let totalExtraWidth = extraWidth
    public static let totalExtraHeight = extraHeight
    public static let totalExtraSize = CGSize(width: extraWidth, height: extraHeight)

    public static func outerSize(forContentSize size: CGSize) -> CGSize {
        CGSize(width: size.width + extraWidth, height: size.height + extraHeight)
    }

    public static func contentRect(in bounds: CGRect) -> CGRect {
        CGRect(x: bounds.minX + contentInsets.left,
               y: bounds.minY + contentInsets.bottom,
               width: max(0, bounds.width - extraWidth),
               height: max(0, bounds.height - extraHeight))
    }

    public let contentView: NSView
    public private(set) var isTransitioning = false
    public private(set) var isFrameVisible = false
    var onResizeStarted: (() -> Void)?
    var onResize: ((CGRect) -> Void)?
    var onResizeEnded: (() -> Void)?
    var onToggleExpanded: (() -> Void)?
    var onDragStarted: (() -> Void)?
    var onDragEnded: ((CGPoint) -> Void)?
    private var dragSession: WindowDragSession?
    private var resizeGesture: (edge: BoardResizeGeometry.Edge, pointer: CGPoint, frame: CGRect, visible: CGRect)?
    private(set) var taskCelebrationCount = 0
    private(set) var gazeAnimationStartCount = 0
    var hasActiveEyeMotion: Bool {
        [leftEyeLayer, rightEyeLayer]
            .contains { !($0.animationKeys() ?? []).isEmpty }
    }
    var usesSolidTransitionTorso: Bool {
        leftTorsoLayer.mask == nil && rightTorsoLayer.mask == nil
    }

    private enum Phase { case hidden, opening, open, closing }

    static let openDuration: TimeInterval = 1.10
    static let closeDuration: TimeInterval = 0.96
    static let reducedDuration: TimeInterval = 0.14
    static let openingExpansionDelay: TimeInterval = 0.32
    static let transitionStageOutset: CGFloat = 18

    private let contentContainer = NSView(frame: .zero)
    private let contentRevealMask = CAShapeLayer()
    private let projectRecordingSign = RobotProjectSignView()
    var recordingProjectName: String? { projectRecordingSign.projectName }
    var recordingSignIsVisible: Bool { !projectRecordingSign.isHidden }
    var recordingSignFrame: CGRect { projectRecordingSign.boardFrame }
    var recordingSignFontSize: CGFloat { projectRecordingSign.fontSize }

    private let leftTorsoLayer = CAGradientLayer()
    private let rightTorsoLayer = CAGradientLayer()
    private let leftTorsoMask = CAShapeLayer()
    private let rightTorsoMask = CAShapeLayer()
    private let frameOutlineLayer = CAShapeLayer()
    private let continuousRimLayer = CAShapeLayer()
    private let centerSeamLayer = CAShapeLayer()
    private let transitionSeamLayer = CAShapeLayer()

    private let headLayer = CALayer()
    private let compactBodyLayer = CALayer()
    private let compactFeetLayer = CAShapeLayer()
    private let faceScreenLayer = CAShapeLayer()
    private let leftEyeLayer = CAShapeLayer()
    private let rightEyeLayer = CAShapeLayer()
    private let mouthLayer = CAShapeLayer()

    private static let headSize = CGSize(width: 42, height: 28.56)

    private let leftArmLayer = CAShapeLayer()
    private let rightArmLayer = CAShapeLayer()
    private let leftArmHighlight = CAShapeLayer()
    private let rightArmHighlight = CAShapeLayer()
    private let leftArmHardware = CAShapeLayer()
    private let rightArmHardware = CAShapeLayer()
    private let legsLayer = CALayer()
    private let leftLegLayer = CAShapeLayer()
    private let rightLegLayer = CAShapeLayer()
    private let leftLegHighlight = CAShapeLayer()
    private let rightLegHighlight = CAShapeLayer()
    private let leftFootLayer = CAShapeLayer()
    private let rightFootLayer = CAShapeLayer()

    private var phase: Phase = .hidden
    private var transitionGeneration: UInt = 0
    private var transitionTask: Task<Void, Never>?
    private var nextBlinkTime: CFTimeInterval = .greatestFiniteMagnitude
    private var blinkSequence: UInt = 0
    private var reduceMotionActive = false
    private var leftEyeHome = CGPoint.zero
    private var rightEyeHome = CGPoint.zero

    private var decorationLayers: [CALayer] {
        [leftTorsoLayer, rightTorsoLayer, headLayer, leftArmLayer, rightArmLayer, legsLayer, compactBodyLayer]
    }

    public init(contentView: NSView) {
        self.contentView = contentView
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = false
        setAccessibilityElement(false)

        configureContent()
        configureRobotLayers()
        addSubview(projectRecordingSign)
        for (robotLayer, name) in zip(decorationLayers,
            ["leftTorso", "rightTorso", "head", "leftArm", "rightArm", "legs", "compactBody"]) {
            if robotLayer.name == nil { robotLayer.name = "robotFrame.\(name)" }
        }
        contentContainer.layer?.name = "robotFrame.content"
        frameOutlineLayer.name = "robotFrame.outline"
        centerSeamLayer.name = "robotFrame.centerSeam"
        transitionSeamLayer.name = "robotFrame.transitionSeam"
        applyStableState(open: false)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layout() {
        super.layout()
        guard bounds.width > 0, bounds.height > 0 else { return }

        withoutActions {
            layer?.masksToBounds = false
            contentContainer.frame = Self.contentRect(in: bounds)
            contentView.frame = contentContainer.bounds
            contentRevealMask.bounds = contentContainer.bounds
            contentRevealMask.position = CGPoint(x: contentContainer.bounds.midX,
                                                 y: contentContainer.bounds.midY)
            contentRevealMask.path = BoardWindowChrome.path(in: contentContainer.bounds)

            layoutTorso()
            layoutHead()
            layoutArms()
            layoutLegs()
            layoutOutlineAndSeam()
            updateChromeBackingScale()
            layoutProjectRecordingSign()
        }
        window?.invalidateCursorRects(for: self)
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateChromeBackingScale()
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateChromeBackingScale()
    }

    func setProjectRecording(projectName: String?, color: NSColor?, isEnabled: Bool,
                             isPaused: Bool = false, statusText: String? = nil) {
        projectRecordingSign.configure(projectName: isEnabled ? projectName : nil,
                                       color: color, isPaused: isPaused, statusText: statusText)
        projectRecordingSign.setAccessibilityElement(projectRecordingSign.projectName != nil)
        projectRecordingSign.setAccessibilityRole(.staticText)
        projectRecordingSign.setAccessibilityLabel(projectRecordingSign.projectName.map {
            "\(projectRecordingSign.statusText): \($0)"
        })
        layoutProjectRecordingSign()
    }

    private func layoutProjectRecordingSign() {
        projectRecordingSign.frame = bounds
        projectRecordingSign.isHidden = projectRecordingSign.projectName == nil || phase != .open
        guard !projectRecordingSign.isHidden else { return }
        // The plate and both hands fit in the existing reserved top chrome.
        // Keep the application header, resize rim and center face unobstructed.
        let size = projectRecordingSign.preferredSize(maximumWidth: min(116, max(0, bounds.width / 2 - 38)))
        let board = CGRect(x: bounds.maxX - size.width - 16, y: bounds.maxY - 28,
                           width: size.width, height: size.height)
        projectRecordingSign.updateAttachment(boardFrame: board,
            leftShoulder: CGPoint(x: board.minX + 12, y: bounds.maxY - 31),
            rightShoulder: CGPoint(x: board.maxX - 12, y: bounds.maxY - 31), armWidth: 2.5)
    }

    private func updateChromeBackingScale() {
        let measured = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        let scale = measured.isFinite && measured > 0 ? measured : 1
        // SwiftUI/AppKit own their view backing layers. Only update the custom
        // vector layers and masks, including on mixed-density display moves.
        func update(_ target: CALayer) {
            target.contentsScale = scale
            target.rasterizationScale = scale
            target.allowsEdgeAntialiasing = true
            target.sublayers?.forEach(update)
            if let mask = target.mask { update(mask) }
        }
        withoutActions {
            (decorationLayers + [frameOutlineLayer, centerSeamLayer,
                transitionSeamLayer, contentRevealMask]).forEach(update)
            contentContainer.layer?.allowsEdgeAntialiasing = true
        }
    }

    /// Visible corners resize; the reserved top chrome moves the window.
    /// All controls inside the application keep their own hit testing.
    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, !contentView.isHidden, !isTransitioning else { return nil }
        // AppKit passes `point` in the receiver's superview coordinates. The
        // hosted view's hitTest in turn expects content-container coordinates.
        let localPoint = superview.map { convert(point, from: $0) } ?? point
        let containerPoint = contentContainer.convert(localPoint, from: self)
        if !isTransitioning, onResize != nil,
           !BoardResizeGeometry.interactionEdge(at: localPoint, in: bounds).isEmpty { return self }
        if !isTransitioning, onDragStarted != nil,
           BoardResizeGeometry.dragRegion(in: bounds).contains(localPoint) { return self }
        guard contentView.frame.contains(containerPoint) else { return nil }
        return contentView.hitTest(containerPoint)
    }

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    public override func resetCursorRects() {
        guard !isTransitioning else { return }
        if onDragStarted != nil {
            addCursorRect(BoardResizeGeometry.dragRegion(in: bounds), cursor: .openHand)
        }
        guard onResize != nil else { return }
        for region in BoardResizeGeometry.edgeRegions(in: bounds) {
            addCursorRect(region.rect, cursor: region.edge.contains(.left) || region.edge.contains(.right)
                ? .resizeLeftRight : .resizeUpDown)
        }
        for region in BoardResizeGeometry.cornerRegions(in: bounds) {
            addCursorRect(region.rect, cursor: Self.cornerCursor(region.edge))
        }
    }

    private static func cornerCursor(_ edge: BoardResizeGeometry.Edge) -> NSCursor {
        if #available(macOS 15.0, *) {
            let position: NSCursor.FrameResizePosition
            if edge.contains(.top) { position = edge.contains(.left) ? .topLeft : .topRight }
            else { position = edge.contains(.left) ? .bottomLeft : .bottomRight }
            return NSCursor.frameResize(position: position, directions: .all)
        }
        return edge.contains(.top) == edge.contains(.left) ? descendingCursor : ascendingCursor
    }

    private static let ascendingCursor = diagonalCursor(ascending: true)
    private static let descendingCursor = diagonalCursor(ascending: false)

    private static func diagonalCursor(ascending: Bool) -> NSCursor {
        let image = NSImage(size: NSSize(width: 24, height: 24), flipped: false) { _ in
            let path = NSBezierPath()
            func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: ascending ? y : 24 - y) }
            path.move(to: point(5, 5)); path.line(to: point(19, 19))
            path.move(to: point(5, 11)); path.line(to: point(5, 5)); path.line(to: point(11, 5))
            path.move(to: point(13, 19)); path.line(to: point(19, 19)); path.line(to: point(19, 13))
            path.lineCapStyle = .round; path.lineJoinStyle = .round
            NSColor.white.setStroke(); path.lineWidth = 3.5; path.stroke()
            NSColor.black.setStroke(); path.lineWidth = 1.5; path.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 12, y: 12))
    }

    public override func mouseDown(with event: NSEvent) {
        guard event.type == .leftMouseDown, let window, !isTransitioning else { return }
        let localPoint = convert(event.locationInWindow, from: nil)
        let edge = BoardResizeGeometry.interactionEdge(at: localPoint, in: bounds)
        if edge.isEmpty {
            guard onDragStarted != nil, BoardResizeGeometry.dragRegion(in: bounds).contains(localPoint) else { return }
            if event.clickCount == 2 { onToggleExpanded?(); return }
            let pointer = window.convertPoint(toScreen: event.locationInWindow)
            onDragStarted?()
            dragSession = WindowDragSession(pointer: pointer, origin: window.frame.origin)
            return
        }
        guard onResize != nil, let screen = window.screen else { return }
        if event.clickCount == 2 { onToggleExpanded?(); return }
        onResizeStarted?()
        resizeGesture = (edge, window.convertPoint(toScreen: event.locationInWindow), window.frame, screen.visibleFrame)
    }

    public override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let pointer = window.convertPoint(toScreen: event.locationInWindow)
        if let dragSession {
            window.setFrameOrigin(dragSession.origin(at: pointer))
            return
        }
        guard let gesture = resizeGesture else { return }
        onResize?(BoardResizeGeometry.resized(gesture.frame, edge: gesture.edge,
            delta: CGPoint(x: pointer.x - gesture.pointer.x, y: pointer.y - gesture.pointer.y),
            visible: gesture.visible))
    }

    public override func mouseUp(with event: NSEvent) {
        if resizeGesture != nil {
            resizeGesture = nil
            onResizeEnded?()
        } else if dragSession != nil {
            dragSession = nil
            if let window { onDragEnded?(window.convertPoint(toScreen: event.locationInWindow)) }
        }
    }

    func cancelWindowInteraction() {
        resizeGesture = nil
        dragSession = nil
    }

    /// Feedback is local to the already-visible robot; it creates no window,
    /// focus change or sound. The coordinator calls this only after persistence.
    func celebrateTaskCompletion(reduceMotion: Bool) {
        guard phase == .open, isFrameVisible, !isHidden else { return }
        taskCelebrationCount += 1
        // Core Animation path morphing needs the same element topology as
        // the canonical idle mouth (one move and three straight segments).
        let smile = QuietOrbitVisualStyle.polygon([(40, 48), (45, 55), (55, 55), (60, 48)],
            in: headLayer.bounds, topDown: false, closed: false)
        let grin = CAKeyframeAnimation(keyPath: "path")
        grin.values = [mouthLayer.path as Any, smile, smile, mouthLayer.path as Any]
        grin.keyTimes = [0, 0.15, 0.82, 1]
        grin.duration = reduceMotion ? 0.7 : 1.1
        mouthLayer.add(grin, forKey: "robotFrame.taskSmile")
        guard !reduceMotion else { return }
        let bounce = CAKeyframeAnimation(keyPath: "transform.translation.y")
        bounce.values = [0, 2, -1, 1, 0]
        bounce.keyTimes = [0, 0.25, 0.5, 0.75, 1]
        bounce.duration = 0.65
        bounce.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        headLayer.add(bounce, forKey: "robotFrame.taskHappy")
        for eye in [leftEyeLayer, rightEyeLayer] {
            let blink = CAKeyframeAnimation(keyPath: "transform.scale.y")
            blink.values = [1, 0.2, 0.2, 1]
            blink.keyTimes = [0, 0.15, 0.7, 1]
            blink.duration = 0.8
            eye.add(blink, forKey: "robotFrame.taskHappy")
        }
    }

    public func setVisible(_ visible: Bool) {
        // Occlusion and frame notifications may echo while the controller is
        // already animating an open/close. A positive visibility echo must not
        // cancel that generation or invoke its completion early.
        if visible && isTransitioning { return }
        if visible == isFrameVisible, !isTransitioning { return }
        if visible { reduceMotionActive = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
        invalidateTransition()
        removeTransitionAnimations()
        applyStableState(open: visible)
    }

    /// Resolve an interrupted transition to a known endpoint. A cancelled
    /// generation never invokes its stale completion closure.
    public func cancelTransition(open: Bool) {
        invalidateTransition()
        removeTransitionAnimations()
        applyStableState(open: open)
    }

    public func animateOpen(from sourceRectInScreen: CGRect,
                            island: Bool,
                            sourceMirrored: Bool = false,
                            reduceMotion: Bool,
                            completion: (() -> Void)? = nil) {
        animateCharacterTransition(source: sourceRectInScreen, island: island, sourceMirrored: sourceMirrored,
                                   opening: true, reduceMotion: reduceMotion, completion: completion)
    }

    public func animateClose(to sourceRectInScreen: CGRect,
                             island: Bool,
                             sourceMirrored: Bool = false,
                             reduceMotion: Bool,
                             completion: (() -> Void)? = nil) {
        animateCharacterTransition(source: sourceRectInScreen, island: island, sourceMirrored: sourceMirrored,
                                   opening: false, reduceMotion: reduceMotion, completion: completion)
    }

    /// Called by the owning controller's existing pointer poll. This schedules
    /// no timer: it only eases the mint eyes to the latest clamped target and uses
    /// the same tick to trigger an occasional blink.
    public func updatePointer(screenPoint: CGPoint?, displayFrame: CGRect) {
        guard isFrameVisible, phase == .open else { return }
        guard !reduceMotionActive else { resetEyes(); return }
        let eyeCenter = eyeCenterInScreen()
        let offset = RobotAppFrameGaze.offset(pointer: screenPoint,
                                              eyeCenter: eyeCenter,
                                              displayFrame: displayFrame)
        easeEye(leftEyeLayer, home: leftEyeHome, offset: offset)
        easeEye(rightEyeLayer, home: rightEyeHome, offset: offset)
        blinkIfNeeded(now: CACurrentMediaTime())
    }

    // MARK: - Configuration

    private func configureContent() {
        contentContainer.wantsLayer = true
        // BoardView owns the user's appearance and opacity. An opaque wrapper
        // would defeat those settings and a full purple backing would tint its
        // translucent material, so this host stays completely clear.
        contentContainer.layer?.backgroundColor = NSColor.clear.cgColor
        // A single shape mask, rather than a second mismatched circular clip.
        contentContainer.layer?.cornerRadius = 0
        contentContainer.layer?.masksToBounds = true
        contentContainer.layer?.zPosition = 10
        contentRevealMask.name = "robotFrame.contentRevealMask"
        contentRevealMask.fillColor = NSColor.black.cgColor
        contentContainer.layer?.mask = contentRevealMask
        addSubview(contentContainer)

        contentView.removeFromSuperview()
        contentView.wantsLayer = true
        contentView.autoresizingMask = [.width, .height]
        contentContainer.addSubview(contentView)
    }

    private func configureRobotLayers() {
        guard let root = layer else { return }
        root.masksToBounds = false

        let shellColors = QuietOrbitVisualStyle.metal.map { QuietOrbitVisualStyle.color($0) }
        for torso in [leftTorsoLayer, rightTorsoLayer] {
            torso.colors = shellColors
            torso.locations = [0, 0.25, 0.5, 0.75, 1]
            torso.startPoint = CGPoint(x: 0.08, y: 0.9)
            torso.endPoint = CGPoint(x: 0.92, y: 0.05)
            torso.masksToBounds = true
            torso.zPosition = 1
            root.addSublayer(torso)
        }
        leftTorsoLayer.mask = leftTorsoMask
        rightTorsoLayer.mask = rightTorsoMask

        frameOutlineLayer.fillColor = nil
        frameOutlineLayer.strokeColor = Self.color(0xBCA3D1, alpha: 0.45)
        frameOutlineLayer.lineWidth = 0.7
        frameOutlineLayer.zPosition = 21
        root.addSublayer(frameOutlineLayer)

        // The continuous rim shares the board's transform and fade. The
        // underlying rails keep their transparent center throughout motion.
        continuousRimLayer.name = "robotFrame.continuousRim"
        // A direct hollow vector fill avoids compositing a full-board gradient
        // and mask for a rim only a few points wide. The torso rails retain
        // their metallic shading; the continuous rim seals their corner gaps.
        continuousRimLayer.fillRule = .evenOdd
        continuousRimLayer.fillColor = Self.color(0xC6BBD0)
        continuousRimLayer.zPosition = -1
        frameOutlineLayer.addSublayer(continuousRimLayer)

        centerSeamLayer.fillColor = nil
        centerSeamLayer.strokeColor = Self.color(0xDCC9E9, alpha: 0.48)
        centerSeamLayer.lineWidth = 1
        centerSeamLayer.zPosition = 22
        root.addSublayer(centerSeamLayer)

        transitionSeamLayer.fillColor = nil
        transitionSeamLayer.strokeColor = Self.color(0xE5D5EF, alpha: 0.82)
        transitionSeamLayer.lineWidth = 1.35
        transitionSeamLayer.lineCap = .round
        transitionSeamLayer.zPosition = 25
        root.addSublayer(transitionSeamLayer)

        configureHead()
        headLayer.zPosition = 24
        root.addSublayer(headLayer)

        for (arm, highlight, hardware) in [(leftArmLayer, leftArmHighlight, leftArmHardware),
                                           (rightArmLayer, rightArmHighlight, rightArmHardware)] {
            arm.fillColor = nil
            arm.strokeColor = QuietOrbitVisualStyle.color(0x554760)
            arm.lineWidth = 3.5
            arm.lineCap = .round
            arm.lineJoin = .round
            highlight.fillColor = nil
            highlight.strokeColor = QuietOrbitVisualStyle.color(QuietOrbitVisualStyle.silver[1])
            highlight.lineWidth = 2
            highlight.lineCap = .round
            highlight.lineJoin = .round
            arm.addSublayer(highlight)
            hardware.fillColor = QuietOrbitVisualStyle.color(QuietOrbitVisualStyle.silver[1])
            hardware.strokeColor = QuietOrbitVisualStyle.color(0x766285)
            hardware.lineWidth = 0.6
            arm.addSublayer(hardware)
            arm.zPosition = 23
            root.addSublayer(arm)
        }

        configureLegs()
        legsLayer.zPosition = 23
        root.addSublayer(legsLayer)
    }

    private func configureHead() {
        headLayer.masksToBounds = false
        headLayer.bounds = CGRect(origin: .zero, size: Self.headSize)
        QuietOrbitHeadArtwork.install(in: headLayer, canvas: Self.headSize,
            headRect: headLayer.bounds, topDown: false, visor: faceScreenLayer,
            leftEye: leftEyeLayer, rightEye: rightEyeLayer, mouth: mouthLayer)
        leftEyeHome = leftEyeLayer.position
        rightEyeHome = rightEyeLayer.position
        let bodySize = CGSize(width: Self.headSize.width, height: Self.headSize.width * 1.07)
        compactBodyLayer.bounds = CGRect(origin: .zero, size: bodySize)
        compactBodyLayer.anchorPoint = CGPoint(x: 0.5, y: 1 - Self.headSize.height / (2 * bodySize.height))
        compactBodyLayer.masksToBounds = false
        QuietOrbitBodyArtwork.install(in: compactBodyLayer, canvas: bodySize,
            headRect: CGRect(x: 0, y: bodySize.height - Self.headSize.height,
                             width: Self.headSize.width, height: Self.headSize.height),
            topDown: false, feet: compactFeetLayer)
        compactBodyLayer.zPosition = 12
        layer?.addSublayer(compactBodyLayer)
    }

    private func configureLegs() {
        legsLayer.masksToBounds = false
        for (leg, highlight) in [(leftLegLayer, leftLegHighlight), (rightLegLayer, rightLegHighlight)] {
            leg.fillColor = nil
            leg.strokeColor = QuietOrbitVisualStyle.color(0x554760)
            leg.lineWidth = 4
            leg.lineCap = .round
            highlight.fillColor = nil
            highlight.strokeColor = QuietOrbitVisualStyle.color(QuietOrbitVisualStyle.silver[1])
            highlight.lineWidth = 2.3
            highlight.lineCap = .round
            leg.addSublayer(highlight)
            legsLayer.addSublayer(leg)
        }
        for foot in [leftFootLayer, rightFootLayer] {
            foot.fillColor = QuietOrbitVisualStyle.color(QuietOrbitVisualStyle.silver[1])
            foot.strokeColor = QuietOrbitVisualStyle.color(0x766285)
            foot.lineWidth = 0.8
            legsLayer.addSublayer(foot)
        }
    }

    // MARK: - Layout

    private func layoutTorso() {
        let content = Self.contentRect(in: bounds)
        let torso = content.insetBy(dx: -BoardWindowChrome.rimWidth, dy: -BoardWindowChrome.rimWidth)
        let split = torso.midX
        leftTorsoLayer.frame = CGRect(x: torso.minX, y: torso.minY,
                                     width: split - torso.minX + 0.5, height: torso.height)
        rightTorsoLayer.frame = CGRect(x: split - 0.5, y: torso.minY,
                                      width: torso.maxX - split + 0.5, height: torso.height)
        leftTorsoLayer.cornerRadius = BoardWindowChrome.cornerRadius + BoardWindowChrome.rimWidth
        rightTorsoLayer.cornerRadius = BoardWindowChrome.cornerRadius + BoardWindowChrome.rimWidth
        leftTorsoLayer.cornerCurve = .continuous
        rightTorsoLayer.cornerCurve = .continuous
        leftTorsoLayer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        rightTorsoLayer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        layoutTorsoMask(leftTorsoMask, for: leftTorsoLayer, content: content)
        layoutTorsoMask(rightTorsoMask, for: rightTorsoLayer, content: content)
    }

    private func layoutTorsoMask(_ mask: CAShapeLayer,
                                 for torso: CALayer,
                                 content: CGRect) {
        mask.frame = torso.bounds
        // A reversing transition still has a transformed model layer. Its
        // frame is that transformed bounding box, not the mask's local origin.
        let origin = CGPoint(x: torso.position.x - torso.bounds.width * torso.anchorPoint.x,
                             y: torso.position.y - torso.bounds.height * torso.anchorPoint.y)
        let contentInTorso = CGRect(x: content.minX - origin.x,
                                    y: content.minY - origin.y,
                                    width: content.width, height: content.height)
        let rails = [
            CGRect(x: torso.bounds.minX, y: torso.bounds.minY,
                   width: max(0, contentInTorso.minX - torso.bounds.minX), height: torso.bounds.height),
            CGRect(x: min(torso.bounds.maxX, contentInTorso.maxX), y: torso.bounds.minY,
                   width: max(0, torso.bounds.maxX - contentInTorso.maxX), height: torso.bounds.height),
            CGRect(x: torso.bounds.minX, y: torso.bounds.minY, width: torso.bounds.width,
                   height: max(0, contentInTorso.minY - torso.bounds.minY)),
            CGRect(x: torso.bounds.minX, y: min(torso.bounds.maxY, contentInTorso.maxY),
                   width: torso.bounds.width, height: max(0, torso.bounds.maxY - contentInTorso.maxY))
        ]
        mask.path = rectangleMaskPath(rails)
        mask.fillColor = NSColor.black.cgColor
    }

    private func layoutHead() {
        let width = Self.headSize.width
        let height = Self.headSize.height
        let rect = CGRect(x: bounds.midX - width / 2,
                          y: bounds.maxY - height - 3,
                          width: width, height: height)
        headLayer.frame = rect
        compactBodyLayer.position = headLayer.position
    }

    private func layoutArms() {
        let pose = stablePose()
        for (arm, highlight, hardware, geometry) in [
            (leftArmLayer, leftArmHighlight, leftArmHardware, pose.left),
            (rightArmLayer, rightArmHighlight, rightArmHardware, pose.right)
        ] {
            arm.frame = bounds
            arm.path = armPath(geometry)
            highlight.path = armPath(geometry)
            hardware.path = armHardwarePath(geometry)
            arm.lineWidth = geometry.unit * 11
            highlight.lineWidth = geometry.unit * 7
            hardware.lineWidth = geometry.unit
        }
    }

    private func layoutLegs() {
        legsLayer.frame = bounds
        let spread = min(35, max(22, bounds.width * 0.075))
        let leftX = bounds.midX - spread
        let rightX = bounds.midX + spread

        let left = CGMutablePath()
        left.move(to: CGPoint(x: leftX, y: Self.contentInsets.bottom - 2))
        left.addCurve(to: CGPoint(x: leftX - 2, y: 5),
                      control1: CGPoint(x: leftX + 2, y: 13),
                      control2: CGPoint(x: leftX - 3, y: 9))
        leftLegLayer.path = left
        leftLegHighlight.path = left

        let right = CGMutablePath()
        right.move(to: CGPoint(x: rightX, y: Self.contentInsets.bottom - 2))
        right.addCurve(to: CGPoint(x: rightX + 2, y: 5),
                       control1: CGPoint(x: rightX - 2, y: 13),
                       control2: CGPoint(x: rightX + 3, y: 9))
        rightLegLayer.path = right
        rightLegHighlight.path = right

        leftFootLayer.path = CGPath(roundedRect: CGRect(x: leftX - 8, y: 2, width: 14, height: 6),
                                               cornerWidth: 2.5, cornerHeight: 2.5, transform: nil)
        rightFootLayer.path = CGPath(roundedRect: CGRect(x: rightX - 6, y: 2, width: 14, height: 6),
                                                cornerWidth: 2.5, cornerHeight: 2.5, transform: nil)
    }

    private func layoutOutlineAndSeam() {
        let content = Self.contentRect(in: bounds)
        frameOutlineLayer.frame = bounds
        frameOutlineLayer.path = BoardWindowChrome.path(in: content, outset: 0.75)
        continuousRimLayer.frame = frameOutlineLayer.bounds
        continuousRimLayer.path = BoardWindowChrome.rimPath(in: content)
        centerSeamLayer.frame = bounds
        let seam = CGMutablePath()
        seam.move(to: CGPoint(x: bounds.midX, y: max(2, content.minY - 7)))
        seam.addLine(to: CGPoint(x: bounds.midX, y: content.minY - 1))
        seam.move(to: CGPoint(x: bounds.midX, y: content.maxY + 1))
        seam.addLine(to: CGPoint(x: bounds.midX, y: content.maxY + 7))
        centerSeamLayer.path = seam

        transitionSeamLayer.frame = bounds
        let split = CGMutablePath()
        split.move(to: CGPoint(x: bounds.midX, y: max(2, content.minY - 7)))
        split.addLine(to: CGPoint(x: bounds.midX, y: content.maxY + 7))
        transitionSeamLayer.path = split
    }

    // MARK: - Transition choreography

    private struct ArmPose {
        let shoulder: CGPoint
        let elbow: CGPoint
        let hand: CGPoint
        let unit: CGFloat
    }

    private struct CharacterPose {
        let surface: CGRect
        let head: CGRect
        let left: ArmPose
        let right: ArmPose
    }

    private var transitionLayers: [CALayer] {
        decorationLayers + [frameOutlineLayer, centerSeamLayer, transitionSeamLayer]
            + [contentContainer.layer].compactMap { $0 }
    }

    private var armShapeLayers: [CAShapeLayer] {
        [leftArmLayer, rightArmLayer, leftArmHighlight, rightArmHighlight,
         leftArmHardware, rightArmHardware]
    }

    private func animateCharacterTransition(source sourceInScreen: CGRect, island: Bool, sourceMirrored: Bool,
                                            opening: Bool, reduceMotion: Bool,
                                            completion: (() -> Void)?) {
        let continuing = isTransitioning
        let source = localSourceRect(for: sourceInScreen)
        let transforms = Dictionary(uniqueKeysWithValues: transitionLayers.map {
            (ObjectIdentifier($0), $0.presentation()?.transform ?? $0.transform)
        })
        let opacities = Dictionary(uniqueKeysWithValues: transitionLayers.map {
            (ObjectIdentifier($0), $0.presentation()?.opacity ?? $0.opacity)
        })
        let paths = Dictionary(uniqueKeysWithValues: armShapeLayers.compactMap { shape -> (ObjectIdentifier, CGPath)? in
            guard let path = shape.presentation()?.path ?? shape.path else { return nil }
            return (ObjectIdentifier(shape), path)
        })
        let widths = Dictionary(uniqueKeysWithValues: armShapeLayers.map {
            (ObjectIdentifier($0), $0.presentation()?.lineWidth ?? $0.lineWidth)
        })
        let rootOpacity = layer?.presentation()?.opacity ?? layer?.opacity ?? (opening ? 0 : 1)
        let eyeScales = Dictionary(uniqueKeysWithValues: [leftEyeLayer, rightEyeLayer].map {
            let transform = $0.presentation()?.transform ?? $0.transform
            return (ObjectIdentifier($0), max(0.08, hypot(transform.m21, transform.m22)))
        })
        let eyePositions = Dictionary(uniqueKeysWithValues: [leftEyeLayer, rightEyeLayer].map {
            (ObjectIdentifier($0), $0.presentation()?.position ?? $0.position)
        })
        let generation = beginTransition(opening ? .opening : .closing)
        reduceMotionActive = reduceMotion
        isHidden = false
        contentContainer.isHidden = false
        contentView.isHidden = false
        layoutSubtreeIfNeeded()
        removeTransitionAnimations()

        if reduceMotion {
            applyOpenModelState()
            withoutActions { layer?.opacity = opening ? 1 : 0 }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = continuing ? rootOpacity : (opening ? 0 : 1)
            fade.toValue = opening ? 1 : 0
            fade.duration = Self.reducedDuration
            layer?.add(fade, forKey: "robotFrame.reduced")
            finish(after: Self.reducedDuration, generation: generation, open: opening, completion: completion)
            return
        }

        let hero = heroRect(source: source)
        let stable = stablePose()
        let arrival = compactPose(in: hero, handsReady: false)
        let ready = compactPose(in: hero.offsetBy(dx: 0, dy: -3), handsReady: true)
        let coil = compactPose(in: scaledRect(hero, by: 0.95,
            center: CGPoint(x: hero.midX, y: hero.midY - 6)), handsReady: true)
        let sourcePose = compactPose(in: source, handsReady: false, mirrored: sourceMirrored)
        let tuck = compactPose(in: scaledRect(source, by: 0.22,
            center: CGPoint(x: source.midX, y: source.midY + (island ? source.height * 0.34 : 0))),
            handsReady: false, mirrored: sourceMirrored)

        let poses: [CharacterPose]
        let times: [Double]
        let duration: TimeInterval
        if opening && continuing {
            // Reversal resumes from the exact presented geometry, without
            // replaying the entrance or visiting a different compact pose.
            poses = [stable, stable]
            times = [0, 1]
            duration = 0.42
        } else if opening {
            poses = [sourcePose,
                compactPose(in: scaledRect(source, by: 0.94,
                    center: CGPoint(x: source.midX, y: source.midY - 2)), handsReady: false, mirrored: sourceMirrored),
                arrival, ready, unfoldingPose(0.91, hero: ready), unfoldingPose(0.995, hero: ready), stable]
            times = [0, 0.12, 0.29, 0.44, 0.82, 0.94, 1]
            duration = Self.openDuration
        } else if continuing {
            poses = [stable, ready, coil, sourcePose, tuck]
            times = [0, 0.44, 0.64, 0.88, 1]
            duration = 0.72
        } else {
            poses = [stable, unfoldingPose(0.985, hero: ready), unfoldingPose(0.38, hero: ready),
                     ready, coil, sourcePose, tuck]
            times = [0, 0.12, 0.38, 0.52, 0.72, 0.90, 1]
            duration = Self.closeDuration
        }
        let started = CACurrentMediaTime()
        withoutActions {
            layer?.opacity = 1
            restoreTorsoRails()
            contentRevealMask.transform = CATransform3DIdentity
        }
        for target in transitionLayers {
            var values = poses.map { pose -> CATransform3D in
                if target === headLayer || target === compactBodyLayer {
                    return headTransform(for: target, rect: pose.head)
                }
                if target === leftArmLayer || target === rightArmLayer { return CATransform3DIdentity }
                return surfaceTransform(for: target, rect: pose.surface)
            }
            if continuing || !opening, let presented = transforms[ObjectIdentifier(target)] {
                values[0] = presented
            }
            withoutActions { target.transform = values.last! }
            let key: String
            if target === contentContainer.layer { key = opening ? "robotFrame.open" : "robotFrame.content.transform.close" }
            else if target === frameOutlineLayer { key = opening ? "robotFrame.open" : "robotFrame.outline.transform.close" }
            else if target === centerSeamLayer { key = opening ? "robotFrame.open" : "robotFrame.centerSeam.transform.close" }
            else { key = opening ? "robotFrame.open" : "robotFrame.close" }
            addTrack(to: target, keyPath: "transform", values: values.map { NSValue(caTransform3D: $0) },
                     times: times, duration: duration, started: started, key: key)
        }

        for (arm, highlight, hardware, left) in [
            (leftArmLayer, leftArmHighlight, leftArmHardware, true),
            (rightArmLayer, rightArmHighlight, rightArmHardware, false)
        ] {
            let armPoses = poses.map { left ? $0.left : $0.right }
            for (shape, hardwarePath) in [(arm, false), (highlight, false), (hardware, true)] {
                var values = armPoses.map { hardwarePath ? armHardwarePath($0) : armPath($0) }
                var lineWidths = armPoses.map { $0.unit * (hardwarePath ? 1 : (shape === arm ? 11 : 7)) }
                if continuing || !opening {
                    if let presented = paths[ObjectIdentifier(shape)] { values[0] = presented }
                    if let width = widths[ObjectIdentifier(shape)] { lineWidths[0] = width }
                }
                withoutActions { shape.path = values.last; shape.lineWidth = lineWidths.last! }
                addTrack(to: shape, keyPath: "path", values: values, times: times, duration: duration,
                         started: started, key: "robotFrame.arm.path")
                addTrack(to: shape, keyPath: "lineWidth", values: lineWidths.map { NSNumber(value: Double($0)) },
                         times: times, duration: duration, started: started, key: "robotFrame.arm.width")
            }
        }

        func opacity(_ target: CALayer?, _ values: [Float], _ stops: [Double], _ key: String) {
            guard let target else { return }
            var values = values
            if continuing || !opening { values[0] = opacities[ObjectIdentifier(target)] ?? values[0] }
            withoutActions { target.opacity = values.last! }
            addTrack(to: target, keyPath: "opacity", values: values.map { NSNumber(value: $0) },
                     times: stops, duration: duration, started: started, key: key)
        }
        let characterLayers = [headLayer, leftArmLayer, rightArmLayer]
        if opening && continuing {
            for target in characterLayers + [leftTorsoLayer, rightTorsoLayer, legsLayer, frameOutlineLayer, centerSeamLayer] {
                opacity(target, [1, 1], [0, 1], "robotFrame.reopenOpacity")
            }
            opacity(compactBodyLayer, [1, 0], [0, 1], "robotFrame.body.opacity")
            opacity(contentContainer.layer, [0, 1], [0, 1], "robotFrame.content.open")
        } else if opening {
            for target in characterLayers { opacity(target, [1, 1], [0, 1], "robotFrame.character.open") }
            opacity(compactBodyLayer, [1, 1, 0, 0], [0, 0.46, 0.69, 1], "robotFrame.body.opacity")
            for target in [leftTorsoLayer, rightTorsoLayer, legsLayer, frameOutlineLayer, centerSeamLayer] {
                opacity(target, [0, 0, 1, 1], [0, 0.46, 0.86, 1], "robotFrame.rails.open")
            }
            opacity(contentContainer.layer, [0, 0, 1, 1], [0, 0.52, 0.88, 1], "robotFrame.content.open")
        } else {
            for target in characterLayers {
                opacity(target, [1, 1, 1, 0], [0, 0.12, 0.90, 1], "robotFrame.closeOpacity")
            }
            if continuing {
                opacity(compactBodyLayer, [0, 1, 1, 0], [0, 0.44, 0.90, 1], "robotFrame.body.opacity")
            } else {
                opacity(compactBodyLayer, [0, 0, 1, 1, 0], [0, 0.32, 0.52, 0.90, 1], "robotFrame.body.opacity")
            }
            for target in [leftTorsoLayer, rightTorsoLayer, legsLayer, frameOutlineLayer, centerSeamLayer] {
                let held = continuing ? opacities[ObjectIdentifier(target)] ?? 0 : 1
                opacity(target, [held, held, 0, 0], [0, 0.22, continuing ? 0.44 : 0.52, 1], "robotFrame.closeOpacity")
            }
            let heldContent = continuing ? contentContainer.layer.flatMap { opacities[ObjectIdentifier($0)] } ?? 0 : 1
            opacity(contentContainer.layer, [heldContent, heldContent, 0, 0],
                    [0, 0.10, continuing ? 0.34 : 0.42, 1], "robotFrame.content.opacity.close")
        }
        withoutActions { transitionSeamLayer.opacity = 0 }
        animateCharacterEyes(opening: opening, continuing: continuing, duration: duration, started: started,
                             scales: eyeScales, positions: eyePositions)
        finish(after: duration, generation: generation, open: opening, completion: completion)
    }

    private func addTrack(to target: CALayer, keyPath: String, values: [Any], times: [Double],
                          duration: TimeInterval, started: CFTimeInterval, key: String) {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = times.map { NSNumber(value: $0) }
        animation.duration = duration
        animation.beginTime = target.convertTime(started, from: nil)
        animation.timingFunctions = (0..<(times.count - 1)).map { index in
            // The big unfold uses one continuous acceleration; smaller
            // anticipation, grip and docking beats ease into their contacts.
            if times.count > 2 && index == (phase == .opening ? 3 : 1) {
                return CAMediaTimingFunction(controlPoints: 0.22, 0.74, 0.24, 1)
            }
            return CAMediaTimingFunction(name: .easeInEaseOut)
        }
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        target.add(animation, forKey: key)
    }

    private func animateCharacterEyes(opening: Bool, continuing: Bool,
                                      duration: TimeInterval, started: CFTimeInterval,
                                      scales: [ObjectIdentifier: CGFloat], positions: [ObjectIdentifier: CGPoint]) {
        for eye in [leftEyeLayer, rightEyeLayer] {
            let scale = scales[ObjectIdentifier(eye)] ?? 1
            let position = positions[ObjectIdentifier(eye)] ?? eye.position
            let home = eye === leftEyeLayer ? leftEyeHome : rightEyeHome
            eye.removeAllAnimations()
            withoutActions { eye.transform = CATransform3DIdentity; eye.position = home }
            let values: [CGFloat] = continuing ? [scale, 1] : [scale, 0.28, 1, 1]
            let times: [Double] = continuing ? [0, 1] : [0, 0.10, opening ? 0.23 : 0.26, 1]
            addTrack(to: eye, keyPath: "transform.scale.y",
                     values: values.map { NSNumber(value: Double($0)) }, times: times,
                     duration: duration, started: started, key: "robotFrame.expression")
            addTrack(to: eye, keyPath: "position", values: [NSValue(point: position), NSValue(point: home), NSValue(point: home)],
                     times: [0, 0.24, 1], duration: duration, started: started, key: "robotFrame.expression.position")
        }
    }

    private func compactPose(in rect: CGRect, handsReady: Bool, mirrored: Bool = false) -> CharacterPose {
        // Exact visible-artwork mapping from RobotCharacterView: the original
        // 42pt head lives inside a 56.7 × 45.75 footprint, with its asymmetric
        // greeting hand included. No squashed head or replacement torso.
        let unit = min(rect.width / 56.7, rect.height / 45.75)
        let head = CGRect(x: rect.midX + (mirrored ? -18.69 : -23.31) * unit, y: rect.maxY - 28.96 * unit,
                          width: 42 * unit, height: 28.56 * unit)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            QuietOrbitVisualStyle.point(mirrored ? 100 - x : x, y, in: head, topDown: false)
        }
        let left = ArmPose(shoulder: point(3, 49),
            elbow: point(handsReady ? -12 : 1, handsReady ? 67 : 33),
            hand: point(handsReady ? 18 : 1, handsReady ? 81 : 9), unit: head.width / 100)
        let right = ArmPose(shoulder: point(97, 49),
            elbow: point(handsReady ? 112 : 114, handsReady ? 67 : 56),
            hand: point(handsReady ? 82 : 109, 81), unit: head.width / 100)
        let surface = QuietOrbitVisualStyle.rectangle(16, 72, 68, 30, in: head, topDown: false)
        return CharacterPose(surface: surface, head: head, left: mirrored ? right : left, right: mirrored ? left : right)
    }

    private func stablePose() -> CharacterPose {
        let content = Self.contentRect(in: bounds)
        let left = ArmPose(shoulder: CGPoint(x: content.minX - 2, y: content.midY + 28),
            elbow: CGPoint(x: content.minX - 6, y: content.midY),
            hand: CGPoint(x: content.minX - 5, y: content.midY - 22), unit: 0.25)
        let right = ArmPose(shoulder: CGPoint(x: content.maxX + 2, y: content.midY + 28),
            elbow: CGPoint(x: content.maxX + 6, y: content.midY),
            hand: CGPoint(x: content.maxX + 5, y: content.midY - 22), unit: 0.25)
        return CharacterPose(surface: content,
            head: CGRect(x: bounds.midX - Self.headSize.width / 2,
                         y: bounds.maxY - Self.headSize.height - 3,
                         width: Self.headSize.width, height: Self.headSize.height),
            left: left, right: right)
    }

    private func unfoldingPose(_ progress: CGFloat, hero: CharacterPose) -> CharacterPose {
        let full = stablePose()
        let p = min(1, max(0, progress))
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * p }
        let faceProgress = max(0, (p - 0.22) / 0.78)
        let width = hero.head.width + (full.head.width - hero.head.width) * faceProgress
        let height = width * Self.headSize.height / Self.headSize.width
        let head = CGRect(x: mix(hero.head.midX, full.head.midX) - width / 2,
                          y: mix(hero.head.maxY, full.head.maxY) - height,
                          width: width, height: height)
        let bottom = mix(hero.surface.minY, full.surface.minY)
        let gap = mix(hero.head.minY - hero.surface.maxY, full.head.minY - full.surface.maxY)
        let surface = CGRect(x: mix(hero.surface.minX, full.surface.minX), y: bottom,
            width: mix(hero.surface.width, full.surface.width), height: max(1, head.minY - gap - bottom))
        func arm(_ small: ArmPose, _ large: ArmPose) -> ArmPose {
            func point(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: mix(a.x, b.x), y: mix(a.y, b.y)) }
            return ArmPose(shoulder: point(small.shoulder, large.shoulder),
                           elbow: point(small.elbow, large.elbow),
                           hand: point(small.hand, large.hand), unit: mix(small.unit, large.unit))
        }
        return CharacterPose(surface: surface, head: head, left: arm(hero.left, full.left),
                             right: arm(hero.right, full.right))
    }

    private func heroRect(source: CGRect) -> CGRect {
        let width = min(156, max(132, bounds.width * 0.34))
        let height = width * 45.75 / 56.7
        let center = CGPoint(x: bounds.midX,
            y: bounds.maxY - min(230, max(150, bounds.height * 0.29)))
        return CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
    }

    private func headTransform(for target: CALayer, rect: CGRect) -> CATransform3D {
        let scale = max(0.001, rect.width / Self.headSize.width)
        var transform = CATransform3DMakeScale(scale, scale, 1)
        transform.m41 = rect.midX - target.position.x
        transform.m42 = rect.midY - target.position.y
        return transform
    }

    private func surfaceTransform(for target: CALayer, rect: CGRect) -> CATransform3D {
        let content = Self.contentRect(in: bounds)
        let sx = max(0.001, rect.width / max(1, content.width))
        let sy = max(0.001, rect.height / max(1, content.height))
        var transform = CATransform3DMakeScale(sx, sy, 1)
        let position = target.position
        transform.m41 = rect.minX + (position.x - content.minX) * sx - position.x
        transform.m42 = rect.minY + (position.y - content.minY) * sy - position.y
        return transform
    }

    private func armPath(_ pose: ArmPose) -> CGPath {
        let path = CGMutablePath()
        path.move(to: pose.shoulder)
        path.addLine(to: pose.elbow)
        path.addLine(to: pose.hand)
        return path
    }

    private func armHardwarePath(_ pose: ArmPose) -> CGPath {
        let path = CGMutablePath()
        let u = pose.unit
        path.addEllipse(in: CGRect(x: pose.elbow.x - 7 * u, y: pose.elbow.y - 7 * u, width: 14 * u, height: 14 * u))
        path.addRoundedRect(in: CGRect(x: pose.hand.x - 12.5 * u, y: pose.hand.y - 9 * u,
                                      width: 25 * u, height: 18 * u),
                            cornerWidth: 5 * u, cornerHeight: 5 * u)
        return path
    }

    private func rectangleMaskPath(_ rectangles: [CGRect]) -> CGPath {
        let path = CGMutablePath()
        for rect in rectangles {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }

    private func restoreTorsoRails() {
        leftTorsoLayer.mask = leftTorsoMask
        rightTorsoLayer.mask = rightTorsoMask
        let content = Self.contentRect(in: bounds)
        layoutTorsoMask(leftTorsoMask, for: leftTorsoLayer, content: content)
        layoutTorsoMask(rightTorsoMask, for: rightTorsoLayer, content: content)
    }

    private func scaledRect(_ rect: CGRect, by scale: CGFloat, center: CGPoint) -> CGRect {
        CGRect(x: center.x - rect.width * scale / 2, y: center.y - rect.height * scale / 2,
               width: rect.width * scale, height: rect.height * scale)
    }

    private func localSourceRect(for sourceRectInScreen: CGRect) -> CGRect {
        let fallback = CGRect(x: bounds.midX - 28.35, y: bounds.maxY + 4, width: 56.7, height: 45.75)
        guard !sourceRectInScreen.isNull, !sourceRectInScreen.isInfinite,
              sourceRectInScreen.width.isFinite, sourceRectInScreen.height.isFinite,
              sourceRectInScreen.midX.isFinite, sourceRectInScreen.midY.isFinite,
              sourceRectInScreen.width > 0, sourceRectInScreen.height > 0, let window else { return fallback }
        let lower = convert(window.convertPoint(fromScreen: sourceRectInScreen.origin), from: nil)
        let upper = convert(window.convertPoint(fromScreen: CGPoint(x: sourceRectInScreen.maxX,
                                                                    y: sourceRectInScreen.maxY)), from: nil)
        return CGRect(x: lower.x, y: lower.y, width: max(1, upper.x - lower.x), height: max(1, upper.y - lower.y))
    }

    private func beginTransition(_ newPhase: Phase) -> UInt {
        transitionGeneration &+= 1
        transitionTask?.cancel()
        transitionTask = nil
        phase = newPhase
        isTransitioning = true
        isFrameVisible = true
        projectRecordingSign.isHidden = true
        return transitionGeneration
    }

    private func invalidateTransition() {
        transitionGeneration &+= 1
        transitionTask?.cancel()
        transitionTask = nil
        isTransitioning = false
    }

    private func finish(after duration: TimeInterval, generation: UInt,
                        open: Bool, completion: (() -> Void)?) {
        transitionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self, !Task.isCancelled, generation == self.transitionGeneration else { return }
            self.transitionTask = nil
            self.removeTransitionAnimations()
            self.applyStableState(open: open)
            completion?()
        }
    }

    private func applyStableState(open: Bool) {
        applyOpenModelState()
        withoutActions {
            for target in transitionLayers { target.opacity = open ? target.opacity : 0 }
            layer?.opacity = 1
        }
        phase = open ? .open : .hidden
        isTransitioning = false
        isFrameVisible = open
        contentContainer.isHidden = !open
        contentView.isHidden = !open
        isHidden = !open
        nextBlinkTime = open && !reduceMotionActive ? CACurrentMediaTime() + 4.6 : .greatestFiniteMagnitude
        if !open { resetEyes() }
        layoutProjectRecordingSign()
    }

    private func applyOpenModelState() {
        withoutActions {
            for target in transitionLayers {
                target.transform = CATransform3DIdentity
                target.opacity = 1
            }
            compactBodyLayer.opacity = 0
            transitionSeamLayer.opacity = 0
            contentRevealMask.transform = CATransform3DIdentity
            restoreTorsoRails()
            layoutArms()
        }
    }

    private func removeTransitionAnimations() {
        layer?.removeAnimation(forKey: "robotFrame.reduced")
        transitionLayers.forEach { $0.removeAllAnimations() }
        armShapeLayers.forEach { $0.removeAllAnimations() }
        contentRevealMask.removeAllAnimations()
        leftTorsoMask.removeAllAnimations()
        rightTorsoMask.removeAllAnimations()
        leftEyeLayer.removeAnimation(forKey: "robotFrame.expression")
        rightEyeLayer.removeAnimation(forKey: "robotFrame.expression")
        leftEyeLayer.removeAnimation(forKey: "robotFrame.expression.position")
        rightEyeLayer.removeAnimation(forKey: "robotFrame.expression.position")
    }

    // MARK: - Gaze and blink

    private func eyeCenterInScreen() -> CGPoint {
        let local = CGPoint(x: headLayer.position.x,
                            y: headLayer.position.y)
        guard let window else { return .zero }
        let windowPoint = convert(local, to: nil)
        return window.convertPoint(toScreen: windowPoint)
    }

    private func easeEye(_ eye: CALayer, home: CGPoint, offset: CGPoint) {
        let target = CGPoint(x: home.x + offset.x, y: home.y + offset.y)
        // The pointer poll continues while the board is open. Its last target
        // is already the model position, even while the easing is in flight.
        // Leave that animation alone so stationary gaze can finish and rest.
        guard abs(target.x - eye.position.x) > 0.001
            || abs(target.y - eye.position.y) > 0.001 else { return }
        let start = eye.presentation()?.position ?? eye.position
        withoutActions { eye.position = target }
        let animation = CABasicAnimation(keyPath: "position")
        animation.fromValue = NSValue(point: start)
        animation.toValue = NSValue(point: target)
        animation.duration = 0.16
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        eye.add(animation, forKey: "robotFrame.gaze")
        gazeAnimationStartCount += 1
    }

    private func blinkIfNeeded(now: CFTimeInterval) {
        guard !reduceMotionActive, phase == .open, now >= nextBlinkTime else { return }
        blinkSequence &+= 1
        let variations: [CFTimeInterval] = [4.7, 6.1, 5.4, 7.0]
        nextBlinkTime = now + variations[Int(blinkSequence % UInt(variations.count))]
        for eye in [leftEyeLayer, rightEyeLayer] {
            let blink = CABasicAnimation(keyPath: "transform.scale.y")
            blink.fromValue = 1
            blink.toValue = 0.08
            blink.duration = 0.075
            blink.autoreverses = true
            blink.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            eye.add(blink, forKey: "robotFrame.blink")
        }
    }

    private func resetEyes() {
        for (eye, home) in [(leftEyeLayer, leftEyeHome), (rightEyeLayer, rightEyeHome)] {
            eye.removeAllAnimations()
            withoutActions { eye.position = home }
        }
    }

    private func withoutActions(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }

    private static func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        NSColor(calibratedRed: CGFloat((hex >> 16) & 0xff) / 255,
                green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255,
                alpha: alpha).cgColor
    }
}

/// Pure gaze math, kept independent of display polling so it can be tested
/// without a window or timer.
enum RobotAppFrameGaze {
    static func offset(pointer: CGPoint?,
                       eyeCenter: CGPoint,
                       displayFrame: CGRect,
                       maximum: CGSize = CGSize(width: 2.15, height: 1.45)) -> CGPoint {
        guard let pointer, pointer.x.isFinite, pointer.y.isFinite,
              displayFrame.width > 0, displayFrame.height > 0 else { return .zero }
        let clamped = CGPoint(x: min(displayFrame.maxX, max(displayFrame.minX, pointer.x)),
                              y: min(displayFrame.maxY, max(displayFrame.minY, pointer.y)))
        let normalizer = CGSize(width: max(80, displayFrame.width * 0.18),
                                height: max(80, displayFrame.height * 0.18))
        var normalized = CGPoint(x: (clamped.x - eyeCenter.x) / normalizer.width,
                                 y: (clamped.y - eyeCenter.y) / normalizer.height)
        let magnitude = hypot(normalized.x, normalized.y)
        if magnitude > 1 {
            normalized.x /= magnitude
            normalized.y /= magnitude
        }
        return CGPoint(x: normalized.x * maximum.width,
                       y: normalized.y * maximum.height)
    }
}
