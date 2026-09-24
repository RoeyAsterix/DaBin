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
    static let edgeInset: CGFloat = 8

    static func primaryScreen(in screens: [AutoCaptureRobotScreen],
                              mainDisplayID: CGDirectDisplayID) -> AutoCaptureRobotScreen? {
        screens.first { $0.displayID == mainDisplayID }
    }

    /// A real camera housing is the robot's home: the panel meets its lower edge
    /// and shares its center. Other built-in displays retain a safe top-center
    /// fallback; external displays use the unobtrusive top-right.
    static func panelFrame(on screen: AutoCaptureRobotScreen,
                           size requestedSize: CGSize = panelSize,
                           inset requestedInset: CGFloat = edgeInset) -> CGRect {
        let display = screen.frame.standardized
        let visible = screen.visibleFrame.standardized.intersection(display)
        guard !visible.isNull, !visible.isEmpty else { return .zero }

        let size = CGSize(width: min(max(0, requestedSize.width), visible.width),
                          height: min(max(0, requestedSize.height), visible.height))
        let inset = max(0, requestedInset)
        let island = screen.cameraIslandRect?.standardized.intersection(display)
        let validIsland = island.flatMap { $0.isNull || $0.isEmpty ? nil : $0 }

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
        } else if screen.isBuiltIn {
            idealX = display.midX - size.width / 2
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
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class AutoCaptureRobotContentView: NSView {
    private let character: RobotCharacterView
    private let countBadge = NSTextField(labelWithString: "")
    private let islandLip = CALayer()
    private(set) var badgeText: String?

    init(frame frameRect: CGRect,
         reduceMotion: @escaping RobotCharacterView.ReduceMotionProvider) {
        character = RobotCharacterView(frame: .zero, reduceMotion: reduceMotion)
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true
        addSubview(character)

        countBadge.font = .monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        countBadge.alignment = .center
        countBadge.textColor = .white
        countBadge.wantsLayer = true
        countBadge.layer?.backgroundColor = NSColor(calibratedRed: 0.32, green: 0.22,
                                                    blue: 0.43, alpha: 0.98).cgColor
        countBadge.layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.62).cgColor
        countBadge.layer?.borderWidth = 0.8
        countBadge.layer?.cornerRadius = 10
        countBadge.layer?.shadowColor = NSColor.black.cgColor
        countBadge.layer?.shadowOpacity = 0.28
        countBadge.layer?.shadowRadius = 3
        countBadge.layer?.shadowOffset = CGSize(width: 0, height: -1)
        countBadge.isHidden = true
        addSubview(countBadge)

        islandLip.backgroundColor = NSColor(calibratedWhite: 0.055, alpha: 0.98).cgColor
        islandLip.borderColor = NSColor(calibratedWhite: 1, alpha: 0.12).cgColor
        islandLip.borderWidth = 0.7
        islandLip.cornerRadius = 6
        islandLip.shadowColor = NSColor.black.cgColor
        islandLip.shadowOpacity = 0.32
        islandLip.shadowRadius = 3
        islandLip.shadowOffset = CGSize(width: 0, height: -1)
        islandLip.zPosition = 50
        islandLip.isHidden = true
        layer?.addSublayer(islandLip)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        character.frame = CGRect(x: 8, y: 5, width: max(0, bounds.width - 16),
                                 height: max(0, bounds.height - 13))
        countBadge.frame = CGRect(x: max(4, bounds.maxX - 39), y: max(4, bounds.maxY - 30),
                                  width: 33, height: 21)
        islandLip.frame = CGRect(x: bounds.midX - 29, y: bounds.maxY - 9, width: 58, height: 12)
    }

    func begin(_ performance: AutoCaptureRobotPerformance, count: Int, showIslandLip: Bool) {
        updateCount(count)
        islandLip.isHidden = !showIslandLip
        character.playAutoCaptureCelebration(performance)
    }

    func updateCount(_ count: Int) {
        guard count > 1 else {
            badgeText = nil
            countBadge.stringValue = ""
            countBadge.isHidden = true
            return
        }
        let value = count > 99 ? "99+" : "×\(count)"
        badgeText = value
        countBadge.stringValue = value
        countBadge.isHidden = false
    }

    func updateIslandLip(_ visible: Bool) { islandLip.isHidden = !visible }

    func hideCharacter() {
        badgeText = nil
        countBadge.isHidden = true
        islandLip.isHidden = true
        character.stopMotion()
    }
}

/// Shows successful automatic captures without activating DaBin or accepting
/// input. One passive panel and one animation are reused for each visible burst.
@MainActor
final class AutoCaptureRobotPresenter {
    typealias PrimaryScreenProvider = @MainActor () -> AutoCaptureRobotScreen?
    typealias ReduceMotionProvider = () -> Bool

    private(set) var state = AutoCaptureRobotBurstState()
    private(set) var currentPerformance: AutoCaptureRobotPerformance?
    private(set) var performanceStartCount = 0
    let panel: NSPanel
    var badgeText: String? { content.badgeText }

    private let content: AutoCaptureRobotContentView
    private let primaryScreenProvider: PrimaryScreenProvider
    private let reduceMotionProvider: ReduceMotionProvider
    private let dismissDelayOverride: TimeInterval?
    private var reactionDeck: AutoCaptureRobotReactionDeck
    private var performanceTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var performanceToken: UInt64 = 0
    private var isShutDown = false

    /// `dismissDelay` is a focused-test hook. Production uses the complete
    /// anticipation-to-exit duration produced by the reaction deck.
    init(dismissDelay: TimeInterval? = nil,
         primaryScreen: @escaping PrimaryScreenProvider = { AutoCaptureRobotGeometry.livePrimaryScreen() },
         reduceMotion: @escaping ReduceMotionProvider = {
             NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
         },
         reactionDeck: AutoCaptureRobotReactionDeck = AutoCaptureRobotReactionDeck()) {
        dismissDelayOverride = dismissDelay.map { max(0, $0) }
        primaryScreenProvider = primaryScreen
        reduceMotionProvider = reduceMotion
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
    }

    /// Starts one celebration for a new burst. Later successes update the same
    /// badge immediately and leave the active sequence untouched.
    @discardableResult
    func present(additionalCaptureCount: Int = 1) -> Bool {
        guard !isShutDown, additionalCaptureCount > 0,
              let screen = primaryScreenProvider() else { return false }
        let frame = AutoCaptureRobotGeometry.panelFrame(on: screen)
        guard !frame.isEmpty else { return false }

        let wasAnimating = state.isVisible
        guard state.present(additionalCount: additionalCaptureCount) != nil else { return false }
        panel.setFrame(frame, display: true)

        if wasAnimating {
            content.updateCount(state.visibleCount)
            content.updateIslandLip(screen.cameraIslandRect != nil)
            return true
        }

        hideTask?.cancel(); hideTask = nil
        performanceTask?.cancel(); performanceTask = nil
        performanceToken &+= 1
        let token = performanceToken
        let entrance: RobotEntrance = screen.isBuiltIn ? .top : .right
        let performance = reactionDeck.nextPerformance(entrance: entrance,
                                                       reduceMotion: reduceMotionProvider())
        currentPerformance = performance
        performanceStartCount += 1
        content.begin(performance, count: state.visibleCount,
                      showIslandLip: screen.cameraIslandRect != nil)

        panel.alphaValue = 1
        panel.orderFrontRegardless()
        scheduleCompletion(token: token,
                           delay: dismissDelayOverride ?? performance.totalDuration)
        return true
    }

    func dismiss() {
        guard !isShutDown else { return }
        performanceTask?.cancel(); performanceTask = nil
        hideTask?.cancel(); hideTask = nil
        performanceToken &+= 1
        state.dismissNow()
        currentPerformance = nil
        hidePanel(animated: panel.isVisible)
    }

    func shutdown() {
        guard !isShutDown else { return }
        performanceTask?.cancel(); performanceTask = nil
        hideTask?.cancel(); hideTask = nil
        performanceToken &+= 1
        state.dismissNow()
        currentPerformance = nil
        isShutDown = true
        panel.alphaValue = 0
        panel.orderOut(nil)
        content.hideCharacter()
        panel.close()
    }

    private func scheduleCompletion(token: UInt64, delay: TimeInterval) {
        performanceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(0, delay)))
            guard !Task.isCancelled, let self, self.performanceToken == token else { return }
            let latestGeneration = self.state.generation
            guard self.state.dismiss(ifCurrent: latestGeneration) else { return }
            self.performanceTask = nil
            self.currentPerformance = nil
            self.hidePanel(animated: true)
        }
    }

    private func hidePanel(animated: Bool) {
        guard animated else {
            panel.alphaValue = 0
            panel.orderOut(nil)
            content.hideCharacter()
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
        }
    }

    private func fadePanel(to alpha: CGFloat, duration: TimeInterval) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = alpha
        }
    }
}
