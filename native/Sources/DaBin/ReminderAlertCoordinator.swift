import AppKit
import Combine
import CryptoKit

/// Restores saved overdue occurrences and schedules one nearest-deadline wakeup.
/// Presentation is passive; persistence is changed only by explicit acknowledgement.
@MainActor
final class ReminderAlertCoordinator {
    private let store: CaptureStore
    private let now: () -> Date
    private var timer: Timer?
    private var subscriptions = Set<AnyCancellable>()
    private var refreshQueued = false
    private(set) var isStarted = false
    var onAlertsChanged: (([TaskTimerCompletion], Set<UUID>) -> Void)?

    init(store: CaptureStore, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
    }

    func start(applicationEvents: NotificationCenter = .default,
               workspaceEvents: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        guard !isStarted else { return }
        isStarted = true
        store.objectWillChange.sink { [weak self] _ in self?.queueRefresh() }.store(in: &subscriptions)
        for name in [NSApplication.didBecomeActiveNotification, Notification.Name.NSSystemClockDidChange,
                     Notification.Name.NSSystemTimeZoneDidChange] {
            applicationEvents.publisher(for: name).receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.queueRefresh() }.store(in: &subscriptions)
        }
        workspaceEvents.publisher(for: NSWorkspace.didWakeNotification).receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.queueRefresh() }.store(in: &subscriptions)
        reconcile()
    }

    func reconcile() {
        guard isStarted else { return }
        timer?.invalidate(); timer = nil
        let instant = now()
        let current = store.captures.filter { !$0.isTask || !$0.isCompleted }
        var alerts: [TaskTimerCompletion] = []
        var nextDate: Date?
        for capture in current {
            if let due = capture.reminderAt, !capture.isReminderAcknowledged {
                if due <= instant {
                    alerts.append(TaskTimerCompletion(id: Self.receiptID(captureID: capture.id,
                        revision: capture.reminderRevision, date: due), taskID: capture.id,
                        title: capture.title, dueAt: due, reminderRevision: capture.reminderRevision))
                } else { nextDate = min(nextDate ?? due, due) }
            }
            if capture.isTask, let session = capture.taskPlanning?.focusSession,
               let id = session.completedAlertID, session.acknowledgedAt == nil,
               session.remainingSeconds == 0, session.endAt == nil {
                if let completedAt = session.completedAt, completedAt > instant {
                    nextDate = min(nextDate ?? completedAt, completedAt)
                } else {
                    alerts.append(TaskTimerCompletion(id: id, taskID: capture.id, title: capture.title,
                                                      dueAt: session.completedAt))
                }
            }
        }
        alerts.sort { ($0.dueAt ?? .distantPast, $0.id.uuidString) < ($1.dueAt ?? .distantPast, $1.id.uuidString) }
        onAlertsChanged?(alerts, Set(current.map(\.id)))
        guard isStarted, let nextDate else { return }
        let delay = max(0.05, nextDate.timeIntervalSince(instant))
        let next = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reconcile() }
        }
        next.tolerance = min(0.5, delay * 0.01)
        timer = next
        RunLoop.main.add(next, forMode: .common)
    }

    func stop() {
        isStarted = false
        timer?.invalidate(); timer = nil
        subscriptions.removeAll()
        onAlertsChanged = nil
    }

    private func queueRefresh() {
        guard isStarted, !refreshQueued else { return }
        refreshQueued = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.refreshQueued = false
            self.reconcile()
        }
    }

    static func receiptID(captureID: UUID, revision: Int, date: Date) -> UUID {
        let value = "\(captureID.uuidString)|\(revision)|\(date.timeIntervalSinceReferenceDate.bitPattern)"
        let bytes = Array(SHA256.hash(data: Data(value.utf8)).prefix(16))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    deinit { timer?.invalidate() }
}
