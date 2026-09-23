import AppKit
import CryptoKit
import Foundation

private let daBinBundleIdentifier = "com.dabin.mac"

private enum UpdateFailure: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}

private struct AppIdentity {
    let version: String
    let build: String
    let configuration: String?

    init(app: URL, requireRelease: Bool) throws {
        let infoURL = app.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: infoURL) as? [String: Any],
              info["CFBundleIdentifier"] as? String == daBinBundleIdentifier,
              let version = info["CFBundleShortVersionString"] as? String,
              let build = info["CFBundleVersion"] as? String else {
            throw UpdateFailure.message("The selected application is not a valid DaBin build.")
        }
        let configuration = info["DaBinBuildConfiguration"] as? String
        if requireRelease && configuration != "Release" {
            throw UpdateFailure.message("The update does not contain a DaBin Release build.")
        }
        self.version = version
        self.build = build
        self.configuration = configuration
    }
}

private struct UpdateOptions {
    var destination = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Applications/DaBin.app")
    var nonInteractive = false
    var noLaunch = false
    var verifyOnly = false
    var package: URL?
    var packageSHA256: String?

    static func parse(_ arguments: [String]) throws -> UpdateOptions {
        var result = UpdateOptions()
        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "--non-interactive": result.nonInteractive = true
            case "--no-launch": result.noLaunch = true
            case "--verify-only": result.verifyOnly = true
            case "--package":
                index += 1
                guard index < arguments.count else {
                    throw UpdateFailure.message("--package needs an absolute update ZIP path.")
                }
                let path = arguments[index]
                guard path.hasPrefix("/"), URL(fileURLWithPath: path).pathExtension.lowercased() == "zip" else {
                    throw UpdateFailure.message("--package must be an absolute path to a ZIP file.")
                }
                result.package = URL(fileURLWithPath: path).standardizedFileURL
            case "--package-sha256":
                index += 1
                guard index < arguments.count,
                      arguments[index].range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
                    throw UpdateFailure.message("--package-sha256 needs a lowercase SHA-256 checksum.")
                }
                result.packageSHA256 = arguments[index]
            case "--destination":
                index += 1
                guard index < arguments.count else {
                    throw UpdateFailure.message("--destination needs an absolute DaBin.app path.")
                }
                let path = arguments[index]
                guard path.hasPrefix("/"), URL(fileURLWithPath: path).lastPathComponent == "DaBin.app" else {
                    throw UpdateFailure.message("--destination must be an absolute path ending in DaBin.app.")
                }
                result.destination = URL(fileURLWithPath: path).standardizedFileURL
            default:
                throw UpdateFailure.message("Unknown updater option: \(arguments[index])")
            }
            index += 1
        }
        guard (result.package == nil) == (result.packageSHA256 == nil) else {
            throw UpdateFailure.message("A package path and its SHA-256 checksum must be supplied together.")
        }
        return result
    }
}

private final class PreparedUpdate {
    private let files = FileManager.default
    private var temporaryRoot: URL?
    let source: URL

    init(options: UpdateOptions, updaterBundle: Bundle) throws {
        guard let package = options.package, let expectedHash = options.packageSHA256 else {
            source = updaterBundle.bundleURL.deletingLastPathComponent().appendingPathComponent("DaBin.app")
            return
        }
        let values = try package.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let bytes = values.fileSize, bytes > 0, bytes <= 1_073_741_824 else {
            throw UpdateFailure.message("The downloaded update is not a normal ZIP file or is unexpectedly large.")
        }
        guard try Self.sha256(package) == expectedHash else {
            throw UpdateFailure.message("The update ZIP does not match the checksum published by DaBin’s GitHub release.")
        }
        let root = files.temporaryDirectory.appendingPathComponent("DaBinUpdate-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: root, withIntermediateDirectories: false)
        temporaryRoot = root
        do {
            _ = try Self.run("/usr/bin/ditto", ["-x", "-k", package.path, root.path])
            try Self.rejectSymlinks(in: root)
            let entries = try files.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                                        options: [.skipsHiddenFiles])
            guard entries.count == 1, entries[0].lastPathComponent.hasPrefix("DaBin-"),
                  try entries[0].resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]).isDirectory == true,
                  try entries[0].resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]).isSymbolicLink != true else {
                throw UpdateFailure.message("The update ZIP has an unexpected folder layout.")
            }
            let app = entries[0].appendingPathComponent("DaBin.app", isDirectory: true)
            guard files.fileExists(atPath: app.path) else {
                throw UpdateFailure.message("The update ZIP does not contain DaBin.app.")
            }
            source = app
        } catch {
            try? files.removeItem(at: root)
            temporaryRoot = nil
            throw error
        }
    }

    deinit {
        if let temporaryRoot { try? files.removeItem(at: temporaryRoot) }
    }

    private static func sha256(_ url: URL) throws -> String {
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

    private static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw UpdateFailure.message(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "The update ZIP could not be extracted." : text)
        }
        return text
    }

    private static func rejectSymlinks(in root: URL) throws {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey]) else {
            throw UpdateFailure.message("The extracted update could not be inspected.")
        }
        for case let item as URL in enumerator where try item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
            throw UpdateFailure.message("The update ZIP contains an unsupported symbolic link.")
        }
    }
}

private struct UpdateResult {
    let identity: AppIdentity
    let backup: URL?
}

private final class DaBinInstaller {
    private let files = FileManager.default
    let source: URL
    let destination: URL
    let standardDestination: URL

    init(source: URL, destination: URL) {
        self.source = source.standardizedFileURL
        self.destination = destination.standardizedFileURL
        standardDestination = files.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/DaBin.app").standardizedFileURL
    }

    @discardableResult
    private func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch {
            throw UpdateFailure.message("Could not run \(URL(fileURLWithPath: executable).lastPathComponent): \(error.localizedDescription)")
        }
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            throw UpdateFailure.message(detail.isEmpty ? "\(executable) failed." : detail)
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func rejectSymlinks(in root: URL) throws {
        let rootValues = try root.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else {
            throw UpdateFailure.message("The update application must be a real folder, not a symbolic link.")
        }
        guard let enumerator = files.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey]) else {
            throw UpdateFailure.message("The update application could not be inspected.")
        }
        for case let item as URL in enumerator {
            if try item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                throw UpdateFailure.message("The update contains an unsupported symbolic link.")
            }
        }
    }

    @discardableResult
    func validateSource() throws -> AppIdentity {
        try rejectSymlinks(in: source)
        let identity = try AppIdentity(app: source, requireRelease: true)
        let executable = source.appendingPathComponent("Contents/MacOS/DaBin")
        let architectures = try run("/usr/bin/lipo", ["-archs", executable.path])
        guard architectures == "arm64" else {
            throw UpdateFailure.message("This update must contain an Apple Silicon ARM64 build.")
        }
        _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", source.path])
        return identity
    }

    private func validateExistingDestination() throws -> AppIdentity? {
        guard files.fileExists(atPath: destination.path) else { return nil }
        let values = try destination.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw UpdateFailure.message("The existing destination is not a normal DaBin application. It was preserved.")
        }
        return try AppIdentity(app: destination, requireRelease: false)
    }

    private func quitInstalledDaBin() throws {
        guard destination == standardDestination else { return }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: daBinBundleIdentifier)
        guard !running.isEmpty else { return }
        running.forEach { _ = $0.terminate() }
        let deadline = Date().addingTimeInterval(15)
        while running.contains(where: { !$0.isTerminated }) && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        guard running.allSatisfy(\.isTerminated) else {
            throw UpdateFailure.message("DaBin is still open. Finish or cancel any edit or removal, quit DaBin, then run the updater again.")
        }
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    func install(launch: Bool) throws -> UpdateResult {
        let sourceIdentity = try validateSource()
        let current = try validateExistingDestination()
        _ = current
        try quitInstalledDaBin()

        let applications = destination.deletingLastPathComponent()
        let parentValues = try applications.deletingLastPathComponent()
            .resourceValues(forKeys: [.isSymbolicLinkKey])
        guard parentValues.isSymbolicLink != true else {
            throw UpdateFailure.message("The Applications destination is reached through a symbolic link. Nothing was changed.")
        }
        if files.fileExists(atPath: applications.path) {
            let values = try applications.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw UpdateFailure.message("The Applications destination is not a normal folder. Nothing was changed.")
            }
        }
        try files.createDirectory(at: applications, withIntermediateDirectories: true)
        let stage = applications.appendingPathComponent(".DaBin-update-\(UUID().uuidString).app")
        var backup: URL?
        defer { if files.fileExists(atPath: stage.path) { try? files.removeItem(at: stage) } }

        _ = try run("/usr/bin/ditto", ["--noextattr", "--norsrc", source.path, stage.path])
        let stagedIdentity = try AppIdentity(app: stage, requireRelease: true)
        guard stagedIdentity.version == sourceIdentity.version,
              stagedIdentity.build == sourceIdentity.build else {
            throw UpdateFailure.message("The staged update identity changed while copying.")
        }
        _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", stage.path])

        if files.fileExists(atPath: destination.path) {
            let backups = applications.appendingPathComponent(".DaBinBackups", isDirectory: true)
            let backupValues = try? backups.resourceValues(forKeys: [.isSymbolicLinkKey])
            if backupValues?.isSymbolicLink == true {
                throw UpdateFailure.message("The DaBin backup location is a symbolic link. Nothing was changed.")
            }
            try files.createDirectory(at: backups, withIntermediateDirectories: true)
            let backupURL = backups.appendingPathComponent("\(timestamp())-\(UUID().uuidString.prefix(8)).app")
            try files.moveItem(at: destination, to: backupURL)
            backup = backupURL
        }

        do {
            try files.moveItem(at: stage, to: destination)
            _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", destination.path])
            let installed = try AppIdentity(app: destination, requireRelease: true)
            guard installed.version == sourceIdentity.version,
                  installed.build == sourceIdentity.build else {
                throw UpdateFailure.message("The installed DaBin version does not match the update.")
            }
        } catch {
            if files.fileExists(atPath: destination.path) { try? files.removeItem(at: destination) }
            if let backup, files.fileExists(atPath: backup.path) {
                try? files.moveItem(at: backup, to: destination)
            }
            throw error
        }

        if launch {
            _ = try run("/usr/bin/open", ["-a", destination.path, "--args", "--show-daily"])
        }
        return UpdateResult(identity: sourceIdentity, backup: backup)
    }
}

@MainActor
private final class UpdateDelegate: NSObject, NSApplicationDelegate {
    let options: UpdateOptions
    let prepared: PreparedUpdate
    let installer: DaBinInstaller

    init(options: UpdateOptions, prepared: PreparedUpdate, installer: DaBinInstaller) {
        self.options = options
        self.prepared = prepared
        self.installer = installer
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        do {
            let update = try installer.validateSource()
            let current = try? AppIdentity(app: options.destination, requireRelease: false)
            let alert = NSAlert()
            alert.messageText = current == nil ? "Install DaBin \(update.version)?" : "Update DaBin to \(update.version)?"
            alert.informativeText = "Current app: \(current.map { "\($0.version) (\($0.build))" } ?? "not installed")\nUpdate: \(update.version) (\(update.build))\n\nDaBin will quit, the current app will be backed up, and the update will be verified before it opens. Your captures and local archive stay in place."
            alert.addButton(withTitle: current == nil ? "Install" : "Update")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { NSApp.terminate(nil); return }

            let result = try installer.install(launch: !options.noLaunch)
            let done = NSAlert()
            done.messageText = "DaBin \(result.identity.version) is ready"
            done.informativeText = result.backup == nil
                ? "DaBin was installed and verified. Your local archive was not changed."
                : "DaBin was updated and verified. The previous app was backed up, and your local archive was not changed."
            done.addButton(withTitle: "Done")
            done.runModal()
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "DaBin could not be updated"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "Close")
            alert.runModal()
        }
        NSApp.terminate(nil)
    }
}

@main
private enum DaBinUpdaterMain {
    @MainActor static func main() {
        do {
            let options = try UpdateOptions.parse(CommandLine.arguments)
            let prepared = try PreparedUpdate(options: options, updaterBundle: .main)
            let installer = DaBinInstaller(source: prepared.source, destination: options.destination)
            if options.verifyOnly {
                let identity = try installer.validateSource()
                print("Verified DaBin \(identity.version) (\(identity.build)) ARM64 Release update")
                return
            }
            if options.nonInteractive {
                let result = try installer.install(launch: !options.noLaunch)
                print("Installed DaBin \(result.identity.version) (\(result.identity.build)) at \(options.destination.path)")
                if let backup = result.backup { print("Previous app backed up at \(backup.path)") }
                return
            }
            let application = NSApplication.shared
            application.setActivationPolicy(.regular)
            let delegate = UpdateDelegate(options: options, prepared: prepared, installer: installer)
            application.delegate = delegate
            application.run()
            _ = delegate
        } catch {
            fputs("DaBin Update: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
