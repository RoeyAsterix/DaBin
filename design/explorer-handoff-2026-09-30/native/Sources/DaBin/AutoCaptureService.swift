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
            return "Choose the folder where macOS saves screenshots to start screenshot capture."
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
    @Published private(set) var isClipboardRunning = false
    @Published private(set) var isScreenshotsRunning = false
    @Published private(set) var screenshotStatus: AutoCaptureStatus = .disabled
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
    private var clipboardGeneration: UInt = 0
    private var screenshotGeneration: UInt = 0
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

    /// Each selected channel starts independently. A missing screenshot grant
    /// never stops clipboard capture, and startup never opens a permission panel.
    func start() {
        guard settings.isEnabled else {
            settings.setStatus(.disabled)
            screenshotStatus = .disabled
            return
        }
        guard !settings.isPaused else {
            settings.setStatus(.paused)
            screenshotStatus = settings.isScreenshotsEnabled ? .paused : .disabled
            return
        }
        lastError = nil
        if settings.isClipboardEnabled && !isClipboardRunning {
            clipboardGeneration &+= 1
            // Read only changeCount so pre-launch contents are never imported.
            lastPasteboardChangeCount = pasteboardProvider().changeCount
            isClipboardRunning = true
            installPollTimer()
        }
        if settings.isScreenshotsEnabled && !isScreenshotsRunning {
            startScreenshotMonitor()
        } else if !settings.isScreenshotsEnabled {
            screenshotStatus = .disabled
        }
        isRunning = isClipboardRunning || isScreenshotsRunning
        if isRunning {
            let activeApplication = sourceApplicationProvider()
            let isExcluded = settings.isExcluded(bundleIdentifier: activeApplication?.bundleIdentifier)
            if isClipboardRunning && activeSourceIsExcluded && !isExcluded {
                lastPasteboardChangeCount = pasteboardProvider().changeCount
            }
            activeSourceIsExcluded = isExcluded
            installApplicationActivationObserver()
            updateRuntimeStatus(excludedApplication: activeSourceIsExcluded ? activeApplication : nil)
        } else {
            removeApplicationActivationObserver()
            settings.setStatus(screenshotStatus)
        }
    }

    private func startScreenshotMonitor() {
        guard let bookmark = settings.screenshotFolderBookmark else {
            screenshotStatus = .permissionRequired
            return
        }

        let resolution: (url: URL, isStale: Bool)
        do {
            resolution = try bookmarkResolver(bookmark)
        } catch {
            screenshotStatus = .permissionRevoked
            report(AutoCaptureServiceError.screenshotFolderAuthorizationStale)
            return
        }
        guard !resolution.isStale else {
            screenshotStatus = .permissionRevoked
            report(AutoCaptureServiceError.screenshotFolderAuthorizationStale)
            return
        }

        let generation = sessionGeneration
        screenshotGeneration &+= 1
        let channelGeneration = screenshotGeneration
        let folder = resolution.url.standardizedFileURL
        securityScopeStarted = folder.startAccessingSecurityScopedResource()
        authorizedFolder = folder
        let monitor = screenshotMonitorFactory(folder)
        monitor.sourceApplicationAtDirectoryActivity = { [weak self] in
            guard let self,
                  self.sessionGeneration == generation,
                  self.screenshotGeneration == channelGeneration,
                  self.settings.isScreenshotsEnabled,
                  !self.settings.isPaused else { return nil }
            return self.sourceApplicationProvider()
        }
        monitor.onNewScreenshot = { [weak self] url, sampledApplication in
            guard let self, self.isSessionGenerationCurrent(generation),
                  self.screenshotGeneration == channelGeneration else { return }
            self.receiveScreenshot(url, application: sampledApplication, generation: generation)
        }
        monitor.onFailure = { [weak self] error in
            guard let self, self.sessionGeneration == generation,
                  self.screenshotGeneration == channelGeneration else { return }
            self.stopScreenshotRuntime()
            self.screenshotStatus = .permissionRevoked
            self.isRunning = self.isClipboardRunning
            if !self.isRunning { self.removeApplicationActivationObserver() }
            self.updateRuntimeStatus()
            self.report(error)
        }
        do {
            try monitor.start()
        } catch {
            monitor.stop()
            releaseFolderAccess()
            screenshotStatus = .permissionRevoked
            report(error)
            return
        }

        screenshotMonitor = monitor
        isScreenshotsRunning = true
        screenshotStatus = .monitoring
    }

    func shutdown() {
        let status: AutoCaptureStatus = settings.isEnabled
            ? (settings.isPaused ? .paused : .ready) : .disabled
        stopRuntime(status: status)
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            settings.setPaused(false)
            start()
        } else {
            stopRuntime(status: .disabled)
            settings.setEnabled(false)
            settings.setPaused(false)
            settings.setStatus(.disabled)
        }
    }

    func setClipboardEnabled(_ enabled: Bool) {
        guard settings.isClipboardEnabled != enabled else { return }
        if !enabled { stopClipboardRuntime() }
        settings.setClipboardEnabled(enabled)
        refreshSelectedChannels()
    }

    func setScreenshotsEnabled(_ enabled: Bool) {
        guard settings.isScreenshotsEnabled != enabled else { return }
        if !enabled { stopScreenshotRuntime() }
        settings.setScreenshotsEnabled(enabled)
        refreshSelectedChannels()
    }

    private func refreshSelectedChannels() {
        isRunning = isClipboardRunning || isScreenshotsRunning
        if settings.isEnabled {
            start()
        } else {
            stopRuntime(status: .disabled)
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
        stopScreenshotRuntime()
        settings.setScreenshotFolderBookmark(bookmark, displayName: url.lastPathComponent)
        refreshSelectedChannels()
    }

    func removeScreenshotFolderAuthorization() {
        stopScreenshotRuntime()
        settings.setScreenshotFolderBookmark(nil)
        refreshSelectedChannels()
    }

    /// Exposed for deterministic tests and for an optional menu command. Normal
    /// production polling is driven by a timer in the common run-loop mode.
    func pollNow() {
        guard isClipboardRunning, settings.isClipboardEnabled,
              isSessionGenerationCurrent(sessionGeneration) else { return }
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
            updateRuntimeStatus()
            return
        }
        if case .sourceApplicationExcluded = settings.status {
            updateRuntimeStatus()
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
        if let fingerprint = event.fingerprint, isScreenshotsRunning {
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
        if isClipboardRunning && (isExcluded || activeSourceIsExcluded) {
            lastPasteboardChangeCount = pasteboardProvider().changeCount
        }
        activeSourceIsExcluded = isExcluded
        updateRuntimeStatus(excludedApplication: isExcluded ? application : nil)
    }

    private func receiveScreenshot(_ url: URL, application: AutoCaptureSourceApplication?, generation: UInt) {
        guard isScreenshotsRunning, settings.isScreenshotsEnabled,
              isSessionGenerationCurrent(generation) else { return }
        if settings.isExcluded(bundleIdentifier: application?.bundleIdentifier) {
            settings.setStatus(.sourceApplicationExcluded(application?.name ?? "Excluded application"))
            return
        }
        if case .sourceApplicationExcluded = settings.status {
            updateRuntimeStatus()
        }
        guard let snapshot = AutoCapturePasteboardSnapshot.file(at: url) else {
            report(AutoCaptureServiceError.unreadableClipboard)
            return
        }
        let fingerprint = AutoCaptureFingerprint.image(at: url)
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
                            fingerprint: fingerprint, generation: generation,
                            screenshotGeneration: screenshotGeneration,
                            clipboardGeneration: clipboardGeneration)
    }

    private func delayClipboardImage(_ event: PendingEvent, fingerprint: AutoCaptureFingerprint) {
        let pendingID = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: clipboardImageDelay)
            guard !Task.isCancelled,
                  let pending = delayedClipboardImages.removeValue(forKey: pendingID) else { return }
            guard isEventCurrent(pending.event) else {
                pending.event.snapshot.clear()
                return
            }
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
        guard isEventCurrent(event) else {
            event.snapshot.clear()
            return
        }
        queue.append(event)
        processNextEventIfPossible()
    }

    private func processNextEventIfPossible() {
        guard !isProcessingEvent, !queue.isEmpty else { return }
        let event = queue.removeFirst()
        guard isEventCurrent(event) else {
            event.snapshot.clear()
            processNextEventIfPossible()
            return
        }
        if isClipboardRunning && isScreenshotsRunning, let fingerprint = event.fingerprint,
           fingerprintHistory.isOppositeChannelDuplicate(fingerprint, origin: event.origin, at: event.receivedAt) {
            event.snapshot.clear()
            processNextEventIfPossible()
            return
        }

        isProcessingEvent = true
        input.receive(
            event.snapshot.pasteboard,
            at: event.receivedAt,
            timeZone: event.timeZone,
            receipt: event.receipt,
            fileURLTransfer: event.snapshot.fileURLTransfer,
            commitGuard: { [weak self] in
                self?.isEventCurrent(event) == true
            }
        ) { [weak self] captures, failures in
            event.snapshot.clear()
            guard let self else { return }
            self.isProcessingEvent = false
            if self.isEventCurrent(event) {
                if !captures.isEmpty {
                    if let fingerprint = event.fingerprint {
                        // Keep the clipboard fallback until the screenshot has
                        // actually committed; disabling its channel or a failed
                        // file import must not discard both representations.
                        if event.origin == .automaticScreenshot {
                            self.cancelDelayedClipboardImages(matching: fingerprint)
                        }
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
        guard applicationActivationObserver == nil else { return }
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
        stopClipboardRuntime()
        removeApplicationActivationObserver()
        stopScreenshotRuntime()
        screenshotStatus = settings.isScreenshotsEnabled ? status : .disabled
        activeSourceIsExcluded = false
        settings.setStatus(status)
    }

    private func removeApplicationActivationObserver() {
        if let observer = applicationActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            applicationActivationObserver = nil
        }
    }

    private func stopClipboardRuntime() {
        clipboardGeneration &+= 1
        isClipboardRunning = false
        pollTimer?.invalidate()
        pollTimer = nil
        lastPasteboardChangeCount = nil
        for pending in delayedClipboardImages.values {
            pending.task.cancel()
            pending.event.snapshot.clear()
        }
        delayedClipboardImages.removeAll()
        discardQueuedEvents(origin: .automaticClipboard)
        fingerprintHistory.reset()
    }

    private func stopScreenshotRuntime() {
        screenshotGeneration &+= 1
        isScreenshotsRunning = false
        screenshotMonitor?.stop()
        screenshotMonitor = nil
        discardQueuedEvents(origin: .automaticScreenshot)
        fingerprintHistory.reset()
        releaseFolderAccess()
    }

    private func discardQueuedEvents(origin: CaptureOrigin) {
        for event in queue where event.origin == origin { event.snapshot.clear() }
        queue.removeAll { $0.origin == origin }
    }

    private func isEventCurrent(_ event: PendingEvent) -> Bool {
        guard isSessionGenerationCurrent(event.generation) else { return false }
        if event.origin == .automaticScreenshot {
            return settings.isScreenshotsEnabled && isScreenshotsRunning
                && event.screenshotGeneration == screenshotGeneration
        }
        return settings.isClipboardEnabled && isClipboardRunning
            && event.clipboardGeneration == clipboardGeneration
    }

    private func updateRuntimeStatus(excludedApplication: AutoCaptureSourceApplication? = nil) {
        if isRunning {
            settings.setStatus(excludedApplication.map {
                .sourceApplicationExcluded($0.name ?? "Excluded application")
            } ?? .monitoring)
        } else {
            settings.setStatus(screenshotStatus)
        }
    }

    var overallStatusText: String {
        guard settings.isEnabled else { return "Off · choose what to capture" }
        if settings.isPaused { return "Paused · existing captures remain" }
        if isClipboardRunning && isScreenshotsRunning { return "Clipboard and screenshots active" }
        if isClipboardRunning {
            return settings.isScreenshotsEnabled
                ? "Clipboard active · screenshots need folder access" : "Clipboard active"
        }
        if isScreenshotsRunning { return "Screenshots active" }
        switch settings.status {
        case .permissionRequired: return "Screenshots waiting for a folder"
        case .permissionRevoked: return "Screenshots need folder access"
        case .failed(let message): return "Needs attention · \(message)"
        default: return "Ready to capture"
        }
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
    let screenshotGeneration: UInt
    let clipboardGeneration: UInt
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
