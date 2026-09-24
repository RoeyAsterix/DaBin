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
        try expect(near(builtInFrame.midX, builtIn.frame.midX),
                   "The built-in presentation is centered under the camera area")
        try expect(near(builtInFrame.maxY, 942),
                   "The built-in presentation sits below both the safe top and edge inset")
        try expect(builtIn.visibleFrame.contains(builtInFrame),
                   "The built-in presentation remains inside the usable display")

        let islandFrame = AutoCaptureRobotGeometry.panelFrame(on: builtInWithIsland)
        try expect(near(islandFrame.midX, islandRect.midX)
                   && near(islandFrame.maxY, islandRect.minY),
                   "A real camera island centers the robot and meets its lower edge")
        try expect(builtInWithIsland.visibleFrame.contains(islandFrame),
                   "The camera-island presentation remains in the usable display")

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
        try expect(presenter.present(additionalCaptureCount: 2)
                   && presenter.state.visibleCount == 3
                   && presenter.performanceStartCount == 1
                   && presenter.currentPerformance?.reaction == firstPerformance.reaction
                   && presenter.badgeText == "×3"
                   && ObjectIdentifier(presenter.panel) == panelIdentity,
                   "A rapid burst updates ×3 without restarting or changing the reaction")
        try expect(!presenter.panel.isKeyWindow && !presenter.panel.isMainWindow,
                   "Ordering the passive panel never makes it key or main")
        try expect(presenter.panel.ignoresMouseEvents && presenter.panel.sharingType == .none,
                   "The visible burst remains click-through and excluded from capture")

        try await Task.sleep(for: .milliseconds(300))
        try expect(!presenter.state.isVisible && !presenter.panel.isVisible,
                   "The one performance completes, fades out and orders out the panel")

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
        try expect(externalPresenter.panel.frame == externalFrame,
                   "The external popup uses the tested top-right safe-area frame")
        externalPresenter.shutdown()

        let unavailablePresenter = AutoCaptureRobotPresenter(
            primaryScreen: { nil },
            reduceMotion: { false },
            reactionDeck: AutoCaptureRobotReactionDeck(seed: 92)
        )
        try expect(!unavailablePresenter.present(additionalCaptureCount: 1)
                   && !unavailablePresenter.panel.isVisible,
                   "No popup is guessed when the hardware primary display is unavailable")
        unavailablePresenter.shutdown()

        print("PASS: \(checks) automatic-capture robot presenter checks")
    }
}
