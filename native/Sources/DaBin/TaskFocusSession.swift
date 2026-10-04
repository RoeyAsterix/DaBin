import AppKit
import Combine
import Foundation

/// One lightweight countdown, never a time ledger. Persist only explicit
/// transitions and expiry; views derive each displayed second from the deadline.
struct TaskFocusSession: Codable, Equatable, Sendable {
    var remainingSeconds: TimeInterval
    var endAt: Date?
    /// Expiry is a durable occurrence, independent of whether the app remains
    /// open long enough for the user to acknowledge its robot.
    var completedAlertID: UUID? = nil
    var completedAt: Date? = nil
    var acknowledgedAt: Date? = nil

    var isValid: Bool {
        guard (completedAlertID == nil) == (completedAt == nil),
              completedAlertID == nil || (remainingSeconds == 0 && endAt == nil),
              acknowledgedAt == nil || (completedAt != nil && acknowledgedAt! >= completedAt!) else { return false }
        return remainingSeconds.isFinite && (0...604_800).contains(remainingSeconds)
        && (endAt.map { $0.timeIntervalSinceReferenceDate.isFinite } ?? true)
        && (completedAt.map { $0.timeIntervalSinceReferenceDate.isFinite } ?? true)
        && (acknowledgedAt.map { $0.timeIntervalSinceReferenceDate.isFinite } ?? true)
    }
    var isRunning: Bool { endAt != nil }
    func remaining(at now: Date) -> TimeInterval {
        // A backward clock adjustment cannot extend a session beyond the amount
        // last started. Forward changes and sleep follow the persisted end date.
        max(0, min(remainingSeconds, endAt.map { $0.timeIntervalSince(now) } ?? remainingSeconds))
    }
    func paused(at now: Date) -> Self {
        let seconds = remaining(at: now)
        if seconds == 0, let deadline = endAt {
            return Self(remainingSeconds: 0, endAt: nil, completedAlertID: UUID(), completedAt: deadline)
        }
        return Self(remainingSeconds: seconds, endAt: nil, completedAlertID: completedAlertID,
                    completedAt: completedAt, acknowledgedAt: acknowledgedAt)
    }
    func started(at now: Date, durationMinutes: Int) -> Self {
        let seconds = remaining(at: now)
        let target = seconds > 0 ? seconds : TimeInterval(durationMinutes * 60)
        return Self(remainingSeconds: target, endAt: now.addingTimeInterval(target))
    }
    static func duration(hours: Int, minutes: Int) -> Int? {
        guard (0...168).contains(hours), (0...59).contains(minutes) else { return nil }
        let total = hours * 60 + minutes
        return (1...10_080).contains(total) ? total : nil
    }
    static func clock(_ seconds: TimeInterval) -> String {
        let whole = Int(ceil(max(0, min(604_800, seconds.isFinite ? seconds : 0))))
        return String(format: "%02d:%02d:%02d", whole / 3600, whole / 60 % 60, whole % 60)
    }
}

/// A single nearest-expiry wakeup across all tasks. No per-second persistence,
/// no notifications, and no timer rendering work while the board is hidden.
@MainActor
final class TaskFocusCoordinator {
    private weak var store: CaptureStore?
    private var timer: Timer?
    private var subscriptions = Set<AnyCancellable>()
    private var queued = false
    private(set) var isShutDown = false
    var onExpired: (([Capture]) -> Void)?
    var onFailure: ((String) -> Void)?

    init(store: CaptureStore) {
        self.store = store
        store.objectWillChange.sink { [weak self] _ in self?.queueRefresh() }.store(in: &subscriptions)
        for name in [NSApplication.didBecomeActiveNotification, Notification.Name.NSSystemClockDidChange,
                     Notification.Name.NSSystemTimeZoneDidChange] {
            NotificationCenter.default.publisher(for: name).receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.queueRefresh() }.store(in: &subscriptions)
        }
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.queueRefresh() }.store(in: &subscriptions)
        queueRefresh()
    }
    deinit { timer?.invalidate() }

    private func queueRefresh() {
        guard !isShutDown, !queued else { return }
        queued = true
        Task { @MainActor [weak self] in
            guard let self, !self.isShutDown else { return }
            self.queued = false
            self.reconcile()
        }
    }

    func reconcile(at now: Date = Date()) {
        guard !isShutDown else { return }
        timer?.invalidate(); timer = nil
        guard let store else { return }
        var expired: [Capture] = []
        var failed = false
        for capture in store.captures where capture.isTask && !capture.isCompleted {
            guard let session = capture.taskPlanning?.focusSession, session.isRunning,
                  session.remaining(at: now) == 0 else { continue }
            do { try store.setTaskFocus(capture, session: session.paused(at: now)); expired.append(capture) }
            catch {
                failed = true
                onFailure?("The focus session ended, but its status could not be saved. DaBin will retry.")
                guard !isShutDown else { return }
            }
        }
        if !expired.isEmpty {
            onExpired?(expired)
            guard !isShutDown else { return }
        }
        let deadlines = store.captures.filter { $0.isTask && !$0.isCompleted }
            .compactMap { $0.taskPlanning?.focusSession?.endAt }.filter { $0 > now }
        let delay = deadlines.min().map { max(0.05, $0.timeIntervalSince(now)) }
        guard let seconds = failed ? min(delay ?? 30, 30) : delay else { return }
        let next = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reconcile() }
        }
        next.tolerance = min(1, seconds * 0.05)
        timer = next
        RunLoop.main.add(next, forMode: .common)
    }

    func shutdown() {
        guard !isShutDown else { return }
        isShutDown = true
        timer?.invalidate(); timer = nil
        subscriptions.removeAll()
        queued = false
        onExpired = nil; onFailure = nil
    }
}
