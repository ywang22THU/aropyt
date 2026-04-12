import AppKit

/// 左右布局的设置界面：左侧 sidebar 列表，右侧 tab 内容。
final class SettingsTabViewController: NSSplitViewController {

    private enum Tab: Int, CaseIterable {
        case shortcuts = 0
        case theme = 1
        case help = 2

        var title: String {
            switch self {
            case .shortcuts: return "Shortcuts"
            case .theme:     return "Theme"
            case .help:      return "Help"
            }
        }

        var symbol: String {
            switch self {
            case .shortcuts: return "keyboard"
            case .theme:     return "paintbrush"
            case .help:      return "questionmark.circle"
            }
        }
    }

    private var sidebarVC: SidebarListViewController!
    private var contentContainerVC: ContentContainerViewController!
    private var currentTab: Tab = .shortcuts
    private var tabControllers: [Tab: NSViewController] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()

        // Sidebar
        let sidebar = SidebarListViewController()
        sidebar.tabs = Tab.allCases.map { (title: $0.title, symbol: $0.symbol) }
        sidebar.onSelect = { [weak self] index in
            guard let tab = Tab(rawValue: index) else { return }
            self?.switchTo(tab)
        }
        self.sidebarVC = sidebar

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 150
        sidebarItem.maximumThickness = 150
        sidebarItem.canCollapse = false
        addSplitViewItem(sidebarItem)

        // Content
        let container = ContentContainerViewController()
        self.contentContainerVC = container

        let contentItem = NSSplitViewItem(viewController: container)
        contentItem.minimumThickness = 400
        addSplitViewItem(contentItem)

        switchTo(.shortcuts)
        sidebar.selectRow(0)
    }

    private func switchTo(_ tab: Tab) {
        currentTab = tab
        contentContainerVC.setContent(viewController(for: tab))
    }

    private func viewController(for tab: Tab) -> NSViewController {
        if let vc = tabControllers[tab] { return vc }
        let vc: NSViewController
        switch tab {
        case .shortcuts: vc = ShortcutsTabViewController()
        case .theme:     vc = ThemeTabViewController()
        case .help:      vc = HelpTabViewController()
        }
        tabControllers[tab] = vc
        return vc
    }
}

// MARK: - SidebarListViewController

/// 左侧列表，每行：图标 + 标题。
final class SidebarListViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {

    var tabs: [(title: String, symbol: String)] = []
    var onSelect: ((Int) -> Void)?

    private var tableView: NSTableView!

    override func loadView() {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = false
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        let tv = NSTableView()
        tv.style = .sourceList
        tv.headerView = nil
        tv.rowHeight = 36
        tv.allowsEmptySelection = false
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        col.isEditable = false
        tv.addTableColumn(col)
        tv.dataSource = self
        tv.delegate = self

        scroll.documentView = tv
        self.tableView = tv
        self.view = scroll
    }

    func selectRow(_ row: Int) {
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { tabs.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("SidebarCell")
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView {
            cell = reused
        } else {
            let c = NSTableCellView()
            c.identifier = id

            let img = NSImageView()
            img.translatesAutoresizingMaskIntoConstraints = false
            c.addSubview(img)
            c.imageView = img

            let tf = NSTextField(labelWithString: "")
            tf.translatesAutoresizingMaskIntoConstraints = false
            tf.font = NSFont.systemFont(ofSize: 13)
            c.addSubview(tf)
            c.textField = tf

            NSLayoutConstraint.activate([
                img.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 6),
                img.centerYAnchor.constraint(equalTo: c.centerYAnchor),
                img.widthAnchor.constraint(equalToConstant: 18),
                img.heightAnchor.constraint(equalToConstant: 18),
                tf.leadingAnchor.constraint(equalTo: img.trailingAnchor, constant: 6),
                tf.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -4),
                tf.centerYAnchor.constraint(equalTo: c.centerYAnchor),
            ])
            cell = c
        }

        let tab = tabs[row]
        cell.textField?.stringValue = tab.title
        cell.imageView?.image = NSImage(systemSymbolName: tab.symbol,
                                        accessibilityDescription: tab.title)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0 else { return }
        onSelect?(row)
    }
}

// MARK: - ContentContainerViewController

/// 右侧内容容器，纯容器，切换 tab 内容。
final class ContentContainerViewController: NSViewController {

    private var currentChild: NSViewController?

    override func loadView() {
        let v = NSView()
        v.wantsLayer = true
        self.view = v
    }

    func setContent(_ vc: NSViewController) {
        if let old = currentChild {
            old.view.removeFromSuperview()
            old.removeFromParent()
        }

        addChild(vc)
        let v = vc.view
        v.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(v)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: view.topAnchor),
            v.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            v.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            v.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        currentChild = vc
    }
}
