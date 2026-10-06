import Foundation

@main
private struct AutoCaptureSignMotionTests {
    private static var checks = 0

    private static func expect(_ condition: @autoclosure () -> Bool,
                               _ message: String) throws {
        checks += 1
        guard condition() else {
            throw NSError(domain: "DaBinAutoCaptureSignMotionTests", code: checks,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private static func near(_ first: Double, _ second: Double,
                             tolerance: Double = 0.000_001) -> Bool {
        abs(first - second) <= tolerance
    }

    static func main() throws {
        try checkReceipts()
        try checkReactionLibraryAndDeck()
        try checkCompanionActing()
        try checkNormalPerformances()
        try checkVisibleSignBounds()
        try checkReducedMotion()
        try checkExpressionOnlyContinuation()
        print("Auto capture sign motion checks passed: \(checks)")
    }

    private static func checkReceipts() throws {
        let screenshot = AutoCaptureSignReceipt(kind: .screenshot)
        try expect(screenshot.kind == .screenshot && screenshot.count == 1,
                   "A screenshot receipt starts with one represented save")
        try expect(screenshot.icon == "camera.viewfinder"
                   && screenshot.message == "Screenshot saved!"
                   && screenshot.accessibilityText == "Screenshot saved",
                   "Screenshot copy is fixed and accessible")

        let clipboard = AutoCaptureSignReceipt(kind: .clipboard, count: 3)
        try expect(clipboard.icon == "doc.on.clipboard.fill"
                   && clipboard.message == "Saved 3 items"
                   && clipboard.accessibilityText == "Saved 3 items",
                   "A clipboard burst shows its exact saved-item acknowledgement")

        let mixed = screenshot.merging(clipboard)
        try expect(mixed.kind == .mixed && mixed.count == 4,
                   "Different capture kinds merge into one accurate mixed receipt")
        try expect(mixed.icon == "square.stack.3d.up.fill"
                   && mixed.message == "Saved 4 items"
                   && mixed.accessibilityText == "Saved 4 items",
                   "A mixed receipt uses only fixed aggregate copy")

        let sameKind = AutoCaptureSignReceipt(kind: .screenshot, count: 2)
            .merging(AutoCaptureSignReceipt(kind: .screenshot, count: 5))
        try expect(sameKind.kind == .screenshot && sameKind.count == 7,
                   "Matching capture kinds remain specific when merged")
        try expect(AutoCaptureSignReceipt(kind: .clipboard, count: 0).count == 1
                   && AutoCaptureSignReceipt(kind: .clipboard, count: Int.min).count == 1,
                   "Receipt counts always remain positive")

        let saturated = AutoCaptureSignReceipt(kind: .screenshot, count: Int.max)
            .merging(AutoCaptureSignReceipt(kind: .clipboard, count: 2))
        try expect(saturated.kind == .mixed && saturated.count == Int.max,
                   "Burst aggregation saturates instead of overflowing")

        let fieldNames = Set(Mirror(reflecting: screenshot).children.compactMap(\.label))
        try expect(fieldNames == ["kind", "count", "icon", "message", "accessibilityText"],
                   "The receipt cannot carry filenames, copied text, app names or project labels")
    }

    private static func checkReactionLibraryAndDeck() throws {
        let reactions = AutoCaptureSignReaction.allCases
        try expect(reactions.count == 15, "The sign library preserves twelve historical and three companion gestures")
        try expect(Set(reactions.map(\.rawValue)).count == reactions.count
                   && Set(reactions.map(\.testIdentifier)).count == reactions.count,
                   "Every reaction has stable unique identifiers")
        try expect(reactions.allSatisfy { !$0.displayName.isEmpty },
                   "Every reaction has a readable diagnostic name")

        var firstDeck = AutoCaptureSignDeck(seed: 0x51_61_6E, reactions: reactions)
        var secondDeck = AutoCaptureSignDeck(seed: 0x51_61_6E, reactions: reactions)
        let first = (0..<(reactions.count * 10)).map { _ in firstDeck.next() }
        let second = (0..<(reactions.count * 10)).map { _ in secondDeck.next() }
        try expect(first == second, "A seed reproduces the complete shuffled rotation")

        for index in first.indices {
            let lower = max(first.startIndex, index - 3)
            try expect(!first[lower..<index].contains(first[index]),
                       "Reaction \(index) does not repeat any of its previous three")
        }
        for start in stride(from: 0, to: first.count, by: reactions.count) {
            let end = min(start + reactions.count, first.count)
            try expect(Set(first[start..<end]) == Set(reactions),
                       "Each shuffled bag emits every sign reaction exactly once")
        }
        try expect(firstDeck.previousThree == Array(first.suffix(3)),
                   "The deck retains exactly its three latest reactions")

        var burstDeck = AutoCaptureSignDeck(seed: 917)
        let burst = burstDeck.next(captureCount: 8)
        try expect(burst == .happyRaise,
                   "A fresh aggregate proudly raises its readable sign")
        var burstHistory = [burst]
        for _ in 0..<100 {
            let reaction = burstDeck.next(captureCount: 4)
            try expect(burstHistory.last != reaction,
                       "The three live gestures avoid an immediate repeat")
            burstHistory.append(reaction)
        }

        var performanceDeck = AutoCaptureSignDeck(seed: 0xA11CE)
        let performances = (0..<48).map { _ in
            performanceDeck.nextPerformance(entrance: .top, reduceMotion: false,
                                            captureCount: 1)
        }
        var matchingDeck = AutoCaptureSignDeck(seed: 0xA11CE)
        let matching = (0..<48).map { _ in
            matchingDeck.nextPerformance(entrance: .top, reduceMotion: false,
                                         captureCount: 1)
        }
        try expect(performances == matching,
                   "A seed reproduces complete reaction, timing and gaze plans")
        try expect(Set(performances.map { $0.variation.timingScale }).count > 1
                   && Set(performances.map { $0.variation.gazeX }).count > 1
                   && Set(performances.map { $0.variation.entranceOffset }).count > 1,
                   "Performances include bounded timing, gaze and entrance variation")
    }

    private static func checkNormalPerformances() throws {
        var distinctTracks: [[AutoCaptureSignFrame]] = []
        let timingScales = [AutoCaptureRobotVariation.timingRange.lowerBound,
                            AutoCaptureRobotVariation.timingRange.upperBound]

        for reaction in AutoCaptureSignReaction.allCases {
            for entrance in RobotEntrance.allCases {
                for timingScale in timingScales {
                    let variation = AutoCaptureRobotVariation(timingScale: timingScale,
                                                              gazeX: 0.32,
                                                              entranceOffset: 1.5)
                    let performance = AutoCaptureSignPerformance.make(
                        reaction: reaction, variation: variation,
                        entrance: entrance, reduceMotion: false
                    )
                    try expect(performance.reaction == reaction
                               && performance.variation == variation
                               && performance.entrance == entrance
                               && !performance.reduceMotion,
                               "A normal plan retains its complete selection inputs")
                    let durationBounds = reaction.isCompanionReaction ? 2.3...2.6 : 1.5...2.0
                    try expect(durationBounds.contains(performance.totalDuration),
                               "\(reaction.rawValue) keeps its complete gesture brief")
                    try expect(performance.entranceEndTime > 0
                               && performance.entranceEndTime < performance.readableStartTime
                               && performance.readableStartTime < performance.readableEndTime
                               && performance.readableEndTime <= performance.exitStartTime
                               && performance.exitStartTime < performance.totalDuration,
                               "Performance boundaries remain ordered")
                    try expect(performance.readableEndTime - performance.readableStartTime >= 0.5,
                               "The confirmation remains readable for at least half a second")

                    let frames = performance.frames
                    try expect(frames.count >= 8 && frames.first?.normalizedTime == 0
                               && frames.last?.normalizedTime == 1,
                               "Every normal plan has a complete keyframe track")
                    try expect(zip(frames, frames.dropFirst()).allSatisfy {
                        $0.normalizedTime < $1.normalizedTime
                    }, "Keyframes are strictly chronological")
                    try expect(frames.first?.robotOpacity == 0
                               && frames.first?.signOpacity == 0
                               && frames.last?.robotOpacity == 0
                               && frames.last?.signOpacity == 0
                               && frames.last?.leftArmPose == .rest
                               && frames.last?.rightArmPose == .rest,
                               "The track begins and ends fully cleaned up")
                    try expect(frames.allSatisfy(valid),
                               "All frame values are finite, bounded and renderable")

                    let before = performance.frame(atNormalizedTime: -50)
                    let after = performance.frame(atNormalizedTime: 50)
                    let notANumber = performance.frame(atNormalizedTime: .nan)
                    try expect(before == frames[0] && after == frames[frames.count - 1]
                               && notANumber == frames[0],
                               "Sampling clamps out-of-range and non-finite time safely")
                    let sample = performance.frame(atNormalizedTime: 0.47)
                    // The first authored segment fades from zero to full opacity
                    // over normalized time 0...0.08. Cubic smoothstep at one
                    // quarter and three quarters is 0.15625 and 0.84375.
                    let easedQuarter = performance.frame(atNormalizedTime: 0.02)
                    let easedThreeQuarters = performance.frame(atNormalizedTime: 0.06)
                    try expect(near(sample.normalizedTime, 0.47) && valid(sample)
                               && near(easedQuarter.robotOpacity, 0.15625)
                               && near(easedThreeQuarters.robotOpacity, 0.84375)
                               && easedQuarter.robotOpacity < 0.25
                               && easedThreeQuarters.robotOpacity > 0.75
                               && performance.frame(atNormalizedTime: 0.08) == frames[1],
                               "Intermediate sampling eases deterministically and preserves authored endpoints")
                    for step in 24...43 {
                        let readable = performance.frame(atNormalizedTime: Double(step) / 50)
                        let frontRotation = readable.signRotationDegrees
                            .truncatingRemainder(dividingBy: 360)
                        try expect(near(readable.signScaleX, 1)
                                   && near(readable.signScaleY, 1)
                                   && near(frontRotation, 0)
                                   && near(readable.signYRotationDegrees, 0)
                                   && near(readable.signOpacity, 1),
                                   "The whole declared reading interval keeps the sign front-facing")
                    }
                }
            }

            let standard = AutoCaptureSignPerformance.make(
                reaction: reaction, entrance: .top, reduceMotion: false
            )
            try expect(!distinctTracks.contains(standard.frames)
                       && namedReactionReadsClearly(standard),
                       "\(reaction.rawValue) has a distinct track whose authored pose matches its name")
            distinctTracks.append(standard.frames)
        }

        let stamped = AutoCaptureSignPerformance.make(
            reaction: .checkmarkStamp, entrance: .top, reduceMotion: false
        )
        try expect(stamped.frames.map(\.checkmarkProgress).max() == 1,
                   "The stamp reaction draws a complete checkmark")
        for reaction in AutoCaptureSignReaction.allCases where reaction != .checkmarkStamp {
            let plan = AutoCaptureSignPerformance.make(
                reaction: reaction, entrance: .top, reduceMotion: false
            )
            try expect(plan.frames.allSatisfy { $0.checkmarkProgress == 0 },
                       "Only the stamp reaction draws the animated checkmark")
        }
    }

    private static func checkReducedMotion() throws {
        for reaction in AutoCaptureSignReaction.allCases {
            for entrance in RobotEntrance.allCases {
                let performance = AutoCaptureSignPerformance.make(
                    reaction: reaction,
                    variation: AutoCaptureRobotVariation(timingScale: 1.04,
                                                         gazeX: 0.45,
                                                         entranceOffset: 2),
                    entrance: entrance,
                    reduceMotion: true
                )
                try expect(performance.reduceMotion && performance.totalDuration <= 1.1,
                           "Reduce Motion uses a short performance")
                try expect(performance.frames.count == 4
                           && performance.frames.map(\.robotOpacity) == [0, 1, 1, 0]
                           && performance.frames.map(\.signOpacity) == [0, 1, 1, 0],
                           "Reduce Motion is a static peek, readable hold and fade")
                try expect(performance.frames.allSatisfy { frame in
                    frame.robotTranslationX == 0 && frame.robotTranslationY == 0
                        && frame.robotScaleX == 1 && frame.robotScaleY == 1
                        && frame.robotRotationDegrees == 0
                        && frame.signTranslationX == 0 && frame.signTranslationY == 0
                        && frame.signScaleX == 1 && frame.signScaleY == 1
                        && frame.signRotationDegrees == 0 && frame.signYRotationDegrees == 0
                        && frame.leftArmPose == .signHold && frame.rightArmPose == .signHold
                        && frame.headRotationDegrees == 0 && frame.torsoScaleY == 1
                        && frame.feetTranslationY == 0 && frame.feetRotationDegrees == 0
                        && frame.eyeBrightness == 1.16
                }, "Reduce Motion removes climbing, travel, bounce, spin and overshoot")
                try expect(performance.readableEndTime > performance.readableStartTime
                           && performance.readableEndTime - performance.readableStartTime >= 0.65
                           && performance.exitStartTime == performance.readableEndTime,
                           "The reduced sign retains a readable static interval")
            }
        }
    }

    private static func checkExpressionOnlyContinuation() throws {
        let variation = AutoCaptureRobotVariation(timingScale: 1.02, gazeX: 0.24,
                                                  entranceOffset: -1)
        for reaction in AutoCaptureSignReaction.allCases {
            for entrance in RobotEntrance.allCases {
                let active = AutoCaptureSignPerformance.make(reaction: reaction,
                    variation: variation, entrance: entrance, reduceMotion: false)
                let reducedGaze = AutoCaptureSignPerformance.make(reaction: reaction,
                    variation: variation, entrance: entrance, reduceMotion: true).frames[0].gazeX
                for remaining in [0.08, 0.85, 2.15] {
                    let continuation = active.expressionOnly(remainingDuration: remaining)
                    try expect(continuation.reduceMotion && continuation.reaction == active.reaction
                               && continuation.variation == active.variation
                               && continuation.entrance == active.entrance
                               && continuation.totalDuration == remaining
                               && continuation.readableStartTime == 0
                               && continuation.readableEndTime == remaining
                               && continuation.entranceEndTime == 0
                               && continuation.exitStartTime == remaining,
                               "An active acknowledgement becomes static for precisely its remaining lifetime")
                    try expect(continuation.frames.count == 2
                               && continuation.frames.first?.normalizedTime == 0
                               && continuation.frames.last?.normalizedTime == 1,
                               "Expression-only continuation has no new entrance or exit phases")
                    for time in [-1.0, 0, 0.08, 0.5, 0.84, 1, 2] {
                        let frame = continuation.frame(atNormalizedTime: time)
                        try expect(valid(frame) && frame.robotOpacity == 1 && frame.signOpacity == 1
                                   && frame.robotTranslationX == 0 && frame.robotTranslationY == 0
                                   && frame.robotScaleX == 1 && frame.robotScaleY == 1
                                   && frame.robotRotationDegrees == 0
                                   && frame.signTranslationX == 0 && frame.signTranslationY == 0
                                   && frame.signScaleX == 1 && frame.signScaleY == 1
                                   && frame.signRotationDegrees == 0 && frame.signYRotationDegrees == 0
                                   && frame.headRotationDegrees == 0 && frame.torsoScaleY == 1
                                   && frame.feetTranslationY == 0 && frame.feetRotationDegrees == 0
                                   && frame.eyeBrightness == 1.16 && frame.gazeX == reducedGaze,
                                   "The static happy expression and sign remain fully visible at every sample")
                    }
                }
            }
        }
        let active = AutoCaptureSignPerformance.make(reaction: .happyNod, entrance: .top,
                                                     reduceMotion: false)
        for malformed in [-10.0, 0, .nan, .infinity, -.infinity] {
            let continuation = active.expressionOnly(remainingDuration: malformed)
            try expect(continuation.totalDuration == 0.001
                       && continuation.frames.allSatisfy { $0.robotOpacity == 1 && $0.signOpacity == 1 },
                       "Malformed remaining time cannot create a nonfinite, empty or invisible continuation")
        }
    }

    private static func namedReactionReadsClearly(_ performance: AutoCaptureSignPerformance) -> Bool {
        func authored(_ time: Double) -> AutoCaptureSignFrame? {
            performance.frames.first { near($0.normalizedTime, time) }
        }
        switch performance.reaction {
        case .proudRaise:
            guard let peak = authored(0.38), let hold = authored(0.68) else { return false }
            return peak.robotTranslationY <= -30 && peak.signTranslationY >= 54
                && hold.robotTranslationY <= -30 && hold.signTranslationY >= 58
        case .oversizedUnfold:
            guard let peak = authored(0.38) else { return false }
            return peak.signTranslationY >= 47 && peak.signScaleY >= 1.68
        case .gentleBonk:
            guard let preparation = authored(0.30), let impact = authored(0.38),
                  let recovery = authored(0.48) else { return false }
            return preparation.robotTranslationY <= -24 && preparation.signTranslationY >= 50
                && impact.robotTranslationY <= -30 && impact.signTranslationY >= 50
                && recovery.robotTranslationY >= 0 && abs(recovery.signTranslationY) <= 1
        case .hangAndClimb:
            guard let hang = authored(0.38) else { return false }
            return hang.robotTranslationY <= -40 && hang.signTranslationY >= 52
        default:
            return true
        }
    }

    private static func checkVisibleSignBounds() throws {
        // Matches the native 224×166 sign stage. The hardware notch occupies
        // x 40...184 above y 132, so visible plaque pixels must remain below
        // that lower edge. The neutral 190×32 plaque is centered at (112, 54).
        for reaction in AutoCaptureSignReaction.allCases {
            let performance = AutoCaptureSignPerformance.make(
                reaction: reaction,
                variation: .standard,
                entrance: .top,
                reduceMotion: false
            )
            var allSamplesFit = true
            for step in 0...1_000 {
                let frame = performance.frame(atNormalizedTime: Double(step) / 1_000)
                guard frame.signOpacity > 0.1 else { continue }
                let zRadians = frame.signRotationDegrees * .pi / 180
                let yRadians = frame.signYRotationDegrees * .pi / 180
                let halfWidth = 95 * frame.signScaleX * abs(cos(yRadians))
                let halfHeight = 16 * frame.signScaleY
                let extentX = abs(halfWidth * cos(zRadians)) + abs(halfHeight * sin(zRadians))
                let extentY = abs(halfWidth * sin(zRadians)) + abs(halfHeight * cos(zRadians))
                let centerX = 112 + frame.signTranslationX
                let centerY = 54 + frame.signTranslationY
                if centerX - extentX < -0.000_001 || centerX + extentX > 224.000_001
                    || centerY - extentY < -0.000_001 || centerY + extentY > 132.000_001 {
                    allSamplesFit = false
                    break
                }
            }
            try expect(allSamplesFit,
                       "\(reaction.rawValue) keeps every visible animated plaque sample inside the stage and below hardware")
        }
    }

    private static func valid(_ frame: AutoCaptureSignFrame) -> Bool {
        let values = [
            frame.normalizedTime,
            frame.robotTranslationX, frame.robotTranslationY,
            frame.robotScaleX, frame.robotScaleY, frame.robotRotationDegrees,
            frame.robotOpacity,
            frame.signTranslationX, frame.signTranslationY,
            frame.signScaleX, frame.signScaleY, frame.signRotationDegrees,
            frame.signYRotationDegrees, frame.signOpacity,
            frame.gazeX, frame.gazeY, frame.checkmarkProgress,
            frame.headRotationDegrees, frame.torsoScaleY, frame.feetTranslationY,
            frame.feetRotationDegrees, frame.eyeBrightness
        ]
        return values.allSatisfy(\.isFinite)
            && frame.robotScaleX > 0 && frame.robotScaleY > 0
            && frame.signScaleX > 0 && frame.signScaleY > 0
            && frame.torsoScaleY > 0 && (0.5...1.3).contains(frame.eyeBrightness)
            && (0...1).contains(frame.robotOpacity)
            && (0...1).contains(frame.signOpacity)
            && (-1...1).contains(frame.gazeX)
            && (-1...1).contains(frame.gazeY)
            && (0...1).contains(frame.checkmarkProgress)
    }

    private static func checkCompanionActing() throws {
        var deck = AutoCaptureSignDeck(seed: 0xC0_5A_6E)
        let rotation = (0..<90).map { _ in deck.next() }
        try expect(Set(rotation) == Set(AutoCaptureSignReaction.companionReactions),
                   "Live save reactions rotate only the small companion gestures")
        try expect(zip(rotation, rotation.dropFirst()).allSatisfy { $0 != $1 },
                   "Consecutive celebrations always alternate gestures")
        for start in stride(from: 0, to: rotation.count, by: 3) {
            try expect(Set(rotation[start..<(start + 3)]) == Set(AutoCaptureSignReaction.companionReactions),
                       "Every live bag includes a nod, wiggle and triumphant raise")
        }

        for reaction in AutoCaptureSignReaction.companionReactions {
            for entrance in RobotEntrance.allCases {
                let performance = AutoCaptureSignPerformance.make(reaction: reaction,
                    entrance: entrance, reduceMotion: false)
                let anticipation = performance.frame(atNormalizedTime: 0.20)
                let lift = performance.frame(atNormalizedTime: 0.28)
                let settle = performance.frame(atNormalizedTime: 0.84)
                try expect(anticipation.torsoScaleY < 1 && lift.torsoScaleY > 1
                           && lift.robotTranslationY > anticipation.robotTranslationY,
                           "The body takes weight before each small bounce")
                try expect(performance.frames.contains { $0.feetRotationDegrees < -8 }
                           && performance.frames.contains { $0.feetRotationDegrees > 8 }
                           && performance.frames.contains { $0.eyeBrightness >= 1.2 },
                           "Each save brightens the eyes and kicks the feet in both directions")
                try expect(settle.headRotationDegrees == 0 && settle.torsoScaleY == 1
                           && settle.feetTranslationY == 0 && settle.feetRotationDegrees == 0,
                           "Every gesture gently settles before slipping behind its edge")
                for step in 8...86 {
                    let frame = performance.frame(atNormalizedTime: Double(step) / 100)
                    try expect(frame.signScaleX == 1 && frame.signScaleY == 1
                               && frame.signRotationDegrees == 0 && frame.signYRotationDegrees == 0
                               && frame.signOpacity == 1,
                               "The acknowledgement stays upright and readable throughout the acting")
                }
                try expect(performance.mergeWindowDuration(maximumDuration: performance.totalDuration) > 1.5
                           && performance.readableEndTime - performance.mergeWindowDuration(
                            maximumDuration: performance.totalDuration) >= 0.299,
                           "Rapid saves blend into one sequence while leaving time to read the final count")
            }
        }
    }
}
