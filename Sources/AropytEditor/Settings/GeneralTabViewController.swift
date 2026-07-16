import AppKit

final class GeneralTabViewController: NSViewController {
    private let preferences = AutoSavePreferences.shared
    private let titleLabel = NSTextField(labelWithString: "")
    private let modeLabel = NSTextField(labelWithString: "")
    private let modePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let delayLabel = NSTextField(labelWithString: "")
    private let delayField = NSTextField()
    private let delayStepper = NSStepper()
    private let secondsLabel = NSTextField(labelWithString: "")
    private let warningLabel = NSTextField(wrappingLabelWithString: "")

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        modePopup.target = self
        modePopup.action = #selector(modeChanged(_:))

        let formatter = NumberFormatter()
        formatter.minimum = NSNumber(value: AutoSavePreferences.validDelayRange.lowerBound)
        formatter.maximum = NSNumber(value: AutoSavePreferences.validDelayRange.upperBound)
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        delayField.formatter = formatter
        delayField.alignment = .right
        delayField.target = self
        delayField.action = #selector(delayFieldChanged(_:))

        delayStepper.minValue = AutoSavePreferences.validDelayRange.lowerBound
        delayStepper.maxValue = AutoSavePreferences.validDelayRange.upperBound
        delayStepper.increment = 0.5
        delayStepper.target = self
        delayStepper.action = #selector(delayStepperChanged(_:))

        warningLabel.textColor = .systemOrange
        warningLabel.maximumNumberOfLines = 0

        for control in [titleLabel, modeLabel, modePopup, delayLabel, delayField,
                        delayStepper, secondsLabel, warningLabel] {
            control.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(control)
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),
            titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -28),

            modeLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 28),
            modeLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            modeLabel.widthAnchor.constraint(equalToConstant: 110),
            modePopup.centerYAnchor.constraint(equalTo: modeLabel.centerYAnchor),
            modePopup.leadingAnchor.constraint(equalTo: modeLabel.trailingAnchor, constant: 12),
            modePopup.widthAnchor.constraint(equalToConstant: 190),

            delayLabel.topAnchor.constraint(equalTo: modeLabel.bottomAnchor, constant: 22),
            delayLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            delayLabel.widthAnchor.constraint(equalTo: modeLabel.widthAnchor),
            delayField.centerYAnchor.constraint(equalTo: delayLabel.centerYAnchor),
            delayField.leadingAnchor.constraint(equalTo: delayLabel.trailingAnchor, constant: 12),
            delayField.widthAnchor.constraint(equalToConstant: 64),
            delayStepper.centerYAnchor.constraint(equalTo: delayField.centerYAnchor),
            delayStepper.leadingAnchor.constraint(equalTo: delayField.trailingAnchor, constant: 4),
            secondsLabel.centerYAnchor.constraint(equalTo: delayField.centerYAnchor),
            secondsLabel.leadingAnchor.constraint(equalTo: delayStepper.trailingAnchor, constant: 8),

            warningLabel.topAnchor.constraint(equalTo: delayLabel.bottomAnchor, constant: 26),
            warningLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            warningLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
        ])

        self.view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesDidChange(_:)),
            name: AutoSavePreferences.didChangeNotification,
            object: preferences
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange(_:)),
            name: L10n.didChangeNotification,
            object: nil
        )
        updateLocalization()
        reloadValues()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func modeChanged(_ sender: NSPopUpButton) {
        let modes = AutoSaveMode.allCases
        guard modes.indices.contains(sender.indexOfSelectedItem) else { return }
        preferences.mode = modes[sender.indexOfSelectedItem]
        reloadValues()
    }

    @objc private func delayFieldChanged(_ sender: NSTextField) {
        preferences.delay = sender.doubleValue
        reloadValues()
    }

    @objc private func delayStepperChanged(_ sender: NSStepper) {
        preferences.delay = sender.doubleValue
        reloadValues()
    }

    @objc private func preferencesDidChange(_ notification: Notification) {
        reloadValues()
    }

    @objc private func languageDidChange(_ notification: Notification) {
        updateLocalization()
        reloadValues()
    }

    private func reloadValues() {
        let modes = AutoSaveMode.allCases
        modePopup.selectItem(at: modes.firstIndex(of: preferences.mode) ?? 0)
        delayField.doubleValue = preferences.delay
        delayStepper.doubleValue = preferences.delay
        let delayEnabled = preferences.mode == .afterDelay
        delayField.isEnabled = delayEnabled
        delayStepper.isEnabled = delayEnabled
        secondsLabel.textColor = delayEnabled ? .labelColor : .disabledControlTextColor
        warningLabel.isHidden = preferences.mode != .onChange
    }

    private func updateLocalization() {
        titleLabel.stringValue = L10n.tr("settings.general.title", "General")
        modeLabel.stringValue = L10n.tr("settings.autosave.mode", "Auto Save")
        delayLabel.stringValue = L10n.tr("settings.autosave.delay", "Delay")
        secondsLabel.stringValue = L10n.tr("settings.autosave.seconds", "seconds")
        warningLabel.stringValue = L10n.tr(
            "settings.autosave.on_change_warning",
            "On Change can cause high CPU usage: editing a long document in Preview repeatedly converts the full document."
        )
        modePopup.removeAllItems()
        modePopup.addItems(withTitles: AutoSaveMode.allCases.map { mode in
            switch mode {
            case .onChange:
                return L10n.tr("settings.autosave.mode.on_change", "On Change")
            case .afterDelay:
                return L10n.tr("settings.autosave.mode.after_delay", "After Delay")
            case .never:
                return L10n.tr("settings.autosave.mode.never", "Never")
            }
        })
    }
}
