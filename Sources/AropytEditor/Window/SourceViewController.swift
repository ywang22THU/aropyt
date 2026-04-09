import AppKit

/// 源码模式：NSTextView + 简单正则语法高亮。
final class SourceViewController: NSViewController, NSTextViewDelegate {

    /// 不要用 lazy var：在 loadView 中通过 helper 创建 NSTextView 后，
    /// 容易出现 scrollView 持有的实例和 self 属性不是同一个的诡异情况。
    /// 改用普通可选属性，loadView 中显式赋值。
    private var textView: NSTextView?
    private var scrollView: NSScrollView?
    private let highlighter = MarkdownHighlighter()

    /// 文本变化回调（用户编辑触发）
    var onTextChanged: ((String) -> Void)?

    var currentText: String {
        return textView?.string ?? ""
    }

    override func loadView() {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = false
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.translatesAutoresizingMaskIntoConstraints = true

        let contentSize = scroll.contentSize
        let tv = NSTextView(frame: NSRect(x: 0, y: 0,
                                          width: contentSize.width,
                                          height: contentSize.height))
        // NSTextView 必备配置 —— 不设这几项可能整片空白
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                            height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.containerSize = NSSize(width: contentSize.width,
                                                 height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true

        tv.isRichText = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isAutomaticDataDetectionEnabled = false
        tv.usesFontPanel = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        tv.textColor = NSColor.textColor
        tv.backgroundColor = NSColor.textBackgroundColor
        tv.insertionPointColor = NSColor.textColor
        tv.delegate = self

        scroll.documentView = tv

        self.textView = tv
        self.scrollView = scroll
        self.view = scroll
    }

    /// 由外部（document 加载完成、模式切换）调用，强制设置内容并触发高亮。
    func setText(_ s: String) {
        guard let tv = textView else { return }
        if tv.string != s {
            tv.string = s
        }
        applyHighlighting()
    }

    private func applyHighlighting() {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.removeAttribute(.foregroundColor, range: full)
        storage.removeAttribute(.font, range: full)
        let baseFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        storage.addAttribute(.font, value: baseFont, range: full)
        storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: full)
        highlighter.apply(to: storage)
        storage.endEditing()
    }

    // MARK: - NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        guard let tv = textView else { return }
        onTextChanged?(tv.string)
        applyHighlighting()
    }

    /// NSTextView 在 isEditable=true 时，cmd+click 带 .link attribute 的文本会调到这里。
    /// 显式用 NSWorkspace 打开，确保统一行为；返回 true 表示我们已处理。
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        if let url = link as? URL {
            NSWorkspace.shared.open(url)
            return true
        }
        if let s = link as? String, let url = URL(string: s) {
            NSWorkspace.shared.open(url)
            return true
        }
        return false
    }
}
