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
    static let innerGrabWidth: CGFloat = 6
    // Stop at the header's 12pt horizontal padding. The much larger outward
    // chrome region adds reach without stealing the close/project controls.
    static let cornerReach: CGFloat = 12
    private static let outerTopGrabWidth: CGFloat = 8

    /// The visible card sits inside the robot's transparent chrome. Corners
    /// must be grabbable there, not only at the invisible outer window bounds.
    static func cornerRegions(in bounds: CGRect) -> [(rect: CGRect, edge: Edge)] {
        guard let content = validContent(in: bounds) else { return [] }
        let reachX = min(cornerReach, content.width / 2)
        let reachY = min(cornerReach, content.height / 2)
        let leftWidth = content.minX + reachX - bounds.minX
        let rightX = content.maxX - reachX
        let topY = content.maxY - reachY
        let bottomHeight = content.minY + reachY - bounds.minY
        return [
            (CGRect(x: bounds.minX, y: topY, width: leftWidth, height: bounds.maxY - topY), [.left, .top]),
            (CGRect(x: rightX, y: topY, width: bounds.maxX - rightX, height: bounds.maxY - topY), [.right, .top]),
            (CGRect(x: bounds.minX, y: bounds.minY, width: leftWidth, height: bottomHeight), [.left, .bottom]),
            (CGRect(x: rightX, y: bounds.minY, width: bounds.maxX - rightX, height: bottomHeight), [.right, .bottom])
        ]
    }

    /// One shared geometry authority for native hit testing and cursor rects.
    /// The card's shallow inside band is padding, not an overlaid control area.
    static func edgeRegions(in bounds: CGRect) -> [(rect: CGRect, edge: Edge)] {
        guard let content = validContent(in: bounds) else { return [] }
        let grabX = min(innerGrabWidth, content.width / 2)
        let grabY = min(innerGrabWidth, content.height / 2)
        let rightX = content.maxX - grabX
        let visibleTopY = content.maxY - grabY
        let visibleTopMaxY = min(bounds.maxY, content.maxY + innerGrabWidth)
        let outerTopY = max(bounds.minY, bounds.maxY - outerTopGrabWidth)
        return [
            (CGRect(x: bounds.minX, y: bounds.minY, width: content.minX + grabX - bounds.minX,
                    height: bounds.height), .left),
            (CGRect(x: rightX, y: bounds.minY, width: bounds.maxX - rightX,
                    height: bounds.height), .right),
            (CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width,
                    height: content.minY + grabY - bounds.minY), .bottom),
            (CGRect(x: bounds.minX, y: visibleTopY, width: bounds.width,
                    height: visibleTopMaxY - visibleTopY), .top),
            (CGRect(x: bounds.minX, y: outerTopY, width: bounds.width,
                    height: bounds.maxY - outerTopY), .top)
        ]
    }

    static func interactionEdge(at point: CGPoint, in bounds: CGRect) -> Edge {
        guard point.x.isFinite, point.y.isFinite, bounds.contains(point) else { return [] }
        return cornerRegions(in: bounds).first { $0.rect.contains(point) }?.edge
            ?? edgeRegions(in: bounds).first { $0.rect.contains(point) }?.edge
            ?? []
    }

    static func dragRegion(in bounds: CGRect) -> CGRect {
        guard let content = validContent(in: bounds) else { return .zero }
        let reachX = min(cornerReach, content.width / 2)
        let left = content.minX + reachX
        let right = content.maxX - reachX
        let bottom = min(bounds.maxY, content.maxY + innerGrabWidth)
        let top = max(bottom, bounds.maxY - outerTopGrabWidth)
        return CGRect(x: left, y: bottom, width: max(0, right - left), height: top - bottom)
    }

    private static func validContent(in bounds: CGRect) -> CGRect? {
        guard !bounds.isNull, !bounds.isInfinite,
              bounds.origin.x.isFinite, bounds.origin.y.isFinite,
              bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0,
              bounds.minX.isFinite, bounds.maxX.isFinite,
              bounds.minY.isFinite, bounds.maxY.isFinite else { return nil }
        let content = RobotAppFrameView.contentRect(in: bounds)
        return content.width > 0 && content.height > 0 ? content : nil
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
