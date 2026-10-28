import AppKit
import Foundation
import Testing

@testable import FileCompare

@Suite(.serialized)
@MainActor
struct WindowLayoutTests {
    @Test func comparisonWindowCanShrinkToACompactSize() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileCompareLayout-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let leftURL = directory.appendingPathComponent("left.txt")
        let rightURL = directory.appendingPathComponent("right.txt")
        try "left\n".write(to: leftURL, atomically: true, encoding: .utf8)
        try "right\n".write(to: rightURL, atomically: true, encoding: .utf8)

        let session = ComparisonSession(
            leftURL: leftURL,
            rightURL: rightURL,
            settings: AppSettings.shared
        )
        let controller = ComparisonWindowController(session: session, coordinator: AppCoordinator.shared)
        defer { controller.window?.orderOut(nil) }

        // The window must be allowed to shrink well below its opening size.
        let minimum = try #require(controller.window?.contentMinSize)
        #expect(minimum.width <= 400)
        #expect(minimum.height <= 240)
    }

    @Test func commandNOpensAnAdditionalLauncherWindow() {
        let coordinator = AppCoordinator.shared
        let existing = Set(NSApp.windows.map { ObjectIdentifier($0) })

        coordinator.newLauncherWindow(nil)
        coordinator.newLauncherWindow(nil)

        let added = NSApp.windows.filter { !existing.contains(ObjectIdentifier($0)) }
        #expect(added.count == 2)
        #expect(added.allSatisfy { $0.title == "FileCompare" })

        for window in added {
            window.performClose(nil)
        }
    }
}
