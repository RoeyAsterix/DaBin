import CoreGraphics
import Foundation

/// Perches belong to the physical camera housing, rather than to an arbitrary
/// window origin. The artwork is mirrored on the left so its inside hand grips
/// the housing and its outside hand remains free for captured items.
enum QuietOrbitPerch: String, CaseIterable {
    case upperLeft = "upper-left"
    case left
    case lowerLeft = "lower-left"
    case bottom
    case lowerRight = "lower-right"
    case right
    case upperRight = "upper-right"

    var isMirrored: Bool {
        self == .upperLeft || self == .left || self == .lowerLeft
    }

    fileprivate var referenceVisibleOffset: CGPoint {
        switch self {
        case .upperLeft: return CGPoint(x: -89, y: -7)
        case .left: return CGPoint(x: -89, y: 5)
        case .lowerLeft: return CGPoint(x: -62, y: 23)
        case .bottom: return CGPoint(x: 0, y: 23)
        case .lowerRight: return CGPoint(x: 62, y: 23)
        case .right: return CGPoint(x: 89, y: 5)
        case .upperRight: return CGPoint(x: 89, y: -7)
        }
    }

    fileprivate var referenceHiddenOffset: CGPoint {
        switch self {
        case .upperLeft: return CGPoint(x: -48, y: -22)
        case .left: return CGPoint(x: -48, y: -15)
        case .lowerLeft: return CGPoint(x: -38, y: -22)
        case .bottom: return CGPoint(x: 0, y: -25)
        case .lowerRight: return CGPoint(x: 38, y: -22)
        case .right: return CGPoint(x: 48, y: -15)
        case .upperRight: return CGPoint(x: 48, y: -22)
        }
    }
}

/// Value-only mapping from the Quiet Orbit reference's y-down coordinates to
/// macOS screen and panel coordinates. A verified housing is required; callers
/// retain the existing corner placement when initialization returns nil.
struct QuietOrbitLayout: Equatable {
    static let referenceCameraSize = CGSize(width: 144, height: 34)
    static let rendererCanvasSize = CGSize(width: 64, height: 78)
    /// The native vector renderer uses transparent padding above its head.
    static let rendererArtworkBounds = CGRect(x: 6, y: 20, width: 56, height: 45)
    static let minimumInteractionSize: CGFloat = 44
    static let pointerDwell: TimeInterval = 0.15

    let cameraIsland: CGRect
    let displayFrame: CGRect

    init?(cameraIsland: CGRect, displayFrame: CGRect) {
        guard Self.isFinite(cameraIsland), Self.isFinite(displayFrame) else { return nil }
        let camera = cameraIsland.standardized
        let display = displayFrame.standardized
        guard !display.isEmpty, camera.width >= 24, camera.height >= 8,
              display.insetBy(dx: -1, dy: -1).contains(camera),
              abs(camera.maxY - display.maxY) <= 1 else { return nil }
        self.cameraIsland = camera
        self.displayFrame = display
    }

    /// The scene includes both sides of the housing and the small underside.
    /// Only the artwork gets a mouse target; this envelope stays transparent.
    var panelFrame: CGRect {
        let envelope = QuietOrbitPerch.allCases.reduce(cameraIsland) { current, perch in
            current.union(visibleRobotFrame(for: perch))
                .union(visibleRobotFrame(for: perch, hidden: true))
        }.insetBy(dx: -8, dy: -8).intersection(displayFrame)
        guard !envelope.isNull, !envelope.isEmpty else { return .zero }
        // Borderless native windows round their origins to whole logical points.
        let minimumX = max(displayFrame.minX, floor(envelope.minX))
        let minimumY = max(displayFrame.minY, floor(envelope.minY))
        let maximumX = min(displayFrame.maxX, ceil(envelope.maxX))
        let maximumY = min(displayFrame.maxY, ceil(envelope.maxY))
        return CGRect(x: minimumX, y: minimumY,
                      width: maximumX - minimumX, height: maximumY - minimumY)
    }

    var cameraFrameInPanel: CGRect { local(cameraIsland) }

    /// Physical artwork footprint, useful as the source for app expansion.
    func visibleRobotFrame(for perch: QuietOrbitPerch, hidden: Bool = false,
                           local: Bool = false) -> CGRect {
        let offset = hidden ? perch.referenceHiddenOffset : perch.referenceVisibleOffset
        // Exact reference fragment bounds after translate(128, -10) scale(.36).
        let referenceSize = CGSize(width: 47.88, height: 38.52)
        let referenceCenter = CGPoint(x: perch.isMirrored ? 198.02 : 201.98, y: 29.78)
        let xScale = cameraIsland.width / Self.referenceCameraSize.width
        let yScale = cameraIsland.height / Self.referenceCameraSize.height
        let artScale = min(xScale, yScale)
        let size = CGSize(width: referenceSize.width * artScale,
                          height: referenceSize.height * artScale)
        let center = CGPoint(x: cameraIsland.midX + (referenceCenter.x + offset.x - 200) * xScale,
                             y: cameraIsland.maxY - (referenceCenter.y + offset.y) * yScale)
        var frame = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                           width: size.width, height: size.height)
        if hidden {
            // Reference fingers can cross the housing edge by two units. Fully
            // tucked native poses must leave no clickable or visible sliver.
            frame.origin.x = min(max(frame.minX, cameraIsland.minX), cameraIsland.maxX - frame.width)
            frame.origin.y = max(frame.minY, cameraIsland.minY)
        }
        return local ? self.local(frame) : frame
    }

    /// The 64 × 78 native renderer canvas, positioned so its visible parts align
    /// with the physical footprint. AppKit's view coordinates are y-up while
    /// the character layer's design coordinates are explicitly y-down.
    func robotFrame(for perch: QuietOrbitPerch, hidden: Bool = false,
                    local: Bool = false) -> CGRect {
        let physical = visibleRobotFrame(for: perch, hidden: hidden)
        let scale = physical.width / Self.rendererArtworkBounds.width
        let artworkMinimumX = perch.isMirrored
            ? Self.rendererCanvasSize.width - Self.rendererArtworkBounds.maxX
            : Self.rendererArtworkBounds.minX
        let frame = CGRect(x: physical.minX - artworkMinimumX * scale,
                           y: physical.maxY + Self.rendererArtworkBounds.minY * scale
                                - Self.rendererCanvasSize.height * scale,
                           width: Self.rendererCanvasSize.width * scale,
                           height: Self.rendererCanvasSize.height * scale)
        return local ? self.local(frame) : frame
    }

    /// A small robot is still easy to click or drop onto. Subtract the real
    /// camera and clip to the physical display, so neither transparent panel
    /// margins nor the housing itself can become invisible input blockers.
    func interactionRegions(for perch: QuietOrbitPerch,
                            minimumTargetSize: CGFloat = Self.minimumInteractionSize,
                            local: Bool = false) -> [CGRect] {
        let physical = visibleRobotFrame(for: perch)
        let minimum = minimumTargetSize.isFinite ? max(0, minimumTargetSize) : Self.minimumInteractionSize
        let size = CGSize(width: max(physical.width, minimum), height: max(physical.height, minimum))
        let target = CGRect(x: physical.midX - size.width / 2, y: physical.midY - size.height / 2,
                            width: size.width, height: size.height).intersection(displayFrame)
        return Self.subtract(cameraIsland, from: target).map { local ? self.local($0) : $0 }
    }

    func containsInteraction(_ point: CGPoint, perch: QuietOrbitPerch,
                             local: Bool = false) -> Bool {
        let camera = local ? cameraFrameInPanel : cameraIsland
        guard !camera.contains(point) else { return false }
        return interactionRegions(for: perch, local: local).contains { $0.contains(point) }
    }

    /// Pointer thresholds are reference-normalized, not display pixels. Upper
    /// and lower corner poses remain discoverable on differently sized notches.
    func perch(at screenPoint: CGPoint) -> QuietOrbitPerch {
        guard screenPoint.x.isFinite, screenPoint.y.isFinite else { return .bottom }
        let x = (screenPoint.x - cameraIsland.midX) * Self.referenceCameraSize.width / cameraIsland.width
        let y = (cameraIsland.maxY - screenPoint.y) * Self.referenceCameraSize.height / cameraIsland.height
        if abs(x) < 35 { return .bottom }
        if y < 22 { return x < 0 ? .upperLeft : .upperRight }
        if y > 38 && abs(x) < 80 { return x < 0 ? .lowerLeft : .lowerRight }
        return x < 0 ? .left : .right
    }

    private func local(_ frame: CGRect) -> CGRect {
        frame.offsetBy(dx: -panelFrame.minX, dy: -panelFrame.minY)
    }

    private static func isFinite(_ rect: CGRect) -> Bool {
        [rect.origin.x, rect.origin.y, rect.width, rect.height].allSatisfy(\.isFinite)
    }

    private static func subtract(_ obstacle: CGRect, from frame: CGRect) -> [CGRect] {
        guard !frame.isNull, !frame.isEmpty else { return [] }
        let cut = frame.intersection(obstacle)
        guard !cut.isNull, !cut.isEmpty else { return [frame] }
        let candidates = [
            CGRect(x: frame.minX, y: frame.minY, width: cut.minX - frame.minX, height: frame.height),
            CGRect(x: cut.maxX, y: frame.minY, width: frame.maxX - cut.maxX, height: frame.height),
            CGRect(x: cut.minX, y: frame.minY, width: cut.width, height: cut.minY - frame.minY),
            CGRect(x: cut.minX, y: cut.maxY, width: cut.width, height: frame.maxY - cut.maxY)
        ]
        return candidates.filter { !$0.isEmpty && $0.width > 0 && $0.height > 0 }
    }
}

/// Event-driven dwell; there is no idle patrol or periodic location sampling.
/// A newer candidate always replaces the pending destination. The owner can
/// cancel on capture, opening, display changes, pointer exit, or shutdown.
struct QuietOrbitPerchDwell: Equatable {
    private(set) var current: QuietOrbitPerch
    private(set) var pending: QuietOrbitPerch?
    private(set) var pendingSince: TimeInterval?

    init(current: QuietOrbitPerch = .bottom) { self.current = current }

    @discardableResult
    mutating func observe(_ candidate: QuietOrbitPerch, at time: TimeInterval) -> QuietOrbitPerch? {
        guard time.isFinite else { return nil }
        guard candidate != current else { cancel(); return nil }
        if candidate != pending || pendingSince.map({ time < $0 }) == true {
            pending = candidate
            pendingSince = time
            return nil
        }
        return commit(at: time)
    }

    @discardableResult
    mutating func commit(at time: TimeInterval) -> QuietOrbitPerch? {
        guard time.isFinite, let pending, let pendingSince,
              time >= pendingSince + QuietOrbitLayout.pointerDwell else { return nil }
        current = pending
        cancel()
        return current
    }

    mutating func cancel() {
        pending = nil
        pendingSince = nil
    }

    mutating func reset(to perch: QuietOrbitPerch = .bottom) {
        current = perch
        cancel()
    }
}
