import AppKit
import Testing
@testable import AropytEditor

@Suite("Document reload")
@MainActor
struct DocumentReloadTests {
    @Test func reloadsCleanDocumentFromDisk() throws {
        _ = NSApplication.shared
        let fileURL = temporaryMarkdownURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try "updated on disk".write(to: fileURL, atomically: true, encoding: .utf8)

        let document = MarkdownDocument()
        document.fileURL = fileURL
        document.fileType = "net.daringfireball.markdown"
        document.text = "original contents"

        try document.reloadFromDisk()

        #expect(document.text == "updated on disk")
        #expect(!document.isDocumentEdited)
        #expect(document.undoManager?.canUndo != true)
    }

    @Test func refusesToOverwriteUnsavedChanges() throws {
        _ = NSApplication.shared
        let fileURL = temporaryMarkdownURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try "updated on disk".write(to: fileURL, atomically: true, encoding: .utf8)

        let document = MarkdownDocument()
        document.fileURL = fileURL
        document.fileType = "net.daringfireball.markdown"
        document.text = "original contents"
        document.updateText("unsaved local edit", actionName: "Edit")

        #expect(throws: MarkdownDocument.ReloadFromDiskError.unsavedChanges) {
            try document.reloadFromDisk()
        }
        #expect(document.text == "unsaved local edit")
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "updated on disk")
    }

    @Test func refusesUntitledDocument() {
        _ = NSApplication.shared
        let document = MarkdownDocument()

        #expect(throws: MarkdownDocument.ReloadFromDiskError.noFileURL) {
            try document.reloadFromDisk()
        }
    }

    private func temporaryMarkdownURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AropytEditor-reload-\(UUID().uuidString).md")
    }
}
