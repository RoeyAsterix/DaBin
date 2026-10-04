import AppKit
import ApplicationServices
import Darwin
import Foundation
import SwiftUI

@MainActor private final class CaptionDragFixtureWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor private final class CaptionDragFixtureReminders: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .undetermined }
    func requestAuthorization() async throws -> Bool { false }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}

@MainActor private struct CaptionDragAX {
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
    var identifier: String? { (value("accessibilityIdentifier") as? String) ?? (attribute("AXIdentifier") as? String) }
    var label: String {
        [value("accessibilityLabel"), value("accessibilityTitle"), attribute("AXTitle"), attribute("AXDescription")]
            .compactMap { $0 as? String }.first { !$0.isEmpty } ?? ""
    }
    var text: String { (value("accessibilityValue") as? String) ?? (attribute("AXValue") as? String) ?? "" }
    var frame: NSRect {
        let selector = NSSelectorFromString("accessibilityFrame")
        guard object.responds(to: selector) else { return .zero }
        typealias Getter = @convention(c) (AnyObject, Selector) -> NSRect
        return unsafeBitCast(object.method(for: selector), to: Getter.self)(object, selector)
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

/// Mounts actual production cards and inspectors with fictional local records.
/// Reads their installed native-source closures without beginning a drag,
/// pressing copy, activating a window, or touching the general clipboard.
@main @MainActor private final class CaptionDragTests: NSObject, NSApplicationDelegate {
    private static var checks = 0
    private var result: Int32 = 0

    static func main() {
        let app = NSApplication.shared
        let delegate = CaptionDragTests()
        app.setActivationPolicy(.accessory); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        exit(delegate.result)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await Self.run() }
            catch { result = 1; fputs("Caption drag QA failed: \(error)\n", stderr) }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "CaptionDragTests", code: checks, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        guard try condition() else { throw failure(message) }
    }
    private static func settle(_ view: NSView) async throws {
        for _ in 0..<6 { view.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(35)) }
    }
    private static func nativeViews(in view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { nativeViews(in: $0) }
    }
    private static func sources(in view: NSView) -> [NativeContentDragView] {
        nativeViews(in: view).compactMap { $0 as? NativeContentDragView }.filter {
            !$0.isHiddenOrHasHiddenAncestor && !$0.visibleRect.isEmpty && $0.bounds.width > 0 && $0.bounds.height > 0
        }
    }
    private static func nodes(in view: NSView) -> [CaptionDragAX] {
        var result: [CaptionDragAX] = [], seen = Set<ObjectIdentifier>()
        func visit(_ candidate: Any, depth: Int) {
            guard depth < 40, let object = candidate as? NSObject,
                  seen.insert(ObjectIdentifier(object)).inserted else { return }
            let node = CaptionDragAX(object: object)
            result.append(node)
            node.children.forEach { visit($0, depth: depth + 1) }
        }
        visit(view, depth: 0)
        NSAccessibility.unignoredChildren(from: [view]).forEach { visit($0, depth: 0) }
        return result
    }
    private static func find(in view: NSView, description: String,
                             where predicate: (CaptionDragAX) -> Bool) async throws -> CaptionDragAX {
        for _ in 0..<6 {
            if let node = nodes(in: view).first(where: { predicate($0) && $0.frame.width > 0 && $0.frame.height > 0 }) {
                return node
            }
            try await settle(view)
        }
        throw failure("Missing rendered \(description)")
    }
    private static func find(_ identifier: String, in view: NSView) async throws -> CaptionDragAX {
        try await find(in: view, description: identifier, where: { $0.identifier == identifier })
    }
    private static func pressEvent(at node: CaptionDragAX, in window: NSWindow) -> NSEvent {
        let center = window.convertPoint(fromScreen: NSPoint(x: node.frame.midX, y: node.frame.midY))
        return NSEvent.mouseEvent(with: .leftMouseDown, location: center, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
    }
    private static func accepts(_ source: NativeContentDragView, node: CaptionDragAX, window: NSWindow) -> Bool {
        source.gestureRecognizer(NSPanGestureRecognizer(), shouldAttemptToRecognizeWith: pressEvent(at: node, in: window))
    }
    private static func source(label: String, anchor: CaptionDragAX? = nil,
                               in view: NSView, window: NSWindow) throws -> NativeContentDragView {
        let matches = sources(in: view).filter { $0.dragLabel == label }
        if let anchor {
            if let source = matches.first(where: { accepts($0, node: anchor, window: window) }) { return source }
        } else if let source = matches.first { return source }
        throw failure("No native drag surface for \(label) at its visible caption")
    }
    private static func outsideSources(_ node: CaptionDragAX, in view: NSView, window: NSWindow, reason: String) throws {
        try expect(!sources(in: view).contains { accepts($0, node: node, window: window) }, reason)
    }

    private static func withView<V: View>(_ rootView: V, size: CGSize = CGSize(width: 760, height: 1_400),
                                          body: (NSView, NSWindow) async throws -> Void) async throws {
        let host = NSHostingView(rootView: rootView.environment(\.daBinTooltipsEnabled, false)
            .transaction { $0.animation = nil; $0.disablesAnimations = true })
        host.frame = NSRect(origin: .zero, size: size); host.sizingOptions = []; host.autoresizingMask = [.width, .height]
        let window = CaptionDragFixtureWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: size.width, height: size.height),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        window.orderBack(nil)
        try await settle(host)
        // SwiftUI materializes its virtual AX children lazily. This request is
        // scoped to the fixture's own process and never reads another app.
        let activation = await Task.detached {
            let process = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            AXUIElementSetMessagingTimeout(process, 3)
            var windows: CFTypeRef?
            return AXUIElementCopyAttributeValue(process, kAXWindowsAttribute as CFString, &windows)
        }.value
        try expect(activation == .success, "Own-process accessibility exposes the fictional production surface")
        try await settle(host)
        try expect(window.frame.maxX < 0 && !window.isKeyWindow && !window.isMainWindow,
                   "Production fixture stays offscreen and never becomes a key or main window")
        try await body(host, window)
        try expect(sources(in: host).allSatisfy { $0.activeSession == nil }, "Inspecting captions never starts a native drag session")
    }

    private static func checkCapture(_ source: NativeContentDragView, expected: [Capture], store: CaptureStore) throws {
        let writers = try source.items()
        defer { source.onEnd() }
        let pasteboard = NSPasteboard(name: .init("DaBin.CaptionCaptureQA.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        try expect(writers.count == expected.count, "Actual caption closure emits one writer per whole capture")
        for (writer, capture) in zip(writers, expected) {
            let identity = writer.pasteboardPropertyList(forType: ExplorerTransfer.pasteboardType) as? Data
            try expect(identity.flatMap { try? ExplorerTransfer.decodeIDs($0) } == [capture.id],
                       "Caption retains each live capture's own identity and collection order")
        }
        try expect(pasteboard.writeObjects(writers), "Private native pasteboard accepts the production caption writers")
        let items = pasteboard.pasteboardItems ?? []
        try expect(items.count == expected.count, "Whole collections remain distinct native pasteboard items")
        for (item, capture) in zip(items, expected) {
            if let url = store.managedURL(for: capture) {
                try expect(item.string(forType: .fileURL) == url.absoluteString, "File caption transfers its saved managed original, not a filename or excerpt")
            } else if capture.kind == .link {
                try expect(item.string(forType: .URL) == capture.originalURL, "Link caption transfers its saved URL")
            } else {
                try expect(item.string(forType: .string) == (capture.originalText ?? capture.title), "Text/task caption transfers the full saved text")
            }
        }
    }

    private static func checkComment(_ source: NativeContentDragView, exactText: String) throws {
        let writers = try source.items()
        defer { source.onEnd() }
        let pasteboard = NSPasteboard(name: .init("DaBin.CaptionCommentQA.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        try expect(writers.count == 1 && writers.first is NSString, "Static comments emit one NSString rather than their capture's file writer")
        try expect(pasteboard.writeObjects(writers), "Private pasteboard accepts the actual comment writer")
        let items = pasteboard.pasteboardItems ?? []
        try expect(items.count == 1 && items[0].string(forType: .string) == exactText, "Comment drag preserves full whitespace and multilingual text despite visible line limits")
        try expect(items[0].string(forType: .fileURL) == nil && items[0].data(forType: ExplorerTransfer.pasteboardType) == nil,
                   "Comment drag carries neither the file original nor an internal whole-capture identity")
    }

    private static func run() async throws {
        let clipboardRevision = NSPasteboard.general.changeCount
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinCaptionDragQA-\(UUID().uuidString)")
        let suite = "DaBinCaptionDragQA.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: PreviewService.linkPreviewPreference)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root)
        // Keep all four automatic actions in one civil-clock hour even when
        // this suite is eventually run near an hour or midnight boundary.
        let at = Calendar.current.startOfDay(for: Date()).addingTimeInterval(12 * 3_600 + 1_200)
        let body = "Fictional detail body keeps its native text selection.\nSecond line: café שלום."
        let note = try store.capture(text: body, at: at)[0]
        note.title = "Fictional detail title"
        note.comment = "Fictional editable note comment"
        let task = try store.createTask(text: "Fictional full saved task body\nSecond task line", at: at)
        task.title = "Fictional task title"
        task.comment = "  Fictional weekly comment: café שלום.\n" + String(repeating: "Keep every word. ", count: 25) + "\n  "
        let file = try await store.importData(Data("Fictional owned file bytes\n".utf8), filename: "Fictional-caption.bin", at: at)
        file.comment = "  Fictional file comment: café שלום.\n" + String(repeating: "Comment is separate from its file. ", count: 20) + "\n  "
        file.indexedText = String(repeating: "Full fictional recognized text. ", count: 100)
        file.contentIndexState = "ready"
        // Terminal index metadata uses a completed extractor version, matching
        // the same schema validation applied to every saved capture.
        file.contentIndexVersion = ContentIndexService.currentVersion
        try store.save(captures: [note, task, file])
        let batchAt = at.addingTimeInterval(-300)
        let firstBatch = try await store.importData(Data("First batch original".utf8), filename: "First-batch.bin", at: batchAt)
        let secondBatch = try await store.importData(Data("Second batch original".utf8), filename: "Second-batch.bin", at: batchAt)
        let batch = [firstBatch, secondBatch]
        firstBatch.comment = "  Fictional batch comment: café שלום.\n" + String(repeating: "Keep the complete batch note. ", count: 20) + "\n  "
        try store.save(captures: [firstBatch])
        let batchGroup = CaptureCardGroup(id: .importedBatch(batchAt), captures: batch)
        var automatic: [Capture] = []
        for index in 0..<4 {
            let receipt = CaptureReceiptContext.automatic(.automaticClipboard, actionID: UUID(), sourceApplicationName: "Fictional Fixture")
            automatic += try store.capture(text: "Fictional complete automatic action \(index).\nIts full second line.",
                at: at.addingTimeInterval(Double(-600 - index * 30)), receipt: receipt)
        }
        let hourly = HourlyCaptureFeed.cards(from: automatic, filter: .all, today: at)
        guard let hour = hourly.compactMap({ if case .automaticHour(let group) = $0 { return group }; return nil }).first else {
            throw failure("Four fictional automatic actions must form an actual hourly collection")
        }
        let previews = PreviewService(store: store, defaults: defaults)
        let auto = AutoCaptureService(settings: AutoCaptureSettings(defaults: defaults), input: InputService(store: store),
            pasteboardProvider: { fatalError("Caption QA must never read the clipboard") }, sourceApplicationProvider: { nil })
        let state = AppState(store: store, previews: previews, reminders: ReminderService(store: store, client: CaptionDragFixtureReminders()),
            autoCapture: auto, captureClipboard: CaptureClipboardService(writer: { _ in fatalError("Caption QA must never write the clipboard") }),
            folderOpener: { _ in fatalError("Caption QA must never open Finder") })
        defer { previews.shutdown(); auto.shutdown(); state.focusSessions.shutdown(); store.cancelArchiveRepair() }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let snapshots = try Dictionary(uniqueKeysWithValues: store.captures.map { ($0.id, try encoder.encode(CaptureSnapshot($0))) })
        let fileBytes = try Data(contentsOf: store.managedURL(for: file)!)

        try await withView(DetailScreen(state: state, capture: note, draft: CaptureDraft(capture: note))) { host, window in
            let title = try await find("detail-title", in: host)
            try checkCapture(source(label: note.title, anchor: title, in: host, window: window), expected: [note], store: store)
            let preview = try await find("detail-preview-open-extended", in: host)
            try checkCapture(source(label: note.title, anchor: preview, in: host, window: window), expected: [note], store: store)
            let editor = try await find("capture-comment-composer", in: host)
            try outsideSources(editor, in: host, window: window, reason: "Detail comment editor retains editing gestures outside all native sources")
        }
        try await withView(DetailScreen(state: state, capture: task, draft: CaptureDraft(capture: task))) { host, window in
            let caption = try await find("detail-task-caption", in: host)
            try checkCapture(source(label: task.title, anchor: caption, in: host, window: window), expected: [task], store: store)
            let editor = try await find("detail-title", in: host)
            try outsideSources(editor, in: host, window: window, reason: "Editable task title stays outside the static task-caption drag source")
        }
        try await withView(ExplorerInspector(state: state, workspace: state.workspace, capture: task, height: 900)) { host, window in
            let title = try await find("explorer-inspector-title", in: host)
            try checkCapture(source(label: task.title, anchor: title, in: host, window: window), expected: [task], store: store)
            let text = try await find(in: host, description: "selectable inspector body", where: { $0.label == task.originalText || $0.text == task.originalText })
            try outsideSources(text, in: host, window: window, reason: "Inspector's selectable task body is independent of its draggable static title")
        }
        try await withView(CaptureRow(state: state, capture: task, featured: false)) { host, window in
            let title = try await find(in: host, description: "static task card title", where: {
                $0.label.hasPrefix("Open \(task.title), task, saved ")
            })
            try checkCapture(source(label: task.title, anchor: title, in: host, window: window), expected: [task], store: store)
            let completion = try await find("capture-task-status-\(task.id.uuidString)", in: host)
            try outsideSources(completion, in: host, window: window, reason: "Static task title drags leave the completion control independent")
        }
        try await withView(CaptureRow(state: state, capture: file, featured: false, indexedTextMatch: "A short recognized excerpt")) { host, window in
            let comment = try await find("capture-comment-\(file.id.uuidString)", in: host)
            try checkComment(source(label: "Comment for \(file.title)", anchor: comment, in: host, window: window), exactText: file.comment)
            let originalComment = file.comment
            file.comment = "  Updated fictional comment: café שלום.\nKeep this exact new text.  "
            try await settle(host)
            try checkComment(source(label: "Comment for \(file.title)", in: host, window: window), exactText: file.comment)
            file.comment = originalComment
            try await settle(host)
            let excerpt = try await find("capture-indexed-match-\(file.id.uuidString)", in: host)
            try checkCapture(source(label: file.title, anchor: excerpt, in: host, window: window), expected: [file], store: store)
            let copy = try await find(CaptureCopyButton.accessibilityIdentifier(for: [file]), in: host)
            try outsideSources(copy, in: host, window: window, reason: "CaptureRow copy remains an independent control outside comment and excerpt drag sources")
        }
        state.filter = .tasks; state.weekEndingDay = at
        try await withView(WeeklyScreen(state: state), size: CGSize(width: 760, height: 900)) { host, window in
            let comment = try await find("capture-comment-\(task.id.uuidString)", in: host)
            try checkComment(source(label: "Comment for \(task.title)", anchor: comment, in: host, window: window), exactText: task.comment)
            let copy = try await find(CaptureCopyButton.accessibilityIdentifier(for: [task]), in: host)
            try outsideSources(copy, in: host, window: window, reason: "Weekly copy button remains outside the static comment source")
        }
        state.filter = .all
        for compact in [false, true] {
            try await withView(GroupedCaptureCard(state: state, group: batchGroup, compact: compact), size: CGSize(width: compact ? 300 : 760, height: 1_000)) { host, window in
                for identifier in ["collection-batch-title", "collection-batch-caption"] {
                    let caption = try await find(identifier, in: host)
                    try checkCapture(source(label: "\(batch.count) captures", anchor: caption, in: host, window: window), expected: batch, store: store)
                }
                let comment = try await find("capture-comment-\(firstBatch.id.uuidString)", in: host)
                try checkComment(source(label: "Comment for \(firstBatch.title)", anchor: comment, in: host, window: window), exactText: firstBatch.comment)
                let copy = try await find(CaptureCopyButton.accessibilityIdentifier(for: batch), in: host)
                try outsideSources(copy, in: host, window: window, reason: "Expanded batch copy is outside both title and summary drag sources")
                let collapse = try await find(in: host, description: "batch collapse control", where: { $0.label == "Collapse batch items" })
                try outsideSources(collapse, in: host, window: window, reason: "Expanded batch collapse retains its independent control gesture")
            }
        }
        state.toggleHourlyGroup(hour.id)
        try await withView(HourlyCaptureCard(state: state, group: hour), size: CGSize(width: 760, height: 1_600)) { host, window in
            let count = try await find("collection-hour-count", in: host)
            let label = hour.displaysDate ? hour.summaryTitle : "\(prettyDay(hour.id.captureDay, includeWeekday: false)) · \(hour.summaryTitle)"
            try checkCapture(source(label: label, anchor: count, in: host, window: window), expected: hour.captures, store: store)
            let collapse = try await find(in: host, description: "hour collapse control", where: { $0.label == "Collapse actions" })
            try outsideSources(collapse, in: host, window: window, reason: "Expanded hour collapse remains outside whole-collection metadata drag source")
            let copy = try await find(CaptureCopyButton.accessibilityIdentifier(for: hour.actions[0].captures), in: host)
            try outsideSources(copy, in: host, window: window, reason: "Per-action copy remains independent of the expanded hour summary source")
        }
        for capture in store.captures {
            try expect(try encoder.encode(CaptureSnapshot(capture)) == snapshots[capture.id], "Resolving production caption writers never modifies source records")
        }
        try expect(try Data(contentsOf: store.managedURL(for: file)!) == fileBytes, "Caption payload inspection preserves the saved original bytes")
        try expect(NSPasteboard.general.changeCount == clipboardRevision, "Production caption inspection never replaces the general clipboard")
        print("PASS: \(checks) production caption drag checks; full capture/collection payloads, exact comment text, independent controls and editors.")
    }
}
