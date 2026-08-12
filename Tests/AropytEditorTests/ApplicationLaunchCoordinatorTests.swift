import Foundation
import Testing
@testable import AropytEditor

@Suite("Application launch coordinator")
@MainActor
struct ApplicationLaunchCoordinatorTests {
    @Test func defaultBehaviorLetsAppKitCreateUntitledDocument() {
        withPreferences { preferences in
            var openedURL: URL?
            var newDocumentCount = 0
            let coordinator = makeCoordinator(
                preferences: preferences,
                openedURL: { openedURL = $0 },
                openSucceeded: true,
                createNewDocument: { newDocumentCount += 1 }
            )

            #expect(coordinator.shouldOpenUntitledFile())
            #expect(openedURL == nil)
            #expect(newDocumentCount == 0)
        }
    }

    @Test func configuredExistingFileIsOpenedInsteadOfUntitledDocument() throws {
        try withPreferences { preferences in
            let fileURL = try makeTemporaryMarkdownFile()
            defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
            preferences.behavior = .openSpecificDocument
            preferences.specificFileURL = fileURL
            var openedURL: URL?
            var newDocumentCount = 0
            let coordinator = makeCoordinator(
                preferences: preferences,
                openedURL: { openedURL = $0 },
                openSucceeded: true,
                createNewDocument: { newDocumentCount += 1 }
            )

            #expect(!coordinator.shouldOpenUntitledFile())
            #expect(openedURL == fileURL.standardizedFileURL)
            #expect(newDocumentCount == 0)
        }
    }

    @Test func failedOpenFallsBackToCreatingUntitledDocument() throws {
        try withPreferences { preferences in
            let fileURL = try makeTemporaryMarkdownFile()
            defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
            preferences.behavior = .reopenLastClosedDocument
            preferences.lastClosedFileURL = fileURL
            var newDocumentCount = 0
            let coordinator = makeCoordinator(
                preferences: preferences,
                openedURL: { _ in },
                openSucceeded: false,
                createNewDocument: { newDocumentCount += 1 }
            )

            #expect(!coordinator.shouldOpenUntitledFile())
            #expect(newDocumentCount == 1)
        }
    }

    @Test func missingConfiguredFileFallsBackToAppKitUntitledFlow() {
        withPreferences { preferences in
            preferences.behavior = .reopenLastClosedDocument
            preferences.lastClosedFileURL = URL(
                fileURLWithPath: "/tmp/\(UUID().uuidString)/missing.md"
            )
            var openedURL: URL?
            let coordinator = makeCoordinator(
                preferences: preferences,
                openedURL: { openedURL = $0 },
                openSucceeded: true,
                createNewDocument: {}
            )

            #expect(coordinator.shouldOpenUntitledFile())
            #expect(openedURL == nil)
        }
    }

    private func makeCoordinator(
        preferences: ApplicationLaunchPreferences,
        openedURL: @escaping (URL) -> Void,
        openSucceeded: Bool,
        createNewDocument: @escaping () -> Void
    ) -> ApplicationLaunchCoordinator {
        ApplicationLaunchCoordinator(
            preferences: preferences,
            openDocument: { url, completion in
                openedURL(url)
                completion(openSucceeded)
            },
            createNewDocument: createNewDocument,
            schedule: { work in work() }
        )
    }

    private func makeTemporaryMarkdownFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("document.md")
        try Data("# Test".utf8).write(to: fileURL)
        return fileURL
    }

    private func withPreferences(
        _ body: (ApplicationLaunchPreferences) throws -> Void
    ) rethrows {
        let suiteName = "ApplicationLaunchCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(ApplicationLaunchPreferences(defaults: defaults))
    }
}
