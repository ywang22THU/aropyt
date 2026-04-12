import AppKit

enum ShortcutAction: String, CaseIterable {
    case newDocument
    case openDocument
    case save
    case close
    case toggleMode
    case bold
    case italic
    case settings

    static let displayOrder: [ShortcutAction] = [
        .newDocument,
        .openDocument,
        .save,
        .close,
        .toggleMode,
        .bold,
        .italic,
        .settings,
    ]

    var label: String {
        switch self {
        case .newDocument: return "New Document"
        case .openDocument: return "Open Document"
        case .save: return "Save"
        case .close: return "Close Window"
        case .toggleMode: return "Toggle Source/Preview"
        case .bold: return "Bold"
        case .italic: return "Italic"
        case .settings: return "Settings"
        }
    }

    var defaultShortcut: KeyboardShortcut {
        switch self {
        case .newDocument:
            return KeyboardShortcut(keyEquivalent: "n", modifiers: .command)
        case .openDocument:
            return KeyboardShortcut(keyEquivalent: "o", modifiers: .command)
        case .save:
            return KeyboardShortcut(keyEquivalent: "s", modifiers: .command)
        case .close:
            return KeyboardShortcut(keyEquivalent: "w", modifiers: .command)
        case .toggleMode:
            return KeyboardShortcut(keyEquivalent: "p", modifiers: [.command, .shift])
        case .bold:
            return KeyboardShortcut(keyEquivalent: "b", modifiers: .command)
        case .italic:
            return KeyboardShortcut(keyEquivalent: "i", modifiers: .command)
        case .settings:
            return KeyboardShortcut(keyEquivalent: ",", modifiers: .command)
        }
    }
}

struct KeyboardShortcut: Codable, Hashable {
    let keyEquivalent: String
    let modifierFlagsRawValue: UInt

    init(keyEquivalent: String, modifiers: NSEvent.ModifierFlags) {
        self.keyEquivalent = keyEquivalent.lowercased()
        self.modifierFlagsRawValue = modifiers.normalizedShortcutFlags.rawValue
    }

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlagsRawValue)
    }

    var formattedLabel: String {
        ShortcutFormatter.format(key: keyEquivalent, modifiers: modifiers)
    }
}

enum ShortcutFormatter {
    static func format(key: String, modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("Ctrl") }
        if modifiers.contains(.option) { parts.append("Option") }
        if modifiers.contains(.shift) { parts.append("Shift") }
        if modifiers.contains(.command) { parts.append("Cmd") }
        parts.append(key == " " ? "Space" : key.uppercased())
        return parts.joined(separator: " + ")
    }
}

final class ShortcutManager {

    static let shared = ShortcutManager()

    static let didChangeNotification = Notification.Name("AropytEditor.ShortcutManager.didChange")

    private static let storageKey = "AropytEditor.shortcuts"

    private let userDefaults: UserDefaults
    private var shortcutsByAction: [ShortcutAction: KeyboardShortcut]

    private init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.shortcutsByAction = Self.loadShortcuts(from: userDefaults)
    }

    func shortcut(for action: ShortcutAction) -> KeyboardShortcut {
        shortcutsByAction[action] ?? action.defaultShortcut
    }

    func updateShortcut(for action: ShortcutAction, to shortcut: KeyboardShortcut) {
        shortcutsByAction[action] = shortcut
        persist()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    func conflictDescription(for shortcut: KeyboardShortcut,
                             excluding action: ShortcutAction? = nil) -> String? {
        for candidate in ShortcutAction.displayOrder where candidate != action {
            if self.shortcut(for: candidate) == shortcut {
                return candidate.label
            }
        }
        return Self.reservedShortcutLabels[shortcut]
    }

    private func persist() {
        let stored = Dictionary(uniqueKeysWithValues: shortcutsByAction.map { pair in
            (pair.key.rawValue, pair.value)
        })
        if let data = try? JSONEncoder().encode(stored) {
            userDefaults.set(data, forKey: Self.storageKey)
        }
    }

    private static func loadShortcuts(from userDefaults: UserDefaults) -> [ShortcutAction: KeyboardShortcut] {
        var shortcuts = Dictionary(uniqueKeysWithValues: ShortcutAction.displayOrder.map { action in
            (action, action.defaultShortcut)
        })

        guard
            let data = userDefaults.data(forKey: storageKey),
            let stored = try? JSONDecoder().decode([String: KeyboardShortcut].self, from: data)
        else {
            return shortcuts
        }

        for action in ShortcutAction.displayOrder {
            if let shortcut = stored[action.rawValue] {
                shortcuts[action] = KeyboardShortcut(keyEquivalent: shortcut.keyEquivalent,
                                                     modifiers: shortcut.modifiers)
            }
        }
        return shortcuts
    }

    private static let reservedShortcutLabels: [KeyboardShortcut: String] = [
        KeyboardShortcut(keyEquivalent: "h", modifiers: .command): "Hide AropytEditor",
        KeyboardShortcut(keyEquivalent: "h", modifiers: [.command, .option]): "Hide Others",
        KeyboardShortcut(keyEquivalent: "q", modifiers: .command): "Quit AropytEditor",
        KeyboardShortcut(keyEquivalent: "s", modifiers: [.command, .shift]): "Save As…",
        KeyboardShortcut(keyEquivalent: "z", modifiers: .command): "Undo",
        KeyboardShortcut(keyEquivalent: "z", modifiers: [.command, .shift]): "Redo",
        KeyboardShortcut(keyEquivalent: "x", modifiers: .command): "Cut",
        KeyboardShortcut(keyEquivalent: "c", modifiers: .command): "Copy",
        KeyboardShortcut(keyEquivalent: "v", modifiers: .command): "Paste",
        KeyboardShortcut(keyEquivalent: "a", modifiers: .command): "Select All",
        KeyboardShortcut(keyEquivalent: "m", modifiers: .command): "Minimize",
    ]
}

private extension NSEvent.ModifierFlags {
    var normalizedShortcutFlags: NSEvent.ModifierFlags {
        intersection([.command, .shift, .option, .control])
    }
}
