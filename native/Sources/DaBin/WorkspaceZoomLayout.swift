import AppKit
import SwiftUI

/// Content measurements only. Navigation, native controls, robot chrome and
/// sheets keep their own dimensions. Typography grows gently while previews
/// and content geometry follow the full zoom; text stays natively rendered.
struct WorkspaceZoomLayout: Equatable {
    let factor: CGFloat
    let gestureLogicalWidth: CGFloat?
    let isInteracting: Bool

    init(factor: CGFloat = 1, gestureLogicalWidth: CGFloat? = nil, isInteracting: Bool = false) {
        self.isInteracting = isInteracting || gestureLogicalWidth != nil
        self.factor = factor.isFinite ? min(2, max(0.75, factor)) : 1
        self.gestureLogicalWidth = gestureLogicalWidth.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    }

    func value(_ points: CGFloat) -> CGFloat { points * factor }
    // 75–200% workspace zoom maps to 95–120% typography. Large cards should
    // reveal more content without turning ordinary captions into headlines.
    private var typographyFactor: CGFloat { 1 + (factor - 1) * 0.2 }
    func fontSize(_ points: CGFloat) -> CGFloat { points * typographyFactor }
    func lineSpacing(_ points: CGFloat) -> CGFloat { points * typographyFactor }
    func hitTarget(_ points: CGFloat) -> CGFloat { max(points, value(points)) }
    func logicalWidth(_ width: CGFloat) -> CGFloat {
        gestureLogicalWidth ?? max(0, width.isFinite ? width / factor : 0)
    }
    func columns(for width: CGFloat, compact: Bool = false) -> Int {
        guard !compact else { return 1 }
        let logical = logicalWidth(width)
        return logical >= 850 ? 3 : logical >= 520 ? 2 : 1
    }
}

private struct WorkspaceZoomLayoutKey: EnvironmentKey {
    static let defaultValue = WorkspaceZoomLayout()
}
extension EnvironmentValues {
    var workspaceZoom: WorkspaceZoomLayout {
        get { self[WorkspaceZoomLayoutKey.self] }
        set { self[WorkspaceZoomLayoutKey.self] = newValue }
    }
}

/// The stable identity and logical offset survive row-height changes and a
/// final grid reflow. No offscreen view or thumbnail is instantiated.
struct WorkspaceZoomItemAnchor: Equatable {
    var itemID: String
    var neighbors: [String]
    var logicalOffset: CGFloat
    var viewportFraction: CGFloat
    var pointerOffset: CGFloat? = nil

    func row(in groups: [[String]]) -> Int? {
        if let row = groups.firstIndex(where: { $0.contains(itemID) }) { return row }
        for neighbor in neighbors {
            if let row = groups.firstIndex(where: { $0.contains(neighbor) }) { return row }
        }
        return nil
    }
    func scrollOrigin(rowOrigin: CGFloat, factor: CGFloat, viewportHeight: CGFloat, contentHeight: CGFloat) -> CGFloat {
        let offset = pointerOffset.map { min(viewportHeight, max(0, $0)) } ?? viewportHeight * viewportFraction
        let desired = rowOrigin + logicalOffset * factor - offset
        return max(0, min(max(0, contentHeight - viewportHeight), desired.isFinite ? desired : 0))
    }
}

/// Registered once per recycled native List. The input dispatcher begins this
/// session before publishing scale or changing a window frame, and ends it
/// after the final layout. Geometry notifications do bounded correction only.
@MainActor struct WorkspaceZoomViewport: NSViewRepresentable {
    let groups: [[String]]
    var historyAnchor: NavigationViewportAnchor? = nil
    var onHistoryAnchor: ((NavigationViewportAnchor) -> Void)? = nil
    @Environment(\.workspaceZoom) private var zoom
    private static var registrations: [UUID: WeakCoordinator] = [:]
    private static var activeWindows = Set<Int>()
    private final class WeakCoordinator { weak var value: Coordinator?; init(_ value: Coordinator) { self.value = value } }

    static func register(_ coordinator: Coordinator) { registrations[coordinator.id] = WeakCoordinator(coordinator) }
    static func unregister(_ coordinator: Coordinator) { registrations[coordinator.id] = nil }
    static func flushHistory() {
        WorkspaceZoomScrollAnchors.flushHistory()
        for registration in registrations.values { registration.value?.rememberHistory(force: true) }
    }
    static func isZooming(in window: NSWindow?) -> Bool {
        window.map { activeWindows.contains($0.windowNumber) } ?? false
    }
    static func begin(in window: NSWindow, anchorInWindow: CGPoint? = nil) {
        guard activeWindows.insert(window.windowNumber).inserted else { return }
        WorkspaceZoomScrollAnchors.begin(in: window, point: anchorInWindow)
        registrations = registrations.filter { $0.value.value != nil }
        for registration in registrations.values { registration.value?.capture(in: window, point: anchorInWindow) }
    }
    static func end(in window: NSWindow) {
        activeWindows.remove(window.windowNumber)
        WorkspaceZoomScrollAnchors.end(in: window)
        for registration in registrations.values { registration.value?.finish(in: window) }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> Marker {
        let marker = Marker()
        marker.connect = { [weak marker, weak coordinator = context.coordinator] in
            if let marker { coordinator?.connect(marker) }
        }
        Self.registrations[context.coordinator.id] = WeakCoordinator(context.coordinator)
        return marker
    }
    func updateNSView(_ marker: Marker, context: Context) {
        context.coordinator.update(groups: groups, factor: zoom.factor, history: historyAnchor, onHistory: onHistoryAnchor)
        context.coordinator.connect(marker)
    }
    static func dismantleNSView(_ marker: Marker, coordinator: Coordinator) {
        marker.connect = nil; coordinator.stop(); registrations[coordinator.id] = nil
    }
    final class Marker: NSView {
        var connect: (() -> Void)?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); connect?() }
        override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); connect?() }
        override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); connect?() }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
    @MainActor final class Coordinator {
        let id = UUID()
        private weak var table: NSTableView?
        private var groups: [[String]] = []
        private var factor: CGFloat = 1
        private var anchor: WorkspaceZoomItemAnchor?
        private var observers: [NSObjectProtocol] = []
        private var connecting = false
        private var restoring = false
        private var restoreQueued = false
        private var stopped = false
        private var attempts = 20
        private var settleGeneration = 0
        private var history: NavigationViewportAnchor?
        private var pendingHistory: NavigationViewportAnchor?
        private var onHistory: ((NavigationViewportAnchor) -> Void)?
        private var historyQueued = false
        private var contextRevision: UInt?
        private var contextGeneration: UInt = 0
        private var historySuspended = false

        func update(groups: [[String]], factor: CGFloat, history: NavigationViewportAnchor?,
                    onHistory: ((NavigationViewportAnchor) -> Void)?, contextRevision: UInt? = nil) {
            if contextRevision != self.contextRevision {
                self.contextRevision = contextRevision
                contextGeneration &+= 1; settleGeneration += 1
                self.history = nil; pendingHistory = nil; anchor = nil
                historyQueued = false; restoreQueued = false; connecting = false
                historySuspended = false
                removeObservers(); table = nil; attempts = 20
            }
            self.groups = groups; self.factor = factor; self.onHistory = onHistory
            if history != self.history { self.history = history; pendingHistory = history }
            if pendingHistory != nil { scheduleRestore() }
            if anchor != nil { scheduleRestore() }
        }
        func connect(_ marker: NSView) {
            guard !stopped, !connecting else { return }
            connecting = true
            let generation = contextGeneration
            DispatchQueue.main.async { [weak self, weak marker] in
                guard let self, generation == self.contextGeneration else { return }
                self.connecting = false
                guard !self.stopped, let marker else { return }
                guard let table = NativeListViewport.table(near: marker) else {
                    if self.attempts > 0 { self.attempts -= 1
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak marker] in
                            if let self, generation == self.contextGeneration, let marker { self.connect(marker) }
                        }
                    }
                    return
                }
                guard self.table !== table else { return }
                self.table = table; self.attempts = 20; self.removeObservers()
                guard let clip = table.enclosingScrollView?.contentView else { return }
                table.postsFrameChangedNotifications = true; clip.postsBoundsChangedNotifications = true
                for (name, object) in [(NSView.frameDidChangeNotification, table as NSView),
                                       (NSView.boundsDidChangeNotification, clip as NSView)] {
                    self.observers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.scheduleRestore() }
                    })
                }
                self.restoreHistory()
            }
        }
        private func scheduleRestore() {
            guard !stopped, !restoring, !restoreQueued else { return }
            restoreQueued = true
            let generation = contextGeneration
            // AppKit can emit frame notifications inside its row-height
            // delegate. Reconcile once on the next main-loop turn, never
            // recursively scroll while NSTableView is calculating heights.
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.contextGeneration else { return }; self.restoreQueued = false
                guard !self.stopped else { return }
                self.restoreHistory(); self.restore(); self.scheduleHistory()
            }
        }
        private func restoreHistory() {
            guard !historySuspended, anchor == nil, let saved = pendingHistory, let table,
                  table.numberOfRows == groups.count, let scroll = table.enclosingScrollView else { return }
            guard let resolved = saved.resolving(against: Set(groups.flatMap { $0 })),
                  let row = groups.firstIndex(where: { $0.contains(resolved.itemID) }) else { pendingHistory = nil; return }
            pendingHistory = nil
            let y = min(max(0, table.bounds.height - scroll.contentView.bounds.height),
                        max(0, table.rect(ofRow: row).minY + CGFloat(resolved.offset) * factor))
            restoring = true
            scroll.contentView.scroll(to: CGPoint(x: scroll.contentView.bounds.minX, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
            restoring = false
        }
        private func scheduleHistory() {
            guard !historySuspended, !historyQueued, !restoring, anchor == nil, pendingHistory == nil, onHistory != nil else { return }
            historyQueued = true
            let generation = contextGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.contextGeneration else { return }; self.historyQueued = false
                self.rememberHistory(force: false)
            }
        }
        /// Native insertion anchoring owns the position until estimated row
        /// heights settle. Do not publish its temporary intermediate geometry.
        func setHistorySuspended(_ suspended: Bool) {
            guard historySuspended != suspended else { return }
            historySuspended = suspended
            if !suspended { scheduleRestore() }
        }
        func rememberHistory(force: Bool) {
            guard !stopped, !historySuspended, !restoring, pendingHistory == nil, let onHistory, let table,
                  table.numberOfRows == groups.count, let scroll = table.enclosingScrollView else { return }
            let row = table.rows(in: table.visibleRect).location
            guard groups.indices.contains(row), let id = groups[row].first else { return }
            guard force || history?.itemID != id else { return }
            let flat = groups.flatMap { $0 }; let index = flat.firstIndex(of: id) ?? 0
            let neighbors = Array(flat.suffix(from: min(flat.count, index + 1)).prefix(4)) + Array(flat.prefix(index).suffix(4).reversed())
            let saved = NavigationViewportAnchor(itemID: id,
                offset: Double((scroll.contentView.bounds.minY - table.rect(ofRow: row).minY) / factor), neighbors: neighbors)
            history = saved; onHistory(saved)
        }
        func capture(in window: NSWindow, point: CGPoint?) {
            guard let table, table.window === window, let scroll = table.enclosingScrollView,
                  table.numberOfRows == groups.count, !groups.isEmpty else { return }
            settleGeneration += 1
            let clip = scroll.contentView
            let windowFrame = clip.convert(clip.bounds, to: nil)
            // A pointer gesture belongs to the viewport it started over.
            if let point, !windowFrame.contains(point) { return }
            var local = point.map { table.convert($0, from: nil) }
            if local == nil, let responder = window.firstResponder as? NSView,
               responder.isDescendant(of: table) {
                let frame = table.convert(responder.bounds, from: responder)
                if frame.intersects(table.visibleRect) { local = CGPoint(x: frame.midX, y: frame.midY) }
            }
            let target = local ?? CGPoint(x: table.visibleRect.midX, y: table.visibleRect.midY)
            let row = table.row(at: target)
            guard groups.indices.contains(row), !groups[row].isEmpty else { return }
            let rowFrame = table.rect(ofRow: row)
            let column = min(groups[row].count - 1, max(0, Int((target.x - rowFrame.minX) / max(1, rowFrame.width) * CGFloat(groups[row].count))))
            let id = groups[row][column]
            let flat = groups.flatMap { $0 }; let index = flat.firstIndex(of: id) ?? 0
            let neighbors = Array(flat.suffix(from: min(flat.count, index + 1)).prefix(4)) + Array(flat.prefix(index).suffix(4).reversed())
            anchor = WorkspaceZoomItemAnchor(itemID: id, neighbors: neighbors,
                logicalOffset: (target.y - rowFrame.minY) / factor,
                viewportFraction: min(1, max(0, (target.y - clip.bounds.minY) / max(1, clip.bounds.height))),
                pointerOffset: point == nil ? nil : target.y - clip.bounds.minY)
        }
        private func restore() {
            guard !stopped, !restoring, let anchor, let table,
                  table.numberOfRows == groups.count, let row = anchor.row(in: groups),
                  let scroll = table.enclosingScrollView else { return }
            let clip = scroll.contentView
            let y = anchor.scrollOrigin(rowOrigin: table.rect(ofRow: row).minY, factor: factor,
                                        viewportHeight: clip.bounds.height, contentHeight: table.bounds.height)
            guard abs(y - clip.bounds.minY) > 0.25 else { return }
            restoring = true
            clip.scroll(to: CGPoint(x: clip.bounds.minX, y: y)); scroll.reflectScrolledClipView(clip)
            restoring = false
        }
        func finish(in window: NSWindow) {
            guard table?.window === window else { return }
            let generation = settleGeneration
            // One short settle lets the last estimated row heights/final grid
            // reflow land, without pinning scrolling after the interaction.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                guard let self, generation == self.settleGeneration else { return }
                self.restore(); self.anchor = nil
            }
        }
        private func removeObservers() { observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll() }
        func stop() {
            stopped = true; contextGeneration &+= 1; settleGeneration += 1
            removeObservers(); anchor = nil; table = nil; onHistory = nil
        }
    }
}
