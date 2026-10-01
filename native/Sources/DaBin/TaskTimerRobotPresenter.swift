import AppKit
import QuartzCore

/// A transient, value-only receipt. Acknowledging it never edits the task.
struct TaskTimerCompletion: Equatable, Identifiable, Sendable {
    let id: UUID
    let taskID: UUID
    let taskWords: String

    init(id: UUID = UUID(), taskID: UUID, title: String) {
        self.id = id
        self.taskID = taskID
        taskWords = Self.firstThreeWords(in: title)
    }

    static func firstThreeWords(in title: String) -> String {
        let words = title.split(maxSplits: 3, omittingEmptySubsequences: true,
                                whereSeparator: \.isWhitespace).prefix(3)
        return words.isEmpty ? "Untitled task" : words.joined(separator: " ")
    }
}

enum TaskTimerRobotGeometry {
    @MainActor static func panelFrame(on screen: AutoCaptureRobotScreen) -> CGRect {
        guard screen.frame.width.isFinite, screen.frame.height.isFinite,
              screen.visibleFrame.width.isFinite, screen.visibleFrame.height.isFinite,
              screen.frame.origin.x.isFinite, screen.frame.origin.y.isFinite,
              screen.visibleFrame.origin.x.isFinite, screen.visibleFrame.origin.y.isFinite,
              screen.safeAreaTop.isFinite,
              screen.frame.width > 0, screen.frame.height > 0,
              screen.visibleFrame.width > 0, screen.visibleFrame.height > 0 else { return .zero }
        return AutoCaptureRobotGeometry.panelFrame(on: screen,
            size: TaskTimerRobotView.stageSize, inset: 12)
    }
}

private final class TaskTimerRobotPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    // The measured display owns this small stage, including offscreen QA
    // displays. Never let AppKit silently relocate it onto another monitor.
    var stageDisplayFrame: CGRect?
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        guard let display = stageDisplayFrame else { return super.constrainFrameRect(frameRect, to: screen) }
        return frameRect.intersection(display)
    }
}

/// Unlike a saved-capture burst, an explicit focus alarm waits for acknowledgement.
/// A single reused nonactivating surface queues simultaneous task expiries.
@MainActor final class TaskTimerRobotPresenter {
    typealias PrimaryScreenProvider = @MainActor () -> AutoCaptureRobotScreen?
    let panel: NSPanel
    let content: TaskTimerRobotView
    private(set) var current: TaskTimerCompletion?
    private(set) var pending: [TaskTimerCompletion] = []
    private(set) var isReturning = false
    private(set) var isSuspendedForInteraction = false
    private(set) var isShutDown = false
    private(set) var presentationCount = 0
    var onPresentationChanged: ((Bool) -> Void)?

    private let primaryScreen: PrimaryScreenProvider
    private let reduceMotion: () -> Bool
    private let returnDelay: TimeInterval?
    private var returnTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var reportedVisible = false
    private var displayObserver: NSObjectProtocol?
    private var motionObserver: NSObjectProtocol?

    init(primaryScreen: @escaping PrimaryScreenProvider = { AutoCaptureRobotGeometry.livePrimaryScreen() },
         reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion },
         returnDelay: TimeInterval? = nil) {
        self.primaryScreen = primaryScreen
        self.reduceMotion = reduceMotion
        self.returnDelay = returnDelay.map { max(0, $0.isFinite ? $0 : 0) }
        let frame = CGRect(origin: .zero, size: TaskTimerRobotView.stageSize)
        let panel = TaskTimerRobotPanel(contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let content = TaskTimerRobotView(frame: frame, reduceMotion: reduceMotion)
        self.panel = panel
        self.content = content
        panel.contentView = content
        content.autoresizingMask = [.width, .height]
        content.onDismiss = { [weak self] in self?.acknowledge() }
        panel.title = "DaBin task timer finished"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // The board can subsequently become key or expand under a waiting
        // alarm. Keep acknowledgement above it, but below modal panels/menus.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.sharingType = .none
        panel.animationBehavior = .none
        panel.becomesKeyOnlyIfNeeded = false
        panel.ignoresMouseEvents = false
        panel.alphaValue = 0
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.displayConfigurationChanged() } }
        motionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refreshMotionPreference() } }
    }

    /// Returns true for a newly accepted receipt, even if manual interaction or
    /// an unavailable screen temporarily keeps it queued. Repeated delivery of
    /// one expiry receipt coalesces; separate runs of the same task still queue.
    @discardableResult func present(task: TaskTimerCompletion) -> Bool {
        guard !isShutDown, current?.id != task.id, !pending.contains(where: { $0.id == task.id }) else { return false }
        pending.append(task)
        showNextIfPossible()
        return true
    }

    func acknowledge() {
        guard !isShutDown, current != nil, panel.isVisible, !isReturning else { return }
        isReturning = true
        let reduced = reduceMotion()
        content.beginReturn(reduceMotion: reduced)
        generation &+= 1
        let token = generation
        let delay = returnDelay ?? (reduced ? 0.14 : TaskTimerRobotView.returnDuration)
        returnTask?.cancel()
        returnTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self, !self.isShutDown, self.generation == token else { return }
            self.returnTask = nil
            self.current = nil
            self.isReturning = false
            // Keep capture feedback suspended through a same-stage handoff.
            // Otherwise it would start and immediately be interrupted by the
            // next waiting alarm in this same main-loop turn.
            self.hideSurface(report: false)
            self.showNextIfPossible()
            if !self.panel.isVisible { self.reportVisibility(false) }
        }
    }

    func suspendForInteraction() {
        guard !isShutDown, !isSuspendedForInteraction else { return }
        isSuspendedForInteraction = true
        interruptReturnIfNeeded()
        hideSurface()
    }

    func resumeAfterInteraction() {
        guard !isShutDown, isSuspendedForInteraction else { return }
        isSuspendedForInteraction = false
        showNextIfPossible()
    }

    func displayConfigurationChanged() {
        guard !isShutDown else { return }
        interruptReturnIfNeeded()
        hideSurface(report: false)
        showNextIfPossible()
        if !panel.isVisible { reportVisibility(false) }
    }

    func refreshMotionPreference() {
        guard !isShutDown, panel.isVisible, let current, reduceMotion() else { return }
        if isReturning {
            content.beginReturn(reduceMotion: true)
            return
        }
        // Switching to reduced motion stops all live leap/clock tracks at once.
        content.show(taskTitle: current.taskWords, reduceMotion: true)
    }

    func shutdown() {
        guard !isShutDown else { return }
        isShutDown = true
        generation &+= 1
        returnTask?.cancel(); returnTask = nil
        current = nil; pending.removeAll(); isReturning = false
        hideSurface()
        content.onDismiss = nil
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
        if let motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(motionObserver) }
        displayObserver = nil; motionObserver = nil
        onPresentationChanged = nil
        panel.close()
    }

    private func showNextIfPossible() {
        guard !isShutDown, !isSuspendedForInteraction, !isReturning, !panel.isVisible,
              let screen = primaryScreen() else { return }
        let frame = TaskTimerRobotGeometry.panelFrame(on: screen)
        guard !frame.isEmpty else { return }
        if current == nil, !pending.isEmpty { current = pending.removeFirst() }
        guard let current else { return }
        (panel as? TaskTimerRobotPanel)?.stageDisplayFrame = screen.frame
        panel.setFrame(frame, display: false)
        content.show(taskTitle: current.taskWords, reduceMotion: reduceMotion())
        panel.alphaValue = 1
        // Announce first so the other island surfaces stop before ordering ours.
        reportVisibility(true)
        guard !isShutDown, !isSuspendedForInteraction, self.current != nil else { return }
        panel.orderFrontRegardless()
        presentationCount += 1
        AccessibilityAnnouncement.post("Timer finished: \(current.taskWords). Press the robot to return home.")
    }

    private func interruptReturnIfNeeded() {
        guard isReturning else { return }
        // A click already acknowledged this receipt even if a drag or display
        // change interrupts its final tuck. Do not bring that receipt back.
        generation &+= 1
        returnTask?.cancel(); returnTask = nil
        current = nil
        isReturning = false
    }

    private func hideSurface(report: Bool = true) {
        panel.alphaValue = 0
        panel.orderOut(nil)
        content.reset()
        if report { reportVisibility(false) }
    }

    private func reportVisibility(_ visible: Bool) {
        guard reportedVisible != visible else { return }
        reportedVisible = visible
        onPresentationChanged?(visible)
    }
}
