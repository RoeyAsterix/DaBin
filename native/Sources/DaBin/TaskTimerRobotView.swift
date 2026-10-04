import AppKit
import QuartzCore

/// The compact sign keeps the complete name in its native text field, while
/// AppKit draws a clear ellipsis on the last visible line when space runs out.
/// This also centers short names vertically instead of leaving a blank footer.
@MainActor
private final class ReminderTaskTitleField: NSTextField {
    override func draw(_ dirtyRect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        let content = NSAttributedString(string: String(stringValue.prefix(2048)), attributes: [
            .font: font ?? NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: textColor ?? NSColor.labelColor,
            .paragraphStyle: paragraph
        ])
        let measured = content.boundingRect(
            with: CGSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading])
        let height = min(bounds.height, ceil(measured.height))
        let area = CGRect(x: bounds.minX, y: bounds.midY - height / 2, width: bounds.width, height: height)
        content.draw(with: area, options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine])
    }
}

/// A value-only, native alarm scene. The presenter owns its window and lifetime;
/// this view owns finite body motion, small-layer clock ringing and acknowledgement.
@MainActor
final class TaskTimerRobotView: NSView {
    static let stageSize = CGSize(width: 320, height: 160)
    static let entryDuration: TimeInterval = 0.82
    static let returnDuration: TimeInterval = 0.50

    var onDismiss: (() -> Void)?
    private(set) var displayedTaskTitle = ""
    private(set) var fullTaskTitle = ""
    private(set) var reminderCount = 0
    private(set) var escalationLevel = 0
    private(set) var islandPlacement = true
    private(set) var displayedScale: CGFloat = 1
    private var reducedMotion = false
    private(set) var recordingProjectName: String?
    var recordingSignFontSize: CGFloat { recordingProjectLabel.font?.pointSize ?? 0 }
    /// The alarm remains outstanding until it is acknowledged.
    private(set) var isRinging = false
    private(set) var isReturning = false
    let characterView: RobotCharacterView

    var characterFrame: CGRect { visibleFrame(of: characterView.layer) }
    var clockFrame: CGRect { visibleFrame(of: clockLayer) }
    var signFrame: CGRect { visibleFrame(of: signView.layer) }
    var hasActiveEntryMotion: Bool { rigView.layer?.animation(forKey: Self.entryKey) != nil }
    var hasActiveRingMotion: Bool { clockLayer.animation(forKey: Self.ringKey) != nil }
    var hasActiveReturnMotion: Bool { rigView.layer?.animation(forKey: Self.returnKey) != nil }

    private static let entryKey = "taskTimer.entry.transform"
    private static let returnKey = "taskTimer.return.transform"
    private static let ringKey = "taskTimer.clock.ring"
    private let reduceMotionProvider: () -> Bool
    private let stageView = NSView()
    private let rigView = NSView()
    /// Keep the robot, hands and props in one artwork coordinate system while
    /// reclaiming the space formerly occupied by the separate timer banner.
    private let artworkView = NSView()
    private let clockLayer = CALayer()
    private let ringMarks = CAShapeLayer()
    private let arms = CAShapeLayer()
    private let armHighlight = CAShapeLayer()
    private let signView = NSView()
    private let signTitle = ReminderTaskTitleField(labelWithString: "")
    private let signCaption = NSTextField(labelWithString: "")
    private let recordingProjectLabel = NSTextField(labelWithString: "")
    private let recordingStatusDot = CAShapeLayer()
    private var acknowledgementFailed = false
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
        setAccessibilityHelp("Press the robot or clock to acknowledge and open the reminders.")
        configureScene()
        reset()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        displayedScale = TaskTimerAlarmMotion.scale(for: reducedMotion ? 0 : escalationLevel,
            availableSize: bounds.size, baseSize: Self.stageSize)
        withoutActions {
            stageView.frame = CGRect(origin: .zero, size: Self.stageSize)
            // Top alignment puts the emergence at the island (or the external
            // display corner) at every scale instead of growing around a center.
            stageView.layer?.anchorPoint = CGPoint(x: islandPlacement ? 0.5 : 1, y: 1)
            stageView.layer?.position = CGPoint(x: islandPlacement ? bounds.midX : bounds.maxX, y: bounds.maxY)
            stageView.layer?.setAffineTransform(CGAffineTransform(scaleX: displayedScale, y: displayedScale))
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

    func show(taskTitle: String, reduceMotion: Bool, count: Int = 1, fullTitle: String? = nil,
              island: Bool = true, level: Int = 0, animateEntrance: Bool = true) {
        reset()
        reducedMotion = reduceMotion || reduceMotionProvider()
        islandPlacement = island
        escalationLevel = reducedMotion ? 0 : min(max(level, 0), 3)
        updateReminder(taskTitle: taskTitle, fullTitle: fullTitle ?? taskTitle, count: count)
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
            ringMarks.opacity = reducedMotion ? 0 : 1
        }
        needsLayout = true
        layoutSubtreeIfNeeded()
        guard !reducedMotion else { return }

        if animateEntrance {
        let entry = CAKeyframeAnimation(keyPath: "transform")
        entry.values = [transform(scale: 0.70, y: 147), transform(scale: 0.87, y: 82),
                        transform(scale: 1.055, y: 9), transform(scale: 1.025, y: -5),
                        transform(scale: 0.985, y: 2), CATransform3DIdentity].map { NSValue(caTransform3D: $0) }
        entry.keyTimes = [0, 0.25, 0.61, 0.76, 0.90, 1]
        entry.duration = Self.entryDuration
        entry.timingFunctions = [.init(name: .easeOut), .init(name: .easeIn),
                                .init(name: .easeOut), .init(name: .easeInEaseOut), .init(name: .easeOut)]
        rigView.layer?.add(entry, forKey: Self.entryKey)

        }
        startClockMotion()
        if escalationLevel == 3 { addPatientBalance() }
    }

    func updateReminder(taskTitle: String, fullTitle: String, count: Int) {
        fullTaskTitle = fullTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if fullTaskTitle.isEmpty { fullTaskTitle = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines) }
        if fullTaskTitle.isEmpty { fullTaskTitle = "Untitled task" }
        fullTaskTitle = fullTaskTitle.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        displayedTaskTitle = fullTaskTitle
        reminderCount = max(1, count)
        signTitle.stringValue = displayedTaskTitle
        layoutSign()
        setAccessibilityHelp(acknowledgementFailed
            ? "Acknowledgement could not be saved. Press the robot or clock to retry."
            : "Press the robot or clock to acknowledge and open the reminders.")
        updateAccessibilityDescription()
    }

    func setEscalation(level: Int, animated: Bool) {
        guard !isHidden, !isReturning else { return }
        let next = reducedMotion ? 0 : min(max(level, 0), 3)
        guard next != escalationLevel else { return }
        let previous = stageView.layer?.presentation()?.transform ?? stageView.layer?.transform ?? CATransform3DIdentity
        escalationLevel = next
        needsLayout = true
        layoutSubtreeIfNeeded()
        updateContentsScale()
        guard animated, !reducedMotion, !reduceMotionProvider() else { return }
        let target = stageView.layer?.transform ?? CATransform3DIdentity
        let growth = CAKeyframeAnimation(keyPath: "transform")
        let verticalLimit = min(TaskTimerAlarmMotion.maximumScale, bounds.height / Self.stageSize.height)
        let anticipationStretch = TaskTimerAlarmMotion.stretchFactor(for: previous.m22, preferred: 1.025, limit: verticalLimit)
        let landingStretch = TaskTimerAlarmMotion.stretchFactor(for: target.m22, preferred: 1.01, limit: verticalLimit)
        growth.values = [previous, CATransform3DScale(previous, 0.98, anticipationStretch, 1),
                         CATransform3DScale(target, 0.99, landingStretch, 1), target].map { NSValue(caTransform3D: $0) }
        growth.keyTimes = [0, 0.16, 0.78, 1]
        growth.duration = TaskTimerAlarmMotion.growthDuration
        growth.timingFunctions = [.init(name: .easeInEaseOut), .init(name: .easeOut), .init(name: .easeInEaseOut)]
        stageView.layer?.add(growth, forKey: "taskTimer.growth")
        let balance = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        balance.values = [0, -0.045, 0.06, -0.025, 0]
        balance.keyTimes = [0, 0.2, 0.45, 0.7, 1]
        balance.duration = 1.15
        rigView.layer?.add(balance, forKey: "taskTimer.surprised.balance")
        // Reuse the canonical eyes and held arms; no new character artwork.
        for eye in namedLayers(prefix: "quietOrbit.eye.") {
            let surprise = CAKeyframeAnimation(keyPath: "transform.scale.y")
            surprise.values = [1, 1.28, 1.28, 1]
            surprise.keyTimes = [0, 0.2, 0.7, 1]
            surprise.duration = 1.1
            eye.add(surprise, forKey: "taskTimer.surprised.eyes")
        }
        let brace = CAKeyframeAnimation(keyPath: "transform.translation.y")
        brace.values = [0, 3, -1, 0]; brace.duration = 1.1
        arms.add(brace, forKey: "taskTimer.bracing")
        armHighlight.add(brace, forKey: "taskTimer.bracing")
        startClockMotion()
        if next == 3 { addPatientBalance() }
    }

    /// Stop immediately before a durable acknowledgement attempt. This does not
    /// claim success and can be resumed if persistence fails.
    func stopAlarmMotion() {
        isRinging = false
        for item in [stageView.layer, rigView.layer, clockLayer, ringMarks, arms, armHighlight].compactMap({ $0 }) {
            let pose = !isHidden ? item.presentation()?.transform : nil
            item.removeAllAnimations()
            if let pose { withoutActions { item.transform = pose } }
        }
        for eye in namedLayers(prefix: "quietOrbit.eye.") { eye.removeAllAnimations() }
        withoutActions { clockLayer.transform = CATransform3DIdentity; ringMarks.opacity = 0 }
    }

    func showAcknowledgementFailure() {
        acknowledgementFailed = true
        layoutSign()
        setAccessibilityHelp("Acknowledgement could not be saved. Press the robot or clock to retry.")
    }

    private func startClockMotion() {
        guard !reducedMotion, !reduceMotionProvider(), !isReturning else { return }
        let amplitude: Double = escalationLevel == 3 ? 0.055 : 0.09
        let shake = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        shake.values = [0, -amplitude, amplitude, -amplitude * 0.6, amplitude * 0.4, 0, 0]
        shake.keyTimes = [0, 0.04, 0.08, 0.12, 0.17, 0.22, 1]
        shake.duration = escalationLevel == 3 ? 3.8 : 2.6
        shake.repeatCount = .infinity
        clockLayer.add(shake, forKey: Self.ringKey)
        let pulse = CAKeyframeAnimation(keyPath: "opacity")
        pulse.values = [0, 1, 0.25, 1, 0, 0]
        pulse.keyTimes = [0, 0.04, 0.1, 0.16, 0.23, 1]
        pulse.duration = shake.duration
        pulse.repeatCount = .infinity
        ringMarks.add(pulse, forKey: "taskTimer.clock.rays")
    }

    private func addPatientBalance() {
        let sway = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        sway.values = [0, 0, -0.012, 0.012, 0, 0]
        sway.keyTimes = [0, 0.55, 0.66, 0.8, 0.9, 1]
        sway.duration = 6
        sway.repeatCount = .infinity
        rigView.layer?.add(sway, forKey: "taskTimer.patient.balance")
        for eye in namedLayers(prefix: "quietOrbit.eye.") {
            let blink = CAKeyframeAnimation(keyPath: "transform.scale.y")
            blink.values = [1, 1, 0.14, 1, 1]
            blink.keyTimes = [0, 0.58, 0.61, 0.64, 1]
            blink.duration = 6.5; blink.repeatCount = .infinity
            eye.add(blink, forKey: "taskTimer.patient.blink")
        }
    }

    private func namedLayers(prefix: String) -> [CALayer] {
        func find(_ item: CALayer) -> [CALayer] {
            (item.name?.hasPrefix(prefix) == true ? [item] : []) + (item.sublayers ?? []).flatMap(find)
        }
        return characterView.layer.map(find) ?? []
    }

    func beginReturn(reduceMotion: Bool) {
        guard !isHidden, !isReturning || reduceMotion || reduceMotionProvider() else { return }
        let current = rigView.layer?.presentation()?.transform ?? rigView.layer?.transform ?? CATransform3DIdentity
        let currentOpacity = rigView.layer?.presentation()?.opacity ?? rigView.layer?.opacity ?? 1
        isReturning = true
        isRinging = false
        dismissRequested = true
        stopAlarmMotion()
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
        for eye in namedLayers(prefix: "quietOrbit.eye.") {
            let relief = CAKeyframeAnimation(keyPath: "transform.scale.y")
            relief.values = [1, 0.28, 0.28, 1]; relief.duration = Self.returnDuration
            eye.add(relief, forKey: "taskTimer.relieved")
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
        fullTaskTitle = ""
        reminderCount = 0
        escalationLevel = 0
        acknowledgementFailed = false
        signTitle.stringValue = ""
        layoutSign()
        updateAccessibilityDescription()
        stopAlarmMotion()
        characterView.stopMotion()
        withoutActions {
            rigView.layer?.transform = CATransform3DIdentity
            rigView.layer?.opacity = 0
            clockLayer.transform = CATransform3DIdentity
            ringMarks.opacity = 0
        }
    }

    /// A timer can own the one visible robot until acknowledged. Its existing
    /// held board shares the currently active recording destination, including
    /// across reset/show for the next alarm. Pause hides only the project label.
    func setProjectRecording(projectName: String?, isPaused: Bool) {
        let name = projectName?.trimmingCharacters(in: .whitespacesAndNewlines)
        recordingProjectName = isPaused ? nil : name.flatMap { $0.isEmpty ? nil : $0 }
        recordingProjectLabel.stringValue = recordingProjectName ?? ""
        recordingProjectLabel.isHidden = recordingProjectName == nil
        recordingStatusDot.isHidden = recordingProjectName == nil
        recordingStatusDot.fillColor = NSColor.systemTeal.cgColor
        layoutSign()
        updateAccessibilityDescription()
    }

    /// A single reminder shows only its task name. Count and retry feedback
    /// share a small optional badge on the same held sign, never a second panel.
    private func layoutSign() {
        if acknowledgementFailed {
            signCaption.stringValue = reminderCount > 1
                ? "Couldn’t save\nRetry · \(reminderCount) reminders" : "Couldn’t save · Retry"
        } else {
            signCaption.stringValue = reminderCount > 1 ? "\(reminderCount) reminders" : ""
        }
        let hasCaption = !signCaption.stringValue.isEmpty
        let captionHeight: CGFloat = hasCaption ? (acknowledgementFailed ? 26 : 15) : 0
        let recordingHeight: CGFloat = recordingProjectName == nil ? 0 : 21
        let text = String(signTitle.stringValue.prefix(2048)) as NSString
        let measured = text.boundingRect(with: CGSize(width: 92, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: signTitle.font ?? NSFont.systemFont(ofSize: 12, weight: .semibold)])
        let titleHeight = min(58, max(17, ceil(measured.height)))
        let badgeSpace = hasCaption ? captionHeight + 4 : 0
        let height = max(44, titleHeight + recordingHeight + badgeSpace + 16)
        withoutActions {
            // Keep the hand attached at the sign's center as the title wraps.
            signView.frame = CGRect(x: 208, y: 97.5 - height / 2, width: 106, height: height)
            signTitle.frame = CGRect(x: 7, y: 8 + recordingHeight,
                                     width: 92, height: height - 16 - recordingHeight - badgeSpace)
            signCaption.frame = CGRect(x: 5, y: height - 8 - captionHeight, width: 96, height: captionHeight)
            signCaption.isHidden = !hasCaption
            signCaption.textColor = NSColor(cgColor: QuietOrbitVisualStyle.color(
                acknowledgementFailed ? 0xFFC9BD : 0xC8F1E5))
            signCaption.layer?.backgroundColor = QuietOrbitVisualStyle.color(
                acknowledgementFailed ? 0x75433F : 0x54766D, alpha: 0.35)
            recordingProjectLabel.frame = CGRect(x: 15, y: 8, width: 85, height: 17)
            recordingStatusDot.path = CGPath(ellipseIn: CGRect(x: 7, y: 15, width: 4, height: 4), transform: nil)
        }
    }

    private func updateAccessibilityDescription() {
        let base = fullTaskTitle.isEmpty ? "Task timer robot" : "\(reminderCount) reminder\(reminderCount == 1 ? "" : "s"): \(fullTaskTitle). Open reminders"
        let destination = recordingProjectName.map {
            ". Recording to \($0)"
        } ?? ""
        setAccessibilityLabel(base + destination)
    }

    private func visibleFrame(of item: CALayer?) -> CGRect {
        guard let item, let root = layer else { return .zero }
        let rendered = item.presentation() ?? item
        let target = root.presentation() ?? root
        return rendered.convert(rendered.bounds, to: target)
    }

    /// Test the rendered positions, including growth/entrance, rather than the
    /// untransformed NSView frames. The sign and all empty padding stay passive.
    func containsInteractivePoint(_ point: CGPoint) -> Bool {
        guard !isHidden, !isReturning, bounds.contains(point), let root = layer else { return false }
        let source = root.presentation() ?? root
        if let body = characterView.layer {
            let rendered = body.presentation() ?? body
            let local = rendered.convert(point, from: source)
            let bodyShape = CGPath(roundedRect: rendered.bounds.insetBy(dx: 8, dy: 4),
                                   cornerWidth: 18, cornerHeight: 18, transform: nil)
            if bodyShape.contains(local) { return true }
        }
        let renderedClock = clockLayer.presentation() ?? clockLayer
        let clockPoint = renderedClock.convert(point, from: source)
        // Tight union of face, bells, handle and feet; rays are decorative.
        let face = CGPath(ellipseIn: CGRect(x: 8, y: 13, width: 68, height: 68), transform: nil)
        return face.contains(clockPoint) || CGRect(x: 10, y: 76, width: 65, height: 19).contains(clockPoint)
            || CGRect(x: 15, y: 7, width: 55, height: 12).contains(clockPoint)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        containsInteractivePoint(convert(point, from: superview)) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        if containsInteractivePoint(convert(event.locationInWindow, from: nil)) { _ = requestDismissal() }
    }
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
        artworkView.frame = CGRect(x: 0, y: -24, width: 320, height: 230)
        artworkView.wantsLayer = true
        artworkView.layer?.name = "taskTimer.artwork"
        artworkView.layer?.masksToBounds = false
        artworkView.setAccessibilityElement(false)
        rigView.addSubview(artworkView)

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
        artworkView.layer?.addSublayer(arms)
        armHighlight.path = armPath
        armHighlight.fillColor = nil
        armHighlight.strokeColor = QuietOrbitVisualStyle.color(0xEEE7F4, alpha: 0.75)
        armHighlight.lineWidth = 2
        armHighlight.lineCap = .round
        artworkView.layer?.addSublayer(armHighlight)
        artworkView.addSubview(characterView)
        configureClock()
        configureSign()
    }

    private func configureClock() {
        clockLayer.name = "taskTimer.clock"
        clockLayer.frame = CGRect(x: 20, y: 68, width: 84, height: 96)
        clockLayer.masksToBounds = false
        artworkView.layer?.addSublayer(clockLayer)
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
        signView.layer?.backgroundColor = QuietOrbitVisualStyle.color(0x342A40, alpha: 0.98)
        signView.layer?.borderColor = QuietOrbitVisualStyle.color(0xC6B3D8, alpha: 0.85)
        signView.layer?.borderWidth = 1
        signView.layer?.cornerRadius = 10
        signView.layer?.masksToBounds = true
        signView.setAccessibilityElement(false)
        configureLabel(signCaption, size: 9, weight: .medium, color: 0xC8F1E5)
        signCaption.maximumNumberOfLines = 2
        signCaption.wantsLayer = true
        signCaption.layer?.cornerRadius = 5
        signCaption.isHidden = true
        configureLabel(signTitle, size: 12, weight: .semibold, color: 0xF5F1F8)
        signTitle.frame = CGRect(x: 7, y: 7, width: 92, height: 45)
        signTitle.maximumNumberOfLines = 4
        signTitle.lineBreakMode = .byTruncatingTail
        signTitle.cell?.wraps = true
        signTitle.cell?.isScrollable = false
        signView.addSubview(signCaption)
        signView.addSubview(signTitle)
        configureLabel(recordingProjectLabel, size: 12, weight: .semibold, color: 0xF5F1F8)
        recordingProjectLabel.font = RobotProjectSignView.projectFont
        recordingProjectLabel.frame = CGRect(x: 15, y: 4, width: 85, height: 17)
        recordingProjectLabel.maximumNumberOfLines = 1
        recordingProjectLabel.lineBreakMode = .byTruncatingTail
        recordingProjectLabel.isHidden = true
        signView.addSubview(recordingProjectLabel)
        recordingStatusDot.name = "taskTimer.recordingStatus"
        recordingStatusDot.path = CGPath(ellipseIn: CGRect(x: 7, y: 11, width: 4, height: 4), transform: nil)
        recordingStatusDot.isHidden = true
        signView.layer?.addSublayer(recordingStatusDot)
        artworkView.addSubview(signView)
        let hand = CAShapeLayer()
        hand.name = "taskTimer.heldProps.hand"
        hand.path = CGPath(roundedRect: CGRect(x: 203, y: 88, width: 14, height: 13), cornerWidth: 5, cornerHeight: 5, transform: nil)
        hand.fillColor = QuietOrbitVisualStyle.color(0xCFBEDC)
        hand.strokeColor = QuietOrbitVisualStyle.color(0x836495)
        hand.lineWidth = 1.5
        artworkView.layer?.addSublayer(hand)
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
        // Rasterized labels remain crisp at the final three-times scale; the
        // robot, arms and clock remain native vector layers throughout.
        withoutActions {
            if let root = layer { update(root) }
            for label in [signTitle, signCaption, recordingProjectLabel] {
                label.layer?.contentsScale = scale * max(1, displayedScale)
            }
        }
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
