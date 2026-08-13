import AppKit

final class SyntaxTabViewController: NSViewController {
    private let preferences: SyntaxPreferences
    private let titleLabel = NSTextField(labelWithString: "")
    private let mathTitleLabel = NSTextField(labelWithString: "")
    private let backslashMathCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let warningLabel = NSTextField(wrappingLabelWithString: "")
    private let mathCodeBlockCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let codeBlockTitleLabel = NSTextField(labelWithString: "")
    private let lineNumbersCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let lineWrappingCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)

    init(preferences: SyntaxPreferences = .shared) {
        self.preferences = preferences
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        mathTitleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        mathTitleLabel.identifier = NSUserInterfaceItemIdentifier("syntax.math.title")

        backslashMathCheckbox.target = self
        backslashMathCheckbox.action = #selector(backslashMathSettingChanged(_:))
        backslashMathCheckbox.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        backslashMathCheckbox.identifier = NSUserInterfaceItemIdentifier(
            "syntax.math.backslashDelimiters"
        )

        let hintFont = NSFont.systemFont(ofSize: 11)
        warningLabel.font = NSFontManager.shared.convert(
            hintFont,
            toHaveTrait: .italicFontMask
        )
        warningLabel.textColor = .secondaryLabelColor
        warningLabel.maximumNumberOfLines = 0
        warningLabel.identifier = NSUserInterfaceItemIdentifier(
            "syntax.math.backslashDelimitersWarning"
        )

        mathCodeBlockCheckbox.target = self
        mathCodeBlockCheckbox.action = #selector(mathCodeBlockSettingChanged(_:))
        mathCodeBlockCheckbox.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        mathCodeBlockCheckbox.identifier = NSUserInterfaceItemIdentifier(
            "syntax.math.codeBlocks"
        )

        codeBlockTitleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        codeBlockTitleLabel.identifier = NSUserInterfaceItemIdentifier("syntax.codeBlock.title")

        lineNumbersCheckbox.target = self
        lineNumbersCheckbox.action = #selector(lineNumbersSettingChanged(_:))
        lineNumbersCheckbox.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        lineNumbersCheckbox.identifier = NSUserInterfaceItemIdentifier(
            "syntax.codeBlock.lineNumbers"
        )

        lineWrappingCheckbox.target = self
        lineWrappingCheckbox.action = #selector(lineWrappingSettingChanged(_:))
        lineWrappingCheckbox.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        lineWrappingCheckbox.identifier = NSUserInterfaceItemIdentifier(
            "syntax.codeBlock.lineWrapping"
        )

        for control in [titleLabel, mathTitleLabel, backslashMathCheckbox, warningLabel,
                        mathCodeBlockCheckbox, codeBlockTitleLabel, lineNumbersCheckbox,
                        lineWrappingCheckbox] {
            control.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(control)
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),
            titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -28),

            mathTitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 28),
            mathTitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            mathTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -28),

            backslashMathCheckbox.topAnchor.constraint(equalTo: mathTitleLabel.bottomAnchor, constant: 16),
            backslashMathCheckbox.leadingAnchor.constraint(equalTo: mathTitleLabel.leadingAnchor),
            backslashMathCheckbox.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -28),

            warningLabel.topAnchor.constraint(equalTo: backslashMathCheckbox.bottomAnchor, constant: 8),
            warningLabel.leadingAnchor.constraint(equalTo: backslashMathCheckbox.leadingAnchor, constant: 20),
            warningLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),

            mathCodeBlockCheckbox.topAnchor.constraint(equalTo: warningLabel.bottomAnchor, constant: 14),
            mathCodeBlockCheckbox.leadingAnchor.constraint(equalTo: mathTitleLabel.leadingAnchor),
            mathCodeBlockCheckbox.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -28),

            codeBlockTitleLabel.topAnchor.constraint(equalTo: mathCodeBlockCheckbox.bottomAnchor, constant: 30),
            codeBlockTitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            codeBlockTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -28),

            lineNumbersCheckbox.topAnchor.constraint(equalTo: codeBlockTitleLabel.bottomAnchor, constant: 16),
            lineNumbersCheckbox.leadingAnchor.constraint(equalTo: codeBlockTitleLabel.leadingAnchor),
            lineNumbersCheckbox.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -28),

            lineWrappingCheckbox.topAnchor.constraint(equalTo: lineNumbersCheckbox.bottomAnchor, constant: 12),
            lineWrappingCheckbox.leadingAnchor.constraint(equalTo: codeBlockTitleLabel.leadingAnchor),
            lineWrappingCheckbox.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -28),
        ])

        self.view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesDidChange(_:)),
            name: SyntaxPreferences.didChangeNotification,
            object: preferences
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange(_:)),
            name: L10n.didChangeNotification,
            object: nil
        )
        updateLocalization()
        reloadValue()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func backslashMathSettingChanged(_ sender: NSButton) {
        preferences.supportsBackslashMathDelimiters = sender.state == .on
    }

    @objc private func mathCodeBlockSettingChanged(_ sender: NSButton) {
        preferences.supportsMathCodeBlocks = sender.state == .on
    }

    @objc private func lineNumbersSettingChanged(_ sender: NSButton) {
        preferences.showsCodeBlockLineNumbers = sender.state == .on
    }

    @objc private func lineWrappingSettingChanged(_ sender: NSButton) {
        preferences.wrapsCodeBlockLines = sender.state == .on
    }

    @objc private func preferencesDidChange(_ notification: Notification) {
        reloadValue()
    }

    @objc private func languageDidChange(_ notification: Notification) {
        updateLocalization()
    }

    private func reloadValue() {
        backslashMathCheckbox.state = preferences.supportsBackslashMathDelimiters ? .on : .off
        mathCodeBlockCheckbox.state = preferences.supportsMathCodeBlocks ? .on : .off
        lineNumbersCheckbox.state = preferences.showsCodeBlockLineNumbers ? .on : .off
        lineWrappingCheckbox.state = preferences.wrapsCodeBlockLines ? .on : .off
    }

    private func updateLocalization() {
        titleLabel.stringValue = L10n.tr(
            "settings.syntax.title",
            "Syntax Preferences"
        )
        mathTitleLabel.stringValue = L10n.tr(
            "settings.syntax.math.title",
            "Math Formulas"
        )
        backslashMathCheckbox.title = L10n.tr(
            "settings.syntax.math.backslash_delimiters",
            "Support \\[\\] and \\(\\) math formulas"
        )
        warningLabel.stringValue = L10n.tr(
            "settings.syntax.math.backslash_delimiters_warning",
            "This syntax conflicts with Markdown bracket escaping and causes problems when editing text in Preview mode."
        )
        mathCodeBlockCheckbox.title = L10n.tr(
            "settings.syntax.math.code_blocks",
            "Support math code blocks in ```math format"
        )
        codeBlockTitleLabel.stringValue = L10n.tr(
            "settings.syntax.code_block.title",
            "Code Blocks"
        )
        lineNumbersCheckbox.title = L10n.tr(
            "settings.syntax.code_block.line_numbers",
            "Show line numbers"
        )
        lineWrappingCheckbox.title = L10n.tr(
            "settings.syntax.code_block.line_wrapping",
            "Automatic line wrapping"
        )
    }
}
