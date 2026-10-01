import AppKit
import Foundation

@MainActor private final class RobotWindowNotificationClient: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .undetermined }
    func requestAuthorization() async throws -> Bool { false }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}

/// Live-panel integration. Other window suites disable the transform so their
/// drag, filter and capture assertions retain independent, deterministic timing.
@main @MainActor
final class RobotWindowTransitionTests: NSObject, NSApplicationDelegate {
    private static var checks = 0
    private static func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard value() else {
            throw NSError(domain: "RobotWindowTransitionTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
    private static func wait(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }
    private static func savePresentation(_ view: NSView, named name: String,
                                          maximumPixelDimension: CGFloat? = nil) throws {
        view.layoutSubtreeIfNeeded()
        let scale = maximumPixelDimension.map { min(2, $0 / max(view.bounds.width, view.bounds.height)) } ?? 2
        guard let rendered = view.layer?.presentation() ?? view.layer,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                pixelsWide: max(1, Int((view.bounds.width * scale).rounded(.up))),
                pixelsHigh: max(1, Int((view.bounds.height * scale).rounded(.up))),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw NSError(domain: "RobotWindowTransitionTests", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Could not render actual presentation frame \(name)"])
        }
        bitmap.size = view.bounds.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.clear(CGRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
        context.cgContext.scaleBy(x: scale, y: scale)
        rendered.render(in: context.cgContext)
        NSGraphicsContext.restoreGraphicsState()
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/robot-animation-qa")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "RobotWindowTransitionTests", code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Could not encode actual presentation frame \(name)"])
        }
        let filename = maximumPixelDimension == nil ? "\(name)@2x.png" : "\(name).png"
        try png.write(to: directory.appendingPathComponent(filename))
    }
    private var result: Int32 = 0
    static func main() {
        let app = NSApplication.shared
        let delegate = RobotWindowTransitionTests()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        exit(delegate.result)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do { try await Self.runChecks() }
            catch { result = 1; fputs("FAIL: \(error)\n", stderr) }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }
    static func runChecks() async throws {
        guard let screen = NSScreen.screens.first else {
            throw NSError(domain: "RobotWindowTransitionTests", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "A display is required"])
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinRobotWindow-\(UUID().uuidString)")
        let suite = "DaBinRobotWindow.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = try CaptureStore(root: root)
        _ = try store.createNote(text: "Fictional animation review. No personal content or clipboard is used.", projectName: nil)
        let previews = PreviewService(store: store, defaults: defaults)
        let state = AppState(store: store, previews: previews, reminders: ReminderService(store: store, client: RobotWindowNotificationClient()))
        let controller = CornerController(state: state, input: InputService(store: store), placementDefaults: nil, robotReduceMotion: { false })
        defer {
            controller.shutdown(); previews.shutdown()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        var openCount = 0
        var closeCount = 0
        controller.onWillOpenBoard = { openCount += 1 }
        controller.onDidCloseBoard = { closeCount += 1 }
        controller.reveal(on: screen, corner: .topRight)
        controller.robot.onDaily?()
        try expect(controller.robotLifecycle.state == .preparingToExpand, "Double-click entry starts preparation")
        try expect(controller.appFrame.isTransitioning, "The real content wrapper animates")
        try expect(!controller.bin.isVisible && controller.board.isVisible, "Exactly one robot/app surface opens")
        try expect(controller.board.captureHostingView === controller.captureHostingView, "Paste and drop keep their hosting view")
        try expect(openCount == 1, "Opening suspends capture feedback first")
        await wait(0.12)
        if let stage = controller.board.contentView { try savePresentation(stage, named: "opening-anticipation") }
        await wait(0.20)
        try expect(controller.robotLifecycle.state == .expandingToApp, "Preparation advances into expansion")
        if let stage = controller.board.contentView { try savePresentation(stage, named: "opening-seam") }
        await wait(0.40)
        if let stage = controller.board.contentView { try savePresentation(stage, named: "opening-body") }
        await wait(0.70)
        try expect(controller.robotLifecycle.state == .fullScreen && !controller.appFrame.isTransitioning,
                   "Opening resolves to the existing full view")
        try expect(controller.board.contentView === controller.appFrame, "Temporary staging container is removed")
        try expect(screen.visibleFrame.contains(controller.board.frame), "Open frame stays on the interaction display")
        try expect(abs(controller.captureHostingView.frame.width - 380) < 1, "Existing 380-point content width is preserved")
        try expect(abs(controller.board.frame.height - controller.captureHostingView.frame.height - 50) < 1,
                   "Head and feet have reserved space outside content")
        try expect(controller.board.sharingType == .none && controller.bin.sharingType == .none,
                   "Native panels request capture exclusion")
        controller.pollPointer(at: NSPoint(x: screen.frame.maxX - 3, y: screen.frame.minY + 3))
        try expect(controller.board.isVisible && !controller.bin.isVisible, "Gaze does not reveal a second robot")
        try expect(!controller.appFrame.isHidden && controller.appFrame.isFrameVisible,
                   "The settled native frame is actually visible after staging cleanup")
        try savePresentation(controller.appFrame, named: "robot-full-view")
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/robot-animation-qa")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let bitmap = controller.appFrame.bitmapImageRepForCachingDisplay(in: controller.appFrame.bounds) {
            controller.appFrame.cacheDisplay(in: controller.appFrame.bounds, to: bitmap)
            if let png = bitmap.representation(using: .png, properties: [:]) {
                try png.write(to: directory.appendingPathComponent("robot-full-view.png"))
            }
        }
        controller.toggleExpandedWindow()
        controller.appFrame.layoutSubtreeIfNeeded()
        let expandedContentSize = controller.captureHostingView.frame.size
        try expect(controller.board.frame == screen.visibleFrame,
                   "The close fixture starts from the actual expanded safe-area app, not a compact approximation")
        try expect(expandedContentSize.width > 380
                   && abs(expandedContentSize.width - screen.visibleFrame.width + RobotAppFrameView.extraWidth) < 1,
                   "The expanded fixture mounts the full-width production capture content")
        try savePresentation(controller.appFrame, named: "closing-expanded-start", maximumPixelDimension: 1_600)
        state.onDismiss?()
        try expect(controller.robotLifecycle.state == .collapsingApp, "X starts the reverse transformation")
        let closingGeneration = controller.robotLifecycle.generation
        let closeStarted = ProcessInfo.processInfo.systemUptime
        var closingFrames: [[String: Any]] = []
        for (name, progress) in [("early", 0.10), ("mid", 0.34), ("compact", 0.69), ("late", 0.86)] {
            let remaining = closeStarted + RobotAppFrameView.closeDuration * progress
                - ProcessInfo.processInfo.systemUptime
            if remaining > 0 { await wait(remaining) }
            try expect(controller.board.isVisible && !controller.bin.isVisible
                       && controller.robotLifecycle.state == .collapsingApp && controller.appFrame.isTransitioning,
                       "The expanded close retains one live transforming surface at the \(name) stage")
            try expect(controller.captureHostingView.frame.size == expandedContentSize,
                       "The \(name) fold keeps the hosted content mounted at its final geometry")
            try expect(closeCount == 0, "The \(name) fold does not resume capture feedback before fully closing")
            if let stage = controller.board.contentView {
                let elapsed = ProcessInfo.processInfo.systemUptime - closeStarted
                try savePresentation(stage, named: "closing-expanded-\(name)", maximumPixelDimension: 1_600)
                closingFrames.append(["file": "closing-expanded-\(name).png", "elapsedSeconds": elapsed,
                    "plannedProgress": progress, "closeDuration": RobotAppFrameView.closeDuration,
                    "geometry": "actual expanded safe-area panel; GPU presentation layers; fictional archive"])
            }
        }
        try expect(closingFrames.count == 4, "The expanded close saves every actual staged presentation frame")
        try JSONSerialization.data(withJSONObject: closingFrames, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("closing-expanded-frames.json"), options: .atomic)
        controller.openDaily()
        try expect(controller.robotLifecycle.state == .preparingToExpand && controller.appFrame.isTransitioning
                   && controller.robotLifecycle.generation > closingGeneration,
                   "A late-close reopen reverses the visible presentation and invalidates the close generation")
        if let stage = controller.board.contentView {
            try savePresentation(stage, named: "closing-expanded-late-reopen", maximumPixelDimension: 1_600)
        }
        await wait(RobotAppFrameView.openDuration + 0.20)
        try expect(controller.board.isVisible && controller.robotLifecycle.state == .fullScreen
                   && controller.board.frame == screen.visibleFrame,
                   "A stale close cannot hide a reopened expanded app or lose its full safe-area geometry")
        try expect(closeCount == 0, "An interrupted close never resumes capture feedback")
        let closeKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: controller.board.windowNumber, context: nil,
            characters: "w", charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13)!
        try expect(controller.board.performKeyEquivalent(with: closeKey)
                   && controller.robotLifecycle.state == .collapsingApp,
                   "Command W uses the same reverse transformation as X")
        controller.board.performClose(nil)
        await wait(RobotAppFrameView.closeDuration + 0.15)
        try expect(!controller.board.isVisible && controller.robotLifecycle.state == .hidden, "Reverse transformation hides the app")
        try expect(closeCount == 1, "Pending feedback resumes once after fully closing")
        controller.openDaily()
        await wait(0.08)
        controller.dismiss()
        await wait(RobotAppFrameView.closeDuration + 0.15)
        try expect(!controller.board.isVisible && !controller.appFrame.isTransitioning, "Close cancels a pending opening")
        try expect(controller.robotLifecycle.state == .hidden, "Interrupted opening reaches a clean closed state")
        try expect(closeCount == 2, "Canceling an opening resumes feedback exactly once after its own close")
        controller.openDaily()
        await wait(0.08)
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        await wait(0.12)
        try expect(controller.robotLifecycle.state == .fullScreen && controller.board.isVisible,
                   "Display reconfiguration settles an opening to the visible endpoint")
        try expect(screen.visibleFrame.contains(controller.board.frame), "Reconfigured frame stays on screen")
        await wait(RobotAppFrameView.openDuration + 0.15)
        try expect(controller.robotLifecycle.state == .fullScreen, "Old display animation callbacks stay invalidated")
        controller.dismiss()
        await wait(RobotAppFrameView.closeDuration + 0.15)
        try expect(closeCount == 3, "The final normal close resumes feedback exactly once")
        controller.openDaily()
        await wait(0.06)
        controller.shutdown()
        try expect(!controller.board.isVisible && !controller.bin.isVisible, "Shutdown removes windows immediately")
        await wait(max(RobotAppFrameView.openDuration, RobotAppFrameView.closeDuration) + 0.15)
        try expect(controller.isShutDown && !controller.board.isVisible && !controller.appFrame.isTransitioning,
                   "No delayed work resurrects a terminated controller")
        try expect(closeCount == 3, "Shutdown invalidates delayed callbacks without replaying close feedback")
        print("PASS \(checks) robot window transition checks")
    }
}
