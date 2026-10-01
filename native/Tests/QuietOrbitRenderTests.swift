import AppKit
import Foundation
import QuartzCore

/// Renders the production character only. No capture archive, pasteboard,
/// permissions, installed application, or real desktop screenshot is involved.
@main
struct QuietOrbitRenderTests {
    @MainActor private static var checks = 0
    @MainActor private static var windows: [NSWindow] = []

    @MainActor private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard condition() else {
            throw NSError(domain: "DaBinQuietOrbitRenderTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    @MainActor private static func allLayers(_ layer: CALayer?) -> [CALayer] {
        guard let layer else { return [] }
        return [layer] + (layer.sublayers ?? []).flatMap { allLayers($0) }
    }

    @MainActor private static func host(_ view: NSView) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000,
                                                   width: view.frame.width, height: view.frame.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = view
        window.orderFront(nil)
        windows.append(window)
        return window
    }

    @MainActor private static func bitmap(_ view: NSView) throws -> NSBitmapImageRep {
        view.layoutSubtreeIfNeeded()
        CATransaction.flush()
        view.displayIfNeeded()
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(view.bounds.width * 2), pixelsHigh: Int(view.bounds.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw NSError(domain: "DaBinQuietOrbitRenderTests", code: 2)
        }
        bitmap.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap
    }

    @MainActor private static func pixelData(_ bitmap: NSBitmapImageRep) -> Data {
        Data(bytes: bitmap.bitmapData!, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    }

    @MainActor private static func image(_ bitmap: NSBitmapImageRep) -> NSImage {
        let image = NSImage(size: bitmap.size)
        image.addRepresentation(bitmap)
        return image
    }

    @MainActor private static func write(_ bitmap: NSBitmapImageRep, to url: URL) throws {
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "DaBinQuietOrbitRenderTests", code: 3)
        }
        try data.write(to: url)
    }

    @MainActor private static func renderPerches(output: URL) throws -> [String] {
        let stageSize = NSSize(width: 320, height: 96)
        let scene = QuietOrbitLayout(cameraIsland: CGRect(x: 94, y: 64, width: 132, height: 32),
                                     displayFrame: CGRect(origin: .zero, size: stageSize))!
        var rendered: [NSImage] = []
        var titles: [String] = []
        var files: [String] = []
        for (theme, color) in [("light", NSColor(calibratedWhite: 0.965, alpha: 1)),
                               ("dark", NSColor(calibratedWhite: 0.085, alpha: 1))] {
            for perch in QuietOrbitPerch.allCases {
                let stage = NSView(frame: CGRect(origin: .zero, size: stageSize))
                stage.wantsLayer = true
                stage.layer?.backgroundColor = color.cgColor
                stage.layer?.masksToBounds = true
                let robot = RobotCharacterView(frame: scene.robotFrame(for: perch), reduceMotion: { true })
                robot.configureQuietOrbit(true)
                stage.addSubview(robot)
                robot.send(.reveal(.top))
                robot.layoutSubtreeIfNeeded()
                if perch.isMirrored {
                    let mirror = CATransform3DMakeScale(-1, 1, 1)
                    robot.layer?.sublayers?.first?.transform = CATransform3DConcat(robot.layer!.sublayers!.first!.transform, mirror)
                }
                let camera = CALayer()
                camera.frame = scene.cameraIsland
                camera.backgroundColor = NSColor.black.cgColor
                camera.cornerRadius = 7
                stage.layer?.addSublayer(camera)
                _ = host(stage)
                let frame = try bitmap(stage)
                try expect(frame.pixelsWide == 640 && frame.pixelsHigh == 192,
                           "\(perch.rawValue) renders at native2x without upscaling an image")
                try expect(!robot.hasActiveAmbientMotion, "\(perch.rawValue) has no periodic idle task")
                let file = "quiet-orbit-\(perch.rawValue)-\(theme)@2x.png"
                try write(frame, to: output.appendingPathComponent(file))
                rendered.append(image(frame))
                titles.append("\(theme.capitalized) · \(perch.rawValue)")
                files.append(file)
                robot.stopMotion()
            }
        }
        let sheetSize = NSSize(width: 1280, height: 448)
        let sheet = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2560, pixelsHigh: 896,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        sheet.size = sheetSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
        NSColor(calibratedWhite: 0.16, alpha: 1).setFill()
        NSRect(origin: .zero, size: sheetSize).fill()
        for index in rendered.indices {
            let x = CGFloat(index % 4) * 320
            let y = sheetSize.height - CGFloat(index / 4 + 1) * 112
            rendered[index].draw(in: NSRect(x: x, y: y + 16, width: 320, height: 96))
            (titles[index] as NSString).draw(at: CGPoint(x: x + 12, y: y + 2), withAttributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: NSColor.white])
        }
        NSGraphicsContext.restoreGraphicsState()
        try write(sheet, to: output.appendingPathComponent("quiet-orbit-perches-contact-sheet@2x.png"))
        return files
    }

    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        defer {
            for window in windows {
                window.orderOut(nil); window.contentView = nil; window.close()
            }
        }
        let output = CommandLine.arguments.count > 1
            ? URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            : URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                .appendingPathComponent("build/qa/quiet-orbit", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let files = try renderPerches(output: output)

        let robot = RobotCharacterView(frame: CGRect(x: 0, y: 0, width: 51, height: 62), reduceMotion: { false })
        _ = host(robot)
        robot.send(.reveal(.top))
        try await Task.sleep(for: .seconds(0.4))
        let idleBefore = pixelData(try bitmap(robot))
        try await Task.sleep(for: .seconds(0.6))
        let idleAfter = pixelData(try bitmap(robot))
        try expect(idleBefore == idleAfter && !robot.hasActiveAmbientMotion,
                   "The settled quiet robot remains pixel-identical while idle")
        try expect(allLayers(robot.layer).allSatisfy { ($0.animationKeys() ?? []).isEmpty },
                   "Idle schedules no recurrent CA animation")

        var signatures: Set<String> = []
        for reaction in AutoCaptureRobotReaction.eatingReactions {
            let performance = AutoCaptureRobotPerformance.make(reaction: reaction, entrance: .top, reduceMotion: false)
            robot.playAutoCaptureCelebration(performance)
            let layers = allLayers(robot.layer)
            try expect(!layers.contains { $0.animation(forKey: "robot.island.body") != nil },
                       "\(reaction.rawValue) uses small local motion rather than the old underside rig")
            guard let track = layers.compactMap({ $0.animation(forKey: "robot.auto-success.body") as? CAKeyframeAnimation }).first,
                  let values = track.values as? [NSValue] else {
                throw NSError(domain: "DaBinQuietOrbitRenderTests", code: 4)
            }
            let signature = values.map { value -> String in
                let matrix = value.caTransform3DValue
                return "\(matrix.m11),\(matrix.m12),\(matrix.m22),\(matrix.m41),\(matrix.m42)"
            }.joined(separator: "|")
            signatures.insert(signature)
            try expect(layers.contains { $0.animation(forKey: "robot.auto-success.eating-token") != nil }
                       && layers.contains { $0.animation(forKey: "robot.auto-success.chewing-mouth") != nil },
                       "\(reaction.rawValue) keeps both eating token and facial reaction")
            robot.updateAutoCaptureCount(1234)
            try expect(robot.autoCaptureTokenCount == 1234
                       && layers.compactMap { $0 as? CATextLayer }.contains { $0.string as? String == "×1234" },
                       "\(reaction.rawValue) displays an accurate burst count")
            robot.stopMotion()
            try expect(allLayers(robot.layer).allSatisfy { ($0.animationKeys() ?? []).isEmpty },
                       "\(reaction.rawValue) interruption removes every animation")
        }
        try expect(signatures.count == 10, "All ten eating reactions retain distinct motion tracks")
        let reduced = RobotCharacterView(frame: robot.frame, reduceMotion: { true })
        reduced.playAutoCaptureCelebration(.make(reaction: .stackedCapture, entrance: .top, reduceMotion: true))
        let reducedTracks = allLayers(reduced.layer).flatMap { layer in
            (layer.animationKeys() ?? []).compactMap { layer.animation(forKey: $0) as? CAPropertyAnimation }
        }
        try expect(!reducedTracks.isEmpty && reducedTracks.allSatisfy { $0.keyPath == "opacity" },
                   "Reduce Motion animates only opacity, without token travel or body rotation")
        reduced.stopMotion()
        let manifest: [String: Any] = ["schemaVersion": 1, "checksPassed": checks,
            "renderedFiles": files + ["quiet-orbit-perches-contact-sheet@2x.png"],
            "renderMethod": "Production RobotCharacterView in offscreen synthetic windows at2x",
            "privacy": "No capture archive, clipboard content, or desktop screenshots were loaded.",
            "limitations": "Synthetic132×32housing; physical menu-bar overlap and realhardware checks are separate."]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("quiet-orbit-render-report.json"))
        print("PASS: \(checks) Quiet Orbit artwork, idle, reaction, burst-count, cleanup, and Reduce Motion checks passed. \(output.path)")
    }
}
