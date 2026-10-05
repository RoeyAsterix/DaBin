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
        let expected = selectedCount == 0 ? "Export project" : "Export selected (\(selectedCount))"
        try expect(label == expected, "Export states its current scope: \(label), expected \(expected)")
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
                                               reorder: Bool, store: CaptureStore) async throws {
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
        try expect(marked.count == (reorder ? 1 : 0),
            "Project reorder marker appears once in My order and is absent outside the reorder scope")
        if reorder {
            try expect(writers[0].pasteboardPropertyList(forType: marker) as? Data == Data("reorder".utf8),
                "Reordering supplements the first item's public content with an explicit local marker")
        }
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
        // Remove the key altogether: an explicitly saved empty sequence still
        // selects manual ordering, unlike a never-reordered project.
        // New captures must prepend without rebuilding every full grid row.
        var initialWorkspace = state.workspace.snapshot
        initialWorkspace.projectItemOrders?.removeValue(forKey: WorkspaceSnapshot.projectKey(project))
        try state.workspace.save(initialWorkspace)
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
        let initialOrder = [imageID, textID, noteID] + seeded.dropFirst().map { ProjectWorkspaceIdentity.capture($0.id) }
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
        let hosting = NSHostingView(rootView: ProjectWorkspaceView(state: state, project: project, pasteboard: clipboard,
            chooseExportDestination: { document in preparedExports.append(document); return nil })
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
        try saveFixtureImage(hosting, filename: "project-grid-wide@2x.png", directory: fixtures)

        let initialSelection = try await selectionText(in: hosting)
        try expect(initialSelection.contains("1002") && !initialSelection.contains("selected"),
                   "Project starts unselected and includes all captures plus its one live note")
        try await checkExportAction(in: hosting)
        try await press("project-export", in: hosting, message: "Whole-project export directly prepares a destination choice")
        try await settle(hosting)
        try expect(preparedExports.count == 1 && preparedExports.last?.scope == .project
            && preparedExports.last?.itemCount == 1_002 && preparedExports.last?.notes != nil,
            "The direct project action includes every capture and the live project note")
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
        try expect(preparedExports.count == 2 && preparedExports.last?.scope == .selection
            && preparedExports.last?.itemCount == 2 && preparedExports.last?.notes == nil
            && Set(preparedExports.last?.items.map(\.id) ?? []) == Set([image.id, text.id]),
            "Selected export includes exactly the two checked captures, with no unselected live note")
        try expect(state.route == .library, "Selecting cards never opens capture details")
        try await press("project-select-" + noteID, in: hosting, message: "Live project notes can join a capture and image selection")
        try await settle(hosting)
        let liveNote = WorkspaceScratchpad(text: state.workspace.scratchpad(project: project), projectName: project, updatedAt: at)
        try await checkNativeProjectDrag(in: hosting, label: image.title,
            expected: [.capture(image), .capture(text), .note(liveNote)], reorder: true, store: store)
        try await settle(hosting)
        try await clearSelection(in: hosting)

        let selectAll = try await find("project-select-all", in: hosting)
        try expect(selectAll.press(), "Select all performs its real accessibility action")
        try await settle(hosting)
        let allSelected = try await selectionText(in: hosting)
        try expect(allSelected.contains("1002 selected"), "Select all includes the complete project and live note, never other projects")
        try await checkExportAction(in: hosting, selectedCount: 1_002)
        window.setContentSize(CGSize(width: 320, height: 760))
        try await settle(hosting)
        try await checkExportAction(in: hosting, selectedCount: 1_002)
        let narrowBoundary = window.convertToScreen(hosting.bounds)
        let narrowSelectedExport = try await find("project-export", in: hosting)
        try expect(narrowSelectedExport.frame.width > 0
            && narrowBoundary.insetBy(dx: -1, dy: -1).contains(narrowSelectedExport.frame),
            "The full selected export label fits the 320-point project window: \(narrowSelectedExport.frame) in \(narrowBoundary)")
        try saveFixtureImage(hosting, filename: "project-selected-narrow@2x.png", directory: fixtures)
        window.setContentSize(CGSize(width: 1_080, height: 760))
        try await settle(hosting)
        try await clearSelection(in: hosting)

        let filesFilter = try await find("project-filter-Files", in: hosting)
        try expect(filesFilter.press(), "Files filter performs its accessibility action")
        try await settle(hosting)
        let filtered = try await selectionText(in: hosting)
        try expect(filtered.contains("1 of 1002"), "Files filter shows one file while retaining the whole-project count")
        try await checkExportAction(in: hosting)
        try await press("project-export", in: hosting, message: "Unselected filtered view still exports the complete project")
        try await settle(hosting)
        try expect(preparedExports.count == 3 && preparedExports.last?.scope == .project
            && preparedExports.last?.itemCount == 1_002 && preparedExports.last?.notes != nil,
            "Viewing only Files never silently narrows whole-project export")
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
            expected: [.capture(image)], reorder: false, store: store)
        try await press("project-filter-All", in: hosting, message: "All filter restores the complete project")
        try await settle(hosting)
        let clearedByFilter = try await selectionText(in: hosting)
        try expect(!clearedByFilter.contains("selected"), "Changing filters clears hidden selection")
        try await checkExportAction(in: hosting)

        // Open and dispatch the production native menus inside this process.
        try await selectMenu(hosting, id: "project-sort-order", title: "Newest first")
        try expect(state.projectPresentation[project]?.newestFirst == true, "Native sort menu changes project ordering")
        try await checkNativeProjectDrag(in: hosting, label: image.title, expected: [.capture(image)], reorder: false, store: store)
        try await selectMenu(hosting, id: "project-sort-order", title: "My order")
        try expect(state.projectPresentation[project]?.newestFirst == false, "Custom order returns through the same native menu")
        // Changing order intentionally preserves a browsing viewport. Position
        // this fixture at its known first item before inspecting that item.
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
        let availableOrder = ProjectWorkspaceContents.captures(in: project, from: store.captures).map { ProjectWorkspaceIdentity.capture($0.id) } + [noteID]
        let restoredOrder = ProjectWorkspaceOrdering.ordered(availableOrder, saved: initialOrder)
        try state.workspace.saveProjectItemOrder(restoredOrder, project: project)
        state.projectPresentation[project, default: ProjectNavigationPresentation()].viewport = nil
        try await scrollToStart(hosting)
        let boundaryMenu = try await nativeMenu(hosting, id: "project-more-" + imageID, containing: "Move earlier")
        try expect(menuItems(boundaryMenu).first { $0.title == "Move earlier" }?.isEnabled == false,
            "The first item cannot offer a no-op Move earlier action")
        try await selectMenu(hosting, id: "project-more-" + imageID, title: "Move later")
        try expect(state.workspace.orderedProjectItemIDs(initialOrder, project: project).prefix(2) == [textID, imageID],
            "Native item action moves the saved item exactly one position")
        state.projectPresentation[project, default: ProjectNavigationPresentation()].viewport = nil
        try await scrollToStart(hosting)
        try await selectMenu(hosting, id: "project-more-" + imageID, title: "Move earlier")
        try expect(state.workspace.orderedProjectItemIDs(initialOrder, project: project).prefix(2) == [imageID, textID],
            "Native reverse reorder restores custom positions")
        try await scrollToStart(hosting)
        try await clearSelection(in: hosting)

        // Narrow widths expose every type through a visible menu; an empty
        // combination offers one action to clear both type and date filtering.
        state.openLibrary()
        window.setContentSize(CGSize(width: 320, height: 760)); try await settle(hosting)
        try await selectMenu(hosting, id: "project-filter-menu", title: "Tasks")
        try expect(state.projectPresentation[project]?.filterRawValue == "Tasks", "Narrow native menu reaches the formerly hidden Tasks filter")
        try await press("project-reset-filters", in: hosting, message: "Empty filtered project resets in one click")
        try await settle(hosting)
        try expect(state.projectPresentation[project]?.filterRawValue == "All"
            && state.projectPresentation[project]?.dateFilter == .anytime, "Reset restores both All types and Any date")
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
        print("PASS: \(checks) project workspace UI checks; 1,000 synthetic text captures plus image and editable project note; native mixed-selection drag payloads on a private pasteboard; no personal archive, network, general clipboard or external opening. At most \(maximumRows) simultaneously materialized native rows.")
    }

    private static func originalBytes(store: CaptureStore, capture: Capture) throws -> Data {
        guard let url = store.managedURL(for: capture) else { throw failure("Synthetic managed original missing") }
        return try Data(contentsOf: url)
    }
}
