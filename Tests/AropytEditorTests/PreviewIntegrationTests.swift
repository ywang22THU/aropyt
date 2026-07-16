import AppKit
import Foundation
import Testing
import WebKit
@testable import AropytEditor
@testable import MarkdownCore

@Suite("Preview integration", .serialized)
@MainActor
struct PreviewIntegrationTests {
    private struct Snapshot: Sendable {
        let h1Count: Int
        let h2Count: Int
        let firstHeading: String
        let lastHeading: String
        let editable: String
        let batchWrapperCount: Int
        let matchesWholeRender: Bool
    }

    @Test func rendersTwoMegabyteFiftyThousandLineDocumentProgressively() async throws {
        _ = NSApplication.shared
        let filler = String(repeating: "x", count: 34)
        let markdown = (0..<50_000)
            .map { "## Item \($0) \(filler)" }
            .joined(separator: "\n")
        #expect(LongDocumentPolicy.lineCount(in: markdown) == 50_000)
        #expect(markdown.utf8.count >= 2_000_000)

        let controller = PreviewViewController()
        _ = controller.view
        let started = ContinuousClock.now
        controller.load(markdown: markdown)

        let firstBatchElapsed = try await waitForFirstBatch(controller, started: started)
        #expect(firstBatchElapsed < .seconds(1))
        try await waitUntilReady(controller, timeout: .seconds(30))

        let snapshot = try await snapshot(from: controller.view as! WKWebView)
        #expect(snapshot.h2Count == 50_000)
        #expect(snapshot.firstHeading.hasPrefix("Item 0 "))
        #expect(snapshot.lastHeading.hasPrefix("Item 49999 "))
        #expect(snapshot.editable == "true")
        #expect(snapshot.batchWrapperCount == 0)
        #expect(snapshot.matchesWholeRender)
    }

    @Test func newerRenderGenerationPreventsOldBatchesFromAppending() async throws {
        _ = NSApplication.shared
        let oldMarkdown = (0..<12_000).map { "## Old \($0)" }.joined(separator: "\n")
        let controller = PreviewViewController()
        _ = controller.view

        controller.load(markdown: oldMarkdown)
        controller.load(markdown: "# Replacement")
        try await waitUntilReady(controller, timeout: .seconds(10))

        let snapshot = try await snapshot(from: controller.view as! WKWebView)
        #expect(snapshot.h1Count == 1)
        #expect(snapshot.h2Count == 0)
        #expect(snapshot.firstHeading == "Replacement")
    }

    @Test func longPreviewDefersTurndownUntilExplicitFlush() async throws {
        _ = NSApplication.shared
        let markdown = String(repeating: "long preview text ", count: 35_000)
        #expect(LongDocumentPolicy.isLongDocument(markdown))

        let controller = PreviewViewController()
        var realtimeMarkdown: String?
        controller.onMarkdownEdited = { realtimeMarkdown = $0 }
        _ = controller.view
        controller.load(markdown: markdown)
        try await waitUntilReady(controller, timeout: .seconds(10))

        let webView = controller.view as! WKWebView
        try await runJavaScript(
            "document.getElementById('content').insertAdjacentHTML('beforeend', '<p>edited marker</p>');"
                + "document.getElementById('content').dispatchEvent(new Event('input', {bubbles:true}));",
            in: webView
        )
        try await Task.sleep(for: .milliseconds(250))
        #expect(realtimeMarkdown == nil)
        #expect(controller.isDirty)

        let flushed = try await withCheckedThrowingContinuation { continuation in
            controller.flushPreviewEdits { result in
                continuation.resume(with: result)
            }
        }
        #expect(flushed?.contains("edited marker") == true)
        #expect(!controller.isDirty)
    }

    @Test func ordinaryPreviewKeepsRealtimeTurndownBehavior() async throws {
        _ = NSApplication.shared
        let controller = PreviewViewController()
        var realtimeMarkdown: String?
        controller.onMarkdownEdited = { realtimeMarkdown = $0 }
        _ = controller.view
        controller.load(markdown: "initial")
        try await waitUntilReady(controller, timeout: .seconds(10))

        let dependencies = try await javaScriptString(
            "typeof marked + '|' + typeof TurndownService + '|' + document.baseURI",
            in: controller.view as! WKWebView
        )
        #expect(dependencies.hasPrefix("object|function|"), "\(dependencies)")
        try await runJavaScript(
            "document.getElementById('content').innerHTML = '<p>changed normally</p>';"
                + "document.getElementById('content').dispatchEvent(new Event('input', {bubbles:true}));",
            in: controller.view as! WKWebView
        )
        try await Task.sleep(for: .milliseconds(300))

        #expect(realtimeMarkdown?.contains("changed normally") == true)
        #expect(!controller.isDirty)
    }

    @Test func keepsComplexBlockBoundariesAndLazilyRendersMermaid() async throws {
        _ = NSApplication.shared
        let prefix = (0..<78).map { "## Prefix \($0)" }.joined(separator: "\n")
        let tail = String(repeating: "tail filler ", count: 50_000)
        let markdown = """
        \(prefix)
        - alpha
        - beta
        - gamma

        | Left | Right |
        | --- | ---: |
        | A | B |

        ```swift
        let answer = 42
        ```

        Math: $x^2 + y^2$

        ```mermaid
        graph TD
          A --> B
        ```

        \(tail)
        """
        #expect(LongDocumentPolicy.isLongDocument(markdown))

        let controller = PreviewViewController()
        _ = controller.view
        controller.load(markdown: markdown)
        try await waitUntilReady(controller, timeout: .seconds(15))
        let webView = controller.view as! WKWebView

        let result = try await javaScriptString("""
            (function() {
                var diagram = document.querySelector('.aropyt-mermaid');
                return [
                    document.querySelectorAll('li').length,
                    document.querySelectorAll('table tbody tr').length,
                    document.querySelector('pre code.language-swift').textContent.trim(),
                    document.querySelectorAll('.katex').length,
                    diagram ? diagram.getAttribute('data-mermaid-source') : ''
                ].join('|');
            })();
            """, in: webView)
        #expect(result.hasPrefix("3|1|let answer = 42|"), "\(result)")
        #expect(result.contains("|graph TD"), "\(result)")
        let parts = result.split(separator: "|", omittingEmptySubsequences: false)
        #expect((Int(parts[3]) ?? 0) > 0)

        try await runJavaScript(
            "document.querySelector('.aropyt-mermaid').scrollIntoView({block:'center'});",
            in: webView
        )
        let mermaidRendered = try await waitForJavaScriptBoolean(
            "!!document.querySelector('.aropyt-mermaid svg')",
            in: webView,
            timeout: .seconds(10)
        )
        #expect(mermaidRendered)
    }

    @Test func switchingToSourceFlushesLongPreviewAndSavesInNeverMode() async throws {
        _ = NSApplication.shared
        let preferences = AutoSavePreferences.shared
        let oldMode = preferences.mode
        preferences.mode = .never
        defer { preferences.mode = oldMode }

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AropytEditor-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let markdown = String(repeating: "source switch text ", count: 32_000)
        try markdown.write(to: fileURL, atomically: true, encoding: .utf8)

        let document = MarkdownDocument()
        document.fileURL = fileURL
        document.fileType = "net.daringfireball.markdown"
        document.text = markdown
        let main = MainViewController()
        main.document = document
        _ = main.view
        main.reloadFromDocument()
        guard let preview = main.children.compactMap({ $0 as? PreviewViewController }).first else {
            Issue.record("Preview controller was not embedded")
            return
        }
        try await waitUntilReady(preview, timeout: .seconds(10))

        try await runJavaScript(
            "document.getElementById('content').insertAdjacentHTML('beforeend', '<p>source switch marker</p>');"
                + "document.getElementById('content').dispatchEvent(new Event('input', {bubbles:true}));",
            in: preview.view as! WKWebView
        )
        try await waitForCondition(timeout: .seconds(2)) { preview.isDirty }

        main.toggleMode(nil)
        try await waitForCondition(timeout: .seconds(10)) { main.mode == .source }
        try await waitForCondition(timeout: .seconds(10)) {
            (try? String(contentsOf: fileURL, encoding: .utf8).contains("source switch marker")) == true
        }
        #expect(document.text.contains("source switch marker"))
    }

    @Test func commandSaveFlushesLongPreviewBeforeWritingDisk() async throws {
        _ = NSApplication.shared
        let preferences = AutoSavePreferences.shared
        let oldMode = preferences.mode
        preferences.mode = .never
        defer { preferences.mode = oldMode }

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AropytEditor-save-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let markdown = String(repeating: "command save text ", count: 32_000)
        try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
        let (document, main, preview) = try await makeLongDocumentEditor(
            markdown: markdown,
            fileURL: fileURL
        )

        try await runJavaScript(
            "document.getElementById('content').insertAdjacentHTML('beforeend', '<p>command save marker</p>');"
                + "document.getElementById('content').dispatchEvent(new Event('input', {bubbles:true}));",
            in: preview.view as! WKWebView
        )
        try await waitForCondition(timeout: .seconds(2)) { preview.isDirty }

        main.saveDocument(nil)
        try await waitForCondition(timeout: .seconds(10)) {
            (try? String(contentsOf: fileURL, encoding: .utf8).contains("command save marker")) == true
        }
        #expect(document.text.contains("command save marker"))
    }

    @Test func failedFlushStopsClosePreparationAndKeepsOldMarkdown() async throws {
        _ = NSApplication.shared
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AropytEditor-close-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let markdown = String(repeating: "close safety text ", count: 32_000)
        try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
        let (document, main, preview) = try await makeLongDocumentEditor(
            markdown: markdown,
            fileURL: fileURL
        )
        let webView = preview.view as! WKWebView

        try await runJavaScript(
            "document.getElementById('content').insertAdjacentHTML('beforeend', '<p>must stay in DOM</p>');"
                + "document.getElementById('content').dispatchEvent(new Event('input', {bubbles:true}));",
            in: webView
        )
        try await waitForCondition(timeout: .seconds(2)) { preview.isDirty }
        try await runJavaScript("""
            window.aropytFlushPreviewEdits = function(requestID) {
                window.webkit.messageHandlers.previewFlushResult.postMessage({
                    requestID: requestID,
                    success: false,
                    markdown: null,
                    error: 'injected conversion failure'
                });
            };
            true;
            """, in: webView)

        let mayClose = await withCheckedContinuation { continuation in
            main.prepareToClose { continuation.resume(returning: $0) }
        }
        #expect(!mayClose)
        #expect(preview.isDirty)
        #expect(!document.text.contains("must stay in DOM"))
        #expect((try? String(contentsOf: fileURL, encoding: .utf8).contains("must stay in DOM")) != true)
    }

    private func waitForFirstBatch(_ controller: PreviewViewController,
                                   started: ContinuousClock.Instant) async throws -> Duration {
        while started.duration(to: .now) < .seconds(10) {
            switch controller.renderState {
            case .rendering(let completed, _) where completed > 0:
                return started.duration(to: .now)
            case .ready:
                return started.duration(to: .now)
            default:
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        throw IntegrationError.timeout("first preview batch")
    }

    private func waitUntilReady(_ controller: PreviewViewController,
                                timeout: Duration) async throws {
        let clock = ContinuousClock()
        let started = clock.now
        while started.duration(to: clock.now) < timeout {
            if controller.renderState == .ready { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        let readyState = try? await javaScriptString("document.readyState + '|' + document.title", in: controller.view as! WKWebView)
        throw IntegrationError.timeout(
            "complete preview; navigationFinished=\(controller.navigationDidFinish); "
                + "navigationError=\(controller.lastNavigationErrorDescription ?? "none"); "
                + "document=\(readyState ?? "unavailable")"
        )
    }

    private func snapshot(from webView: WKWebView) async throws -> Snapshot {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript("""
                (function() {
                    var headings = document.querySelectorAll('h1, h2');
                    return [
                        document.querySelectorAll('h1').length,
                        document.querySelectorAll('h2').length,
                        headings.length ? headings[0].textContent : '',
                        headings.length ? headings[headings.length - 1].textContent : '',
                        document.getElementById('content').getAttribute('contenteditable') || '',
                        document.querySelectorAll('.aropyt-render-batch').length,
                        window.aropytMatchesWholeRender ? window.aropytMatchesWholeRender() : false
                    ];
                })();
                """) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let values = value as? [Any], values.count == 7 else {
                    continuation.resume(throwing: IntegrationError.invalidJavaScriptResult)
                    return
                }
                continuation.resume(returning: Snapshot(
                    h1Count: values[0] as? Int ?? 0,
                    h2Count: values[1] as? Int ?? 0,
                    firstHeading: values[2] as? String ?? "",
                    lastHeading: values[3] as? String ?? "",
                    editable: values[4] as? String ?? "",
                    batchWrapperCount: values[5] as? Int ?? -1,
                    matchesWholeRender: values[6] as? Bool ?? false
                ))
            }
        }
    }

    private func runJavaScript(_ script: String, in webView: WKWebView) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            webView.evaluateJavaScript(script) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func waitForJavaScriptBoolean(_ script: String,
                                          in webView: WKWebView,
                                          timeout: Duration) async throws -> Bool {
        let clock = ContinuousClock()
        let started = clock.now
        while started.duration(to: clock.now) < timeout {
            let value: Bool = try await withCheckedThrowingContinuation { continuation in
                webView.evaluateJavaScript(script) { value, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: value as? Bool ?? false)
                    }
                }
            }
            if value { return true }
            try await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    private func makeLongDocumentEditor(markdown: String,
                                        fileURL: URL) async throws
        -> (MarkdownDocument, MainViewController, PreviewViewController) {
        let document = MarkdownDocument()
        document.fileURL = fileURL
        document.fileType = "net.daringfireball.markdown"
        document.text = markdown
        let main = MainViewController()
        main.document = document
        _ = main.view
        main.reloadFromDocument()
        guard let preview = main.children.compactMap({ $0 as? PreviewViewController }).first else {
            throw IntegrationError.missingPreviewController
        }
        try await waitUntilReady(preview, timeout: .seconds(10))
        return (document, main, preview)
    }

    private func waitForCondition(timeout: Duration,
                                  condition: @escaping @MainActor () -> Bool) async throws {
        let clock = ContinuousClock()
        let started = clock.now
        while started.duration(to: clock.now) < timeout {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw IntegrationError.timeout("condition")
    }

    private func javaScriptString(_ script: String, in webView: WKWebView) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: value as? String ?? "")
                }
            }
        }
    }

    private enum IntegrationError: Error {
        case timeout(String)
        case invalidJavaScriptResult
        case missingPreviewController
    }
}
