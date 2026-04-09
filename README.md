# AropytEditor

macOS 上的本地 Markdown 编辑器，使用 Swift + AppKit 开发，纯 Swift Package Manager 构建（无 Xcode 项目）。

## 功能

### P0（已实现）

-   打开 / 新建 / 保存 `.md` 文件（NSDocument）
-   **源码模式**：基于 `NSTextView`，带正则语法高亮
-   **预览模式**：基于 `WKWebView` + 本地 `marked.js` + `highlight.js`，支持完整 CommonMark/GFM
    -   粗体、斜体、删除线、列表、标题、代码块（带语法高亮）、表格、图片、链接、引用块、HR 等
-   工具栏一键切换源码 / 预览模式
-   预览模式下的所见即所得编辑

### P1（待实现）

-   Cmd+V 直接粘贴图片（自动写入 assets）
-   表格行列增删
-   Cmd+点击 链接由系统浏览器打开

## 文件结构与各文件作用

### 顶层

| 文件 | 作用 |
| --- | --- |
| `Package.swift` | SPM 构建配置。定义两个 target（`MarkdownCore` 和 `AropytEditor`），配置 Resources 处理规则，并通过 linker `-sectcreate __TEXT __info_plist` 把 Info.plist 嵌入可执行文件。**改 target / 资源 / 链接选项时改这里。** |
| `README.md` | 本文件。 |
| `ARCHITECTURE.md` | 架构设计、数据流、关键决策、P1 草图。设计层面的"为什么"。 |
| `CLAUDE.md` | 给 AI 协作者的项目指引：构建命令、目录约定、AppKit 陷阱清单、P0/P1 边界。 |
| `PROMPT.md` | 原始需求文档。功能优先级 P0/P1 来源。 |

### `Sources/MarkdownCore/`（纯 Swift，无 AppKit 依赖）

| 文件 | 作用 |
| --- | --- |
| `MarkdownRenderer.swift` | 把 markdown 字符串嵌入 HTML 模板返回完整 HTML 文档。包含 `<link>` CSS、`<script>` 引用 marked.js / highlight.js，以及内联 JS 调 `marked.parse` 渲染。**改预览页面样式（暗色模式、代码块外观、字体等）时改这里。** 字符串嵌入用 `JSONSerialization` 安全转义为 JS 字面量。 |

### `Sources/AropytEditor/`（App 主体，AppKit）

| 文件 | 作用 |
| --- | --- |
| `main.swift` | 程序入口。**第一行必须 `_ = AppDocumentController()`** —— 让 `NSDocumentController.shared` 返回我们的子类。然后构造 NSApp、设置 delegate、`run()`。 |
| `AppDelegate.swift` | NSApplicationDelegate。负责安装菜单栏（App / File / Edit / View / Window 五组）、决定最后窗口关闭时是否退出、决定启动时是否自动开 untitled 窗口。**想加菜单项 / 快捷键时改这里。** |
| `AppDocumentController.swift` | NSDocumentController 子类。硬编码 `documentClassNames`、`defaultType`、`documentClass(forType:)`、`typeForContents(of:)`，绕过脱 .app bundle 时 Info.plist 不被读取的问题。同时定制 Open 面板的允许文件类型。**想改打开文件时支持的扩展名时改这里。** |

### `Sources/AropytEditor/Document/`

| 文件 | 作用 |
| --- | --- |
| `MarkdownDocument.swift` | NSDocument 子类。**单一数据源**：所有 ViewController 都从 `document.text` 读写。负责文件读写（`read(from:ofType:)` / `data(ofType:)`，UTF-8 / UTF-16 兜底）、注册 undo（`updateText(_:actionName:)`）、文本变化时通过 `Notification` 广播给监听者。**改文档持久化逻辑、改文本变更通知、改 undo 行为时改这里。** 注意此文件内 `print(...)` 必须写 `Swift.print(...)`。 |

### `Sources/AropytEditor/Window/`

| 文件 | 作用 |
| --- | --- |
| `EditorWindowController.swift` | NSWindowController。在 `convenience init()` 里创建窗口对象，**不依赖 `windowDidLoad`**（用 `init(window:)` 时不会触发）；通过显式 `setup(document:)` 由 document 调用，绑定 contentViewController、安装 toolbar。同时实现 `NSToolbarDelegate` 提供"切换源码/预览"toolbar 按钮。**改窗口尺寸、标题、toolbar 内容时改这里。** |
| `MainViewController.swift` | 模式协调器。持有 `document` 引用、`sourceVC` 实例、懒加载的 `previewVC`，维护当前 `mode`。`toggleMode(_:)` 是切换入口（菜单和 toolbar 都连到这里）；切换时移除旧子 VC、嵌入新子 VC，并把最新文本同步到对方。监听 `markdownDocumentTextChanged` 通知实现外部变更同步。**改源码/预览之间的同步逻辑、模式切换行为时改这里。** |
| `SourceViewController.swift` | 源码模式 ViewController。在 `loadView()` 里手动构造 `NSScrollView` + `NSTextView`（必须设 `minSize/maxSize/isVerticallyResizable/textContainer` 等，否则可能空白），关闭所有自动替换/拼写检查/链接检测/富文本，使用等宽字体。`textDidChange` 回调把文本传给 `onTextChanged`，并调 `applyHighlighting()` 重新染色。**改编辑器字体、颜色、行为（如缩进、wrapping）时改这里。** |
| `PreviewViewController.swift` | 预览模式 ViewController。**懒加载 `webView`**：`load(markdown:)` 入口必须先 `_ = self.view` 触发 `loadView()` 才能访问 `webView`。`renderInternal` 调 `MarkdownRenderer.htmlDocument(for:)` 拿到 HTML，然后 `loadHTMLString(_:baseURL:)`（baseURL 指向 `Bundle.module.resourceURL`，让相对路径资源生效）。`WKNavigationDelegate` 拦截 `linkActivated`，用 `NSWorkspace.shared.open` 在系统浏览器打开。**改预览的 WebView 配置、链接打开行为时改这里。** |

### `Sources/AropytEditor/Highlighter/`

| 文件 | 作用 |
| --- | --- |
| `MarkdownHighlighter.swift` | 源码模式的语法高亮器。基于 `NSRegularExpression` 的 9 条规则（标题、引用、列表、代码块围栏、行内代码、粗体、斜体、链接、图片、删除线），对 `NSTextStorage` 设置 `.foregroundColor` 和 `.font` 属性。**想加新的高亮规则、改高亮颜色时改这里。** |

### `Sources/AropytEditor/Resources/`

| 文件 | 作用 |
| --- | --- |
| `Info.plist` | App 元信息。**通过 linker `-sectcreate` 嵌入**（不能作为 SPM 普通资源），所以在 `Package.swift` 的 `exclude:` 里排除。包含 `CFBundleDocumentTypes` 注册 `.md` 文件类型，以及 `NSDocumentClass = AropytEditor.MarkdownDocument`。**改 bundle id、版本号、文件类型支持时改这里**（同时记得改 `AppDocumentController` 里的硬编码）。 |
| `marked.umd.js` | 第三方 Markdown→HTML 解析器（marked v12）。被预览 HTML 的 `<script src>` 加载。**想升级 marked 时替换这个文件。** |
| `highlight.min.js` | 第三方代码块语法高亮库（highlight.js v11.9）。在预览 HTML 中调 `hljs.highlightElement` 高亮 `<pre><code>`。 |
| `github.min.css` | highlight.js 的 GitHub light 主题。通过 `media="(prefers-color-scheme: light)"` 仅亮色模式生效。 |
| `github-dark.min.css` | highlight.js 的 GitHub dark 主题。通过 `media="(prefers-color-scheme: dark)"` 仅暗色模式生效。 |
| `github-markdown.css` | GitHub 风格的 markdown body 样式（标题、列表、引用、表格等）。 |

## 环境要求

-   macOS 13+
-   Swift 6.x（Apple toolchain，`/usr/bin/swift` 即可）
-   不需要 Xcode 项目；如果 `xcode-select` 指向 Command Line Tools 也能编译

```sh
swift --version    # 应输出 swift-driver / Apple Swift 6.x
```

## 构建与运行

### 编译

```sh
swift build              # debug 构建
swift build -c release   # release 构建
```

### 运行

```sh
swift run AropytEditor
# 或直接跑产物
.build/debug/AropytEditor
```

启动后会自动出现一个空白 Markdown 文档窗口。

### 常用快捷键

| 操作 | 快捷键 |
| --- | --- |
| 新建文档 | `Cmd+N` |
| 打开文件 | `Cmd+O` |
| 保存 | `Cmd+S` |
| 切换源码 / 预览 | `Cmd+Shift+P` |
| 关闭窗口 | `Cmd+W` |

## 调试

由于不通过 .app bundle 启动，可直接 `print` / `Swift.print` 到终端。

```sh
swift build && .build/debug/AropytEditor
```

如需用 LLDB：

```sh
lldb .build/debug/AropytEditor
(lldb) run
```

要重置构建产物：

```sh
rm -rf .build
swift build
```

## 关键架构决策
[ARCHITECTURE.md](www.baidu.com)

详见 [ARCHITECTURE.md](ARCHITECTURE.md)。简短版：

-   **NSDocument 单一数据源**：所有编辑都经过 `MarkdownDocument.text`
-   **预览渲染本地化**：`marked.js` 和 `highlight.js` 打包在 `Resources/`，离线可用
-   **Info.plist 通过 linker 嵌入**：因为 SPM `.process("Resources")` 禁止把 Info.plist 当资源
-   **自定义 NSDocumentController**：脱 .app bundle 跑时让文档类型注册生效