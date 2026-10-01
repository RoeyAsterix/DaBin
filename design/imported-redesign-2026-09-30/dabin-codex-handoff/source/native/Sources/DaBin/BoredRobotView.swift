import AppKit
import SwiftUI

/// The same robot as the corner widget, taking a small, sleepy pause between captures.
/// A hidden panel pauses the timeline; removing the empty state removes it entirely.
@MainActor
struct BoredRobotView: View {
    var isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appearedAt = Date()
    @State private var isMounted = false

    private static let robotImage: NSImage? = Bundle.main.url(forResource: "robot", withExtension: "svg")
        .flatMap(NSImage.init(contentsOf:))

    var body: some View {
        Group {
            if reduceMotion {
                robot(at: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 24, paused: !isActive || !isMounted)) { context in
                    robot(at: isActive ? context.date.timeIntervalSince(appearedAt) : 0)
                }
            }
        }
        .onAppear { appearedAt = Date(); isMounted = true }
        .onDisappear { isMounted = false }
        .onChange(of: isActive) { _, active in if active { appearedAt = Date() } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your purple robot is bored, waiting for a capture")
    }

    private func robot(at time: TimeInterval) -> some View {
        let phase = max(0, time).truncatingRemainder(dividingBy: 8.8)
        let sigh = pulse(phase, center: 6.1, radius: 1.2)
        let blink = max(pulse(phase, center: 2.2, radius: 0.15), pulse(phase, center: 7.4, radius: 0.16))
        let glance = pulse(phase, center: 3.7, radius: 1.2) * 1.2
        let sway = sin(time * .pi / 4.4) * 1.4
        return GeometryReader { geometry in
            let scale = min(geometry.size.width / 64, geometry.size.height / 78)
            ZStack(alignment: .topLeading) {
                if let image = Self.robotImage {
                    Image(nsImage: image).resizable().frame(width: 64, height: 78)
                    // The glass stays inside the original SVG bezel; only the face changes.
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(red: 41 / 255, green: 35 / 255, blue: 56 / 255))
                        .frame(width: 25, height: 17).position(x: 32, y: 40)
                    ForEach([26.0, 38.0], id: \.self) { x in
                        Capsule().fill(Color(red: 215 / 255, green: 244 / 255, blue: 239 / 255))
                            .frame(width: 5.2, height: max(0.55, (2 - sigh * 0.5) * (1 - blink)))
                            .position(x: x + glance, y: 40)
                    }
                    if sigh > 0.2 {
                        Ellipse().stroke(Color(red: 150 / 255, green: 206 / 255, blue: 201 / 255), lineWidth: 1)
                            .frame(width: 3.3, height: 1.5 + sigh * 2.2).position(x: 32, y: 45.3)
                    } else {
                        Path { path in
                            path.move(to: CGPoint(x: 29.5, y: 46))
                            path.addQuadCurve(to: CGPoint(x: 34.5, y: 46), control: CGPoint(x: 32, y: 44.4))
                        }.stroke(Color(red: 150 / 255, green: 206 / 255, blue: 201 / 255), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                    }
                }
            }
            .frame(width: 64, height: 78)
            .scaleEffect(x: 1 + sigh * 0.018, y: 0.97 - sigh * 0.025, anchor: .bottom)
            .rotationEffect(.degrees(-2 + sway), anchor: .bottom)
            .offset(y: 1 + sigh * 1.4)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: 64 * scale, height: 78 * scale)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }

    private func pulse(_ value: Double, center: Double, radius: Double) -> Double {
        let distance = abs(value - center)
        guard distance < radius else { return 0 }
        return (cos(distance / radius * .pi) + 1) / 2
    }
}
