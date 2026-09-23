import AppKit
import UniformTypeIdentifiers

/// Small adapter allows promised-file lifecycle tests without a live drag source.
protocol InputFilePromise {
    var fileNames: [String] { get }
    func receive(at destination: URL, operationQueue: OperationQueue,
                 reader: @escaping (URL, Error?) -> Void)
}

extension NSFilePromiseReceiver: InputFilePromise {
    func receive(at destination: URL, operationQueue: OperationQueue,
                 reader: @escaping (URL, Error?) -> Void) {
        receivePromisedFiles(atDestination: destination, options: [:], operationQueue: operationQueue, reader: reader)
    }
}

/// Holds the native NSURL pasteboard readers that consume App Sandbox file
/// transfer grants. The object stays alive until every asynchronous import
/// finishes; rebuilding file URLs from strings does not preserve Finder's
/// sandbox handoff.
@MainActor
final class InputFileURLTransfer {
    fileprivate let objects: [NSURL]

    init(retaining objects: [NSURL]) {
        self.objects = objects
    }

    static func consume(from pasteboard: NSPasteboard) -> InputFileURLTransfer {
        let values = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) ?? []
        return InputFileURLTransfer(retaining: values.compactMap { $0 as? NSURL })
    }

    fileprivate var urls: [URL] {
        objects.map { $0 as URL }
    }

    var retainedURLCount: Int { objects.count }
}

/// Reads the pasteboard only after an explicit Paste or accepted drop.
@MainActor
final class InputService {
    let store: CaptureStore
    var onBusy: ((Bool) -> Void)?
    var onResult: (([Capture], [String]) -> Void)?
    var isBusy: Bool { operations > 0 }
    private var operations = 0
    private let promiseTimeout: TimeInterval
    private let stagingRoot: URL
    private let promiseReader: (NSPasteboard) -> [InputFilePromise]
    private let promiseQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "DaBin.file-promises"
        queue.maxConcurrentOperationCount = 2
        return queue
    }()

    init(store: CaptureStore, promiseTimeout: TimeInterval = 60, stagingRoot: URL? = nil,
         promiseReader: ((NSPasteboard) -> [InputFilePromise])? = nil) {
        self.store = store
        self.promiseTimeout = promiseTimeout
        self.stagingRoot = stagingRoot ?? FileManager.default.temporaryDirectory
        self.promiseReader = promiseReader ?? { pasteboard in
            (pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver] ?? []).map { $0 as InputFilePromise }
        }
    }

    static var dragTypes: [NSPasteboard.PasteboardType] {
        // The generic data registration also covers original bytes supplied by
        // apps without a file URL (for example JPEG or HTML). AppKit matches
        // conforming UTIs; acceptance below still requires a savable format.
        let base: [NSPasteboard.PasteboardType] = [.fileURL, .URL, .string, .png, .tiff, .pdf, .rtf, .html,
                                                  .init(UTType.data.identifier)]
        return base + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType(rawValue: $0) }
    }

    /// Inspect only advertised types while hovering. Loading a lazy pasteboard
    /// representation or requesting a promised file belongs to the actual drop.
    static func canReceive(_ pasteboard: NSPasteboard) -> Bool {
        let direct: Set<NSPasteboard.PasteboardType> = [.fileURL, .URL, .string, .png, .tiff, .pdf, .rtf]
        let promises = Set(NSFilePromiseReceiver.readableDraggedTypes)
        return (pasteboard.types ?? []).contains { type in
            direct.contains(type) || promises.contains(type.rawValue) || originalDataType(type) != nil
        }
    }

    private static func originalDataType(_ pasteboardType: NSPasteboard.PasteboardType) -> UTType? {
        guard let type = UTType(pasteboardType.rawValue), type.conforms(to: .data),
              type.preferredFilenameExtension != nil else { return nil }
        return type
    }

    private enum Payload {
        case file(URL, CaptureSource?)
        case text(String, CaptureSource)
        case bytes(Data, String, CaptureSource)
        case failure(String)
    }

    /// WebKit exports the source page in a web archive's main resource. Only read
    /// these explicit fields; links inside text/RTF/HTML are not provenance.
    /// Format: WebKit Source/WebCore/loader/archive/cf/LegacyWebArchive.cpp.
    private static func exportedSource(from item: NSPasteboardItem) -> CaptureSource {
        guard let data = item.data(forType: .init("com.apple.webarchive")),
              let archive = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any],
              let main = archive["WebMainResource"] as? [String: Any],
              let raw = main["WebResourceURL"] as? String,
              !raw.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }),
              let url = URL(string: raw) else { return .unknown }
        if url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost",
           url.path.hasPrefix("/"), !url.path.contains("\0") {
            return CaptureSource(filePath: url.standardizedFileURL.path)
        }
        if ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
           let host = url.host, !host.isEmpty, url.user == nil, url.password == nil {
            return CaptureSource(url: url.absoluteString)
        }
        return .unknown
    }

    func paste() { receive(.general) }

    func receive(_ pasteboard: NSPasteboard, at receivedAt: Date = Date(), timeZone zone: TimeZone = .current,
                 receipt: CaptureReceiptContext = .manual,
                 fileURLTransfer suppliedFileURLTransfer: InputFileURLTransfer? = nil,
                 commitGuard: @escaping () -> Bool = { true },
                 completion: (([Capture], [String]) -> Void)? = nil) {
        let receivers = promiseReader(pasteboard)
        // AppKit's URL reader also consumes the sandbox transfer grants supplied by
        // Finder. Auto Capture supplies the transfer consumed from the original
        // system pasteboard before it creates its immutable private snapshot.
        let fileURLTransfer = suppliedFileURLTransfer ?? InputFileURLTransfer.consume(from: pasteboard)
        let transferredURLs = fileURLTransfer.urls
        let promiseTypes = Set(NSFilePromiseReceiver.readableDraggedTypes)
        let items = pasteboard.pasteboardItems ?? []
        var payloads: [Payload] = []
        for item in items {
            if !promiseTypes.isDisjoint(with: item.types.map(\.rawValue)), !receivers.isEmpty { continue }
            let source = Self.exportedSource(from: item)
            // One representation per item; equal content in two items remains two captures.
            if let string = item.string(forType: .fileURL), let url = URL(string: string), url.isFileURL {
                payloads.append(.file(transferredURLs.first(where: { $0.standardizedFileURL == url.standardizedFileURL }) ?? url, nil))
            } else if let bytes = item.data(forType: .png) {
                payloads.append(.bytes(bytes, "Pasted image.png", source))
            } else if let bytes = item.data(forType: .tiff) {
                payloads.append(.bytes(bytes, "Pasted image.tiff", source))
            } else if let bytes = item.data(forType: .pdf) {
                payloads.append(.bytes(bytes, "Pasted document.pdf", source))
            } else if let url = item.string(forType: .URL) {
                payloads.append(.text(url, source))
            } else if let string = item.string(forType: .string) {
                payloads.append(.text(string, source))
            } else if let rtf = item.data(forType: .rtf),
                      let text = try? NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil).string {
                payloads.append(.text(text, source))
            } else if let type = item.types.first(where: { Self.originalDataType($0) != nil }),
                      let data = item.data(forType: type) {
                let ext = Self.originalDataType(type)?.preferredFilenameExtension ?? "bin"
                payloads.append(.bytes(data, "Captured item.\(ext)", source))
            } else {
                payloads.append(.failure("This item did not provide a readable file, image, link or text representation."))
            }
        }
        if items.isEmpty, receivers.isEmpty { payloads.append(.failure("The clipboard has no readable content to capture.")) }
        let batch = InputBatch(date: receivedAt, zone: zone, receipt: receipt,
                               fileURLTransfer: fileURLTransfer, commitGuard: commitGuard,
                               remaining: (payloads.isEmpty ? 0 : 1) + receivers.count,
                               completion: completion)
        setBusy(1)
        if !payloads.isEmpty {
            Task { @MainActor in
                await importPayloads(payloads, into: batch)
                finishUnit(batch)
            }
        }
        for receiver in receivers { receivePromise(receiver, batch: batch) }
        // A malformed pasteboard must still terminate its busy state.
        if batch.remaining == 0 { complete(batch) }
    }

    private func setBusy(_ delta: Int) {
        let wasBusy = isBusy
        operations = max(0, operations + delta)
        if isBusy != wasBusy { onBusy?(isBusy) }
    }

    private func finishUnit(_ batch: InputBatch) {
        guard !batch.reported else { return }
        batch.remaining -= 1
        if batch.remaining == 0 { complete(batch) }
    }

    private func complete(_ batch: InputBatch) {
        guard !batch.reported else { return }
        batch.reported = true
        setBusy(-1)
        onResult?(batch.captures, batch.failures)
        batch.completion?(batch.captures, batch.failures)
    }

    private func importPayloads(_ payloads: [Payload], into batch: InputBatch) async {
        for payload in payloads {
            do {
                switch payload {
                case .text(let text, let source): batch.captures += try store.capture(text: text, at: batch.date, timeZone: batch.zone, source: source, receipt: batch.receipt, commitGuard: batch.commitGuard)
                case .file(let url, let source): batch.captures.append(try await store.importFile(url, at: batch.date, timeZone: batch.zone, source: source, receipt: batch.receipt, commitGuard: batch.commitGuard))
                case .bytes(let data, let filename, let source): batch.captures.append(try await store.importData(data, filename: filename, at: batch.date, timeZone: batch.zone, source: source, receipt: batch.receipt, commitGuard: batch.commitGuard))
                case .failure(let reason): batch.failures.append(reason)
                }
            } catch { batch.failures.append(error.localizedDescription) }
        }
    }

    private func receivePromise(_ receiver: InputFilePromise, batch: InputBatch) {
        let destination = stagingRoot.appendingPathComponent("DaBin-Promise-\(UUID().uuidString)", isDirectory: true)
        do { try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true) }
        catch { batch.failures.append(error.localizedDescription); finishUnit(batch); return }
        let work = InputPromiseWork(destination: destination, receiver: receiver)
        receiver.receive(at: destination, operationQueue: promiseQueue) { [weak self] url, error in
            // This is the coordinated reader callback. Make our own copy before it returns.
            let prepared: Result<URL, Error>
            if let error { prepared = .failure(error) }
            else {
                do {
                    let owned = destination.appendingPathComponent("Import-\(UUID().uuidString)", isDirectory: true)
                    try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: true)
                    let copy = owned.appendingPathComponent(url.lastPathComponent)
                    try FileManager.default.copyItem(at: url, to: copy)
                    prepared = .success(copy)
                } catch { prepared = .failure(error) }
            }
            Task { @MainActor in
                guard let self else {
                    if case .success(let url) = prepared { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
                    return
                }
                self.handlePromise(prepared, work: work, batch: batch)
            }
        }
        // Names are populated by receivePromisedFiles; fileTypes can contain one type for many files.
        work.expected = max(1, receiver.fileNames.count)
        work.timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(self?.promiseTimeout ?? 60))
            guard !Task.isCancelled, let self, !work.holdReleased else { return }
            let missing = max(0, work.expected - work.received)
            guard missing > 0 else { return }
            batch.failures.append("The source has not provided \(missing) promised \(missing == 1 ? "file" : "files") yet. Any files arriving later will still be saved under the original capture date.")
            work.holdReleased = true
            self.finishUnit(batch)
            // Keep staging while the source may still write. Last callback cleans it in full.
        }
    }

    private func handlePromise(_ prepared: Result<URL, Error>, work: InputPromiseWork, batch: InputBatch) {
        work.received += 1
        work.importing += 1
        let target: InputBatch
        if batch.reported {
            // A timed-out source may finish later. Report only new captures, never past successes.
            target = InputBatch(date: batch.date, zone: batch.zone, receipt: batch.receipt,
                                fileURLTransfer: batch.fileURLTransfer,
                                commitGuard: batch.commitGuard,
                                remaining: 1, completion: batch.completion)
            setBusy(1)
        } else {
            target = batch
            target.remaining += 1
        }
        if work.received >= work.expected, !work.holdReleased {
            work.holdReleased = true
            work.timeout?.cancel()
            work.timeout = nil
            finishUnit(batch)
        }
        Task { @MainActor in
            switch prepared {
            case .success(let url):
                // A promise delivers a new temporary file. Its staging location is
                // not the document's source and must never be shown as provenance.
                await importPayloads([.file(url, .unknown)], into: target)
                try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            case .failure(let error):
                target.failures.append("The source could not provide its promised file: \(error.localizedDescription)")
            }
            work.importing -= 1
            if work.received >= work.expected, work.importing == 0 {
                try? FileManager.default.removeItem(at: work.destination)
                work.receiver = nil
            }
            finishUnit(target)
        }
    }
}

@MainActor private final class InputBatch {
    let date: Date
    let zone: TimeZone
    let receipt: CaptureReceiptContext
    /// Retains the NSURL readers, and therefore Finder's sandbox transfer grant,
    /// through all asynchronous file imports in this batch.
    let fileURLTransfer: InputFileURLTransfer
    let commitGuard: () -> Bool
    var remaining: Int
    var captures: [Capture] = []
    var failures: [String] = []
    var reported = false
    let completion: (([Capture], [String]) -> Void)?
    init(date: Date, zone: TimeZone, receipt: CaptureReceiptContext = .manual,
         fileURLTransfer: InputFileURLTransfer,
         commitGuard: @escaping () -> Bool = { true }, remaining: Int,
         completion: (([Capture], [String]) -> Void)? = nil) {
        self.date = date; self.zone = zone; self.receipt = receipt
        self.fileURLTransfer = fileURLTransfer; self.commitGuard = commitGuard; self.remaining = remaining
        self.completion = completion
    }
}

@MainActor private final class InputPromiseWork {
    let destination: URL
    // Keep the native receiver alive through all callbacks, including a late completion.
    var receiver: InputFilePromise?
    var expected = 1
    var received = 0
    var importing = 0
    var holdReleased = false
    var timeout: Task<Void, Never>?
    init(destination: URL, receiver: InputFilePromise) {
        self.destination = destination; self.receiver = receiver
    }
}
