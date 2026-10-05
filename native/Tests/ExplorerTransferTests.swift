import AppKit
import Foundation
import UniformTypeIdentifiers

private final class ExplorerLatePromiseFixture: InputFilePromise {
    private(set) var fileNames: [String] = []
    private let name: String
    private var destination: URL?
    private var queue: OperationQueue?
    private var reader: ((URL, Error?) -> Void)?
    init(_ name: String) { self.name = name }
    func receive(at destination: URL, operationQueue: OperationQueue, reader: @escaping (URL, Error?) -> Void) {
        self.destination = destination; queue = operationQueue; self.reader = reader; fileNames = [name]
    }
    func deliver() {
        guard let destination, let queue, let reader else { fatalError("Promise was never requested") }
        let name = name
        queue.addOperation {
            let url = destination.appendingPathComponent(name)
            do {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                try Data(name.utf8).write(to: url)
                reader(url, nil)
            } catch { reader(url, error) }
        }
    }
}

@MainActor private final class ExplorerTransferReminderClient: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .allowed }
    func requestAuthorization() async throws -> Bool { true }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}

@main struct ExplorerTransferTests {
    @MainActor private static var checks = 0
    @MainActor private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        if try !condition() { throw NSError(domain: "ExplorerTransferTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    @MainActor private static func waitForIdle(_ controller: ExplorerCaptureController) async throws {
        let deadline = Date().addingTimeInterval(5)
        while controller.isBusy && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try expect(!controller.isBusy, "Explorer intake finishes its busy state")
    }

    @MainActor private static func sharedInputLifecycle(_ root: URL) async throws {
        let firstBoard = NSPasteboard(name: .init("DaBin.ExplorerLate.First.\(UUID())"))
        let secondBoard = NSPasteboard(name: .init("DaBin.ExplorerLate.Second.\(UUID())"))
        defer { firstBoard.releaseGlobally(); secondBoard.releaseGlobally() }
        let first = ExplorerLatePromiseFixture("Old-promise.txt")
        let second = ExplorerLatePromiseFixture("New-promise.txt")
        let store = try CaptureStore(root: root)
        let input = InputService(store: store, promiseTimeout: 1, stagingRoot: root,
                                 promiseReader: { $0.name == firstBoard.name ? [first] : [second] })
        let previews = PreviewService(store: store)
        defer { previews.shutdown() }
        let state = AppState(store: store, previews: previews,
            reminders: ReminderService(store: store, client: ExplorerTransferReminderClient()), manualInput: input)
        var priorBusyCalls = 0
        let originalObserver = input.onBusy
        input.onBusy = { busy in originalObserver?(busy); priorBusyCalls += 1 }
        let controller = ExplorerCaptureController(state: state, input: input)
        var completions = 0
        input.onResult = { _, _ in completions += 1 }
        controller.paste(project: "First project", from: firstBoard)
        try expect(input.isBusy && controller.isBusy, "Explorer uses the injected input's promise lifecycle immediately")
        try await waitForIdle(controller)
        try expect(completions == 1 && priorBusyCalls >= 2 && !state.isImporting,
                   "Timeout releases only its operation and retains existing InputService busy observers")
        controller.paste(project: "Second project", from: secondBoard)
        first.deliver()
        let deadline = Date().addingTimeInterval(5)
        while completions < 2 && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try expect(completions == 2 && input.isBusy && controller.isBusy && state.isImporting,
                   "An older late completion cannot clear a newer Explorer receive or its quit protection")
        try expect(store.captures.contains { $0.originalFilename == "Old-promise.txt" && $0.projectName == "First project" },
                   "Late promised files retain the destination of their original paste")
        second.deliver()
        try await waitForIdle(controller)
        try expect(completions == 3 && !input.isBusy && !state.isImporting,
                   "The final receive releases aggregate busy state after each promise is reported once")
        try expect(store.captures.contains { $0.originalFilename == "New-promise.txt" && $0.projectName == "Second project" },
                   "A newer receive keeps its own independent project destination")
    }

    @MainActor private static func undoFailureRetry(_ root: URL) async throws {
        let store = try CaptureStore(root: root)
        let defaultsName = "DaBin.ExplorerUndo.\(UUID())"
        let defaults = UserDefaults(suiteName: defaultsName)!
        let previews = PreviewService(store: store, defaults: defaults)
        let board = NSPasteboard(name: .init("DaBin.ExplorerUndo.\(UUID())"))
        let state = AppState(store: store, previews: previews,
            reminders: ReminderService(store: store, client: ExplorerTransferReminderClient()),
            captureClipboard: CaptureClipboardService(pasteboard: board))
        defer {
            state.autoCapture.shutdown(); state.focusSessions.shutdown(); state.shutdownNotificationPresentation()
            previews.shutdown(); board.releaseGlobally()
            defaults.removePersistentDomain(forName: defaultsName)
        }
        let first = try store.capture(text: "First exact move original", projectName: "Origin")[0]
        let second = try store.capture(text: "Second exact move original", projectName: "Origin")[0]
        let laterEdited = try store.capture(text: "Later edited move original", projectName: "Origin")[0]
        let items = [first, second, laterEdited]
        let originals = items.map { ($0.id, $0.originalText, $0.capturedAt) }
        let providers = try items.map { try ExplorerTransfer.itemProvider(for: $0, store: store) }
        let controller = ExplorerCaptureController(state: state, input: InputService(store: store))
        try expect(controller.receive(providers, project: "Destination"), "A mixed Undo fixture moves one existing identity per provider")
        try await waitForIdle(controller)
        try store.setOrganization(laterEdited, pinned: true, projectName: "Later work")
        let movedRevisions = Dictionary(uniqueKeysWithValues: [first, second].map { ($0.id, $0.updatedAt) })
        var writes = 0
        store.failureInjector = { point in
            if point == .beforeMetadataSave {
                writes += 1
                if writes == 1 { throw CaptureStoreError.injectedInterruption }
            }
        }
        controller.undoLastMove()
        try expect(writes == 2 && controller.canUndoMove && state.status?.severity == .warning,
                   "A transient Undo write failure retains only a retryable receipt and reports partial restoration")
        let retry = [first, second].first { $0.projectName == "Destination" }!
        let restored = [first, second].first { $0.projectName == "Origin" }!
        let restoredRevision = restored.updatedAt
        try expect(retry.updatedAt == movedRevisions[retry.id] && laterEdited.projectName == "Later work" && laterEdited.isPinned,
                   "Failed Undo rolls back its exact revision while a stale receipt never overwrites later work")
        let afterFailure = try CaptureStore(root: root)
        try expect(afterFailure.captures.first { $0.id == retry.id }?.projectName == "Destination"
            && afterFailure.captures.first { $0.id == restored.id }?.projectName == "Origin"
            && afterFailure.captures.first { $0.id == laterEdited.id }?.projectName == "Later work",
                   "Restart observes successful restorations and preserves failed or later-edited items")
        store.failureInjector = nil
        controller.undoLastMove()
        try expect(!controller.canUndoMove && first.projectName == "Origin" && second.projectName == "Origin"
            && laterEdited.projectName == "Later work" && restored.updatedAt == restoredRevision,
                   "Retry restores only the failed eligible item without repeating a successful Undo")
        controller.undoLastMove()
        try expect(restored.updatedAt == restoredRevision && Set(store.captures.map(\.id)) == Set(items.map(\.id)),
                   "An exhausted receipt neither runs twice nor duplicates original identities")
        for (id, text, receipt) in originals {
            let item = store.captures.first { $0.id == id }!
            try expect(item.originalText == text && item.capturedAt == receipt,
                       "Mixed Undo and retry preserve exact original content and saved receipt dates")
        }
        try expect(controller.receive([providers[0]], project: "Destination"), "Another move creates a fresh receipt")
        try await waitForIdle(controller)
        store.failureInjector = { if $0 == .beforeMetadataSave { throw CaptureStoreError.injectedInterruption } }
        controller.undoLastMove()
        try expect(controller.canUndoMove && first.projectName == "Destination", "A fully failed Undo remains available")
        store.failureInjector = nil
        try store.setOrganization(first, pinned: true, projectName: "Newer destination")
        controller.undoLastMove()
        try expect(!controller.canUndoMove && first.projectName == "Newer destination" && first.isPinned,
                   "An edit after a failed Undo invalidates its retry instead of discarding newer work")
        let reopened = try CaptureStore(root: root)
        try expect(reopened.captures.first { $0.id == first.id }?.projectName == "Newer destination"
            && reopened.captures.count == items.count, "Final restart preserves later edits and exact capture count")
    }

    private static func load(_ provider: NSItemProvider, type: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                if let error { continuation.resume(throwing: error) }
                else if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: ExplorerTransferError.invalidReference) }
            }
        }
    }

    private static func readFileBytes(_ provider: NSItemProvider, type: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                if let error { continuation.resume(throwing: error) }
                else if let url {
                    do { continuation.resume(returning: try Data(contentsOf: url)) }
                    catch { continuation.resume(throwing: error) }
                } else { continuation.resume(throwing: ExplorerTransferError.invalidReference) }
            }
        }
    }

    private static func identityProvider(_ data: Data, fallback: String = "Do not import this fallback") -> NSItemProvider {
        let provider = NSItemProvider(object: fallback as NSString)
        provider.registerDataRepresentation(forTypeIdentifier: ExplorerTransfer.captureType, visibility: .all) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }

    /// Exercise real outgoing representations using synthetic originals and a
    /// private pasteboard. Nothing is written to the user's clipboard or apps.
    @MainActor private static func outgoingNativeSelection(_ store: CaptureStore, root: URL,
                                                           note: Capture, link: Capture, file: Capture, task: Capture) async throws {
        let files = FileManager.default
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j8ocAAAAASUVORK5CYII=")!
        let source = root.appendingPathComponent("Synthetic-drag-image.png")
        try png.write(to: source)
        let image = try await store.importFile(source)
        let managedImage = store.managedURL(for: image)!
        let provider = try ExplorerTransfer.itemProvider(for: image, store: store)
        try expect(provider.hasItemConformingToTypeIdentifier(UTType.image.identifier)
            && provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
            "Image drags advertise both native image content and their managed file URL")
        try files.removeItem(at: source)
        let imageData = try await load(provider, type: UTType.png.identifier)
        try expect(imageData == png, "A destination requesting image data receives exact original PNG bytes")
        let genericImageData = try await load(provider, type: UTType.image.identifier)
        try expect(genericImageData == png, "A destination requesting generic image content receives the original encoding")
        let imageFileBytes = try await readFileBytes(provider, type: UTType.png.identifier)
        try expect(imageFileBytes == png, "Adding image data preserves the existing file representation")
        let imageIDs = try await ExplorerTransfer.internalCaptureIDs(in: [provider])
        try expect(imageIDs == [image.id], "Public image content retains the same internal capture identity")

        let pasteboard = NSPasteboard(name: .init("DaBin.NativeOutgoingSelection.\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        let captures = [note, file, link, task, image]
        let writers = try ExplorerTransfer.pasteboardWriters(for: captures, store: store)
        try expect(writers.count == captures.count, "A mixed native drag publishes one writer per capture in selection order")
        for (capture, writer) in zip(captures, writers) {
            let data = writer.pasteboardPropertyList(forType: ExplorerTransfer.pasteboardType) as? Data
            try expect(data.flatMap { try? ExplorerTransfer.decodeIDs($0) } == [capture.id],
                "Each native drag item carries only its own capture identity")
        }
        let fileURL = store.managedURL(for: file)!
        let base = fileURL as NSURL
        let nativeTypes = base.writableTypes(for: pasteboard)
        try expect(Array(writers[1].writableTypes(for: pasteboard).prefix(nativeTypes.count)) == nativeTypes,
            "Managed-file writers preserve NSURL's native type priority and sandbox representations")
        for type in nativeTypes {
            let actualProperty = writers[1].pasteboardPropertyList(forType: type) as? NSObject
            let expectedProperty = base.pasteboardPropertyList(forType: type) as? NSObject
            try expect(actualProperty == expectedProperty,
                "Managed-file writers retain NSURL's property list for \(type.rawValue)")
            let expectedOptions = base.writingOptions(forType: type, pasteboard: pasteboard)
            try expect(writers[1].writingOptions?(forType: type, pasteboard: pasteboard) == expectedOptions,
                "Managed-file writers retain NSURL's writing options for \(type.rawValue)")
        }
        try expect(writers[4].writingOptions?(forType: .png, pasteboard: pasteboard) == .promised,
            "Native image bytes remain promised rather than loaded while starting a drag")
        try expect(pasteboard.writeObjects(writers), "macOS accepts the mixed native writers on an isolated pasteboard")
        let items = pasteboard.pasteboardItems ?? []
        try expect(items.count == captures.count, "macOS preserves distinct text, file, link, task and image drag items")
        try expect(items[0].string(forType: .string) == note.originalText,
            "Native text drags preserve exact original whitespace and multilingual words")
        try expect(items[1].string(forType: .fileURL) == fileURL.absoluteString,
            "File drags transfer a real managed file URL rather than a text-only path")
        try expect(items[2].string(forType: .URL) == link.originalURL
            && items[2].string(forType: .string) == link.originalURL,
            "Native link drags offer exact URL and plain-text representations")
        try expect(items[3].string(forType: .string) == task.originalText,
            "Native task drags publish readable original task text")
        try expect(items[4].data(forType: .png) == png,
            "A native image destination can request the promised exact PNG bytes")
        let fileReaders = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        try expect(Set(fileReaders) == Set([fileURL, managedImage]),
            "Finder-style NSURL readers retain both managed files in a mixed native drag")
        let publicWriters = try ExplorerTransfer.pasteboardWriters(for: captures, store: store, includeInternalReference: false)
        try expect(publicWriters.allSatisfy { !$0.writableTypes(for: pasteboard).contains(ExplorerTransfer.pasteboardType) },
            "Native public-only transfers omit internal identity while retaining their public representations")

        let disguised = try await store.importData(Data("This is not image content".utf8), filename: "Disguised.png")
        let disguisedProvider = try ExplorerTransfer.itemProvider(for: disguised, store: store)
        var rejectedNonImage = false
        do { _ = try await load(disguisedProvider, type: UTType.png.identifier) } catch { rejectedNonImage = true }
        try expect(rejectedNonImage, "An image filename does not fabricate image content for non-image bytes")

        try files.removeItem(at: managedImage)
        // Restore the historical source to prove that no fallback reads it.
        try png.write(to: source)
        var rejectedMissingImage = false
        do { _ = try await load(provider, type: UTType.png.identifier) } catch { rejectedMissingImage = true }
        try expect(rejectedMissingImage && writers[4].pasteboardPropertyList(forType: .png) == nil,
            "An original removed after drag start fails both provider and native promised-image materialization")
        try expect(writers[4].pasteboardPropertyList(forType: .fileURL) == nil,
            "A vanished native original does not publish a stale file URL on later request")
        let beforeFailure = pasteboard.pasteboardItems?.count
        var rejectedSelection = false
        do { _ = try ExplorerTransfer.pasteboardWriters(for: [note, image, task], store: store) }
        catch CaptureClipboardError.missingSavedOriginal { rejectedSelection = true }
        try expect(rejectedSelection && pasteboard.pasteboardItems?.count == beforeFailure,
            "An unavailable original rejects the complete selection before yielding writers or changing a pasteboard")
        try files.createSymbolicLink(at: managedImage, withDestinationURL: source)
        var rejectedSymlink = false
        do { _ = try await load(provider, type: UTType.png.identifier) } catch { rejectedSymlink = true }
        try expect(rejectedSymlink && writers[4].pasteboardPropertyList(forType: .png) == nil,
            "A substituted symbolic image path is never followed by outgoing drag materialization")
        try expect(try Data(contentsOf: source) == png, "Failed outgoing materialization leaves the historical source untouched")
        try files.removeItem(at: managedImage)
        try png.write(to: managedImage)
    }

    @MainActor static func main() async throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("DaBin-ExplorerTransferTests-\(UUID())", isDirectory: true)
        defer { try? files.removeItem(at: root) }
        let store = try CaptureStore(root: root.appendingPathComponent("archive"))
        let state = AppState(store: store, previews: PreviewService(store: store),
                             reminders: ReminderService(store: store, client: ExplorerTransferReminderClient()))
        let controller = ExplorerCaptureController(state: state)
        var results: [([UUID], String?)] = []
        controller.onResult = { captures, project in results.append((captures.map(\.id), project)) }

        let text = "  Client feedback — שלום\nKeep every line.  "
        let note = try store.capture(text: text)[0]
        note.comment = "Follow up with the client"
        try store.setOrganization(note, pinned: true, projectName: "Client A")
        let noteProvider = try ExplorerTransfer.itemProvider(for: note, store: store)
        try expect(ExplorerTransfer.containsInternalReference(noteProvider), "Outgoing captures carry an internal identity")
        let noteIDs = try await ExplorerTransfer.internalCaptureIDs(in: [noteProvider, noteProvider])
        try expect(noteIDs == [note.id], "Repeated providers resolve one distinct capture identity")
        let noteBytes = try await load(noteProvider, type: UTType.utf8PlainText.identifier)
        try expect(String(data: noteBytes, encoding: .utf8) == text, "External text drops preserve exact whitespace and multilingual content")
        let unmarked = NSItemProvider(object: "External selected text" as NSString)
        let noIdentity = try await ExplorerTransfer.internalCaptureIDs(in: [unmarked])
        try expect(noIdentity == nil, "External providers are clearly distinct from internal references")

        let link = try store.capture(text: "https://example.com/brief?q=review#part")[0]
        let linkProvider = try ExplorerTransfer.itemProvider(for: link, store: store)
        try expect(linkProvider.hasItemConformingToTypeIdentifier(UTType.url.identifier)
                   && linkProvider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   "Links expose both URL and plain text for native apps and browsers")
        let linkBytes = try await load(linkProvider, type: UTType.utf8PlainText.identifier)
        try expect(String(data: linkBytes, encoding: .utf8) == link.originalURL, "External link text preserves its query and fragment")

        let source = root.appendingPathComponent("Proposal.pdf")
        let original = Data("A saved document fixture".utf8)
        try original.write(to: source)
        let file = try await store.importFile(source)
        let fileProvider = try ExplorerTransfer.itemProvider(for: file, store: store)
        try expect(fileProvider.suggestedName == "Proposal.pdf", "Outgoing files preserve their recognizable filename")
        try expect(fileProvider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier), "Native file drops expose a file URL to Finder and browser upload targets")
        try files.removeItem(at: source)
        let transferred = try await readFileBytes(fileProvider, type: UTType.pdf.identifier)
        try expect(transferred == original, "File drops use DaBin's saved original after the external source disappears")

        let daily = root.appendingPathComponent("2026-09-30 - Captures and Links.md")
        let dailyBytes = Data("# 30 September 2026\n\nA daily capture and link record.\n".utf8)
        try dailyBytes.write(to: daily)
        let dailyProvider = try ExplorerTransfer.documentProvider(url: daily)
        try expect(!ExplorerTransfer.containsInternalReference(dailyProvider), "Generated daily documents transfer as files rather than fake capture IDs")
        let markdown = UTType(filenameExtension: "md") ?? .data
        let dailyTransferred = try await readFileBytes(dailyProvider, type: markdown.identifier)
        try expect(dailyTransferred == dailyBytes, "The actual UTF-8 daily document is transferable byte-for-byte")

        let task = try store.createTask(text: "Send the revised proposal")
        let taskProvider = try ExplorerTransfer.itemProvider(for: task, store: store)
        let taskBytes = try await load(taskProvider, type: UTType.utf8PlainText.identifier)
        try expect(String(data: taskBytes, encoding: .utf8) == task.originalText, "A task has a readable text representation outside DaBin")
        try await outgoingNativeSelection(store, root: root, note: note, link: link, file: file, task: task)

        let beforeMove = store.captures.count
        let receiptDate = note.capturedAt
        try expect(controller.receive([noteProvider, noteProvider], project: "Client B"), "An internal project drop is accepted")
        try await waitForIdle(controller)
        try expect(store.captures.count == beforeMove && note.projectName == "Client B", "Internal dragging moves the existing capture without importing a duplicate")
        try expect(note.isPinned && note.comment == "Follow up with the client" && note.capturedAt == receiptDate && note.originalText == text,
                   "Project transfer retains original content, receipt date, pin, and comment")
        try expect(results.last?.0 == [note.id] && results.last?.1 == "Client B", "Transfer reports the original destination for selection-safe UI updates")
        try expect(controller.canUndoMove, "A project move exposes Undo")
        controller.undoLastMove()
        try expect(note.projectName == "Client A" && !controller.canUndoMove, "Undo returns the capture to its previous project")

        try expect(controller.receive([noteProvider], project: "Client B"), "Another internal drop begins")
        try await waitForIdle(controller)
        try store.setOrganization(note, pinned: true, projectName: "Client C")
        controller.undoLastMove()
        try expect(note.projectName == "Client C" && state.status?.severity == .warning,
                   "Undo never overwrites a later project change")

        let malformed = identityProvider(Data("not a UUID payload".utf8))
        do {
            _ = try await ExplorerTransfer.internalCaptureIDs(in: [malformed])
            try expect(false, "Malformed internal references must throw")
        } catch ExplorerTransferError.invalidReference { }
        let countBeforeInvalid = store.captures.count
        try expect(controller.receive([malformed], project: "Client A"), "Malformed identity is handled as a completed transfer error")
        try await waitForIdle(controller)
        try expect(store.captures.count == countBeforeInvalid && state.status?.severity == .error,
                   "An invalid internal drag never silently imports its public fallback")

        let absent = identityProvider(try JSONEncoder().encode([UUID()]))
        try expect(controller.receive([noteProvider, absent], project: "Unsafe destination"), "Stale identity batch reaches the validation boundary")
        try await waitForIdle(controller)
        try expect(note.projectName == "Client C" && store.captures.count == countBeforeInvalid,
                   "Every internal ID is validated before any capture in that reference set moves")

        let delayed = NSItemProvider()
        delayed.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all) { completion in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { completion(Data("Slow browser selection".utf8), nil) }
            return nil
        }
        try expect(controller.receive([delayed], project: "Original destination"), "Delayed external intake starts")
        try expect(!controller.receive([unmarked], project: "Other"), "A second intake cannot overlap the active Explorer import")
        state.libraryProject = "Changed while importing"
        try await waitForIdle(controller)
        let imported = store.captures.first { $0.originalText == "Slow browser selection" }
        try expect(imported?.projectName == "Original destination" && results.last?.1 == "Original destination",
                   "Asynchronous intake keeps the destination chosen before navigation changed")
        try expect(state.workspace.shelfCaptureIDs.isEmpty, "Explorer intake does not secretly add shelf membership")

        let pb = NSPasteboard(name: .init("DaBin.ExplorerTransferTests.\(UUID())"))
        defer { pb.releaseGlobally() }
        let clipItem = NSPasteboardItem()
        clipItem.setString("Normal copied text", forType: .string)
        pb.writeObjects([clipItem])
        controller.paste(project: "Paste destination", from: pb)
        try await waitForIdle(controller)
        try expect(store.captures.contains { $0.originalText == "Normal copied text" && $0.projectName == "Paste destination" },
                   "Normal clipboard paste saves a fresh capture in the explicit project")
        pb.clearContents()
        let badItem = NSPasteboardItem()
        badItem.setData(Data("broken".utf8), forType: ExplorerTransfer.pasteboardType)
        badItem.setString("Never reimport marked fallback", forType: .string)
        pb.writeObjects([badItem])
        let beforeBadPaste = store.captures.count
        controller.paste(project: nil, from: pb)
        try await waitForIdle(controller)
        try expect(store.captures.count == beforeBadPaste && state.status?.severity == .error,
                   "Invalid identity on a native pasteboard also cannot fall through to text import")

        let attached = try store.capture(text: "Supporting capture")[0]
        try store.attachCapture(attached, to: task)
        let attachmentProvider = try ExplorerTransfer.itemProvider(for: attached, store: store)
        try expect(controller.receive([attachmentProvider], project: "Different project"), "Attachment project drop is handled explicitly")
        try await waitForIdle(controller)
        try expect(attached.parentTaskID == task.id && state.status?.severity == .error,
                   "An attachment cannot be silently separated from its task by a project drop")

        let independentFile = try await store.importData(Data("Task reference bytes".utf8), filename: "Reference.txt")
        let existingFileCount = store.captures.count
        let referenceProvider = try ExplorerTransfer.itemProvider(for: independentFile, store: store)
        try expect(controller.receive([referenceProvider, referenceProvider], attachingTo: task), "An Explorer file can be dropped onto a task")
        try await waitForIdle(controller)
        try expect(independentFile.parentTaskID == task.id && store.captures.count == existingFileCount,
                   "Task drop attaches the existing capture once without a duplicate receipt")
        try expect(store.managedURL(for: independentFile) != nil
                   && (try Data(contentsOf: store.managedURL(for: independentFile)!)) == Data("Task reference bytes".utf8),
                   "Attaching an existing capture retains readable managed file bytes")
        try expect(controller.receive([referenceProvider], attachingTo: task), "Repeated drop onto the same task is accepted")
        try await waitForIdle(controller)
        try expect(store.captures.count == existingFileCount && state.status?.severity == .success,
                   "Re-dropping the same attachment is an idempotent reference operation")
        try expect(controller.receive([malformed], attachingTo: task), "Malformed task drops are handled")
        try await waitForIdle(controller)
        try expect(store.captures.count == existingFileCount && state.status?.severity == .error,
                   "Invalid internal task drops never import fallback text")
        let anotherTask = try store.createTask(text: "A different task")
        try expect(controller.receive([referenceProvider], attachingTo: anotherTask), "Moving an existing attachment is explicitly evaluated")
        try await waitForIdle(controller)
        try expect(independentFile.parentTaskID == task.id && state.status?.severity == .error,
                   "Cross-task drops cannot silently detach an existing attachment")
        try expect(controller.receive([taskProvider], attachingTo: anotherTask), "Nested task drop reaches the model's validation")
        try await waitForIdle(controller)
        try expect(task.parentTaskID == nil && state.status?.severity == .error, "Task-to-task nesting remains unsupported with clear feedback")

        try store.moveToTrash(link)
        do {
            _ = try ExplorerTransfer.itemProvider(for: link, store: store)
            try expect(false, "Trashed items cannot start outgoing drags")
        } catch ExplorerTransferError.unavailableCapture { }
        try expect(controller.receive([linkProvider], project: "Client A"), "A drag started before deletion is validated on arrival")
        try await waitForIdle(controller)
        try expect(state.status?.severity == .error && !store.captures.contains { $0.id == link.id },
                   "A stale drag cannot restore or duplicate a deleted capture")

        let managed = store.managedURL(for: file)!
        try files.removeItem(at: managed)
        do {
            _ = try ExplorerTransfer.itemProvider(for: file, store: store)
            try expect(false, "A missing managed original must not publish a drag")
        } catch CaptureClipboardError.missingSavedOriginal { }
        var failedAfterDeletion = false
        do { _ = try await readFileBytes(fileProvider, type: UTType.pdf.identifier) }
        catch { failedAfterDeletion = true }
        try expect(failedAfterDeletion && !files.fileExists(atPath: managed.path),
                   "A file deleted after dragging starts must fail materialization without fabricating a replacement")
        try files.removeItem(at: daily)
        do {
            _ = try ExplorerTransfer.documentProvider(url: daily)
            try expect(false, "Missing daily records report failure")
        } catch ExplorerTransferError.missingDocument { }

        let stuck = NSItemProvider()
        stuck.registerDataRepresentation(forTypeIdentifier: ExplorerTransfer.captureType, visibility: .all) { _ in nil }
        let started = Date()
        do {
            _ = try await ExplorerTransfer.internalCaptureIDs(in: [stuck], timeout: 0.03)
            try expect(false, "A nonresponding internal provider must time out")
        } catch ExplorerTransferError.timedOut {
            try expect(Date().timeIntervalSince(started) < 1, "Broken internal promises have a bounded wait")
        }
        try await sharedInputLifecycle(root.appendingPathComponent("Shared input lifecycle"))
        try await undoFailureRetry(root.appendingPathComponent("Undo failure retry"))
        print("PASS: \(checks) Explorer transfer checks; native representations, projects, preservation, Undo, asynchronous destinations and failures.")
    }
}
