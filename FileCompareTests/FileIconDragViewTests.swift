import AppKit
import Testing

@testable import FileCompare

@Suite
@MainActor
struct FileIconDragViewTests {
    @Test func iconUsesRequestedSizeInsteadOfImageSize() {
        let view = FileIconDragView.DraggingIconView()
        let url = URL(fileURLWithPath: "/System/Applications/TextEdit.app")

        view.configure(url: url, size: 13)

        #expect(view.intrinsicContentSize == NSSize(width: 13, height: 13))
    }

    @Test func iconNeverMovesTheWindow() {
        let view = FileIconDragView.DraggingIconView()

        #expect(view.mouseDownCanMoveWindow == false)
    }

    @Test func iconAcceptsTheFirstClickInAnInactiveWindow() {
        let view = FileIconDragView.DraggingIconView()

        #expect(view.acceptsFirstMouse(for: nil))
    }

    @Test func iconDelaysWindowOrderingForAnInactiveWindowDrag() throws {
        let view = FileIconDragView.DraggingIconView()
        let event = try #require(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
        )

        #expect(view.shouldDelayWindowOrdering(for: event))
    }
}
