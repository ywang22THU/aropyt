import AppKit
import Foundation
import Testing
@testable import AropytEditor

@Suite("Workspace sidebar")
@MainActor
struct WorkspaceSidebarTests {
    @Test func rootItemIsActuallyRenderedAwayFromLeftBorder() throws {
        _ = NSApplication.shared
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = try WorkspaceSidebarViewController(rootURL: root)
        controller.view.frame = NSRect(x: 0, y: 0, width: 250, height: 500)
        controller.view.layoutSubtreeIfNeeded()
        controller.outlineView.reloadData()

        let rootRow = controller.outlineView.row(forItem: controller.model.root)
        #expect(rootRow == 0)
        guard rootRow >= 0 else { return }
        let disclosureFrame = controller.outlineView.frameOfOutlineCell(atRow: rootRow)
        let disclosureOrigin = controller.outlineView.convert(
            disclosureFrame.origin,
            to: controller.view
        )

        #expect(disclosureOrigin.x >= WorkspaceSidebarViewController.horizontalContentInset)
    }

    @Test func treeUsesEqualHorizontalMargins() throws {
        _ = NSApplication.shared
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = try WorkspaceSidebarViewController(rootURL: root)
        controller.view.frame = NSRect(x: 0, y: 0, width: 250, height: 500)
        controller.view.layoutSubtreeIfNeeded()
        let scrollView = try #require(controller.outlineView.enclosingScrollView)

        let leftMargin = scrollView.frame.minX - controller.view.bounds.minX
        let rightMargin = controller.view.bounds.maxX - scrollView.frame.maxX

        #expect(abs(leftMargin - WorkspaceSidebarViewController.horizontalContentInset) < 0.5)
        #expect(abs(rightMargin - WorkspaceSidebarViewController.horizontalContentInset) < 0.5)
        #expect(abs(leftMargin - rightMargin) < 0.5)
    }

    @Test func directoryMenuUsesRequestedGroups() throws {
        _ = NSApplication.shared
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = try WorkspaceSidebarViewController(rootURL: root)

        let menu = controller.contextMenu(for: controller.model.root)

        #expect(menu.items.map(\.isSeparatorItem) == [
            false, true, false, false, true, false, false, true, false, true, false, false,
        ])
        #expect(menu.items[2].title == L10n.tr("workspace.menu.new_markdown_file", "New Markdown File"))
        #expect(menu.items[3].title == L10n.tr("workspace.menu.new_folder", "New Folder"))
        #expect(menu.items[8].title == L10n.tr("workspace.menu.refresh", "Refresh"))
    }

    @Test func fileMenuOmitsDirectoryOnlyActions() throws {
        _ = NSApplication.shared
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("README.md")
        try Data().write(to: fileURL)
        let controller = try WorkspaceSidebarViewController(rootURL: root)
        let node = try #require(try controller.model.children(of: controller.model.root).first)

        let menu = controller.contextMenu(for: node)

        #expect(menu.items.map(\.isSeparatorItem) == [false, true, false, false, true, false, false])
        let titles = Set(menu.items.filter { !$0.isSeparatorItem }.map(\.title))
        #expect(!titles.contains(L10n.tr("workspace.menu.new_markdown_file", "New Markdown File")))
        #expect(!titles.contains(L10n.tr("workspace.menu.new_folder", "New Folder")))
        #expect(!titles.contains(L10n.tr("workspace.menu.refresh", "Refresh")))
    }

    @Test func selectingMarkdownFileRequestsOpeningInEditor() throws {
        _ = NSApplication.shared
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("README.md")
        try Data().write(to: fileURL)
        let controller = try WorkspaceSidebarViewController(rootURL: root)
        _ = controller.view
        controller.outlineView.reloadData()
        controller.outlineView.expandItem(controller.model.root)
        var openedURL: URL?
        controller.onOpenFile = { openedURL = $0 }
        let node = try #require(try controller.model.children(of: controller.model.root).first)
        let row = controller.outlineView.row(forItem: node)

        controller.outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)

        #expect(openedURL == fileURL.standardizedFileURL)
    }

    @Test func selectingDirectoryExpandsItsNextLevel() throws {
        _ = NSApplication.shared
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Guides", isDirectory: true),
            withIntermediateDirectories: false
        )
        let controller = try WorkspaceSidebarViewController(rootURL: root)
        _ = controller.view
        controller.outlineView.reloadData()
        controller.outlineView.expandItem(controller.model.root)
        let directory = try #require(try controller.model.children(of: controller.model.root).first)

        controller.outlineView.selectRowIndexes(
            IndexSet(integer: controller.outlineView.row(forItem: directory)),
            byExtendingSelection: false
        )

        #expect(controller.outlineView.isItemExpanded(directory))
    }

    @Test func contextActionsDispatchNewWindowAndCopyPath() throws {
        _ = NSApplication.shared
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("README.md")
        try Data().write(to: fileURL)
        var copiedPath: String?
        let controller = try WorkspaceSidebarViewController(
            rootURL: root,
            copyPathHandler: { copiedPath = $0 }
        )
        let node = try #require(try controller.model.children(of: controller.model.root).first)
        let menu = controller.contextMenu(for: node)
        let openItem = try #require(menu.items.first)
        let copyItem = try #require(menu.items.first {
            $0.title == L10n.tr("workspace.menu.copy_path", "Copy File Path")
        })
        var openedNode: WorkspaceTreeNode?
        controller.onOpenInNewWindow = { openedNode = $0 }

        NSApp.sendAction(try #require(openItem.action), to: openItem.target, from: openItem)
        NSApp.sendAction(try #require(copyItem.action), to: copyItem.target, from: copyItem)

        #expect(openedNode === node)
        #expect(copiedPath == fileURL.path)
    }

    @Test func deleteRequiresConfirmationBeforeChangingDisk() throws {
        _ = NSApplication.shared
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("README.md")
        try Data().write(to: fileURL)
        let controller = try WorkspaceSidebarViewController(rootURL: root)
        let node = try #require(try controller.model.children(of: controller.model.root).first)
        let deleteItem = try #require(controller.contextMenu(for: node).items.first {
            $0.title == L10n.tr("workspace.menu.delete", "Delete")
        })

        controller.confirmDelete = { _, completion in completion(false) }
        NSApp.sendAction(try #require(deleteItem.action), to: deleteItem.target, from: deleteItem)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        controller.confirmDelete = { _, completion in completion(true) }
        NSApp.sendAction(try #require(deleteItem.action), to: deleteItem.target, from: deleteItem)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test func refreshReadsLatestDirectoryStateFromDisk() throws {
        _ = NSApplication.shared
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = try WorkspaceSidebarViewController(rootURL: root)
        #expect(try controller.model.children(of: controller.model.root).isEmpty)
        try Data().write(to: root.appendingPathComponent("external.md"))

        controller.refresh(controller.model.root)

        #expect(try controller.model.children(of: controller.model.root).map(\.name) == ["external.md"])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AropytEditor-sidebar-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
}
