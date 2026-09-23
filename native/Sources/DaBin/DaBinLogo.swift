import SwiftUI

/// A compact wordmark and robot-bin drawn as native vectors, with no image asset or backdrop.
struct DaBinLogo: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.daBinAccent) private var accent

    private var isDark: Bool { colorScheme == .dark }
    private var ink: Color {
        isDark ? Color(red: 0.92, green: 0.91, blue: 0.95) : Color(red: 0.22, green: 0.18, blue: 0.27)
    }

    var body: some View {
        HStack(spacing: 6) {
            emblem
                .accessibilityHidden(true)
            (Text("Da").foregroundColor(ink) + Text("Bin").foregroundColor(accent))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .tracking(-0.8)
        }
        .fixedSize(horizontal: true, vertical: true)
        .frame(height: 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("DaBin")
        .accessibilityAddTraits(.isHeader)
    }

    private var emblem: some View {
        ZStack(alignment: .topLeading) {
            // The short handle and overhanging rim give the little robot its bin silhouette.
            RoundedRectangle(cornerRadius: 1.6, style: .continuous)
                .stroke(accent, lineWidth: 1.3)
                .frame(width: 7, height: 4)
                .position(x: 12.5, y: 4.2)

            BinBody()
                .fill(LinearGradient(
                    stops: [
                        .init(color: accent.opacity(0.45), location: 0),
                        .init(color: accent.opacity(0.75), location: 0.35),
                        .init(color: accent, location: 1)
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .overlay(BinBody().stroke(accent.opacity(isDark ? 0.95 : 0.8), lineWidth: 0.8))

            RoundedRectangle(cornerRadius: 1.7, style: .continuous)
                .fill(LinearGradient(
                    colors: [accent.opacity(0.4), accent],
                    startPoint: .top, endPoint: .bottom
                ))
                .frame(width: 22, height: 4)
                .position(x: 12.5, y: 7)

            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(Color(red: 0.18, green: 0.14, blue: 0.24))
                .frame(width: 13, height: 8)
                .position(x: 12.5, y: 14)

            ForEach([9.7, 15.3], id: \.self) { x in
                Capsule()
                    .fill(Color(red: 0.87, green: 0.95, blue: 0.94))
                    .frame(width: 2, height: 2.8)
                    .position(x: x, y: 13.4)
            }

            Path { path in
                path.move(to: CGPoint(x: 11.2, y: 16))
                path.addQuadCurve(to: CGPoint(x: 13.8, y: 16), control: CGPoint(x: 12.5, y: 17))
            }
            .stroke(Color(red: 0.67, green: 0.79, blue: 0.79), style: StrokeStyle(lineWidth: 0.7, lineCap: .round))

            ForEach([9.5, 15.5], id: \.self) { x in
                Capsule()
                    .fill(Color.white.opacity(0.28))
                    .frame(width: 1, height: 3.5)
                    .position(x: x, y: 21.5)
            }
        }
        .frame(width: 25, height: 28)
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
