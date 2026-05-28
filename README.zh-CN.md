# Crux

*一款面向 macOS（兼容 iPad / iPhone）的 AI 原生 EPUB 阅读工作台，使用 SwiftUI 构建。*

[English README](./README.md)

Crux 把一本 EPUB 变成你可以*共同思考*的对象。划选段落，AI 对话即以旁注的形式在原文一侧展开；继续追问、随时切换模型（云端或完全本地），整段对话都会被写回这条高亮的批注里。书库内容会建入 Spotlight 索引——从系统搜索里点开结果，就能直接落到阅读器中那一段。所有较长的 AI 回复均按 token 逐字流式渲染，可用 `⌘.` 立即取消，也可重新生成、复制或通过系统分享菜单转发。高亮、书签、对话、阅读会话、连续阅读天数、阅读目标全部是头等公民——并且都能导出。

![书库 — 继续阅读](Screenshots/Crux%202026-05-24%20at%2016.33.06%402x.jpg)

---

## 核心亮点

- **以高亮为锚的 AI 对话。** 划选文本 → 一条 AI 旁注会沿着段落流式展开释义；可持续追问，对话按高亮粒度保存进本书的批注里。
- **六大模型，统一接口。** Claude（Anthropic）、OpenAI、任意 OpenAI 兼容端点、**Ollama**、**LM Studio**，以及完全本地的 **Apple Intelligence**（Foundation Models，macOS 26 / iOS 18.4+）。所有模型共享同一套流式、取消与重试语义。
- **章级 AI 分析。** 工具栏 **Ask AI** 菜单提供预设分析（章节概要、主题与意象、疑难段落、讨论问题）以及任意自定义问题，结果可一键保存为 `.analysis` 书签。
- **五种语气 + 自定义提示词。** Scholarly（学术）、Casual（随性）、Socratic（苏格拉底）、Minimalist（极简）、Technical（技术）。全局切换；通过 `AIRequestOptions.systemPrompt` 注入到每一个模型。
- **真实 EPUB 渲染。** WKWebView 以你设定的字体、字号、行距和主题渲染章节。**基于 CFI 的位置恢复**确保你重开应用、切换主题甚至跨设备都能落到原段落。
- **可扩展的书库。** 封面网格 + 紧凑列表；多维过滤（阅读状态 / 作者 / 合集 / 出版年份 / 语言 / 标签）；色彩标签的合集；拖拽批量导入并逐文件显示进度；多窗口阅读。
- **可导出的知识。** 批注支持 Markdown、HTML、JSON、纯文本、CSV、BibTeX、PDF，以及可无损合并回来的 `.cruxnotes` 离线包。
- **阅读生活。** 会话、连续阅读天数（当前 / 最佳 / 总天数）、按周期的阅读目标（日 / 周 / 月 / 年）、成就、基于 Swift Charts 的活动视图。
- **优雅适配 Liquid Glass。** 新系统启用 macOS 26 Liquid Glass，旧系统（macOS 14–25）自动回退到原生 Materials —— 无需为版本分裂代码路径。
- **可信赖。** API Key 走系统 Keychain；批注采用原子写入 + `.bak` 回滚；ATS 仅放行 localhost 的明文 HTTP；启用应用沙盒与 JIT WebKit 授权。

---

## 截图

### 阅读器 — 旁注式 AI 对话与划线高亮

每条高亮都拥有一段独立的 AI 旁注。AI 输出按 token 流式渲染；滚动时当前段落始终保持定位；对话可继续追问，全部存进本书的批注。

![阅读器与旁注 AI 对话](Screenshots/Crux%202026-05-24%20at%2016.32.44%402x.jpg)

### 书库 — 继续阅读

以封面为主的书库视图，展示每本书的阅读进度与完成徽章，支持拖拽导入；右键菜单含 *在新窗口中打开*、*显示详情*、*在 Finder 中显示*、*合集*、*移除* 等；常驻搜索框同时检索标题、作者、主题与标签。

![书库视图](Screenshots/Crux%202026-05-24%20at%2016.33.06%402x.jpg)

### 设置 → AI 模型

可并行配置多个模型。当前激活的模型会显示 `ACTIVE` 标识；本地模型（Apple Intelligence、Ollama、LM Studio）带有盾形徽章，断网时也不会触发只对云端模型显示的「Offline」提示。*Refresh installed models* 会通过 Ollama 的 `/api/tags` 与 LM Studio 的 `/v1/models` 自动发现本地模型。

![设置 → AI 模型](Screenshots/Crux%202026-05-24%20at%2016.33.14%402x.jpg)

### 设置 → AI 提示词

内置五种系统提示词预设外加自定义槽位。自定义可以从任意预设导入作为初始模板。激活的提示词通过 `AIRequestOptions.systemPrompt` 注入到每一个模型，保证语气统一。

![设置 → AI 提示词](Screenshots/Crux%202026-05-24%20at%2016.33.27%402x.jpg)

---

## 功能巡览

### 阅读与 WebKit 引擎

- **WKWebView + JS 桥。** `Resources/Reader/` 内的一组 JavaScript 模块会在加载时注入：`cfi.js`（CFI 生成与查找）、`highlighter.js`（绘制高亮、点击处理、`scrollToCFI`）、`viewport-tracker.js`（滚动时上报最顶部可见元素的 CFI）、`search.js`（章内查找）、`margin-notes.js`（带碰撞检测的旁注栏），以及平台相关的 `selection-macos.js` / `selection-ios.js`。
- **基于 CFI 的位置持久化。** 位置以 EPUB 规范 Canonical Fragment Identifier（如 `/4/2/1:42`）保存——一组以 1 起始、沿 DOM 路径递增的索引——在每次滚动时写入。重开应用会回到原元素；若 CFI 失效则回退到滚动百分比。
- **多色高亮 + 对话。** 黄 / 绿 / 蓝 / 粉 / 橙。每条高亮存有 CFI 范围、选中文本、前后语境、可选批注、分类（Quote / Analysis / Question / Important / Reference / Definition / Example / Personal / Other）、标签，以及一组 AI 对话。
- **章内查找 + 全书检索。** `CruxSearch` 在已渲染的章节里高亮匹配；`BookSearchIndex` 维护每本书的纯文本索引（开书时预热），支持跨章节检索并附带语境摘录。
- **文本朗读。** AVSpeechSynthesizer，TTS 面板可调语速与音调；朗读到的当前词会被即时高亮。
- **词典查询。** 选中单词调用系统词典。
- **引用格式化。** 高亮与对话可导出为 Markdown、HTML、PDF 或 BibTeX，包含书名、作者、出版日期、章节与位置。

### AI：模型、提示词、对话

- **全员流式。** Claude 与 OpenAI 使用 SSE（`content_block_delta` / `choices[].delta.content`）；Ollama 使用 JSONL；LM Studio 使用 OpenAI 兼容 SSE；Apple Intelligence 借 Foundation Models 的 partial token 流式输出。所有模型都对 UI 暴露同一个 `AsyncThrowingStream<String, Error>`，token 写入 `streamingText` 后实时渲染。
- **取消。** 当前任务保存在 `ThreadPanelState.activeTask`。`⌘.`（或 **Stop** 按钮）即可取消，取消会沿 `AsyncThrowingStream` 一路传递到底层 `URLSessionTask`，已生成的局部回复被丢弃。
- **指数退避重试。** 临时性错误（超时、408 / 429 / 5xx、URLSession transient code）由 `RetryPolicy` 自动重试 —— 0.8 s → 1.6 s → 3.2 s，封顶 15 s，最多 3 次。**流式过程中的错误不会自动重试**（避免重复输出）。
- **重新生成。** 悬停在最后一条 AI 回复上 → **Regenerate** 会弹出最后的消息对，并以当前提示词预设重新发起。
- **保存章节洞察。** 章级分析默认是临时的；一键即可固定为 `.analysis` 书签，配有保存确认动画。
- **原生分享。** AI 回复在 macOS 上经 `NSSharingServicePicker` 分享——备忘录、邮件、Messages、提醒事项等全部可用。
- **笔记模板。** 在批注输入时一键插入六种结构化脚手架：人物分析、主题、引用、提问、关联、词汇。

### 书库与组织

- **两种视图。** 封面网格与紧凑列表，可按标题 / 作者 / 添加日期 / 最近阅读 / 阅读进度排序。
- **多维筛选。** 阅读状态（未开始 / 阅读中 / 已读完）、作者、合集、出版年份区间、语言、出版社、主题、标签。
- **合集。** 色彩标签的文件夹式分组，支持拖拽排序与双向关系；行内即可看到书数。
- **继续阅读。** 书库首屏展示最近五本未完成的书。
- **批量导入。** 拖入一整个 EPUB 文件夹，`BatchImportProgressView` 显示逐文件状态（待处理 / 导入中 / 成功 / 失败）。
- **在 Finder 中显示。** 任意书籍右键即可定位到 EPUB 文件。
- **多窗口。** `BookWindowScene` 让每本书独占一个窗口，便于并排阅读或同时标注两本书。

### 批注、笔记、书签

- **HighlightsView。** 内嵌对话展开、强调色渐变、滑动删除、导出工具栏。
- **NotesView。** 左侧高亮列表 + 右侧详情的双栏布局；统计条（高亮 / 对话 / 笔记数）；带搜索与过滤（仅含对话 / 仅含笔记 / 全部）。
- **BookmarksView。** 显示章节标题、滚动百分比、可选笔记，并支持「跳转到此处」。
- **原子写入 + 回滚。** 批注以 JSON 与书并排存储，写入流程是三步：`tmp → 旋转为 .bak → rename`。任意一步崩溃均可在下次加载时由 `.bak` 恢复。
- **批注导出。** Markdown、HTML（带严格 CSP 的样式）、JSON、纯文本、CSV（按消息分行）以及 `.cruxnotes` —— 自描述格式，含 `formatVersion`、书籍元数据，按 id 合并导入并跳过重复。

### 阅读生活：统计、连续天数、目标

- **会话。** 按书记录会话的时长、章节范围、页数；可在设置里关闭。
- **连续阅读天数。** 当前、最佳、总天数；火焰图标；`AchievementChecker` 触发奖项（如 *Week Streak*、*Night Owl*、*Marathon Reader*）。
- **目标。** 日 / 周 / 月 / 年，带动效进度环，并保留历史成就。
- **统计。** 基于 Swift Charts 按天聚合的柱状图；区间选择器（周 / 月 / 年）；总阅读时长、完读书数、会话次数、平均会话时长卡片。
- **阅读时长估算。** 每分钟 220 词的基准，先剥 HTML 再计数，结果缓存到 `StoredBook.cachedReadingMinutes`，避免每次刷新书库都重新解析。

### 主题与排版

- **六种主题。** 浅色、深色、跟随系统、Sepia、夜间，以及一款对比度 >21:1 的高对比主题（WCAG AAA）。
- **阅读器控件。** 字体（System、Georgia、Garamond 等）、字号（10–24pt）、行高（1.4–2.0）、段落间距（0.5–2.0em）、页边距（20–120px）。
- **主题即时注入。** 主题切换通过 WebView 的 CSS 变量传递，无需重新加载。

### macOS 集成

- **Spotlight。** 书籍以 `NSUserActivity` 形式 donate，开启 `isEligibleForSearch` 与 `isEligibleForHandoff`；activity 的 identifier 携带书籍 UUID，Spotlight 会学习再访问频次，搜索结果点开后直接定位到阅读器。
- **接力（Handoff）。** 通过 activity continuation 在另一台设备上继续阅读。
- **Liquid Glass。** `LiquidGlass.swift` 暴露 `cruxGlassCard`、`cruxGlassFloating`、`cruxGlassBar`、`cruxGlassButton`、`cruxScrollEdgeSoft` 等修饰符：可用时启用 macOS 26 的玻璃效果，否则在 macOS 14–25 上回退到 `.regularMaterial` / `.thickMaterial` / `.bar` 并加上 hairline 边框。
- **快捷键。** 覆盖书库、阅读、查找、批注、窗口管理的约 30 个快捷键（⌘L 目录、⌘B 书签、⌘F 查找、⌘⇧S 统计、⌘⇧G 目标、⌘⇧T 连续天数、⌘H 确认高亮、⌘A 询问 AI、⌘. 取消）。

### 无障碍

- 全应用尊重系统的 **减弱动态效果**：欢迎流程的转场、行的悬停动画、高亮特效都会读取 `\.accessibilityReduceMotion`。
- **高对比** 主题以 WCAG AAA 对比度为低视力读者准备。
- 工具栏 `.help()` 描述符与较大命中区域（`.contentShape(Rectangle())`）让图标按钮对屏幕阅读器友好。

---

## 架构

### 技术栈

- **SwiftUI** 一份代码同时支持 **macOS 14+** 与 **iOS 17+**，并在运行时按需启用 **macOS 26 / iOS 18.4** 特性（Liquid Glass、Apple Intelligence Foundation Models）。
- **Swift 5.9 / Toolchain 6.2**，使用 [`xcodegen`](https://github.com/yonaskolb/XcodeGen) 生成 `.xcodeproj`。
- **SwiftData** 管理书库、设置、AI 模型配置与阅读会话。
- **WKWebView** 渲染章节内容，通过六个 `WKScriptMessageHandler` 桥接到 Swift。
- **CoreSpotlight** 用于 Spotlight 索引；**NSUserActivity** 用于接力与 Recents。
- **Foundation Models** 用于 Apple Intelligence 的本地推理。
- **Swift Charts** 用于统计视图。
- 唯一一项 SPM 依赖：[`swift-markdown-ui`](https://github.com/gonzalezreal/swift-markdown-ui)，用于渲染 AI 回复中的 Markdown。

### 分层设计

```
Views（SwiftUI）
  ↓ read
@Observable 状态（AppState、ThemeManager、ThreadPanelState、NotesViewModel）
  ↓ call
Services（actor + Sendable 值类型）
  ↓ own
持久化（SwiftData • 文件系统 • Keychain）
```

依赖严格自上而下。Services 永远不引用 Views；WebKit 阅读器仅通过命名 JS 消息处理器回到 Swift，从不共享可变状态。

### 并发模型

- **基于 actor 的 I/O。** `BookStorage`、`EPUBParser`、`AIProviderManager`、每一个具体的 `AIProvider`（`ClaudeProvider`、`OpenAIProvider`、`OllamaProvider`、`LMStudioProvider`、`AppleIntelligenceProvider`、`CustomProvider`）、`CoverImageCache` 与 `KeychainService` 均为 `actor` —— 文件系统、网络、Keychain 访问从结构上即无数据竞争。
- **`@MainActor @Observable` 的 UI 状态。** `AppState`、`ThreadPanelState`、`ErrorHandler`、`ThemeManager`、`NetworkMonitor` 都在主 actor 上，视图读取状态无需 suspension point。
- **流式。** 模型对外暴露 `AsyncThrowingStream<String, Error>`；取消会沿流传递到底层 `URLSessionTask`。
- **重试边界。** `RetryPolicy` 仅包裹非流式调用；流式中的错误直接抛到用户面前，不会偷偷重发。

### 数据层

**SwiftData（`@Model`）**
- `StoredBook` —— 书库条目：标题、作者、章节、进度、`scrollPosition`、`lastReadingCFI`、封面缓存、合集关系、`cachedReadingMinutes`。
- `BookCollection` —— 色彩标签的文件夹，与 `books` 双向关系。
- `ReadingSession` —— 单次阅读会话：开始 / 结束 / 时长 / 章节区间 / 页数。
- `AppSettings` —— 单例：主题、字体、页边距、书库视图与排序、当前模型 id、自定义提示词、高亮色板、各类开关。
- `AIProviderConfig` —— 模型身份（name、type、baseURL、model）。**API Key 不在 SwiftData**，而在 Keychain，按模型 UUID 索引。

**运行时值类型（内存）**
- `Book`、`Chapter`、`BookMetadata` —— 打开阅读器时即时从 EPUB 解析（解析很轻，不缓存）。

**按书 JSON（原子）**
- `BookAnnotations { highlights: [Highlight], bookmarks: [Bookmark], updatedAt }` 写入 `Documents/Annotations/<uuid>.json`，过程是 `tmp → 旋转为 .bak → rename`。崩溃后下次加载会自动从 `.bak` 恢复。
- `Highlight` 携带 `CFIRange`、选中文本、前后语境、可选批注、`AnnotationCategory`（9 项枚举）、标签、颜色，以及 `threads: [AIThread]`（每条消息含角色 + Markdown 内容）。

### WebKit 阅读器引擎

| 文件 | 角色 |
|---|---|
| `reader-template.html` + `reader.css` | 容器、阅读器样式、用于主题 / 字体 / 间距的 CSS 变量 |
| `selection-macos.js` / `selection-ios.js` | 上报文本选择，附带 CFI 和 500 字符语境，经 `webkit.messageHandlers.textSelection` 通信 |
| `viewport-tracker.js` | 滚动时上报最顶部可见元素的 CFI 与滚动位置 |
| `highlighter.js` | 把已存的高亮绘制为 `<span class="crux-highlight">`，注册点击处理，提供 `scrollToCFI` |
| `search.js` | 章内查找，使用 TreeWalker 与正则转义，支持上一项 / 下一项 |
| `cfi.js` | EPUB 规范的 Canonical Fragment Identifier 生成与按路径回溯 |
| `margin-notes.js` | 旁注栏 UI、碰撞检测、AI 状态（「Analyzing…」）、追问输入条 |

### 服务层（节选）

| 服务 | 职责 |
|---|---|
| `EPUBParser` | 纯 Swift 实现的 EPUB 2/3 解析，含对损坏 XML 的回退 |
| `BookStorage` | 按书的文件布局、原子化批注写入 + `.bak` 回滚 |
| `LibraryBackupService` | 版本化的 JSON 整体备份，含 skip / overwrite / keep-newer 合并策略 |
| `AIProviderManager` / `AIProvider` | 6 种模型后端的统一抽象 + 重试编排 |
| `RetryPolicy` | 临时错误的指数退避分类器 |
| `BookSearchIndex` | 每本书的纯文本索引，开书时预热 |
| `CoverImageCache` | 基于 actor + `NSCache` 的封面缩略图缓存（上限 200 条 / 64 MB） |
| `SpotlightIndexer` | `CSSearchableIndex` 增删 + 冷启动对账 + NSUserActivity donate |
| `KeychainService` | 模型 API Key 在 Keychain 中的封装 |
| `NetworkMonitor` | 基于 `NWPathMonitor` 的连通性 → AI 面板的「Offline」标识 |
| `LocalModelDiscovery` | 把 Ollama `/api/tags` 与 LM Studio `/v1/models` 归一化为同一份模型列表 |
| `ReadingSessionManager` | 会话、连续天数、统计、按周期的目标进度 |
| `ReadingTimeEstimator` | 220 wpm 估算，剥 HTML，按书缓存 |
| `CitationFormatter` | 高亮与对话导出为 Markdown / HTML / PDF / BibTeX |
| `CruxNotesIO` | `.cruxnotes` 离线包导入 / 导出，含版本校验、合并、去重 |
| `ThemeManager` | 监听 `AppSettings.theme`；推送 ColorScheme + 注入 CSS 变量 |
| `ErrorHandler` | 单一 `@Observable`，按严重程度分发 toast 与 alert |
| `AppLog` | 分类的 `os.Logger` 通道：parser、ai、storage、security、errors、data、reader、ui |

完整的分层概览、「应该把代码加到哪里」速查表与决策记录见 [`ARCHITECTURE.md`](./ARCHITECTURE.md)。

---

## 工程结构

```
Shared/
├── Models/           SwiftData 实体 + 值类型（Book、Annotations、AppSettings、AIProviderConfig、NoteTemplate 等）
├── Services/         actor 与值类型 —— AI 模型、EPUB 解析器、存储、索引、重试、Spotlight、日志
├── ViewModels/       响应式 view-models（NotesViewModel 等）
├── Views/
│   ├── Library/      拆分后的书库行 / 卡片子视图
│   ├── Reader/       阅读器子视图（ProgressScrubber、TTSControlPanel 等）
│   ├── ReaderView.swift、LibraryView.swift、ThreadPanel.swift 等
│   └── LiquidGlass.swift
└── CruxApp.swift     @main 场景树、命令、NSUserActivity 接力
Resources/
└── Reader/           注入到 WebView 的 JS 模块 + CSS + HTML 容器
iOS/
└── …               平台入口与 app delegate
macOS/
└── …               平台入口、app delegate、AppKit 桥接
Tests/                EPUBParser、BookStorageError、CitationFormatter、AIPromptPreset、ReadingTimeEstimator、BookSearchIndex、Annotations、ViewportTracking、CruxNotesBundle、LocalProviderURL
UITests/
project.yml           xcodegen 工程描述
```

---

## 构建与运行

```bash
# 从 project.yml 生成 Xcode 工程
xcodegen generate

# 构建 macOS 版本
xcodebuild -scheme Crux_macOS -destination 'platform=macOS' \
           -derivedDataPath ./DerivedData build

# 运行测试
xcodebuild -scheme Crux_macOS -destination 'platform=macOS' test

# 启动构建好的应用
open DerivedData/Build/Products/Debug/Crux.app
```

**环境要求**

- Xcode 15 或更高 —— 编译 Liquid Glass 与 Apple Intelligence 代码路径需要 Xcode 26 SDK（运行时由 `#available` 守卫）。
- macOS 14.0+ 部署目标（macOS 26 特性在运行时按需启用）。
- iPad / iPhone 构建需 iOS 17.0+。
- [`xcodegen`](https://github.com/yonaskolb/XcodeGen) 用于工程生成。

---

## 隐私与安全

- **API Key 存放于 macOS Keychain**（`com.crux.aiProviders`，按模型 UUID 索引，`kSecAttrAccessibleAfterFirstUnlock`）。老版本基于 UserDefaults 的存储会在首次启动时自动迁移。
- **本地模型带有盾形徽章。** Apple Intelligence、Ollama、LM Studio 不会离开你的机器，也不会显示「Offline」提示。
- **批注完全本地。** 与书并排存为 JSON；导出的 HTML 会经 `htmlEscaped` 处理并附带严格的 CSP meta。
- **App Transport Security** 仅对 `localhost` 放行明文 HTTP（用于 Ollama / LM Studio 的默认地址）。
- 启用 **应用沙盒**；WebKit 拥有 JIT 授权；文件导入使用 security-scoped 资源。

---

## 致谢

- [`swift-markdown-ui`](https://github.com/gonzalezreal/swift-markdown-ui) —— 用于渲染 AI 回复中的 Markdown。
- Apple 的 `WKWebView`、`CoreSpotlight`、`Foundation Models`、`Swift Charts`，以及 macOS 26 的 Liquid Glass API。

---

## 许可证

如仓库根目录存在 `LICENSE` 文件，以该文件为准。

---

*Crux 仍在持续开发中。最新的开发日志见 [`handoff.md`](./handoff.md)；按 pass 记录的改动清单见 [`IMPROVEMENTS.md`](./IMPROVEMENTS.md)。*
