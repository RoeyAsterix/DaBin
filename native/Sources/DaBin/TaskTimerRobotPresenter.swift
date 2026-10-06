import AppKit
import QuartzCore

/// Value-only receipt. The coordinator durably acknowledges reminder revisions;
/// the presentation itself never modifies a task or discards an unseen receipt.
struct TaskTimerCompletion: Equatable, Identifiable, Sendable {
    let id: UUID
    let taskID: UUID
    let title: String
    let dueAt: Date?
    let reminderRevision: Int?
    let taskWords: String

    init(id: UUID = UUID(), taskID: UUID, title: String, dueAt: Date? = nil, reminderRevision: Int? = nil) {
        self.id = id
        self.taskID = taskID
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = clean.isEmpty ? "Untitled task" : clean
        self.dueAt = dueAt
        self.reminderRevision = reminderRevision
        taskWords = Self.firstThreeWords(in: title)
    }

    static func firstThreeWords(in title: String) -> String {
        let words = title.split(maxSplits: 3, omittingEmptySubsequences: true,
                                whereSeparator: \.isWhitespace).prefix(3)
        return words.isEmpty ? "Untitled task" : words.joined(separator: " ")
    }
}

enum TaskTimerRobotGeometry {
    @MainActor static func panelFrame(on screen: AutoCaptureRobotScreen, reduceMotion: Bool = false) -> CGRect {
        guard screen.frame.width.isFinite, screen.frame.height.isFinite,
              screen.visibleFrame.width.isFinite, screen.visibleFrame.height.isFinite,
              screen.frame.origin.x.isFinite, screen.frame.origin.y.isFinite,
              screen.visibleFrame.origin.x.isFinite, screen.visibleFrame.origin.y.isFinite,
              screen.safeAreaTop.isFinite,
              screen.frame.width > 0, screen.frame.height > 0,
              screen.visibleFrame.width > 0, screen.visibleFrame.height > 0 else { return .zero }
        let scale: CGFloat = reduceMotion ? 1 : TaskTimerAlarmMotion.maximumScale
        // Reserve the final transparent stage once. Growth stays on the GPU;
        // native click-through routing prevents the spare area blocking apps.
        let size = CGSize(width: TaskTimerRobotView.stageSize.width * scale,
                          height: TaskTimerRobotView.stageSize.height * scale)
        let placement = AutoCaptureRobotScreen(displayID: screen.displayID, frame: screen.frame,
            visibleFrame: screen.visibleFrame, safeAreaTop: screen.safeAreaTop,
            isBuiltIn: screen.isBuiltIn, cameraIslandRect: screen.isBuiltIn ? screen.cameraIslandRect : nil)
        return AutoCaptureRobotGeometry.panelFrame(on: placement, size: size, inset: 12)
    }
}

private final class TaskTimerRobotPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    var stageDisplayFrame: CGRect?
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        guard let display = stageDisplayFrame else { return super.constrainFrameRect(frameRect, to: screen) }
        return frameRect.intersection(display)
    }
}

/// A single persistent, nonactivating reminder. All outstanding receipts are
/// represented by its count. Only a successful durable acknowledgement clears them.
@MainActor final class TaskTimerRobotPresenter {
    typealias PrimaryScreenProvider = @MainActor () -> AutoCaptureRobotScreen?
    let panel: NSPanel
    let content: TaskTimerRobotView
    private(set) var current: TaskTimerCompletion?
    private(set) var pending: [TaskTimerCompletion] = []
    private(set) var isReturning = false
    private(set) var isSuspendedForInteraction = false
    private(set) var isCapturePaused = false
    private(set) var isShutDown = false
    private(set) var presentationCount = 0
    private(set) var escalationLevel = 0
    var onPresentationChanged: ((Bool) -> Void)?
    /// Called before receipts are removed. Return false if persistence failed.
    var onAcknowledge: (([TaskTimerCompletion]) -> Bool)?
    /// Navigation belongs here, after successful persistence, never on arrival.
    var onAcknowledged: (([TaskTimerCompletion]) -> Void)?
    var outstandingReceipts: [TaskTimerCompletion] { (isReturning ? [] : current.map { [$0] } ?? []) + pending }

    private let primaryScreen: PrimaryScreenProvider
    private let reduceMotion: () -> Bool
    private let returnDelay: TimeInterval?
    private var returnTask: Task<Void, Never>?
    private var escalationTask: Task<Void, Never>?
    private var pointerTimer: Timer?
    private var elapsedBeforePause: TimeInterval = 0
    private var activeSince: TimeInterval?
    private var isAcknowledging = false
    private var acknowledgedIDs = Set<UUID>()
    private var deferredReconciliation: (Set<UUID>, Set<UUID>, Set<UUID>?)?
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
        panel.title = "DaBin reminders"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.sharingType = .none
        panel.animationBehavior = .none
        panel.becomesKeyOnlyIfNeeded = false
        panel.ignoresMouseEvents = true
        panel.alphaValue = 0
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.displayConfigurationChanged() } }
        motionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refreshMotionPreference() } }
    }

    @discardableResult func present(task: TaskTimerCompletion) -> Bool {
        guard !isShutDown, !acknowledgedIDs.contains(task.id), current?.id != task.id,
              !pending.contains(where: { $0.id == task.id }) else { return false }
        pending.append(task)
        if panel.isVisible, !isReturning, !isAcknowledging { refreshCount() }
        showNextIfPossible()
        return true
    }

    func acknowledge() {
        guard !isShutDown, current != nil, panel.isVisible, !isReturning, !isAcknowledging else { return }
        // Freeze before calling storage: even a slow/failed save never rings
        // under the user's pointer. Snapshot excludes arrivals during the gate.
        let snapshot = outstandingReceipts
        guard !snapshot.isEmpty else { return }
        isAcknowledging = true
        pauseEscalation()
        content.stopAlarmMotion()
        panel.ignoresMouseEvents = true
        let accepted = onAcknowledge?(snapshot) ?? true
        isAcknowledging = false
        guard !isShutDown else { return }
        if !accepted {
            if let deferred = deferredReconciliation {
                deferredReconciliation = nil
                reconcile(validTaskIDs: deferred.0, validReminderReceiptIDs: deferred.1, validFocusReceiptIDs: deferred.2)
            }
            if panel.isVisible, let current {
                content.show(taskTitle: current.taskWords, reduceMotion: reduceMotion(), count: outstandingReceipts.count,
                             fullTitle: current.title, island: content.islandPlacement, level: escalationLevel, animateEntrance: false)
                content.showAcknowledgementFailure()
                resumeEscalation()
            }
            return
        }
        let ids = Set(snapshot.map(\.id))
        acknowledgedIDs.formUnion(ids)
        pending.removeAll { ids.contains($0.id) }
        isReturning = true
        let reduced = reduceMotion()
        content.beginReturn(reduceMotion: reduced)
        if let deferred = deferredReconciliation {
            deferredReconciliation = nil
            reconcile(validTaskIDs: deferred.0, validReminderReceiptIDs: deferred.1, validFocusReceiptIDs: deferred.2)
        }
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
            self.resetEscalation()
            self.hideSurface(report: false)
            self.showNextIfPossible()
            if !self.panel.isVisible { self.reportVisibility(false) }
        }
        // Opening the requested task/list can legitimately suspend or interrupt
        // the return. Receipt removal is already committed before navigation.
        onAcknowledged?(snapshot)
    }

    /// Call after task/reminder edits, deletion or completion. Focus receipts have
    /// no reminder revision and survive reminder edits while their task exists.
    func reconcile(validTaskIDs: Set<UUID>, validReminderReceiptIDs: Set<UUID>, validFocusReceiptIDs: Set<UUID>? = nil) {
        guard !isShutDown else { return }
        if isAcknowledging { deferredReconciliation = (validTaskIDs, validReminderReceiptIDs, validFocusReceiptIDs); return }
        func valid(_ receipt: TaskTimerCompletion) -> Bool {
            validTaskIDs.contains(receipt.taskID) &&
                (receipt.reminderRevision == nil ? (validFocusReceiptIDs?.contains(receipt.id) ?? true) : validReminderReceiptIDs.contains(receipt.id))
        }
        pending.removeAll { !valid($0) }
        if !isReturning, let current, !valid(current) { self.current = nil }
        guard !isReturning else { return }
        if current == nil {
            if !pending.isEmpty { current = pending.removeFirst() }
            else { resetEscalation(); hideSurface(); return }
        }
        if panel.isVisible { refreshCount() }
        else { showNextIfPossible() }
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
    /// Hide presentation without acknowledging reminders or cancelling focus
    /// timers. Every outstanding occurrence is still available after Resume.
    func setCapturePaused(_ paused: Bool) {
        guard !isShutDown, paused != isCapturePaused else { return }
        isCapturePaused = paused
        if paused {
            interruptReturnIfNeeded()
            hideSurface()
        } else { showNextIfPossible() }
    }
    func displayConfigurationChanged() {
        guard !isShutDown else { return }
        interruptReturnIfNeeded()
        hideSurface(report: false)
        showNextIfPossible()
        if !panel.isVisible { reportVisibility(false) }
    }
    func refreshMotionPreference() {
        guard !isShutDown, panel.isVisible else { return }
        if isReturning {
            if reduceMotion() { content.beginReturn(reduceMotion: true) }
            return
        }
        // Rebuild native geometry as well as the tracks when this setting changes.
        hideSurface(report: false)
        showNextIfPossible()
        if !panel.isVisible { reportVisibility(false) }
    }

    /// Explicit elapsed input keeps stage/bounds tests deterministic without
    /// waiting 24 seconds. Production calls this only at stage boundaries.
    func advanceEscalation(elapsed: TimeInterval) {
        guard !isShutDown, panel.isVisible, !isReturning, !isAcknowledging else { return }
        if elapsed.isFinite, elapsed >= 0, !reduceMotion() {
            elapsedBeforePause = max(elapsedBeforePause, elapsed)
            activeSince = ProcessInfo.processInfo.systemUptime
        }
        escalationLevel = TaskTimerAlarmMotion.level(after: elapsedBeforePause, reduceMotion: reduceMotion())
        content.setEscalation(level: escalationLevel, animated: !reduceMotion())
    }

    /// NSView hit testing alone does not pass clicks through a borderless panel.
    /// Polling the pointer needs no input-monitoring permission and observes no
    /// keyboard events. Only the moving robot/clock enable native mouse routing.
    func updatePointerAcceptance(at screenPoint: CGPoint) {
        guard panel.isVisible, !isReturning, !isAcknowledging, !isShutDown else {
            panel.ignoresMouseEvents = true; return
        }
        let point = content.convert(panel.convertPoint(fromScreen: screenPoint), from: nil)
        panel.ignoresMouseEvents = !content.containsInteractivePoint(point)
    }

    func shutdown() {
        guard !isShutDown else { return }
        isShutDown = true
        generation &+= 1
        returnTask?.cancel(); returnTask = nil
        current = nil; pending.removeAll(); isReturning = false
        deferredReconciliation = nil
        hideSurface()
        content.onDismiss = nil
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
        if let motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(motionObserver) }
        displayObserver = nil; motionObserver = nil
        onPresentationChanged = nil; onAcknowledge = nil; onAcknowledged = nil
        panel.close()
    }

    private func showNextIfPossible() {
        guard !isShutDown, !isCapturePaused, !isSuspendedForInteraction, !isReturning, !panel.isVisible,
              let screen = primaryScreen() else { return }
        let reduced = reduceMotion()
        let frame = TaskTimerRobotGeometry.panelFrame(on: screen, reduceMotion: reduced)
        guard !frame.isEmpty else { return }
        if current == nil, !pending.isEmpty { current = pending.removeFirst() }
        guard let current else { return }
        (panel as? TaskTimerRobotPanel)?.stageDisplayFrame = screen.frame
        panel.setFrame(frame, display: false)
        escalationLevel = TaskTimerAlarmMotion.level(after: elapsedBeforePause, reduceMotion: reduced)
        let island = screen.isBuiltIn && AutoCaptureRobotGeometry.cameraIsland(on: screen) != nil
        content.show(taskTitle: current.taskWords, reduceMotion: reduced, count: outstandingReceipts.count,
                     fullTitle: current.title, island: island, level: escalationLevel,
                     animateEntrance: elapsedBeforePause == 0)
        panel.alphaValue = 1
        reportVisibility(true)
        guard !isShutDown, !isCapturePaused, !isSuspendedForInteraction, self.current != nil else { return }
        panel.orderFrontRegardless()
        presentationCount += 1
        resumeEscalation()
        startPointerRouting()
        AccessibilityAnnouncement.post("\(outstandingReceipts.count) reminder\(outstandingReceipts.count == 1 ? "" : "s"): \(current.title). Press the robot to open.")
    }

    private func refreshCount() {
        guard let current else { return }
        content.updateReminder(taskTitle: current.taskWords, fullTitle: current.title, count: outstandingReceipts.count)
    }
    private func resumeEscalation() {
        escalationTask?.cancel(); escalationTask = nil
        guard !reduceMotion(), !isCapturePaused, panel.isVisible, !isReturning, !isSuspendedForInteraction else { return }
        activeSince = ProcessInfo.processInfo.systemUptime
        let elapsed = elapsedBeforePause
        escalationTask = Task { @MainActor [weak self] in
            for boundary in 1..<TaskTimerAlarmMotion.scales.count {
                let target = Double(boundary) * TaskTimerAlarmMotion.stageInterval
                guard target > elapsed else { continue }
                guard let self else { return }
                let currentElapsed = self.elapsedBeforePause + max(0, ProcessInfo.processInfo.systemUptime - (self.activeSince ?? ProcessInfo.processInfo.systemUptime))
                do { try await Task.sleep(for: .seconds(max(0, target - currentElapsed))) } catch { return }
                guard !Task.isCancelled, !self.isShutDown, self.panel.isVisible else { return }
                self.advanceEscalation(elapsed: target)
            }
        }
    }
    private func pauseEscalation() {
        if let activeSince { elapsedBeforePause += max(0, ProcessInfo.processInfo.systemUptime - activeSince) }
        activeSince = nil
        escalationTask?.cancel(); escalationTask = nil
    }
    private func resetEscalation() {
        pauseEscalation()
        elapsedBeforePause = 0
        escalationLevel = 0
    }
    private func startPointerRouting() {
        pointerTimer?.invalidate()
        updatePointerAcceptance(at: NSEvent.mouseLocation)
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePointerAcceptance(at: NSEvent.mouseLocation) }
        }
        timer.tolerance = 0.008
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
    }
    private func interruptReturnIfNeeded() {
        guard isReturning else { return }
        generation &+= 1
        returnTask?.cancel(); returnTask = nil
        current = nil
        isReturning = false
        resetEscalation()
    }
    private func hideSurface(report: Bool = true) {
        pauseEscalation()
        pointerTimer?.invalidate(); pointerTimer = nil
        panel.ignoresMouseEvents = true
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
