import AppKit
import Foundation
import QuartzCore

@MainActor private final class AutoRecordFixtureWindow: NSWindow {
    override var backingScaleFactor: CGFloat { 2 }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// The real indicator and compositor, in this process's non-key offscreen
/// windows. No application activation, user preferences, clipboard or input.
@main @MainActor private final class AutoRecordIndicatorTests: NSObject, NSApplicationDelegate {
    private static var checks = 0
    private static var maximumMotionDistance: CGFloat = 0
    private var result: Int32 = 0

    static func main() {
        let application = NSApplication.shared
        let delegate = AutoRecordIndicatorTests()
        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
        exit(delegate.result)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await Self.run() }
            catch {
                result = 1
                fputs("Auto Record indicator QA failed: \(error)\n", stderr)
            }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "AutoRecordIndicatorTests", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard condition() else { throw failure(message) }
    }

    private static func presentation(running: Bool = true, enabled: Bool = true,
                                     paused: Bool = false, visible: Bool = true,
                                     reduceMotion: Bool = false) -> AutoRecordPresentation {
        AutoRecordPresentation(runtimeIsRunning: running, isEnabled: enabled,
                               isPaused: paused, isVisible: visible, reduceMotion: reduceMotion)
    }

    private static func stateChecks() throws {
        for running in [false, true] {
            for enabled in [false, true] {
                for paused in [false, true] {
                    for visible in [false, true] {
                        for reduced in [false, true] {
                            let value = presentation(running: running, enabled: enabled, paused: paused,
                                                     visible: visible, reduceMotion: reduced)
                            let context = "runtime=\(running), enabled=\(enabled), paused=\(paused), visible=\(visible), reduced=\(reduced)"
                            try expect(value.isRecording == (running && enabled && !paused),
                                       "Recording represents a running, enabled, unpaused channel: \(context)")
                            try expect(value.animates == (value.isRecording && visible && !reduced),
                                       "Motion requires recording, visibility and unrestricted motion: \(context)")
                        }
                    }
                }
            }
        }
        try expect(!presentation(running: false).isRecording,
                   "Enabled ready or permission-blocked screenshot capture cannot claim to be recording")
        try expect(presentation().isRecording,
                   "A running clipboard channel still records while screenshot access is unavailable")
        try expect(presentation() == presentation(), "Equivalent presentations compare equal")
        try expect(AutoRecordIndicatorView.idleDotDiameter == 8
                   && AutoRecordIndicatorView.recordingDotDiameter == 16
                   && AutoRecordIndicatorView.recordingDotDiameter == 2 * AutoRecordIndicatorView.idleDotDiameter,
                   "Recording doubles the dot diameter from eight to sixteen points")
    }

    private static func window(containing view: NSView) -> AutoRecordFixtureWindow {
        let window = AutoRecordFixtureWindow(contentRect: NSRect(x: -20_000, y: -20_000,
            width: view.bounds.width, height: view.bounds.height),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.contentView = view
        window.orderFront(nil)
        return window
    }

    private static func settle(_ view: NSView, milliseconds: Int = 50) async throws {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        CATransaction.flush()
        try await Task.sleep(for: .milliseconds(milliseconds))
        CATransaction.flush()
    }

    private static func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }

    private static func expectStopped(_ indicator: AutoRecordIndicatorView, label: String) async throws {
        try await settle(indicator)
        let center = CGPoint(x: indicator.bounds.midX, y: indicator.bounds.midY)
        try expect(!indicator.hasActiveAnimations, "\(label) removes the native dance animation")
        for _ in 0..<3 {
            try await Task.sleep(for: .milliseconds(55))
            try expect(distance(indicator.dotPresentationPosition, center) < 0.05,
                       "\(label) resets and retains the centered dot; actual=\(indicator.dotPresentationPosition), center=\(center)")
        }
    }

    private static func nativeChecks() async throws {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 80, height: 80))
        let indicator = AutoRecordIndicatorView(frame: NSRect(x: 26, y: 26, width: 28, height: 28))
        indicator.configure(presentation())
        try expect(!indicator.hasActiveAnimations && indicator.window == nil,
                   "An unattached recording indicator does not start compositor work")
        host.addSubview(indicator)
        let fixtureWindow = window(containing: host)
        defer {
            indicator.stopAnimation()
            fixtureWindow.orderOut(nil)
            fixtureWindow.contentView = nil
            fixtureWindow.close()
        }
        try await settle(host)
        try expect(fixtureWindow.isVisible && !fixtureWindow.isKeyWindow && !fixtureWindow.canBecomeKey,
                   "The private offscreen fixture is visible to AppKit without taking keyboard focus")
        try expect(indicator.presentation == presentation() && indicator.dotDiameter == 16,
                   "The attached recording view retains its presentation and real sixteen-point layer bounds")
        try expect(indicator.bounds.size == NSSize(width: 28, height: 28)
                   && indicator.intrinsicContentSize == NSSize(width: 28, height: 28),
                   "Recording remains inside the fixed twenty-eight-point canvas")
        try expect(indicator.hitTest(CGPoint(x: 14, y: 14)) == nil
                   && indicator.hitTest(CGPoint(x: 1, y: 1)) == nil
                   && !indicator.isAccessibilityElement(),
                   "The decorative native indicator adds no input target or accessibility element")
        try expect(indicator.hasActiveAnimations, "Attachment starts the real Core Animation dance")

        let center = CGPoint(x: indicator.bounds.midX, y: indicator.bounds.midY)
        var samples: [CGPoint] = []
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(90))
            CATransaction.flush()
            samples.append(indicator.dotPresentationPosition)
        }
        maximumMotionDistance = samples.map { distance($0, center) }.max() ?? 0
        let spread = samples.flatMap { first in samples.map { distance(first, $0) } }.max() ?? 0
        try expect(maximumMotionDistance > 0.5 && spread > 0.5,
                   "Native presentation positions visibly change over real elapsed time; maxDistance=\(maximumMotionDistance), spread=\(spread), samples=\(samples)")
        let allowedCenters = indicator.bounds.insetBy(dx: indicator.dotDiameter / 2, dy: indicator.dotDiameter / 2)
        try expect(samples.allSatisfy { allowedCenters.contains($0) },
                   "Every sampled dancing dot remains inside its native canvas")

        for (label, value, diameter) in [
            ("Disabled", presentation(enabled: false), CGFloat(8)),
            ("Paused", presentation(paused: true), CGFloat(8)),
            ("Ready or permission blocked", presentation(running: false), CGFloat(8)),
            ("Reduced motion", presentation(reduceMotion: true), CGFloat(16)),
            ("Hidden presentation", presentation(visible: false), CGFloat(16))
        ] {
            indicator.configure(presentation())
            try await settle(indicator)
            try expect(indicator.hasActiveAnimations, "Recording resumes before the \(label) transition")
            indicator.configure(value)
            try expect(indicator.dotDiameter == diameter && indicator.bounds.size == NSSize(width: 28, height: 28),
                       "\(label) has the correct dot diameter without resizing its canvas")
            try await expectStopped(indicator, label: label)
        }

        indicator.configure(presentation())
        try await settle(indicator)
        try expect(indicator.hasActiveAnimations, "Recording restarts before detachment")
        indicator.removeFromSuperview()
        try expect(indicator.window == nil && indicator.dotDiameter == 16,
                   "Detachment retains the recording size while releasing its window")
        try await expectStopped(indicator, label: "Detached indicator")
        host.addSubview(indicator)
        try await settle(host)
        try expect(indicator.window === fixtureWindow && indicator.hasActiveAnimations,
                   "Reattachment restarts a still-visible recording presentation")
        indicator.stopAnimation()
        try await expectStopped(indicator, label: "Explicit representable teardown")
    }

    private static func renderStrips() async throws {
        guard let path = ProcessInfo.processInfo.environment["DABIN_AUTO_RECORD_RENDER_DIR"], !path.isEmpty else { return }
        let output = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var records: [[String: Any]] = []
        for dark in [false, true] {
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
            let canvas = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 100))
            canvas.appearance = appearance
            canvas.wantsLayer = true
            appearance.performAsCurrentDrawingAppearance {
                canvas.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            }
            for (index, recording) in [false, true].enumerated() {
                let x = CGFloat(index) * 120
                let indicator = AutoRecordIndicatorView(frame: NSRect(x: x + 46, y: 47, width: 28, height: 28))
                indicator.configure(presentation(running: recording, enabled: recording, reduceMotion: true))
                canvas.addSubview(indicator)
                let label = NSTextField(labelWithString: recording ? "Recording" : "Off")
                label.frame = NSRect(x: x + 8, y: 19, width: 104, height: 19)
                label.alignment = .center
                label.font = .systemFont(ofSize: 12, weight: .medium)
                label.textColor = .labelColor
                canvas.addSubview(label)
            }
            let fixtureWindow = window(containing: canvas)
            defer {
                fixtureWindow.orderOut(nil)
                fixtureWindow.contentView = nil
                fixtureWindow.close()
            }
            fixtureWindow.appearance = appearance
            try await settle(canvas)
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 480, pixelsHigh: 200,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
                throw failure("Could not allocate the native indicator render strip")
            }
            bitmap.size = canvas.bounds.size
            appearance.performAsCurrentDrawingAppearance { canvas.cacheDisplay(in: canvas.bounds, to: bitmap) }
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                throw failure("Could not encode the native indicator render strip")
            }
            let filename = "auto-record-\(dark ? "dark" : "light")-idle-recording@2x.png"
            try png.write(to: output.appendingPathComponent(filename), options: .atomic)
            records.append(["filename": filename, "appearance": dark ? "dark" : "light",
                            "idleDotDiameter": 8, "recordingDotDiameter": 16, "scale": 2])
        }
        let manifest: [String: Any] = ["checks": checks, "motionMaxDistance": maximumMotionDistance,
            "privacy": "Own-process native indicator, private offscreen non-key windows; no user settings, clipboard or input.",
            "renders": records]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("manifest.json"), options: .atomic)
        print("Auto Record native render strips: \(output.path)")
    }

    private static func run() async throws {
        try stateChecks()
        try await nativeChecks()
        try await renderStrips()
        print("PASS: \(checks) Auto Record state, native geometry, compositor motion, reduced-motion and lifecycle checks")
    }
}
