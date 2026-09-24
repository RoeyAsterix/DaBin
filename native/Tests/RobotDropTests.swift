import AppKit
import Foundation

/// Supplies native destination callbacks without driving the system cursor or
/// accessing the user's clipboard. No actual drag source application is opened.
@MainActor private final class DropFixture: NSObject, NSDraggingInfo {
    var draggingDestinationWindow: NSWindow?
    var draggingSourceOperationMask: NSDragOperation = .copy
    var draggingLocation = NSPoint(x: 36, y: 44)
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

@MainActor private final class DropNotificationClient: ReminderNotificationClient {
    var permissionRequests = 0
    var additions = 0
    func authorization() async -> ReminderAuthorization { .undetermined }
    func requestAuthorization() async throws -> Bool { permissionRequests += 1; return false }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { additions += 1 }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}

@main struct RobotDropTests {
    @MainActor private static var checks = 0
    @MainActor private static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        if try !value() { throw NSError(domain: "DaBinRobotDropTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    @MainActor private static func wait(_ message: String, until condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try expect(condition(), message)
    }
    @MainActor private static func board(_ items: [NSPasteboardItem]) throws -> NSPasteboard {
        let result = NSPasteboard(name: .init("DaBin.RobotDropTests.\(UUID().uuidString)"))
        result.clearContents()
        if !items.isEmpty { try expect(result.writeObjects(items), "Private drop fixture writes") }
        return result
    }
    @MainActor private static func item(_ text: String, type: NSPasteboard.PasteboardType = .string) -> NSPasteboardItem {
        let result = NSPasteboardItem()
        result.setString(text, forType: type)
        return result
    }
    private static func point(_ corner: ScreenCorner, screen: NSScreen) -> NSPoint {
        NSPoint(x: corner.isRight ? screen.frame.maxX - 1 : screen.frame.minX + 1,
                y: corner.isTop ? screen.frame.maxY - 1 : screen.frame.minY + 1)
    }

    @MainActor static func main() async throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.finishLaunching()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinRobotDropTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root.appendingPathComponent("ArchiveFixture"))
        let input = InputService(store: store, stagingRoot: root.appendingPathComponent("Promises"))
        let robot = RobotView(frame: NSRect(x: 11, y: 17, width: 72, height: 88))
        var dropCount = 0
        var dragStates: [Bool] = []
        var batches: [([Capture], [String])] = []
        robot.onDragState = { dragStates.append($0) }
        robot.onDrop = { pasteboard in dropCount += 1; input.receive(pasteboard) }
        input.onResult = { batches.append(($0, $1)) }
        input.onBusy = { robot.isSaving = $0 }

        // The decorative NSImageView and badge must never intercept a drop.
        for local in [NSPoint(x: 2, y: 2), NSPoint(x: 35, y: 44), NSPoint(x: 54, y: 72), NSPoint(x: 70, y: 86)] {
            let parentPoint = NSPoint(x: robot.frame.minX + local.x, y: robot.frame.minY + local.y)
            try expect(robot.hitTest(parentPoint) === robot, "Robot owns hit testing at \(local)")
        }
        try expect(robot.hitTest(NSPoint(x: robot.frame.minX - 1, y: robot.frame.midY)) == nil, "Outside robot remains transparent to mouse hit testing")

        let text = "A fictional paragraph dragged from another app.\nSecond line remains intact."
        let textBoard = try board([item(text)]); defer { textBoard.releaseGlobally() }
        let textDrag = DropFixture(textBoard)
        try expect(robot.draggingEntered(textDrag) == .copy, "Text enters as copy")
        try expect(dragStates.last == true, "Text hover retains robot")
        try expect(robot.draggingUpdated(textDrag) == .copy, "Text remains accepted while moving")
        try expect(store.captures.isEmpty && dropCount == 0, "Hover does not capture data")
        try expect(robot.prepareForDragOperation(textDrag), "Text drop prepares")
        try expect(robot.performDragOperation(textDrag), "Text drop dispatches")
        robot.concludeDragOperation(textDrag)
        try expect(dragStates.last == false, "Completed text drop releases drag hold")
        try await wait("Text is durably received") { batches.count == 1 && !input.isBusy }
        try expect(dropCount == 1 && batches[0].0.count == 1 && batches[0].1.isEmpty, "One text drop produces one success")
        let textCapture = try unwrap(batches[0].0.first, "Text capture exists")
        try expect(textCapture.kind == .text && textCapture.originalText == text, "Dragged text keeps exact original content")
        try expect(textCapture.sourceFilePath == nil && textCapture.sourceURL == nil, "Plain dragged text does not invent provenance")
        let textArchive = try unwrap(store.archiveURL(for: textCapture), "Text archive exists")
        try expect(try String(contentsOf: textArchive.appendingPathComponent("Content.txt"), encoding: .utf8) == text, "Text original is saved in dated archive")
        try expect(FileManager.default.fileExists(atPath: textArchive.appendingPathComponent("Capture.json").path), "Text metadata sidecar exists")

        // A copy destination must leave a Finder-style file source untouched.
        let source = root.appendingPathComponent("Fictional document.pdf")
        let original = Data("%PDF-1.4\nDaBin fictional drag test\n%%EOF\n".utf8)
        try original.write(to: source)
        let sourceDate = try source.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let fileBoard = try board([item(source.absoluteString, type: .fileURL)]); defer { fileBoard.releaseGlobally() }
        let fileDrag = DropFixture(fileBoard)
        fileDrag.draggingSourceOperationMask = [.copy, .move]
        try expect(robot.draggingEntered(fileDrag) == .copy, "File source offering copy and move is accepted as copy")
        try expect(robot.prepareForDragOperation(fileDrag) && robot.performDragOperation(fileDrag), "File drops on robot")
        robot.concludeDragOperation(fileDrag)
        try await wait("File import finishes") { batches.count == 2 && !input.isBusy }
        try expect(dropCount == 2 && batches[1].0.count == 1 && batches[1].1.isEmpty, "One file drop produces one success")
        let fileCapture = try unwrap(batches[1].0.first, "File capture exists")
        try expect(fileCapture.kind == .pdf && fileCapture.originalFilename == source.lastPathComponent, "Dropped PDF keeps its filename and type")
        try expect(fileCapture.sourceFilePath == source.standardizedFileURL.path, "Dropped file records its explicit source path")
        let managed = try unwrap(store.managedURL(for: fileCapture), "Managed original exists")
        try expect(managed != source && managed.path.hasPrefix(store.root.path + "/Archive/"), "Dropped file is copied into dated local archive")
        try expect(try Data(contentsOf: managed) == original, "Archived file retains exact bytes")
        try expect(try Data(contentsOf: source) == original, "Source file retains exact bytes")
        try expect(try source.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == sourceDate, "Copy does not change source modification date")
        let reopened = try CaptureStore(root: store.root)
        try expect(reopened.captures.count == 2 && Set(reopened.captures.map(\.id)) == Set(store.captures.map(\.id)), "Both robot drops survive reopening the store")

        let unsupportedBoard = try board([item("unsupported", type: .init("org.dabin.test.unsupported"))])
        defer { unsupportedBoard.releaseGlobally() }
        let unsupported = DropFixture(unsupportedBoard)
        try expect(robot.draggingEntered(unsupported).isEmpty, "Unknown representation is rejected on entry")
        try expect(robot.draggingUpdated(unsupported).isEmpty, "Unknown representation stays rejected")
        try expect(!robot.prepareForDragOperation(unsupported), "Unknown representation cannot prepare")
        try expect(!robot.performDragOperation(unsupported), "Unknown representation cannot dispatch")
        let emptyBoard = try board([]); defer { emptyBoard.releaseGlobally() }
        let empty = DropFixture(emptyBoard)
        try expect(robot.draggingEntered(empty).isEmpty && !robot.performDragOperation(empty), "Empty drag is rejected")
        textDrag.draggingSourceOperationMask = .move
        try expect(robot.draggingEntered(textDrag).isEmpty, "Move-only source is rejected instead of moving content")
        try expect(!robot.prepareForDragOperation(textDrag) && !robot.performDragOperation(textDrag), "Move-only source cannot dispatch")

        textDrag.draggingSourceOperationMask = .copy
        _ = robot.draggingEntered(textDrag)
        textDrag.draggingSourceOperationMask = .move
        try expect(robot.draggingUpdated(textDrag).isEmpty && dragStates.last == false, "Modifier/source mask change withdraws acceptance and hold")
        try expect(!robot.performDragOperation(textDrag), "A source changed to move cannot dispatch")
        textDrag.draggingSourceOperationMask = .copy
        _ = robot.draggingEntered(textDrag)
        robot.draggingExited(textDrag)
        try expect(dragStates.last == false, "Leaving robot clears accepted drag hold")
        _ = robot.draggingEntered(textDrag)
        robot.draggingEnded(textDrag)
        try expect(dragStates.last == false, "Cancelled drag clears accepted drag hold")
        _ = robot.draggingEntered(textDrag)
        robot.concludeDragOperation(nil)
        try expect(dragStates.last == false, "Concluding without drag info clears accepted drag hold")
        robot.onDrop = nil
        try expect(robot.draggingEntered(textDrag).isEmpty && !robot.prepareForDragOperation(textDrag) && !robot.performDragOperation(textDrag), "Robot without capture handler never claims successful drop")
        try expect(dropCount == 2 && batches.count == 2 && store.captures.count == 2 && !input.isBusy, "All rejected and cancelled drags leave archive untouched")

        // A first-open board has no saved placement yet. Revealing its robot at
        // another corner must not re-anchor the board when the import resizes it.
        if let initialScreen = NSScreen.main {
            let placementSuite = "DaBinRobotDropTests.\(UUID().uuidString)"
            let preferences = UserDefaults(suiteName: placementSuite)!
            defer { preferences.removePersistentDomain(forName: placementSuite) }
            let freshStore = try CaptureStore(root: root.appendingPathComponent("UnplacedBoardFixture"))
            let freshInput = InputService(store: freshStore)
            let freshPreviews = PreviewService(store: freshStore)
            let freshReminders = ReminderService(store: freshStore, client: DropNotificationClient())
            let freshState = AppState(store: freshStore, previews: freshPreviews, reminders: freshReminders)
            let freshController = CornerController(state: freshState, input: freshInput, placementDefaults: preferences, animateRobotTransitions: false)
            defer { freshController.dismiss(); freshController.bin.orderOut(nil); freshController.board.orderOut(nil); freshPreviews.cancelNetwork() }
            freshController.reveal(on: initialScreen, corner: .bottomRight)
            freshController.openDaily()
            let initialFrame = freshController.board.frame
            let initialTopLeft = NSPoint(x: initialFrame.minX, y: initialFrame.maxY)
            try expect(preferences.object(forKey: CornerController.boardPlacementKey) == nil, "Initial automatic board placement is not persisted")
            let targetScreen = NSScreen.screens.first(where: { $0 !== initialScreen }) ?? initialScreen
            freshController.pollPointer(at: point(.topLeft, screen: targetScreen), pressedMouseButtons: 1)
            try expect(freshController.bin.isVisible && freshController.board.frame == initialFrame, "Opposite-corner reveal leaves the unplaced board where it opened")
            _ = freshController.robot.draggingEntered(textDrag)
            try expect(freshController.robot.performDragOperation(textDrag), "Opposite-corner drop reaches unplaced board's handler")
            freshController.robot.concludeDragOperation(textDrag)
            try await wait("Opposite-corner drop persists") { freshStore.captures.count == 1 && !freshInput.isBusy }
            // Waiting for an actual size change proves the debounced publication
            // ran, rather than checking the old frame before resizeBoard executes.
            try await wait("Capture publication resizes the initially empty board") {
                freshController.board.frame.height != initialFrame.height
            }
            let afterDrop = freshController.board.frame
            try expect(NSPoint(x: afterDrop.minX, y: afterDrop.maxY) == initialTopLeft, "Opposite-corner capture resize preserves original board top-left")
            try expect(initialScreen.visibleFrame.contains(afterDrop), "Opposite-display robot capture keeps board on its original screen")
            try expect(preferences.object(forKey: CornerController.boardPlacementKey) == nil, "Robot reveal and capture resize do not create a saved user placement")
        }

        // Exercise the real controller's robot callback and pointer policy while
        // a Daily board is open. All storage and preferences remain isolated.
        let notifications = DropNotificationClient()
        let previews = PreviewService(store: store)
        let reminders = ReminderService(store: store, client: notifications)
        let state = AppState(store: store, previews: previews, reminders: reminders)
        let controller = CornerController(state: state, input: input, placementDefaults: nil, animateRobotTransitions: false)
        defer { controller.dismiss(); controller.bin.orderOut(nil); controller.board.orderOut(nil); previews.cancelNetwork() }
        try expect(!NSScreen.screens.isEmpty, "Corner drag checks require an attached screen")
        for (index, screen) in NSScreen.screens.enumerated() {
            let away = NSPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY)
            for corner in ScreenCorner.allCases {
                controller.openDaily()
                let start = Date().addingTimeInterval(10)
                controller.pollPointer(at: away, now: start, pressedMouseButtons: 0)
                controller.pollPointer(at: point(corner, screen: screen), now: start, pressedMouseButtons: 0)
                try expect(!controller.bin.isVisible && controller.board.isVisible, "Screen \(index) \(corner): ordinary hover preserves board-only presence")
                controller.pollPointer(at: point(corner, screen: screen), now: start, pressedMouseButtons: 1)
                try expect(controller.bin.isVisible && controller.board.isVisible, "Screen \(index) \(corner): held drag reveals robot alongside Daily")
                try expect(controller.bin.frame == CornerGeometry.robotFrame(corner: corner, visible: screen.visibleFrame), "Screen \(index) \(corner): correct corner robot receives drop")
                try expect(!controller.bin.isKeyWindow, "Screen \(index) \(corner): drag reveal does not steal keyboard focus")
                _ = controller.robot.draggingEntered(textDrag)
                controller.pollPointer(at: away, now: start.addingTimeInterval(2), pressedMouseButtons: 1)
                try expect(controller.bin.isVisible, "Screen \(index) \(corner): active drag holds robot visible")
                controller.robot.draggingEnded(textDrag)
                controller.pollPointer(at: away, now: start.addingTimeInterval(4), pressedMouseButtons: 0)
                try expect(!controller.bin.isVisible && controller.board.isVisible, "Screen \(index) \(corner): cancelled drag retreats while board stays open")
            }
        }
        if let screen = NSScreen.screens.first {
            let away = NSPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY)
            controller.openDaily()
            controller.pollPointer(at: point(.topLeft, screen: screen), pressedMouseButtons: 1)
            _ = controller.robot.draggingEntered(textDrag)
            try expect(controller.robot.performDragOperation(textDrag), "Controller wiring accepts direct robot drop")
            controller.robot.concludeDragOperation(textDrag)
            try await wait("Controller-wired drop reaches archive") { store.captures.count == 3 && !input.isBusy }
            try expect(controller.bin.isVisible && controller.board.isVisible, "Robot remains for digestion feedback when Daily is open")
            controller.pollPointer(at: away, now: Date(), pressedMouseButtons: 0)
            try expect(controller.bin.isVisible, "Digestion feedback survives immediate cursor exit")
            controller.pollPointer(at: away, now: Date().addingTimeInterval(5), pressedMouseButtons: 0)
            try expect(!controller.bin.isVisible && controller.board.isVisible, "Robot retreats after digestion without closing Daily")
            state.onBoardDragStarted?()
            controller.pollPointer(at: point(.topLeft, screen: screen), pressedMouseButtons: 1)
            try expect(!controller.bin.isVisible, "Moving DaBin's own header to a corner does not summon robot")
        }
        try expect(notifications.permissionRequests == 0 && notifications.additions == 0, "Drop tests never request notifications or schedule reminders")
        print("PASS: \(checks) robot drop checks (private pasteboards, isolated archive, native destination callbacks and corner panels)")
    }

    private static func unwrap<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw NSError(domain: "DaBinRobotDropTests", code: 2,
            userInfo: [NSLocalizedDescriptionKey: message]) }
        return value
    }
}
