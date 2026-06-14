import AppKit

/// Theme tab：深色 / 浅色 / 跟随系统。
final class ThemeTabViewController: NSViewController {
    private weak var appearanceStack: NSStackView?
    private weak var languageStack: NSStackView?

    private enum ThemeOption: Int, CaseIterable {
        case system = 0
        case light = 1
        case dark = 2

        var title: String {
            switch self {
            case .system: return L10n.tr("settings.theme.option.system", "Follow System")
            case .light:  return L10n.tr("settings.theme.option.light", "Light")
            case .dark:   return L10n.tr("settings.theme.option.dark", "Dark")
            }
        }

        var symbol: String {
            switch self {
            case .system: return "circle.lefthalf.filled"
            case .light:  return "sun.max"
            case .dark:   return "moon"
            }
        }
    }

    private enum LanguageOption: Int, CaseIterable {
        case system = 0
        case english = 1
        case simplifiedChinese = 2

        var language: L10n.AppLanguage {
            switch self {
            case .system: return .system
            case .english: return .english
            case .simplifiedChinese: return .simplifiedChinese
            }
        }

        var title: String {
            language.title
        }

        var symbol: String {
            language.symbol
        }
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 420))

        let appearanceTitle = makeSectionTitle(L10n.tr("settings.theme.title", "Appearance"))
        root.addSubview(appearanceTitle)

        // 三个选项卡片
        let appearanceStack = makeOptionStack()
        root.addSubview(appearanceStack)
        self.appearanceStack = appearanceStack

        let saved = UserDefaults.standard.integer(forKey: "AropytEditor.theme")

        for opt in ThemeOption.allCases {
            let card = makeCard(
                title: opt.title,
                symbol: opt.symbol,
                selected: opt.rawValue == saved,
                tag: opt.rawValue,
                action: #selector(themeSelected(_:))
            )
            appearanceStack.addArrangedSubview(card)
        }

        let languageTitle = makeSectionTitle(L10n.tr("settings.language.title", "Language"))
        root.addSubview(languageTitle)

        let languageStack = makeOptionStack()
        root.addSubview(languageStack)
        self.languageStack = languageStack

        let currentLanguage = L10n.currentLanguage
        for opt in LanguageOption.allCases {
            let card = makeCard(
                title: opt.title,
                symbol: opt.symbol,
                selected: opt.language == currentLanguage,
                tag: opt.rawValue,
                action: #selector(languageSelected(_:))
            )
            languageStack.addArrangedSubview(card)
        }

        NSLayoutConstraint.activate([
            appearanceTitle.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            appearanceTitle.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            appearanceStack.topAnchor.constraint(equalTo: appearanceTitle.bottomAnchor, constant: 18),
            appearanceStack.centerXAnchor.constraint(equalTo: root.centerXAnchor),

            languageTitle.topAnchor.constraint(equalTo: appearanceStack.bottomAnchor, constant: 32),
            languageTitle.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            languageStack.topAnchor.constraint(equalTo: languageTitle.bottomAnchor, constant: 18),
            languageStack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
        ])

        self.view = root
    }

    private func makeSectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func makeOptionStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func makeCard(title: String,
                          symbol: String,
                          selected: Bool,
                          tag: Int,
                          action: Selector) -> NSView {
        let card = NSView(frame: NSRect(x: 0, y: 0, width: 132, height: 100))
        card.wantsLayer = true
        card.layer?.cornerRadius = 10
        card.layer?.borderWidth = selected ? 2 : 1
        card.layer?.borderColor = selected
            ? NSColor.controlAccentColor.cgColor
            : NSColor.separatorColor.cgColor
        card.translatesAutoresizingMaskIntoConstraints = false

        let imgView = NSImageView()
        imgView.image = NSImage(systemSymbolName: symbol,
                                accessibilityDescription: title)
        imgView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 28, weight: .light)
        imgView.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(imgView)

        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(label)

        let btn = NSButton(title: "", target: self, action: action)
        btn.tag = tag
        btn.isTransparent = true
        btn.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(btn)

        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: 132),
            card.heightAnchor.constraint(equalToConstant: 100),
            imgView.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            imgView.centerYAnchor.constraint(equalTo: card.centerYAnchor, constant: -10),
            label.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            label.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: imgView.bottomAnchor, constant: 8),
            btn.topAnchor.constraint(equalTo: card.topAnchor),
            btn.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            btn.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            btn.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])

        return card
    }

    @objc private func themeSelected(_ sender: NSButton) {
        let value = sender.tag
        UserDefaults.standard.set(value, forKey: "AropytEditor.theme")

        // 应用主题
        switch value {
        case 1:  NSApp.appearance = NSAppearance(named: .aqua)
        case 2:  NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil  // 跟随系统
        }

        updateSelection(in: appearanceStack, selectedIndex: value)
    }

    @objc private func languageSelected(_ sender: NSButton) {
        guard let option = LanguageOption(rawValue: sender.tag) else { return }
        L10n.setLanguage(option.language)
    }

    private func updateSelection(in stack: NSStackView?, selectedIndex: Int) {
        guard let stack else { return }
        for (i, card) in stack.arrangedSubviews.enumerated() {
            card.layer?.borderWidth = (i == selectedIndex) ? 2 : 1
            card.layer?.borderColor = (i == selectedIndex)
                ? NSColor.controlAccentColor.cgColor
                : NSColor.separatorColor.cgColor
        }
    }
}
