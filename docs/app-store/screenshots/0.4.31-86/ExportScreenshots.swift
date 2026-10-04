@testable import DaBinTestCore
import AppKit
import Foundation
import QuartzCore
import SwiftUI

/// Adapted from design/onepager/ExportGuide.swift. Only fictional native UI is
/// rendered; none of the live application's services/windows are controlled.
@MainActor private final class ScreenshotNotificationClient: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .undetermined }
    func requestAuthorization() async throws -> Bool { fatalError("Screenshot export cannot request permission") }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { fatalError("Screenshot export cannot deliver notifications") }
    func removePending(_ identifiers: [String]) {}
    func removeDelivered(_ identifiers: [String]) {}
}

@MainActor private final class ScreenshotWindow: NSWindow {
    override var backingScaleFactor: CGFloat { 1 }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor private final class ScreenshotCanvas: NSView {
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(red: 0.94, green: 0.97, blue: 0.96, alpha: 1).setFill()
        bounds.fill()
    }
}

@main @MainActor private final class ExportScreenshots: NSObject, NSApplicationDelegate {
    private var result: Int32 = 0
    private var records: [[String: Any]] = []

    static func main() {
        let app = NSApplication.shared, delegate = ExportScreenshots()
        app.setActivationPolicy(.prohibited)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        exit(delegate.result)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await run() }
            catch { result = 1; fputs("App Store screenshot export failed: \(error)\n", stderr) }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }

    private func run() async throws {
        guard CommandLine.arguments.count == 2 else { throw failure("Pass the screenshot-draft output directory") }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinStoreScreenshot-\(UUID().uuidString)", isDirectory: true)
        let suite = "DaBin.StoreScreenshot.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw failure("Isolated preferences unavailable") }
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        defaults.set(false, forKey: PreviewService.linkPreviewPreference)
        let store = try CaptureStore(root: root)
        let stamp = ISO8601DateFormatter().date(from: "2026-10-02T06:40:00Z")!
        let zone = TimeZone(identifier: "Asia/Jerusalem")!
        let project = "Weekend ideas"
        let trail = try await store.importData(landscapePNG(), filename: "Weekend trail.png", at: stamp,
            timeZone: zone, projectName: project)
        try makePreview(trail, title: "A trail worth saving", root: root, alternate: false)
        let water = try await store.importData(landscapePNG(alternate: true), filename: "Morning by the water.png",
            at: stamp.addingTimeInterval(-120), timeZone: zone, projectName: project)
        try makePreview(water, title: "Morning by the water", root: root, alternate: true)
        let note = try store.createNote(text: "A little fresh air\nPick a quiet path, pack a snack, and leave time to explore.",
            at: stamp.addingTimeInterval(-300), projectName: project)
        note.title = "A little fresh air"
        var planning = TaskPlanning()
        planning.plannedDay = CaptureCalendar.dayString(Date())
        planning.effortMinutes = 25
        planning.checklist = [TaskChecklistItem(text: "Choose a quiet route", isCompleted: true),
            TaskChecklistItem(text: "Pack water and a snack"), TaskChecklistItem(text: "Leave room to explore")]
        let task = try store.createTask(text: "Plan a weekend walk", at: stamp.addingTimeInterval(-180),
            timeZone: zone, planning: planning, projectName: project)
        let attachment = try await store.importData(landscapePNG(), filename: "Trail inspiration.png", at: stamp,
            timeZone: zone, parentTask: task)
        try makePreview(attachment, title: "Trail inspiration", root: root, alternate: false)
        let inboxImage = try await store.importData(landscapePNG(alternate: true), filename: "A place to wander.png",
            at: stamp.addingTimeInterval(180), timeZone: zone)
        try makePreview(inboxImage, title: "A place to wander", root: root, alternate: true)
        let inboxNote = try store.createNote(text: "An idea for the weekend\nTry the riverside path and bring a notebook.",
            at: stamp.addingTimeInterval(120))
        inboxNote.title = "An idea for the weekend"
        _ = try store.createTask(text: "Find a new walking route", at: stamp.addingTimeInterval(60), timeZone: zone)
        try store.save()

        let previews = PreviewService(store: store, defaults: defaults)
        let auto = AutoCaptureService(settings: AutoCaptureSettings(defaults: defaults), input: InputService(store: store),
            pasteboardProvider: { fatalError("Screenshot export cannot read the clipboard") }, sourceApplicationProvider: { nil })
        let state = AppState(store: store, previews: previews,
            reminders: ReminderService(store: store, client: ScreenshotNotificationClient()),
            robotPlacement: RobotPlacementSettings(defaults: defaults), autoCapture: auto,
            captureClipboard: CaptureClipboardService(writer: { _ in fatalError("Screenshot export cannot write the clipboard") }),
            quickAccessSettings: QuickAccessSettings(defaults: defaults))
        defer { state.shutdownNotificationPresentation(); state.focusSessions.shutdown(); auto.shutdown(); previews.shutdown() }
        let theme = ThemeSettings(defaults: defaults, systemDarkMode: false)
        theme.setBoardOpacity(1); theme.setDarkMode(false); theme.select(.teal); theme.setShowTooltips(false)
        state.isBoardVisible = true
        try state.workspace.setProjectColor(hex: "198F91", for: project)

        state.openInbox(); state.newNoteText = "Something worth keeping…"; state.status = nil
        try await render(state, theme: theme, filename: "DABIN__APP_STORE__01_INBOX.png",
            headline: "Keep the useful bits.", subtitle: "Save notes, images and files. Sort them when you're ready.", output: output)

        state.clearNewNoteDraft(); state.openLibrary(); state.libraryProject = project
        state.workspace.mode = .collection; state.workspace.selectedCaptureID = trail.id
        state.workspace.explorerShowsDailyFiles = false; state.status = nil
        try await render(state, theme: theme, filename: "DABIN__APP_STORE__02_PROJECTS.png",
            headline: "A home for every project.", subtitle: "Choose a color. Keep your previews, notes and tasks together.", output: output)

        guard state.configureTaskFocus(task, hours: 0, minutes: 25) else { throw failure("Fictional task focus could not be configured") }
        state.openCapture(task.id); state.detailFocus = nil; state.status = nil
        try await render(state, theme: theme, filename: "DABIN__APP_STORE__03_FOCUS.png",
            headline: "Make room for one task.", subtitle: "Choose a duration and start a focus timer when you're ready.", output: output)

        try JSONSerialization.data(withJSONObject: [
            "version": "0.4.31", "build": "86", "status": "DRAFT",
            "fixturePrivacy": "Temporary fictional archive and isolated preference domain, own offscreen non-key windows, no actual clipboard/network/permission/notification/global-input access.",
            "renderMethod": "Actual current-production BoardView and RobotAppFrameView, canonical RobotCharacterView, native 1x cacheDisplay on opaque canvas. Marketing headline/subtitle/backdrop are not app controls.",
            "assets": records
        ], options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("native-renders.json"), options: .atomic)
        print("PASS: \(records.count) fictional native App Store screenshot drafts exported")
    }

    private func failure(_ text: String) -> NSError {
        NSError(domain: "DaBinStoreScreenshot", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }

    private func makePreview(_ capture: Capture, title: String, root: URL, alternate: Bool) throws {
        capture.title = title
        capture.previewDescription = "A quiet path, a bright morning, and a little room to wander."
        let path = "Previews/\(capture.id.uuidString)/thumbnail.png"
        let thumbnail = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: thumbnail.deletingLastPathComponent(), withIntermediateDirectories: true)
        try landscapePNG(alternate: alternate).write(to: thumbnail, options: .atomic)
        capture.thumbnailRelativePath = path; capture.previewState = "ready"
    }

    private func label(_ text: String, size: CGFloat, bold: Bool, frame: CGRect) -> NSTextField {
        let view = NSTextField(labelWithString: text)
        view.font = NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        view.textColor = NSColor(red: 0.10, green: 0.22, blue: 0.21, alpha: 1)
        view.lineBreakMode = .byTruncatingTail; view.maximumNumberOfLines = 1
        view.frame = frame
        return view
    }

    private func render(_ state: AppState, theme: ThemeSettings, filename: String,
                        headline: String, subtitle: String, output: URL) async throws {
        let canvas = ScreenshotCanvas(frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        canvas.wantsLayer = true
        canvas.layer?.backgroundColor = NSColor(red: 0.94, green: 0.97, blue: 0.96, alpha: 1).cgColor
        canvas.addSubview(label(headline, size: 40, bold: true, frame: CGRect(x: 130, y: 38, width: 1070, height: 54)))
        canvas.addSubview(label(subtitle, size: 20, bold: false, frame: CGRect(x: 130, y: 101, width: 1070, height: 30)))
        let mascot = RobotCharacterView(frame: CGRect(x: 1235, y: 18, width: 96, height: 117), reduceMotion: { true })
        canvas.addSubview(mascot)
        let export = DayExportActionController(pasteboardWriter: { _ in false }, destinationChooser: { _, _ in .cancelled }, fileWriter: { _, _ in })
        let hosting = NSHostingView(rootView: BoardView(state: state, theme: theme, dayExportController: export)
            .environment(\.displayScale, 1).transaction { $0.animation = nil; $0.disablesAnimations = true })
        let frame = RobotAppFrameView(contentView: hosting)
        let contentSize = CGSize(width: 1160, height: 652)
        let boardSize = RobotAppFrameView.outerSize(forContentSize: contentSize)
        frame.frame = CGRect(origin: CGPoint(x: (1440 - boardSize.width) / 2, y: 164), size: boardSize)
        canvas.addSubview(frame)
        let window = ScreenshotWindow(contentRect: CGRect(x: -10_000, y: -10_000, width: 1440, height: 900),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.isOpaque = true
        window.backgroundColor = NSColor(red: 0.94, green: 0.97, blue: 0.96, alpha: 1)
        window.contentView = canvas
        CornerController.applyBoardAppearance(darkMode: false, to: window, frame: frame, hosting: hosting)
        window.orderFront(nil)
        // Set the same stable open endpoint without live pointer polling or
        // consulting the user's global animation preference.
        frame.cancelTransition(open: true); frame.viewDidChangeBackingProperties()
        mascot.send(.reveal(.right)); mascot.viewDidChangeBackingProperties()
        defer {
            mascot.stopMotion(); frame.setVisible(false); window.orderOut(nil)
            window.contentView = nil; window.close()
        }
        for _ in 0..<8 { canvas.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(90)) }
        for scroll in scrollViews(in: hosting) {
            guard let document = scroll.documentView else { continue }
            let top = document.isFlipped ? CGFloat(0) : max(0, document.bounds.height - scroll.contentView.bounds.height)
            scroll.contentView.scroll(to: CGPoint(x: 0, y: top)); scroll.reflectScrolledClipView(scroll.contentView)
        }
        for _ in 0..<4 { canvas.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(75)) }
        canvas.displayIfNeeded(); CATransaction.flush()
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1440, pixelsHigh: 900,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { throw failure("RGBA snapshot allocation failed") }
        bitmap.bitmapData?.initialize(repeating: 0, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        bitmap.size = canvas.bounds.size
        canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw failure("Native PNG encoding failed") }
        try png.write(to: output.appendingPathComponent(filename), options: .atomic)
        records.append(["file": filename, "width": 1440, "height": 900, "pixelScale": 1, "nativeBuffer": "RGBA",
            "exportConversion": "Opaque RGB export by companion script, without resizing or repainting native UI", "route": String(describing: state.route), "headline": headline, "subtitle": subtitle,
            "nativeBoardRectFromTopLeft": [frame.frame.minX, frame.frame.minY, frame.frame.width, frame.frame.height],
            "nativeContentSize": [contentSize.width, contentSize.height], "mascot": "Canonical production Quiet Orbit RobotCharacterView",
            "fixtureCaptures": state.store.captures.count, "autoCaptureEnabled": state.autoCapture.settings.isEnabled,
            "websitePreviewsEnabled": state.previews.enabled,
            "fixtureImageProvenance": "Original code-drawn landscapes adapted from ExportGuide.swift; no personal/copyrighted third-party imagery."])
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
    }

    private func landscapePNG(alternate: Bool = false) throws -> Data {
        let size = CGSize(width: 1000, height: 650)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw failure("Landscape fixture allocation failed") }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSColor(red: alternate ? 0.86 : 0.87, green: 0.96, blue: alternate ? 0.99 : 0.94, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor(red: 0.99, green: 0.77, blue: 0.40, alpha: 1).setFill()
        NSBezierPath(ovalIn: CGRect(x: alternate ? 165 : 720, y: 450, width: 100, height: 100)).fill()
        func hill(_ color: NSColor, _ points: [CGPoint]) {
            let path = NSBezierPath(); path.move(to: points[0])
            for point in points.dropFirst() { path.line(to: point) }
            path.close(); color.setFill(); path.fill()
        }
        hill(NSColor(red: 0.47, green: 0.70, blue: 0.64, alpha: 1), [CGPoint(x: 0,y: 0), CGPoint(x: 0,y: 340), CGPoint(x: 250,y: 520), CGPoint(x: 540,y: 310), CGPoint(x: 770,y: 430), CGPoint(x: 1000,y: 280), CGPoint(x: 1000,y: 0)])
        hill(NSColor(red: 0.22, green: 0.53, blue: 0.46, alpha: 1), [CGPoint(x: 0,y: 0), CGPoint(x: 0,y: 190), CGPoint(x: 240,y: 300), CGPoint(x: 550,y: 190), CGPoint(x: 810,y: 290), CGPoint(x: 1000,y: 180), CGPoint(x: 1000,y: 0)])
        hill(NSColor(red: 0.12, green: 0.36, blue: 0.32, alpha: 1), [CGPoint(x: 0,y: 0), CGPoint(x: 0,y: 100), CGPoint(x: 330,y: 180), CGPoint(x: 640,y: 80), CGPoint(x: 1000,y: 130), CGPoint(x: 1000,y: 0)])
        if alternate {
            NSColor(red: 0.30, green: 0.68, blue: 0.73, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: 1000, height: 135).fill()
            NSColor.white.withAlphaComponent(0.35).setStroke()
            for y in [CGFloat(25), CGFloat(65), CGFloat(100)] {
                let wave = NSBezierPath(); wave.move(to: CGPoint(x: 120, y: y)); wave.line(to: CGPoint(x: 830, y: y))
                wave.lineWidth = 3; wave.stroke()
            }
        } else {
            let trail = NSBezierPath(); trail.move(to: CGPoint(x: 515,y: 0))
            trail.curve(to: CGPoint(x: 650,y: 190), controlPoint1: CGPoint(x: 280,y: 135), controlPoint2: CGPoint(x: 660,y: 120))
            trail.lineWidth = 38; NSColor(red: 0.96, green: 0.87, blue: 0.65, alpha: 1).setStroke(); trail.stroke()
        }
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw failure("Landscape PNG failed") }
        return png
    }
}
