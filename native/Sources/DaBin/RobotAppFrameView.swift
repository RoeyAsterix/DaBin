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

    static let openDuration: TimeInterval = 1.15
    static let closeDuration: TimeInterval = 0.78
    static let reducedDuration: TimeInterval = 0.14

    private let contentContainer = NSView(frame: .zero)
    private let contentRevealMask = CAShapeLayer()

    private let leftTorsoLayer = CAGradientLayer()
    private let rightTorsoLayer = CAGradientLayer()
    private let leftTorsoMask = CAShapeLayer()
    private let rightTorsoMask = CAShapeLayer()
    private let frameOutlineLayer = CAShapeLayer()
    private let continuousRimLayer = CAShapeLayer()
    private let centerSeamLayer = CAShapeLayer()
    private let transitionSeamLayer = CAShapeLayer()

    private let headLayer = CALayer()
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
    private var torsoMaskIsFilled = false
    private var leftEyeHome = CGPoint.zero
    private var rightEyeHome = CGPoint.zero

    private enum RobotPart { case leftTorso, rightTorso, head, leftArm, rightArm, legs }
    private enum SourcePose: Equatable { case climb, brace }

    private var decorationLayers: [CALayer] {
        [leftTorsoLayer, rightTorsoLayer, headLayer, leftArmLayer, rightArmLayer, legsLayer]
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
        for (robotLayer, name) in zip(decorationLayers,
            ["leftTorso", "rightTorso", "head", "leftArm", "rightArm", "legs"]) {
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
        guard !isHidden, !contentView.isHidden else { return nil }
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
                            reduceMotion: Bool,
                            completion: (() -> Void)? = nil) {
        reduceMotionActive = reduceMotion
        let sourceRect = localSourceRect(for: sourceRectInScreen)
        let continuing = isTransitioning
        let currentTransforms = continuing ? presentationTransforms() : [:]
        let currentOpacities = continuing ? presentationOpacities() : [:]
        let currentTorsoMasks = continuing ? presentationTorsoMasks() : [:]
        let currentContentTransform = continuing
            ? (contentContainer.layer?.presentation()?.transform
                ?? contentContainer.layer?.transform ?? CATransform3DIdentity) : nil
        let currentContentOpacity = continuing
            ? (contentContainer.layer?.presentation()?.opacity ?? contentContainer.layer?.opacity ?? 0) : nil
        let currentOutlineTransform = continuing
            ? (frameOutlineLayer.presentation()?.transform ?? frameOutlineLayer.transform) : nil
        let currentOutlineOpacity = continuing
            ? (frameOutlineLayer.presentation()?.opacity ?? frameOutlineLayer.opacity) : nil
        let currentCenterSeamTransform = continuing
            ? (centerSeamLayer.presentation()?.transform ?? centerSeamLayer.transform) : nil
        let currentCenterSeamOpacity = continuing
            ? (centerSeamLayer.presentation()?.opacity ?? centerSeamLayer.opacity) : nil
        let currentTransitionSeamOpacity = continuing
            ? (transitionSeamLayer.presentation()?.opacity ?? transitionSeamLayer.opacity) : nil
        let currentTransitionSeamTransform = continuing
            ? (transitionSeamLayer.presentation()?.transform ?? transitionSeamLayer.transform) : nil

        let generation = beginTransition(.opening)
        isHidden = false
        contentContainer.isHidden = false
        contentView.isHidden = false
        layoutSubtreeIfNeeded()
        removeTransitionAnimations()

        if reduceMotion {
            applyOpenModelState()
            animateReducedFade(open: true, duration: Self.reducedDuration)
            finish(after: Self.reducedDuration, generation: generation, open: true,
                   completion: completion)
            return
        }

        withoutActions {
            layer?.opacity = 1
            if !continuing { setTorsoSolid(true) }
        }
        if continuing { animateTorsoFill(from: currentTorsoMasks, delay: 0, duration: 0.20) }
        for (index, robotLayer) in decorationLayers.enumerated() {
            let climb = sourcePoseTransform(for: robotLayer, sourceRect: sourceRect,
                                            pose: .climb, island: island)
            let brace = sourcePoseTransform(for: robotLayer, sourceRect: sourceRect,
                                            pose: .brace, island: island)
            let start = currentTransforms[ObjectIdentifier(robotLayer)] ?? climb
            withoutActions { robotLayer.transform = CATransform3DIdentity; robotLayer.opacity = 1 }
            addOpeningTransform(to: robotLayer, from: start, brace: brace,
                                outward: splitDirection(for: robotLayer),
                                delay: Double(index) * 0.006,
                                continuing: continuing)
            if let opacity = currentOpacities[ObjectIdentifier(robotLayer)], opacity < 1 {
                animateOpacity(robotLayer, from: opacity, to: 1, duration: 0.20, delay: 0,
                               key: "robotFrame.reopenOpacity")
            }
        }

        let contentClimb = bodySurfaceTransform(for: contentContainer.layer,
                                                sourceRect: sourceRect,
                                                pose: .climb, island: island)
        let contentBrace = bodySurfaceTransform(for: contentContainer.layer,
                                                sourceRect: sourceRect,
                                                pose: .brace, island: island)
        let outlineClimb = bodySurfaceTransform(for: frameOutlineLayer,
                                                sourceRect: sourceRect,
                                                pose: .climb, island: island)
        let outlineBrace = bodySurfaceTransform(for: frameOutlineLayer,
                                                sourceRect: sourceRect,
                                                pose: .brace, island: island)
        let centerSeamClimb = bodySurfaceTransform(for: centerSeamLayer,
                                                   sourceRect: sourceRect,
                                                   pose: .climb, island: island)
        let centerSeamBrace = bodySurfaceTransform(for: centerSeamLayer,
                                                   sourceRect: sourceRect,
                                                   pose: .brace, island: island)
        withoutActions {
            contentRevealMask.transform = CATransform3DIdentity
            contentContainer.layer?.transform = CATransform3DIdentity
            contentContainer.layer?.opacity = 1
            frameOutlineLayer.transform = CATransform3DIdentity
            frameOutlineLayer.opacity = 1
            centerSeamLayer.transform = CATransform3DIdentity
            centerSeamLayer.opacity = 1
            transitionSeamLayer.transform = CATransform3DIdentity
            transitionSeamLayer.opacity = 0
        }
        if let contentLayer = contentContainer.layer {
            addOpeningTransform(to: contentLayer,
                                from: currentContentTransform ?? contentClimb,
                                brace: contentBrace, outward: 0, delay: 0,
                                continuing: continuing)
        }
        addOpeningTransform(to: frameOutlineLayer,
                            from: currentOutlineTransform ?? outlineClimb,
                            brace: outlineBrace, outward: 0, delay: 0,
                            continuing: continuing)
        addOpeningTransform(to: centerSeamLayer,
                            from: currentCenterSeamTransform ?? centerSeamClimb,
                            brace: centerSeamBrace, outward: 0, delay: 0,
                            continuing: continuing)
        let transitionSeamStart = currentTransitionSeamTransform
            ?? sourcePoseTransform(for: transitionSeamLayer,
                                   sourceRect: sourceRect, pose: .climb, island: island)
        let transitionSeamBrace = sourcePoseTransform(for: transitionSeamLayer,
                                                      sourceRect: sourceRect,
                                                      pose: .brace, island: island)
        addOpeningTransform(to: transitionSeamLayer, from: transitionSeamStart,
                            brace: transitionSeamBrace, outward: 0, delay: 0,
                            continuing: continuing)
        animateOpacity(transitionSeamLayer, from: currentTransitionSeamOpacity ?? 1, to: 0,
                       duration: 0.78, delay: 0.17, key: "robotFrame.splitSeam.open")
        animateOpacity(frameOutlineLayer, from: currentOutlineOpacity ?? 0, to: 1,
                       duration: 0.22, delay: 0.82, key: "robotFrame.outline.open")
        animateOpacity(centerSeamLayer, from: currentCenterSeamOpacity ?? 0, to: 1,
                       duration: 0.18, delay: 0.86, key: "robotFrame.seam.open")
        animateOpacity(contentContainer.layer, from: currentContentOpacity ?? 0, to: 1,
                       duration: 0.68, delay: 0.24, key: "robotFrame.content.open")

        finish(after: Self.openDuration, generation: generation, open: true,
               completion: completion)
    }

    public func animateClose(to sourceRectInScreen: CGRect,
                             island: Bool,
                             reduceMotion: Bool,
                             completion: (() -> Void)? = nil) {
        reduceMotionActive = reduceMotion
        let sourceRect = localSourceRect(for: sourceRectInScreen)
        let continuing = isTransitioning
        let currentTransforms = presentationTransforms()
        let currentOpacities = presentationOpacities()
        let currentTorsoMasks = presentationTorsoMasks()
        let currentContentTransform = contentContainer.layer?.presentation()?.transform
            ?? contentContainer.layer?.transform ?? CATransform3DIdentity
        let currentContentOpacity = contentContainer.layer?.presentation()?.opacity
            ?? contentContainer.layer?.opacity ?? 1
        let currentOutlineTransform = frameOutlineLayer.presentation()?.transform
            ?? frameOutlineLayer.transform
        let currentOutlineOpacity = frameOutlineLayer.presentation()?.opacity ?? frameOutlineLayer.opacity
        let currentCenterSeamTransform = centerSeamLayer.presentation()?.transform
            ?? centerSeamLayer.transform
        let currentCenterSeamOpacity = centerSeamLayer.presentation()?.opacity ?? centerSeamLayer.opacity
        let currentTransitionSeamOpacity = transitionSeamLayer.presentation()?.opacity
            ?? transitionSeamLayer.opacity
        let currentTransitionSeamTransform = transitionSeamLayer.presentation()?.transform
            ?? transitionSeamLayer.transform
        let generation = beginTransition(.closing)
        isHidden = false
        contentContainer.isHidden = false
        contentView.isHidden = false
        layoutSubtreeIfNeeded()
        removeTransitionAnimations()

        if reduceMotion {
            applyOpenModelState()
            animateReducedFade(open: false, duration: Self.reducedDuration)
            finish(after: Self.reducedDuration, generation: generation, open: false,
                   completion: completion)
            return
        }

        withoutActions {
            layer?.opacity = 1
        }
        // Keep the stable perimeter at first. The shell fills continuously
        // only as the content contracts, instead of flashing a backing plate.
        animateTorsoFill(from: currentTorsoMasks, delay: 0.22, duration: 0.29)
        let gather = closingGatherRect(source: sourceRect)
        let coiled = scaledRect(gather, by: 0.92, center: CGPoint(x: gather.midX, y: gather.midY + 3))
        let tuckCenter = CGPoint(x: sourceRect.midX,
                                 y: island ? sourceRect.maxY - sourceRect.height * 0.06 : sourceRect.midY)
        let tucked = scaledRect(sourceRect, by: 0.12, center: tuckCenter)
        let beginTime = CACurrentMediaTime()
        for robotLayer in decorationLayers {
            let start = currentTransforms[ObjectIdentifier(robotLayer)] ?? CATransform3DIdentity
            addClosingTransform(to: robotLayer, from: start, source: sourceRect,
                                gather: gather, coiled: coiled, tucked: tucked,
                                island: island, continuing: continuing, beginTime: beginTime,
                                surface: false, key: "robotFrame.close")
            addClosingOpacity(to: robotLayer,
                              from: currentOpacities[ObjectIdentifier(robotLayer)] ?? 1,
                              beginTime: beginTime)
        }

        withoutActions {
            contentRevealMask.transform = CATransform3DIdentity
            contentContainer.layer?.opacity = 0
            frameOutlineLayer.opacity = 0
            centerSeamLayer.opacity = 0
            transitionSeamLayer.opacity = 0
        }
        if let contentLayer = contentContainer.layer {
            addClosingTransform(to: contentLayer, from: currentContentTransform, source: sourceRect,
                                gather: gather, coiled: coiled, tucked: tucked,
                                island: island, continuing: continuing, beginTime: beginTime,
                                surface: true, key: "robotFrame.content.transform.close")
        }
        // Transform and opacity need different keys. Reusing a key silently
        // replaces the shrink with a fade, leaving the board full-size.
        animateOpacity(contentContainer.layer, from: currentContentOpacity, to: 0,
                       duration: 0.30, delay: 0.20, key: "robotFrame.content.opacity.close")
        animateOpacity(frameOutlineLayer, from: currentOutlineOpacity, to: 0,
                       duration: 0.36, delay: 0.18, key: "robotFrame.outline.close")
        addClosingTransform(to: frameOutlineLayer, from: currentOutlineTransform, source: sourceRect,
                            gather: gather, coiled: coiled, tucked: tucked,
                            island: island, continuing: continuing, beginTime: beginTime,
                            surface: true, key: "robotFrame.outline.transform.close")
        animateOpacity(centerSeamLayer, from: currentCenterSeamOpacity, to: 0,
                       duration: 0.35, delay: 0.20, key: "robotFrame.seam.close")
        addClosingTransform(to: centerSeamLayer, from: currentCenterSeamTransform, source: sourceRect,
                            gather: gather, coiled: coiled, tucked: tucked,
                            island: island, continuing: continuing, beginTime: beginTime,
                            surface: true, key: "robotFrame.centerSeam.transform.close")
        addClosingTransform(to: transitionSeamLayer, from: currentTransitionSeamTransform,
                            source: sourceRect, gather: gather, coiled: coiled, tucked: tucked,
                            island: island, continuing: continuing, beginTime: beginTime,
                            surface: false, key: "robotFrame.splitSeam.close")
        let seam = CAKeyframeAnimation(keyPath: "opacity")
        seam.values = [currentTransitionSeamOpacity, 0, 0.9, 0.9, 0]
        seam.keyTimes = [0, 0.18, 0.60, 0.80, 1]
        seam.duration = Self.closeDuration
        seam.beginTime = beginTime
        seam.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 4)
        transitionSeamLayer.add(seam, forKey: "robotFrame.splitSeam.opacity.close")

        finish(after: Self.closeDuration, generation: generation, open: false,
               completion: completion)
    }

    /// Called by the owning controller's existing pointer poll. This schedules
    /// no timer: it only eases the mint eyes to the latest clamped target and uses
    /// the same tick to trigger an occasional blink.
    public func updatePointer(screenPoint: CGPoint?, displayFrame: CGRect) {
        guard isFrameVisible || isTransitioning else { return }
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

        // Fill the complete continuous corner rim. The existing four-rectangle
        // torso masks stay intact for the rail-to-solid closing choreography.
        // As an outline child this rim shares its shrink/fade, not a new timer.
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
        let contentInTorso = CGRect(x: content.minX - torso.frame.minX,
                                    y: content.minY - torso.frame.minY,
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
        mask.path = torsoMaskIsFilled ? solidTorsoMaskPath(for: torso) : rectangleMaskPath(rails)
        mask.fillColor = NSColor.black.cgColor
    }

    private func layoutHead() {
        let width = Self.headSize.width
        let height = Self.headSize.height
        let rect = CGRect(x: bounds.midX - width / 2,
                          y: bounds.maxY - height - 3,
                          width: width, height: height)
        headLayer.frame = rect
    }

    private func layoutArms() {
        let content = Self.contentRect(in: bounds)
        leftArmLayer.frame = bounds
        rightArmLayer.frame = bounds

        let left = CGMutablePath()
        left.move(to: CGPoint(x: content.minX - 2, y: content.midY + 28))
        left.addCurve(to: CGPoint(x: max(bounds.minX + 1, content.minX - 7), y: content.midY - 22),
                      control1: CGPoint(x: content.minX - 8, y: content.midY + 20),
                      control2: CGPoint(x: content.minX - 9, y: content.midY - 13))
        leftArmLayer.path = left
        leftArmHighlight.path = left

        let right = CGMutablePath()
        right.move(to: CGPoint(x: content.maxX + 2, y: content.midY + 28))
        right.addCurve(to: CGPoint(x: min(bounds.maxX - 1, content.maxX + 7), y: content.midY - 22),
                       control1: CGPoint(x: content.maxX + 8, y: content.midY + 20),
                       control2: CGPoint(x: content.maxX + 9, y: content.midY - 13))
        rightArmLayer.path = right
        rightArmHighlight.path = right
        for (hardware, x, direction) in [(leftArmHardware, content.minX - 7, CGFloat(-1)),
                                         (rightArmHardware, content.maxX + 7, CGFloat(1))] {
            let joints = CGMutablePath()
            joints.addEllipse(in: CGRect(x: x - 2.6, y: content.midY - 2.6, width: 5.2, height: 5.2))
            joints.addRoundedRect(in: CGRect(x: x - 2.5 + direction * 0.3, y: content.midY - 26,
                                            width: 5, height: 7), cornerWidth: 1.5, cornerHeight: 1.5)
            hardware.path = joints
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

    /// Four rectangles keep identical path topology in both rail and filled
    /// states. The fill can therefore grow smoothly without swapping masks.
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

    private func solidTorsoMaskPath(for torso: CALayer) -> CGPath {
        let empty = CGRect(origin: torso.bounds.origin, size: .zero)
        return rectangleMaskPath([torso.bounds, empty, empty, empty])
    }

    private func presentationTorsoMasks() -> [ObjectIdentifier: CGPath] {
        Dictionary(uniqueKeysWithValues: [leftTorsoLayer, rightTorsoLayer].map { torso in
            let mask = torso.mask as? CAShapeLayer
            let path = (mask?.presentation() as? CAShapeLayer)?.path ?? mask?.path
                ?? solidTorsoMaskPath(for: torso)
            return (ObjectIdentifier(torso), path)
        })
    }

    private func animateTorsoFill(from paths: [ObjectIdentifier: CGPath],
                                 delay: TimeInterval, duration: TimeInterval) {
        withoutActions {
            setTorsoSolid(false)
            torsoMaskIsFilled = true
        }
        for (torso, mask) in [(leftTorsoLayer, leftTorsoMask), (rightTorsoLayer, rightTorsoMask)] {
            let end = solidTorsoMaskPath(for: torso)
            withoutActions { mask.path = end }
            let fill = CABasicAnimation(keyPath: "path")
            fill.fromValue = paths[ObjectIdentifier(torso)] ?? end
            fill.toValue = end
            fill.duration = duration
            fill.beginTime = CACurrentMediaTime() + delay
            fill.fillMode = .backwards
            fill.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            mask.add(fill, forKey: "robotFrame.shellFill")
        }
    }

    private func scaledRect(_ rect: CGRect, by scale: CGFloat, center: CGPoint) -> CGRect {
        CGRect(x: center.x - rect.width * scale / 2, y: center.y - rect.height * scale / 2,
               width: rect.width * scale, height: rect.height * scale)
    }

    private func closingGatherRect(source: CGRect) -> CGRect {
        let width = min(92, max(62, source.width * 1.20))
        let height = min(118, max(90, source.height * 1.12))
        let center = CGPoint(x: bounds.midX + (source.midX - bounds.midX) * 0.18,
                             y: max(bounds.minY + height / 2, bounds.maxY - height * 1.08))
        return CGRect(x: center.x - width / 2, y: center.y - height / 2,
                      width: width, height: height)
    }

    private func closingPreparation(from start: CATransform3D, for target: CALayer,
                                    surface: Bool, continuing: Bool) -> CATransform3D {
        guard !continuing else { return start }
        var result = start
        if surface || target === transitionSeamLayer || target === leftTorsoLayer || target === rightTorsoLayer {
            result.m11 *= 0.992
            result.m22 *= 0.975
            result.m42 += 3
        } else if target === headLayer {
            result.m11 *= 0.97
            result.m22 *= 0.97
            result.m42 -= 3
        } else if target === legsLayer {
            result.m22 *= 0.93
            result.m42 += 3
        } else {
            result.m41 += target === leftArmLayer ? 4 : -4
            result.m42 += 4
        }
        return result
    }

    private func addClosingTransform(to target: CALayer, from start: CATransform3D,
                                     source: CGRect, gather: CGRect, coiled: CGRect, tucked: CGRect,
                                     island: Bool, continuing: Bool, beginTime: CFTimeInterval,
                                     surface: Bool, key: String) {
        func pose(_ rect: CGRect, _ pose: SourcePose = .brace) -> CATransform3D {
            surface ? bodySurfaceTransform(for: target, sourceRect: rect, pose: pose, island: island)
                : sourcePoseTransform(for: target, sourceRect: rect, pose: pose, island: island)
        }
        let end = pose(tucked, island ? .climb : .brace)
        let animation = CAKeyframeAnimation(keyPath: "transform")
        animation.values = [start, closingPreparation(from: start, for: target, surface: surface,
                                                      continuing: continuing),
                            pose(gather), pose(coiled), pose(source, island ? .climb : .brace), end]
            .map { NSValue(caTransform3D: $0) }
        animation.keyTimes = [0, 0.12, 0.60, 0.72, 0.87, 1]
        animation.timingFunctions = [CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(controlPoints: 0.32, 0.04, 0.16, 1),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(controlPoints: 0.42, 0, 0.58, 1),
            CAMediaTimingFunction(name: .easeIn)]
        animation.duration = Self.closeDuration
        animation.beginTime = beginTime
        withoutActions { target.transform = end }
        target.add(animation, forKey: key)
    }

    private func addClosingOpacity(to target: CALayer, from opacity: Float, beginTime: CFTimeInterval) {
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [opacity, 1, 1, 0]
        animation.keyTimes = [0, 0.12, 0.80, 1]
        animation.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 3)
        animation.duration = Self.closeDuration
        animation.beginTime = beginTime
        withoutActions { target.opacity = 0 }
        target.add(animation, forKey: "robotFrame.closeOpacity")
    }

    private func beginTransition(_ newPhase: Phase) -> UInt {
        transitionGeneration &+= 1
        transitionTask?.cancel()
        transitionTask = nil
        phase = newPhase
        isTransitioning = true
        isFrameVisible = true
        return transitionGeneration
    }

    private func invalidateTransition() {
        transitionGeneration &+= 1
        transitionTask?.cancel()
        transitionTask = nil
        isTransitioning = false
    }

    private func finish(after duration: TimeInterval,
                        generation: UInt,
                        open: Bool,
                        completion: (() -> Void)?) {
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
        withoutActions {
            layer?.opacity = 1
            for robotLayer in decorationLayers {
                robotLayer.transform = CATransform3DIdentity
                robotLayer.opacity = open ? 1 : 0
            }
            contentRevealMask.transform = CATransform3DIdentity
            contentContainer.layer?.transform = CATransform3DIdentity
            contentContainer.layer?.opacity = open ? 1 : 0
            frameOutlineLayer.transform = CATransform3DIdentity
            frameOutlineLayer.opacity = open ? 1 : 0
            centerSeamLayer.transform = CATransform3DIdentity
            centerSeamLayer.opacity = open ? 1 : 0
            transitionSeamLayer.opacity = 0
            transitionSeamLayer.transform = CATransform3DIdentity
            setTorsoSolid(false)
        }
        phase = open ? .open : .hidden
        isTransitioning = false
        isFrameVisible = open
        contentContainer.isHidden = !open
        contentView.isHidden = !open
        isHidden = !open
        nextBlinkTime = open && !reduceMotionActive
            ? CACurrentMediaTime() + 4.6 : .greatestFiniteMagnitude
        if !open { resetEyes() }
    }

    private func applyOpenModelState() {
        withoutActions {
            for robotLayer in decorationLayers {
                robotLayer.transform = CATransform3DIdentity
                robotLayer.opacity = 1
            }
            contentRevealMask.transform = CATransform3DIdentity
            contentContainer.layer?.transform = CATransform3DIdentity
            contentContainer.layer?.opacity = 1
            frameOutlineLayer.transform = CATransform3DIdentity
            frameOutlineLayer.opacity = 1
            centerSeamLayer.transform = CATransform3DIdentity
            centerSeamLayer.opacity = 1
            transitionSeamLayer.opacity = 0
            transitionSeamLayer.transform = CATransform3DIdentity
            setTorsoSolid(false)
        }
    }

    private func animateReducedFade(open: Bool, duration: TimeInterval) {
        let root = layer
        withoutActions { root?.opacity = open ? 1 : 0 }
        animateOpacity(root, from: open ? 0 : 1, to: open ? 1 : 0,
                       duration: duration, delay: 0, key: "robotFrame.reduced")
    }

    private func addOpeningTransform(to target: CALayer,
                                     from start: CATransform3D,
                                     brace: CATransform3D,
                                     outward: CGFloat,
                                     delay: TimeInterval,
                                     continuing: Bool) {
        var expanded = CATransform3DIdentity
        expanded.m11 = 1.012
        expanded.m22 = 1.006
        expanded.m41 = outward
        let animation = CAKeyframeAnimation(keyPath: "transform")
        if continuing {
            animation.values = [NSValue(caTransform3D: start),
                                NSValue(caTransform3D: interpolatedTransform(from: start, to: expanded, progress: 0.76)),
                                NSValue(caTransform3D: expanded),
                                NSValue(caTransform3D: CATransform3DIdentity)]
            animation.keyTimes = [0, 0.67, 0.87, 1]
            animation.timingFunctions = [
                CAMediaTimingFunction(controlPoints: 0.18, 0.84, 0.28, 1),
                CAMediaTimingFunction(name: .easeOut),
                CAMediaTimingFunction(name: .easeInEaseOut)
            ]
        } else {
            // The compact source becomes a recognizable robot first: hands
            // release the island, feet drop, and the two torso halves brace.
            // Only then does that same body split continuously into the app.
            animation.values = [NSValue(caTransform3D: start),
                                NSValue(caTransform3D: brace),
                                NSValue(caTransform3D: brace),
                                NSValue(caTransform3D: interpolatedTransform(from: brace, to: expanded, progress: 0.73)),
                                NSValue(caTransform3D: expanded),
                                NSValue(caTransform3D: CATransform3DIdentity)]
            animation.keyTimes = [0, 0.19, 0.23, 0.70, 0.88, 1]
            animation.timingFunctions = [
                CAMediaTimingFunction(name: .easeOut),
                CAMediaTimingFunction(name: .linear),
                CAMediaTimingFunction(controlPoints: 0.18, 0.84, 0.28, 1),
                CAMediaTimingFunction(name: .easeOut),
                CAMediaTimingFunction(name: .easeInEaseOut)
            ]
        }
        animation.duration = Self.openDuration - delay
        animation.beginTime = CACurrentMediaTime() + delay
        animation.fillMode = .backwards
        animation.isRemovedOnCompletion = true
        target.add(animation, forKey: "robotFrame.open")
    }

    private func animateTransform(_ target: CALayer,
                                  from: CATransform3D,
                                  to: CATransform3D,
                                  duration: TimeInterval,
                                  delay: TimeInterval,
                                  timing: CAMediaTimingFunction,
                                  key: String) {
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: from)
        animation.toValue = NSValue(caTransform3D: to)
        animation.duration = duration
        animation.beginTime = CACurrentMediaTime() + delay
        animation.fillMode = .backwards
        animation.timingFunction = timing
        target.add(animation, forKey: key)
    }

    private func animateOpacity(_ target: CALayer?,
                                from: Float,
                                to: Float,
                                duration: TimeInterval,
                                delay: TimeInterval,
                                key: String) {
        guard let target else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.beginTime = CACurrentMediaTime() + delay
        animation.fillMode = .backwards
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        target.add(animation, forKey: key)
    }

    private func sourcePoseTransform(for target: CALayer,
                                     sourceRect: CGRect,
                                     pose: SourcePose,
                                     island: Bool) -> CATransform3D {
        let source = normalizedSourceRect(sourceRect)
        let climbing = pose == .climb && island
        let content = Self.contentRect(in: bounds)

        if target === transitionSeamLayer {
            let feature = CGPoint(x: bounds.midX, y: content.midY)
            let destination = CGPoint(x: source.midX,
                                      y: source.minY + source.height * (climbing ? 0.58 : 0.43))
            return mappedTransform(for: target, feature: feature, destination: destination,
                                   scaleX: source.width * (climbing ? 0.48 : 0.68) / max(1, bounds.width),
                                   scaleY: source.height * (climbing ? 0.34 : 0.52) /
                                       max(1, content.height + 14))
        }

        switch part(for: target) {
        case .head:
            let feature = CGPoint(x: target.bounds.midX, y: target.bounds.midY)
            let destination = CGPoint(x: source.midX,
                                      y: source.minY + source.height * (climbing ? 0.84 : 0.78))
            // Preserve the canonical head's aspect ratio while it travels
            // between the island and the application, not a flattened bin.
            let scale = source.width * (climbing ? 0.47 : 0.55) / max(1, target.bounds.width)
            return mappedTransform(for: target, feature: feature, destination: destination,
                                   scaleX: scale, scaleY: scale)

        case .leftTorso, .rightTorso:
            let isLeft = target === leftTorsoLayer
            let direction: CGFloat = isLeft ? -1 : 1
            let feature = CGPoint(x: target.bounds.midX, y: target.bounds.midY)
            let destination = CGPoint(
                x: source.midX + direction * source.width * (climbing ? 0.10 : 0.18),
                y: source.minY + source.height * (climbing ? 0.58 : 0.43))
            return mappedTransform(for: target, feature: feature, destination: destination,
                                   scaleX: source.width * (climbing ? 0.24 : 0.34) /
                                       max(1, target.bounds.width),
                                   scaleY: source.height * (climbing ? 0.34 : 0.52) /
                                       max(1, target.bounds.height))

        case .leftArm, .rightArm:
            let isLeft = target === leftArmLayer
            let direction: CGFloat = isLeft ? -1 : 1
            // The free rounded endpoint is the robot's hand. It grips the
            // island lip first, then slides down to the source body's side.
            let feature = CGPoint(x: isLeft ? max(bounds.minX + 1, content.minX - 7)
                                            : min(bounds.maxX - 1, content.maxX + 7),
                                  y: content.midY - 22)
            let destination = CGPoint(
                x: source.midX + direction * source.width * (climbing ? 0.20 : 0.43),
                y: source.minY + source.height * (climbing ? 0.94 : 0.50))
            let scale = source.height * (climbing ? 0.25 : 0.31) / 55
            return mappedTransform(for: target, feature: feature, destination: destination,
                                   scaleX: scale, scaleY: scale)

        case .legs:
            let spread = min(35, max(22, bounds.width * 0.075))
            let feature = CGPoint(x: bounds.midX, y: 5)
            let destination = CGPoint(x: source.midX,
                                      y: source.minY + source.height * (climbing ? 0.35 : 0.07))
            let scale = source.width * (climbing ? 0.38 : 0.58) / max(1, spread * 2 + 14)
            return mappedTransform(for: target, feature: feature, destination: destination,
                                   scaleX: scale, scaleY: scale)
        }
    }

    private func part(for target: CALayer) -> RobotPart {
        if target === leftTorsoLayer { return .leftTorso }
        if target === rightTorsoLayer { return .rightTorso }
        if target === headLayer { return .head }
        if target === leftArmLayer { return .leftArm }
        if target === rightArmLayer { return .rightArm }
        return .legs
    }

    private func mappedTransform(for target: CALayer,
                                 feature: CGPoint,
                                 destination: CGPoint,
                                 scaleX: CGFloat,
                                 scaleY: CGFloat) -> CATransform3D {
        let anchor = CGPoint(x: target.bounds.minX + target.bounds.width * target.anchorPoint.x,
                             y: target.bounds.minY + target.bounds.height * target.anchorPoint.y)
        var transform = CATransform3DMakeScale(max(0.015, scaleX), max(0.015, scaleY), 1)
        transform.m41 = destination.x - target.position.x - (feature.x - anchor.x) * transform.m11
        transform.m42 = destination.y - target.position.y - (feature.y - anchor.y) * transform.m22
        return transform
    }

    /// Maps the live board and its finishing strokes onto the same compact
    /// torso rectangle. Because all three use this transform, the content can
    /// fade through the shell without a detached rectangle or sliding mask.
    private func bodySurfaceTransform(for target: CALayer?,
                                      sourceRect: CGRect,
                                      pose: SourcePose,
                                      island: Bool) -> CATransform3D {
        guard let target else { return CATransform3DIdentity }
        let source = normalizedSourceRect(sourceRect)
        let climbing = pose == .climb && island
        let content = Self.contentRect(in: bounds)
        let targetIsContent = target === contentContainer.layer
        let feature = targetIsContent
            ? CGPoint(x: target.bounds.midX, y: target.bounds.midY)
            : CGPoint(x: content.midX, y: content.midY)
        let destination = CGPoint(x: source.midX,
                                  y: source.minY + source.height * (climbing ? 0.58 : 0.43))
        return mappedTransform(for: target, feature: feature, destination: destination,
                               scaleX: source.width * (climbing ? 0.48 : 0.68) /
                                   max(1, content.width),
                               scaleY: source.height * (climbing ? 0.34 : 0.52) /
                                   max(1, content.height))
    }

    /// Transition frames need a solid robot body. Stable frames restore the
    /// rail masks so a transparent BoardView still shows the desktop through
    /// its center instead of a purple backing plate.
    private func setTorsoSolid(_ solid: Bool) {
        torsoMaskIsFilled = solid
        leftTorsoLayer.mask = solid ? nil : leftTorsoMask
        rightTorsoLayer.mask = solid ? nil : rightTorsoMask
        let content = Self.contentRect(in: bounds)
        layoutTorsoMask(leftTorsoMask, for: leftTorsoLayer, content: content)
        layoutTorsoMask(rightTorsoMask, for: rightTorsoLayer, content: content)
    }

    private func splitDirection(for target: CALayer) -> CGFloat {
        if target === leftTorsoLayer { return -4 }
        if target === rightTorsoLayer { return 4 }
        if target === leftArmLayer { return -2 }
        if target === rightArmLayer { return 2 }
        return 0
    }

    private func localSourceRect(for sourceRectInScreen: CGRect) -> CGRect {
        let fallback = CGRect(x: bounds.midX - 36, y: bounds.maxY + 8,
                              width: 72, height: 88)
        guard !sourceRectInScreen.isNull, !sourceRectInScreen.isInfinite,
              sourceRectInScreen.midX.isFinite, sourceRectInScreen.midY.isFinite,
              let window else { return fallback }
        let screenRect = normalizedSourceRect(sourceRectInScreen)
        let lowerWindow = window.convertPoint(fromScreen: screenRect.origin)
        let upperWindow = window.convertPoint(fromScreen: CGPoint(x: screenRect.maxX, y: screenRect.maxY))
        let lower = convert(lowerWindow, from: nil)
        let upper = convert(upperWindow, from: nil)
        return normalizedSourceRect(CGRect(x: lower.x, y: lower.y,
                                           width: upper.x - lower.x,
                                           height: upper.y - lower.y))
    }

    private func normalizedSourceRect(_ rect: CGRect) -> CGRect {
        let standardized = rect.standardized
        guard standardized.width.isFinite, standardized.height.isFinite,
              standardized.minX.isFinite, standardized.minY.isFinite else {
            return CGRect(x: bounds.midX - 36, y: bounds.maxY + 8, width: 72, height: 88)
        }
        let width = max(1, standardized.width)
        let height = max(1, standardized.height)
        return CGRect(x: standardized.midX - width / 2,
                      y: standardized.midY - height / 2,
                      width: width, height: height)
    }

    private func presentationTransforms() -> [ObjectIdentifier: CATransform3D] {
        Dictionary(uniqueKeysWithValues: decorationLayers.map {
            (ObjectIdentifier($0), $0.presentation()?.transform ?? $0.transform)
        })
    }

    private func presentationOpacities() -> [ObjectIdentifier: Float] {
        Dictionary(uniqueKeysWithValues: decorationLayers.map {
            (ObjectIdentifier($0), $0.presentation()?.opacity ?? $0.opacity)
        })
    }

    private func interpolatedTransform(from: CATransform3D,
                                       to: CATransform3D,
                                       progress: CGFloat) -> CATransform3D {
        var result = CATransform3DIdentity
        result.m11 = from.m11 + (to.m11 - from.m11) * progress
        result.m22 = from.m22 + (to.m22 - from.m22) * progress
        result.m33 = 1
        result.m41 = from.m41 + (to.m41 - from.m41) * progress
        result.m42 = from.m42 + (to.m42 - from.m42) * progress
        return result
    }

    private func removeTransitionAnimations() {
        layer?.removeAnimation(forKey: "robotFrame.reduced")
        contentContainer.layer?.removeAllAnimations()
        contentRevealMask.removeAllAnimations()
        leftTorsoMask.removeAllAnimations()
        rightTorsoMask.removeAllAnimations()
        decorationLayers.forEach { $0.removeAllAnimations() }
        frameOutlineLayer.removeAllAnimations()
        centerSeamLayer.removeAllAnimations()
        transitionSeamLayer.removeAllAnimations()
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
