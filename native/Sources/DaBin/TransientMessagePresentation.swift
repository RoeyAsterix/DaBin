import Combine
import Foundation

enum TransientMessagePolicy {
    static let maximumDisplayDuration: Duration = .seconds(2)
}

/// A presentation receipt, not the underlying operation/error state. Identical
/// messages are new receipts; a canceled expiry can never hide their successor.
@MainActor
final class TransientMessagePresentation<Message: Equatable>: ObservableObject {
    @Published private(set) var message: Message?
    @Published private(set) var revision: UInt = 0
    private let now: @MainActor () -> ContinuousClock.Instant
    private let sleep: @Sendable (Duration) async throws -> Void
    private var deadline: ContinuousClock.Instant?
    private var expiry: Task<Void, Never>?
    private var isStopped = false

    init(now: @escaping @MainActor () -> ContinuousClock.Instant = { ContinuousClock().now },
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.now = now
        self.sleep = sleep
    }

    /// The deadline also gates rendering after sleep/wake or a delayed callback.
    var visibleMessage: Message? {
        guard !isStopped, let deadline, now() < deadline else { return nil }
        return message
    }

    func present(_ value: Message?) {
        guard !isStopped else { return }
        // Recycling a lazy row with no feedback must not publish another
        // invalidation into the layout transaction that removed that row.
        guard value != nil || message != nil || deadline != nil || expiry != nil else { return }
        expiry?.cancel()
        expiry = nil
        revision &+= 1
        guard let value else {
            deadline = nil
            message = nil
            return
        }
        deadline = now().advanced(by: TransientMessagePolicy.maximumDisplayDuration)
        message = value
        let receipt = revision
        let sleeper = sleep
        expiry = Task { [weak self] in
            do { try await sleeper(TransientMessagePolicy.maximumDisplayDuration) }
            catch { return }
            guard !Task.isCancelled, let self, !self.isStopped, self.revision == receipt else { return }
            self.deadline = nil
            self.message = nil
            self.expiry = nil
        }
    }

    func dismiss() { present(nil) }

    func shutdown() {
        guard !isStopped else { return }
        dismiss()
        isStopped = true
    }

    deinit { expiry?.cancel() }
}
