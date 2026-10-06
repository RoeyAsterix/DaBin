import Darwin
import CryptoKit
import Foundation

struct DaBinUpdateHandoff: Codable, Equatable {
    struct Resolved: Equatable {
        let package: URL
        let packageSHA256: String
    }

    static let schemaVersion = 1
    static let fileExtension = "dabinupdate"
    static let maximumBytes = 8 * 1024

    let schemaVersion: Int
    let packageName: String
    let packageSHA256: String

    static func create(package: URL, sha256: String, in directory: URL) throws -> URL {
        let root = directory.standardizedFileURL
        let archive = package.standardizedFileURL
        try validateDirectory(root)
        guard archive.deletingLastPathComponent() == root,
              validPackageName(archive.lastPathComponent), validSHA256(sha256) else {
            throw handoffError()
        }
        let archiveValues = try archive.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard archiveValues.isRegularFile == true, archiveValues.isSymbolicLink != true else {
            throw handoffError()
        }

        let request = Self(schemaVersion: schemaVersion, packageName: archive.lastPathComponent,
                           packageSHA256: sha256)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(request)
        guard !data.isEmpty, data.count <= maximumBytes else { throw handoffError() }

        let result = root.appendingPathComponent("DaBin-\(UUID().uuidString).\(fileExtension)")
        try writeExclusive(data, to: result)
        return result
    }

    static func consume(_ handoff: URL, allowedDirectory: URL) throws -> Resolved {
        let files = FileManager.default
        let root = allowedDirectory.standardizedFileURL
        let requestURL = handoff.standardizedFileURL
        try validateDirectory(root)
        guard requestURL.deletingLastPathComponent() == root,
              requestURL.pathExtension.lowercased() == fileExtension else {
            throw handoffError()
        }
        let values = try requestURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let byteCount = values.fileSize, byteCount > 0, byteCount <= maximumBytes else {
            throw handoffError()
        }
        let attributes = try files.attributesOfItem(atPath: requestURL.path)
        let owner = (attributes[.ownerAccountID] as? NSNumber)?.uint32Value
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.uint16Value
        guard owner == getuid(), let permissions, permissions & 0o022 == 0 else {
            throw handoffError()
        }

        let data = try Data(contentsOf: requestURL, options: .mappedIfSafe)
        guard let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(dictionary.keys) == Set(["schemaVersion", "packageName", "packageSHA256"]) else {
            throw handoffError()
        }
        let request = try JSONDecoder().decode(Self.self, from: data)
        guard request.schemaVersion == schemaVersion,
              validPackageName(request.packageName), validSHA256(request.packageSHA256) else {
            throw handoffError()
        }
        let package = root.appendingPathComponent(request.packageName).standardizedFileURL
        guard package.deletingLastPathComponent() == root else { throw handoffError() }
        let packageValues = try package.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard packageValues.isRegularFile == true, packageValues.isSymbolicLink != true else {
            throw handoffError()
        }
        try files.removeItem(at: requestURL)
        return Resolved(package: package, packageSHA256: request.packageSHA256)
    }

    private static func validateDirectory(_ directory: URL) throws {
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw handoffError() }
    }

    private static func validPackageName(_ value: String) -> Bool {
        value.range(of: "^DaBin-\\d+(?:\\.\\d+){0,2}-Update\\.zip$", options: .regularExpression) != nil
    }

    private static func validSHA256(_ value: String) -> Bool {
        value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
    }

    private static func writeExclusive(_ data: Data, to url: URL) throws {
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var shouldRemove = true
        defer {
            _ = close(descriptor)
            if shouldRemove { try? FileManager.default.removeItem(at: url) }
        }
        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { throw handoffError() }
            var offset = 0
            while offset < rawBuffer.count {
                let count = Darwin.write(descriptor, base.advanced(by: offset), rawBuffer.count - offset)
                if count < 0 {
                    if errno == EINTR { continue }
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                guard count > 0 else { throw handoffError() }
                offset += count
            }
        }
        guard fsync(descriptor) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        shouldRemove = false
    }

    private static func handoffError() -> NSError {
        NSError(domain: "DaBinUpdateHandoff", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The verified update request is invalid or unsafe."])
    }
}

/// Pin the caller's package descriptor, then give extraction an owned private
/// copy. Reopening the caller's pathname after hashing permits replacement.
enum DaBinUpdatePackageCopy {
    static let maximumBytes: Int64 = 1_073_741_824

    static func freeze(_ package: URL, sha256 expected: String, in directory: URL) throws -> URL {
        guard package.isFileURL, directory.isFileURL,
              expected.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
            throw failure("The update package checksum or path is invalid.")
        }
        var directoryStat = stat()
        guard lstat(directory.path, &directoryStat) == 0,
              directoryStat.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              directoryStat.st_uid == getuid(), directoryStat.st_mode & 0o077 == 0 else {
            throw failure("The update copy needs a private, owned temporary folder.")
        }
        let source = open(package.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard source >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { _ = close(source) }
        var sourceStat = stat()
        guard fstat(source, &sourceStat) == 0,
              sourceStat.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              sourceStat.st_size > 0, sourceStat.st_size <= maximumBytes else {
            throw failure("The downloaded update is not a normal ZIP file or is unexpectedly large.")
        }
        let result = directory.appendingPathComponent("verified-update.zip")
        let copied = open(result.path, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard copied >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var completed = false
        defer {
            _ = close(copied)
            if !completed { try? FileManager.default.removeItem(at: result) }
        }
        let input = FileHandle(fileDescriptor: source, closeOnDealloc: false)
        var bytes: Int64 = 0
        while try autoreleasepool(invoking: {
            let data = try input.read(upToCount: 1024 * 1024) ?? Data()
            guard !data.isEmpty else { return false }
            bytes += Int64(data.count)
            guard bytes <= maximumBytes else { throw failure("The update grew beyond its allowed size while copying.") }
            try data.withUnsafeBytes { buffer in
                guard let base = buffer.baseAddress else { return }
                var offset = 0
                while offset < buffer.count {
                    let written = Darwin.write(copied, base.advanced(by: offset), buffer.count - offset)
                    if written < 0 {
                        if errno == EINTR { continue }
                        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                    }
                    guard written > 0 else { throw failure("The private update copy could not be written.") }
                    offset += written
                }
            }
            return true
        }) {}
        guard bytes == sourceStat.st_size, fsync(copied) == 0, lseek(copied, 0, SEEK_SET) == 0 else {
            throw failure("The update package changed or could not be saved safely.")
        }
        let output = FileHandle(fileDescriptor: copied, closeOnDealloc: false)
        var hasher = SHA256()
        while try autoreleasepool(invoking: {
            let data = try output.read(upToCount: 1024 * 1024) ?? Data()
            guard !data.isEmpty else { return false }
            hasher.update(data: data)
            return true
        }) {}
        let actual = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == expected else {
            throw failure("The update ZIP does not match the checksum published by DaBin’s GitHub release.")
        }
        completed = true
        return result
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "DaBinUpdatePackageCopy", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}

/// Commit without replacing a competing app. Rollback may remove only the
/// directory this transaction moved into place, identified by device/inode.
enum DaBinUpdateCommit {
    struct Identity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    static func install(stage: URL, destination: URL, backup: URL?,
                        beforeRollbackQuarantine: (() throws -> Void)? = nil,
                        validate: (URL) throws -> Void) throws {
        let owned = try directoryIdentity(stage)
        var moved = false
        do {
            try moveExclusively(stage, to: destination)
            moved = true
            try validate(destination)
        } catch {
            let originalError = error
            var recoveryProblems: [String] = []
            if moved {
                do {
                    try removeOwnedDirectory(destination, matching: owned,
                                             beforeQuarantine: beforeRollbackQuarantine)
                } catch { recoveryProblems.append(error.localizedDescription) }
            }
            if let backup {
                do { try moveExclusively(backup, to: destination) }
                catch {
                    recoveryProblems.append("The previous app could not be restored without replacing a conflicting destination. Its backup is preserved at \(backup.path).")
                }
            }
            if !recoveryProblems.isEmpty {
                throw failure(originalError.localizedDescription + "\n" + recoveryProblems.joined(separator: "\n"))
            }
            throw originalError
        }
    }

    static func removeOwnedDirectory(_ url: URL, matching owned: Identity,
                                     beforeQuarantine: (() throws -> Void)? = nil) throws {
        guard try directoryIdentity(url) == owned else {
            throw failure("A different app now occupies \(url.path). It was preserved.")
        }
        try beforeQuarantine?()
        let quarantine = url.deletingLastPathComponent()
            .appendingPathComponent(".DaBin-update-recovery-\(UUID().uuidString).app")
        // The original leaf is never recursively deleted. Inspect the inode
        // after an exclusive rename into this transaction's private UUID path.
        try moveExclusively(url, to: quarantine)
        guard let movedIdentity = try? directoryIdentity(quarantine), movedIdentity == owned else {
            var preserved = quarantine
            do { try moveExclusively(quarantine, to: url); preserved = url }
            catch { /* Preserve the conflicting app in quarantine if its leaf is occupied. */ }
            throw failure("Another app replaced the update during rollback. It was preserved at \(preserved.path).")
        }
        do { try FileManager.default.removeItem(at: quarantine) }
        catch {
            throw failure("The owned failed update could not be removed completely. Its remaining files are at \(quarantine.path): \(error.localizedDescription)")
        }
    }

    static func moveExclusively(_ source: URL, to destination: URL) throws {
        guard source.isFileURL, destination.isFileURL else { throw failure("The update move needs local file paths.") }
        guard renamex_np(source.path, destination.path, UInt32(RENAME_EXCL)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    static func directoryIdentity(_ url: URL) throws -> Identity {
        var attributes = stat()
        guard lstat(url.path, &attributes) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard attributes.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else {
            throw failure("The update destination is no longer the owned application folder.")
        }
        return Identity(device: attributes.st_dev, inode: attributes.st_ino)
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "DaBinUpdateCommit", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}
