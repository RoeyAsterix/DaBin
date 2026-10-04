import AppKit
import CryptoKit
import Foundation

@MainActor final class ReceiverState {
    let output: URL
    var onStatus: (String) -> Void = { _ in }
    init(output: URL) { self.output = output }
    func status(_ value: String) { onStatus(value) }
    func trace(_ name: String, sender: NSDraggingInfo? = nil, view: NSView? = nil) {
        var record: [String: Any] = ["event": name, "time": ISO8601DateFormatter().string(from: Date())]
        let mouse = NSEvent.mouseLocation
        record["globalMouseAppKit"] = [mouse.x, mouse.y]
        if let sender {
            record["sequence"] = sender.draggingSequenceNumber
            record["sourceMask"] = sender.draggingSourceOperationMask.rawValue
            record["locationInDestinationWindow"] = [sender.draggingLocation.x, sender.draggingLocation.y]
        }
        if let view, let window = view.window {
            record["destinationWindowFrameAppKit"] = [window.frame.minX, window.frame.minY, window.frame.width, window.frame.height]
            let rect = window.convertToScreen(view.convert(view.bounds, to: nil))
            let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
            record["targetFrameAppKit"] = [rect.minX, rect.minY, rect.width, rect.height]
            record["targetFrameGlobalTopLeft"] = [rect.minX, primaryTop - rect.maxY, rect.width, rect.height]
        }
        do {
            var data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
            data.append(0x0a)
            let url = output.appendingPathComponent("events.jsonl")
            if !FileManager.default.fileExists(atPath: url.path) { try Data().write(to: url) }
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd(); try handle.write(contentsOf: data); try handle.close()
        } catch { fputs("Trace failed: \(error)\n", stderr) }
    }
}

@MainActor final class FileDropView: NSView {
    let state: ReceiverState
    init(frame: NSRect, state: ReceiverState) {
        self.state = state
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, .URL, .string, .png, .tiff])
        setAccessibilityElement(true); setAccessibilityRole(.group)
        setAccessibilityLabel("Fixed native file and mixed-item drop target")
        setAccessibilityIdentifier("external-fixed-file-drop")
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
        box.fill(); NSColor.systemBlue.setStroke(); box.lineWidth = 2; box.stroke()
        let style = NSMutableParagraphStyle(); style.alignment = .center
        "DROP FILES OR MIXED ITEMS HERE\nFixed native target; no layout changes while dragging".draw(
            in: bounds.insetBy(dx: 14, dy: 42), withAttributes: [.font: NSFont.systemFont(ofSize: 16),
                .foregroundColor: NSColor.labelColor, .paragraphStyle: style])
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        state.trace("entered", sender: sender, view: self)
        state.status("Drag entered. Source mask: \(sender.draggingSourceOperationMask.rawValue). Waiting for mouse release.")
        return sender.draggingSourceOperationMask.contains(.copy) ? .copy : []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        state.trace("updated", sender: sender, view: self)
        return sender.draggingSourceOperationMask.contains(.copy) ? .copy : []
    }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        state.trace("exited", sender: sender, view: self)
        state.status("Drag exited the file target.")
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        state.trace("prepare", sender: sender, view: self)
        state.status("Preparing accepted drop.")
        return true
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        state.trace("perform", sender: sender, view: self)
        do {
            let items = sender.draggingPasteboard.pasteboardItems ?? []
            var records: [[String: Any]] = []
            var fileCount = 0
            for item in items {
                if let raw = item.string(forType: .fileURL), let url = URL(string: raw), url.isFileURL {
                    let resolved = url.resolvingSymlinksInPath()
                    guard resolved.lastPathComponent == "Fixture.txt",
                          resolved.deletingLastPathComponent().lastPathComponent.hasPrefix("DaBinNativeDragManual-") else {
                        throw NSError(domain: "FixtureOnly", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "QA receiver only accepts fictional Fixture.txt source."])
                    }
                    let info = try resolved.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                    guard info.isRegularFile == true, (info.fileSize ?? Int.max) < 1_000_000 else { throw NSError(domain: "FixtureOnly", code: 2) }
                    let destination = state.output.appendingPathComponent("\(UUID().uuidString)-Fixture.txt")
                    try FileManager.default.copyItem(at: resolved, to: destination)
                    let sourceHash = SHA256.hash(data: try Data(contentsOf: resolved)).map { String(format: "%02x", $0) }.joined()
                    let copyHash = SHA256.hash(data: try Data(contentsOf: destination)).map { String(format: "%02x", $0) }.joined()
                    guard sourceHash == copyHash else { throw NSError(domain: "HashMismatch", code: 1) }
                    records.append(["kind": "file", "source": resolved.path, "copy": destination.path,
                        "sourceSHA256": sourceHash, "copySHA256": copyHash,
                        "originalStillExists": FileManager.default.fileExists(atPath: resolved.path)])
                    fileCount += 1
                } else if let raw = item.string(forType: .URL) {
                    guard raw.hasPrefix("https://example.invalid/") else { throw NSError(domain: "FixtureOnly", code: 3) }
                    records.append(["kind": "link", "value": raw])
                } else if let text = item.string(forType: .string) {
                    guard text.hasPrefix("Fictional") else { throw NSError(domain: "FixtureOnly", code: 4) }
                    records.append(["kind": "text", "value": text])
                }
            }
            guard !records.isEmpty else { throw NSError(domain: "NoNativeItems", code: 1) }
            let receipt: [String: Any] = ["receivedAt": ISO8601DateFormatter().string(from: Date()),
                "sourceOperationMask": sender.draggingSourceOperationMask.rawValue,
                "pasteboardItemCount": items.count, "received": records, "fileCount": fileCount]
            let receiptURL = state.output.appendingPathComponent("receipt-\(UUID().uuidString).json")
            try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys]).write(to: receiptURL)
            state.status("Received \(records.count) native item(s), including \(fileCount) file copies. Hashes match; originals preserved. Mask: \(sender.draggingSourceOperationMask.rawValue).")
            state.trace("success", sender: sender, view: self)
            return true
        } catch {
            state.status("Drop failed: \(error.localizedDescription)")
            state.trace("failure-\(error.localizedDescription)", sender: sender, view: self)
            return false
        }
    }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) { state.trace("conclude", sender: sender, view: self) }
    override func draggingEnded(_ sender: NSDraggingInfo) { state.trace("ended", sender: sender, view: self) }
}

@MainActor final class TracedTextView: NSTextView {
    var state: ReceiverState!
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        state.trace("text-entered", sender: sender, view: self)
        return super.draggingEntered(sender)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        state.trace("text-perform", sender: sender, view: self)
        let accepted = super.performDragOperation(sender)
        state.status("Native text receiver accepted: \(accepted).")
        return accepted
    }
}

@main @MainActor final class ReceiverApp: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var state: ReceiverState!
    var frameLabel: NSTextField!
    var target: FileDropView!
    var text: TracedTextView!
    static func main() {
        let app = NSApplication.shared; let delegate = ReceiverApp()
        app.delegate = delegate; app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
    private func label(_ value: String, frame: NSRect, size: CGFloat = 13) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: value)
        field.frame = frame; field.font = .systemFont(ofSize: size)
        return field
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let output = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("dabin-native-drop-receiver-fixed-\(UUID())", isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            state = ReceiverState(output: output)
            window = NSWindow(contentRect: NSRect(x: 760, y: 150, width: 560, height: 650),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "DaBin External Drop Receiver Verification — fictional samples"
            window.isReleasedWhenClosed = false; window.delegate = self
            let content = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 650))
            window.contentView = content
            content.addSubview(label("DaBin External Drop Receiver Verification", frame: NSRect(x: 20, y: 600, width: 520, height: 30), size: 20))
            content.addSubview(label("Separate app · fixed AppKit geometry · fictional samples only", frame: NSRect(x: 20, y: 566, width: 520, height: 25)))
            frameLabel = label("Frame pending", frame: NSRect(x: 20, y: 492, width: 520, height: 70), size: 11)
            frameLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            frameLabel.setAccessibilityIdentifier("fixed-receiver-frame")
            content.addSubview(frameLabel)
            let scroll = NSScrollView(frame: NSRect(x: 20, y: 335, width: 520, height: 145))
            text = TracedTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 145))
            text.state = state; text.string = "External native text receiver:\n"
            text.isEditable = true; text.isRichText = true; text.font = .systemFont(ofSize: 16)
            text.autoresizingMask = [.width]
            text.setAccessibilityLabel("Fixed external text receiver"); text.setAccessibilityIdentifier("external-fixed-text-receiver")
            scroll.documentView = text; scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
            content.addSubview(scroll)
            target = FileDropView(frame: NSRect(x: 20, y: 170, width: 520, height: 145), state: state)
            content.addSubview(target)
            let status = label("Ready for drop.", frame: NSRect(x: 20, y: 98, width: 520, height: 62), size: 14)
            status.setAccessibilityIdentifier("fixed-receiver-status")
            content.addSubview(status)
            state.onStatus = { [weak status] in status?.stringValue = $0 }
            let outputLabel = label("QA output: \(output.path)", frame: NSRect(x: 20, y: 16, width: 520, height: 72), size: 11)
            outputLabel.isSelectable = true; content.addSubview(outputLabel)
            let menu = NSMenu(); let appMenu = NSMenu(); let item = NSMenuItem()
            appMenu.addItem(withTitle: "Quit fixed drop receiver", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            item.submenu = appMenu; menu.addItem(item); NSApp.mainMenu = menu
            window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            updateFrame(); state.trace("ready", view: target)
        } catch { fputs("Fixture failed: \(error)\n", stderr); NSApp.terminate(nil) }
    }
    func updateFrame() {
        guard let frameLabel, let target else { return }
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let rect = window.frame
        let drop = window.convertToScreen(target.convert(target.bounds, to: nil))
        frameLabel.stringValue = "AppKit window x=\(Int(rect.minX)) y=\(Int(rect.minY)) w=\(Int(rect.width)) h=\(Int(rect.height))\nGlobal top-left window x=\(Int(rect.minX)) y=\(Int(primaryTop - rect.maxY))\nFile target global top-left x=\(Int(drop.minX)) y=\(Int(primaryTop - drop.maxY)) w=\(Int(drop.width)) h=\(Int(drop.height))\nFile target global center x=\(Int(drop.midX)) y=\(Int(primaryTop - drop.midY))"
        state.trace("window-frame", view: target)
    }
    func windowDidMove(_ notification: Notification) { if state != nil { updateFrame() } }
    func windowWillClose(_ notification: Notification) { NSApp.terminate(nil) }
}
