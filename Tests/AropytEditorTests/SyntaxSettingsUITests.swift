import AppKit
import Testing
@testable import AropytEditor

@Suite("Syntax settings UI")
@MainActor
struct SyntaxSettingsUITests {
    @Test func settingsSidebarIncludesSyntaxPreferencesTab() throws {
        _ = NSApplication.shared
        let controller = SettingsTabViewController()
        _ = controller.view

        let table = try #require(firstSubview(of: NSTableView.self, in: controller.view))
        #expect(table.numberOfRows == 6)
        let cell = try #require(
            table.view(atColumn: 0, row: 3, makeIfNecessary: true) as? NSTableCellView
        )
        #expect(cell.textField?.stringValue == L10n.tr(
            "settings.tabs.syntax",
            "Syntax Preferences"
        ))
    }

    @Test func syntaxTabShowsMathOptionAndItalicWarning() throws {
        _ = NSApplication.shared
        let suiteName = "SyntaxSettingsUITests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = SyntaxTabViewController(
            preferences: SyntaxPreferences(defaults: defaults)
        )
        let root = controller.view
        root.frame = NSRect(x: 0, y: 0, width: 670, height: 500)
        root.layoutSubtreeIfNeeded()

        let section = try #require(view(
            identifiedBy: "syntax.math.title",
            in: root
        ) as? NSTextField)
        #expect(section.stringValue == L10n.tr(
            "settings.syntax.math.title",
            "Math Formulas"
        ))
        #expect(section.font?.pointSize == 15)
        #expect(NSFontManager.shared.traits(of: try #require(section.font))
            .contains(.boldFontMask))

        let checkbox = try #require(view(
            identifiedBy: "syntax.math.backslashDelimiters",
            in: root
        ) as? NSButton)
        #expect(checkbox.title.contains(#"\[\]"#))
        #expect(checkbox.title.contains(#"\(\)"#))
        #expect(!NSFontManager.shared.traits(of: try #require(checkbox.font))
            .contains(.boldFontMask))

        let warning = try #require(view(
            identifiedBy: "syntax.math.backslashDelimitersWarning",
            in: root
        ) as? NSTextField)
        #expect(warning.font?.pointSize == 11)
        let traits = warning.font.map { NSFontManager.shared.traits(of: $0) }
        #expect(traits?.contains(.italicFontMask) == true)

        let mathCodeBlocks = try #require(view(
            identifiedBy: "syntax.math.codeBlocks",
            in: root
        ) as? NSButton)
        #expect(mathCodeBlocks.title.contains("```math"))
        #expect(mathCodeBlocks.state == .off)

        let codeBlockSection = try #require(view(
            identifiedBy: "syntax.codeBlock.title",
            in: root
        ) as? NSTextField)
        #expect(codeBlockSection.stringValue == L10n.tr(
            "settings.syntax.code_block.title",
            "Code Blocks"
        ))
        #expect(codeBlockSection.font?.pointSize == section.font?.pointSize)
        #expect(NSFontManager.shared.traits(of: try #require(codeBlockSection.font))
            .contains(.boldFontMask))
        #expect(abs(codeBlockSection.frame.minX - section.frame.minX) < 0.5)

        let lineNumbers = try #require(view(
            identifiedBy: "syntax.codeBlock.lineNumbers",
            in: root
        ) as? NSButton)
        let lineWrapping = try #require(view(
            identifiedBy: "syntax.codeBlock.lineWrapping",
            in: root
        ) as? NSButton)
        #expect(lineNumbers.state == .on)
        #expect(lineWrapping.state == .on)
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

    private func firstSubview<T: NSView>(of type: T.Type, in root: NSView) -> T? {
        if let match = root as? T { return match }
        for subview in root.subviews {
            if let match = firstSubview(of: type, in: subview) {
                return match
            }
        }
        return nil
    }
}
