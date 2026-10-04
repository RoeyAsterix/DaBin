import AppKit
import Foundation

@MainActor private final class ViewportLifecycleWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
@MainActor private final class ViewportLifecycleRows: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var ids = (0..<40).map { "capture:row-\($0)" }
    func numberOfRows(in tableView: NSTableView) -> Int { ids.count }
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? { ids[row] }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        NSTextField(labelWithString: ids[row])
    }
}
@MainActor private final class ViewportLifecycleFixture {
    let window: ViewportLifecycleWindow
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 240))
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 240))
    let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 400, height: 3200))
    let marker = ExplorerViewport.Marker(frame: NSRect(x: 0, y: 0, width: 400, height: 240))
    let source = ViewportLifecycleRows()
    init() {
        window = ViewportLifecycleWindow(contentRect: NSRect(x: -10000, y: -10000, width: 400, height: 240),
                                         styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("items")))
        table.headerView = nil; table.rowHeight = 80; table.intercellSpacing = .zero
        table.dataSource = source; table.delegate = source; scroll.documentView = table
        root.addSubview(scroll); root.addSubview(marker); window.contentView = root
        window.orderFront(nil); table.reloadData(); root.layoutSubtreeIfNeeded()
    }
    func position(_ y: CGFloat) {
        scroll.contentView.scroll(to: CGPoint(x: 0, y: y)); scroll.reflectScrolledClipView(scroll.contentView)
    }
    func close() { window.orderOut(nil); window.contentView = nil; window.close() }
}

/// Deterministic native viewport lifecycle checks. A short intentional main
/// thread hold represents a large List update; no user archive/input is used.
@main @MainActor private final class ViewportLifecycleTests: NSObject, NSApplicationDelegate {
    private static var checks = 0
    private var result: Int32 = 0
    static func main() {
        let app = NSApplication.shared
        let delegate = ViewportLifecycleTests(); app.delegate = delegate
        app.setActivationPolicy(.prohibited); app.run(); exit(delegate.result)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do { try await Self.run() }
            catch { result = 1; fputs("Viewport lifecycle QA failed: \(error)\n", stderr) }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }
    private static func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard value() else { throw NSError(domain: "ViewportLifecycleTests", code: 1,
                                           userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    private static func settle(_ milliseconds: Int = 80) async throws {
        try await Task.sleep(for: .milliseconds(milliseconds))
    }
    private static func context(_ query: String, selectedID: UUID? = nil) -> ExplorerViewportContext {
        ExplorerViewportContext(project: nil, unfiledOnly: false, dailyFiles: false, query: query,
            filter: "all", pinnedOnly: false, dateFilter: "all", source: nil, origin: "all", grouping: "day", selectedID: selectedID)
    }
    private static func run() async throws {
        try await delayedInsertion()
        try await staleHistory()
        try await selectionKeepsScrollOwnership()
        print("PASS: \(checks) viewport lifecycle checks; delayed insertion settle, bounded expiry, context cancellation, generation-safe history, keyboard selection scroll ownership")
    }
    private static func delayedInsertion() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinViewportLifecycle-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try CaptureStore(root: directory)
        let fixture = ViewportLifecycleFixture(); defer { fixture.close() }
        let coordinator = ExplorerViewport.Coordinator(store: store); defer { coordinator.shutdown() }
        coordinator.update(rowIDs: fixture.source.ids, context: context("first"))
        coordinator.connect(from: fixture.marker); try await settle()
        fixture.position(fixture.table.rect(ofRow: 20).minY + 13); try await settle()
        let row = fixture.table.rows(in: fixture.table.visibleRect).location
        let identity = fixture.source.ids[row]
        let offset = fixture.table.rect(ofRow: row).minY - fixture.scroll.contentView.bounds.minY
        try expect(fixture.table.rowView(atRow: row, makeIfNecessary: false) != nil, "The original anchor is an actual materialized row")
        store.objectWillChange.send()
        fixture.source.ids.insert("capture:new", at: 0); fixture.table.reloadData()
        coordinator.update(rowIDs: fixture.source.ids, context: context("first"))
        // Deliberately hold this one native transaction past the old 600ms
        // deadline, then let its deferred restoration and expiry both run.
        usleep(750_000)
        try await settle(50)
        fixture.table.rowHeight = 105
        fixture.table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<fixture.source.ids.count))
        NotificationCenter.default.post(name: NSView.frameDidChangeNotification, object: fixture.table)
        try await settle()
        let movedRow = fixture.source.ids.firstIndex(of: identity)!
        let restoredOffset = fixture.table.rect(ofRow: movedRow).minY - fixture.scroll.contentView.bounds.minY
        try expect(abs(restoredOffset - offset) < 2,
                   "A late native height correction preserves the same row and offset after a delayed insertion (\(restoredOffset), expected \(offset))")

        // Once the bounded settle ends, a later programmatic scroll must stay
        // where it was put; no invisible anchor may pin it indefinitely.
        try await settle(700)
        fixture.position(400); try await settle()
        try expect(abs(fixture.scroll.contentView.bounds.minY - 400) < 2, "Insertion protection expires after the matching layout settles")
        store.objectWillChange.send()
        try await settle(700)
        fixture.position(600); try await settle()
        try expect(abs(fixture.scroll.contentView.bounds.minY - 600) < 2, "A publication with no matching update still expires")
        store.objectWillChange.send()
        coordinator.update(rowIDs: fixture.source.ids, context: context("replacement"))
        fixture.position(800); try await settle()
        try expect(abs(fixture.scroll.contentView.bounds.minY - 800) < 2, "Replacing the query cancels insertion protection immediately")
    }
    private static func staleHistory() async throws {
        let fixture = ViewportLifecycleFixture(); defer { fixture.close() }
        let coordinator = WorkspaceZoomViewport.Coordinator(); defer { coordinator.stop() }
        var oldWrites: [NavigationViewportAnchor] = [], newWrites: [NavigationViewportAnchor] = []
        let original = fixture.source.ids.map { [$0] }
        coordinator.update(groups: original, factor: 1, history: nil,
                           onHistory: { oldWrites.append($0) }, contextRevision: 1)
        coordinator.connect(fixture.marker); try await settle()
        fixture.position(600); try await settle()
        coordinator.rememberHistory(force: true)
        try expect(!oldWrites.isEmpty, "The fixture has a live native history writer")
        let oldCount = oldWrites.count
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: fixture.scroll.contentView)
        // Native restore is queued first; it queues its history write behind
        // this context replacement. Row count intentionally stays identical.
        DispatchQueue.main.async {
            coordinator.update(groups: (0..<40).map { ["capture:new-query-\($0)"] }, factor: 1, history: nil,
                               onHistory: { newWrites.append($0) }, contextRevision: 2)
        }
        try await settle()
        try expect(oldWrites.count == oldCount && newWrites.isEmpty,
                   "A queued previous-query history callback cannot publish into a replacement query with equal row counts")
        coordinator.connect(fixture.marker); try await settle()
        coordinator.rememberHistory(force: true)
        try expect(newWrites.last?.itemID.hasPrefix("capture:new-query-") == true,
                   "The replacement context can independently record its newly mounted viewport")
        let count = newWrites.count
        coordinator.setHistorySuspended(true)
        fixture.position(900); try await settle()
        coordinator.rememberHistory(force: true)
        try expect(newWrites.count == count, "Insertion-owned intermediate geometry is never published as navigation history")
        coordinator.setHistorySuspended(false); try await settle()
        try expect(newWrites.count > count, "History resumes after insertion ownership ends")
    }

    private static func selectionKeepsScrollOwnership() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinViewportSelection-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try CaptureStore(root: directory)
        let fixture = ViewportLifecycleFixture(); defer { fixture.close() }
        let coordinator = ExplorerViewport.Coordinator(store: store); defer { coordinator.shutdown() }
        var saved = NavigationViewportAnchor(itemID: fixture.source.ids[10], offset: 0, neighbors: [])
        let onHistory: (NavigationViewportAnchor) -> Void = { saved = $0 }
        coordinator.update(rowIDs: fixture.source.ids, context: context("selection"),
                           zoom: WorkspaceZoomLayout(), history: saved, onHistory: onHistory)
        coordinator.connect(from: fixture.marker); try await settle()
        try expect(abs(fixture.scroll.contentView.bounds.minY - fixture.table.rect(ofRow: 10).minY) < 2,
                   "Entering a collection still restores its saved viewport")

        for target in [25, 30] {
            // A keyboard selection publishes its new selected ID and scrolls
            // to that item in the same transaction. Its prior history remains
            // valid context, but must not be replayed after the explicit scroll.
            coordinator.update(rowIDs: fixture.source.ids, context: context("selection", selectedID: UUID()),
                               zoom: WorkspaceZoomLayout(), history: saved, onHistory: onHistory)
            let y = fixture.table.rect(ofRow: target).minY
            fixture.position(y); coordinator.connect(from: fixture.marker)
            try await settle()
            try expect(abs(fixture.scroll.contentView.bounds.minY - y) < 2,
                       "Selection changes preserve the keyboard-owned scroll to row \(target)")
        }

        store.objectWillChange.send()
        coordinator.update(rowIDs: fixture.source.ids, context: context("selection", selectedID: UUID()),
                           zoom: WorkspaceZoomLayout(), history: saved, onHistory: onHistory)
        let y = fixture.table.rect(ofRow: 33).minY
        fixture.position(y); coordinator.connect(from: fixture.marker); try await settle()
        try expect(abs(fixture.scroll.contentView.bounds.minY - y) < 2,
                   "Selection changes still cancel insertion anchoring immediately")
        try expect(context("selection", selectedID: UUID()).historyContext == context("selection").historyContext,
                   "Item selection is not a different navigation-history context")
        try expect(context("replacement").historyContext != context("selection").historyContext,
                   "Changing the query still invalidates the navigation-history context")
    }
}
