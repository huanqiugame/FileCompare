import OSLog
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.mainMenu = MainMenu.build(coordinator: AppCoordinator.shared)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppCoordinator.shared.start()
        NSApp.activate()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        AppLog.lifecycle.notice(
            "Open event with \(urls.count) URL(s): \(urls.map(\.path).joined(separator: ", "), privacy: .public)"
        )
        AppCoordinator.shared.handleOpen(urls: urls)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppCoordinator.shared.handleReopen()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppCoordinator.shared.shutdown()
    }
}
