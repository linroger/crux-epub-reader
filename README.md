# Crux

*An AI-native EPUB reading workspace for macOS — and iPad / iPhone — built in SwiftUI.*

[简体中文 README](./README.zh-CN.md)

Crux turns an EPUB into something you can *think with*. Highlight a passage and an AI thread opens beside it as a margin note; ask follow-ups, swap providers (cloud or fully on-device), and the conversation is saved into the book's annotations. Books are indexed into Spotlight, so a system search opens straight into the reader at the right element. Every long AI response streams token-by-token, cancels with `⌘.`, and can be regenerated, copied, or sent through the native share sheet. Highlights, bookmarks, threads, reading sessions, streaks, and goals are all first-class — and exportable.

![Library — Continue Reading](Screenshots/Crux%202026-05-24%20at%2016.33.06%402x.jpg)

---

## Highlights

- **Reader-anchored AI threads.** Select text → an AI margin note streams an explication beside the line. Keep asking follow-ups; threads persist per-highlight inside the book.
- **Six providers, one interface.** Claude (Anthropic), OpenAI, any OpenAI-compatible endpoint, **Ollama**, **LM Studio**, and on-device **Apple Intelligence** (Foundation Models, macOS 26 / iOS 18.4+). All share the same streaming, cancellation, and retry semantics.
- **Chapter-scope analysis.** A toolbar **Ask AI** menu runs preset analyses (Summarize, Themes, Difficult Passages, Discussion Questions) — or any free-form question — against the current chapter, then saves the result as a `.analysis` bookmark.
- **Five prompt voices + Custom.** Scholarly, Casual, Socratic, Minimalist, Technical. Switch globally; every provider honors the active voice via `AIRequestOptions.systemPrompt`.
- **Real EPUB rendering.** WKWebView renders chapters with your fonts, sizes, spacing, and theme. **CFI-based position restoration** keeps you on the exact paragraph across reopens, theme changes, and devices.
- **Library that scales.** Cover grid + dense list, multi-tier filters (status / author / collection / year / language / tags), collections with color tags, drag-and-drop batch import with per-file progress, multi-window reading.
- **Knowledge you can export.** Annotation exports in Markdown, HTML, JSON, plain text, CSV, BibTeX, PDF, and a portable `.cruxnotes` bundle that merges back losslessly.
- **Reading life.** Sessions, streaks (current / best / total days), period-aware goals (daily / weekly / monthly / yearly), achievements, and Swift Charts activity views.
- **Liquid Glass, gracefully.** macOS 26 Liquid Glass on the latest OS, automatic fallback to system Materials on macOS 14–25 — no version split required.
- **Built for trust.** API keys live in the Keychain. Atomic annotation writes with `.bak` rollback. ATS allows local HTTP only for localhost. App sandbox + JIT WebKit entitlements.

---

## Screenshots

### Reader — margin AI threads and live highlights

Each highlight gets its own AI margin note. Streams render token-by-token; the active passage stays anchored as you scroll; conversations can continue with follow-ups, all persisted inside the book's annotations.

![Reader with margin AI threads](Screenshots/Crux%202026-05-24%20at%2016.32.44%402x.jpg)

### Library — Continue Reading

Cover-forward library with per-book progress, finished badges, drag-and-drop import, and a right-click context for *Open in New Window*, *Show Details*, *Reveal in Finder*, *Collections*, and *Remove*. A persistent search bar runs across title, author, subjects, and tags.

![Library view](Screenshots/Crux%202026-05-24%20at%2016.33.06%402x.jpg)

### Settings → AI Providers

Configure multiple providers side-by-side. The active provider is marked with an `ACTIVE` chip; on-device providers (Apple Intelligence, Ollama, LM Studio) get a shield badge and skip the "Offline" pill that cloud providers display when the network drops. *Refresh installed models* discovers local models from Ollama's `/api/tags` and LM Studio's `/v1/models`.

![Settings → AI Providers](Screenshots/Crux%202026-05-24%20at%2016.33.14%402x.jpg)

### Settings → AI Prompt

Five built-in system prompts plus a Custom slot. Custom can be seeded from any preset as a starting template. The active prompt is injected into every request through `AIRequestOptions.systemPrompt`.

![Settings → AI Prompt](Screenshots/Crux%202026-05-24%20at%2016.33.27%402x.jpg)

---

## Feature tour

### Reading and the WebKit engine

- **WKWebView + JS bridge.** A small set of JavaScript modules in `Resources/Reader/` are injected at load: `cfi.js` (CFI generation and lookup), `highlighter.js` (paint highlights, click handlers, scrollToCFI), `viewport-tracker.js` (reports the topmost visible element's CFI on scroll), `search.js` (in-chapter find), `margin-notes.js` (margin rail with collision detection), and platform-specific `selection-macos.js` / `selection-ios.js`.
- **CFI position persistence.** Position is stored as a Canonical Fragment Identifier (`/4/2/1:42`) — a 1-based path through the DOM — on every scroll. Reopens land on the exact element, with scroll percentage as a graceful fallback.
- **Multi-color highlights and threads.** Yellow / green / blue / pink / orange. Each highlight stores its CFI range, selected text, surrounding context, optional annotation note, category (Quote / Analysis / Question / Important / Reference / Definition / Example / Personal / Other), tags, and an array of AI threads.
- **In-chapter and book-wide search.** `CruxSearch` paints matches inside the rendered chapter; `BookSearchIndex` keeps a per-book plain-text index (built/warmed on open) for cross-chapter results with snippet context.
- **Text-to-speech.** AVSpeechSynthesizer with rate and pitch controls in the TTS panel; the currently spoken word is highlighted as audio plays.
- **Dictionary lookup.** Native system dictionary on selected words.
- **Citation formatting.** Export highlights and threads as Markdown, HTML, PDF, or BibTeX, with book title, author, publication date, chapter, and position.

### AI: providers, prompts, threads

- **Streaming everywhere.** Claude and OpenAI use SSE (`content_block_delta` / `choices[].delta.content`); Ollama uses JSONL; LM Studio uses OpenAI-compatible SSE; Apple Intelligence streams Foundation Models partials. All providers expose the same `AsyncThrowingStream<String, Error>` to the UI; tokens land in `streamingText` and render live.
- **Cancellation.** The active `Task` lives on `ThreadPanelState.activeTask`. `⌘.` (or **Stop**) cancels; the cancellation propagates through `AsyncThrowingStream` to the underlying `URLSessionTask`, and partial output is discarded.
- **Retry with backoff.** Transient failures (timeouts, 408 / 429 / 5xx, URLSession transient codes) auto-retry via `RetryPolicy` — 0.8 s → 1.6 s → 3.2 s with a 15 s ceiling, 3 attempts. Mid-stream errors are *not* retried (avoids duplicate output).
- **Regenerate.** Hover the most recent assistant reply → **Regenerate** pops the last message pair and re-issues with the current prompt preset.
- **Save chapter insights.** Chapter-scope analyses are ephemeral by default; one click pins them as a `.analysis` Bookmark, with a small confirmation animation.
- **Native sharing.** AI replies route through `NSSharingServicePicker` on macOS — Notes, Mail, Messages, Reminders, all available.
- **Note templates.** When you start typing an annotation, six structured scaffolds are one click away: Character Analysis, Theme, Citation, Question, Connection, Vocabulary.

### Library and organization

- **Two views.** Cover grid and dense list, with Title / Author / Date Added / Last Read / Progress sorts.
- **Multi-tier filters.** Reading status (Not Started / In Progress / Finished), author, collection, publication year range, language, publisher, subjects, tags.
- **Collections.** Color-coded folders with drag-to-reorder and bidirectional relationships; collection rows show book counts.
- **Continue Reading.** Carousel of the five most recently opened unfinished books on the library landing.
- **Batch import.** Drag a folder of EPUBs; `BatchImportProgressView` shows per-file state (pending / importing / succeeded / failed).
- **Reveal in Finder.** Right-click any book to surface the underlying EPUB.
- **Multi-window.** `BookWindowScene` opens each book in its own window — perfect for side-by-side reading or annotating two books at once.

### Annotations, notes, and bookmarks

- **HighlightsView.** Inline thread expansion, accent gradients, swipe-to-delete, export toolbar.
- **NotesView.** Split-view sidebar with highlight list and detail pane; statistics bar (highlight / thread / note counts); search and filter (with-threads, with-notes, all).
- **BookmarksView.** Chapter title, scroll percentage, optional note, jump-to-position.
- **Atomic writes with rollback.** Annotations are saved as JSON next to each book via a three-step `tmp → rotate → rename` flow with a `.bak` revision. A crash between rotate and rename is recovered on load.
- **Annotation exports.** Markdown, HTML (with CSP-strict styling), JSON, plain text, CSV (one row per message), and the `.cruxnotes` bundle — a self-describing format with `formatVersion`, book metadata, and merge-by-id import that skips duplicates.

### Reading life: statistics, streaks, goals

- **Sessions.** Per-book sessions track duration, chapter range, and pages read; an opt-out lives in Settings.
- **Streaks.** Current, best, and total days; flame indicators; an `AchievementChecker` surfaces awards like *Week Streak*, *Night Owl*, *Marathon Reader*.
- **Goals.** Daily / weekly / monthly / yearly, with animated progress rings and a history of past achievements.
- **Statistics.** Swift Charts bar marks aggregated by day; range picker (Week / Month / Year); cards for total reading time, books finished, session count, average session duration.
- **Reading time estimation.** 220 wpm baseline, HTML-stripped word counts, cached on `StoredBook.cachedReadingMinutes` so library rows don't re-parse.

### Themes and reader chrome

- **Six themes.** Light, Dark, System, Sepia, Night, and a >21:1-contrast High Contrast (WCAG AAA).
- **Reader controls.** Font family (System, Georgia, Garamond, …), font size (10–24pt), line height (1.4–2.0), paragraph spacing (0.5–2.0em), margin width (20–120px).
- **Live theme injection.** Theme changes flow through CSS variables in the WebView for instant updates without reload.

### macOS integration

- **Spotlight.** Books are donated as `NSUserActivity` with `isEligibleForSearch` + `isEligibleForHandoff`; activity identifiers carry book UUIDs, so Spotlight learns re-engagement and the result opens straight into the reader.
- **Handoff.** Continue on another device via the activity continuation.
- **Liquid Glass.** `LiquidGlass.swift` exposes `cruxGlassCard`, `cruxGlassFloating`, `cruxGlassBar`, `cruxGlassButton`, and `cruxScrollEdgeSoft` modifiers that adopt macOS 26 glass effects when available and fall back to `.regularMaterial` / `.thickMaterial` / `.bar` with hairline borders on macOS 14–25.
- **Keyboard shortcuts.** ~30 shortcuts spanning library, reading, search, annotations, and window management (⌘L TOC, ⌘B bookmark, ⌘F find, ⌘⇧S stats, ⌘⇧G goals, ⌘⇧T streaks, ⌘H commit highlight, ⌘A ask AI, ⌘. cancel).

### Accessibility

- **Reduce Motion** is respected throughout — onboarding transitions, row hover animations, highlight effects all honor `\.accessibilityReduceMotion`.
- **High Contrast** theme ships WCAG AAA contrast for low-vision readers.
- **Toolbar `.help()` descriptors** and large hit targets (`.contentShape(Rectangle())`) make icon buttons screen-reader friendly.

---

## Architecture

### Tech stack

- **SwiftUI** unified codebase for **macOS 14+** and **iOS 17+**, with runtime opt-ins for **macOS 26 / iOS 18.4** features (Liquid Glass, Apple Intelligence Foundation Models).
- **Swift 5.9 / toolchain 6.2**, generated `.xcodeproj` via [`xcodegen`](https://github.com/yonaskolb/XcodeGen).
- **SwiftData** for the library, settings, AI provider configs, and reading sessions.
- **WKWebView** for chapter rendering, bridged to Swift through six `WKScriptMessageHandler`s.
- **CoreSpotlight** for Spotlight indexing; **NSUserActivity** for Handoff and Recents.
- **Foundation Models** for on-device Apple Intelligence inference.
- **Swift Charts** for the statistics view.
- One SPM dependency: [`swift-markdown-ui`](https://github.com/gonzalezreal/swift-markdown-ui) for rendering assistant Markdown.

### Layered design

```
Views (SwiftUI)
  ↓ read
@Observable state (AppState, ThemeManager, ThreadPanelState, NotesViewModel)
  ↓ call
Services (actors + Sendable value types)
  ↓ own
Persistence (SwiftData • FileSystem • Keychain)
```

Dependencies flow strictly downward. Services never reference views; the WebKit reader bridges back to Swift only via named JS message handlers, never via shared mutable state.

### Concurrency model

- **Actor-based I/O.** `BookStorage`, `EPUBParser`, `AIProviderManager`, every concrete `AIProvider` (`ClaudeProvider`, `OpenAIProvider`, `OllamaProvider`, `LMStudioProvider`, `AppleIntelligenceProvider`, `CustomProvider`), `CoverImageCache`, and `KeychainService` are all `actor`s — file system, network, and keychain access are race-free by construction.
- **`@MainActor @Observable` UI state.** `AppState`, `ThreadPanelState`, `ErrorHandler`, `ThemeManager`, and `NetworkMonitor` live on the main actor, so views can read state without suspension points.
- **Streaming.** Providers yield `AsyncThrowingStream<String, Error>` chunks; cancellation propagates through the stream to `URLSessionTask`.
- **Retry boundaries.** `RetryPolicy` wraps non-streaming calls; mid-stream failures surface to the user rather than silently re-issuing.

### Data layer

**SwiftData (`@Model`)**
- `StoredBook` — library entry: title, author, chapters, progress, `scrollPosition`, `lastReadingCFI`, cached cover, collections relationship, `cachedReadingMinutes`.
- `BookCollection` — color-tagged folder with bidirectional `books`.
- `ReadingSession` — per-book session with start / end / duration / chapter range / pages.
- `AppSettings` — singleton: theme, fonts, margins, library view + sort, active provider id, custom prompt, highlight palette, opt-outs.
- `AIProviderConfig` — provider identity (name, type, baseURL, model). **API keys are not in SwiftData** — they live in Keychain, indexed by provider UUID.

**Runtime value types (in-memory)**
- `Book`, `Chapter`, `BookMetadata` — parsed from the EPUB on reader open (parsing is cheap; no caching needed).

**JSON per book (atomic)**
- `BookAnnotations { highlights: [Highlight], bookmarks: [Bookmark], updatedAt }` written to `Documents/Annotations/<uuid>.json` via `tmp → rotate-to-.bak → rename`. Crash between steps recovers from `.bak`.
- `Highlight` carries `CFIRange`, selected text, surrounding context, optional annotation, `AnnotationCategory` (9-case enum), tags, color, and a `threads: [AIThread]` array of `ThreadMessage` (role + Markdown content).

### WebKit reader engine

| File | Role |
|---|---|
| `reader-template.html` + `reader.css` | Container, reader styling, CSS variables for theme/font/spacing |
| `selection-macos.js` / `selection-ios.js` | Surface text selection with CFI + 500-char context via `webkit.messageHandlers.textSelection` |
| `viewport-tracker.js` | Report topmost visible element's CFI and scroll position on scroll |
| `highlighter.js` | Paint stored highlights as `<span class="crux-highlight">`, register click handlers, `scrollToCFI` |
| `search.js` | In-chapter find with TreeWalker, regex-escaped matches, next / previous |
| `cfi.js` | EPUB Canonical Fragment Identifier generation + path-walking lookup |
| `margin-notes.js` | Margin rail UI, collision detection, AI status states ("Analyzing…"), follow-up input bar |

### Services (selected)

| Service | Responsibility |
|---|---|
| `EPUBParser` | Pure-Swift EPUB 2/3 parsing with malformed-XML fallbacks |
| `BookStorage` | Per-book file layout, atomic annotation writes with `.bak` rollback |
| `LibraryBackupService` | Versioned JSON library backup with skip / overwrite / keep-newer merge |
| `AIProviderManager` / `AIProvider` | 6-backend abstraction + retry orchestration |
| `RetryPolicy` | Exponential-backoff classifier for transient failures |
| `BookSearchIndex` | Per-book plain-text index, warmed on open |
| `CoverImageCache` | Actor + `NSCache` thumbnail cache (200 entries / 64 MB ceiling) |
| `SpotlightIndexer` | `CSSearchableIndex` upserts + cold-launch reconcile + NSUserActivity donation |
| `KeychainService` | Keychain wrapper for provider API keys |
| `NetworkMonitor` | `NWPathMonitor` connectivity → the AI panel's "Offline" pill |
| `LocalModelDiscovery` | Normalize Ollama `/api/tags` and LM Studio `/v1/models` into a unified list |
| `ReadingSessionManager` | Sessions, streaks, statistics, period-aware goal progress |
| `ReadingTimeEstimator` | 220 wpm estimate, HTML-stripped, cached per book |
| `CitationFormatter` | Markdown / HTML / PDF / BibTeX export of highlights and threads |
| `CruxNotesIO` | `.cruxnotes` bundle import/export with version validation, merge, dedup |
| `ThemeManager` | Watches `AppSettings.theme`; pushes ColorScheme + injects CSS variables |
| `ErrorHandler` | Single `@Observable` for toasts and alerts, severity-routed |
| `AppLog` | Categorized `os.Logger` channels: parser, ai, storage, security, errors, data, reader, ui |

Full layered overview, "where to add things" cheatsheet, and decisions log: [`ARCHITECTURE.md`](./ARCHITECTURE.md).

---

## Project layout

```
Shared/
├── Models/           SwiftData entities + value types (Book, Annotations, AppSettings, AIProviderConfig, NoteTemplate, …)
├── Services/         Actors and value types — AI providers, EPUB parser, storage, indexing, retry, spotlight, logging
├── ViewModels/       Reactive view-models (NotesViewModel, …)
├── Views/
│   ├── Library/      Decomposed library row / card subviews
│   ├── Reader/       Reader subviews (ProgressScrubber, TTSControlPanel, …)
│   ├── ReaderView.swift, LibraryView.swift, ThreadPanel.swift, …
│   └── LiquidGlass.swift
└── CruxApp.swift     @main scene tree, commands, NSUserActivity continuation
Resources/
└── Reader/           Injected JS modules + CSS + HTML container
iOS/
└── …                Platform shims (entry, app delegate)
macOS/
└── …                Platform shims (entry, app delegate, AppKit bridges)
Tests/                EPUBParser, BookStorageError, CitationFormatter, AIPromptPreset, ReadingTimeEstimator, BookSearchIndex, Annotations, ViewportTracking, CruxNotesBundle, LocalProviderURL
UITests/
project.yml           xcodegen spec
```

---

## Build and run

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

- Xcode 15 or newer — Xcode 26 SDK is required to compile the Liquid Glass and Apple Intelligence paths (runtime-gated by `#available`).
- macOS 14.0+ deployment target (macOS 26 features opt in at runtime).
- iOS 17.0+ for the iPad / iPhone build.
- [`xcodegen`](https://github.com/yonaskolb/XcodeGen) for project generation.

---

## Privacy and security

- **API keys live in the macOS Keychain** (`com.crux.aiProviders`, indexed by provider UUID, `kSecAttrAccessibleAfterFirstUnlock`). Legacy UserDefaults keys are migrated automatically on first launch.
- **On-device providers ship a shield badge.** Apple Intelligence, Ollama, and LM Studio never leave your machine; no "Offline" warning is shown for them.
- **Annotations are local.** Stored as JSON beside the EPUB; HTML export passes through `htmlEscaped` and ships a strict CSP meta.
- **App Transport Security** allows plaintext HTTP only for `localhost` (Ollama and LM Studio defaults).
- **App sandbox** is on; WebKit gets JIT entitlements; file imports use security-scoped resources.

---

## Acknowledgements

- [`swift-markdown-ui`](https://github.com/gonzalezreal/swift-markdown-ui) — assistant message rendering.
- Apple `WKWebView`, `CoreSpotlight`, `Foundation Models`, `Swift Charts`, and the macOS 26 Liquid Glass APIs.

---

## License

See `LICENSE` if present in the repo root.

---

*Crux is in active development. The most recent session log lives in [`handoff.md`](./handoff.md); the pass-by-pass change list in [`IMPROVEMENTS.md`](./IMPROVEMENTS.md).*
