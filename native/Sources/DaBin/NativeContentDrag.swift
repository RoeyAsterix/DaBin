import AppKit
import SwiftUI

extension View {
    /// Attach to a preview, title, or another content surface. Keep independent
    /// controls (selection, completion, menus and text editors) outside it, or
    /// reserve their rectangles using SwiftUI's top-left coordinate space.
    @MainActor
    func nativeContentDrag(label: String,
                           excluding: [CGRect] = [],
                           items: @escaping @MainActor () throws -> [NSPasteboardWriting],
                           onError: @escaping @MainActor (Error) -> Void,
                           onEnd: @escaping @MainActor () -> Void = {}) -> some View {
        background(NativeContentDragSurface(label: label, excluding: excluding, items: items, onError: onError, onEnd: onEnd))
    }
}

@MainActor
private struct NativeContentDragSurface: NSViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    let label: String
    let excluding: [CGRect]
    let items: () throws -> [NSPasteboardWriting]
    let onError: (Error) -> Void
    let onEnd: () -> Void

    func makeNSView(context: Context) -> NativeContentDragView {
        let view = NativeContentDragView()
        view.setAccessibilityElement(false)
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: NativeContentDragView, context: Context) {
        view.isDragEnabled = isEnabled
        view.dragLabel = label
        view.excludedRects = excluding
        view.items = items
        view.onError = onError
        view.onEnd = onEnd
    }

    static func dismantleNSView(_ view: NativeContentDragView, coordinator: ()) {
        view.detachRecognizer()
    }
}

/// SwiftUI's onDrag publishes one provider. AppKit's session instead preserves
/// every selected item as its own native pasteboard object, including mixtures
/// of files, links and text. The background never takes a mouse hit: a scoped
/// pan recognizer delays only primary mouse events until it either recognizes
/// dragging or fails, in which case AppKit delivers the ordinary click.
@MainActor
class NativeContentDragView: NSView, NSGestureRecognizerDelegate, NSDraggingSource {
    var dragLabel = "Item"
    var isDragEnabled = true
    var excludedRects: [CGRect] = []
    var items: () throws -> [NSPasteboardWriting] = { [] }
    var onError: (Error) -> Void = { _ in }
    var onEnd: () -> Void = { }
    private(set) var activeSession: NSDraggingSession?
    private var pan: NativeContentPanGesture?
    private weak var recognizerHost: NSView?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attachRecognizer()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        attachRecognizer()
    }

    private func attachRecognizer() {
        guard let host = window?.contentView, superview != nil else {
            detachRecognizer()
            return
        }
        guard host !== recognizerHost else { return }
        detachRecognizer()
        let recognizer = NativeContentPanGesture(target: self, action: #selector(dragRecognized(_:)))
        recognizer.buttonMask = 1
        recognizer.delaysPrimaryMouseButtonEvents = true
        recognizer.delegate = self
        host.addGestureRecognizer(recognizer)
        recognizerHost = host
        pan = recognizer
    }

    func detachRecognizer() {
        if let pan { recognizerHost?.removeGestureRecognizer(pan) }
        pan = nil
        recognizerHost = nil
    }

    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer,
                           shouldAttemptToRecognizeWith event: NSEvent) -> Bool {
        guard isDragEnabled, event.type == .leftMouseDown, event.window === window,
              !event.modifierFlags.contains(.control), !isHiddenOrHasHiddenAncestor,
              window?.attachedSheet == nil else { return false }
        let point = convert(event.locationInWindow, from: nil)
        let region = bounds.intersection(visibleRect)
        let topLeftPoint = CGPoint(x: point.x - bounds.minX,
                                   y: isFlipped ? point.y - bounds.minY : bounds.maxY - point.y)
        return !region.isEmpty && region.contains(point)
            && !excludedRects.contains { $0.contains(topLeftPoint) }
    }

    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer,
                           shouldBeRequiredToFailBy otherGestureRecognizer: NSGestureRecognizer) -> Bool {
        // SwiftUI buttons otherwise claim the press before a pan can cross its
        // threshold. Their click waits for this scoped pan to fail on mouse-up.
        true
    }

    @objc private func dragRecognized(_ recognizer: NativeContentPanGesture) {
        guard recognizer.state == .began, let event = recognizer.lastMouseEvent else { return }
        _ = beginContentDrag(with: event)
    }

    /// Payloads are resolved only after the user actually begins dragging.
    /// This method never changes the general clipboard or any source record.
    @discardableResult
    func beginContentDrag(with event: NSEvent) -> NSDraggingSession? {
        guard isDragEnabled, window != nil, activeSession == nil else { return nil }
        do {
            let writers = try items()
            guard !writers.isEmpty else { onEnd(); return nil }
            let image = dragImage(count: writers.count)
            let point = convert(event.locationInWindow, from: nil)
            let draggingItems = writers.enumerated().map { index, writer in
                let item = NSDraggingItem(pasteboardWriter: writer)
                // A compact stack communicates a multi-item transfer without
                // allocating screenshots or loading full-size source images.
                let offset = CGFloat(min(index, 4)) * 3
                item.setDraggingFrame(NSRect(x: point.x + offset, y: point.y - image.size.height + offset,
                                             width: image.size.width, height: image.size.height), contents: image)
                return item
            }
            let session = beginDraggingSession(with: draggingItems, event: event, source: self)
            session.draggingFormation = .pile
            session.animatesToStartingPositionsOnCancelOrFail = true
            return session
        } catch {
            onError(error)
            onEnd()
            return nil
        }
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : [.copy, .move]
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        activeSession = session
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        activeSession = nil
        onEnd()
    }

    private func dragImage(count: Int) -> NSImage {
        let title = count == 1 ? dragLabel : "\(count) items"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        let text = NSAttributedString(string: String(title.prefix(64)), attributes: attributes)
        let size = NSSize(width: min(300, max(96, text.size().width + 30)), height: 36)
        return NSImage(size: size, flipped: false) { rect in
            NSColor.windowBackgroundColor.withAlphaComponent(0.96).setFill()
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 9, yRadius: 9)
            path.fill()
            NSColor.separatorColor.setStroke()
            path.stroke()
            text.draw(in: NSRect(x: 14, y: 9, width: rect.width - 28, height: 18))
            return true
        }
    }
}

@MainActor
private final class NativeContentPanGesture: NSPanGestureRecognizer {
    private(set) var lastMouseEvent: NSEvent?

    override func mouseDown(with event: NSEvent) {
        lastMouseEvent = event
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        lastMouseEvent = event
        super.mouseDragged(with: event)
    }

    override func reset() {
        super.reset()
        lastMouseEvent = nil
    }
}
