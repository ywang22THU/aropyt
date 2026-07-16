import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var configurableMenuItems: [ShortcutAction: NSMenuItem] = [:]
    private var isPreparingApplicationTermination = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureSystemTooltipDelay()
        installMenuBar()
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
        // 不要在这里手动调 newDocument —— NSDocumentController 会通过
        // applicationShouldOpenUntitledFile / applicationOpenUntitledFile 自动开一个，
        // 重复调用会出现两个空白窗口。

        // 从终端启动时确保应用窗口获得焦点
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configureSystemTooltipDelay() {
        UserDefaults.standard.set(200, forKey: "NSInitialToolTipDelay")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isPreparingApplicationTermination else { return .terminateLater }
        let coordinators = NSDocumentController.shared.documents
            .flatMap(\.windowControllers)
            .compactMap { $0 as? EditorWindowController }
            .filter(\.hasUnflushedPreviewEdits)
        guard !coordinators.isEmpty else { return .terminateNow }

        isPreparingApplicationTermination = true
        var remaining = coordinators.count
        var allSucceeded = true
        for coordinator in coordinators {
            coordinator.prepareForApplicationTermination { [weak self] succeeded in
                allSucceeded = allSucceeded && succeeded
                remaining -= 1
                guard remaining == 0 else { return }
                self?.isPreparingApplicationTermination = false
                sender.reply(toApplicationShouldTerminate: allSucceeded)
            }
        }
        return .terminateLater
    }

    // MARK: - Menu

    private func installMenuBar() {
        configurableMenuItems.removeAll()
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L10n.tr("menu.about", "About AropytEditor"),
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L10n.tr("menu.hide_app", "Hide AropytEditor"),
                        action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: L10n.tr("menu.hide_others", "Hide Others"),
                                    action: #selector(NSApplication.hideOtherApplications(_:)),
                                    keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: L10n.tr("menu.show_all", "Show All"),
                        action: #selector(NSApplication.unhideAllApplications(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        let settingsItem = NSMenuItem(title: L10n.tr("menu.settings", "Settings..."),
                                      action: #selector(openSettings(_:)),
                                      keyEquivalent: "")
        appMenu.addItem(settingsItem)
        configurableMenuItems[.settings] = settingsItem
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L10n.tr("menu.quit_app", "Quit AropytEditor"),
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        // File menu
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: L10n.tr("menu.file", "File"))
        let newItem = NSMenuItem(title: L10n.tr("menu.file.new", "New"),
                                 action: #selector(NSDocumentController.newDocument(_:)),
                                 keyEquivalent: "")
        fileMenu.addItem(newItem)
        configurableMenuItems[.newDocument] = newItem

        let openItem = NSMenuItem(title: L10n.tr("menu.file.open", "Open..."),
                                  action: #selector(NSDocumentController.openDocument(_:)),
                                  keyEquivalent: "")
        fileMenu.addItem(openItem)
        configurableMenuItems[.openDocument] = openItem
        fileMenu.addItem(.separator())
        let closeItem = NSMenuItem(title: L10n.tr("menu.file.close", "Close"),
                                   action: #selector(NSWindow.performClose(_:)),
                                   keyEquivalent: "")
        fileMenu.addItem(closeItem)
        configurableMenuItems[.close] = closeItem

        let saveItem = NSMenuItem(title: L10n.tr("menu.file.save", "Save"),
                                  action: #selector(MainViewController.saveDocument(_:)),
                                  keyEquivalent: "")
        fileMenu.addItem(saveItem)
        configurableMenuItems[.save] = saveItem
        let saveAs = NSMenuItem(title: L10n.tr("menu.file.save_as", "Save As..."),
                                action: #selector(MainViewController.saveDocumentAs(_:)),
                                keyEquivalent: "S")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(saveAs)
        fileMenu.addItem(withTitle: L10n.tr("menu.file.revert_to_saved", "Revert to Saved"),
                         action: #selector(NSDocument.revertToSaved(_:)),
                         keyEquivalent: "")
        fileMenuItem.submenu = fileMenu

        // Edit menu (standard)
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: L10n.tr("menu.edit", "Edit"))
        editMenu.addItem(withTitle: L10n.tr("menu.edit.undo", "Undo"),
                         action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: L10n.tr("menu.edit.redo", "Redo"),
                              action: Selector(("redo:")),
                              keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: L10n.tr("menu.edit.cut", "Cut"),
                         action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L10n.tr("menu.edit.copy", "Copy"),
                         action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L10n.tr("menu.edit.paste", "Paste"),
                         action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L10n.tr("menu.edit.select_all", "Select All"),
                         action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        // Format menu
        let formatMenuItem = NSMenuItem()
        mainMenu.addItem(formatMenuItem)
        let formatMenu = NSMenu(title: L10n.tr("menu.format", "Format"))
        let boldItem = NSMenuItem(title: L10n.tr("menu.format.bold", "Bold"),
                                  action: #selector(MainViewController.applyBold(_:)),
                                  keyEquivalent: "")
        formatMenu.addItem(boldItem)
        configurableMenuItems[.bold] = boldItem
        let italicItem = NSMenuItem(title: L10n.tr("menu.format.italic", "Italic"),
                                    action: #selector(MainViewController.applyItalic(_:)),
                                    keyEquivalent: "")
        formatMenu.addItem(italicItem)
        configurableMenuItems[.italic] = italicItem
        formatMenuItem.submenu = formatMenu

        // View menu
        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: L10n.tr("menu.view", "View"))
        let toggleMode = NSMenuItem(title: L10n.tr("menu.view.toggle_source_preview", "Toggle Source / Preview"),
                                    action: #selector(MainViewController.toggleMode(_:)),
                                    keyEquivalent: "")
        viewMenu.addItem(toggleMode)
        configurableMenuItems[.toggleMode] = toggleMode
        viewMenuItem.submenu = viewMenu

        // Window menu
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: L10n.tr("menu.window", "Window"))
        windowMenu.addItem(withTitle: L10n.tr("menu.window.minimize", "Minimize"),
                           action: #selector(NSWindow.performMiniaturize(_:)),
                           keyEquivalent: "m")
        windowMenu.addItem(withTitle: L10n.tr("menu.window.zoom", "Zoom"),
                           action: #selector(NSWindow.performZoom(_:)),
                           keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
        applyConfiguredShortcuts()
    }

    @objc private func openSettings(_ sender: Any?) {
        SettingsWindowController.shared.showWindow()
    }

    @objc private func shortcutsDidChange(_ notification: Notification) {
        applyConfiguredShortcuts()
    }

    @objc private func languageDidChange(_ notification: Notification) {
        installMenuBar()
    }

    private func applyConfiguredShortcuts() {
        let manager = ShortcutManager.shared
        for (action, item) in configurableMenuItems {
            let shortcut = manager.shortcut(for: action)
            item.keyEquivalent = shortcut.keyEquivalent
            item.keyEquivalentModifierMask = shortcut.modifiers
        }
    }
}
