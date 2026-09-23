import AppKit
import Foundation

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

        let animated = RobotCharacterView(frame: NSRect(x: 0, y: 0, width: 64, height: 78),
                                          reduceMotion: { false })
        animated.layoutSubtreeIfNeeded()
        animated.send(.reveal(.left))
        try expect(animated.mood == .idle && animated.hasActiveAmbientMotion,
                   "Visible animated character schedules quiet blink and glance personality")
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

        print("PASS: \(checks) robot motion and personality checks")
    }
}
