import AppKit
import Foundation

@main
struct RobotAppFrameTests {
    @MainActor private static var checks = 0

    @MainActor private static func expect(_ condition: @autoclosure () -> Bool,
                                          _ message: String) throws {
        checks += 1
        guard condition() else {
            throw NSError(domain: "DaBinRobotAppFrameTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    @MainActor private static func approximately(_ lhs: CGFloat, _ rhs: CGFloat,
                                                  tolerance: CGFloat = 0.001) -> Bool {
        abs(lhs - rhs) <= tolerance
    }

    @MainActor private static func spinMainRunLoop(for duration: TimeInterval) {
        let end = Date().addingTimeInterval(duration)
        while Date() < end {
            _ = RunLoop.main.run(mode: .default, before: min(end, Date().addingTimeInterval(0.01)))
        }
    }

    @MainActor static func main() throws {
        _ = NSApplication.shared

        let insets = RobotAppFrameView.contentInsets
        try expect(insets.top == 32 && insets.left == 10 && insets.bottom == 18 && insets.right == 10,
                   "Robot chrome reserves the agreed head, side and leg clearances")
        try expect(RobotAppFrameView.totalExtraWidth == 20 && RobotAppFrameView.totalExtraHeight == 50,
                   "Published extra dimensions match the asymmetric content insets")
        try expect(RobotAppFrameView.outerSize(forContentSize: CGSize(width: 380, height: 500))
            == CGSize(width: 400, height: 550),
                   "A 380-point Daily surface remains intact inside the robot frame")

        let nominal = RobotAppFrameView.contentRect(in: CGRect(x: 0, y: 0, width: 400, height: 550))
        try expect(nominal == CGRect(x: 10, y: 18, width: 380, height: 500),
                   "Content geometry uses AppKit's lower-left origin and leaves legs below it")
        let offset = RobotAppFrameView.contentRect(in: CGRect(x: -25, y: 40, width: 400, height: 550))
        try expect(offset == CGRect(x: -15, y: 58, width: 380, height: 500),
                   "Content geometry preserves a nonzero bounds origin")
        let tiny = RobotAppFrameView.contentRect(in: CGRect(x: 3, y: -7, width: 7, height: 12))
        try expect(tiny.width == 0 && tiny.height == 0 && tiny.origin.x.isFinite && tiny.origin.y.isFinite,
                   "Very small frames clamp content dimensions without negative or nonfinite geometry")

        let stage = NSView(frame: CGRect(x: 0, y: 0, width: 900, height: 760))
        let content = NSView(frame: .zero)
        let control = NSButton(title: "Daily control", target: nil, action: nil)
        control.frame = CGRect(x: 22, y: 26, width: 118, height: 32)
        content.addSubview(control)
        let frame = RobotAppFrameView(contentView: content)
        frame.frame = CGRect(x: 137, y: 91, width: 400, height: 550)
        stage.addSubview(frame)
        frame.setVisible(true)
        frame.layoutSubtreeIfNeeded()

        try expect(content.superview != nil && content.isDescendant(of: frame),
                   "The real Daily view stays mounted as an interactive descendant")
        try expect(content.superview?.frame == nominal && content.frame == CGRect(x: 0, y: 0, width: 380, height: 500),
                   "Layout reserves robot chrome without shrinking the 380-point Daily content")
        let hostColor = content.superview?.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))
        try expect(hostColor?.alphaComponent == 0,
                   "The wrapper stays transparent so BoardView's theme and opacity remain authoritative")

        let controlPoint = control.convert(CGPoint(x: control.bounds.midX, y: control.bounds.midY), to: stage)
        try expect(frame.hitTest(controlPoint) === control,
                   "An offset frame hosted in a larger transition stage forwards hits to real controls")
        let headPoint = CGPoint(x: frame.frame.midX, y: frame.frame.maxY - 4)
        try expect(frame.hitTest(headPoint) == nil,
                   "Robot head and decorative shell remain click-through")

        frame.frame.size = CGSize(width: 470, height: 610)
        frame.layoutSubtreeIfNeeded()
        let resized = RobotAppFrameView.contentRect(in: frame.bounds)
        try expect(content.superview?.frame == resized && content.frame.size == resized.size,
                   "Resizing recomputes the inset once without cumulative drift")

        let display = CGRect(x: 100, y: 50, width: 1_200, height: 800)
        let eye = CGPoint(x: display.midX, y: display.midY)
        try expect(RobotAppFrameGaze.offset(pointer: eye, eyeCenter: eye, displayFrame: display) == .zero,
                   "A centered pointer leaves the pupils centered")
        let right = RobotAppFrameGaze.offset(pointer: CGPoint(x: display.maxX, y: eye.y),
                                             eyeCenter: eye, displayFrame: display)
        let left = RobotAppFrameGaze.offset(pointer: CGPoint(x: display.minX, y: eye.y),
                                            eyeCenter: eye, displayFrame: display)
        try expect(right.x > 0 && left.x < 0 && approximately(abs(right.x), abs(left.x)),
                   "Gaze follows the pointer symmetrically across the display")
        let top = RobotAppFrameGaze.offset(pointer: CGPoint(x: eye.x, y: display.maxY),
                                           eyeCenter: eye, displayFrame: display)
        try expect(top.y > 0 && abs(top.y) <= 1.45,
                   "The unflipped AppKit eye layers look upward for a higher screen point")
        let clamped = RobotAppFrameGaze.offset(pointer: CGPoint(x: display.maxX + 10_000, y: eye.y),
                                               eyeCenter: eye, displayFrame: display)
        try expect(clamped == right,
                   "Pointers beyond a display edge clamp to the same bounded gaze target")
        try expect(RobotAppFrameGaze.offset(pointer: nil, eyeCenter: eye, displayFrame: display) == .zero &&
                   RobotAppFrameGaze.offset(pointer: eye, eyeCenter: eye, displayFrame: .zero) == .zero,
                   "Absent pointers and invalid displays settle safely at center")

        frame.setVisible(false)
        try expect(frame.isHidden && !frame.isFrameVisible && content.isHidden,
                   "Hiding the frame also hides the live content and stops its interactive surface")
        try expect(frame.hitTest(controlPoint) == nil,
                   "A hidden frame cannot intercept a stale content hit")

        try expect(RobotAppFrameView.openDuration == 1.15 &&
                   RobotAppFrameView.closeDuration == 0.42 &&
                   RobotAppFrameView.reducedDuration == 0.14,
                   "Continuous open, quick close and reduced fade durations stay explicit")

        var opened = 0
        frame.animateOpen(from: CGRect(x: 600, y: 740, width: 72, height: 88),
                          island: true, reduceMotion: true) { opened += 1 }
        let openingFade = frame.layer?.animation(forKey: "robotFrame.reduced")
        try expect(frame.isTransitioning && openingFade != nil &&
                   approximately(openingFade?.duration ?? 0, RobotAppFrameView.reducedDuration),
                   "Reduce Motion opens with one short static-frame fade")
        // A visibility notification during the fade must not cancel its completion generation.
        frame.setVisible(true)
        try expect(frame.isTransitioning, "Positive visibility echoes leave an active transition intact")
        spinMainRunLoop(for: 0.20)
        try expect(opened == 1 && frame.isFrameVisible && !frame.isTransitioning && !frame.isHidden,
                   "Reduced opening reaches one clean visible endpoint and completes once")
        try expect(!frame.usesSolidTransitionTorso,
                   "A stable open frame restores perimeter rails for transparent BoardView content")
        frame.updatePointer(screenPoint: CGPoint(x: display.maxX, y: display.maxY),
                            displayFrame: display)
        try expect(!frame.hasActiveEyeMotion,
                   "Reduce Motion keeps the presented robot frame static without gaze easing or blink")

        var closed = 0
        frame.animateClose(to: CGRect(x: 600, y: 740, width: 72, height: 88),
                           island: true, reduceMotion: true) { closed += 1 }
        let closingFade = frame.layer?.animation(forKey: "robotFrame.reduced")
        try expect(closingFade != nil &&
                   approximately(closingFade?.duration ?? 0, RobotAppFrameView.reducedDuration),
                   "Reduce Motion closes with the same short fade and no travel")
        spinMainRunLoop(for: 0.20)
        try expect(closed == 1 && !frame.isFrameVisible && !frame.isTransitioning && frame.isHidden,
                   "Reduced closing hides the renderer and its content at one clean endpoint")
        try expect(!frame.usesSolidTransitionTorso,
                   "A stable hidden frame does not retain the temporary solid torso masks")

        var cancelledCompletion = 0
        frame.animateOpen(from: CGRect(x: 40, y: 700, width: 72, height: 88),
                          island: false, reduceMotion: false) { cancelledCompletion += 1 }
        try expect(frame.usesSolidTransitionTorso,
                   "Animated transitions use a filled robot body instead of a hollow outline")
        frame.cancelTransition(open: true)
        spinMainRunLoop(for: 0.03)
        try expect(cancelledCompletion == 0 && frame.isFrameVisible && !frame.isTransitioning,
                   "Cancelling a generation resolves its endpoint without firing a stale completion")
        try expect(!frame.usesSolidTransitionTorso,
                   "Cancellation restores stable perimeter masks and preserves center transparency")

        print("PASS: \(checks) robot application frame geometry, gaze and lifecycle checks")
    }
}
