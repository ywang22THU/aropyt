import AppKit
import Testing
@testable import AropytEditor

@Suite("Document find")
@MainActor
struct DocumentFindTests {
    @Test func sourceFindsEveryMatchCaseInsensitivelyAndWraps() {
        _ = NSApplication.shared
        let controller = SourceViewController()
        controller.setText("Alpha beta alpha\nALPHA")

        #expect(controller.find(query: "alpha", direction: .initial)
            == DocumentFindResult(currentIndex: 0, totalMatches: 3))
        #expect(controller.find(query: "alpha", direction: .next)
            == DocumentFindResult(currentIndex: 1, totalMatches: 3))
        #expect(controller.find(query: "alpha", direction: .next)
            == DocumentFindResult(currentIndex: 2, totalMatches: 3))
        #expect(controller.find(query: "alpha", direction: .next)
            == DocumentFindResult(currentIndex: 0, totalMatches: 3))
        #expect(controller.find(query: "alpha", direction: .previous)
            == DocumentFindResult(currentIndex: 2, totalMatches: 3))
    }

    @Test func sourceReportsNoMatch() {
        _ = NSApplication.shared
        let controller = SourceViewController()
        controller.setText("A document with no matching term")

        #expect(controller.find(query: "missing", direction: .initial)
            == DocumentFindResult(currentIndex: nil, totalMatches: 0))
        #expect(controller.find(query: "", direction: .initial) == nil)
    }
}
