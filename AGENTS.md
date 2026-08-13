# AropytEditor Code Memory

本文件用于保持对当前项目的感知，避免 compact 或重开 thread 后重新完整读取项目代码。

## HARD RULES

- 本文件只维护三类信息：代码结构、项目进展、最近一次用户 `/goal` input。
- 开始处理新的 `/goal` 时，把用户原始输入写入“最近一次 /goal input”。
- 一个 goal 完成后，清空“最近一次 /goal input”，并把结果沉淀到“项目进展”或“代码结构”中。
- 执行 `/goal` 时按可独立验证的阶段逐步创建 commit；每个阶段验证通过后及时提交，不要把整个 goal 的改动积压到最后一次性提交。
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
- `Sources/MarkdownCore/`：纯 Swift 逻辑，不引入 AppKit。`LongDocumentPolicy.swift` 定义 512 KiB / 1 万行阈值；`MarkdownRenderer.swift` 生成普通或渐进预览 HTML。
- `Sources/AropytEditor/main.swift`：程序入口。第一行必须 `_ = AppDocumentController()`，保证裸跑时 `NSDocumentController.shared` 是自定义 controller。
- `Sources/AropytEditor/AppDelegate.swift`：安装菜单栏、应用启动/退出行为、动态应用快捷键配置。
- `Sources/AropytEditor/ApplicationLaunchCoordinator.swift`：根据通用设置选择启动文档，目标文件无效或打开失败时回退新建 untitled。
- `Sources/AropytEditor/AppDocumentController.swift`：自定义 `NSDocumentController`，硬编码 Markdown 文档类型、document class、Open panel 文件类型。
- `Sources/AropytEditor/Document/MarkdownDocument.swift`：`NSDocument` 子类，文档文本的单一数据源。负责读写、undo、变更通知。
- `Sources/AropytEditor/Window/EditorWindowController.swift`：窗口和 toolbar。用显式 `setup(document:)` 初始化，不依赖 `windowDidLoad`。
- `Sources/AropytEditor/Window/MainViewController.swift`：源码 / 预览模式协调器。负责 child VC 切换、文档同步、全文查找栏、异步 preview flush、保存与自动保存前准备。
- `Sources/AropytEditor/Window/FindBarView.swift`：源码 / 预览共用的悬浮查找 / 替换栏，以及全文查找和替换结果模型。
- `Sources/AropytEditor/Window/SourceViewController.swift`：源码模式，TextKit 非连续布局、可见区优先和后台分批正则高亮。
- `Sources/AropytEditor/Window/PreviewViewController.swift`：预览模式，`WKWebView` 渐进渲染、dirty / flush 状态、JS bridge、本地资源 scheme、链接和格式化命令。
- `Sources/AropytEditor/ImagePaste/`：图片剪贴板解析与粘贴服务。负责识别文件 URL / 位图、按偏好决定原路径或复制目录、安全避免覆盖同名文件、生成并可选 URL 转义 Markdown image。
- `Sources/AropytEditor/Workspace/`：打开目录工作区。`WorkspaceFileSystem` 负责过滤与真实磁盘操作，`WorkspaceTreeModel` 提供懒加载树，`WorkspaceSidebarViewController` 提供文件树和右键菜单，`WorkspaceContainerViewController` 提供左右 split view 与折叠动画。
- `Sources/AropytEditor/Highlighter/MarkdownHighlighter.swift`：支持范围高亮与段落范围扩展，并给 Markdown 链接设置 `.link` attribute。
- `Sources/AropytEditor/AutoSave/`：`AutoSavePreferences` 和按文档串行合并请求的 `AutoSaveManager`。
- `Sources/AropytEditor/Settings/`：Settings 窗口、General 启动行为与自动保存、Shortcuts、Theme、Syntax Preferences、Images、About。
- `Sources/AropytEditor/Resources/`：`marked.umd.js`、`highlight.min.js`、`katex.min.js`、`auto-render.min.js`、`katex.min.css`、`fonts/` KaTeX woff2 字体、`mermaid.min.js`、`turndown.js`、`turndown-plugin-gfm.js`、GitHub CSS 主题、`Info.plist`。
- `package.sh`：release build、组装 `.app`、ad-hoc 签名、生成 DMG/PKG。
- `README.md`：功能、目录、构建、打包说明。
- `ARCHITECTURE.md`：架构设计、数据流、关键决策。
- `PROMPT.md`：原始需求。
- `JOURNAL.md`：历史开发日志。

## 关键架构事实

### 文档模型

- `MarkdownDocument.text` 是唯一可信数据源，所有 ViewController 从这里读写。
- `read(from:ofType:)` 支持 UTF-8，失败后尝试 UTF-16。
- `data(ofType:)` 使用 UTF-8 保存。
- `reloadFromDisk()` 仅允许无未保存修改的已落盘文档重新读取，避免磁盘内容覆盖本地编辑。
- `updateText(_:actionName:)` 注册 undo，更新 `text`，调用 `updateChangeCount(.changeDone)`。
- `text` didSet 发送 `.markdownDocumentTextChanged` 通知。
- `MarkdownDocument.isLongDocument` 使用 UTF-8 512 KiB 或 1 万行的包含边界判定。
- `autosavesInPlace` 为 `false`；所有自动保存由 `AutoSaveManager` 协调，避免预览 dirty 时写入旧 Markdown。
- `NSDocument` 子类里如果需要打印，使用 `Swift.print(...)`，避免和 `NSDocument.print()` 歧义。

### 初始化和窗口

- 裸跑 `.build/debug/AropytEditor` 不是 `.app` bundle，因此必须在 `main.swift` 第一行实例化 `AppDocumentController`。
- General 可配置启动时创建新文件、重新打开上次关闭的文件或打开指定文件，默认创建新文件；`MarkdownDocument.close()` 记录上次关闭路径，任何恢复错误都回退创建 untitled。
- `EditorWindowController` 通过 `init(window:)` 创建窗口，不能依赖 `windowDidLoad`。
- `MarkdownDocument.makeWindowControllers()` 中先 `addWindowController(wc)`，再显式调用 `wc.setup(document: self)`。
- `EditorWindowController.setup(document:)` 会显式触发 `MainViewController.view` 加载，再 `reloadFromDocument()`，避免首次打开文件时 source view 尚未创建。

### 目录工作区

- File → Open Directory 创建独立 untitled `MarkdownDocument` 窗口并安装工作区侧边栏；同一目录已打开时复用原窗口。
- 文件树按目录优先排序，保留目录但仅显示 `.md` 文件；每一级在展开时才读取磁盘，刷新会丢弃目标目录的缓存并重新加载。
- 点击目录会展开，点击 Markdown 文件会在同一窗口右侧复用当前 `MarkdownDocument`；切换前先 flush 预览，并通过 `NSDocument.canClose` 处理未保存内容。
- 侧边栏右键菜单分为“新窗口打开｜新建 Markdown 文件/文件夹｜重命名/删除｜刷新｜访达显示/复制路径”，目录专属区域不会出现在文件菜单；删除使用确认 sheet，文件系统操作直接落盘。
- 侧边栏按钮仅在目录模式以 `.left` 的 `NSTitlebarAccessoryViewController` 插入，保证位于红绿灯右侧、文件标题左侧；按钮按窗口顶部 chrome 的实际高度纵向居中，展开/收起使用不同 SF Symbol，不显示 toast。
- 目录树使用普通 `NSSplitViewItem` 和 `.plain` outline 样式，不使用悬浮 sidebar 外观；左右区域之间只有 `.thin` 纵向分割线，折叠和展开使用 0.22 秒隐式动画。
- 目录树的整个 `NSScrollView` 通过布局约束与左右边框各保持 10 pt 距离（不能用 `contentInsets`，它不会可靠移动根级 disclosure/cell），使文件树两侧留白对称，根目录节点和展开箭头不会紧贴左边框；空白区域与 scroll view 都绘制 `controlBackgroundColor`。
- 活动文件或其父目录被重命名时同步更新 `document.fileURL`；被删除时清空活动文档，避免随后保存回已删除路径。

### 源码 / 预览同步

- `MainViewController` 默认进入 `.preview`，隐藏的 source view 不预先高亮长文档。
- 切换到 preview 前，源码模式会把当前 `sourceVC.currentText` 写入 `document.text`。
- 预览编辑通过 `PreviewViewController.onMarkdownEdited` 回写 document。
- `isApplyingFromPreview` 用于避免预览编辑回写后 WebView 被重新 `loadHTMLString`，否则光标和滚动位置会丢。
- `SourceViewController.setText(_:)` 会触发自身 view 加载，保证 `textView` 创建后再写入文本。
- 源码与预览切换时以视口顶部的 UTF-16 Markdown 偏移为共同锚点；源码用 TextKit glyph/character 映射，预览用顶层 token 的 `data-aropyt-source-start/end` 范围双向恢复。
- 数学保护占位符保存原始/保护后范围并转换偏移；新预览尚未完成渐进渲染时会暂存恢复请求，收到 `previewReady` 后执行。
- 长文档预览 dirty 时，切源码、Save、Save As、关闭窗口和应用退出都会先异步 flush；失败会停止后续写盘或关闭。

### 源码模式

- `NSTextView` 必须设置 `minSize`、`maxSize`、`isVerticallyResizable`、`isHorizontallyResizable`、`autoresizingMask`、`textContainer.widthTracksTextView`、`textContainer.containerSize`，否则可能空白。
- 源码 `NSTextView` 与预览共用正文宽度规则：左右边距至少 36 pt，窗口较宽时正文最大 920 pt 并居中；`lineFragmentPadding` 为 0。这一边距属于源码视图自身，会按编辑区域宽度动态更新。
- 源码段落样式使用 `lineHeightMultiple = 1.2` 增大段落内行距，不额外添加段前或段后间距；初始文本、局部重高亮和后续输入都保留该样式。
- 源码模式关闭富文本、自动替换、拼写纠正、自动链接检测和 data detection。
- `MarkdownHighlighter` 负责标题、引用、列表、代码、粗体、斜体、链接、图片、删除线的颜色和字体属性。
- `allowsNonContiguousLayout` 开启；长文档先高亮可见区，再以约 64 KiB 批次让出主线程，generation 会取消过期批次。
- 编辑只重置并高亮受影响段落；UTF-8 大小和行数使用局部 delta 维护，不在普通按键路径重新扫描全文。

### 预览模式

- `PreviewViewController.webView` 懒加载；`load(markdown:)` 先 `_ = self.view`。
- `MarkdownRenderer.htmlDocument(for:configuration:)` 生成完整 HTML；Markdown 和本地化 payload 同时做 JSON 与 script 上下文转义。
- 超长预览先 `marked.lexer`，首批最多 80 token / 64 KiB，后续按 12ms 预算空闲调度；渲染期间只读并显示进度，完成后恢复编辑。
- 预览模式用本地 KaTeX 渲染数学公式，默认支持 `$...$`、`$$...$$`；Syntax Preferences 可选择启用与 Markdown 转义冲突的 `\\(...\\)`、`\\[...\\]`，默认关闭。进入 `marked.parse` 前会保护启用的完整数学片段，并在 DOM 上保存原始源码、行内/行间类型和分隔符元数据，Turndown 据此无损回写公式。
- Syntax Preferences 可选择把 `math` fenced code block 渲染为行间公式，默认关闭；开启后使用原始 fenced Markdown 元数据保证预览编辑回写不丢格式。
- 预览代码块默认显示独立行号 gutter 并自动换行；Syntax Preferences 可分别关闭行号或关闭换行，关闭换行后超长单行使用横向滚动条。行号不进入 `<code>`，不会污染 Turndown 回写；自动换行时 gutter 会根据实际视觉折行插入空位，使后续源码行号保持对齐。
- Mermaid 通过 `IntersectionObserver` 在接近视口时才加载脚本和渲染；每张图有独立工具栏，直接调整 SVG `viewBox` 实现保持清晰的 50%–500% 矢量缩放与拖动平移，不使用 CSS transform 放大合成层；支持重置与 SVG 导出；`data-mermaid-source` 保留原始源码供 Turndown 回写。
- 普通预览 input 继续实时 Turndown；超长预览只标 dirty，`flushPreviewEdits` 才执行全文转换。
- `openLink` message handler 使用系统浏览器打开链接。
- `previewReady` 标记 WebView 可接收格式化命令。
- `PreviewViewController.resourceBaseURL()` 查找资源目录，再由只读 `aropyt-resource://` scheme 提供给 WebView，兼容 SwiftPM、测试与打包 app。

### 自动保存

- `AutoSaveMode` 为 On Change、After Delay、Never，默认 Never；延迟默认 1 秒并夹取到 0.5–60 秒。
- On Change 串行化保存并把运行期间的新变化合并成一次后续请求；After Delay 重置 debounce；失败保留 pending 状态等待后续重试。
- 设置通知即时更新所有已注册文档；长文档使用 On Change 时，General 与预览状态区都显示本地化性能警告。

### 全文查找与替换

- Edit → Find 提供 `Cmd+F`、`Cmd+R`、`Cmd+G`、`Cmd+Shift+G`；查找栏支持实时搜索、前后跳转、首尾循环和 Esc 关闭，左侧 disclosure 可展开替换输入框。
- 源码模式直接搜索整篇 Markdown，大小写不敏感，并显示当前匹配项 / 总匹配数；扫描过程不保存全部匹配范围，避免长文档产生大量临时内存。
- 预览模式使用 `WKWebView.find` 搜索渲染后的整页可见文本；WebKit 不提供匹配总数，因此仅在未命中时显示“无结果”。
- 长文档预览尚未完成时暂不搜索，收到 `previewReady` 后自动重试当前查询；切换源码 / 预览时也会在新模式重跑查询。
- 替换支持当前项和全部匹配项。源码模式通过 TextKit 编辑路径回写 Markdown；预览模式通过 DOM Range 修改渲染内容并触发现有 input / Turndown / dirty / flush 链路。

### 图片粘贴

- Cmd+V 在源码与预览编辑器焦点内识别 Finder 图片文件 URL 或剪贴板位图；普通文本粘贴继续交给系统。源码插入 Markdown，预览在当前 DOM 选区插入后通过既有 input / Turndown 链路回写。
- Images 设置提供原路径（默认且不复制）、当前目录 `./`、资源目录 `./assets/` 三种位置；资源目录名默认 `assets`，仅在资源目录模式可编辑，支持安全相对路径并实时反映到选项和实际目录。
- 复制模式要求文档已保存；位图统一写成 PNG，文件名冲突时追加 `-2` 等序号，不覆盖已有文件。原路径模式要求剪贴板带本地文件路径。
- 图片 Markdown URL 默认按 HTTP path 规则转义空格与 UTF-8 非 ASCII 字符，可在 Images 设置关闭。预览的只读 `aropyt-document://` scheme 只提供图片 MIME，可显示文档目录内外的本地图片，并用 `data-aropyt-image-source` 保证回写仍保留原 Markdown 路径。

## 项目进展

已实现：

- NSDocument 打开 / 新建 / 保存 Markdown。
- 源码模式编辑和语法高亮。
- 源码模式 Cmd+Click 打开链接。
- 预览模式 Markdown 渲染和代码高亮。
- 预览模式数学公式渲染（KaTeX，本地离线资源）。
- 预览模式 Mermaid 图表渲染（Mermaid，本地离线资源）。
- Mermaid 图表 50%–500% 缩放、拖动平移、重置和原生保存面板 SVG 导出。
- 预览模式 contenteditable 编辑，并通过 turndown 回写 Markdown。
- 预览模式 Cmd+Click 打开链接。
- toolbar 切换源码 / 预览。
- toolbar 格式化按钮：bold、italic、strikethrough、H1、H2、inline code、code block、unordered list、ordered list、blockquote。
- Settings：快捷键、主题、语法偏好、About（logo、版本号、权限说明）；“语法偏好 → 数学公式”可选择启用 `\\[...\\]`、`\\(...\\)` 或 `math` fenced code block，均默认关闭；“语法偏好 → 代码块”可控制行号与自动换行，二者默认开启。
- 预览编辑回写使用数学节点元数据保留 `$...$` 与 `$$...$$` 的原始分隔符和行内/行间类型。
- 可选的 `math` fenced code block 预览渲染与原格式回写。
- 预览代码块行号与自动换行偏好；二者默认开启，关闭自动换行时显示横向滚动条；行号测量会忽略 WebKit 在换行边界产生的零宽 Range 矩形，避免无折行代码出现空号和错位。
- 主题偏好由 `AppThemePreferences` 持久化，并在应用启动、创建窗口前恢复；重启后继续保持浅色或深色选择。
- 超长 Markdown 源码增量高亮与预览渐进加载（目标 2 MB / 5 万行）。
- 长文档预览 dirty / 异步 flush 与保存、关闭、退出一致性保护。
- General 自动保存设置：On Change、After Delay、Never。
- General 应用启动行为设置：默认创建新文件，也可恢复上次关闭文件或打开指定文件，失败时回退新建。
- Swift Testing 单元与 WebKit 集成测试套件。
- 源码 / 预览模式切换时双向同步视窗位置。
- Cmd+F 全文查找、Cmd+R 直接打开替换、替换当前项 / 全部替换，以及 Cmd+G / Cmd+Shift+G 前后循环跳转；同时支持源码与预览模式。
- File → 重新加载（Cmd+L）从磁盘刷新当前文档；存在未保存源码修改或未 flush 的预览修改时拒绝执行。
- File → 打开目录：左侧懒加载 `.md` 文件树、同窗文件切换、标题栏侧边栏按钮，以及分组右键菜单（新窗口打开、新建、重命名、确认删除、刷新、访达显示、复制路径）。
- Cmd+V 图片粘贴：默认使用本地图片原路径且不复制，也可复制到当前目录或可配置资源目录；支持源码 / 预览模式、同名保护和图片 URL 自动转义。
- 打包脚本 `package.sh`，可生成 `.app` 和 DMG/PKG。

待实现 / 待完善：

- 表格操作：行列插入 / 删除、对齐控制。
- `ShortcutAction` 只覆盖 bold / italic，没有覆盖 toolbar 里的全部格式化按钮。

## 验证状态

最近一次已知验证：

- 2026-08-13：修复预览代码块行号把 WebKit 换行边界零宽 Range 矩形误判成视觉折行的问题；截图中的 9 行 shell 代码回归用例与既有长行折行 / 关闭折行真实 WebKit 用例均通过。
- 2026-08-13：新增 Cmd+V 图片粘贴与 Images 设置后，偏好/UI、原路径不复制、当前/资源目录复制、嵌套资源目录、同名保护、UTF-8 URL 转义、Finder 文件 URL / 原始位图、源码插入和真实 WebKit 预览插入共 23 项聚焦测试通过；Xcode toolchain 构建通过。完整 97 项测试中 96 项通过，唯一失败仍是既有 2 MB / 5 万行 WebKit 完整预览 30 秒超时；普通预览、相对图片、视口同步及本轮图片粘贴用例均通过。
- 2026-08-12：修复目录树根节点仍贴左边框并统一左右留白后，测试直接读取根行 disclosure indicator 的实际渲染坐标，并量取滚动区域左右边距，确认两侧均为 10 pt；工作区侧边栏 9 项、工作区窗口 2 项聚焦测试通过。此前完整 78 项测试中 76 项通过：既有 2 MB / 5 万行 WebKit 完整预览仍于 30 秒超时，普通文档视口同步用例也超时；后者单独复跑仍失败，与本次仅涉及侧边栏布局的改动无代码交集。
- 2026-08-12：移除侧边栏切换 toast、按窗口顶部 chrome 动态纵向居中标题栏按钮，并给目录树根节点增加 10 pt 左侧 inset 后，工作区窗口 2 项聚焦测试通过；Xcode toolchain 构建通过。完整 77 项测试中 76 项通过，唯一失败仍是既有 2 MB / 5 万行 WebKit 完整预览 30 秒超时；源码视口同步和局部高亮性能用例通过。
- 2026-08-12：修正目录工作区 UI/UX 后，标题栏 `.left` accessory 位置、普通 split item + thin divider + plain outline、0.22 秒折叠/展开动画和源码左右 28 pt 边距共 3 项聚焦测试通过；Xcode toolchain 构建通过。完整 77 项测试中 76 项通过，唯一失败仍是既有 2 MB / 5 万行 WebKit 完整预览 30 秒超时；源码视口同步和局部高亮性能用例通过。
- 2026-08-12：新增打开目录工作区后，目录过滤/排序/刷新/落盘操作、菜单分组与目录专属项、删除确认、目录展开/同窗文件加载、活动路径同步、新窗口动作/复制路径、标题栏按钮/状态 icon/toast 共 15 项聚焦测试通过；Xcode toolchain 构建通过。完整 76 项测试中 75 项通过；唯一失败仍是既有 2 MB / 5 万行 WebKit 渐进预览用例（首批约 1.046 秒、略超 1 秒门槛，完整预览仍于 30 秒超时）；本轮局部高亮性能用例通过。
- 2026-08-12：新增应用启动行为设置后，偏好、General UI、启动选择、失败回退和关闭文件记录共 11 项聚焦测试通过。完整 61 项测试中 59 项通过；既有 2 MB / 5 万行 WebKit 渐进预览用例仍超时，既有局部高亮性能用例在当前机器为约 52 ms、略超 50 ms 门槛。
- 2026-08-12：新增 `math` fenced code block、代码行号和自动换行语法偏好后，Xcode toolchain 构建通过；默认值/持久化、设置 UI、数学代码块渲染与回写、代码行号/折行/横向滚动及回写测试通过。完整 50 项测试中 49 项通过，既有 2 MB / 5 万行 WebKit 渐进预览用例仍于 30 秒超时。
- 2026-08-12：新增数学公式元数据回写和 Syntax Preferences 后，Xcode toolchain 构建通过；美元公式回写、反斜杠公式开关、偏好持久化和设置 UI 共 10 项聚焦测试通过。完整 47 项测试中 46 项通过，既有 2 MB / 5 万行 WebKit 渐进预览用例仍于 30 秒超时。
- 2026-08-11：新增磁盘重新加载与冲突保护后，Xcode toolchain 构建通过；重新加载、未保存修改冲突和未命名文档 3 项测试通过。
- 2026-08-11：新增全文查找与替换后，Xcode toolchain 构建通过；源码查找 / 替换 5 项和真实 WebKit 预览查找 / 替换用例通过。完整 38 项测试中 37 项通过，既有 2 MB / 5 万行 WebKit 渐进预览用例仍于 30 秒超时。
- 2026-08-03：修复主题重启恢复后，Xcode toolchain `swift build --disable-sandbox` 通过；`AppThemePreferencesTests` 2 项通过。完整 31 项测试中主题与其他 30 项通过，既有 2 MB / 5 万行 WebKit 渐进预览用例在当前环境下仍于 30 秒超时。
- 2026-07-20：Mermaid 缩放由 CSS transform 改为 SVG `viewBox` 后，Xcode toolchain `swift test --disable-sandbox` 全部 29 项通过；真实 WebKit 用例验证 500% 时 `viewBox` 为原始范围的 1/5、拖动修改 `viewBox` 坐标且画布无 CSS transform。
- 2026-07-20：Xcode toolchain `swift test --disable-sandbox` 全部 29 项通过；新增真实 WebKit Mermaid 缩放边界、拖动、重置、SVG 导出与 Turndown 回写测试。
- 2026-07-20：Xcode toolchain `swift build --disable-sandbox` 通过。
- 2026-07-17：Xcode toolchain `swift test --disable-sandbox` 全部 28 项通过；新增普通/超长文档双向视窗同步测试，覆盖中文、emoji 与数学公式偏移。
- 2026-07-16：Xcode toolchain `swift test --disable-sandbox` 全部 26 项通过；包括真实 WebKit 的 2 MB / 5 万行、复杂块边界、Mermaid 懒渲染、generation 取消、Cmd+S / 切源码前 flush 落盘、关闭失败保护和普通文档实时回写。
- 2 MB / 5 万行集成用例首批内容在 1 秒目标内出现，完整预览随后完成并与整篇渲染结果一致。
- 源码局部按键高亮低于 50ms、64 KiB 后台批次低于 100ms 的测试通过。
- 2026-07-16：`xcrun swift build --disable-sandbox` 通过。
- 2026-06-14：Settings 的 Help 替换为 About 后，`swift build` 通过。
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
- 由 Codex 创建或修改 commit 时，commit message 必须符合 Conventional Commits，例如 `feat: add KaTeX math rendering`，不要使用无类型前缀的裸消息。
