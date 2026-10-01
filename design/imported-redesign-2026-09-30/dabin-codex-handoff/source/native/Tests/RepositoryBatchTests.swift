import Foundation

@main
struct RepositoryBatchTests {
    @MainActor private static var checks = 0
    @MainActor private static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        if try !value() { throw NSError(domain: "RepositoryBatchTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinRepositoryBatch-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try CaptureRepository(root: root)
        let captures = (0..<1_000).map { index in
            Capture(kind: .text, originalText: "Synthetic batch record \(index)", title: "Batch \(index)")
        }
        let start = ProcessInfo.processInfo.systemUptime
        try repository.save(captures)
        let seconds = ProcessInfo.processInfo.systemUptime - start
        print(String(format: "BENCHMARK: 1000-record metadata batch save %.4f seconds", seconds))
        try expect(try repository.load().count == 1_000, "A batch spanning multiple prefetch chunks saves every identity")

        let changed = captures[0]
        changed.comment = "First payload"
        let first = CaptureSnapshot(changed)
        changed.comment = "Latest payload"
        let latest = CaptureSnapshot(changed)
        let new = Capture(kind: .task, originalText: "New task in a mixed batch", title: "New task")
        try repository.saveSnapshots([first, CaptureSnapshot(new), latest])
        let mixed = try repository.load()
        try expect(mixed.count == 1_001 && mixed.first { $0.id == changed.id }?.comment == "Latest payload",
                   "Mixed updates and inserts preserve latest-wins duplicate payload semantics")
        try expect(mixed.first { $0.id == new.id }?.kindRaw == "task", "Mixed batch persists newly inserted records")
        try expect(mixed.first { $0.id == captures[999].id }?.comment == "", "Scoped updates preserve unrelated rows")

        let duplicateNew = Capture(kind: .text, originalText: "Only one new identity", title: "New duplicate")
        let originalDuplicate = CaptureSnapshot(duplicateNew)
        duplicateNew.comment = "Last new duplicate wins"
        try repository.saveSnapshots([originalDuplicate, CaptureSnapshot(duplicateNew)])
        try expect(try repository.load().filter { $0.id == duplicateNew.id }.count == 1, "A repeated new identity inserts exactly one managed record")
        try expect(try repository.load().first { $0.id == duplicateNew.id }?.comment == "Last new duplicate wins", "Repeated new identities keep their last payload")

        let beforeFailure = try repository.load()
        changed.comment = "This update must roll back"
        let failedNew = Capture(kind: .text, originalText: "This insert must roll back", title: "Failed insert")
        var invalidObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(CaptureSnapshot(failedNew))) as! [String: Any]
        invalidObject["schemaVersion"] = 999
        let invalid = try JSONDecoder().decode(CaptureSnapshot.self, from: JSONSerialization.data(withJSONObject: invalidObject))
        var rejected = false
        do { try repository.saveSnapshots([CaptureSnapshot(changed), CaptureSnapshot(failedNew), invalid]) }
        catch { rejected = true }
        let afterFailure = try repository.load()
        try expect(rejected && afterFailure.count == beforeFailure.count && !afterFailure.contains { $0.id == failedNew.id },
                   "A late invalid payload rolls back every insertion in its transaction")
        try expect(afterFailure.first { $0.id == changed.id }?.comment == "Latest payload", "Failed mixed batch restores existing row contents")

        changed.comment = "A later retry succeeds"
        try repository.save([changed])
        try expect(try CaptureRepository(root: root).load().first { $0.id == changed.id }?.comment == "A later retry succeeds",
                   "Rollback leaves the context usable, and a scoped retry survives reopening")
        try repository.saveSnapshots([])
        try expect(try repository.load().count == beforeFailure.count, "An empty batch does not alter unrelated records")
        print("PASS: \(checks) repository batching, duplicate, mixed-update, rollback, and restart checks.")
    }
}
