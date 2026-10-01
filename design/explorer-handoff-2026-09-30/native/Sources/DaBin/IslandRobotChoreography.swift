import CoreGraphics
import Foundation

/// A small set of readable physical performances, shared by all capture styles.
enum IslandRobotAct: String, CaseIterable {
    case swingSnack
    case slipCatch
    case ledgeShimmy

    static func forReaction(_ reaction: AutoCaptureRobotReaction) -> Self {
        switch reaction.eatingStyle {
        case .recoil, .swallow, .hiccup: return .slipCatch
        case .chase, .inspect, .nibble: return .ledgeShimmy
        case .bite, .slurp, .toss, .stack: return .swingSnack
        }
    }
}

/// Hands are world/design-space targets, not children of the moving torso.
/// Feet are a secondary local transform; gaze is a local pupil offset.
struct IslandRobotFrame: Equatable {
    let time: TimeInterval
    let body: RobotPartTransform
    let leftHand: CGPoint
    let rightHand: CGPoint
    let leftHandOpacity: Float
    let rightHandOpacity: Float
    let feet: RobotPartTransform
    let gaze: CGPoint
    let leftEyeScaleY: CGFloat
    let rightEyeScaleY: CGFloat
}

/// Deterministic layer-ready motion. The island edge is y=0, down is positive,
/// and body transforms rotate about (32,0). No timer, window, or capture data.
enum IslandRobotChoreography {
    static let bodyPivot = CGPoint(x: 32, y: 0)
    static let leftGrip = CGPoint(x: 18, y: 1)
    static let rightGrip = CGPoint(x: 46, y: 1)
    static let sampleRate: Double = 30

    /// Equivalent to the renderer's translate × rotate × scale transform,
    /// accounting for the body's island-edge anchor point.
    static func worldPoint(_ point: CGPoint, body: RobotPartTransform) -> CGPoint {
        let radians = body.rotationDegrees * .pi / 180
        let x = (point.x - bodyPivot.x) * body.scaleX
        let y = (point.y - bodyPivot.y) * body.scaleY
        return CGPoint(x: bodyPivot.x + body.translation.x + x * cos(radians) - y * sin(radians),
                       y: bodyPivot.y + body.translation.y + x * sin(radians) + y * cos(radians))
    }

    static func capture(_ performance: AutoCaptureRobotPerformance) -> [IslandRobotFrame] {
        let duration = validDuration(performance.totalDuration)
        guard !performance.reduceMotion,
              let anticipation = performance.phases.first(where: { $0.kind == .anticipation }),
              let entrance = performance.phases.first(where: { $0.kind == .entrance }),
              let eating = performance.phases.first(where: { $0.kind == .eating(performance.reaction) }),
              let reaction = performance.phases.first(where: { $0.kind == .reaction(performance.reaction) }),
              let exit = performance.phases.first(where: { $0.kind == .exit }),
              duration > 0 else {
            return sample([Knot(0, .hidden), Knot(duration, .hidden)], duration: duration)
        }

        var knots = entranceKnots(anticipationEnd: anticipation.endTime,
                                  entranceEnd: entrance.endTime)
        let act = IslandRobotAct.forReaction(performance.reaction)
        let mirrored = act == .ledgeShimmy && performance.variation.gazeX < 0
        knots += eatingKnots(act, phase: eating).map { knot in
            mirrored ? Knot(knot.time, knot.pose.mirrored) : knot
        }
        knots += [
            Knot(reaction.startTime, Pose()),
            Knot(at(reaction, 0.28), Pose(body: body(y: -2), gaze: CGPoint(x: 0, y: -0.5))),
            Knot(at(reaction, 0.56), Pose(leftEye: 0.12, rightEye: 0.9)),
            Knot(at(reaction, 0.78), Pose()),
            Knot(reaction.endTime, Pose())
        ]
        knots += exitKnots(exit)
        return sample(knots, duration: duration,
                      exactTimes: performance.phases.flatMap { [$0.startTime, $0.endTime] })
    }

    /// Feet emerge first under an opaque edge; no part opacity is needed.
    /// Ends in a stable two-handed hang for the interaction surface to own.
    static func reveal(duration: TimeInterval) -> [IslandRobotFrame] {
        let duration = validDuration(duration)
        guard duration > 0 else { return [Pose().frame(at: 0)] }
        return sample(entranceKnots(anticipationEnd: duration * 0.27,
                                    entranceEnd: duration), duration: duration)
    }

    /// An upside-down look from behind the lip. Rotating the shoulders swaps
    /// their screen sides, so the anatomical left hand grips at x=46 here.
    static func peek(duration: TimeInterval) -> [IslandRobotFrame] {
        let duration = validDuration(duration)
        func pose(_ y: CGFloat, leftOpacity: Float = 1, rightOpacity: Float = 1,
                  right: Hand = .world(leftGrip), gaze: CGPoint = .zero,
                  leftEye: CGFloat = 1, rightEye: CGFloat = 1) -> Pose {
            Pose(body: body(y: y, angle: 180), left: .world(rightGrip), right: right,
                 leftOpacity: leftOpacity, rightOpacity: rightOpacity, gaze: gaze,
                 leftEye: leftEye, rightEye: rightEye)
        }
        let hidden = pose(-5, leftOpacity: 0, rightOpacity: 0)
        let knots = [
            Knot(0, hidden),
            Knot(duration * 0.10, pose(-5, rightOpacity: 0)),
            Knot(duration * 0.18, pose(8)),
            Knot(duration * 0.32, pose(50, gaze: CGPoint(x: -1, y: 0))),
            Knot(duration * 0.44, pose(50, gaze: CGPoint(x: 1.5, y: 0))),
            Knot(duration * 0.53, pose(50, right: .world(CGPoint(x: 10, y: 16)))),
            Knot(duration * 0.61, pose(50, right: .world(CGPoint(x: 5, y: 20)), leftEye: 0.15)),
            Knot(duration * 0.68, pose(50, right: .world(CGPoint(x: 13, y: 15)))),
            Knot(duration * 0.76, pose(50)),
            Knot(duration * 0.91, pose(-5)),
            Knot(duration, hidden)
        ]
        return sample(knots, duration: duration)
    }

    // MARK: - Contact-aware pose construction

    private enum Hand {
        case world(CGPoint)
        case body(CGPoint)

        func point(body: RobotPartTransform) -> CGPoint {
            switch self {
            case .world(let point): return point
            case .body(let point): return IslandRobotChoreography.worldPoint(point, body: body)
            }
        }

        var mirrored: Hand {
            switch self {
            case .world(let p): return .world(CGPoint(x: 64 - p.x, y: p.y))
            case .body(let p): return .body(CGPoint(x: 64 - p.x, y: p.y))
            }
        }
    }

    private struct Pose {
        var body = RobotPartTransform.identity
        var left = Hand.world(IslandRobotChoreography.leftGrip)
        var right = Hand.world(IslandRobotChoreography.rightGrip)
        var leftOpacity: Float = 1
        var rightOpacity: Float = 1
        var feet = RobotPartTransform.identity
        var gaze = CGPoint.zero
        var leftEye: CGFloat = 1
        var rightEye: CGFloat = 1

        static let hidden = Pose(body: RobotPartTransform(translation: CGPoint(x: 0, y: -94)),
                                 leftOpacity: 0, rightOpacity: 0)

        func frame(at time: TimeInterval) -> IslandRobotFrame {
            IslandRobotFrame(time: time, body: body, leftHand: left.point(body: body),
                             rightHand: right.point(body: body), leftHandOpacity: leftOpacity,
                             rightHandOpacity: rightOpacity, feet: feet, gaze: gaze,
                             leftEyeScaleY: leftEye, rightEyeScaleY: rightEye)
        }

        var mirrored: Pose {
            var result = self
            result.body.translation.x *= -1
            result.body.rotationDegrees *= -1
            result.left = right.mirrored
            result.right = left.mirrored
            result.leftOpacity = rightOpacity
            result.rightOpacity = leftOpacity
            result.feet.translation.x *= -1
            result.feet.rotationDegrees *= -1
            result.gaze.x *= -1
            result.leftEye = rightEye
            result.rightEye = leftEye
            return result
        }
    }

    private struct Knot {
        let time: TimeInterval
        let pose: Pose
        init(_ time: TimeInterval, _ pose: Pose) { self.time = time; self.pose = pose }
    }

    private static func body(x: CGFloat = 0, y: CGFloat = 0,
                             angle: CGFloat = 0, scaleY: CGFloat = 1) -> RobotPartTransform {
        RobotPartTransform(translation: CGPoint(x: x, y: y), scaleY: scaleY,
                           rotationDegrees: angle)
    }

    /// A pendulum rotates about the planted left hand, not the feet. Translation
    /// compensates the renderer's central pivot to keep that contact exact.
    private static func suspended(_ angle: CGFloat) -> RobotPartTransform {
        var pose = body(angle: angle)
        let movedGrip = worldPoint(leftGrip, body: pose)
        pose.translation = CGPoint(x: leftGrip.x - movedGrip.x, y: leftGrip.y - movedGrip.y)
        return pose
    }

    private static func entranceKnots(anticipationEnd: TimeInterval,
                                      entranceEnd: TimeInterval) -> [Knot] {
        let span = entranceEnd - anticipationEnd
        func time(_ fraction: Double) -> Double { anticipationEnd + span * fraction }
        return [
            Knot(0, .hidden),
            Knot(anticipationEnd * 0.26, Pose(body: body(y: -94), rightOpacity: 0)),
            Knot(anticipationEnd * 0.60, Pose(body: body(y: -82), rightOpacity: 0)),
            Knot(anticipationEnd * 0.86, Pose(body: body(y: -75))),
            Knot(anticipationEnd, Pose(body: body(y: -61))),
            Knot(time(0.22), Pose(body: body(y: -38, angle: -4), feet: body(angle: 7))),
            Knot(time(0.46), Pose(body: body(y: -12, angle: 4), feet: body(y: 2, angle: -7))),
            Knot(time(0.68), Pose(body: body(y: 4, angle: -3, scaleY: 1.02),
                                  feet: body(y: 3, angle: 9))),
            Knot(time(0.88), Pose(body: body(angle: 1), feet: body(angle: -3))),
            Knot(entranceEnd, Pose())
        ]
    }

    private static func eatingKnots(_ act: IslandRobotAct,
                                    phase: AutoCaptureRobotPerformancePhase) -> [Knot] {
        func knot(_ fraction: Double, _ pose: Pose) -> Knot { Knot(at(phase, fraction), pose) }
        switch act {
        case .swingSnack:
            return [
                knot(0, Pose()), knot(0.08, Pose()),
                knot(0.20, Pose(body: suspended(-12), right: .body(CGPoint(x: 56, y: 36)),
                                feet: body(angle: 11), gaze: CGPoint(x: 2, y: 0))),
                knot(0.37, Pose(body: suspended(10), right: .body(CGPoint(x: 41, y: 44)),
                                feet: body(angle: -9), gaze: CGPoint(x: 0.5, y: 1))),
                knot(0.55, Pose(body: suspended(-6), right: .body(CGPoint(x: 40, y: 45)),
                                feet: body(angle: 6), leftEye: 0.4, rightEye: 0.4)),
                knot(0.72, Pose(body: suspended(3), right: .body(CGPoint(x: 53, y: 38)),
                                feet: body(angle: -3))),
                knot(0.90, Pose()), knot(1, Pose())
            ]
        case .slipCatch:
            return [
                knot(0, Pose()),
                knot(0.16, Pose(right: .body(CGPoint(x: 51, y: 38)), gaze: CGPoint(x: 2, y: 0))),
                knot(0.30, Pose(body: body(x: 2, y: 16, angle: -14),
                                right: .body(CGPoint(x: 59, y: 19)), feet: body(y: 4, angle: 12),
                                leftEye: 1.35, rightEye: 1.35)),
                knot(0.42, Pose(body: body(x: 1, y: 12, angle: -9),
                                right: .world(rightGrip), feet: body(angle: 7),
                                gaze: CGPoint(x: 0, y: -2), leftEye: 1.2, rightEye: 1.2)),
                knot(0.57, Pose(body: body(y: -5, angle: 3), feet: body(y: -4, angle: -8),
                                leftEye: 0.3, rightEye: 0.3)),
                knot(0.73, Pose(body: body(y: 2, angle: -2), feet: body(angle: 3))),
                knot(0.89, Pose()), knot(1, Pose())
            ]
        case .ledgeShimmy:
            return [
                knot(0, Pose()),
                knot(0.12, Pose(right: .body(CGPoint(x: 58, y: 12)), gaze: CGPoint(x: 2, y: -1))),
                knot(0.27, Pose(body: body(x: 8, angle: -3),
                                right: .world(CGPoint(x: 64, y: 1)), feet: body(angle: 7))),
                knot(0.40, Pose(body: body(x: 18, angle: -2),
                                left: .body(CGPoint(x: 17, y: 13)), right: .world(CGPoint(x: 64, y: 1)),
                                feet: body(angle: 3), gaze: CGPoint(x: 1.5, y: 0))),
                knot(0.53, Pose(body: body(x: 18), left: .world(CGPoint(x: 36, y: 1)),
                                right: .world(CGPoint(x: 64, y: 1)), gaze: CGPoint(x: 1, y: 1))),
                knot(0.67, Pose(body: body(x: 12, angle: 3),
                                right: .world(CGPoint(x: 64, y: 1)), feet: body(angle: -6))),
                knot(0.82, Pose(right: .body(CGPoint(x: 55, y: 15)), feet: body(angle: -2))),
                knot(0.94, Pose()), knot(1, Pose())
            ]
        }
    }

    private static func exitKnots(_ phase: AutoCaptureRobotPerformancePhase) -> [Knot] {
        [
            Knot(phase.startTime, Pose()),
            Knot(at(phase, 0.18), Pose(body: body(y: -7), feet: body(y: -3, angle: -10),
                                      gaze: CGPoint(x: 0, y: -2))),
            Knot(at(phase, 0.38), Pose(body: body(y: -31, angle: -3), feet: body(y: -8, angle: -12))),
            Knot(at(phase, 0.62), Pose(body: body(y: -70), feet: body(y: -7, angle: -7))),
            Knot(at(phase, 0.77), Pose(body: body(y: -94), right: .world(CGPoint(x: 43, y: 8)))),
            Knot(at(phase, 0.85), Pose(body: body(y: -94), left: .world(CGPoint(x: 18, y: -5)),
                                      right: .world(CGPoint(x: 50, y: 4)), leftOpacity: 0)),
            Knot(at(phase, 0.93), Pose(body: body(y: -94), left: .world(CGPoint(x: 18, y: -5)),
                                      right: .world(CGPoint(x: 43, y: 8)), leftOpacity: 0)),
            Knot(phase.endTime, Pose(body: body(y: -94), left: .world(CGPoint(x: 18, y: -7)),
                                    right: .world(CGPoint(x: 46, y: -7)), leftOpacity: 0, rightOpacity: 0))
        ]
    }

    // MARK: - Sampling

    private static func validDuration(_ duration: TimeInterval) -> TimeInterval {
        duration.isFinite ? max(0, duration) : 0
    }

    private static func at(_ phase: AutoCaptureRobotPerformancePhase, _ fraction: Double) -> Double {
        phase.startTime + phase.duration * fraction
    }

    private static func sample(_ input: [Knot], duration: TimeInterval,
                               exactTimes: [TimeInterval] = []) -> [IslandRobotFrame] {
        // Prefer the last authored pose at a shared phase boundary.
        var byTime: [TimeInterval: Pose] = [:]
        for knot in input where knot.time.isFinite && knot.time >= 0 && knot.time <= duration {
            byTime[knot.time] = knot.pose
        }
        let knots = byTime.keys.sorted().map { Knot($0, byTime[$0]!) }
        guard let first = knots.first else { return [Pose.hidden.frame(at: 0)] }
        guard duration > 0 else { return [first.pose.frame(at: 0)] }
        var times = Set(knots.map(\.time) + [0, duration] + exactTimes.filter {
            $0.isFinite && $0 >= 0 && $0 <= duration
        })
        let exact = times
        for index in 0...Int(ceil(duration * sampleRate)) {
            let time = min(duration, Double(index) / sampleRate)
            if !exact.contains(where: { abs($0 - time) < 0.000_000_1 }) { times.insert(time) }
        }
        var segment = 0
        return times.sorted().map { time in
            while segment + 1 < knots.count && knots[segment + 1].time < time { segment += 1 }
            guard segment + 1 < knots.count else { return knots.last!.pose.frame(at: time) }
            let start = knots[segment], end = knots[segment + 1]
            let fraction = max(0, min(1, (time - start.time) / (end.time - start.time)))
            let eased = CGFloat(fraction * fraction * (3 - 2 * fraction))
            return interpolate(start.pose, end.pose, fraction: eased).frame(at: time)
        }
    }

    private static func interpolate(_ a: Pose, _ b: Pose, fraction t: CGFloat) -> Pose {
        let body = mix(a.body, b.body, t)
        func hand(_ first: Hand, _ second: Hand) -> Hand {
            switch (first, second) {
            case (.body(let p), .body(let q)): return .body(mix(p, q, t))
            default:
                return .world(mix(first.point(body: body), second.point(body: body), t))
            }
        }
        return Pose(body: body, left: hand(a.left, b.left), right: hand(a.right, b.right),
                    leftOpacity: Float(mix(CGFloat(a.leftOpacity), CGFloat(b.leftOpacity), t)),
                    rightOpacity: Float(mix(CGFloat(a.rightOpacity), CGFloat(b.rightOpacity), t)),
                    feet: mix(a.feet, b.feet, t), gaze: mix(a.gaze, b.gaze, t),
                    leftEye: mix(a.leftEye, b.leftEye, t), rightEye: mix(a.rightEye, b.rightEye, t))
    }

    private static func mix(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
    private static func mix(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: mix(a.x, b.x, t), y: mix(a.y, b.y, t))
    }
    private static func mix(_ a: RobotPartTransform, _ b: RobotPartTransform,
                            _ t: CGFloat) -> RobotPartTransform {
        RobotPartTransform(translation: mix(a.translation, b.translation, t),
                           scaleX: mix(a.scaleX, b.scaleX, t), scaleY: mix(a.scaleY, b.scaleY, t),
                           rotationDegrees: mix(a.rotationDegrees, b.rotationDegrees, t))
    }
}
