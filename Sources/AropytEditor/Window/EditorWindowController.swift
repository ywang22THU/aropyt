import AppKit

/// 文档窗口控制器。
///
/// 关键陷阱：用 `init(window:)` 传入预建窗口时，AppKit 不会触发 `windowDidLoad`。
/// 因此所有初始化逻辑放在 `setup(document:)` 里，由 `MarkdownDocument.makeWindowControllers`
/// 在 `addWindowController` 之后显式调用。
final class EditorWindowController: NSWindowController, NSWindowDelegate {

    private var mainVC: MainViewController?
    private var isObservingShortcutChanges = false

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
        self.init(window: window)
    }

    /// 在 addWindowController 之后由 document 显式调用。
    func setup(document: MarkdownDocument) {
        let vc = MainViewController()
        vc.document = document
        self.contentViewController = vc
        self.mainVC = vc
        self.window?.delegate = self
        self.window?.toolbar = makeToolbar()

        // 通过 representedObject 也传一份，方便 VC 内部访问
        vc.representedObject = document

        // 明确触发 loadView/viewDidLoad，避免打包 app 打开文件时
        // reloadFromDocument 早于 SourceViewController.textView 创建。
        _ = vc.view

        startObservingShortcutChangesIfNeeded()
        updateToolbarTooltips()

        // 触发首次加载
        vc.reloadFromDocument()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Toolbar

    private func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "AropytEditorToolbar")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconOnly
        return toolbar
    }

    private func startObservingShortcutChangesIfNeeded() {
        guard !isObservingShortcutChanges else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(shortcutsDidChange(_:)),
            name: ShortcutManager.didChangeNotification,
            object: ShortcutManager.shared
        )
        isObservingShortcutChanges = true
    }

    @objc private func shortcutsDidChange(_ notification: Notification) {
        updateToolbarTooltips()
    }

    private func updateToolbarTooltips() {
        guard let items = window?.toolbar?.items else { return }
        let manager = ShortcutManager.shared
        for item in items {
            if item.itemIdentifier == Self.toggleModeItemID {
                item.setTooltipOnItemAndView(Self.toggleModeTooltip(manager: manager))
            } else if item.itemIdentifier == Self.settingsItemID {
                item.setTooltipOnItemAndView(Self.settingsTooltip(manager: manager))
            } else if let btn = Self.formatButtons.first(where: { $0.id == item.itemIdentifier }) {
                item.setTooltipOnItemAndView(Self.tooltip(for: btn, manager: manager))
            }
        }
    }

    /// 描述一个格式化按钮的元数据
    fileprivate struct FormatButton {
        let id: NSToolbarItem.Identifier
        let label: String
        let symbol: String
        let command: String
        let tooltip: String
    }

    fileprivate static let formatButtons: [FormatButton] = [
        .init(id: .init("AropytEditor.Format.Bold"),
              label: "Bold", symbol: "bold", command: "bold",
              tooltip: "粗体（仅预览模式）"),
        .init(id: .init("AropytEditor.Format.Italic"),
              label: "Italic", symbol: "italic", command: "italic",
              tooltip: "斜体（仅预览模式）"),
        .init(id: .init("AropytEditor.Format.Strike"),
              label: "Strikethrough", symbol: "strikethrough", command: "strikethrough",
              tooltip: "删除线（仅预览模式）"),
        .init(id: .init("AropytEditor.Format.H1"),
              label: "H1", symbol: "1.square", command: "h1",
              tooltip: "一级标题"),
        .init(id: .init("AropytEditor.Format.H2"),
              label: "H2", symbol: "2.square", command: "h2",
              tooltip: "二级标题"),
        .init(id: .init("AropytEditor.Format.Code"),
              label: "Code", symbol: "chevron.left.forwardslash.chevron.right", command: "code",
              tooltip: "行内代码"),
        .init(id: .init("AropytEditor.Format.CodeBlock"),
              label: "Code Block", symbol: "curlybraces", command: "codeblock",
              tooltip: "代码块"),
        .init(id: .init("AropytEditor.Format.UL"),
              label: "Bulleted List", symbol: "list.bullet", command: "ul",
              tooltip: "无序列表"),
        .init(id: .init("AropytEditor.Format.OL"),
              label: "Numbered List", symbol: "list.number", command: "ol",
              tooltip: "有序列表"),
        .init(id: .init("AropytEditor.Format.Quote"),
              label: "Quote", symbol: "text.quote", command: "blockquote",
              tooltip: "引用块"),
    ]

    fileprivate static func toggleModeTooltip(manager: ShortcutManager = ShortcutManager.shared) -> String {
        return "切换源码 / 预览模式 (\(manager.shortcut(for: .toggleMode).formattedLabel))"
    }

    fileprivate static func settingsTooltip(manager: ShortcutManager = ShortcutManager.shared) -> String {
        return "Settings (\(manager.shortcut(for: .settings).formattedLabel))"
    }

    fileprivate static func tooltip(for button: FormatButton,
                                    manager: ShortcutManager = ShortcutManager.shared) -> String {
        switch button.command {
        case "bold":
            return "粗体（仅预览模式，\(manager.shortcut(for: .bold).formattedLabel)）"
        case "italic":
            return "斜体（仅预览模式，\(manager.shortcut(for: .italic).formattedLabel)）"
        default:
            return button.tooltip
        }
    }
}

extension EditorWindowController: NSToolbarDelegate {

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
        var ids: [NSToolbarItem.Identifier] = [.flexibleSpace, .space, Self.toggleModeItemID, Self.settingsItemID]
        for btn in Self.formatButtons {
            ids.append(btn.id)
        }
        return ids
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if itemIdentifier == Self.toggleModeItemID {
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Source / Preview"
            item.paletteLabel = "Source / Preview"
            let tooltip = Self.toggleModeTooltip()
            item.setTooltipOnItemAndView(tooltip)
            item.image = NSImage(systemSymbolName: "doc.richtext", accessibilityDescription: "Toggle")
            item.view = makeToolbarButton(symbol: "doc.richtext",
                                          accessibilityDescription: "Toggle",
                                          tooltip: tooltip,
                                          tag: 0,
                                          action: #selector(toggleModeFromToolbar(_:)))
            return item
        }
        if itemIdentifier == Self.settingsItemID {
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Settings"
            item.paletteLabel = "Settings"
            let tooltip = Self.settingsTooltip()
            item.setTooltipOnItemAndView(tooltip)
            item.image = NSImage(systemSymbolName: "gear", accessibilityDescription: "Settings")
            item.view = makeToolbarButton(symbol: "gear",
                                          accessibilityDescription: "Settings",
                                          tooltip: tooltip,
                                          tag: 0,
                                          action: #selector(openSettingsFromToolbar(_:)))
            return item
        }
        if let btn = Self.formatButtons.first(where: { $0.id == itemIdentifier }) {
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = btn.label
            item.paletteLabel = btn.label
            let tooltip = Self.tooltip(for: btn)
            item.setTooltipOnItemAndView(tooltip)
            item.image = NSImage(systemSymbolName: btn.symbol,
                                 accessibilityDescription: btn.label)
                ?? NSImage(systemSymbolName: "questionmark", accessibilityDescription: nil)
            // 用 tag 编码命令在按钮列表里的索引
            item.tag = Self.formatButtons.firstIndex(where: { $0.id == itemIdentifier }) ?? 0
            item.view = makeToolbarButton(symbol: btn.symbol,
                                          accessibilityDescription: btn.label,
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
