import AppKit
import CoreText
import Foundation
import QuartzCore

/// An isolated native animation render, never a recording of the installed app
/// or the user's desktop. The character and all its motion are production code.
@MainActor private final class IslandPreviewWindow: NSWindow {
    override var backingScaleFactor: CGFloat { 2 }
}

@main @MainActor
private final class IslandPlaygroundRender: NSObject, NSApplicationDelegate {
    private struct Failure: Error { let message: String }
    private struct Shot {
        let identifier: String
        let title: String
        let subtitle: String
        let reaction: AutoCaptureRobotReaction?
        let count: Int
    }
    private struct Sample {
        let title: String
        let time: Double
        let image: CGImage
    }
    private var exitCode = 0
    private let stageSize = CGSize(width: 232, height: 150)
    private let filmSize = CGSize(width: 900, height: 600)
    private let fps = 30
    private var samples: [Sample] = []
    private var records: [[String: Any]] = []
    private var shotRecords: [[String: Any]] = []

    static func main() {
        let app = NSApplication.shared
        let delegate = IslandPlaygroundRender()
        app.setActivationPolicy(.prohibited)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        exit(Int32(delegate.exitCode))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await run() }
            catch { exitCode = 1; fputs("Island preview render failed: \(error)\n", stderr) }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }

    private func run() async throws {
        guard CommandLine.arguments.count == 2 else { throw Failure(message: "Pass an output directory") }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let frames = output.appendingPathComponent("frames", isDirectory: true)
        try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        guard (try FileManager.default.contentsOfDirectory(atPath: frames.path)).isEmpty else {
            throw Failure(message: "Use an empty frame directory so old frames cannot enter a new render")
        }
        let character = RobotCharacterView(frame: CGRect(origin: .zero, size: stageSize), reduceMotion: { false })
        character.configureIslandStage(true)
        let window = IslandPreviewWindow(contentRect: CGRect(x: -10000, y: -10000,
            width: stageSize.width, height: stageSize.height), styleMask: .borderless,
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = character
        window.orderFront(nil)
        defer {
            character.stopMotion()
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        character.layoutSubtreeIfNeeded()
        character.displayIfNeeded()
        CATransaction.flush()
        try await Task.sleep(for: .milliseconds(150))

        let shots: [Shot] = [
            Shot(identifier: "swing-snack", title: "Swing & snack",
                 subtitle: "A little acrobat with an appetite.", reaction: .quickBite, count: 1),
            Shot(identifier: "slip-catch", title: "Slip. Catch. Pretend that was planned.",
                 subtitle: "Three captures. One very determined robot.", reaction: .oversizedBite, count: 3),
            Shot(identifier: "ledge-shimmy", title: "The ledge shuffle",
                 subtitle: "That snack is not getting away.", reaction: .escapingCapture, count: 1),
            Shot(identifier: "upside-down-peek", title: "Just checking on you",
                 subtitle: "A curious upside-down hello.", reaction: nil, count: 1)
        ]
        var frameIndex = 0
        for (shotIndex, shot) in shots.enumerated() {
            character.stopMotion()
            let performance = shot.reaction.map {
                AutoCaptureRobotPerformance.make(reaction: $0, variation: .standard,
                                                entrance: .top, reduceMotion: false)
            }
            let duration: TimeInterval
            if let performance {
                character.playAutoCaptureCelebration(performance)
                character.updateAutoCaptureCount(shot.count)
                duration = performance.totalDuration
            } else {
                duration = character.playIslandPeek()
            }
            CATransaction.flush()
            let started = CACurrentMediaTime()
            let count = Int(ceil((duration + 0.3) * Double(fps)))
            // Sample entrances, the widest act pose, eating, celebration and
            // retreat. Uniform time fractions can miss the slip/swing extremes.
            let sampleTimes: [Double]
            if let performance, let reaction = shot.reaction,
               let entrance = performance.phases.first(where: { $0.kind == .entrance }),
               let eating = performance.phases.first(where: { $0.kind == .eating(reaction) }),
               let celebration = performance.phases.first(where: { $0.kind == .reaction(reaction) }),
               let exit = performance.phases.first(where: { $0.kind == .exit }) {
                let extreme: Double = reaction == .quickBite ? 0.20 : (reaction == .oversizedBite ? 0.30 : 0.40)
                sampleTimes = [entrance.startTime + entrance.duration * 0.35,
                               eating.startTime + eating.duration * extreme,
                               eating.startTime + eating.duration * 0.56,
                               celebration.startTime + celebration.duration * 0.50,
                               exit.startTime + exit.duration * 0.52]
            } else {
                sampleTimes = [0.20, 0.40, 0.60, 0.80, 0.94].map { duration * $0 }
            }
            let sampleIndices = Set(sampleTimes.map { Int(($0 * Double(fps)).rounded()) })
            let startFrame = frameIndex
            var previous: Data?
            var changedFrameCount = 0
            var maximumDelta = 0
            var maximumOpaquePixels = 0
            var maximumLateness = 0.0
            var gapStopped = false
            for localIndex in 0..<count {
                let scheduled = Double(localIndex) / Double(fps)
                let remaining = started + scheduled - CACurrentMediaTime()
                if remaining > 0 { try await Task.sleep(for: .seconds(remaining)) }
                if scheduled >= duration && !gapStopped {
                    character.stopMotion()
                    CATransaction.flush()
                    gapStopped = true
                }
                let elapsed = CACurrentMediaTime() - started
                let lateness = max(0, elapsed - scheduled)
                maximumLateness = max(maximumLateness, lateness)
                let (stage, raster, opaquePixels) = try stageFrame(character)
                let delta = previous.map { changedBytes($0, raster) } ?? 0
                previous = raster
                if scheduled < duration {
                    if delta > 40 { changedFrameCount += 1 }
                    maximumDelta = max(maximumDelta, delta)
                    maximumOpaquePixels = max(maximumOpaquePixels, opaquePixels)
                }
                let film = try filmFrame(stage: stage, shot: shot, index: shotIndex,
                                         progress: min(1, scheduled / duration))
                let filename = String(format: "frame-%05d.png", frameIndex)
                try png(film, to: frames.appendingPathComponent(filename))
                if sampleIndices.contains(localIndex), let image = film.cgImage {
                    samples.append(Sample(title: shot.title, time: Double(frameIndex) / Double(fps), image: image))
                }
                records.append(["frame": frameIndex, "file": "frames/\(filename)",
                    "videoSeconds": Double(frameIndex) / Double(fps), "shot": shot.identifier,
                    "scheduledShotSeconds": scheduled, "actualShotSeconds": elapsed,
                    "latenessSeconds": lateness, "changedStageBytes": delta,
                    "visibleStagePixels": opaquePixels, "isGap": scheduled >= duration])
                frameIndex += 1
            }
            guard maximumOpaquePixels > 200, changedFrameCount >= 6, maximumDelta > 100 else {
                throw Failure(message: "\(shot.identifier) did not produce visible native motion")
            }
            // Absolute deadlines avoid accumulated render drift. Large misses
            // require another run instead of silently presenting slow samples.
            guard maximumLateness < 0.25 else {
                throw Failure(message: "\(shot.identifier) missed its native sample deadline by \(maximumLateness)s")
            }
            shotRecords.append(["identifier": shot.identifier, "title": shot.title,
                "reaction": shot.reaction?.rawValue ?? "island-peek", "captureCount": shot.count,
                "startFrame": startFrame, "frameCount": count, "nativeDurationSeconds": duration,
                "changedFrameCount": changedFrameCount, "maximumChangedStageBytes": maximumDelta,
                "maximumVisibleStagePixels": maximumOpaquePixels, "maximumLatenessSeconds": maximumLateness,
                "phases": performance?.phases.map {
                    ["id": $0.id, "startSeconds": $0.startTime, "durationSeconds": $0.duration] as [String: Any]
                } ?? []])
            print("RENDERED \(shot.identifier): \(count) frames; \(changedFrameCount) visibly changing")
        }
        try contactSheet(to: output.appendingPathComponent("contact-sheet.png"))
        let manifest: [String: Any] = [
            "renderMethod": "Real-time production Core Animation presentation layers in an isolated offscreen native window",
            "scope": "Native test render with a fictional vector desktop, not the installed app or a screen recording",
            "editorialRobotMotion": false, "networkUsed": false, "generalClipboardUsed": false,
            "width": 900, "height": 600, "fps": fps, "frameCount": frameIndex,
            "durationSeconds": Double(frameIndex) / Double(fps),
            "logicalStage": ["width": 232, "height": 150], "nativeRasterScale": 2,
            "presentationLayerRequired": true,
            "contactSheetTimes": samples.map(\.time), "shots": shotRecords, "frames": records
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("native-render.json"), options: .atomic)
        print("PASS: \(frameIndex) native frames at \(fps) fps")
    }

    private func bitmap(width: Int, height: Int, logicalSize: CGSize? = nil) throws -> NSBitmapImageRep {
        guard let value = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let bytes = value.bitmapData else {
            throw Failure(message: "Cannot allocate native bitmap")
        }
        bytes.initialize(repeating: 0, count: value.bytesPerRow * value.pixelsHigh)
        value.size = logicalSize ?? CGSize(width: width, height: height)
        return value
    }

    private func stageFrame(_ character: RobotCharacterView) throws -> (CGImage, Data, Int) {
        character.layoutSubtreeIfNeeded()
        character.displayIfNeeded()
        let value = try bitmap(width: 464, height: 300, logicalSize: stageSize)
        guard let context = NSGraphicsContext(bitmapImageRep: value),
              let presentation = character.layer?.presentation(), let bytes = value.bitmapData else {
            throw Failure(message: "The live Core Animation presentation layer is unavailable")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        // The bitmap's logical size already supplies the 2x drawing transform.
        presentation.render(in: context.cgContext)
        NSGraphicsContext.restoreGraphicsState()
        guard let image = value.cgImage else { throw Failure(message: "Cannot extract the live stage") }
        var visible = 0
        for y in 0..<value.pixelsHigh {
            for x in 0..<value.pixelsWide where bytes[y * value.bytesPerRow + x * 4 + 3] > 24 { visible += 1 }
        }
        return (image, Data(bytes: bytes, count: value.bytesPerRow * value.pixelsHigh), visible)
    }

    private func filmFrame(stage: CGImage, shot: Shot, index: Int, progress: Double) throws -> NSBitmapImageRep {
        let value = try bitmap(width: Int(filmSize.width), height: Int(filmSize.height))
        guard let context = NSGraphicsContext(bitmapImageRep: value) else { throw Failure(message: "No film context") }
        let cg = context.cgContext
        cg.setFillColor(color(0x0C101B)); cg.fill(CGRect(origin: .zero, size: filmSize))
        text("DaBin", x: 30, y: 551, size: 29, weight: "HelveticaNeue-Bold", color: 0xF0ECFF, in: cg)
        text("ISLAND PLAYGROUND", x: 138, y: 557, size: 12, weight: "HelveticaNeue-Medium", color: 0xB49BFF, in: cg)
        text("A small robot. A lot of personality.", x: 31, y: 529, size: 15, color: 0xA7B0C5, in: cg)
        rounded(CGRect(x: 735, y: 548, width: 133, height: 28), radius: 14, fill: 0x25223C, in: cg)
        text("NATIVE MOTION", x: 751, y: 557, size: 10, weight: "HelveticaNeue-Medium", color: 0xCBB9FF, in: cg)

        // Only the backdrop is a fixture. Both placements below use the exact
        // same live robot pixels, at 2x and 1x logical scale respectively.
        rounded(CGRect(x: 24, y: 153, width: 536, height: 365), radius: 20, fill: 0x20283A, in: cg)
        let closeScreen = CGRect(x: 36, y: 169, width: 512, height: 338)
        desktop(closeScreen, in: cg)
        island(centerX: 292, undersideY: 471, width: 370, height: 36, in: cg)
        cg.interpolationQuality = .high
        cg.draw(stage, in: CGRect(x: 60, y: 171, width: 464, height: 300))
        text("2× CLOSE-UP", x: 42, y: 157, size: 9, weight: "HelveticaNeue-Medium", color: 0xA9B5CD, in: cg)

        text("IN CONTEXT", x: 592, y: 484, size: 11, weight: "HelveticaNeue-Medium", color: 0xB7C4DD, in: cg)
        text("Actual size · fictional desktop", x: 592, y: 463, size: 12, color: 0x8998B5, in: cg)
        rounded(CGRect(x: 578, y: 229, width: 280, height: 211), radius: 13, fill: 0x363F52, in: cg)
        rounded(CGRect(x: 583, y: 234, width: 270, height: 201), radius: 10, fill: 0x090D15, in: cg)
        desktop(CGRect(x: 590, y: 246, width: 256, height: 183), in: cg)
        island(centerX: 718, undersideY: 411, width: 185, height: 18, in: cg)
        cg.draw(stage, in: CGRect(x: 602, y: 261, width: 232, height: 150))
        rounded(CGRect(x: 568, y: 219, width: 300, height: 13), radius: 5, fill: 0x65718B, in: cg)
        rounded(CGRect(x: 689, y: 225, width: 58, height: 5), radius: 2, fill: 0x252D40, in: cg)

        rounded(CGRect(x: 26, y: 42, width: 848, height: 94), radius: 17, fill: 0x192131, in: cg)
        text(String(format: "%02d", index + 1), x: 45, y: 91, size: 16, weight: "HelveticaNeue-Medium", color: 0xAE91FF, in: cg)
        text(shot.title, x: 85, y: 92, size: 22, weight: "HelveticaNeue-Medium", color: 0xF0F3FB, in: cg)
        text(shot.subtitle, x: 86, y: 67, size: 14, color: 0xA6B4CB, in: cg)
        rounded(CGRect(x: 44, y: 49, width: 812, height: 3), radius: 1.5, fill: 0x2F3A50, in: cg)
        if progress > 0 {
            rounded(CGRect(x: 44, y: 49, width: 812 * progress, height: 3), radius: 1.5, fill: 0xAE91FF, in: cg)
        }
        text("Native test render · fictional desktop · no screen recording", x: 29, y: 17, size: 10, color: 0x6D7D97, in: cg)
        return value
    }

    private func desktop(_ rect: CGRect, in context: CGContext) {
        context.saveGState()
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 5, cornerHeight: 5, transform: nil)); context.clip()
        let colors = [color(0x182A40), color(0x27364D), color(0x252640)] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.maxY),
                                       end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
        }
        context.setFillColor(color(0x526585, alpha: 0.11))
        context.fillEllipse(in: CGRect(x: rect.minX - rect.width * 0.2, y: rect.minY - rect.height * 0.7,
                                      width: rect.width * 1.3, height: rect.height * 1.3))
        context.restoreGState()
    }

    private func island(centerX: CGFloat, undersideY: CGFloat, width: CGFloat, height: CGFloat, in context: CGContext) {
        // The island ends exactly at the native stage's upper edge. Nothing is
        // painted over the animation to fake a grip or hide an incorrect pose.
        rounded(CGRect(x: centerX - width / 2, y: undersideY, width: width, height: height),
                radius: height * 0.45, fill: 0x080A10, in: context)
        context.setFillColor(color(0x080A10))
        context.fill(CGRect(x: centerX - width / 2, y: undersideY + height / 2, width: width, height: height / 2))
        context.setFillColor(color(0x213049))
        context.fillEllipse(in: CGRect(x: centerX - height * 0.10, y: undersideY + height * 0.43,
                                      width: height * 0.20, height: height * 0.20))
    }

    private func rounded(_ rect: CGRect, radius: CGFloat, fill: UInt32, in context: CGContext) {
        context.setFillColor(color(fill))
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.fillPath()
    }

    private func text(_ string: String, x: CGFloat, y: CGFloat, size: CGFloat,
                      weight: String = "HelveticaNeue", color hex: UInt32, in context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(weight as CFString, size, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color(hex)
        ]
        context.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes)), context)
    }

    private func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: alpha)
    }

    private func png(_ bitmap: NSBitmapImageRep, to path: URL) throws {
        guard let bytes = bitmap.representation(using: .png, properties: [:]) else { throw Failure(message: "PNG encoding failed") }
        try bytes.write(to: path, options: .atomic)
    }

    private func changedBytes(_ first: Data, _ second: Data) -> Int {
        first.withUnsafeBytes { left in
            second.withUnsafeBytes { right in
                let a = left.bindMemory(to: UInt8.self), b = right.bindMemory(to: UInt8.self)
                var changed = 0
                for index in 0..<min(a.count, b.count) where a[index] != b[index] { changed += 1 }
                return changed
            }
        }
    }

    private func contactSheet(to output: URL) throws {
        let columns = 3, width = 956, cellWidth = 300, cellHeight = 200, gap = 14, caption = 30
        let rows = (samples.count + columns - 1) / columns
        let height = 54 + rows * (cellHeight + caption + gap) + gap
        let value = try bitmap(width: width, height: height)
        guard let context = NSGraphicsContext(bitmapImageRep: value) else { throw Failure(message: "No contact-sheet context") }
        let cg = context.cgContext
        cg.setFillColor(color(0x0C101B)); cg.fill(CGRect(x: 0, y: 0, width: width, height: height))
        text("DaBin · actual native animation frames", x: 15, y: CGFloat(height - 34), size: 20, color: 0xE5EAF5, in: cg)
        for (index, sample) in samples.enumerated() {
            let x = CGFloat(gap + (index % columns) * (cellWidth + gap))
            let y = CGFloat(height - 54 - cellHeight - (index / columns) * (cellHeight + caption + gap))
            cg.draw(sample.image, in: CGRect(x: x, y: y, width: CGFloat(cellWidth), height: CGFloat(cellHeight)))
            text(String(format: "%.2fs · %@", sample.time, sample.title), x: x, y: y - 19,
                 size: 10, color: 0xA9B7CE, in: cg)
        }
        try png(value, to: output)
    }
}
