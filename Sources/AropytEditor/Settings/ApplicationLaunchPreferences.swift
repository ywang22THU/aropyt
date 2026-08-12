import Foundation

enum ApplicationLaunchBehavior: String, CaseIterable {
    case createNewDocument
    case reopenLastClosedDocument
    case openSpecificDocument
}

final class ApplicationLaunchPreferences {
    static let shared = ApplicationLaunchPreferences()
    static let didChangeNotification = Notification.Name(
        "AropytEditor.ApplicationLaunchPreferences.didChange"
    )

    private enum Key {
        static let behavior = "AropytEditor.applicationLaunch.behavior"
        static let lastClosedFilePath = "AropytEditor.applicationLaunch.lastClosedFilePath"
        static let specificFilePath = "AropytEditor.applicationLaunch.specificFilePath"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var behavior: ApplicationLaunchBehavior {
        get {
            guard
                let rawValue = defaults.string(forKey: Key.behavior),
                let behavior = ApplicationLaunchBehavior(rawValue: rawValue)
            else { return .createNewDocument }
            return behavior
        }
        set {
            guard newValue != behavior else { return }
            defaults.set(newValue.rawValue, forKey: Key.behavior)
            notifyChanged()
        }
    }

    var lastClosedFileURL: URL? {
        get { fileURL(forKey: Key.lastClosedFilePath) }
        set { setFileURL(newValue, forKey: Key.lastClosedFilePath) }
    }

    var specificFileURL: URL? {
        get { fileURL(forKey: Key.specificFilePath) }
        set { setFileURL(newValue, forKey: Key.specificFilePath) }
    }

    func startupFileURL(fileManager: FileManager = .default) -> URL? {
        let candidate: URL?
        switch behavior {
        case .createNewDocument:
            return nil
        case .reopenLastClosedDocument:
            candidate = lastClosedFileURL
        case .openSpecificDocument:
            candidate = specificFileURL
        }

        guard let candidate else { return nil }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              fileManager.isReadableFile(atPath: candidate.path)
        else { return nil }
        return candidate
    }

    private func fileURL(forKey key: String) -> URL? {
        guard let path = defaults.string(forKey: key), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    private func setFileURL(_ url: URL?, forKey key: String) {
        let oldValue = fileURL(forKey: key)
        let newValue = url?.standardizedFileURL
        guard newValue != oldValue else { return }
        if let newValue {
            defaults.set(newValue.path, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
        notifyChanged()
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
