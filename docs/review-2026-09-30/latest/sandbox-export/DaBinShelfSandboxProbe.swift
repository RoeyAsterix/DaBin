import AppKit
import Foundation
@testable import DaBinTestCore

@main struct DaBinShelfSandboxProbe {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.finishLaunching()
        app.activate(ignoringOtherApps: true)
        let picker = NSSavePanel()
        picker.title = "DaBin Shelf Sandbox QA — synthetic content only"
        picker.message = "Save a synthetic shelf ZIP to test the actual App Sandbox export permission. No personal DaBin archive is opened."
        picker.nameFieldStringValue = "DaBin-Shelf-QA-20260930.zip"
        picker.directoryURL = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
        picker.canCreateDirectories = false
        guard picker.runModal() == .OK, let destination = picker.url else {
            print("SANDBOX_PROBE_CANCELLED")
            return
        }
        let scope = destination.startAccessingSecurityScopedResource()
        defer { if scope { destination.stopAccessingSecurityScopedResource() } }
        var result: [String: Any] = [
            "probe": "DaBin ShelfExport sandbox probe",
            "bundleID": Bundle.main.bundleIdentifier ?? "unknown",
            "sandboxTemporaryDirectory": FileManager.default.temporaryDirectory.path,
            "destination": destination.path,
            "securityScopeStarted": scope
        ]
        do {
            let entries = [ShelfExportEntry(name: "Synthetic client notes.txt", source: nil,
                text: "Synthetic QA content only.\nClient A: review the proposal.\nשלום / 日本語\n")]
            try ShelfExport.write(entries, to: destination)
            let data = try Data(contentsOf: destination)
            result["passed"] = true
            result["zipBytes"] = data.count
            result["zipMagic"] = Array(data.prefix(4)).map { String(format: "%02x", $0) }.joined()
        } catch {
            let failure = error as NSError
            result["passed"] = false
            result["errorDomain"] = failure.domain
            result["errorCode"] = failure.code
            result["error"] = failure.localizedDescription
            result["destinationExists"] = FileManager.default.fileExists(atPath: destination.path)
        }
        let output = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        print("SANDBOX_PROBE_RESULT\n" + String(decoding: output, as: UTF8.self))
        fflush(stdout)
    }
}
