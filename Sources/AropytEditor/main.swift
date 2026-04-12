import AppKit

// 必须在 NSApplication 启动前实例化我们的 DocumentController 子类，
// 这样 NSDocumentController.shared 才会返回 AppDocumentController。
// 脱 .app bundle 直接跑 .build/debug/AropytEditor 时，文档类型注册靠它。
_ = AppDocumentController()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
