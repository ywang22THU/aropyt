import AppKit

// MARK: - ShortcutsTabViewController

/// Shortcuts tab：显示快捷键列表，点击快捷键按钮可录制新快捷键。
final class ShortcutsTabViewController: NSViewController {

    private let actions = ShortcutAction.displayOrder

    private var tableView: NSTableView!
    private var feedbackLabel: NSTextField!

    /// 当前正在录制的行（nil = 未录制）
    private var recordingRow: Int? = nil

    /// 冲突行（key = 发生冲突的行，value = 与哪个 action 冲突）
    private var conflictRows: [Int: String] = [:]

    override func loadView() {
        let root = NSView()

        let hintLabel = NSTextField(wrappingLabelWithString:
            "Click a shortcut and press the new key combination. Recording blocks other in-app shortcuts, and conflicting changes are not saved."
        )
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.font = NSFont.systemFont(ofSize: 12)
        hintLabel.textColor = NSColor.secondaryLabelColor

        let feedbackLabel = NSTextField(wrappingLabelWithString: "")
        feedbackLabel.translatesAutoresizingMaskIntoConstraints = false
        feedbackLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        feedbackLabel.textColor = NSColor.systemOrange
        feedbackLabel.isHidden = true
        self.feedbackLabel = feedbackLabel

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let tv = NSTableView()
        tv.style = .inset
        tv.rowHeight = 36

        let actionCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("action"))
        actionCol.title = "Action"
        actionCol.width = 200
        actionCol.isEditable = false
        tv.addTableColumn(actionCol)

        let shortcutCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("shortcut"))
        shortcutCol.title = "Shortcut"
        shortcutCol.width = 260
        shortcutCol.isEditable = false
        tv.addTableColumn(shortcutCol)

        tv.dataSource = self
        tv.delegate = self
        tv.headerView = NSTableHeaderView()
        tv.target = self
        tv.action = #selector(tableClicked(_:))

        scroll.documentView = tv
        self.tableView = tv
        root.addSubview(hintLabel)
        root.addSubview(feedbackLabel)
        root.addSubview(scroll)
        NSLayoutConstraint.activate([
            hintLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            hintLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            hintLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),

            feedbackLabel.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 8),
            feedbackLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            feedbackLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),

            scroll.topAnchor.constraint(equalTo: feedbackLabel.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
        ])
        self.view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(shortcutsDidChange(_:)),
            name: ShortcutManager.didChangeNotification,
            object: ShortcutManager.shared
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Recording

    @objc private func tableClicked(_ sender: Any?) {
        let col = tableView.clickedColumn
        let row = tableView.clickedRow
        guard row >= 0, col == 1 else {
            cancelRecording()
            return
        }
        startRecording(row: row)
    }

    func recorderClicked(row: Int) {
        startRecording(row: row)
    }

    private func startRecording(row: Int) {
        let previous = recordingRow
        recordingRow = row
        clearConflictState(reloadTable: true)

        if let prev = previous, prev != row {
            tableView.reloadData(forRowIndexes: IndexSet(integer: prev),
                                 columnIndexes: IndexSet(integer: 1))
        }
        tableView.reloadData(forRowIndexes: IndexSet(integer: row),
                             columnIndexes: IndexSet(integer: 1))

        if let recorder = recorderView(at: row) {
            view.window?.makeFirstResponder(recorder)
        }
    }

    func cancelRecording() {
        guard let row = recordingRow else { return }
        recordingRow = nil
        tableView.reloadData(forRowIndexes: IndexSet(integer: row),
                             columnIndexes: IndexSet(integer: 1))
    }

    /// 尝试提交录制结果，冲突时显示警告而不保存。
    func commitRecording(row: Int, key: String, modifiers: NSEvent.ModifierFlags) {
        let action = actions[row]
        let shortcut = KeyboardShortcut(keyEquivalent: key, modifiers: modifiers)

        if let conflictLabel = ShortcutManager.shared.conflictDescription(for: shortcut, excluding: action) {
            conflictRows = [row: conflictLabel]
            recordingRow = nil
            showConflictMessage(
                shortcut: shortcut.formattedLabel,
                conflictLabel: conflictLabel
            )
            tableView.reloadData(forRowIndexes: IndexSet(integer: row),
                                 columnIndexes: IndexSet(integer: 1))
            return
        }

        ShortcutManager.shared.updateShortcut(for: action, to: shortcut)
        recordingRow = nil
        clearConflictState(reloadTable: false)
        tableView.reloadData(forRowIndexes: IndexSet(integer: row),
                             columnIndexes: IndexSet(integer: 1))
    }

    private func clearConflictState(reloadTable: Bool) {
        var rowsToReload = IndexSet()
        for row in conflictRows.keys {
            rowsToReload.insert(row)
        }
        conflictRows.removeAll()
        feedbackLabel.stringValue = ""
        feedbackLabel.isHidden = true
        guard reloadTable, !rowsToReload.isEmpty else { return }
        tableView.reloadData(forRowIndexes: rowsToReload,
                             columnIndexes: IndexSet(integer: 1))
    }

    private func showConflictMessage(shortcut: String, conflictLabel: String) {
        feedbackLabel.stringValue = "Shortcut \(shortcut) is already used by \(conflictLabel). Choose a different combination."
        feedbackLabel.isHidden = false
    }

    @objc private func shortcutsDidChange(_ notification: Notification) {
        tableView?.reloadData()
    }

    private func recorderView(at row: Int) -> ShortcutRecorderView? {
        let v = tableView.view(atColumn: 1, row: row, makeIfNecessary: false)
        return v?.subviews.compactMap { $0 as? ShortcutRecorderView }.first
    }
}

extension ShortcutsTabViewController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int { actions.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let action = actions[row]
        let shortcut = ShortcutManager.shared.shortcut(for: action)
        let colID = tableColumn?.identifier.rawValue ?? ""

        if colID == "action" {
            let id = NSUserInterfaceItemIdentifier("ActionCell")
            let cell = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView
                       ?? makeTextCell(id: id)
            cell.textField?.stringValue = action.label
            return cell

        } else {
            let id = NSUserInterfaceItemIdentifier("ShortcutCell")
            let cell: NSTableCellView
            if let reused = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView {
                cell = reused
            } else {
                let c = NSTableCellView()
                c.identifier = id
                let recorder = ShortcutRecorderView()
                recorder.translatesAutoresizingMaskIntoConstraints = false
                c.addSubview(recorder)
                NSLayoutConstraint.activate([
                    recorder.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 4),
                    recorder.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -4),
                    recorder.centerYAnchor.constraint(equalTo: c.centerYAnchor),
                    recorder.heightAnchor.constraint(equalToConstant: 24),
                ])
                cell = c
            }

            if let recorder = cell.subviews.compactMap({ $0 as? ShortcutRecorderView }).first {
                recorder.configure(
                    label: shortcut.formattedLabel,
                    isRecording: (recordingRow == row),
                    conflictWith: conflictRows[row],
                    row: row,
                    owner: self
                )
            }
            return cell
        }
    }

    private func makeTextCell(id: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let c = NSTableCellView()
        c.identifier = id
        let tf = NSTextField(labelWithString: "")
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.font = NSFont.systemFont(ofSize: 13)
        c.addSubview(tf)
        c.textField = tf
        NSLayoutConstraint.activate([
            tf.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 4),
            tf.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -4),
            tf.centerYAnchor.constraint(equalTo: c.centerYAnchor),
        ])
        return c
    }
}

// MARK: - ShortcutRecorderView

/// 单个快捷键显示 + 录制控件。
/// 普通态：圆角标签显示 "Cmd + N"。
/// 录制态：显示 "Press keys…"，通过 local event monitor 拦截所有快捷键。
/// 冲突态：橙色背景显示冲突信息。
final class ShortcutRecorderView: NSView {

    private let label = NSTextField(labelWithString: "")
    private var isRecording = false
    private var row = 0
    private weak var owner: ShortcutsTabViewController?

    /// 录制期间拦截菜单快捷键的 event monitor
    private var keyMonitor: Any?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 5

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(label labelText: String, isRecording: Bool, conflictWith: String?,
                   row: Int, owner: ShortcutsTabViewController) {
        self.isRecording = isRecording
        self.row = row
        self.owner = owner
        updateAppearance(labelText: labelText, conflictWith: conflictWith)
    }

    private func updateAppearance(labelText: String, conflictWith: String?) {
        if isRecording {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.borderWidth = 1.5
            label.stringValue = "Press keys..."
            label.textColor = NSColor.controlAccentColor
        } else if let conflict = conflictWith {
            // 冲突状态：橙色
            layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.15).cgColor
            layer?.borderColor = NSColor.systemOrange.cgColor
            layer?.borderWidth = 1.5
            label.stringValue = "Conflict with \(conflict)"
            label.textColor = NSColor.systemOrange
        } else {
            layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.25).cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
            layer?.borderWidth = 1
            label.stringValue = labelText
            label.textColor = NSColor.labelColor
        }
    }

    // MARK: - First responder

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        installKeyMonitor()
        return true
    }

    override func resignFirstResponder() -> Bool {
        removeKeyMonitor()
        if isRecording {
            owner?.cancelRecording()
        }
        return true
    }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            owner?.cancelRecording()
            window?.makeFirstResponder(nil)
        } else {
            owner?.recorderClicked(row: row)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        if event.type == .keyDown {
            handleKeyDown(event)
        }
        return true
    }

    // MARK: - Event monitor（拦截所有快捷键，包括菜单绑定）

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        // .keyDown 拦截普通按键；通过返回 nil 阻止事件传递到菜单系统
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self, self.isRecording else { return event }
            if event.type == .keyDown {
                self.handleKeyDown(event)
                return nil  // 吞掉事件，阻止触发菜单/其他快捷键
            }
            if event.type == .keyUp {
                return nil
            }
            return event  // flagsChanged 放行（modifier-only 不录制）
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        // Esc 取消
        if event.keyCode == 53 {
            owner?.cancelRecording()
            window?.makeFirstResponder(nil)
            return
        }

        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard !mods.isEmpty else { return }  // 无 modifier 不录制

        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        guard !chars.isEmpty else { return }

        owner?.commitRecording(row: row, key: chars, modifiers: mods)
        window?.makeFirstResponder(nil)
    }

    // keyDown 仍需覆盖以防止系统 beep（monitor 会先拦截，这里是保底）
    override func keyDown(with event: NSEvent) {}
}
