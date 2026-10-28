import AppKit
import SwiftUI

@MainActor
final class LauncherWindowController: NSWindowController, NSWindowDelegate {
    let model: LauncherModel

    private unowned let coordinator: AppCoordinator

    init(coordinator: AppCoordinator, model: LauncherModel) {
        self.coordinator = coordinator
        self.model = model

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 344),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "FileCompare"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false

        let root = LauncherView(
            model: model,
            onPick: { side in
                coordinator.pickFileForLauncher(side: side, model: model)
            },
            onCompare: {
                coordinator.compareFromLauncher(model)
            }
        )
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 700, height: 344))

        super.init(window: window)
        window.delegate = self
    }

    /// Centers the first launcher and cascades additional ones so Command-N
    /// windows never open exactly on top of each other.
    func position(cascadeIndex: Int) {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let offset = CGFloat(cascadeIndex % 6) * 28
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
        NSApp.activate()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        coordinator.launcherDidBecomeKey()
    }

    func windowWillClose(_ notification: Notification) {
        coordinator.launcherWillClose(self)
    }
}
