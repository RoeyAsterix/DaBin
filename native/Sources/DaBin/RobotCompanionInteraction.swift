import CoreGraphics
import Foundation

/// One pointer encounter uses a fixed stage and click target. Leaving the
/// approach zone first earns a watchful pause, then a short, reversible retreat.
struct RobotCompanionEncounter {
    enum Phase: String { case hidden, peeking, climbing, reaching, watching, retreating }
    struct Snapshot {
        let phase: Phase
        let progress: CGFloat
        let pointer: CGPoint
        var isVisible: Bool { phase != .hidden }
    }
    static let retreatDelay: TimeInterval = 0.65
    static let retreatDuration: TimeInterval = 0.42
    private(set) var progress: CGFloat = 0
    private var lastNear: TimeInterval?
    private var lastUpdate: TimeInterval?

    mutating func reset() { self = Self() }

    mutating func update(proximity: CGFloat?, pointer: CGPoint, at time: TimeInterval,
                         expressionOnly: Bool = false) -> Snapshot {
        let now = time.isFinite ? time : (lastUpdate ?? 0)
        let previousUpdate = lastUpdate
        let elapsed = min(0.2, max(0, now - (previousUpdate ?? now - 0.1)))
        lastUpdate = now
        let gaze = CGPoint(x: pointer.x.isFinite ? min(1, max(-1, pointer.x)) : 0,
                           y: pointer.y.isFinite ? min(1, max(-1, pointer.y)) : 0)
        let phase: Phase
        if let proximity, proximity.isFinite {
            lastNear = now
            let desired = max(0.22, min(1, proximity))
            if expressionOnly { progress = 1 }
            else if desired >= progress { progress = min(desired, progress + CGFloat(elapsed / 0.32)) }
            else { progress = max(desired, progress - CGFloat(elapsed / 0.45)) }
            phase = progress < 0.4 ? .peeking : progress < 0.9 ? .climbing : .reaching
        } else if let lastNear, progress > 0 {
            if now - lastNear <= Self.retreatDelay { phase = .watching }
            else {
                // Entry motion is frame-bounded, but departure follows the
                // real clock. A sparse sample must consume all elapsed retreat
                // time, excluding the portion still inside the watch grace.
                let retreatStart = max(lastNear + Self.retreatDelay, previousUpdate ?? now)
                let retreatElapsed = max(0, now - retreatStart)
                progress = expressionOnly ? 0 : max(0, progress - CGFloat(retreatElapsed / Self.retreatDuration))
                phase = progress > 0 ? .retreating : .hidden
            }
        } else { phase = .hidden; progress = 0 }
        if phase == .hidden { lastNear = nil }
        return Snapshot(phase: phase, progress: progress, pointer: gaze)
    }
}

enum RobotCompanionProximity {
    static func island(_ point: CGPoint, housing: CGRect) -> CGFloat? {
        let x = max(0, max(housing.minX - point.x, point.x - housing.maxX))
        let y = max(0, max(housing.minY - point.y, point.y - housing.maxY))
        return progress(distance: hypot(x, y), outer: 64, inner: 16)
    }

    static func corner(_ point: CGPoint, anchor: CGPoint) -> CGFloat? {
        progress(distance: hypot(point.x - anchor.x, point.y - anchor.y), outer: 96, inner: 24)
    }

    private static func progress(distance: CGFloat, outer: CGFloat, inner: CGFloat) -> CGFloat? {
        guard distance.isFinite, distance < outer else { return nil }
        return min(1, max(0, (outer - distance) / (outer - inner)))
    }
}
