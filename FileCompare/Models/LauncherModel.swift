import Foundation
import Observation

@MainActor
@Observable
final class LauncherModel {
    var leftURL: URL?
    var rightURL: URL?
    var errorMessage: String?

    @ObservationIgnored private var leftScopedFile: SecurityScopedFile?
    @ObservationIgnored private var rightScopedFile: SecurityScopedFile?

    var canCompare: Bool { leftURL != nil && rightURL != nil }

    func url(for side: ComparisonSide) -> URL? {
        side == .left ? leftURL : rightURL
    }

    func set(_ url: URL, for side: ComparisonSide) {
        guard validate(url) else { return }
        errorMessage = nil
        if side == .left {
            leftURL = url
            leftScopedFile = SecurityScopedFile(url: url)
        } else {
            rightURL = url
            rightScopedFile = SecurityScopedFile(url: url)
        }
    }

    func setPair(_ left: URL?, _ right: URL?) {
        if let left {
            set(left, for: .left)
        }
        if let right {
            set(right, for: .right)
        }
        errorMessage = nil
    }

    func clear(_ side: ComparisonSide) {
        if side == .left {
            leftURL = nil
            leftScopedFile = nil
        } else {
            rightURL = nil
            rightScopedFile = nil
        }
    }

    func clearAll() {
        leftURL = nil
        rightURL = nil
        leftScopedFile = nil
        rightScopedFile = nil
        errorMessage = nil
    }

    private func validate(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            errorMessage = String(localized: "error.notAFile", defaultValue: "Not a text file")
            return false
        }
        return true
    }
}
