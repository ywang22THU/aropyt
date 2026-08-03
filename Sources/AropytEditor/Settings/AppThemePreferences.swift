import AppKit

enum AppTheme: Int, CaseIterable {
    case system = 0
    case light = 1
    case dark = 2

    var appearance: NSAppearance? {
        switch self {
        case .system:
            return nil
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        }
    }
}

final class AppThemePreferences {
    static let shared = AppThemePreferences()

    private static let storageKey = "AropytEditor.theme"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var theme: AppTheme {
        get {
            AppTheme(rawValue: defaults.integer(forKey: Self.storageKey)) ?? .system
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.storageKey)
        }
    }

    func apply(to application: NSApplication) {
        application.appearance = theme.appearance
    }
}
