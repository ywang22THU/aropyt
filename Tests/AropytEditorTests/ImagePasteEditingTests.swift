import AppKit
import Testing
import WebKit
@testable import AropytEditor

@Suite("Image paste editing", .serialized)
@MainActor
struct ImagePasteEditingTests {
    @Test func sourcePasteWritesRawImageBesideDocumentAndInsertsMarkdown() async throws {
        _ = NSApplication.shared
        try await withFixture(destination: .currentDirectory) { fixture in
            fixture.document.text = "before "
            _ = fixture.main.view
            fixture.main.reloadFromDocument()
            fixture.main.toggleMode(nil)
            try await waitForSourceMode(fixture.main)
            let source = try #require(
                fixture.main.children.compactMap { $0 as? SourceViewController }.first
            )
            source.setEditorSelectedRange(NSRange(location: 7, length: 0))
            let pasteboard = imageDataPasteboard()

            #expect(fixture.main.pasteImage(from: pasteboard))
            #expect(fixture.document.text == "before ![](./image.png)")
            #expect(FileManager.default.fileExists(
                atPath: fixture.documentURL.deletingLastPathComponent()
                    .appendingPathComponent("image.png").path
            ))
        }
    }

    @Test func previewPasteUsesOriginalExternalPathWithoutCopying() async throws {
        _ = NSApplication.shared
        try await withFixture(destination: .originalPath) { fixture in
            fixture.document.text = "before"
            let outsideDirectory = fixture.root.appendingPathComponent("outside", isDirectory: true)
            try FileManager.default.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)
            let imageURL = outsideDirectory.appendingPathComponent("外部 图片.png")
            try Self.pixelPNG.write(to: imageURL)
            let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
            pasteboard.clearContents()
            #expect(pasteboard.writeObjects([imageURL as NSURL]))

            _ = fixture.main.view
            fixture.main.reloadFromDocument()
            let preview = try #require(
                fixture.main.children.compactMap { $0 as? PreviewViewController }.first
            )
            try await waitUntilReady(preview)
            let webView = try #require(preview.view as? WKWebView)
            _ = try await webView.evaluateJavaScript("""
                (function() {
                    var content = document.getElementById('content');
                    var range = document.createRange();
                    range.selectNodeContents(content);
                    range.collapse(false);
                    var selection = window.getSelection();
                    selection.removeAllRanges();
                    selection.addRange(range);
                })();
                """)

            #expect(fixture.main.pasteImage(from: pasteboard))
            try await waitForCondition {
                fixture.document.text.contains("%E5%A4%96%E9%83%A8%20%E5%9B%BE%E7%89%87.png")
            }
            let imageState = try await webView.evaluateJavaScript("""
                (function() {
                    var image = document.querySelector('img');
                    return image ? [image.complete, image.naturalWidth,
                        image.getAttribute('data-aropyt-image-source') || '', image.src] : [];
                })();
                """) as? [Any]
            let state = try #require(imageState)
            #expect(state.count == 4)
            #expect(state[0] as? Bool == true)
            #expect((state[1] as? NSNumber)?.intValue == 1)
            #expect((state[2] as? String)?.contains("%E5%A4%96%E9%83%A8") == true)
            #expect((state[3] as? String)?.hasPrefix("aropyt-document://local/") == true)
            let outsideContents = try FileManager.default.contentsOfDirectory(
                atPath: outsideDirectory.path
            )
            #expect(outsideContents == ["外部 图片.png"])
        }
    }

    private func withFixture(
        destination: ImagePasteDestination,
        _ body: (Fixture) async throws -> Void
    ) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let documentDirectory = root.appendingPathComponent("document", isDirectory: true)
        try FileManager.default.createDirectory(at: documentDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let documentURL = documentDirectory.appendingPathComponent("note.md")

        let suiteName = "ImagePasteEditingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = ImagePastePreferences(defaults: defaults)
        preferences.destination = destination
        let document = MarkdownDocument()
        document.fileURL = documentURL
        let main = MainViewController(
            imagePasteService: ImagePasteService(preferences: preferences)
        )
        main.document = document
        try await body(Fixture(
            root: root,
            documentURL: documentURL,
            document: document,
            main: main
        ))
    }

    private func imageDataPasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        pasteboard.setData(Self.pixelPNG, forType: .png)
        return pasteboard
    }

    private func waitForSourceMode(_ main: MainViewController) async throws {
        try await waitForCondition { main.mode == .source }
    }

    private func waitUntilReady(_ preview: PreviewViewController) async throws {
        try await waitForCondition(timeout: .seconds(10)) { preview.renderState == .ready }
    }

    private func waitForCondition(
        timeout: Duration = .seconds(5),
        _ condition: @escaping () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let started = clock.now
        while started.duration(to: clock.now) < timeout {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw TestError.timeout
    }

    private struct Fixture {
        let root: URL
        let documentURL: URL
        let document: MarkdownDocument
        let main: MainViewController
    }

    private enum TestError: Error { case timeout }

    private static let pixelPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!
}
