import AppKit
import WebKit
import MarkdownCore

/// 预览模式：WKWebView 渲染 + 可编辑（contenteditable）+ 格式化命令。
///
/// 数据流：
///   document.text  --(load)-->  WebView innerHTML
///   WebView 编辑  --(turndown JS)-->  markdownChanged 消息  --> onMarkdownEdited 回调
///
/// 防循环：`lastSentMarkdown` 记录最近一次从 WebView 收到的 markdown，
/// 当外部（document）回填的内容和它一致时跳过 reload，避免打乱光标。
final class PreviewViewController: NSViewController, WKNavigationDelegate, WKScriptMessageHandler {

    private var webView: WKWebView?
    private var pendingMarkdown: String?
    private(set) var lastSentMarkdown: String?
    private var isReady = false

    /// 用户在预览中编辑触发的 markdown 更新回调
    var onMarkdownEdited: ((String) -> Void)?

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        let userContent = WKUserContentController()
        userContent.add(self, name: "markdownChanged")
        userContent.add(self, name: "openLink")
        userContent.add(self, name: "previewReady")
        config.userContentController = userContent

        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 1100, height: 720),
                           configuration: config)
        wv.autoresizingMask = [.width, .height]
        wv.navigationDelegate = self
        wv.setValue(false, forKey: "drawsBackground") // 让系统背景透出
        self.webView = wv
        self.view = wv

        if let pending = pendingMarkdown {
            pendingMarkdown = nil
            renderInternal(markdown: pending)
        }
    }

    /// 公开入口：渲染指定的 markdown。
    /// 如果 markdown 与 lastSentMarkdown 完全一致（说明这是从预览编辑回流回来的），
    /// 则跳过 reload 避免打乱光标。
    func load(markdown: String) {
        // 触发 loadView（如果尚未加载）
        _ = self.view
        guard self.webView != nil else {
            pendingMarkdown = markdown
            return
        }
        if let last = lastSentMarkdown, last == markdown {
            return
        }
        renderInternal(markdown: markdown)
    }

    private func renderInternal(markdown: String) {
        guard let wv = self.webView else { return }
        isReady = false
        lastSentMarkdown = markdown
        let html = MarkdownRenderer.htmlDocument(for: markdown)
        let baseURL = Bundle.module.resourceURL ?? Bundle.module.bundleURL
        wv.loadHTMLString(html, baseURL: baseURL)
    }

    /// 应用一个格式化命令（由 toolbar / 菜单调用）。
    /// 命令名见 MarkdownRenderer 内 `aropytApplyFormat` 的 switch。
    func applyFormat(_ command: String) {
        guard let wv = self.webView, isReady else { return }
        let escaped = command.replacingOccurrences(of: "'", with: "\\'")
        wv.evaluateJavaScript("window.aropytApplyFormat && window.aropytApplyFormat('\(escaped)')",
                              completionHandler: nil)
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        switch message.name {
        case "markdownChanged":
            guard let md = message.body as? String else { return }
            lastSentMarkdown = md
            onMarkdownEdited?(md)
        case "openLink":
            guard let s = message.body as? String,
                  let url = URL(string: s) else { return }
            NSWorkspace.shared.open(url)
        case "previewReady":
            isReady = true
        default:
            break
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // contenteditable 下点击链接默认不会触发 navigation，但保险起见拦截一下
        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}
