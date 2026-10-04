import Foundation

/// The only capture categories that can influence a confirmation sign. The
/// sign model deliberately has no initializer that accepts captured content.
enum AutoCaptureSignKind: String, CaseIterable, Equatable, Sendable {
    case screenshot
    case clipboard
    case mixed

    fileprivate func merging(_ other: Self) -> Self {
        self == other ? self : .mixed
    }
}

/// Privacy-safe content for an Auto Capture confirmation sign. All visible and
/// spoken copy is derived from a closed capture kind and a positive count.
struct AutoCaptureSignReceipt: Equatable, Sendable {
    let kind: AutoCaptureSignKind
    let count: Int
    let icon: String
    let message: String
    let accessibilityText: String

    init(kind: AutoCaptureSignKind, count: Int = 1) {
        let safeCount = max(1, count)
        self.kind = kind
        self.count = safeCount

        switch kind {
        case .screenshot:
            icon = "camera.viewfinder"
            message = "Screenshot saved!"
            accessibilityText = safeCount == 1
                ? "Screenshot saved"
                : "\(safeCount) screenshots saved"
        case .clipboard:
            icon = "doc.on.clipboard.fill"
            message = "Copied!"
            accessibilityText = safeCount == 1
                ? "Copied"
                : "\(safeCount) clipboard captures saved"
        case .mixed:
            icon = "square.stack.3d.up.fill"
            message = "Captures saved!"
            accessibilityText = safeCount == 1
                ? "Capture saved"
                : "\(safeCount) captures saved"
        }
    }

    /// Combines rapid successful captures without losing any represented save.
    /// Addition saturates instead of overflowing during an unusually long burst.
    func merging(_ other: Self) -> Self {
        let mergedCount: Int
        if count > Int.max - other.count {
            mergedCount = Int.max
        } else {
            mergedCount = count + other.count
        }
        return Self(kind: kind.merging(other.kind), count: mergedCount)
    }
}

/// The complete live rotation requested for the robot's confirmation placard.
enum AutoCaptureSignReaction: String, CaseIterable, Identifiable, Sendable {
    case proudRaise = "proud-raise"
    case oversizedUnfold = "oversized-unfold"
    case heavyPullDown = "heavy-pull-down"
    case wrongSideFlip = "wrong-side-flip"
    case spinToFace = "spin-to-face"
    case gentleBonk = "gentle-bonk"
    case hangAndClimb = "hang-and-climb"
    case checkmarkStamp = "checkmark-stamp"
    case slideOvershoot = "slide-overshoot"
    case proudBow = "proud-bow"
    case mechanicalBillboard = "mechanical-billboard"
    case lastMomentCatch = "last-moment-catch"

    var id: String { rawValue }
    var testIdentifier: String { "auto-capture-sign-reaction-\(rawValue)" }

    var displayName: String {
        switch self {
        case .proudRaise: return "Proud Raise"
        case .oversizedUnfold: return "Oversized Unfold"
        case .heavyPullDown: return "Heavy Pull Down"
        case .wrongSideFlip: return "Wrong Side Flip"
        case .spinToFace: return "Spin to Face"
        case .gentleBonk: return "Gentle Bonk"
        case .hangAndClimb: return "Hang and Climb"
        case .checkmarkStamp: return "Checkmark Stamp"
        case .slideOvershoot: return "Slide Overshoot"
        case .proudBow: return "Proud Bow"
        case .mechanicalBillboard: return "Mechanical Billboard"
        case .lastMomentCatch: return "Last Moment Catch"
        }
    }

    fileprivate var baseDuration: TimeInterval {
        switch self {
        case .proudRaise: return 1.88
        case .oversizedUnfold: return 1.90
        case .heavyPullDown: return 1.92
        case .wrongSideFlip: return 1.88
        case .spinToFace: return 1.90
        case .gentleBonk: return 1.88
        case .hangAndClimb: return 1.92
        case .checkmarkStamp: return 1.88
        case .slideOvershoot: return 1.90
        case .proudBow: return 1.88
        case .mechanicalBillboard: return 1.91
        case .lastMomentCatch: return 1.92
        }
    }

    fileprivate var gazeBias: Double {
        switch self {
        case .proudRaise, .oversizedUnfold, .gentleBonk: return 0.12
        case .heavyPullDown, .hangAndClimb, .lastMomentCatch: return -0.12
        case .wrongSideFlip, .spinToFace, .mechanicalBillboard: return 0.08
        case .checkmarkStamp, .slideOvershoot, .proudBow: return -0.08
        }
    }

    fileprivate var isBurstFriendly: Bool {
        switch self {
        case .oversizedUnfold, .heavyPullDown, .mechanicalBillboard: return true
        default: return false
        }
    }
}

/// Semantic poses let the artwork renderer map motion onto the existing robot
/// without placing anatomy coordinates in the policy layer.
enum AutoCaptureSignArmPose: String, Equatable, Sendable {
    case rest
    case ledgeGrip
    case signHold
    case signRaise
    case brace
    case catchReach
    case hangGrip
    case stamp
    case present
    case bow
    case recover
}

/// One value-only sample in a performance track. Translations use native
/// logical points with +X right and +Y up. Sign translation is relative to the
/// neutral two-hand hold center. Rotations are degrees and scales are unitless.
struct AutoCaptureSignFrame: Equatable, Sendable {
    let normalizedTime: Double

    let robotTranslationX: Double
    let robotTranslationY: Double
    let robotScaleX: Double
    let robotScaleY: Double
    let robotRotationDegrees: Double
    let robotOpacity: Double

    let signTranslationX: Double
    let signTranslationY: Double
    let signScaleX: Double
    let signScaleY: Double
    let signRotationDegrees: Double
    let signYRotationDegrees: Double
    let signOpacity: Double

    let gazeX: Double
    let gazeY: Double
    let leftArmPose: AutoCaptureSignArmPose
    let rightArmPose: AutoCaptureSignArmPose
    let checkmarkProgress: Double

    fileprivate init(normalizedTime: Double,
                     robotTranslationX: Double = 0,
                     robotTranslationY: Double = 0,
                     robotScaleX: Double = 1,
                     robotScaleY: Double = 1,
                     robotRotationDegrees: Double = 0,
                     robotOpacity: Double = 1,
                     signTranslationX: Double = 0,
                     signTranslationY: Double = 0,
                     signScaleX: Double = 1,
                     signScaleY: Double = 1,
                     signRotationDegrees: Double = 0,
                     signYRotationDegrees: Double = 0,
                     signOpacity: Double = 1,
                     gazeX: Double = 0,
                     gazeY: Double = 0,
                     leftArmPose: AutoCaptureSignArmPose = .signHold,
                     rightArmPose: AutoCaptureSignArmPose = .signHold,
                     checkmarkProgress: Double = 0) {
        self.normalizedTime = Self.unit(normalizedTime)
        self.robotTranslationX = Self.finite(robotTranslationX)
        self.robotTranslationY = Self.finite(robotTranslationY)
        self.robotScaleX = Self.positive(robotScaleX)
        self.robotScaleY = Self.positive(robotScaleY)
        self.robotRotationDegrees = Self.finite(robotRotationDegrees)
        self.robotOpacity = Self.unit(robotOpacity)
        self.signTranslationX = Self.finite(signTranslationX)
        self.signTranslationY = Self.finite(signTranslationY)
        self.signScaleX = Self.positive(signScaleX)
        self.signScaleY = Self.positive(signScaleY)
        self.signRotationDegrees = Self.finite(signRotationDegrees)
        self.signYRotationDegrees = Self.finite(signYRotationDegrees)
        self.signOpacity = Self.unit(signOpacity)
        self.gazeX = Self.clamp(Self.finite(gazeX), lower: -1, upper: 1)
        self.gazeY = Self.clamp(Self.finite(gazeY), lower: -1, upper: 1)
        self.leftArmPose = leftArmPose
        self.rightArmPose = rightArmPose
        self.checkmarkProgress = Self.unit(checkmarkProgress)
    }

    private static func finite(_ value: Double) -> Double { value.isFinite ? value : 0 }
    private static func positive(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return max(0.001, value)
    }
    private static func unit(_ value: Double) -> Double {
        clamp(value.isFinite ? value : 0, lower: 0, upper: 1)
    }
    private static func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(upper, max(lower, value))
    }
}

/// A complete render plan. The renderer receives fixed keyframes and timing
/// boundaries; it never chooses a reaction or reads capture data while active.
struct AutoCaptureSignPerformance: Equatable, Sendable {
    let reaction: AutoCaptureSignReaction
    let variation: AutoCaptureRobotVariation
    let entrance: RobotEntrance
    let reduceMotion: Bool
    let frames: [AutoCaptureSignFrame]
    let totalDuration: TimeInterval
    let readableStartTime: TimeInterval
    let readableEndTime: TimeInterval
    let entranceEndTime: TimeInterval
    let exitStartTime: TimeInterval

    static func make(reaction: AutoCaptureSignReaction,
                     variation: AutoCaptureRobotVariation = .standard,
                     entrance: RobotEntrance,
                     reduceMotion: Bool) -> Self {
        if reduceMotion {
            let duration = 1.0 * variation.timingScale
            let gaze = clampedGaze(variation.gazeX + reaction.gazeBias)
            let frames = [
                frame(0, robotOpacity: 0, signOpacity: 0, gazeX: gaze),
                frame(0.16, robotOpacity: 1, signOpacity: 1, gazeX: gaze),
                frame(0.84, robotOpacity: 1, signOpacity: 1, gazeX: gaze),
                frame(1, robotOpacity: 0, signOpacity: 0, gazeX: gaze)
            ]
            return Self(reaction: reaction, variation: variation, entrance: entrance,
                        reduceMotion: true, frames: frames, totalDuration: duration,
                        readableStartTime: duration * 0.16,
                        readableEndTime: duration * 0.84,
                        entranceEndTime: duration * 0.16,
                        exitStartTime: duration * 0.84)
        }

        let duration = reaction.baseDuration * variation.timingScale
        let frames = normalFrames(reaction: reaction, variation: variation,
                                  entrance: entrance)
        return Self(reaction: reaction, variation: variation, entrance: entrance,
                    reduceMotion: false, frames: frames, totalDuration: duration,
                    readableStartTime: duration * 0.48,
                    readableEndTime: duration * 0.86,
                    entranceEndTime: duration * 0.28,
                    exitStartTime: duration * 0.86)
    }

    /// Deterministically samples the keyframe track. Numeric values ease into
    /// and out of every authored keyframe; semantic arm poses switch at the
    /// midpoint of a segment for renderers to blend between pose targets.
    func frame(atNormalizedTime normalizedTime: Double) -> AutoCaptureSignFrame {
        guard let first = frames.first, let last = frames.last else {
            return Self.frame(0, robotOpacity: 0, signOpacity: 0)
        }
        let time = normalizedTime.isFinite ? min(1, max(0, normalizedTime)) : 0
        if time <= first.normalizedTime { return first }
        if time >= last.normalizedTime { return last }

        for index in 1..<frames.count {
            let upper = frames[index]
            guard time <= upper.normalizedTime else { continue }
            let lower = frames[index - 1]
            let span = upper.normalizedTime - lower.normalizedTime
            let progress = span > 0 ? (time - lower.normalizedTime) / span : 1
            return Self.interpolate(from: lower, to: upper, progress: progress, time: time)
        }
        return last
    }

    private static func interpolate(from lower: AutoCaptureSignFrame,
                                    to upper: AutoCaptureSignFrame,
                                    progress: Double,
                                    time: Double) -> AutoCaptureSignFrame {
        let boundedProgress = min(1, max(0, progress))
        let easedProgress = boundedProgress * boundedProgress * (3 - (2 * boundedProgress))
        func value(_ first: Double, _ second: Double) -> Double {
            first + ((second - first) * easedProgress)
        }
        let useUpperPose = boundedProgress >= 0.5
        return AutoCaptureSignFrame(
            normalizedTime: time,
            robotTranslationX: value(lower.robotTranslationX, upper.robotTranslationX),
            robotTranslationY: value(lower.robotTranslationY, upper.robotTranslationY),
            robotScaleX: value(lower.robotScaleX, upper.robotScaleX),
            robotScaleY: value(lower.robotScaleY, upper.robotScaleY),
            robotRotationDegrees: value(lower.robotRotationDegrees, upper.robotRotationDegrees),
            robotOpacity: value(lower.robotOpacity, upper.robotOpacity),
            signTranslationX: value(lower.signTranslationX, upper.signTranslationX),
            signTranslationY: value(lower.signTranslationY, upper.signTranslationY),
            signScaleX: value(lower.signScaleX, upper.signScaleX),
            signScaleY: value(lower.signScaleY, upper.signScaleY),
            signRotationDegrees: value(lower.signRotationDegrees, upper.signRotationDegrees),
            signYRotationDegrees: value(lower.signYRotationDegrees, upper.signYRotationDegrees),
            signOpacity: value(lower.signOpacity, upper.signOpacity),
            gazeX: value(lower.gazeX, upper.gazeX),
            gazeY: value(lower.gazeY, upper.gazeY),
            leftArmPose: useUpperPose ? upper.leftArmPose : lower.leftArmPose,
            rightArmPose: useUpperPose ? upper.rightArmPose : lower.rightArmPose,
            checkmarkProgress: value(lower.checkmarkProgress, upper.checkmarkProgress)
        )
    }

    private static func normalFrames(reaction: AutoCaptureSignReaction,
                                     variation: AutoCaptureRobotVariation,
                                     entrance: RobotEntrance) -> [AutoCaptureSignFrame] {
        let entry: (x: Double, y: Double)
        switch entrance {
        case .top:
            entry = (variation.entranceOffset, 28)
        case .left:
            entry = (-34, variation.entranceOffset)
        case .right:
            entry = (34, variation.entranceOffset)
        }
        let gaze = clampedGaze(variation.gazeX + reaction.gazeBias)
        let gazeY = entrance == .top ? -0.16 : 0.04
        var result = [
            frame(0, robotX: entry.x, robotY: entry.y, robotScaleX: 0.96,
                  robotScaleY: 0.92, robotOpacity: 0, signScaleX: 0.72,
                  signScaleY: 0.72, signOpacity: 0, gazeX: gaze, gazeY: gazeY,
                  leftArm: .rest, rightArm: .rest),
            frame(0.08, robotX: entry.x * 0.72, robotY: entry.y * 0.72,
                  robotScaleX: 0.98, robotScaleY: 0.94, robotOpacity: 1,
                  signScaleX: 0.72, signScaleY: 0.72, signOpacity: 0,
                  gazeX: gaze, gazeY: gazeY, leftArm: .ledgeGrip,
                  rightArm: .ledgeGrip),
            frame(0.20, robotX: entry.x * 0.14, robotY: entry.y * 0.14,
                  robotScaleX: 1.03, robotScaleY: 0.97, robotRotation: -entry.x * 0.08,
                  signScaleX: 0.78, signScaleY: 0.78, signOpacity: 0,
                  gazeX: gaze, gazeY: gazeY, leftArm: .ledgeGrip,
                  rightArm: .ledgeGrip),
            frame(0.28, robotScaleX: 0.98, robotScaleY: 1.03,
                  signY: -4, signScaleX: 0.82, signScaleY: 0.82,
                  signOpacity: 1, gazeX: gaze, leftArm: .signHold,
                  rightArm: .signHold)
        ]
        result.append(contentsOf: reactionFrames(reaction, gaze: gaze))

        guard let hold = result.last else { return result }
        result.append(frame(0.89, robotX: entry.x * 0.18, robotY: entry.y * 0.18,
                            robotScaleX: 0.98, robotScaleY: 0.97,
                            robotRotation: entry.x * 0.05, robotOpacity: 1,
                            signX: hold.signTranslationX, signY: hold.signTranslationY,
                            signScaleX: hold.signScaleX, signScaleY: hold.signScaleY,
                            signRotation: hold.signRotationDegrees,
                            signYRotation: hold.signYRotationDegrees, signOpacity: 1,
                            gazeX: gaze * 0.5, leftArm: .recover, rightArm: .recover,
                            checkmark: hold.checkmarkProgress))
        result.append(frame(1, robotX: entry.x, robotY: entry.y,
                            robotScaleX: 0.96, robotScaleY: 0.92,
                            robotOpacity: 0, signX: hold.signTranslationX,
                            signY: hold.signTranslationY, signScaleX: hold.signScaleX,
                            signScaleY: hold.signScaleY,
                            signRotation: hold.signRotationDegrees,
                            signYRotation: hold.signYRotationDegrees, signOpacity: 0,
                            gazeX: gaze * 0.5, leftArm: .rest, rightArm: .rest,
                            checkmark: hold.checkmarkProgress))
        return result
    }

    private static func reactionFrames(_ reaction: AutoCaptureSignReaction,
                                       gaze: Double) -> [AutoCaptureSignFrame] {
        switch reaction {
        case .proudRaise:
            return [
                frame(0.30, robotY: -18, signY: 34, signScaleX: 0.9, signScaleY: 0.9,
                      signRotation: -4, gazeX: gaze, leftArm: .signRaise, rightArm: .signRaise),
                frame(0.38, robotY: -30, robotScaleX: 1.04, robotScaleY: 0.97, signY: 54,
                      signScaleX: 1.06, signScaleY: 1.06, signRotation: 3,
                      gazeX: gaze, gazeY: 0.2, leftArm: .signRaise, rightArm: .signRaise),
                frame(0.48, robotY: -30, signY: 58, gazeX: gaze, gazeY: 0.12,
                      leftArm: .signRaise, rightArm: .signRaise),
                frame(0.68, robotY: -30, signY: 58, gazeX: gaze * 0.6,
                      leftArm: .signRaise, rightArm: .signRaise),
                frame(0.84, robotY: -30, signY: 58, gazeX: gaze * 0.4,
                      leftArm: .signRaise, rightArm: .signRaise)
            ]
        case .oversizedUnfold:
            return [
                frame(0.30, signY: 47, signScaleX: 0.16, signScaleY: 0.88,
                      gazeX: gaze, leftArm: .brace, rightArm: .brace),
                frame(0.38, robotScaleX: 0.94, signY: 47,
                      signScaleX: 1.10, signScaleY: 1.68,
                      signRotation: -2, gazeX: gaze, leftArm: .brace, rightArm: .brace),
                frame(0.48,
                      gazeX: gaze, leftArm: .brace, rightArm: .brace),
                frame(0.68, gazeX: gaze * 0.5),
                frame(0.84, gazeX: gaze * 0.4)
            ]
        case .heavyPullDown:
            return [
                frame(0.30, robotY: -1, signY: 3, signRotation: 4,
                      gazeX: gaze, leftArm: .brace, rightArm: .brace),
                frame(0.38, robotY: -10, robotScaleX: 1.06, robotScaleY: 0.88,
                      robotRotation: -4, signY: -8, signScaleX: 1.1, signScaleY: 1.1,
                      signRotation: 7, gazeX: gaze, gazeY: -0.22,
                      leftArm: .brace, rightArm: .brace),
                frame(0.48, robotY: -2, robotScaleX: 0.98, robotScaleY: 1.04,
                      gazeX: gaze,
                      leftArm: .signHold, rightArm: .signHold),
                frame(0.68, gazeX: gaze * 0.5),
                frame(0.84, gazeX: gaze * 0.4)
            ]
        case .wrongSideFlip:
            return [
                frame(0.30, signYRotation: 180, gazeX: gaze,
                      leftArm: .signHold, rightArm: .signHold),
                frame(0.38, signScaleX: 0.2, signYRotation: 92,
                      gazeX: gaze, leftArm: .signHold, rightArm: .signHold),
                frame(0.48, gazeX: gaze, leftArm: .present, rightArm: .signHold),
                frame(0.68, gazeX: gaze * 0.5, leftArm: .present, rightArm: .signHold),
                frame(0.84, gazeX: gaze * 0.4)
            ]
        case .spinToFace:
            return [
                frame(0.30, signY: 8, signScaleX: 0.58, signScaleY: 0.58,
                      signRotation: 0, gazeX: gaze,
                      leftArm: .signHold, rightArm: .signHold),
                frame(0.32, signY: 8, signScaleX: 0.58, signScaleY: 0.58,
                      signRotation: 20, gazeX: gaze,
                      leftArm: .brace, rightArm: .brace),
                frame(0.34, signY: 8, signScaleX: 0.58, signScaleY: 0.58,
                      signRotation: 190, gazeX: gaze,
                      leftArm: .brace, rightArm: .brace),
                frame(0.38, signY: 8, signScaleX: 0.58, signScaleY: 0.58,
                      signRotation: 390, gazeX: gaze, leftArm: .brace, rightArm: .brace),
                frame(0.48, signRotation: 360, gazeX: gaze,
                      leftArm: .signHold, rightArm: .signHold),
                frame(0.68, signRotation: 360, gazeX: gaze * 0.5),
                frame(0.84, signRotation: 360, gazeX: gaze * 0.4)
            ]
        case .gentleBonk:
            return [
                frame(0.30, robotY: -24, signY: 50, signRotation: -5, gazeX: gaze,
                      leftArm: .signRaise, rightArm: .signRaise),
                frame(0.38, robotY: -30, robotScaleX: 1.06, robotScaleY: 0.9,
                      robotRotation: 5, signY: 50, signRotation: 7,
                      gazeX: gaze, gazeY: 0.28, leftArm: .brace, rightArm: .brace),
                frame(0.48, robotY: 1, robotScaleX: 0.98, robotScaleY: 1.03,
                      gazeX: gaze, leftArm: .signHold, rightArm: .signHold),
                frame(0.68, gazeX: gaze * 0.5),
                frame(0.84, gazeX: gaze * 0.4)
            ]
        case .hangAndClimb:
            return [
                frame(0.30, robotY: -18, signY: 34, gazeX: gaze,
                      leftArm: .hangGrip, rightArm: .hangGrip),
                frame(0.38, robotY: -40, robotScaleX: 0.94, robotScaleY: 1.08,
                      signY: 52, signRotation: -3, gazeX: gaze,
                      leftArm: .hangGrip, rightArm: .hangGrip),
                frame(0.48, robotY: -1, robotScaleX: 1.02, robotScaleY: 0.98,
                      signY: 2, gazeX: gaze, leftArm: .signHold, rightArm: .signHold),
                frame(0.68, signY: 2, gazeX: gaze * 0.5),
                frame(0.84, signY: 2, gazeX: gaze * 0.4)
            ]
        case .checkmarkStamp:
            return [
                frame(0.30, signRotation: -2, gazeX: gaze,
                      leftArm: .signHold, rightArm: .stamp),
                frame(0.38, robotRotation: 3, signScaleX: 1.04, signScaleY: 0.96,
                      gazeX: gaze, leftArm: .signHold, rightArm: .stamp,
                      checkmark: 0.35),
                frame(0.48, gazeX: gaze, leftArm: .signHold, rightArm: .stamp,
                      checkmark: 1),
                frame(0.68, gazeX: gaze * 0.5, leftArm: .present,
                      rightArm: .signHold, checkmark: 1),
                frame(0.84, gazeX: gaze * 0.4, checkmark: 1)
            ]
        case .slideOvershoot:
            return [
                frame(0.30, robotX: -18, robotRotation: -4, signX: -14,
                      gazeX: gaze, leftArm: .signHold, rightArm: .signHold),
                frame(0.38, robotX: 7, robotRotation: 3, signX: 6,
                      signRotation: 3, gazeX: gaze, leftArm: .brace, rightArm: .brace),
                frame(0.48, robotX: -2, signX: -1,
                      gazeX: gaze, leftArm: .signHold, rightArm: .signHold),
                frame(0.68, signX: -1, gazeX: gaze * 0.5),
                frame(0.84, signX: -1, gazeX: gaze * 0.4)
            ]
        case .proudBow:
            return [
                frame(0.30, signX: 4, signRotation: 3, gazeX: gaze,
                      leftArm: .present, rightArm: .signHold),
                frame(0.38, robotY: -3, robotScaleY: 0.94, robotRotation: 8,
                      signX: 7, signRotation: 5, gazeX: gaze, gazeY: -0.18,
                      leftArm: .present, rightArm: .bow),
                frame(0.48, robotY: 1, robotScaleY: 1.02, robotRotation: -2,
                      signX: 2, gazeX: gaze, leftArm: .present, rightArm: .signHold),
                frame(0.68, signX: 2, gazeX: gaze * 0.5,
                      leftArm: .present, rightArm: .signHold),
                frame(0.84, signX: 2, gazeX: gaze * 0.4)
            ]
        case .mechanicalBillboard:
            return [
                frame(0.30, signScaleX: 0.08, signScaleY: 0.88,
                      signYRotation: 70, gazeX: gaze, leftArm: .brace, rightArm: .brace),
                frame(0.38, signScaleX: 1.10, signScaleY: 1.08,
                      signYRotation: -8, gazeX: gaze, leftArm: .brace, rightArm: .brace),
                frame(0.48, gazeX: gaze, leftArm: .signHold, rightArm: .signHold),
                frame(0.68, gazeX: gaze * 0.5),
                frame(0.84, gazeX: gaze * 0.4)
            ]
        case .lastMomentCatch:
            return [
                frame(0.30, signY: 30, signRotation: 9, signOpacity: 0.9,
                      gazeX: gaze, gazeY: 0.3, leftArm: .catchReach, rightArm: .catchReach),
                frame(0.38, robotScaleX: 1.05, robotScaleY: 0.93,
                      signY: 5, signRotation: -7, gazeX: gaze,
                      leftArm: .catchReach, rightArm: .catchReach),
                frame(0.48, robotScaleX: 0.98, robotScaleY: 1.03,
                      signY: -1, gazeX: gaze,
                      leftArm: .signHold, rightArm: .signHold),
                frame(0.68, signY: -1, gazeX: gaze * 0.5),
                frame(0.84, signY: -1, gazeX: gaze * 0.4)
            ]
        }
    }

    private static func frame(_ time: Double,
                              robotX: Double = 0, robotY: Double = 0,
                              robotScaleX: Double = 1, robotScaleY: Double = 1,
                              robotRotation: Double = 0, robotOpacity: Double = 1,
                              signX: Double = 0, signY: Double = 0,
                              signScaleX: Double = 1, signScaleY: Double = 1,
                              signRotation: Double = 0, signYRotation: Double = 0,
                              signOpacity: Double = 1,
                              gazeX: Double = 0, gazeY: Double = 0,
                              leftArm: AutoCaptureSignArmPose = .signHold,
                              rightArm: AutoCaptureSignArmPose = .signHold,
                              checkmark: Double = 0) -> AutoCaptureSignFrame {
        AutoCaptureSignFrame(
            normalizedTime: time,
            robotTranslationX: robotX, robotTranslationY: robotY,
            robotScaleX: robotScaleX, robotScaleY: robotScaleY,
            robotRotationDegrees: robotRotation, robotOpacity: robotOpacity,
            signTranslationX: signX, signTranslationY: signY,
            signScaleX: signScaleX, signScaleY: signScaleY,
            signRotationDegrees: signRotation, signYRotationDegrees: signYRotation,
            signOpacity: signOpacity, gazeX: gazeX, gazeY: gazeY,
            leftArmPose: leftArm, rightArmPose: rightArm,
            checkmarkProgress: checkmark
        )
    }

    private static func clampedGaze(_ value: Double) -> Double {
        min(1, max(-1, value.isFinite ? value : 0))
    }
}

/// A seeded shuffled bag. Every bag contains all twelve reactions exactly once,
/// and no choice may repeat any of the three most recent performances.
struct AutoCaptureSignDeck: Sendable {
    private var generator: AutoCaptureSignSplitMix64
    private var remaining: [AutoCaptureSignReaction] = []
    private(set) var previousThree: [AutoCaptureSignReaction] = []

    init(seed: UInt64) {
        generator = AutoCaptureSignSplitMix64(seed: seed)
    }

    init() {
        var source = SystemRandomNumberGenerator()
        self.init(seed: source.next())
    }

    var remainingCount: Int { remaining.count }

    mutating func next(captureCount: Int = 1) -> AutoCaptureSignReaction {
        if remaining.isEmpty { refill() }

        if captureCount > 1,
           let burstIndex = remaining.firstIndex(where: {
               $0.isBurstFriendly && !previousThree.contains($0)
           }) {
            remaining.swapAt(0, burstIndex)
        }

        let index = remaining.firstIndex { !previousThree.contains($0) } ?? 0
        let reaction = remaining.remove(at: index)
        previousThree.append(reaction)
        if previousThree.count > 3 {
            previousThree.removeFirst(previousThree.count - 3)
        }
        return reaction
    }

    mutating func nextVariation() -> AutoCaptureRobotVariation {
        let timingValues = [0.96, 0.98, 1.0, 1.02, 1.04]
        let gazeValues = [-0.45, -0.24, 0.0, 0.24, 0.45]
        let offsetValues = [-2.0, -1.0, 0.0, 1.0, 2.0]
        return AutoCaptureRobotVariation(
            timingScale: timingValues[randomIndex(upperBound: timingValues.count)],
            gazeX: gazeValues[randomIndex(upperBound: gazeValues.count)],
            entranceOffset: offsetValues[randomIndex(upperBound: offsetValues.count)]
        )
    }

    mutating func nextPerformance(entrance: RobotEntrance,
                                  reduceMotion: Bool,
                                  captureCount: Int = 1) -> AutoCaptureSignPerformance {
        let reaction = next(captureCount: max(1, captureCount))
        return .make(reaction: reaction, variation: nextVariation(), entrance: entrance,
                     reduceMotion: reduceMotion)
    }

    private mutating func refill() {
        remaining = AutoCaptureSignReaction.allCases
        guard remaining.count > 1 else { return }
        for upper in stride(from: remaining.count - 1, through: 1, by: -1) {
            let index = randomIndex(upperBound: upper + 1)
            if index != upper { remaining.swapAt(index, upper) }
        }
    }

    private mutating func randomIndex(upperBound: Int) -> Int {
        precondition(upperBound > 0)
        return Int(generator.next() % UInt64(upperBound))
    }
}

private struct AutoCaptureSignSplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
