import AppKit

final class WorkspaceContainerViewController: NSSplitViewController {
    let sidebarViewController: WorkspaceSidebarViewController
    let editorViewController: MainViewController

    var onSidebarVisibilityChanged: ((Bool) -> Void)?
    private(set) var isSidebarVisible = true

    static let sidebarAnimationDuration: TimeInterval = 0.22

    private let sidebarItem: NSSplitViewItem

    init(sidebarViewController: WorkspaceSidebarViewController,
         editorViewController: MainViewController) {
        self.sidebarViewController = sidebarViewController
        self.editorViewController = editorViewController
        self.sidebarItem = NSSplitViewItem(viewController: sidebarViewController)
        super.init(nibName: nil, bundle: nil)

        splitView.isVertical = true
        splitView.dividerStyle = .thin
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 420
        sidebarItem.canCollapse = true
        sidebarItem.holdingPriority = .defaultLow
        addSplitViewItem(sidebarItem)
        addSplitViewItem(NSSplitViewItem(viewController: editorViewController))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func toggleSidebar() {
        let visible = !isSidebarVisible
        isSidebarVisible = visible
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.sidebarAnimationDuration
            context.allowsImplicitAnimation = true
            sidebarItem.animator().isCollapsed = !visible
        }
        onSidebarVisibilityChanged?(visible)
    }
}
