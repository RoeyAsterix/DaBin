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

        frame.onResize = { _ in }
        let edgePoint = CGPoint(x: frame.frame.minX + 2, y: frame.frame.midY)
        try expect(frame.hitTest(edgePoint) === frame,
                   "The six-point outer edge is a resize handle without covering content")
        try expect(frame.hitTest(controlPoint) === control,
                   "Enabling resize handles leaves actual content controls clickable")

        // The card corners are inset from the transparent native window. They
        // must be discoverable resize targets without requiring a six-pixel
        // hunt at the invisible outer edge.
        let contentCorners: [(CGPoint, BoardResizeGeometry.Edge)] = [
            (CGPoint(x: resized.minX, y: resized.maxY), [.left, .top]),
            (CGPoint(x: resized.maxX, y: resized.maxY), [.right, .top]),
            (CGPoint(x: resized.minX, y: resized.minY), [.left, .bottom]),
            (CGPoint(x: resized.maxX, y: resized.minY), [.right, .bottom])
        ]
        for (point, expected) in contentCorners {
            try expect(BoardResizeGeometry.interactionEdge(at: point, in: frame.bounds) == expected,
                       "Each visible card corner selects both of its resize axes: \(expected.rawValue)")
            try expect(frame.hitTest(frame.convert(point, to: stage)) === frame,
                       "Each visible corner routes native hits to the resize handler: \(expected.rawValue)")
            let inward = CGPoint(x: point.x + (expected.contains(.left) ? 8 : -8),
                                 y: point.y + (expected.contains(.bottom) ? 8 : -8))
            try expect(BoardResizeGeometry.interactionEdge(at: inward, in: frame.bounds) == expected,
                       "Corner targets extend into the rounded card instead of existing only in transparent chrome")
        }
        let cornerRegions = BoardResizeGeometry.cornerRegions(in: frame.bounds)
        try expect(cornerRegions.count == 4 && cornerRegions.allSatisfy { frame.bounds.contains($0.rect) },
                   "All four enlarged resize regions remain inside the native frame")
        let offsetBounds = CGRect(x: -20, y: 35, width: 400, height: 550)
        let offsetContent = RobotAppFrameView.contentRect(in: offsetBounds)
        try expect(BoardResizeGeometry.interactionEdge(
            at: CGPoint(x: offsetContent.minX, y: offsetContent.maxY), in: offsetBounds) == [.left, .top],
                   "Visible corner detection preserves nonzero bounds origins")
        try expect(BoardResizeGeometry.interactionEdge(at: CGPoint(x: -1, y: frame.bounds.midY), in: frame.bounds).isEmpty,
                   "Enlarged corner targets never accept points outside the native frame")

        frame.onDragStarted = { }
        let dragBand = BoardResizeGeometry.dragRegion(in: frame.bounds)
        let chromePoint = CGPoint(x: dragBand.midX, y: dragBand.midY)
        try expect(frame.bounds.contains(dragBand) && dragBand.minY >= resized.maxY,
                   "The draggable chrome band reserves its space above application content")
        try expect(frame.hitTest(frame.convert(chromePoint, to: stage)) === frame,
                   "Configured robot chrome provides a full-width native drag surface")
        let headerControl = NSButton(title: "Header control", target: nil, action: nil)
        headerControl.frame = CGRect(x: content.bounds.maxX - 66, y: content.bounds.maxY - 40,
                                     width: 48, height: 28)
        content.addSubview(headerControl)
        let headerControlPoint = headerControl.convert(
            CGPoint(x: headerControl.bounds.midX, y: headerControl.bounds.midY), to: stage)
        try expect(frame.hitTest(headerControlPoint) === headerControl && frame.hitTest(controlPoint) === control,
                   "Top chrome dragging and larger corner targets preserve header and content controls")
        frame.onDragStarted = nil
        frame.onResize = nil
        try expect(frame.hitTest(frame.convert(chromePoint, to: stage)) == nil,
                   "Decorative chrome is click-through when no drag or resize handler is configured")
        frame.celebrateTaskCompletion(reduceMotion: true)
        try expect(frame.taskCelebrationCount == 1 && !frame.hasActiveEyeMotion,
                   "A saved completion acknowledges happiness without eye motion under Reduce Motion")

        let resizingDisplay = CGRect(x: -1440, y: 24, width: 1440, height: 876)
        let original = CGRect(x: -1300, y: 300, width: 500, height: 550)
        let wider = BoardResizeGeometry.resized(original, edge: .right,
            delta: CGPoint(x: 250, y: 0), visible: resizingDisplay)
        try expect(wider.width == 750 && wider.minX == original.minX && wider.maxY == original.maxY,
                   "Right-edge resize preserves the user's left and top anchors on a negative-coordinate display")
        let smaller = BoardResizeGeometry.resized(original, edge: [.left, .bottom],
            delta: CGPoint(x: 900, y: 900), visible: resizingDisplay)
        try expect(smaller.size == BoardResizeGeometry.minimumSize && smaller.maxX == original.maxX && smaller.maxY == original.maxY,
                   "Corner dragging stops at the usable minimum and keeps opposite edges anchored")
        let larger = BoardResizeGeometry.resized(original, edge: [.right, .top],
            delta: CGPoint(x: 9_000, y: 9_000), visible: resizingDisplay)
        try expect(resizingDisplay.contains(larger) && larger.maxY == resizingDisplay.maxY,
                   "The menu bar and screen safe area remain clear when stretching beyond a display")
        let tinyDisplay = CGRect(x: 0, y: 0, width: 300, height: 250)
        try expect(BoardResizeGeometry.fitted(original, visible: tinyDisplay) == tinyDisplay,
                   "Disconnecting to a display smaller than the minimum safely fits its actual area")
        try expect(BoardResizeGeometry.edge(at: CGPoint(x: 200, y: 200), in: original) == [],
                   "Off-window coordinates cannot start a resize")

        let spaciousDisplay = CGRect(x: -1600, y: -1000, width: 3000, height: 2400)
        for (_, corner) in contentCorners {
            let delta = CGPoint(x: corner.contains(.left) ? -60 : 60,
                                y: corner.contains(.bottom) ? -45 : 45)
            let grown = BoardResizeGeometry.resized(original, edge: corner, delta: delta, visible: spaciousDisplay)
            try expect(grown.width == original.width + 60 && grown.height == original.height + 45,
                       "Each corner changes width and height together: \(corner.rawValue)")
            try expect((corner.contains(.left) ? grown.maxX == original.maxX : grown.minX == original.minX)
                       && (corner.contains(.bottom) ? grown.maxY == original.maxY : grown.minY == original.minY),
                       "Each corner preserves its opposite corner on either coordinate axis: \(corner.rawValue)")
            let shrunk = BoardResizeGeometry.resized(original, edge: corner,
                delta: CGPoint(x: -delta.x * 100, y: -delta.y * 100), visible: spaciousDisplay)
            try expect(shrunk.size == BoardResizeGeometry.minimumSize,
                       "Every corner stops shrinking at the usable content minimum: \(corner.rawValue)")
            try expect((corner.contains(.left) ? shrunk.maxX == original.maxX : shrunk.minX == original.minX)
                       && (corner.contains(.bottom) ? shrunk.maxY == original.maxY : shrunk.minY == original.minY),
                       "Hitting minimum size never moves a corner's fixed opposite anchor: \(corner.rawValue)")
        }
        try expect(BoardResizeGeometry.resized(original, edge: [.left, .top],
            delta: CGPoint(x: CGFloat.infinity, y: CGFloat.nan), visible: resizingDisplay) == original,
                   "An interrupted gesture with nonfinite pointer data retains a valid original frame")

        let leftDisplay = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        let rightDisplay = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let straddling = CGRect(x: -900, y: 240, width: 1000, height: 550)
        try expect(BoardResizeGeometry.destinationDisplay(for: straddling,
            pointer: CGPoint(x: 30, y: 700), displays: [leftDisplay, rightDisplay]) == 1,
                   "The released pointer chooses the new display while most of a wide window remains on the old one")
        try expect(BoardResizeGeometry.destinationDisplay(for: straddling,
            pointer: CGPoint(x: -20, y: 700), displays: [leftDisplay, rightDisplay]) == 0,
                   "Dragging back chooses a display with negative desktop coordinates")
        try expect(BoardResizeGeometry.destinationDisplay(for: straddling,
            pointer: nil, displays: [leftDisplay, rightDisplay]) == 0,
                   "A release without a pointer uses the display with the largest real window overlap")
        let upperDisplay = CGRect(x: 120, y: 1200, width: 1600, height: 900)
        try expect(BoardResizeGeometry.destinationDisplay(for: CGRect(x: 100, y: 750, width: 700, height: 550),
            pointer: CGPoint(x: 400, y: 1220), displays: [rightDisplay, upperDisplay]) == 1,
                   "Pointer destination selection works with vertically stacked displays and a desktop gap")
        try expect(BoardResizeGeometry.destinationDisplay(for: CGRect(x: 100, y: 750, width: 700, height: 550),
            pointer: CGPoint(x: 400, y: 1130), displays: [rightDisplay, upperDisplay]) == 0,
                   "A release in the gap falls back to overlap rather than a disconnected or arbitrary screen")
        try expect(BoardResizeGeometry.destinationDisplay(for: straddling,
            pointer: CGPoint(x: -20, y: 700), displays: [rightDisplay]) == 0,
                   "After disconnection the remaining overlapping display remains a valid destination")
        try expect(BoardResizeGeometry.destinationDisplay(for: original, pointer: nil, displays: []) == nil
                   && BoardResizeGeometry.destinationDisplay(for: original, pointer: nil, displays: [rightDisplay]) == nil,
                   "No available or overlapping display leaves recovery to the controller's explicit fallback")

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
        frame.celebrateTaskCompletion(reduceMotion: false)
        try expect(frame.taskCelebrationCount == 1,
                   "Completing a task never reveals or animates a hidden window")
        try expect(frame.isHidden && !frame.isFrameVisible && content.isHidden,
                   "Hiding the frame also hides the live content and stops its interactive surface")
        try expect(frame.hitTest(controlPoint) == nil,
                   "A hidden frame cannot intercept a stale content hit")

        try expect(RobotAppFrameView.openDuration == 1.15 &&
                   RobotAppFrameView.closeDuration == 0.78 &&
                   RobotAppFrameView.reducedDuration == 0.14,
                   "Continuous open, deliberate fold-and-tuck close and reduced fade durations stay explicit")

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

        let gazePoint = CGPoint(x: display.maxX, y: display.maxY)
        let initialGazeCount = frame.gazeAnimationStartCount
        frame.updatePointer(screenPoint: gazePoint, displayFrame: display)
        try expect(frame.gazeAnimationStartCount == initialGazeCount + 2,
                   "A new pointer target eases both pupils")
        let movingGazeCount = frame.gazeAnimationStartCount
        for _ in 0..<20 { frame.updatePointer(screenPoint: gazePoint, displayFrame: display) }
        try expect(frame.gazeAnimationStartCount == movingGazeCount,
                   "Repeated stationary pointer polls leave the current gaze animation running without restarting it")
        frame.updatePointer(screenPoint: CGPoint(x: display.minX, y: display.maxY), displayFrame: display)
        try expect(frame.gazeAnimationStartCount == movingGazeCount + 2,
                   "Moving the pointer still retargets both pupils")
        frame.updatePointer(screenPoint: nil, displayFrame: display)
        let centeredGazeCount = frame.gazeAnimationStartCount
        try expect(centeredGazeCount == movingGazeCount + 4,
                   "Leaving the display eases the gaze back to center")
        for _ in 0..<20 { frame.updatePointer(screenPoint: nil, displayFrame: display) }
        try expect(frame.gazeAnimationStartCount == centeredGazeCount,
                   "An already-centered absent pointer produces no new eye animations")

        print("PASS: \(checks) robot application frame geometry, gaze and lifecycle checks")
    }
}
