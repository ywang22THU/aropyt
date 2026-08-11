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

final class FindBarView: NSVisualEffectView, NSSearchFieldDelegate {
    var onQueryChanged: ((String) -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onClose: (() -> Void)?

    private let searchField = FindSearchField()
    private let resultLabel = NSTextField(labelWithString: "")
    private let previousButton = NSButton()
    private let nextButton = NSButton()
    private let closeButton = NSButton()

    var query: String { searchField.stringValue }
    var hasQuery: Bool { !query.isEmpty }

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
        previousButton.toolTip = L10n.tr("find.previous", "Previous Match")
        previousButton.setAccessibilityLabel(previousButton.toolTip ?? "")
        nextButton.toolTip = L10n.tr("find.next", "Next Match")
        nextButton.setAccessibilityLabel(nextButton.toolTip ?? "")
        closeButton.toolTip = L10n.tr("find.close", "Close Find")
        closeButton.setAccessibilityLabel(closeButton.toolTip ?? "")
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

        resultLabel.alignment = .right
        resultLabel.textColor = .secondaryLabelColor
        resultLabel.lineBreakMode = .byClipping
        resultLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        configureButton(previousButton, symbol: "chevron.up", action: #selector(previousMatch(_:)))
        configureButton(nextButton, symbol: "chevron.down", action: #selector(nextMatch(_:)))
        configureButton(closeButton, symbol: "xmark", action: #selector(closeFind(_:)))

        let stack = NSStackView(views: [searchField, resultLabel, previousButton, nextButton, closeButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 190).isActive = true
        resultLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 54).isActive = true
        for button in [previousButton, nextButton, closeButton] {
            button.widthAnchor.constraint(equalToConstant: 24).isActive = true
            button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])

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

    func controlTextDidChange(_ obj: Notification) {
        onQueryChanged?(query)
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
