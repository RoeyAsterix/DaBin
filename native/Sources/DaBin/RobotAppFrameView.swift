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
    var hasActiveEyeMotion: Bool {
        [leftEyeLayer, rightEyeLayer, leftPupilLayer, rightPupilLayer]
            .contains { !($0.animationKeys() ?? []).isEmpty }
    }
    var usesSolidTransitionTorso: Bool {
        leftTorsoLayer.mask == nil && rightTorsoLayer.mask == nil
    }

    private enum Phase { case hidden, opening, open, closing }

    static let openDuration: TimeInterval = 1.15
    static let closeDuration: TimeInterval = 0.42
    static let reducedDuration: TimeInterval = 0.14

    private let contentContainer = NSView(frame: .zero)
    private let contentRevealMask = CALayer()

    private let leftTorsoLayer = CAGradientLayer()
    private let rightTorsoLayer = CAGradientLayer()
    private let leftTorsoMask = CAShapeLayer()
    private let rightTorsoMask = CAShapeLayer()
    private let frameOutlineLayer = CAShapeLayer()
    private let centerSeamLayer = CAShapeLayer()
    private let transitionSeamLayer = CAShapeLayer()

    private let headLayer = CALayer()
    private let headShellLayer = CAGradientLayer()
    private let faceScreenLayer = CAShapeLayer()
    private let leftEyeLayer = CALayer()
    private let rightEyeLayer = CALayer()
    private let leftPupilLayer = CAShapeLayer()
    private let rightPupilLayer = CAShapeLayer()
    private let mouthLayer = CAShapeLayer()

    private let leftArmLayer = CAShapeLayer()
    private let rightArmLayer = CAShapeLayer()
    private let legsLayer = CALayer()
    private let leftLegLayer = CAShapeLayer()
    private let rightLegLayer = CAShapeLayer()
    private let leftFootLayer = CAShapeLayer()
    private let rightFootLayer = CAShapeLayer()

    private var phase: Phase = .hidden
    private var transitionGeneration: UInt = 0
    private var transitionTask: Task<Void, Never>?
    private var nextBlinkTime: CFTimeInterval = .greatestFiniteMagnitude
    private var blinkSequence: UInt = 0
    private var reduceMotionActive = false
    private var leftPupilHome = CGPoint.zero
    private var rightPupilHome = CGPoint.zero

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
            contentRevealMask.cornerRadius = 13

            layoutTorso()
            layoutHead()
            layoutArms()
            layoutLegs()
            layoutOutlineAndSeam()
        }
    }

    /// Only the hosted application surface participates in hit testing. Robot
    /// chrome is made entirely of layers and remains click-through.
    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, !contentView.isHidden else { return nil }
        // AppKit passes `point` in the receiver's superview coordinates. The
        // hosted view's hitTest in turn expects content-container coordinates.
        let localPoint = superview.map { convert(point, from: $0) } ?? point
        let containerPoint = contentContainer.convert(localPoint, from: self)
        guard contentView.frame.contains(containerPoint) else { return nil }
        return contentView.hitTest(containerPoint)
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
            setTorsoSolid(true)
        }
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
        let currentTransforms = presentationTransforms()
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
            setTorsoSolid(true)
        }
        for robotLayer in decorationLayers {
            let start = currentTransforms[ObjectIdentifier(robotLayer)] ?? CATransform3DIdentity
            let collapsed = sourcePoseTransform(for: robotLayer, sourceRect: sourceRect,
                                                pose: .brace, island: island)
            withoutActions { robotLayer.transform = collapsed }
            animateTransform(robotLayer, from: start, to: collapsed,
                             duration: Self.closeDuration, delay: 0,
                             timing: CAMediaTimingFunction(name: .easeIn),
                             key: "robotFrame.close")
        }

        let collapsedContent = bodySurfaceTransform(for: contentContainer.layer,
                                                    sourceRect: sourceRect,
                                                    pose: .brace, island: island)
        let collapsedOutline = bodySurfaceTransform(for: frameOutlineLayer,
                                                    sourceRect: sourceRect,
                                                    pose: .brace, island: island)
        let collapsedCenterSeam = bodySurfaceTransform(for: centerSeamLayer,
                                                       sourceRect: sourceRect,
                                                       pose: .brace, island: island)
        withoutActions {
            contentRevealMask.transform = CATransform3DIdentity
            contentContainer.layer?.transform = collapsedContent
            contentContainer.layer?.opacity = 0
            frameOutlineLayer.transform = collapsedOutline
            frameOutlineLayer.opacity = 0
            centerSeamLayer.transform = collapsedCenterSeam
            centerSeamLayer.opacity = 0
            transitionSeamLayer.transform = sourcePoseTransform(for: transitionSeamLayer,
                                                                 sourceRect: sourceRect,
                                                                 pose: .brace, island: island)
            transitionSeamLayer.opacity = 1
        }
        if let contentLayer = contentContainer.layer {
            animateTransform(contentLayer, from: currentContentTransform, to: collapsedContent,
                             duration: Self.closeDuration, delay: 0,
                             timing: CAMediaTimingFunction(name: .easeIn),
                             key: "robotFrame.content.close")
        }
        animateOpacity(contentContainer.layer, from: currentContentOpacity, to: 0,
                       duration: 0.24, delay: 0.08, key: "robotFrame.content.close")
        animateOpacity(frameOutlineLayer, from: currentOutlineOpacity, to: 0,
                       duration: 0.24, delay: 0, key: "robotFrame.outline.close")
        animateTransform(frameOutlineLayer, from: currentOutlineTransform, to: collapsedOutline,
                         duration: Self.closeDuration, delay: 0,
                         timing: CAMediaTimingFunction(name: .easeIn),
                         key: "robotFrame.outline.transform.close")
        animateOpacity(centerSeamLayer, from: currentCenterSeamOpacity, to: 0,
                       duration: 0.20, delay: 0, key: "robotFrame.seam.close")
        animateTransform(centerSeamLayer, from: currentCenterSeamTransform,
                         to: collapsedCenterSeam,
                         duration: Self.closeDuration, delay: 0,
                         timing: CAMediaTimingFunction(name: .easeIn),
                         key: "robotFrame.centerSeam.transform.close")
        animateTransform(transitionSeamLayer, from: currentTransitionSeamTransform,
                         to: transitionSeamLayer.transform,
                         duration: Self.closeDuration, delay: 0,
                         timing: CAMediaTimingFunction(name: .easeIn),
                         key: "robotFrame.splitSeam.close")
        animateOpacity(transitionSeamLayer, from: currentTransitionSeamOpacity, to: 1,
                       duration: 0.24, delay: 0.12, key: "robotFrame.splitSeam.opacity.close")

        finish(after: Self.closeDuration, generation: generation, open: false,
               completion: completion)
    }

    /// Called by the owning controller's existing pointer poll. This schedules
    /// no timer: it only eases the pupils to the latest clamped target and uses
    /// the same tick to trigger an occasional blink.
    public func updatePointer(screenPoint: CGPoint?, displayFrame: CGRect) {
        guard isFrameVisible || isTransitioning else { return }
        guard !reduceMotionActive else { resetEyes(); return }
        let eyeCenter = eyeCenterInScreen()
        let offset = RobotAppFrameGaze.offset(pointer: screenPoint,
                                              eyeCenter: eyeCenter,
                                              displayFrame: displayFrame)
        easePupil(leftPupilLayer, home: leftPupilHome, offset: offset)
        easePupil(rightPupilLayer, home: rightPupilHome, offset: offset)
        blinkIfNeeded(now: CACurrentMediaTime())
    }

    // MARK: - Configuration

    private func configureContent() {
        contentContainer.wantsLayer = true
        // BoardView owns the user's appearance and opacity. An opaque wrapper
        // would defeat those settings and a full purple backing would tint its
        // translucent material, so this host stays completely clear.
        contentContainer.layer?.backgroundColor = NSColor.clear.cgColor
        contentContainer.layer?.cornerRadius = 13
        contentContainer.layer?.masksToBounds = true
        contentContainer.layer?.zPosition = 10
        contentRevealMask.backgroundColor = NSColor.black.cgColor
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

        let shellColors = [Self.color(0xB89CCF), Self.color(0x765D94), Self.color(0x503E6E)]
        for torso in [leftTorsoLayer, rightTorsoLayer] {
            torso.colors = shellColors
            torso.locations = [0, 0.54, 1]
            torso.startPoint = CGPoint(x: 0.08, y: 0.9)
            torso.endPoint = CGPoint(x: 0.92, y: 0.05)
            torso.masksToBounds = true
            torso.zPosition = 1
            root.addSublayer(torso)
        }
        leftTorsoLayer.mask = leftTorsoMask
        rightTorsoLayer.mask = rightTorsoMask

        frameOutlineLayer.fillColor = nil
        frameOutlineLayer.strokeColor = Self.color(0x433451, alpha: 0.84)
        frameOutlineLayer.lineWidth = 1.25
        frameOutlineLayer.zPosition = 21
        root.addSublayer(frameOutlineLayer)

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

        for arm in [leftArmLayer, rightArmLayer] {
            arm.fillColor = nil
            arm.strokeColor = Self.color(0x59466E)
            arm.lineWidth = 4
            arm.lineCap = .round
            arm.lineJoin = .round
            arm.zPosition = 23
            root.addSublayer(arm)
        }

        configureLegs()
        legsLayer.zPosition = 23
        root.addSublayer(legsLayer)
    }

    private func configureHead() {
        headLayer.masksToBounds = false
        headShellLayer.colors = [Self.color(0xC9B5DA), Self.color(0x755B91), Self.color(0x4F3C69)]
        headShellLayer.locations = [0, 0.58, 1]
        headShellLayer.startPoint = CGPoint(x: 0.1, y: 0.9)
        headShellLayer.endPoint = CGPoint(x: 0.9, y: 0.1)
        headShellLayer.cornerRadius = 11
        headShellLayer.borderWidth = 1.2
        headShellLayer.borderColor = Self.color(0x433451)
        headLayer.addSublayer(headShellLayer)

        faceScreenLayer.fillColor = Self.color(0x292338)
        faceScreenLayer.strokeColor = Self.color(0xB49CC7)
        faceScreenLayer.lineWidth = 1
        headLayer.addSublayer(faceScreenLayer)

        configureEye(leftEyeLayer, pupil: leftPupilLayer)
        configureEye(rightEyeLayer, pupil: rightPupilLayer)
        headLayer.addSublayer(leftEyeLayer)
        headLayer.addSublayer(rightEyeLayer)

        mouthLayer.fillColor = nil
        mouthLayer.strokeColor = Self.color(0x96CEC9)
        mouthLayer.lineWidth = 1.1
        mouthLayer.lineCap = .round
        headLayer.addSublayer(mouthLayer)
    }

    private func configureEye(_ eye: CALayer, pupil: CAShapeLayer) {
        eye.backgroundColor = Self.color(0xD7F4EF)
        eye.cornerRadius = 3.5
        eye.shadowColor = Self.color(0xBCEBFF)
        eye.shadowOpacity = 0.26
        eye.shadowRadius = 2
        eye.shadowOffset = .zero
        eye.masksToBounds = false

        pupil.fillColor = Self.color(0x4B526E)
        pupil.shadowColor = Self.color(0xBCEBFF)
        pupil.shadowOpacity = 0.3
        pupil.shadowRadius = 1.5
        pupil.shadowOffset = .zero
        eye.addSublayer(pupil)
    }

    private func configureLegs() {
        legsLayer.masksToBounds = false
        for leg in [leftLegLayer, rightLegLayer] {
            leg.fillColor = nil
            leg.strokeColor = Self.color(0x59466E)
            leg.lineWidth = 4
            leg.lineCap = .round
            legsLayer.addSublayer(leg)
        }
        for foot in [leftFootLayer, rightFootLayer] {
            foot.fillColor = Self.color(0x4A3A62)
            foot.strokeColor = Self.color(0x392D4A)
            foot.lineWidth = 0.8
            legsLayer.addSublayer(foot)
        }
    }

    // MARK: - Layout

    private func layoutTorso() {
        let content = Self.contentRect(in: bounds)
        let torso = CGRect(x: bounds.minX + 2,
                           y: max(bounds.minY + 7, content.minY - 7),
                           width: max(0, bounds.width - 4),
                           height: max(0, content.height + 14))
        let split = torso.midX
        leftTorsoLayer.frame = CGRect(x: torso.minX, y: torso.minY,
                                     width: split - torso.minX + 0.5, height: torso.height)
        rightTorsoLayer.frame = CGRect(x: split - 0.5, y: torso.minY,
                                      width: torso.maxX - split + 0.5, height: torso.height)
        leftTorsoLayer.cornerRadius = 15
        rightTorsoLayer.cornerRadius = 15
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
        let visible = CGMutablePath()
        if contentInTorso.minX > torso.bounds.minX {
            visible.addRect(CGRect(x: torso.bounds.minX, y: torso.bounds.minY,
                                   width: contentInTorso.minX - torso.bounds.minX,
                                   height: torso.bounds.height))
        }
        if contentInTorso.maxX < torso.bounds.maxX {
            visible.addRect(CGRect(x: contentInTorso.maxX, y: torso.bounds.minY,
                                   width: torso.bounds.maxX - contentInTorso.maxX,
                                   height: torso.bounds.height))
        }
        if contentInTorso.minY > torso.bounds.minY {
            visible.addRect(CGRect(x: torso.bounds.minX, y: torso.bounds.minY,
                                   width: torso.bounds.width,
                                   height: contentInTorso.minY - torso.bounds.minY))
        }
        if contentInTorso.maxY < torso.bounds.maxY {
            visible.addRect(CGRect(x: torso.bounds.minX, y: contentInTorso.maxY,
                                   width: torso.bounds.width,
                                   height: torso.bounds.maxY - contentInTorso.maxY))
        }
        mask.path = visible
        mask.fillColor = NSColor.black.cgColor
    }

    private func layoutHead() {
        let width = min(78, max(54, bounds.width * 0.22))
        let height: CGFloat = 29
        let rect = CGRect(x: bounds.midX - width / 2,
                          y: bounds.maxY - height - 2,
                          width: width, height: height)
        headLayer.frame = rect
        headShellLayer.frame = headLayer.bounds
        faceScreenLayer.path = CGPath(roundedRect: headLayer.bounds.insetBy(dx: 8, dy: 5),
                                      cornerWidth: 7, cornerHeight: 7, transform: nil)

        let eyeY = headLayer.bounds.midY + 1
        let leftCenter = CGPoint(x: headLayer.bounds.midX - 11, y: eyeY)
        let rightCenter = CGPoint(x: headLayer.bounds.midX + 11, y: eyeY)
        leftEyeLayer.bounds = CGRect(x: 0, y: 0, width: 9, height: 7)
        rightEyeLayer.bounds = leftEyeLayer.bounds
        leftEyeLayer.position = leftCenter
        rightEyeLayer.position = rightCenter
        layoutPupil(leftPupilLayer, in: leftEyeLayer, home: &leftPupilHome)
        layoutPupil(rightPupilLayer, in: rightEyeLayer, home: &rightPupilHome)

        let mouth = CGMutablePath()
        mouth.move(to: CGPoint(x: headLayer.bounds.midX - 4, y: 7.5))
        mouth.addCurve(to: CGPoint(x: headLayer.bounds.midX + 4, y: 7.5),
                       control1: CGPoint(x: headLayer.bounds.midX - 2, y: 6),
                       control2: CGPoint(x: headLayer.bounds.midX + 2, y: 6))
        mouthLayer.path = mouth
    }

    private func layoutPupil(_ pupil: CAShapeLayer, in eye: CALayer, home: inout CGPoint) {
        let pupilBounds = CGRect(x: 0, y: 0, width: 3.2, height: 3.2)
        pupil.bounds = pupilBounds
        pupil.path = CGPath(ellipseIn: pupilBounds, transform: nil)
        home = CGPoint(x: eye.bounds.midX, y: eye.bounds.midY)
        if pupil.animation(forKey: "robotFrame.gaze") == nil { pupil.position = home }
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

        let right = CGMutablePath()
        right.move(to: CGPoint(x: content.maxX + 2, y: content.midY + 28))
        right.addCurve(to: CGPoint(x: min(bounds.maxX - 1, content.maxX + 7), y: content.midY - 22),
                       control1: CGPoint(x: content.maxX + 8, y: content.midY + 20),
                       control2: CGPoint(x: content.maxX + 9, y: content.midY - 13))
        rightArmLayer.path = right
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

        let right = CGMutablePath()
        right.move(to: CGPoint(x: rightX, y: Self.contentInsets.bottom - 2))
        right.addCurve(to: CGPoint(x: rightX + 2, y: 5),
                       control1: CGPoint(x: rightX - 2, y: 13),
                       control2: CGPoint(x: rightX + 3, y: 9))
        rightLegLayer.path = right

        leftFootLayer.path = CGPath(roundedRect: CGRect(x: leftX - 8, y: 2, width: 14, height: 6),
                                               cornerWidth: 2.5, cornerHeight: 2.5, transform: nil)
        rightFootLayer.path = CGPath(roundedRect: CGRect(x: rightX - 6, y: 2, width: 14, height: 6),
                                                cornerWidth: 2.5, cornerHeight: 2.5, transform: nil)
    }

    private func layoutOutlineAndSeam() {
        let content = Self.contentRect(in: bounds)
        frameOutlineLayer.frame = bounds
        frameOutlineLayer.path = CGPath(roundedRect: content.insetBy(dx: -0.75, dy: -0.75),
                                        cornerWidth: 13.75, cornerHeight: 13.75, transform: nil)
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
            return mappedTransform(for: target, feature: feature, destination: destination,
                                   scaleX: source.width * (climbing ? 0.47 : 0.55) /
                                       max(1, target.bounds.width),
                                   scaleY: source.height * (climbing ? 0.22 : 0.30) /
                                       max(1, target.bounds.height))

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
        leftTorsoLayer.mask = solid ? nil : leftTorsoMask
        rightTorsoLayer.mask = solid ? nil : rightTorsoMask
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

    private func easePupil(_ pupil: CALayer, home: CGPoint, offset: CGPoint) {
        let target = CGPoint(x: home.x + offset.x, y: home.y + offset.y)
        let start = pupil.presentation()?.position ?? pupil.position
        withoutActions { pupil.position = target }
        let animation = CABasicAnimation(keyPath: "position")
        animation.fromValue = NSValue(point: start)
        animation.toValue = NSValue(point: target)
        animation.duration = 0.16
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        pupil.add(animation, forKey: "robotFrame.gaze")
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
        for eye in [leftEyeLayer, rightEyeLayer] { eye.removeAllAnimations() }
        for (pupil, home) in [(leftPupilLayer, leftPupilHome),
                              (rightPupilLayer, rightPupilHome)] {
            pupil.removeAllAnimations()
            withoutActions { pupil.position = home }
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
