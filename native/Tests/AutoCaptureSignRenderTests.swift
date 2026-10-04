import AppKit
import Foundation
import QuartzCore

/// Native fixtures exercise the same compositor samples as the live sign. They
/// do not inspect the desktop, clipboard, capture archive, or installed app.
@main struct AutoCaptureSignRenderTests {
    @MainActor private static var checks = 0
    @MainActor private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard condition() else { throw NSError(domain: "AutoCaptureSignRenderTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    @MainActor private static func render(_ view: NSView, name: String, directory: URL) throws {
        view.layoutSubtreeIfNeeded()
        CATransaction.flush()
        view.displayIfNeeded()
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(view.bounds.width * 2), pixelsHigh: Int(view.bounds.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw NSError(domain: "AutoCaptureSignRenderTests", code: 2)
        }
        bitmap.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "AutoCaptureSignRenderTests", code: 3)
        }
        try data.write(to: directory.appendingPathComponent(name + ".png"), options: .atomic)
    }

    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.finishLaunching()
        let directory = ProcessInfo.processInfo.environment["DABIN_CAPTURE_SIGN_RENDER_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? URL(fileURLWithPath: "../docs/qa/auto-capture-sign-2026-10-03/renders", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stage = AutoCaptureSignView(frame: CGRect(x: 0, y: 0, width: 224, height: 166))
        let host = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 224, height: 166),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false
        host.isOpaque = false
        host.backgroundColor = .clear
        host.contentView = stage
        host.orderFront(nil)
        defer { stage.stop(); host.orderOut(nil); host.contentView = nil; host.close() }
        let island = CGRect(x: 40, y: 132, width: 144, height: 34)
        let variation = AutoCaptureRobotVariation.standard
        for theme in [NSAppearance.Name.aqua, .darkAqua] {
            host.appearance = NSAppearance(named: theme)
            let name = theme == .aqua ? "light" : "dark"
            for reaction in AutoCaptureSignReaction.allCases {
                let performance = AutoCaptureSignPerformance.make(reaction: reaction, variation: variation,
                                                                  entrance: .top, reduceMotion: false)
                let receipt = AutoCaptureSignReceipt(kind: .screenshot, count: 3)
                stage.begin(performance: performance, receipt: receipt, islandRect: island, accent: .systemPurple)
                try expect(stage.hasActiveAnimations, "Each normal sign starts finite compositor tracks")
                try expect(stage.hitTest(CGPoint(x: 100, y: 60)) == nil, "Decorative views never intercept input")
                for (label, time) in [("peek", 0.06), ("reaction", 0.38), ("hold", 0.66)] {
                    stage.applySample(normalizedTime: time)
                    stage.layoutSubtreeIfNeeded()
                    let sample = performance.frame(atNormalizedTime: time)
                    try expect(abs(stage.actualSignTransform.m41 - sample.signTranslationX) < 0.001
                               && abs(stage.actualSignTransform.m42 - sample.signTranslationY) < 0.001
                               && abs(stage.actualRobotTransform.m41 - sample.robotTranslationX) < 0.001
                               && abs(stage.actualRobotTransform.m42 - sample.robotTranslationY) < 0.001,
                               "A native layout pass must preserve the sign transform and its physical grip")
                    if label == "hold" {
                        try expect(stage.bounds.contains(stage.signFrame), "Readable sign fits the stage: \(reaction)")
                        try expect(!stage.signFrame.intersects(island), "Hardware cannot obscure the readable message")
                        try expect(stage.hasArmConnection && stage.nativeArmsAreHidden,
                                   "Jointed grip arms replace the normal arms, without duplicate hands")
                        try expect(stage.signMessage == "Screenshot saved!" && stage.countText == "×3",
                                   "The screenshot receipt and exact aggregate remain visible")
                        try expect(stage.messageFontSize == 12, "Native twelve-point receipt remains readable")
                        try expect(stage.messageTextFrame.width >= stage.messageRequiredWidth
                                   && stage.countTextFrame.width >= stage.countRequiredWidth,
                                   "The full message and aggregate count fit their native text cells")
                    }
                    try render(stage, name: "\(name)-\(reaction.rawValue)-\(label)", directory: directory)
                }
                stage.stop()
                try expect(stage.isHidden && !stage.hasActiveAnimations && stage.receipt == nil,
                           "Stopping clears layers, payload, and animation tracks")
            }
        }
        host.appearance = NSAppearance(named: .darkAqua)
        for reduced in [false, true] {
            let performance = AutoCaptureSignPerformance.make(reaction: .checkmarkStamp, variation: variation,
                                                              entrance: .right, reduceMotion: reduced)
            stage.begin(performance: performance, receipt: AutoCaptureSignReceipt(kind: .clipboard),
                        islandRect: nil, accent: .systemTeal)
            stage.applySample(normalizedTime: 0.66)
            try expect(!stage.usesIsland && stage.reduceMotion == reduced, "External fallback does not invent a notch")
            try expect(stage.signMessage == "Copied!" && stage.countText == nil, "Single copy receipt is concise")
            try expect(stage.bounds.contains(stage.signFrame), "External receipt fits safe stage")
            try render(stage, name: reduced ? "external-reduced-motion" : "external-clipboard", directory: directory)
        }
        for count in [1, 3, 125, 1234, Int.max] {
            stage.updateReceipt(AutoCaptureSignReceipt(kind: .mixed, count: count))
            try expect(stage.accessibilityStatus == (count == 1 ? "Capture saved" : "\(count) captures saved"),
                       "Accessible status preserves every successfully stored capture")
            try expect(stage.messageTextFrame.width >= stage.messageRequiredWidth
                       && (count == 1 || stage.countTextFrame.width >= stage.countRequiredWidth),
                       "Large counts remain fully legible without truncation")
            try render(stage, name: "mixed-count-\(count)", directory: directory)
        }
        stage.stop()
        try expect(!stage.hasActiveAnimations && stage.signMessage.isEmpty && stage.countText == nil,
                   "Final cleanup retains no transient receipt")
        print("PASS: \(checks) native confirmation-sign checks; renders: \(directory.path)")
    }
}
