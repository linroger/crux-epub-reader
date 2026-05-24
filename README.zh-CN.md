# Crux

*一款面向 macOS（兼容 iPad / iPhone）的 AI 原生 EPUB 阅读器，使用 SwiftUI 构建。*

[English README](./README.md)

Crux 不只是阅读器，而是一个阅读工作台。划选任意段落，AI 对话即在旁侧展开；继续追问、随时切换模型（云端或完全本地），并把洞见保存回书库。书籍会被建入 macOS Spotlight 索引——从系统搜索点击结果即可直接在阅读器中打开。每一段较长的 AI 回复都按 token 逐字流式呈现，可用 `⌘.` 立即停止，也可重新生成、复制或通过系统分享菜单转发。

![书库 — 继续阅读](Screenshots/Crux%202026-05-24%20at%2016.33.06%402x.png)

---

## 核心亮点

- **AI 原生批注。** 划选任意段落 → 自动展开一段流式、学术深度的 AI 释义，可继续追问、重新生成、复制、分享。
- **自带模型，灵活切换。** 支持 Claude、OpenAI、自定义 OpenAI 兼容端点、Ollama、LM Studio，以及完全本地的 Apple Intelligence（macOS 26 / iOS 18.4+）。
- **章级 AI 命令。** 工具栏 **Ask AI** 菜单提供四种预设分析（章节概要、主题与意象、疑难段落、讨论问题），也支持任意自定义问题，结果可保存为 `.analysis` 类型的书签。
- **真实 EPUB 渲染。** 通过 WKWebView 渲染章节内容，支持自定义字体、字号、行高、主题；基于 CFI 的精准位置恢复，让你重开即停在原元素位置。
- **原生 macOS 体验。** 检视器侧栏、macOS 26 Liquid Glass、系统级 `NSSharingServicePicker` 分享、Spotlight 索引、NSUserActivity 接力（Handoff / Recents）、Finder 中显示。
- **稳健可靠。** 批注采用原子写入 + `.bak` 回滚；云端调用对临时错误指数退避重试；API Key 走系统 Keychain；ATS 配置正确地放行本地网络；启用 JIT 沙盒授权保证 WKWebView 正常工作。
- **主题与排版。** 内置浅色、深色、Sepia、夜间，以及对比度 >21:1 的高对比主题；字体、行高、页边距、段落间距均可调。

---

## 截图

### 阅读器 — 旁注式 AI 对话与划线高亮

每条高亮都拥有一段独立的 AI 旁注。AI 输出逐 token 流式渲染；滚动时当前段落始终保持定位。

![阅读器与旁注 AI 对话](Screenshots/Crux%202026-05-24%20at%2016.32.44%402x.png)

### 书库 — 继续阅读

以封面为主的书库视图，展示每本书的阅读进度、完成徽章，支持拖拽导入；右键菜单含 *在新窗口中打开*、*显示详情*、*在 Finder 中显示*、*合集*、*移除* 等。

![书库视图](Screenshots/Crux%202026-05-24%20at%2016.33.06%402x.png)

### 设置 — AI 模型

可并行配置多个模型：Claude、OpenAI、自定义端点、Ollama、LM Studio、Apple Intelligence。当前激活的模型会高亮显示；本地模型带有盾形徽章，断网时也不会触发只对云端模型显示的「Offline」提示。

![设置 → AI 模型](Screenshots/Crux%202026-05-24%20at%2016.33.14%402x.png)

### 设置 — AI 提示词

内置五种系统提示词预设（学术 Scholarly、随性 Casual、苏格拉底 Socratic、极简 Minimalist、技术 Technical），另有自定义槽位。当前选中的提示词通过 `AIRequestOptions` 注入到每一个模型，保证回复的语气统一。

![设置 → AI 提示词](Screenshots/Crux%202026-05-24%20at%2016.33.27%402x.png)

---

## Crux 中的 AI 是如何工作的

Crux 将所有模型抽象在统一的 `AIProvider` 协议之后。对话编排器（`ThreadPanelState`）经由 `AIProviderManager` 调用当前激活的模型，透明地完成以下流程：

1. **流式输出。** OpenAI、Claude、Ollama、LM Studio、Apple Intelligence 均原生流式。云端模型走包装为 `AsyncThrowingStream` 的 SSE；Ollama 使用 JSONL；Apple Intelligence 通过 Foundation Models 的 partial token 增量流式。Token 进入 `streamingText`，在面板中实时渲染。
2. **取消。** 当前任务保存在 `ThreadPanelState.activeTask`。按 `⌘.`（或 Stop 按钮）即可取消——取消会沿 `AsyncThrowingStream` 一路传递到底层的 `URLSessionTask`，已生成的局部回复会被丢弃，确保下次调用从干净状态开始。
3. **自动重试。** 临时性错误（断网、408 / 429 / 5xx、URLSession transient code）会按指数退避自动重试（`RetryPolicy`，0.8 s → 1.6 s → 3.2 s，封顶 15 s）。错误的密钥及硬性 4xx 会立即提示，并提供 *打开设置* 的快捷操作。
4. **重新生成。** 将鼠标悬停在最新一条 AI 回复上 → **Regenerate** 会弹出最后的消息对，并以当前提示词预设重新发起。
5. **章级范围。** 工具栏 **Ask AI** 菜单会把章节 HTML 剥离为纯文本（限制在约 20k 字符以适配上下文窗口），再向所选预设或自定义问题发起流式调用。结果可一键保存为 `.analysis` 类型的书签。

### 提示词自定义

可选用五种内建语气，或编写自己的：

- **Scholarly（学术）** — 研究生级深度，兼顾文学 / 哲学 / 历史分析。
- **Casual（随性）** — 友好、口语化。
- **Socratic（苏格拉底）** — 以提问代替直接给出答案。
- **Minimalist（极简）** — 简洁、无修辞。
- **Technical（技术）** — 面向代码，强调精确。
- **Custom（自定义）** — 粘贴你自己的系统提示词；可从任意预设导入模板再修改。

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

- Xcode 15 或更高（Xcode 26 SDK 才能启用 Liquid Glass 与 Apple Intelligence 路径）
- macOS 14.0+ 部署目标（Crux 在运行时通过 `#available` 渐进启用 macOS 26 特性）
- iPad / iPhone 构建需 iOS 17.0+
- [`xcodegen`](https://github.com/yonaskolb/XcodeGen) 用于工程生成

---

## 架构总览

```
Shared/
├── Models/           SwiftData 实体 + 值类型（Book、Annotations、Settings）
├── Services/         AI 模型、EPUB 解析器、存储、索引、重试策略
├── ViewModels/       响应式 View Model（NotesViewModel 等）
├── Views/            SwiftUI 视图（ReaderView、LibraryView、ThreadPanel 等）
│   ├── Library/      拆分后的书库行 / 卡片子视图
│   └── Reader/       阅读器专属子视图（ProgressScrubber、TTSControlPanel 等）
└── CruxApp.swift     @main 场景树 + 命令 + activity 接力处理
Resources/
└── Reader/           注入到 WKWebView 的 JS 模块（cfi.js、highlighter.js、search.js、viewport-tracker.js、selection-macos.js）
```

更完整的分层概览、并发模型与「应该把代码加到哪里」的速查表，参见 [`ARCHITECTURE.md`](./ARCHITECTURE.md)。

### 关键服务

| 服务 | 职责 |
|---|---|
| `EPUBParser` | 纯 Swift 实现的 EPUB 2/3 解析，含对损坏 XML 的回退处理 |
| `BookStorage` | 在 Application Support 中以书为单位存储，原子化写入批注（`.tmp` → rename，`.bak` 回滚） |
| `AIProviderManager` / `AIProvider` | 统一接入 6 种模型后端，编排重试 |
| `RetryPolicy` | 指数退避的临时错误分类与重试 |
| `BookSearchIndex` | 每本书的纯文本索引，开书时后台预热 |
| `CoverImageCache` | 基于 actor + `NSCache` 的封面缩略图缓存（上限 64 MB / 200 条） |
| `SpotlightIndexer` | 导入 / 删除时同步 `CSSearchableIndex`，冷启动时整轮对账 |
| `KeychainService` | API Key 存入系统 Keychain |
| `NetworkMonitor` | 基于 `NWPathMonitor` 的连通性检测，驱动 AI 面板的「Offline」标识 |
| `CruxNotesIO` | `.cruxnotes` 离线批注包的导入 / 导出，含合并与去重 |

---

## 隐私与安全

- **API Key 存放于 macOS Keychain。** 老版本基于 UserDefaults 的存储会在首次启动时自动迁移一次。
- **本地模型带有盾形徽章。** Apple Intelligence、Ollama、LM Studio 不会离开你的机器——它们也不会显示「Offline」提示。
- **批注完全本地。** 与书并排存为 JSON；导出的 HTML 经 `htmlEscaped` 处理并附带严格的 CSP meta。
- **App Transport Security** 仅对 `localhost` 放行本地 HTTP（用于 Ollama / LM Studio 的默认地址）。

---

## 致谢

- [`MarkdownUI`](https://github.com/gonzalezreal/swift-markdown-ui) — 用于渲染 AI 回复中的 Markdown
- Apple `WKWebView`、`CoreSpotlight`、`Foundation Models`
- macOS 26 的 Liquid Glass API

---

## 许可证

如仓库根目录存在 `LICENSE` 文件，以该文件为准。

---

*Crux 仍在持续开发中。最新的开发日志见 [`handoff.md`](./handoff.md)，按 pass 记录的改动清单见 [`IMPROVEMENTS.md`](./IMPROVEMENTS.md)。*
