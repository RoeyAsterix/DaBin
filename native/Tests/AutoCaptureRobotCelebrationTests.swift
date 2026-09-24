import Foundation

@main
private struct AutoCaptureRobotCelebrationTests {
    private static var checks = 0

    private static func expect(_ condition: @autoclosure () -> Bool,
                               _ message: String) throws {
        checks += 1
        guard condition() else {
            throw NSError(domain: "DaBinAutoCaptureRobotCelebrationTests", code: checks,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private static func near(_ first: Double, _ second: Double,
                             tolerance: Double = 0.000_001) -> Bool {
        abs(first - second) <= tolerance
    }

    static func main() throws {
        let reactions = AutoCaptureRobotReaction.allCases
        try expect(reactions.count >= 12, "The success library contains at least twelve reactions")
        try expect(Set(reactions.map(\.rawValue)).count == reactions.count,
                   "Every reaction has a unique stable identifier")
        try expect(Set(reactions.map(\.testIdentifier)).count == reactions.count,
                   "Every reaction has a unique test identifier")
        try expect(reactions.allSatisfy { !$0.displayName.isEmpty },
                   "Every reaction has a readable diagnostic name")

        var firstDeck = AutoCaptureRobotReactionDeck(seed: 0xDA_B1_2026)
        var secondDeck = AutoCaptureRobotReactionDeck(seed: 0xDA_B1_2026)
        let firstSequence = (0..<120).map { _ in firstDeck.next() }
        let secondSequence = (0..<120).map { _ in secondDeck.next() }
        try expect(firstSequence == secondSequence,
                   "An explicit seed reproduces the shuffled reaction rotation")

        for index in firstSequence.indices {
            let lower = max(firstSequence.startIndex, index - 3)
            let prior = firstSequence[lower..<index]
            try expect(!prior.contains(firstSequence[index]),
                       "Reaction \(index) does not repeat any of its previous three")
        }
        for start in stride(from: 0, to: firstSequence.count, by: reactions.count) {
            let end = min(start + reactions.count, firstSequence.count)
            try expect(Set(firstSequence[start..<end]) == Set(reactions),
                       "Each shuffled bag emits every reaction exactly once")
        }
        try expect(firstDeck.previousThree == Array(firstSequence.suffix(3)),
                   "The deck exposes only its three most recent reactions")

        var variationDeck = AutoCaptureRobotReactionDeck(seed: 0x5151)
        let performances = (0..<36).map { _ in
            variationDeck.nextPerformance(entrance: .top, reduceMotion: false)
        }
        var matchingPerformanceDeck = AutoCaptureRobotReactionDeck(seed: 0x5151)
        let matchingPerformances = (0..<36).map { _ in
            matchingPerformanceDeck.nextPerformance(entrance: .top, reduceMotion: false)
        }
        try expect(performances == matchingPerformances,
                   "The seed reproduces complete reaction and variation plans")
        for index in performances.indices {
            let lower = max(performances.startIndex, index - 3)
            let prior = performances[lower..<index].map(\.reaction)
            try expect(!prior.contains(performances[index].reaction),
                       "Variation generation does not weaken the prior-three exclusion")
        }
        let variations = performances.map(\.variation)
        try expect(Set(variations.map(\.timingScale)).count > 1
                   && Set(variations.map(\.gazeX)).count > 1
                   && Set(variations.map(\.entranceOffset)).count > 1,
                   "Seeded performances still vary timing, gaze and entrance offset")
        try expect(variations.allSatisfy {
            AutoCaptureRobotVariation.timingRange.contains($0.timingScale)
                && AutoCaptureRobotVariation.gazeRange.contains($0.gazeX)
                && AutoCaptureRobotVariation.entranceOffsetRange.contains($0.entranceOffset)
        }, "Every generated variation stays inside the subtle-motion bounds")

        let clamped = AutoCaptureRobotVariation(timingScale: 50, gazeX: -.infinity,
                                                entranceOffset: .nan)
        try expect(clamped.timingScale == AutoCaptureRobotVariation.timingRange.upperBound
                   && clamped.gazeX == AutoCaptureRobotVariation.gazeRange.lowerBound
                   && clamped.entranceOffset == 0,
                   "Direct variations safely clamp extreme and non-finite inputs")

        let scales = [AutoCaptureRobotVariation.timingRange.lowerBound,
                      AutoCaptureRobotVariation.timingRange.upperBound]
        for reaction in reactions {
            for scale in scales {
                let variation = AutoCaptureRobotVariation(timingScale: scale, gazeX: 0.3,
                                                          entranceOffset: -1)
                let performance = AutoCaptureRobotPerformance.make(
                    reaction: reaction, variation: variation, entrance: .top,
                    reduceMotion: false
                )
                try expect(performance.reaction == reaction && performance.entrance == .top
                           && !performance.reduceMotion,
                           "A normal plan retains its reaction, variation and entrance")
                try expect(performance.phases.map(\.kind) == [
                    .anticipation, .entrance, .reaction(reaction), .exit
                ], "\(reaction.rawValue) follows anticipation, entrance, reaction and exit")
                try expect((1.8...2.6).contains(performance.totalDuration),
                           "\(reaction.rawValue) remains inside the requested duration at scale \(scale)")
                try expect(performance.phases.allSatisfy { $0.duration > 0 },
                           "Every normal phase has positive duration")
                for (index, phase) in performance.phases.enumerated() {
                    let expectedStart = index == 0 ? 0 : performance.phases[index - 1].endTime
                    try expect(near(phase.startTime, expectedStart),
                               "Normal phases form a contiguous non-overlapping timeline")
                }
                try expect(near(performance.totalDuration,
                                performance.phases.reduce(0) { $0 + $1.duration }),
                           "The reported total equals the normal phase durations")

                let anticipation = performance.phases[0]
                let entrance = performance.phases[1]
                let reactionPhase = performance.phases[2]
                let exit = performance.phases[3]
                try expect(anticipation.effects.contains(.eyeMovement)
                           && !anticipation.effects.contains(.bodyTravel),
                           "Anticipation moves the eyes before the body emerges")
                try expect(entrance.effects.isSuperset(of: [.bodyTravel, .squashAndStretch, .overshoot])
                           && exit.effects.isSuperset(of: [.bodyTravel, .squashAndStretch, .overshoot]),
                           "Entrance and exit encode travel, squash-and-stretch and overshoot")
                try expect(reactionPhase.effects.contains(.successCue)
                           && reactionPhase.kind == .reaction(reaction),
                           "Every library reaction is an explicit success cue")
                if case .spring = entrance.timingCurve {} else {
                    try expect(false, "Entrance uses spring easing")
                }
                if case .spring = exit.timingCurve {} else {
                    try expect(false, "Exit uses spring easing")
                }
            }
        }

        let normalPlans = reactions.map {
            AutoCaptureRobotPerformance.make(reaction: $0, variation: .standard,
                                             entrance: .top, reduceMotion: false)
        }
        try expect(Set(normalPlans.map { $0.phases[2].kind.id }).count == reactions.count,
                   "Every reaction produces a distinguishable performance phase")

        for entrance in RobotEntrance.allCases {
            let reduced = AutoCaptureRobotPerformance.make(
                reaction: .victoryDance,
                variation: AutoCaptureRobotVariation(timingScale: 1.04, gazeX: 0.45,
                                                     entranceOffset: 2),
                entrance: entrance,
                reduceMotion: true
            )
            try expect(reduced.phases.map(\.kind) == [.reducedPeek, .successCheck, .fade],
                       "Reduce Motion uses only peek, check and fade")
            try expect(reduced.totalDuration > 0 && reduced.totalDuration <= 0.9,
                       "The reduced performance is brief")
            try expect(!reduced.phases.contains { phase in
                phase.effects.contains(.bodyTravel)
                    || phase.effects.contains(.squashAndStretch)
                    || phase.effects.contains(.overshoot)
                    || {
                        if case .spring = phase.timingCurve { return true }
                        return false
                    }()
            }, "Reduce Motion removes travel, squash, overshoot and spring movement")
            try expect(reduced.phases[0].effects.contains(.eyeMovement)
                       && reduced.phases[1].effects.contains(.successCue)
                       && reduced.phases[2].effects.contains(.opacity),
                       "The reduced plan preserves a readable peek, success check and fade")
            for (index, phase) in reduced.phases.enumerated() {
                let expectedStart = index == 0 ? 0 : reduced.phases[index - 1].endTime
                try expect(near(phase.startTime, expectedStart),
                           "Reduced phases form a contiguous non-overlapping timeline")
            }
            try expect(near(reduced.totalDuration,
                            reduced.phases.reduce(0) { $0 + $1.duration }),
                       "The reduced total equals its contiguous phase durations")
        }

        print("PASS: \(checks) auto-capture celebration rotation and performance checks")
    }
}
