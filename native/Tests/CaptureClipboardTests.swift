import AppKit
import Foundation

@MainActor
private final class ClipboardReminderClient: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .allowed }
    func requestAuthorization() async throws -> Bool { true }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}

@main
struct CaptureClipboardTests {
    @MainActor private static var checks = 0

    @MainActor
    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        if !condition() {
            throw NSError(domain: "CaptureClipboardTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    @MainActor
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DaBinClipboard-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root)

        let exactNote = "  Exact note body ✨\nwith a second line  "
        let note = try store.capture(text: exactNote)[0]
        let link = try store.capture(text: "https://example.com/path?q=copy")[0]
        let task = try store.createTask(text: "Copy this task")
        let sourceOne = root.appendingPathComponent("Source One.pdf")
        let sourceTwo = root.appendingPathComponent("Source Two.txt")
        try Data("one".utf8).write(to: sourceOne)
        try Data("two".utf8).write(to: sourceTwo)
        let fileOne = try await store.importFile(sourceOne)
        let fileTwo = try await store.importFile(sourceTwo, at: fileOne.capturedAt)
        let imageBytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j8ocAAAAASUVORK5CYII=")!
        let image = try await store.importData(imageBytes, filename: "Copied image.png")

        var written: [CaptureClipboardPayload] = []
        let service = CaptureClipboardService { payload in
            written.append(payload)
            return true
        }

        let notePayload = try service.copy([note], managedURL: store.managedURL(for:))
        try expect(notePayload.items == [.text(exactNote)],
                   "Text copy preserves exact whitespace, newlines and emoji")
        let linkPayload = try service.copy([link], managedURL: store.managedURL(for:))
        try expect(linkPayload.items == [.webURL("https://example.com/path?q=copy")],
                   "Link copy preserves the original URL")
        let taskPayload = try service.copy([task], managedURL: store.managedURL(for:))
        try expect(taskPayload.items == [.text("Copy this task")],
                   "Task copy uses its original text")

        let batchPayload = try service.copy([fileOne, fileTwo], managedURL: store.managedURL(for:))
        try expect(batchPayload.items.count == 2, "A two-file action copies both saved originals")
        guard case .file(let firstURL) = batchPayload.items[0],
              case .file(let secondURL) = batchPayload.items[1] else {
            throw NSError(domain: "CaptureClipboardTests", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "File batch contains file clipboard items"])
        }
        try expect(firstURL == store.managedURL(for: fileOne) && secondURL == store.managedURL(for: fileTwo),
                   "File copy uses DaBin-managed originals in action order")
        try expect(written.count == 4, "Every successful request writes once")

        let privateBoard = NSPasteboard(name: .init("DaBin.ClipboardTests.\(UUID().uuidString)"))
        let nativeService = CaptureClipboardService(pasteboard: privateBoard)
        try nativeService.copy([link], managedURL: store.managedURL(for:))
        try expect(privateBoard.pasteboardItems?.count == 1,
                   "A link writes one native pasteboard item")
        try expect(privateBoard.pasteboardItems?.first?.string(forType: .URL) == "https://example.com/path?q=copy",
                   "Native link copy exposes URL data")
        try expect(privateBoard.string(forType: .string) == "https://example.com/path?q=copy",
                   "Native link copy also exposes plain text")

        try nativeService.copy([fileOne, fileTwo], managedURL: store.managedURL(for:))
        let copiedFileURLs = privateBoard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
        try expect(copiedFileURLs?.count == 2, "Native batch copy exposes both file URLs")
        try expect(copiedFileURLs == [firstURL, secondURL], "Native batch copy preserves file order")

        try nativeService.copy([image], managedURL: store.managedURL(for:))
        let copiedImageURLs = privateBoard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
        try expect(copiedImageURLs?.count == 1, "Native image copy exposes one local file URL")
        try expect(copiedImageURLs?.first.flatMap { try? Data(contentsOf: $0) } == imageBytes,
                   "Copied image file preserves the captured pixels exactly")

        var failureWrites = 0
        let failing = CaptureClipboardService { _ in failureWrites += 1; return false }
        do {
            _ = try failing.copy([note], managedURL: store.managedURL(for:))
            try expect(false, "A failed pasteboard write throws")
        } catch CaptureClipboardError.writeFailed {
            try expect(failureWrites == 1, "A failed writer is attempted exactly once")
        }

        do {
            _ = try service.copy([], managedURL: store.managedURL(for:))
            try expect(false, "An empty action cannot overwrite the clipboard")
        } catch CaptureClipboardError.noContent {
            try expect(written.count == 4, "An empty action never reaches the writer")
        }

        try FileManager.default.removeItem(at: firstURL)
        do {
            _ = try service.copy([fileOne], managedURL: store.managedURL(for:))
            try expect(false, "A missing saved original cannot report a successful copy")
        } catch CaptureClipboardError.missingSavedOriginal {
            try expect(written.count == 4, "A missing original leaves the clipboard untouched")
        }

        let validBeforeBrokenBatch = written.count
        do {
            _ = try service.copy([fileTwo, fileOne], managedURL: store.managedURL(for:))
            try expect(false, "A batch with one missing original cannot partially copy")
        } catch CaptureClipboardError.missingSavedOriginal {
            try expect(written.count == validBeforeBrokenBatch,
                       "A broken batch is validated in full before the clipboard writer runs")
        }

        let stateClipboard = CaptureClipboardService { payload in
            written.append(payload)
            return true
        }
        let state = AppState(store: store, previews: PreviewService(store: store),
                             reminders: ReminderService(store: store, client: ClipboardReminderClient()),
                             captureClipboard: stateClipboard)
        try expect(state.copyCapturesToClipboard([task]), "App state reports a successful card copy")
        try expect(state.status == nil, "Successful card copy does not resize the board with a banner")
        try expect(state.route == .daily && state.selectedCapture == nil,
                   "Copying a card leaves navigation and selection unchanged")
        try expect(CaptureCopyButton.accessibilityIdentifier(for: [task]) == "capture-copy-\(task.id.uuidString)",
                   "A single card copy control has a stable accessibility identifier")
        try expect(CaptureCopyButton.accessibilityLabel(for: [task], copied: false) == "Copy Copy this task to clipboard",
                   "A single card copy control names its captured content")
        try expect(CaptureCopyButton.accessibilityIdentifier(for: [fileOne, fileTwo]) == "capture-copy-batch-\(fileOne.id.uuidString)",
                   "A batch copy control has one stable group accessibility identifier")
        try expect(CaptureCopyButton.accessibilityLabel(for: [fileOne, fileTwo], copied: true) == "Copied 2 captured items",
                   "A batch copy control exposes success to assistive technology")
        let stale = Capture(kind: .text, originalText: "stale", title: "stale")
        try expect(!state.copyCapturesToClipboard([stale]), "A stale card cannot replace the clipboard")
        try expect(state.status?.severity == .error, "A stale card reports visible failure feedback")

        print("PASS: \(checks) capture clipboard checks; text, links, tasks, files, batches, native types and failures.")
    }
}
