import AppKit
import SwiftUI

/// A native window drag surface restricted to the heading and its adjacent space.
/// Keeping it separate from the header buttons preserves their normal mouse events.
@MainActor
struct WindowDragHandle: NSViewRepresentable {
    var onDragStarted: (() -> Void)? = nil

    func makeNSView(context: Context) -> WindowDragHandleView {
        let view = WindowDragHandleView()
        view.toolTip = "Drag to move DaBin"
        view.setAccessibilityElement(false)
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ nsView: WindowDragHandleView, context: Context) {
        nsView.onDragStarted = onDragStarted
    }
}

@MainActor
final class WindowDragHandleView: NSView {
    var onDragStarted: (() -> Void)?
    private var dragOrigin: (pointer: NSPoint, window: NSPoint)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        guard event.type == .leftMouseDown, let window else { return }
        dragOrigin = (window.convertPoint(toScreen: event.locationInWindow), window.frame.origin)
        onDragStarted?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let origin = dragOrigin else { return }
        let pointer = window.convertPoint(toScreen: event.locationInWindow)
        window.setFrameOrigin(NSPoint(x: origin.window.x + pointer.x - origin.pointer.x,
                                     y: origin.window.y + pointer.y - origin.pointer.y))
    }

    override func mouseUp(with event: NSEvent) {
        dragOrigin = nil
    }
}
