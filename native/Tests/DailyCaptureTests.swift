import AppKit
import Foundation

/// Private pasteboards and destination callbacks exercise the real import path
/// without touching the user's clipboard, synthesizing a cursor, or opening files.
@MainActor private final class DailyDropFixture: NSObject, NSDraggingInfo {
    var draggingDestinationWindow: NSWindow?
    var draggingSourceOperationMask: NSDragOperation = .copy
    var draggingLocation = NSPoint(x: 100, y: 150)
    var draggedImageLocation = NSPoint.zero
    nonisolated var draggedImage: NSImage? { nil }
    let draggingPasteboard: NSPasteboard
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 0
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    init(_ pasteboard: NSPasteboard) { draggingPasteboard = pasteboard }
    func slideDraggedImage(to screenPoint: NSPoint) { }
    nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() { }
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions,
        for view: NSView?, classes classArray: [AnyClass],
        searchOptions: [NSPasteboard.ReadingOptionKey: Any],
        using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) { }
}

@MainActor private final class DailyNotificationClient: ReminderNotificationClient {
    var permissionRequests = 0
    var additions = 0
    func authorization() async -> ReminderAuthorization { .undetermined }
    func requestAuthorization() async throws -> Bool { permissionRequests += 1; return false }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { additions += 1 }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}

/// Records responder fallback without consulting NSPasteboard.general.
@MainActor private final class DailyEditorProbe: NSTextView {
    var keyEvents = 0
    var equivalents = 0
    var pastes = 0
    override func keyDown(with event: NSEvent) { keyEvents += 1 }
    override func performKeyEquivalent(with event: NSEvent) -> Bool { equivalents += 1; return false }
    override func paste(_ sender: Any?) { pastes += 1 }
}

@main struct DailyCaptureTests {
    @MainActor private static var checks = 0
    @MainActor private static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        if try !value() { throw NSError(domain: "DaBinDailyCaptureTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    @MainActor private static func wait(_ message: String, until condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try expect(condition(), message)
    }
    @MainActor private static func board(_ items: [NSPasteboardItem]) throws -> NSPasteboard {
        let result = NSPasteboard(name: .init("DaBin.DailyCaptureTests.\(UUID().uuidString)"))
        result.clearContents()
        if !items.isEmpty { try expect(result.writeObjects(items), "Private Daily fixture writes") }
        return result
    }
    @MainActor private static func item(_ text: String, type: NSPasteboard.PasteboardType = .string) -> NSPasteboardItem {
        let result = NSPasteboardItem(); result.setString(text, forType: type); return result
    }
    private static func unwrap<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw NSError(domain: "DaBinDailyCaptureTests", code: 2,
            userInfo: [NSLocalizedDescriptionKey: message]) }
        return value
    }
    @MainActor private static func shortcut(_ flags: NSEvent.ModifierFlags, time: TimeInterval,
        window: NSWindow, repeatKey: Bool = false, characters: String = "v",
        ignoringModifiers: String = "v", type: NSEvent.EventType = .keyDown) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: time,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: ignoringModifiers, isARepeat: repeatKey, keyCode: 9)!
    }

    @MainActor static func main() async throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.finishLaunching()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinDailyCaptureTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root.appendingPathComponent("ArchiveFixture"))
        let input = InputService(store: store, stagingRoot: root.appendingPathComponent("Promises"))
        let notifications = DailyNotificationClient()
        let previews = PreviewService(store: store)
        let reminders = ReminderService(store: store, client: notifications)
        let state = AppState(store: store, previews: previews, reminders: reminders)
        defer { previews.cancelNetwork() }
        let hosting = DailyCaptureHostingView(state: state)
        hosting.sizingOptions = []
        let panel = DailyCapturePanel(contentRect: NSRect(x: 60, y: 60, width: 380, height: 500),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting
        defer { panel.orderOut(nil) }
        var dropCount = 0
        var dragStates: [Bool] = []
        var batches: [([Capture], [String])] = []
        hosting.onDrop = { dropCount += 1; input.receive($0) }
        hosting.onDragState = { dragStates.append($0) }
        input.onResult = { batches.append(($0, $1)) }
        try expect(hosting.registeredDraggedTypes.contains(.string) && hosting.registeredDraggedTypes.contains(.fileURL),
                   "Daily registers text and Finder file representations")
        try expect(hosting.registeredDraggedTypes.contains(.png) && hosting.registeredDraggedTypes.contains(.URL),
                   "Daily registers images and links")

        // Unlike the decorative robot, the board must preserve its controls.
        let button = NSButton(title: "Fixture control", target: nil, action: nil)
        button.frame = NSRect(x: 30, y: 30, width: 120, height: 30)
        hosting.addSubview(button, positioned: .above, relativeTo: nil)
        let hitPoint = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: hosting.superview)
        let hit = hosting.hitTest(hitPoint)
        try expect(hit === button || hit?.isDescendant(of: button) == true,
                   "Daily drop support preserves native control hit testing")
        try expect(hosting.hitTest(NSPoint(x: -1, y: -1)) == nil,
                   "Drop support does not create an invisible area outside the panel")
        button.removeFromSuperview()

        let text = "A fictional Daily note.\nKeep this second line."
        let textBoard = try board([item(text)]); defer { textBoard.releaseGlobally() }
        let textDrag = DailyDropFixture(textBoard); textDrag.draggingDestinationWindow = panel
        try expect(hosting.draggingEntered(textDrag) == .copy, "Daily accepts text as copy")
        try expect(dragStates.last == true, "Accepted Daily drag publishes targeting feedback")
        try expect(hosting.draggingUpdated(textDrag) == .copy, "Daily remains a destination while drag moves")
        try expect(dropCount == 0 && store.captures.isEmpty && !input.isBusy, "Hover never captures data")
        try expect(hosting.prepareForDragOperation(textDrag), "Daily text drop prepares")
        try expect(hosting.performDragOperation(textDrag), "Daily text drop dispatches")
        hosting.concludeDragOperation(textDrag)
        try expect(dragStates.last == false, "Successful Daily drop clears targeting feedback")
        try await wait("Daily text reaches local archive") { batches.count == 1 && !input.isBusy }
        let textCapture = try unwrap(batches[0].0.first, "Text capture exists")
        try expect(dropCount == 1 && batches[0].0.count == 1 && batches[0].1.isEmpty, "A Daily drop creates one successful capture")
        try expect(textCapture.kind == .text && textCapture.originalText == text, "Daily text preserves exact contents")
        try expect(textCapture.sourceFilePath == nil && textCapture.sourceURL == nil, "Daily text does not invent its source")
        let textArchive = try unwrap(store.archiveURL(for: textCapture), "Daily text archive exists")
        try expect(try String(contentsOf: textArchive.appendingPathComponent("Content.txt"), encoding: .utf8) == text,
                   "Daily text original is persisted under its dated folder")

        let source = root.appendingPathComponent("Fictional Daily document.pdf")
        let original = Data("%PDF-1.4\nDaBin fictional Daily drop\n%%EOF\n".utf8)
        try original.write(to: source)
        let modified = try source.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let fileBoard = try board([item(source.absoluteString, type: .fileURL)]); defer { fileBoard.releaseGlobally() }
        let fileDrag = DailyDropFixture(fileBoard); fileDrag.draggingDestinationWindow = panel
        fileDrag.draggingSourceOperationMask = [.copy, .move]
        try expect(hosting.draggingEntered(fileDrag) == .copy, "Daily only offers copy for a copy/move file source")
        try expect(hosting.prepareForDragOperation(fileDrag) && hosting.performDragOperation(fileDrag), "Daily file drop dispatches")
        hosting.concludeDragOperation(fileDrag)
        try await wait("Daily file import completes") { batches.count == 2 && !input.isBusy }
        let fileCapture = try unwrap(batches[1].0.first, "Daily file capture exists")
        try expect(fileCapture.kind == .pdf && fileCapture.originalFilename == source.lastPathComponent, "Daily file keeps its filename and kind")
        try expect(fileCapture.sourceFilePath == source.standardizedFileURL.path, "Daily file retains explicit source path")
        let managed = try unwrap(store.managedURL(for: fileCapture), "Daily file has an archived original")
        try expect(managed != source && managed.path.hasPrefix(store.root.path + "/Archive/"), "Daily drop copies file into local dated archive")
        try expect(try Data(contentsOf: managed) == original, "Daily archived file retains source bytes")
        try expect(try Data(contentsOf: source) == original, "Daily drop leaves original file intact")
        try expect(try source.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == modified,
                   "Daily copy leaves original modification time intact")

        let imageData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
        let imageItem = NSPasteboardItem(); imageItem.setData(imageData, forType: .png)
        let imageBoard = try board([imageItem]); defer { imageBoard.releaseGlobally() }
        let imageDrag = DailyDropFixture(imageBoard); imageDrag.draggingDestinationWindow = panel
        try expect(hosting.draggingEntered(imageDrag) == .copy && hosting.performDragOperation(imageDrag), "Daily accepts original image bytes")
        hosting.concludeDragOperation(imageDrag)
        try await wait("Daily image import completes") { batches.count == 3 && !input.isBusy }
        let imageCapture = try unwrap(batches[2].0.first, "Daily image capture exists")
        let archivedImage = try unwrap(store.managedURL(for: imageCapture), "Daily image original exists")
        try expect(imageCapture.kind == .image && (try Data(contentsOf: archivedImage)) == imageData, "Daily image preserves exact original bytes")

        let url = "https://example.invalid/fictional-daily-link"
        let linkBoard = try board([item(url, type: .URL)]); defer { linkBoard.releaseGlobally() }
        let linkDrag = DailyDropFixture(linkBoard); linkDrag.draggingDestinationWindow = panel
        try expect(hosting.draggingEntered(linkDrag) == .copy && hosting.performDragOperation(linkDrag), "Daily accepts a dragged browser link")
        hosting.concludeDragOperation(linkDrag)
        try await wait("Daily link import completes locally") { batches.count == 4 && !input.isBusy }
        let linkCapture = try unwrap(batches[3].0.first, "Daily link capture exists")
        try expect(linkCapture.kind == .link && linkCapture.originalText == url, "Daily link preserves its address")
        let reopened = try CaptureStore(root: store.root)
        try expect(Set(reopened.captures.map(\.id)) == Set(store.captures.map(\.id)) && reopened.captures.count == 4,
                   "All four Daily input kinds survive reopening storage")

        let unsupportedBoard = try board([item("unsupported", type: .init("org.dabin.fixture.unsupported"))])
        defer { unsupportedBoard.releaseGlobally() }
        let emptyBoard = try board([]); defer { emptyBoard.releaseGlobally() }
        for (label, pasteboard) in [("unsupported", unsupportedBoard), ("empty", emptyBoard)] {
            let drag = DailyDropFixture(pasteboard)
            try expect(hosting.draggingEntered(drag).isEmpty && hosting.draggingUpdated(drag).isEmpty, "Daily rejects \(label) data on hover")
            try expect(!hosting.prepareForDragOperation(drag) && !hosting.performDragOperation(drag), "Daily cannot dispatch \(label) data")
        }
        textDrag.draggingSourceOperationMask = .move
        try expect(hosting.draggingEntered(textDrag).isEmpty && !hosting.performDragOperation(textDrag), "Daily rejects move-only drops")
        textDrag.draggingSourceOperationMask = .copy
        _ = hosting.draggingEntered(textDrag)
        textDrag.draggingSourceOperationMask = .move
        try expect(hosting.draggingUpdated(textDrag).isEmpty && dragStates.last == false, "Source modifier change clears Daily acceptance")
        textDrag.draggingSourceOperationMask = .copy
        _ = hosting.draggingEntered(textDrag); hosting.draggingExited(textDrag)
        try expect(dragStates.last == false, "Daily drag exit clears feedback")
        _ = hosting.draggingEntered(textDrag); hosting.draggingEnded(textDrag)
        try expect(dragStates.last == false, "Cancelled Daily drag clears feedback")
        _ = hosting.draggingEntered(textDrag); hosting.concludeDragOperation(nil)
        try expect(dragStates.last == false, "Nil Daily drag conclusion clears feedback")
        _ = hosting.draggingEntered(textDrag); hosting.clearDropTarget()
        try expect(dragStates.last == false, "Hiding or rerouting Daily can clear feedback explicitly")
        let dropHandler = hosting.onDrop
        hosting.onDrop = nil
        try expect(hosting.draggingEntered(textDrag).isEmpty && !hosting.prepareForDragOperation(textDrag) && !hosting.performDragOperation(textDrag),
                   "Daily never claims a drop when no import handler exists")
        hosting.onDrop = dropHandler
        try expect(dropCount == 4 && store.captures.count == 4 && !input.isBusy, "Rejected/cancelled Daily drops leave storage untouched")

        // Shortcuts are dispatched to local callbacks, not to the general clipboard.
        var pasteCalls = 0
        hosting.onPaste = { pasteCalls += 1 }
        try expect(panel.makeFirstResponder(hosting), "Daily hosting accepts keyboard focus")
        let control = shortcut(.control, time: 1, window: panel)
        try expect(hosting.handlePasteShortcut(control) && pasteCalls == 1, "Daily Control V invokes capture")
        try expect(hosting.handlePasteShortcut(control) && pasteCalls == 1, "The same Daily event cannot capture twice")
        try expect(hosting.handlePasteShortcut(shortcut(.control, time: 1, window: panel)) && pasteCalls == 1,
                   "Duplicate AppKit event metadata cannot capture twice")
        try expect(hosting.handlePasteShortcut(shortcut(.command, time: 2, window: panel)) && pasteCalls == 2,
                   "Daily Command V invokes capture")
        try expect(hosting.handlePasteShortcut(shortcut(.control, time: 3, window: panel, repeatKey: true)) && pasteCalls == 2,
                   "Holding Daily paste consumes repeat without duplicate captures")
        try expect(hosting.handlePasteShortcut(shortcut([.control, .capsLock], time: 4, window: panel, characters: "V", ignoringModifiers: "V")) && pasteCalls == 3,
                   "Caps Lock preserves Daily Control V")
        try expect(hosting.handlePasteShortcut(shortcut(.control, time: 5, window: panel, characters: "\u{16}", ignoringModifiers: "\u{16}")) && pasteCalls == 4,
                   "Control-character representation pastes into Daily")
        for flags: NSEvent.ModifierFlags in [[], [.shift, .control], [.shift, .command], [.option, .command], [.command, .control]] {
            try expect(!hosting.handlePasteShortcut(shortcut(flags, time: 6, window: panel)), "Unrelated Daily modifiers do not capture")
        }
        try expect(!hosting.handlePasteShortcut(shortcut(.command, time: 7, window: panel, characters: "c", ignoringModifiers: "c")), "Command C remains available")
        try expect(!hosting.handlePasteShortcut(shortcut(.control, time: 8, window: panel, type: .keyUp)), "Key-up is not a new Daily capture")
        let robot = RobotView(frame: NSRect(x: 0, y: 0, width: 72, height: 88))
        var robotPastes = 0
        robot.onPaste = { robotPastes += 1 }
        try expect(robot.handlePasteShortcut(shortcut(.control, time: 9, window: panel)) && robotPastes == 1,
                   "Robot still handles its original paste shortcut")
        try expect(robot.handlePasteShortcut(shortcut(.control, time: 9, window: panel)) && robotPastes == 1,
                   "Robot duplicate event metadata is key-safe and does not duplicate capture")
        hosting.pasteCapture(nil)
        try expect(pasteCalls == 5, "Explicit Daily Paste action uses same capture handler")
        let panelControl = shortcut(.control, time: 10, window: panel)
        try expect(panel.performKeyEquivalent(with: panelControl) && pasteCalls == 6,
                   "Daily panel supplies paste fallback for focused board controls")
        panel.keyDown(with: panelControl)
        try expect(pasteCalls == 6, "Panel keyDown and key equivalent share event deduplication")
        panel.keyDown(with: shortcut(.control, time: 11, window: panel))
        try expect(pasteCalls == 7, "Daily panel keyDown captures Control V")
        let pasteMenu = NSMenuItem(title: "Paste", action: #selector(DailyCapturePanel.paste(_:)), keyEquivalent: "v")
        try expect(panel.validateUserInterfaceItem(pasteMenu), "Native Edit Paste is enabled on Daily")
        panel.makeKeyAndOrderFront(nil)
        try await wait("Daily panel becomes key for native Edit routing") { panel.isKeyWindow }
        try expect(application.target(forAction: pasteMenu.action!, to: nil, from: pasteMenu) as? DailyCapturePanel === panel,
                   "Native responder chain resolves the panel's Paste target")
        panel.paste(nil)
        try expect(pasteCalls == 8, "Daily panel explicit Paste reaches capture handler")

        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 120, height: 40))
        editor.isEditable = true; editor.string = "A draft stays a draft"
        hosting.addSubview(editor)
        try expect(panel.makeFirstResponder(editor), "Native text editor can become board responder")
        try expect(!hosting.handlePasteShortcut(shortcut(.command, time: 12, window: panel)), "Daily capture leaves Command V with a native editor")
        try expect(!hosting.handlePasteShortcut(shortcut(.control, time: 13, window: panel)), "Daily capture leaves Control V with a native editor")
        try expect(!panel.validateUserInterfaceItem(pasteMenu), "Panel Paste fallback defers while editing")
        try expect(hosting.draggingEntered(textDrag).isEmpty && !hosting.performDragOperation(textDrag), "Daily destination leaves native editor drops alone")
        try expect(pasteCalls == 8 && editor.string == "A draft stays a draft", "Editor protection adds no capture and preserves draft contents")
        panel.makeFirstResponder(hosting); editor.removeFromSuperview()

        let probe = DailyEditorProbe(frame: NSRect(x: 0, y: 0, width: 120, height: 40))
        hosting.addSubview(probe)
        try expect(panel.makeFirstResponder(probe), "Editor fallback probe receives focus")
        _ = panel.performKeyEquivalent(with: shortcut(.command, time: 14, window: panel))
        try expect(pasteCalls == 8, "Panel Command V fallback does not create captures while editing")
        panel.makeFirstResponder(hosting); probe.removeFromSuperview()

        for route: BoardRoute in [.weekly, .search, .newTask, .detail, .reminders, .settings] {
            state.route = route
            try expect(!hosting.handlePasteShortcut(shortcut(.control, time: 20, window: panel)), "\(route) never captures a Daily shortcut")
            try expect(hosting.draggingEntered(textDrag).isEmpty && !hosting.prepareForDragOperation(textDrag) && !hosting.performDragOperation(textDrag),
                       "\(route) never intercepts Daily drops")
            try expect(!panel.validateUserInterfaceItem(pasteMenu), "\(route) cannot enable Daily Paste fallback")
            hosting.pasteCapture(nil)
            try expect(pasteCalls == 8, "\(route) explicit Paste cannot create a Daily capture")
        }
        state.openDaily()
        try expect(store.captures.count == 4 && dropCount == 4, "All shortcut routing tests leave the isolated archive unchanged")

        // Exercise production controller wiring; the board imports at capture
        // time even when the user was viewing an old day through a narrow filter.
        let controller = CornerController(state: state, input: input, placementDefaults: nil, animateRobotTransitions: false)
        defer { controller.dismiss(); controller.bin.orderOut(nil); controller.board.orderOut(nil) }
        try expect(controller.board.responds(to: #selector(DailyCapturePanel.paste(_:))), "Controller installs a native Paste responder")
        let wired = try unwrap(controller.board.captureHostingView, "Controller installs Daily capture hosting")
        controller.openDaily()
        state.selectedDay = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        state.filter = .files
        _ = wired.draggingEntered(textDrag)
        try expect(state.isDailyDropTargeted, "Real controller publishes Daily drag highlight")
        try expect(wired.performDragOperation(textDrag), "Real Daily controller accepts direct text drop")
        wired.concludeDragOperation(textDrag)
        try expect(!state.isDailyDropTargeted, "Real controller clears Daily drag highlight after drop")
        try await wait("Controller-wired Daily drop persists") { store.captures.count == 5 && !input.isBusy }
        try expect(state.route == .daily && Calendar.current.isDateInToday(state.selectedDay) && state.filter == .all,
                   "Daily capture returns to Today and All so the new item is visible")
        let latest = try unwrap(store.captures.filter { $0.originalText == text }.max(by: { $0.capturedAt < $1.capturedAt }), "Controller capture exists")
        try expect(latest.captureDay == CaptureCalendar.dayString(Date()), "Daily drop uses current capture date, not browsed date")
        try expect(state.dailyCaptures.contains { $0.id == latest.id }, "New capture is present in the visible Daily selection")
        try expect(controller.board.isVisible && !controller.bin.isVisible, "Direct Daily drop keeps one visible board without summoning robot")
        let oldDay = Calendar.current.date(byAdding: .day, value: -5, to: Date())!
        state.selectedDay = oldDay; state.filter = .media
        let missing = root.appendingPathComponent("missing-original.pdf")
        let missingBoard = try board([item(missing.absoluteString, type: .fileURL)])
        defer { missingBoard.releaseGlobally() }
        let missingDrag = DailyDropFixture(missingBoard)
        try expect(wired.performDragOperation(missingDrag), "A readable file representation starts explicit import")
        try await wait("Missing file import finishes with failure") { !input.isBusy }
        try expect(store.captures.count == 5 && state.selectedDay == oldDay && state.filter == .media,
                   "Failed Daily import preserves the browsed date and filter")
        try expect(state.status?.severity == .error, "Failed Daily import shows actionable status")
        try expect(wired.performDragOperation(textDrag), "A following valid Daily import starts")
        state.openNewTask()
        state.newTaskDraft.text = "Keep my fictional draft open"
        try await wait("Daily import finishes after navigation") { store.captures.count == 6 && !input.isBusy }
        try expect(state.route == .newTask && state.newTaskDraft.text == "Keep my fictional draft open",
                   "A finishing import does not pull the user out of a new task draft")
        state.newTaskDraft.text = ""
        state.openDaily()
        state.selectedDay = oldDay; state.filter = .files
        try expect(wired.performDragOperation(textDrag), "Another Daily import starts before a date selection")
        let differentDay = Calendar.current.date(byAdding: .day, value: -2, to: oldDay)!
        state.selectedDay = differentDay
        try await wait("Daily import finishes after a date change") { store.captures.count == 7 && !input.isBusy }
        try expect(state.route == .daily && state.selectedDay == differentDay && state.filter == .files,
                   "A finishing import respects the user's later date choice")
        try expect(wired.performDragOperation(textDrag), "Another Daily import starts before a filter selection")
        state.filter = .tasks
        try await wait("Daily import finishes after a filter change") { store.captures.count == 8 && !input.isBusy }
        try expect(state.selectedDay == differentDay && state.filter == .tasks,
                   "A finishing import respects the user's later filter choice")
        try expect(wired.performDragOperation(textDrag), "Another Daily import starts before temporary navigation")
        state.showSettings()
        state.route = .daily
        try await wait("Daily import finishes after leaving and returning") { store.captures.count == 9 && !input.isBusy }
        try expect(state.selectedDay == differentDay && state.filter == .tasks,
                   "A finishing import preserves a view the user left and deliberately revisited")
        _ = wired.draggingEntered(textDrag)
        try expect(state.isDailyDropTargeted, "Controller receives next hover feedback")
        state.showSettings()
        try expect(!state.isDailyDropTargeted, "Leaving Daily clears its drop highlight")
        state.route = .daily
        _ = wired.draggingUpdated(textDrag)
        try expect(state.isDailyDropTargeted, "Returning to Daily during a drag restores targeting feedback")
        controller.dismiss()
        try expect(!state.isDailyDropTargeted, "Dismissing Daily clears stale drop feedback")
        try expect(notifications.permissionRequests == 0 && notifications.additions == 0,
                   "Daily capture never requests notification permission or schedules a reminder")
        print("PASS: \(checks) Daily capture checks (private pasteboards, local archive, native drop callbacks, shortcut/editor routing and controller integration)")
    }
}
