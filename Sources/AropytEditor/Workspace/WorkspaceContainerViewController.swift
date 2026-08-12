import AppKit

final class WorkspaceContainerViewController: NSSplitViewController {
    let sidebarViewController: WorkspaceSidebarViewController
    let editorViewController: MainViewController

    var onSidebarVisibilityChanged: ((Bool) -> Void)?
    private(set) var lastToastMessage: String?
    private(set) var isSidebarVisible = true

    static let sidebarAnimationDuration: TimeInterval = 0.22

    private let sidebarItem: NSSplitViewItem
    private let toastLabel = NSTextField(labelWithString: "")
    private var toastWorkItem: DispatchWorkItem?

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

    override func viewDidLoad() {
        super.viewDidLoad()
        toastLabel.alignment = .center
        toastLabel.textColor = .white
        toastLabel.backgroundColor = NSColor.black.withAlphaComponent(0.76)
        toastLabel.drawsBackground = true
        toastLabel.isBezeled = false
        toastLabel.wantsLayer = true
        toastLabel.layer?.cornerRadius = 7
        toastLabel.translatesAutoresizingMaskIntoConstraints = false
        toastLabel.alphaValue = 0
        toastLabel.setContentHuggingPriority(.required, for: .horizontal)
        toastLabel.setAccessibilityIdentifier("workspace.sidebar.toast")
        view.addSubview(toastLabel)
        NSLayoutConstraint.activate([
            toastLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toastLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -28),
            toastLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 32),
            toastLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
        ])
    }

    func toggleSidebar() {
        let visible = !isSidebarVisible
        isSidebarVisible = visible
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.sidebarAnimationDuration
            context.allowsImplicitAnimation = true
            sidebarItem.animator().isCollapsed = !visible
        }
        let message = visible
            ? L10n.tr("workspace.sidebar.toast.shown", "Sidebar shown")
            : L10n.tr("workspace.sidebar.toast.hidden", "Sidebar hidden")
        showToast(message)
        onSidebarVisibilityChanged?(visible)
    }

    private func showToast(_ message: String) {
        _ = view
        lastToastMessage = message
        toastWorkItem?.cancel()
        toastLabel.stringValue = "  \(message)  "
        toastLabel.animator().alphaValue = 1

        let workItem = DispatchWorkItem { [weak self] in
            self?.toastLabel.animator().alphaValue = 0
        }
        toastWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: workItem)
    }
}
