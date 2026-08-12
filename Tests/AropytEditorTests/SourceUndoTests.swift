import AppKit
import Testing
@testable import AropytEditor

@Suite("Source undo", .serialized)
@MainActor
struct SourceUndoTests {
    @Test func undoRestoresInsertionPoint() async throws {
        _ = NSApplication.shared
        let document = MarkdownDocument()
        document.text = "alpha omega"
        let windowController = EditorWindowController()
        document.addWindowController(windowController)
        windowController.setup(document: document)
        defer {
            document.removeWindowController(windowController)
            windowController.close()
        }

        let main = try #require(windowController.contentViewController as? MainViewController)
        main.toggleMode(nil)
        try await waitForSourceMode(main)

        let source = try #require(
            main.children.compactMap { $0 as? SourceViewController }.first
        )
        source.setEditorSelectedRange(NSRange(location: 6, length: 0))
        source.insertEditorText("brave ")
        #expect(document.text == "alpha brave omega")
        #expect(source.editorSelectedRange == NSRange(location: 12, length: 0))

        let undoManager = try #require(source.editorUndoManager)
        undoManager.undo()

        #expect(document.text == "alpha omega")
        #expect(source.currentText == "alpha omega")
        #expect(source.editorSelectedRange == NSRange(location: 6, length: 0))
    }

    private func waitForSourceMode(_ main: MainViewController) async throws {
        let clock = ContinuousClock()
        let started = clock.now
        while started.duration(to: clock.now) < .seconds(5) {
            if main.mode == .source { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw SourceUndoTestError.timeout
    }

    private enum SourceUndoTestError: Error {
        case timeout
    }
}
