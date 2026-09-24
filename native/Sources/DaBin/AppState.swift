import AppKit
import Combine
import Foundation

enum BoardRoute: Equatable {
    case daily, weekly, search, detail, reminders, settings, newTask
}

enum BoardTimelineMode: Hashable {
    case daily, weekly
}

enum WeeklyExpansionDirection: Equatable { case left, right }

struct AppStatusMessage: Equatable {
    enum Severity { case success, warning, error }
    let text: String
    let severity: Severity
    let reminderCaptureID: UUID?

    init(text: String, severity: Severity, reminderCaptureID: UUID? = nil) {
        self.text = text
        self.severity = severity
        self.reminderCaptureID = reminderCaptureID
    }

    var symbol: String {
        switch severity {
        case .success: return "checkmark.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "exclamationmark.circle"
        }
    }
}

@MainActor
final class NewTaskDraft: ObservableObject {
    @Published var text = ""
    @Published var reminderEnabled = false
    @Published var reminderDate = Date().addingTimeInterval(3600)
    @Published var message: String?

    var hasChanges: Bool { !text.isEmpty || reminderEnabled }

    func reset() {
        text = ""
        reminderEnabled = false
        reminderDate = Date().addingTimeInterval(3600)
        message = nil
    }
}

/// Drafts live outside the view hierarchy, so closing the panel never loses an edit.
@MainActor
final class CaptureDraft: ObservableObject {
    @Published var comment: String
    @Published var reminderEnabled: Bool
    @Published var reminderDate: Date
    @Published var message: String?
    @Published var hasError = false
    private var savedComment: String
    private var savedReminder: Date?

    init(capture: Capture) {
        comment = capture.comment
        reminderEnabled = capture.reminderAt != nil
        reminderDate = capture.reminderAt ?? Date().addingTimeInterval(3600)
        savedComment = capture.comment
        savedReminder = capture.reminderAt
    }

    var reminder: Date? { reminderEnabled ? reminderDate : nil }
    var hasChanges: Bool { comment != savedComment || reminder != savedReminder }
    var reminderChanged: Bool { reminder != savedReminder }

    func didSave() {
        savedComment = comment
        savedReminder = reminder
        message = "Changes saved."
        hasError = false
    }
}

@MainActor
final class AppState: ObservableObject {
    let store: CaptureStore
    let previews: PreviewService
    let reminders: ReminderService
    let updates: SoftwareUpdateService
    let robotPlacement: RobotPlacementSettings
    let autoCapture: AutoCaptureService
    let newTaskDraft = NewTaskDraft()
    @Published var route: BoardRoute = .daily {
        didSet {
            if route != oldValue { captureNavigationRevision &+= 1 }
            if route != .daily { isDailyDropTargeted = false }
            if route != .weekly { weeklySearchActionsPresented = false }
        }
    }
    @Published var selectedDay = Date() {
        didSet { if selectedDay != oldValue { captureNavigationRevision &+= 1 } }
    }
    @Published var weekEndingDay = Date()
    @Published var weeklyExpansionDirection: WeeklyExpansionDirection = .right
    @Published var filter: CaptureFilter = .all {
        didSet { if filter != oldValue { captureNavigationRevision &+= 1 } }
    }
    @Published var query = ""
    @Published private(set) var searchScope: CaptureSearchScope = .all
    @Published var weeklySearchActionsPresented = false
    @Published var selectedCapture: Capture?
    @Published var pendingRemoval: Capture?
    @Published private(set) var removingCaptureID: UUID?
    @Published private(set) var captureLayoutRevision: UInt = 0
    @Published var status: AppStatusMessage?
    @Published var detailFocus: String?
    @Published var selectedDraft: CaptureDraft?
    @Published var dailyScrollID: CaptureFeedCardID?
    @Published var searchScrollID: UUID?
    @Published private(set) var expandedAutomaticHours: Set<AutomaticHourKey> = []
    @Published var isBoardVisible = false
    @Published var isDailyDropTargeted = false
    private(set) var captureNavigationRevision: UInt = 0
    var onDismiss: (() -> Void)?
    var onBoardDragStarted: (() -> Void)?
    private var origin: BoardRoute = .daily
    private var searchReturnRoute: BoardRoute = .daily
    private var drafts: [UUID: CaptureDraft] = [:]
    private var subscriptions = Set<AnyCancellable>()
    private var reminderServiceFeedback: (captureID: UUID, message: String?)?
    private var currentDayKey = CaptureCalendar.dayString(Date())

    init(store: CaptureStore, previews: PreviewService, reminders: ReminderService,
         updates: SoftwareUpdateService? = nil, robotPlacement: RobotPlacementSettings? = nil,
         autoCapture: AutoCaptureService? = nil) {
        self.store = store
        self.previews = previews
        self.reminders = reminders
        self.updates = updates ?? SoftwareUpdateService()
        self.robotPlacement = robotPlacement ?? RobotPlacementSettings(defaults: nil)
        self.autoCapture = autoCapture ?? AutoCaptureService(
            settings: AutoCaptureSettings(defaults: nil), input: InputService(store: store))
        store.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &subscriptions)
        reminders.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &subscriptions)
        self.autoCapture.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &subscriptions)
        self.autoCapture.settings.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &subscriptions)
        newTaskDraft.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &subscriptions)
        // Advance a board left on Today across midnight or sleep without moving
        // a day the user deliberately chose to browse.
        for name in [Notification.Name.NSCalendarDayChanged,
                     NSApplication.didBecomeActiveNotification,
                     Notification.Name.NSSystemTimeZoneDidChange] {
            NotificationCenter.default.publisher(for: name)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.refreshCurrentDay() }
                .store(in: &subscriptions)
        }
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshCurrentDay() }
            .store(in: &subscriptions)
    }

    var dayKey: String { CaptureCalendar.dayString(selectedDay) }
    var dailyCaptures: [Capture] { captures(for: selectedDay) }
    var weeklyDays: [Date] {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: min(weekEndingDay, Date()))
        return (-6...0).compactMap { calendar.date(byAdding: .day, value: $0, to: end) }
    }
    /// The seven-day range remains the navigation source of truth, while the
    /// Weekly board only presents dates that contain activity. Filters change
    /// the cards inside those dates without making the date columns jump.
    /// Carried and reminder-day tasks are included by `allCaptures(for:)`.
    var weeklyVisibleDays: [Date] {
        weeklyDays.filter { !allCaptures(for: $0).isEmpty }
    }

    func allCaptures(for day: Date) -> [Capture] {
        let key = CaptureCalendar.dayString(day)
        return store.captures.filter {
            $0.captureDay == key || isTaskAtTop($0, dayKey: key)
        }.sorted {
            let lhsAtTop = isTaskAtTop($0, dayKey: key), rhsAtTop = isTaskAtTop($1, dayKey: key)
            if lhsAtTop != rhsAtTop { return lhsAtTop }
            return $0.capturedAt == $1.capturedAt ? $0.id.uuidString < $1.id.uuidString : $0.capturedAt > $1.capturedAt
        }
    }
    func captures(for day: Date) -> [Capture] { allCaptures(for: day).filter { filter.includes($0.kind) } }
    var allCapturesForDay: [Capture] { allCaptures(for: selectedDay) }
    func isTaskAtTop(_ capture: Capture) -> Bool {
        isTaskAtTop(capture, on: selectedDay)
    }
    func isTaskAtTop(_ capture: Capture, on day: Date) -> Bool {
        isTaskAtTop(capture, dayKey: CaptureCalendar.dayString(day))
    }
    private func isTaskAtTop(_ capture: Capture, dayKey: String) -> Bool {
        guard capture.isTask, !capture.isCompleted, capture.captureDay <= dayKey else { return false }
        if let reminder = capture.reminderAt {
            // Match the local day shown by the reminder label, including tasks
            // created on that day. A reminder replaces automatic daily carryover.
            return CaptureCalendar.dayString(reminder) == dayKey
        }
        return capture.captureDay < dayKey
    }

    func refreshCurrentDay(at now: Date = Date()) {
        let nextDay = CaptureCalendar.dayString(now)
        guard nextDay != currentDayKey else { return }
        if dayKey == currentDayKey || dayKey > nextDay {
            selectedDay = now
            dailyScrollID = nil
        }
        let weekEnd = CaptureCalendar.dayString(weekEndingDay)
        if weekEnd == currentDayKey || weekEnd > nextDay { weekEndingDay = now }
        currentDayKey = nextDay
    }
    var searchGroups: [SearchGroup] {
        CaptureSearch.groups(captures: store.captures, query: query, filter: filter,
                             scope: searchScope)
    }
    var searchScopeTitle: String {
        switch searchScope {
        case .all:
            return "All dates"
        case .day(let day):
            return prettyDay(day)
        case .week(let days):
            let ordered = days.sorted()
            guard let first = ordered.first, let last = ordered.last else { return "Selected week" }
            return "\(prettyDay(first, includeWeekday: false))–\(prettyDay(last, includeWeekday: false))"
        }
    }

    /// The day used by Weekly's day-scoped Search and Export actions. Keep a
    /// preserved in-range selection; after range navigation, fall back to the
    /// visible week end so the action never silently targets an off-screen day.
    var weeklyActionDay: Date {
        let selectedKey = CaptureCalendar.dayString(selectedDay)
        return weeklyDays.first(where: { CaptureCalendar.dayString($0) == selectedKey })
            ?? weeklyDays.last
            ?? weekEndingDay
    }
    var hasUnsavedDrafts: Bool { newTaskDraft.hasChanges || drafts.values.contains(where: \.hasChanges) }

    func openDaily() {
        refreshCurrentDay()
        selectedDay = Date()
        filter = .all
        dailyScrollID = nil
        route = .daily
    }

    func openWeekly() {
        weekEndingDay = min(selectedDay, Date())
        route = .weekly
    }

    var timelineMode: BoardTimelineMode { route == .weekly ? .weekly : .daily }

    func selectTimelineMode(_ mode: BoardTimelineMode) {
        switch (route, mode) {
        case (.daily, .weekly):
            openWeekly()
        case (.weekly, .daily):
            route = .daily
        default:
            break
        }
    }

    func selectWeeklyDay(_ day: Date) {
        selectedDay = min(day, Date())
        dailyScrollID = nil
        route = .daily
    }

    func selectWeeklyActionDay(_ day: Date) {
        let key = CaptureCalendar.dayString(day)
        guard let selected = weeklyDays.first(where: { CaptureCalendar.dayString($0) == key }) else { return }
        selectedDay = selected
    }

    func setWeekEndingDay(_ day: Date) {
        weekEndingDay = min(day, Date())
    }

    func moveWeek(_ amount: Int) {
        guard let end = Calendar.current.date(byAdding: .day, value: amount * 7, to: weekEndingDay) else { return }
        setWeekEndingDay(end)
    }

    func showCurrentWeek() {
        refreshCurrentDay()
        let today = Date()
        selectedDay = today
        weekEndingDay = today
        route = .weekly
    }

    func openSearch() {
        guard route != .search else { return }
        searchScope = .all
        searchReturnRoute = route == .weekly ? .weekly : .daily
        searchScrollID = nil
        route = .search
    }

    /// Routes the application-wide Search command through Weekly's explicit
    /// day/week chooser. Keeping this in state lets the native application
    /// menu and the compact header share exactly the same behavior.
    func performSearchCommand() {
        if route == .weekly {
            weeklySearchActionsPresented = true
        } else if route != .search {
            openSearch()
        }
    }

    func openSearch(day: Date) {
        weeklySearchActionsPresented = false
        searchScope = .day(CaptureCalendar.dayString(day))
        searchReturnRoute = .weekly
        searchScrollID = nil
        route = .search
    }

    func openSearch(week days: [Date]) {
        weeklySearchActionsPresented = false
        searchScope = .week(Set(days.map { CaptureCalendar.dayString($0) }))
        searchReturnRoute = .weekly
        searchScrollID = nil
        route = .search
    }
    func showReminders() { route = .reminders }
    func showSettings() { route = .settings }

    func openNewTask() {
        status = nil
        newTaskDraft.message = nil
        route = .newTask
    }

    func cancelNewTask() {
        newTaskDraft.reset()
        route = .daily
    }

    func saveNewTask() {
        guard !newTaskDraft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            newTaskDraft.message = "Give your task a name."
            return
        }
        let reminder = newTaskDraft.reminderEnabled ? newTaskDraft.reminderDate : nil
        if let reminder, reminder <= Date() {
            newTaskDraft.message = "Choose a reminder time in the future."
            return
        }
        do {
            let capture = try store.createTask(text: newTaskDraft.text, reminderAt: reminder,
                reminderTimeZoneID: reminder == nil ? nil : TimeZone.current.identifier)
            newTaskDraft.reset()
            openDaily()
            dailyScrollID = feedID(for: capture, on: selectedDay)
            if reminder != nil {
                Task { await saveReminderAndReport(for: capture) }
            }
        } catch {
            newTaskDraft.message = "Could not add this task: \(error.localizedDescription)"
        }
    }

    func toggleTaskCompletion(_ capture: Capture) {
        guard capture.kind == .task else { return }
        do {
            try store.setTaskCompleted(capture, completed: !capture.isCompleted)
            if capture.isCompleted { clearReminderFeedback(for: capture) }
            objectWillChange.send()
            Task {
                if capture.isCompleted { await reminders.clearForCapture(capture.id) }
                else { await saveReminderAndReport(for: capture) }
            }
        } catch {
            reportFailure("Could not update the task: \(error.localizedDescription)")
        }
    }

    func toggleMinimized(_ capture: Capture) {
        guard removingCaptureID != capture.id else { return }
        do {
            try store.setMinimized(capture, minimized: !capture.isMinimized)
            captureLayoutRevision &+= 1
        }
        catch { reportFailure("Could not resize this capture: \(error.localizedDescription)") }
    }

    func toggleMinimized(_ captures: [Capture]) {
        let current = captures.filter { capture in
            store.captures.contains(where: { $0 === capture })
        }
        guard !current.isEmpty, removingCaptureID == nil else { return }
        let minimized = !current.allSatisfy(\.isMinimized)
        do {
            for capture in current where capture.isMinimized != minimized {
                try store.setMinimized(capture, minimized: minimized)
            }
            captureLayoutRevision &+= 1
        } catch {
            reportFailure("Could not resize this batch: \(error.localizedDescription)")
        }
    }

    func isHourlyGroupExpanded(_ key: AutomaticHourKey) -> Bool {
        expandedAutomaticHours.contains(key)
    }

    func toggleHourlyGroup(_ key: AutomaticHourKey) {
        if expandedAutomaticHours.remove(key) == nil { expandedAutomaticHours.insert(key) }
        captureLayoutRevision &+= 1
    }

    func requestRemoval(_ capture: Capture) {
        guard removingCaptureID == nil, store.captures.contains(where: { $0 === capture }) else { return }
        pendingRemoval = capture
    }

    func confirmRemoval() {
        guard let capture = pendingRemoval else { return }
        pendingRemoval = nil
        Task { await removeCapture(capture) }
    }

    /// The view obtains confirmation first. Quiesce preview IO before deleting
    /// its files, then clear notifications through the service's serialized queue.
    func removeCapture(_ capture: Capture) async {
        guard removingCaptureID == nil, store.captures.contains(where: { $0 === capture }) else { return }
        removingCaptureID = capture.id
        defer { removingCaptureID = nil }
        await previews.cancel(for: capture.id)
        do {
            let result = try store.remove(capture)
            captureLayoutRevision &+= 1
            drafts.removeValue(forKey: capture.id)
            clearReminderFeedback(for: capture)
            if pendingRemoval?.id == capture.id { pendingRemoval = nil }
            // Removing an action can dissolve a four-action summary, so a prior
            // feed anchor may no longer exist.
            dailyScrollID = nil
            if searchScrollID == capture.id { searchScrollID = nil }
            if selectedCapture?.id == capture.id {
                selectedCapture = nil
                selectedDraft = nil
                detailFocus = nil
                if route == .detail { route = origin }
            }
            status = AppStatusMessage(text: result.warning ?? "Capture removed.",
                                     severity: result.cleanupPending ? .warning : .success)
            await reminders.clearForCapture(capture.id)
        } catch {
            reportFailure("Could not remove this capture: \(error.localizedDescription)")
            previews.process([capture])
        }
    }

    func removeCaptures(_ captures: [Capture]) async {
        let ids = Set(captures.map(\.id))
        guard !ids.isEmpty, removingCaptureID == nil else { return }
        for capture in captures where store.captures.contains(where: { $0 === capture }) {
            await removeCapture(capture)
        }
        let remaining = store.captures.filter { ids.contains($0.id) }
        if remaining.isEmpty {
            status = AppStatusMessage(text: "Removed \(ids.count) items from the batch.", severity: .success)
        } else if status?.severity != .error {
            reportFailure("Could not remove every item in this batch.")
        }
    }

    func openCapture(_ id: UUID, focus: String? = nil) {
        guard let capture = store.captures.first(where: { $0.id == id }) else {
            reportFailure("This capture could not be found.")
            return
        }
        if route != .detail { origin = route }
        selectedCapture = capture
        if drafts[id] == nil { drafts[id] = CaptureDraft(capture: capture) }
        selectedDraft = drafts[id]
        detailFocus = focus
        route = .detail
    }

    func back() {
        if route == .detail {
            route = origin
        } else if route == .search {
            route = searchReturnRoute
        } else {
            route = .daily
        }
        detailFocus = nil
    }

    func showCaptureDay(_ capture: Capture) {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        parser.timeZone = .current
        selectedDay = parser.date(from: capture.captureDay) ?? capture.capturedAt
        filter = .all
        route = .daily
        if capture.captureOrigin.isAutomatic {
            let hour = AutomaticHourKey(capture: capture)
            if automaticActionCount(in: hour, on: selectedDay) >= HourlyCaptureFeed.summaryThreshold {
                expandedAutomaticHours.insert(hour)
            }
        }
        dailyScrollID = feedID(for: capture, on: selectedDay)
    }

    func moveDay(_ amount: Int) {
        guard let day = Calendar.current.date(byAdding: .day, value: amount, to: selectedDay),
              Calendar.current.startOfDay(for: day) <= Calendar.current.startOfDay(for: Date()) else { return }
        selectedDay = day
        dailyScrollID = nil
    }

    func didCapture(_ captures: [Capture]) {
        guard !captures.isEmpty else { return }
        let days = Set(captures.map(\.captureDay)).sorted()
        status = AppStatusMessage(text: "Saved \(captures.count == 1 ? "capture" : "\(captures.count) captures") · \(days.joined(separator: ", "))", severity: .success)
        previews.process(captures)
    }

    func didAutoCapture(_ captures: [Capture]) {
        guard !captures.isEmpty else { return }
        // The passive robot confirms automatic saves. Keep the board calm while
        // still scheduling local previews and publishing the live feed update.
        previews.process(captures)
        objectWillChange.send()
    }

    func reportFailure(_ message: String) {
        status = AppStatusMessage(text: message, severity: .error)
    }

    func reportCaptureResult(_ captures: [Capture], errors: [String]) {
        didCapture(captures)
        guard !errors.isEmpty else { return }
        let summary = (captures.isEmpty ? "Couldn’t save this capture. " : "Saved \(captures.count); some items failed. ") + errors.joined(separator: "\n")
        status = AppStatusMessage(text: summary, severity: captures.isEmpty ? .error : .warning)
    }

    /// The task form returns to Daily before macOS resolves notification permission.
    /// Keep failures visible there, even if the user never opens the task detail.
    private func saveReminderAndReport(for capture: Capture) async {
        let revision = capture.reminderRevision
        let desiredDate = capture.reminderAt
        await reminders.saveReminder(for: capture)
        // A permission dialog or scheduling request may finish after a later
        // clear/edit/completion. Only the still-current request may show feedback.
        guard capture.reminderRevision == revision, capture.reminderAt == desiredDate,
              desiredDate != nil, !(capture.isTask && capture.isCompleted),
              store.captures.contains(where: { $0 === capture }) else { return }
        switch capture.notificationState {
        case "scheduled":
            status = AppStatusMessage(text: "Reminder scheduled.", severity: .success, reminderCaptureID: capture.id)
        case "denied", "pending":
            status = AppStatusMessage(text: "Reminder saved. Enable DaBin notifications in System Settings to receive alerts.", severity: .warning, reminderCaptureID: capture.id)
        case "failed":
            status = AppStatusMessage(text: "Reminder saved, but its notification could not be scheduled. Open the capture to retry.", severity: .error, reminderCaptureID: capture.id)
        default: return
        }
        reminderServiceFeedback = (capture.id, reminders.status)
    }

    private func clearReminderFeedback(for capture: Capture) {
        if status?.reminderCaptureID == capture.id { status = nil }
        if let feedback = reminderServiceFeedback, feedback.captureID == capture.id {
            // Do not erase service feedback that a newer operation replaced.
            if reminders.status == feedback.message { reminders.status = nil }
            reminderServiceFeedback = nil
        }
    }

    func saveDetail() {
        guard let capture = selectedCapture, let draft = selectedDraft else { return }
        if draft.reminderChanged, let reminder = draft.reminder, reminder <= Date() {
            draft.message = "Choose a reminder time in the future."
            draft.hasError = true
            return
        }
        let changedReminder = draft.reminderChanged
        do {
            try store.update(capture, comment: draft.comment, reminderAt: draft.reminder,
                             reminderTimeZoneID: draft.reminder == nil ? nil : (changedReminder ? TimeZone.current.identifier : capture.reminderTimeZoneID))
            draft.didSave()
            if changedReminder {
                if capture.reminderAt == nil { clearReminderFeedback(for: capture) }
                Task {
                    if capture.reminderAt == nil { await reminders.clearForCapture(capture.id) }
                    else { await saveReminderAndReport(for: capture) }
                }
            }
        } catch {
            draft.message = "Could not save changes: \(error.localizedDescription)"
            draft.hasError = true
        }
    }

    func openOriginal(_ capture: Capture) {
        let url: URL?
        if let original = capture.originalURL, let parsed = URL(string: original),
           ["https", "http"].contains(parsed.scheme?.lowercased() ?? "") {
            url = parsed
        } else {
            url = store.managedURL(for: capture)
            if let file = url, !FileManager.default.fileExists(atPath: file.path) {
                reportFailure("The saved original is missing. Its capture and annotations are still available.")
                return
            }
        }
        guard let url else { reportFailure("No original file or link is available for this capture."); return }
        if !NSWorkspace.shared.open(url) { reportFailure("macOS could not open this original. Choose a compatible application in Finder.") }
    }

    func showArchiveFolder(for capture: Capture? = nil) {
        do {
            let folder = try store.prepareArchiveFolder(for: capture)
            if !NSWorkspace.shared.open(folder) { reportFailure("macOS could not open the local archive folder.") }
        } catch { reportFailure("Could not open the local archive: \(error.localizedDescription)") }
    }

    func retryReminder(_ capture: Capture) {
        Task { await saveReminderAndReport(for: capture) }
    }

    func setLinkPreviews(_ enabled: Bool) {
        previews.enabled = enabled
        if enabled { previews.process(store.captures.filter { $0.kind == .link && !$0.captureOrigin.isAutomatic }) }
        else { previews.cancelNetwork() }
        objectWillChange.send()
    }

    func feedID(for capture: Capture, on day: Date) -> CaptureFeedCardID {
        if capture.captureOrigin.isAutomatic {
            let hour = AutomaticHourKey(capture: capture)
            if automaticActionCount(in: hour, on: day) >= HourlyCaptureFeed.summaryThreshold {
                return .automaticHour(hour)
            }
        }
        if capture.attachmentRelativePath != nil {
            let batchCount = allCaptures(for: day).filter {
                $0.attachmentRelativePath != nil && $0.capturedAt == capture.capturedAt
            }.count
            if batchCount > 1 { return .capture(.importedBatch(capture.capturedAt)) }
        }
        return .capture(.capture(capture.id))
    }

    private func automaticActionCount(in hour: AutomaticHourKey, on day: Date) -> Int {
        Set(allCaptures(for: day).filter {
            $0.captureOrigin.isAutomatic && AutomaticHourKey(capture: $0) == hour
        }.map { $0.automaticActionID ?? $0.id }).count
    }
}
