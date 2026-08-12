import AppKit
import Foundation
import Testing
@testable import AropytEditor

@Suite("Workspace window")
@MainActor
struct WorkspaceWindowTests {
    @Test func openingDirectoryInstallsLeftTitlebarAccessoryAndLoadsSelectionInPlace() throws {
        _ = NSApplication.shared
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("README.md")
        try "# Selected".write(to: fileURL, atomically: true, encoding: .utf8)
        let document = MarkdownDocument()
        let windowController = EditorWindowController()
        document.addWindowController(windowController)
        windowController.setup(document: document)
        defer { document.close() }

        try windowController.openDirectory(at: root)

        let container = try #require(windowController.workspaceContainer)
        let accessory = try #require(windowController.sidebarTitlebarAccessory)
        #expect(document.workspaceRootURL == root.standardizedFileURL)
        #expect(container.isSidebarVisible)
        #expect(container.splitView.dividerStyle == .thin)
        #expect(container.sidebarViewController.outlineView.style == .plain)
        #expect(accessory.layoutAttribute == .left)
        #expect(windowController.window?.titlebarAccessoryViewControllers.first === accessory)
        let sidebarButton = try #require(
            view(identifiedBy: "workspace.sidebar.toggle", in: accessory.view) as? NSButton
        )
        let window = try #require(windowController.window)
        let chromeHeight = max(
            28,
            window.frame.height - window.contentLayoutRect.height
        )
        #expect(abs(accessory.view.bounds.height - chromeHeight) < 0.5)
        #expect(abs(sidebarButton.frame.midY - accessory.view.bounds.midY) < 0.5)
        #expect(container.sidebarViewController.sidebarContentInsets.left
            == WorkspaceSidebarViewController.leadingContentInset)

        windowController.openWorkspaceFile(at: fileURL)
        #expect(document.fileURL == fileURL.standardizedFileURL)
        #expect(document.text == "# Selected")
    }

    @Test func toggleChangesIconStateAndAnimatesWithoutToast() async throws {
        _ = NSApplication.shared
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let document = MarkdownDocument()
        let windowController = EditorWindowController()
        document.addWindowController(windowController)
        windowController.setup(document: document)
        defer { document.close() }
        try windowController.openDirectory(at: root)
        let container = try #require(windowController.workspaceContainer)
        let visibleSymbol = EditorWindowController.sidebarSymbolName(isVisible: true)
        let hiddenSymbol = EditorWindowController.sidebarSymbolName(isVisible: false)

        windowController.toggleWorkspaceSidebar()

        #expect(!container.isSidebarVisible)
        #expect(visibleSymbol != hiddenSymbol)
        #expect(view(identifiedBy: "workspace.sidebar.toast", in: container.view) == nil)
        try await Task.sleep(for: .milliseconds(300))
        #expect(container.splitViewItems.first?.isCollapsed == true)
        windowController.toggleWorkspaceSidebar()
        #expect(container.isSidebarVisible)
        try await Task.sleep(for: .milliseconds(300))
        #expect(container.splitViewItems.first?.isCollapsed == false)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AropytEditor-window-workspace-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func view(identifiedBy identifier: String, in root: NSView) -> NSView? {
        if root.identifier?.rawValue == identifier { return root }
        for subview in root.subviews {
            if let match = view(identifiedBy: identifier, in: subview) {
                return match
            }
        }
        return nil
    }
}
