import XCTest
@testable import DaBin

final class DaBinTests: XCTestCase {
    @MainActor func testStoredOriginalAndDaySurviveReopen() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBin-XCTest-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data("An original retained across relaunch".utf8)
        let date = ISO8601DateFormatter().date(from: "2026-09-22T23:59:59Z")!
        var first: CaptureStore? = try CaptureStore(root: root)
        let capture = try await first!.importData(bytes, filename: "reference.txt", at: date, timeZone: TimeZone(secondsFromGMT: 7200)!)
        let id = capture.id
        try first!.update(capture, comment: "A personal note", reminderAt: nil, reminderTimeZoneID: nil)
        first = nil
        let reopened = try CaptureStore(root: root)
        let found = try XCTUnwrap(reopened.captures.first { $0.id == id })
        XCTAssertEqual(found.captureDay, "2026-09-23")
        XCTAssertEqual(found.comment, "A personal note")
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(reopened.managedURL(for: found))), bytes)
    }

    @MainActor func testSearchIncludesOnlySameDayNeighborsAcrossTypeFilter() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBin-XCTest-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root)
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
