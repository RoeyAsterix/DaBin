import XCTest
@testable import DaBin

final class DaBinTests: XCTestCase {
    private func temporaryArchiveRoot() -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBin-XCTest-\(UUID())")
        addTeardownBlock { @MainActor in
            // The test's local stores must leave scope before their SQLite
            // files are removed. Yield once so the completed async import's
            // AppKit autorelease pool can drain as well.
            await Task.yield()
            if FileManager.default.fileExists(atPath: root.path) {
                try FileManager.default.removeItem(at: root)
            }
        }
        return root
    }

    @MainActor func testStoredOriginalAndDaySurviveReopen() async throws {
        let root = temporaryArchiveRoot()
        let bytes = Data("An original retained across relaunch".utf8)
        let date = ISO8601DateFormatter().date(from: "2026-09-22T23:59:59Z")!
        var first: CaptureStore? = try autoreleasepool { try CaptureStore(root: root) }
        defer { first?.cancelArchiveRepair(); first = nil }
        let capture = try await first!.importData(bytes, filename: "reference.txt", at: date, timeZone: TimeZone(secondsFromGMT: 7200)!)
        let id = capture.id
        try autoreleasepool {
            try first!.update(capture, comment: "A personal note", reminderAt: nil, reminderTimeZoneID: nil)
        }
        first?.cancelArchiveRepair()
        first = nil
        await Task.yield()
        try autoreleasepool {
            let reopened = try CaptureStore(root: root)
            defer { reopened.cancelArchiveRepair() }
            let found = try XCTUnwrap(reopened.captures.first { $0.id == id })
            XCTAssertEqual(found.captureDay, "2026-09-23")
            XCTAssertEqual(found.comment, "A personal note")
            XCTAssertEqual(try Data(contentsOf: XCTUnwrap(reopened.managedURL(for: found))), bytes)
        }
    }

    @MainActor func testSearchIncludesOnlySameDayNeighborsAcrossTypeFilter() throws {
        let root = temporaryArchiveRoot()
        try autoreleasepool {
            let store = try CaptureStore(root: root)
            defer { store.cancelArchiveRepair() }
            let date = ISO8601DateFormatter().date(from: "2026-09-22T12:00:00Z")!
            let before = try store.capture(text: "Before", at: date)[0]
            let hit = try store.capture(text: "https://example.org/needle", at: date.addingTimeInterval(1))[0]
            let after = try store.capture(text: "After", at: date.addingTimeInterval(2))[0]
            _ = try store.capture(text: "Unrelated tomorrow", at: date.addingTimeInterval(86400))
            let groups = CaptureSearch.groups(captures: store.captures, query: "needle", filter: .links)
            XCTAssertEqual(groups.count, 1)
            XCTAssertEqual(groups[0].entries.map { $0.capture.id }, [before.id, hit.id, after.id])
            XCTAssertEqual(groups[0].entries.map(\.isMatch), [false, true, false])
        }
    }
}
