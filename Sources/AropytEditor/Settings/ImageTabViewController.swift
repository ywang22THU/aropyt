import AppKit

final class ImageTabViewController: NSViewController, NSTextFieldDelegate {
    private let preferences: ImagePastePreferences
    private let titleLabel = NSTextField(labelWithString: "")
    private let destinationLabel = NSTextField(labelWithString: "")
    private let originalPathButton = NSButton(radioButtonWithTitle: "", target: nil, action: nil)
    private let currentDirectoryButton = NSButton(radioButtonWithTitle: "", target: nil, action: nil)
    private let resourceDirectoryButton = NSButton(radioButtonWithTitle: "", target: nil, action: nil)
    private let resourceDirectoryLabel = NSTextField(labelWithString: "")
    private let resourceDirectoryField = NSTextField()
    private let escapeURLsCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)

    init(preferences: ImagePastePreferences = .shared) {
        self.preferences = preferences
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        destinationLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        destinationLabel.identifier = NSUserInterfaceItemIdentifier("image.destination.title")

        configureDestinationButton(
            originalPathButton,
            identifier: "image.destination.originalPath"
        )
        configureDestinationButton(
            currentDirectoryButton,
            identifier: "image.destination.currentDirectory"
        )
        configureDestinationButton(
            resourceDirectoryButton,
            identifier: "image.destination.resourceDirectory"
        )

        resourceDirectoryLabel.identifier = NSUserInterfaceItemIdentifier(
            "image.resourceDirectory.title"
        )
        resourceDirectoryField.delegate = self
        resourceDirectoryField.target = self
        resourceDirectoryField.action = #selector(resourceDirectoryChanged(_:))
        resourceDirectoryField.identifier = NSUserInterfaceItemIdentifier(
            "image.resourceDirectory.name"
        )

        escapeURLsCheckbox.target = self
        escapeURLsCheckbox.action = #selector(escapeURLsChanged(_:))
        escapeURLsCheckbox.identifier = NSUserInterfaceItemIdentifier("image.escapeURLs")

        for control in [titleLabel, destinationLabel, originalPathButton,
                        currentDirectoryButton, resourceDirectoryButton,
                        resourceDirectoryLabel, resourceDirectoryField,
                        escapeURLsCheckbox] {
            control.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(control)
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),
            titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -28),

            destinationLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 28),
            destinationLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            destinationLabel.widthAnchor.constraint(equalToConstant: 140),

            originalPathButton.topAnchor.constraint(equalTo: destinationLabel.topAnchor),
            originalPathButton.leadingAnchor.constraint(
                equalTo: destinationLabel.trailingAnchor,
                constant: 12
            ),
            currentDirectoryButton.topAnchor.constraint(
                equalTo: originalPathButton.bottomAnchor,
                constant: 8
            ),
            currentDirectoryButton.leadingAnchor.constraint(equalTo: originalPathButton.leadingAnchor),
            resourceDirectoryButton.topAnchor.constraint(
                equalTo: currentDirectoryButton.bottomAnchor,
                constant: 8
            ),
            resourceDirectoryButton.leadingAnchor.constraint(equalTo: originalPathButton.leadingAnchor),

            resourceDirectoryLabel.topAnchor.constraint(
                equalTo: resourceDirectoryButton.bottomAnchor,
                constant: 28
            ),
            resourceDirectoryLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            resourceDirectoryLabel.widthAnchor.constraint(equalTo: destinationLabel.widthAnchor),
            resourceDirectoryField.centerYAnchor.constraint(equalTo: resourceDirectoryLabel.centerYAnchor),
            resourceDirectoryField.leadingAnchor.constraint(
                equalTo: resourceDirectoryLabel.trailingAnchor,
                constant: 12
            ),
            resourceDirectoryField.widthAnchor.constraint(equalToConstant: 220),

            escapeURLsCheckbox.topAnchor.constraint(
                equalTo: resourceDirectoryLabel.bottomAnchor,
                constant: 28
            ),
            escapeURLsCheckbox.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            escapeURLsCheckbox.trailingAnchor.constraint(
                lessThanOrEqualTo: root.trailingAnchor,
                constant: -28
            ),
        ])

        self.view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesDidChange(_:)),
            name: ImagePastePreferences.didChangeNotification,
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

    @objc private func destinationChanged(_ sender: NSButton) {
        switch sender {
        case originalPathButton:
            preferences.destination = .originalPath
        case currentDirectoryButton:
            preferences.destination = .currentDirectory
        case resourceDirectoryButton:
            preferences.destination = .resourceDirectory
        default:
            return
        }
        reloadValues()
    }

    @objc private func resourceDirectoryChanged(_ sender: NSTextField) {
        preferences.resourceDirectoryName = sender.stringValue
        reloadValues()
    }

    @objc private func escapeURLsChanged(_ sender: NSButton) {
        preferences.escapesImageURLs = sender.state == .on
    }

    @objc private func preferencesDidChange(_ notification: Notification) {
        reloadValues()
    }

    @objc private func languageDidChange(_ notification: Notification) {
        updateLocalization()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        resourceDirectoryChanged(resourceDirectoryField)
    }

    private func reloadValues() {
        let destination = preferences.destination
        originalPathButton.state = destination == .originalPath ? .on : .off
        currentDirectoryButton.state = destination == .currentDirectory ? .on : .off
        resourceDirectoryButton.state = destination == .resourceDirectory ? .on : .off
        resourceDirectoryField.stringValue = preferences.resourceDirectoryName
        resourceDirectoryField.isEnabled = destination == .resourceDirectory
        resourceDirectoryLabel.textColor = destination == .resourceDirectory
            ? .labelColor
            : .disabledControlTextColor
        escapeURLsCheckbox.state = preferences.escapesImageURLs ? .on : .off
    }

    private func updateLocalization() {
        titleLabel.stringValue = L10n.tr("settings.image.title", "Images")
        destinationLabel.stringValue = L10n.tr(
            "settings.image.destination.title",
            "Insert Image Location"
        )
        originalPathButton.title = L10n.tr(
            "settings.image.destination.original_path",
            "Original path (do not copy)"
        )
        currentDirectoryButton.title = L10n.tr(
            "settings.image.destination.current_directory",
            "Copy to current directory (./)"
        )
        resourceDirectoryButton.title = L10n.tr(
            "settings.image.destination.resource_directory",
            "Copy to resource directory (./assets/)"
        )
        resourceDirectoryLabel.stringValue = L10n.tr(
            "settings.image.resource_directory_name",
            "Resource Directory Name"
        )
        escapeURLsCheckbox.title = L10n.tr(
            "settings.image.escape_urls",
            "Automatically escape image URLs when inserting"
        )
    }

    private func configureDestinationButton(_ button: NSButton, identifier: String) {
        button.target = self
        button.action = #selector(destinationChanged(_:))
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
    }
}
