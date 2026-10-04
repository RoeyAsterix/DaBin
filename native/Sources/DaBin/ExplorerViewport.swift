import AppKit
import Combine
import SwiftUI

/// List backgrounds can share a native ancestor when dates are side by side.
/// Resolve the viewport nearest this marker instead of taking the first List
/// in that ancestor. Discovery follows host changes, never individual rows.
@MainActor enum NativeListViewport {
    static func table(near marker: NSView) -> NSTableView? {
        let markerFrame = marker.convert(marker.bounds, to: nil)
        guard marker.window != nil, markerFrame.width > 0, markerFrame.height > 0 else { return nil }
        var ancestor = marker.superview
        while let view = ancestor {
            let candidates = tables(in: view).filter {
                guard $0.window === marker.window, !$0.isHiddenOrHasHiddenAncestor,
                      let scroll = $0.enclosingScrollView else { return false }
                let frame = scroll.convert(scroll.bounds, to: nil)
                return frame.width > 0 && frame.height > 0 && frame.intersects(markerFrame)
            }
            if !candidates.isEmpty {
                return candidates.min { score($0, relativeTo: markerFrame) < score($1, relativeTo: markerFrame) }
            }
            ancestor = view.superview
        }
        return nil
    }

    private static func tables(in view: NSView) -> [NSTableView] {
        if let table = view as? NSTableView { return [table] }
        return view.subviews.flatMap { tables(in: $0) }
    }

    private static func score(_ table: NSTableView, relativeTo marker: NSRect) -> CGFloat {
        let viewport: NSView = (table.enclosingScrollView as NSView?) ?? table
        let frame = viewport.convert(viewport.bounds, to: nil)
        let dx = frame.midX - marker.midX, dy = frame.midY - marker.midY
        return dx * dx + dy * dy
    }
}

/// A capture arriving in the same browser is not navigation. Any deliberate
/// change to the browser or selected item instead gives up the saved anchor.
struct ExplorerViewportContext: Equatable {
    let project: String?
    let unfiledOnly: Bool
    let dailyFiles: Bool
    let query: String
    let filter: String
    let pinnedOnly: Bool
    let dateFilter: String
    let source: String?
    let origin: String
    let grouping: String
    let selectedID: UUID?

    /// Selecting another item gives up insertion protection, but does not
    /// navigate to another collection. Replaying its saved scroll position
    /// would otherwise undo the keyboard selection's scroll-to-item action.
    var historyContext: Self {
        Self(project: project, unfiledOnly: unfiledOnly, dailyFiles: dailyFiles,
             query: query, filter: filter, pinnedOnly: pinnedOnly,
             dateFilter: dateFilter, source: source, origin: origin,
             grouping: grouping, selectedID: nil)
    }
}

/// SwiftUI's macOS List recycles the rich cards, but its estimated-height
/// insertion animation can move an existing card even with animations disabled.
/// Follow one already-materialized row during that bounded native update. This
/// does not publish geometry into SwiftUI or create any offscreen row views.
@MainActor struct ExplorerViewport: NSViewRepresentable {
    let store: CaptureStore
    let rowIDs: [String]
    let context: ExplorerViewportContext
    var handlesZoom = true
    var historyAnchor: NavigationViewportAnchor? = nil
    var onHistoryAnchor: ((NavigationViewportAnchor) -> Void)? = nil
    @Environment(\.workspaceZoom) private var zoom

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    func makeNSView(context: Context) -> Marker {
        let view = Marker()
        view.connect = { [weak coordinator = context.coordinator, weak view] in
            guard let view else { return }
            coordinator?.connect(from: view)
        }
        return view
    }

    func updateNSView(_ view: Marker, context: Context) {
        context.coordinator.update(rowIDs: rowIDs, context: self.context, zoom: handlesZoom ? zoom : nil,
                                   history: historyAnchor, onHistory: onHistoryAnchor)
        context.coordinator.connect(from: view)
    }

    static func dismantleNSView(_ view: Marker, coordinator: Coordinator) {
        view.connect = nil
        coordinator.shutdown()
    }

    final class Marker: NSView {
        var connect: (() -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            connect?()
        }
        override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); connect?() }
        override func setFrameOrigin(_ newOrigin: NSPoint) { super.setFrameOrigin(newOrigin); connect?() }
        override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); connect?() }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    @MainActor final class Coordinator {
        private let zoomViewport = WorkspaceZoomViewport.Coordinator()
        private var handlesZoom = true
        private struct Anchor {
            let id: String
            let offset: CGFloat
            let viewportSize: CGSize
        }

        private weak var table: NSTableView?
        private weak var anchorRow: NSTableRowView?
        private var rowIDs: [String] = []
        private var context: ExplorerViewportContext?
        private var anchor: Anchor?
        private var storeSubscription: AnyCancellable?
        private var scrollSubscriptions: [AnyCancellable] = []
        private var anchorSubscriptions: [AnyCancellable] = []
        private var rowSubscription: AnyCancellable?
        private var expiry: DispatchWorkItem?
        private var eventMonitor: Any?
        private var connecting = false
        private var connectionAttempts = 20
        private var boundMarkerFrame: NSRect?
        private var restoring = false
        private var pendingRestore: DispatchWorkItem?
        private var anchorGeneration: UInt = 0
        private var contextRevision: UInt = 0
        private var expiryGeneration: UInt = 0
        private var receivedMutationUpdate = false
        private var startedMatchingSettle = false
        private var liveScrolling = false
        private var stopped = false

        init(store: CaptureStore) {
            WorkspaceZoomViewport.register(zoomViewport)
            // Organization can change after an initially unfiled save, without
            // replacing $captures. Observe the store's complete change signal.
            storeSubscription = store.objectWillChange.sink { [weak self] _ in self?.captureAnchor() }
        }

        func update(rowIDs: [String], context: ExplorerViewportContext, zoom: WorkspaceZoomLayout? = nil,
                    history: NavigationViewportAnchor? = nil, onHistory: ((NavigationViewportAnchor) -> Void)? = nil) {
            handlesZoom = zoom != nil
            if self.context != context { discardAnchor() }
            if self.context?.historyContext != context.historyContext { contextRevision &+= 1 }
            if let zoom {
                zoomViewport.update(groups: rowIDs.map { [$0] }, factor: zoom.factor, history: history,
                                    onHistory: onHistory, contextRevision: contextRevision)
            }
            self.context = context
            self.rowIDs = rowIDs
            if let anchor, !rowIDs.contains(anchor.id) { discardAnchor() }
            // Run after the List applies its new identities. Native frame and
            // clip notifications handle subsequent estimated-height changes.
            if anchor != nil { receivedMutationUpdate = true; scheduleRestore() }
        }

        func connect(from view: Marker) {
            if handlesZoom { zoomViewport.connect(view) }
            guard !stopped, !connecting else { return }
            connecting = true
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self else { return }
                self.connecting = false
                guard !self.stopped, let view else { return }
                let frame = view.convert(view.bounds, to: nil)
                if let table = self.table, view.window != nil, table.window === view.window,
                   !table.isHiddenOrHasHiddenAncestor, self.boundMarkerFrame == frame { return }
                if let table = NativeListViewport.table(near: view) {
                    self.boundMarkerFrame = frame
                    self.connectionAttempts = 20
                    if self.table !== table {
                        self.discardAnchor()
                        self.scrollSubscriptions.removeAll()
                        self.install(table)
                    }
                } else if self.connectionAttempts > 0 {
                    self.connectionAttempts -= 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak view] in
                        if let view { self?.connect(from: view) }
                    }
                }
            }
        }

        private func install(_ table: NSTableView) {
            self.table = table
            guard let scroll = table.enclosingScrollView else { return }
            let center = NotificationCenter.default
            scrollSubscriptions = [
                center.publisher(for: NSScrollView.willStartLiveScrollNotification, object: scroll)
                    .sink { [weak self] _ in self?.liveScrolling = true; self?.discardAnchor() },
                center.publisher(for: NSScrollView.didEndLiveScrollNotification, object: scroll)
                    .sink { [weak self] _ in self?.liveScrolling = false }
            ]
        }

        private func captureAnchor() {
            guard !stopped, anchor == nil, !liveScrolling, !WorkspaceZoomViewport.isZooming(in: table?.window), context?.dailyFiles == false,
                  let table, let scroll = table.enclosingScrollView,
                  table.window != nil, table.numberOfRows == rowIDs.count,
                  scroll.contentView.bounds.minY > 1 else { return }
            let visible = table.rows(in: table.visibleRect)
            guard visible.location != NSNotFound else { return }
            let end = min(rowIDs.count, NSMaxRange(visible))
            guard visible.location < end else { return }
            // rowView(...false) only reads an existing viewport row. Headers
            // are not anchors because newly created sections may move them.
            guard let index = (visible.location..<end).first(where: {
                rowIDs[$0].hasPrefix("capture:") && table.rowView(atRow: $0, makeIfNecessary: false) != nil
            }), let row = table.rowView(atRow: index, makeIfNecessary: false) else { return }
            anchor = Anchor(id: rowIDs[index], offset: row.frame.minY - scroll.contentView.bounds.minY,
                            viewportSize: scroll.contentView.bounds.size)
            receivedMutationUpdate = false; startedMatchingSettle = false
            zoomViewport.setHistorySuspended(true)
            observe(row)
            table.postsFrameChangedNotifications = true
            scroll.contentView.postsBoundsChangedNotifications = true
            let center = NotificationCenter.default
            anchorSubscriptions = [
                center.publisher(for: NSView.frameDidChangeNotification, object: table)
                    .sink { [weak self] _ in self?.scheduleRestore() },
                center.publisher(for: NSView.boundsDidChangeNotification, object: scroll.contentView)
                    .sink { [weak self] _ in self?.scheduleRestore() }
            ]
            armExpiry()
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .keyDown, .leftMouseDown,
                                                                       .rightMouseDown, .otherMouseDown]) { [weak self] event in
                if event.window === self?.table?.window { self?.discardAnchor() }
                return event
            }
        }

        private func observe(_ row: NSTableRowView) {
            guard anchorRow !== row else { return }
            anchorRow = row
            row.postsFrameChangedNotifications = true
            rowSubscription = NotificationCenter.default.publisher(for: NSView.frameDidChangeNotification, object: row)
                .sink { [weak self] _ in self?.scheduleRestore() }
        }

        private func armExpiry() {
            expiryGeneration &+= 1
            let generation = expiryGeneration
            expiry?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.expiryGeneration == generation else { return }
                self.expiry = nil
                // A large synchronous List update can occupy the main thread
                // past this deadline. Give its now-installed identities one
                // restoration before starting the bounded settle window.
                if self.receivedMutationUpdate && !self.startedMatchingSettle {
                    self.restoreAnchor()
                    if self.startedMatchingSettle { return }
                }
                self.discardAnchor()
            }
            expiry = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        }

        private func scheduleRestore() {
            guard !stopped, !restoring, !liveScrolling, anchor != nil, pendingRestore == nil else { return }
            let generation = anchorGeneration
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.anchorGeneration == generation else { return }
                self.pendingRestore = nil
                guard !self.stopped else { return }
                self.restoreAnchor()
            }
            pendingRestore = work
            // NSTableView sends frame notifications while measuring rows.
            // Scroll only after that delegate pass returns, coalescing all
            // three frame/bounds sources into one bounded pending callback.
            DispatchQueue.main.async(execute: work)
        }

        private func restoreAnchor() {
            if WorkspaceZoomViewport.isZooming(in: table?.window) { discardAnchor(); return }
            guard !stopped, !restoring, !liveScrolling, let anchor, let table,
                  let scroll = table.enclosingScrollView else { return }
            restoring = true
            defer { restoring = false }
            guard scroll.contentView.bounds.size == anchor.viewportSize else { discardAnchor(); return }
            guard table.numberOfRows == rowIDs.count, let index = rowIDs.firstIndex(of: anchor.id) else { return }
            if receivedMutationUpdate && !startedMatchingSettle {
                startedMatchingSettle = true
                armExpiry()
            }
            // A native insertion can recycle the anchored row just outside
            // the viewport before this deferred correction runs. Its stable
            // identity still has a row rect; use that estimate to recover it,
            // then follow the materialized row's final geometry. Never create
            // offscreen row views solely to maintain an anchor.
            let row = table.rowView(atRow: index, makeIfNecessary: false)
            if let row { observe(row) }
            let origin = row?.frame.minY ?? table.rect(ofRow: index).minY
            let y = max(0, min(table.bounds.height - scroll.contentView.bounds.height, origin - anchor.offset))
            guard y.isFinite, abs(y - scroll.contentView.bounds.minY) > 0.25 else { return }
            scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.minX, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
        }

        private func discardAnchor() {
            anchorGeneration &+= 1
            pendingRestore?.cancel(); pendingRestore = nil
            anchor = nil
            receivedMutationUpdate = false; startedMatchingSettle = false
            anchorRow = nil
            rowSubscription = nil
            anchorSubscriptions.removeAll()
            expiryGeneration &+= 1; expiry?.cancel()
            expiry = nil
            if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
            eventMonitor = nil
            zoomViewport.setHistorySuspended(false)
        }

        func shutdown() {
            zoomViewport.stop(); WorkspaceZoomViewport.unregister(zoomViewport)
            stopped = true
            discardAnchor()
            storeSubscription = nil
            scrollSubscriptions.removeAll()
            table = nil
        }
    }
}
