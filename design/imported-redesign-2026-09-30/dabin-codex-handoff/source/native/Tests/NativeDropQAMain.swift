import AppKit

// Manual integration fixture: real AppKit dragging sessions enter the production
// robot and importer. The archive and both sources are generated in a new temp
// directory; this process never reads the normal DaBin archive or clipboard.
@MainActor private final class DragFixtureView: NSView, NSDraggingSource {
    let title: String
    let writer: NSPasteboardWriting
    var onEnded: ((NSDragOperation) -> Void)?
    var onEvent: ((String, NSEvent?) -> Void)?
    private var began = false

    init(frame: NSRect, title: String, writer: NSPasteboardWriting) {
        self.title = title
        self.writer = writer
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        setAccessibilityHelp("Drag this fixture onto the purple robot")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.32, green: 0.22, blue: 0.47, alpha: 1).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
        (title as NSString).draw(at: NSPoint(x: 20, y: 21), withAttributes: [
            .font: NSFont.systemFont(ofSize: 17, weight: .medium), .foregroundColor: NSColor.white
        ])
    }
    override func mouseDown(with event: NSEvent) {
        began = false
        onEvent?("mouseDown", event)
        // These rows are dedicated drag handles. Establish the native session
        // immediately, before an automation client sends its sole drag movement.
        beginFixtureDrag(with: event)
    }
    override func mouseUp(with event: NSEvent) { onEvent?("mouseUp", event) }
    override func mouseDragged(with event: NSEvent) {
        onEvent?("mouseDragged", event)
        beginFixtureDrag(with: event)
    }
    private func beginFixtureDrag(with event: NSEvent) {
        guard !began else { return }
        began = true
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        draw(bounds)
        image.unlockFocus()
        let item = NSDraggingItem(pasteboardWriter: writer)
        item.setDraggingFrame(bounds, contents: image)
        onEvent?("sessionStarting", event)
        let session = beginDraggingSession(with: [item], event: event, source: self)
        onEvent?("sessionStarted", event)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .none
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        began = false
        onEvent?("sessionEnded", nil)
        onEnded?(operation)
    }
}

@MainActor private final class DropQAWindow: NSWindow {
    var onMouseEvent: ((NSEvent) -> Void)?
    override func sendEvent(_ event: NSEvent) {
        if [.leftMouseDown, .leftMouseDragged, .leftMouseUp].contains(event.type) {
            onMouseEvent?(event)
        }
        super.sendEvent(event)
    }
}

@MainActor private final class NativeDropQA: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: DropQAWindow!
    private var store: CaptureStore!
    private var input: InputService!
    private let robot = RobotView(frame: NSRect(x: 504, y: 150, width: 72, height: 88))
    private let status = NSTextField(wrappingLabelWithString: "Ready — drag either fixture onto the robot.")
    private var root: URL!
    private var sourceURL: URL!
    private let fixtureText = "DaBin native drag fixture — selected text stays exact."
    private let fixtureBytes = Data("DaBin native drag fixture file.\nOriginal bytes must stay unchanged.\n".utf8)
    private var dropCalls = 0
    private var hoverEntries = 0
    private var operations: [UInt] = []
    private var failures: [String] = []
    private var eventCounts: [String: Int] = [:]
    private var eventTrace: [[String: Any]] = []
    private var summaryURL: URL { Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("DaBinDropQA-results.json") }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinDropQA-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            sourceURL = root.appendingPathComponent("Native drag fixture.txt")
            try fixtureBytes.write(to: sourceURL)
            store = try CaptureStore(root: root.appendingPathComponent("IsolatedArchive", isDirectory: true))
            input = InputService(store: store)
            makeWindow()
            wireInput()
            writeSummary()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } catch {
            fputs("Native drop QA setup failed: \(error)\n", stderr)
            NSApp.terminate(nil)
        }
    }

    private func label(_ text: String, frame: NSRect, size: CGFloat = 14, weight: NSFont.Weight = .regular) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.frame = frame
        label.font = .systemFont(ofSize: size, weight: weight)
        return label
    }

    private func makeWindow() {
        window = DropQAWindow(contentRect: NSRect(x: 250, y: 250, width: 640, height: 360),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "DaBin Drop QA — isolated fixtures"
        window.delegate = self
        window.isReleasedWhenClosed = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
        window.contentView = content
        window.onMouseEvent = { [weak self] event in
            self?.recordEvent(source: "window", name: String(describing: event.type), event: event)
        }
        content.addSubview(label("Direct drop into DaBin", frame: NSRect(x: 28, y: 296, width: 580, height: 32), size: 23, weight: .semibold))
        content.addSubview(label("Real native dragging • temporary archive • no personal data", frame: NSRect(x: 28, y: 267, width: 585, height: 24)))
        let text = DragFixtureView(frame: NSRect(x: 28, y: 177, width: 300, height: 64), title: "Drag text →", writer: fixtureText as NSString)
        let file = DragFixtureView(frame: NSRect(x: 28, y: 97, width: 300, height: 64), title: "Drag file →", writer: sourceURL as NSURL)
        for source in [text, file] {
            source.onEvent = { [weak self, weak source] name, event in
                guard let source else { return }
                self?.recordEvent(source: source.title, name: name, event: event)
            }
            source.onEnded = { [weak self] operation in
                self?.operations.append(operation.rawValue)
                self?.writeSummary()
            }
            content.addSubview(source)
        }
        content.addSubview(robot)
        content.addSubview(label("Drop on the robot", frame: NSRect(x: 451, y: 110, width: 165, height: 24), weight: .medium))
        status.frame = NSRect(x: 28, y: 17, width: 584, height: 64)
        status.font = .systemFont(ofSize: 13)
        content.addSubview(status)
        let menu = NSMenu()
        let appItem = NSMenuItem()
        menu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit DaBin Drop QA", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        NSApp.mainMenu = menu
    }

    private func recordEvent(source: String, name: String, event: NSEvent?) {
        let key = "\(source).\(name)"
        eventCounts[key, default: 0] += 1
        var entry: [String: Any] = ["source": source, "event": name]
        if let event {
            entry["windowX"] = event.locationInWindow.x
            entry["windowY"] = event.locationInWindow.y
        }
        eventTrace.append(entry)
        if eventTrace.count > 32 { eventTrace.removeFirst(eventTrace.count - 32) }
        writeSummary()
    }

    private func wireInput() {
        robot.onDrop = { [weak self] board in
            guard let self else { return }
            self.dropCalls += 1
            self.input.receive(board)
            self.writeSummary()
        }
        robot.onDragState = { [weak self] active in
            guard let self else { return }
            if active { self.hoverEntries += 1 }
            self.writeSummary()
        }
        input.onBusy = { [weak self] busy in self?.robot.isSaving = busy }
        input.onResult = { [weak self] captures, failures in
            guard let self else { return }
            self.failures.append(contentsOf: failures)
            self.robot.digest(success: !captures.isEmpty, partial: !failures.isEmpty)
            let names = self.store.captures.map(\.title).joined(separator: " | ")
            self.status.stringValue = "Saved \(self.store.captures.count) captures. \(names)" + (failures.isEmpty ? "" : " Errors: \(failures.joined(separator: "; "))")
            self.writeSummary()
        }
    }

    private func writeSummary() {
        guard let store, let sourceURL else { return }
        let captures: [[String: Any]] = store.captures.map { capture in
            var value: [String: Any] = ["kind": capture.kind.rawValue, "title": capture.title]
            if let text = capture.originalText { value["textExact"] = text == fixtureText }
            if let managedURL = store.managedURL(for: capture) {
                value["copiedBytesExact"] = (try? Data(contentsOf: managedURL)) == fixtureBytes
                value["sourcePathExact"] = capture.sourceFilePath == sourceURL.path
            }
            return value
        }
        let value: [String: Any] = [
            "fixtureOnly": true, "root": root.path, "captureCount": store.captures.count,
            "dropCalls": dropCalls, "acceptedHoverEntries": hoverEntries,
            "dragEndOperations": operations, "errors": failures, "captures": captures,
            "eventCounts": eventCounts, "recentEvents": eventTrace,
            "sourceFileUnchanged": (try? Data(contentsOf: sourceURL)) == fixtureBytes,
            "updatedAt": ISO8601DateFormatter().string(from: Date())
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: summaryURL, options: .atomic)
        } catch { fputs("Native drop QA summary failed: \(error)\n", stderr) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { writeSummary() }
}

@main struct NativeDropQAMain {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = NativeDropQA()
        application.setActivationPolicy(.regular)
        application.delegate = delegate
        application.run()
    }
}
