import AppKit
import QuartzCore

/// A finite, privacy-safe success receipt. The presenter owns its window and
/// lifecycle; this decorative view cannot receive input or initiate a capture.
@MainActor
final class AutoCaptureSignView: NSView {
    var onOpen: (() -> Void)? {
        didSet {
            setAccessibilityElement(onOpen != nil)
            if onOpen != nil {
                setAccessibilityRole(.button)
                setAccessibilityIdentifier("auto-capture-companion")
                setAccessibilityLabel(accessibilityStatus)
                setAccessibilityHelp("Click once to open DaBin, even while he moves")
            }
        }
    }
    /// Artwork moves; the native target is the same neutral 44-point robot.
    var interactionBounds: CGRect {
        guard receipt != nil, !isHidden else { return .zero }
        let art = RobotCharacterView.transitionArtworkFrame(in: neutralRobotFrame)
        let body = CGRect(x: art.midX - max(64, art.width) / 2,
                      y: art.midY - max(64, art.height) / 2,
                      width: max(64, art.width), height: max(64, art.height))
        let firstPeek = CGRect(x: neutralRobotFrame.midX - 16, y: ledgeY - 13, width: 32, height: 13)
        return body.union(firstPeek).intersection(bounds)
    }
    static let plaqueSize = CGSize(width: 190, height: 32)
    static var messageFont: NSFont {
        let base = NSFont.systemFont(ofSize: 12, weight: .semibold)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: descriptor, size: 12) ?? base
    }

    private let character = RobotCharacterView(frame: .zero, reduceMotion: { true })
    private let plaque = NSView()
    private let robotContainer = CALayer()
    private let plaqueContainer = CALayer()
    private let symbolLayer = CALayer()
    private let messageLayer = CATextLayer()
    private let countLayer = CATextLayer()
    private let icon = NSImageView()
    private let message = NSTextField(labelWithString: "")
    private let count = NSTextField(labelWithString: "")
    private let countBackground = CALayer()
    private let arms = CAShapeLayer()
    private let armHighlights = CAShapeLayer()
    private let hands = CAShapeLayer()
    private let handDetails = CAShapeLayer()
    private let peekEyes = CAShapeLayer()
    private let stamp = CAShapeLayer()
    private let sceneMask = CAShapeLayer()
    private var accent = NSColor.systemPurple
    private var islandRect: CGRect?
    private var neutralRobotFrame = CGRect.zero
    private var neutralSignFrame = CGRect.zero

    private(set) var performance: AutoCaptureSignPerformance?
    private(set) var receipt: AutoCaptureSignReceipt?
    private(set) var signFrame = CGRect.zero
    private(set) var robotFrame = CGRect.zero
    private(set) var sampledNormalizedTime: Double?
    var signMessage: String { message.stringValue }
    var countText: String? { count.stringValue.isEmpty ? nil : count.stringValue }
    var messageFontSize: CGFloat { message.font?.pointSize ?? 0 }
    var messageTextFrame: CGRect { message.frame }
    var countTextFrame: CGRect { count.frame }
    var messageRequiredWidth: CGFloat { ceil(message.cell?.cellSize.width ?? message.intrinsicContentSize.width) }
    var countRequiredWidth: CGFloat { ceil(count.cell?.cellSize.width ?? count.intrinsicContentSize.width) }
    private(set) var countUsesSecondRow = false
    var usesIsland: Bool { islandRect != nil }
    var housingRect: CGRect? { islandRect }
    var reduceMotion: Bool { performance?.reduceMotion ?? false }
    var nativeArmsAreHidden: Bool { character.nativeArmsAreHidden }
    var hasArmConnection: Bool { arms.path != nil && hands.path != nil && receipt != nil }
    var hasActiveAnimations: Bool {
        ([robotContainer, plaqueContainer, arms, armHighlights, hands, handDetails, peekEyes, stamp]
            .compactMap { $0 }).contains { !($0.animationKeys() ?? []).isEmpty }
    }
    var actualSignTransform: CATransform3D { plaqueContainer.transform }
    var actualRobotTransform: CATransform3D { robotContainer.transform }
    var accessibilityStatus: String { receipt?.accessibilityText ?? "" }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.name = "autoCaptureSign.stage"
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true
        setAccessibilityElement(false)
        for (shape, name) in [(arms, "arms"), (armHighlights, "armHighlights"),
                              (hands, "hands"), (handDetails, "handDetails"),
                              (peekEyes, "peekEyes")] {
            shape.name = "autoCaptureSign.\(name)"
            shape.lineCap = .round
            shape.lineJoin = .round
            layer?.addSublayer(shape)
        }
        arms.fillColor = nil
        arms.strokeColor = QuietOrbitVisualStyle.color(0x554760)
        arms.lineWidth = 4.4
        armHighlights.fillColor = nil
        armHighlights.strokeColor = QuietOrbitVisualStyle.color(0xD4CDDC)
        armHighlights.lineWidth = 2.8
        hands.fillColor = QuietOrbitVisualStyle.color(0xD4CDDC)
        hands.strokeColor = QuietOrbitVisualStyle.color(0x766285)
        hands.lineWidth = 0.8
        handDetails.fillColor = nil
        handDetails.strokeColor = QuietOrbitVisualStyle.color(0x766285)
        handDetails.lineWidth = 0.7
        peekEyes.fillColor = QuietOrbitVisualStyle.color(QuietOrbitVisualStyle.eye)
        peekEyes.shadowColor = QuietOrbitVisualStyle.color(0x263E36)
        peekEyes.shadowOpacity = 0.45
        peekEyes.shadowRadius = 1
        peekEyes.shadowOffset = .zero
        character.setAccessibilityElement(false)
        robotContainer.name = "autoCaptureSign.robotContainer"
        layer?.addSublayer(robotContainer)
        character.mountCaptureSignArtwork(in: robotContainer)
        plaque.wantsLayer = true
        plaqueContainer.name = "autoCaptureSign.plaque"
        plaqueContainer.cornerRadius = 8
        plaqueContainer.borderWidth = 1
        plaqueContainer.shadowOpacity = 0.19
        plaqueContainer.shadowRadius = 5
        plaqueContainer.shadowOffset = CGSize(width: 0, height: -2)
        plaque.setAccessibilityElement(false)
        layer?.addSublayer(plaqueContainer)
        // Visible fingers overlap the physical upper edge of the plaque.
        hands.zPosition = 3
        handDetails.zPosition = 4
        peekEyes.zPosition = 5
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.wantsLayer = true
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        icon.setAccessibilityElement(false)
        symbolLayer.name = "autoCaptureSign.symbol"
        plaqueContainer.addSublayer(symbolLayer)
        for label in [message, count] {
            label.isSelectable = false
            label.maximumNumberOfLines = 1
            label.lineBreakMode = .byClipping
            label.cell?.wraps = false
            label.cell?.isScrollable = false
            label.setAccessibilityElement(false)

        }
        message.font = Self.messageFont
        messageLayer.font = Self.messageFont
        messageLayer.fontSize = 12
        messageLayer.alignmentMode = .left
        messageLayer.truncationMode = .none
        countLayer.alignmentMode = .center
        countLayer.truncationMode = .none
        plaqueContainer.addSublayer(messageLayer)
        plaqueContainer.addSublayer(countLayer)
        count.font = .systemFont(ofSize: 10.5, weight: .bold)
        count.alignment = .center
        countLayer.font = count.font
        countLayer.fontSize = 10.5
        countBackground.cornerRadius = 5
        plaqueContainer.insertSublayer(countBackground, at: 0)
        stamp.name = "autoCaptureSign.checkmark"
        stamp.fillColor = nil
        stamp.strokeColor = QuietOrbitVisualStyle.color(0xBCEBDD)
        stamp.lineWidth = 3
        stamp.lineJoin = .round
        stamp.lineCap = .round
        plaqueContainer.addSublayer(stamp)
        isHidden = true
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateContentsScale()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateContentsScale()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    override func layout() {
        super.layout()
        layoutScene()
    }

    /// Starts exactly one compositor timeline. No current or historical capture
    /// payload is accepted: the receipt is a closed vocabulary plus a count.
    func begin(performance: AutoCaptureSignPerformance, receipt: AutoCaptureSignReceipt,
               islandRect: CGRect?, accent: NSColor) {
        stop()
        self.performance = performance
        self.receipt = receipt
        self.islandRect = islandRect.flatMap { rectangle in
            guard [rectangle.minX, rectangle.minY, rectangle.width, rectangle.height].allSatisfy(\.isFinite),
                  rectangle.width > 0, rectangle.height > 0 else { return nil }
            return rectangle.standardized
        }
        self.accent = accent.usingColorSpace(.sRGB) ?? .systemPurple
        sampledNormalizedTime = nil
        isHidden = false
        character.prepareForCaptureSign()
        updateReceipt(receipt)
        needsLayout = true
        layoutSubtreeIfNeeded()
        let frames = sampledFrames(performance)
        let begin = CACurrentMediaTime()
        applyFrame(frames.last!, performance: performance)
        animate(frames, performance: performance, beginTime: begin)
    }

    /// Changes only the fixed message/icon/count, leaving the current clock and
    /// choreography intact when another successfully saved capture arrives.
    func updateReceipt(_ receipt: AutoCaptureSignReceipt) {
        self.receipt = receipt
        message.stringValue = receipt.count > 999_999 ? "Items saved" : receipt.message
        if onOpen != nil { setAccessibilityLabel(receipt.accessibilityText) }
        count.stringValue = receipt.count > 1 ? "×\(receipt.count)" : ""
        icon.image = NSImage(systemSymbolName: receipt.icon, accessibilityDescription: nil)
        messageLayer.string = message.stringValue
        countLayer.string = count.stringValue
        count.isHidden = receipt.count <= 1
        countLayer.isHidden = receipt.count <= 1
        countBackground.isHidden = receipt.count <= 1
        applyColors()
        layoutPlaqueContents()
    }

    func stop() {
        removeAnimationsRecursively(layer)
        for target in [robotContainer, plaqueContainer, symbolLayer, arms, armHighlights,
                       hands, handDetails, peekEyes, stamp].compactMap({ $0 }) {
            removeAnimationsRecursively(target)
        }
        character.stopMotion()
        performance = nil
        receipt = nil
        islandRect = nil
        sampledNormalizedTime = nil
        message.stringValue = ""
        count.stringValue = ""
        messageLayer.string = ""
        countLayer.string = ""
        symbolLayer.contents = nil
        icon.image = nil
        withoutActions {
            robotContainer.opacity = 0
            plaqueContainer.opacity = 0
            for shape in [arms, armHighlights, hands, handDetails, peekEyes, stamp] { shape.opacity = 0 }
        }
        isHidden = true
    }

    /// Deterministic static frame for render QA. It samples the same authored
    /// motion and kinematics used by live compositor tracks, without a timer.
    func applySample(normalizedTime: Double) {
        guard let performance else { return }
        let time = normalizedTime.isFinite ? min(1, max(0, normalizedTime)) : 0
        removeAnimationsRecursively(layer)
        sampledNormalizedTime = time
        applyFrame(performance.frame(atNormalizedTime: time), performance: performance)
        CATransaction.flush()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    func containsInteraction(_ point: CGPoint) -> Bool {
        onOpen != nil && !interactionBounds.isEmpty && interactionBounds.contains(point)
            && !(islandRect?.contains(point) ?? false)
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        containsInteraction(convert(point, from: superview)) ? self : nil
    }
    override func mouseDown(with event: NSEvent) {
        guard event.clickCount == 1, !isHidden else { return }
        onOpen?()
    }
    override func accessibilityPerformPress() -> Bool {
        guard !isHidden, let onOpen else { return false }
        onOpen(); return true
    }

    private var ledgeY: CGFloat { min(bounds.maxY - (usesIsland ? 0 : 8), islandRect?.minY ?? bounds.maxY) }

    private func layoutScene() {
        let scale: CGFloat = 0.92
        let center = CGPoint(x: islandRect?.midX ?? bounds.midX, y: ledgeY)
        neutralRobotFrame = CGRect(x: center.x - 32 * scale,
                                  y: center.y + 20 * scale - 8 - 78 * scale,
                                  width: 64 * scale, height: 78 * scale)
        let size = CGSize(width: min(Self.plaqueSize.width, max(0, bounds.width - 24)),
                          height: Self.plaqueSize.height)
        neutralSignFrame = CGRect(x: center.x - size.width / 2, y: center.y - 78 - size.height / 2,
                                 width: size.width, height: size.height)
        withoutActions {
            if character.frame != neutralRobotFrame { character.frame = neutralRobotFrame }
            if plaque.frame != neutralSignFrame { plaque.frame = neutralSignFrame }
            robotContainer.bounds = CGRect(origin: .zero, size: neutralRobotFrame.size)
            robotContainer.position = CGPoint(x: neutralRobotFrame.midX, y: neutralRobotFrame.midY)
            plaqueContainer.bounds = CGRect(origin: .zero, size: neutralSignFrame.size)
            plaqueContainer.position = CGPoint(x: neutralSignFrame.midX, y: neutralSignFrame.midY)
            let path = CGMutablePath()
            path.addRect(bounds)
            if let islandRect {
                let camera = islandRect.intersection(bounds)
                if !camera.isNull && !camera.isEmpty { path.addRect(camera) }
            }
            sceneMask.fillRule = .evenOdd
            sceneMask.frame = bounds
            sceneMask.path = path
            layer?.mask = sceneMask
            let eyes = CGMutablePath()
            for x in [center.x - 9, center.x + 4] {
                eyes.addRect(CGRect(x: x, y: ledgeY - 7, width: 5, height: 5))
            }
            peekEyes.path = eyes
        }
        character.layoutSubtreeIfNeeded()
        layoutPlaqueContents()
        updateContentsScale()
    }

    private func layoutPlaqueContents() {
        let width = plaque.bounds.width
        let height = plaque.bounds.height
        let hasCount = (receipt?.count ?? 1) > 1
        let countWidth: CGFloat = hasCount ? max(20, countRequiredWidth + 2) : 0
        countUsesSecondRow = hasCount && width - 40 - countWidth < messageRequiredWidth
        withoutActions {
            if countUsesSecondRow {
                // Very large bursts keep their exact number and readable type
                // size in a second line inside the same constant-size plaque.
                // The robot's animated grip points never shift during updates.
                icon.frame = CGRect(x: 9, y: height - 16, width: 14, height: 14)
                message.frame = CGRect(x: 30, y: height - 18, width: max(0, width - 38), height: 18)
                let badgeWidth = min(max(0, width - 12), countWidth + 8)
                count.frame = CGRect(x: (width - badgeWidth) / 2, y: 0, width: badgeWidth, height: 14)
                countBackground.frame = count.frame.insetBy(dx: 0, dy: -0.5)
            } else {
                icon.frame = CGRect(x: 9, y: (height - 16) / 2, width: 16, height: 16)
                message.frame = CGRect(x: 30, y: (height - 18) / 2,
                                       width: max(0, width - 38 - countWidth), height: 18)
                count.frame = CGRect(x: width - 7 - countWidth, y: (height - 16) / 2,
                                     width: countWidth, height: 16)
                countBackground.frame = count.frame.insetBy(dx: -1, dy: -2)
            }
            let check = CGMutablePath()
            let iconCenter = CGPoint(x: icon.frame.midX, y: icon.frame.midY)
            check.move(to: CGPoint(x: iconCenter.x - 6, y: iconCenter.y))
            check.addLine(to: CGPoint(x: iconCenter.x - 2, y: iconCenter.y - 4))
            check.addLine(to: CGPoint(x: iconCenter.x + 6, y: iconCenter.y + 5))
            stamp.path = check
            symbolLayer.frame = icon.frame
            messageLayer.frame = message.frame.insetBy(dx: 2, dy: 1)
            countLayer.frame = count.frame.insetBy(dx: 2, dy: 0)
        }
    }

    private func applyColors() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        withoutActions {
            plaqueContainer.backgroundColor = QuietOrbitVisualStyle.color(dark ? 0x33283F : 0xFBF7FF)
            plaqueContainer.borderColor = accent.withAlphaComponent(dark ? 0.78 : 0.62).cgColor
            plaqueContainer.shadowColor = QuietOrbitVisualStyle.color(0x18101F)
            countBackground.backgroundColor = accent.withAlphaComponent(dark ? 0.28 : 0.13).cgColor
            stamp.strokeColor = QuietOrbitVisualStyle.color(dark ? 0xBCEBDD : 0x27755F)
        }
        message.textColor = NSColor(cgColor: QuietOrbitVisualStyle.color(dark ? 0xF9F5FE : 0x382647))
        count.textColor = message.textColor
        icon.contentTintColor = accent
        messageLayer.foregroundColor = message.textColor?.cgColor
        countLayer.foregroundColor = count.textColor?.cgColor
        updateSymbolContents()
    }

    private func updateSymbolContents() {
        guard let image = icon.image?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)) else {
            symbolLayer.contents = nil
            return
        }
        let backing = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let pixels = max(16, Int(ceil(16 * backing)))
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        let context = graphics.cgContext
        context.scaleBy(x: CGFloat(pixels) / 16, y: CGFloat(pixels) / 16)
        image.draw(in: CGRect(x: 0, y: 0, width: 16, height: 16), from: .zero,
                   operation: .sourceOver, fraction: 1)
        context.setBlendMode(.sourceIn)
        context.setFillColor(accent.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        NSGraphicsContext.restoreGraphicsState()
        withoutActions {
            symbolLayer.contents = bitmap.cgImage
            symbolLayer.contentsScale = backing
            symbolLayer.contentsGravity = .resizeAspect
        }
    }

    private func sampledFrames(_ performance: AutoCaptureSignPerformance) -> [AutoCaptureSignFrame] {
        let count = max(2, Int(ceil(performance.totalDuration * 60)))
        let times = Set((0...count).map { Double($0) / Double(count) }
            + performance.frames.map(\.normalizedTime))
        return times.sorted().map { performance.frame(atNormalizedTime: $0) }
    }

    private func robotTransform(_ frame: AutoCaptureSignFrame) -> CATransform3D {
        transform(x: frame.robotTranslationX, y: frame.robotTranslationY,
                  scaleX: frame.robotScaleX, scaleY: frame.robotScaleY,
                  angle: frame.robotRotationDegrees)
    }

    private func signTransform(_ frame: AutoCaptureSignFrame) -> CATransform3D {
        // A mechanical flip is a horizontal fold. Keeping its projection in
        // two dimensions makes native cached renders match the compositor and
        // lets connected fingers follow the exact same projected board edge.
        transform(x: frame.signTranslationX, y: frame.signTranslationY,
                  scaleX: frame.signScaleX * cos(frame.signYRotationDegrees * .pi / 180),
                  scaleY: frame.signScaleY, angle: frame.signRotationDegrees)
    }

    private func transform(x: CGFloat, y: CGFloat, scaleX: CGFloat, scaleY: CGFloat,
                           angle: CGFloat) -> CATransform3D {
        var value = CATransform3DIdentity
        value = CATransform3DTranslate(value, x, y, 0)
        value = CATransform3DRotate(value, angle * .pi / 180, 0, 0, 1)
        return CATransform3DScale(value, scaleX, scaleY, 1)
    }

    private func transformedPoint(_ point: CGPoint, in rectangle: CGRect,
                                  x: CGFloat, y: CGFloat, scaleX: CGFloat, scaleY: CGFloat,
                                  angle: CGFloat, yAngle: CGFloat = 0) -> CGPoint {
        let radians = angle * .pi / 180
        let dx = (point.x - rectangle.midX) * scaleX * cos(yAngle * .pi / 180)
        let dy = (point.y - rectangle.midY) * scaleY
        return CGPoint(x: rectangle.midX + x + dx * cos(radians) - dy * sin(radians),
                       y: rectangle.midY + y + dx * sin(radians) + dy * cos(radians))
    }

    private func shoulder(_ left: Bool, frame: AutoCaptureSignFrame) -> CGPoint {
        let scale = neutralRobotFrame.width / 64
        let shoulderY = 66 + (40.58 - 66) * frame.torsoScaleY
        let point = CGPoint(x: neutralRobotFrame.minX + (left ? 12.26 : 51.74) * scale,
                            y: neutralRobotFrame.maxY - shoulderY * scale)
        return transformedPoint(point, in: neutralRobotFrame, x: frame.robotTranslationX,
                                y: frame.robotTranslationY, scaleX: frame.robotScaleX,
                                scaleY: frame.robotScaleY, angle: frame.robotRotationDegrees)
    }

    private func grip(_ left: Bool, pose: AutoCaptureSignArmPose, frame: AutoCaptureSignFrame) -> CGPoint {
        let side: CGFloat = left ? -1 : 1
        switch pose {
        case .ledgeGrip:
            guard usesIsland else {
                let start = shoulder(left, frame: frame)
                return CGPoint(x: start.x + side * 4, y: start.y - 12)
            }
            return CGPoint(x: neutralRobotFrame.midX + side * 18, y: ledgeY - 1)
        case .rest:
            let start = shoulder(left, frame: frame)
            return CGPoint(x: start.x + side * 5, y: start.y - 17)
        case .bow:
            let start = shoulder(left, frame: frame)
            return CGPoint(x: start.x + side * 7, y: start.y - 11)
        case .stamp:
            return transformedPoint(CGPoint(x: neutralSignFrame.minX + icon.frame.midX,
                                             y: neutralSignFrame.minY + icon.frame.midY),
                in: neutralSignFrame, x: frame.signTranslationX, y: frame.signTranslationY,
                scaleX: frame.signScaleX, scaleY: frame.signScaleY, angle: frame.signRotationDegrees,
                yAngle: frame.signYRotationDegrees)
        case .catchReach:
            return transformedPoint(CGPoint(x: neutralSignFrame.midX + side * 44, y: neutralSignFrame.maxY),
                in: neutralSignFrame, x: frame.signTranslationX, y: frame.signTranslationY,
                scaleX: frame.signScaleX, scaleY: frame.signScaleY, angle: frame.signRotationDegrees,
                yAngle: frame.signYRotationDegrees)
        case .hangGrip:
            return transformedPoint(CGPoint(x: neutralSignFrame.midX + side * 37, y: neutralSignFrame.minY + 1),
                in: neutralSignFrame, x: frame.signTranslationX, y: frame.signTranslationY,
                scaleX: frame.signScaleX, scaleY: frame.signScaleY, angle: frame.signRotationDegrees,
                yAngle: frame.signYRotationDegrees)
        case .signRaise:
            return transformedPoint(CGPoint(x: neutralSignFrame.midX + side * min(64, neutralSignFrame.width * 0.34),
                                             y: neutralSignFrame.minY + 1),
                in: neutralSignFrame, x: frame.signTranslationX, y: frame.signTranslationY,
                scaleX: frame.signScaleX, scaleY: frame.signScaleY, angle: frame.signRotationDegrees,
                yAngle: frame.signYRotationDegrees)
        case .signHold, .brace, .present, .recover:
            return transformedPoint(CGPoint(x: neutralSignFrame.midX + side * min(64, neutralSignFrame.width * 0.34),
                                             y: neutralSignFrame.maxY - 1),
                in: neutralSignFrame, x: frame.signTranslationX, y: frame.signTranslationY,
                scaleX: frame.signScaleX, scaleY: frame.signScaleY, angle: frame.signRotationDegrees,
                yAngle: frame.signYRotationDegrees)
        }
    }

    private func interpolatedGrip(_ left: Bool, frame: AutoCaptureSignFrame,
                                  performance: AutoCaptureSignPerformance) -> CGPoint {
        let keyframes = performance.frames
        guard let last = keyframes.last else {
            return grip(left, pose: left ? frame.leftArmPose : frame.rightArmPose, frame: frame)
        }
        for index in 1..<keyframes.count where frame.normalizedTime <= keyframes[index].normalizedTime {
            let first = keyframes[index - 1]
            let second = keyframes[index]
            let span = second.normalizedTime - first.normalizedTime
            let value = span > 0 ? min(1, max(0, (frame.normalizedTime - first.normalizedTime) / span)) : 1
            let eased = value * value * (3 - 2 * value)
            let start = grip(left, pose: left ? first.leftArmPose : first.rightArmPose, frame: frame)
            let end = grip(left, pose: left ? second.leftArmPose : second.rightArmPose, frame: frame)
            return CGPoint(x: start.x + (end.x - start.x) * eased,
                           y: start.y + (end.y - start.y) * eased)
        }
        return grip(left, pose: left ? last.leftArmPose : last.rightArmPose, frame: frame)
    }

    private func limbPaths(_ frame: AutoCaptureSignFrame,
                           performance: AutoCaptureSignPerformance) -> (arms: CGPath, hands: CGPath, details: CGPath) {
        let armPath = CGMutablePath()
        let handPath = CGMutablePath()
        let details = CGMutablePath()
        for left in [true, false] {
            let start = shoulder(left, frame: frame)
            let end = interpolatedGrip(left, frame: frame, performance: performance)
            let side: CGFloat = left ? -1 : 1
            let elbow = CGPoint(x: start.x + (end.x - start.x) * 0.5 + side * 3,
                                y: (start.y + end.y) * 0.5 - 3)
            armPath.move(to: start)
            armPath.addLine(to: elbow)
            armPath.addLine(to: end)
            handPath.addEllipse(in: CGRect(x: elbow.x - 2.5, y: elbow.y - 2.5, width: 5, height: 5))
            handPath.addRoundedRect(in: CGRect(x: end.x - 4, y: end.y - 3, width: 8, height: 6),
                                    cornerWidth: 1.5, cornerHeight: 1.5)
            for offset: CGFloat in [-1.3, 1.3] {
                details.move(to: CGPoint(x: end.x + offset, y: end.y - 2))
                details.addLine(to: CGPoint(x: end.x + offset, y: end.y + 1))
            }
        }
        return (armPath, handPath, details)
    }

    private func partPose(_ frame: AutoCaptureSignFrame, performance: AutoCaptureSignPerformance) -> RobotCaptureSignPartPose {
        guard !performance.reduceMotion else {
            return RobotCaptureSignPartPose(normalizedTime: frame.normalizedTime, gaze: .zero,
                                             headOpacity: 1, torsoOpacity: 1, eyeScaleY: 1,
                                             eyeBrightness: frame.eyeBrightness)
        }
        let entry = max(0.001, performance.entranceEndTime / performance.totalDuration)
        let progress = min(1, max(0, frame.normalizedTime / entry))
        let head = min(1, max(0, (progress - 0.18) / 0.30))
        let torso = min(1, max(0, (progress - 0.42) / 0.47))
        let blink: CGFloat = progress > 0.65 && progress < 0.76 ? 0.24 : 1
        return RobotCaptureSignPartPose(normalizedTime: frame.normalizedTime,
            gaze: CGPoint(x: frame.gazeX, y: frame.gazeY), headOpacity: Float(head),
            torsoOpacity: Float(torso), eyeScaleY: blink,
            head: RobotPartTransform(rotationDegrees: frame.headRotationDegrees),
            torso: RobotPartTransform(scaleY: frame.torsoScaleY),
            feet: RobotPartTransform(translation: CGPoint(x: 0, y: -frame.feetTranslationY),
                                     rotationDegrees: frame.feetRotationDegrees),
            eyeBrightness: frame.eyeBrightness)
    }

    private func peekOpacity(_ frame: AutoCaptureSignFrame, performance: AutoCaptureSignPerformance) -> Float {
        guard usesIsland, !performance.reduceMotion else { return 0 }
        let entry = max(0.001, performance.entranceEndTime / performance.totalDuration)
        let progress = frame.normalizedTime / entry
        return Float(min(1, max(0, min(progress / 0.18, (0.56 - progress) / 0.20))))
    }

    private func applyFrame(_ frame: AutoCaptureSignFrame, performance: AutoCaptureSignPerformance) {
        let limbs = limbPaths(frame, performance: performance)
        withoutActions {
            robotContainer.transform = robotTransform(frame)
            robotContainer.opacity = Float(frame.robotOpacity)
            plaqueContainer.transform = signTransform(frame)
            plaqueContainer.opacity = Float(frame.signOpacity)
            arms.path = limbs.arms
            armHighlights.path = limbs.arms
            hands.path = limbs.hands
            handDetails.path = limbs.details
            let alpha = Float(frame.robotOpacity)
            for shape in [arms, armHighlights, hands, handDetails] { shape.opacity = alpha }
            peekEyes.opacity = peekOpacity(frame, performance: performance)
            stamp.strokeEnd = frame.checkmarkProgress
            stamp.opacity = frame.checkmarkProgress > 0 ? 1 : 0
            symbolLayer.opacity = frame.checkmarkProgress > 0 ? 0 : 1
        }
        character.applyCaptureSignPartPose(partPose(frame, performance: performance))
        robotFrame = boundingBox(neutralRobotFrame, x: frame.robotTranslationX, y: frame.robotTranslationY,
                                 scaleX: frame.robotScaleX, scaleY: frame.robotScaleY,
                                 angle: frame.robotRotationDegrees)
        signFrame = boundingBox(neutralSignFrame, x: frame.signTranslationX, y: frame.signTranslationY,
                                scaleX: frame.signScaleX, scaleY: frame.signScaleY,
                                angle: frame.signRotationDegrees, yAngle: frame.signYRotationDegrees)
    }

    private func boundingBox(_ rectangle: CGRect, x: CGFloat, y: CGFloat,
                             scaleX: CGFloat, scaleY: CGFloat, angle: CGFloat, yAngle: CGFloat = 0) -> CGRect {
        let points = [CGPoint(x: rectangle.minX, y: rectangle.minY), CGPoint(x: rectangle.maxX, y: rectangle.minY),
                      CGPoint(x: rectangle.minX, y: rectangle.maxY), CGPoint(x: rectangle.maxX, y: rectangle.maxY)]
            .map { transformedPoint($0, in: rectangle, x: x, y: y, scaleX: scaleX, scaleY: scaleY,
                                     angle: angle, yAngle: yAngle) }
        return CGRect(x: points.map(\.x).min()!, y: points.map(\.y).min()!,
                      width: points.map(\.x).max()! - points.map(\.x).min()!,
                      height: points.map(\.y).max()! - points.map(\.y).min()!)
    }

    private func animate(_ frames: [AutoCaptureSignFrame], performance: AutoCaptureSignPerformance,
                         beginTime: CFTimeInterval) {
        func track(_ target: CALayer?, keyPath: String, values: [Any], name: String) {
            guard let target else { return }
            let animation = CAKeyframeAnimation(keyPath: keyPath)
            animation.values = values
            animation.keyTimes = frames.map { NSNumber(value: $0.normalizedTime) }
            animation.duration = performance.totalDuration
            animation.beginTime = target.convertTime(beginTime, from: nil)
            animation.calculationMode = .linear
            target.add(animation, forKey: "autoCaptureSign.\(name)")
        }
        track(robotContainer, keyPath: "transform", values: frames.map { NSValue(caTransform3D: robotTransform($0)) }, name: "robot")
        track(robotContainer, keyPath: "opacity", values: frames.map(\.robotOpacity), name: "robotOpacity")
        track(plaqueContainer, keyPath: "transform", values: frames.map { NSValue(caTransform3D: signTransform($0)) }, name: "plaque")
        track(plaqueContainer, keyPath: "opacity", values: frames.map(\.signOpacity), name: "plaqueOpacity")
        let limbs = frames.map { limbPaths($0, performance: performance) }
        for shape in [arms, armHighlights] {
            track(shape, keyPath: "path", values: limbs.map(\.arms), name: "arm-\(shape.name ?? "")")
        }
        track(hands, keyPath: "path", values: limbs.map(\.hands), name: "hands")
        track(handDetails, keyPath: "path", values: limbs.map(\.details), name: "fingers")
        for shape in [arms, armHighlights, hands, handDetails] {
            track(shape, keyPath: "opacity", values: frames.map(\.robotOpacity), name: "limbOpacity-\(shape.name ?? "")")
        }
        track(peekEyes, keyPath: "opacity", values: frames.map { peekOpacity($0, performance: performance) }, name: "peek")
        track(stamp, keyPath: "strokeEnd", values: frames.map(\.checkmarkProgress), name: "stampProgress")
        track(stamp, keyPath: "opacity", values: frames.map { $0.checkmarkProgress > 0 ? 1 : 0 }, name: "stampOpacity")
        track(symbolLayer, keyPath: "opacity", values: frames.map { $0.checkmarkProgress > 0 ? 0 : 1 }, name: "stampIconReplacement")
        character.animateCaptureSignParts(frames.map { partPose($0, performance: performance) },
                                         duration: performance.totalDuration, beginTime: beginTime)
    }

    private func updateContentsScale() {
        let backing = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        func apply(_ layer: CALayer) {
            layer.contentsScale = backing
            if let mask = layer.mask { apply(mask) }
            for child in layer.sublayers ?? [] { apply(child) }
        }
        if let layer { apply(layer) }
    }

    private func removeAnimationsRecursively(_ layer: CALayer?) {
        guard let layer else { return }
        layer.removeAllAnimations()
        for child in layer.sublayers ?? [] { removeAnimationsRecursively(child) }
    }

    private func withoutActions(_ action: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        action()
        CATransaction.commit()
    }
}
