@testable import DaBinTestCore
import AppKit
import CoreText
import Foundation
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// Production views, production persistence/index/actions, and only fictional data.
/// This executable is never linked into DaBin. It never reads the general pasteboard.
@MainActor
private final class WalkthroughNotifications: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .undetermined }
    func requestAuthorization() async throws -> Bool { fatalError("Walkthrough must not request permissions") }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { fatalError("Walkthrough must not deliver notifications") }
    func removePending(_ identifiers: [String]) {}
    func removeDelivered(_ identifiers: [String]) {}
}

/// Offscreen media surface: supplies an explicit 2× backing contract even when
/// the attached physical display is 1×. It is never used by the application.
@MainActor private final class WalkthroughWindow: NSWindow {
    override var backingScaleFactor: CGFloat { 2 }
}

@main @MainActor
private final class WalkthroughRenderTests: NSObject, NSApplicationDelegate {
    private var result = 0
    private var records: [[String: Any]] = []
    private var theme: ThemeSettings!
    private var output: URL!
    private var retainedWindows: [NSWindow] = []
    private var restoredPDFTiles = 0
    private struct Failure: Error { let message: String }

    static func main() {
        let app = NSApplication.shared
        let delegate = WalkthroughRenderTests()
        app.setActivationPolicy(.prohibited)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        exit(Int32(delegate.result))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await run() }
            catch { result = 1; fputs("Walkthrough render failed: \(error)\n", stderr) }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }

    private func run() async throws {
        guard CommandLine.arguments.count == 3 else { throw Failure(message: "Output and fixture paths required") }
        output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let fixtureText = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBin-Walkthrough-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "DaBin.Walkthrough.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        theme = ThemeSettings(defaults: defaults)
        theme.setDarkMode(true)
        theme.setBoardOpacity(1)
        let store = try CaptureStore(root: root)
        let previews = PreviewService(store: store, defaults: defaults)
        let index = ContentIndexService(store: store)
        defer { previews.shutdown(); index.shutdown() }
        let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: URL(fileURLWithPath: "Resources/Info.plist")), format: nil) as! [String: Any]
        let updates = SoftwareUpdateService(currentVersion: info["CFBundleShortVersionString"] as! String,
            currentBuild: info["CFBundleVersion"] as! String,
            manifestURL: SoftwareUpdateConfiguration.manifestURL(),
            transport: SoftwareUpdateTransport(loadData: { _ in throw Failure(message: "Network forbidden in walkthrough") },
                download: { _ in throw Failure(message: "Network forbidden in walkthrough") }),
            updatesDirectory: root.appendingPathComponent("Updates"), helperURL: root.appendingPathComponent("Unused helper"),
            validateHelper: { _ in throw Failure(message: "Installer forbidden in walkthrough") },
            launchInstaller: { _, _ in throw Failure(message: "Installer forbidden in walkthrough") })
        let state = AppState(store: store, previews: previews, contentIndex: index,
            reminders: ReminderService(store: store, client: WalkthroughNotifications()), updates: updates)
        guard !state.autoCapture.settings.isEnabled, !previews.enabled else {
            throw Failure(message: "Demo Auto Capture and link previews must default to off")
        }
        let today = Calendar.current.startOfDay(for: Date())
        // Stable daily receipt times; stay before the real clock so the live
        // export UI can include the new capture without a fake future clock.
        let receiptTime = min(today.addingTimeInterval(8 * 3600 + 4 * 60), Date().addingTimeInterval(-60))
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: today)!
        _ = try store.capture(text: "Sketch the welcome screen", at: twoDaysAgo.addingTimeInterval(11 * 3600))
        _ = try store.capture(text: "Gather feedback for the preview build", at: yesterday.addingTimeInterval(14 * 3600))
        _ = try store.capture(text: "A quiet place for today's ideas.", at: receiptTime.addingTimeInterval(-19 * 60))
        state.openDaily()
        try await board(state, "01-daily-before")
        state.isDailyDropTargeted = true
        try await board(state, "02-drop-target")
        state.isDailyDropTargeted = false

        let data = try fixturePDF(text: fixtureText)
        try data.write(to: output.appendingPathComponent("Launch-plan.pdf"), options: .atomic)
        let pdf = try await store.importData(data, filename: "Launch-plan.pdf", at: receiptTime)
        state.reportCaptureResult([pdf], errors: [])
        index.process([pdf])
        previews.process([pdf])
        let deadline = Date().addingTimeInterval(15)
        while (index.isBusy || pdf.previewState == "loading") && Date() < deadline {
            try await Task.sleep(for: .milliseconds(30))
        }
        guard pdf.kind == .pdf, pdf.contentIndexState == "ready",
              pdf.indexedText.lowercased().contains("launch checklist"),
              pdf.previewState == "ready" else {
            throw Failure(message: "Actual PDF extraction or preview did not succeed")
        }
        try await board(state, "03-capture-success")
        state.status = nil
        try await board(state, "04-daily-captured")
        state.filter = .files
        try await board(state, "05-daily-files")
        state.filter = .all
        state.selectTimelineMode(.weekly)
        guard state.weeklyVisibleDays.count == 7, state.weeklyActiveDays.count == 3 else {
            throw Failure(message: "Expected all 7 selected dates with exactly 3 active days")
        }
        try await board(state, "06-weekly", width: 1440)
        try await popover(WeeklySearchPopover(state: state, isPresented: .constant(true)),
                           "07-week-search-menu", width: 258, height: 174)
        state.openSearch(week: state.weeklyDays)
        state.query = ""
        try await board(state, "08-search-empty")
        for (name, query) in [("09-search-launch", "launch"), ("10-search-launch-check", "launch check"),
                              ("11-search-result", "launch checklist")] {
            state.query = query
            try await board(state, name)
        }
        let matchingEntries = state.searchGroups.flatMap(\.entries).filter(\.isMatch)
        guard matchingEntries.count == 1, matchingEntries[0].capture.id == pdf.id,
              matchingEntries[0].indexedTextMatch != nil else {
            throw Failure(message: "Search must match actual extracted PDF text, not a title or fabricated snippet")
        }
        state.openCapture(pdf.id)
        try await board(state, "12-detail-before")
        state.detailFocus = "comment"
        try await board(state, "13-comment-empty", scroll: 1)
        state.selectedDraft?.comment = "Review this before sharing the preview."
        try await board(state, "14-comment-draft", scroll: 1)
        state.saveDetail()
        guard pdf.comment == "Review this before sharing the preview.", state.selectedDraft?.hasChanges == false else {
            throw Failure(message: "Comment save did not persist")
        }
        try await board(state, "15-comment-saved", scroll: 1)
        state.detailFocus = nil
        state.openCapture(pdf.id)
        try await board(state, "16-before-task")
        state.convertToTask(pdf)
        guard pdf.isTask, pdf.kind == .pdf else { throw Failure(message: "Task conversion must preserve PDF") }
        try await board(state, "17-task-created")
        state.status = nil
        state.showCaptureDay(pdf)
        try await board(state, "18-daily-task")
        state.toggleTaskCompletion(pdf)
        try await Task.sleep(for: .milliseconds(80))
        try await board(state, "19-daily-completed")
        guard pdf.isCompleted else { throw Failure(message: "Task completion did not save") }
        state.showSettings()
        try await board(state, "20-settings-auto-off")
        try await board(state, "21-settings-local", scrollY: 455)
        state.openDaily()
        state.selectTimelineMode(.weekly)
        try await board(state, "22-weekly-export", width: 780)
        var exportedText = ""
        let export = DayExportActionController(pasteboardWriter: { exportedText = $0; return true },
            destinationChooser: { _, _ in .cancelled }, fileWriter: { _, _ in
                throw Failure(message: "Walkthrough must not write outside its fixture output")
            })
        try await popover(WeeklyExportPopover(state: state, controller: export, reportFailure: { _ in }),
                           "23-export-menu", width: 262, height: 286)
        let dayDocument = DayExportDocument.make(captures: store.captures, selectedDate: today)
        let weekDocument = WeekExportDocument.make(captures: store.captures, weekEndingDate: state.weekEndingDay)
        guard export.copy(dayDocument), exportedText.contains("Launch-plan.pdf") else {
            throw Failure(message: "Copy Day must include same fixture")
        }
        try await popover(WeeklyExportPopover(state: state, controller: export, reportFailure: { _ in }),
                           "24-export-copied", width: 262, height: 316)
        export.dismiss()
        try dayDocument.utf8Data.write(to: output.appendingPathComponent(dayDocument.filename))
        try weekDocument.utf8Data.write(to: output.appendingPathComponent(weekDocument.filename))
        state.openDaily()
        try await board(state, "25-daily-final")
        let reloaded = try CaptureStore(root: root)
        guard let saved = reloaded.captures.first(where: { $0.id == pdf.id }), saved.isTask,
              saved.isCompleted, saved.comment == pdf.comment,
              saved.indexedText.lowercased().contains("launch checklist") else {
            throw Failure(message: "Reopened isolated archive lost walkthrough actions")
        }
        try await robots()
        let fileIcon = NSWorkspace.shared.icon(for: .pdf)
        let iconBitmap = try makeBitmap(width: 64, height: 64)
        if let context = NSGraphicsContext(bitmapImageRep: iconBitmap) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            fileIcon.draw(in: CGRect(x: 0, y: 0, width: 64, height: 64))
            NSGraphicsContext.restoreGraphicsState()
        }
        try save(iconBitmap, name: "fixture-file-icon", width: 64, height: 64, route: "macOS-PDF-icon")
        let manifest: [String: Any] = [
            "description": "Exact production DaBin views with one coherent fictional PDF arc.",
            "fixture": "Launch-plan.pdf", "query": "launch checklist",
            "productionSources": ["BoardView.swift", "CaptureStore.swift", "ContentIndexService.swift", "AppState.swift", "DayExportUI.swift", "RobotCharacterView.swift"],
            "privacy": "Isolated temporary store and UserDefaults suite; fictional fixtures only; never read general clipboard, request permissions, deliver notifications, or contact network. Temporary archive deleted on exit.",
            "actionsVerified": ["production PDF import", "real PDFKit text extraction", "indexed-only query match", "3 active weekly days", "AppState.saveDetail persists comment", "AppState.convertToTask preserves PDF", "AppState.toggleTaskCompletion persists completion", "archive reopen retains all edits", "Auto Capture defaults off", "Copy Day output contains fixture"],
            "captureMethod": "Exact production views in an isolated offscreen NSWindow subclass with an explicit 2× backingScaleFactor, captured by NSView.cacheDisplay into 2× bitmaps. This preserves crisp native typography on a physical 1× display. Cursor transitions are editorial reenactments between actual production states.",
            "pdfTileCapture": "PDFKit tiled layers are omitted by cacheDisplay. For visible PDFViews only, this renderer rasterizes the actual fixture PDF page at the live PDFView measured page bounds. No UI is redrawn.",
            "restoredPDFTiles": restoredPDFTiles,
            "controls": ["daily": ["files": [404, 90], "weekly": [244, 22], "search": [320, 56], "settings": [500, 56], "export": [380, 56]],
                         "detail": ["convertToTask": [77, 127], "save": [693, 535]],
                         "search": ["field": [315, 71], "match": [200, 379]],
                         "dailyTask": ["completion": [704, 298]],
                         "comment": ["editor": [260, 414], "save": [693, 535]],
                         "weekly": ["daily": [228, 22], "search": [330, 56], "export": [390, 56]],
                         "settings": ["autoCaptureOff": [128, 240], "localArchiveText": [350, 240]]],
            "screenshots": records
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("walkthrough-renders.json"), options: .atomic)
        print("PASS: \(records.count) production UI/robot assets. PDF extraction, search, comment save, task conversion/completion, export and archive reload verified.")
    }

    private func board(_ state: AppState, _ name: String, width: CGFloat = 760,
                       scroll: CGFloat = 0, scrollY: CGFloat? = nil) async throws {
        try await snapshot(BoardView(state: state, theme: theme), name: name,
            width: width, height: 560, route: String(describing: state.route), scroll: scroll, scrollY: scrollY)
    }

    private func popover<Content: View>(_ content: Content, _ name: String,
                                        width: CGFloat, height: CGFloat) async throws {
        try await snapshot(content.environment(\.daBinAccent, theme.accent).preferredColorScheme(.dark)
            .background(Palette.background).clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.line)),
            name: name, width: width, height: height, route: "production-popover")
    }

    private func snapshot<Content: View>(_ content: Content, name: String, width: CGFloat, height: CGFloat,
                                         route: String, scroll: CGFloat = 0, scrollY: CGFloat? = nil) async throws {
        let renderWidth = width, renderHeight = height
        let hosting = NSHostingView(rootView: content.environment(\.displayScale, 2)
            .frame(width: width, height: height))
        hosting.frame = CGRect(x: 0, y: 0, width: renderWidth, height: renderHeight)
        hosting.wantsLayer = true
        let window = makeWindow(hosting, width: renderWidth, height: renderHeight)
        defer { close(window) }
        try await Task.sleep(for: .milliseconds(route == "weekly" ? 700 : 260))
        hosting.layoutSubtreeIfNeeded()
        if (scroll > 0 || scrollY != nil), let scrollView = firstScroll(in: hosting), let doc = scrollView.documentView {
            for _ in 0..<3 {
                let maxY = max(0, doc.bounds.height - scrollView.contentView.bounds.height)
                let y = min(maxY, scrollY ?? (scroll * maxY))
                scrollView.contentView.scroll(to: CGPoint(x: 0, y: y))
                scrollView.reflectScrolledClipView(scrollView.contentView)
                try await Task.sleep(for: .milliseconds(80))
                hosting.layoutSubtreeIfNeeded()
            }
        }
        hosting.displayIfNeeded()
        let bitmap = try makeBitmap(width: width, height: height)
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        // Capture PDFKit's real page at its measured production location. The UI
        // itself remains the untouched cacheDisplay image.
        if let context = NSGraphicsContext(bitmapImageRep: bitmap) {
            for pdf in pdfViews(in: hosting) {
                guard let page = pdf.currentPage else { continue }
                let rect = hosting.convert(pdf.convert(page.bounds(for: pdf.displayBox), from: page), from: pdf)
                let visible = hosting.convert(pdf.visibleRect, from: pdf).intersection(hosting.bounds)
                guard !rect.isEmpty, !visible.isEmpty else { continue }
                let converted = CGRect(x: rect.minX, y: renderHeight - rect.maxY, width: rect.width, height: rect.height)
                let clip = CGRect(x: visible.minX, y: renderHeight - visible.maxY, width: visible.width, height: visible.height)
                let cg = context.cgContext
                cg.saveGState(); cg.clip(to: clip)
                cg.setFillColor(NSColor.white.cgColor); cg.fill(converted)
                cg.translateBy(x: converted.minX, y: converted.minY)
                let pageRect = page.bounds(for: pdf.displayBox)
                cg.scaleBy(x: converted.width / pageRect.width, y: converted.height / pageRect.height)
                page.draw(with: pdf.displayBox, to: cg)
                cg.restoreGState()
                restoredPDFTiles += 1
            }
        }
        try save(bitmap, name: name, width: width, height: height, route: route)
    }

    private func makeWindow(_ view: NSView, width: CGFloat, height: CGFloat) -> NSWindow {
        let window = WalkthroughWindow(contentRect: CGRect(x: -10000, y: -10000, width: width, height: height),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.isOpaque = false; window.backgroundColor = .clear
        window.contentView = view; retainedWindows.append(window); window.orderFront(nil)
        return window
    }

    private func close(_ window: NSWindow) {
        window.orderOut(nil); window.contentView = nil; window.close()
        retainedWindows.removeAll { $0 === window }
    }

    private func makeBitmap(width: CGFloat, height: CGFloat) throws -> NSBitmapImageRep {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * 2),
            pixelsHigh: Int(height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw Failure(message: "Bitmap allocation failed")
        }
        bitmap.size = CGSize(width: width, height: height)
        return bitmap
    }

    private func save(_ bitmap: NSBitmapImageRep, name: String, width: CGFloat, height: CGFloat, route: String) throws {
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw Failure(message: "PNG encoding failed") }
        let filename = "\(name)@2x.png"
        try data.write(to: output.appendingPathComponent(filename), options: .atomic)
        records.append(["file": filename, "route": route, "logicalWidth": Int(width), "logicalHeight": Int(height),
                        "pixelWidth": bitmap.pixelsWide, "pixelHeight": bitmap.pixelsHigh, "pixelScale": 2])
    }

    private func firstScroll(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.compactMap { firstScroll(in: $0) }.first
    }

    private func pdfViews(in view: NSView) -> [PDFView] {
        if let pdf = view as? PDFView { return [pdf] }
        return view.subviews.flatMap { pdfViews(in: $0) }
    }

    private func fixturePDF(text: String) throws -> Data {
        let data = NSMutableData()
        var page = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &page, nil) else {
            throw Failure(message: "PDF context failed")
        }
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(red: 0.98, green: 0.97, blue: 1, alpha: 1)); context.fill(page)
        context.setFillColor(CGColor(red: 0.49, green: 0.32, blue: 0.66, alpha: 1))
        context.fill(CGRect(x: 45, y: 665, width: 522, height: 7))
        let lines = text.components(separatedBy: .newlines)
        for (i, line) in lines.enumerated() {
            let font = CTFontCreateWithName("Helvetica" as CFString, i == 0 ? 30 : 18, nil)
            let str = NSAttributedString(string: line, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.12, alpha: 1)])
            context.textPosition = CGPoint(x: 48, y: i == 0 ? 714 : 650 - CGFloat(i) * 34)
            CTLineDraw(CTLineCreateWithAttributedString(str), context)
        }
        context.endPDFPage(); context.closePDF()
        guard PDFDocument(data: data as Data)?.string?.lowercased().contains("launch checklist") == true else {
            throw Failure(message: "Generated PDF contains no searchable fixture text")
        }
        return data as Data
    }

    private func robots() async throws {
        let width: CGFloat = 128, height: CGFloat = 156
        let robot = RobotCharacterView(frame: CGRect(x: 0, y: 0, width: width, height: height), reduceMotion: { true })
        let window = makeWindow(robot, width: width, height: height)
        defer { robot.stopMotion(); close(window) }
        let states: [(String, RobotMotionEvent?)] = [("robot-idle", nil),
            ("robot-curious", .hover(true, pointer: CGPoint(x: 0.6, y: -0.3))),
            ("robot-hungry", .acceptedDrag(true)), ("robot-digesting", .saving(true)),
            ("robot-success", .result(.success))]
        for (name, event) in states {
            robot.send(.hide); robot.send(.reveal(.top))
            if let event { robot.send(event) }
            try await Task.sleep(for: .milliseconds(100))
            robot.layoutSubtreeIfNeeded(); robot.displayIfNeeded()
            let bitmap = try makeBitmap(width: width, height: height)
            robot.cacheDisplay(in: robot.bounds, to: bitmap)
            try save(bitmap, name: name, width: width, height: height, route: "production-robot")
        }
    }
}
