import AppKit
import QuartzCore

/// The island character is the visual authority for every DaBin robot surface.
/// Geometry uses the original mechanical head's 100 × 68 top-down coordinates.
enum QuietOrbitVisualStyle {
    static let headSize = CGSize(width: 100, height: 68)
    static let metal: [UInt32] = [0xEEE7F4, 0xC8B4DC, 0x977CAD, 0xBCA5D0, 0x6D5387]
    static let silver: [UInt32] = [0xF6F4F8, 0xD4CDDC, 0xA9A1B3, 0xE3DCE9, 0x85758F]
    static let visor: [UInt32] = [0x3E3449, 0x1E1924, 0x30253B]
    static let eye: UInt32 = 0xC8F1E5

    static func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(red: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: alpha)
    }

    static func point(_ x: CGFloat, _ y: CGFloat, in rect: CGRect, topDown: Bool) -> CGPoint {
        CGPoint(x: rect.minX + x * rect.width / headSize.width,
                y: topDown ? rect.minY + y * rect.height / headSize.height
                           : rect.maxY - y * rect.height / headSize.height)
    }

    static func rectangle(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat,
                          in rect: CGRect, topDown: Bool) -> CGRect {
        let start = point(x, y, in: rect, topDown: topDown)
        let end = point(x + width, y + height, in: rect, topDown: topDown)
        return CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                      width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    static func polygon(_ points: [(CGFloat, CGFloat)], in rect: CGRect, topDown: Bool,
                        closed: Bool = true) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: point(first.0, first.1, in: rect, topDown: topDown))
        for next in points.dropFirst() { path.addLine(to: point(next.0, next.1, in: rect, topDown: topDown)) }
        if closed { path.closeSubpath() }
        return path
    }

    static func headPath(in rect: CGRect, topDown: Bool) -> CGPath {
        polygon([(16, 0), (84, 0), (100, 14), (100, 55), (87, 68), (13, 68), (0, 55), (0, 14)],
                in: rect, topDown: topDown)
    }

    static func visorPath(in rect: CGRect, topDown: Bool) -> CGPath {
        polygon([(14, 18), (86, 18), (92, 25), (92, 50), (84, 59), (16, 59), (8, 50), (8, 25)],
                in: rect, topDown: topDown)
    }

    static func idleMouthPath(in rect: CGRect, topDown: Bool) -> CGPath {
        polygon([(44, 49), (47, 52), (53, 52), (56, 49)], in: rect, topDown: topDown, closed: false)
    }
}

/// One native vector construction for both the island and expanded frame.
/// Callers retain their existing eye/mouth layers and animation ownership.
@MainActor
enum QuietOrbitHeadArtwork {
    static func install(in parent: CALayer, canvas: CGSize, headRect: CGRect, topDown: Bool,
                        visor: CAShapeLayer, leftEye: CAShapeLayer, rightEye: CAShapeLayer,
                        mouth: CAShapeLayer) {
        let unit = headRect.width / QuietOrbitVisualStyle.headSize.width
        parent.name = "quietOrbit.head"
        func path(_ points: [(CGFloat, CGFloat)], closed: Bool = true) -> CGPath {
            QuietOrbitVisualStyle.polygon(points, in: headRect, topDown: topDown, closed: closed)
        }
        func shape(_ path: CGPath, in target: CALayer, name: String? = nil,
                   fill: UInt32? = nil, stroke: UInt32? = nil, width: CGFloat = 1,
                   alpha: CGFloat = 1) {
            let layer = CAShapeLayer()
            layer.name = name
            layer.path = path
            layer.fillColor = fill.map { QuietOrbitVisualStyle.color($0, alpha: alpha) }
            layer.strokeColor = stroke.map { QuietOrbitVisualStyle.color($0, alpha: alpha) }
            layer.lineWidth = width
            layer.lineJoin = .round
            layer.lineCap = .round
            target.addSublayer(layer)
        }
        func gradient(_ path: CGPath, colors: [UInt32], in target: CALayer, name: String) {
            let mask = CAShapeLayer()
            mask.path = path
            let layer = CAGradientLayer()
            layer.name = name
            layer.frame = CGRect(origin: .zero, size: canvas)
            layer.colors = colors.map { QuietOrbitVisualStyle.color($0) }
            layer.locations = colors.indices.map { NSNumber(value: Double($0) / Double(max(1, colors.count - 1))) }
            let box = path.boundingBoxOfPath
            layer.startPoint = CGPoint(x: box.minX / canvas.width,
                                      y: (topDown ? box.minY : box.maxY) / canvas.height)
            layer.endPoint = CGPoint(x: box.maxX / canvas.width,
                                    y: (topDown ? box.maxY : box.minY) / canvas.height)
            layer.mask = mask
            target.addSublayer(layer)
        }

        let head = QuietOrbitVisualStyle.headPath(in: headRect, topDown: topDown)
        gradient(head, colors: QuietOrbitVisualStyle.metal, in: parent, name: "quietOrbit.headShell")
        shape(head, in: parent, name: "quietOrbit.headOutline", stroke: 0x7D6490, width: 1.2 * unit)
        shape(path([(8, 16), (19, 6), (81, 6), (92, 16)], closed: false),
              in: parent, stroke: 0xF2EAF9, width: 2 * unit)

        let glass = QuietOrbitVisualStyle.visorPath(in: headRect, topDown: topDown)
        visor.name = "quietOrbit.visor"
        visor.path = glass
        visor.fillColor = QuietOrbitVisualStyle.color(0x1E1924)
        visor.strokeColor = QuietOrbitVisualStyle.color(0x8D759F)
        visor.lineWidth = unit
        parent.addSublayer(visor)
        gradient(glass, colors: QuietOrbitVisualStyle.visor, in: visor, name: "quietOrbit.visorGradient")
        shape(path([(19, 23), (79, 23)], closed: false), in: parent,
              stroke: 0xDFD2EA, width: 1.4 * unit, alpha: 0.18)

        for (eye, x, name) in [(leftEye, CGFloat(24), "quietOrbit.eye.left"),
                               (rightEye, CGFloat(63), "quietOrbit.eye.right")] {
            let center = QuietOrbitVisualStyle.point(x + 6.5, 38.5, in: headRect, topDown: topDown)
            eye.name = name
            eye.bounds = CGRect(origin: .zero, size: canvas)
            eye.anchorPoint = CGPoint(x: center.x / canvas.width, y: center.y / canvas.height)
            eye.position = center
            eye.masksToBounds = false
            eye.path = CGPath(rect: QuietOrbitVisualStyle.rectangle(x, 31, 13, 15, in: headRect, topDown: topDown), transform: nil)
            eye.fillColor = QuietOrbitVisualStyle.color(QuietOrbitVisualStyle.eye)
            eye.shadowColor = QuietOrbitVisualStyle.color(0xB3E6D9)
            eye.shadowOpacity = 0.16
            eye.shadowRadius = 0.8
            eye.shadowOffset = .zero
            let scanlines = CGMutablePath()
            for offset: CGFloat in [4, 8, 12] {
                scanlines.addPath(path([(x + 2, 31 + offset), (x + 11, 31 + offset)], closed: false))
            }
            shape(scanlines, in: eye, name: "quietOrbit.eye.scanlines", stroke: 0x233B35,
                  width: 0.8 * unit, alpha: 0.18)
            parent.addSublayer(eye)
        }

        mouth.name = "quietOrbit.mouth"
        mouth.path = QuietOrbitVisualStyle.idleMouthPath(in: headRect, topDown: topDown)
        mouth.fillColor = nil
        mouth.strokeColor = QuietOrbitVisualStyle.color(0xA3C7BD)
        mouth.lineWidth = 1.8 * unit
        mouth.lineCap = .square
        mouth.lineJoin = .round
        parent.addSublayer(mouth)

        let slot = QuietOrbitVisualStyle.rectangle(42, 9, 16, 3, in: headRect, topDown: topDown)
        shape(CGPath(roundedRect: slot, cornerWidth: unit, cornerHeight: unit, transform: nil),
              in: parent, fill: 0x5B486A)
        shape(path([(45, 10.5), (52, 10.5)], closed: false), in: parent,
              stroke: QuietOrbitVisualStyle.eye, width: 1.2 * unit)
        let seams = CGMutablePath()
        for x: CGFloat in [5, 95] { seams.addPath(path([(x, 27), (x, 44)], closed: false)) }
        for x: CGFloat in [15, 82] { seams.addPath(path([(x, 62), (x + 3, 62)], closed: false)) }
        shape(seams, in: parent, stroke: 0x584664, width: 1.5 * unit)
    }
}

/// The compact chest, neck and feet share the island's original geometry.
/// Coordinates extend below the same 100 × 68 head rectangle used above.
/// Callers retain the body container and feet layer that own their animations.
@MainActor
enum QuietOrbitBodyArtwork {
    static func install(in parent: CALayer, canvas: CGSize, headRect: CGRect,
                        topDown: Bool, feet: CAShapeLayer) {
        let unit = headRect.width / QuietOrbitVisualStyle.headSize.width
        parent.name = "quietOrbit.body"
        func path(_ points: [(CGFloat, CGFloat)], closed: Bool = true) -> CGPath {
            QuietOrbitVisualStyle.polygon(points, in: headRect, topDown: topDown, closed: closed)
        }
        func roundedRect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat,
                         radius: CGFloat) -> CGPath {
            CGPath(roundedRect: QuietOrbitVisualStyle.rectangle(x, y, width, height,
                in: headRect, topDown: topDown), cornerWidth: radius * unit,
                cornerHeight: radius * unit, transform: nil)
        }
        func shape(_ path: CGPath, name: String? = nil, fill: UInt32? = nil,
                   stroke: UInt32? = nil, width: CGFloat = 1) {
            let layer = CAShapeLayer()
            layer.name = name
            layer.path = path
            layer.fillColor = fill.map { QuietOrbitVisualStyle.color($0) }
            layer.strokeColor = stroke.map { QuietOrbitVisualStyle.color($0) }
            layer.lineWidth = width
            layer.lineJoin = .round
            layer.lineCap = .round
            parent.addSublayer(layer)
        }
        func gradient(_ path: CGPath, colors: [UInt32], in target: CALayer, name: String) {
            let mask = CAShapeLayer()
            mask.path = path
            let layer = CAGradientLayer()
            layer.name = name
            layer.frame = CGRect(origin: .zero, size: canvas)
            layer.colors = colors.map { QuietOrbitVisualStyle.color($0) }
            layer.locations = colors.indices.map { NSNumber(value: Double($0) / Double(max(1, colors.count - 1))) }
            let box = path.boundingBoxOfPath
            layer.startPoint = CGPoint(x: box.minX / canvas.width,
                                      y: (topDown ? box.minY : box.maxY) / canvas.height)
            layer.endPoint = CGPoint(x: box.maxX / canvas.width,
                                    y: (topDown ? box.maxY : box.minY) / canvas.height)
            layer.mask = mask
            target.addSublayer(layer)
        }

        shape(roundedRect(37, 60, 26, 18, radius: 1), name: "quietOrbit.neck",
              fill: 0x554760, stroke: 0x9986AA, width: unit)
        let ribs = CGMutablePath()
        for y: CGFloat in [65, 70] { ribs.addPath(path([(38, y), (62, y)], closed: false)) }
        shape(ribs, name: "quietOrbit.neck.ribs", stroke: 0xC4B7D0, width: 2 * unit)

        let feetPath = CGMutablePath()
        feetPath.addPath(roundedRect(20, 98, 19, 9, radius: 3))
        feetPath.addPath(roundedRect(61, 98, 19, 9, radius: 3))
        feet.name = "quietOrbit.feet"
        feet.path = feetPath
        feet.fillColor = QuietOrbitVisualStyle.color(0xD4CDDC)
        feet.strokeColor = QuietOrbitVisualStyle.color(0x766285)
        feet.lineWidth = unit
        parent.addSublayer(feet)
        gradient(feetPath, colors: QuietOrbitVisualStyle.silver, in: feet,
                 name: "quietOrbit.feet.metal")

        let chest = path([(26, 72), (74, 72), (84, 81), (79, 102), (21, 102), (16, 81)])
        gradient(chest, colors: QuietOrbitVisualStyle.metal, in: parent, name: "quietOrbit.chest")
        shape(chest, name: "quietOrbit.chest.outline", stroke: 0x7A628D, width: unit)
        shape(path([(26, 75), (74, 75)], closed: false), name: "quietOrbit.chest.highlight",
              stroke: 0xEEE5F5, width: 1.5 * unit)
        shape(roundedRect(33, 83, 34, 10, radius: 2), name: "quietOrbit.intake",
              fill: 0x282230, stroke: 0x8E7A9F, width: unit)
        shape(path([(37, 91), (63, 91)], closed: false), name: "quietOrbit.intake.light",
              stroke: 0xB3E6D9, width: 1.5 * unit)
        let screws = CGMutablePath()
        for x: CGFloat in [25, 71] { screws.addPath(path([(x, 95), (x + 4, 95)], closed: false)) }
        shape(screws, name: "quietOrbit.chest.screws", stroke: 0x544260, width: 1.5 * unit)
    }
}
