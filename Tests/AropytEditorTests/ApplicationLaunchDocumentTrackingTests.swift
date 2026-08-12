import AppKit
import Foundation
import Testing
@testable import AropytEditor

@Suite("Application launch document tracking")
@MainActor
struct ApplicationLaunchDocumentTrackingTests {
    @Test func closingSavedDocumentRecordsItsURL() {
        _ = NSApplication.shared
        withPreferences { preferences in
            let fileURL = URL(fileURLWithPath: "/tmp/last-closed.md")
            let document = MarkdownDocument()
            document.applicationLaunchPreferences = preferences
            document.fileURL = fileURL

            document.close()

            #expect(preferences.lastClosedFileURL == fileURL)
        }
    }

    @Test func closingUntitledDocumentClearsThePreviousURL() {
        _ = NSApplication.shared
        withPreferences { preferences in
            preferences.lastClosedFileURL = URL(fileURLWithPath: "/tmp/older.md")
            let document = MarkdownDocument()
            document.applicationLaunchPreferences = preferences

            document.close()

            #expect(preferences.lastClosedFileURL == nil)
        }
    }

    private func withPreferences(_ body: (ApplicationLaunchPreferences) -> Void) {
        let suiteName = "ApplicationLaunchDocumentTrackingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(ApplicationLaunchPreferences(defaults: defaults))
    }
}
