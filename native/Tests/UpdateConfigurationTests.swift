import CryptoKit
import Foundation

@main
private enum UpdateConfigurationTests {
    private static var checks = 0

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard condition() else {
            throw NSError(domain: "UpdateConfigurationTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private static func text(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func run(_ executable: String, _ arguments: [String]) throws -> (Int32, String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    }

    private static func verifyStableReleaseStaging() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("DaBinLatestReleaseTests-\(UUID().uuidString)")
        defer { try? files.removeItem(at: root) }
        try files.createDirectory(at: root, withIntermediateDirectories: false)

        let version = "9.8.7"
        let update = root.appendingPathComponent("DaBin-\(version)-Update.zip")
        let standalone = root.appendingPathComponent("DaBin-\(version)-AppleSilicon.zip")
        let manifest = root.appendingPathComponent("DaBin-update.json")
        let attestation = root.appendingPathComponent("DISTRIBUTION-ATTESTATION.json")
        let guide = root.appendingPathComponent("DaBin-Quick-Guide.pdf")
        let notes = root.appendingPathComponent("RELEASE_NOTES_\(version).md")
        let updateBytes = Data("verified update fixture".utf8)
        let standaloneBytes = Data("verified standalone fixture".utf8)
        try updateBytes.write(to: update, options: .withoutOverwriting)
        try standaloneBytes.write(to: standalone, options: .withoutOverwriting)
        try Data("%PDF-1.4 fixture".utf8).write(to: guide, options: .withoutOverwriting)
        try Data("# Release fixture".utf8).write(to: notes, options: .withoutOverwriting)
        let identity = "Developer ID Application: DaBin Release (A1B2C3D4E5)"
        let submission = "11111111-2222-3333-4444-555555555555"
        let distribution: [String: Any] = [
            "developerIDIdentity": identity,
            "teamIdentifier": "A1B2C3D4E5",
            "localAdHocSigning": false,
            "hardenedRuntime": true,
            "trustedTimestamp": true,
            "notarizationValidated": true,
            "stapleValidated": true,
            "gatekeeperValidated": true,
            "notarySubmissionID": submission,
        ]
        let updaterQA: [String: Any] = [
            "freshInstall": "passed",
            "replacement": "passed",
            "backup": "passed",
            "installedCodeSignature": "passed",
            "installedStaple": "passed",
            "installedGatekeeper": "passed",
            "installedSystemPolicy": "passed",
            "updateZIPSHA256": sha256(updateBytes),
        ]
        let payload: [String: Any] = [
            "schemaVersion": 1,
            "bundleIdentifier": "com.dabin.mac",
            "version": version,
            "buildNumber": "987",
            "architecture": "arm64",
            "minimumMacOS": "14.0",
            "sourceFingerprint": String(repeating: "a", count: 64),
            "releasePageURL": "https://github.com/RoeyAsterix/DaBin/releases/tag/v\(version)",
            "distribution": distribution,
            "updaterQA": updaterQA,
            "asset": [
                "name": update.lastPathComponent,
                "url": "https://github.com/RoeyAsterix/DaBin/releases/download/v\(version)/\(update.lastPathComponent)",
                "bytes": updateBytes.count,
                "sha256": sha256(updateBytes),
            ],
        ]
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            .write(to: manifest, options: .withoutOverwriting)
        var attestationPayload: [String: Any] = [
            "schemaVersion": 1,
            "version": version,
            "buildNumber": "987",
            "createdAtUTC": "2026-09-24T12:00:00+00:00",
            "signedExecutableSHA256": String(repeating: "b", count: 64),
            "signedUpdaterExecutableSHA256": String(repeating: "c", count: 64),
            "updaterQA": updaterQA,
            "artifacts": [
                update.lastPathComponent: ["bytes": updateBytes.count, "sha256": sha256(updateBytes)],
                standalone.lastPathComponent: [
                    "bytes": standaloneBytes.count,
                    "sha256": sha256(standaloneBytes),
                ],
            ],
        ]
        for (key, value) in distribution { attestationPayload[key] = value }
        try JSONSerialization.data(withJSONObject: attestationPayload, options: [.prettyPrinted, .sortedKeys])
            .write(to: attestation, options: .withoutOverwriting)

        let destination = root.appendingPathComponent("release-assets")
        let arguments = ["scripts/stage_release_assets.py", "--update", update.path,
                         "--standalone", standalone.path, "--manifest", manifest.path,
                         "--attestation", attestation.path,
                         "--guide", guide.path, "--notes", notes.path,
                         "--output-directory", destination.path]
        let staged = try run("/usr/bin/python3", arguments)
        try expect(staged.0 == 0, "The release tool stages a complete valid fixture: \(staged.1)")
        let expectedNames = Set([update.lastPathComponent, standalone.lastPathComponent,
                                 "DaBin-Latest-Update.zip", "DaBin-Latest-AppleSilicon.zip",
                                 manifest.lastPathComponent, attestation.lastPathComponent,
                                 guide.lastPathComponent, notes.lastPathComponent])
        let stagedNames = Set(try files.contentsOfDirectory(atPath: destination.path))
        try expect(stagedNames == expectedNames,
                   "A release contains versioned packages, permanent aliases, manifest, guide and notes")
        let stagedLatestUpdate = try Data(contentsOf: destination.appendingPathComponent("DaBin-Latest-Update.zip"))
        let stagedLatestStandalone = try Data(contentsOf: destination.appendingPathComponent("DaBin-Latest-AppleSilicon.zip"))
        try expect(stagedLatestUpdate == updateBytes,
                   "The permanent update URL serves byte-identical verified update data")
        try expect(stagedLatestStandalone == standaloneBytes,
                   "The permanent direct-install URL serves byte-identical verified standalone data")
        let stagedAttestation = try Data(contentsOf: destination.appendingPathComponent(attestation.lastPathComponent))
        let sourceAttestation = try Data(contentsOf: attestation)
        try expect(stagedAttestation == sourceAttestation,
                   "The release preserves the notarized distribution attestation")

        let repeated = try run("/usr/bin/python3", arguments)
        let preservedLatestUpdate = try Data(contentsOf: destination.appendingPathComponent("DaBin-Latest-Update.zip"))
        try expect(repeated.0 != 0 && preservedLatestUpdate == updateBytes,
                   "Release staging refuses to replace existing verified output")
        try Data("changed after manifest".utf8).write(to: update)
        let rejectedDestination = root.appendingPathComponent("rejected-assets")
        var rejectedArguments = arguments
        rejectedArguments[rejectedArguments.count - 1] = rejectedDestination.path
        let rejected = try run("/usr/bin/python3", rejectedArguments)
        try expect(rejected.0 != 0 && !files.fileExists(atPath: rejectedDestination.path),
                   "Release staging rejects bytes that do not match the manifest and attestation")

        try updateBytes.write(to: update)
        var failedAttestation = attestationPayload
        failedAttestation["gatekeeperValidated"] = false
        try JSONSerialization.data(withJSONObject: failedAttestation, options: [.sortedKeys]).write(to: attestation)
        let failedGateDestination = root.appendingPathComponent("failed-gate-assets")
        var failedGateArguments = arguments
        failedGateArguments[failedGateArguments.count - 1] = failedGateDestination.path
        let failedGate = try run("/usr/bin/python3", failedGateArguments)
        try expect(failedGate.0 != 0 && !files.fileExists(atPath: failedGateDestination.path),
                   "Release staging refuses an attestation whose Gatekeeper gate did not pass")
    }

    static func main() throws {
        let infoData = try Data(contentsOf: URL(fileURLWithPath: "Resources/Info.plist"))
        let info = try PropertyListSerialization.propertyList(from: infoData, format: nil) as! [String: Any]
        let project = try text("DaBin.xcodeproj/project.pbxproj")
        let service = try text("Sources/DaBin/SoftwareUpdateService.swift")
        let handoff = try text("Sources/DaBin/UpdateHandoff.swift")
        let builder = try text("scripts/build_app.py")
        let archive = try text("scripts/archive_app_store.sh")
        let packager = try text("UpdateTools/package_update.py")
        let latestStager = try text("scripts/stage_release_assets.py")
        let latestWorkflow = try text("../.github/workflows/stable-latest-downloads.yml")
        let releasing = try text("../docs/RELEASING.md")
        let rootReadme = try text("../README.md")
        let helper = try text("UpdateTools/DaBinUpdater.swift")
        let privacy = try text("Resources/PrivacyPolicy.md")

        try expect(info["DaBinUpdateManifestURL"] == nil && info["DaBinDistributionChannel"] == nil,
                   "The shared Info.plist does not opt an App Store archive into direct updates")
        try expect(!project.contains("DABIN_DIRECT_UPDATES") && !project.contains("DaBinUpdater.swift"),
                   "The generated Xcode Store path excludes the direct-update flag and helper source")
        try expect(project.contains("SoftwareUpdateService.swift"),
                   "The Xcode path compiles the Store-managed update-service stub")
        try expect(service.contains("#if DABIN_DIRECT_UPDATES") && service.contains("#else")
                    && service.contains("Updates for this build are delivered through the Mac App Store"),
                   "Direct download code has an explicit Store-managed compile boundary")
        try expect(builder.contains("\"-D\", \"DABIN_DIRECT_UPDATES\"")
                    && builder.contains("Contents/Helpers/DaBin Update.app")
                    && builder.contains("DaBinUpdateManifestURL"),
                   "Only the standalone builder enables the direct channel and embeds its helper")
        try expect(archive.contains("INFOPLIST_FILE") && !archive.contains("DABIN_DIRECT_UPDATES"),
                   "The App Store archive helper uses the generated Xcode path without the direct flag")
        try expect(packager.contains("releasePageURL") && packager.contains("sha256")
                    && packager.contains("sandboxCompatibleDocumentHandoff"),
                   "Release packaging publishes and exercises the verified update manifest")
        try expect(latestStager.contains("DaBin-Latest-Update.zip")
                    && latestStager.contains("DaBin-Latest-AppleSilicon.zip")
                    && latestStager.contains("DISTRIBUTION-ATTESTATION.json")
                    && latestStager.contains("gatekeeperValidated")
                    && latestStager.contains("The manifest does not describe the exact versioned update package"),
                   "Release staging creates stable aliases only after validating notarized packages")
        try expect(latestWorkflow.contains("release:") && latestWorkflow.contains("types: [published]")
                    && latestWorkflow.contains("gh release upload") && latestWorkflow.contains("--clobber")
                    && latestWorkflow.contains("runs-on: macos-14")
                    && latestWorkflow.contains("DISTRIBUTION-ATTESTATION.json")
                    && latestWorkflow.contains("codesign --verify --deep --strict")
                    && latestWorkflow.contains("stapler validate")
                    && latestWorkflow.contains("spctl --assess")
                    && latestWorkflow.contains("syspolicy_check distribution")
                    && latestWorkflow.contains("DaBin-Latest-Update.zip")
                    && latestWorkflow.contains("DaBin-Latest-AppleSilicon.zip"),
                   "A macOS release gate validates notarization before restoring permanent aliases")
        try expect(releasing.contains("releases/latest/download/DaBin-Latest-Update.zip")
                    && releasing.contains("releases/latest/download/DaBin-Latest-AppleSilicon.zip")
                    && rootReadme.contains("releases/latest/download/DaBin-Latest-Update.zip")
                    && rootReadme.contains("releases/latest/download/DaBin-Latest-AppleSilicon.zip"),
                   "Release instructions and the repository front page expose permanent latest downloads")
        try expect(helper.contains("The update ZIP does not match the checksum")
                    && helper.contains("rejectSymlinks") && helper.contains("codesign")
                    && helper.contains("informativeText = error.localizedDescription"),
                   "The installer rechecks the ZIP, extracted layout and app signature")
        try expect(service.contains("configuration.createsNewApplicationInstance = true")
                    && service.contains("NSWorkspace.shared.open([handoffURL]")
                    && !service.contains("configuration.arguments ="),
                   "The sandboxed app opens a one-use handoff document instead of stripped launch arguments")
        try expect(handoff.contains("packageName") && handoff.contains("packageSHA256")
                    && handoff.contains("isSymbolicLinkKey") && handoff.contains("removeItem"),
                   "The update handoff is strict, path-safe and consumed once")
        try expect(privacy.contains("checks for updates only when you choose")
                    && privacy.contains("does not check or download updates silently"),
                   "The bundled privacy policy explains GitHub contact and user control")
        try expect(info["CFBundleShortVersionString"] as? String == "0.3.18"
                    && info["CFBundleVersion"] as? String == "43",
                   "The release version and monotonically increasing build are configured")
        try verifyStableReleaseStaging()
        print("PASS: \(checks) update-channel configuration checks")
    }
}
