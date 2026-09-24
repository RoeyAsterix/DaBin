import Foundation

@MainActor
private final class ConversionReminderClient: ReminderNotificationClient {
    var requests: [String: ScheduledReminder] = [:]
    func authorization() async -> ReminderAuthorization { .allowed }
    func requestAuthorization() async throws -> Bool {
        fatalError("Conversion QA must never request real notification permission")
    }
    func pending() async -> [ScheduledReminder] { Array(requests.values) }
    func add(_ reminder: ScheduledReminder) async throws { requests[reminder.identifier] = reminder }
    func removePending(_ identifiers: [String]) { identifiers.forEach { requests.removeValue(forKey: $0) } }
    func removeDelivered(_ identifiers: [String]) {}
}

/// Every archive, reminder client and clipboard writer is private to this run.
@main
struct CaptureTaskConversionTests {
    @MainActor private static var checks = 0

    @MainActor
    private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        if try !condition() {
            throw NSError(domain: "CaptureTaskConversionTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    @MainActor
    private static func rejected(_ action: () throws -> Void, _ message: String) throws {
        var failed = false
        do { try action() } catch { failed = true }
        try expect(failed, message)
    }

    private static func date(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: value)!
    }

    /// Compare every persisted field except the intended conversion and edit time.
    private static func preservedFields(_ capture: Capture) throws -> Data {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(CaptureSnapshot(capture))) as! [String: Any]
        for key in ["convertedToTask", "updatedAt", "schemaVersion"] { object.removeValue(forKey: key) }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    @MainActor
    private static func state(for store: CaptureStore, client: ConversionReminderClient? = nil) -> AppState {
        AppState(store: store, previews: PreviewService(store: store),
                 reminders: ReminderService(store: store, client: client ?? ConversionReminderClient()),
                 captureClipboard: CaptureClipboardService { _ in true })
    }

    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinConversionQA-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try await preserveOriginals(root.appendingPathComponent("originals"))
        try legacyPayloads()
        try rollbackAndIdentity(root.appendingPathComponent("transactions"))
        try await detailAndPageState(root.appendingPathComponent("state"))
        try await taskMembership(root.appendingPathComponent("membership"))
        try await groupingAndExports(root.appendingPathComponent("grouping"))
        try await promotedAutomaticOrder(root.appendingPathComponent("promoted-order"))
        print("PASS: \(checks) capture-to-task checks; originals, legacy data, persistence, atomic failure, drafts, routes, filters, carryover, reminders and receipt exports.")
    }

    @MainActor private static func preserveOriginals(_ root: URL) async throws {
        var store: CaptureStore? = try CaptureStore(root: root)
        let stamp = date("2024-01-02 10:20")
        let provenance = CaptureSource(filePath: "/Fictional/Source/notes.txt", url: "https://example.invalid/source")
        let receipt = CaptureReceiptContext.automatic(.automaticClipboard,
            sourceApplicationName: "Fixture Notes", sourceApplicationBundleIdentifier: "com.dabin.fixture.notes")
        let note = try store!.capture(text: "  Exact copied words ✨\nincluding newlines  ", at: stamp,
                                      source: provenance, receipt: receipt)[0]
        let link = try store!.capture(text: "https://example.invalid/research?q=original", at: stamp,
                                      source: provenance)[0]
        var fixtures = [note, link]
        let imageBytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j8ocAAAAASUVORK5CYII=")!
        for filename in ["notes.txt", "brief.pdf", "photo.png", "clip.mp4", "design.ai", "payload.bin"] {
            let source = root.appendingPathComponent(filename)
            try (filename == "photo.png" ? imageBytes : Data("Original \(filename)".utf8)).write(to: source)
            fixtures.append(try await store!.importFile(source, at: stamp))
        }
        let reminder = Date().addingTimeInterval(7_200)
        let clipboard = CaptureClipboardService { _ in true }
        var snapshots: [UUID: Data] = [:]
        var payloads: [UUID: CaptureClipboardPayload] = [:]
        var archives: [UUID: URL] = [:]
        var originalBytes: [UUID: Data] = [:]
        for capture in fixtures {
            capture.previewDescription = "Preview context for \(capture.kind.rawValue)"
            capture.previewState = "ready"
            capture.previewError = nil
            try store!.update(capture, comment: "Keep this comment", reminderAt: reminder,
                              reminderTimeZoneID: TimeZone.current.identifier)
            let before = try preservedFields(capture)
            let payload = try clipboard.payload(for: [capture], managedURL: store!.managedURL(for:))
            let archive = store!.archiveURL(for: capture)!
            if let url = store!.managedURL(for: capture) { originalBytes[capture.id] = try Data(contentsOf: url) }
            try expect(!capture.isTask && !capture.convertedToTask, "Every source kind begins as an ordinary capture")
            try store!.convertToTask(capture)
            try expect(capture.isTask && capture.convertedToTask && !capture.isCompleted,
                       "Converting \(capture.kind.rawValue) creates an open task on the original record")
            try expect(try preservedFields(capture) == before,
                       "Conversion preserves every original, receipt, source, preview, comment and reminder field")
            try expect(try clipboard.payload(for: [capture], managedURL: store!.managedURL(for:)) == payload,
                       "Converted \(capture.kind.rawValue) retains its original clipboard representation")
            try expect(store!.archiveURL(for: capture) == archive,
                       "Conversion keeps the original dated archive location")
            snapshots[capture.id] = before
            payloads[capture.id] = payload
            archives[capture.id] = archive
        }
        try expect(Set(fixtures.map(\.kind)) == Set([.text, .link, .document, .pdf, .image, .video, .ai, .file]),
                   "Every supported original content kind remains available for its existing preview renderer")
        let ids = Set(fixtures.map(\.id))
        store = nil
        let reopened = try CaptureStore(root: root)
        try expect(Set(reopened.captures.map(\.id)) == ids, "Conversion never duplicates or replaces saved capture identities")
        for capture in reopened.captures {
            try expect(capture.isTask && capture.convertedToTask && !capture.isCompleted,
                       "An open converted task survives store reopening")
            try expect(try preservedFields(capture) == snapshots[capture.id], "All preserved fields survive store reopening")
            try expect(try clipboard.payload(for: [capture], managedURL: reopened.managedURL(for:)) == payloads[capture.id],
                       "Original clipboard payload survives store reopening")
            try expect(reopened.archiveURL(for: capture) == archives[capture.id], "Original archive path survives store reopening")
            if let bytes = originalBytes[capture.id], let url = reopened.managedURL(for: capture) {
                try expect(try Data(contentsOf: url) == bytes, "Converted attachment bytes remain intact")
            }
        }
    }

    @MainActor private static func legacyPayloads() throws {
        for kind in [CaptureKind.text, .task] {
            let capture = Capture(kind: kind, originalText: "Legacy \(kind.rawValue)", title: "Legacy")
            capture.isCompleted = true
            var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(CaptureSnapshot(capture))) as! [String: Any]
            object.removeValue(forKey: "convertedToTask")
            object["schemaVersion"] = 4
            let snapshot = try JSONDecoder().decode(CaptureSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
            let restored = Capture(snapshot: snapshot)
            try expect(!restored.convertedToTask, "Older payloads without the conversion flag decode safely")
            try expect(restored.isTask == (kind == .task), "Older native tasks stay tasks and ordinary captures stay ordinary")
            try expect(restored.isCompleted == (kind == .task), "Legacy completion is valid only for a task")
        }
    }

    @MainActor private static func rollbackAndIdentity(_ root: URL) throws {
        var store: CaptureStore? = try CaptureStore(root: root)
        let capture = try store!.capture(text: "Do not lose this capture")[0]
        let initial = try JSONEncoder().encode(CaptureSnapshot(capture))
        let initialArchive = try Data(contentsOf: store!.archiveURL(for: capture)!.appendingPathComponent("Capture.json"))
        store!.failureInjector = { if $0 == .beforeMetadataSave { throw CaptureStoreError.importVerificationFailed } }
        try rejected({ try store!.convertToTask(capture) }, "Metadata failure is surfaced to the conversion caller")
        try expect(!capture.isTask && !capture.convertedToTask, "A failed conversion restores the ordinary capture state")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let initialSnapshot = try JSONDecoder().decode(CaptureSnapshot.self, from: initial)
        try expect(try encoder.encode(CaptureSnapshot(capture)) == encoder.encode(initialSnapshot),
                   "A failed conversion restores every field including updatedAt")
        try expect(try Data(contentsOf: store!.archiveURL(for: capture)!.appendingPathComponent("Capture.json")) == initialArchive,
                   "A failed conversion leaves the archived metadata untouched")
        store = nil
        store = try CaptureStore(root: root)
        let current = store!.captures[0]
        try expect(!current.isTask, "Failed conversion never leaks into durable metadata")
        let clone = Capture(snapshot: CaptureSnapshot(current))
        try rejected({ try store!.convertToTask(clone) }, "A stale clone sharing a current ID cannot convert the live record")
        try expect(!current.isTask, "Rejected stale conversion preserves the current object")
        try store!.convertToTask(current)
        try store!.setTaskCompleted(current, completed: true)
        let saved = try encoder.encode(CaptureSnapshot(current))
        store!.failureInjector = { if $0 == .beforeMetadataSave { throw CaptureStoreError.importVerificationFailed } }
        try store!.convertToTask(current)
        try expect(try encoder.encode(CaptureSnapshot(current)) == saved,
                   "Repeated conversion is a no-op that keeps completion and does not attempt a metadata write")
        let taskClone = Capture(snapshot: CaptureSnapshot(current))
        try rejected({ try store!.convertToTask(taskClone) }, "Already-task stale clones are still rejected before idempotence")
        store!.failureInjector = nil
        _ = try store!.remove(current)
        try rejected({ try store!.convertToTask(current) }, "Deleted captures cannot be revived by conversion")
        try expect(store!.captures.isEmpty, "Stale conversion creates no replacement record")
    }

    @MainActor private static func detailAndPageState(_ root: URL) async throws {
        let store = try CaptureStore(root: root)
        let client = ConversionReminderClient()
        let app = state(for: store, client: client)
        let capture = try store.capture(text: "Detail conversion keeps draft")[0]
        let savedReminder = Date().addingTimeInterval(7_200)
        try store.update(capture, comment: "Saved context", reminderAt: savedReminder,
                         reminderTimeZoneID: TimeZone.current.identifier)
        await app.reminders.saveReminder(for: capture)
        let notificationID = ReminderService.identifier(capture.id)
        app.route = .weekly
        app.openCapture(capture.id, focus: "comment")
        let draft = app.selectedDraft!
        draft.comment = "Unsaved comment stays in editor"
        draft.reminderDate = savedReminder.addingTimeInterval(3_600)
        app.dailyScrollID = .capture(.capture(capture.id))
        let layout = app.captureLayoutRevision
        let navigation = app.captureNavigationRevision
        app.convertToTask(capture)
        try expect(capture.isTask && app.status?.severity == .success, "App state immediately saves conversion and reports success")
        try expect(app.route == .detail && app.selectedCapture === capture && app.selectedDraft === draft,
                   "Conversion keeps the open detail and its original draft object")
        try expect(draft.comment == "Unsaved comment stays in editor" && draft.reminderDate == savedReminder.addingTimeInterval(3_600)
                   && draft.hasChanges && app.detailFocus == "comment",
                   "Conversion preserves unsaved comment and reminder edits and editor focus")
        try expect(capture.comment == "Saved context" && capture.reminderAt == savedReminder,
                   "Task conversion does not silently commit unrelated editor drafts")
        try expect(app.captureLayoutRevision > layout && app.captureNavigationRevision == navigation
                   && app.dailyScrollID == .capture(.capture(capture.id)),
                   "Task conversion refreshes layout without navigating or discarding scroll position")
        try expect(client.requests[notificationID] != nil, "Conversion keeps the existing scheduled reminder")
        app.back()
        try expect(app.route == .weekly, "Leaving converted details returns to the original page")

        for route in [BoardRoute.daily, .weekly, .search, .reminders] {
            let item = try store.capture(text: "Convert on \(route)")[0]
            app.route = route
            let oldDay = app.selectedDay
            app.convertToTask(item)
            try expect(item.isTask && app.route == route && app.selectedDay == oldDay,
                       "Page conversion preserves the active \(route) page and selected date")
        }
        let failed = try store.capture(text: "Keep unsaved details after failure")[0]
        app.openCapture(failed.id)
        let failedDraft = app.selectedDraft!
        failedDraft.comment = "Still editing"
        let failedLayout = app.captureLayoutRevision
        store.failureInjector = { if $0 == .beforeMetadataSave { throw CaptureStoreError.importVerificationFailed } }
        app.convertToTask(failed)
        try expect(!failed.isTask && app.status?.severity == .error, "App state reports failure without showing task success")
        try expect(app.route == .detail && app.selectedDraft === failedDraft && failedDraft.comment == "Still editing"
                   && failedDraft.hasChanges && app.captureLayoutRevision == failedLayout,
                   "Failed conversion preserves the page, draft and layout revision")
        store.failureInjector = nil
    }

    @MainActor private static func taskMembership(_ root: URL) async throws {
        var store: CaptureStore? = try CaptureStore(root: root)
        let item = try store!.capture(text: "https://example.invalid/converted-task", at: date("2024-01-01 10:00"))[0]
        let note = try store!.capture(text: "An ordinary selected-day note", at: date("2024-01-02 18:00"))[0]
        try store!.convertToTask(item)
        let app = state(for: store!)
        app.selectedDay = date("2024-01-02 12:00")
        app.filter = .tasks
        try expect(app.dailyCaptures.map(\.id) == [item.id] && app.isTaskAtTop(item),
                   "The Tasks filter includes a converted capture carried to the next day")
        app.filter = .all
        try expect(app.dailyCaptures.map(\.id) == [item.id, note.id], "Converted carryover appears above ordinary selected-day content")
        app.filter = .links
        try expect(app.dailyCaptures.map(\.id) == [item.id], "Converted links also remain available in their original content filter")
        app.filter = .tasks
        app.query = "converted-task"
        try expect(app.searchGroups.count == 1 && app.searchGroups[0].day == "2024-01-01"
                   && app.searchGroups[0].entries.filter(\.isMatch).map(\.id) == [item.id],
                   "Task-filtered search finds a converted link under its immutable capture date")
        app.selectedDay = date("2023-12-31 12:00")
        try expect(app.dailyCaptures.isEmpty, "A converted task never appears before its capture day")
        try store!.update(item, comment: "Planned context", reminderAt: date("2024-01-03 11:00"),
                          reminderTimeZoneID: TimeZone.current.identifier)
        app.selectedDay = date("2024-01-02 12:00")
        try expect(app.dailyCaptures.isEmpty, "A reminder suppresses converted-task carryover before the reminder day")
        app.selectedDay = date("2024-01-03 12:00")
        try expect(app.dailyCaptures.map(\.id) == [item.id] && app.isTaskAtTop(item),
                   "A converted task with a reminder is promoted on its reminder date")
        app.selectedDay = date("2024-01-04 12:00")
        try expect(app.dailyCaptures.isEmpty, "A reminded converted task does not keep carrying beyond its scheduled date")
        app.selectedDay = date("2024-01-03 12:00")
        app.toggleTaskCompletion(item)
        await app.reminders.reconcile()
        try expect(item.isCompleted && app.dailyCaptures.isEmpty, "Completion removes a converted task from its reminder-day promotion")
        app.selectedDay = date("2024-01-01 12:00")
        try expect(app.dailyCaptures.map(\.id) == [item.id] && !app.isTaskAtTop(item),
                   "Completed converted tasks remain visible on their original capture day")
        let reopened = try CaptureStore(root: root)
        let restored = reopened.captures.first { $0.id == item.id }!
        try expect(restored.isTask && restored.isCompleted && restored.kind == .link,
                   "Completion survives reopening while keeping the link original")
        app.toggleTaskCompletion(item)
        await app.reminders.reconcile()
        app.selectedDay = date("2024-01-03 12:00")
        try expect(!item.isCompleted && app.dailyCaptures.map(\.id) == [item.id],
                   "Reopening a converted task restores its existing reminder-day behavior")
        store = nil
    }

    @MainActor private static func groupingAndExports(_ root: URL) async throws {
        let store = try CaptureStore(root: root)
        let stamp = date("2024-01-02 10:00")
        let first = try await store.importData(Data("First original".utf8), filename: "first.txt", at: stamp)
        let second = try await store.importData(Data("Second original".utf8), filename: "second.txt", at: stamp)
        try expect(CaptureCardGroup.cards(from: [first, second]).count == 1,
                   "Same-receipt imported attachments begin as one file card")
        try store.convertToTask(first)
        let visualCards = CaptureCardGroup.cards(from: [first, second])
        try expect(visualCards.count == 2 && visualCards.allSatisfy { $0.captures.count == 1 },
                   "A converted attachment receives its own task card outside its original file batch")
        let day = DayExportDocument.make(captures: [first, second], selectedDate: stamp,
                                         now: date("2024-01-03 12:00"))
        try expect(day.actionCount == 1 && day.text.contains("Items: 2")
                   && day.text.contains("first.txt") && day.text.contains("second.txt"),
                   "Visual task separation preserves one receipt action with both originals in day export")
        try expect(day.text.contains("Type: Document") && day.text.contains("Status: Task"),
                   "Export preserves original content type and adds explicit task status")
        let week = WeekExportDocument.make(captures: [first, second], weekEndingDate: stamp,
                                           now: date("2024-01-03 12:00"))
        try expect(week.actionCount == 1 && week.text.contains("Items: 2"),
                   "Week export also retains original multi-file receipt grouping")
        var automatic: [Capture] = []
        for index in 0..<5 {
            let receipt = CaptureReceiptContext.automatic(.automaticClipboard,
                sourceApplicationName: "Fixture Notes", sourceApplicationBundleIdentifier: "com.dabin.fixture")
            automatic.append(try store.capture(text: "Automatic action \(index)",
                at: stamp.addingTimeInterval(Double(index * 60)), receipt: receipt)[0])
        }
        let promoted = automatic[0]
        try store.convertToTask(promoted)
        let feed = HourlyCaptureFeed.cards(from: automatic, filter: .all, today: stamp)
        let hours = feed.compactMap { card -> AutomaticHourGroup? in
            if case .automaticHour(let group) = card { return group }; return nil
        }
        let independent = feed.compactMap { card -> CaptureCardGroup? in
            if case .capture(let group) = card { return group }; return nil
        }
        try expect(hours.count == 1 && hours[0].totalActionCount == 5 && hours[0].visibleActionCount == 4
                   && !hours[0].captures.contains { $0.id == promoted.id },
                   "Remaining automatic actions retain the original receipt count without absorbing the converted task")
        try expect(independent.count == 1 && independent[0].captures.map(\.id) == [promoted.id],
                   "An automatic capture converted to a task stays independently actionable")
        let taskFeed = HourlyCaptureFeed.cards(from: automatic, filter: .tasks, today: stamp)
        try expect(taskFeed.count == 1 && taskFeed.flatMap(\.captures).map(\.id) == [promoted.id],
                   "The Tasks feed displays a converted automatic capture directly")
        let automaticExport = DayExportDocument.make(captures: automatic, selectedDate: stamp,
                                                     now: date("2024-01-03 12:00"))
        try expect(automaticExport.actionCount == 5
                   && automaticExport.text.components(separatedBy: "Title: Automatic action").count == 6,
                   "Conversion preserves all automatic receipt actions exactly once in export")
        let carriedExport = DayExportDocument.make(captures: automatic, selectedDate: date("2024-01-03 12:00"),
                                                   now: date("2024-01-04 12:00"))
        try expect(carriedExport.isEmpty, "Carried converted tasks are exported only on their actual receipt date")
    }

    @MainActor private static func promotedAutomaticOrder(_ root: URL) async throws {
        // Model the selected day as today without depending on the wall clock.
        let today = date("2024-01-02 10:00")
        let reminder = date("2024-01-02 12:00")
        let singleStore = try CaptureStore(root: root.appendingPathComponent("single-actions"))
        var singles: [Capture] = []
        for index in 0..<4 {
            singles.append(try singleStore.capture(text: "Single automatic action \(index)",
                at: today.addingTimeInterval(Double(index * 60)),
                receipt: .automatic(.automaticClipboard))[0])
        }
        let promoted = singles[0]
        try singleStore.convertToTask(promoted)
        try singleStore.update(promoted, comment: "Due on the selected day", reminderAt: reminder,
                               reminderTimeZoneID: TimeZone.current.identifier)
        let singleState = state(for: singleStore)
        singleState.selectedDay = today
        try expect(singleState.allCapturesForDay.first?.id == promoted.id && singleState.isTaskAtTop(promoted),
                   "AppState promotes an older converted automatic capture above newer same-hour captures on its reminder day")
        let singleFeed = HourlyCaptureFeed.cards(from: singleState.allCapturesForDay, filter: .all, today: today)
        try expect(singleFeed.count == 2 && singleFeed.first?.id == .capture(.capture(promoted.id)),
                   "A promoted automatic task is the first independent card, before its original hour summary")
        guard singleFeed.count == 2, case .automaticHour(let singleHour) = singleFeed[1] else {
            throw NSError(domain: "CaptureTaskConversionTests", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "The remaining automatic-hour summary must follow the promoted task"])
        }
        try expect(singleHour.totalActionCount == 4 && singleHour.visibleActionCount == 3
                   && singleHour.captures.count == 3 && !singleHour.captures.contains { $0.id == promoted.id },
                   "Promoting one of four automatic actions retains a three-of-four summary without duplicating the task")
        try expect(singleFeed.flatMap(\.captures).count == 4
                   && Set(singleFeed.flatMap(\.captures).map(\.id)) == Set(singles.map(\.id)),
                   "Promotion preserves all four saved actions exactly once in the feed")

        let mixedStore = try CaptureStore(root: root.appendingPathComponent("mixed-action"))
        let sharedReceipt = CaptureReceiptContext.automatic(.automaticClipboard)
        let taskFile = try await mixedStore.importData(Data("Task file original".utf8), filename: "task.txt",
                                                       at: today, receipt: sharedReceipt)
        let normalFile = try await mixedStore.importData(Data("Sibling file original".utf8), filename: "sibling.txt",
                                                         at: today, receipt: sharedReceipt)
        var mixedCaptures = [taskFile, normalFile]
        for index in 1...3 {
            mixedCaptures.append(try mixedStore.capture(text: "Other automatic action \(index)",
                at: today.addingTimeInterval(Double(index * 60)),
                receipt: .automatic(.automaticClipboard))[0])
        }
        try mixedStore.convertToTask(taskFile)
        try mixedStore.update(taskFile, comment: "One attachment needs action today", reminderAt: reminder,
                              reminderTimeZoneID: TimeZone.current.identifier)
        let mixedState = state(for: mixedStore)
        mixedState.selectedDay = today
        try expect(mixedState.allCapturesForDay.first?.id == taskFile.id && mixedState.isTaskAtTop(taskFile),
                   "AppState promotes one converted file from a multi-file automatic action to the first position")
        let mixedFeed = HourlyCaptureFeed.cards(from: mixedState.allCapturesForDay, filter: .all, today: today)
        try expect(mixedFeed.count == 2 && mixedFeed.first?.id == .capture(.capture(taskFile.id)),
                   "A mixed automatic action cannot place its hour summary before its promoted task member")
        guard mixedFeed.count == 2, case .automaticHour(let mixedHour) = mixedFeed[1] else {
            throw NSError(domain: "CaptureTaskConversionTests", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "The mixed-action summary must follow its promoted task member"])
        }
        try expect(mixedHour.totalActionCount == 4 && mixedHour.visibleActionCount == 4
                   && mixedHour.captures.contains { $0.id == normalFile.id }
                   && !mixedHour.captures.contains { $0.id == taskFile.id },
                   "The non-task sibling remains in its shared automatic action while the task is independently actionable")
        try expect(mixedFeed.flatMap(\.captures).count == 5
                   && Set(mixedFeed.flatMap(\.captures).map(\.id)) == Set(mixedCaptures.map(\.id)),
                   "Mixed-action promotion preserves every file and other action exactly once")
    }
}
