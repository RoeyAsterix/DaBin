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

    @MainActor private static func verifyTransitionArtworkGeometry() throws {
        func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.000_001 }
        let corner = RobotCharacterView.transitionArtworkFrame(
            in: CGRect(x: 0, y: 0, width: 72, height: 88).insetBy(dx: 4, dy: 4))
        try expect(near(corner.minX, 9.96) && near(corner.minY, 17.65)
                   && near(corner.width, 56.7) && near(corner.height, 45.75),
                   "Corner transition starts from visible artwork, including canvas centering and flipped y")
        let renderer = CGRect(x: -300, y: 200, width: 128, height: 200)
        let normal = RobotCharacterView.transitionArtworkFrame(in: renderer)
        let mirrored = RobotCharacterView.transitionArtworkFrame(in: renderer, mirrored: true)
        try expect(near(normal.minX, -288.08) && near(normal.minY, 247.3)
                   && near(normal.width, 113.4) && near(normal.height, 91.5),
                   "Transition mapping scales uniformly, centers taller canvases, and preserves negative display origins")
        try expect(near(mirrored.minX, 2 * renderer.midX - normal.maxX)
                   && near(mirrored.minY, normal.minY) && mirrored.size == normal.size,
                   "Left perches mirror only the asymmetric artwork's horizontal footprint")
        let scene = QuietOrbitLayout(cameraIsland: CGRect(x: 94, y: 64, width: 132, height: 32),
                                     displayFrame: CGRect(x: 0, y: 0, width: 320, height: 96))!
        for perch in QuietOrbitPerch.allCases {
            let global = RobotCharacterView.transitionArtworkFrame(in: scene.robotFrame(for: perch),
                mirrored: perch.isMirrored)
            let local = RobotCharacterView.transitionArtworkFrame(in: scene.robotFrame(for: perch, local: true),
                mirrored: perch.isMirrored)
            try expect(near(global.minX, local.minX + scene.panelFrame.minX)
                       && near(global.minY, local.minY + scene.panelFrame.minY)
                       && global.size == local.size,
                       "\(perch.rawValue) live and hidden-fallback transition endpoints share exact renderer geometry")
        }
        try expect(RobotCharacterView.transitionArtworkFrame(in: .zero) == .zero,
                   "An empty renderer has no visible transition footprint")
    }

    @MainActor private static func verifyMovingTransitionSource() async throws {
        func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.05 }
        func sameRect(_ a: CGRect, _ b: CGRect) -> Bool {
            near(a.minX, b.minX) && near(a.minY, b.minY)
                && near(a.width, b.width) && near(a.height, b.height)
        }
        let scene = QuietOrbitLayout(cameraIsland: CGRect(x: 94, y: 64, width: 132, height: 32),
                                     displayFrame: CGRect(x: 0, y: 0, width: 320, height: 96))!
        for perch in [QuietOrbitPerch.bottom, .left] {
            let robot = RobotView(frame: CGRect(origin: .zero, size: scene.panelFrame.size), reduceMotion: { true })
            robot.configureOrbit(scene, perch: perch)
            _ = host(robot)
            robot.layoutSubtreeIfNeeded()
            guard let renderer = robot.subviews.compactMap({ $0 as? RobotCharacterView }).first,
                  let layer = renderer.layer else {
                throw NSError(domain: "DaBinQuietOrbitRenderTests", code: 5,
                              userInfo: [NSLocalizedDescriptionKey: "The transition source renderer is missing"])
            }
            let modelFrame = renderer.frame
            try expect(sameRect(layer.frame, modelFrame),
                       "\(perch.rawValue) backing-layer frame uses the renderer's parent coordinates")
            let modelBody = RobotCharacterView.transitionArtworkFrame(in: modelFrame, mirrored: perch.isMirrored)
            let position = layer.position
            let travel = CABasicAnimation(keyPath: "position")
            travel.fromValue = NSValue(point: position)
            travel.toValue = NSValue(point: CGPoint(x: position.x + 80, y: position.y + 40))
            travel.duration = 1
            travel.timingFunction = CAMediaTimingFunction(name: .linear)
            travel.speed = 0
            travel.timeOffset = 0.5
            travel.fillMode = .both
            travel.isRemovedOnCompletion = false
            layer.add(travel, forKey: "qa.frozenOrbitTravel")
            CATransaction.flush()
            // The explicit frozen midpoint, not elapsed wall time, determines
            // the geometry. Yield once for the native presentation tree commit.
            try await Task.sleep(for: .milliseconds(40))
            guard let presentedFrame = layer.presentation()?.frame else {
                throw NSError(domain: "DaBinQuietOrbitRenderTests", code: 6,
                              userInfo: [NSLocalizedDescriptionKey: "The active transition source has no presentation frame"])
            }
            try expect(near(presentedFrame.minX, modelFrame.minX + 40)
                       && near(presentedFrame.minY, modelFrame.minY + 20),
                       "\(perch.rawValue) source fixture has a fixed in-flight position distinct from its model frame")
            let expectedBody = RobotCharacterView.transitionArtworkFrame(in: presentedFrame, mirrored: perch.isMirrored)
            try expect(sameRect(robot.transitionBodyBounds, expectedBody)
                       && near(robot.transitionBodyBounds.minX, modelBody.minX + 40)
                       && near(robot.transitionBodyBounds.minY, modelBody.minY + 20),
                       "\(perch.rawValue) opening hands off from the currently drawn robot during orbit travel")
            layer.removeAnimation(forKey: "qa.frozenOrbitTravel")
            CATransaction.flush()
            try await Task.sleep(for: .milliseconds(40))
            try expect(sameRect(robot.transitionBodyBounds, modelBody),
                       "\(perch.rawValue) settled transition source returns to its ordinary artwork bounds")
            robot.stopFeedback()
        }
    }

    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        try verifyTransitionArtworkGeometry()
        defer {
            for window in windows {
                window.orderOut(nil); window.contentView = nil; window.close()
            }
        }
        try await verifyMovingTransitionSource()
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
