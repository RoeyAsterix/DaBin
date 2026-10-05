import AppKit
import Darwin
import Foundation

private struct OutgoingBatchPublication {
    let captureID: UUID
    let snapshotURL: URL
}

/// Exercise production native file-URL/image/identity representations through
/// a private pasteboard. Copying into the receiving directory is this fixture's
/// explicit consumer operation, not proof of a physical drop, sandbox grant,
/// browser acceptance or live upload.
@main @MainActor private final class OutgoingFileBatchTests: NSObject, NSApplicationDelegate {
    private static var checks = 0
    private var result: Int32 = 1

    static func main() {
        setbuf(stdout, nil)
        let app = NSApplication.shared, delegate = OutgoingFileBatchTests()
        app.setActivationPolicy(.prohibited); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        exit(delegate.result)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do {
                try await Self.run()
                print("COMPLETE: OutgoingFileBatchTests finished all native URL reads, copies, delayed reads and cleanup")
                result = 0
            } catch { fputs("FAIL: Outgoing file batch QA: \(error)\n", stderr) }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "OutgoingFileBatchTests", code: checks, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        guard try condition() else { throw failure(message) }
    }

    private static func archiveMetadata(_ store: CaptureStore) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode((store.captures + store.trashedCaptures)
            .sorted { $0.id.uuidString < $1.id.uuidString }.map(CaptureSnapshot.init))
    }

    /// Only plain URL values and IDs escape. The temporary writer array and
    /// its snapshot owners are released independently of subsequent reads.
    private static func publish(_ captures: [Capture], store: CaptureStore,
                                pasteboard: NSPasteboard, stagingRoot: URL) throws -> [OutgoingBatchPublication] {
        try autoreleasepool {
            let writers = try ExplorerTransfer.pasteboardWriters(for: captures, store: store, stagingRoot: stagingRoot)
            try expect(writers.count == captures.count, "Production exports one native item per captured file")
            let values: [OutgoingBatchPublication] = try zip(captures, writers).map { capture, writer in
                try expect(writer.writableTypes(for: pasteboard).contains(.fileURL),
                    "Each production file writer advertises a native file URL")
                guard let raw = writer.pasteboardPropertyList(forType: .fileURL) as? String,
                      let url = URL(string: raw), url.isFileURL else {
                    throw failure("Production native writer is missing its valid snapshot URL")
                }
                let identity = writer.pasteboardPropertyList(forType: ExplorerTransfer.pasteboardType) as? Data
                try expect(identity.flatMap { try? ExplorerTransfer.decodeIDs($0) } == [capture.id],
                    "Each production native writer preserves its exact capture identity")
                return OutgoingBatchPublication(captureID: capture.id, snapshotURL: url)
            }
            try expect(pasteboard.writeObjects(writers), "Private native pasteboard accepts the production file writers")
            return values
        }
    }

    private static func requireRegularSnapshot(_ snapshot: URL, original: URL, stagingRoot: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: snapshot.path)
        let values = try snapshot.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isAliasFileKey])
        try expect(snapshot.isFileURL && attributes[.type] as? FileAttributeType == .typeRegular
            && values.isRegularFile == true && values.isSymbolicLink != true && values.isAliasFile != true,
            "Exported URL is a real regular, nonalias file rather than a symbolic link")
        try expect(snapshot.standardizedFileURL != original.standardizedFileURL
            && snapshot.resolvingSymlinksInPath() != original.resolvingSymlinksInPath(),
            "Export URL is independent of the mutable managed archive original")
        try expect(snapshot.deletingLastPathComponent().lastPathComponent == "Contents"
            && snapshot.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .resolvingSymlinksInPath().standardizedFileURL == stagingRoot.resolvingSymlinksInPath().standardizedFileURL,
            "Every export stays in the fixture-owned snapshot staging root")
    }

    private static func run() async throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("DaBinOutgoingBatchQA-" + UUID().uuidString, isDirectory: true)
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }
        let clipboardRevision = NSPasteboard.general.changeCount
        let store = try CaptureStore(root: root.appendingPathComponent("archive", isDirectory: true))
        defer { store.cancelArchiveRepair() }
        let maximumASCII = String(repeating: "a", count: 251) + ".txt"
        let multilingualStem = String(repeating: "資料", count: 100)
        let multilingual = multilingualStem + ".pdf"
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j8ocAAAAASUVORK5CYII=")!
        let fixtures = [
            ("Fictional.bin", Data([0, 1, 2, 127, 128, 254, 255]) + Data("Exact fictional binary bytes.\n".utf8)),
            ("Fictional.png", png),
            ("Report.txt", Data("First exact duplicate filename, café שלום.\n".utf8)),
            ("Report.txt", Data("Second exact duplicate filename, 日本語.\n".utf8)),
            (maximumASCII, Data("First 255-byte filename, exact fictional bytes.\n".utf8)),
            (maximumASCII, Data("Second 255-byte filename, different exact fictional bytes.\n".utf8)),
            (multilingual, Data("Fictional PDF-extension bytes for oversized multilingual metadata.\n".utf8)),
            ("Case.txt", Data("First case-equivalent original.\n".utf8)),
            ("case.txt", Data("Second case-equivalent original.\n".utf8))
        ]
        try expect(maximumASCII.utf8.count == 255 && multilingual.utf8.count > 255,
            "Filename fixtures cover the native component limit and oversized original metadata")
        var captures: [Capture] = []
        for (name, bytes) in fixtures {
            captures.append(try await store.importData(bytes, filename: name, projectName: "Before outgoing drag"))
        }
        let captureIDs = captures.map(\.id)
        let originals = captures.map { store.managedURL(for: $0)! }
        let metadataBeforePublication = try archiveMetadata(store)
        let stagingRoot = root.appendingPathComponent("outgoing snapshots", isDirectory: true)
        let board = NSPasteboard(name: .init("DaBin.OutgoingFileBatchQA." + UUID().uuidString))
        var boardReleased = false
        defer { if !boardReleased { board.clearContents(); board.releaseGlobally() } }
        let published = try publish(captures, store: store, pasteboard: board, stagingRoot: stagingRoot)
        let expectedNames = ["Fictional.bin", "Fictional.png", "Report.txt", "Report (2).txt",
            fixtures[4].0, String(repeating: "a", count: 247) + " (2).txt",
            String(multilingualStem.prefix(83)) + ".pdf", "Case.txt", "case (2).txt"]
        try expect(published.map(\.captureID) == captureIDs, "Native batch publication preserves all nine capture IDs in selection order")
        try expect(published.map { $0.snapshotURL.lastPathComponent } == expectedNames,
            "Native URL names preserve ordinary and uncollided 255-byte originals and bound/disambiguate only the necessary stems")
        try expect(Set(expectedNames.map { $0.precomposedStringWithCanonicalMapping.lowercased() }).count == fixtures.count,
            "Published native filenames are distinct on normalization/case-insensitive destinations")
        for (index, item) in published.enumerated() {
            try requireRegularSnapshot(item.snapshotURL, original: originals[index], stagingRoot: stagingRoot)
            try expect(try Data(contentsOf: item.snapshotURL) == fixtures[index].1,
                "Publication freezes each original's distinct full bytes")
            try expect(item.snapshotURL.lastPathComponent.utf8.count <= 255
                && item.snapshotURL.pathExtension == (fixtures[index].0 as NSString).pathExtension,
                "Every native snapshot leaf fits the UTF-8 byte limit and retains the complete original extension")
        }
        try expect(try archiveMetadata(store) == metadataBeforePublication,
            "Snapshot preparation and native publication never modify capture metadata")

        // Exercise real source mutations before any pasteboard NSURL consumer
        // asks for its bytes. Snapshots must outlive all former managed paths.
        try store.setOrganization(captures[0], pinned: true, projectName: "Filed after publication")
        try store.moveToTrash(captures[1])
        try store.moveToTrash(captures[2])
        guard let removed = store.trashedCaptures.first(where: { $0.id == captureIDs[2] }) else {
            throw failure("The selected report must reach Recently Deleted before permanent removal")
        }
        _ = try store.permanentlyRemove(removed)
        try expect(originals.prefix(3).allSatisfy { !files.fileExists(atPath: $0.path) },
            "Filing, trash and permanent deletion retire the three actual former source paths")
        try expect(!store.captures.contains { $0.id == captureIDs[2] }
            && !store.trashedCaptures.contains { $0.id == captureIDs[2] },
            "Delayed reads do not depend on a permanently deleted capture remaining in the live store")
        let metadataAfterSourceChanges = try archiveMetadata(store)
        var nativeItems = board.pasteboardItems ?? []
        try expect(nativeItems.count == fixtures.count, "All nine files remain distinct materialized native pasteboard items")
        for (index, item) in nativeItems.enumerated() {
            try expect(item.data(forType: ExplorerTransfer.pasteboardType).flatMap { try? ExplorerTransfer.decodeIDs($0) }
                == [captureIDs[index]], "Serialized native batch retains each exact identity and visible selection order")
            try expect(item.string(forType: .fileURL) == published[index].snapshotURL.absoluteString,
                "Serialized file URL refers to the frozen native snapshot rather than a moved managed location")
        }
        try expect(nativeItems[1].data(forType: .png) == png,
            "Lazy native PNG representation still materializes exact bytes after the original moved to Trash")
        let nativeURLs = (board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [NSURL] ?? [])
            .map { $0 as URL }
        try expect(nativeURLs.count == fixtures.count && nativeURLs == published.map(\.snapshotURL),
            "Actual native NSURL readObjects returns all nine independent snapshots in selection order")
        let destination = root.appendingPathComponent("receiving directory", isDirectory: true)
        try files.createDirectory(at: destination, withIntermediateDirectories: true)
        let sentinel = destination.appendingPathComponent("Unrelated receiver file.txt")
        let sentinelBytes = Data("Existing fixture destination content must survive.\n".utf8)
        try sentinelBytes.write(to: sentinel, options: .withoutOverwriting)
        var copiedURLs: [URL] = []
        for (index, url) in nativeURLs.enumerated() {
            try expect(try Data(contentsOf: url) == fixtures[index].1,
                "Delayed native NSURL consumer reads the exact original bytes after filing, trash and permanent deletion")
            let copied = destination.appendingPathComponent(url.lastPathComponent)
            try files.copyItem(at: url, to: copied)
            copiedURLs.append(copied)
            try expect(try Data(contentsOf: copied) == fixtures[index].1,
                "Fixture-owned receiving copy preserves each native item's exact distinct bytes")
        }
        try expect(try Set(files.contentsOfDirectory(atPath: destination.path)) == Set(expectedNames + [sentinel.lastPathComponent]),
            "Receiving directory contains all nine valid names and preserves its unrelated preexisting file")
        var rejectedOverwrite = false
        do { try files.copyItem(at: nativeURLs[1], to: copiedURLs[0]) }
        catch { rejectedOverwrite = true }
        let occupiedBytesAfterCopy = try Data(contentsOf: copiedURLs[0])
        let sentinelBytesAfterCopy = try Data(contentsOf: sentinel)
        try expect(rejectedOverwrite && occupiedBytesAfterCopy == fixtures[0].1
            && sentinelBytesAfterCopy == sentinelBytes,
            "A receiving copy refuses an occupied target without overwriting either original destination bytes or unrelated content")
        try expect(String(expectedNames[6].dropLast(4)) == String(multilingualStem.prefix(83))
            && !expectedNames[6].contains("\u{FFFD}"),
            "Oversized multilingual native filename ends at a complete original character with an undamaged extension")
        try expect(try archiveMetadata(store) == metadataAfterSourceChanges
            && captures.map(\.originalFilename) == fixtures.map { Optional($0.0) },
            "Native reads and receiving copies preserve full original filename metadata and all later capture changes")
        for index in fixtures.indices where index != 2 {
            guard let capture = (store.captures + store.trashedCaptures).first(where: { $0.id == captureIDs[index] }) else {
                throw failure("Surviving canonical source record missing at index \(index), filename \(fixtures[index].0)")
            }
            guard let current = store.managedURL(for: capture) else {
                throw failure("Surviving canonical source original missing at index \(index), filename \(fixtures[index].0)")
            }
            try expect(try Data(contentsOf: current) == fixtures[index].1,
                "Native consumption leaves the canonical surviving or trashed original unchanged at index \(index), filename \(fixtures[index].0)")
        }

        // Drop all materialized item/provider references and release the named
        // board. Retain only plain URL values for delayed uploader-style reads.
        nativeItems.removeAll()
        board.clearContents(); board.releaseGlobally(); boardReleased = true
        for (index, url) in nativeURLs.enumerated() {
            try expect(try Data(contentsOf: url) == fixtures[index].1
                && Data(contentsOf: copiedURLs[index]) == fixtures[index].1,
                "Frozen native export and receiving copy remain readable after publication ownership is released")
        }
        try expect(try archiveMetadata(store) == metadataAfterSourceChanges,
            "Publication release and delayed URL reads do not resurrect or mutate removed captures")
        try expect(NSPasteboard.general.changeCount == clipboardRevision,
            "Private native batch checks never read or replace the user's general clipboard contents")
        print("PASS: \(checks) outgoing native file batch checks; nine actual NSURL reads and exact receiving copies, bounded/case-equivalent filenames, source filing/trash/removal, no-overwrite and publication lifetime. Own-process native URL delivery only.")
    }
}
