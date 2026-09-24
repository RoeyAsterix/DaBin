import Foundation

private struct FixtureEntry: Decodable {
    let id: String
    let day: String
    let capturedAt: String
    let zone: String
    let kind: CaptureKind
    let title: String
    let original: String
    let description: String
    let comment: String
}
private struct FixtureExpected: Decodable {
    struct Item: Decodable { let id: String; let match: Bool }
    let day: String
    let hits: Int
    let items: [Item]
}
private struct FixtureCase: Decodable {
    let name: String
    let query: String
    let filter: String
    let entries: [FixtureEntry]?
    let expected: [FixtureExpected]
}
private struct Fixtures: Decodable { let entries: [FixtureEntry]; let cases: [FixtureCase] }

@main struct DomainTests {
    @MainActor static var checks = 0
    @MainActor static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        if try !value() { throw NSError(domain: "DaBinTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static func date(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let value = formatter.date(from: string) { return value }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)!
    }
    static func fixtureID(_ value: String) -> UUID {
        UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012x", value.unicodeScalars.first!.value))")!
    }
    @MainActor private static func from(_ entry: FixtureEntry) -> Capture {
        let capture = Capture(id: fixtureID(entry.id), capturedAt: date(entry.capturedAt),
                              timeZone: TimeZone(identifier: entry.zone)!, kind: entry.kind,
                              originalURL: entry.kind == .link ? entry.original : nil,
                              originalText: entry.kind == .text ? entry.original : nil,
                              title: entry.title, captureDay: entry.day)
        capture.previewDescription = entry.description
        capture.comment = entry.comment
        return capture
    }

    @MainActor private static func checkTasksFilterAndSearch() throws {
        try expect(CaptureFilter.tasks.includes(.task), "Tasks filter accepts explicit tasks")
        for kind in CaptureKind.allCases where kind != .task {
            try expect(!CaptureFilter.tasks.includes(kind), "Tasks filter excludes \(kind.rawValue) captures")
        }
        let zone = TimeZone(secondsFromGMT: 0)!
        func item(_ stamp: String, _ kind: CaptureKind, _ title: String) -> Capture {
            Capture(capturedAt: date(stamp), timeZone: zone, kind: kind, title: title)
        }
        let previousDate = item("2024-01-01T23:59:00Z", .text, "Review previous-day note")
        let before = item("2024-01-02T09:00:00Z", .link, "Review supporting link")
        let openTask = item("2024-01-02T10:00:00Z", .task, "Review open task")
        let between = item("2024-01-02T11:00:00Z", .pdf, "Review reference PDF")
        let completedTask = item("2024-01-02T12:00:00Z", .task, "Review completed task")
        completedTask.isCompleted = true
        let after = item("2024-01-02T13:00:00Z", .image, "Review supporting image")
        let excluded = item("2024-01-02T14:00:00Z", .text, "Review unrelated note")
        let nextDate = item("2024-01-03T00:01:00Z", .document, "Review next-day document")
        let captures = [nextDate, completedTask, before, previousDate, excluded, openTask, between, after]
        let groups = CaptureSearch.groups(captures: captures, query: "Review", filter: .tasks)
        try expect(groups.map(\.day) == ["2024-01-02"], "Tasks search includes only dates with matching explicit tasks")
        try expect(groups.first?.entries.map(\.id) == [before.id, openTask.id, between.id, completedTask.id, after.id],
                   "Tasks search keeps immediate chronological neighbors, merging shared context without duplicates")
        try expect(groups.first?.entries.filter(\.isMatch).map(\.id) == [openTask.id, completedTask.id],
                   "Open and completed tasks both match while neighboring matching text remains context only")
        try expect(groups.first?.entries.map(\.isMatch) == [false, true, false, true, false],
                   "Links, PDFs and media remain visibly contextual even when their titles contain the search query")
        try expect(CaptureSearch.groups(captures: captures, query: "unrelated note", filter: .tasks).isEmpty,
                   "A query matching only an ordinary note produces no task-filtered result")
    }

    @MainActor private static func checkTextFilterAndSearch() throws {
        try expect(CaptureFilter.allCases == [.all, .text, .links, .files, .media, .tasks],
                   "Text filter is immediately before Links in the visible filter order")
        try expect(CaptureFilter.text.includes(.text), "Text filter accepts plain-text captures")
        for kind in CaptureKind.allCases where kind != .text {
            try expect(!CaptureFilter.text.includes(kind), "Text filter excludes \(kind.rawValue) captures")
        }
        let zone = TimeZone(secondsFromGMT: 0)!
        func item(_ stamp: String, _ kind: CaptureKind, _ title: String) -> Capture {
            Capture(capturedAt: date(stamp), timeZone: zone, kind: kind, title: title)
        }
        let before = item("2024-01-02T09:00:00Z", .link, "Text filter context link")
        let copiedText = item("2024-01-02T10:00:00Z", .text, "Copied planning text")
        let after = item("2024-01-02T11:00:00Z", .document, "Text filter context document")
        let matchingTask = item("2024-01-02T12:00:00Z", .task, "Copied planning task")
        let groups = CaptureSearch.groups(captures: [matchingTask, after, copiedText, before],
                                          query: "Copied planning", filter: .text)
        try expect(groups.first?.entries.map(\.id) == [before.id, copiedText.id, after.id],
                   "Text search keeps one chronological neighbor on each side of its text match")
        try expect(groups.first?.entries.filter(\.isMatch).map(\.id) == [copiedText.id],
                   "Text search excludes matching tasks while retaining surrounding context")
    }

    @MainActor private static func checkDateScopedSearch() throws {
        let zone = TimeZone(secondsFromGMT: 0)!
        func item(_ stamp: String, day: String, kind: CaptureKind = .text,
                  title: String) -> Capture {
            Capture(capturedAt: date(stamp), timeZone: zone, kind: kind,
                    title: title, captureDay: day,
                    captureTimeZoneID: zone.identifier, captureUTCOffsetSeconds: 0)
        }

        let outsideBefore = item("2026-12-27T23:59:00Z", day: "2026-12-27",
                                 title: "Needle before week")
        let decemberHit = item("2026-12-31T12:00:00Z", day: "2026-12-31",
                               title: "Needle in December")
        let dayBefore = item("2027-01-01T08:00:00Z", day: "2027-01-01",
                             title: "Same-day context before")
        let januaryHit = item("2027-01-01T09:00:00Z", day: "2027-01-01",
                              title: "Needle on New Year")
        let dayAfter = item("2027-01-01T10:00:00Z", day: "2027-01-01",
                            title: "Same-day context after")
        let linkHit = item("2027-01-02T11:00:00Z", day: "2027-01-02", kind: .link,
                           title: "Needle link")
        let finalHit = item("2027-01-03T12:00:00Z", day: "2027-01-03",
                            title: "Needle at week end")
        let outsideAfter = item("2027-01-04T00:01:00Z", day: "2027-01-04",
                                title: "Needle after week")
        let captures = [outsideAfter, linkHit, dayAfter, decemberHit, outsideBefore,
                        januaryHit, finalHit, dayBefore]

        let weekDays = Set(["2026-12-28", "2026-12-29", "2026-12-30", "2026-12-31",
                            "2027-01-01", "2027-01-02", "2027-01-03"])
        let dayScope = CaptureSearchScope.day("2027-01-01")
        let weekScope = CaptureSearchScope.week(weekDays)
        try expect(CaptureSearchScope.all.includes(captureDay: "1900-01-01")
                   && dayScope.includes(captureDay: "2027-01-01")
                   && !dayScope.includes(captureDay: "2026-12-31")
                   && weekScope.includes(captureDay: "2026-12-31")
                   && !weekScope.includes(captureDay: "2027-01-04"),
                   "Search scopes expose stable stored-day membership across a year boundary")

        let dayGroups = CaptureSearch.groups(captures: captures, query: "needle",
                                             filter: .all, scope: dayScope)
        try expect(dayGroups.map(\.day) == ["2027-01-01"],
                   "Day search cannot leak matches from adjacent calendar days")
        try expect(dayGroups[0].entries.map(\.id) == [dayBefore.id, januaryHit.id, dayAfter.id]
                   && dayGroups[0].entries.map(\.isMatch) == [false, true, false],
                   "Day search preserves one-before and one-after context inside its selected date")

        let weekGroups = CaptureSearch.groups(captures: captures, query: "needle",
                                              filter: .all, scope: weekScope)
        try expect(weekGroups.map(\.day) == ["2027-01-03", "2027-01-02", "2027-01-01", "2026-12-31"],
                   "Week search uses exact day keys and retains newest-day-first group ordering")
        try expect(!weekGroups.flatMap(\.entries).contains { $0.id == outsideBefore.id || $0.id == outsideAfter.id },
                   "Week search excludes both dates immediately outside its fixed seven days")

        let filteredWeek = CaptureSearch.groups(captures: captures, query: "needle",
                                                filter: .text, scope: weekScope)
        try expect(!filteredWeek.map(\.day).contains("2027-01-02"),
                   "Content filters still decide matches within a date-scoped search")
        let defaultGroups = CaptureSearch.groups(captures: captures, query: "needle", filter: .all)
        let explicitAllGroups = CaptureSearch.groups(captures: captures, query: "needle",
                                                     filter: .all, scope: .all)
        try expect(defaultGroups.map(\.day) == explicitAllGroups.map(\.day)
                   && defaultGroups.flatMap(\.entries).map(\.id)
                   == explicitAllGroups.flatMap(\.entries).map(\.id),
                   "The default API preserves archive-wide search behavior")
        try expect(CaptureSearch.groups(captures: captures, query: "needle", filter: .all,
                                       scope: .week([])).isEmpty,
                   "An empty week scope produces no search results")
    }

    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinDomainTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixturePath = CommandLine.arguments.dropFirst().first ?? "DaBin/native/Handoff/implementation/search-cases.json"
        let fixtures = try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: URL(fileURLWithPath: fixturePath)))
        for fixture in fixtures.cases {
            let captures = (fixture.entries ?? fixtures.entries).map(from)
            let groups = CaptureSearch.groups(captures: captures, query: fixture.query, filter: CaptureFilter(rawValue: fixture.filter)!)
            try expect(groups.count == fixture.expected.count, "\(fixture.name): group count")
            for (group, expected) in zip(groups, fixture.expected) {
                try expect(group.day == expected.day, "\(fixture.name): group date")
                try expect(group.entries.filter(\.isMatch).count == expected.hits, "\(fixture.name): hit count")
                try expect(group.entries.map(\.id) == expected.items.map { fixtureID($0.id) }, "\(fixture.name): chronological IDs and context")
                try expect(group.entries.map(\.isMatch) == expected.items.map(\.match), "\(fixture.name): match flags")
            }
        }
        try expect(CaptureClassifier.textKind("  https://example.test/a?q=1  ") == .link, "HTTP URL classification")
        try expect(CaptureClassifier.textKind("HTTP://example.test") == .link, "URL scheme case")
        for text in ["file:///etc/passwd", "javascript:alert(1)", "https://", "a note https://example.test", "https://example.test\nanother line"] {
            try expect(CaptureClassifier.textKind(text) == .text, "Unsafe or mixed input remains text: \(text)")
        }
        let fileCases: [(String, CaptureKind)] = [("A.PNG", .image), ("v.webm", .video), ("p.pdf", .pdf),
                                                  ("project.ai", .ai), ("readme.md", .document), ("deck.pptx", .document),
                                                  ("unknown.xyz", .file), ("noextension", .file)]
        for (name, kind) in fileCases { try expect(CaptureClassifier.fileKind(filename: name) == kind, "File kind for \(name)") }
        try expect(CaptureFilter.files.includes(.ai) && !CaptureFilter.files.includes(.text), "File filter scope")
        try expect(CaptureFilter.media.includes(.image) && CaptureFilter.media.includes(.video), "Media filter scope")
        try checkTextFilterAndSearch()
        try checkTasksFilterAndSearch()
        try checkDateScopedSearch()
        let newYork = TimeZone(identifier: "America/New_York")!
        let beforeDST = date("2026-11-01T05:30:00Z")
        let afterDST = date("2026-11-01T06:30:00Z")
        try expect(CaptureCalendar.dayString(beforeDST, timeZone: newYork) == "2026-11-01", "DST first repeated hour day")
        try expect(CaptureCalendar.dayString(afterDST, timeZone: newYork) == "2026-11-01", "DST second repeated hour day")
        try expect(newYork.secondsFromGMT(for: beforeDST) != newYork.secondsFromGMT(for: afterDST), "DST receipt offsets differ")
        try expect(CaptureCalendar.dayString(date("2026-01-01T00:30:00Z"), timeZone: TimeZone(identifier: "America/Los_Angeles")!) == "2025-12-31", "Receipt local year boundary")

        let storeRoot = root.appendingPathComponent("reopen")
        var store: CaptureStore? = try CaptureStore(root: storeRoot)
        let receipt = date("2026-09-20T23:59:59Z")
        let zone = TimeZone(identifier: "Asia/Jerusalem")!
        let raw = "  personal note\nverbatim  "
        let text = try store!.capture(text: raw, at: receipt, timeZone: zone)[0]
        let immutable = (text.id, text.capturedAt, text.captureDay, text.captureTimeZoneID, text.captureUTCOffsetSeconds)
        try expect(text.originalText == raw, "Verbatim text preservation")
        try expect(text.sourceFilePath == nil && text.sourceURL == nil, "Plain text does not invent a source")
        let attributedSource = CaptureSource(filePath: "/Users/example/Documents/notes.txt", url: "https://example.test/notes")
        let sourcedText = try store!.capture(text: "An exported excerpt", source: attributedSource)[0]
        try expect(sourcedText.sourceFilePath == attributedSource.filePath && sourcedText.sourceURL == attributedSource.url, "Explicit source metadata retained")
        let automaticActionID = UUID()
        let automatic = try store!.capture(text: "Copied planning note", at: receipt, timeZone: zone,
            receipt: .automatic(.automaticClipboard, actionID: automaticActionID,
                                sourceApplicationName: "Notes",
                                sourceApplicationBundleIdentifier: "com.apple.Notes"))[0]
        try expect(automatic.captureOrigin == .automaticClipboard
                   && automatic.automaticActionID == automaticActionID
                   && automatic.sourceApplicationName == "Notes"
                   && automatic.sourceApplicationBundleIdentifier == "com.apple.Notes",
                   "Automatic capture receipt retains action identity and source application")
        try expect(CaptureSearch.groups(captures: [automatic], query: "copied notes", filter: .all).first != nil,
                   "Automatic origin and source application are searchable")
        var legacyPayload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(CaptureSnapshot(sourcedText))) as! [String: Any]
        legacyPayload.removeValue(forKey: "sourceFilePath")
        legacyPayload.removeValue(forKey: "sourceURL")
        legacyPayload.removeValue(forKey: "captureOriginRaw")
        legacyPayload.removeValue(forKey: "automaticActionID")
        legacyPayload.removeValue(forKey: "sourceApplicationName")
        legacyPayload.removeValue(forKey: "sourceApplicationBundleIdentifier")
        legacyPayload["schemaVersion"] = 1
        let legacySnapshot = try JSONDecoder().decode(CaptureSnapshot.self, from: JSONSerialization.data(withJSONObject: legacyPayload))
        let legacyCapture = Capture(snapshot: legacySnapshot)
        try expect(legacyCapture.originalText == sourcedText.originalText && legacyCapture.sourceFilePath == nil
                   && legacyCapture.sourceURL == nil && legacyCapture.captureOrigin == .manual
                   && legacyCapture.automaticActionID == nil,
                   "Version 1 payload migrates with unknown source and manual origin")
        for version in [1, 2] {
            var payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(CaptureSnapshot(sourcedText))) as! [String: Any]
            payload["schemaVersion"] = version
            payload.removeValue(forKey: "isCompleted")
            let snapshot = try JSONDecoder().decode(CaptureSnapshot.self, from: JSONSerialization.data(withJSONObject: payload))
            let migrated = Capture(snapshot: snapshot)
            try expect(!migrated.isTask && !migrated.isCompleted && migrated.originalText == sourcedText.originalText,
                       "Version \(version) missing task status decodes as an unchanged ordinary capture")
        }

        let taskRoot = root.appendingPathComponent("tasks")
        let taskStore = try CaptureStore(root: taskRoot)
        let taskReminder = Date().addingTimeInterval(7200)
        let task = try taskStore.createTask(text: "  Send studio brief\n ", reminderAt: taskReminder,
                                           reminderTimeZoneID: "Asia/Jerusalem", at: receipt, timeZone: zone)
        let taskStamp = (task.id, task.capturedAt, task.captureDay, task.captureTimeZoneID, task.captureUTCOffsetSeconds)
        try expect(task.isTask && !task.isCompleted && task.originalText == "Send studio brief" && task.title == "Send studio brief", "Explicit task keeps trimmed task text and defaults to open")
        try expect(task.reminderAt == taskReminder && task.reminderTimeZoneID == "Asia/Jerusalem" && task.reminderRevision == 1, "Task and initial reminder commit together")
        try expect(CaptureSnapshot(task).schemaVersion == 6, "Capture snapshots use schema 6")
        try expect(CaptureFilter.all.includes(.task) && !CaptureFilter.text.includes(.task) && !CaptureFilter.files.includes(.task) && !CaptureFilter.links.includes(.task) && !CaptureFilter.media.includes(.task), "Tasks appear in All without changing text/file/link/media filters")
        try expect(CaptureSearch.groups(captures: [task], query: "studio brief", filter: .all).first?.entries.first?.id == task.id, "Task text is searchable")
        try taskStore.setTaskCompleted(task, completed: true)
        let completedRevision = task.reminderRevision
        try expect(task.isCompleted && task.notificationState == "completed" && task.reminderAt == taskReminder, "Completion preserves the historical reminder while invalidating its schedule")
        try taskStore.setTaskCompleted(task, completed: true)
        try expect(task.reminderRevision == completedRevision, "Repeated completion is a no-op")
        let taskReopenStore = try CaptureStore(root: taskRoot)
        let reopenedTask = taskReopenStore.captures.first { $0.id == task.id }!
        try expect(reopenedTask.isTask && reopenedTask.isCompleted && reopenedTask.reminderAt == taskReminder, "Completed status and reminder survive relaunch")
        try taskReopenStore.setTaskCompleted(reopenedTask, completed: false)
        try expect(!reopenedTask.isCompleted && reopenedTask.notificationState == "pending" && reopenedTask.reminderRevision == completedRevision + 1, "Reopening preserves desired reminder and creates a new schedule revision")
        try expect(reopenedTask.id == taskStamp.0 && reopenedTask.capturedAt == taskStamp.1 && reopenedTask.captureDay == taskStamp.2 && reopenedTask.captureTimeZoneID == taskStamp.3 && reopenedTask.captureUTCOffsetSeconds == taskStamp.4 && reopenedTask.originalText == "Send studio brief", "Completion and reopening preserve every receipt field and task text")
        let reopenedAgain = try CaptureStore(root: taskRoot).captures.first { $0.id == task.id }!
        try expect(!reopenedAgain.isCompleted && reopenedAgain.reminderRevision == reopenedTask.reminderRevision, "Reopened task status survives relaunch")
        let urlTask = try taskReopenStore.createTask(text: "https://example.test/to-do")
        try expect(urlTask.isTask && urlTask.originalURL == nil && urlTask.reminderAt == nil && urlTask.reminderTimeZoneID == nil, "Explicit URL task remains a task; reminders are optional")
        let ordinary = try taskReopenStore.capture(text: "Regular capture")[0]
        try taskReopenStore.setTaskCompleted(ordinary, completed: true)
        try expect(!ordinary.isCompleted && ordinary.kind == .text && ordinary.reminderRevision == 0, "Ordinary captures cannot become completed tasks")
        let countBeforeRejectedTasks = taskReopenStore.captures.count
        do { _ = try taskReopenStore.createTask(text: " \n "); throw NSError(domain: "Expected empty task rejection", code: 1) }
        catch CaptureStoreError.emptyInput { checks += 1 }
        do { _ = try taskReopenStore.createTask(text: "Past task", reminderAt: Date().addingTimeInterval(-1)); throw NSError(domain: "Expected past reminder rejection", code: 1) }
        catch CaptureStoreError.reminderNotFuture { checks += 1 }
        taskReopenStore.failureInjector = { if $0 == .beforeMetadataSave { throw NSError(domain: "Task write failure", code: 1) } }
        do { _ = try taskReopenStore.createTask(text: "Must not appear", reminderAt: taskReminder); throw NSError(domain: "Expected task write rejection", code: 1) }
        catch let error as NSError where error.domain == "Task write failure" { checks += 1 }
        let statusBeforeFailure = (reopenedTask.isCompleted, reopenedTask.reminderRevision, reopenedTask.notificationState, reopenedTask.updatedAt)
        do { try taskReopenStore.setTaskCompleted(reopenedTask, completed: true); throw NSError(domain: "Expected status write rejection", code: 1) }
        catch let error as NSError where error.domain == "Task write failure" { checks += 1 }
        try expect(reopenedTask.isCompleted == statusBeforeFailure.0 && reopenedTask.reminderRevision == statusBeforeFailure.1 && reopenedTask.notificationState == statusBeforeFailure.2 && reopenedTask.updatedAt == statusBeforeFailure.3, "Failed completion rolls back all mutable task status")
        taskReopenStore.failureInjector = nil
        try expect(taskReopenStore.captures.count == countBeforeRejectedTasks && (try CaptureStore(root: taskRoot)).captures.count == countBeforeRejectedTasks, "Rejected and failed tasks leave no partial records on disk")
        try expect(text.captureDay == "2026-09-21", "Local capture day retained")
        let reminder = date("2030-01-01T09:00:00Z")
        try store!.update(text, comment: "Revisit", reminderAt: reminder, reminderTimeZoneID: "Europe/London")
        try expect(text.reminderRevision == 1 && text.notificationState == "pending", "Reminder revision increments")
        try store!.update(text, comment: "Comment only", reminderAt: reminder, reminderTimeZoneID: "Europe/London")
        try expect(text.reminderRevision == 1, "Comment-only edit keeps reminder revision")
        try store!.update(text, comment: "Keep", reminderAt: nil, reminderTimeZoneID: "Europe/London")
        try expect(text.reminderRevision == 2 && text.reminderTimeZoneID == nil, "Clear reminder increments and clears zone")
        try expect(text.id == immutable.0 && text.capturedAt == immutable.1 && text.captureDay == immutable.2 &&
                   text.captureTimeZoneID == immutable.3 && text.captureUTCOffsetSeconds == immutable.4, "Edits preserve all immutable receipt fields")
        let urlBatch = try store!.capture(text: " https://first.example/a \n\nhttps://second.example/b", at: receipt, timeZone: zone)
        try expect(urlBatch.count == 2 && urlBatch.allSatisfy { $0.kind == .link }, "URL-only lines become individual links")
        try expect(urlBatch.map(\.originalURL) == ["https://first.example/a", "https://second.example/b"], "URL lines preserve entered links")
        try expect(urlBatch.map(\.sourceURL) == urlBatch.map(\.originalURL), "URL captures retain their own link as source")
        try expect(urlBatch.allSatisfy { $0.capturedAt == receipt && $0.captureDay == "2026-09-21" }, "URL batch shares immutable intake stamp")
        let mixed = "https://first.example/a\nA note about this link"
        let prose = try store!.capture(text: mixed)
        try expect(prose.count == 1 && prose[0].kind == .text && prose[0].originalText == mixed, "Mixed URL and prose stays one verbatim capture")
        let source = root.appendingPathComponent("source.pdf")
        let payload = Data("independent managed original".utf8)
        try payload.write(to: source)
        let attachment = try await store!.importFile(source, at: receipt, timeZone: zone, originalName: "../../source.pdf")
        let attachmentID = attachment.id
        try expect(attachment.originalFilename == "../../source.pdf", "Display filename preserved")
        try expect(attachment.sourceFilePath == source.standardizedFileURL.path, "Original source path is independent of display filename")
        try expect(attachment.byteCount == Int64(payload.count), "Verified attachment byte count")
        let managed = store!.managedURL(for: attachment)!
        try expect(attachment.sourceFilePath != managed.path, "Managed copy never replaces original source path")
        try expect(managed.path.hasPrefix(store!.root.appendingPathComponent("Archive").path + "/"), "Managed path contained")
        try expect(!managed.lastPathComponent.contains("/"), "Sanitized storage leaf")
        let duplicate = try await store!.importFile(source)
        try expect(duplicate.id != attachment.id && duplicate.attachmentRelativePath != attachment.attachmentRelativePath, "Equal filenames never overwrite")
        try FileManager.default.removeItem(at: source)
        store = nil
        store = try CaptureStore(root: storeRoot)
        let reopened = store!.captures.first { $0.id == attachmentID }!
        try expect(try Data(contentsOf: store!.managedURL(for: reopened)!) == payload, "Reopen original after external source deletion")
        try expect(reopened.sourceFilePath == source.standardizedFileURL.path, "Original source path survives relaunch and source deletion")
        let reopenedSourcedText = store!.captures.first { $0.id == sourcedText.id }!
        try expect(reopenedSourcedText.sourceFilePath == attributedSource.filePath && reopenedSourcedText.sourceURL == attributedSource.url, "Text provenance survives relaunch")
        let reopenedText = store!.captures.first { $0.id == immutable.0 }!
        try expect(reopenedText.captureDay == immutable.2 && reopenedText.captureTimeZoneID == immutable.3 && reopenedText.comment == "Keep", "Reopen immutable day and edits")
        let firstCount = store!.captures.count
        do { _ = try store!.capture(text: " \n "); throw NSError(domain: "Expected rejection", code: 1) }
        catch CaptureStoreError.emptyInput { checks += 1 }
        do { _ = try await store!.importFile(root); throw NSError(domain: "Expected directory rejection", code: 1) }
        catch CaptureStoreError.directoryNotSupported { checks += 1 }
        let link = root.appendingPathComponent("external-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: managed)
        do { _ = try await store!.importFile(link); throw NSError(domain: "Expected symlink rejection", code: 1) }
        catch CaptureStoreError.symbolicLinkNotSupported { checks += 1 }
        try expect(store!.captures.count == firstCount, "Rejected inputs create no records")

        for checkpoint in ImportCheckpoint.allCases.filter({ $0 != .afterMetadataSave }) {
            let failureRoot = root.appendingPathComponent("failure-\(checkpoint.rawValue)")
            let failureStore = try CaptureStore(root: failureRoot)
            let existing = try failureStore.capture(text: "Existing capture")[0]
            failureStore.failureInjector = { stage in
                if stage == checkpoint { throw NSError(domain: "Injected I/O failure", code: 1) }
            }
            do {
                _ = try await failureStore.importData(payload, filename: "same.txt")
                throw NSError(domain: "Expected import failure", code: 1)
            } catch let failure as NSError where failure.domain == "Injected I/O failure" { checks += 1 }
            try failureStore.refresh()
            try expect(failureStore.captures.map(\.id) == [existing.id], "\(checkpoint): failure preserves other captures")
            for folder in ["Originals", "Staging", "Imports"] {
                let files = try FileManager.default.contentsOfDirectory(atPath: failureRoot.appendingPathComponent(folder).path)
                try expect(files.isEmpty, "\(checkpoint): cleans owned \(folder)")
            }
        }
        let committedStore = try CaptureStore(root: root.appendingPathComponent("post-commit"))
        committedStore.failureInjector = { if $0 == .afterMetadataSave { throw NSError(domain: "Post-commit cleanup", code: 1) } }
        let committed = try await committedStore.importData(payload, filename: "kept.txt")
        try expect(committedStore.captures.contains { $0.id == committed.id }, "Post-commit housekeeping error does not report a lost capture")

        for checkpoint in ImportCheckpoint.allCases {
            let recoveryRoot = root.appendingPathComponent("recovery-\(checkpoint.rawValue)")
            var interrupted: CaptureStore? = try CaptureStore(root: recoveryRoot)
            interrupted!.failureInjector = { if $0 == checkpoint { throw CaptureStoreError.injectedInterruption } }
            do { _ = try await interrupted!.importData(payload, filename: "original.bin", at: receipt, timeZone: zone, source: attributedSource) }
            catch CaptureStoreError.injectedInterruption { checks += 1 }
            interrupted = nil
            let recovered = try CaptureStore(root: recoveryRoot)
            if checkpoint == .beforeCopy {
                try expect(recovered.captures.isEmpty && recovered.error != nil, "Incomplete copy preserved with recovery warning")
                try expect(!(try FileManager.default.contentsOfDirectory(atPath: recoveryRoot.appendingPathComponent("Imports").path)).isEmpty, "Incomplete journal preserved")
            } else {
                try expect(recovered.captures.count == 1, "\(checkpoint): recovery commits exactly one capture")
                let recoveredCapture = recovered.captures[0]
                try expect(recoveredCapture.capturedAt == receipt && recoveredCapture.captureDay == "2026-09-21", "\(checkpoint): recovery retains receipt stamp")
                try expect(recoveredCapture.sourceFilePath == attributedSource.filePath && recoveredCapture.sourceURL == attributedSource.url, "\(checkpoint): recovery retains source metadata")
                try expect(try Data(contentsOf: recovered.managedURL(for: recoveredCapture)!) == payload, "\(checkpoint): recovery retains bytes")
                let secondOpen = try CaptureStore(root: recoveryRoot)
                try expect(secondOpen.captures.count == 1, "\(checkpoint): recovery is idempotent")
            }
        }
        // Recovery journals written by v1 have no provenance keys.
        let legacyJournalRoot = root.appendingPathComponent("legacy-journal")
        var legacyJournalStore: CaptureStore? = try CaptureStore(root: legacyJournalRoot)
        legacyJournalStore!.failureInjector = { if $0 == .afterCopy { throw CaptureStoreError.injectedInterruption } }
        do { _ = try await legacyJournalStore!.importData(payload, filename: "legacy.txt", source: attributedSource) }
        catch CaptureStoreError.injectedInterruption { }
        let journalURL = try FileManager.default.contentsOfDirectory(at: legacyJournalRoot.appendingPathComponent("Imports"), includingPropertiesForKeys: nil)[0]
        var journal = try JSONSerialization.jsonObject(with: Data(contentsOf: journalURL)) as! [String: Any]
        journal.removeValue(forKey: "sourceFilePath"); journal.removeValue(forKey: "sourceURL")
        try JSONSerialization.data(withJSONObject: journal).write(to: journalURL)
        legacyJournalStore = nil
        let recoveredLegacy = try CaptureStore(root: legacyJournalRoot)
        try expect(recoveredLegacy.captures.count == 1, "Version 1 import journal still recovers")
        try expect(recoveredLegacy.captures[0].sourceFilePath == nil && recoveredLegacy.captures[0].sourceURL == nil, "Version 1 journal does not infer provenance from staging")
        let damagedRoot = root.appendingPathComponent("damaged-staging")
        var damaged: CaptureStore? = try CaptureStore(root: damagedRoot)
        damaged!.failureInjector = { if $0 == .afterCopy { throw CaptureStoreError.injectedInterruption } }
        do { _ = try await damaged!.importData(payload, filename: "original.bin") }
        catch CaptureStoreError.injectedInterruption { }
        let stagedFolders = try FileManager.default.contentsOfDirectory(at: damagedRoot.appendingPathComponent("Staging"), includingPropertiesForKeys: nil)
        let stagedFile = stagedFolders[0].appendingPathComponent("original.bin")
        try Data("tampered".utf8).write(to: stagedFile)
        damaged = nil
        let damagedReopen = try CaptureStore(root: damagedRoot)
        try expect(damagedReopen.captures.isEmpty && damagedReopen.error != nil, "Failed recovery verification creates no false card")
        try expect(FileManager.default.fileExists(atPath: stagedFile.path), "Ambiguous original retained for recovery")
        let corruptRoot = root.appendingPathComponent("corrupt-store")
        try FileManager.default.createDirectory(at: corruptRoot, withIntermediateDirectories: true)
        let corruptURL = corruptRoot.appendingPathComponent("metadata.store")
        let corruptData = Data("this is deliberately not a database".utf8)
        try corruptData.write(to: corruptURL)
        var rejectedCorruption = false
        do { _ = try CaptureStore(root: corruptRoot) } catch { rejectedCorruption = true }
        try expect(rejectedCorruption, "Corrupt database initialization fails")
        try expect(try Data(contentsOf: corruptURL) == corruptData, "Corrupt database is never silently replaced")
        print("PASS: \(checks) assertions; \(fixtures.cases.count) search fixtures; managed-copy reopen, immutable dates, import compensation and interruption recovery.")
    }
}
