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

    static func main() throws {
        let infoData = try Data(contentsOf: URL(fileURLWithPath: "Resources/Info.plist"))
        let info = try PropertyListSerialization.propertyList(from: infoData, format: nil) as! [String: Any]
        let project = try text("DaBin.xcodeproj/project.pbxproj")
        let service = try text("Sources/DaBin/SoftwareUpdateService.swift")
        let builder = try text("scripts/build_app.py")
        let archive = try text("scripts/archive_app_store.sh")
        let packager = try text("UpdateTools/package_update.py")
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
                    && packager.contains("--package-sha256"),
                   "Release packaging publishes and exercises the verified update manifest")
        try expect(helper.contains("The update ZIP does not match the checksum")
                    && helper.contains("rejectSymlinks") && helper.contains("codesign")
                    && helper.contains("informativeText = error.localizedDescription"),
                   "The installer rechecks the ZIP, extracted layout and app signature")
        try expect(service.contains("configuration.createsNewApplicationInstance = true")
                    && service.contains("configuration.arguments = arguments"),
                   "The app launches a fresh helper instance so the verified package arguments arrive")
        try expect(privacy.contains("checks for updates only when you choose")
                    && privacy.contains("does not check or download updates silently"),
                   "The bundled privacy policy explains GitHub contact and user control")
        try expect(info["CFBundleShortVersionString"] as? String == "0.3.3"
                    && info["CFBundleVersion"] as? String == "28",
                   "The release version and monotonically increasing build are configured")
        print("PASS: \(checks) update-channel configuration checks")
    }
}
