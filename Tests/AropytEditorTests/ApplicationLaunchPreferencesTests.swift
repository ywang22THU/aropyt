import Foundation
import Testing
@testable import AropytEditor

@Suite("Application launch preferences")
struct ApplicationLaunchPreferencesTests {
    @Test func defaultsToCreatingANewDocumentAndPersistsSelections() {
        withPreferences { preferences, defaults in
            #expect(preferences.behavior == .createNewDocument)
            #expect(preferences.lastClosedFileURL == nil)
            #expect(preferences.specificFileURL == nil)

            let lastURL = URL(fileURLWithPath: "/tmp/last.md")
            let specificURL = URL(fileURLWithPath: "/tmp/specific.md")
            preferences.lastClosedFileURL = lastURL
            preferences.specificFileURL = specificURL
            preferences.behavior = .openSpecificDocument

            let reloaded = ApplicationLaunchPreferences(defaults: defaults)
            #expect(reloaded.behavior == .openSpecificDocument)
            #expect(reloaded.lastClosedFileURL == lastURL)
            #expect(reloaded.specificFileURL == specificURL)
        }
    }

    @Test func invalidStoredBehaviorFallsBackToCreatingANewDocument() {
        withPreferences { preferences, defaults in
            defaults.set("invalid", forKey: "AropytEditor.applicationLaunch.behavior")
            #expect(preferences.behavior == .createNewDocument)
        }
    }

    @Test func startupFileMustExistAndBeReadable() throws {
        try withPreferences { preferences, _ in
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            defer { try? FileManager.default.removeItem(at: directory) }
            let file = directory.appendingPathComponent("document.md")
            try Data("# Test".utf8).write(to: file)

            preferences.behavior = .reopenLastClosedDocument
            preferences.lastClosedFileURL = file
            #expect(preferences.startupFileURL() == file.standardizedFileURL)

            try FileManager.default.removeItem(at: file)
            #expect(preferences.startupFileURL() == nil)

            preferences.behavior = .openSpecificDocument
            preferences.specificFileURL = directory
            #expect(preferences.startupFileURL() == nil)
        }
    }

    private func withPreferences(
        _ body: (ApplicationLaunchPreferences, UserDefaults) throws -> Void
    ) rethrows {
        let suiteName = "ApplicationLaunchPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(ApplicationLaunchPreferences(defaults: defaults), defaults)
    }
}
