import AppKit

/// About tab：展示应用信息和权限说明。
final class AboutTabViewController: NSViewController {

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 420))

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        let iconView = NSImageView()
        iconView.image = Self.appIcon()
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(iconView)

        let nameLabel = NSTextField(labelWithString: Self.appDisplayName())
        nameLabel.font = NSFont.systemFont(ofSize: 24, weight: .semibold)
        nameLabel.alignment = .center
        nameLabel.textColor = .labelColor
        stack.addArrangedSubview(nameLabel)

        let versionLabel = NSTextField(labelWithString: Self.versionText())
        versionLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        versionLabel.alignment = .center
        versionLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(versionLabel)

        let sectionTitle = NSTextField(labelWithString: L10n.tr(
            "settings.about.permissions.title",
            "Permissions"
        ))
        sectionTitle.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        sectionTitle.textColor = .labelColor
        sectionTitle.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(sectionTitle)

        let permissionStack = NSStackView()
        permissionStack.orientation = .vertical
        permissionStack.alignment = .leading
        permissionStack.spacing = 14
        permissionStack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(permissionStack)

        for item in Self.permissionItems() {
            permissionStack.addArrangedSubview(makePermissionRow(item))
        }

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),
            stack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 82),
            iconView.heightAnchor.constraint(equalToConstant: 82),

            sectionTitle.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: 34),
            sectionTitle.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 52),
            sectionTitle.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -52),

            permissionStack.topAnchor.constraint(equalTo: sectionTitle.bottomAnchor, constant: 16),
            permissionStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 52),
            permissionStack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -52),
        ])

        self.view = root
    }

    private func makePermissionRow(_ item: PermissionItem) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        let imageView = NSImageView()
        imageView.image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: item.title)
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        imageView.contentTintColor = .secondaryLabelColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        row.addArrangedSubview(imageView)

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3
        textStack.translatesAutoresizingMaskIntoConstraints = false
        row.addArrangedSubview(textStack)

        let titleLabel = NSTextField(labelWithString: item.title)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        textStack.addArrangedSubview(titleLabel)

        let bodyLabel = NSTextField(wrappingLabelWithString: item.body)
        bodyLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        bodyLabel.textColor = .secondaryLabelColor
        bodyLabel.maximumNumberOfLines = 0
        textStack.addArrangedSubview(bodyLabel)

        NSLayoutConstraint.activate([
            row.widthAnchor.constraint(equalToConstant: 456),
            imageView.widthAnchor.constraint(equalToConstant: 24),
            imageView.heightAnchor.constraint(equalToConstant: 24),
            textStack.widthAnchor.constraint(equalToConstant: 420),
        ])

        return row
    }

    private static func appIcon() -> NSImage {
        if let image = NSImage(named: NSImage.applicationIconName) {
            return image
        }
        if
            let url = Bundle.module.url(forResource: "AropytEditor", withExtension: "icns"),
            let image = NSImage(contentsOf: url)
        {
            return image
        }
        return NSApp.applicationIconImage
    }

    private static func appDisplayName() -> String {
        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String {
            return name
        }
        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String {
            return name
        }
        return L10n.tr("app.name", "AropytEditor")
    }

    private static func versionText() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        guard !build.isEmpty else {
            return L10n.tr("settings.about.version", "Version %@", version)
        }
        return L10n.tr("settings.about.version_build", "Version %@ (%@)", version, build)
    }

    private static func permissionItems() -> [PermissionItem] {
        [
            PermissionItem(
                symbol: "doc",
                title: L10n.tr("settings.about.permissions.files.title", "File Access"),
                body: L10n.tr(
                    "settings.about.permissions.files.body",
                    "Aropyt only reads or writes Markdown files and save locations you choose through the system open/save panels."
                )
            ),
            PermissionItem(
                symbol: "safari",
                title: L10n.tr("settings.about.permissions.links.title", "External Links"),
                body: L10n.tr(
                    "settings.about.permissions.links.body",
                    "Cmd-clicking a link asks macOS to open it in your default browser."
                )
            ),
            PermissionItem(
                symbol: "network",
                title: L10n.tr("settings.about.permissions.network.title", "Network"),
                body: L10n.tr(
                    "settings.about.permissions.network.body",
                    "Aropyt has no account, telemetry, or background sync. Remote images or links in your Markdown may be loaded by preview or the browser."
                )
            ),
            PermissionItem(
                symbol: "lock",
                title: L10n.tr("settings.about.permissions.local_data.title", "Local Data"),
                body: L10n.tr(
                    "settings.about.permissions.local_data.body",
                    "Shortcuts, theme, and language preferences are stored locally in macOS user defaults."
                )
            ),
        ]
    }
}

private struct PermissionItem {
    let symbol: String
    let title: String
    let body: String
}
