import AppKit
import Foundation
import SwiftUI
import Testing

@testable import FileCompare

/// Renders the SwiftUI surfaces to PNGs so the UI can be inspected without
/// screen-recording permissions. Not a pixel-comparison test; the output paths
/// are printed in the test log.
@Suite(.serialized)
@MainActor
struct SnapshotRenderTests {
    @Test func renderComparisonAndLauncher() throws {
        let originalLineNumbers = AppSettings.shared.showLineNumbers
        AppSettings.shared.showLineNumbers = false
        defer { AppSettings.shared.showLineNumbers = originalLineNumbers }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileCompareSnapshots-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let leftURL = directory.appendingPathComponent("方案甲.md")
        let rightURL = directory.appendingPathComponent("方案乙.md")
        let leftText = """
        # 项目说明

        这是一份用于比较的文档。
        第二行保持不变。
        我们今天去公园散步。
        English line with quick brown fox.
        Whitespace   here.
        Case Test.
        A very long line that should wrap when the window is narrow: https://example.com/a/very/long/path/that/keeps/going/and/going/without/spaces?parameter=value&another=value
        """
        let rightText = """
        # 项目说明

        这是一份用于比较的文档。
        第二行保持不变。
        我们明天去公园跑步。
        English line with quick red fox.
        Whitespace here.
        Case test.
        A very long line that should wrap when the window is narrow: https://example.com/a/very/long/path/that/keeps/going/and/going/without/spaces?parameter=value&another=value
        Added line.
        """
        try leftText.write(to: leftURL, atomically: true, encoding: .utf8)
        try rightText.write(to: rightURL, atomically: true, encoding: .utf8)

        let leftFile = try TextFileLoader.read(url: leftURL)
        let rightFile = try TextFileLoader.read(url: rightURL)
        let document = try DiffEngine.compare(left: leftFile, right: rightFile)

        let session = ComparisonSession(
            leftURL: leftURL,
            rightURL: rightURL,
            settings: AppSettings.shared
        )
        session.document = document
        session.isLoading = false

        let comparison = ComparisonRootView(session: session) { _ in }
            .environment(\.colorScheme, .light)
        try renderInWindow(
            comparison,
            name: "comparison-light",
            size: NSSize(width: 1120, height: 760),
            directory: directory
        )

        let dark = ComparisonRootView(session: session) { _ in }
            .environment(\.colorScheme, .dark)
        try renderInWindow(
            dark,
            name: "comparison-dark",
            size: NSSize(width: 1120, height: 760),
            directory: directory
        )

        AppSettings.shared.showLineNumbers = true
        let lines = ComparisonRootView(session: session) { _ in }
            .environment(\.colorScheme, .light)
        try renderInWindow(
            lines,
            name: "comparison-lines",
            size: NSSize(width: 1120, height: 760),
            directory: directory
        )
        AppSettings.shared.showLineNumbers = false

        session.presentFindBar()
        session.setFindQuery("公园")
        let find = ComparisonRootView(session: session) { _ in }
            .environment(\.colorScheme, .light)
        try renderInWindow(
            find,
            name: "comparison-find",
            size: NSSize(width: 1120, height: 760),
            directory: directory
        )
        session.dismissFindBar()

        let errorSession = ComparisonSession(
            leftURL: leftURL,
            rightURL: rightURL,
            settings: AppSettings.shared
        )
        errorSession.errorMessage = String(
            localized: "error.lineTooLong",
            defaultValue: "A line exceeds the supported length"
        )
        errorSession.isLoading = false
        let errorView = ComparisonRootView(session: errorSession) { _ in }
            .environment(\.colorScheme, .light)
        try renderInWindow(
            errorView,
            name: "comparison-error",
            size: NSSize(width: 1120, height: 760),
            directory: directory
        )

        let narrow = ComparisonRootView(session: session) { _ in }
            .environment(\.colorScheme, .light)
        try renderInWindow(
            narrow,
            name: "comparison-narrow",
            size: NSSize(width: 680, height: 420),
            directory: directory
        )

        let launcherModel = LauncherModel()
        launcherModel.set(leftURL, for: .left)
        launcherModel.set(rightURL, for: .right)
        let launcher = LauncherView(model: launcherModel, onPick: { _ in }, onCompare: {})
            .environment(\.colorScheme, .light)
        try renderInWindow(
            launcher,
            name: "launcher-light",
            size: NSSize(width: 700, height: 344),
            directory: directory
        )

        let emptyModel = LauncherModel()
        let emptyLauncher = LauncherView(model: emptyModel, onPick: { _ in }, onCompare: {})
            .environment(\.colorScheme, .light)
        try renderInWindow(
            emptyLauncher,
            name: "launcher-empty",
            size: NSSize(width: 700, height: 344),
            directory: directory
        )

        let zhComparison = ComparisonRootView(session: session) { _ in }
            .environment(\.colorScheme, .light)
            .environment(\.locale, Locale(identifier: "zh-Hans"))
        try renderInWindow(
            zhComparison,
            name: "comparison-zh",
            size: NSSize(width: 1120, height: 760),
            directory: directory
        )

        let zhLauncher = LauncherView(model: launcherModel, onPick: { _ in }, onCompare: {})
            .environment(\.colorScheme, .light)
            .environment(\.locale, Locale(identifier: "zh-Hans"))
        try renderInWindow(
            zhLauncher,
            name: "launcher-zh",
            size: NSSize(width: 700, height: 344),
            directory: directory
        )

        print("SNAPSHOT_DIRECTORY \(directory.path)")
    }

    /// Renders through a real NSWindow/NSHostingView instead of ImageRenderer so
    /// ScrollView, Liquid Glass and AppKit-backed content have a window to lay
    /// out against.
    private func renderInWindow<V: View>(
        _ view: V,
        name: String,
        size: NSSize,
        directory: URL
    ) throws {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.setContentSize(size)
        window.setFrameOrigin(NSPoint(x: -12_000, y: -12_000))
        window.orderFrontRegardless()

        let deadline = Date().addingTimeInterval(0.9)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        window.contentView?.layoutSubtreeIfNeeded()

        guard let content = window.contentView,
              content.bounds.width > 0,
              content.bounds.height > 0,
              let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
            Issue.record("Unable to render \(name)")
            window.orderOut(nil)
            return
        }
        content.cacheDisplay(in: content.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            Issue.record("Unable to encode \(name)")
            window.orderOut(nil)
            return
        }
        try png.write(to: directory.appendingPathComponent("\(name).png"))

        if let frameView = content.superview,
           frameView.bounds.width > 0,
           frameView.bounds.height > 0,
           let frameRep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) {
            frameView.cacheDisplay(in: frameView.bounds, to: frameRep)
            if let framePNG = frameRep.representation(using: .png, properties: [:]) {
                try? framePNG.write(to: directory.appendingPathComponent("\(name)-frame.png"))
            }
        }

        window.orderOut(nil)
    }
}
