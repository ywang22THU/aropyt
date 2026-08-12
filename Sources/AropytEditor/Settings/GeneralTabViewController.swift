import AppKit
import UniformTypeIdentifiers

final class GeneralTabViewController: NSViewController {
    private let autoSavePreferences: AutoSavePreferences
    private let launchPreferences: ApplicationLaunchPreferences
    private let chooseFile: () -> URL?
    private let titleLabel = NSTextField(labelWithString: "")
    private let launchBehaviorLabel = NSTextField(labelWithString: "")
    private let createNewDocumentButton = NSButton(radioButtonWithTitle: "", target: nil, action: nil)
    private let reopenLastDocumentButton = NSButton(radioButtonWithTitle: "", target: nil, action: nil)
    private let openSpecificDocumentButton = NSButton(radioButtonWithTitle: "", target: nil, action: nil)
    private let chooseSpecificFileButton = NSButton(title: "", target: nil, action: nil)
    private let specificFileLabel = NSTextField(labelWithString: "")
    private let modeLabel = NSTextField(labelWithString: "")
    private let modePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let delayLabel = NSTextField(labelWithString: "")
    private let delayField = NSTextField()
    private let delayStepper = NSStepper()
    private let secondsLabel = NSTextField(labelWithString: "")
    private let warningLabel = NSTextField(wrappingLabelWithString: "")

    init(
        autoSavePreferences: AutoSavePreferences = .shared,
        launchPreferences: ApplicationLaunchPreferences = .shared,
        chooseFile: (() -> URL?)? = nil
    ) {
        self.autoSavePreferences = autoSavePreferences
        self.launchPreferences = launchPreferences
        self.chooseFile = chooseFile ?? Self.chooseMarkdownFile
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        launchBehaviorLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        launchBehaviorLabel.identifier = NSUserInterfaceItemIdentifier("general.launch.title")
        configureLaunchRadioButton(
            createNewDocumentButton,
            identifier: "general.launch.createNewDocument"
        )
        configureLaunchRadioButton(
            reopenLastDocumentButton,
            identifier: "general.launch.reopenLastDocument"
        )
        configureLaunchRadioButton(
            openSpecificDocumentButton,
            identifier: "general.launch.openSpecificDocument"
        )
        chooseSpecificFileButton.target = self
        chooseSpecificFileButton.action = #selector(chooseSpecificFile(_:))
        chooseSpecificFileButton.bezelStyle = .rounded
        chooseSpecificFileButton.identifier = NSUserInterfaceItemIdentifier(
            "general.launch.chooseSpecificFile"
        )
        specificFileLabel.lineBreakMode = .byTruncatingMiddle
        specificFileLabel.textColor = .secondaryLabelColor
        specificFileLabel.identifier = NSUserInterfaceItemIdentifier(
            "general.launch.specificFilePath"
        )
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

        for control in [titleLabel, launchBehaviorLabel, createNewDocumentButton,
                        reopenLastDocumentButton, openSpecificDocumentButton,
                        chooseSpecificFileButton, specificFileLabel, modeLabel,
                        modePopup, delayLabel, delayField, delayStepper,
                        secondsLabel, warningLabel] {
            control.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(control)
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),
            titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -28),

            launchBehaviorLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 28),
            launchBehaviorLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            launchBehaviorLabel.widthAnchor.constraint(equalToConstant: 140),

            createNewDocumentButton.topAnchor.constraint(equalTo: launchBehaviorLabel.topAnchor),
            createNewDocumentButton.leadingAnchor.constraint(
                equalTo: launchBehaviorLabel.trailingAnchor,
                constant: 12
            ),
            reopenLastDocumentButton.topAnchor.constraint(
                equalTo: createNewDocumentButton.bottomAnchor,
                constant: 8
            ),
            reopenLastDocumentButton.leadingAnchor.constraint(equalTo: createNewDocumentButton.leadingAnchor),
            openSpecificDocumentButton.topAnchor.constraint(
                equalTo: reopenLastDocumentButton.bottomAnchor,
                constant: 8
            ),
            openSpecificDocumentButton.leadingAnchor.constraint(equalTo: createNewDocumentButton.leadingAnchor),
            chooseSpecificFileButton.centerYAnchor.constraint(equalTo: openSpecificDocumentButton.centerYAnchor),
            chooseSpecificFileButton.leadingAnchor.constraint(
                equalTo: openSpecificDocumentButton.trailingAnchor,
                constant: 12
            ),
            specificFileLabel.topAnchor.constraint(
                equalTo: openSpecificDocumentButton.bottomAnchor,
                constant: 7
            ),
            specificFileLabel.leadingAnchor.constraint(equalTo: createNewDocumentButton.leadingAnchor),
            specificFileLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),

            modeLabel.topAnchor.constraint(equalTo: specificFileLabel.bottomAnchor, constant: 30),
            modeLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            modeLabel.widthAnchor.constraint(equalTo: launchBehaviorLabel.widthAnchor),
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
            object: autoSavePreferences
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesDidChange(_:)),
            name: ApplicationLaunchPreferences.didChangeNotification,
            object: launchPreferences
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
        autoSavePreferences.mode = modes[sender.indexOfSelectedItem]
        reloadValues()
    }

    @objc private func launchBehaviorChanged(_ sender: NSButton) {
        let behavior: ApplicationLaunchBehavior
        switch sender {
        case createNewDocumentButton:
            behavior = .createNewDocument
        case reopenLastDocumentButton:
            behavior = .reopenLastClosedDocument
        case openSpecificDocumentButton:
            if launchPreferences.specificFileURL == nil {
                guard selectSpecificFile() else {
                    reloadValues()
                    return
                }
            }
            behavior = .openSpecificDocument
        default:
            return
        }
        launchPreferences.behavior = behavior
        reloadValues()
    }

    @objc private func chooseSpecificFile(_ sender: NSButton) {
        _ = selectSpecificFile()
        reloadValues()
    }

    @objc private func delayFieldChanged(_ sender: NSTextField) {
        autoSavePreferences.delay = sender.doubleValue
        reloadValues()
    }

    @objc private func delayStepperChanged(_ sender: NSStepper) {
        autoSavePreferences.delay = sender.doubleValue
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
        let launchBehavior = launchPreferences.behavior
        createNewDocumentButton.state = launchBehavior == .createNewDocument ? .on : .off
        reopenLastDocumentButton.state = launchBehavior == .reopenLastClosedDocument ? .on : .off
        openSpecificDocumentButton.state = launchBehavior == .openSpecificDocument ? .on : .off
        if let url = launchPreferences.specificFileURL {
            specificFileLabel.stringValue = url.path
            specificFileLabel.toolTip = url.path
        } else {
            specificFileLabel.stringValue = L10n.tr(
                "settings.launch.specific_file.none",
                "No file selected"
            )
            specificFileLabel.toolTip = nil
        }

        let modes = AutoSaveMode.allCases
        modePopup.selectItem(at: modes.firstIndex(of: autoSavePreferences.mode) ?? 0)
        delayField.doubleValue = autoSavePreferences.delay
        delayStepper.doubleValue = autoSavePreferences.delay
        let delayEnabled = autoSavePreferences.mode == .afterDelay
        delayField.isEnabled = delayEnabled
        delayStepper.isEnabled = delayEnabled
        secondsLabel.textColor = delayEnabled ? .labelColor : .disabledControlTextColor
        warningLabel.isHidden = autoSavePreferences.mode != .onChange
    }

    private func updateLocalization() {
        titleLabel.stringValue = L10n.tr("settings.general.title", "General")
        launchBehaviorLabel.stringValue = L10n.tr(
            "settings.launch.title",
            "Behavior at Application Launch"
        )
        createNewDocumentButton.title = L10n.tr(
            "settings.launch.create_new",
            "Create a new document"
        )
        reopenLastDocumentButton.title = L10n.tr(
            "settings.launch.reopen_last",
            "Reopen the last closed document"
        )
        openSpecificDocumentButton.title = L10n.tr(
            "settings.launch.open_specific",
            "Open a specific document"
        )
        chooseSpecificFileButton.title = L10n.tr(
            "settings.launch.choose_file",
            "Choose…"
        )
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

    private func configureLaunchRadioButton(_ button: NSButton, identifier: String) {
        button.target = self
        button.action = #selector(launchBehaviorChanged(_:))
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
    }

    private func selectSpecificFile() -> Bool {
        guard let url = chooseFile() else { return false }
        launchPreferences.specificFileURL = url
        launchPreferences.behavior = .openSpecificDocument
        return true
    }

    private static func chooseMarkdownFile() -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "markdown") ?? .plainText,
            .plainText,
        ]
        panel.allowsOtherFileTypes = true
        panel.prompt = L10n.tr("settings.launch.choose_file", "Choose…")
        return panel.runModal() == .OK ? panel.url : nil
    }
}
