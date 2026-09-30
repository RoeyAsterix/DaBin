@testable import DaBinTestCore
import AppKit
import SwiftUI
import Combine

@MainActor private final class ReviewNotifications: ReminderNotificationClient {
    var requests: [String: ScheduledReminder] = [:]
    func authorization() async -> ReminderAuthorization { .allowed }
    func requestAuthorization() async throws -> Bool { true }
    func pending() async -> [ScheduledReminder] { Array(requests.values) }
    func add(_ reminder: ScheduledReminder) async throws { requests[reminder.identifier] = reminder }
    func removePending(_ ids: [String]) { ids.forEach { requests.removeValue(forKey: $0) } }
    func removeDelivered(_ ids: [String]) {}
}
@MainActor private final class ReviewScreenshots: ScreenshotFolderMonitoring {
    var sourceApplicationAtDirectoryActivity: (() -> AutoCaptureSourceApplication?)?
    var onNewScreenshot: ((URL, AutoCaptureSourceApplication?) -> Void)?
    var onFailure: ((Error) -> Void)?
    private(set) var isRunning = false
    func start() throws { isRunning = true }
    func stop() { isRunning = false }
}
@MainActor private final class ReviewWindow: NSWindow {
    var record: ((NSEvent) -> Void)?
    override func sendEvent(_ event: NSEvent) {
        if [.leftMouseDown, .rightMouseDown, .keyDown].contains(event.type) { record?(event) }
        super.sendEvent(event)
    }
}
@MainActor private final class ReviewFixture: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let root = URL(fileURLWithPath: "/private/tmp/DaBin-Review-Latest-Live-20260930", isDirectory: true)
    private let suite = "com.dabin.qa.uxreview.preferences.latest.20260930"
    private var defaults: UserDefaults!
    private var store: CaptureStore!
    private var state: AppState!
    private var theme: ThemeSettings!
    private var automatic: AutoCaptureService!
    private var hosting: DailyCaptureHostingView!
    private var shell: RobotAppFrameView!
    private var window: ReviewWindow!
    private var controlWindow: NSWindow!
    private var subscriptions = Set<AnyCancellable>()
    private var events: [[String: Any]] = []
    private var counter = 0
    private let launchedAt = ProcessInfo.processInfo.systemUptime
    private var initialWindowShown = false
    private var board: NSPasteboard!
    private let status = NSTextField(wrappingLabelWithString: "Synthetic archive only. Do not use production Paste menu: use Paste fixture here.")

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do {
                try await setup()
                if let index = CommandLine.arguments.firstIndex(of: "--render-only"), CommandLine.arguments.count > index + 1 {
                    try renderStates(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
                    NSApp.terminate(nil)
                } else { show() }
            }
            catch { fputs("Fixture setup failed: \(error)\n", stderr); NSApp.terminate(nil) }
        }
    }
    private func setup() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let marker = root.appendingPathComponent(".dabin-review-fixture")
        if FileManager.default.fileExists(atPath: root.appendingPathComponent("Archive").path), !FileManager.default.fileExists(atPath: marker.path) {
            throw NSError(domain: "Review", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unmarked fixture root"])
        }
        try Data("Only fictional UX review data.\n".utf8).write(to: marker, options: .atomic)
        if let data = try? Data(contentsOf: root.appendingPathComponent("review-events.json")),
           let previous = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let history = previous["events"] as? [[String: Any]] { events = history }
        guard let preferences = UserDefaults(suiteName: suite) else { throw NSError(domain: "Review", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to create isolated preference suite"]) }
        defaults = preferences
        // Dedicated fixture preferences survive relaunch for persistence checks.
        defaults.set(false, forKey: PreviewService.linkPreviewPreference)
        if defaults.object(forKey: ThemeSettings.darkModeKey) == nil { defaults.set(false, forKey: ThemeSettings.darkModeKey) }
        board = NSPasteboard(name: .init("com.dabin.qa.uxreview.latest.clipboard"))
        board.clearContents()
        board.setString("A new idea for the launch checklist", forType: .string)
        store = try CaptureStore(root: root.appendingPathComponent("Archive"))
        if store.captures.isEmpty { try await seed() }
        automatic = AutoCaptureService(settings: AutoCaptureSettings(defaults: defaults), input: InputService(store: store),
            pasteboardProvider: { [board] in board! }, sourceApplicationProvider: { nil },
            screenshotMonitorFactory: { _ in ReviewScreenshots() })
        let disabled = SoftwareUpdateTransport(loadData: { _ in throw URLError(.notConnectedToInternet) }, download: { _ in throw URLError(.notConnectedToInternet) })
        let updates = SoftwareUpdateService(currentVersion: "0.4.1", currentBuild: "50", manifestURL: nil,
            transport: disabled, updatesDirectory: root.appendingPathComponent("Updates"), helperURL: root.appendingPathComponent("NoInstaller"),
            validateHelper: { _ in throw URLError(.notConnectedToInternet) }, launchInstaller: { _, _ in throw URLError(.notConnectedToInternet) })
        state = AppState(store: store, previews: PreviewService(store: store, defaults: defaults),
            reminders: ReminderService(store: store, client: ReviewNotifications()), updates: updates,
            robotPlacement: RobotPlacementSettings(defaults: defaults), autoCapture: automatic,
            captureClipboard: CaptureClipboardService { [weak self] payload in
                self?.log("copy-capture", details: ["payload": String(describing: payload)])
                return true
            }, quickAccessSettings: QuickAccessSettings(defaults: defaults))
        theme = ThemeSettings(defaults: defaults)
        theme.setBoardOpacity(1)
        let exports = DayExportActionController(pasteboardWriter: { [weak self] text in
            guard let self else { return false }
            try? Data(text.utf8).write(to: self.root.appendingPathComponent("Copied-export.txt"), options: .atomic)
            self.log("copy-export", details: ["characters": text.count]); return true
        }, destinationChooser: { [root] _, filename in .selected(root.appendingPathComponent(filename)) }, fileWriter: { data, url in try data.write(to: url, options: .atomic) })
        hosting = DailyCaptureHostingView(state: state, theme: theme)
        hosting.rootView = BoardView(state: state, theme: theme, dayExportController: exports)
        hosting.onPaste = { [weak self] in self?.pasteFixture() }
        hosting.onDrop = { [weak self] pasteboard in
            guard let self else { return }
            let input = InputService(store: self.store)
            input.receive(pasteboard, completion: { [weak self, input] captures, errors in
                _ = input
                self?.state.reportCaptureResult(captures, errors: errors)
                self?.log("native-drop", details: ["saved": captures.count, "errors": errors])
            })
        }
        shell = RobotAppFrameView(contentView: hosting)
        let size = RobotAppFrameView.outerSize(forContentSize: CGSize(width: 380, height: 650))
        window = ReviewWindow(contentRect: NSRect(x: 340, y: 120, width: size.width, height: size.height),
            styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "DaBin UX Review — synthetic latest"
        window.identifier = .init("dabin-ux-review-window")
        window.contentView = shell
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.sharingType = .readOnly // Fixture only; production screenshot privacy is untouched.
        window.minSize = NSSize(width: 380, height: 380)
        shell.autoresizingMask = [.width, .height]
        CornerController.applyBoardAppearance(darkMode: false, to: window, frame: shell, hosting: hosting)
        state.onDismiss = { [weak self] in self?.snapshot(); self?.window.orderOut(nil); self?.state.isBoardVisible = false; self?.shell.setVisible(false); self?.log("hide") }
        state.onTaskCompleted = { [weak self] in self?.shell.celebrateTaskCompletion(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion); self?.log("completed-task") }
        state.onToggleExpandedWindow = { [weak self] in self?.resize(width: 760, height: 760) }
        window.record = { [weak self] event in
            self?.log("input", details: ["type": event.type.rawValue, "x": event.locationInWindow.x, "y": event.locationInWindow.y, "keyCode": event.type == .keyDown ? event.keyCode : 0])
        }
        state.$route.removeDuplicates().sink { [weak self] route in self?.log("route", details: ["route": String(describing: route)]) }.store(in: &subscriptions)
        store.$captures.sink { [weak self] captures in self?.log("capture-count", details: ["count": captures.count]) }.store(in: &subscriptions)
        makeControls()
        try seedWorkspaceIfNeeded()
        state.openInbox()
        log("ready", details: ["bundleID": Bundle.main.bundleIdentifier ?? "", "archive": store.root.path])
    }
    private func seed() async throws {
        let now = Date().addingTimeInterval(-3600)
        _ = try store.capture(text: "Launch checklist\nKeep the first step small and welcoming.", at: now,
            source: CaptureSource(url: "https://example.invalid/launch"), receipt: .automatic(.automaticClipboard, sourceApplicationName: "Safari", sourceApplicationBundleIdentifier: "com.apple.Safari"))
        let image = NSImage(size: NSSize(width: 640, height: 400))
        image.lockFocus(); NSColor(calibratedWhite: 0.96, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 640, height: 400).fill()
        NSColor.systemPurple.withAlphaComponent(0.3).setFill(); NSBezierPath(roundedRect: NSRect(x: 35, y: 35, width: 570, height: 330), xRadius: 30, yRadius: 30).fill()
        ("LAUNCH\nA little space for good ideas" as NSString).draw(in: NSRect(x: 65, y: 135, width: 520, height: 145), withAttributes: [.font: NSFont.systemFont(ofSize: 34, weight: .semibold), .foregroundColor: NSColor.darkGray])
        image.unlockFocus()
        let data = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        let capture = try await store.importData(data, filename: "Launch moodboard.png", at: now.addingTimeInterval(60))
        capture.thumbnailRelativePath = "Previews/\(capture.id.uuidString)/thumbnail.png"
        let thumbnail = store.root.appendingPathComponent(capture.thumbnailRelativePath!)
        try FileManager.default.createDirectory(at: thumbnail.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: thumbnail); capture.previewState = "ready"
        let task = try store.createTask(text: "Polish the welcome screen", at: now.addingTimeInterval(120))
        try store.update(task, comment: "Use the violet sketch. Keep the capture step obvious.", reminderAt: nil, reminderTimeZoneID: nil)
        _ = try store.capture(text: "Welcome copy\nDrop, remember, carry on.", at: now.addingTimeInterval(180), parentTask: task)
        for day in [1, 3, 6] {
            _ = try store.capture(text: "Studio note from \(day) days ago", at: now.addingTimeInterval(-Double(day) * 86400))
        }
        try store.save()
    }
    private func makeControls() {
        controlWindow = NSWindow(contentRect: NSRect(x: 45, y: 140, width: 270, height: 370), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        controlWindow.title = "Review controls — fixtures only"
        controlWindow.isReleasedWhenClosed = false
        controlWindow.sharingType = .readOnly
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 270, height: 370))
        controlWindow.contentView = content
        status.frame = NSRect(x: 16, y: 274, width: 238, height: 80); content.addSubview(status)
        let actions: [(String, Selector)] = [("Show fixture", #selector(show)), ("Paste fixture", #selector(pasteFixture)), ("Narrow 380", #selector(narrow)), ("Wide 760", #selector(wide)), ("Light / Dark", #selector(toggleTheme)), ("Snapshot + checkpoint", #selector(snapshot)), ("Quit review", #selector(quit))]
        for (i, action) in actions.enumerated() {
            let button = NSButton(title: action.0, target: self, action: action.1)
            button.frame = NSRect(x: 16, y: 238 - i * 33, width: 238, height: 28); button.bezelStyle = .rounded
            content.addSubview(button)
        }
        let menu = NSMenu(); let item = NSMenuItem(); let app = NSMenu()
        for (name, selector, key) in [("Show fixture", #selector(show), "o"), ("Inbox", #selector(inbox), "1"), ("Today", #selector(today), "2"), ("Workspace", #selector(workspace), "3"), ("Narrow", #selector(narrow), "4"), ("Wide", #selector(wide), "5"), ("Snapshot", #selector(snapshot), "s"), ("Light / Dark", #selector(toggleTheme), "l"), ("Paste fixture", #selector(pasteFixture), "p"), ("Quit review", #selector(quit), "q")] {
            let command = app.addItem(withTitle: name, action: selector, keyEquivalent: key)
            command.target = self
        }
        item.submenu = app; menu.addItem(item); NSApp.mainMenu = menu
    }
    @objc private func show() {
        let start = ProcessInfo.processInfo.systemUptime
        state.isBoardVisible = true; shell.setVisible(true); controlWindow.orderFront(nil); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        shell.layoutSubtreeIfNeeded(); shell.displayIfNeeded()
        log(initialWindowShown ? "reopen-layout" : "launch-layout", details: ["seconds": ProcessInfo.processInfo.systemUptime - (initialWindowShown ? start : launchedAt), "measurement": "Delegate setup + synchronous layout, excludes process bootstrap and GPU presentation"])
        initialWindowShown = true
    }
    @objc private func inbox() { state.openInbox(); show() }
    @objc private func today() { state.showReminders(); show() }
    @objc private func workspace() { state.openLibrary(); show() }
    private func seedWorkspaceIfNeeded() throws {
        let marker = root.appendingPathComponent("workspace-seeded")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        let today = CaptureCalendar.dayString(Date())
        if let task = store.captures.first(where: { $0.isTask }) {
            try store.setTaskPlanning(task, planning: TaskPlanning(plannedDay: today, priority: .high, effortMinutes: 25, checklist: [TaskChecklistItem(text: "Choose the welcome copy"), TaskChecklistItem(text: "Check the empty state")]))
            state.assignProject(task, name: "Launch")
        }
        for capture in store.captures where capture.kind == .image { state.assignProject(capture, name: "Launch") }
        if let reference = store.captures.first(where: { $0.title.contains("Launch checklist") }) {
            state.assignProject(reference, name: "Launch")
            try state.workspace.setOnShelf([reference.id], included: true)
            try state.workspace.setSnippetName("Launch greeting", for: reference.id)
        }
        try state.workspace.setScratchpad(text: "Welcome should feel calm.\nMake the capture action easy to spot.\nTry the violet sketch first.", project: "Launch")
        _ = try store.createTask(text: "Collect feedback from the first tester", at: Date().addingTimeInterval(-120))
        state.workspace.selectedProject = nil
        try Data("Synthetic workspace seed complete".utf8).write(to: marker, options: .atomic)
    }
    @objc private func pasteFixture() {
        if let task = state.selectedCapture, state.route == .detail, task.isTask { state.pasteAttachments(to: task, from: board) }
        else { state.pasteClipboard(from: board) }
        log("paste-fixture"); window.makeKeyAndOrderFront(nil)
    }
    @objc private func narrow() { resize(width: 380, height: 650) }
    @objc private func wide() { resize(width: 760, height: 730) }
    private func resize(width: CGFloat, height: CGFloat) { window.setContentSize(RobotAppFrameView.outerSize(forContentSize: CGSize(width: width, height: height))); log("resize", details: ["width": width, "height": height]); show() }
    @objc private func toggleTheme() { theme.setDarkMode(!theme.darkModeEnabled); CornerController.applyBoardAppearance(darkMode: theme.darkModeEnabled, to: window, frame: shell, hosting: hosting); log("theme", details: ["dark": theme.darkModeEnabled]) }
    @objc private func snapshot() {
        shell.layoutSubtreeIfNeeded(); shell.displayIfNeeded()
        guard let bitmap = shell.bitmapImageRepForCachingDisplay(in: shell.bounds) else { return }
        shell.cacheDisplay(in: shell.bounds, to: bitmap)
        if let data = bitmap.representation(using: .png, properties: [:]) {
            counter += 1; let file = "live-\(Int(Date().timeIntervalSince1970 * 1000))-\(state.route)-\(Int(shell.bounds.width))x\(Int(shell.bounds.height)).png"
            try? data.write(to: root.appendingPathComponent(file)); log("snapshot", details: ["file": file])
        }
    }
    private func log(_ event: String, details: [String: Any] = [:]) {
        var value = details; value["uptime"] = ProcessInfo.processInfo.systemUptime; value["event"] = event; value["at"] = ISO8601DateFormatter().string(from: Date()); events.append(value)
        let payload: [String: Any] = ["fixtureOnly": true, "bundleID": Bundle.main.bundleIdentifier ?? "", "root": root.path, "captureCount": store?.captures.count ?? 0, "events": events]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: root.appendingPathComponent("review-events.json"), options: .atomic) }
    }
    /// Own-process native fixture rendering. No activation or other-app UI access.
    private func renderStates(to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        shell.setVisible(true)
        for dark in [false, true] {
            theme.setDarkMode(dark)
            CornerController.applyBoardAppearance(darkMode: dark, to: window, frame: shell, hosting: hosting)
            for (width, height) in [(CGFloat(380), CGFloat(430)), (380, 680), (760, 680)] {
                window.setContentSize(RobotAppFrameView.outerSize(forContentSize: CGSize(width: width, height: height)))
                for view in ["inbox", "today", "library", "clipboard", "shelf", "scratchpad"] {
                    state.libraryProject = nil
                    if view == "inbox" { state.openInbox() }
                    else if view == "today" { state.showReminders() }
                    else {
                        state.openLibrary()
                        state.workspace.mode = view == "library" ? .collection : view == "clipboard" ? .clipboard : view == "shelf" ? .shelf : .scratchpad
                        if view == "scratchpad" { state.libraryProject = "Launch" }
                    }
                    RunLoop.main.run(until: Date().addingTimeInterval(0.15))
                    shell.layoutSubtreeIfNeeded(); shell.displayIfNeeded()
                    guard let bitmap = shell.bitmapImageRepForCachingDisplay(in: shell.bounds) else { continue }
                    shell.cacheDisplay(in: shell.bounds, to: bitmap)
                    if let png = bitmap.representation(using: .png, properties: [:]) {
                        let suffix = height == 430 ? "-minimum" : ""
                        try png.write(to: destination.appendingPathComponent("native-\(view)-\(dark ? "dark" : "light")-\(Int(width))\(suffix).png"), options: .atomic)
                    }
                }
            }
        }
        print("PASS: 36 latest native view renders (offscreen, synthetic archive)")
    }
    func windowWillClose(_ notification: Notification) { if notification.object as? NSWindow === window { state.isBoardVisible = false; shell.setVisible(false) } }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { automatic?.shutdown(); shell?.setVisible(false); board?.releaseGlobally(); log("quit"); _ = defaults }
}
@main struct ReviewFixtureMain {
    @MainActor static func main() {
        let application = NSApplication.shared; let delegate = ReviewFixture()
        application.setActivationPolicy(.regular); application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
