import AppKit
import Testing
@testable import AropytEditor

@Suite("Source view layout")
@MainActor
struct SourceViewLayoutTests {
    @Test func editorUsesPreviewMarginsAtNarrowAndWideWidths() {
        _ = NSApplication.shared
        let controller = SourceViewController()
        let root = controller.view

        root.frame = NSRect(x: 0, y: 0, width: 800, height: 500)
        controller.viewDidLayout()
        #expect(controller.editorTextContainerInset.width == 36)

        root.frame = NSRect(x: 0, y: 0, width: 1100, height: 500)
        controller.viewDidLayout()
        #expect(controller.editorTextContainerInset.width == 90)
        #expect(1100 - 2 * controller.editorTextContainerInset.width == 920)

        #expect(controller.editorTextContainerInset.height == 0)
        #expect(controller.editorLineFragmentPadding == 0)
    }

    @Test func editorUsesOnePointTwoLineHeightWithinParagraphs() {
        _ = NSApplication.shared
        let controller = SourceViewController()
        controller.setText("first wrapped line\nsecond paragraph")

        #expect(
            abs(
                controller.editorParagraphLineHeightMultiple
                    - SourceViewController.lineHeightMultiple
            ) < 0.001
        )
        #expect(SourceViewController.lineHeightMultiple == 1.2)
    }
}
