import AppKit
import SwiftUI

@MainActor
final class ComparisonWindowController: NSWindowController, NSWindowDelegate {
    let session: ComparisonSession
    private unowned let coordinator: AppCoordinator

    init(session: ComparisonSession, coordinator: AppCoordinator) {
        self.session = session
        self.coordinator = coordinator

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = session.title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = false
        window.backgroundColor = .textBackgroundColor
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false

        let root = ComparisonRootView(session: session) { side in
            coordinator.pickFile(for: side, in: session)
        }
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 1120, height: 760))
        window.contentMinSize = NSSize(width: 340, height: 180)

        super.init(window: window)
        window.delegate = self

        observeTitle()
    }

    /// Centers the first comparison window and cascades later ones so multiple
    /// comparisons never open exactly on top of each other.
    func position(cascadeIndex: Int) {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let offset = CGFloat(cascadeIndex) * 28
        let origin = NSPoint(
            x: visible.midX - window.frame.width / 2 + offset,
            y: visible.midY - window.frame.height / 2 - offset
        )
        window.setFrameOrigin(origin)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        coordinator.comparisonDidBecomeKey(session)
    }

    func windowDidResignKey(_ notification: Notification) {
        coordinator.comparisonDidResignKey(session)
    }

    func windowWillClose(_ notification: Notification) {
        coordinator.comparisonWillClose(session)
    }

    private func observeTitle() {
        withObservationTracking {
            _ = session.title
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.window?.title = self.session.title
                self.observeTitle()
            }
        }
    }
}
