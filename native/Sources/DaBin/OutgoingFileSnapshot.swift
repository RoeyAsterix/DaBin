import Darwin
import Foundation

/// A drag exports isolated bytes, never a mutable managed-archive location.
/// Files outlive their publisher so an asynchronous receiver can still read them.
final class OutgoingFileSnapshot: Sendable {
    let url: URL
    private let directoryKey: String
    private static let retention: TimeInterval = 24 * 60 * 60
    private static let receiptName = ".dabin-outgoing-receipt.json"
    private static let payloadDirectory = "Contents"
    private static let ownershipKind = "com.dabin.outgoing-file-snapshot"
    private static let active = ActiveDirectories()

    private struct Receipt: Codable {
        let schemaVersion: Int
        let kind: String
        let id: UUID
        let filename: String
        let createdAt: Date
        let byteCount: Int64
    }

    private final class ActiveDirectories: @unchecked Sendable {
        let lock = NSLock()
        var paths: Set<String> = []
        var lastCleanup: [String: Date] = [:]
    }

    private init(url: URL, directoryKey: String) {
        self.url = url; self.directoryKey = directoryKey
    }

    deinit {
        Self.active.lock.lock()
        Self.active.paths.remove(directoryKey)
        Self.active.lock.unlock()
        // Dropping a provider/session is not proof the receiver finished reading.
    }

    static func prepare(source: URL, filename: String? = nil, stagingRoot: URL? = nil, now: Date = Date()) throws -> OutgoingFileSnapshot {
        guard now.timeIntervalSinceReferenceDate.isFinite else { throw CaptureStoreError.invalidManagedPath }
        let original = try regularFile(source)
        let filename = try exportFilename(filename ?? original.lastPathComponent)
        let reader = original.withUnsafeFileSystemRepresentation { path in
            path.map { Darwin.open($0, O_RDONLY | O_NOFOLLOW) } ?? -1
        }
        guard reader >= 0 else { throw posixError() }
        defer { Darwin.close(reader) }
        var before = stat()
        guard fstat(reader, &before) == 0 else { throw posixError() }
        guard before.st_mode & S_IFMT == S_IFREG else { throw CaptureStoreError.invalidManagedPath }

        let files = FileManager.default
        let requestedRoot = stagingRoot ?? files.temporaryDirectory.appendingPathComponent("DaBinOutgoingTransfers", isDirectory: true)
        guard requestedRoot.isFileURL else { throw CaptureStoreError.invalidManagedPath }
        var rootStat = stat()
        let rootExists = requestedRoot.withUnsafeFileSystemRepresentation { path in
            path.map { Darwin.lstat($0, &rootStat) == 0 } ?? false
        }
        if !rootExists {
            guard errno == ENOENT else { throw posixError() }
            try files.createDirectory(at: requestedRoot, withIntermediateDirectories: true,
                                      attributes: [.posixPermissions: 0o700])
        }
        // lstat sees dangling links too; never create through a supplied root link.
        try regularDirectory(requestedRoot)
        let root = requestedRoot.resolvingSymlinksInPath().standardizedFileURL
        cleanupExpired(in: root, now: now)
        let id = UUID()
        let directory = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try files.createDirectory(at: directory, withIntermediateDirectories: false,
                                  attributes: [.posixPermissions: 0o700])
        // Foundation may enumerate the same temp directory through /private/var
        // while creation uses /var. Lease identity must use the same form.
        let key = directory.standardizedFileURL.path
        active.lock.lock(); active.paths.insert(key); active.lock.unlock()
        var complete = false
        defer {
            if !complete {
                active.lock.lock()
                try? files.removeItem(at: directory)
                active.paths.remove(key)
                active.lock.unlock()
            }
        }
        let contents = directory.appendingPathComponent(payloadDirectory, isDirectory: true)
        try files.createDirectory(at: contents, withIntermediateDirectories: false,
                                  attributes: [.posixPermissions: 0o700])
        let destination = contents.appendingPathComponent(filename)
        // Clone the already validated open file, never a replaceable pathname.
        let cloned = destination.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return Darwin.fclonefileat(reader, AT_FDCWD, path, 0) == 0
        }
        if !cloned {
            // Any failed clone residue belongs only to this fresh private copy.
            if files.fileExists(atPath: destination.path) { try files.removeItem(at: destination) }
            try copyBytes(from: reader, to: destination)
        }
        let copied = try regularFile(destination)
        var after = stat()
        guard fstat(reader, &after) == 0 else { throw posixError() }
        let byteCount = try files.attributesOfItem(atPath: copied.path)[.size] as? NSNumber
        guard before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              byteCount?.int64Value == Int64(before.st_size) else {
            throw CaptureStoreError.importVerificationFailed
        }
        let receipt = Receipt(schemaVersion: 1, kind: ownershipKind, id: id, filename: filename,
                              createdAt: now, byteCount: Int64(before.st_size))
        try JSONEncoder().encode(receipt).write(to: directory.appendingPathComponent(receiptName), options: .atomic)
        complete = true
        return OutgoingFileSnapshot(url: copied, directoryKey: key)
    }

    private static func copyBytes(from reader: Int32, to destination: URL) throws {
        let writer = destination.withUnsafeFileSystemRepresentation { path in
            path.map { Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600)) } ?? -1
        }
        guard writer >= 0 else { throw posixError() }
        defer { Darwin.close(writer) }
        var buffer = [UInt8](repeating: 0, count: 1_048_576)
        try buffer.withUnsafeMutableBytes { bytes in
            while true {
                let count = Darwin.read(reader, bytes.baseAddress, bytes.count)
                if count == 0 { return }
                if count < 0 {
                    if errno == EINTR { continue }
                    throw posixError()
                }
                var written = 0
                while written < count {
                    let amount = Darwin.write(writer, bytes.baseAddress?.advanced(by: written), count - written)
                    if amount < 0 {
                        if errno == EINTR { continue }
                        throw posixError()
                    }
                    guard amount > 0 else { throw CaptureStoreError.importVerificationFailed }
                    written += amount
                }
            }
        }
    }

    private static func regularFile(_ url: URL) throws -> URL {
        guard url.isFileURL else { throw CaptureStoreError.invalidManagedPath }
        var current = url
        current.removeAllCachedResourceValues()
        let attributes = try FileManager.default.attributesOfItem(atPath: current.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw CaptureStoreError.invalidManagedPath }
        try OriginalFileStorage.validateRegularFile(current)
        return current
    }

    private static func regularDirectory(_ url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw CaptureStoreError.invalidManagedPath }
        var current = url; current.removeAllCachedResourceValues()
        let values = try current.resourceValues(forKeys: [.isSymbolicLinkKey, .isAliasFileKey])
        guard values.isSymbolicLink != true, values.isAliasFile != true else { throw CaptureStoreError.invalidManagedPath }
    }

    static func exportFilename(_ name: String) throws -> String {
        guard validFilename(name) else { throw CaptureStoreError.invalidManagedPath }
        return boundedFilename(name)
    }

    /// Archive metadata can contain names longer than a native filesystem leaf.
    /// Preserve ordinary names exactly; shortening keeps whole characters and
    /// the extension, leaving space for a multi-file collision suffix.
    static func boundedFilename(_ name: String, suffix: String = "") -> String {
        if suffix.isEmpty && name.utf8.count <= 255 { return name }
        let path = name as NSString
        func prefix(_ value: String, bytes: Int) -> String {
            var result = ""
            for character in value {
                let next = String(character)
                if result.utf8.count + next.utf8.count > bytes { break }
                result += next
            }
            return result
        }
        let extensionName = prefix(path.pathExtension, bytes: 80)
        let tail = suffix + (extensionName.isEmpty ? "" : "." + extensionName)
        let stem = prefix(path.deletingPathExtension, bytes: max(0, 255 - tail.utf8.count))
        return (stem.isEmpty ? "Capture" : stem) + tail
    }

    private static func validFilename(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\0")
    }

    /// Cleanup understands only our complete, typed receipts. Unrecognized,
    /// altered, nested, symbolic-link and active transfer directories survive.
    private static func cleanupExpired(in root: URL, now: Date) {
        let files = FileManager.default
        active.lock.lock()
        if let last = active.lastCleanup[root.path] {
            let elapsed = now.timeIntervalSince(last)
            if elapsed >= 0 && elapsed < 60 { active.lock.unlock(); return }
        }
        active.lastCleanup[root.path] = now
        let activePaths = active.paths
        active.lock.unlock()
        guard let directories = try? files.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for directory in directories where !activePaths.contains(directory.standardizedFileURL.path) {
            guard let id = UUID(uuidString: directory.lastPathComponent), id.uuidString == directory.lastPathComponent,
                  (try? regularDirectory(directory)) != nil,
                  let entries = try? files.contentsOfDirectory(atPath: directory.path),
                  Set(entries) == Set([receiptName, payloadDirectory]) else { continue }
            let receiptURL = directory.appendingPathComponent(receiptName)
            guard (try? regularFile(receiptURL)) != nil,
                  let attributes = try? files.attributesOfItem(atPath: receiptURL.path),
                  let size = attributes[.size] as? NSNumber, size.int64Value <= 16_384,
                  let data = try? Data(contentsOf: receiptURL),
                  let receipt = try? JSONDecoder().decode(Receipt.self, from: data),
                  receipt.schemaVersion == 1, receipt.kind == ownershipKind, receipt.id == id,
                  validFilename(receipt.filename), receipt.byteCount >= 0,
                  receipt.createdAt.timeIntervalSinceReferenceDate.isFinite,
                  now.timeIntervalSince(receipt.createdAt) >= retention else { continue }
            let contents = directory.appendingPathComponent(payloadDirectory, isDirectory: true)
            guard (try? regularDirectory(contents)) != nil,
                  let payloads = try? files.contentsOfDirectory(atPath: contents.path), payloads == [receipt.filename],
                  let payload = try? regularFile(contents.appendingPathComponent(receipt.filename)),
                  let payloadAttributes = try? files.attributesOfItem(atPath: payload.path),
                  (payloadAttributes[.size] as? NSNumber)?.int64Value == receipt.byteCount else { continue }
            active.lock.lock()
            if !active.paths.contains(directory.standardizedFileURL.path) { try? files.removeItem(at: directory) }
            active.lock.unlock()
        }
    }

    private static func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
    }
}
