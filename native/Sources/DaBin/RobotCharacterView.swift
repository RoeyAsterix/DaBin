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

    private let artLayer = CALayer()
    private let shadowLayer = CAShapeLayer()
    private let bodyLayer = CALayer()
    private let shellLayer = CALayer()
    private let faceLayer = CALayer()
    private let faceScreenLayer = CAShapeLayer()
    private let leftEyeLayer = CAShapeLayer()
    private let rightEyeLayer = CAShapeLayer()
    private let mouthLayer = CAShapeLayer()
    private let lidLayer = CALayer()
    private let leftArmLayer = CAShapeLayer()
    private let rightArmLayer = CAShapeLayer()
    private let intakeLayer = CAShapeLayer()

    private static let designSize = CGSize(width: 64, height: 78)

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

    override func layout() {
        super.layout()
        let scale = min(bounds.width / Self.designSize.width, bounds.height / Self.designSize.height)
        withoutActions {
            artLayer.bounds = CGRect(origin: .zero, size: Self.designSize)
            artLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
            artLayer.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        }
    }

    func send(_ event: RobotMotionEvent) {
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
        let reduceMotion = reduceMotionProvider()
        if reduceMotion {
            stopAmbientMotion()
            removeAllAnimations()
        }
        guard mood != .hidden else { applyHiddenPose(); return }
        applyMood(mood, previous: mood, event: nil, reduceMotion: reduceMotion)
        updateAmbientMotion(reduceMotion: reduceMotion)
    }

    /// One-way visual cleanup for panel hiding and application shutdown.
    func stopMotion() {
        motionState.send(.hide)
        stopAmbientMotion()
        removeAllAnimations()
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

        configureShadow()
        configureContainer(leftArmLayer, anchor: CGPoint(x: 13, y: 45))
        configureContainer(rightArmLayer, anchor: CGPoint(x: 51, y: 45))
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

    private func configureArms() {
        let left = CGMutablePath()
        left.move(to: CGPoint(x: 14, y: 43))
        left.addCurve(to: CGPoint(x: 12, y: 54), control1: CGPoint(x: 7, y: 42), control2: CGPoint(x: 5, y: 51))
        leftArmLayer.path = left
        styleArm(leftArmLayer)

        let right = CGMutablePath()
        right.move(to: CGPoint(x: 50, y: 43))
        right.addCurve(to: CGPoint(x: 52, y: 54), control1: CGPoint(x: 57, y: 42), control2: CGPoint(x: 59, y: 51))
        rightArmLayer.path = right
        styleArm(rightArmLayer)
    }

    private func styleArm(_ layer: CAShapeLayer) {
        layer.fillColor = nil
        layer.strokeColor = Self.color(0x59466E)
        layer.lineWidth = 4
        layer.lineCap = .round
    }

    private func configureShell() {
        let feet = CAShapeLayer()
        let feetPath = CGMutablePath()
        feetPath.addRoundedRect(in: CGRect(x: 16, y: 62, width: 12, height: 9), cornerWidth: 2, cornerHeight: 2)
        feetPath.addRoundedRect(in: CGRect(x: 36, y: 62, width: 12, height: 9), cornerWidth: 2, cornerHeight: 2)
        feet.path = feetPath
        feet.fillColor = Self.color(0x4A3A62)
        shellLayer.addSublayer(feet)

        let shellPath = CGPath(roundedRect: CGRect(x: 12, y: 20, width: 40, height: 46),
                               cornerWidth: 10, cornerHeight: 10, transform: nil)
        let shellMask = CAShapeLayer()
        shellMask.path = shellPath
        let gradient = CAGradientLayer()
        gradient.frame = CGRect(origin: .zero, size: Self.designSize)
        gradient.colors = [Self.color(0xB89CCF), Self.color(0x765D94), Self.color(0x503E6E)]
        gradient.locations = [0, 0.53, 1]
        gradient.startPoint = CGPoint(x: 0.15, y: 0.12)
        gradient.endPoint = CGPoint(x: 0.82, y: 0.9)
        gradient.mask = shellMask
        shellLayer.addSublayer(gradient)

        let outline = CAShapeLayer()
        outline.path = shellPath
        outline.fillColor = nil
        outline.strokeColor = Self.color(0x433451)
        outline.lineWidth = 1.5
        shellLayer.addSublayer(outline)

        let highlight = CAShapeLayer()
        let highlightPath = CGMutablePath()
        highlightPath.move(to: CGPoint(x: 16, y: 25))
        highlightPath.addLine(to: CGPoint(x: 16, y: 57))
        highlightPath.addCurve(to: CGPoint(x: 20, y: 63), control1: CGPoint(x: 16, y: 60), control2: CGPoint(x: 18, y: 62))
        highlight.path = highlightPath
        highlight.fillColor = nil
        highlight.strokeColor = Self.color(0xE2D1EF, alpha: 0.63)
        highlight.lineWidth = 1.2
        highlight.lineCap = .round
        shellLayer.addSublayer(highlight)

        let slot = CAShapeLayer()
        slot.path = CGPath(roundedRect: CGRect(x: 23, y: 55, width: 18, height: 5),
                           cornerWidth: 2.5, cornerHeight: 2.5, transform: nil)
        slot.fillColor = Self.color(0x30263C)
        slot.strokeColor = Self.color(0xB398C7)
        slot.lineWidth = 0.8
        shellLayer.addSublayer(slot)
    }

    private func configureFace() {
        faceScreenLayer.path = CGPath(roundedRect: CGRect(x: 18, y: 30, width: 28, height: 20),
                                      cornerWidth: 6, cornerHeight: 6, transform: nil)
        faceScreenLayer.fillColor = Self.color(0x292338)
        faceScreenLayer.strokeColor = Self.color(0xB49CC7)
        faceScreenLayer.lineWidth = 1
        faceLayer.addSublayer(faceScreenLayer)

        for (eye, center) in [(leftEyeLayer, CGPoint(x: 26, y: 39)),
                              (rightEyeLayer, CGPoint(x: 38, y: 39))] {
            eye.path = CGPath(roundedRect: CGRect(x: center.x - 2.8, y: center.y - 2.3, width: 5.6, height: 4.6),
                              cornerWidth: 2.3, cornerHeight: 2.3, transform: nil)
            eye.fillColor = Self.color(0xD7F4EF)
            eye.shadowColor = Self.color(0xBCEBFF)
            eye.shadowOpacity = 0.22
            eye.shadowRadius = 2
            eye.shadowOffset = .zero
            faceLayer.addSublayer(eye)
        }

        mouthLayer.path = mouthPath(for: .idle)
        mouthLayer.fillColor = nil
        mouthLayer.strokeColor = Self.color(0x96CEC9)
        mouthLayer.lineWidth = 1.1
        mouthLayer.lineCap = .round
        faceLayer.addSublayer(mouthLayer)
    }

    private func configureIntakeCard() {
        intakeLayer.path = CGPath(roundedRect: CGRect(x: 27.5, y: 2, width: 9, height: 12),
                                  cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)
        intakeLayer.fillColor = Self.color(0xFBF7FF)
        intakeLayer.strokeColor = Self.color(0x8E7AA7)
        intakeLayer.lineWidth = 0.8
        intakeLayer.opacity = 0
    }

    private func configureLid() {
        let lidPath = CGMutablePath()
        lidPath.move(to: CGPoint(x: 14, y: 23))
        lidPath.addLine(to: CGPoint(x: 14, y: 18))
        lidPath.addCurve(to: CGPoint(x: 21, y: 11), control1: CGPoint(x: 14, y: 14), control2: CGPoint(x: 17, y: 11))
        lidPath.addLine(to: CGPoint(x: 43, y: 11))
        lidPath.addCurve(to: CGPoint(x: 50, y: 18), control1: CGPoint(x: 47, y: 11), control2: CGPoint(x: 50, y: 14))
        lidPath.addLine(to: CGPoint(x: 50, y: 23))
        lidPath.closeSubpath()

        let mask = CAShapeLayer()
        mask.path = lidPath
        let gradient = CAGradientLayer()
        gradient.frame = CGRect(origin: .zero, size: Self.designSize)
        gradient.colors = [Self.color(0xC9B5DA), Self.color(0x6B537F)]
        gradient.startPoint = CGPoint(x: 0.2, y: 0.1)
        gradient.endPoint = CGPoint(x: 0.8, y: 0.9)
        gradient.mask = mask
        lidLayer.addSublayer(gradient)

        let outline = CAShapeLayer()
        outline.path = lidPath
        outline.fillColor = nil
        outline.strokeColor = Self.color(0x483556)
        outline.lineWidth = 1.4
        lidLayer.addSublayer(outline)

        let shine = CAShapeLayer()
        let shinePath = CGMutablePath()
        shinePath.move(to: CGPoint(x: 18, y: 16))
        shinePath.addLine(to: CGPoint(x: 46, y: 16))
        shine.path = shinePath
        shine.fillColor = nil
        shine.strokeColor = Self.color(0xE9D9F1, alpha: 0.7)
        shine.lineWidth = 1
        shine.lineCap = .round
        lidLayer.addSublayer(shine)
    }

    // MARK: - State presentation

    private func animateReveal(from entrance: RobotEntrance, reduceMotion: Bool) {
        removeAllAnimations()
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
        animateOpacity(shadowLayer, to: Float(descriptor.shadowOpacity), duration: descriptor.duration, key: "robot.reveal.shadow")
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
        animateOpacity(shadowLayer, to: Float(descriptor.shadowOpacity), duration: duration, key: "robot.shadow.opacity")
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
        guard descriptor.allowsAmbientMotion, motionState.isVisible else {
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
        let descriptor = RobotMotionDescriptor.make(for: .hide(motionState.entrance), reduceMotion: true)
        withoutActions {
            bodyLayer.transform = transform(descriptor.body)
            faceLayer.transform = CATransform3DIdentity
            lidLayer.transform = CATransform3DIdentity
            leftArmLayer.transform = CATransform3DIdentity
            rightArmLayer.transform = CATransform3DIdentity
            leftEyeLayer.transform = CATransform3DIdentity
            rightEyeLayer.transform = CATransform3DIdentity
            intakeLayer.opacity = 0
            shadowLayer.opacity = 0
        }
    }

    private func removeAllAnimations() {
        for layer in [artLayer, shadowLayer, bodyLayer, shellLayer, faceLayer, faceScreenLayer,
                      leftEyeLayer, rightEyeLayer, mouthLayer, lidLayer, leftArmLayer,
                      rightArmLayer, intakeLayer] {
            layer.removeAllAnimations()
        }
    }

    private func removeAnimations(withPrefix prefix: String) {
        for layer in [shadowLayer, bodyLayer, faceLayer, leftEyeLayer, rightEyeLayer,
                      mouthLayer, lidLayer, leftArmLayer, rightArmLayer, intakeLayer] {
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
            path.addEllipse(in: CGRect(x: 30, y: 43.2, width: 4, height: 4.5))
        case .delighted:
            path.move(to: CGPoint(x: 28.5, y: 44))
            path.addQuadCurve(to: CGPoint(x: 35.5, y: 44), control: CGPoint(x: 32, y: 49))
        case .partialSuccess:
            path.move(to: CGPoint(x: 29, y: 46))
            path.addQuadCurve(to: CGPoint(x: 35, y: 45), control: CGPoint(x: 32, y: 43.8))
        case .puzzled:
            path.move(to: CGPoint(x: 29, y: 45))
            path.addQuadCurve(to: CGPoint(x: 35, y: 46), control: CGPoint(x: 32, y: 48))
        case .digesting:
            path.move(to: CGPoint(x: 29.5, y: 45))
            path.addLine(to: CGPoint(x: 34.5, y: 45))
        default:
            path.move(to: CGPoint(x: 29, y: 45))
            path.addQuadCurve(to: CGPoint(x: 35, y: 45), control: CGPoint(x: 32, y: 47))
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
