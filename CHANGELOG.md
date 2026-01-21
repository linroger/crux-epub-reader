# Changelog

## [Unreleased] - 2026-01-21

### Added - New Features
- **HighlightsView**: Complete highlights management view with export functionality
  - Visual highlight rows with gradient accents
  - Swipe-to-delete functionality
  - Export to CSV and CSV with Threads formats
  - Export statistics display
  - Navigation to highlight locations in reader

- **BookmarksView**: Enhanced bookmarks management
  - Beautiful gradient-styled bookmark rows
  - Export to CSV and Markdown formats
  - Export statistics and preview
  - Delete functionality with confirmation

- **TableOfContentsView**: Modern table of contents interface
  - Nested chapter support with indentation
  - Search functionality for chapters
  - Current chapter highlighting
  - Smooth navigation to chapters

- **NotesView**: Centralized notes and annotations viewer
  - Filter by book, highlights only, or notes only
  - Export all notes and highlights
  - Clean typography and visual hierarchy

- **SettingsView**: Comprehensive settings panel
  - AI provider configuration (Claude, OpenAI, Custom)
  - API key management
  - Reading time tracking toggle
  - Theme and display preferences

- **KeyboardShortcutsView**: Interactive keyboard shortcuts reference
  - Categorized shortcuts (Navigation, Search, Bookmarks, etc.)
  - Visual key representations
  - Quick access via ⌘/

- **StatisticsView**: Reading statistics dashboard
  - Total reading time across all books
  - Book-specific statistics
  - Session counts and streaks
  - Average session duration

- **BookDetailView**: Detailed book information sheet
  - Cover display and metadata
  - Reading progress visualization
  - Reading statistics integration
  - Quick actions (Continue Reading, Export)

### Enhanced - Keyboard Shortcuts
- **⌘F**: Open search panel
- **⌘T**: Toggle table of contents
- **⌘B**: Toggle bookmarks panel
- **⌘H**: Toggle highlights panel
- **⌘[**: Navigate to previous chapter
- **⌘]**: Navigate to next chapter
- **⌘O**: Open EPUB file
- **⌘/** Show keyboard shortcuts reference
- **⌘⇧S**: Show reading statistics
- **Left/Right Arrow**: Chapter navigation
- **Escape**: Close panels

### Enhanced - Library View
- **Grid/List view modes**: Toggle between grid and list layouts
- **Multiple sort options**: Sort by Title, Author, Date Added, Last Read, Progress
- **Sort direction toggle**: Ascending/descending sort
- **Search functionality**: Filter books by title, author, or subjects
- **Book info button**: Quick access to detailed book information
- **Visual progress indicators**: Progress bars and chapter position
- **Annotation statistics**: Display highlight and thread counts per book
- **Hover effects**: Interactive feedback on book rows and cards

### Enhanced - Reader View
- **ThreadPanel improvements**: Better styling and layout for AI conversations
- **Highlight navigation**: Jump to highlights from highlights view
- **Bookmark navigation**: Jump to bookmarks from bookmarks view
- **Chapter progress tracking**: Visual feedback for current position
- **Search improvements**: Better search UI and results display

### Added - Services and Models
- **AIProviderManager**: Unified AI provider configuration management
- **ClaudeProvider**: Native Claude AI integration
- **OpenAIProvider**: OpenAI API integration
- **CustomProvider**: Support for custom AI endpoints
- **ExportService**: Comprehensive export functionality for highlights and bookmarks
- **ReadingSessionManager**: Reading time tracking and statistics
- **AIProviderConfig**: Persistent AI provider settings
- **AppSettings**: Global app preferences
- **HighlightWithBookInfo**: Export data structure
- **ReadingStatistics**: Statistics data models

### Technical Improvements
- **SwiftUI best practices**: Proper view decomposition and @Observable usage
- **Export architecture**: Flexible export system with multiple formats
- **Settings persistence**: SwiftData integration for settings
- **Type safety**: Proper enum and struct definitions throughout
- **Error handling**: Comprehensive error handling in services
- **Async/await**: Modern Swift concurrency throughout

### Fixed
- Compilation errors in HighlightsView and ReaderView related to CFIRange
- LibraryView type-check timeout error through view extraction
- Compiler warnings across multiple files
- Missing argument labels in export service calls

### Testing Status
✅ Build succeeds without errors or warnings
⏳ UI testing in progress
⏳ Keyboard shortcut testing pending
⏳ Export functionality testing pending
⏳ AI features testing pending

## Architecture Highlights

### View Organization
- Clean separation of concerns
- Reusable components (BookListRow, BookGridCard, etc.)
- Proper state management with @Observable
- View decomposition for better compilation and maintainability

### Data Flow
- SwiftData for persistent storage
- @Query for reactive data updates
- Environment objects for shared state
- Proper model relationships

### Services Layer
- AIProviderManager for unified AI provider access
- ExportService for file export operations
- BookStorage for book management
- ReadingSessionManager for statistics tracking

## Next Steps
1. Complete UI testing with sample EPUB files
2. Test all keyboard shortcuts in various scenarios
3. Test export functionality for highlights and bookmarks
4. Test AI features with configured providers
5. Test reading statistics accuracy
6. Performance optimization if needed
7. Final polish and refinements
