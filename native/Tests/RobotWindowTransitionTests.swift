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
    private static func companionEncounterChecks() throws {
        var encounter = RobotCompanionEncounter()
        let pointer = CGPoint(x: 0.6, y: -0.4)
        var sample = encounter.update(proximity: nil, pointer: pointer, at: 0)
        try expect(sample.phase == .hidden && !sample.isVisible && sample.progress == 0,
                   "An absent pointer encounter leaves no visible companion")
        sample = encounter.update(proximity: 0.1, pointer: pointer, at: 0.1)
        try expect(sample.phase == .peeking && sample.isVisible && sample.progress > 0 && sample.progress < 0.4,
                   "The outer approach exposes an eyes-first peek before a climb")
        sample = encounter.update(proximity: 1, pointer: pointer, at: 0.2)
        try expect(sample.phase == .climbing && sample.progress < 0.9,
                   "A closer pointer traverses the climb instead of jumping to a full reveal")
        sample = encounter.update(proximity: 1, pointer: pointer, at: 0.4)
        try expect(sample.phase == .reaching && sample.progress == 1 && sample.pointer == pointer,
                   "A sustained close approach reaches the pointer with its current gaze")
        let departure = 0.4
        sample = encounter.update(proximity: nil, pointer: pointer, at: departure + 0.64)
        try expect(sample.phase == .watching && sample.progress == 1,
                   "Leaving the approach zone earns a watchful pause without immediate retreat")
        sample = encounter.update(proximity: nil, pointer: pointer, at: departure + 0.74)
        try expect(sample.phase == .retreating && sample.progress > 0 && sample.progress < 1,
                   "Retreat starts only after the 650-millisecond departure grace")
        let retreatProgress = sample.progress
        sample = encounter.update(proximity: 1, pointer: CGPoint(x: -0.8, y: 0.2), at: departure + 0.84)
        try expect(sample.isVisible && sample.phase != .retreating && sample.progress > retreatProgress,
                   "Returning during retreat reverses it from the existing visible progress")
        sample = encounter.update(proximity: 1, pointer: pointer, at: departure + 1.04)
        let lastNear = departure + 1.04
        for offset in [0.64, 0.74, 0.94, 1.14, 1.34] {
            sample = encounter.update(proximity: nil, pointer: pointer, at: lastNear + offset)
            try expect(sample.progress.isFinite && (0...1).contains(sample.progress),
                       "Every watch and retreat sample stays within the normalized visual range")
        }
        try expect(sample.phase == .hidden && !sample.isVisible && sample.progress == 0,
                   "Completed retreat removes the companion without a frozen last pose")
        try expect(RobotCompanionEncounter.retreatDelay == 0.65 && RobotCompanionEncounter.retreatDuration == 0.42,
                   "The encounter retains its explicit pause and finite retreat timing")

        var sparse = RobotCompanionEncounter()
        _ = sparse.update(proximity: 1, pointer: pointer, at: 10)
        _ = sparse.update(proximity: 1, pointer: pointer, at: 10.2)
        sample = sparse.update(proximity: 1, pointer: pointer, at: 10.4)
        try expect(sample.progress == 1, "The sparse-sampling fixture starts fully revealed")
        var boundary = sparse
        var directBoundary = sparse
        sample = sparse.update(proximity: nil, pointer: pointer, at: 13.4)
        try expect(sample.phase == .hidden && sample.progress == 0 && !sample.isVisible,
                   "One away sample after three seconds completes the real-time retreat")
        sample = sparse.update(proximity: 0.1, pointer: pointer, at: 13.5)
        try expect(sample.phase == .peeking && sample.progress > 0 && sample.progress < 0.4,
                   "A completed sparse retreat permits a fresh encounter at another target")
        sample = boundary.update(proximity: nil, pointer: pointer, at: 11.04)
        try expect(sample.phase == .watching && sample.progress == 1,
                   "The last sample before the grace boundary consumes no retreat time")
        sample = boundary.update(proximity: nil, pointer: pointer, at: 11.14)
        let boundaryProgress = CGFloat(1 - 0.09 / RobotCompanionEncounter.retreatDuration)
        try expect(sample.phase == .retreating && abs(sample.progress - boundaryProgress) < 0.000_001,
                   "Crossing the grace boundary subtracts only the 90 milliseconds after it")
        let directSample = directBoundary.update(proximity: nil, pointer: pointer, at: 11.14)
        try expect(abs(directSample.progress - sample.progress) < 0.000_001,
                   "Skipping watch samples does not change the retreat pose at the same elapsed time")
        sample = boundary.update(proximity: nil, pointer: pointer, at: 11.24)
        try expect(abs(sample.progress - CGFloat(1 - 0.19 / RobotCompanionEncounter.retreatDuration)) < 0.000_001,
                   "Later retreat samples consume each elapsed interval exactly once")

        var expressions = RobotCompanionEncounter()
        sample = expressions.update(proximity: 1, pointer: pointer, at: 0, expressionOnly: true)
        try expect(sample.isVisible && sample.progress == 1 && sample.pointer == pointer,
                   "Quiet and Reduce Motion retain a static visible face and pointer expression")
        sample = expressions.update(proximity: nil, pointer: pointer, at: 0.64, expressionOnly: true)
        try expect(sample.phase == .watching && sample.progress == 1,
                   "Expression-only presentation retains the same departure grace")
        sample = expressions.update(proximity: nil, pointer: pointer, at: 0.8, expressionOnly: true)
        try expect(!sample.isVisible && sample.progress == 0,
                   "Expression-only retreat hides without a body-motion sequence")
        sample = expressions.update(proximity: .nan, pointer: CGPoint(x: CGFloat.nan, y: CGFloat.infinity), at: .nan)
        try expect(sample.progress.isFinite && sample.pointer == .zero,
                   "Malformed proximity, time and gaze samples never reach native layers as NaN")

        let housing = CGRect(x: -850, y: 950, width: 140, height: 32)
        try expect(RobotCompanionProximity.island(CGPoint(x: housing.midX, y: housing.minY - 8), housing: housing) == 1,
                   "A close approach below a negative-origin camera is fully engaged")
        try expect(RobotCompanionProximity.island(CGPoint(x: housing.midX, y: housing.minY - 64), housing: housing) == nil,
                   "The camera approach has a bounded outer edge")
        let anchor = CGPoint(x: -1512, y: -200)
        try expect(RobotCompanionProximity.corner(CGPoint(x: anchor.x + 12, y: anchor.y + 12), anchor: anchor) == 1,
                   "Corner proximity uses display coordinates without assuming positive origins")
        try expect(RobotCompanionProximity.corner(CGPoint(x: anchor.x + 96, y: anchor.y), anchor: anchor) == nil,
                   "An ordinary distant pointer cannot summon a corner companion")
    }

    private static func immediateCompanionClicks(screen: NSScreen, state: AppState, store: CaptureStore) async throws {
        for retreating in [false, true] {
            let controller = CornerController(state: state, input: InputService(store: store),
                placementDefaults: nil, robotReduceMotion: { false })
            defer { controller.shutdown() }
            var opens = 0
            controller.onWillOpenBoard = { opens += 1 }
            controller.reveal(on: screen, corner: .topRight)
            // Fictional hardware makes the moving-island fixture independent of
            // whether this machine's selected display has a physical notch.
            let housing = CGRect(x: screen.frame.midX - 72, y: screen.frame.maxY - 34, width: 144, height: 34)
            let layout = QuietOrbitLayout(cameraIsland: housing, displayFrame: screen.frame)!
            controller.bin.setFrame(layout.panelFrame, display: true)
            controller.robot.presentCompanion(from: .top, orbit: layout, perch: .bottom)
            let target = layout.interactionRegions(for: .bottom, local: true).first!
            let local = CGPoint(x: target.midX, y: target.midY)
            let stableTarget = controller.robot.interactionBounds
            var encounter = RobotCompanionEncounter()
            var snapshot = encounter.update(proximity: 0.1, pointer: .zero, at: 0)
            if retreating {
                _ = encounter.update(proximity: 1, pointer: .zero, at: 0.2)
                _ = encounter.update(proximity: 1, pointer: .zero, at: 0.4)
                snapshot = encounter.update(proximity: nil, pointer: .zero, at: 1.14)
                try expect(snapshot.phase == .retreating && snapshot.progress > 0 && snapshot.progress < 1,
                           "The click fixture is inside the live companion's finite retreat")
            } else {
                try expect(snapshot.phase == .peeking, "The first-click fixture begins during the eyes-first reveal")
            }
            controller.robot.updateCompanion(snapshot)
            try expect(controller.robot.interactionBounds == stableTarget
                       && controller.robot.containsInteraction(local),
                       "The fixed companion target remains usable while \(retreating ? "retreating" : "revealing")")
            let parentPoint = controller.robot.convert(local, to: controller.robot.superview)
            let receiver = controller.robot.hitTest(parentPoint)
            try expect(receiver === controller.robot, "Native hit testing reaches the moving companion")
            func click(_ count: Int) -> NSEvent {
                NSEvent.mouseEvent(with: .leftMouseDown,
                    location: controller.robot.convert(local, to: nil), modifierFlags: [], timestamp: Double(count),
                    windowNumber: controller.bin.windowNumber, context: nil, eventNumber: count,
                    clickCount: count, pressure: 1)!
            }
            receiver?.mouseDown(with: click(1))
            try expect(opens == 1 && controller.board.isVisible && !controller.bin.isVisible
                       && controller.robotLifecycle.state == .fullScreen && !controller.appFrame.isTransitioning,
                       "One native click opens usable content immediately during companion motion")
            controller.robot.mouseDown(with: click(2))
            try expect(opens == 1, "The second click in a double-click sequence cannot reopen content")
            await wait(0.55)
            try expect(opens == 1 && controller.board.isVisible && !controller.bin.isVisible
                       && controller.robotLifecycle.state == .fullScreen,
                       "An interrupted companion completion cannot hide or reopen the user's content")
        }
    }
    private static func frameInScreen(_ view: NSView, window: NSWindow) -> NSRect {
        window.convertToScreen(view.convert(view.bounds, to: nil))
    }
    private static func checkTransitionStage(_ controller: CornerController,
                                             source: NSRect, destination: NSRect) throws {
        guard let stage = controller.board.contentView else {
            throw NSError(domain: "RobotWindowTransitionTests", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "A robot transition needs its native stage"])
        }
        let padding = RobotAppFrameView.transitionStageOutset
        try expect(stage !== controller.appFrame && controller.appFrame.superview === stage,
                   "A separate native stage hosts the existing app frame during movement")
        try expect(controller.board.frame.contains(source.insetBy(dx: -padding, dy: -padding))
                   && controller.board.frame.contains(destination.insetBy(dx: -padding, dy: -padding)),
                   "The real window reserves stroke and overshoot room around both transition endpoints")
        try expect(frameInScreen(controller.appFrame, window: controller.board) == destination,
                   "Stage padding does not move the hosted application's intended screen coordinates")
        try expect(controller.appFrame.frame.size == destination.size
                   && controller.captureHostingView.frame.size == RobotAppFrameView.contentRect(in: controller.appFrame.bounds).size,
                   "Staging preserves the final app and content geometry instead of resizing per frame")
    }
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
        try companionEncounterChecks()
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
        let source = controller.bin.convertToScreen(controller.robot.convert(controller.robot.transitionBodyBounds, to: nil))
        controller.showBoard()
        let openingDestination = frameInScreen(controller.appFrame, window: controller.board)
        let openingContentSize = controller.captureHostingView.frame.size
        try checkTransitionStage(controller, source: source, destination: openingDestination)
        try expect(controller.robotLifecycle.state == .preparingToExpand, "An explicit animated opening starts preparation")
        try expect(controller.appFrame.isTransitioning, "The real content wrapper animates")
        try expect(!controller.bin.isVisible && controller.board.isVisible, "Exactly one robot/app surface opens")
        try expect(controller.board.captureHostingView === controller.captureHostingView, "Paste and drop keep their hosting view")
        try expect(openCount == 1, "Opening suspends capture feedback first")
        await wait(0.12)
        if let stage = controller.board.contentView { try savePresentation(stage, named: "opening-anticipation") }
        await wait(RobotAppFrameView.openingExpansionDelay + 0.05)
        try expect(controller.robotLifecycle.state == .expandingToApp, "Preparation advances into expansion")
        if let stage = controller.board.contentView { try savePresentation(stage, named: "opening-seam") }
        await wait(0.40)
        if let stage = controller.board.contentView { try savePresentation(stage, named: "opening-body") }
        await wait(0.70)
        try expect(controller.robotLifecycle.state == .fullScreen && !controller.appFrame.isTransitioning,
                   "Opening resolves to the existing full view")
        try expect(controller.board.contentView === controller.appFrame, "Temporary staging container is removed")
        try expect(controller.board.frame == openingDestination
                   && controller.captureHostingView.frame.size == openingContentSize,
                   "Opening removes only the stage padding without an endpoint jump or content resize")
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
        let closingDestination = controller.board.frame
        state.onDismiss?()
        try checkTransitionStage(controller, source: source, destination: closingDestination)
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
        let closingStage = controller.board.contentView
        let closingStageFrame = controller.board.frame
        let closingAppFrame = controller.appFrame.frame
        controller.openDaily()
        try expect(controller.robotLifecycle.state == .preparingToExpand && controller.appFrame.isTransitioning
                   && controller.robotLifecycle.generation > closingGeneration,
                   "A late-close reopen reverses the visible presentation and invalidates the close generation")
        try expect(controller.board.contentView === closingStage && controller.board.frame == closingStageFrame
                   && controller.appFrame.frame == closingAppFrame,
                   "Reopening reuses the same source-to-destination stage without moving either endpoint")
        try checkTransitionStage(controller, source: source, destination: closingDestination)
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
        try await immediateCompanionClicks(screen: screen, state: state, store: store)
        print("PASS \(checks) robot window transition checks")
    }
}
