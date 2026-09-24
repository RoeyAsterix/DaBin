import Foundation
import CryptoKit

/// The human-readable local archive. Core Data remains the index; this component
/// owns only generated sidecars and never copies, changes, or removes originals.
@MainActor final class DailyArchive {
    enum ArchiveError: LocalizedError {
        case invalidDay(String), invalidTime, unsafePath(String), notDirectory(String), notFile(String)

        var errorDescription: String? {
            switch self {
            case .invalidDay(let value): return "Invalid archive day: \(value)."
            case .invalidTime: return "The capture has an invalid time or UTC offset."
            case .unsafePath(let value): return "Unsafe archive path: \(value)."
            case .notDirectory(let value): return "An archive folder is occupied by a file: \(value)."
            case .notFile(let value): return "An archive file is occupied by a folder or special file: \(value)."
            }
        }
    }

    private struct GeneratedManifest: Codable {
        let version: Int
        let hashes: [String: String]
    }

    nonisolated let root: URL
    private nonisolated let resolvedRoot: URL
    private nonisolated var files: FileManager { FileManager.default }
    private let manifestName = ".dabin-generated.json"

    init(root: URL) {
        self.root = root.standardizedFileURL
        self.resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
    }

    /// Fixed English names and Gregorian dates do not change when macOS locale changes.
    nonisolated static func dayRelativePath(captureDay: String) throws -> String {
        let day = try parsedDay(captureDay)
        let year = day.calendar.component(.year, from: day.date)
        let month = day.calendar.component(.month, from: day.date)
        let number = day.calendar.component(.day, from: day.date)
        let weekday = day.calendar.component(.weekday, from: day.date)
        let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
        let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let monthFolder = String(format: "%02d %@", month, months[month - 1])
        // Keep the day label in one place so its user-facing naming can evolve independently.
        let dayFolder = String(format: "%02d %@ %@ %04d", number, weekdays[weekday - 1], months[month - 1], year)
        return String(format: "Archive/%04d/%@/%@", year, monthFolder, dayFolder)
    }

    nonisolated static func captureRelativePath(id: UUID, capturedAt: Date, captureDay: String, utcOffset: Int) throws -> String {
        let day = try dayRelativePath(captureDay: captureDay)
        let clock = try captureClock(capturedAt, offset: utcOffset, separator: "-")
        return "\(day)/\(clock) - \(id.uuidString)"
    }

    nonisolated static func originalRelativePath(id: UUID, capturedAt: Date, captureDay: String, utcOffset: Int, filename: String) throws -> String {
        try captureRelativePath(id: id, capturedAt: capturedAt, captureDay: captureDay, utcOffset: utcOffset)
            + "/Original/" + CaptureClassifier.storageFilename(filename)
    }

    /// Reject path traversal and all symlinks below the configured root, including
    /// dangling links. System aliases above the root (such as /var) are supported.
    nonisolated func safeURL(_ relative: String) throws -> URL {
        guard root.isFileURL, !relative.isEmpty, !relative.hasPrefix("/"),
              !relative.contains("\\"), !relative.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw ArchiveError.unsafePath(relative)
        }
        let parts = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            throw ArchiveError.unsafePath(relative)
        }
        try validateRoot()
        var result = root
        for (index, part) in parts.enumerated() {
            result.appendPathComponent(String(part))
            try rejectSymbolicLink(result)
            var isDirectory: ObjCBool = false
            if files.fileExists(atPath: result.path, isDirectory: &isDirectory), index < parts.count - 1, !isDirectory.boolValue {
                throw ArchiveError.notDirectory(result.path)
            }
        }
        let resolved = result.resolvingSymlinksInPath().standardizedFileURL.path
        guard resolved.hasPrefix(resolvedRoot.path + "/") else { throw ArchiveError.unsafePath(relative) }
        return result
    }

    @discardableResult nonisolated func ensureDirectory(_ relative: String) throws -> URL {
        let destination = try safeURL(relative)
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        var current = root
        for part in relative.split(separator: "/") {
            current.appendPathComponent(String(part), isDirectory: true)
            try rejectSymbolicLink(current)
            var isDirectory: ObjCBool = false
            if files.fileExists(atPath: current.path, isDirectory: &isDirectory) {
                guard isDirectory.boolValue else { throw ArchiveError.notDirectory(current.path) }
            } else {
                do {
                    try files.createDirectory(at: current, withIntermediateDirectories: false)
                } catch let error as CocoaError where error.code == .fileWriteFileExists {
                    // Independent preview workers can create a shared parent
                    // between the existence check and mkdir. Accept that race
                    // only when the resulting entry is still a safe directory.
                    try rejectSymbolicLink(current)
                    guard files.fileExists(atPath: current.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                        throw ArchiveError.notDirectory(current.path)
                    }
                }
            }
        }
        _ = try safeURL(relative)
        return destination
    }

    /// Synchronization is repeatable. A changed user sidecar is copied into Local
    /// edits before replacement; a sidecar already equal to this snapshot is untouched.
    func synchronize(_ capture: Capture) throws {
        let relative = try Self.captureRelativePath(id: capture.id, capturedAt: capture.capturedAt,
                                                   captureDay: capture.captureDay, utcOffset: capture.captureUTCOffsetSeconds)
        _ = try ensureDirectory(relative)
        let manifestRelative = relative + "/" + manifestName
        let manifestURL = try safeURL(manifestRelative)
        let oldManifestData = try readRegularFileIfPresent(manifestURL)
        let oldManifest = oldManifestData.flatMap { try? JSONDecoder().decode(GeneratedManifest.self, from: $0) }
        let oldHashes = oldManifest?.version == 1 ? oldManifest!.hashes : [:]

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        var outputs: [String: Data] = [
            "Capture.json": try encoder.encode(CaptureSnapshot(capture)),
            "Capture.md": Data(try markdown(capture).utf8)
        ]
        if let text = capture.originalText { outputs["Content.txt"] = Data(text.utf8) }
        if ContentIndexService.isEligible(capture.kind) {
            // Always own the sidecar for eligible immutable types, including an
            // empty result, so rebuilding cannot leave stale recognized text.
            outputs["Searchable Text.txt"] = Data(capture.indexedText.utf8)
        }
        if capture.kind == .link, let link = capture.originalURL {
            outputs["Link.webloc"] = try PropertyListSerialization.data(fromPropertyList: ["URL": link], format: .xml, options: 0)
        }
        var hashes = oldHashes
        for name in outputs.keys.sorted() {
            let contents = outputs[name]!
            let outputRelative = relative + "/" + name
            let outputURL = try safeURL(outputRelative)
            let existing = try readRegularFileIfPresent(outputURL)
            if let existing, existing != contents {
                if oldHashes[name] != Self.digest(existing) {
                    try preserve(existing, filename: name, captureRelative: relative)
                }
            }
            if existing != contents { try write(contents, to: outputRelative) }
            hashes[name] = Self.digest(contents)
        }
        let newManifestData = try encoder.encode(GeneratedManifest(version: 1, hashes: hashes))
        if oldManifestData != newManifestData {
            if let oldManifestData, oldManifest == nil || oldManifest?.version != 1 {
                try preserve(oldManifestData, filename: manifestName, captureRelative: relative)
            }
            try write(newManifestData, to: manifestRelative)
        }
    }

    private nonisolated func validateRoot() throws {
        try rejectSymbolicLink(root)
        guard root.resolvingSymlinksInPath().path == resolvedRoot.path else { throw ArchiveError.unsafePath(root.path) }
        var isDirectory: ObjCBool = false
        if files.fileExists(atPath: root.path, isDirectory: &isDirectory), !isDirectory.boolValue {
            throw ArchiveError.notDirectory(root.path)
        }
    }

    private nonisolated func rejectSymbolicLink(_ url: URL) throws {
        if (try? files.destinationOfSymbolicLink(atPath: url.path)) != nil {
            throw ArchiveError.unsafePath(url.path)
        }
    }

    private nonisolated func readRegularFileIfPresent(_ url: URL) throws -> Data? {
        try rejectSymbolicLink(url)
        guard files.fileExists(atPath: url.path) else { return nil }
        let attributes = try files.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw ArchiveError.notFile(url.path) }
        return try Data(contentsOf: url)
    }

    private nonisolated func write(_ contents: Data, to relative: String) throws {
        let destination = try safeURL(relative)
        _ = try readRegularFileIfPresent(destination)
        try contents.write(to: destination, options: .atomic)
    }

    private func preserve(_ contents: Data, filename: String, captureRelative: String) throws {
        let backupRelative = captureRelative + "/Local edits"
        _ = try ensureDirectory(backupRelative)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let relative = "\(backupRelative)/\(stamp) - \(UUID().uuidString) - \(CaptureClassifier.storageFilename(filename))"
        let destination = try safeURL(relative)
        // UUID naming plus withoutOverwriting avoids replacing any existing backup.
        try contents.write(to: destination, options: .withoutOverwriting)
    }

    private nonisolated static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func parsedDay(_ value: String) throws -> (date: Date, calendar: Calendar) {
        let bytes = Array(value.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ [4, 7].contains($0.offset) || (48...57).contains($0.element) }),
              let year = Int(value.prefix(4)), year >= 1,
              let month = Int(value.dropFirst(5).prefix(2)), let day = Int(value.suffix(2)) else {
            throw ArchiveError.invalidDay(value)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(era: 1, year: year, month: month, day: day)) else {
            throw ArchiveError.invalidDay(value)
        }
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        guard check.year == year, check.month == month, check.day == day else { throw ArchiveError.invalidDay(value) }
        return (date, calendar)
    }

    private nonisolated static func captureClock(_ date: Date, offset: Int, separator: String) throws -> String {
        guard date.timeIntervalSinceReferenceDate.isFinite, (-64_800...64_800).contains(offset),
              let zone = TimeZone(secondsFromGMT: offset) else { throw ArchiveError.invalidTime }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        guard let hour = parts.hour, let minute = parts.minute, let second = parts.second else { throw ArchiveError.invalidTime }
        return String(format: "%02d%@%02d%@%02d", hour, separator, minute, separator, second)
    }

    private func markdown(_ capture: Capture) throws -> String {
        let iso = ISO8601DateFormatter()
        let time = try Self.captureClock(capture.capturedAt, offset: capture.captureUTCOffsetSeconds, separator: ":")
        let title = capture.title.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        var lines = ["# \(title)", "", "- Kind: \(capture.kind.rawValue)",
                     "- Captured day: \(capture.captureDay)", "- Captured time: \(time)",
                     "- Captured time zone: \(capture.captureTimeZoneID) (UTC offset \(capture.captureUTCOffsetSeconds) seconds)",
                     "- Captured instant: \(iso.string(from: capture.capturedAt))", "- ID: \(capture.id.uuidString)"]
        if capture.isTask { lines.append("- Status: \(capture.isCompleted ? "Completed" : "Task")") }
        lines.append("- Capture origin: \(capture.captureOrigin.displayName)")
        if let actionID = capture.automaticActionID { lines.append("- Automatic action ID: \(actionID.uuidString)") }
        if let application = capture.sourceApplicationName { lines.append("- Source application: \(singleLine(application))") }
        if let bundle = capture.sourceApplicationBundleIdentifier { lines.append("- Source application bundle: \(singleLine(bundle))") }
        if let original = capture.originalFilename { lines.append("- Original filename: \(singleLine(original))") }
        if let path = capture.attachmentRelativePath { lines.append("- Local original: \(singleLine(path))") }
        if let path = capture.sourceFilePath { lines.append("- Source path: \(singleLine(path))") }
        if let url = capture.sourceURL { lines.append("- Source URL: \(singleLine(url))") }
        if capture.sourceFilePath == nil && capture.sourceURL == nil { lines.append("- Source location: Not supplied") }
        if let reminder = capture.reminderAt {
            lines.append("- Reminder: \(iso.string(from: reminder))")
            if let zone = capture.reminderTimeZoneID { lines.append("- Reminder time zone: \(zone)") }
            lines.append("- Reminder state: \(capture.notificationState)")
        } else { lines.append("- Reminder: None") }
        if let original = capture.originalURL { lines += ["", "## Link", "", fenced(original)] }
        if let text = capture.originalText { lines += ["", "## Content", "", fenced(text)] }
        if !capture.indexedText.isEmpty {
            lines += ["", "## Searchable text", "", fenced(capture.indexedText)]
        }
        lines += ["", "## Comment", "", capture.comment.isEmpty ? "No comment." : fenced(capture.comment), ""]
        return lines.joined(separator: "\n")
    }

    private func singleLine(_ value: String) -> String {
        value.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
    }

    private func fenced(_ value: String) -> String {
        let longest = value.split(whereSeparator: { $0 != "`" }).map(\.count).max() ?? 0
        let fence = String(repeating: "`", count: max(3, longest + 1))
        return "\(fence)text\n\(value)\n\(fence)"
    }
}
