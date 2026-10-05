import AppKit
import CryptoKit
import Darwin
import Foundation
import UniformTypeIdentifiers

private struct OutgoingPromiseRead: Sendable {
    let receiverIndex: Int
    let url: URL
    let bytes: Data?
    let error: String?
}

private final class OutgoingPromiseReads: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [OutgoingPromiseRead] = []
    func append(_ value: OutgoingPromiseRead) {
        lock.lock(); values.append(value); lock.unlock()
    }
    func snapshot() -> [OutgoingPromiseRead] {
        lock.lock(); defer { lock.unlock() }; return values
    }
}

private struct OutgoingPublishedItem {
    let captureID: UUID
    let snapshotURL: URL
    let types: [String]
}

/// Production file promises are fulfilled through the public receiver API on a
/// private pasteboard. This is own-process native promise delivery, not proof of
/// WindowServer drag-end, sandbox grants, browser acceptance or live uploads.
@main @MainActor private final class OutgoingFilePromiseTests: NSObject, NSApplicationDelegate {
    private static var checks = 0
    private static var actualCallbacks = 0
    private var result: Int32 = 1

    static func main() {
        setbuf(stdout, nil)
        let app = NSApplication.shared, delegate = OutgoingFilePromiseTests()
        app.setActivationPolicy(.prohibited); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        exit(delegate.result)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do {
                try await Self.run()
                print("COMPLETE: OutgoingFilePromiseTests finished every receiver fixture and cleanup")
                result = 0
            } catch { fputs("FAIL: Outgoing file promise QA: \(error)\n", stderr) }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "OutgoingFilePromiseTests", code: checks, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        guard try condition() else { throw failure(message) }
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func archiveMetadata(_ store: CaptureStore) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode((store.captures + store.trashedCaptures)
            .sorted { $0.id.uuidString < $1.id.uuidString }.map(CaptureSnapshot.init))
    }

    /// No writer/delegate/session-owner reference escapes this lexical scope.
    /// AppKit must retain its registered promises, and exported paths must not
    /// depend on the lifetime of this function's temporary writer array.
    private static func publish(_ captures: [Capture], store: CaptureStore,
                                pasteboard: NSPasteboard, stagingRoot: URL) throws -> [OutgoingPublishedItem] {
        try autoreleasepool {
            let writers = try ExplorerTransfer.pasteboardWriters(for: captures, store: store, stagingRoot: stagingRoot)
            try expect(writers.count == captures.count, "Each captured file has one native pasteboard item")
            let promiseTypes = Set(NSFilePromiseReceiver.readableDraggedTypes)
            let published: [OutgoingPublishedItem] = try zip(captures, writers).map { capture, writer in
                let types = writer.writableTypes(for: pasteboard).map(\.rawValue)
                try expect(!promiseTypes.isDisjoint(with: types), "Each native file item advertises a real file promise")
                try expect(types.contains(NSPasteboard.PasteboardType.fileURL.rawValue),
                    "A promised file retains its native NSURL fallback")
                guard let raw = writer.pasteboardPropertyList(forType: .fileURL) as? String,
                      let url = URL(string: raw), url.isFileURL else {
                    throw failure("Production file promise is missing its valid native file URL")
                }
                let identity = writer.pasteboardPropertyList(forType: ExplorerTransfer.pasteboardType) as? Data
                try expect(identity.flatMap { try? ExplorerTransfer.decodeIDs($0) } == [capture.id],
                    "A native file promise preserves only its original capture ID")
                return OutgoingPublishedItem(captureID: capture.id, snapshotURL: url, types: types)
            }
            try expect(pasteboard.writeObjects(writers), "Private pasteboard accepts production file promise providers")
            return published
        }
    }

    private static func receive(_ receivers: [NSFilePromiseReceiver], at destination: URL,
                                expectedCallbacks: Int) async throws -> [OutgoingPromiseRead] {
        let queue = OperationQueue()
        queue.name = "DaBin.OutgoingFilePromiseQA.receiver"; queue.maxConcurrentOperationCount = 1
        let reads = OutgoingPromiseReads()
        for (index, receiver) in receivers.enumerated() {
            receiver.receivePromisedFiles(atDestination: destination, options: [:], operationQueue: queue) { url, error in
                if let error {
                    reads.append(OutgoingPromiseRead(receiverIndex: index, url: url, bytes: nil,
                        error: error.localizedDescription))
                    return
                }
                do {
                    // NSFilePromiseReceiver coordinates this reader. Read inside
                    // its callback rather than retaining a temporary read scope.
                    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                    guard attributes[.type] as? FileAttributeType == .typeRegular,
                          url.standardizedFileURL.deletingLastPathComponent() == destination.standardizedFileURL,
                          url.resolvingSymlinksInPath().deletingLastPathComponent() == destination.resolvingSymlinksInPath() else {
                        throw NSError(domain: "OutgoingFilePromiseTests", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Receiver output must be a regular file in its owned destination"])
                    }
                    reads.append(OutgoingPromiseRead(receiverIndex: index, url: url,
                        bytes: try Data(contentsOf: url), error: nil))
                } catch {
                    reads.append(OutgoingPromiseRead(receiverIndex: index, url: url, bytes: nil,
                        error: error.localizedDescription))
                }
            }
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while reads.snapshot().count < expectedCallbacks && ContinuousClock.now < deadline {
            // Yield MainActor for AppKit's promise request and completion IPC.
            try await Task.sleep(for: .milliseconds(20))
        }
        let results = reads.snapshot()
        actualCallbacks += results.count
        if results.count != expectedCallbacks { queue.cancelAllOperations() }
        try expect(results.count == expectedCallbacks,
            "Every actual NSFilePromiseReceiver produces exactly one bounded completion (got \(results.count)/\(expectedCallbacks))")
        return results.sorted { $0.receiverIndex < $1.receiverIndex }
    }

    private static func run() async throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("DaBinOutgoingPromiseQA-" + UUID().uuidString, isDirectory: true)
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }
        let clipboardRevision = NSPasteboard.general.changeCount
        let store = try CaptureStore(root: root.appendingPathComponent("archive", isDirectory: true))
        defer { store.cancelArchiveRepair() }
        let binary = Data([0, 1, 2, 127, 128, 254, 255]) + Data("Fictional promised file\n".utf8)
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j8ocAAAAASUVORK5CYII=")!
        let firstReport = Data("First exact duplicate filename, café שלום.\n".utf8)
        let secondReport = Data("Second exact duplicate filename, 日本語.\n".utf8)
        let fixtures = [("Fictional.bin", binary), ("Fictional.png", png),
                        ("Report.txt", firstReport), ("Report.txt", secondReport)]
        var captures: [Capture] = []
        for (name, bytes) in fixtures {
            captures.append(try await store.importData(bytes, filename: name, projectName: "Before outgoing drag"))
        }
        let captureIDs = captures.map(\.id)
        let oldURLs = captures.map { store.managedURL(for: $0)! }
        let board = NSPasteboard(name: .init("DaBin.OutgoingFilePromiseQA." + UUID().uuidString))
        var boardReleased = false
        defer { if !boardReleased { board.releaseGlobally() } }
        let published = try publish(captures, store: store, pasteboard: board, stagingRoot: root.appendingPathComponent("outgoing snapshots"))
        try expect(published.map(\.captureID) == captureIDs, "Mixed native file promises preserve selection order")
        for (index, item) in published.enumerated() {
            try expect(try Data(contentsOf: item.snapshotURL) == fixtures[index].1,
                "Export snapshot retains exact original bytes before source changes")
        }

        // None of the native writer/delegate refs is retained by this fixture.
        // Exercise ordinary source relocation and actual permanent removal
        // before the receiving application calls in the published promises.
        try store.setOrganization(captures[0], pinned: true, projectName: "Filed after publication")
        try store.moveToTrash(captures[1])
        try store.moveToTrash(captures[2])
        let removed = store.trashedCaptures.first { $0.id == captureIDs[2] }!
        _ = try store.permanentlyRemove(removed)
        try expect(!files.fileExists(atPath: oldURLs[0].path) && !files.fileExists(atPath: oldURLs[1].path)
            && !files.fileExists(atPath: oldURLs[2].path),
            "Filing, trash and permanent deletion retire the actual original source paths")
        let surviving = store.captures.first { $0.id == captureIDs[3] }!
        let survivingURL = store.managedURL(for: surviving)!
        try expect(try Data(contentsOf: survivingURL) == secondReport,
            "Other duplicate-name original remains unchanged")
        let metadataAfterSourceChanges = try archiveMetadata(store)
        let nativeItems = board.pasteboardItems ?? []
        try expect(nativeItems.count == fixtures.count, "The private native pasteboard contains all four file items")
        for (index, item) in nativeItems.enumerated() {
            let identity = item.data(forType: ExplorerTransfer.pasteboardType)
            try expect(identity.flatMap { try? ExplorerTransfer.decodeIDs($0) } == [captureIDs[index]],
                "Materialized native pasteboard retains the selected file's internal ID")
        }
        try expect(nativeItems[1].data(forType: .png) == png,
            "Native image bytes remain readable after the source moved to Recently Deleted")
        let receivers = board.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver] ?? []
        try expect(receivers.count == fixtures.count, "AppKit constructs one real receiver for each production file promise")
        let destination = root.appendingPathComponent("receiver", isDirectory: true)
        try files.createDirectory(at: destination, withIntermediateDirectories: true)
        let sentinel = destination.appendingPathComponent("Unrelated receiver file.txt")
        let sentinelBytes = Data("Existing receiver file must survive.\n".utf8)
        try sentinelBytes.write(to: sentinel, options: .withoutOverwriting)
        let results = try await receive(receivers, at: destination, expectedCallbacks: fixtures.count)
        try expect(results.allSatisfy { $0.error == nil },
            "All production file promises complete successfully: " + results.compactMap(\.error).joined(separator: "; "))
        let names = results.map { $0.url.lastPathComponent }
        try expect(Set(names.map { $0.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX")) }).count == fixtures.count,
            "Duplicate promised names become distinct destination files without overwriting another capture")
        for (index, read) in results.enumerated() {
            try expect(read.receiverIndex == index && read.bytes == fixtures[index].1,
                "Actual receiver copies each exact original byte sequence in selection order")
            try expect(receivers[index].fileNames == [read.url.lastPathComponent],
                "Actual receiver reports the exact delivered filename")
            let expectedName = fixtures[index].0
            if index < 2 {
                try expect(read.url.lastPathComponent == expectedName, "Unique originals retain recognizable promised filenames")
            } else {
                try expect(read.url.pathExtension == "txt" && read.url.deletingPathExtension().lastPathComponent.hasPrefix("Report"),
                    "Duplicate report promises retain a recognizable basename and original extension")
            }
        }
        try expect(names[2] != names[3] && names.contains("Report.txt"),
            "Only a duplicate promised name is disambiguated; the original name is retained once")
        try expect(try Data(contentsOf: sentinel) == sentinelBytes, "Receiving multiple promises preserves existing unrelated destination files")
        try expect(try archiveMetadata(store) == metadataAfterSourceChanges
            && Data(contentsOf: survivingURL) == secondReport,
            "Promise fulfillment does not mutate captures, annotations, organization or surviving originals")

        board.clearContents(); board.releaseGlobally(); boardReleased = true
        // Retain only plain URL values after publisher/pasteboard ownership ends.
        // This is the delayed uploader lifetime contract, not a simulated drag.
        for (index, item) in published.enumerated() {
            try expect(try Data(contentsOf: item.snapshotURL) == fixtures[index].1,
                "Export URL remains readable after native publication ownership is released")
            try expect(try Data(contentsOf: results[index].url) == fixtures[index].1,
                "Destination-owned copy remains readable after publication ownership is released")
        }
        try await occupiedDestination(store: store, root: root)
        try await filenameBoundaryReceivers(store: store, root: root)
        try expect(NSPasteboard.general.changeCount == clipboardRevision,
            "Native file promises never replace or read the user's general clipboard")
        print("PASS: \(checks) outgoing file promise checks; \(actualCallbacks) actual receiver callbacks, exact originals, duplicate/case-equivalent/boundary filenames, relocation/trash/removal and publication lifetime. Own-process delivery only.")
    }

    private static func filenameBoundaryReceivers(store: CaptureStore, root: URL) async throws {
        let maximumASCII = String(repeating: "a", count: 251) + ".txt"
        let multilingualStem = String(repeating: "資料", count: 100)
        let multilingual = multilingualStem + ".pdf"
        let fixtures = [
            (maximumASCII, Data("First 255-byte filename, exact fictional bytes.\n".utf8)),
            (maximumASCII, Data("Second 255-byte filename, different exact fictional bytes.\n".utf8)),
            (multilingual, Data("Fictional PDF-extension bytes for oversized multilingual metadata.\n".utf8)),
            ("Case.txt", Data("First case-equivalent original.\n".utf8)),
            ("case.txt", Data("Second case-equivalent original.\n".utf8))
        ]
        try expect(maximumASCII.utf8.count == 255 && multilingual.utf8.count > 255,
            "Boundary fixtures exercise a valid maximum-length basename and oversized original metadata")
        var captures: [Capture] = []
        for (name, bytes) in fixtures {
            captures.append(try await store.importData(bytes, filename: name, projectName: "Filename boundaries"))
        }
        let metadata = try archiveMetadata(store)
        let board = NSPasteboard(name: .init("DaBin.OutgoingFilePromiseFilenameQA." + UUID().uuidString))
        defer { board.releaseGlobally() }
        let published = try publish(captures, store: store, pasteboard: board,
            stagingRoot: root.appendingPathComponent("outgoing snapshots"))
        // These explicit expected names describe the public contract, including
        // suffix space and a complete-character Unicode cut before the extension.
        let boundedMultilingual = String(multilingualStem.prefix(83)) + ".pdf"
        let expectedSnapshotNames = [maximumASCII, maximumASCII, boundedMultilingual, "Case.txt", "case.txt"]
        let expectedPromisedNames = [maximumASCII, String(repeating: "a", count: 247) + " (2).txt",
            boundedMultilingual, "Case.txt", "case (2).txt"]
        for (index, item) in published.enumerated() {
            try expect(item.captureID == captures[index].id
                && item.snapshotURL.lastPathComponent == expectedSnapshotNames[index],
                "Snapshot preserves valid original names and bounds oversized metadata using complete characters")
            try expect(try Data(contentsOf: item.snapshotURL) == fixtures[index].1,
                "Filename normalization preserves every original byte sequence")
        }
        let nativeItems = board.pasteboardItems ?? []
        try expect(nativeItems.count == fixtures.count, "All filename-boundary items survive native pasteboard publication")
        for (index, item) in nativeItems.enumerated() {
            try expect(item.data(forType: ExplorerTransfer.pasteboardType).flatMap { try? ExplorerTransfer.decodeIDs($0) }
                == [captures[index].id], "Filename disambiguation retains the exact original capture identity")
        }
        let receivers = board.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver] ?? []
        try expect(receivers.count == fixtures.count, "Boundary and case-equivalent names use actual native file promise receivers")
        let destination = root.appendingPathComponent("filename boundary receiver", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let results = try await receive(receivers, at: destination, expectedCallbacks: fixtures.count)
        try expect(results.allSatisfy { $0.error == nil },
            "Every boundary filename promise completes without a filesystem-name error: " + results.compactMap(\.error).joined(separator: "; "))
        let names = results.map { $0.url.lastPathComponent }
        try expect(names == expectedPromisedNames,
            "Receiver preserves ordinary and uncollided 255-byte names, truncates only the collision stem and disambiguates case equivalents")
        try expect(Set(names.map { $0.precomposedStringWithCanonicalMapping.lowercased() }).count == fixtures.count,
            "Native receiver output names remain unique on normalization/case-insensitive filesystems")
        for (index, read) in results.enumerated() {
            try expect(read.receiverIndex == index && read.bytes == fixtures[index].1,
                "Actual receiver delivers each boundary-name capture's distinct exact bytes")
            try expect(receivers[index].fileNames == [expectedPromisedNames[index]],
                "Public receiver reports the exact suffix-aware bounded promised filename")
            try expect(read.url.lastPathComponent.utf8.count <= 255
                && read.url.pathExtension == (fixtures[index].0 as NSString).pathExtension,
                "Every received basename fits 255 UTF-8 bytes while preserving its complete original extension")
        }
        try expect(names[2].hasSuffix(".pdf")
            && String(names[2].dropLast(4)) == String(multilingualStem.prefix(83))
            && !names[2].contains("\u{FFFD}"),
            "Oversized multilingual output ends at a complete original character without replacement or damaged extension")
        try expect(try archiveMetadata(store) == metadata
            && captures.map(\.originalFilename) == fixtures.map { Optional($0.0) },
            "Preparing and fulfilling bounded promises never changes original filename metadata or capture state")
        board.clearContents()
        for (index, item) in published.enumerated() {
            try expect(try Data(contentsOf: item.snapshotURL) == fixtures[index].1
                && Data(contentsOf: results[index].url) == fixtures[index].1,
                "Boundary-name snapshot and destination copies outlive native pasteboard ownership")
        }
    }

    private static func occupiedDestination(store: CaptureStore, root: URL) async throws {
        let bytes = Data("Promised bytes must not overwrite an occupied target.\n".utf8)
        let capture = try await store.importData(bytes, filename: "Occupied.txt", projectName: "Collision fixture")
        let board = NSPasteboard(name: .init("DaBin.OutgoingFilePromiseCollisionQA." + UUID().uuidString))
        defer { board.releaseGlobally() }
        _ = try publish([capture], store: store, pasteboard: board, stagingRoot: root.appendingPathComponent("outgoing snapshots"))
        let receivers = board.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver] ?? []
        try expect(receivers.count == 1, "Occupied-target fixture uses a real native file promise receiver")
        let destination = root.appendingPathComponent("occupied receiver", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let occupied = destination.appendingPathComponent("Occupied.txt")
        let sentinel = Data("Exact existing destination content.\n".utf8)
        try sentinel.write(to: occupied, options: .withoutOverwriting)
        let metadata = try archiveMetadata(store)
        let results = try await receive(receivers, at: destination, expectedCallbacks: 1)
        // AppKit may choose a disambiguated URL. Otherwise the no-overwrite
        // delegate must return an explicit error for its occupied supplied URL.
        if let error = results[0].error {
            try expect(!error.isEmpty && results[0].bytes == nil, "An occupied target returns a real receiver error without fabricated success")
        } else {
            try expect(results[0].url != occupied && results[0].bytes == bytes,
                "AppKit collision disambiguation writes only to a distinct supplied destination")
        }
        try expect(try Data(contentsOf: occupied) == sentinel, "An occupied promise target is never overwritten")
        try expect(try archiveMetadata(store) == metadata, "An occupied destination does not change source archive metadata")
    }
}
