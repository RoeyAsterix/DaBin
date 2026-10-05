import AppKit
import Darwin
import Foundation
import SwiftUI

// Deliberately independent of DaBin: only public SwiftUI/AppKit, no repository,
// preview workers, viewport markers, custom table delegates or table mutation.
private struct ProbeItem: Identifiable {
    let id: Int
    var title: String { "Fictional item \(id) — a variable-height native List card" }
    var body: String {
        let unit = "A public SwiftUI List should measure this wrapping text while recycling its native rows. "
        return String(repeating: unit, count: id.isMultiple(of: 7) ? 7 : id.isMultiple(of: 3) ? 3 : 1)
    }
}
private struct ProbeRow: Identifiable {
    let items: [ProbeItem]
    var id: Int { items[0].id }
}
@MainActor private final class ProbeModel: ObservableObject {
    @Published var items = (0..<1_002).map { ProbeItem(id: $0) }
    @Published var compact = false
    @Published var factor: CGFloat = 1
    @Published var selected: Set<Int> = []
    func rows(columns: Int) -> [ProbeRow] {
        stride(from: 0, to: items.count, by: columns).map {
            ProbeRow(items: Array(items[$0..<min(items.count, $0 + columns)]))
        }
    }
}
@MainActor private struct ProbeList: View {
    @ObservedObject var model: ProbeModel
    private func columns(_ width: CGFloat) -> Int {
        model.compact ? 1 : width >= 1_000 ? 3 : width >= 580 ? 2 : 1
    }
    var body: some View {
        GeometryReader { geometry in
            let count = columns(geometry.size.width)
            List {
                ForEach(model.rows(columns: count)) { row in
                    HStack(alignment: .top, spacing: 12 * model.factor) {
                        ForEach(row.items) { item in
                            VStack(alignment: .leading, spacing: 8 * model.factor) {
                                HStack(alignment: .top) {
                                    Toggle("Select", isOn: Binding(
                                        get: { model.selected.contains(item.id) },
                                        set: { if $0 { model.selected.insert(item.id) } else { model.selected.remove(item.id) } }))
                                        .labelsHidden().toggleStyle(.checkbox)
                                    Text(item.title).font(.system(size: 13 * model.factor, weight: .semibold)).lineLimit(2)
                                    Spacer(minLength: 0)
                                    Button("Copy") { }
                                }
                                Text(item.body).font(.system(size: 12 * model.factor)).lineLimit(model.compact ? 2 : 5)
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.blue.opacity(item.id.isMultiple(of: 2) ? 0.14 : 0.2))
                                    .frame(height: (model.compact ? 40 : item.id.isMultiple(of: 4) ? 220 : 180) * model.factor)
                                Text("Fictional receipt · \(item.id)").font(.system(size: 10 * model.factor))
                            }.padding(12 * model.factor).frame(maxWidth: .infinity, alignment: .topLeading)
                                .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        }
                        ForEach(0..<max(0, count - row.items.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                    }.listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 7, trailing: 16))
                        .listRowSeparator(.hidden).listRowBackground(Color.clear)
                }
            }.listStyle(.plain).scrollContentBackground(.hidden)
                .transaction { $0.animation = nil; $0.disablesAnimations = true }
        }
    }
}
@MainActor private final class ProbeWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
@main @MainActor private final class StandaloneVariableHeightListProbe: NSObject, NSApplicationDelegate {
    private var exitCode: Int32 = 0
    private static var checks = 0
    private static var snapshots: [[String: Any]] = []
    static func main() {
        let app = NSApplication.shared
        let delegate = StandaloneVariableHeightListProbe()
        app.setActivationPolicy(.accessory); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        exit(delegate.exitCode)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await Self.run() }
            catch { exitCode = 1; fputs("Standalone List probe failed: \(error)\n", stderr) }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }
    private static func expect(_ value: Bool, _ message: String) throws {
        checks += 1
        guard value else { throw NSError(domain: "StandaloneVariableHeightListProbe", code: checks,
            userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    private static func tables(_ view: NSView) -> [NSTableView] {
        if let table = view as? NSTableView { return [table] }
        return view.subviews.flatMap(tables)
    }
    private static func materializedRows(_ view: NSView) -> Int {
        (view is NSTableRowView ? 1 : 0) + view.subviews.reduce(0) { $0 + materializedRows($1) }
    }
    private static func settle(_ host: NSView) async throws {
        for _ in 0..<6 { host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(35)) }
    }
    private static func snapshot(_ phase: String, host: NSView, window: NSWindow, model: ProbeModel) throws -> NSTableView {
        guard let table = tables(host).first, let scroll = table.enclosingScrollView else {
            throw NSError(domain: "StandaloneVariableHeightListProbe", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "No native SwiftUI List table"]) }
        let columns = model.compact ? 1 : host.bounds.width >= 1_000 ? 3 : host.bounds.width >= 580 ? 2 : 1
        let nativeRows = materializedRows(table)
        try expect(table.numberOfRows == model.rows(columns: columns).count, "Native row identities match the current grouping")
        try expect(table.usesAutomaticRowHeights, "Public SwiftUI List retains automatic variable row heights")
        try expect(nativeRows > 0 && nativeRows < 100, "Native rows remain materially virtualized")
        try expect(!window.isKeyWindow && !window.isMainWindow && !NSApp.isActive, "Owned offscreen fixture never steals focus")
        let first = table.rows(in: table.visibleRect).location
        snapshots.append(["phase": phase, "width": host.bounds.width, "height": host.bounds.height,
            "records": model.items.count, "columns": columns, "compact": model.compact, "factor": model.factor,
            "logicalRows": table.numberOfRows, "materializedRowViews": nativeRows,
            "automaticRowHeights": table.usesAutomaticRowHeights, "nativeEstimate": table.rowHeight,
            "delegateClass": String(describing: type(of: table.delegate as Any)),
            "visibleFirstRow": first, "clipOriginY": scroll.contentView.bounds.minY])
        print("PROBE_PHASE: \(phase) rows=\(table.numberOfRows) materialized=\(nativeRows) estimate=\(table.rowHeight) automatic=\(table.usesAutomaticRowHeights)")
        return table
    }
    private static func run() async throws {
        guard CommandLine.arguments.count == 2 else { throw NSError(domain: "StandaloneVariableHeightListProbe", code: 0,
            userInfo: [NSLocalizedDescriptionKey: "Pass a fresh output directory"]) }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let reportURL = output.appendingPathComponent("standalone-variable-list-report.json")
        try expect(!FileManager.default.fileExists(atPath: reportURL.path), "Never overwrite an earlier probe receipt")
        let model = ProbeModel()
        let host = NSHostingView(rootView: ProbeList(model: model))
        host.sizingOptions = []; host.frame = NSRect(x: 0, y: 0, width: 1_080, height: 760)
        host.autoresizingMask = [.width, .height]
        let window = ProbeWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 1_080, height: 760),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        window.orderFrontRegardless()
        try await settle(host)
        _ = try snapshot("initial-presentation", host: host, window: window, model: model)
        for width in [380.0, 760.0, 1_080.0, 320.0, 560.0, 1_080.0] {
            print("PROBE_OPERATION: resize \(width)")
            window.setContentSize(NSSize(width: width, height: 760))
            try await settle(host)
            _ = try snapshot("resize-\(Int(width))", host: host, window: window, model: model)
        }
        model.compact = true; try await settle(host)
        var table = try snapshot("compact", host: host, window: window, model: model)
        if let scroll = table.enclosingScrollView {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: table.rect(ofRow: 100).minY))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        try await settle(host)
        _ = try snapshot("compact-middle-scroll", host: host, window: window, model: model)
        model.compact = false; try await settle(host)
        for batch in 0..<4 {
            print("PROBE_OPERATION: insert-batch \(batch)")
            model.items.insert(contentsOf: (0..<12).map { ProbeItem(id: 2_000 + batch * 12 + $0) }, at: 0)
            try await settle(host)
            table = try snapshot("insert-\(batch)", host: host, window: window, model: model)
        }
        for factor in [0.75, 1.0, 1.5, 2.0, 1.0] {
            print("PROBE_OPERATION: factor \(factor)")
            model.factor = factor; try await settle(host)
            _ = try snapshot("font-layout-\(factor)", host: host, window: window, model: model)
        }
        try expect(model.items.count == 1_050 && Set(model.items.map(\.id)).count == model.items.count,
            "All fictional arrivals retain unique identities")
        let report: [String: Any] = ["kind": "standalone-public-swiftui-list-diagnostic", "passed": true,
            "checks": checks, "snapshots": snapshots, "usesDaBinCode": false, "customTableDelegateInstalled": false,
            "nativeVirtualizationPreserved": true, "warningsCounted": false,
            "warningBoundary": "Parent must inspect complete unsuppressed stderr; a passing semantic probe alone does not mean the warning reproduced or disappeared."]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: reportURL)
        print("PASS: \(checks) standalone public SwiftUI List checks; no DaBin code; warnings remain in unsuppressed stderr")
    }
}
