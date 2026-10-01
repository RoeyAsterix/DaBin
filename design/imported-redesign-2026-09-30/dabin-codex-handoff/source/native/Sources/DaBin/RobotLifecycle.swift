import Foundation

/// Value-only coordination for the one robot shared by capture, reveal, and
/// full-app transitions. Every animated step receives a generation. Callers
/// must return that generation with `animationCompleted`; stale callbacks are
/// ignored after an interrupt, a display change, or a higher-priority open.
struct RobotLifecycle: Equatable, Sendable {
    enum State: String, CaseIterable, Hashable, Sendable {
        case hidden
        case peeking
        case climbingOut
        case waitingForCapture
        case eatingCapture
        case captureReaction
        case returningToIsland
        case preparingToExpand
        case expandingToApp
        case fullScreen
        case collapsingApp
    }

    enum Endpoint: Hashable, Sendable {
        case hidden
        case fullScreen
    }

    enum Event: Equatable, Sendable {
        case captureSaved(count: Int)
        case openRequested
        case closeRequested
        case animationCompleted(generation: UInt64)
        case advance(to: State, generation: UInt64)
        case interrupt(toward: Endpoint)
        case displayChanged(hasDisplay: Bool)
    }

    enum Effect: Equatable, Sendable {
        case cancelAnimation
        case animate(State, generation: UInt64)
        case updateCaptureCount(Int)
        case reposition
        case showFullScreen
        case hide
    }

    private(set) var state: State
    private(set) var generation: UInt64
    private(set) var pendingCaptureCount: Int
    private(set) var hasDisplay: Bool
    private var recoveryEndpoint: Endpoint

    init(state: State = .hidden, generation: UInt64 = 0,
         pendingCaptureCount: Int = 0, hasDisplay: Bool = true) {
        self.state = state
        self.generation = generation
        self.pendingCaptureCount = max(0, pendingCaptureCount)
        self.hasDisplay = hasDisplay
        self.recoveryEndpoint = Self.recoveryEndpoint(for: state)
    }

    var isCaptureSequence: Bool { Self.captureStates.contains(state) }
    var isOpening: Bool { state == .preparingToExpand || state == .expandingToApp }
    var isAppVisible: Bool { state == .fullScreen }
    var isTransitioning: Bool {
        state != .hidden && state != .waitingForCapture && state != .fullScreen
    }

    @discardableResult
    mutating func send(_ event: Event) -> [Effect] {
        switch event {
        case .captureSaved(let count):
            return receiveCapture(count)
        case .openRequested:
            return requestOpen()
        case .closeRequested:
            return requestClose()
        case .animationCompleted(let candidate):
            guard candidate == generation, let next = completionTarget(from: state) else { return [] }
            return move(to: next, cancelCurrent: false)
        case .advance(let target, let candidate):
            guard candidate == generation, Self.allowedNextStates[state]?.contains(target) == true else {
                return []
            }
            return move(to: target, cancelCurrent: false)
        case .interrupt(let endpoint):
            return settle(at: endpoint, cancelCurrent: true)
        case .displayChanged(let available):
            return displayChanged(available)
        }
    }

    private mutating func receiveCapture(_ count: Int) -> [Effect] {
        guard count > 0 else { return [] }
        pendingCaptureCount = Self.saturatingAdd(pendingCaptureCount, count)

        guard hasDisplay else { return [] }
        if state == .hidden {
            return move(to: .peeking, cancelCurrent: false, prefix: [.updateCaptureCount(pendingCaptureCount)])
        }
        if state == .returningToIsland {
            return move(to: .eatingCapture, cancelCurrent: true,
                        prefix: [.updateCaptureCount(pendingCaptureCount)])
        }
        if isCaptureSequence {
            return [.updateCaptureCount(pendingCaptureCount)]
        }
        // Captures received while the app opens or is visible stay pending.
        // The presenter resumes them after the board has fully collapsed.
        return []
    }

    private mutating func requestOpen() -> [Effect] {
        guard hasDisplay else {
            recoveryEndpoint = .fullScreen
            return []
        }
        guard state != .fullScreen, !isOpening else { return [] }
        return move(to: .preparingToExpand, cancelCurrent: state != .hidden)
    }

    private mutating func requestClose() -> [Effect] {
        switch state {
        case .preparingToExpand, .expandingToApp, .fullScreen:
            return move(to: .collapsingApp, cancelCurrent: state != .fullScreen)
        case .peeking, .climbingOut, .waitingForCapture, .eatingCapture, .captureReaction:
            return move(to: .returningToIsland, cancelCurrent: true)
        case .returningToIsland, .collapsingApp, .hidden:
            return []
        }
    }

    private mutating func displayChanged(_ available: Bool) -> [Effect] {
        if !available {
            guard hasDisplay || state != .hidden else { return [] }
            hasDisplay = false
            recoveryEndpoint = Self.recoveryEndpoint(for: state)
            generation &+= 1
            state = .hidden
            return [.cancelAnimation, .hide]
        }

        let wasUnavailable = !hasDisplay
        hasDisplay = true
        let endpoint = wasUnavailable ? recoveryEndpoint : Self.recoveryEndpoint(for: state)
        switch endpoint {
        case .fullScreen:
            generation &+= 1
            state = .fullScreen
            recoveryEndpoint = .fullScreen
            return [.cancelAnimation, .reposition, .showFullScreen]
        case .hidden:
            if pendingCaptureCount > 0, wasUnavailable {
                state = .hidden
                return move(to: .peeking, cancelCurrent: true,
                            prefix: [.reposition, .updateCaptureCount(pendingCaptureCount)])
            }
            generation &+= 1
            state = .hidden
            recoveryEndpoint = .hidden
            return [.cancelAnimation, .reposition, .hide]
        }
    }

    private mutating func settle(at endpoint: Endpoint, cancelCurrent: Bool) -> [Effect] {
        generation &+= 1
        recoveryEndpoint = endpoint
        switch endpoint {
        case .hidden:
            state = .hidden
            pendingCaptureCount = 0
            return (cancelCurrent ? [.cancelAnimation] : []) + [.hide]
        case .fullScreen:
            state = .fullScreen
            return (cancelCurrent ? [.cancelAnimation] : []) + (hasDisplay ? [.showFullScreen] : [])
        }
    }

    private mutating func move(to target: State, cancelCurrent: Bool,
                               prefix: [Effect] = []) -> [Effect] {
        generation &+= 1
        state = target
        recoveryEndpoint = Self.recoveryEndpoint(for: target)
        var effects = prefix
        if cancelCurrent { effects.append(.cancelAnimation) }
        switch target {
        case .hidden:
            pendingCaptureCount = 0
            effects.append(.hide)
        case .fullScreen:
            effects.append(.showFullScreen)
        default:
            effects.append(.animate(target, generation: generation))
        }
        return effects
    }

    private func completionTarget(from state: State) -> State? {
        switch state {
        case .peeking: return .climbingOut
        case .climbingOut: return .waitingForCapture
        case .waitingForCapture: return .eatingCapture
        case .eatingCapture: return .captureReaction
        case .captureReaction: return .returningToIsland
        case .returningToIsland: return .hidden
        case .preparingToExpand: return .expandingToApp
        case .expandingToApp: return .fullScreen
        case .collapsingApp: return .hidden
        case .hidden, .fullScreen: return nil
        }
    }

    private static let captureStates: Set<State> = [
        .peeking, .climbingOut, .waitingForCapture, .eatingCapture,
        .captureReaction, .returningToIsland
    ]

    private static let allowedNextStates: [State: Set<State>] = [
        .hidden: [.peeking, .preparingToExpand],
        .peeking: [.climbingOut, .preparingToExpand, .returningToIsland],
        .climbingOut: [.waitingForCapture, .preparingToExpand, .returningToIsland],
        .waitingForCapture: [.eatingCapture, .preparingToExpand, .returningToIsland],
        .eatingCapture: [.captureReaction, .preparingToExpand, .returningToIsland],
        .captureReaction: [.returningToIsland, .preparingToExpand],
        .returningToIsland: [.hidden, .eatingCapture, .preparingToExpand],
        .preparingToExpand: [.expandingToApp, .collapsingApp, .fullScreen],
        .expandingToApp: [.fullScreen, .collapsingApp],
        .fullScreen: [.collapsingApp],
        .collapsingApp: [.hidden, .preparingToExpand]
    ]

    private static func recoveryEndpoint(for state: State) -> Endpoint {
        switch state {
        case .preparingToExpand, .expandingToApp, .fullScreen:
            return .fullScreen
        default:
            return .hidden
        }
    }

    private static func saturatingAdd(_ lhs: Int, _ rhs: Int) -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int.max : sum
    }
}
