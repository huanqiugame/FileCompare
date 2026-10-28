import AppKit
import SwiftUI

/// A small file icon that can be dragged out of the window as a file.
///
/// The icon is backed by a real AppKit view instead of SwiftUI's `onDrag` so
/// the drag session can start reliably inside the title strip. While the
/// pointer is over the icon the window is made immovable, which keeps the
/// native title-bar drag from stealing the gesture.
struct FileIconDragView: NSViewRepresentable {
    let url: URL
    let size: CGFloat

    func makeNSView(context: Context) -> DraggingIconView {
        let view = DraggingIconView()
        view.configure(url: url, size: size)
        return view
    }

    func updateNSView(_ nsView: DraggingIconView, context: Context) {
        nsView.configure(url: url, size: size)
    }

    final class DraggingIconView: NSImageView, NSDraggingSource {
        private static let dragThreshold: CGFloat = 4

        private var url: URL?
        private var iconSize: CGFloat = 13
        private var mouseDownEvent: NSEvent?
        private var isDragging = false
        private var iconURL: URL?
        private var hoverTrackingArea: NSTrackingArea?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            imageScaling = .scaleProportionallyUpOrDown
            imageFrameStyle = .none
            setAccessibilityElement(false)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        /// NSImageView reports the image's full size as its intrinsic size, which
        /// makes SwiftUI lay it out at 32pt regardless of the requested frame.
        override var intrinsicContentSize: NSSize {
            NSSize(width: iconSize, height: iconSize)
        }

        /// Only the icon is a file drag source, never a window drag surface.
        override var mouseDownCanMoveWindow: Bool { false }

        /// The icon stays draggable even when its window is inactive.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        /// Treat a click on the icon as a potential drag, so AppKit defers the
        /// window raise until we decide whether the drag actually starts.
        override func shouldDelayWindowOrdering(for event: NSEvent) -> Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard !isHidden else { return nil }
            return super.hitTest(point)
        }

        func configure(url: URL, size: CGFloat) {
            self.url = url
            if iconSize != size {
                iconSize = size
                invalidateIntrinsicContentSize()
            }
            if iconURL != url {
                iconURL = url
                image = NSWorkspace.shared.icon(forFile: url.path)
            }
        }

        // MARK: - Window movability

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let hoverTrackingArea {
                removeTrackingArea(hoverTrackingArea)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            hoverTrackingArea = area

            if let window {
                let mouse = convert(window.mouseLocationOutsideOfEventStream, from: nil)
                if bounds.contains(mouse) {
                    window.isMovable = false
                }
            }
        }

        override func mouseEntered(with event: NSEvent) {
            disableWindowMovement()
        }

        override func mouseExited(with event: NSEvent) {
            restoreWindowMovementIfPossible()
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil {
                window?.isMovable = true
            }
            super.viewWillMove(toWindow: newWindow)
        }

        private func disableWindowMovement() {
            window?.isMovable = false
        }

        private func restoreWindowMovementIfPossible() {
            guard let window, mouseDownEvent == nil, !isDragging else { return }
            let mouse = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            if !bounds.contains(mouse) {
                window.isMovable = true
            }
        }

        // MARK: - Dragging

        override func mouseDown(with event: NSEvent) {
            guard !isHidden else { return }
            // Keep the click from raising/activating an inactive window while
            // the user drags the file out of it.
            NSApp.preventWindowOrdering()
            mouseDownEvent = event
            isDragging = false
            disableWindowMovement()
            setPressedState()
        }

        override func mouseDragged(with event: NSEvent) {
            guard !isDragging, let down = mouseDownEvent, let url else { return }
            let dx = event.locationInWindow.x - down.locationInWindow.x
            let dy = event.locationInWindow.y - down.locationInWindow.y
            guard hypot(dx, dy) >= Self.dragThreshold else { return }

            isDragging = true
            resetPressedState()

            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = image ?? NSWorkspace.shared.icon(forFile: url.path)
            item.setDraggingFrame(bounds, contents: icon)

            let session = beginDraggingSession(with: [item], event: down, source: self)
            session.draggingFormation = .none
            session.animatesToStartingPositionsOnCancelOrFail = true
        }

        override func mouseUp(with event: NSEvent) {
            isDragging = false
            mouseDownEvent = nil
            resetPressedState()
            restoreWindowMovementIfPossible()
        }

        private func setPressedState() {
            alphaValue = 0.55
        }

        private func resetPressedState() {
            alphaValue = 1
        }

        // MARK: - NSDraggingSource

        func draggingSession(
            _ session: NSDraggingSession,
            sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {
            .copy
        }

        func draggingSession(
            _ session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            operation: NSDragOperation
        ) {
            isDragging = false
            mouseDownEvent = nil
            resetPressedState()
            restoreWindowMovementIfPossible()
        }
    }
}
