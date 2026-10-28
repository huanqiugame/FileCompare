import AppKit
import SwiftUI

/// A transparent AppKit hit area laid over a filename.
///
/// SwiftUI's tap gesture can't distinguish a click from a window drag: once the
/// window follows the pointer, the text moves with it, so the tap still looks
/// stationary. This view tracks the pointer in screen space instead: a short
/// press opens the file picker, while a real drag moves the window.
struct FilenameInteractionView: NSViewRepresentable {
    let onClick: () -> Void

    func makeNSView(context: Context) -> InteractionView {
        let view = InteractionView()
        view.onClick = onClick
        return view
    }

    func updateNSView(_ nsView: InteractionView, context: Context) {
        nsView.onClick = onClick
    }

    final class InteractionView: NSView {
        private static let dragThreshold: CGFloat = 4

        var onClick: (() -> Void)?

        private var mouseDownLocation: NSPoint?
        private var didDrag = false

        override var mouseDownCanMoveWindow: Bool { false }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setAccessibilityElement(false)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func mouseDown(with event: NSEvent) {
            mouseDownLocation = NSEvent.mouseLocation
            didDrag = false
            window?.isMovable = true
        }

        override func mouseDragged(with event: NSEvent) {
            guard !didDrag, let start = mouseDownLocation else { return }
            let current = NSEvent.mouseLocation
            guard hypot(current.x - start.x, current.y - start.y) >= Self.dragThreshold else {
                return
            }

            didDrag = true
            mouseDownLocation = nil
            window?.performDrag(with: event)
        }

        override func mouseUp(with event: NSEvent) {
            let wasDragged = didDrag
            mouseDownLocation = nil
            guard !wasDragged else { return }
            onClick?()
        }
    }
}
