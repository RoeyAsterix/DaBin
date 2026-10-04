import AppKit
import SwiftUI

/// Document surfaces opt out before the window's workspace dispatcher chooses
/// an owner. This also covers passive overlays whose hitTest intentionally is nil.
@MainActor protocol DaBinDocumentGestureOwner: AnyObject {}

@MainActor struct WorkspaceInputRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> WorkspaceInputRegionView { WorkspaceInputRegionView() }
    func updateNSView(_ nsView: WorkspaceInputRegionView, context: Context) {}
}
@MainActor final class WorkspaceInputRegionView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

enum WorkspaceCommand: Equatable { case back, forward, zoomIn, zoomOut, resetZoom }

/// Pure input classification keeps driver-specific button mapping small and
/// leaves every unrecognized input to AppKit. Never infer navigation from
/// ordinary wheel deltas: only AppKit's completed native swipe amount commits.
enum WorkspaceInputPolicy {
    static func command(characters: String, modifiers: NSEvent.ModifierFlags) -> WorkspaceCommand? {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
        guard flags == .command || flags == [.command, .shift] else { return nil }
        switch characters {
        case "[" where flags == .command: return .back
        case "]" where flags == .command: return .forward
        case "=", "+": return .zoomIn
        case "-" where flags == .command: return .zoomOut
        case "0" where flags == .command: return .resetZoom
        default: return nil
        }
    }
    static func auxiliaryButton(_ number: Int) -> WorkspaceCommand? {
        switch number { case 3: return .back; case 4: return .forward; default: return nil }
    }
    static func completedSwipe(amount: CGFloat, cancelled: Bool) -> WorkspaceCommand? {
        guard !cancelled, amount.isFinite, abs(amount) >= 0.99 else { return nil }
        return amount > 0 ? .back : .forward
    }
    static func qualifiesForWheelZoom(modifiers: NSEvent.ModifierFlags, momentum: NSEvent.Phase) -> Bool {
        modifiers.contains(.command) && !modifiers.contains(.control) && momentum.isEmpty
    }
}

/// Window-local gesture ownership. No monitors, permission prompts, background
/// hooks or blocking event loops. Child ownership is latched for a whole gesture.
@MainActor final class WorkspaceInputController {
    enum Owner: Equatable { case undecided, child, scrolling, zoom, swipe }
    private weak var state: AppState?
    private weak var host: NSView?
    private(set) var owner: Owner?
    private var pendingFactor: CGFloat?
    private var displayTimer: Timer?
    private var wheelTimer: Timer?
    private var gestureGeneration = 0
    private var receivedBegan = false
    private var beganOverHorizontalScroller = false
    private var consumesZoomMomentum = false
    private var checkingFirstResponder = false
    private var lastCommandEvent: EventIdentity?
    private var observers: [NSObjectProtocol] = []
    var swipePreference: () -> Bool = { NSEvent.isSwipeTrackingFromScrollEventsEnabled }
    /// The real recognizer owns completion/cancellation and semantic direction.
    /// Injection lets native fixtures verify callbacks without global gestures.
    var trackSwipe: (NSEvent, CGFloat, CGFloat, @escaping (CGFloat, NSEvent.Phase, Bool, UnsafeMutablePointer<ObjCBool>) -> Void) -> Void = { event, minimum, maximum, handler in
        event.trackSwipeEvent(options: [.lockDirection, .clampGestureAmount],
            dampenAmountThresholdMin: minimum, max: maximum, usingHandler: handler)
    }
    private struct EventIdentity: Equatable {
        var timestamp: TimeInterval; var window: Int; var type: UInt; var key: UInt16
        var modifiers: UInt; var characters: String?
        init(_ event: NSEvent) {
            timestamp = event.timestamp; window = event.windowNumber; type = event.type.rawValue
            switch event.type {
            case .keyDown: key = event.keyCode
            case .otherMouseUp, .otherMouseDown: key = UInt16(clamping: event.buttonNumber)
            default: key = 0
            }
            modifiers = event.modifierFlags.rawValue
            characters = event.type == .keyDown ? event.charactersIgnoringModifiers : nil
        }
    }
    init(state: AppState, host: NSView) { self.state = state; self.host = host }
    func attach(to window: NSWindow?) {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        guard let window else { cancel(); return }
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification,
                     NSWindow.willBeginSheetNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancel() }
            })
        }
    }
    deinit {
        displayTimer?.invalidate(); wheelTimer?.invalidate()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
    private var window: NSWindow? { host?.window }
    var blocked: Bool {
        guard let state, let window, window.isVisible else { return true }
        return state.isWorkspaceInputBlocked || window.attachedSheet != nil || NSApp.modalWindow != nil
            || (window.firstResponder as? NSTextView)?.hasMarkedText() == true
            || NSEvent.pressedMouseButtons & 1 != 0
    }
    func enabled(_ command: WorkspaceCommand) -> Bool {
        guard let state, !blocked else { return false }
        switch command {
        case .back: return !state.workspaceZoom.isInteracting && state.canGoBack
        case .forward: return !state.workspaceZoom.isInteracting && state.canGoForward
        case .zoomIn: return state.route != .settings && state.workspaceZoom.canZoomIn
        case .zoomOut: return state.route != .settings && state.workspaceZoom.canZoomOut
        case .resetZoom: return state.route != .settings && state.workspaceZoom.factor != 1
        }
    }
    @discardableResult func perform(_ command: WorkspaceCommand, event: NSEvent? = nil) -> Bool {
        if let event, lastCommandEvent == EventIdentity(event) { return true }
        guard enabled(command), let state else { return false }
        if let event { lastCommandEvent = EventIdentity(event) }
        switch command {
        case .back: state.back()
        case .forward: state.forward()
        case .zoomIn, .zoomOut, .resetZoom:
            cancel()
            state.workspaceZoom.anchorInWindow = nil
            switch command {
            case .zoomIn: state.workspaceZoom.stepIn()
            case .zoomOut: state.workspaceZoom.stepOut()
            default: state.workspaceZoom.reset()
            }
        }
        return true
    }
    func key(_ event: NSEvent) -> Bool {
        guard !checkingFirstResponder, event.type == .keyDown, window?.isKeyWindow == true,
              event.windowNumber == window?.windowNumber,
              let command = WorkspaceInputPolicy.command(characters: event.charactersIgnoringModifiers ?? "", modifiers: event.modifierFlags) else { return false }
        if lastCommandEvent == EventIdentity(event) { return true }
        guard !blocked else { return false }
        // Child responders get first refusal without recursing back through the
        // hosting view. Document commands keep their native responder chain.
        if let responder = window?.firstResponder as? NSView {
            if isDocument(responder) { return false }
            if responder !== host, responder !== window?.contentView {
                checkingFirstResponder = true
                let handled = responder.performKeyEquivalent(with: event)
                checkingFirstResponder = false
                if handled { lastCommandEvent = EventIdentity(event); return true }
            }
        }
        guard !event.isARepeat else { return true }
        return perform(command, event: event)
    }
    func handle(_ event: NSEvent) -> Bool {
        guard let window, let state, event.windowNumber == window.windowNumber,
              window.isKeyWindow, window.isVisible else { return false }
        if blocked { cancel(); return false }
        if event.type == .otherMouseUp, let command = WorkspaceInputPolicy.auxiliaryButton(event.buttonNumber) {
            return perform(command, event: event)
        }
        guard [.scrollWheel, .magnify, .swipe].contains(event.type) else { return false }
        if event.modifierFlags.contains(.control) { cancel(); return false }
        if event.type == .scrollWheel, !event.momentumPhase.isEmpty, consumesZoomMomentum {
            if event.momentumPhase.contains(.ended) { consumesZoomMomentum = false }
            return true
        }
        if event.phase.contains(.began) || event.phase.contains(.mayBegin)
            || (event.type == .scrollWheel && event.phase.isEmpty && event.momentumPhase.isEmpty) {
            consumesZoomMomentum = false
        }
        let began = event.phase.contains(.began)
        let ended = event.phase.contains(.ended) || event.phase.contains(.cancelled)
        // mayBegin chooses the surface once. The later began must not re-hit
        // test under a moved pointer and steal a child's existing gesture.
        if began, receivedBegan { cancel() }
        if began { receivedBegan = true }
        if owner == nil {
            guard (!ended || (event.type == .swipe && !event.phase.contains(.cancelled))),
                  event.momentumPhase.isEmpty else { return false }
            guard insideWorkspace(event.locationInWindow) else { return false }
            beganOverHorizontalScroller = horizontalScrollerOwns(event.locationInWindow)
            owner = documentOwns(event.locationInWindow) ? .child : .undecided
        }
        // A horizontal scroller reserves scrolling, not magnification. Keep
        // the initial surface through mayBegin without stealing a later pinch.
        if owner == .undecided, beganOverHorizontalScroller {
            let wheelZoom = WorkspaceInputPolicy.qualifiesForWheelZoom(modifiers: event.modifierFlags, momentum: event.momentumPhase)
            if event.type == .swipe || (event.type == .scrollWheel && !wheelZoom
                && (event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 || began)) { owner = .child }
        }
        if owner == .child {
            if ended { clearOwner() }
            return false
        }
        // An ended/cancelled zero event only finishes its existing owner. It
        // never starts magnification or commits page navigation by itself.
        if ended && owner != .swipe && event.type != .swipe {
            let consumed = owner == .zoom
            if consumed, event.type == .scrollWheel, !event.phase.contains(.cancelled) {
                scheduleWheelFinish()
            } else if consumed { finish() } else { clearOwner() }
            return consumed
        }
        // Secondary recognizers cannot tear down the current physical owner.
        // In particular an unrelated swipe must not orphan an active pinch.
        if owner == .zoom && event.type == .swipe { return true }
        if owner == .swipe && event.type == .magnify { return true }
        if event.type == .magnify {
            guard owner == .undecided || owner == .zoom else { return false }
            if owner == .undecided, !beginZoom(at: event.locationInWindow) { cancel(); return false }
            queueFactor((pendingFactor ?? state.workspaceZoom.factor) * (1 + event.magnification))
            if ended { finish() }
            return true
        }
        if event.type == .swipe {
            defer { clearOwner() }
            guard owner == .undecided, state.workspaceZoom.trackpadNavigationEnabled,
                  swipePreference(), !event.phase.contains(.cancelled), event.deltaY == 0,
                  abs(event.deltaX) == 1 else { return false }
            // Recognized NSEvent.swipe has AppKit's semantic direction, unlike raw wheel data.
            return perform(event.deltaX > 0 ? .back : .forward, event: event)
        }
        if WorkspaceInputPolicy.qualifiesForWheelZoom(modifiers: event.modifierFlags, momentum: event.momentumPhase),
           owner == .undecided || owner == .zoom {
            if owner == .undecided, !beginZoom(at: event.locationInWindow) { cancel(); return false }
            let delta = event.scrollingDeltaY
            if delta.isFinite { queueFactor((pendingFactor ?? state.workspaceZoom.factor) * exp(delta * 0.006)) }
            consumesZoomMomentum = true
            scheduleWheelFinish()
            return true
        }
        if owner == .zoom { if ended { finish() }; return true }
        if owner == .swipe { return true }
        if owner == .scrolling { if ended { owner = nil }; return false }
        guard event.momentumPhase.isEmpty, event.hasPreciseScrollingDeltas,
              !event.phase.isEmpty, state.workspaceZoom.trackpadNavigationEnabled, swipePreference() else {
            owner = ended || event.phase.isEmpty ? nil : .scrolling
            return false
        }
        let x = abs(event.scrollingDeltaX), y = abs(event.scrollingDeltaY)
        if y > x { owner = ended ? nil : .scrolling; return false }
        guard x > y, x > 0, !ended else { if ended { clearOwner() }; return false }
        guard event.phase.contains(.began) || event.phase.contains(.changed) else { return false }
        guard !state.workspaceZoom.isInteracting, state.canGoBack || state.canGoForward else { clearOwner(); return false }
        owner = .swipe
        let generation = gestureGeneration
        var cancelled = false
        var completed = false
        trackSwipe(event, state.canGoForward ? -1 : 0, state.canGoBack ? 1 : 0) { [weak self] amount, phase, complete, stop in
            guard let self, !completed, generation == self.gestureGeneration else {
                stop.pointee = true
                return
            }
            guard !self.blocked, self.window?.isKeyWindow == true else {
                stop.pointee = true
                // AppKit stops delivering this recognizer after stop becomes
                // true. Release its owner now rather than waiting for an end
                // callback that will never arrive. Stale generations above
                // cannot cancel a newer gesture.
                self.cancel()
                return
            }
            if phase.contains(.cancelled) { cancelled = true }
            guard complete else { return }
            completed = true
            self.clearOwner()
            if let command = WorkspaceInputPolicy.completedSwipe(amount: amount, cancelled: cancelled) {
                _ = self.perform(command)
            }
        }
        return true
    }
    private func scheduleWheelFinish() {
        wheelTimer?.invalidate()
        let timer = Timer(timeInterval: 0.2, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish() }
        }
        wheelTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    private func beginZoom(at point: CGPoint) -> Bool {
        guard let state, state.route != .settings else { return false }
        state.workspaceZoom.anchorInWindow = point
        guard state.workspaceZoom.beginInteraction() else { return false }
        owner = .zoom
        return true
    }
    private func queueFactor(_ proposed: CGFloat) {
        guard let next = WorkspaceZoomSettings.validated(proposed) else { return }
        pendingFactor = next
        guard displayTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
        displayTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    func flush() {
        displayTimer?.invalidate(); displayTimer = nil
        if let pendingFactor { state?.workspaceZoom.update(to: pendingFactor) }
        pendingFactor = nil
    }
    func finish() {
        flush(); wheelTimer?.invalidate(); wheelTimer = nil
        state?.workspaceZoom.finishInteraction(); clearOwner()
    }
    private func clearOwner() { owner = nil; receivedBegan = false; beganOverHorizontalScroller = false }
    func cancel() { gestureGeneration &+= 1; finish() }
    private func isDocument(_ view: NSView) -> Bool {
        var candidate: NSView? = view
        while let value = candidate {
            if value is DaBinDocumentGestureOwner { return true }; candidate = value.superview
        }
        return false
    }
    private func matchingSurface(in view: NSView, at point: CGPoint, matches: (NSView) -> Bool) -> Bool {
        guard !view.isHiddenOrHasHiddenAncestor, view.visibleRect.contains(view.convert(point, from: nil)) else { return false }
        return matches(view) || view.subviews.contains { matchingSurface(in: $0, at: point, matches: matches) }
    }
    private func insideWorkspace(_ point: CGPoint) -> Bool {
        guard let host else { return false }
        return matchingSurface(in: host, at: point) { $0 is WorkspaceInputRegionView }
    }
    private func documentOwns(_ point: CGPoint) -> Bool {
        guard let host else { return true }
        return matchingSurface(in: host, at: point) { $0 is DaBinDocumentGestureOwner }
    }
    private func horizontalScrollerOwns(_ point: CGPoint) -> Bool {
        guard let host else { return false }
        var view = host.hitTest(host.convert(point, from: nil))
        while let current = view {
            if let scroll = current as? NSScrollView,
               scroll.hasHorizontalScroller || (scroll.documentView?.frame.width ?? 0) > scroll.contentSize.width + 2 { return true }
            view = current.superview
        }
        return false
    }
}
