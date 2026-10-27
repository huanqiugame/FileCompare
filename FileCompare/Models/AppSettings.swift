import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private enum Key {
        static let showLineNumbers = "showLineNumbers"
        static let fontSize = "fontSize"
        static let autoReload = "autoReload"
    }

    private let defaults: UserDefaults

    var showLineNumbers: Bool {
        didSet { defaults.set(showLineNumbers, forKey: Key.showLineNumbers) }
    }

    var fontSize: Double {
        didSet { defaults.set(fontSize, forKey: Key.fontSize) }
    }

    var autoReload: Bool {
        didSet { defaults.set(autoReload, forKey: Key.autoReload) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.showLineNumbers = defaults.object(forKey: Key.showLineNumbers) as? Bool ?? false
        self.fontSize = defaults.object(forKey: Key.fontSize) as? Double ?? 14
        self.autoReload = defaults.object(forKey: Key.autoReload) as? Bool ?? true
    }

    func increaseFontSize() {
        fontSize = min(fontSize + 1, 24)
    }

    func decreaseFontSize() {
        fontSize = max(fontSize - 1, 11)
    }

    func resetFontSize() {
        fontSize = 14
    }
}
