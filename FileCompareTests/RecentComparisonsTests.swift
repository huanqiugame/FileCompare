import Foundation
import Testing

@testable import FileCompare

@MainActor
struct RecentComparisonsTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "RecentComparisonsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/FileCompareRecentTests/\(name)")
    }

    @Test func recordsMostRecentFirstWithVsTitle() {
        let store = RecentComparisonsStore(defaults: makeDefaults())

        store.record(left: url("a.txt"), right: url("b.txt"))

        #expect(store.items.count == 1)
        #expect(store.items[0].displayTitle == "a.txt vs b.txt")
        #expect(store.items[0].leftPath == "/tmp/FileCompareRecentTests/a.txt")
        #expect(store.items[0].rightPath == "/tmp/FileCompareRecentTests/b.txt")
    }

    @Test func samePairInEitherOrderMovesToTop() {
        let store = RecentComparisonsStore(defaults: makeDefaults())
        store.record(left: url("a.txt"), right: url("b.txt"))
        store.record(left: url("c.txt"), right: url("d.txt"))

        store.record(left: url("b.txt"), right: url("a.txt"))

        #expect(store.items.count == 2)
        #expect(store.items[0].displayTitle == "b.txt vs a.txt")
        #expect(store.items[1].displayTitle == "c.txt vs d.txt")
    }

    @Test func pairMatchingIgnoresCase() {
        let store = RecentComparisonsStore(defaults: makeDefaults())
        store.record(left: url("Readme.md"), right: url("notes.md"))

        store.record(left: url("readme.md"), right: url("NOTES.md"))

        #expect(store.items.count == 1)
        #expect(store.items[0].displayTitle == "readme.md vs NOTES.md")
    }

    @Test func trimsToMaximumCount() {
        let store = RecentComparisonsStore(defaults: makeDefaults())

        for index in 0..<(RecentComparisonsStore.maximumCount + 2) {
            store.record(left: url("left\(index).txt"), right: url("right\(index).txt"))
        }

        #expect(store.items.count == RecentComparisonsStore.maximumCount)
        #expect(store.items[0].displayTitle == "left11.txt vs right11.txt")
        #expect(store.items.last?.displayTitle == "left2.txt vs right2.txt")
    }

    @Test func persistsAcrossInstances() {
        let defaults = makeDefaults()
        let first = RecentComparisonsStore(defaults: defaults)
        first.record(left: url("a.txt"), right: url("b.txt"))

        let second = RecentComparisonsStore(defaults: defaults)

        #expect(second.items.count == 1)
        #expect(second.items[0].displayTitle == "a.txt vs b.txt")
    }

    @Test func clearRemovesEverythingFromStorage() {
        let defaults = makeDefaults()
        let first = RecentComparisonsStore(defaults: defaults)
        first.record(left: url("a.txt"), right: url("b.txt"))
        first.clear()

        #expect(first.items.isEmpty)
        #expect(RecentComparisonsStore(defaults: defaults).items.isEmpty)
    }

    @Test func resolvesFallsBackToStoredPaths() {
        let store = RecentComparisonsStore(defaults: makeDefaults())
        store.record(left: url("missing-left.txt"), right: url("missing-right.txt"))

        let urls = store.resolve(store.items[0])

        #expect(urls.left.path == "/tmp/FileCompareRecentTests/missing-left.txt")
        #expect(urls.right.path == "/tmp/FileCompareRecentTests/missing-right.txt")
    }
}
