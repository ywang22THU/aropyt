import Foundation
import Testing
@testable import AropytEditor

@Suite("Image paste service")
struct ImagePasteServiceTests {
    @Test func originalPathDoesNotCopyAndEscapesLikeAURL() throws {
        try withFixture { fixture in
            let source = fixture.root.appendingPathComponent("原始 图片.png")
            try fixture.png.write(to: source)

            let insertion = try fixture.service.makeInsertion(
                for: .file(source),
                documentURL: fixture.document
            )

            #expect(insertion.copiedFileURL == nil)
            #expect(insertion.imageURL == source)
            #expect(insertion.markdown.contains("%E5%8E%9F%E5%A7%8B%20%E5%9B%BE%E7%89%87.png"))
            #expect(try Data(contentsOf: source) == fixture.png)
        }
    }

    @Test func currentDirectoryCopiesFileAndAvoidsOverwriting() throws {
        try withFixture(destination: .currentDirectory) { fixture in
            let sourceDirectory = fixture.root.appendingPathComponent("source", isDirectory: true)
            try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
            let source = sourceDirectory.appendingPathComponent("photo.png")
            try fixture.png.write(to: source)
            try Data("existing".utf8).write(
                to: fixture.document.deletingLastPathComponent().appendingPathComponent("photo.png")
            )

            let insertion = try fixture.service.makeInsertion(
                for: .file(source),
                documentURL: fixture.document
            )

            let copied = try #require(insertion.copiedFileURL)
            #expect(copied.lastPathComponent == "photo-2.png")
            #expect(insertion.markdown == "![](./photo-2.png)")
            #expect(try Data(contentsOf: copied) == fixture.png)
        }
    }

    @Test func configuredResourceDirectoryControlsCreatedPath() throws {
        try withFixture(destination: .resourceDirectory) { fixture in
            fixture.preferences.resourceDirectoryName = "资源/插图"
            let insertion = try fixture.service.makeInsertion(
                for: .data(fixture.png, suggestedFilename: "屏幕 截图.png"),
                documentURL: fixture.document
            )

            let copied = try #require(insertion.copiedFileURL)
            #expect(copied.path.hasSuffix("/资源/插图/屏幕 截图.png"))
            #expect(FileManager.default.fileExists(atPath: copied.path))
            #expect(insertion.markdown == "![](./%E8%B5%84%E6%BA%90/%E6%8F%92%E5%9B%BE/%E5%B1%8F%E5%B9%95%20%E6%88%AA%E5%9B%BE.png)")
        }
    }

    @Test func escapingCanBeDisabled() throws {
        try withFixture(destination: .currentDirectory) { fixture in
            fixture.preferences.escapesImageURLs = false
            let source = fixture.root.appendingPathComponent("中文 图片.png")
            try fixture.png.write(to: source)
            let insertion = try fixture.service.makeInsertion(
                for: .file(source),
                documentURL: fixture.document
            )
            #expect(insertion.markdown == "![](./中文 图片.png)")
        }
    }

    @Test func currentDirectoryReusesImageAlreadyBesideDocument() throws {
        try withFixture(destination: .currentDirectory) { fixture in
            let source = fixture.document.deletingLastPathComponent()
                .appendingPathComponent("photo.png")
            try fixture.png.write(to: source)
            let insertion = try fixture.service.makeInsertion(
                for: .file(source),
                documentURL: fixture.document
            )
            #expect(insertion.copiedFileURL == nil)
            #expect(insertion.imageURL == source)
            #expect(insertion.markdown == "![](./photo.png)")
        }
    }

    @Test func copyingRequiresSavedDocumentAndOriginalPathRequiresFile() throws {
        try withFixture(destination: .currentDirectory) { fixture in
            #expect(throws: ImagePasteService.PasteError.documentMustBeSaved) {
                try fixture.service.makeInsertion(
                    for: .data(fixture.png, suggestedFilename: "image.png"),
                    documentURL: nil
                )
            }
            fixture.preferences.destination = .originalPath
            #expect(throws: ImagePasteService.PasteError.originalPathUnavailable) {
                try fixture.service.makeInsertion(
                    for: .data(fixture.png, suggestedFilename: "image.png"),
                    documentURL: fixture.document
                )
            }
        }
    }

    private func withFixture(
        destination: ImagePasteDestination = .originalPath,
        _ body: (Fixture) throws -> Void
    ) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let documentDirectory = root.appendingPathComponent("document", isDirectory: true)
        try FileManager.default.createDirectory(at: documentDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let suiteName = "ImagePasteServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = ImagePastePreferences(defaults: defaults)
        preferences.destination = destination
        let fixture = Fixture(
            root: root,
            document: documentDirectory.appendingPathComponent("note.md"),
            png: Data(Self.pixelPNG),
            preferences: preferences,
            service: ImagePasteService(preferences: preferences)
        )
        try body(fixture)
    }

    private struct Fixture {
        let root: URL
        let document: URL
        let png: Data
        let preferences: ImagePastePreferences
        let service: ImagePasteService
    }

    private static let pixelPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!
}
