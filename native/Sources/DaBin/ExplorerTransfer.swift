import AppKit
import Combine
import ImageIO
import UniformTypeIdentifiers

enum ExplorerTransferError: LocalizedError, Equatable {
    case invalidReference, unavailableCapture, timedOut, cancelled
    case missingDocument(String)
    var errorDescription: String? {
        switch self {
        case .invalidReference: return "This DaBin drag contains an unreadable capture reference. Drag the item again."
        case .unavailableCapture: return "This capture is no longer in the current DaBin archive."
        case .timedOut: return "The dragged capture did not respond in time. Please try again."
        case .cancelled: return "The transfer was cancelled."
        case .missingDocument(let name): return "The saved file \(name) is unavailable."
        }
    }
}

/// Native representations remain useful outside DaBin. Its additional identity
/// representation is only a reference: destinations must resolve it in the live
/// store before making changes, and must not import its fallback on a bad ID.
enum ExplorerTransfer {
    static let captureType = "com.dabin.capture-id"
    static let pasteboardType = NSPasteboard.PasteboardType(captureType)
    static let acceptedTypes = [captureType, UTType.fileURL.identifier, UTType.url.identifier,
                                UTType.plainText.identifier, UTType.image.identifier, UTType.data.identifier]
    static let acceptedTypeIdentifiers = acceptedTypes

    /// One native drag item per capture, in the caller's selection order. The
    /// original NSURL writer is retained for file drags, including its sandbox
    /// representations; a string containing the path is never a substitute.
    /// Validate the entire selection before handing any writers to AppKit.
    @MainActor
    static func pasteboardWriters(for captures: [Capture], store: CaptureStore,
                                 includeInternalReference: Bool = true) throws -> [NSPasteboardWriting] {
        let current = Dictionary(uniqueKeysWithValues: store.captures.map { ($0.id, $0) })
        guard Set(captures.map(\.id)).count == captures.count,
              captures.allSatisfy({ capture in
                  capture.deletedAt == nil && current[capture.id] === capture
              }) else {
            throw ExplorerTransferError.unavailableCapture
        }
        let payload = try CaptureClipboardService(writer: { _ in true }).payload(for: captures, managedURL: store.managedURL(for:))
        return try zip(captures, payload.items).map { capture, item in
            let base: NSPasteboardWriting
            var image: LazyImageRepresentation?
            var fileURL: URL?
            switch item {
            case .text(let text): base = text as NSString
            case .webURL(let value):
                guard let url = URL(string: value), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
                    throw CaptureClipboardError.noContent
                }
                let item = NSPasteboardItem()
                item.setString(value, forType: .URL)
                item.setString(value, forType: .string)
                base = item
            case .file(let url):
                do { _ = try freshRegularFile(url) }
                catch { throw CaptureClipboardError.missingSavedOriginal(capture.originalFilename ?? capture.title) }
                base = url as NSURL
                fileURL = url
                image = LazyImageRepresentation(url: url)
            }
            let identity = includeInternalReference ? try JSONEncoder().encode([capture.id]) : nil
            return NativeCaptureWriter(base: base, identity: identity, image: image, fileURL: fileURL)
        }
    }

    @MainActor
    static func itemProvider(for capture: Capture, store: CaptureStore, includeInternalReference: Bool = true) throws -> NSItemProvider {
        guard capture.deletedAt == nil, store.captures.contains(where: { $0 === capture }) else {
            throw ExplorerTransferError.unavailableCapture
        }
        let provider: NSItemProvider
        switch capture.kind {
        case .image, .video, .pdf, .document, .ai, .file:
            guard let url = store.managedURL(for: capture) else {
                throw CaptureClipboardError.missingSavedOriginal(capture.originalFilename ?? capture.title)
            }
            provider = try documentProvider(url: url)
        case .link:
            guard let raw = capture.originalURL ?? capture.originalText, let url = URL(string: raw),
                  ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
                throw CaptureClipboardError.noContent
            }
            provider = NSItemProvider(object: url as NSURL)
            registerText(raw, on: provider)
        case .text, .task:
            let text = WorkspaceQuery.plainText(capture) ?? capture.title
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CaptureClipboardError.noContent
            }
            provider = NSItemProvider(object: text as NSString)
        }
        provider.suggestedName = capture.originalFilename ?? capture.title
        if includeInternalReference {
            let identity = try JSONEncoder().encode([capture.id])
            provider.registerDataRepresentation(forTypeIdentifier: captureType, visibility: .ownProcess) { completion in
                completion(identity, nil)
                return nil
            }
        }
        return provider
    }

    /// Used for generated daily Markdown and saved originals. Never fabricates a
    /// placeholder file or falls back to the source application's original path.
    static func documentProvider(url: URL) throws -> NSItemProvider {
        do { _ = try freshRegularFile(url) }
        catch { throw ExplorerTransferError.missingDocument(url.lastPathComponent) }
        let provider = NSItemProvider(object: url as NSURL)
        provider.suggestedName = url.lastPathComponent
        let type = UTType(filenameExtension: url.pathExtension) ?? .data
        provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all) { completion in
            do {
                let current = try freshRegularFile(url)
                completion(current, false, nil)
            } catch { completion(nil, false, ExplorerTransferError.missingDocument(url.lastPathComponent)) }
            return nil
        }
        if let image = LazyImageRepresentation(url: url) {
            // Registering a drag performs no image read or decoding. Destination
            // apps request the exact encoded original only when accepting it.
            provider.registerDataRepresentation(forTypeIdentifier: image.type.identifier, visibility: .all) { completion in
                DispatchQueue.global(qos: .utility).async {
                    do { completion(try image.read(), nil) }
                    catch { completion(nil, error) }
                }
                return nil
            }
        }
        return provider
    }

    /// A retained URL can cache resource values from drag start. Every promised
    /// read checks the current directory entry, so a replaced symbolic link is
    /// rejected rather than followed using a stale regular-file result.
    private static func freshRegularFile(_ url: URL) throws -> URL {
        var current = url
        current.removeAllCachedResourceValues()
        let attributes = try FileManager.default.attributesOfItem(atPath: current.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw ExplorerTransferError.missingDocument(current.lastPathComponent)
        }
        try OriginalFileStorage.validateRegularFile(current)
        return current
    }

    private struct LazyImageRepresentation: Sendable {
        let url: URL
        let type: UTType
        init?(url: URL) {
            guard let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image) else { return nil }
            self.url = url; self.type = type
        }
        func read() throws -> Data {
            do {
                let current = try ExplorerTransfer.freshRegularFile(url)
                let data = try Data(contentsOf: current, options: .mappedIfSafe)
                guard let source = CGImageSourceCreateWithData(data as CFData,
                    [kCGImageSourceShouldCache: false] as CFDictionary),
                      CGImageSourceGetCount(source) > 0,
                      CGImageSourceGetStatus(source) == .statusComplete,
                      let identifier = CGImageSourceGetType(source),
                      let actual = UTType(identifier as String), actual.conforms(to: type) else {
                    throw ExplorerTransferError.missingDocument(url.lastPathComponent)
                }
                return data
            } catch { throw ExplorerTransferError.missingDocument(url.lastPathComponent) }
        }
    }

    /// Additional native representations surround rather than replace Apple's
    /// URL/string writers. Image data is promised and materialized only when a
    /// receiving application asks for it. AppKit's callback is synchronous and
    /// waits for its requested data; no image bytes are read at drag start.
    private final class NativeCaptureWriter: NSObject, NSPasteboardWriting {
        private final class ImageReadResult: @unchecked Sendable {
            private let lock = NSLock()
            private var data: Data?
            func store(_ value: Data?) { lock.lock(); data = value; lock.unlock() }
            func value() -> Data? { lock.lock(); defer { lock.unlock() }; return data }
        }
        private let base: NSPasteboardWriting
        private let identity: Data?
        private let image: LazyImageRepresentation?
        private let fileURL: URL?
        private static let imageQueue = DispatchQueue(label: "com.dabin.drag-image", qos: .utility)
        init(base: NSPasteboardWriting, identity: Data?, image: LazyImageRepresentation?, fileURL: URL?) {
            self.base = base; self.identity = identity; self.image = image; self.fileURL = fileURL
        }
        func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
            var types = base.writableTypes(for: pasteboard)
            if let image {
                let type = NSPasteboard.PasteboardType(image.type.identifier)
                if !types.contains(type) { types.append(type) }
            }
            if identity != nil, !types.contains(ExplorerTransfer.pasteboardType) { types.append(ExplorerTransfer.pasteboardType) }
            return types
        }
        func writingOptions(forType type: NSPasteboard.PasteboardType, pasteboard: NSPasteboard) -> NSPasteboard.WritingOptions {
            if identity != nil, type == ExplorerTransfer.pasteboardType { return [] }
            if let image, type.rawValue == image.type.identifier { return .promised }
            return base.writingOptions?(forType: type, pasteboard: pasteboard)
                ?? (base.writableTypes(for: pasteboard).first == type ? [] : .promised)
        }
        func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
            if type == ExplorerTransfer.pasteboardType { return identity }
            if let image, type.rawValue == image.type.identifier {
                let result = ImageReadResult()
                let finished = DispatchSemaphore(value: 0)
                Self.imageQueue.async { result.store(try? image.read()); finished.signal() }
                finished.wait()
                return result.value()
            }
            if let fileURL { do { _ = try ExplorerTransfer.freshRegularFile(fileURL) } catch { return nil } }
            return base.pasteboardPropertyList(forType: type)
        }
    }

    private static func registerText(_ value: String, on provider: NSItemProvider) {
        provider.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all) { completion in
            completion(Data(value.utf8), nil)
            return nil
        }
    }

    static func containsInternalReference(_ provider: NSItemProvider) -> Bool {
        provider.registeredTypeIdentifiers.contains(captureType)
    }

    /// nil means an external transfer. An advertised but broken identity is an
    /// error, never permission to silently reimport its public file/text fallback.
    static func internalCaptureIDs(in providers: [NSItemProvider], timeout: TimeInterval = 10) async throws -> [UUID]? {
        let marked = providers.filter(containsInternalReference)
        guard !marked.isEmpty else { return nil }
        guard marked.count <= 1_000 else { throw ExplorerTransferError.invalidReference }
        var unique = Set<UUID>()
        var result: [UUID] = []
        for provider in marked {
            let data = try await readIdentity(provider, timeout: timeout)
            for id in try decodeIDs(data) where unique.insert(id).inserted { result.append(id) }
            guard result.count <= 1_000 else { throw ExplorerTransferError.invalidReference }
        }
        return result
    }

    static func decodeIDs(_ data: Data) throws -> [UUID] {
        guard data.count <= 64_000, let ids = try? JSONDecoder().decode([UUID].self, from: data),
              !ids.isEmpty, ids.count <= 1_000 else { throw ExplorerTransferError.invalidReference }
        return ids
    }

    @MainActor
    static func resolve(_ ids: [UUID], store: CaptureStore) throws -> [Capture] {
        var seen = Set<UUID>()
        let current = Dictionary(uniqueKeysWithValues: store.captures.map { ($0.id, $0) })
        return try ids.filter { seen.insert($0).inserted }.map { id in
            guard let capture = current[id], capture.deletedAt == nil else { throw ExplorerTransferError.unavailableCapture }
            return capture
        }
    }

    private final class IdentityGate: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Data, Error>?
        init(_ continuation: CheckedContinuation<Data, Error>, timeout: TimeInterval) {
            self.continuation = continuation
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + max(0.01, timeout)) { [self] in
                finish(.failure(ExplorerTransferError.timedOut))
            }
        }
        func finish(_ result: Result<Data, Error>) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(with: result)
        }
    }

    private static func readIdentity(_ provider: NSItemProvider, timeout: TimeInterval) async throws -> Data {
        try Task.checkCancellation()
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            let gate = IdentityGate(continuation, timeout: timeout)
            provider.loadDataRepresentation(forTypeIdentifier: captureType) { data, error in
                if let error { gate.finish(.failure(error)) }
                else if let data { gate.finish(.success(data)) }
                else { gate.finish(.failure(ExplorerTransferError.invalidReference)) }
            }
        }
        try Task.checkCancellation()
        return data
    }
}

/// Project-scoped intake reuses the ordinary import pipeline. The destination
/// is captured before asynchronous materialization, so navigating elsewhere
/// cannot silently retarget a slow Finder/browser drop.
@MainActor
final class ExplorerCaptureController: ObservableObject {
    var isBusy: Bool { !operations.isEmpty || input.isBusy }
    private var operations = Set<UUID>()
    @Published private(set) var canUndoMove = false
    var onResult: (([Capture], String?) -> Void)?
    private weak var state: AppState?
    private let input: InputService
    private struct Move {
        let id: UUID
        let before: String?
        let after: String?
        let revision: Date
    }
    private var undoMoves: [Move] = []

    init(state: AppState, input suppliedInput: InputService? = nil) {
        self.state = state
        input = suppliedInput ?? InputService(store: state.store)
        // A shared input already notifies AppState. Retain its observer rather
        // than replacing the quit/lifecycle notification pipeline.
        let previous = input.onBusy
        input.onBusy = { [weak self] busy in
            previous?(busy)
            self?.objectWillChange.send()
        }
    }

    private func beginOperation() -> UUID {
        let id = UUID()
        operations.insert(id)
        objectWillChange.send()
        return id
    }

    private func finishOperation(_ id: UUID) {
        operations.remove(id)
        objectWillChange.send()
    }

    private func resumeCompletion(_ id: UUID) {
        // File promises can report again after their original timeout. Protect
        // that callback's metadata work without releasing any newer operation.
        operations.insert(id)
        objectWillChange.send()
    }

    func paste(project: String?, from pasteboard: NSPasteboard = .general) {
        guard let state, !isBusy, !state.isArchiveOperationRunning else { return }
        // Normal Copy/Paste intentionally creates a new capture; only an
        // explicit internal drag uses identities to move existing records.
        let operation = beginOperation()
        let items = pasteboard.pasteboardItems ?? []
        if items.contains(where: { $0.types.contains(ExplorerTransfer.pasteboardType) }) {
            var ids: [UUID] = []
            var failures: [String] = []
            let external = items.filter { !$0.types.contains(ExplorerTransfer.pasteboardType) }
            for item in items where item.types.contains(ExplorerTransfer.pasteboardType) {
                do {
                    guard let data = item.data(forType: ExplorerTransfer.pasteboardType) else {
                        throw ExplorerTransferError.invalidReference
                    }
                    ids += try ExplorerTransfer.decodeIDs(data)
                } catch { failures.append(error.localizedDescription) }
            }
            let moved = move(ids, project: project, failures: &failures)
            guard !external.isEmpty else { finish([], moved: moved, failures: failures, project: project, operation: operation); return }
            // Keep the source NSURL readers alive for Finder sandbox grants.
            let transfer = InputFileURLTransfer.consume(from: pasteboard)
            let filtered = NSPasteboard(name: .init("DaBin.ExplorerTransfer.\(UUID().uuidString)"))
            let copies = external.map { item in
                let copy = NSPasteboardItem()
                for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
                return copy
            }
            guard filtered.writeObjects(copies) else {
                filtered.releaseGlobally()
                finish([], moved: moved, failures: failures + ["The other dragged items could not be read."], project: project, operation: operation)
                return
            }
            let transferFailures = failures
            input.receive(filtered, fileURLTransfer: transfer, completion: { [self] captures, importFailures in
                filtered.releaseGlobally()
                finish(captures, moved: moved, failures: transferFailures + importFailures, project: project, operation: operation)
            })
            return
        }
        input.receive(pasteboard, completion: { [self] captures, failures in
            finish(captures, moved: [], failures: failures, project: project, operation: operation)
        })
    }

    @discardableResult
    func receive(_ providers: [NSItemProvider], project: String?) -> Bool {
        guard let state, !isBusy, !state.isArchiveOperationRunning, !providers.isEmpty else { return false }
        guard providers.count <= 1_000 else {
            state.reportFailure("Choose at most 1,000 items for one transfer.")
            return false
        }
        let operation = beginOperation()
        let receivedAt = Date()
        Task { @MainActor [self, state] in
            var failures: [String] = []
            var references: [UUID] = []
            let external = providers.filter { !ExplorerTransfer.containsInternalReference($0) }
            for provider in providers where ExplorerTransfer.containsInternalReference(provider) {
                do { references += try await ExplorerTransfer.internalCaptureIDs(in: [provider]) ?? [] }
                catch { failures.append(error.localizedDescription) }
            }
            guard !state.isArchiveOperationRunning else {
                finish([], moved: [], failures: ["Wait until the archive operation finishes, then try again."], project: project, operation: operation)
                return
            }
            let moved = move(references, project: project, failures: &failures)
            guard !external.isEmpty else { finish([], moved: moved, failures: failures, project: project, operation: operation); return }
            let transferFailures = failures
            input.receiveProviders(external, at: receivedAt) { [self] captures, importFailures in
                finish(captures, moved: moved, failures: transferFailures + importFailures, project: project, operation: operation)
            }
        }
        return true
    }

    func chooseFiles(project: String?) {
        guard let state, !isBusy, !state.isArchiveOperationRunning else { return }
        let picker = NSOpenPanel()
        picker.title = "Add files to \(project ?? "Unfiled")"
        picker.message = "DaBin saves a local copy. Your original files stay where they are."
        picker.prompt = "Add files"
        picker.canChooseDirectories = false
        picker.allowsMultipleSelection = true
        guard picker.runModal() == .OK else { return }
        let urls = picker.urls
        let timestamp = Date()
        let operation = beginOperation()
        Task { @MainActor [self, state] in
            var captures: [Capture] = []
            var failures: [String] = []
            for url in urls {
                do { captures.append(try await state.store.importFile(url, at: timestamp)) }
                catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            }
            finish(captures, moved: [], failures: failures, project: project, operation: operation)
        }
    }

    /// Existing captures are attached by reference. A mixed external drop still
    /// uses the import pipeline, while a bad internal identity never becomes a
    /// second copy through its file/text representation.
    @discardableResult
    func receive(_ providers: [NSItemProvider], attachingTo task: Capture) -> Bool {
        guard let state, !isBusy, !state.isArchiveOperationRunning, !providers.isEmpty,
              providers.count <= 1_000, task.isTask,
              state.store.captures.contains(where: { $0 === task }) else { return false }
        let operation = beginOperation()
        let receivedAt = Date()
        Task { @MainActor [self, state] in
            var failures: [String] = []
            var ids: [UUID] = []
            for provider in providers where ExplorerTransfer.containsInternalReference(provider) {
                do { ids += try await ExplorerTransfer.internalCaptureIDs(in: [provider]) ?? [] }
                catch { failures.append(error.localizedDescription) }
            }
            var attached: [Capture] = []
            do {
                guard !state.isArchiveOperationRunning else {
                    throw CaptureStoreError.invalidOriginal("Wait until the archive operation finishes, then try again.")
                }
                guard task.isTask, state.store.captures.contains(where: { $0 === task }) else {
                    throw CaptureStoreError.invalidOriginal("The task is no longer available for these attachments.")
                }
                guard ids.count <= 1_000 else { throw ExplorerTransferError.invalidReference }
                let captures = try ExplorerTransfer.resolve(ids, store: state.store)
                for capture in captures {
                    do {
                        // Re-dropping an attachment onto its own task is a no-op.
                        if capture.parentTaskID != task.id { try state.store.attachCapture(capture, to: task) }
                        attached.append(capture)
                    } catch { failures.append("\(capture.title): \(error.localizedDescription)") }
                }
            } catch { failures.append(error.localizedDescription) }
            let external = providers.filter { !ExplorerTransfer.containsInternalReference($0) }
            guard !external.isEmpty, !state.isArchiveOperationRunning else {
                finishAttachments([], attached: attached, failures: failures, operation: operation)
                return
            }
            let transferFailures = failures
            let referenced = attached
            input.receiveProviders(external, attachingTo: task, at: receivedAt) { [self] captures, importFailures in
                finishAttachments(captures, attached: referenced, failures: transferFailures + importFailures, operation: operation)
            }
        }
        return true
    }

    private func finishAttachments(_ captures: [Capture], attached: [Capture], failures: [String], operation: UUID) {
        resumeCompletion(operation)
        defer { finishOperation(operation) }
        guard let state else { return }
        state.didCapture(captures)
        let count = captures.count + attached.count
        if failures.isEmpty {
            state.status = AppStatusMessage(text: "\(count) \(count == 1 ? "item" : "items") attached to the task.", severity: .success)
        } else {
            state.status = AppStatusMessage(text: (count == 0 ? "Couldn’t attach these items. " : "Attached \(count); some items failed. ") + failures.joined(separator: "\n"),
                                            severity: count == 0 ? .error : .warning)
        }
    }

    private func move(_ ids: [UUID], project: String?, failures: inout [String]) -> [Capture] {
        guard let state else { return [] }
        var moved: [Capture] = []
        var receipts: [Move] = []
        do {
            guard ids.count <= 1_000 else { throw ExplorerTransferError.invalidReference }
            // Validate the complete reference set before changing any record.
            let captures = try ExplorerTransfer.resolve(ids, store: state.store)
            for capture in captures {
                do {
                    guard capture.parentTaskID == nil else {
                        throw CaptureStoreError.invalidOriginal("Move this attachment’s task to change its project.")
                    }
                    let previous = capture.projectName
                    try state.store.setOrganization(capture, pinned: capture.isPinned, projectName: project)
                    moved.append(capture)
                    if previous != capture.projectName {
                        receipts.append(Move(id: capture.id, before: previous, after: capture.projectName, revision: capture.updatedAt))
                    }
                } catch { failures.append("\(capture.title): \(error.localizedDescription)") }
            }
        } catch { failures.append(error.localizedDescription) }
        if !receipts.isEmpty { undoMoves = receipts; canUndoMove = true }
        return moved
    }

    func undoLastMove() {
        guard let state, !isBusy, !state.isArchiveOperationRunning, !undoMoves.isEmpty else { return }
        var restored = 0
        var failures: [String] = []
        let moves = undoMoves
        var retryable: [Move] = []
        for change in moves {
            guard let capture = state.store.captures.first(where: { $0.id == change.id }),
                  capture.projectName == change.after, capture.updatedAt == change.revision, capture.parentTaskID == nil else {
                failures.append("An item changed since the move and was left as it is.")
                continue
            }
            do {
                try state.store.setOrganization(capture, pinned: capture.isPinned, projectName: change.before)
                restored += 1
            } catch {
                // A failed write rolls back the item. Keep its exact revision
                // receipt so the user can retry without undoing newer edits.
                retryable.append(change)
                failures.append(error.localizedDescription)
            }
        }
        undoMoves = retryable
        canUndoMove = !retryable.isEmpty
        state.status = AppStatusMessage(text: failures.isEmpty ? "Project move undone." :
            "Restored \(restored) items. " + failures.joined(separator: "\n"), severity: failures.isEmpty ? .success : .warning)
    }

    private func finish(_ captures: [Capture], moved: [Capture], failures: [String], project: String?, operation: UUID) {
        resumeCompletion(operation)
        defer { finishOperation(operation) }
        guard let state else { return }
        var errors = failures
        var assigned: [Capture] = []
        for capture in captures {
            do {
                try state.store.setOrganization(capture, pinned: capture.isPinned, projectName: project)
                assigned.append(capture)
            } catch { errors.append("\(capture.title) was saved in Unfiled, but could not be added to \(project ?? "Unfiled"): \(error.localizedDescription)") }
        }
        state.didCapture(captures)
        let affected = assigned + moved
        onResult?(affected, project)
        let destination = project ?? "Unfiled"
        let success = "\(captures.count) saved, \(moved.count) moved to \(destination)."
        if !errors.isEmpty {
            state.status = AppStatusMessage(text: (captures.isEmpty && moved.isEmpty ? "Couldn’t add these items. " : success + " ") + errors.joined(separator: "\n"),
                                            severity: captures.isEmpty && moved.isEmpty ? .error : .warning)
        } else if !affected.isEmpty {
            let message = captures.isEmpty ? "Moved \(moved.count) \(moved.count == 1 ? "item" : "items") to \(destination)." :
                moved.isEmpty ? "Saved \(captures.count) \(captures.count == 1 ? "item" : "items") to \(destination)." : success
            state.status = AppStatusMessage(text: message, severity: .success)
        }
    }
}
