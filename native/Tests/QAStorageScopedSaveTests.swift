import Foundation

@main struct QAStorageScopedSaveTests {
    static var checks = 0
    static let files = FileManager.default

    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else {
            throw NSError(domain: "QAStorageScopedSaveTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        checks += 1
    }

    @MainActor static func stored(_ store: CaptureStore, _ capture: Capture) throws -> CaptureSnapshot {
        guard let snapshot = try CaptureRepository(root: store.root).load().first(where: { $0.id == capture.id }) else {
            throw CaptureStoreError.invalidOriginal("Missing test capture")
        }
        return snapshot
    }

    @MainActor static func main() async throws {
        let root = files.temporaryDirectory.appendingPathComponent("QAStorageScopedSaveTests-\(UUID().uuidString)")
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }
        try await scopedUpdates(root.appendingPathComponent("scoped"))
        try warningRetention(root.appendingPathComponent("warnings"))
        try await reminderRetry(root.appendingPathComponent("retry"))
        try benchmark(root.appendingPathComponent("scale"))
        print("PASS: \(checks) scoped-storage assertions; touched-record saves, no-op previews, transaction rollback, reminder retry, retained archive warnings, and 1,000-record benchmark.")
    }

    @MainActor static func scopedUpdates(_ root: URL) async throws {
        let store = try CaptureStore(root: root)
        let first = try store.capture(text: "Unrelated original")[0]
        let second = try store.capture(text: "Preview target")[0]
        let firstSidecar = store.archiveURL(for: first)!.appendingPathComponent("Capture.md")
        let externalEdit = Data("An external note waiting for this capture's next update.".utf8)
        try externalEdit.write(to: firstSidecar)
        first.title = "An unrelated unsaved title"
        second.previewDescription = "A durable single-record description"
        try store.save(captures: [second])
        try expect(try stored(store, first).title == "Unrelated original", "Scoped save does not persist an unrelated in-memory mutation")
        try expect(try stored(store, second).previewDescription == second.previewDescription, "Scoped save durably updates the touched record")
        try expect(try Data(contentsOf: firstSidecar) == externalEdit, "Scoped save does not inspect or regenerate unrelated sidecars")

        let previews = PreviewService(store: store)
        previews.process([second])
        try expect(try stored(store, second).previewState == "ready", "A text preview transition is durably stored")
        try expect(try stored(store, first).title == "Unrelated original", "Preview processing persists only the touched capture")
        try expect(try Data(contentsOf: firstSidecar) == externalEdit, "Preview completion leaves unrelated sidecars alone")
        let secondSidecar = store.archiveURL(for: second)!.appendingPathComponent("Capture.md")
        try externalEdit.write(to: secondSidecar)
        previews.process([second])
        try expect(try Data(contentsOf: secondSidecar) == externalEdit, "Processing an unchanged ready text preview performs no archive write")
        previews.cancelNetwork()
        try expect(try Data(contentsOf: secondSidecar) == externalEdit, "Cancelling an empty network queue performs no archive write")

        let previousTitle = second.title
        first.title = "Must roll back in repository"
        second.updatedAt = Date(timeIntervalSinceReferenceDate: .infinity)
        var failed = false
        do { try store.save(captures: [first, second]) } catch { failed = true }
        try expect(failed, "A batch containing an unencodable record rejects the metadata transaction")
        try expect(try stored(store, first).title == "Unrelated original", "A later encoding failure rolls back earlier records in the batch")
        try expect(try stored(store, second).title == previousTitle, "The failing record leaves its durable snapshot intact")
        second.updatedAt = Date()
        first.title = "Generic save still saves all captures"
        try store.save()
        try expect(try stored(store, first).title == first.title, "The legacy unscoped save remains backward compatible")
        try expect(try files.contentsOfDirectory(at: firstSidecar.deletingLastPathComponent().appendingPathComponent("Local edits"), includingPropertiesForKeys: nil).contains {
            try Data(contentsOf: $0) == externalEdit
        }, "Later explicit archive regeneration preserves the earlier external edit")
    }

    @MainActor static func warningRetention(_ root: URL) throws {
        let store = try CaptureStore(root: root)
        let blocked = try store.capture(text: "Blocked mirror")[0]
        let other = try store.capture(text: "Healthy mirror")[0]
        let sidecar = store.archiveURL(for: blocked)!.appendingPathComponent("Capture.md")
        try files.moveItem(at: sidecar, to: sidecar.appendingPathExtension("backup"))
        try files.createDirectory(at: sidecar, withIntermediateDirectories: false)
        blocked.previewDescription = "Still durable despite a sidecar obstruction"
        try store.save(captures: [blocked])
        try expect(store.error?.contains("1 capture folder(s)") == true, "A failed mirror records its per-capture warning")
        other.previewDescription = "Healthy scoped update"
        try store.save(captures: [other])
        try expect(store.error?.contains("1 capture folder(s)") == true, "An unrelated successful scoped update retains the unresolved warning")
        try expect(try stored(store, blocked).previewDescription == blocked.previewDescription, "A sidecar failure never rolls back committed metadata")
        try files.removeItem(at: sidecar)
        try store.save(captures: [blocked])
        try expect(store.error == nil, "Repairing the failed capture clears only its resolved warning")
    }

    @MainActor static func reminderRetry(_ root: URL) async throws {
        let store = try CaptureStore(root: root)
        let capture = try store.capture(text: "Notification transition retry")[0]
        capture.notificationState = "pending"
        try store.save(captures: [capture])
        let service = ReminderService(store: store, client: SilentNotificationClient())
        capture.updatedAt = Date(timeIntervalSinceReferenceDate: .infinity)
        await service.reconcile()
        try expect(capture.notificationState == "pending", "A failed notification-state save restores the prior in-memory state")
        try expect(try stored(store, capture).notificationState == "pending", "Failed notification-state metadata remains durable and unchanged")
        capture.updatedAt = Date()
        await service.reconcile()
        try expect(try stored(store, capture).notificationState == "none", "Reconciliation retries and persists the state after the write issue is fixed")
    }

    @MainActor static func benchmark(_ root: URL) throws {
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        let captures = (0..<1_000).map { Capture(capturedAt: Date(timeIntervalSince1970: 1_785_000_000 + Double($0)), kind: .text,
                                               originalText: "Scale check \($0)", title: "Scale check \($0)") }
        do { try CaptureRepository(root: root).save(captures) }
        let store = try CaptureStore(root: root)
        let capture = store.captures[0]
        capture.notificationState = "scheduled"
        var start = Date()
        try store.save(captures: [capture])
        print(String(format: "BENCHMARK 1000 records, one scoped state update: %.4f seconds", Date().timeIntervalSince(start)))
        start = Date()
        PreviewService(store: store).process([capture])
        print(String(format: "BENCHMARK 1000 records, one text preview update: %.4f seconds", Date().timeIntervalSince(start)))
        let reopened = try CaptureStore(root: root)
        try expect(reopened.captures.count == 1_000, "Scoped updates and startup preserve all records in a 1,000-record archive")
        try expect(reopened.captures.first { $0.id == capture.id }?.notificationState == "scheduled", "Scoped state persists through the full startup path")
    }
}

@MainActor private final class SilentNotificationClient: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .denied }
    func requestAuthorization() async throws -> Bool { false }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}
