import Combine
import Foundation
import UserNotifications

@MainActor
final class ReminderService: NSObject, UNUserNotificationCenterDelegate, ObservableObject {
    @Published var status: String?
    var onOpenCapture: ((UUID) -> Void)? {
        didSet {
            guard let callback = onOpenCapture, let id = deferredOpen else { return }
            deferredOpen = nil
            callback(id)
        }
    }
    private let store: CaptureStore
    private let client: ReminderNotificationClient
    private var tail: Task<Void, Never>?
    private var tailID: UUID?
    private var deferredOpen: UUID?
    static let identifierPrefix = "dabin.capture."

    convenience init(store: CaptureStore) {
        self.init(store: store, client: SystemReminderNotificationClient())
    }

    // Dependency injection keeps tests away from real notification permission and scheduling.
    init(store: CaptureStore, client: ReminderNotificationClient) {
        self.store = store
        self.client = client
        super.init()
        (client as? SystemReminderNotificationClient)?.center.delegate = self
    }

    /// Called at launch/activation. This deliberately never presents a permission request.
    func reconcile() async {
        await serialized { [self] in
            let pending = await client.pending()
            let known = Set(store.captures.map { Self.identifier($0.id) })
            let orphaned = pending.map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) && !known.contains($0) }
            client.removePending(orphaned)
            client.removeDelivered(orphaned)
            for id in store.captures.map(\.id) {
                await synchronize(id: id, requestPermission: false)
            }
        }
    }

    /// The caller commits the desired date/revision before this explicit user-save operation.
    func saveReminder(for capture: Capture) async {
        let id = capture.id
        await serialized { [self] in await synchronize(id: id, requestPermission: true) }
    }

    func clearForCapture(_ id: UUID) async {
        // The caller commits nil or completion first. A delayed Clear honors newer state.
        await serialized { [self] in await synchronize(id: id, requestPermission: false) }
    }

    private func serialized(_ work: @escaping @MainActor () async -> Void) async {
        let previous = tail
        let id = UUID()
        let task = Task { @MainActor in
            await previous?.value
            await work()
        }
        tail = task
        tailID = id
        await task.value
        if tailID == id { tail = nil; tailID = nil }
    }

    private func synchronize(id: UUID, requestPermission: Bool) async {
        let identifier = Self.identifier(id)
        var mayRequestPermission = requestPermission
        while true {
            guard let capture = store.captures.first(where: { $0.id == id }) else {
                client.removePending([identifier])
                client.removeDelivered([identifier])
                return
            }
            let revision = capture.reminderRevision
            guard !capture.isTask || !capture.isCompleted else {
                client.removePending([identifier])
                client.removeDelivered([identifier])
                persistState("completed", for: capture)
                return
            }
            guard let desired = capture.reminderAt else {
                client.removePending([identifier])
                client.removeDelivered([identifier])
                persistState("none", for: capture)
                return
            }
            guard desired > Date() else {
                client.removePending([identifier])
                persistState("past", for: capture)
                return
            }
            var authorization = await client.authorization()
            guard isCurrent(id: id, revision: revision, date: desired) else { continue }
            if authorization == .undetermined && mayRequestPermission {
                mayRequestPermission = false
                do {
                    authorization = try await client.requestAuthorization() ? .allowed : .denied
                } catch {
                    guard isCurrent(id: id, revision: revision, date: desired) else { continue }
                    client.removePending([identifier])
                    persistState("failed", for: capture)
                    status = "Reminder saved. Notification permission could not be checked: \(error.localizedDescription)"
                    return
                }
            }
            guard isCurrent(id: id, revision: revision, date: desired) else { continue }
            guard authorization == .allowed else {
                client.removePending([identifier])
                client.removeDelivered([identifier])
                persistState(authorization == .denied ? "denied" : "pending", for: capture)
                if requestPermission {
                    status = "Reminder saved. Enable DaBin notifications in System Settings to receive alerts."
                }
                return
            }
            let pending = await client.pending()
            guard isCurrent(id: id, revision: revision, date: desired) else { continue }
            if pending.contains(where: { $0.identifier == identifier && $0.revision == revision && abs($0.date.timeIntervalSince(desired)) < 1 }) {
                persistState("scheduled", for: capture)
                if requestPermission { status = "Reminder scheduled." }
                return
            }
            // An edit replaces both the old request and any alert already delivered for the item.
            client.removePending([identifier])
            client.removeDelivered([identifier])
            persistState("pending", for: capture)
            do {
                guard desired > Date() else { continue }
                try await client.add(.init(identifier: identifier, captureID: id, revision: revision, date: desired))
                guard isCurrent(id: id, revision: revision, date: desired) else {
                    client.removePending([identifier])
                    continue
                }
                persistState("scheduled", for: capture)
                if requestPermission { status = "Reminder scheduled." }
                return
            } catch {
                guard isCurrent(id: id, revision: revision, date: desired) else { continue }
                persistState("failed", for: capture)
                status = "Reminder saved, but its notification could not be scheduled: \(error.localizedDescription)"
                return
            }
        }
    }

    private func isCurrent(id: UUID, revision: Int, date: Date) -> Bool {
        guard let capture = store.captures.first(where: { $0.id == id }) else { return false }
        return (!capture.isTask || !capture.isCompleted) && capture.reminderRevision == revision && capture.reminderAt == date
    }

    private func persistState(_ state: String, for capture: Capture) {
        guard capture.notificationState != state else { return }
        let previous = capture.notificationState
        capture.notificationState = state
        do { try store.save(captures: [capture]) }
        catch {
            // Keep the in-memory state honest so the next reconciliation retries
            // this transition after a temporary metadata-write failure.
            capture.notificationState = previous
            status = "Reminder notification state could not be saved: \(error.localizedDescription)"
        }
    }

    static func identifier(_ id: UUID) -> String { identifierPrefix + id.uuidString }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let rawID = response.notification.request.content.userInfo["captureID"] as? String
        Task { @MainActor [weak self] in
            defer { completionHandler() }
            guard let self, let rawID, let id = UUID(uuidString: rawID),
                  self.store.captures.contains(where: { $0.id == id }) else { return }
            // Opening an old alert can reveal the item, but never mutates its current reminder.
            if let callback = self.onOpenCapture { callback(id) }
            else { self.deferredOpen = id }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

enum ReminderAuthorization { case undetermined, allowed, denied }

struct ScheduledReminder {
    let identifier: String
    let captureID: UUID
    let revision: Int
    let date: Date
}

@MainActor
protocol ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization
    func requestAuthorization() async throws -> Bool
    func pending() async -> [ScheduledReminder]
    func add(_ reminder: ScheduledReminder) async throws
    func removePending(_ identifiers: [String])
    func removeDelivered(_ identifiers: [String])
}

@MainActor
private final class SystemReminderNotificationClient: ReminderNotificationClient {
    let center = UNUserNotificationCenter.current()

    func authorization() async -> ReminderAuthorization {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional: return .allowed
        case .notDetermined: return .undetermined
        default: return .denied
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func pending() async -> [ScheduledReminder] {
        await center.pendingNotificationRequests().compactMap { request in
            let values = request.content.userInfo
            guard let rawID = values["captureID"] as? String, let id = UUID(uuidString: rawID),
                  let revision = values["revision"] as? Int,
                  let interval = values["reminderAt"] as? Double else { return nil }
            return ScheduledReminder(identifier: request.identifier, captureID: id, revision: revision,
                                     date: Date(timeIntervalSince1970: interval))
        }
    }

    func add(_ reminder: ScheduledReminder) async throws {
        let content = UNMutableNotificationContent()
        content.title = "DaBin"
        content.body = "You saved something to revisit."
        content.sound = .default
        content.userInfo = ["captureID": reminder.captureID.uuidString,
                            "revision": reminder.revision,
                            "reminderAt": reminder.date.timeIntervalSince1970]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.date)
        components.timeZone = calendar.timeZone
        components.calendar = calendar
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await center.add(UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger))
    }

    func removePending(_ identifiers: [String]) {
        if !identifiers.isEmpty { center.removePendingNotificationRequests(withIdentifiers: identifiers) }
    }

    func removeDelivered(_ identifiers: [String]) {
        if !identifiers.isEmpty { center.removeDeliveredNotifications(withIdentifiers: identifiers) }
    }
}
