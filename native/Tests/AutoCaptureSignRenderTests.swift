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
        let historicalReactions: Set<String> = ["proud-raise", "oversized-unfold", "heavy-pull-down",
            "wrong-side-flip", "spin-to-face", "gentle-bonk", "hang-and-climb", "checkmark-stamp",
            "slide-overshoot", "proud-bow", "mechanical-billboard", "last-moment-catch"]
        try expect(AutoCaptureSignReaction.allCases.count == 15
                   && historicalReactions.isSubset(of: Set(AutoCaptureSignReaction.allCases.map(\.rawValue))),
                   "Three companion celebrations preserve the twelve historical render reactions")
        try expect(Set(AutoCaptureSignReaction.companionReactions.map(\.rawValue))
                   == Set(["happy-nod", "happy-wiggle", "happy-raise"]),
                   "Live companion saves rotate among the three requested readable gestures")
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
                        try expect(stage.signMessage == "Saved 3 items" && stage.countText == "×3"
                                   && stage.accessibilityStatus == "Saved 3 items",
                                   "An aggregate reports its exact saved-item count visibly and accessibly")
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
            try expect(stage.accessibilityStatus == (count == 1 ? "Capture saved" : "Saved \(count) items"),
                       "Accessible status preserves every successfully stored capture")
            try expect(stage.messageTextFrame.width >= stage.messageRequiredWidth
                       && (count == 1 || stage.countTextFrame.width >= stage.countRequiredWidth),
                       "Large counts remain fully legible without truncation")
            try render(stage, name: "mixed-count-\(count)", directory: directory)
        }
        for kind in AutoCaptureSignKind.allCases {
            stage.updateReceipt(AutoCaptureSignReceipt(kind: kind, count: 7))
            try expect(stage.signMessage == "Saved 7 items" && stage.accessibilityStatus == "Saved 7 items",
                       "Rapid saves use the same exact aggregate wording for \(kind.rawValue)")
        }
        stage.stop()
        var openCount = 0
        stage.onOpen = { openCount += 1 }
        stage.begin(performance: AutoCaptureSignPerformance.make(reaction: .happyNod, variation: variation,
                        entrance: .top, reduceMotion: false),
                    receipt: AutoCaptureSignReceipt(kind: .mixed, count: 3), islandRect: island, accent: .systemPurple)
        let steadyTarget = stage.interactionBounds
        try expect(!steadyTarget.isEmpty && stage.bounds.contains(steadyTarget),
                   "An interactive confirmation owns a bounded native target")
        let clickPoint = CGPoint(x: steadyTarget.midX, y: steadyTarget.midY)
        for time in [0.06, 0.38, 0.66, 0.95] {
            stage.applySample(normalizedTime: time)
            stage.layoutSubtreeIfNeeded()
            try expect(stage.interactionBounds == steadyTarget && steadyTarget.contains(clickPoint)
                       && stage.hitTest(stage.convert(clickPoint, to: stage.superview)) === stage,
                       "Sign motion keeps the same target at normalized time \(time)")
            let cameraPoint = CGPoint(x: island.midX, y: island.midY)
            try expect(stage.hitTest(stage.convert(cameraPoint, to: stage.superview)) == nil,
                       "Interactive confirmations preserve camera-housing pass-through")
            try expect(stage.hitTest(stage.convert(CGPoint(x: 1, y: 1), to: stage.superview)) == nil,
                       "The unused sign stage never becomes an invisible input blocker")
        }
        func click(_ count: Int) -> NSEvent {
            NSEvent.mouseEvent(with: .leftMouseDown, location: stage.convert(clickPoint, to: nil),
                modifierFlags: [], timestamp: Double(count), windowNumber: host.windowNumber, context: nil,
                eventNumber: count, clickCount: count, pressure: 1)!
        }
        stage.hitTest(stage.convert(clickPoint, to: stage.superview))?.mouseDown(with: click(1))
        try expect(openCount == 1, "One native confirmation click dispatches the immediate-open callback")
        stage.mouseDown(with: click(2))
        try expect(openCount == 1, "A second click in the same sequence does not dispatch another open")
        stage.stop()
        try expect(stage.hitTest(stage.convert(clickPoint, to: stage.superview)) == nil,
                   "Stopped confirmations cannot retain an invisible native target")
        stage.onOpen = nil
        stage.stop()
        try expect(!stage.hasActiveAnimations && stage.signMessage.isEmpty && stage.countText == nil,
                   "Final cleanup retains no transient receipt")
        print("PASS: \(checks) native confirmation-sign checks; renders: \(directory.path)")
    }
}
