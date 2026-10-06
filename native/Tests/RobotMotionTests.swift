import AppKit
import Foundation
import QuartzCore

@main
struct RobotMotionTests {
    @MainActor private static var checks = 0

    @MainActor private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard condition() else {
            throw NSError(domain: "DaBinRobotMotionTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    /// Offscreen synthetic stages exercise the production renderer and mask.
    /// They never read the desktop, clipboard, capture archive or installed app.
    @MainActor private static func renderCompanionFixtures() throws {
        guard let path = ProcessInfo.processInfo.environment["DABIN_COMPANION_QA_OUTPUT"] else { return }
        let output = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.finishLaunching()
        let display = CGRect(x: 0, y: 0, width: 320, height: 220)
        let housing = CGRect(x: 88, y: 186, width: 144, height: 34)
        let orbit = QuietOrbitLayout(cameraIsland: housing, displayFrame: display)!
        var files: [String] = []
        let placements: [(String, QuietOrbitPerch?, RobotEntrance)] = [
            ("island-bottom", .bottom, .top), ("island-right", .right, .left),
            ("island-left", .left, .left), ("screen-left", nil, .left), ("screen-right", nil, .right)
        ]
        func removeAnimations(_ target: CALayer?) {
            guard let target else { return }
            target.removeAllAnimations()
            for child in target.sublayers ?? [] { removeAnimations(child) }
        }
        func raster(_ view: NSView) throws -> NSBitmapImageRep {
            view.layoutSubtreeIfNeeded()
            removeAnimations(view.layer)
            CATransaction.flush()
            view.displayIfNeeded()
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                pixelsWide: Int(view.bounds.width * 2), pixelsHigh: Int(view.bounds.height * 2),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
                throw NSError(domain: "DaBinRobotMotionTests", code: 2)
            }
            bitmap.size = view.bounds.size
            view.cacheDisplay(in: view.bounds, to: bitmap)
            return bitmap
        }
        for theme in ["light", "dark"] {
            for (placement, perch, entrance) in placements {
                let size = perch == nil ? CGSize(width: 160, height: 120) : orbit.panelFrame.size
                let stage = NSView(frame: CGRect(origin: .zero, size: size))
                stage.wantsLayer = true
                stage.layer?.backgroundColor = (theme == "light"
                    ? NSColor(calibratedWhite: 0.96, alpha: 1)
                    : NSColor(calibratedWhite: 0.09, alpha: 1)).cgColor
                let hardware = CALayer()
                hardware.backgroundColor = NSColor.black.cgColor
                hardware.cornerRadius = 4
                if perch != nil { hardware.frame = orbit.cameraFrameInPanel }
                else { hardware.frame = CGRect(x: entrance == .left ? 0 : size.width - 8,
                                               y: 0, width: 8, height: size.height) }
                stage.layer?.addSublayer(hardware)
                let robot = RobotView(frame: perch == nil
                    ? CGRect(x: entrance == .left ? 0 : size.width - 72, y: 16, width: 72, height: 88)
                    : stage.bounds, reduceMotion: { false })
                stage.addSubview(robot)
                let host = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: size.width, height: size.height),
                                    styleMask: [.borderless], backing: .buffered, defer: false)
                host.isReleasedWhenClosed = false
                host.contentView = stage
                host.appearance = NSAppearance(named: theme == "light" ? .aqua : .darkAqua)
                host.orderFront(nil)
                if let perch { robot.presentCompanion(from: entrance, orbit: orbit, perch: perch) }
                else { robot.presentCompanion(from: entrance) }
                let fixedTarget = robot.interactionBounds
                var firstRaster: Data?
                for (label, progress, pointer, expressionOnly) in [
                    ("peek", CGFloat(0.18), CGPoint(x: 0.7, y: -0.2), false),
                    ("climb", CGFloat(0.48), CGPoint(x: 0.7, y: -0.2), false),
                    ("reach", CGFloat(1), CGPoint(x: 0.7, y: -0.2), false),
                    ("retreat", CGFloat(0.30), CGPoint(x: -0.9, y: 0.5), false),
                    ("quiet", CGFloat(1), CGPoint(x: 0.7, y: -0.2), true)
                ] {
                    let snapshot = RobotCompanionEncounter.Snapshot(phase: label == "retreat" ? .retreating : .reaching,
                        progress: progress, pointer: pointer)
                    robot.updateCompanion(snapshot)
                    guard let character = robot.subviews.compactMap({ $0 as? RobotCharacterView }).first,
                          let pose = character.currentCompanionPose else {
                        throw NSError(domain: "DaBinRobotMotionTests", code: 3)
                    }
                    if expressionOnly {
                        character.applyCompanionPose(revealProgress: progress, pointer: pointer, entrance: entrance,
                            expressionOnly: true, duration: 0,
                            gripPoint: pose.grippingHandIndex == 0 ? pose.leftHand : pose.rightHand)
                    }
                    try expect(robot.interactionBounds == fixedTarget,
                               "\(placement) \(label) keeps the production click target steady")
                    let bitmap = try raster(stage)
                    guard let png = bitmap.representation(using: .png, properties: [:]) else {
                        throw NSError(domain: "DaBinRobotMotionTests", code: 4)
                    }
                    if label == "peek" { firstRaster = png }
                    if label == "reach" {
                        try expect(png != firstRaster && png.count > 400,
                                   "\(placement) full-body acting produces a distinct native raster after the eyes-only peek")
                    }
                    let name = "\(theme)-\(placement)-\(label)@2x.png"
                    try png.write(to: output.appendingPathComponent(name), options: .atomic)
                    files.append(name)
                }
                robot.stopFeedback()
                host.orderOut(nil)
                host.contentView = nil
                host.close()
            }
        }
        try JSONSerialization.data(withJSONObject: ["files": files, "pixelScale": 2,
            "source": "Production RobotView and RobotCharacterView in isolated synthetic stages",
            "privacy": "No desktop pixels, clipboard or saved captures accessed"], options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("companion-renders.json"), options: .atomic)
    }

    @MainActor static func main() throws {
        var state = RobotMotionState()
        try expect(state.mood == .hidden && !state.isVisible, "A new robot starts hidden")

        state.send(.reveal(.top))
        try expect(state.mood == .idle && state.isVisible && state.entrance == .top,
                   "Top reveal enters the idle camera-island pose")
        state.send(.hover(true, pointer: CGPoint(x: 4, y: -3)))
        try expect(state.mood == .curious(pointer: CGPoint(x: 1, y: -1)),
                   "Pointer gaze clamps to the normalized face range")
        state.send(.acceptedDrag(true))
        try expect(state.mood == .hungry && state.isAcceptingDrag,
                   "An accepted drag takes priority over hover")
        state.send(.saving(true))
        try expect(state.mood == .digesting && state.isSaving && !state.isAcceptingDrag,
                   "Saving takes priority and clears drag anticipation")
        state.send(.result(.success))
        try expect(state.mood == .delighted && !state.isSaving,
                   "A successful capture becomes a delighted result")
        state.send(.hover(false))
        try expect(state.mood == .delighted, "Result feedback remains higher priority than hover")
        state.send(.feedbackExpired)
        try expect(state.mood == .idle, "Expired feedback settles to idle")

        state.send(.result(.partialSuccess))
        try expect(state.mood == .partialSuccess, "Partial import has its own friendly shrug")
        state.send(.acceptedDrag(true))
        try expect(state.mood == .hungry, "A new drag cancels stale result feedback")
        state.send(.acceptedDrag(false))
        state.send(.result(.failure))
        try expect(state.mood == .puzzled, "A failed import uses the puzzled state")
        state.send(.saving(true))
        try expect(state.mood == .digesting, "A new save cancels stale failure feedback")
        state.send(.hide)
        try expect(state.mood == .hidden && !state.isVisible && !state.isHovered
                   && !state.isAcceptingDrag && !state.isSaving && state.result == nil,
                   "Hide clears every transient interaction state")

        for entrance in RobotEntrance.allCases {
            let reveal = RobotMotionDescriptor.make(for: .reveal(entrance), reduceMotion: false)
            try expect(reveal.isAnimated && reveal.duration == 0.30 && reveal.usesKeyframes,
                       "\(entrance.rawValue) reveal uses the short spring motion")
            try expect(reveal.initialBody.translation == entrance.hiddenTranslation,
                       "\(entrance.rawValue) reveal starts behind its matching edge")
            let reduced = RobotMotionDescriptor.make(for: .reveal(entrance), reduceMotion: true)
            try expect(!reduced.isAnimated && reduced.duration == 0 && reduced.initialBody == .identity,
                       "Reduce Motion removes \(entrance.rawValue) travel and spring")
        }

        let curious = RobotMotionDescriptor.make(for: .mood(.curious(pointer: CGPoint(x: 0.8, y: -0.5))),
                                                  reduceMotion: false)
        try expect(curious.pupilOffset.x > 0 && curious.pupilOffset.y < 0
                   && curious.rightArm.rotationDegrees > 0,
                   "Curious pose follows the pointer and gives one greeting wave")
        let hungry = RobotMotionDescriptor.make(for: .mood(.hungry), reduceMotion: false)
        try expect(hungry.lid.translation.y < 0 && hungry.leftArm.rotationDegrees < 0
                   && hungry.rightArm.rotationDegrees > 0,
                   "Hungry pose opens the lid and raises both arms")
        let digesting = RobotMotionDescriptor.make(for: .mood(.digesting), reduceMotion: false)
        try expect(digesting.usesKeyframes && digesting.intakeProgress == 1 && digesting.duration == 0.66,
                   "Digesting uses the card and two-chew sequence")
        let delighted = RobotMotionDescriptor.make(for: .mood(.delighted), reduceMotion: false)
        try expect(delighted.usesKeyframes && delighted.body.translation.y < 0
                   && delighted.shadowScale < 1,
                   "Success lifts the robot into a short happy hop")
        let reducedHungry = RobotMotionDescriptor.make(for: .mood(.hungry), reduceMotion: true)
        try expect(!reducedHungry.isAnimated && reducedHungry.body == .identity
                   && reducedHungry.leftArm == .identity && reducedHungry.rightArm == .identity,
                   "Reduce Motion retains an instant expression without body or arm movement")

        for entrance in RobotEntrance.allCases {
            let concealed = RobotCompanionPose.make(revealProgress: 0, pointer: .zero,
                                                    entrance: entrance, expressionOnly: false)
            let eyes = RobotCompanionPose.make(revealProgress: 0.18, pointer: CGPoint(x: 0.6, y: -0.3),
                                               entrance: entrance, expressionOnly: false)
            let head = RobotCompanionPose.make(revealProgress: 0.40, pointer: .zero,
                                               entrance: entrance, expressionOnly: false)
            let weight = RobotCompanionPose.make(revealProgress: 0.48, pointer: .zero,
                                                 entrance: entrance, expressionOnly: false)
            let settled = RobotCompanionPose.make(revealProgress: 1, pointer: .zero,
                                                  entrance: entrance, expressionOnly: false)
            try expect(concealed.headOpacity == 0 && concealed.torsoOpacity == 0 && concealed.peekEyeOpacity == 0,
                       "\(entrance) encounter starts completely concealed")
            try expect(eyes.peekEyeOpacity > 0.9 && eyes.headOpacity == 0 && eyes.torsoOpacity == 0,
                       "\(entrance) eyes peek before any head or torso is revealed")
            try expect(head.headOpacity > 0 && head.torsoOpacity == 0,
                       "\(entrance) head emerges before the supporting torso")
            try expect(weight.body.scaleY < 0.98 && weight.body.scaleX > 1.01,
                       "\(entrance) climb anticipates with compressed weight")
            try expect(abs(settled.body.translation.x) < 0.001 && abs(settled.body.translation.y) < 0.001
                       && abs(settled.body.scaleX - 1) < 0.001 && abs(settled.body.scaleY - 1) < 0.001,
                       "\(entrance) weight settles gently into a neutral body")
            try expect(settled.headOpacity == 1 && settled.torsoOpacity == 1 && settled.handOpacity == 1
                       && settled.peekEyeOpacity == 0,
                       "\(entrance) full reveal switches from peeking eyes to the complete character")

            let fixedGrip = CGPoint(x: entrance == .right ? 58 : 6, y: 17)
            let first = RobotCompanionPose.make(revealProgress: 0.70, pointer: CGPoint(x: -1, y: -1),
                                                entrance: entrance, expressionOnly: false, gripPoint: fixedGrip)
            let second = RobotCompanionPose.make(revealProgress: 1, pointer: CGPoint(x: 1, y: 1),
                                                 entrance: entrance, expressionOnly: false, gripPoint: fixedGrip)
            let firstGrip = first.grippingHandIndex == 0 ? first.leftHand : first.rightHand
            let secondGrip = second.grippingHandIndex == 0 ? second.leftHand : second.rightHand
            let firstReach = first.grippingHandIndex == 0 ? first.rightHand : first.leftHand
            let secondReach = second.grippingHandIndex == 0 ? second.rightHand : second.leftHand
            try expect(firstGrip == fixedGrip && secondGrip == fixedGrip,
                       "\(entrance) grip remains attached to the same physical edge during weight and gaze changes")
            try expect(firstReach != secondReach && second.gaze.x > first.gaze.x && second.gaze.y > first.gaze.y,
                       "\(entrance) the free hand, head and gaze respond to the cursor without relocating the grip")
            try expect(second.grippingHandIndex == (entrance == .right ? 1 : 0),
                       "\(entrance) uses the hand nearest the chosen edge as its grip")

            for x: CGFloat in [-1, 0, 1] {
                for y: CGFloat in [-1, 0, 1] {
                    let edgeReach = RobotCompanionPose.make(revealProgress: 1,
                        pointer: CGPoint(x: x, y: y), entrance: entrance, expressionOnly: false)
                    let palm = edgeReach.grippingHandIndex == 0 ? edgeReach.rightHand : edgeReach.leftHand
                    try expect(palm.x >= 3 && palm.x <= 61 && palm.y >= 3 && palm.y <= 75,
                               "\(entrance) reaching toward every cursor direction retains room for the complete palm in the fixed stage")
                }
            }

            let still = RobotCompanionPose.make(revealProgress: 0.6, pointer: CGPoint(x: 0.8, y: 0.6),
                                                entrance: entrance, expressionOnly: true)
            try expect(still.isExpressionOnly && still.body == .identity && still.head == .identity
                       && still.feet == .identity && still.handOpacity == 0 && still.eyeBrightness > 1,
                       "\(entrance) Quiet Mode and Reduce Motion retain only a simple bright expression")
        }
        let invalidPose = RobotCompanionPose.make(revealProgress: CGFloat.infinity,
            pointer: CGPoint(x: CGFloat.nan, y: -CGFloat.infinity), entrance: .top, expressionOnly: false,
            gripPoint: CGPoint(x: CGFloat.nan, y: CGFloat.infinity))
        try expect(invalidPose.headOpacity == 0 && invalidPose.body == .identity
                   && invalidPose.leftHand.x.isFinite && invalidPose.rightHand.y.isFinite,
                   "Invalid approach geometry cannot create an unbounded compositor transform")

        let animated = RobotCharacterView(frame: NSRect(x: 0, y: 0, width: 64, height: 78),
                                          reduceMotion: { false })
        animated.layoutSubtreeIfNeeded()
        animated.send(.reveal(.left))
        try expect(animated.mood == .idle && !animated.hasActiveAmbientMotion,
                   "Quiet Orbit remains still without idle rendering timers")
        animated.send(.hover(true, pointer: CGPoint(x: 0.4, y: 0.2)))
        try expect(animated.mood == .curious(pointer: CGPoint(x: 0.4, y: 0.2)),
                   "Character view exposes its curious pointer state")
        animated.send(.acceptedDrag(true))
        try expect(animated.mood == .hungry, "Character view reacts before a drop is committed")
        animated.send(.saving(true))
        try expect(animated.mood == .digesting, "Character view begins chewing while an import saves")
        animated.send(.result(.success))
        try expect(animated.mood == .delighted, "Character view hops after a successful import")
        animated.send(.feedbackExpired)
        try expect(animated.mood == .curious(pointer: CGPoint(x: 0.4, y: 0.2)),
                   "Feedback expiry returns to the still-active hover expression")
        animated.stopMotion()
        try expect(animated.mood == .hidden && !animated.hasActiveAmbientMotion,
                   "Stopping the character cancels ambient work and hides its state")

        let fixedCharacterFrame = animated.frame
        animated.applyCompanionPose(revealProgress: 0.18, pointer: CGPoint(x: 0.4, y: -0.2),
                                    entrance: .top, duration: 0)
        try expect(animated.currentCompanionPose?.peekEyeOpacity == 1
                   && animated.mood == .curious(pointer: CGPoint(x: 0.4, y: -0.2)),
                   "The native renderer exposes an eyes-first curious encounter")
        animated.applyCompanionPose(revealProgress: 1, pointer: CGPoint(x: -0.7, y: 0.3),
                                    entrance: .left, duration: 0, gripPoint: CGPoint(x: 8, y: 19))
        try expect(animated.frame == fixedCharacterFrame && animated.currentCompanionPose?.leftHand == CGPoint(x: 8, y: 19),
                   "Whole-body acting preserves the fixed native frame while its stage-space hand grips the edge")
        animated.applyCompanionPose(revealProgress: 0.55, pointer: .zero, entrance: .left, duration: 0.15)
        try expect(animated.hasActiveCompanionAnimations,
                   "An ordinary approach interpolates finite compositor poses")
        animated.applyCompanionPose(revealProgress: 0.55, pointer: .zero, entrance: .left, expressionOnly: true)
        try expect(!animated.hasActiveCompanionAnimations && animated.currentCompanionPose?.body == .identity,
                   "Quiet Mode interrupts an in-flight approach and cancels its compositor movement")
        animated.send(.saving(true))
        try expect(animated.currentCompanionPose == nil && animated.mood == .digesting,
                   "A capture immediately interrupts the invitation and restores ordinary save rendering")
        animated.applyCompanionPose(revealProgress: 0, pointer: .zero, entrance: .left, duration: 0)
        try expect(animated.mood == .hidden && animated.currentCompanionPose?.headOpacity == 0,
                   "A completed retreat clears the semantic hover state")
        animated.stopMotion()
        try expect(animated.currentCompanionPose == nil && !animated.hasActiveAmbientMotion,
                   "Closing the surface cancels every invitation pose")

        let reduced = RobotCharacterView(frame: NSRect(x: 0, y: 0, width: 64, height: 78),
                                         reduceMotion: { true })
        reduced.send(.reveal(.top))
        try expect(reduced.mood == .idle && !reduced.hasActiveAmbientMotion,
                   "Reduced-motion character appears without scheduling ambient animation")
        reduced.send(.acceptedDrag(true))
        reduced.send(.saving(true))
        reduced.send(.result(.failure))
        try expect(reduced.mood == .puzzled && !reduced.hasActiveAmbientMotion,
                   "Reduced-motion character keeps meaningful states without looping motion")
        reduced.applyCompanionPose(revealProgress: 0.65, pointer: CGPoint(x: 1, y: -1), entrance: .right)
        try expect(reduced.currentCompanionPose?.isExpressionOnly == true
                   && reduced.currentCompanionPose?.body == .identity
                   && reduced.currentCompanionPose?.feet == .identity && !reduced.hasActiveCompanionAnimations,
                   "The renderer's Reduce Motion provider independently removes invitation travel and foot movement")
        reduced.stopMotion()

        let target = RobotView(frame: NSRect(x: 0, y: 0, width: 72, height: 88), reduceMotion: { true })
        target.present(from: .top)
        try expect(target.isPresented && target.mood == .idle,
                   "Robot interaction surface forwards camera-island reveal")
        target.isSaving = true
        try expect(target.mood == .digesting, "Robot interaction surface forwards busy state")
        target.digest(success: true)
        try expect(target.mood == .delighted, "Robot interaction surface forwards save results")
        target.hideCharacter()
        try expect(!target.isPresented && target.mood == .hidden,
                   "Robot interaction surface hides and clears character work")
        target.stopFeedback()

        try renderCompanionFixtures()

        print("PASS: \(checks) robot motion and personality checks")
    }
}
