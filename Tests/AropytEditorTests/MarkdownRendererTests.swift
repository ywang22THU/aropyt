import JavaScriptCore
import Testing
@testable import MarkdownCore

@Suite("Markdown renderer")
struct MarkdownRendererTests {
    @Test func payloadCannotTerminateInlineScript() {
        let payload = #"</script><script>window.pwned = true</script>  "#
        let html = MarkdownRenderer.htmlDocument(for: payload)

        #expect(!html.contains(payload))
        #expect(!html.contains("</script><script>window.pwned"))
        #expect(html.contains(#"\u003C\/script\u003E\u003Cscript\u003Ewindow.pwned = true\u003C\/script\u003E\u2028\u2029"#))
    }

    @Test func longDocumentTemplateContainsProgressiveRenderingContracts() {
        let configuration = PreviewRenderConfiguration(isLongDocument: true, generation: 42)
        let html = MarkdownRenderer.htmlDocument(for: "# Heading", configuration: configuration)

        #expect(html.contains("var isLongDocument = true"))
        #expect(html.contains("var renderGeneration = 42"))
        #expect(html.contains("marked.lexer(protectedMarkdown)"))
        #expect(html.contains("takeTokenBatch(80, 64 * 1024)"))
        #expect(html.contains("performance.now() - started < 12"))
        #expect(html.contains("requestIdleCallback"))
        #expect(html.contains("IntersectionObserver"))
        #expect(html.contains("window.aropytCancelRender"))
        #expect(html.contains("window.aropytFlushPreviewEdits"))
        #expect(html.contains("data-aropyt-source-start"))
        #expect(html.contains("window.aropytViewportSourceOffset"))
        #expect(html.contains("window.aropytScrollToSourceOffset"))
        #expect(html.contains("var supportsBackslashMathDelimiters = false"))
        #expect(html.contains("var supportsMathCodeBlocks = false"))
        #expect(html.contains("var showsCodeBlockLineNumbers = true"))
        #expect(html.contains("var wrapsCodeBlockLines = true"))
        #expect(html.contains("data-aropyt-math-source"))
        #expect(html.contains("data-aropyt-math-display"))
        #expect(html.contains("data-aropyt-math-delimiter"))
        #expect(html.contains("turndownService.addRule('aropytMathSegment'"))
    }

    @Test func backslashMathDelimiterConfigurationIsEmbedded() {
        let configuration = PreviewRenderConfiguration(
            isLongDocument: false,
            supportsBackslashMathDelimiters: true
        )
        let html = MarkdownRenderer.htmlDocument(for: #"\[x\]"#, configuration: configuration)

        #expect(html.contains("var supportsBackslashMathDelimiters = true"))
    }

    @Test func syntaxCodeBlockConfigurationIsEmbedded() {
        let configuration = PreviewRenderConfiguration(
            isLongDocument: false,
            supportsMathCodeBlocks: true,
            showsCodeBlockLineNumbers: false,
            wrapsCodeBlockLines: false
        )
        let html = MarkdownRenderer.htmlDocument(for: "```math\nx^2\n```", configuration: configuration)

        #expect(html.contains("var supportsMathCodeBlocks = true"))
        #expect(html.contains("var showsCodeBlockLineNumbers = false"))
        #expect(html.contains("var wrapsCodeBlockLines = false"))
        #expect(html.contains("function prepareMathCodeBlocks(root)"))
        #expect(html.contains("function applyCodeBlockPreferences(root)"))
    }

    @Test func localImageBaseURLIsEmbedded() {
        let configuration = PreviewRenderConfiguration(
            isLongDocument: false,
            imageBaseURL: "aropyt-document://local/tmp/notes/"
        )
        let html = MarkdownRenderer.htmlDocument(
            for: "![](assets/image.png)",
            configuration: configuration
        )

        #expect(html.contains(#"aropyt-document:\/\/local\/tmp\/notes\/"#))
        #expect(html.contains("function resolveLocalImageSources(root)"))
        #expect(html.contains("new URL(source, imageBaseURL).href"))
        #expect(html.contains("data-aropyt-image-source"))
        #expect(html.contains("turndownService.addRule('aropytLocalImage'"))
    }

    @Test func localizedConfigurationIsSafelyEmbedded() {
        let configuration = PreviewRenderConfiguration(
            isLongDocument: true,
            progressText: #"进度 </script> %d / %d"#,
            autoSaveWarningText: #"警告 </script>"#,
            showsAutoSaveWarning: true,
            mermaidExportText: #"导出 </script>"#
        )
        let html = MarkdownRenderer.htmlDocument(for: "text", configuration: configuration)

        #expect(!html.contains(#"进度 </script>"#))
        #expect(html.contains(#"进度 \u003C\/script\u003E %d \/ %d"#))
        #expect(html.contains(#"导出 \u003C\/script\u003E"#))
        #expect(html.contains("var showsAutoSaveWarning = true"))
    }

    @Test func generatedInlineJavaScriptHasNoSyntaxError() throws {
        let html = MarkdownRenderer.htmlDocument(
            for: "# syntax check",
            configuration: PreviewRenderConfiguration(isLongDocument: true)
        )
        guard
            let start = html.range(of: "<script>\n", options: .backwards),
            let end = html.range(of: "</script>", range: start.upperBound..<html.endIndex)
        else {
            Issue.record("Could not locate inline preview script")
            return
        }
        let script = String(html[start.upperBound..<end.lowerBound])
        let context = JSContext()!
        context.evaluateScript(script)
        let exception = context.exception?.toString() ?? ""
        #expect(!exception.contains("SyntaxError"), "\(exception)")
    }
}
