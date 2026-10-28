import OSLog
import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppCoordinator: NSObject, NSMenuItemValidation {
    static let shared = AppCoordinator()

    private(set) var activeSession: ComparisonSession?
    private(set) var settings: AppSettings
    private let launcherModel = LauncherModel()

    private var launcherController: LauncherWindowController?
    private var comparisonControllers: [UUID: ComparisonWindowController] = [:]
    private var pendingOpenURLs: [URL] = []
    private var didStart = false

    private override init() {
        self.settings = .shared
        super.init()
    }

    // MARK: - Lifecycle

    func start() {
        guard !didStart else { return }
        didStart = true

        if pendingOpenURLs.isEmpty {
            showLauncher()
        } else {
            let urls = pendingOpenURLs
            pendingOpenURLs.removeAll()
            processOpen(urls: urls)
        }
    }

    func shutdown() {
        for controller in comparisonControllers.values {
            controller.session.setAutoReload(false)
        }
    }

    func handleReopen() {
        if comparisonControllers.isEmpty {
            showLauncher()
        } else {
            for controller in comparisonControllers.values {
                controller.window?.deminiaturize(nil)
                controller.window?.orderFront(nil)
            }
            NSApp.activate()
        }
    }

    func handleOpen(urls: [URL]) {
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty else { return }

        guard didStart else {
            pendingOpenURLs.append(contentsOf: files)
            return
        }
        processOpen(urls: files)
    }

    private func processOpen(urls: [URL]) {
        AppLog.lifecycle.notice("Processing \(urls.count) file(s) after launch")
        switch urls.count {
        case 0:
            return
        case 1:
            showLauncher(left: urls[0])
        default:
            var index = 0
            while index + 1 < urls.count {
                openComparison(left: urls[index], right: urls[index + 1])
                index += 2
            }
            if index < urls.count {
                showLauncher(left: urls[index])
            }
        }
    }

    // MARK: - Launcher

    func showLauncher(left: URL? = nil, right: URL? = nil) {
        if let left {
            launcherModel.set(left, for: .left)
        }
        if let right {
            launcherModel.set(right, for: .right)
        }
        AppLog.lifecycle.notice(
            "Showing launcher: \(self.launcherModel.leftURL?.lastPathComponent ?? "nil", privacy: .public) / \(self.launcherModel.rightURL?.lastPathComponent ?? "nil", privacy: .public)"
        )

        if launcherController == nil {
            launcherController = LauncherWindowController(coordinator: self, model: launcherModel)
        }
        launcherController?.window?.deminiaturize(nil)
        launcherController?.showWindow(nil)
    }

    func compareFromLauncher() {
        guard let left = launcherModel.leftURL, let right = launcherModel.rightURL else { return }
        openComparison(left: left, right: right)
        launcherModel.clearAll()
        launcherController?.window?.orderOut(nil)
    }

    func launcherDidBecomeKey() {
        activeSession = nil
    }

    func launcherWillClose() {
        launcherController = nil
        launcherModel.clearAll()
        activeSession = keyComparisonSession
    }

    // MARK: - Comparison windows

    func openComparison(left: URL, right: URL) {
        AppLog.comparison.notice(
            "Opening comparison: \(left.lastPathComponent, privacy: .public) vs \(right.lastPathComponent, privacy: .public)"
        )
        let session = ComparisonSession(leftURL: left, rightURL: right, settings: settings)
        let controller = ComparisonWindowController(session: session, coordinator: self)
        controller.position(cascadeIndex: comparisonControllers.count)
        comparisonControllers[session.id] = controller

        launcherController?.window?.orderOut(nil)
        launcherModel.clearAll()
        controller.showWindow(nil)
        NSApp.activate()
        session.load()
    }

    func comparisonDidBecomeKey(_ session: ComparisonSession) {
        activeSession = session
    }

    func comparisonDidResignKey(_ session: ComparisonSession) {
        if activeSession === session, NSApp.keyWindow == nil {
            activeSession = nil
        }
    }

    func comparisonWillClose(_ session: ComparisonSession) {
        comparisonControllers.removeValue(forKey: session.id)
        if activeSession === session {
            activeSession = keyComparisonSession
        }
    }

    private var keyComparisonSession: ComparisonSession? {
        comparisonControllers.values
            .first(where: { $0.window?.isKeyWindow == true })?
            .session
    }

    // MARK: - File picking

    func pickFile(for side: ComparisonSide, in session: ComparisonSession) {
        guard let url = runOpenPanel() else { return }
        session.replace(side: side, with: url)
    }

    func pickFileForLauncher(side: ComparisonSide) {
        guard launcherController != nil else {
            showLauncher()
            pickFileForLauncher(side: side)
            return
        }
        guard let url = runOpenPanel() else { return }
        launcherModel.set(url, for: side)
    }

    private func runOpenPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.prompt = String(localized: "panel.open_file.prompt", defaultValue: "Open")
        panel.message = String(
            localized: "panel.open_file.message",
            defaultValue: "Choose a text or Markdown file."
        )

        var types: [UTType] = [.plainText, .text, .sourceCode, .json, .commaSeparatedText]
        if let markdown = UTType(filenameExtension: "md") {
            types.append(markdown)
        }
        if let markdown = UTType(filenameExtension: "markdown") {
            types.append(markdown)
        }
        panel.allowedContentTypes = types

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    // MARK: - Menu actions

    @objc func openLeftFile(_ sender: Any?) {
        openFileFromMenu(side: .left)
    }

    @objc func openRightFile(_ sender: Any?) {
        openFileFromMenu(side: .right)
    }

    private func openFileFromMenu(side: ComparisonSide) {
        if let session = activeSession {
            pickFile(for: side, in: session)
            return
        }
        if launcherController == nil {
            showLauncher()
        }
        pickFileForLauncher(side: side)
    }

    @objc func reloadComparison(_ sender: Any?) {
        activeSession?.reload()
    }

    @objc func revealInFinder(_ sender: Any?) {
        guard let session = activeSession else { return }
        let urls = [session.leftURL, session.rightURL].compactMap { $0 }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    @objc func toggleAutoReload(_ sender: Any?) {
        settings.autoReload.toggle()
        for controller in comparisonControllers.values {
            controller.session.setAutoReload(settings.autoReload)
        }
    }

    @objc func find(_ sender: Any?) {
        activeSession?.presentFindBar()
    }

    @objc func findNext(_ sender: Any?) {
        activeSession?.findNext()
    }

    @objc func findPrevious(_ sender: Any?) {
        activeSession?.findPrevious()
    }

    @objc func swapSides(_ sender: Any?) {
        activeSession?.swap()
    }

    @objc func toggleIgnoreWhitespace(_ sender: Any?) {
        guard let session = activeSession else { return }
        session.setIgnoreWhitespace(!session.options.ignoreWhitespace)
    }

    @objc func toggleIgnoreCase(_ sender: Any?) {
        guard let session = activeSession else { return }
        session.setIgnoreCase(!session.options.ignoreCase)
    }

    @objc func toggleLineNumbers(_ sender: Any?) {
        settings.showLineNumbers.toggle()
    }

    @objc func increaseFontSize(_ sender: Any?) {
        settings.increaseFontSize()
    }

    @objc func decreaseFontSize(_ sender: Any?) {
        settings.decreaseFontSize()
    }

    @objc func actualSize(_ sender: Any?) {
        settings.resetFontSize()
    }

    @objc func nextDifference(_ sender: Any?) {
        activeSession?.nextChange()
    }

    @objc func previousDifference(_ sender: Any?) {
        activeSession?.previousChange()
    }

    // MARK: - Menu validation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let action = menuItem.action

        if action == #selector(toggleAutoReload(_:)) {
            menuItem.state = settings.autoReload ? .on : .off
            return true
        }
        if action == #selector(toggleLineNumbers(_:)) {
            menuItem.state = settings.showLineNumbers ? .on : .off
            return true
        }
        if action == #selector(increaseFontSize(_:)) ||
            action == #selector(decreaseFontSize(_:)) ||
            action == #selector(actualSize(_:)) {
            return true
        }
        if action == #selector(openLeftFile(_:)) || action == #selector(openRightFile(_:)) {
            return true
        }

        guard let session = activeSession else { return false }

        switch action {
        case #selector(reloadComparison(_:)):
            return true
        case #selector(revealInFinder(_:)):
            return session.leftURL != nil || session.rightURL != nil
        case #selector(find(_:)):
            return true
        case #selector(findNext(_:)), #selector(findPrevious(_:)):
            return session.findMatchCount > 0
        case #selector(swapSides(_:)):
            return session.canSwap
        case #selector(toggleIgnoreWhitespace(_:)):
            menuItem.state = session.options.ignoreWhitespace ? .on : .off
            return true
        case #selector(toggleIgnoreCase(_:)):
            menuItem.state = session.options.ignoreCase ? .on : .off
            return true
        case #selector(nextDifference(_:)), #selector(previousDifference(_:)):
            return session.changeCount > 0
        default:
            return true
        }
    }
}
