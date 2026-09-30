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

    static let minimumContentSize = CGSize(width: 380, height: 280)
    static var minimumSize: CGSize { RobotAppFrameView.outerSize(forContentSize: minimumContentSize) }

    static func edge(at point: CGPoint, in bounds: CGRect, thickness: CGFloat = 6) -> Edge {
        guard bounds.contains(point) else { return [] }
        var result: Edge = []
        if point.x <= bounds.minX + thickness { result.insert(.left) }
        if point.x >= bounds.maxX - thickness { result.insert(.right) }
        if point.y <= bounds.minY + thickness { result.insert(.bottom) }
        if point.y >= bounds.maxY - thickness { result.insert(.top) }
        return result
    }

    static func fitted(_ frame: CGRect, visible: CGRect) -> CGRect {
        let size = CGSize(width: min(visible.width, max(minimumSize.width, frame.width)),
                          height: min(visible.height, max(minimumSize.height, frame.height)))
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
