import Foundation
import Testing
@testable import AropytEditor

@Suite("Syntax preferences")
struct SyntaxPreferencesTests {
    @Test func syntaxDefaultsAndPersistence() {
        let suiteName = "SyntaxPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = SyntaxPreferences(defaults: defaults)
        #expect(!preferences.supportsBackslashMathDelimiters)
        #expect(!preferences.supportsMathCodeBlocks)
        #expect(preferences.showsCodeBlockLineNumbers)
        #expect(preferences.wrapsCodeBlockLines)

        preferences.supportsBackslashMathDelimiters = true
        preferences.supportsMathCodeBlocks = true
        preferences.showsCodeBlockLineNumbers = false
        preferences.wrapsCodeBlockLines = false
        let reloaded = SyntaxPreferences(defaults: defaults)
        #expect(reloaded.supportsBackslashMathDelimiters)
        #expect(reloaded.supportsMathCodeBlocks)
        #expect(!reloaded.showsCodeBlockLineNumbers)
        #expect(!reloaded.wrapsCodeBlockLines)

        preferences.supportsBackslashMathDelimiters = false
        preferences.supportsMathCodeBlocks = false
        preferences.showsCodeBlockLineNumbers = true
        preferences.wrapsCodeBlockLines = true
        #expect(!SyntaxPreferences(defaults: defaults).supportsBackslashMathDelimiters)
        #expect(!SyntaxPreferences(defaults: defaults).supportsMathCodeBlocks)
        #expect(SyntaxPreferences(defaults: defaults).showsCodeBlockLineNumbers)
        #expect(SyntaxPreferences(defaults: defaults).wrapsCodeBlockLines)
    }
}
