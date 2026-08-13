import AppKit
import Testing
@testable import AropytEditor

@Suite("Image settings UI")
@MainActor
struct ImageSettingsUITests {
    @Test func settingsSidebarIncludesImageTab() throws {
        _ = NSApplication.shared
        let controller = SettingsTabViewController()
        _ = controller.view

        let table = try #require(firstSubview(of: NSTableView.self, in: controller.view))
        #expect(table.numberOfRows == 6)
        let cell = try #require(
            table.view(atColumn: 0, row: 4, makeIfNecessary: true) as? NSTableCellView
        )
        #expect(cell.textField?.stringValue == L10n.tr("settings.tabs.image", "Images"))
    }

    @Test func imageTabControlsPreferencesAndResourceFieldAvailability() throws {
        _ = NSApplication.shared
        let suiteName = "ImageSettingsUITests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = ImagePastePreferences(defaults: defaults)
        let controller = ImageTabViewController(preferences: preferences)
        let root = controller.view

        let original = try #require(view(
            identifiedBy: "image.destination.originalPath",
            in: root
        ) as? NSButton)
        let resource = try #require(view(
            identifiedBy: "image.destination.resourceDirectory",
            in: root
        ) as? NSButton)
        let name = try #require(view(
            identifiedBy: "image.resourceDirectory.name",
            in: root
        ) as? NSTextField)
        let escape = try #require(view(identifiedBy: "image.escapeURLs", in: root) as? NSButton)
        let destinationTitle = try #require(view(
            identifiedBy: "image.destination.title",
            in: root
        ) as? NSTextField)
        let resourceTitle = try #require(view(
            identifiedBy: "image.resourceDirectory.title",
            in: root
        ) as? NSTextField)

        #expect(original.state == .on)
        #expect(isRegular(destinationTitle.font))
        #expect(isRegular(resourceTitle.font))
        #expect(isRegular(original.font))
        #expect(isRegular(escape.font))
        #expect(!name.isEnabled)
        #expect(escape.state == .on)

        resource.performClick(nil)
        #expect(preferences.destination == .resourceDirectory)
        #expect(name.isEnabled)

        name.stringValue = "illustrations"
        name.sendAction(name.action, to: name.target)
        #expect(preferences.resourceDirectoryName == "illustrations")
        #expect(resource.title.contains("./illustrations/"))

        name.stringValue = "../outside"
        name.sendAction(name.action, to: name.target)
        #expect(preferences.resourceDirectoryName == "illustrations")
        #expect(name.stringValue == "illustrations")

        escape.performClick(nil)
        #expect(!preferences.escapesImageURLs)
    }

    private func view(identifiedBy identifier: String, in root: NSView) -> NSView? {
        if root.identifier?.rawValue == identifier { return root }
        for subview in root.subviews {
            if let match = view(identifiedBy: identifier, in: subview) { return match }
        }
        return nil
    }

    private func firstSubview<T: NSView>(of type: T.Type, in root: NSView) -> T? {
        if let match = root as? T { return match }
        for subview in root.subviews {
            if let match = firstSubview(of: type, in: subview) { return match }
        }
        return nil
    }

    private func isRegular(_ font: NSFont?) -> Bool {
        guard let font else { return false }
        return !NSFontManager.shared.traits(of: font).contains(.boldFontMask)
    }
}
