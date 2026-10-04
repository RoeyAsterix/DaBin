import Foundation
import zlib

/// Reads only bounded in-memory OOXML parts. No package member is written to
/// disk, and relationships, images, embedded objects and remote resources are
/// never followed. Classic ZIP (stored/raw deflate) and the main Word body are
/// supported; ZIP64, encryption, macros and unusual package layouts are not.
enum LocalDOCXTextExtractor {
    struct Result: Sendable, Equatable {
        let text: String
        let truncated: Bool
    }

    enum Failure: Error, Equatable {
        case malformed, unsupported, encrypted, tooLarge, cancelled

        var message: String {
            switch self {
            case .malformed:
                return "This DOCX document is damaged or malformed and could not be read for text search."
            case .unsupported:
                return "This DOCX document uses an unsupported package or XML feature for local text search."
            case .encrypted:
                return "This DOCX document is encrypted or uses a legacy Office container. Save an unencrypted DOCX copy to make its text searchable."
            case .tooLarge:
                return "This DOCX document exceeds the 12 MB local text-search safety limits."
            case .cancelled:
                return "Text recognition was cancelled."
            }
        }
    }

    static let maximumBytes = 12 * 1_024 * 1_024
    static let maximumCharacters = 300_000
    private static let maximumMembers = 2_048

    static func extract(data: Data, maximumBytes: Int = maximumBytes,
                        maximumCharacters: Int = maximumCharacters) throws -> Result {
        guard !Task.isCancelled else { throw Failure.cancelled }
        guard maximumBytes > 0, maximumCharacters > 0,
              data.count <= maximumBytes else { throw Failure.tooLarge }
        let data = Data(data) // Normalize a caller's slice to zero-based indices.
        // Office password protection uses an OLE container, not a ZIP package.
        if data.starts(with: [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]) {
            throw Failure.encrypted
        }
        let package = try Package(data: data, limit: maximumBytes)
        let types = try package.read("[Content_Types].xml")
        let typeParser = PartParser(mode: .contentTypes, maximumCharacters: maximumCharacters)
        try typeParser.parse(types)
        guard typeParser.hasMainContentType else { throw Failure.unsupported }
        let document = try package.read("word/document.xml")
        let textParser = PartParser(mode: .document, maximumCharacters: maximumCharacters)
        try textParser.parse(document)
        return Result(text: textParser.text.trimmingCharacters(in: .whitespacesAndNewlines),
                      truncated: textParser.truncated)
    }

    private struct Member {
        let name: String
        let flags: UInt16
        let method: UInt16
        let crc: UInt32
        let compressed: Int
        let expanded: Int
        let offset: Int
        let nameBytes: Data
        var payload: Range<Int> = 0..<0
        var end = 0
    }

    private struct Package {
        let data: Data
        let members: [String: Member]

        init(data: Data, limit: Int) throws {
            self.data = data
            guard data.count >= 22 else { throw Failure.malformed }
            let lower = max(0, data.count - 22 - 65_535)
            guard let end = stride(from: data.count - 22, through: lower, by: -1).first(where: {
                data.u32($0) == 0x06054B50 && $0 + 22 + Int(data.u16($0 + 20)) == data.count
            }) else { throw Failure.malformed }
            let count = Int(data.u16(end + 10))
            guard data.u16(end + 4) == 0, data.u16(end + 6) == 0,
                  data.u16(end + 8) == UInt16(count), count != 65_535,
                  data.u32(end + 12) != .max, data.u32(end + 16) != .max else {
                throw Failure.unsupported
            }
            guard count > 0, count <= maximumMembers else { throw Failure.tooLarge }
            let directory = Int(data.u32(end + 16))
            let directoryBytes = Int(data.u32(end + 12))
            guard directory <= end, directoryBytes == end - directory else { throw Failure.malformed }
            var cursor = directory
            var expandedTotal = 0
            var found: [String: Member] = [:]
            for _ in 0..<count {
                guard !Task.isCancelled else { throw Failure.cancelled }
                guard cursor <= end - 46, data.u32(cursor) == 0x02014B50 else { throw Failure.malformed }
                let flags = data.u16(cursor + 8)
                let method = data.u16(cursor + 10)
                try Self.validate(flags: flags, method: method, version: data.u16(cursor + 6))
                let nameLength = Int(data.u16(cursor + 28))
                let extraLength = Int(data.u16(cursor + 30))
                let commentLength = Int(data.u16(cursor + 32))
                let next = cursor + 46 + nameLength + extraLength + commentLength
                guard next <= end, nameLength > 0, nameLength <= 1_024 else { throw Failure.malformed }
                guard data.u16(cursor + 34) == 0 else { throw Failure.unsupported }
                let bytes = data.subdata(in: cursor + 46..<cursor + 46 + nameLength)
                guard let name = String(data: bytes, encoding: .utf8), Self.safe(name),
                      found[name] == nil else { throw Failure.malformed }
                // Without the UTF-8 flag, only unambiguous ASCII names are accepted.
                guard flags & 0x0800 != 0 || bytes.allSatisfy({ $0 < 0x80 }) else { throw Failure.unsupported }
                let mode = (data.u32(cursor + 38) >> 16) & 0xF000
                guard mode == 0 || mode == 0x8000 || mode == 0x4000 else { throw Failure.unsupported }
                try Self.validateExtra(data.subdata(in: cursor + 46 + nameLength..<cursor + 46 + nameLength + extraLength))
                let compressed = data.u32(cursor + 20), expanded = data.u32(cursor + 24)
                guard compressed != .max, expanded != .max, data.u32(cursor + 42) != .max else {
                    throw Failure.unsupported
                }
                guard compressed <= limit, expanded <= limit,
                      Int(expanded) <= limit - expandedTotal else { throw Failure.tooLarge }
                expandedTotal += Int(expanded)
                // The absolute expanded budget is primary; this also rejects extreme
                // claimed expansion before allocating even a bounded output buffer.
                guard Int(expanded) <= Int(compressed) * 1_000 + 65_536 else { throw Failure.tooLarge }
                if name.hasSuffix("/") && (expanded != 0 || compressed != 0) { throw Failure.malformed }
                found[name] = Member(name: name, flags: flags, method: method, crc: data.u32(cursor + 16),
                                     compressed: Int(compressed), expanded: Int(expanded),
                                     offset: Int(data.u32(cursor + 42)), nameBytes: bytes)
                cursor = next
            }
            guard cursor == end else { throw Failure.malformed }
            // Canonical contiguous local records prevent overlapping aliases, hidden
            // prefixes/trailers and inconsistent local/central package descriptions.
            var localCursor = 0
            for original in found.values.sorted(by: { $0.offset < $1.offset }) {
                var member = original
                let local = member.offset
                guard local == localCursor, local <= directory - 30,
                      data.u32(local) == 0x04034B50 else { throw Failure.malformed }
                try Self.validate(flags: data.u16(local + 6), method: data.u16(local + 8), version: data.u16(local + 4))
                guard data.u16(local + 6) == member.flags, data.u16(local + 8) == member.method else {
                    throw Failure.malformed
                }
                let nameLength = Int(data.u16(local + 26)), extraLength = Int(data.u16(local + 28))
                let start = local + 30 + nameLength + extraLength
                guard start <= directory, member.compressed <= directory - start,
                      nameLength == member.nameBytes.count,
                      data.subdata(in: local + 30..<local + 30 + nameLength) == member.nameBytes else {
                    throw Failure.malformed
                }
                try Self.validateExtra(data.subdata(in: local + 30 + nameLength..<start))
                member.payload = start..<start + member.compressed
                member.end = member.payload.upperBound
                if member.flags & 0x0008 != 0 {
                    guard [0, member.crc].contains(data.u32(local + 14)),
                          [0, UInt32(member.compressed)].contains(data.u32(local + 18)),
                          [0, UInt32(member.expanded)].contains(data.u32(local + 22)) else { throw Failure.malformed }
                    var descriptor = member.end
                    guard descriptor <= directory - 12 else { throw Failure.malformed }
                    if data.u32(descriptor) == 0x08074B50 { descriptor += 4 }
                    guard descriptor <= directory - 12,
                          data.u32(descriptor) == member.crc,
                          data.u32(descriptor + 4) == UInt32(member.compressed),
                          data.u32(descriptor + 8) == UInt32(member.expanded) else { throw Failure.malformed }
                    member.end = descriptor + 12
                } else {
                    guard data.u32(local + 14) == member.crc,
                          data.u32(local + 18) == UInt32(member.compressed),
                          data.u32(local + 22) == UInt32(member.expanded) else { throw Failure.malformed }
                }
                found[member.name] = member
                localCursor = member.end
            }
            guard localCursor == directory else { throw Failure.malformed }
            members = found
        }

        func read(_ name: String) throws -> Data {
            guard !Task.isCancelled else { throw Failure.cancelled }
            guard let member = members[name], !name.hasSuffix("/") else { throw Failure.malformed }
            let input = data.subdata(in: member.payload)
            let output: Data
            switch member.method {
            case 0:
                guard member.compressed == member.expanded else { throw Failure.malformed }
                output = input
            case 8:
                // One extra byte detects dishonest sizes, with no unbounded inflater
                // allocation. Raw ZIP deflate must consume the exact input stream.
                var buffer = Data(count: member.expanded + 1)
                var stream = z_stream()
                guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
                    throw Failure.unsupported
                }
                defer { inflateEnd(&stream) }
                let status = input.withUnsafeBytes { source in
                    buffer.withUnsafeMutableBytes { destination in
                        stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: Bytef.self).baseAddress)
                        stream.avail_in = uInt(input.count)
                        stream.next_out = destination.bindMemory(to: Bytef.self).baseAddress
                        stream.avail_out = uInt(destination.count)
                        return inflate(&stream, Z_FINISH)
                    }
                }
                guard status == Z_STREAM_END, stream.total_out == member.expanded,
                      stream.total_in == member.compressed else { throw Failure.malformed }
                output = buffer.prefix(member.expanded)
            default: throw Failure.unsupported
            }
            let checksum = output.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(output.count)) }
            guard UInt32(checksum) == member.crc else { throw Failure.malformed }
            return output
        }

        private static func validate(flags: UInt16, method: UInt16, version: UInt16) throws {
            guard flags & 0x0041 == 0 else { throw Failure.encrypted }
            guard (method == 0 || method == 8), version <= 20,
                  flags & ~UInt16(0x080E) == 0, method == 8 || flags & 0x0006 == 0 else { throw Failure.unsupported }
        }

        private static func safe(_ name: String) -> Bool {
            guard !name.hasPrefix("/"), !name.contains("\\"), !name.contains(":"),
                  !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return false }
            let components = name.split(separator: "/", omittingEmptySubsequences: false)
            return components.enumerated().allSatisfy { index, value in
                value != "." && value != ".." && (!value.isEmpty || index == components.count - 1 && name.hasSuffix("/"))
            }
        }

        private static func validateExtra(_ data: Data) throws {
            var cursor = 0
            while cursor < data.count {
                guard cursor <= data.count - 4 else { throw Failure.malformed }
                let identifier = data.u16(cursor), length = Int(data.u16(cursor + 2))
                guard length <= data.count - cursor - 4 else { throw Failure.malformed }
                guard identifier != 0x0001 && identifier != 0x9901 else { throw Failure.unsupported }
                cursor += 4 + length
            }
        }
    }

    private final class PartParser: NSObject, XMLParserDelegate {
        enum Mode { case contentTypes, document }
        let mode: Mode
        let maximumCharacters: Int
        var text = ""
        var truncated = false
        var hasMainContentType = false
        private var failure: Failure?
        private var depth = 0
        private var elements = 0
        private var bodyDepth: Int?
        private var textDepth: Int?
        private var ignoredDepth: Int?
        private var foundRoot = false
        private var foundBody = false
        private var characters = 0
        private let wordNamespaces: Set<String> = [
            "http://schemas.openxmlformats.org/wordprocessingml/2006/main",
            "http://purl.oclc.org/ooxml/wordprocessingml/main"
        ]
        private let typesNamespace = "http://schemas.openxmlformats.org/package/2006/content-types"

        init(mode: Mode, maximumCharacters: Int) {
            self.mode = mode
            self.maximumCharacters = maximumCharacters
        }

        func parse(_ data: Data) throws {
            // Entity expansion is not needed for Word text. Reject declarations in
            // both supported encodings before handing bytes to the XML parser.
            let document: String?
            if data.starts(with: [0xFF, 0xFE]) { document = String(data: data, encoding: .utf16LittleEndian) }
            else if data.starts(with: [0xFE, 0xFF]) { document = String(data: data, encoding: .utf16BigEndian) }
            else { document = String(data: data, encoding: .utf8) }
            guard let document, !document.contains("\0") else { throw Failure.unsupported }
            guard document.range(of: "<!DOCTYPE", options: .caseInsensitive) == nil,
                  document.range(of: "<!ENTITY", options: .caseInsensitive) == nil else { throw Failure.unsupported }
            let parser = XMLParser(data: data)
            parser.delegate = self
            parser.shouldProcessNamespaces = true
            parser.shouldResolveExternalEntities = false
            parser.externalEntityResolvingPolicy = .never
            parser.allowedExternalEntityURLs = []
            let succeeded = parser.parse()
            if let failure { throw failure }
            guard succeeded, foundRoot, mode == .contentTypes || foundBody else { throw Failure.malformed }
        }

        func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI namespace: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            guard check(parser) else { return }
            depth += 1
            elements += 1
            guard depth <= 128, elements <= 250_000 else { stop(parser, .tooLarge); return }
            if depth == 1 {
                foundRoot = mode == .contentTypes
                    ? element == "Types" && namespace == typesNamespace
                    : element == "document" && wordNamespaces.contains(namespace ?? "")
                if !foundRoot { stop(parser, .malformed) }
                return
            }
            if mode == .contentTypes {
                if depth == 2, namespace == typesNamespace, element == "Override",
                   attributes["PartName"] == "/word/document.xml" {
                    guard !hasMainContentType,
                          attributes["ContentType"] == "application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml" else {
                        stop(parser, .unsupported); return
                    }
                    hasMainContentType = true
                }
                return
            }
            guard wordNamespaces.contains(namespace ?? "") else { return }
            if depth == 2 && element == "body" {
                guard !foundBody else { stop(parser, .malformed); return }
                foundBody = true
                bodyDepth = depth
            }
            guard bodyDepth != nil else { return }
            if element == "del" || element == "moveFrom" { ignoredDepth = ignoredDepth ?? depth }
            guard ignoredDepth == nil else { return }
            if element == "t" { textDepth = depth }
            if element == "tab" { append("\t", separator: true) }
            if element == "br" || element == "cr" { append("\n", separator: true) }
        }

        func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI namespace: String?, qualifiedName: String?) {
            guard check(parser) else { return }
            if mode == .document, wordNamespaces.contains(namespace ?? ""), bodyDepth != nil, ignoredDepth == nil {
                if element == "p" { append("\n", separator: true) }
                if element == "tc" { trimTrailing(); append("\t", separator: true) }
                if element == "tr" { trimTrailing(includingTabs: true); append("\n", separator: true) }
            }
            if textDepth == depth { textDepth = nil }
            if ignoredDepth == depth { ignoredDepth = nil }
            if bodyDepth == depth { bodyDepth = nil }
            depth -= 1
        }

        func parser(_ parser: XMLParser, foundCharacters value: String) {
            guard check(parser), mode == .document, textDepth != nil, ignoredDepth == nil else { return }
            append(value)
        }

        func parser(_ parser: XMLParser, foundCDATA data: Data) {
            guard check(parser), mode == .document, textDepth != nil, ignoredDepth == nil else { return }
            guard let value = String(data: data, encoding: .utf8) else { stop(parser, .malformed); return }
            append(value)
        }

        func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) { stop(parser, .unsupported) }
        func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) { stop(parser, .unsupported) }
        func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? { stop(parser, .unsupported); return nil }

        private func check(_ parser: XMLParser) -> Bool {
            if Task.isCancelled { stop(parser, .cancelled) }
            return failure == nil
        }

        private func stop(_ parser: XMLParser, _ reason: Failure) {
            failure = failure ?? reason
            parser.abortParsing()
        }

        private func append(_ value: String, separator: Bool = false) {
            guard !truncated else { return }
            let available = maximumCharacters - characters
            let count = value.count
            if count > available {
                text += String(value.prefix(available))
                characters = maximumCharacters
                if !separator { truncated = true }
            } else {
                text += value
                characters += count
            }
        }

        private func trimTrailing(includingTabs: Bool = false) {
            guard !truncated else { return }
            while let last = text.last, last.isWhitespace, includingTabs || last != "\t" {
                text.removeLast(); characters -= 1
            }
        }
    }
}

private extension Data {
    func u16(_ offset: Int) -> UInt16 {
        UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    func u32(_ offset: Int) -> UInt32 {
        UInt32(u16(offset)) | UInt32(u16(offset + 2)) << 16
    }
}
