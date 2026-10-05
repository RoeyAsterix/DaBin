import AppKit
import ApplicationServices
import Combine
import Foundation
import SwiftUI

@MainActor private final class MessageFixtureClock {
    var instant = ContinuousClock().now
    func advance(_ duration: Duration) { instant = instant.advanced(by: duration) }
}

/// Cancellation deliberately does not resume these sleepers: a canceled task
/// may finish late, so receipt ownership must independently reject its result.
private actor MessageFixtureSleeper {
    private var continuations: [Int: CheckedContinuation<Void, Error>] = [:]
    private var durations: [Duration] = []
    func sleep(_ duration: Duration) async throws {
        let id = durations.count
        durations.append(duration)
        try await withCheckedThrowingContinuation { continuations[id] = $0 }
    }
    var count: Int { durations.count }
    func duration(_ id: Int) -> Duration { durations[id] }
    func resume(_ id: Int) { continuations.removeValue(forKey: id)?.resume() }
    func finish() {
        let pending = continuations.values
        continuations.removeAll()
        pending.forEach { $0.resume(throwing: CancellationError()) }
    }
}

@MainActor private final class MessageFixtureNotifications: ReminderNotificationClient {
    var permissionCalls = 0
    var writes = 0
    func authorization() async -> ReminderAuthorization { .undetermined }
    func requestAuthorization() async throws -> Bool { permissionCalls += 1; return false }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { writes += 1 }
    func removePending(_ identifiers: [String]) { writes += identifiers.count }
    func removeDelivered(_ identifiers: [String]) { writes += identifiers.count }
}

@MainActor private final class MessageFixtureWindow: NSWindow {
    override var backingScaleFactor: CGFloat { 2 }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor private struct MessageAXNode {
    let object: NSObject
    private func value(_ name: String) -> Any? {
        let selector = NSSelectorFromString(name)
        return object.responds(to: selector) ? object.perform(selector)?.takeUnretainedValue() : nil
    }
    private func attribute(_ name: String) -> Any? {
        let selector = NSSelectorFromString("accessibilityAttributeValue:")
        guard object.responds(to: selector),
              (value("accessibilityAttributeNames") as? [String])?.contains(name) == true else { return nil }
        return object.perform(selector, with: name as NSString)?.takeUnretainedValue()
    }
    var identifier: String? { (value("accessibilityIdentifier") as? String) ?? (attribute("AXIdentifier") as? String) }
    var text: String {
        [value("accessibilityLabel"), value("accessibilityTitle"), value("accessibilityValue"),
         attribute("AXTitle"), attribute("AXDescription"), attribute("AXValue")]
            .compactMap { $0 as? String }.first { !$0.isEmpty } ?? ""
    }
    func press() -> Bool {
        let selector = NSSelectorFromString("accessibilityPerformPress")
        guard object.responds(to: selector) else { return false }
        typealias Action = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(object.method(for: selector), to: Action.self)(object, selector)
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
}

/// Exact monotonic deadlines plus actual production views in own-process,
/// offscreen, non-key windows. Fictional local captures only; no real clipboard,
/// notification permission, network, external application or desktop capture.
@main @MainActor private final class NotificationPresentationTests: NSObject, NSApplicationDelegate {
    private static var checks = 0
    private var result: Int32 = 0

    static func main() {
        let app = NSApplication.shared
        let delegate = NotificationPresentationTests()
        app.setActivationPolicy(.accessory); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        exit(delegate.result)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await Self.run() }
            catch { result = 1; fputs("Notification presentation QA failed: \(error)\n", stderr) }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }
    private static func failure(_ text: String) -> NSError {
        NSError(domain: "NotificationPresentationTests", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard condition() else { throw failure(message) }
    }
    private static func pump() async {
        for _ in 0..<8 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(2))
    }
    private static func wait(_ sleeper: MessageFixtureSleeper, count: Int) async throws {
        for _ in 0..<100 {
            if await sleeper.count == count { return }
            await pump()
        }
        throw failure("Gated expiry did not start: expected \(count), actual \(await sleeper.count)")
    }

    private static func deadlineChecks() async throws {
        let clock = MessageFixtureClock(), sleeper = MessageFixtureSleeper()
        let presenter = TransientMessagePresentation<String>(now: { clock.instant }, sleep: { try await sleeper.sleep($0) })
        var changes = 0
        let subscription = presenter.objectWillChange.sink { changes += 1 }
        try expect(TransientMessagePolicy.maximumDisplayDuration == .seconds(2), "Every transient receipt has the exact two-second maximum")
        try expect(presenter.message == nil && presenter.visibleMessage == nil && presenter.revision == 0, "Presenter begins empty")
        presenter.present("First fictional receipt")
        try await wait(sleeper, count: 1)
        let duration = await sleeper.duration(0)
        try expect(duration == .seconds(2), "Expiry sleeper receives the exact maximum duration")
        try expect(presenter.visibleMessage == "First fictional receipt", "A fresh receipt is visible")
        clock.advance(.nanoseconds(1_999_999_999))
        try expect(presenter.visibleMessage != nil, "Receipt is still visible one nanosecond before deadline")
        clock.advance(.nanoseconds(1))
        try expect(presenter.visibleMessage == nil && presenter.message == "First fictional receipt", "Exact deadline hides the UI before a delayed sleeper callback")
        clock.advance(.seconds(20))
        try expect(presenter.visibleMessage == nil, "A late wake cannot resurrect an expired receipt")
        await sleeper.resume(0); await pump()
        try expect(presenter.message == nil && changes >= 3, "Late expiry cleans receipt state and publishes UI changes")
        withExtendedLifetime(subscription) { }
        presenter.shutdown(); await sleeper.finish()
    }

    private static func replacementChecks() async throws {
        let clock = MessageFixtureClock(), sleeper = MessageFixtureSleeper()
        let presenter = TransientMessagePresentation<String>(now: { clock.instant }, sleep: { try await sleeper.sleep($0) })
        presenter.present("Same receipt"); try await wait(sleeper, count: 1)
        let firstRevision = presenter.revision
        clock.advance(.seconds(1))
        presenter.present("Same receipt"); try await wait(sleeper, count: 2)
        try expect(presenter.revision > firstRevision && presenter.visibleMessage == "Same receipt", "Identical assignment creates a new receipt and restarts its timer")
        clock.advance(.seconds(1)); await sleeper.resume(0); await pump()
        try expect(presenter.visibleMessage == "Same receipt", "Old identical receipt cannot dismiss its restarted successor")
        clock.advance(.nanoseconds(999_999_999))
        try expect(presenter.visibleMessage == "Same receipt", "Restarted receipt owns its complete new two seconds")
        clock.advance(.nanoseconds(1))
        try expect(presenter.visibleMessage == nil, "Restarted receipt also ends at its exact deadline")
        await sleeper.resume(1); await pump()
        presenter.present("A"); try await wait(sleeper, count: 3)
        presenter.present("B"); try await wait(sleeper, count: 4)
        presenter.present("C"); try await wait(sleeper, count: 5)
        await sleeper.resume(3); await sleeper.resume(2); await pump()
        try expect(presenter.visibleMessage == "C" && presenter.message == "C", "Out-of-order canceled callbacks never hide rapid replacement")
        presenter.dismiss()
        try expect(presenter.visibleMessage == nil && presenter.message == nil, "Explicit dismissal clears presentation immediately")
        await sleeper.resume(4); await pump()
        try expect(presenter.visibleMessage == nil, "Dismissed receipt cannot return when its canceled sleeper finishes")
        presenter.present("Last receipt"); try await wait(sleeper, count: 6)
        presenter.present(nil)
        try expect(presenter.message == nil && presenter.visibleMessage == nil, "A nil source update clears current presentation")
        await sleeper.resume(5); await pump()
        presenter.present("Shutdown receipt"); try await wait(sleeper, count: 7)
        presenter.shutdown()
        let stoppedRevision = presenter.revision
        presenter.present("Must never appear"); presenter.shutdown()
        await sleeper.resume(6); await pump()
        try expect(presenter.message == nil && presenter.visibleMessage == nil && presenter.revision == stoppedRevision, "Shutdown is idempotent, cancels late work and rejects future presentation")
        await sleeper.finish()
    }

    private static func emptyDismissalChecks() async throws {
        let clock = MessageFixtureClock(), sleeper = MessageFixtureSleeper()
        let presenter = TransientMessagePresentation<String>(now: { clock.instant }, sleep: { try await sleeper.sleep($0) })
        var changes = 0
        let subscription = presenter.objectWillChange.sink { changes += 1 }
        for _ in 0..<500 { presenter.dismiss(); presenter.present(nil) }
        try expect(changes == 0 && presenter.revision == 0,
                   "Empty lifecycle cleanup publishes no layout invalidations and creates no receipt revisions")
        let idleSleepers = await sleeper.count
        try expect(idleSleepers == 0, "Empty cleanup schedules no expiry work")

        presenter.present("Visible row feedback"); try await wait(sleeper, count: 1)
        let shownChanges = changes, shownRevision = presenter.revision
        presenter.dismiss()
        try expect(presenter.message == nil && presenter.visibleMessage == nil
                   && presenter.revision > shownRevision && changes > shownChanges,
                   "Dismissing a real receipt still publishes removal and invalidates its expiry")
        let dismissedChanges = changes, dismissedRevision = presenter.revision
        for _ in 0..<500 { presenter.dismiss(); presenter.present(nil) }
        try expect(changes == dismissedChanges && presenter.revision == dismissedRevision,
                   "Repeated disappearance after dismissal remains a publication-free no-op")
        await sleeper.resume(0); await pump()
        try expect(changes == dismissedChanges && presenter.message == nil,
                   "Canceled receipt completion cannot publish after its dismissal")

        presenter.present("Later row feedback"); try await wait(sleeper, count: 2)
        try expect(presenter.visibleMessage == "Later row feedback" && presenter.revision > dismissedRevision,
                   "No-op cleanup does not stop a later receipt from appearing")
        clock.advance(.seconds(2)); await sleeper.resume(1); await pump()
        let expiredChanges = changes, expiredRevision = presenter.revision
        presenter.dismiss(); presenter.present(nil); presenter.shutdown()
        try expect(presenter.message == nil && changes == expiredChanges && presenter.revision == expiredRevision,
                   "Cleanup and shutdown after ordinary expiry publish no redundant empty state")
        withExtendedLifetime(subscription) { }
        await sleeper.finish()
    }

    private static func nodes(_ view: NSView) -> [MessageAXNode] {
        var result: [MessageAXNode] = [], seen = Set<ObjectIdentifier>()
        func visit(_ candidate: Any, depth: Int) {
            guard depth < 50, let object = candidate as? NSObject,
                  seen.insert(ObjectIdentifier(object)).inserted else { return }
            let node = MessageAXNode(object: object); result.append(node)
            node.children.forEach { visit($0, depth: depth + 1) }
        }
        visit(view, depth: 0)
        NSAccessibility.unignoredChildren(from: [view]).forEach { visit($0, depth: 0) }
        return result
    }
    private static func settle(_ views: [NSView]) async {
        for _ in 0..<4 {
            views.forEach { $0.layoutSubtreeIfNeeded() }
            try? await Task.sleep(for: .milliseconds(35))
        }
    }
    private static func mount<V: View>(_ root: V, size: CGSize, dark: Bool) -> (NSView, NSWindow) {
        let hosting = NSHostingView(rootView: root.frame(width: size.width, height: size.height, alignment: .topLeading)
            .environment(\.displayScale, 2).environment(\.daBinTooltipsEnabled, false)
            .preferredColorScheme(dark ? .dark : .light).transaction { $0.animation = nil; $0.disablesAnimations = true })
        hosting.frame = NSRect(origin: .zero, size: size); hosting.wantsLayer = true
        let window = MessageFixtureWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        hosting.appearance = window.appearance; window.contentView = hosting; window.orderFront(nil)
        return (hosting, window)
    }
    private static func captureData(_ captures: [Capture]) throws -> [UUID: Data] {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try Dictionary(uniqueKeysWithValues: captures.map { ($0.id, try encoder.encode(CaptureSnapshot($0))) })
    }
    private static func save(_ view: NSView, name: String, output: URL) throws {
        let rect = view.bounds.integral
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(rect.width * 2), pixelsHigh: Int(rect.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0) else { throw failure("Native notification bitmap allocation failed") }
        bitmap.size = rect.size; view.cacheDisplay(in: rect, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw failure("Notification PNG encoding failed") }
        try png.write(to: output.appendingPathComponent(name + "@2x.png"), options: .atomic)
    }

    private static func nativeChecks(output: URL) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinMessageQA-\(UUID().uuidString)")
        let suite = "DaBinMessageQA.\(UUID().uuidString)", defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: PreviewService.linkPreviewPreference)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root)
        let capture = try store.capture(text: "Fictional notification fixture. All original content stays local.",
            at: Date(timeIntervalSince1970: 1_700_000_000), timeZone: TimeZone(secondsFromGMT: 0)!).first!
        let original = Data((capture.originalText ?? "").utf8)
        let previews = PreviewService(store: store, defaults: defaults), client = MessageFixtureNotifications()
        let reminders = ReminderService(store: store, client: client)
        let auto = AutoCaptureService(settings: AutoCaptureSettings(defaults: defaults), input: InputService(store: store),
            pasteboardProvider: { fatalError("Notification QA must not read the real clipboard") }, sourceApplicationProvider: { nil })
        let state = AppState(store: store, previews: previews, reminders: reminders, autoCapture: auto,
            captureClipboard: CaptureClipboardService(writer: { _ in fatalError("Notification QA must not write the real clipboard") }))
        defer { state.shutdownNotificationPresentation(); state.focusSessions.shutdown(); auto.shutdown(); previews.shutdown() }
        state.openCapture(capture.id)
        guard let draft = state.selectedDraft else { throw failure("Detail fixture has no draft") }
        state.route = .daily; state.selectedDay = Date(timeIntervalSince1970: 1_600_000_000); state.isBoardVisible = true
        let theme = ThemeSettings(defaults: defaults, systemDarkMode: false); theme.setDarkMode(false); theme.setShowTooltips(false)
        let export = DayExportActionController(pasteboardWriter: { _ in false }, destinationChooser: { _, _ in .cancelled }, fileWriter: { _, _ in })
        let board = mount(BoardView(state: state, theme: theme, dayExportController: export), size: CGSize(width: 380, height: 560), dark: false)
        state.detailFocus = "reminder"
        let detail = mount(DetailScreen(state: state, capture: capture, draft: draft), size: CGSize(width: 650, height: 900), dark: true)
        let settings = mount(SettingsScreen(state: state, theme: theme, quitApplication: {}), size: CGSize(width: 600, height: 2_400), dark: false)
        let fixtures = [board, detail, settings], views = fixtures.map(\.0)
        defer { for (_, window) in fixtures { window.orderOut(nil); window.contentView = nil; window.close() } }
        await settle(views)
        let activation = await Task.detached {
            let process = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            AXUIElementSetMessagingTimeout(process, 3)
            var windows: CFTypeRef?
            return AXUIElementCopyAttributeValue(process, kAXWindowsAttribute as CFString, &windows)
        }.value
        try expect(activation == .success && fixtures.allSatisfy { $0.1.frame.maxX < 0 && !$0.1.isKeyWindow }, "Native message fixtures initialize only own offscreen non-key windows")
        await settle(views)
        let reminderNodes = nodes(detail.0)
        try expect(["reminder-preset-15", "reminder-preset-60", "reminder-preset-tomorrow"].allSatisfy { id in
            reminderNodes.contains { $0.identifier == id }
        }, "Actual Detail exposes reminder presets before enabling a reminder")
        try expect(!draft.reminderEnabled && !draft.reminderChanged
            && !reminderNodes.contains { $0.identifier == "capture-save-reminder" },
                   "An unchanged reminder-off pane omits its inactive Apply action")
        let baseline = try captureData(store.captures), baselineHeight = CornerGeometry.dailyPanelHeight(for: state)
        try expect(baselineHeight == 380, "An empty selected day has no reserved banner height")
        let status = AppStatusMessage(text: "Fictional capture saved successfully.", severity: .success)
        let reminderText = "Fictional reminder feedback. No system notification was scheduled."
        let started = ContinuousClock().now
        state.status = status; reminders.status = reminderText; draft.didSave()
        let cleanup = await state.clipboardRetention.clearUnfiledHistory(confirmedIDs: [])
        try expect(cleanup.movedCount == 0 && state.clipboardRetention.visibleResultMessage == cleanup.message,
                   "No-op isolated cleanup displays success without moving any capture")
        var mayCopy = true
        let replacementExport = DayExportActionController(pasteboardWriter: { _ in mayCopy },
            destinationChooser: { _, _ in .cancelled }, fileWriter: { _, _ in })
        let document = DayExportDocument.make(captures: [capture], selectedDate: capture.capturedAt,
            now: capture.capturedAt.addingTimeInterval(3_600), calendarTimeZone: TimeZone(secondsFromGMT: 0)!)
        replacementExport.present()
        try expect(replacementExport.copy(document), "Isolated export starts with a successful receipt")
        try await Task.sleep(for: .milliseconds(100))
        mayCopy = false
        try expect(!replacementExport.copy(document) && replacementExport.isPresented
            && replacementExport.visibleFeedback == .failed("Couldn’t copy this day."),
            "A new export failure replaces success while preserving retry actions")
        defer { replacementExport.dismiss() }
        await settle(views)
        try expect(nodes(board.0).contains { $0.text == status.text }, "Actual Board displays the transient success receipt")
        try expect(nodes(detail.0).contains { $0.text == "Changes saved." }, "Actual Detail displays save success")
        try expect(nodes(detail.0).contains { $0.text == reminderText }, "Actual Detail displays reminder feedback")
        try expect(nodes(settings.0).contains { $0.text == reminderText }, "Actual Settings displays reminder feedback")
        try expect(CornerGeometry.dailyPanelHeight(for: state) == baselineHeight + 45, "Visible receipt temporarily reserves its banner height")
        try save(board.0, name: "board-success-visible", output: output)
        try await Task.sleep(until: started.advanced(by: .milliseconds(1_350)), clock: .continuous)
        try expect(replacementExport.isPresented && replacementExport.visibleFeedback == .failed("Couldn’t copy this day."),
                   "New export failure remains actionable beyond the older success dismissal deadline")
        try await Task.sleep(until: started.advanced(by: .milliseconds(2_250)), clock: .continuous)
        await settle(views)
        try expect(!nodes(board.0).contains { $0.text == status.text || $0.identifier == "app-notification-banner" }, "Board success leaves both pixels and accessibility after two seconds")
        try expect(!nodes(detail.0).contains { $0.text == "Changes saved." || $0.text == reminderText }, "Detail save and reminder success leave accessibility after two seconds")
        try expect(!nodes(settings.0).contains { $0.text == reminderText }, "Settings reminder feedback leaves accessibility after two seconds")
        try expect(state.status == status && reminders.status == reminderText && draft.message == "Changes saved.", "Expiry leaves underlying diagnostic values intact")
        try expect(state.notificationMessage == nil && reminders.visibleStatus == nil && draft.visibleMessage == nil, "All three owner presentations are expired, independent of raw values")
        try expect(CornerGeometry.dailyPanelHeight(for: state) == baselineHeight, "Expired banner stops reserving height despite retained raw diagnostics")
        try expect(state.clipboardRetention.visibleResultMessage == nil && state.clipboardRetention.lastResult?.message == cleanup.message,
                   "Cleanup success expires without erasing its raw result")
        try expect(replacementExport.isPresented && replacementExport.visibleFeedback == nil
            && replacementExport.feedback == .failed("Couldn’t copy this day."),
            "Old export success cannot close a newer failure; feedback expires but retry remains")
        try save(board.0, name: "board-success-expired", output: output)

        let storeError = "Fictional storage diagnostic remains available."
        let detailError = "Fictional unsaved draft error must remain actionable."
        export.present()
        try expect(!export.copy(document), "Actual Board controller produces a fictional copy failure without real clipboard access")
        await settle(views)
        let copyFailure = "Couldn’t copy this day."
        try expect(nodes(board.0).contains { $0.text == copyFailure } && state.notificationMessage?.text == copyFailure,
                   "Actual Board receives export failure feedback")
        store.error = storeError; draft.hasError = true; draft.message = detailError
        await settle(views)
        try expect(state.notificationMessage?.text == storeError && nodes(board.0).contains { $0.text == storeError }, "New store error becomes a new visible board receipt")
        try await Task.sleep(for: .milliseconds(2_150)); await settle(views)
        try expect(state.notificationMessage == nil && !nodes(board.0).contains { $0.text == storeError }, "Store-error banner also expires after two seconds")
        try expect(store.error == storeError && draft.visibleMessage == detailError && nodes(detail.0).contains { $0.text == detailError }, "Underlying storage diagnosis and unsaved Detail error are not erased")
        try expect(CornerGeometry.dailyPanelHeight(for: state) == baselineHeight, "Retained store error does not leave phantom banner space")

        let previousFeedbackRevision = export.feedbackRevision
        try expect(!export.copy(document), "Retry repeats the same fictional export failure")
        await settle(views)
        try expect(export.feedbackRevision > previousFeedbackRevision && state.notificationMessage?.text == copyFailure
            && nodes(board.0).contains { $0.text == copyFailure },
            "Repeated identical export failure reappears on the actual Board as a fresh receipt")
        try await Task.sleep(for: .milliseconds(1_400))
        try expect(state.notificationMessage?.text == copyFailure && export.isPresented,
                   "Repeated copy failure owns a new interval and keeps its retry surface")
        try await Task.sleep(for: .milliseconds(750)); await settle(views)
        try expect(state.notificationMessage == nil && !nodes(board.0).contains { $0.text == copyFailure }
            && export.feedback == .failed(copyFailure) && export.isPresented,
            "Repeated failure expires again without deleting outcome or closing retry")
        export.dismiss()

        state.status = AppStatusMessage(text: "Old status source", severity: .success)
        store.error = "New storage source"
        state.status = nil
        try expect(state.notificationMessage?.text == "New storage source", "Clearing an older status source cannot dismiss a newer storage receipt")
        state.status = AppStatusMessage(text: "New status source", severity: .warning)
        store.error = nil
        try expect(state.notificationMessage?.text == "New status source", "Clearing an older storage source cannot dismiss a newer status receipt")
        let revision = state.notifications.revision
        let repeatedStatus = state.status
        state.status = repeatedStatus
        try expect(state.notifications.revision > revision && state.notificationMessage?.text == "New status source", "Repeated identical raw status starts a new presentation receipt")
        store.error = "Dismissal preserves this diagnostic"
        await settle(views)
        guard let dismiss = nodes(board.0).first(where: { $0.text == "Dismiss message" }) else { throw failure("Board exposes no native Dismiss message action") }
        try expect(dismiss.press(), "Actual Board dismissal activates through native accessibility")
        await settle(views)
        try expect(state.notificationMessage == nil && store.error == "Dismissal preserves this diagnostic"
            && state.status?.text == "New status source", "Manual dismissal only hides presentation, never diagnostic sources")
        let after = try captureData(store.captures)
        let originalAfter = Data((capture.originalText ?? "").utf8)
        try expect(after == baseline && originalAfter == original, "All transient presentation changes preserve full captures and original text bytes")
        try expect(client.permissionCalls == 0 && client.writes == 0, "Feedback tests never request permission or mutate system notifications")
        state.shutdownNotificationPresentation()
        state.status = AppStatusMessage(text: "After shutdown", severity: .success); reminders.status = "After shutdown"
        draft.hasError = false; draft.message = "After shutdown"
        try expect(state.notificationMessage == nil && reminders.visibleStatus == nil && draft.visibleMessage == nil, "Owner shutdown prevents late presentation without deleting raw data")
    }

    private static func run() async throws {
        try await deadlineChecks()
        try await replacementChecks()
        try await emptyDismissalChecks()
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("build/qa/notification-presentation/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try await nativeChecks(output: output)
        let report: [String: Any] = ["checks": checks, "maximumDisplaySeconds": 2,
            "nativeEvidence": ["board-success-visible@2x.png", "board-success-expired@2x.png"],
            "privacy": "Own offscreen non-key windows, fictional isolated store/preferences, no clipboard/network/system notification writes."]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("report.json"), options: .atomic)
        print("PASS: \(checks) notification presentation checks; exact monotonic expiry, identical restarts, stale cancellation, native Board/Detail/Settings, persistent diagnostics and unchanged captures. Evidence: \(output.path)")
    }
}
