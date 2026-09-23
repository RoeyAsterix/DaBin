import AppKit
import Foundation
import ImageIO
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// Native NSHostingView renders of production views and an isolated real persistent store.
/// These are view snapshots, not screen captures or end-to-end interaction tests.
@MainActor
private final class RenderNotificationClient: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .undetermined }
    func requestAuthorization() async throws -> Bool { fatalError("Render QA must never request notification permission") }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { fatalError("Render QA must never schedule a notification") }
    func removePending(_ identifiers: [String]) {}
    func removeDelivered(_ identifiers: [String]) {}
}

@MainActor
private final class BoredRobotMotionState: ObservableObject {
    @Published var isActive = true
}

@MainActor
private struct RobotMotionFixture: View {
    @ObservedObject var state: BoredRobotMotionState
    var body: some View {
        BoredRobotView(isActive: state.isActive)
            .frame(width: 128, height: 156)
    }
}

@main
@MainActor
private final class NativeRenderTests: NSObject, NSApplicationDelegate {
    private var result = 0
    private var retainedWindows: [NSWindow] = []
    private var records: [[String: Any]] = []
    private var renderTheme: ThemeSettings!

    static func main() {
        let application = NSApplication.shared
        let delegate = NativeRenderTests()
        application.setActivationPolicy(.prohibited)
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
        exit(Int32(delegate.result))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await run() }
            catch {
                result = 1
                fputs("Native render QA failed: \(error)\n", stderr)
            }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }

    private func run() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let previewFitOnly = arguments.contains("--preview-fit")
        let themeOnly = arguments.contains("--theme")
        let robotPersonalityOnly = arguments.contains("--robot-personality")
        let output = URL(fileURLWithPath: arguments.first(where: { !$0.hasPrefix("--") }) ?? "DaBin/native/build/qa/screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinNativeRender-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let themeSuite = "DaBin.NativeRender.Theme.\(UUID().uuidString)"
        guard let themeDefaults = UserDefaults(suiteName: themeSuite) else {
            throw RenderError.message("Could not create isolated theme preferences")
        }
        renderTheme = ThemeSettings(defaults: themeDefaults)
        defer { themeDefaults.removePersistentDomain(forName: themeSuite) }
        let preference = UserDefaults.standard.object(forKey: PreviewService.linkPreviewPreference)
        UserDefaults.standard.set(false, forKey: PreviewService.linkPreviewPreference)
        defer {
            if let preference { UserDefaults.standard.set(preference, forKey: PreviewService.linkPreviewPreference) }
            else { UserDefaults.standard.removeObject(forKey: PreviewService.linkPreviewPreference) }
        }

        if robotPersonalityOnly {
            let manifest = try await verifyRobotPersonality(output: output)
            try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("robot-personality-renders.json"), options: .atomic)
            let screenshotCount = (manifest["screenshots"] as? [[String: Any]])?.count ?? 0
            print("PASS: \(screenshotCount) native 2x robot personality renders with raster, motion, Reduce Motion and cleanup checks")
            return
        }

        if arguments.contains("--release-ui") {
            try await renderReleaseUI(root: root, output: output)
            let robotPersonality = try await verifyRobotPersonality(output: output)
            try JSONSerialization.data(withJSONObject: [
                "description": "Refactored production screens at compact application sizes, in light and dark appearance, with selected 2x bitmap renders and native robot personality states.",
                "fixturePrivacy": "Fictional isolated archive and theme preferences; no clipboard access, network requests, notification delivery, or personal captures.",
                "robotPersonality": robotPersonality,
                "screenshots": records
            ], options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("release-ui-renders.json"), options: .atomic)
            print("PASS: \(records.count) release UI renders, including compact and 2x samples")
            return
        }

        if themeOnly {
            try await renderThemes(root: root, output: output, theme: renderTheme)
            let manifest: [String: Any] = [
                "description": "Production Settings, Daily and capture detail views rendered with six theme presets and a custom colour, in both appearances.",
                "fixturePrivacy": "Fictional local-only Core Data records and isolated theme preferences; no user captures, clipboard reads, network or notification scheduling.",
                "defaultLogicalSize": ["width": 380, "height": 430],
                "systemAppearanceChanged": false,
                "screenshots": records
            ]
            try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("theme-renders.json"), options: .atomic)
            print("PASS: \(records.count) native theme renders from isolated production views and persistent fixtures. Output: \(output.path)")
            return
        }

        if previewFitOnly {
            try await renderPreviewFit(root: root, output: output)
            let manifest: [String: Any] = [
                "description": "Production preview views rendered with deliberately tall and wide local fixtures. Four coloured corner markers must remain visible in every raster image and document thumbnail preview.",
                "fixturePrivacy": "Fictional local-only fixtures; no network, clipboard reads, notification permission prompts or user captures.",
                "documentThumbnail": "Synthetic cached page thumbnail: tests the document preview presentation, not Quick Look generation.",
                "PDFRasterLimitation": "PDFKit page tiles are omitted by NSView.cacheDisplay, including when the isolated test window is on screen. PDF renders verify surrounding layout only; page fitting requires separate native PDFView geometry checks.",
                "screenshots": records
            ]
            try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("preview-fit-renders.json"), options: .atomic)
            print("PASS: \(records.count) preview-fit renders; all four corner markers visible in 16 image/document renders. 8 PDF renders are layout only because NSView.cacheDisplay omits PDFKit page tiles. Output: \(output.path)")
            return
        }

        if arguments.contains("--weekly-empty") {
            let store = try CaptureStore(root: root.appendingPathComponent("EmptyWeek"))
            let state = AppState(store: store, previews: PreviewService(store: store),
                                 reminders: ReminderService(store: store, client: RenderNotificationClient()))
            for mode in ["light", "dark"] {
                state.openDaily()
                try await snapshot(state, name: "weekly-entry-empty-daily", mode: mode, output: output, height: 290)
                state.selectTimelineMode(.weekly)
                guard state.route == .weekly, state.weeklyDays.count == 7,
                      state.weeklyDays.allSatisfy({ state.captures(for: $0).isEmpty }) else {
                    throw RenderError.message("Empty Daily/Weekly toggle must still open seven days")
                }
                try await snapshot(state, name: "weekly-entry-empty-week", mode: mode, output: output, height: 560, width: 1440)
                state.filter = .tasks
                try await snapshot(state, name: "weekly-entry-empty-tasks", mode: mode, output: output, height: 560, width: 1440)
                try await snapshot(state, name: "weekly-entry-empty-narrow", mode: mode, output: output, height: 560, width: 800)
            }
            try JSONSerialization.data(withJSONObject: ["screenshots": records,
                "fixturePrivacy": "Empty isolated archive; no personal captures, clipboard, network or notifications."],
                options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("weekly-entry-renders.json"), options: .atomic)
            print("PASS: \(records.count) empty Daily/Week renders across both appearances and a narrow display")
            return
        }

        if arguments.contains("--recovery-guidance") {
            let store = try CaptureStore(root: root.appendingPathComponent("RecoveryGuidance"))
            let failedLink = try store.capture(text: "https://example.invalid/offline-reference")[0]
            failedLink.previewState = "unavailable"
            failedLink.previewError = "Website preview unavailable. The saved link is available."
            let pastTask = try store.createTask(text: "Revisit the studio reference")
            try store.update(pastTask, comment: "", reminderAt: Date().addingTimeInterval(-3600),
                             reminderTimeZoneID: TimeZone.current.identifier)
            pastTask.notificationState = "past"
            let futureTask = try store.createTask(text: "Review the colour samples", reminderAt: Date().addingTimeInterval(3600))
            futureTask.notificationState = "failed"
            try store.save()
            let state = AppState(store: store, previews: PreviewService(store: store),
                                 reminders: ReminderService(store: store, client: RenderNotificationClient()))
            for mode in ["light", "dark"] {
                state.openCapture(failedLink.id)
                try await snapshot(state, name: "recovery-preview-error", mode: mode, output: output)
                state.openCapture(pastTask.id, focus: "reminder")
                try await snapshot(state, name: "recovery-reminder-past", mode: mode, output: output, scrollToBottom: true)
                state.openCapture(futureTask.id, focus: "reminder")
                try await snapshot(state, name: "recovery-reminder-retry", mode: mode, output: output, scrollToBottom: true)
            }
            try JSONSerialization.data(withJSONObject: ["screenshots": records,
                "fixturePrivacy": "Fictional isolated archive; no clipboard, website fetches or notification scheduling.",
                "review": "Check preview failure explanation; expired reminders offer future-time guidance and no retry; failed future reminders retain retry."],
                options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("recovery-guidance-renders.json"), options: .atomic)
            print("PASS: \(records.count) recovery guidance renders in light and dark appearances")
            return
        }

        if arguments.contains("--capture-actions") {
            let store = try CaptureStore(root: root.appendingPathComponent("CaptureActions"))
            let today = Calendar.current.startOfDay(for: Date())
            func day(_ offset: Int) -> Date { Calendar.current.date(byAdding: .day, value: offset, to: today)! }
            let note = try store.capture(text: "Review the workshop notes and keep the quiet violet details consistent across every reference board.", at: day(-3).addingTimeInterval(8 * 3600))[0]
            try store.update(note, comment: "A longer note to test the compact capture controls.", reminderAt: nil, reminderTimeZoneID: nil)
            let picture = try await store.importData(Self.fixturePNG(), filename: "Workshop materials and purple colour references.png", at: day(-2).addingTimeInterval(8 * 3600))
            try store.update(picture, comment: "Keep every original corner visible in the preview.", reminderAt: nil, reminderTimeZoneID: nil)
            let task = try store.createTask(text: "Review the studio reference collection before the afternoon workshop", reminderAt: Date().addingTimeInterval(3600), at: day(0).addingTimeInterval(8 * 3600))
            let completed = try store.createTask(text: "Finish collecting the workshop materials and reference documents", at: day(-1).addingTimeInterval(8 * 3600))
            try store.setTaskCompleted(completed, completed: true)
            let link = try store.capture(text: "https://example.invalid/workshop-references", at: day(-4).addingTimeInterval(8 * 3600))[0]
            link.title = "Workshop reference ideas with a deliberately long descriptive title"
            link.previewState = "ready"
            _ = try store.capture(text: "Saved the first draft of the workshop plan", at: day(-5).addingTimeInterval(8 * 3600))
            _ = try store.capture(text: "Gathered the first set of materials", at: day(-6).addingTimeInterval(8 * 3600))
            try store.save()
            let previews = PreviewService(store: store)
            previews.process([picture])
            let deadline = Date().addingTimeInterval(8)
            while picture.previewState == "loading" && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
            guard picture.previewState == "ready" else { throw RenderError.message("Capture actions image preview did not finish") }
            let state = AppState(store: store, previews: previews,
                                 reminders: ReminderService(store: store, client: RenderNotificationClient()))
            let subjects: [(String, Capture, Date)] = [("note", note, day(-3)), ("media", picture, day(-2)),
                                                       ("task", task, day(0)), ("completed", completed, day(-1))]
            for mode in ["light", "dark"] {
                for (name, capture, selectedDay) in subjects {
                    state.openDaily()
                    state.selectedDay = selectedDay
                    try store.setMinimized(capture, minimized: false)
                    try await snapshot(state, name: "capture-actions-\(name)-expanded", mode: mode, output: output,
                                       height: CornerGeometry.dailyPanelHeight(for: state))
                    state.toggleMinimized(capture)
                    try await snapshot(state, name: "capture-actions-\(name)-minimized", mode: mode, output: output,
                                       height: CornerGeometry.dailyPanelHeight(for: state))
                    guard capture.isMinimized else { throw RenderError.message("Minimize action did not update production state") }
                }
                for capture in store.captures { try store.setMinimized(capture, minimized: false) }
                state.selectTimelineMode(.weekly)
                try await snapshot(state, name: "capture-actions-week-expanded", mode: mode, output: output, height: 560, width: 1440)
                for capture in store.captures { state.toggleMinimized(capture) }
                try await snapshot(state, name: "capture-actions-week-minimized", mode: mode, output: output, height: 560, width: 1440)
                try await snapshot(state, name: "capture-actions-week-narrow", mode: mode, output: output, height: 560, width: 900)
            }
            try JSONSerialization.data(withJSONObject: ["screenshots": records,
                "fixturePrivacy": "Fictional isolated archive; no clipboard, network contact, permission requests or notification scheduling.",
                "review": "Inspect long note, media, open and completed task cards before/after minimizing; action buttons, titles and time/status must remain readable; inspect full and narrow Week columns."],
                options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("capture-actions-renders.json"), options: .atomic)
            print("PASS: \(records.count) capture action renders in light and dark appearances")
            return
        }

        let store = try CaptureStore(root: root)
        let today = Calendar.current.startOfDay(for: Date())
        func receipt(_ hour: Int, _ minute: Int, dayOffset: Int = 0) -> Date {
            Calendar.current.date(byAdding: .day, value: dayOffset, to: today)!
                .addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
        }
        let before = try store.capture(text: "Morning desk reset", at: receipt(9, 12))[0]
        let match = try store.capture(text: "https://example.invalid/quiet-forms", at: receipt(9, 24))[0]
        match.title = "Quiet forms, thoughtful spaces"
        match.previewDescription = "A small collection of ideas for the studio."
        match.previewState = "ready"
        let after = try store.capture(text: "Try the warm grey palette", at: receipt(9, 31))[0]
        let sourceNote = try store.capture(text: "A passage from the studio brief.", at: receipt(11, 0),
            source: CaptureSource(filePath: "/Users/demo/Projects/Quiet Studio/Research/Studio brief.docx"))[0]
        let sourceDocument = try await store.importData(Data("Fictional studio workshop notes".utf8), filename: "Workshop notes.txt", at: receipt(11, 10),
            source: CaptureSource(filePath: "/Users/demo/Projects/Quiet Studio/Research/Workshop notes.txt"))
        let image = try await store.importData(Self.fixturePNG(), filename: "studio-materials.png", at: receipt(10, 5))
        image.title = "Studio materials"
        let completedTask = try store.createTask(text: "Collect the workshop references", reminderAt: Date().addingTimeInterval(3600),
            reminderTimeZoneID: TimeZone.current.identifier, at: receipt(12, 10))
        try store.setTaskCompleted(completedTask, completed: true)
        let activeTask = try store.createTask(text: "Review the studio brief", reminderAt: Date().addingTimeInterval(7200),
            reminderTimeZoneID: TimeZone.current.identifier, at: receipt(12, 20))
        let earlierBefore = try store.capture(text: "Drafted three layout options", at: receipt(14, 2, dayOffset: -2))[0]
        let earlier = try store.capture(text: "Keep the corner quiet and the materials simple.", at: receipt(14, 20, dayOffset: -2))[0]
        let earlierAfter = try store.capture(text: "Saved the final reference sheet", at: receipt(14, 39, dayOffset: -2))[0]
        try store.update(image, comment: "Use the soft violet as a small accent.", reminderAt: Date().addingTimeInterval(7200), reminderTimeZoneID: TimeZone.current.identifier)
        image.notificationState = "pending"
        try store.update(earlier, comment: "A useful reminder from the sketch session.", reminderAt: Date().addingTimeInterval(-3600), reminderTimeZoneID: TimeZone.current.identifier)
        earlier.notificationState = "past"
        try store.save()

        let previews = PreviewService(store: store)
        previews.process([image])
        let deadline = Date().addingTimeInterval(8)
        while image.previewState == "loading" && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        guard image.previewState == "ready" else { throw RenderError.message("Synthetic fixture thumbnail failed") }

        // Reopen the on-disk store to prove renders are driven by actual persistence.
        let reopened = try CaptureStore(root: root)
        guard reopened.captures.count == 11,
              let persistedImage = reopened.captures.first(where: { $0.id == image.id }),
              persistedImage.comment == image.comment else { throw RenderError.message("Real store relaunch verification failed") }
        let service = ReminderService(store: reopened, client: RenderNotificationClient())
        let state = AppState(store: reopened, previews: PreviewService(store: reopened), reminders: service)

        // Keep carryover fixtures separate so the ordinary empty and search renders stay meaningful.
        let carryoverRoot = root.appendingPathComponent("Carryover", isDirectory: true)
        let carryoverStore = try CaptureStore(root: carryoverRoot)
        let carriedTask = try carryoverStore.createTask(text: "Finish the workshop outline", at: receipt(16, 45, dayOffset: -2))
        let oldCompletedTask = try carryoverStore.createTask(text: "Send the finished reference sheet", at: receipt(14, 10, dayOffset: -1))
        try carryoverStore.setTaskCompleted(oldCompletedTask, completed: true)
        let todayTask = try carryoverStore.createTask(text: "Review the new colour samples", at: receipt(12, 20))
        let todayNote = try carryoverStore.capture(text: "A softer violet for the studio wall.", at: receipt(13, 5))[0]
        let carryoverReopened = try CaptureStore(root: carryoverRoot)
        let carryoverState = AppState(store: carryoverReopened, previews: PreviewService(store: carryoverReopened),
            reminders: ReminderService(store: carryoverReopened, client: RenderNotificationClient()))
        carryoverState.selectedDay = today
        guard carryoverState.dailyCaptures.map(\.id) == [carriedTask.id, todayNote.id, todayTask.id],
              carryoverState.isTaskAtTop(carryoverState.dailyCaptures[0]),
              !carryoverState.dailyCaptures.contains(where: { $0.id == oldCompletedTask.id }) else {
            throw RenderError.message("Carryover render fixture must show the old unfinished task first and exclude the old completed task")
        }

        // A reminder replaces daily carryover. Keep these receipts on distinct
        // local dates so the before, due and after boards prove the selection rule.
        let reminderDaysRoot = root.appendingPathComponent("ReminderDays", isDirectory: true)
        let reminderDaysStore = try CaptureStore(root: reminderDaysRoot)
        let unscheduledTask = try reminderDaysStore.createTask(text: "Finish the workshop outline", at: receipt(9, 0, dayOffset: -3))
        let reminderTask = try reminderDaysStore.createTask(text: "Review the scheduled studio brief", at: receipt(10, 0, dayOffset: -3))
        try reminderDaysStore.update(reminderTask, comment: "", reminderAt: receipt(14, 0, dayOffset: -1),
            reminderTimeZoneID: TimeZone.current.identifier)
        let reminderBeforeNote = try reminderDaysStore.capture(text: "Collected a few colour references.", at: receipt(11, 0, dayOffset: -2))[0]
        let reminderDayNote = try reminderDaysStore.capture(text: "Saved the latest studio sketch.", at: receipt(11, 0, dayOffset: -1))[0]
        let reminderAfterNote = try reminderDaysStore.capture(text: "A softer violet for the studio wall.", at: receipt(11, 0))[0]
        let reminderDaysReopened = try CaptureStore(root: reminderDaysRoot)
        let reminderDaysState = AppState(store: reminderDaysReopened, previews: PreviewService(store: reminderDaysReopened),
            reminders: ReminderService(store: reminderDaysReopened, client: RenderNotificationClient()))
        reminderDaysState.selectedDay = receipt(0, 0, dayOffset: -3)
        guard reminderDaysState.dailyCaptures.map(\.id) == [reminderTask.id, unscheduledTask.id],
              reminderDaysState.dailyCaptures.allSatisfy({ !reminderDaysState.isTaskAtTop($0) }) else {
            throw RenderError.message("A task with a later reminder must remain an ordinary creation-day record")
        }
        let reminderDayCases: [(name: String, offset: Int, expected: [UUID], promoted: Set<UUID>)] = [
            ("daily-reminder-before", -2, [unscheduledTask.id, reminderBeforeNote.id], [unscheduledTask.id]),
            ("daily-reminder-day", -1, [reminderTask.id, unscheduledTask.id, reminderDayNote.id], [reminderTask.id, unscheduledTask.id]),
            ("daily-reminder-after", 0, [unscheduledTask.id, reminderAfterNote.id], [unscheduledTask.id])
        ]

        let weeklyRoot = root.appendingPathComponent("Weekly", isDirectory: true)
        let weeklyStore = try CaptureStore(root: weeklyRoot)
        let weeklyTitles = ["A quieter workspace", "Notes from the first sketch", "Simplify the morning routine",
                            "Material samples to revisit", "Keep the layout light", "A few finishing details", "Ready for the next workshop"]
        for (index, title) in weeklyTitles.enumerated() {
            let capture = try weeklyStore.capture(text: title, at: receipt(9 + index, 12, dayOffset: index - 6))[0]
            if index == 1 {
                try weeklyStore.update(capture, comment: "Leave more breathing room around the edges.", reminderAt: nil, reminderTimeZoneID: nil)
            }
        }
        let weeklyLink = try weeklyStore.capture(text: "https://example.invalid/studio-inspiration", at: receipt(16, 10, dayOffset: -6))[0]
        weeklyLink.title = "Studio inspiration"
        _ = try await weeklyStore.importData(Data("Fictional workshop plan".utf8), filename: "Workshop plan.txt", at: receipt(14, 30, dayOffset: -4))
        let weeklyImage = try await weeklyStore.importData(Self.fixturePNG(), filename: "Material palette.png", at: receipt(16, 20, dayOffset: -3))
        let weeklyCompleted = try weeklyStore.createTask(text: "Collect the references", at: receipt(12, 10, dayOffset: -5))
        try weeklyStore.setTaskCompleted(weeklyCompleted, completed: true)
        let weeklyScheduled = try weeklyStore.createTask(text: "Review the workshop plan", at: receipt(11, 40, dayOffset: -2))
        try weeklyStore.update(weeklyScheduled, comment: "Bring the colour samples.", reminderAt: receipt(16, 0), reminderTimeZoneID: TimeZone.current.identifier)
        _ = try weeklyStore.createTask(text: "Finish the final outline", at: receipt(17, 10, dayOffset: -1))
        try weeklyStore.save()
        let weeklyPreviews = PreviewService(store: weeklyStore)
        weeklyPreviews.process([weeklyImage])
        let weeklyDeadline = Date().addingTimeInterval(8)
        while weeklyImage.previewState == "loading" && Date() < weeklyDeadline { try await Task.sleep(for: .milliseconds(20)) }
        guard weeklyImage.previewState == "ready" else { throw RenderError.message("Weekly fixture thumbnail failed") }
        let weeklyReopened = try CaptureStore(root: weeklyRoot)
        let weeklyState = AppState(store: weeklyReopened, previews: PreviewService(store: weeklyReopened),
            reminders: ReminderService(store: weeklyReopened, client: RenderNotificationClient()))

        for mode in ["light", "dark"] {
            weeklyState.selectedDay = today
            weeklyState.openWeekly()
            weeklyState.filter = .all
            weeklyState.weeklyExpansionDirection = mode == "light" ? .right : .left
            guard weeklyState.weeklyDays.count == 7,
                  weeklyState.weeklyDays.allSatisfy({ !weeklyState.captures(for: $0).isEmpty }) else {
                throw RenderError.message("Weekly overview fixture must contain seven populated days")
            }
            try await snapshot(weeklyState, name: "weekly-populated", mode: mode, output: output, height: 560, width: 1440)
            try await snapshot(weeklyState, name: "weekly-narrow", mode: mode, output: output, height: 560, width: 800)
            weeklyState.filter = .tasks
            guard weeklyState.weeklyDays.flatMap({ weeklyState.captures(for: $0) }).allSatisfy(\.isTask) else {
                throw RenderError.message("Weekly Tasks filter included another capture type")
            }
            try await snapshot(weeklyState, name: "weekly-tasks", mode: mode, output: output, height: 560, width: 1440)
            weeklyState.filter = .all
            weeklyState.weekEndingDay = receipt(0, 0, dayOffset: -14)
            try await snapshot(weeklyState, name: "weekly-empty", mode: mode, output: output, height: 560, width: 1440)
            try await snapshot(carryoverState, name: "daily-carried-tasks", mode: mode, output: output)
            for fixture in reminderDayCases {
                reminderDaysState.selectedDay = receipt(0, 0, dayOffset: fixture.offset)
                reminderDaysState.dailyScrollID = nil
                guard reminderDaysState.dailyCaptures.map(\.id) == fixture.expected,
                      Set(reminderDaysState.dailyCaptures.filter { reminderDaysState.isTaskAtTop($0) }.map(\.id)) == fixture.promoted else {
                    throw RenderError.message("Reminder-day membership or task promotion failed for \(fixture.name)")
                }
                try await snapshot(reminderDaysState, name: fixture.name, mode: mode, output: output)
            }
            state.status = nil
            state.selectedDay = today
            state.filter = .all
            state.route = .daily
            state.dailyScrollID = nil
            try await snapshot(state, name: "daily-populated", mode: mode, output: output)

            state.reportCaptureResult([], errors: ["This item did not provide readable content."])
            try await snapshot(state, name: "daily-capture-error", mode: mode, output: output)
            state.status = AppStatusMessage(text: "Reminder saved. Enable DaBin notifications in System Settings to receive alerts.", severity: .warning)
            try await snapshot(state, name: "daily-reminder-warning", mode: mode, output: output)
            state.status = nil

            state.filter = .media
            state.dailyScrollID = nil
            try await snapshot(state, name: "daily-media", mode: mode, output: output)

            state.filter = .files
            state.dailyScrollID = nil
            try await snapshot(state, name: "daily-files", mode: mode, output: output)

            state.filter = .tasks
            state.dailyScrollID = nil
            guard Set(state.dailyCaptures.map(\.id)) == Set([activeTask.id, completedTask.id]),
                  state.dailyCaptures.allSatisfy(\.isTask) else {
                throw RenderError.message("Tasks filter must show only the two original-day tasks, including completed tasks")
            }
            try await snapshot(state, name: "daily-tasks", mode: mode, output: output)
            state.route = .search
            state.query = "studio brief"
            state.searchScrollID = nil
            guard state.searchGroups.flatMap(\.entries).filter(\.isMatch).map(\.id) == [activeTask.id] else {
                throw RenderError.message("Task search must exclude ordinary text matches while retaining context")
            }
            try await snapshot(state, name: "search-tasks", mode: mode, output: output)
            state.route = .daily

            state.filter = .all
            state.selectedDay = Calendar.current.date(byAdding: .day, value: -1, to: today)!
            state.dailyScrollID = nil
            try await snapshot(state, name: "daily-empty", mode: mode, output: output)
            try await snapshot(state, name: "daily-empty-compact", mode: mode, output: output, height: 290)

            state.route = .search
            state.query = "quiet"
            state.filter = .all
            state.searchScrollID = nil
            let groups = state.searchGroups
            guard groups.count == 2,
                  groups.contains(where: { Set($0.entries.map(\.id)) == Set([before.id, match.id, after.id]) }),
                  groups.contains(where: { Set($0.entries.map(\.id)) == Set([earlierBefore.id, earlier.id, earlierAfter.id]) }) else {
                throw RenderError.message("Contextual search did not return the two expected matching days and neighbors")
            }
            try await snapshot(state, name: "search-context-top", mode: mode, output: output)
            state.searchScrollID = after.id
            try await snapshot(state, name: "search-context-after", mode: mode, output: output, scrollToBottom: true)

            state.openCapture(image.id)
            try await snapshot(state, name: "detail-top", mode: mode, output: output)
            state.detailFocus = "comment"
            try await snapshot(state, name: "detail-comment-reminder", mode: mode, output: output)

            state.openCapture(sourceNote.id)
            try await snapshot(state, name: "detail-text-source", mode: mode, output: output)
            state.openCapture(sourceDocument.id)
            try await snapshot(state, name: "detail-document-source", mode: mode, output: output, scrollToBottom: true)
            state.openCapture(before.id)
            try await snapshot(state, name: "detail-source-unavailable", mode: mode, output: output)

            state.openCapture(activeTask.id)
            try await snapshot(state, name: "detail-task-active", mode: mode, output: output)
            state.openCapture(completedTask.id)
            try await snapshot(state, name: "detail-task-completed", mode: mode, output: output)

            state.openNewTask()
            state.newTaskDraft.text = "Prepare the next workshop"
            try await snapshot(state, name: "new-task", mode: mode, output: output, height: 310)
            state.newTaskDraft.reminderEnabled = true
            try await snapshot(state, name: "new-task-reminder", mode: mode, output: output, height: 370)
            state.cancelNewTask()

            state.route = .reminders
            try await snapshot(state, name: "reminders", mode: mode, output: output)
            state.route = .settings
            try await snapshot(state, name: "settings", mode: mode, output: output)
        }
        let robotMotion = try await verifyRobotMotion(output: output)
        let robotPersonality = try await verifyRobotPersonality(output: output)
        let manifest: [String: Any] = [
            "description": "Native NSHostingView renders of production BoardView, AppState and services backed by a real isolated Core Data store. These are native-view renders, not screen captures.",
            "fixturePrivacy": "Fictional local-only fixtures; no network, clipboard reads, permission prompts or notification scheduling.",
            "defaultLogicalSize": ["width": 380, "height": 500],
            "systemAppearanceChanged": false,
            "robotMotion": robotMotion,
            "robotPersonality": robotPersonality,
            "screenshots": records
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("native-view-renders.json"), options: .atomic)
        print("PASS: \(records.count) native-view renders from real persistent fixtures, including compact 380 × 290 points. Output: \(output.path)")
    }

    /// Compare actual rasterized production-view frames rather than animation constants.
    /// The inactive check keeps the hosting view mounted to exercise a hidden panel's lifecycle.
    private func verifyRobotMotion(output: URL) async throws -> [String: Any] {
        guard let asset = Bundle.main.url(forResource: "robot", withExtension: "svg"),
              let image = NSImage(contentsOf: asset), image.size.width > 0, image.size.height > 0 else {
            throw RenderError.message("The production robot SVG is missing or unreadable in the native renderer")
        }
        let state = BoredRobotMotionState()
        let hosting = NSHostingView(rootView: RobotMotionFixture(state: state))
        hosting.frame = NSRect(x: 0, y: 0, width: 128, height: 156)
        hosting.wantsLayer = true
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 128, height: 156),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hosting
        retainedWindows.append(window)
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
            retainedWindows.removeAll { $0 === window }
        }
        window.orderFront(nil)

        func frame(_ name: String) throws -> Data {
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 128, pixelsHigh: 156,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let bytes = bitmap.bitmapData else {
                throw RenderError.message("Could not allocate robot motion frame")
            }
            let byteCount = bitmap.bytesPerRow * bitmap.pixelsHigh
            bytes.initialize(repeating: 0, count: byteCount)
            bitmap.size = NSSize(width: 128, height: 156)
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                throw RenderError.message("Could not encode robot motion frame")
            }
            try png.write(to: output.appendingPathComponent("native-robot-\(name).png"), options: .atomic)
            return Data(bytes: bytes, count: byteCount)
        }
        func changedBytes(_ first: Data, _ second: Data) -> Int {
            zip(first, second).reduce(0) { $0 + ($1.0 == $1.1 ? 0 : 1) }
        }

        try await Task.sleep(for: .milliseconds(250))
        let activeBefore = try frame("active-before")
        try await Task.sleep(for: .milliseconds(1500))
        let activeAfter = try frame("active-after")
        let activeChange = changedBytes(activeBefore, activeAfter)
        let systemReduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard activeBefore.filter({ $0 != 0 }).count > 1000 else {
            throw RenderError.message("The native robot frame is empty despite the SVG resource being present")
        }
        if systemReduceMotion {
            guard activeChange == 0 else {
                throw RenderError.message("The active bored robot moved while macOS Reduce Motion was enabled")
            }
        } else if activeChange <= 20 {
            throw RenderError.message("The active bored robot did not visibly animate across 1.5 seconds (\(activeChange) changed raster bytes)")
        }

        state.isActive = false
        try await Task.sleep(for: .milliseconds(200))
        let inactiveBefore = try frame("inactive-before")
        try await Task.sleep(for: .milliseconds(700))
        let inactiveAfter = try frame("inactive-after")
        let inactiveChange = changedBytes(inactiveBefore, inactiveAfter)
        guard inactiveChange == 0 else {
            throw RenderError.message("The hidden/inactive bored robot kept changing (\(inactiveChange) raster bytes)")
        }

        print("PASS: Robot asset rendered; active motion changed \(activeChange) raster bytes; inactive changed 0 bytes.")
        return ["assetPresent": true, "activeChangedBytes": activeChange,
            "activeIntervalSeconds": 1.5, "inactiveChangedBytes": inactiveChange,
            "staticIntervalSeconds": 0.7,
            "systemReduceMotionEnabled": systemReduceMotion,
            "reduceMotionVerification": systemReduceMotion ? "Verified static with current system setting." : "Code review only: macOS accessibilityReduceMotion is a read-only environment value; system preferences are not changed by QA.",
            "description": "Raster comparison of the production BoredRobotView; mounted inactive state remains static."]
    }

    /// Render the transient native robot itself. Each semantic state is allowed to
    /// settle onto its model-layer pose before capture, so these 2x artifacts are
    /// deterministic and do not depend on sampling an animation at a lucky frame.
    /// A separate digest pair proves that the live keyframes visibly move.
    private func verifyRobotPersonality(output: URL) async throws -> [String: Any] {
        let logicalSize = NSSize(width: 72, height: 88)
        let pixelScale = 2
        var reduceMotionEnabled = false
        let character = RobotCharacterView(frame: NSRect(origin: .zero, size: logicalSize),
                                           reduceMotion: { reduceMotionEnabled })
        character.wantsLayer = true
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000,
                                                   width: logicalSize.width, height: logicalSize.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = character
        retainedWindows.append(window)
        defer {
            character.stopMotion()
            window.orderOut(nil)
            window.contentView = nil
            window.close()
            retainedWindows.removeAll { $0 === window }
        }
        window.orderFront(nil)

        func changedBytes(_ first: Data, _ second: Data) -> Int {
            zip(first, second).reduce(0) { $0 + ($1.0 == $1.1 ? 0 : 1) }
        }

        @discardableResult
        func frame(_ name: String? = nil, presentation: Bool = false) throws -> Data {
            character.layoutSubtreeIfNeeded()
            character.displayIfNeeded()
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                    pixelsWide: Int(logicalSize.width) * pixelScale,
                    pixelsHigh: Int(logicalSize.height) * pixelScale,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                    isPlanar: false, colorSpaceName: .deviceRGB,
                    bytesPerRow: 0, bitsPerPixel: 0),
                  let bytes = bitmap.bitmapData else {
                throw RenderError.message("Could not allocate a 2x robot personality frame")
            }
            let byteCount = bitmap.bytesPerRow * bitmap.pixelsHigh
            bytes.initialize(repeating: 0, count: byteCount)
            bitmap.size = logicalSize
            if presentation {
                guard let context = NSGraphicsContext(bitmapImageRep: bitmap),
                      let renderedLayer = character.layer?.presentation() ?? character.layer else {
                    throw RenderError.message("Could not create a native presentation-layer robot frame")
                }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = context
                renderedLayer.render(in: context.cgContext)
                NSGraphicsContext.restoreGraphicsState()
            } else {
                character.cacheDisplay(in: character.bounds, to: bitmap)
            }
            let raster = Data(bytes: bytes, count: byteCount)
            if let name {
                guard let png = bitmap.representation(using: .png, properties: [:]) else {
                    throw RenderError.message("Could not encode the 2x \(name) robot frame")
                }
                try png.write(to: output.appendingPathComponent("native-robot-personality-\(name)@2x.png"),
                              options: .atomic)
            }
            return raster
        }

        func resetVisibleRobot() async throws {
            character.send(.hide)
            character.send(.reveal(.top))
            try await Task.sleep(for: .milliseconds(360))
            guard character.mood == .idle else {
                throw RenderError.message("Robot did not settle into idle after its top entrance")
            }
        }

        let curiousPoint = CGPoint(x: 0.82, y: -0.64)
        let states: [(name: String, event: RobotMotionEvent?, expected: RobotMood, settleMS: Int)] = [
            ("idle", nil, .idle, 30),
            ("curious", .hover(true, pointer: curiousPoint), .curious(pointer: curiousPoint), 230),
            ("hungry", .acceptedDrag(true), .hungry, 280),
            ("digesting", .saving(true), .digesting, 760),
            ("delighted", .result(.success), .delighted, 740),
            ("partial", .result(.partialSuccess), .partialSuccess, 580),
            ("puzzled", .result(.failure), .puzzled, 520)
        ]
        var stateRasters: [String: Data] = [:]
        for state in states {
            try await resetVisibleRobot()
            if let event = state.event { character.send(event) }
            try await Task.sleep(for: .milliseconds(state.settleMS))
            guard character.mood == state.expected else {
                throw RenderError.message("Robot personality state \(state.name) did not reach its expected mood")
            }
            let raster = try frame(state.name)
            guard raster.filter({ $0 != 0 }).count > 3_000 else {
                throw RenderError.message("The 2x \(state.name) robot render is blank or nearly blank")
            }
            stateRasters[state.name] = raster
        }

        guard let idleRaster = stateRasters["idle"] else {
            throw RenderError.message("Idle robot personality render is missing")
        }
        var changedFromIdle: [String: Int] = [:]
        for state in states where state.name != "idle" {
            guard let raster = stateRasters[state.name] else {
                throw RenderError.message("Robot personality render is missing for \(state.name)")
            }
            let changed = changedBytes(idleRaster, raster)
            guard changed > 20 else {
                throw RenderError.message("The \(state.name) robot is not visibly distinct from idle (\(changed) changed bytes)")
            }
            changedFromIdle[state.name] = changed
        }
        guard Set(stateRasters.values).count == states.count else {
            throw RenderError.message("Two semantic robot moods produced identical 2x raster output")
        }

        // Sample the real digest animation twice. This supplements the settled,
        // deterministic state renders without making them timing dependent.
        try await resetVisibleRobot()
        character.send(.saving(true))
        try await Task.sleep(for: .milliseconds(90))
        let digestMotionA = try frame("digest-motion-a", presentation: true)
        try await Task.sleep(for: .milliseconds(260))
        let digestMotionB = try frame("digest-motion-b", presentation: true)
        let digestMotionChange = changedBytes(digestMotionA, digestMotionB)
        guard digestMotionChange > 40 else {
            throw RenderError.message("Digest keyframes did not visibly move across two 2x frames (\(digestMotionChange) changed bytes)")
        }

        // The accessibility path keeps expressions but removes repeated and
        // positional motion. It must neither schedule ambient work nor drift.
        character.send(.hide)
        reduceMotionEnabled = true
        character.send(.reveal(.top))
        character.send(.result(.success))
        try await Task.sleep(for: .milliseconds(40))
        guard character.mood == .delighted, !character.hasActiveAmbientMotion else {
            throw RenderError.message("Reduce Motion did not retain the delighted expression without ambient work")
        }
        let reducedBefore = try frame("reduced-motion-delighted")
        try await Task.sleep(for: .milliseconds(500))
        let reducedAfter = try frame()
        let reducedMotionChange = changedBytes(reducedBefore, reducedAfter)
        guard reducedMotionChange == 0 else {
            throw RenderError.message("Reduce Motion robot drifted by \(reducedMotionChange) raster bytes")
        }

        // Cleanup is verified while the view remains mounted, matching a hidden
        // transient panel whose AppKit view has not yet been released.
        character.stopMotion()
        try await Task.sleep(for: .milliseconds(40))
        guard character.mood == .hidden, !character.hasActiveAmbientMotion else {
            throw RenderError.message("Robot cleanup retained visible state or ambient work")
        }
        let cleanupBefore = try frame()
        try await Task.sleep(for: .milliseconds(400))
        let cleanupAfter = try frame()
        let cleanupChange = changedBytes(cleanupBefore, cleanupAfter)
        guard cleanupChange == 0 else {
            throw RenderError.message("Stopped robot kept changing by \(cleanupChange) raster bytes")
        }

        let stateScreenshots: [[String: Any]] = states.map { state in
            var record: [String: Any] = [
                "file": "native-robot-personality-\(state.name)@2x.png",
                "semanticState": state.name,
                "logicalWidth": Int(logicalSize.width),
                "logicalHeight": Int(logicalSize.height),
                "pixelWidth": Int(logicalSize.width) * pixelScale,
                "pixelHeight": Int(logicalSize.height) * pixelScale,
                "pixelScale": pixelScale,
                "renderMethod": "RobotCharacterView cacheDisplay directly into a 2x bitmap after the semantic pose settles; no image scaling"
            ]
            if let changed = changedFromIdle[state.name] { record["changedBytesFromIdle"] = changed }
            return record
        }
        let motionScreenshots: [[String: Any]] = ["digest-motion-a", "digest-motion-b"].map {
            ["file": "native-robot-personality-\($0)@2x.png", "semanticState": "digesting-live",
             "logicalWidth": Int(logicalSize.width), "logicalHeight": Int(logicalSize.height),
             "pixelWidth": Int(logicalSize.width) * pixelScale,
             "pixelHeight": Int(logicalSize.height) * pixelScale, "pixelScale": pixelScale,
             "renderMethod": "Timed native presentation frame at 2x; used only to prove live digest movement"]
        }
        let reducedScreenshot: [String: Any] = [
            "file": "native-robot-personality-reduced-motion-delighted@2x.png",
            "semanticState": "delighted-reduced-motion",
            "logicalWidth": Int(logicalSize.width), "logicalHeight": Int(logicalSize.height),
            "pixelWidth": Int(logicalSize.width) * pixelScale,
            "pixelHeight": Int(logicalSize.height) * pixelScale, "pixelScale": pixelScale,
            "renderMethod": "RobotCharacterView cacheDisplay directly into a 2x bitmap with injected Reduce Motion"
        ]
        print("PASS: Native robot personality states are distinct; digest changed \(digestMotionChange) bytes; Reduce Motion and cleanup changed 0 bytes.")
        return [
            "description": "Native transient RobotCharacterView personality states rendered at 2x after settling, plus live digest motion and lifecycle checks.",
            "fixturePrivacy": "Code-drawn local character only; no clipboard, files, network, notifications or personal content.",
            "deterministicStateCount": states.count,
            "distinctStateRasterCount": Set(stateRasters.values).count,
            "changedBytesFromIdle": changedFromIdle,
            "digestAnimation": ["sampleIntervalSeconds": 0.26, "changedBytes": digestMotionChange],
            "reduceMotion": ["ambientWorkActive": false, "changedBytesOverHalfSecond": reducedMotionChange],
            "cleanup": ["mood": "hidden", "ambientWorkActive": false,
                         "changedBytesOverPointFourSeconds": cleanupChange],
            "screenshots": stateScreenshots + motionScreenshots + [reducedScreenshot]
        ]
    }

    private func snapshot(_ state: AppState, name: String, mode: String, output: URL, scrollToBottom: Bool = false, height: CGFloat = 500, width: CGFloat = 380, requireCornerMarkers: Bool = false, theme: ThemeSettings? = nil, pixelScale: Int = 1) async throws {
        let size = NSSize(width: width, height: height)
        let selectedTheme = theme ?? renderTheme!
        selectedTheme.setDarkMode(mode == "dark")
        // Appearance is driven only by the production Dark mode preference.
        // The fixture does not set the window or SwiftUI environment appearance.
        let hosting = NSHostingView(rootView: BoardView(state: state, theme: selectedTheme)
            .frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.wantsLayer = true
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hosting
        retainedWindows.append(window)
        window.orderFront(nil)
        try await Task.sleep(for: .milliseconds(state.route == .weekly ? 650 : (requireCornerMarkers ? 450 : 220)))
        hosting.layoutSubtreeIfNeeded()
        if scrollToBottom, let scroll = Self.scrollView(in: hosting), let document = scroll.documentView {
            // Lazy stacks measure more rows as scrolling exposes them; settle their final extent.
            for _ in 0..<3 {
                let y = document.isFlipped ? max(0, document.bounds.height - scroll.contentView.bounds.height) : 0
                scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
                scroll.reflectScrolledClipView(scroll.contentView)
                try await Task.sleep(for: .milliseconds(120))
                hosting.layoutSubtreeIfNeeded()
            }
        }
        hosting.displayIfNeeded()
        let backingScale = window.backingScaleFactor
        let backingSize = hosting.convertToBacking(hosting.bounds).size
        if pixelScale == 2 && (backingScale < 2 || backingSize.width < width * 2) {
            throw RenderError.message("A native Retina backing surface is required for the 2x release render; this window reports \(backingScale)x")
        }
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width) * pixelScale, pixelsHigh: Int(height) * pixelScale,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw RenderError.message("Could not allocate native render bitmap")
        }
        bitmap.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw RenderError.message("PNG encoding failed") }
        let suffix = pixelScale == 1 ? "" : "@\(pixelScale)x"
        let filename = "native-view-\(name)-\(mode)-\(Int(width))x\(Int(height))\(suffix).png"
        try png.write(to: output.appendingPathComponent(filename), options: .atomic)
        var record: [String: Any] = ["file": filename, "route": String(describing: state.route), "appearance": mode,
                                   "pixelWidth": bitmap.pixelsWide, "pixelHeight": bitmap.pixelsHigh,
                                   "logicalWidth": Int(width), "logicalHeight": Int(height), "pixelScale": pixelScale,
                                   "nativeWindowBackingScale": backingScale,
                                   "nativeViewBackingWidth": backingSize.width, "nativeViewBackingHeight": backingSize.height,
                                   "renderMethod": "NSView.cacheDisplay directly into a bitmap with logical point size and requested pixel density; no pixel resampling",
                                   "themeHex": selectedTheme.selectedHex,
                                   "darkModeEnabled": selectedTheme.darkModeEnabled,
                                   "boardOpacity": selectedTheme.boardOpacity]
        if requireCornerMarkers {
            let counts = Self.cornerMarkerCounts(in: bitmap)
            record["cornerMarkerPixelCounts"] = counts
            guard counts.values.allSatisfy({ $0 >= 6 }) else {
                throw RenderError.message("\(filename) clips or hides fixture corner markers: \(counts)")
            }
        } else if name.hasPrefix("preview-fit-") && state.selectedCapture?.kind == .pdf {
            record["validation"] = "Layout only: NSView.cacheDisplay omits PDFKit page tiles. Separate native PDFView geometry checks are required for page fitting."
        }
        records.append(record)
        window.orderOut(nil)
        window.contentView = nil
        window.close()
        retainedWindows.removeAll { $0 === window }
    }

    private func renderReleaseUI(root: URL, output: URL) async throws {
        let store = try CaptureStore(root: root.appendingPathComponent("ReleaseUI"))
        let today = Calendar.current.startOfDay(for: Date())
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let note = try store.capture(text: "Workshop notes: keep the soft violet details consistent across the collection.",
                                     at: today.addingTimeInterval(8 * 3600))[0]
        try store.update(note, comment: "Keep a little room for the next idea.", reminderAt: nil, reminderTimeZoneID: nil)
        let image = try await store.importData(Self.fixturePNG(), filename: "Workshop materials and colour references.png",
                                              at: today.addingTimeInterval(7 * 3600))
        try store.update(image, comment: "Use the soft violet from the first sample.", reminderAt: Date().addingTimeInterval(7200),
                         reminderTimeZoneID: TimeZone.current.identifier)
        let batchStamp = today.addingTimeInterval(9 * 3600)
        let batchImage = try await store.importData(Self.fixturePNG(), filename: "Purple robot sketch.png", at: batchStamp)
        _ = try await store.importData(Data("Fictional grouped document".utf8), filename: "Robot interaction notes.txt", at: batchStamp)
        let task = try store.createTask(text: "Review the studio reference collection before the next workshop", at: yesterday.addingTimeInterval(8 * 3600))
        let previous = try store.capture(text: "Saved the first workshop sketch", at: yesterday.addingTimeInterval(7 * 3600))[0]
        try store.update(previous, comment: "A quiet starting point.", reminderAt: nil, reminderTimeZoneID: nil)
        let previews = PreviewService(store: store)
        previews.process([image, batchImage])
        let deadline = Date().addingTimeInterval(8)
        while [image, batchImage].contains(where: { $0.previewState == "loading" }) && Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        guard [image, batchImage].allSatisfy({ $0.previewState == "ready" }) else {
            throw RenderError.message("Release UI image fixture failed")
        }
        let state = AppState(store: store, previews: previews,
                             reminders: ReminderService(store: store, client: RenderNotificationClient()))
        let emptyStore = try CaptureStore(root: root.appendingPathComponent("ReleaseEmpty"))
        let emptyState = AppState(store: emptyStore, previews: PreviewService(store: emptyStore),
                                  reminders: ReminderService(store: emptyStore, client: RenderNotificationClient()))

        // Keep a focused visual fixture for the fourth-action threshold and the
        // expanded in-place state. Its separate archive prevents the release
        // Daily, Weekly, search and detail fixtures from changing shape.
        let hourlyStore = try CaptureStore(root: root.appendingPathComponent("ReleaseHourly"))
        let hourlyStart = today.addingTimeInterval(14 * 3600)
        let automaticReceipts: [(CaptureOrigin, String)] = [
            (.automaticClipboard, "Notes"),
            (.automaticClipboard, "Safari"),
            (.automaticScreenshot, "Preview"),
            (.automaticClipboard, "Mail")
        ]
        for (index, fixture) in automaticReceipts.enumerated() {
            let receipt = CaptureReceiptContext.automatic(
                fixture.0,
                actionID: UUID(),
                sourceApplicationName: fixture.1,
                sourceApplicationBundleIdentifier: "com.dabin.render.\(fixture.1.lowercased())"
            )
            let stamp = hourlyStart.addingTimeInterval(TimeInterval(index * 9 * 60))
            if fixture.0 == .automaticScreenshot {
                _ = try await hourlyStore.importData(Self.fixturePNG(), filename: "Captured screen.png",
                                                     at: stamp, receipt: receipt)
            } else {
                _ = try hourlyStore.capture(text: "Automatic capture \(index + 1) from \(fixture.1)",
                                            at: stamp, receipt: receipt)
            }
        }
        let hourlyState = AppState(store: hourlyStore, previews: PreviewService(store: hourlyStore),
                                   reminders: ReminderService(store: hourlyStore, client: RenderNotificationClient()))
        hourlyState.selectedDay = today
        guard let hourlyKey = hourlyStore.captures.first.map(AutomaticHourKey.init) else {
            throw RenderError.message("Hourly release fixture did not create captures")
        }
        for mode in ["light", "dark"] {
            try await snapshot(emptyState, name: "release-empty", mode: mode, output: output,
                               height: CornerGeometry.dailyPanelHeight(for: emptyState))
            state.openDaily()
            try store.setMinimized(task, minimized: false)
            try await snapshot(state, name: "release-daily", mode: mode, output: output,
                               height: CornerGeometry.dailyPanelHeight(for: state))
            try await snapshot(state, name: "release-daily", mode: mode, output: output,
                               height: CornerGeometry.dailyPanelHeight(for: state), pixelScale: 2)
            try store.setTaskCompleted(task, completed: true)
            state.openDaily()
            try await snapshot(state, name: "release-grouped-batch", mode: mode, output: output,
                               height: CornerGeometry.dailyPanelHeight(for: state))
            try store.setTaskCompleted(task, completed: false)
            state.filter = .tasks
            state.toggleMinimized(task)
            try await snapshot(state, name: "release-minimized-task", mode: mode, output: output,
                               height: CornerGeometry.dailyPanelHeight(for: state))
            state.filter = .all
            state.selectTimelineMode(.weekly)
            try await snapshot(state, name: "release-week", mode: mode, output: output, height: 560, width: 1440)
            try await snapshot(state, name: "release-week-narrow", mode: mode, output: output, height: 560, width: 900)
            state.openSearch()
            state.query = "workshop"
            try await snapshot(state, name: "release-search", mode: mode, output: output)
            state.openCapture(image.id)
            try await snapshot(state, name: "release-detail-preview", mode: mode, output: output)
            state.detailFocus = "comment"
            try await snapshot(state, name: "release-detail-edit", mode: mode, output: output, scrollToBottom: true)
            state.showSettings()
            try await snapshot(state, name: "release-settings", mode: mode, output: output, height: 430)
            try await snapshot(state, name: "release-settings", mode: mode, output: output, height: 430, pixelScale: 2)
            try await snapshot(state, name: "release-settings-bottom", mode: mode, output: output, scrollToBottom: true, height: 430)
            hourlyState.openDaily()
            try await snapshot(hourlyState, name: "release-hourly-collapsed", mode: mode,
                               output: output, height: 430)
            hourlyState.toggleHourlyGroup(hourlyKey)
            try await snapshot(hourlyState, name: "release-hourly-expanded", mode: mode,
                               output: output, height: 560)
            hourlyState.toggleHourlyGroup(hourlyKey)
            state.openNewTask()
            state.newTaskDraft.text = "Prepare the next workshop reference board"
            state.newTaskDraft.reminderEnabled = true
            try await snapshot(state, name: "release-new-task", mode: mode, output: output, height: 370)
            state.cancelNewTask()
        }
    }

    private func renderThemes(root: URL, output: URL, theme: ThemeSettings) async throws {
        let store = try CaptureStore(root: root)
        let today = Calendar.current.startOfDay(for: Date())
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        _ = try store.createTask(text: "Finish the workshop outline", at: yesterday.addingTimeInterval(16 * 3600))
        let completed = try store.createTask(text: "Collect the material samples", at: today.addingTimeInterval(9 * 3600))
        try store.setTaskCompleted(completed, completed: true)
        let link = try store.capture(text: "https://example.invalid/studio-references", at: today.addingTimeInterval(10 * 3600))[0]
        link.title = "Studio references"
        link.previewDescription = "A few ideas to revisit in the next workshop."
        link.previewState = "ready"
        let sourceNote = try store.capture(text: "Leave room for ideas to take shape.", at: yesterday.addingTimeInterval(11 * 3600),
            source: CaptureSource(filePath: "/Users/demo/Projects/Quiet Studio/Studio brief.docx"))[0]
        try store.update(sourceNote, comment: "Use the new accent sparingly.", reminderAt: nil, reminderTimeZoneID: nil)
        try store.save()

        let reopened = try CaptureStore(root: root)
        let state = AppState(store: reopened, previews: PreviewService(store: reopened),
            reminders: ReminderService(store: reopened, client: RenderNotificationClient()))
        for mode in ["light", "dark"] {
            state.route = .settings
            for preset in ThemePreset.allCases {
                theme.select(preset)
                try await snapshot(state, name: "theme-settings-\(preset.rawValue)", mode: mode,
                    output: output, height: 430, theme: theme)
            }
            theme.setColor(Color(red: 0.72, green: 0.23, blue: 0.42))
            try await snapshot(state, name: "theme-settings-custom", mode: mode, output: output, height: 430, theme: theme)
            if mode == "light" {
                try await snapshot(state, name: "theme-settings-narrow-custom", mode: mode, output: output,
                    height: 430, width: 260, theme: theme)
            }
            state.selectedDay = today
            state.route = .daily
            state.filter = .all
            state.dailyScrollID = nil
            try await snapshot(state, name: "theme-daily-custom", mode: mode, output: output, theme: theme)
            state.openCapture(sourceNote.id)
            try await snapshot(state, name: "theme-detail-custom", mode: mode, output: output, theme: theme)
        }
    }

    private func renderPreviewFit(root: URL, output: URL) async throws {
        let store = try CaptureStore(root: root.appendingPathComponent("PreviewFit", isDirectory: true))
        let today = Calendar.current.startOfDay(for: Date())
        let fixtures: [(name: String, file: String, data: Data)] = [
            ("tall-image", "Tall colour study.png", try Self.previewFixturePNG(width: 700, height: 1800)),
            ("wide-image", "Wide colour study.png", try Self.previewFixturePNG(width: 1800, height: 650)),
            ("portrait-pdf", "Portrait page study.pdf", try Self.previewFixturePDF(landscapeFirst: false)),
            ("landscape-pdf", "Landscape page study.pdf", try Self.previewFixturePDF(landscapeFirst: true)),
            ("document", "Workshop page.rtf", Data("{\\rtf1\\ansi Fictional workshop page. Local render fixture.}".utf8))
        ]
        var captures: [(name: String, capture: Capture, day: Date)] = []
        for (index, fixture) in fixtures.enumerated() {
            let day = Calendar.current.date(byAdding: .day, value: -index, to: today)!
            let capture = try await store.importData(fixture.data, filename: fixture.file, at: day.addingTimeInterval(12 * 3600))
            capture.title = fixture.file
            captures.append((fixture.name, capture, day))
        }
        let document = captures.last!.capture
        document.thumbnailRelativePath = "Previews/\(document.id.uuidString)/thumbnail.png"
        guard let thumbnailURL = store.previewURL(for: document) else {
            throw RenderError.message("Document fixture thumbnail path was rejected")
        }
        try FileManager.default.createDirectory(at: thumbnailURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.previewFixturePNG(width: 700, height: 1000, page: true).write(to: thumbnailURL)
        document.previewState = "ready"
        let previews = PreviewService(store: store)
        previews.process(captures.dropLast().map(\.capture))
        let deadline = Date().addingTimeInterval(8)
        while captures.dropLast().contains(where: { $0.capture.previewState == "loading" }) && Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        guard captures.allSatisfy({ $0.capture.previewState == "ready" }) else {
            throw RenderError.message("Preview fit fixture thumbnails did not become ready")
        }
        try store.save()
        let state = AppState(store: store, previews: previews,
                             reminders: ReminderService(store: store, client: RenderNotificationClient()))
        for mode in ["light", "dark"] {
            for fixture in captures {
                state.openCapture(fixture.capture.id)
                for width: CGFloat in [380, 260] {
                    try await snapshot(state, name: "preview-fit-\(fixture.name)", mode: mode, output: output,
                                       width: width, requireCornerMarkers: fixture.capture.kind != .pdf)
                }
                if fixture.capture.kind == .image {
                    state.route = .daily
                    state.selectedDay = fixture.day
                    state.dailyScrollID = nil
                    try await snapshot(state, name: "preview-fit-thumbnail-\(fixture.name)", mode: mode,
                                       output: output, requireCornerMarkers: true)
                }
            }
        }
    }

    /// Each marker has a colour absent from the monochrome fictional page and normal DaBin chrome.
    /// Finding all four is a raster check that catches a centred fill/crop of either aspect ratio.
    private static func cornerMarkerCounts(in bitmap: NSBitmapImageRep) -> [String: Int] {
        var counts = ["red": 0, "green": 0, "blue": 0, "orange": 0]
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.alphaComponent > 0.9 else { continue }
                let r = color.redComponent, g = color.greenComponent, b = color.blueComponent
                if r > 0.75 && g < 0.3 && b < 0.3 { counts["red", default: 0] += 1 }
                if r < 0.3 && g > 0.6 && b < 0.4 { counts["green", default: 0] += 1 }
                if r < 0.3 && g < 0.5 && b > 0.75 { counts["blue", default: 0] += 1 }
                if r > 0.85 && g > 0.45 && g < 0.8 && b < 0.2 { counts["orange", default: 0] += 1 }
            }
        }
        return counts
    }

    private static func drawPreviewFixture(in context: CGContext, size: CGSize, page: Bool) {
        let width = size.width, height = size.height
        context.setFillColor(CGColor(gray: page ? 0.99 : 0.94, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        let marker = min(width, height) * 0.14
        let inset = min(width, height) * 0.025
        for (rect, color) in [
            (CGRect(x: inset, y: inset, width: marker, height: marker), CGColor(red: 1, green: 0, blue: 0, alpha: 1)),
            (CGRect(x: width - marker - inset, y: inset, width: marker, height: marker), CGColor(red: 0, green: 0.85, blue: 0.2, alpha: 1)),
            (CGRect(x: inset, y: height - marker - inset, width: marker, height: marker), CGColor(red: 0, green: 0.25, blue: 1, alpha: 1)),
            (CGRect(x: width - marker - inset, y: height - marker - inset, width: marker, height: marker), CGColor(red: 1, green: 0.65, blue: 0, alpha: 1))
        ] {
            context.setFillColor(color)
            context.fill(rect)
        }
        context.setFillColor(CGColor(gray: 0.3, alpha: 1))
        let centerWidth = width * 0.52
        context.fill(CGRect(x: width * 0.24, y: height * 0.65, width: centerWidth, height: height * 0.018))
        context.setFillColor(CGColor(gray: 0.65, alpha: 1))
        for line in 0..<8 {
            context.fill(CGRect(x: width * 0.24, y: height * (0.59 - CGFloat(line) * 0.045),
                                width: centerWidth * (line.isMultiple(of: 3) ? 0.73 : 1), height: height * 0.008))
        }
    }

    private static func previewFixturePNG(width: Int, height: Int, page: Bool = false) throws -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        drawPreviewFixture(in: context, size: CGSize(width: width, height: height), page: page)
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        guard CGImageDestinationFinalize(destination) else { throw RenderError.message("Preview image encoding failed") }
        return data as Data
    }

    private static func previewFixturePDF(landscapeFirst: Bool) throws -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            throw RenderError.message("PDF fixture context creation failed")
        }
        for landscape in [landscapeFirst, !landscapeFirst] {
            var page = CGRect(x: 0, y: 0, width: landscape ? 792 : 612, height: landscape ? 612 : 792)
            let box = NSData(bytes: &page, length: MemoryLayout<CGRect>.size)
            context.beginPDFPage([kCGPDFContextMediaBox: box] as CFDictionary)
            drawPreviewFixture(in: context, size: page.size, page: true)
            context.endPDFPage()
        }
        context.closePDF()
        guard PDFDocument(data: data as Data)?.pageCount == 2 else {
            throw RenderError.message("Mixed orientation PDF fixture must contain two readable pages")
        }
        return data as Data
    }

    private static func scrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for child in view.subviews { if let scroll = scrollView(in: child) { return scroll } }
        return nil
    }

    private static func fixturePNG() throws -> Data {
        let context = CGContext(data: nil, width: 900, height: 600, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.90, green: 0.88, blue: 0.85, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 900, height: 600))
        for (rect, color) in [(CGRect(x: 50, y: 55, width: 470, height: 490), CGColor(red: 0.66, green: 0.62, blue: 0.72, alpha: 1)),
                              (CGRect(x: 550, y: 55, width: 300, height: 230), CGColor(red: 0.38, green: 0.39, blue: 0.38, alpha: 1)),
                              (CGRect(x: 550, y: 315, width: 300, height: 230), CGColor(red: 0.78, green: 0.75, blue: 0.70, alpha: 1))] {
            context.setFillColor(color)
            context.fill(rect)
        }
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        guard CGImageDestinationFinalize(destination) else { throw RenderError.message("Fixture image encoding failed") }
        return data as Data
    }
}

private enum RenderError: Error { case message(String) }
