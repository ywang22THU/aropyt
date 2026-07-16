import AppKit
import Testing
@testable import AropytEditor

@Suite("Markdown highlighter")
struct MarkdownHighlighterTests {
    @Test @MainActor func partialHighlightCoversHeadingAndLinkWithoutTouchingOtherParagraphs() {
        let text = "# Heading\nplain sentinel\n[OpenAI](openai.com)\n"
        let storage = NSTextStorage(string: text)
        let sentinelRange = (text as NSString).range(of: "plain sentinel")
        storage.addAttribute(.backgroundColor, value: NSColor.systemRed, range: sentinelRange)

        let highlighter = MarkdownHighlighter()
        let headingRange = (text as NSString).range(of: "Heading")
        let linkRange = (text as NSString).range(of: "[OpenAI]")
        highlighter.apply(to: storage, range: headingRange)
        highlighter.apply(to: storage, range: linkRange)

        #expect(storage.attribute(.foregroundColor, at: headingRange.location, effectiveRange: nil) as? NSColor == NSColor.systemBlue)
        #expect(storage.attribute(.link, at: linkRange.location, effectiveRange: nil) != nil)
        #expect(storage.attribute(.backgroundColor, at: sentinelRange.location, effectiveRange: nil) as? NSColor == NSColor.systemRed)
    }

    @Test func rangeExpansionHandlesMultilinePasteAndDeletedNewline() {
        let text = "first line\nsecond line\nthird line" as NSString
        let multiline = MarkdownHighlighter.expandedHighlightRange(
            for: NSRange(location: 3, length: 15),
            in: text
        )
        #expect(text.substring(with: multiline) == "first line\nsecond line\n")

        let joined = "first linesecond line\nthird line" as NSString
        let deletion = MarkdownHighlighter.expandedHighlightRange(
            for: NSRange(location: 10, length: 0),
            in: joined
        )
        #expect(joined.substring(with: deletion) == "first linesecond line\n")
    }

    @Test @MainActor func rehighlightingRemovedLinkClearsStaleAttribute() {
        let storage = NSTextStorage(string: "plain text\n")
        let full = NSRange(location: 0, length: storage.length)
        storage.addAttribute(.link, value: URL(string: "https://example.com")!, range: full)

        MarkdownHighlighter().apply(to: storage, range: full)

        #expect(storage.attribute(.link, at: 0, effectiveRange: nil) == nil)
    }

    @Test @MainActor func localEditRangeStaysBelowFiftyMilliseconds() {
        let line = "plain text with [link](https://example.com) and **bold**\n"
        let text = String(repeating: line, count: 50_000)
        let storage = NSTextStorage(string: text)
        let target = NSRange(location: (text as NSString).length / 2, length: 1)
        let clock = ContinuousClock()

        let elapsed = clock.measure {
            MarkdownHighlighter().apply(to: storage, range: target)
        }

        #expect(elapsed < .milliseconds(50), "Local highlight took \(elapsed)")
    }

    @Test @MainActor func backgroundBatchStaysBelowOneHundredMilliseconds() {
        let line = "## heading with [link](https://example.com) and **bold**\n"
        let text = String(repeating: line, count: 3_000)
        let storage = NSTextStorage(string: text)
        let batch = NSRange(location: 0, length: min(64 * 1024, storage.length))
        let clock = ContinuousClock()

        let elapsed = clock.measure {
            MarkdownHighlighter().apply(to: storage, range: batch)
        }

        #expect(elapsed < .milliseconds(100), "64 KiB highlight batch took \(elapsed)")
    }
}
