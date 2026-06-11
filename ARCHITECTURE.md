# Crux Architecture

This document describes how the Crux EPUB reader is organized, why it's
organized that way, and where to look when adding new features.

Crux targets **macOS 14+ / iOS 17+** with a shared SwiftUI codebase. Most
of the code lives under `Shared/`. The macOS-only and iOS-only entry
points (`macOS/`, `iOS/`) hold platform shims.

The audience for this doc is someone who already knows SwiftUI / Swift
concurrency and just needs to find the right seam to extend.

---

## Layer overview

```
        ┌────────────────────────────────────────────────────────────┐
        │  Views (SwiftUI)                                           │
        │   ContentView · LibraryView · ReaderView · ThreadPanel     │
        │   SettingsView · NotesView · OnboardingView · …            │
        └─────────────┬──────────────────────────────────────────────┘
                      │
        ┌─────────────┴────────────────────────────────────────────┐
        │  View-bound state (`@Observable`)                        │
        │   AppState · ThreadPanelState · NotesViewModel ·         │
        │   ThemeManager · ReadingSessionManager                   │
        └─────────────┬────────────────────────────────────────────┘
                      │
        ┌─────────────┴────────────────────────────────────────────┐
        │  Services (actors / value types)                         │
        │   AIProviderManager · AIProviderFactory · ClaudeProvider │
        │   OpenAIProvider · OllamaProvider · LMStudioProvider     │
        │   AppleIntelligenceProvider · CustomProvider             │
        │   EPUBParser · BookStorage · KeychainService             │
        │   AnnotationExportService · ExportService                │
        │   LibraryBackupService · TextToSpeechService             │
        │   NetworkMonitor · CoverImageCache · ReadingTimeEstimator│
        │   CitationFormatter · LocalModelDiscovery · RetryPolicy  │
        └─────────────┬────────────────────────────────────────────┘
                      │
        ┌─────────────┴────────────────────────────────────────────┐
        │  Persistence                                             │
        │   SwiftData (StoredBook, BookCollection, AppSettings,    │
        │     AIProviderConfig, ReadingSession, ReadingGoal,       │
        │     GoalAchievement, ReadingStreak, Achievement,         │
        │     SearchHistoryItem)                                   │
        │   Filesystem (Documents/Books/<id>.epub,                 │
        │               Documents/Annotations/<id>.json{,.bak})    │
        │   Keychain (AI provider API keys)                        │
        └──────────────────────────────────────────────────────────┘
```

**Direction of dependency.** Higher layers depend on lower layers, never
the reverse. Views read from `@Observable` state objects; state objects
call into services; services own persistence. Services never reach back
into views.

---

## Concurrency model

* **Long-lived persistent state** uses Swift `actor`s. `BookStorage`,
  `AIProviderManager`, `EPUBParser`, `CoverImageCache`,
  `KeychainService`, every `AIProvider` implementation, and
  `AnnotationExportService` are actors. They serialize internal state
  and own non-Sendable Foundation/AppKit types behind the actor barrier.

* **UI-bound state** is `@MainActor @Observable`. `AppState`,
  `ThreadPanelState`, `ErrorHandler`, `NetworkMonitor`, `ThemeManager`
  all live on the main actor so views can read them without
  suspension points.

* **AI requests** start at `@MainActor` in `ThreadPanelState`, hop into
  the active provider's actor for the network call, and hop back to
  publish results. Streaming uses
  `AsyncThrowingStream<String, Error>` so the UI can render tokens
  incrementally.

* **`RetryPolicy`** is a `Sendable` value type. It wraps a
  `@Sendable () async throws -> T` closure, classifies transient
  errors, and reissues with exponential backoff (0.8s → 1.6s → 3.2s,
  capped at 15s, default 3 attempts). Mid-stream retries are
  deliberately *not* attempted — partial output is already on screen.

---

## AI provider architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  AIProvider (protocol, Sendable)                                 │
│   generateResponse(for:context:history:options:)                 │
│   streamResponse(for:context:history:options:)                   │
└──────────────────────────────────────────────────────────────────┘
                      ▲
        ┌─────────────┼─────────────┬───────────┬───────────────┐
        │             │             │           │               │
   ClaudeProvider  OpenAI        Ollama    LMStudio       Custom
                   Provider      Provider  Provider       Provider
                                                              │
                                                          AppleIntelligence
                                                          Provider
```

* `AIProviderConfig` (SwiftData `@Model`) stores the per-provider
  identity (name, type, baseURL, model) but **never** the API key — keys
  live in `KeychainService` and are loaded on demand via
  `getAPIKey()`/`setAPIKey(_:)`.

* `AIProviderFactory` materializes a concrete provider actor from a
  config. It has both a synchronous variant (for UI rendering where
  blocking Keychain reads are acceptable) and an async variant
  (preferred everywhere else).

* `AIProviderManager` is `@MainActor @Observable`. It owns the active
  provider, performs the migration of any pre-existing
  `UserDefaults`-stored API key into Keychain on first launch, and is
  the single entry point for views: `generateResponse(...)` and
  `streamResponse(...)`.

* `AIRequestOptions` carries the resolved system prompt + temperature
  through every call so users can switch prompt presets at runtime
  without restarting.

* `LocalModelDiscovery` is the bridge between `OllamaProvider` /
  `LMStudioProvider` and the Settings UI: it normalizes the two
  different `/api/tags` vs `/v1/models` shapes into one
  `[DiscoveredModel]` array.

* **Streaming**: native streaming implementations exist for OpenAI
  (SSE `delta.content`), Anthropic (SSE `content_block_delta`), Ollama
  (JSONL with `done: true`), and LM Studio (SSE +
  `reasoning_content`). `SSEStream.swift` provides the shared parser.
  The protocol default falls back to non-streaming.

---

## Reader runtime

* `Book` (value type) is the parsed in-memory EPUB. It's recreated each
  time a reader window opens (parsing is cheap; the EPUB file lives in
  `Documents/Books/<id>.epub`).

* `EPUBWebViewRepresentable` wraps `WKWebView`. JavaScript bridges live
  in `Resources/Reader/`:
  * `selection-macos.js` / `selection-ios.js` — surface text selection
    plus a CFI to Swift via `webkit.messageHandlers.textSelection`.
  * `viewport-tracker.js` — reports which chapter / anchor is visible
    so `ReaderView` can keep `currentChapterIndex` and
    `scrollPosition` up to date.
  * `highlighter.js` — paints saved highlights into the WebView.
  * `search.js` — in-chapter search.

* **Position restoration**: when a book opens, `ReaderView.loadState`
  reads `StoredBook.scrollPosition` and queues it in
  `pendingScrollPosition`. After the WebView reports
  initialization, `restoreScrollPositionIfNeeded` injects
  `CruxHighlighter.setScrollPosition(...)` to jump to the saved spot.
  A future enhancement uses `StoredBook.lastReadingCFI` for
  element-precise restoration (the field exists today; the JS hook
  is the follow-up).

* **Annotation persistence** is atomic and crash-tolerant:
  `BookStorage.saveAnnotations` writes to `<id>.json.tmp`, rotates
  the live file into `<id>.json.bak`, then renames temp → live.
  `loadAnnotations` recovers from the backup if the live file is
  missing or fails to decode.

---

## Settings & theming

* `AppSettings` is a single-row SwiftData model. The first launch
  creates it; subsequent loads pull it via `@Query` and write through
  bindings.

* `ThemeManager` watches `AppSettings.theme` and pushes
  `ColorScheme?` through the environment. Themes include Light, Dark,
  System, Sepia, Night Mode, and High Contrast (pure white on pure
  black, exceeds WCAG AAA).

* `AIPromptPreset` enumerates the built-in system prompts (Scholarly,
  Casual, Socratic, Minimalist, Technical) plus a `.custom` sentinel
  that reads from `AppSettings.customSystemPrompt`.

* **Liquid Glass**: macOS 26 ships `glassEffect`/`buttonStyle(.glass)`/
  `scrollEdgeEffectStyle`. The deployment target is still macOS 14.0
  so every adoption goes through the shim modifiers in
  `Shared/Views/LiquidGlass.swift`: `cruxGlassCard`, `cruxGlassFloating`,
  `cruxGlassBar`, `cruxScrollEdgeSoft`, `cruxGlassButton`,
  `cruxSidebarMaterial`. Each falls back to system Materials (`.bar`,
  `.regularMaterial`, `.thickMaterial`) with hairline borders on
  older systems.

---

## Error handling

* `ErrorHandler` (singleton, `@MainActor @Observable`) is the chokepoint
  for user-facing errors. Views call `handle(_:context:)` with anything
  that conforms to `Error`; it routes through severity-aware logging
  (`AppLog.errors`) and surfaces either a toast (default) or a
  critical-error alert.

* `AppError` is the central user-presentable error envelope. The
  remaining domain-specific errors (`EPUBParserError`, `AIProviderError`,
  `BookStorageError`, etc.) are left alone where they don't cross
  module boundaries.

* `AIProviderError` carries `recoverySuggestion` so the
  `ThreadErrorCard` can show actionable next steps.

* `AppLog` exposes categorized `os.Logger` channels (`parser`, `ai`,
  `storage`, `security`, `errors`, `data`, `reader`, `ui`). Use these
  instead of `print()`.

---

## Where to add things

| If you're adding…                       | Touch these                                              |
|-----------------------------------------|----------------------------------------------------------|
| A new AI provider                       | New `…Provider.swift` (actor conforming to `AIProvider`); extend `ProviderType`; wire in `AIProviderFactory` (both branches); add a "Quick add" chip if no-setup |
| A new reader chrome control             | `Shared/Views/Reader/*.swift`; consult the Liquid Glass shims for materials |
| A new book metadata field               | `Book` + `BookMetadata` (parsed); `StoredBook` (persisted); migrate display sites |
| A new annotation field                  | `Highlight` / `BookAnnotations`; bump the JSON shape; the rolling backup handles transition |
| A new settings tab                      | Add a `Tab` in `SettingsView`; build a new view; persist via `AppSettings`; consider an `@Query` row |
| A new built-in AI prompt preset         | `AIPromptPreset` + bundled text + `symbolName` + tests |
| A new export format                     | `AnnotationExportService` or `ExportService`; remember to HTML-escape user-supplied fields |

---

## Project layout cheatsheet

```
Shared/
├── CruxApp.swift                # @main entry; WindowGroup setup; commands
├── Models/                      # SwiftData @Models + value types
├── Services/                    # Actors + value-type services
├── ViewModels/                  # @Observable state objects (e.g. NotesViewModel)
├── Views/                       # SwiftUI; subfolder `Reader/` for in-reader UI
└── Extensions/                  # Foundation/SwiftUI extensions

Resources/
└── Reader/                      # JavaScript injected into WKWebView

Tests/
└── *Tests.swift                 # XCTest cases
```
