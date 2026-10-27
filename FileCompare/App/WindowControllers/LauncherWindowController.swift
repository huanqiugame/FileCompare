import AppKit
import SwiftUI

@MainActor
final class LauncherWindowController: NSWindowController, NSWindowDelegate {
    private unowned let coordinator: AppCoordinator

    init(coordinator: AppCoordinator, model: LauncherModel) {
        self.coordinator = coordinator

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
                coordinator.pickFileForLauncher(side: side)
            },
            onCompare: {
                coordinator.compareFromLauncher()
            }
        )
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 700, height: 344))

        super.init(window: window)
        window.delegate = self
        window.center()
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
        coordinator.launcherWillClose()
    }
}
