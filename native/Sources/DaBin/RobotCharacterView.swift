import AppKit
import QuartzCore

/// Small native character renderer used inside an existing interaction surface.
/// It owns no pasteboard or window behavior; callers send semantic motion events.
@MainActor
final class RobotCharacterView: NSView {
    typealias ReduceMotionProvider = () -> Bool

    private(set) var motionState = RobotMotionState()
    var mood: RobotMood { motionState.mood }
    var hasActiveAmbientMotion: Bool { ambientTask != nil }

    private let reduceMotionProvider: ReduceMotionProvider
    private var ambientTask: Task<Void, Never>?
    private var quietOrbitEnabled = true
    private var islandMotionActive = false
    private var islandResting = false
    private var islandStageEnabled = false
    private var islandCompletionTask: Task<Void, Never>?

    private let artLayer = CALayer()
    private let shadowLayer = CAShapeLayer()
    private let bodyLayer = CALayer()
    private let shellLayer = CALayer()
    private let feetLayer = CAShapeLayer()
    private let islandGripLayer = CAShapeLayer()
    // Stage-space hands keep their contact with the hardware edge while the
    // body rotates independently. Arm paths join those hands to moving shoulders.
    private let hangingArms = [CAShapeLayer(), CAShapeLayer()]
    private let hangingArmHighlights = [CAShapeLayer(), CAShapeLayer()]
    private let hangingHands = [CAShapeLayer(), CAShapeLayer()]
    private var islandRigLayers: [CALayer] { hangingArms + hangingArmHighlights + hangingHands }
    private let faceLayer = CALayer()
    private let faceScreenLayer = CAShapeLayer()
    private let leftEyeLayer = CAShapeLayer()
    private let rightEyeLayer = CAShapeLayer()
    private let mouthLayer = CAShapeLayer()
    private let lidLayer = CALayer()
    private let leftArmLayer = CAShapeLayer()
    private let rightArmLayer = CAShapeLayer()
    private let intakeLayer = CAShapeLayer()

    // Automatic captures use the same character, with a few small vector props.
    // These layers are deliberately local and transient: no image assets, sound,
    // or additional windows are involved in a celebration.
    private let autoTokenLayer = CALayer()
    private let autoCountLayer = CATextLayer()
    private let autoPropLayer = CAShapeLayer()
    private let autoPropDetailLayer = CAShapeLayer()
    private let autoSuccessBadgeLayer = CAShapeLayer()
    private let autoSuccessCheckLayer = CAShapeLayer()
    private let autoFlashLayer = CAShapeLayer()
    private let autoConfettiLayer = CALayer()
    private var autoConfettiPieces: [CAShapeLayer] = []

    private(set) var currentAutoCaptureReaction: AutoCaptureRobotReaction?
    private(set) var autoCaptureCelebrationStartCount = 0
    private(set) var autoCaptureTokenCount = 1

    private static let designSize = CGSize(width: 64, height: 78)
    /// The mechanical character is intentionally short; layout must use its
    /// visible artwork rather than treating the animation canvas as its body.
    static let quietOrbitArtworkBounds = CGRect(x: 5.96, y: 19.6, width: 56.7, height: 45.75)

    /// Quiet Orbit has no idle animation timer. Pointer gaze, capture feedback,
    /// and deliberate greeting tracks still use the existing event renderer.
    func configureQuietOrbit(_ enabled: Bool) {
        quietOrbitEnabled = enabled
        if enabled { stopAmbientMotion() }
        else { updateAmbientMotion(reduceMotion: reduceMotionProvider()) }
        configureAutomaticCountBadge()
    }

    init(frame frameRect: NSRect,
         reduceMotion: @escaping ReduceMotionProvider = {
             NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
         }) {
        reduceMotionProvider = reduceMotion
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = false
        configureLayers()
        applyHiddenPose()
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateLayerContentsScale()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateLayerContentsScale()
    }

    private func updateLayerContentsScale() {
        let backing = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let artScale = max(1, artworkScale)
        let scale = backing * artScale
        func apply(_ layer: CALayer) {
            layer.contentsScale = scale
            if let mask = layer.mask { apply(mask) }
            for child in layer.sublayers ?? [] { apply(child) }
        }
        if let layer { apply(layer) }
    }

    func configureIslandStage(_ enabled: Bool) {
        guard islandStageEnabled != enabled else { return }
        islandStageEnabled = enabled
        layer?.masksToBounds = enabled
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    private var artworkScale: CGFloat {
        islandStageEnabled
            ? min(1.35, bounds.height / 112, bounds.width / 174)
            : min(bounds.width / Self.designSize.width, bounds.height / Self.designSize.height)
    }

    override func layout() {
        super.layout()
        updateLayerContentsScale()
        let scale = artworkScale
        withoutActions {
            artLayer.bounds = CGRect(origin: .zero, size: Self.designSize)
            artLayer.position = CGPoint(x: bounds.midX,
                                        y: islandStageEnabled ? bounds.maxY - Self.designSize.height * scale / 2 : bounds.midY)
            artLayer.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        }
    }

    func send(_ event: RobotMotionEvent) {
        // Pointer entry commonly happens before the climb has finished. Retain
        // its latest gaze without replacing the coherent entrance layer tracks.
        // A drag, save, hide or opening still interrupts immediately.
        if islandMotionActive, case .hover = event {
            motionState.send(event)
            if islandResting { updateIslandGaze() }
            return
        }
        cancelIslandCompletion()
        if currentAutoCaptureReaction != nil || islandMotionActive {
            removeAllAnimations()
            resetAutomaticCelebrationLayers()
        }
        currentAutoCaptureReaction = nil
        islandMotionActive = false
        islandResting = false
        let previous = motionState
        let previousMood = previous.mood
        motionState.send(event)
        let nextMood = motionState.mood
        let reduceMotion = reduceMotionProvider()

        if nextMood == .hidden {
            stopAmbientMotion()
            removeAllAnimations()
            applyHiddenPose()
            return
        }

        if case .reveal(let entrance) = event,
           previousMood == .hidden || previous.entrance != entrance {
            animateReveal(from: entrance, reduceMotion: reduceMotion)
        } else {
            applyMood(nextMood, previous: previousMood, event: event, reduceMotion: reduceMotion)
        }
        updateAmbientMotion(reduceMotion: reduceMotion)
    }

    /// Re-evaluates the injected macOS preference without changing the semantic state.
    func refreshMotionPreference() {
        // An automatic performance samples Reduce Motion once when it begins.
        // Do not replace its coherent timeline with the generic mood renderer.
        guard currentAutoCaptureReaction == nil else { return }
        let reduceMotion = reduceMotionProvider()
        if islandMotionActive && !reduceMotion { return }
        if reduceMotion {
            cancelIslandCompletion()
            islandMotionActive = false
            stopAmbientMotion()
            removeAllAnimations()
            resetAutomaticCelebrationLayers()
        }
        guard mood != .hidden else { applyHiddenPose(); return }
        applyMood(mood, previous: mood, event: nil, reduceMotion: reduceMotion)
        updateAmbientMotion(reduceMotion: reduceMotion)
    }

    /// One-way visual cleanup for panel hiding and application shutdown.
    func stopMotion() {
        cancelIslandCompletion()
        currentAutoCaptureReaction = nil
        islandMotionActive = false
        motionState.send(.hide)
        stopAmbientMotion()
        removeAllAnimations()
        resetAutomaticCelebrationLayers()
        applyHiddenPose()
    }

    // MARK: - Layer construction

    private func configureLayers() {
        guard let root = layer else { return }
        let designBounds = CGRect(origin: .zero, size: Self.designSize)
        artLayer.bounds = designBounds
        artLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        artLayer.isGeometryFlipped = true
        artLayer.masksToBounds = false
        root.addSublayer(artLayer)

        configureContainer(bodyLayer, anchor: CGPoint(x: 32, y: 69))
        artLayer.addSublayer(shadowLayer)
        artLayer.addSublayer(bodyLayer)

        islandGripLayer.path = Self.islandGripPath()
        islandGripLayer.fillColor = Self.color(0xB99CCF)
        islandGripLayer.strokeColor = Self.color(0x483556)
        islandGripLayer.lineWidth = 1
        islandGripLayer.opacity = 0
        artLayer.addSublayer(islandGripLayer)

        configureShadow()
        configureContainer(leftArmLayer, anchor: orbitPoint(153, 106))
        configureContainer(rightArmLayer, anchor: orbitPoint(247, 106))
        configureContainer(shellLayer, anchor: CGPoint(x: 32, y: 66))
        configureContainer(faceLayer, anchor: CGPoint(x: 32, y: 40))
        configureContainer(intakeLayer, anchor: CGPoint(x: 32, y: 17))
        configureContainer(lidLayer, anchor: CGPoint(x: 32, y: 23))

        bodyLayer.addSublayer(leftArmLayer)
        bodyLayer.addSublayer(rightArmLayer)
        bodyLayer.addSublayer(shellLayer)
        bodyLayer.addSublayer(faceLayer)
        bodyLayer.addSublayer(intakeLayer)
        bodyLayer.addSublayer(lidLayer)

        configureArms()
        configureShell()
        configureFace()
        configureIntakeCard()
        configureLid()
        configureAutomaticCelebrationLayers()
        configureIslandRig()
    }

    private func configureContainer(_ layer: CALayer, anchor: CGPoint) {
        layer.bounds = CGRect(origin: .zero, size: Self.designSize)
        layer.anchorPoint = CGPoint(x: anchor.x / Self.designSize.width,
                                    y: anchor.y / Self.designSize.height)
        layer.position = anchor
        layer.masksToBounds = false
    }

    private func configureShadow() {
        shadowLayer.path = CGPath(ellipseIn: CGRect(x: 14, y: 71.5, width: 36, height: 5), transform: nil)
        shadowLayer.fillColor = Self.color(0x261E32, alpha: 1)
        shadowLayer.opacity = 0.18
    }

    // MARK: Quiet Orbit artwork

    // These points preserve the supplied SVG geometry while retaining the
    // 64×78 animation canvas, so existing reaction tracks remain reusable.
    private let orbitUnit: CGFloat = 0.42
    private func orbitPoint(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: 32 + (x - 200) * orbitUnit, y: 20 + (y - 57) * orbitUnit)
    }
    private func orbitRect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
        CGRect(origin: orbitPoint(x, y), size: CGSize(width: width * orbitUnit, height: height * orbitUnit))
    }
    private func orbitPolygon(_ points: [(CGFloat, CGFloat)], close: Bool = true) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: orbitPoint(first.0, first.1))
        for point in points.dropFirst() { path.addLine(to: orbitPoint(point.0, point.1)) }
        if close { path.closeSubpath() }
        return path
    }
    private func orbitRoundRect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat,
                                radius: CGFloat) -> CGPath {
        CGPath(roundedRect: orbitRect(x, y, width, height), cornerWidth: radius * orbitUnit,
               cornerHeight: radius * orbitUnit, transform: nil)
    }
    private var orbitMetal: [UInt32] { [0xEEE7F4, 0xC8B4DC, 0x977CAD, 0xBCA5D0, 0x6D5387] }
    private var orbitSilver: [UInt32] { [0xF6F4F8, 0xD4CDDC, 0xA9A1B3, 0xE3DCE9, 0x85758F] }

    @discardableResult
    private func addOrbitGradient(_ path: CGPath, colors: [UInt32], to parent: CALayer,
                                  stroke: CGFloat? = nil) -> CAGradientLayer {
        let mask = CAShapeLayer()
        mask.path = path
        if let stroke {
            mask.fillColor = nil
            mask.strokeColor = Self.color(0xFFFFFF)
            mask.lineWidth = stroke
            mask.lineJoin = .round
            mask.lineCap = .round
        }
        let gradient = CAGradientLayer()
        gradient.frame = CGRect(origin: .zero, size: Self.designSize)
        gradient.colors = colors.map { Self.color($0) }
        gradient.locations = colors.indices.map { NSNumber(value: Double($0) / Double(max(1, colors.count - 1))) }
        let bounds = path.boundingBoxOfPath
        gradient.startPoint = CGPoint(x: bounds.minX / Self.designSize.width, y: bounds.minY / Self.designSize.height)
        gradient.endPoint = CGPoint(x: bounds.maxX / Self.designSize.width, y: bounds.maxY / Self.designSize.height)
        gradient.mask = mask
        parent.addSublayer(gradient)
        return gradient
    }

    @discardableResult
    private func addOrbitShape(_ path: CGPath, to parent: CALayer, fill: UInt32? = nil,
                               stroke: UInt32? = nil, width: CGFloat = 1, alpha: CGFloat = 1) -> CAShapeLayer {
        let shape = CAShapeLayer()
        shape.path = path
        shape.fillColor = fill.map { Self.color($0, alpha: alpha) }
        shape.strokeColor = stroke.map { Self.color($0, alpha: alpha) }
        shape.lineWidth = width
        shape.lineJoin = .round
        shape.lineCap = .round
        parent.addSublayer(shape)
        return shape
    }

    private func configureArms() {
        configureOrbitArm(leftArmLayer, shoulder: (153, 106), elbow: (151, 90), hand: (151, 66),
                          handOrigin: (139, 57))
        configureOrbitArm(rightArmLayer, shoulder: (247, 106), elbow: (264, 113), hand: (259, 138),
                          handOrigin: (247, 133))
    }

    private func configureOrbitArm(_ arm: CAShapeLayer, shoulder: (CGFloat, CGFloat),
                                   elbow: (CGFloat, CGFloat), hand: (CGFloat, CGFloat),
                                   handOrigin: (CGFloat, CGFloat)) {
        let path = orbitPolygon([shoulder, elbow, hand], close: false)
        arm.path = path
        arm.fillColor = nil
        arm.strokeColor = Self.color(0x554760)
        arm.lineWidth = 11 * orbitUnit
        arm.lineJoin = .round
        arm.lineCap = .round
        addOrbitGradient(path, colors: orbitSilver, to: arm, stroke: 7 * orbitUnit)
        let joint = CGPath(ellipseIn: orbitRect(elbow.0 - 7, elbow.1 - 7, 14, 14), transform: nil)
        addOrbitGradient(joint, colors: orbitMetal, to: arm)
        addOrbitShape(joint, to: arm, stroke: 0x655373, width: orbitUnit)
        addOrbitShape(orbitPolygon([(elbow.0 - 3, elbow.1), (elbow.0 + 3, elbow.1)], close: false),
                      to: arm, stroke: 0x544260, width: 2 * orbitUnit)
        let palm = orbitRoundRect(handOrigin.0, handOrigin.1, 25, 18, radius: 5)
        addOrbitGradient(palm, colors: orbitSilver, to: arm)
        addOrbitShape(palm, to: arm, stroke: 0x766285, width: orbitUnit)
        let fingers = CGMutablePath()
        for offset: CGFloat in [6, 12, 18] {
            fingers.move(to: orbitPoint(handOrigin.0 + offset, handOrigin.1 + 1))
            fingers.addLine(to: orbitPoint(handOrigin.0 + offset, handOrigin.1 + 10))
        }
        addOrbitShape(fingers, to: arm, stroke: 0x776487, width: 1.2 * orbitUnit)
        addOrbitShape(orbitPolygon([(handOrigin.0 + 4, handOrigin.1 + 15),
                                   (handOrigin.0 + 21, handOrigin.1 + 15)], close: false),
                      to: arm, stroke: 0xF3EDF7, width: orbitUnit)
        let servo = CGPath(ellipseIn: orbitRect(shoulder.0 - 8, shoulder.1 - 8, 16, 16), transform: nil)
        addOrbitGradient(servo, colors: orbitSilver, to: arm)
        addOrbitShape(servo, to: arm, stroke: 0x766285, width: orbitUnit)
        addOrbitShape(CGPath(ellipseIn: orbitRect(shoulder.0 - 3, shoulder.1 - 3, 6, 6), transform: nil),
                      to: arm, fill: 0x554760)
    }

    private func configureShell() {
        let neck = orbitRoundRect(187, 117, 26, 18, radius: 1)
        addOrbitShape(neck, to: shellLayer, fill: 0x554760, stroke: 0x9986AA, width: orbitUnit)
        let neckRibs = CGMutablePath()
        for y: CGFloat in [122, 127] {
            neckRibs.move(to: orbitPoint(188, y)); neckRibs.addLine(to: orbitPoint(212, y))
        }
        addOrbitShape(neckRibs, to: shellLayer, stroke: 0xC4B7D0, width: 2 * orbitUnit)

        let feetPath = CGMutablePath()
        feetPath.addPath(orbitRoundRect(170, 155, 19, 9, radius: 3))
        feetPath.addPath(orbitRoundRect(211, 155, 19, 9, radius: 3))
        feetLayer.path = feetPath
        feetLayer.fillColor = Self.color(0xD4CDDC)
        feetLayer.strokeColor = Self.color(0x766285)
        feetLayer.lineWidth = orbitUnit
        shellLayer.addSublayer(feetLayer)
        addOrbitGradient(feetPath, colors: orbitSilver, to: feetLayer)

        let torso = orbitPolygon([(176, 129), (224, 129), (234, 138), (229, 159), (171, 159), (166, 138)])
        addOrbitGradient(torso, colors: orbitMetal, to: shellLayer)
        addOrbitShape(torso, to: shellLayer, stroke: 0x7A628D, width: orbitUnit)
        addOrbitShape(orbitPolygon([(176, 132), (224, 132)], close: false), to: shellLayer,
                      stroke: 0xEEE5F5, width: 1.5 * orbitUnit)
        addOrbitShape(orbitRoundRect(183, 140, 34, 10, radius: 2), to: shellLayer,
                      fill: 0x282230, stroke: 0x8E7A9F, width: orbitUnit)
        addOrbitShape(orbitPolygon([(187, 148), (213, 148)], close: false), to: shellLayer,
                      stroke: 0xB3E6D9, width: 1.5 * orbitUnit)
        let screws = CGMutablePath()
        for x: CGFloat in [175, 221] {
            screws.move(to: orbitPoint(x, 152)); screws.addLine(to: orbitPoint(x + 4, 152))
        }
        addOrbitShape(screws, to: shellLayer, stroke: 0x544260, width: 1.5 * orbitUnit)
    }

    private func configureFace() {
        let head = orbitPolygon([(166, 57), (234, 57), (250, 71), (250, 112),
                                 (237, 125), (163, 125), (150, 112), (150, 71)])
        addOrbitGradient(head, colors: orbitMetal, to: faceLayer)
        addOrbitShape(head, to: faceLayer, stroke: 0x7D6490, width: 1.2 * orbitUnit)
        addOrbitShape(orbitPolygon([(158, 73), (169, 63), (231, 63), (242, 73)], close: false),
                      to: faceLayer, stroke: 0xF2EAF9, width: 2 * orbitUnit)
        let visor = orbitPolygon([(164, 75), (236, 75), (242, 82), (242, 107),
                                  (234, 116), (166, 116), (158, 107), (158, 82)])
        faceScreenLayer.path = visor
        faceScreenLayer.fillColor = Self.color(0x1E1924)
        faceScreenLayer.strokeColor = Self.color(0x8D759F)
        faceScreenLayer.lineWidth = orbitUnit
        faceLayer.addSublayer(faceScreenLayer)
        addOrbitGradient(visor, colors: [0x3E3449, 0x1E1924, 0x30253B], to: faceScreenLayer)
        addOrbitShape(orbitPolygon([(169, 80), (229, 80)], close: false), to: faceLayer,
                      stroke: 0xDFD2EA, width: 1.4 * orbitUnit, alpha: 0.18)

        for (eye, origin) in [(leftEyeLayer, CGPoint(x: 174, y: 88)),
                              (rightEyeLayer, CGPoint(x: 213, y: 88))] {
            let center = orbitPoint(origin.x + 6.5, origin.y + 7.5)
            configureContainer(eye, anchor: center)
            eye.path = CGPath(rect: orbitRect(origin.x, origin.y, 13, 15), transform: nil)
            eye.fillColor = Self.color(0xC8F1E5)
            eye.shadowColor = Self.color(0xB3E6D9)
            eye.shadowOpacity = 0.16
            eye.shadowRadius = 0.8
            eye.shadowOffset = .zero
            let scanlines = CGMutablePath()
            for offset: CGFloat in [4, 8, 12] {
                scanlines.move(to: orbitPoint(origin.x + 2, origin.y + offset))
                scanlines.addLine(to: orbitPoint(origin.x + 11, origin.y + offset))
            }
            addOrbitShape(scanlines, to: eye, stroke: 0x233B35, width: 0.8 * orbitUnit, alpha: 0.18)
            faceLayer.addSublayer(eye)
        }
        mouthLayer.path = mouthPath(for: .idle)
        mouthLayer.fillColor = nil
        mouthLayer.strokeColor = Self.color(0xA3C7BD)
        mouthLayer.lineWidth = 1.8 * orbitUnit
        mouthLayer.lineCap = .square
        mouthLayer.lineJoin = .round
        faceLayer.addSublayer(mouthLayer)

        addOrbitShape(orbitRoundRect(192, 66, 16, 3, radius: 1), to: faceLayer, fill: 0x5B486A)
        addOrbitShape(orbitPolygon([(195, 67.5), (202, 67.5)], close: false), to: faceLayer,
                      stroke: 0xC8F1E5, width: 1.2 * orbitUnit)
        let seams = CGMutablePath()
        for x: CGFloat in [155, 245] {
            seams.move(to: orbitPoint(x, 84)); seams.addLine(to: orbitPoint(x, 101))
        }
        for x: CGFloat in [165, 232] {
            seams.move(to: orbitPoint(x, 119)); seams.addLine(to: orbitPoint(x + 3, 119))
        }
        addOrbitShape(seams, to: faceLayer, stroke: 0x584664, width: 1.5 * orbitUnit)
    }

    private func configureIntakeCard() {
        // A generic paper icon passes into the physical torso slot. It never
        // carries the user's clipboard text or screenshot pixels.
        intakeLayer.path = CGPath(roundedRect: CGRect(x: 28, y: 39, width: 8, height: 11),
                                  cornerWidth: 0.8, cornerHeight: 0.8, transform: nil)
        intakeLayer.fillColor = Self.color(0xFBF7FF)
        intakeLayer.strokeColor = Self.color(0x8E7AA7)
        intakeLayer.lineWidth = 0.8
        intakeLayer.opacity = 0
    }

    private func configureLid() {
        // The original bin-lid animation layer remains for compatibility with
        // existing motion descriptors. Quiet Orbit's head is a complete,
        // separate mechanical assembly in faceLayer; it has no floating lid.
    }

    private func configureAutomaticCelebrationLayers() {
        // A mouth-anchored token makes every scale/fold end inside the face.
        // The token contains only vector strokes; private captures never enter it.
        autoTokenLayer.position = CGPoint(x: 32, y: 42)
        artLayer.addSublayer(autoTokenLayer)
        configureAutomaticCountBadge()
        autoCountLayer.alignmentMode = .center
        autoCountLayer.foregroundColor = Self.color(0xFFFFFF)
        autoCountLayer.backgroundColor = Self.color(0x51346F)
        autoCountLayer.cornerRadius = 4
        autoCountLayer.contentsScale = 2
        autoCountLayer.isHidden = true
        for prop in [autoPropLayer, autoPropDetailLayer] {
            prop.strokeColor = Self.color(0x4A385A)
            prop.lineWidth = 1.1
            prop.lineJoin = .round
            prop.lineCap = .round
            prop.opacity = 0
            autoTokenLayer.addSublayer(prop)
        }
        autoPropLayer.fillColor = Self.color(0xF8F2FC)
        autoPropDetailLayer.fillColor = nil
        autoTokenLayer.addSublayer(autoCountLayer)

        autoSuccessBadgeLayer.path = CGPath(ellipseIn: CGRect(x: 45, y: 5, width: 14, height: 14), transform: nil)
        autoSuccessBadgeLayer.fillColor = Self.color(0x5C4275, alpha: 0.98)
        autoSuccessBadgeLayer.strokeColor = Self.color(0xF7F1FC, alpha: 0.92)
        autoSuccessBadgeLayer.lineWidth = 1
        autoSuccessBadgeLayer.shadowColor = Self.color(0x241B2D)
        autoSuccessBadgeLayer.shadowOpacity = 0.22
        autoSuccessBadgeLayer.shadowRadius = 2
        autoSuccessBadgeLayer.shadowOffset = CGSize(width: 0, height: 1)
        autoSuccessBadgeLayer.opacity = 0
        artLayer.addSublayer(autoSuccessBadgeLayer)

        let check = CGMutablePath()
        check.move(to: CGPoint(x: 49, y: 12))
        check.addLine(to: CGPoint(x: 52.2, y: 15))
        check.addLine(to: CGPoint(x: 56.5, y: 9))
        autoSuccessCheckLayer.path = check
        autoSuccessCheckLayer.fillColor = nil
        autoSuccessCheckLayer.strokeColor = Self.color(0xFFFFFF)
        autoSuccessCheckLayer.lineWidth = 1.7
        autoSuccessCheckLayer.lineCap = .round
        autoSuccessCheckLayer.lineJoin = .round
        autoSuccessCheckLayer.opacity = 0
        artLayer.addSublayer(autoSuccessCheckLayer)

        let flash = CGMutablePath()
        let center = CGPoint(x: 32, y: 29)
        for angle in stride(from: CGFloat.zero, to: CGFloat.pi * 2, by: CGFloat.pi / 4) {
            let start = CGPoint(x: center.x + cos(angle) * 7, y: center.y + sin(angle) * 7)
            let end = CGPoint(x: center.x + cos(angle) * 13, y: center.y + sin(angle) * 13)
            flash.move(to: start)
            flash.addLine(to: end)
        }
        autoFlashLayer.path = flash
        autoFlashLayer.fillColor = nil
        autoFlashLayer.strokeColor = Self.color(0xFFF4B5)
        autoFlashLayer.lineWidth = 1.8
        autoFlashLayer.lineCap = .round
        autoFlashLayer.opacity = 0
        artLayer.addSublayer(autoFlashLayer)

        autoConfettiLayer.frame = CGRect(origin: .zero, size: Self.designSize)
        autoConfettiLayer.opacity = 0
        artLayer.addSublayer(autoConfettiLayer)
        let colors = [Self.color(0xD7F4EF), Self.color(0xC9A9DD), Self.color(0xFFD773)]
        let points = [CGPoint(x: 22, y: 25), CGPoint(x: 28, y: 21), CGPoint(x: 35, y: 23),
                      CGPoint(x: 42, y: 26), CGPoint(x: 25, y: 31), CGPoint(x: 39, y: 32)]
        for (index, point) in points.enumerated() {
            let piece = CAShapeLayer()
            piece.path = index.isMultiple(of: 2)
                ? CGPath(ellipseIn: CGRect(x: point.x - 1.2, y: point.y - 1.2, width: 2.4, height: 2.4), transform: nil)
                : CGPath(roundedRect: CGRect(x: point.x - 0.8, y: point.y - 2, width: 1.6, height: 4),
                         cornerWidth: 0.6, cornerHeight: 0.6, transform: nil)
            piece.fillColor = colors[index % colors.count]
            autoConfettiLayer.addSublayer(piece)
            autoConfettiPieces.append(piece)
        }
    }

    private func configureAutomaticCountBadge() {
        // The count stays readable even when the companion itself is tiny.
        // Keep it in the same transient token rather than adding another popup.
        let fontSize: CGFloat = quietOrbitEnabled ? 14 : 7
        autoCountLayer.frame = quietOrbitEnabled
            ? CGRect(x: -24, y: -27, width: 48, height: 19)
            : CGRect(x: -13, y: -19, width: 26, height: 10)
        autoCountLayer.font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold)
        autoCountLayer.fontSize = fontSize
    }

    // MARK: - Automatic capture celebration

    /// Plays one complete automatic-capture performance. The presenter owns the
    /// panel lifetime; this view owns a single synchronized Core Animation
    /// timeline, so entrance, reaction and retreat never compete for a layer.
    func playAutoCaptureCelebration(_ performance: AutoCaptureRobotPerformance) {
        cancelIslandCompletion()
        islandMotionActive = false
        configureIslandStage(performance.entrance == .top && !quietOrbitEnabled)
        stopAmbientMotion()
        removeAllAnimations()
        resetAutomaticCelebrationLayers()

        motionState.send(.hide)
        motionState.send(.reveal(performance.entrance))
        motionState.send(.result(.success))
        currentAutoCaptureReaction = performance.reaction
        autoCaptureCelebrationStartCount += 1

        autoCaptureTokenCount = 1
        configureAutomaticProp(for: performance.reaction)
        withoutActions {
            artLayer.opacity = 1
            artLayer.masksToBounds = false
            mouthLayer.path = automaticMouthPath(for: performance.reaction)
        }

        if performance.reduceMotion {
            playReducedMotionAutoCaptureCelebration(performance)
        } else {
            playFullAutoCaptureCelebration(performance)
        }
    }

    private struct AutomaticPoseFrame {
        let time: TimeInterval
        let pose: RobotPartTransform
    }

    private struct AutomaticOpacityFrame {
        let time: TimeInterval
        let opacity: Float
    }

    private func playFullAutoCaptureCelebration(_ performance: AutoCaptureRobotPerformance) {
        guard performance.totalDuration > 0,
              let anticipation = phase(.anticipation, in: performance),
              let entrance = phase(.entrance, in: performance),
              let eating = phase(.eating(performance.reaction), in: performance),
              let reaction = reactionPhase(in: performance),
              let exit = phase(.exit, in: performance) else { return }

        if performance.entrance == .top && !quietOrbitEnabled {
            prepareIslandRig()
            animateIslandFrames(IslandRobotChoreography.capture(performance), duration: performance.totalDuration)
            addAutomaticPropTimeline(reaction: performance.reaction, phase: eating,
                                     totalDuration: performance.totalDuration, performance: performance)
            addAutomaticMouthTimeline(eating: eating, reaction: reaction, performance: performance)
            addAutomaticSuccessBadgeTimeline(reaction: reaction, exit: exit, performance: performance)
            return
        }

        if quietOrbitEnabled {
            // The native panel controls which notch perch is visible. Local
            // character travel stays small; opacity cleanly tucks the sprite
            // away without a second stage-space climbing rig.
            addAutomaticOpacityTrack([
                AutomaticOpacityFrame(time: 0, opacity: 0),
                AutomaticOpacityFrame(time: phaseTime(anticipation, 0.34), opacity: 1),
                AutomaticOpacityFrame(time: reaction.endTime, opacity: 1),
                AutomaticOpacityFrame(time: exit.endTime, opacity: 0)
            ], to: artLayer, key: "robot.auto-success.orbit-visibility", performance: performance)
        }
        let hidden = automaticHiddenPose(for: performance.entrance)
        let peek = automaticPeekPose(for: performance.entrance,
                                     offset: CGFloat(performance.variation.entranceOffset))
        let compressed = automaticCompressedEntrancePose(for: performance.entrance,
                                                          offset: CGFloat(performance.variation.entranceOffset))
        let overshoot = automaticEntranceOvershoot(for: performance.entrance,
                                                   offset: CGFloat(performance.variation.entranceOffset))

        var bodyFrames = [
            AutomaticPoseFrame(time: 0, pose: hidden),
            AutomaticPoseFrame(time: phaseTime(anticipation, 0.34), pose: peek),
            AutomaticPoseFrame(time: anticipation.endTime, pose: peek),
            AutomaticPoseFrame(time: phaseTime(entrance, 0.20), pose: compressed),
            AutomaticPoseFrame(time: phaseTime(entrance, 0.76), pose: overshoot),
            AutomaticPoseFrame(time: entrance.endTime, pose: .identity)
        ]
        bodyFrames.append(contentsOf: automaticEatingBodyFrames(performance.reaction.eatingStyle,
                                                                phase: eating))
        bodyFrames.append(contentsOf: automaticReactionBodyFrames(performance.reaction,
                                                                   phase: reaction,
                                                                   entrance: performance.entrance))
        bodyFrames.append(contentsOf: [
            AutomaticPoseFrame(time: reaction.endTime, pose: .identity),
            AutomaticPoseFrame(time: phaseTime(exit, 0.24),
                               pose: RobotPartTransform(translation: CGPoint(x: 0, y: 1.2),
                                                        scaleX: 1.06, scaleY: 0.91)),
            AutomaticPoseFrame(time: phaseTime(exit, 0.46),
                               pose: RobotPartTransform(translation: CGPoint(x: 0, y: -2.0),
                                                        scaleX: 0.97, scaleY: 1.05)),
            AutomaticPoseFrame(time: phaseTime(exit, 0.67), pose: compressed),
            AutomaticPoseFrame(time: exit.endTime, pose: hidden)
        ])
        addAutomaticTransformTrack(bodyFrames, to: bodyLayer, key: "robot.auto-success.body",
                                   performance: performance)

        addAutomaticTransformTrack(automaticArmFrames(reaction: performance.reaction,
                                                       phase: eating, left: true,
                                                       totalDuration: performance.totalDuration),
                                   to: leftArmLayer, key: "robot.auto-success.left-arm",
                                   performance: performance)
        addAutomaticTransformTrack(automaticArmFrames(reaction: performance.reaction,
                                                       phase: eating, left: false,
                                                       totalDuration: performance.totalDuration),
                                   to: rightArmLayer, key: "robot.auto-success.right-arm",
                                   performance: performance)

        let gaze = CGFloat(performance.variation.gazeX) * 4
        let eyeTracks = automaticEyeFrames(reaction: performance.reaction, phase: eating,
                                           anticipation: anticipation, entrance: entrance,
                                           totalDuration: performance.totalDuration, gaze: gaze)
        addAutomaticTransformTrack(eyeTracks.left, to: leftEyeLayer,
                                   key: "robot.auto-success.left-eye", performance: performance)
        addAutomaticTransformTrack(eyeTracks.right, to: rightEyeLayer,
                                   key: "robot.auto-success.right-eye", performance: performance)

        addAutomaticShadowTimeline(anticipation: anticipation, entrance: entrance,
                                   reaction: reaction, exit: exit, performance: performance)
        addAutomaticSuccessBadgeTimeline(reaction: reaction, exit: exit, performance: performance)
        addAutomaticPropTimeline(reaction: performance.reaction, phase: eating,
                                 totalDuration: performance.totalDuration, performance: performance)
        addAutomaticMouthTimeline(eating: eating, reaction: reaction, performance: performance)
        if performance.entrance == .top && !quietOrbitEnabled {
            addIslandClimbingDetails(anticipation: anticipation, entrance: entrance,
                                    exit: exit, performance: performance)
        }
    }

    private func playReducedMotionAutoCaptureCelebration(_ performance: AutoCaptureRobotPerformance) {
        guard performance.totalDuration > 0,
              let peek = phase(.reducedPeek, in: performance),
              let check = phase(.successCheck, in: performance),
              let fade = phase(.fade, in: performance) else { return }

        // This is a static cropped peek. Only opacity changes; the body never
        // travels, rotates, spins, scales, bounces or schedules ambient work.
        let staticPeek: RobotPartTransform
        switch performance.entrance {
        case _ where quietOrbitEnabled: staticPeek = .identity
        case .top: staticPeek = RobotPartTransform(translation: CGPoint(x: 0, y: -18))
        case .right: staticPeek = RobotPartTransform(translation: CGPoint(x: 12, y: 0))
        case .left: staticPeek = RobotPartTransform(translation: CGPoint(x: -12, y: 0))
        }
        withoutActions {
            bodyLayer.transform = transform(staticPeek)
            leftEyeLayer.transform = CATransform3DIdentity
            rightEyeLayer.transform = CATransform3DIdentity
            shadowLayer.opacity = 0
            artLayer.opacity = 0
        }
        addAutomaticOpacityTrack([
            AutomaticOpacityFrame(time: 0, opacity: 0),
            AutomaticOpacityFrame(time: peek.endTime, opacity: 1),
            AutomaticOpacityFrame(time: check.endTime, opacity: 1),
            AutomaticOpacityFrame(time: fade.endTime, opacity: 0)
        ], to: artLayer, key: "robot.auto-success.reduced-fade", performance: performance)
        let badge = [
            AutomaticOpacityFrame(time: 0, opacity: 0),
            AutomaticOpacityFrame(time: check.startTime, opacity: 0),
            AutomaticOpacityFrame(time: phaseTime(check, 0.20), opacity: 1),
            AutomaticOpacityFrame(time: check.endTime, opacity: 1),
            AutomaticOpacityFrame(time: fade.endTime, opacity: 0)
        ]
        addAutomaticOpacityTrack(badge, to: autoSuccessBadgeLayer,
                                 key: "robot.auto-success.reduced-badge", performance: performance)
        addAutomaticOpacityTrack(badge, to: autoSuccessCheckLayer,
                                 key: "robot.auto-success.reduced-check", performance: performance)
    }

    private func automaticHiddenPose(for entrance: RobotEntrance) -> RobotPartTransform {
        if quietOrbitEnabled {
            switch entrance {
            case .top: return RobotPartTransform(translation: CGPoint(x: 0, y: -12))
            case .right: return RobotPartTransform(translation: CGPoint(x: 12, y: 0))
            case .left: return RobotPartTransform(translation: CGPoint(x: -12, y: 0))
            }
        }
        switch entrance {
        case .top: return RobotPartTransform(translation: CGPoint(x: 0, y: -92))
        case .right: return RobotPartTransform(translation: CGPoint(x: 84, y: 0), rotationDegrees: 7)
        case .left: return RobotPartTransform(translation: CGPoint(x: -84, y: 0), rotationDegrees: -7)
        }
    }

    private func automaticPeekPose(for entrance: RobotEntrance, offset: CGFloat) -> RobotPartTransform {
        if quietOrbitEnabled {
            switch entrance {
            case .top: return RobotPartTransform(translation: CGPoint(x: offset * 0.4, y: -5))
            case .right: return RobotPartTransform(translation: CGPoint(x: 5, y: offset * 0.4))
            case .left: return RobotPartTransform(translation: CGPoint(x: -5, y: offset * 0.4))
            }
        }
        switch entrance {
        case .top:
            return RobotPartTransform(translation: CGPoint(x: offset, y: -37),
                                      scaleX: 1.01, scaleY: 0.99, rotationDegrees: offset * 0.7)
        case .right:
            return RobotPartTransform(translation: CGPoint(x: 52, y: offset), rotationDegrees: 7)
        case .left:
            return RobotPartTransform(translation: CGPoint(x: -52, y: offset), rotationDegrees: -7)
        }
    }

    private func automaticCompressedEntrancePose(for entrance: RobotEntrance,
                                                  offset: CGFloat) -> RobotPartTransform {
        if quietOrbitEnabled {
            switch entrance {
            case .top: return RobotPartTransform(translation: CGPoint(x: offset * 0.4, y: -6), scaleX: 1.04, scaleY: 0.94)
            case .right: return RobotPartTransform(translation: CGPoint(x: 6, y: offset * 0.4), scaleX: 0.94, scaleY: 1.04)
            case .left: return RobotPartTransform(translation: CGPoint(x: -6, y: offset * 0.4), scaleX: 0.94, scaleY: 1.04)
            }
        }
        switch entrance {
        case .top:
            return RobotPartTransform(translation: CGPoint(x: offset, y: -43),
                                      scaleX: 1.08, scaleY: 0.87, rotationDegrees: offset)
        case .right:
            return RobotPartTransform(translation: CGPoint(x: 43, y: offset),
                                      scaleX: 0.88, scaleY: 1.07, rotationDegrees: 8)
        case .left:
            return RobotPartTransform(translation: CGPoint(x: -43, y: offset),
                                      scaleX: 0.88, scaleY: 1.07, rotationDegrees: -8)
        }
    }

    private func automaticEntranceOvershoot(for entrance: RobotEntrance,
                                             offset: CGFloat) -> RobotPartTransform {
        switch entrance {
        case .top:
            return RobotPartTransform(translation: CGPoint(x: offset * -0.25, y: 2.5),
                                      scaleX: 0.97, scaleY: 1.06, rotationDegrees: -offset * 0.35)
        case .right:
            return RobotPartTransform(translation: CGPoint(x: -2.4, y: offset * -0.25),
                                      scaleX: 1.05, scaleY: 0.98, rotationDegrees: -1.5)
        case .left:
            return RobotPartTransform(translation: CGPoint(x: 2.4, y: offset * -0.25),
                                      scaleX: 1.05, scaleY: 0.98, rotationDegrees: 1.5)
        }
    }

    private func automaticEatingBodyFrames(_ style: AutoCaptureEatingStyle,
                                            phase: AutoCaptureRobotPerformancePhase)
        -> [AutomaticPoseFrame] {
        func frame(_ fraction: Double, x: CGFloat = 0, y: CGFloat = 0,
                   sx: CGFloat = 1, sy: CGFloat = 1, angle: CGFloat = 0) -> AutomaticPoseFrame {
            AutomaticPoseFrame(time: phaseTime(phase, fraction),
                               pose: RobotPartTransform(translation: CGPoint(x: x, y: y),
                                                        scaleX: sx, scaleY: sy,
                                                        rotationDegrees: angle))
        }
        switch style {
        case .bite: return [frame(0.3, x: 2, angle: 3), frame(0.58, sx: 1.05, sy: 0.95), frame(0.88)]
        case .recoil: return [frame(0.28, x: 3, angle: 5), frame(0.52, x: -7, y: -2, sx: 0.95, sy: 1.05, angle: -13), frame(0.79, x: 2, angle: 4), frame(0.96)]
        case .slurp: return [frame(0.24, x: 3, sx: 0.98, sy: 1.04, angle: 4), frame(0.50, x: 1, sx: 0.95, sy: 1.07), frame(0.73, sx: 1.08, sy: 0.91), frame(0.96)]
        case .nibble: return [frame(0.23, x: 2, angle: -4), frame(0.42, y: 1, sx: 1.04, sy: 0.96, angle: 4), frame(0.61, x: 1, angle: -4), frame(0.79, sx: 1.04, sy: 0.96, angle: 3), frame(0.96)]
        case .toss: return [frame(0.2, x: 2, y: 2, sx: 1.03, sy: 0.94), frame(0.45, y: -4, sx: 0.97, sy: 1.06), frame(0.70, x: -2, angle: -4), frame(0.86, y: 2, sx: 1.08, sy: 0.9), frame(0.98)]
        case .swallow: return [frame(0.30, x: 2, sx: 1.06, sy: 0.95), frame(0.49, sx: 1.13, sy: 0.86), frame(0.63, x: -2, sx: 1.05, sy: 0.92, angle: -5), frame(0.77, y: -2, sx: 0.94, sy: 1.11), frame(0.98)]
        case .chase: return [frame(0.22, x: 2, angle: 4), frame(0.42, x: 6, y: -1, angle: 11), frame(0.60, x: 9, y: 1, sx: 0.95, sy: 1.04, angle: 7), frame(0.81, x: 2, sx: 1.05, sy: 0.94), frame(0.98)]
        case .inspect: return [frame(0.24, x: -1, angle: -8), frame(0.49, x: 1, angle: 7), frame(0.65, x: -1, angle: -5), frame(0.87, x: 3, sx: 1.04, sy: 0.96), frame(0.98)]
        case .stack: return [frame(0.28, sx: 1.03, sy: 0.98), frame(0.47, sx: 1.08, sy: 0.94), frame(0.64, sx: 1.12, sy: 0.89), frame(0.81, y: -2, sx: 0.96, sy: 1.05), frame(0.98)]
        case .hiccup: return [frame(0.31, sx: 1.03, sy: 0.96), frame(0.54), frame(0.66, y: -5, sx: 0.95, sy: 1.1), frame(0.79, y: 1, sx: 1.06, sy: 0.93), frame(0.94)]
        }
    }

    private func automaticReactionBodyFrames(_ reaction: AutoCaptureRobotReaction,
                                             phase: AutoCaptureRobotPerformancePhase,
                                             entrance: RobotEntrance) -> [AutomaticPoseFrame] {
        let style = reaction.eatingStyle
        let angle: CGFloat = style == .inspect ? -5 : style == .recoil ? 4 : 0
        let hop: CGFloat = style == .hiccup ? -4 : style == .stack ? -2 : -1
        return [AutomaticPoseFrame(time: phase.startTime, pose: .identity),
                AutomaticPoseFrame(time: phaseTime(phase, 0.36),
                                   pose: RobotPartTransform(translation: CGPoint(x: 0, y: hop),
                                                            scaleX: 1.025, scaleY: 1.02,
                                                            rotationDegrees: angle)),
                AutomaticPoseFrame(time: phaseTime(phase, 0.68),
                                   pose: RobotPartTransform(scaleX: 1.025, scaleY: 0.98,
                                                            rotationDegrees: -angle * 0.4)),
                AutomaticPoseFrame(time: phase.endTime, pose: .identity)]
    }

    private func automaticArmFrames(reaction: AutoCaptureRobotReaction,
                                    phase: AutoCaptureRobotPerformancePhase,
                                    left: Bool,
                                    totalDuration: TimeInterval) -> [AutomaticPoseFrame] {
        let sign: CGFloat = left ? -1 : 1
        let values: [CGFloat]
        switch reaction.eatingStyle {
        case .bite: values = [8, 26, 12, 0]
        case .recoil: values = [22, 48, 18, 0]
        case .slurp: values = left ? [5, 10, 5, 0] : [24, 32, 20, 0]
        case .nibble: values = [28, 36, 29, 34]
        case .toss: values = left ? [10, 15, 26, 8] : [28, 62, 15, 9]
        case .swallow: values = [29, 42, 37, 10]
        case .chase: values = left ? [10, 20, 32, 8] : [32, 53, 38, 8]
        case .inspect: values = left ? [4, 8, 5, 0] : [30, 34, 30, 10]
        case .stack: values = [28, 36, 40, 9]
        case .hiccup: values = [12, 20, 45, 8]
        }
        var frames = [AutomaticPoseFrame(time: 0, pose: .identity),
                      AutomaticPoseFrame(time: phase.startTime, pose: .identity)]
        frames += zip([0.22, 0.45, 0.67, 0.85], values).map { fraction, angle in
            AutomaticPoseFrame(time: phaseTime(phase, fraction),
                               pose: RobotPartTransform(rotationDegrees: angle * sign))
        }
        frames.append(AutomaticPoseFrame(time: phase.endTime, pose: .identity))
        frames.append(AutomaticPoseFrame(time: totalDuration, pose: .identity))
        return frames
    }

    private func automaticEyeFrames(reaction: AutoCaptureRobotReaction,
                                    phase: AutoCaptureRobotPerformancePhase,
                                    anticipation: AutoCaptureRobotPerformancePhase,
                                    entrance: AutoCaptureRobotPerformancePhase,
                                    totalDuration: TimeInterval,
                                    gaze: CGFloat)
        -> (left: [AutomaticPoseFrame], right: [AutomaticPoseFrame]) {
        var frames = [AutomaticPoseFrame(time: 0, pose: .identity),
                      AutomaticPoseFrame(time: phaseTime(anticipation, 0.4),
                                         pose: RobotPartTransform(translation: CGPoint(x: -1.2 + gaze * 0.3, y: 0))),
                      AutomaticPoseFrame(time: anticipation.endTime,
                                         pose: RobotPartTransform(translation: CGPoint(x: 1.6, y: -0.6))),
                      AutomaticPoseFrame(time: entrance.endTime,
                                         pose: RobotPartTransform(translation: CGPoint(x: 1.7, y: -0.5)))]
        // Pupils follow the generic token, clamped to the screen's eye socket.
        frames += reaction.eatingStyle.tokenKeyframes.map { token in
            AutomaticPoseFrame(time: phaseTime(phase, token.fraction),
                               pose: RobotPartTransform(translation: CGPoint(
                                x: min(1.8, max(-1.8, token.x * 0.08)),
                                y: min(1.2, max(-1.2, token.y * 0.055))),
                                scaleX: 1, scaleY: reaction.eatingStyle == .inspect ? 0.65 : 1))
        }
        frames += [AutomaticPoseFrame(time: phase.endTime, pose: .identity),
                   AutomaticPoseFrame(time: phase.endTime + 0.12,
                                      pose: RobotPartTransform(scaleX: 1, scaleY: 0.09)),
                   AutomaticPoseFrame(time: phase.endTime + 0.24, pose: .identity),
                   AutomaticPoseFrame(time: totalDuration, pose: .identity)]
        return (frames, frames)
    }

    private func addAutomaticShadowTimeline(anticipation: AutoCaptureRobotPerformancePhase,
                                            entrance: AutoCaptureRobotPerformancePhase,
                                            reaction: AutoCaptureRobotPerformancePhase,
                                            exit: AutoCaptureRobotPerformancePhase,
                                            performance: AutoCaptureRobotPerformance) {
        guard !quietOrbitEnabled else { return }
        addAutomaticOpacityTrack([
            AutomaticOpacityFrame(time: 0, opacity: 0),
            AutomaticOpacityFrame(time: anticipation.endTime, opacity: 0),
            AutomaticOpacityFrame(time: entrance.endTime, opacity: 0.18),
            AutomaticOpacityFrame(time: reaction.endTime, opacity: 0.18),
            AutomaticOpacityFrame(time: exit.endTime, opacity: 0)
        ], to: shadowLayer, key: "robot.auto-success.shadow-opacity", performance: performance)
        addAutomaticTransformTrack([
            AutomaticPoseFrame(time: 0, pose: RobotPartTransform(scaleX: 0.55, scaleY: 1)),
            AutomaticPoseFrame(time: entrance.endTime, pose: .identity),
            AutomaticPoseFrame(time: phaseTime(reaction, 0.52),
                               pose: RobotPartTransform(scaleX: 0.86, scaleY: 1)),
            AutomaticPoseFrame(time: reaction.endTime, pose: .identity),
            AutomaticPoseFrame(time: exit.endTime, pose: RobotPartTransform(scaleX: 0.55, scaleY: 1))
        ], to: shadowLayer, key: "robot.auto-success.shadow-transform", performance: performance)
    }

    private func addAutomaticSuccessBadgeTimeline(reaction: AutoCaptureRobotPerformancePhase,
                                                   exit: AutoCaptureRobotPerformancePhase,
                                                   performance: AutoCaptureRobotPerformance) {
        let opacity = [
            AutomaticOpacityFrame(time: 0, opacity: 0),
            AutomaticOpacityFrame(time: phaseTime(reaction, 0.26), opacity: 0),
            AutomaticOpacityFrame(time: phaseTime(reaction, 0.38), opacity: 1),
            AutomaticOpacityFrame(time: reaction.endTime, opacity: 1),
            AutomaticOpacityFrame(time: phaseTime(exit, 0.34), opacity: 0),
            AutomaticOpacityFrame(time: exit.endTime, opacity: 0)
        ]
        addAutomaticOpacityTrack(opacity, to: autoSuccessBadgeLayer,
                                 key: "robot.auto-success.badge-opacity", performance: performance)
        addAutomaticOpacityTrack(opacity, to: autoSuccessCheckLayer,
                                 key: "robot.auto-success.check-opacity", performance: performance)
        let transformFrames = [
            AutomaticPoseFrame(time: 0, pose: RobotPartTransform(scaleX: 0.45, scaleY: 0.45)),
            AutomaticPoseFrame(time: phaseTime(reaction, 0.26), pose: RobotPartTransform(scaleX: 0.45, scaleY: 0.45)),
            AutomaticPoseFrame(time: phaseTime(reaction, 0.42), pose: RobotPartTransform(scaleX: 1.18, scaleY: 1.18, rotationDegrees: 6)),
            AutomaticPoseFrame(time: phaseTime(reaction, 0.55), pose: .identity),
            AutomaticPoseFrame(time: exit.endTime, pose: .identity)
        ]
        addAutomaticTransformTrack(transformFrames, to: autoSuccessBadgeLayer,
                                   key: "robot.auto-success.badge-transform", performance: performance)
        addAutomaticTransformTrack(transformFrames, to: autoSuccessCheckLayer,
                                   key: "robot.auto-success.check-transform", performance: performance)
    }

    private func configureAutomaticProp(for reaction: AutoCaptureRobotReaction) {
        let path = CGMutablePath()
        let detail = CGMutablePath()
        let stacked = reaction.eatingStyle == .stack || autoCaptureTokenCount > 1
        if stacked {
            path.addRoundedRect(in: CGRect(x: -8, y: -11, width: 13, height: 17),
                                cornerWidth: 2, cornerHeight: 2)
            path.addRoundedRect(in: CGRect(x: -4, y: -9, width: 13, height: 17),
                                cornerWidth: 2, cornerHeight: 2)
        }
        path.addRoundedRect(in: CGRect(x: -6.5, y: -8.5, width: 13, height: 17),
                            cornerWidth: 2, cornerHeight: 2)
        // A generic check is the only mark on the paper. Never use capture text,
        // screenshots, OCR, file names or application icons in this animation.
        detail.move(to: CGPoint(x: -3, y: 0))
        detail.addLine(to: CGPoint(x: -0.5, y: 3))
        detail.addLine(to: CGPoint(x: 4, y: -3))
        withoutActions {
            autoPropLayer.path = path
            autoPropDetailLayer.path = detail
            autoPropLayer.opacity = 1
            autoPropDetailLayer.opacity = 1
            autoCountLayer.string = autoCaptureTokenCount > 1 ? "×\(autoCaptureTokenCount)" : ""
            autoCountLayer.isHidden = autoCaptureTokenCount <= 1
        }
    }

    /// Updates the existing paper stack in place. No motion or phase is restarted,
    /// even if a burst arrives while the current token is already being swallowed.
    func updateAutoCaptureCount(_ count: Int) {
        autoCaptureTokenCount = max(1, count)
        if let currentAutoCaptureReaction {
            configureAutomaticProp(for: currentAutoCaptureReaction)
        }
    }

    /// A brief upside-down look around the physical island edge.
    @discardableResult
    func playIslandPeek() -> TimeInterval {
        beginIslandMotion()
        let duration: TimeInterval = reduceMotionProvider() ? 0.38 : 2.2
        if reduceMotionProvider() {
            // Callers normally suppress idle invitations in reduced motion.
            withoutActions { artLayer.opacity = 0 }
        } else {
            animateIslandFrames(IslandRobotChoreography.peek(duration: duration), duration: duration)
        }
        return duration
    }

    /// Hands hook over the edge, then lower the robot into a supported hang.
    @discardableResult
    func playIslandClimb() -> TimeInterval {
        beginIslandMotion()
        let reduced = reduceMotionProvider()
        let duration = reduced ? RobotManualEntranceTiming.reducedDuration : RobotManualEntranceTiming.islandDuration
        if reduced {
            let final = IslandRobotChoreography.reveal(duration: 1).last!
            applyIslandFrame(final)
            withoutActions { artLayer.opacity = 0 }
            animateOpacity(artLayer, to: 1, duration: duration, key: "robot.island.climb-fade")
        } else {
            animateIslandFrames(IslandRobotChoreography.reveal(duration: duration), duration: duration)
        }
        islandCompletionTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(duration)) }
            catch { return }
            guard let self, !Task.isCancelled, self.islandMotionActive,
                  self.motionState.isVisible else { return }
            self.islandCompletionTask = nil
            self.islandResting = true
            self.updateIslandGaze()
        }
        return duration
    }

    private func beginIslandMotion() {
        cancelIslandCompletion()
        stopAmbientMotion()
        removeAllAnimations()
        resetAutomaticCelebrationLayers()
        configureIslandStage(true)
        currentAutoCaptureReaction = nil
        islandMotionActive = true
        islandResting = false
        motionState.send(.hide)
        motionState.send(.reveal(.top))
        prepareIslandRig()
        withoutActions { mouthLayer.path = mouthPath(for: .idle) }
    }

    private func updateIslandGaze() {
        let pointer = motionState.pointer
        let pose = RobotPartTransform(translation: CGPoint(x: pointer.x * 1.8, y: pointer.y * 1.2))
        for eye in [leftEyeLayer, rightEyeLayer] {
            animateTransform(eye, to: transform(pose), duration: reduceMotionProvider() ? 0 : 0.15,
                             key: "robot.island.pointer-gaze")
        }
    }

    private func configureIslandRig() {
        for index in 0..<2 {
            let arm = hangingArms[index]
            arm.fillColor = nil
            arm.strokeColor = Self.color(0x483556)
            arm.lineWidth = 5.2
            arm.lineCap = .round
            let highlight = hangingArmHighlights[index]
            highlight.fillColor = nil
            highlight.strokeColor = Self.color(0xB99CCF)
            highlight.lineWidth = 3.2
            highlight.lineCap = .round
            artLayer.insertSublayer(arm, below: bodyLayer)
            artLayer.insertSublayer(highlight, below: bodyLayer)
            let hand = hangingHands[index]
            let fingers = CGMutablePath()
            fingers.addRoundedRect(in: CGRect(x: -3.6, y: -2, width: 7.2, height: 7),
                                   cornerWidth: 2.2, cornerHeight: 2.2)
            for x in [-1.2, 1.2] as [CGFloat] {
                fingers.move(to: CGPoint(x: x, y: -0.5))
                fingers.addLine(to: CGPoint(x: x, y: 1.8))
            }
            hand.path = fingers
            hand.fillColor = Self.color(0xCEB6DE)
            hand.strokeColor = Self.color(0x483556)
            hand.lineWidth = 1.1
            artLayer.addSublayer(hand)
        }
        for part in islandRigLayers { part.opacity = 0 }
    }

    private func prepareIslandRig() {
        withoutActions {
            artLayer.opacity = 1
            artLayer.masksToBounds = false
            configureContainer(bodyLayer, anchor: CGPoint(x: 32, y: 0))
            configureContainer(feetLayer, anchor: CGPoint(x: 32, y: 70))
            bodyLayer.transform = CATransform3DIdentity
            leftArmLayer.opacity = 0
            rightArmLayer.opacity = 0
            shadowLayer.opacity = 0
            islandGripLayer.opacity = 0
            // The paper finishes inside a moving mouth, including during a swing.
            for part in [autoTokenLayer, autoSuccessBadgeLayer, autoSuccessCheckLayer] {
                bodyLayer.addSublayer(part)
            }
        }
    }

    private func islandArmPath(_ frame: IslandRobotFrame, index: Int) -> CGPath {
        let shoulder = IslandRobotChoreography.worldPoint(CGPoint(x: index == 0 ? 14 : 50, y: 43),
                                                         body: frame.body)
        let hand = index == 0 ? frame.leftHand : frame.rightHand
        let side: CGFloat = index == 0 ? -1 : 1
        let bend = min(10, max(3, abs(shoulder.y - hand.y) * 0.14))
        let path = CGMutablePath()
        path.move(to: shoulder)
        path.addCurve(to: hand,
                      control1: CGPoint(x: shoulder.x + side * bend, y: shoulder.y - 8),
                      control2: CGPoint(x: hand.x + side * bend, y: hand.y + 12))
        return path
    }

    private func applyIslandFrame(_ frame: IslandRobotFrame) {
        withoutActions {
            bodyLayer.transform = transform(frame.body)
            feetLayer.transform = transform(frame.feet)
            leftEyeLayer.transform = transform(RobotPartTransform(translation: frame.gaze, scaleY: frame.leftEyeScaleY))
            rightEyeLayer.transform = transform(RobotPartTransform(translation: frame.gaze, scaleY: frame.rightEyeScaleY))
            for index in 0..<2 {
                let opacity = index == 0 ? frame.leftHandOpacity : frame.rightHandOpacity
                let path = islandArmPath(frame, index: index)
                hangingArms[index].path = path
                hangingArmHighlights[index].path = path
                hangingHands[index].position = index == 0 ? frame.leftHand : frame.rightHand
                for part in [hangingArms[index], hangingArmHighlights[index], hangingHands[index]] {
                    part.opacity = opacity
                }
            }
        }
    }

    private func animateIslandFrames(_ frames: [IslandRobotFrame], duration: TimeInterval) {
        guard let final = frames.last, duration > 0 else { return }
        applyIslandFrame(final)
        // One clock and linear interpolation of densely sampled poses keep the
        // stage-space arms attached to the body-space shoulders on every frame.
        let begin = CACurrentMediaTime()
        func track(_ target: CALayer, _ property: String, _ values: [Any], _ suffix: String) {
            let animation = CAKeyframeAnimation(keyPath: property)
            animation.values = values
            animation.keyTimes = frames.map { NSNumber(value: $0.time / duration) }
            animation.duration = duration
            animation.beginTime = target.convertTime(begin, from: nil)
            animation.calculationMode = .linear
            target.add(animation, forKey: "robot.island.\(suffix)")
        }
        track(bodyLayer, "transform", frames.map { NSValue(caTransform3D: transform($0.body)) }, "body")
        track(feetLayer, "transform", frames.map { NSValue(caTransform3D: transform($0.feet)) }, "feet")
        for index in 0..<2 {
            let eye = index == 0 ? leftEyeLayer : rightEyeLayer
            track(eye, "transform", frames.map {
                NSValue(caTransform3D: transform(RobotPartTransform(translation: $0.gaze,
                    scaleY: index == 0 ? $0.leftEyeScaleY : $0.rightEyeScaleY)))
            }, "eye-\(index)")
            let paths = frames.map { islandArmPath($0, index: index) }
            track(hangingArms[index], "path", paths, "arm-\(index)")
            track(hangingArmHighlights[index], "path", paths, "arm-highlight-\(index)")
            track(hangingHands[index], "position", frames.map {
                NSValue(point: index == 0 ? $0.leftHand : $0.rightHand)
            }, "hand-\(index)")
            for (partIndex, part) in [hangingArms[index], hangingArmHighlights[index], hangingHands[index]].enumerated() {
                track(part, "opacity", frames.map { index == 0 ? $0.leftHandOpacity : $0.rightHandOpacity },
                      "visibility-\(index)-\(partIndex)")
            }
        }
    }

    private func cancelIslandCompletion() {
        islandCompletionTask?.cancel()
        islandCompletionTask = nil
    }

    private func addAutomaticPropTimeline(reaction: AutoCaptureRobotReaction,
                                          phase: AutoCaptureRobotPerformancePhase,
                                          totalDuration: TimeInterval,
                                          performance: AutoCaptureRobotPerformance) {
        let poses = reaction.eatingStyle.tokenKeyframes.map { token in
            AutomaticPoseFrame(time: phaseTime(phase, token.fraction),
                               pose: RobotPartTransform(translation: CGPoint(x: token.x, y: token.y),
                                                        scaleX: token.scaleX, scaleY: token.scaleY,
                                                        rotationDegrees: token.rotation))
        }
        addAutomaticTransformTrack([AutomaticPoseFrame(time: 0, pose: poses[0].pose)] + poses +
                                   [AutomaticPoseFrame(time: totalDuration, pose: poses.last!.pose)],
                                   to: autoTokenLayer, key: "robot.auto-success.eating-token",
                                   performance: performance)
        addAutomaticOpacityTrack([
            AutomaticOpacityFrame(time: 0, opacity: 0),
            AutomaticOpacityFrame(time: phase.startTime, opacity: 0),
            AutomaticOpacityFrame(time: phaseTime(phase, 0.09), opacity: 1),
            AutomaticOpacityFrame(time: phaseTime(phase, 0.86), opacity: 1),
            AutomaticOpacityFrame(time: phaseTime(phase, 0.96), opacity: 0),
            AutomaticOpacityFrame(time: totalDuration, opacity: 0)
        ], to: autoTokenLayer, key: "robot.auto-success.token-opacity", performance: performance)
    }

    private func addAutomaticMouthTimeline(eating: AutoCaptureRobotPerformancePhase,
                                           reaction: AutoCaptureRobotPerformancePhase,
                                           performance: AutoCaptureRobotPerformance) {
        // A filled mouth opens before contact, chews twice, then returns to the
        // familiar smile. Path animation stays on one small GPU-backed layer.
        // Matching curve topology keeps Core Animation interpolation smooth.
        func chewingPath(width: CGFloat, opening: CGFloat) -> CGPath {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 32 - width / 2, y: 42))
            path.addCurve(to: CGPoint(x: 32 + width / 2, y: 42),
                          control1: CGPoint(x: 32 - width / 2, y: 42 - opening),
                          control2: CGPoint(x: 32 + width / 2, y: 42 - opening))
            path.addCurve(to: CGPoint(x: 32 - width / 2, y: 42),
                          control1: CGPoint(x: 32 + width / 2, y: 42 + opening),
                          control2: CGPoint(x: 32 - width / 2, y: 42 + opening))
            path.closeSubpath()
            return path
        }
        let smile = chewingPath(width: 6, opening: 0.8)
        let bite = chewingPath(width: 8, opening: 3.6)
        let closed = chewingPath(width: 5, opening: 0.1)
        let animation = CAKeyframeAnimation(keyPath: "path")
        animation.values = [smile, smile, bite, closed, bite, closed, smile, smile]
        animation.keyTimes = [0, eating.startTime, phaseTime(eating, 0.27),
                              phaseTime(eating, 0.49), phaseTime(eating, 0.66),
                              phaseTime(eating, 0.86), reaction.startTime,
                              performance.totalDuration].map { NSNumber(value: $0 / performance.totalDuration) }
        animation.duration = performance.totalDuration
        animation.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 7)
        withoutActions { mouthLayer.path = smile }
        mouthLayer.add(animation, forKey: "robot.auto-success.chewing-mouth")
    }

    private static func islandGripPath() -> CGPath {
        let path = CGMutablePath()
        for x in [12.0, 46.0] {
            path.addRoundedRect(in: CGRect(x: x, y: 0.5, width: 7, height: 5),
                                cornerWidth: 2.3, cornerHeight: 2.3)
        }
        return path
    }

    private func addIslandClimbingDetails(anticipation: AutoCaptureRobotPerformancePhase,
                                          entrance: AutoCaptureRobotPerformancePhase,
                                          exit: AutoCaptureRobotPerformancePhase?,
                                          performance: AutoCaptureRobotPerformance) {
        // Hide the lower parts while the face peeks. Without this stagger a body
        // translated below a clipping edge would incorrectly reveal feet first.
        let end = performance.totalDuration
        func visibility(_ start: Double, _ finish: Double) -> [AutomaticOpacityFrame] {
            var frames = [AutomaticOpacityFrame(time: 0, opacity: 0),
                          AutomaticOpacityFrame(time: phaseTime(entrance, start), opacity: 0),
                          AutomaticOpacityFrame(time: phaseTime(entrance, finish), opacity: 1)]
            if let exit {
                frames += [AutomaticOpacityFrame(time: phaseTime(exit, 0.25), opacity: 1),
                           AutomaticOpacityFrame(time: phaseTime(exit, 0.72), opacity: 0)]
            }
            frames.append(AutomaticOpacityFrame(time: end, opacity: exit == nil ? 1 : 0))
            return frames
        }
        addAutomaticOpacityTrack(visibility(0.18, 0.45), to: shellLayer,
                                 key: "robot.auto-success.torso-emergence", performance: performance)
        addAutomaticOpacityTrack(visibility(0.56, 0.83), to: feetLayer,
                                 key: "robot.auto-success.feet-emergence", performance: performance)
        addAutomaticOpacityTrack(visibility(0.08, 0.30), to: faceScreenLayer,
                                 key: "robot.auto-success.face-emergence", performance: performance)
        addAutomaticOpacityTrack(visibility(0.12, 0.35), to: mouthLayer,
                                 key: "robot.auto-success.mouth-emergence", performance: performance)
        addAutomaticOpacityTrack(visibility(0.04, 0.24), to: lidLayer,
                                 key: "robot.auto-success.head-emergence", performance: performance)
        for (index, arm) in [leftArmLayer, rightArmLayer].enumerated() {
            addAutomaticOpacityTrack(visibility(0.08, 0.3), to: arm,
                                     key: "robot.auto-success.arm-emergence-\(index)", performance: performance)
            // Reach up to the lip, briefly slip, then release the hand as the
            // torso settles. The model path is restored after the short track.
            let left = index == 0
            let normal = arm.path!
            let reach = CGMutablePath()
            reach.move(to: CGPoint(x: left ? 14 : 50, y: 43))
            reach.addQuadCurve(to: CGPoint(x: left ? 15 : 49, y: 7),
                               control: CGPoint(x: left ? 3 : 61, y: 23))
            let armPath = CAKeyframeAnimation(keyPath: "path")
            let values: [CGPath]
            let times: [Double]
            if let exit {
                values = [normal, reach, reach, normal, normal, reach, normal]
                times = [0, phaseTime(entrance, 0.22), phaseTime(entrance, 0.52), entrance.endTime,
                         exit.startTime, phaseTime(exit, 0.45), end]
            } else {
                values = [normal, reach, reach, normal]
                times = [0, phaseTime(entrance, 0.22), phaseTime(entrance, 0.52), end]
            }
            armPath.values = values
            armPath.keyTimes = times.map { NSNumber(value: $0 / end) }
            armPath.duration = end
            arm.add(armPath, forKey: "robot.auto-success.gripping-arm-\(index)")
        }
        var grip = [AutomaticOpacityFrame(time: 0, opacity: 0),
                    AutomaticOpacityFrame(time: anticipation.endTime * 0.7, opacity: 0),
                    AutomaticOpacityFrame(time: anticipation.endTime, opacity: 1),
                    AutomaticOpacityFrame(time: phaseTime(entrance, 0.46), opacity: 1),
                    AutomaticOpacityFrame(time: phaseTime(entrance, 0.71), opacity: 0)]
        if let exit {
            grip += [AutomaticOpacityFrame(time: exit.startTime, opacity: 0),
                     AutomaticOpacityFrame(time: phaseTime(exit, 0.45), opacity: 1),
                     AutomaticOpacityFrame(time: phaseTime(exit, 0.87), opacity: 1)]
        }
        grip.append(AutomaticOpacityFrame(time: end, opacity: 0))
        addAutomaticOpacityTrack(grip, to: islandGripLayer,
                                 key: "robot.auto-success.island-grip", performance: performance)
    }

    private func resetAutomaticCelebrationLayers() {
        islandResting = false
        withoutActions {
            configureContainer(bodyLayer, anchor: CGPoint(x: 32, y: 69))
            feetLayer.transform = CATransform3DIdentity
            for part in islandRigLayers { part.opacity = 0 }
            for part in [autoTokenLayer, autoSuccessBadgeLayer, autoSuccessCheckLayer] {
                artLayer.addSublayer(part)
            }
            artLayer.opacity = 1
            bodyLayer.transform = CATransform3DIdentity
            for part in [shellLayer, feetLayer, lidLayer, leftArmLayer, rightArmLayer,
                         faceScreenLayer, mouthLayer] { part.opacity = 1 }
            faceLayer.transform = CATransform3DIdentity
            lidLayer.transform = CATransform3DIdentity
            leftArmLayer.transform = CATransform3DIdentity
            rightArmLayer.transform = CATransform3DIdentity
            leftEyeLayer.transform = CATransform3DIdentity
            rightEyeLayer.transform = CATransform3DIdentity
            shadowLayer.transform = CATransform3DIdentity
            shadowLayer.opacity = 0
            intakeLayer.opacity = 0
            for layer in [autoTokenLayer, autoPropLayer, autoPropDetailLayer, islandGripLayer, autoSuccessBadgeLayer,
                          autoSuccessCheckLayer, autoFlashLayer, autoConfettiLayer] {
                layer.transform = CATransform3DIdentity
                layer.opacity = 0
            }
            for piece in autoConfettiPieces { piece.transform = CATransform3DIdentity }
        }
    }

    private func phase(_ kind: AutoCaptureRobotPhaseKind,
                       in performance: AutoCaptureRobotPerformance) -> AutoCaptureRobotPerformancePhase? {
        performance.phases.first { $0.kind == kind }
    }

    private func reactionPhase(in performance: AutoCaptureRobotPerformance)
        -> AutoCaptureRobotPerformancePhase? {
        performance.phases.first {
            if case .reaction = $0.kind { return true }
            return false
        }
    }

    private func phaseTime(_ phase: AutoCaptureRobotPerformancePhase, _ fraction: Double) -> TimeInterval {
        phase.startTime + phase.duration * min(1, max(0, fraction))
    }

    private func addAutomaticTransformTrack(_ rawFrames: [AutomaticPoseFrame],
                                            to layer: CALayer,
                                            key: String,
                                            performance: AutoCaptureRobotPerformance) {
        let frames = canonicalAutomaticPoseFrames(rawFrames, totalDuration: performance.totalDuration)
        guard performance.totalDuration > 0, !frames.isEmpty else { return }
        let animation = CAKeyframeAnimation(keyPath: "transform")
        animation.values = frames.map { NSValue(caTransform3D: transform($0.pose)) }
        animation.keyTimes = frames.map { NSNumber(value: $0.time / performance.totalDuration) }
        animation.duration = performance.totalDuration
        animation.timingFunctions = automaticTimingFunctions(for: frames.map(\.time), performance: performance)
        withoutActions { layer.transform = transform(frames.last!.pose) }
        layer.add(animation, forKey: key)
    }

    private func addAutomaticOpacityTrack(_ rawFrames: [AutomaticOpacityFrame],
                                          to layer: CALayer,
                                          key: String,
                                          performance: AutoCaptureRobotPerformance) {
        let frames = canonicalAutomaticOpacityFrames(rawFrames, totalDuration: performance.totalDuration)
        guard performance.totalDuration > 0, !frames.isEmpty else { return }
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = frames.map(\.opacity)
        animation.keyTimes = frames.map { NSNumber(value: $0.time / performance.totalDuration) }
        animation.duration = performance.totalDuration
        animation.timingFunctions = automaticTimingFunctions(for: frames.map(\.time), performance: performance)
        withoutActions { layer.opacity = frames.last!.opacity }
        layer.add(animation, forKey: key)
    }

    private func canonicalAutomaticPoseFrames(_ frames: [AutomaticPoseFrame],
                                              totalDuration: TimeInterval) -> [AutomaticPoseFrame] {
        var result: [AutomaticPoseFrame] = []
        for frame in frames.sorted(by: { $0.time < $1.time }) {
            let clamped = AutomaticPoseFrame(time: min(totalDuration, max(0, frame.time)), pose: frame.pose)
            if let last = result.last, abs(last.time - clamped.time) < 0.000_001 {
                result[result.count - 1] = clamped
            } else {
                result.append(clamped)
            }
        }
        return result
    }

    private func canonicalAutomaticOpacityFrames(_ frames: [AutomaticOpacityFrame],
                                                 totalDuration: TimeInterval) -> [AutomaticOpacityFrame] {
        var result: [AutomaticOpacityFrame] = []
        for frame in frames.sorted(by: { $0.time < $1.time }) {
            let clamped = AutomaticOpacityFrame(time: min(totalDuration, max(0, frame.time)),
                                                opacity: frame.opacity)
            if let last = result.last, abs(last.time - clamped.time) < 0.000_001 {
                result[result.count - 1] = clamped
            } else {
                result.append(clamped)
            }
        }
        return result
    }

    private func automaticTimingFunctions(for times: [TimeInterval],
                                          performance: AutoCaptureRobotPerformance)
        -> [CAMediaTimingFunction] {
        guard times.count > 1 else { return [] }
        return (0..<(times.count - 1)).map { index in
            let midpoint = (times[index] + times[index + 1]) / 2
            let curve = performance.phases.first {
                midpoint >= $0.startTime && midpoint <= $0.endTime
            }?.timingCurve ?? .easeInOut
            switch curve {
            case .easeInOut:
                return CAMediaTimingFunction(name: .easeInEaseOut)
            case .easeOut:
                return CAMediaTimingFunction(name: .easeOut)
            case .spring:
                // Overshoot is represented by explicit keyframes. This curve
                // supplies the quick, soft spring arrival between them.
                return CAMediaTimingFunction(controlPoints: 0.18, 0.78, 0.24, 1)
            }
        }
    }

    private func automaticMouthPath(for reaction: AutoCaptureRobotReaction) -> CGPath {
        switch reaction {
        case .cameraFlash, .confettiSneeze:
            return mouthPath(for: .hungry)
        case .dizzySpin, .wobblySalute:
            return mouthPath(for: .puzzled)
        default:
            return mouthPath(for: .delighted)
        }
    }

    // MARK: - State presentation

    private func animateReveal(from entrance: RobotEntrance, reduceMotion: Bool) {
        removeAllAnimations()
        resetAutomaticCelebrationLayers()
        let descriptor = RobotMotionDescriptor.make(for: .reveal(entrance), reduceMotion: reduceMotion)
        applyExpression(.idle, duration: 0)
        applyPartTransforms(RobotMotionDescriptor.make(for: .mood(.idle), reduceMotion: reduceMotion), duration: 0)
        guard descriptor.isAnimated else { return }

        let start = transform(descriptor.initialBody)
        var overshoot = RobotPartTransform.identity
        overshoot.translation.x = entrance == .left ? 1.6 : entrance == .right ? -1.6 : 0
        overshoot.translation.y = entrance == .top ? 1.2 : -1
        overshoot.scaleX = 1.045
        overshoot.scaleY = 1.045
        overshoot.rotationDegrees = entrance.revealRotationDegrees * -0.18
        let values = [start, transform(overshoot), CATransform3DIdentity].map { NSValue(caTransform3D: $0) }
        setModelTransform(bodyLayer, CATransform3DIdentity)
        addKeyframes(values, keyTimes: [0, 0.72, 1], duration: descriptor.duration,
                     to: bodyLayer, keyPath: "transform", key: "robot.reveal")
        animateOpacity(shadowLayer, to: quietOrbitEnabled ? 0 : Float(descriptor.shadowOpacity), duration: descriptor.duration, key: "robot.reveal.shadow")
    }

    private func applyMood(_ mood: RobotMood, previous: RobotMood, event: RobotMotionEvent?, reduceMotion: Bool) {
        let descriptor = RobotMotionDescriptor.make(for: .mood(mood), reduceMotion: reduceMotion)
        applyExpression(mood, duration: descriptor.duration)

        switch mood {
        case .digesting where descriptor.isAnimated && (previous != .digesting || event == .saving(true)):
            animateDigest(descriptor)
        case .delighted where descriptor.isAnimated && event != nil:
            applyPartTransforms(descriptor, duration: 0)
            animateDelight(descriptor)
        case .partialSuccess where descriptor.isAnimated && event != nil:
            applyPartTransforms(descriptor, duration: 0)
            animatePartialSuccess(descriptor)
        case .puzzled where descriptor.isAnimated && event != nil:
            applyPartTransforms(descriptor, duration: 0)
            animatePuzzled(descriptor)
        default:
            applyPartTransforms(descriptor, duration: descriptor.duration)
        }

        if case .curious = mood, !previous.isCurious, descriptor.isAnimated {
            animateGreetingArm(final: transform(descriptor.rightArm))
        }
    }

    private func applyPartTransforms(_ descriptor: RobotMotionDescriptor, duration: TimeInterval) {
        animateTransform(bodyLayer, to: transform(descriptor.body), duration: duration, key: "robot.body.pose")
        animateTransform(faceLayer, to: transform(descriptor.face), duration: duration, key: "robot.face.pose")
        animateTransform(lidLayer, to: transform(descriptor.lid), duration: duration, key: "robot.lid.pose")
        animateTransform(leftArmLayer, to: transform(descriptor.leftArm), duration: duration, key: "robot.left-arm.pose")
        animateTransform(rightArmLayer, to: transform(descriptor.rightArm), duration: duration, key: "robot.right-arm.pose")
        let eyeTransform = RobotPartTransform(translation: descriptor.pupilOffset)
        animateTransform(leftEyeLayer, to: transform(eyeTransform), duration: duration, key: "robot.left-eye.gaze")
        animateTransform(rightEyeLayer, to: transform(eyeTransform), duration: duration, key: "robot.right-eye.gaze")
        animateTransform(shadowLayer, to: CATransform3DMakeScale(descriptor.shadowScale, 1, 1),
                         duration: duration, key: "robot.shadow.pose")
        animateOpacity(shadowLayer, to: quietOrbitEnabled ? 0 : Float(descriptor.shadowOpacity), duration: duration, key: "robot.shadow.opacity")
        if descriptor.intakeProgress == 0 { animateOpacity(intakeLayer, to: 0, duration: min(0.12, duration), key: "robot.intake.opacity") }
    }

    private func applyExpression(_ mood: RobotMood, duration: TimeInterval) {
        let scales: (CGFloat, CGFloat)
        switch mood {
        case .delighted: scales = (0.30, 0.30)
        case .partialSuccess: scales = (0.38, 1)
        case .puzzled: scales = (1, 0.48)
        case .hungry: scales = (1.16, 1.16)
        default: scales = (1, 1)
        }
        animateEyeScale(leftEyeLayer, scaleY: scales.0, duration: duration, key: "robot.left-eye.expression")
        animateEyeScale(rightEyeLayer, scaleY: scales.1, duration: duration, key: "robot.right-eye.expression")
        animatePath(mouthLayer, to: mouthPath(for: mood), duration: duration, key: "robot.mouth.expression")
    }

    private func animateDigest(_ descriptor: RobotMotionDescriptor) {
        removeAnimations(withPrefix: "robot.digest")
        let bodyValues = [
            RobotPartTransform.identity,
            RobotPartTransform(translation: CGPoint(x: 0, y: 1.2), scaleX: 1.07, scaleY: 0.87),
            RobotPartTransform(translation: CGPoint(x: 0, y: -1.0), scaleX: 0.96, scaleY: 1.07),
            RobotPartTransform(translation: CGPoint(x: 0, y: 0.8), scaleX: 1.04, scaleY: 0.94),
            RobotPartTransform.identity
        ].map { NSValue(caTransform3D: transform($0)) }
        setModelTransform(bodyLayer, CATransform3DIdentity)
        addKeyframes(bodyValues, keyTimes: [0, 0.25, 0.48, 0.72, 1], duration: descriptor.duration,
                     to: bodyLayer, keyPath: "transform", key: "robot.digest.body")

        let openLid = RobotPartTransform(translation: CGPoint(x: 0, y: -5.5), rotationDegrees: -6)
        let lidValues = [openLid, .identity, openLid, .identity].map { NSValue(caTransform3D: transform($0)) }
        setModelTransform(lidLayer, CATransform3DIdentity)
        addKeyframes(lidValues, keyTimes: [0, 0.34, 0.62, 1], duration: descriptor.duration,
                     to: lidLayer, keyPath: "transform", key: "robot.digest.lid")

        withoutActions { intakeLayer.opacity = 0 }
        let intakeMotion = CAKeyframeAnimation(keyPath: "transform")
        intakeMotion.values = [
            RobotPartTransform(translation: CGPoint(x: 0, y: -7), scaleX: 0.9, scaleY: 0.9),
            RobotPartTransform(translation: CGPoint(x: 0, y: 2), scaleX: 0.82, scaleY: 0.82),
            RobotPartTransform(translation: CGPoint(x: 0, y: 18), scaleX: 0.35, scaleY: 0.35)
        ].map { NSValue(caTransform3D: transform($0)) }
        intakeMotion.keyTimes = [0, 0.48, 1]
        intakeMotion.duration = descriptor.duration * 0.82
        intakeMotion.timingFunctions = [CAMediaTimingFunction(name: .easeIn), CAMediaTimingFunction(name: .easeIn)]
        intakeLayer.add(intakeMotion, forKey: "robot.digest.intake.motion")
        let intakeOpacity = CAKeyframeAnimation(keyPath: "opacity")
        intakeOpacity.values = [0, 1, 1, 0]
        intakeOpacity.keyTimes = [0, 0.12, 0.72, 1]
        intakeOpacity.duration = descriptor.duration * 0.82
        intakeLayer.add(intakeOpacity, forKey: "robot.digest.intake.opacity")

        animateBlink(duration: descriptor.duration * 0.48, delay: descriptor.duration * 0.20,
                     keyPrefix: "robot.digest")
    }

    private func animateDelight(_ descriptor: RobotMotionDescriptor) {
        let values = [
            RobotPartTransform.identity,
            RobotPartTransform(translation: CGPoint(x: 0, y: -4), scaleX: 1.04, scaleY: 1.04),
            RobotPartTransform(translation: CGPoint(x: 0, y: 0.5), scaleX: 0.99, scaleY: 0.99),
            descriptor.body
        ].map { NSValue(caTransform3D: transform($0)) }
        addKeyframes(values, keyTimes: [0, 0.34, 0.70, 1], duration: descriptor.duration,
                     to: bodyLayer, keyPath: "transform", key: "robot.delight.body")
        let armValues = [-4.0, 25.0, -10.0, 22.0].map {
            NSValue(caTransform3D: transform(RobotPartTransform(rotationDegrees: CGFloat($0))))
        }
        addKeyframes(armValues, keyTimes: [0, 0.34, 0.68, 1], duration: descriptor.duration,
                     to: rightArmLayer, keyPath: "transform", key: "robot.delight.wave")
    }

    private func animatePartialSuccess(_ descriptor: RobotMotionDescriptor) {
        let values = [0.0, -4.0, 3.0, -3.0].map {
            NSValue(caTransform3D: transform(RobotPartTransform(rotationDegrees: CGFloat($0))))
        }
        addKeyframes(values, keyTimes: [0, 0.30, 0.68, 1], duration: descriptor.duration,
                     to: bodyLayer, keyPath: "transform", key: "robot.partial.body")
    }

    private func animatePuzzled(_ descriptor: RobotMotionDescriptor) {
        let values = [0.0, 6.0, 3.5, 5.0].map {
            NSValue(caTransform3D: transform(RobotPartTransform(rotationDegrees: CGFloat($0))))
        }
        addKeyframes(values, keyTimes: [0, 0.34, 0.70, 1], duration: descriptor.duration,
                     to: bodyLayer, keyPath: "transform", key: "robot.puzzled.body")
    }

    private func animateGreetingArm(final: CATransform3D) {
        let values = [0.0, 18.0, -5.0].map {
            NSValue(caTransform3D: transform(RobotPartTransform(rotationDegrees: CGFloat($0))))
        } + [NSValue(caTransform3D: final)]
        addKeyframes(values, keyTimes: [0, 0.34, 0.68, 1], duration: 0.44,
                     to: rightArmLayer, keyPath: "transform", key: "robot.greeting.wave")
    }

    // MARK: - Ambient personality

    private func updateAmbientMotion(reduceMotion: Bool) {
        let descriptor = RobotMotionDescriptor.make(for: .mood(mood), reduceMotion: reduceMotion)
        guard !quietOrbitEnabled, descriptor.allowsAmbientMotion, motionState.isVisible else {
            stopAmbientMotion()
            return
        }
        guard ambientTask == nil else { return }
        ambientTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2.6)) }
                catch { return }
                guard let self, self.motionState.isVisible, !self.reduceMotionProvider() else { return }
                self.animateBlink(duration: 0.17, keyPrefix: "robot.ambient")
                do { try await Task.sleep(for: .seconds(1.7)) }
                catch { return }
                guard self.mood == .idle else { continue }
                self.animateIdleGlance()
                do { try await Task.sleep(for: .seconds(2.4)) }
                catch { return }
                guard self.mood == .idle else { continue }
                self.animateIdleShrug()
            }
        }
    }

    private func stopAmbientMotion() {
        ambientTask?.cancel()
        ambientTask = nil
        removeAnimations(withPrefix: "robot.ambient")
    }

    private func animateBlink(duration: TimeInterval, delay: TimeInterval = 0, keyPrefix: String) {
        for (index, eye) in [leftEyeLayer, rightEyeLayer].enumerated() {
            let animation = CAKeyframeAnimation(keyPath: "transform.scale.y")
            animation.values = [1, 0.10, 1]
            animation.keyTimes = [0, 0.46, 1]
            animation.duration = duration
            animation.beginTime = CACurrentMediaTime() + delay + Double(index) * 0.018
            animation.timingFunctions = [CAMediaTimingFunction(name: .easeIn), CAMediaTimingFunction(name: .easeOut)]
            eye.add(animation, forKey: "\(keyPrefix).blink.\(index)")
        }
    }

    private func animateIdleGlance() {
        let values = [-1.6, 1.2, 0].map {
            NSValue(caTransform3D: transform(RobotPartTransform(translation: CGPoint(x: CGFloat($0), y: 0))))
        }
        for (index, eye) in [leftEyeLayer, rightEyeLayer].enumerated() {
            addKeyframes(values, keyTimes: [0, 0.58, 1], duration: 0.62,
                         to: eye, keyPath: "transform", key: "robot.ambient.glance.\(index)")
        }
    }

    private func animateIdleShrug() {
        let left = [-2.0, -12.0, 3.0, 0.0].map {
            NSValue(caTransform3D: transform(RobotPartTransform(rotationDegrees: CGFloat($0))))
        }
        let right = [2.0, 12.0, -3.0, 0.0].map {
            NSValue(caTransform3D: transform(RobotPartTransform(rotationDegrees: CGFloat($0))))
        }
        addKeyframes(left, keyTimes: [0, 0.34, 0.68, 1], duration: 0.52,
                     to: leftArmLayer, keyPath: "transform", key: "robot.ambient.shrug.left")
        addKeyframes(right, keyTimes: [0, 0.34, 0.68, 1], duration: 0.52,
                     to: rightArmLayer, keyPath: "transform", key: "robot.ambient.shrug.right")
    }

    // MARK: - Animation helpers

    private func applyHiddenPose() {
        resetAutomaticCelebrationLayers()
        let descriptor = RobotMotionDescriptor.make(for: .hide(motionState.entrance), reduceMotion: true)
        withoutActions {
            artLayer.opacity = 1
            bodyLayer.transform = transform(descriptor.body)
            faceLayer.transform = CATransform3DIdentity
            lidLayer.transform = CATransform3DIdentity
            leftArmLayer.transform = CATransform3DIdentity
            rightArmLayer.transform = CATransform3DIdentity
            leftEyeLayer.transform = CATransform3DIdentity
            rightEyeLayer.transform = CATransform3DIdentity
            intakeLayer.opacity = 0
            shadowLayer.opacity = 0
            for layer in [autoTokenLayer, autoPropLayer, autoPropDetailLayer, islandGripLayer, autoSuccessBadgeLayer,
                          autoSuccessCheckLayer, autoFlashLayer, autoConfettiLayer] {
                layer.transform = CATransform3DIdentity
                layer.opacity = 0
            }
            for piece in autoConfettiPieces { piece.transform = CATransform3DIdentity }
        }
    }

    private func removeAllAnimations() {
        for layer in [artLayer, shadowLayer, bodyLayer, shellLayer, faceLayer, faceScreenLayer,
                      leftEyeLayer, rightEyeLayer, mouthLayer, lidLayer, leftArmLayer,
                      rightArmLayer, intakeLayer, autoPropLayer, autoPropDetailLayer,
                      autoSuccessBadgeLayer, autoSuccessCheckLayer, autoFlashLayer,
                      autoConfettiLayer, autoTokenLayer, autoCountLayer, islandGripLayer, feetLayer] + autoConfettiPieces + islandRigLayers {
            layer.removeAllAnimations()
        }
    }

    private func removeAnimations(withPrefix prefix: String) {
        for layer in [shadowLayer, bodyLayer, faceLayer, leftEyeLayer, rightEyeLayer,
                      mouthLayer, lidLayer, leftArmLayer, rightArmLayer, intakeLayer,
                      autoPropLayer, autoPropDetailLayer, autoSuccessBadgeLayer,
                      autoSuccessCheckLayer, autoFlashLayer, autoConfettiLayer, autoTokenLayer, autoCountLayer, islandGripLayer, feetLayer] + autoConfettiPieces + islandRigLayers {
            for key in layer.animationKeys() ?? [] where key.hasPrefix(prefix) {
                layer.removeAnimation(forKey: key)
            }
        }
    }

    private func animateTransform(_ layer: CALayer, to target: CATransform3D,
                                  duration: TimeInterval, key: String) {
        let source = layer.presentation()?.transform ?? layer.transform
        setModelTransform(layer, target)
        guard duration > 0 else { layer.removeAnimation(forKey: key); return }
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: source)
        animation.toValue = NSValue(caTransform3D: target)
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: key)
    }

    private func animateEyeScale(_ layer: CALayer, scaleY: CGFloat,
                                 duration: TimeInterval, key: String) {
        let current = layer.presentation()?.value(forKeyPath: "transform.scale.y") as? CGFloat ?? 1
        withoutActions { layer.setValue(scaleY, forKeyPath: "transform.scale.y") }
        guard duration > 0 else { layer.removeAnimation(forKey: key); return }
        let animation = CABasicAnimation(keyPath: "transform.scale.y")
        animation.fromValue = current
        animation.toValue = scaleY
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: key)
    }

    private func animateOpacity(_ layer: CALayer, to target: Float,
                                duration: TimeInterval, key: String) {
        let source = layer.presentation()?.opacity ?? layer.opacity
        withoutActions { layer.opacity = target }
        guard duration > 0 else { layer.removeAnimation(forKey: key); return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = source
        animation.toValue = target
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: key)
    }

    private func animatePath(_ layer: CAShapeLayer, to target: CGPath,
                             duration: TimeInterval, key: String) {
        let source = layer.presentation()?.path ?? layer.path
        withoutActions { layer.path = target }
        guard duration > 0, let source else { layer.removeAnimation(forKey: key); return }
        let animation = CABasicAnimation(keyPath: "path")
        animation.fromValue = source
        animation.toValue = target
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: key)
    }

    private func addKeyframes(_ values: [Any], keyTimes: [NSNumber], duration: TimeInterval,
                              to layer: CALayer, keyPath: String, key: String) {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = keyTimes
        animation.duration = duration
        animation.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut),
                                          count: max(0, values.count - 1))
        layer.add(animation, forKey: key)
    }

    private func setModelTransform(_ layer: CALayer, _ value: CATransform3D) {
        withoutActions { layer.transform = value }
    }

    private func withoutActions(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }

    private func transform(_ part: RobotPartTransform) -> CATransform3D {
        var value = CATransform3DIdentity
        value = CATransform3DTranslate(value, part.translation.x, part.translation.y, 0)
        value = CATransform3DRotate(value, part.rotationDegrees * .pi / 180, 0, 0, 1)
        value = CATransform3DScale(value, part.scaleX, part.scaleY, 1)
        return value
    }

    private func mouthPath(for mood: RobotMood) -> CGPath {
        let path = CGMutablePath()
        switch mood {
        case .hungry:
            path.addRoundedRect(in: CGRect(x: 30.5, y: 39.7, width: 3, height: 3.8),
                                cornerWidth: 0.45, cornerHeight: 0.45)
        case .delighted:
            path.move(to: CGPoint(x: 28.8, y: 40.7))
            path.addLine(to: CGPoint(x: 30.6, y: 43))
            path.addLine(to: CGPoint(x: 33.4, y: 43))
            path.addLine(to: CGPoint(x: 35.2, y: 40.7))
        case .partialSuccess:
            path.move(to: CGPoint(x: 29.4, y: 42))
            path.addLine(to: CGPoint(x: 32, y: 42.8))
            path.addLine(to: CGPoint(x: 34.6, y: 41.4))
        case .puzzled:
            path.move(to: CGPoint(x: 29.4, y: 42.8))
            path.addLine(to: CGPoint(x: 32, y: 41.6))
            path.addLine(to: CGPoint(x: 34.6, y: 42.8))
        case .digesting:
            path.move(to: CGPoint(x: 29.5, y: 42))
            path.addLine(to: CGPoint(x: 34.5, y: 42))
        default:
            path.move(to: orbitPoint(194, 106))
            path.addLine(to: orbitPoint(197, 109))
            path.addLine(to: orbitPoint(203, 109))
            path.addLine(to: orbitPoint(206, 106))
        }
        return path
    }

    private static func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(red: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255,
                alpha: alpha)
    }
}

private extension RobotMood {
    var isCurious: Bool {
        if case .curious = self { return true }
        return false
    }
}
