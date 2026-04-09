# AropytEditor 架构设计

## 目标

macOS 本地 Markdown 编辑器，支持源码编辑 + 预览渲染 + 模式切换。
P1 阶段加入 WYSIWYG 预览编辑、表格/图片/链接交互。

## 技术栈

- **语言**：Swift 6.x
- **UI**：AppKit（NSDocument 架构）
- **构建**：Swift Package Manager（脱 Xcode 也能 `swift build`）
- **预览渲染**：WKWebView + marked.js + highlight.js（本地资源，离线可用）
- **平台**：macOS 13+（Ventura 起步，使用 modern APIs）

## 模块结构

```
aropyt/
├── Package.swift
├── README.md
├── ARCHITECTURE.md
├── CLAUDE.md
├── Sources/
│   ├── MarkdownCore/                  # 纯 Swift target，无 AppKit 依赖
│   │   └── MarkdownRenderer.swift     # 把 markdown 字符串包进 HTML 模板
│   └── AropytEditor/                  # App 主体 target
│       ├── main.swift                 # 入口
│       ├── AppDelegate.swift
│       ├── AppDocumentController.swift
│       ├── Document/
│       │   └── MarkdownDocument.swift # NSDocument 子类，单一数据源
│       ├── Window/
│       │   ├── EditorWindowController.swift
│       │   ├── MainViewController.swift     # 模式协调器（切换 source/preview）
│       │   ├── SourceViewController.swift   # NSTextView + 正则高亮
│       │   └── PreviewViewController.swift  # WKWebView 渲染
│       ├── Highlighter/
│       │   └── MarkdownHighlighter.swift    # 简单正则语法高亮
│       └── Resources/
│           ├── Info.plist             # 通过 linkerSettings 嵌入
│           ├── preview.html           # WebView 模板
│           ├── marked.umd.js          # MD → HTML
│           ├── highlight.min.js       # 代码块高亮
│           └── github-markdown.css    # GitHub 样式
```

## 数据流

```
[文件]
  ↓ open
[MarkdownDocument.read(from:)] —— 单一数据源（document.text: String）
  ↓ makeWindowControllers
[EditorWindowController] → [MainViewController]
  ↓ 持有 document
[SourceViewController]   ←→  [PreviewViewController]
  (NSTextView 编辑)            (WKWebView 渲染)
  text 改变 → document.text → markedAsEdited
```

**约定**：所有写入都经过 `document.text`。源码模式编辑直接同步到 document.text；切换到预览时用最新 document.text 渲染。

## P0 关键决策

### 1. NSDocument + 子类化 NSDocumentController

直接 `swift run` 时 `.build/debug/AropytEditor` 不是 .app bundle，`NSDocumentController` 默认通过 Info.plist 的 `CFBundleDocumentTypes` 注册类型，但脱 bundle 时这条路径失效。
**解法**：自定义 `AppDocumentController`，硬编码 `documentClassNames`、`defaultType`，并在 `main.swift` 第一行 `_ = AppDocumentController()` 让 `.shared` 返回它。

### 2. Info.plist 嵌入

SPM 的 `.process("Resources")` 把 Info.plist 当作禁止的顶层资源；必须 `exclude` + `linkerSettings(.unsafeFlags(["-Xlinker", "-sectcreate", ...]))` 把 plist 写入 Mach-O 的 `__TEXT,__info_plist` 段。这样脱 bundle 也能让 `Bundle.main.infoDictionary` 工作。

### 3. WindowController 初始化

不依赖 `windowDidLoad`（用 `init(window:)` 时不会触发）。改为：
```swift
override init() {
    let window = NSWindow(...)
    super.init(window: window)
}
func setup(document: MarkdownDocument) { ... }
```
`makeWindowControllers` 里 `addWindowController(wc)` 之后显式调 `wc.setup(document: self)`。

### 4. 预览懒加载

`PreviewViewController` 的 `webView` 在 `loadView()` 才创建。`load(markdown:)` 入口先 `_ = view` 触发 `loadView()`，再 `guard let webView`。避免提前访问导致 nil。

### 5. NSTextView 必备配置

```swift
tv.minSize = .zero
tv.maxSize = NSSize(width: .infinity, height: .infinity)
tv.isVerticallyResizable = true
tv.isHorizontallyResizable = false
tv.autoresizingMask = [.width]
tv.textContainer?.widthTracksTextView = true
tv.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: .infinity)
```

### 6. 预览渲染流程

1. `MarkdownRenderer.htmlDocument(for: text, baseURL:)` 拼出完整 HTML：
   - 头部 `<link>` 样式 + `<script src="marked.umd.js">` + `<script src="highlight.min.js">`
   - body 里塞一个 `<div id="content"></div>`
   - 用 `JSON.stringify` 内联原始 markdown 字符串，避免转义错误
   - 末尾 `<script>` 调 `marked.parse` 写入 `#content`，再对 `pre code` 跑 `hljs.highlightAll()`
2. WebView 用 `loadHTMLString(_:baseURL:)`，baseURL 指向 Resources 目录，让 `<script src>` 和图片相对路径生效。

## P1 设计草图（不在本次实现范围）

- **WYSIWYG 编辑**：基于预览 WebView 的 `contenteditable`，通过 JS bridge 把 DOM 编辑事件回传 Swift，再用 turndown.js 反向生成 markdown 写回 document.text。
- **图片粘贴**：`NSTextView.paste:` 重写，从 NSPasteboard 取 PNG/TIFF，写入 `<doc-dir>/assets/`，插入 `![](assets/xxx.png)`。
- **表格操作**：右键菜单 + JS 工具栏；preview 端用 contenteditable 表格 + JS 维护行列。
- **链接 cmd+click**：源码模式监听 NSTextView 点击；预览模式 WebView 通过 `decidePolicyFor navigationAction` 拦截 + `NSWorkspace.shared.open`。

## 构建 / 运行

```sh
swift build              # debug
swift run AropytEditor   # 直接运行
.build/debug/AropytEditor # 跑出来的可执行文件
```
