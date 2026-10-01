import AppKit
import Combine
import ImageIO
import PDFKit
import Vision

struct ContentIndexExtraction: Sendable, Equatable {
    enum Status: String, Sendable { case ready, unavailable }
    let text: String
    let status: Status
    let message: String?
    let canRetry: Bool

    static func ready(_ text: String, message: String? = nil) -> Self {
        .init(text: text, status: .ready, message: message, canRetry: false)
    }

    static func unavailable(_ message: String, canRetry: Bool = true) -> Self {
        .init(text: "", status: .unavailable, message: message, canRetry: canRetry)
    }
}

/// Builds a local text index from DaBin-owned originals. The service has no
/// network dependency; all extraction uses Apple frameworks on this Mac.
@MainActor
final class ContentIndexService: ObservableObject {
    typealias Extractor = @Sendable (URL, CaptureKind, String?) async -> ContentIndexExtraction

    static let currentVersion = 1
    private let store: CaptureStore
    private let extractor: Extractor
    private var queue: [IndexJob] = []
    private var running: [UUID: Task<Void, Never>] = [:]
    private var tokens: [UUID: UUID] = [:]
    private var targets: [UUID: Capture] = [:]
    private var cancelling = Set<UUID>()
    private var hasShutDown = false
    private let maximumConcurrentJobs = 1
    @Published private(set) var pendingCount = 0
    var isBusy: Bool { pendingCount > 0 }

    init(store: CaptureStore, extractor: Extractor? = nil) {
        self.store = store
        self.extractor = extractor ?? { url, kind, filename in
            await ContentTextExtractor.extract(url: url, kind: kind, filename: filename)
        }
    }

    static func isEligible(_ kind: CaptureKind) -> Bool {
        [.image, .pdf, .document, .ai].contains(kind)
    }

    func needsIndex(_ capture: Capture) -> Bool {
        guard Self.isEligible(capture.kind) else { return false }
        let terminal = capture.contentIndexState == ContentIndexExtraction.Status.ready.rawValue
            || capture.contentIndexState == ContentIndexExtraction.Status.unavailable.rawValue
        return capture.contentIndexVersion != Self.currentVersion || !terminal
    }

    func process(_ captures: [Capture]) {
        enqueue(captures, force: false)
    }

    private func enqueue(_ captures: [Capture], force: Bool) {
        guard !hasShutDown else { return }
        for capture in captures {
            guard !cancelling.contains(capture.id), tokens[capture.id] == nil,
                  store.captures.contains(where: { $0 === capture }), Self.isEligible(capture.kind),
                  force || needsIndex(capture) else { continue }
            let token = UUID()
            tokens[capture.id] = token
            targets[capture.id] = capture
            queue.append(IndexJob(id: capture.id, token: token, kind: capture.kind,
                                  managedURL: store.managedURL(for: capture), filename: capture.originalFilename))
        }
        updateProgress()
        drain()
    }

    func retry(_ capture: Capture) {
        guard !hasShutDown, tokens[capture.id] == nil,
              store.captures.contains(where: { $0 === capture }),
              capture.contentIndexState != ContentIndexExtraction.Status.unavailable.rawValue
                || capture.contentIndexCanRetry else { return }
        enqueue([capture], force: true)
    }

    @discardableResult
    func rebuildAll() async -> Bool {
        guard !hasShutDown, !isBusy else { return false }
        let eligible = store.captures.filter { Self.isEligible($0.kind) }
        enqueue(eligible, force: true)
        return true
    }

    /// Quiesces extraction before the capture and its managed original are
    /// removed. A late Vision/PDF result cannot recreate deleted metadata.
    func cancel(for id: UUID) async {
        cancelling.insert(id)
        defer { cancelling.remove(id) }
        queue.removeAll { $0.id == id }
        tokens.removeValue(forKey: id)
        targets.removeValue(forKey: id)
        updateProgress()
        let active = running[id]
        active?.cancel()
        await active?.value
        drain()
    }

    func shutdown() {
        guard !hasShutDown else { return }
        hasShutDown = true
        queue.removeAll()
        tokens.removeAll()
        targets.removeAll()
        updateProgress()
        for task in running.values { task.cancel() }
    }

    private func drain() {
        guard !hasShutDown else { return }
        while running.count < maximumConcurrentJobs && !queue.isEmpty {
            let job = queue.removeFirst()
            guard begin(job) else { continue }
            let extraction = extractor
            let task = Task { [weak self] in
                guard let self else { return }
                guard !self.hasShutDown, self.tokens[job.id] == job.token else {
                    self.running.removeValue(forKey: job.id)
                    self.drain()
                    return
                }
                let result: ContentIndexExtraction
                if let managedURL = job.managedURL {
                    let worker = Task.detached(priority: .utility) {
                        await extraction(managedURL, job.kind, job.filename)
                    }
                    result = await withTaskCancellationHandler {
                        await worker.value
                    } onCancel: {
                        worker.cancel()
                    }
                } else {
                    result = .unavailable("The saved original is unavailable for text recognition.", canRetry: false)
                }
                await self.finish(job, result: result)
            }
            running[job.id] = task
        }
    }

    /// Persist only the item whose single worker is about to start. This keeps
    /// launch responsive for large legacy archives and leaves queued captures'
    /// prior searchable text intact until their replacement begins.
    private func begin(_ job: IndexJob) -> Bool {
        guard tokens[job.id] == job.token, let capture = targets[job.id],
              store.captures.contains(where: { $0 === capture }), capture.kind == job.kind else {
            discard(job)
            return false
        }
        let previous = (capture.contentIndexState, capture.contentIndexError,
                        capture.contentIndexVersion, capture.contentIndexCanRetry)
        capture.contentIndexState = "indexing"
        capture.contentIndexError = nil
        capture.contentIndexVersion = 0
        capture.contentIndexCanRetry = false
        do {
            try store.save(captures: [capture])
            return true
        } catch {
            capture.contentIndexState = previous.0
            capture.contentIndexError = previous.1
            capture.contentIndexVersion = previous.2
            capture.contentIndexCanRetry = previous.3
            store.error = "Text recognition could not start: \(error.localizedDescription)"
            discard(job)
            return false
        }
    }

    private func discard(_ job: IndexJob) {
        if tokens[job.id] == job.token {
            tokens.removeValue(forKey: job.id)
            targets.removeValue(forKey: job.id)
        }
        updateProgress()
    }

    private func finish(_ job: IndexJob, result: ContentIndexExtraction) async {
        defer {
            running.removeValue(forKey: job.id)
            if tokens[job.id] == job.token {
                tokens.removeValue(forKey: job.id)
                targets.removeValue(forKey: job.id)
            }
            updateProgress()
            drain()
        }
        guard !hasShutDown, !Task.isCancelled, tokens[job.id] == job.token,
              let capture = targets[job.id],
              store.captures.contains(where: { $0 === capture }), capture.id == job.id,
              capture.kind == job.kind else { return }
        let previous = (capture.indexedText, capture.contentIndexState,
                        capture.contentIndexError, capture.contentIndexVersion,
                        capture.contentIndexCanRetry)
        // Originals are immutable, so a previous successful index remains
        // useful if rebuilding with a newer extractor cannot read the file.
        if result.status == .ready { capture.indexedText = result.text }
        capture.contentIndexState = result.status.rawValue
        capture.contentIndexError = result.message
        capture.contentIndexVersion = Self.currentVersion
        capture.contentIndexCanRetry = result.canRetry
        do {
            try store.save(captures: [capture])
        } catch {
            capture.indexedText = previous.0
            capture.contentIndexState = previous.1
            capture.contentIndexError = previous.2
            capture.contentIndexVersion = previous.3
            capture.contentIndexCanRetry = previous.4
            store.error = "The original is saved, but its searchable text could not be updated: \(error.localizedDescription)"
        }
    }

    private func updateProgress() {
        pendingCount = tokens.count
    }
}

private struct IndexJob: Sendable {
    let id: UUID
    let token: UUID
    let kind: CaptureKind
    let managedURL: URL?
    let filename: String?
}

enum ContentTextExtractor {
    static let maximumPages = 100
    static let maximumCharacters = 300_000
    static let maximumTextFileBytes = 12 * 1_024 * 1_024

    static func extract(url: URL, kind: CaptureKind, filename: String?) async -> ContentIndexExtraction {
        guard !Task.isCancelled else { return .unavailable("Text recognition was cancelled.") }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            return .unavailable("The saved original could not be read for text recognition.")
        }
        switch kind {
        case .image:
            return recognizeImage(url)
        case .pdf, .ai:
            return recognizePDF(url)
        case .document:
            return readDocument(url, filename: filename)
        default:
            return .unavailable("This capture type does not contain a searchable document.", canRetry: false)
        }
    }

    private static func recognizeImage(_ url: URL) -> ContentIndexExtraction {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return .unavailable("This image could not be opened for text recognition.", canRetry: false)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 4_096
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return .unavailable("This image could not be opened for text recognition.", canRetry: false)
        }
        switch recognize(image) {
        case .success(let text): return boundedResult(text)
        case .failure:
            return .unavailable("Text recognition could not process this image. Try again.")
        }
    }

    private static func recognizePDF(_ url: URL) -> ContentIndexExtraction {
        guard let document = PDFDocument(url: url), !document.isLocked else {
            return .unavailable("This PDF is locked or could not be opened for text recognition.", canRetry: false)
        }
        var pages: [String] = []
        var characterCount = 0
        var processedPages = 0
        var failedPages = 0
        var reachedCharacterLimit = false
        let pageLimit = min(document.pageCount, maximumPages)
        for index in 0..<pageLimit {
            if Task.isCancelled { return .unavailable("Text recognition was cancelled.") }
            if characterCount >= maximumCharacters {
                reachedCharacterLimit = true
                break
            }
            let pageResult: PDFPageText = autoreleasepool {
                guard let page = document.page(at: index) else { return .failure }
                let native = clean(page.string ?? "")
                if !native.isEmpty { return .success(native) }
                guard let image = pdfImage(page) else { return .failure }
                switch recognize(image) {
                case .success(let text): return .success(text)
                case .failure: return .failure
                }
            }
            processedPages += 1
            switch pageResult {
            case .failure:
                failedPages += 1
            case .success(let value):
                guard !value.isEmpty else { continue }
                let separatorCount = pages.isEmpty ? 0 : 1
                let remaining = maximumCharacters - characterCount - separatorCount
                guard remaining > 0 else {
                    reachedCharacterLimit = true
                    break
                }
                if value.count > remaining {
                    pages.append(String(value.prefix(remaining)))
                    characterCount = maximumCharacters
                    reachedCharacterLimit = true
                    break
                }
                pages.append(value)
                characterCount += separatorCount + value.count
            }
            if reachedCharacterLimit { break }
        }
        let joined = pages.joined(separator: "\n")
        if joined.isEmpty, failedPages > 0 {
            return .unavailable("Text recognition could not read \(failedPages == 1 ? "this PDF page" : "\(failedPages) PDF pages"). Try again.")
        }
        var notes: [String] = []
        if reachedCharacterLimit {
            notes.append("Indexed the first \(maximumCharacters.formatted()) characters across \(processedPages) of \(document.pageCount) pages.")
        } else if document.pageCount > processedPages {
            notes.append("Indexed the first \(processedPages) of \(document.pageCount) pages.")
        }
        if failedPages > 0 {
            notes.append("Could not recognize text on \(failedPages) \(failedPages == 1 ? "page" : "pages").")
        }
        return .ready(joined, message: notes.isEmpty ? nil : notes.joined(separator: " "))
    }

    private static func pdfImage(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let ratio = bounds.width / bounds.height
        let size = ratio >= 1
            ? NSSize(width: 1_800, height: max(1, 1_800 / ratio))
            : NSSize(width: max(1, 1_800 * ratio), height: 1_800)
        let thumbnail = page.thumbnail(of: size, for: .mediaBox)
        var rect = NSRect(origin: .zero, size: thumbnail.size)
        return thumbnail.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private enum ImageText { case success(String), failure }
    private enum PDFPageText { case success(String), failure }

    private static func recognize(_ image: CGImage) -> ImageText {
        guard !Task.isCancelled else { return .failure }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
            guard !Task.isCancelled else { return .failure }
            let observations = (request.results ?? []).sorted { lhs, rhs in
                let lhsRow = Int((lhs.boundingBox.maxY * 100).rounded(.down))
                let rhsRow = Int((rhs.boundingBox.maxY * 100).rounded(.down))
                if lhsRow != rhsRow { return lhsRow > rhsRow }
                if lhs.boundingBox.minX != rhs.boundingBox.minX { return lhs.boundingBox.minX < rhs.boundingBox.minX }
                return lhs.boundingBox.maxY > rhs.boundingBox.maxY
            }
            return .success(clean(observations.compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")))
        } catch {
            return .failure
        }
    }

    private static func readDocument(_ url: URL, filename: String?) -> ContentIndexExtraction {
        let ext = ((filename ?? url.lastPathComponent) as NSString).pathExtension.lowercased()
        let richTypes: Set<String> = ["rtf"]
        let textTypes = CaptureClassifier.locallySearchableDocumentExtensions.subtracting(richTypes)
        guard richTypes.contains(ext) || textTypes.contains(ext) else {
            return .unavailable("Text search is not available yet for this document format.", canRetry: false)
        }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return .unavailable("This document could not be inspected for text search.")
        }
        guard size.intValue <= maximumTextFileBytes else {
            return .unavailable("This document is larger than the 12 MB local text-search limit.", canRetry: false)
        }
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            return .unavailable("This document could not be read for text search.")
        }
        if richTypes.contains(ext) {
            guard let value = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf],
                                                       documentAttributes: nil).string else {
                return .unavailable("This formatted document could not be read for text search.", canRetry: false)
            }
            return boundedResult(clean(value))
        }
        let value: String
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            guard let decoded = String(data: data.dropFirst(3), encoding: .utf8) else {
                return .unavailable("This text document uses an unsupported encoding.", canRetry: false)
            }
            value = decoded
        } else if let decoded = String(data: data, encoding: .utf8) {
            value = decoded
        } else if let decoded = String(data: data, encoding: .utf16) {
            value = decoded
        } else {
            return .unavailable("This text document uses an unsupported encoding.", canRetry: false)
        }
        return boundedResult(clean(value))
    }

    private static func clean(_ value: String) -> String {
        value.replacingOccurrences(of: "\0", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func bounded(_ value: String) -> String {
        value.count <= maximumCharacters ? value : String(value.prefix(maximumCharacters))
    }

    private static func boundedResult(_ value: String) -> ContentIndexExtraction {
        .ready(bounded(value), message: value.count > maximumCharacters
            ? "Indexed the first \(maximumCharacters.formatted()) characters."
            : nil)
    }
}
