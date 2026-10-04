import AppKit
import SwiftUI

enum WorkspaceZoomScrollAxis { case horizontal, vertical }

/// Lightweight markers for LazyVStack workspaces. Native Lists use their row
/// registry instead. Markers exist only for materialized content and never
/// request an offscreen preview to preserve an anchor.
@MainActor private struct WorkspaceZoomItemMarker: NSViewRepresentable {
    let itemID: String
    let axis: WorkspaceZoomScrollAxis
    @Environment(\.workspaceZoom) private var zoom
    func makeNSView(context: Context) -> Marker {
        let marker = Marker(); marker.itemID = itemID; marker.axis = axis
        WorkspaceZoomScrollAnchors.register(marker)
        return marker
    }
    func updateNSView(_ marker: Marker, context: Context) {
        marker.itemID = itemID; marker.axis = axis; marker.factor = zoom.factor
        WorkspaceZoomScrollAnchors.layoutChanged(in: marker.window)
    }
    static func dismantleNSView(_ marker: Marker, coordinator: ()) { WorkspaceZoomScrollAnchors.unregister(marker) }
    final class Marker: NSView {
        let registrationID = UUID()
        var itemID = ""
        var factor: CGFloat = 1
        var axis: WorkspaceZoomScrollAxis = .vertical
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); WorkspaceZoomScrollAnchors.layoutChanged(in: window) }
        override func setFrameOrigin(_ newOrigin: NSPoint) { super.setFrameOrigin(newOrigin); WorkspaceZoomScrollAnchors.layoutChanged(in: window) }
        var workspaceScroll: NSScrollView? {
            var current = superview
            while let view = current {
                if view is NSTableView { return nil }
                if let scroll = view as? NSScrollView { return scroll }
                current = view.superview
            }
            return nil
        }
    }
}

extension View {
    @MainActor func workspaceZoomItem(_ id: String, axis: WorkspaceZoomScrollAxis = .vertical) -> some View {
        background { WorkspaceZoomItemMarker(itemID: id, axis: axis).allowsHitTesting(false).accessibilityHidden(true) }
    }
}

@MainActor enum WorkspaceZoomScrollAnchors {
    private final class WeakMarker {
        weak var value: WorkspaceZoomItemMarker.Marker?
        init(_ value: WorkspaceZoomItemMarker.Marker) { self.value = value }
    }
    @MainActor private final class Session {
        weak var scroll: NSScrollView?
        weak var window: NSWindow?
        let itemID: String
        let axis: WorkspaceZoomScrollAxis
        let logicalOffset: CGFloat
        let viewportFraction: CGFloat
        let pointerOffset: CGFloat?
        var restoring = false
        init(scroll: NSScrollView, marker: WorkspaceZoomItemMarker.Marker, target: CGPoint, hasPointer: Bool) {
            self.scroll = scroll; window = scroll.window; itemID = marker.itemID; axis = marker.axis
            let frame = marker.convert(marker.bounds, to: scroll.documentView)
            let position = axis == .horizontal ? target.x : target.y
            let origin = axis == .horizontal ? frame.minX : frame.minY
            let clip = scroll.contentView.bounds
            let clipOrigin = axis == .horizontal ? clip.minX : clip.minY
            let extent = axis == .horizontal ? clip.width : clip.height
            logicalOffset = (position - origin) / marker.factor
            pointerOffset = hasPointer ? position - clipOrigin : nil
            viewportFraction = min(1, max(0, (position - clipOrigin) / max(1, extent)))
        }
    }
    private final class WindowSession {
        let anchors: [Session]
        var queued = false
        init(_ anchors: [Session]) { self.anchors = anchors }
    }
    private static var markers: [UUID: WeakMarker] = [:]
    private static var sessions: [Int: WindowSession] = [:]
    private static var historyCoordinators: [UUID: WeakHistoryCoordinator] = [:]
    private final class WeakHistoryCoordinator { weak var value: WorkspaceScrollHistory.Coordinator?; init(_ value: WorkspaceScrollHistory.Coordinator) { self.value = value } }
    fileprivate static func register(_ marker: WorkspaceZoomItemMarker.Marker) { markers[marker.registrationID] = WeakMarker(marker) }
    fileprivate static func unregister(_ marker: WorkspaceZoomItemMarker.Marker) { markers[marker.registrationID] = nil }

    static func registerHistory(_ coordinator: WorkspaceScrollHistory.Coordinator) { historyCoordinators[coordinator.id] = WeakHistoryCoordinator(coordinator) }
    static func unregisterHistory(_ coordinator: WorkspaceScrollHistory.Coordinator) { historyCoordinators[coordinator.id] = nil }
    static func flushHistory() {
        for coordinator in historyCoordinators.values { coordinator.value?.flush() }
    }
    static func remember(near marker: NSView) -> NavigationViewportAnchor? {
        let candidates = historyMarkers(near: marker)
        guard let sample = candidates.first, let scroll = sample.workspaceScroll, let document = scroll.documentView else { return nil }
        let ordered = candidates.filter { $0.workspaceScroll === scroll }.sorted {
            $0.convert($0.bounds, to: document).minY < $1.convert($1.bounds, to: document).minY
        }
        guard let first = ordered.first(where: { $0.convert($0.bounds, to: document).maxY > scroll.contentView.bounds.minY + 1 }) else { return nil }
        let rect = first.convert(first.bounds, to: document)
        let ids = ordered.map(\.itemID); let index = ids.firstIndex(of: first.itemID) ?? 0
        let neighbors = Array(ids.suffix(from: min(ids.count, index + 1)).prefix(4)) + Array(ids.prefix(index).suffix(4).reversed())
        return NavigationViewportAnchor(itemID: first.itemID,
            offset: Double((scroll.contentView.bounds.minY - rect.minY) / first.factor), neighbors: neighbors)
    }
    static func restore(_ anchor: NavigationViewportAnchor, near marker: NSView) -> Bool {
        let candidates = historyMarkers(near: marker)
        let identifiers = [anchor.itemID] + anchor.neighbors
        // The caller first materializes the saved identity through
        // ScrollViewReader. Never substitute an unrelated list index.
        guard let target = identifiers.compactMap({ id in candidates.first { $0.itemID == id } }).first,
              let scroll = target.workspaceScroll, let document = scroll.documentView else { return false }
        let rect = target.convert(target.bounds, to: document)
        let desired = rect.minY + CGFloat(anchor.offset) * target.factor
        let y = min(max(0, document.bounds.height - scroll.contentView.bounds.height), max(0, desired))
        scroll.contentView.scroll(to: CGPoint(x: scroll.contentView.bounds.minX, y: y))
        scroll.reflectScrolledClipView(scroll.contentView)
        return true
    }
    private static func historyMarkers(near marker: NSView) -> [WorkspaceZoomItemMarker.Marker] {
        let markerFrame = marker.convert(marker.bounds, to: nil)
        return markers.values.compactMap(\.value).filter {
            guard $0.axis == .vertical, $0.window != nil, $0.window === marker.window, !$0.isHiddenOrHasHiddenAncestor,
                  let scroll = $0.workspaceScroll else { return false }
            let viewport = scroll.contentView.convert(scroll.contentView.bounds, to: nil)
            return viewport.width > 0 && viewport.height > 0 && viewport.intersects(markerFrame)
        }
    }
    static func begin(in window: NSWindow, point: CGPoint?) {
        markers = markers.filter { $0.value.value != nil }
        sessions[window.windowNumber] = nil
        let candidates = markers.values.compactMap(\.value).filter {
            $0.window === window && $0.workspaceScroll != nil && !$0.isHiddenOrHasHiddenAncestor
        }.sorted { $0.itemID < $1.itemID }
        var scrolls: [NSScrollView] = []
        for marker in candidates {
            if let scroll = marker.workspaceScroll, !scrolls.contains(where: { $0 === scroll }),
               !visibleViewport(scroll).isEmpty { scrolls.append(scroll) }
        }
        guard !scrolls.isEmpty else { return }
        let center = window.contentView.map { $0.convert(CGPoint(x: $0.bounds.midX, y: $0.bounds.midY), to: nil) } ?? .zero
        var target = point
        if target == nil, let focus = window.firstResponder as? NSView {
            let rect = focus.convert(focus.bounds, to: nil)
            let focusPoint = CGPoint(x: rect.midX, y: rect.midY)
            if scrolls.contains(where: { scroll in
                scroll.documentView.map { focus.isDescendant(of: $0) } == true && visibleViewport(scroll).contains(focusPoint)
            }) { target = focusPoint }
        }
        if target == nil, let closest = scrolls.min(by: {
            let left = visibleViewport($0), right = visibleViewport($1)
            let lhs = distance(left, to: center), rhs = distance(right, to: center)
            if lhs != rhs { return lhs < rhs }
            // Prefer a content column to its enclosing horizontal strip.
            if left.width * left.height != right.width * right.height { return left.width * left.height < right.width * right.height }
            return left.minX == right.minX ? left.minY < right.minY : left.minX < right.minX
        }) {
            let frame = visibleViewport(closest); target = CGPoint(x: frame.midX, y: frame.midY)
        }
        guard let target else { return }
        var anchors: [Session] = []
        for scroll in scrolls where visibleViewport(scroll).contains(target) {
            guard let document = scroll.documentView else { continue }
            let local = document.convert(target, from: nil)
            let visible = candidates.filter {
                $0.workspaceScroll === scroll && $0.convert($0.bounds, to: document).intersects(scroll.contentView.bounds)
            }
            guard let marker = visible.min(by: {
                distance($0.convert($0.bounds, to: document), to: local) < distance($1.convert($1.bounds, to: document), to: local)
            }) else { continue }
            anchors.append(Session(scroll: scroll, marker: marker, target: local, hasPointer: point != nil))
        }
        // A nested Week interaction keeps the same date horizontally and the
        // same capture vertically. Both belong to one replaceable session.
        if !anchors.isEmpty { sessions[window.windowNumber] = WindowSession(anchors) }
    }
    private static func visibleViewport(_ scroll: NSScrollView) -> CGRect {
        scroll.contentView.convert(scroll.contentView.visibleRect, to: nil)
    }
    static func end(in window: NSWindow) {
        let key = window.windowNumber
        guard let session = sessions[key] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard sessions[key] === session else { return }
            session.anchors.forEach(restore); sessions[key] = nil
        }
    }
    static func layoutChanged(in window: NSWindow?) {
        for coordinator in historyCoordinators.values { coordinator.value?.scheduleRestore() }
        guard let window, let session = sessions[window.windowNumber], !session.queued,
              !session.anchors.contains(where: \.restoring) else { return }
        let key = window.windowNumber
        session.queued = true
        DispatchQueue.main.async {
            guard sessions[key] === session else { return }
            session.queued = false; session.anchors.forEach(restore)
        }
    }
    private static func restore(_ session: Session) {
        guard !session.restoring, let window = session.window, let scroll = session.scroll,
              scroll.window === window, let document = scroll.documentView,
              let marker = markers.values.compactMap(\.value).first(where: { $0.itemID == session.itemID && $0.workspaceScroll === scroll }) else { return }
        let frame = marker.convert(marker.bounds, to: document)
        let anchor = WorkspaceZoomItemAnchor(itemID: session.itemID, neighbors: [], logicalOffset: session.logicalOffset,
                                             viewportFraction: session.viewportFraction, pointerOffset: session.pointerOffset)
        let horizontal = session.axis == .horizontal
        let clip = scroll.contentView.bounds
        let value = anchor.scrollOrigin(rowOrigin: horizontal ? frame.minX : frame.minY, factor: marker.factor,
            viewportHeight: horizontal ? clip.width : clip.height,
            contentHeight: horizontal ? document.bounds.width : document.bounds.height)
        guard abs(value - (horizontal ? clip.minX : clip.minY)) > 0.25 else { return }
        session.restoring = true
        scroll.contentView.scroll(to: CGPoint(x: horizontal ? value : clip.minX, y: horizontal ? clip.minY : value))
        scroll.reflectScrolledClipView(scroll.contentView); session.restoring = false
    }
    private static func distance(_ frame: CGRect, to point: CGPoint) -> CGFloat {
        if frame.contains(point) { return 0 }
        return abs(frame.midY - point.y) + abs(frame.midX - point.x)
    }
}

/// Keeps a LazyVStack's identity plus within-item offset in navigation state.
/// No archive writes, observers on every pixel, or draft copies are involved.
@MainActor struct WorkspaceScrollHistory: NSViewRepresentable {
    let anchor: NavigationViewportAnchor?
    let contextID: String
    let onAnchor: (NavigationViewportAnchor) -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.marker = view
        WorkspaceZoomScrollAnchors.registerHistory(context.coordinator)
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.update(anchor: anchor, contextID: contextID, onAnchor: onAnchor)
    }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.stop(); WorkspaceZoomScrollAnchors.unregisterHistory(coordinator)
    }
    @MainActor final class Coordinator {
        let id = UUID()
        weak var marker: NSView?
        private var lastAnchor: NavigationViewportAnchor?
        private var pending: NavigationViewportAnchor?
        private var contextID: String?
        private var onAnchor: ((NavigationViewportAnchor) -> Void)?
        private var attempts = 0
        private var queued = false
        private var stopped = false
        func update(anchor: NavigationViewportAnchor?, contextID: String, onAnchor: @escaping (NavigationViewportAnchor) -> Void) {
            self.onAnchor = onAnchor
            if self.contextID != contextID || anchor != lastAnchor {
                self.contextID = contextID; lastAnchor = anchor; pending = anchor; attempts = 20
                scheduleRestore()
            }
        }
        func flush() {
            guard !stopped, pending == nil, let marker, let anchor = WorkspaceZoomScrollAnchors.remember(near: marker) else { return }
            lastAnchor = anchor; onAnchor?(anchor)
        }
        func scheduleRestore() {
            guard !stopped, !queued, pending != nil, attempts > 0 else { return }
            queued = true; attempts -= 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                guard let self, !self.stopped else { return }; self.queued = false
                if let anchor = self.pending, let marker = self.marker,
                   WorkspaceZoomScrollAnchors.restore(anchor, near: marker) { self.pending = nil }
                else if self.attempts > 0 { self.scheduleRestore() }
                else { self.pending = nil }
            }
        }
        func stop() { stopped = true; pending = nil; marker = nil; onAnchor = nil }
    }
}
