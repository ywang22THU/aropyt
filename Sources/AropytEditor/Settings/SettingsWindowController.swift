import AppKit

/// Settings 窗口控制器。单例管理，⌘, 打开。
final class SettingsWindowController: NSWindowController {

    static let shared = SettingsWindowController()

    private init() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        w.title = "Settings"
        w.center()
        w.minSize = NSSize(width: 600, height: 400)
        w.isReleasedWhenClosed = false
        super.init(window: w)
        let vc = SettingsTabViewController()
        w.contentViewController = vc
    }

    required init?(coder: NSCoder) { fatalError() }

    func showWindow() {
        // 确保窗口尺寸正确（单例首次创建后可能被缓存为旧尺寸）
        if let w = window {
            let current = w.frame.size
            let target = NSSize(width: 820, height: 500)
            if current.width < target.width || current.height < target.height {
                w.setContentSize(target)
            }
        }
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
