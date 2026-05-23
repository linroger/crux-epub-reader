# Crux EPUB Reader - Improvement Opportunities

**Last Updated:** 2026-05-22
**Codebase Analysis Version:** 1.0
**Status:** Comprehensive Review Complete

This document catalogs potential improvements, optimizations, and enhancements for the Crux EPUB reader application, organized by category and priority.

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
