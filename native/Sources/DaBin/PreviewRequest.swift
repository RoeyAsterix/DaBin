import Foundation

/// Adapts callback work into one cancellable result. Completion, timeout and
/// cancellation may race; the provider is stopped only for timeout/cancellation.
final class PreviewRequest<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?
    private var cancelledBeforeStart: Value?
    private var finished = false
    private var cancelled = false
    private var stopProvider: (@Sendable () -> Void)?
    private var timeout: DispatchWorkItem?

    static func perform(timeout seconds: TimeInterval, timeoutValue: Value, cancelledValue: Value,
                        start: (@escaping @Sendable (Value) -> Void) -> @Sendable () -> Void) async -> Value {
        let request = PreviewRequest<Value>()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard request.begin(continuation) else { return }
                let stop = start { request.finish($0) }
                request.installCancellation(stop)
                request.scheduleTimeout(after: seconds, value: timeoutValue)
            }
        } onCancel: {
            request.cancel(returning: cancelledValue)
        }
    }

    private func begin(_ continuation: CheckedContinuation<Value, Never>) -> Bool {
        lock.lock()
        let priorCancellation = cancelledBeforeStart
        cancelledBeforeStart = nil
        if !finished { self.continuation = continuation }
        lock.unlock()
        if let priorCancellation { continuation.resume(returning: priorCancellation); return false }
        return true
    }

    private func installCancellation(_ stop: @escaping @Sendable () -> Void) {
        lock.lock()
        let mustStop = cancelled
        if !finished { stopProvider = stop }
        lock.unlock()
        // Cancellation can happen while the provider is starting. Registering
        // its stop callback afterwards must still stop the newly started work.
        if mustStop { stop() }
    }

    private func scheduleTimeout(after seconds: TimeInterval, value: Value) {
        let work = DispatchWorkItem { [weak self] in self?.cancel(returning: value) }
        lock.lock()
        let shouldSchedule = !finished
        if shouldSchedule { timeout = work }
        lock.unlock()
        if shouldSchedule { DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + seconds, execute: work) }
    }

    private func finish(_ value: Value) {
        complete(value, cancelProvider: false)
    }

    private func cancel(returning value: Value) {
        complete(value, cancelProvider: true)
    }

    private func complete(_ value: Value, cancelProvider: Bool) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        cancelled = cancelProvider
        let pending = continuation
        if pending == nil, cancelProvider { cancelledBeforeStart = value }
        let stop = cancelProvider ? stopProvider : nil
        let timer = timeout
        continuation = nil
        stopProvider = nil
        timeout = nil
        lock.unlock()
        timer?.cancel()
        stop?()
        pending?.resume(returning: value)
    }
}
