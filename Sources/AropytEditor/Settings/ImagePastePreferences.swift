import Foundation

enum ImagePasteDestination: String, CaseIterable {
    case originalPath
    case currentDirectory
    case resourceDirectory
}

final class ImagePastePreferences {
    static let shared = ImagePastePreferences()
    static let didChangeNotification = Notification.Name(
        "AropytEditor.ImagePastePreferences.didChange"
    )
    static let defaultResourceDirectoryName = "assets"

    private enum Key {
        static let destination = "AropytEditor.imagePaste.destination"
        static let resourceDirectoryName = "AropytEditor.imagePaste.resourceDirectoryName"
        static let escapesImageURLs = "AropytEditor.imagePaste.escapesImageURLs"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var destination: ImagePasteDestination {
        get {
            guard
                let rawValue = defaults.string(forKey: Key.destination),
                let destination = ImagePasteDestination(rawValue: rawValue)
            else { return .originalPath }
            return destination
        }
        set {
            guard newValue != destination else { return }
            defaults.set(newValue.rawValue, forKey: Key.destination)
            notifyChanged()
        }
    }

    var resourceDirectoryName: String {
        get {
            guard
                let value = defaults.string(forKey: Key.resourceDirectoryName),
                Self.isValidResourceDirectoryName(value)
            else { return Self.defaultResourceDirectoryName }
            return value
        }
        set {
            guard
                let normalized = Self.normalizedResourceDirectoryName(newValue),
                normalized != resourceDirectoryName
            else { return }
            defaults.set(normalized, forKey: Key.resourceDirectoryName)
            notifyChanged()
        }
    }

    var escapesImageURLs: Bool {
        get {
            guard defaults.object(forKey: Key.escapesImageURLs) != nil else { return true }
            return defaults.bool(forKey: Key.escapesImageURLs)
        }
        set {
            guard newValue != escapesImageURLs else { return }
            defaults.set(newValue, forKey: Key.escapesImageURLs)
            notifyChanged()
        }
    }

    static func isValidResourceDirectoryName(_ value: String) -> Bool {
        normalizedResourceDirectoryName(value) == value
    }

    static func normalizedResourceDirectoryName(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.hasPrefix("/"), !value.hasPrefix("~") else {
            return nil
        }

        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }

        var allowed = CharacterSet.alphanumerics
        allowed.formUnion(CharacterSet(charactersIn: " -_."))
        guard value.unicodeScalars.allSatisfy({ $0 == "/" || allowed.contains($0) }) else {
            return nil
        }
        return value
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
