import CoreGraphics
import Foundation

@main
private struct IslandRobotChoreographyTests {
    private static var checks = 0

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard condition() else {
            throw NSError(domain: "DaBinIslandRobotChoreographyTests", code: checks,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private static func near(_ first: CGFloat, _ second: CGFloat, tolerance: CGFloat = 0.000_001) -> Bool {
        abs(first - second) <= tolerance
    }

    private static func near(_ first: CGPoint, _ second: CGPoint) -> Bool {
        near(first.x, second.x) && near(first.y, second.y)
    }

    static func main() throws {
        let pivot = IslandRobotChoreography.bodyPivot
        try expect(pivot == CGPoint(x: 32, y: 0), "The body rotates at the island edge")
        let identityPoint = CGPoint(x: 14, y: 43)
        try expect(IslandRobotChoreography.worldPoint(identityPoint, body: .identity) == identityPoint,
                   "Neutral hanging preserves design-space shoulders")
        let transformed = IslandRobotChoreography.worldPoint(
            CGPoint(x: 42, y: 10),
            body: RobotPartTransform(translation: CGPoint(x: 5, y: 7), scaleX: 2, scaleY: 3,
                                     rotationDegrees: 90))
        try expect(near(transformed, CGPoint(x: 7, y: 27)),
                   "World points scale, rotate about the lip, then translate in renderer order")

        var signatures = Set<String>()
        let representatives: [(AutoCaptureRobotReaction, IslandRobotAct)] = [
            (.quickBite, .swingSnack), (.oversizedBite, .slipCatch), (.escapingCapture, .ledgeShimmy)
        ]
        for (reaction, act) in representatives {
            try expect(IslandRobotAct.forReaction(reaction) == act, "\(reaction) selects its physical act")
            let performance = AutoCaptureRobotPerformance.make(reaction: reaction, entrance: .top,
                                                               reduceMotion: false)
            let frames = IslandRobotChoreography.capture(performance)
            try validate(frames, duration: performance.totalDuration, label: act.rawValue)
            try expect((3.4...4.0).contains(performance.totalDuration),
                       "Island performance leaves time to read its contacts")
            for phase in performance.phases {
                try expect(frames.contains { abs($0.time - phase.startTime) < 0.000_001 }
                           && frames.contains { abs($0.time - phase.endTime) < 0.000_001 },
                           "Every semantic phase boundary has an exact sample")
            }

            let anticipation = performance.phases.first { $0.kind == .anticipation }!
            let entrance = performance.phases.first { $0.kind == .entrance }!
            let eating = performance.phases.first { $0.kind == .eating(reaction) }!
            let exit = performance.phases.first { $0.kind == .exit }!
            let lowering = frames.filter { $0.time >= anticipation.endTime && $0.time <= entrance.endTime }
            try expect(lowering.allSatisfy {
                near($0.leftHand, IslandRobotChoreography.leftGrip)
                    && near($0.rightHand, IslandRobotChoreography.rightGrip)
                    && $0.leftHandOpacity == 1 && $0.rightHandOpacity == 1
            }, "Both supporting hands stay planted as the body lowers")

            let action = frames.filter { $0.time >= eating.startTime && $0.time <= eating.endTime }
            if act == .swingSnack || act == .slipCatch {
                try expect(action.allSatisfy { near($0.leftHand, IslandRobotChoreography.leftGrip) },
                           "The supporting left hand never slides during \(act)")
                try expect(action.contains { !near($0.rightHand, IslandRobotChoreography.rightGrip) },
                           "The free hand visibly leaves the lip")
            }
            switch act {
            case .swingSnack:
                try expect(action.contains { $0.body.rotationDegrees <= -10 }
                           && action.contains { $0.body.rotationDegrees >= 8 },
                           "Snack swing crosses both sides of its grip")
            case .slipCatch:
                try expect(action.contains { $0.body.translation.y >= 14 && $0.leftEyeScaleY > 1.2 },
                           "The slip has a visible drop and startled expression")
                try expect(action.contains { $0.body.translation.y < -4 },
                           "The recovery pulls upward after catching the lip")
            case .ledgeShimmy:
                try expect(action.contains { $0.body.translation.x >= 17 },
                           "The shimmy travels visibly along the ledge")
                let support = action.filter {
                    $0.time >= eating.startTime + eating.duration * 0.27
                        && $0.time <= eating.startTime + eating.duration * 0.67
                }
                try expect(!support.isEmpty && support.allSatisfy { near($0.rightHand, CGPoint(x: 64, y: 1)) },
                           "The advanced right grip stays fixed during the second hand's step")
            }
            let pulling = frames.filter {
                $0.time >= exit.startTime && $0.time <= exit.startTime + exit.duration * 0.62
            }
            try expect(pulling.allSatisfy {
                near($0.leftHand, IslandRobotChoreography.leftGrip)
                    && near($0.rightHand, IslandRobotChoreography.rightGrip)
            }, "Both hands support the pull-up before either lets go")
            try expect(frames.filter { $0.time >= exit.startTime && $0.leftHandOpacity < 0.99 }.allSatisfy {
                $0.body.translation.y < -80
            }, "The robot is behind the lip before releasing its supporting hand")
            let last = frames.last!
            try expect(last.body.translation.y < -80 && last.leftHandOpacity == 0 && last.rightHandOpacity == 0,
                       "The entire performance finishes hidden")
            try expect(frames.allSatisfy { abs($0.body.rotationDegrees) <= 14 },
                       "Capture reactions use pendulums rather than full spins")
            signatures.insert(action.map {
                String(format: "%.2f,%.2f,%.2f", Double($0.body.translation.x),
                       Double($0.body.translation.y), Double($0.body.rotationDegrees))
            }.joined(separator: ";"))
        }
        try expect(signatures.count == 3, "Each physical act produces distinct body travel")

        for reaction in AutoCaptureRobotReaction.allCases {
            for variation in [AutoCaptureRobotVariation.standard,
                              AutoCaptureRobotVariation(timingScale: 0.96, gazeX: -0.45, entranceOffset: -2),
                              AutoCaptureRobotVariation(timingScale: 1.04, gazeX: 0.45, entranceOffset: 2)] {
                let performance = AutoCaptureRobotPerformance.make(reaction: reaction, variation: variation,
                                                                   entrance: .top, reduceMotion: false)
                try validate(IslandRobotChoreography.capture(performance), duration: performance.totalDuration,
                             label: reaction.rawValue)
            }
        }
        let mirroredPerformance = AutoCaptureRobotPerformance.make(
            reaction: .escapingCapture, variation: .init(timingScale: 1, gazeX: -0.3, entranceOffset: 0),
            entrance: .top, reduceMotion: false)
        try expect(IslandRobotChoreography.capture(mirroredPerformance).contains { $0.body.translation.x <= -17 },
                   "The alternate shimmy explores the other side of the lip")

        let reveal = IslandRobotChoreography.reveal(duration: 0.9)
        try validate(reveal, duration: 0.9, label: "reveal")
        try expect(reveal.first!.body.translation.y < -80 && reveal.last!.body == .identity,
                   "Reveal lowers from behind the edge into neutral hanging")
        try expect(near(reveal.last!.leftHand, IslandRobotChoreography.leftGrip)
                   && near(reveal.last!.rightHand, IslandRobotChoreography.rightGrip),
                   "Reveal ends with two anchored hands")

        let peek = IslandRobotChoreography.peek(duration: 1.7)
        try validate(peek, duration: 1.7, label: "peek")
        try expect(peek.allSatisfy { $0.body.rotationDegrees == 180 },
                   "The upside-down peek has no visible full-spin transition")
        try expect(peek.contains { near($0.body.translation.y, 50) }
                   && peek.first!.body.translation.y == -5 && peek.last!.body.translation.y == -5,
                   "The peek reaches a visible head hold and returns behind the lip")
        try expect(peek.filter { $0.leftHandOpacity == 1 }.allSatisfy {
            near($0.leftHand, IslandRobotChoreography.rightGrip)
        }, "The inverted anatomical left hand holds the correct screen-side grip")
        try expect(peek.contains { $0.rightHand.y > 10 && $0.body.translation.y == 50 },
                   "The free hand waves while the head remains visible")

        for duration in [0.0, -1.0, Double.nan, Double.infinity] {
            try validate(IslandRobotChoreography.reveal(duration: duration), duration: 0, label: "zero reveal")
            try validate(IslandRobotChoreography.peek(duration: duration), duration: 0, label: "zero peek")
        }
        let fallback = AutoCaptureRobotPerformance.make(reaction: .quickBite, entrance: .right, reduceMotion: false)
        try expect(abs(fallback.totalDuration - 2.33) < 0.000_001,
                   "Side-screen fallback timing is unchanged")
        let reduced = AutoCaptureRobotPerformance.make(reaction: .quickBite, entrance: .top, reduceMotion: true)
        try expect(abs(reduced.totalDuration - 0.74) < 0.000_001,
                   "Reduced Motion keeps the existing short static confirmation")
        print("PASS: \(checks) island choreography contact, timing, and envelope checks")
    }

    private static func validate(_ frames: [IslandRobotFrame], duration: Double, label: String) throws {
        try expect(!frames.isEmpty, "\(label) supplies frames")
        try expect(frames.first!.time == 0 && abs(frames.last!.time - duration) < 0.000_001,
                   "\(label) covers its exact full duration")
        for (index, frame) in frames.enumerated() {
            let numbers: [CGFloat] = [CGFloat(frame.time), frame.body.translation.x, frame.body.translation.y,
                                      frame.body.scaleX, frame.body.scaleY, frame.body.rotationDegrees,
                                      frame.leftHand.x, frame.leftHand.y, frame.rightHand.x, frame.rightHand.y,
                                      CGFloat(frame.leftHandOpacity), CGFloat(frame.rightHandOpacity),
                                      frame.feet.translation.x, frame.feet.translation.y, frame.feet.scaleX,
                                      frame.feet.scaleY, frame.feet.rotationDegrees, frame.gaze.x, frame.gaze.y,
                                      frame.leftEyeScaleY, frame.rightEyeScaleY]
            try expect(numbers.allSatisfy(\.isFinite), "\(label) has no NaN or infinite frame values")
            try expect((0...1).contains(frame.leftHandOpacity) && (0...1).contains(frame.rightHandOpacity),
                       "\(label) hand visibility stays bounded")
            if index > 0 {
                let gap = frame.time - frames[index - 1].time
                try expect(gap > 0 && gap <= 1.0 / 30 + 0.000_001,
                           "\(label) times are unique, ordered, and at least 30Hz")
            }
            let corners = [CGPoint(x: 0, y: 0), CGPoint(x: 64, y: 0),
                           CGPoint(x: 0, y: 78), CGPoint(x: 64, y: 78)]
            let points = corners.map { IslandRobotChoreography.worldPoint($0, body: frame.body) }
                + [frame.leftHand, frame.rightHand]
            try expect(points.filter { $0.y >= 0 }.allSatisfy {
                (-55.0...119.0).contains($0.x) && $0.y <= 105
            }, "\(label) visible body and hand travel fits the island stage")
        }
    }
}
