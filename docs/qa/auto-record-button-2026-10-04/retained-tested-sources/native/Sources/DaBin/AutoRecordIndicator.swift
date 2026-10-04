import AppKit
import QuartzCore
import SwiftUI

/// Enabled capture can still be waiting for permission or its runtime to start.
/// Only a running channel should tell the user that recording is taking place.
struct AutoRecordPresentation: Equatable {
    let isRecording: Bool
    let animates: Bool

    init(runtimeIsRunning: Bool, isEnabled: Bool, isPaused: Bool,
         isVisible: Bool, reduceMotion: Bool) {
        isRecording = runtimeIsRunning && isEnabled && !isPaused
        animates = isRecording && isVisible && !reduceMotion
    }
}

@MainActor
struct AutoRecordIndicator: NSViewRepresentable {
    let presentation: AutoRecordPresentation

    func makeNSView(context: Context) -> AutoRecordIndicatorView {
        let view = AutoRecordIndicatorView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        view.configure(presentation)
        return view
    }

    func updateNSView(_ view: AutoRecordIndicatorView, context: Context) {
        view.configure(presentation)
    }

    static func dismantleNSView(_ view: AutoRecordIndicatorView, coordinator: ()) {
        view.stopAnimation()
    }
}

/// Compositor motion avoids a repeating SwiftUI task invalidating the timeline.
/// This view draws only; the surrounding SwiftUI button owns input and focus.
@MainActor
final class AutoRecordIndicatorView: NSView {
    static let idleDotDiameter: CGFloat = 8
    static let recordingDotDiameter: CGFloat = 16
    private static let danceKey = "auto-record-dance"
    private let ring = CAShapeLayer()
    private let dot = CAGradientLayer()
    private(set) var presentation = AutoRecordPresentation(
        runtimeIsRunning: false, isEnabled: false, isPaused: false,
        isVisible: true, reduceMotion: false)

    var dotDiameter: CGFloat { dot.bounds.width }
    var hasActiveAnimations: Bool { dot.animation(forKey: Self.danceKey) != nil }
    var dotPresentationPosition: CGPoint { dot.presentation()?.position ?? dot.position }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(false)
        ring.fillColor = NSColor.clear.cgColor
        ring.lineWidth = 1.25
        dot.startPoint = CGPoint(x: 0.3, y: 1)
        dot.endPoint = CGPoint(x: 0.7, y: 0)
        dot.masksToBounds = true
        layer?.addSublayer(ring)
        layer?.addSublayer(dot)
        updateLayers()
    }

    required init?(coder: NSCoder) { nil }
    override var intrinsicContentSize: NSSize { NSSize(width: 28, height: 28) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(_ presentation: AutoRecordPresentation) {
        guard self.presentation != presentation else { return }
        self.presentation = presentation
        updateLayers()
        updateAnimation()
    }

    override func layout() {
        super.layout()
        updateLayers()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateLayers()
        updateAnimation()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLayers()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateLayers()
    }

    func stopAnimation() { dot.removeAnimation(forKey: Self.danceKey) }

    private func updateLayers() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let diameter = presentation.isRecording ? Self.recordingDotDiameter : Self.idleDotDiameter
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let scale = window?.backingScaleFactor ?? 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.contentsScale = scale
        ring.frame = bounds
        ring.path = CGPath(ellipseIn: CGRect(x: center.x - 12, y: center.y - 12,
                                            width: 24, height: 24), transform: nil)
        ring.strokeColor = (presentation.isRecording
            ? NSColor(srgbRed: 1, green: 0.24, blue: 0.28, alpha: dark ? 0.60 : 0.42)
            : NSColor(calibratedWhite: dark ? 0.70 : 0.38, alpha: 0.60)).cgColor
        ring.shadowColor = NSColor.systemRed.cgColor
        ring.shadowOpacity = presentation.isRecording ? 0.20 : 0
        ring.shadowRadius = 2
        ring.shadowOffset = .zero
        dot.contentsScale = scale
        dot.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        dot.position = center
        dot.cornerRadius = diameter / 2
        dot.colors = [
            NSColor(srgbRed: 1, green: 0.30, blue: 0.34, alpha: 1).cgColor,
            NSColor(srgbRed: 0.88, green: 0.10, blue: 0.16, alpha: 1).cgColor,
        ]
        CATransaction.commit()
    }

    private func updateAnimation() {
        guard presentation.animates, window != nil else {
            stopAnimation()
            return
        }
        guard !hasActiveAnimations else { return }
        let dance = CAKeyframeAnimation(keyPath: "position")
        // Two small alternating hops, with a short landing at the center.
        dance.values = [CGPoint.zero, CGPoint(x: -1.6, y: 2), .zero,
                        .zero, CGPoint(x: 1.6, y: 2), .zero, .zero]
            .map { NSValue(point: $0) }
        dance.keyTimes = [0, 0.18, 0.34, 0.50, 0.68, 0.84, 1]
        dance.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 6)
        dance.duration = 1.6
        dance.repeatCount = .infinity
        dance.isAdditive = true
        dot.add(dance, forKey: Self.danceKey)
    }
}
