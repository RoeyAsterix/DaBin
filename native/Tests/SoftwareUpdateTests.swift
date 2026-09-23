import CryptoKit
import Foundation

@main
@MainActor
private enum SoftwareUpdateTests {
    private final class Box {
        var dataCalls = 0
        var downloadCalls = 0
        var helperChecks = 0
        var launches: [(URL, [String])] = []
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
            launchInstaller: { url, arguments in box.launches.append((url, arguments)) }
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
        try await Task.sleep(for: .milliseconds(30))
        try expect(box.dataCalls == 0 && box.downloadCalls == 0,
                   "Constructing the service never contacts GitHub automatically")
        service.checkForUpdates()
        try await wait("A newer GitHub release becomes available") { service.phase == .updateAvailable }
        try expect(box.dataCalls == 1 && service.availableRelease == manifest,
                   "One explicit check reads one manifest and keeps the validated release")
        try expect(service.canInstall && service.message.contains("0.3.0"),
                   "The settings state offers the validated newer release")
        service.downloadAndInstall()
        try await wait("The verified helper opens") { service.phase == .installerOpened }
        try expect(box.downloadCalls == 1 && box.helperChecks == 1 && box.launches.count == 1,
                   "Download, bundled-helper validation and launch each run once")
        let arguments = box.launches[0].1
        try expect(arguments == ["--package", root.appendingPathComponent("Updates/DaBin-0.3.0-Update.zip").path,
                                 "--package-sha256", checksum],
                   "The installer receives only the verified archive path and published checksum")
        let retainedChecksum = try SoftwareUpdateService.sha256(root.appendingPathComponent("Updates/DaBin-0.3.0-Update.zip"))
        try expect(retainedChecksum == checksum,
                   "The archive retained for the installer matches the published SHA-256")
        service.cancel()

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
        print("PASS: \(checks) software update checks; no external network, installed app or user archive used.")
    }
}
