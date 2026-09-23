import AppKit
import Foundation

/// Rechecks notification authorization when the user returns from System Settings
/// or the Mac wakes. Bursts of lifecycle events never queue an unbounded backlog.
@MainActor
final class ReminderLifecycle {
    private let reconcile: @MainActor () async -> Void
    private var observations: [(NotificationCenter, NSObjectProtocol)] = []
    private var reconciliation: Task<Void, Never>?
    private var needsReconciliation = false
    private var started = false

    init(reconcile: @escaping @MainActor () async -> Void) {
        self.reconcile = reconcile
    }

    func start(applicationEvents: NotificationCenter = .default,
               workspaceEvents: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        guard !started else { return }
        started = true
        observe(NSApplication.didBecomeActiveNotification, in: applicationEvents)
        observe(NSWorkspace.didWakeNotification, in: workspaceEvents)
        requestReconciliation()
    }

    func stop() {
        started = false
        needsReconciliation = false
        for (center, token) in observations { center.removeObserver(token) }
        observations.removeAll()
    }

    private func observe(_ name: Notification.Name, in center: NotificationCenter) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.requestReconciliation() }
        }
        observations.append((center, token))
    }

    private func requestReconciliation() {
        guard started else { return }
        needsReconciliation = true
        guard reconciliation == nil else { return }
        reconciliation = Task { @MainActor [weak self] in
            guard let self else { return }
            while self.needsReconciliation {
                self.needsReconciliation = false
                await self.reconcile()
            }
            self.reconciliation = nil
        }
    }

    deinit {
        for (center, token) in observations { center.removeObserver(token) }
    }
}
