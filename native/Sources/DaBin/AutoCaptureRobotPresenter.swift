import AppKit
import CoreGraphics
import QuartzCore

/// The screen facts needed to place the passive automatic-capture confirmation.
/// Keeping these as values makes multi-display and notch geometry testable without
/// creating a window or depending on the current desktop arrangement.
struct AutoCaptureRobotScreen: Equatable {
    let displayID: CGDirectDisplayID
    let frame: CGRect
    let visibleFrame: CGRect
    let safeAreaTop: CGFloat
    let isBuiltIn: Bool
}

enum AutoCaptureRobotGeometry {
    static let panelSize = CGSize(width: 88, height: 104)
    static let edgeInset: CGFloat = 8

    /// Selects the hardware primary display. `NSScreen.main` follows the key
    /// window, so it is deliberately not used for this background presentation.
    static func primaryScreen(in screens: [AutoCaptureRobotScreen],
                              mainDisplayID: CGDirectDisplayID) -> AutoCaptureRobotScreen? {
        screens.first { $0.displayID == mainDisplayID }
    }

    /// The built-in display presents below its safe top area, centered under the
    /// camera housing. An external primary display uses its unobtrusive top-right.
    static func panelFrame(on screen: AutoCaptureRobotScreen,
                           size requestedSize: CGSize = panelSize,
                           inset requestedInset: CGFloat = edgeInset) -> CGRect {
        let display = screen.frame.standardized
        let visible = screen.visibleFrame.standardized.intersection(display)
        guard !visible.isNull, !visible.isEmpty else { return .zero }

        let size = CGSize(width: min(max(0, requestedSize.width), visible.width),
                          height: min(max(0, requestedSize.height), visible.height))
        let inset = max(0, requestedInset)
        let topLimit: CGFloat
        if screen.isBuiltIn {
            let safeTop = min(max(0, screen.safeAreaTop), display.height)
            topLimit = min(visible.maxY, display.maxY - safeTop)
        } else {
            topLimit = visible.maxY
        }

        let idealX = screen.isBuiltIn
            ? display.midX - size.width / 2
            : visible.maxX - size.width - inset
        let idealY = topLimit - size.height - inset
        return CGRect(x: min(max(idealX, visible.minX), visible.maxX - size.width),
                      y: min(max(idealY, visible.minY), visible.maxY - size.height),
                      width: size.width, height: size.height)
    }

    @MainActor
    static func livePrimaryScreen(screens: [NSScreen] = NSScreen.screens,
                                  mainDisplayID: CGDirectDisplayID = CGMainDisplayID()) -> AutoCaptureRobotScreen? {
        let values = screens.compactMap(screenValue)
        return primaryScreen(in: values, mainDisplayID: mainDisplayID)
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
                                      isBuiltIn: CGDisplayIsBuiltin(displayID) != 0)
    }
}

/// Pure burst reducer. Every presentation returns a generation that owns the
/// current dismissal deadline. A superseded deadline cannot dismiss a later burst.
struct AutoCaptureRobotBurstState: Equatable {
    private(set) var visibleCount = 0
    private(set) var generation: UInt64 = 0

    var isVisible: Bool { visibleCount > 0 }

    @discardableResult
    mutating func present(additionalCount: Int) -> UInt64? {
        guard additionalCount > 0 else { return nil }
        generation &+= 1
        if isVisible {
            visibleCount = additionalCount > Int.max - visibleCount
                ? Int.max
                : visibleCount + additionalCount
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

    /// Invalidates any scheduled generation even if the panel is already hidden.
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

    init(frame frameRect: CGRect,
         reduceMotion: @escaping RobotCharacterView.ReduceMotionProvider) {
        character = RobotCharacterView(frame: .zero, reduceMotion: reduceMotion)
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(character)

        countBadge.font = .monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        countBadge.alignment = .center
        countBadge.textColor = .white
        countBadge.wantsLayer = true
        countBadge.layer?.backgroundColor = NSColor(calibratedRed: 0.32, green: 0.22,
                                                    blue: 0.43, alpha: 0.96).cgColor
        countBadge.layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.46).cgColor
        countBadge.layer?.borderWidth = 0.7
        countBadge.layer?.cornerRadius = 9
        countBadge.layer?.shadowColor = NSColor.black.cgColor
        countBadge.layer?.shadowOpacity = 0.18
        countBadge.layer?.shadowRadius = 2
        countBadge.layer?.shadowOffset = CGSize(width: 0, height: -1)
        addSubview(countBadge)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        character.frame = CGRect(x: 8, y: 8, width: max(0, bounds.width - 16),
                                 height: max(0, bounds.height - 16))
        countBadge.frame = CGRect(x: max(4, bounds.maxX - 35), y: max(4, bounds.maxY - 27),
                                  width: 29, height: 19)
    }

    func present(count: Int, entrance: RobotEntrance) {
        countBadge.stringValue = count > 99 ? "99+" : "×\(count)"
        character.refreshMotionPreference()
        character.send(.reveal(entrance))
        character.send(.result(.success))
    }

    func hideCharacter() { character.stopMotion() }
}

/// Shows successful automatic captures without activating DaBin or accepting
/// input. The same passive panel is reused for the presenter's full lifetime.
@MainActor
final class AutoCaptureRobotPresenter {
    typealias PrimaryScreenProvider = @MainActor () -> AutoCaptureRobotScreen?
    typealias ReduceMotionProvider = () -> Bool

    private(set) var state = AutoCaptureRobotBurstState()
    let panel: NSPanel

    private let content: AutoCaptureRobotContentView
    private let primaryScreenProvider: PrimaryScreenProvider
    private let dismissDelay: TimeInterval
    private var dismissTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var isShutDown = false

    init(dismissDelay: TimeInterval = 2.0,
         primaryScreen: @escaping PrimaryScreenProvider = {
             AutoCaptureRobotGeometry.livePrimaryScreen()
         },
         reduceMotion: @escaping ReduceMotionProvider = {
             NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
         }) {
        self.dismissDelay = max(0, dismissDelay)
        primaryScreenProvider = primaryScreen

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
        // Keep a confirmation that is still visible from being composited into
        // the user's next screenshot or screen-share frame.
        panel.sharingType = .none
        panel.animationBehavior = .none
        panel.becomesKeyOnlyIfNeeded = false
        panel.acceptsMouseMovedEvents = false
        panel.ignoresMouseEvents = true
        panel.alphaValue = 0
    }

    /// Adds successful captures to the current visible burst, repositions on the
    /// hardware primary display, and gives the whole burst a fresh dismissal time.
    @discardableResult
    func present(additionalCaptureCount: Int = 1) -> Bool {
        guard !isShutDown, additionalCaptureCount > 0,
              let screen = primaryScreenProvider() else { return false }
        let frame = AutoCaptureRobotGeometry.panelFrame(on: screen)
        guard !frame.isEmpty,
              let generation = state.present(additionalCount: additionalCaptureCount) else { return false }

        dismissTask?.cancel()
        hideTask?.cancel(); hideTask = nil
        let wasVisible = panel.isVisible
        panel.setFrame(frame, display: true)
        content.present(count: state.visibleCount, entrance: screen.isBuiltIn ? .top : .right)

        if !wasVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        fadePanel(to: 1, duration: 0.16)
        scheduleDismiss(generation: generation)
        return true
    }

    func dismiss() {
        guard !isShutDown else { return }
        dismissTask?.cancel(); dismissTask = nil
        hideTask?.cancel(); hideTask = nil
        let generation = state.dismissNow()
        hidePanel(generation: generation, animated: panel.isVisible)
    }

    /// One-way lifecycle cleanup for the composition root.
    func shutdown() {
        guard !isShutDown else { return }
        dismissTask?.cancel(); dismissTask = nil
        hideTask?.cancel(); hideTask = nil
        state.dismissNow()
        isShutDown = true
        panel.alphaValue = 0
        panel.orderOut(nil)
        content.hideCharacter()
        panel.close()
    }

    private func scheduleDismiss(generation: UInt64) {
        let delay = dismissDelay
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.dismiss(generation: generation)
        }
    }

    private func dismiss(generation: UInt64) {
        guard state.dismiss(ifCurrent: generation) else { return }
        dismissTask = nil
        hidePanel(generation: generation, animated: true)
    }

    private func hidePanel(generation: UInt64, animated: Bool) {
        guard animated else {
            panel.alphaValue = 0
            panel.orderOut(nil)
            content.hideCharacter()
            return
        }
        let duration = 0.18
        fadePanel(to: 0, duration: duration)
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, let self,
                  !self.state.isVisible, self.state.generation == generation else { return }
            self.panel.orderOut(nil)
            self.content.hideCharacter()
            self.hideTask = nil
        }
    }

    /// Alpha is the only panel-level transition. RobotCharacterView removes its
    /// travel, keyframes, and ambient motion when the macOS preference is enabled,
    /// leaving this short fade as the complete Reduce Motion presentation.
    private func fadePanel(to alpha: CGFloat, duration: TimeInterval) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = alpha
        }
    }
}
