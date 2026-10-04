import AppKit
import ApplicationServices
import CryptoKit
import Foundation
import SwiftUI

@MainActor private final class LocalFolderReminderClient: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .undetermined }
    func requestAuthorization() async throws -> Bool { fatalError("Folder QA must not request notification permission") }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws { }
    func removePending(_ identifiers: [String]) { }
    func removeDelivered(_ identifiers: [String]) { }
}

@MainActor private final class LocalFolderFixtureWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Inspect only our retained production hosting views. SwiftUI's virtual nodes
/// expose public accessibility selectors without always adopting the protocol.
@MainActor private struct LocalFolderAX {
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
    var diagnostic: String {
        let role = (value("accessibilityRole") as? String) ?? (attribute("AXRole") as? String) ?? "no role"
        let names = ["accessibilityLabel", "accessibilityTitle", "accessibilityDescription", "accessibilityValue"]
            .compactMap { name -> String? in
                guard let content = value(name) as? String else { return nil }
                return "\(name)=\(String(reflecting: content))"
            }.joined(separator: ", ")
        return "\(type(of: object)) role=\(role) id=\(identifier ?? "none") resolvedLabel=\(String(reflecting: label)) press=\(object.responds(to: NSSelectorFromString("accessibilityPerformPress"))) [\(names)]"
    }
    func press() -> Bool {
        let selector = NSSelectorFromString("accessibilityPerformPress")
        guard object.responds(to: selector) else { return false }
        typealias Action = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(object.method(for: selector), to: Action.self)(object, selector)
    }
    var children: [Any] {
        var result: [Any] = []
        for name in ["accessibilityChildren", "accessibilityChildrenInNavigationOrder", "accessibilityContents"] {
            if let children = value(name) as? [Any] { result += children }
        }
        if let children = attribute("AXChildren") as? [Any] { result += children }
        if let view = object as? NSView { result += view.subviews }
        return result
    }
}

/// Production folder buttons with a read-only opener spy. Disposable fictional
/// captures and offscreen, non-key windows only: no Finder, personal archive,
/// clipboard, global pointer events, permission requests or network.
@main @MainActor private final class LocalFileLocationTests: NSObject, NSApplicationDelegate {
    private static var checks = 0
    private var result: Int32 = 0
    private static let files = FileManager.default
    private struct Fixture {
        let hosting: NSHostingView<AnyView>
        let window: NSWindow
        func close() { window.orderOut(nil); window.contentView = nil; window.close() }
    }

    static func main() {
        let app = NSApplication.shared
        let delegate = LocalFileLocationTests()
        app.setActivationPolicy(.accessory); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        exit(delegate.result)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await Self.run() }
            catch { result = 1; fputs("Local file location QA failed: \(error)\n", stderr) }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "LocalFileLocationTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        guard try condition() else { throw failure(message) }
    }
    private static func rejects(_ action: () throws -> Void, _ message: String) throws {
        var rejected = false
        do { try action() } catch { rejected = true }
        try expect(rejected, message)
    }
    private static func nodes(_ view: NSView) -> [LocalFolderAX] {
        view.layoutSubtreeIfNeeded()
        var seen = Set<ObjectIdentifier>(), result: [LocalFolderAX] = []
        func visit(_ candidate: Any, depth: Int) {
            guard depth < 50, let object = candidate as? NSObject,
                  seen.insert(ObjectIdentifier(object)).inserted else { return }
            let node = LocalFolderAX(object: object); result.append(node)
            node.children.forEach { visit($0, depth: depth + 1) }
        }
        visit(view, depth: 0)
        NSAccessibility.unignoredChildren(from: [view]).forEach { visit($0, depth: 0) }
        return result
    }
    private static func settle(_ view: NSView) async {
        for _ in 0..<5 { view.layoutSubtreeIfNeeded(); try? await Task.sleep(for: .milliseconds(35)) }
    }
    private static func hierarchy(_ root: LocalFolderAX) -> String {
        var seen = Set<ObjectIdentifier>(), lines: [String] = []
        func visit(_ node: LocalFolderAX, depth: Int) {
            guard depth < 20, seen.insert(ObjectIdentifier(node.object)).inserted else { return }
            lines.append(String(repeating: "  ", count: depth) + node.diagnostic)
            for child in node.children {
                if let object = child as? NSObject { visit(LocalFolderAX(object: object), depth: depth + 1) }
            }
        }
        visit(root, depth: 0)
        return lines.joined(separator: "\n")
    }
    private static func find(_ view: NSView, id: String? = nil, label: String? = nil) async throws -> LocalFolderAX {
        for _ in 0..<6 {
            if let node = nodes(view).first(where: {
                if let id { return $0.identifier == id }
                return label != nil && $0.label == label
            }) { return node }
            await settle(view)
        }
        throw failure("Missing local folder control \(id ?? label ?? "unknown"): \(nodes(view).map { $0.identifier ?? $0.label }.joined(separator: "; "))")
    }
    private static func press(_ view: NSView, id: String? = nil, label: String? = nil) async throws {
        let control = try await find(view, id: id, label: label)
        try expect(control.press(), "\(id ?? label ?? "Folder button") exposes its real native press action")
        await settle(view)
    }
    private static func fixture<V: View>(_ root: V, size: NSSize) async throws -> Fixture {
        let content = root.frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(Palette.background).environment(\.daBinTooltipsEnabled, false)
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
        let hosting = NSHostingView(rootView: AnyView(content))
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = LocalFolderFixtureWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting; window.orderFront(nil)
        await settle(hosting)
        let activation = await Task.detached {
            let process = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            AXUIElementSetMessagingTimeout(process, 3)
            var windows: CFTypeRef?
            return AXUIElementCopyAttributeValue(process, kAXWindowsAttribute as CFString, &windows)
        }.value
        if activation != .success {
            window.orderOut(nil); window.contentView = nil; window.close()
            throw failure("Own-process accessibility activation failed: \(activation.rawValue)")
        }
        await settle(hosting)
        try expect(window.frame.maxX < 0 && !window.isKeyWindow, "Folder fixtures remain offscreen and non-key")
        return Fixture(hosting: hosting, window: window)
    }
    private static func inventory(_ root: URL) throws -> [String: String] {
        guard let entries = files.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
            throw failure("Cannot enumerate fictional library")
        }
        var result: [String: String] = [:]
        for case let url as URL in entries where try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            let path = String(url.path.dropFirst(root.path.count + 1))
            result[path] = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
        }
        return result
    }

    private static func run() async throws {
        let scratch = files.temporaryDirectory.appendingPathComponent("DaBinLocalFolderQA-\(UUID().uuidString)")
        let root = scratch.appendingPathComponent("Library", isDirectory: true)
        let suite = "DaBinLocalFolderQA.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? files.removeItem(at: scratch) }
        let store = try CaptureStore(root: root)
        let source = scratch.appendingPathComponent("Fictional proposal.bin")
        let payload = Data([0, 1, 2, 3, 255]) + Data("Exact fictional imported original\n".utf8)
        try payload.write(to: source)
        let capturedAt = ISO8601DateFormatter().date(from: "2026-09-30T09:10:11Z")!
        let imported = try await store.importFile(source, at: capturedAt, timeZone: .gmt, projectName: "Northstar")
        let originalURL = try store.localArchiveFolderURL(for: imported)
        let managedBefore = store.managedURL(for: imported)!
        try expect(originalURL == managedBefore.deletingLastPathComponent(), "Imported capture opens the actual managed-original parent")
        try expect(originalURL != store.archiveURL(for: imported) && originalURL != source.deletingLastPathComponent(),
                   "Saved folder is neither its metadata sidecar nor the external source location")
        try expect(try store.localArchiveFolderURL() == store.root && store.root != store.archiveRoot,
                   "Global archive opens the complete local library, including Projects and Unfiled")

        try store.setOrganization(imported, pinned: true, projectName: "Southstar")
        let managedAfter = store.managedURL(for: imported)!
        let currentParent = managedAfter.deletingLastPathComponent()
        try expect(managedAfter != managedBefore && !files.fileExists(atPath: managedBefore.path),
                   "Fixture actually moved between physical project folders")
        try expect(try store.localArchiveFolderURL(for: imported) == currentParent && currentParent != originalURL,
                   "Folder resolution follows a reorganized file's current owned path")
        try expect(try Data(contentsOf: managedAfter) == payload && Data(contentsOf: source) == payload,
                   "Resolving saved folders preserves both managed and external original bytes")

        let note = try store.createNote(text: "Fictional project note", at: capturedAt, projectName: "Northstar")
        let task = try store.createTask(text: "Fictional project task", at: capturedAt, timeZone: .gmt, projectName: "Northstar")
        let child = try store.capture(text: "Fictional attached note", at: capturedAt, timeZone: .gmt)[0]
        try store.attachCapture(child, to: task)
        let northDay = try store.explorerDayURL(project: "Northstar", day: task.captureDay).deletingLastPathComponent()
        try expect(try store.localArchiveFolderURL(for: note) == northDay,
                   "A metadata-only note opens its readable project/date directory")
        try expect(try store.localArchiveFolderURL(for: task) == northDay,
                   "A task without an attachment opens its readable project/date directory")
        try expect(try store.localArchiveFolderURL(for: child) == northDay,
                   "An attached metadata-only note uses its live task parent's effective project")
        try expect(files.fileExists(atPath: try store.explorerDayURL(project: "Northstar", day: note.captureDay).path),
                   "Metadata-only destination contains the generated readable daily record")
        let unfiled = try store.capture(text: "Fictional unfiled note", at: capturedAt, timeZone: .gmt)[0]
        let unfiledDay = try store.explorerDayURL(project: nil, day: unfiled.captureDay).deletingLastPathComponent()
        try expect(try store.localArchiveFolderURL(for: unfiled) == unfiledDay,
                   "An unfiled capture opens its Unfiled date directory")

        let autoCapture = AutoCaptureService(settings: AutoCaptureSettings(defaults: defaults), input: InputService(store: store),
            pasteboardProvider: { fatalError("Folder QA must not access the clipboard") }, sourceApplicationProvider: { nil })
        defer { autoCapture.shutdown() }
        var opened: [URL] = []
        var openerSucceeds = true
        let previews = PreviewService(store: store, defaults: defaults)
        defer { previews.cancelNetwork() }
        let state = AppState(store: store, previews: previews,
            reminders: ReminderService(store: store, client: LocalFolderReminderClient()), autoCapture: autoCapture,
            folderOpener: { url in opened.append(url); return openerSucceeds })
        let northFolder = try store.explorerFolderURL(project: "Northstar")
        let unfiledFolder = try store.explorerFolderURL(project: nil)
        let beforeOpen = try inventory(store.root)
        state.showArchiveFolder()
        try expect(opened.last == store.root, "AppState sends the complete local archive to its macOS opener")
        state.showArchiveFolder(for: imported)
        try expect(opened.last == currentParent, "Capture action sends its actual managed file directory")
        try expect(try inventory(store.root) == beforeOpen, "Opening the archive or file location changes no library file bytes")
        state.libraryProject = "Northstar"; state.workspace.explorerUnfiledOnly = false
        state.showProjectFiles()
        try expect(opened.last == northFolder, "Project Files opens the selected project's physical directory")
        state.libraryProject = nil
        state.showProjectFiles()
        try expect(opened.last == store.root, "All projects Files opens the complete local archive")
        state.workspace.explorerUnfiledOnly = true
        state.showProjectFiles()
        try expect(opened.last == unfiledFolder, "Unfiled Files opens only the physical Unfiled directory")

        state.workspace.explorerUnfiledOnly = false; state.libraryProject = "Northstar"
        let explorer = try await fixture(ExplorerScreen(state: state), size: NSSize(width: 380, height: 800))
        defer { explorer.close() }
        let explorerImport = try await find(explorer.hosting, id: "explorer-add-files")
        try expect(explorerImport.label == "Add files", "Explorer preserves an explicitly named Add files importer")
        await settle(explorer.hosting)
        let explorerOpens = opened.count
        try await press(explorer.hosting, id: "explorer-open-files")
        try expect(opened.count == explorerOpens + 1 && opened.last == northFolder,
                   "Production Explorer Files button opens its selected local project without invoking intake")
        state.libraryProject = nil
        try await press(explorer.hosting, id: "explorer-open-files")
        try expect(opened.last == store.root, "The mounted Explorer button follows All projects")
        state.workspace.explorerUnfiledOnly = true
        try await press(explorer.hosting, id: "explorer-open-files")
        try expect(opened.last == unfiledFolder, "The mounted Explorer button follows the Unfiled scope")

        state.workspace.explorerUnfiledOnly = false; state.libraryProject = "Northstar"; state.workspace.mode = .shelf
        let shelf = try await fixture(LibraryScreen(state: state), size: NSSize(width: 380, height: 800))
        defer { shelf.close() }
        let shelfImport = try await find(shelf.hosting, id: "workspace-add-files")
        try expect(shelfImport.label == "Add files", "Shelf preserves the separate Add files importer. Selected ID node hierarchy:\n\(hierarchy(shelfImport))\nAll matching ID nodes:\n\(nodes(shelf.hosting).filter { $0.identifier == "workspace-add-files" }.map(\.diagnostic).joined(separator: "\n"))")
        let shelfOpens = opened.count
        try await press(shelf.hosting, id: "workspace-open-files")
        try expect(opened.count == shelfOpens + 1 && opened.last == northFolder,
                   "Production Shelf Files opens the selected local project directory")

        let settings = try await fixture(SettingsScreen(state: state, theme: ThemeSettings(defaults: defaults)),
            size: NSSize(width: 600, height: 2_600))
        defer { settings.close() }
        let settingsOpens = opened.count
        try await press(settings.hosting, id: "settings-open-local-archive")
        try expect(opened.count == settingsOpens + 1 && opened.last == store.root,
                   "Settings Open local archive opens the complete library despite selected project")

        state.openCapture(imported.id)
        guard let draft = state.selectedDraft else { throw failure("File detail fixture did not create its draft") }
        let detail = try await fixture(DetailScreen(state: state, capture: imported, draft: draft),
            size: NSSize(width: 380, height: 1_300))
        defer { detail.close() }
        let detailOpens = opened.count
        try await press(detail.hosting, label: "Show saved folder")
        try expect(opened.count == detailOpens + 1 && opened.last == currentParent,
                   "Production capture-detail folder action opens the current saved original directory")

        openerSucceeds = false; state.status = nil
        state.showArchiveFolder(for: imported)
        try expect(state.status?.severity == .error && state.status?.text.localizedCaseInsensitiveContains("could not open") == true,
                   "macOS opener failure produces visible archive feedback")
        state.status = nil; state.showProjectFiles()
        try expect(state.status?.severity == .error && state.status?.text.localizedCaseInsensitiveContains("folder") == true,
                   "macOS opener failure also produces visible project-files feedback")
        openerSucceeds = true

        let stale = Capture(snapshot: CaptureSnapshot(imported))
        try rejects({ _ = try store.localArchiveFolderURL(for: stale) }, "Stale copy with a matching UUID cannot resolve a live record's file")
        let staleOpens = opened.count; state.status = nil
        state.showArchiveFolder(for: stale)
        try expect(opened.count == staleOpens && state.status?.severity == .error,
                   "A stale action reports failure without opening any location")
        try store.moveToTrash(unfiled)
        let deleted = store.trashedCaptures.first { $0.id == unfiled.id }!
        try rejects({ _ = try store.localArchiveFolderURL(for: deleted) }, "Deleted records cannot open a live saved-folder destination")
        let deletedOpens = opened.count; state.status = nil
        state.showArchiveFolder(for: deleted)
        try expect(opened.count == deletedOpens && state.status?.severity == .error,
                   "A deleted-record action reports failure without opening a live folder")

        try files.removeItem(at: managedAfter)
        let missingOpens = opened.count; state.status = nil
        try rejects({ _ = try store.localArchiveFolderURL(for: imported) }, "Missing managed original never falls back to a misleading metadata/source folder")
        state.showArchiveFolder(for: imported)
        try expect(opened.count == missingOpens && state.status?.severity == .error,
                   "Missing saved file reports an error without opening an unrelated location")
        try expect(try Data(contentsOf: source) == payload && files.fileExists(atPath: store.archiveURL(for: imported)!.path),
                   "Missing-file feedback preserves the outside source and capture metadata")
        print("PASS: \(checks) local-folder resolution, project scope, native button, read-only byte preservation, and failure-feedback checks")
    }
}
