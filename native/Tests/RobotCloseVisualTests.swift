import AppKit
import AVFoundation
import CoreVideo
import Foundation
import QuartzCore
import SwiftUI

@MainActor private final class ClosePreviewWindow: NSWindow {
    override var backingScaleFactor: CGFloat { 2 }
}

@MainActor private final class ClosePreviewReminders: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .undetermined }
    func requestAuthorization() async throws -> Bool { false }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}

/// Records actual opening and closing presentation layers at native 2x in an isolated
/// offscreen window. No screenshot of the desktop, editorial robot motion,
/// personal archive, global input, general pasteboard, or network is involved.
@main @MainActor
private final class RobotCloseVisualTests: NSObject, NSApplicationDelegate {
    private struct Sample {
        let image: CGImage
        let time: Double
        let closeTime: Double
        let headScale: CGFloat
        let headOpacity: Float
        let rootOpacity: Float
        let readbackSeconds: Double
        let signature: [UInt8]
    }
    private static var checks = 0
    private static var reports: [[String: Any]] = []
    private var result: Int32 = 0

    static func main() {
        let app = NSApplication.shared
        let delegate = RobotCloseVisualTests()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        exit(delegate.result)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do { try await Self.runChecks() }
            catch { result = 1; fputs("FAIL: \(error)\n", stderr) }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "RobotCloseVisualTests", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard value() else { throw failure(message) }
    }

    private static func layers(_ root: CALayer?) -> [CALayer] {
        guard let root else { return [] }
        return [root] + (root.sublayers ?? []).flatMap { layers($0) } + layers(root.mask)
    }

    private static func named(_ name: String, in root: CALayer?) throws -> CALayer {
        guard let layer = layers(root).first(where: { $0.name == name }) else {
            throw failure("Missing actual production layer \(name)")
        }
        return layer
    }

    private static func wait(_ seconds: Double) async throws {
        if seconds > 0 { try await Task.sleep(for: .seconds(seconds)) }
    }

    private static func runChecks() async throws {
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("build/qa/robot-close-visual", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for size in [CGSize(width: 380, height: 500), CGSize(width: 1200, height: 800)] {
            for dark in [false, true] {
                try await recordClose(size: size, dark: dark, output: output)
            }
        }
        let report: [String: Any] = [
            "schemaVersion": 1, "checksPassed": checks, "fixtures": reports,
            "renderMethod": "Actual production Core Animation presentation layers sampled against real elapsed time in isolated offscreen 2x windows",
            "videoMethod": "Local AVAssetWriter H.264 from live samples at their observed timestamps; no frame repetition, optical flow, or editorial motion",
            "samplingInterpretation": "Native 2x CPU readback evidence, not compositor FPS. Compact and closing gaps remain below 120ms. Expanded opening may account for measured readback cost plus 25ms scheduling allowance, with an absolute 180ms ceiling; frame/change minimums and direct live timing probes remain required.",
            "privacy": "Fictional production BoardView; isolated store and preferences; no personal archive, desktop screenshots, clipboard, global input or network",
            "closeDurationSeconds": RobotAppFrameView.closeDuration,
            "openDurationSeconds": RobotAppFrameView.openDuration,
            "reducedDurationSeconds": RobotAppFrameView.reducedDuration
        ]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("robot-close-visual-report.json"), options: .atomic)
        print("PASS: \(checks) actual robot opening/closing motion, presentation, reversal, cleanup and encoded video checks. \(output.path)")
    }

    private static func recordClose(size: CGSize, dark: Bool, output: URL) async throws {
        let fixture = "\(Int(size.width))x\(Int(size.height))-\(dark ? "dark" : "light")"
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("DaBinClosePreview-\(UUID().uuidString)", isDirectory: true)
        let suite = "DaBinClosePreview.\(UUID().uuidString)"
        guard let preferences = UserDefaults(suiteName: suite) else {
            throw failure("Cannot create isolated close preview preferences")
        }
        preferences.set(false, forKey: PreviewService.linkPreviewPreference)
        let store = try CaptureStore(root: fixtureRoot)
        let previews = PreviewService(store: store, defaults: preferences)
        let state = AppState(store: store, previews: previews,
            reminders: ReminderService(store: store, client: ClosePreviewReminders()))
        let theme = ThemeSettings(defaults: preferences, systemDarkMode: dark)
        theme.setDarkMode(dark)
        theme.setBoardOpacity(1)
        let texts = [
            "Atlas workshop — review the updated design",
            "Prepare the fictional launch checklist",
            "Keep the robot's head and body connected as it folds"
        ]
        for (index, text) in texts.enumerated() {
            let capture = try store.capture(text: text, at: Date().addingTimeInterval(Double(-index * 60)))[0]
            try store.update(capture, comment: "Local animation fixture · no personal content",
                             reminderAt: nil, reminderTimeZoneID: nil)
        }
        state.route = .daily
        state.isBoardVisible = true
        let hosting = NSHostingView(rootView: BoardView(state: state, theme: theme)
            .environment(\.displayScale, 2).frame(width: size.width, height: size.height))
        let frame = RobotAppFrameView(contentView: hosting)
        let outer = RobotAppFrameView.outerSize(forContentSize: size)
        let stageSize = CGSize(width: outer.width + 100, height: outer.height + 160)
        let stage = NSView(frame: CGRect(origin: .zero, size: stageSize))
        stage.wantsLayer = true
        stage.layer?.backgroundColor = (dark
            ? NSColor(calibratedRed: 0.065, green: 0.06, blue: 0.075, alpha: 1)
            : NSColor(calibratedRed: 0.93, green: 0.92, blue: 0.945, alpha: 1)).cgColor
        frame.frame = CGRect(origin: CGPoint(x: 50, y: 40), size: outer)
        stage.addSubview(frame)
        let label = NSTextField(labelWithString: "Actual native robot · \(fixture) · 2× · fictional content")
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = dark ? .lightGray : .darkGray
        label.frame = CGRect(x: 18, y: 13, width: stageSize.width - 36, height: 18)
        stage.addSubview(label)
        let window = ClosePreviewWindow(contentRect: CGRect(x: -10000, y: -10000,
            width: stageSize.width, height: stageSize.height), styleMask: [.borderless],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = true
        window.backgroundColor = .clear
        window.sharingType = .none
        window.contentView = stage
        CornerController.applyBoardAppearance(darkMode: dark, to: window, frame: frame, hosting: hosting)
        window.orderFront(nil)
        defer {
            frame.cancelTransition(open: false)
            window.orderOut(nil); window.contentView = nil; window.close()
            previews.cancelNetwork()
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: fixtureRoot)
        }
        frame.setVisible(true)
        stage.layoutSubtreeIfNeeded(); hosting.displayIfNeeded(); stage.displayIfNeeded()
        CATransaction.flush()
        try await wait(0.18)
        let appearance: NSAppearance.Name = dark ? .darkAqua : .aqua
        try expect(hosting.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == appearance,
                   "\(fixture) uses the real nested-host appearance bridge")
        try expect(hosting.frame.size == size && window.backingScaleFactor == 2,
                   "\(fixture) mounts full-size readable production content at native 2x")
        let sourceInStage = CGRect(x: stageSize.width / 2 - 36,
                                  y: stageSize.height - 102, width: 72, height: 88)
        let lower = window.convertPoint(toScreen: stage.convert(sourceInStage.origin, to: nil))
        let source = CGRect(origin: lower, size: sourceInStage.size)
        guard let head = try named("quietOrbit.headShell", in: frame.layer).superlayer else {
            throw failure("The actual shared head artwork must have a robot parent")
        }
        let railMasks = try stableRailMasks(frame)
        let openingEvidence = try await recordOpening(stage: stage, frame: frame, head: head,
            source: source, contentSize: size, fixture: fixture, railMasks: railMasks, output: output)
        let recordingContext = try makeRecordingContext(stage)
        let started = CACurrentMediaTime()
        var samples: [Sample] = [try sample(stage, frame: frame, head: head, started: started,
                                          closedAt: nil, context: recordingContext)]
        try await wait(0.16)
        samples.append(try sample(stage, frame: frame, head: head, started: started,
                                  closedAt: nil, context: recordingContext))
        var completions = 0
        let closedAt = CACurrentMediaTime()
        frame.animateClose(to: source, island: true, reduceMotion: false) { completions += 1 }
        CATransaction.flush()
        try checkTransitionStructure(frame: frame, head: head, source: source, opening: false,
                                     railMasks: railMasks, fixture: fixture)
        let duration = RobotAppFrameView.closeDuration + 0.18
        let sampleInterval = 1.0 / 30.0
        var nextSampleAt = closedAt
        while CACurrentMediaTime() - closedAt < duration {
            let delay = nextSampleAt - CACurrentMediaTime()
            if delay > 0 {
                try await wait(delay)
            } else {
                // A brief asynchronous pause lets AppKit commit presentation
                // updates and run the real completion task. Task.yield alone
                // can resume this actor before the offscreen run loop advances.
                try await Task.sleep(for: .milliseconds(1))
            }
            let observedAt = CACurrentMediaTime()
            samples.append(try sample(stage, frame: frame, head: head,
                                      started: started, closedAt: closedAt, context: recordingContext))
            try expect(hosting.frame.size == size,
                       "\(fixture) closing keeps the full-size hosted content mounted throughout")
            // Schedule from before the live render, not the next grid point
            // after it. Slow 2x renders take only the brief run-loop pause, not
            // an extra frame-grid idle interval; fast renders stay at 30Hz.
            // Samples retain observed timestamps and all assertions below.
            nextSampleAt = max(nextSampleAt + sampleInterval, observedAt + sampleInterval)
        }
        try expect(completions == 1 && frame.isHidden && !frame.isTransitioning && !frame.isFrameVisible,
                   "\(fixture) completes its real close once at a hidden stable endpoint")
        try expect(hosting.isHidden && hosting.frame.size == size && !frame.usesSolidTransitionTorso,
                   "\(fixture) keeps mounted content geometry and transparent torso rails")
        try checkRailMasks(frame, expected: railMasks, fixture: "\(fixture) after close")
        try expect(layers(frame.layer).allSatisfy { layer in
            !(layer.animationKeys() ?? []).contains(where: { $0.hasPrefix("robotFrame.") })
        }, "\(fixture) leaves no close animations behind")
        let moving = samples.filter { $0.closeTime >= 0 && $0.closeTime < RobotAppFrameView.closeDuration }
        let deltas = zip(moving, moving.dropFirst()).map { changedSamples($0.signature, $1.signature) }
        let changed = deltas.filter { $0 > 8 }.count
        let maxGap = zip(moving, moving.dropFirst()).map { $1.time - $0.time }.max() ?? .infinity
        try expect(moving.count >= 12 && changed >= 8 && maxGap < 0.12,
                   "\(fixture) records dense changing live motion, not endpoint stills (\(moving.count) frames, \(changed) changed, max gap \(maxGap)s)")
        try expect(moving.allSatisfy { $0.headScale.isFinite && $0.headScale > 0 },
                   "\(fixture) never inverts or collapses the canonical head to an invalid scale")
        let video = output.appendingPathComponent("DaBin-Robot-Close-\(fixture)@2x.mp4")
        try await encode(samples, to: video)
        try await verifyVideo(video, expectedCount: samples.count, size: stageSize)
        for (name, fraction) in [("open", -1.0), ("fold", 0.28), ("compact", 0.66),
                                 ("tuck", 0.88), ("closed", 1.1)] {
            let target = fraction < 0 ? samples[0].closeTime : RobotAppFrameView.closeDuration * fraction
            guard let chosen = samples.min(by: { abs($0.closeTime - target) < abs($1.closeTime - target) }) else { continue }
            try png(chosen.image, to: output.appendingPathComponent("\(fixture)-\(name)@2x.png"))
        }
        let timedOpacity = try await checkTimedOpacity(frame: frame, head: head, source: source, fixture: fixture)
        try await checkLateReversal(frame: frame, head: head, source: source, fixture: fixture)
        reports.append([
            "fixture": fixture, "contentWidth": size.width, "contentHeight": size.height,
            "pixelWidth": Int(stageSize.width * 2), "pixelHeight": Int(stageSize.height * 2),
            "video": video.lastPathComponent, "frameCount": samples.count,
            "changedCloseFrames": changed, "maximumCloseSampleGapSeconds": maxGap,
            "opening": openingEvidence,
            "timedOpacityProbe": timedOpacity,
            "frames": samples.enumerated().map { index, value in
                ["index": index, "actualSeconds": value.time, "actualCloseSeconds": value.closeTime,
                 "headScale": value.headScale, "headOpacity": value.headOpacity,
                 "rootOpacity": value.rootOpacity, "cpuReadbackSeconds": value.readbackSeconds] as [String: Any]
            }
        ])
        print("RENDERED \(fixture): \(samples.count) actual presentation frames. \(video.path)")
    }

    private static func recordOpening(stage: NSView, frame: RobotAppFrameView, head: CALayer,
                                       source: CGRect, contentSize: CGSize, fixture: String,
                                       railMasks: [String: CGPath], output: URL) async throws -> [String: Any] {
        let recordingContext = try makeRecordingContext(stage)
        // Prepare the full-size CPU readback before the measured animation.
        // The app was already laid out and visible; this primes glyph/vector
        // caches without altering a layer or sampling a fabricated pose.
        _ = try sample(stage, frame: frame, head: head, started: CACurrentMediaTime(),
                       closedAt: nil, context: recordingContext)
        frame.cancelTransition(open: false)
        CATransaction.flush()
        try await wait(0.05)
        let started = CACurrentMediaTime()
        var samples = [try sample(stage, frame: frame, head: head, started: started,
                                  closedAt: nil, context: recordingContext)]
        var completions = 0
        let openedAt = CACurrentMediaTime()
        frame.animateOpen(from: source, island: true, reduceMotion: false) { completions += 1 }
        CATransaction.flush()
        try checkTransitionStructure(frame: frame, head: head, source: source, opening: true,
                                     railMasks: railMasks, fixture: fixture)
        let duration = RobotAppFrameView.openDuration
        let interval = 1.0 / 30.0
        var nextSampleAt = openedAt
        while CACurrentMediaTime() - openedAt < duration + 0.18 {
            let delay = nextSampleAt - CACurrentMediaTime()
            if delay > 0 { try await wait(delay) }
            else { try await Task.sleep(for: .milliseconds(1)) }
            let observedAt = CACurrentMediaTime()
            // The shared sampler's phase-relative field also records opening;
            // metadata below labels this explicitly as actual opening time.
            samples.append(try sample(stage, frame: frame, head: head,
                                      started: started, closedAt: openedAt, context: recordingContext))
            try expect(frame.contentView.frame.size == contentSize,
                       "\(fixture) opening keeps the full-size hosted content mounted throughout")
            nextSampleAt = max(nextSampleAt + interval, observedAt + interval)
        }
        try expect(completions == 1 && !frame.isHidden && !frame.contentView.isHidden
            && frame.isFrameVisible && !frame.isTransitioning,
                   "\(fixture) completes its real opening once at an interactive stable endpoint")
        try checkRailMasks(frame, expected: railMasks, fixture: "\(fixture) after open")
        let moving = samples.filter { $0.closeTime >= 0 && $0.closeTime < duration }
        let changed = zip(moving, moving.dropFirst())
            .filter { changedSamples($0.signature, $1.signature) > 8 }.count
        let maxGap = zip(moving, moving.dropFirst()).map { $1.time - $0.time }.max() ?? .infinity
        let maximumReadback = moving.map(\.readbackSeconds).max() ?? .infinity
        let expanded = contentSize.width > 380
        let schedulingAllowance = 0.025
        // A full 2640 × 2020 bitmap is read on the same thread as these
        // samples. Account only for observed CPU readback work between actual
        // timestamps, never by slowing the animation or fabricating frames.
        // Even an explained expensive readback may not leave a gap >=180ms.
        let acceptableGaps = zip(moving, moving.dropFirst()).allSatisfy { previous, next in
            let gap = next.time - previous.time
            let accountedLimit = max(0.12, previous.readbackSeconds + schedulingAllowance)
            return gap < (expanded ? min(0.18, accountedLimit) : 0.12)
        }
        try expect(moving.count >= 14 && changed >= 9 && acceptableGaps,
                   "\(fixture) records dense changing actual opening (\(moving.count) frames, \(changed) changed, max gap \(maxGap)s, max measured CPU readback \(maximumReadback)s)")
        try expect(moving.contains { $0.headScale * head.bounds.width >= 90 && $0.headOpacity > 0.95 },
                   "\(fixture) actual opening visibly presents the recognizable enlarged robot before the board unfolds")
        let video = output.appendingPathComponent("DaBin-Robot-Open-\(fixture)@2x.mp4")
        try await encode(samples, to: video)
        try await verifyVideo(video, expectedCount: samples.count, size: stage.bounds.size)
        for (name, fraction) in [("source", 0.02), ("hero", 0.35), ("unfold", 0.65), ("settled", 1.05)] {
            guard let chosen = samples.min(by: { abs($0.closeTime - duration * fraction)
                < abs($1.closeTime - duration * fraction) }) else { continue }
            try png(chosen.image, to: output.appendingPathComponent("\(fixture)-opening-\(name)@2x.png"))
        }
        print("RENDERED opening \(fixture): \(samples.count) actual presentation frames. \(video.path)")
        return ["video": video.lastPathComponent, "frameCount": samples.count,
                "changedOpeningFrames": changed, "maximumOpeningSampleGapSeconds": maxGap,
                "maximumCPUReadbackSeconds": maximumReadback,
                "sampleGapPolicy": ["baselineMaximumSeconds": 0.12,
                    "measuredReadbackSchedulingAllowanceSeconds": expanded ? schedulingAllowance : 0,
                    "absoluteMaximumSeconds": expanded ? 0.18 : 0.12,
                    "meaning": "CPU recording continuity; not display compositor FPS"] as [String: Any],
                "completionCount": completions,
                "frames": samples.enumerated().map { index, value in
                    ["index": index, "actualSeconds": value.time, "actualOpenSeconds": value.closeTime,
                     "headScale": value.headScale, "headOpacity": value.headOpacity,
                     "rootOpacity": value.rootOpacity, "cpuReadbackSeconds": value.readbackSeconds] as [String: Any]
                }]
    }

    private static func makeRecordingContext(_ stage: NSView) throws -> CGContext {
        guard let context = CGContext(data: nil, width: Int(stage.bounds.width * 2),
                height: Int(stage.bounds.height * 2), bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw failure("The native 2x recording context is unavailable")
        }
        return context
    }

    private static func sample(_ stage: NSView, frame: RobotAppFrameView, head: CALayer,
                               started: Double, closedAt: Double?, context: CGContext) throws -> Sample {
        // Core Graphics snapshots retain their own pixel state. Reusing the
        // drawing context does not alter earlier images; it avoids recreating
        // the color space and renderer on every sample. Drain temporary native
        // render objects before the next live readback, retaining only evidence.
        try autoreleasepool {
            let observed = CACurrentMediaTime()
            guard let presentation = stage.layer?.presentation() else {
                throw failure("Live native presentation tree or 2x context is unavailable")
            }
            // Metadata belongs to this live presentation sample, not the later
            // animation state reached while the full-size CPU render is running.
            let headPresentation = head.presentation() ?? head
            let transform = headPresentation.transform
            let headOpacity = headPresentation.opacity
            let rootOpacity = frame.layer?.presentation()?.opacity ?? frame.layer?.opacity ?? 0
            let readbackStarted = CACurrentMediaTime()
            context.saveGState()
            context.clear(CGRect(x: 0, y: 0, width: context.width, height: context.height))
            context.scaleBy(x: 2, y: 2)
            presentation.render(in: context)
            context.restoreGState()
            guard let image = context.makeImage(), let bytes = context.data else {
                throw failure("Cannot extract actual native frame pixels")
            }
            let readbackSeconds = CACurrentMediaTime() - readbackStarted
            let data = bytes.assumingMemoryBound(to: UInt8.self)
            var signature: [UInt8] = []
            signature.reserveCapacity(80 * 80 * 3)
            for y in stride(from: 0, to: image.height, by: max(1, image.height / 72)) {
                for x in stride(from: 0, to: image.width, by: max(1, image.width / 72)) {
                    let offset = y * context.bytesPerRow + x * 4
                    signature.append(data[offset])
                    signature.append(data[offset + 1])
                    signature.append(data[offset + 2])
                }
            }
            try expect(abs(hypot(transform.m11, transform.m12) - hypot(transform.m21, transform.m22)) < 0.0001,
                       "Every captured head preserves the island character's uniform scale")
            return Sample(image: image, time: observed - started,
                          closeTime: closedAt.map { observed - $0 } ?? -1,
                          headScale: hypot(transform.m11, transform.m12),
                          headOpacity: headOpacity,
                          rootOpacity: rootOpacity,
                          readbackSeconds: readbackSeconds,
                          signature: signature)
        }
    }

    private static func changedSamples(_ first: [UInt8], _ second: [UInt8]) -> Int {
        zip(first, second).filter { abs(Int($0) - Int($1)) > 4 }.count
    }

    private static func png(_ image: CGImage, to url: URL) throws {
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw failure("Cannot encode native motion evidence")
        }
        try data.write(to: url, options: .atomic)
    }

    private static func encode(_ samples: [Sample], to url: URL) async throws {
        guard let first = samples.first else { throw failure("No actual motion samples") }
        let width = first.image.width, height = first.image.height
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 12_000_000,
                                             AVVideoMaxKeyFrameIntervalKey: 30]
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                                         kCVPixelBufferWidthKey as String: width,
                                         kCVPixelBufferHeightKey as String: height])
        guard writer.canAdd(input) else { throw failure("Local H.264 writer cannot accept video input") }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? failure("Cannot start local motion video") }
        writer.startSession(atSourceTime: .zero)
        for value in samples {
            let deadline = CACurrentMediaTime() + 10
            while !input.isReadyForMoreMediaData && writer.status == .writing && CACurrentMediaTime() < deadline {
                try await wait(0.005)
            }
            guard input.isReadyForMoreMediaData && writer.status == .writing else {
                throw writer.error ?? failure("Local video writer stalled")
            }
            var optional: CVPixelBuffer?
            let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                [kCVPixelBufferCGImageCompatibilityKey: true,
                 kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary, &optional)
            guard status == kCVReturnSuccess, let buffer = optional else { throw failure("Cannot allocate local video frame") }
            CVPixelBufferLockBaseAddress(buffer, [])
            guard let base = CVPixelBufferGetBaseAddress(buffer),
                  let context = CGContext(data: base, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
                CVPixelBufferUnlockBaseAddress(buffer, [])
                throw failure("Cannot draw local video frame")
            }
            context.draw(value.image, in: CGRect(x: 0, y: 0, width: width, height: height))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(seconds: value.time - first.time,
                                                                      preferredTimescale: 60_000)) else {
                throw writer.error ?? failure("Local video writer rejected an actual frame")
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        try expect(writer.status == .completed, "Actual presentation frames encode into a complete local MP4")
    }

    private static func verifyVideo(_ url: URL, expectedCount: Int, size: CGSize) async throws {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        try expect(tracks.count == 1 && audio.isEmpty,
                   "Native motion preview has one video track and no unintended audio")
        guard let track = tracks.first else { throw failure("No encoded native video track") }
        let natural = try await track.load(.naturalSize)
        try expect(natural == CGSize(width: size.width * 2, height: size.height * 2),
                   "Encoded native motion preview preserves exact 2x pixel dimensions without resampling")
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? failure("Cannot decode actual motion MP4") }
        var count = 0
        var last = CMTime.negativeInfinity
        while let sample = output.copyNextSampleBuffer() {
            let time = CMSampleBufferGetPresentationTimeStamp(sample)
            try expect(CMTimeCompare(time, last) > 0, "Encoded actual frame timestamps are strictly increasing")
            last = time; count += 1
        }
        try expect(reader.status == .completed && count == expectedCount,
                   "Every actual native motion frame fully decodes (\(count)/\(expectedCount))")
    }

    private static func stableRailMasks(_ frame: RobotAppFrameView) throws -> [String: CGPath] {
        var result: [String: CGPath] = [:]
        for name in ["robotFrame.leftTorso", "robotFrame.rightTorso"] {
            guard let path = (try named(name, in: frame.layer).mask as? CAShapeLayer)?.path else {
                throw failure("The actual window rails must have perimeter masks")
            }
            result[name] = path
        }
        return result
    }

    private static func checkRailMasks(_ frame: RobotAppFrameView, expected: [String: CGPath],
                                       fixture: String) throws {
        try expect(!frame.usesSolidTransitionTorso,
                   "\(fixture) keeps window rails transparent instead of creating a solid purple plate")
        for (name, expectedPath) in expected {
            guard let mask = try named(name, in: frame.layer).mask as? CAShapeLayer,
                  let path = mask.path else { throw failure("The window rail lost its stable perimeter mask") }
            try expect(samePath(path, expectedPath) && (mask.animationKeys() ?? []).isEmpty,
                       "\(fixture) retains the exact perimeter mask throughout character motion: \(name), actual \(path.boundingBoxOfPath), expected \(expectedPath.boundingBoxOfPath), animations \(mask.animationKeys() ?? [])")
        }
    }

    private static func checkTransitionStructure(frame: RobotAppFrameView, head: CALayer,
                                                 source: CGRect, opening: Bool,
                                                 railMasks: [String: CGPath], fixture: String) throws {
        let key = opening ? "robotFrame.open" : "robotFrame.close"
        guard let animation = head.animation(forKey: key) as? CAKeyframeAnimation,
              let values = animation.values as? [NSValue], let times = animation.keyTimes else {
            throw failure("\(fixture) must animate the actual shared head through character poses")
        }
        try expect(values.count >= 4 && values.count == times.count,
                   "\(fixture) includes recognizable character poses between its endpoints")
        try expect(times.first?.doubleValue == 0 && times.last?.doubleValue == 1
            && zip(times, times.dropFirst()).allSatisfy { $0.doubleValue < $1.doubleValue },
                   "\(fixture) authored poses cover one continuous monotonic timeline")
        try expect(abs(animation.duration - (opening ? RobotAppFrameView.openDuration : RobotAppFrameView.closeDuration)) < 0.00001,
                   "\(fixture) normal motion uses the published duration")
        try expect(values.allSatisfy { value in
            let transform = value.caTransform3DValue
            return transform.m11.isFinite && transform.m22.isFinite && transform.m41.isFinite
                && transform.m42.isFinite && transform.m11 > 0
                && abs(transform.m11 - transform.m22) < 0.00001
        }, "\(fixture) preserves canonical head aspect through every authored pose")
        let widths = values.map { transformedBounds(head, transform: $0.caTransform3DValue).width }
        try expect((widths.max() ?? 0) >= 90,
                   "\(fixture) gives the main character a readable enlarged head before settling")
        let sourceHeadWidth = 42 * min(source.width / 56.7, source.height / 45.75)
        if opening {
            try expect(abs((widths.first ?? 0) - sourceHeadWidth) < 0.001,
                       "\(fixture) begins at the canonical island head size without a shrunken-head handoff")
        } else {
            try expect(widths.dropFirst().dropLast().contains { abs($0 - sourceHeadWidth) < 0.001 },
                       "\(fixture) returns to the original island head size before docking")
            guard let opacity = head.animation(forKey: "robotFrame.closeOpacity") as? CAKeyframeAnimation,
                  let opacityValues = opacity.values as? [NSNumber], let opacityTimes = opacity.keyTimes else {
                throw failure("\(fixture) must hold the recognisable robot until the final docking fade")
            }
            try expect(opacityValues.last?.doubleValue == 0 && zip(opacityTimes, opacityValues).contains {
                $0.doubleValue >= 0.85 && $1.doubleValue == 1
            }, "\(fixture) keeps the character visible through the source arrival")
        }
        guard let content = frame.contentView.superview?.layer else { throw failure("Missing mounted content layer") }
        try expect(content.animation(forKey: opening ? "robotFrame.open" : "robotFrame.content.transform.close") != nil
            && content.animation(forKey: opening ? "robotFrame.content.open" : "robotFrame.content.opacity.close") != nil,
                   "\(fixture) keeps shrinking and fading on distinct keys so neither animation replaces the other")
        let body = try named("quietOrbit.body", in: frame.layer)
        guard let bodyMotion = body.animation(forKey: key) as? CAKeyframeAnimation,
              let bodyValues = bodyMotion.values as? [NSValue], bodyValues.count == values.count,
              let chest = try named("quietOrbit.chest", in: body).mask as? CAShapeLayer,
              let chestPath = chest.path else { throw failure("A canonical compact body must travel with the shared head") }
        try expect(abs(chestPath.boundingBoxOfPath.width / head.bounds.width - 0.68) < 0.001
            && abs(chestPath.boundingBoxOfPath.height / head.bounds.width - 0.30) < 0.001,
                   "\(fixture) uses the island's small mechanical chest below its much wider head")
        try expect(zip(values, bodyValues).allSatisfy {
            let a = $0.caTransform3DValue, b = $1.caTransform3DValue
            return abs(a.m11 - b.m11) < 0.001 && abs(a.m22 - b.m22) < 0.001
                && abs(a.m41 - b.m41) < 0.001 && abs(a.m42 - b.m42) < 0.001
        }, "\(fixture) head and compact body move as one connected character")
        let globalStart = head.convertTime(animation.beginTime, to: nil)
        for layer in layers(frame.layer) {
            for name in layer.animationKeys() ?? [] where name.hasPrefix("robotFrame.") {
                guard let track = layer.animation(forKey: name) else { continue }
                try expect(abs(layer.convertTime(track.beginTime, to: nil) - globalStart) < 0.00001
                    && abs(track.duration - animation.duration) < 0.00001,
                           "\(fixture) all character, expression, content and rim tracks share one animation clock")
            }
        }
        for name in ["robotFrame.leftArm", "robotFrame.rightArm"] {
            let arm = try named(name, in: frame.layer)
            guard let pathTrack = arm.animation(forKey: "robotFrame.arm.path") as? CAKeyframeAnimation,
                  let paths = pathTrack.values,
                  let widthTrack = arm.animation(forKey: "robotFrame.arm.width") as? CAKeyframeAnimation,
                  let armWidths = widthTrack.values as? [NSNumber] else {
                throw failure("\(fixture) arms must articulate their actual paths and stroke widths")
            }
            let topology = try paths.map { pathElements(try animationPath($0)).map(\.kind) }
            try expect(topology.count == values.count && topology.allSatisfy { $0 == topology.first }
                && armWidths.count == values.count && armWidths.allSatisfy { $0.doubleValue > 0 && $0.doubleValue.isFinite },
                       "\(fixture) synchronized arm geometry interpolates without topology swaps or invalid strokes")
        }
        try checkRailMasks(frame, expected: railMasks, fixture: "\(fixture) \(opening ? "opening" : "closing") start")
    }

    private static func animationPath(_ value: Any?) throws -> CGPath {
        guard let value, CFGetTypeID(value as CFTypeRef) == CGPath.typeID else {
            throw failure("Production arm animation must carry an actual Core Graphics path")
        }
        return value as! CGPath
    }

    private static func pathElements(_ path: CGPath) -> [(kind: Int, values: [CGFloat])] {
        var elements: [(kind: Int, values: [CGFloat])] = []
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            let count: Int
            switch element.type {
            case .moveToPoint, .addLineToPoint: count = 1
            case .addQuadCurveToPoint: count = 2
            case .addCurveToPoint: count = 3
            case .closeSubpath: count = 0
            @unknown default: count = 0
            }
            elements.append((Int(element.type.rawValue), (0..<count).flatMap {
                [element.points[$0].x, element.points[$0].y]
            }))
        }
        return elements
    }

    private static func samePath(_ first: CGPath, _ second: CGPath) -> Bool {
        let lhs = pathElements(first), rhs = pathElements(second)
        return lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { first, second in
            first.kind == second.kind && first.values.count == second.values.count
                && zip(first.values, second.values).allSatisfy { abs($0 - $1) < 0.001 }
        }
    }

    private static func transformedBounds(_ layer: CALayer, transform: CATransform3D) -> CGRect {
        let anchor = CGPoint(x: layer.bounds.minX + layer.bounds.width * layer.anchorPoint.x,
                             y: layer.bounds.minY + layer.bounds.height * layer.anchorPoint.y)
        let points = [CGPoint(x: layer.bounds.minX, y: layer.bounds.minY),
                      CGPoint(x: layer.bounds.maxX, y: layer.bounds.minY),
                      CGPoint(x: layer.bounds.minX, y: layer.bounds.maxY),
                      CGPoint(x: layer.bounds.maxX, y: layer.bounds.maxY)].map { point in
            CGPoint(x: layer.position.x + transform.m41 + (point.x - anchor.x) * transform.m11
                        + (point.y - anchor.y) * transform.m21,
                    y: layer.position.y + transform.m42 + (point.x - anchor.x) * transform.m12
                        + (point.y - anchor.y) * transform.m22)
        }
        let minX = points.map(\.x).min() ?? 0, minY = points.map(\.y).min() ?? 0
        return CGRect(x: minX, y: minY, width: (points.map(\.x).max() ?? 0) - minX,
                      height: (points.map(\.y).max() ?? 0) - minY)
    }

    /// Full-stage 2x CPU recording can miss the short late-fade window even
    /// while satisfying its density/gap checks. Probe a second real close
    /// directly, without rendering work, changing animation time, interpolating
    /// frames or weakening either recording or temporal assertions.
    private static func checkTimedOpacity(frame: RobotAppFrameView, head: CALayer,
                                         source: CGRect, fixture: String) async throws -> [String: Any] {
        frame.setVisible(true)
        CATransaction.flush()
        try await wait(0.05)
        var completions = 0
        let closedAt = CACurrentMediaTime()
        frame.animateClose(to: source, island: true, reduceMotion: false) { completions += 1 }
        CATransaction.flush()
        let duration = RobotAppFrameView.closeDuration

        try await wait(closedAt + duration * 0.66 - CACurrentMediaTime())
        let heldAt = CACurrentMediaTime() - closedAt
        guard let heldPresentation = head.presentation() else {
            throw failure("\(fixture) has no live head presentation at its timed compact probe (\(heldAt)s)")
        }
        let heldTransform = heldPresentation.transform
        let heldOpacity = heldPresentation.opacity
        let heldScale = hypot(heldTransform.m11, heldTransform.m12)
        try expect(heldAt > duration * 0.60 && heldAt < duration * 0.78,
                   "\(fixture) observes its real compact pose inside the character hold (\(heldAt)s)")
        try expect(heldScale.isFinite && heldScale > 0
            && abs(heldScale - hypot(heldTransform.m21, heldTransform.m22)) < 0.0001,
                   "\(fixture) timed compact probe preserves the real head's finite uniform scale")
        let body = try named("quietOrbit.body", in: frame.layer)
        try expect(heldOpacity > 0.95 && heldScale * head.bounds.width >= 90
            && (body.presentation()?.opacity ?? body.opacity) > 0.95,
                   "\(fixture) holds a readable compact robot (\(heldAt)s, opacity \(heldOpacity))")

        try await wait(closedAt + duration * 0.94 - CACurrentMediaTime())
        let fadedAt = CACurrentMediaTime() - closedAt
        guard let fadedPresentation = head.presentation() else {
            throw failure("\(fixture) has no live head presentation at its timed late-fade probe (\(fadedAt)s)")
        }
        let fadedTransform = fadedPresentation.transform
        let fadedOpacity = fadedPresentation.opacity
        let fadedScale = hypot(fadedTransform.m11, fadedTransform.m12)
        try expect(fadedAt > duration * 0.90 && fadedAt < duration,
                   "\(fixture) observes its real late fade inside the original fade band (\(fadedAt)s)")
        try expect(fadedScale.isFinite && fadedScale > 0
            && abs(fadedScale - hypot(fadedTransform.m21, fadedTransform.m22)) < 0.0001,
                   "\(fixture) timed late-fade probe preserves the real head's finite uniform scale")
        try expect(fadedOpacity < 0.8 && completions == 0 && frame.isTransitioning && !frame.isHidden,
                   "\(fixture) genuinely fades before completion (\(fadedAt)s, opacity \(fadedOpacity), completions \(completions))")

        try await wait(closedAt + duration + 0.12 - CACurrentMediaTime())
        try expect(completions == 1 && frame.isHidden && frame.contentView.isHidden
            && !frame.isTransitioning && !frame.isFrameVisible,
                   "\(fixture) timed close completes once at the real hidden endpoint")
        return ["method": "Second actual production close; direct live presentation probes at observed wall-clock times",
                "heldSeconds": heldAt, "heldHeadOpacity": heldOpacity, "heldHeadScale": heldScale,
                "fadedSeconds": fadedAt, "fadedHeadOpacity": fadedOpacity, "fadedHeadScale": fadedScale,
                "completionCount": completions]
    }

    private static func checkLateReversal(frame: RobotAppFrameView, head: CALayer,
                                          source: CGRect, fixture: String) async throws {
        frame.setVisible(true)
        CATransaction.flush()
        try await wait(0.05)
        var staleClosed = 0, reopened = 0
        let closedAt = CACurrentMediaTime()
        frame.animateClose(to: source, island: true, reduceMotion: false) { staleClosed += 1 }
        CATransaction.flush()
        let duration = RobotAppFrameView.closeDuration
        try await wait(closedAt + duration * 0.88 - CACurrentMediaTime())
        var observedFade: (transform: CATransform3D, opacity: Float)?
        var elapsed = CACurrentMediaTime() - closedAt
        var lastOpacity = head.presentation()?.opacity ?? head.opacity
        while elapsed <= duration + 0.06 {
            guard frame.isTransitioning else { break }
            if let presented = head.presentation() {
                lastOpacity = presented.opacity
                if lastOpacity > 0 && lastOpacity < 0.9 {
                    observedFade = (presented.transform, lastOpacity)
                    break
                }
            }
            try await wait(0.005)
            elapsed = CACurrentMediaTime() - closedAt
        }
        guard let observedFade else {
            throw failure("\(fixture) missed the actual late fade before completion: elapsed \(elapsed)s, opacity \(lastOpacity), transitioning \(frame.isTransitioning)")
        }
        let before = observedFade.transform
        let opacityBefore = observedFade.opacity
        try expect(opacityBefore > 0 && opacityBefore < 0.9 && frame.isTransitioning,
                   "\(fixture) reversal fixture actually observes the late fade (\(elapsed)s, opacity \(opacityBefore))")
        frame.animateOpen(from: source, island: true, reduceMotion: false) { reopened += 1 }
        guard let opening = head.animation(forKey: "robotFrame.open") as? CAKeyframeAnimation,
              let start = (opening.values as? [NSValue])?.first?.caTransform3DValue else {
            throw failure("Late reopening must continue through actual production keyframes")
        }
        try expect(abs(start.m11 - before.m11) < 0.015 && abs(start.m41 - before.m41) < 2
            && abs(start.m42 - before.m42) < 2,
                   "\(fixture) late reopening starts from the visible head transform, not an endpoint jump")
        let opacityAnimations = (head.animationKeys() ?? []).compactMap { head.animation(forKey: $0) }
        let opacityStart = opacityAnimations.compactMap { value -> Double? in
            if let basic = value as? CABasicAnimation, basic.keyPath == "opacity" {
                return (basic.fromValue as? NSNumber)?.doubleValue
            }
            if let keyed = value as? CAKeyframeAnimation, keyed.keyPath == "opacity" {
                return (keyed.values?.first as? NSNumber)?.doubleValue
            }
            return nil
        }.first
        try expect(opacityStart.map { abs($0 - Double(opacityBefore)) < 0.06 } == true,
                   "\(fixture) late reopening preserves visible per-part opacity instead of flashing fully opaque")
        try expect(opening.duration < RobotAppFrameView.openDuration,
                   "\(fixture) reversal resumes promptly instead of replaying the full entrance")
        try await wait(opening.duration + 0.12)
        try expect(staleClosed == 0 && reopened == 1 && !frame.isHidden
            && frame.isFrameVisible && !frame.isTransitioning,
                   "\(fixture) late close cancellation cannot hide or complete over a reopened app")
        frame.cancelTransition(open: false)
        try expect(!frame.hasActiveEyeMotion && frame.isHidden,
                   "\(fixture) cleanup stops the renderer without leaving interactive content")
        try await checkMidHeroReversal(frame: frame, source: source, fixture: fixture)
        try await checkInterruptedEntrance(frame: frame, source: source, fixture: fixture)
    }

    private static func checkMidHeroReversal(frame: RobotAppFrameView, source: CGRect,
                                             fixture: String) async throws {
        frame.setVisible(true)
        CATransaction.flush()
        try await wait(0.04)
        var stale = 0
        let railMasks = try stableRailMasks(frame)
        frame.animateClose(to: source, island: true, reduceMotion: false) { stale += 1 }
        CATransaction.flush()
        try await wait(RobotAppFrameView.closeDuration * 0.60)
        let body = try named("quietOrbit.body", in: frame.layer)
        guard let arm = try named("robotFrame.leftArm", in: frame.layer) as? CAShapeLayer,
              let presented = arm.presentation(),
              let visible = presented.path else { throw failure("Missing actual articulated arm presentation") }
        let width = presented.lineWidth
        let bodyOpacity = body.presentation()?.opacity ?? body.opacity
        try expect(bodyOpacity > 0.95,
                   "\(fixture) samples a genuinely visible canonical compact character before reversal")
        frame.animateOpen(from: source, island: true, reduceMotion: false) { stale += 1 }
        guard let reopen = arm.animation(forKey: "robotFrame.arm.path") as? CAKeyframeAnimation,
              let firstPath = reopen.values?.first,
              let widths = arm.animation(forKey: "robotFrame.arm.width") as? CAKeyframeAnimation,
              let firstWidth = widths.values?.first as? NSNumber,
              let opacity = body.animation(forKey: "robotFrame.body.opacity") as? CAKeyframeAnimation,
              let firstOpacity = opacity.values?.first as? NSNumber else {
            throw failure("Interrupted character motion must resume from actual presented paths, widths and opacity")
        }
        let start = try animationPath(firstPath)
        try expect(samePath(start, visible) && abs(firstWidth.doubleValue - Double(width)) < 0.001
            && abs(firstOpacity.doubleValue - Double(bodyOpacity)) < 0.001,
                   "\(fixture) reopening the compact robot preserves actual arm geometry and body opacity")
        try checkRailMasks(frame, expected: railMasks, fixture: fixture)
        frame.cancelTransition(open: true)
        try await wait(RobotAppFrameView.closeDuration + 0.06)
        try expect(stale == 0 && frame.isFrameVisible && !frame.isTransitioning
            && !frame.usesSolidTransitionTorso,
                   "\(fixture) canceled callbacks remain invalidated and retain transparent stable rails")
        try expect(layers(frame.layer).allSatisfy { ($0.animationKeys() ?? []).isEmpty },
                   "\(fixture) cancellation removes torso mask, opacity and transform animations")
        frame.cancelTransition(open: false)
    }

    private static func checkInterruptedEntrance(frame: RobotAppFrameView, source: CGRect,
                                                  fixture: String) async throws {
        frame.cancelTransition(open: false)
        CATransaction.flush()
        try await wait(0.04)
        var opened = 0, closed = 0
        frame.animateOpen(from: source, island: true, reduceMotion: false) { opened += 1 }
        CATransaction.flush()
        try await wait(0.10)
        guard let content = frame.contentView.superview?.layer else { throw failure("Missing mounted content") }
        let body = try named("quietOrbit.body", in: frame.layer)
        let beforeContent = content.presentation()?.opacity ?? content.opacity
        let beforeBody = body.presentation()?.opacity ?? body.opacity
        try expect(beforeContent < 0.05 && beforeBody > 0.95,
                   "\(fixture) cancellation fixture reaches the visible entrance before hidden content unfolds")
        frame.animateClose(to: source, island: true, reduceMotion: false) { closed += 1 }
        CATransaction.flush()
        guard let close = body.animation(forKey: "robotFrame.close") else {
            throw failure("Interrupted entrance needs a real character return")
        }
        for _ in 0..<3 {
            try await wait(0.06)
            let contentOpacity = content.presentation()?.opacity ?? content.opacity
            let bodyOpacity = body.presentation()?.opacity ?? body.opacity
            try expect(contentOpacity <= beforeContent + 0.01 && bodyOpacity >= beforeBody - 0.05,
                       "\(fixture) early close never flashes the hidden board or makes the visible robot disappear")
        }
        try await wait(close.duration + 0.10)
        try expect(opened == 0 && closed == 1 && frame.isHidden && !frame.isTransitioning,
                   "\(fixture) an interrupted entrance cancels its stale completion and returns once")
    }
}
