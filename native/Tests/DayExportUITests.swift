import Foundation

@main
private enum DayExportUITests {
    @MainActor private static var checks = 0

    @MainActor private static func expect(_ condition: @autoclosure () -> Bool,
                                          _ message: String) throws {
        checks += 1
        guard condition() else {
            throw NSError(domain: "DayExportUITests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    @MainActor
    static func main() async throws {
        try checkHeaderActionContract()
        let document = makeDocument()
        try await checkCopyFeedback(document)
        try checkCopyFailureAndEmpty(document)
        try checkSaveSuccessCancellationAndFailure(document)
        try checkWeekCopyAndDownload()
        print("PASS: \(checks) export UI checks; day/week copy and download, ordered header actions, popover presentation, feedback, cancellation, failure and exact bytes.")
    }

    @MainActor
    private static func checkHeaderActionContract() throws {
        try expect(TimelinePrimaryAction.allCases == [.add, .search, .exportDay, .notifications, .settings],
                   "Primary actions keep the required keyboard and visual order")
        try expect(TimelinePrimaryAction.allCases.map(\.symbol) ==
                   ["plus", "magnifyingglass", "square.and.arrow.up", "bell", "gearshape"],
                   "Primary actions use recognizable icons, including export and Settings gear")
        try expect(TimelinePrimaryAction.exportDay.label == "Export Day"
                   && TimelinePrimaryAction.settings.label == "Settings and options",
                   "Icon-only actions expose complete accessible names")
    }

    @MainActor
    private static func makeDocument() -> DayExportDocument {
        let zone = TimeZone(secondsFromGMT: 0)!
        let selected = Date(timeIntervalSince1970: 1_796_860_800) // 2026-12-10 00:00 UTC
        let capture = Capture(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                              capturedAt: selected.addingTimeInterval(9 * 3_600), timeZone: zone,
                              kind: .text, originalText: "A complete fictional note",
                              title: "Morning note", captureDay: "2026-12-10",
                              captureTimeZoneID: zone.identifier, captureUTCOffsetSeconds: 0)
        return DayExportDocument.make(captures: [capture], selectedDate: selected,
                                      now: selected.addingTimeInterval(10 * 3_600),
                                      calendarTimeZone: zone)
    }

    @MainActor
    private static func checkCopyFeedback(_ document: DayExportDocument) async throws {
        var copied: String?
        var chooserCalls = 0
        let controller = DayExportActionController(pasteboardWriter: {
            copied = $0
            return true
        }, destinationChooser: { _, _ in
            chooserCalls += 1
            return .cancelled
        }, fileWriter: { _, _ in })

        controller.present()
        try expect(controller.isPresented && controller.feedback == nil,
                   "Opening the action popover starts without stale feedback")
        try expect(controller.copy(document), "Copy Day reports pasteboard success")
        try expect(copied == document.text && controller.feedback == .copied(.day),
                   "Copy Day uses the exact generated plain text and shows Day copied")
        try expect(controller.isPresented, "Copy success remains visible briefly")
        try await Task.sleep(for: .milliseconds(1_250))
        try expect(!controller.isPresented && controller.feedback == nil,
                   "The brief Copy Day confirmation dismisses cleanly")
        try expect(chooserCalls == 0, "Copy Day never opens the save destination chooser")

        controller.present()
        controller.updatePresentation(false)
        try expect(!controller.isPresented,
                   "An outside dismissal binding closes the action popover")
        controller.present()
        controller.dismiss()
        try expect(!controller.isPresented,
                   "Escape dismissal closes the action popover")
    }

    @MainActor
    private static func checkCopyFailureAndEmpty(_ document: DayExportDocument) throws {
        var writes = 0
        let failed = DayExportActionController(pasteboardWriter: { _ in
            writes += 1
            return false
        }, destinationChooser: { _, _ in .cancelled }, fileWriter: { _, _ in })
        failed.present()
        try expect(!failed.copy(document), "A pasteboard refusal is not reported as success")
        try expect(failed.isPresented && failed.feedback == .failed("Couldn’t copy this day."),
                   "Copy failure remains visible and actionable in the popover")

        let empty = DayExportDocument.make(captures: [], selectedDate: Date(), now: Date())
        failed.present()
        try expect(!failed.copy(empty) && writes == 1,
                   "An empty day cannot invoke the clipboard writer")
        try expect(failed.save(empty) == .nothingToExport,
                   "An empty day cannot invoke the file export path")
    }

    @MainActor
    private static func checkSaveSuccessCancellationAndFailure(_ document: DayExportDocument) throws {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("DaBinExportUI-\(UUID().uuidString)-\(document.filename)")
        defer { try? FileManager.default.removeItem(at: destination) }
        var offeredPeriod: TimelineExportPeriod?
        var offeredName: String?
        var savedData: Data?
        var savedURL: URL?
        let success = DayExportActionController(pasteboardWriter: { _ in false },
            destinationChooser: { period, filename in
                offeredPeriod = period
                offeredName = filename
                return .selected(destination)
            }, fileWriter: {
                savedData = $0
                savedURL = $1
                try $0.write(to: $1, options: .atomic)
            })
        success.present()
        try expect(success.save(document) == .saved(destination),
                   "Export Text File reports its selected destination")
        try expect(offeredPeriod == .day && offeredName == document.filename,
                   "The save panel receives the day scope and required DaBin ISO-date filename")
        try expect(savedURL == destination && savedData == document.utf8Data
                   && (try? Data(contentsOf: destination)) == document.utf8Data
                   && String(data: savedData!, encoding: .utf8) == document.text,
                   "Text export writes the exact UTF-8 bytes used by Copy Day")
        try expect(success.feedback == .saved(.day),
                   "A successful file export has affirmative feedback")
        success.dismiss()

        var cancellationWrites = 0
        let cancelled = DayExportActionController(pasteboardWriter: { _ in false },
            destinationChooser: { _, _ in .cancelled }, fileWriter: { _, _ in cancellationWrites += 1 })
        cancelled.present()
        try expect(cancelled.save(document) == .cancelled && cancellationWrites == 0,
                   "Cancelling the save panel quietly writes nothing")
        try expect(cancelled.feedback == nil,
                   "Cancellation is not presented as an error")

        struct ExpectedFailure: LocalizedError {
            var errorDescription: String? { "Fixture destination is unavailable." }
        }
        let failed = DayExportActionController(pasteboardWriter: { _ in false },
            destinationChooser: { _, _ in .selected(destination) },
            fileWriter: { _, _ in throw ExpectedFailure() })
        failed.present()
        let outcome = failed.save(document)
        guard case .failed(let message) = outcome else {
            try expect(false, "A writer error produces the file failure state")
            return
        }
        try expect(message.contains("Fixture destination is unavailable")
                   && failed.feedback == .failed(message) && failed.isPresented,
                   "A file write failure remains visible with its useful cause")
    }

    @MainActor
    private static func checkWeekCopyAndDownload() throws {
        let zone = TimeZone(secondsFromGMT: 0)!
        let end = Date(timeIntervalSince1970: 1_796_860_800) // 2026-12-10 00:00 UTC
        let capture = Capture(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!,
                              capturedAt: end.addingTimeInterval(-2 * 86_400 + 3_600), timeZone: zone,
                              kind: .text, originalText: "Weekly fictional note",
                              title: "Weekly note", captureDay: "2026-12-08",
                              captureTimeZoneID: zone.identifier, captureUTCOffsetSeconds: 0)
        let document = WeekExportDocument.make(captures: [capture], weekEndingDate: end,
                                               now: end.addingTimeInterval(3_600),
                                               calendarTimeZone: zone)
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("DaBinExportUI-\(UUID().uuidString)-\(document.filename)")
        defer { try? FileManager.default.removeItem(at: destination) }
        var copied: String?
        var offeredPeriod: TimelineExportPeriod?
        var offeredName: String?
        var savedData: Data?
        let controller = DayExportActionController(pasteboardWriter: {
            copied = $0
            return true
        }, destinationChooser: { period, filename in
            offeredPeriod = period
            offeredName = filename
            return .selected(destination)
        }, fileWriter: { data, url in
            savedData = data
            try data.write(to: url, options: .atomic)
        })

        controller.present()
        try expect(controller.copy(document) && copied == document.text,
                   "Copy Week uses the complete deterministic week text")
        try expect(controller.feedback == .copied(.week)
                   && controller.feedback?.message == "Week copied.",
                   "Copy Week reports scope-specific success")
        controller.dismiss()

        controller.present()
        try expect(controller.save(document) == .saved(destination),
                   "Download Week reports its selected destination")
        try expect(offeredPeriod == .week && offeredName == document.filename,
                   "The week save panel receives its scope and ISO range filename")
        try expect(savedData == document.utf8Data
                   && (try? Data(contentsOf: destination)) == document.utf8Data,
                   "Download Week writes exactly the same UTF-8 bytes as Copy Week")
        try expect(controller.feedback == .saved(.week)
                   && controller.feedback?.message == "Week downloaded.",
                   "Download Week reports scope-specific success")
    }
}
