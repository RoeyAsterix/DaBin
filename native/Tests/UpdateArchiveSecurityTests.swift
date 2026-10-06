import Darwin
import Foundation
import zlib

/// All ZIPs and extraction fixtures are fictional, disposable and local.
/// No application bundle, user archive, clipboard, account or network is opened.
@main
private enum UpdateArchiveSecurityTests {
    private static var checks = 0
    private static let files = FileManager.default

    private struct Member {
        var name: String
        var bytes = Data("Fictional local update bytes".utf8)
        var method: UInt16 = 0
        var flags: UInt16 = 0x0800
        var mode: UInt32 = 0o100600
        var localName: String?
        var advertisedExpanded: UInt32?
        var extra = Data()
        var descriptorSignature = true
    }

    private static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        guard try value() else { throw NSError(domain: "UpdateArchiveSecurityTests", code: checks,
                                               userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    private static func append16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value)); data.append(UInt8(truncatingIfNeeded: value >> 8))
    }

    private static func append32(_ value: UInt32, to data: inout Data) {
        for shift in [0, 8, 16, 24] { data.append(UInt8(truncatingIfNeeded: value >> shift)) }
    }

    private static func replace32(_ value: UInt32, at offset: Int, in data: inout Data) {
        for (index, shift) in [0, 8, 16, 24].enumerated() { data[offset + index] = UInt8(truncatingIfNeeded: value >> shift) }
    }

    private static func crc(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { UInt32(crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(data.count))) }
    }

    private static func deflated(_ data: Data) throws -> Data {
        var stream = z_stream()
        guard deflateInit2_(&stream, Z_BEST_COMPRESSION, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY,
                           ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw NSError(domain: "Fixture deflate", code: 1)
        }
        defer { deflateEnd(&stream) }
        var result = Data()
        var output = [UInt8](repeating: 0, count: 65_536)
        try data.withUnsafeBytes { input in
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(data.count)
            while true {
                let status = output.withUnsafeMutableBufferPointer { buffer -> Int32 in
                    stream.next_out = buffer.baseAddress
                    stream.avail_out = uInt(buffer.count)
                    let status = deflate(&stream, Z_FINISH)
                    result.append(buffer.baseAddress!, count: buffer.count - Int(stream.avail_out))
                    return status
                }
                if status == Z_STREAM_END { break }
                guard status == Z_OK else { throw NSError(domain: "Fixture deflate", code: 2) }
            }
        }
        return result
    }

    /// Emits real classic ZIP bytes, including payload CRCs and local records.
    /// Optional corruptions model deliberate central/local inventory ambiguity.
    private static func archive(_ members: [Member]) throws -> Data {
        var local = Data()
        var central = Data()
        for member in members {
            let name = Data(member.name.utf8)
            let localName = Data((member.localName ?? member.name).utf8)
            let payload = try member.method == 8 ? deflated(member.bytes) : member.bytes
            let checksum = crc(member.bytes)
            let expanded = member.advertisedExpanded ?? UInt32(member.bytes.count)
            let compressed = UInt32(payload.count)
            let offset = UInt32(local.count)
            let streaming = member.flags & 0x0008 != 0
            append32(0x04034b50, to: &local)
            append16(20, to: &local); append16(member.flags, to: &local); append16(member.method, to: &local)
            append16(0, to: &local); append16(0, to: &local)
            append32(streaming ? 0 : checksum, to: &local)
            append32(streaming ? 0 : compressed, to: &local); append32(streaming ? 0 : expanded, to: &local)
            append16(UInt16(localName.count), to: &local); append16(UInt16(member.extra.count), to: &local)
            local.append(localName); local.append(member.extra); local.append(payload)
            if streaming {
                if member.descriptorSignature { append32(0x08074b50, to: &local) }
                append32(checksum, to: &local); append32(compressed, to: &local); append32(expanded, to: &local)
            }
            append32(0x02014b50, to: &central)
            append16(0x0314, to: &central); append16(20, to: &central)
            append16(member.flags, to: &central); append16(member.method, to: &central)
            append16(0, to: &central); append16(0, to: &central)
            append32(checksum, to: &central); append32(compressed, to: &central); append32(expanded, to: &central)
            append16(UInt16(name.count), to: &central); append16(UInt16(member.extra.count), to: &central)
            append16(0, to: &central); append16(0, to: &central); append16(0, to: &central)
            append32(member.mode << 16 | (member.name.hasSuffix("/") ? 0x10 : 0), to: &central)
            append32(offset, to: &central)
            central.append(name); central.append(member.extra)
        }
        let directoryOffset = UInt32(local.count)
        local.append(central)
        append32(0x06054b50, to: &local)
        append16(0, to: &local); append16(0, to: &local)
        append16(UInt16(members.count), to: &local); append16(UInt16(members.count), to: &local)
        append32(UInt32(central.count), to: &local); append32(directoryOffset, to: &local); append16(0, to: &local)
        return local
    }

    private static func write(_ data: Data, root: URL) throws -> URL {
        let url = root.appendingPathComponent(UUID().uuidString + ".zip")
        try data.write(to: url, options: .withoutOverwriting)
        return url
    }

    private static func rejects(_ data: Data, root: URL, _ reason: String) throws {
        let url = try write(data, root: root)
        let before = try Data(contentsOf: url)
        var rejected = false
        do { _ = try DaBinUpdateArchiveValidator.validate(url) } catch { rejected = true }
        try expect(rejected, reason)
        try expect(try Data(contentsOf: url) == before, "Rejected preflight never modifies the ZIP: " + reason)
    }

    private static func validArchives(root: URL) throws {
        let prefix = "DaBin-0.0.1-Update/"
        let contents = Data(("Fictional fixture with Unicode תודה\n" + String(repeating: "abc012", count: 50_000)).utf8)
        let members = [Member(name: prefix, bytes: Data(), mode: 0o040700),
                       Member(name: prefix + "Readme.txt"),
                       Member(name: prefix + "DaBin.app/Contents/Resources/תודה.txt", bytes: contents, method: 8)]
        let url = try write(archive(members), root: root)
        let inventory = try DaBinUpdateArchiveValidator.validate(url)
        try expect(inventory.entryCount == 3 && inventory.expandedBytes == Int64(members.reduce(0) { $0 + $1.bytes.count })
                   && inventory.rootDirectory == "DaBin-0.0.1-Update",
                   "Real stored and raw-deflated Unicode payloads pass exact inventory and CRC checks")
        for signed in [true, false] {
            let streamed = Member(name: prefix + "Streamed.txt", bytes: contents, method: 8,
                                  flags: 0x0808, descriptorSignature: signed)
            try expect(try DaBinUpdateArchiveValidator.validate(write(archive([streamed]), root: root)).expandedBytes == Int64(contents.count),
                       "Classic32-bit streamed ZIPs pass with an optional data-descriptor signature")
        }
        var noise = Data()
        var seed: UInt64 = 0xdab1_2026_1006_1234
        for _ in 0..<300_000 {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            noise.append(UInt8(truncatingIfNeeded: seed))
        }
        try expect(try deflated(noise).count > 65_536, "The incompressible fixture exercises multiple compressed-input chunks")
        let large = Member(name: prefix + "Multiple chunks.bin", bytes: noise, method: 8)
        try expect(try DaBinUpdateArchiveValidator.validate(write(archive([large]), root: root)).expandedBytes == Int64(noise.count),
                   "Multiple compressed-input and output chunks stream safely without a large allocation")
        let timestamp = Data([0x55, 0x54, 5, 0, 1, 0, 0, 0, 0])
        let timed = Member(name: prefix + "Timestamp.txt", extra: timestamp)
        try expect(try DaBinUpdateArchiveValidator.validate(write(archive([timed]), root: root)).entryCount == 1,
                   "Bounded timestamp extra metadata remains compatible")
    }

    private static func unsafeInventories(root: URL) throws {
        let prefix = "DaBin-0.0.1-Update/"
        for name in ["../Escape.txt", "/Absolute.txt", prefix + "../Escape.txt", prefix + "./Hidden.txt",
                     prefix + "nested//File.txt", prefix + "nested\\File.txt", prefix + "Nul\0.txt",
                     prefix + "Newline\n.txt", prefix + "C:Drive.txt", prefix + String(repeating: "a", count: 256),
                     prefix + String(repeating: "a/", count: 600) + "Long.txt"] {
            try rejects(archive([Member(name: name)]), root: root, "Unsafe or oversized ZIP paths fail before extraction")
        }
        for mode: UInt32 in [0o120777, 0o010600, 0o020600, 0o060600, 0o1004755, 0o1002755] {
            try rejects(archive([Member(name: prefix + "Special", mode: mode)]), root: root,
                        "Symlink, FIFO, device and privileged-mode entries are rejected")
        }
        try rejects(archive([Member(name: prefix + "A.txt"), Member(name: prefix + "A.txt")]), root: root,
                    "Duplicate entries cannot overwrite a prior archive path")
        try rejects(archive([Member(name: prefix + "Case.txt"), Member(name: prefix + "case.txt")]), root: root,
                    "Case aliases on a standard macOS filesystem are rejected")
        try rejects(archive([Member(name: prefix + "Café.txt"), Member(name: prefix + "Cafe\u{301}.txt")]), root: root,
                    "Unicode-normalization aliases are rejected")
        try rejects(archive([Member(name: prefix + "Parent"), Member(name: prefix + "Parent/Child.txt")]), root: root,
                    "A file cannot also become an implicit parent directory")
        try rejects(archive([Member(name: prefix + "Parent/Child.txt"), Member(name: prefix + "Parent")]), root: root,
                    "Reverse-order file/parent collisions are also rejected")
        try rejects(archive([Member(name: prefix + "Safe.txt", localName: "../Evil.txt")]), root: root,
                    "Local headers cannot substitute an unsafe path for a safe central name")
        try rejects(archive([Member(name: prefix + "A.txt"), Member(name: "DaBin-other-Update/B.txt")]), root: root,
                    "More than one update-package root is rejected")
        for member in [Member(name: prefix + "Encrypted", flags: 0x0801),
                       Member(name: prefix + "Unsupported", method: 12),
                       Member(name: prefix + "ZIP64", extra: Data([1, 0, 0, 0])),
                       Member(name: prefix + "Alternate path", extra: Data([0x75, 0x70, 0, 0])),
                       Member(name: prefix + "Bad extra", extra: Data([0x55, 0x54, 5, 0, 1]))] {
            try rejects(archive([member]), root: root, "Unsupported encryption, methods, ZIP64 and path metadata fail closed")
        }
    }

    private static func sizeAndStreamBounds(root: URL) throws {
        let name = "DaBin-0.0.1-Update/Limit.txt"
        let bytes = Data(repeating: 65, count: 1_048_576)
        try rejects(archive([Member(name: name, bytes: bytes, method: 8, advertisedExpanded: 1)]), root: root,
                    "A deflate stream lying about its expanded size is stopped with bounded buffers")
        try rejects(archive([Member(name: name, bytes: bytes, method: 8, advertisedExpanded: 2_000_000)]), root: root,
                    "An overstated expanded length also fails actual streamed verification")
        try rejects(archive([Member(name: name, bytes: Data(), method: 8,
                                   advertisedExpanded: UInt32(DaBinUpdateArchiveValidator.maximumEntryBytes + 1))]), root: root,
                    "An oversized advertised entry is rejected without allocating its expanded size")
        let total = (0..<5).map { Member(name: "DaBin-0.0.1-Update/Limit-\($0)", bytes: Data(), method: 8,
                                       advertisedExpanded: UInt32(DaBinUpdateArchiveValidator.maximumEntryBytes)) }
        try rejects(archive(total), root: root, "Combined expanded limits are enforced before decoding")
        let excessive = (0...DaBinUpdateArchiveValidator.maximumEntries).map { Member(name: "DaBin-0.0.1-Update/Entry-\($0)", bytes: Data()) }
        try rejects(archive(excessive), root: root, "Too many entries fail the bounded central-inventory policy")
        var corrupt = try archive([Member(name: name)])
        let payloadOffset = 30 + name.utf8.count
        corrupt[payloadOffset] ^= 1
        try rejects(corrupt, root: root, "Stored payload corruption is detected before extraction")
        var localSize = try archive([Member(name: name)])
        replace32(1, at: 22, in: &localSize)
        try rejects(localSize, root: root, "Local and central size ambiguity is rejected")
        var hidden = try archive([Member(name: name)])
        hidden.insert(contentsOf: [0, 0, 0, 0], at: 0)
        try rejects(hidden, root: root, "Unlisted prefix/local records cannot create alternate extractor inventories")
        let valid = try archive([Member(name: name, bytes: bytes, method: 8)])
        for cut in [1, 10, 21, 30, valid.count - 1] {
            try rejects(Data(valid.prefix(cut)), root: root, "Truncated ZIP structures are rejected safely")
        }
        let huge = root.appendingPathComponent("Sparse oversized ZIP.zip")
        try Data().write(to: huge)
        let handle = try FileHandle(forWritingTo: huge)
        try handle.truncate(atOffset: UInt64(DaBinUpdateArchiveValidator.maximumArchiveBytes + 1))
        try handle.close()
        var rejected = false
        do { _ = try DaBinUpdateArchiveValidator.validate(huge) } catch { rejected = true }
        try expect(rejected, "A sparse oversized compressed file is rejected without reading or allocating its contents")
    }

    private static func realDittoArchive(root: URL) throws {
        let source = root.appendingPathComponent("DaBin-0.0.1-DittoUpdate", isDirectory: true)
        let folder = source.appendingPathComponent("DaBin.app/Contents/Resources", isDirectory: true)
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        let bytes = Data("Fictional ditto interoperability fixture\n".utf8)
        try bytes.write(to: folder.appendingPathComponent("Fixture.txt"))
        let zip = root.appendingPathComponent("Actual ditto.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", source.path, zip.path]
        let output = Pipe()
        process.standardOutput = output; process.standardError = output
        try process.run()
        let diagnostics = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try expect(process.terminationStatus == 0, "Synthetic ditto packaging succeeds: " + String(decoding: diagnostics, as: UTF8.self))
        let result = try DaBinUpdateArchiveValidator.validate(zip)
        try expect(result.expandedBytes == Int64(bytes.count) && result.rootDirectory == source.lastPathComponent,
                   "Actual macOS ditto packages pass bounded preflight before extraction")
    }

    static func main() throws {
        let root = files.temporaryDirectory.appendingPathComponent("DaBinUpdateArchiveSecurity-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? files.removeItem(at: root) }
        try validArchives(root: root)
        try unsafeInventories(root: root)
        try sizeAndStreamBounds(root: root)
        try realDittoArchive(root: root)
        print("PASS: \(checks) local ZIP inventory, path, mode, expansion, checksum, streamed-descriptor and ditto interoperability checks")
    }
}
