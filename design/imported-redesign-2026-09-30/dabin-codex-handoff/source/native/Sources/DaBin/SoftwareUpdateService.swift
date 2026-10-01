import AppKit
import Combine
import CryptoKit
import Foundation
import Security

enum SoftwareUpdatePhase: Equatable {
    case idle
    case checking
    case updateAvailable
    case downloading
    case installerOpened
    case upToDate
    case failed
    case storeManaged
}

struct SoftwareUpdateAsset: Codable, Equatable {
    let name: String
    let url: URL
    let bytes: Int64
    let sha256: String
}

struct SoftwareReleaseManifest: Codable, Equatable {
    let schemaVersion: Int
    let bundleIdentifier: String
    let version: String
    let buildNumber: String
    let architecture: String
    let minimumMacOS: String
    let sourceFingerprint: String
    let releasePageURL: URL
    let asset: SoftwareUpdateAsset

    func validate() throws {
        guard schemaVersion == 1 else { throw SoftwareUpdateError.message("This update feed uses an unsupported format.") }
        guard bundleIdentifier == SoftwareUpdateConfiguration.bundleIdentifier else {
            throw SoftwareUpdateError.message("The release is for a different application.")
        }
        guard SoftwareUpdateConfiguration.numericVersion(version),
              let build = Int(buildNumber), build > 0 else {
            throw SoftwareUpdateError.message("The release has an invalid version.")
        }
        guard architecture == "arm64" else {
            throw SoftwareUpdateError.message("The release is not for Apple Silicon.")
        }
        guard SoftwareUpdateConfiguration.numericVersion(minimumMacOS),
              SoftwareUpdateConfiguration.compareVersions(minimumMacOS, SoftwareUpdateConfiguration.currentMacOS) <= 0 else {
            throw SoftwareUpdateError.message("This update needs a newer version of macOS.")
        }
        guard sourceFingerprint.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
            throw SoftwareUpdateError.message("The release source fingerprint is invalid.")
        }
        let expectedName = "DaBin-\(version)-Update.zip"
        guard asset.name == expectedName, asset.bytes > 0, asset.bytes <= SoftwareUpdateConfiguration.maximumAssetBytes,
              asset.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
            throw SoftwareUpdateError.message("The release package description is invalid.")
        }
        try SoftwareUpdateConfiguration.validateReleaseAssetURL(asset.url, version: version, name: expectedName)
        try SoftwareUpdateConfiguration.validateReleasePageURL(releasePageURL, version: version)
    }
}

enum SoftwareUpdateError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}

enum SoftwareUpdateConfiguration {
    static let bundleIdentifier = "com.dabin.mac"
    static let repositoryOwner = "RoeyAsterix"
    static let repositoryName = "DaBin"
    static let manifestKey = "DaBinUpdateManifestURL"
    static let helperBundleIdentifier = "com.dabin.mac.updater.local"
    static let maximumManifestBytes = 64 * 1024
    static let maximumAssetBytes: Int64 = 1_073_741_824
    static let latestReleasePageURL = URL(
        string: "https://github.com/\(repositoryOwner)/\(repositoryName)/releases/latest"
    )!

    static var currentMacOS: String {
        let value = ProcessInfo.processInfo.operatingSystemVersion
        return "\(value.majorVersion).\(value.minorVersion).\(value.patchVersion)"
    }

    static func manifestURL(bundle: Bundle = .main) -> URL? {
        let expected = "https://github.com/\(repositoryOwner)/\(repositoryName)/releases/latest/download/DaBin-update.json"
        guard let value = bundle.object(forInfoDictionaryKey: manifestKey) as? String else {
            return URL(string: expected)
        }
        guard let url = URL(string: value) else { return nil }
        return url.absoluteString == expected ? url : nil
    }

    static func numericVersion(_ value: String) -> Bool {
        value.range(of: "^\\d+(?:\\.\\d+){0,2}$", options: .regularExpression) != nil
    }

    static func compareVersions(_ lhs: String, _ rhs: String) -> Int {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a < b ? -1 : 1 }
        }
        return 0
    }

    static func validateReleaseAssetURL(_ url: URL, version: String, name: String) throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "https", components.host?.lowercased() == "github.com",
              components.port == nil, components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path == "/\(repositoryOwner)/\(repositoryName)/releases/download/v\(version)/\(name)" else {
            throw SoftwareUpdateError.message("The update package is not hosted by DaBin’s GitHub release channel.")
        }
    }

    static func validateReleasePageURL(_ url: URL, version: String) throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "https", components.host?.lowercased() == "github.com",
              components.port == nil, components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path == "/\(repositoryOwner)/\(repositoryName)/releases/tag/v\(version)" else {
            throw SoftwareUpdateError.message("The release page is not part of DaBin’s GitHub repository.")
        }
    }

    static func validateGitHubResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let url = http.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "https", components.user == nil, components.password == nil,
              let host = components.host?.lowercased(),
              host == "github.com" || host == "objects.githubusercontent.com"
                || host == "release-assets.githubusercontent.com"
                || host.hasSuffix(".githubusercontent.com") else {
            throw SoftwareUpdateError.message("GitHub did not return a trusted update response.")
        }
    }
}

struct SoftwareUpdateTransport {
    let loadData: (URL) async throws -> (Data, URLResponse)
    let download: (URL) async throws -> (URL, URLResponse)

    static func live() -> SoftwareUpdateTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 180
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        return SoftwareUpdateTransport(
            loadData: { url in try await session.data(from: url) },
            download: { url in try await session.download(from: url) }
        )
    }
}

#if DABIN_DIRECT_UPDATES
@MainActor
final class SoftwareUpdateService: ObservableObject {
    typealias HelperValidator = (URL) throws -> Void
    typealias InstallerLauncher = (URL, URL) async throws -> Void

    @Published private(set) var phase: SoftwareUpdatePhase = .idle
    @Published private(set) var availableRelease: SoftwareReleaseManifest?
    @Published private(set) var message = "Updates are checked only when you choose."

    let currentVersion: String
    let currentBuild: String
    let isDirectChannel: Bool

    private let manifestURL: URL?
    private let transport: SoftwareUpdateTransport
    private let updatesDirectory: URL
    private let helperURL: URL
    private let validateHelper: HelperValidator
    private let launchInstaller: InstallerLauncher
    private var operation: Task<Void, Never>?
    private var operationID = UUID()
    private var downloadedArchive: URL?

    convenience init(bundle: Bundle = .main) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let helper = bundle.bundleURL.appendingPathComponent("Contents/Helpers/DaBin Update.app")
        self.init(
            currentVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0",
            currentBuild: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
            manifestURL: SoftwareUpdateConfiguration.manifestURL(bundle: bundle),
            transport: .live(),
            updatesDirectory: support.appendingPathComponent("DaBin/Updates", isDirectory: true),
            helperURL: helper,
            validateHelper: Self.validateBundledHelper,
            launchInstaller: Self.openInstaller
        )
    }

    init(currentVersion: String, currentBuild: String, manifestURL: URL?,
         transport: SoftwareUpdateTransport, updatesDirectory: URL, helperURL: URL,
         validateHelper: @escaping HelperValidator,
         launchInstaller: @escaping InstallerLauncher) {
        self.currentVersion = currentVersion
        self.currentBuild = currentBuild
        self.manifestURL = manifestURL
        self.transport = transport
        self.updatesDirectory = updatesDirectory.standardizedFileURL
        self.helperURL = helperURL.standardizedFileURL
        self.validateHelper = validateHelper
        self.launchInstaller = launchInstaller
        isDirectChannel = manifestURL != nil
        if manifestURL == nil {
            phase = .failed
            message = "The direct update channel is not configured in this build."
        }
    }

    var isBusy: Bool { phase == .checking || phase == .downloading }
    var canCheck: Bool { isDirectChannel && !isBusy }
    var canInstall: Bool { phase == .updateAvailable && availableRelease != nil }
    var releasePageURL: URL? {
        availableRelease?.releasePageURL
            ?? (isDirectChannel ? SoftwareUpdateConfiguration.latestReleasePageURL : nil)
    }
    var versionLabel: String { "DaBin \(currentVersion) (\(currentBuild))" }

    func checkForUpdates() {
        guard canCheck, let manifestURL else { return }
        begin { [weak self] identifier in
            guard let self else { return }
            self.phase = .checking
            self.message = "Checking GitHub Releases…"
            self.availableRelease = nil
            self.downloadedArchive = nil
            do {
                let (data, response) = try await self.transport.loadData(manifestURL)
                try Task.checkCancellation()
                guard data.count <= SoftwareUpdateConfiguration.maximumManifestBytes else {
                    throw SoftwareUpdateError.message("The update description is unexpectedly large.")
                }
                try SoftwareUpdateConfiguration.validateGitHubResponse(response)
                let release = try JSONDecoder().decode(SoftwareReleaseManifest.self, from: data)
                try release.validate()
                guard self.operationID == identifier else { return }
                guard let build = Int(release.buildNumber), let installed = Int(self.currentBuild),
                      SoftwareUpdateConfiguration.numericVersion(self.currentVersion) else {
                    throw SoftwareUpdateError.message("The installed DaBin version could not be compared safely.")
                }
                if build > installed && SoftwareUpdateConfiguration.compareVersions(release.version, self.currentVersion) < 0 {
                    throw SoftwareUpdateError.message("The update feed tried to offer an older DaBin version.")
                }
                if build > installed {
                    self.availableRelease = release
                    self.phase = .updateAvailable
                    self.message = "DaBin \(release.version) is ready to download."
                } else {
                    self.phase = .upToDate
                    self.message = "You’re up to date with DaBin \(self.currentVersion)."
                }
            } catch is CancellationError {
                if self.operationID == identifier { self.phase = .idle; self.message = "Update check cancelled." }
            } catch {
                if self.operationID == identifier { self.fail(error) }
            }
        }
    }

    func downloadAndInstall() {
        guard canInstall, let release = availableRelease else { return }
        begin { [weak self] identifier in
            guard let self else { return }
            self.phase = .downloading
            self.message = "Downloading and verifying DaBin \(release.version)…"
            do {
                let archive = try await self.download(release)
                try Task.checkCancellation()
                try self.validateHelper(self.helperURL)
                guard self.operationID == identifier else { return }
                self.downloadedArchive = archive
                let handoffURL = try DaBinUpdateHandoff.create(package: archive,
                                                               sha256: release.asset.sha256,
                                                               in: self.updatesDirectory)
                do {
                    try await self.launchInstaller(self.helperURL, handoffURL)
                } catch {
                    try? FileManager.default.removeItem(at: handoffURL)
                    throw error
                }
                guard self.operationID == identifier else { return }
                self.phase = .installerOpened
                self.message = "The verified installer is open. Choose Update to continue."
            } catch is CancellationError {
                if self.operationID == identifier {
                    self.phase = .updateAvailable
                    self.message = "Download cancelled. DaBin \(release.version) is still available."
                }
            } catch {
                if self.operationID == identifier { self.fail(error) }
            }
        }
    }

    func cancel() {
        operationID = UUID()
        operation?.cancel()
        operation = nil
    }

    private func begin(_ work: @escaping (UUID) async -> Void) {
        operation?.cancel()
        let identifier = UUID()
        operationID = identifier
        operation = Task { [weak self] in
            await work(identifier)
            if self?.operationID == identifier { self?.operation = nil }
        }
    }

    private func fail(_ error: Error) {
        phase = .failed
        message = error.localizedDescription
    }

    private func download(_ release: SoftwareReleaseManifest) async throws -> URL {
        try FileManager.default.createDirectory(at: updatesDirectory, withIntermediateDirectories: true)
        let destination = updatesDirectory.appendingPathComponent(release.asset.name)
        if try Self.matches(release.asset, file: destination) { return destination }
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }

        let (temporary, response) = try await transport.download(release.asset.url)
        try SoftwareUpdateConfiguration.validateGitHubResponse(response)
        try Task.checkCancellation()
        guard try Self.matches(release.asset, file: temporary) else {
            throw SoftwareUpdateError.message("The downloaded update did not match its published size and SHA-256 checksum.")
        }
        let partial = updatesDirectory.appendingPathComponent(".\(release.asset.name).\(UUID().uuidString).partial")
        defer { try? FileManager.default.removeItem(at: partial) }
        try FileManager.default.copyItem(at: temporary, to: partial)
        guard try Self.matches(release.asset, file: partial) else {
            throw SoftwareUpdateError.message("The verified update changed while it was saved.")
        }
        try FileManager.default.moveItem(at: partial, to: destination)
        return destination
    }

    static func sha256(_ url: URL) throws -> String {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw SoftwareUpdateError.message("The update download is not a normal file.")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func matches(_ asset: SoftwareUpdateAsset, file: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: file.path) else { return false }
        let values = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              Int64(values.fileSize ?? -1) == asset.bytes else { return false }
        return try sha256(file) == asset.sha256
    }

    private static func validateBundledHelper(_ url: URL) throws {
        let info = url.appendingPathComponent("Contents/Info.plist")
        guard let dictionary = NSDictionary(contentsOf: info) as? [String: Any],
              dictionary["CFBundleIdentifier"] as? String == SoftwareUpdateConfiguration.helperBundleIdentifier else {
            throw SoftwareUpdateError.message("The built-in DaBin installer is missing or has the wrong identity.")
        }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw SoftwareUpdateError.message("The built-in DaBin installer is not a normal application.")
        }
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else {
            throw SoftwareUpdateError.message("The built-in DaBin installer could not be inspected.")
        }
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures)
        guard SecStaticCodeCheckValidity(staticCode, flags, nil) == errSecSuccess else {
            throw SoftwareUpdateError.message("The built-in DaBin installer did not pass code-signature validation.")
        }
    }

    private static func openInstaller(_ url: URL, handoffURL: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.createsNewApplicationInstance = true
            configuration.allowsRunningApplicationSubstitution = false
            // App Sandbox deliberately strips OpenConfiguration.arguments.
            // A document-open event is the supported cross-application handoff and
            // carries the verified package path and checksum to the exact helper.
            NSWorkspace.shared.open([handoffURL], withApplicationAt: url,
                                    configuration: configuration) { application, error in
                if let error { continuation.resume(throwing: error) }
                else if application == nil {
                    continuation.resume(throwing: SoftwareUpdateError.message("macOS could not open the DaBin installer."))
                } else { continuation.resume() }
            }
        }
    }
}
#else
@MainActor
final class SoftwareUpdateService: ObservableObject {
    @Published private(set) var phase: SoftwareUpdatePhase = .storeManaged
    @Published private(set) var availableRelease: SoftwareReleaseManifest?
    @Published private(set) var message = "Updates for this build are delivered through the Mac App Store."
    let currentVersion: String
    let currentBuild: String
    let isDirectChannel = false
    var isBusy: Bool { false }
    var canCheck: Bool { false }
    var canInstall: Bool { false }
    var releasePageURL: URL? { nil }
    var versionLabel: String { "DaBin \(currentVersion) (\(currentBuild))" }

    init(bundle: Bundle = .main) {
        currentVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        currentBuild = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    func checkForUpdates() {}
    func downloadAndInstall() {}
    func cancel() {}
}
#endif
