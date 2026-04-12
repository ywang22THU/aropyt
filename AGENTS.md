# AGENTS.md

本文件给未来在此目录工作的 Codex 提供项目特定指引。

## 项目简介

AropytEditor — macOS 本地 Markdown 编辑器。Swift + AppKit + SPM。详见 [ARCHITECTURE.md](ARCHITECTURE.md) 和 [PROMPT.md](PROMPT.md)。

## 构建 / 运行

```sh
swift build
swift run AropytEditor
```

不要尝试通过 Xcode 项目运行 —— 此项目纯 SPM，没有 .xcodeproj。用户偏好直接跑 `.build/debug/AropytEditor`。

## 目录约定

- `Sources/MarkdownCore/` —— **不许 import AppKit**。这里只放纯逻辑（HTML 模板、字符串处理等），方便未来加测试。
- `Sources/AropytEditor/` —— App 主体，AppKit 全在这里。
- `Sources/AropytEditor/Resources/` —— 通过 `.process("Resources")` 打包，但 **Info.plist 必须 exclude** 并通过 linkerSettings 嵌入。

## 必须遵守的 AppKit 陷阱

1. **NSWindowController** 子类不要依赖 `windowDidLoad`。用 `init(window:)` 时它**不会**触发。改用显式 `setup()` 方法，在 `addWindowController(wc)` 之后手动调。
2. **NSDocument 子类内调 print 必须写 `Swift.print(...)`**，否则和 NSDocument 自己的 `print()` 实例方法歧义。
3. **`NSTextView`** 创建后必须设置 `minSize/maxSize/isVerticallyResizable` 和 textContainer 的 width 跟踪，否则可能空白。
4. **`PreviewViewController.webView`** 必须懒加载。`load(markdown:)` 入口先 `_ = view` 触发 `loadView()`，再 `guard let webView`。
5. **不要用 `lazy var`** 在 `loadView()` 里通过 helper 函数创建子视图 —— 容易出现 scrollView 里的实例和 self 属性不是同一个。改用 `var foo: NSTextView?` + `loadView` 中赋值。
6. **`AppDocumentController` 必须在 `main.swift` 第一行实例化** 才能让 `NSDocumentController.shared` 返回它。脱 bundle 跑时这是文档类型注册的唯一办法。

## P0 / P1 边界

P0 = 源码编辑 + 预览渲染 + 模式切换 + README，**不包含**预览模式下编辑。
P1 = WYSIWYG 编辑、图片粘贴、表格操作、cmd+click 链接。

不要在 P0 阶段提前实现 P1 功能；先把 P0 闭环跑通。

## 用户偏好

- 中文沟通
- 简洁直接，技术背景强，喜欢知道"为什么"
- 用 fish shell；xcode-select 可能指向 Command Line Tools，但 `swift build` 用的是 `/usr/bin/swift`（Apple Swift toolchain）即可
