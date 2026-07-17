import Foundation

public struct PreviewRenderConfiguration: Sendable {
    public var isLongDocument: Bool
    public var generation: Int
    public var progressText: String
    public var completeText: String
    public var convertingText: String
    public var autoSaveWarningText: String
    public var showsAutoSaveWarning: Bool

    public init(isLongDocument: Bool,
                generation: Int = 1,
                progressText: String = "Rendering preview… %d of %d blocks",
                completeText: String = "Preview complete",
                convertingText: String = "Converting preview edits…",
                autoSaveWarningText: String = "On Change is active. Preview edits to this long document require repeated full-document conversion.",
                showsAutoSaveWarning: Bool = false) {
        self.isLongDocument = isLongDocument
        self.generation = generation
        self.progressText = progressText
        self.completeText = completeText
        self.convertingText = convertingText
        self.autoSaveWarningText = autoSaveWarningText
        self.showsAutoSaveWarning = showsAutoSaveWarning
    }
}

/// 纯 Swift 的 Markdown HTML 模板生成器。
///
/// 这里只负责把 markdown 字符串嵌入到一个 HTML 文档里，由 WebView 中的 marked.js
/// 真正解析，并用 KaTeX / Mermaid 渲染公式和图表。这样做的好处是渲染规则与 GFM
/// 完全一致，且离线可用。
///
/// 预览模式同时是可编辑的：`<article>` 设了 `contenteditable=true`，
/// 内嵌脚本会监听 `input` 事件，用 turndown.js 把 HTML 反向转回 markdown，
/// 再通过 `window.webkit.messageHandlers.markdownChanged` 回传 Swift 端。
public enum MarkdownRenderer {

    /// 生成完整 HTML 文档。WebView 应使用 baseURL 指向 Resources 目录，
    /// 这样 `marked.umd.js` / `highlight.min.js` / `mermaid.min.js` 等资源的相对路径
    /// 才能解析。
    public static func htmlDocument(for markdown: String) -> String {
        htmlDocument(
            for: markdown,
            configuration: PreviewRenderConfiguration(
                isLongDocument: LongDocumentPolicy.isLongDocument(markdown)
            )
        )
    }

    public static func htmlDocument(for markdown: String,
                                    configuration: PreviewRenderConfiguration) -> String {
        let payload = jsStringLiteral(markdown)
        let progressText = jsStringLiteral(configuration.progressText)
        let completeText = jsStringLiteral(configuration.completeText)
        let convertingText = jsStringLiteral(configuration.convertingText)
        let autoSaveWarningText = jsStringLiteral(configuration.autoSaveWarningText)
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
            <link rel="stylesheet" href="katex.min.css">
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
                .markdown-body .katex {
                    font-size: 1.06em;
                }
                .markdown-body .katex-display {
                    overflow-x: auto;
                    overflow-y: hidden;
                    padding: 4px 0;
                }
                .markdown-body .aropyt-math-block {
                    display: block;
                    margin: 1em 0;
                    text-align: center;
                }
                .markdown-body .aropyt-math-block > .katex-display {
                    margin: 0;
                }
                .markdown-body .aropyt-mermaid {
                    display: flex;
                    justify-content: center;
                    margin: 1em 0;
                    padding: 8px 0;
                    overflow-x: auto;
                }
                .markdown-body .aropyt-mermaid svg {
                    max-width: 100%;
                    height: auto;
                }
                #preview-status {
                    box-sizing: border-box;
                    max-width: 920px;
                    margin: 0 auto 14px auto;
                    padding: 9px 12px;
                    border: 1px solid rgba(110,118,129,0.35);
                    border-radius: 6px;
                    color: #57606a;
                    background: rgba(175,184,193,0.12);
                    font-size: 12px;
                    line-height: 1.45;
                }
                #preview-status[hidden], #preview-progress[hidden], #preview-warning[hidden] { display: none; }
                #preview-warning { color: #9a6700; }
                #preview-error { color: #cf222e; }
                .aropyt-render-batch { display: contents; }
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
                    #preview-status { color: #8c959f; }
                    #preview-warning { color: #d29922; }
                    #preview-error { color: #ff7b72; }
                }
            </style>
            <script src="marked.umd.js"></script>
            <script src="highlight.min.js"></script>
            <script src="katex.min.js"></script>
            <script src="auto-render.min.js"></script>
            <script src="turndown.js"></script>
            <script src="turndown-plugin-gfm.js"></script>
        </head>
        <body>
            <div id="preview-status" role="status" aria-live="polite" hidden>
                <div id="preview-progress" hidden></div>
                <div id="preview-warning" hidden></div>
                <div id="preview-error" hidden></div>
            </div>
            <article id="content" class="markdown-body" contenteditable="false" spellcheck="false" tabindex="0" autofocus></article>
            <script>
                (function() {
                    var raw = \(payload);
                    var content = document.getElementById('content');
                    var statusArea = document.getElementById('preview-status');
                    var progressLabel = document.getElementById('preview-progress');
                    var warningLabel = document.getElementById('preview-warning');
                    var errorLabel = document.getElementById('preview-error');
                    var isLongDocument = \(configuration.isLongDocument ? "true" : "false");
                    var renderGeneration = \(configuration.generation);
                    var progressText = \(progressText);
                    var completeText = \(completeText);
                    var convertingText = \(convertingText);
                    var autoSaveWarningText = \(autoSaveWarningText);
                    var showsAutoSaveWarning = \(configuration.showsAutoSaveWarning ? "true" : "false");
                    var renderCancelled = false;
                    var renderComplete = false;
                    var protectedMathSegments = [];

                    window.__aropytRenderGeneration = renderGeneration;

                    function isCurrentRender() {
                        return !renderCancelled
                            && window.__aropytRenderGeneration === renderGeneration;
                    }

                    function updateStatusVisibility() {
                        statusArea.hidden = progressLabel.hidden
                            && warningLabel.hidden
                            && errorLabel.hidden;
                    }

                    function formatProgress(completed, total) {
                        return progressText.replace('%d', String(completed)).replace('%d', String(total));
                    }

                    function setProgress(message) {
                        progressLabel.textContent = message || '';
                        progressLabel.hidden = !message;
                        updateStatusVisibility();
                    }

                    function setError(message) {
                        errorLabel.textContent = message || '';
                        errorLabel.hidden = !message;
                        updateStatusVisibility();
                    }
                    window.aropytShowFlushError = setError;

                    window.aropytSetAutoSaveWarning = function(show, message) {
                        showsAutoSaveWarning = !!show;
                        if (message) autoSaveWarningText = message;
                        warningLabel.textContent = autoSaveWarningText;
                        warningLabel.hidden = !(isLongDocument && showsAutoSaveWarning);
                        updateStatusVisibility();
                    };
                    window.aropytSetAutoSaveWarning(showsAutoSaveWarning, autoSaveWarningText);

                    function mathKey(index) {
                        return 'AROPYTMATHSEGMENT' + index + 'END';
                    }

                    function stashMath(segment, display, sourceStart, protectedStart) {
                        var key = mathKey(protectedMathSegments.length);
                        protectedMathSegments.push({
                            segment: segment,
                            display: display,
                            sourceStart: sourceStart,
                            sourceEnd: sourceStart + segment.length,
                            protectedStart: protectedStart,
                            protectedEnd: protectedStart + key.length
                        });
                        return key;
                    }

                    function findBackslashDelimitedEnd(markdown, start, closeChar) {
                        for (var i = start; i < markdown.length - 1; i++) {
                            if (markdown.charCodeAt(i) === 92 && markdown.charAt(i + 1) === closeChar) {
                                return i + 2;
                            }
                        }
                        return -1;
                    }

                    function findInlineDollarEnd(markdown, start) {
                        for (var i = start; i < markdown.length; i++) {
                            var ch = markdown.charAt(i);
                            if (ch === '\\n') return -1;
                            if (ch === '$' && markdown.charAt(i - 1) !== '\\\\') {
                                return i + 1;
                            }
                        }
                        return -1;
                    }

                    function protectMathSegments(markdown) {
                        protectedMathSegments = [];
                        var output = '';
                        var i = 0;
                        while (i < markdown.length) {
                            if (markdown.startsWith('$$', i)) {
                                var displayDollarEnd = markdown.indexOf('$$', i + 2);
                                if (displayDollarEnd !== -1) {
                                    output += stashMath(
                                        markdown.slice(i, displayDollarEnd + 2),
                                        true,
                                        i,
                                        output.length
                                    );
                                    i = displayDollarEnd + 2;
                                    continue;
                                }
                            }

                            if (markdown.charCodeAt(i) === 92 && markdown.charAt(i + 1) === '[') {
                                var displayBracketEnd = findBackslashDelimitedEnd(markdown, i + 2, ']');
                                if (displayBracketEnd !== -1) {
                                    output += stashMath(
                                        markdown.slice(i, displayBracketEnd),
                                        true,
                                        i,
                                        output.length
                                    );
                                    i = displayBracketEnd;
                                    continue;
                                }
                            }

                            if (markdown.charCodeAt(i) === 92 && markdown.charAt(i + 1) === '(') {
                                var inlineParenEnd = findBackslashDelimitedEnd(markdown, i + 2, ')');
                                if (inlineParenEnd !== -1) {
                                    output += stashMath(
                                        markdown.slice(i, inlineParenEnd),
                                        false,
                                        i,
                                        output.length
                                    );
                                    i = inlineParenEnd;
                                    continue;
                                }
                            }

                            if (markdown.charAt(i) === '$'
                                && markdown.charAt(i + 1) !== '$'
                                && markdown.charAt(i - 1) !== '\\\\'
                                && markdown.charAt(i + 1) !== ' ') {
                                var inlineDollarEnd = findInlineDollarEnd(markdown, i + 1);
                                if (inlineDollarEnd !== -1 && markdown.charAt(inlineDollarEnd - 2) !== ' ') {
                                    output += stashMath(
                                        markdown.slice(i, inlineDollarEnd),
                                        false,
                                        i,
                                        output.length
                                    );
                                    i = inlineDollarEnd;
                                    continue;
                                }
                            }

                            output += markdown.charAt(i);
                            i += 1;
                        }
                        return output;
                    }

                    function originalOffsetForProtectedOffset(offset) {
                        var delta = 0;
                        for (var i = 0; i < protectedMathSegments.length; i++) {
                            var record = protectedMathSegments[i];
                            if (offset < record.protectedStart) return offset + delta;
                            if (offset <= record.protectedEnd) {
                                var protectedLength = record.protectedEnd - record.protectedStart;
                                var sourceLength = record.sourceEnd - record.sourceStart;
                                if (protectedLength <= 0) return record.sourceStart;
                                var fraction = (offset - record.protectedStart) / protectedLength;
                                return Math.round(record.sourceStart + sourceLength * fraction);
                            }
                            delta += (record.sourceEnd - record.sourceStart)
                                - (record.protectedEnd - record.protectedStart);
                        }
                        return offset + delta;
                    }

                    function escapeHtmlText(value) {
                        return value.replace(/[&<>]/g, function(ch) {
                            if (ch === '&') return '&amp;';
                            if (ch === '<') return '&lt;';
                            return '&gt;';
                        });
                    }

                    function restoreMathSegments(html) {
                        var restored = html;
                        var indexes = {};
                        var match;
                        var keyPattern = /AROPYTMATHSEGMENT(\\d+)END/g;
                        while ((match = keyPattern.exec(html)) !== null) {
                            indexes[match[1]] = true;
                        }
                        Object.keys(indexes).forEach(function(indexText) {
                            var index = Number(indexText);
                            var record = protectedMathSegments[index];
                            if (!record) return;
                            var key = mathKey(index);
                            var mathHtml = escapeHtmlText(record.segment);
                            if (record.display) {
                                var blockHtml = '<div class="aropyt-math-block">' + mathHtml + '</div>';
                                restored = restored.replaceAll('<p>' + key + '</p>', blockHtml);
                                restored = restored.replaceAll(key, blockHtml);
                            } else {
                                restored = restored.replaceAll(key, mathHtml);
                            }
                        });
                        return restored;
                    }

                    function renderMath(root) {
                        if (!window.renderMathInElement) return;
                        try {
                            renderMathInElement(root, {
                                delimiters: [
                                    { left: '$$', right: '$$', display: true },
                                    { left: '\\\\[', right: '\\\\]', display: true },
                                    { left: '\\\\(', right: '\\\\)', display: false },
                                    { left: '$', right: '$', display: false }
                                ],
                                throwOnError: false,
                                strict: 'ignore',
                                ignoredTags: [
                                    'script',
                                    'noscript',
                                    'style',
                                    'textarea',
                                    'pre',
                                    'code',
                                    'option'
                                ]
                            });
                        } catch (e) {
                            console.error('math render failed:', e);
                        }
                    }

                    var mermaidObserver = null;
                    var mermaidLoadPromise = null;

                    function renderMermaid(diagrams) {
                        if (!isCurrentRender() || diagrams.length === 0 || !window.mermaid) return;

                        try {
                            var isDark = window.matchMedia
                                && window.matchMedia('(prefers-color-scheme: dark)').matches;
                            mermaid.initialize({
                                startOnLoad: false,
                                securityLevel: 'strict',
                                theme: isDark ? 'dark' : 'default'
                            });
                            var result = mermaid.run({
                                nodes: diagrams,
                                suppressErrors: true
                            });
                            if (result && typeof result.catch === 'function') {
                                result.catch(function(error) {
                                    console.error('mermaid render failed:', error);
                                });
                            }
                        } catch (e) {
                            console.error('mermaid render failed:', e);
                        }
                    }

                    function ensureMermaidLoaded() {
                        if (window.mermaid) return Promise.resolve();
                        if (mermaidLoadPromise) return mermaidLoadPromise;
                        mermaidLoadPromise = new Promise(function(resolve, reject) {
                            var script = document.createElement('script');
                            script.src = 'mermaid.min.js';
                            script.async = true;
                            script.onload = resolve;
                            script.onerror = function() {
                                reject(new Error('mermaid failed to load'));
                            };
                            document.head.appendChild(script);
                        });
                        return mermaidLoadPromise;
                    }

                    function renderVisibleMermaid(diagrams) {
                        if (!isCurrentRender() || diagrams.length === 0) return;
                        ensureMermaidLoaded().then(function() {
                            if (isCurrentRender()) renderMermaid(diagrams);
                        }).catch(function(error) {
                            console.error(error);
                        });
                    }

                    if ('IntersectionObserver' in window) {
                        mermaidObserver = new IntersectionObserver(function(entries) {
                            var visible = [];
                            entries.forEach(function(entry) {
                                if (!entry.isIntersecting) return;
                                mermaidObserver.unobserve(entry.target);
                                visible.push(entry.target);
                            });
                            renderVisibleMermaid(visible);
                        }, { root: null, rootMargin: '480px 0px', threshold: 0.01 });
                    }

                    function prepareMermaidDiagrams(root) {
                        var diagrams = [];
                        root.querySelectorAll('pre code.language-mermaid').forEach(function(code) {
                            var pre = code.parentElement;
                            if (!pre) return;

                            var source = code.textContent || '';
                            if (source.endsWith('\\n')) source = source.slice(0, -1);

                            var diagram = document.createElement('div');
                            diagram.className = 'mermaid aropyt-mermaid';
                            diagram.setAttribute('contenteditable', 'false');
                            diagram.setAttribute('data-mermaid-source', source);
                            ['data-aropyt-source-start', 'data-aropyt-source-end'].forEach(function(name) {
                                var value = pre.getAttribute(name);
                                if (value !== null) diagram.setAttribute(name, value);
                            });
                            diagram.textContent = source;
                            pre.replaceWith(diagram);
                            diagrams.push(diagram);
                            if (mermaidObserver) {
                                mermaidObserver.observe(diagram);
                            }
                        });
                        if (!mermaidObserver) renderVisibleMermaid(diagrams);
                        return diagrams;
                    }

                    // ---------- marked: markdown -> HTML ----------
                    var allTokens = [];
                    var nextTokenIndex = 0;
                    var textEncoder = window.TextEncoder ? new TextEncoder() : null;

                    function tokenByteLength(token) {
                        var tokenRaw = token && token.raw ? token.raw : '';
                        return textEncoder ? textEncoder.encode(tokenRaw).length : tokenRaw.length;
                    }

                    function assignTokenSourceRanges(tokens) {
                        var protectedOffset = 0;
                        tokens.forEach(function(token) {
                            var tokenRaw = token && token.raw ? token.raw : '';
                            token._aropytSourceStart = originalOffsetForProtectedOffset(protectedOffset);
                            protectedOffset += tokenRaw.length;
                            token._aropytSourceEnd = originalOffsetForProtectedOffset(protectedOffset);
                        });
                    }

                    function annotateRenderedBlocks(root, tokens) {
                        var blockTokens = tokens.filter(function(token) {
                            return token && token.type !== 'space' && token.type !== 'def';
                        });
                        var elements = Array.prototype.slice.call(root.children || []);
                        if (blockTokens.length === 0 || elements.length === 0) return;

                        elements.forEach(function(element, index) {
                            var firstTokenIndex = Math.floor(index * blockTokens.length / elements.length);
                            var lastTokenIndex = Math.max(
                                firstTokenIndex,
                                Math.ceil((index + 1) * blockTokens.length / elements.length) - 1
                            );
                            var firstToken = blockTokens[Math.min(firstTokenIndex, blockTokens.length - 1)];
                            var lastToken = blockTokens[Math.min(lastTokenIndex, blockTokens.length - 1)];
                            element.setAttribute(
                                'data-aropyt-source-start',
                                String(firstToken._aropytSourceStart || 0)
                            );
                            element.setAttribute(
                                'data-aropyt-source-end',
                                String(lastToken._aropytSourceEnd || firstToken._aropytSourceStart || 0)
                            );
                        });
                    }

                    function processRenderedRoot(root) {
                        renderMath(root);
                        prepareMermaidDiagrams(root);
                        if (window.hljs) {
                            root.querySelectorAll('pre code').forEach(function(el) {
                                try { hljs.highlightElement(el); } catch (e) {}
                            });
                        }
                    }

                    function appendTokenBatch(tokens) {
                        if (!isCurrentRender() || tokens.length === 0) return;
                        if (allTokens.links) tokens.links = allTokens.links;
                        var wrapper = document.createElement('div');
                        wrapper.className = 'aropyt-render-batch';
                        wrapper.innerHTML = restoreMathSegments(marked.parser(tokens));
                        annotateRenderedBlocks(wrapper, tokens);
                        content.appendChild(wrapper);
                        processRenderedRoot(wrapper);
                    }

                    function takeTokenBatch(maxTokens, maxBytes) {
                        var batch = [];
                        var byteCount = 0;
                        while (nextTokenIndex < allTokens.length && batch.length < maxTokens) {
                            var token = allTokens[nextTokenIndex];
                            var bytes = tokenByteLength(token);
                            if (batch.length > 0 && byteCount + bytes > maxBytes) break;
                            batch.push(token);
                            byteCount += bytes;
                            nextTokenIndex += 1;
                        }
                        return batch;
                    }

                    function postPreviewState(phase, completed, total) {
                        if (!(window.webkit && window.webkit.messageHandlers
                            && window.webkit.messageHandlers.previewState)) return;
                        window.webkit.messageHandlers.previewState.postMessage({
                            phase: phase,
                            completed: completed,
                            total: total,
                            generation: renderGeneration
                        });
                    }

                    function notifyPreviewReady() {
                        if (window.webkit && window.webkit.messageHandlers
                            && window.webkit.messageHandlers.previewReady) {
                            window.webkit.messageHandlers.previewReady.postMessage({
                                generation: renderGeneration
                            });
                        }
                    }

                    function unwrapRenderBatches() {
                        content.querySelectorAll('.aropyt-render-batch').forEach(function(wrapper) {
                            while (wrapper.firstChild) {
                                wrapper.parentNode.insertBefore(wrapper.firstChild, wrapper);
                            }
                            wrapper.remove();
                        });
                    }

                    function finishRendering() {
                        if (!isCurrentRender()) return;
                        unwrapRenderBatches();
                        renderComplete = true;
                        content.setAttribute('contenteditable', 'true');
                        if (isLongDocument) {
                            setProgress(completeText);
                            postPreviewState('complete', allTokens.length, allTokens.length);
                            setTimeout(function() {
                                if (isCurrentRender()) setProgress('');
                            }, 1200);
                        }
                        notifyPreviewReady();
                    }

                    function viewportAnchorElements() {
                        return Array.prototype.filter.call(content.children, function(element) {
                            return element.hasAttribute('data-aropyt-source-start');
                        });
                    }

                    function sourceRangeForElement(element) {
                        return {
                            start: Number(element.getAttribute('data-aropyt-source-start')) || 0,
                            end: Number(element.getAttribute('data-aropyt-source-end')) || 0
                        };
                    }

                    function viewportReferenceY() {
                        return 24;
                    }

                    window.aropytViewportSourceOffset = function() {
                        var anchors = viewportAnchorElements();
                        if (anchors.length === 0) return 0;
                        var referenceY = viewportReferenceY();
                        var candidate = anchors[0];

                        for (var i = 0; i < anchors.length; i++) {
                            var rect = anchors[i].getBoundingClientRect();
                            if (rect.top <= referenceY) candidate = anchors[i];
                            if (rect.bottom > referenceY) {
                                if (rect.top <= referenceY) candidate = anchors[i];
                                break;
                            }
                        }

                        var candidateRect = candidate.getBoundingClientRect();
                        var range = sourceRangeForElement(candidate);
                        if (candidateRect.height <= 0 || range.end <= range.start) return range.start;
                        var fraction = Math.max(
                            0,
                            Math.min(1, (referenceY - candidateRect.top) / candidateRect.height)
                        );
                        return Math.round(range.start + (range.end - range.start) * fraction);
                    };

                    window.aropytScrollToSourceOffset = function(requestedOffset) {
                        var anchors = viewportAnchorElements();
                        if (anchors.length === 0) return false;
                        var offset = Math.max(0, Math.min(raw.length, Number(requestedOffset) || 0));
                        var candidate = anchors[0];
                        var range = sourceRangeForElement(candidate);

                        for (var i = 0; i < anchors.length; i++) {
                            var nextRange = sourceRangeForElement(anchors[i]);
                            candidate = anchors[i];
                            range = nextRange;
                            if (offset <= nextRange.end) break;
                        }

                        var rect = candidate.getBoundingClientRect();
                        var fraction = range.end > range.start
                            ? Math.max(0, Math.min(1, (offset - range.start) / (range.end - range.start)))
                            : 0;
                        var documentY = window.scrollY + rect.top + rect.height * fraction;
                        var maximumY = Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
                        window.scrollTo(0, Math.max(0, Math.min(maximumY, documentY - viewportReferenceY())));
                        return true;
                    };

                    // Used by integration verification for documents without
                    // post-processing mutations. It does not participate in the
                    // render path and therefore cannot delay first paint.
                    window.aropytMatchesWholeRender = function() {
                        if (!renderComplete || !window.marked) return false;
                        var savedSegments = protectedMathSegments;
                        var expected = restoreMathSegments(marked.parse(protectMathSegments(raw)));
                        protectedMathSegments = savedSegments;
                        var clone = content.cloneNode(true);
                        clone.querySelectorAll('[data-aropyt-source-start]').forEach(function(element) {
                            element.removeAttribute('data-aropyt-source-start');
                            element.removeAttribute('data-aropyt-source-end');
                        });
                        return clone.innerHTML === expected;
                    };

                    function scheduleIdle(callback) {
                        if (window.requestIdleCallback) {
                            requestIdleCallback(callback, { timeout: 50 });
                        } else {
                            setTimeout(function() {
                                callback({ timeRemaining: function() { return 12; } });
                            }, 0);
                        }
                    }

                    function renderMoreTokens() {
                        if (!isCurrentRender()) return;
                        var started = performance.now();
                        do {
                            appendTokenBatch(takeTokenBatch(64, 64 * 1024));
                        } while (nextTokenIndex < allTokens.length && performance.now() - started < 12);

                        setProgress(formatProgress(nextTokenIndex, allTokens.length));
                        postPreviewState('rendering', nextTokenIndex, allTokens.length);
                        if (nextTokenIndex >= allTokens.length) {
                            finishRendering();
                        } else {
                            scheduleIdle(renderMoreTokens);
                        }
                    }

                    function startRendering() {
                        if (!window.marked) {
                            content.textContent = raw;
                            finishRendering();
                            return;
                        }

                        marked.setOptions({
                            gfm: true,
                            breaks: false,
                            headerIds: true,
                            mangle: false
                        });
                        var protectedMarkdown = protectMathSegments(raw);
                        allTokens = marked.lexer(protectedMarkdown);
                        assignTokenSourceRanges(allTokens);
                        if (!isLongDocument) {
                            content.innerHTML = restoreMathSegments(marked.parser(allTokens));
                            annotateRenderedBlocks(content, allTokens);
                            processRenderedRoot(content);
                            finishRendering();
                            return;
                        }

                        nextTokenIndex = 0;
                        setProgress(formatProgress(0, allTokens.length));
                        postPreviewState('rendering', 0, allTokens.length);
                        appendTokenBatch(takeTokenBatch(80, 64 * 1024));
                        setProgress(formatProgress(nextTokenIndex, allTokens.length));
                        postPreviewState('rendering', nextTokenIndex, allTokens.length);
                        if (nextTokenIndex >= allTokens.length) {
                            finishRendering();
                        } else {
                            scheduleIdle(renderMoreTokens);
                        }
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
                        function texFromKatexNode(node) {
                            var annotation = node.querySelector
                                ? node.querySelector('annotation[encoding="application/x-tex"]')
                                : null;
                            return annotation ? (annotation.textContent || '') : '';
                        }
                        turndownService.addRule('katexDisplayMath', {
                            filter: function(node) {
                                return node.nodeType === 1
                                    && node.classList
                                    && node.classList.contains('katex-display');
                            },
                            replacement: function(_, node) {
                                var tex = texFromKatexNode(node);
                                return tex ? '\\n\\n$$\\n' + tex + '\\n$$\\n\\n' : '';
                            }
                        });
                        turndownService.addRule('katexInlineMath', {
                            filter: function(node) {
                                return node.nodeType === 1
                                    && node.classList
                                    && node.classList.contains('katex')
                                    && !(node.parentElement
                                        && node.parentElement.classList
                                        && node.parentElement.classList.contains('katex-display'));
                            },
                            replacement: function(_, node) {
                                var tex = texFromKatexNode(node);
                                return tex ? '$' + tex + '$' : '';
                            }
                        });
                        turndownService.addRule('mermaidDiagram', {
                            filter: function(node) {
                                return node.nodeType === 1
                                    && node.classList
                                    && node.classList.contains('aropyt-mermaid');
                            },
                            replacement: function(_, node) {
                                var source = node.getAttribute('data-mermaid-source') || '';
                                return '\\n\\n```mermaid\\n' + source + '\\n```\\n\\n';
                            }
                        });
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
                    var previewDirty = false;

                    function postDirtyState() {
                        if (window.webkit && window.webkit.messageHandlers
                            && window.webkit.messageHandlers.previewDirty) {
                            window.webkit.messageHandlers.previewDirty.postMessage(previewDirty);
                        }
                    }

                    function markPreviewDirty() {
                        if (previewDirty) return;
                        previewDirty = true;
                        postDirtyState();
                    }

                    function markdownFromContent() {
                        if (!turndownService) throw new Error('Turndown is unavailable');
                        return turndownService.turndown(content.innerHTML);
                    }

                    function postMarkdown() {
                        if (!turndownService || !previewDirty) return;
                        try {
                            var md = markdownFromContent();
                            previewDirty = false;
                            if (window.webkit && window.webkit.messageHandlers
                                && window.webkit.messageHandlers.markdownChanged) {
                                window.webkit.messageHandlers.markdownChanged.postMessage(md);
                            }
                            postDirtyState();
                        } catch (e) {
                            console.error('turndown failed:', e);
                        }
                    }
                    content.addEventListener('input', function() {
                        markPreviewDirty();
                        if (isLongDocument) return;
                        if (inputDebounceId) clearTimeout(inputDebounceId);
                        inputDebounceId = setTimeout(postMarkdown, 150);
                    });

                    function postFlushResult(requestID, succeeded, markdown, error) {
                        if (!(window.webkit && window.webkit.messageHandlers
                            && window.webkit.messageHandlers.previewFlushResult)) return;
                        window.webkit.messageHandlers.previewFlushResult.postMessage({
                            requestID: requestID,
                            success: succeeded,
                            markdown: markdown === null ? null : markdown,
                            error: error || ''
                        });
                    }

                    window.aropytFlushPreviewEdits = function(requestID) {
                        if (inputDebounceId) {
                            clearTimeout(inputDebounceId);
                            inputDebounceId = null;
                        }
                        if (!previewDirty) {
                            postFlushResult(requestID, true, null, '');
                            return;
                        }

                        content.setAttribute('contenteditable', 'false');
                        setError('');
                        setProgress(convertingText);
                        setTimeout(function() {
                            try {
                                var markdown = markdownFromContent();
                                previewDirty = false;
                                postDirtyState();
                                if (renderComplete) content.setAttribute('contenteditable', 'true');
                                setProgress('');
                                postFlushResult(requestID, true, markdown, '');
                            } catch (error) {
                                previewDirty = true;
                                if (renderComplete) content.setAttribute('contenteditable', 'true');
                                setProgress('');
                                setError(String(error && error.message ? error.message : error));
                                postFlushResult(
                                    requestID,
                                    false,
                                    null,
                                    String(error && error.message ? error.message : error)
                                );
                            }
                        }, 0);
                    };

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
                    function selectedNode() {
                        var sel = window.getSelection();
                        if (!sel || sel.rangeCount === 0) return null;
                        return sel.focusNode || sel.anchorNode;
                    }
                    function asElement(node) {
                        if (!node) return null;
                        return node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement;
                    }
                    function closestTagFromSelection(tagName) {
                        var el = asElement(selectedNode());
                        if (!el) return null;
                        tagName = tagName.toUpperCase();
                        while (el && el !== content) {
                            if (el.tagName === tagName) return el;
                            el = el.parentElement;
                        }
                        return null;
                    }
                    function currentBlockTag() {
                        var value = '';
                        try {
                            value = document.queryCommandValue('formatBlock') || '';
                        } catch (e) {}
                        value = String(value).replace(/[<>]/g, '').toLowerCase();
                        if (value) return value;

                        var el = asElement(selectedNode());
                        while (el && el !== content) {
                            var tag = el.tagName ? el.tagName.toLowerCase() : '';
                            if (['h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'p', 'pre', 'blockquote', 'li', 'div'].indexOf(tag) !== -1) {
                                return tag;
                            }
                            el = el.parentElement;
                        }
                        return '';
                    }
                    function setBlock(tagName) {
                        document.execCommand('formatBlock', false, tagName.toUpperCase());
                    }
                    function toggleBlock(tagName) {
                        var normalized = tagName.toLowerCase();
                        setBlock(currentBlockTag() === normalized ? 'P' : tagName);
                    }
                    function toggleCodeBlock() {
                        if (currentBlockTag() === 'pre' || closestTagFromSelection('pre')) {
                            setBlock('P');
                        } else {
                            setBlock('PRE');
                        }
                    }
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
                                toggleBlock(cmd);
                                break;
                            case 'paragraph':
                                setBlock('P');
                                break;
                            case 'blockquote':
                                setBlock('BLOCKQUOTE');
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
                                toggleCodeBlock();
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

                    window.aropytCancelRender = function(nextGeneration) {
                        renderCancelled = true;
                        window.__aropytRenderGeneration = nextGeneration || (renderGeneration + 1);
                        if (mermaidObserver) mermaidObserver.disconnect();
                    };

                    startRendering();
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
        // A valid JSON string can still contain `</script>`, which would close
        // this template's inline script in the HTML parser before JavaScript sees
        // it. Escaping HTML-significant scalars keeps the payload in script data.
        return trimmed
            .replacingOccurrences(of: "&", with: "\\u0026")
            .replacingOccurrences(of: "<", with: "\\u003C")
            .replacingOccurrences(of: ">", with: "\\u003E")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }
}
