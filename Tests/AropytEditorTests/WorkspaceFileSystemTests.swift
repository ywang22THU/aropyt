import Foundation
import Testing
@testable import AropytEditor

@Suite("Workspace file system")
struct WorkspaceFileSystemTests {
    @Test func listsDirectoriesAndMarkdownFilesOnly() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Zoo"),
                                                withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("alpha"),
                                                withIntermediateDirectories: false)
        try Data().write(to: root.appendingPathComponent("README.md"))
        try Data().write(to: root.appendingPathComponent("guide.MD"))
        try Data().write(to: root.appendingPathComponent("notes.markdown"))
        try Data().write(to: root.appendingPathComponent("image.png"))
        try Data().write(to: root.appendingPathComponent(".hidden.md"))

        let entries = try WorkspaceFileSystem(rootURL: root).contents(of: root)

        #expect(entries.map(\.name) == ["alpha", "Zoo", "guide.MD", "README.md"])
        #expect(entries.prefix(2).allSatisfy { $0.isDirectory })
        #expect(entries.dropFirst(2).allSatisfy { !$0.isDirectory })
    }

    @Test func createsRenamesAndDeletesItemsOnDisk() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileSystem = try WorkspaceFileSystem(rootURL: root)

        let folder = try fileSystem.createDirectory(in: root, named: "Notes")
        let file = try fileSystem.createMarkdownFile(in: folder, named: "Today")
        #expect(FileManager.default.fileExists(atPath: folder.path))
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(file.lastPathComponent == "Today.md")

        let renamedFile = try fileSystem.renameItem(at: file, to: "Tomorrow")
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(FileManager.default.fileExists(atPath: renamedFile.path))
        #expect(renamedFile.lastPathComponent == "Tomorrow.md")

        try fileSystem.deleteItem(at: renamedFile)
        #expect(!FileManager.default.fileExists(atPath: renamedFile.path))
    }

    @Test func refreshDiscardsCachedDirectoryState() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try WorkspaceTreeModel(rootURL: root)

        #expect(try model.children(of: model.root).isEmpty)
        try Data().write(to: root.appendingPathComponent("added.md"))
        #expect(try model.children(of: model.root).isEmpty)

        model.refresh()
        #expect(try model.children(of: model.root).map(\.name) == ["added.md"])
    }

    @Test func rejectsEscapesCollisionsAndNonMarkdownNames() throws {
        let root = try makeTemporaryDirectory()
        let outside = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        let fileSystem = try WorkspaceFileSystem(rootURL: root)
        try Data().write(to: root.appendingPathComponent("existing.md"))

        #expect(throws: WorkspaceFileSystemError.itemIsOutsideWorkspace) {
            try fileSystem.createDirectory(in: outside, named: "Nope")
        }
        #expect(throws: WorkspaceFileSystemError.invalidName) {
            try fileSystem.createDirectory(in: root, named: "../Nope")
        }
        #expect(throws: WorkspaceFileSystemError.itemAlreadyExists) {
            try fileSystem.createMarkdownFile(in: root, named: "existing.md")
        }
        #expect(throws: WorkspaceFileSystemError.unsupportedFileType) {
            try fileSystem.createMarkdownFile(in: root, named: "plain.txt")
        }
        #expect(throws: WorkspaceFileSystemError.itemIsOutsideWorkspace) {
            try fileSystem.deleteItem(at: root)
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AropytEditor-workspace-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
}
