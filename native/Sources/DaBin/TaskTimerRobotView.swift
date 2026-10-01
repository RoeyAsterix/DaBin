import AppKit
import QuartzCore

/// A value-only, native alarm scene. The presenter owns its window and lifetime;
/// this view owns finite body motion, small-layer clock ringing and acknowledgement.
@MainActor
final class TaskTimerRobotView: NSView {
    static let stageSize = CGSize(width: 320, height: 230)
    static let entryDuration: TimeInterval = 0.82
    static let returnDuration: TimeInterval = 0.50

    var onDismiss: (() -> Void)?
    private(set) var displayedTaskTitle = ""
    /// The alarm remains outstanding until it is acknowledged.
    private(set) var isRinging = false
    private(set) var isReturning = false
    let characterView: RobotCharacterView

    var characterFrame: CGRect { characterView.convert(characterView.bounds, to: self) }
    var clockFrame: CGRect { rigView.convert(clockLayer.frame, to: self) }
    var signFrame: CGRect { signView.convert(signView.bounds, to: self) }
    var hasActiveEntryMotion: Bool { rigView.layer?.animation(forKey: Self.entryKey) != nil }
    var hasActiveRingMotion: Bool { clockLayer.animation(forKey: Self.ringKey) != nil }
    var hasActiveReturnMotion: Bool { rigView.layer?.animation(forKey: Self.returnKey) != nil }

    private static let entryKey = "taskTimer.entry.transform"
    private static let returnKey = "taskTimer.return.transform"
    private static let ringKey = "taskTimer.clock.ring"
    private let reduceMotionProvider: () -> Bool
    private let stageView = NSView()
    private let rigView = NSView()
    private let clockLayer = CALayer()
    private let ringMarks = CAShapeLayer()
    private let signView = NSView()
    private let signTitle = NSTextField(labelWithString: "")
    private let signCaption = NSTextField(labelWithString: "FOCUS COMPLETE")
    private let hintTitle = NSTextField(labelWithString: "Timer finished")
    private let hintDetail = NSTextField(labelWithString: "Click to return home")
    private var dismissRequested = false

    init(frame frameRect: NSRect, reduceMotion: @escaping () -> Bool = {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }) {
        reduceMotionProvider = reduceMotion
        // The canonical renderer is intentionally static here. One wrapper owns
        // the whole leap so the held clock and board cannot detach from its arms.
        characterView = RobotCharacterView(frame: CGRect(x: 109, y: 42, width: 102, height: 124.3125),
                                            reduceMotion: { true })
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.name = "taskTimer.stage"
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityIdentifier("task-timer-robot")
        setAccessibilityHelp("Press to acknowledge the finished timer and return the robot home.")
        configureScene()
        reset()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        let scale = max(0.01, min(bounds.width / Self.stageSize.width, bounds.height / Self.stageSize.height))
        withoutActions {
            stageView.frame = CGRect(x: bounds.midX - Self.stageSize.width / 2,
                                     y: bounds.midY - Self.stageSize.height / 2,
                                     width: Self.stageSize.width, height: Self.stageSize.height)
            stageView.layer?.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateContentsScale()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateContentsScale()
    }

    func show(taskTitle: String, reduceMotion: Bool) {
        reset()
        displayedTaskTitle = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if displayedTaskTitle.isEmpty { displayedTaskTitle = "Untitled task" }
        // The label wraps and truncates independently of the complete AX label.
        signTitle.stringValue = displayedTaskTitle
        setAccessibilityLabel("Timer finished: \(displayedTaskTitle). Return robot home")
        characterView.configureQuietOrbit(true)
        characterView.send(.reveal(.top))
        characterView.setNativeArmsHidden(true)
        characterView.layoutSubtreeIfNeeded()
        isRinging = true
        isHidden = false
        withoutActions {
            rigView.layer?.transform = CATransform3DIdentity
            rigView.layer?.opacity = 1
            clockLayer.transform = CATransform3DIdentity
            ringMarks.opacity = 1
        }
        needsLayout = true
        layoutSubtreeIfNeeded()
        guard !reduceMotion, !reduceMotionProvider() else { return }

        let entry = CAKeyframeAnimation(keyPath: "transform")
        entry.values = [transform(scale: 0.70, y: 147), transform(scale: 0.87, y: 82),
                        transform(scale: 1.055, y: 9), transform(scale: 1.025, y: -5),
                        transform(scale: 0.985, y: 2), CATransform3DIdentity].map { NSValue(caTransform3D: $0) }
        entry.keyTimes = [0, 0.25, 0.61, 0.76, 0.90, 1]
        entry.duration = Self.entryDuration
        entry.timingFunctions = [.init(name: .easeOut), .init(name: .easeIn),
                                .init(name: .easeOut), .init(name: .easeInEaseOut), .init(name: .easeOut)]
        rigView.layer?.add(entry, forKey: Self.entryKey)

        // Only these tiny native prop layers repeat while the alarm is visible.
        // There is no per-frame application work, layout or timer loop.
        let shake = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        shake.values = [0, -0.10, 0.10, -0.07, 0.07, 0]
        shake.keyTimes = [0, 0.18, 0.38, 0.60, 0.82, 1]
        shake.duration = 0.25
        shake.repeatCount = .infinity
        shake.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 5)
        clockLayer.add(shake, forKey: Self.ringKey)
        let pulse = CAKeyframeAnimation(keyPath: "opacity")
        pulse.values = [1, 0.25, 1]
        pulse.duration = 0.5
        pulse.repeatCount = .infinity
        ringMarks.add(pulse, forKey: "taskTimer.clock.rays")
    }

    func beginReturn(reduceMotion: Bool) {
        guard !isHidden, !isReturning || reduceMotion || reduceMotionProvider() else { return }
        let current = rigView.layer?.presentation()?.transform ?? rigView.layer?.transform ?? CATransform3DIdentity
        let currentOpacity = rigView.layer?.presentation()?.opacity ?? rigView.layer?.opacity ?? 1
        isReturning = true
        isRinging = false
        dismissRequested = true
        rigView.layer?.removeAllAnimations()
        clockLayer.removeAllAnimations()
        ringMarks.removeAllAnimations()
        withoutActions {
            clockLayer.transform = CATransform3DIdentity
            ringMarks.opacity = 0
        }
        if reduceMotion || reduceMotionProvider() {
            withoutActions {
                rigView.layer?.transform = current
                rigView.layer?.opacity = 0
            }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = currentOpacity
            fade.toValue = 0
            fade.duration = 0.14
            rigView.layer?.add(fade, forKey: "taskTimer.return.opacity")
            return
        }
        let destination = transform(scale: 0.12, y: 155)
        withoutActions {
            rigView.layer?.transform = destination
            rigView.layer?.opacity = 0
        }
        let flight = CAKeyframeAnimation(keyPath: "transform")
        let gather = CATransform3DScale(CATransform3DTranslate(current, 0, -5, 0), 0.955, 0.955, 1)
        flight.values = [current, gather, transform(scale: 0.66, y: max(65, current.m42 + 18)),
                         destination].map { NSValue(caTransform3D: $0) }
        flight.keyTimes = [0, 0.17, 0.57, 1]
        flight.duration = Self.returnDuration
        flight.timingFunctions = [.init(name: .easeInEaseOut), .init(name: .easeIn), .init(name: .easeIn)]
        rigView.layer?.add(flight, forKey: Self.returnKey)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [currentOpacity, currentOpacity, 0]
        fade.keyTimes = [0, 0.78, 1]
        fade.duration = Self.returnDuration
        rigView.layer?.add(fade, forKey: "taskTimer.return.opacity")
    }

    func reset() {
        isHidden = true
        isRinging = false
        isReturning = false
        dismissRequested = false
        displayedTaskTitle = ""
        signTitle.stringValue = ""
        setAccessibilityLabel("Task timer robot")
        rigView.layer?.removeAllAnimations()
        clockLayer.removeAllAnimations()
        ringMarks.removeAllAnimations()
        characterView.stopMotion()
        withoutActions {
            rigView.layer?.transform = CATransform3DIdentity
            rigView.layer?.opacity = 0
            clockLayer.transform = CATransform3DIdentity
            ringMarks.opacity = 0
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard !isHidden, !isReturning, bounds.contains(local), super.hitTest(point) != nil else { return nil }
        return self
    }

    override func mouseDown(with event: NSEvent) { _ = requestDismissal() }
    override func accessibilityPerformPress() -> Bool { requestDismissal() }

    @discardableResult private func requestDismissal() -> Bool {
        guard !isHidden, !isReturning, !dismissRequested else { return false }
        dismissRequested = true
        onDismiss?()
        return true
    }

    private func configureScene() {
        stageView.wantsLayer = true
        stageView.layer?.masksToBounds = false
        stageView.setAccessibilityElement(false)
        addSubview(stageView)
        rigView.frame = CGRect(origin: .zero, size: Self.stageSize)
        rigView.wantsLayer = true
        rigView.layer?.name = "taskTimer.rig"
        rigView.layer?.masksToBounds = false
        rigView.setAccessibilityElement(false)
        stageView.addSubview(rigView)

        let arms = CAShapeLayer()
        arms.name = "taskTimer.heldProps.arms"
        let armPath = CGMutablePath()
        armPath.move(to: CGPoint(x: 129, y: 109))
        armPath.addQuadCurve(to: CGPoint(x: 91, y: 108), control: CGPoint(x: 107, y: 111))
        armPath.move(to: CGPoint(x: 193, y: 109))
        armPath.addQuadCurve(to: CGPoint(x: 221, y: 94), control: CGPoint(x: 212, y: 112))
        arms.path = armPath
        arms.fillColor = nil
        arms.strokeColor = QuietOrbitVisualStyle.color(0xA68BBB)
        arms.lineWidth = 8
        arms.lineCap = .round
        rigView.layer?.addSublayer(arms)
        let armHighlight = CAShapeLayer()
        armHighlight.path = armPath
        armHighlight.fillColor = nil
        armHighlight.strokeColor = QuietOrbitVisualStyle.color(0xEEE7F4, alpha: 0.75)
        armHighlight.lineWidth = 2
        armHighlight.lineCap = .round
        rigView.layer?.addSublayer(armHighlight)
        rigView.addSubview(characterView)
        configureClock()
        configureSign()

        configureLabel(hintTitle, size: 13, weight: .semibold, color: 0xF5F1F8)
        configureLabel(hintDetail, size: 10.5, weight: .medium, color: 0xD9CEE5)
        let hint = NSView(frame: CGRect(x: 85, y: 7, width: 150, height: 43))
        hint.wantsLayer = true
        hint.layer?.name = "taskTimer.hint"
        hint.layer?.backgroundColor = QuietOrbitVisualStyle.color(0x211A2B, alpha: 0.94)
        hint.layer?.cornerRadius = 12
        hint.layer?.borderColor = QuietOrbitVisualStyle.color(0xD0BEDF, alpha: 0.35)
        hint.layer?.borderWidth = 1
        hint.setAccessibilityElement(false)
        rigView.addSubview(hint)
        hintTitle.frame = CGRect(x: 8, y: 21, width: 134, height: 17)
        hintDetail.frame = CGRect(x: 6, y: 5, width: 138, height: 15)
        hint.addSubview(hintTitle)
        hint.addSubview(hintDetail)
    }

    private func configureClock() {
        clockLayer.name = "taskTimer.clock"
        clockLayer.frame = CGRect(x: 20, y: 68, width: 84, height: 96)
        clockLayer.masksToBounds = false
        rigView.layer?.addSublayer(clockLayer)
        func shape(_ name: String, _ path: CGPath, fill: UInt32?, stroke: UInt32? = nil, width: CGFloat = 1) {
            let item = CAShapeLayer()
            item.name = name
            item.path = path
            item.fillColor = fill.map { QuietOrbitVisualStyle.color($0) }
            item.strokeColor = stroke.map { QuietOrbitVisualStyle.color($0) }
            item.lineWidth = width
            item.lineCap = .round
            item.lineJoin = .round
            clockLayer.addSublayer(item)
        }
        let feet = CGMutablePath()
        feet.move(to: CGPoint(x: 23, y: 18)); feet.addLine(to: CGPoint(x: 18, y: 8))
        feet.move(to: CGPoint(x: 61, y: 18)); feet.addLine(to: CGPoint(x: 66, y: 8))
        shape("taskTimer.clock.feet", feet, fill: nil, stroke: 0xCFBDD9, width: 6)
        let handle = CGMutablePath()
        handle.move(to: CGPoint(x: 31, y: 79))
        handle.addCurve(to: CGPoint(x: 53, y: 79), control1: CGPoint(x: 32, y: 93), control2: CGPoint(x: 52, y: 93))
        shape("taskTimer.clock.handle", handle, fill: nil, stroke: 0xEEE7F4, width: 3)
        shape("taskTimer.clock.shell", CGPath(ellipseIn: CGRect(x: 9, y: 14, width: 66, height: 66), transform: nil),
              fill: 0xBDA8CF, stroke: 0x6D5387, width: 2)
        shape("taskTimer.clock.face", CGPath(ellipseIn: CGRect(x: 15, y: 20, width: 54, height: 54), transform: nil),
              fill: 0xFFF8E8, stroke: 0xEEE7F4, width: 2)
        for (index, x) in [CGFloat(12), CGFloat(51)].enumerated() {
            let bell = CGMutablePath()
            bell.move(to: CGPoint(x: x, y: 76))
            bell.addCurve(to: CGPoint(x: x + 23, y: 82), control1: CGPoint(x: x - 3, y: 96), control2: CGPoint(x: x + 20, y: 101))
            bell.addLine(to: CGPoint(x: x, y: 76))
            shape("taskTimer.clock.bell.\(index)", bell, fill: 0xEFC97C, stroke: 0x967645, width: 1.5)
        }
        let ticks = CGMutablePath()
        for index in 0..<12 {
            let angle = CGFloat(index) * .pi / 6
            ticks.move(to: CGPoint(x: 42 + sin(angle) * 20, y: 47 + cos(angle) * 20))
            ticks.addLine(to: CGPoint(x: 42 + sin(angle) * 23, y: 47 + cos(angle) * 23))
        }
        shape("taskTimer.clock.ticks", ticks, fill: nil, stroke: 0x7F697A, width: 1.7)
        let hands = CGMutablePath()
        hands.move(to: CGPoint(x: 42, y: 63)); hands.addLine(to: CGPoint(x: 42, y: 47))
        hands.addLine(to: CGPoint(x: 56, y: 41))
        shape("taskTimer.clock.hands", hands, fill: nil, stroke: 0x3E3449, width: 3)
        shape("taskTimer.clock.pin", CGPath(ellipseIn: CGRect(x: 39, y: 44, width: 6, height: 6), transform: nil), fill: 0x80608D)
        let rays = CGMutablePath()
        for (start, end) in [(CGPoint(x: 0, y: 76), CGPoint(x: -6, y: 80)),
                             (CGPoint(x: 2, y: 86), CGPoint(x: -3, y: 94)),
                             (CGPoint(x: 83, y: 77), CGPoint(x: 90, y: 81)),
                             (CGPoint(x: 81, y: 88), CGPoint(x: 85, y: 96))] {
            rays.move(to: start); rays.addLine(to: end)
        }
        ringMarks.name = "taskTimer.clock.ringMarks"
        ringMarks.path = rays
        ringMarks.fillColor = nil
        ringMarks.strokeColor = QuietOrbitVisualStyle.color(0xF7DDA4)
        ringMarks.lineWidth = 2.5
        ringMarks.lineCap = .round
        clockLayer.addSublayer(ringMarks)
    }

    private func configureSign() {
        signView.frame = CGRect(x: 208, y: 59, width: 106, height: 77)
        signView.wantsLayer = true
        signView.layer?.name = "taskTimer.sign"
        signView.layer?.backgroundColor = QuietOrbitVisualStyle.color(0x342A40)
        signView.layer?.borderColor = QuietOrbitVisualStyle.color(0xD0BEDF)
        signView.layer?.borderWidth = 2
        signView.layer?.cornerRadius = 9
        signView.layer?.masksToBounds = true
        signView.setAccessibilityElement(false)
        configureLabel(signCaption, size: 8, weight: .bold, color: 0xC8F1E5)
        signCaption.frame = CGRect(x: 5, y: 57, width: 96, height: 13)
        configureLabel(signTitle, size: 11.5, weight: .semibold, color: 0xF5F1F8)
        signTitle.frame = CGRect(x: 7, y: 7, width: 92, height: 45)
        signTitle.maximumNumberOfLines = 3
        signTitle.lineBreakMode = .byTruncatingTail
        signTitle.cell?.wraps = true
        signTitle.cell?.isScrollable = false
        signView.addSubview(signCaption)
        signView.addSubview(signTitle)
        rigView.addSubview(signView)
        let hand = CAShapeLayer()
        hand.name = "taskTimer.heldProps.hand"
        hand.path = CGPath(roundedRect: CGRect(x: 203, y: 88, width: 14, height: 13), cornerWidth: 5, cornerHeight: 5, transform: nil)
        hand.fillColor = QuietOrbitVisualStyle.color(0xCFBEDC)
        hand.strokeColor = QuietOrbitVisualStyle.color(0x836495)
        hand.lineWidth = 1.5
        rigView.layer?.addSublayer(hand)
    }

    private func configureLabel(_ label: NSTextField, size: CGFloat, weight: NSFont.Weight, color: UInt32) {
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = NSColor(cgColor: QuietOrbitVisualStyle.color(color))
        label.alignment = .center
        label.isSelectable = false
        label.setAccessibilityElement(false)
    }

    private func updateContentsScale() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        func update(_ item: CALayer) {
            item.contentsScale = scale
            for child in item.sublayers ?? [] { update(child) }
        }
        update(clockLayer)
    }

    private func transform(scale: CGFloat, y: CGFloat) -> CATransform3D {
        CATransform3DTranslate(CATransform3DMakeScale(scale, scale, 1), 0, y / scale, 0)
    }

    private func withoutActions(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }
}
