import Foundation
import CryptoKit

/// Uses only disposable archives and fixture files; never opens the user's store.
@main struct CaptureRemovalTests {
    @MainActor private static var checks = 0
    private static let files = FileManager.default

    @MainActor private static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        if try !value() { throw NSError(domain: "CaptureRemovalTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    @MainActor private static func rejected(_ action: () throws -> Void, _ message: String) throws {
        var failed = false
        do { try action() } catch { failed = true }
        try expect(failed, message)
    }

    private static func write(_ data: Data, to url: URL) throws {
        try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    private static func fixture(_ text: String, to url: URL) throws { try write(Data(text.utf8), to: url) }

    @MainActor static func main() async throws {
        let root = files.temporaryDirectory.appendingPathComponent("DaBinCaptureRemovalTests-\(UUID())")
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }
        try await completeRemoval(root.appendingPathComponent("complete"))
        try minimize(root.appendingPathComponent("minimize"))
        try await interruption(root.appendingPathComponent("before-commit"), checkpoint: .afterJournal, shouldRemove: false)
        try await interruption(root.appendingPathComponent("at-commit"), checkpoint: .beforeMetadataDelete, shouldRemove: false)
        try await interruption(root.appendingPathComponent("after-commit"), checkpoint: .afterMetadataDelete, shouldRemove: true)
        try await interruption(root.appendingPathComponent("before-cleanup"), checkpoint: .beforeFileCleanup, shouldRemove: true)
        try await interruption(root.appendingPathComponent("after-cleanup"), checkpoint: .afterFileCleanup, shouldRemove: true)
        try await ordinaryFailures(root.appendingPathComponent("failures"))
        try await unsafePaths(root.appendingPathComponent("unsafe"))
        try await staleReceipt(root.appendingPathComponent("receipt"))
        try await blockedReceipt(root.appendingPathComponent("blocked-receipt"))
        try await untrustedAttachment(root.appendingPathComponent("untrusted-attachment"))
        print("PASS: \(checks) capture removal/minimize checks")
    }

    @MainActor private static func completeRemoval(_ root: URL) async throws {
        let source = root.appendingPathComponent("source/keep-original.txt")
        let sourceData = Data("Original source must survive".utf8)
        try write(sourceData, to: source)
        var store: CaptureStore? = try CaptureStore(root: root.appendingPathComponent("store"))
        let capture = try await store!.importFile(source)
        let sibling = try store!.capture(text: "Neighbor stays")[0]
        let siblingURL = store!.archiveURL(for: sibling)!
        let siblingBytes = try Data(contentsOf: siblingURL.appendingPathComponent("Capture.json"))
        let archiveURL = store!.archiveURL(for: capture)!
        let folderNames = ["Originals", "Previews", "Staging", "MigrationStaging"]
        for name in folderNames {
            try fixture("owned recovery/cache bytes", to: store!.root.appendingPathComponent("\(name)/\(capture.id)/fixture.bin"))
        }
        try fixture("saved edit", to: archiveURL.appendingPathComponent("Local edits/fixture.md"))
        let unrelated = store!.root.appendingPathComponent("Originals/unknown-safety-copy/keep.txt")
        try fixture("unclaimed bytes", to: unrelated)
        let result = try store!.remove(capture)
        try expect(!result.cleanupPending && result.warning == nil, "Complete removal reports success")
        try expect(store!.captures.map(\.id) == [sibling.id], "Only selected capture leaves the live list")
        try expect(!files.fileExists(atPath: archiveURL.path), "Capture folder and local-edit copies are removed")
        for name in folderNames {
            try expect(!files.fileExists(atPath: store!.root.appendingPathComponent("\(name)/\(capture.id)").path), "Owned \(name) folder is removed")
        }
        try expect(try Data(contentsOf: source) == sourceData, "Source original remains byte-for-byte intact")
        try expect(try Data(contentsOf: siblingURL.appendingPathComponent("Capture.json")) == siblingBytes, "Neighbor archive is untouched")
        try expect(files.fileExists(atPath: unrelated.path), "Unclaimed files outside owned capture paths are preserved")
        try expect(try files.contentsOfDirectory(atPath: store!.root.appendingPathComponent("Deletions").path).isEmpty, "Successful removal clears its intent")
        try rejected({ try store!.save(captures: [capture]) }, "A late preview or notification save cannot recreate a deleted capture")
        try rejected({ try store!.update(capture, comment: "stale", reminderAt: nil, reminderTimeZoneID: nil) }, "Stale detail edits cannot recreate a deleted capture")
        try rejected({ _ = try store!.prepareArchiveFolder(for: capture) }, "Opening a stale record folder cannot recreate it")
        try rejected({ _ = try store!.remove(capture) }, "Double removal is rejected without touching other captures")
        let storeURL = store!.root
        store = nil
        let reopened = try CaptureStore(root: storeURL)
        try expect(reopened.captures.map(\.id) == [sibling.id], "Removal survives reopening")
        try expect(!files.fileExists(atPath: archiveURL.path), "Relaunch does not regenerate deleted sidecars")
    }

    @MainActor private static func minimize(_ root: URL) throws {
        var store: CaptureStore? = try CaptureStore(root: root)
        let capture = try store!.capture(text: "Can be collapsed")[0]
        let originalDate = capture.capturedAt
        try expect(!capture.isMinimized, "New captures begin expanded")
        try store!.setMinimized(capture, minimized: true)
        try expect(capture.isMinimized, "Minimize updates the record immediately")
        try expect(capture.capturedAt == originalDate, "Minimize preserves capture time")
        let id = capture.id
        store = nil
        store = try CaptureStore(root: root)
        let reopened = store!.captures.first(where: { $0.id == id })!
        try expect(reopened.isMinimized, "Minimize persists after relaunch")
        let savedDate = reopened.updatedAt
        store!.failureInjector = { checkpoint in
            if checkpoint == .beforeMetadataSave { throw CaptureStoreError.importVerificationFailed }
        }
        try rejected({ try store!.setMinimized(reopened, minimized: false) }, "A failed minimize edit reports failure")
        try expect(reopened.isMinimized && reopened.updatedAt == savedDate, "Failed edit rolls back both display state and update time")
        store!.failureInjector = nil
        try store!.setMinimized(reopened, minimized: false)
        try expect(!reopened.isMinimized, "Restore expands the record")
        let stale = Capture(snapshot: CaptureSnapshot(reopened))
        try rejected({ try store!.setMinimized(stale, minimized: true) }, "A stale clone cannot overwrite current display state")
    }

    @MainActor private static func interruption(_ root: URL, checkpoint: RemovalCheckpoint, shouldRemove: Bool) async throws {
        var store: CaptureStore? = try CaptureStore(root: root)
        let capture = try await store!.importData(Data("Recoverable bytes".utf8), filename: "archive.txt")
        let id = capture.id
        let archive = store!.archiveURL(for: capture)!
        store!.removalFailureInjector = { if $0 == checkpoint { throw CaptureStoreError.injectedInterruption } }
        try rejected({ _ = try store!.remove(capture) }, "Interruption is modeled at \(checkpoint)")
        store = nil
        let reopened = try CaptureStore(root: root)
        try expect(reopened.captures.contains { $0.id == id } != shouldRemove, "\(checkpoint): metadata outcome follows commit boundary")
        try expect(files.fileExists(atPath: archive.path) != shouldRemove, "\(checkpoint): original bytes follow metadata outcome")
        try expect(try files.contentsOfDirectory(atPath: root.appendingPathComponent("Deletions").path).isEmpty, "\(checkpoint): recovery completes the intent")
        try expect(reopened.error == nil, "\(checkpoint): clean recovery reports no stale warning")
    }

    @MainActor private static func ordinaryFailures(_ root: URL) async throws {
        var store: CaptureStore? = try CaptureStore(root: root)
        let capture = try await store!.importData(Data("Kept before commit".utf8), filename: "original.txt")
        let archive = store!.archiveURL(for: capture)!
        store!.removalFailureInjector = { if $0 == .beforeMetadataDelete { throw CaptureStoreError.importVerificationFailed } }
        try rejected({ _ = try store!.remove(capture) }, "Metadata failure is surfaced")
        try expect(store!.captures.contains { $0.id == capture.id } && files.fileExists(atPath: archive.path), "Metadata failure preserves record and originals")
        try expect(try files.contentsOfDirectory(atPath: root.appendingPathComponent("Deletions").path).isEmpty, "Aborted removal discards preparation")
        store!.removalFailureInjector = { if $0 == .beforeFileCleanup { throw CaptureStoreError.importVerificationFailed } }
        let result = try store!.remove(capture)
        try expect(result.cleanupPending && result.warning != nil, "Post-commit file failure reports pending cleanup rather than false deletion failure")
        try expect(store!.captures.isEmpty && files.fileExists(atPath: archive.path), "Pending cleanup retains files while removed record stays absent")
        store = nil
        let reopened = try CaptureStore(root: root)
        try expect(reopened.captures.isEmpty && !files.fileExists(atPath: archive.path), "Next launch retries and finishes file cleanup")
    }

    @MainActor private static func unsafePaths(_ root: URL) async throws {
        let external = root.appendingPathComponent("outside/keep.txt")
        try fixture("External data stays", to: external)
        var store: CaptureStore? = try CaptureStore(root: root.appendingPathComponent("store"))
        let capture = try await store!.importData(Data("Owned".utf8), filename: "owned.txt")
        let preview = store!.root.appendingPathComponent("Previews/\(capture.id)")
        try files.createDirectory(at: preview.deletingLastPathComponent(), withIntermediateDirectories: true)
        try files.createSymbolicLink(at: preview, withDestinationURL: external.deletingLastPathComponent())
        try rejected({ _ = try store!.remove(capture) }, "Symlinked owned path prevents deletion before commit")
        try expect(store!.captures.count == 1, "Rejected unsafe removal preserves record")
        try expect(try String(contentsOf: external, encoding: .utf8) == "External data stays", "Unsafe removal never follows the symlink")
        try files.removeItem(at: preview)
        try fixture("Unrecognized obstruction", to: preview)
        try rejected({ _ = try store!.remove(capture) }, "A file in place of an expected folder is preserved")
        try expect(files.fileExists(atPath: preview.path), "Unknown obstruction remains intact")
        try files.removeItem(at: preview)
        // A symlink nested inside a known owned folder is unlinked by recursive
        // removal, never followed into a different capture or source directory.
        let archive = store!.archiveURL(for: capture)!
        try files.createSymbolicLink(at: archive.appendingPathComponent("link-to-outside"), withDestinationURL: external.deletingLastPathComponent())
        _ = try store!.remove(capture)
        try expect(try String(contentsOf: external, encoding: .utf8) == "External data stays", "Deleting a capture folder never follows a nested link")

        let malformedID = UUID()
        try fixture("broken journal", to: store!.root.appendingPathComponent("Deletions/\(malformedID).json"))
        let storeURL = store!.root
        store = nil
        let reopened = try CaptureStore(root: storeURL)
        try expect(reopened.error?.contains("removal could not finish safely") == true, "Malformed deletion intent is reported")
        try expect(files.fileExists(atPath: storeURL.appendingPathComponent("Deletions/\(malformedID).json").path), "Malformed intent remains for safe recovery")
    }

    @MainActor private static func staleReceipt(_ root: URL) async throws {
        var store: CaptureStore? = try CaptureStore(root: root)
        let content = Data("Receipt must never resurrect this capture".utf8)
        let capture = try await store!.importData(content, filename: "receipt.txt")
        let importReceipt = ImportJournal(id: capture.id, capturedAt: capture.capturedAt, captureDay: capture.captureDay,
            timeZoneID: capture.captureTimeZoneID, utcOffset: capture.captureUTCOffsetSeconds,
            originalFilename: capture.originalFilename!, sourceFilePath: nil, sourceURL: nil,
            relativePath: capture.attachmentRelativePath!, stagingRelativePath: "Staging/\(capture.id)/receipt.txt",
            kind: .document, contentType: "public.plain-text", phase: "moved", byteCount: Int64(content.count),
            sha256: SHA256.hash(data: content).map { String(format: "%02x", $0) }.joined())
        let receiptURL = root.appendingPathComponent("Imports/\(capture.id).json")
        try JSONEncoder().encode(importReceipt).write(to: receiptURL)
        let archive = store!.archiveURL(for: capture)!
        store!.removalFailureInjector = { if $0 == .afterMetadataDelete { throw CaptureStoreError.injectedInterruption } }
        try rejected({ _ = try store!.remove(capture) }, "Crash leaves stale import receipt after committed deletion")
        store = nil
        let reopened = try CaptureStore(root: root)
        try expect(reopened.captures.isEmpty, "Deletion recovery runs before import recovery, preventing resurrection")
        try expect(!files.fileExists(atPath: receiptURL.path) && !files.fileExists(atPath: archive.path), "Deleted receipt and its original bytes are removed")
    }

    @MainActor private static func blockedReceipt(_ root: URL) async throws {
        let outside = root.appendingPathComponent("outside/untouched.json")
        try fixture("Unrelated external file", to: outside)
        let storeURL = root.appendingPathComponent("store")
        var store: CaptureStore? = try CaptureStore(root: storeURL)
        let capture = try await store!.importData(Data("Owned bytes".utf8), filename: "owned.txt")
        store!.removalFailureInjector = { if $0 == .afterMetadataDelete { throw CaptureStoreError.injectedInterruption } }
        try rejected({ _ = try store!.remove(capture) }, "A post-commit interruption leaves recovery intent")
        let receipt = storeURL.appendingPathComponent("Imports/\(capture.id).json")
        try files.createSymbolicLink(at: receipt, withDestinationURL: outside)
        store = nil
        store = try CaptureStore(root: storeURL)
        try expect(store!.captures.isEmpty, "A blocked receipt cannot resurrect a deleted capture")
        try expect(store!.error?.contains("removal could not finish safely") == true, "Cleanup obstruction stays visible after import recovery")
        try expect(store!.error?.contains("blocks recovery") == true, "Pending intent explicitly blocks import recovery")
        try expect(try String(contentsOf: outside, encoding: .utf8) == "Unrelated external file", "Cleanup never follows an untrusted import receipt")
        try expect(files.fileExists(atPath: storeURL.appendingPathComponent("Deletions/\(capture.id).json").path), "Intent is kept until all owned cleanup finishes")
        try files.removeItem(at: receipt)
        store = nil
        store = try CaptureStore(root: storeURL)
        try expect(store!.captures.isEmpty && store!.error == nil, "Fixing the obstruction completes pending removal on relaunch")
    }

    @MainActor private static func untrustedAttachment(_ root: URL) async throws {
        let store = try CaptureStore(root: root)
        let neighbor = try await store.importData(Data("Neighbor's bytes".utf8), filename: "neighbor.txt")
        let removed = try store.capture(text: "Untrusted attachment metadata")[0]
        let neighborURL = store.managedURL(for: neighbor)!
        removed.relocateManagedAttachment(to: neighbor.attachmentRelativePath!)
        // Model a corrupted persisted attachment path. Removal must derive owned
        // paths from immutable identity, never trust this foreign attachment.
        try store.save(captures: [removed])
        _ = try store.remove(removed)
        try expect(try String(contentsOf: neighborURL, encoding: .utf8) == "Neighbor's bytes", "Removal ignores a persisted attachment path owned by another capture")
        try expect(store.captures.map(\.id) == [neighbor.id], "Neighbor survives untrusted attachment metadata")
    }
}
