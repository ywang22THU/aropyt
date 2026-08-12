import Foundation
import Testing
@testable import AropytEditor

@Suite("Image paste preferences")
struct ImagePastePreferencesTests {
    @Test func defaultsAndPersistence() {
        let suiteName = "ImagePastePreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = ImagePastePreferences(defaults: defaults)
        #expect(preferences.destination == .originalPath)
        #expect(preferences.resourceDirectoryName == "assets")
        #expect(preferences.escapesImageURLs)

        preferences.destination = .resourceDirectory
        preferences.resourceDirectoryName = "图片/assets_2026"
        preferences.escapesImageURLs = false

        let reloaded = ImagePastePreferences(defaults: defaults)
        #expect(reloaded.destination == .resourceDirectory)
        #expect(reloaded.resourceDirectoryName == "图片/assets_2026")
        #expect(!reloaded.escapesImageURLs)
    }

    @Test func resourceDirectoryNameAcceptsSafeRelativePathsOnly() {
        #expect(ImagePastePreferences.normalizedResourceDirectoryName(" images ") == "images")
        #expect(ImagePastePreferences.normalizedResourceDirectoryName("图片/插图 2") == "图片/插图 2")
        #expect(ImagePastePreferences.normalizedResourceDirectoryName("") == nil)
        #expect(ImagePastePreferences.normalizedResourceDirectoryName("/assets") == nil)
        #expect(ImagePastePreferences.normalizedResourceDirectoryName("../assets") == nil)
        #expect(ImagePastePreferences.normalizedResourceDirectoryName("assets//images") == nil)
        #expect(ImagePastePreferences.normalizedResourceDirectoryName("assets:images") == nil)
        #expect(ImagePastePreferences.normalizedResourceDirectoryName("assets?query") == nil)
    }

    @Test func invalidResourceDirectoryNameDoesNotReplaceSavedValue() {
        let suiteName = "ImagePastePreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = ImagePastePreferences(defaults: defaults)
        preferences.resourceDirectoryName = "images"
        preferences.resourceDirectoryName = "../outside"
        #expect(preferences.resourceDirectoryName == "images")
    }
}
