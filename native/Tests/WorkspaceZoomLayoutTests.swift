import AppKit
import ApplicationServices
import Foundation
import SwiftUI

@MainActor private final class ZoomLayoutNotifications: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .undetermined }
    func requestAuthorization() async throws -> Bool { false }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}
@MainActor private final class ZoomLayoutWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override var backingScaleFactor: CGFloat { 2 }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
@MainActor private final class ZoomTableRows: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { 40 }
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? { "Row \(row)" }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        NSTextField(labelWithString: "Row \(row)")
    }
}

@MainActor private final class ZoomFlippedView: NSView {
    override var isFlipped: Bool { true }
}
@MainActor private final class ZoomFocusPoint: NSView {
    override var acceptsFirstResponder: Bool { true }
}
/// Actual production item markers inside native nested scroll views. Geometry
/// is deterministic and the fixture never reads the archive or clipboard.
@MainActor private final class ZoomNestedScrollFixture {
    let window: ZoomLayoutWindow
    let root = ZoomFlippedView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
    let horizontal = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
    let document = ZoomFlippedView()
    let focus = ZoomFocusPoint()
    private(set) var columns: [NSScrollView] = []
    private var columnDocuments: [ZoomFlippedView] = []
    private var days: [NSHostingView<AnyView>] = []
    private var items: [[NSHostingView<AnyView>]] = []
    init() {
        window = ZoomLayoutWindow(contentRect: NSRect(x: -10000, y: -10000, width: 500, height: 400),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        horizontal.hasHorizontalScroller = true; horizontal.scrollerStyle = .overlay
        horizontal.documentView = document; root.addSubview(horizontal); window.contentView = root
        for day in 0..<4 {
            let dayHost = NSHostingView(rootView: AnyView(Color.clear.workspaceZoomItem("day:\(day)", axis: .horizontal)))
            dayHost.sizingOptions = []; days.append(dayHost); document.addSubview(dayHost)
            let column = NSScrollView(); column.hasVerticalScroller = true; column.scrollerStyle = .overlay
            let content = ZoomFlippedView(); column.documentView = content
            columns.append(column); columnDocuments.append(content); document.addSubview(column)
            var hosts: [NSHostingView<AnyView>] = []
            for item in 0..<10 {
                let host = NSHostingView(rootView: AnyView(Color.clear.workspaceZoomItem("day:\(day)-item:\(item)")))
                host.sizingOptions = []; content.addSubview(host); hosts.append(host)
            }
            items.append(hosts)
        }
        columnDocuments[2].addSubview(focus)
        apply(1); window.orderFront(nil)
    }
    func apply(_ factor: CGFloat) {
        let width = 240 * factor, itemHeight = 160 * factor
        document.frame = CGRect(x: 0, y: 0, width: width * 4 + 36, height: 400)
        for day in 0..<4 {
            let rect = CGRect(x: CGFloat(day) * (width + 12), y: 0, width: width, height: 400)
            days[day].frame = rect
            days[day].rootView = AnyView(Color.clear.workspaceZoomItem("day:\(day)", axis: .horizontal)
                .environment(\.workspaceZoom, WorkspaceZoomLayout(factor: factor)))
            columns[day].frame = rect
            columnDocuments[day].frame = CGRect(x: 0, y: 0, width: width, height: itemHeight * 10)
            for item in 0..<10 {
                items[day][item].frame = CGRect(x: 0, y: CGFloat(item) * itemHeight, width: width, height: itemHeight)
                items[day][item].rootView = AnyView(Color.clear.workspaceZoomItem("day:\(day)-item:\(item)")
                    .environment(\.workspaceZoom, WorkspaceZoomLayout(factor: factor)))
                items[day][item].layoutSubtreeIfNeeded()
            }
            days[day].layoutSubtreeIfNeeded()
        }
        focus.frame = CGRect(x: 80 * factor, y: 695 * factor, width: 20 * factor, height: 20 * factor)
        root.layoutSubtreeIfNeeded()
    }
    func position(x: CGFloat = 300, y: CGFloat = 600) {
        horizontal.contentView.scroll(to: CGPoint(x: x, y: 0)); horizontal.reflectScrolledClipView(horizontal.contentView)
        for column in columns {
            column.contentView.scroll(to: CGPoint(x: 0, y: y)); column.reflectScrolledClipView(column.contentView)
        }
    }
    func focusCenter() -> CGPoint {
        let rect = focus.convert(focus.bounds, to: nil)
        return CGPoint(x: rect.midX, y: rect.midY)
    }
    func close() {
        window.orderOut(nil); window.contentView = nil; window.close()
    }
}

@MainActor private struct ZoomCompactProjectFixture: View {
    let state: AppState
    let capture: Capture
    @FocusState private var focus: String?
    var body: some View {
        ProjectWorkspaceCard(state: state, item: .capture(capture), selected: false, compact: true,
            color: ProjectColorChoice.color(for: "7568D8"), focus: $focus,
            open: {}, select: {}, details: {}, makeTask: {}, drag: { [] })
    }
}
@MainActor private struct ZoomLayoutAX {
    let object: NSObject
    func value(_ name: String) -> Any? {
        let selector = NSSelectorFromString(name)
        return object.responds(to: selector) ? object.perform(selector)?.takeUnretainedValue() : nil
    }
    var identifier: String? { value("accessibilityIdentifier") as? String }
    var frame: CGRect {
        if let cell = object as? NSCell, let view = cell.controlView, let window = view.window {
            return window.convertToScreen(view.convert(view.bounds, to: nil))
        }
        let selector = NSSelectorFromString("accessibilityFrame")
        guard object.responds(to: selector) else { return .zero }
        typealias Getter = @convention(c) (AnyObject, Selector) -> NSRect
        return unsafeBitCast(object.method(for: selector), to: Getter.self)(object, selector)
    }
    var children: [Any] {
        ["accessibilityChildren", "accessibilityChildrenInNavigationOrder", "accessibilityContents"]
            .flatMap { value($0) as? [Any] ?? [] }
    }
}

@main @MainActor final class WorkspaceZoomLayoutTests: NSObject, NSApplicationDelegate {
    private static var checks = 0
    private var result: Int32 = 0
    static func main() {
        let app = NSApplication.shared
        let delegate = WorkspaceZoomLayoutTests(); app.delegate = delegate
        app.setActivationPolicy(.prohibited); app.run(); exit(delegate.result)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do { try await Self.run() }
            catch { result = 1; fputs("Workspace zoom layout QA failed: \(error)\n", stderr) }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }
    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard condition() else { throw NSError(domain: "WorkspaceZoomLayoutTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    private static func settle() async { for _ in 0..<5 { try? await Task.sleep(for: .milliseconds(30)) } }
    private static func run() async throws {
        try expect(WorkspaceZoomLayout(factor: .nan).factor == 1, "NaN scale is safe")
        try expect(WorkspaceZoomLayout(factor: -.infinity).factor == 1, "Infinite scale is safe")
        try expect(WorkspaceZoomLayout(factor: 0).factor == 0.75, "Content stops at 75 percent")
        try expect(WorkspaceZoomLayout(factor: 3).factor == 2, "Content stops at 200 percent")
        for factor in [CGFloat(0.75), 1, 1.5, 2] {
            let metrics = WorkspaceZoomLayout(factor: factor)
            try expect(metrics.value(160) == 160 * factor, "Preview geometry retains the full content zoom")
            try expect(metrics.hitTarget(32) >= 32, "Zooming out keeps minimum pointer targets")
            try expect(metrics.columns(for: 700 * factor) == 2, "Coupled layout uses logical width")
            try expect(WorkspaceZoomLayout(factor: factor, gestureLogicalWidth: 700).columns(for: 400) == 2,
                       "Columns remain stable during an active gesture")
            try expect(metrics.columns(for: 1800, compact: true) == 1, "Compact view keeps one column")
        }
        try expect(WorkspaceZoomLayout().fontSize(16) == 16, "Default caption typography remains unchanged")
        try expect(WorkspaceZoomLayout(factor: 2).fontSize(16) <= 19.2001,
                   "200% workspace zoom keeps a 16-point caption at most 20% larger, not a 32-point headline")
        try expect(WorkspaceZoomLayout(factor: 0.75).fontSize(12) >= 11.3999,
                   "Zooming out preserves readable metadata rather than shrinking it to nine points")
        var previousFont: CGFloat = 0
        for step in 0...125 {
            let metrics = WorkspaceZoomLayout(factor: 0.75 + CGFloat(step) / 100)
            let font = metrics.fontSize(16)
            try expect(font >= previousFont && font <= 19.2001, "Typography remains monotonic and bounded throughout a pinch")
            try expect(abs(metrics.lineSpacing(4) / font - 0.25) < 0.0001,
                       "Caption leading follows typography rather than full preview scaling")
            previousFont = font
        }
        let anchor = WorkspaceZoomItemAnchor(itemID: "b", neighbors: ["c", "a"], logicalOffset: 30, viewportFraction: 0.5)
        try expect(anchor.row(in: [["a"], ["b", "c"]]) == 1, "Anchor follows item identity through reflow")
        try expect(anchor.row(in: [["a"], ["c"]]) == 1, "Deleted anchor uses known surviving neighbor")
        try expect(anchor.row(in: [["x"]]) == nil, "Never anchor unrelated item at old index")
        try expect(anchor.scrollOrigin(rowOrigin: 600, factor: 2, viewportHeight: 400, contentHeight: 2000) == 460, "Logical content offset preserves pointer location")
        try expect(anchor.scrollOrigin(rowOrigin: 0, factor: 0.75, viewportHeight: 400, contentHeight: 200) == 0, "Short content clamps safely")
        var pointerAnchor = anchor; pointerAnchor.pointerOffset = 150
        try expect(pointerAnchor.scrollOrigin(rowOrigin: 600, factor: 2, viewportHeight: 600, contentHeight: 2000) == 510,
                   "Coupled window growth keeps physical pointer offset rather than recentering it")
        let detail100 = DetailLayout(viewport: CGSize(width: 500, height: 700))
        let detail150 = DetailLayout(viewport: CGSize(width: 750, height: 1050), factor: 1.5)
        try expect(detail150.titleSize >= detail100.titleSize && detail150.titleSize <= 28,
                   "An enlarged capture detail retains a restrained native heading")
        for width in [CGFloat(380), 500, 750, 1200] {
            var lastTitle: CGFloat = 0, lastBody: CGFloat = 0
            for factor in [CGFloat(0.75), 1, 1.25, 1.5, 2] {
                let layout = DetailLayout(viewport: CGSize(width: width, height: 900), factor: factor)
                try expect(layout.titleSize >= lastTitle && layout.titleSize <= 28,
                           "Fixed-width detail zoom never shrinks or oversizes its title")
                try expect(layout.bodySize >= lastBody && layout.bodySize <= 17,
                           "Detail body text stays readable and within its normal reading size")
                lastTitle = layout.titleSize; lastBody = layout.bodySize
            }
        }
        try expect(abs(detail150.previewHeight - detail100.previewHeight * 1.5) < 0.01, "Detail preview scales with coupled viewport")
        try expect(DetailLayout(viewport: CGSize(width: 1200, height: 900), factor: 2).usesTaskColumns == false,
                   "Detail task columns use readable logical width")
        try await testNativeAnchor()
        try await testDeferredInsertionAnchor()
        try await testNestedScrollAnchors()
        try await renderCards()
        print("PASS: \(checks) workspace zoom layout checks; finite metrics, logical columns, pointer/item anchoring, history offset, native cards at 75/100/150/200%")
    }
    private static func testNativeAnchor() async throws {
        let window = ZoomLayoutWindow(contentRect: NSRect(x: -10000, y: -10000, width: 600, height: 400),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let scroll = NSScrollView(frame: root.bounds); let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 600, height: 4000))
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("content")))
        table.headerView = nil; table.rowHeight = 100; table.intercellSpacing = .zero
        let source = ZoomTableRows(); table.dataSource = source; scroll.documentView = table
        root.addSubview(scroll); window.contentView = root; window.orderFront(nil); table.reloadData()
        let marker = NSView(frame: root.bounds); root.addSubview(marker)
        let coordinator = WorkspaceZoomViewport.Coordinator(); WorkspaceZoomViewport.register(coordinator)
        defer { coordinator.stop(); WorkspaceZoomViewport.unregister(coordinator) }
        var remembered: NavigationViewportAnchor?
        let groups = (0..<40).map { ["row:\($0)"] }
        coordinator.update(groups: groups, factor: 1, history: nil, onHistory: { remembered = $0 })
        coordinator.connect(marker); await settle()
        scroll.contentView.scroll(to: CGPoint(x: 0, y: 800)); scroll.reflectScrolledClipView(scroll.contentView)
        let visibleRow = table.rows(in: table.visibleRect).location
        WorkspaceZoomViewport.flushHistory()
        try expect(remembered?.itemID == "row:\(visibleRow)", "History saves first visible stable row; got \(remembered?.itemID ?? "nil"), rows \(table.numberOfRows), clip \(scroll.contentView.bounds), visible \(table.visibleRect)")
        let point = scroll.contentView.convert(CGPoint(x: 250, y: 950), to: nil)
        let target = table.convert(point, from: nil)
        let targetRow = table.row(at: target)
        let initialLogicalOffset = target.y - table.rect(ofRow: targetRow).minY
        let pointerOffset = target.y - scroll.contentView.bounds.minY
        WorkspaceZoomViewport.begin(in: window, anchorInWindow: point)
        table.rowHeight = 150
        table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<40))
        coordinator.update(groups: groups, factor: 1.5, history: remembered, onHistory: { remembered = $0 })
        await settle()
        try expect(WorkspaceZoomViewport.isZooming(in: window), "Native gesture lifetime stays active")
        let expectedOrigin = table.rect(ofRow: targetRow).minY + initialLogicalOffset * 1.5 - pointerOffset
        try expect(abs(scroll.contentView.bounds.minY - expectedOrigin) < 3,
                   "Native list keeps stable row and logical offset under the pointer: \(scroll.contentView.bounds.minY), expected \(expectedOrigin)")
        WorkspaceZoomViewport.end(in: window); await settle()
        try expect(!WorkspaceZoomViewport.isZooming(in: window), "End clears transient anchoring ownership")
        withExtendedLifetime(source) {}
    }
    private static func testDeferredInsertionAnchor() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinDeferredViewport-\(UUID())")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = try CaptureStore(root: rootURL)
        let window = ZoomLayoutWindow(contentRect: NSRect(x: -10000, y: -10000, width: 600, height: 400),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let scroll = NSScrollView(frame: root.bounds)
        let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 600, height: 4000))
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("content")))
        table.headerView = nil; table.rowHeight = 100; table.intercellSpacing = .zero
        let source = ZoomTableRows(); table.dataSource = source; table.delegate = source
        scroll.documentView = table; root.addSubview(scroll); window.contentView = root; window.orderFront(nil)
        table.reloadData()
        let marker = ExplorerViewport.Marker(frame: root.bounds); root.addSubview(marker)
        let coordinator = ExplorerViewport.Coordinator(store: store)
        coordinator.update(rowIDs: (0..<40).map { "capture:\($0)" },
            context: ExplorerViewportContext(project: nil, unfiledOnly: false, dailyFiles: false, query: "", filter: "all",
                pinnedOnly: false, dateFilter: "anytime", source: nil, origin: "all", grouping: "all", selectedID: nil))
        coordinator.connect(from: marker); await settle()
        scroll.contentView.scroll(to: CGPoint(x: 0, y: 800)); scroll.reflectScrolledClipView(scroll.contentView)
        await settle()
        let original = scroll.contentView.bounds.minY
        let firstVisible = table.rows(in: table.visibleRect).location
        try expect(firstVisible != NSNotFound && table.rowView(atRow: firstVisible, makeIfNecessary: false) != nil,
                   "Insertion fixture has a materialized first visible row before capture")
        store.objectWillChange.send()
        scroll.contentView.scroll(to: CGPoint(x: 0, y: original + 100))
        try expect(abs(scroll.contentView.bounds.minY - original - 100) < 1,
                   "Insertion guard never scrolls reentrantly from a clip bounds notification")
        await settle()
        try expect(abs(scroll.contentView.bounds.minY - original) < 1,
                   "Queued insertion correction restores the original visible capture; origin \(original), actual \(scroll.contentView.bounds.minY), first row \(firstVisible), visible \(table.rows(in: table.visibleRect))")
        scroll.contentView.scroll(to: CGPoint(x: 0, y: original + 150))
        coordinator.shutdown()
        await settle()
        try expect(abs(scroll.contentView.bounds.minY - original - 150) < 1,
                   "Teardown cancels queued correction instead of scrolling a departed viewport")
        withExtendedLifetime(source) {}
    }
    private static func testNestedScrollAnchors() async throws {
        let fixture = ZoomNestedScrollFixture()
        defer { fixture.close() }
        await settle(); fixture.position(); await settle()
        let pointer = fixture.root.convert(CGPoint(x: 264, y: 130), to: nil)
        WorkspaceZoomScrollAnchors.begin(in: fixture.window, point: pointer)
        fixture.apply(1.5); await settle()
        try expect(abs(fixture.horizontal.contentView.bounds.minX - 570) < 2,
                   "Pointer zoom anchors the Week date horizontally; got \(fixture.horizontal.contentView.bounds.minX)")
        try expect(abs(fixture.columns[2].contentView.bounds.minY - 965) < 2,
                   "Pointer zoom anchors the nested capture vertically; got \(fixture.columns[2].contentView.bounds.minY)")
        fixture.apply(1); await settle()
        try expect(abs(fixture.horizontal.contentView.bounds.minX - 300) < 2
            && abs(fixture.columns[2].contentView.bounds.minY - 600) < 2,
                   "Nested two-axis zoom returns to its original date and capture offset")
        WorkspaceZoomScrollAnchors.end(in: fixture.window); await settle()

        fixture.position(); await settle()
        try expect(fixture.window.makeFirstResponder(fixture.focus), "Nested fixture accepts a real focused content view")
        let focusedBefore = fixture.focusCenter()
        WorkspaceZoomScrollAnchors.begin(in: fixture.window, point: nil)
        fixture.apply(1.5); await settle()
        let focusedAfter = fixture.focusCenter()
        try expect(abs(focusedBefore.x - focusedAfter.x) < 2 && abs(focusedBefore.y - focusedAfter.y) < 2,
                   "Keyboard zoom anchors the focused date column on both axes, independent of marker registration order; before \(focusedBefore), after \(focusedAfter)")
        WorkspaceZoomScrollAnchors.end(in: fixture.window); await settle()

        fixture.window.makeFirstResponder(nil)
        fixture.apply(1); await settle(); fixture.position(); await settle()
        WorkspaceZoomScrollAnchors.begin(in: fixture.window, point: pointer)
        fixture.position(x: 450, y: 900)
        WorkspaceZoomScrollAnchors.layoutChanged(in: fixture.window)
        WorkspaceZoomScrollAnchors.end(in: fixture.window)
        // Replacing a session before its queued correction is delivered must
        // invalidate both that correction and its delayed completion.
        WorkspaceZoomScrollAnchors.begin(in: fixture.window, point: pointer)
        await settle()
        try expect(abs(fixture.horizontal.contentView.bounds.minX - 450) < 2
            && abs(fixture.columns[2].contentView.bounds.minY - 900) < 2,
                   "Replaced sessions cannot replay old horizontal or vertical corrections")
        WorkspaceZoomScrollAnchors.end(in: fixture.window); await settle()

        fixture.position(); await settle()
        WorkspaceZoomScrollAnchors.begin(in: fixture.window, point: pointer)
        fixture.position(x: 450, y: 900)
        WorkspaceZoomScrollAnchors.layoutChanged(in: fixture.window)
        let otherWindow = ZoomLayoutWindow(contentRect: NSRect(x: -11000, y: -11000, width: 500, height: 400),
                                           styleMask: [.borderless], backing: .buffered, defer: false)
        otherWindow.isReleasedWhenClosed = false
        defer {
            otherWindow.orderOut(nil); otherWindow.contentView = nil; otherWindow.close()
            fixture.window.contentView = fixture.root
        }
        fixture.window.contentView = nil; otherWindow.contentView = fixture.root; otherWindow.orderFront(nil)
        await settle()
        try expect(abs(fixture.horizontal.contentView.bounds.minX - 450) < 2
            && abs(fixture.columns[2].contentView.bounds.minY - 900) < 2,
                   "Queued corrections never reposition scroll views moved to a different window")
        WorkspaceZoomScrollAnchors.end(in: fixture.window); await settle()
    }
    private static func renderCards() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinZoomLayout-\(UUID())")
        let suite = "DaBinZoomLayout.\(UUID())"; let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root)
        let auto = AutoCaptureService(settings: AutoCaptureSettings(defaults: defaults), input: InputService(store: store),
            pasteboardProvider: { fatalError("Fixture must not read clipboard") }, sourceApplicationProvider: { nil })
        defer { auto.shutdown() }
        let state = AppState(store: store, previews: PreviewService(store: store, defaults: defaults),
                            reminders: ReminderService(store: store, client: ZoomLayoutNotifications()), autoCapture: auto)
        let task = try store.createTask(text: "Review the spring launch with Alex", planning: TaskPlanning(priority: .high))
        try store.setOrganization(task, pinned: false, projectName: "North Studio")
        let note = try store.createNote(text: "Client feedback\nKeep the opening clear. Preserve the original wording and the project context.", projectName: "North Studio")
        let output = ProcessInfo.processInfo.environment["DABIN_ZOOM_LAYOUT_QA_OUTPUT"].map { URL(fileURLWithPath: $0) }
            ?? root.appendingPathComponent("renders")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try await renderCompactCaptureProfiles(state: state, output: output)
        for factor in [CGFloat(0.75), 1, 1.5, 2] {
            for dark in [false, true] {
                let width = max(380, 420 * factor), height = 600 * factor
                let content = ScrollView { VStack(alignment: .leading, spacing: 10) {
                    Text("WORKSPACE · \(Int(factor * 100))%").font(.system(size: 12, weight: .semibold))
                    TodayTaskCard(state: state, capture: task)
                    CaptureRow(state: state, capture: note, featured: false)
                }.padding(16) }.frame(width: width, height: height, alignment: .topLeading)
                    .environment(\.workspaceZoom, WorkspaceZoomLayout(factor: factor))
                    .environment(\.displayScale, 2).environment(\.daBinTooltipsEnabled, false)
                    .preferredColorScheme(dark ? .dark : .light).background(Palette.background)
                let host = NSHostingView(rootView: content)
                let window = ZoomLayoutWindow(contentRect: NSRect(x: -10000, y: -10000, width: width, height: height),
                                              styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
                await settle(); host.layoutSubtreeIfNeeded()
                try expect(host.fittingSize.width <= width + 1, "Card content fits coupled width at \(factor)")
                guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * 2), pixelsHigh: Int(height * 2),
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                    bytesPerRow: 0, bitsPerPixel: 0) else { throw NSError(domain: "Bitmap", code: 1) }
                bitmap.size = NSSize(width: width, height: height); host.cacheDisplay(in: host.bounds, to: bitmap)
                guard let data = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain: "PNG", code: 1) }
                try data.write(to: output.appendingPathComponent("workspace-\(Int(factor * 100))-\(dark ? "dark" : "light")@2x.png"))
                window.orderOut(nil); window.contentView = nil; window.close()
            }
        }
        try await narrowFixture(AnyView(ZoomCompactProjectFixture(state: state, capture: task)),
            identifiers: ["project-select-capture:" + task.id.uuidString, "project-preview-capture:" + task.id.uuidString,
                          "project-task-toggle-capture:" + task.id.uuidString, "task-priority-tag-" + task.id.uuidString],
            name: "project-compact-380-200", height: 440, output: output)
        for width in [CGFloat(320), 380, 760] {
            try await narrowFixture(AnyView(TodayTaskCard(state: state, capture: task, reorderIndex: 1, reorderCount: 3)),
                identifiers: ["capture-project-picker-", "task-priority-tag-", "capture-task-status-", "today-plan-day-", "today-plan-task-",
                              "task-focus-duration-", "capture-more-"]
                    .map { $0 + task.id.uuidString }, name: "today-\(Int(width))-200", height: 720, output: output, width: width)
        }
    }
    /// The shared card must fit its actual content rather than reserving a
    /// large preview for a note or a file without a saved thumbnail. Inspect
    /// real native targets and capture only the production card bounds.
    private static func renderCompactCaptureProfiles(state: AppState, output: URL) async throws {
        let note = try state.store.createNote(text: "Review the client feedback and keep the original wording", projectName: nil)
        let file = Capture(capturedAt: note.capturedAt, kind: .pdf,
                           title: "Quarterly proposal.pdf", captureDay: note.captureDay)
        var geometry: [[String: Any]] = []
        for capture in [note, file] {
            for width in [CGFloat(260), 380, 760] {
                for factor in [CGFloat(0.75), 1, 2] {
                    for dark in [false, true] {
                        let content = VStack(spacing: 0) {
                            CaptureRow(state: state, capture: capture, featured: false)
                            Spacer(minLength: 0)
                        }.padding(8).frame(width: width, height: 420, alignment: .topLeading)
                            .environment(\.workspaceZoom, WorkspaceZoomLayout(factor: factor))
                            .environment(\.displayScale, 2).environment(\.daBinTooltipsEnabled, false)
                            .preferredColorScheme(dark ? .dark : .light).background(Palette.background)
                        let host = NSHostingView(rootView: content)
                        let window = ZoomLayoutWindow(contentRect: NSRect(x: -10000, y: -10000, width: width, height: 420),
                            styleMask: [.borderless], backing: .buffered, defer: false)
                        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
                        defer { window.orderOut(nil); window.contentView = nil; window.close() }
                        await settle(); host.layoutSubtreeIfNeeded()
                        // SwiftUI materializes its native accessibility tree after
                        // the process receives an AX query, as in the existing
                        // narrow-card fixtures below. Query only this QA process.
                        _ = await Task.detached {
                            let process = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
                            AXUIElementSetMessagingTimeout(process, 3)
                            var windows: CFTypeRef?
                            return AXUIElementCopyAttributeValue(process, kAXWindowsAttribute as CFString, &windows)
                        }.value
                        await settle()
                        var seen = Set<ObjectIdentifier>(), nodes: [ZoomLayoutAX] = []
                        func visit(_ candidate: Any, depth: Int) {
                            guard depth < 50, let object = candidate as? NSObject,
                                  seen.insert(ObjectIdentifier(object)).inserted else { return }
                            let node = ZoomLayoutAX(object: object); nodes.append(node)
                            node.children.forEach { visit($0, depth: depth + 1) }
                        }
                        visit(host, depth: 0)
                        NSAccessibility.unignoredChildren(from: [host]).forEach { visit($0, depth: 0) }
                        let suffix = capture.id.uuidString
                        guard let card = nodes.first(where: { $0.identifier == "capture-card-" + suffix && $0.frame.height > 0 }) else {
                            throw NSError(domain: "CardDensity", code: 1,
                                userInfo: [NSLocalizedDescriptionKey: "Missing native card bounds; available \(nodes.compactMap(\.identifier))"])
                        }
                        try expect(host.fittingSize.width <= width + 1 && window.frame.insetBy(dx: -1, dy: -1).contains(card.frame),
                                   "Shared card fits \(width) points at \(factor) in both appearances")
                        let targets = ["capture-open-", "capture-copy-", "capture-trash-", "capture-more-", "capture-project-picker-"]
                            .compactMap { prefix in nodes.first { $0.identifier == prefix + suffix } }
                        try expect(targets.count == 5, "Title, copy, trash, More and project assignment remain reachable")
                        for target in targets {
                            try expect(target.frame.width >= 31.5 && target.frame.height >= 31.5
                                && card.frame.insetBy(dx: -1, dy: -1).contains(target.frame),
                                "Compact native action stays at least 32 points and inside the card: \(target.identifier ?? "")")
                        }
                        let open = targets.first { $0.identifier == "capture-open-" + suffix }!
                        let copy = targets.first { $0.identifier == "capture-copy-" + suffix }!
                        let stackedHeader = copy.frame.maxY <= open.frame.minY + 1
                        let baselineBudget: CGFloat = width < 300 ? 232 : 204
                        let readableHeaderRow = stackedHeader ? copy.frame.height + 6 : 0
                        try expect(open.frame.width >= 119.5,
                                   "Every narrow card preserves readable title width at every zoom")
                        try expect(card.frame.height <= baselineBudget + readableHeaderRow,
                                   "No empty preview slot; a narrow card allows only its measured readable action row: \(card.frame.height), budget \(baselineBudget + readableHeaderRow)")
                        let icons = targets.filter { $0.identifier != "capture-open-" + suffix && $0.identifier != "capture-project-picker-" + suffix }
                        try expect(icons.map(\.frame.midY).max()! - icons.map(\.frame.midY).min()! < 1,
                                   "Header action icons share one aligned row")
                        let ids = ["capture-receipt-time-", "capture-receipt-category-"].map { $0 + suffix }
                        try expect(ids.allSatisfy { id in nodes.contains { $0.identifier == id && card.frame.insetBy(dx: -1, dy: -1).contains($0.frame) } },
                                   "The compact card still shows original receipt date/time and category")
                        let rect = host.convert(window.convertFromScreen(card.frame), from: nil).intersection(host.bounds)
                        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                            pixelsWide: Int(ceil(rect.width * 2)), pixelsHigh: Int(ceil(rect.height * 2)),
                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
                            throw NSError(domain: "CardDensityBitmap", code: 1)
                        }
                        bitmap.size = rect.size; host.cacheDisplay(in: rect, to: bitmap)
                        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain: "CardDensityPNG", code: 1) }
                        let name = "compact-\(capture.kind.rawValue)-\(Int(width))-\(Int(factor * 100))-\(dark ? "dark" : "light")"
                        try png.write(to: output.appendingPathComponent(name + ".png"))
                        geometry.append(["kind": capture.kind.rawValue, "width": width, "zoom": factor,
                                         "appearance": dark ? "dark" : "light", "cardWidth": card.frame.width,
                                         "cardHeight": card.frame.height, "titleWidth": open.frame.width,
                                         "stackedHeader": stackedHeader, "file": name + ".png"])
                    }
                }
            }
        }
        try JSONSerialization.data(withJSONObject: geometry, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("compact-card-geometry.json"))
    }

    private static func narrowFixture(_ card: AnyView, identifiers: [String], name: String, height: CGFloat, output: URL, width: CGFloat = 380) async throws {
        let content = VStack { card; Spacer(minLength: 0) }.padding(12).frame(width: width, height: height, alignment: .topLeading)
            .environment(\.workspaceZoom, WorkspaceZoomLayout(factor: 2))
            .environment(\.displayScale, 2).environment(\.daBinTooltipsEnabled, false)
            .preferredColorScheme(.dark).background(Palette.background)
        let host = NSHostingView(rootView: content)
        let window = ZoomLayoutWindow(contentRect: NSRect(x: -10000, y: -10000, width: width, height: height),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        await settle(); host.layoutSubtreeIfNeeded()
        _ = await Task.detached {
            let process = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            AXUIElementSetMessagingTimeout(process, 3)
            var windows: CFTypeRef?
            return AXUIElementCopyAttributeValue(process, kAXWindowsAttribute as CFString, &windows)
        }.value
        await settle()
        var seen = Set<ObjectIdentifier>(), nodes: [ZoomLayoutAX] = []
        func visit(_ candidate: Any, depth: Int) {
            guard depth < 50, let object = candidate as? NSObject, seen.insert(ObjectIdentifier(object)).inserted else { return }
            let node = ZoomLayoutAX(object: object); nodes.append(node)
            node.children.forEach { visit($0, depth: depth + 1) }
        }
        visit(host, depth: 0)
        NSAccessibility.unignoredChildren(from: [host]).forEach { visit($0, depth: 0) }
        for id in identifiers {
            let node = nodes.first { $0.identifier == id }
            try expect(node != nil, "Narrow zoom fixture exposes \(id); available \(nodes.compactMap(\.identifier))")
            if let node {
                try expect(node.frame.width > 0 && window.frame.insetBy(dx: -1, dy: -1).contains(node.frame),
                           "200% control remains visible within \(Int(width))-point frame: \(id), \(node.frame)")
            }
        }
        if name.hasPrefix("today-") {
            let durationID = identifiers.first { $0.hasPrefix("task-focus-duration-") }!
            let duration = nodes.first { $0.identifier == durationID }!
            let label = duration.value("accessibilityLabel") as? String
            try expect(label == "Set focus time"
                && duration.object.responds(to: NSSelectorFromString("accessibilityPerformPress")),
                       "Unconfigured task exposes one labeled accessible Set focus time action at200%")
            try expect(duration.frame.width >= 31.5 && duration.frame.height >= 31.5,
                       "Unconfigured focus keeps its32-point native target")
            let playID = durationID.replacingOccurrences(of: "task-focus-duration-", with: "task-focus-play-")
            try expect(!nodes.contains { $0.identifier == playID },
                       "Unconfigured task does not duplicate duration setup with an unavailable play control")
        }
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * 2), pixelsHigh: Int(height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0) else { throw NSError(domain: "Bitmap", code: 1) }
        bitmap.size = NSSize(width: width, height: height); host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain: "PNG", code: 1) }
        try data.write(to: output.appendingPathComponent(name + "@2x.png"))
    }
}
