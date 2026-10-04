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
        try checkNormalPerformances()
        try checkVisibleSignBounds()
        try checkReducedMotion()
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
                   && clipboard.message == "Copied!"
                   && clipboard.accessibilityText == "3 clipboard captures saved",
                   "Clipboard copy remains concise while accessibility reports the burst")

        let mixed = screenshot.merging(clipboard)
        try expect(mixed.kind == .mixed && mixed.count == 4,
                   "Different capture kinds merge into one accurate mixed receipt")
        try expect(mixed.icon == "square.stack.3d.up.fill"
                   && mixed.message == "Captures saved!"
                   && mixed.accessibilityText == "4 captures saved",
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
        try expect(reactions.count == 12, "The sign library contains all twelve requested reactions")
        try expect(Set(reactions.map(\.rawValue)).count == 12
                   && Set(reactions.map(\.testIdentifier)).count == 12,
                   "Every reaction has stable unique identifiers")
        try expect(reactions.allSatisfy { !$0.displayName.isEmpty },
                   "Every reaction has a readable diagnostic name")

        var firstDeck = AutoCaptureSignDeck(seed: 0x51_61_6E)
        var secondDeck = AutoCaptureSignDeck(seed: 0x51_61_6E)
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
        try expect([.oversizedUnfold, .heavyPullDown, .mechanicalBillboard].contains(burst),
                   "A fresh aggregate uses a reaction suited to multiple captures")
        var burstHistory = [burst]
        for _ in 0..<100 {
            let reaction = burstDeck.next(captureCount: 4)
            try expect(!burstHistory.suffix(3).contains(reaction),
                       "Burst-friendly selection preserves the previous-three exclusion")
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
                    try expect((1.5...2.0).contains(performance.totalDuration),
                               "\(reaction.rawValue) remains within the 1.5–2 second target")
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
                }, "Reduce Motion removes climbing, travel, bounce, spin and overshoot")
                try expect(performance.readableEndTime > performance.readableStartTime
                           && performance.readableEndTime - performance.readableStartTime >= 0.65
                           && performance.exitStartTime == performance.readableEndTime,
                           "The reduced sign retains a readable static interval")
            }
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
            frame.gazeX, frame.gazeY, frame.checkmarkProgress
        ]
        return values.allSatisfy(\.isFinite)
            && frame.robotScaleX > 0 && frame.robotScaleY > 0
            && frame.signScaleX > 0 && frame.signScaleY > 0
            && (0...1).contains(frame.robotOpacity)
            && (0...1).contains(frame.signOpacity)
            && (-1...1).contains(frame.gazeX)
            && (-1...1).contains(frame.gazeY)
            && (0...1).contains(frame.checkmarkProgress)
    }
}
