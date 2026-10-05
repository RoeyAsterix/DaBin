import Foundation

/// Local synthetic files only: no window, pasteboard, personal archive, network,
/// or system preferences. Every snapshot uses this suite's private staging root.
@main @MainActor struct OutgoingFileSnapshotTests {
    static let files = FileManager.default
    static var checks = 0
    static let retention: TimeInterval = 24 * 60 * 60
    static let receiptFilename = ".dabin-outgoing-receipt.json"

    static func expect(_ value: @autoclosure () throws -> Bool, _ reason: String) throws {
        checks += 1
        let passed: Bool
        do { passed = try value() }
        catch {
            throw NSError(domain: "OutgoingFileSnapshotTests", code: checks,
                          userInfo: [NSLocalizedDescriptionKey: reason + ": " + error.localizedDescription,
                                     NSUnderlyingErrorKey: error])
        }
        if !passed {
            throw NSError(domain: "OutgoingFileSnapshotTests", code: checks,
                          userInfo: [NSLocalizedDescriptionKey: reason])
        }
    }

    static func rejects(_ reason: String, _ action: () throws -> Void) throws {
        var rejected = false
        do { try action() } catch { rejected = true }
        try expect(rejected, reason)
    }

    static func directory(_ url: URL) throws {
        try files.createDirectory(at: url, withIntermediateDirectories: true)
    }

    static func entries(_ root: URL) throws -> [String] {
        guard files.fileExists(atPath: root.path) else { return [] }
        return try files.contentsOfDirectory(atPath: root.path).sorted()
    }

    static func payloadDirectory(_ payload: URL) -> URL {
        payload.deletingLastPathComponent().deletingLastPathComponent()
    }

    static func receiptURL(_ payload: URL) -> URL {
        payloadDirectory(payload).appendingPathComponent(receiptFilename)
    }

    static func receipt(_ payload: URL) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: receiptURL(payload)))
        guard let result = object as? [String: Any] else {
            throw NSError(domain: "OutgoingFileSnapshotTests", code: 10_000,
                          userInfo: [NSLocalizedDescriptionKey: "Generated receipt is not a JSON object"])
        }
        return result
    }

    static func changeReceipt(_ payload: URL, _ change: (inout [String: Any]) -> Void) throws {
        var object = try receipt(payload)
        change(&object)
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            .write(to: receiptURL(payload), options: .atomic)
    }

    /// Return the published URL without retaining the publisher's snapshot lease.
    static func retiredPayload(_ source: URL, _ staging: URL, _ now: Date) throws -> URL {
        let snapshot = try OutgoingFileSnapshot.prepare(source: source, stagingRoot: staging, now: now)
        return snapshot.url
    }

    static func snapshotIsolation(root: URL, now: Date) throws {
        let sources = root.appendingPathComponent("Sources")
        let staging = root.appendingPathComponent("Snapshots")
        try directory(sources)
        let source = sources.appendingPathComponent("Fictional upload — תודה 資料.pdf")
        let original = Data(("Synthetic saved-original bytes\n" + String(repeating: "0123456789abcdef", count: 8_192)).utf8)
        try original.write(to: source)
        var snapshot: OutgoingFileSnapshot? = try OutgoingFileSnapshot.prepare(source: source, stagingRoot: staging, now: now)
        let published = snapshot!.url
        try expect(published != source && published.isFileURL, "Published file is an independent local URL")
        try expect(published.lastPathComponent == source.lastPathComponent, "Original Unicode filename and extension remain exact")
        try expect(published.deletingLastPathComponent().lastPathComponent == "Contents", "Payload remains inside its owned Contents directory")
        try expect(payloadDirectory(published).deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL == staging.resolvingSymlinksInPath().standardizedFileURL,
                   "Explicit private staging root contains the snapshot")
        try expect(try Data(contentsOf: published) == original, "Snapshot bytes equal the complete source")
        let values = try published.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isAliasFileKey])
        try expect(values.isRegularFile == true && values.isSymbolicLink != true && values.isAliasFile != true,
                   "Published payload is a regular file, never a symlink or alias")
        let ownedEntries = try entries(payloadDirectory(published))
        try expect(ownedEntries == [receiptFilename, "Contents"].sorted(), "Successful publication has no partial or extra payload files")
        let record = try receipt(published)
        try expect(record["filename"] as? String == source.lastPathComponent, "Ownership receipt records exact original filename")
        try expect((record["byteCount"] as? NSNumber)?.intValue == original.count, "Ownership receipt records exact payload byte count")
        try expect(try !String(decoding: Data(contentsOf: receiptURL(published)), as: UTF8.self).contains(source.path),
                   "Ownership receipt does not expose the private source path")
        let permissions = try files.attributesOfItem(atPath: payloadDirectory(published).path)[.posixPermissions] as? NSNumber
        try expect(permissions?.intValue == 0o700, "Owned snapshot directory is private to its owner")

        // An atomic rewrite would miss hardlinks. Mutate the existing inode first.
        let writer = try FileHandle(forWritingTo: source)
        try writer.truncate(atOffset: 0)
        try writer.write(contentsOf: Data("In-place source mutation".utf8))
        try writer.close()
        try expect(try Data(contentsOf: published) == original, "In-place source writes cannot mutate a published snapshot")
        let moved = sources.appendingPathComponent("Moved original.pdf")
        try files.moveItem(at: source, to: moved)
        try expect(try Data(contentsOf: published) == original, "Snapshot survives an original file move")
        try Data("Replacement at the former source URL".utf8).write(to: source)
        try expect(try Data(contentsOf: published) == original, "Replacing the original path cannot redirect the published URL")
        try files.removeItem(at: source)
        try files.removeItem(at: moved)
        try expect(try Data(contentsOf: published) == original, "Snapshot survives removal of both original and replacement")

        // A private provider publishes this URL; neither it nor its lease survives.
        weak var releasedProvider: NSItemProvider?
        try autoreleasepool {
            var provider: NSItemProvider? = NSItemProvider(object: published as NSURL)
            try expect(provider != nil, "Synthetic provider is created without a pasteboard")
            releasedProvider = provider
            provider = nil
        }
        weak var releasedSnapshot = snapshot
        snapshot = nil
        try expect(releasedSnapshot == nil && releasedProvider == nil, "Publisher and snapshot lease can both be released")
        releasedSnapshot = nil
        try expect(try Data(contentsOf: published) == original, "A delayed external reader still finds bytes after publisher release")

        let empty = sources.appendingPathComponent("Empty.txt")
        try Data().write(to: empty)
        let emptySnapshot = try OutgoingFileSnapshot.prepare(source: empty, stagingRoot: staging, now: now)
        try expect(try Data(contentsOf: emptySnapshot.url).isEmpty && emptySnapshot.url.lastPathComponent == "Empty.txt",
                   "An empty regular file remains a valid exact-name upload")
        let second = try OutgoingFileSnapshot.prepare(source: empty, stagingRoot: staging, now: now)
        try expect(second.url != emptySnapshot.url, "Independent publications never share a mutable destination")
        let receiptNamedSource = sources.appendingPathComponent(receiptFilename)
        let receiptNamedBytes = Data("Original payload whose name resembles snapshot metadata".utf8)
        try receiptNamedBytes.write(to: receiptNamedSource)
        let receiptNamedSnapshot = try OutgoingFileSnapshot.prepare(source: receiptNamedSource, stagingRoot: staging, now: now)
        try expect(try receiptNamedSnapshot.url.lastPathComponent == receiptFilename
            && Data(contentsOf: receiptNamedSnapshot.url) == receiptNamedBytes,
                   "A payload named like the receipt retains its exact name and bytes")
        try expect(try receipt(receiptNamedSnapshot.url)["filename"] as? String == receiptFilename,
                   "The separate ownership receipt cannot collide with an original filename")
        withExtendedLifetime((emptySnapshot, second, receiptNamedSnapshot)) {}
    }

    static func failedPreparation(root: URL, now: Date) throws {
        let sources = root.appendingPathComponent("Sources")
        let staging = root.appendingPathComponent("Snapshots")
        try directory(sources)
        try directory(staging)
        let source = sources.appendingPathComponent("Fictional.txt")
        let original = Data("Unchanged synthetic source".utf8)
        try original.write(to: source)
        let before = try entries(staging)
        let missing = sources.appendingPathComponent("Missing.pdf")
        try rejects("Missing originals are rejected") {
            _ = try OutgoingFileSnapshot.prepare(source: missing, stagingRoot: staging, now: now)
        }
        try expect(try entries(staging) == before, "Missing-source failure leaves no partial snapshot")
        let folder = sources.appendingPathComponent("Folder.pdf")
        try directory(folder)
        try rejects("Directories cannot masquerade as uploaded files") {
            _ = try OutgoingFileSnapshot.prepare(source: folder, stagingRoot: staging, now: now)
        }
        try expect(try entries(staging) == before, "Directory-source failure leaves no partial snapshot")
        let symlink = sources.appendingPathComponent("Link.txt")
        try files.createSymbolicLink(at: symlink, withDestinationURL: source)
        try rejects("Symbolic originals are rejected without following their target") {
            _ = try OutgoingFileSnapshot.prepare(source: symlink, stagingRoot: staging, now: now)
        }
        try expect(try entries(staging) == before && Data(contentsOf: source) == original,
                   "Symlink rejection preserves source bytes and staging contents")
        let alias = sources.appendingPathComponent("Fictional alias.txt")
        let bookmark = try source.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
        try URL.writeBookmarkData(bookmark, to: alias)
        try expect(try alias.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile == true,
                   "Alias rejection uses a real macOS bookmark-file alias")
        try rejects("Alias originals are rejected instead of silently resolving") {
            _ = try OutgoingFileSnapshot.prepare(source: alias, stagingRoot: staging, now: now)
        }
        try expect(try entries(staging) == before && Data(contentsOf: source) == original,
                   "Alias rejection preserves original bytes and leaves no partial snapshot")

        let blockedRoot = root.appendingPathComponent("Blocked root")
        let rootBytes = Data("This is a file, not a staging directory".utf8)
        try rootBytes.write(to: blockedRoot)
        try rejects("A regular file cannot become a staging root") {
            _ = try OutgoingFileSnapshot.prepare(source: source, stagingRoot: blockedRoot, now: now)
        }
        try expect(try Data(contentsOf: blockedRoot) == rootBytes && Data(contentsOf: source) == original,
                   "Failed root preparation preserves both existing files")
        let linkedRoot = root.appendingPathComponent("Linked staging root")
        try files.createSymbolicLink(at: linkedRoot, withDestinationURL: staging)
        try rejects("A symlink staging root is rejected") {
            _ = try OutgoingFileSnapshot.prepare(source: source, stagingRoot: linkedRoot, now: now)
        }
        try expect(try entries(staging) == before, "Rejected symlink staging root never publishes into its target")

        let unreadable = sources.appendingPathComponent("Unreadable.bin")
        try original.write(to: unreadable)
        try files.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadable.path)
        defer { try? files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: unreadable.path) }
        try rejects("Unreadable fixture really denies reads to the test process") { _ = try Data(contentsOf: unreadable) }
        try rejects("Failure copying a regular unreadable source is reported") {
            _ = try OutgoingFileSnapshot.prepare(source: unreadable, stagingRoot: staging, now: now)
        }
        try expect(try entries(staging) == before, "Unreadable-source preparation leaves no partial owned directory")
        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: unreadable.path)
        try expect(try Data(contentsOf: unreadable) == original, "Failed preparation never changes source contents")
        let readonly = root.appendingPathComponent("Readonly staging")
        try directory(readonly)
        try files.setAttributes([.posixPermissions: 0o500], ofItemAtPath: readonly.path)
        defer { try? files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: readonly.path) }
        try rejects("An unwritable staging root reports failure") {
            _ = try OutgoingFileSnapshot.prepare(source: source, stagingRoot: readonly, now: now)
        }
        try expect(try entries(readonly).isEmpty, "Unwritable-root failure leaves no partial payload")
    }

    static func filenameOverrides(root: URL, now: Date) throws {
        try directory(root)
        let source = root.appendingPathComponent("Managed original — fictional identity.bin")
        let staging = root.appendingPathComponent("Snapshots")
        let bytes = Data("Exact synthetic bytes behind independently named metadata".utf8)
        try bytes.write(to: source)
        let exactName = "Fictional brief — תודה.pdf"
        let exact = try OutgoingFileSnapshot.prepare(source: source, filename: exactName, stagingRoot: staging, now: now)
        try expect(exact.url.lastPathComponent == exactName && (try Data(contentsOf: exact.url)) == bytes,
                   "A valid original-name override is preserved exactly without changing source bytes")
        let oversizedName = String(repeating: "資料é👩🏽‍💻", count: 100) + ".pdf"
        try expect(oversizedName.utf8.count > 255, "Oversized Unicode fixture actually exceeds native filename limits")
        let shortened = try OutgoingFileSnapshot.prepare(source: source, filename: oversizedName, stagingRoot: staging, now: now)
        let shortenedStem = shortened.url.deletingPathExtension().lastPathComponent
        try expect(shortened.url.lastPathComponent.utf8.count <= 255 && shortened.url.pathExtension == "pdf"
            && !shortenedStem.isEmpty && String(oversizedName.dropLast(4)).hasPrefix(shortenedStem),
                   "Oversized metadata becomes a bounded recognizable basename with intact characters and extension")
        try expect(try Data(contentsOf: shortened.url) == bytes,
                   "Shortening an oversized original name preserves complete upload bytes")
        try expect(try receipt(shortened.url)["filename"] as? String == shortened.url.lastPathComponent,
                   "A bounded metadata name and its ownership receipt agree")
        let maximumName = String(repeating: "a", count: 251) + ".txt"
        let maximum = try OutgoingFileSnapshot.prepare(source: source, filename: maximumName, stagingRoot: staging, now: now)
        try expect(maximum.url.lastPathComponent == maximumName && maximum.url.lastPathComponent.utf8.count == 255,
                   "An ordinary filename at the native byte limit remains exact")
        let before = try entries(staging)
        for unsafeName in ["../Escape.pdf", "nested/File.pdf", "/Escape.pdf", "bad\0name.pdf", ".", "..", ""] {
            try rejects("Unsafe original-name override is rejected: " + unsafeName.debugDescription) {
                _ = try OutgoingFileSnapshot.prepare(source: source, filename: unsafeName, stagingRoot: staging, now: now)
            }
            try expect(try entries(staging) == before && Data(contentsOf: source) == bytes,
                       "Rejected original-name override cannot escape or leave a partial payload")
        }
        withExtendedLifetime((exact, shortened, maximum)) {}
    }

    static func expiryBoundaries(root: URL, now: Date) throws {
        let staging = root.appendingPathComponent("Snapshots")
        let source = root.appendingPathComponent("Fictional.bin")
        try directory(root)
        let bytes = Data("Synthetic retained transfer".utf8)
        try bytes.write(to: source)

        // Independent roots avoid using a future clock to set up a retention
        // boundary fixture. Each root's cleanup cadence remains explicit.
        let beforeRoot = root.appendingPathComponent("Before-boundary snapshots")
        let beforePayload = try retiredPayload(source, beforeRoot, now)
        let beforeBoundary = try OutgoingFileSnapshot.prepare(source: source, stagingRoot: beforeRoot,
                                                             now: now.addingTimeInterval(retention - 1))
        try expect(try Data(contentsOf: beforePayload) == bytes,
                   "Released snapshots remain readable one second before the 24-hour boundary")

        let retired = try retiredPayload(source, staging, now)
        var active: OutgoingFileSnapshot? = try OutgoingFileSnapshot.prepare(source: source, stagingRoot: staging, now: now)
        let activeURL = active!.url
        let young = try retiredPayload(source, staging, now.addingTimeInterval(retention / 2))
        let atBoundary = try withExtendedLifetime(active) {
            let result = try OutgoingFileSnapshot.prepare(source: source, stagingRoot: staging,
                                                         now: now.addingTimeInterval(retention))
            try expect(!files.fileExists(atPath: payloadDirectory(retired).path),
                       "Released valid snapshot is removed at exactly 24 hours")
            try expect(try Data(contentsOf: activeURL) == bytes,
                       "An explicitly retained active expired snapshot survives cleanup")
            try expect(try Data(contentsOf: young) == bytes,
                       "Snapshot younger than 24 hours is preserved")
            return result
        }
        weak var released = active
        active = nil
        try expect(released == nil, "The active cleanup lease can end without deleting payload immediately")
        released = nil
        try expect(try Data(contentsOf: activeURL) == bytes,
                   "Releasing a lease preserves bytes until a later cleanup")
        // Leave the production throttle its full 60 seconds after the previous
        // scan; the active lease is now gone but the young snapshot remains ineligible.
        let afterRelease = try OutgoingFileSnapshot.prepare(source: source, stagingRoot: staging,
                                                          now: now.addingTimeInterval(retention + 60))
        try expect(!files.fileExists(atPath: payloadDirectory(activeURL).path),
                   "The next cleanup removes the now-inactive expired snapshot")
        try expect(try Data(contentsOf: young) == bytes,
                   "Expired cleanup remains selective after a lease ends")

        let futureRoot = root.appendingPathComponent("Future-dated snapshots")
        let future = try retiredPayload(source, futureRoot, now.addingTimeInterval(retention * 2))
        let futureCleanup = try OutgoingFileSnapshot.prepare(source: source, stagingRoot: futureRoot,
                                                           now: now.addingTimeInterval(retention))
        try expect(try Data(contentsOf: future) == bytes, "A future-dated snapshot is preserved")
        withExtendedLifetime((beforeBoundary, atBoundary, afterRelease, futureCleanup)) {}
    }

    static func conservativeCleanup(root: URL, now: Date) throws {
        let staging = root.appendingPathComponent("Snapshots")
        let source = root.appendingPathComponent("Fictional.bin")
        try directory(root)
        let bytes = Data("Only this synthetic transfer may expire".utf8)
        try bytes.write(to: source)
        let validExpired = try retiredPayload(source, staging, now)
        var kept: [URL] = []
        let malformed = try retiredPayload(source, staging, now)
        try Data("not JSON".utf8).write(to: receiptURL(malformed))
        kept.append(malformed)
        let wrongKind = try retiredPayload(source, staging, now)
        try changeReceipt(wrongKind) { $0["kind"] = "some.other.application" }
        kept.append(wrongKind)
        let wrongSchema = try retiredPayload(source, staging, now)
        try changeReceipt(wrongSchema) { $0["schemaVersion"] = 999 }
        kept.append(wrongSchema)
        let wrongIdentity = try retiredPayload(source, staging, now)
        try changeReceipt(wrongIdentity) { $0["id"] = UUID().uuidString }
        kept.append(wrongIdentity)
        let wrongSize = try retiredPayload(source, staging, now)
        try changeReceipt(wrongSize) { $0["byteCount"] = bytes.count + 1 }
        kept.append(wrongSize)
        let unsafeFilename = try retiredPayload(source, staging, now)
        try changeReceipt(unsafeFilename) { $0["filename"] = "../Fictional.bin" }
        kept.append(unsafeFilename)
        let extraEntry = try retiredPayload(source, staging, now)
        try Data("Unrecognized owner's data".utf8).write(to: payloadDirectory(extraEntry).appendingPathComponent("Keep this.txt"))
        kept.append(extraEntry)
        let extraPayload = try retiredPayload(source, staging, now)
        try Data("Unrecognized payload".utf8).write(to: extraPayload.deletingLastPathComponent().appendingPathComponent("Another.bin"))
        kept.append(extraPayload)
        let noReceipt = try retiredPayload(source, staging, now)
        try files.removeItem(at: receiptURL(noReceipt))
        kept.append(noReceipt)
        let nonUUID = try retiredPayload(source, staging, now)
        let nonUUIDDirectory = staging.appendingPathComponent("Do not delete this folder")
        try files.moveItem(at: payloadDirectory(nonUUID), to: nonUUIDDirectory)
        let movedNonUUID = nonUUIDDirectory.appendingPathComponent("Contents").appendingPathComponent(source.lastPathComponent)
        kept.append(movedNonUUID)

        let unknown = staging.appendingPathComponent(UUID().uuidString)
        try directory(unknown)
        let unknownFile = unknown.appendingPathComponent("Other application's file.bin")
        try bytes.write(to: unknownFile)
        let looseFile = staging.appendingPathComponent("Keep unrelated loose file.txt")
        try bytes.write(to: looseFile)
        let externalRoot = root.appendingPathComponent("External owned-looking directory")
        let external = try retiredPayload(source, externalRoot, now)
        let linkedDirectory = staging.appendingPathComponent(payloadDirectory(external).lastPathComponent)
        try files.createSymbolicLink(at: linkedDirectory, withDestinationURL: payloadDirectory(external))
        let linkedPayload = try retiredPayload(source, staging, now)
        try files.removeItem(at: linkedPayload)
        try files.createSymbolicLink(at: linkedPayload, withDestinationURL: source)
        let linkedReceipt = try retiredPayload(source, staging, now)
        let originalReceipt = try Data(contentsOf: receiptURL(linkedReceipt))
        let externalReceipt = root.appendingPathComponent("External receipt.json")
        try originalReceipt.write(to: externalReceipt)
        try files.removeItem(at: receiptURL(linkedReceipt))
        try files.createSymbolicLink(at: receiptURL(linkedReceipt), withDestinationURL: externalReceipt)
        kept.append(linkedPayload)
        kept.append(linkedReceipt)

        let trigger = try OutgoingFileSnapshot.prepare(source: source, stagingRoot: staging,
                                                      now: now.addingTimeInterval(retention * 3))
        try expect(!files.fileExists(atPath: payloadDirectory(validExpired).path), "Cleanup still removes a fully valid inactive expired snapshot")
        for payload in kept {
            try expect(files.fileExists(atPath: payloadDirectory(payload).path),
                       "Cleanup preserves uncertain ownership at \(payloadDirectory(payload).lastPathComponent)")
            try expect(try Data(contentsOf: payload) == bytes, "Cleanup preserves every uncertain owner's payload bytes")
        }
        try expect(try Data(contentsOf: unknownFile) == bytes && Data(contentsOf: looseFile) == bytes,
                   "Unknown directories and loose files are untouched")
        try expect(try linkedDirectory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true,
                   "A symlink directory under the staging root is preserved")
        try expect(try Data(contentsOf: external) == bytes && Data(contentsOf: source) == bytes,
                   "Cleanup never follows symlinks into external directories or source files")
        try expect(try Data(contentsOf: externalReceipt) == originalReceipt,
                   "Cleanup never edits an external receipt reached through a symlink")
        withExtendedLifetime(trigger) {}
    }

    static func main() throws {
        let root = files.temporaryDirectory.appendingPathComponent("DaBinOutgoingFileSnapshotQA-\(UUID().uuidString)")
        try directory(root)
        defer { try? files.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_791_158_400)
        try snapshotIsolation(root: root.appendingPathComponent("Isolation"), now: now)
        try failedPreparation(root: root.appendingPathComponent("Rejections"), now: now)
        try filenameOverrides(root: root.appendingPathComponent("Filename overrides"), now: now)
        try expiryBoundaries(root: root.appendingPathComponent("Expiry"), now: now)
        try conservativeCleanup(root: root.appendingPathComponent("Conservative cleanup"), now: now)
        print("PASS: \(checks) outgoing snapshot immutability, filename and metadata override, publisher lifetime, unsafe-source rejection, failed-publication, retention, active-lease, and conservative-cleanup checks")
    }
}
