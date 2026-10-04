import Foundation

/// Shared, deterministic alarm pacing. The native view animates only transforms;
/// the presenter wakes at the three stage boundaries, never once per frame.
enum TaskTimerAlarmMotion {
    static let stageInterval: TimeInterval = 8
    static let growthDuration: TimeInterval = 0.85
    static let scales: [CGFloat] = [1, 1.5, 2, 3]
    static let maximumScale: CGFloat = 3

    static func level(after elapsed: TimeInterval, reduceMotion: Bool = false) -> Int {
        guard !reduceMotion, elapsed.isFinite, elapsed > 0 else { return 0 }
        return min(scales.count - 1, Int(min(elapsed / stageInterval, Double(scales.count - 1))))
    }

    /// Squash/stretch may approach a hard size limit but never overshoot it,
    /// including a display whose available height caps growth before 3×.
    static func stretchFactor(for scale: CGFloat, preferred: CGFloat, limit: CGFloat) -> CGFloat {
        guard scale.isFinite, scale > 0, preferred.isFinite, limit.isFinite else { return 1 }
        return max(0.01, min(preferred, max(0.01, limit) / scale))
    }

    static func scale(for level: Int, availableSize: CGSize, baseSize: CGSize) -> CGFloat {
        guard availableSize.width.isFinite, availableSize.height.isFinite,
              baseSize.width > 0, baseSize.height > 0 else { return 0.01 }
        let requested = scales[min(max(level, 0), scales.count - 1)]
        return max(0.01, min(requested, availableSize.width / baseSize.width,
                             availableSize.height / baseSize.height))
    }
}
