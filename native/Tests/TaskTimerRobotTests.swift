import AppKit
import ApplicationServices
import Foundation
import QuartzCore

@MainActor private final class TimerFixtureNotifications: ReminderNotificationClient {
    private(set) var requests = 0
    func authorization() async -> ReminderAuthorization { .undetermined }
    func requestAuthorization() async throws -> Bool { requests += 1; return false }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { requests += 1 }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}

/// Actual timer presenter and artwork, with fictional tasks, preference domains
/// and displays. No personal archive, desktop capture, clipboard, activation,
/// network service, notification authorization or global input is used.
@main @MainActor private final class TaskTimerRobotTests: NSObject, NSApplicationDelegate {
    private static var checks = 0
    private var result: Int32 = 0

    static func main() {
        let app = NSApplication.shared
        let delegate = TaskTimerRobotTests()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        exit(delegate.result)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await Self.run() }
            catch { result = 1; fputs("Task timer robot QA failed: \(error)\n", stderr) }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "TaskTimerRobotTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        guard try condition() else { throw failure(message) }
    }
    private static func wait(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }
    private static func until(_ condition: () -> Bool, message: String) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline { await wait(0.02) }
        try expect(condition(), message)
    }
    private static var display: AutoCaptureRobotScreen {
        AutoCaptureRobotScreen(displayID: 9,
            frame: CGRect(x: -10_000, y: -10_000, width: 1_200, height: 900),
            visibleFrame: CGRect(x: -10_000, y: -10_000, width: 1_200, height: 875),
            safeAreaTop: 32, isBuiltIn: true,
            cameraIslandRect: CGRect(x: -9_466, y: -9_132, width: 132, height: 32))
    }
    private static var external: AutoCaptureRobotScreen {
        AutoCaptureRobotScreen(displayID: 10,
            frame: CGRect(x: -12_000, y: -10_000, width: 1_600, height: 1_000),
            visibleFrame: CGRect(x: -12_000, y: -10_000, width: 1_600, height: 975),
            safeAreaTop: 0, isBuiltIn: false)
    }
    private static func layers(_ root: CALayer?) -> [CALayer] {
        guard let root else { return [] }
        return [root] + (root.sublayers ?? []).flatMap { layers($0) } + layers(root.mask)
    }
    private static func liveAnimations(_ root: CALayer?) -> [CAAnimation] {
        layers(root).flatMap { layer in (layer.animationKeys() ?? []).compactMap { layer.animation(forKey: $0) } }
    }
    private static func snapshot(_ capture: Capture) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(CaptureSnapshot(capture))
    }
    private static func changedFields(_ before: Data, _ after: Data) throws -> [String] {
        let first = try JSONSerialization.jsonObject(with: before) as! [String: Any]
        let second = try JSONSerialization.jsonObject(with: after) as! [String: Any]
        return try Set(first.keys).union(second.keys).sorted().filter { key in
            let left = try JSONSerialization.data(withJSONObject: [key: first[key] ?? NSNull()], options: [.sortedKeys])
            let right = try JSONSerialization.data(withJSONObject: [key: second[key] ?? NSNull()], options: [.sortedKeys])
            return left != right
        }
    }

    private static func titleAndGeometry() throws {
        for (input, expected) in [
            ("Review the design before launch", "Review the design"),
            ("  one\t two\nthree    four", "one two three"),
            ("Short", "Short"), ("\n\t \u{00a0}", "Untitled task"),
            ("👩🏽‍🔬 Plan 未来 together", "👩🏽‍🔬 Plan 未来"),
            ("שלום\u{00a0}עולם 今日 tomorrow", "שלום עולם 今日")
        ] {
            try expect(TaskTimerCompletion.firstThreeWords(in: input) == expected,
                       "Legacy short-word receipt summary normalizes whitespace without modifying the complete task title: \(input)")
            let id = UUID()
            let eventID = UUID()
            let completion = TaskTimerCompletion(id: eventID, taskID: id, title: input)
            try expect(completion.id == eventID && completion.taskID == id && completion.taskWords == expected,
                       "Completion retains separate expiry and task identities plus normalized words")
            let clean = input.trimmingCharacters(in: .whitespacesAndNewlines)
            try expect(completion.title == (clean.isEmpty ? "Untitled task" : clean),
                       "Full task title survives in the navigation/acknowledgement payload")
        }
        let long = String(repeating: "界", count: 300)
        try expect(TaskTimerCompletion.firstThreeWords(in: "\(long) two 👨‍👩‍👧‍👦 fourth") == "\(long) two 👨‍👩‍👧‍👦",
                   "Long Unicode words are not split by byte or UTF-16 truncation")
        for screen in [display, external] {
            let frame = TaskTimerRobotGeometry.panelFrame(on: screen)
            try expect(TaskTimerRobotView.stageSize == CGSize(width: 320, height: 160)
                && frame.size == CGSize(width: 960, height: 480) && screen.frame.contains(frame),
                       "Clock/sign stage reclaims the removed bottom panel and still fits island/external displays at 3×")
            try expect(frame.maxX < 0 && frame.maxY < 0, "Every presenter fixture remains away from the user's desktop")
        }
        for (seconds, expected) in [(0.0, 0), (7.99, 0), (8, 1), (15.99, 1), (16, 2), (24, 3), (100000, 3)] {
            try expect(TaskTimerAlarmMotion.level(after: seconds) == expected, "Escalation observes fixed eight-second pauses and caps at three")
            try expect(TaskTimerAlarmMotion.level(after: seconds, reduceMotion: true) == 0, "Reduce Motion never escalates")
        }
        for limit in [CGFloat(1.2), 2, 3] {
            for scale in [CGFloat(1), 1.5, 2, 2.98, 3] {
                let factor = TaskTimerAlarmMotion.stretchFactor(for: scale, preferred: 1.025, limit: limit)
                try expect(scale * factor <= limit + 0.0001, "Every growth keyframe obeys both the screen bound and hard 3× cap")
            }
        }
        try expect(TaskTimerAlarmMotion.level(after: .nan) == 0 && TaskTimerAlarmMotion.level(after: -.infinity) == 0,
                   "Invalid elapsed values cannot create invalid transforms")
        try expect(TaskTimerAlarmMotion.scale(for: 3, availableSize: CGSize(width: 500, height: 400),
            baseSize: TaskTimerRobotView.stageSize) == 1.5625, "Growth fits the actual display before reaching the three-times cap")
        for screen in [display, external] {
            let compact = TaskTimerRobotGeometry.panelFrame(on: screen, reduceMotion: true)
            try expect(compact.size == TaskTimerRobotView.stageSize, "Reduced motion reserves only the compact static stage")
            let expanded = TaskTimerRobotGeometry.panelFrame(on: screen)
            try expect(screen.visibleFrame.contains(expanded), "Max-scale stage respects the visible menu-bar safe area")
            if let island = screen.cameraIslandRect { try expect(expanded.maxY <= island.minY, "Island alarm remains beneath the notch") }
        }
        let tiny = AutoCaptureRobotScreen(displayID: 2, frame: CGRect(x: -100, y: -100, width: 40, height: 30),
            visibleFrame: CGRect(x: -100, y: -100, width: 40, height: 30), safeAreaTop: 0, isBuiltIn: false)
        try expect(tiny.frame.contains(TaskTimerRobotGeometry.panelFrame(on: tiny)), "Tiny displays clamp the complete stage safely")
        let invalid = AutoCaptureRobotScreen(displayID: 2, frame: CGRect(x: 0, y: 0, width: CGFloat.nan, height: 30),
            visibleFrame: CGRect(x: 0, y: 0, width: 40, height: 30), safeAreaTop: 0, isBuiltIn: false)
        try expect(TaskTimerRobotGeometry.panelFrame(on: invalid).isEmpty, "Invalid display geometry cannot order a timer panel")
    }

    private static func presenterLifecycle() async throws {
        var screen: AutoCaptureRobotScreen? = display
        var reduced = true
        let presenter = TaskTimerRobotPresenter(primaryScreen: { screen }, reduceMotion: { reduced }, returnDelay: 0.04)
        defer { presenter.shutdown() }
        let first = TaskTimerCompletion(taskID: UUID(), title: "Review the design before launch")
        let second = TaskTimerCompletion(taskID: first.taskID, title: "Review the design again")
        let third = TaskTimerCompletion(taskID: UUID(), title: "Finish the final mockup", dueAt: Date(), reminderRevision: 4)
        var edges: [Bool] = []
        var acknowledged: [[TaskTimerCompletion]] = []
        presenter.onPresentationChanged = { edges.append($0) }
        presenter.onAcknowledged = { acknowledged.append($0) }
        let identity = ObjectIdentifier(presenter.panel)
        try expect(presenter.panel.styleMask.contains(.borderless) && presenter.panel.styleMask.contains(.nonactivatingPanel),
                   "Timer reminder uses a borderless nonactivating native panel")
        try expect(!presenter.panel.canBecomeKey && !presenter.panel.canBecomeMain && presenter.panel.ignoresMouseEvents,
                   "Unused native stage passes through every click without stealing focus")
        try expect(presenter.panel.sharingType == .none, "Private task words are excluded from screen sharing")
        try expect(presenter.present(task: first) && presenter.current == first && presenter.panel.isVisible,
                   "Explicit task timer completion appears immediately")
        try expect(presenter.panel.frame.maxX < 0 && !presenter.panel.isKeyWindow && !presenter.panel.isMainWindow,
                   "Actual reminder surface remains offscreen and never becomes key")
        try expect(!presenter.present(task: first) && presenter.present(task: second) && !presenter.present(task: second)
            && presenter.pending == [second] && presenter.content.reminderCount == 2,
                   "Duplicate receipts coalesce while the badge immediately represents both distinct alarms")
        await wait(0.12)
        try expect(presenter.current == first && presenter.panel.isVisible && acknowledged.isEmpty,
                   "Arrival never acknowledges, navigates or expires automatically")
        presenter.suspendForInteraction(); presenter.suspendForInteraction()
        try expect(presenter.isSuspendedForInteraction && !presenter.panel.isVisible && presenter.current == first,
                   "Manual interaction hides but preserves the unacknowledged task")
        try expect(presenter.present(task: third) && presenter.pending == [second, third], "New expiries queue during manual interaction in arrival order")
        presenter.resumeAfterInteraction(); presenter.resumeAfterInteraction()
        try expect(presenter.content.reminderCount == 3 && ObjectIdentifier(presenter.panel) == identity,
                   "Resume represents every receipt on one reused native panel")
        var attempted: [TaskTimerCompletion] = []
        presenter.onAcknowledge = { snapshot in attempted = snapshot; return false }
        presenter.acknowledge()
        try expect(attempted == [first, second, third], "Durable gate receives the exact represented snapshot")
        try expect(!presenter.isReturning && presenter.outstandingReceipts == [first, second, third] && acknowledged.isEmpty,
                   "Failed persistence preserves every receipt and performs no success navigation")
        let failureLabels = visibleLabels(in: presenter.content)
        try expect(failureLabels.contains { $0.stringValue.localizedCaseInsensitiveContains("retry") }
            && failureLabels.contains { $0.stringValue == first.title }
            && failureLabels.contains { $0.stringValue.contains("3") }
            && presenter.content.reminderCount == 3,
                   "Failed acknowledgement keeps the task title and every receipt, with visible retry feedback on the held sign")
        try expect(axText(presenter.content, selector: "accessibilityHelp").localizedCaseInsensitiveContains("retry"),
                   "Failed acknowledgement remains understandable to accessibility without the removed hint panel")
        try expect(!layers(presenter.content.layer).contains { $0.name == "taskTimer.hint" },
                   "Save failure does not resurrect the removed bottom panel")
        let late = TaskTimerCompletion(taskID: UUID(), title: "Arriving during the click")
        presenter.onAcknowledge = { snapshot in
            _ = presenter.present(task: late)
            presenter.reconcile(validTaskIDs: Set([first.taskID, third.taskID, late.taskID]),
                                validReminderReceiptIDs: [third.id], validFocusReceiptIDs: [first.id, second.id, late.id])
            return snapshot == [first, second, third]
        }
        presenter.acknowledge(); presenter.acknowledge()
        try expect(presenter.isReturning && acknowledged == [[first, second, third]] && presenter.pending == [late],
                   "One click acknowledges its entire visible count, excluding a receipt arriving during the durable gate")
        try expect(!presenter.content.hasActiveRingMotion && presenter.panel.ignoresMouseEvents,
                   "Click stops clock vibration immediately and return cannot intercept clicks")
        try await until({ presenter.current == late && !presenter.isReturning }, message: "A post-click arrival gets its own persistent alarm")
        try expect(!presenter.present(task: first), "Redelivery of an acknowledged receipt cannot resurrect it")
        screen = nil; presenter.displayConfigurationChanged()
        try expect(presenter.current == late && !presenter.panel.isVisible, "Display loss keeps an unacknowledged receipt")
        screen = external; presenter.displayConfigurationChanged()
        try expect(presenter.current == late && presenter.panel.isVisible && !presenter.content.islandPlacement
            && presenter.panel.frame == TaskTimerRobotGeometry.panelFrame(on: external, reduceMotion: true),
                   "Replacement external display uses its safe top-right corner")
        presenter.onAcknowledge = nil
        presenter.acknowledge(); presenter.suspendForInteraction()
        await wait(0.10)
        try expect(presenter.current == nil && presenter.pending.isEmpty && !presenter.isReturning,
                   "Interrupting an acknowledged return never resurrects its task")
        presenter.resumeAfterInteraction()
        try expect(!presenter.panel.isVisible, "No invisible return window remains after interruption")
        let restarted = TaskTimerCompletion(taskID: first.taskID, title: "Review the design once more")
        reduced = false
        try expect(presenter.present(task: restarted), "A distinct restarted focus receipt can announce after acknowledgment")
        presenter.advanceEscalation(elapsed: 8)
        try expect(presenter.escalationLevel == 1 && presenter.content.displayedScale == 1.5, "First stage grows to one and a half times")
        presenter.advanceEscalation(elapsed: 16)
        try expect(presenter.content.displayedScale == 2, "Second stage doubles the visible character")
        presenter.advanceEscalation(elapsed: 24)
        try expect(presenter.content.displayedScale == 3, "Maximum stage is capped at three times")
        screen = nil; presenter.displayConfigurationChanged()
        try expect(!presenter.panel.isVisible && presenter.current == restarted, "Disconnecting during escalation preserves its receipt")
        screen = display; presenter.displayConfigurationChanged()
        try expect(presenter.escalationLevel == 3 && presenter.content.displayedScale == 3,
                   "Display reconnection preserves escalation progress instead of restarting the alarm")
        presenter.suspendForInteraction(); presenter.resumeAfterInteraction()
        try expect(presenter.escalationLevel == 3, "Manual board interaction preserves the alarm stage")
        reduced = true; presenter.refreshMotionPreference()
        let reducedTracks = layers(presenter.content.layer).flatMap { layer in (layer.animationKeys() ?? []).map { "\(layer.name ?? "unnamed"):\($0)" } }
        try expect(reducedTracks.isEmpty && presenter.content.displayedScale == 1,
                   "Live Reduce Motion stops every growth/ring/blink track and restores the compact static robot. Scale=\(presenter.content.displayedScale), tracks=\(reducedTracks)")
        presenter.reconcile(validTaskIDs: [restarted.taskID], validReminderReceiptIDs: [], validFocusReceiptIDs: [])
        try expect(presenter.current == nil && !presenter.panel.isVisible, "Restart/reset removes obsolete focus receipts without deleting the task")
        let edited = TaskTimerCompletion(taskID: third.taskID, title: third.title, dueAt: Date(), reminderRevision: 5)
        try expect(presenter.present(task: edited), "A distinct scheduled occurrence is accepted")
        presenter.reconcile(validTaskIDs: [edited.taskID], validReminderReceiptIDs: [])
        try expect(presenter.current == nil && !presenter.panel.isVisible, "Editing/removing a reminder removes its obsolete revision")
        _ = presenter.present(task: TaskTimerCompletion(taskID: first.taskID, title: "A focus alert"))
        presenter.reconcile(validTaskIDs: [first.taskID], validReminderReceiptIDs: [])
        try expect(presenter.current != nil, "Legacy reconciliation preserves focus receipts while their task exists")
        presenter.reconcile(validTaskIDs: [], validReminderReceiptIDs: [])
        try expect(presenter.current == nil, "Deleted/completed tasks clear focus receipts")
        presenter.shutdown(); presenter.shutdown()
        try expect(presenter.isShutDown && presenter.pending.isEmpty && !presenter.panel.isVisible
            && !presenter.present(task: second), "Shutdown immediately clears every receipt and rejects late callbacks")
        try expect(edges.first == true && edges.last == false, "Presentation ownership exposes real visible/hidden edges")
    }

    private static func durableExpiry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinTimerQA-\(UUID().uuidString)")
        let suite = "DaBinTimerQA.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: PreviewService.linkPreviewPreference)
        defaults.set(true, forKey: QuickAccessSettings.quietKey)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root)
        let notifications = TimerFixtureNotifications()
        let coordinator = ApplicationCoordinator(store: store, defaults: defaults, notificationClient: notifications,
            applicationEvents: NotificationCenter(), workspaceEvents: NotificationCenter(), taskTimerPrimaryScreen: { display })
        defer { coordinator.shutdown() }
        // Start only the local occurrence service: no capture monitoring, global
        // shortcuts or user-facing navigation. Native presenter callbacks are
        // exercised independently above; retain the real durable save gate here.
        var openedReceipts: [TaskTimerCompletion] = []
        coordinator.taskTimerRobot.onAcknowledged = { openedReceipts = $0 }
        coordinator.reminderAlerts.start(applicationEvents: NotificationCenter(), workspaceEvents: NotificationCenter())
        let state = coordinator.state
        try expect(coordinator.taskTimerRobot.panel.level.rawValue > coordinator.corners.board.level.rawValue,
                   "Outstanding timer stays above the board without making either window key")
        let now = Date().addingTimeInterval(-3_600)
        let task = try store.createTask(text: "Review the design before fictional launch")
        try expect(state.configureTaskFocus(task, hours: 0, minutes: 1, start: true, at: now), "Fixture timer is durably configured")
        state.openCapture(task.id)
        state.selectedDraft?.comment = "An unrelated unsaved fictional note"
        let deadline = task.taskPlanning!.focusSession!.endAt!
        store.failureInjector = { if $0 == .beforeMetadataSave { throw CaptureStoreError.importVerificationFailed } }
        state.focusSessions.reconcile(at: deadline.addingTimeInterval(1))
        try expect(coordinator.taskTimerRobot.current == nil && coordinator.taskTimerRobot.presentationCount == 0
            && task.taskPlanning?.focusSession?.endAt == deadline, "A failed expiry commit emits no premature robot alarm")
        store.failureInjector = nil
        state.focusSessions.reconcile(at: deadline.addingTimeInterval(2))
        try expect(task.taskPlanning?.focusSession?.remainingSeconds == 0 && task.taskPlanning?.focusSession?.endAt == nil
            && task.taskPlanning?.focusSession?.completedAlertID != nil && !task.isCompleted,
                   "Expiry commits paused zero without completing the task")
        try expect(coordinator.taskTimerRobot.current?.taskID == task.id
            && coordinator.taskTimerRobot.current?.taskWords == TaskTimerCompletion.firstThreeWords(in: task.title)
            && coordinator.taskTimerRobot.panel.isVisible && coordinator.taskTimerRobot.presentationCount == 1,
                   "The actual ApplicationCoordinator binding presents only after durable expiry")
        try expect(state.selectedDraft?.comment == "An unrelated unsaved fictional note"
            && state.selectedDraft?.planning.focusSession == task.taskPlanning?.focusSession, "Immediate expiry rebases timing without erasing draft work")
        try expect(coordinator.autoCaptureRobot.isSuspendedForTaskTimer, "Timer alarm independently owns the robot over Auto Capture")
        state.focusSessions.reconcile(at: deadline.addingTimeInterval(3))
        try expect(coordinator.taskTimerRobot.presentationCount == 1 && coordinator.taskTimerRobot.pending.isEmpty,
                   "Repeated reconciliation announces an expired session exactly once")
        let firstReceiptID = coordinator.taskTimerRobot.current!.id
        try expect(state.configureTaskFocus(task, hours: 0, minutes: 1, start: true, at: now.addingTimeInterval(120)),
                   "The same task can restart while its previous alarm remains outstanding")
        let secondDeadline = task.taskPlanning!.focusSession!.endAt!
        coordinator.reminderAlerts.reconcile()
        try expect(coordinator.taskTimerRobot.current == nil, "Restarting a focus timer removes its obsolete completion receipt")
        state.focusSessions.reconcile(at: secondDeadline.addingTimeInterval(1))
        try expect(coordinator.taskTimerRobot.current?.id != firstReceiptID
            && coordinator.taskTimerRobot.current?.taskID == task.id
            && coordinator.taskTimerRobot.pending.isEmpty,
                   "A new committed focus expiry owns a fresh durable occurrence")
        let saved = try snapshot(task)
        coordinator.taskTimerRobot.acknowledge()
        try await until({ coordinator.taskTimerRobot.current == nil }, message: "Actual coordinator timer can be acknowledged")
        try expect(!coordinator.autoCaptureRobot.isSuspendedForTaskTimer, "Acknowledgment releases Auto Capture timer ownership")
        try expect(openedReceipts.count == 1 && openedReceipts.first?.title == task.title
            && task.taskPlanning?.focusSession?.acknowledgedAt != nil,
                   "Actual coordinator durably acknowledges before delivering the complete title for explicit navigation")
        let afterAcknowledgment = try snapshot(task)
        let fields = try changedFields(saved, afterAcknowledgment)
        try expect(Set(fields).isSubset(of: ["taskPlanning", "updatedAt"]) && !task.isCompleted,
                   "Acknowledgement only stores focus receipt metadata and never completes the task; changed fields: \(fields)")
        try expect(notifications.requests == 0, "Local focus timers never request notification permission or schedule a system alarm")
        try expect(try CaptureStore(root: root).captures.first { $0.id == task.id }?.taskPlanning?.focusSession == task.taskPlanning?.focusSession,
                   "Expired zero state survives reopening the fictional archive")
        let late = try store.createTask(text: "No alarm after shutdown")
        try expect(state.configureTaskFocus(late, hours: 0, minutes: 1, start: true, at: now), "Second fixture timer configures normally")
        let lateDeadline = late.taskPlanning!.focusSession!.endAt!
        coordinator.shutdown()
        state.focusSessions.reconcile(at: lateDeadline.addingTimeInterval(1))
        try expect(state.focusSessions.isShutDown && coordinator.taskTimerRobot.isShutDown
            && late.taskPlanning?.focusSession?.endAt == lateDeadline, "Shutdown prevents stale expiry writes and late robot UI")
    }

    private static func nativeObjects(in view: NSView) -> [NSObject] {
        var seen = Set<ObjectIdentifier>()
        var result: [NSObject] = []
        func walk(_ value: Any, depth: Int) {
            guard depth < 50, let object = value as? NSObject, seen.insert(ObjectIdentifier(object)).inserted else { return }
            result.append(object)
            for name in ["accessibilityChildren", "accessibilityChildrenInNavigationOrder", "accessibilityContents"] {
                let selector = NSSelectorFromString(name)
                if object.responds(to: selector), let children = object.perform(selector)?.takeUnretainedValue() as? [Any] {
                    children.forEach { walk($0, depth: depth + 1) }
                }
            }
            if let native = object as? NSView { native.subviews.forEach { walk($0, depth: depth + 1) } }
        }
        walk(view, depth: 0)
        NSAccessibility.unignoredChildren(from: [view]).forEach { walk($0, depth: 0) }
        return result
    }

    /// Real composition-root callback, including the separately opened Extended
    /// View. Only an explicit own-window AX press may perform navigation.
    private static func acknowledgedNavigation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinAlarmNavigationQA-\(UUID())")
        let suite = "DaBinAlarmNavigationQA.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: PreviewService.linkPreviewPreference)
        defaults.set(true, forKey: QuickAccessSettings.quietKey)
        let store = try CaptureStore(root: root)
        let coordinator = ApplicationCoordinator(store: store, defaults: defaults, notificationClient: TimerFixtureNotifications(),
            applicationEvents: NotificationCenter(), workspaceEvents: NotificationCenter(), taskTimerPrimaryScreen: { display })
        defer {
            coordinator.shutdown()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let first = try store.createNote(text: "A complete fictional reminder title that exceeds three words")
        first.reminderAt = Date().addingTimeInterval(-120)
        try store.save(captures: [first])
        let frontmost = NSApp.keyWindow
        let wasActive = NSApp.isActive
        coordinator.reminderAlerts.start(applicationEvents: NotificationCenter(), workspaceEvents: NotificationCenter())
        let robot = coordinator.taskTimerRobot
        try expect(robot.current?.taskID == first.id && robot.current?.title == first.title,
                   "Persisted overdue note reaches the actual alarm with its full title")
        try expect(!coordinator.extendedView.window.isVisible && !coordinator.corners.board.isVisible
            && NSApp.keyWindow === frontmost && NSApp.isActive == wasActive,
                   "Reminder arrival leaves the board, Extended View and application focus untouched")
        store.failureInjector = { if $0 == .beforeMetadataSave { throw CaptureStoreError.importVerificationFailed } }
        try expect(robot.content.accessibilityPerformPress(), "The actual alarm accepts explicit acknowledgement")
        try expect(!first.isReminderAcknowledged && robot.current != nil && !coordinator.extendedView.window.isVisible,
                   "A failed coordinator save neither loses the reminder nor opens Extended View")
        store.failureInjector = nil
        try expect(robot.content.accessibilityPerformPress(), "Persistence failure permits a real user retry")
        try expect(first.isReminderAcknowledged && coordinator.extendedView.window.isVisible
            && coordinator.extendedView.captureID == first.id && coordinator.state.selectedCapture?.id == first.id,
                   "Successful robot click durably acknowledges then opens that capture in Extended View")
        coordinator.extendedView.window.setFrameOrigin(CGPoint(x: -9000, y: -9000))
        coordinator.extendedView.window.performClose(nil)
        coordinator.corners.board.orderOut(nil)
        try await until({ !robot.isReturning }, message: "Single-reminder return completes before the next fixture burst")

        let second = try store.createNote(text: "Second fictional overdue reminder with full content")
        let third = try store.createTask(text: "Third fictional due task remains incomplete after opening")
        second.reminderAt = Date().addingTimeInterval(-90)
        third.reminderAt = Date().addingTimeInterval(-60)
        try store.save(captures: [second, third])
        coordinator.reminderAlerts.reconcile()
        try expect(robot.outstandingReceipts.count == 2 && robot.content.reminderCount == 2,
                   "Two due captures produce a single alarm and an accurate count")
        try expect(robot.content.accessibilityPerformPress(), "The combined alarm is acknowledged with one explicit click")
        let extended = coordinator.extendedView
        try expect(second.isReminderAcknowledged && third.isReminderAcknowledged && !third.isCompleted
            && extended.window.isVisible && extended.captureID == nil,
                   "Acknowledged burst opens one complete-reminder list and never completes a task")
        extended.window.setFrameOrigin(CGPoint(x: -9000, y: -9000))
        guard let host = extended.window.contentView else { throw failure("Completed reminder list has no native host") }
        for _ in 0..<4 { host.layoutSubtreeIfNeeded(); await wait(0.05) }
        _ = await Task.detached {
            let process = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            var windows: CFTypeRef?
            return AXUIElementCopyAttributeValue(process, kAXWindowsAttribute as CFString, &windows)
        }.value
        let wanted = "Open reminder: \(third.title)"
        var row: NSObject?
        for _ in 0..<15 {
            row = nativeObjects(in: host).first { object in
                let selector = NSSelectorFromString("accessibilityLabel")
                return object.responds(to: selector) && object.perform(selector)?.takeUnretainedValue() as? String == wanted
            }
            if row != nil { break }
            await wait(0.04)
        }
        guard let row else { throw failure("The actual completed-reminder list omits its full-title task row") }
        let selector = NSSelectorFromString("accessibilityPerformPress")
        typealias Action = @convention(c) (AnyObject, Selector) -> Bool
        try expect(row.responds(to: selector) && unsafeBitCast(row.method(for: selector), to: Action.self)(row, selector),
                   "An acknowledged reminder list row can be opened with native accessibility")
        try expect(extended.captureID == third.id && extended.window.isVisible && coordinator.state.selectedCapture?.id == third.id,
                   "Selecting a completed-reminder row reuses Extended View for the correct task")
    }

    private static func independentAutoCaptureOwnership() throws {
        let auto = AutoCaptureRobotPresenter(dismissDelay: 1, primaryScreen: { display }, reduceMotion: { true })
        defer { auto.shutdown() }
        auto.suspendForBoard(); auto.suspendForTaskTimer()
        try expect(auto.present(additionalCaptureCount: 2) && auto.pendingCaptureCount == 2 && !auto.panel.isVisible,
                   "Automatic capture queues while board and timer own the robot")
        auto.resumeAfterTaskTimer()
        try expect(auto.isSuspendedForBoard && !auto.panel.isVisible && auto.pendingCaptureCount == 2,
                   "Acknowledging a timer does not clear independent board suspension")
        auto.resumeAfterBoard()
        try expect(auto.panel.isVisible && auto.state.visibleCount == 2, "Auto Capture resumes after every independent owner releases")
        auto.suspendForTaskTimer(); auto.suspendForInteraction()
        auto.resumeAfterTaskTimer()
        try expect(!auto.panel.isVisible && auto.pendingCaptureCount == 2, "Timer release never overrides a live manual interaction")
        auto.resumeAfterInteraction()
        try expect(auto.panel.isVisible && auto.state.visibleCount == 2, "Manual release restores retained capture confirmations")
    }

    /// Inspect the real native labels rather than a test-only mirror of the
    /// sign. Hidden recording/count labels must not reappear as an empty panel.
    private static func visibleLabels(in view: NSView) -> [NSTextField] {
        guard !view.isHiddenOrHasHiddenAncestor else { return [] }
        let own = (view as? NSTextField).map { [$0] } ?? []
        return own + view.subviews.flatMap { visibleLabels(in: $0) }
    }
    private static func normalizedTitle(_ title: String) -> String {
        let words = title.split(whereSeparator: \.isWhitespace).map(String.init).joined(separator: " ")
        return words.isEmpty ? "Untitled task" : words
    }
    private static func assertMinimalSign(_ view: TaskTimerRobotView, title: String, count: Int) throws {
        let normalized = normalizedTitle(title)
        let labels = visibleLabels(in: view)
        try expect(view.displayedTaskTitle == normalized && labels.contains { $0.stringValue == normalized },
                   "The actual held sign retains the complete normalized task title, including words after the third")
        try expect(axText(view, selector: "accessibilityLabel").contains(normalized),
                   "The complete task name remains accessible even when its visual lines truncate")
        try expect(!layers(view.layer).contains { $0.name == "taskTimer.hint" }
            && !labels.contains { $0.stringValue == "Time is up" || $0.stringValue == "Click robot to open"
                || $0.stringValue == "Timer finished" },
                   "Alarm artwork has no detached bottom hint panel or obsolete instructional text")
        if count == 1 {
            try expect(labels.count == 1 && labels.first?.stringValue == normalized,
                       "One reminder shows only its name on the held sign, without a redundant REMINDER heading")
        } else {
            try expect(labels.contains { $0.stringValue.contains(String(count))
                    && $0.stringValue.localizedCaseInsensitiveContains("reminder") }
                && view.reminderCount == count,
                       "Multiple reminders retain a visible count beside the full task title")
        }
        try expect(view.bounds.contains(view.signFrame) && view.bounds.contains(view.characterFrame)
            && view.bounds.contains(view.clockFrame),
                   "The complete robot, clock and sign fit the shortened stage")
    }

    private static func axText(_ view: NSView, selector name: String) -> String {
        let selector = NSSelectorFromString(name)
        guard view.responds(to: selector) else { return "" }
        return view.perform(selector)?.takeUnretainedValue() as? String ?? ""
    }
    private static func nativePNG(_ view: TaskTimerRobotView, dark: Bool, to url: URL) throws {
        view.layoutSubtreeIfNeeded()
        CATransaction.flush()
        guard let presentation = view.layer?.presentation(),
              let context = CGContext(data: nil, width: Int(view.bounds.width * 2), height: Int(view.bounds.height * 2),
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw failure("Native timer presentation tree is unavailable") }
        // Generic backdrop, not a desktop screenshot: floating artwork is clear.
        context.setFillColor(CGColor(gray: dark ? 0.10 : 0.97, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
        context.scaleBy(x: 2, y: 2)
        presentation.render(in: context)
        guard let image = context.makeImage(),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw failure("Native timer PNG encoding failed") }
        try expect(image.width == Int(view.bounds.width * 2) && image.height == Int(view.bounds.height * 2),
                   "Timer evidence is actual native-vector presentation at 2x")
        try png.write(to: url, options: .atomic)
    }

    private static func visualAndNativeAcknowledgment(output: URL) async throws {
        for dark in [false, true] {
            for reduced in [false, true] {
                let presenter = TaskTimerRobotPresenter(primaryScreen: { display }, reduceMotion: { reduced }, returnDelay: 0.06)
                let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                presenter.panel.appearance = appearance; presenter.content.appearance = appearance
                defer { presenter.shutdown() }
                let receipt = TaskTimerCompletion(taskID: UUID(), title: "Review the design before tomorrow")
                try expect(presenter.present(task: receipt), "Native timer visual fixture presents")
                let view = presenter.content
                let prefix = "\(dark ? "dark" : "light")-\(reduced ? "reduced" : "normal")"
                await wait(0.16)
                if !reduced {
                    let rig = layers(view.layer).first { $0.name == "taskTimer.rig" }
                    let pose = rig?.presentation()?.transform ?? CATransform3DIdentity
                    try expect(view.hasActiveEntryMotion && pose.m42 > 1,
                               "Actual finite entry is moving, not only an endpoint model")
                    try nativePNG(view, dark: dark, to: output.appendingPathComponent("\(prefix)-entry@2x.png"))
                    await wait(TaskTimerRobotView.entryDuration + 0.12)
                }
                try expect(view.isRinging && !view.isReturning && view.displayedTaskTitle == receipt.title,
                           "Held alarm keeps its complete task title until clicked")
                try assertMinimalSign(view, title: receipt.title, count: 1)
                let rig = layers(view.layer).first { $0.name == "taskTimer.rig" }
                let heldPose = rig?.presentation()?.transform ?? CATransform3DIdentity
                // Offscreen AppKit can retain an expired CA key even when its
                // live presentation has finished. Measure the actual pose, not
                // key existence, and independently reject repeating entry work.
                try expect(CATransform3DIsIdentity(heldPose), "Finite entry reaches the actual static held body pose")
                if let entry = rig?.animation(forKey: "taskTimer.entry.transform") {
                    try expect(!reduced && entry.duration == TaskTimerRobotView.entryDuration
                        && entry.repeatCount == 0 && entry.repeatDuration == 0,
                               "Any retained offscreen entry key is a finite, non-repeating track")
                }
                await wait(0.08)
                let settledPose = rig?.presentation()?.transform ?? CATransform3DIdentity
                try expect(CATransform3DIsIdentity(settledPose), "Held body remains static across two real presentation samples")
                try expect(view.hasActiveRingMotion == !reduced, "Only normal-motion clock ringing continues during hold")
                try expect(view.bounds.contains(view.characterFrame) && view.bounds.contains(view.clockFrame)
                    && view.bounds.contains(view.signFrame), "Robot, physical clock and sign fit their native stage completely")
                let center = CGPoint(x: view.characterFrame.midX, y: view.characterFrame.midY)
                let clockCenter = CGPoint(x: view.clockFrame.midX, y: view.clockFrame.midY)
                let signCenter = CGPoint(x: view.signFrame.midX, y: view.signFrame.midY)
                try expect(view.containsInteractivePoint(center) && view.containsInteractivePoint(clockCenter),
                           "The rendered robot and clock are native click targets")
                try expect(!view.containsInteractivePoint(signCenter) && !view.containsInteractivePoint(CGPoint(x: 2, y: 2)),
                           "The held sign and transparent padding never intercept clicks")
                presenter.updatePointerAcceptance(at: presenter.panel.convertPoint(toScreen: view.convert(center, to: nil)))
                try expect(!presenter.panel.ignoresMouseEvents, "Native panel accepts clicks only over the rendered robot")
                presenter.updatePointerAcceptance(at: presenter.panel.convertPoint(toScreen: view.convert(signCenter, to: nil)))
                try expect(presenter.panel.ignoresMouseEvents, "Native panel genuinely passes clicks through its sign and transparent region")
                try expect(view.characterView.nativeArmsAreHidden,
                           "Held clock/sign use their articulated arms without duplicate canonical greeting arms")
                for name in ["quietOrbit.head", "taskTimer.clock.face", "taskTimer.clock.bell.0", "taskTimer.clock.bell.1",
                             "taskTimer.clock.hands", "taskTimer.sign"] {
                    try expect(layers(view.layer).contains { $0.name == name }, "Native timer scene retains \(name)")
                }
                try expect(axText(view, selector: "accessibilityIdentifier") == "task-timer-robot"
                    && axText(view, selector: "accessibilityLabel").contains(receipt.title),
                           "Native robot is an accessible acknowledgment button with the complete task name")
                try nativePNG(view, dark: dark, to: output.appendingPathComponent("\(prefix)-hold@2x.png"))
                if !reduced {
                    for level in 1...3 {
                        presenter.advanceEscalation(elapsed: Double(level) * TaskTimerAlarmMotion.stageInterval)
                        await wait(TaskTimerAlarmMotion.growthDuration + 0.4)
                        try expect(view.displayedScale == TaskTimerAlarmMotion.scales[level], "Actual native scene reaches escalation scale \(level)")
                        try expect(view.bounds.contains(view.characterFrame) && view.bounds.contains(view.clockFrame)
                            && view.bounds.contains(view.signFrame), "Escalated native artwork stays inside its safe stage")
                        try nativePNG(view, dark: dark, to: output.appendingPathComponent("\(prefix)-stage-\(level)@2x.png"))
                    }
                }
                await wait(0.16)
                try expect(presenter.current == receipt && presenter.panel.isVisible, "Clock ringing has no automatic dismissal")
                try expect(view.accessibilityPerformPress() && !view.accessibilityPerformPress(), "Real native AX press acknowledges exactly once")
                try expect(presenter.isReturning && !view.isRinging && !view.hasActiveRingMotion,
                           "Acknowledgment stops ringing and begins the return-home path")
                try await until({ presenter.current == nil && !presenter.panel.isVisible }, message: "Native AX acknowledgment completes cleanup")
                try expect(view.isHidden && !view.isReturning && liveAnimations(view.layer).isEmpty, "Returned scene leaves no running artwork animations")
            }
        }
        var reduced = false
        let clicked = TaskTimerRobotPresenter(primaryScreen: { display }, reduceMotion: { reduced })
        defer { clicked.shutdown() }
        var dismissals = 0
        let original = clicked.content.onDismiss
        clicked.content.onDismiss = { dismissals += 1; original?() }
        _ = clicked.present(task: TaskTimerCompletion(taskID: UUID(), title: "Early native mouse press"))
        await wait(0.08)
        try expect(clicked.content.hasActiveEntryMotion, "Early-click fixture is in its actual live entry phase")
        // Use actual rendered geometry during entry, not the transparent panel center.
        let body = clicked.content.characterFrame.intersection(clicked.content.bounds)
        let point = CGPoint(x: body.midX, y: body.midY)
        try expect(clicked.content.containsInteractivePoint(point), "Early click targets the visible robot, not transparent padding")
        clicked.updatePointerAcceptance(at: clicked.panel.convertPoint(toScreen: clicked.content.convert(point, to: nil)))
        try expect(!clicked.panel.ignoresMouseEvents, "Native click routing tracks the actual moving robot during entrance")
        clicked.updatePointerAcceptance(at: clicked.panel.convertPoint(toScreen: CGPoint(x: 2, y: 2)))
        try expect(clicked.panel.ignoresMouseEvents, "The moving alarm still passes clicks through empty native stage pixels")
        guard let event = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: clicked.panel.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1) else { throw failure("Own-window mouse event cannot be constructed") }
        clicked.content.mouseDown(with: event); clicked.content.mouseDown(with: event)
        try expect(dismissals == 1 && clicked.isReturning && !clicked.content.accessibilityPerformPress(),
                   "Mouse press during entry acknowledges once; duplicate mouse/AX actions are ignored")
        await wait(0.09)
        reduced = true; clicked.refreshMotionPreference()
        try expect(!clicked.content.hasActiveReturnMotion && clicked.content.isReturning
            && !clicked.content.hasActiveRingMotion, "Live Reduce Motion during return freezes travel and clock motion")
        try expect(liveAnimations(clicked.content.layer).allSatisfy { ($0 as? CAPropertyAnimation)?.keyPath == "opacity" },
                   "Reduced mid-return animation is only the permitted opacity fade")
        try await until({ !clicked.panel.isVisible }, message: "Early acknowledgment returns without focus theft")
        try expect(!clicked.panel.isKeyWindow && !clicked.panel.isMainWindow && dismissals == 1, "Neither entry click nor return takes foreground focus")
    }

    private static func signVariants(output: URL) async throws {
        let variants: [(String, String, Int)] = [
            ("short", "Send invoice", 1),
            ("long", "  Review the complete client launch presentation and confirm the final artwork before sending  ", 1),
            ("multiple", "Review client artwork", 3),
            ("mixed-language", "日本語のデザインを確認して送信する שלום עולם 📋", 1)
        ]
        for dark in [false, true] {
            for (name, title, count) in variants {
                let presenter = TaskTimerRobotPresenter(primaryScreen: { display }, reduceMotion: { true }, returnDelay: 0.04)
                defer { presenter.shutdown() }
                let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                presenter.panel.appearance = appearance; presenter.content.appearance = appearance
                let primary = TaskTimerCompletion(taskID: UUID(), title: title)
                try expect(presenter.present(task: primary), "Native \(name) sign fixture presents")
                if count > 1 {
                    for index in 2...count {
                        try expect(presenter.present(task: TaskTimerCompletion(taskID: UUID(), title: "Additional reminder \(index)")),
                                   "A separate completed reminder contributes to the same sign count")
                    }
                }
                await wait(0.12)
                let view = presenter.content
                try assertMinimalSign(view, title: title, count: count)
                try expect(presenter.panel.frame.size == TaskTimerRobotView.stageSize
                    && !presenter.panel.isKeyWindow && !presenter.panel.isMainWindow
                    && liveAnimations(view.layer).isEmpty,
                           "Compact sign variants remain static and nonactivating under Reduce Motion")
                let signPoint = CGPoint(x: view.signFrame.midX, y: view.signFrame.midY)
                let clockPoint = CGPoint(x: view.clockFrame.midX, y: view.clockFrame.midY)
                try expect(!view.containsInteractivePoint(signPoint) && view.containsInteractivePoint(clockPoint),
                           "Changing title length or count leaves sign passive and clock clickable")
                try nativePNG(view, dark: dark, to: output.appendingPathComponent("sign-\(name)-\(dark ? "dark" : "light")@2x.png"))
                if count > 1 {
                    presenter.onAcknowledge = { _ in false }
                    try expect(view.accessibilityPerformPress(), "Multiple-reminder fixture exercises failed acknowledgement")
                    await wait(0.08)
                    let labels = visibleLabels(in: view)
                    try expect(presenter.outstandingReceipts.count == count
                        && labels.contains { $0.stringValue.localizedCaseInsensitiveContains("retry") }
                        && labels.contains { $0.stringValue.contains(String(count)) }
                        && labels.contains { $0.stringValue == normalizedTitle(title) },
                               "The held sign communicates a retry without losing title or pending reminders")
                    try nativePNG(view, dark: dark, to: output.appendingPathComponent("sign-retry-\(dark ? "dark" : "light")@2x.png"))
                }
            }
        }
    }

    /// The tallest supported sign combines a long task, active project,
    /// pending count and save failure. Sample actual presentation frames during
    /// every spring/balance transition; endpoint-only checks missed edge clips.
    private static func combinedSignGrowth(output: URL) async throws {
        let presenter = TaskTimerRobotPresenter(primaryScreen: { display }, reduceMotion: { false }, returnDelay: 0.04)
        defer { presenter.shutdown() }
        presenter.panel.appearance = NSAppearance(named: .darkAqua)
        presenter.content.appearance = NSAppearance(named: .darkAqua)
        let title = "Review the complete client launch presentation and confirm the final artwork before sending"
        presenter.content.setProjectRecording(projectName: "Project Atlas", isPaused: false)
        for index in 1...3 {
            let receipt = TaskTimerCompletion(taskID: UUID(), title: index == 1 ? title : "Additional task \(index)")
            try expect(presenter.present(task: receipt), "Combined sign collects each distinct completed reminder")
        }
        await wait(TaskTimerRobotView.entryDuration + 0.15)
        presenter.onAcknowledge = { _ in false }
        try expect(presenter.content.accessibilityPerformPress(), "Combined sign exercises the durable acknowledgement failure")
        await wait(0.08)
        let view = presenter.content
        try expect(view.recordingProjectName == "Project Atlas" && view.recordingSignFontSize == 12
            && visibleLabels(in: view).contains { $0.stringValue == "Project Atlas" }
            && view.displayedTaskTitle == title && presenter.outstandingReceipts.count == 3,
                   "Tallest sign retains its complete task, active 12-point project and all pending receipts")
        for level in 1...3 {
            presenter.advanceEscalation(elapsed: Double(level) * TaskTimerAlarmMotion.stageInterval)
            for sample in 1...24 {
                await wait(0.05)
                let sign = view.signFrame
                try expect(sign.width > 0 && sign.height > 0 && view.bounds.contains(sign),
                           "Tallest sign remains fully inside the native stage during level \(level), sample \(sample): \(sign)")
                let signPoint = CGPoint(x: sign.midX, y: sign.midY)
                try expect(!view.containsInteractivePoint(signPoint),
                           "The growing retry/project sign never becomes an extra click target")
                if sample == 5 || sample == 24 {
                    try nativePNG(view, dark: true,
                        to: output.appendingPathComponent("sign-combined-stage-\(level)-sample-\(sample)@2x.png"))
                }
            }
            try expect(view.displayedScale == TaskTimerAlarmMotion.scales[level]
                && view.bounds.contains(view.characterFrame) && view.bounds.contains(view.clockFrame),
                       "Robot and clock reach the expected bounded scale beside the tallest sign")
        }
        let labels = visibleLabels(in: view)
        try expect(labels.contains { $0.stringValue.localizedCaseInsensitiveContains("retry") }
            && labels.contains { $0.stringValue.contains("3") }
            && labels.contains { $0.stringValue == title }
            && presenter.outstandingReceipts.count == 3 && !presenter.isReturning,
                   "Growth never clears retry feedback, the full title or any outstanding receipt")
    }

    private static func run() async throws {
        try titleAndGeometry()
        try await presenterLifecycle()
        try await durableExpiry()
        try independentAutoCaptureOwnership()
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("build/qa/task-timer-robot", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try await visualAndNativeAcknowledgment(output: output)
        try await signVariants(output: output)
        try await combinedSignGrowth(output: output)
        try await acknowledgedNavigation()
        let report: [String: Any] = ["checksPassed": checks,
            "renderMethod": "Actual production Core Animation presentation tree at native 2x over generic light/dark backdrops",
            "privacy": "Fictional local tasks, temporary preferences/archive, offscreen injected displays, own-window AX/mouse methods; no desktop capture, clipboard, network or global input",
            "entryDuration": TaskTimerRobotView.entryDuration, "returnDuration": TaskTimerRobotView.returnDuration,
            "acknowledgment": "Native accessibilityPerformPress and own-window mouseDown during active entry"]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("task-timer-robot-report.json"), options: .atomic)
        print("PASS: \(checks) task timer title, geometry, presenter, durable expiry, integration, native 2x artwork and acknowledgment checks. \(output.path)")
    }
}
