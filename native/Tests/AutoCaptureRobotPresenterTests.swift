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

        let presenter = AutoCaptureRobotPresenter(dismissDelay: 0.06,
                                                   primaryScreen: { builtIn },
                                                   reduceMotion: { true })
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
        try expect(ObjectIdentifier(presenter.panel) == panelIdentity && presenter.panel.isVisible,
                   "Presentation reuses the one panel instead of creating a window")
        try expect(presenter.present(additionalCaptureCount: 2)
                   && presenter.state.visibleCount == 3
                   && ObjectIdentifier(presenter.panel) == panelIdentity,
                   "A live burst reuses its panel and updates its count")
        try expect(!presenter.panel.isKeyWindow && !presenter.panel.isMainWindow,
                   "Ordering the passive panel never makes it key or main")

        try await Task.sleep(for: .milliseconds(300))
        try expect(!presenter.state.isVisible && !presenter.panel.isVisible,
                   "The latest burst deadline fades out and orders out the panel")
        presenter.shutdown()
        try expect(!presenter.present(additionalCaptureCount: 1),
                   "A shut-down presenter cannot recreate its passive UI")

        print("PASS: \(checks) automatic-capture robot presenter checks")
    }
}
