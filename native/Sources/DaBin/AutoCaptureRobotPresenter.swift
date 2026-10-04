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

    /// Confirmation text needs a little more room than the legacy eating token.
    /// Its artwork remains beneath the housing/menu bar; the window is passive.
    static func signPanelFrame(on screen: AutoCaptureRobotScreen) -> CGRect {
        let display = screen.frame.standardized
        let visible = screen.visibleFrame.standardized.intersection(display)
        guard !visible.isEmpty, !visible.isNull else { return .zero }
        if let island = cameraIsland(on: screen), screen.isBuiltIn {
            let size = CGSize(width: min(224, display.width), height: min(166, display.height))
            return CGRect(x: min(max(display.minX, island.midX - size.width / 2), display.maxX - size.width),
                          y: max(display.minY, island.maxY - size.height), width: size.width, height: size.height)
        }
        return panelFrame(on: screen, size: CGSize(width: 220, height: 154))
    }

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

/// A tiny, passive destination placard. It deliberately lives outside the
/// character renderer so a new saved capture can wave the sign without
/// restarting the robot's eating choreography.
@MainActor
private final class AutoCaptureProjectSignView: NSView {
    private static let animationKey = "dabin.auto-capture.project-sign-wave"
    private let folder = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private(set) var projectName: String?
    private(set) var waveCount = 0
    private(set) var lastUpdateReducedMotion = false
    var hasActiveWave: Bool { layer?.animation(forKey: Self.animationKey) != nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.94).cgColor
        layer?.cornerRadius = 7
        layer?.borderWidth = 1.5
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.28
        layer?.shadowRadius = 3
        layer?.shadowOffset = CGSize(width: 0, height: -1)

        folder.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)
        folder.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        folder.imageScaling = .scaleProportionallyDown
        addSubview(folder)

        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        addSubview(label)

        isHidden = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        folder.frame = CGRect(x: 7, y: floor((bounds.height - 12) / 2), width: 12, height: 12)
        label.frame = CGRect(x: 23, y: 3, width: max(0, bounds.width - 29), height: bounds.height - 6)
    }

    func preferredWidth(maximum: CGFloat) -> CGFloat {
        let measured = ceil((label.stringValue as NSString).size(
            withAttributes: [.font: label.font!]
        ).width) + 34
        return min(max(0, maximum), max(62, measured))
    }

    func show(projectName: String, color: NSColor?, waveRepetitions: Int,
              reduceMotion: Bool) {
        self.projectName = projectName
        label.stringValue = projectName
        let accent = (color ?? .systemPurple).usingColorSpace(.sRGB) ?? .systemPurple
        folder.contentTintColor = accent
        layer?.borderColor = accent.cgColor
        isHidden = false
        needsLayout = true
        wave(repetitions: waveRepetitions, reduceMotion: reduceMotion)
    }

    func hideAndReset() {
        layer?.removeAnimation(forKey: Self.animationKey)
        layer?.setAffineTransform(.identity)
        isHidden = true
        projectName = nil
        label.stringValue = ""
        waveCount = 0
        lastUpdateReducedMotion = false
    }

    private func wave(repetitions: Int, reduceMotion: Bool) {
        guard repetitions > 0 else { return }
        waveCount = Self.saturatingAdd(waveCount, repetitions)
        lastUpdateReducedMotion = reduceMotion
        layer?.removeAnimation(forKey: Self.animationKey)
        layer?.setAffineTransform(.identity)
        guard !reduceMotion else { return }

        // Normal saves arrive one at a time. A long suspension can coalesce a
        // much larger backlog, so retain its exact logical count while keeping
        // the resumed animation short and allocation-bounded.
        let renderedRepetitions = min(repetitions, 6)
        let cycle: [CGFloat] = [0, -0.10, 0.12, -0.055, 0]
        var values: [NSNumber] = []
        for index in 0..<renderedRepetitions {
            let slice = index == 0 ? cycle : Array(cycle.dropFirst())
            values.append(contentsOf: slice.map { NSNumber(value: Double($0)) })
        }
        let animation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        animation.values = values
        animation.keyTimes = values.indices.map {
            NSNumber(value: values.count == 1 ? 0 : Double($0) / Double(values.count - 1))
        }
        animation.duration = 0.28 * Double(renderedRepetitions)
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.isRemovedOnCompletion = true
        layer?.add(animation, forKey: Self.animationKey)
    }

    private static func saturatingAdd(_ lhs: Int, _ rhs: Int) -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int.max : sum
    }
}

@MainActor
private final class AutoCaptureRobotContentView: NSView {
    private let character: RobotCharacterView
    private let receiptBadge = NSTextField(labelWithString: "✓")
    private let projectSign = AutoCaptureProjectSignView()
    private var islandWidth: CGFloat?
    private var orbitLayout: QuietOrbitLayout?
    private var orbitPerch: QuietOrbitPerch = .bottom
    private let hardwareMask = CAShapeLayer()
    private(set) var badgeText: String?
    var projectName: String? { projectSign.projectName }
    var projectSignWaveCount: Int { projectSign.waveCount }
    var projectSignIsVisible: Bool { !projectSign.isHidden }
    var projectSignHasActiveWave: Bool { projectSign.hasActiveWave }
    var projectSignLastUpdateReducedMotion: Bool { projectSign.lastUpdateReducedMotion }

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
        addSubview(projectSign)

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
            layoutProjectSign()
            layoutReceiptBadge()
            return
        }
        layer?.mask = nil
        character.frame = islandWidth == nil
            ? CGRect(x: 8, y: 5, width: max(0, bounds.width - 16), height: max(0, bounds.height - 13))
            : bounds
        layoutProjectSign()
        layoutReceiptBadge()
    }

    func begin(_ performance: AutoCaptureRobotPerformance, count: Int,
               orbitLayout: QuietOrbitLayout?, projectName: String?,
               projectColor: NSColor?, projectSignWaveCount: Int) {
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
        updateProjectSign(projectName: projectName, color: projectColor,
                          waveRepetitions: projectSignWaveCount,
                          reduceMotion: performance.reduceMotion)
    }

    func updateCount(_ count: Int) {
        character.updateAutoCaptureCount(count)
        badgeText = count > 1 ? "×\(count)" : nil
        receiptBadge.stringValue = count > 1 ? "✓ ×\(count)" : "✓"
        receiptBadge.isHidden = count <= 0 || orbitLayout == nil
        layoutReceiptBadge()
    }

    func updateProjectSign(projectName: String?, color: NSColor?,
                           waveRepetitions: Int, reduceMotion: Bool) {
        guard let projectName else {
            projectSign.hideAndReset()
            return
        }
        projectSign.show(projectName: projectName, color: color,
                         waveRepetitions: waveRepetitions,
                         reduceMotion: reduceMotion)
        layoutProjectSign()
        layoutReceiptBadge()
    }

    func hideProjectSign() {
        projectSign.hideAndReset()
    }

    func hideCharacter() {
        receiptBadge.isHidden = true
        badgeText = nil
        projectSign.hideAndReset()
        character.updateAutoCaptureCount(0)
        character.stopMotion()
    }

    private func layoutProjectSign() {
        guard !projectSign.isHidden else { return }
        let width = projectSign.preferredWidth(maximum: min(112, max(0, bounds.width - 8)))
        let height: CGFloat = 23
        var frame: CGRect
        if let orbitLayout {
            let artwork = orbitLayout.visibleRobotFrame(for: orbitPerch, local: true)
            let proposedX: CGFloat
            switch orbitPerch {
            case .upperLeft, .left, .lowerLeft:
                proposedX = artwork.minX - width + 9
            case .bottom:
                proposedX = artwork.midX - width / 2
            case .lowerRight, .right, .upperRight:
                proposedX = artwork.maxX - 9
            }
            frame = CGRect(x: min(max(4, proposedX), max(4, bounds.width - width - 4)),
                           y: min(max(3, artwork.minY - 5), max(3, bounds.height - height - 3)),
                           width: width, height: height)
            if frame.intersects(orbitLayout.cameraFrameInPanel) {
                frame.origin.y = max(3, orbitLayout.cameraFrameInPanel.minY - height - 3)
            }
        } else {
            frame = CGRect(x: max(4, (bounds.width - width) / 2), y: 5,
                           width: width, height: height)
        }
        projectSign.frame = frame
        projectSign.layoutSubtreeIfNeeded()
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
        if !projectSign.isHidden, frame.intersects(projectSign.frame) {
            let right = projectSign.frame.maxX + 3
            let left = projectSign.frame.minX - width - 3
            if right + width <= bounds.width - 2 {
                frame.origin.x = right
            } else if left >= 2 {
                frame.origin.x = left
            } else {
                frame.origin.y = min(max(2, projectSign.frame.maxY + 2),
                                     max(2, bounds.height - frame.height - 2))
            }
        }
        receiptBadge.frame = frame
    }
}

@MainActor
private struct AutoCaptureRobotDestination {
    let projectName: String?
    let projectColor: NSColor?

    init(projectName: String?, projectColor: NSColor?) {
        let trimmed = projectName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.projectName = trimmed.flatMap { $0.isEmpty ? nil : $0 }
        self.projectColor = self.projectName == nil ? nil : projectColor
    }

    func isSameProject(as other: AutoCaptureRobotDestination) -> Bool {
        projectName == other.projectName
    }

    func preferringColor(from newer: AutoCaptureRobotDestination) -> AutoCaptureRobotDestination {
        AutoCaptureRobotDestination(projectName: projectName,
                                    projectColor: newer.projectColor ?? projectColor)
    }
}

@MainActor
private struct AutoCaptureRobotPendingBurst {
    var count: Int
    var projectSignWaveCount: Int
    var destination: AutoCaptureRobotDestination
    var confirmation: AutoCaptureSignReceipt? = nil
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
    private(set) var currentSignPerformance: AutoCaptureSignPerformance?
    private(set) var currentSignReceipt: AutoCaptureSignReceipt?
    private(set) var confirmationEnabled = true
    private(set) var isSuspendedForScreenCapture = false
    private(set) var performanceStartCount = 0
    private(set) var isSuspendedForBoard = false
    private(set) var isSuspendedForInteraction = false
    private(set) var isSuspendedForTaskTimer = false
    private var isSuspended: Bool { isSuspendedForBoard || isSuspendedForInteraction || isSuspendedForTaskTimer || isSuspendedForScreenCapture }
    let panel: NSPanel
    var badgeText: String? {
        if let receipt = currentSignReceipt { return receipt.count > 1 ? "×\(receipt.count)" : nil }
        return content.badgeText
    }
    var signMessage: String? { currentSignReceipt?.message }
    var pendingConfirmationCount: Int { pendingBursts.compactMap(\.confirmation).reduce(0) { Self.saturatingAdd($0, $1.count) } }
    var pendingConfirmationPerformances: Int { pendingBursts.filter { $0.confirmation != nil }.count }
    var signHasActiveAnimations: Bool { signContent.hasActiveAnimations }
    var currentProjectName: String? { content.projectName }
    var projectSignWaveCount: Int { content.projectSignWaveCount }
    var projectSignIsVisible: Bool { content.projectSignIsVisible }
    var projectSignHasActiveWave: Bool { content.projectSignHasActiveWave }
    var projectSignLastUpdateReducedMotion: Bool { content.projectSignLastUpdateReducedMotion }
    var nextPendingProjectName: String? { pendingBursts.first?.destination.projectName }
    var pendingCaptureCount: Int {
        pendingBursts.reduce(0) { Self.saturatingAdd($0, $1.count) }
    }
    var onPresentationChanged: ((Bool) -> Void)?

    private let content: AutoCaptureRobotContentView
    private let signContent: AutoCaptureSignView
    private let primaryScreenProvider: PrimaryScreenProvider
    private let reduceMotionProvider: ReduceMotionProvider
    private let currentDateProvider: () -> Date
    private let dismissDelayOverride: TimeInterval?
    private var reactionDeck: AutoCaptureRobotReactionDeck
    private var signDeck: AutoCaptureSignDeck
    private let accentProvider: () -> NSColor
    private let appearanceProvider: () -> NSAppearance?
    private let announce: @MainActor (String) -> Void
    private var announcementTask: Task<Void, Never>?
    private var performanceTask: Task<Void, Never>?
    private var lifecycleTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var performanceToken: UInt64 = 0
    private var updateDeadline: Date?
    private var consumptionDeadline: Date?
    private var performanceScreen: AutoCaptureRobotScreen?
    private var activeDestination: AutoCaptureRobotDestination?
    private var pendingBursts: [AutoCaptureRobotPendingBurst] = []
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
         currentDate: @escaping () -> Date = { Date() },
         signDeck: AutoCaptureSignDeck = AutoCaptureSignDeck(),
         accent: @escaping () -> NSColor = { ThemeSettings.accentNSColor(for: ThemeSettings.defaultHex) },
         appearance: @escaping () -> NSAppearance? = { nil },
         announce: @escaping @MainActor (String) -> Void = { AccessibilityAnnouncement.post($0, priority: .low) }) {
        dismissDelayOverride = dismissDelay.map { max(0, $0) }
        primaryScreenProvider = primaryScreen
        reduceMotionProvider = reduceMotion
        currentDateProvider = currentDate
        self.reactionDeck = reactionDeck
        self.signDeck = signDeck
        accentProvider = accent
        appearanceProvider = appearance
        self.announce = announce

        let frame = CGRect(origin: .zero, size: AutoCaptureRobotGeometry.panelSize)
        let panel = AutoCaptureRobotPanel(contentRect: frame,
                                          styleMask: [.borderless, .nonactivatingPanel],
                                          backing: .buffered, defer: false)
        let content = AutoCaptureRobotContentView(frame: frame, reduceMotion: reduceMotion)
        self.panel = panel
        self.content = content
        signContent = AutoCaptureSignView(frame: frame)

        panel.contentView = content
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        // Legacy protection only. Modern macOS does not guarantee that another
        // application's screenshot excludes this window. Confirmation starts
        // after the completed image is durably saved, never before that receipt.
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
    func present(additionalCaptureCount: Int = 1, projectName: String? = nil,
                 projectColor: NSColor? = nil) -> Bool {
        enqueuePresentation(additionalCaptureCount: additionalCaptureCount,
                            projectName: projectName, projectColor: projectColor, confirmation: nil)
    }

    private func enqueuePresentation(additionalCaptureCount: Int, projectName: String?,
                                     projectColor: NSColor?, confirmation: AutoCaptureSignReceipt?) -> Bool {
        guard !isShutDown, additionalCaptureCount > 0 else { return false }
        guard confirmation == nil || confirmationEnabled else { return false }
        let destination = AutoCaptureRobotDestination(projectName: projectName,
                                                      projectColor: projectColor)
        let pending = AutoCaptureRobotPendingBurst(
            count: additionalCaptureCount,
            projectSignWaveCount: destination.projectName == nil ? 0 : 1,
            destination: destination, confirmation: confirmation
        )
        if isSuspended {
            enqueuePending(pending)
            return true
        }

        if state.isVisible, primaryScreenProvider() != performanceScreen {
            displayConfigurationChanged()
        }

        if state.isVisible {
            if let activeDestination,
               activeDestination.isSameProject(as: destination),
               (currentSignReceipt != nil) == (confirmation != nil),
               let deadline = updateDeadline, currentDateProvider() <= deadline {
                guard state.present(additionalCount: additionalCaptureCount) != nil else { return false }
                _ = lifecycle.send(.captureSaved(count: additionalCaptureCount))
                let resolvedDestination = activeDestination.preferringColor(from: destination)
                self.activeDestination = resolvedDestination
                if let confirmation, let current = currentSignReceipt {
                    let combined = current.merging(confirmation)
                    currentSignReceipt = combined
                    signContent.updateReceipt(combined)
                    // An interruption must not discard a count that was only
                    // just added to an otherwise already-readable sign.
                    let updatedCountDeadline = currentDateProvider().addingTimeInterval(0.25)
                    consumptionDeadline = max(consumptionDeadline ?? updatedCountDeadline, updatedCountDeadline)
                } else {
                    content.updateCount(state.visibleCount)
                    content.updateProjectSign(projectName: resolvedDestination.projectName,
                        color: resolvedDestination.projectColor, waveRepetitions: pending.projectSignWaveCount,
                        reduceMotion: reduceMotionProvider())
                }
            } else {
                // A destination change must never relabel a still-active
                // capture. Keep it as a separate performance; late arrivals
                // use the same queue instead of overlapping the retreat.
                enqueuePending(pending)
            }
            return true
        }

        enqueuePending(pending)
        guard let screen = validPrimaryScreen() else {
            return false
        }
        return startPendingPerformanceIfPossible(on: screen)
    }

    /// Live Auto Capture uses only a typed, privacy-safe receipt. A grouped
    /// multi-file paste is one action, regardless of the number of saved files.
    @discardableResult
    func present(confirmation receipt: AutoCaptureSignReceipt) -> Bool {
        enqueuePresentation(additionalCaptureCount: receipt.count, projectName: nil,
                            projectColor: nil, confirmation: receipt)
    }

    func setConfirmationEnabled(_ enabled: Bool) {
        confirmationEnabled = enabled
        guard !enabled else { return }
        pendingBursts.removeAll { $0.confirmation != nil }
        // This preference gates automatic receipts. Existing manual/legacy
        // feedback keeps its own lifecycle; Quiet mode can dismiss both paths.
        if currentSignReceipt != nil || panel.contentView === signContent {
            stopActivePresentation(clearPending: false, closePanel: false)
            _ = startPendingPerformanceIfPossible()
        }
    }

    /// Can also be called by a future DaBin-owned capture operation before it
    /// samples pixels. System screenshot-tool activation uses the same gate.
    func setScreenCaptureInProgress(_ active: Bool) {
        guard !isShutDown, active != isSuspendedForScreenCapture else { return }
        let wasSuspended = isSuspended
        isSuspendedForScreenCapture = active
        if active && !wasSuspended { preserveAndSuspendPresentation() }
        if !active { _ = startPendingPerformanceIfPossible() }
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

    func suspendForTaskTimer() {
        guard !isShutDown, !isSuspendedForTaskTimer else { return }
        let wasSuspended = isSuspended
        isSuspendedForTaskTimer = true
        if !wasSuspended { preserveAndSuspendPresentation() }
    }

    @discardableResult
    func resumeAfterTaskTimer() -> Bool {
        guard !isShutDown, isSuspendedForTaskTimer else { return false }
        isSuspendedForTaskTimer = false
        return startPendingPerformanceIfPossible()
    }

    private func preserveAndSuspendPresentation() {
        if state.isVisible, !activeCaptureWasConsumed {
            prependPending(AutoCaptureRobotPendingBurst(
                count: state.visibleCount,
                projectSignWaveCount: 0,
                destination: activeDestination ?? AutoCaptureRobotDestination(
                    projectName: nil, projectColor: nil), confirmation: currentSignReceipt
            ))
        }
        stopActivePresentation(clearPending: false, closePanel: false)
    }

    /// Called by the screen-parameter observer and exposed for deterministic
    /// coordination tests. A disappearing display never leaves an off-screen
    /// panel ordered in; an available replacement is used immediately.
    func displayConfigurationChanged() {
        guard !isShutDown else { return }
        guard let screen = validPrimaryScreen() else {
            if state.isVisible, !activeCaptureWasConsumed {
                prependPending(AutoCaptureRobotPendingBurst(
                    count: state.visibleCount,
                    projectSignWaveCount: 0,
                    destination: activeDestination ?? AutoCaptureRobotDestination(
                        projectName: nil, projectColor: nil), confirmation: currentSignReceipt
                ))
            }
            stopActivePresentation(clearPending: false, closePanel: false)
            return
        }

        if state.isVisible {
            guard performanceScreen != screen else { return }
            // Attachment geometry and the entrance form one plan. Replaying a
            // completed eating cue would duplicate saved-capture feedback, but
            // an unfinished cue must survive a new display or island layout.
            if !activeCaptureWasConsumed {
                prependPending(AutoCaptureRobotPendingBurst(
                    count: state.visibleCount,
                    projectSignWaveCount: 0,
                    destination: activeDestination ?? AutoCaptureRobotDestination(
                        projectName: nil, projectColor: nil), confirmation: currentSignReceipt
                ))
            }
            stopActivePresentation(clearPending: false, closePanel: false)
        }
        if !isSuspended {
            _ = startPendingPerformanceIfPossible(on: screen)
        }
    }

    func dismiss() {
        guard !isShutDown else { return }
        content.hideProjectSign()
        stopActivePresentation(clearPending: true, closePanel: false, animated: panel.isVisible)
    }

    func shutdown() {
        guard !isShutDown else { return }
        isShutDown = true
        stopActivePresentation(clearPending: true, closePanel: false)
        if let displayObserver {
            NotificationCenter.default.removeObserver(displayObserver)
            self.displayObserver = nil
        }
        panel.alphaValue = 0
        panel.orderOut(nil)
        content.hideCharacter()
        signContent.stop()
        reportPresentation(false)
        panel.close()
    }

    private func beginPerformance(_ pending: AutoCaptureRobotPendingBurst,
                                  on screen: AutoCaptureRobotScreen) -> Bool {
        guard pending.count > 0 else { return false }
        if let confirmation = pending.confirmation { return beginSignPerformance(confirmation, on: screen) }
        let frame = AutoCaptureRobotGeometry.panelFrame(on: screen)
        guard !frame.isEmpty, state.present(additionalCount: pending.count) != nil else {
            prependPending(pending)
            return false
        }

        hideTask?.cancel(); hideTask = nil
        performanceTask?.cancel(); performanceTask = nil
        lifecycleTask?.cancel(); lifecycleTask = nil
        performanceToken &+= 1
        let token = performanceToken
        lifecycle = RobotLifecycle()
        _ = lifecycle.send(.captureSaved(count: pending.count))

        let island = AutoCaptureRobotGeometry.cameraIsland(on: screen)
        let orbit = island.flatMap { QuietOrbitLayout(cameraIsland: $0, displayFrame: screen.frame) }
        let entrance: RobotEntrance = island == nil ? .right : .top
        let performance = reactionDeck.nextPerformance(entrance: entrance,
                                                       reduceMotion: reduceMotionProvider(),
                                                       captureCount: pending.count)
        currentPerformance = performance
        performanceScreen = screen
        activeDestination = pending.destination
        performanceStartCount += 1
        let delay = dismissDelayOverride ?? performance.totalDuration
        let now = currentDateProvider()
        let updateDuration = dismissDelayOverride == nil
            ? updateWindow(in: performance)
            : min(updateWindow(in: performance), delay * 0.65)
        updateDeadline = now.addingTimeInterval(min(delay, updateDuration))
        consumptionDeadline = now.addingTimeInterval(min(delay, consumptionTime(in: performance)))

        (panel as? AutoCaptureRobotPanel)?.cameraStageDisplayFrame = orbit == nil ? nil : screen.frame
        signContent.stop()
        panel.contentView = content
        panel.setFrame(frame, display: true)
        content.begin(performance, count: pending.count, orbitLayout: orbit,
                      projectName: pending.destination.projectName,
                      projectColor: pending.destination.projectColor,
                      projectSignWaveCount: pending.projectSignWaveCount)
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

    private func beginSignPerformance(_ receipt: AutoCaptureSignReceipt,
                                      on screen: AutoCaptureRobotScreen) -> Bool {
        guard confirmationEnabled else { return false }
        let frame = AutoCaptureRobotGeometry.signPanelFrame(on: screen)
        guard !frame.isEmpty, state.present(additionalCount: receipt.count) != nil else { return false }
        hideTask?.cancel(); hideTask = nil
        performanceTask?.cancel(); lifecycleTask?.cancel(); announcementTask?.cancel()
        performanceToken &+= 1
        let token = performanceToken
        let island = screen.isBuiltIn ? AutoCaptureRobotGeometry.cameraIsland(on: screen) : nil
        let performance = signDeck.nextPerformance(entrance: island == nil ? .right : .top,
            reduceMotion: reduceMotionProvider(), captureCount: receipt.count)
        currentPerformance = nil
        currentSignPerformance = performance
        currentSignReceipt = receipt
        performanceScreen = screen
        activeDestination = AutoCaptureRobotDestination(projectName: nil, projectColor: nil)
        performanceStartCount += 1
        lifecycle = RobotLifecycle()
        _ = lifecycle.send(.captureSaved(count: receipt.count))
        let delay = dismissDelayOverride ?? performance.totalDuration
        let now = currentDateProvider()
        let updateDuration = max(0, min(delay * 0.65, performance.readableEndTime - 0.25))
        updateDeadline = now.addingTimeInterval(updateDuration)
        consumptionDeadline = now.addingTimeInterval(min(delay,
            max(performance.readableStartTime + 0.30, updateDuration + 0.02)))

        content.hideCharacter()
        panel.contentView = signContent
        panel.appearance = appearanceProvider()
        (panel as? AutoCaptureRobotPanel)?.cameraStageDisplayFrame = island == nil ? nil : screen.frame
        panel.setFrame(frame, display: true)
        signContent.frame = CGRect(origin: .zero, size: panel.frame.size)
        let localIsland = island.map { $0.offsetBy(dx: -panel.frame.minX, dy: -panel.frame.minY) }
        signContent.begin(performance: performance, receipt: receipt, islandRect: localIsland, accent: accentProvider())
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        reportPresentation(true)

        // One low-priority announcement after the merge window closes. Every
        // count on this sign is represented; later saves belong to the next
        // sign and its own announcement. No AX focus change or private content.
        announcementTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(min(delay, updateDuration + 0.01)))
            guard !Task.isCancelled, let self, self.performanceToken == token,
                  let current = self.currentSignReceipt else { return }
            self.announce(current.accessibilityText)
        }
        let milestones: [(TimeInterval, RobotLifecycle.State)] = [
            (performance.entranceEndTime * 0.35, .climbingOut),
            (performance.readableStartTime, .captureReaction),
            (performance.exitStartTime, .returningToIsland)
        ]
        lifecycleTask = Task { @MainActor [weak self] in
            var cursor: TimeInterval = 0
            for (time, target) in milestones where time <= delay {
                try? await Task.sleep(for: .seconds(max(0, time - cursor)))
                guard !Task.isCancelled, let self, self.performanceToken == token else { return }
                self.advanceLifecycle(to: target)
                cursor = time
            }
        }
        scheduleCompletion(token: token, delay: delay)
        return true
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
        announcementTask?.cancel(); announcementTask = nil
        _ = state.dismissNow()
        _ = lifecycle.send(.interrupt(toward: .hidden))
        currentPerformance = nil
        currentSignPerformance = nil
        currentSignReceipt = nil
        performanceScreen = nil
        activeDestination = nil
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
              !pendingBursts.isEmpty,
              let screen = suppliedScreen ?? validPrimaryScreen() else { return false }
        let pending = pendingBursts.removeFirst()
        return beginPerformance(pending, on: screen)
    }

    private func stopActivePresentation(clearPending: Bool, closePanel: Bool,
                                        animated: Bool = false) {
        performanceTask?.cancel(); performanceTask = nil
        lifecycleTask?.cancel(); lifecycleTask = nil
        hideTask?.cancel(); hideTask = nil
        announcementTask?.cancel(); announcementTask = nil
        performanceToken &+= 1
        _ = state.dismissNow()
        _ = lifecycle.send(.interrupt(toward: .hidden))
        currentPerformance = nil
        currentSignPerformance = nil
        currentSignReceipt = nil
        performanceScreen = nil
        activeDestination = nil
        updateDeadline = nil
        consumptionDeadline = nil
        if clearPending { pendingBursts.removeAll() }
        hidePanel(animated: animated)
        if closePanel { panel.close() }
    }

    private func hidePanel(animated: Bool) {
        guard animated else {
            panel.alphaValue = 0
            panel.orderOut(nil)
            content.hideCharacter()
            signContent.stop()
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
            self.signContent.stop()
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

    private func enqueuePending(_ pending: AutoCaptureRobotPendingBurst) {
        guard pending.count > 0 else { return }
        if let receipt = pending.confirmation,
           let index = pendingBursts.firstIndex(where: { $0.confirmation != nil }) {
            let combined = pendingBursts[index].confirmation!.merging(receipt)
            pendingBursts[index].confirmation = combined
            pendingBursts[index].count = combined.count
            return
        }
        if let last = pendingBursts.indices.last,
           pending.confirmation == nil, pendingBursts[last].confirmation == nil,
           pendingBursts[last].destination.isSameProject(as: pending.destination) {
            pendingBursts[last].count = Self.saturatingAdd(pendingBursts[last].count, pending.count)
            pendingBursts[last].projectSignWaveCount = Self.saturatingAdd(
                pendingBursts[last].projectSignWaveCount, pending.projectSignWaveCount)
            pendingBursts[last].destination = pendingBursts[last].destination
                .preferringColor(from: pending.destination)
        } else {
            pendingBursts.append(pending)
        }
    }

    private func prependPending(_ pending: AutoCaptureRobotPendingBurst) {
        guard pending.count > 0 else { return }
        if let receipt = pending.confirmation {
            // One bounded pending confirmation stores an exact aggregate; it
            // never allocates a queue entry for each rapid capture or project.
            let index = pendingBursts.firstIndex(where: { $0.confirmation != nil })
            var combined = receipt
            if let index { combined = receipt.merging(pendingBursts.remove(at: index).confirmation!) }
            pendingBursts.insert(AutoCaptureRobotPendingBurst(count: combined.count, projectSignWaveCount: 0,
                destination: AutoCaptureRobotDestination(projectName: nil, projectColor: nil), confirmation: combined), at: 0)
            return
        }
        if !pendingBursts.isEmpty,
           pendingBursts[0].confirmation == nil,
           pending.destination.isSameProject(as: pendingBursts[0].destination) {
            pendingBursts[0].count = Self.saturatingAdd(pending.count, pendingBursts[0].count)
            pendingBursts[0].projectSignWaveCount = Self.saturatingAdd(
                pending.projectSignWaveCount, pendingBursts[0].projectSignWaveCount)
            // The first queued value is newer than the interrupted active one.
            pendingBursts[0].destination = pending.destination
                .preferringColor(from: pendingBursts[0].destination)
        } else {
            pendingBursts.insert(pending, at: 0)
        }
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
