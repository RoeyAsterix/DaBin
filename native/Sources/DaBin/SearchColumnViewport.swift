import AppKit
import SwiftUI

/// Remember the first visible recycled row, without making SwiftUI measure
/// offscreen cards. Each marker is scoped to one native date-column List.
@MainActor
struct SearchColumnViewport: NSViewRepresentable {
    let state: AppState
    let day: String
    let rowIDs: [String]

    func makeCoordinator() -> Coordinator { Coordinator(state: state, day: day) }
    func makeNSView(context: Context) -> Marker {
        let view = Marker()
        view.connect = { [weak view, weak coordinator = context.coordinator] in
            if let view { coordinator?.connect(from: view) }
        }
        return view
    }
    func updateNSView(_ view: Marker, context: Context) {
        context.coordinator.rowIDs = rowIDs
        context.coordinator.connect(from: view)
    }
    static func dismantleNSView(_ view: Marker, coordinator: Coordinator) { view.connect = nil; coordinator.stop() }

    final class Marker: NSView {
        var connect: (() -> Void)?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); connect?() }
        override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); connect?() }
        override func setFrameOrigin(_ newOrigin: NSPoint) { super.setFrameOrigin(newOrigin); connect?() }
        override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); connect?() }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    @MainActor final class Coordinator {
        private weak var state: AppState?
        private let day: String
        private weak var table: NSTableView?
        private var observer: NSObjectProtocol?
        private var connecting = false
        private var stopped = false
        private var connectionAttempts = 20
        private var boundMarkerFrame: NSRect?
        private var viewportGeneration: UInt = 0
        var rowIDs: [String] = [] {
            didSet {
                guard rowIDs != oldValue else { return }
                viewportGeneration &+= 1
                connectionAttempts = 20
            }
        }

        init(state: AppState, day: String) { self.state = state; self.day = day }
        func connect(from marker: Marker) {
            guard !stopped, !connecting else { return }
            connecting = true
            DispatchQueue.main.async { [weak self, weak marker] in
                guard let self else { return }
                self.connecting = false
                guard !self.stopped, let marker else { return }
                let frame = marker.convert(marker.bounds, to: nil)
                if let table = self.table, marker.window != nil, table.window === marker.window,
                   !table.isHiddenOrHasHiddenAncestor, self.boundMarkerFrame == frame { return }
                if let table = NativeListViewport.table(near: marker), let scroll = table.enclosingScrollView {
                    self.boundMarkerFrame = frame
                    self.connectionAttempts = 20
                    guard self.table !== table else { return }
                    self.viewportGeneration &+= 1
                    if let observer = self.observer { NotificationCenter.default.removeObserver(observer) }
                    self.table = table
                    scroll.contentView.postsBoundsChangedNotifications = true
                    self.observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                        object: scroll.contentView, queue: .main) { [weak self] _ in
                            MainActor.assumeIsolated { self?.rememberVisibleRow() }
                    }
                } else if self.connectionAttempts > 0 {
                    // SwiftUI can install the native List after the background
                    // receives its frame. This is a bounded mounting retry.
                    self.connectionAttempts -= 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak marker] in
                        if let marker { self?.connect(from: marker) }
                    }
                }
            }
        }
        private func rememberVisibleRow() {
            guard !stopped, let table, let state, !WorkspaceZoomViewport.isZooming(in: table.window) else { return }
            let row = table.rows(in: table.visibleRect).location
            guard rowIDs.indices.contains(row) else { return }
            let id = rowIDs[row]
            let revision = state.searchPositionRevision
            let generation = viewportGeneration
            // A bounds notification can occur during SwiftUI layout.
            DispatchQueue.main.async { [weak self, weak table] in
                guard let self, !self.stopped, let state = self.state,
                      let table, self.table === table, self.viewportGeneration == generation,
                      state.searchPositionRevision == revision, state.route == .search,
                      state.searchColumnScrollIDs[self.day] != id else { return }
                state.searchColumnScrollIDs[self.day] = id
            }
        }
        func stop() {
            stopped = true
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil; table = nil
        }
    }
}
