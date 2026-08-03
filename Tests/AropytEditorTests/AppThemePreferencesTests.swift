import Foundation
import Testing
@testable import AropytEditor

@Suite("App theme preferences")
struct AppThemePreferencesTests {
    @Test func defaultsToSystemAndPersistsSelection() {
        let suiteName = "AppThemePreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = AppThemePreferences(defaults: defaults)
        #expect(preferences.theme == .system)

        preferences.theme = .light
        #expect(AppThemePreferences(defaults: defaults).theme == .light)

        preferences.theme = .dark
        #expect(AppThemePreferences(defaults: defaults).theme == .dark)
    }

    @Test func invalidStoredValueFallsBackToSystem() {
        let suiteName = "AppThemePreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(99, forKey: "AropytEditor.theme")
        #expect(AppThemePreferences(defaults: defaults).theme == .system)
    }
}
