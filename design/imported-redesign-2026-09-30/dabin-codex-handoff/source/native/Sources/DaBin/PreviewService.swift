import AppKit
@preconcurrency import AVFoundation
import ImageIO
import LinkPresentation
import PDFKit
@preconcurrency import QuickLookThumbnailing
import UniformTypeIdentifiers

/// Previews are disposable derivatives. Originals and capture timestamps never change here.
@MainActor
final class PreviewService {
    static let linkPreviewPreference = "DaBin.linkPreviewsEnabled"
    private let store: CaptureStore
    private let defaults: UserDefaults
    private let thumbnailWriter: @Sendable (Data, URL, UUID) async -> String?
    private var queue: [PreviewJob] = []
    private var running: [UUID: Task<Void, Never>] = [:]
    private var tokens: [UUID: UUID] = [:]
    private var providers: [UUID: LPMetadataProvider] = [:]
    private var restartAfterCancellation: Set<UUID> = []
    private var cancelling: Set<UUID> = []
    private var networkGeneration = 0
    private var hasShutDown = false
    private let maximumConcurrentJobs = 2

    init(store: CaptureStore, defaults: UserDefaults = .standard,
         thumbnailWriter: (@Sendable (Data, URL, UUID) async -> String?)? = nil) {
        self.store = store
        self.defaults = defaults
        self.thumbnailWriter = thumbnailWriter ?? { png, root, id in
            await Self.writeThumbnail(png, root: root, id: id)
        }
    }

    /// Off until the user explicitly enables website contact in Settings.
    var enabled: Bool {
        get { defaults.bool(forKey: Self.linkPreviewPreference) }
        set {
            guard !hasShutDown else { return }
            defaults.set(newValue, forKey: Self.linkPreviewPreference)
            if newValue {
                for capture in store.captures where capture.kind == .link && capture.previewState == "unavailable" && running[capture.id] != nil {
                    restartAfterCancellation.insert(capture.id)
                }
                process(store.captures.filter { $0.kind == .link && !$0.captureOrigin.isAutomatic })
            } else {
                cancelNetwork()
            }
        }
    }

    /// A link without an image can be a complete preview. Only rebuild a ready
    /// link when it previously had a thumbnail and that disposable file is gone,
    /// and only while website contact is still enabled.
    func needsPreview(for capture: Capture) -> Bool {
        guard capture.previewState == "ready" else { return true }
        if capture.kind == .text || capture.kind == .task { return capture.previewError != nil }
        let thumbnailReadable = store.previewURL(for: capture).map {
            FileManager.default.isReadableFile(atPath: $0.path)
        } ?? false
        if capture.kind == .link {
            return enabled && capture.thumbnailRelativePath != nil && !thumbnailReadable
        }
        return !thumbnailReadable
    }

    func process(_ captures: [Capture]) {
        guard !hasShutDown else { return }
        var changed: [Capture] = []
        for capture in captures {
            guard !cancelling.contains(capture.id), tokens[capture.id] == nil,
                  store.captures.contains(where: { $0 === capture }), needsPreview(for: capture) else { continue }
            if capture.kind == .text || capture.kind == .task {
                if capture.previewState != "ready" || capture.previewError != nil {
                    capture.previewState = "ready"
                    capture.previewError = nil
                    changed.append(capture)
                }
                continue
            }
            if capture.kind == .link && (capture.captureOrigin.isAutomatic || !enabled) {
                let message = capture.captureOrigin.isAutomatic
                    ? "Automatic captures stay local. Open the saved link when you choose."
                    : "Website previews are off. The saved link is available."
                if capture.previewState != "unavailable" || capture.previewError != message {
                    capture.previewState = "unavailable"
                    capture.previewError = message
                    changed.append(capture)
                }
                continue
            }
            let token = UUID()
            let job = PreviewJob(id: capture.id, token: token, kind: capture.kind.rawValue,
                                 originalURL: capture.originalURL.flatMap(URL.init(string:)),
                                 managedURL: store.managedURL(for: capture),
                                 filename: capture.originalFilename,
                                 networkGeneration: networkGeneration)
            tokens[capture.id] = token
            capture.previewState = "loading"
            capture.previewError = nil
            queue.append(job)
            changed.append(capture)
        }
        persist(changed)
        drain()
    }

    /// Quiesce a capture's preview before deleting its owned files. A renderer
    /// may finish after cancellation, so await its completion before cleanup.
    /// The store removes cache files only after metadata deletion commits.
    func cancel(for id: UUID) async {
        cancelling.insert(id)
        defer { cancelling.remove(id) }
        queue.removeAll { $0.id == id }
        tokens.removeValue(forKey: id)
        restartAfterCancellation.remove(id)
        providers[id]?.cancel()
        let active = running[id]
        active?.cancel()
        await active?.value
        drain()
    }

    func cancelNetwork() {
        guard !hasShutDown else { return }
        networkGeneration += 1
        restartAfterCancellation.removeAll()
        let queued = queue.filter { $0.kind == "link" }
        queue.removeAll { $0.kind == "link" }
        for job in queued { tokens.removeValue(forKey: job.id) }
        for (id, provider) in providers {
            provider.cancel()
            running[id]?.cancel()
        }
        var changed: [Capture] = []
        for capture in store.captures where capture.kind == .link && capture.previewState == "loading" {
            capture.previewState = "unavailable"
            capture.previewError = "Website previews are off. The saved link is available."
            changed.append(capture)
        }
        persist(changed)
        drain()
    }

    /// One-way application teardown. Existing preferences, records and cache
    /// files remain intact; unfinished previews will be retried on next launch.
    func shutdown() {
        guard !hasShutDown else { return }
        hasShutDown = true
        networkGeneration += 1
        queue.removeAll()
        tokens.removeAll()
        restartAfterCancellation.removeAll()
        for provider in providers.values { provider.cancel() }
        for task in running.values { task.cancel() }
    }

    private func drain() {
        guard !hasShutDown else { return }
        while running.count < maximumConcurrentJobs && !queue.isEmpty {
            let job = queue.removeFirst()
            let task = Task { [weak self] in
                guard let self else { return }
                guard !self.hasShutDown, self.tokens[job.id] == job.token else {
                    self.running.removeValue(forKey: job.id)
                    self.drain()
                    return
                }
                let result: PreviewResult
                if job.kind == "link" {
                    result = await self.linkPreview(job)
                } else {
                    // Only immutable values cross into the worker; Capture objects stay on MainActor.
                    let renderer = Task.detached(priority: .utility) {
                        await PreviewRenderer.render(job)
                    }
                    result = await withTaskCancellationHandler {
                        await renderer.value
                    } onCancel: { renderer.cancel() }
                }
                await self.finish(job, result: result)
            }
            running[job.id] = task
        }
    }

    private func linkPreview(_ job: PreviewJob) async -> PreviewResult {
        guard enabled, job.networkGeneration == networkGeneration,
              let url = job.originalURL,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return .unavailable("Website previews are off. The saved link is available.")
        }
        let provider = LPMetadataProvider()
        provider.timeout = 12
        providers[job.id] = provider
        defer { providers.removeValue(forKey: job.id) }
        do {
            let metadata = try await provider.startFetchingMetadata(for: url)
            guard !Task.isCancelled, enabled, job.networkGeneration == networkGeneration else {
                return .unavailable("Website preview was cancelled. The saved link is available.")
            }
            var thumbnail: Data?
            if let imageProvider = metadata.imageProvider ?? metadata.iconProvider {
                let data = await PreviewRenderer.imageData(from: imageProvider)
                if let data {
                    thumbnail = await Task.detached(priority: .utility) {
                        PreviewRenderer.downsample(data: data)
                    }.value
                }
            }
            return PreviewResult(title: metadata.title, description: url.host ?? "Web link",
                                 png: thumbnail, state: "ready", error: nil)
        } catch {
            return .unavailable("Website preview unavailable. The saved link is available.")
        }
    }

    private func finish(_ job: PreviewJob, result: PreviewResult) async {
        defer {
            running.removeValue(forKey: job.id)
            if tokens[job.id] == job.token { tokens.removeValue(forKey: job.id) }
            drain()
            if !hasShutDown, restartAfterCancellation.remove(job.id) != nil, enabled,
               let current = store.captures.first(where: { $0.id == job.id }) {
                process([current])
            }
        }
        guard !hasShutDown, tokens[job.id] == job.token,
              job.kind != "link" || (enabled && job.networkGeneration == networkGeneration),
              let capture = store.captures.first(where: { $0.id == job.id }) else { return }
        var relativePath: String?
        if let png = result.png {
            relativePath = await thumbnailWriter(png, store.root, job.id)
        }
        guard !hasShutDown else { return }
        // Disabling website previews during an image fetch/write must also suppress its UI update.
        guard tokens[job.id] == job.token,
              job.kind != "link" || (enabled && job.networkGeneration == networkGeneration),
              store.captures.contains(where: { $0 === capture }) else {
            // Defensive cleanup also covers removal outside the normal cancel-
            // then-delete flow while the thumbnail write was suspended.
            if !store.captures.contains(where: { $0.id == job.id }) { removeThumbnail(for: job.id) }
            return
        }
        if let title = result.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            capture.title = String(title.prefix(500))
        }
        if let description = result.description { capture.previewDescription = description }
        if let relativePath { capture.thumbnailRelativePath = relativePath }
        else if job.kind == "link", result.state == "ready", result.png == nil {
            // A refreshed page may no longer supply an image. Treat its valid
            // metadata-only card as complete instead of fetching on every launch.
            capture.thumbnailRelativePath = nil
        }
        capture.previewState = result.state
        capture.previewError = result.error
        if result.png != nil && relativePath == nil {
            capture.previewState = "unavailable"
            capture.previewError = "Thumbnail could not be cached. The saved original is available."
        }
        persist([capture])
    }

    static func writeThumbnail(_ png: Data, root: URL, id: UUID) async -> String? {
        let archive = DailyArchive(root: root)
        return await Task.detached(priority: .utility) {
            let relative = "Previews/\(id.uuidString)/thumbnail.png"
            do {
                try archive.ensureDirectory("Previews/\(id.uuidString)")
                try png.write(to: archive.safeURL(relative), options: .atomic)
                return relative
            } catch { return nil }
        }.value
    }

    private func removeThumbnail(for id: UUID) {
        do {
            let folder = try DailyArchive(root: store.root).safeURL("Previews/\(id.uuidString)")
            if FileManager.default.fileExists(atPath: folder.path) {
                try FileManager.default.removeItem(at: folder)
            }
        } catch {
            store.error = "The preview cache could not be cleared: \(error.localizedDescription)"
        }
    }

    private func persist(_ captures: [Capture]) {
        do { try store.save(captures: captures) }
        catch { store.error = "The original is saved, but its preview could not be updated: \(error.localizedDescription)" }
    }
}

private struct PreviewJob: Sendable {
    let id: UUID
    let token: UUID
    let kind: String
    let originalURL: URL?
    let managedURL: URL?
    let filename: String?
    let networkGeneration: Int
}

private struct PreviewResult: Sendable {
    var title: String?
    var description: String?
    var png: Data?
    var state: String
    var error: String?

    static func unavailable(_ reason: String, description: String? = nil) -> Self {
        .init(title: nil, description: description, png: nil, state: "unavailable", error: reason)
    }
}

private enum PreviewRenderer {
    static let thumbnailSize = 600

    static func render(_ job: PreviewJob) async -> PreviewResult {
        guard !Task.isCancelled else {
            return .unavailable("Preview cancelled. The saved original is available.")
        }
        guard let url = job.managedURL, FileManager.default.isReadableFile(atPath: url.path) else {
            return .unavailable("The managed original could not be read.")
        }
        switch job.kind {
        case "image":
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let png = thumbnail(source) else {
                return .unavailable("Image preview unavailable. Open the saved original to view it.")
            }
            var description = "Image"
            if let values = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
               let width = values[kCGImagePropertyPixelWidth] as? NSNumber,
               let height = values[kCGImagePropertyPixelHeight] as? NSNumber {
                description = "\(width.intValue) × \(height.intValue) pixels"
            }
            return .init(title: nil, description: description, png: png, state: "ready", error: nil)
        case "pdf":
            guard let document = PDFDocument(url: url), !document.isLocked,
                  let page = document.page(at: 0) else {
                return .unavailable("PDF preview unavailable. The document may be encrypted or unreadable.", description: "PDF document")
            }
            let image = page.thumbnail(of: NSSize(width: thumbnailSize, height: thumbnailSize), for: .mediaBox)
            let png = image.tiffRepresentation.flatMap(downsample(data:))
            return .init(title: nil, description: "\(document.pageCount) \(document.pageCount == 1 ? "page" : "pages") · PDF",
                         png: png, state: png == nil ? "unavailable" : "ready",
                         error: png == nil ? "PDF thumbnail unavailable. The saved original is available." : nil)
        case "video":
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: thumbnailSize, height: thumbnailSize)
            return await PreviewRequest.perform(timeout: 15,
                timeoutValue: .unavailable("Video preview timed out. The saved original is available.", description: "Video"),
                cancelledValue: .unavailable("Video preview cancelled. The saved original is available.", description: "Video")) { finish in
                let work = Task {
                    do {
                        let image = try await generator.image(at: .zero).image
                        let duration = try? await asset.load(.duration)
                        let seconds = duration.map(CMTimeGetSeconds).flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
                        let description = seconds.map { String(format: "%d:%02d · Video", Int($0) / 60, Int($0) % 60) } ?? "Video"
                        finish(.init(title: nil, description: description, png: png(image), state: "ready", error: nil))
                    } catch {
                        finish(.unavailable("Video preview unavailable. Open the saved original to play it.", description: "Video"))
                    }
                }
                return {
                    generator.cancelAllCGImageGeneration()
                    asset.cancelLoading()
                    work.cancel()
                }
            }
        default:
            let request = QLThumbnailGenerator.Request(fileAt: url,
                size: CGSize(width: thumbnailSize, height: thumbnailSize), scale: 1,
                representationTypes: [.thumbnail])
            let generator = QLThumbnailGenerator.shared
            let result: PreviewResult = await PreviewRequest.perform(timeout: 15,
                timeoutValue: .unavailable("Preview timed out. The saved original is available.", description: typeLabel(url)),
                cancelledValue: .unavailable("Preview cancelled. The saved original is available.", description: typeLabel(url))) { finish in
                generator.generateBestRepresentation(for: request) { representation, _ in
                    if let representation, let data = png(representation.cgImage) {
                        finish(.init(title: nil, description: typeLabel(url), png: data, state: "ready", error: nil))
                    } else {
                        finish(.unavailable("No system thumbnail is available. The saved original is available.", description: typeLabel(url)))
                    }
                }
                return { generator.cancel(request) }
            }
            return result
        }
    }

    static func typeLabel(_ url: URL) -> String {
        if url.pathExtension.lowercased() == "ai" { return "Adobe Illustrator file" }
        return UTType(filenameExtension: url.pathExtension)?.localizedDescription ?? "\(url.pathExtension.uppercased()) file"
    }

    static func downsample(data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return thumbnail(source)
    }

    static func thumbnail(_ source: CGImageSource) -> Data? {
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                      kCGImageSourceCreateThumbnailWithTransform: true,
                                      kCGImageSourceThumbnailMaxPixelSize: thumbnailSize,
                                      kCGImageSourceShouldCacheImmediately: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return png(image)
    }

    static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    static func imageData(from provider: NSItemProvider) async -> Data? {
        guard let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) else { return nil }
        let load = PreviewImageLoad()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard load.begin(continuation) else { return }
                let progress = provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
                    // Keep unexpectedly large website images out of the thumbnail decode path.
                    load.finish(data.flatMap { $0.count <= 20 * 1_024 * 1_024 ? $0 : nil })
                }
                load.setProgress(progress)
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 8) { load.cancel() }
            }
        } onCancel: { load.cancel() }
    }
}

private final class PreviewImageLoad: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data?, Never>?
    private var progress: Progress?
    private var cancelled = false

    func begin(_ continuation: CheckedContinuation<Data?, Never>) -> Bool {
        lock.lock()
        let stopped = cancelled
        if !stopped { self.continuation = continuation }
        lock.unlock()
        if stopped { continuation.resume(returning: nil) }
        return !stopped
    }

    func setProgress(_ progress: Progress) {
        lock.lock()
        self.progress = progress
        let stopped = cancelled
        lock.unlock()
        if stopped { progress.cancel() }
    }

    func finish(_ data: Data?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        progress = nil
        lock.unlock()
        pending?.resume(returning: data)
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let pending = continuation
        let active = progress
        continuation = nil
        progress = nil
        lock.unlock()
        active?.cancel()
        pending?.resume(returning: nil)
    }
}
