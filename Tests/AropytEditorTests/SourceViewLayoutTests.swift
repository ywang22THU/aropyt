import AppKit
import Testing
@testable import AropytEditor

@Suite("Source view layout")
@MainActor
struct SourceViewLayoutTests {
    @Test func editorUsesSymmetricHorizontalTextInsets() {
        _ = NSApplication.shared
        let controller = SourceViewController()
        _ = controller.view

        #expect(controller.editorTextContainerInset.width == SourceViewController.horizontalTextInset)
        #expect(controller.editorTextContainerInset.width > 0)
        #expect(controller.editorTextContainerInset.height == 0)
        #expect(controller.editorLineFragmentPadding == 0)
    }
}
