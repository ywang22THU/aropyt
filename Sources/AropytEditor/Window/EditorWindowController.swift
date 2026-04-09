import AppKit

/// 文档窗口控制器。
///
/// 关键陷阱：用 `init(window:)` 传入预建窗口时，AppKit 不会触发 `windowDidLoad`。
/// 因此所有初始化逻辑放在 `setup(document:)` 里，由 `MarkdownDocument.makeWindowControllers`
/// 在 `addWindowController` 之后显式调用。
final class EditorWindowController: NSWindowController, NSWindowDelegate {

    private var mainVC: MainViewController?

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

        // 触发首次加载
        vc.reloadFromDocument()
    }

    // MARK: - Toolbar

    private func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "AropytEditorToolbar")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconOnly
        return toolbar
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
}

extension EditorWindowController: NSToolbarDelegate {

    static let toggleModeItemID = NSToolbarItem.Identifier("AropytEditor.ToggleMode")

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        var ids: [NSToolbarItem.Identifier] = []
        for btn in Self.formatButtons {
            ids.append(btn.id)
        }
        ids.append(.flexibleSpace)
        ids.append(Self.toggleModeItemID)
        return ids
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        var ids: [NSToolbarItem.Identifier] = [.flexibleSpace, .space, Self.toggleModeItemID]
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
            item.toolTip = "切换源码 / 预览模式 (⌘⇧P)"
            item.image = NSImage(systemSymbolName: "doc.richtext", accessibilityDescription: "Toggle")
            item.target = self
            item.action = #selector(toggleModeFromToolbar(_:))
            return item
        }
        if let btn = Self.formatButtons.first(where: { $0.id == itemIdentifier }) {
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = btn.label
            item.paletteLabel = btn.label
            item.toolTip = btn.tooltip
            item.image = NSImage(systemSymbolName: btn.symbol,
                                 accessibilityDescription: btn.label)
                ?? NSImage(systemSymbolName: "questionmark", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(formatItemAction(_:))
            // 用 tag 编码命令在按钮列表里的索引
            item.tag = Self.formatButtons.firstIndex(where: { $0.id == itemIdentifier }) ?? 0
            return item
        }
        return nil
    }

    @objc private func toggleModeFromToolbar(_ sender: Any?) {
        mainVC?.toggleMode(sender)
    }

    @objc private func formatItemAction(_ sender: Any?) {
        guard let item = sender as? NSToolbarItem else { return }
        let idx = item.tag
        guard idx >= 0 && idx < Self.formatButtons.count else { return }
        let cmd = Self.formatButtons[idx].command
        mainVC?.applyFormat(cmd)
    }
}
