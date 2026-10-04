import AppKit
import Foundation
import SwiftUI

@MainActor private final class NativeDragFixtureState: ObservableObject {
    var opened = 0
    var secondaryClicks = 0
    var payloadRequests = 0
    var ended = 0
    var errors: [Error] = []
    var writers: [NSPasteboardWriting] = ["Fixture note" as NSString]
}

@MainActor private struct NativeDragFixture: View {
    let state: NativeDragFixtureState
    var body: some View {
        VStack(spacing: 20) {
            Button { state.opened += 1 } label: {
                Text("Fictional draggable note").frame(width: 240, height: 100).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .nativeContentDrag(label: "Fictional note", excluding: [CGRect(x: 4, y: 4, width: 44, height: 44)], items: {
                    state.payloadRequests += 1
                    return state.writers
                }, onError: { state.errors.append($0) }, onEnd: { state.ended += 1 })
            Button("Independent selection") { state.secondaryClicks += 1 }.frame(width: 240, height: 40)
        }.padding(20)
    }
}

@MainActor private final class NativeDragFixtureWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor private final class NativeDragFlippedSource: NativeContentDragView {
    override var isFlipped: Bool { true }
}

@MainActor private final class NativeDragManualState: ObservableObject {
    @Published var status = "Ready. Drag any sample into the receiver or another application."
    @Published var opens = 0
    var ended = 0
}

@MainActor private struct NativeDragManualReceiver: NSViewRepresentable {
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 140))
        text.string = "Drop fictional text or a link here.\n"
        text.isEditable = true
        text.isRichText = true
        text.font = .systemFont(ofSize: 15)
        text.autoresizingMask = [.width]
        text.setAccessibilityIdentifier("native-drag-receiver")
        text.setAccessibilityLabel("Native drag receiver")
        scroll.documentView = text
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        return scroll
    }
    func updateNSView(_ view: NSScrollView, context: Context) { }
}

@MainActor private struct NativeDragManualFixture: View {
    @ObservedObject var state: NativeDragManualState
    let file: URL

    private func source(_ title: String, identifier: String, writers: [NSPasteboardWriting]) -> some View {
        Button { state.opens += 1 } label: {
            Text(title).frame(maxWidth: .infinity, minHeight: 52).contentShape(Rectangle())
        }.buttonStyle(.bordered)
            .accessibilityIdentifier(identifier)
            .nativeContentDrag(label: title, items: {
                state.status = "Dragging \(writers.count) item(s)"
                return writers
            }, onError: { state.status = $0.localizedDescription }, onEnd: {
                state.ended += 1
                state.status = "Drag ended \(state.ended) time(s). Preview clicks: \(state.opens)."
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("DaBin native drag QA").font(.title2.bold())
            Text("All samples are fictional and local. A drag must not open its preview.")
            source("Drag text: Fictional DaBin note", identifier: "native-drag-text", writers: ["Fictional DaBin note" as NSString])
            source("Drag link: example.invalid", identifier: "native-drag-link", writers: [URL(string: "https://example.invalid/fixture")! as NSURL])
            source("Drag file: Fixture.txt", identifier: "native-drag-file", writers: [file as NSURL])
            source("Drag all three items", identifier: "native-drag-mixed", writers: ["Fictional DaBin note" as NSString,
                URL(string: "https://example.invalid/fixture")! as NSURL, file as NSURL])
            Text(state.status).accessibilityIdentifier("native-drag-status")
            Text("Preview clicks: \(state.opens)").accessibilityIdentifier("native-drag-opens")
            NativeDragManualReceiver().frame(height: 150)
        }.padding(24).frame(width: 560)
    }
}

/// All events are delivered to this process's fictional offscreen window. No
/// global pointer events, user archive, network, or general clipboard writes.
@main @MainActor private final class NativeContentDragTests: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private static var checks = 0
    private var result: Int32 = 0
    private var manualWindow: NSWindow?
    private var manualRoot: URL?

    static func main() {
        setbuf(stdout, nil)
        let app = NSApplication.shared
        let delegate = NativeContentDragTests()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
        exit(delegate.result)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["DABIN_NATIVE_DRAG_MANUAL"] == "1"
            || CommandLine.arguments.contains("--manual") {
            do { try showManualFixture() }
            catch { fputs("Native drag fixture failed: \(error)\n", stderr); exit(1) }
            return
        }
        Task {
            do { try await Self.run() }
            catch { result = 1; fputs("Native content drag QA failed: \(error)\n", stderr) }
            NSApp.stop(nil)
            NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: true)
        }
    }

    private func showManualFixture() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinNativeDragManual-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        manualRoot = root
        let file = root.appendingPathComponent("Fixture.txt")
        try Data("Fictional DaBin attachment for native drag QA.\n".utf8).write(to: file)
        let host = NSHostingView(rootView: NativeDragManualFixture(state: NativeDragManualState(), file: file))
        let window = NSWindow(contentRect: NSRect(x: 150, y: 150, width: 608, height: 610),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "DaBin Native Drag QA — fictional samples"
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.delegate = self
        manualWindow = window
        let menu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit native drag QA", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let item = NSMenuItem()
        item.submenu = appMenu
        menu.addItem(item)
        NSApp.mainMenu = menu
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) { NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        if let manualRoot { try? FileManager.default.removeItem(at: manualRoot) }
    }

    private static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        guard try value() else {
            throw NSError(domain: "NativeContentDragTests", code: checks, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private static func settle(_ view: NSView) async throws {
        for _ in 0..<5 { view.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(35)) }
    }

    private static func source(in view: NSView) -> NativeContentDragView? {
        if let source = view as? NativeContentDragView { return source }
        return view.subviews.lazy.compactMap { source(in: $0) }.first
    }

    private static func event(_ type: NSEvent.EventType, at point: NSPoint, in window: NSWindow,
                              flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: flags,
                          timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                          context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
    }

    private static func post(_ type: NSEvent.EventType, at point: NSPoint, in window: NSWindow) async throws {
        NSApp.postEvent(event(type, at: point, in: window), atStart: false)
        try await Task.sleep(for: .milliseconds(70))
    }

    private static func run() async throws {
        let clipboardRevision = NSPasteboard.general.changeCount
        let state = NativeDragFixtureState()
        let host = NSHostingView(rootView: NativeDragFixture(state: state))
        let window = NativeDragFixtureWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 320, height: 240),
                                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderBack(nil)
        defer { window.orderOut(nil); window.close() }
        try await settle(host)
        guard let source = source(in: host) else {
            throw NSError(domain: "NativeContentDragTests", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "The production SwiftUI modifier did not install its native source"])
        }
        let center = source.convert(NSPoint(x: source.bounds.midX, y: source.bounds.midY), to: nil)
        try expect(source.bounds.width == 240 && source.bounds.height == 100, "The source follows only its content surface")
        try expect(source.hitTest(source.bounds.origin) == nil, "The background never intercepts ordinary control hit testing")
        let recognizers = host.gestureRecognizers
        try expect(recognizers.count == 1, "The visible source registers one pan recognizer")
        let recognizer = recognizers[0]
        try expect(recognizer.delaysPrimaryMouseButtonEvents, "Primary events wait until click or drag is determined")
        try expect(!recognizer.delaysSecondaryMouseButtonEvents, "Context clicks remain immediate")
        try expect(source.gestureRecognizer(recognizer, shouldAttemptToRecognizeWith: event(.leftMouseDown, at: center, in: window)),
                   "The source accepts a primary press on its visible preview")
        try expect(!source.gestureRecognizer(recognizer, shouldAttemptToRecognizeWith: event(.leftMouseDown, at: center, in: window, flags: .control)),
                   "Control-click remains a context menu gesture")
        try expect(!source.gestureRecognizer(recognizer, shouldAttemptToRecognizeWith: event(.leftMouseDown, at: .zero, in: window)),
                   "Controls outside the content surface cannot start its drag")
        try expect(!source.gestureRecognizer(recognizer, shouldAttemptToRecognizeWith: event(.rightMouseDown, at: center, in: window)),
                   "Secondary presses do not start content drags")
        try expect(source.excludedRects == [CGRect(x: 4, y: 4, width: 44, height: 44)],
                   "The SwiftUI modifier passes overlay control exclusions to its native surface")
        let excludedPoint = source.convert(NSPoint(x: 20, y: source.isFlipped ? 20 : source.bounds.height - 20), to: nil)
        let adjacentPoint = source.convert(NSPoint(x: 52, y: source.isFlipped ? 20 : source.bounds.height - 20), to: nil)
        let belowPoint = source.convert(NSPoint(x: 20, y: source.isFlipped ? 80 : source.bounds.height - 80), to: nil)
        try expect(!source.gestureRecognizer(recognizer, shouldAttemptToRecognizeWith: event(.leftMouseDown, at: excludedPoint, in: window)),
                   "The top-left checkbox overlay remains outside native drag recognition")
        try expect(source.gestureRecognizer(recognizer, shouldAttemptToRecognizeWith: event(.leftMouseDown, at: adjacentPoint, in: window)),
                   "The preview next to the checkbox remains draggable")
        try expect(source.gestureRecognizer(recognizer, shouldAttemptToRecognizeWith: event(.leftMouseDown, at: belowPoint, in: window)),
                   "Top-left exclusions do not accidentally exclude the mirrored bottom-left area")
        let flippedWindow = NativeDragFixtureWindow(contentRect: NSRect(x: -21_000, y: -21_000, width: 160, height: 120),
                                                     styleMask: [.borderless], backing: .buffered, defer: false)
        flippedWindow.isReleasedWhenClosed = false
        let flippedHost = NSView(frame: NSRect(x: 0, y: 0, width: 160, height: 120))
        flippedWindow.contentView = flippedHost
        let flipped = NativeDragFlippedSource(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        flipped.excludedRects = source.excludedRects
        flippedHost.addSubview(flipped)
        let flippedExcluded = flipped.convert(NSPoint(x: 20, y: 20), to: nil)
        let flippedAdjacent = flipped.convert(NSPoint(x: 52, y: 20), to: nil)
        try expect(!flipped.gestureRecognizer(recognizer, shouldAttemptToRecognizeWith: event(.leftMouseDown, at: flippedExcluded, in: flippedWindow)),
                   "Flipped AppKit surfaces honor the same top-left exclusion coordinates")
        try expect(flipped.gestureRecognizer(recognizer, shouldAttemptToRecognizeWith: event(.leftMouseDown, at: flippedAdjacent, in: flippedWindow)),
                   "Flipped surfaces still accept the neighboring preview")
        flipped.detachRecognizer()
        flippedWindow.close()
        try expect(state.payloadRequests == 0, "Layout and hit testing do not resolve content or copy files")

        window.makeFirstResponder(host)
        try await post(.leftMouseDown, at: center, in: window)
        try await post(.leftMouseUp, at: center, in: window)
        try await settle(host)
        try expect(state.opened == 1, "A normal click still opens the SwiftUI preview exactly once (got \(state.opened))")
        try expect(state.payloadRequests == 0, "A click does not request a drag payload")

        let secondary = NSPoint(x: center.x, y: center.y - 90)
        try await post(.leftMouseDown, at: secondary, in: window)
        try await post(.leftMouseUp, at: secondary, in: window)
        try await settle(host)
        try expect(state.secondaryClicks == 1, "A neighboring control keeps its ordinary click action")
        try expect(state.payloadRequests == 0, "Clicking an independent control does not resolve drag content")
        source.isHidden = true
        try expect(!source.gestureRecognizer(recognizer, shouldAttemptToRecognizeWith: event(.leftMouseDown, at: center, in: window)),
                   "Hidden content cannot register a drag")
        source.isHidden = false
        let originalItems = source.items
        source.items = { throw NSError(domain: "FixtureMissingFile", code: 1) }
        try expect(source.beginContentDrag(with: event(.leftMouseDragged, at: center, in: window)) == nil,
                   "An unavailable payload does not start an empty misleading drag")
        try expect(state.errors.count == 1 && state.ended == 1, "Payload failure reports the error and clears caller drag state")
        source.items = { [] }
        try expect(source.beginContentDrag(with: event(.leftMouseDragged, at: center, in: window)) == nil && state.ended == 2,
                   "Empty payloads clear caller state without a native drag")
        source.items = originalItems
        state.errors.removeAll()

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinNativeDragQA-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Fixture.txt")
        let bytes = Data("Fictional local attachment".utf8)
        try bytes.write(to: file)
        state.writers = ["Fictional note" as NSString, URL(string: "https://example.invalid/fixture")! as NSURL, file as NSURL]

        try await post(.leftMouseDown, at: center, in: window)
        try await post(.leftMouseDragged, at: NSPoint(x: center.x + 35, y: center.y + 20), in: window)
        try await post(.leftMouseDragged, at: NSPoint(x: center.x + 65, y: center.y + 35), in: window)
        try await post(.leftMouseUp, at: NSPoint(x: center.x + 65, y: center.y + 35), in: window)
        try await settle(host)
        try expect(state.payloadRequests == 1, "A threshold drag requests its outgoing content once (got \(state.payloadRequests))")
        try expect(state.opened == 1, "Finishing a drag does not also open the preview")
        try expect(state.errors.isEmpty, "A valid drag has no materialization error")

        guard let session = source.activeSession else {
            throw NSError(domain: "NativeContentDragTests", code: 0, userInfo: [NSLocalizedDescriptionKey: "AppKit did not create the mixed native session"])
        }
        let values = session.draggingPasteboard.pasteboardItems ?? []
        try expect(values.count == 3, "A native session advertises three distinct mixed items (got \(values.count))")
        try expect(values[0].string(forType: .string) == "Fictional note", "The text item preserves its full value")
        try expect(values[1].string(forType: .URL) == "https://example.invalid/fixture", "The link item advertises its native URL")
        try expect(values[2].string(forType: .fileURL) == file.absoluteString, "The file item points to the existing saved original")
        try expect(source.draggingSession(session, sourceOperationMaskFor: .outsideApplication) == .copy,
                   "External applications can only copy the source content")
        try expect(source.draggingSession(session, sourceOperationMaskFor: .withinApplication).contains(.move),
                   "The application's explicit internal reorder/drop handlers retain move support")
        try expect(source.ignoreModifierKeys(for: session), "Modifier keys cannot turn an external copy into a move")
        try expect(try Data(contentsOf: file) == bytes, "Native dragging preserves the saved file bytes")
        try expect(NSPasteboard.general.changeCount == clipboardRevision, "Dragging never replaces the general clipboard")
        // The actual session above validates AppKit's drag pasteboard. Own-
        // process events cannot synthesize WindowServer release; exercise the
        // source's cancellation callback directly and leave physical drop/end
        // verification to this fixture's optional manual mode.
        let endedBeforeCancellation = state.ended
        source.draggingSession(session, endedAt: .zero, operation: [])
        try expect(source.activeSession == nil && state.ended == endedBeforeCancellation + 1,
                   "Cancellation clears the active session and informs its owning card")
        source.detachRecognizer()
        try expect(host.gestureRecognizers.isEmpty, "Dismantling the source removes its recognizer")
        print("PASS: \(checks) native content drag checks; clicks, mixed native items, copy-only external transfers and source preservation.")
    }
}
