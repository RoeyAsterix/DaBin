import Foundation
import zlib

/// All Office packages and attack fixtures are synthetic local bytes. This
/// suite needs neither Word, a converter subprocess, a network nor user files.
@main
struct LocalDOCXTextExtractorTests {
    private static var checks = 0
    private static let wordNamespace = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    private static let contentTypes = """
    <?xml version="1.0" encoding="UTF-8"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
    </Types>
    """

    private struct Entry {
        let name: String
        let data: Data
        var method: UInt16 = 8
        var flags: UInt16 = 0
        var attributes: UInt32 = 0
        var extra = Data()
        var descriptor = false
    }

    private static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        if try !value() {
            throw NSError(domain: "LocalDOCXTextExtractorTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private static func failure(_ data: Data, _ expected: LocalDOCXTextExtractor.Failure,
                                _ message: String, limit: Int = LocalDOCXTextExtractor.maximumBytes) throws {
        do {
            _ = try LocalDOCXTextExtractor.extract(data: data, maximumBytes: limit)
            try expect(false, message + " (unexpected success)")
        } catch let actual as LocalDOCXTextExtractor.Failure {
            try expect(actual == expected, message + " (\(actual) instead of \(expected))")
        }
    }

    static func main() async throws {
        try usefulText()
        try characterLimit()
        try corruptPackages()
        try boundedPackages()
        try unsafeXML()
        try await cancellation()
        try privacyBoundary()
        #if !DABIN_DOCX_STANDALONE
        try await persistedLegacyIndexes()
        try await migrationAndManagedExtraction()
        #endif
        print("PASS: \(checks) local DOCX checks; paragraphs/tables/Unicode, strict OOXML, stored/deflated ZIP, descriptors, CRC/size/path guards, bounded inflation/XML, entity rejection, cancellation and no remote/converter loading.")
    }

    private static func document(_ body: String, namespace: String = wordNamespace) -> String {
        "<w:document xmlns:w=\"\(namespace)\"><w:body>\(body)</w:body></w:document>"
    }

    private static func package(_ xml: String, method: UInt16 = 8,
                                extras: [Entry] = [], descriptor: Bool = false,
                                types: String = contentTypes) throws -> Data {
        try zip([Entry(name: "[Content_Types].xml", data: Data(types.utf8), method: method),
                 Entry(name: "word/document.xml", data: Data(xml.utf8), method: method, descriptor: descriptor)] + extras)
    }

    private static func usefulText() throws {
        let xml = document("""
        <w:p><w:r><w:t>Résumé ירושלים &amp; </w:t></w:r><w:r><w:t>violet orbit</w:t></w:r></w:p>
        <w:p><w:hyperlink><w:r><w:t>Visible link</w:t></w:r></w:hyperlink><w:r><w:tab/><w:t>after tab</w:t><w:br/><w:t>next line</w:t></w:r></w:p>
        <w:tbl><w:tr><w:tc><w:p><w:r><w:t>Alpha cell</w:t></w:r></w:p></w:tc><w:tc><w:p/></w:tc><w:tc><w:p><w:r><w:t>Beta cell</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
        <w:p><w:r><w:instrText>FIELD SECRET</w:instrText></w:r><w:del><w:r><w:t>DELETED SECRET</w:t></w:r></w:del><w:moveFrom><w:r><w:t>OLD MOVE</w:t></w:r></w:moveFrom><w:r><w:t>Kept text</w:t></w:r></w:p>
        """)
        let ignored = [
            Entry(name: "word/_rels/document.xml.rels", data: Data("<Relationship Target='https://example.invalid/never-contact' TargetMode='External'/>".utf8)),
            Entry(name: "word/header1.xml", data: Data("HEADER SECRET".utf8)),
            Entry(name: "word/footnotes.xml", data: Data("FOOTNOTE SECRET".utf8)),
            Entry(name: "word/media/image.svg", data: Data("<!DOCTYPE svg SYSTEM 'file:///Fictional/never-read'>".utf8))
        ]
        let expected = "Résumé ירושלים & violet orbit\nVisible link\tafter tab\nnext line\nAlpha cell\t\tBeta cell\nKept text"
        for method: UInt16 in [0, 8] {
            let bytes = try package(xml, method: method, extras: ignored)
            let result = try LocalDOCXTextExtractor.extract(data: bytes)
            try expect(result.text == expected && !result.truncated, "Stored/deflated body preserves useful Unicode, paragraphs and table cells")
            try expect(!result.text.contains("SECRET") && !result.text.contains("never-contact"),
                       "Deleted/instruction/header/footnote/relationship/media content is never indexed")
            var prefixed = Data([0x99]); prefixed.append(bytes)
            try expect(try LocalDOCXTextExtractor.extract(data: prefixed.dropFirst()) == result,
                       "A non-zero-index Data slice is safe and equivalent")
        }
        let streamed = try package(document("<w:p><w:r><w:t>Streamed text</w:t></w:r></w:p>"), descriptor: true)
        try expect(try LocalDOCXTextExtractor.extract(data: streamed).text == "Streamed text",
                   "ZIP data descriptors used by streaming Office writers are validated and supported")
        let strict = try package(document("<w:p><w:r><w:t>Strict OOXML</w:t></w:r></w:p>",
                                          namespace: "http://purl.oclc.org/ooxml/wordprocessingml/main"))
        try expect(try LocalDOCXTextExtractor.extract(data: strict).text == "Strict OOXML", "Strict OOXML Word namespace is supported")
        let blank = try package(document("<w:p/>"))
        try expect(try LocalDOCXTextExtractor.extract(data: blank).text.isEmpty, "A valid empty document has a successful empty index")
        let cdata = try package(document("<w:p><w:r><w:t><![CDATA[Plain <local> words]]></w:t></w:r></w:p>"))
        try expect(try LocalDOCXTextExtractor.extract(data: cdata).text == "Plain <local> words", "CDATA inside Word text remains local literal text")
    }

    private static func characterLimit() throws {
        let value = String(repeating: "x", count: LocalDOCXTextExtractor.maximumCharacters + 1)
        let bytes = try package(document("<w:p><w:r><w:t>\(value)</w:t></w:r></w:p>"))
        let result = try LocalDOCXTextExtractor.extract(data: bytes)
        try expect(result.text.count == 300_000 && result.truncated,
                   "DOCX text retains the existing 300,000-character cap and discloses truncation")
        let unicode = try package(document("<w:p><w:r><w:t>🌕Résumé ירושלים violet</w:t></w:r></w:p>"))
        let bounded = try LocalDOCXTextExtractor.extract(data: unicode, maximumCharacters: 12)
        try expect(bounded.text == String("🌕Résumé ירושלים violet".prefix(12)) && bounded.truncated,
                   "Character limits preserve complete Unicode characters rather than split UTF-8 bytes")
        let malformedTail = try package("<w:document xmlns:w=\"\(wordNamespace)\"><w:body><w:p><w:r><w:t>\(value)</w:t></w:r></w:p><broken></w:body></w:document>")
        try failure(malformedTail, .malformed, "The whole XML still validates after the text cap; a malformed tail is not accepted")
    }

    private static func corruptPackages() throws {
        let valid = try package(document("<w:p><w:r><w:t>Fixture text</w:t></w:r></w:p>"))
        try failure(Data("not an Office package".utf8), .malformed, "Non-Office bytes are not searchable garbage")
        try failure(Data([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]), .encrypted,
                    "Encrypted/legacy Office containers are not interpreted as OOXML")
        try failure(valid.dropLast(12), .malformed, "Truncated ZIP end records fail safely")
        var trailing = valid; trailing.append(0)
        try failure(trailing, .malformed, "Unexplained trailing bytes are rejected")
        let main = try positions(in: valid, name: "word/document.xml")
        var badCRC = valid
        badCRC.put(UInt32(0xBAD0C0DE), at: main.central + 16); badCRC.put(UInt32(0xBAD0C0DE), at: main.local + 14)
        try failure(badCRC, .malformed, "A checksum mismatch in read document bytes is rejected")
        var dishonestSize = valid
        dishonestSize.put(UInt32(1), at: main.central + 24); dishonestSize.put(UInt32(1), at: main.local + 22)
        try failure(dishonestSize, .malformed, "Inflation cannot exceed a dishonest declared output buffer")
        var badLocalName = valid; badLocalName[main.local + 30] = 0x58
        try failure(badLocalName, .malformed, "Local and central names must agree exactly")
        var overlap = valid; overlap.put(UInt32(0), at: main.central + 42)
        try failure(overlap, .malformed, "Overlapping local entry offsets cannot alias package members")
        var encrypted = valid
        encrypted.put(UInt16(1), at: main.central + 8); encrypted.put(UInt16(1), at: main.local + 6)
        try failure(encrypted, .encrypted, "Encrypted ZIP flags fail clearly before any inflation")
        var unsupported = valid
        unsupported.put(UInt16(99), at: main.central + 10); unsupported.put(UInt16(99), at: main.local + 8)
        try failure(unsupported, .unsupported, "Unknown/AES compression is not passed to a fallback converter")
        var split = valid; split.put(UInt16(1), at: split.count - 22 + 4)
        try failure(split, .unsupported, "Multi-disk packages are unsupported")
        var zip64 = valid; zip64.put(UInt32.max, at: zip64.count - 22 + 16)
        try failure(zip64, .unsupported, "ZIP64 fields are rejected instead of truncated")
        var zip64Extra = Data(); zip64Extra.add(UInt16(1)); zip64Extra.add(UInt16(0))
        let withExtra = try package(document("<w:p/>"), extras: [Entry(name: "word/extra", data: Data(), method: 0, extra: zip64Extra)])
        try failure(withExtra, .unsupported, "ZIP64 extension records are not silently ignored")
        for name in ["../escape", "/absolute", "word/../escape", "word/./escape", "word//escape", "C:escape", "word\\escape", "word/\0escape"] {
            let unsafe = try package(document("<w:p/>"), extras: [Entry(name: name, data: Data())])
            try failure(unsafe, .malformed, "Unsafe package path \(name.debugDescription) is rejected without extracting a file")
        }
        let symlink = try package(document("<w:p/>"), extras: [Entry(name: "word/link", data: Data("target".utf8), attributes: 0xA000 << 16)])
        try failure(symlink, .unsupported, "Symlink package entries cannot redirect local reads")
        let duplicate = try package(document("<w:p/>"), extras: [Entry(name: "word/document.xml", data: Data("duplicate".utf8))])
        try failure(duplicate, .malformed, "Duplicate main parts cannot select ambiguous content")
        let missing = try zip([Entry(name: "[Content_Types].xml", data: Data(contentTypes.utf8))])
        try failure(missing, .malformed, "Missing main document parts are not presented as a blank document")
        let missingTypes = try zip([Entry(name: "word/document.xml", data: Data(document("<w:p/>").utf8))])
        try failure(missingTypes, .malformed, "A random XML ZIP needs a Word content-type declaration")
        let macros = try package(document("<w:p/>"), types: contentTypes.replacingOccurrences(of:
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml",
            with: "application/vnd.ms-word.document.macroEnabled.main+xml"))
        try failure(macros, .unsupported, "Macro-enabled packages renamed DOCX are unsupported")
        let wrongRoot = try package("<plain>not Word text</plain>")
        try failure(wrongRoot, .malformed, "Word body extraction requires the actual document root and namespace")
        let noBody = try package("<w:document xmlns:w=\"\(wordNamespace)\"/>")
        try failure(noBody, .malformed, "A missing Word body is not accepted as an empty document")
        let malformed = try package(document("<w:p><w:r><w:t>bad</w:r></w:p>"))
        try failure(malformed, .malformed, "Malformed XML does not publish a partial successful index")
        let streamed = try package(document("<w:p/>"), descriptor: true)
        let streamMain = try positions(in: streamed, name: "word/document.xml")
        var badDescriptor = streamed
        let descriptor = streamMain.payload + Int(streamed.read32(streamMain.central + 20))
        badDescriptor.put(UInt32(0xBAD0C0DE), at: descriptor + 4)
        try failure(badDescriptor, .malformed, "Streaming descriptors must match their central CRC and sizes")
    }

    private static func boundedPackages() throws {
        try failure(Data(count: LocalDOCXTextExtractor.maximumBytes + 1), .tooLarge, "Archive bytes retain the 12 MiB upper bound")
        let valid = try package(document("<w:p/>"))
        let main = try positions(in: valid, name: "word/document.xml")
        var expandedBomb = valid
        expandedBomb.put(UInt32(LocalDOCXTextExtractor.maximumBytes + 1), at: main.central + 24)
        try failure(expandedBomb, .tooLarge, "Claimed oversized inflation is refused before allocating output")
        var ratioBomb = valid
        ratioBomb.put(UInt32(1), at: main.central + 20); ratioBomb.put(UInt32(100_000), at: main.central + 24)
        try failure(ratioBomb, .tooLarge, "Extreme declared compression ratios are refused before reading payloads")
        let repeated = try package(document("<w:p><w:r><w:t>\(String(repeating: "a", count: 1_800))</w:t></w:r></w:p>"))
        try failure(repeated, .tooLarge, "Total expanded package bytes have the same bounded budget", limit: 1_024)
        var members = valid
        members.put(UInt16(2_049), at: members.count - 22 + 8); members.put(UInt16(2_049), at: members.count - 22 + 10)
        try failure(members, .tooLarge, "Entry counts are bounded before central-directory iteration")
        let deeplyNested = try package(document(String(repeating: "<w:x>", count: 130) + String(repeating: "</w:x>", count: 130)))
        try failure(deeplyNested, .tooLarge, "XML nesting is bounded")
    }

    private static func unsafeXML() throws {
        let external = "<!DOCTYPE w:document [<!ENTITY leak SYSTEM 'file:///Fictional/never-read'>]>" + document("<w:p><w:r><w:t>&leak;</w:t></w:r></w:p>")
        let remote = "<!DOCTYPE w:document SYSTEM 'https://example.invalid/never-contact'>" + document("<w:p/>")
        let internalEntity = "<!DOCTYPE w:document [<!ENTITY boom 'lots of repeated text'>]>" + document("<w:p><w:r><w:t>&boom;</w:t></w:r></w:p>")
        for xml in [external, remote, internalEntity] {
            try failure(try package(xml), .unsupported, "DTDs/entities cannot read disk, contact hosts or amplify text")
        }
        for (encoding, bom): (String.Encoding, [UInt8]) in [(.utf16LittleEndian, [0xFF, 0xFE]), (.utf16BigEndian, [0xFE, 0xFF])] {
            for (xml, rejected) in [(document("<w:p><w:r><w:t>Unicode 文書</w:t></w:r></w:p>"), false), (external, true)] {
                var bytes = Data(bom); bytes.append(xml.data(using: encoding)!)
                let zip = try self.zip([Entry(name: "[Content_Types].xml", data: Data(contentTypes.utf8)), Entry(name: "word/document.xml", data: bytes)])
                if rejected { try failure(zip, .unsupported, "UTF-16 cannot bypass the pre-parser DTD/entity rejection") }
                else { try expect(try LocalDOCXTextExtractor.extract(data: zip).text == "Unicode 文書", "BOM-prefixed UTF-16 Word parts are decoded locally") }
            }
            let withoutBOM = try self.zip([Entry(name: "[Content_Types].xml", data: Data(contentTypes.utf8)),
                Entry(name: "word/document.xml", data: ("<?xml version=\"1.0\" encoding=\"UTF-16\"?>" + external).data(using: encoding)!)])
            try failure(withoutBOM, .unsupported, "BOM-less UTF-16 cannot hide DTD tokens in NUL-padded UTF-8 before parser detection")
        }
        let entityTypes = "<!DOCTYPE Types SYSTEM 'https://example.invalid/types'>" + contentTypes
        try failure(try package(document("<w:p/>"), types: entityTypes), .unsupported, "Package content-type XML has the same entity restrictions")
    }

    private static func cancellation() async throws {
        let bytes = try package(document("<w:p/>"))
        let work = Task.detached { () -> Bool in
            try? await Task.sleep(for: .milliseconds(20))
            do { _ = try LocalDOCXTextExtractor.extract(data: bytes); return false }
            catch let failure as LocalDOCXTextExtractor.Failure { return failure == .cancelled }
            catch { return false }
        }
        work.cancel()
        let cancelled = await work.value
        try expect(cancelled, "Cancelled jobs exit before ZIP/XML work and publish no successful index")
    }

    private static func privacyBoundary() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let source = try String(contentsOf: root.appendingPathComponent("Sources/DaBin/LocalDOCXTextExtractor.swift"), encoding: .utf8)
        for forbidden in ["URLSession", "XMLParser(contentsOf:", "Process(", "NSAttributedString", "NSWorkspace", "Data(contentsOf:"] {
            try expect(!source.contains(forbidden), "DOCX extraction has no remote/file resolver or converter dependency: \(forbidden)")
        }
        try expect(source.contains("XMLParser(data: data)") && source.contains("externalEntityResolvingPolicy = .never")
                   && source.contains("shouldResolveExternalEntities = false") && source.contains("allowedExternalEntityURLs = []"),
                   "The XML parser is data-only with all external entity access explicitly disabled")
    }

    #if !DABIN_DOCX_STANDALONE
    @MainActor
    private static func persistedLegacyIndexes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinPersistedDOCXIndexFixture-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceRoot = root.appendingPathComponent("source")
        let store = try CaptureStore(root: sourceRoot)
        let word = try package(document("<w:p><w:r><w:t>New violet Word text</w:t></w:r></w:p>"))
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aK1cAAAAASUVORK5CYII=")!
        let fixtures: [(name: String, bytes: Data, state: String, text: String)] = [
            ("legacy-image.png", png, "ready", "Existing image recognition"),
            ("legacy-pdf.pdf", Data("Unrecognizable synthetic PDF original".utf8), "unavailable", ""),
            ("legacy-note.txt", Data("Original text document".utf8), "ready", "Existing text index"),
            ("legacy-ready.docx", word, "ready", "Prior Word index"),
            ("legacy-unavailable.docx", word, "unavailable", "")
        ]
        var saved: [Capture] = []
        var originals: [UUID: Data] = [:]
        var snapshots: [UUID: CaptureSnapshot] = [:]
        var archiveRecords: [UUID: Data] = [:]
        for fixture in fixtures {
            let capture = try await store.importData(fixture.bytes, filename: fixture.name)
            capture.contentIndexVersion = 1
            capture.contentIndexState = fixture.state
            capture.indexedText = fixture.text
            capture.contentIndexError = fixture.state == "unavailable" ? "Legacy local limitation" : nil
            capture.contentIndexCanRetry = false
            saved.append(capture)
            originals[capture.id] = try Data(contentsOf: store.managedURL(for: capture)!)
        }
        // Unlike an in-memory migration probe, this goes through repository
        // validation before persisting and then through load-time validation.
        try store.save(captures: saved)
        for capture in saved {
            snapshots[capture.id] = CaptureSnapshot(capture)
            archiveRecords[capture.id] = try Data(contentsOf: store.archiveURL(for: capture)!.appendingPathComponent("Capture.json"))
        }
        let reopened = try CaptureStore(root: sourceRoot)
        try expect(reopened.captures.count == saved.count,
                   "A real archive with persisted version 1 ready/unavailable indexes opens without an unsupported-schema error")
        let service = ContentIndexService(store: reopened)
        for capture in reopened.captures {
            let prior = snapshots[capture.id]!
            try expect(capture.contentIndexVersion == 1 && capture.contentIndexState == prior.contentIndexState
                       && capture.indexedText == prior.indexedText && capture.contentIndexError == prior.contentIndexError,
                       "Opening preserves each persisted legacy index version, terminal state, text and limitation")
            try expect(try Data(contentsOf: reopened.managedURL(for: capture)!) == originals[capture.id],
                       "Opening never changes the immutable legacy original bytes")
            try expect(try Data(contentsOf: reopened.archiveURL(for: capture)!.appendingPathComponent("Capture.json")) == archiveRecords[capture.id],
                       "Opening preserves the readable legacy archive record before explicit indexing")
            let isDOCX = capture.originalFilename?.hasSuffix(".docx") == true
            try expect(service.needsIndex(capture) == isDOCX,
                       "Only persisted legacy DOCX is queued for the new extractor; old image/PDF/text indexes stay usable")
        }

        let backup = root.appendingPathComponent("Legacy-v1.dabinbackup")
        try reopened.exportBackup(to: backup)
        let restoredRoot = root.appendingPathComponent("restored")
        let restoredStore = try CaptureStore(root: restoredRoot)
        let restoration = try restoredStore.restoreBackup(from: backup)
        let restored = try CaptureStore(root: restoredRoot)
        let restoredService = ContentIndexService(store: restored)
        try expect(restoration.addedCount == saved.count && restored.captures.count == saved.count,
                   "A version 1 legacy-index archive exports, restores and reopens through the real backup path")
        for capture in restored.captures {
            let prior = snapshots[capture.id]!
            try expect(capture.contentIndexVersion == 1 && capture.contentIndexState == prior.contentIndexState
                       && capture.indexedText == prior.indexedText && capture.contentIndexError == prior.contentIndexError,
                       "Backup restoration preserves legacy terminal versions, text and limitations")
            try expect(try Data(contentsOf: restored.managedURL(for: capture)!) == originals[capture.id],
                       "The legacy-index backup round trip preserves original document/image bytes")
            try expect(restoredService.needsIndex(capture) == (capture.originalFilename?.hasSuffix(".docx") == true),
                       "Restored old indexes retain the same targeted DOCX-only upgrade decision")
        }
        restoredService.shutdown()

        let protected = reopened.captures.first(where: { $0.originalFilename == "legacy-note.txt" })!
        for (state, version) in [("ready", 3), ("ready", 0), ("unavailable", 0), ("idle", 1), ("indexing", 1)] {
            protected.contentIndexState = state
            protected.contentIndexVersion = version
            var rejected = false
            do { try reopened.save(captures: [protected]) } catch { rejected = true }
            try expect(rejected, "Future/zero-terminal and nonzero-pending index versions remain invalid: \(state) v\(version)")
            protected.contentIndexState = "ready"
            protected.contentIndexVersion = 1
            let preserved = try CaptureStore(root: sourceRoot)
            let record = preserved.captures.first(where: { $0.id == protected.id })!
            try expect(record.contentIndexState == "ready" && record.contentIndexVersion == 1
                       && record.indexedText == "Existing text index",
                       "A rejected index save leaves the durable legacy record intact")
            try expect(try Data(contentsOf: preserved.managedURL(for: record)!) == originals[record.id]
                       && Data(contentsOf: preserved.archiveURL(for: record)!.appendingPathComponent("Capture.json")) == archiveRecords[record.id],
                       "A rejected index save leaves original and readable archive bytes untouched")
        }

        service.process(reopened.captures)
        let deadline = Date().addingTimeInterval(8)
        while service.isBusy && Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        let upgraded = reopened.captures.filter { $0.originalFilename?.hasSuffix(".docx") == true }
        try expect(upgraded.count == 2 && upgraded.allSatisfy {
            $0.contentIndexState == "ready" && $0.contentIndexVersion == 2 && $0.indexedText == "New violet Word text"
        }, "Both persisted ready and unavailable version 1 DOCX indexes upgrade successfully once")
        for capture in reopened.captures {
            try expect(try Data(contentsOf: reopened.managedURL(for: capture)!) == originals[capture.id],
                       "Migrating the DOCX text cache preserves every saved original")
            if capture.originalFilename?.hasSuffix(".docx") != true {
                try expect(capture.contentIndexVersion == 1 && capture.indexedText == snapshots[capture.id]?.indexedText,
                           "DOCX migration does not touch a persisted unchanged image/PDF/text cache")
            }
        }
        service.process(reopened.captures)
        try expect(!service.isBusy && reopened.captures.allSatisfy { !service.needsIndex($0) },
                   "Reprocessing the reopened archive schedules neither another DOCX job nor unwanted legacy OCR")
        service.shutdown()
    }

    @MainActor
    private static func migrationAndManagedExtraction() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinDOCXIndexFixture-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root)
        let bytes = try package(document("<w:p><w:r><w:t>Violet document project</w:t></w:r></w:p>"))
        let capture = try await store.importData(bytes, filename: "Fixture.DOCX")
        let image = Capture(kind: .image, title: "Existing image")
        image.contentIndexVersion = 1; image.contentIndexState = "ready"
        let pdf = Capture(kind: .pdf, title: "Existing PDF")
        pdf.contentIndexVersion = 1; pdf.contentIndexState = "unavailable"
        let text = Capture(kind: .document, originalFilename: "fixture.txt", title: "Existing text")
        text.contentIndexVersion = 1; text.contentIndexState = "ready"
        let service = ContentIndexService(store: store)
        try expect(ContentIndexService.currentVersion == 2 && ContentIndexService.requiredVersion(for: capture) == 2,
                   "DOCX extraction has a new targeted index version, including uppercase file extensions")
        for old in [image, pdf, text] {
            try expect(ContentIndexService.requiredVersion(for: old) == 1 && !service.needsIndex(old),
                       "Version 1 terminal image/PDF/plain-text indexes do not restart unchanged work")
        }
        capture.contentIndexVersion = 1; capture.contentIndexState = "unavailable"
        capture.contentIndexCanRetry = false
        try expect(service.needsIndex(capture), "Previously unsupported version 1 DOCX is retried once despite its old permanent limitation")
        let managed = store.managedURL(for: capture)!
        let before = try Data(contentsOf: managed)
        service.process([capture])
        let deadline = Date().addingTimeInterval(8)
        while service.isBusy && Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try expect(capture.kind == .document && capture.contentIndexState == "ready"
                   && capture.indexedText == "Violet document project" && capture.contentIndexVersion == 2,
                   "Real managed DOCX imports reach local searchable text through the production service")
        try expect(!service.needsIndex(capture) && !capture.contentIndexCanRetry,
                   "A completed version 2 DOCX index does not repeat on launch")
        try expect(try Data(contentsOf: managed) == before, "DOCX indexing never changes its owned original bytes")
        let bad = try await store.importData(Data("not a DOCX package".utf8), filename: "bad.docx")
        bad.contentIndexVersion = 1; bad.contentIndexState = "unavailable"
        service.process([bad])
        let failureDeadline = Date().addingTimeInterval(8)
        while service.isBusy && Date() < failureDeadline { try await Task.sleep(for: .milliseconds(5)) }
        try expect(bad.contentIndexState == "unavailable" && bad.contentIndexVersion == 2
                   && !bad.contentIndexCanRetry && !service.needsIndex(bad)
                   && bad.contentIndexError?.contains("malformed") == true,
                   "A malformed DOCX fails honestly once instead of entering a reindex loop")
        service.shutdown()
    }
    #endif

    private static func positions(in data: Data, name: String) throws -> (local: Int, central: Int, payload: Int) {
        var cursor = Int(data.read32(data.count - 22 + 16))
        for _ in 0..<Int(data.read16(data.count - 22 + 10)) {
            let count = Int(data.read16(cursor + 28))
            let entryName = String(data: data.subdata(in: cursor + 46..<cursor + 46 + count), encoding: .utf8)
            if entryName == name {
                let local = Int(data.read32(cursor + 42))
                return (local, cursor, local + 30 + Int(data.read16(local + 26)) + Int(data.read16(local + 28)))
            }
            cursor += 46 + count + Int(data.read16(cursor + 30)) + Int(data.read16(cursor + 32))
        }
        throw NSError(domain: "LocalDOCXTextExtractorTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing synthetic entry"])
    }

    private static func zip(_ entries: [Entry]) throws -> Data {
        var result = Data(), directory = Data()
        for entry in entries {
            let name = Data(entry.name.utf8), payload = entry.method == 8 ? try deflate(entry.data) : entry.data
            let crc = UInt32(entry.data.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(entry.data.count)) })
            let offset = UInt32(result.count), flags = entry.flags | (entry.descriptor ? 8 : 0)
            result.add(UInt32(0x04034B50)); result.add(UInt16(20)); result.add(flags); result.add(entry.method)
            result.add(UInt16(0)); result.add(UInt16(0)); result.add(entry.descriptor ? UInt32(0) : crc)
            result.add(entry.descriptor ? UInt32(0) : UInt32(payload.count)); result.add(entry.descriptor ? UInt32(0) : UInt32(entry.data.count))
            result.add(UInt16(name.count)); result.add(UInt16(entry.extra.count)); result.append(name); result.append(entry.extra); result.append(payload)
            if entry.descriptor {
                result.add(UInt32(0x08074B50)); result.add(crc); result.add(UInt32(payload.count)); result.add(UInt32(entry.data.count))
            }
            directory.add(UInt32(0x02014B50)); directory.add(UInt16(0x0314)); directory.add(UInt16(20))
            directory.add(flags); directory.add(entry.method); directory.add(UInt16(0)); directory.add(UInt16(0)); directory.add(crc)
            directory.add(UInt32(payload.count)); directory.add(UInt32(entry.data.count)); directory.add(UInt16(name.count))
            directory.add(UInt16(entry.extra.count)); directory.add(UInt16(0)); directory.add(UInt16(0)); directory.add(UInt16(0))
            directory.add(entry.attributes); directory.add(offset); directory.append(name); directory.append(entry.extra)
        }
        let offset = UInt32(result.count)
        result.append(directory); result.add(UInt32(0x06054B50)); result.add(UInt16(0)); result.add(UInt16(0))
        result.add(UInt16(entries.count)); result.add(UInt16(entries.count)); result.add(UInt32(directory.count)); result.add(offset); result.add(UInt16(0))
        return result
    }

    private static func deflate(_ input: Data) throws -> Data {
        var stream = z_stream()
        guard deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY,
                           ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw NSError(domain: "LocalDOCXTextExtractorTests", code: 3)
        }
        defer { deflateEnd(&stream) }
        var output = Data(count: Int(deflateBound(&stream, uLong(input.count))))
        let status = input.withUnsafeBytes { source in
            output.withUnsafeMutableBytes { destination in
                stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: Bytef.self).baseAddress)
                stream.avail_in = uInt(input.count)
                stream.next_out = destination.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(destination.count)
                return zlib.deflate(&stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END else { throw NSError(domain: "LocalDOCXTextExtractorTests", code: 4) }
        return output.prefix(Int(stream.total_out))
    }
}

private extension Data {
    mutating func add(_ value: UInt16) { append(UInt8(truncatingIfNeeded: value)); append(UInt8(truncatingIfNeeded: value >> 8)) }
    mutating func add(_ value: UInt32) { add(UInt16(truncatingIfNeeded: value)); add(UInt16(truncatingIfNeeded: value >> 16)) }
    mutating func put(_ value: UInt16, at offset: Int) { self[offset] = UInt8(truncatingIfNeeded: value); self[offset + 1] = UInt8(truncatingIfNeeded: value >> 8) }
    mutating func put(_ value: UInt32, at offset: Int) { put(UInt16(truncatingIfNeeded: value), at: offset); put(UInt16(truncatingIfNeeded: value >> 16), at: offset + 2) }
    func read16(_ offset: Int) -> UInt16 { UInt16(self[offset]) | UInt16(self[offset + 1]) << 8 }
    func read32(_ offset: Int) -> UInt32 { UInt32(read16(offset)) | UInt32(read16(offset + 2)) << 16 }
}
