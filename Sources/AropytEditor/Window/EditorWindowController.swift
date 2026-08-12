import AppKit

/// 文档窗口控制器。
///
/// 关键陷阱：用 `init(window:)` 传入预建窗口时，AppKit 不会触发 `windowDidLoad`。
/// 因此所有初始化逻辑放在 `setup(document:)` 里，由 `MarkdownDocument.makeWindowControllers`
/// 在 `addWindowController` 之后显式调用。
final class EditorWindowController: NSWindowController, NSWindowDelegate {

    private var mainVC: MainViewController?
    private(set) var workspaceContainer: WorkspaceContainerViewController?
    private var isObservingToolbarLocalizationChanges = false
    private var closePreparationRunning = false
    private var allowsNextClose = false
    private var isEditorBusy = false
    private var workspaceTransitionRunning = false
    private var pendingWorkspaceFileURL: URL?

    var workspaceRootURL: URL? {
        workspaceContainer?.sidebarViewController.model.fileSystem.rootURL
    }

    convenience init() {
        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        window.title = "Untitled"
        window.center()
        window.setFrameAutosaveName("AropytEditorMainWindow")
        window.minSize = NSSize(width: 600, height: 400)
        window.toolbarStyle = .unified
        self.init(window: window)
    }

    /// 在 addWindowController 之后由 document 显式调用。
    func setup(document: MarkdownDocument) {
        let vc = MainViewController()
        vc.document = document
        self.contentViewController = vc
        self.mainVC = vc
        vc.onBusyStateChanged = { [weak self] busy in
            self?.isEditorBusy = busy
            self?.updateEditingControlsEnabled()
        }
        self.window?.delegate = self
        self.window?.toolbar = makeToolbar()

        // 通过 representedObject 也传一份，方便 VC 内部访问
        vc.representedObject = document

        // 明确触发 loadView/viewDidLoad，避免打包 app 打开文件时
        // reloadFromDocument 早于 SourceViewController.textView 创建。
        _ = vc.view

        startObservingToolbarLocalizationChangesIfNeeded()
        updateToolbarLocalization()

        // 触发首次加载
        vc.reloadFromDocument()
    }

    func openDirectory(at rootURL: URL) throws {
        guard let mainVC, let document = mainVC.document else {
            throw CocoaError(.fileReadUnknown)
        }
        let sidebar = try WorkspaceSidebarViewController(rootURL: rootURL)
        let container = WorkspaceContainerViewController(
            sidebarViewController: sidebar,
            editorViewController: mainVC
        )
        container.onSidebarVisibilityChanged = { [weak self] _ in
            self?.updateSidebarToolbarItem()
        }
        sidebar.onOpenFile = { [weak self] url in
            self?.openWorkspaceFile(at: url)
        }
        sidebar.onOpenInNewWindow = { [weak self] node in
            self?.openWorkspaceItemInNewWindow(node)
        }
        sidebar.onItemMoved = { [weak self] oldURL, newURL in
            guard let self, let document = self.mainVC?.document else { return }
            document.updateWorkspaceFileURL(afterMoving: oldURL, to: newURL)
            self.workspaceContainer?.sidebarViewController.selectFile(at: document.fileURL ?? newURL)
        }
        sidebar.onItemDeleted = { [weak self] deletedURL in
            guard let self, let document = self.mainVC?.document else { return }
            document.clearWorkspaceFileIfDeleted(at: deletedURL)
            self.mainVC?.reloadFromDocument()
            if document.fileURL == nil {
                self.window?.title = rootURL.lastPathComponent
            }
        }

        workspaceContainer = container
        document.workspaceRootURL = sidebar.model.fileSystem.rootURL
        contentViewController = container
        _ = container.view
        if let toolbar = window?.toolbar,
           !toolbar.items.contains(where: { $0.itemIdentifier == Self.sidebarItemID }) {
            toolbar.insertItem(withItemIdentifier: Self.sidebarItemID, at: 0)
        }
        updateSidebarToolbarItem()

        if let fileURL = document.fileURL,
           sidebar.model.fileSystem.contains(fileURL),
           WorkspaceFileSystem.isMarkdownFile(fileURL) {
            sidebar.selectFile(at: fileURL)
        } else if document.fileURL == nil {
            window?.title = rootURL.lastPathComponent
        }
    }

    func openWorkspaceFile(at url: URL) {
        guard !workspaceTransitionRunning,
              let mainVC,
              let document = mainVC.document else { return }
        let url = url.standardizedFileURL
        guard url != document.fileURL?.standardizedFileURL else {
            workspaceContainer?.sidebarViewController.selectFile(at: url)
            return
        }

        setWorkspaceTransitionRunning(true)
        mainVC.prepareToClose { [weak self, weak document] succeeded in
            guard let self, let document else { return }
            guard succeeded else {
                self.setWorkspaceTransitionRunning(false)
                return
            }
            guard document.isDocumentEdited else {
                self.finishOpeningWorkspaceFile(url, in: document)
                return
            }
            self.pendingWorkspaceFileURL = url
            document.canClose(
                withDelegate: self,
                shouldClose: #selector(self.document(_:shouldClose:contextInfo:)),
                contextInfo: nil
            )
        }
    }

    @objc private func document(_ document: NSDocument,
                                shouldClose: Bool,
                                contextInfo: UnsafeMutableRawPointer?) {
        let url = pendingWorkspaceFileURL
        pendingWorkspaceFileURL = nil
        guard shouldClose, let url, let markdownDocument = document as? MarkdownDocument else {
            setWorkspaceTransitionRunning(false)
            return
        }
        finishOpeningWorkspaceFile(url, in: markdownDocument)
    }

    private func finishOpeningWorkspaceFile(_ url: URL, in document: MarkdownDocument) {
        do {
            try document.loadWorkspaceFile(at: url)
            AutoSaveManager.shared.markSaved(document)
            mainVC?.reloadFromDocument()
            workspaceContainer?.sidebarViewController.selectFile(at: url)
        } catch {
            presentWorkspaceError(error)
        }
        setWorkspaceTransitionRunning(false)
    }

    private func openWorkspaceItemInNewWindow(_ node: WorkspaceTreeNode) {
        if node.isDirectory {
            (NSDocumentController.shared as? AppDocumentController)?.openDirectory(at: node.url)
            return
        }
        NSDocumentController.shared.openDocument(
            withContentsOf: node.url,
            display: true
        ) { _, _, error in
            guard let error else { return }
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    private func presentWorkspaceError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = L10n.tr("workspace.operation_error.title", "Workspace Operation Failed")
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func setWorkspaceTransitionRunning(_ running: Bool) {
        workspaceTransitionRunning = running
        updateEditingControlsEnabled()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if allowsNextClose {
            allowsNextClose = false
            return true
        }
        guard mainVC?.hasUnflushedPreviewEdits == true else { return true }
        guard !closePreparationRunning else { return false }

        closePreparationRunning = true
        mainVC?.prepareToClose { [weak self, weak sender] succeeded in
            guard let self else { return }
            self.closePreparationRunning = false
            guard succeeded, let sender else { return }
            self.allowsNextClose = true
            sender.performClose(nil)
        }
        return false
    }

    var hasUnflushedPreviewEdits: Bool {
        mainVC?.hasUnflushedPreviewEdits == true
    }

    func prepareForApplicationTermination(completion: @escaping (Bool) -> Void) {
        mainVC?.prepareToClose(completion: completion) ?? completion(true)
    }

    // MARK: - Toolbar

    private func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "AropytEditorToolbar")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconOnly
        return toolbar
    }

    private func startObservingToolbarLocalizationChangesIfNeeded() {
        guard !isObservingToolbarLocalizationChanges else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(shortcutsDidChange(_:)),
            name: ShortcutManager.didChangeNotification,
            object: ShortcutManager.shared
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange(_:)),
            name: L10n.didChangeNotification,
            object: nil
        )
        isObservingToolbarLocalizationChanges = true
    }

    @objc private func shortcutsDidChange(_ notification: Notification) {
        updateToolbarLocalization()
    }

    @objc private func languageDidChange(_ notification: Notification) {
        updateToolbarLocalization()
    }

    private func updateToolbarLocalization() {
        guard let items = window?.toolbar?.items else { return }
        let manager = ShortcutManager.shared
        for item in items {
            if item.itemIdentifier == Self.sidebarItemID {
                updateSidebarToolbarItem(item)
            } else if item.itemIdentifier == Self.toggleModeItemID {
                let label = L10n.tr("toolbar.toggle_source_preview.label", "Source / Preview")
                let accessibility = L10n.tr(
                    "toolbar.toggle_source_preview.accessibility",
                    "Toggle source / preview"
                )
                item.label = label
                item.paletteLabel = label
                item.setTooltipOnItemAndView(Self.toggleModeTooltip(manager: manager))
                item.image = NSImage(systemSymbolName: "doc.richtext", accessibilityDescription: accessibility)
                if let button = item.view as? NSButton {
                    button.image = item.image
                    button.setAccessibilityLabel(accessibility)
                }
            } else if item.itemIdentifier == Self.settingsItemID {
                let label = L10n.tr("toolbar.settings.label", "Settings")
                item.label = label
                item.paletteLabel = label
                item.setTooltipOnItemAndView(Self.settingsTooltip(manager: manager))
                item.image = NSImage(systemSymbolName: "gear", accessibilityDescription: label)
                if let button = item.view as? NSButton {
                    button.image = item.image
                    button.setAccessibilityLabel(label)
                }
            } else if let btn = Self.formatButtons.first(where: { $0.id == item.itemIdentifier }) {
                let label = Self.label(for: btn)
                item.label = label
                item.paletteLabel = label
                item.setTooltipOnItemAndView(Self.tooltip(for: btn, manager: manager))
                item.image = NSImage(systemSymbolName: btn.symbol, accessibilityDescription: label)
                    ?? NSImage(systemSymbolName: "questionmark", accessibilityDescription: nil)
                if let button = item.view as? NSButton {
                    button.image = item.image
                    button.setAccessibilityLabel(label)
                }
            }
        }
    }

    private func updateEditingControlsEnabled() {
        setEditingControlsEnabled(!isEditorBusy && !workspaceTransitionRunning)
    }

    private func setEditingControlsEnabled(_ enabled: Bool) {
        for item in window?.toolbar?.items ?? [] where item.itemIdentifier != Self.settingsItemID {
            item.isEnabled = enabled
            (item.view as? NSControl)?.isEnabled = enabled
        }
        workspaceContainer?.sidebarViewController.outlineView.isEnabled = enabled
    }

    private func updateSidebarToolbarItem(_ item: NSToolbarItem? = nil) {
        guard let container = workspaceContainer else { return }
        let item = item ?? window?.toolbar?.items.first {
            $0.itemIdentifier == Self.sidebarItemID
        }
        guard let item else { return }
        let visible = container.isSidebarVisible
        let title = visible
            ? L10n.tr("toolbar.sidebar.hide", "Hide Sidebar")
            : L10n.tr("toolbar.sidebar.show", "Show Sidebar")
        let symbol = Self.sidebarSymbolName(isVisible: visible)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            ?? NSImage(systemSymbolName: visible ? "rectangle.leadinghalf.filled" : "rectangle", accessibilityDescription: title)
        item.label = title
        item.paletteLabel = title
        item.image = image
        item.setTooltipOnItemAndView(title)
        if let button = item.view as? NSButton {
            button.image = image
            button.setAccessibilityLabel(title)
        }
    }

    static func sidebarSymbolName(isVisible: Bool) -> String {
        isVisible ? "sidebar.left" : "sidebar.right"
    }

    func toggleWorkspaceSidebar() {
        workspaceContainer?.toggleSidebar()
        updateSidebarToolbarItem()
    }

    /// 描述一个格式化按钮的元数据
    fileprivate struct FormatButton {
        let id: NSToolbarItem.Identifier
        let labelKey: String
        let labelFallback: String
        let symbol: String
        let command: String
        let tooltipKey: String
        let tooltipFallback: String
    }

    fileprivate static let formatButtons: [FormatButton] = [
        .init(id: .init("AropytEditor.Format.Bold"),
              labelKey: "toolbar.format.bold.label", labelFallback: "Bold",
              symbol: "bold", command: "bold",
              tooltipKey: "toolbar.format.bold.tooltip", tooltipFallback: "Bold (Preview mode only)"),
        .init(id: .init("AropytEditor.Format.Italic"),
              labelKey: "toolbar.format.italic.label", labelFallback: "Italic",
              symbol: "italic", command: "italic",
              tooltipKey: "toolbar.format.italic.tooltip", tooltipFallback: "Italic (Preview mode only)"),
        .init(id: .init("AropytEditor.Format.Strike"),
              labelKey: "toolbar.format.strikethrough.label", labelFallback: "Strikethrough",
              symbol: "strikethrough", command: "strikethrough",
              tooltipKey: "toolbar.format.strikethrough.tooltip",
              tooltipFallback: "Strikethrough (Preview mode only)"),
        .init(id: .init("AropytEditor.Format.H1"),
              labelKey: "toolbar.format.h1.label", labelFallback: "H1",
              symbol: "1.square", command: "h1",
              tooltipKey: "toolbar.format.h1.tooltip", tooltipFallback: "Heading 1 (Preview mode only)"),
        .init(id: .init("AropytEditor.Format.H2"),
              labelKey: "toolbar.format.h2.label", labelFallback: "H2",
              symbol: "2.square", command: "h2",
              tooltipKey: "toolbar.format.h2.tooltip", tooltipFallback: "Heading 2 (Preview mode only)"),
        .init(id: .init("AropytEditor.Format.Code"),
              labelKey: "toolbar.format.code.label", labelFallback: "Code",
              symbol: "chevron.left.forwardslash.chevron.right", command: "code",
              tooltipKey: "toolbar.format.code.tooltip", tooltipFallback: "Inline code (Preview mode only)"),
        .init(id: .init("AropytEditor.Format.CodeBlock"),
              labelKey: "toolbar.format.code_block.label", labelFallback: "Code Block",
              symbol: "curlybraces", command: "codeblock",
              tooltipKey: "toolbar.format.code_block.tooltip", tooltipFallback: "Code block (Preview mode only)"),
        .init(id: .init("AropytEditor.Format.UL"),
              labelKey: "toolbar.format.bulleted_list.label", labelFallback: "Bulleted List",
              symbol: "list.bullet", command: "ul",
              tooltipKey: "toolbar.format.bulleted_list.tooltip",
              tooltipFallback: "Bulleted list (Preview mode only)"),
        .init(id: .init("AropytEditor.Format.OL"),
              labelKey: "toolbar.format.numbered_list.label", labelFallback: "Numbered List",
              symbol: "list.number", command: "ol",
              tooltipKey: "toolbar.format.numbered_list.tooltip",
              tooltipFallback: "Numbered list (Preview mode only)"),
        .init(id: .init("AropytEditor.Format.Quote"),
              labelKey: "toolbar.format.quote.label", labelFallback: "Quote",
              symbol: "text.quote", command: "blockquote",
              tooltipKey: "toolbar.format.quote.tooltip", tooltipFallback: "Block quote (Preview mode only)"),
    ]

    fileprivate static func toggleModeTooltip(manager: ShortcutManager = ShortcutManager.shared) -> String {
        return L10n.tr(
            "toolbar.toggle_source_preview.tooltip",
            "Toggle source / preview mode (%@)",
            manager.shortcut(for: .toggleMode).formattedLabel
        )
    }

    fileprivate static func settingsTooltip(manager: ShortcutManager = ShortcutManager.shared) -> String {
        return L10n.tr(
            "toolbar.settings.tooltip",
            "Settings (%@)",
            manager.shortcut(for: .settings).formattedLabel
        )
    }

    fileprivate static func tooltip(for button: FormatButton,
                                    manager: ShortcutManager = ShortcutManager.shared) -> String {
        switch button.command {
        case "bold":
            return L10n.tr(
                "toolbar.format.bold.tooltip_with_shortcut",
                "Bold (Preview mode only, %@)",
                manager.shortcut(for: .bold).formattedLabel
            )
        case "italic":
            return L10n.tr(
                "toolbar.format.italic.tooltip_with_shortcut",
                "Italic (Preview mode only, %@)",
                manager.shortcut(for: .italic).formattedLabel
            )
        default:
            return L10n.tr(button.tooltipKey, button.tooltipFallback)
        }
    }

    fileprivate static func label(for button: FormatButton) -> String {
        return L10n.tr(button.labelKey, button.labelFallback)
    }
}

extension EditorWindowController: NSToolbarDelegate {

    static let sidebarItemID    = NSToolbarItem.Identifier("AropytEditor.Sidebar")
    static let toggleModeItemID = NSToolbarItem.Identifier("AropytEditor.ToggleMode")
    static let settingsItemID   = NSToolbarItem.Identifier("AropytEditor.Settings")

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        var ids: [NSToolbarItem.Identifier] = []
        for btn in Self.formatButtons {
            ids.append(btn.id)
        }
        ids.append(.flexibleSpace)
        ids.append(Self.toggleModeItemID)
        ids.append(Self.settingsItemID)
        return ids
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        var ids: [NSToolbarItem.Identifier] = [
            .flexibleSpace, .space, Self.sidebarItemID, Self.toggleModeItemID, Self.settingsItemID,
        ]
        for btn in Self.formatButtons {
            ids.append(btn.id)
        }
        return ids
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if itemIdentifier == Self.sidebarItemID {
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            let visible = workspaceContainer?.isSidebarVisible ?? true
            let title = visible
                ? L10n.tr("toolbar.sidebar.hide", "Hide Sidebar")
                : L10n.tr("toolbar.sidebar.show", "Show Sidebar")
            let symbol = Self.sidebarSymbolName(isVisible: visible)
            item.label = title
            item.paletteLabel = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            item.view = makeToolbarButton(symbol: symbol,
                                          accessibilityDescription: title,
                                          tooltip: title,
                                          tag: 0,
                                          action: #selector(toggleSidebarFromToolbar(_:)))
            return item
        }
        if itemIdentifier == Self.toggleModeItemID {
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            let label = L10n.tr("toolbar.toggle_source_preview.label", "Source / Preview")
            let accessibility = L10n.tr(
                "toolbar.toggle_source_preview.accessibility",
                "Toggle source / preview"
            )
            item.label = label
            item.paletteLabel = label
            let tooltip = Self.toggleModeTooltip()
            item.setTooltipOnItemAndView(tooltip)
            item.image = NSImage(systemSymbolName: "doc.richtext", accessibilityDescription: accessibility)
            item.view = makeToolbarButton(symbol: "doc.richtext",
                                          accessibilityDescription: accessibility,
                                          tooltip: tooltip,
                                          tag: 0,
                                          action: #selector(toggleModeFromToolbar(_:)))
            return item
        }
        if itemIdentifier == Self.settingsItemID {
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            let label = L10n.tr("toolbar.settings.label", "Settings")
            item.label = label
            item.paletteLabel = label
            let tooltip = Self.settingsTooltip()
            item.setTooltipOnItemAndView(tooltip)
            item.image = NSImage(systemSymbolName: "gear", accessibilityDescription: label)
            item.view = makeToolbarButton(symbol: "gear",
                                          accessibilityDescription: label,
                                          tooltip: tooltip,
                                          tag: 0,
                                          action: #selector(openSettingsFromToolbar(_:)))
            return item
        }
        if let btn = Self.formatButtons.first(where: { $0.id == itemIdentifier }) {
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            let label = Self.label(for: btn)
            item.label = label
            item.paletteLabel = label
            let tooltip = Self.tooltip(for: btn)
            item.setTooltipOnItemAndView(tooltip)
            item.image = NSImage(systemSymbolName: btn.symbol,
                                 accessibilityDescription: label)
                ?? NSImage(systemSymbolName: "questionmark", accessibilityDescription: nil)
            // 用 tag 编码命令在按钮列表里的索引
            item.tag = Self.formatButtons.firstIndex(where: { $0.id == itemIdentifier }) ?? 0
            item.view = makeToolbarButton(symbol: btn.symbol,
                                          accessibilityDescription: label,
                                          tooltip: tooltip,
                                          tag: item.tag,
                                          action: #selector(formatItemAction(_:)))
            return item
        }
        return nil
    }

    private func makeToolbarButton(symbol: String,
                                   accessibilityDescription: String,
                                   tooltip: String,
                                   tag: Int,
                                   action: Selector) -> NSButton {
        let button = HoverableToolbarButton(frame: NSRect(x: 0, y: 0, width: 32, height: 28))
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.image = NSImage(systemSymbolName: symbol,
                               accessibilityDescription: accessibilityDescription)
            ?? NSImage(systemSymbolName: "questionmark", accessibilityDescription: nil)
        button.toolTip = tooltip
        button.tag = tag
        button.target = self
        button.action = action
        button.setAccessibilityLabel(accessibilityDescription)
        return button
    }

    @objc private func openSettingsFromToolbar(_ sender: Any?) {
        SettingsWindowController.shared.showWindow()
    }

    @objc private func toggleModeFromToolbar(_ sender: Any?) {
        mainVC?.toggleMode(sender)
    }

    @objc private func toggleSidebarFromToolbar(_ sender: Any?) {
        toggleWorkspaceSidebar()
    }

    @objc private func formatItemAction(_ sender: Any?) {
        let idx: Int
        if let item = sender as? NSToolbarItem {
            idx = item.tag
        } else if let button = sender as? NSButton {
            idx = button.tag
        } else {
            return
        }
        guard idx >= 0 && idx < Self.formatButtons.count else { return }
        let cmd = Self.formatButtons[idx].command
        mainVC?.applyFormat(cmd)
    }
}

private final class HoverableToolbarButton: NSButton {
    override var intrinsicContentSize: NSSize {
        return NSSize(width: 32, height: 28)
    }

    override var acceptsFirstResponder: Bool {
        return false
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

private extension NSToolbarItem {
    func setTooltipOnItemAndView(_ tooltip: String) {
        self.toolTip = tooltip
        self.view?.toolTip = tooltip
    }
}
