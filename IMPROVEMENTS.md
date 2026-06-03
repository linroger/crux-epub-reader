# Crux EPUB Reader - Improvement Opportunities

**Last Updated:** 2026-05-23
**Codebase Analysis Version:** 1.1
**Status:** Initial Production Pass — items below marked `[DONE]` were executed in this session.

This document catalogs potential improvements, optimizations, and enhancements for the Crux EPUB reader application, organized by category and priority.

---

## Implementation Log — 2026-05-23

Executed in this pass to lift the app toward production quality:

- **[DONE] 1.2 Cover Image Caching** — Added `CoverImageCache` (actor + NSCache, 64 MB ceiling, 200-entry limit) with on-demand thumbnail generation (`Shared/Services/CoverImageCache.swift`) and a new `CachedCoverView` SwiftUI helper. Replaced direct `NSImage(data:)` calls in `BookListRow` and `BookGridRow` so library scrolling no longer decodes full-resolution covers on every render.
- **[DONE] 3.3 Structured Logging** — Introduced `AppLog` (`Shared/Services/AppLog.swift`) exposing categorized `os.Logger` channels (`parser`, `ai`, `storage`, `security`, `errors`, `data`, `reader`, `ui`). Replaced ad-hoc `print()` calls in `AIProviderManager`, `AIProviderConfig`, `ErrorHandler`, `ExportService`, and `ReaderView`. `ErrorHandler.logError` now emits at the appropriate severity (`fault` / `error` / `warning` / `info`).
- **[DONE] 4.2 API Error Recovery** — Added `RetryPolicy` (`Shared/Services/RetryPolicy.swift`) with exponential backoff (0.8s → 1.6s → 3.2s, 15s ceiling), transient-error classifier (network drops, 408/429/5xx, URLSession transient codes), and wired it through `AIProviderManager.generateResponse(...)`. Bad keys and 4xx still surface immediately.
- **[DONE] 5.4 HTML Export Sanitisation** — `AnnotationExportService.exportAsHTML` now escapes book title, author, chapter IDs, and bookmark fields at every interpolation point and emits a strict `Content-Security-Policy` meta tag. Replaced force-unwrapped `UTType` with safe optional binding in `saveToFile`.
- **[DONE] 5.5 Custom Provider URL Validation** — `SettingsView` now validates the user-entered base URL for HTTPS scheme/host, surfaces a contextual warning row when the URL is malformed or HTTP-non-local, and disables Save until the URL parses. iOS keyboard hint set to `.URL` with disabled autocapitalize.
- **[DONE] 2.2 Onboarding Experience** — New `OnboardingView` (`Shared/Views/OnboardingView.swift`) presents a four-page welcome covering reading, highlights/AI threads, provider/Keychain story, and stats. Stored in `AppSettings.hasSeenOnboarding`; auto-shows on first launch via `ContentView`, and re-triggerable from the About settings tab.
- **[DONE] 7.1 VoiceOver Optimisation (library)** — Library list and grid rows now expose a combined accessibility element with a descriptive label (`"Title, by Author, NN percent read, selected"`), `.isButton` trait, and contextual hint, so VoiceOver users get a meaningful announcement on every book.
- **[DONE] Liquid Glass availability hardening** — `SettingsView` and `LibraryView` previously gated macOS 26 APIs (`buttonStyle(.glass)`, `glassEffect`, `scrollEdgeEffectStyle`, `buttonStyle(.glassProminent)`) on `#if compiler(>=6.2)`. That fires whenever building with Swift 6.2+ even on a macOS 14 deployment target, which broke the build under Xcode 26. Replaced with `ViewModifier` shims (`AddProviderButtonStyle`, `ProviderCardBackground`, `SoftScrollEdgeEffectIfAvailable`, `LiquidGlassCardIfAvailable`, `GlassProminentButtonIfAvailable`) that use `#available(macOS 26.0, *)` at runtime. Build now succeeds.

### Build verification

`xcodebuild -scheme Crux_macOS -destination 'platform=macOS' build` ⇒ **BUILD SUCCEEDED** (SDK 26.2, deployment target macOS 14.0). Only pre-existing warnings remain (Sendable capture in `TagManagementService`, MainActor isolation on `pauseSession`/`resumeSession` in `ReaderView`, unused locals). None introduced by this change set.

---

## Implementation Log — 2026-05-23 (pass 2)

### Local AI providers — Ollama & LM Studio

- **`ProviderType` extended** with `.ollama` and `.lmstudio` cases (`Shared/Models/AIProviderConfig.swift`). Each carries a default URL (11434 / 1234), subtitle copy, SF Symbol, `requiresAPIKey == false`, `isOnDevice == true`, and `supportsModelDiscovery == true`. Factories `AIProviderConfig.createOllama` / `createLMStudio` added.
- **`OllamaProvider`** (`Shared/Services/OllamaProvider.swift`) — actor implementing `AIProvider`. Talks to `/api/chat` for completions (rich error envelope; specifically detects the 404 "model not installed" case and tells the user to run `ollama pull <model>`). Exposes `discoverModels(baseURL:)` against `/api/tags`, returning `InstalledModel { name, sizeBytes, modifiedAt, displaySize }`.
- **`LMStudioProvider`** (`Shared/Services/LMStudioProvider.swift`) — actor implementing `AIProvider` via `/v1/chat/completions` (OpenAI-shape). Sends a placeholder `Bearer lm-studio` because some LM Studio builds expect any non-empty token. `discoverModels(baseURL:)` against `/v1/models` returns `InstalledModel { id, ownedBy }`. Parser falls back to `reasoning_content` when LM Studio is hosting a reasoning model.
- **Shared URL helpers** moved to `Shared/Services/LocalProviderURL.swift` (`trimmedTrailingSlash`, `appendingPath`) so both providers can use them without redeclaration.
- **`LocalModelDiscovery`** (`Shared/Services/LocalModelDiscovery.swift`) — single entry point that returns `[DiscoveredModel]` for the SettingsView. Normalizes Ollama and LM Studio's slightly different shapes.
- **`AIProviderFactory`** dispatches the two new cases in both the sync and async constructor paths.
- **`AIProviderManager.discoverLocalModels(for:)`** — manager-level convenience the Settings UI calls.

### Settings UX for local providers

- Provider picker rows now show `displayName + subtitle + symbol`.
- When `.ollama` / `.lmstudio` is selected, an "API keys not required" privacy callout replaces the auth section.
- Model field is replaced with a discovery picker: a "Refresh installed models" button hits the local server and populates the picker; states are `idle / loading / loaded(count) / empty / failed(message)`. Tailored error message when the server isn't responding ("Ollama isn't responding at … — start it with `ollama serve`").
- Empty-state of the AI Providers tab gains three "quick add" chips for Apple Intelligence, Ollama, and LM Studio, each one-tap creating a default-configured provider and opening the edit sheet.
- `isValid` validation updated to accept "no API key + valid URL" for the new local types.
- `ProviderRow` now shows the provider-type SF Symbol (instead of a generic check) plus an "on-device" lock-shield badge for local providers.

### ThreadPanel UI overhaul

- **`ThreadPanelState.LastAction`** added so a transient failure can be retried in-place. `canRetry` uses `RetryPolicy.isTransient(error)` to decide whether the Retry button appears.
- **`retryLastAction(book:chapter:)`** re-issues either the initial thread call or the most recent follow-up, depending on `LastAction`.
- **`activeModelLabel`** exposes "Provider · model" so the UI can display the actual model the user is running.
- **`AILoadingView` redesigned** — three breathing dots with staggered phase animation (no more 360° spinning sparkle), provider+model label, calmer color treatment. Friendlier for the 15-60s waits typical of local inference.
- **`ThreadErrorCard`** — new component that distinguishes configuration errors (suggests "Open Settings") from transient errors (shows "Retry"), uses `AIProviderError.recoverySuggestion` when present, and renders `error.localizedDescription` selectable.
- **`ThreadMessageView`** — hover reveals a "Copy" affordance on assistant messages; tapping it flips to "Copied" for 1.5s. Lets users pull margin notes into other tools without selecting text manually.
- **Optimistic user-message rollback** — when `continueThread` errors, the just-added user message is removed so a subsequent retry doesn't duplicate it.

### Library card visual polish

- **`BookGridCard`** rebuilt around a cleaner Books.app-style aesthetic: cover floats on its own soft shadow rather than living inside a bordered card; hover lifts the cover; subtle background pill on hover instead of the previous heavy border + scale.
- **Progress bar** is now a thin capsule (4 pt) tinted green when finished, accent color while reading; the "%" label switches to "Done" in green for finished books.
- **`FinishedBadge`** added — small white-checkmark-in-green-pill overlay anchored bottom-left of finished covers.

### Reader chrome refinement

- Toolbar consolidated: chapters as its own button (with ⌘L shortcut), bookmarks now a single menu (Add / View All / count), highlights stays direct, export moved into a "More" overflow menu so it's no longer competing with primary actions.
- Bookmark icon swaps to `bookmark.fill` when at least one bookmark exists, giving a quick at-a-glance signal.

### EPUB parser resilience

- `EPUBParser.parse(url:)` now logs through `AppLog.parser`: file size on entry, extract failures, container-fallback paths used, OPF recovery via recursive search, and final chapter count on success. Makes diagnosing malformed EPUBs from logs alone tractable.

### Build verification (pass 2)

`xcodebuild -scheme Crux_macOS -destination 'platform=macOS' build` ⇒ **BUILD SUCCEEDED**. No errors. Only the same pre-existing warnings as the previous pass.

---

## Implementation Log — 2026-06-04

### More AI providers + TOC HTML fix + iOS portability

- **DeepSeek / MiniMax / Kimi (Moonshot) providers** — added three first-class
  `ProviderType` cases (`Shared/Models/AIProviderConfig.swift`). Each carries a
  default OpenAI-compatible endpoint (`api.deepseek.com/v1/chat/completions`,
  `api.minimax.io/v1/text/chatcompletion_v2`, `api.moonshot.ai/v1/chat/completions`),
  a curated default-model list, a subtitle, and an SF Symbol. `AIProviderFactory`
  (both sync + async paths) routes all three through the existing
  `OpenAIProvider` — they share OpenAI's request/response shape and native SSE
  streaming, so no new networking code was needed. Convenience factories
  `createDeepSeek` / `createMiniMax` / `createKimi` added. They auto-surface in
  the Settings provider picker via `ProviderType.allCases`.
- **Editable model field for cloud providers** — the Settings model row used to
  be a fixed `Picker` over the bundled default list, so a custom or
  newly-released model name was impossible to enter. It's now an editable
  `TextField` plus a "Suggested models" menu that fills from the bundled list.
  This also fully supports the "custom endpoints" requirement (Custom provider
  already existed; now every cloud provider accepts arbitrary model IDs).
- **LM Studio verified** — traced routing (`AIProviderFactory` → `LMStudioProvider`),
  `/v1/models` discovery, and OpenAI-shape `/v1/chat/completions` streaming with
  the `reasoning_content` fallback. Working end-to-end; no change required.
- **HTML tags no longer leak into the Table of Contents** — root cause was the
  anchor/text regexes capturing only `[^<]+`, which truncated titles wrapped in
  nested markup (`<a><span class="num">1.</span> Intro</a>`) or dropped the entry
  entirely. New `EPUBParser.cleanTitle(_:)` strips tags, decodes entities, and
  collapses whitespace; applied in `parseNavList` (EPUB3 nav — capture widened to
  `[\s\S]*?`, href now accepts single **or** double quotes), `processNavPointRecursive`
  (EPUB2 NCX `<text>`), and `extractChapterTitle` (spine/HTML fallback headings).
  Verified with a standalone Swift harness: 5/5 cases pass, including the
  nested-`<span>`/`<i>`/`<br>` cases the old regex failed.
- **iOS build restored** — `RecentBooksSection.swift` and `BookDetailView.swift`
  constructed `NSImage(data:)` directly in shared code, breaking the iOS target
  (`cannot find 'NSImage' in scope`). Both now use the existing cross-platform,
  cache-backed `CachedCoverView`, matching `BookListRow` / `BookGridCard`.
- **Build status:** `xcodebuild -scheme Crux_macOS` ⇒ **BUILD SUCCEEDED**;
  `xcodebuild -scheme Crux_iOS -destination 'iPhone 17 Pro'` ⇒ **BUILD SUCCEEDED**.

---

## Implementation Log — 2026-05-23 (pass 3)

### Liquid Glass / native macOS polish

- **`Shared/Views/LiquidGlass.swift`** — single source of truth for Liquid Glass + Materials shims. Exposes `cruxGlassCard`, `cruxGlassFloating`, `cruxGlassBar`, `cruxScrollEdgeSoft`, `cruxGlassButton`, `cruxSidebarMaterial`. Each uses `#available(macOS 26.0, …)` to opt into the real Liquid Glass APIs and falls back to system Materials (`.regularMaterial`, `.thickMaterial`, `.bar`) on macOS 14–25. `LibraryView` and `SettingsView` were de-duped against this module.
- **ThreadPanel chrome** — header is now `cruxGlassBar`, body sits on `.regularMaterial`, follow-up composer uses the central glass card, empty-state tips card uses `cruxGlassCard`. Provider name + model now show under the title.
- **Settings tabs** — Settings window now `minWidth: 620, minHeight: 540`, gained a fourth tab ("AI Prompt") with native picker rows.

### AI prompt customization (full E2E)

- New `AIPromptPreset` enum with five built-in presets — Scholarly, Casual, Socratic, Minimalist, Technical — plus a `.custom` sentinel that pulls from `AppSettings.customSystemPrompt`. Each preset carries its own SF Symbol, subtitle, and bundled prompt text.
- `AppSettings` extended with `activePromptPresetId` (defaults to scholarly) and `customSystemPrompt`.
- **`AIPromptSettingsView`** — new tab inside Settings that lists every preset as a tappable card with selection ring, plus an always-visible `TextEditor` for the custom prompt. A "Templates" menu lets users seed the custom field from any built-in preset.
- **Protocol change**: `AIProvider.generateResponse` and `streamResponse` now take an `AIRequestOptions` (system prompt, temperature). All providers updated. A back-compat shim on the protocol lets callers continue to pass no options.
- `ReaderView.resolvePromptFromSettings()` reads the active preset and forwards to `ThreadPanelState.resolvedSystemPrompt`, which the streaming calls package into `AIRequestOptions.systemPrompt`.

### AI response streaming (native)

- **`Shared/Services/SSEStream.swift`** — minimal Server-Sent Events parser + an `URLSession.dataChunks(for:)` helper that turns `bytes(for:)` into a buffered `AsyncThrowingStream<Data, Error>`.
- **`OpenAIProvider.streamResponse`** — flips body to `stream: true`, parses `delta.content` from each SSE event.
- **`ClaudeProvider.streamResponse`** — flips body to `stream: true`, handles Anthropic's `content_block_delta.delta.text` events and `error` events.
- **`OllamaProvider.streamResponse`** — JSONL streaming (one JSON object per line), reads `message.content` chunks and terminates on `done: true`.
- **`LMStudioProvider.streamResponse`** — OpenAI-shaped SSE, also accepts `reasoning_content` for reasoning models.
- **`AppleIntelligenceProvider`** — already had streaming; updated for the new options API.
- **`AIProviderManager.streamResponse(...)`** — manager-level entry point. *Not* wrapped in `RetryPolicy` because mid-stream retry would duplicate visible tokens.
- **`ThreadPanelState`** — switched `startThread`/`continueThread`/`retryLastAction` to consume the stream, accumulating into `streamingText`. New `applyChunk(_:to:)` helper detects whether a provider emits cumulative or delta chunks (Apple Intelligence emits cumulative; others emit deltas) and merges correctly. Optimistic user-message rollback retained.

### Reader resilience features

- **Network reachability**: new `NetworkMonitor` (`@MainActor @Observable`, `NWPathMonitor`-backed) singleton. ThreadPanel header surfaces an "Offline" pill **only** when the active provider is cloud (the indicator stays hidden for Ollama / LM Studio / Apple Intelligence).
- **Annotation write safety**: `BookStorage.saveAnnotations` now writes via `<id>.json.tmp` → rename → keeps `<id>.json.bak` as a single-revision rollback. `loadAnnotations` automatically recovers from the backup if the live file is missing or its JSON fails to decode. `removeAnnotations` deletes both files. Logs through `AppLog.storage` when recovery kicks in.
- **`StoredBook.lastReadingCFI`** — new field laying groundwork for precise CFI-based position restoration (the JS viewport tracker change is a follow-up; scrollPosition restoration already works end-to-end).

### Reading-time estimation

- **`ReadingTimeEstimator`** — HTML-stripping whitespace tokenizer with `minutes(forText:wpm:)`, `totalMinutes(forChapters:wpm:)`, and friendly `label(forMinutes:)` ("12 min read", "2 hr 15 min read"). Default 220 WPM. Ready for surfaces that want to render it on book detail / library rows.

### Accessibility

- **Reduce Motion**: `AILoadingView` checks `@Environment(\.accessibilityReduceMotion)` and renders a static dot cluster (no breathing animation) when reduce motion is on. `OnboardingView` page transitions also disable animation when reduce-motion is on.
- **`AppSettings.respectsReduceMotion`** added (default true) for future manual overrides.

### Cross-book search (extended)

- `NotesViewModel` search now also matches inside every AI thread message — a thread that discussed "kenosis" surfaces even when the original highlight didn't contain that word.

### Note templates

- New `NoteTemplate` enum with six scaffolds (Character Analysis, Theme, Citation, Question, Connection, Vocabulary). Each is a markdown scaffold with bracketed prompts.
- `AnnotationEditView` gains a "Templates" menu in the header next to "Your Note" — appends template body to existing text so users can stack scaffolds.

### Build verification (pass 3)

`xcodebuild -scheme Crux_macOS -destination 'platform=macOS' clean build` ⇒ **BUILD SUCCEEDED**. No new warnings introduced.

---

## Implementation Log — 2026-05-23 (pass 7)

### Annotation portability — `.cruxnotes` bundles

- **`CruxNotesBundle`** (6.5). Self-describing Codable bundle carrying
  `formatVersion`, `bookId`, `bookTitle`, `bookAuthor`, `exportedAt`,
  and the full `BookAnnotations` payload. Backwards-compatible by
  construction: future fields can be added without breaking older
  importers, and importers refuse unknown major versions explicitly
  via `ImportError.unsupportedVersion`.
- **`CruxNotesIO`** actor — `encode` / `decode` / `read(from:)` /
  `write(_:to:)`, plus a `merge(bundle:into:)` that de-duplicates by
  highlight id and bookmark id (collisions keep the local copy,
  never destructive) and returns a `MergeSummary` for the UI.
- **`UTType.cruxNotesBundle`** registered (`exportedAs:
  "com.crux.notes-bundle"`) so the Save and Open panels filter
  cleanly and Finder gets a meaningful description.
- **`ExportFormat.cruxNotes`** added to the existing export picker.
  `AnnotationExportView` lists it as "Crux Notes Bundle" alongside
  Markdown / HTML / Plain Text / JSON, with a contextual description.
  The picker shipped via `AnnotationExportService.exportAnnotations`
  which is now `async` to accommodate the actor hop into
  `CruxNotesIO.encode`.
- **File menu → Import Annotations…** new command in `CruxApp`
  flips `AppState.showImportNotesPanel`; `ContentView` runs the
  picker, decodes the bundle, matches by `bookId` (exact) then by
  case-insensitive title/author (cross-library), merges into the
  matched book's annotations, and surfaces the summary
  ("Added 12 highlights, 3 bookmarks; skipped 4 duplicates").

### Documentation

- **JSDoc on reader JS modules** (9.3). Header docblocks added to
  `viewport-tracker.js`, `highlighter.js`, `cfi.js`, and `search.js`
  documenting the Swift↔JS message protocol (which
  `webkit.messageHandlers` channel each module posts to, what fields
  go in/out, what guards exist) and the simplified CFI element-path
  format.

### Tests (8.1 extension)

- `Tests/BookSearchIndexTests.swift` — empty index, build population,
  cross-chapter hits, case-insensitivity, empty-query short-circuit,
  HTML-strip independence.
- `Tests/BookStorageErrorTests.swift` — localized-description content
  for every error case.
- `Tests/CruxNotesBundleTests.swift` — encode/decode round trip,
  future-version rejection, malformed-JSON detection, merge
  de-duplication, `MergeSummary.humanReadable` formatting.

### Build verification (pass 7)

`xcodegen generate` + `xcodebuild -scheme Crux_macOS -destination 'platform=macOS' build`
⇒ **BUILD SUCCEEDED** (one inline fix: `exportAnnotations` had to be
made `async` because the new `.cruxNotes` branch hops to the
`CruxNotesIO` actor). No new warnings introduced; pre-existing
warnings on `LibraryBackupService`, `ReaderView` lifecycle hooks, and
`ReadingGoalsView` remain.

---

## Implementation Log — 2026-05-23 (pass 6)

### Reader navigation

- **Internal EPUB link navigation** (2.4 partial). `EPUBWebViewRepresentable`
  now implements `WKNavigationDelegate.decidePolicyFor navigationAction`:
  initial loads pass through; user link activations are intercepted.
  HTTP(S) links open in the system browser via `NSWorkspace`/`UIApplication.open`;
  internal links surface to Swift via a new `onInternalLink: (path,
  fragment) -> Void` closure. `ReaderView.followInternalLink` resolves
  the link's last path component against `Chapter.filePath` (with
  fragment as a tie-breaker), pushes the current `(chapterIndex,
  scrollPosition)` onto a back stack, then navigates. Same-file
  fragment-only links scroll to the anchor in place. Unresolved links
  log a warning rather than navigating nowhere silently.

- **Back button** (companion to 2.4). Reader toolbar gains a
  `chevron.backward.circle` button that pops the navigation history
  and restores the chapter + scroll position the user had before
  following a footnote / glossary link. Hidden when the stack is
  empty so it doesn't clutter the chrome on first read.

### Robustness

- **Disk-space pre-check on import** (4.5 partial). `BookStorage.importBook`
  now measures the source file size and the destination volume's
  `systemFreeSize` before invoking `copyItem`. A 16 MB safety margin
  covers FS metadata and the annotation file that's about to follow.
  On failure a typed `BookStorageError.insufficientDiskSpace(needed:
  available:)` flows out with a friendly localized description.
  `copyItem` failures now bubble through `.copyFailed` and the partial
  destination is cleaned up so retries don't trip on "file already
  exists".

### Discoverability

- **Keyboard shortcuts cheat sheet refresh** (9.4 update). The existing
  `KeyboardShortcutsView` (⌘/) was missing several shortcuts wired up
  during the pass-3/4 work. Added the `⌘L` table of contents, the
  `⌃⌘D` dictionary lookup, the `Left/Right Arrow` chapter shortcuts,
  and a new "Internal Links" section documenting the click-to-follow
  + Back button flow added in this pass.

### Documentation

- **CONTRIBUTING.md** (9.2). Setup, build commands, conventions,
  commit-message style, and PR checklist. Cross-references
  `ARCHITECTURE.md` for layered overview and `IMPROVEMENTS.md` for
  open work.

### Build verification (pass 6)

`xcodegen generate` + `xcodebuild -scheme Crux_macOS -destination 'platform=macOS' build`
⇒ **BUILD SUCCEEDED**. No new warnings introduced.

---

## Implementation Log — 2026-05-23 (pass 5)

### Reader resilience

- **CFI-precise position restoration** (2.1, full E2E). `viewport-tracker.js`
  now emits an element-level CFI path along with each visible-section
  update (top of viewport, biased toward block elements: `p`, `h*`,
  `li`, `blockquote`, etc.). `highlighter.js` gained `scrollToCFI(...)`,
  accepting either the combined start/end form (used by highlight
  navigation) or a bare element path (used by reading-position
  restore). `EPUBWebViewRepresentable.onVisibleSection` closure
  extended to `(Int, Double, String?)` so the CFI rides through to
  Swift. `ReaderView` persists `currentReadingCFI` into
  `StoredBook.lastReadingCFI` on every progress save and prefers it
  over the scroll-percentage fallback during `restoreScrollPositionIfNeeded`.
  When the CFI no longer resolves (e.g., CSS changes reflow the
  chapter) the chapter loads at the top — `scrollPosition` remains
  the recovery anchor for the next reopen.

### Library — surfaced reading-time

- **Cached reading-time estimates** (6.4 surfaced). `StoredBook` gained
  `cachedReadingMinutes: Int = 0` (SwiftData-default for migration
  safety). Populated during `ContentView.importBook` and
  `recoverOrphanedBooks` using
  `ReadingTimeEstimator.totalMinutes(forChapters:)`. Lazy backfill
  added to `ReaderView.loadState` for books imported before the field
  existed — first reader-open computes once and saves. Library
  list rows (`ProgressLine`) and grid cards (`BookGridCard`) now show
  the "~12 min read" / "~2 hr 15 min read" label inline with the
  progress strip; row hides label entirely when the cache is 0
  (better than rendering "less than a minute" for every freshly
  imported book pre-first-open).

### Book-wide search — index caching

- **`BookSearchIndex` service** (1.5 perceived-perf path). Wraps the
  existing `HTMLTextExtractor.findMatches` call site with a
  pre-stripped plain-text + lowercased cache built once per book.
  Replaces the per-keystroke chapter-by-chapter HTML-stripping loop in
  `ReaderView.performBookSearch`, so subsequent queries are tight
  substring scans over the cached strings. Index is built lazily on
  first search (cost deferred until ⌘F in book scope is actually used)
  and reused across keystrokes. Snippet format unchanged — the
  `BookSearchResultsView` UI didn't need to change.

### LibraryView decomposition

- **3.2 partial.** `LibraryView.swift` extracted from 2389 → 2051 lines:
  - `Shared/Views/Library/BookListRow.swift` — `BookListRow`,
    `MetadataLine`, `ProgressLine`, `AnnotationLine`.
  - `Shared/Views/Library/BookGridCard.swift` — `BookGridCard`,
    `FinishedBadge`.
  Pure cut/paste; no behavior change. Further extraction (toolbar,
  filter chips, batch operations, sidebar) is a follow-up — these
  two were the largest ones and account for most of the size drop.

### Build verification (pass 5)

`xcodegen generate` + `xcodebuild -scheme Crux_macOS -destination 'platform=macOS' build`
⇒ **BUILD SUCCEEDED**. No new warnings introduced.

---

## Implementation Log — 2026-05-24 (pass 4)

### Reader UX

- **Progress scrubber bar** (2.4) — `Shared/Views/Reader/ProgressScrubber.swift`. Replaces the static 4 pt bar with a tappable/draggable 6 pt strip (grows to 8 pt while pressed). Hovering shows a caret + tooltip with the destination chapter title; tapping or dragging seeks via `navigateToChapter`. Exposes `accessibilityAdjustableAction` for VoiceOver users.
- **Dictionary lookup** (6.1) — `Shared/Services/DictionaryLookup.swift`. `⌃⌘D` from the reader feeds the current selection into the `dict://` URL scheme so Dictionary.app's lookup panel opens with the word. Caps at the first two whitespace-separated tokens — long selections weren't being handled well by Dictionary.app's input.
- **Multi-window** (2.6) — `Shared/Views/BookWindowScene.swift` is the dedicated reader scene keyed on `UUID`. CruxApp wires it as a `WindowGroup(id: "book-reader", for: UUID.self)`. Library list + grid context menus gained an "Open in New Window" item before "Show Details". Each window holds its own ThreadPanelState, so side-by-side reading doesn't share selection/AI state.
- **Drag-and-drop progress** (2.7) — `Shared/Views/BatchImportProgressView.swift`. Multi-file drops now show a 440-pt glass-floating sheet with one row per file (pending → importing → succeeded/failed). Single-file drops still skip the sheet to avoid flicker.

### Native macOS chrome

- **High-contrast theme** (7.4) — `AppTheme.highContrast` (pure white-on-pure-black, >21:1 contrast ratio, exceeds WCAG AAA). Reuses the existing `ThemePreset.highContrast` plumbing. `ThemeManager.colorScheme` returns `.dark` for it so chrome reads correctly.

### Citations & academic features

- **Citation export** (6.2) — `Shared/Services/CitationFormatter.swift`. Generates APA 7, MLA 9, Chicago (notes-bibliography), and BibTeX citations from `Book` + `BookMetadata`. Author inversion (`"Jane Austen"` → `"Austen, J."` for APA, `"Austen, Jane"` for MLA), multi-author handling via the canonical "and / & / ;" separators, n.d. fallback when year is missing, BibTeX citation key generated from surname + year (or slugified title prefix).

### Code health

- **ClaudeService deprecation** (3.1) — removed `Shared/Services/ClaudeService.swift` and its `createFromLegacySettings` shim on `ClaudeProvider`. The migration of any pre-existing UserDefaults key still happens once via `AIProviderManager.migrateFromLegacySettings()`. Tests still pass.

### Tests (8.1)

- `Tests/ReadingTimeEstimatorTests.swift` — word counting, HTML stripping, WPM scaling, label formatting, multi-chapter sums.
- `Tests/RetryPolicyTests.swift` — classification of every transient/permanent error case, plus end-to-end execute() retry behavior.
- `Tests/LocalProviderURLTests.swift` — `String.trimmedTrailingSlash` and `appendingPath` correctness for the Ollama/LM Studio URL builders.
- `Tests/CitationFormatterTests.swift` — APA, MLA, Chicago, and BibTeX outputs for the canonical Pride and Prejudice example plus missing-author / missing-year fallbacks.
- `Tests/AIPromptPresetTests.swift` — every non-custom preset ships a non-trivial system prompt, all symbols and display names are unique, raw-value round-trip.

### Documentation

- **`ARCHITECTURE.md`** — layer diagram, concurrency model, AI provider architecture, reader runtime (CFI + annotation persistence), settings & theming (Liquid Glass shims), error handling, "where to add things" cheatsheet, project layout.

### Build verification (pass 4)

`xcodebuild -scheme Crux_macOS -destination 'platform=macOS' build` ⇒ **BUILD SUCCEEDED**. One in-pass fix required (`ThemeManager.colorScheme` switch needed a `.highContrast` arm). No new warnings introduced.

Not in scope for this pass (left for follow-up; rationale noted inline below):

- 1.1 Library virtualization — current library already uses `LazyVStack`/`LazyVGrid`; pagination only matters at very large libraries and risks regressing recent-books layout. Defer until profiling confirms a problem.
- 1.5 Search indexing & 1.6 streaming UI — meaningful UX work; require dedicated design pass.
- 6.x feature ideas, 7.x accessibility deep-dive, 8.x deeper test coverage — multi-session work tracked here.

---

## Table of Contents

1. [Performance Optimizations](#1-performance-optimizations)
2. [User Experience Enhancements](#2-user-experience-enhancements)
3. [Code Quality & Architecture](#3-code-quality--architecture)
4. [Robustness & Error Handling](#4-robustness--error-handling)
5. [Security Improvements](#5-security-improvements)
6. [New Feature Opportunities](#6-new-feature-opportunities)
7. [Accessibility](#7-accessibility)
8. [Testing & Quality Assurance](#8-testing--quality-assurance)
9. [Documentation](#9-documentation)

---

## 1. Performance Optimizations

### 1.1 Library View Virtualization
**Priority:** High | **Impact:** High | **Effort:** Medium

**Current State:** `LibraryView.swift` (2200+ lines) renders all books in the library at once using `ForEach` loops.

**Problem:** Libraries with hundreds of books will experience slow initial render times and high memory usage.

**Recommendation:**
- Implement `LazyVStack`/`LazyVGrid` for book lists
- Add pagination with "Load More" or infinite scroll
- Consider `@Query` pagination using SwiftData's `fetchLimit` and `fetchOffset`

```swift
// Example: Paginated book query
@Query(sort: \StoredBook.dateAdded, order: .reverse)
var allBooks: [StoredBook]

@State private var displayLimit = 50

var displayedBooks: [StoredBook] {
    Array(allBooks.prefix(displayLimit))
}
```

---

### 1.2 Cover Image Caching & Optimization
**Priority:** High | **Impact:** High | **Effort:** Medium

**Current State:** Cover images are extracted from EPUBs and stored as raw `Data` in `StoredBook`.

**Problem:** Large cover images consume excessive memory; no thumbnail generation or caching strategy.

**Recommendation:**
- Generate thumbnails (150x200) for grid view; load full resolution on-demand
- Use `NSCache` for in-memory cover caching
- Consider disk caching with expiration for extracted covers
- Implement progressive image loading (blur-to-sharp transition)

```swift
actor CoverImageCache {
    static let shared = CoverImageCache()
    private var cache = NSCache<NSString, NSImage>()

    func thumbnail(for bookId: UUID, size: CGSize) async -> NSImage? {
        let key = "\(bookId)-\(Int(size.width))x\(Int(size.height))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        // Generate and cache thumbnail...
    }
}
```

---

### 1.3 Annotation Loading Optimization
**Priority:** Medium | **Impact:** Medium | **Effort:** Low

**Current State:** `BookStorage.loadAnnotations(for:)` loads the entire JSON file for a book's annotations.

**Problem:** Books with hundreds of highlights load all annotation data at once, including potentially large conversation threads.

**Recommendation:**
- Implement lazy loading for thread message content
- Add indices for common queries (by chapter, by category)
- Consider SQLite/SwiftData migration for annotations to enable efficient queries
- Load threads on-demand when user expands them

---

### 1.4 WebView Performance
**Priority:** Medium | **Impact:** Medium | **Effort:** High

**Current State:** Single `WKWebView` instance in `EPUBWebViewRepresentable`; entire chapter HTML loaded at once.

**Problem:** Large chapters with many images may cause rendering delays.

**Recommendation:**
- Implement WebView content pooling for chapter pre-caching
- Use `WKWebView` configuration optimization (disable unnecessary features)
- Consider lazy image loading in reader.css (`loading="lazy"`)
- Pre-render next/previous chapters in background
- Investigate `WKWebView` process reuse for faster subsequent loads

```swift
// Pre-cache adjacent chapters
func preloadAdjacentChapters(current: Int) {
    let indices = [current - 1, current + 1].filter { $0 >= 0 && $0 < chapters.count }
    for index in indices {
        Task.detached(priority: .background) {
            await preRenderChapter(at: index)
        }
    }
}
```

---

### 1.5 Search Indexing
**Priority:** Medium | **Impact:** High | **Effort:** High

**Current State:** In-chapter search uses JavaScript DOM traversal; book-wide search not visible in codebase.

**Problem:** Full-text search across entire books is slow without an index.

**Recommendation:**
- Build full-text search index on book import using `SearchKit` or custom inverted index
- Store index in separate file per book
- Support advanced queries (phrase search, boolean operators)
- Consider Core Spotlight integration for system-wide book search

---

### 1.6 AI Response Streaming
**Priority:** Medium | **Impact:** Medium | **Effort:** Medium

**Current State:** AI providers have `supportsStreaming` flags but streaming isn't fully implemented in the UI.

**Problem:** Users wait for complete AI responses; no incremental feedback.

**Recommendation:**
- Implement `AsyncSequence`-based streaming in `ThreadPanel`
- Show tokens as they arrive for better perceived performance
- Add typing indicator during AI generation
- Consider cancellation support for long responses

---

## 2. User Experience Enhancements

### 2.1 Reading Position Restoration
**Priority:** High | **Impact:** High | **Effort:** Low

**Current State:** Chapter index is persisted; scroll position within chapter may be lost.

**Problem:** Users lose exact position when switching between books or reopening the app.

**Recommendation:**
- Persist CFI (Canonical Fragment Identifier) as primary position marker
- Implement "Return to reading position" button if user navigates away
- Add visual bookmark indicator at last-read position
- Sync position to iCloud for cross-device continuity

---

### 2.2 Onboarding Experience
**Priority:** Medium | **Impact:** High | **Effort:** Medium

**Current State:** No visible onboarding flow; users must discover features manually.

**Problem:** AI features, annotation categories, and keyboard shortcuts may go undiscovered.

**Recommendation:**
- Add first-launch tutorial highlighting key features:
  - How to create highlights and start AI threads
  - Keyboard shortcuts (⌘H, ⌘A, etc.)
  - Collections and organization
  - Reading statistics
- Implement contextual tooltips on first use of features
- Add "Tips" section in settings

---

### 2.3 Highlight Color Customization
**Priority:** Low | **Impact:** Medium | **Effort:** Low

**Current State:** `SettingsView` has highlight color palette editor; limited to predefined colors per category.

**Problem:** Users may want custom colors or opacity levels.

**Recommendation:**
- Allow custom color picker for each annotation category
- Add opacity slider for highlight backgrounds
- Support highlight style options (underline, border, etc.)
- Import/export color schemes

---

### 2.4 Enhanced Navigation
**Priority:** Medium | **Impact:** Medium | **Effort:** Medium

**Current State:** TOC navigation, arrow keys for chapter changes, scroll for positioning.

**Problem:** No quick page/location jump; no reading progress bar with scrubbing.

**Recommendation:**
- Add progress scrubber bar showing book-wide position
- Implement "Go to location" dialog (percentage, page, CFI)
- Add mini-map for chapter overview
- Support hyperlink navigation within EPUBs (internal links)
- "Back" button after following internal links

---

### 2.5 Dark Mode Synchronization
**Priority:** Medium | **Impact:** Medium | **Effort:** Low

**Current State:** Themes include Light, Dark, Sepia, Night Mode; managed via `AppTheme` enum.

**Problem:** May not automatically sync with macOS/iOS system appearance when "System" is selected.

**Recommendation:**
- Ensure `@Environment(\.colorScheme)` properly triggers theme updates
- Smoothly animate theme transitions in WebView content
- Add scheduled theme switching (auto-dark mode at sunset)

---

### 2.6 Multi-Window Support (macOS)
**Priority:** Low | **Impact:** Medium | **Effort:** High

**Current State:** Single window architecture implied by `ContentView` structure.

**Problem:** Users can't read multiple books simultaneously.

**Recommendation:**
- Implement `WindowGroup` with book-specific scene
- Each window maintains independent reading state
- Add "Open in New Window" context menu action

---

### 2.7 Drag & Drop Improvements
**Priority:** Low | **Impact:** Low | **Effort:** Low

**Current State:** Library supports drag & drop import.

**Problem:** No progress indication for large file imports; no multi-file feedback.

**Recommendation:**
- Add import progress sheet with file list
- Show parsing status per file
- Allow cancellation of batch imports
- Display import summary (succeeded/failed counts)

---

## 3. Code Quality & Architecture

### 3.1 ClaudeService Deprecation
**Priority:** High | **Impact:** Medium | **Effort:** Medium

**Current State:** `ClaudeService.swift` exists alongside modular `AIProvider` system.

**Problem:** Duplicate code paths; migration partially complete based on git status.

**Recommendation:**
- Complete migration to `AIProviderManager`
- Remove `ClaudeService.swift` after all references updated
- Update legacy settings migration to handle all edge cases
- Add deprecation warnings during transition

---

### 3.2 View Decomposition
**Priority:** Medium | **Impact:** Medium | **Effort:** Medium

**Current State:** `LibraryView.swift` is 2200+ lines; `ReaderView.swift` is 1300+ lines.

**Problem:** Large files are harder to maintain, test, and reason about.

**Recommendation:**
- Extract logical sections into subviews:
  - `LibraryView` → `LibraryToolbar`, `LibraryFilterPanel`, `BookGrid`, `BookList`, `BatchOperationsView`
  - `ReaderView` → `ReaderToolbar`, `ReaderNavigationOverlay`, `AnnotationSidebar`
- Use `ViewBuilder` for conditional content
- Consider MVVM extraction with dedicated ViewModels

---

### 3.3 Structured Logging
**Priority:** Medium | **Impact:** Medium | **Effort:** Low

**Current State:** Uses `print()` statements for debugging.

**Problem:** No log levels, no persistence, difficult to filter in production.

**Recommendation:**
- Adopt `os.Logger` for structured logging
- Define subsystems: `com.crux.parser`, `com.crux.ai`, `com.crux.storage`
- Add log categories (debug, info, error, fault)
- Consider user-exportable logs for troubleshooting

```swift
import os

extension Logger {
    static let parser = Logger(subsystem: "com.crux", category: "EPUBParser")
    static let ai = Logger(subsystem: "com.crux", category: "AIProvider")
}

// Usage:
Logger.parser.info("Parsing EPUB: \(url.lastPathComponent)")
Logger.ai.error("API request failed: \(error.localizedDescription)")
```

---

### 3.4 Dependency Injection
**Priority:** Medium | **Impact:** Medium | **Effort:** High

**Current State:** Singletons (`BookStorage.shared`, `ErrorHandler.shared`) and environment injection mixed.

**Problem:** Hard to test; tight coupling to concrete implementations.

**Recommendation:**
- Define protocols for all services
- Use constructor injection where possible
- Create service container for managing dependencies
- Enable mock injection for testing

```swift
protocol BookStorageProtocol: Actor {
    func saveAnnotations(_ annotations: BookAnnotations, for bookId: UUID) async throws
    func loadAnnotations(for bookId: UUID) async throws -> BookAnnotations?
}

// Test mock
actor MockBookStorage: BookStorageProtocol {
    var savedAnnotations: [UUID: BookAnnotations] = [:]
    // ...
}
```

---

### 3.5 Error Type Consolidation
**Priority:** Low | **Impact:** Low | **Effort:** Low

**Current State:** Multiple error enums: `AIProviderError`, `BookStorageError`, parser errors.

**Problem:** Inconsistent error handling patterns across modules.

**Recommendation:**
- Define unified `CruxError` type with nested domains
- Standardize error codes for analytics
- Ensure all errors are user-presentable
- Add recovery suggestions where applicable

---

### 3.6 Swift Concurrency Audit
**Priority:** High | **Impact:** High | **Effort:** Medium

**Current State:** Mix of actors, `@MainActor`, and unstructured concurrency.

**Problem:** Potential race conditions in annotation updates; `ReadingSessionManager` complexity.

**Recommendation:**
- Audit all `Task {}` usages for proper cancellation
- Ensure annotation saves are serialized per book
- Use `TaskGroup` for parallelizable operations
- Add `@Sendable` annotations where missing
- Consider `AsyncStream` for continuous state updates

---

## 4. Robustness & Error Handling

### 4.1 EPUB Parsing Resilience
**Priority:** High | **Impact:** High | **Effort:** Medium

**Current State:** `EPUBParser` has extensive fallback logic but may fail on edge cases.

**Problem:** Malformed EPUBs may crash or show blank content.

**Recommendation:**
- Add more defensive parsing for malformed XML/HTML
- Implement graceful degradation (show raw text if HTML parsing fails)
- Add EPUB validation on import with user warnings
- Log parsing issues for debugging
- Consider libarchive fallback for unusual ZIP formats

---

### 4.2 API Error Recovery
**Priority:** High | **Impact:** High | **Effort:** Medium

**Current State:** `AIProviderError` includes rate limit and timeout cases.

**Problem:** No automatic retry logic; users must manually retry failed requests.

**Recommendation:**
- Implement exponential backoff with jitter for transient errors
- Add request queue with rate limiting awareness
- Show "Retry" button on failure with countdown
- Cache partial responses to resume interrupted generations
- Add circuit breaker pattern for provider health

```swift
actor RetryManager {
    func execute<T>(
        maxAttempts: Int = 3,
        baseDelay: Duration = .seconds(1),
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                let delay = baseDelay * Double(1 << (attempt - 1)) // Exponential
                try await Task.sleep(for: delay)
            }
        }
        throw lastError!
    }
}
```

---

### 4.3 Data Integrity Checks
**Priority:** Medium | **Impact:** High | **Effort:** Medium

**Current State:** Annotations stored as JSON; no integrity verification.

**Problem:** Corrupted annotation files could cause data loss.

**Recommendation:**
- Add checksum validation for annotation files
- Implement automatic backup before writes
- Add corruption detection and recovery prompts
- Consider WAL-style append-only logging for annotations

---

### 4.4 Offline Mode Handling
**Priority:** Medium | **Impact:** Medium | **Effort:** Medium

**Current State:** AI features require network connectivity.

**Problem:** No indication when offline; AI requests fail silently or with generic errors.

**Recommendation:**
- Add network reachability monitoring
- Show offline indicator in AI-dependent UI
- Queue annotation requests for later sync
- Prefer Apple Intelligence when offline (on-device)

---

### 4.5 File System Edge Cases
**Priority:** Medium | **Impact:** Medium | **Effort:** Low

**Current State:** `BookStorage` manages Documents directory files.

**Problem:** May not handle disk full, permissions denied, or iCloud sync conflicts gracefully.

**Recommendation:**
- Check available disk space before large operations
- Handle `NSFileProviderError` for iCloud conflicts
- Add user prompts for permission issues
- Implement file locking for concurrent access

---

## 5. Security Improvements

### 5.1 API Key Storage
**Priority:** Critical | **Impact:** High | **Effort:** Medium

**Current State:** AI provider API keys stored in SwiftData (implicitly UserDefaults-backed).

**Problem:** API keys are sensitive credentials; should use Keychain.

**Recommendation:**
- Migrate API keys to Keychain using `Security` framework
- Add biometric authentication option for key access
- Clear keys from old storage after migration
- Consider per-provider key rotation reminders

```swift
import Security

enum KeychainService {
    static func saveAPIKey(_ key: String, for providerId: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.crux.aiProvider",
            kSecAttrAccount as String: providerId.uuidString,
            kSecValueData as String: key.data(using: .utf8)!
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.saveFailed(status) }
    }
}
```

---

### 5.2 Annotation Encryption
**Priority:** Medium | **Impact:** Medium | **Effort:** High

**Current State:** Annotations stored as plain JSON files.

**Problem:** Sensitive notes visible if device accessed without authorization.

**Recommendation:**
- Implement file-level encryption using `CryptoKit`
- Derive key from user passphrase or device key
- Add "Secure Notes" option for sensitive annotations
- Consider FileVault integration awareness

---

### 5.3 Network Security
**Priority:** Medium | **Impact:** Medium | **Effort:** Medium

**Current State:** Standard URLSession for API calls.

**Problem:** No certificate pinning; potential MITM risk.

**Recommendation:**
- Implement certificate pinning for known API endpoints (Anthropic, OpenAI)
- Validate custom provider URLs before use
- Log and warn on certificate changes
- Enforce TLS 1.3 minimum

---

### 5.4 HTML Export Sanitization
**Priority:** Medium | **Impact:** Low | **Effort:** Low

**Current State:** `AnnotationExportService` generates HTML exports.

**Problem:** User-provided text (notes, tags) may contain malicious HTML/JS.

**Recommendation:**
- Escape all user content in HTML export
- Use safe HTML generation libraries
- Strip JavaScript from exported content
- Add CSP headers to exported HTML files

---

### 5.5 Custom Provider Validation
**Priority:** High | **Impact:** Medium | **Effort:** Low

**Current State:** `CustomProvider` accepts arbitrary API endpoints.

**Problem:** User could be tricked into entering malicious endpoints.

**Recommendation:**
- Validate URL format and HTTPS requirement
- Warn if endpoint differs significantly from known providers
- Add "Test Provider" result verification
- Rate-limit initial requests to unknown endpoints

---

## 6. New Feature Opportunities

### 6.1 Dictionary & Vocabulary
**Priority:** Medium | **Impact:** High | **Effort:** Medium

**Problem:** No inline word definitions; users must switch apps.

**Recommendation:**
- Integrate system dictionary lookup (`UIReferenceLibraryViewController` / `NSTextView` dictionary)
- Add vocabulary list for looked-up words
- Track unfamiliar words per book
- Consider AI-powered contextual definitions

---

### 6.2 Citation Management
**Priority:** Low | **Impact:** Medium | **Effort:** Medium

**Problem:** Academic readers need citation exports.

**Recommendation:**
- Generate BibTeX/RIS entries from book metadata
- Add "Copy Citation" button in book details
- Support multiple citation styles (APA, MLA, Chicago)
- Include highlight citations with page/CFI references

---

### 6.3 Cross-Book Annotation Search
**Priority:** Medium | **Impact:** High | **Effort:** Medium

**Problem:** Highlights can't be searched across entire library.

**Recommendation:**
- Build annotation search index
- Add global search that spans books and annotations
- Support semantic search using AI embeddings
- Show search results grouped by book

---

### 6.4 Reading Time Estimation
**Priority:** Low | **Impact:** Medium | **Effort:** Medium

**Problem:** Users don't know how long a chapter or book will take.

**Recommendation:**
- Calculate based on user's historical reading speed
- Show estimated time remaining for chapter/book
- Consider adaptive estimates based on content difficulty
- Display "X min read" badge in library

---

### 6.5 Collaborative Annotations
**Priority:** Low | **Impact:** Medium | **Effort:** High

**Problem:** No way to share annotations with others.

**Recommendation:**
- Export annotation bundle format (.cruxnotes)
- Import annotations from others
- Merge strategies for overlapping highlights
- Consider cloud sync for shared reading groups

---

### 6.6 OPDS Catalog Support
**Priority:** Low | **Impact:** Medium | **Effort:** Medium

**Problem:** Users must manually import EPUBs; no catalog browsing.

**Recommendation:**
- Add OPDS feed support for browsing catalogs
- One-click download and import
- Save favorite catalogs
- Support authentication for private catalogs

---

### 6.7 Note Templates
**Priority:** Low | **Impact:** Low | **Effort:** Low

**Problem:** Users often write similar types of notes.

**Recommendation:**
- Add note templates (e.g., "Character Analysis", "Theme Notes", "Research Citation")
- Quick-insert template placeholders
- Custom template creation

---

### 6.8 AI Prompt Customization
**Priority:** Medium | **Impact:** Medium | **Effort:** Low

**Problem:** AI prompts are hardcoded; users may prefer different analysis styles.

**Recommendation:**
- Allow custom system prompts per provider
- Provide prompt templates (Academic, Casual, Socratic, etc.)
- Save favorite prompts
- A/B test different prompts

---

## 7. Accessibility

### 7.1 VoiceOver Optimization
**Priority:** High | **Impact:** High | **Effort:** Medium

**Current State:** Standard SwiftUI accessibility; WebView content may lack labels.

**Problem:** Blind users may struggle with reader navigation.

**Recommendation:**
- Add accessibility labels to all interactive elements
- Ensure WebView content is VoiceOver navigable
- Test full reading flow with VoiceOver
- Add rotor actions for chapter navigation

---

### 7.2 Dynamic Type Support
**Priority:** Medium | **Impact:** High | **Effort:** Low

**Current State:** Reader font size controlled via settings slider.

**Problem:** May not respect system Dynamic Type preferences.

**Recommendation:**
- Support `@ScaledMetric` for UI elements
- Option to follow system text size
- Test at all Dynamic Type sizes
- Ensure reader CSS respects user preferences

---

### 7.3 Reduce Motion
**Priority:** Low | **Impact:** Medium | **Effort:** Low

**Problem:** Animations may cause discomfort for some users.

**Recommendation:**
- Respect `accessibilityReduceMotion` preference
- Replace animations with fades when enabled
- Test with Reduce Motion enabled

---

### 7.4 High Contrast Mode
**Priority:** Medium | **Impact:** Medium | **Effort:** Low

**Problem:** Current themes may not provide sufficient contrast.

**Recommendation:**
- Add High Contrast theme option
- Test all color combinations for WCAG AA compliance
- Ensure focus indicators are clearly visible

---

## 8. Testing & Quality Assurance

### 8.1 Unit Test Coverage
**Priority:** High | **Impact:** High | **Effort:** High

**Current State:** Limited test files visible (6 test files).

**Problem:** Insufficient test coverage for complex logic.

**Recommendation:**
- Target 80%+ coverage for Models and Services
- Priority areas:
  - `EPUBParser`: All parsing paths, malformed input handling
  - AI providers: Response parsing, error handling
  - `BookAnnotations`: CRUD operations, JSON encoding
  - `ReadingStatistics`: Calculation accuracy
- Use mock injection for isolated testing

---

### 8.2 UI Testing
**Priority:** Medium | **Impact:** Medium | **Effort:** High

**Current State:** `ReaderPositionUITests.swift` exists.

**Problem:** Limited UI test coverage for critical user flows.

**Recommendation:**
- Test critical flows:
  - Book import → library display
  - Open book → navigate → create highlight
  - AI thread creation and conversation
  - Settings changes persist
- Use accessibility identifiers for reliable element targeting

---

### 8.3 Snapshot Testing
**Priority:** Low | **Impact:** Medium | **Effort:** Medium

**Problem:** UI regressions hard to catch without visual comparison.

**Recommendation:**
- Implement snapshot testing for key views
- Test across themes and Dynamic Type sizes
- Integrate into CI pipeline
- Review snapshots on PR

---

### 8.4 Performance Testing
**Priority:** Medium | **Impact:** Medium | **Effort:** Medium

**Problem:** No automated performance regression detection.

**Recommendation:**
- Add XCTest performance metrics for:
  - EPUB parsing time by file size
  - Library view render time
  - AI response latency
- Set baseline thresholds
- Alert on regression

---

### 8.5 Fuzz Testing
**Priority:** Low | **Impact:** High | **Effort:** Medium

**Problem:** Parser robustness not validated against malformed input.

**Recommendation:**
- Generate malformed EPUB variants
- Fuzz XML/HTML parsing paths
- Test with corrupted ZIP files
- Ensure no crashes or hangs

---

## 9. Documentation

### 9.1 Architecture Documentation
**Priority:** Medium | **Impact:** Medium | **Effort:** Low

**Problem:** No high-level architecture guide for new contributors.

**Recommendation:**
- Create `ARCHITECTURE.md` documenting:
  - Layer diagram (Views → ViewModels → Services → Persistence)
  - Data flow for key features
  - Concurrency model explanation
  - Key design decisions and rationale

---

### 9.2 Contributing Guide
**Priority:** Low | **Impact:** Low | **Effort:** Low

**Problem:** No setup instructions for contributors.

**Recommendation:**
- Create `CONTRIBUTING.md` with:
  - Development environment setup
  - Build instructions
  - Testing requirements
  - PR guidelines
  - Code style conventions

---

### 9.3 API Documentation
**Priority:** Low | **Impact:** Low | **Effort:** Medium

**Problem:** JavaScript modules lack documentation.

**Recommendation:**
- Add JSDoc comments to all exported functions
- Document message protocol between WebView and Swift
- Explain CFI format and usage

---

### 9.4 User Guide
**Priority:** Low | **Impact:** Medium | **Effort:** Medium

**Problem:** No user-facing documentation.

**Recommendation:**
- In-app help section
- Keyboard shortcuts reference
- AI feature explanation
- FAQ for common issues

---

## Summary by Priority

### Critical (Do First)
- 5.1 API Key Storage (Keychain migration)

### High Priority
- 1.1 Library View Virtualization
- 1.2 Cover Image Caching
- 2.1 Reading Position Restoration
- 3.1 ClaudeService Deprecation
- 3.6 Swift Concurrency Audit
- 4.1 EPUB Parsing Resilience
- 4.2 API Error Recovery
- 7.1 VoiceOver Optimization
- 8.1 Unit Test Coverage

### Medium Priority
- 1.3-1.6 Various performance optimizations
- 2.2-2.5 UX enhancements
- 3.2-3.4 Code quality improvements
- 4.3-4.5 Robustness improvements
- 5.2-5.5 Security hardening
- 6.1, 6.3, 6.8 New features
- 7.2, 7.4 Accessibility
- 8.2, 8.4 Testing

### Low Priority
- 2.3, 2.6, 2.7 Minor UX improvements
- 3.5 Error consolidation
- 6.2, 6.4-6.7 Nice-to-have features
- 7.3 Reduce motion
- 8.3, 8.5 Advanced testing
- 9.1-9.4 Documentation

---

## Implementation Roadmap Suggestion

### Phase 1: Foundation (Weeks 1-2)
Focus on critical security and stability:
- Keychain migration for API keys
- Swift concurrency audit
- Error handling improvements
- Unit test coverage for core services

### Phase 2: Performance (Weeks 3-4)
Address user-facing performance issues:
- Library virtualization
- Cover image caching
- EPUB parsing resilience
- Reading position persistence

### Phase 3: Polish (Weeks 5-6)
Enhance user experience:
- Onboarding experience
- Accessibility improvements
- Code quality refactoring
- Additional test coverage

### Phase 4: Features (Weeks 7+)
Add new capabilities:
- Dictionary integration
- Cross-book search
- AI prompt customization
- Advanced export options

---

*This document should be reviewed and updated as improvements are implemented or new issues are discovered.*
