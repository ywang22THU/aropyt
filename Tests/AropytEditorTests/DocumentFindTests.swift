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

    @Test func sourceExposesSelectedTextForCommandFind() {
        _ = NSApplication.shared
        let controller = SourceViewController()
        controller.setText("before selected after")
        controller.setEditorSelectedRange(NSRange(location: 7, length: 8))

        #expect(controller.editorSelectedText == "selected")
    }

    @Test func sourceReplacesCurrentMatchAndThenAllRemainingMatches() {
        _ = NSApplication.shared
        let controller = SourceViewController()
        var changedText: String?
        controller.onTextChanged = { changedText = $0 }
        controller.setText("Alpha alpha ALPHA")

        _ = controller.find(query: "alpha", direction: .initial)
        let current = controller.replaceCurrent(query: "alpha", with: "Beta")
        #expect(current?.replacements == 1)
        #expect(current?.findResult == DocumentFindResult(currentIndex: 0, totalMatches: 2))
        #expect(controller.currentText == "Beta alpha ALPHA")
        #expect(changedText == controller.currentText)

        let remaining = controller.replaceAll(query: "alpha", with: "Gamma")
        #expect(remaining?.replacements == 2)
        #expect(remaining?.findResult == DocumentFindResult(currentIndex: nil, totalMatches: 0))
        #expect(controller.currentText == "Beta Gamma Gamma")
        #expect(changedText == controller.currentText)
    }

    @Test func sourceReplaceAllDoesNotRecursivelyReplaceInsertedText() {
        _ = NSApplication.shared
        let controller = SourceViewController()
        controller.setText("a a")

        let result = controller.replaceAll(query: "a", with: "aa")
        #expect(result?.replacements == 2)
        #expect(controller.currentText == "aa aa")
    }

    @Test func replaceControlsExpandFromFindBar() {
        _ = NSApplication.shared
        let findBar = FindBarView()

        #expect(!findBar.isReplaceVisible)
        findBar.showReplace()
        #expect(findBar.isReplaceVisible)
    }

    @Test func findBarShowsCurrentIndexAndDocumentTotal() {
        _ = NSApplication.shared
        let findBar = FindBarView()

        findBar.setResult(DocumentFindResult(currentIndex: 1, totalMatches: 4))

        #expect(findBar.resultDescription == "2 / 4")
    }
}
