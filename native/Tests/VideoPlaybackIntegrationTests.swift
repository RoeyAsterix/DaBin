import AppKit
import ApplicationServices
@preconcurrency import AVFoundation
@preconcurrency import AVKit
import CoreVideo
import CryptoKit
import Foundation
import SwiftUI

private final class VideoCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Bool?
    var result: Bool? { lock.lock(); defer { lock.unlock() }; return stored }
    func finish(_ value: Bool) { lock.lock(); stored = value; lock.unlock() }
}

@MainActor private final class VideoFixtureWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// These are the actual production SwiftUI components. Their private AVPlayer
/// state is neither replaced nor inspected. Public AVPlayerView.player gives
/// access to the player that the mounted production component actually owns.
@MainActor private final class VideoMount: NSObject, NSWindowDelegate {
    enum Kind: String, CaseIterable { case fittedPreview, extendedCanvas }
    let window: NSWindow
    private var hosting: NSHostingView<AnyView>?
    init(size: NSSize) {
        window = VideoFixtureWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
            styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false; window.delegate = self
    }
    func show(kind: Kind, store: CaptureStore, capture: Capture, zoom: CaptureZoomState, size: NSSize) {
        let content: AnyView
        switch kind {
        case .fittedPreview:
            // The optional opener is deliberately absent: this reusable
            // production component embeds its real native player. DetailScreen
            // itself uses a thumbnail/opener to the Extended View instead.
            content = AnyView(GeometryReader { geometry in
                DetailPreview(store: store, capture: capture, height: geometry.size.height)
            })
        case .extendedCanvas:
            content = AnyView(ExtendedCaptureCanvas(store: store, capture: capture, zoom: zoom))
        }
        let host = NSHostingView(rootView: AnyView(content.id(capture.id)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.daBinTooltipsEnabled, false)
            .transaction { $0.animation = nil; $0.disablesAnimations = true }))
        host.frame = NSRect(origin: .zero, size: size)
        window.setContentSize(size)
        // CaptureExtendedWindowController.show also replaces its hosting view
        // when switching captures; Board's Detail destination uses capture.id.
        window.contentView = host; hosting = host
        window.orderFront(nil)
    }
    func resize(_ size: NSSize) { window.setContentSize(size); hosting?.frame.size = size }
    func layout() { hosting?.layoutSubtreeIfNeeded() }
    var root: NSView? { hosting }
    func windowWillClose(_ notification: Notification) {
        // Match the production Extended controller's close ownership: detach
        // content so onDisappear must pause and release the native player.
        window.contentView = nil; hosting = nil
    }
    func close() { window.close(); window.contentView = nil; hosting = nil }
}

@MainActor private final class VideoPlayerProbe {
    var retainedPlayer: AVPlayer?
    weak var player: AVPlayer?
    weak var item: AVPlayerItem?
    weak var nativeView: AVPlayerView?
    init(view: AVPlayerView, player: AVPlayer, item: AVPlayerItem) {
        nativeView = view; retainedPlayer = player; self.player = player; self.item = item
    }
}

/// Public, responds-gated accessibility only. Optional AVKit accessibility
/// selectors must never be invoked unconditionally or via private ivars.
@MainActor private struct VideoAX {
    let object: NSObject
    private func value(_ name: String) -> Any? {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue()
    }
    private func attribute(_ name: String) -> Any? {
        let selector = NSSelectorFromString("accessibilityAttributeValue:")
        guard object.responds(to: selector),
              (value("accessibilityAttributeNames") as? [String])?.contains(name) == true else { return nil }
        return object.perform(selector, with: name as NSString)?.takeUnretainedValue()
    }
    var role: String { (value("accessibilityRole") as? String) ?? (attribute("AXRole") as? String) ?? "" }
    var label: String {
        [value("accessibilityLabel"), value("accessibilityTitle"), attribute("AXTitle"), attribute("AXDescription")]
            .compactMap { $0 as? String }.first { !$0.isEmpty } ?? ""
    }
    var actionNames: [String] { value("accessibilityActionNames") as? [String] ?? [] }
    var hasPress: Bool {
        object.responds(to: NSSelectorFromString("accessibilityPerformPress"))
            || (actionNames.contains("AXPress") && object.responds(to: NSSelectorFromString("accessibilityPerformAction:")))
    }
    var children: [Any] {
        var result: [Any] = []
        for name in ["accessibilityChildren", "accessibilityChildrenInNavigationOrder", "accessibilityContents"] {
            if let children = value(name) as? [Any] { result += children }
        }
        if let children = attribute("AXChildren") as? [Any] { result += children }
        if let view = object as? NSView { result += view.subviews }
        return result
    }
    func press() -> Bool {
        let selector = NSSelectorFromString("accessibilityPerformPress")
        if object.responds(to: selector) {
            typealias Press = @convention(c) (AnyObject, Selector) -> Bool
            return unsafeBitCast(object.method(for: selector), to: Press.self)(object, selector)
        }
        let legacy = NSSelectorFromString("accessibilityPerformAction:")
        guard actionNames.contains("AXPress"), object.responds(to: legacy) else { return false }
        object.perform(legacy, with: "AXPress" as NSString)
        return true
    }
}

/// Actual AVKit/AVFoundation transport and lifecycle integration with synthetic
/// silent local movies. No private controls, network, clipboard, personal data,
/// notification permission, global input, Finder, or key/active app window.
@main @MainActor private final class VideoPlaybackIntegrationTests: NSObject, NSApplicationDelegate {
    private static var checks = 0
    private static var nativeButtonPresses = 0
    private static var unavailableControls: [String] = []
    private static var accessibilityStatus: Int32?
    private var result: Int32 = 0
    static func main() {
        let application = NSApplication.shared
        let delegate = VideoPlaybackIntegrationTests()
        application.setActivationPolicy(.accessory); application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
        exit(delegate.result)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await Self.run() }
            catch { result = 1; fputs("Video playback integration failed: \(error)\n", stderr) }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "VideoPlaybackIntegrationTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        guard try value() else { throw failure(message) }
    }
    private static func wait(_ mount: VideoMount?, timeout: TimeInterval = 8, _ predicate: () -> Bool) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        repeat {
            mount?.layout()
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        } while ProcessInfo.processInfo.systemUptime < deadline
        return predicate()
    }
    private static func nativePlayers(in view: NSView) -> [AVPlayerView] {
        var result = (view as? AVPlayerView).map { [$0] } ?? []
        for child in view.subviews { result += nativePlayers(in: child) }
        return result
    }
    private static func sourceURL(_ player: AVPlayer) -> URL? {
        (player.currentItem?.asset as? AVURLAsset)?.url.standardizedFileURL
    }
    private static func activateOwnAccessibility() async {
        guard accessibilityStatus == nil else { return }
        let result = await Task.detached {
            let application = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            AXUIElementSetMessagingTimeout(application, 3)
            var windows: CFTypeRef?
            return AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &windows).rawValue
        }.value
        accessibilityStatus = result
        print("OWN_PROCESS_AX: windows attribute activation result=\(result); only this test process was queried")
    }
    private static func accessibleNodes(_ root: NSView) -> [VideoAX] {
        var seen = Set<ObjectIdentifier>(), result: [VideoAX] = []
        func visit(_ candidate: Any, depth: Int) {
            guard depth < 40, let object = candidate as? NSObject,
                  seen.insert(ObjectIdentifier(object)).inserted else { return }
            let node = VideoAX(object: object); result.append(node)
            node.children.forEach { visit($0, depth: depth + 1) }
        }
        visit(root, depth: 0)
        NSAccessibility.unignoredChildren(from: [root]).forEach { visit($0, depth: 0) }
        return result
    }
    private static func nativeTransport(_ title: String, player: AVPlayer, mount: VideoMount, label: String) async throws {
        var candidate: VideoAX?
        _ = await wait(mount, timeout: 1) {
            guard let root = mount.root else { return false }
            candidate = accessibleNodes(root).first {
                let text = $0.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return $0.role == NSAccessibility.Role.button.rawValue && $0.hasPress
                    && [title.lowercased(), "\(title.lowercased()) button", "\(title.lowercased()) playback",
                        "play/pause", "play or pause", "play or pause playback"].contains(text)
            }
            return candidate != nil
        }
        if let candidate {
            try expect(candidate.press(), "\(label): the actual native \(title) button advertises and accepts its real AXPress action")
            nativeButtonPresses += 1
            print("NATIVE_CONTROL: \(label); \(title) activated via public native accessibility action")
        } else {
            let buttons = mount.root.map { accessibleNodes($0).filter { $0.role == NSAccessibility.Role.button.rawValue }
                .map { "\($0.label) [AXPress=\($0.hasPress)]" }.joined(separator: "; ") } ?? "no mounted root"
            unavailableControls.append("\(label).\(title)")
            print("CONTROL_BOUNDARY: \(label) \(title): no standard named native button with a supported AXPress was exposed by this inactive offscreen AVKit view; ownProcessAX=\(accessibilityStatus.map(String.init) ?? "not initialized"). Exposed buttons: \(buttons)")
            if title == "Play" { player.play() } else { player.pause() }
        }
    }

    private static func makeMovie(at url: URL, width: Int, height: Int, frames: Int, colorOffset: Int) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height])
        guard writer.canAdd(input) else { throw failure("Synthetic movie writer cannot add H.264 input") }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? failure("Synthetic movie writer cannot start") }
        writer.startSession(atSourceTime: .zero)
        let deadline = ProcessInfo.processInfo.systemUptime + 20
        for frame in 0..<frames {
            while !input.isReadyForMoreMediaData && writer.status == .writing
                && ProcessInfo.processInfo.systemUptime < deadline {
                try await Task.sleep(for: .milliseconds(5))
            }
            guard input.isReadyForMoreMediaData && writer.status == .writing
                && ProcessInfo.processInfo.systemUptime < deadline else {
                writer.cancelWriting(); throw writer.error ?? failure("Synthetic movie writer exceeded its20-second bound")
            }
            var optional: CVPixelBuffer?
            let result = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary,
                &optional)
            guard result == kCVReturnSuccess, let buffer = optional else { throw failure("Synthetic movie pixel allocation failed") }
            CVPixelBufferLockBaseAddress(buffer, [])
            guard let address = CVPixelBufferGetBaseAddress(buffer) else { throw failure("Synthetic movie pixel buffer has no bytes") }
            let row = CVPixelBufferGetBytesPerRow(buffer), bytes = address.assumingMemoryBound(to: UInt8.self)
            for y in 0..<height {
                for x in 0..<width {
                    let offset = y * row + x * 4
                    bytes[offset] = UInt8((x + frame * 3 + colorOffset) % 256)
                    bytes[offset + 1] = UInt8((y + frame + colorOffset) % 256)
                    bytes[offset + 2] = UInt8((frame * 5 + colorOffset) % 256)
                    bytes[offset + 3] = 255
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30)) else {
                writer.cancelWriting(); throw writer.error ?? failure("Synthetic movie writer rejected a frame")
            }
        }
        input.markAsFinished()
        let finished = VideoCompletion()
        writer.finishWriting { finished.finish(true) }
        guard await wait(nil, timeout: 10, { finished.result != nil }) else {
            writer.cancelWriting(); throw failure("Synthetic movie completion exceeded its10-second bound")
        }
        try expect(writer.status == .completed, "The silent local movie writer completes its actual MOV file")
    }

    private static func mountedPlayer(_ mount: VideoMount, url: URL, label: String) async throws -> VideoPlayerProbe {
        await activateOwnAccessibility()
        let mounted = await wait(mount) {
            guard let root = mount.root else { return false }
            return nativePlayers(in: root).contains { view in
                guard let player = view.player else { return false }
                return sourceURL(player) == url.standardizedFileURL && player.currentItem?.status == .readyToPlay
            }
        }
        try expect(mounted, "\(label): production component mounts a ready native AVPlayerView using its correct managed URL")
        guard let root = mount.root,
              let view = nativePlayers(in: root).first(where: { view in
                  guard let player = view.player else { return false }
                  return sourceURL(player) == url.standardizedFileURL
              }),
              let player = view.player, let item = player.currentItem else { throw failure("\(label): mounted native player disappeared") }
        view.updatesNowPlayingInfoCenter = false
        player.isMuted = true // The generated movie also contains no audio track.
        let displayed = await wait(mount) { view.isReadyForDisplay && item.duration.seconds.isFinite && item.duration.seconds > 2 }
        try expect(displayed && player.error == nil && item.error == nil,
            "\(label): the actual AVKit display becomes ready without a transport or decode error")
        try expect(player.rate == 0 && player.timeControlStatus == .paused,
            "\(label): mounting a capture does not automatically start playback")
        try expect(mount.window.frame.maxX < 0 && !mount.window.isKeyWindow && !NSApp.isActive,
            "\(label): native video mounting preserves the inactive offscreen fixture")
        print("NATIVE_VIDEO: \(label); controlsStyle=\(view.controlsStyle); duration=\(item.duration.seconds); source=\(url.lastPathComponent)")
        return VideoPlayerProbe(view: view, player: player, item: item)
    }

    private static func seek(_ player: AVPlayer, seconds: Double, mount: VideoMount, label: String) async throws {
        let completed = VideoCompletion()
        // Public sample-accurate transport API; no private slider or ivar.
        // https://developer.apple.com/documentation/avfoundation/avplayer/seek(to:tolerancebefore:toleranceafter:completionhandler:)
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) {
            completed.finish($0)
        }
        let finished = await wait(mount, timeout: 5) { completed.result != nil }
        if !finished { player.currentItem?.cancelPendingSeeks() }
        try expect(finished && completed.result == true && abs(player.currentTime().seconds - seconds) <= 0.07,
            "\(label): a real completed sample-accurate seek reaches its requested time")
    }
    private static func decodedFrame(_ output: AVPlayerItemVideoOutput, player: AVPlayer, mount: VideoMount,
                                     label: String) async throws -> Data {
        var digest: Data?
        let received = await wait(mount, timeout: 5) {
            let time = player.currentTime()
            guard time.isNumeric, output.hasNewPixelBuffer(forItemTime: time),
                  let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { return false }
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            guard let address = CVPixelBufferGetBaseAddress(buffer) else { return false }
            let count = CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer)
            digest = Data(SHA256.hash(data: Data(bytes: address, count: count)))
            return true
        }
        try expect(received && digest != nil, "\(label): the mounted player's actual item outputs a decoded video frame")
        return digest!
    }

    private static func exercise(_ probe: VideoPlayerProbe, mount: VideoMount, label: String) async throws {
        guard let player = probe.retainedPlayer, let item = player.currentItem else { throw failure("\(label): no retained production player") }
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        item.add(output)
        defer { item.remove(output) }
        let duration = item.duration.seconds
        try await seek(player, seconds: 0, mount: mount, label: label)
        try await nativeTransport("Play", player: player, mount: mount, label: label)
        let moving = await wait(mount, timeout: 5) {
            player.timeControlStatus == .playing && player.currentTime().seconds >= 0.2
        }
        try expect(moving && player.rate > 0, "\(label): Play advances the real playback clock")
        let early = try await decodedFrame(output, player: player, mount: mount, label: label)
        try await nativeTransport("Pause", player: player, mount: mount, label: label)
        let stopped = await wait(mount, timeout: 2) { player.rate == 0 && player.timeControlStatus == .paused }
        try expect(stopped, "\(label): Play/Pause activation changes the real transport state")
        let paused = player.currentTime().seconds
        try await Task.sleep(for: .milliseconds(250))
        try expect(player.rate == 0 && player.timeControlStatus == .paused
            && abs(player.currentTime().seconds - paused) < 0.05, "\(label): Pause stops the actual clock instead of only changing a label")
        try await seek(player, seconds: 1.2, mount: mount, label: label)
        try expect(player.rate == 0, "\(label): seeking a paused video preserves its paused state")
        player.play()
        let resumed = await wait(mount, timeout: 5) { player.currentTime().seconds >= 1.4 && player.rate > 0 }
        try expect(resumed, "\(label): playback resumes from the sought position")
        let later = try await decodedFrame(output, player: player, mount: mount, label: label)
        try expect(early != later, "\(label): decoded content advances on the production player, beyond static thumbnail generation")
        player.pause()
        let ended = VideoCompletion()
        let token = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
            ended.finish(true)
        }
        defer { NotificationCenter.default.removeObserver(token) }
        try await seek(player, seconds: max(0, duration - 0.2), mount: mount, label: label)
        player.play()
        let completed = await wait(mount, timeout: 5) { ended.result == true && player.rate == 0 }
        try expect(completed && abs(player.currentTime().seconds - duration) < 0.1,
            "\(label): actual end-of-item notification arrives and playback stops at the movie end")
        try await seek(player, seconds: 0, mount: mount, label: label)
        player.play()
        let replayed = await wait(mount, timeout: 5) { player.currentTime().seconds > 0.15 && player.rate > 0 }
        try expect(replayed, "\(label): seeking to the beginning permits real replay after completion")
        player.pause()
        for size in [NSSize(width: 760, height: 430), NSSize(width: 380, height: 240)] {
            mount.resize(size)
            let fitted = await wait(mount, timeout: 3) {
                guard let view = probe.nativeView, let root = mount.root else { return false }
                return view.videoBounds.width > 0 && view.videoBounds.height > 0
                    && view.bounds.insetBy(dx: -1, dy: -1).contains(view.videoBounds)
                    && abs(view.bounds.width - root.bounds.width) < 1
            }
            try expect(fitted && probe.nativeView?.videoGravity == .resizeAspect,
                "\(label): the complete real video fits its native bounds after resizing to\(Int(size.width))×\(Int(size.height))")
            try expect(probe.nativeView?.player === player && sourceURL(player) == sourceURL(probe.player!),
                "\(label): resizing preserves the same production player and current item")
        }
    }

    private static func released(_ probe: VideoPlayerProbe, mount: VideoMount, label: String) async throws {
        let paused = await wait(mount, timeout: 5) { probe.retainedPlayer?.rate == 0 }
        try expect(paused, "\(label): production onDisappear pauses the outgoing playing item")
        probe.retainedPlayer = nil
        let disposed = await wait(mount, timeout: 10) { probe.player == nil && probe.item == nil && probe.nativeView == nil }
        try expect(disposed, "\(label): outgoing native view, player and item deallocate after releasing the test's observation reference")
    }

    private static func run() async throws {
        let started = ProcessInfo.processInfo.systemUptime
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("DaBinVideoPlayback-\(UUID())", isDirectory: true)
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }
        let landscape = root.appendingPathComponent("Synthetic-landscape.mov")
        let portrait = root.appendingPathComponent("Synthetic-portrait.mov")
        try await makeMovie(at: landscape, width: 160, height: 90, frames: 120, colorOffset: 0)
        try await makeMovie(at: portrait, width: 90, height: 160, frames: 90, colorOffset: 67)
        let sourceBytes = try [landscape, portrait].map { try Data(contentsOf: $0) }
        let store = try CaptureStore(root: root.appendingPathComponent("Archive"), repairArchiveOnOpen: false)
        defer { store.cancelArchiveRepair() }
        var captures: [Capture] = []
        for url in [landscape, portrait] { captures.append(try await store.importFile(url)) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let metadata = try captures.map { try encoder.encode(CaptureSnapshot($0)) }
        try expect(captures.allSatisfy { $0.kind == .video }, "Both synthetic movies import as real video captures")
        for kind in VideoMount.Kind.allCases {
            let mount = VideoMount(size: NSSize(width: 380, height: 240))
            defer { mount.close() }
            let zoom = CaptureZoomState()
            let firstURL = store.managedURL(for: captures[0])!
            mount.show(kind: kind, store: store, capture: captures[0], zoom: zoom, size: NSSize(width: 380, height: 240))
            let first = try await mountedPlayer(mount, url: firstURL, label: "\(kind.rawValue) landscape")
            try await exercise(first, mount: mount, label: "\(kind.rawValue) landscape")
            try await seek(first.retainedPlayer!, seconds: 0, mount: mount, label: "Outgoing landscape")
            first.retainedPlayer!.play()
            let firstMoving = await wait(mount, timeout: 5, { first.retainedPlayer!.rate > 0 && first.retainedPlayer!.currentTime().seconds > 0.1 })
            try expect(firstMoving,
                "The replacement lifecycle starts with an actually playing outgoing capture")
            let secondURL = store.managedURL(for: captures[1])!
            mount.show(kind: kind, store: store, capture: captures[1], zoom: zoom, size: NSSize(width: 380, height: 240))
            let second = try await mountedPlayer(mount, url: secondURL, label: "\(kind.rawValue) portrait replacement")
            try expect(second.player !== first.player && sourceURL(second.retainedPlayer!) == secondURL.standardizedFileURL,
                "Capture replacement displays the second movie through a distinct production-owned player")
            try await released(first, mount: mount, label: "\(kind.rawValue) capture replacement")
            try await exercise(second, mount: mount, label: "\(kind.rawValue) portrait")
            try await seek(second.retainedPlayer!, seconds: 0, mount: mount, label: "Closing portrait")
            second.retainedPlayer!.play()
            let secondMoving = await wait(mount, timeout: 5, { second.retainedPlayer!.rate > 0 && second.retainedPlayer!.currentTime().seconds > 0.1 })
            try expect(secondMoving,
                "The close lifecycle starts with an actually playing capture")
            mount.window.close()
            try await released(second, mount: mount, label: "\(kind.rawValue) native window close")
            try expect(!mount.window.isVisible && !mount.window.isKeyWindow && !NSApp.isActive,
                "Native close removes the fixture window while preserving inactive app ownership")
        }
        for index in captures.indices {
            let original = index == 0 ? landscape : portrait
            try expect(try Data(contentsOf: original) == sourceBytes[index]
                && Data(contentsOf: store.managedURL(for: captures[index])!) == sourceBytes[index]
                && encoder.encode(CaptureSnapshot(captures[index])) == metadata[index],
                "Playback, seeking, replacement and close preserve source bytes, owned original and capture metadata exactly")
        }
        print("NATIVE_CONTROL_COUNTS: actualAXButtonPresses=\(nativeButtonPresses); unavailable=\(unavailableControls.joined(separator: ","))")
        print("BOUNDARIES: Transport is measured on actual production AVPlayerView.player. Native Play/Pause activation is asserted only where a standard named AX button is exposed, and each API fallback is separately reported. Slider dragging, audio, AirPlay, PiP and hardware decoder varieties are not asserted. Live reusable DetailPreview is distinct from DetailScreen's thumbnail/opener flow. Capture replacement follows the production hosting/identity boundary.")
        print("PASS: \(checks) native video playback checks;2 production components ×2 actual MOV captures, clock and decoded-frame advancement, pause/seek/end/replay, fitted resize, capture replacement, native close and deallocation; no external effects. seconds=\(String(format: "%.3f", ProcessInfo.processInfo.systemUptime - started))")
    }
}
