import Foundation

/// 纯 Swift 的 Markdown HTML 模板生成器。
///
/// 这里只负责把 markdown 字符串嵌入到一个 HTML 文档里，由 WebView 中的 marked.js
/// 真正解析。这样做的好处是渲染规则与 GFM 完全一致，且离线可用。
///
/// 预览模式同时是可编辑的：`<article>` 设了 `contenteditable=true`，
/// 内嵌脚本会监听 `input` 事件，用 turndown.js 把 HTML 反向转回 markdown，
/// 再通过 `window.webkit.messageHandlers.markdownChanged` 回传 Swift 端。
public enum MarkdownRenderer {

    /// 生成完整 HTML 文档。WebView 应使用 baseURL 指向 Resources 目录，
    /// 这样 `marked.umd.js` / `highlight.min.js` / 等资源的相对路径才能解析。
    public static func htmlDocument(for markdown: String) -> String {
        let payload = jsStringLiteral(markdown)
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>Preview</title>
            <link rel="stylesheet" href="github-markdown.css">
            <link rel="stylesheet" href="github.min.css" media="(prefers-color-scheme: light)">
            <link rel="stylesheet" href="github-dark.min.css" media="(prefers-color-scheme: dark)">
            <style>
                :root { color-scheme: light dark; }
                body {
                    margin: 0;
                    padding: 24px 36px 64px 36px;
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
                    background: #ffffff;
                    color: #1f2328;
                }
                @media (prefers-color-scheme: dark) {
                    body { background: #0d1117; color: #e6edf3; }
                }
                .markdown-body {
                    box-sizing: border-box;
                    max-width: 920px;
                    margin: 0 auto;
                    background: transparent;
                    color: inherit;
                    outline: none;
                    caret-color: auto;
                }
                .markdown-body:focus { outline: none; }
                .markdown-body img { max-width: 100%; }

                /* 代码块容器 */
                .markdown-body pre {
                    background: #f6f8fa;
                    border-radius: 6px;
                    padding: 0;
                    overflow: auto;
                }
                .markdown-body pre code,
                .markdown-body pre code.hljs {
                    display: block;
                    padding: 14px 16px;
                    background: transparent;
                    color: #1f2328;
                    font-size: 13px;
                    line-height: 1.5;
                    border-radius: 6px;
                }
                /* 行内 code */
                .markdown-body code:not(pre code) {
                    background: rgba(175,184,193,0.2);
                    color: inherit;
                    padding: 2px 6px;
                    border-radius: 4px;
                    font-size: 0.9em;
                }
                /* contenteditable 下，链接默认无法点击；视觉上提示 cmd+click */
                .markdown-body a { cursor: pointer; }
                @media (prefers-color-scheme: dark) {
                    .markdown-body pre {
                        background: #161b22;
                    }
                    .markdown-body pre code,
                    .markdown-body pre code.hljs {
                        color: #e6edf3;
                    }
                    .markdown-body code:not(pre code) {
                        background: rgba(110,118,129,0.4);
                    }
                }
            </style>
            <script src="marked.umd.js"></script>
            <script src="highlight.min.js"></script>
            <script src="turndown.js"></script>
            <script src="turndown-plugin-gfm.js"></script>
        </head>
        <body>
            <article id="content" class="markdown-body" contenteditable="true" spellcheck="false" tabindex="0" autofocus></article>
            <script>
                (function() {
                    var raw = \(payload);
                    var content = document.getElementById('content');

                    // ---------- marked: markdown -> HTML ----------
                    if (window.marked) {
                        marked.setOptions({
                            gfm: true,
                            breaks: false,
                            headerIds: true,
                            mangle: false
                        });
                        content.innerHTML = marked.parse(raw);
                    } else {
                        content.textContent = raw;
                    }
                    if (window.hljs) {
                        document.querySelectorAll('pre code').forEach(function(el) {
                            try { hljs.highlightElement(el); } catch (e) {}
                        });
                    }

                    // ---------- turndown: HTML -> markdown ----------
                    var turndownService = null;
                    if (window.TurndownService) {
                        turndownService = new TurndownService({
                            headingStyle: 'atx',
                            codeBlockStyle: 'fenced',
                            bulletListMarker: '-',
                            emDelimiter: '*',
                            strongDelimiter: '**'
                        });
                        if (window.turndownPluginGfm) {
                            turndownService.use(window.turndownPluginGfm.gfm);
                        }
                        // 让 highlight.js 的 <span class="hljs-..."> 不污染输出
                        turndownService.addRule('hljsCode', {
                            filter: function(node) {
                                return node.nodeName === 'PRE' && node.firstChild && node.firstChild.nodeName === 'CODE';
                            },
                            replacement: function(_, node) {
                                var code = node.firstChild;
                                var lang = '';
                                var cls = code.getAttribute('class') || '';
                                var m = cls.match(/language-(\\S+)/);
                                if (m) lang = m[1];
                                var text = code.innerText || code.textContent || '';
                                if (text.endsWith('\\n')) text = text.slice(0, -1);
                                return '\\n\\n```' + lang + '\\n' + text + '\\n```\\n\\n';
                            }
                        });
                    }

                    // ---------- 通知 Swift 端 markdown 变化 ----------
                    var inputDebounceId = null;
                    function postMarkdown() {
                        if (!turndownService) return;
                        try {
                            var md = turndownService.turndown(content.innerHTML);
                            if (window.webkit && window.webkit.messageHandlers
                                && window.webkit.messageHandlers.markdownChanged) {
                                window.webkit.messageHandlers.markdownChanged.postMessage(md);
                            }
                        } catch (e) {
                            console.error('turndown failed:', e);
                        }
                    }
                    content.addEventListener('input', function() {
                        if (inputDebounceId) clearTimeout(inputDebounceId);
                        inputDebounceId = setTimeout(postMarkdown, 150);
                    });

                    // ---------- Cmd+Click 链接 ----------
                    // 注意：用捕获阶段（第三参数 true），抢在 contenteditable 默认行为之前处理。
                    // 同时挂 mousedown 和 click 双保险。
                    function findLinkFrom(target) {
                        if (!target) return null;
                        if (target.closest) return target.closest('a');
                        var n = target;
                        while (n && n.nodeName !== 'A') n = n.parentNode;
                        return (n && n.nodeName === 'A') ? n : null;
                    }
                    // 把可能没有 scheme 的 href 规范化为可打开的 URL。
                    // markdown 里常写 `[x](www.foo.com)` —— 没 scheme 时直接 new URL
                    // 会被当成相对路径拼到 baseURI（file://...bundle/）上，无法打开。
                    function normalizeHref(href) {
                        if (!href) return null;
                        // 已有 scheme（http: / https: / mailto: / tel: / file: 等）
                        if (/^[a-z][a-z0-9+\\-.]*:/i.test(href)) return href;
                        // 页内锚点
                        if (href.charAt(0) === '#') return null;
                        // 看起来像域名 / 协议相对，统一补 https://
                        if (href.indexOf('//') === 0) return 'https:' + href;
                        return 'https://' + href;
                    }
                    function handleLinkEvent(e) {
                        var a = findLinkFrom(e.target);
                        if (!a) return;
                        if (e.metaKey) {
                            e.preventDefault();
                            e.stopPropagation();
                            var abs = normalizeHref(a.getAttribute('href'));
                            if (!abs) return;
                            if (window.webkit && window.webkit.messageHandlers
                                && window.webkit.messageHandlers.openLink) {
                                window.webkit.messageHandlers.openLink.postMessage(abs);
                            }
                        } else if (e.type === 'click') {
                            // contenteditable 下普通点击挡住默认跳转
                            e.preventDefault();
                        }
                    }
                    // 同时挂在 document 和 content 上，capture 阶段抢在 WebKit 内部之前
                    document.addEventListener('mousedown', handleLinkEvent, true);
                    document.addEventListener('click', handleLinkEvent, true);
                    content.addEventListener('mousedown', handleLinkEvent, true);
                    content.addEventListener('click', handleLinkEvent, true);
                    content.addEventListener('auxclick', handleLinkEvent, true);

                    // ---------- 暴露给 Swift 调用的格式化命令 ----------
                    // Swift 通过 evaluateJavaScript("window.aropytApplyFormat('bold')") 调用
                    window.aropytApplyFormat = function(cmd, arg) {
                        content.focus();
                        switch (cmd) {
                            case 'bold':
                            case 'italic':
                            case 'strikethrough':
                                document.execCommand(cmd, false, null);
                                break;
                            case 'h1':
                            case 'h2':
                            case 'h3':
                                document.execCommand('formatBlock', false, cmd.toUpperCase());
                                break;
                            case 'paragraph':
                                document.execCommand('formatBlock', false, 'P');
                                break;
                            case 'blockquote':
                                document.execCommand('formatBlock', false, 'BLOCKQUOTE');
                                break;
                            case 'ul':
                                document.execCommand('insertUnorderedList', false, null);
                                break;
                            case 'ol':
                                document.execCommand('insertOrderedList', false, null);
                                break;
                            case 'code':
                                // 行内 code：包一个 <code>
                                wrapSelection('code');
                                break;
                            case 'codeblock':
                                document.execCommand('formatBlock', false, 'PRE');
                                break;
                            default:
                                break;
                        }
                        // 触发一次 input 让 Swift 收到更新
                        content.dispatchEvent(new Event('input', { bubbles: true }));
                    };

                    function wrapSelection(tagName) {
                        var sel = window.getSelection();
                        if (!sel || sel.rangeCount === 0) return;
                        var range = sel.getRangeAt(0);
                        if (range.collapsed) return;
                        var el = document.createElement(tagName);
                        try {
                            range.surroundContents(el);
                        } catch (e) {
                            // 跨节点选择 fallback
                            el.appendChild(range.extractContents());
                            range.insertNode(el);
                        }
                        sel.removeAllRanges();
                        sel.addRange(range);
                    }

                    // 通知 Swift 已就绪
                    if (window.webkit && window.webkit.messageHandlers
                        && window.webkit.messageHandlers.previewReady) {
                        window.webkit.messageHandlers.previewReady.postMessage('ready');
                    }
                })();
            </script>
        </body>
        </html>
        """
    }

    /// 把任意字符串安全地序列化为一个 JavaScript 字符串字面量。
    /// 直接拼字符串太脆弱（反斜杠/引号/换行/U+2028 都会出问题），用 JSON 编码最稳。
    private static func jsStringLiteral(_ s: String) -> String {
        // JSONSerialization 不支持顶层字符串（早期版本），所以包成数组再切片。
        let data = (try? JSONSerialization.data(
            withJSONObject: [s],
            options: [.fragmentsAllowed]
        )) ?? Data("[\"\"]".utf8)
        guard let json = String(data: data, encoding: .utf8) else { return "\"\"" }
        // json 形如 ["..."]，去掉两端的方括号即得字符串字面量
        var trimmed = json
        if trimmed.hasPrefix("[") { trimmed.removeFirst() }
        if trimmed.hasSuffix("]") { trimmed.removeLast() }
        return trimmed
    }
}
