import Foundation
import CryptoKit

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
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey, .isAliasFileKey])
        guard values.isSymbolicLink != true, values.isAliasFile != true else { throw CaptureStoreError.symbolicLinkNotSupported }
        guard values.isDirectory != true else { throw CaptureStoreError.directoryNotSupported }
        guard values.isRegularFile == true else { throw CaptureStoreError.invalidOriginal("This is not a regular file.") }
    }

    static func verify(_ url: URL) throws -> OriginalVerification {
        try validateRegularFile(url)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var size: Int64 = 0
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
            size += Int64(data.count)
        }
        return OriginalVerification(byteCount: size, sha256: hasher.finalize().map { String(format: "%02x", $0) }.joined())
    }

}
