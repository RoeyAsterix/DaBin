import AppKit
import Darwin
import Foundation
import SwiftUI

/// This timer runs independently of SwiftUI's main-thread transaction loop.
/// A stuck graph cannot defer its own failure timeout indefinitely.
private final class ExplorerResponsivenessWatchdog: @unchecked Sendable {
    private let lock = NSLock()
    private var lastBeat = DispatchTime.now().uptimeNanoseconds
    private var phase = "starting"
    private var active = true
    private let timer: DispatchSourceTimer

    init() {
        timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "DaBin.ExplorerQA.watchdog", qos: .userInitiated))
        timer.schedule(deadline: .now() + 1, repeating: .milliseconds(250))
        timer.setEventHandler { [weak self] in self?.check() }
        timer.resume()
    }

    func beat(_ phase: String) {
        lock.lock()
        self.phase = phase
        lastBeat = DispatchTime.now().uptimeNanoseconds
        lock.unlock()
    }

    func stop() {
        lock.lock(); active = false; lock.unlock()
        timer.cancel()
    }

    private func check() {
        lock.lock()
        let stalled = active && DispatchTime.now().uptimeNanoseconds - lastBeat > 8_000_000_000
        let stalledPhase = phase
        lock.unlock()
        if stalled {
            let message = "FAIL: Explorer main-thread heartbeat stopped for 8 seconds during \(stalledPhase).\n"
            FileHandle.standardError.write(Data(message.utf8))
            _exit(124)
        }
    }
}

@MainActor private final class ExplorerResponsivenessWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor private final class ExplorerResponsivenessNotifications: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .undetermined }
    func requestAuthorization() async throws -> Bool { false }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}

/// Actual production Explorer, not isolated rows. All saves and preview work
/// use a fresh fictional archive and preferences; there is no pasteboard access,
/// user archive access, remote preview, global event, or foreground activation.
@main @MainActor private final class AutoCaptureExplorerResponsivenessTests: NSObject, NSApplicationDelegate {
    private static var checks = 0
    private var result: Int32 = 0
    private let watchdog = ExplorerResponsivenessWatchdog()

    static func main() {
        let app = NSApplication.shared
        let delegate = AutoCaptureExplorerResponsivenessTests()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        exit(delegate.result)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await Self.run(watchdog: watchdog) }
            catch { result = 1; fputs("Explorer responsiveness QA failed: \(error)\n", stderr) }
            watchdog.stop()
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }

    private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        guard try condition() else {
            throw NSError(domain: "AutoCaptureExplorerResponsivenessTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private static func settle(_ view: NSView, phase: String, watchdog: ExplorerResponsivenessWatchdog) async throws {
        watchdog.beat(phase)
        print("PHASE: \(phase)"); fflush(stdout)
        let started = ContinuousClock.now
        for _ in 0..<4 {
            view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(35))
            watchdog.beat(phase)
        }
        try expect(ContinuousClock.now - started < .seconds(3), "Explorer settles without starving the run loop during \(phase)")
    }

    private static func scrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView, scroll.bounds.height > 80 { return scroll }
        return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
    }

    private static func tableView(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        return view.subviews.lazy.compactMap { tableView(in: $0) }.first
    }

    /// Inspect only existing native rows. Asking for every logical row's AX
    /// subtree or calling rowView(makeIfNecessary: true) would materialize the
    /// content this regression is supposed to prove stays viewport-bounded.
    private static func checkNativeRows(in view: NSView, captures: Int, phase: String) throws -> Int {
        guard let table = tableView(in: view) else {
            throw NSError(domain: "AutoCaptureExplorerResponsivenessTests", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Explorer must use the native reusable table during \(phase)"])
        }
        var available = 0
        var availableIndexes: [Int] = []
        table.enumerateAvailableRowViews { _, index in
            available += 1
            availableIndexes.append(index)
        }
        try expect(table.numberOfRows >= captures, "Native Explorer keeps all logical captures during \(phase)")
        try expect(available > 0 && available < max(24, captures / 2),
            "Native Explorer materializes fewer than half its rows during \(phase), not a growing full archive (\(available)/\(table.numberOfRows))")
        print("ROWS: \(phase); logical=\(table.numberOfRows), available=\(available), indices=\(availableIndexes.sorted())")
        return available
    }

    private static func checkRegroupSelection(in view: NSView, state: AppState, previousTable: NSTableView?) throws {
        guard let table = tableView(in: view), let selected = state.workspace.selectedCaptureID else {
            throw NSError(domain: "AutoCaptureExplorerResponsivenessTests", code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Regrouping must retain a native table and selected capture"])
        }
        try expect(table !== previousTable, "Deliberate regrouping replaces the complete native table")
        let items = ExplorerQuery.items(state.store.captures, workspace: state.workspace, project: state.libraryProject,
            filter: state.filter, pinnedOnly: state.libraryPinnedOnly)
        let rows: [UUID?] = ExplorerQuery.sections(items, grouping: state.workspace.explorerGrouping)
            .flatMap { [Optional<UUID>.none] + $0.captures.map { Optional($0.id) } }
        guard let index = rows.firstIndex(where: { $0 == selected }) else {
            throw NSError(domain: "AutoCaptureExplorerResponsivenessTests", code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Regrouped capture identity is missing"])
        }
        try expect(table.rowView(atRow: index, makeIfNecessary: false) != nil
            && table.rect(ofRow: index).intersects(table.visibleRect),
            "The new \(state.workspace.explorerGrouping.rawValue) table brings the remembered selected capture into view")
    }

    private static func fixturePNG() throws -> Data {
        let width = 320, height = 200
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.19, green: 0.68, blue: 0.82, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.91, green: 0.63, blue: 0.22, alpha: 1))
        context.fill(CGRect(x: 35, y: 30, width: 100, height: 130))
        return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
    }

    private static func run(watchdog: ExplorerResponsivenessWatchdog) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinExplorerResponsivenessQA-\(UUID().uuidString)")
        let suite = "DaBinExplorerResponsivenessQA.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: PreviewService.linkPreviewPreference)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root)
        let previews = PreviewService(store: store, defaults: defaults) { data, root, id in
            // Hold successful image output briefly so live placeholder rows
            // become real thumbnails after layout and selection have begun.
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return nil }
            return await PreviewService.writeThumbnail(data, root: root, id: id)
        }
        let auto = AutoCaptureService(settings: AutoCaptureSettings(defaults: defaults), input: InputService(store: store),
            pasteboardProvider: { fatalError("Explorer responsiveness QA must not read the clipboard") },
            sourceApplicationProvider: { nil })
        let state = AppState(store: store, previews: previews,
            reminders: ReminderService(store: store, client: ExplorerResponsivenessNotifications()), autoCapture: auto,
            captureClipboard: CaptureClipboardService(writer: { _ in fatalError("Explorer responsiveness QA must not write the clipboard") }))
        defer { previews.shutdown(); auto.shutdown(); state.focusSessions.shutdown() }
        state.isBoardVisible = true
        state.workspace.explorerGrouping = .type
        state.workspace.mode = .collection
        state.openLibrary()
        let png = try fixturePNG()
        let baseDate = Date(timeIntervalSince1970: 1_791_000_000)
        let zone = TimeZone(secondsFromGMT: 0)!
        var expectedIDs = Set<UUID>()

        func save(_ index: Int) async throws -> Capture {
            watchdog.beat("saving fictional automatic capture \(index)")
            let receipt = CaptureReceiptContext.automatic(index % 3 == 0 ? .automaticScreenshot : .automaticClipboard,
                sourceApplicationName: "Fictional source", sourceApplicationBundleIdentifier: "invalid.example.fixture")
            let at = baseDate.addingTimeInterval(Double(index))
            let capture: Capture
            if index % 3 == 0 {
                capture = try await store.importData(png, filename: "Fictional screenshot \(index).png", at: at,
                    timeZone: zone, receipt: receipt)
            } else {
                let text = index % 3 == 1 ? "A short fictional capture \(index)" : String(repeating: "Long fictional title and copied text \(index). ", count: 8)
                capture = try store.capture(text: text, at: at, timeZone: zone, receipt: receipt)[0]
            }
            if index % 4 != 0 {
                capture.setPasteHistory((0..<(index % 6 + 1)).map { destination in
                    CapturePasteEvent(applicationName: "Fictional destination \(destination)",
                        applicationBundleIdentifier: "invalid.example.destination\(destination)",
                        recordedAt: at.addingTimeInterval(Double(destination)), evidence: .manual)
                })
                try store.save(captures: [capture])
            }
            if index % 11 == 0 { try store.convertToTask(capture) }
            expectedIDs.insert(capture.id)
            if index >= 80 { state.didAutoCapture([capture]) }
            return capture
        }

        for index in 0..<80 { _ = try await save(index) }
        let middleImage = store.captures.filter { $0.kind == .image }[13]
        state.workspace.selectedCaptureID = middleImage.id
        let theme = ThemeSettings(defaults: defaults)
        theme.setDarkMode(true)
        theme.setShowTooltips(true)
        let tooltip = TimelineTooltipController()
        let hosting = DailyCaptureHostingView(state: state, theme: theme)
        hosting.rootView = BoardView(state: state, theme: theme, tooltipController: tooltip)
        hosting.frame = CGRect(x: 0, y: 0, width: 1_300, height: 760)
        let appFrame = RobotAppFrameView(contentView: hosting)
        let initialOuterSize = RobotAppFrameView.outerSize(forContentSize: hosting.frame.size)
        appFrame.frame = CGRect(origin: .zero, size: initialOuterSize)
        appFrame.autoresizingMask = [.width, .height]
        let window = ExplorerResponsivenessWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: initialOuterSize),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = appFrame
        appFrame.setVisible(true)
        defer { appFrame.cancelTransition(open: false); window.orderOut(nil); window.contentView = nil; window.close() }
        window.orderFront(nil)
        try await settle(appFrame, phase: "production native host selected middle image and initial scrollTo", watchdog: watchdog)
        try expect(hosting.sizingOptions.isEmpty && hosting.superview?.superview === appFrame,
                   "Production DailyCaptureHostingView disables intrinsic sizing inside the actual robot content container")
        try expect(hosting.frame.size == CGSize(width: 1_300, height: 760),
                   "Native wrapper insets preserve the intended BoardView dimensions")
        state.didAutoCapture(store.captures)
        try await settle(appFrame, phase: "80 initial captures begin live local previews", watchdog: watchdog)
        try expect(window.frame.maxX < 0 && !window.isKeyWindow && !window.isMainWindow,
                   "All UI remains offscreen, non-key, and non-main")
        try expect(scrollView(in: hosting)?.window === window, "Initial Explorer scroll view belongs to the fixture window")
        var maximumNativeRows = try checkNativeRows(in: hosting, captures: store.captures.count, phase: "initial 80 captures")
        var scrolledChecks = 0
        let widths: [CGFloat] = [699, 701, 260, 300, 1_300, 700, 701, 360, 760, 699, 701, 700, 320, 260, 1_300, 380]
        for (burst, width) in widths.enumerated() {
            watchdog.beat("resize and scroll burst \(burst)")
            let boardSize = CGSize(width: width, height: burst.isMultiple(of: 2) ? 660 : 520)
            window.setContentSize(RobotAppFrameView.outerSize(forContentSize: boardSize))
            try await settle(appFrame, phase: "width \(width) before burst \(burst)", watchdog: watchdog)
            try expect(hosting.frame.size == boardSize,
                       "Board width \(width) remains exact inside the live robot wrapper")
            // Grouping replaces the native table. Never keep scrolling a
            // detached table from an earlier grouping and count it as coverage.
            guard let scroll = scrollView(in: hosting) else {
                throw NSError(domain: "AutoCaptureExplorerResponsivenessTests", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Current Explorer scroll view missing in burst \(burst)"])
            }
            try expect(scroll.window === window, "Burst \(burst) scrolls the currently attached Explorer")
            if let document = scroll.documentView {
                let available = max(0, document.bounds.height - scroll.contentView.bounds.height)
                let fraction: CGFloat = burst % 3 == 0 ? 0 : burst % 3 == 1 ? 0.5 : 1
                scroll.contentView.scroll(to: CGPoint(x: 0, y: available * fraction))
                scroll.reflectScrolledClipView(scroll.contentView)
                if available > 0 { scrolledChecks += 1 }
            }
            try await settle(appFrame, phase: "scrolled before burst \(burst)", watchdog: watchdog)
            tooltip.presentImmediately(TimelineTooltipDescriptor(id: "board-settings-tooltip", text: "Settings",
                index: 0, itemCount: 1))
            let robotSource = window.convertToScreen(CGRect(x: appFrame.bounds.midX - 28.35,
                y: appFrame.bounds.maxY - 50, width: 56.7, height: 45.75))
            if burst == 7 {
                appFrame.animateClose(to: robotSource, island: false, reduceMotion: false)
                try await settle(appFrame, phase: "automatic saves during native close", watchdog: watchdog)
                try expect(appFrame.isTransitioning, "Capture insertions can overlap native closing")
            }
            for offset in 0..<3 { _ = try await save(80 + burst * 3 + offset) }
            try await settle(appFrame, phase: "three automatic saves burst \(burst)", watchdog: watchdog)
            if burst == 7 {
                appFrame.animateOpen(from: robotSource, island: false, reduceMotion: false)
                watchdog.beat("native close-to-open reversal settles")
                try await Task.sleep(for: .milliseconds(1_200))
                try await settle(appFrame, phase: "native close-to-open reversal completed", watchdog: watchdog)
                try expect(appFrame.isFrameVisible && !appFrame.isTransitioning,
                           "Interrupted close reopens the same live Explorer host")
            }
            // Preview completion mutates observed rows after insertion, a
            // sequence relevant to the sampled installed-app layout hang.
            // Earlier synthetic baselines passed; this is stress coverage,
            // not a claim that the original failure was reproduced here.
            let previousTable = tableView(in: hosting)
            if burst == 5 { state.workspace.explorerGrouping = .date }
            if burst == 10 { state.workspace.explorerGrouping = .type }
            try await settle(appFrame, phase: "preview completion burst \(burst)", watchdog: watchdog)
            if burst == 5 || burst == 10 {
                try checkRegroupSelection(in: hosting, state: state, previousTable: previousTable)
            }
            tooltip.dismiss()
            if burst == 11 {
                appFrame.animateClose(to: robotSource, island: false, reduceMotion: false)
                watchdog.beat("complete native close")
                try await Task.sleep(for: .milliseconds(1_050))
                try await settle(appFrame, phase: "native close completed", watchdog: watchdog)
                try expect(!appFrame.isFrameVisible && !appFrame.isTransitioning,
                           "Native close completes with the Explorer host retained")
                appFrame.animateOpen(from: robotSource, island: false, reduceMotion: false)
                watchdog.beat("complete native reopen")
                try await Task.sleep(for: .milliseconds(1_200))
                try await settle(appFrame, phase: "native reopen completed", watchdog: watchdog)
                try expect(appFrame.isFrameVisible && !appFrame.isTransitioning && appFrame.contentView === hosting,
                           "Full reopening retains the exact production host and selected Explorer")
            }
            try expect(Set(store.captures.map(\.id)) == expectedIDs, "Every durable automatic capture remains present after burst \(burst)")
            maximumNativeRows = max(maximumNativeRows,
                try checkNativeRows(in: hosting, captures: store.captures.count, phase: "burst \(burst)"))
        }
        try expect(scrolledChecks >= 8, "Most bursts exercise a genuinely scrollable Explorer")
        let pendingDeadline = ContinuousClock.now.advanced(by: .seconds(6))
        while store.captures.contains(where: { $0.previewState == "loading" }) && ContinuousClock.now < pendingDeadline {
            try await settle(appFrame, phase: "final local preview drain", watchdog: watchdog)
        }
        try expect(store.captures.filter { $0.kind == .image }.allSatisfy { $0.previewState == "ready" && $0.thumbnailRelativePath != nil },
                   "Every synthetic image completed the production local thumbnail pipeline")
        try expect(store.captures.count == 128 && store.captures.allSatisfy { $0.captureOrigin.isAutomatic },
                   "128 automatic receipts survived repeated live Explorer updates")
        try expect(state.workspace.selectedCaptureID == middleImage.id,
                   "Prepending captures preserves the selected middle image")
        watchdog.beat("reopening isolated archive")
        let reopened = try CaptureStore(root: root)
        try expect(Set(reopened.captures.map(\.id)) == expectedIDs, "All automatic captures remain durable after reopening")
        print("PASS: \(checks) Explorer responsiveness checks; production DailyCaptureHostingView and RobotAppFrameView, actual BoardView, 128 automatic captures, late local previews, 16 insertion bursts, selected-middle-image scrolling, mixed paste trails/tasks, exact narrow/wide breakpoint resizing, visible tooltip overlay, native close/reopen and interrupted reversal. Native table had at most \(maximumNativeRows) simultaneously available row views. Background 8-second run-loop watchdog remained healthy.")
    }
}
