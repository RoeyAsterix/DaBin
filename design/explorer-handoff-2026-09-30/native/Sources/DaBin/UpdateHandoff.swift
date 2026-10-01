import Darwin
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
