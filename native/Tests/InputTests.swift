import AppKit
import Foundation

private enum FixtureError: Error { case unavailable }

private final class LazyTextFixture: NSObject, NSPasteboardItemDataProvider {
    private(set) var requests = 0
    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        requests += 1
        item.setString("Lazy selected text", forType: type)
    }
}

private final class PromiseFixture: InputFilePromise {
    private(set) var fileNames: [String] = []
    private let names: [String]
    private var reader: ((URL, Error?) -> Void)?
    private var queue: OperationQueue?
    private(set) var destination: URL?
    init(_ names: [String]) { self.names = names }
    func receive(at destination: URL, operationQueue: OperationQueue, reader: @escaping (URL, Error?) -> Void) {
        self.destination = destination
        self.queue = operationQueue
        self.reader = reader
        // Match native timing: names are unavailable until receive is invoked.
        fileNames = names
    }
    func deliver(_ index: Int, error: Error? = nil) {
        guard let destination, let reader, let queue else { fatalError("Fixture was not started") }
        let name = names[index]
        queue.addOperation {
            let url = destination.appendingPathComponent(name)
            if let error { reader(url, error); return }
            do {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                try Data("promise-\(index)".utf8).write(to: url)
                reader(url, nil)
            } catch { reader(url, error) }
        }
    }
}

@MainActor private final class InputRecorder {
    var results: [([Capture], [String])] = []
    var busy: [Bool] = []
    var durableAtSuccess = true
    init(_ input: InputService) {
        input.onBusy = { [weak self] in self?.busy.append($0) }
        input.onResult = { [weak self, weak input] captures, failures in
            guard let self, let input else { return }
            for capture in captures where capture.attachmentRelativePath != nil {
                if let url = input.store.managedURL(for: capture) {
                    self.durableAtSuccess = self.durableAtSuccess && FileManager.default.fileExists(atPath: url.path)
                } else { self.durableAtSuccess = false }
            }
            self.results.append((captures, failures))
        }
    }
}

@main struct InputTests {
    @MainActor static var checks = 0
    @MainActor static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        if try !value() { throw NSError(domain: "DaBinInputTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    @MainActor static func wait(_ message: String, until condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try expect(condition(), message)
    }
    @MainActor static func item(_ text: String, type: NSPasteboard.PasteboardType = .string) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(text, forType: type)
        return item
    }
    @MainActor static func board(_ items: [NSPasteboardItem]) throws -> NSPasteboard {
        // Never access NSPasteboard.general: fixtures get private, randomly named boards.
        let board = NSPasteboard(name: .init("DaBin.InputTests.\(UUID().uuidString)"))
        board.clearContents()
        if !items.isEmpty { try expect(board.writeObjects(items), "Named fixture pasteboard write") }
        return board
    }
    @MainActor static func addWebSource(_ url: String, to item: NSPasteboardItem, type: String = "com.apple.webarchive") throws {
        let archive: [String: Any] = ["WebMainResource": ["WebResourceURL": url, "WebResourceData": Data("excerpt".utf8), "WebResourceMIMEType": "text/html"]]
        item.setData(try PropertyListSerialization.data(fromPropertyList: archive, format: .binary, options: 0), forType: .init(type))
    }
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinInputTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let stamp = ISO8601DateFormatter().date(from: "2026-01-01T00:30:00Z")!
        let zone = TimeZone(identifier: "America/Los_Angeles")!

        // Hover acceptance must not ask the drag source to materialize content.
        do {
            let provider = LazyTextFixture()
            let lazy = NSPasteboardItem()
            try expect(lazy.setDataProvider(provider, forTypes: [.string]), "Lazy text advertises its representation")
            let pb = try board([lazy]); defer { pb.releaseGlobally() }
            try expect(InputService.canReceive(pb), "Advertised selected text is accepted")
            try expect(provider.requests == 0, "Drag hover does not read lazy source content")
            let unknown = try board([item("opaque", type: .init("com.dabin.test.unsupported"))]); defer { unknown.releaseGlobally() }
            try expect(!InputService.canReceive(unknown), "Unsupported advertised data is rejected")
            let empty = try board([]); defer { empty.releaseGlobally() }
            try expect(!InputService.canReceive(empty), "Empty drag is rejected")
            let generic = try board([item("bytes", type: .init("public.data"))]); defer { generic.releaseGlobally() }
            try expect(!InputService.canReceive(generic), "Unspecified bytes without a filename extension are rejected")
            for type in [NSPasteboard.PasteboardType.fileURL, .URL, .rtf, .html, .png, .tiff, .pdf, .init("public.jpeg")] {
                let advertised = try board([item("fixture", type: type)]); defer { advertised.releaseGlobally() }
                try expect(InputService.canReceive(advertised), "Supported drag type accepted: \(type.rawValue)")
            }
            if let type = NSFilePromiseReceiver.readableDraggedTypes.first {
                let promised = try board([item("fixture", type: .init(type))]); defer { promised.releaseGlobally() }
                try expect(InputService.canReceive(promised), "Advertised file promises accepted without starting transfer")
            }
        }

        // Finder exposes each selected file as a native NSURL pasteboard writer.
        do {
            let store = try CaptureStore(root: root.appendingPathComponent("finder-files"))
            let input = InputService(store: store); let log = InputRecorder(input)
            let urls = [root.appendingPathComponent("First selected file.txt"), root.appendingPathComponent("Second selected file.pdf")]
            for (index, url) in urls.enumerated() { try Data("finder-original-\(index)".utf8).write(to: url) }
            let pb = try board([]); defer { pb.releaseGlobally() }
            try expect(pb.writeObjects(urls.map { $0 as NSURL }), "Native NSURL file writers publish the Finder transfer shape")
            try expect(InputService.canReceive(pb), "Finder file batch accepted")
            input.receive(pb, at: stamp, timeZone: zone)
            try await wait("Finder file batch completes") { log.results.count == 1 }
            let captures = log.results[0].0
            try expect(captures.count == 2 && log.results[0].1.isEmpty, "Each selected native file becomes one capture")
            let cards = CaptureCardGroup.cards(from: captures)
            try expect(cards.count == 1 && cards[0].isImportedBatch && cards[0].captures.count == 2,
                       "Files from one Finder drop share one caption card")
            try expect(Set(captures.compactMap(\.sourceFilePath)) == Set(urls.map(\.path)), "Native file transfers retain both original paths")
            for capture in captures {
                let original = URL(fileURLWithPath: capture.sourceFilePath!)
                try expect(try Data(contentsOf: store.managedURL(for: capture)!) == Data(contentsOf: original), "Native file transfer preserves original bytes")
                try expect(capture.capturedAt == stamp && capture.captureDay == "2025-12-31", "All selected files use the same drop date")
            }
            let reopened = try CaptureStore(root: root.appendingPathComponent("finder-files"))
            let reopenedCards = CaptureCardGroup.cards(from: reopened.captures)
            try expect(reopenedCards.count == 1 && reopenedCards[0].captures.count == 2,
                       "The shared caption card survives reopening the local archive")
            try expect(log.durableAtSuccess && log.busy == [true, false], "Finder batch is durable before finishing once")
        }

        do {
            let store = try CaptureStore(root: root.appendingPathComponent("rich-text"))
            let input = InputService(store: store); let log = InputRecorder(input)
            let rich = NSPasteboardItem()
            rich.setData(Data(#"{\rtf1\ansi Rich \b selected\b0  text}"#.utf8), forType: .rtf)
            let alternatives = item("Selected browser paragraph")
            alternatives.setString("<p>Selected <b>browser</b> paragraph</p>", forType: .html)
            let pb = try board([rich, alternatives]); defer { pb.releaseGlobally() }
            input.receive(pb)
            try await wait("Rich selected text completes") { log.results.count == 1 }
            let captures = log.results[0].0
            try expect(captures.count == 2 && log.results[0].1.isEmpty, "Rich selections capture once per item")
            try expect(captures[0].kind == .text && captures[0].originalText == "Rich selected text", "RTF-only selection becomes readable text")
            try expect(captures[1].kind == .text && captures[1].originalText == "Selected browser paragraph", "Browser plain text takes precedence over HTML alternative")
        }

        do {
            let store = try CaptureStore(root: root.appendingPathComponent("html-original"))
            let input = InputService(store: store); let log = InputRecorder(input)
            let html = Data("<p>Offline original</p><img src='https://example.invalid/image'>".utf8)
            let value = NSPasteboardItem(); value.setData(html, forType: .html)
            let pb = try board([value]); defer { pb.releaseGlobally() }
            input.receive(pb)
            try await wait("HTML-only original completes") { log.results.count == 1 }
            try expect(log.results[0].0.count == 1 && log.results[0].1.isEmpty, "HTML-only representation is kept as a local original")
            try expect(try Data(contentsOf: store.managedURL(for: log.results[0].0[0])!) == html, "HTML original bytes retained without parsing or fetching embedded content")
        }

        // URL and text are alternate representations of one item, not two captures.
        do {
            let store = try CaptureStore(root: root.appendingPathComponent("alternatives"))
            let input = InputService(store: store)
            let log = InputRecorder(input)
            let value = item("Descriptive alternate label")
            value.setString("https://example.test/one", forType: .URL)
            let pb = try board([value]); defer { pb.releaseGlobally() }
            input.receive(pb, at: stamp, timeZone: zone)
            try await wait("Alternative batch completes") { log.results.count == 1 }
            try expect(log.results[0].0.count == 1 && log.results[0].1.isEmpty, "One representation becomes one capture")
            let capture = log.results[0].0[0]
            try expect(capture.kind == .link && capture.originalURL == "https://example.test/one", "URL preferred to alternate text")
            try expect(capture.sourceURL == "https://example.test/one" && capture.sourceFilePath == nil, "Link has its own source URL")
            try expect(capture.capturedAt == stamp && capture.captureDay == "2025-12-31" && capture.captureTimeZoneID == zone.identifier, "Receipt stamp and local day retained")
            try expect(log.busy == [true, false], "One busy lifecycle for one batch")
        }
        do {
            let store = try CaptureStore(root: root.appendingPathComponent("distinct-items"))
            let input = InputService(store: store); let log = InputRecorder(input)
            let pb = try board([item("same text"), item("same text")]); defer { pb.releaseGlobally() }
            input.receive(pb)
            try await wait("Distinct identical items complete") { log.results.count == 1 }
            try expect(log.results[0].0.count == 2, "Equal text in distinct items remains two captures")
            try expect(Set(log.results[0].0.map(\.id)).count == 2, "Distinct items have separate identifiers")
            try expect(log.results[0].0.allSatisfy { $0.sourceFilePath == nil && $0.sourceURL == nil }, "Plain clipboard text does not fabricate a source")
        }
        do {
            let store = try CaptureStore(root: root.appendingPathComponent("web-source"))
            let input = InputService(store: store); let log = InputRecorder(input)
            let web = item("A quoted paragraph from a page")
            try addWebSource("https://example.test/source-page", to: web)
            let file = item("An excerpt from a local document")
            try addWebSource("file:///Users/example/Documents/Source%20Document.html", to: file)
            let unsafe = item("Text with an unsupported source")
            try addWebSource("javascript:alert(1)", to: unsafe)
            let malformed = item("Text survives malformed metadata")
            malformed.setData(Data("not a property list".utf8), forType: .init("com.apple.webarchive"))
            let plainPath = item("/Users/example/Documents/not-provenance.txt")
            let pb = try board([web, file, unsafe, malformed, plainPath]); defer { pb.releaseGlobally() }
            input.receive(pb)
            try await wait("Source metadata capture completes") { log.results.count == 1 }
            let values = log.results[0].0
            try expect(values.count == 5 && log.results[0].1.isEmpty, "Source metadata never creates extra captures or blocks text")
            try expect(values[0].kind == .text && values[0].sourceURL == "https://example.test/source-page", "Web archive main resource is source of copied text")
            try expect(values[1].sourceFilePath == "/Users/example/Documents/Source Document.html" && values[1].sourceURL == nil, "Explicit local source URI is decoded as original path")
            try expect(values[2...].allSatisfy { $0.sourceFilePath == nil && $0.sourceURL == nil }, "Unsafe, malformed and plain text paths remain unknown")
        }
        do {
            let store = try CaptureStore(root: root.appendingPathComponent("url-lines"))
            let input = InputService(store: store); let log = InputRecorder(input)
            let pb = try board([item("https://first.example/a\n\nhttps://second.example/b")]); defer { pb.releaseGlobally() }
            input.receive(pb, at: stamp, timeZone: zone)
            try await wait("URL-only lines complete") { log.results.count == 1 }
            try expect(log.results[0].0.count == 2 && log.results[0].0.allSatisfy { $0.kind == .link && $0.capturedAt == stamp }, "URL lines split with one receipt stamp")
        }
        do {
            let store = try CaptureStore(root: root.appendingPathComponent("image"))
            let input = InputService(store: store); let log = InputRecorder(input)
            let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j8ocAAAAASUVORK5CYII=")!
            let value = item("Image alternate text")
            value.setData(png, forType: .png)
            value.setString("https://example.test/image", forType: .URL)
            let pb = try board([value]); defer { pb.releaseGlobally() }
            input.receive(pb)
            try await wait("Image completes") { log.results.count == 1 }
            try expect(log.results[0].0.count == 1 && log.results[0].0[0].kind == .image, "Image preferred to URL/text alternatives")
            try expect(try Data(contentsOf: store.managedURL(for: log.results[0].0[0])!) == png, "Original image bytes retained")
            try expect(log.durableAtSuccess, "Image original is durable before success callback")
        }
        do {
            let store = try CaptureStore(root: root.appendingPathComponent("partial"))
            let input = InputService(store: store); let log = InputRecorder(input)
            let source = root.appendingPathComponent("valid.pdf")
            try Data("a file fixture".utf8).write(to: source)
            let missing = root.appendingPathComponent("does-not-exist.pdf")
            let pb = try board([item(source.absoluteString, type: .fileURL), item(missing.absoluteString, type: .fileURL)]); defer { pb.releaseGlobally() }
            input.receive(pb)
            try await wait("Mixed file batch completes") { log.results.count == 1 }
            try expect(log.results[0].0.count == 1 && log.results[0].1.count == 1, "Partial result aggregates successful and failed files")
            try expect(log.results[0].0[0].sourceFilePath == source.standardizedFileURL.path, "Copied document retains source path from file transfer")
            try expect(log.durableAtSuccess && log.busy == [true, false], "Partial success has durable original and complete busy lifecycle")
        }
        do {
            let store = try CaptureStore(root: root.appendingPathComponent("empty"))
            let input = InputService(store: store); let log = InputRecorder(input)
            let pb = try board([]); defer { pb.releaseGlobally() }
            input.receive(pb)
            try await wait("Empty pasteboard reports failure") { log.results.count == 1 }
            try expect(log.results[0].0.isEmpty && log.results[0].1.count == 1 && !input.isBusy, "Empty input is honest and terminates")
        }
        do {
            let store = try CaptureStore(root: root.appendingPathComponent("promises"))
            let promise = PromiseFixture(["first.pdf", "second.pdf"])
            let input = InputService(store: store, stagingRoot: root, promiseReader: { _ in [promise] })
            let log = InputRecorder(input)
            let pb = try board([item("An ordinary note in the same receive")]); defer { pb.releaseGlobally() }
            input.receive(pb, at: stamp, timeZone: zone)
            promise.deliver(0)
            try await wait("First promised original imported") { store.captures.count == 2 }
            try expect(log.results.isEmpty && input.isBusy, "No early result or busy release after first of two promises")
            promise.deliver(1)
            try await wait("Whole promise batch completes") { log.results.count == 1 }
            try expect(log.results[0].0.count == 3 && log.results[0].1.isEmpty, "Ordinary and promised items aggregate once")
            let cards = CaptureCardGroup.cards(from: log.results[0].0)
            try expect(cards.count == 2 && cards.contains(where: { $0.isImportedBatch && $0.captures.count == 2 }),
                       "Multiple promised files share a caption card while unrelated text stays separate")
            try expect(log.results[0].0.allSatisfy { $0.capturedAt == stamp && $0.captureDay == "2025-12-31" }, "All promise callbacks retain drop stamp")
            try expect(log.busy == [true, false] && log.durableAtSuccess, "Busy held until every durable promise import finishes")
            try expect(!FileManager.default.fileExists(atPath: promise.destination!.path), "Whole promise staging destination removed")
            for capture in log.results[0].0 where capture.attachmentRelativePath != nil {
                try expect(FileManager.default.fileExists(atPath: store.managedURL(for: capture)!.path), "Managed original survives staging cleanup")
                try expect(capture.sourceFilePath == nil && capture.sourceURL == nil, "Promise temporary delivery path is never shown as original source")
            }
        }
        do {
            let store = try CaptureStore(root: root.appendingPathComponent("promise-partial"))
            let promise = PromiseFixture(["good.pdf", "bad.pdf"])
            let input = InputService(store: store, stagingRoot: root, promiseReader: { _ in [promise] })
            let log = InputRecorder(input)
            let pb = try board([]); defer { pb.releaseGlobally() }
            input.receive(pb)
            promise.deliver(0)
            promise.deliver(1, error: FixtureError.unavailable)
            try await wait("Failed promise batch completes") { log.results.count == 1 }
            try expect(log.results[0].0.count == 1 && log.results[0].1.count == 1, "Promise success/failure aggregate into one result")
            try expect(!FileManager.default.fileExists(atPath: promise.destination!.path), "Failed promise staging removed after all callbacks")
        }
        do {
            let store = try CaptureStore(root: root.appendingPathComponent("promise-late"))
            let promise = PromiseFixture(["on-time.pdf", "late.pdf"])
            let input = InputService(store: store, promiseTimeout: 0.12, stagingRoot: root, promiseReader: { _ in [promise] })
            let log = InputRecorder(input)
            let pb = try board([]); defer { pb.releaseGlobally() }
            input.receive(pb, at: stamp, timeZone: zone)
            promise.deliver(0)
            try await wait("Timeout reports outstanding promise once") { log.results.count == 1 }
            try expect(log.results[0].0.count == 1 && log.results[0].1.count == 1 && !input.isBusy, "Timeout preserves earlier success and reports missing promise")
            try expect(FileManager.default.fileExists(atPath: promise.destination!.path), "Timeout does not delete destination while provider may still write")
            let firstID = log.results[0].0[0].id
            promise.deliver(1)
            try await wait("Late callback completes") { log.results.count == 2 }
            try expect(log.results[1].0.count == 1 && log.results[1].1.isEmpty && log.results[1].0[0].id != firstID, "Late callback reports only newly captured item")
            try expect(log.results[1].0[0].capturedAt == stamp && log.results[1].0[0].captureDay == "2025-12-31", "Late callback retains original immutable receipt")
            try expect(log.busy == [true, false, true, false], "Late callback has safe independent busy lifecycle")
            try expect(!FileManager.default.fileExists(atPath: promise.destination!.path) && log.durableAtSuccess, "Late completion cleans all staging after durable import")
            try await Task.sleep(for: .milliseconds(160))
            try expect(log.results.count == 2, "No duplicate timeout or success callback")
        }
        print("PASS: \(checks) input lifecycle checks (private named pasteboards; general clipboard untouched)")
    }
}
