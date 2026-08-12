import AppKit
import Testing
@testable import AropytEditor

@Suite("General settings UI")
@MainActor
struct GeneralSettingsUITests {
    @Test func launchBehaviorUsesRadioButtonsAndDefaultsToNewDocument() throws {
        _ = NSApplication.shared
        let suiteName = "GeneralSettingsUITests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let launchPreferences = ApplicationLaunchPreferences(defaults: defaults)
        let controller = GeneralTabViewController(
            autoSavePreferences: AutoSavePreferences(defaults: defaults),
            launchPreferences: launchPreferences,
            chooseFile: { nil }
        )
        let root = controller.view
        root.frame = NSRect(x: 0, y: 0, width: 670, height: 500)
        root.layoutSubtreeIfNeeded()

        let title = try #require(view(identifiedBy: "general.launch.title", in: root) as? NSTextField)
        #expect(title.stringValue == L10n.tr(
            "settings.launch.title",
            "Behavior at Application Launch"
        ))

        let createNew = try #require(button("general.launch.createNewDocument", in: root))
        let reopenLast = try #require(button("general.launch.reopenLastDocument", in: root))
        let openSpecific = try #require(button("general.launch.openSpecificDocument", in: root))
        #expect(createNew.state == .on)
        #expect(reopenLast.state == .off)
        #expect(openSpecific.state == .off)

        reopenLast.performClick(nil)
        #expect(launchPreferences.behavior == .reopenLastClosedDocument)
        #expect(createNew.state == .off)
        #expect(reopenLast.state == .on)
        #expect(openSpecific.state == .off)
    }

    @Test func choosingSpecificFileSelectsTheMatchingBehavior() throws {
        _ = NSApplication.shared
        let suiteName = "GeneralSettingsUITests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let selectedURL = URL(fileURLWithPath: "/tmp/selected.md")
        let launchPreferences = ApplicationLaunchPreferences(defaults: defaults)
        let controller = GeneralTabViewController(
            autoSavePreferences: AutoSavePreferences(defaults: defaults),
            launchPreferences: launchPreferences,
            chooseFile: { selectedURL }
        )
        let root = controller.view
        let openSpecific = try #require(button("general.launch.openSpecificDocument", in: root))

        openSpecific.performClick(nil)

        #expect(launchPreferences.behavior == .openSpecificDocument)
        #expect(launchPreferences.specificFileURL == selectedURL)
        #expect(openSpecific.state == .on)
    }

    private func button(_ identifier: String, in root: NSView) -> NSButton? {
        view(identifiedBy: identifier, in: root) as? NSButton
    }

    private func view(identifiedBy identifier: String, in root: NSView) -> NSView? {
        if root.identifier?.rawValue == identifier { return root }
        for subview in root.subviews {
            if let match = view(identifiedBy: identifier, in: subview) {
                return match
            }
        }
        return nil
    }
}
