import CryptoKit
import Darwin
import Foundation

#if DABIN_DIRECT_UPDATES
private final class DirectUpdateNetworkProbe: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var requests = 0
    static var requestCount: Int {
        lock.lock(); defer { lock.unlock() }; return requests
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

@main
@MainActor
private enum SoftwareUpdateTests {
    private final class Box {
        var dataCalls = 0
        var downloadCalls = 0
        var helperChecks = 0
        var launches: [(URL, URL)] = []
    }

    private final class RedirectProbe: @unchecked Sendable {
        private let lock = NSLock()
        private var result: URLRequest?
        private var completions = 0
        func receive(_ request: URLRequest?) {
            lock.lock(); defer { lock.unlock() }
            result = request
            completions += 1
        }
        var value: (request: URLRequest?, count: Int) {
            lock.lock(); defer { lock.unlock() }
            return (result, completions)
        }
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
                                assetURL: URL? = nil, minimumMacOS: String = "14.0") -> SoftwareReleaseManifest {
        let version = "0.3.0"
        let name = "DaBin-\(version)-Update.zip"
        return SoftwareReleaseManifest(
            schemaVersion: 1,
            bundleIdentifier: "com.dabin.mac",
            version: version,
            buildNumber: build,
            architecture: "arm64",
            minimumMacOS: minimumMacOS,
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
        let overflowingNumber = String(repeating: "9", count: 64)
        try expect(!SoftwareUpdateConfiguration.numericVersion(overflowingNumber)
                   && !SoftwareUpdateConfiguration.numericVersion("١.٢")
                   && !SoftwareUpdateConfiguration.numericVersion("1.2.3.4"),
                   "Version components must be bounded ASCII integers in the supported format")
        for malformed in [release(bytes: size, sha256: checksum, minimumMacOS: overflowingNumber + ".0"),
                          release(bytes: size, sha256: checksum, build: overflowingNumber)] {
            var rejected = false
            do { try malformed.validate() } catch { rejected = true }
            try expect(rejected, "An overflowing minimum macOS or build number cannot validate as a compatible update")
        }
        try await redirectChecks()
        try await updateCacheChecks(root: root, release: manifest, download: downloaded)
        try packageCopyChecks(root: root, download: downloaded, checksum: checksum)
        try transactionChecks(root: root)

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

    private static func redirectChecks() async throws {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        // This task is never resumed. Exercise the production delegate callback
        // with fabricated responses; no socket or real update request is used.
        let origin = URL(string: "https://github.com/RoeyAsterix/DaBin/releases/latest/download/DaBin-update.json")!
        let task = session.dataTask(with: origin)
        let redirect = response(origin, status: 302) as! HTTPURLResponse
        let guardDelegate = SoftwareUpdateRedirectGuard()
        for value in [
            "https://github.com/RoeyAsterix/DaBin/releases/download/v0.3.0/DaBin-0.3.0-Update.zip",
            "https://objects.githubusercontent.com/github-production-release-asset/fixture?token=fictional",
            "https://release-assets.githubusercontent.com/github-production-release-asset/fixture?signature=fictional&expiry=1"
        ] {
            let request = URLRequest(url: URL(string: value)!)
            let probe = RedirectProbe()
            guardDelegate.urlSession(session, task: task, willPerformHTTPRedirection: redirect,
                                     newRequest: request) { probe.receive($0) }
            try expect(probe.value.count == 1 && probe.value.request?.url == request.url,
                       "The redirect guard preserves a legitimate HTTPS GitHub release URL and signed query")
            try SoftwareUpdateConfiguration.validateGitHubResponse(response(request.url!))
        }
        for value in [
            "https://example.invalid/fixture", "http://github.com/fixture",
            "https://github.com:8443/fixture", "https://user:secret@github.com/fixture",
            "https://github.com.example.invalid/fixture", "https://unlisted.githubusercontent.com/fixture",
            "https://127.0.0.1/fixture", "file:///private/tmp/fictional-update.zip",
            "https://github.com/fixture#fragment"
        ] {
            let request = URLRequest(url: URL(string: value)!)
            let probe = RedirectProbe()
            guardDelegate.urlSession(session, task: task, willPerformHTTPRedirection: redirect,
                                     newRequest: request) { probe.receive($0) }
            try expect(probe.value.count == 1 && probe.value.request == nil,
                       "An untrusted redirect is refused before any destination request: \(value)")
            var rejected = false
            do { try SoftwareUpdateConfiguration.validateGitHubResponse(response(request.url!)) }
            catch { rejected = true }
            try expect(rejected, "Final response validation enforces the same transfer boundary")
        }
        try expect(URLProtocol.registerClass(DirectUpdateNetworkProbe.self),
                   "The direct transport fixture blocks all HTTP(S) requests if a guard regresses")
        defer { URLProtocol.unregisterClass(DirectUpdateNetworkProbe.self) }
        let initialRequests = DirectUpdateNetworkProbe.requestCount
        let live = SoftwareUpdateTransport.live()
        let outside = URL(string: "https://example.invalid/fictional-update")!
        var dataRejected = false
        do { _ = try await live.loadData(outside) }
        catch { dataRejected = (error as? SoftwareUpdateError)?.localizedDescription.contains("outside") == true }
        var downloadRejected = false
        do { _ = try await live.download(outside) }
        catch { downloadRejected = (error as? SoftwareUpdateError)?.localizedDescription.contains("outside") == true }
        try expect(dataRejected && downloadRejected && DirectUpdateNetworkProbe.requestCount == initialRequests,
                   "The production transport rejects an untrusted initial URL before creating a network task")
    }

    private static func updateCacheChecks(root: URL, release: SoftwareReleaseManifest, download: URL) async throws {
        let files = FileManager.default
        let packageBytes = try Data(contentsOf: download)
        for mode in ["updates-folder", "cache-parent", "cached-archive"] {
            let base = root.appendingPathComponent("SymlinkCache-\(mode)")
            let outside = base.appendingPathComponent("FictionalOutside")
            let serviceRoot = base.appendingPathComponent("Service")
            try files.createDirectory(at: outside, withIntermediateDirectories: true)
            var link: URL
            let outsidePackage: URL
            if mode == "cache-parent" {
                let outsideUpdates = outside.appendingPathComponent("Updates")
                try files.createDirectory(at: outsideUpdates, withIntermediateDirectories: false)
                outsidePackage = outsideUpdates.appendingPathComponent(release.asset.name)
                link = serviceRoot
                try files.createSymbolicLink(at: link, withDestinationURL: outside)
            } else {
                try files.createDirectory(at: serviceRoot, withIntermediateDirectories: false)
                outsidePackage = outside.appendingPathComponent(release.asset.name)
                link = serviceRoot.appendingPathComponent("Updates")
                if mode == "cached-archive" {
                    try files.createDirectory(at: link, withIntermediateDirectories: false)
                    link.appendPathComponent(release.asset.name)
                    try files.createSymbolicLink(at: link, withDestinationURL: outsidePackage)
                } else {
                    try files.createSymbolicLink(at: link, withDestinationURL: outside)
                }
            }
            try packageBytes.write(to: outsidePackage)
            let originalLink = try files.destinationOfSymbolicLink(atPath: link.path)
            let box = Box()
            let service = try makeService(root: serviceRoot, release: release, download: download, box: box)
            service.checkForUpdates()
            try await wait("The fictional manifest is offered before inspecting the update cache") {
                service.phase == .updateAvailable
            }
            service.downloadAndInstall()
            try await wait("The \(mode) symlink fails before cache access or installation") { service.phase == .failed }
            try expect(box.downloadCalls == 0 && box.helperChecks == 0 && box.launches.isEmpty,
                       "An unsafe cache never starts a download, helper validation or installer launch")
            let remainingLink = try files.destinationOfSymbolicLink(atPath: link.path)
            let remainingBytes = try Data(contentsOf: outsidePackage)
            try expect(remainingLink == originalLink && remainingBytes == packageBytes,
                       "Unsafe cache rejection preserves the symlink and all fictional outside bytes")
            service.cancel()
        }
    }

    private static func packageCopyChecks(root: URL, download: URL, checksum: String) throws {
        let files = FileManager.default
        let original = try Data(contentsOf: download)
        func privateFolder(_ name: String) throws -> URL {
            let folder = root.appendingPathComponent("Frozen-\(name)")
            try files.createDirectory(at: folder, withIntermediateDirectories: false,
                                      attributes: [.posixPermissions: 0o700])
            return folder
        }
        let owned = try privateFolder("valid")
        let frozen = try DaBinUpdatePackageCopy.freeze(download, sha256: checksum, in: owned)
        let frozenBytes = try Data(contentsOf: frozen)
        let permissions = try files.attributesOfItem(atPath: frozen.path)[.posixPermissions] as? NSNumber
        try expect(frozenBytes == original && permissions?.intValue == 0o600,
                   "The helper freezes exact verified package bytes in a private 0600 file")
        try Data("replacement after package verification".utf8).write(to: download, options: .atomic)
        let retainedBytes = try Data(contentsOf: frozen)
        try original.write(to: download, options: .atomic)
        try expect(retainedBytes == original,
                   "Replacing the caller's package pathname cannot change the frozen extraction input")
        var collisionRejected = false
        do { _ = try DaBinUpdatePackageCopy.freeze(download, sha256: checksum, in: owned) }
        catch { collisionRejected = true }
        let afterCollision = try Data(contentsOf: frozen)
        try expect(collisionRejected && afterCollision == original,
                   "A frozen-copy filename conflict preserves the previously owned bytes")

        let mismatched = try privateFolder("bad-hash")
        var hashRejected = false
        do { _ = try DaBinUpdatePackageCopy.freeze(download, sha256: String(repeating: "0", count: 64), in: mismatched) }
        catch { hashRejected = true }
        let mismatchEntries = try files.contentsOfDirectory(atPath: mismatched.path)
        try expect(hashRejected && mismatchEntries.isEmpty,
                   "Checksum mismatch removes only the failed private copy before extraction")

        let linkedSource = root.appendingPathComponent("linked-update.zip")
        try files.createSymbolicLink(at: linkedSource, withDestinationURL: download)
        let symlinkFolder = try privateFolder("source-link")
        var linkRejected = false
        do { _ = try DaBinUpdatePackageCopy.freeze(linkedSource, sha256: checksum, in: symlinkFolder) }
        catch { linkRejected = true }
        let linkEntries = try files.contentsOfDirectory(atPath: symlinkFolder.path)
        try expect(linkRejected && linkEntries.isEmpty,
                   "The source descriptor refuses a symlink without creating a frozen copy")

        let fifo = root.appendingPathComponent("fictional-update-fifo.zip")
        try expect(mkfifo(fifo.path, 0o600) == 0, "The fixture creates an owned FIFO without any writer")
        let fifoFolder = try privateFolder("fifo")
        var fifoRejected = false
        do { _ = try DaBinUpdatePackageCopy.freeze(fifo, sha256: checksum, in: fifoFolder) }
        catch { fifoRejected = true }
        let fifoEntries = try files.contentsOfDirectory(atPath: fifoFolder.path)
        try expect(fifoRejected && fifoEntries.isEmpty,
                   "An unconnected FIFO is rejected without blocking before descriptor validation")

        let multichunk = root.appendingPathComponent("multi-chunk-update.zip")
        let multichunkData = Data(repeating: 0x5A, count: 3 * 1024 * 1024 + 17)
        try multichunkData.write(to: multichunk)
        let multichunkHash = try SoftwareUpdateService.sha256(multichunk)
        let multichunkFolder = try privateFolder("multiple-chunks")
        let multichunkCopy = try DaBinUpdatePackageCopy.freeze(multichunk, sha256: multichunkHash, in: multichunkFolder)
        let multichunkCopiedBytes = try Data(contentsOf: multichunkCopy)
        try expect(multichunkCopiedBytes == multichunkData,
                   "Bounded per-chunk copying and hashing preserve every full chunk and the final partial chunk")

        let publicFolder = root.appendingPathComponent("Frozen-public")
        try files.createDirectory(at: publicFolder, withIntermediateDirectories: false,
                                  attributes: [.posixPermissions: 0o755])
        var publicRejected = false
        do { _ = try DaBinUpdatePackageCopy.freeze(download, sha256: checksum, in: publicFolder) }
        catch { publicRejected = true }
        try expect(publicRejected, "A non-private temporary directory cannot receive an update copy")

        let oversized = root.appendingPathComponent("oversized-sparse-update.zip")
        try expect(files.createFile(atPath: oversized.path, contents: Data()),
                   "The oversized package fixture starts as an owned empty file")
        let sparse = try FileHandle(forWritingTo: oversized)
        try sparse.truncate(atOffset: UInt64(DaBinUpdatePackageCopy.maximumBytes + 1))
        try sparse.close()
        let largeFolder = try privateFolder("oversized")
        var largeRejected = false
        do { _ = try DaBinUpdatePackageCopy.freeze(oversized, sha256: checksum, in: largeFolder) }
        catch { largeRejected = true }
        let largeEntries = try files.contentsOfDirectory(atPath: largeFolder.path)
        try expect(largeRejected && largeEntries.isEmpty,
                   "A sparse oversized package is rejected by descriptor metadata before allocating or copying its bytes")
    }

    private static func transactionChecks(root: URL) throws {
        let files = FileManager.default
        let failure = NSError(domain: "FictionalUpdateVerification", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Fictional verification failure"])
        func app(_ name: String, marker: String) throws -> URL {
            let url = root.appendingPathComponent("\(name).app")
            try files.createDirectory(at: url, withIntermediateDirectories: false)
            try Data(marker.utf8).write(to: url.appendingPathComponent("marker"))
            return url
        }
        func marker(_ app: URL) throws -> String {
            try String(contentsOf: app.appendingPathComponent("marker"), encoding: .utf8)
        }
        let freshStage = try app("FreshStage", marker: "new")
        let freshDestination = root.appendingPathComponent("FreshDestination.app")
        try DaBinUpdateCommit.install(stage: freshStage, destination: freshDestination, backup: nil) { destination in
            guard try marker(destination) == "new" else { throw failure }
        }
        try expect(!files.fileExists(atPath: freshStage.path), "Successful commit moves the staged app exactly once")
        let freshBytes = try marker(freshDestination)
        try expect(freshBytes == "new", "Successful commit retains the verified new app")

        let ownedStage = try app("OwnedStage", marker: "new")
        let oldBackup = try app("OwnedBackup", marker: "old")
        let ownedDestination = root.appendingPathComponent("OwnedDestination.app")
        var ownedRejected = false
        do {
            try DaBinUpdateCommit.install(stage: ownedStage, destination: ownedDestination, backup: oldBackup) { _ in throw failure }
        } catch { ownedRejected = true }
        let restored = try marker(ownedDestination)
        try expect(ownedRejected && restored == "old" && !files.fileExists(atPath: oldBackup.path),
                   "Failed validation removes this transaction's owned app and atomically restores the original")

        let conflictStage = try app("ConflictStage", marker: "new")
        let conflictBackup = try app("ConflictBackup", marker: "old")
        let foreign = try app("ForeignDestination", marker: "foreign")
        var conflictRejected = false
        var conflictMessage = ""
        do {
            try DaBinUpdateCommit.install(stage: conflictStage, destination: foreign, backup: conflictBackup) { _ in
                try expect(false, "Conflicting initial destination never reaches validation")
            }
        } catch { conflictRejected = true; conflictMessage = error.localizedDescription }
        let foreignBytes = try marker(foreign)
        let backupBytes = try marker(conflictBackup)
        let stageBytes = try marker(conflictStage)
        try expect(conflictRejected && foreignBytes == "foreign" && backupBytes == "old" && stageBytes == "new",
                   "A failed stage move preserves the competing destination, original backup and stage")
        try expect(conflictMessage.contains("backup is preserved"), "An unrestored original backup has a clear user-facing explanation")

        let replacedStage = try app("ReplacedStage", marker: "new")
        let replacedBackup = try app("ReplacedBackup", marker: "old")
        let replacement = try app("SecondHelperStage", marker: "second helper")
        let replacedDestination = root.appendingPathComponent("ReplacedDestination.app")
        let displaced = root.appendingPathComponent("SecondHelperBackup.app")
        var replacedRejected = false
        do {
            try DaBinUpdateCommit.install(stage: replacedStage, destination: replacedDestination, backup: replacedBackup) { destination in
                // Deterministically model another helper completing while the
                // first helper's installed-app verification is in flight.
                try DaBinUpdateCommit.moveExclusively(destination, to: displaced)
                try DaBinUpdateCommit.moveExclusively(replacement, to: destination)
                throw failure
            }
        } catch { replacedRejected = true }
        let replacementBytes = try marker(replacedDestination)
        let originalBackupBytes = try marker(replacedBackup)
        let displacedBytes = try marker(displaced)
        try expect(replacedRejected && replacementBytes == "second helper" && originalBackupBytes == "old" && displacedBytes == "new",
                   "Inode-checked rollback preserves the second helper's app and both original app backups")

        let boundaryStage = try app("BoundaryStage", marker: "new")
        let boundaryBackup = try app("BoundaryBackup", marker: "old")
        let boundaryForeign = try app("BoundarySecondHelperStage", marker: "second helper")
        let boundaryDestination = root.appendingPathComponent("BoundaryDestination.app")
        let boundaryDisplaced = root.appendingPathComponent("BoundarySecondHelperBackup.app")
        var boundaryRejected = false
        do {
            try DaBinUpdateCommit.install(stage: boundaryStage, destination: boundaryDestination, backup: boundaryBackup,
                beforeRollbackQuarantine: {
                    // Replace the leaf after the first inode check, at exactly
                    // the boundary that made check-then-remove unsafe.
                    try DaBinUpdateCommit.moveExclusively(boundaryDestination, to: boundaryDisplaced)
                    try DaBinUpdateCommit.moveExclusively(boundaryForeign, to: boundaryDestination)
                }, validate: { _ in throw failure })
        } catch { boundaryRejected = true }
        let boundaryCurrent = try marker(boundaryDestination)
        let boundaryOriginal = try marker(boundaryBackup)
        let boundaryPrevious = try marker(boundaryDisplaced)
        try expect(boundaryRejected && boundaryCurrent == "second helper" && boundaryOriginal == "old" && boundaryPrevious == "new",
                   "Quarantine verifies the moved inode and restores a foreign app replaced after the initial ownership check")

        let cleanupStage = try app("CleanupStage", marker: "owned stage")
        let cleanupForeign = try app("CleanupForeign", marker: "foreign stage")
        let cleanupDisplaced = root.appendingPathComponent("CleanupOwnedPreserved.app")
        let cleanupIdentity = try DaBinUpdateCommit.directoryIdentity(cleanupStage)
        var cleanupRejected = false
        do {
            try DaBinUpdateCommit.removeOwnedDirectory(cleanupStage, matching: cleanupIdentity, beforeQuarantine: {
                try DaBinUpdateCommit.moveExclusively(cleanupStage, to: cleanupDisplaced)
                try DaBinUpdateCommit.moveExclusively(cleanupForeign, to: cleanupStage)
            })
        } catch { cleanupRejected = true }
        let cleanupForeignBytes = try marker(cleanupStage)
        let cleanupOwnedBytes = try marker(cleanupDisplaced)
        try expect(cleanupRejected && cleanupForeignBytes == "foreign stage" && cleanupOwnedBytes == "owned stage",
                   "Failed-stage cleanup uses the same ownership rule and preserves a substituted stage")

        let emptyConflict = root.appendingPathComponent("EmptyConflict.app")
        try files.createDirectory(at: emptyConflict, withIntermediateDirectories: false)
        let emptyStage = try app("EmptyConflictStage", marker: "new")
        var emptyRejected = false
        do { try DaBinUpdateCommit.moveExclusively(emptyStage, to: emptyConflict) }
        catch { emptyRejected = true }
        let emptyContents = try files.contentsOfDirectory(atPath: emptyConflict.path)
        try expect(emptyRejected && emptyContents.isEmpty && files.fileExists(atPath: emptyStage.path),
                   "Atomic exclusive rename never replaces even a competing empty directory")
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
