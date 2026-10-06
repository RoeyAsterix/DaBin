import Foundation
import CryptoKit
import Darwin

enum CaptureStoreError: LocalizedError {
    case emptyInput, directoryNotSupported, symbolicLinkNotSupported, invalidManagedPath
    case invalidOriginal(String), importVerificationFailed, injectedInterruption
    case reminderNotFuture, captureCancelled
    var errorDescription: String? {
        switch self {
        case .emptyInput: return "There is no readable content to save."
        case .directoryNotSupported: return "Folders cannot be saved yet. Drop individual files instead."
        case .symbolicLinkNotSupported: return "Aliases and symbolic links cannot be imported as originals. Drop the actual file."
        case .invalidManagedPath: return "An attachment path is outside DaBin’s managed storage."
        case .invalidOriginal(let reason): return "The original could not be saved: \(reason)"
        case .importVerificationFailed: return "The copied original could not be verified. Your source file is unchanged."
        case .injectedInterruption: return "Simulated process interruption."
        case .reminderNotFuture: return "Choose a reminder time in the future."
        case .captureCancelled: return "Auto Capture stopped before this item was saved."
        }
    }
}

// Only the isolated test runner sets this hook; shipping code leaves it nil.
enum ImportCheckpoint: String, CaseIterable {
    case beforeCopy, afterCopy, afterMove, beforeMetadataSave, afterMetadataSave
}

struct ImportJournal: Codable, Sendable {
    let id: UUID
    let capturedAt: Date
    let captureDay: String
    let timeZoneID: String
    let utcOffset: Int
    let originalFilename: String
    let sourceFilePath: String?
    let sourceURL: String?
    var parentTaskID: UUID? = nil
    /// Optional so import journals written before project filing remain recoverable.
    var projectName: String? = nil
    var captureOriginRaw: String? = nil
    var automaticActionID: UUID? = nil
    var sourceApplicationName: String? = nil
    var sourceApplicationBundleIdentifier: String? = nil
    let relativePath: String
    let stagingRelativePath: String
    let kind: CaptureKind
    let contentType: String?
    var phase: String
    var byteCount: Int64?
    var sha256: String?
}

struct OriginalVerification: Sendable {
    let byteCount: Int64
    let sha256: String
}

/// File integrity and import receipt types, independent of metadata persistence.
enum OriginalFileStorage {
    static func validateRegularFile(_ url: URL) throws {
        guard url.isFileURL else { throw CaptureStoreError.invalidManagedPath }
        // URL resource metadata is cached. Inspect the current directory entry
        // as well, including dangling links and special files, without following
        // a leaf link left in place of a previously validated original.
        var entry = stat()
        guard url.path.withCString({ Darwin.lstat($0, &entry) }) == 0 else { throw posixError() }
        let type = entry.st_mode & S_IFMT
        guard type != S_IFLNK else { throw CaptureStoreError.symbolicLinkNotSupported }
        guard type != S_IFDIR else { throw CaptureStoreError.directoryNotSupported }
        guard type == S_IFREG else { throw CaptureStoreError.invalidOriginal("This is not a regular file.") }
        var current = url
        current.removeAllCachedResourceValues()
        let values = try current.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey, .isAliasFileKey])
        guard values.isSymbolicLink != true, values.isAliasFile != true else { throw CaptureStoreError.symbolicLinkNotSupported }
        guard values.isDirectory != true else { throw CaptureStoreError.directoryNotSupported }
        guard values.isRegularFile == true else { throw CaptureStoreError.invalidOriginal("This is not a regular file.") }
    }

    static func verify(_ url: URL) throws -> OriginalVerification {
        try validateRegularFile(url)
        // Read a validated descriptor, rather than reopening a checked pathname
        // with link-following semantics. Nonblocking open also prevents a FIFO
        // substituted after validation from hanging the import/restore worker.
        let descriptor = url.path.withCString { Darwin.open($0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) }
        guard descriptor >= 0 else { throw posixError() }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var before = stat()
        guard Darwin.fstat(descriptor, &before) == 0 else { throw posixError() }
        guard before.st_mode & S_IFMT == S_IFREG else {
            throw CaptureStoreError.invalidOriginal("This is not a regular file.")
        }
        var hasher = SHA256()
        var size: Int64 = 0
        while try autoreleasepool(invoking: {
            // FileHandle may return an autoreleased Foundation buffer. Release
            // each chunk before the next read, including when several complete
            // integrity checks run in one main-actor project move.
            guard let data = try handle.read(upToCount: 1_048_576), !data.isEmpty else { return false }
            hasher.update(data: data)
            size += Int64(data.count)
            return true
        }) {
        }
        var after = stat()
        guard Darwin.fstat(descriptor, &after) == 0 else { throw posixError() }
        guard before.st_dev == after.st_dev, before.st_ino == after.st_ino,
              before.st_size == after.st_size, size == Int64(after.st_size),
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else {
            throw CaptureStoreError.importVerificationFailed
        }
        return OriginalVerification(byteCount: size, sha256: hasher.finalize().map { String(format: "%02x", $0) }.joined())
    }

    /// DaBin-owned roots are private directories, never symbolic-link redirects.
    /// Parent system aliases such as /tmp remain usable; only the requested leaf
    /// is constrained. The descriptor binds chmod to the inspected directory.
    static func ensurePrivateDirectory(_ url: URL, withIntermediateDirectories: Bool = true) throws {
        guard url.isFileURL else { throw CaptureStoreError.invalidManagedPath }
        var entry = stat()
        let exists = url.path.withCString { Darwin.lstat($0, &entry) } == 0
        if exists {
            guard entry.st_mode & S_IFMT == S_IFDIR else { throw CaptureStoreError.invalidManagedPath }
        } else {
            guard errno == ENOENT else { throw posixError() }
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories,
                                                    attributes: [.posixPermissions: 0o700])
        }
        let descriptor = url.path.withCString { Darwin.open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK) }
        guard descriptor >= 0 else { throw posixError() }
        defer { Darwin.close(descriptor) }
        var opened = stat()
        guard Darwin.fstat(descriptor, &opened) == 0 else { throw posixError() }
        guard opened.st_mode & S_IFMT == S_IFDIR, opened.st_uid == Darwin.geteuid() else {
            throw CaptureStoreError.invalidManagedPath
        }
        guard Darwin.fchmod(descriptor, mode_t(0o700)) == 0 else { throw posixError() }
    }

    private static func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
    }
}
