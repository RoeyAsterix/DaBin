import AppKit

/// Window geometry is independent of capture state and never mutates the archive.
@MainActor enum BoardResizeGeometry {
    struct Edge: OptionSet {
        let rawValue: Int
        static let left = Edge(rawValue: 1)
        static let right = Edge(rawValue: 2)
        static let bottom = Edge(rawValue: 4)
        static let top = Edge(rawValue: 8)
    }

    // At 280pt the persistent controls could leave only one line of results.
    // Keep a useful list/preview area at the smallest supported size.
    static let minimumContentSize = CGSize(width: 380, height: 430)
    static var minimumSize: CGSize { RobotAppFrameView.outerSize(forContentSize: minimumContentSize) }

    /// The visible card sits inside the robot's transparent chrome. Corners
    /// must be grabbable there, not only at the invisible outer window bounds.
    static func cornerRegions(in bounds: CGRect) -> [(rect: CGRect, edge: Edge)] {
        let content = RobotAppFrameView.contentRect(in: bounds)
        return [
            (CGPoint(x: content.minX, y: content.maxY), Edge([.left, .top])),
            (CGPoint(x: content.maxX, y: content.maxY), Edge([.right, .top])),
            (CGPoint(x: content.minX, y: content.minY), Edge([.left, .bottom])),
            (CGPoint(x: content.maxX, y: content.minY), Edge([.right, .bottom]))
        ].map { point, edge in
            (CGRect(x: point.x - 12, y: point.y - 12, width: 24, height: 24).intersection(bounds), edge)
        }
    }

    static func interactionEdge(at point: CGPoint, in bounds: CGRect) -> Edge {
        guard bounds.contains(point) else { return [] }
        return cornerRegions(in: bounds).first { $0.rect.contains(point) }?.edge
            ?? edge(at: point, in: bounds)
    }

    static func dragRegion(in bounds: CGRect) -> CGRect {
        let content = RobotAppFrameView.contentRect(in: bounds)
        return CGRect(x: bounds.minX + 6, y: content.maxY,
                      width: max(0, bounds.width - 12), height: max(0, bounds.maxY - content.maxY - 6))
    }

    /// The display under the released pointer wins even when most of a wide
    /// window still overlaps its previous display. Gaps use actual overlap.
    static func destinationDisplay(for frame: CGRect, pointer: CGPoint?, displays: [CGRect]) -> Int? {
        if let pointer, let index = displays.firstIndex(where: { $0.contains(pointer) }) { return index }
        let overlaps = displays.enumerated().map { index, display in
            let overlap = display.intersection(frame)
            return (index, overlap.isNull ? CGFloat.zero : overlap.width * overlap.height)
        }
        return overlaps.max(by: { $0.1 < $1.1 }).flatMap { $0.1 > 0 ? $0.0 : nil }
    }

    static func edge(at point: CGPoint, in bounds: CGRect, thickness: CGFloat = 6) -> Edge {
        guard bounds.contains(point) else { return [] }
        var result: Edge = []
        if point.x <= bounds.minX + thickness { result.insert(.left) }
        if point.x >= bounds.maxX - thickness { result.insert(.right) }
        if point.y <= bounds.minY + thickness { result.insert(.bottom) }
        if point.y >= bounds.maxY - thickness { result.insert(.top) }
        return result
    }

    static func fitted(_ frame: CGRect, visible: CGRect, minimum: CGSize? = nil) -> CGRect {
        let minimum = minimum ?? minimumSize
        let size = CGSize(width: min(visible.width, max(minimum.width, frame.width)),
                          height: min(visible.height, max(minimum.height, frame.height)))
        return CGRect(x: min(max(visible.minX, frame.minX), visible.maxX - size.width),
                      y: min(max(visible.minY, frame.maxY - size.height), visible.maxY - size.height),
                      width: size.width, height: size.height)
    }

    static func resized(_ original: CGRect, edge: Edge, delta: CGPoint, visible: CGRect) -> CGRect {
        guard delta.x.isFinite, delta.y.isFinite else { return fitted(original, visible: visible) }
        var minX = original.minX, maxX = original.maxX
        var minY = original.minY, maxY = original.maxY
        let minimumWidth = min(minimumSize.width, visible.width)
        let minimumHeight = min(minimumSize.height, visible.height)
        if edge.contains(.left) { minX = max(visible.minX, min(maxX - minimumWidth, minX + delta.x)) }
        if edge.contains(.right) { maxX = min(visible.maxX, max(minX + minimumWidth, maxX + delta.x)) }
        if edge.contains(.bottom) { minY = max(visible.minY, min(maxY - minimumHeight, minY + delta.y)) }
        if edge.contains(.top) { maxY = min(visible.maxY, max(minY + minimumHeight, maxY + delta.y)) }
        return fitted(CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY), visible: visible)
    }
}
