# Crux EPUB Reader - Comprehensive Feature Plan
**Version:** 1.0
**Date:** 2026-01-21
**Status:** Ready for Implementation

---

## Executive Summary

Crux is currently **70% feature-complete** with a solid foundation. This plan outlines the remaining 30% to achieve a **ship-ready, fully-polished macOS/iOS EPUB reader** with best-in-class AI integration and user experience.

### Current State Assessment
- ✅ **Core strengths:** Robust EPUB parsing, clean SwiftUI architecture, thoughtful annotation system
- ⚠️ **Main gaps:** Settings UI, multi-provider AI, export features, reader customization
- 🎯 **Goal:** Transform from "functional prototype" → "production-ready, delightful app"

---

## Gap Analysis: Current vs. Desired State

### 1. AI Features (Currently: Claude-only)
| Current | Requested | Gap |
|---------|-----------|-----|
| Claude Opus 4.5 hardcoded | Multiple providers (Claude, OpenAI, custom) | ❌ No provider abstraction |
| API key in UserDefaults | Secure, per-provider key management | ❌ No settings UI |
| Fixed base URL | Custom base URLs (e.g., cliproxyapi) | ❌ No provider config model |
| No streaming | Optional streaming responses | ⚠️ Consider adding |
| No rate limiting | Throttling, error recovery | ⚠️ Consider adding |

### 2. Settings & Customization (Currently: None)
| Current | Requested | Gap |
|---------|-----------|-----|
| Stub SettingsView | Full settings menu | ❌ Missing entirely |
| No reader customization | Font, size, spacing, margins | ❌ No customization model |
| No theme options | Light/dark, custom colors | ❌ No theme system |
| No highlight colors | Customizable highlight colors | ❌ Hardcoded styles |

### 3. Notes & Highlights Management (Currently: Basic)
| Current | Requested | Gap |
|---------|-----------|-----|
| View in ThreadPanel only | Dedicated notes view | ❌ No notes browser |
| No editing | Edit/delete highlights | ❌ Immutable after creation |
| No organization | Tagging, categorization | ⚠️ Consider adding |
| No export | CSV export with metadata | ❌ No export system |

### 4. UI/UX Polish (Currently: Functional but basic)
| Current | Requested | Gap |
|---------|-----------|-----|
| Basic toolbar | Rich toolbar with notes, export, etc. | ⚠️ Limited actions |
| No onboarding | First-run experience, tooltips | ⚠️ No help system |
| No error context | Better error messages | ⚠️ Generic errors |
| Platform-specific UI | More macOS-native controls | ⚠️ Some SwiftUI defaults |

### 5. Library Features (Currently: Basic)
| Current | Requested | Gap |
|---------|-----------|-----|
| Search only | Sorting (author, date, progress) | ⚠️ No sort options |
| No collections | Smart folders, tags | ⚠️ Consider adding |
| No metadata editing | Edit title, author, cover | ⚠️ Consider adding |

---

## Feature Categories & Priorities

### Priority 1: Foundation (Must-Have for Ship)
**Goal:** Settings, multi-provider AI, basic export

1. **Settings System** (2-3 days)
   - Settings data model (`AppSettings` SwiftData model)
   - Settings UI (native macOS/iOS preferences)
   - API provider management
   - Reader preferences
   - About/Help section

2. **Multi-Provider AI Architecture** (3-4 days)
   - `AIProvider` protocol abstraction
   - Provider implementations:
     - `ClaudeProvider` (migrate existing)
     - `OpenAIProvider` (GPT-4/o1)
     - `CustomProvider` (user-defined base URL)
   - Provider selection UI
   - Per-provider API key management
   - Error handling & fallback logic

3. **Notes Management View** (2-3 days)
   - Dedicated notes browser window/panel
   - List all highlights across books
   - Show: book, chapter, text, timestamp, annotations
   - Filter/search highlights
   - Navigate to highlight location in reader
   - Edit/delete highlights

4. **CSV Export** (1-2 days)
   - Export highlights + annotations to CSV
   - Include: book, chapter, text, CFI, timestamp, threads
   - Export all or filtered selection
   - macOS file picker integration

### Priority 2: Reader Customization (High Value)
**Goal:** Delightful, personalized reading experience

5. **Reader Appearance Customization** (2-3 days)
   - Font family selector (system fonts)
   - Font size slider (8-32pt)
   - Line height adjustment
   - Paragraph spacing
   - Margin width (left/right/content)
   - Background color picker
   - Text color picker
   - Custom CSS injection into WebView

6. **Highlight Color Customization** (1 day)
   - Color palette for highlights (yellow, pink, blue, green, custom)
   - Per-highlight color assignment
   - CSS style updates
   - Persistence in annotations JSON

7. **Theme System** (1-2 days)
   - Light/dark mode (system-aware)
   - Custom theme presets
   - Sepia, night mode, high contrast
   - Theme preview

### Priority 3: UI/UX Polish (Ship-Ready Quality)
**Goal:** Professional, macOS-native feel

8. **Enhanced Toolbar** (1-2 days)
   - Notes button (open notes view)
   - Export button (CSV export)
   - Settings button (open preferences)
   - Reader appearance popover
   - Better iconography (SF Symbols)

9. **Improved Library UI** (1-2 days)
   - Sorting options (title, author, progress, last read)
   - Grid/list view toggle
   - Cover thumbnail improvements
   - Metadata editing (context menu)
   - Collection/tag support

10. **Error Handling & Feedback** (1 day)
    - Better error alerts with recovery actions
    - Loading states (progress indicators)
    - Success confirmations (toast notifications)
    - API error details (rate limits, auth failures)

11. **Onboarding & Help** (1-2 days)
    - First-run tutorial
    - Tooltips on key features
    - Help menu with shortcuts
    - In-app documentation
    - Sample EPUB for demo

### Priority 4: Advanced Features (Nice-to-Have)
**Goal:** Differentiation, power user features

12. **Bookmarks System** (1-2 days)
    - Create named bookmarks (vs. auto-resume)
    - Bookmark list view
    - Quick navigation
    - Bookmark export

13. **Reading Goals & Analytics** (2-3 days)
    - Time tracking per book
    - Reading streaks
    - Pages/day goals
    - Progress charts
    - Reading history

14. **Advanced Search** (1-2 days)
    - Regex support
    - Search in annotations
    - Search across library
    - Recent searches

15. **Sync & Backup** (3-4 days)
    - iCloud sync (CloudKit)
    - Export/import library
    - Annotation backup
    - Conflict resolution

16. **AI Enhancements** (2-3 days)
    - Streaming responses
    - Model selection per provider
    - Context window management
    - Summarization features
    - Translation support

---

## Architecture Recommendations

### 1. Multi-Provider AI Architecture

```swift
// Protocol-based abstraction
protocol AIProvider: Sendable {
    var id: String { get }
    var name: String { get }
    var supportsStreaming: Bool { get }

    func generateResponse(
        for selection: String,
        context: String?,
        conversationHistory: [ThreadMessage]
    ) async throws -> String

    func streamResponse(
        for selection: String,
        context: String?,
        conversationHistory: [ThreadMessage]
    ) async throws -> AsyncThrowingStream<String, Error>
}

// Provider implementations
actor ClaudeProvider: AIProvider {
    let apiKey: String
    let baseURL: URL
    let model: String
    // Migrate existing ClaudeService logic
}

actor OpenAIProvider: AIProvider {
    let apiKey: String
    let baseURL: URL
    let model: String
    // Implement OpenAI chat completions API
}

actor CustomProvider: AIProvider {
    let apiKey: String
    let baseURL: URL
    let model: String?
    // Generic HTTP client for OpenAI-compatible APIs
}

// Provider registry
@Observable
class AIProviderManager {
    var providers: [AIProviderConfig] = []
    var activeProviderId: String?

    func createProvider(_ config: AIProviderConfig) -> any AIProvider
}

// Configuration model (SwiftData)
@Model
class AIProviderConfig {
    var id: UUID
    var type: ProviderType // .claude, .openai, .custom
    var name: String
    var apiKey: String
    var baseURL: String?
    var model: String?
    var isActive: Bool
}
```

### 2. Settings Architecture

```swift
// Comprehensive settings model
@Model
class AppSettings {
    // AI Providers
    var aiProviders: [AIProviderConfig]
    var defaultProviderId: UUID?

    // Reader Appearance
    var fontFamily: String
    var fontSize: Double
    var lineHeight: Double
    var paragraphSpacing: Double
    var marginWidth: Double
    var backgroundColor: String // hex color
    var textColor: String
    var highlightColors: [String] // color palette

    // UI Preferences
    var theme: AppTheme // .light, .dark, .system
    var libraryViewMode: LibraryViewMode // .list, .grid
    var defaultSortOrder: SortOrder

    // Reading Behavior
    var autoSaveInterval: TimeInterval
    var confirmDelete: Bool
    var trackReadingTime: Bool

    static let `default`: AppSettings
}

// Settings views
SettingsView (macOS: TabView, iOS: NavigationStack)
├── GeneralSettingsView
├── AIProvidersSettingsView
│   ├── ProviderListView
│   └── ProviderEditView
├── ReaderSettingsView
│   ├── FontSettingsSection
│   ├── SpacingSettingsSection
│   └── ColorSettingsSection
└── AboutView
```

### 3. Notes Management Architecture

```swift
// Notes view model
@Observable
class NotesViewModel {
    var books: [StoredBook]
    var highlights: [HighlightWithContext]
    var filterText: String = ""
    var selectedBookId: UUID?
    var sortOrder: NoteSortOrder

    var filteredHighlights: [HighlightWithContext] {
        // Filter by search + book
    }
}

// Rich highlight context
struct HighlightWithContext {
    let highlight: Highlight
    let book: StoredBook
    let chapter: Chapter
    let createdAt: Date
    let threadCount: Int
}

// Notes view
NotesView (macOS: Window, iOS: Sheet)
├── Toolbar (search, export, filter)
├── Sidebar (book list)
└── HighlightList
    └── HighlightRow
        ├── Text preview
        ├── Book/chapter info
        ├── Timestamp
        ├── Thread count badge
        └── Actions (edit, delete, navigate)
```

### 4. Export System

```swift
// Export service
actor ExportService {
    func exportHighlightsCSV(
        highlights: [HighlightWithContext],
        to url: URL
    ) async throws

    func exportBookAnnotations(
        bookId: UUID,
        format: ExportFormat
    ) async throws -> Data

    func exportLibrary(to url: URL) async throws
}

// CSV format
// Book Title, Chapter, Highlight Text, CFI, Created At, Thread Count, Annotations
```

---

## Implementation Phases

### Phase 1: Foundation (Week 1-2)
**Goal:** Settings, multi-provider AI, notes view
- [ ] AppSettings model + UI
- [ ] AIProvider protocol + ClaudeProvider migration
- [ ] OpenAIProvider implementation
- [ ] CustomProvider implementation
- [ ] Provider management UI
- [ ] Notes management view
- [ ] CSV export

**Acceptance Criteria:**
- Can add/edit/delete AI providers
- Can switch between Claude, OpenAI, custom providers
- Can view all highlights in notes view
- Can export highlights to CSV

### Phase 2: Customization (Week 3)
**Goal:** Reader personalization
- [ ] Font customization
- [ ] Spacing/margins controls
- [ ] Color customization (text, bg, highlights)
- [ ] Theme system
- [ ] CSS injection into WebView
- [ ] Settings persistence

**Acceptance Criteria:**
- Can change font family, size, line height
- Can adjust margins and spacing
- Can set custom colors
- Settings persist across sessions

### Phase 3: Polish (Week 4)
**Goal:** Ship-ready UI/UX
- [ ] Enhanced toolbar
- [ ] Improved library (sorting, grid view)
- [ ] Better error handling
- [ ] Onboarding/help
- [ ] Iconography refresh
- [ ] Performance optimization

**Acceptance Criteria:**
- macOS-native feel
- Clear error messages
- First-run tutorial works
- No performance regressions

### Phase 4: Advanced (Week 5+)
**Goal:** Differentiation
- [ ] Bookmarks
- [ ] Reading analytics
- [ ] Advanced search
- [ ] iCloud sync
- [ ] AI streaming
- [ ] Translation

**Acceptance Criteria:**
- (Per feature requirements)

---

## Technical Debt & Improvements

### Code Quality
1. **Refactor large views** - Split 300+ line files
2. **Dependency injection** - Use `@Environment` for services
3. **Error types** - More specific error enums
4. **Logging** - Add OSLog throughout
5. **Accessibility** - VoiceOver, Dynamic Type
6. **Localization** - Prepare for i18n

### Performance
1. **Lazy loading** - Library list virtualization
2. **Image caching** - Cover thumbnails
3. **WebView optimization** - Memory management
4. **Debouncing** - Search input
5. **Background tasks** - EPUB parsing, export

### Testing
1. **Unit test coverage** - Increase from current
2. **UI test coverage** - Critical user flows
3. **Integration tests** - AI provider switching
4. **Performance tests** - Large EPUBs
5. **Accessibility tests** - VoiceOver navigation

---

## UI/UX Enhancements for macOS Native Feel

### macOS-Specific Improvements
1. **Window management**
   - Restorable state (window positions)
   - Full-screen support
   - Split view support
   - Tabbed windows (multi-book)

2. **Menu bar integration**
   - Complete menu bar (File, Edit, View, Navigate, Window, Help)
   - Keyboard shortcuts (⌘K for search, etc.)
   - Services menu integration

3. **Toolbar**
   - Customizable toolbar
   - SF Symbols icons
   - Segmented controls for view modes

4. **Context menus**
   - Rich click menus
   - Quick actions
   - Preview integration

5. **System integration**
   - Drag & drop EPUB files
   - Quick Look plugin
   - Spotlight integration
   - Touch Bar support (if applicable)

### Visual Polish
1. **Animations**
   - Smooth transitions
   - Spring animations for sheets/popovers
   - Loading skeletons

2. **Typography**
   - SF Pro/SF Mono where appropriate
   - Dynamic Type support
   - Proper text hierarchy

3. **Colors**
   - Semantic colors (`.primary`, `.secondary`)
   - Accent color customization
   - Vibrancy/materials

4. **Layout**
   - Proper spacing (8pt grid)
   - Alignment to Apple HIG
   - Responsive to window size

---

## Success Metrics

### Feature Completeness
- [ ] 100% of Priority 1 features implemented
- [ ] 80%+ of Priority 2 features implemented
- [ ] Settings menu fully functional
- [ ] Multi-provider AI working end-to-end
- [ ] Notes view + CSV export functional

### Quality Gates
- [ ] Zero compiler warnings
- [ ] All tests passing
- [ ] No crashes in testing
- [ ] <1s app launch time
- [ ] <2s EPUB load time (typical book)

### User Experience
- [ ] First-run onboarding complete
- [ ] All features have help/tooltips
- [ ] Error messages are clear and actionable
- [ ] Keyboard navigation works throughout
- [ ] VoiceOver support functional

---

## Risks & Mitigation

### Technical Risks
| Risk | Impact | Mitigation |
|------|--------|------------|
| OpenAI API changes | Medium | Abstract with protocol, version API |
| CloudKit complexity | High | Phase 4, optional feature |
| WebView CSS injection conflicts | Medium | Scoped CSS, test thoroughly |
| Performance with large libraries | Medium | Lazy loading, pagination |

### Scope Risks
| Risk | Impact | Mitigation |
|------|--------|------------|
| Feature creep | High | Stick to Priority 1-2, defer others |
| Over-engineering | Medium | Build minimal viable feature first |
| Testing debt | High | Write tests alongside features |

---

## Next Steps

1. **Review & Approve** - Get user confirmation on plan
2. **Create feature_list.json** - Detailed task breakdown
3. **Start Phase 1** - Settings + multi-provider AI
4. **Iterate** - Build → Test → Polish per feature
5. **Ship** - Production release when all P1/P2 complete

---

## Appendix: Detailed Feature Specifications

### A. Multi-Provider AI Provider Types

#### Claude Provider
- **Base URL:** `https://api.anthropic.com/v1/messages`
- **Models:** claude-opus-4-5, claude-sonnet-4-5, claude-haiku-4
- **Auth:** API key in header `x-api-key`
- **Request format:** Messages API
- **Response:** JSON with `content[0].text`

#### OpenAI Provider
- **Base URL:** `https://api.openai.com/v1/chat/completions`
- **Models:** gpt-4o, gpt-4-turbo, o1-preview
- **Auth:** Bearer token
- **Request format:** Chat completions
- **Response:** JSON with `choices[0].message.content`

#### Custom Provider
- **Base URL:** User-defined (e.g., `https://cliproxyapi.com/v1/chat/completions`)
- **Models:** User-specified or auto-detected
- **Auth:** Configurable (API key or Bearer)
- **Request format:** OpenAI-compatible
- **Fallback:** Detect response schema

### B. Settings Menu Structure

```
Settings Window (macOS: NSWindow, iOS: Sheet)
├── Sidebar
│   ├── General
│   ├── AI Providers
│   ├── Reader
│   ├── Library
│   └── About
└── Detail View
    ├── General
    │   ├── Theme (Light/Dark/System)
    │   ├── Language
    │   └── Auto-save interval
    ├── AI Providers
    │   ├── Provider List
    │   │   ├── Claude (default)
    │   │   ├── OpenAI
    │   │   └── Custom providers
    │   ├── Add Provider button
    │   └── Provider Edit Form
    │       ├── Name
    │       ├── Type (Claude/OpenAI/Custom)
    │       ├── API Key (secure field)
    │       ├── Base URL (for custom)
    │       ├── Model (dropdown/text)
    │       └── Test Connection button
    ├── Reader
    │   ├── Font Section
    │   │   ├── Font family picker
    │   │   ├── Font size slider (8-32pt)
    │   │   └── Preview
    │   ├── Spacing Section
    │   │   ├── Line height (1.0-3.0)
    │   │   ├── Paragraph spacing
    │   │   └── Margin width
    │   ├── Colors Section
    │   │   ├── Background color
    │   │   ├── Text color
    │   │   └── Highlight color palette
    │   └── Reset to defaults
    ├── Library
    │   ├── Default view mode (List/Grid)
    │   ├── Default sort order
    │   ├── Confirm delete
    │   └── Show metadata
    └── About
        ├── App version
        ├── Build number
        ├── Credits
        ├── License
        └── Help/Documentation link
```

### C. Notes View Specification

```
Notes View (macOS: Window, iOS: NavigationStack)
├── Toolbar
│   ├── Search field
│   ├── Filter menu (All Books / Current Book)
│   ├── Sort menu (Date / Book / Chapter)
│   ├── Export button
│   └── Close (on iOS)
├── Sidebar (macOS only)
│   └── Book List (with highlight counts)
├── Main Content
│   └── Highlight List (LazyVStack)
│       └── HighlightCard
│           ├── Header
│           │   ├── Book title (if multi-book view)
│           │   ├── Chapter title
│           │   └── Timestamp (relative)
│           ├── Highlighted Text (quoted style)
│           ├── Context snippet (if available)
│           ├── Thread Badge (if threads > 0)
│           ├── Actions Row
│           │   ├── Navigate button (opens reader)
│           │   ├── Edit button
│           │   ├── Delete button
│           │   └── Color picker (highlight color)
│           └── Thread Preview (expandable)
└── Empty State (if no highlights)
    ├── Icon
    ├── "No highlights yet"
    └── "Select text while reading to create highlights"
```

### D. CSV Export Format

```csv
Book Title,Author,Chapter,Highlight Text,CFI Range,Created At,Thread Count,Annotations
"The Republic","Plato","Book II","Justice is the interest of the stronger","epubcfi(/6/4[ch02]!/4/2/1:0,/4/2/1:42)",2026-01-15 14:32:10,1,"Initial margin note: Thrasymachus' position..."
```

**Columns:**
- Book Title
- Author
- Chapter
- Highlight Text
- CFI Range (for re-import)
- Created At (ISO 8601)
- Thread Count
- Annotations (concatenated thread messages)

---

## Conclusion

This plan provides a **clear roadmap** from "70% complete" to "ship-ready" with:
- ✅ Detailed gap analysis
- ✅ Prioritized features (P1-P4)
- ✅ Architecture recommendations
- ✅ Implementation phases (4 weeks)
- ✅ Quality gates & success metrics

**Estimated timeline:** 4-5 weeks for Priority 1-2 features (ship-ready state)

**Next action:** Generate `feature_list.json` and begin Phase 1 implementation.
