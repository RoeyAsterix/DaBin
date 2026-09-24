import Foundation

/// The complete success-reaction library for the passive Auto Capture robot.
/// Raw values are stable so render manifests and regression failures can name a
/// performance without depending on enum declaration order.
enum AutoCaptureRobotReaction: String, CaseIterable, Identifiable, Sendable {
    case quickBite = "quick-bite"
    case oversizedBite = "oversized-bite"
    case captureSlurp = "capture-slurp"
    case cornerNibble = "corner-nibble"
    case tossAndCatch = "toss-and-catch"
    case oversizedSwallow = "oversized-swallow"
    case escapingCapture = "escaping-capture"
    case suspiciousInspection = "suspicious-inspection"
    case stackedCapture = "stacked-capture"
    case digitalHiccups = "digital-hiccups"

    // Keep the original identifiers valid for saved render manifests. They now
    // include an eating sequence before their familiar celebration gesture.
    case peekAndWink = "peek-and-wink"
    case victoryDance = "victory-dance"
    case doubleBounce = "double-bounce"
    case cameraFlash = "camera-flash"
    case catchCapture = "catch-capture"
    case clipboardHug = "clipboard-hug"
    case dizzySpin = "dizzy-spin"
    case wobblySalute = "wobbly-salute"
    case savedStamp = "saved-stamp"
    case confettiSneeze = "confetti-sneeze"
    case screenHighFive = "screen-high-five"
    case sneakAndGrab = "sneak-and-grab"

    /// Only these ten distinct eating styles participate in live rotation.
    /// Legacy identifiers remain available to callers and historical QA fixtures.
    static let eatingReactions: [AutoCaptureRobotReaction] = [
        .quickBite, .oversizedBite, .captureSlurp, .cornerNibble, .tossAndCatch,
        .oversizedSwallow, .escapingCapture, .suspiciousInspection, .stackedCapture, .digitalHiccups
    ]

    var id: String { rawValue }
    var testIdentifier: String { "auto-capture-reaction-\(rawValue)" }

    var displayName: String {
        switch self {
        case .quickBite: return "Quick Bite and Satisfied Blink"
        case .oversizedBite: return "Oversized Bite and Recoil"
        case .captureSlurp: return "Capture Noodle Slurp"
        case .cornerNibble: return "Nibble the Corners"
        case .tossAndCatch: return "Toss and Mouth Catch"
        case .oversizedSwallow: return "Oversized Swallow"
        case .escapingCapture: return "Chase the Escaping Capture"
        case .suspiciousInspection: return "Suspicious Inspection"
        case .stackedCapture: return "Stacked Capture Snack"
        case .digitalHiccups: return "Digital Hiccups"
        case .peekAndWink: return "Peek and Wink"
        case .victoryDance: return "Victory Dance"
        case .doubleBounce: return "Double Bounce"
        case .cameraFlash: return "Camera Flash"
        case .catchCapture: return "Catch Capture"
        case .clipboardHug: return "Clipboard Hug"
        case .dizzySpin: return "Dizzy Spin"
        case .wobblySalute: return "Wobbly Salute"
        case .savedStamp: return "Saved Stamp"
        case .confettiSneeze: return "Confetti Sneeze"
        case .screenHighFive: return "Screen High Five"
        case .sneakAndGrab: return "Sneak and Grab"
        }
    }

    var eatingStyle: AutoCaptureEatingStyle {
        switch self {
        case .quickBite, .peekAndWink, .savedStamp: return .bite
        case .oversizedBite, .cameraFlash: return .recoil
        case .captureSlurp: return .slurp
        case .cornerNibble, .clipboardHug: return .nibble
        case .tossAndCatch, .doubleBounce, .screenHighFive: return .toss
        case .oversizedSwallow, .wobblySalute: return .swallow
        case .escapingCapture, .sneakAndGrab: return .chase
        case .suspiciousInspection: return .inspect
        case .stackedCapture, .catchCapture: return .stack
        case .digitalHiccups, .confettiSneeze, .victoryDance, .dizzySpin: return .hiccup
        }
    }

    fileprivate var eatingDuration: TimeInterval {
        switch eatingStyle {
        case .bite, .recoil: return 0.82
        case .slurp, .nibble, .stack, .hiccup: return 0.89
        case .toss, .swallow, .chase, .inspect: return 0.96
        }
    }

    fileprivate var baseDuration: TimeInterval { 0.38 }

}

/// Small bounded differences prevent consecutive performances from feeling
/// mechanical without changing their overall pace or leaving the island area.
struct AutoCaptureRobotVariation: Equatable, Sendable {
    static let timingRange: ClosedRange<Double> = 0.96...1.04
    static let gazeRange: ClosedRange<Double> = -0.45...0.45
    static let entranceOffsetRange: ClosedRange<Double> = -2.0...2.0
    static let standard = AutoCaptureRobotVariation(timingScale: 1, gazeX: 0,
                                                     entranceOffset: 0)

    let timingScale: Double
    let gazeX: Double
    let entranceOffset: Double

    init(timingScale: Double, gazeX: Double, entranceOffset: Double) {
        self.timingScale = Self.clamp(timingScale, to: Self.timingRange)
        self.gazeX = Self.clamp(gazeX, to: Self.gazeRange)
        self.entranceOffset = Self.clamp(entranceOffset, to: Self.entranceOffsetRange)
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        guard value.isFinite else {
            if value == -.infinity { return range.lowerBound }
            if value == .infinity { return range.upperBound }
            return (range.lowerBound + range.upperBound) / 2
        }
        return min(range.upperBound, max(range.lowerBound, value))
    }
}

enum AutoCaptureRobotTimingCurve: Equatable, Sendable {
    case easeInOut
    case easeOut
    case spring(response: Double, dampingFraction: Double)
}

enum AutoCaptureRobotPhaseKind: Equatable, Sendable {
    case anticipation
    case entrance
    case eating(AutoCaptureRobotReaction)
    case reaction(AutoCaptureRobotReaction)
    case exit
    case reducedPeek
    case successCheck
    case fade

    var id: String {
        switch self {
        case .anticipation: return "anticipation"
        case .entrance: return "entrance"
        case .eating(let reaction): return "eating-\(reaction.rawValue)"
        case .reaction(let reaction): return "reaction-\(reaction.rawValue)"
        case .exit: return "exit"
        case .reducedPeek: return "reduced-peek"
        case .successCheck: return "success-check"
        case .fade: return "fade"
        }
    }
}

/// Semantic effects keep timing policy independently testable while the layer
/// renderer remains free to adapt each move to the existing robot anatomy.
struct AutoCaptureRobotPhaseEffects: OptionSet, Equatable, Sendable {
    let rawValue: UInt8

    static let eyeMovement = Self(rawValue: 1 << 0)
    static let bodyTravel = Self(rawValue: 1 << 1)
    static let squashAndStretch = Self(rawValue: 1 << 2)
    static let overshoot = Self(rawValue: 1 << 3)
    static let successCue = Self(rawValue: 1 << 4)
    static let opacity = Self(rawValue: 1 << 5)
    static let captureToken = Self(rawValue: 1 << 6)
    static let eating = Self(rawValue: 1 << 7)
}

struct AutoCaptureRobotPerformancePhase: Equatable, Identifiable, Sendable {
    let kind: AutoCaptureRobotPhaseKind
    let startTime: TimeInterval
    let duration: TimeInterval
    let timingCurve: AutoCaptureRobotTimingCurve
    let effects: AutoCaptureRobotPhaseEffects

    var id: String { kind.id }
    var endTime: TimeInterval { startTime + duration }
}

/// A complete value-only performance plan. Rendering code can schedule these
/// phases without choosing reactions, deriving durations or querying global
/// accessibility state during the sequence.
struct AutoCaptureRobotPerformance: Equatable, Sendable {
    let reaction: AutoCaptureRobotReaction
    let variation: AutoCaptureRobotVariation
    let entrance: RobotEntrance
    let reduceMotion: Bool
    let phases: [AutoCaptureRobotPerformancePhase]
    let totalDuration: TimeInterval

    static func make(reaction: AutoCaptureRobotReaction,
                     variation: AutoCaptureRobotVariation = .standard,
                     entrance: RobotEntrance,
                     reduceMotion: Bool) -> AutoCaptureRobotPerformance {
        if reduceMotion {
            let phases = timeline([
                (.reducedPeek, 0.20, .easeOut, [.eyeMovement, .opacity]),
                (.successCheck, 0.32, .easeInOut, [.successCue]),
                (.fade, 0.22, .easeOut, [.opacity])
            ])
            return AutoCaptureRobotPerformance(reaction: reaction, variation: variation,
                                               entrance: entrance, reduceMotion: true,
                                               phases: phases,
                                               totalDuration: phases.last?.endTime ?? 0)
        }

        let scale = variation.timingScale
        let phases = timeline([
            (.anticipation, 0.23 * scale, .easeInOut, [.eyeMovement]),
            (.entrance, 0.50 * scale,
             .spring(response: 0.34 * scale, dampingFraction: 0.72),
             [.bodyTravel, .squashAndStretch, .overshoot]),
            (.eating(reaction), reaction.eatingDuration * scale,
             .spring(response: 0.30 * scale, dampingFraction: 0.78),
             [.eyeMovement, .squashAndStretch, .captureToken, .eating]),
            (.reaction(reaction), reaction.baseDuration * scale,
             .spring(response: 0.38 * scale, dampingFraction: 0.76),
             [.eyeMovement, .squashAndStretch, .overshoot, .successCue]),
            (.exit, 0.40 * scale,
             .spring(response: 0.31 * scale, dampingFraction: 0.78),
             [.bodyTravel, .squashAndStretch, .overshoot])
        ])
        return AutoCaptureRobotPerformance(reaction: reaction, variation: variation,
                                           entrance: entrance, reduceMotion: false,
                                           phases: phases,
                                           totalDuration: phases.last?.endTime ?? 0)
    }

    private static func timeline(_ descriptions: [(AutoCaptureRobotPhaseKind, TimeInterval,
                                                    AutoCaptureRobotTimingCurve,
                                                    AutoCaptureRobotPhaseEffects)])
        -> [AutoCaptureRobotPerformancePhase] {
        var cursor: TimeInterval = 0
        return descriptions.map { kind, duration, curve, effects in
            let phase = AutoCaptureRobotPerformancePhase(kind: kind, startTime: cursor,
                                                         duration: duration,
                                                         timingCurve: curve, effects: effects)
            cursor = phase.endTime
            return phase
        }
    }
}

/// Shuffled-bag reaction selection. Each bag contains every reaction exactly
/// once, and boundary picks skip anything seen in the previous three results.
/// An explicit seed gives tests and recorded QA runs reproducible sequences.
struct AutoCaptureRobotReactionDeck: Sendable {
    private var generator: AutoCaptureRobotSplitMix64
    private var remaining: [AutoCaptureRobotReaction] = []
    private(set) var previousThree: [AutoCaptureRobotReaction] = []

    init(seed: UInt64) {
        generator = AutoCaptureRobotSplitMix64(seed: seed)
    }

    init() {
        var source = SystemRandomNumberGenerator()
        self.init(seed: source.next())
    }

    var remainingCount: Int { remaining.count }

    mutating func next() -> AutoCaptureRobotReaction {
        if remaining.isEmpty { refill() }
        // With more than three reactions and at most three exclusions, an eligible item
        // always exists. Within a bag, already-seen items have already been removed.
        let index = remaining.firstIndex { !previousThree.contains($0) } ?? 0
        let reaction = remaining.remove(at: index)
        previousThree.append(reaction)
        if previousThree.count > 3 { previousThree.removeFirst(previousThree.count - 3) }
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
                                  captureCount: Int = 1) -> AutoCaptureRobotPerformance {
        // Prefer a stack for a burst only when that pick obeys the same deck and
        // recent-history rules. Updating an active token never makes a new pick.
        if remaining.isEmpty { refill() }
        if captureCount > 1, !previousThree.contains(.stackedCapture),
           let index = remaining.firstIndex(of: .stackedCapture) {
            remaining.swapAt(0, index)
        }
        let reaction = next()
        let variation = nextVariation()
        return .make(reaction: reaction, variation: variation,
                     entrance: entrance, reduceMotion: reduceMotion)
    }

    private mutating func refill() {
        remaining = AutoCaptureRobotReaction.eatingReactions
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

/// Small deterministic generator used only for local animation choice. It is
/// intentionally unrelated to capture data and is not a security primitive.
private struct AutoCaptureRobotSplitMix64: RandomNumberGenerator, Sendable {
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

/// Value-only token choreography shared by the layer renderer and unit tests.
/// Coordinates are in the robot's 64 × 78 design space relative to its mouth;
/// these are generic paper tokens and cannot carry capture content.
enum AutoCaptureEatingStyle: String, CaseIterable, Sendable {
    case bite, recoil, slurp, nibble, toss, swallow, chase, inspect, stack, hiccup

    struct TokenKeyframe: Equatable, Sendable {
        let fraction: Double
        let x: Double
        let y: Double
        let scaleX: Double
        let scaleY: Double
        let rotation: Double

        init(_ fraction: Double, _ x: Double, _ y: Double,
             _ scaleX: Double = 1, _ scaleY: Double = 1, _ rotation: Double = 0) {
            self.fraction = fraction
            self.x = x
            self.y = y
            self.scaleX = scaleX
            self.scaleY = scaleY
            self.rotation = rotation
        }
    }

    /// Every path finishes inside the mouth with the paper folded to nothing.
    var tokenKeyframes: [TokenKeyframe] {
        typealias K = TokenKeyframe
        let swallowed = K(0.94, 0, 0, 0.04, 0.04)
        switch self {
        case .bite:
            return [K(0, 25, -20, 1, 1, -12), K(0.36, 9, -1),
                    K(0.60, 2, 0, 0.65, 0.8), swallowed]
        case .recoil:
            return [K(0, 27, -16, 1.7, 1.5, 12), K(0.32, 12, 1, 1.7, 1.5),
                    K(0.53, -2, -1, 0.9, 0.8, -9), swallowed]
        case .slurp:
            return [K(0, 26, 6, 1.8, 0.25, -8), K(0.28, 17, 3, 2.3, 0.18),
                    K(0.55, 8, 1, 1.4, 0.12), K(0.80, 2, 0, 0.4, 0.1), swallowed]
        case .nibble:
            return [K(0, 18, -18), K(0.24, 7, 0, 1, 1, 28),
                    K(0.42, 10, 0, 0.85, 0.85, -28), K(0.61, 6, 0, 0.65, 0.65, 28),
                    K(0.79, 3, 0, 0.45, 0.45, -20), swallowed]
        case .toss:
            return [K(0, 22, 2, 1, 1, 10), K(0.22, 13, 3, 1, 1, -18),
                    K(0.47, 1, -34, 0.9, 0.9, 145), K(0.66, -2, -24, 0.8, 0.8, 240),
                    K(0.82, 0, -3, 0.65, 0.65, 350), swallowed]
        case .swallow:
            return [K(0, 27, -14, 1.8, 1.8), K(0.32, 9, 1, 1.6, 1.5),
                    K(0.49, 6, 0, 1.1, 1.5, -8), K(0.63, 6, -1, 0.9, 1.1, 8),
                    K(0.77, 3, 0, 0.65, 0.65), swallowed]
        case .chase:
            return [K(0, 16, -15, 1, 1, -12), K(0.23, 9, 0, 1, 1, 8),
                    K(0.42, 29, -10, 0.9, 0.9, 18), K(0.59, 23, 2, 0.9, 0.9, -12),
                    K(0.78, 3, 0, 0.65, 0.65), swallowed]
        case .inspect:
            return [K(0, 25, -18, 1, 1, 8), K(0.23, 13, -8, 1, 1, -14),
                    K(0.49, 13, -8, 1, 1, 14), K(0.65, 11, -6, 1, 1, -8), swallowed]
        case .stack:
            return [K(0, 23, -18, 1.2, 1.2, -10), K(0.28, 10, 0, 1.2, 1.2),
                    K(0.47, 7, 0, 1, 0.75), K(0.64, 4, 0, 0.7, 0.48),
                    K(0.81, 2, 0, 0.4, 0.25), swallowed]
        case .hiccup:
            return [K(0, 22, -20, 1, 1, 12), K(0.30, 8, 0),
                    K(0.51, 1, 0, 0.4, 0.4), K(0.65, 5, -4, 0.6, 0.6, -16),
                    K(0.80, 1, 0, 0.3, 0.3), swallowed]
        }
    }
}
