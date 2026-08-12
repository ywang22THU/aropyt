import AppKit
import MarkdownCore

/// Markdown 文档模型，单一数据源。
/// 注意：这里不能用 `print(...)`，会和 NSDocument 自带的 `print()` 实例方法冲突。
/// 必须写 `Swift.print(...)`。
final class MarkdownDocument: NSDocument {

    var applicationLaunchPreferences = ApplicationLaunchPreferences.shared
    var workspaceRootURL: URL?

    enum ReloadFromDiskError: LocalizedError {
        case noFileURL
        case unsavedChanges

        var errorDescription: String? {
            switch self {
            case .noFileURL:
                return L10n.tr(
                    "reload.error.no_file",
                    "This document has not been saved to disk yet."
                )
            case .unsavedChanges:
                return L10n.tr(
                    "reload.error.conflict",
                    "This document contains unsaved changes. Save or discard them before reloading."
                )
            }
        }
    }

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

    /// Saving is coordinated by AutoSaveManager so dirty preview DOM is flushed
    /// before any bytes are written.
    override class var autosavesInPlace: Bool { false }

    override func close() {
        applicationLaunchPreferences.lastClosedFileURL = fileURL
        super.close()
    }

    var isLongDocument: Bool {
        LongDocumentPolicy.isLongDocument(text)
    }

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
        self.text = try Self.decode(data)
    }

    override func data(ofType typeName: String) throws -> Data {
        return Data(self.text.utf8)
    }

    /// Reloads the current file without allowing disk contents to overwrite
    /// unsaved edits in the document model.
    func reloadFromDisk() throws {
        guard let fileURL else {
            throw ReloadFromDiskError.noFileURL
        }
        guard !isDocumentEdited else {
            throw ReloadFromDiskError.unsavedChanges
        }

        let type = fileType ?? Self.readableTypes[0]
        try revert(toContentsOf: fileURL, ofType: type)
    }

    /// Reuses this NSDocument as the active editor inside a directory window.
    /// The bytes are decoded before any document state changes, so a failed read
    /// leaves the current editor untouched.
    func loadWorkspaceFile(at url: URL) throws {
        let url = url.standardizedFileURL
        let data = try Data(contentsOf: url)
        let decodedText = try Self.decode(data)

        text = decodedText
        fileType = Self.readableTypes[0]
        fileURL = url
        undoManager?.removeAllActions()
        updateChangeCount(.changeCleared)
        windowControllers.forEach { $0.synchronizeWindowTitleWithDocumentName() }
    }

    func updateWorkspaceFileURL(afterMoving oldURL: URL, to newURL: URL) {
        guard let fileURL else { return }
        let oldComponents = oldURL.standardizedFileURL.pathComponents
        let currentComponents = fileURL.standardizedFileURL.pathComponents
        guard currentComponents.count >= oldComponents.count,
              Array(currentComponents.prefix(oldComponents.count)) == oldComponents else { return }
        let suffix = currentComponents.dropFirst(oldComponents.count)
        self.fileURL = suffix.reduce(newURL.standardizedFileURL) {
            $0.appendingPathComponent($1)
        }
        windowControllers.forEach { $0.synchronizeWindowTitleWithDocumentName() }
    }

    func clearWorkspaceFileIfDeleted(at deletedURL: URL) {
        guard let fileURL else { return }
        let deletedComponents = deletedURL.standardizedFileURL.pathComponents
        let currentComponents = fileURL.standardizedFileURL.pathComponents
        guard currentComponents.count >= deletedComponents.count,
              Array(currentComponents.prefix(deletedComponents.count)) == deletedComponents else { return }
        text = ""
        self.fileURL = nil
        undoManager?.removeAllActions()
        updateChangeCount(.changeCleared)
        windowControllers.forEach { $0.synchronizeWindowTitleWithDocumentName() }
    }

    private static func decode(_ data: Data) throws -> String {
        if let string = String(data: data, encoding: .utf8) { return string }
        if let string = String(data: data, encoding: .utf16) { return string }
        throw NSError(domain: NSCocoaErrorDomain,
                      code: NSFileReadCorruptFileError,
                      userInfo: [
                          NSLocalizedDescriptionKey: L10n.tr(
                              "error.file.decode_failed",
                              "Unable to decode file contents (not UTF-8/UTF-16)."
                          )
                      ])
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

    /// Synchronizes an edit already tracked by NSTextView or WKWebView. Those
    /// views own the undo operation so AppKit/WebKit can restore their native
    /// selection and insertion-point state. Registering another whole-document
    /// undo here would run first and reload the view, discarding that state.
    func synchronizeTextFromEditingView(_ newText: String) {
        guard text != newText else { return }
        text = newText
        updateChangeCount(.changeDone)
    }

    /// Saves an already-flushed document without opening a save panel. Untitled
    /// documents remain pending until the user chooses a location explicitly.
    func saveThroughCoordinator(completion: @escaping (Bool) -> Void) {
        guard let fileURL else {
            completion(false)
            return
        }
        let type = fileType ?? Self.writableTypes[0]
        save(to: fileURL, ofType: type, for: .saveOperation) { error in
            completion(error == nil)
        }
    }
}

extension Notification.Name {
    static let markdownDocumentTextChanged = Notification.Name("MarkdownDocumentTextChanged")
}
