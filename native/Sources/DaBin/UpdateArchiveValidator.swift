import Darwin
import Foundation
import zlib

/// Preflight the deliberately small ZIP feature set used by DaBin packages
/// before an extractor can create any paths or expand attacker-controlled data.
/// Payloads are CRC checked with bounded streaming expansion; application
/// signatures are validated separately by the installer after extraction.
enum DaBinUpdateArchiveValidator {
    struct Inventory: Equatable {
        let entryCount: Int
        let expandedBytes: Int64
        let rootDirectory: String
    }

    static let maximumArchiveBytes: Int64 = 1_073_741_824
    static let maximumExpandedBytes: Int64 = 2_147_483_648
    static let maximumEntryBytes: Int64 = 536_870_912
    static let maximumEntries = 20_000
    static let maximumNameBytes = 1_024
    private static let maximumDirectoryBytes = 32 * 1_024 * 1_024
    private static let maximumExtraBytes = 4_096

    private struct Entry {
        let name: String
        let nameBytes: Data
        let flags: UInt16
        let method: UInt16
        let crc: UInt32
        let compressed: Int64
        let expanded: Int64
        let offset: Int64
        let directory: Bool
    }

    private final class Reader {
        let descriptor: Int32
        let size: Int64
        let identity: stat

        init(_ url: URL) throws {
            guard url.isFileURL else { throw invalid("Choose a local update ZIP.") }
            let fd = url.path.withCString { Darwin.open($0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC) }
            guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            var metadata = stat()
            guard Darwin.fstat(fd, &metadata) == 0 else {
                Darwin.close(fd)
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            guard metadata.st_mode & S_IFMT == S_IFREG, metadata.st_size >= 22,
                  metadata.st_size <= maximumArchiveBytes else {
                Darwin.close(fd)
                throw invalid("The update ZIP is not a regular file or exceeds its size limit.")
            }
            descriptor = fd
            size = Int64(metadata.st_size)
            identity = metadata
        }

        deinit { Darwin.close(descriptor) }

        func read(at offset: Int64, count: Int) throws -> Data {
            guard offset >= 0, count >= 0, count <= maximumDirectoryBytes,
                  Int64(count) <= size, offset <= size - Int64(count) else {
                throw invalid("The ZIP inventory contains an out-of-bounds record.")
            }
            var data = Data(count: count)
            try data.withUnsafeMutableBytes { bytes in
                var completed = 0
                while completed < count {
                    let result = Darwin.pread(descriptor, bytes.baseAddress?.advanced(by: completed),
                                              count - completed, off_t(offset + Int64(completed)))
                    if result < 0 {
                        if errno == EINTR { continue }
                        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                    }
                    guard result > 0 else { throw invalid("The update ZIP is truncated.") }
                    completed += result
                }
            }
            return data
        }

        func verifyUnchanged() throws {
            var after = stat()
            guard Darwin.fstat(descriptor, &after) == 0,
                  after.st_dev == identity.st_dev, after.st_ino == identity.st_ino,
                  after.st_size == identity.st_size,
                  after.st_mtimespec.tv_sec == identity.st_mtimespec.tv_sec,
                  after.st_mtimespec.tv_nsec == identity.st_mtimespec.tv_nsec,
                  after.st_ctimespec.tv_sec == identity.st_ctimespec.tv_sec,
                  after.st_ctimespec.tv_nsec == identity.st_ctimespec.tv_nsec else {
                throw invalid("The update ZIP changed during inspection.")
            }
        }
    }

    @discardableResult
    static func validate(_ package: URL) throws -> Inventory {
        let reader = try Reader(package)
        let tailSize = Int(min(reader.size, 65_557))
        let tail = try reader.read(at: reader.size - Int64(tailSize), count: tailSize)
        var endRecord: Int?
        for position in stride(from: tail.count - 22, through: 0, by: -1) {
            if uint32(tail, position) == 0x06054b50,
               position + 22 + Int(uint16(tail, position + 20)) == tail.count {
                endRecord = position
                break
            }
        }
        guard let end = endRecord else { throw invalid("The ZIP end record is missing or ambiguous.") }
        let count = Int(uint16(tail, end + 10))
        let directorySize = Int64(uint32(tail, end + 12))
        let directoryOffset = Int64(uint32(tail, end + 16))
        let endOffset = reader.size - Int64(tailSize) + Int64(end)
        guard uint16(tail, end + 4) == 0, uint16(tail, end + 6) == 0,
              Int(uint16(tail, end + 8)) == count, count > 0, count <= maximumEntries,
              count != 0xffff, directorySize != 0xffffffff, directoryOffset != 0xffffffff,
              directorySize > 0, directorySize <= Int64(maximumDirectoryBytes),
              directoryOffset > 0, directoryOffset <= endOffset,
              directorySize == endOffset - directoryOffset else {
            throw invalid("Split, ZIP64, oversized or inconsistent ZIP inventories are unsupported.")
        }
        let central = try reader.read(at: directoryOffset, count: Int(directorySize))
        var entries: [Entry] = []
        var seen: [String: Bool] = [:]
        var parentDirectories: Set<String> = []
        var rootName: String?
        var expandedBytes: Int64 = 0
        var cursor = 0
        for _ in 0..<count {
            guard cursor <= central.count - 46, uint32(central, cursor) == 0x02014b50 else {
                throw invalid("A ZIP central record is missing or truncated.")
            }
            let needed = uint16(central, cursor + 6)
            let flags = uint16(central, cursor + 8)
            let method = uint16(central, cursor + 10)
            try validateFeatures(version: needed, flags: flags, method: method)
            let nameCount = Int(uint16(central, cursor + 28))
            let extraCount = Int(uint16(central, cursor + 30))
            let commentCount = Int(uint16(central, cursor + 32))
            let recordSize = 46 + nameCount + extraCount + commentCount
            guard nameCount > 0, nameCount <= maximumNameBytes, extraCount <= maximumExtraBytes,
                  recordSize <= central.count - cursor, uint16(central, cursor + 34) == 0 else {
                throw invalid("A ZIP entry exceeds its name or metadata limits.")
            }
            let nameBytes = central.subdata(in: (cursor + 46)..<(cursor + 46 + nameCount))
            let name = try decodedName(nameBytes, flags: flags)
            let components = try pathComponents(name)
            let directory = name.hasSuffix("/")
            let external = uint32(central, cursor + 38)
            let host = uint16(central, cursor + 4) >> 8
            try validateMode(external, host: host, directory: directory)
            let compressed = Int64(uint32(central, cursor + 20))
            let expanded = Int64(uint32(central, cursor + 24))
            let offset = Int64(uint32(central, cursor + 42))
            guard compressed != 0xffffffff, expanded != 0xffffffff, offset != 0xffffffff,
                  expanded <= maximumEntryBytes, expanded <= maximumExpandedBytes - expandedBytes,
                  compressed <= maximumArchiveBytes, offset < directoryOffset,
                  (!directory || expanded == 0), (method != 0 || compressed == expanded) else {
                throw invalid("A ZIP entry exceeds its expanded size limit or has inconsistent sizes.")
            }
            expandedBytes += expanded
            try validateExtra(central.subdata(in: (cursor + 46 + nameCount)..<(cursor + 46 + nameCount + extraCount)))
            let normalized = components.map {
                $0.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
                    .precomposedStringWithCanonicalMapping
            }
            let key = normalized.joined(separator: "/")
            guard seen[key] == nil, directory || !parentDirectories.contains(key) else {
                throw invalid("The ZIP contains duplicate or conflicting filesystem paths.")
            }
            for depth in 1..<normalized.count {
                let parent = normalized.prefix(depth).joined(separator: "/")
                guard seen[parent] != false else { throw invalid("A ZIP file also acts as another entry's directory.") }
                parentDirectories.insert(parent)
            }
            seen[key] = directory
            if let rootName {
                guard components.first == rootName else { throw invalid("The ZIP has more than one package root.") }
            } else {
                guard let first = components.first, first.hasPrefix("DaBin-") else {
                    throw invalid("The ZIP is not a DaBin update package.")
                }
                rootName = first
            }
            entries.append(Entry(name: name, nameBytes: nameBytes, flags: flags, method: method,
                                 crc: uint32(central, cursor + 16), compressed: compressed,
                                 expanded: expanded, offset: offset, directory: directory))
            cursor += recordSize
        }
        guard cursor == central.count else { throw invalid("The ZIP has unlisted central records.") }
        var nextOffset: Int64 = 0
        for entry in entries.sorted(by: { $0.offset < $1.offset }) {
            guard entry.offset == nextOffset else { throw invalid("The ZIP has overlapping, hidden or unlisted local records.") }
            let local = try reader.read(at: entry.offset, count: 30)
            guard uint32(local, 0) == 0x04034b50,
                  uint16(local, 6) == entry.flags, uint16(local, 8) == entry.method else {
                throw invalid("Local and central ZIP headers disagree.")
            }
            try validateFeatures(version: uint16(local, 4), flags: uint16(local, 6), method: uint16(local, 8))
            let nameCount = Int(uint16(local, 26))
            let extraCount = Int(uint16(local, 28))
            guard nameCount == entry.nameBytes.count, extraCount <= maximumExtraBytes else {
                throw invalid("Local and central ZIP names or metadata disagree.")
            }
            let variable = try reader.read(at: entry.offset + 30, count: nameCount + extraCount)
            guard variable.prefix(nameCount) == entry.nameBytes else { throw invalid("Local and central ZIP paths disagree.") }
            try validateExtra(variable.subdata(in: nameCount..<(nameCount + extraCount)))
            let payloadStart = entry.offset + 30 + Int64(nameCount + extraCount)
            guard payloadStart <= directoryOffset, entry.compressed <= directoryOffset - payloadStart else {
                throw invalid("A ZIP payload overlaps its inventory.")
            }
            nextOffset = payloadStart + entry.compressed
            if entry.flags & 0x0008 == 0 {
                guard uint32(local, 14) == entry.crc,
                      Int64(uint32(local, 18)) == entry.compressed,
                      Int64(uint32(local, 22)) == entry.expanded else {
                    throw invalid("Local and central ZIP checksums or sizes disagree.")
                }
            } else {
                guard [UInt32(0), entry.crc].contains(uint32(local, 14)),
                      [Int64(0), entry.compressed].contains(Int64(uint32(local, 18))),
                      [Int64(0), entry.expanded].contains(Int64(uint32(local, 22))) else {
                    throw invalid("A streamed ZIP local record contradicts its central inventory.")
                }
                let first = try reader.read(at: nextOffset, count: 4)
                let signed = uint32(first, 0) == 0x08074b50
                let descriptorSize = signed ? 16 : 12
                guard Int64(descriptorSize) <= directoryOffset - nextOffset else { throw invalid("A ZIP data descriptor overlaps its inventory.") }
                let descriptor = try reader.read(at: nextOffset, count: descriptorSize)
                let start = signed ? 4 : 0
                guard uint32(descriptor, start) == entry.crc,
                      Int64(uint32(descriptor, start + 4)) == entry.compressed,
                      Int64(uint32(descriptor, start + 8)) == entry.expanded else {
                    throw invalid("A ZIP data descriptor disagrees with its central inventory.")
                }
                nextOffset += Int64(descriptorSize)
            }
            try validatePayload(entry, at: payloadStart, reader: reader)
        }
        guard nextOffset == directoryOffset, let rootName else { throw invalid("The ZIP has unlisted payload data.") }
        try reader.verifyUnchanged()
        return Inventory(entryCount: entries.count, expandedBytes: expandedBytes, rootDirectory: rootName)
    }

    private static func validateFeatures(version: UInt16, flags: UInt16, method: UInt16) throws {
        guard (10...20).contains(version), method == 0 || method == 8,
              flags & ~UInt16(0x080e) == 0, method == 8 || flags & 0x0006 == 0 else {
            throw invalid("Encrypted, ZIP64 or unsupported ZIP features are not accepted.")
        }
    }

    private static func decodedName(_ data: Data, flags: UInt16) throws -> String {
        guard flags & 0x0800 != 0 || data.allSatisfy({ $0 < 0x80 }),
              let value = String(data: data, encoding: .utf8) else {
            throw invalid("ZIP paths must use unambiguous ASCII or UTF-8 names.")
        }
        return value
    }

    private static func pathComponents(_ name: String) throws -> [String] {
        guard !name.hasPrefix("/"), !name.contains("\\"), !name.contains(":"),
              !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw invalid("The ZIP contains an unsafe absolute or control-character path.")
        }
        let path = name.hasSuffix("/") ? String(name.dropLast()) : name
        let components = path.components(separatedBy: "/")
        guard !components.isEmpty, components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.utf8.count <= 255 }) else {
            throw invalid("The ZIP contains path traversal or ambiguous empty components.")
        }
        return components
    }

    private static func validateMode(_ external: UInt32, host: UInt16, directory: Bool) throws {
        guard host == 0 || host == 3 || host == 19 else { throw invalid("The ZIP uses unsupported filesystem metadata.") }
        let mode = external >> 16
        let type = mode & 0o170000
        guard mode & 0o7000 == 0, type == 0 || type == 0o100000 || type == 0o040000,
              type != 0o040000 || directory, type != 0o100000 || !directory,
              external & 0x10 == 0 || directory else {
            throw invalid("Symbolic links, special files and privileged ZIP modes are unsupported.")
        }
    }

    private static func validateExtra(_ data: Data) throws {
        var cursor = 0
        var seen: Set<UInt16> = []
        while cursor < data.count {
            guard cursor <= data.count - 4 else { throw invalid("ZIP extra metadata is truncated.") }
            let tag = uint16(data, cursor)
            let length = Int(uint16(data, cursor + 2))
            guard length <= data.count - cursor - 4, seen.insert(tag).inserted else {
                throw invalid("ZIP extra metadata is malformed or duplicated.")
            }
            // Time/owner annotations do not supply replacement paths. Unknown
            // fields (including ZIP64 and Unicode-path overrides) fail closed.
            guard (tag == 0x5455 && [1, 5, 9, 13].contains(length)) || (tag == 0x7875 && (3...19).contains(length))
                || (tag == 0x7855 && [0, 4].contains(length)) || (tag == 0x5855 && [8, 12].contains(length)) else {
                throw invalid("ZIP64 and alternate or unsupported ZIP metadata are not accepted.")
            }
            if tag == 0x5455 {
                guard data[cursor + 4] & ~UInt8(0x07) == 0 else { throw invalid("ZIP timestamp metadata is malformed.") }
            } else if tag == 0x7875 {
                let start = cursor + 4
                let uidBytes = Int(data[start + 1])
                guard data[start] == 1, uidBytes > 0, uidBytes <= 8, 3 + uidBytes <= length else {
                    throw invalid("ZIP owner metadata is malformed.")
                }
                let gidBytes = Int(data[start + 2 + uidBytes])
                guard gidBytes > 0, gidBytes <= 8, 3 + uidBytes + gidBytes == length else {
                    throw invalid("ZIP group metadata is malformed.")
                }
            }
            cursor += 4 + length
        }
    }

    private static func validatePayload(_ entry: Entry, at offset: Int64, reader: Reader) throws {
        let chunkSize = 65_536
        var checksum = crc32(0, nil, 0)
        var expanded: Int64 = 0
        var consumed: Int64 = 0
        if entry.method == 0 {
            while consumed < entry.compressed {
                let count = Int(min(Int64(chunkSize), entry.compressed - consumed))
                let data = try reader.read(at: offset + consumed, count: count)
                checksum = data.withUnsafeBytes {
                    crc32(checksum, $0.bindMemory(to: Bytef.self).baseAddress, uInt(count))
                }
                consumed += Int64(count)
            }
            expanded = consumed
        } else {
            var stream = z_stream()
            guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
                throw invalid("The ZIP decoder could not be initialized.")
            }
            defer { inflateEnd(&stream) }
            var output = [UInt8](repeating: 0, count: chunkSize)
            var finished = false
            while consumed < entry.compressed && !finished {
                let count = Int(min(Int64(chunkSize), entry.compressed - consumed))
                let data = try reader.read(at: offset + consumed, count: count)
                consumed += Int64(count)
                try data.withUnsafeBytes { input in
                    stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
                    stream.avail_in = uInt(count)
                    var produced = chunkSize
                    while stream.avail_in > 0 || produced == chunkSize {
                        let previousInput = stream.avail_in
                        let result = output.withUnsafeMutableBufferPointer { buffer -> Int32 in
                            stream.next_out = buffer.baseAddress
                            stream.avail_out = uInt(buffer.count)
                            let result = inflate(&stream, Z_NO_FLUSH)
                            produced = buffer.count - Int(stream.avail_out)
                            if produced > 0 { checksum = crc32(checksum, buffer.baseAddress, uInt(produced)) }
                            return result
                        }
                        guard Int64(produced) <= entry.expanded - expanded else {
                            throw invalid("A ZIP stream expands beyond its declared size or safety limit.")
                        }
                        expanded += Int64(produced)
                        if result == Z_STREAM_END {
                            guard stream.avail_in == 0, consumed == entry.compressed else {
                                throw invalid("A ZIP stream has unlisted compressed data.")
                            }
                            finished = true
                            break
                        }
                        if produced == 0, stream.avail_in == 0, result == Z_BUF_ERROR || result == Z_OK {
                            // A full output buffer can drain the current input
                            // chunk without ending the stream. Yield to the
                            // next bounded input read; the final finish check
                            // still rejects an actually truncated last chunk.
                            break
                        }
                        guard result == Z_OK, produced > 0 || stream.avail_in < previousInput else {
                            throw invalid("A ZIP deflate stream is malformed or truncated.")
                        }
                    }
                }
            }
            guard finished else { throw invalid("A ZIP deflate stream did not finish.") }
        }
        guard expanded == entry.expanded, UInt32(checksum) == entry.crc else {
            throw invalid("A ZIP payload does not match its declared size and checksum.")
        }
    }

    private static func uint16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func uint32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset]) | UInt32(data[offset + 1]) << 8 | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
    }

    private static func invalid(_ message: String) -> NSError {
        NSError(domain: "DaBinUpdateArchive", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The update ZIP could not be verified. " + message])
    }
}
