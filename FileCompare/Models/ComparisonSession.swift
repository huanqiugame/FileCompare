import OSLog
import Foundation
import Observation

/// A request from the session for the diff view to reveal a specific row.
struct ScrollRequest: Equatable, Sendable {
    let id: UUID
    let rowID: Int
    let animated: Bool
}

/// One occurrence of the find query inside a diff row.
struct FindMatch: Identifiable, Equatable {
    let id: Int
    let rowID: Int
    let side: ComparisonSide
    /// UTF-16 range inside the cell's text.
    let range: NSRange
}

/// Owns the files, the computed diff, find state and change navigation for a
/// single comparison window.
@MainActor
@Observable
final class ComparisonSession: Identifiable {
    let id = UUID()

    var leftURL: URL?
    var rightURL: URL?
    var document: DiffDocument?
    var options = DiffOptions()
    var isLoading = false
    var errorMessage: String?
    var isFindBarVisible = false
    var findQuery = ""
    var findMatchCount = 0
    var currentFindIndex = -1
    var scrollRequest: ScrollRequest?
    var highlightedRowID: Int?

    /// Bumped when the find bar is asked to present while it is already open, so
    /// the field can take focus again (for example on a repeated Command-F).
    private(set) var findFocusRequest = 0

    /// Incremented whenever `document` is replaced or swapped. Views use this to
    /// invalidate layout caches.
    private(set) var documentRevision = 0

    private(set) var findMatches: [FindMatch] = []
    /// Highlight ranges grouped for fast per-row lookup by the diff view.
    private(set) var findHighlights: [Int: [ComparisonSide: [NSRange]]] = [:]

    @ObservationIgnored private var leftScopedFile: SecurityScopedFile?
    @ObservationIgnored private var rightScopedFile: SecurityScopedFile?
    @ObservationIgnored private var leftTextFile: LoadedTextFile?
    @ObservationIgnored private var rightTextFile: LoadedTextFile?
    @ObservationIgnored private var topRowID: Int?

    private var changeIndex = -1

    @ObservationIgnored private var autoReloadEnabled = false
    @ObservationIgnored private var monitor: FileChangeMonitor?
    @ObservationIgnored private var autoReloadTask: Task<Void, Never>?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var highlightTask: Task<Void, Never>?
    @ObservationIgnored private var activeLoadToken: UUID?
    @ObservationIgnored private var pendingReplacement: PendingReplacement?

    init(leftURL: URL, rightURL: URL, settings: AppSettings) {
        self.leftURL = leftURL
        self.rightURL = rightURL
        self.leftScopedFile = SecurityScopedFile(url: leftURL)
        self.rightScopedFile = SecurityScopedFile(url: rightURL)
        self.autoReloadEnabled = settings.autoReload
    }

    // MARK: - Derived state

    var title: String {
        "\(leftDisplayName) vs \(rightDisplayName)"
    }

    var canSwap: Bool {
        leftURL != nil && rightURL != nil
    }

    var changeCount: Int {
        document?.changeGroups.count ?? 0
    }

    var currentChangeIndex: Int {
        changeIndex
    }

    var currentMatch: FindMatch? {
        guard findMatches.indices.contains(currentFindIndex) else { return nil }
        return findMatches[currentFindIndex]
    }

    var leftDisplayName: String {
        displayName(for: .left)
    }

    var rightDisplayName: String {
        displayName(for: .right)
    }

    // MARK: - Loading

    func load() {
        guard let leftURL, let rightURL else {
            isLoading = false
            errorMessage = String(localized: "error.noFile", defaultValue: "No file selected")
            return
        }

        let leftFile: SecurityScopedFile
        if let existing = leftScopedFile, existing.url == leftURL {
            leftFile = existing
        } else {
            leftFile = SecurityScopedFile(url: leftURL)
            leftScopedFile = leftFile
        }

        let rightFile: SecurityScopedFile
        if let existing = rightScopedFile, existing.url == rightURL {
            rightFile = existing
        } else {
            rightFile = SecurityScopedFile(url: rightURL)
            rightScopedFile = rightFile
        }

        let anchor = captureAnchor()
        let requestedOptions = options
        let token = UUID()
        activeLoadToken = token
        loadTask?.cancel()
        isLoading = true
        errorMessage = nil

        // `nonisolated async` functions run on the caller's executor under the
        // project's approachable-concurrency settings, so waiting for
        // `performLoad` from a MainActor task would still block the UI. A
        // detached task makes the off-main execution explicit.
        loadTask = Task.detached(priority: .userInitiated) { [weak self] in
            let outcome = await Self.performLoad(
                left: leftFile,
                right: rightFile,
                options: requestedOptions
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.activeLoadToken == token else { return }
                self.apply(outcome, anchor: anchor)
            }
        }
    }

    func reload() {
        load()
    }

    func replace(side: ComparisonSide, with url: URL) {
        let scopedFile = SecurityScopedFile(url: url)
        switch side {
        case .left:
            pendingReplacement = PendingReplacement(
                side: .left,
                oldURL: leftURL,
                oldScopedFile: leftScopedFile,
                oldTextFile: leftTextFile
            )
            leftURL = url
            leftScopedFile = scopedFile
            leftTextFile = nil
        case .right:
            pendingReplacement = PendingReplacement(
                side: .right,
                oldURL: rightURL,
                oldScopedFile: rightScopedFile,
                oldTextFile: rightTextFile
            )
            rightURL = url
            rightScopedFile = scopedFile
            rightTextFile = nil
        }
        stopMonitoring()
        load()
    }

    /// Swaps both sides in place. The existing diff is mirrored rather than
    /// recomputed, so scroll position and change groups remain stable.
    func swap() {
        guard let oldLeftURL = leftURL, let oldRightURL = rightURL else { return }
        if pendingReplacement != nil {
            pendingReplacement = nil
            load()
            return
        }

        leftURL = oldRightURL
        rightURL = oldLeftURL

        let oldLeftFile = leftScopedFile
        leftScopedFile = rightScopedFile
        rightScopedFile = oldLeftFile

        let oldLeftText = leftTextFile
        leftTextFile = rightTextFile
        rightTextFile = oldLeftText

        guard let document else {
            load()
            return
        }

        // A load started before the swap would publish a document with the old
        // orientation, so it must not overwrite the mirrored document.
        loadTask?.cancel()
        loadTask = nil
        activeLoadToken = nil
        isLoading = false

        self.document = document.swapped()
        documentRevision &+= 1
        recomputeFindMatches(resetIndex: false)
        restartMonitoring()
    }

    // MARK: - Options

    func setIgnoreWhitespace(_ value: Bool) {
        guard options.ignoreWhitespace != value else { return }
        options.ignoreWhitespace = value
        reload()
    }

    func setIgnoreCase(_ value: Bool) {
        guard options.ignoreCase != value else { return }
        options.ignoreCase = value
        reload()
    }

    // MARK: - Change navigation

    func nextChange() {
        guard let document, !document.changeGroups.isEmpty else { return }
        let count = document.changeGroups.count
        if changeIndex < 0 || changeIndex >= count - 1 {
            changeIndex = 0
        } else {
            changeIndex += 1
        }
        revealChange(at: changeIndex, in: document)
    }

    func previousChange() {
        guard let document, !document.changeGroups.isEmpty else { return }
        let count = document.changeGroups.count
        if changeIndex <= 0 {
            changeIndex = count - 1
        } else {
            changeIndex -= 1
        }
        revealChange(at: changeIndex, in: document)
    }

    private func revealChange(at index: Int, in document: DiffDocument) {
        guard document.changeGroups.indices.contains(index) else { return }
        let group = document.changeGroups[index]
        let rowIndex = min(max(group.firstRow, 0), document.rows.count - 1)
        guard let row = document.rows[safe: rowIndex] else { return }
        requestScroll(toRowID: row.id, animated: isNearCurrentPosition(row.id))
        flash(rowID: row.id)
    }

    // MARK: - Scroll position

    func updateTopRow(_ rowID: Int?) {
        topRowID = rowID
    }

    private func requestScroll(toRowID rowID: Int, animated: Bool) {
        scrollRequest = ScrollRequest(id: UUID(), rowID: rowID, animated: animated)
    }

    private func isNearCurrentPosition(_ rowID: Int) -> Bool {
        guard let document else { return false }
        guard let target = document.rows.firstIndex(where: { $0.id == rowID }) else { return false }
        let current = topRowID.flatMap { id in
            document.rows.firstIndex(where: { $0.id == id })
        } ?? 0
        return abs(target - current) <= 30
    }

    private func flash(rowID: Int) {
        highlightedRowID = rowID
        highlightTask?.cancel()
        highlightTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(800))
            } catch {
                return
            }
            guard let self, self.highlightedRowID == rowID else { return }
            self.highlightedRowID = nil
        }
    }

    // MARK: - Auto reload

    func setAutoReload(_ enabled: Bool) {
        autoReloadEnabled = enabled
        if enabled {
            if monitor == nil, document != nil {
                startMonitoring()
            }
        } else {
            stopMonitoring()
        }
    }

    private func restartMonitoring() {
        stopMonitoring()
        guard autoReloadEnabled, document != nil else { return }
        startMonitoring()
    }

    private func startMonitoring() {
        monitor?.stop()
        monitor = nil
        autoReloadTask?.cancel()
        autoReloadTask = nil
        guard let leftURL, let rightURL else { return }
        let monitor = FileChangeMonitor()
        self.monitor = monitor
        monitor.start(urls: [leftURL, rightURL]) { [weak self] in
            self?.scheduleAutoReload()
        }
    }

    private func stopMonitoring() {
        autoReloadTask?.cancel()
        autoReloadTask = nil
        monitor?.stop()
        monitor = nil
    }

    private func scheduleAutoReload() {
        autoReloadTask?.cancel()
        autoReloadTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            guard let self, !Task.isCancelled, self.autoReloadEnabled else { return }
            self.reload()
        }
    }

    // MARK: - Find

    func presentFindBar() {
        isFindBarVisible = true
        findFocusRequest &+= 1
    }

    func dismissFindBar() {
        isFindBarVisible = false
        findQuery = ""
        findMatches = []
        findHighlights = [:]
        findMatchCount = 0
        currentFindIndex = -1
    }

    func setFindQuery(_ query: String) {
        guard findQuery != query else { return }
        findQuery = query
        recomputeFindMatches(resetIndex: true)
        if let match = currentMatch {
            requestScroll(toRowID: match.rowID, animated: false)
        }
    }

    func findNext() {
        guard !findMatches.isEmpty else { return }
        currentFindIndex = (currentFindIndex + 1) % findMatches.count
        if currentFindIndex < 0 { currentFindIndex = 0 }
        revealCurrentMatch()
    }

    func findPrevious() {
        guard !findMatches.isEmpty else { return }
        if currentFindIndex <= 0 {
            currentFindIndex = findMatches.count - 1
        } else {
            currentFindIndex -= 1
        }
        revealCurrentMatch()
    }

    private func revealCurrentMatch() {
        guard let match = currentMatch else { return }
        requestScroll(toRowID: match.rowID, animated: isNearCurrentPosition(match.rowID))
    }

    private func recomputeFindMatches(resetIndex: Bool) {
        var matches: [FindMatch] = []
        var highlights: [Int: [ComparisonSide: [NSRange]]] = [:]

        if !findQuery.isEmpty, let document {
            let query = findQuery
            for row in document.rows {
                if let cell = row.left {
                    Self.collectMatches(
                        in: cell.text,
                        query: query,
                        rowID: row.id,
                        side: .left,
                        matches: &matches,
                        highlights: &highlights
                    )
                }
                if let cell = row.right {
                    Self.collectMatches(
                        in: cell.text,
                        query: query,
                        rowID: row.id,
                        side: .right,
                        matches: &matches,
                        highlights: &highlights
                    )
                }
            }
        }

        findMatches = matches
        findHighlights = highlights
        findMatchCount = matches.count

        if matches.isEmpty {
            currentFindIndex = -1
        } else if resetIndex || currentFindIndex < 0 {
            currentFindIndex = 0
        } else if currentFindIndex >= matches.count {
            currentFindIndex = matches.count - 1
        }
    }

    private nonisolated static func collectMatches(
        in text: String,
        query: String,
        rowID: Int,
        side: ComparisonSide,
        matches: inout [FindMatch],
        highlights: inout [Int: [ComparisonSide: [NSRange]]]
    ) {
        guard !text.isEmpty else { return }
        let string = text as NSString
        var searchRange = NSRange(location: 0, length: string.length)

        while searchRange.length > 0 {
            let found = string.range(
                of: query,
                options: [.caseInsensitive],
                range: searchRange
            )
            guard found.location != NSNotFound, found.length > 0 else { break }

            matches.append(
                FindMatch(id: matches.count, rowID: rowID, side: side, range: found)
            )
            highlights[rowID, default: [:]][side, default: []].append(found)

            let nextLocation = found.location + found.length
            guard nextLocation < string.length else { break }
            searchRange = NSRange(location: nextLocation, length: string.length - nextLocation)
        }
    }

    // MARK: - Load results

    private func apply(_ outcome: LoadOutcome, anchor: ScrollAnchor?) {
        switch outcome {
        case .success(let leftFile, let rightFile, let document):
            AppLog.comparison.notice(
                "Loaded \(leftFile.displayName, privacy: .public) (\(leftFile.lineCount) lines) vs \(rightFile.displayName, privacy: .public) (\(rightFile.lineCount) lines), \(document.changeGroups.count) change group(s)"
            )
            isLoading = false
            leftTextFile = leftFile
            rightTextFile = rightFile
            self.document = document
            documentRevision &+= 1
            pendingReplacement = nil
            errorMessage = nil
            if document.changeGroups.isEmpty {
                changeIndex = -1
            } else if changeIndex >= 0 {
                changeIndex = min(changeIndex, document.changeGroups.count - 1)
            }
            recomputeFindMatches(resetIndex: true)
            restoreScroll(anchor: anchor, in: document)
            startMonitoringIfNeeded()
        case .failure(let message):
            AppLog.comparison.error("Comparison failed: \(message, privacy: .public)")
            isLoading = false
            errorMessage = message
            // A failed side replacement must not leave the title pointing at a
            // file whose content is not in the document. Restore the previous
            // side and keep the old document visible behind the error card.
            if let pending = pendingReplacement {
                switch pending.side {
                case .left:
                    leftURL = pending.oldURL
                    leftScopedFile = pending.oldScopedFile
                    leftTextFile = pending.oldTextFile
                case .right:
                    rightURL = pending.oldURL
                    rightScopedFile = pending.oldScopedFile
                    rightTextFile = pending.oldTextFile
                }
                pendingReplacement = nil
                if autoReloadEnabled, document != nil, monitor == nil {
                    startMonitoring()
                }
            }
        case .cancelled:
            break
        }
    }

    private func startMonitoringIfNeeded() {
        guard autoReloadEnabled, document != nil else { return }
        // A reload caused by the monitor itself must not reset its baseline:
        // that could miss a save made while the new document was being read.
        guard monitor == nil else { return }
        startMonitoring()
    }

    // MARK: - Scroll restoration

    private func captureAnchor() -> ScrollAnchor? {
        guard let document, !document.rows.isEmpty else { return nil }
        let rowID = topRowID ?? document.rows[0].id
        guard let index = document.rows.firstIndex(where: { $0.id == rowID }) else { return nil }
        let row = document.rows[index]
        return ScrollAnchor(
            leftLine: row.leftLineNumber,
            rightLine: row.rightLineNumber,
            rowIndex: index
        )
    }

    private func restoreScroll(anchor: ScrollAnchor?, in document: DiffDocument) {
        guard let anchor, !document.rows.isEmpty else { return }

        var targetIndex: Int?
        if let leftLine = anchor.leftLine {
            targetIndex = document.rows.firstIndex(where: { $0.leftLineNumber == leftLine })
        }
        if targetIndex == nil, let rightLine = anchor.rightLine {
            targetIndex = document.rows.firstIndex(where: { $0.rightLineNumber == rightLine })
        }
        if targetIndex == nil, let rightLine = anchor.rightLine {
            var bestDistance = Int.max
            for (index, row) in document.rows.enumerated() {
                guard let line = row.rightLineNumber else { continue }
                let distance = abs(line - rightLine)
                if distance < bestDistance {
                    bestDistance = distance
                    targetIndex = index
                }
            }
        }

        let index = min(max(targetIndex ?? anchor.rowIndex, 0), document.rows.count - 1)
        guard let row = document.rows[safe: index] else { return }
        topRowID = row.id
        requestScroll(toRowID: row.id, animated: false)
    }

    // MARK: - Display names

    private func displayName(for side: ComparisonSide) -> String {
        switch side {
        case .left:
            if let leftURL, let document, document.left.url == leftURL {
                return document.left.displayName
            }
            return leftURL?.lastPathComponent ?? Self.noFileName
        case .right:
            if let rightURL, let document, document.right.url == rightURL {
                return document.right.displayName
            }
            return rightURL?.lastPathComponent ?? Self.noFileName
        }
    }

    private static var noFileName: String {
        String(localized: "file.none", defaultValue: "No file")
    }

    // MARK: - Off-main work

    private nonisolated static func performLoad(
        left: SecurityScopedFile,
        right: SecurityScopedFile,
        options: DiffOptions
    ) async -> LoadOutcome {
        do {
            try Task.checkCancellation()
            let leftFile = try TextFileLoader.read(url: left.url)
            try Task.checkCancellation()
            let rightFile = try TextFileLoader.read(url: right.url)
            try Task.checkCancellation()
            let document = try DiffEngine.compare(left: leftFile, right: rightFile, options: options)
            return .success(leftFile, rightFile, document)
        } catch is CancellationError {
            return .cancelled
        } catch let error as FileLoadError {
            return .failure(message(for: error))
        } catch {
            return .failure(String(localized: "error.read", defaultValue: "Cannot read file"))
        }
    }

    private nonisolated static func message(for error: FileLoadError) -> String {
        switch error {
        case .notAFile:
            return String(localized: "error.notAFile", defaultValue: "Not a text file")
        case .unreadable:
            return String(localized: "error.unreadable", defaultValue: "Cannot read file")
        case .tooLarge:
            return String(localized: "error.tooLarge", defaultValue: "File is too large")
        case .tooManyLines:
            return String(localized: "error.tooManyLines", defaultValue: "File has too many lines")
        case .lineTooLong:
            return String(localized: "error.lineTooLong", defaultValue: "A line exceeds the supported length")
        case .binary:
            return String(localized: "error.binary", defaultValue: "Binary file is not supported")
        case .unsupportedEncoding:
            return String(localized: "error.encoding", defaultValue: "Unsupported text encoding")
        case .emptySelection:
            return String(localized: "error.noFile", defaultValue: "No file selected")
        }
    }
}

// MARK: - Private types

private struct ScrollAnchor: Sendable {
    var leftLine: Int?
    var rightLine: Int?
    var rowIndex: Int
}

private struct PendingReplacement {
    var side: ComparisonSide
    var oldURL: URL?
    var oldScopedFile: SecurityScopedFile?
    var oldTextFile: LoadedTextFile?
}

private enum LoadOutcome: Sendable {
    case success(LoadedTextFile, LoadedTextFile, DiffDocument)
    case failure(String)
    case cancelled
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
