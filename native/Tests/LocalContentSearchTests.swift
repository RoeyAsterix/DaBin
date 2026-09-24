import AppKit
import CoreText
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// A notification double keeps removal integration away from the user's
/// notification center and permission state.
@MainActor
private final class ContentIndexReminderClient: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .allowed }
    func requestAuthorization() async throws -> Bool {
        fatalError("Content-index QA must never request notification permission")
    }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws {}
    func removePending(_ identifiers: [String]) {}
    func removeDelivered(_ identifiers: [String]) {}
}

/// A cancellation-aware extractor lets the suite hold native work at exact
/// lifecycle boundaries. Production cancellation has to await this work before
/// removing a capture's managed original.
private actor GatedContentExtractor {
    struct Call: Sendable {
        let url: URL
        let kind: CaptureKind
        let filename: String?
    }

    private struct Pending {
        let token: UUID
        let call: Call
        let continuation: CheckedContinuation<ContentIndexExtraction, Never>
    }

    private var calls: [Call] = []
    private var pending: [Pending] = []
    private var active = 0
    private(set) var maximumActive = 0

    func extract(url: URL, kind: CaptureKind, filename: String?) async -> ContentIndexExtraction {
        let token = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: .unavailable("Fixture cancelled."))
                    return
                }
                let call = Call(url: url, kind: kind, filename: filename)
                calls.append(call)
                pending.append(Pending(token: token, call: call, continuation: continuation))
                active += 1
                maximumActive = max(maximumActive, active)
            }
        } onCancel: {
            Task { await self.cancel(token) }
        }
    }

    func callCount() -> Int { calls.count }
    func pendingCount() -> Int { pending.count }
    func recordedCalls() -> [Call] { calls }

    @discardableResult
    func releaseFirst(_ result: ContentIndexExtraction) -> String? {
        guard !pending.isEmpty else { return nil }
        let item = pending.removeFirst()
        active -= 1
        item.continuation.resume(returning: result)
        return item.call.filename
    }

    private func cancel(_ token: UUID) {
        guard let index = pending.firstIndex(where: { $0.token == token }) else { return }
        let item = pending.remove(at: index)
        active -= 1
        item.continuation.resume(returning: .unavailable("Fixture cancelled."))
    }
}

private actor ScriptedContentExtractor {
    private var results: [ContentIndexExtraction]
    private(set) var calls = 0

    init(_ results: [ContentIndexExtraction]) { self.results = results }

    func extract(url: URL, kind: CaptureKind, filename: String?) -> ContentIndexExtraction {
        calls += 1
        return results.isEmpty ? .unavailable("No fixture response.") : results.removeFirst()
    }

    func callCount() -> Int { calls }
}

@main
@MainActor
struct LocalContentSearchTests {
    private static let files = FileManager.default
    private static var checks = 0

    private static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        if try !value() {
            throw NSError(domain: "LocalContentSearchTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private static func unwrap<T>(_ value: T?, _ message: String) throws -> T {
        try expect(value != nil, message)
        return value!
    }

    private static func wait(_ message: String, timeout: TimeInterval = 8,
                             until condition: @MainActor () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !(await condition()), Date() < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        let completed = await condition()
        try expect(completed, message)
    }

    private static func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)!
    }

    /// The expected index mutations are removed so the comparison protects all
    /// immutable receipt, provenance, original, preview and user-edit fields.
    private static func nonIndexMetadata(_ capture: Capture) throws -> Data {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(CaptureSnapshot(capture))) as! [String: Any]
        for key in ["schemaVersion", "indexedText", "contentIndexState", "contentIndexError", "contentIndexVersion", "contentIndexCanRetry"] {
            object.removeValue(forKey: key)
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private static func state(store: CaptureStore, contentIndex: ContentIndexService) -> AppState {
        AppState(store: store, previews: PreviewService(store: store), contentIndex: contentIndex,
                 reminders: ReminderService(store: store, client: ContentIndexReminderClient()),
                 captureClipboard: CaptureClipboardService { _ in true })
    }

    static func main() async throws {
        let root = files.temporaryDirectory.appendingPathComponent("DaBinLocalContentSearch-\(UUID())", isDirectory: true)
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }

        try schemaCompatibility()
        try await persistenceAndMetadata(root.appendingPathComponent("persistence"))
        try await searchSemantics(root.appendingPathComponent("search"))
        try await queueCancellationAndRestart(root.appendingPathComponent("queue"))
        try await removalRaces(root.appendingPathComponent("removal"))
        try await failureAndRetry(root.appendingPathComponent("failure"))
        try await realExtraction(root.appendingPathComponent("real"))
        try privacyBoundary()

        print("PASS: \(checks) local content-search checks; schema compatibility, persistence, OCR snippets, filters, scopes, task conversion, queueing, cancellation, shutdown, removal, retry, native Vision/PDF/text extraction and privacy boundaries.")
    }

    private static func schemaCompatibility() throws {
        let current = Capture(kind: .image, originalText: nil, title: "Legacy screenshot")
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(CaptureSnapshot(current))) as! [String: Any]
        for key in ["indexedText", "contentIndexState", "contentIndexError", "contentIndexVersion", "contentIndexCanRetry"] {
            object.removeValue(forKey: key)
        }
        object["schemaVersion"] = 5
        let snapshot = try JSONDecoder().decode(CaptureSnapshot.self,
                                                from: JSONSerialization.data(withJSONObject: object))
        let restored = Capture(snapshot: snapshot)
        try expect(restored.indexedText.isEmpty && restored.contentIndexState == "idle"
                   && restored.contentIndexError == nil && restored.contentIndexVersion == 0
                   && !restored.contentIndexCanRetry,
                   "Schema 5 records without index fields decode as safe, retryable legacy captures")
        let scratch = files.temporaryDirectory.appendingPathComponent("DaBinIndexSchema-\(UUID())")
        defer { try? files.removeItem(at: scratch) }
        let store = try CaptureStore(root: scratch)
        let service = ContentIndexService(store: store)
        try expect(service.needsIndex(restored), "An eligible schema 5 capture is eligible for local indexing")
        try expect(CaptureSnapshot(current).schemaVersion == 6, "New snapshots identify the local-index schema")
        try expect(!ContentIndexService.isEligible(.text) && !ContentIndexService.isEligible(.link)
                   && !ContentIndexService.isEligible(.video) && !ContentIndexService.isEligible(.file)
                   && !ContentIndexService.isEligible(.task),
                   "Already textual and unsupported capture kinds never enter OCR")
        try expect(ContentIndexService.isEligible(.image) && ContentIndexService.isEligible(.pdf)
                   && ContentIndexService.isEligible(.document) && ContentIndexService.isEligible(.ai),
                   "Images, PDFs, supported documents and Illustrator PDFs are locally indexable")
        service.shutdown()
    }

    private static func persistenceAndMetadata(_ root: URL) async throws {
        var store: CaptureStore? = try CaptureStore(root: root)
        let stamp = date("2026-09-20T08:15:00Z")
        let source = CaptureSource(filePath: "/Fictional/Source/board.png",
                                   url: "https://example.invalid/project")
        let receipt = CaptureReceiptContext.automatic(.automaticScreenshot,
            sourceApplicationName: "Fixture Canvas", sourceApplicationBundleIdentifier: "com.dabin.fixture.canvas")
        let bytes = solidPNG(width: 40, height: 30)
        let capture = try await store!.importData(bytes, filename: "board.png", at: stamp,
                                                  timeZone: TimeZone(secondsFromGMT: 7200)!,
                                                  source: source, receipt: receipt)
        capture.previewDescription = "Local image preview"
        capture.previewState = "ready"
        try store!.update(capture, comment: "Keep my caption", reminderAt: nil, reminderTimeZoneID: nil)
        let before = try nonIndexMetadata(capture)
        let managed = try unwrap(store!.managedURL(for: capture), "Managed original is available before indexing")
        let originalBytes = try Data(contentsOf: managed)
        let script = ScriptedContentExtractor([.ready("Purple launch map\nSecond recognized line")])
        var service: ContentIndexService? = ContentIndexService(store: store!) { url, kind, filename in
            await script.extract(url: url, kind: kind, filename: filename)
        }
        service!.process([capture])
        service!.process([capture])
        try await wait("Injected extraction reaches its terminal state") { capture.contentIndexState == "ready" }
        let initialCalls = await script.callCount()
        try expect(initialCalls == 1, "Repeated process calls deduplicate an active capture")
        try expect(capture.indexedText == "Purple launch map\nSecond recognized line"
                   && capture.contentIndexVersion == ContentIndexService.currentVersion
                   && capture.contentIndexError == nil,
                   "Recognized text and index version are published together")
        try expect(try nonIndexMetadata(capture) == before,
                   "Indexing changes no receipt, provenance, preview, user edit or original metadata")
        try expect(try Data(contentsOf: managed) == originalBytes,
                   "Local text recognition never rewrites the saved original")
        let archiveRecord = try unwrap(store!.archiveURL(for: capture), "Capture has a dated archive")
            .appendingPathComponent("Capture.json")
        let archiveFolder = archiveRecord.deletingLastPathComponent()
        try expect(try String(contentsOf: archiveFolder.appendingPathComponent("Searchable Text.txt"),
                              encoding: .utf8) == capture.indexedText,
                   "The readable archive owns an exact searchable-text sidecar")
        try expect(try String(contentsOf: archiveFolder.appendingPathComponent("Capture.md"), encoding: .utf8)
            .contains("## Searchable text\n\n```text\nPurple launch map\nSecond recognized line\n```"),
                   "The readable capture summary includes locally recognized text")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let readable = try decoder.decode(CaptureSnapshot.self, from: Data(contentsOf: archiveRecord))
        try expect(readable.indexedText == capture.indexedText && readable.contentIndexState == "ready"
                   && readable.contentIndexVersion == ContentIndexService.currentVersion,
                   "Readable archive metadata mirrors the searchable text")

        service!.shutdown()
        service = nil
        store = nil
        let reopened = try CaptureStore(root: root)
        let restored = try unwrap(reopened.captures.first(where: { $0.id == capture.id }),
                                  "Indexed capture reopens with the same identity")
        try expect(restored.indexedText == capture.indexedText && restored.contentIndexState == "ready",
                   "Searchable text survives a full store reopen")
        let noRepeat = ScriptedContentExtractor([.ready("This response must remain unused")])
        let reopenedService = ContentIndexService(store: reopened) { url, kind, filename in
            await noRepeat.extract(url: url, kind: kind, filename: filename)
        }
        reopenedService.process([restored])
        try await Task.sleep(for: .milliseconds(30))
        let callsBeforeRecovery = await noRepeat.callCount()
        try expect(callsBeforeRecovery == 0 && restored.indexedText == capture.indexedText,
                   "A terminal current-version index is not rebuilt at every launch")
        restored.contentIndexState = "indexing"
        restored.contentIndexVersion = 0
        try reopened.save(captures: [restored])
        reopenedService.process([restored])
        try await wait("A crash-left indexing state is retried on the next service") {
            restored.contentIndexState == "ready" && restored.indexedText == "This response must remain unused"
        }
        let recoveryCalls = await noRepeat.callCount()
        try expect(recoveryCalls == 1, "A nonterminal stale version is resumed exactly once")
        reopenedService.shutdown()
    }

    private static func searchSemantics(_ root: URL) async throws {
        let first = Capture(capturedAt: date("2026-09-20T08:00:00Z"), kind: .text,
                            originalText: "Before context", title: "Before")
        let image = Capture(capturedAt: date("2026-09-20T09:00:00Z"), kind: .image,
                            title: "Planning board")
        image.indexedText = "Résumé for Violet launch\nOwner: Noya\n" + String(repeating: "detail ", count: 40)
        image.contentIndexState = "ready"
        image.contentIndexVersion = ContentIndexService.currentVersion
        let after = Capture(capturedAt: date("2026-09-20T10:00:00Z"), kind: .pdf,
                            title: "After context")
        after.indexedText = "Different archive words"
        let otherDay = Capture(capturedAt: date("2026-09-21T09:00:00Z"), kind: .document,
                               title: "Other date")
        otherDay.indexedText = "Résumé for Violet launch"
        let captures = [otherDay, after, image, first]

        let groups = CaptureSearch.groups(captures: captures, query: "resume VIOLET", filter: .media,
                                          scope: .day(image.captureDay))
        try expect(groups.count == 1 && groups[0].day == image.captureDay,
                   "Indexed text honors case/diacritic folding and immutable day scope")
        try expect(groups[0].entries.map(\.id) == [first.id, image.id, after.id]
                   && groups[0].entries.map(\.isMatch) == [false, true, false],
                   "An OCR match retains exactly one chronological neighbor on each side")
        let match = try unwrap(groups[0].entries.first(where: \.isMatch), "OCR result identifies its matching row")
        try expect(match.indexedTextMatch == "Résumé for Violet launch",
                   "Search returns direct recognized-text evidence rather than a generated summary")
        try expect(CaptureSearch.groups(captures: captures, query: "resume VIOLET", filter: .files,
                                        scope: .day(image.captureDay)).isEmpty,
                   "The content filter decides matches even when filtered rows remain context")
        try expect(CaptureSearch.groups(captures: captures, query: "resume VIOLET", filter: .all,
                                        scope: .week([otherDay.captureDay])).map(\.day) == [otherDay.captureDay],
                   "Week search uses its exact stored-day set")
        let mixed = CaptureSearch.groups(captures: [image], query: "planning violet", filter: .all)
        try expect(mixed.first?.entries.first?.indexedTextMatch == "Résumé for Violet launch",
                   "A query may span title and OCR while its snippet shows only the matching source line")
        let titleOnly = CaptureSearch.groups(captures: [image], query: "planning", filter: .all)
        try expect(titleOnly.first?.entries.first?.indexedTextMatch == nil,
                   "A metadata-only hit does not invent an OCR snippet")
        image.indexedText = String(repeating: "longword ", count: 30) + "violet tail"
        let longSnippet = CaptureSearch.groups(captures: [image], query: "violet", filter: .all)
            .first?.entries.first?.indexedTextMatch
        try expect(longSnippet?.count == 178 && longSnippet?.hasSuffix("…") == true,
                   "Long recognized lines are bounded for the compact result card")

        let store = try CaptureStore(root: root)
        let indexedTask = try await store.importData(solidPNG(width: 20, height: 20), filename: "task.png",
                                                     at: date("2026-09-22T09:00:00Z"))
        indexedTask.indexedText = "Converted screenshot followup"
        indexedTask.contentIndexState = "ready"
        indexedTask.contentIndexVersion = ContentIndexService.currentVersion
        try store.save(captures: [indexedTask])
        try store.convertToTask(indexedTask)
        let taskGroups = CaptureSearch.groups(captures: store.captures, query: "screenshot followup", filter: .tasks)
        try expect(taskGroups.first?.entries.filter(\.isMatch).map(\.id) == [indexedTask.id]
                   && taskGroups.first?.entries.first?.indexedTextMatch == "Converted screenshot followup",
                   "Converted captures retain OCR and become searchable through the Tasks filter")
        try expect(CaptureSearch.groups(captures: store.captures, query: "screenshot", filter: .media)
            .first?.entries.filter(\.isMatch).map(\.id) == [indexedTask.id],
                   "A converted image remains searchable through its original Media filter")
    }

    private static func queueCancellationAndRestart(_ root: URL) async throws {
        let store = try CaptureStore(root: root)
        var captures: [Capture] = []
        for index in 0..<3 {
            captures.append(try await store.importData(Data("Fixture \(index)".utf8),
                                                       filename: "queue-\(index).txt"))
        }
        let gate = GatedContentExtractor()
        let service = ContentIndexService(store: store) { url, kind, filename in
            await gate.extract(url: url, kind: kind, filename: filename)
        }
        service.process(captures)
        service.process(captures)
        try await wait("Only the first queued index starts") { await gate.callCount() == 1 }
        let rebuildWhileBusy = await service.rebuildAll()
        try expect(!rebuildWhileBusy, "Rebuild cannot repeatedly cancel and restart an active local index")
        try expect(captures[0].contentIndexState == "indexing"
                   && captures.dropFirst().allSatisfy { $0.contentIndexState == "idle" }
                   && service.pendingCount == 3,
                   "Only the active worker persists an in-progress state while queued captures retain prior metadata")
        await service.cancel(for: captures[0].id)
        try await wait("Canceling active work drains the next queued capture") { await gate.callCount() == 2 }
        try expect(captures[0].contentIndexState == "indexing" && captures[0].contentIndexVersion == 0,
                   "Cancellation remains retryable and is not presented as extraction failure")
        _ = await gate.releaseFirst(.ready("Second queued result"))
        try await wait("The second result commits before the third starts") {
            let calls = await gate.callCount()
            return captures[1].contentIndexState == "ready" && calls == 3
        }
        _ = await gate.releaseFirst(.ready("Third queued result"))
        try await wait("The serial queue completes") { captures[2].contentIndexState == "ready" }
        let maximumActive = await gate.maximumActive
        try expect(maximumActive == 1, "Local OCR uses one bounded worker and never stacks heavy Vision jobs")
        service.process([captures[0]])
        try await wait("A canceled nonterminal item can be resumed") { await gate.callCount() == 4 }
        _ = await gate.releaseFirst(.ready("Retried first result"))
        try await wait("Retried extraction commits") { captures[0].contentIndexState == "ready" }
        try expect(captures.map(\.indexedText) == ["Retried first result", "Second queued result", "Third queued result"],
                   "Each queued callback updates only its own capture")

        let shutdownStore = try CaptureStore(root: root.appendingPathComponent("shutdown"))
        let one = try await shutdownStore.importData(Data("One".utf8), filename: "one.txt")
        let two = try await shutdownStore.importData(Data("Two".utf8), filename: "two.txt")
        let shutdownGate = GatedContentExtractor()
        let stopping = ContentIndexService(store: shutdownStore) { url, kind, filename in
            await shutdownGate.extract(url: url, kind: kind, filename: filename)
        }
        stopping.process([one, two])
        try await wait("Shutdown fixture starts one bounded worker") { await shutdownGate.callCount() == 1 }
        stopping.shutdown()
        stopping.shutdown()
        stopping.process([one, two])
        try await wait("Shutdown cancels the active extraction") { await shutdownGate.pendingCount() == 0 }
        let shutdownCalls = await shutdownGate.callCount()
        try expect(shutdownCalls == 1 && one.contentIndexState == "indexing"
                   && two.contentIndexState == "idle" && stopping.pendingCount == 0,
                   "Shutdown drops queued work, refuses restart and leaves only active work in durable retry state")
        let fresh = ContentIndexService(store: shutdownStore) { _, _, filename in
            .ready("Fresh launch \(filename ?? "document")")
        }
        fresh.process([one, two])
        try await wait("A fresh launch resumes every unfinished index") {
            [one, two].allSatisfy { $0.contentIndexState == "ready" }
        }
        try expect(one.indexedText.contains("one.txt") && two.indexedText.contains("two.txt"),
                   "Relaunch recovery does not confuse queued capture identities")
        fresh.shutdown()
    }

    private static func removalRaces(_ root: URL) async throws {
        var store: CaptureStore? = try CaptureStore(root: root.appendingPathComponent("coordinated"))
        let capture = try await store!.importData(Data("Remove through app state".utf8), filename: "remove.txt")
        let gate = GatedContentExtractor()
        let service = ContentIndexService(store: store!) { url, kind, filename in
            await gate.extract(url: url, kind: kind, filename: filename)
        }
        let app = state(store: store!, contentIndex: service)
        service.process([capture])
        try await wait("Removal fixture starts indexing") { await gate.callCount() == 1 }
        await app.removeCapture(capture)
        try expect(store!.captures.isEmpty && app.status?.severity == .success,
                   "App removal awaits index cancellation and removes the capture")
        let coordinatedPending = await gate.pendingCount()
        try expect(coordinatedPending == 0, "Coordinated removal leaves no extraction callback in flight")
        service.shutdown()
        store = nil
        let reopened = try CaptureStore(root: root.appendingPathComponent("coordinated"))
        try expect(reopened.captures.isEmpty, "A canceled late OCR callback cannot recreate deleted metadata")

        let directStore = try CaptureStore(root: root.appendingPathComponent("defensive"))
        let direct = try await directStore.importData(Data("Direct removal".utf8), filename: "direct.txt")
        let directGate = GatedContentExtractor()
        let directService = ContentIndexService(store: directStore) { url, kind, filename in
            await directGate.extract(url: url, kind: kind, filename: filename)
        }
        directService.process([direct])
        try await wait("Defensive fixture starts indexing") { await directGate.callCount() == 1 }
        _ = try directStore.remove(direct)
        _ = await directGate.releaseFirst(.ready("Too late to publish"))
        try await wait("Late callback finishes after direct removal") { await directGate.pendingCount() == 0 }
        try await Task.sleep(for: .milliseconds(30))
        try expect(directStore.captures.isEmpty,
                   "Identity checks ignore a late result when removal bypasses coordinated cancellation")
        let directReopen = try CaptureStore(root: root.appendingPathComponent("defensive"))
        try expect(directReopen.captures.isEmpty, "A direct-removal race stays deleted after reopen")
        directService.shutdown()
    }

    private static func failureAndRetry(_ root: URL) async throws {
        let store = try CaptureStore(root: root)
        let capture = try await store.importData(Data("Retry fixture".utf8), filename: "retry.txt")
        let before = try nonIndexMetadata(capture)
        let script = ScriptedContentExtractor([
            .unavailable("This formatted document could not be read for text search."),
            .ready("Recovered searchable text")
        ])
        let service = ContentIndexService(store: store) { url, kind, filename in
            await script.extract(url: url, kind: kind, filename: filename)
        }
        service.process([capture])
        try await wait("Extraction failure reaches a stable unavailable state") {
            capture.contentIndexState == "unavailable"
        }
        try expect(capture.indexedText.isEmpty && capture.contentIndexError?.contains("could not be read") == true
                   && capture.contentIndexVersion == ContentIndexService.currentVersion
                   && capture.contentIndexCanRetry,
                   "A failed extractor stores no fabricated text and exposes a useful local error")
        try expect(try nonIndexMetadata(capture) == before,
                   "An extraction failure preserves every non-index field and original receipt")
        service.process([capture])
        try await Task.sleep(for: .milliseconds(20))
        let callsBeforeRetry = await script.callCount()
        try expect(callsBeforeRetry == 1, "A terminal failure does not spin in a launch retry loop")
        service.retry(capture)
        try await wait("An explicit retry can recover") { capture.indexedText == "Recovered searchable text" }
        let callsAfterRetry = await script.callCount()
        try expect(callsAfterRetry == 2 && capture.contentIndexState == "ready"
                   && capture.contentIndexError == nil && !capture.contentIndexCanRetry,
                   "A successful retry atomically replaces the previous failure")

        let missing = try await store.importData(Data("Original will be removed in fixture".utf8),
                                                 filename: "missing.txt")
        let missingURL = try unwrap(store.managedURL(for: missing), "Missing-original fixture starts with a managed file")
        try files.removeItem(at: missingURL)
        service.process([missing])
        try await wait("Missing original is terminal without invoking extraction") {
            missing.contentIndexState == "unavailable"
        }
        let callsAfterMissing = await script.callCount()
        try expect(missing.contentIndexError?.contains("saved original is unavailable") == true
                   && !missing.contentIndexCanRetry && callsAfterMissing == 2,
                   "Missing originals fail locally without entering the extractor")
        service.retry(missing)
        try await Task.sleep(for: .milliseconds(20))
        let callsAfterPermanentRetry = await script.callCount()
        try expect(callsAfterPermanentRetry == callsAfterMissing && service.pendingCount == 0,
                   "Permanent local limitations do not offer a retry loop")
        service.shutdown()
    }

    private static func realExtraction(_ root: URL) async throws {
        try files.createDirectory(at: root, withIntermediateDirectories: true)

        let imageURL = root.appendingPathComponent("vision.png")
        try textPNG("PURPLE ORBITAL NOTE").write(to: imageURL)
        let imageResult = await ContentTextExtractor.extract(url: imageURL, kind: .image, filename: "vision.png")
        try expect(imageResult.status == .ready && containsWords(imageResult.text, ["purple", "orbital", "note"]),
                   "Vision recognizes a generated high-contrast image entirely on device")

        let textPDFURL = root.appendingPathComponent("text-layer.pdf")
        try textLayerPDF("MEETING CONSTELLATION", at: textPDFURL)
        try expect(PDFDocument(url: textPDFURL)?.string?.contains("MEETING CONSTELLATION") == true,
                   "Generated text-layer PDF really contains selectable text")
        let textPDF = await ContentTextExtractor.extract(url: textPDFURL, kind: .pdf, filename: "text-layer.pdf")
        try expect(textPDF.status == .ready && containsWords(textPDF.text, ["meeting", "constellation"]),
                   "PDF text layers are indexed without depending on OCR guesses")

        let scanPDFURL = root.appendingPathComponent("scan.pdf")
        try imageOnlyPDF(try cgImage(from: textPNG("SCANNED PURPLE ARCHIVE")), at: scanPDFURL)
        let scannedDocument = try unwrap(PDFDocument(url: scanPDFURL), "Generated scanned PDF opens")
        try expect((scannedDocument.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   "Scanned fixture has no hidden PDF text layer")
        let scannedPDF = await ContentTextExtractor.extract(url: scanPDFURL, kind: .pdf, filename: "scan.pdf")
        try expect(scannedPDF.status == .ready
                   && containsWords(scannedPDF.text, ["scanned", "purple", "archive"]),
                   "An image-only PDF falls back to local page OCR")

        let bomURL = root.appendingPathComponent("unicode.txt")
        var bom = Data([0xEF, 0xBB, 0xBF])
        bom.append(Data("Résumé ירושלים\r\nPurple line\rSecond".utf8))
        try bom.write(to: bomURL)
        let plain = await ContentTextExtractor.extract(url: bomURL, kind: .document, filename: "unicode.txt")
        try expect(plain.status == .ready && plain.text == "Résumé ירושלים\nPurple line\nSecond",
                   "UTF-8 BOM, Unicode and mixed newlines normalize without losing content")

        let importedStore = try CaptureStore(root: root.appendingPathComponent("imported-documents"))
        let importedJSON = try await importedStore.importData(Data(#"{"project":"Violet Orbit"}"#.utf8),
                                                               filename: "project.json")
        try expect(importedJSON.kind == .document
                   && CaptureClassifier.fileKind(filename: "notes.yaml") == .document
                   && CaptureClassifier.fileKind(filename: "screen.html") == .file,
                   "Store classification reaches local JSON/YAML indexing while HTML stays outside the offline decoder")
        let importedService = ContentIndexService(store: importedStore)
        importedService.process([importedJSON])
        try await wait("A document imported through the real store becomes searchable") {
            importedJSON.contentIndexState == "ready"
        }
        try expect(containsWords(importedJSON.indexedText, ["project", "violet", "orbit"]),
                   "Import-through-store indexing covers supported structured text instead of only direct extractor calls")
        importedService.shutdown()

        let invalidBOMURL = root.appendingPathComponent("invalid-bom.txt")
        try Data([0xEF, 0xBB, 0xBF, 0xFF]).write(to: invalidBOMURL)
        let invalidBOM = await ContentTextExtractor.extract(url: invalidBOMURL, kind: .document,
                                                            filename: "invalid-bom.txt")
        try expect(invalidBOM.status == .unavailable && !invalidBOM.canRetry,
                   "Invalid BOM-prefixed UTF-8 is not stored as a successful empty index")

        let cappedURL = root.appendingPathComponent("capped.txt")
        try Data(String(repeating: "x", count: ContentTextExtractor.maximumCharacters + 1).utf8).write(to: cappedURL)
        let capped = await ContentTextExtractor.extract(url: cappedURL, kind: .document, filename: "capped.txt")
        try expect(capped.status == .ready && capped.text.count == ContentTextExtractor.maximumCharacters
                   && capped.message?.contains(ContentTextExtractor.maximumCharacters.formatted()) == true,
                   "Character-limited local documents disclose their partial index")

        let richURL = root.appendingPathComponent("note.rtf")
        let rich = NSAttributedString(string: "Formatted violet résumé",
                                      attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .medium)])
        let rtf = try rich.data(from: NSRange(location: 0, length: rich.length),
                                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        try rtf.write(to: richURL)
        let richResult = await ContentTextExtractor.extract(url: richURL, kind: .document, filename: "note.rtf")
        try expect(richResult.status == .ready && richResult.text == "Formatted violet résumé"
                   && !richResult.text.contains("\\rtf"),
                   "RTF indexing extracts rendered words instead of format control codes")

        let corruptPDF = root.appendingPathComponent("corrupt.pdf")
        try Data("not a PDF".utf8).write(to: corruptPDF)
        let corrupt = await ContentTextExtractor.extract(url: corruptPDF, kind: .pdf, filename: "corrupt.pdf")
        try expect(corrupt.status == .unavailable && corrupt.text.isEmpty
                   && corrupt.message?.contains("locked or could not be opened") == true,
                   "Corrupt PDFs fail clearly without searchable garbage")
        let unsupportedURL = root.appendingPathComponent("office.docx")
        try Data("not an Office package".utf8).write(to: unsupportedURL)
        let unsupported = await ContentTextExtractor.extract(url: unsupportedURL, kind: .document,
                                                             filename: "office.docx")
        try expect(unsupported.status == .unavailable && unsupported.text.isEmpty
                   && unsupported.message?.contains("not available yet") == true && !unsupported.canRetry,
                   "Unsupported document formats say they are unavailable instead of claiming success")
        let blankURL = root.appendingPathComponent("blank.png")
        try solidPNG(width: 240, height: 160).write(to: blankURL)
        let blank = await ContentTextExtractor.extract(url: blankURL, kind: .image, filename: "blank.png")
        try expect(blank.status == .ready && blank.text.isEmpty,
                   "A readable image with no words completes once with an empty index")
        let binaryURL = root.appendingPathComponent("binary.bin")
        try Data([0x00, 0xFF, 0x01]).write(to: binaryURL)
        let binary = await ContentTextExtractor.extract(url: binaryURL, kind: .file, filename: "binary.bin")
        try expect(binary.status == .unavailable && binary.text.isEmpty,
                   "Generic binary files never enter a misleading text path")
    }

    private static func privacyBoundary() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: files.currentDirectoryPath)
            .appendingPathComponent("Sources/DaBin/ContentIndexService.swift"), encoding: .utf8)
        for forbidden in ["URLSession", "LPMetadataProvider", "http://", "https://"] {
            try expect(!source.contains(forbidden), "The local index implementation has no \(forbidden) dependency")
        }
        try expect(!source.contains("DocumentType.html"),
                   "The document index does not invoke an HTML importer that could resolve external resources")
        try expect(source.contains("import Vision") && source.contains("import PDFKit"),
                   "The index explicitly uses Apple's on-device Vision and PDF frameworks")
    }

    private static func containsWords(_ value: String, _ words: [String]) -> Bool {
        let normalized = CaptureSearch.normalized(value)
        return words.allSatisfy { normalized.contains(CaptureSearch.normalized($0)) }
    }

    private static func solidPNG(width: Int, height: Int) -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return png(context.makeImage()!)
    }

    private static func textPNG(_ text: String) -> Data {
        let width = 1_800
        let height = 420
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        draw(text, in: context, at: CGPoint(x: 70, y: 150), size: 104)
        return png(context.makeImage()!)
    }

    private static func draw(_ text: String, in context: CGContext, at point: CGPoint, size: CGFloat) {
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.02, alpha: 1)
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.textPosition = point
        CTLineDraw(line, context)
    }

    private static func png(_ image: CGImage) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        precondition(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private static func cgImage(from data: Data) throws -> CGImage {
        let source = try unwrap(CGImageSourceCreateWithData(data as CFData, nil), "Generated PNG opens")
        return try unwrap(CGImageSourceCreateImageAtIndex(source, 0, nil), "Generated PNG has one image")
    }

    private static func textLayerPDF(_ text: String, at url: URL) throws {
        guard let consumer = CGDataConsumer(url: url as CFURL) else {
            throw NSError(domain: "LocalContentSearchTests", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create PDF consumer"])
        }
        var box = CGRect(x: 0, y: 0, width: 1_800, height: 420)
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw NSError(domain: "LocalContentSearchTests", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create PDF context"])
        }
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(box)
        draw(text, in: context, at: CGPoint(x: 70, y: 150), size: 104)
        context.endPDFPage()
        context.closePDF()
    }

    private static func imageOnlyPDF(_ image: CGImage, at url: URL) throws {
        guard let consumer = CGDataConsumer(url: url as CFURL) else {
            throw NSError(domain: "LocalContentSearchTests", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create scanned PDF consumer"])
        }
        var box = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw NSError(domain: "LocalContentSearchTests", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create scanned PDF context"])
        }
        context.beginPDFPage(nil)
        context.draw(image, in: box)
        context.endPDFPage()
        context.closePDF()
    }
}
