import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
private final class FakeScreenshotMonitor: ScreenshotFolderMonitoring {
    private struct ActivitySample {
        let application: AutoCaptureSourceApplication?
    }

    var sourceApplicationAtDirectoryActivity: (() -> AutoCaptureSourceApplication?)?
    var onNewScreenshot: ((URL, AutoCaptureSourceApplication?) -> Void)?
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
        activitySample = ActivitySample(application: sourceApplicationAtDirectoryActivity?())
    }

    func emitSettled(_ url: URL) {
        guard isRunning else { return }
        let application = activitySample?.application
        activitySample = nil
        onNewScreenshot?(url, application)
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
    static func main() async throws {
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
        try expect(!service.isRunning && settings.isEnabled && settings.status == .permissionRequired,
                   "Enabling without a folder grant exposes the missing-permission state")
        service.setEnabled(false)

        settings.setScreenshotFolderBookmark(Data("fixture-bookmark".utf8))
        service.setEnabled(true)
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
        writeString("A private automatic clipboard fixture", to: privateBoard)
        service.pollNow()
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
        try expect(settings.isEnabled && defaults.bool(forKey: AutoCaptureSettings.enabledKey),
                   "Enabled state is persisted")
        try expect(AutoCaptureSettings(defaults: defaults, ownBundleIdentifier: "com.dabin.mac").status == .ready,
                   "A persisted monitoring status relaunches as ready rather than falsely active")

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
        writePNG(screenshotData, to: privateBoard)
        service.pollNow()
        fakeMonitor.emit(screenshotURL)
        try await waitUntil { savedActions.count == actionsBeforeDedupe + 1 }
        try await Task.sleep(for: .milliseconds(350))
        try expect(savedActions.count == actionsBeforeDedupe + 1,
                   "Clipboard and screenshot-folder versions of one image create one action")
        let screenshotAction = savedActions.last!
        try expect(screenshotAction.origin == .automaticScreenshot
                   && screenshotAction.captures.first?.captureOrigin == .automaticScreenshot,
                   "The file-backed screenshot wins the cross-channel duplicate race")

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
        try await waitUntil { !service.isRunning && failures.count > failuresBeforeRevocation }
        try expect(settings.isEnabled && settings.status == .permissionRevoked,
                   "A lost screenshot-folder grant stops monitoring and exposes the revoked state")

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
        var sourceSampleCount = 0
        var monitoredNames: [String] = []
        var monitoredSourceBundleIdentifiers: [String: String] = [:]
        concreteMonitor.sourceApplicationAtDirectoryActivity = {
            sourceSampleCount += 1
            return monitorSource
        }
        concreteMonitor.onNewScreenshot = { url, application in
            monitoredNames.append(url.lastPathComponent)
            monitoredSourceBundleIdentifiers[url.lastPathComponent] = application?.bundleIdentifier
        }
        try concreteMonitor.start()
        try await Task.sleep(for: .milliseconds(100))
        try expect(monitoredNames.isEmpty, "Screenshot monitoring baselines existing files")
        try pngData(red: 0.8).write(to: monitorFolder.appendingPathComponent("new.png"), options: .atomic)
        try await waitUntil { sourceSampleCount > 0 }
        monitorSource = AutoCaptureSourceApplication(name: "Preview", bundleIdentifier: "com.apple.Preview")
        try await waitUntil { monitoredNames.contains("new.png") }
        try expect(monitoredNames == ["new.png"]
                   && monitoredSourceBundleIdentifiers["new.png"] == "com.apple.Notes",
                   "A complete screenshot emits once with the app sampled at the first directory activity")

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
