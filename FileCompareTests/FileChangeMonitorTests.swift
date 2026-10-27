import Foundation
import Testing

@testable import FileCompare

@Suite(.serialized)
@MainActor
struct FileChangeMonitorTests {
    // MARK: - Helpers

    private final class Counter {
        private(set) var count = 0

        func increment() {
            count += 1
        }
    }

    /// Creates a unique temporary directory containing one file and returns
    /// the file URL. Callers remove `url.deletingLastPathComponent()`.
    private static func makeTempFile(
        _ contents: String,
        name: String = "watched.txt"
    ) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileChangeMonitorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    private static func removeContainingDirectory(of url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    /// Rewrites the file through its existing inode, which is what an editor
    /// doing an in-place save does. `Data.write(to:)` without `.atomic` also
    /// does this, but making it explicit keeps the test's intent clear.
    private static func overwriteInPlace(_ url: URL, with text: String) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data(text.utf8))
        try handle.synchronize()
        try handle.close()
    }

    private static func prepareMonitor(
        url: URL
    ) -> (FileChangeMonitor, Counter) {
        let monitor = FileChangeMonitor()
        let counter = Counter()
        monitor.prepare(urls: [url]) { counter.increment() }
        return (monitor, counter)
    }

    /// Polls a condition until it becomes true or `timeout` elapses. Used only
    /// for the one test that exercises the real polling task.
    private static func waitUntil(
        timeout: Duration,
        condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock().now + timeout
        while ContinuousClock().now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    // MARK: - Stamps

    @Test func stampDetectsInPlaceWrite() throws {
        let url = try Self.makeTempFile("alpha")
        defer { Self.removeContainingDirectory(of: url) }

        let before = FileChangeMonitor.stamp(for: url)
        #expect(before.exists)
        #expect(before.fileSize == 5)

        // Same length as before: only timestamps and the inode cache could
        // reveal the write, which is exactly the case URL resource values
        // used to miss.
        try Self.overwriteInPlace(url, with: "bravo")

        let after = FileChangeMonitor.stamp(for: url)
        #expect(after.exists)
        #expect(after.fileSize == 5)
        #expect(after != before)
    }

    @Test func stampDetectsDeletion() throws {
        let url = try Self.makeTempFile("alpha")
        defer { Self.removeContainingDirectory(of: url) }

        let before = FileChangeMonitor.stamp(for: url)
        try FileManager.default.removeItem(at: url)

        let after = FileChangeMonitor.stamp(for: url)
        #expect(after.exists == false)
        #expect(after != before)
    }

    @Test func stampDetectsDeleteAndRecreate() throws {
        let url = try Self.makeTempFile("alpha")
        defer { Self.removeContainingDirectory(of: url) }

        let before = FileChangeMonitor.stamp(for: url)
        try FileManager.default.removeItem(at: url)
        try Data("recreated with a different length".utf8).write(to: url)

        let after = FileChangeMonitor.stamp(for: url)
        #expect(after.exists)
        #expect(after != before)
    }

    @Test func stampDetectsAtomicReplace() throws {
        let url = try Self.makeTempFile("alpha")
        defer { Self.removeContainingDirectory(of: url) }

        let before = FileChangeMonitor.stamp(for: url)
        try Data("atomic replacement with a different length".utf8)
            .write(to: url, options: .atomic)

        let after = FileChangeMonitor.stamp(for: url)
        #expect(after.exists)
        #expect(after != before)
    }

    // MARK: - Polling (deterministic)

    @Test func monitorNotifiesForInPlaceWrite() async throws {
        let url = try Self.makeTempFile("alpha")
        defer { Self.removeContainingDirectory(of: url) }

        let (monitor, counter) = Self.prepareMonitor(url: url)
        await monitor.pollOnce() // baseline
        #expect(counter.count == 0)

        try Self.overwriteInPlace(url, with: "bravo")

        await monitor.pollOnce()
        #expect(counter.count == 1)
    }

    @Test func monitorNotifiesForDeletion() async throws {
        let url = try Self.makeTempFile("alpha")
        defer { Self.removeContainingDirectory(of: url) }

        let (monitor, counter) = Self.prepareMonitor(url: url)
        await monitor.pollOnce()

        try FileManager.default.removeItem(at: url)

        await monitor.pollOnce()
        #expect(counter.count == 1)
    }

    @Test func monitorNotifiesForDeleteAndRecreate() async throws {
        let url = try Self.makeTempFile("alpha")
        defer { Self.removeContainingDirectory(of: url) }

        let (monitor, counter) = Self.prepareMonitor(url: url)
        await monitor.pollOnce()

        try FileManager.default.removeItem(at: url)
        try Data("recreated".utf8).write(to: url)

        await monitor.pollOnce()
        #expect(counter.count == 1)
    }

    @Test func monitorNotifiesForAtomicReplace() async throws {
        let url = try Self.makeTempFile("alpha")
        defer { Self.removeContainingDirectory(of: url) }

        let (monitor, counter) = Self.prepareMonitor(url: url)
        await monitor.pollOnce()

        try Data("replacement".utf8).write(to: url, options: .atomic)

        await monitor.pollOnce()
        #expect(counter.count == 1)
    }

    @Test func monitorCoalescesUnchangedPolls() async throws {
        let url = try Self.makeTempFile("alpha")
        defer { Self.removeContainingDirectory(of: url) }

        let (monitor, counter) = Self.prepareMonitor(url: url)
        await monitor.pollOnce()

        await monitor.pollOnce()
        await monitor.pollOnce()
        #expect(counter.count == 0)
    }

    @Test func stopPreventsNotifications() async throws {
        let url = try Self.makeTempFile("alpha")
        defer { Self.removeContainingDirectory(of: url) }

        let (monitor, counter) = Self.prepareMonitor(url: url)
        await monitor.pollOnce()

        monitor.stop()
        try Self.overwriteInPlace(url, with: "changed after stop")

        await monitor.pollOnce()
        #expect(counter.count == 0)
    }

    // MARK: - Real polling task

    @Test func pollingTaskNotifiesAfterInPlaceWrite() async throws {
        let url = try Self.makeTempFile("alpha")
        defer { Self.removeContainingDirectory(of: url) }

        let monitor = FileChangeMonitor()
        let counter = Counter()
        monitor.start(urls: [url]) { counter.increment() }
        defer { monitor.stop() }

        // Let the first poll establish its baseline. Polling runs every second.
        try await Task.sleep(for: .milliseconds(1200))
        #expect(counter.count == 0)

        try Self.overwriteInPlace(url, with: "bravo")

        let fired = await Self.waitUntil(timeout: .seconds(8)) {
            counter.count > 0
        }
        #expect(fired)
    }

    @Test func stopCancelsThePollingTask() async throws {
        let url = try Self.makeTempFile("alpha")
        defer { Self.removeContainingDirectory(of: url) }

        let monitor = FileChangeMonitor()
        let counter = Counter()
        monitor.start(urls: [url]) { counter.increment() }
        defer { monitor.stop() }

        try await Task.sleep(for: .milliseconds(1200))
        monitor.stop()

        try Self.overwriteInPlace(url, with: "changed after polling stopped")
        try await Task.sleep(for: .milliseconds(2000))

        #expect(counter.count == 0)
    }

    @Test func monitorDeallocatesAfterStart() async throws {
        let url = try Self.makeTempFile("alpha")
        defer { Self.removeContainingDirectory(of: url) }

        weak var weakMonitor: FileChangeMonitor?
        do {
            let monitor = FileChangeMonitor()
            weakMonitor = monitor
            monitor.start(urls: [url]) {}
        }

        #expect(weakMonitor == nil)
    }
}
