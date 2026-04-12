import AppKit

/// Theme tab：深色 / 浅色 / 跟随系统。
final class ThemeTabViewController: NSViewController {

    private enum ThemeOption: Int, CaseIterable {
        case system = 0
        case light = 1
        case dark = 2

        var title: String {
            switch self {
            case .system: return "Follow System"
            case .light:  return "Light"
            case .dark:   return "Dark"
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

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 376))

        let titleLabel = NSTextField(labelWithString: "Appearance")
        titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(titleLabel)

        // 三个选项卡片
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        let saved = UserDefaults.standard.integer(forKey: "AropytEditor.theme")

        for opt in ThemeOption.allCases {
            let card = makeCard(opt, selected: opt.rawValue == saved)
            stack.addArrangedSubview(card)
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            titleLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            stack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 24),
            stack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
        ])

        self.view = root
    }

    private func makeCard(_ option: ThemeOption, selected: Bool) -> NSView {
        let card = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 100))
        card.wantsLayer = true
        card.layer?.cornerRadius = 10
        card.layer?.borderWidth = selected ? 2 : 1
        card.layer?.borderColor = selected
            ? NSColor.controlAccentColor.cgColor
            : NSColor.separatorColor.cgColor
        card.translatesAutoresizingMaskIntoConstraints = false

        let imgView = NSImageView()
        imgView.image = NSImage(systemSymbolName: option.symbol,
                                accessibilityDescription: option.title)
        imgView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 28, weight: .light)
        imgView.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(imgView)

        let label = NSTextField(labelWithString: option.title)
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(label)

        let btn = NSButton(title: "", target: self, action: #selector(themeSelected(_:)))
        btn.tag = option.rawValue
        btn.isTransparent = true
        btn.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(btn)

        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: 120),
            card.heightAnchor.constraint(equalToConstant: 100),
            imgView.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            imgView.centerYAnchor.constraint(equalTo: card.centerYAnchor, constant: -10),
            label.centerXAnchor.constraint(equalTo: card.centerXAnchor),
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

        // 刷新 UI 显示选中状态
        if let stack = view.subviews.compactMap({ $0 as? NSStackView }).first {
            for (i, card) in stack.arrangedSubviews.enumerated() {
                card.layer?.borderWidth = (i == value) ? 2 : 1
                card.layer?.borderColor = (i == value)
                    ? NSColor.controlAccentColor.cgColor
                    : NSColor.separatorColor.cgColor
            }
        }
    }
}
