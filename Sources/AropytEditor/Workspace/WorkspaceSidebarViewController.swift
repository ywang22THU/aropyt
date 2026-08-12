import AppKit

final class WorkspaceSidebarViewController: NSViewController {
    let model: WorkspaceTreeModel
    let outlineView = WorkspaceOutlineView()

    var onOpenFile: ((URL) -> Void)?
    var onOpenInNewWindow: ((WorkspaceTreeNode) -> Void)?
    var onItemMoved: ((URL, URL) -> Void)?
    var onItemDeleted: ((URL) -> Void)?

    /// Test seam; production uses an NSAlert sheet when this is nil.
    var confirmDelete: ((WorkspaceTreeNode, @escaping (Bool) -> Void) -> Void)?

    private let scrollView = NSScrollView()
    private let copyPathHandler: (String) -> Void
    private var pendingError: Error?

    init(rootURL: URL,
         fileManager: FileManager = .default,
         copyPathHandler: ((String) -> Void)? = nil) throws {
        self.model = try WorkspaceTreeModel(rootURL: rootURL, fileManager: fileManager)
        self.copyPathHandler = copyPathHandler ?? { path in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(path, forType: .string)
        }
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 250, height: 720))

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("workspace.name"))
        column.title = L10n.tr("workspace.sidebar.title", "Files")
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.rowHeight = 24
        outlineView.indentationPerLevel = 14
        outlineView.autosaveExpandedItems = false
        outlineView.style = .plain
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.setAccessibilityIdentifier("workspace.outline")

        let menu = NSMenu()
        menu.delegate = self
        outlineView.menu = menu

        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: rootView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
        ])

        view = rootView
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        outlineView.expandItem(model.root)
    }

    func selectFile(at url: URL) {
        do {
            guard let node = try model.node(at: url) else { return }
            var ancestor = node.parent
            while let item = ancestor {
                outlineView.expandItem(item)
                ancestor = item.parent
            }
            let row = outlineView.row(forItem: node)
            guard row >= 0 else { return }
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            outlineView.scrollRowToVisible(row)
        } catch {
            present(error)
        }
    }

    func refresh(_ node: WorkspaceTreeNode? = nil) {
        let target = node ?? model.root
        let wasExpanded = outlineView.isItemExpanded(target)
        model.refresh(target)
        outlineView.reloadItem(target, reloadChildren: true)
        if wasExpanded || target === model.root {
            outlineView.expandItem(target)
        }
    }

    func contextMenu(for node: WorkspaceTreeNode) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(menuItem(
            title: L10n.tr("workspace.menu.open_new_window", "Open in New Window"),
            action: #selector(openInNewWindow(_:)),
            node: node
        ))

        if node.isDirectory {
            menu.addItem(.separator())
            menu.addItem(menuItem(
                title: L10n.tr("workspace.menu.new_markdown_file", "New Markdown File"),
                action: #selector(createMarkdownFile(_:)),
                node: node
            ))
            menu.addItem(menuItem(
                title: L10n.tr("workspace.menu.new_folder", "New Folder"),
                action: #selector(createFolder(_:)),
                node: node
            ))
        }

        menu.addItem(.separator())
        let renameItem = menuItem(
            title: L10n.tr("workspace.menu.rename", "Rename"),
            action: #selector(renameItem(_:)),
            node: node
        )
        let deleteItem = menuItem(
            title: L10n.tr("workspace.menu.delete", "Delete"),
            action: #selector(deleteItem(_:)),
            node: node
        )
        let isRoot = node === model.root
        renameItem.isEnabled = !isRoot
        deleteItem.isEnabled = !isRoot
        menu.addItem(renameItem)
        menu.addItem(deleteItem)

        if node.isDirectory {
            menu.addItem(.separator())
            menu.addItem(menuItem(
                title: L10n.tr("workspace.menu.refresh", "Refresh"),
                action: #selector(refreshItem(_:)),
                node: node
            ))
        }

        menu.addItem(.separator())
        menu.addItem(menuItem(
            title: L10n.tr("workspace.menu.reveal_in_finder", "Show in Finder"),
            action: #selector(revealInFinder(_:)),
            node: node
        ))
        menu.addItem(menuItem(
            title: L10n.tr("workspace.menu.copy_path", "Copy File Path"),
            action: #selector(copyPath(_:)),
            node: node
        ))
        return menu
    }

    private func menuItem(title: String, action: Selector, node: WorkspaceTreeNode) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = node
        return item
    }

    private func node(from sender: Any?) -> WorkspaceTreeNode? {
        (sender as? NSMenuItem)?.representedObject as? WorkspaceTreeNode
    }

    @objc private func openInNewWindow(_ sender: Any?) {
        guard let node = node(from: sender) else { return }
        onOpenInNewWindow?(node)
    }

    @objc private func createMarkdownFile(_ sender: Any?) {
        guard let directory = node(from: sender), directory.isDirectory else { return }
        requestName(
            title: L10n.tr("workspace.new_file.title", "New Markdown File"),
            message: L10n.tr("workspace.new_file.message", "Enter a name for the new Markdown file."),
            defaultValue: L10n.tr("workspace.new_file.default_name", "Untitled.md"),
            confirmationTitle: L10n.tr("workspace.action.create", "Create")
        ) { [weak self] name in
            guard let self, let name else { return }
            do {
                let url = try self.model.fileSystem.createMarkdownFile(in: directory.url, named: name)
                self.refresh(directory)
                self.selectFile(at: url)
                self.onOpenFile?(url)
            } catch {
                self.present(error)
            }
        }
    }

    @objc private func createFolder(_ sender: Any?) {
        guard let directory = node(from: sender), directory.isDirectory else { return }
        requestName(
            title: L10n.tr("workspace.new_folder.title", "New Folder"),
            message: L10n.tr("workspace.new_folder.message", "Enter a name for the new folder."),
            defaultValue: L10n.tr("workspace.new_folder.default_name", "New Folder"),
            confirmationTitle: L10n.tr("workspace.action.create", "Create")
        ) { [weak self] name in
            guard let self, let name else { return }
            do {
                _ = try self.model.fileSystem.createDirectory(in: directory.url, named: name)
                self.refresh(directory)
            } catch {
                self.present(error)
            }
        }
    }

    @objc private func renameItem(_ sender: Any?) {
        guard let node = node(from: sender), node !== model.root else { return }
        let oldURL = node.url
        requestName(
            title: L10n.tr("workspace.rename.title", "Rename"),
            message: L10n.tr("workspace.rename.message", "Enter a new name for “%@”.", node.name),
            defaultValue: node.name,
            confirmationTitle: L10n.tr("workspace.menu.rename", "Rename")
        ) { [weak self] name in
            guard let self, let name else { return }
            do {
                let newURL = try self.model.fileSystem.renameItem(at: oldURL, to: name)
                self.model.updateURLs(afterMoving: oldURL, to: newURL)
                if let parent = node.parent {
                    self.refresh(parent)
                } else {
                    self.outlineView.reloadData()
                }
                self.onItemMoved?(oldURL, newURL)
            } catch {
                self.present(error)
            }
        }
    }

    @objc private func deleteItem(_ sender: Any?) {
        guard let node = node(from: sender), node !== model.root else { return }
        let performDelete: (Bool) -> Void = { [weak self, weak node] confirmed in
            guard confirmed, let self, let node else { return }
            let url = node.url
            do {
                try self.model.fileSystem.deleteItem(at: url)
                if let parent = node.parent {
                    self.refresh(parent)
                } else {
                    self.outlineView.reloadData()
                }
                self.onItemDeleted?(url)
            } catch {
                self.present(error)
            }
        }
        if let confirmDelete {
            confirmDelete(node, performDelete)
        } else {
            presentDeleteConfirmation(for: node, completion: performDelete)
        }
    }

    @objc private func refreshItem(_ sender: Any?) {
        guard let node = node(from: sender), node.isDirectory else { return }
        refresh(node)
    }

    @objc private func revealInFinder(_ sender: Any?) {
        guard let node = node(from: sender) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }

    @objc private func copyPath(_ sender: Any?) {
        guard let node = node(from: sender) else { return }
        copyPathHandler(node.url.path)
    }

    private func requestName(title: String,
                             message: String,
                             defaultValue: String,
                             confirmationTitle: String,
                             completion: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirmationTitle)
        alert.addButton(withTitle: L10n.tr("workspace.action.cancel", "Cancel"))
        let field = NSTextField(string: defaultValue)
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = field

        let finish: (NSApplication.ModalResponse) -> Void = { response in
            completion(response == .alertFirstButtonReturn ? field.stringValue : nil)
        }
        if let window = view.window {
            alert.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(alert.runModal())
        }
    }

    private func presentDeleteConfirmation(for node: WorkspaceTreeNode,
                                           completion: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = L10n.tr("workspace.delete.title", "Delete “%@”?", node.name)
        alert.informativeText = L10n.tr(
            "workspace.delete.message",
            "This item will be permanently deleted from disk. This action cannot be undone."
        )
        alert.addButton(withTitle: L10n.tr("workspace.menu.delete", "Delete"))
        alert.addButton(withTitle: L10n.tr("workspace.action.cancel", "Cancel"))
        let finish: (NSApplication.ModalResponse) -> Void = {
            completion($0 == .alertFirstButtonReturn)
        }
        if let window = view.window {
            alert.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(alert.runModal())
        }
    }

    private func present(_ error: Error) {
        let alert = NSAlert(error: error)
        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else {
            pendingError = error
        }
    }
}

extension WorkspaceSidebarViewController: NSOutlineViewDataSource, NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView,
                     numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? WorkspaceTreeNode else { return 1 }
        do {
            return try model.children(of: node).count
        } catch {
            pendingError = error
            return 0
        }
    }

    func outlineView(_ outlineView: NSOutlineView,
                     child index: Int,
                     ofItem item: Any?) -> Any {
        guard let node = item as? WorkspaceTreeNode else { return model.root }
        do {
            return try model.children(of: node)[index]
        } catch {
            pendingError = error
            return node
        }
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? WorkspaceTreeNode)?.isDirectory == true
    }

    func outlineView(_ outlineView: NSOutlineView,
                     viewFor tableColumn: NSTableColumn?,
                     item: Any) -> NSView? {
        guard let node = item as? WorkspaceTreeNode else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("workspace.cell")
        let cell: NSTableCellView
        if let reused = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier
            let icon = NSImageView()
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.imageScaling = .scaleProportionallyDown
            icon.setContentHuggingPriority(.required, for: .horizontal)
            let label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.lineBreakMode = .byTruncatingMiddle
            cell.imageView = icon
            cell.textField = label
            cell.addSubview(icon)
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 16),
                icon.heightAnchor.constraint(equalToConstant: 16),
                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 5),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        cell.textField?.stringValue = node.name
        cell.imageView?.image = node.isDirectory
            ? NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            : NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        let row = outlineView.selectedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? WorkspaceTreeNode else { return }
        if node.isDirectory {
            if !outlineView.isItemExpanded(node) {
                outlineView.expandItem(node)
            }
        } else {
            onOpenFile?(node.url)
        }
    }
}

extension WorkspaceSidebarViewController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = outlineView.clickedRow >= 0 ? outlineView.clickedRow : outlineView.selectedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? WorkspaceTreeNode else { return }
        for item in contextMenu(for: node).items {
            menu.addItem(item.copy() as! NSMenuItem)
        }
    }
}

final class WorkspaceOutlineView: NSOutlineView {
    override func menu(for event: NSEvent) -> NSMenu? {
        let clickedRow = row(at: convert(event.locationInWindow, from: nil))
        if clickedRow >= 0 {
            selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
        }
        return super.menu(for: event)
    }
}
