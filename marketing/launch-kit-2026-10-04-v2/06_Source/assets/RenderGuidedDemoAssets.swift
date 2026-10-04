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

@main @MainActor private final class RenderGuidedDemoAssets: NSObject, NSApplicationDelegate {
    private var result: Int32 = 0
    private var records: [[String: Any]] = []

    static func main() {
        let app = NSApplication.shared, delegate = RenderGuidedDemoAssets()
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
        guard CommandLine.arguments.count == 2 else { throw failure("Pass output folder") }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinV2Fixture-\(UUID().uuidString)", isDirectory: true)
        let suite = "DaBin.MarketingV2.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw failure("Isolated defaults unavailable") }
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        defaults.set(false, forKey: PreviewService.linkPreviewPreference)
        let store = try CaptureStore(root: root)
        let index = ContentIndexService(store: store)
        let previews = PreviewService(store: store, defaults: defaults)
        let settings = AutoCaptureSettings(defaults: defaults)
        let auto = AutoCaptureService(settings: settings, input: InputService(store: store),
            pasteboardProvider: { fatalError("Fixture cannot read real clipboard") }, sourceApplicationProvider: { nil })
        let state = AppState(store: store, previews: previews, contentIndex: index,
            reminders: ReminderService(store: store, client: ScreenshotNotificationClient()),
            robotPlacement: RobotPlacementSettings(defaults: defaults), autoCapture: auto,
            captureClipboard: CaptureClipboardService(writer: { _ in fatalError("Fixture cannot write real clipboard") }),
            quickAccessSettings: QuickAccessSettings(defaults: defaults))
        defer { index.shutdown(); state.shutdownNotificationPresentation(); state.focusSessions.shutdown(); auto.shutdown(); previews.shutdown() }
        let theme = ThemeSettings(defaults: defaults, systemDarkMode: false)
        theme.setBoardOpacity(1); theme.setDarkMode(false); theme.select(.teal); theme.setShowTooltips(false)
        state.isBoardVisible = true
        let today = Calendar.current.startOfDay(for: Date())
        let stamp = today.addingTimeInterval(9 * 3600)
        let zone = TimeZone.current
        let project = "Studio refresh"
        try await renderMascots(output: output)

        state.openInbox(); state.status = nil
        try await render(state, theme: theme, filename: "DABIN__UI__01_INBOX_EMPTY.png", output: output)
        let screenshot = try await store.importData(referenceScreenshotPNG(), filename: "Studio reference.png", at: stamp, timeZone: zone)
        screenshot.title = "Palette inspiration"
        let thumbPath = "Previews/\(screenshot.id.uuidString)/thumbnail.png"
        let thumbURL = root.appendingPathComponent(thumbPath)
        try FileManager.default.createDirectory(at: thumbURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try referenceScreenshotPNG().write(to: thumbURL)
        screenshot.thumbnailRelativePath = thumbPath; screenshot.previewState = "ready"
        try await render(state, theme: theme, filename: "DABIN__UI__02A_INBOX_IMAGE_CAPTURE.png", output: output)
        let link = try store.capture(text: "https://example.com/studio", at: stamp.addingTimeInterval(60), timeZone: zone).first!
        link.title = "example.com/studio"
        try await render(state, theme: theme, filename: "DABIN__UI__02B_INBOX_LINK_CAPTURE.png", output: output)
        state.newNoteText = "Warm clay. Deep teal. Soft cream."
        try await render(state, theme: theme, filename: "DABIN__UI__02_INBOX_TYPED.png", output: output)
        state.saveNewNote(); state.status = nil
        let note = store.captures.first!
        _ = try store.capture(text: "Riverside studio — choose paper samples", at: stamp.addingTimeInterval(-86400), timeZone: zone)
        _ = try store.capture(text: "A calmer desk, one useful idea at a time.", at: stamp.addingTimeInterval(-172800), timeZone: zone)
        index.process([screenshot])
        for _ in 0..<200 { if !index.isBusy { break }; try await Task.sleep(for: .milliseconds(40)) }
        guard screenshot.contentIndexState == "ready", screenshot.indexedText.localizedCaseInsensitiveContains("riverside") else { throw failure("Real local OCR failed") }
        try store.save()
        state.openInbox(); state.status = nil
        try await render(state, theme: theme, filename: "DABIN__UI__03_INBOX_SAVED.png", output: output)
        state.route = .daily; state.selectedDay = stamp
        try await render(state, theme: theme, filename: "DABIN__UI__04_INBOX_DAY.png", output: output)
        state.openWeekly(); state.setWeekEndingDay(stamp)
        try await render(state, theme: theme, filename: "DABIN__UI__05_INBOX_WEEK.png", output: output)

        note.title = "Palette notes" // The Inbox keeps its original captured text visible before this fictional rename.
        try state.workspace.createProject(name: project, colorHex: "D87552")
        state.assignProject(screenshot, name: project); state.assignProject(link, name: project); state.assignProject(note, name: project)
        state.status = nil; state.openLibrary(); state.libraryProject = project
        state.workspace.mode = .collection; state.workspace.selectedCaptureID = nil
        state.workspace.explorerShowsDailyFiles = false
        try await render(state, theme: theme, filename: "DABIN__UI__06_STUDIO_COLLECTION.png", output: output)
        try state.workspace.setScratchpad(text: "Riverside studio\n\nWarm clay. Deep teal. Soft cream.\nKeep the typography calm and the desk clear.\n\nNext: choose paper samples and finish the palette.", project: project)
        state.workspace.mode = .scratchpad
        try await render(state, theme: theme, filename: "DABIN__UI__07_STUDIO_NOTES.png", output: output)
        try state.workspace.setSnippetName("Studio palette", for: note.id)
        state.workspace.mode = .clipboard; state.workspace.snippetsOnly = false
        try await render(state, theme: theme, filename: "DABIN__UI__08A_CLIPBOARD_HISTORY.png", output: output)
        state.workspace.snippetsOnly = true
        try await render(state, theme: theme, filename: "DABIN__UI__08_NAMED_SNIPPETS.png", output: output)
        try state.workspace.setOnShelf([screenshot.id, note.id, link.id], included: true)
        state.workspace.mode = .shelf; state.workspace.snippetsOnly = false
        try await render(state, theme: theme, filename: "DABIN__UI__09_SHELF.png", output: output)

        state.openSearch(); state.query = "riverside"; state.status = nil
        try await render(state, theme: theme, filename: "DABIN__UI__10_OCR_SEARCH.png", output: output)
        state.searchSelectedResultID = "capture:" + screenshot.id.uuidString
        try await render(state, theme: theme, filename: "DABIN__UI__11_OCR_PREVIEW.png", output: output)
        state.selectSearchProject(project); state.filter = .media; state.setSearchDay(stamp)
        state.searchSelectedResultID = nil
        try await render(state, theme: theme, filename: "DABIN__UI__12_FILTERED_SEARCH.png", output: output)

        state.openLibrary(); state.libraryProject = project; state.workspace.mode = .collection
        state.openNewTask()
        state.newTaskDraft.text = "Finish the studio palette"
        var planning = TaskPlanning()
        planning.plannedDay = CaptureCalendar.dayString(today)
        planning.priority = .high; planning.effortMinutes = 25
        planning.checklist = [TaskChecklistItem(text: "Choose three colors", isCompleted: true), TaskChecklistItem(text: "Check the paper samples"), TaskChecklistItem(text: "Share the final palette")]
        planning.recurrence = .weekly
        state.newTaskDraft.planning = planning
        state.newTaskDraft.reminderEnabled = true; state.newTaskDraft.reminderMode = .countdown
        state.newTaskDraft.countdownHours = 0; state.newTaskDraft.countdownMinutes = 30
        try await render(state, theme: theme, filename: "DABIN__UI__13_TASK_PLAN.png", output: output)
        try await render(state, theme: theme, filename: "DABIN__UI__14_TASK_REPEAT_REMINDER.png", output: output, bottom: true)
        // Persist the same fictional task directly without scheduling a real OS notification.
        let task = try store.createTask(text: "Finish the studio palette", reminderAt: Date().addingTimeInterval(1800), at: stamp.addingTimeInterval(120), timeZone: zone, planning: planning, projectName: project)
        try store.save()
        state.cancelNewTask(); state.status = nil
        state.showReminders()
        try await render(state, theme: theme, filename: "DABIN__UI__15_TODAY.png", output: output)
        guard state.configureTaskFocus(task, hours: 0, minutes: 25) else { throw failure("Focus setup failed") }
        state.openCapture(task.id); state.detailFocus = nil; state.status = nil
        try await render(state, theme: theme, filename: "DABIN__UI__16_FOCUS_READY.png", output: output)
        guard state.toggleTaskFocus(task, at: Date().addingTimeInterval(-2)) else { throw failure("Focus start failed") }
        try await render(state, theme: theme, filename: "DABIN__UI__17_FOCUS_RUNNING.png", output: output)
        _ = state.toggleTaskFocus(task)
        try await renderAlarm(output: output)

        state.showSettings(); state.status = nil
        try await render(state, theme: theme, filename: "DABIN__UI__18_AUTO_CAPTURE_OFF.png", output: output)
        // Demonstrate persisted opt-ins while deliberately keeping both monitoring runtimes inert.
        settings.acknowledgePrivacyExplanation(); settings.setClipboardEnabled(true); settings.setScreenshotsEnabled(true)
        settings.setPaused(true); settings.setStatus(.paused)
        try await render(state, theme: theme, filename: "DABIN__UI__19_AUTO_CAPTURE_PAUSED.png", output: output)
        settings.setEnabled(false); settings.setStatus(.disabled)
        state.openLibrary(); state.libraryProject = project; state.workspace.mode = .collection
        try await render(state, theme: theme, filename: "DABIN__UI__20_PROJECT_EXPORT.png", output: output)
        let temporaryNote = try store.createNote(text: "An earlier palette idea", at: stamp.addingTimeInterval(-300), projectName: project)
        temporaryNote.title = "Earlier palette idea"
        await state.removeCapture(temporaryNote); state.status = nil; state.showTrash()
        try await render(state, theme: theme, filename: "DABIN__UI__21_RECENTLY_DELETED.png", output: output)
        guard let trashed = store.trashedCaptures.first else { throw failure("Deleted fixture missing") }
        await state.restoreCapture(trashed); state.status = nil; state.openLibrary(); state.libraryProject = project
        state.workspace.selectedCaptureID = temporaryNote.id
        let restoredFirst = [ProjectWorkspaceIdentity.capture(temporaryNote.id)] + ProjectWorkspaceContents.captures(in: project, from: store.captures).filter { $0.id != temporaryNote.id }.map { ProjectWorkspaceIdentity.capture($0.id) } + [ProjectWorkspaceIdentity.note(project: project)]
        try state.workspace.saveProjectItemOrder(restoredFirst, project: project)
        try await render(state, theme: theme, filename: "DABIN__UI__22_RESTORED.png", output: output)

        try JSONSerialization.data(withJSONObject: ["version": "0.4.31", "build": "86", "status": "NATIVE_FICTIONAL_GUIDED_DEMO_STATES", "privacy": "Isolated temporary local archive, isolated preferences, offscreen non-key windows. No real clipboard, network, permission requests, live app actions or OS notifications. Auto Capture settings are paused and its runtime never starts.", "realLocalOCR": screenshot.indexedText, "assets": records], options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("native-v2-renders.json"))
        print("PASS: \(records.count) safe actual native UI states; real local OCR: \(screenshot.indexedText)")
    }
    private func failure(_ text: String) -> NSError {
        NSError(domain: "DaBinMarketingFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
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

    private func render(_ state: AppState, theme: ThemeSettings, filename: String, output: URL, bottom: Bool = false) async throws {
        let contentSize = CGSize(width: 1160, height: 652)
        let boardSize = RobotAppFrameView.outerSize(forContentSize: contentSize)
        let canvas = ScreenshotCanvas(frame: CGRect(origin: .zero, size: boardSize))
        canvas.wantsLayer = true
        canvas.layer?.backgroundColor = NSColor(red: 0.969, green: 0.953, blue: 0.922, alpha: 1).cgColor
        let export = DayExportActionController(pasteboardWriter: { _ in false }, destinationChooser: { _, _ in .cancelled }, fileWriter: { _, _ in })
        let hosting = NSHostingView(rootView: BoardView(state: state, theme: theme, dayExportController: export)
            .environment(\.displayScale, 2).transaction { $0.animation = nil; $0.disablesAnimations = true })
        let frame = RobotAppFrameView(contentView: hosting)
        frame.frame = CGRect(origin: .zero, size: boardSize); canvas.addSubview(frame)
        let window = ScreenshotWindow(contentRect: CGRect(x: -10000, y: -10000, width: boardSize.width, height: boardSize.height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.isOpaque = true
        window.backgroundColor = NSColor(red: 0.969, green: 0.953, blue: 0.922, alpha: 1)
        window.contentView = canvas
        CornerController.applyBoardAppearance(darkMode: false, to: window, frame: frame, hosting: hosting)
        window.orderFront(nil); frame.cancelTransition(open: true); frame.viewDidChangeBackingProperties()
        defer { frame.setVisible(false); window.orderOut(nil); window.contentView = nil; window.close() }
        for _ in 0..<8 { canvas.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(70)) }
        if bottom, let scroll = scrollViews(in: hosting).first, let document = scroll.documentView {
            for _ in 0..<6 {
                let y = document.isFlipped ? max(0, document.bounds.height - scroll.contentView.bounds.height) : 0
                scroll.contentView.scroll(to: CGPoint(x: 0, y: y)); scroll.reflectScrolledClipView(scroll.contentView)
                canvas.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(50))
            }
        }
        for _ in 0..<3 { canvas.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(50)) }
        canvas.displayIfNeeded(); CATransaction.flush()
        let w = Int(boardSize.width * 2), h = Int(boardSize.height * 2)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.bitmapData?.initialize(repeating: 0, count: bitmap.bytesPerRow * bitmap.pixelsHigh); bitmap.size = canvas.bounds.size
        canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(filename))
        records.append(["file": filename, "width": w, "height": h, "pixelScale": 2, "route": String(describing: state.route), "nativeContentSize": [1160,652], "scroll": bottom ? "bottom" : "current/top", "captureCount": state.store.captures.count, "autoCaptureRuntime": state.autoCapture.isRunning, "autoCaptureStatus": state.autoCapture.overallStatusText, "linkPreviews": state.previews.enabled])
        print("Exported \(filename)")
    }

    private func renderMascots(output: URL) async throws {
        for (name, event) in [("idle", RobotMotionEvent.feedbackExpired), ("hungry", RobotMotionEvent.acceptedDrag(true)), ("delighted", RobotMotionEvent.result(.success)), ("puzzled", RobotMotionEvent.result(.failure)), ("curious_left", RobotMotionEvent.hover(true, pointer: CGPoint(x: -1, y: 0))), ("curious_right", RobotMotionEvent.hover(true, pointer: CGPoint(x: 1, y: 0))), ("blink", RobotMotionEvent.feedbackExpired)] {
            let mascot = RobotCharacterView(frame: CGRect(x: 0, y: 0, width: 1024, height: 1248), reduceMotion: { true })
            let window = ScreenshotWindow(contentRect: mascot.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.setFrameOrigin(CGPoint(x: -10000, y: -10000)); window.isReleasedWhenClosed = false
            window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false; window.contentView = mascot; window.orderFront(nil)
            mascot.send(.reveal(.top)); mascot.send(event); mascot.viewDidChangeBackingProperties()
            if name == "blink" { mascot.applyCaptureSignPartPose(RobotCaptureSignPartPose(normalizedTime: 0, gaze: .zero, headOpacity: 1, torsoOpacity: 1, eyeScaleY: 0.08)) }
            for _ in 0..<6 { mascot.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(60)) }
            mascot.displayIfNeeded(); CATransaction.flush()
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1248,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { throw failure("Robot allocation failed") }
            bitmap.bitmapData?.initialize(repeating: 0, count: bitmap.bytesPerRow * bitmap.pixelsHigh); bitmap.size = mascot.bounds.size
            mascot.cacheDisplay(in: mascot.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("DABIN__ROBOT_CANVAS__\(name.uppercased()).png"))
            mascot.stopMotion(); window.orderOut(nil); window.contentView = nil; window.close()
        }
    }

    private func renderAlarm(output: URL) async throws {
        let view = TaskTimerRobotView(frame: CGRect(x: 0, y: 0, width: 960, height: 630), reduceMotion: { true })
        let window = ScreenshotWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.setFrameOrigin(CGPoint(x: -10000, y: -10000)); window.isReleasedWhenClosed = false
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false; window.contentView = view; window.orderFront(nil)
        view.show(taskTitle: "Finish the studio", reduceMotion: true)
        for _ in 0..<6 { view.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(50)) }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 960, pixelsHigh: 630, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.bitmapData?.initialize(repeating: 0, count: bitmap.bytesPerRow * bitmap.pixelsHigh); bitmap.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("DABIN__ROBOT__FOCUS_ALARM_CANVAS.png"))
        view.reset(); window.orderOut(nil); window.contentView = nil; window.close()
    }

    private func referenceScreenshotPNG() throws -> Data {
        let size = CGSize(width: 1000, height: 650)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1000, pixelsHigh: 650,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSColor(red: 0.98, green: 0.96, blue: 0.91, alpha: 1).setFill(); NSRect(origin: .zero, size: size).fill()
        let titleStyle: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 74, weight: .semibold), .foregroundColor: NSColor(red: 0.10, green: 0.22, blue: 0.21, alpha: 1)]
        ("Riverside studio" as NSString).draw(at: CGPoint(x: 65, y: 486), withAttributes: titleStyle)
        let style: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 30), .foregroundColor: NSColor(red: 0.20, green: 0.31, blue: 0.30, alpha: 1)]
        ("Warm clay. Deep teal. Soft cream." as NSString).draw(at: CGPoint(x: 65, y: 420), withAttributes: style)
        let palette: [(NSColor, String)] = [(NSColor(red: 0.84, green: 0.45, blue: 0.30, alpha: 1), "Clay"), (NSColor(red: 0.08, green: 0.38, blue: 0.37, alpha: 1), "Teal"), (NSColor(red: 0.88, green: 0.83, blue: 0.69, alpha: 1), "Cream")]
        for (n, item) in palette.enumerated() {
            item.0.setFill(); NSBezierPath(roundedRect: CGRect(x: 65 + n * 302, y: 138, width: 265, height: 218), xRadius: 18, yRadius: 18).fill()
            (item.1 as NSString).draw(at: CGPoint(x: 65 + n * 302, y: 83), withAttributes: style)
        }
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("DABIN__SAMPLE__STUDIO_REFERENCE.png"))
        return bitmap.representation(using: .png, properties: [:])!
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
