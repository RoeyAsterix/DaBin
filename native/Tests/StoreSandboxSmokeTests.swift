import CryptoKit
import Darwin
import Foundation
import Security

/// Launched only by Tests/store_sandbox_smoke.py as a uniquely identified,
/// ad-hoc-signed App Sandbox fixture. It never initializes the application UI.
@main struct StoreSandboxSmokeTests {
    struct Receipt: Codable {
        let noteID: UUID
        let fileID: UUID
        let body: String
        let comment: String
        let original: Data
        let capturedAt: Date
    }

    @MainActor static var evidence: [String: Any] = ["passed": false, "checks": [String](),
        "runtimeScope": "ad-hoc test bundle linked to Store QA module; not distribution-signed application"]

    @MainActor static func expect(_ condition: @autoclosure () throws -> Bool, _ description: String) throws {
        guard try condition() else {
            throw NSError(domain: "DaBinStoreSandboxSmoke", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: description])
        }
        var checks = evidence["checks"] as! [String]
        checks.append(description)
        evidence["checks"] = checks
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    @MainActor static func main() async {
        do {
            try await run()
            evidence["passed"] = true
        } catch {
            evidence["error"] = String(describing: error)
        }
        let encoded = try! JSONSerialization.data(withJSONObject: evidence, options: [.sortedKeys])
        print(String(decoding: encoded, as: UTF8.self))
        if evidence["passed"] as? Bool != true { exit(1) }
    }

    @MainActor static func run() async throws {
        let arguments = CommandLine.arguments
        try expect(arguments.count == 4, "Only phase, unique bundle ID, and synthetic denial fixture are supplied")
        let phase = arguments[1]
        let identifier = arguments[2]
        evidence["phase"] = phase
        evidence["bundleIdentifier"] = identifier
        try expect(["save", "reopen-export"].contains(phase), "The fixture phase is known")
        try expect(identifier.hasPrefix("com.dabin.qa.sandbox.") && Bundle.main.bundleIdentifier == identifier,
                   "The process has its unique test-only bundle identity")
        guard let task = SecTaskCreateFromSelf(nil) else { throw CaptureStoreError.invalidManagedPath }
        let sandbox = SecTaskCopyValueForEntitlement(task, "com.apple.security.app-sandbox" as CFString, nil)
        try expect((sandbox as? NSNumber)?.boolValue == true, "The running process has App Sandbox enabled")
        let network = SecTaskCopyValueForEntitlement(task, "com.apple.security.network.client" as CFString, nil)
        let userSelected = SecTaskCopyValueForEntitlement(task, "com.apple.security.files.user-selected.read-write" as CFString, nil)
        try expect((network as? NSNumber)?.boolValue != true && (userSelected as? NSNumber)?.boolValue != true,
                   "The fixture has no network or user-selected file-access entitlements")

        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).standardizedFileURL
        try expect(Array(home.pathComponents.suffix(4)) == ["Library", "Containers", identifier, "Data"],
                   "Foundation routes this process to its unique App Sandbox container")
        evidence["containerHome"] = home.path
        let denial = URL(fileURLWithPath: arguments[3], isDirectory: true)
        let readPath = denial.appendingPathComponent("FictionalPrivate.txt").path
        let readFD = readPath.withCString { Darwin.open($0, O_RDONLY) }
        let readError = errno
        if readFD >= 0 { Darwin.close(readFD) }
        evidence["deniedReadErrno"] = readError
        try expect(readFD == -1 && [EPERM, EACCES].contains(readError),
                   "Reading the ungranted fictional private file is denied by the sandbox")
        let writePath = denial.appendingPathComponent("ForbiddenOutput.txt").path
        let writeFD = writePath.withCString { Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL, mode_t(0o600)) }
        let writeError = errno
        if writeFD >= 0 { Darwin.close(writeFD) }
        evidence["deniedWriteErrno"] = writeError
        try expect(writeFD == -1 && [EPERM, EACCES].contains(writeError),
                   "Writing an ungranted fictional private sibling is denied by the sandbox")

        let files = FileManager.default
        let support = try files.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true).standardizedFileURL
        try expect(support.path.hasPrefix(home.path + "/"), "Application Support belongs to this fixture container")
        let root = support.appendingPathComponent("DaBinSandboxSmoke", isDirectory: true)
        let archive = root.appendingPathComponent("Archive", isDirectory: true)
        let receiptURL = root.appendingPathComponent("FixtureReceipt.json")
        evidence["fixtureRoot"] = root.path
        let updater = SoftwareUpdateService()
        try expect(!updater.isDirectChannel && !updater.canCheck && !updater.canInstall,
                   "The linked production core is the Store channel")

        if phase == "save" {
            try expect(!files.fileExists(atPath: root.path), "The synthetic archive starts fresh")
            let store = try CaptureStore(root: archive)
            let body = "  Fictional quartz lantern notes\nSecond line 🟣\n"
            let comment = "Synthetic violet checkpoint"
            let original = Data("{\"fixture\":\"fictional quartz lantern\"}\n".utf8)
            let at = ISO8601DateFormatter().date(from: "2026-09-21T12:13:14Z")!
            let zone = TimeZone(secondsFromGMT: 0)!
            let note = try store.capture(text: body, at: at, timeZone: zone)[0]
            try store.update(note, comment: comment, reminderAt: nil, reminderTimeZoneID: nil)
            let file = try await store.importData(original, filename: "Fictional.json", at: at, timeZone: zone)
            try store.save()
            try expect(store.captures.count == 2 && store.error == nil, "Production capture and import save without archive warnings")
            let receipt = Receipt(noteID: note.id, fileID: file.id, body: body, comment: comment,
                                  original: original, capturedAt: at)
            try JSONEncoder().encode(receipt).write(to: receiptURL, options: [.atomic])
            evidence["savedCaptureIDs"] = [note.id.uuidString, file.id.uuidString]
            return
        }

        let receipt = try JSONDecoder().decode(Receipt.self, from: Data(contentsOf: receiptURL))
        let store = try CaptureStore(root: archive)
        try expect(store.captures.count == 2 && store.error == nil, "A second sandbox process reopens the saved archive without warnings")
        guard let note = store.captures.first(where: { $0.id == receipt.noteID }),
              let file = store.captures.first(where: { $0.id == receipt.fileID }),
              let managed = store.managedURL(for: file) else { throw CaptureStoreError.importVerificationFailed }
        try expect(note.originalText == receipt.body && note.comment == receipt.comment,
                   "Capture identity, exact original text, and comment survive process relaunch")
        try expect(try Data(contentsOf: managed) == receipt.original, "Imported original bytes survive process relaunch")
        let results = CaptureSearch.groups(captures: store.captures, query: "quartz lantern", filter: .all,
                                           includeContext: false).flatMap(\.entries)
        try expect(results.contains { $0.isMatch && $0.capture.id == receipt.noteID },
                   "Production search finds the reopened fictional original text")
        let comments = CaptureSearch.groups(captures: store.captures, query: "violet checkpoint", filter: .all,
                                            includeContext: false).flatMap(\.entries)
        try expect(comments.count == 1 && comments[0].capture.id == receipt.noteID && comments[0].isMatch,
                   "Production search finds the persisted synthetic comment")
        let day = DayExportDocument.make(captures: store.captures, selectedDate: receipt.capturedAt,
                                         now: receipt.capturedAt.addingTimeInterval(60), calendarTimeZone: TimeZone(secondsFromGMT: 0)!)
        let exported = root.appendingPathComponent(day.filename)
        try day.utf8Data.write(to: exported, options: [.withoutOverwriting])
        try expect(day.actionCount == 2 && day.text.contains("Fictional quartz lantern notes") && day.text.contains(receipt.comment),
                   "Production day export includes both saved actions and the comment")
        try expect(try Data(contentsOf: exported) == day.utf8Data, "The sandbox can publish and reread its own day export")
        let zip = root.appendingPathComponent("FictionalCollection.zip")
        try ShelfExport.write(ShelfExport.entries(for: store.captures, store: store), to: zip)
        let zipBytes = try Data(contentsOf: zip)
        try expect(zipBytes.count > 4 && Array(zipBytes.prefix(4)) == [0x50, 0x4b, 0x03, 0x04],
                   "Production collection ZIP export publishes a readable archive inside the container")
        try expect(try Data(contentsOf: managed) == receipt.original && note.originalText == receipt.body,
                   "Export preserves the saved originals")
        evidence["dayExportSHA256"] = hash(day.utf8Data)
        evidence["collectionZIPBytes"] = zipBytes.count
        evidence["collectionZIPSHA256"] = hash(zipBytes)
        // Cleanup is restricted to the exact root created in the first phase.
        try files.removeItem(at: root)
        evidence["syntheticArchiveRemoved"] = true
    }
}
