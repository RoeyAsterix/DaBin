import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
protocol ScreenshotFolderMonitoring: AnyObject {
    /// Sampled on the first directory notification for a write burst, before
    /// the watcher waits for the file to settle. The sampled application is
    /// carried with every image first discovered in that burst.
    var sourceApplicationAtDirectoryActivity: (() -> AutoCaptureSourceApplication?)? { get set }
    var onNewScreenshot: ((URL, AutoCaptureSourceApplication?) -> Void)? { get set }
    var onFailure: ((Error) -> Void)? { get set }
    var isRunning: Bool { get }
    func start() throws
    func stop()
}

enum ScreenshotFolderMonitorError: LocalizedError {
    case unavailable
    case notDirectory
    case symbolicLink
    case cannotObserve(Int32)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "The selected screenshot folder is no longer available."
        case .notDirectory:
            return "The selected screenshot location is not a folder."
        case .symbolicLink:
            return "Choose the screenshot folder itself instead of a symbolic link."
        case .cannotObserve(let code):
            return "DaBin could not observe the screenshot folder (error \(code))."
        }
    }
}

/// Observes one user-authorized directory. Existing files are recorded as a
/// baseline at start and are never emitted as new screenshots.
@MainActor
final class ScreenshotFolderMonitor: ScreenshotFolderMonitoring {
    var sourceApplicationAtDirectoryActivity: (() -> AutoCaptureSourceApplication?)?
    var onNewScreenshot: ((URL, AutoCaptureSourceApplication?) -> Void)?
    var onFailure: ((Error) -> Void)?
    private(set) var isRunning = false

    private let folder: URL
    private let settleDelay: Duration
    private let maximumSettleAttempts: Int
    private var source: DispatchSourceFileSystemObject?
    private var knownPaths: Set<String> = []
    private var pendingObservations: [String: PendingObservation] = [:]
    private var activitySourceSample: ActivitySourceSample?
    private var scanTask: Task<Void, Never>?
    private var generation: UInt = 0

    init(folder: URL, settleDelay: Duration = .milliseconds(350), maximumSettleAttempts: Int = 30) {
        self.folder = folder.standardizedFileURL
        self.settleDelay = settleDelay
        self.maximumSettleAttempts = max(2, maximumSettleAttempts)
    }

    func start() throws {
        guard !isRunning else { return }
        let values: URLResourceValues
        do {
            values = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        } catch {
            throw ScreenshotFolderMonitorError.unavailable
        }
        guard values.isSymbolicLink != true else { throw ScreenshotFolderMonitorError.symbolicLink }
        guard values.isDirectory == true else { throw ScreenshotFolderMonitorError.notDirectory }

        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { throw ScreenshotFolderMonitorError.cannotObserve(errno) }
        let watcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .rename, .delete, .revoke],
            queue: DispatchQueue.global(qos: .utility)
        )
        watcher.setCancelHandler { close(descriptor) }
        watcher.setEventHandler { [weak self, weak watcher] in
            let events = watcher?.data ?? []
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !events.intersection([.rename, .delete, .revoke]).isEmpty {
                    self.handleFolderFailure(ScreenshotFolderMonitorError.unavailable)
                } else {
                    self.recordDirectoryActivity()
                }
            }
        }

        do {
            knownPaths = Set(try currentScreenshots().map(Self.identity))
        } catch {
            watcher.cancel()
            throw error
        }
        generation &+= 1
        source = watcher
        isRunning = true
        watcher.resume()
    }

    func stop() {
        generation &+= 1
        scanTask?.cancel()
        scanTask = nil
        source?.cancel()
        source = nil
        knownPaths.removeAll()
        pendingObservations.removeAll()
        activitySourceSample = nil
        isRunning = false
    }

    private func recordDirectoryActivity() {
        guard isRunning else { return }
        if activitySourceSample == nil {
            activitySourceSample = ActivitySourceSample(
                application: sourceApplicationAtDirectoryActivity?()
            )
        }
        scheduleSettledScan(replacingExisting: true)
    }

    private func scheduleSettledScan(replacingExisting: Bool) {
        let expectedGeneration = generation
        if replacingExisting { scanTask?.cancel() }
        scanTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: settleDelay)
            guard !Task.isCancelled, isRunning, generation == expectedGeneration else { return }
            scanNow()
        }
    }

    private func scanNow() {
        do {
            let files = try currentScreenshots()
            let current = Set(files.map(Self.identity))
            knownPaths.formIntersection(current)
            pendingObservations = pendingObservations.filter { current.contains($0.key) }

            let additions = files
                .filter { !knownPaths.contains(Self.identity($0)) }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            let sampledApplication = activitySourceSample?.application
            activitySourceSample = nil

            var completed: [(URL, AutoCaptureSourceApplication?)] = []
            for file in additions {
                let identity = Self.identity(file)
                let currentSize = Self.fileSize(file)
                guard let previous = pendingObservations[identity] else {
                    pendingObservations[identity] = PendingObservation(
                        lastSize: currentSize,
                        attempts: 1,
                        sourceApplication: sampledApplication
                    )
                    continue
                }

                let attempts = previous.attempts + 1
                if let priorSize = previous.lastSize,
                   let currentSize,
                   priorSize == currentSize,
                   Self.isCompleteImage(file) {
                    pendingObservations.removeValue(forKey: identity)
                    knownPaths.insert(identity)
                    completed.append((file, previous.sourceApplication))
                } else if attempts >= maximumSettleAttempts {
                    // Stop polling a permanently incomplete or unreadable file.
                    // A delete/recreate cycle removes this identity from knownPaths
                    // and allows a future complete image at the same path.
                    pendingObservations.removeValue(forKey: identity)
                    knownPaths.insert(identity)
                } else {
                    pendingObservations[identity] = PendingObservation(
                        lastSize: currentSize,
                        attempts: attempts,
                        sourceApplication: previous.sourceApplication
                    )
                }
            }

            for (file, application) in completed {
                onNewScreenshot?(file, application)
            }
            if !pendingObservations.isEmpty {
                // A file can complete without another vnode event. Poll until it
                // has a stable size and ImageIO confirms a complete decode.
                scheduleSettledScan(replacingExisting: false)
            }
        } catch {
            handleFolderFailure(error)
        }
    }

    private func handleFolderFailure(_ error: Error) {
        guard isRunning else { return }
        stop()
        onFailure?(error)
    }

    private func currentScreenshots() throws -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .contentTypeKey]
        return try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ).filter { candidate in
            guard let values = try? candidate.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true, values.isSymbolicLink != true else { return false }
            let contentType = values.contentType
            let extensionType = UTType(filenameExtension: candidate.pathExtension)
            return contentType?.conforms(to: .image) == true
                || extensionType?.conforms(to: .image) == true
        }
    }

    private nonisolated static func fileSize(_ url: URL) -> Int? {
        try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    }

    private nonisolated static func isCompleteImage(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetStatus(source) == .statusComplete else { return false }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return false }
        return (0..<count).allSatisfy { index in
            CGImageSourceGetStatusAtIndex(source, index) == .statusComplete
                && CGImageSourceCreateImageAtIndex(source, index, nil) != nil
        }
    }

    private nonisolated static func identity(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

private struct PendingObservation {
    let lastSize: Int?
    let attempts: Int
    let sourceApplication: AutoCaptureSourceApplication?
}

/// Wrapping the optional application distinguishes "sampled, but unavailable"
/// from "no directory activity has been sampled yet."
private struct ActivitySourceSample {
    let application: AutoCaptureSourceApplication?
}
