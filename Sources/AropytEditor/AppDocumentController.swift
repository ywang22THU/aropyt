import AppKit
import UniformTypeIdentifiers

/// 自定义 NSDocumentController 以解决脱 .app bundle 跑时无法读取 Info.plist 文档类型的问题。
/// 必须在 main.swift 第一行 `_ = AppDocumentController()` 实例化，
/// 这样 NSDocumentController.shared 才会返回这个子类。
final class AppDocumentController: NSDocumentController {

    @objc func openDirectory(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = L10n.tr("workspace.open_panel.action", "Open")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openDirectory(at: url)
    }

    func openDirectory(at rootURL: URL) {
        let rootURL = rootURL.standardizedFileURL
        if let existing = documents.first(where: {
            ($0 as? MarkdownDocument)?.workspaceRootURL == rootURL
        }) {
            existing.showWindows()
            existing.windowControllers.first?.window?.makeKeyAndOrderFront(nil)
            return
        }

        var createdDocument: MarkdownDocument?
        do {
            guard let type = defaultType,
                  let document = try makeUntitledDocument(ofType: type) as? MarkdownDocument else {
                throw CocoaError(.fileReadUnknown)
            }
            createdDocument = document
            addDocument(document)
            document.makeWindowControllers()
            guard let windowController = document.windowControllers.first as? EditorWindowController else {
                document.close()
                throw CocoaError(.fileReadUnknown)
            }
            try windowController.openDirectory(at: rootURL)
            document.showWindows()
            closeEmptyUntitled(except: document)
        } catch {
            createdDocument?.close()
            presentDirectoryOpenError(error)
        }
    }

    override var documentClassNames: [String] {
        return ["AropytEditor.MarkdownDocument"]
    }

    override var defaultType: String? {
        return "net.daringfireball.markdown"
    }

    override func documentClass(forType typeName: String) -> AnyClass? {
        return MarkdownDocument.self
    }

    override func typeForContents(of url: URL) throws -> String {
        // 不管扩展名，统统当 markdown 处理（用户也可能编辑 .markdown / .mdown / 无扩展名）
        return "net.daringfireball.markdown"
    }

    override func runModalOpenPanel(_ openPanel: NSOpenPanel,
                                    forTypes types: [String]?) -> Int {
        openPanel.allowedContentTypes = [
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "markdown") ?? .plainText,
            .plainText
        ]
        openPanel.allowsOtherFileTypes = true
        openPanel.canChooseDirectories = false
        return openPanel.runModal().rawValue
    }

    /// 打开文件时关闭尚未编辑的空 untitled 窗口（避免出现两个窗口的尴尬）。
    /// 走 Open 面板、Recent、双击文件、`open` 命令行都会经过这个入口。
    override func openDocument(withContentsOf url: URL,
                               display displayDocument: Bool,
                               completionHandler: @escaping (NSDocument?, Bool, Error?) -> Void) {
        super.openDocument(withContentsOf: url, display: displayDocument) { [weak self] doc, alreadyOpen, error in
            if let doc = doc, error == nil {
                self?.closeEmptyUntitled(except: doc)
            }
            completionHandler(doc, alreadyOpen, error)
        }
    }

    /// 关闭所有未保存、未编辑、内容为空的 untitled 文档（除了 except 指定的那个）。
    private func closeEmptyUntitled(except keepDoc: NSDocument?) {
        for d in self.documents {
            if d === keepDoc { continue }
            guard let md = d as? MarkdownDocument else { continue }
            guard md.workspaceRootURL == nil else { continue }
            if md.fileURL == nil && md.text.isEmpty && !md.isDocumentEdited {
                md.close()
            }
        }
    }

    private func presentDirectoryOpenError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = L10n.tr("workspace.open_error.title", "Could Not Open Directory")
        alert.runModal()
    }
}
