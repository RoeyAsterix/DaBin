import AppKit
import SwiftUI

/// A native window drag surface restricted to the heading and its adjacent space.
/// Keeping it separate from the header buttons preserves their normal mouse events.
@MainActor
struct WindowDragHandle: NSViewRepresentable {
    @Environment(\.daBinTooltipsEnabled) private var tooltipsEnabled
    var onDragStarted: (() -> Void)? = nil
    var onDragEnded: ((CGPoint) -> Void)? = nil

    func makeNSView(context: Context) -> WindowDragHandleView {
        let view = WindowDragHandleView()
        view.setAccessibilityElement(false)
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ nsView: WindowDragHandleView, context: Context) {
        nsView.toolTip = tooltipsEnabled ? "Drag to move DaBin between screens" : nil
        nsView.onDragStarted = onDragStarted
        nsView.onDragEnded = onDragEnded
    }
}

@MainActor
final class WindowDragHandleView: NSView {
    var onDragStarted: (() -> Void)?
    var onDragEnded: ((CGPoint) -> Void)?
    private var dragSession: WindowDragSession?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        guard event.type == .leftMouseDown, let window else { return }
        let pointer = window.convertPoint(toScreen: event.locationInWindow)
        onDragStarted?()
        dragSession = WindowDragSession(pointer: pointer, origin: window.frame.origin)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let dragSession else { return }
        let pointer = window.convertPoint(toScreen: event.locationInWindow)
        window.setFrameOrigin(dragSession.origin(at: pointer))
    }

    override func mouseUp(with event: NSEvent) {
        guard dragSession != nil else { return }
        dragSession = nil
        if let window { onDragEnded?(window.convertPoint(toScreen: event.locationInWindow)) }
    }

    func cancelWindowInteraction() { dragSession = nil }
}

/// Global display coordinates allow one uninterrupted drag across monitors.
struct WindowDragSession {
    let pointer: CGPoint
    let origin: CGPoint

    func origin(at current: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + current.x - pointer.x, y: origin.y + current.y - pointer.y)
    }
}
