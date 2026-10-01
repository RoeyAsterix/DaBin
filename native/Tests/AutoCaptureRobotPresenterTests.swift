import AppKit
import Foundation

@main
@MainActor
private struct AutoCaptureRobotPresenterTests {
    private static var checks = 0

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard condition() else {
            throw NSError(domain: "DaBinAutoCaptureRobotPresenterTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private static func near(_ first: CGFloat, _ second: CGFloat) -> Bool {
        abs(first - second) < 0.01
    }

    /// Synthetic displays exercise placement policy independently of hardware.
    /// AppKit may apply the host screen's menu-bar constraint when ordering a
    /// real panel, so compare against that native result instead of assuming
    /// an injected synthetic screen also changes the computer's screens.
    private static func hasNativeFrame(_ panel: NSPanel, requested: CGRect) -> Bool {
        panel.frame == panel.constrainFrameRect(requested, to: panel.screen)
    }

    static func main() async throws {
        let external = AutoCaptureRobotScreen(
            displayID: 19,
            frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1055),
            safeAreaTop: 0,
            isBuiltIn: false
        )
        let builtIn = AutoCaptureRobotScreen(
            displayID: 7,
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950),
            safeAreaTop: 32,
            isBuiltIn: true
        )
        let islandRect = CGRect(x: 690, y: 950, width: 132, height: 32)
        let builtInWithIsland = AutoCaptureRobotScreen(
            displayID: 7,
            frame: builtIn.frame,
            visibleFrame: builtIn.visibleFrame,
            safeAreaTop: builtIn.safeAreaTop,
            isBuiltIn: true,
            cameraIslandRect: islandRect
        )

        try expect(AutoCaptureRobotGeometry.primaryScreen(in: [external, builtIn], mainDisplayID: 7) == builtIn,
                   "The hardware main display ID wins even when it is not first")
        try expect(AutoCaptureRobotGeometry.primaryScreen(in: [external, builtIn], mainDisplayID: 99) == nil,
                   "A missing hardware main display is not guessed from array order")

        let builtInFrame = AutoCaptureRobotGeometry.panelFrame(on: builtIn)
        try expect(near(builtInFrame.maxX, builtIn.visibleFrame.maxX - 8),
                   "A built-in display without a verified camera island uses top-right")
        try expect(near(builtInFrame.maxY, 942),
                   "The built-in presentation sits below both the safe top and edge inset")
        try expect(builtIn.visibleFrame.contains(builtInFrame),
                   "The built-in presentation remains inside the usable display")

        let islandFrame = AutoCaptureRobotGeometry.panelFrame(on: builtInWithIsland)
        try expect(near(islandFrame.midX, islandRect.midX)
                   && near(islandFrame.maxY, builtIn.frame.maxY),
                   "A camera stage reaches drawable pixels beside and below the real housing")
        try expect(builtInWithIsland.frame.contains(islandFrame),
                   "The camera-island presentation remains in the usable display")
        try expect(islandFrame == QuietOrbitLayout(cameraIsland: islandRect, displayFrame: builtIn.frame)?.panelFrame
                   && builtInFrame.size == AutoCaptureRobotGeometry.panelSize,
                   "A physical island receives a wider motion stage without enlarging fallback popups")
        let explicitIslandFrame = AutoCaptureRobotGeometry.panelFrame(
            on: builtInWithIsland, size: CGSize(width: 88, height: 96))
        try expect(explicitIslandFrame.size == CGSize(width: 88, height: 96)
                   && near(explicitIslandFrame.midX, islandRect.midX)
                   && near(explicitIslandFrame.maxY, islandRect.minY),
                   "An explicitly requested stage size remains authoritative and island-attached")

        let narrowIslandScreen = AutoCaptureRobotScreen(
            displayID: 8, frame: CGRect(x: -120, y: 20, width: 180, height: 120),
            visibleFrame: CGRect(x: -120, y: 20, width: 180, height: 88),
            safeAreaTop: 32, isBuiltIn: true,
            cameraIslandRect: CGRect(x: -64, y: 108, width: 68, height: 32))
        try expect(narrowIslandScreen.frame.contains(AutoCaptureRobotGeometry.panelFrame(on: narrowIslandScreen)),
                   "A narrow island display clips the entire motion stage to usable display bounds")
        let invalidIslandScreen = AutoCaptureRobotScreen(
            displayID: 7, frame: builtIn.frame, visibleFrame: builtIn.visibleFrame,
            safeAreaTop: builtIn.safeAreaTop, isBuiltIn: true,
            cameraIslandRect: CGRect(x: 2000, y: 1000, width: 132, height: 32))
        try expect(AutoCaptureRobotGeometry.cameraIsland(on: invalidIslandScreen) == nil
                   && AutoCaptureRobotGeometry.panelFrame(on: invalidIslandScreen) == builtInFrame,
                   "An island outside the display cannot create an attached stage")

        let externalFrame = AutoCaptureRobotGeometry.panelFrame(on: external)
        try expect(near(externalFrame.maxX, external.visibleFrame.maxX - 8),
                   "An external primary display uses the top-right inset")
        try expect(near(externalFrame.maxY, external.visibleFrame.maxY - 8),
                   "An external primary display stays below its menu bar")
        try expect(external.visibleFrame.contains(externalFrame),
                   "Negative-coordinate external displays are supported")

        let tiny = AutoCaptureRobotScreen(displayID: 2, frame: CGRect(x: 20, y: 30, width: 50, height: 40),
                                          visibleFrame: CGRect(x: 20, y: 30, width: 50, height: 40),
                                          safeAreaTop: 100, isBuiltIn: true)
        try expect(AutoCaptureRobotGeometry.panelFrame(on: tiny) == tiny.visibleFrame,
                   "An unusually small safe-area display clamps the panel fully inside its visible frame")

        var burst = AutoCaptureRobotBurstState()
        let first = burst.present(additionalCount: 1)!
        try expect(burst.isVisible && burst.visibleCount == 1,
                   "The first automatic capture starts a one-item burst")
        let second = burst.present(additionalCount: 3)!
        try expect(second != first && burst.visibleCount == 4,
                   "A later automatic action reuses and increments the visible burst")
        try expect(!burst.dismiss(ifCurrent: first) && burst.visibleCount == 4,
                   "A stale dismissal cannot hide a newer burst")
        try expect(burst.dismiss(ifCurrent: second) && !burst.isVisible,
                   "The current deadline dismisses its burst")
        _ = burst.present(additionalCount: 2)
        try expect(burst.visibleCount == 2, "A new burst restarts its count after dismissal")
        try expect(burst.present(additionalCount: 0) == nil && burst.visibleCount == 2,
                   "Invalid empty updates do not mutate the burst")
        let cancelledGeneration = burst.dismissNow()
        try expect(!burst.isVisible && burst.generation == cancelledGeneration,
                   "Immediate dismissal invalidates scheduled callbacks")

        var reduceMotion = true
        let presenter = AutoCaptureRobotPresenter(dismissDelay: 0.12,
                                                   primaryScreen: { builtInWithIsland },
                                                   reduceMotion: { reduceMotion },
                                                   reactionDeck: AutoCaptureRobotReactionDeck(seed: 77))
        var presentationChanges: [Bool] = []
        presenter.onPresentationChanged = { presentationChanges.append($0) }
        let panelIdentity = ObjectIdentifier(presenter.panel)
        try expect(presenter.panel.styleMask.contains(.borderless)
                   && presenter.panel.styleMask.contains(.nonactivatingPanel),
                   "The automatic confirmation uses a borderless nonactivating panel")
        try expect(!presenter.panel.canBecomeKey && !presenter.panel.canBecomeMain
                   && presenter.panel.ignoresMouseEvents,
                   "The automatic confirmation cannot take focus and ignores clicks")
        try expect(presenter.panel.sharingType == .none,
                   "The automatic confirmation is excluded from screen capture")
        try expect(presenter.present(additionalCaptureCount: 1),
                   "A valid automatic capture presents successfully")
        guard let firstPerformance = presenter.currentPerformance else {
            throw NSError(domain: "DaBinAutoCaptureRobotPresenterTests", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "A successful presentation did not create a performance"])
        }
        try expect(firstPerformance.reduceMotion
                   && firstPerformance.phases.map(\.kind) == [.reducedPeek, .successCheck, .fade],
                   "The live accessibility preference selects the reduced peek, check and fade")
        try expect(presenter.performanceStartCount == 1 && presenter.badgeText == nil,
                   "One success starts one performance and does not show a redundant ×1 badge")
        try expect(ObjectIdentifier(presenter.panel) == panelIdentity && presenter.panel.isVisible,
                   "Presentation reuses the one panel instead of creating a window")
        try expect(hasNativeFrame(presenter.panel, requested: islandFrame)
                   && presenter.panel.contentView?.subviews.first?.frame.size == QuietOrbitLayout(cameraIsland: islandRect, displayFrame: builtIn.frame)?.robotFrame(for: .bottom).size
                   && presenter.panel.contentView?.layer?.masksToBounds == true,
                   "Island artwork gets the full clipped stage after native screen constraints, without a fake housing")
        try expect(presenter.present(additionalCaptureCount: 2)
                   && presenter.state.visibleCount == 3
                   && presenter.performanceStartCount == 1
                   && presenter.currentPerformance?.reaction == firstPerformance.reaction
                   && presenter.badgeText == "×3"
                   && ObjectIdentifier(presenter.panel) == panelIdentity,
                   "A rapid burst updates ×3 without restarting or changing the reaction")
        let nativeBadge = presenter.panel.contentView?.subviews.compactMap { $0 as? NSTextField }.first
        let cameraInPanel = QuietOrbitLayout(cameraIsland: islandRect, displayFrame: builtIn.frame)!.cameraFrameInPanel
        try expect(nativeBadge?.stringValue == "✓ ×3" && nativeBadge?.isHidden == false
                   && nativeBadge?.font?.pointSize == 11,
                   "A native-size success cue keeps the exact burst count readable")
        try expect(nativeBadge.map { !cameraInPanel.intersects($0.frame) } == true,
                   "The camera cannot obscure the Reduce Motion success cue or burst count")
        try expect(!presenter.panel.isKeyWindow && !presenter.panel.isMainWindow,
                   "Ordering the passive panel never makes it key or main")
        try expect(presenter.panel.ignoresMouseEvents && presenter.panel.sharingType == .none,
                   "The visible burst remains click-through and excluded from capture")

        // Completion includes a second scheduled fade task. Under concurrent
        // compiler/IO load its main-actor turn can arrive after a fixed sleep.
        // Assert the endpoint with a bounded deadline; motion timing itself is
        // covered by the deterministic choreography tests.
        let completionDeadline = Date().addingTimeInterval(2)
        while (presenter.state.isVisible || presenter.panel.isVisible), Date() < completionDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try expect(!presenter.state.isVisible && !presenter.panel.isVisible,
                   "The one performance completes, fades out and orders out the panel")
        try expect(presentationChanges == [true, false],
                   "Presentation coordination reports one visible edge and one hidden edge")

        reduceMotion = false
        try expect(presenter.present(additionalCaptureCount: 1),
                   "A later burst can start after cleanup")
        try expect(presenter.currentPerformance?.reduceMotion == false
                   && presenter.performanceStartCount == 2,
                   "The accessibility preference is read live for each new burst")
        presenter.dismiss()
        try await Task.sleep(for: .milliseconds(180))
        try expect(!presenter.panel.isVisible && !presenter.state.isVisible,
                   "Explicit dismissal cancels and cleans the active performance")
        presenter.shutdown()
        try expect(!presenter.present(additionalCaptureCount: 1),
                   "A shut-down presenter cannot recreate its passive UI")

        let externalPresenter = AutoCaptureRobotPresenter(
            dismissDelay: 0.04,
            primaryScreen: { external },
            reduceMotion: { false },
            reactionDeck: AutoCaptureRobotReactionDeck(seed: 91)
        )
        try expect(externalPresenter.present(additionalCaptureCount: 1)
                   && externalPresenter.currentPerformance?.entrance == .right,
                   "An external hardware primary display uses the right-edge entrance")
        try expect(hasNativeFrame(externalPresenter.panel, requested: externalFrame),
                   "The external popup uses the tested top-right safe-area frame")
        externalPresenter.shutdown()

        let exactPresenter = AutoCaptureRobotPresenter(
            dismissDelay: 0.20,
            primaryScreen: { builtInWithIsland },
            reduceMotion: { false },
            reactionDeck: AutoCaptureRobotReactionDeck(seed: 101)
        )
        try expect(exactPresenter.present(additionalCaptureCount: 127)
                   && exactPresenter.state.visibleCount == 127
                   && exactPresenter.badgeText == "×127"
                   && exactPresenter.currentPerformance?.reaction == .stackedCapture,
                   "Large successful batches show their exact count and prefer the stack reaction")
        exactPresenter.shutdown()

        let suspendedPresenter = AutoCaptureRobotPresenter(
            dismissDelay: 0.20,
            primaryScreen: { builtInWithIsland },
            reduceMotion: { false },
            reactionDeck: AutoCaptureRobotReactionDeck(seed: 102)
        )
        var suspensionChanges: [Bool] = []
        suspendedPresenter.onPresentationChanged = { suspensionChanges.append($0) }
        try expect(suspendedPresenter.present(additionalCaptureCount: 2),
                   "A pre-board capture begins normally")
        suspendedPresenter.suspendForBoard()
        try expect(suspendedPresenter.isSuspendedForBoard
                   && suspendedPresenter.pendingCaptureCount == 2
                   && !suspendedPresenter.state.isVisible
                   && !suspendedPresenter.panel.isVisible,
                   "Opening the board removes the passive robot and preserves its unconsumed count")
        try expect(suspendedPresenter.present(additionalCaptureCount: 5)
                   && suspendedPresenter.pendingCaptureCount == 7
                   && !suspendedPresenter.panel.isVisible,
                   "Captures received while the board owns the robot aggregate without presentation")
        try expect(suspendedPresenter.resumeAfterBoard()
                   && !suspendedPresenter.isSuspendedForBoard
                   && suspendedPresenter.pendingCaptureCount == 0
                   && suspendedPresenter.state.visibleCount == 7
                   && suspendedPresenter.badgeText == "×7",
                   "Closing the board resumes one performance with every pending capture")
        try expect(suspensionChanges == [true, false, true],
                   "Suspension and resumption expose exact presentation ownership changes")
        suspendedPresenter.shutdown()

        let latePresenter = AutoCaptureRobotPresenter(
            dismissDelay: 0.16,
            primaryScreen: { external },
            reduceMotion: { false },
            reactionDeck: AutoCaptureRobotReactionDeck(seed: 103)
        )
        var lateChanges: [Bool] = []
        latePresenter.onPresentationChanged = { lateChanges.append($0) }
        try expect(latePresenter.present(additionalCaptureCount: 1),
                   "The first item starts a late-arrival test performance")
        let firstLateReaction = latePresenter.currentPerformance?.reaction
        try await Task.sleep(for: .milliseconds(120))
        try expect(latePresenter.present(additionalCaptureCount: 4)
                   && latePresenter.state.visibleCount == 1
                   && latePresenter.pendingCaptureCount == 4
                   && latePresenter.currentPerformance?.reaction == firstLateReaction,
                   "An arrival after the eating window queues instead of overlapping the active robot")
        try await Task.sleep(for: .milliseconds(80))
        try expect(latePresenter.performanceStartCount == 2
                   && latePresenter.state.visibleCount == 4
                   && latePresenter.pendingCaptureCount == 0
                   && latePresenter.badgeText == "×4"
                   && lateChanges == [true],
                   "The queued exact count receives a second non-overlapping performance with no visibility gap")
        try await Task.sleep(for: .milliseconds(300))
        try expect(!latePresenter.panel.isVisible && lateChanges == [true, false],
                   "The chained performances report one continuous presentation interval")
        latePresenter.shutdown()

        var changingScreen: AutoCaptureRobotScreen? = builtInWithIsland
        let changingPresenter = AutoCaptureRobotPresenter(
            dismissDelay: 0.30,
            primaryScreen: { changingScreen },
            reduceMotion: { false },
            reactionDeck: AutoCaptureRobotReactionDeck(seed: 104)
        )
        try expect(changingPresenter.present(additionalCaptureCount: 3),
                   "A display-recovery capture starts on the current primary display")
        changingScreen = nil
        changingPresenter.displayConfigurationChanged()
        try expect(!changingPresenter.panel.isVisible
                   && changingPresenter.pendingCaptureCount == 3,
                   "Losing all displays orders out the panel and retains unconsumed captures")
        try expect(!changingPresenter.present(additionalCaptureCount: 2)
                   && changingPresenter.pendingCaptureCount == 5,
                   "New saved captures are retained while all displays are disconnected")
        changingScreen = external
        changingPresenter.displayConfigurationChanged()
        try expect(changingPresenter.panel.isVisible
                   && hasNativeFrame(changingPresenter.panel, requested: externalFrame)
                   && changingPresenter.state.visibleCount == 5
                   && changingPresenter.currentPerformance?.entrance == .right,
                   "A replacement display repositions and resumes without a stranded window")
        changingPresenter.shutdown()

        var relocationScreen: AutoCaptureRobotScreen? = builtInWithIsland
        var relocationDate = Date(timeIntervalSinceReferenceDate: 100)
        let relocationPresenter = AutoCaptureRobotPresenter(
            dismissDelay: 60,
            primaryScreen: { relocationScreen },
            reduceMotion: { true },
            reactionDeck: AutoCaptureRobotReactionDeck(seed: 105),
            currentDate: { relocationDate }
        )
        let relocationPanelIdentity = ObjectIdentifier(relocationPresenter.panel)
        try expect(relocationPresenter.present(additionalCaptureCount: 3),
                   "A geometry-change scenario starts an attached capture cue")
        let initialRelocationPerformance = relocationPresenter.currentPerformance
        relocationPresenter.displayConfigurationChanged()
        try expect(relocationPresenter.performanceStartCount == 1
                   && relocationPresenter.currentPerformance == initialRelocationPerformance,
                   "An unchanged display notification leaves the active plan and burst untouched")

        // Advance into the final quarter of the authored success cue, after
        // count updates close but before consumption. Derive this boundary
        // from the plan so motion refinements cannot change the scenario.
        let successPhase = initialRelocationPerformance!.phases.first { $0.kind == .successCheck }!
        relocationDate.addTimeInterval(successPhase.endTime - successPhase.duration * 0.125)
        try expect(relocationPresenter.present(additionalCaptureCount: 4)
                   && relocationPresenter.pendingCaptureCount == 4,
                   "Late captures queue while an unconsumed cue is still in flight")
        relocationScreen = external
        relocationPresenter.displayConfigurationChanged()
        try expect(relocationPresenter.state.visibleCount == 7
                   && relocationPresenter.pendingCaptureCount == 0
                   && relocationPresenter.performanceStartCount == 2
                   && relocationPresenter.currentPerformance?.entrance == .right
                   && hasNativeFrame(relocationPresenter.panel, requested: externalFrame)
                   && ObjectIdentifier(relocationPresenter.panel) == relocationPanelIdentity,
                   "A valid island-to-external change replans unfinished and pending counts in the same passive panel")
        try expect(relocationPresenter.panel.contentView?.subviews.first?.frame
                   == CGRect(x: 8, y: 5, width: 88, height: 109),
                   "Leaving the island restores compact inset artwork rather than a leftover wide stage")

        relocationDate.addTimeInterval(1)
        try expect(relocationPresenter.present(additionalCaptureCount: 2)
                   && relocationPresenter.pendingCaptureCount == 2,
                   "A consumed cue accepts later saves only into its pending queue")
        relocationScreen = builtInWithIsland
        relocationPresenter.displayConfigurationChanged()
        try expect(relocationPresenter.state.visibleCount == 2
                   && relocationPresenter.pendingCaptureCount == 0
                   && relocationPresenter.performanceStartCount == 3
                   && relocationPresenter.currentPerformance?.entrance == .top
                   && hasNativeFrame(relocationPresenter.panel, requested: islandFrame),
                   "Returning to an island presents only pending saves and never replays a consumed cue")

        relocationDate.addTimeInterval(1)
        relocationScreen = external
        relocationPresenter.displayConfigurationChanged()
        try expect(!relocationPresenter.panel.isVisible
                   && !relocationPresenter.state.isVisible
                   && relocationPresenter.currentPerformance == nil
                   && relocationPresenter.pendingCaptureCount == 0
                   && relocationPresenter.performanceStartCount == 3,
                   "Moving a consumed performance with no pending saves hides it without inventing another success")
        relocationPresenter.shutdown()

        let coordinated = AutoCaptureRobotPresenter(dismissDelay: 0.3, primaryScreen: { external }, reduceMotion: { false })
        _ = coordinated.present(additionalCaptureCount: 2)
        coordinated.suspendForInteraction()
        coordinated.suspendForBoard()
        try expect(coordinated.pendingCaptureCount == 2 && !coordinated.panel.isVisible,
                   "Two suspension reasons preserve the active count exactly once")
        _ = coordinated.present(additionalCaptureCount: 3)
        try expect(!coordinated.resumeAfterInteraction() && coordinated.pendingCaptureCount == 5,
                   "Finishing a manual drop cannot resume feedback while the board owns the robot")
        try expect(coordinated.resumeAfterBoard() && coordinated.state.visibleCount == 5,
                   "Releasing the final owner resumes exactly one aggregate")
        coordinated.shutdown()

        let unavailablePresenter = AutoCaptureRobotPresenter(
            primaryScreen: { nil },
            reduceMotion: { false },
            reactionDeck: AutoCaptureRobotReactionDeck(seed: 92)
        )
        try expect(!unavailablePresenter.present(additionalCaptureCount: 1)
                   && !unavailablePresenter.panel.isVisible && unavailablePresenter.pendingCaptureCount == 1,
                   "No popup is guessed when the hardware primary display is unavailable")
        unavailablePresenter.shutdown()

        print("PASS: \(checks) automatic-capture robot presenter checks")
    }
}
