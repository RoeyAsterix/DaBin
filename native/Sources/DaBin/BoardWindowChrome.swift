import SwiftUI

/// One continuous curve for the hosted board, native reveal and metal rim.
enum BoardWindowChrome {
    static let cornerRadius: CGFloat = 21
    static let rimWidth: CGFloat = 2.25

    static var shape: RoundedRectangle { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous) }

    static func path(in rect: CGRect, outset: CGFloat = 0) -> CGPath {
        RoundedRectangle(cornerRadius: max(0, cornerRadius + outset), style: .continuous)
            .path(in: rect.insetBy(dx: -outset, dy: -outset)).cgPath
    }

    static func rimPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        path.addPath(Self.path(in: rect, outset: rimWidth))
        path.addPath(Self.path(in: rect))
        return path
    }
}
