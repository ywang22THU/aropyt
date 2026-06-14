import Foundation

enum L10n {
    static let didChangeNotification = Notification.Name("AropytEditor.L10n.didChange")

    enum AppLanguage: String, CaseIterable {
        case system
        case english = "en"
        case simplifiedChinese = "zh-Hans"

        var title: String {
            switch self {
            case .system:
                return L10n.tr("settings.language.option.system", "Follow System")
            case .english:
                return L10n.tr("settings.language.option.english", "English")
            case .simplifiedChinese:
                return L10n.tr("settings.language.option.zh_hans", "Simplified Chinese")
            }
        }

        var symbol: String {
            switch self {
            case .system: return "globe"
            case .english: return "textformat.abc"
            case .simplifiedChinese: return "character.book.closed"
            }
        }
    }

    private static let languageStorageKey = "AropytEditor.language"

    static var currentLanguage: AppLanguage {
        guard
            let rawValue = UserDefaults.standard.string(forKey: languageStorageKey),
            let language = AppLanguage(rawValue: rawValue)
        else {
            return .system
        }
        return language
    }

    static func setLanguage(_ language: AppLanguage) {
        guard language != currentLanguage else { return }
        UserDefaults.standard.set(language.rawValue, forKey: languageStorageKey)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    static func tr(_ key: String, _ fallback: String, _ args: CVarArg...) -> String {
        let format = NSLocalizedString(
            key,
            tableName: "Localizable",
            bundle: localizationBundle,
            value: fallback,
            comment: ""
        )
        guard !args.isEmpty else { return format }
        return String(format: format, locale: formatLocale, arguments: args)
    }

    private static var localizationBundle: Bundle {
        let language = currentLanguage
        guard language != .system else { return .module }
        for resourceName in [language.rawValue, language.rawValue.lowercased()] {
            if
                let path = Bundle.module.path(forResource: resourceName, ofType: "lproj"),
                let bundle = Bundle(path: path)
            {
                return bundle
            }
        }
        return .module
    }

    private static var formatLocale: Locale {
        switch currentLanguage {
        case .system:
            return .current
        case .english:
            return Locale(identifier: "en")
        case .simplifiedChinese:
            return Locale(identifier: "zh-Hans")
        }
    }
}
