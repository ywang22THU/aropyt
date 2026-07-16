import AppKit

/// 协调器：在源码 VC 和预览 VC 之间切换。
final class MainViewController: NSViewController, NSMenuItemValidation {

    enum Mode {
        case source
        case preview
    }

    weak var document: MarkdownDocument?

    private(set) var mode: Mode = .preview

    private let sourceVC = SourceViewController()
    /// 预览 VC 懒加载：webView 必须等到 view 第一次访问时 loadView() 才会创建。
    private var previewVC: PreviewViewController?

    /// 当前正在把"来自预览编辑"的更新写回 document。
    /// 在这个窗口期间，document 的变更通知不应再回流去 reload 预览 webview，
    /// 否则会触发 loadHTMLString 重置整页（表现为按下空格后视图先跳到顶部、再回到光标）。
    private var isApplyingFromPreview = false
    private var isPreparingForDiskWrite = false {
        didSet {
            guard oldValue != isPreparingForDiskWrite else { return }
            onBusyStateChanged?(isPreparingForDiskWrite)
        }
    }
    private var preparationCompletions: [(Bool) -> Void] = []

    var onBusyStateChanged: ((Bool) -> Void)?

    var hasUnflushedPreviewEdits: Bool {
        mode == .preview && previewVC?.isDirty == true
    }

    private var container: NSView { self.view }

    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 1100, height: 720))
        self.view.autoresizingMask = [.width, .height]
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        sourceVC.onTextChanged = { [weak self] newText in
            guard let self, let doc = self.document else { return }
            guard doc.text != newText else { return }
            // 用户在源码模式下打字 → 同步到 document
            doc.updateText(newText, actionName: "Edit")
            AutoSaveManager.shared.contentDidChange(in: doc)
        }
        embedPreview()
        if let document {
            AutoSaveManager.shared.register(document: document) { [weak self] completion in
                guard let self else {
                    completion(false)
                    return
                }
                self.performAutoSave(completion: completion)
            }
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(documentTextChangedExternally(_:)),
            name: .markdownDocumentTextChanged,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if let document {
            AutoSaveManager.shared.unregister(document: document)
        }
    }

    /// 由 WindowController 在 setup 之后调用，把 document 内容首次填进 view。
    func reloadFromDocument() {
        _ = self.view
        guard let doc = self.document else { return }
        if mode == .source {
            sourceVC.setText(doc.text)
        }
        // 新窗口默认预览模式，首次加载时把文档内容渲染进 WebView。
        if mode == .preview {
            previewVC?.load(markdown: doc.text)
        }
    }

    @objc private func documentTextChangedExternally(_ note: Notification) {
        guard let doc = note.object as? MarkdownDocument, doc === self.document else { return }
        // 如果这次变更是用户在预览里编辑触发的，跳过对 webview 的回流刷新，
        // 不然 loadHTMLString 会重置整页（光标位置 / 滚动位置全丢）。
        if isApplyingFromPreview {
            // 源码 VC 不可见时也不必同步，等切回源码再 reload
            if mode == .source && sourceVC.currentText != doc.text {
                sourceVC.setText(doc.text)
            }
            return
        }
        if mode == .preview, previewVC?.isDirty == true {
            // Never replace unflushed DOM edits with an older document snapshot.
            return
        }
        // 源码模式下，避免回填覆盖光标：只有内容真的不同才更新
        if mode == .source, sourceVC.currentText != doc.text {
            sourceVC.setText(doc.text)
        }
        if mode == .preview {
            previewVC?.load(markdown: doc.text)
        }
    }

    // MARK: - Mode switch

    @IBAction func toggleMode(_ sender: Any?) {
        guard !isPreparingForDiskWrite else { return }
        switch mode {
        case .source:
            switchTo(.preview)
        case .preview:
            requestSwitchToSource()
        }
    }

    private func requestSwitchToSource() {
        guard mode == .preview else { return }
        guard previewVC?.isDirty == true else {
            switchTo(.source)
            return
        }
        prepareForDiskWrite { [weak self] succeeded in
            guard let self, succeeded else { return }
            self.switchTo(.source)
            if AutoSavePreferences.shared.mode == .never,
               let document = self.document,
               document.fileURL != nil {
                document.saveThroughCoordinator { _ in }
            }
        }
    }

    private func switchTo(_ newMode: Mode) {
        guard newMode != mode else { return }
        // 离开源码 → 把当前文本同步进 document
        if mode == .source, let doc = self.document {
            doc.updateText(sourceVC.currentText)
        }
        mode = newMode
        // 移除现有子 VC
        for child in children {
            child.view.removeFromSuperview()
        }
        children.removeAll()

        switch newMode {
        case .source:
            embedSource()
            if let doc = self.document {
                sourceVC.setText(doc.text)
            }
        case .preview:
            embedPreview()
            if let doc = self.document {
                previewVC?.load(markdown: doc.text)
            }
        }
    }

    private func embedSource() {
        addChild(sourceVC)
        sourceVC.view.frame = container.bounds
        sourceVC.view.autoresizingMask = [.width, .height]
        container.addSubview(sourceVC.view)
    }

    private func embedPreview() {
        if previewVC == nil {
            let pvc = PreviewViewController()
            pvc.onMarkdownEdited = { [weak self] newText in
                guard let self, let doc = self.document else { return }
                // 用户在预览模式直接编辑 → 同步到 document
                // 标记 isApplyingFromPreview，让 documentTextChangedExternally 跳过对
                // webview 的回流刷新（否则 loadHTMLString 会让光标 + 滚动位置全丢）
                self.isApplyingFromPreview = true
                doc.updateText(newText, actionName: "Edit")
                self.isApplyingFromPreview = false
                AutoSaveManager.shared.contentDidChange(in: doc)
            }
            pvc.onDirtyStateChanged = { [weak self] dirty in
                guard
                    dirty,
                    let document = self?.document,
                    document.isLongDocument
                else { return }
                AutoSaveManager.shared.contentDidChange(in: document)
            }
            previewVC = pvc
        }
        guard let pvc = previewVC else { return }
        addChild(pvc)
        // 关键：先 _ = view 触发 loadView，再访问 webView
        _ = pvc.view
        pvc.view.frame = container.bounds
        pvc.view.autoresizingMask = [.width, .height]
        container.addSubview(pvc.view)
        // 让 webview 成为 firstResponder，避免 spacebar 路由到 NSScrollView 触发滚动
        DispatchQueue.main.async { [weak self] in
            self?.view.window?.makeFirstResponder(pvc.view)
        }
    }

    /// 由 toolbar / 菜单调用：在预览模式下应用一个格式化命令。
    func applyFormat(_ command: String) {
        guard !isPreparingForDiskWrite, mode == .preview, let pvc = previewVC else {
            NSSound.beep()
            return
        }
        pvc.applyFormat(command)
    }

    @IBAction func applyBold(_ sender: Any?) {
        applyFormat("bold")
    }

    @IBAction func applyItalic(_ sender: Any?) {
        applyFormat("italic")
    }

    // MARK: - Save / close coordination

    @IBAction func saveDocument(_ sender: Any?) {
        guard !isPreparingForDiskWrite else { return }
        prepareForDiskWrite { [weak self] succeeded in
            guard succeeded, let self, let document = self.document else { return }
            document.save(sender)
        }
    }

    @IBAction func saveDocumentAs(_ sender: Any?) {
        guard !isPreparingForDiskWrite else { return }
        prepareForDiskWrite { [weak self] succeeded in
            guard succeeded, let self, let document = self.document else { return }
            document.saveAs(sender)
        }
    }

    func prepareToClose(completion: @escaping (Bool) -> Void) {
        prepareForDiskWrite(completion: completion)
    }

    private func prepareForDiskWrite(completion: @escaping (Bool) -> Void) {
        guard mode == .preview, let previewVC, previewVC.isDirty else {
            completion(true)
            return
        }

        preparationCompletions.append(completion)
        guard !isPreparingForDiskWrite else { return }
        isPreparingForDiskWrite = true
        previewVC.flushPreviewEdits { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let markdown):
                if let markdown, let document = self.document {
                    self.isApplyingFromPreview = true
                    document.updateText(markdown, actionName: "Edit")
                    self.isApplyingFromPreview = false
                }
                self.finishPreparation(succeeded: true)
            case .failure:
                self.presentFlushFailureAlert()
                self.finishPreparation(succeeded: false)
            }
        }
    }

    private func finishPreparation(succeeded: Bool) {
        isPreparingForDiskWrite = false
        let completions = preparationCompletions
        preparationCompletions.removeAll()
        completions.forEach { $0(succeeded) }
    }

    private func performAutoSave(completion: @escaping (Bool) -> Void) {
        prepareForDiskWrite { [weak self] succeeded in
            guard succeeded, let document = self?.document else {
                completion(false)
                return
            }
            document.saveThroughCoordinator(completion: completion)
        }
    }

    private func presentFlushFailureAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.tr("preview.flush.alert.title", "Preview edits were not saved")
        alert.informativeText = L10n.tr(
            "preview.flush.error",
            "Could not convert Preview edits back to Markdown. Your edits remain in Preview and the older Markdown was not saved."
        )
        if let window = view.window {
            alert.beginSheetModal(for: window)
        }
    }

    // MARK: - Validation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleMode(_:)) {
            menuItem.title = (mode == .source)
                ? L10n.tr("menu.view.switch_to_preview", "Switch to Preview")
                : L10n.tr("menu.view.switch_to_source", "Switch to Source")
            return !isPreparingForDiskWrite
        }
        if menuItem.action == #selector(applyBold(_:)) || menuItem.action == #selector(applyItalic(_:)) {
            return mode == .preview && !isPreparingForDiskWrite
        }
        if menuItem.action == #selector(saveDocument(_:))
            || menuItem.action == #selector(saveDocumentAs(_:)) {
            return !isPreparingForDiskWrite
        }
        return true
    }
}
