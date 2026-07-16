import Foundation

enum AutoSaveMode: String, CaseIterable {
    case onChange
    case afterDelay
    case never
}

final class AutoSavePreferences {
    static let shared = AutoSavePreferences()
    static let didChangeNotification = Notification.Name("AropytEditor.AutoSavePreferences.didChange")

    static let defaultDelay: TimeInterval = 1
    static let validDelayRange: ClosedRange<TimeInterval> = 0.5...60

    private enum Key {
        static let mode = "AropytEditor.autoSave.mode"
        static let delay = "AropytEditor.autoSave.delay"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var mode: AutoSaveMode {
        get {
            guard
                let rawValue = defaults.string(forKey: Key.mode),
                let mode = AutoSaveMode(rawValue: rawValue)
            else { return .never }
            return mode
        }
        set {
            guard newValue != mode else { return }
            defaults.set(newValue.rawValue, forKey: Key.mode)
            notifyChanged()
        }
    }

    var delay: TimeInterval {
        get {
            guard defaults.object(forKey: Key.delay) != nil else {
                return Self.defaultDelay
            }
            return Self.clampedDelay(defaults.double(forKey: Key.delay))
        }
        set {
            let clamped = Self.clampedDelay(newValue)
            guard clamped != delay || defaults.object(forKey: Key.delay) == nil else { return }
            defaults.set(clamped, forKey: Key.delay)
            notifyChanged()
        }
    }

    static func clampedDelay(_ delay: TimeInterval) -> TimeInterval {
        min(max(delay, validDelayRange.lowerBound), validDelayRange.upperBound)
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
