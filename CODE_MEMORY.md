# AropytEditor Code Memory

本文件用于保持对当前项目的感知，避免 compact 或重开 thread 后重新完整读取项目代码。

## Memory 维护规则

- 本文件只维护三类信息：代码结构、项目进展、最近一次用户 `/goal` input。
- 开始处理新的 `/goal` 时，把用户原始输入写入“最近一次 /goal input”。
- 一个 goal 完成后，清空“最近一次 /goal input”，并把结果沉淀到“项目进展”或“代码结构”中。
- 每次 compact 后先读本文件，再决定还需要补读哪些源码或文档。
- 本文件不是完整开发日志；不要把已完成 goal 的 input 长期堆在这里。

## 最近一次 /goal input

无。当前没有进行中的 goal；已完成 goal 的结果已沉淀到下面的项目进展中。

## 项目概况

AropytEditor 是 macOS 本地 Markdown 编辑器，目标体验类似 Typora。项目使用 Swift + AppKit + Swift Package Manager，无 Xcode project。

构建 / 运行：

```sh
swift build
swift run AropytEditor
.build/debug/AropytEditor
```

用户偏好直接运行 `.build/debug/AropytEditor`。不要创建或依赖 `.xcodeproj`。

## 代码结构

- `Package.swift`：SPM 配置。包含 `MarkdownCore` library target 和 `AropytEditor` executable target；`Info.plist` 被 exclude，并通过 linker `-sectcreate __TEXT __info_plist` 嵌入。
- `Sources/MarkdownCore/`：纯 Swift 逻辑，不引入 AppKit。当前核心是 `MarkdownRenderer.swift`，负责生成 WebView 使用的完整 HTML 模板。
- `Sources/AropytEditor/main.swift`：程序入口。第一行必须 `_ = AppDocumentController()`，保证裸跑时 `NSDocumentController.shared` 是自定义 controller。
- `Sources/AropytEditor/AppDelegate.swift`：安装菜单栏、应用启动/退出行为、动态应用快捷键配置。
- `Sources/AropytEditor/AppDocumentController.swift`：自定义 `NSDocumentController`，硬编码 Markdown 文档类型、document class、Open panel 文件类型。
- `Sources/AropytEditor/Document/MarkdownDocument.swift`：`NSDocument` 子类，文档文本的单一数据源。负责读写、undo、变更通知。
- `Sources/AropytEditor/Window/EditorWindowController.swift`：窗口和 toolbar。用显式 `setup(document:)` 初始化，不依赖 `windowDidLoad`。
- `Sources/AropytEditor/Window/MainViewController.swift`：源码 / 预览模式协调器。负责 child VC 切换、文档同步、预览编辑回写防循环。
- `Sources/AropytEditor/Window/SourceViewController.swift`：源码模式，`NSTextView` + `NSScrollView` + 正则高亮。
- `Sources/AropytEditor/Window/PreviewViewController.swift`：预览模式，`WKWebView` 渲染、contenteditable 编辑、JS bridge、链接打开、格式化命令。
- `Sources/AropytEditor/Highlighter/MarkdownHighlighter.swift`：源码模式正则高亮，并给 Markdown 链接设置 `.link` attribute 以支持 Cmd+Click。
- `Sources/AropytEditor/Settings/`：Settings 窗口、Shortcuts、Theme、Help。`ShortcutManager` 是快捷键数据层。
- `Sources/AropytEditor/Resources/`：`marked.umd.js`、`highlight.min.js`、`katex.min.js`、`auto-render.min.js`、`katex.min.css`、`fonts/` KaTeX woff2 字体、`turndown.js`、`turndown-plugin-gfm.js`、GitHub CSS 主题、`Info.plist`。
- `package.sh`：release build、组装 `.app`、ad-hoc 签名、生成 DMG/PKG。
- `README.md`：功能、目录、构建、打包说明。
- `ARCHITECTURE.md`：架构设计、数据流、关键决策。
- `PROMPT.md`：原始需求。
- `JOURNAL.md`：历史开发日志。

`AGENTS.md` 和 `CLAUDE.md` 已删除，不再作为依据。

## 关键架构事实

### 文档模型

- `MarkdownDocument.text` 是唯一可信数据源，所有 ViewController 从这里读写。
- `read(from:ofType:)` 支持 UTF-8，失败后尝试 UTF-16。
- `data(ofType:)` 使用 UTF-8 保存。
- `updateText(_:actionName:)` 注册 undo，更新 `text`，调用 `updateChangeCount(.changeDone)`。
- `text` didSet 发送 `.markdownDocumentTextChanged` 通知。
- `NSDocument` 子类里如果需要打印，使用 `Swift.print(...)`，避免和 `NSDocument.print()` 歧义。

### 初始化和窗口

- 裸跑 `.build/debug/AropytEditor` 不是 `.app` bundle，因此必须在 `main.swift` 第一行实例化 `AppDocumentController`。
- `EditorWindowController` 通过 `init(window:)` 创建窗口，不能依赖 `windowDidLoad`。
- `MarkdownDocument.makeWindowControllers()` 中先 `addWindowController(wc)`，再显式调用 `wc.setup(document: self)`。
- `EditorWindowController.setup(document:)` 会显式触发 `MainViewController.view` 加载，再 `reloadFromDocument()`，避免首次打开文件时 source view 尚未创建。

### 源码 / 预览同步

- `MainViewController` 默认进入 `.source`。
- 切换到 preview 前，源码模式会把当前 `sourceVC.currentText` 写入 `document.text`。
- 预览编辑通过 `PreviewViewController.onMarkdownEdited` 回写 document。
- `isApplyingFromPreview` 用于避免预览编辑回写后 WebView 被重新 `loadHTMLString`，否则光标和滚动位置会丢。
- `SourceViewController.setText(_:)` 会触发自身 view 加载，保证 `textView` 创建后再写入文本。

### 源码模式

- `NSTextView` 必须设置 `minSize`、`maxSize`、`isVerticallyResizable`、`isHorizontallyResizable`、`autoresizingMask`、`textContainer.widthTracksTextView`、`textContainer.containerSize`，否则可能空白。
- 源码模式关闭富文本、自动替换、拼写纠正、自动链接检测和 data detection。
- `MarkdownHighlighter` 负责标题、引用、列表、代码、粗体、斜体、链接、图片、删除线的颜色和字体属性。

### 预览模式

- `PreviewViewController.webView` 懒加载；`load(markdown:)` 先 `_ = self.view`。
- `MarkdownRenderer.htmlDocument(for:)` 生成完整 HTML，加载本地 JS/CSS 并把原始 Markdown 用 JSON 字符串字面量安全嵌入。
- 预览模式用本地 KaTeX 渲染数学公式，支持 `$...$`、`$$...$$`、`\\(...\\)`、`\\[...\\]`。进入 `marked.parse` 前会保护完整数学片段，避免 `_`、`<`、`&` 或 `\\[` 被 Markdown 解析破坏。
- 预览 `<article>` 是 `contenteditable=true`；input 事件经 turndown 转回 Markdown，通过 `markdownChanged` message handler 回 Swift。
- `openLink` message handler 使用系统浏览器打开链接。
- `previewReady` 标记 WebView 可接收格式化命令。
- `PreviewViewController.resourceBaseURL()` 会选择实际包含 `marked.umd.js` 的目录，兼容 SwiftPM 裸跑和打包 app 的资源 bundle 布局。

## 项目进展

已实现：

- NSDocument 打开 / 新建 / 保存 Markdown。
- 源码模式编辑和语法高亮。
- 源码模式 Cmd+Click 打开链接。
- 预览模式 Markdown 渲染和代码高亮。
- 预览模式数学公式渲染（KaTeX，本地离线资源）。
- 预览模式 contenteditable 编辑，并通过 turndown 回写 Markdown。
- 预览模式 Cmd+Click 打开链接。
- toolbar 切换源码 / 预览。
- toolbar 格式化按钮：bold、italic、strikethrough、H1、H2、inline code、code block、unordered list、ordered list、blockquote。
- Settings：快捷键、主题、Help。
- 打包脚本 `package.sh`，可生成 `.app` 和 DMG/PKG。
- `CODE_MEMORY.md` 已取代旧的 `AGENTS.md` / `CLAUDE.md` 作为项目上下文依据。

最近重要修复：

- `113f993 Fix packaged preview rendering`：修复打包后预览模式显示原始 Markdown 的问题。核心修复是 `PreviewViewController.resourceBaseURL()` 按实际资源文件存在性选择 baseURL，并补强首次打开文件时 view 加载顺序。

待实现 / 待完善：

- Cmd+V 直接粘贴图片：从 pasteboard 取图片，写入文档旁 assets 目录，插入 Markdown image。
- 表格操作：行列插入 / 删除、对齐控制。
- `ShortcutAction` 只覆盖 bold / italic，没有覆盖 toolbar 里的全部格式化按钮。
- 相对图片路径目前主要依赖 WebView baseURL；后续做图片粘贴/资源管理时需要重新审视预览资源 URL 与文档目录 URL 的关系。

## 验证状态

最近一次已知验证：

- `swift build` 通过。
- `./package.sh dmg` 通过，生成 `dist/AropytEditor.app` 和 `dist/Aropyt-0.1.0.dmg`。
- `codesign --verify --deep --strict --verbose=2 dist/AropytEditor.app` 通过。
- 打包 app 内存在 `Contents/Resources/AropytEditor_AropytEditor.bundle/marked.umd.js`。
- 用户手动确认 `/Users/renxiao/Desktop/pptx/README.md` 打包后源码模式正常，预览模式也恢复正常。

## 开发约束

- 中文沟通，简洁直接，说明原因。
- 修改前先读当前文件，不依赖旧上下文。
- 手写改文件使用 `apply_patch`。
- `Sources/MarkdownCore/` 不引入 AppKit。
- 不要引入 Xcode project。
- 不要提前实现与当前任务无关的大块 P1 功能。
- 工作区可能有用户改动；不要回滚未确认的用户改动。
