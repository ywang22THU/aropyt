import Testing
@testable import MarkdownCore

@Suite("Long document policy")
struct LongDocumentPolicyTests {
    @Test func utf8ByteThresholdIsInclusive() {
        #expect(!LongDocumentPolicy.isLongDocument(
            utf8ByteCount: LongDocumentPolicy.utf8ByteThreshold - 1,
            lineCount: 1
        ))
        #expect(LongDocumentPolicy.isLongDocument(
            utf8ByteCount: LongDocumentPolicy.utf8ByteThreshold,
            lineCount: 1
        ))
    }

    @Test func lineThresholdIsInclusive() {
        #expect(!LongDocumentPolicy.isLongDocument(
            utf8ByteCount: 1,
            lineCount: LongDocumentPolicy.lineThreshold - 1
        ))
        #expect(LongDocumentPolicy.isLongDocument(
            utf8ByteCount: 1,
            lineCount: LongDocumentPolicy.lineThreshold
        ))
    }

    @Test func countsGeneratedFiftyThousandLineDocument() {
        let markdown = Array(repeating: "line", count: 50_000).joined(separator: "\n")
        #expect(LongDocumentPolicy.lineCount(in: markdown) == 50_000)
        #expect(LongDocumentPolicy.isLongDocument(markdown))
    }

    @Test func utf8SizeUsesBytesRatherThanUTF16Units() {
        let markdown = String(repeating: "文", count: LongDocumentPolicy.utf8ByteThreshold / 3)
        #expect(!LongDocumentPolicy.isLongDocument(markdown))
        #expect(LongDocumentPolicy.isLongDocument(markdown + "文"))
    }

    @Test func countsLFCRLFAndCRLineEndings() {
        #expect(LongDocumentPolicy.lineCount(in: "a\nb\nc") == 3)
        #expect(LongDocumentPolicy.lineCount(in: "a\r\nb\r\nc") == 3)
        #expect(LongDocumentPolicy.lineCount(in: "a\rb\rc") == 3)
    }
}
