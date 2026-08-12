import Foundation

final class SyntaxPreferences {
    static let shared = SyntaxPreferences()
    static let didChangeNotification = Notification.Name(
        "AropytEditor.SyntaxPreferences.didChange"
    )

    private enum Key {
        static let supportsBackslashMathDelimiters =
            "AropytEditor.syntax.supportsBackslashMathDelimiters"
        static let supportsMathCodeBlocks =
            "AropytEditor.syntax.supportsMathCodeBlocks"
        static let showsCodeBlockLineNumbers =
            "AropytEditor.syntax.showsCodeBlockLineNumbers"
        static let wrapsCodeBlockLines =
            "AropytEditor.syntax.wrapsCodeBlockLines"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// `false` preserves CommonMark's meaning of `\[` and `\(` as escaped
    /// punctuation. Enabling this opts into the conflicting TeX delimiters.
    var supportsBackslashMathDelimiters: Bool {
        get {
            defaults.bool(forKey: Key.supportsBackslashMathDelimiters)
        }
        set {
            set(newValue, forKey: Key.supportsBackslashMathDelimiters, oldValue: supportsBackslashMathDelimiters)
        }
    }

    var supportsMathCodeBlocks: Bool {
        get { defaults.bool(forKey: Key.supportsMathCodeBlocks) }
        set {
            set(newValue, forKey: Key.supportsMathCodeBlocks, oldValue: supportsMathCodeBlocks)
        }
    }

    var showsCodeBlockLineNumbers: Bool {
        get { value(forKey: Key.showsCodeBlockLineNumbers, default: true) }
        set {
            set(newValue, forKey: Key.showsCodeBlockLineNumbers, oldValue: showsCodeBlockLineNumbers)
        }
    }

    var wrapsCodeBlockLines: Bool {
        get { value(forKey: Key.wrapsCodeBlockLines, default: true) }
        set {
            set(newValue, forKey: Key.wrapsCodeBlockLines, oldValue: wrapsCodeBlockLines)
        }
    }

    private func value(forKey key: String, default defaultValue: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }

    private func set(_ newValue: Bool, forKey key: String, oldValue: Bool) {
        guard newValue != oldValue else { return }
        defaults.set(newValue, forKey: key)
        NotificationCenter.default.post(
            name: Self.didChangeNotification,
            object: self
        )
    }
}
