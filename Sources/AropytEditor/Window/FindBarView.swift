import AppKit

enum DocumentFindDirection {
    case initial
    case next
    case previous
}

struct DocumentFindResult: Equatable {
    let currentIndex: Int?
    /// WebKit reports only whether a match exists, so this is nil when the
    /// preview has a match whose total count is unavailable.
    let totalMatches: Int?

    var found: Bool { totalMatches.map { $0 > 0 } ?? true }
}

struct DocumentReplaceResult: Equatable {
    let replacements: Int
    let findResult: DocumentFindResult?
}

final class FindBarView: NSVisualEffectView, NSSearchFieldDelegate {
    var onQueryChanged: ((String) -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onReplaceCurrent: (() -> Void)?
    var onReplaceAll: (() -> Void)?
    var onClose: (() -> Void)?

    private let searchField = FindSearchField()
    private let replacementField = FindTextField()
    private let resultLabel = NSTextField(labelWithString: "")
    private let disclosureButton = NSButton()
    private let previousButton = NSButton()
    private let nextButton = NSButton()
    private let closeButton = NSButton()
    private let replaceButton = NSButton()
    private let replaceAllButton = NSButton()
    private let replacementRow = NSStackView()

    var query: String { searchField.stringValue }
    var replacement: String { replacementField.stringValue }
    var hasQuery: Bool { !query.isEmpty }
    private(set) var isReplaceVisible = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func focus(in window: NSWindow?) {
        window?.makeFirstResponder(searchField)
        searchField.selectText(nil)
    }

    func showReplace() {
        setReplaceVisible(true)
    }

    func setResult(_ result: DocumentFindResult?) {
        guard let result else {
            resultLabel.stringValue = ""
            return
        }
        guard result.found else {
            resultLabel.stringValue = L10n.tr("find.no_results", "No results")
            return
        }
        if let currentIndex = result.currentIndex, let totalMatches = result.totalMatches {
            resultLabel.stringValue = "\(currentIndex + 1)/\(totalMatches)"
        } else {
            resultLabel.stringValue = ""
        }
    }

    func updateLocalization() {
        searchField.placeholderString = L10n.tr("find.placeholder", "Find in document")
        replacementField.placeholderString = L10n.tr("find.replace_placeholder", "Replace with")
        disclosureButton.toolTip = L10n.tr("find.toggle_replace", "Toggle Replace")
        disclosureButton.setAccessibilityLabel(disclosureButton.toolTip ?? "")
        previousButton.toolTip = L10n.tr("find.previous", "Previous Match")
        previousButton.setAccessibilityLabel(previousButton.toolTip ?? "")
        nextButton.toolTip = L10n.tr("find.next", "Next Match")
        nextButton.setAccessibilityLabel(nextButton.toolTip ?? "")
        closeButton.toolTip = L10n.tr("find.close", "Close Find")
        closeButton.setAccessibilityLabel(closeButton.toolTip ?? "")
        replaceButton.title = L10n.tr("find.replace", "Replace")
        replaceButton.toolTip = replaceButton.title
        replaceButton.setAccessibilityLabel(replaceButton.title)
        replaceAllButton.title = L10n.tr("find.replace_all", "Replace All")
        replaceAllButton.toolTip = replaceAllButton.title
        replaceAllButton.setAccessibilityLabel(replaceAllButton.title)
    }

    private func configure() {
        material = .popover
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true

        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(submitSearch(_:))
        searchField.onCancel = { [weak self] in self?.onClose?() }
        replacementField.target = self
        replacementField.action = #selector(replaceCurrent(_:))
        replacementField.onCancel = { [weak self] in self?.onClose?() }

        resultLabel.alignment = .right
        resultLabel.textColor = .secondaryLabelColor
        resultLabel.lineBreakMode = .byClipping
        resultLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        configureButton(disclosureButton, symbol: "chevron.right", action: #selector(toggleReplace(_:)))
        configureButton(previousButton, symbol: "chevron.up", action: #selector(previousMatch(_:)))
        configureButton(nextButton, symbol: "chevron.down", action: #selector(nextMatch(_:)))
        configureButton(closeButton, symbol: "xmark", action: #selector(closeFind(_:)))

        let searchRow = NSStackView(
            views: [disclosureButton, searchField, resultLabel, previousButton, nextButton, closeButton]
        )
        searchRow.orientation = .horizontal
        searchRow.alignment = .centerY
        searchRow.spacing = 6

        let replacementIndent = NSView()
        replacementIndent.translatesAutoresizingMaskIntoConstraints = false
        replacementIndent.widthAnchor.constraint(equalToConstant: 24).isActive = true
        configureTextButton(replaceButton, action: #selector(replaceCurrent(_:)))
        configureTextButton(replaceAllButton, action: #selector(replaceAll(_:)))
        replacementRow.setViews(
            [replacementIndent, replacementField, replaceButton, replaceAllButton],
            in: .leading
        )
        replacementRow.orientation = .horizontal
        replacementRow.alignment = .centerY
        replacementRow.spacing = 6
        replacementRow.isHidden = true

        let rows = NSStackView(views: [searchRow, replacementRow])
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 4
        rows.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rows)

        searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 190).isActive = true
        replacementField.widthAnchor.constraint(equalTo: searchField.widthAnchor).isActive = true
        resultLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 54).isActive = true
        for button in [disclosureButton, previousButton, nextButton, closeButton] {
            button.widthAnchor.constraint(equalToConstant: 24).isActive = true
            button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        }
        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            rows.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            rows.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            rows.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])

        updateReplaceActionsEnabled()
        updateLocalization()
    }

    private func configureButton(_ button: NSButton, symbol: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.isBordered = false
        button.bezelStyle = .inline
        button.target = self
        button.action = action
    }

    private func configureTextButton(_ button: NSButton, action: Selector) {
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.target = self
        button.action = action
    }

    private func setReplaceVisible(_ visible: Bool) {
        guard visible != isReplaceVisible else { return }
        isReplaceVisible = visible
        replacementRow.isHidden = !visible
        disclosureButton.image = NSImage(
            systemSymbolName: visible ? "chevron.down" : "chevron.right",
            accessibilityDescription: nil
        )
    }

    private func updateReplaceActionsEnabled() {
        replaceButton.isEnabled = hasQuery
        replaceAllButton.isEnabled = hasQuery
    }

    func controlTextDidChange(_ obj: Notification) {
        updateReplaceActionsEnabled()
        onQueryChanged?(query)
    }

    @objc private func toggleReplace(_ sender: Any?) {
        setReplaceVisible(!isReplaceVisible)
    }

    @objc private func submitSearch(_ sender: Any?) {
        if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
            onPrevious?()
        } else {
            onNext?()
        }
    }

    @objc private func previousMatch(_ sender: Any?) {
        onPrevious?()
    }

    @objc private func nextMatch(_ sender: Any?) {
        onNext?()
    }

    @objc private func replaceCurrent(_ sender: Any?) {
        guard hasQuery else {
            focus(in: window)
            return
        }
        onReplaceCurrent?()
    }

    @objc private func replaceAll(_ sender: Any?) {
        guard hasQuery else {
            focus(in: window)
            return
        }
        onReplaceAll?()
    }

    @objc private func closeFind(_ sender: Any?) {
        onClose?()
    }
}

private final class FindSearchField: NSSearchField {
    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

private final class FindTextField: NSTextField {
    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
