import AppKit
import ApplicationServices
import Darwin
import Foundation
import SwiftUI

@MainActor private final class ProjectWorkspaceFixtureWindow: NSWindow {
    override var backingScaleFactor: CGFloat { 2 }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor private final class ProjectWorkspaceFixtureNotifications: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .undetermined }
    func requestAuthorization() async throws -> Bool { false }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}

/// One retained host follows the production zoom model. Descendants receive
/// BoardView's real content environment rather than a freshly replaced root
/// or a second independently rendered card for each measurement.
@MainActor private struct ProjectWorkspaceLiveZoomFixture: View {
    let state: AppState
    let project: String
    let pasteboard: NSPasteboard
    @ObservedObject private var zoom: WorkspaceZoomSettings

    init(state: AppState, project: String, pasteboard: NSPasteboard) {
        self.state = state; self.project = project; self.pasteboard = pasteboard
        _zoom = ObservedObject(wrappedValue: state.workspaceZoom)
    }

    var body: some View {
        ProjectWorkspaceView(state: state, project: project, pasteboard: pasteboard,
            chooseExportDestination: { _ in nil })
            .environment(\.workspaceZoom, WorkspaceZoomLayout(factor: zoom.factor, isInteracting: zoom.isInteracting))
            .environment(\.daBinTooltipsEnabled, false).environment(\.displayScale, 2).preferredColorScheme(.light)
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
    }
}

@MainActor private struct ProjectWorkspaceAX {
    let object: NSObject
    private func value(_ name: String) -> Any? {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue()
    }
    private func attribute(_ name: String) -> Any? {
        let selector = NSSelectorFromString("accessibilityAttributeValue:")
        guard object.responds(to: selector),
              (value("accessibilityAttributeNames") as? [String])?.contains(name) == true else { return nil }
        return object.perform(selector, with: name as NSString)?.takeUnretainedValue()
    }
    var identifier: String? { (value("accessibilityIdentifier") as? String) ?? (attribute("AXIdentifier") as? String) }
    var label: String {
        [value("accessibilityLabel"), value("accessibilityTitle"), attribute("AXTitle"), attribute("AXDescription")]
            .compactMap { $0 as? String }.first { !$0.isEmpty } ?? ""
    }
    var valueText: String { (value("accessibilityValue") as? String) ?? (attribute("AXValue") as? String) ?? "" }
    var role: String { (value("accessibilityRole") as? String) ?? (attribute("AXRole") as? String) ?? "" }
    var frame: NSRect {
        let selector = NSSelectorFromString("accessibilityFrame")
        guard object.responds(to: selector) else { return .zero }
        typealias Getter = @convention(c) (AnyObject, Selector) -> NSRect
        return unsafeBitCast(object.method(for: selector), to: Getter.self)(object, selector)
    }
    var interactionFrame: NSRect {
        if let cell = object as? NSCell, let view = cell.controlView, let window = view.window {
            return window.convertToScreen(view.convert(view.bounds, to: nil))
        }
        return frame
    }
    var isEnabled: Bool {
        let selector = NSSelectorFromString("isAccessibilityEnabled")
        guard object.responds(to: selector) else { return false }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(object.method(for: selector), to: Getter.self)(object, selector)
    }
    func press() -> Bool {
        let selector = NSSelectorFromString("accessibilityPerformPress")
        guard object.responds(to: selector) else { return false }
        typealias Action = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(object.method(for: selector), to: Action.self)(object, selector)
    }
    func showMenu() -> Bool {
        let selector = NSSelectorFromString("accessibilityPerformShowMenu")
        guard object.responds(to: selector) else { return false }
        typealias Action = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(object.method(for: selector), to: Action.self)(object, selector)
    }
    var actions: [String] { (value("accessibilityActionNames") as? [String]) ?? [] }
    var children: [Any] {
        var result: [Any] = []
        for name in ["accessibilityChildren", "accessibilityChildrenInNavigationOrder", "accessibilityContents"] {
            if let values = value(name) as? [Any] { result += values }
        }
        if let values = attribute("AXChildren") as? [Any] { result += values }
        if let view = object as? NSView { result += view.subviews }
        return result
    }
}

@MainActor private final class ProjectMenuTracking {
    let deadline = ProcessInfo.processInfo.systemUptime + 2
    weak var window: NSWindow?
    private(set) var menus: [NSMenu] = []
    private(set) var ended = Set<ObjectIdentifier>()
    private(set) var timedOut = false
    init(window: NSWindow?) { self.window = window }
    func began(_ menu: NSMenu) {
        if !menus.contains(where: { $0 === menu }) { menus.append(menu) }
        fputs("MENU tracking began: \(menu.items.map(\.title))\n", stderr)
    }
    func didEnd(_ menu: NSMenu) {
        ended.insert(ObjectIdentifier(menu)); fputs("MENU tracking ended\n", stderr)
    }
    func cancel() {
        menus.forEach { $0.cancelTrackingWithoutAnimation() }
        guard ProcessInfo.processInfo.systemUptime >= deadline else { return }
        timedOut = true
        // A bounded fallback for a menu implementation that hasn't delivered
        // its notification yet. This event is queued only in the test process
        // and carries the fixture's own window number; no global input is sent.
        guard let window, let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53) else { return }
        NSApp.postEvent(escape, atStart: true)
    }
}

/// Production project UI on an offscreen non-key window. The archive, images,
/// preferences and notification client are fictional and isolated. Native drag
/// representations use a private pasteboard; the general clipboard, network
/// previews and external file opening are not exercised.
@main @MainActor private final class ProjectWorkspaceViewTests: NSObject, NSApplicationDelegate {
    private static var checks = 0
    private var result: Int32 = 0

    static func main() {
        let app = NSApplication.shared
        let delegate = ProjectWorkspaceViewTests()
        app.setActivationPolicy(.accessory); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        exit(delegate.result)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await Self.run() }
            catch { result = 1; fputs("Project workspace view QA failed: \(error)\n", stderr) }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "ProjectWorkspaceViewTests", code: checks, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        guard try condition() else { throw failure(message) }
    }

    private static func settle(_ view: NSView) async throws {
        let started = ContinuousClock.now
        for _ in 0..<6 { view.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(35)) }
        try expect(ContinuousClock.now - started < .seconds(4), "Project workspace settles without starving the run loop")
    }

    private static func table(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        return view.subviews.lazy.compactMap { table(in: $0) }.first
    }

    /// A table's complete accessibility children can materialize offscreen rows.
    /// Enumerate only native views that AppKit has already made, never force one.
    private static func nodes(in view: NSView) -> [ProjectWorkspaceAX] {
        var result: [ProjectWorkspaceAX] = [], seen = Set<ObjectIdentifier>()
        func visit(_ candidate: Any, depth: Int) {
            guard depth < 45, let object = candidate as? NSObject,
                  seen.insert(ObjectIdentifier(object)).inserted else { return }
            if let table = object as? NSTableView {
                table.enumerateAvailableRowViews { row, _ in visit(row, depth: depth + 1) }
                return
            }
            let node = ProjectWorkspaceAX(object: object)
            // SwiftUI may expose an AX proxy instead of the native table.
            // Inspect its already-materialized row views separately below.
            if ["AXTable", "AXOutline", "AXList"].contains(node.role) { return }
            result.append(node)
            node.children.forEach { visit($0, depth: depth + 1) }
        }
        visit(view, depth: 0)
        NSAccessibility.unignoredChildren(from: [view]).forEach { visit($0, depth: 0) }
        if let table = table(in: view) { table.enumerateAvailableRowViews { row, _ in visit(row, depth: 0) } }
        return result
    }

    private static func find(_ identifier: String, in view: NSView) async throws -> ProjectWorkspaceAX {
        for _ in 0..<6 {
            if let node = nodes(in: view).first(where: { $0.identifier == identifier }) { return node }
            try await settle(view)
        }
        let visible = nodes(in: view)
        let diagnostic = visible.prefix(15).map { "\(type(of: $0.object)) [\($0.role)] \($0.label)" }.joined(separator: "; ")
        throw failure("Missing project control \(identifier); visible: \(visible.compactMap(\.identifier).joined(separator: ", ")); tree: \(diagnostic)")
    }

    private static func selectionText(in view: NSView) async throws -> String {
        let node = try await find("project-selection-count", in: view)
        // Localized SwiftUI numeric interpolation may group 1002 as 1,002.
        return (node.label + " " + node.valueText).replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "\u{202f}", with: "")
    }

    private static func checkExportAction(in view: NSView, selectedCount: Int = 0) async throws {
        let action = try await find("project-export", in: view)
        let label = action.label.replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "\u{202f}", with: "")
        try expect(label == "Export Selected", "Export keeps its clear selection-only label: \(label)")
        try expect(action.isEnabled == (selectedCount > 0),
            "Export is enabled exactly when visible items are selected (\(selectedCount))")
        try expect(action.role == "AXButton", "Export is one direct button rather than another menu")
        let available = nodes(in: view).filter { $0.frame.width > 0 && $0.frame.height > 0 }
        let exportFrames = Set(available.filter { $0.identifier == "project-export" }.map { NSStringFromRect($0.frame) })
        try expect(exportFrames.count == 1, "The project presents one export control, including while items are selected")
        try expect(!available.contains {
            ["project-export-all", "project-export-selection"].contains($0.identifier ?? "")
                || ["Copy project", "Copy", "Export ZIP"].contains($0.label)
        }, "Separate project/selection export buttons and standalone copy menus are absent")
        _ = try await find("project-actions", in: view)
    }

    private static func checkWrittenSelection(_ destination: URL, in view: NSView,
                                              document: ProjectWorkspaceExportDocument,
                                              image: Capture, original: Data, text: Capture,
                                              notes: String, excluded: [Capture]) async throws {
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: destination.path) {
            try await Task.sleep(for: .milliseconds(35))
        }
        try expect(FileManager.default.fileExists(atPath: destination.path),
            "Pressing the native selected export button publishes the chosen ZIP destination")
        try await settle(view)
        try await checkExportAction(in: view, selectedCount: 3)
        let unpacked = destination.deletingLastPathComponent().appendingPathComponent("Selected-unpacked")
        let extract = Process()
        extract.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        extract.arguments = ["-x", "-k", destination.path, unpacked.path]
        try extract.run(); extract.waitUntilExit()
        try expect(extract.terminationStatus == 0, "The button's ZIP opens with macOS's native ZIP reader")
        let bundle = unpacked.appendingPathComponent("DaBin project")
        let manifestData = try Data(contentsOf: bundle.appendingPathComponent("manifest.json"))
        guard let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              let items = manifest["items"] as? [[String: Any]],
              let content = manifest["content"] as? [[String: Any]] else {
            throw failure("Native selection export must contain a readable manifest")
        }
        try expect(manifest["scope"] as? String == "selection"
            && items.compactMap { $0["id"] as? String } == [image.id.uuidString, text.id.uuidString]
            && manifest["orderedItemIDs"] as? [String] == document.orderedItemIDs,
            "The written manifest includes exactly checked captures and their selected live-note position")
        try expect(manifest["notesPath"] as? String == "Notes.md" && content.count == 2,
            "The selected live note is included once alongside exactly two capture payloads")
        let itemFiles = try FileManager.default.contentsOfDirectory(at: bundle.appendingPathComponent("Items"),
            includingPropertiesForKeys: nil).map(\.lastPathComponent)
        try expect(Set(itemFiles) == Set(document.items.map { URL(fileURLWithPath: $0.contentPath).lastPathComponent }),
            "The ZIP has no hidden or unchecked capture files")
        let exportedImage = document.items.first { $0.id == image.id }!
        let exportedText = document.items.first { $0.id == text.id }!
        try expect(try Data(contentsOf: bundle.appendingPathComponent(exportedImage.contentPath)) == original,
            "Native selected export preserves the original checked image bytes")
        try expect(try String(contentsOf: bundle.appendingPathComponent(exportedText.contentPath), encoding: .utf8) == text.originalText,
            "Native selected export preserves the exact checked capture text")
        try expect(try String(contentsOf: bundle.appendingPathComponent("Notes.md"), encoding: .utf8) == notes,
            "Native selected export preserves the exact checked live note")
        let summary = try String(contentsOf: bundle.appendingPathComponent("Project.md"), encoding: .utf8)
        let manifestText = String(decoding: manifestData, as: UTF8.self)
        try expect(summary == document.summary && summary.contains("Scope: Selected items")
            && excluded.allSatisfy { capture in
                !manifestText.contains(capture.id.uuidString)
                    && !summary.contains(capture.originalText ?? capture.title)
            }, "The ZIP summary and manifest exclude unchecked project content and unrelated projects")
    }

    private static func checkToolbar(in view: NSView) async throws {
        guard let window = view.window else { throw failure("Project toolbar needs its fixture window") }
        let boundary = window.convertToScreen(view.bounds).insetBy(dx: -1, dy: -1)
        let menuIDs: Set<String> = ["project-filter-menu", "project-actions"]
        var controls: [ProjectWorkspaceAX] = []
        for identifier in ["project-search", "project-filter-menu", "project-date-filter",
                           "project-view-toggle", "project-export", "project-actions"] {
            _ = try await find(identifier, in: view)
            let matches = nodes(in: view).filter { $0.identifier == identifier }
            let diagnostic = matches.map {
                "\(type(of: $0.object)) [\($0.role)] AX=\(NSStringFromRect($0.frame)), hit=\(NSStringFromRect($0.interactionFrame)), actions=\($0.actions)"
            }.joined(separator: "; ")
            // An identifier may also reach an image descendant. Inspect the
            // actionable button rather than its decorative label.
            guard let control = matches.first(where: {
                ["AXButton", "AXMenuButton", "AXPopUpButton"].contains($0.role)
                    || $0.actions.contains("AXPress") || $0.actions.contains("AXShowMenu")
            }) else { throw failure("Toolbar \(identifier) has no actionable control: \(diagnostic)") }
            let frame = control.interactionFrame
            try expect(control.frame.width > 0 && control.frame.height > 0 && boundary.contains(control.frame)
                && frame.width > 0 && frame.height > 0 && boundary.contains(frame),
                "Toolbar control \(identifier) fits the \(Int(view.bounds.width))-point project: \(diagnostic)")
            if menuIDs.contains(identifier) {
                // Native borderless menu cells use intrinsic symbol-sized
                // hosts. Their real action is exercised by nativeMenu below,
                // separately from icon Buttons' minimum hit-target checks.
                try expect(control.actions.contains("AXPress") || control.actions.contains("AXShowMenu")
                    || control.object.responds(to: NSSelectorFromString("accessibilityPerformPress")),
                    "Native toolbar menu \(identifier) retains an accessible action: \(diagnostic)")
            } else {
                try expect(frame.width >= 24 && frame.height >= 24,
                    "Toolbar button \(identifier) retains a usable hit target: \(diagnostic)")
            }
            controls.append(control)
        }
        guard let export = controls.first(where: { $0.identifier == "project-export" }) else {
            throw failure("Toolbar has no export control")
        }
        // AX frames describe rendered controls. Native popup backing views
        // include an invisible left inset that is not a visible overlap.
        try expect(controls.allSatisfy { abs($0.frame.midY - export.frame.midY) <= 1 },
            "Search, filters, date, list/grid, export, and actions share one line at width \(Int(view.bounds.width))")
        let horizontal = controls.map(\.frame).sorted { $0.minX < $1.minX }
        try expect(zip(horizontal, horizontal.dropFirst()).allSatisfy { $0.0.maxX <= $0.1.minX + 1 },
            "The single project toolbar has distinct, nonoverlapping controls")
        try expect(!nodes(in: view).contains {
            ["project-sort-order", "project-sort-custom", "project-sort-newest", "project-reorder-selection"].contains($0.identifier ?? "")
                || $0.label == "My order" || $0.label == "Reorder selected items"
        }, "Project sorting and selection expose no manual-order controls")
    }

    private static func nativeViews(in view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { nativeViews(in: $0) }
    }

    private static func dragSource(label: String, in view: NSView) async throws -> NativeContentDragView {
        for _ in 0..<6 {
            if let source = nativeViews(in: view).compactMap({ $0 as? NativeContentDragView })
                .first(where: { $0.dragLabel == label && !$0.isHiddenOrHasHiddenAncestor
                    && $0.bounds.width > 0 && $0.bounds.height > 0 }) { return source }
            try await settle(view)
        }
        throw failure("No rendered native project drag surface for \(label)")
    }

    private static func checkNativeProjectDrag(in view: NSView, label: String, expected: [ProjectWorkspaceItem],
                                               store: CaptureStore) async throws {
        let source = try await dragSource(label: label, in: view)
        // This is the closure installed by the production project card and
        // workspace, rather than a second implementation of their selection.
        let writers = try source.items()
        defer { source.onEnd() }
        let pasteboard = NSPasteboard(name: .init("DaBin.ProjectCardDragQA.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        try expect(writers.count == expected.count, "Rendered project drag supplies one native writer per checked capture or live note")
        let marker = NSPasteboard.PasteboardType("com.dabin.project-item-order")
        let marked = writers.filter { $0.writableTypes(for: pasteboard).contains(marker) }
        try expect(marked.isEmpty,
            "Newest-first project drags contain public item payloads without a manual-reorder marker")
        for (writer, item) in zip(writers, expected) {
            switch item {
            case .capture(let capture):
                let identity = writer.pasteboardPropertyList(forType: ExplorerTransfer.pasteboardType) as? Data
                try expect(identity.flatMap { try? ExplorerTransfer.decodeIDs($0) } == [capture.id],
                    "A selected project capture keeps its identity in visible order")
            case .note:
                try expect(!writer.writableTypes(for: pasteboard).contains(ExplorerTransfer.pasteboardType),
                    "Live project notes remain their own text drag item rather than a fabricated capture")
            }
        }
        try expect(pasteboard.writeObjects(writers), "macOS accepts the actual project card's mixed drag payload")
        let transferred = pasteboard.pasteboardItems ?? []
        try expect(transferred.count == expected.count, "A project selection remains distinct native drag items after pasteboard serialization")
        for (output, item) in zip(transferred, expected) {
            switch item {
            case .capture(let capture):
                if let original = store.managedURL(for: capture) {
                    guard let raw = output.string(forType: .fileURL), let snapshot = URL(string: raw), snapshot.isFileURL else {
                        throw failure("Project file drag must expose a real native snapshot file URL")
                    }
                    let attributes = try FileManager.default.attributesOfItem(atPath: snapshot.path)
                    let values = try snapshot.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isAliasFileKey])
                    try expect(snapshot.standardizedFileURL != original.standardizedFileURL
                        && snapshot.resolvingSymlinksInPath() != original.resolvingSymlinksInPath()
                        && attributes[.type] as? FileAttributeType == .typeRegular
                        && values.isRegularFile == true && values.isSymbolicLink != true && values.isAliasFile != true,
                        "Project file drags retain independent regular, nonalias snapshot URLs in visible selection order")
                    try expect(snapshot.lastPathComponent == (capture.originalFilename ?? original.lastPathComponent)
                        && snapshot.lastPathComponent.utf8.count <= 255,
                        "Project drag snapshot preserves its safe recognizable original fixture filename")
                    try expect(try Data(contentsOf: snapshot) == Data(contentsOf: original),
                        "Project file drag snapshot preserves the exact saved original bytes")
                    if capture.kind == .image {
                        try expect(output.data(forType: .png) == (try Data(contentsOf: original)),
                            "A project image drag exposes its exact saved PNG bytes to native image receivers")
                    }
                } else {
                    try expect(output.string(forType: .string) == (capture.originalText ?? capture.title),
                        "Project capture drag preserves exact original text")
                }
            case .note(let note):
                try expect(output.string(forType: .string) == note.text,
                    "Project live-note drag preserves exact full note text and its visible position")
            }
        }
        try expect(source.activeSession == nil, "Inspecting a production drag payload does not start a session or open another application")
    }


    private static func press(_ identifier: String, in view: NSView, message: String) async throws {
        let node = try await find(identifier, in: view)
        try expect(node.press(), message)
    }

    private static func calendarPopover() -> (window: NSWindow, content: NSView)? {
        for window in NSApp.windows where window.isVisible {
            guard let content = window.contentView,
                  nodes(in: content).contains(where: { $0.identifier == "project-date-picker" }) else { continue }
            return (window, content)
        }
        return nil
    }

    private static func openCalendar(_ host: NSView) async throws -> (window: NSWindow, content: NSView) {
        try await press("project-date-filter", in: host, message: "Project calendar opens through its native toolbar button")
        for _ in 0..<8 {
            if let popup = calendarPopover() {
                try expect(popup.window !== host.window, "Project dates open in one anchored popover, leaving the project window available")
                try await settle(popup.content)
                return popup
            }
            try await settle(host)
        }
        throw failure("Project date button did not open its real calendar popover")
    }

    private static func chooseCalendarAction(_ identifier: String, in host: NSView) async throws {
        let popup = try await openCalendar(host)
        try await press(identifier, in: popup.content, message: "Calendar \(identifier) performs its real selection action")
        for _ in 0..<8 where calendarPopover() != nil { try await settle(host) }
        try expect(calendarPopover() == nil, "A project date selection dismisses its calendar immediately")
        try await settle(host)
    }

    private static func checkCalendarGeometry(_ popup: (window: NSWindow, content: NSView)) async throws {
        let picker = try await find("project-date-picker", in: popup.content)
        try expect(picker.frame.width > 0 && picker.frame.width <= 316 && picker.frame.height <= 440,
            "Project calendar stays compact: \(picker.frame)")
        let day = try await find("project-date-mode-day", in: popup.content)
        let week = try await find("project-date-mode-week", in: popup.content)
        try expect(abs(day.frame.midY - week.frame.midY) <= 1 && day.frame.maxX <= week.frame.minX + 1,
            "Day and Week share a distinct aligned mode row")
        for identifier in ["project-date-mode-day", "project-date-mode-week", "project-calendar-prev",
                           "project-calendar-next", "project-date-any", "project-date-today", "project-date-this-week"] {
            let control = try await find(identifier, in: popup.content)
            let frame = control.interactionFrame
            try expect(frame.width >= 24 && frame.height >= 24
                && popup.window.frame.insetBy(dx: -1, dy: -1).contains(frame),
                "Calendar control \(identifier) has a visible usable hit target: \(frame)")
        }
        let days = nodes(in: popup.content).filter {
            $0.identifier?.hasPrefix("project-calendar-day-") == true && $0.role == "AXButton"
        }
        try expect(days.count >= 28 && days.count <= 42, "The calendar exposes one bounded month of individual date buttons")
        try expect(days.allSatisfy { $0.interactionFrame.width >= 24 && $0.interactionFrame.height >= 24
            && popup.window.frame.insetBy(dx: -1, dy: -1).contains($0.interactionFrame) },
            "Every calendar date remains a reachable native button inside its compact popover")
    }

    private static func clearSelection(in view: NSView) async throws {
        guard let clear = nodes(in: view).first(where: { $0.label == "Clear selection" }) else {
            throw failure("Selection needs an accessible clear action")
        }
        try expect(clear.press(), "Clear selection performs its real accessibility action")
        try await settle(view)
        let text = try await selectionText(in: view)
        try expect(!text.contains("selected"), "Clear selection restores the ordinary item count")
        try await checkExportAction(in: view)
    }

    private static func checkNativeRows(_ view: NSView, itemCount: Int) throws -> Int {
        guard let table = table(in: view) else { throw failure("Project grid must retain native reusable table rows") }
        var materialized = 0
        table.enumerateAvailableRowViews { _, _ in materialized += 1 }
        try expect(table.numberOfRows >= (itemCount + 5) / 6,
                   "The grid retains every logical item in bounded card rows")
        try expect(materialized > 0 && materialized < 50 && materialized < table.numberOfRows / 2,
                   "Project grid materializes only its viewport: \(materialized) of \(table.numberOfRows) rows")
        print("ROWS: project grid logical=\(table.numberOfRows), materialized=\(materialized)")
        return materialized
    }

    private static func fixturePNG() throws -> Data {
        guard let context = CGContext(data: nil, width: 600, height: 400, bitsPerComponent: 8, bytesPerRow: 2_400,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw failure("Could not allocate synthetic preview")
        }
        context.setFillColor(CGColor(red: 0.16, green: 0.66, blue: 0.82, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
        context.setFillColor(CGColor(red: 0.92, green: 0.66, blue: 0.18, alpha: 1))
        context.fill(CGRect(x: 35, y: 35, width: 200, height: 200))
        guard let image = context.makeImage(), let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw failure("Could not encode synthetic preview")
        }
        return data
    }

    private static func saveFixtureImage(_ view: NSView, filename: String, directory: URL) throws {
        let bounds = view.bounds.integral
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2),
            pixelsHigh: Int(bounds.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw failure("Could not allocate project fixture screenshot")
        }
        bitmap.size = bounds.size
        view.cacheDisplay(in: bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw failure("Could not encode project fixture screenshot")
        }
        let destination = directory.appendingPathComponent(filename)
        try png.write(to: destination, options: .atomic)
        print("FIXTURE: \(destination.path)")
    }

    private static func checkScrolledInsertions(_ view: NSView, state: AppState, project: String,
                                                imageID: UUID, existingCount: Int) async throws -> Int {
        // The old saved manual order stays on disk. Arriving captures still
        // prepend in newest-first order without rebuilding every full grid row.
        state.openLibrary()
        try await settle(view)
        guard let table = table(in: view), let scroll = table.enclosingScrollView else {
            throw failure("Default project order needs its native table viewport")
        }
        let maximumY = max(0, table.bounds.height - scroll.contentView.bounds.height)
        try expect(maximumY > 500, "The synthetic archive provides a genuinely scrollable viewport")
        scroll.contentView.scroll(to: NSPoint(x: 0, y: maximumY * 0.5))
        scroll.reflectScrolledClipView(scroll.contentView)
        try await settle(view)
        let visible = table.rows(in: table.visibleRect)
        guard visible.location != NSNotFound else { throw failure("Scrolled project has no visible native rows") }
        let end = min(table.numberOfRows, NSMaxRange(visible))
        var anchor: ProjectWorkspaceAX?
        for index in visible.location..<end {
            guard let row = table.rowView(atRow: index, makeIfNecessary: false) else { continue }
            let viewport = table.window!.convertToScreen(scroll.convert(scroll.bounds, to: nil))
            if let candidate = nodes(in: row).first(where: {
                $0.identifier?.hasPrefix("project-preview-capture:") == true
                    && $0.frame.width > 0 && viewport.contains($0.frame)
            }) { anchor = candidate; break }
        }
        guard let anchor, let identifier = anchor.identifier else { throw failure("No fully visible capture anchor in the scrolled project") }
        let initialFrame = anchor.frame
        var maximumRows = try checkNativeRows(view, itemCount: existingCount)
        for index in 0..<4 {
            _ = try state.store.createNote(text: "Fictional arriving automatic capture \(index)",
                at: Date().addingTimeInterval(Double(index)), projectName: project)
            try await settle(view)
            guard let currentTable = self.table(in: view), currentTable === table,
                  let current = nodes(in: view).first(where: { $0.identifier == identifier }) else {
                throw failure("Arrival \(index) replaced the native table or recycled the visible anchor")
            }
            let viewport = table.window!.convertToScreen(scroll.convert(scroll.bounds, to: nil))
            try expect(viewport.intersects(current.frame), "Arriving capture \(index) keeps the same card visible")
            try expect(abs(current.frame.minY - initialFrame.minY) <= 2,
                       "Arriving capture \(index) preserves the scrolled card position: \(current.frame.minY) vs \(initialFrame.minY)")
            maximumRows = max(maximumRows, try checkNativeRows(view, itemCount: existingCount + index + 1))
        }
        try expect(state.store.captures.contains { $0.id == imageID }, "Automatic-style insertions retain the existing saved image")
        return maximumRows
    }

    private static func menuItems(_ menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { [$0] + ($0.submenu.map(menuItems) ?? []) }
    }
    private static func nativeMenu(_ host: NSView, id: String, containing title: String) async throws -> NSMenu {
        let target = try await find(id, in: host), tracking = ProjectMenuTracking(window: host.window)
        let center = NotificationCenter.default
        let began = center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { notification in
            guard let menu = notification.object as? NSMenu else { return }
            MainActor.assumeIsolated { tracking.began(menu) }
        }
        let ended = center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: nil) { notification in
            guard let menu = notification.object as? NSMenu else { return }
            MainActor.assumeIsolated { tracking.didEnd(menu) }
        }
        let timer = Timer(timeInterval: 0.02, repeats: true) { _ in MainActor.assumeIsolated { tracking.cancel() } }
        RunLoop.main.add(timer, forMode: .common); RunLoop.main.add(timer, forMode: .eventTracking)
        defer { timer.invalidate(); center.removeObserver(began); center.removeObserver(ended) }
        var accepted = target.actions.contains("AXShowMenu") ? target.showMenu() : false
        if !accepted && tracking.menus.isEmpty && target.actions.contains("AXPress") { accepted = target.press() }
        if !accepted && tracking.menus.isEmpty {
            guard let window = host.window else { throw NSError(domain: "ProjectWorkspaceViewTests", code: 8) }
            let frame = target.interactionFrame, point = window.convertPoint(fromScreen: NSPoint(x: frame.midX, y: frame.midY))
            try expect(frame.width > 0 && frame.height > 0 && window.convertToScreen(host.bounds).insetBy(dx: -1, dy: -1).contains(frame), "Menu fits its fixture window: \(frame)")
            let timestamp = ProcessInfo.processInfo.systemUptime
            guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
                timestamp: timestamp, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1),
                  let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [],
                timestamp: timestamp + 0.02, windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0) else {
                throw NSError(domain: "ProjectWorkspaceViewTests", code: 9)
            }
            NSApp.postEvent(up, atStart: true); window.sendEvent(down)
            if let remaining = NSApp.nextEvent(matching: .leftMouseUp, until: Date(), inMode: .default, dequeue: true) {
                try expect(remaining.windowNumber == window.windowNumber, "Native menu release belongs only to the fixture")
                window.sendEvent(remaining)
            }
        }
        try await settle(host)
        guard let menu = tracking.menus.first(where: { menuItems($0).contains { $0.title == title } }) else {
            throw NSError(domain: "ProjectWorkspaceViewTests", code: 10,
                userInfo: [NSLocalizedDescriptionKey: "\(id) must expose the real native menu containing \(title)"])
        }
        try expect(!tracking.timedOut && tracking.ended.contains(ObjectIdentifier(menu)), "Actual \(id) menu closes before item dispatch")
        return menu
    }
    private static func selectMenu(_ host: NSView, id: String, title: String) async throws {
        let menu = try await nativeMenu(host, id: id, containing: title)
        guard let item = menuItems(menu).first(where: { $0.title == title }), let owner = item.menu else {
            throw NSError(domain: "ProjectWorkspaceViewTests", code: 11)
        }
        try expect(item.isEnabled && !item.isHidden && item.action != nil, "Native menu destination \(title) remains actionable")
        owner.performActionForItem(at: owner.index(of: item)); try await settle(host)
    }
    private static func scrollToStart(_ view: NSView) async throws {
        try await settle(view)
        guard let table = table(in: view), let scroll = table.enclosingScrollView else { throw failure("Missing native project table") }
        // A deliberate scroll must send the native live-scroll lifecycle;
        // otherwise the production arrival-protection coordinator correctly
        // restores its still-active insertion anchor over this programmatic move.
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
        table.scrollRowToVisible(0)
        scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView)
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scroll)
        try await settle(view)
    }

    private static func run() async throws {
        let watchdog = DispatchWorkItem {
            FileHandle.standardError.write(Data("FAIL: Project workspace view QA exceeded 90 seconds\n".utf8))
            _exit(124)
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 90, execute: watchdog)
        defer { watchdog.cancel() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinProjectWorkspaceViewQA-\(UUID().uuidString)")
        let suite = "DaBinProjectWorkspaceViewQA.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: PreviewService.linkPreviewPreference)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }

        let project = "Fictional launch kit"
        let at = Date(timeIntervalSince1970: 1_791_000_000), zone = TimeZone(secondsFromGMT: 0)!
        let seeded = (0..<1_000).map { index -> Capture in
            let capture = Capture(capturedAt: at.addingTimeInterval(-Double(index + 1)), timeZone: zone,
                kind: .text, originalText: "Fictional project note \(index). Retain this exact original.",
                title: "Fictional project note \(index)")
            capture.projectName = project
            return capture
        }
        let otherSeed = Capture(capturedAt: at, timeZone: zone, kind: .text,
            originalText: "Unrelated project must stay excluded", title: "Unrelated project")
        otherSeed.projectName = "Another fictional project"
        try CaptureRepository(root: root).save(seeded + [otherSeed])
        let store = try CaptureStore(root: root, repairArchiveOnOpen: false)
        guard let other = store.captures.first(where: { $0.id == otherSeed.id }) else { throw failure("Unrelated stored fixture missing") }
        let png = try fixturePNG()
        let image = try await store.importData(png, filename: "Fictional poster.png", at: at,
            timeZone: zone, projectName: project)
        guard let thumbnail = await PreviewService.writeThumbnail(png, root: root, id: image.id) else {
            throw failure("Could not write local synthetic thumbnail")
        }
        image.thumbnailRelativePath = thumbnail; image.previewState = "ready"
        try store.save(captures: [image])
        let previews = PreviewService(store: store, defaults: defaults)
        let auto = AutoCaptureService(settings: AutoCaptureSettings(defaults: defaults), input: InputService(store: store),
            pasteboardProvider: { fatalError("Project view QA must not read the clipboard") },
            sourceApplicationProvider: { nil })
        var openedFolders: [URL] = []
        let state = AppState(store: store, previews: previews,
            reminders: ReminderService(store: store, client: ProjectWorkspaceFixtureNotifications()),
            autoCapture: auto,
            captureClipboard: CaptureClipboardService(writer: { _ in fatalError("Project view QA must not write the clipboard") }),
            folderOpener: { openedFolders.append($0); return true })
        defer { previews.shutdown(); auto.shutdown(); state.focusSessions.shutdown(); store.cancelArchiveRepair() }
        state.libraryProject = project
        state.workspace.mode = .collection
        state.openLibrary()
        try state.workspace.setScratchpad(text: "Fictional editable project notes. No duplicate capture is needed.", project: project)
        guard let text = store.captures.first(where: { $0.id == seeded[0].id }) else { throw failure("Seeded note missing") }
        let imageID = ProjectWorkspaceIdentity.capture(image.id)
        let textID = ProjectWorkspaceIdentity.capture(text.id)
        let noteID = ProjectWorkspaceIdentity.note(project: project)
        // Pin the live note between the two newest captures, then restore a
        // conflicting legacy manual order. The UI must still
        // render, drag, copy, and export in newest-first order.
        var legacyWorkspace = state.workspace.snapshot
        legacyWorkspace.scratchpads[WorkspaceSnapshot.projectKey(project)]?.updatedAt = at.addingTimeInterval(-1.5)
        try state.workspace.save(legacyWorkspace)
        let initialOrder = Array(([imageID, textID, noteID]
            + seeded.dropFirst().map { ProjectWorkspaceIdentity.capture($0.id) }).reversed())
        try state.workspace.saveProjectItemOrder(initialOrder, project: project)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let before = try Dictionary(uniqueKeysWithValues: store.captures.map { ($0.id, try encoder.encode(CaptureSnapshot($0))) })
        let original = try originalBytes(store: store, capture: image)
        let fixtures = ProcessInfo.processInfo.environment["DABIN_PROJECT_WORKSPACE_VIEW_QA_OUTPUT"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("build/qa/project-workspace-view", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)

        let clipboard = NSPasteboard(name: .init("DaBin.ProjectActionsQA.\(UUID().uuidString)"))
        defer { clipboard.releaseGlobally() }
        var preparedExports: [ProjectWorkspaceExportDocument] = []
        var exportDestination: URL?
        let hosting = NSHostingView(rootView: ProjectWorkspaceView(state: state, project: project, pasteboard: clipboard,
            chooseExportDestination: { document in preparedExports.append(document); return exportDestination })
            .environment(\.daBinTooltipsEnabled, false).environment(\.displayScale, 2).preferredColorScheme(.light)
            .transaction { $0.animation = nil; $0.disablesAnimations = true })
        hosting.frame = CGRect(x: 0, y: 0, width: 1_080, height: 760)
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        let window = ProjectWorkspaceFixtureWindow(contentRect: CGRect(x: -10_000, y: -10_000, width: 1_080, height: 760),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = hosting
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        window.orderFront(nil)
        try await settle(hosting)
        // SwiftUI constructs its virtual accessibility nodes lazily. This
        // own-process AX request enables the same tree used by the existing
        // Explorer card/keyboard regressions, without inspecting another app.
        let activation = await Task.detached {
            let process = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            AXUIElementSetMessagingTimeout(process, 3)
            var windows: CFTypeRef?
            return AXUIElementCopyAttributeValue(process, kAXWindowsAttribute as CFString, &windows)
        }.value
        try expect(activation == .success, "Own-process accessibility activates for the synthetic project window")
        try await settle(hosting)
        try expect(window.frame.maxX < 0 && !window.isKeyWindow && !window.isMainWindow,
                   "Synthetic project window stays offscreen, non-key, and non-main")
        var maximumRows = try checkNativeRows(hosting, itemCount: 1_002)
        try expect(!nodes(in: hosting).contains {
            $0.frame.width > 0 && ($0.label == project || $0.label.contains("One place for your project"))
        }, "The project grid does not repeat the dropdown's project name or the removed tagline")
        try await checkToolbar(in: hosting)
        try saveFixtureImage(hosting, filename: "project-grid-wide@2x.png", directory: fixtures)

        let initialSelection = try await selectionText(in: hosting)
        try expect(initialSelection.contains("1002") && !initialSelection.contains("selected"),
                   "Project starts unselected and includes all captures plus its one live note")
        try await checkExportAction(in: hosting)
        _ = try await find("project-export", in: hosting).press()
        try await settle(hosting)
        try expect(preparedExports.isEmpty,
            "An empty selection cannot open the ZIP chooser or fall back to the whole project")
        try expect(!nodes(in: hosting).contains { $0.identifier == "project-make-tasks" && $0.frame.width > 0 },
                   "Bulk conversion controls remain hidden until selection")
        let filePreview = try await find("project-preview-" + imageID, in: hosting)
        let expectedPreviewHeight = ExplorerCaptureCardPresentation.previewHeight(for: filePreview.frame.width)
        try expect(filePreview.frame.width >= 32 && filePreview.frame.height >= 96
            && abs(filePreview.frame.height - expectedPreviewHeight) < 1,
                   "Grid file preview follows its actual width within the compact media budget: \(filePreview.frame)")
        let notePreview = try await find("project-preview-" + noteID, in: hosting)
        try expect(notePreview.frame.width >= 32 && (32...80).contains(notePreview.frame.height),
                   "Live project notes use natural readable text height without an empty hero: \(notePreview.frame)")
        try expect(!nodes(in: hosting).contains { $0.identifier == "project-card-" + ProjectWorkspaceIdentity.capture(other.id) },
                   "Unrelated project is absent from the visible project board")
        try await press("project-select-" + imageID, in: hosting, message: "Image checkbox selects without opening its file")
        try await settle(hosting)
        let oneSelected = try await selectionText(in: hosting)
        try expect(oneSelected.contains("1 selected"), "First explicit checkbox selects exactly one item")
        try await checkExportAction(in: hosting, selectedCount: 1)
        try await press("project-select-" + textID, in: hosting, message: "Second checkbox adds a capture to selection")
        try await settle(hosting)
        let twoSelected = try await selectionText(in: hosting)
        try expect(twoSelected.contains("2 selected"), "Project supports multi-selection without replacing the first item")
        _ = try await find("project-make-tasks", in: hosting)
        try await checkExportAction(in: hosting, selectedCount: 2)
        try await press("project-export", in: hosting, message: "The same export action directly prepares the selected items")
        try await settle(hosting)
        try expect(preparedExports.count == 1 && preparedExports.last?.scope == .selection
            && preparedExports.last?.itemCount == 2 && preparedExports.last?.notes == nil
            && Set(preparedExports.last?.items.map(\.id) ?? []) == Set([image.id, text.id]),
            "Selected export includes exactly the two checked captures, with no unselected live note")
        try expect(state.route == .library, "Selecting cards never opens capture details")
        try await press("project-select-" + noteID, in: hosting, message: "Live project notes can join a capture and image selection")
        try await settle(hosting)
        let liveNote = WorkspaceScratchpad(text: state.workspace.scratchpad(project: project),
            projectName: project, updatedAt: at.addingTimeInterval(-1.5))
        let selectedZIP = root.appendingPathComponent("Selected.zip")
        exportDestination = selectedZIP
        try await press("project-export", in: hosting,
            message: "Checked image, text and live notes export directly to one selected ZIP")
        exportDestination = nil
        try expect(preparedExports.count == 2 && preparedExports.last?.scope == .selection
            && preparedExports.last?.itemCount == 3 && preparedExports.last?.notes == liveNote.text,
            "Native selected export prepares exactly the three checked items")
        guard let writtenSelection = preparedExports.last else { throw failure("Native selected ZIP document missing") }
        try await checkWrittenSelection(selectedZIP, in: hosting, document: writtenSelection,
            image: image, original: original, text: text, notes: liveNote.text, excluded: [seeded[1], other])
        try await checkNativeProjectDrag(in: hosting, label: image.title,
            expected: [.capture(image), .capture(text), .note(liveNote)], store: store)
        try await settle(hosting)
        try await clearSelection(in: hosting)
        try await checkExportAction(in: hosting)

        let selectAll = try await find("project-select-all", in: hosting)
        try expect(selectAll.press(), "Select all performs its real accessibility action")
        try await settle(hosting)
        let allSelected = try await selectionText(in: hosting)
        try expect(allSelected.contains("1002 selected"), "Select all includes the complete project and live note, never other projects")
        try await checkExportAction(in: hosting, selectedCount: 1_002)
        try await press("project-export", in: hosting,
            message: "Explicitly selecting all exports all checked items through the selection-only button")
        try await settle(hosting)
        try expect(preparedExports.count == 3 && preparedExports.last?.scope == .selection
            && preparedExports.last?.itemCount == 1_002 && preparedExports.last?.notes == liveNote.text
            && preparedExports.last?.items.prefix(2).map(\.id) == [image.id, text.id],
            "Select-all export retains newest-first order and live notes without changing its selection scope")
        try await checkToolbar(in: hosting)
        window.setContentSize(CGSize(width: 320, height: 760))
        try await settle(hosting)
        try await checkExportAction(in: hosting, selectedCount: 1_002)
        let narrowBoundary = window.convertToScreen(hosting.bounds)
        let narrowSelectedExport = try await find("project-export", in: hosting)
        try expect(narrowSelectedExport.frame.width > 0
            && narrowBoundary.insetBy(dx: -1, dy: -1).contains(narrowSelectedExport.frame),
            "Selected export stays visible in the 320-point project window: \(narrowSelectedExport.frame) in \(narrowBoundary)")
        try await checkToolbar(in: hosting)
        try saveFixtureImage(hosting, filename: "project-selected-narrow@2x.png", directory: fixtures)
        window.setContentSize(CGSize(width: 1_080, height: 760))
        try await settle(hosting)
        try await clearSelection(in: hosting)

        try await selectMenu(hosting, id: "project-filter-menu", title: "Files")
        let filtered = try await selectionText(in: hosting)
        try expect(filtered.contains("1 of 1002"), "Files filter shows one file while retaining the whole-project count")
        try await checkExportAction(in: hosting)
        _ = try await find("project-export", in: hosting).press()
        try await settle(hosting)
        try expect(preparedExports.count == 3,
            "Filtering without choosing any items cannot prepare an export")
        try await press("project-select-all", in: hosting, message: "Select all works on the filtered file view")
        try await settle(hosting)
        let filteredSelection = try await selectionText(in: hosting)
        try expect(filteredSelection.contains("1 selected"), "Filtered selection excludes hidden captures and notes")
        try await checkExportAction(in: hosting, selectedCount: 1)
        try await press("project-export", in: hosting, message: "Filtered selection uses the same clearly scoped export action")
        try await settle(hosting)
        try expect(preparedExports.count == 4 && preparedExports.last?.scope == .selection
            && preparedExports.last?.itemCount == 1 && preparedExports.last?.items.first?.id == image.id
            && preparedExports.last?.notes == nil,
            "Filtered selected export contains the checked file and no hidden captures or notes")
        try await checkNativeProjectDrag(in: hosting, label: image.title,
            expected: [.capture(image)], store: store)
        try await selectMenu(hosting, id: "project-filter-menu", title: "All")
        let clearedByFilter = try await selectionText(in: hosting)
        try expect(!clearedByFilter.contains("selected"), "Changing filters clears hidden selection")
        try await checkExportAction(in: hosting)
        try await chooseCalendarAction("project-date-this-week", in: hosting)
        try expect(state.projectPresentation[project]?.selectedDateRange?.mode == .week
            && state.projectPresentation[project]?.dateFilter == .anytime,
            "The toolbar calendar applies the actual current calendar week without a hidden relative preset")
        try await checkToolbar(in: hosting)
        try await chooseCalendarAction("project-date-any", in: hosting)
        try expect(state.projectPresentation[project]?.dateFilter == .anytime
            && state.projectPresentation[project]?.selectedDateRange == nil,
            "The toolbar calendar restores the complete project date range")

        try await checkNativeProjectDrag(in: hosting, label: image.title, expected: [.capture(image)], store: store)
        // Filtering preserves the browsing viewport. Position this fixture at
        // its newest item before measuring every supported compact width.
        state.projectPresentation[project, default: ProjectNavigationPresentation()].viewport = nil
        try await scrollToStart(hosting)

        for width in [CGFloat(760), 400, 320, 1_080] {
            window.setContentSize(CGSize(width: width, height: 760))
            try await settle(hosting)
            let boundary = window.convertToScreen(hosting.bounds)
            for identifier in ["project-preview-" + imageID, "project-select-" + imageID,
                               "project-export", "project-actions", "project-search", "project-selection-count"] {
                let control = try await find(identifier, in: hosting)
                try expect(control.frame.width > 0 && control.frame.minX >= boundary.minX - 1
                    && control.frame.maxX <= boundary.maxX + 1,
                    "Project control \(identifier) fits width \(width): \(control.frame) in \(boundary)")
            }
            try await checkExportAction(in: hosting)
            try await checkToolbar(in: hosting)
            maximumRows = max(maximumRows, try checkNativeRows(hosting, itemCount: 1_002))
            if width == 320 { try saveFixtureImage(hosting, filename: "project-grid-narrow@2x.png", directory: fixtures) }
        }

        let compactToggle = try await find("project-view-toggle", in: hosting)
        try expect(compactToggle.press(), "Compact view toggle is active")
        try await settle(hosting)
        let compactPreview = try await find("project-preview-" + imageID, in: hosting)
        try expect(abs(compactPreview.frame.width - 64) < 1 && abs(compactPreview.frame.height - 64) < 1,
                   "Compact mode keeps the real media preview in a usable 64-point square: \(compactPreview.frame)")
        maximumRows = max(maximumRows, try checkNativeRows(hosting, itemCount: 1_002))
        try await press("project-view-toggle", in: hosting, message: "Preview grid can be restored")
        try await settle(hosting)

        // Text details are local navigation; never press a file/link opener in QA.
        let textPreview = try await find("project-preview-" + textID, in: hosting)
        try expect(textPreview.press(), "Text preview activates its real local navigation action")
        try await settle(hosting)
        try expect(state.route == .detail && state.selectedCapture?.id == text.id,
                   "Text preview opens the matching capture's details")

        maximumRows = max(maximumRows, try await checkScrolledInsertions(hosting, state: state,
            project: project, imageID: image.id, existingCount: 1_002))

        let after = try Dictionary(uniqueKeysWithValues: store.captures.map { ($0.id, try encoder.encode(CaptureSnapshot($0))) })
        try expect(before.allSatisfy { after[$0.key] == $0.value },
                   "Rendering, selecting and new arrivals preserve every preexisting original capture and receipt")
        try expect(after.count == before.count + 4, "Only the four explicitly inserted synthetic captures are added")
        try expect(try originalBytes(store: store, capture: image) == original,
                   "Project preview, resizing, and selection preserve original file bytes")
        maximumRows = max(maximumRows, try checkNativeRows(hosting, itemCount: 1_006))
        state.projectPresentation[project, default: ProjectNavigationPresentation()].viewport = nil
        try await scrollToStart(hosting)
        let itemMenu = try await nativeMenu(hosting, id: "project-more-" + imageID, containing: "Open details")
        try expect(!menuItems(itemMenu).contains { ["Move earlier", "Move later", "My order"].contains($0.title) },
            "Item actions no longer offer manual reordering")
        try await checkExportAction(in: hosting)
        try await press("project-select-all", in: hosting,
            message: "Newly arriving captures can be explicitly selected before export")
        try await settle(hosting)
        try await checkExportAction(in: hosting, selectedCount: 1_006)
        try await press("project-export", in: hosting, message: "Newest-first selected export includes checked arriving captures")
        try await settle(hosting)
        let arrivingIDs = store.captures.filter { $0.originalText?.hasPrefix("Fictional arriving automatic capture ") == true }
            .sorted { $0.capturedAt > $1.capturedAt }.map(\.id)
        try expect(preparedExports.count == 5 && preparedExports.last?.scope == .selection
            && preparedExports.last?.itemCount == 1_006
            && preparedExports.last?.items.prefix(4).map(\.id) == arrivingIDs,
            "New arrivals precede older project captures despite the legacy saved manual order")
        try expect(state.workspace.snapshot.projectItemOrders?[WorkspaceSnapshot.projectKey(project)] == initialOrder,
            "Ignoring obsolete manual ordering preserves the legacy workspace data")

        // Every width exposes item types through one icon menu; an empty
        // combination offers one action to clear both type and date filtering.
        state.openLibrary()
        window.setContentSize(CGSize(width: 320, height: 760)); try await settle(hosting)
        try await selectMenu(hosting, id: "project-filter-menu", title: "Tasks")
        try expect(state.projectPresentation[project]?.filterRawValue == "Tasks", "Narrow native menu reaches the formerly hidden Tasks filter")
        try await press("project-reset-filters", in: hosting, message: "Empty filtered project resets in one click")
        try await settle(hosting)
        try expect(state.projectPresentation[project]?.filterRawValue == "All"
            && state.projectPresentation[project]?.dateFilter == .anytime
            && state.projectPresentation[project]?.selectedDateRange == nil, "Reset restores both All types and Any date")
        try saveFixtureImage(hosting, filename: "project-filter-menu-narrow@2x.png", directory: fixtures)
        window.setContentSize(CGSize(width: 1_080, height: 760)); try await settle(hosting)

        // Mixed copy actions execute the menu's real closures against a private
        // pasteboard. Their labels and output have the same selected scope.
        state.projectPresentation[project, default: ProjectNavigationPresentation()].selectedIDs = [imageID, textID, noteID]
        try await settle(hosting)
        try await selectMenu(hosting, id: "project-actions", title: "Copy selected items")
        let copied = clipboard.pasteboardItems ?? []
        try expect(copied.count == 3 && copied[0].string(forType: .fileURL) == store.managedURL(for: image)?.absoluteString,
            "Mixed selected Copy retains its file, text and live note as three ordered items")
        try expect(copied[1].string(forType: .string) == text.originalText
            && copied[2].string(forType: .string) == state.workspace.scratchpad(project: project), "Copy retains exact text and live project notes")
        try expect(copied.allSatisfy { !$0.types.contains(ExplorerTransfer.pasteboardType) }, "Public Copy does not leak a local move identity")
        try await selectMenu(hosting, id: "project-actions", title: "Copy selection summary")
        let summary = clipboard.string(forType: .string) ?? ""
        try expect(summary.contains(project) && summary.contains(text.title) && summary.contains(image.title)
            && !summary.contains(other.originalText ?? "UNRELATED"), "Copy summary includes the selected project content and excludes unrelated captures")
        try await clearSelection(in: hosting)
        try await selectMenu(hosting, id: "project-actions", title: "Open folder")
        try expect(openedFolders.count == 1 && openedFolders[0].path.hasPrefix(root.path), "Open folder resolves only the selected fictional project's local archive")

        // Both mode destinations retain project context and an actual history
        // return. The Board-level picker suite covers their rendered return UI.
        for (title, mode) in [("Clipboard view", WorkspaceMode.clipboard), ("Shelf view", WorkspaceMode.shelf)] {
            try await selectMenu(hosting, id: "project-actions", title: title)
            try expect(state.workspace.mode == mode && state.libraryProject == project, "Native \(title) keeps the selected project")
            state.back(); try await settle(hosting)
            try expect(state.route == .library && state.workspace.mode == .collection && state.libraryProject == project,
                "Back returns from \(title) to the same project collection")
        }
        try await selectMenu(hosting, id: "project-actions", title: "Project notes")
        guard let sheet = window.sheets.first, let noteHost = sheet.contentView else { throw failure("Project notes must open its own editable sheet") }
        try await settle(noteHost)
        try await press("project-notes-done", in: noteHost, message: "Project notes has a reachable Done return")
        try await settle(hosting)
        try expect(window.sheets.isEmpty && state.workspace.scratchpad(project: project) == liveNote.text,
            "Closing notes preserves the live project note without another capture")

        // Native conversion and immediate Undo preserve the same captures and
        // files. A later edit invalidates the receipt and hides a stale Undo.
        state.projectPresentation[project, default: ProjectNavigationPresentation()].selectedIDs = [imageID, textID, noteID]
        try await settle(hosting)
        try await press("project-make-tasks", in: hosting, message: "Selected originals can become tasks in place")
        try await settle(hosting)
        try expect(image.isTask && text.isTask && state.workspace.scratchpad(project: project) == liveNote.text,
            "Conversion changes captures in place while live project notes remain notes")
        try await press("project-undo-tasks", in: hosting, message: "Native Undo restores task conversion")
        try await settle(hosting)
        let restoredOriginal = try originalBytes(store: store, capture: image)
        try expect(!image.isTask && !text.isTask && restoredOriginal == original,
            "Undo restores original capture types and exact file bytes")
        try await clearSelection(in: hosting)

        // Feed the production named-project drop receiver an explicit internal
        // drag identity, then invoke the newly reachable native Undo action.
        let provider = try ExplorerTransfer.itemProvider(for: other, store: store)
        try expect(state.explorerInput.receive([provider], project: project), "Named project accepts the internal drag payload")
        for _ in 0..<40 where state.explorerInput.isBusy { try await Task.sleep(for: .milliseconds(35)) }
        try await settle(hosting)
        try expect(other.projectName == project && state.explorerInput.canUndoMove, "Drop moves the same capture into the named project")
        try await press("project-undo-move", in: hosting, message: "Undo move is reachable in the destination named project")
        try await settle(hosting)
        try expect(other.projectName == "Another fictional project" && !state.explorerInput.canUndoMove,
            "Named-project Undo restores the source project without copying or deleting the capture")

        clipboard.clearContents(); try expect(clipboard.setString("Fictional native project paste", forType: .string), "Private paste fixture is prepared")
        let countBeforePaste = store.captures.count
        try await selectMenu(hosting, id: "project-actions", title: "Paste into project")
        for _ in 0..<40 where state.explorerInput.isBusy { try await Task.sleep(for: .milliseconds(35)) }
        try await settle(hosting)
        try expect(store.captures.count == countBeforePaste + 1
            && store.captures.contains { $0.originalText == "Fictional native project paste" && $0.projectName == project },
            "Native Paste imports exactly one new capture into the selected project")

        state.projectPresentation[project, default: ProjectNavigationPresentation()].selectedIDs = [textID]
        try await settle(hosting); try await press("project-make-tasks", in: hosting, message: "Single selected capture can become a task")
        try await settle(hosting)
        _ = try store.setTaskCompleted(text, completed: true)
        try await settle(hosting)
        try expect(!nodes(in: hosting).contains { $0.identifier == "project-undo-tasks" && $0.frame.width > 0 },
            "After later task edits the project hides an invalid conversion Undo instead of offering an action that must fail")
        try expect(!window.isKeyWindow && !window.isMainWindow, "Project menus and sheet returns stay inside the isolated fixture")
        try await checkLiveZoomBrowser(fixtures: fixtures)
        try await checkCalendarFiltering(fixtures: fixtures)
        print("PASS: \(checks) project workspace UI checks; 1,000 synthetic text captures plus image and editable project note; retained-host live zoom, observable edits and replacement identities; native mixed-selection drag payloads on a private pasteboard; no personal archive, network, general clipboard or external opening. At most \(maximumRows) simultaneously materialized native rows.")
    }

    private static func checkLiveZoomBrowser(fixtures: URL) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinProjectLiveZoomQA-\(UUID())")
        let suite = "DaBinProjectLiveZoomQA.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: PreviewService.linkPreviewPreference)
        defaults.set(1, forKey: WorkspaceZoomSettings.factorKey)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let project = "Fictional live zoom project"
        let at = Calendar.current.startOfDay(for: Date()).addingTimeInterval(12 * 3_600)
        let taskSeed = Capture(capturedAt: at.addingTimeInterval(2), kind: .task,
            originalText: "Fictional task original preserved across zoom and replacement", title: "Fictional original task")
        taskSeed.projectName = project
        let olderSeed = Capture(capturedAt: Calendar.current.date(byAdding: .day, value: -1, to: at)!,
            kind: .text, originalText: "Fictional previous-day capture excluded by today's selection", title: "Fictional previous-day capture")
        olderSeed.projectName = project
        try CaptureRepository(root: root).save([taskSeed, olderSeed])
        let store = try CaptureStore(root: root, repairArchiveOnOpen: false)
        guard let task = store.captures.first(where: { $0.id == taskSeed.id }),
              let older = store.captures.first(where: { $0.id == olderSeed.id }) else { throw failure("Live zoom seed is missing") }
        let png = try fixturePNG()
        let image = try await store.importData(png, filename: "Fictional zoom poster.png",
            at: at.addingTimeInterval(3), projectName: project)
        guard let thumbnail = await PreviewService.writeThumbnail(png, root: root, id: image.id) else {
            throw failure("Live zoom fixture needs its real local thumbnail")
        }
        image.thumbnailRelativePath = thumbnail; image.previewState = "ready"
        image.title = "Fictional retained project picture title spanning two readable lines across the saved poster"
        try store.save(captures: [image])
        let previews = PreviewService(store: store, defaults: defaults)
        let auto = AutoCaptureService(settings: AutoCaptureSettings(defaults: defaults), input: InputService(store: store),
            pasteboardProvider: { fatalError("Live zoom QA must not read the clipboard") }, sourceApplicationProvider: { nil })
        let zoom = WorkspaceZoomSettings(defaults: defaults)
        let state = AppState(store: store, previews: previews,
            reminders: ReminderService(store: store, client: ProjectWorkspaceFixtureNotifications()), autoCapture: auto,
            captureClipboard: CaptureClipboardService(writer: { _ in fatalError("Live zoom QA must not write the clipboard") }),
            workspaceZoom: zoom, folderOpener: { _ in fatalError("Live zoom QA must not open external folders") })
        defer { previews.shutdown(); auto.shutdown(); state.focusSessions.shutdown(); store.cancelArchiveRepair() }
        state.libraryProject = project; state.workspace.mode = .collection; state.openLibrary()
        let initialNote = "Fictional initial live project note"
        try state.workspace.setScratchpad(text: initialNote, project: project)
        var workspace = state.workspace.snapshot
        workspace.scratchpads[WorkspaceSnapshot.projectKey(project)]?.updatedAt = at.addingTimeInterval(1)
        try state.workspace.save(workspace)
        let pasteboard = NSPasteboard(name: .init("DaBin.ProjectLiveZoomQA.\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        let host = NSHostingView(rootView: ProjectWorkspaceLiveZoomFixture(state: state, project: project, pasteboard: pasteboard))
        host.frame = CGRect(x: 0, y: 0, width: 960, height: 820)
        host.sizingOptions = []; host.autoresizingMask = [.width, .height]
        let window = ProjectWorkspaceFixtureWindow(contentRect: host.frame.offsetBy(dx: -10_000, dy: -10_000),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        zoom.onInteractionBegan = { WorkspaceZoomViewport.begin(in: window); return true }
        zoom.onInteractionEnded = { WorkspaceZoomViewport.end(in: window) }
        defer {
            zoom.finishInteraction(); zoom.onInteractionBegan = nil; zoom.onInteractionEnded = nil
            window.orderOut(nil); window.contentView = nil; window.close()
        }
        window.orderFront(nil); try await settle(host)
        let imageID = ProjectWorkspaceIdentity.capture(image.id), taskID = ProjectWorkspaceIdentity.capture(task.id)
        let noteID = ProjectWorkspaceIdentity.note(project: project)
        let initialNotePreview = try await find("project-preview-" + noteID, in: host)
        try expect(initialNotePreview.valueText == initialNote,
            "The initial non-media note preview exposes the same excerpt as its rendered text")
        try saveFixtureImage(host, filename: "project-live-note-initial@2x.png", directory: fixtures)
        guard let originalTable = table(in: host) else { throw failure("Live project zoom needs its native List") }
        let originalRows = originalTable.numberOfRows
        try expect(zoom.beginInteraction(), "The retained project host begins its real zoom interaction")
        var titleHeights: [CGFloat: CGFloat] = [:], previewHeights: [CGFloat: CGFloat] = [:]
        for factor in [CGFloat(0.75), 2, 1] {
            zoom.update(to: factor); try await settle(host)
            let title = try await find("project-details-" + imageID, in: host)
            let media = try await find("project-preview-" + imageID, in: host)
            // List exposes the outer card's containing AX group and its real
            // buttons. The redundant non-task inner group is merged away;
            // standalone card QA also uses this outer group for card bounds.
            let content = try await find("project-card-" + imageID, in: host)
            let expectedHeight = min(192, ExplorerCaptureCardPresentation.previewHeight(for: media.frame.width / factor) * factor)
            titleHeights[factor] = title.frame.height; previewHeights[factor] = media.frame.height
            try expect(zoom.isInteracting && table(in: host) === originalTable && originalTable.numberOfRows == originalRows,
                "\(Int(factor * 100))% zoom retains the same native table and gesture-locked row identities")
            try expect(title.frame.height > 32 && abs(media.frame.height - expectedHeight) < 1
                && content.frame.width > 0 && content.frame.height > media.frame.height
                && content.frame.insetBy(dx: -1, dy: -1).contains(title.frame)
                && content.frame.insetBy(dx: -1, dy: -1).contains(media.frame),
                "Live \(Int(factor * 100))% zoom keeps naturally measured two-line title, scaled media and complete card content")
            for identifier in ["project-select-" + imageID, "project-select-" + taskID, "project-task-toggle-" + taskID] {
                let control = try await find(identifier, in: host)
                try expect(abs(control.interactionFrame.width - 32) <= 1 && abs(control.interactionFrame.height - 32) <= 1,
                    "Zoom keeps the native \(identifier) target at 32 points")
            }
            if factor != 1 { try saveFixtureImage(host, filename: "project-live-zoom-\(Int(factor * 100))@2x.png", directory: fixtures) }
        }
        zoom.finishInteraction(); try await settle(host)
        try expect(titleHeights[2]! > titleHeights[0.75]! + 2 && titleHeights[1]! < titleHeights[2]!
            && previewHeights[2]! > previewHeights[0.75]! + 20 && previewHeights[1]! < previewHeights[2]!,
            "The same hosted title and real preview grow at 200% and return at 100%, independently of stable List equality")
        try expect(!zoom.isInteracting && !WorkspaceZoomViewport.isZooming(in: window), "Live project zoom releases its viewport interaction owner")

        // An observable edit must repaint even before a store-wide revision.
        task.title = "Fictional observable task edit after zoom"
        try await settle(host)
        let editedTitle = try await find("project-details-" + taskID, in: host)
        try expect(editedTitle.label.contains(task.title), "A live Capture observer updates its title through the stable browser boundary")
        try store.save(captures: [task])
        try store.moveToTrash(task); try await settle(host)
        try expect(!nodes(in: host).contains { $0.identifier == "project-card-" + taskID && $0.frame.width > 0 },
            "A removed capture leaves the same retained native browser")
        guard let trashed = store.trashedCaptures.first(where: { $0.id == task.id }) else { throw failure("Replacement fixture must enter local trash") }
        try store.restoreFromTrash(trashed)
        guard let replacement = store.captures.first(where: { $0.id == task.id }) else { throw failure("Replacement fixture must return to its project") }
        try expect(replacement !== task, "Restoring the fixture supplies a genuinely new Capture object with the same row identity")
        task.title = "Fictional obsolete capture instance"
        replacement.title = "Fictional current restored task after zoom"
        try store.save(captures: [replacement]); try await settle(host)
        let restoredTitle = try await find("project-details-" + taskID, in: host)
        try expect(restoredTitle.label.contains(replacement.title) && !restoredTitle.label.contains(task.title),
            "Content revision replaces an obsolete capture while preserving its logical card ID")
        try await press("project-task-toggle-" + taskID, in: host, message: "Restored card completion performs its current native action")
        try await settle(host)
        try expect(replacement.isCompleted && !task.isCompleted && state.store.error == nil,
            "The retained completion callback targets the current replacement, not its rejected obsolete instance")

        let revisedNote = "Fictional live note edited after the retained browser zoom"
        try state.workspace.setScratchpad(text: revisedNote, project: project)
        workspace = state.workspace.snapshot
        workspace.scratchpads[WorkspaceSnapshot.projectKey(project)]?.updatedAt = at.addingTimeInterval(1)
        try state.workspace.save(workspace); try await settle(host)
        try saveFixtureImage(host, filename: "project-live-note-edited@2x.png", directory: fixtures)
        let revisedNotePreview = try await find("project-preview-" + noteID, in: host)
        try expect(nodes(in: host).contains { ($0.label + " " + $0.valueText).contains(revisedNote) && $0.frame.width > 0 },
            "Live scratchpad text changes in the existing project card after zoom")
        try expect(revisedNotePreview.valueText == revisedNote && revisedNotePreview.valueText != initialNote,
            "The same hosted note preview replaces its initial excerpt with the latest workspace edit")
        try await press("project-select-" + taskID, in: host, message: "Restored capture remains independently selectable")
        try await press("project-select-" + noteID, in: host, message: "Edited project notes join the current selection")
        try await settle(host)
        try expect(state.projectPresentation[project]?.selectedIDs == [taskID, noteID]
            && state.projectPresentation[project]?.focusedID == noteID,
            "Post-zoom native selection preserves the live focus binding and both checked items")
        let currentNote = WorkspaceScratchpad(text: revisedNote, projectName: project, updatedAt: at.addingTimeInterval(1))
        try await checkNativeProjectDrag(in: host, label: replacement.title,
            expected: [.capture(replacement), .note(currentNote)], store: store)
        try await selectMenu(host, id: "project-filter-menu", title: "Files")
        try await press("project-select-all", in: host, message: "Post-zoom Files selection uses only its current visible item")
        try await settle(host)
        try expect(state.projectPresentation[project]?.selectedIDs == [imageID], "Filtering replaces the previously selected task and note with the visible image")
        try await checkNativeProjectDrag(in: host, label: image.title, expected: [.capture(image)], store: store)
        try await selectMenu(host, id: "project-filter-menu", title: "All")
        try await chooseCalendarAction("project-date-today", in: host)
        try await press("project-select-all", in: host, message: "Post-zoom calendar selection uses only today's visible items")
        try await settle(host)
        try expect(state.projectPresentation[project]?.selectedIDs == [imageID, taskID, noteID], "Exact date filtering excludes the previous-day capture")
        try await checkNativeProjectDrag(in: host, label: image.title,
            expected: [.capture(image), .capture(replacement), .note(currentNote)], store: store)
        state.projectPresentation[project, default: ProjectNavigationPresentation()].selectedDateRange =
            ProjectDateSelection(date: older.capturedAt, mode: .day)
        try await settle(host)
        try await press("project-select-all", in: host, message: "A restored date context selects its newly visible previous-day capture")
        try await settle(host)
        try expect(state.projectPresentation[project]?.selectedIDs == [ProjectWorkspaceIdentity.capture(older.id)],
            "A changed date context prunes hidden selection and updates the stable action holder")
        try await checkNativeProjectDrag(in: host, label: older.title, expected: [.capture(older)], store: store)
        try expect(!window.isKeyWindow && !window.isMainWindow && window.frame.maxX < 0,
            "Zoom, mutation, replacement, notes, dates and actual native drag payload checks stay in the fictional offscreen fixture")
    }

    private static func checkCalendarFiltering(fixtures: URL) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinProjectCalendarQA-\(UUID().uuidString)")
        let suite = "DaBinProjectCalendarQA.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: PreviewService.linkPreviewPreference)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let project = "Fictional calendar project", calendar = Calendar.current
        func date(_ key: String, timeZone: TimeZone = .current, hour: Int = 12) -> Date {
            var civil = Calendar(identifier: .gregorian); civil.timeZone = timeZone
            let parts = key.split(separator: "-").compactMap { Int($0) }
            return civil.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: hour))!
        }
        let start = date("2025-12-25")
        var captures = (0..<15).map { offset -> Capture in
            let at = calendar.date(byAdding: .day, value: offset, to: start)!
            let capture = Capture(capturedAt: at, kind: .text, originalText: "Fictional receipt \(offset)", title: "Receipt \(offset)")
            capture.projectName = project
            return capture
        }
        // This timestamp displays on an adjacent day on the Mac. Project day
        // filtering must use its immutable Jan 1 capture-zone receipt instead.
        let eastward = calendar.timeZone.secondsFromGMT(for: date("2026-01-01")) < 14 * 3_600
        let receiptZone = TimeZone(secondsFromGMT: (eastward ? 14 : -12) * 3_600)!
        let shifted = Capture(capturedAt: date("2026-01-01", timeZone: receiptZone, hour: eastward ? 0 : 23), timeZone: receiptZone,
            kind: .text, originalText: "Fictional date-line receipt", title: "Date-line receipt")
        shifted.projectName = project; captures.append(shifted)
        try expect(shifted.captureDay == "2026-01-01" && CaptureCalendar.dayString(shifted.capturedAt) != shifted.captureDay,
            "The calendar fixture contains a real capture-zone date-line difference")
        try CaptureRepository(root: root).save(captures)
        let store = try CaptureStore(root: root, repairArchiveOnOpen: false)
        let previews = PreviewService(store: store, defaults: defaults)
        let auto = AutoCaptureService(settings: AutoCaptureSettings(defaults: defaults), input: InputService(store: store),
            pasteboardProvider: { fatalError("Project calendar QA must not read the clipboard") }, sourceApplicationProvider: { nil })
        let state = AppState(store: store, previews: previews,
            reminders: ReminderService(store: store, client: ProjectWorkspaceFixtureNotifications()), autoCapture: auto,
            captureClipboard: CaptureClipboardService(writer: { _ in fatalError("Project calendar QA must not write the clipboard") }))
        defer { previews.shutdown(); auto.shutdown(); state.focusSessions.shutdown(); store.cancelArchiveRepair() }
        state.libraryProject = project; state.workspace.mode = .collection; state.openLibrary()
        try state.workspace.setScratchpad(text: "Fictional project note dated Jan 2", project: project)
        var workspace = state.workspace.snapshot
        workspace.scratchpads[WorkspaceSnapshot.projectKey(project)]?.updatedAt = date("2026-01-02")
        try state.workspace.save(workspace)
        let initialWorkspace = state.workspace.snapshot
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let before = try Dictionary(uniqueKeysWithValues: store.captures.map { ($0.id, try encoder.encode(CaptureSnapshot($0))) })
        state.projectPresentation[project, default: ProjectNavigationPresentation()].selectedDateRange =
            ProjectDateSelection(date: date("2025-12-31"), mode: .day)
        state.projectPresentation[project, default: ProjectNavigationPresentation()].dateFilter = .lastSevenDays
        let pasteboard = NSPasteboard(name: .init("DaBin.ProjectCalendarQA.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let host = NSHostingView(rootView: ProjectWorkspaceView(state: state, project: project, pasteboard: pasteboard,
            chooseExportDestination: { _ in nil })
            .environment(\.daBinTooltipsEnabled, false).environment(\.displayScale, 2).preferredColorScheme(.light)
            .transaction { $0.animation = nil; $0.disablesAnimations = true })
        host.frame = CGRect(x: 0, y: 0, width: 760, height: 760)
        host.sizingOptions = []; host.autoresizingMask = [.width, .height]
        let window = ProjectWorkspaceFixtureWindow(contentRect: CGRect(x: -10_000, y: -10_000, width: 760, height: 760),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        window.orderFront(nil); try await settle(host)
        let initialCount = try await selectionText(in: host)
        try expect(initialCount.contains("1 of 17"), "An exact civil day takes precedence over a stale relative preset")

        var popup = try await openCalendar(host)
        try await checkCalendarGeometry(popup)
        try await press("project-date-mode-week", in: popup.content, message: "Week mode can be selected inside the native calendar")
        try await settle(popup.content)
        try expect(calendarPopover() != nil, "Changing Day/Week mode keeps the calendar available until a date is chosen")
        try await press("project-calendar-day-2025-12-31", in: popup.content, message: "A December date selects its entire calendar week")
        try await settle(host)
        try expect(calendarPopover() == nil, "Choosing a week closes the native calendar immediately")
        let interval = calendar.dateInterval(of: .weekOfYear, for: date("2025-12-31"))!
        let weekStart = CaptureCalendar.dayString(interval.start, timeZone: calendar.timeZone)
        let weekEnd = CaptureCalendar.dayString(calendar.date(byAdding: .day, value: -1, to: interval.end)!, timeZone: calendar.timeZone)
        let selectedWeek = state.projectPresentation[project]?.selectedDateRange
        try expect(selectedWeek?.mode == .week && selectedWeek?.startDay == weekStart && selectedWeek?.endDay == weekEnd
            && weekStart.hasPrefix("2025-12-") && weekEnd.hasPrefix("2026-01-"),
            "Week selection honors the Mac's calendar boundaries across both month and year")
        try expect(state.projectPresentation[project]?.dateFilter == .anytime,
            "Selecting a week clears any hidden rolling-date preset")
        let weekCount = captures.filter { $0.captureDay >= weekStart && $0.captureDay <= weekEnd }.count
            + ((weekStart...weekEnd).contains("2026-01-02") ? 1 : 0)
        let weekCountText = try await selectionText(in: host)
        try expect(weekCountText.contains("\(weekCount) of 17"),
            "The native week action filters exact receipt days and the live note's updated day")

        popup = try await openCalendar(host)
        try expect(state.projectPresentation[project]?.selectedDateRange == selectedWeek,
            "Reopening the date picker preserves its committed calendar week")
        let reopenedWeekDay = try await find("project-calendar-day-2025-12-31", in: popup.content)
        try expect(reopenedWeekDay.valueText.contains("Selected"),
            "The reopened calendar visibly and accessibly marks the previously chosen week")
        try saveFixtureImage(popup.content, filename: "project-calendar-week-light@2x.png", directory: fixtures)
        try await press("project-date-mode-day", in: popup.content, message: "Day mode restores individual date selection")
        try await press("project-calendar-next", in: popup.content, message: "Month navigation moves December into January")
        try await settle(popup.content)
        _ = try await find("project-calendar-day-2026-01-01", in: popup.content)
        try saveFixtureImage(popup.content, filename: "project-calendar-january-light@2x.png", directory: fixtures)
        try await press("project-calendar-day-2026-01-01", in: popup.content, message: "Jan 1 is selected through its native date button")
        try await settle(host)
        try expect(calendarPopover() == nil && state.projectPresentation[project]?.selectedDateRange?.startDay == "2026-01-01"
            && state.projectPresentation[project]?.selectedDateRange?.endDay == "2026-01-01",
            "Day mode commits exactly one date and dismisses the picker")
        let dayCount = try await selectionText(in: host)
        try expect(dayCount.contains("2 of 17"), "Jan 1 contains its normal capture and date-line receipt, excluding Jan 2 project notes")
        _ = try await find("project-card-" + ProjectWorkspaceIdentity.capture(shifted.id), in: host)
        try expect(!nodes(in: host).contains { $0.identifier == "project-card-" + ProjectWorkspaceIdentity.note(project: project) },
            "A live note is filtered by its updatedAt day rather than the capture receipt day")

        try await chooseCalendarAction("project-calendar-day-2026-01-02", in: host)
        let noteDayCount = try await selectionText(in: host)
        try expect(noteDayCount.contains("2 of 17"), "Jan 2 includes its capture and its one live project note")
        _ = try await find("project-card-" + ProjectWorkspaceIdentity.note(project: project), in: host)
        let selectedDay = state.projectPresentation[project]?.selectedDateRange
        try await selectMenu(host, id: "project-actions", title: "Clipboard view")
        state.back(); try await settle(host)
        try expect(state.route == .library && state.libraryProject == project
            && state.projectPresentation[project]?.selectedDateRange == selectedDay,
            "Returning to the project preserves its exact calendar day")

        popup = try await openCalendar(host)
        let reopenedDay = try await find("project-calendar-day-2026-01-02", in: popup.content)
        try expect(reopenedDay.valueText.contains("Selected"),
            "The reopened calendar retains the selected individual day")
        try saveFixtureImage(popup.content, filename: "project-calendar-day-light@2x.png", directory: fixtures)
        try await press("project-calendar-prev", in: popup.content, message: "Previous month navigates across January into December")
        try await settle(popup.content)
        _ = try await find("project-calendar-day-2025-12-31", in: popup.content)
        try await press("project-calendar-next", in: popup.content, message: "Forward month restores January without changing the committed date")
        try await settle(popup.content)
        try expect(state.projectPresentation[project]?.selectedDateRange == selectedDay,
            "Browsing months leaves the committed project date unchanged")
        try await press("project-date-any", in: popup.content, message: "Any date clears calendar refinement in one click")
        try await settle(host)
        let unfilteredCount = try await selectionText(in: host)
        try expect(calendarPopover() == nil && unfilteredCount.contains("17") && !unfilteredCount.contains(" of ")
            && state.projectPresentation[project]?.selectedDateRange == nil && state.projectPresentation[project]?.dateFilter == .anytime,
            "Any date closes the picker and restores all captures and live project notes")

        try await chooseCalendarAction("project-date-today", in: host)
        let today = CaptureCalendar.dayString(Date())
        try expect(state.projectPresentation[project]?.selectedDateRange?.mode == .day
            && state.projectPresentation[project]?.selectedDateRange?.startDay == today
            && state.projectPresentation[project]?.selectedDateRange?.endDay == today,
            "Today shortcut selects exactly the current civil day")
        try await selectMenu(host, id: "project-filter-menu", title: "Tasks")
        try await press("project-reset-filters", in: host, message: "Show all items clears both type and exact date filtering")
        try await settle(host)
        try expect(state.projectPresentation[project]?.filterRawValue == "All"
            && state.projectPresentation[project]?.selectedDateRange == nil && state.projectPresentation[project]?.dateFilter == .anytime,
            "The empty state resets the calendar range along with the item filter")

        for scheme in [ColorScheme.light, .dark] {
            state.projectPresentation[project, default: ProjectNavigationPresentation()].selectedDateRange = selectedDay
            host.rootView = ProjectWorkspaceView(state: state, project: project, pasteboard: pasteboard,
                chooseExportDestination: { _ in nil })
                .environment(\.daBinTooltipsEnabled, false).environment(\.displayScale, 2).preferredColorScheme(scheme)
                .transaction { $0.animation = nil; $0.disablesAnimations = true }
            for width in [CGFloat(320), 400, 760] {
                window.setContentSize(CGSize(width: width, height: 760)); try await settle(host)
                try await checkToolbar(in: host)
                popup = try await openCalendar(host)
                try await checkCalendarGeometry(popup)
                if width == 320 {
                    try saveFixtureImage(popup.content,
                        filename: "project-calendar-320-\(scheme == .light ? "light" : "dark")@2x.png", directory: fixtures)
                }
                try await press("project-date-any", in: popup.content, message: "Calendar dismissal remains reachable at width \(Int(width))")
                try await settle(host)
                try expect(calendarPopover() == nil, "Compact \(scheme) calendar selection closes its popover")
            }
        }
        let after = try Dictionary(uniqueKeysWithValues: store.captures.map { ($0.id, try encoder.encode(CaptureSnapshot($0))) })
        try expect(before == after && state.workspace.snapshot.scratchpads == initialWorkspace.scratchpads,
            "Calendar opening, mode changes, month browsing, filtering, clear, reset, and history preserve all saved content")
        try expect(!window.isKeyWindow && !window.isMainWindow,
            "Calendar regression uses only its own offscreen project fixture")
    }

    private static func originalBytes(store: CaptureStore, capture: Capture) throws -> Data {
        guard let url = store.managedURL(for: capture) else { throw failure("Synthetic managed original missing") }
        return try Data(contentsOf: url)
    }
}
