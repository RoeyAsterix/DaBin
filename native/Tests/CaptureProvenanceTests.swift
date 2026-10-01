import Foundation

@main
struct CaptureProvenanceTests {
    @MainActor private static var checks = 0
    @MainActor private static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        guard try value() else { throw NSError(domain: "CaptureProvenanceTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    @MainActor private static func rejects(_ body: () throws -> Void, _ message: String) throws {
        var rejected = false
        do { try body() } catch { rejected = true }
        try expect(rejected, message)
    }

    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinProvenance-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root.appendingPathComponent("Source"))
        let time = Date(timeIntervalSince1970: 1_790_769_600)
        let capture = try store.capture(text: "Fictional client feedback", at: time)[0]
        try expect(capture.pasteHistory.isEmpty, "Existing and new captures start without invented paste receipts")
        let original = CaptureSnapshot(capture)
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        legacy.removeValue(forKey: "pasteHistory")
        for version in 1...9 {
            legacy["schemaVersion"] = version
            let restored = Capture(snapshot: try JSONDecoder().decode(CaptureSnapshot.self, from: JSONSerialization.data(withJSONObject: legacy)))
            try expect(restored.pasteHistory.isEmpty, "Schema \(version) opens with an empty usage ledger")
        }
        try expect(CapturePasteHistory.isValid([]), "An absent or empty history is valid")
        let first = try store.recordPasteDestination(for: capture, applicationName: "Mail", applicationBundleIdentifier: "com.apple.mail", at: time)
        let repeated = try store.recordPasteDestination(for: capture, applicationName: "Mail", applicationBundleIdentifier: "com.apple.mail", at: time.addingTimeInterval(1))
        try expect(first.id != repeated.id && capture.pasteHistory.count == 2, "Repeated pastes remain separate events with unique IDs")
        try expect(capture.pasteHistory.allSatisfy { $0.evidence == .manual }, "Every user-facing record operation is manual")
        try expect(CapturePasteHistory.destinations(capture.pasteHistory).first?.count == 2
                   && CapturePasteHistory.destinations(capture.pasteHistory).count == 1, "Repeated app receipts share one compact destination mark")
        for (offset, app) in ["Notes", "Finder", "Safari", "Fictional Studio"].enumerated() {
            try store.recordPasteDestination(for: capture, applicationName: app, at: time.addingTimeInterval(Double(offset + 2)))
        }
        let compact = CapturePasteHistory.compactDestinations(capture.pasteHistory)
        try expect(compact.count == 3 && CapturePasteHistory.overflowCount(capture.pasteHistory) == 2,
                   "The compact trail shows exactly three distinct applications and an accurate overflow count")
        try expect(compact.first?.application.name == "Fictional Studio", "The most recently recorded destination is shown first")
        let aliasEvents = [CapturePasteEvent(applicationName: "Google Chrome", recordedAt: time),
                           CapturePasteEvent(applicationName: "Chrome", applicationBundleIdentifier: "com.google.Chrome", recordedAt: time)]
        try expect(CapturePasteHistory.destinations(aliasEvents).count == 1, "Known name and bundle identities merge without losing event counts")
        try expect(CapturePasteHistory.destinations([.init(applicationName: "Studio", recordedAt: time),
                                                     .init(applicationName: "studio", recordedAt: time)]).count == 1,
                   "Custom product names are compared without case sensitivity")
        try expect(!CapturePasteHistory.isValid([first, first]), "Duplicate event identities are rejected")
        try expect(!CapturePasteHistory.isValid((0...CapturePasteHistory.maximumEvents).map { _ in
            CapturePasteEvent(applicationName: "Mail", recordedAt: time)
        }), "The ledger has a bounded event count")
        for invalid in ["", "   ", String(repeating: "x", count: 101), "Two\nLines", "App\u{0000}Name"] {
            try rejects({ _ = try store.recordPasteDestination(for: capture, applicationName: invalid) }, "Invalid app names cannot create receipts")
        }
        try expect(!CapturePasteEvent(applicationName: "App", applicationBundleIdentifier: "bundle/path", recordedAt: time).isValid,
                   "Bundle IDs cannot contain file paths or controls")
        try expect(!CapturePasteEvent(applicationName: "App", recordedAt: .init(timeIntervalSince1970: .infinity)).isValid,
                   "Nonfinite timestamps are rejected")
        try expect(!CapturePasteEvent(applicationName: "App", recordedAt: .init(timeIntervalSince1970: -1)).isValid,
                   "Out-of-range timestamps are rejected")

        let sourceLink = try store.capture(text: "https://example.com/destination", at: time)[0]
        try expect(CaptureSourcePresentation.origin(for: sourceLink).name == "Unknown source",
                   "The target of a copied link is never presented as its source website")
        let browserSource = Capture(kind: .text, originalText: "Quoted selection", title: "Quoted selection",
                                    sourceURL: "https://www.example.com/article")
        try expect(CaptureSourcePresentation.origin(for: browserSource).name == "example.com",
                   "Explicit source URL metadata can identify its website")
        let automatic = Capture(kind: .text, originalText: "Known receipt", title: "Known receipt",
            receipt: .automatic(.automaticClipboard, sourceApplicationName: "Wrong label", sourceApplicationBundleIdentifier: "com.apple.Safari"))
        try expect(CaptureSourcePresentation.origin(for: automatic).name == "Safari", "Known recorded bundle identity takes precedence over a legacy display name")
        let unknownProduct = Capture(kind: .text, originalText: "Known custom source", title: "Known custom source",
            receipt: .automatic(.automaticClipboard, sourceApplicationName: "Fictional Writer", sourceApplicationBundleIdentifier: "example.writer"))
        try expect(CaptureSourcePresentation.origin(for: unknownProduct).name == "Fictional Writer",
                   "Unknown applications keep their actual supplied names")
        let copiedHistory = capture.pasteHistory
        let clipboard = CaptureClipboardService { _ in true }
        _ = try clipboard.copy([capture], managedURL: store.managedURL(for:))
        try expect(capture.pasteHistory == copiedHistory, "Copying content is not proof of a paste and creates no receipt")

        let beforeFailure = CaptureSnapshot(capture)
        store.failureInjector = { if $0 == .beforeMetadataSave { throw CaptureStoreError.importVerificationFailed } }
        try rejects({ _ = try store.recordPasteDestination(for: capture, applicationName: "Failed write") }, "A failed save reports an error")
        try expect(capture.pasteHistory == beforeFailure.pasteHistory && capture.updatedAt == beforeFailure.updatedAt,
                   "A failed append rolls back the history and update date")
        try rejects({ try store.removePasteDestination(first.id, from: capture) }, "A failed manual removal reports an error")
        try expect(capture.pasteHistory == beforeFailure.pasteHistory, "A failed removal keeps all history events")
        store.failureInjector = nil
        let reopened = try CaptureStore(root: store.root)
        try expect(reopened.captures.first { $0.id == capture.id }?.pasteHistory == capture.pasteHistory,
                   "Only committed history survives restart")
        try store.removePasteDestination(first.id, from: capture)
        try expect(capture.pasteHistory.count == copiedHistory.count - 1 && capture.pasteHistory.contains(repeated),
                   "Removing one manual event leaves other pastes into the same app intact")
        try rejects({ try store.removePasteDestination(first.id, from: capture) }, "A missing event is not silently reported as removed")

        let pastesBeforeConversion = capture.pasteHistory
        try store.convertToTask(capture)
        try expect(capture.isTask && capture.id == original.id && capture.pasteHistory == pastesBeforeConversion,
                   "Task conversion preserves original identity and all paste history")
        try store.setTaskPlanning(capture, planning: TaskPlanning(plannedDay: "2026-09-30", recurrence: .daily))
        guard let successor = try store.setTaskCompleted(capture, completed: true, at: time) else {
            throw NSError(domain: "CaptureProvenanceTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing recurring successor"])
        }
        try expect(successor.pasteHistory.isEmpty && capture.pasteHistory == pastesBeforeConversion,
                   "A recurring successor starts clean while the completed occurrence retains its usage history")
        let backup = root.appendingPathComponent("Trail.dabinbackup")
        try store.exportBackup(to: backup)
        let backupStore = try CaptureStore(root: root.appendingPathComponent("Restored"))
        _ = try backupStore.restoreBackup(from: backup)
        try expect(backupStore.captures.first { $0.id == capture.id }?.pasteHistory == capture.pasteHistory,
                   "Portable backup and restore preserve full individual paste receipts")
        try expect(backupStore.captures.first { $0.id == successor.id }?.pasteHistory.isEmpty == true,
                   "Backup does not add history to a recurring successor")
        let stale = Capture(kind: .text, originalText: "Stale", title: "Stale")
        try rejects({ _ = try store.recordPasteDestination(for: stale, applicationName: "Mail") }, "A stale record cannot acquire a destination")
        try expect(stale.pasteHistory.isEmpty, "A stale record is unchanged")
        _ = try store.remove(sourceLink)
        try rejects({ _ = try store.recordPasteDestination(for: sourceLink, applicationName: "Mail") }, "A trashed record cannot acquire a destination")
        try expect(sourceLink.pasteHistory.isEmpty, "A trashed record is unchanged")
        try checkExportsAndSidecars(root: root.appendingPathComponent("Exports"))
        print("PASS: \(checks) provenance checks; legacy records, truthful origins, bounded manual ledger, compact grouping, rollback, conversion, recurrence, restart, backup, day/week exports and readable sidecars.")
    }

    @MainActor private static func checkExportsAndSidecars(root: URL) throws {
        let store = try CaptureStore(root: root)
        let iso = ISO8601DateFormatter()
        let time = iso.date(from: "2026-09-30T08:00:00Z")!
        let now = iso.date(from: "2026-10-10T12:00:00Z")!
        let zone = TimeZone(secondsFromGMT: 0)!
        let receipt = CaptureReceiptContext.automatic(.automaticClipboard,
            sourceApplicationName: "Safari", sourceApplicationBundleIdentifier: "com.apple.Safari")
        let capture = try store.capture(text: "Review fictional client feedback", at: time, timeZone: zone,
            source: CaptureSource(url: "https://example.invalid/feedback"), receipt: receipt)[0]
        try store.convertToTask(capture)
        try store.setOrganization(capture, pinned: false, projectName: "Export fixture")
        try store.setTaskPlanning(capture, planning: TaskPlanning(plannedDay: "2026-10-04", plannedTime: "09:45", effortMinutes: 25))
        try store.setTaskFocus(capture, session: .init(remainingSeconds: 1_500, endAt: time.addingTimeInterval(1_500)))
        let later = try store.recordPasteDestination(for: capture, applicationName: "Slack",
            applicationBundleIdentifier: "com.tinyspeck.slackmacgap", at: time.addingTimeInterval(7_200))
        let earlier = try store.recordPasteDestination(for: capture, applicationName: "Mail",
            applicationBundleIdentifier: "com.apple.mail", at: time.addingTimeInterval(3_600))
        let earlierLine = "Paste destination: Mail · 2026-09-30T09:00:00Z · Recorded by you"
        let laterLine = "Paste destination: Slack · 2026-09-30T10:00:00Z · Recorded by you"
        let day = DayExportDocument.make(captures: store.captures, selectedDate: time, now: now, calendarTimeZone: zone)
        let week = WeekExportDocument.make(captures: store.captures, weekEndingDate: time, now: now, calendarTimeZone: zone)
        try expect(day.actionCount == 1 && week.actionCount == 1, "Paste receipts remain metadata on their original capture, not new capture actions")
        let dayBody = day.text.range(of: "\n\n1. ").map { String(day.text[$0.lowerBound...]) }
        let weekBody = week.text.range(of: "\n\n1. ").map { String(week.text[$0.lowerBound...]) }
        try expect(dayBody != nil && dayBody == weekBody, "Day and week export use exactly the same action detail output")
        try expect(day.text.contains("Source: Safari (com.apple.Safari)") && day.text.contains("Planned day: 2026-10-04")
                   && day.text.contains("Planned local time: 09:45") && day.text.contains("Focus duration: 25 minutes")
                   && day.text.contains("Focus remaining at last transition: 00:25:00"),
                   "Exports retain supplied source, planned date/time and the persisted focus transition")
        try expect(day.text.contains(earlierLine) && day.text.contains(laterLine)
                   && day.text.range(of: earlierLine)!.lowerBound < day.text.range(of: laterLine)!.lowerBound,
                   "Individual manual events export chronologically even when supplied in reverse order")
        try expect(!day.text.contains("Confirmed paste") && day.text.components(separatedBy: "Paste destination:").count == 3,
                   "Export preserves manual attribution without inventing a confirmed paste or collapsing separate events")
        let plannedDay = DayExportDocument.make(captures: store.captures,
            selectedDate: iso.date(from: "2026-10-04T12:00:00Z")!, now: now, calendarTimeZone: zone)
        try expect(plannedDay.isEmpty && capture.captureDay == "2026-09-30", "Scheduling and recording use never move a capture into the planned day's export")

        guard let folder = store.archiveURL(for: capture) else { throw CaptureStoreError.importVerificationFailed }
        let privateMarkdownURL = folder.appendingPathComponent("Capture.md")
        let projectMarkdownURL = try store.explorerDayURL(project: capture.projectName, day: capture.captureDay)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let sidecar = try decoder.decode(CaptureSnapshot.self, from: Data(contentsOf: folder.appendingPathComponent("Capture.json")))
        try expect(sidecar.pasteHistory == [later, earlier] && sidecar.taskPlanning == capture.taskPlanning,
                   "The readable JSON sidecar preserves exact event identity/order and complete focus/planning metadata")
        for url in [privateMarkdownURL, projectMarkdownURL] {
            let document = try String(contentsOf: url, encoding: .utf8)
            try expect(document.contains(earlierLine) && document.contains(laterLine)
                       && document.range(of: earlierLine)!.lowerBound < document.range(of: laterLine)!.lowerBound,
                       "Both readable Markdown archives retain every manual paste in chronological order")
            try expect(document.contains("Planned local time: 09:45")
                       && document.contains("Focus remaining at last transition: 00:25:00")
                       && document.contains("Source URL: https://example.invalid/feedback"),
                       "Both archives retain focus state, local work time and actual supplied source location")
        }
        let privateBeforeFailure = try Data(contentsOf: privateMarkdownURL)
        let projectBeforeFailure = try Data(contentsOf: projectMarkdownURL)
        store.failureInjector = { if $0 == .beforeMetadataSave { throw CaptureStoreError.importVerificationFailed } }
        try rejects({ _ = try store.recordPasteDestination(for: capture, applicationName: "Unsaved destination") },
                    "Failed receipt saves cannot be reported as successful archive updates")
        try expect(try Data(contentsOf: privateMarkdownURL) == privateBeforeFailure
                   && Data(contentsOf: projectMarkdownURL) == projectBeforeFailure,
                   "A failed receipt leaves both readable archives byte-for-byte unchanged")
        store.failureInjector = nil
        try store.removePasteDestination(earlier.id, from: capture)
        for url in [privateMarkdownURL, projectMarkdownURL] {
            let document = try String(contentsOf: url, encoding: .utf8)
            try expect(!document.contains(earlierLine) && document.contains(laterLine),
                       "Removing a manual event regenerates both archives while retaining the other event")
        }
        let reopened = try CaptureStore(root: root)
        let restored = reopened.captures.first { $0.id == capture.id }!
        try expect(restored.pasteHistory == [later] && restored.taskPlanning == capture.taskPlanning,
                   "The revised history and complete planning survive reopening")

        let target = "https://example.invalid/link-target"
        let plainLink = try store.capture(text: target, at: time, timeZone: zone)[0]
        guard let linkFolder = store.archiveURL(for: plainLink) else { throw CaptureStoreError.importVerificationFailed }
        let linkDaily = try store.explorerDayURL(project: nil, day: plainLink.captureDay)
        for url in [linkFolder.appendingPathComponent("Capture.md"), linkDaily] {
            let document = try String(contentsOf: url, encoding: .utf8)
            try expect(document.contains("Captured link: \(target)") && !document.contains("Source URL: \(target)"),
                       "Readable exports keep a plain copied link without misrepresenting its target as a proven origin")
        }
    }
}
