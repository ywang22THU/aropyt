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

    enum RenderState: Equatable {
        case idle
        case rendering(completed: Int, total: Int)
        case ready
    }

    enum FlushError: LocalizedError {
        case javaScript(String)
        case conversion(String)

        var errorDescription: String? {
            switch self {
            case .javaScript(let message), .conversion(let message):
                return message
            }
        }
    }

    private var webView: WKWebView?
    private var pendingMarkdown: String?
    private(set) var lastSentMarkdown: String?
    private var isReady = false
    private(set) var renderState: RenderState = .idle
    private(set) var isDirty = false
    private(set) var isFlushing = false
    private var renderGeneration = 0
    private var hasCommittedDocument = false
    private(set) var navigationDidFinish = false
    private(set) var lastNavigationErrorDescription: String?
    private var activeFlushRequestID: String?
    private var flushCompletions: [(Result<String?, Error>) -> Void] = []
    private var pendingViewportSourceOffset: Int?

    /// 用户在预览中编辑触发的 markdown 更新回调
    var onMarkdownEdited: ((String) -> Void)?
    var onDirtyStateChanged: ((Bool) -> Void)?

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        let userContent = WKUserContentController()
        for name in ["markdownChanged", "openLink", "previewReady", "previewDirty",
                     "previewFlushResult", "previewState"] {
            userContent.add(WeakScriptMessageHandler(delegate: self), name: name)
        }
        config.userContentController = userContent
        config.setURLSchemeHandler(
            PreviewResourceSchemeHandler(resourceDirectory: Self.resourceBaseURL()),
            forURLScheme: PreviewResourceSchemeHandler.scheme
        )

        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 1100, height: 720),
                           configuration: config)
        wv.autoresizingMask = [.width, .height]
        wv.navigationDelegate = self
        wv.setValue(false, forKey: "drawsBackground") // 让系统背景透出
        self.webView = wv
        self.view = wv

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(autoSavePreferencesDidChange(_:)),
            name: AutoSavePreferences.didChangeNotification,
            object: AutoSavePreferences.shared
        )

        if let pending = pendingMarkdown {
            pendingMarkdown = nil
            renderInternal(markdown: pending)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if let webView {
            for name in ["markdownChanged", "openLink", "previewReady", "previewDirty",
                         "previewFlushResult", "previewState"] {
                webView.configuration.userContentController.removeScriptMessageHandler(forName: name)
            }
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
        renderGeneration &+= 1
        let generation = renderGeneration
        isReady = false
        renderState = .idle
        setDirty(false)
        lastSentMarkdown = markdown
        let isLongDocument = LongDocumentPolicy.isLongDocument(markdown)
        let configuration = PreviewRenderConfiguration(
            isLongDocument: isLongDocument,
            generation: generation,
            progressText: L10n.tr("preview.render.progress", "Rendering preview… %d of %d blocks"),
            completeText: L10n.tr("preview.render.complete", "Preview complete"),
            convertingText: L10n.tr("preview.render.converting", "Converting preview edits…"),
            autoSaveWarningText: L10n.tr(
                "preview.autosave.on_change_warning",
                "On Change is active. Preview edits to this long document require repeated full-document conversion."
            ),
            showsAutoSaveWarning: AutoSavePreferences.shared.mode == .onChange
        )
        let html = MarkdownRenderer.htmlDocument(for: markdown, configuration: configuration)
        let baseURL = PreviewResourceSchemeHandler.baseURL
        let loadHTML = { [weak self, weak wv] in
            guard let self, let wv, generation == self.renderGeneration else { return }
            self.hasCommittedDocument = false
            self.navigationDidFinish = false
            self.lastNavigationErrorDescription = nil
            wv.loadHTMLString(html, baseURL: baseURL)
        }
        guard hasCommittedDocument else {
            loadHTML()
            return
        }
        wv.evaluateJavaScript(
            "window.aropytCancelRender && window.aropytCancelRender(\(generation))"
        ) { _, _ in
            loadHTML()
        }
    }

    /// SwiftPM resource bundles can be laid out differently between `swift run`
    /// and a manually assembled `.app`. Use the first directory that actually
    /// contains the JS/CSS files required by MarkdownRenderer.
    private static func resourceBaseURL() -> URL {
        let resourceBundleName = "AropytEditor_AropytEditor.bundle"

        let mainBundleCandidates = [
            Bundle.main.resourceURL?.appendingPathComponent(resourceBundleName),
            Bundle.main.bundleURL.appendingPathComponent(resourceBundleName),
        ].compactMap { $0 }

        if let url = firstUsableResourceDirectory(in: mainBundleCandidates) {
            return url
        }

        let swiftPMBundle = Bundle.module
        let swiftPMCandidates = [
            swiftPMBundle.resourceURL,
            swiftPMBundle.bundleURL,
        ].compactMap { $0 }

        return firstUsableResourceDirectory(in: swiftPMCandidates)
            ?? swiftPMBundle.resourceURL
            ?? swiftPMBundle.bundleURL
    }

    private static func firstUsableResourceDirectory(in candidates: [URL]) -> URL? {
        let fileManager = FileManager.default
        for candidate in candidates {
            let directMarker = candidate.appendingPathComponent("marked.umd.js")
            if fileManager.fileExists(atPath: directMarker.path) {
                return candidate
            }

            let nestedResources = candidate.appendingPathComponent("Contents/Resources")
            let nestedMarker = nestedResources.appendingPathComponent("marked.umd.js")
            if fileManager.fileExists(atPath: nestedMarker.path) {
                return nestedResources
            }
        }
        return nil
    }

    /// 应用一个格式化命令（由 toolbar / 菜单调用）。
    /// 命令名见 MarkdownRenderer 内 `aropytApplyFormat` 的 switch。
    func applyFormat(_ command: String) {
        guard let wv = self.webView, isReady else { return }
        let escaped = command.replacingOccurrences(of: "'", with: "\\'")
        wv.evaluateJavaScript("window.aropytApplyFormat && window.aropytApplyFormat('\(escaped)')",
                              completionHandler: nil)
    }

    /// Reads the UTF-16 Markdown offset aligned with the top of the preview
    /// viewport. The page derives it from source ranges attached to rendered
    /// top-level blocks.
    func viewportSourceOffset(completion: @escaping (Int?) -> Void) {
        guard let webView else {
            completion(nil)
            return
        }
        webView.evaluateJavaScript(
            "window.aropytViewportSourceOffset ? window.aropytViewportSourceOffset() : null"
        ) { value, error in
            guard error == nil, let number = value as? NSNumber else {
                completion(nil)
                return
            }
            completion(number.intValue)
        }
    }

    /// Restores a UTF-16 Markdown viewport offset. Requests made while a new
    /// preview is rendering are retained and applied as soon as previewReady is
    /// received, preventing the initial load from resetting the position.
    func scrollToSourceOffset(_ offset: Int) {
        pendingViewportSourceOffset = max(0, offset)
        applyPendingViewportSourceOffsetIfPossible()
    }

    private func applyPendingViewportSourceOffsetIfPossible() {
        guard isReady, let webView, let offset = pendingViewportSourceOffset else { return }
        webView.evaluateJavaScript(
            "window.aropytScrollToSourceOffset && window.aropytScrollToSourceOffset(\(offset))"
        ) { [weak self] _, error in
            guard let self, error == nil, self.pendingViewportSourceOffset == offset else { return }
            self.pendingViewportSourceOffset = nil
        }
    }

    /// Converts pending DOM edits back to Markdown. Concurrent callers share one
    /// conversion so mode switches and overlapping save requests cannot race.
    func flushPreviewEdits(completion: @escaping (Result<String?, Error>) -> Void) {
        guard isDirty else {
            completion(.success(nil))
            return
        }
        flushCompletions.append(completion)
        guard !isFlushing else { return }
        guard let webView else {
            finishFlush(.failure(FlushError.javaScript("Preview WebView is unavailable")))
            return
        }

        isFlushing = true
        let requestID = UUID().uuidString
        activeFlushRequestID = requestID
        let literal = Self.javaScriptStringLiteral(requestID)
        webView.evaluateJavaScript("window.aropytFlushPreviewEdits && window.aropytFlushPreviewEdits(\(literal))") {
            [weak self] _, error in
            guard let self, let error, self.activeFlushRequestID == requestID else { return }
            self.showLocalizedFlushError(reason: error.localizedDescription)
            self.finishFlush(.failure(FlushError.javaScript(error.localizedDescription)))
        }
    }

    private func finishFlush(_ result: Result<String?, Error>) {
        activeFlushRequestID = nil
        isFlushing = false
        if case .success = result {
            setDirty(false)
        }
        let completions = flushCompletions
        flushCompletions.removeAll()
        completions.forEach { $0(result) }
    }

    private func setDirty(_ dirty: Bool) {
        guard isDirty != dirty else { return }
        isDirty = dirty
        onDirtyStateChanged?(dirty)
    }

    private func showLocalizedFlushError(reason: String?) {
        let message: String
        if let reason, !reason.isEmpty {
            message = L10n.tr(
                "preview.flush.error_with_reason",
                "Could not convert Preview edits back to Markdown: %@. Your edits remain in Preview and the older Markdown was not saved.",
                reason
            )
        } else {
            message = L10n.tr(
                "preview.flush.error",
                "Could not convert Preview edits back to Markdown. Your edits remain in Preview and the older Markdown was not saved."
            )
        }
        let literal = Self.javaScriptStringLiteral(message)
        webView?.evaluateJavaScript("window.aropytShowFlushError && window.aropytShowFlushError(\(literal))")
    }

    @objc private func autoSavePreferencesDidChange(_ notification: Notification) {
        let enabled = AutoSavePreferences.shared.mode == .onChange
        let message = L10n.tr(
            "preview.autosave.on_change_warning",
            "On Change is active. Preview edits to this long document require repeated full-document conversion."
        )
        let literal = Self.javaScriptStringLiteral(message)
        webView?.evaluateJavaScript(
            "window.aropytSetAutoSaveWarning && window.aropytSetAutoSaveWarning(\(enabled), \(literal))"
        )
    }

    private static func javaScriptStringLiteral(_ string: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [string], options: [.fragmentsAllowed]))
            ?? Data("[\"\"]".utf8)
        guard var json = String(data: data, encoding: .utf8) else { return "\"\"" }
        if json.hasPrefix("[") { json.removeFirst() }
        if json.hasSuffix("]") { json.removeLast() }
        return json
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        switch message.name {
        case "markdownChanged":
            guard let md = message.body as? String else { return }
            lastSentMarkdown = md
            setDirty(false)
            onMarkdownEdited?(md)
        case "openLink":
            guard let s = message.body as? String,
                  let url = URL(string: s) else { return }
            NSWorkspace.shared.open(url)
        case "previewReady":
            if let body = message.body as? [String: Any],
               let generation = body["generation"] as? Int,
               generation != renderGeneration {
                return
            }
            isReady = true
            renderState = .ready
            applyPendingViewportSourceOffsetIfPossible()
        case "previewDirty":
            guard let dirty = message.body as? Bool else { return }
            setDirty(dirty)
        case "previewState":
            guard
                let body = message.body as? [String: Any],
                let generation = body["generation"] as? Int,
                generation == renderGeneration,
                let phase = body["phase"] as? String
            else { return }
            if phase == "complete" {
                renderState = .ready
            } else {
                renderState = .rendering(
                    completed: body["completed"] as? Int ?? 0,
                    total: body["total"] as? Int ?? 0
                )
            }
        case "previewFlushResult":
            guard
                let body = message.body as? [String: Any],
                let requestID = body["requestID"] as? String,
                requestID == activeFlushRequestID,
                let success = body["success"] as? Bool
            else { return }
            if success {
                let markdown = body["markdown"] as? String
                if let markdown { lastSentMarkdown = markdown }
                finishFlush(.success(markdown))
            } else {
                let reason = body["error"] as? String ?? ""
                showLocalizedFlushError(reason: reason)
                finishFlush(.failure(FlushError.conversion(reason)))
            }
        default:
            break
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        hasCommittedDocument = true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationDidFinish = true
    }

    func webView(_ webView: WKWebView,
                 didFail navigation: WKNavigation!,
                 withError error: Error) {
        lastNavigationErrorDescription = error.localizedDescription
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        lastNavigationErrorDescription = error.localizedDescription
    }

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

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

private final class PreviewResourceSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "aropyt-resource"
    static let baseURL = URL(string: "\(scheme)://local/")!

    private let resourceDirectory: URL

    init(resourceDirectory: URL) {
        self.resourceDirectory = resourceDirectory.resolvingSymlinksInPath()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url else {
            fail(urlSchemeTask, code: NSURLErrorBadURL)
            return
        }

        let relativePath = requestURL.path.removingPercentEncoding?
            .trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        guard !relativePath.isEmpty, !relativePath.split(separator: "/").contains("..") else {
            fail(urlSchemeTask, code: NSURLErrorBadURL)
            return
        }

        let fileURL = resourceDirectory.appendingPathComponent(relativePath).resolvingSymlinksInPath()
        let rootPath = resourceDirectory.path.hasSuffix("/")
            ? resourceDirectory.path
            : resourceDirectory.path + "/"
        guard fileURL.path.hasPrefix(rootPath) else {
            fail(urlSchemeTask, code: NSURLErrorNoPermissionsToReadFile)
            return
        }

        do {
            let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            let response = URLResponse(
                url: requestURL,
                mimeType: Self.mimeType(for: fileURL.pathExtension),
                expectedContentLength: data.count,
                textEncodingName: Self.textEncoding(for: fileURL.pathExtension)
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func fail(_ task: WKURLSchemeTask, code: Int) {
        task.didFailWithError(NSError(domain: NSURLErrorDomain, code: code))
    }

    private static func mimeType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "js": return "text/javascript"
        case "css": return "text/css"
        case "woff2": return "font/woff2"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        default: return "application/octet-stream"
        }
    }

    private static func textEncoding(for pathExtension: String) -> String? {
        switch pathExtension.lowercased() {
        case "js", "css", "svg": return "utf-8"
        default: return nil
        }
    }
}
