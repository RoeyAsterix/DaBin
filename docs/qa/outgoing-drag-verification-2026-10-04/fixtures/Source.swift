import AppKit
import SwiftUI
import Foundation

@MainActor final class SourceTextReceiver: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        let scroll = NSScrollView(frame: bounds)
        let text = NSTextView(frame: NSRect(origin: .zero, size: bounds.size))
        text.string = "Same-app text receiver (optional):\n"
        text.isRichText = true; text.isEditable = true
        text.font = .systemFont(ofSize: 15); text.autoresizingMask = [.width]
        text.setAccessibilityLabel("Fixed source text receiver")
        scroll.documentView = text; scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        addSubview(scroll)
    }
    required init?(coder: NSCoder) { fatalError() }
}

@main @MainActor final class SourceApp: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var frameLabel: NSTextField!
    var statusLabel: NSTextField!
    var content: NSView!
    var sources: [(name: String, view: NSView)] = []
    var fixtureRoot: URL!
    var ended = 0
    var opens = 0
    var begins = 0
    var initialClipboardRevision = 0

    static func main() {
        let app = NSApplication.shared; let delegate = SourceApp()
        app.delegate = delegate; app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
    private func label(_ value: String, frame: NSRect, size: CGFloat = 13) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: value)
        field.frame = frame; field.font = .systemFont(ofSize: size)
        return field
    }
    private func addSource(_ title: String, name: String, y: CGFloat, writers: [NSPasteboardWriting]) {
        let button = Button { [weak self] in
            guard let self else { return }
            opens += 1; updateStatus("Preview clicked")
        } label: {
            Text(title).frame(width: 518, height: 44).contentShape(Rectangle())
        }.buttonStyle(.bordered)
            .accessibilityLabel(title).accessibilityIdentifier("source-fixed-\(name)")
            .nativeContentDrag(label: title, items: { [weak self] in
                guard let self else { return [] }
                begins += 1
                updateStatus("Dragging \(name): \(writers.count) item(s)")
                trace("begin-\(name)")
                return writers
            }, onError: { [weak self] error in
                self?.updateStatus("Error: \(error.localizedDescription)")
            }, onEnd: { [weak self] in
                guard let self else { return }
                ended += 1; updateStatus("Drag ended")
                trace("end-\(name)")
            }).frame(width: 530, height: 56)
        let host = NSHostingView(rootView: button)
        host.frame = NSRect(x: 20, y: y, width: 530, height: 56)
        content.addSubview(host)
        sources.append((name, host))
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            initialClipboardRevision = NSPasteboard.general.changeCount
            fixtureRoot = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("DaBinNativeDragManual-\(UUID())", isDirectory: true)
            try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
            let file = fixtureRoot.appendingPathComponent("Fixture.txt")
            try Data("Fictional DaBin attachment for native drag QA.\n".utf8).write(to: file)
            window = NSWindow(contentRect: NSRect(x: 150, y: 150, width: 570, height: 730),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "DaBin Native Drag Source Verification — fictional samples"
            window.isReleasedWhenClosed = false; window.delegate = self
            content = NSView(frame: NSRect(x: 0, y: 0, width: 570, height: 730))
            window.contentView = content
            content.addSubview(label("DaBin Native Drag Source Verification", frame: NSRect(x: 20, y: 685, width: 530, height: 28), size: 20))
            content.addSubview(label("Actual production drag bridge · fixed geometry · fictional local samples", frame: NSRect(x: 20, y: 653, width: 530, height: 26), size: 12))
            frameLabel = label("Frame pending", frame: NSRect(x: 20, y: 500, width: 530, height: 145), size: 12)
            frameLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            frameLabel.setAccessibilityIdentifier("source-fixed-coordinates")
            content.addSubview(frameLabel)
            addSource("Drag text: Fictional DaBin note", name: "text", y: 436, writers: ["Fictional DaBin note" as NSString])
            addSource("Drag link: example.invalid", name: "link", y: 366, writers: [URL(string: "https://example.invalid/fixture")! as NSURL])
            addSource("Drag file: Fixture.txt", name: "file", y: 296, writers: [file as NSURL])
            addSource("Drag all three items", name: "mixed", y: 226, writers: ["Fictional DaBin note" as NSString,
                URL(string: "https://example.invalid/fixture")! as NSURL, file as NSURL])
            statusLabel = label("Ready", frame: NSRect(x: 20, y: 164, width: 530, height: 52), size: 13)
            statusLabel.setAccessibilityIdentifier("source-fixed-status")
            content.addSubview(statusLabel)
            content.addSubview(SourceTextReceiver(frame: NSRect(x: 20, y: 20, width: 530, height: 135)))
            let menu = NSMenu(); let appMenu = NSMenu(); let item = NSMenuItem()
            appMenu.addItem(withTitle: "Quit fixed source", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            item.submenu = appMenu; menu.addItem(item); NSApp.mainMenu = menu
            window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            updateFrame(); updateStatus("Ready"); trace("ready")
        } catch { fputs("Source fixture failed: \(error)\n", stderr); NSApp.terminate(nil) }
    }
    func updateStatus(_ value: String) {
        statusLabel.stringValue = "\(value). Begins: \(begins), ends: \(ended), preview clicks: \(opens).\nClipboard unchanged: \(NSPasteboard.general.changeCount == initialClipboardRevision)."
    }
    func updateFrame() {
        guard let frameLabel else { return }
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let rect = window.frame
        var lines = ["AppKit window x=\(Int(rect.minX)) y=\(Int(rect.minY)) w=\(Int(rect.width)) h=\(Int(rect.height))",
            "Global top-left window x=\(Int(rect.minX)) y=\(Int(primaryTop - rect.maxY))"]
        for source in sources {
            let box = window.convertToScreen(source.view.convert(source.view.bounds, to: nil))
            lines.append("\(source.name.uppercased()) global center x=\(Int(box.midX)) y=\(Int(primaryTop - box.midY))")
        }
        frameLabel.stringValue = lines.joined(separator: "\n")
        trace("window-frame")
    }
    func trace(_ name: String) {
        guard let fixtureRoot, let window else { return }
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let mouse = NSEvent.mouseLocation
        var record: [String: Any] = ["event": name, "time": ISO8601DateFormatter().string(from: Date()),
            "windowFrameAppKit": [window.frame.minX, window.frame.minY, window.frame.width, window.frame.height],
            "mouseGlobalAppKit": [mouse.x, mouse.y], "mouseGlobalTopLeft": [mouse.x, primaryTop - mouse.y],
            "begins": begins, "ends": ended, "previewClicks": opens]
        record["sourceFramesGlobalTopLeft"] = sources.map { source -> [String: Any] in
            let box = window.convertToScreen(source.view.convert(source.view.bounds, to: nil))
            return ["source": source.name, "x": box.minX, "y": primaryTop - box.maxY,
                    "width": box.width, "height": box.height, "centerX": box.midX, "centerY": primaryTop - box.midY]
        }
        do {
            var data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]); data.append(0x0a)
            let url = fixtureRoot.appendingPathComponent("source-events.jsonl")
            if !FileManager.default.fileExists(atPath: url.path) { try Data().write(to: url) }
            let handle = try FileHandle(forWritingTo: url); try handle.seekToEnd()
            try handle.write(contentsOf: data); try handle.close()
        } catch { fputs("Trace failed: \(error)\n", stderr) }
    }
    func windowDidMove(_ notification: Notification) { updateFrame() }
    func windowWillClose(_ notification: Notification) { NSApp.terminate(nil) }
}
