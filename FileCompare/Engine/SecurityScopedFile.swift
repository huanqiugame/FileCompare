import Foundation

/// Holds a security-scoped resource open for as long as the instance lives.
///
/// Sandboxed document pickers hand back URLs that must be "started" before the
/// file can be read. `startAccessingSecurityScopedResource()` returns `false`
/// for URLs that live inside the app container or were not handed out with a
/// security scope, which is normal; stopping access in that case would be
/// harmless but pointless, so it is skipped.
final class SecurityScopedFile: @unchecked Sendable {
    let url: URL

    private let isAccessing: Bool

    init(url: URL) {
        self.url = url
        self.isAccessing = url.startAccessingSecurityScopedResource()
    }

    deinit {
        if isAccessing {
            url.stopAccessingSecurityScopedResource()
        }
    }
}
