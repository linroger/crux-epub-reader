# Crux

*An AI-native EPUB reader for macOS (and iPad/iPhone), built in SwiftUI.*

[简体中文 README](./README.zh-CN.md)

Crux is a reading workspace, not just a reader. Highlight a passage and an AI thread opens beside it; ask follow-ups, switch providers (cloud or fully on-device), and save the insight back into your library. Books are indexed into macOS Spotlight, so the result you click in the system search opens directly in the reader. Every long AI response streams token-by-token, can be stopped with `⌘.`, and can be regenerated, copied, or shared via the system share sheet.

![Library — Continue Reading](Screenshots/Crux%202026-05-24%20at%2016.33.06%402x.jpg)

---

## Highlights

- **AI-native annotations.** Highlight any passage → an AI thread opens with a streaming, scholarly explication. Follow up freely, regenerate, copy, share.
- **Bring-your-own provider.** Claude, OpenAI, custom OpenAI-compatible endpoints, Ollama, LM Studio, and on-device Apple Intelligence (macOS 26 / iOS 18.4+).
- **Chapter-scope AI.** A toolbar **Ask AI** menu runs four preset analyses (Summarize, Themes, Difficult Passages, Discussion Questions) or any free-form question against the current chapter. Save the result as a `.analysis` bookmark.
- **Real EPUB rendering.** WKWebView renders chapters with your fonts, sizes, spacing, and theme; CFI-based position restoration keeps you on the exact element across reopens.
- **Native macOS.** Inspector sidebar, Liquid Glass on macOS 26, system share menu via `NSSharingServicePicker`, Spotlight indexing, NSUserActivity donation for Handoff and Recents, Reveal in Finder.
- **Robust.** Atomic annotation writes with `.bak` rollback, transient-error retry with exponential backoff for cloud calls, keychain-backed API keys, ATS-correct local-network handling, sandboxed but with JIT entitlements for WKWebView.
- **Themes & reader chrome.** Light, Dark, Sepia, Night, and a >21:1-contrast High Contrast theme. Configurable fonts, line height, margins, paragraph spacing.

---

## Screenshots

### Reader — margin AI threads & live highlights

Each highlight gets its own AI-powered margin note. Streams render token-by-token; the active passage stays anchored as you scroll.

![Reader with margin AI threads](Screenshots/Crux%202026-05-24%20at%2016.32.44%402x.jpg)

### Library — Continue Reading

Cover-forward library with per-book progress, finished badges, drag-and-drop import, and right-click context for *Open in New Window*, *Show Details*, *Reveal in Finder*, *Collections*, and *Remove*.

![Library view](Screenshots/Crux%202026-05-24%20at%2016.33.06%402x.jpg)

### Settings — AI Providers

Configure multiple providers side-by-side: Claude, OpenAI, custom endpoints, Ollama, LM Studio, Apple Intelligence. The active provider is marked; on-device providers get a shield badge and skip the "Offline" pill that cloud providers show when network drops.

![Settings → AI Providers](Screenshots/Crux%202026-05-24%20at%2016.33.14%402x.jpg)

### Settings — AI Prompt

Five built-in system prompts (Scholarly, Casual, Socratic, Minimalist, Technical) plus a Custom slot. The active prompt routes through `AIRequestOptions` so every provider honors the same voice.

![Settings → AI Prompt](Screenshots/Crux%202026-05-24%20at%2016.33.27%402x.jpg)

---

## How AI works in Crux

Crux abstracts every model behind a single `AIProvider` protocol. The thread orchestrator (`ThreadPanelState`) calls into the active provider via `AIProviderManager`, transparently:

1. **Streaming.** OpenAI, Claude, Ollama, LM Studio, and Apple Intelligence all stream natively. Cloud providers run through `AsyncThrowingStream`-wrapped SSE; Ollama uses JSONL; Apple Intelligence streams via Foundation Models partials. Tokens land in `streamingText` and render live in the panel.
2. **Cancellation.** The active task is held in `ThreadPanelState.activeTask`. `⌘.` (or the Stop button) cancels — the cancellation propagates through `AsyncThrowingStream` to the underlying `URLSessionTask`, then the partial reply is discarded so the next attempt starts clean.
3. **Retry.** Transient failures (network drops, 408 / 429 / 5xx, URLSession transient codes) auto-retry with exponential backoff (`RetryPolicy`, 0.8 s → 1.6 s → 3.2 s, 15 s ceiling). Bad keys and hard 4xx errors surface immediately with a *Open Settings* CTA.
4. **Regenerate.** Hover the most recent assistant reply → **Regenerate** pops the message pair and re-issues with the current prompt preset.
5. **Chapter scope.** The toolbar **Ask AI** menu strips chapter HTML to plain text (capped at ~20k chars to fit context windows) and runs the streaming call against the chosen preset or free-form question. Results can be saved as a `.analysis` Bookmark.

### Prompt customization

Pick one of five built-in voices, or write your own:

- **Scholarly** — graduate-level depth, with literary / philosophical / historical analysis.
- **Casual** — friendly, conversational.
- **Socratic** — asks probing questions instead of declaring answers.
- **Minimalist** — terse, no chrome.
- **Technical** — code-oriented; precise.
- **Custom** — paste your own system prompt; templates seeded from any preset.

---

## Build & run

```bash
# Generate the Xcode project from project.yml
xcodegen generate

# Build for macOS
xcodebuild -scheme Crux_macOS -destination 'platform=macOS' \
           -derivedDataPath ./DerivedData build

# Run tests
xcodebuild -scheme Crux_macOS -destination 'platform=macOS' test

# Launch the built app
open DerivedData/Build/Products/Debug/Crux.app
```

**Requirements**

- Xcode 15 or newer (Xcode 26 SDK enables Liquid Glass + Apple Intelligence paths)
- macOS 14.0+ deployment target (Crux opts in to macOS 26 features at runtime via `#available`)
- iOS 17.0+ for the iPad/iPhone build
- [`xcodegen`](https://github.com/yonaskolb/XcodeGen) for project generation

---

## Architecture

```
Shared/
├── Models/           SwiftData entities + value types (Book, Annotations, Settings)
├── Services/         AI providers, EPUB parser, storage, indexing, retry policy
├── ViewModels/       Reactive view-models (NotesViewModel, …)
├── Views/            SwiftUI views (ReaderView, LibraryView, ThreadPanel, …)
│   ├── Library/      Decomposed library row / card subviews
│   └── Reader/       Reader-specific subviews (ProgressScrubber, TTSControlPanel, …)
└── CruxApp.swift     @main scene tree + commands + activity continuation
Resources/
└── Reader/           JS modules injected into WKWebView (cfi.js, highlighter.js, search.js, viewport-tracker.js, selection-macos.js)
```

See [`ARCHITECTURE.md`](./ARCHITECTURE.md) for the full layered overview, concurrency model, and "where to add things" cheatsheet.

### Key services

| Service | Responsibility |
|---|---|
| `EPUBParser` | Pure-Swift EPUB 2/3 parsing with malformed-XML fallbacks |
| `BookStorage` | Per-book storage in Application Support, atomic annotation writes (`.tmp` → rename, `.bak` rollback) |
| `AIProviderManager` / `AIProvider` | Unified interface to 6 provider backends, retry orchestration |
| `RetryPolicy` | Exponential-backoff retry classifier for transient failures |
| `BookSearchIndex` | Per-book plain-text index, background-warmed on book open |
| `CoverImageCache` | Actor + `NSCache` thumbnail cache (64 MB / 200 entries) |
| `SpotlightIndexer` | `CSSearchableIndex` upserts on import/delete + cold-launch reconcile |
| `KeychainService` | API-key storage in the system Keychain |
| `NetworkMonitor` | `NWPathMonitor`-backed connectivity for the AI offline pill |
| `CruxNotesIO` | `.cruxnotes` bundle import/export with merge & dedup |

---

## Privacy & security

- **API keys live in the macOS Keychain.** Migration from earlier UserDefaults storage happens once on first launch.
- **On-device providers ship a shield badge.** Apple Intelligence, Ollama, and LM Studio never leave your machine — no "Offline" warning appears for them.
- **Annotations are local.** Saved as JSON next to each book; HTML export goes through `htmlEscaped` + strict CSP meta.
- **App Transport Security** allows local-network HTTP only for `localhost` (for the Ollama / LM Studio default URLs).

---

## Acknowledgements

- [`MarkdownUI`](https://github.com/gonzalezreal/swift-markdown-ui) — assistant message rendering
- Apple `WKWebView` + `CoreSpotlight` + `Foundation Models`
- Apple's Liquid Glass APIs on macOS 26

---

## License

See `LICENSE` if present in the repo root.

---

*Crux is in active development. See [`handoff.md`](./handoff.md) for the most recent session log and [`IMPROVEMENTS.md`](./IMPROVEMENTS.md) for the running list of pass-by-pass changes.*
