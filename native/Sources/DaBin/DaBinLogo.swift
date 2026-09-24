import SwiftUI

/// A compact wordmark and robot-bin drawn as native vectors, with no image asset or backdrop.
struct DaBinLogo: View {
    enum Variant {
        case standard
        case compact
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.daBinAccent) private var accent
    @Environment(\.displayScale) private var displayScale
    let variant: Variant

    init(variant: Variant = .standard) {
        self.variant = variant
    }

    private var isDark: Bool { colorScheme == .dark }
    private var scale: CGFloat { variant == .compact ? 0.75 : 1 }
    private var ink: Color {
        isDark ? Color(red: 0.92, green: 0.91, blue: 0.95) : Color(red: 0.22, green: 0.18, blue: 0.27)
    }

    private func scaled(_ value: CGFloat) -> CGFloat { value * scale }
    private func pixelAlignedStroke(_ value: CGFloat) -> CGFloat {
        let pixelsPerPoint = max(1, displayScale)
        return max(1, (scaled(value) * pixelsPerPoint).rounded()) / pixelsPerPoint
    }

    var body: some View {
        HStack(spacing: scaled(6)) {
            emblem
                .accessibilityHidden(true)
            (Text("Da").foregroundColor(ink) + Text("Bin").foregroundColor(accent))
                .font(.system(size: scaled(24), weight: .bold, design: .rounded))
                .tracking(scaled(-0.8))
        }
        .fixedSize(horizontal: true, vertical: true)
        .frame(height: scaled(28))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("DaBin")
        .accessibilityAddTraits(.isHeader)
    }

    private var emblem: some View {
        ZStack(alignment: .topLeading) {
            // The short handle and overhanging rim give the little robot its bin silhouette.
            RoundedRectangle(cornerRadius: scaled(1.6), style: .continuous)
                .stroke(accent, lineWidth: pixelAlignedStroke(1.3))
                .frame(width: scaled(7), height: scaled(4))
                .position(x: scaled(12.5), y: scaled(4.2))

            BinBody()
                .fill(LinearGradient(
                    stops: [
                        .init(color: accent.opacity(0.45), location: 0),
                        .init(color: accent.opacity(0.75), location: 0.35),
                        .init(color: accent, location: 1)
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .overlay(BinBody().stroke(accent.opacity(isDark ? 0.95 : 0.8),
                                          lineWidth: pixelAlignedStroke(0.8)))

            RoundedRectangle(cornerRadius: scaled(1.7), style: .continuous)
                .fill(LinearGradient(
                    colors: [accent.opacity(0.4), accent],
                    startPoint: .top, endPoint: .bottom
                ))
                .frame(width: scaled(22), height: scaled(4))
                .position(x: scaled(12.5), y: scaled(7))

            RoundedRectangle(cornerRadius: scaled(2.5), style: .continuous)
                .fill(Color(red: 0.18, green: 0.14, blue: 0.24))
                .frame(width: scaled(13), height: scaled(8))
                .position(x: scaled(12.5), y: scaled(14))

            ForEach([9.7, 15.3], id: \.self) { x in
                Capsule()
                    .fill(Color(red: 0.87, green: 0.95, blue: 0.94))
                    .frame(width: scaled(2), height: scaled(2.8))
                    .position(x: scaled(x), y: scaled(13.4))
            }

            Path { path in
                path.move(to: CGPoint(x: scaled(11.2), y: scaled(16)))
                path.addQuadCurve(to: CGPoint(x: scaled(13.8), y: scaled(16)),
                                  control: CGPoint(x: scaled(12.5), y: scaled(17)))
            }
            .stroke(Color(red: 0.67, green: 0.79, blue: 0.79),
                    style: StrokeStyle(lineWidth: pixelAlignedStroke(0.7), lineCap: .round))

            ForEach([9.5, 15.5], id: \.self) { x in
                Capsule()
                    .fill(Color.white.opacity(0.28))
                    .frame(width: scaled(1), height: scaled(3.5))
                    .position(x: scaled(x), y: scaled(21.5))
            }
        }
        .frame(width: scaled(25), height: scaled(28))
    }
}

private struct BinBody: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 3.4, y: 7.5))
        path.addLine(to: CGPoint(x: 21.6, y: 7.5))
        path.addLine(to: CGPoint(x: 19.8, y: 23.2))
        path.addQuadCurve(to: CGPoint(x: 17.3, y: 25.5), control: CGPoint(x: 19.5, y: 25.5))
        path.addLine(to: CGPoint(x: 7.7, y: 25.5))
        path.addQuadCurve(to: CGPoint(x: 5.2, y: 23.2), control: CGPoint(x: 5.5, y: 25.5))
        path.closeSubpath()
        return path.applying(CGAffineTransform(scaleX: rect.width / 25, y: rect.height / 28))
    }
}
