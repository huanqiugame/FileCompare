import Darwin
import Foundation

/// Watches a set of files for external changes by polling their metadata.
///
/// Polling is deliberate: sandboxed access is read-only and short-lived, which
/// makes FSEvents streams and file descriptors awkward to keep valid across
/// document swaps. One lightweight `stat` per second per file is cheap and
/// keeps working when a file is deleted and recreated by an atomic save.
///
/// Metadata is read with `stat(2)` rather than `URL.resourceValues(forKeys:)`.
/// The latter caches per-`URL` values and can keep returning the same size,
/// modification date, and resource identifier forever, which makes in-place
/// writes, deletions, and delete-and-recreate invisible to the poller.
@MainActor
final class FileChangeMonitor {
    /// Metadata used to decide whether a file changed.
    struct FileStamp: Hashable, Sendable {
        var exists: Bool
        var modificationDate: Date?
        var changeDate: Date?
        var fileSize: Int?
        var resourceIdentifier: String?
    }

    static let pollInterval: Duration = .seconds(1)
    static let minimumNotificationInterval: Duration = .milliseconds(500)

    private var urls: [URL] = []
    private var onChange: (@MainActor () -> Void)?
    private var baseline: [URL: FileStamp]?
    private var pollTask: Task<Void, Never>?
    private var lastNotification: ContinuousClock.Instant?
    private var hasPendingNotification = false

    init() {}

    deinit {
        pollTask?.cancel()
    }

    /// Starts polling `urls`, replacing any previous watch.
    ///
    /// The first poll establishes a baseline so callers are not notified about
    /// the state they just loaded. `onChange` runs on the main actor and fires
    /// once per burst of changes.
    func start(urls: [URL], onChange: @escaping @MainActor () -> Void) {
        prepare(urls: urls, onChange: onChange)
        guard !urls.isEmpty else { return }

        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let shouldContinue = await Self.poll(monitor: self)
                guard shouldContinue, !Task.isCancelled else { return }

                do {
                    try await Task.sleep(for: Self.pollInterval)
                } catch {
                    return
                }
            }
        }
    }

    /// Configures the watch without scheduling the timer.
    ///
    /// `start` calls this before creating its polling task. Tests call it
    /// together with `pollOnce()` so change detection can be exercised
    /// deterministically instead of waiting on wall-clock polling.
    func prepare(urls: [URL], onChange: @escaping @MainActor () -> Void) {
        stop()
        guard !urls.isEmpty else { return }

        self.urls = urls
        self.onChange = onChange
    }

    /// Runs one poll immediately, without waiting for `pollInterval`.
    ///
    /// Internal seam for deterministic tests; production code uses `start`.
    func pollOnce() async {
        _ = await Self.poll(monitor: self)
    }

    /// Stops polling and releases the change handler.
    func stop() {
        pollTask?.cancel()
        pollTask = nil
        urls = []
        onChange = nil
        baseline = nil
        lastNotification = nil
        hasPendingNotification = false
    }

    // MARK: - Polling

    private static func poll(monitor: FileChangeMonitor?) async -> Bool {
        guard let monitor, monitor.onChange != nil else { return false }

        let urls = monitor.urls
        guard !urls.isEmpty else { return false }

        let stamps = await snapshot(urls)
        guard !Task.isCancelled, let onChange = monitor.onChange else { return false }

        if let previous = monitor.baseline {
            if stamps != previous {
                monitor.hasPendingNotification = true
            }
        }
        monitor.baseline = stamps

        guard monitor.hasPendingNotification else { return true }

        let now = ContinuousClock().now
        if let last = monitor.lastNotification,
           now - last < minimumNotificationInterval {
            // Coalesce the burst; the pending flag survives until the next poll.
            return true
        }

        monitor.hasPendingNotification = false
        monitor.lastNotification = now
        onChange()
        return true
    }

    private nonisolated static func snapshot(_ urls: [URL]) async -> [URL: FileStamp] {
        await Task.detached(priority: .utility) {
            var result: [URL: FileStamp] = [:]
            result.reserveCapacity(urls.count)
            for url in urls {
                result[url] = stamp(for: url)
            }
            return result
        }.value
    }

    /// Reads fresh metadata for `url` with `stat(2)`.
    ///
    /// Unlike `URL.resourceValues(forKeys:)`, this is a syscall on the current
    /// filesystem state, so it sees in-place writes, deletions, and
    /// delete-and-recreate cycles immediately. Works with security-scoped URLs
    /// as long as the caller holds the scope open, since `stat` only needs the
    /// filesystem path.
    nonisolated static func stamp(for url: URL) -> FileStamp {
        var info = stat()
        let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return stat(path, &info)
        }

        guard result == 0 else {
            return FileStamp(
                exists: false,
                modificationDate: nil,
                changeDate: nil,
                fileSize: nil,
                resourceIdentifier: nil
            )
        }

        return FileStamp(
            exists: true,
            modificationDate: date(from: info.st_mtimespec),
            changeDate: date(from: info.st_ctimespec),
            fileSize: Int(info.st_size),
            // Device + inode identify the file itself, so an atomic replace or
            // delete-and-recreate is visible even when size and dates match.
            resourceIdentifier: "\(info.st_dev):\(info.st_ino)"
        )
    }

    private nonisolated static func date(from time: timespec) -> Date {
        Date(
            timeIntervalSince1970:
                Double(time.tv_sec) + Double(time.tv_nsec) / 1_000_000_000
        )
    }
}
