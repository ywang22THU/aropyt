# AropytEditor Code Memory

本文件是后续开发的首要协作依据。每次 compact 之后，先阅读本文件，再继续工作。

## 当前 Goal

- 用户输入：现在模式切换似乎有大问题，我不知道是不是打包的结果，打包后的 /Users/renxiao/Desktop/pptx/README.md 都无法在预览模式下正常显示了。
- 当前状态：已完成，用户手动验证打包后的 app 打开 `/Users/renxiao/Desktop/pptx/README.md` 后，源码模式正常，切到预览模式也恢复正常。
- 本次修复：
  - `EditorWindowController.setup(document:)` 显式触发 `MainViewController.view` 加载，避免首次 `reloadFromDocument()` 早于源码 view 创建。
  - `MainViewController.reloadFromDocument()` 显式触发自身 view 加载。
  - `SourceViewController.setText(_:)` 显式触发自身 view 加载，确保 `textView` 已创建后再写入文档文本。
  - `PreviewViewController.renderInternal(markdown:)` 不再直接使用 `Bundle.module.resourceURL` 作为 WebView baseURL；新增资源目录探测逻辑，优先选择真正包含 `marked.umd.js` 的目录。
  - 资源目录探测覆盖 SwiftPM 裸跑 resource bundle、打包 app 的 `Contents/Resources/AropytEditor_AropytEditor.bundle`，以及 bundle 内 `Contents/Resources` 嵌套形态。
- 验证：
  - `swift build` 通过。
  - `./package.sh dmg` 通过，生成 `dist/AropytEditor.app` 和 `dist/Aropyt-0.1.0.dmg`。
  - `codesign --verify --deep --strict --verbose=2 dist/AropytEditor.app` 通过。
  - `test -f dist/AropytEditor.app/Contents/Resources/AropytEditor_AropytEditor.bundle/marked.umd.js` 通过。
  - 用户确认修复后预览模式已经正常。

## 已完成 Goal 记录

### 初始化 CODE_MEMORY

- 用户输入：初始化 MEMORY 文档，之后都用这个作为依据，agents.md 和 claude.md 已经过时，可以去掉，你需要根据代码和 architecture 来撰写 memory 文档。
- 当前状态：已完成并验证；`AGENTS.md` 和 `CLAUDE.md` 已按目标移除，README / ARCHITECTURE 已改为引用 `CODE_MEMORY.md`。
- 本次变更记录：
  - 新增 `CODE_MEMORY.md`，用当前代码和 `ARCHITECTURE.md` 整理项目事实、约束、进展和待办。
  - 删除过时的 `AGENTS.md`。
  - 删除过时的 `CLAUDE.md`。
  - 更新 `README.md` 和 `ARCHITECTURE.md` 中的旧协作文件引用，改为 `CODE_MEMORY.md`。

## 开发依据优先级

1. 当前代码和当前工作区状态。
2. 本文件 `CODE_MEMORY.md`。
3. `ARCHITECTURE.md` 的架构设计和关键决策。
4. `README.md` 的使用说明和功能清单。
5. `PROMPT.md` 的原始需求背景。

`AGENTS.md` 和 `CLAUDE.md` 已过时，不再作为依据。

## 项目概况

AropytEditor 是 macOS 本地 Markdown 编辑器，目标类似 Typora。技术栈是 Swift + AppKit + Swift Package Manager，无 Xcode project。

核心体验：

- 打开 / 新建 / 保存 Markdown 文档。
- 源码模式：`NSTextView` 原始 Markdown 编辑，带正则语法高亮。
- 预览模式：`WKWebView` + 本地 `marked.js` / `highlight.js` 渲染 CommonMark/GFM。
- 预览模式已支持 `contenteditable` 编辑，并通过 `turndown` 回写 Markdown。
- 源码 / 预览模式切换。
- Cmd+Click 打开链接。
- Settings 窗口支持快捷键配置、主题设置和 Help。

当前明确未完成：

- Cmd+V 直接粘贴图片并自动写入 assets。
- 表格行列增删、对齐等结构化表格编辑。

## 构建与运行

项目是纯 SPM。

```sh
swift build
swift run AropytEditor
.build/debug/AropytEditor
```

用户偏好直接运行 `.build/debug/AropytEditor`。

不要创建或依赖 `.xcodeproj`。

## 目录和模块

- `Package.swift`：SPM 配置。包含 `MarkdownCore` library target 和 `AropytEditor` executable target。
- `Sources/MarkdownCore/`：纯 Swift 逻辑，不引入 AppKit。当前核心文件是 `MarkdownRenderer.swift`。
- `Sources/AropytEditor/`：AppKit app 主体。
- `Sources/AropytEditor/Resources/`：JS/CSS/Info.plist 等资源。`Info.plist` 不作为普通 resource 处理，而是通过 linker 嵌入。
- `ARCHITECTURE.md`：架构和关键决策说明。
- `README.md`：功能、运行、打包说明。
- `JOURNAL.md`：历史开发日志。
- `PROMPT.md`：原始需求。

## 关键架构事实

### NSDocument 是单一数据源

`MarkdownDocument.text` 是文档文本的唯一可信数据源。所有 ViewController 从这里读写。

关键行为：

- `read(from:ofType:)` 支持 UTF-8，失败后尝试 UTF-16。
- `data(ofType:)` 使用 UTF-8 保存。
- `updateText(_:actionName:)` 注册 undo，更新 `text`，调用 `updateChangeCount(.changeDone)`。
- `text` didSet 通过 `.markdownDocumentTextChanged` 通知外部同步。

### 自定义 DocumentController

裸跑 `.build/debug/AropytEditor` 时不是 `.app` bundle，系统可能读不到 Info.plist 中的文档类型。

当前解法：

- `main.swift` 第一行必须 `_ = AppDocumentController()`。
- `AppDocumentController` 硬编码 document class、default type、文件类型判断和 Open 面板类型。

### Info.plist 嵌入

SPM `.process("Resources")` 不能把 `Info.plist` 当普通顶层资源处理。

当前解法在 `Package.swift`：

- executable target `exclude: ["Resources/Info.plist"]`。
- linkerSettings 使用 `-sectcreate __TEXT __info_plist Sources/AropytEditor/Resources/Info.plist` 嵌入。

### WindowController 初始化

不要依赖 `NSWindowController.windowDidLoad`。当前窗口由 `init(window:)` 路径创建，`windowDidLoad` 不会按预期触发。

当前模式：

- `EditorWindowController.convenience init()` 创建 `NSWindow`。
- `MarkdownDocument.makeWindowControllers()` 中先 `addWindowController(wc)`，再显式调用 `wc.setup(document: self)`。

### 源码 / 预览协调

`MainViewController` 是模式协调器。

关键状态：

- 默认 `mode = .source`。
- 持有 `sourceVC`。
- 懒加载 `previewVC`。
- 切换到 preview 时加载当前 `document.text`。
- 从 preview 编辑回写时使用 `isApplyingFromPreview` 避免 WebView reload 打断光标和滚动位置。

### 源码模式

`SourceViewController` 手动创建 `NSScrollView` + `NSTextView`。

必须保留的 AppKit 设置：

- `minSize` / `maxSize`
- `isVerticallyResizable = true`
- `isHorizontallyResizable = false`
- `autoresizingMask = [.width]`
- `textContainer?.widthTracksTextView = true`
- `textContainer?.containerSize` 高度为 `CGFloat.greatestFiniteMagnitude`

源码模式关闭自动替换、拼写纠正、链接检测、富文本，使用等宽字体。

`MarkdownHighlighter` 负责标题、引用、列表、代码、粗体、斜体、链接、图片、删除线的正则高亮，并手动给 Markdown 链接设置 `.link` attribute 以支持 Cmd+Click。

### 预览模式

`PreviewViewController` 使用懒加载 `WKWebView`。

关键点：

- `load(markdown:)` 先 `_ = self.view` 触发 `loadView()`。
- `renderInternal(markdown:)` 调 `MarkdownRenderer.htmlDocument(for:)`。
- `loadHTMLString(_:baseURL:)` 的 baseURL 指向 `Bundle.module.resourceURL` 或 bundleURL。
- JS bridge 接收：
  - `markdownChanged`：预览编辑后的 markdown 回写 Swift。
  - `openLink`：系统浏览器打开链接。
  - `previewReady`：标记 WebView 可接受格式化命令。

`MarkdownRenderer` 当前已经：

- 加载 `github-markdown.css`、`github.min.css`、`github-dark.min.css`。
- 加载 `marked.umd.js`、`highlight.min.js`、`turndown.js`、`turndown-plugin-gfm.js`。
- 使用 `JSONSerialization` 安全生成 JS string literal。
- 将 `<article id="content">` 设置为 `contenteditable=true`。
- 监听 input，debounce 150ms 后用 turndown 转回 markdown。
- 支持 Cmd+Click 链接，并给无 scheme 的链接补 `https://`。
- 暴露 `window.aropytApplyFormat(cmd)` 给 Swift toolbar / menu 调用。

### Settings 和快捷键

`SettingsWindowController` 是单例窗口。

`SettingsTabViewController` 当前包含：

- Shortcuts
- Theme
- Help

`ShortcutManager` 是快捷键数据层：

- `ShortcutAction` 当前包含 newDocument、openDocument、save、close、toggleMode、bold、italic、settings。
- 默认快捷键通过 enum 提供。
- 用户配置存入 UserDefaults。
- 变更通过 `AropytEditor.ShortcutManager.didChange` 通知菜单和 toolbar。

## 现有功能状态

已实现：

- NSDocument 打开 / 新建 / 保存 Markdown。
- 源码模式编辑。
- 源码模式语法高亮。
- 源码模式 Cmd+Click 链接。
- 预览模式 Markdown 渲染。
- 预览模式代码高亮。
- 预览模式 contenteditable 编辑。
- 预览编辑通过 turndown 回写 Markdown。
- 预览模式 Cmd+Click 链接。
- toolbar 切换源码 / 预览。
- toolbar 格式化按钮：bold、italic、strikethrough、H1、H2、inline code、code block、unordered list、ordered list、blockquote。
- Settings：快捷键、主题、Help。
- 打包脚本 `package.sh`。

待实现或待完善：

- 粘贴图片：从 pasteboard 取图片，写入文档旁 assets 目录，插入 Markdown image。
- 表格操作：行列插入 / 删除、对齐控制。
- `ShortcutAction` 只覆盖 bold / italic，没有覆盖 toolbar 里的所有格式化按钮。

## 开发约束

- 中文沟通，简洁直接，说明原因。
- 修改前先读当前文件，不依赖旧上下文。
- 手写改文件使用 `apply_patch`。
- `Sources/MarkdownCore/` 不引入 AppKit。
- `NSDocument` 子类内如果需要打印，写 `Swift.print(...)`。
- 不要引入 Xcode project。
- 不要提前实现与当前任务无关的大块 P1 功能。
- 工作区可能有用户改动；不要回滚未确认的用户改动。

## Goal 工作流

用户使用 `/goal` 后：

1. 先把用户输入和目标状态写入本文件。
2. 再开始修改代码或文档。
3. 修改完成后，把本次改动、验证命令、结果、剩余风险记录回本文件。
4. compact 后先读本文件，确认当前进展，再继续。

## 最近验证

- 本次初始化前确认 `git status --short` 为空。
- 本次初始化前确认 `CODE_MEMORY.md` 不存在。
- 本次初始化基于当前 `ARCHITECTURE.md`、`README.md`、`Package.swift`、`MarkdownDocument.swift`、`MainViewController.swift`、`MarkdownRenderer.swift` 以及当前文件列表。
- 本次初始化后用 `rg -n "AGENTS|CLAUDE|CODE_MEMORY" .` 检查旧文件引用，并将 README / ARCHITECTURE 的 `CLAUDE.md` 引用更新为 `CODE_MEMORY.md`。
- 最终文件列表中已没有 `AGENTS.md` / `CLAUDE.md`，有 `CODE_MEMORY.md`。
- 本次是文档依据调整，没有修改 Swift 源码；未运行 `swift build`。
