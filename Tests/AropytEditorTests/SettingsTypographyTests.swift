import AppKit
import Testing
@testable import AropytEditor

@Suite("Settings typography")
@MainActor
struct SettingsTypographyTests {
    @Test func themeUsesLargeSectionTitlesAndRegularItems() throws {
        _ = NSApplication.shared
        let root = ThemeTabViewController().view

        for title in [
            L10n.tr("settings.theme.title", "Appearance"),
            L10n.tr("settings.language.title", "Language"),
        ] {
            let label = try #require(textField(with: title, in: root))
            #expect(label.font?.pointSize == 18)
            #expect(isBold(label.font))
        }

        for item in [
            L10n.tr("settings.theme.option.system", "Follow System"),
            L10n.tr("settings.theme.option.light", "Light"),
            L10n.tr("settings.theme.option.dark", "Dark"),
            L10n.tr("settings.language.option.english", "English"),
            L10n.tr("settings.language.option.zh_hans", "Simplified Chinese"),
        ] {
            let label = try #require(textField(with: item, in: root))
            #expect(isRegular(label.font))
        }
    }

    @Test func aboutKeepsSectionTitleLargeAndPermissionItemsRegular() throws {
        _ = NSApplication.shared
        let root = AboutTabViewController().view
        let section = try #require(textField(
            with: L10n.tr("settings.about.permissions.title", "Permissions"),
            in: root
        ))
        #expect(section.font?.pointSize == 16)
        #expect(isBold(section.font))

        for item in [
            L10n.tr("settings.about.permissions.files.title", "File Access"),
            L10n.tr("settings.about.permissions.links.title", "External Links"),
            L10n.tr("settings.about.permissions.network.title", "Network"),
            L10n.tr("settings.about.permissions.local_data.title", "Local Data"),
        ] {
            let label = try #require(textField(with: item, in: root))
            #expect(isRegular(label.font))
        }
    }

    @Test func shortcutRowsAndRecorderUseRegularFonts() throws {
        _ = NSApplication.shared
        let controller = ShortcutsTabViewController()
        let root = controller.view
        let table = try #require(firstSubview(of: NSTableView.self, in: root))
        let actionCell = try #require(
            controller.tableView(table, viewFor: table.tableColumns[0], row: 0)
                as? NSTableCellView
        )
        let shortcutCell = try #require(
            controller.tableView(table, viewFor: table.tableColumns[1], row: 0)
                as? NSTableCellView
        )
        #expect(isRegular(actionCell.textField?.font))
        let shortcutLabel = try #require(firstSubview(of: NSTextField.self, in: shortcutCell))
        #expect(isRegular(shortcutLabel.font))
    }

    private func textField(with text: String, in root: NSView) -> NSTextField? {
        allSubviews(of: NSTextField.self, in: root).first { $0.stringValue == text }
    }

    private func allSubviews<T: NSView>(of type: T.Type, in root: NSView) -> [T] {
        var matches = root as? T != nil ? [root as! T] : []
        for subview in root.subviews {
            matches.append(contentsOf: allSubviews(of: type, in: subview))
        }
        return matches
    }

    private func firstSubview<T: NSView>(of type: T.Type, in root: NSView) -> T? {
        if let match = root as? T { return match }
        for subview in root.subviews {
            if let match = firstSubview(of: type, in: subview) { return match }
        }
        return nil
    }

    private func isBold(_ font: NSFont?) -> Bool {
        guard let font else { return false }
        return NSFontManager.shared.traits(of: font).contains(.boldFontMask)
    }

    private func isRegular(_ font: NSFont?) -> Bool {
        guard font != nil else { return false }
        return !isBold(font)
    }
}
