import Foundation

/// The complete success-reaction library for the passive Auto Capture robot.
/// Raw values are stable so render manifests and regression failures can name a
/// performance without depending on enum declaration order.
enum AutoCaptureRobotReaction: String, CaseIterable, Identifiable, Sendable {
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

    var id: String { rawValue }
    var testIdentifier: String { "auto-capture-reaction-\(rawValue)" }

    var displayName: String {
        switch self {
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

    /// The reaction is the flexible part of the performance. Anticipation,
    /// entrance and exit have fixed bases around this value.
    fileprivate var baseDuration: TimeInterval {
        switch self {
        case .sneakAndGrab: return 0.88
        case .savedStamp: return 0.94
        case .peekAndWink, .catchCapture: return 0.96
        case .doubleBounce: return 0.98
        case .cameraFlash: return 1.02
        case .screenHighFive: return 1.04
        case .clipboardHug: return 1.05
        case .wobblySalute: return 1.08
        case .victoryDance, .confettiSneeze: return 1.18
        case .dizzySpin: return 1.22
        }
    }
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
    case reaction(AutoCaptureRobotReaction)
    case exit
    case reducedPeek
    case successCheck
    case fade

    var id: String {
        switch self {
        case .anticipation: return "anticipation"
        case .entrance: return "entrance"
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
            (.anticipation, 0.26 * scale, .easeInOut, [.eyeMovement]),
            (.entrance, 0.44 * scale,
             .spring(response: 0.34 * scale, dampingFraction: 0.72),
             [.bodyTravel, .squashAndStretch, .overshoot]),
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
        // With twelve reactions and at most three exclusions, an eligible item
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
                                  reduceMotion: Bool) -> AutoCaptureRobotPerformance {
        let reaction = next()
        let variation = nextVariation()
        return .make(reaction: reaction, variation: variation,
                     entrance: entrance, reduceMotion: reduceMotion)
    }

    private mutating func refill() {
        remaining = AutoCaptureRobotReaction.allCases
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
