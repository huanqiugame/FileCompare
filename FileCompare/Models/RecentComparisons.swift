import Foundation
import OSLog

/// One comparison that was opened before, persisted so it can be reopened from
/// the Dock menu.
struct RecentComparison: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let leftPath: String
    let rightPath: String
    let leftName: String
    let rightName: String
    let leftBookmark: Data?
    let rightBookmark: Data?
    let lastOpened: Date

    /// Shown in the Dock menu as `A vs B`, matching comparison window titles.
    var displayTitle: String {
        "\(leftName) vs \(rightName)"
    }

    init(
        id: UUID = UUID(),
        leftURL: URL,
        rightURL: URL,
        leftBookmark: Data?,
        rightBookmark: Data?,
        lastOpened: Date = Date()
    ) {
        self.id = id
        self.leftPath = leftURL.path
        self.rightPath = rightURL.path
        self.leftName = leftURL.lastPathComponent
        self.rightName = rightURL.lastPathComponent
        self.leftBookmark = leftBookmark
        self.rightBookmark = rightBookmark
        self.lastOpened = lastOpened
    }

    /// Recents treat `A vs B` and `B vs A` as the same pair.
    func isSamePair(as other: RecentComparison) -> Bool {
        let lhs = [Self.comparisonKey(for: leftPath), Self.comparisonKey(for: rightPath)].sorted()
        let rhs = [Self.comparisonKey(for: other.leftPath), Self.comparisonKey(for: other.rightPath)].sorted()
        return lhs == rhs
    }

    private static func comparisonKey(for path: String) -> String {
        path.precomposedStringWithCanonicalMapping.lowercased()
    }
}

/// Keeps the most recently opened comparison pairs in `UserDefaults`.
///
/// The app is sandboxed, so each file is also stored as a security-scoped
/// bookmark. Reopening falls back to the plain path when bookmarks are not
/// available (for example for files handed over by Launch Services).
@MainActor
final class RecentComparisonsStore {
    static let shared = RecentComparisonsStore()
    static let maximumCount = 10

    private enum Key {
        static let recentComparisons = "recentComparisons"
    }

    private let defaults: UserDefaults
    private(set) var items: [RecentComparison]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Key.recentComparisons),
           let decoded = try? JSONDecoder().decode([RecentComparison].self, from: data) {
            self.items = Array(decoded.prefix(Self.maximumCount))
        } else {
            self.items = []
        }
    }

    /// Moves an existing pair back to the top, keeping only the latest
    /// orientation, and trims the list to `maximumCount`.
    func record(left: URL, right: URL) {
        let leftURL = left.standardizedFileURL
        let rightURL = right.standardizedFileURL
        let comparison = RecentComparison(
            leftURL: leftURL,
            rightURL: rightURL,
            leftBookmark: Self.makeBookmark(for: leftURL),
            rightBookmark: Self.makeBookmark(for: rightURL)
        )

        items.removeAll { $0.isSamePair(as: comparison) }
        items.insert(comparison, at: 0)
        if items.count > Self.maximumCount {
            items.removeSubrange(Self.maximumCount...)
        }
        save()
    }

    func item(id: String) -> RecentComparison? {
        items.first { $0.id.uuidString == id }
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    /// Resolves stored bookmarks back to URLs. Missing files still resolve to
    /// their original path so the comparison window can report the load error.
    func resolve(_ item: RecentComparison) -> (left: URL, right: URL) {
        (
            left: Self.resolveURL(bookmark: item.leftBookmark, fallbackPath: item.leftPath),
            right: Self.resolveURL(bookmark: item.rightBookmark, fallbackPath: item.rightPath)
        )
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: Key.recentComparisons)
    }

    private static func makeBookmark(for url: URL) -> Data? {
        if let data = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            return data
        }
        return try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private static func resolveURL(bookmark: Data?, fallbackPath: String) -> URL {
        if let bookmark {
            for options: URL.BookmarkResolutionOptions in [[.withSecurityScope, .withoutUI], [.withoutUI]] {
                var isStale = false
                if let url = try? URL(
                    resolvingBookmarkData: bookmark,
                    options: options,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                ) {
                    return url
                }
            }
            AppLog.lifecycle.notice("Could not resolve recent comparison bookmark; using stored path")
        }
        return URL(fileURLWithPath: fallbackPath)
    }
}
