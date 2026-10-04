import AppKit
import ApplicationServices
import Darwin
import Foundation
import SwiftUI

@MainActor
private final class SearchWindowReminderClient: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .allowed }
    func requestAuthorization() async throws -> Bool { false }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws {}
    func removePending(_ identifiers: [String]) {}
    func removeDelivered(_ identifiers: [String]) {}
}

@MainActor
private final class SearchWindowTableDataSource: NSObject, NSTableViewDataSource {
    let count: Int

    init(count: Int) { self.count = count }

    func numberOfRows(in tableView: NSTableView) -> Int { count }
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? { row }
}

/// SwiftUI's own-process accessibility objects expose AppKit selectors without
/// necessarily conforming to NSAccessibility. Keep this adapter scoped to the
/// isolated fixture window; the suite never inspects another application.
@MainActor
private struct SearchWindowAXNode {
    let object: NSObject

    private func value(_ selectorName: String) -> Any? {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue()
    }

    private func attribute(_ name: String) -> Any? {
        let selector = NSSelectorFromString("accessibilityAttributeValue:")
        guard object.responds(to: selector),
              (value("accessibilityAttributeNames") as? [String])?.contains(name) == true else { return nil }
        return object.perform(selector, with: name as NSString)?.takeUnretainedValue()
    }

    var identifier: String? {
        (value("accessibilityIdentifier") as? String) ?? (attribute("AXIdentifier") as? String)
    }

    var label: String? {
        [value("accessibilityLabel"), value("accessibilityTitle"), attribute("AXTitle"),
         attribute("AXDescription"), value("accessibilityValue"), attribute("AXValue")]
            .compactMap { $0 as? String }.first { !$0.isEmpty }
    }

    var role: String {
        (value("accessibilityRole") as? String) ?? (attribute("AXRole") as? String) ?? ""
    }

    var frame: NSRect {
        let selector = NSSelectorFromString("accessibilityFrame")
        if object.responds(to: selector) {
            typealias FrameGetter = @convention(c) (AnyObject, Selector) -> NSRect
            return unsafeBitCast(object.method(for: selector), to: FrameGetter.self)(object, selector)
        }
        if let position = attribute("AXPosition") as? NSValue,
           let size = attribute("AXSize") as? NSValue {
            return NSRect(origin: position.pointValue, size: size.sizeValue)
        }
        return .zero
    }

    func press() -> Bool {
        let selector = NSSelectorFromString("accessibilityPerformPress")
        if object.responds(to: selector) {
            typealias PressAction = @convention(c) (AnyObject, Selector) -> Bool
            return unsafeBitCast(object.method(for: selector), to: PressAction.self)(object, selector)
        }
        let legacy = NSSelectorFromString("accessibilityPerformAction:")
        guard (value("accessibilityActionNames") as? [String])?.contains("AXPress") == true,
              object.responds(to: legacy) else { return false }
        _ = object.perform(legacy, with: "AXPress" as NSString)
        return true
    }

    var children: [Any] {
        var result: [Any] = []
        for selector in ["accessibilityChildren", "accessibilityChildrenInNavigationOrder", "accessibilityContents"] {
            if let values = value(selector) as? [Any] { result.append(contentsOf: values) }
        }
        if let values = attribute("AXChildren") as? [Any] { result.append(contentsOf: values) }
        if let view = object as? NSView { result.append(contentsOf: view.subviews) }
        return result
    }

    /// Single-ID lookups use one canonical AX child collection and stop as
    /// soon as the target is found. The exhaustive `children` list remains for
    /// intentionally bounded inventories and visual column collection.
    var lookupChildGroups: [[Any]] {
        var groups: [[Any]] = []
        for selector in ["accessibilityChildren", "accessibilityChildrenInNavigationOrder", "accessibilityContents"] {
            if let values = value(selector) as? [Any], !values.isEmpty {
                groups.append(values)
                break
            }
        }
        if groups.isEmpty, let values = attribute("AXChildren") as? [Any], !values.isEmpty {
            groups.append(values)
        }
        if let view = object as? NSView, !view.subviews.isEmpty { groups.append(view.subviews) }
        return groups
    }
}

@MainActor
private struct SearchWindowFixture {
    let root: URL
    let defaults: UserDefaults
    let store: CaptureStore
    let previews: PreviewService
    let autoCapture: AutoCaptureService
    let state: AppState
    let theme: ThemeSettings
    let datedCaptures: [Capture]
    let task: Capture
    let photo: Capture
    let note: WorkspaceScratchpad
    let stressDay: Date
}

/// Native Search acceptance coverage uses only generated fixture records, a
/// code-drawn 10x10 PNG, private temporary archives and private defaults.
@main
private enum SearchWindowTests {
    @MainActor private static var checks = 0
    @MainActor private static var keyboardNavigationVerification = "incomplete"
    private static let boardHeight: CGFloat = 720
    private static let commonQuery = "saffron atlas"
    private static let viewportQuery = "viewport load token"
    private static let columnViewportQuery = "independent column viewport"
    private static var skipsKeyboardVerification: Bool {
        ProcessInfo.processInfo.environment["DABIN_SEARCH_QA_SKIP_KEYBOARD"] == "1"
    }

    @MainActor private static var keyboardVerificationReceipt: String {
        skipsKeyboardVerification
            ? "not run: desktop focus unavailable"
            : "passed: native focus, \(keyboardNavigationVerification), Escape dismissal and Return activates Done"
    }

    @MainActor private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        guard try condition() else {
            throw NSError(domain: "SearchWindowTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    @MainActor private static func settle(_ seconds: TimeInterval = 0.22) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// Suspend the current MainActor job so queued SwiftUI/AppKit mounting and
    /// DispatchQueue.main viewport work can run before native assertions.
    @MainActor private static func waitForNativeUI(_ milliseconds: Int = 50) async throws {
        await Task.yield()
        try await Task.sleep(for: .milliseconds(milliseconds))
    }

    @MainActor private static func nodes(in view: NSView, maximumDepth: Int = 45) -> [SearchWindowAXNode] {
        var result: [SearchWindowAXNode] = []
        var visited = Set<ObjectIdentifier>()
        func visit(_ candidate: Any, depth: Int) {
            guard depth < maximumDepth, let object = candidate as? NSObject,
                  visited.insert(ObjectIdentifier(object)).inserted else { return }
            if let table = object as? NSTableView {
                table.enumerateAvailableRowViews { row, _ in visit(row, depth: depth + 1) }
                return
            }
            let node = SearchWindowAXNode(object: object)
            // Asking an AX table proxy for all children can instantiate every
            // logical SwiftUI List row. Realized native rows are visited below.
            if ["AXTable", "AXOutline", "AXList"].contains(node.role) { return }
            result.append(node)
            for child in node.children { visit(child, depth: depth + 1) }
        }
        visit(view, depth: 0)
        for child in NSAccessibility.unignoredChildren(from: [view]) { visit(child, depth: 0) }
        func visitAvailableRows(in current: NSView) {
            if let table = current as? NSTableView {
                table.enumerateAvailableRowViews { row, _ in visit(row, depth: 0) }
            }
            for child in current.subviews { visitAvailableRows(in: child) }
        }
        visitAvailableRows(in: view)
        return result
    }

    @MainActor private static func phase(_ message: String) {
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "en_US_POSIX")
        clock.timeZone = .current
        clock.dateFormat = "HH:mm:ss.SSS"
        let timestamp = clock.string(from: Date())
        let uptime = ProcessInfo.processInfo.systemUptime
        FileHandle.standardError.write(Data("[SearchWindowTests \(timestamp) +\(String(format: "%.3f", uptime))] \(message)\n".utf8))
    }

    private struct NodeLookupMetrics {
        var visited = 0
        var maximumChildCount = 0
        var sample: [String] = []
    }

    @MainActor private static func lookupNode(in view: NSView, id: String,
                                               maximumDepth: Int = 45) -> (SearchWindowAXNode?, NodeLookupMetrics) {
        var metrics = NodeLookupMetrics()
        var visited = Set<ObjectIdentifier>()
        func visit(_ candidate: Any, depth: Int) -> SearchWindowAXNode? {
            guard depth < maximumDepth, let object = candidate as? NSObject,
                  visited.insert(ObjectIdentifier(object)).inserted else { return nil }
            metrics.visited += 1
            if let table = object as? NSTableView {
                guard id.hasPrefix("search-select-") else { return nil }
                var match: SearchWindowAXNode?
                table.enumerateAvailableRowViews { row, _ in
                    if match == nil { match = visit(row, depth: depth + 1) }
                }
                return match
            }
            let node = SearchWindowAXNode(object: object)
            if metrics.sample.count < 60, node.identifier != nil || node.label != nil {
                metrics.sample.append("\(node.identifier ?? "-")/\(node.label ?? "-")")
            }
            if node.identifier == id { return node }
            if ["AXTable", "AXOutline", "AXList"].contains(node.role) { return nil }
            for children in node.lookupChildGroups {
                metrics.maximumChildCount = max(metrics.maximumChildCount, children.count)
                for child in children {
                    if let match = visit(child, depth: depth + 1) { return match }
                }
            }
            return nil
        }

        if id.hasPrefix("search-select-") {
            for table in nativeTables(in: view) {
                var match: SearchWindowAXNode?
                table.enumerateAvailableRowViews { row, _ in
                    if match == nil { match = visit(row, depth: 0) }
                }
                if let match { return (match, metrics) }
            }
        }
        if let match = visit(view, depth: 0) { return (match, metrics) }
        for child in NSAccessibility.unignoredChildren(from: [view]) {
            if let match = visit(child, depth: 0) { return (match, metrics) }
        }
        return (nil, metrics)
    }

    @MainActor private static func node(in view: NSView, id: String) throws -> SearchWindowAXNode {
        let started = ProcessInfo.processInfo.systemUptime
        var totalVisited = 0
        var maximumChildCount = 0
        var sample: [String] = []
        for _ in 0..<7 {
            let (result, metrics) = lookupNode(in: view, id: id)
            totalVisited += metrics.visited
            maximumChildCount = max(maximumChildCount, metrics.maximumChildCount)
            if sample.isEmpty { sample = metrics.sample }
            if let result {
                let duration = ProcessInfo.processInfo.systemUptime - started
                if duration >= 0.25 {
                    phase(String(format: "slow AX lookup id=%@ duration=%.3fs nodes=%d maxChildren=%d",
                                 id, duration, totalVisited, maximumChildCount))
                }
                return result
            }
            settle(0.1)
        }
        let duration = ProcessInfo.processInfo.systemUptime - started
        throw NSError(domain: "SearchWindowTests", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Missing \(id) after \(String(format: "%.3f", duration))s and \(totalVisited) AX nodes (max children \(maximumChildCount)). Fixture AX: \(sample.joined(separator: "; "))"])
    }

    @MainActor private static func labeledNode(in view: NSView, prefix: String) throws -> SearchWindowAXNode {
        var available: [SearchWindowAXNode] = []
        for _ in 0..<7 {
            available = nodes(in: view)
            if let result = available.first(where: { $0.label?.hasPrefix(prefix) == true && $0.press() }) {
                return result
            }
            settle(0.1)
        }
        throw NSError(domain: "SearchWindowTests", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "Missing pressable label beginning \(prefix). Labels: \(available.compactMap(\.label).prefix(100).joined(separator: "; "))"])
    }

    @MainActor private static func press(_ view: NSView, id: String) throws {
        let result = try node(in: view, id: id).press()
        try expect(result, "\(id) exposes a native press action")
    }

    @MainActor private static func sendKey(_ application: NSApplication, window: NSWindow,
                                           code: UInt16, characters: String,
                                           modifiers: NSEvent.ModifierFlags = []) {
        window.makeKey()
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers,
                                         timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: window.windowNumber, context: nil,
                                         characters: characters, charactersIgnoringModifiers: characters,
                                         isARepeat: false, keyCode: code)!
            application.sendEvent(event)
        }
        settle()
    }

    @MainActor private static func resize(_ window: NSWindow, hosting: NSView, width: CGFloat,
                                          height: CGFloat = boardHeight) {
        let size = NSSize(width: width, height: height)
        window.setContentSize(size)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        settle(0.28)
    }

    @MainActor private static func expectNativeHostingWidth(_ expected: CGFloat, window: NSWindow,
                                                             hosting: NSView, context: String) throws {
        hosting.layoutSubtreeIfNeeded()
        let hostingBounds = hosting.bounds.width
        let hostingFrame = hosting.frame.width
        let visible = hosting.visibleRect.width
        let content = window.contentLayoutRect.width
        let tolerance: CGFloat = 0.75
        try expect(hosting.window === window && window.contentView === hosting
                   && abs(hostingBounds - expected) <= tolerance
                   && abs(hostingFrame - expected) <= tolerance
                   && abs(visible - expected) <= tolerance
                   && abs(content - expected) <= tolerance,
                   "\(context) keeps the real native host at \(Int(expected)) points; bounds=\(hostingBounds), frame=\(hostingFrame), visible=\(visible), content=\(content)")
    }

    @MainActor private static func visibleColumnIDs(in hosting: NSView, window: NSWindow) -> [String] {
        let windowFrame = window.frame.insetBy(dx: -2, dy: -2)
        return nodes(in: hosting).compactMap { candidate -> (String, CGFloat)? in
            guard let id = candidate.identifier, id.hasPrefix("search-date-column-"),
                  candidate.frame.width > 1, candidate.frame.height > 1,
                  candidate.frame.intersects(windowFrame) else { return nil }
            return (String(id.dropFirst("search-date-column-".count)), candidate.frame.minX)
        }.reduce(into: [String: CGFloat]()) { values, pair in
            if values[pair.0] == nil { values[pair.0] = pair.1 }
        }.sorted { $0.value < $1.value }.map { $0.key }
    }

    @MainActor private static func nativeTables(in view: NSView) -> [NSTableView] {
        var result: [NSTableView] = []
        func visit(_ current: NSView) {
            if let table = current as? NSTableView, !table.isHiddenOrHasHiddenAncestor,
               table.visibleRect.width > 0, table.visibleRect.height > 0 { result.append(table) }
            for child in current.subviews { visit(child) }
        }
        visit(view)
        return result
    }

    @MainActor private static func viewportGeometry(in hosting: NSView) -> String {
        var values: [String] = []
        func visit(_ view: NSView) {
            let typeName = String(describing: type(of: view))
            if let table = view as? NSTableView {
                let frame = view.convert(view.bounds, to: hosting)
                let clip = table.enclosingScrollView?.contentView
                let clipDescription = clip.map {
                    "clipBounds=\(NSStringFromRect($0.bounds)), clipFrame=\(NSStringFromRect($0.convert($0.bounds, to: hosting))), postsBounds=\($0.postsBoundsChangedNotifications)"
                } ?? "clip=nil"
                values.append("\(typeName)#\(ObjectIdentifier(table)):\(NSStringFromRect(frame)), \(clipDescription)")
            } else if typeName == "Marker" {
                let frame = view.convert(view.bounds, to: hosting)
                let resolved = NativeListViewport.table(near: view).map { table -> String in
                    let tableFrame = table.convert(table.bounds, to: hosting)
                    let clip = table.enclosingScrollView?.contentView
                    let clipDescription = clip.map {
                        "clipBounds=\(NSStringFromRect($0.bounds)), clipFrame=\(NSStringFromRect($0.convert($0.bounds, to: hosting))), postsBounds=\($0.postsBoundsChangedNotifications)"
                    } ?? "clip=nil"
                    return "\(ObjectIdentifier(table)) frame=\(NSStringFromRect(tableFrame)), \(clipDescription)"
                } ?? "nil"
                values.append("\(typeName):\(NSStringFromRect(frame)) resolves=\(resolved)")
            }
            for child in view.subviews { visit(child) }
        }
        visit(hosting)
        return values.joined(separator: "; ")
    }

    @MainActor private static func editableTextView(in view: NSView) -> NSTextView? {
        if let text = view as? NSTextView, text.isEditable, !text.isHiddenOrHasHiddenAncestor { return text }
        for child in view.subviews {
            if let result = editableTextView(in: child) { return result }
        }
        return nil
    }

    @MainActor private static func popupButton(in view: NSView, containing title: String) -> NSPopUpButton? {
        nodes(in: view).compactMap { candidate in
            (candidate.object as? NSPopUpButton) ?? ((candidate.object as? NSCell)?.controlView as? NSPopUpButton)
        }.first { $0.window === view.window && $0.item(withTitle: title) != nil && !$0.isHiddenOrHasHiddenAncestor }
    }

    @MainActor private static func popover(containing id: String) -> (NSWindow, NSView)? {
        for window in NSApplication.shared.windows where window.isVisible {
            guard let content = window.contentView else { continue }
            if nodes(in: content).contains(where: { $0.identifier == id }) { return (window, content) }
        }
        return nil
    }

    @MainActor private static func responderDescription(_ responder: NSResponder?) -> String {
        guard let responder else { return "nil" }
        return "\(String(describing: type(of: responder)))#\(ObjectIdentifier(responder))"
    }

    @MainActor private static func matchingWindowDiagnostics(_ application: NSApplication,
                                                               id: String) -> String {
        application.windows.filter(\.isVisible).map { candidate in
            let matches = candidate.contentView.map { content in
                nodes(in: content).filter { $0.identifier == id }.map {
                    "\($0.identifier ?? "-")/\($0.label ?? "-")@\(NSStringFromRect($0.frame))"
                }
            } ?? []
            return "\(String(describing: type(of: candidate)))#\(candidate.windowNumber)"
                + " key=\(candidate.isKeyWindow) main=\(candidate.isMainWindow)"
                + " frame=\(NSStringFromRect(candidate.frame))"
                + " first=\(responderDescription(candidate.firstResponder)) matches=\(matches)"
        }.joined(separator: "; ")
    }

    @MainActor private static func snapshot(_ view: NSView, to url: URL, scale: Int = 2) throws -> [String: Any] {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let width = Int(view.bounds.width.rounded())
        let height = Int(view.bounds.height.rounded())
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width * scale,
                                            pixelsHigh: height * scale, bitsPerSample: 8,
                                            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw NSError(domain: "SearchWindowTests", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "Could not allocate Search evidence bitmap"])
        }
        bitmap.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "SearchWindowTests", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "Could not encode Search evidence bitmap"])
        }
        try png.write(to: url, options: .atomic)
        return ["file": url.lastPathComponent, "logicalWidth": width, "logicalHeight": height,
                "pixelWidth": bitmap.pixelsWide, "pixelHeight": bitmap.pixelsHigh, "pixelScale": scale]
    }

    @MainActor private static func fixturePNG() throws -> Data {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 10, pixelsHigh: 10,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                            isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw NSError(domain: "SearchWindowTests", code: 6,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create the local 10x10 photo fixture"])
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor(calibratedRed: 0.10, green: 0.52, blue: 0.48, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 10, height: 10).fill()
        NSColor(calibratedRed: 0.98, green: 0.76, blue: 0.25, alpha: 1).setFill()
        NSRect(x: 2, y: 2, width: 6, height: 6).fill()
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "SearchWindowTests", code: 7,
                          userInfo: [NSLocalizedDescriptionKey: "Could not encode the local photo fixture"])
        }
        return data
    }

    @MainActor private static func makeFixture(root: URL, defaults: UserDefaults) async throws -> SearchWindowFixture {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let today = calendar.startOfDay(for: Date()).addingTimeInterval(12 * 60 * 60)
        let days = (0..<6).map { calendar.date(byAdding: .day, value: -$0, to: today)! }
        var dated: [Capture] = []
        for index in 0..<6 {
            let receipt: CaptureReceiptContext = index.isMultiple(of: 2)
                ? .automatic(.automaticClipboard, sourceApplicationName: "Fictional Editor",
                             sourceApplicationBundleIdentifier: "example.fixture.editor")
                : .manual
            let capture = Capture(capturedAt: days[index].addingTimeInterval(TimeInterval(index * 61)),
                                  kind: index == 2 ? .task : .text,
                                  originalText: "\(commonQuery) fictional receipt \(index)",
                                  title: "Asterism planning record \(index) — a deliberately long fictional title that proves two-line search cards remain readable and do not hide the project",
                                  receipt: receipt)
            capture.projectName = index == 1 ? "Beta Studio" : "Alpha Project"
            capture.comment = index == 3 ? "Comment-only phrase copper aurora" : ""
            if index == 2 {
                var planning = TaskPlanning()
                planning.priority = .high
                planning.checklist = [TaskChecklistItem(text: "zephyr launch checklist"),
                                      TaskChecklistItem(text: "confirm fictional handoff", isCompleted: true)]
                capture.setTaskPlanning(planning)
            }
            dated.append(capture)
        }

        let stressDay = days[5]
        let stress = (0..<2_000).map { index -> Capture in
            let capture = Capture(capturedAt: stressDay.addingTimeInterval(TimeInterval(1_000 + index)),
                                  kind: .text,
                                  originalText: "\(viewportQuery) \(index)",
                                  title: String(format: "Viewport receipt %04d", index))
            capture.projectName = "Alpha Project"
            return capture
        }
        let columnViewportCaptures = (0..<3).flatMap { dayIndex in
            (0..<50).map { rowIndex -> Capture in
                let capture = Capture(capturedAt: days[dayIndex].addingTimeInterval(TimeInterval(5_000 + rowIndex * 30)),
                                      kind: .text,
                                      originalText: "\(columnViewportQuery) day \(dayIndex) row \(rowIndex)",
                                      title: "Independent column \(dayIndex) row \(rowIndex)")
                capture.projectName = "Alpha Project"
                return capture
            }
        }
        do {
            let repository = try CaptureRepository(root: root)
            try repository.save(dated + stress + columnViewportCaptures)
        }

        let store = try CaptureStore(root: root, repairArchiveOnOpen: false)
        let photo = try await store.importData(fixturePNG(), filename: "Fictional local color reference.png",
                                               at: days[1].addingTimeInterval(4_000),
                                               receipt: .manual, projectName: "Beta Studio")
        photo.title = "Beta Studio local photo — a long title whose only requested phrase comes from its local extracted text"
        photo.indexedText = "ultraviolet OCR only phrase global needle"
        photo.contentIndexState = "ready"
        photo.contentIndexVersion = ContentIndexService.currentVersion
        try store.save(captures: [photo])

        let settings = AutoCaptureSettings(defaults: defaults)
        let autoCapture = AutoCaptureService(settings: settings, input: InputService(store: store),
                                             pasteboardProvider: { fatalError("Search window QA must not read the clipboard") },
                                             sourceApplicationProvider: { nil })
        let previews = PreviewService(store: store, defaults: defaults)
        previews.process([photo])
        let state = AppState(store: store, previews: previews,
                             reminders: ReminderService(store: store, client: SearchWindowReminderClient()),
                             robotPlacement: RobotPlacementSettings(defaults: defaults),
                             autoCapture: autoCapture,
                             quickAccessSettings: QuickAccessSettings(defaults: defaults))
        state.libraryProject = "Alpha Project"
        state.openLibrary()
        state.openNewNote()
        state.back()
        state.newTaskDraft.destination = ComposerDestination(projectName: "Alpha Project")
        try state.workspace.setSnippetName("studio codename marigold", for: dated[4].id)
        try state.workspace.setScratchpad(text: "nebula notebook observations for the fictional Alpha launch",
                                          project: "Alpha Project")
        guard let note = state.workspace.scratchpads.first(where: { $0.projectName == "Alpha Project" }) else {
            throw NSError(domain: "SearchWindowTests", code: 8,
                          userInfo: [NSLocalizedDescriptionKey: "The isolated project note was not persisted"])
        }
        let theme = ThemeSettings(defaults: defaults, systemDarkMode: false)
        for _ in 0..<15 where photo.previewState != "ready" { settle(0.08) }
        return SearchWindowFixture(root: root, defaults: defaults, store: store, previews: previews,
                                   autoCapture: autoCapture, state: state, theme: theme,
                                   datedCaptures: dated, task: dated[2], photo: photo, note: note,
                                   stressDay: stressDay)
    }

    @MainActor private static func checkGlobalMatching(_ fixture: SearchWindowFixture) throws {
        let state = fixture.state
        state.updateGlobalSearch("ultraviolet OCR only phrase")
        try expect(state.route == .search && state.searchProject == nil && !state.searchUnfiledOnly,
                   "A search opened from Alpha is global")
        try expect(state.searchDateGroups.flatMap(\.captureEntries).map(\.id) == [fixture.photo.id],
                   "Local extracted text finds the Beta photo even while Alpha remains the Library destination")
        try expect(state.libraryProject == "Alpha Project"
                   && state.newNoteProject == "Alpha Project"
                   && state.newTaskDraft.destination == ComposerDestination(projectName: "Alpha Project"),
                   "Global Search leaves Library and composer destinations unchanged")

        state.updateGlobalSearch("zephyr launch checklist")
        try expect(state.searchDateGroups.flatMap(\.captureEntries).contains(where: { $0.id == fixture.task.id }),
                   "Task checklist text is globally searchable")
        state.updateGlobalSearch("studio codename marigold")
        try expect(state.searchDateGroups.flatMap(\.captureEntries).contains(where: { $0.id == fixture.datedCaptures[4].id }),
                   "A saved snippet alias is globally searchable")
        state.updateGlobalSearch("")
        try expect(state.searchDateGroups.reduce(0) { $0 + $1.matchCount } == state.store.captures.count + 1,
                   "An empty Search deliberately browses every active capture plus the project note")
        state.updateGlobalSearch("Asterism planning record")
        try expect(state.searchDateGroups.flatMap(\.captureEntries).count == 6,
                   "Mixed long titles remain searchable across all six receipt dates")
    }

    @MainActor private static func checkProjectSearchEntry(_ fixture: SearchWindowFixture,
                                                            hosting: NSView, window: NSWindow) async throws {
        let state = fixture.state
        phase("entry.step prepare scoped Search state")
        state.updateGlobalSearch("project entry refinement seed")
        state.selectSearchProject("Alpha Project")
        state.filter = .tasks
        state.searchSource = "Fictional Editor"
        state.setSearchDay(fixture.datedCaptures[2].capturedAt)
        state.showSearchContext = true
        state.workspace.mode = .collection
        state.libraryProject = "Alpha Project"
        phase("entry.step mount Alpha Project workspace")
        state.openLibrary()
        phase("entry.step resize Project workspace to 736")
        resize(window, hosting: hosting, width: 736)
        phase("entry.step await Project workspace mount")
        try await waitForNativeUI(100)
        phase("entry.step lookup project-workspace")
        try expect((try node(in: hosting, id: "project-workspace")).frame.width > 0,
                   "The Alpha project workspace is mounted for its native Search entry")
        let noteDestination = state.newNoteProject
        let taskDestination = state.newTaskDraft.destination
        phase("entry.step press project-search")
        try press(hosting, id: "project-search")
        phase("entry.step project-search returned; await Search mount")
        try await waitForNativeUI()
        phase("entry.step assert global Search state")
        try expect(state.route == .search && state.searchProject == nil && !state.searchUnfiledOnly
                   && state.filter == .all && state.searchSource == nil && state.searchScope == .all
                   && !state.showSearchContext,
                   "Project Search opens a fresh global Search instead of inheriting project refinements")
        try expect(state.libraryProject == "Alpha Project" && state.workspace.selectedProject == "Alpha Project"
                   && state.newNoteProject == noteDestination && state.newTaskDraft.destination == taskDestination,
                   "Project Search keeps the Alpha Library and capture destinations unchanged")
    }

    @MainActor private static func checkPagingAndResponsiveColumns(_ fixture: SearchWindowFixture,
                                                                    hosting: NSView, window: NSWindow) throws {
        let state = fixture.state
        state.updateGlobalSearch(commonQuery)
        state.searchDateAnchor = nil
        state.searchSelectedResultID = nil
        resize(window, hosting: hosting, width: 380)
        try expectNativeHostingWidth(380, window: window, hosting: hosting, context: "Compact Search")
        let groups = state.searchDateGroups
        try expect(groups.count == 6 && groups.map(\.day) == groups.map(\.day).sorted(by: >),
                   "Date board groups six real saved days newest first")
        let newest = groups[0].day
        if state.searchDateAnchor == nil { state.searchDateAnchor = newest; settle() }
        try expect(visibleColumnIDs(in: hosting, window: window) == [newest],
                   "A 380-point window presents one real date column")
        resize(window, hosting: hosting, width: 320)
        try expectNativeHostingWidth(320, window: window, hosting: hosting, context: "Minimum-width Search")
        try expect(visibleColumnIDs(in: hosting, window: window).count == 1,
                   "The Search content remains one bounded column at the optional 320-point stress width")
        resize(window, hosting: hosting, width: 380)
        try expectNativeHostingWidth(380, window: window, hosting: hosting, context: "Restored compact Search")

        try press(hosting, id: "search-older-dates")
        let pagedAnchor = groups[1].day
        try expect(state.searchDateAnchor == pagedAnchor, "Older paging advances by the visible one-column page")
        resize(window, hosting: hosting, width: 736)
        try expectNativeHostingWidth(736, window: window, hosting: hosting, context: "Two-column Search")
        try expect(state.searchDateAnchor == pagedAnchor
                   && visibleColumnIDs(in: hosting, window: window) == Array(groups[1...2].map(\.day)),
                   "A 736-point resize keeps the exact anchor and presents two dates")
        let twoTables = nativeTables(in: hosting)
        try expect(twoTables.count == 2 && Set(twoTables.map { ObjectIdentifier($0) }).count == 2,
                   "Each visible two-column date owns an independent native List")
        resize(window, hosting: hosting, width: 1_060)
        try expectNativeHostingWidth(1_060, window: window, hosting: hosting, context: "Three-column Search")
        try expect(state.searchDateAnchor == pagedAnchor
                   && visibleColumnIDs(in: hosting, window: window) == Array(groups[1...3].map(\.day)),
                   "A 1060-point resize keeps the exact anchor and presents three dates")
        let threeTables = nativeTables(in: hosting)
        try expect(threeTables.count == 3 && Set(threeTables.map { ObjectIdentifier($0) }).count == 3,
                   "All three visible date columns bind to distinct recycled Lists")
        resize(window, hosting: hosting, width: 380)
        try expectNativeHostingWidth(380, window: window, hosting: hosting, context: "Shrunk Search")
        try expect(state.searchDateAnchor == pagedAnchor
                   && visibleColumnIDs(in: hosting, window: window) == [pagedAnchor],
                   "Shrinking does not snap the date anchor to a page boundary")
        try press(hosting, id: "search-newer-dates")
        try expect(state.searchDateAnchor == newest, "Newer paging returns to the newest date")
    }

    @MainActor private static func checkCaptureRouting(_ fixture: SearchWindowFixture,
                                                        hosting: NSView, window: NSWindow) async throws {
        let state = fixture.state
        resize(window, hosting: hosting, width: 380)
        state.updateGlobalSearch(commonQuery)
        state.searchDateAnchor = state.searchDateGroups[0].day
        state.searchSelectedResultID = nil
        try await waitForNativeUI()
        let capture = fixture.datedCaptures[0]
        let query = state.query
        let anchor = state.searchDateAnchor
        try press(hosting, id: "search-select-\(capture.id.uuidString)")
        try await waitForNativeUI()
        try expect(state.route == .detail && state.selectedCapture?.id == capture.id,
                   "Selecting a compact Search card opens capture details")
        try press(hosting, id: "board-back")
        try await waitForNativeUI()
        try expect(state.route == .search && state.query == query && state.searchDateAnchor == anchor
                   && state.searchSelectedResultID == "capture:\(capture.id.uuidString)",
                   "Back restores the compact Search query, date and selected result")

        state.searchSelectedResultID = nil
        resize(window, hosting: hosting, width: 1_060)
        try await waitForNativeUI()
        try press(hosting, id: "search-select-\(capture.id.uuidString)")
        try await waitForNativeUI()
        try expect(state.route == .search && state.searchSelectedResultID == "capture:\(capture.id.uuidString)",
                   "Selecting an expanded card stays in Search")
        try expect((try? node(in: hosting, id: "search-preview").frame.width) ?? 0 > 200,
                   "Expanded Search selection shows the production inspector")
        try expect(state.libraryProject == "Alpha Project"
                   && state.newNoteProject == "Alpha Project"
                   && state.newTaskDraft.destination == ComposerDestination(projectName: "Alpha Project"),
                   "Capture preview does not replace the Library or composer destination")
    }

    @MainActor private static func checkIndependentColumnViewports(_ fixture: SearchWindowFixture,
                                                                    hosting: NSView, window: NSWindow) async throws {
        let state = fixture.state
        resize(window, hosting: hosting, width: 1_060)
        state.updateGlobalSearch(columnViewportQuery)
        let groups = state.searchDateGroups
        try expect(groups.count == 3 && groups.allSatisfy { $0.items.count == 50 },
                   "The independent viewport fixture has fifty rows on each of three dates")
        state.searchDateAnchor = groups[0].day
        state.searchColumnScrollIDs.removeAll()
        try await waitForNativeUI(400)
        let tables = nativeTables(in: hosting).sorted {
            $0.convert($0.bounds, to: hosting).minX < $1.convert($1.bounds, to: hosting).minX
        }
        try expect(tables.count == 3, "Three date columns expose three native scroll tables")
        var remembered: [String: String] = [:]
        for index in groups.indices {
            let table = tables[index]
            let targetRows = [12, 25, 38]
            table.scrollRowToVisible(targetRows[index])
            try await waitForNativeUI(400)
            let firstVisibleRow = table.rows(in: table.visibleRect).location
            try expect(groups[index].items.indices.contains(firstVisibleRow),
                       "Column \(index + 1) reports a valid first visible logical row")
            let expectedID = groups[index].items[firstVisibleRow].id
            var storedID = state.searchColumnScrollIDs[groups[index].day]
            for _ in 0..<8 where storedID != expectedID {
                try await waitForNativeUI(80)
                storedID = state.searchColumnScrollIDs[groups[index].day]
            }
            let storedBeforeManualPost = storedID
            var storedAfterManualPost: String?
            if storedBeforeManualPost != expectedID, let clip = table.enclosingScrollView?.contentView {
                NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: clip)
                try await waitForNativeUI(180)
                storedAfterManualPost = state.searchColumnScrollIDs[groups[index].day]
            }
            try expect(storedBeforeManualPost == expectedID,
                       "Column \(index + 1) remembers the row visible in its own table; expected \(expectedID), stored before manual notification \(String(describing: storedBeforeManualPost)), stored after manual notification \(String(describing: storedAfterManualPost)), all stored IDs \(state.searchColumnScrollIDs), native geometry \(viewportGeometry(in: hosting))")
            for (day, id) in remembered {
                try expect(state.searchColumnScrollIDs[day] == id,
                           "Scrolling column \(index + 1) does not overwrite another date's viewport")
            }
            remembered[groups[index].day] = expectedID
        }
        try expect(Set(remembered.values).count == 3,
                   "Three date columns retain three independent presentation IDs")
    }

    /// A bounds callback deliberately defers its AppState write until the next
    /// main-queue turn. A query refinement in that gap must invalidate the
    /// pending viewport generation instead of restoring stale Search position.
    @MainActor private static func checkDeferredViewportResetRace(_ fixture: SearchWindowFixture) async throws {
        let state = fixture.state
        state.updateGlobalSearch("viewport deferred reset seed")
        let day = "2099-12-31"
        let rowIDs = ["capture:viewport-race-0", "capture:viewport-race-1"]

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 240),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 240))
        let dataSource = SearchWindowTableDataSource(count: rowIDs.count)
        let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 360, height: 240))
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("viewport-race-column"))
        column.width = 360
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 44
        table.dataSource = dataSource
        table.reloadData()
        let scroll = NSScrollView(frame: root.bounds)
        scroll.documentView = table
        root.addSubview(scroll)
        let marker = SearchColumnViewport.Marker(frame: root.bounds)
        root.addSubview(marker)
        panel.contentView = root
        panel.orderFront(nil)

        let coordinator = SearchColumnViewport.Coordinator(state: state, day: day)
        coordinator.rowIDs = rowIDs
        defer {
            coordinator.stop()
            panel.orderOut(nil)
            panel.contentView = nil
            panel.close()
            _ = dataSource // Keep the weak NSTableView data source alive through teardown.
        }

        root.layoutSubtreeIfNeeded()
        scroll.layoutSubtreeIfNeeded()
        coordinator.connect(from: marker)
        try await waitForNativeUI(100)
        try expect(scroll.contentView.postsBoundsChangedNotifications,
                   "The isolated native viewport installs its bounds observer")

        state.searchColumnScrollIDs.removeAll()
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        try await waitForNativeUI()
        try expect(state.searchColumnScrollIDs[day] == rowIDs[0],
                   "The viewport race fixture proves its deferred native row write is active")

        state.searchColumnScrollIDs.removeAll()
        let revision = state.searchPositionRevision
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        state.query = "viewport deferred reset replacement"
        try expect(state.searchPositionRevision == revision &+ 1 && state.searchColumnScrollIDs.isEmpty,
                   "Changing Search words synchronously clears position and advances its generation")
        try await waitForNativeUI()
        try expect(state.searchColumnScrollIDs.isEmpty,
                   "A deferred native viewport callback cannot repopulate position after the query reset")
    }

    @MainActor private static func checkNoteRouting(_ fixture: SearchWindowFixture,
                                                     hosting: NSView, window: NSWindow) async throws {
        let state = fixture.state
        resize(window, hosting: hosting, width: 736)
        state.updateGlobalSearch("nebula notebook")
        state.searchDateAnchor = state.searchDateGroups.first?.day
        try await waitForNativeUI()
        let query = state.query
        let anchor = state.searchDateAnchor
        _ = try labeledNode(in: hosting, prefix: "Open Alpha Project notes")
        try await waitForNativeUI()
        try expect(state.route == .searchNote && state.selectedSearchNote?.projectName == "Alpha Project",
                   "A project-note result opens the editable Search note route")
        try expect((try node(in: hosting, id: "workspace-scratchpad")).frame.height >= 100,
                   "Search notes use the native autosaving scratchpad editor")
        guard let editor = editableTextView(in: hosting) else {
            throw NSError(domain: "SearchWindowTests", code: 9,
                          userInfo: [NSLocalizedDescriptionKey: "Search note has no native editable text view"])
        }
        let edited = "nebula notebook observations — saved through the native editor"
        _ = window.makeFirstResponder(editor)
        editor.insertText(edited, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        try await waitForNativeUI(100)
        try expect(state.workspace.scratchpad(project: "Alpha Project") == edited,
                   "Typing in the Search note editor autosaves to the displayed note context")
        try press(hosting, id: "board-back")
        try await waitForNativeUI()
        try expect(state.route == .search && state.query == query && state.searchDateAnchor == anchor
                   && state.searchSelectedResultID == "note:project:Alpha Project",
                   "Back returns to the same note result and date position")
        try expect(state.libraryProject == "Alpha Project"
                   && state.newNoteProject == "Alpha Project"
                   && state.newTaskDraft.destination == ComposerDestination(projectName: "Alpha Project"),
                   "Editing a Search note leaves capture and composer destinations unchanged")
    }

    @MainActor private static func checkFilterKeyboard(_ filterPopover: (NSWindow, NSView),
                                                        hosting: NSView,
                                                        application: NSApplication) async throws {
        application.activate(ignoringOtherApps: true)
        filterPopover.0.makeKey()
        guard let firstFilter = popupButton(in: filterPopover.1, containing: "All projects") else {
            throw NSError(domain: "SearchWindowTests", code: 16,
                          userInfo: [NSLocalizedDescriptionKey: "Search filters expose no native Project popup for keyboard focus"])
        }
        try expect(filterPopover.0.makeFirstResponder(firstFilter),
                   "Keyboard focus enters the native Project filter")
        try await waitForNativeUI()
        let chosenWindow = "\(String(describing: type(of: filterPopover.0)))#\(filterPopover.0.windowNumber)"
        let keyBeforeTab = application.keyWindow.map { "\(String(describing: type(of: $0)))#\($0.windowNumber)" } ?? "nil"
        let beforeTab = filterPopover.0.firstResponder
        let responderWindow = (beforeTab as? NSView)?.window
        let keyWindow = application.keyWindow
        let focusDiagnostics = "active=\(application.isActive), chosen=\(chosenWindow)"
            + " canBecomeKey=\(filterPopover.0.canBecomeKey), isKey=\(filterPopover.0.isKeyWindow),"
            + " key=\(keyBeforeTab), keyCanBecome=\(keyWindow?.canBecomeKey.description ?? "nil"),"
            + " responder=\(responderDescription(beforeTab)),"
            + " responderWindow=\(responderWindow.map { "\(String(describing: type(of: $0)))#\($0.windowNumber)" } ?? "nil"),"
            + " parent=\(filterPopover.0.parent.map { "\(String(describing: type(of: $0)))#\($0.windowNumber)" } ?? "nil")"
        try expect(application.isActive && keyWindow != nil && responderWindow === filterPopover.0,
                   "Search filter keyboard checks have active native focus. \(focusDiagnostics)")
        let fullKeyboardAccess = application.isFullKeyboardAccessEnabled
        let nextValidKeyView = firstFilter.nextValidKeyView
        sendKey(application, window: keyWindow!, code: 48, characters: "\t")
        let afterTab = filterPopover.0.firstResponder
        let keyAfterTab = application.keyWindow.map { "\(String(describing: type(of: $0)))#\($0.windowNumber)" } ?? "nil"
        let tabDiagnostics = "\(focusDiagnostics), fullKeyboardAccess=\(fullKeyboardAccess),"
            + " nextKeyView=\(responderDescription(firstFilter.nextKeyView)),"
            + " nextValidKeyView=\(responderDescription(nextValidKeyView)),"
            + " afterTab=\(responderDescription(afterTab)), keyAfterTab=\(keyAfterTab),"
            + " keyResponder=\(responderDescription(application.keyWindow?.firstResponder)),"
            + " visible windows=[\(matchingWindowDiagnostics(application, id: "search-filters-popover"))]"
        if fullKeyboardAccess {
            try expect(afterTab != nil && afterTab !== beforeTab && (afterTab as? NSView)?.window === filterPopover.0,
                       "Tab advances between native controls inside Search filters. \(tabDiagnostics)")
        } else {
            // AppKit excludes popup/button controls from the Tab loop when the
            // user's Keyboard Navigation preference is off. Verify that native
            // behavior without changing the preference or fabricating a loop.
            try expect(!firstFilter.canBecomeKeyView && nextValidKeyView == nil
                       && afterTab === beforeTab && (afterTab as? NSView)?.window === filterPopover.0
                       && popover(containing: "search-filters-popover")?.0 === filterPopover.0,
                       "Tab respects disabled Keyboard Navigation and retains Search filter focus. \(tabDiagnostics)")
        }
        sendKey(application, window: application.keyWindow ?? keyWindow!, code: 53, characters: "\u{1b}")
        try await waitForNativeUI()
        let afterEscape = filterPopover.0.firstResponder
        let keyAfterEscape = application.keyWindow.map { "\(String(describing: type(of: $0)))#\($0.windowNumber)" } ?? "nil"
        var stillPresented = popover(containing: "search-filters-popover")
        for _ in 0..<6 where stillPresented != nil {
            try await waitForNativeUI()
            stillPresented = popover(containing: "search-filters-popover")
        }
        var escapeDiagnostics = ""
        if let stillPresented {
            let diagnosticDirectory = evidenceRoot().appendingPathComponent("diagnostics", isDirectory: true)
            try? FileManager.default.createDirectory(at: diagnosticDirectory, withIntermediateDirectories: true)
            let popoverScreenshot = diagnosticDirectory.appendingPathComponent("search-filter-escape-selected-window@2x.png")
            let boardScreenshot = diagnosticDirectory.appendingPathComponent("search-filter-escape-board@2x.png")
            var screenshotResults: [String] = []
            do {
                _ = try snapshot(filterPopover.1, to: popoverScreenshot)
                screenshotResults.append(popoverScreenshot.path)
            } catch { screenshotResults.append("selected window failed: \(error)") }
            do {
                _ = try snapshot(hosting, to: boardScreenshot)
                screenshotResults.append(boardScreenshot.path)
            } catch { screenshotResults.append("board failed: \(error)") }
            let stillNodes = nodes(in: stillPresented.1).filter {
                $0.identifier != nil || $0.label != nil
            }.prefix(80).map {
                "\($0.identifier ?? "-")/\($0.label ?? "-")@\(NSStringFromRect($0.frame))"
            }.joined(separator: "; ")
            escapeDiagnostics = " chosen=\(chosenWindow), key before Tab=\(keyBeforeTab), after Tab=\(keyAfterTab),"
                + " after Escape=\(keyAfterEscape), responders before=\(responderDescription(beforeTab)),"
                + " afterTab=\(responderDescription(afterTab)), afterEscape=\(responderDescription(afterEscape)),"
                + " still=\(String(describing: type(of: stillPresented.0)))#\(stillPresented.0.windowNumber),"
                + " visible windows=[\(matchingWindowDiagnostics(application, id: "search-filters-popover"))],"
                + " still AX=[\(stillNodes)], screenshots=\(screenshotResults)"
        }
        try expect(stillPresented == nil,
                   "Escape closes the Search filter popover.\(escapeDiagnostics)")

        try press(hosting, id: "search-filters")
        try await waitForNativeUI(100)
        guard let returnPopover = popover(containing: "search-filters-popover"),
              let returnFilter = popupButton(in: returnPopover.1, containing: "All projects") else {
            throw NSError(domain: "SearchWindowTests", code: 17,
                          userInfo: [NSLocalizedDescriptionKey: "Search filters did not reopen for the native Return action"])
        }
        returnPopover.0.makeKey()
        try expect(returnPopover.0.makeFirstResponder(returnFilter),
                   "Keyboard focus reenters the native Project filter before Return")
        try await waitForNativeUI()
        try expect(application.isActive && (returnPopover.0.firstResponder as? NSView)?.window === returnPopover.0,
                   "Return starts with active native focus inside Search filters")
        sendKey(application, window: application.keyWindow ?? returnPopover.0, code: 36, characters: "\r")
        try await waitForNativeUI()
        var returnStillPresented = popover(containing: "search-filters-popover")
        for _ in 0..<6 where returnStillPresented != nil {
            try await waitForNativeUI()
            returnStillPresented = popover(containing: "search-filters-popover")
        }
        try expect(returnStillPresented == nil,
                   "Return activates the native Done button in Search filters. "
                   + matchingWindowDiagnostics(application, id: "search-filters-popover"))
        keyboardNavigationVerification = fullKeyboardAccess
            ? "Tab traversed native controls with Keyboard Navigation enabled"
            : "Tab retained filter focus with Keyboard Navigation disabled"
    }

    @MainActor private static func closeFilterUsingDone(_ filterPopover: (NSWindow, NSView)) async throws {
        _ = try labeledNode(in: filterPopover.1, prefix: "Done")
        try await waitForNativeUI()
        var stillPresented = popover(containing: "search-filters-popover")
        for _ in 0..<6 where stillPresented != nil {
            try await waitForNativeUI()
            stillPresented = popover(containing: "search-filters-popover")
        }
        try expect(stillPresented == nil, "The native Done action closes Search filters")
    }

    @MainActor private static func checkFilters(_ fixture: SearchWindowFixture, hosting: NSView,
                                                 window: NSWindow, application: NSApplication) async throws {
        let state = fixture.state
        resize(window, hosting: hosting, width: 736)
        state.updateGlobalSearch(commonQuery)
        try await waitForNativeUI()
        try press(hosting, id: "search-filters")
        try await waitForNativeUI(100)
        var filterPopover: (NSWindow, NSView)?
        for _ in 0..<8 where filterPopover == nil {
            filterPopover = popover(containing: "search-filters-popover")
            try await waitForNativeUI()
        }
        guard let filterPopover else {
            throw NSError(domain: "SearchWindowTests", code: 10,
                          userInfo: [NSLocalizedDescriptionKey: "The production Search filter popover did not open"])
        }
        for id in ["search-project-picker", "search-type-picker", "search-source-picker", "search-date-mode"] {
            try expect((try node(in: filterPopover.1, id: id)).frame.width > 0,
                       "\(id) is present in the native Search filter popover")
        }
        if skipsKeyboardVerification { try await closeFilterUsingDone(filterPopover) }
        else { try await checkFilterKeyboard(filterPopover, hosting: hosting, application: application) }

        state.selectSearchProject("Alpha Project")
        state.filter = .tasks
        state.searchSource = "Fictional Editor"
        state.setSearchDay(fixture.datedCaptures[2].capturedAt)
        state.showSearchContext = true
        try await waitForNativeUI()
        for id in ["search-chip-project", "search-chip-type", "search-chip-source", "search-chip-date"] {
            try expect((try node(in: hosting, id: id)).frame.width > 0, "\(id) is a visible removable refinement chip")
        }
        let query = state.query
        try press(hosting, id: "search-clear-filters")
        try await waitForNativeUI()
        try expect(state.query == query && state.searchProject == nil && !state.searchUnfiledOnly
                   && state.filter == .all && state.searchSource == nil && state.searchScope == .all
                   && !state.showSearchContext,
                   "Clear filters retains the words and clears every visible refinement")
    }

    @MainActor private static func checkRecyclingAndLiveInsertion(_ fixture: SearchWindowFixture,
                                                                   hosting: NSView, window: NSWindow) async throws {
        let state = fixture.state
        phase("recycling.step mount 2000-row Search query")
        resize(window, hosting: hosting, width: 380)
        state.updateGlobalSearch(viewportQuery)
        guard let group = state.searchDateGroups.first else {
            throw NSError(domain: "SearchWindowTests", code: 11,
                          userInfo: [NSLocalizedDescriptionKey: "The 2000-row viewport fixture did not match"])
        }
        state.searchDateAnchor = group.day
        phase("recycling.step await initial List mount")
        try await waitForNativeUI(400)
        phase("recycling.step inspect native table and realized rows")
        let tables = nativeTables(in: hosting)
        try expect(tables.count == 1 && tables[0].numberOfRows == 2_000,
                   "A 2000-result day uses one native List with all logical rows")
        let table = tables[0]
        var realized: [(NSTableRowView, Int)] = []
        table.enumerateAvailableRowViews { row, index in realized.append((row, index)) }
        try expect(!realized.isEmpty && realized.count < 80,
                   "The native List realizes a bounded set of rows (\(realized.count) of 2000)")
        var visibleAXResults = 0
        for (row, _) in realized where row.frame.intersects(table.visibleRect) {
            visibleAXResults += nodes(in: row, maximumDepth: 25).filter { $0.identifier?.hasPrefix("search-result-") == true }.count
        }
        try expect(visibleAXResults < 80, "Visible-row accessibility remains bounded without materializing the archive")

        phase("recycling.step scroll native table to row 1000")
        table.scrollRowToVisible(1_000)
        phase("recycling.step await scrolled viewport memory")
        try await waitForNativeUI(550)
        var remembered = state.searchColumnScrollIDs[group.day]
        for _ in 0..<8 where remembered == nil {
            try await waitForNativeUI(100)
            remembered = state.searchColumnScrollIDs[group.day]
        }
        guard let remembered else {
            throw NSError(domain: "SearchWindowTests", code: 12,
                          userInfo: [NSLocalizedDescriptionKey: "SearchColumnViewport did not remember the first visible recycled row"])
        }
        func viewportDiagnostic(_ phaseName: String) {
            let visible = table.rows(in: table.visibleRect)
            let current = state.searchDateGroups.first { $0.day == group.day }
            let rememberedRow = current?.items.firstIndex { $0.id == remembered }
            let viewport = state.searchColumnViewports[group.day]
            phase("viewport diagnostic \(phaseName): visible=\(visible), rememberedRow=\(String(describing: rememberedRow)), bounds=\(table.visibleRect), stored=\(String(describing: viewport))")
        }
        viewportDiagnostic("before insertion")
        state.searchSelectedResultID = remembered
        let anchor = state.searchDateAnchor
        phase("recycling.step save live matching capture")
        _ = try fixture.store.capture(text: "\(viewportQuery) live insertion", at: fixture.stressDay.addingTimeInterval(10_000),
                                      projectName: "Alpha Project")
        phase("recycling.step live save returned; await List update")
        try await waitForNativeUI(650)
        viewportDiagnostic("after insertion")
        phase("recycling.step assert live List position and row count")
        try expect(state.searchDateAnchor == anchor && state.searchSelectedResultID == remembered,
                   "A live matching save keeps the date anchor and selected presentation ID")
        try expect(state.searchColumnScrollIDs[group.day] == remembered,
                   "A live matching save keeps the visible recycled row anchor")
        try expect(nativeTables(in: hosting).first?.numberOfRows == 2_001,
                   "The held viewport receives the new matching result")

        let capturePrefix = "capture:"
        guard remembered.hasPrefix(capturePrefix),
              let rememberedID = UUID(uuidString: String(remembered.dropFirst(capturePrefix.count))) else {
            throw NSError(domain: "SearchWindowTests", code: 13,
                          userInfo: [NSLocalizedDescriptionKey: "The remembered viewport row is not a capture presentation ID"])
        }
        phase("recycling.step press deep visible Search result")
        try press(hosting, id: "search-select-\(rememberedID.uuidString)")
        phase("recycling.step detail press returned; await detail route")
        try await waitForNativeUI()
        try expect(state.route == .detail, "A visible card in the deep recycled viewport opens compact details")
        phase("recycling.step press Back from deep detail")
        try press(hosting, id: "board-back")
        phase("recycling.step Back returned; await restored List")
        try await waitForNativeUI(450)
        phase("recycling.step inspect restored native viewport")
        try expect(state.route == .search && state.searchColumnScrollIDs[group.day] == remembered,
                   "Back from a deeply scrolled result preserves the exact stored row ID")
        guard let restoredGroup = state.searchDateGroups.first(where: { $0.day == group.day }),
              let restoredTable = nativeTables(in: hosting).first else {
            throw NSError(domain: "SearchWindowTests", code: 14,
                          userInfo: [NSLocalizedDescriptionKey: "The recycled date column did not return after capture details"])
        }
        let restoredFirstRow = restoredTable.rows(in: restoredTable.visibleRect).location
        try expect(restoredGroup.items.indices.contains(restoredFirstRow)
                   && restoredGroup.items[restoredFirstRow].id == remembered,
                   "The native List restores the remembered result as its first visible row")
    }

    @MainActor private static func benchmarkSearch(root: URL, defaults: UserDefaults) throws -> [String: Any] {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let day = calendar.startOfDay(for: Date()).addingTimeInterval(10 * 60 * 60)
        let captures = (0..<5_000).map { index -> Capture in
            let text = index.isMultiple(of: 17) ? "perf beacon matching record \(index)" : "fictional archive record \(index)"
            let capture = Capture(capturedAt: day.addingTimeInterval(TimeInterval(index % 3_000)),
                                  kind: .text, originalText: text, title: "Performance fixture \(index)")
            capture.projectName = index.isMultiple(of: 3) ? "Alpha Project" : "Beta Studio"
            return capture
        }
        let seedStart = ProcessInfo.processInfo.systemUptime
        do { try CaptureRepository(root: root).save(captures) }
        let seedSeconds = ProcessInfo.processInfo.systemUptime - seedStart
        let store = try CaptureStore(root: root, repairArchiveOnOpen: false)
        let previews = PreviewService(store: store, defaults: defaults)
        let autoCapture = AutoCaptureService(settings: AutoCaptureSettings(defaults: defaults),
                                             input: InputService(store: store),
                                             pasteboardProvider: { fatalError("Search benchmark must not read the clipboard") },
                                             sourceApplicationProvider: { nil })
        defer { autoCapture.shutdown(); previews.shutdown() }
        let state = AppState(store: store, previews: previews,
                             reminders: ReminderService(store: store, client: SearchWindowReminderClient()),
                             robotPlacement: RobotPlacementSettings(defaults: defaults),
                             autoCapture: autoCapture,
                             quickAccessSettings: QuickAccessSettings(defaults: defaults))
        defer { state.shutdownNotificationPresentation(); store.cancelArchiveRepair() }
        state.updateGlobalSearch("perf beacon")
        let coldStart = ProcessInfo.processInfo.systemUptime
        let coldGroups = state.searchDateGroups
        let coldSeconds = ProcessInfo.processInfo.systemUptime - coldStart
        let warmStart = ProcessInfo.processInfo.systemUptime
        var checksum = 0
        for _ in 0..<500 { checksum += state.searchDateGroups.count }
        let warmSeconds = ProcessInfo.processInfo.systemUptime - warmStart
        let matches = coldGroups.reduce(0) { $0 + $1.matchCount }
        try expect(store.captures.count == 5_000 && matches == 295 && checksum == coldGroups.count * 500,
                   "The 5000-record benchmark returns every expected match and 500 stable cached reads")
        try expect(coldSeconds < 12 && warmSeconds < 3,
                   "Cold and cached Search stay within a generous native QA budget")
        return ["records": 5_000, "matches": matches, "repositoryBatchSeconds": seedSeconds,
                "coldSearchSeconds": coldSeconds, "cachedReadCount": 500,
                "cached500Seconds": warmSeconds,
                "cachedAverageMicroseconds": warmSeconds * 1_000_000 / 500]
    }

    @MainActor private static func renderEvidence(_ fixture: SearchWindowFixture, hosting: NSView,
                                                   window: NSWindow, renders: URL) async throws -> [[String: Any]] {
        var records: [[String: Any]] = []
        let state = fixture.state
        for appearance in ["light", "dark"] {
            fixture.theme.setDarkMode(appearance == "dark")
            state.updateGlobalSearch(commonQuery)
            state.searchDateAnchor = state.searchDateGroups.first?.day
            state.searchSelectedResultID = nil
            for width in [320, 380, 736, 1_060] {
                resize(window, hosting: hosting, width: CGFloat(width))
                try await waitForNativeUI()
                try expectNativeHostingWidth(CGFloat(width), window: window, hosting: hosting,
                                             context: "\(appearance.capitalized) evidence render")
                let name = "global-date-search-\(appearance)-\(width)x\(Int(boardHeight))@2x.png"
                var record = try snapshot(hosting, to: renders.appendingPathComponent(name))
                record["appearance"] = appearance
                record["query"] = commonQuery
                record["visibleDates"] = visibleColumnIDs(in: hosting, window: window)
                records.append(record)
            }
            resize(window, hosting: hosting, width: 380, height: 520)
            try await waitForNativeUI()
            let shortName = "global-date-search-compact-short-\(appearance)-380x520@2x.png"
            var shortRecord = try snapshot(hosting, to: renders.appendingPathComponent(shortName))
            shortRecord["appearance"] = appearance
            shortRecord["query"] = commonQuery
            shortRecord["visibleDates"] = visibleColumnIDs(in: hosting, window: window)
            records.append(shortRecord)

            state.searchSelectedResultID = "capture:" + fixture.datedCaptures[0].id.uuidString
            resize(window, hosting: hosting, width: 1_060)
            try await waitForNativeUI(100)
            let previewName = "global-date-search-selected-preview-\(appearance)-1060x\(Int(boardHeight))@2x.png"
            var previewRecord = try snapshot(hosting, to: renders.appendingPathComponent(previewName))
            previewRecord["appearance"] = appearance
            previewRecord["query"] = commonQuery
            previewRecord["selectedResult"] = state.searchSelectedResultID ?? ""
            records.append(previewRecord)

            state.searchSelectedResultID = nil
            resize(window, hosting: hosting, width: 736)
            try await waitForNativeUI()
            try press(hosting, id: "search-filters")
            try await waitForNativeUI(100)
            var filterPopover: (NSWindow, NSView)?
            for _ in 0..<8 where filterPopover == nil {
                filterPopover = popover(containing: "search-filters-popover")
                try await waitForNativeUI()
            }
            guard let filterPopover else {
                throw NSError(domain: "SearchWindowTests", code: 15,
                              userInfo: [NSLocalizedDescriptionKey: "Could not open filters for visual evidence"])
            }
            let filterName = "global-date-search-filters-popover-\(appearance)@2x.png"
            var filterRecord = try snapshot(filterPopover.1, to: renders.appendingPathComponent(filterName))
            filterRecord["appearance"] = appearance
            filterRecord["surface"] = "native Search filters popover"
            records.append(filterRecord)
            try await closeFilterUsingDone(filterPopover)

            state.updateGlobalSearch("nebula notebook")
            state.openSearchNote(fixture.note)
            resize(window, hosting: hosting, width: 736)
            try await waitForNativeUI(100)
            let noteName = "global-date-search-note-editor-\(appearance)-736x\(Int(boardHeight))@2x.png"
            var noteRecord = try snapshot(hosting, to: renders.appendingPathComponent(noteName))
            noteRecord["appearance"] = appearance
            noteRecord["surface"] = "editable Search note route"
            records.append(noteRecord)
            state.back()
            try await waitForNativeUI()

            state.updateGlobalSearch("ultraviolet OCR only phrase")
            state.searchDateAnchor = state.searchDateGroups.first?.day
            state.searchSelectedResultID = nil
            resize(window, hosting: hosting, width: 380)
            try await waitForNativeUI(100)
            let photoName = "global-date-search-local-photo-\(appearance)-380x\(Int(boardHeight))@2x.png"
            var photoRecord = try snapshot(hosting, to: renders.appendingPathComponent(photoName))
            photoRecord["appearance"] = appearance
            photoRecord["query"] = "local indexed-text fixture"
            records.append(photoRecord)
        }
        return records
    }

    private static func evidenceRoot() -> URL {
        if let override = ProcessInfo.processInfo.environment["DABIN_SEARCH_QA_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let repository = FileManager.default.fileExists(atPath: current.appendingPathComponent("native/Sources/DaBin").path)
            ? current : current.deletingLastPathComponent()
        return repository.appendingPathComponent("docs/qa/global-date-search-2026-10-03", isDirectory: true)
    }

    @MainActor private static func prepareQAResultSentinel() throws {
        guard let path = ProcessInfo.processInfo.environment["DABIN_QA_RESULT_PATH"], !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        try writeQAResult(passed: false, error: "incomplete: Search QA did not reach a terminal result")
    }

    @MainActor private static func writeQAResult(passed: Bool, error: String? = nil) throws {
        guard let path = ProcessInfo.processInfo.environment["DABIN_QA_RESULT_PATH"], !path.isEmpty else { return }
        var result: [String: Any] = [
            "passed": passed,
            "checks": checks,
            "keyboardVerification": passed
                ? keyboardVerificationReceipt
                : (skipsKeyboardVerification
                    ? "not run: desktop focus unavailable"
                    : "failed or incomplete: strict keyboard verification required")
        ]
        if let error { result["error"] = error }
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    @MainActor private static func runTests(application: NSApplication) async throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("DaBinSearchWindow-\(UUID().uuidString)", isDirectory: true)
        let fixtureRoot = temporary.appendingPathComponent("fixture", isDirectory: true)
        let benchmarkRoot = temporary.appendingPathComponent("benchmark", isDirectory: true)
        let suite = "DaBinSearchWindow.\(UUID().uuidString)"
        let benchmarkSuite = "DaBinSearchBenchmark.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let benchmarkDefaults = UserDefaults(suiteName: benchmarkSuite)!
        defer {
            defaults.removePersistentDomain(forName: suite)
            benchmarkDefaults.removePersistentDomain(forName: benchmarkSuite)
            try? FileManager.default.removeItem(at: temporary)
        }

        phase("fixture: create isolated records")
        let fixture = try await makeFixture(root: fixtureRoot, defaults: defaults)
        defer {
            fixture.state.shutdownNotificationPresentation()
            fixture.autoCapture.shutdown()
            fixture.previews.shutdown()
            fixture.store.cancelArchiveRepair()
        }

        phase("matching: indexed text, checklist, snippets and empty browse")
        try checkGlobalMatching(fixture)
        phase("window: mount and activate native Board")
        let initialSize = NSSize(width: 380, height: boardHeight)
        let hosting = NSHostingView(rootView: BoardView(state: fixture.state, theme: fixture.theme)
            .environment(\.displayScale, 2))
        hosting.frame = NSRect(origin: .zero, size: initialSize)
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        let window = DaBinPanel(contentRect: NSRect(x: 90, y: 90, width: initialSize.width, height: initialSize.height),
                                styleMask: [.borderless], backing: .buffered, defer: false)
        window.becomesKeyOnlyIfNeeded = false
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        application.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        try await waitForNativeUI(150)

        let accessibilityActivation = await Task.detached {
            let process = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            AXUIElementSetMessagingTimeout(process, 3)
            var windows: CFTypeRef?
            return AXUIElementCopyAttributeValue(process, kAXWindowsAttribute as CFString, &windows)
        }.value
        try expect(accessibilityActivation == .success,
                   "Own-process accessibility activation succeeds (AX error \(accessibilityActivation.rawValue))")
        try await waitForNativeUI()
        for _ in 0..<10 where !(application.isActive && application.keyWindow === window) {
            application.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            try await waitForNativeUI(100)
        }
        if !skipsKeyboardVerification {
            let key = application.keyWindow.map { "\(String(describing: type(of: $0)))#\($0.windowNumber)" } ?? "nil"
            try expect(application.isActive && application.keyWindow === window,
                       "The isolated Search QA app becomes active with its production panel key; active=\(application.isActive), key=\(key), panelIsKey=\(window.isKeyWindow), canBecomeKey=\(window.canBecomeKey), visible=\(window.isVisible)")
        }

        phase("entry: Project workspace Search is global")
        try await checkProjectSearchEntry(fixture, hosting: hosting, window: window)
        phase("paging: responsive one, two and three date columns")
        try checkPagingAndResponsiveColumns(fixture, hosting: hosting, window: window)
        phase("viewport: independent native date columns")
        try await checkIndependentColumnViewports(fixture, hosting: hosting, window: window)
        phase("viewport: stale deferred write invalidation")
        try await checkDeferredViewportResetRace(fixture)
        phase("routing: compact details and expanded preview")
        try await checkCaptureRouting(fixture, hosting: hosting, window: window)
        phase("routing: editable project note and Back")
        try await checkNoteRouting(fixture, hosting: hosting, window: window)
        phase("filters: controls, keyboard or explicit Done, chips and clear")
        try await checkFilters(fixture, hosting: hosting, window: window, application: application)
        phase("recycling: 2000 rows, live insertion and detail restoration")
        try await checkRecyclingAndLiveInsertion(fixture, hosting: hosting, window: window)

        phase("evidence: light and dark native renders")
        let qa = evidenceRoot()
        let renders = qa.appendingPathComponent("renders", isDirectory: true)
        try FileManager.default.createDirectory(at: renders, withIntermediateDirectories: true)
        let screenshots = try await renderEvidence(fixture, hosting: hosting, window: window, renders: renders)
        phase("performance: 5000-record cold and cached Search")
        let timings = try benchmarkSearch(root: benchmarkRoot, defaults: benchmarkDefaults)
        try JSONSerialization.data(withJSONObject: timings, options: [.prettyPrinted, .sortedKeys])
            .write(to: qa.appendingPathComponent("timings.json"), options: .atomic)
        let manifest: [String: Any] = [
            "description": "Native chronological global Search at compact and expanded widths, using only generated fictional local fixtures.",
            "privacy": "Temporary private archives, generated text and a code-drawn 10x10 PNG. No clipboard, network, personal archive or external app content.",
            "dateCount": 6,
            "stressResultCount": 2_000,
            "keyboardVerification": keyboardVerificationReceipt,
            "screenshots": screenshots,
            "timings": timings
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            .write(to: qa.appendingPathComponent("manifest.json"), options: .atomic)
        if skipsKeyboardVerification {
            print("PASS: \(checks) native global Search window, routing, paging, filter, note, recycling, render and performance checks. Keyboard verification excluded: desktop focus unavailable.")
        } else {
            print("PASS: \(checks) native global Search checks; keyboard verification \(keyboardVerificationReceipt).")
        }
        phase("complete")
    }

    /// Run the asynchronous fixture inside AppKit's sustained event loop so
    /// activation, key-window routing, native focus, Tab and Escape are real.
    @MainActor static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        let watchdog = DispatchWorkItem {
            let message = "SearchWindowTests failed: watchdog timed out after 180 seconds\n"
            message.withCString { pointer in
                _ = Darwin.write(STDERR_FILENO, pointer, strlen(pointer))
            }
            Darwin._exit(124)
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 180, execute: watchdog)
        Task { @MainActor in
            do {
                try prepareQAResultSentinel()
                try await runTests(application: application)
                try writeQAResult(passed: true)
                watchdog.cancel()
                application.terminate(nil)
            } catch {
                watchdog.cancel()
                let failure = String(describing: error)
                var resultWriteFailure: String?
                do { try writeQAResult(passed: false, error: failure) }
                catch { resultWriteFailure = String(describing: error) }
                let resultSuffix = resultWriteFailure.map { "; result sentinel write failed: \($0)" } ?? ""
                let message = "SearchWindowTests failed: \(failure)\(resultSuffix)\n"
                FileHandle.standardError.write(Data(message.utf8))
                Darwin.exit(EXIT_FAILURE)
            }
        }
        application.run()
    }
}
