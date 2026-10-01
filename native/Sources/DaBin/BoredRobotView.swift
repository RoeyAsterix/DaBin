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
        let sway = sin(time * .pi / 4.4) * 1.4
        return GeometryReader { geometry in
            let scale = min(geometry.size.width / 64, geometry.size.height / 78)
            BoredRobotCharacter()
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

/// The empty state borrows the live island character rather than maintaining
/// an SVG and a second face. Its native pose stays static; only the surrounding
/// visible TimelineView supplies the small sleepy sway and sigh.
@MainActor
private struct BoredRobotCharacter: NSViewRepresentable {
    func makeNSView(context: Context) -> RobotCharacterView {
        let character = RobotCharacterView(frame: NSRect(x: 0, y: 0, width: 64, height: 78),
                                           reduceMotion: { true })
        character.configureQuietOrbit(true)
        character.send(.reveal(.top))
        return character
    }

    func updateNSView(_ character: RobotCharacterView, context: Context) {}

    static func dismantleNSView(_ character: RobotCharacterView, coordinator: ()) {
        character.stopMotion()
    }
}
