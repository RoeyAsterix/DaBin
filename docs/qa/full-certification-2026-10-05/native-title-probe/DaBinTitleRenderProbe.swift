@testable import DaBinTestCore
import AppKit
import AVFoundation
import Foundation
import SwiftUI

@MainActor private final class ProbeNotifications: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .undetermined }
    func requestAuthorization() async throws -> Bool { fatalError("Title probe must not request notification permission") }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { fatalError("Title probe must not schedule notifications") }
    func removePending(_ identifiers: [String]) {}
    func removeDelivered(_ identifiers: [String]) {}
}

/// Separate visible fixture app. Production views and the native title field are
/// used unchanged; no installed DaBin instance or personal data is inspected.
@main @MainActor private final class DaBinTitleRenderProbe: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private static let fixtureTitle = "Fictional longer task title for a narrow desktop companion window with readable planning controls"
    @MainActor private final class Services {
        let root: URL
        let preferencesName = "DaBin.NativeTitleProbe.\(UUID().uuidString)"
        let defaults: UserDefaults
        let store: CaptureStore
        let previews: PreviewService
        let auto: AutoCaptureService
        let state: AppState
        let theme: ThemeSettings
        let exports: DayExportActionController
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBin-NativeTitleProbe-\(UUID().uuidString)")
            defaults = UserDefaults(suiteName: preferencesName)!
            defaults.set(false, forKey: PreviewService.linkPreviewPreference)
            do { store = try CaptureStore(root: root, repairArchiveOnOpen: false) }
            catch {
                defaults.removePersistentDomain(forName: preferencesName)
                try? FileManager.default.removeItem(at: root)
                throw error
            }
            previews = PreviewService(store: store, defaults: defaults)
            auto = AutoCaptureService(settings: AutoCaptureSettings(defaults: defaults), input: InputService(store: store),
                pasteboardProvider: { fatalError("Title probe must not read the clipboard") }, sourceApplicationProvider: { nil })
            state = AppState(store: store, previews: previews,
                reminders: ReminderService(store: store, client: ProbeNotifications()),
                updates: SoftwareUpdateService(bundle: .main), autoCapture: auto,
                captureClipboard: CaptureClipboardService(writer: { _ in fatalError("Title probe must not write the clipboard") }),
                folderOpener: { _ in fatalError("Title probe must not open Finder") })
            theme = ThemeSettings(defaults: defaults)
            theme.setShowTooltips(false); theme.setDarkMode(false)
            exports = DayExportActionController(pasteboardWriter: { _ in fatalError("Title probe must not export to clipboard") },
                destinationChooser: { _, _ in .cancelled }, fileWriter: { _, _ in fatalError("Title probe must not export files") })
        }
        func close() {
            previews.shutdown(); auto.shutdown(); state.focusSessions.shutdown()
            state.shutdownNotificationPresentation(); store.cancelArchiveRepair()
            defaults.removePersistentDomain(forName: preferencesName)
            try? FileManager.default.removeItem(at: root)
        }
    }
    private var services: Services?
    private var window: NSWindow?
    private var host: NSHostingView<AnyView>?
    private var lifetime: Timer?
    private var extended: CaptureExtendedWindowController?
    private var videoCapture: Capture?
    private var videoPreparation: Task<Void, Never>?
    private var output: URL!
    private var finished = false
    private var result = 0

    static func main() {
        let app = NSApplication.shared, delegate = DaBinTitleRenderProbe()
        app.setActivationPolicy(.regular); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        exit(Int32(delegate.result))
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        output = CommandLine.arguments.count > 1 ? URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true) :
            Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("output", isDirectory: true)
        if let override = ProcessInfo.processInfo.environment["DABIN_NATIVE_TITLE_PROBE_OUTPUT"] {
            output = URL(fileURLWithPath: override, isDirectory: true)
        }
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try showFixture()
            installProbeMenu()
            lifetime = Timer.scheduledTimer(withTimeInterval: 180, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.finish(reason: "180-second observation limit") }
            }
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                guard let self, !self.finished else { return }
                do { try self.recordReady() }
                catch { self.result = 1; self.finish(reason: "Capture failed: \(error)") }
            }
        } catch { result = 1; finish(reason: "Setup failed: \(error)") }
    }
    private func showFixture() throws {
        let size = CGSize(width: 380, height: 680)
        let services = try Services(); self.services = services
        let plan = TaskPlanning(priority: .high, checklist: [
            TaskChecklistItem(text: "Fictional multiline planning step that remains readable while the desktop window is narrow"),
            TaskChecklistItem(text: "Fictional completed step", isCompleted: true)])
        let capture = try services.store.createTask(text: Self.fixtureTitle, planning: plan)
        try services.store.setOrganization(capture, pinned: false, projectName: "Fictional project with a deliberately descriptive name")
        services.state.openCapture(capture.id, focus: "task"); services.state.workspaceZoom.setFactor(1)
        let host = NSHostingView(rootView: AnyView(BoardView(state: services.state, theme: services.theme,
            dayExportController: services.exports)
            .environment(\.workspaceZoom, WorkspaceZoomLayout(factor: 1))
            .environment(\.displayScale, 2).environment(\.daBinTooltipsEnabled, false)
            .preferredColorScheme(.light)))
        host.sizingOptions = []; host.frame = NSRect(origin: .zero, size: size); self.host = host
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "DaBin native title probe — fictional data"
        window.isReleasedWhenClosed = false; window.delegate = self
        window.contentView = host; self.window = window
        window.backgroundColor = .clear; window.isOpaque = false
        window.center()
        if let screen = window.screen ?? NSScreen.main, !screen.visibleFrame.contains(window.frame) {
            throw NSError(domain: "DaBinTitleRenderProbe", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Physical screen cannot contain the unchanged 380×680 content viewport"])
        }
        services.state.onDismiss = { [weak self] in self?.finish(reason: "Production Board close") }
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        host.layoutSubtreeIfNeeded(); window.makeFirstResponder(nil)
    }
    private func installProbeMenu() {
        let main = NSMenu(), appItem = NSMenuItem(), appMenu = NSMenu()
        let quit = NSMenuItem(title: "Quit DaBin title probe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.addItem(quit); appItem.submenu = appMenu; main.addItem(appItem)
        let probeItem = NSMenuItem(title: "Probe", action: nil, keyEquivalent: ""), probe = NSMenu(title: "Probe")
        let video = NSMenuItem(title: "Open synthetic video", action: #selector(showVideo(_:)), keyEquivalent: "2")
        video.target = self; probe.addItem(video)
        let title = NSMenuItem(title: "Return to task title", action: #selector(showTitle(_:)), keyEquivalent: "1")
        title.target = self; probe.addItem(title); probeItem.submenu = probe; main.addItem(probeItem)
        NSApp.mainMenu = main
    }
    @objc private func showTitle(_ sender: Any?) {
        extended?.window.performClose(nil); window?.makeKeyAndOrderFront(nil); window?.makeFirstResponder(nil)
    }
    @objc private func showVideo(_ sender: Any?) {
        guard !finished, let services, videoPreparation == nil else { return }
        if let videoCapture { presentVideo(videoCapture); return }
        videoPreparation = Task { [weak self] in
            guard let self else { return }
            defer { self.videoPreparation = nil }
            do {
                let url = services.root.appendingPathComponent("Synthetic-silent-motion.mov")
                try await self.makeVideo(at: url)
                try Task.checkCancellation()
                guard !self.finished else { return }
                let capture = try await services.store.importFile(url)
                guard capture.kind == .video else { throw NSError(domain: "DaBinTitleRenderProbe", code: 5) }
                self.videoCapture = capture; self.presentVideo(capture)
                let report: [String: Any] = ["syntheticSource": url.path, "captureKind": capture.kind.rawValue,
                    "durationSeconds": 8, "audioTracks": 0, "surface": "Production CaptureExtendedWindowController and ExtendedCaptureCanvas",
                    "transport": "Unmodified production SwiftUI VideoPlayer / AVKit controls", "pid": ProcessInfo.processInfo.processIdentifier]
                try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                    .write(to: self.output.appendingPathComponent("video-ready.json"), options: .atomic)
            } catch {
                if !self.finished { fputs("Synthetic video probe failed: \(error)\n", stderr) }
            }
        }
    }
    private func presentVideo(_ capture: Capture) {
        guard let services else { return }
        if extended == nil { extended = CaptureExtendedWindowController(state: services.state, theme: services.theme) }
        extended?.show(capture: capture, draft: CaptureDraft(capture: capture))
    }
    private func makeVideo(at url: URL) async throws {
        let width = 320, height = 180
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        defer { if writer.status == .writing { writer.cancelWriting() } }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height])
        guard writer.canAdd(input) else { throw NSError(domain: "DaBinTitleRenderProbe", code: 6) }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? NSError(domain: "DaBinTitleRenderProbe", code: 7) }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<240 {
            try Task.checkCancellation()
            let deadline = Date().addingTimeInterval(10)
            while !input.isReadyForMoreMediaData && writer.status == .writing && Date() < deadline {
                try await Task.sleep(for: .milliseconds(5))
            }
            guard input.isReadyForMoreMediaData, writer.status == .writing else {
                throw writer.error ?? NSError(domain: "DaBinTitleRenderProbe", code: 8)
            }
            var optionalBuffer: CVPixelBuffer?
            let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary, &optionalBuffer)
            guard status == kCVReturnSuccess, let buffer = optionalBuffer else { throw NSError(domain: "DaBinTitleRenderProbe", code: 9) }
            CVPixelBufferLockBaseAddress(buffer, [])
            guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw NSError(domain: "DaBinTitleRenderProbe", code: 10) }
            let stride = CVPixelBufferGetBytesPerRow(buffer), bytes = base.assumingMemoryBound(to: UInt8.self)
            for y in 0..<height { for x in 0..<width {
                let offset = y * stride + x * 4
                bytes[offset] = UInt8((x + frame * 3) % 256); bytes[offset + 1] = UInt8(y % 256)
                bytes[offset + 2] = UInt8((frame * 4) % 256); bytes[offset + 3] = 255
            } }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30)) else {
                throw writer.error ?? NSError(domain: "DaBinTitleRenderProbe", code: 11)
            }
        }
        input.markAsFinished(); await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? NSError(domain: "DaBinTitleRenderProbe", code: 12) }
    }
    private func nativeFields(_ view: NSView) -> [[String: Any]] {
        var records: [[String: Any]] = []
        if let text = view as? NSTextField, text.isEditable {
            let frame = window!.convertToScreen(text.convert(text.bounds, to: nil))
            var record: [String: Any] = ["class": NSStringFromClass(type(of: text)), "value": text.stringValue,
                "fullFixtureTitle": text.stringValue == Self.fixtureTitle, "maximumNumberOfLines": text.maximumNumberOfLines,
                "frame": NSStringFromRect(frame), "fontSize": text.font?.pointSize ?? 0]
            if let cell = text.cell {
                record["wraps"] = cell.wraps; record["scrollable"] = cell.isScrollable
                record["usesSingleLineMode"] = cell.usesSingleLineMode
            }
            records.append(record)
        }
        for child in view.subviews { records += nativeFields(child) }
        return records
    }
    private func recordReady() throws {
        guard let host, let window, let services else { return }
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded(); window.makeFirstResponder(nil)
        guard window.isVisible, !window.styleMask.contains(.fullScreen),
              abs(host.bounds.width - 380) < 0.5, abs(host.bounds.height - 680) < 0.5,
              services.state.selectedCapture?.title == Self.fixtureTitle else {
            throw NSError(domain: "DaBinTitleRenderProbe", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Probe must retain the visible production viewport and complete title"])
        }
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 760, pixelsHigh: 1360,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0) else { throw NSError(domain: "DaBinTitleRenderProbe", code: 3) }
        bitmap.size = host.bounds.size; host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain: "DaBinTitleRenderProbe", code: 4) }
        try png.write(to: output.appendingPathComponent("cache-display-visible-window@2x.png"))
        let report: [String: Any] = ["processName": ProcessInfo.processInfo.processName,
            "pid": ProcessInfo.processInfo.processIdentifier, "windowNumber": window.windowNumber,
            "windowTitle": window.title, "windowFrame": NSStringFromRect(window.frame),
            "contentBounds": NSStringFromRect(host.bounds), "backingScaleFactor": window.backingScaleFactor,
            "physicalScreenFrame": window.screen.map { NSStringFromRect($0.frame) } ?? "none",
            "windowVisible": window.isVisible, "fullscreen": window.styleMask.contains(.fullScreen),
            "keyWindow": window.isKeyWindow, "appActive": NSApp.isActive,
            "firstResponder": window.firstResponder.map { NSStringFromClass(type(of: $0)) } ?? "none",
            "titleFocusRequested": false, "detailFocus": services.state.detailFocus ?? "none",
            "nativeEditableFields": nativeFields(host), "fullFixtureTitle": Self.fixtureTitle,
            "width": 380, "height": 680, "zoom": 1, "theme": "light", "automaticLifetimeSeconds": 180,
            "privateStore": services.root.path, "privatePreferences": services.preferencesName,
            "snapshotMethod": "cacheDisplay after native layout/display; physical observation supplied separately by root",
            "limitations": "Visible fixture only; no claim that cached pixels represent physical window pixels until compared"]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("launch-ready.json"), options: .atomic)
        print("READY DaBinTitleRenderProbe \(ProcessInfo.processInfo.processIdentifier) \(output.path)")
        fflush(stdout)
    }
    private func finish(reason: String, terminate: Bool = true) {
        guard !finished else { return }; finished = true
        lifetime?.invalidate(); lifetime = nil
        videoPreparation?.cancel(); videoPreparation = nil
        extended?.shutdown(); extended = nil; videoCapture = nil
        let archive = services?.root, preferencesName = services?.preferencesName
        window?.delegate = nil; window?.orderOut(nil); window?.contentView = nil; window?.close()
        host = nil; window = nil; services?.close(); services = nil
        if let output {
            let report: [String: Any] = ["reason": reason, "archiveRemoved": archive.map { !FileManager.default.fileExists(atPath: $0.path) } ?? true,
                "preferencesName": preferencesName ?? "none", "windowsClosed": true, "servicesShutdown": true,
                "processPID": ProcessInfo.processInfo.processIdentifier, "result": result]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: output.appendingPathComponent("cleanup.json"), options: .atomic)
            }
        }
        if terminate { NSApp.terminate(nil) }
    }
    func windowWillClose(_ notification: Notification) { finish(reason: "Native window close") }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { finish(reason: "Application termination", terminate: false) }
}
