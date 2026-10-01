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
                       "Task sign keeps the first three real whitespace-separated words: \(input)")
            let id = UUID()
            let eventID = UUID()
            let completion = TaskTimerCompletion(id: eventID, taskID: id, title: input)
            try expect(completion.id == eventID && completion.taskID == id && completion.taskWords == expected,
                       "Completion retains separate expiry and task identities plus normalized words")
        }
        let long = String(repeating: "界", count: 300)
        try expect(TaskTimerCompletion.firstThreeWords(in: "\(long) two 👨‍👩‍👧‍👦 fourth") == "\(long) two 👨‍👩‍👧‍👦",
                   "Long Unicode words are not split by byte or UTF-16 truncation")
        for screen in [display, external] {
            let frame = TaskTimerRobotGeometry.panelFrame(on: screen)
            try expect(frame.size == TaskTimerRobotView.stageSize && screen.frame.contains(frame),
                       "Clock/sign stage fits the measured offscreen island or external display")
            try expect(frame.maxX < 0 && frame.maxY < 0, "Every presenter fixture remains away from the user's desktop")
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
        let third = TaskTimerCompletion(taskID: UUID(), title: "Finish the final mockup")
        var edges: [Bool] = []
        presenter.onPresentationChanged = { edges.append($0) }
        let identity = ObjectIdentifier(presenter.panel)
        try expect(presenter.panel.styleMask.contains(.borderless) && presenter.panel.styleMask.contains(.nonactivatingPanel),
                   "Timer reminder uses a borderless nonactivating native panel")
        try expect(!presenter.panel.canBecomeKey && !presenter.panel.canBecomeMain && !presenter.panel.ignoresMouseEvents,
                   "Acknowledgment accepts clicks without stealing focus")
        try expect(presenter.panel.sharingType == .none, "Private task words are excluded from screen sharing")
        try expect(presenter.present(task: first) && presenter.current == first && presenter.panel.isVisible,
                   "Explicit task timer completion appears immediately")
        try expect(presenter.panel.frame.maxX < 0 && !presenter.panel.isKeyWindow && !presenter.panel.isMainWindow,
                   "Actual reminder surface remains offscreen and never becomes key")
        try expect(!presenter.present(task: first) && presenter.present(task: second) && !presenter.present(task: second)
            && presenter.pending == [second], "Active and queued duplicate task alarms coalesce without losing the next task")
        try expect(first.id != second.id && first.taskID == second.taskID,
                   "A second successful timer run for the same task retains its distinct queued expiry")
        await wait(0.40)
        try expect(presenter.current == first && presenter.pending == [second] && presenter.panel.isVisible && !presenter.isReturning,
                   "Timer alarm has no automatic success-popup timeout")
        presenter.suspendForInteraction(); presenter.suspendForInteraction()
        try expect(presenter.isSuspendedForInteraction && !presenter.panel.isVisible && presenter.current == first,
                   "Manual robot interaction hides but preserves the unacknowledged task")
        try expect(presenter.present(task: third) && presenter.pending == [second, third], "New expiries queue during manual interaction in arrival order")
        presenter.resumeAfterInteraction(); presenter.resumeAfterInteraction()
        try expect(presenter.current == first && presenter.panel.isVisible && ObjectIdentifier(presenter.panel) == identity,
                   "Resume restores the same task using the same single native panel")
        presenter.acknowledge(); presenter.acknowledge()
        try expect(presenter.isReturning, "Acknowledgment starts one return-home transition")
        try await until({ presenter.current == second && !presenter.isReturning }, message: "Only acknowledgement advances to the next queued task")
        try expect(presenter.pending == [third], "First acknowledgment does not discard later tasks")
        screen = nil; presenter.displayConfigurationChanged()
        try expect(presenter.current == second && presenter.pending == [third] && !presenter.panel.isVisible,
                   "Display loss keeps pending and current unacknowledged task receipts")
        screen = external; presenter.displayConfigurationChanged()
        try expect(presenter.current == second && presenter.panel.isVisible
            && presenter.panel.frame == TaskTimerRobotGeometry.panelFrame(on: external), "Replacement display relocates the retained receipt safely")
        presenter.acknowledge()
        presenter.suspendForInteraction()
        await wait(0.10)
        try expect(presenter.current == nil && presenter.pending == [third] && !presenter.isReturning,
                   "Interrupting an acknowledged return never resurrects that task")
        presenter.resumeAfterInteraction()
        try expect(presenter.current == third && presenter.panel.isVisible, "Interaction resumes only the next unacknowledged task")
        reduced = false
        presenter.suspendForInteraction(); presenter.resumeAfterInteraction()
        try expect(!liveAnimations(presenter.content.layer).isEmpty, "Normal motion starts the actual leap/clock tracks")
        reduced = true; presenter.refreshMotionPreference()
        try expect(liveAnimations(presenter.content.layer).isEmpty, "Live Reduce Motion switch stops all motion immediately")
        presenter.acknowledge()
        try await until({ presenter.current == nil && !presenter.panel.isVisible }, message: "Final acknowledgment returns the robot and clears the surface")
        let restarted = TaskTimerCompletion(taskID: first.taskID, title: "Review the design once more")
        try expect(presenter.present(task: restarted), "A restarted timer on the same task can announce after prior acknowledgment")
        presenter.acknowledge(); presenter.shutdown(); presenter.shutdown()
        await wait(0.10)
        try expect(presenter.isShutDown && presenter.current == nil && presenter.pending.isEmpty && !presenter.panel.isVisible
            && !presenter.present(task: second), "Shutdown cancels late return callbacks and permanently clears this presenter")
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
        // No coordinator.start(): monitoring, global shortcuts and user UI never run.
        let state = coordinator.state
        try expect(coordinator.taskTimerRobot.panel.level.rawValue > coordinator.corners.board.level.rawValue,
                   "Outstanding timer stays above the board without making either window key")
        let now = Date().addingTimeInterval(86_400)
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
        try expect(task.taskPlanning?.focusSession == TaskFocusSession(remainingSeconds: 0) && !task.isCompleted,
                   "Expiry commits paused zero without completing the task")
        try expect(coordinator.taskTimerRobot.current?.taskID == task.id
            && coordinator.taskTimerRobot.current?.taskWords == TaskTimerCompletion.firstThreeWords(in: task.title)
            && coordinator.taskTimerRobot.panel.isVisible && coordinator.taskTimerRobot.presentationCount == 1,
                   "The actual ApplicationCoordinator binding presents only after durable expiry")
        try expect(state.selectedDraft?.comment == "An unrelated unsaved fictional note"
            && state.selectedDraft?.planning.focusSession == TaskFocusSession(remainingSeconds: 0), "Immediate expiry rebases timing without erasing draft work")
        try expect(coordinator.autoCaptureRobot.isSuspendedForTaskTimer, "Timer alarm independently owns the robot over Auto Capture")
        state.focusSessions.reconcile(at: deadline.addingTimeInterval(3))
        try expect(coordinator.taskTimerRobot.presentationCount == 1 && coordinator.taskTimerRobot.pending.isEmpty,
                   "Repeated reconciliation announces an expired session exactly once")
        let firstReceiptID = coordinator.taskTimerRobot.current!.id
        try expect(state.configureTaskFocus(task, hours: 0, minutes: 1, start: true, at: now.addingTimeInterval(120)),
                   "The same task can restart while its previous alarm remains outstanding")
        let secondDeadline = task.taskPlanning!.focusSession!.endAt!
        state.focusSessions.reconcile(at: secondDeadline.addingTimeInterval(1))
        try expect(coordinator.taskTimerRobot.current?.id == firstReceiptID
            && coordinator.taskTimerRobot.pending.count == 1
            && coordinator.taskTimerRobot.pending[0].taskID == task.id
            && coordinator.taskTimerRobot.pending[0].id != firstReceiptID,
                   "Two committed runs retain separate expiry receipts before first acknowledgment")
        let secondReceiptID = coordinator.taskTimerRobot.pending[0].id
        let saved = try snapshot(task)
        coordinator.taskTimerRobot.acknowledge()
        try await until({ coordinator.taskTimerRobot.current?.id == secondReceiptID }, message: "First acknowledgment advances to the same task's second expiry")
        coordinator.taskTimerRobot.acknowledge()
        try await until({ coordinator.taskTimerRobot.current == nil }, message: "Actual coordinator timer can be acknowledged")
        try expect(!coordinator.autoCaptureRobot.isSuspendedForTaskTimer, "Acknowledgment releases Auto Capture timer ownership")
        let afterAcknowledgment = try snapshot(task)
        try expect(afterAcknowledgment == saved,
                   "Acknowledgment changes no task data; changed fields: \(try changedFields(saved, afterAcknowledgment))")
        try expect(notifications.requests == 0, "Local focus timers never request notification permission or schedule a system alarm")
        try expect(try CaptureStore(root: root).captures.first { $0.id == task.id }?.taskPlanning?.focusSession == TaskFocusSession(remainingSeconds: 0),
                   "Expired zero state survives reopening the fictional archive")
        let late = try store.createTask(text: "No alarm after shutdown")
        try expect(state.configureTaskFocus(late, hours: 0, minutes: 1, start: true, at: now), "Second fixture timer configures normally")
        let lateDeadline = late.taskPlanning!.focusSession!.endAt!
        coordinator.shutdown()
        state.focusSessions.reconcile(at: lateDeadline.addingTimeInterval(1))
        try expect(state.focusSessions.isShutDown && coordinator.taskTimerRobot.isShutDown
            && late.taskPlanning?.focusSession?.endAt == lateDeadline, "Shutdown prevents stale expiry writes and late robot UI")
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
        try expect(image.width == 640 && image.height == 460, "Timer evidence is actual native-vector presentation at 2x")
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
                try expect(view.isRinging && !view.isReturning && view.displayedTaskTitle == "Review the design",
                           "Held alarm keeps its exact three-word sign until clicked")
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
                try expect(view.characterView.nativeArmsAreHidden,
                           "Held clock/sign use their articulated arms without duplicate canonical greeting arms")
                for name in ["quietOrbit.head", "taskTimer.clock.face", "taskTimer.clock.bell.0", "taskTimer.clock.bell.1",
                             "taskTimer.clock.hands", "taskTimer.sign", "taskTimer.hint"] {
                    try expect(layers(view.layer).contains { $0.name == name }, "Native timer scene retains \(name)")
                }
                try expect(axText(view, selector: "accessibilityIdentifier") == "task-timer-robot"
                    && axText(view, selector: "accessibilityLabel").contains("Review the design"),
                           "Native robot is an accessible acknowledgment button with full task words")
                try nativePNG(view, dark: dark, to: output.appendingPathComponent("\(prefix)-hold@2x.png"))
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
        let point = CGPoint(x: clicked.content.bounds.midX, y: clicked.content.bounds.midY)
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
