import AppKit
import Foundation
import Testing
@testable import AropytEditor

@Suite("Workspace document")
@MainActor
struct WorkspaceDocumentTests {
    @Test func loadsSelectedFileAndResetsEditingState() throws {
        _ = NSApplication.shared
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("README.md")
        try "# Workspace".write(to: fileURL, atomically: true, encoding: .utf8)
        let document = MarkdownDocument()
        document.updateText("unsaved", actionName: "Edit")

        try document.loadWorkspaceFile(at: fileURL)

        #expect(document.text == "# Workspace")
        #expect(document.fileURL == fileURL.standardizedFileURL)
        #expect(!document.isDocumentEdited)
        #expect(document.undoManager?.canUndo != true)
    }

    @Test func tracksActiveFileWhenParentMovesOrIsDeleted() throws {
        _ = NSApplication.shared
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let oldFolder = root.appendingPathComponent("Old", isDirectory: true)
        let newFolder = root.appendingPathComponent("New", isDirectory: true)
        try FileManager.default.createDirectory(at: oldFolder, withIntermediateDirectories: false)
        let fileURL = oldFolder.appendingPathComponent("note.md")
        try "note".write(to: fileURL, atomically: true, encoding: .utf8)
        let document = MarkdownDocument()
        try document.loadWorkspaceFile(at: fileURL)

        document.updateWorkspaceFileURL(afterMoving: oldFolder, to: newFolder)
        #expect(document.fileURL == newFolder.appendingPathComponent("note.md"))

        document.clearWorkspaceFileIfDeleted(at: newFolder)
        #expect(document.fileURL == nil)
        #expect(document.text.isEmpty)
        #expect(!document.isDocumentEdited)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AropytEditor-document-workspace-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
}
