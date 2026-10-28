import AppKit
import SwiftUI

/// NSHostingView consumes mouse events, so window-background dragging alone is insufficient.
/// Track the pointer in screen coordinates so movement works across displays and scales.
struct WindowDragArea: NSViewRepresentable {
    var onDoubleClick: () -> Void
    var onMenu: () -> Void

    func makeNSView(context: Context) -> DragSurface { DragSurface() }

    func updateNSView(_ view: DragSurface, context: Context) {
        view.onDoubleClick = onDoubleClick
        view.onMenu = onMenu
    }

    final class DragSurface: NSView {
        var onDoubleClick: (() -> Void)?
        var onMenu: (() -> Void)?
        private var dragStart: NSPoint?
        private var windowStart: NSPoint?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }

        override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control) {
                onMenu?()
            } else if event.clickCount == 2 {
                onDoubleClick?()
            } else {
                dragStart = window?.convertPoint(toScreen: event.locationInWindow)
                windowStart = window?.frame.origin
            }
        }

        override func mouseDragged(with event: NSEvent) {
            guard let dragStart, let windowStart, let window else { return }
            let pointer = window.convertPoint(toScreen: event.locationInWindow)
            window.setFrameOrigin(NSPoint(
                x: windowStart.x + pointer.x - dragStart.x,
                y: windowStart.y + pointer.y - dragStart.y
            ))
        }

        override func mouseUp(with event: NSEvent) {
            dragStart = nil
            windowStart = nil
        }

        override func rightMouseDown(with event: NSEvent) { onMenu?() }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }
    }
}
