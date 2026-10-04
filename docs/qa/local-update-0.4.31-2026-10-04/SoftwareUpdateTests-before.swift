import CryptoKit
import Foundation

#if DABIN_DIRECT_UPDATES
@main
@MainActor
private enum SoftwareUpdateTests {
    private final class Box {
        var dataCalls = 0
        var downloadCalls = 0
        var helperChecks = 0
        var launches: [(URL, URL)] = []
    }

    private static var checks = 0

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard condition() else {
            throw NSError(domain: "SoftwareUpdateTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private static func wait(_ message: String, until condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(4)
        while !condition() && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try expect(condition(), message)
    }

    private static func expectHandoffRejected(_ url: URL, allowedDirectory: URL,
                                               _ message: String) throws {
        var rejected = false
        do { _ = try DaBinUpdateHandoff.consume(url, allowedDirectory: allowedDirectory) }
        catch { rejected = true }
        try expect(rejected, message)
    }

    private static func response(_ url: URL, status: Int = 200) -> URLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
    }

    private static func release(bytes: Int64, sha256: String, build: String = "25",
                                assetURL: URL? = nil) -> SoftwareReleaseManifest {
        let version = "0.3.0"
        let name = "DaBin-\(version)-Update.zip"
        return SoftwareReleaseManifest(
            schemaVersion: 1,
            bundleIdentifier: "com.dabin.mac",
            version: version,
            buildNumber: build,
            architecture: "arm64",
            minimumMacOS: "14.0",
            sourceFingerprint: String(repeating: "a", count: 64),
            releasePageURL: URL(string: "https://github.com/RoeyAsterix/DaBin/releases/tag/v\(version)")!,
            asset: SoftwareUpdateAsset(
                name: name,
                url: assetURL ?? URL(string: "https://github.com/RoeyAsterix/DaBin/releases/download/v\(version)/\(name)")!,
                bytes: bytes,
                sha256: sha256
            )
        )
    }

    private static func makeService(root: URL, release: SoftwareReleaseManifest, download: URL,
                                    box: Box, responseURL: URL? = nil) throws -> SoftwareUpdateService {
        let manifestData = try JSONEncoder().encode(release)
        let finalURL = responseURL ?? URL(string: "https://release-assets.githubusercontent.com/github-production-release-asset/test")!
        return SoftwareUpdateService(
            currentVersion: "0.2.2",
            currentBuild: "24",
            manifestURL: URL(string: "https://github.com/RoeyAsterix/DaBin/releases/latest/download/DaBin-update.json")!,
            transport: SoftwareUpdateTransport(
                loadData: { url in
                    box.dataCalls += 1
                    return (manifestData, response(finalURL))
                },
                download: { url in
                    box.downloadCalls += 1
                    return (download, response(finalURL))
                }
            ),
            updatesDirectory: root.appendingPathComponent("Updates"),
            helperURL: root.appendingPathComponent("DaBin Update.app"),
            validateHelper: { _ in box.helperChecks += 1 },
            launchInstaller: { url, handoffURL in box.launches.append((url, handoffURL)) }
        )
    }

    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinUpdateTests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let downloaded = root.appendingPathComponent("download.zip")
        try Data("synthetic verified update".utf8).write(to: downloaded)
        let checksum = try SoftwareUpdateService.sha256(downloaded)
        let size = Int64(try downloaded.resourceValues(forKeys: [.fileSizeKey]).fileSize!)
        let manifest = release(bytes: size, sha256: checksum)
        try manifest.validate()
        try expect(checksum.count == 64, "Streaming SHA-256 produces a complete lowercase digest")
        try expect(SoftwareUpdateConfiguration.compareVersions("0.3.0", "0.2.9") > 0,
                   "Numeric version comparison recognizes a newer release")
        try expect(SoftwareUpdateConfiguration.compareVersions("14.0", "14.0.0") == 0,
                   "Numeric version comparison normalizes missing components")

        let box = Box()
        let service = try makeService(root: root, release: manifest, download: downloaded, box: box)
        try expect(service.phase == .idle && service.canCheck && !service.canInstall,
                   "A configured direct build starts idle and user controlled")
        try expect(service.releasePageURL == SoftwareUpdateConfiguration.latestReleasePageURL,
                   "Settings always has a stable link to the latest GitHub release before a check")
        try await Task.sleep(for: .milliseconds(30))
        try expect(box.dataCalls == 0 && box.downloadCalls == 0,
                   "Constructing the service never contacts GitHub automatically")
        service.checkForUpdates()
        try await wait("A newer GitHub release becomes available") { service.phase == .updateAvailable }
        try expect(box.dataCalls == 1 && service.availableRelease == manifest,
                   "One explicit check reads one manifest and keeps the validated release")
        try expect(service.releasePageURL == manifest.releasePageURL,
                   "An available update links to its validated GitHub release page")
        try expect(service.canInstall && service.message.contains("0.3.0"),
                   "The settings state offers the validated newer release")
        service.downloadAndInstall()
        try await wait("The verified helper opens") { service.phase == .installerOpened }
        try expect(box.downloadCalls == 1 && box.helperChecks == 1 && box.launches.count == 1,
                   "Download, bundled-helper validation and launch each run once")
        let handoff = box.launches[0].1
        try expect(handoff.pathExtension == DaBinUpdateHandoff.fileExtension,
                   "The installer receives a dedicated update-request document")
        let resolved = try DaBinUpdateHandoff.consume(handoff,
            allowedDirectory: root.appendingPathComponent("Updates"))
        try expect(resolved.package == root.appendingPathComponent("Updates/DaBin-0.3.0-Update.zip")
                   && resolved.packageSHA256 == checksum && !FileManager.default.fileExists(atPath: handoff.path),
                   "The one-use handoff resolves only the verified archive and published checksum")
        let retainedChecksum = try SoftwareUpdateService.sha256(root.appendingPathComponent("Updates/DaBin-0.3.0-Update.zip"))
        try expect(retainedChecksum == checksum,
                   "The archive retained for the installer matches the published SHA-256")
        service.cancel()

        let hostileRoot = root.appendingPathComponent("HostileHandoffs")
        try FileManager.default.createDirectory(at: hostileRoot, withIntermediateDirectories: false)
        let hostilePackage = hostileRoot.appendingPathComponent("DaBin-0.3.0-Update.zip")
        try Data("safe test package".utf8).write(to: hostilePackage)
        func request(_ name: String, _ dictionary: [String: Any]) throws -> URL {
            let url = hostileRoot.appendingPathComponent(name)
            let data = try JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys])
            try data.write(to: url, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return url
        }
        let invalidHash = try request("invalid-hash.dabinupdate", [
            "schemaVersion": 1, "packageName": hostilePackage.lastPathComponent,
            "packageSHA256": "not-a-checksum"
        ])
        try expectHandoffRejected(invalidHash, allowedDirectory: hostileRoot,
                                  "A handoff with a malformed checksum fails closed")
        let extraField = try request("extra-field.dabinupdate", [
            "schemaVersion": 1, "packageName": hostilePackage.lastPathComponent,
            "packageSHA256": checksum, "destination": "/Applications/Other.app"
        ])
        try expectHandoffRejected(extraField, allowedDirectory: hostileRoot,
                                  "A handoff cannot smuggle extra installer controls")
        let writable = try request("group-writable.dabinupdate", [
            "schemaVersion": 1, "packageName": hostilePackage.lastPathComponent,
            "packageSHA256": checksum
        ])
        try FileManager.default.setAttributes([.posixPermissions: 0o620], ofItemAtPath: writable.path)
        try expectHandoffRejected(writable, allowedDirectory: hostileRoot,
                                  "A group-writable handoff is rejected")
        let symlinkTarget = try request("symlink-target.dabinupdate", [
            "schemaVersion": 1, "packageName": hostilePackage.lastPathComponent,
            "packageSHA256": checksum
        ])
        let symlinkRequest = hostileRoot.appendingPathComponent("symlink-request.dabinupdate")
        try FileManager.default.createSymbolicLink(at: symlinkRequest, withDestinationURL: symlinkTarget)
        try expectHandoffRejected(symlinkRequest, allowedDirectory: hostileRoot,
                                  "A symbolic-link handoff is rejected")
        let linkedPackage = hostileRoot.appendingPathComponent("DaBin-0.3.1-Update.zip")
        try FileManager.default.createSymbolicLink(at: linkedPackage, withDestinationURL: hostilePackage)
        let linkedPackageRequest = try request("linked-package.dabinupdate", [
            "schemaVersion": 1, "packageName": linkedPackage.lastPathComponent,
            "packageSHA256": checksum
        ])
        try expectHandoffRejected(linkedPackageRequest, allowedDirectory: hostileRoot,
                                  "A symbolic-link update package is rejected")
        let oversized = hostileRoot.appendingPathComponent("oversized.dabinupdate")
        try Data(repeating: 0x61, count: DaBinUpdateHandoff.maximumBytes + 1).write(to: oversized)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: oversized.path)
        try expectHandoffRejected(oversized, allowedDirectory: hostileRoot,
                                  "An oversized handoff is rejected before decoding")
        let outsideRoot = root.appendingPathComponent("OutsideHandoffs")
        try FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: false)
        let outside = outsideRoot.appendingPathComponent("outside.dabinupdate")
        try Data("{}".utf8).write(to: outside)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: outside.path)
        try expectHandoffRejected(outside, allowedDirectory: hostileRoot,
                                  "A handoff outside the allowed update directory is rejected")

        let staleBox = Box()
        let stale = try makeService(root: root.appendingPathComponent("stale"),
                                    release: release(bytes: size, sha256: checksum, build: "24"),
                                    download: downloaded, box: staleBox)
        stale.checkForUpdates()
        try await wait("The installed build is reported current") { stale.phase == .upToDate }
        try expect(!stale.canInstall && staleBox.downloadCalls == 0,
                   "An equal build never offers or downloads a downgrade")
        stale.cancel()

        let badHashBox = Box()
        let badHash = try makeService(root: root.appendingPathComponent("bad-hash"),
                                      release: release(bytes: size, sha256: String(repeating: "0", count: 64)),
                                      download: downloaded, box: badHashBox)
        badHash.checkForUpdates()
        try await wait("The mismatched release is offered before its bytes are fetched") { badHash.phase == .updateAvailable }
        badHash.downloadAndInstall()
        try await wait("A checksum mismatch fails closed") { badHash.phase == .failed }
        try expect(badHashBox.helperChecks == 0 && badHashBox.launches.isEmpty,
                   "An invalid download never reaches or opens the installer")
        try expect(badHash.message.contains("SHA-256"), "Checksum failure is explained without suggesting a security bypass")
        badHash.cancel()

        let evilURL = URL(string: "https://example.com/DaBin-0.3.0-Update.zip")!
        do {
            try release(bytes: size, sha256: checksum, assetURL: evilURL).validate()
            try expect(false, "An external update host must be rejected")
        } catch {
            try expect(error.localizedDescription.contains("GitHub"), "Only the fixed DaBin GitHub release path is trusted")
        }
        do {
            try SoftwareUpdateConfiguration.validateGitHubResponse(response(URL(string: "https://example.com/file")!))
            try expect(false, "A redirected non-GitHub response must be rejected")
        } catch {
            try expect(true, "A redirected non-GitHub response fails closed")
        }
        let disabled = SoftwareUpdateService(
            currentVersion: "0.3.0", currentBuild: "25", manifestURL: nil,
            transport: .live(), updatesDirectory: root, helperURL: root,
            validateHelper: { _ in }, launchInstaller: { _, _ in }
        )
        try expect(!disabled.isDirectChannel && !disabled.canCheck && disabled.phase == .failed,
                   "A build without the fixed feed cannot improvise an update source")
        try expect(disabled.releasePageURL == nil,
                   "A build without the direct channel does not expose a GitHub release link")

        let settingsSource = try String(contentsOfFile: "Sources/DaBin/SettingsScreen.swift", encoding: .utf8)
        guard let updateSection = settingsSource.range(of: "SettingsSoftwareUpdateSection(updates: updates)"),
              let tutorialSection = settingsSource.range(of: "SettingsTutorialSection(runTutorial: runTutorial)"),
              let captureSection = settingsSource.range(of: "Text(\"Automatic capture\")") else {
            try expect(false, "Settings contains its update, tutorial and Capture sections")
            return
        }
        try expect(updateSection.lowerBound < tutorialSection.lowerBound
                   && tutorialSection.lowerBound < captureSection.lowerBound,
                   "Run tutorial sits immediately below Get updates and above Automatic capture")
        try expect(settingsSource.contains("static let title = \"Get updates\"")
                   && settingsSource.contains("settings-software-updates")
                   && settingsSource.contains("Check for DaBin updates")
                   && settingsSource.contains("Download and install the DaBin update")
                   && settingsSource.contains("View the latest DaBin release on GitHub"),
                   "The compact update panel keeps clear controls and accessible names")
        try expect(settingsSource.contains("settings-run-tutorial")
                   && settingsSource.contains("Run DaBin tutorial"),
                   "The Settings tutorial entry has a stable identifier and accessible name")
        let tutorialSteps = DaBinTutorialStep.ordered
        try expect(tutorialSteps.first == .welcome && tutorialSteps.last == .finish
                   && tutorialSteps.count == 13,
                   "The tutorial has one deterministic beginning-to-end sequence")
        for destination in [BoardRoute.inbox, .daily, .weekly, .reminders, .library, .search, .settings] {
            try expect(tutorialSteps.contains { $0.destination == destination },
                       "The tutorial visits the \(destination) workflow")
        }
        try expect(tutorialSteps.allSatisfy { !$0.targetCandidates.isEmpty },
                   "Every tutorial step identifies a real interface target or safe visible fallback")
        try expect(tutorialSteps.contains { $0 == .capture }
                   && tutorialSteps.contains { $0 == .projectRecording }
                   && tutorialSteps.contains { $0 == .automation },
                   "The tutorial covers manual capture, project recording and opt-in automation")
        let boardSource = try String(contentsOfFile: "Sources/DaBin/BoardView.swift", encoding: .utf8)
        try expect(boardSource.contains("overlayPreferenceValue(DaBinTutorialAnchorKey.self)")
                   && boardSource.contains("DaBinTutorialScrim")
                   && boardSource.contains("daBinTutorialAnchor(.captureDestination)"),
                   "The robot spotlights real controls instead of presenting a narration-only walkthrough")
        let compactTutorialLayout = DaBinTutorialStageLayout(
            container: CGSize(width: 380, height: 430),
            focus: CGRect(x: 16, y: 20, width: 160, height: 48)
        )
        try expect(compactTutorialLayout.margin * 2 + compactTutorialLayout.robotSize.width
                   + compactTutorialLayout.gap + compactTutorialLayout.cardWidth <= 380,
                   "The tutorial robot and speech bubble fit the minimum board width")
        let compactRobotCenter = compactTutorialLayout.robotCenter(in: CGSize(width: 380, height: 430))
        try expect(compactRobotCenter.x >= 0 && compactRobotCenter.x <= 380
                   && compactRobotCenter.y >= 0 && compactRobotCenter.y <= 430
                   && compactTutorialLayout.panelAtBottom,
                   "The compact tutorial keeps the robot in bounds opposite a top control")
        print("PASS: \(checks) software update checks; no external network, installed app or user archive used.")
    }
}
#else
/// Intercept every HTTP(S) request made by the Store updater fixture, so a
/// regression is counted and rejected without contacting any remote service.
private final class StoreUpdateNetworkProbe: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var requests = 0

    static var requestCount: Int {
        lock.lock(); defer { lock.unlock() }
        return requests
    }

    override class func canInit(with request: URLRequest) -> Bool {
        ["http", "https"].contains(request.url?.scheme?.lowercased() ?? "")
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.requests += 1; Self.lock.unlock()
        client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
    }
    override func stopLoading() {}
}

@main @MainActor private enum SoftwareUpdateStoreTests {
    private static var checks = 0
    private static func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard value() else {
            throw NSError(domain: "SoftwareUpdateStoreTests", code: checks,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinStoreUpdateTests-\(UUID())")
        let bundleURL = root.appendingPathComponent("Fictional.bundle")
        let contents = bundleURL.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // Even stale direct-channel metadata must not re-enable the updater in
        // a Store-compiled binary. Version values belong to this fixture only.
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.dabin.qa.store-updater.\(UUID().uuidString)",
            "CFBundlePackageType": "BNDL", "CFBundleShortVersionString": "8.7.6", "CFBundleVersion": "543",
            "DaBinDistributionChannel": "github",
            "DaBinUpdateManifestURL": "https://example.invalid/fictional-update.json"
        ]
        let infoURL = contents.appendingPathComponent("Info.plist")
        let bytes = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try bytes.write(to: infoURL)
        guard let bundle = Bundle(url: bundleURL) else { throw CocoaError(.fileReadCorruptFile) }
        try expect(URLProtocol.registerClass(StoreUpdateNetworkProbe.self), "The fixture blocks all updater HTTP(S) requests")
        defer { URLProtocol.unregisterClass(StoreUpdateNetworkProbe.self) }
        let service = SoftwareUpdateService(bundle: bundle)
        try expect(service.currentVersion == "8.7.6" && service.currentBuild == "543",
                   "Store updater reads version metadata from the supplied bundle")
        try expect(service.versionLabel == "DaBin 8.7.6 (543)", "Store updater presents the supplied build accurately")
        try expect(service.phase == .storeManaged, "Store builds begin in the Store-managed phase")
        try expect(!service.isDirectChannel, "Direct-channel metadata cannot enable a Store-compiled updater")
        try expect(!service.canCheck && !service.canInstall && !service.isBusy,
                   "Store builds expose no downloader or installer action")
        try expect(service.availableRelease == nil && service.releasePageURL == nil,
                   "Store builds provide no direct release or external release-page destination")
        let message = service.message
        try expect(message == "Updates for this build are delivered through the Mac App Store.",
                   "Store builds explain where updates are delivered")
        for _ in 0..<3 {
            service.checkForUpdates()
            service.downloadAndInstall()
            service.cancel()
            try await Task.sleep(for: .milliseconds(50))
            try expect(service.phase == .storeManaged && service.message == message,
                       "Calling disabled update actions leaves the Store status unchanged")
            try expect(!service.isBusy && !service.canCheck && !service.canInstall && service.availableRelease == nil,
                       "Repeated update actions never start a direct download or installer")
        }
        try expect(StoreUpdateNetworkProbe.requestCount == 0, "Store update actions issue zero HTTP(S) requests")
        let after = try Data(contentsOf: infoURL)
        try expect(after == bytes, "Store update actions preserve the supplied bundle metadata")
        let children = try FileManager.default.contentsOfDirectory(atPath: root.path)
        try expect(children == ["Fictional.bundle"], "Store updater does not create staged updates beside the fixture")
        print("PASS: \(checks) Store update checks; disabled direct actions, stable Store-managed state, zero HTTP(S) requests; no signing, installed app, or user archive used.")
    }
}
#endif
