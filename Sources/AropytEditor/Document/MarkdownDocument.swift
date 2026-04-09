import AppKit

/// Markdown 文档模型，单一数据源。
/// 注意：这里不能用 `print(...)`，会和 NSDocument 自带的 `print()` 实例方法冲突。
/// 必须写 `Swift.print(...)`。
final class MarkdownDocument: NSDocument {

    /// 文档当前文本。所有视图都从这里读、写。
    var text: String = "" {
        didSet {
            guard text != oldValue else { return }
            // 文本变化时通知主视图刷新预览（如果在预览模式）
            NotificationCenter.default.post(
                name: .markdownDocumentTextChanged,
                object: self
            )
        }
    }

    override init() {
        super.init()
        self.hasUndoManager = true
    }

    override class var autosavesInPlace: Bool { true }

    override class var readableTypes: [String] {
        return ["net.daringfireball.markdown", "public.plain-text"]
    }

    override class var writableTypes: [String] {
        return ["net.daringfireball.markdown", "public.plain-text"]
    }

    override func makeWindowControllers() {
        let wc = EditorWindowController()
        addWindowController(wc)
        // 不依赖 windowDidLoad —— 用 init(window:) 创建的窗口不会触发它。
        wc.setup(document: self)
    }

    // MARK: - 读写

    override func read(from data: Data, ofType typeName: String) throws {
        if let s = String(data: data, encoding: .utf8) {
            self.text = s
        } else if let s = String(data: data, encoding: .utf16) {
            self.text = s
        } else {
            throw NSError(domain: NSCocoaErrorDomain,
                          code: NSFileReadCorruptFileError,
                          userInfo: [NSLocalizedDescriptionKey: "无法解码文件内容（非 UTF-8/UTF-16）"])
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        return Data(self.text.utf8)
    }

    // MARK: - 文本变更入口（视图控制器调用，走 undo manager）

    /// 由视图控制器调用：把新文本写入 document，并注册 undo。
    func updateText(_ newText: String, actionName: String? = nil) {
        let old = self.text
        guard old != newText else { return }
        if let undo = self.undoManager {
            undo.registerUndo(withTarget: self) { target in
                target.updateText(old, actionName: actionName)
            }
            if let name = actionName {
                undo.setActionName(name)
            }
        }
        self.text = newText
        self.updateChangeCount(.changeDone)
    }
}

extension Notification.Name {
    static let markdownDocumentTextChanged = Notification.Name("MarkdownDocumentTextChanged")
}
