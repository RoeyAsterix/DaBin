import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
private final class FakeScreenshotMonitor: ScreenshotFolderMonitoring {
    private struct ActivitySample {
        let application: AutoCaptureSourceApplication?
        let projectName: String?
    }

    var sourceApplicationAtDirectoryActivity: (() -> AutoCaptureSourceApplication?)?
    var projectAtDirectoryActivity: (() -> String?)?
    var onNewScreenshot: ((URL, AutoCaptureSourceApplication?, String?) -> Void)?
    var onFailure: ((Error) -> Void)?
    private(set) var isRunning = false
    var startError: Error?
    private var activitySample: ActivitySample?

    func start() throws {
        if let startError { throw startError }
        isRunning = true
    }

    func stop() {
        isRunning = false
        activitySample = nil
    }

    func beginActivity() {
        guard isRunning, activitySample == nil else { return }
        activitySample = ActivitySample(application: sourceApplicationAtDirectoryActivity?(),
                                        projectName: projectAtDirectoryActivity?())
    }

    func emitSettled(_ url: URL) {
        guard isRunning else { return }
        let application = activitySample?.application
        let projectName = activitySample?.projectName
        activitySample = nil
        onNewScreenshot?(url, application, projectName)
    }

    func emit(_ url: URL) {
        beginActivity()
        emitSettled(url)
    }

    func fail(_ error: Error) { if isRunning { onFailure?(error) } }
}

@main
struct AutoCaptureServiceTests {
    @MainActor private static var checks = 0

    @MainActor
    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard condition() else {
            throw NSError(domain: "DaBinAutoCaptureServiceTests", code: checks,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    @MainActor
    private static func waitUntil(timeout: TimeInterval = 3,
                                  _ condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw NSError(domain: "DaBinAutoCaptureServiceTests", code: 999,
                      userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for an automatic capture."])
    }

    private static func temporaryDirectory(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DaBin-AutoCapture-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func pngData(red: CGFloat = 0.45) throws -> Data {
        guard let context = CGContext(data: nil, width: 24, height: 16, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw NSError(domain: "DaBinAutoCaptureServiceTests", code: 2)
        }
        context.setFillColor(CGColor(red: red, green: 0.25, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 24, height: 16))
        guard let painted = context.makeImage() else {
            throw NSError(domain: "DaBinAutoCaptureServiceTests", code: 3)
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "DaBinAutoCaptureServiceTests", code: 4)
        }
        CGImageDestinationAddImage(destination, painted, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "DaBinAutoCaptureServiceTests", code: 5)
        }
        return data as Data
    }

    @discardableResult
    private static func writeString(_ value: String, to pasteboard: NSPasteboard) -> Int {
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        return pasteboard.changeCount
    }

    @discardableResult
    private static func writePNG(_ data: Data, to pasteboard: NSPasteboard) -> Int {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setData(data, forType: .png)
        pasteboard.writeObjects([item])
        return pasteboard.changeCount
    }

    @MainActor
    private static func migrationChecks() throws {
        let suiteName = "DaBin.AutoCaptureMigration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let fresh = AutoCaptureSettings(defaults: defaults)
        try expect(!fresh.isClipboardEnabled && !fresh.isScreenshotsEnabled && !fresh.isEnabled,
                   "Fresh installs leave both channels off")

        defaults.set(true, forKey: AutoCaptureSettings.enabledKey)
        defaults.set(true, forKey: AutoCaptureSettings.pausedKey)
        defaults.set(["com.example.private"], forKey: AutoCaptureSettings.exclusionsKey)
        defaults.set(Data("kept bookmark".utf8), forKey: AutoCaptureSettings.screenshotFolderBookmarkKey)
        defaults.set(true, forKey: AutoCaptureSettings.privacyExplanationAcknowledgedKey)
        let legacy = AutoCaptureSettings(defaults: defaults)
        try expect(legacy.isClipboardEnabled && legacy.isScreenshotsEnabled && legacy.isPaused
                   && legacy.status == .paused,
                   "An existing enabled legacy preference preserves both sources and pause")
        try expect(legacy.screenshotFolderBookmark == Data("kept bookmark".utf8)
                   && legacy.isExcluded(bundleIdentifier: "com.example.private")
                   && legacy.hasAcknowledgedPrivacyExplanation,
                   "Migration preserves authorization, exclusions and privacy acknowledgement")
        try expect(defaults.bool(forKey: AutoCaptureSettings.clipboardEnabledKey)
                   && defaults.bool(forKey: AutoCaptureSettings.screenshotsEnabledKey),
                   "Legacy choices migrate durably only once")
        legacy.setScreenshotsEnabled(false)
        let restored = AutoCaptureSettings(defaults: defaults)
        try expect(restored.isClipboardEnabled && !restored.isScreenshotsEnabled && restored.isPaused,
                   "A later channel choice overrides the legacy aggregate enabled value")

        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(false, forKey: AutoCaptureSettings.enabledKey)
        defaults.set(true, forKey: AutoCaptureSettings.pausedKey)
        let disabled = AutoCaptureSettings(defaults: defaults)
        try expect(!disabled.isEnabled && !disabled.isClipboardEnabled
                   && !disabled.isScreenshotsEnabled && !disabled.isPaused
                   && !defaults.bool(forKey: AutoCaptureSettings.pausedKey),
                   "Legacy disabled state never opts into a channel and clears stale pause")

        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: AutoCaptureSettings.enabledKey)
        defaults.set(false, forKey: AutoCaptureSettings.clipboardEnabledKey)
        let partial = AutoCaptureSettings(defaults: defaults)
        try expect(!partial.isClipboardEnabled && !partial.isScreenshotsEnabled,
                   "An explicit channel preference prevents missing keys from inheriting legacy opt-in")
    }

    @MainActor
    private static func independentChannelChecks() async throws {
        let suiteName = "DaBin.AutoCaptureChannels.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let root = try temporaryDirectory("IndependentChannels")
        defer { try? FileManager.default.removeItem(at: root) }
        let screenshots = try temporaryDirectory("IndependentScreenshots")
        defer { try? FileManager.default.removeItem(at: screenshots) }
        let board = NSPasteboard(name: .init("DaBin.AutoCaptureChannels.\(UUID().uuidString)"))
        defer { board.clearContents() }
        writeString("Already on clipboard", to: board)
        let store = try CaptureStore(root: root)
        let settings = AutoCaptureSettings(defaults: defaults)
        let monitor = FakeScreenshotMonitor()
        var clipboardReads = 0
        var folderResolutions = 0
        var staleBookmark = false
        let service = AutoCaptureService(
            settings: settings, input: InputService(store: store),
            pasteboardProvider: { clipboardReads += 1; return board },
            sourceApplicationProvider: { AutoCaptureSourceApplication(name: "Notes", bundleIdentifier: "com.apple.Notes") },
            screenshotMonitorFactory: { _ in monitor },
            bookmarkCreator: { Data($0.path.utf8) },
            bookmarkResolver: { _ in folderResolutions += 1; return (screenshots, staleBookmark) },
            pollInterval: 60, clipboardImageDelay: .milliseconds(160)
        )
        defer { service.shutdown() }
        service.setClipboardEnabled(true)
        try expect(service.isClipboardRunning && !service.isScreenshotsRunning
                   && folderResolutions == 0 && clipboardReads == 1 && store.captures.isEmpty,
                   "Clipboard alone starts without folder access and seeds the existing content")
        writeString("Clipboard without any folder grant", to: board)
        service.pollNow()
        try await waitUntil { store.captures.count == 1 }

        service.setScreenshotsEnabled(true)
        try expect(service.isRunning && service.isClipboardRunning && !service.isScreenshotsRunning
                   && service.screenshotStatus == .permissionRequired,
                   "Missing screenshot access leaves clipboard capture active")
        writeString("Clipboard while screenshots wait for access", to: board)
        service.pollNow()
        try await waitUntil { store.captures.count == 2 }
        service.setClipboardEnabled(false)
        let readsBeforeScreenshotOnly = clipboardReads
        try expect(!service.isRunning && settings.status == .permissionRequired,
                   "Screenshot-only mode waits for its grant")
        try service.authorizeScreenshotFolder(screenshots)
        try expect(service.isScreenshotsRunning && !service.isClipboardRunning
                   && clipboardReads == readsBeforeScreenshotOnly,
                   "Screenshot-only capture starts without touching clipboard")
        service.applicationDidActivate(AutoCaptureSourceApplication(name: "Bitwarden", bundleIdentifier: "com.bitwarden.desktop"))
        service.applicationDidActivate(AutoCaptureSourceApplication(name: "Notes", bundleIdentifier: "com.apple.Notes"))
        service.pollNow()
        try expect(clipboardReads == readsBeforeScreenshotOnly,
                   "App activation and explicit polling cannot read a disabled clipboard channel")
        let imageURL = screenshots.appendingPathComponent("independent.png")
        try pngData(red: 0.73).write(to: imageURL)
        monitor.emit(imageURL)
        try await waitUntil { store.captures.count == 3 }
        try expect(store.captures.first(where: { $0.captureOrigin == .automaticScreenshot }) != nil,
                   "Screenshot-only capture commits a screenshot receipt")

        monitor.emit(imageURL)
        let obsoleteScreenshotCallback = monitor.onNewScreenshot
        service.setScreenshotsEnabled(false)
        service.setScreenshotsEnabled(true)
        obsoleteScreenshotCallback?(imageURL, nil, nil)
        try await Task.sleep(for: .milliseconds(180))
        try expect(store.captures.count == 3,
                   "Disabling and immediately restarting screenshots cancels pending events and obsolete callbacks")

        service.setClipboardEnabled(true)
        writePNG(try pngData(red: 0.37), to: board)
        service.pollNow()
        service.setClipboardEnabled(false)
        try await Task.sleep(for: .milliseconds(260))
        try expect(store.captures.count == 3 && service.isScreenshotsRunning,
                   "Disabling clipboard cancels its delayed image while screenshots stay selected and active")
        writeString("Copied while clipboard channel was off", to: board)
        service.setClipboardEnabled(true)
        service.pollNow()
        try await Task.sleep(for: .milliseconds(80))
        try expect(store.captures.count == 3,
                   "Enabling clipboard again seeds its counter rather than importing content from while off")

        monitor.emit(imageURL)
        writeString("Clipboard survives screenshot permission loss", to: board)
        service.pollNow()
        monitor.fail(NSError(domain: "DaBinChannels", code: 1))
        try await waitUntil { store.captures.count == 4 }
        try expect(service.isClipboardRunning && !service.isScreenshotsRunning
                   && service.screenshotStatus == .permissionRevoked
                   && store.captures.contains(where: { $0.originalText == "Clipboard survives screenshot permission loss" }),
                   "Screenshot failure cancels its pending commit without canceling queued clipboard work")

        staleBookmark = true
        service.shutdown()
        service.start()
        try expect(service.isClipboardRunning && !service.isScreenshotsRunning
                   && service.screenshotStatus == .permissionRevoked,
                   "A stale bookmark on relaunch does not prevent clipboard startup")
        staleBookmark = false
        monitor.startError = NSError(domain: "DaBinChannels", code: 2)
        service.shutdown()
        service.start()
        try expect(service.isClipboardRunning && !service.isScreenshotsRunning,
                   "A screenshot monitor startup failure leaves clipboard running")
        monitor.startError = nil
        try service.authorizeScreenshotFolder(screenshots)
        try expect(service.isScreenshotsRunning && service.isClipboardRunning,
                   "Choosing a new folder recovers screenshots alongside clipboard")
        service.removeScreenshotFolderAuthorization()
        try expect(service.isClipboardRunning && !service.isScreenshotsRunning
                   && service.screenshotStatus == .permissionRequired,
                   "Removing folder access does not disable clipboard or forget selected sources")
        service.pause()
        service.setScreenshotsEnabled(false)
        service.setScreenshotsEnabled(true)
        try expect(settings.isPaused && !service.isRunning,
                   "Changing selected channels while paused does not resume either channel")
        writeString("Copied while all selected sources paused", to: board)
        service.resume()
        service.pollNow()
        try await Task.sleep(for: .milliseconds(80))
        try expect(store.captures.count == 4 && service.isClipboardRunning,
                   "Shared resume reseeds clipboard even when screenshots are degraded")
        writeString("Clipboard work survives changing screenshot selection", to: board)
        service.pollNow()
        let readsBeforeUnrelatedChange = clipboardReads
        service.setScreenshotsEnabled(false)
        try await waitUntil { store.captures.count == 5 }
        try expect(clipboardReads == readsBeforeUnrelatedChange && service.isClipboardRunning,
                   "Changing screenshot selection neither cancels pending clipboard work nor reseeds clipboard")
        try service.authorizeScreenshotFolder(screenshots)
        service.setScreenshotsEnabled(true)
        monitor.emit(imageURL)
        service.setClipboardEnabled(false)
        try await waitUntil { store.captures.count == 6 }
        try expect(service.isScreenshotsRunning && !service.isClipboardRunning,
                   "Disabling clipboard preserves a screenshot already waiting to commit")
        service.setClipboardEnabled(true)
        let fallbackImage = try pngData(red: 0.21)
        try fallbackImage.write(to: imageURL)
        writePNG(fallbackImage, to: board)
        service.pollNow()
        monitor.emit(imageURL)
        service.setScreenshotsEnabled(false)
        try await waitUntil { store.captures.count == 7 }
        try expect(store.captures.filter { $0.captureOrigin == .automaticClipboard && $0.kind == .image }.count == 1,
                   "Canceling a screenshot before commit preserves its pending clipboard representation")
        service.setEnabled(false)
        try expect(!settings.isEnabled && !settings.isClipboardEnabled && !settings.isScreenshotsEnabled
                   && !service.isRunning && !settings.isPaused,
                   "Explicit master disable stops and clears both choices")
        service.setEnabled(true)
        try expect(!service.isRunning && !settings.isEnabled,
                   "A later master enable cannot resurrect disabled source choices")
    }

    @MainActor
    static func main() async throws {
        try migrationChecks()
        try await independentChannelChecks()
        let suiteName = "DaBin.AutoCaptureServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let privateBoard = NSPasteboard(name: .init("DaBin.AutoCaptureTests.\(UUID().uuidString)"))
        privateBoard.clearContents()
        writeString("Content already copied before launch", to: privateBoard)
        var pasteboardProviderCalls = 0
        let root = try temporaryDirectory("Archive")
        defer { try? FileManager.default.removeItem(at: root) }
        let screenshotFolder = try temporaryDirectory("Screenshots")
        defer { try? FileManager.default.removeItem(at: screenshotFolder) }
        let store = try CaptureStore(root: root)
        let input = InputService(store: store)
        let settings = AutoCaptureSettings(defaults: defaults, ownBundleIdentifier: "com.dabin.mac")
        var source = AutoCaptureSourceApplication(name: "Notes", bundleIdentifier: "com.apple.Notes")
        var selectedProject: String?
        let fakeMonitor = FakeScreenshotMonitor()
        let service = AutoCaptureService(
            settings: settings,
            input: input,
            pasteboardProvider: {
                pasteboardProviderCalls += 1
                return privateBoard
            },
            sourceApplicationProvider: { source },
            screenshotMonitorFactory: { _ in fakeMonitor },
            bookmarkCreator: { Data($0.path.utf8) },
            bookmarkResolver: { _ in (screenshotFolder, false) },
            pollInterval: 60,
            clipboardImageDelay: .milliseconds(180),
            duplicateInterval: 2
        )
        service.projectProvider = { selectedProject }

        try expect(!settings.isEnabled && !settings.isPaused && settings.status == .disabled,
                   "Auto Capture defaults off and unpaused")
        try expect(!settings.hasAcknowledgedPrivacyExplanation,
                   "The privacy explanation starts unacknowledged")
        settings.acknowledgePrivacyExplanation()
        try expect(settings.hasAcknowledgedPrivacyExplanation
                   && defaults.bool(forKey: AutoCaptureSettings.privacyExplanationAcknowledgedKey),
                   "First-enable privacy acknowledgement is durable")
        try expect(defaults.object(forKey: AutoCaptureSettings.enabledKey) == nil,
                   "Acknowledging privacy does not silently opt in")
        try expect(settings.isExcluded(bundleIdentifier: "com.bitwarden.desktop")
                   && settings.isExcluded(bundleIdentifier: "com.dabin.mac"),
                   "Password managers and DaBin are excluded by default")
        service.start()
        try expect(pasteboardProviderCalls == 0 && !service.isRunning && !fakeMonitor.isRunning,
                   "Starting while disabled does not touch the clipboard or folder monitor")
        service.setEnabled(true)
        try expect(!service.isRunning && !settings.isEnabled,
                   "Master enable cannot select channels on the user's behalf")
        service.setScreenshotsEnabled(true)
        try expect(!service.isRunning && settings.isEnabled && settings.status == .permissionRequired,
                   "Screenshot-only opt-in exposes missing folder access without reading clipboard")
        service.setEnabled(false)

        settings.setScreenshotFolderBookmark(Data("fixture-bookmark".utf8))
        settings.setClipboardEnabled(true)
        settings.setScreenshotsEnabled(true)
        service.start()
        try expect(service.isRunning && fakeMonitor.isRunning && settings.status == .monitoring,
                   "The explicit opt-in starts both monitors")
        try expect(pasteboardProviderCalls == 1 && store.captures.isEmpty,
                   "Startup reads only changeCount and never imports existing clipboard contents")
        service.pollNow()
        try await Task.sleep(for: .milliseconds(80))
        try expect(store.captures.isEmpty, "The seeded clipboard value remains ignored")

        var savedActions: [AutoCaptureSavedAction] = []
        var committedActions: [AutoCaptureSavedAction] = []
        var failures: [String] = []
        service.onCommitted = { committedActions.append($0) }
        service.onSaved = { action in
            // The callback must never run before the committed capture is visible.
            if action.captures.allSatisfy({ saved in store.captures.contains(where: { $0.id == saved.id }) }) {
                savedActions.append(action)
            }
        }
        service.onFailure = { failures.append($0) }
        selectedProject = "Launch project"
        writeString("A private automatic clipboard fixture", to: privateBoard)
        service.pollNow()
        // Navigation after observation must not redirect an event already queued
        // through the asynchronous import pipeline.
        selectedProject = "Different project"
        try await waitUntil { savedActions.count == 1 }
        try expect(committedActions.count == 1,
                   "A fully saved action updates the feed and success channel once")
        let clipboardCapture = try XCTUnwrap(savedActions.first?.captures.first)
        try expect(clipboardCapture.captureOrigin == .automaticClipboard
                   && clipboardCapture.automaticActionID == savedActions[0].actionID,
                   "Clipboard imports keep one durable automatic action receipt")
        try expect(clipboardCapture.sourceApplicationName == "Notes"
                   && clipboardCapture.sourceApplicationBundleIdentifier == "com.apple.Notes",
                   "The available source application is stored on the capture")
        try expect(clipboardCapture.projectName == "Launch project"
                   && savedActions[0].projectName == "Launch project",
                   "Auto Capture snapshots the selected project when the copy is observed")
        selectedProject = nil
        try expect(settings.isEnabled && defaults.bool(forKey: AutoCaptureSettings.enabledKey),
                   "Enabled state is persisted")
        try expect(AutoCaptureSettings(defaults: defaults, ownBundleIdentifier: "com.dabin.mac").status == .ready,
                   "A persisted monitoring status relaunches as ready rather than falsely active")

        let countBeforeShutdown = store.captures.count
        service.shutdown()
        writeString("Copied after the application began terminating", to: privateBoard)
        service.pollNow()
        fakeMonitor.emit(screenshotFolder.appendingPathComponent("ignored-after-shutdown.png"))
        try await Task.sleep(for: .milliseconds(100))
        try expect(!service.isRunning && !fakeMonitor.isRunning && settings.status == .ready,
                   "Termination shutdown stops clipboard polling and the screenshot-folder monitor")
        try expect(store.captures.count == countBeforeShutdown,
                   "No automatic action can commit after termination shutdown")
        service.start()
        try expect(service.isRunning && fakeMonitor.isRunning && settings.status == .monitoring,
                   "The shutdown fixture can restart without changing the persisted Auto Capture preference")
        service.pollNow()
        try await Task.sleep(for: .milliseconds(80))
        try expect(store.captures.count == countBeforeShutdown,
                   "Restart after shutdown seeds the clipboard counter instead of importing intervening content")

        // InputService schedules its work on the main actor. Pausing immediately
        // after observation invalidates the commit guard before durable storage.
        let countBeforePause = store.captures.count
        writeString("Must be cancelled before commit", to: privateBoard)
        service.pollNow()
        service.setPaused(true)
        try await Task.sleep(for: .milliseconds(150))
        try expect(store.captures.count == countBeforePause && savedActions.count == 1,
                   "Pause immediately blocks an observed but uncommitted action")
        try expect(!service.isRunning && settings.isPaused && settings.status == .paused,
                   "Paused state is visible and persisted")
        service.setPaused(false)
        service.pollNow()
        try await Task.sleep(for: .milliseconds(80))
        try expect(store.captures.count == countBeforePause,
                   "Resume reseeds changeCount instead of importing clipboard contents copied while paused")

        source = AutoCaptureSourceApplication(name: "Bitwarden", bundleIdentifier: "com.bitwarden.desktop")
        writeString("Excluded secret fixture", to: privateBoard)
        service.pollNow()
        try await Task.sleep(for: .milliseconds(100))
        try expect(store.captures.count == countBeforePause
                   && settings.status == .sourceApplicationExcluded("Bitwarden"),
                   "Excluded applications consume the counter without loading or saving their content")
        source = AutoCaptureSourceApplication(name: "Notes", bundleIdentifier: "com.apple.Notes")
        service.pollNow()
        try await Task.sleep(for: .milliseconds(60))
        try expect(store.captures.count == countBeforePause,
                   "An excluded copy is not imported after switching applications")

        source = AutoCaptureSourceApplication(name: "Bitwarden", bundleIdentifier: "com.bitwarden.desktop")
        service.applicationDidActivate(source)
        writeString("Excluded copy followed by an immediate app switch", to: privateBoard)
        source = AutoCaptureSourceApplication(name: "Notes", bundleIdentifier: "com.apple.Notes")
        service.applicationDidActivate(source)
        service.pollNow()
        try await Task.sleep(for: .milliseconds(80))
        try expect(store.captures.count == countBeforePause,
                   "Leaving an excluded app reseeds the counter before the next poll")

        writeString("Capture after resume", to: privateBoard)
        service.pollNow()
        try await waitUntil { savedActions.count == 2 }
        try expect(settings.status == .monitoring, "Successful polling restores the monitoring status")

        let excludedScreenshotURL = screenshotFolder.appendingPathComponent("Excluded source screenshot.png")
        try pngData(red: 0.2).write(to: excludedScreenshotURL, options: .atomic)
        let actionsBeforeExcludedScreenshot = savedActions.count
        source = AutoCaptureSourceApplication(name: "Bitwarden", bundleIdentifier: "com.bitwarden.desktop")
        fakeMonitor.beginActivity()
        source = AutoCaptureSourceApplication(name: "Notes", bundleIdentifier: "com.apple.Notes")
        fakeMonitor.emitSettled(excludedScreenshotURL)
        try await Task.sleep(for: .milliseconds(120))
        try expect(savedActions.count == actionsBeforeExcludedScreenshot
                   && committedActions.count == actionsBeforeExcludedScreenshot
                   && settings.status == .sourceApplicationExcluded("Bitwarden"),
                   "Screenshot exclusion uses the app sampled at directory activity, not the app active after settling")

        let firstCopiedFile = root.appendingPathComponent("Auto Capture first file.txt")
        let secondCopiedFile = root.appendingPathComponent("Auto Capture second file.pdf")
        try Data("first copied file".utf8).write(to: firstCopiedFile)
        try Data("second copied file".utf8).write(to: secondCopiedFile)
        privateBoard.clearContents()
        try expect(privateBoard.writeObjects([firstCopiedFile as NSURL, secondCopiedFile as NSURL]),
                   "The automatic file fixture publishes native NSURL readers")
        let actionsBeforeFiles = savedActions.count
        service.pollNow()
        // The system board can change immediately after polling. Import must use
        // the frozen content plus retained native transfer readers from above.
        privateBoard.clearContents()
        try await waitUntil { savedActions.count == actionsBeforeFiles + 1 }
        let copiedFileAction = savedActions.last!
        try expect(copiedFileAction.captures.compactMap(\.sourceFilePath)
                   == [firstCopiedFile.standardizedFileURL.path, secondCopiedFile.standardizedFileURL.path],
                   "Automatic native file copies retain access and preserve Finder item order")
        let copiedFileCards = CaptureCardGroup.cards(from: copiedFileAction.captures)
        try expect(copiedFileAction.captures.count == 2
                   && Set(copiedFileAction.captures.compactMap(\.automaticActionID)) == [copiedFileAction.actionID]
                   && copiedFileCards.count == 1 && copiedFileCards[0].captures.count == 2,
                   "Files copied together remain one automatic action and caption card")

        let screenshotData = try pngData()
        let screenshotURL = screenshotFolder.appendingPathComponent("Screen Shot fixture.png")
        try screenshotData.write(to: screenshotURL, options: .atomic)
        let actionsBeforeDedupe = savedActions.count
        selectedProject = "Screenshot observation project"
        writePNG(screenshotData, to: privateBoard)
        service.pollNow()
        fakeMonitor.beginActivity()
        selectedProject = "Later project"
        fakeMonitor.emitSettled(screenshotURL)
        try await waitUntil { savedActions.count == actionsBeforeDedupe + 1 }
        try await Task.sleep(for: .milliseconds(350))
        try expect(savedActions.count == actionsBeforeDedupe + 1,
                   "Clipboard and screenshot-folder versions of one image create one action")
        let screenshotAction = savedActions.last!
        try expect(screenshotAction.origin == .automaticScreenshot
                   && screenshotAction.captures.first?.captureOrigin == .automaticScreenshot
                   && screenshotAction.projectName == "Screenshot observation project"
                   && screenshotAction.captures.first?.projectName == "Screenshot observation project",
                   "The file-backed screenshot wins dedupe without changing the project sampled at directory activity")
        selectedProject = nil

        let successCount = savedActions.count
        fakeMonitor.emit(screenshotFolder.appendingPathComponent("missing.png"))
        try await waitUntil { !failures.isEmpty }
        try expect(savedActions.count == successCount,
                   "A failed import never triggers the success callback or robot contract")
        try expect(committedActions.count == successCount,
                   "An action with no durable captures does not update the feed callback")

        let partialSource = root.appendingPathComponent("automatic-partial.txt")
        try Data("durable partial fixture".utf8).write(to: partialSource)
        let missingSource = root.appendingPathComponent("automatic-missing.txt")
        let validItem = NSPasteboardItem()
        validItem.setString(partialSource.absoluteString, forType: .fileURL)
        let missingItem = NSPasteboardItem()
        missingItem.setString(missingSource.absoluteString, forType: .fileURL)
        privateBoard.clearContents()
        try expect(privateBoard.writeObjects([validItem, missingItem]),
                   "The mixed automatic fixture writes to its private pasteboard")
        let failuresBeforePartial = failures.count
        service.pollNow()
        try await waitUntil { committedActions.count == successCount + 1 && failures.count > failuresBeforePartial }
        try expect(savedActions.count == successCount,
                   "A partly failed action updates durable content without triggering success confirmation")
        try expect(committedActions.last?.captures.count == 1,
                   "The durable subset of a partly failed action remains visible in the feed")

        let failuresBeforeRevocation = failures.count
        fakeMonitor.fail(NSError(domain: "DaBinRevokedFolderFixture", code: 1,
                                 userInfo: [NSLocalizedDescriptionKey: "Folder access revoked."]))
        try await waitUntil { !service.isScreenshotsRunning && failures.count > failuresBeforeRevocation }
        try expect(settings.isEnabled && service.isClipboardRunning && service.isRunning
                   && settings.status == .monitoring && service.screenshotStatus == .permissionRevoked,
                   "A lost screenshot-folder grant stops only screenshots and keeps clipboard active")

        let captureCountBeforeDisable = store.captures.count
        service.setEnabled(false)
        writeString("Copied after disable", to: privateBoard)
        service.pollNow()
        fakeMonitor.emit(screenshotURL)
        try await Task.sleep(for: .milliseconds(100))
        try expect(store.captures.count == captureCountBeforeDisable && settings.status == .disabled,
                   "Disabling immediately prevents both clipboard and screenshot actions")
        try expect(!defaults.bool(forKey: AutoCaptureSettings.enabledKey)
                   && !defaults.bool(forKey: AutoCaptureSettings.pausedKey),
                   "Turning Auto Capture off persists a clean disabled state")

        // Exercise the concrete directory watcher separately: its baseline must
        // ignore existing images and emit only a later file.
        let monitorFolder = try temporaryDirectory("MonitorBaseline")
        defer { try? FileManager.default.removeItem(at: monitorFolder) }
        try screenshotData.write(to: monitorFolder.appendingPathComponent("existing.png"), options: .atomic)
        let concreteMonitor = ScreenshotFolderMonitor(folder: monitorFolder, settleDelay: .milliseconds(60))
        var monitorSource = AutoCaptureSourceApplication(name: "Notes", bundleIdentifier: "com.apple.Notes")
        var monitorProject = "Initial screenshot project"
        var sourceSampleCount = 0
        var monitoredNames: [String] = []
        var monitoredSourceBundleIdentifiers: [String: String] = [:]
        var monitoredProjects: [String: String] = [:]
        concreteMonitor.sourceApplicationAtDirectoryActivity = {
            sourceSampleCount += 1
            return monitorSource
        }
        concreteMonitor.projectAtDirectoryActivity = { monitorProject }
        concreteMonitor.onNewScreenshot = { url, application, projectName in
            monitoredNames.append(url.lastPathComponent)
            monitoredSourceBundleIdentifiers[url.lastPathComponent] = application?.bundleIdentifier
            monitoredProjects[url.lastPathComponent] = projectName
        }
        try concreteMonitor.start()
        try await Task.sleep(for: .milliseconds(100))
        try expect(monitoredNames.isEmpty, "Screenshot monitoring baselines existing files")
        try pngData(red: 0.8).write(to: monitorFolder.appendingPathComponent("new.png"), options: .atomic)
        try await waitUntil { sourceSampleCount > 0 }
        monitorSource = AutoCaptureSourceApplication(name: "Preview", bundleIdentifier: "com.apple.Preview")
        monitorProject = "Later screenshot project"
        try await waitUntil { monitoredNames.contains("new.png") }
        try expect(monitoredNames == ["new.png"]
                   && monitoredSourceBundleIdentifiers["new.png"] == "com.apple.Notes"
                   && monitoredProjects["new.png"] == "Initial screenshot project",
                   "A complete screenshot emits once with the app and project sampled at the first directory activity")

        let partialData = try pngData(red: 0.62)
        let splitIndex = partialData.count / 2
        let partialURL = monitorFolder.appendingPathComponent("partial.png")
        try Data(partialData.prefix(splitIndex)).write(to: partialURL)
        try await Task.sleep(for: .milliseconds(240))
        try expect(!monitoredNames.contains("partial.png"),
                   "A stable-size file is not emitted while ImageIO still reports an incomplete decode")

        let partialHandle = try FileHandle(forWritingTo: partialURL)
        _ = try partialHandle.seekToEnd()
        try partialHandle.write(contentsOf: Data(partialData.suffix(from: splitIndex)))
        try partialHandle.close()
        try await waitUntil { monitoredNames.contains("partial.png") }
        try expect(monitoredNames.filter { $0 == "partial.png" }.count == 1,
                   "An incomplete screenshot emits once after its size stabilizes and decoding completes")

        let namesBeforePDF = monitoredNames
        let pdfURL = monitorFolder.appendingPathComponent("not-a-screenshot.pdf")
        try Data("%PDF-1.4\n% ignored by screenshot monitoring\n%%EOF\n".utf8).write(to: pdfURL)
        try await Task.sleep(for: .milliseconds(240))
        try expect(monitoredNames == namesBeforePDF,
                   "The screenshot folder monitor ignores new PDF documents")
        concreteMonitor.stop()

        privateBoard.clearContents()
        print("PASS: \(checks) auto-capture service checks")
    }
}

private func XCTUnwrap<T>(_ value: T?) throws -> T {
    guard let value else {
        throw NSError(domain: "DaBinAutoCaptureServiceTests", code: 998,
                      userInfo: [NSLocalizedDescriptionKey: "Expected a non-nil test value."])
    }
    return value
}
