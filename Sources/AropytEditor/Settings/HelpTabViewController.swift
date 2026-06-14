import AppKit

/// Help tab：介绍基础功能。
final class HelpTabViewController: NSViewController {

    private var textView: NSTextView?

    override func loadView() {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        let tv = NSTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 20, height: 20)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(
            width: 0, height: CGFloat.greatestFiniteMagnitude)

        let content = buildHelpContent()
        tv.textStorage?.setAttributedString(content)

        scroll.documentView = tv
        self.textView = tv
        self.view = scroll
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

    private func buildHelpContent() -> NSAttributedString {
        let result = NSMutableAttributedString()
        let shortcuts = ShortcutManager.shared

        let titleFont = NSFont.systemFont(ofSize: 20, weight: .bold)
        let headingFont = NSFont.systemFont(ofSize: 15, weight: .semibold)
        let bodyFont = NSFont.systemFont(ofSize: 13, weight: .regular)
        let monoFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.paragraphSpacing = 6

        func title(_ s: String) {
            result.append(NSAttributedString(string: s + "\n\n", attributes: [
                .font: titleFont,
                .foregroundColor: NSColor.labelColor,
            ]))
        }

        func heading(_ s: String) {
            result.append(NSAttributedString(string: "\n" + s + "\n", attributes: [
                .font: headingFont,
                .foregroundColor: NSColor.labelColor,
            ]))
        }

        func body(_ s: String) {
            result.append(NSAttributedString(string: s + "\n", attributes: [
                .font: bodyFont,
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paraStyle,
            ]))
        }

        func shortcut(_ key: String, _ desc: String) {
            let line = NSMutableAttributedString()
            line.append(NSAttributedString(string: "  \(key)", attributes: [
                .font: monoFont,
                .foregroundColor: NSColor.labelColor,
            ]))
            line.append(NSAttributedString(string: "  — \(desc)\n", attributes: [
                .font: bodyFont,
                .foregroundColor: NSColor.secondaryLabelColor,
            ]))
            result.append(line)
        }

        title(L10n.tr("settings.help.title", "AropytEditor Help"))

        heading(L10n.tr("settings.help.overview.heading", "Overview"))
        body(L10n.tr(
            "settings.help.overview.body",
            "AropytEditor is a lightweight Markdown editor for macOS. It provides a source editing mode with syntax highlighting and a live preview mode powered by marked.js."
        ))

        heading(L10n.tr("settings.help.editing_modes.heading", "Editing Modes"))
        body(L10n.tr(
            "settings.help.editing_modes.source",
            "• Source Mode — Edit raw Markdown with syntax highlighting."
        ))
        body(L10n.tr(
            "settings.help.editing_modes.preview",
            "• Preview Mode — See rendered HTML output with code highlighting."
        ))

        heading(L10n.tr("settings.help.keyboard_shortcuts.heading", "Keyboard Shortcuts"))
        shortcut(shortcuts.shortcut(for: .newDocument).formattedLabel,
                 L10n.tr("settings.help.shortcuts.new_document", "New document"))
        shortcut(shortcuts.shortcut(for: .openDocument).formattedLabel,
                 L10n.tr("settings.help.shortcuts.open_document", "Open document"))
        shortcut(shortcuts.shortcut(for: .save).formattedLabel,
                 L10n.tr("settings.help.shortcuts.save", "Save"))
        shortcut(shortcuts.shortcut(for: .close).formattedLabel,
                 L10n.tr("settings.help.shortcuts.close", "Close window"))
        shortcut(shortcuts.shortcut(for: .toggleMode).formattedLabel,
                 L10n.tr("settings.help.shortcuts.toggle_mode", "Toggle source / preview mode"))
        shortcut(shortcuts.shortcut(for: .settings).formattedLabel,
                 L10n.tr("settings.help.shortcuts.settings", "Open settings"))

        heading(L10n.tr("settings.help.links.heading", "Links"))
        body(L10n.tr(
            "settings.help.links.body",
            "In source mode, Cmd+Click on a link to open it in your browser. Links without a scheme (e.g. www.example.com) are automatically prefixed with https://."
        ))

        heading(L10n.tr("settings.help.toolbar.heading", "Toolbar"))
        body(L10n.tr(
            "settings.help.toolbar.body",
            "The toolbar provides quick access to formatting commands: Bold, Italic, Strikethrough, Headings, Code, Lists, and Blockquote."
        ))

        return result
    }

    @objc private func shortcutsDidChange(_ notification: Notification) {
        textView?.textStorage?.setAttributedString(buildHelpContent())
    }
}
