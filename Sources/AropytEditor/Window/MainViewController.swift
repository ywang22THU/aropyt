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
    private let contentContainer = NSView()
    private let findBar = FindBarView()
    private var findGeneration = 0

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
    private var isSwitchingMode = false

    var onBusyStateChanged: ((Bool) -> Void)?

    var hasUnflushedPreviewEdits: Bool {
        mode == .preview && previewVC?.isDirty == true
    }

    private var container: NSView { contentContainer }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1100, height: 720))
        root.autoresizingMask = [.width, .height]

        contentContainer.frame = root.bounds
        contentContainer.autoresizingMask = [.width, .height]
        root.addSubview(contentContainer)

        findBar.translatesAutoresizingMaskIntoConstraints = false
        findBar.isHidden = true
        root.addSubview(findBar)
        NSLayoutConstraint.activate([
            findBar.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
            findBar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
        ])
        self.view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        sourceVC.onTextChanged = { [weak self] newText in
            guard let self, let doc = self.document else { return }
            guard doc.text != newText else { return }
            // 用户在源码模式下打字 → 同步到 document
            doc.synchronizeTextFromEditingView(newText)
            AutoSaveManager.shared.contentDidChange(in: doc)
        }
        findBar.onQueryChanged = { [weak self] _ in self?.performFind(.initial) }
        findBar.onNext = { [weak self] in self?.performFind(.next) }
        findBar.onPrevious = { [weak self] in self?.performFind(.previous) }
        findBar.onReplaceCurrent = { [weak self] in self?.performReplaceCurrent() }
        findBar.onReplaceAll = { [weak self] in self?.performReplaceAll() }
        findBar.onClose = { [weak self] in self?.hideFind() }
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange(_:)),
            name: L10n.didChangeNotification,
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
        guard !isPreparingForDiskWrite, !isSwitchingMode else { return }
        switch mode {
        case .source:
            let sourceOffset = sourceVC.viewportSourceOffset()
            switchTo(.preview, sourceOffset: sourceOffset)
        case .preview:
            requestSwitchToSource()
        }
    }

    private func requestSwitchToSource() {
        guard mode == .preview else { return }
        guard let previewVC else {
            switchTo(.source, sourceOffset: nil)
            return
        }

        isSwitchingMode = true
        previewVC.viewportSourceOffset { [weak self] sourceOffset in
            guard let self, self.mode == .preview else {
                self?.isSwitchingMode = false
                return
            }
            self.finishSwitchingToSource(sourceOffset: sourceOffset)
        }
    }

    private func finishSwitchingToSource(sourceOffset: Int?) {
        let performSwitch = { [weak self] in
            guard let self else { return }
            self.switchTo(.source, sourceOffset: sourceOffset)
            self.isSwitchingMode = false
            if AutoSavePreferences.shared.mode == .never,
               let document = self.document,
               document.fileURL != nil {
                document.saveThroughCoordinator { _ in }
            }
        }

        guard previewVC?.isDirty == true else {
            performSwitch()
            return
        }
        prepareForDiskWrite { [weak self] succeeded in
            guard let self else { return }
            guard succeeded else {
                self.isSwitchingMode = false
                return
            }
            performSwitch()
        }
    }

    private func switchTo(_ newMode: Mode, sourceOffset: Int?) {
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
            if let sourceOffset {
                sourceVC.scrollToSourceOffset(sourceOffset)
            }
        case .preview:
            embedPreview()
            if let doc = self.document {
                previewVC?.load(markdown: doc.text)
            }
            if let sourceOffset {
                previewVC?.scrollToSourceOffset(sourceOffset)
            }
        }
        if !findBar.isHidden, findBar.hasQuery {
            performFind(.initial)
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
                doc.synchronizeTextFromEditingView(newText)
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
            pvc.onRenderReady = { [weak self, weak pvc] in
                guard let self, self.mode == .preview, self.previewVC === pvc,
                      !self.findBar.isHidden, self.findBar.hasQuery else { return }
                self.performFind(.initial)
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

    // MARK: - Find

    @IBAction func showFind(_ sender: Any?) {
        _ = view
        findBar.updateLocalization()
        findBar.isHidden = false
        findBar.focus(in: view.window)
        if findBar.hasQuery {
            performFind(.initial)
        } else {
            findBar.setResult(nil)
        }
    }

    @IBAction func showReplace(_ sender: Any?) {
        _ = view
        findBar.updateLocalization()
        findBar.isHidden = false
        findBar.showReplace()
        findBar.focus(in: view.window)
        if findBar.hasQuery {
            performFind(.initial)
        } else {
            findBar.setResult(nil)
        }
    }

    @IBAction func findNext(_ sender: Any?) {
        _ = view
        if findBar.isHidden {
            findBar.isHidden = false
            findBar.updateLocalization()
        }
        guard findBar.hasQuery else {
            findBar.focus(in: view.window)
            return
        }
        performFind(.next)
    }

    @IBAction func findPrevious(_ sender: Any?) {
        _ = view
        if findBar.isHidden {
            findBar.isHidden = false
            findBar.updateLocalization()
        }
        guard findBar.hasQuery else {
            findBar.focus(in: view.window)
            return
        }
        performFind(.previous)
    }

    private func performFind(_ direction: DocumentFindDirection) {
        let query = findBar.query
        guard !query.isEmpty else {
            findGeneration &+= 1
            findBar.setResult(nil)
            return
        }
        findGeneration &+= 1
        let generation = findGeneration
        switch mode {
        case .source:
            findBar.setResult(sourceVC.find(query: query, direction: direction))
        case .preview:
            findBar.setResult(nil)
            previewVC?.find(query: query, direction: direction) { [weak self] result in
                guard let self, generation == self.findGeneration else { return }
                self.findBar.setResult(result)
            }
        }
    }

    private func performReplaceCurrent() {
        guard !isPreparingForDiskWrite, findBar.hasQuery else { return }
        findGeneration &+= 1
        let generation = findGeneration
        switch mode {
        case .source:
            let result = sourceVC.replaceCurrent(
                query: findBar.query,
                with: findBar.replacement
            )
            findBar.setResult(result?.findResult)
        case .preview:
            findBar.setResult(nil)
            previewVC?.replaceCurrent(
                query: findBar.query,
                with: findBar.replacement
            ) { [weak self] result in
                guard let self, generation == self.findGeneration else { return }
                self.findBar.setResult(result?.findResult)
            }
        }
    }

    private func performReplaceAll() {
        guard !isPreparingForDiskWrite, findBar.hasQuery else { return }
        findGeneration &+= 1
        let generation = findGeneration
        switch mode {
        case .source:
            let result = sourceVC.replaceAll(
                query: findBar.query,
                with: findBar.replacement
            )
            findBar.setResult(result?.findResult)
        case .preview:
            findBar.setResult(nil)
            previewVC?.replaceAll(
                query: findBar.query,
                with: findBar.replacement
            ) { [weak self] result in
                guard let self, generation == self.findGeneration else { return }
                self.findBar.setResult(result?.findResult)
            }
        }
    }

    private func hideFind() {
        findGeneration &+= 1
        findBar.isHidden = true
        switch mode {
        case .source:
            sourceVC.focusEditor()
        case .preview:
            view.window?.makeFirstResponder(previewVC?.view)
        }
    }

    @objc private func languageDidChange(_ notification: Notification) {
        findBar.updateLocalization()
    }

    // MARK: - Reload / save / close coordination

    @IBAction func reloadDocument(_ sender: Any?) {
        guard !isPreparingForDiskWrite, !isSwitchingMode, let document else { return }
        guard !hasUnflushedPreviewEdits, !document.isDocumentEdited else {
            presentReloadError(MarkdownDocument.ReloadFromDiskError.unsavedChanges)
            return
        }

        do {
            try document.reloadFromDisk()
            AutoSaveManager.shared.markSaved(document)
        } catch {
            presentReloadError(error)
        }
    }

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
                    document.synchronizeTextFromEditingView(markdown)
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

    private func presentReloadError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.tr("reload.error.title", "Could Not Reload")
        alert.informativeText = error.localizedDescription
        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    // MARK: - Validation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleMode(_:)) {
            menuItem.title = (mode == .source)
                ? L10n.tr("menu.view.switch_to_preview", "Switch to Preview")
                : L10n.tr("menu.view.switch_to_source", "Switch to Source")
            return !isPreparingForDiskWrite && !isSwitchingMode
        }
        if menuItem.action == #selector(applyBold(_:)) || menuItem.action == #selector(applyItalic(_:)) {
            return mode == .preview && !isPreparingForDiskWrite
        }
        if menuItem.action == #selector(saveDocument(_:))
            || menuItem.action == #selector(saveDocumentAs(_:)) {
            return !isPreparingForDiskWrite
        }
        if menuItem.action == #selector(reloadDocument(_:)) {
            return document?.fileURL != nil && !isPreparingForDiskWrite && !isSwitchingMode
        }
        if menuItem.action == #selector(findNext(_:))
            || menuItem.action == #selector(findPrevious(_:)) {
            return true
        }
        return true
    }
}
