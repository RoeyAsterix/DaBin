import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

struct AutoCaptureSourceApplication: Equatable, Sendable {
    let name: String?
    let bundleIdentifier: String?

    init(name: String?, bundleIdentifier: String?) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
    }
}

/// Emitted only after all durable writes for at least one capture succeeded.
/// The UI can use this as the sole trigger for the confirmation robot.
struct AutoCaptureSavedAction {
    let actionID: UUID
    let origin: CaptureOrigin
    let capturedAt: Date
    let sourceApplication: AutoCaptureSourceApplication?
    let captures: [Capture]
}

enum AutoCaptureServiceError: LocalizedError {
    case screenshotFolderNotAuthorized
    case screenshotFolderAuthorizationStale
    case unreadableClipboard

    var errorDescription: String? {
        switch self {
        case .screenshotFolderNotAuthorized:
            return "Choose the folder where macOS saves screenshots before enabling Auto Capture."
        case .screenshotFolderAuthorizationStale:
            return "DaBin no longer has access to the screenshot folder. Choose it again in Settings."
        case .unreadableClipboard:
            return "The copied item did not provide a supported representation."
        }
    }
}

/// Owns the opt-in monitors and serializes their events through InputService.
/// Initialization is inert: callers explicitly invoke `start()` or a setting
/// mutation, so launch never prompts and never imports the existing clipboard.
@MainActor
final class AutoCaptureService: ObservableObject {
    typealias ScreenshotMonitorFactory = (URL) -> ScreenshotFolderMonitoring
    typealias BookmarkCreator = (URL) throws -> Data
    typealias BookmarkResolver = (Data) throws -> (url: URL, isStale: Bool)

    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?

    let settings: AutoCaptureSettings
    /// Delivers every durable subset so the feed and local preview pipeline can
    /// reflect committed records even when another item in the action failed.
    var onCommitted: ((AutoCaptureSavedAction) -> Void)?
    /// Delivers only actions whose complete input saved successfully. This is
    /// the sole callback suitable for positive visual confirmation.
    var onSaved: ((AutoCaptureSavedAction) -> Void)?
    var onFailure: ((String) -> Void)?

    private let input: InputService
    private let pasteboardProvider: () -> NSPasteboard
    private let sourceApplicationProvider: () -> AutoCaptureSourceApplication?
    private let screenshotMonitorFactory: ScreenshotMonitorFactory
    private let bookmarkCreator: BookmarkCreator
    private let bookmarkResolver: BookmarkResolver
    private let dateProvider: () -> Date
    private let timeZoneProvider: () -> TimeZone
    private let pollInterval: TimeInterval
    private let clipboardImageDelay: Duration

    private var pollTimer: Timer?
    private var applicationActivationObserver: NSObjectProtocol?
    private var screenshotMonitor: ScreenshotFolderMonitoring?
    private var authorizedFolder: URL?
    private var securityScopeStarted = false
    private var lastPasteboardChangeCount: Int?
    private var sessionGeneration: UInt = 0
    private var queue: [PendingEvent] = []
    private var isProcessingEvent = false
    private var delayedClipboardImages: [UUID: DelayedClipboardImage] = [:]
    private var fingerprintHistory: AutoCaptureFingerprintHistory
    private var activeSourceIsExcluded = false

    init(settings: AutoCaptureSettings,
         input: InputService,
         pasteboardProvider: @escaping () -> NSPasteboard = { .general },
         sourceApplicationProvider: @escaping () -> AutoCaptureSourceApplication? = {
             guard let application = NSWorkspace.shared.frontmostApplication else { return nil }
             return AutoCaptureSourceApplication(name: application.localizedName,
                                                 bundleIdentifier: application.bundleIdentifier)
         },
         screenshotMonitorFactory: ScreenshotMonitorFactory? = nil,
         bookmarkCreator: @escaping BookmarkCreator = AutoCaptureService.createBookmark,
         bookmarkResolver: @escaping BookmarkResolver = AutoCaptureService.resolveBookmark,
         dateProvider: @escaping () -> Date = Date.init,
         timeZoneProvider: @escaping () -> TimeZone = { .current },
         pollInterval: TimeInterval = 0.35,
         clipboardImageDelay: Duration = .milliseconds(1_250),
         duplicateInterval: TimeInterval = 4) {
        self.settings = settings
        self.input = input
        self.pasteboardProvider = pasteboardProvider
        self.sourceApplicationProvider = sourceApplicationProvider
        self.screenshotMonitorFactory = screenshotMonitorFactory ?? { ScreenshotFolderMonitor(folder: $0) }
        self.bookmarkCreator = bookmarkCreator
        self.bookmarkResolver = bookmarkResolver
        self.dateProvider = dateProvider
        self.timeZoneProvider = timeZoneProvider
        self.pollInterval = max(0.1, pollInterval)
        self.clipboardImageDelay = clipboardImageDelay
        fingerprintHistory = AutoCaptureFingerprintHistory(interval: duplicateInterval)
    }

    /// Starts only when the persisted opt-in, pause state and folder grant allow
    /// it. Missing authorization becomes visible state; no panel is opened here.
    func start() {
        guard !isRunning else { return }
        guard settings.isEnabled else {
            settings.setStatus(.disabled)
            return
        }
        guard !settings.isPaused else {
            settings.setStatus(.paused)
            return
        }
        guard let bookmark = settings.screenshotFolderBookmark else {
            settings.setStatus(.permissionRequired)
            report(AutoCaptureServiceError.screenshotFolderNotAuthorized)
            return
        }

        let resolution: (url: URL, isStale: Bool)
        do {
            resolution = try bookmarkResolver(bookmark)
        } catch {
            settings.setStatus(.permissionRevoked)
            report(AutoCaptureServiceError.screenshotFolderAuthorizationStale)
            return
        }
        guard !resolution.isStale else {
            settings.setStatus(.permissionRevoked)
            report(AutoCaptureServiceError.screenshotFolderAuthorizationStale)
            return
        }

        sessionGeneration &+= 1
        let generation = sessionGeneration
        let folder = resolution.url.standardizedFileURL
        securityScopeStarted = folder.startAccessingSecurityScopedResource()
        authorizedFolder = folder
        let monitor = screenshotMonitorFactory(folder)
        monitor.sourceApplicationAtDirectoryActivity = { [weak self] in
            guard let self,
                  self.sessionGeneration == generation,
                  self.settings.isEnabled,
                  !self.settings.isPaused else { return nil }
            return self.sourceApplicationProvider()
        }
        monitor.onNewScreenshot = { [weak self] url, sampledApplication in
            guard let self, self.isSessionGenerationCurrent(generation) else { return }
            self.receiveScreenshot(url, application: sampledApplication, generation: generation)
        }
        monitor.onFailure = { [weak self] error in
            guard let self, self.sessionGeneration == generation else { return }
            self.stopRuntime(status: .permissionRevoked)
            self.report(error)
        }
        do {
            try monitor.start()
        } catch {
            releaseFolderAccess()
            settings.setStatus(.permissionRevoked)
            report(error)
            return
        }

        screenshotMonitor = monitor
        // Seeding the monotonic counter, without reading any pasteboard items,
        // guarantees that pre-launch clipboard contents are not imported.
        lastPasteboardChangeCount = pasteboardProvider().changeCount
        let activeApplication = sourceApplicationProvider()
        activeSourceIsExcluded = settings.isExcluded(bundleIdentifier: activeApplication?.bundleIdentifier)
        isRunning = true
        lastError = nil
        settings.setStatus(activeSourceIsExcluded
                           ? .sourceApplicationExcluded(activeApplication?.name ?? "Excluded application")
                           : .monitoring)
        installApplicationActivationObserver()
        installPollTimer()
    }

    func shutdown() {
        let status: AutoCaptureStatus = settings.isEnabled
            ? (settings.isPaused ? .paused : .ready) : .disabled
        stopRuntime(status: status)
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            settings.setEnabled(true)
            settings.setPaused(false)
            start()
        } else {
            stopRuntime(status: .disabled)
            settings.setEnabled(false)
            settings.setPaused(false)
            settings.setStatus(.disabled)
        }
    }

    func setPaused(_ paused: Bool) {
        guard settings.isEnabled else {
            settings.setPaused(false)
            settings.setStatus(.disabled)
            return
        }
        settings.setPaused(paused)
        if paused {
            stopRuntime(status: .paused)
        } else {
            start()
        }
    }

    func pause() { setPaused(true) }
    func resume() { setPaused(false) }

    /// Called after the user has explicitly selected a directory in NSOpenPanel.
    /// This method creates the durable grant but never presents UI itself.
    func authorizeScreenshotFolder(_ url: URL) throws {
        let bookmark = try bookmarkCreator(url.standardizedFileURL)
        if isRunning { stopRuntime(status: .ready) }
        settings.setScreenshotFolderBookmark(bookmark, displayName: url.lastPathComponent)
        settings.setStatus(settings.isEnabled ? (settings.isPaused ? .paused : .ready) : .disabled)
        if settings.isEnabled, !settings.isPaused { start() }
    }

    func removeScreenshotFolderAuthorization() {
        if isRunning { stopRuntime(status: .permissionRequired) }
        settings.setScreenshotFolderBookmark(nil)
        settings.setStatus(settings.isEnabled ? .permissionRequired : .disabled)
    }

    /// Exposed for deterministic tests and for an optional menu command. Normal
    /// production polling is driven by a timer in the common run-loop mode.
    func pollNow() {
        guard isSessionGenerationCurrent(sessionGeneration) else { return }
        let pasteboard = pasteboardProvider()
        let currentCount = pasteboard.changeCount
        let application = sourceApplicationProvider()
        if settings.isExcluded(bundleIdentifier: application?.bundleIdentifier) {
            // Changes made in an excluded app are consumed without loading data,
            // so they cannot be imported later after the user switches apps.
            lastPasteboardChangeCount = currentCount
            activeSourceIsExcluded = true
            settings.setStatus(.sourceApplicationExcluded(application?.name ?? "Excluded application"))
            return
        }
        if activeSourceIsExcluded {
            // App activation normally reseeds this synchronously. This fallback
            // covers a missed workspace notification without reading content
            // copied while an excluded application was active.
            lastPasteboardChangeCount = currentCount
            activeSourceIsExcluded = false
            settings.setStatus(.monitoring)
            return
        }
        if case .sourceApplicationExcluded = settings.status {
            settings.setStatus(.monitoring)
        }
        guard currentCount != lastPasteboardChangeCount else { return }
        lastPasteboardChangeCount = currentCount
        guard let snapshot = AutoCapturePasteboardSnapshot.copy(of: pasteboard) else {
            report(AutoCaptureServiceError.unreadableClipboard)
            return
        }

        let event = makeEvent(origin: .automaticClipboard, snapshot: snapshot,
                              application: application,
                              fingerprint: AutoCaptureFingerprint.image(on: snapshot.pasteboard),
                              generation: sessionGeneration)
        if let fingerprint = event.fingerprint {
            delayClipboardImage(event, fingerprint: fingerprint)
        } else {
            enqueue(event)
        }
    }

    func isSessionGenerationCurrent(_ generation: UInt) -> Bool {
        isRunning && generation == sessionGeneration && settings.isEnabled && !settings.isPaused
    }

    /// Workspace activation arrives before the next clipboard timer in normal
    /// use. Reseeding on the transition away from an excluded app closes the
    /// short copy-then-switch window without loading the pasteboard payload.
    func applicationDidActivate(_ application: AutoCaptureSourceApplication) {
        guard isSessionGenerationCurrent(sessionGeneration) else { return }
        let isExcluded = settings.isExcluded(bundleIdentifier: application.bundleIdentifier)
        if isExcluded || activeSourceIsExcluded {
            lastPasteboardChangeCount = pasteboardProvider().changeCount
        }
        activeSourceIsExcluded = isExcluded
        settings.setStatus(isExcluded
                           ? .sourceApplicationExcluded(application.name ?? "Excluded application")
                           : .monitoring)
    }

    private func receiveScreenshot(_ url: URL, application: AutoCaptureSourceApplication?, generation: UInt) {
        guard isSessionGenerationCurrent(generation) else { return }
        if settings.isExcluded(bundleIdentifier: application?.bundleIdentifier) {
            settings.setStatus(.sourceApplicationExcluded(application?.name ?? "Excluded application"))
            return
        }
        if case .sourceApplicationExcluded = settings.status {
            settings.setStatus(.monitoring)
        }
        guard let snapshot = AutoCapturePasteboardSnapshot.file(at: url) else {
            report(AutoCaptureServiceError.unreadableClipboard)
            return
        }
        let fingerprint = AutoCaptureFingerprint.image(at: url)
        if let fingerprint { cancelDelayedClipboardImages(matching: fingerprint) }
        enqueue(makeEvent(origin: .automaticScreenshot, snapshot: snapshot,
                          application: application, fingerprint: fingerprint,
                          generation: generation))
    }

    private func makeEvent(origin: CaptureOrigin, snapshot: AutoCapturePasteboardSnapshot,
                           application: AutoCaptureSourceApplication?,
                           fingerprint: AutoCaptureFingerprint?, generation: UInt) -> PendingEvent {
        let actionID = UUID()
        let receipt = CaptureReceiptContext.automatic(
            origin,
            actionID: actionID,
            sourceApplicationName: application?.name,
            sourceApplicationBundleIdentifier: application?.bundleIdentifier
        )
        return PendingEvent(actionID: actionID, origin: origin, snapshot: snapshot,
                            receivedAt: dateProvider(), timeZone: timeZoneProvider(),
                            sourceApplication: application, receipt: receipt,
                            fingerprint: fingerprint, generation: generation)
    }

    private func delayClipboardImage(_ event: PendingEvent, fingerprint: AutoCaptureFingerprint) {
        let pendingID = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: clipboardImageDelay)
            guard !Task.isCancelled,
                  let pending = delayedClipboardImages.removeValue(forKey: pendingID),
                  isSessionGenerationCurrent(pending.event.generation) else { return }
            enqueue(pending.event)
        }
        delayedClipboardImages[pendingID] = DelayedClipboardImage(
            fingerprint: fingerprint,
            event: event,
            task: task
        )
    }

    private func cancelDelayedClipboardImages(matching fingerprint: AutoCaptureFingerprint) {
        let matches = delayedClipboardImages.filter { $0.value.fingerprint == fingerprint }
        for (id, pending) in matches {
            pending.task.cancel()
            pending.event.snapshot.clear()
            delayedClipboardImages.removeValue(forKey: id)
        }
    }

    private func enqueue(_ event: PendingEvent) {
        guard isSessionGenerationCurrent(event.generation) else {
            event.snapshot.clear()
            return
        }
        queue.append(event)
        processNextEventIfPossible()
    }

    private func processNextEventIfPossible() {
        guard !isProcessingEvent, !queue.isEmpty else { return }
        let event = queue.removeFirst()
        guard isSessionGenerationCurrent(event.generation) else {
            event.snapshot.clear()
            processNextEventIfPossible()
            return
        }
        if let fingerprint = event.fingerprint,
           fingerprintHistory.isOppositeChannelDuplicate(fingerprint, origin: event.origin, at: event.receivedAt) {
            event.snapshot.clear()
            processNextEventIfPossible()
            return
        }

        isProcessingEvent = true
        let generation = event.generation
        input.receive(
            event.snapshot.pasteboard,
            at: event.receivedAt,
            timeZone: event.timeZone,
            receipt: event.receipt,
            fileURLTransfer: event.snapshot.fileURLTransfer,
            commitGuard: { [weak self] in
                self?.isSessionGenerationCurrent(generation) == true
            }
        ) { [weak self] captures, failures in
            event.snapshot.clear()
            guard let self else { return }
            self.isProcessingEvent = false
            if self.isSessionGenerationCurrent(generation) {
                if !captures.isEmpty {
                    if let fingerprint = event.fingerprint {
                        self.fingerprintHistory.record(fingerprint, origin: event.origin, at: self.dateProvider())
                    }
                    let action = AutoCaptureSavedAction(
                        actionID: event.actionID,
                        origin: event.origin,
                        capturedAt: event.receivedAt,
                        sourceApplication: event.sourceApplication,
                        captures: captures
                    )
                    self.onCommitted?(action)
                    if failures.isEmpty { self.onSaved?(action) }
                }
                if !failures.isEmpty { self.report(failures.joined(separator: "\n")) }
            }
            self.processNextEventIfPossible()
        }
    }

    private func installPollTimer() {
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pollNow() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func installApplicationActivationObserver() {
        if let observer = applicationActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        applicationActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let running = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else { return }
            Task { @MainActor [weak self] in
                self?.applicationDidActivate(AutoCaptureSourceApplication(
                    name: running.localizedName,
                    bundleIdentifier: running.bundleIdentifier
                ))
            }
        }
    }

    private func stopRuntime(status: AutoCaptureStatus) {
        sessionGeneration &+= 1
        isRunning = false
        pollTimer?.invalidate()
        pollTimer = nil
        if let observer = applicationActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            applicationActivationObserver = nil
        }
        screenshotMonitor?.stop()
        screenshotMonitor = nil
        lastPasteboardChangeCount = nil

        for pending in delayedClipboardImages.values {
            pending.task.cancel()
            pending.event.snapshot.clear()
        }
        delayedClipboardImages.removeAll()
        for event in queue { event.snapshot.clear() }
        queue.removeAll()
        fingerprintHistory.reset()
        activeSourceIsExcluded = false
        releaseFolderAccess()
        settings.setStatus(status)
    }

    private func releaseFolderAccess() {
        if securityScopeStarted { authorizedFolder?.stopAccessingSecurityScopedResource() }
        securityScopeStarted = false
        authorizedFolder = nil
    }

    private func report(_ error: Error) {
        report(error.localizedDescription)
    }

    private func report(_ message: String) {
        lastError = message
        onFailure?(message)
    }

    nonisolated private static func createBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                             includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    nonisolated private static func resolveBookmark(_ data: Data) throws -> (url: URL, isStale: Bool) {
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI],
                          relativeTo: nil, bookmarkDataIsStale: &stale)
        return (url, stale)
    }
}

private struct PendingEvent {
    let actionID: UUID
    let origin: CaptureOrigin
    /// Retains both the immutable content snapshot and any NSURL objects that
    /// consumed App Sandbox file-transfer grants from the source pasteboard.
    let snapshot: AutoCapturePasteboardSnapshot
    let receivedAt: Date
    let timeZone: TimeZone
    let sourceApplication: AutoCaptureSourceApplication?
    let receipt: CaptureReceiptContext
    let fingerprint: AutoCaptureFingerprint?
    let generation: UInt
}

private struct DelayedClipboardImage {
    let fingerprint: AutoCaptureFingerprint
    let event: PendingEvent
    let task: Task<Void, Never>
}

@MainActor
private final class AutoCapturePasteboardSnapshot {
    private static let webArchive = NSPasteboard.PasteboardType("com.apple.webarchive")

    let pasteboard: NSPasteboard
    let fileURLTransfer: InputFileURLTransfer

    private init(pasteboard: NSPasteboard, fileURLTransfer: InputFileURLTransfer) {
        self.pasteboard = pasteboard
        self.fileURLTransfer = fileURLTransfer
    }

    static func copy(of source: NSPasteboard) -> AutoCapturePasteboardSnapshot? {
        // Consume Finder's native transfer grant on the source pasteboard before
        // reading string representations. These NSURL objects travel with the
        // pending event while the private pasteboard freezes its content.
        let fileURLTransfer = InputFileURLTransfer.consume(from: source)
        let copiedItems = (source.pasteboardItems ?? []).compactMap { sourceItem -> NSPasteboardItem? in
            let item = NSPasteboardItem()
            for type in sourceItem.types where supported(type) {
                if [.fileURL, .URL, .string].contains(type),
                   let value = sourceItem.string(forType: type) {
                    item.setString(value, forType: type)
                } else if let data = sourceItem.data(forType: type) {
                    item.setData(data, forType: type)
                }
            }
            return item.types.isEmpty ? nil : item
        }
        guard !copiedItems.isEmpty else { return nil }
        let destination = NSPasteboard(name: .init("com.dabin.auto-capture.\(UUID().uuidString)"))
        destination.clearContents()
        guard destination.writeObjects(copiedItems) else { return nil }
        return AutoCapturePasteboardSnapshot(pasteboard: destination,
                                             fileURLTransfer: fileURLTransfer)
    }

    static func file(at url: URL) -> AutoCapturePasteboardSnapshot? {
        let destination = NSPasteboard(name: .init("com.dabin.auto-screenshot.\(UUID().uuidString)"))
        destination.clearContents()
        let item = NSPasteboardItem()
        guard item.setString(url.absoluteString, forType: .fileURL),
              destination.writeObjects([item]) else { return nil }
        return AutoCapturePasteboardSnapshot(
            pasteboard: destination,
            fileURLTransfer: InputFileURLTransfer(retaining: [url as NSURL])
        )
    }

    func clear() { pasteboard.clearContents() }

    private static func supported(_ type: NSPasteboard.PasteboardType) -> Bool {
        let direct: Set<NSPasteboard.PasteboardType> = [
            .fileURL, .URL, .string, .png, .tiff, .pdf, .rtf, .html, webArchive
        ]
        if direct.contains(type) { return true }
        guard let uniformType = UTType(type.rawValue) else { return false }
        return uniformType.conforms(to: .data) && uniformType.preferredFilenameExtension != nil
    }
}
