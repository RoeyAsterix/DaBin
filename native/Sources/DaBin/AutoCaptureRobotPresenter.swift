import AppKit
import CoreGraphics
import QuartzCore

/// Value facts used to place the passive success confirmation without relying
/// on whichever display currently owns the key window.
struct AutoCaptureRobotScreen: Equatable {
    let displayID: CGDirectDisplayID
    let frame: CGRect
    let visibleFrame: CGRect
    let safeAreaTop: CGFloat
    let isBuiltIn: Bool
    let cameraIslandRect: CGRect?

    init(displayID: CGDirectDisplayID, frame: CGRect, visibleFrame: CGRect,
         safeAreaTop: CGFloat, isBuiltIn: Bool, cameraIslandRect: CGRect? = nil) {
        self.displayID = displayID
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.safeAreaTop = safeAreaTop
        self.isBuiltIn = isBuiltIn
        self.cameraIslandRect = cameraIslandRect
    }
}

enum AutoCaptureRobotGeometry {
    static let panelSize = CGSize(width: 104, height: 122)
    static let islandPanelSize = CGSize(width: 232, height: 150)
    static let edgeInset: CGFloat = 8

    static func cameraIsland(on screen: AutoCaptureRobotScreen) -> CGRect? {
        guard let island = screen.cameraIslandRect?.standardized.intersection(screen.frame.standardized),
              !island.isNull, !island.isEmpty else { return nil }
        return island
    }

    static func primaryScreen(in screens: [AutoCaptureRobotScreen],
                              mainDisplayID: CGDirectDisplayID) -> AutoCaptureRobotScreen? {
        screens.first { $0.displayID == mainDisplayID }
    }

    /// A real camera housing is the robot's home: the panel meets its lower edge
    /// and shares its center. Any display without a verified physical housing,
    /// including a built-in display with only a menu-bar safe area, uses the
    /// unobtrusive top-right fallback.
    static func panelFrame(on screen: AutoCaptureRobotScreen,
                           size requestedSize: CGSize? = nil,
                           inset requestedInset: CGFloat = edgeInset) -> CGRect {
        let display = screen.frame.standardized
        let visible = screen.visibleFrame.standardized.intersection(display)
        guard !visible.isNull, !visible.isEmpty else { return .zero }

        let validIsland = cameraIsland(on: screen)
        if requestedSize == nil, let validIsland,
           let layout = QuietOrbitLayout(cameraIsland: validIsland, displayFrame: display) {
            return layout.panelFrame
        }
        let preferredSize = requestedSize ?? (validIsland == nil ? panelSize : islandPanelSize)
        let size = CGSize(width: min(max(0, preferredSize.width), visible.width),
                          height: min(max(0, preferredSize.height), visible.height))
        let inset = max(0, requestedInset)

        let topLimit: CGFloat
        if let validIsland {
            topLimit = min(visible.maxY, validIsland.minY)
        } else if screen.isBuiltIn {
            let safeTop = min(max(0, screen.safeAreaTop), display.height)
            topLimit = min(visible.maxY, display.maxY - safeTop) - inset
        } else {
            topLimit = visible.maxY - inset
        }

        let idealX: CGFloat
        if let validIsland {
            idealX = validIsland.midX - size.width / 2
        } else {
            idealX = visible.maxX - size.width - inset
        }
        return CGRect(x: min(max(idealX, visible.minX), visible.maxX - size.width),
                      y: min(max(topLimit - size.height, visible.minY), visible.maxY - size.height),
                      width: size.width, height: size.height)
    }

    @MainActor
    static func livePrimaryScreen(screens: [NSScreen] = NSScreen.screens,
                                  mainDisplayID: CGDirectDisplayID = CGMainDisplayID()) -> AutoCaptureRobotScreen? {
        primaryScreen(in: screens.compactMap(screenValue), mainDisplayID: mainDisplayID)
    }

    @MainActor
    private static func screenValue(_ screen: NSScreen) -> AutoCaptureRobotScreen? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else { return nil }
        let displayID = CGDirectDisplayID(number.uint32Value)
        return AutoCaptureRobotScreen(displayID: displayID,
                                      frame: screen.frame,
                                      visibleFrame: screen.visibleFrame,
                                      safeAreaTop: screen.safeAreaInsets.top,
                                      isBuiltIn: CGDisplayIsBuiltin(displayID) != 0,
                                      cameraIslandRect: CornerGeometry.cameraIslandRect(on: screen))
    }
}

/// Pure count reducer retained separately from presentation timing. A capture
/// can update the count without restarting the active celebration.
struct AutoCaptureRobotBurstState: Equatable {
    private(set) var visibleCount = 0
    private(set) var generation: UInt64 = 0
    var isVisible: Bool { visibleCount > 0 }

    @discardableResult
    mutating func present(additionalCount: Int) -> UInt64? {
        guard additionalCount > 0 else { return nil }
        generation &+= 1
        if isVisible {
            visibleCount = additionalCount > Int.max - visibleCount ? Int.max : visibleCount + additionalCount
        } else {
            visibleCount = additionalCount
        }
        return generation
    }

    @discardableResult
    mutating func dismiss(ifCurrent candidate: UInt64) -> Bool {
        guard isVisible, candidate == generation else { return false }
        visibleCount = 0
        return true
    }

    @discardableResult
    mutating func dismissNow() -> UInt64 {
        generation &+= 1
        visibleCount = 0
        return generation
    }
}

private final class AutoCaptureRobotPanel: NSPanel {
    var cameraStageDisplayFrame: CGRect?
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        guard let display = cameraStageDisplayFrame else { return super.constrainFrameRect(frameRect, to: screen) }
        return frameRect.intersection(display)
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class AutoCaptureRobotContentView: NSView {
    private let character: RobotCharacterView
    private let receiptBadge = NSTextField(labelWithString: "✓")
    private var islandWidth: CGFloat?
    private var orbitLayout: QuietOrbitLayout?
    private var orbitPerch: QuietOrbitPerch = .bottom
    private let hardwareMask = CAShapeLayer()
    private(set) var badgeText: String?

    init(frame frameRect: CGRect,
         reduceMotion: @escaping RobotCharacterView.ReduceMotionProvider) {
        character = RobotCharacterView(frame: .zero, reduceMotion: reduceMotion)
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true
        addSubview(character)
        receiptBadge.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        receiptBadge.alignment = .center
        receiptBadge.textColor = .white
        receiptBadge.wantsLayer = true
        receiptBadge.layer?.backgroundColor = NSColor(calibratedRed: 0.34, green: 0.24, blue: 0.46, alpha: 0.96).cgColor
        receiptBadge.layer?.cornerRadius = 7
        receiptBadge.isHidden = true
        receiptBadge.setAccessibilityElement(false)
        addSubview(receiptBadge)

        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        if let orbitLayout {
            character.frame = orbitLayout.robotFrame(for: orbitPerch, local: true)
            hardwareMask.frame = bounds
            let path = CGMutablePath()
            path.addRect(bounds)
            path.addRect(orbitLayout.cameraFrameInPanel)
            hardwareMask.path = path
            hardwareMask.fillRule = .evenOdd
            layer?.mask = hardwareMask
            layoutReceiptBadge()
            return
        }
        layer?.mask = nil
        character.frame = islandWidth == nil
            ? CGRect(x: 8, y: 5, width: max(0, bounds.width - 16), height: max(0, bounds.height - 13))
            : bounds
        layoutReceiptBadge()
    }

    func begin(_ performance: AutoCaptureRobotPerformance, count: Int, orbitLayout: QuietOrbitLayout?) {
        self.orbitLayout = orbitLayout
        // Vary the home only between complete saved-capture performances.
        // Never move a robot while it is eating a burst.
        let perches = QuietOrbitPerch.allCases
        let index = AutoCaptureRobotReaction.eatingReactions.firstIndex(of: performance.reaction) ?? 0
        orbitPerch = perches[index % perches.count]
        self.islandWidth = nil
        character.configureQuietOrbit(true)
        character.configureIslandStage(false)
        character.layer?.setAffineTransform(CGAffineTransform(scaleX: orbitLayout != nil && orbitPerch.isMirrored ? -1 : 1, y: 1))
        needsLayout = true
        layoutSubtreeIfNeeded()
        // The measured housing is subtracted from the transparent stage.
        character.playAutoCaptureCelebration(performance)
        // Starting the renderer resets transient token layers. Apply the exact
        // aggregate after that reset so the visible paper stack is never ×1.
        updateCount(count)
    }

    func updateCount(_ count: Int) {
        character.updateAutoCaptureCount(count)
        badgeText = count > 1 ? "×\(count)" : nil
        receiptBadge.stringValue = count > 1 ? "✓ ×\(count)" : "✓"
        receiptBadge.isHidden = count <= 0 || orbitLayout == nil
        layoutReceiptBadge()
    }

    func hideCharacter() {
        receiptBadge.isHidden = true
        badgeText = nil
        character.updateAutoCaptureCount(0)
        character.stopMotion()
    }

    /// A native-size cue remains readable when the tiny head is partly hidden
    /// by hardware. It shares the same passive, click-through panel.
    private func layoutReceiptBadge() {
        guard let orbitLayout else { return }
        let artwork = orbitLayout.visibleRobotFrame(for: orbitPerch, local: true)
        let width = min(bounds.width, max(18, ceil((receiptBadge.stringValue as NSString).size(
            withAttributes: [.font: receiptBadge.font!]).width) + 8))
        let x = orbitPerch.isMirrored || orbitPerch == .bottom
            ? artwork.maxX + 4 : artwork.minX - width - 4
        var frame = CGRect(x: min(max(2, x), max(2, bounds.width - width - 2)),
                           y: min(max(2, artwork.minY + 3), max(2, bounds.height - 20)),
                           width: width, height: 18)
        if frame.intersects(orbitLayout.cameraFrameInPanel) {
            frame.origin.y = max(2, orbitLayout.cameraFrameInPanel.minY - frame.height - 3)
        }
        receiptBadge.frame = frame
    }
}

/// Shows successful automatic captures without activating DaBin or accepting
/// input. One passive panel and one animation are reused for each visible burst.
@MainActor
final class AutoCaptureRobotPresenter {
    typealias PrimaryScreenProvider = @MainActor () -> AutoCaptureRobotScreen?
    typealias ReduceMotionProvider = () -> Bool

    private(set) var state = AutoCaptureRobotBurstState()
    private(set) var lifecycle = RobotLifecycle()
    private(set) var currentPerformance: AutoCaptureRobotPerformance?
    private(set) var performanceStartCount = 0
    private(set) var pendingCaptureCount = 0
    private(set) var isSuspendedForBoard = false
    private(set) var isSuspendedForInteraction = false
    private var isSuspended: Bool { isSuspendedForBoard || isSuspendedForInteraction }
    let panel: NSPanel
    var badgeText: String? { content.badgeText }
    var onPresentationChanged: ((Bool) -> Void)?

    private let content: AutoCaptureRobotContentView
    private let primaryScreenProvider: PrimaryScreenProvider
    private let reduceMotionProvider: ReduceMotionProvider
    private let currentDateProvider: () -> Date
    private let dismissDelayOverride: TimeInterval?
    private var reactionDeck: AutoCaptureRobotReactionDeck
    private var performanceTask: Task<Void, Never>?
    private var lifecycleTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var performanceToken: UInt64 = 0
    private var updateDeadline: Date?
    private var consumptionDeadline: Date?
    private var performanceScreen: AutoCaptureRobotScreen?
    private var displayObserver: NSObjectProtocol?
    private var reportedPresentation = false
    private var isShutDown = false

    /// `dismissDelay` is a focused-test hook. Production uses the complete
    /// anticipation-to-exit duration produced by the reaction deck.
    init(dismissDelay: TimeInterval? = nil,
         primaryScreen: @escaping PrimaryScreenProvider = { AutoCaptureRobotGeometry.livePrimaryScreen() },
         reduceMotion: @escaping ReduceMotionProvider = {
             NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
         },
         reactionDeck: AutoCaptureRobotReactionDeck = AutoCaptureRobotReactionDeck(),
         currentDate: @escaping () -> Date = { Date() }) {
        dismissDelayOverride = dismissDelay.map { max(0, $0) }
        primaryScreenProvider = primaryScreen
        reduceMotionProvider = reduceMotion
        currentDateProvider = currentDate
        self.reactionDeck = reactionDeck

        let frame = CGRect(origin: .zero, size: AutoCaptureRobotGeometry.panelSize)
        let panel = AutoCaptureRobotPanel(contentRect: frame,
                                          styleMask: [.borderless, .nonactivatingPanel],
                                          backing: .buffered, defer: false)
        let content = AutoCaptureRobotContentView(frame: frame, reduceMotion: reduceMotion)
        self.panel = panel
        self.content = content

        panel.contentView = content
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.sharingType = .none
        panel.animationBehavior = .none
        panel.becomesKeyOnlyIfNeeded = false
        panel.acceptsMouseMovedEvents = false
        panel.ignoresMouseEvents = true
        panel.alphaValue = 0

        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.displayConfigurationChanged() }
        }
    }

    /// Starts one celebration for a new burst. Later successes update the same
    /// badge immediately and leave the active sequence untouched.
    @discardableResult
    func present(additionalCaptureCount: Int = 1) -> Bool {
        guard !isShutDown, additionalCaptureCount > 0 else { return false }
        if isSuspended {
            addPending(additionalCaptureCount)
            return true
        }

        if state.isVisible, primaryScreenProvider() != performanceScreen {
            displayConfigurationChanged()
        }

        if state.isVisible {
            if let deadline = updateDeadline, currentDateProvider() <= deadline {
                guard state.present(additionalCount: additionalCaptureCount) != nil else { return false }
                _ = lifecycle.send(.captureSaved(count: additionalCaptureCount))
                content.updateCount(state.visibleCount)
            } else {
                // The current robot is already retreating. Keep one exact
                // integer for the next performance instead of overlapping it.
                addPending(additionalCaptureCount)
            }
            return true
        }

        guard let screen = validPrimaryScreen() else {
            addPending(additionalCaptureCount)
            return false
        }
        let count = takePending(adding: additionalCaptureCount)
        return beginPerformance(count: count, on: screen)
    }

    /// The full board owns the one robot while it opens and remains visible.
    /// Captures that have not yet reached the eating cue, plus every capture
    /// received during suspension, are retained as one exact bounded count.
    func suspendForBoard() {
        guard !isShutDown, !isSuspendedForBoard else { return }
        let wasSuspended = isSuspended
        isSuspendedForBoard = true
        if !wasSuspended { preserveAndSuspendPresentation() }
    }

    @discardableResult
    func resumeAfterBoard() -> Bool {
        guard !isShutDown, isSuspendedForBoard else { return false }
        isSuspendedForBoard = false
        return startPendingPerformanceIfPossible()
    }

    func suspendForInteraction() {
        guard !isShutDown, !isSuspendedForInteraction else { return }
        let wasSuspended = isSuspended
        isSuspendedForInteraction = true
        if !wasSuspended { preserveAndSuspendPresentation() }
    }

    @discardableResult
    func resumeAfterInteraction() -> Bool {
        guard !isShutDown, isSuspendedForInteraction else { return false }
        isSuspendedForInteraction = false
        return startPendingPerformanceIfPossible()
    }

    private func preserveAndSuspendPresentation() {
        if state.isVisible, !activeCaptureWasConsumed { addPending(state.visibleCount) }
        stopActivePresentation(clearPending: false, closePanel: false)
    }

    /// Called by the screen-parameter observer and exposed for deterministic
    /// coordination tests. A disappearing display never leaves an off-screen
    /// panel ordered in; an available replacement is used immediately.
    func displayConfigurationChanged() {
        guard !isShutDown else { return }
        guard let screen = validPrimaryScreen() else {
            if state.isVisible, !activeCaptureWasConsumed {
                addPending(state.visibleCount)
            }
            stopActivePresentation(clearPending: false, closePanel: false)
            return
        }

        if state.isVisible {
            guard performanceScreen != screen else { return }
            // Attachment geometry and the entrance form one plan. Replaying a
            // completed eating cue would duplicate saved-capture feedback, but
            // an unfinished cue must survive a new display or island layout.
            if !activeCaptureWasConsumed { addPending(state.visibleCount) }
            stopActivePresentation(clearPending: false, closePanel: false)
        }
        if !isSuspended {
            _ = startPendingPerformanceIfPossible(on: screen)
        }
    }

    func dismiss() {
        guard !isShutDown else { return }
        pendingCaptureCount = 0
        stopActivePresentation(clearPending: true, closePanel: false, animated: panel.isVisible)
    }

    func shutdown() {
        guard !isShutDown else { return }
        isShutDown = true
        pendingCaptureCount = 0
        stopActivePresentation(clearPending: true, closePanel: false)
        if let displayObserver {
            NotificationCenter.default.removeObserver(displayObserver)
            self.displayObserver = nil
        }
        panel.alphaValue = 0
        panel.orderOut(nil)
        content.hideCharacter()
        reportPresentation(false)
        panel.close()
    }

    private func beginPerformance(count: Int, on screen: AutoCaptureRobotScreen) -> Bool {
        guard count > 0 else { return false }
        let frame = AutoCaptureRobotGeometry.panelFrame(on: screen)
        guard !frame.isEmpty, state.present(additionalCount: count) != nil else {
            addPending(count)
            return false
        }

        hideTask?.cancel(); hideTask = nil
        performanceTask?.cancel(); performanceTask = nil
        lifecycleTask?.cancel(); lifecycleTask = nil
        performanceToken &+= 1
        let token = performanceToken
        lifecycle = RobotLifecycle()
        _ = lifecycle.send(.captureSaved(count: count))

        let island = AutoCaptureRobotGeometry.cameraIsland(on: screen)
        let orbit = island.flatMap { QuietOrbitLayout(cameraIsland: $0, displayFrame: screen.frame) }
        let entrance: RobotEntrance = island == nil ? .right : .top
        let performance = reactionDeck.nextPerformance(entrance: entrance,
                                                       reduceMotion: reduceMotionProvider(),
                                                       captureCount: count)
        currentPerformance = performance
        performanceScreen = screen
        performanceStartCount += 1
        let delay = dismissDelayOverride ?? performance.totalDuration
        let now = currentDateProvider()
        let updateDuration = dismissDelayOverride == nil
            ? updateWindow(in: performance)
            : min(updateWindow(in: performance), delay * 0.65)
        updateDeadline = now.addingTimeInterval(min(delay, updateDuration))
        consumptionDeadline = now.addingTimeInterval(min(delay, consumptionTime(in: performance)))

        (panel as? AutoCaptureRobotPanel)?.cameraStageDisplayFrame = orbit == nil ? nil : screen.frame
        panel.setFrame(frame, display: true)
        content.begin(performance, count: count, orbitLayout: orbit)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        reportPresentation(true)
        scheduleLifecycle(performance, token: token, maximumDuration: delay)
        scheduleCompletion(token: token, delay: delay)
        return true
    }

    private func scheduleCompletion(token: UInt64, delay: TimeInterval) {
        performanceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(0, delay)))
            guard !Task.isCancelled, let self, self.performanceToken == token else { return }
            self.performanceTask = nil
            self.finishPerformance(token: token)
        }
    }

    private func scheduleLifecycle(_ performance: AutoCaptureRobotPerformance,
                                   token: UInt64, maximumDuration: TimeInterval) {
        let milestones = performance.phases.compactMap { phase -> (TimeInterval, RobotLifecycle.State)? in
            guard phase.startTime <= maximumDuration,
                  let target = lifecycleTarget(for: phase.kind.id) else { return nil }
            return (phase.startTime, target)
        }
        lifecycleTask = Task { @MainActor [weak self] in
            var cursor: TimeInterval = 0
            for (time, target) in milestones {
                try? await Task.sleep(for: .seconds(max(0, time - cursor)))
                guard !Task.isCancelled, let self, self.performanceToken == token else { return }
                self.advanceLifecycle(to: target)
                cursor = time
            }
        }
    }

    private func finishPerformance(token: UInt64) {
        guard performanceToken == token else { return }
        lifecycleTask?.cancel(); lifecycleTask = nil
        _ = state.dismissNow()
        _ = lifecycle.send(.interrupt(toward: .hidden))
        currentPerformance = nil
        performanceScreen = nil
        updateDeadline = nil
        consumptionDeadline = nil

        if !isSuspended, pendingCaptureCount > 0,
           startPendingPerformanceIfPossible() {
            return
        }
        hidePanel(animated: true)
    }

    private func startPendingPerformanceIfPossible(on suppliedScreen: AutoCaptureRobotScreen? = nil) -> Bool {
        guard !isShutDown, !isSuspended, !state.isVisible,
              pendingCaptureCount > 0,
              let screen = suppliedScreen ?? validPrimaryScreen() else { return false }
        let count = pendingCaptureCount
        pendingCaptureCount = 0
        return beginPerformance(count: count, on: screen)
    }

    private func stopActivePresentation(clearPending: Bool, closePanel: Bool,
                                        animated: Bool = false) {
        performanceTask?.cancel(); performanceTask = nil
        lifecycleTask?.cancel(); lifecycleTask = nil
        hideTask?.cancel(); hideTask = nil
        performanceToken &+= 1
        _ = state.dismissNow()
        _ = lifecycle.send(.interrupt(toward: .hidden))
        currentPerformance = nil
        performanceScreen = nil
        updateDeadline = nil
        consumptionDeadline = nil
        if clearPending { pendingCaptureCount = 0 }
        hidePanel(animated: animated)
        if closePanel { panel.close() }
    }

    private func hidePanel(animated: Bool) {
        guard animated else {
            panel.alphaValue = 0
            panel.orderOut(nil)
            content.hideCharacter()
            reportPresentation(false)
            return
        }
        let duration = 0.10
        fadePanel(to: 0, duration: duration)
        hideTask?.cancel()
        let token = performanceToken
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, let self, self.performanceToken == token,
                  !self.state.isVisible else { return }
            self.panel.orderOut(nil)
            self.content.hideCharacter()
            self.hideTask = nil
            self.reportPresentation(false)
        }
    }

    private var activeCaptureWasConsumed: Bool {
        guard state.isVisible else { return true }
        guard let consumptionDeadline else { return false }
        return currentDateProvider() >= consumptionDeadline
    }

    private func validPrimaryScreen() -> AutoCaptureRobotScreen? {
        guard let screen = primaryScreenProvider(),
              !AutoCaptureRobotGeometry.panelFrame(on: screen).isEmpty else { return nil }
        return screen
    }

    private func takePending(adding count: Int) -> Int {
        let result = Self.saturatingAdd(pendingCaptureCount, count)
        pendingCaptureCount = 0
        return result
    }

    private func addPending(_ count: Int) {
        guard count > 0 else { return }
        pendingCaptureCount = Self.saturatingAdd(pendingCaptureCount, count)
    }

    private func reportPresentation(_ visible: Bool) {
        guard visible != reportedPresentation else { return }
        reportedPresentation = visible
        onPresentationChanged?(visible)
    }

    private func advanceLifecycle(to target: RobotLifecycle.State) {
        var remaining = RobotLifecycle.State.allCases.count
        while lifecycle.state != target, remaining > 0 {
            let previous = lifecycle.state
            _ = lifecycle.send(.animationCompleted(generation: lifecycle.generation))
            guard lifecycle.state != previous else { break }
            remaining -= 1
        }
    }

    private func lifecycleTarget(for phaseID: String) -> RobotLifecycle.State? {
        if phaseID == "entrance" { return .climbingOut }
        if phaseID.hasPrefix("eating") { return .eatingCapture }
        if phaseID.hasPrefix("reaction-") || phaseID == "success-check" { return .captureReaction }
        if phaseID == "exit" || phaseID == "fade" { return .returningToIsland }
        return nil
    }

    private func updateWindow(in performance: AutoCaptureRobotPerformance) -> TimeInterval {
        if let eating = performance.phases.first(where: {
            $0.kind.id.hasPrefix("eating") || $0.kind.id == "success-check"
        }) {
            return max(eating.startTime, eating.endTime - min(0.18, eating.duration * 0.25))
        }
        return performance.phases.first {
            $0.kind.id == "exit" || $0.kind.id == "fade"
        }?.startTime ?? performance.totalDuration
    }

    private func consumptionTime(in performance: AutoCaptureRobotPerformance) -> TimeInterval {
        performance.phases.first {
            $0.kind.id.hasPrefix("eating") || $0.kind.id == "success-check"
        }?.endTime ?? updateWindow(in: performance)
    }

    private static func saturatingAdd(_ lhs: Int, _ rhs: Int) -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int.max : sum
    }

    private func fadePanel(to alpha: CGFloat, duration: TimeInterval) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = alpha
        }
    }
}
