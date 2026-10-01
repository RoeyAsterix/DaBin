import Foundation

@main
private struct RobotLifecycleTests {
    private static var checks = 0

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard condition() else {
            throw NSError(domain: "DaBinRobotLifecycleTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    static func main() throws {
        var capture = RobotLifecycle()
        try expect(capture.state == .hidden && capture.generation == 0
                   && capture.pendingCaptureCount == 0,
                   "The value lifecycle starts hidden with no capture")
        try expect(capture.send(.captureSaved(count: 0)).isEmpty && capture.state == .hidden,
                   "An empty capture never starts a success sequence")

        let peekEffects = capture.send(.captureSaved(count: 2))
        let peekGeneration = capture.generation
        try expect(capture.state == .peeking && capture.pendingCaptureCount == 2,
                   "A successful capture starts the peek with its exact count")
        try expect(peekEffects == [.updateCaptureCount(2),
                                   .animate(.peeking, generation: peekGeneration)],
                   "The first capture supplies count and guarded peek effects")

        _ = capture.send(.captureSaved(count: 3))
        try expect(capture.pendingCaptureCount == 5
                   && capture.state == .peeking,
                   "An active capture sequence aggregates without restarting")
        try expect(capture.send(.animationCompleted(generation: peekGeneration))
                   == [.animate(.climbingOut, generation: capture.generation)]
                   && capture.state == .climbingOut,
                   "A count-only update leaves the active animation generation valid")

        let expectedCaptureStates: [RobotLifecycle.State] = [
            .waitingForCapture, .eatingCapture,
            .captureReaction, .returningToIsland, .hidden
        ]
        for expected in expectedCaptureStates {
            let effects = capture.send(.animationCompleted(generation: capture.generation))
            try expect(capture.state == expected, "Capture completion advances to \(expected.rawValue)")
            if expected == .hidden {
                try expect(effects == [.hide] && capture.pendingCaptureCount == 0,
                           "The completed return clears the burst at the hidden endpoint")
            } else {
                try expect(effects == [.animate(expected, generation: capture.generation)],
                           "Every capture phase carries its new generation")
            }
        }

        var lateArrival = RobotLifecycle(state: .returningToIsland,
                                         pendingCaptureCount: 4)
        let lateEffects = lateArrival.send(.captureSaved(count: 7))
        try expect(lateArrival.state == .eatingCapture && lateArrival.pendingCaptureCount == 11,
                   "A capture during retreat returns to eating with the exact aggregate")
        try expect(lateEffects == [.updateCaptureCount(11), .cancelAnimation,
                                   .animate(.eatingCapture, generation: lateArrival.generation)],
                   "A late capture cancels retreat before beginning another eating phase")

        var opening = RobotLifecycle()
        _ = opening.send(.captureSaved(count: 1))
        let abandonedPeek = opening.generation
        let openEffects = opening.send(.openRequested)
        try expect(opening.state == .preparingToExpand
                   && openEffects == [.cancelAnimation,
                                      .animate(.preparingToExpand, generation: opening.generation)],
                   "Opening the app has priority over the passive capture")
        try expect(opening.send(.animationCompleted(generation: abandonedPeek)).isEmpty,
                   "The preempted peek cannot mutate the opening app")
        _ = opening.send(.animationCompleted(generation: opening.generation))
        try expect(opening.state == .expandingToApp,
                   "Preparation advances into app expansion")
        let showEffects = opening.send(.animationCompleted(generation: opening.generation))
        try expect(opening.state == .fullScreen && showEffects == [.showFullScreen],
                   "Expansion ends at the full-screen endpoint")
        let closeEffects = opening.send(.closeRequested)
        try expect(opening.state == .collapsingApp
                   && closeEffects == [.animate(.collapsingApp, generation: opening.generation)],
                   "Closing a full app begins one collapse")
        let hideEffects = opening.send(.animationCompleted(generation: opening.generation))
        try expect(opening.state == .hidden && hideEffects == [.hide],
                   "Collapse returns to a definite hidden endpoint")

        var reversal = RobotLifecycle()
        _ = reversal.send(.openRequested)
        let cancelledOpen = reversal.generation
        _ = reversal.send(.closeRequested)
        try expect(reversal.state == .collapsingApp,
                   "Close can reverse an opening transition")
        _ = reversal.send(.openRequested)
        try expect(reversal.state == .preparingToExpand,
                   "A newer open reverses collapse and keeps open priority")
        try expect(reversal.send(.animationCompleted(generation: cancelledOpen)).isEmpty,
                   "A callback from the first open is ignored after both reversals")

        let openGeneration = reversal.generation
        try expect(reversal.send(.advance(to: .fullScreen, generation: openGeneration))
                   == [.showFullScreen] && reversal.state == .fullScreen,
                   "A legal explicit advance can settle a partially animated open")
        try expect(reversal.send(.advance(to: .eatingCapture,
                                         generation: reversal.generation)).isEmpty,
                   "An illegal explicit jump is rejected")
        let interruptEffects = reversal.send(.interrupt(toward: .hidden))
        try expect(reversal.state == .hidden
                   && interruptEffects == [.cancelAnimation, .hide],
                   "A user interrupt settles hidden and invalidates animation callbacks")

        var displayOpen = RobotLifecycle()
        _ = displayOpen.send(.openRequested)
        let oldDisplayGeneration = displayOpen.generation
        try expect(displayOpen.send(.displayChanged(hasDisplay: false)) == [.cancelAnimation, .hide]
                   && displayOpen.state == .hidden && !displayOpen.hasDisplay,
                   "Display loss immediately hides a partially opened app")
        try expect(displayOpen.send(.animationCompleted(generation: oldDisplayGeneration)).isEmpty,
                   "Display loss invalidates an in-flight app animation")
        try expect(displayOpen.send(.displayChanged(hasDisplay: true))
                   == [.cancelAnimation, .reposition, .showFullScreen]
                   && displayOpen.state == .fullScreen && displayOpen.hasDisplay,
                   "A replacement display repositions and restores the intended open endpoint")

        var displayCapture = RobotLifecycle()
        _ = displayCapture.send(.captureSaved(count: 8))
        _ = displayCapture.send(.displayChanged(hasDisplay: false))
        try expect(displayCapture.state == .hidden && displayCapture.pendingCaptureCount == 8,
                   "Display loss retains an unconsumed capture aggregate")
        let recoveredCapture = displayCapture.send(.displayChanged(hasDisplay: true))
        try expect(displayCapture.state == .peeking
                   && recoveredCapture == [.reposition, .updateCaptureCount(8), .cancelAnimation,
                                           .animate(.peeking, generation: displayCapture.generation)],
                   "A replacement display restarts the retained capture from a known phase")

        var unavailable = RobotLifecycle(hasDisplay: false)
        try expect(unavailable.send(.openRequested).isEmpty && unavailable.state == .hidden,
                   "An open request waits when there is no display")
        try expect(unavailable.send(.displayChanged(hasDisplay: true)).contains(.showFullScreen)
                   && unavailable.state == .fullScreen,
                   "The deferred open recovers directly to its visible endpoint")

        var bounded = RobotLifecycle()
        _ = bounded.send(.captureSaved(count: Int.max))
        _ = bounded.send(.captureSaved(count: 1))
        try expect(bounded.pendingCaptureCount == Int.max,
                   "Constant-memory count aggregation cannot overflow")

        print("PASS: \(checks) robot lifecycle checks")
    }
}
