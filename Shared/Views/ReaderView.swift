import SwiftUI
import SwiftData
import WebKit

struct ReaderView: View {
    let book: Book
    let bookId: UUID

    @Environment(AppState.self) private var appState
    @Environment(AIProviderManager.self) private var providerManager
    @Environment(\.modelContext) private var modelContext
    @Query private var storedBooks: [StoredBook]
    @Query private var settings: [AppSettings]

    @State private var currentChapterIndex = 0
    @State private var threadState = ThreadPanelState()
    @State private var annotations = BookAnnotations(bookId: UUID())
    @State private var loadingHighlightId: UUID? = nil
    @State private var pendingSelection: SelectionData? = nil
    @State private var pendingHighlightId: UUID? = nil
    @State private var searchState = SearchState()
    /// Cached plain-text index for the active book. Built once when the
    /// book opens, then reused for every keystroke in book-wide search
    /// so we don't re-strip HTML on each query.
    @State private var bookSearchIndex = BookSearchIndex()
    @State private var webViewCoordinator: WebViewCoordinator? = nil
    @State private var pendingFragment: String? = nil
    @State private var previousFilePath: String? = nil
    @State private var isNavigatingProgrammatically = false
    @State private var currentScrollPosition: Double = 0
    @State private var pendingScrollPosition: Double? = nil
    /// Most recent CFI reported by the viewport tracker. Persisted into
    /// `StoredBook.lastReadingCFI` on every progress save so the reader
    /// can restore to the exact element on reopen.
    @State private var currentReadingCFI: String = ""
    /// CFI queued for restoration after a chapter loads. Empty means
    /// "fall back to `pendingScrollPosition`".
    @State private var pendingReadingCFI: String = ""
    /// Stack of (chapterIndex, scrollPosition) tuples to support a
    /// "Back" action when the user follows an internal EPUB hyperlink
    /// (footnote, glossary reference, etc.). Capped to a sensible depth
    /// so deeply nested hops don't grow indefinitely.
    @State private var navigationHistory: [(chapterIndex: Int, scrollPosition: Double)] = []
    private static let navigationHistoryLimit = 32
    @State private var showTableOfContents = false
    @State private var showBookmarks = false
    @State private var showHighlights = false
    @State private var showAddBookmark = false
    @State private var showExportAnnotations = false
    @State private var bookmarkNote = ""
    @State private var sessionManager: ReadingSessionManager?

    /// Native macOS sidebar that surfaces the live AI thread. Opens
    /// automatically when the user kicks off a chapter-scope AI action
    /// from the toolbar; can be toggled freely with ⌥⌘A.
    @State private var showAIInspector = false
    /// Free-form chapter-scope question routed into ThreadPanelState.
    @State private var chapterQuestion = ""
    /// Backs the sheet for typing a free-form chapter-scope question.
    @State private var showChapterAskSheet = false

    /// Passage routed into the AI Inspector for annotation. On macOS the
    /// inspector is only used for chapter-scope analyses and viewing
    /// highlights, so this stays `nil` there (passage annotation flows
    /// through the right-click menu + margin notes). On iOS — where the
    /// reader margins collapse on narrow screens and there's no
    /// right-click — the floating selection bar sets this so the inspector
    /// becomes the full-width surface for annotating the selected passage.
    @State private var inspectorSelection: SelectionData? = nil

    private var isTrackingEnabled: Bool {
        settings.first?.trackReadingTime ?? true
    }

    private var storedBook: StoredBook? {
        storedBooks.first { $0.id == bookId }
    }

    var currentChapter: Chapter? {
        guard currentChapterIndex < book.chapters.count else { return nil }
        return book.chapters[currentChapterIndex]
    }

    private var bookProgress: Double {
        guard book.chapters.count > 0 else { return 0 }
        // Include within-chapter progress for smoother overall progress
        let chapterProgress = Double(currentChapterIndex) / Double(book.chapters.count)
        let withinChapterProgress = currentScrollPosition / Double(book.chapters.count)
        return chapterProgress + withinChapterProgress
    }

    private var chapterPercentage: Int {
        Int(currentScrollPosition * 100)
    }

    private var overallPercentage: Int {
        Int(bookProgress * 100)
    }

    var currentChapterHighlights: [Highlight] {
        guard let chapter = currentChapter else { return [] }
        let currentFilePath = chapter.filePath

        // Find all chapters that share this file path (including parent/subchapters)
        let chaptersForFile = book.chapters.filter { $0.filePath == currentFilePath }
        let chapterIds = Set(chaptersForFile.map { $0.id })

        return annotations.highlights.filter { chapterIds.contains($0.chapterId) }
    }

    /// Highlights to display in WebView (includes pending uncommitted selection)
    var displayHighlights: [Highlight] {
        var highlights = currentChapterHighlights

        // Add pending selection as a temporary highlight.
        //
        // macOS only: after `mouseup` the native selection is cleared, so
        // painting an accent span over the passage is the user's only
        // visual cue that the selection was captured. On iOS the native
        // selection (with its drag handles) stays live and `selectionchange`
        // fires continuously while dragging — injecting a highlight span
        // mid-drag mutates the DOM under the selection and fights the
        // system UI. There the floating selection bar is the affordance, so
        // we leave the live selection untouched until the user commits.
        #if os(macOS)
        if let pending = pendingSelection, let pendingId = pendingHighlightId, let chapter = currentChapter {
            let pendingHighlight = Highlight(
                id: pendingId,
                chapterId: chapter.id,
                selectedText: pending.text,
                surroundingContext: pending.context,
                cfiRange: pending.cfiRange
            )
            highlights.append(pendingHighlight)
        }
        #endif

        return highlights
    }

    /// Convert markdown text to HTML for margin-note rendering.
    private func markdownToHTML(_ text: String) -> String {
        var result = text

        // Escape HTML entities first
        result = result
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        // Bold: **text** or __text__
        if let regex = try? NSRegularExpression(pattern: #"\*\*(.+?)\*\*|__(.+?)__"#) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "<strong>$1$2</strong>")
        }

        // Italic: *text* or _text_ (but not inside words for underscore)
        if let regex = try? NSRegularExpression(pattern: #"\*([^*]+?)\*|(?<!\w)_([^_]+?)_(?!\w)"#) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "<em>$1$2</em>")
        }

        // Inline code: `code`
        if let regex = try? NSRegularExpression(pattern: #"`([^`]+?)`"#) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "<code>$1</code>")
        }

        // Line breaks
        result = result.replacingOccurrences(of: "\n", with: "<br>")

        return result
    }

    /// Build margin note data from current highlights for passing to the
    /// WebView. macOS only — the side gutters collapse on iOS's narrow
    /// screens (CSS media query), where passage annotation flows through the
    /// inspector sheet instead. The notes anchor visually beside the
    /// highlighted passage; the gutter is sized in CSS to fit them without
    /// overlapping the prose (see `ReaderResources.generateCustomCSS`).
    var currentMarginNotes: [MarginNoteData] {
        #if os(macOS)
        var notes: [MarginNoteData] = []

        // Pending (uncommitted) selection — carries the Highlight / Annotate
        // buttons for the captured passage.
        if let pending = pendingSelection, let pendingId = pendingHighlightId {
            let errorMsg = (loadingHighlightId == pendingId && threadState.error != nil)
                ? threadState.error?.localizedDescription
                : nil
            notes.append(MarginNoteData(
                highlightId: pendingId.uuidString,
                previewText: String(pending.text.prefix(100)),
                isCommitted: false,
                hasThread: false,
                threadContent: nil,
                isLoading: false,
                errorMessage: errorMsg
            ))
        }

        // Committed highlights for the current chapter.
        for highlight in currentChapterHighlights {
            let thread = highlight.threads.first
            let isLoading = loadingHighlightId == highlight.id
            let errorMsg = (loadingHighlightId == highlight.id && threadState.error != nil)
                ? threadState.error?.localizedDescription
                : nil

            var threadContent: String? = nil
            if let thread = thread, !thread.messages.isEmpty {
                threadContent = thread.messages.map { msg in
                    let roleClass = msg.role == .user ? "user" : "assistant"
                    let htmlContent = markdownToHTML(msg.content)
                    return "<div class=\"thread-message \(roleClass)\">\(htmlContent)</div>"
                }.joined()
            }

            notes.append(MarginNoteData(
                highlightId: highlight.id.uuidString,
                previewText: String(highlight.selectedText.prefix(100)),
                isCommitted: true,
                hasThread: thread != nil,
                threadContent: threadContent,
                isLoading: isLoading,
                errorMessage: errorMsg
            ))
        }

        return notes
        #else
        return []
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar at top when active
            if searchState.isSearchActive {
                InlineSearchBar(
                    searchState: searchState,
                    onSearch: { query in
                        if searchState.scope == .chapter {
                            performInChapterSearch(query)
                        } else {
                            performBookSearch(query)
                        }
                    },
                    onNext: { navigateSearchResult(forward: true) },
                    onPrevious: { navigateSearchResult(forward: false) },
                    onClose: { closeSearch() },
                    onScopeChange: { scope in
                        handleScopeChange(scope)
                    },
                    searchHistory: appState.searchHistoryService.getRecentSearches(forBookId: bookId),
                    onSelectHistory: { query in
                        searchState.query = query
                        if searchState.scope == .chapter {
                            performInChapterSearch(query)
                        } else {
                            performBookSearch(query)
                        }
                    },
                    onDeleteHistory: { item in
                        appState.searchHistoryService.deleteSearch(item)
                    },
                    onClearHistory: {
                        appState.searchHistoryService.clearHistory(forBookId: bookId)
                    }
                )

                // Book search results dropdown
                if searchState.scope == .book && !searchState.bookMatches.isEmpty {
                    BookSearchResultsView(
                        matches: searchState.bookMatches,
                        onSelectMatch: { match in
                            navigateToChapter(match.chapterIndex)
                            // Switch to chapter scope to highlight in context
                            searchState.scope = .chapter
                            // Search will be re-run by onChange handler
                        }
                    )
                    .frame(maxHeight: 200)
                }
            }

            if let chapter = currentChapter {
                EPUBWebView(
                    chapter: chapter,
                    highlights: displayHighlights,
                    marginNotes: currentMarginNotes,
                    onTextSelected: { selectionData in
                        handleTextSelection(selectionData)
                    },
                    onHighlightTapped: { _ in
                        // Handled by margin notes in WebView
                    },
                    onMarginNoteAction: { action in
                        handleMarginNoteAction(action)
                    },
                    onSearchResults: { matchCount, currentIndex in
                        searchState.inChapterMatchCount = matchCount
                        searchState.inChapterCurrentIndex = max(0, currentIndex)

                        // Save to search history if we got results
                        if matchCount > 0 && !searchState.query.isEmpty {
                            appState.searchHistoryService.addSearch(
                                query: searchState.query,
                                bookId: bookId,
                                resultCount: matchCount
                            )
                        }
                    },
                    onContentLoaded: {
                        scrollToFragmentOrTop()
                        initializeViewportTracking()
                        restoreScrollPositionIfNeeded()
                    },
                    onVisibleSection: { chapterIndex, scrollPosition, cfi in
                        handleVisibleSectionChange(chapterIndex, scrollPosition: scrollPosition, cfi: cfi)
                    },
                    onContextMenuAction: { selectionData, action in
                        handleContextMenuAction(selectionData, action: action)
                    },
                    onInternalLink: { path, fragment in
                        followInternalLink(path: path, fragment: fragment)
                    }
                )
                // Key the WebView on the rendered file, NOT the chapter index.
                // Many EPUBs map several TOC entries (file.xhtml#sec1,
                // file.xhtml#sec2, …) to a single XHTML file. While you scroll,
                // the viewport tracker advances `currentChapterIndex` as you
                // cross those in-file section boundaries — so keying on the
                // index tore down and rebuilt the entire WebView mid-scroll,
                // which flashed white and dumped you back at the top. Keying on
                // the file path keeps the live WebView (and your scroll
                // position) for same-file section changes; only an actual file
                // change rebuilds it and loads new content.
                .id(currentChapter?.filePath ?? "crux-no-content")
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .trailing)),
                    removal: .opacity.combined(with: .move(edge: .leading))
                ))
                #if os(iOS)
                // Touch platforms have no right-click menu, so surface the
                // passage actions in a floating bar over the reader.
                .overlay(alignment: .bottom) {
                    iOSSelectionToolbar
                        .padding(.bottom, 12)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8),
                                   value: pendingSelection != nil)
                }
                #endif
            } else {
                Text("No content available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Navigation bar
            HStack(spacing: 16) {
                Button {
                    navigateToChapter(currentChapterIndex - 1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(currentChapterIndex == 0)
                .accessibilityIdentifier("previousChapter")

                Spacer()

                // Position indicator
                VStack(spacing: 2) {
                    if let chapter = currentChapter {
                        Text(chapter.title)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .accessibilityIdentifier("chapterTitle")
                    }
                    HStack(spacing: 8) {
                        Text("Ch \(currentChapterIndex + 1)/\(book.chapters.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("chapterPosition")
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("\(chapterPercentage)% in chapter")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("chapterPercentage")
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("\(overallPercentage)% overall")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("overallPercentage")
                    }
                }
                .accessibilityIdentifier("positionIndicator")

                Spacer()

                Button {
                    navigateToChapter(currentChapterIndex + 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(currentChapterIndex >= book.chapters.count - 1)
                .accessibilityIdentifier("nextChapter")
            }
            .padding()
            .background(.bar)
            .accessibilityIdentifier("navigationBar")

            // Progress scrubber — tap or drag to jump to any chapter.
            // Hovering reveals the chapter that would be navigated to.
            ProgressScrubber(
                chapters: book.chapters,
                currentChapterIndex: currentChapterIndex,
                currentScrollPosition: currentScrollPosition,
                onSeek: { targetIndex in
                    navigateToChapter(targetIndex)
                }
            )
        }
        .navigationTitle(book.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { readerToolbarIOS }
        #endif
        #if os(macOS)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                // Back through internal-link history. Hidden until the
                // user has actually followed a footnote/glossary link.
                if !navigationHistory.isEmpty {
                    Button {
                        popNavigationHistory()
                    } label: {
                        Label("Back", systemImage: "chevron.backward.circle")
                    }
                    .help("Return to before the last internal link")
                    .accessibilityIdentifier("readerBack")
                }

                // Chapters — most-used navigation affordance, surfaced first.
                Button {
                    showTableOfContents = true
                } label: {
                    Label("Chapters", systemImage: "list.bullet")
                }
                .help("Table of contents (⌘L)")
                .keyboardShortcut("l", modifiers: .command)

                // Bookmarks — a single grouped menu reduces toolbar noise
                // while keeping both "view" and "add" within one tap.
                Menu {
                    bookmarksMenuContent
                } label: {
                    Label("Bookmarks", systemImage: annotations.bookmarks.isEmpty ? "bookmark" : "bookmark.fill")
                }
                .help("Bookmarks (⌘B to add)")

                // Highlights — direct button, always relevant when reading.
                Button {
                    showHighlights = true
                } label: {
                    Label("Highlights", systemImage: "highlighter")
                }
                .help("View highlights in this book")

                // Ask AI — chapter-scope quick actions. The presets fan out
                // into the AI inspector, where streaming + cancel + the
                // shared follow-up composer live. A free-form prompt is
                // available via the sheet for anything off-preset.
                Menu {
                    askAIMenuContent
                } label: {
                    Label("Ask AI", systemImage: "sparkles")
                }
                .help("Chapter-level AI insights (⌥⌘A)")
                .disabled(currentChapter == nil)

                // Export — moved into an overflow menu since it's used less
                // often than the bookmark/highlight flows.
                Menu {
                    Button {
                        showExportAnnotations = true
                    } label: {
                        Label("Export Annotations…", systemImage: "square.and.arrow.up")
                    }
                    .disabled(annotations.highlights.isEmpty && annotations.bookmarks.isEmpty)

                    Divider()

                    Button {
                        showAIInspector.toggle()
                    } label: {
                        Label(showAIInspector ? "Hide AI Inspector" : "Show AI Inspector",
                              systemImage: "sidebar.right")
                    }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .help("More actions")
            }
        }
        #endif
        .inspector(isPresented: $showAIInspector) {
            ThreadPanel(
                pendingSelection: inspectorSelection,
                book: book,
                chapter: currentChapter,
                state: threadState,
                annotations: $annotations,
                onDismiss: {
                    showAIInspector = false
                    inspectorSelection = nil
                }
            )
            .inspectorColumnWidth(min: 320, ideal: 380, max: 520)
        }
        .sheet(isPresented: $showChapterAskSheet) {
            ChapterAskSheet(
                chapterTitle: currentChapter?.title ?? "Chapter",
                question: $chapterQuestion,
                onCancel: { showChapterAskSheet = false },
                onSubmit: {
                    let q = chapterQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
                    showChapterAskSheet = false
                    guard !q.isEmpty else { return }
                    runChapterAIAction(label: q, prompt: q)
                }
            )
            #if os(iOS)
            .presentationDetents([.medium, .large])
            #endif
        }
        .sheet(isPresented: $showTableOfContents) {
            NavigationStack {
                TableOfContentsView(
                    chapters: book.chapters,
                    currentChapterIndex: currentChapterIndex,
                    onSelectChapter: { index in
                        showTableOfContents = false
                        navigateToChapter(index)
                    }
                )
                .navigationTitle("Table of Contents")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            showTableOfContents = false
                        }
                    }
                }
            }
            #if os(macOS)
            .frame(minWidth: 400, minHeight: 500)
            #endif
        }
        .sheet(isPresented: $showBookmarks) {
            NavigationStack {
                BookmarksView(
                    bookmarks: annotations.bookmarks,
                    bookTitle: book.title,
                    bookAuthor: book.author ?? "Unknown Author",
                    onSelectBookmark: { bookmark in
                        showBookmarks = false
                        navigateToBookmark(bookmark)
                    },
                    onDeleteBookmark: { bookmarkId in
                        deleteBookmark(id: bookmarkId)
                    }
                )
                .navigationTitle("Bookmarks")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            showBookmarks = false
                        }
                    }
                }
            }
            #if os(macOS)
            .frame(minWidth: 400, minHeight: 500)
            #endif
        }
        .sheet(isPresented: $showHighlights) {
            NavigationStack {
                HighlightsView(
                    bookId: bookId,
                    highlights: annotations.highlights,
                    bookTitle: book.title,
                    bookAuthor: book.author ?? "Unknown Author",
                    onSelectHighlight: { highlight in
                        showHighlights = false
                        navigateToHighlight(highlight)
                    },
                    onDeleteHighlight: { highlightId in
                        deleteHighlight(id: highlightId)
                    }
                )
                .navigationTitle("Highlights")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            showHighlights = false
                        }
                    }
                }
            }
            #if os(macOS)
            .frame(minWidth: 400, minHeight: 500)
            #endif
        }
        .sheet(isPresented: $showExportAnnotations) {
            AnnotationExportView(
                bookTitle: book.title,
                bookAuthor: book.author,
                annotations: annotations
            )
        }
        .alert("Add Bookmark", isPresented: $showAddBookmark) {
            TextField("Note (optional)", text: $bookmarkNote)
            Button("Cancel", role: .cancel) {
                bookmarkNote = ""
            }
            Button("Add") {
                addBookmark()
            }
        } message: {
            if let chapter = currentChapter {
                Text("Save bookmark for \"\(chapter.title)\"")
            }
        }
        .task {
            await loadState()
            // Warm the per-book plain-text search index off the main
            // thread so the first ⌘F in book scope returns instantly
            // instead of paying the strip-HTML cost mid-keystroke. We
            // only warm books with more than a handful of chapters —
            // tiny books were already fast enough.
            await warmBookSearchIndex()
        }
        // Donate the currently-open book as an NSUserActivity so macOS
        // surfaces it in Handoff, Recents, and downstream Spotlight
        // ranking. The activity carries the book's UUID in `userInfo`,
        // which CruxApp's `.onContinueUserActivity` handler routes back
        // through `AppState.selectedBookId`. Setting both `isEligibleFor*`
        // flags lets Spotlight learn from how often the user re-engages.
        .userActivity(SpotlightIndexer.activityType, isActive: true) { activity in
            activity.title = book.title
            activity.userInfo = [
                SpotlightIndexer.userInfoBookIDKey: bookId.uuidString
            ]
            activity.isEligibleForSearch = true
            activity.isEligibleForHandoff = true
            #if os(iOS)
            // iOS-only: lets Siri/Suggestions surface the activity as
            // a predicted next action. macOS handles this through
            // Spotlight ranking instead.
            activity.isEligibleForPrediction = true
            #endif
            // Tag the activity so Spotlight ranks recurring reads
            // higher and re-displays them in Suggested.
            activity.persistentIdentifier = bookId.uuidString
        }
        .onAppear {
            // Initialize AI provider for thread state
            threadState.setProviderManager(providerManager)
            // Push the user's current prompt selection so future calls
            // pick it up. Done in onAppear (not onChange) because the user
            // can edit prompts in Settings, then come back here.
            threadState.resolvedSystemPrompt = resolvePromptFromSettings()

            // Initialize and start reading session tracking
            sessionManager = ReadingSessionManager(
                modelContext: modelContext,
                isTrackingEnabled: isTrackingEnabled
            )
            if let bookId = storedBooks.first(where: { $0.id == book.id })?.id {
                sessionManager?.startSession(bookId: bookId, chapterIndex: currentChapterIndex)
            }

            // Listen for app lifecycle events to pause/resume tracking
            #if os(macOS)
            NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                sessionManager?.pauseSession(chapterIndex: currentChapterIndex)
            }

            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                sessionManager?.resumeSession(chapterIndex: currentChapterIndex)
            }
            #endif
        }
        .onDisappear {
            // End reading session when view disappears
            sessionManager?.endCurrentSession(chapterIndex: currentChapterIndex)

            // Remove lifecycle observers
            #if os(macOS)
            NotificationCenter.default.removeObserver(
                self,
                name: NSApplication.didResignActiveNotification,
                object: nil
            )
            NotificationCenter.default.removeObserver(
                self,
                name: NSApplication.didBecomeActiveNotification,
                object: nil
            )
            #endif
        }
        .onChange(of: currentChapterIndex) { _, newChapter in
            // Update reading session progress
            sessionManager?.updateProgress(chapterIndex: newChapter)

            // Scroll to position after chapter change
            // Use delay to let content load/update first
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                scrollToFragmentOrTop()
            }

            // Re-run search in new chapter if search is active
            if searchState.isSearchActive && searchState.scope == .chapter && !searchState.query.isEmpty {
                // Small delay to let the new chapter content load
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    performInChapterSearch(searchState.query)
                }
            }
        }
        #if os(macOS)
        .onKeyPress(.leftArrow) {
            if currentChapterIndex > 0 {
                navigateToChapter(currentChapterIndex - 1)
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.rightArrow) {
            if currentChapterIndex < book.chapters.count - 1 {
                navigateToChapter(currentChapterIndex + 1)
                return .handled
            }
            return .ignored
        }
        .onKeyPress(characters: .init(charactersIn: "fF")) { press in
            if press.modifiers.contains(.command) {
                searchState.isSearchActive = true
                return .handled
            }
            return .ignored
        }
        .onKeyPress(characters: .init(charactersIn: "tT")) { press in
            if press.modifiers.contains(.command) {
                showTableOfContents.toggle()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(characters: .init(charactersIn: "bB")) { press in
            if press.modifiers.contains(.command) {
                showBookmarks.toggle()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(characters: .init(charactersIn: "hH")) { press in
            if press.modifiers.contains(.command) {
                showHighlights.toggle()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(characters: .init(charactersIn: "dD")) { press in
            // ⌃⌘D — macOS standard "Look Up in Dictionary" gesture.
            // Falls through to system handling if no selection exists.
            if press.modifiers.contains(.control) && press.modifiers.contains(.command),
               let selection = pendingSelection {
                _ = DictionaryLookup.lookUp(selection.text)
                return .handled
            }
            return .ignored
        }
        .onKeyPress(characters: .init(charactersIn: "[")) { press in
            if press.modifiers.contains(.command) {
                // Previous chapter
                if currentChapterIndex > 0 {
                    navigateToChapter(currentChapterIndex - 1)
                }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(characters: .init(charactersIn: "]")) { press in
            if press.modifiers.contains(.command) {
                // Next chapter
                if currentChapterIndex < book.chapters.count - 1 {
                    navigateToChapter(currentChapterIndex + 1)
                }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.escape) {
            if pendingSelection != nil {
                clearPendingSelection()
                evaluateJavaScript("window.getSelection().removeAllRanges();")
                return .handled
            }
            return .ignored
        }
        #endif
    }

    // MARK: - Reader Toolbar Content (shared)

    /// Bookmark add/view actions, shared by the macOS toolbar menu and the
    /// iOS overflow menu so both stay in lockstep.
    @ViewBuilder
    private var bookmarksMenuContent: some View {
        Button {
            showAddBookmark = true
        } label: {
            Label("Add Bookmark Here", systemImage: "bookmark.circle")
        }
        .keyboardShortcut("b", modifiers: .command)

        Button {
            showBookmarks = true
        } label: {
            Label("View All Bookmarks", systemImage: "bookmark.fill")
        }

        if !annotations.bookmarks.isEmpty {
            Divider()
            Text("\(annotations.bookmarks.count) bookmark\(annotations.bookmarks.count == 1 ? "" : "s")")
        }
    }

    /// Chapter-scope AI preset actions, shared by both platforms' toolbars.
    @ViewBuilder
    private var askAIMenuContent: some View {
        Button {
            runChapterAIAction(label: "Summarize Chapter",
                               prompt: "Write a concise but substantive summary of the current chapter. Capture the central arguments or narrative beats, key turning points, and any concepts the reader needs to carry into later chapters. Keep it tight — under ~250 words — but don't sacrifice insight for brevity.")
        } label: {
            Label("Summarize Chapter", systemImage: "doc.text.magnifyingglass")
        }
        .keyboardShortcut("u", modifiers: [.command, .option])

        Button {
            runChapterAIAction(label: "Key Themes & Motifs",
                               prompt: "Identify the chapter's principal themes, motifs, and any recurring images or symbols. For each, briefly cite where in the chapter it appears and why it matters to the wider argument or narrative.")
        } label: {
            Label("Key Themes & Motifs", systemImage: "sparkle.magnifyingglass")
        }

        Button {
            runChapterAIAction(label: "Difficult Passages",
                               prompt: "Pinpoint two to four passages a careful reader is most likely to find difficult or ambiguous, and for each explain what makes it hard and how to read it. Prefer concrete textual reasons (vocabulary, syntax, rhetorical structure, implied context) over generic remarks.")
        } label: {
            Label("Explain Difficult Passages", systemImage: "questionmark.text.page")
        }

        Button {
            runChapterAIAction(label: "Discussion Questions",
                               prompt: "Propose five thought-provoking discussion questions grounded in this chapter. The questions should require interpretation, not recall — each one should be answerable in several ways depending on the reader's stance.")
        } label: {
            Label("Discussion Questions", systemImage: "bubble.left.and.text.bubble.right")
        }

        Divider()

        Button {
            chapterQuestion = ""
            showChapterAskSheet = true
        } label: {
            Label("Ask About This Chapter…", systemImage: "text.bubble")
        }
        .keyboardShortcut("a", modifiers: [.command, .option])
    }

    #if os(iOS)
    /// Consolidated reader toolbar for iPhone/iPad. The nav bar can't hold
    /// the half-dozen controls the macOS window toolbar spreads out, so
    /// only Chapters and Ask AI stay direct; bookmarks, highlights, search,
    /// export, and the AI inspector fold into one overflow menu.
    @ToolbarContentBuilder
    private var readerToolbarIOS: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showTableOfContents = true
            } label: {
                Label("Chapters", systemImage: "list.bullet")
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                askAIMenuContent
            } label: {
                Label("Ask AI", systemImage: "sparkles")
            }
            .disabled(currentChapter == nil)
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    searchState.isSearchActive = true
                } label: {
                    Label("Search in Book", systemImage: "magnifyingglass")
                }

                Section {
                    bookmarksMenuContent
                }

                Button {
                    showHighlights = true
                } label: {
                    Label("Highlights", systemImage: "highlighter")
                }

                Section {
                    Button {
                        showAIInspector.toggle()
                    } label: {
                        Label(showAIInspector ? "Hide AI Inspector" : "Show AI Inspector",
                              systemImage: "sidebar.right")
                    }

                    Button {
                        showExportAnnotations = true
                    } label: {
                        Label("Export Annotations…", systemImage: "square.and.arrow.up")
                    }
                    .disabled(annotations.highlights.isEmpty && annotations.bookmarks.isEmpty)
                }

                if !navigationHistory.isEmpty {
                    Section {
                        Button {
                            popNavigationHistory()
                        } label: {
                            Label("Back (undo last link)", systemImage: "chevron.backward.circle")
                        }
                    }
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }
    #endif

    #if os(iOS)
    // MARK: - iOS Selection Action Bar

    /// Floating capsule of passage actions shown over the reader whenever
    /// the user has an active text selection. This is the touch-platform
    /// stand-in for the macOS right-click selection menu: highlight the
    /// passage, hand it to the AI Inspector for annotation, or dismiss.
    @ViewBuilder
    private var iOSSelectionToolbar: some View {
        if let selection = pendingSelection {
            HStack(spacing: 2) {
                selectionBarButton("Highlight", systemImage: "highlighter") {
                    handleContextMenuAction(selection, action: .highlight)
                    finishIOSSelection()
                }

                selectionBarDivider

                selectionBarButton("Annotate", systemImage: "sparkles") {
                    // Route the passage into the inspector, which on iPhone
                    // presents as a sheet — a full-width surface for the
                    // streaming annotation and follow-up questions. Margin
                    // notes collapse on narrow screens, so the inspector is
                    // the place AI output is actually readable.
                    inspectorSelection = selection
                    showAIInspector = true
                    finishIOSSelection()
                }

                selectionBarDivider

                Button {
                    finishIOSSelection()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss selection actions")
            }
            .padding(.horizontal, 6)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 4)
            .padding(.horizontal, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var selectionBarDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 24)
    }

    private func selectionBarButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .frame(minWidth: 60, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    /// Clears the pending selection and drops the live web selection so the
    /// floating bar dismisses cleanly after an action runs.
    private func finishIOSSelection() {
        clearPendingSelection()
        evaluateJavaScript("window.getSelection().removeAllRanges();")
    }
    #endif

    private func handleTextSelection(_ selectionData: SelectionData) {
        guard currentChapter != nil else { return }

        // Check if this highlight already exists (committed)
        if annotations.highlights.contains(where: { $0.selectedText == selectionData.text && $0.cfiRange == selectionData.cfiRange }) {
            return
        }

        // Store as pending (don't save yet - wait for user to click Highlight or Annotate)
        pendingSelection = selectionData
        pendingHighlightId = UUID()
    }

    private func clearPendingSelection() {
        pendingSelection = nil
        pendingHighlightId = nil
    }
    
    private func handleContextMenuAction(_ selectionData: SelectionData, action: SelectionContextAction) {
        guard currentChapter != nil else { return }
        
        switch action {
        case .highlight:
            // Set up as pending selection and commit immediately
            pendingSelection = selectionData
            pendingHighlightId = UUID()
            if let _ = commitPendingHighlight() {
                Task {
                    try? await BookStorage.shared.saveAnnotations(annotations)
                }
            }
            
        case .annotateWithAI:
            // Set up pending selection and trigger AI annotation
            pendingSelection = selectionData
            pendingHighlightId = UUID()
            
            Task {
                await startAIAnnotation(for: selectionData, customPrompt: nil)
            }
            
        case .annotateWithCustomPrompt(let customPrompt):
            // Set up pending selection and trigger AI annotation with custom prompt
            pendingSelection = selectionData
            pendingHighlightId = UUID()
            
            Task {
                await startAIAnnotation(for: selectionData, customPrompt: customPrompt)
            }
            
        case .copy:
            // Copy is handled in the coordinator, nothing more needed here
            break
        }
    }
    
    /// Reads the user's prompt selection from AppSettings and returns the
    /// resolved system-prompt string for AI requests. Returns nil when
    /// the user is on the built-in scholarly default (so the provider
    /// uses its bundled prompt instead of duplicating it via SwiftData).
    private func resolvePromptFromSettings() -> String? {
        guard let appSettings = settings.first else { return nil }
        let preset = AIPromptPreset(rawValue: appSettings.activePromptPresetId) ?? .scholarly
        switch preset {
        case .scholarly:
            // Built-in default — let the provider use its own copy.
            return nil
        case .custom:
            let trimmed = appSettings.customSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case .casual, .socratic, .minimalist, .technical:
            return preset.systemPrompt
        }
    }

    private func startAIAnnotation(for selectionData: SelectionData, customPrompt: String?) async {
        guard let chapter = currentChapter,
              let pendingId = pendingHighlightId else { return }
        
        // Check if AI provider is configured
        guard threadState.isConfigured else {
            let error = NSError(
                domain: "Crux",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No AI provider configured. Please configure a provider in Settings."]
            )
            threadState.error = error
            return
        }
        
        // Create and commit the highlight
        let highlight = Highlight(
            id: pendingId,
            chapterId: chapter.id,
            selectedText: selectionData.text,
            surroundingContext: selectionData.context,
            cfiRange: selectionData.cfiRange
        )
        annotations.addHighlight(highlight)
        clearPendingSelection()
        try? await BookStorage.shared.saveAnnotations(annotations)

        // Clear any previous errors
        threadState.error = nil

        // Make this the panel's active highlight too, so the inspector (used
        // for follow-ups and on iOS) targets it — but the response renders in
        // the margin note anchored beside the passage.
        threadState.currentHighlight = highlight

        // Set loading state — drives the margin note's "Analyzing…" state.
        loadingHighlightId = pendingId

        // Start the AI thread with optional custom prompt
        if let thread = await threadState.startThread(
            for: highlight,
            book: book,
            chapter: currentChapter,
            bookId: annotations.bookId,
            customPrompt: customPrompt,
            imageSources: selectionData.images
        ) {
            annotations.addThread(to: pendingId, thread: thread)
            try? await BookStorage.shared.saveAnnotations(annotations)
        }

        // Clear loading state
        loadingHighlightId = nil
    }

    private func commitPendingHighlight() -> Highlight? {
        guard let pending = pendingSelection,
              let pendingId = pendingHighlightId,
              let chapter = currentChapter else { return nil }

        let highlight = Highlight(
            id: pendingId,
            chapterId: chapter.id,
            selectedText: pending.text,
            surroundingContext: pending.context,
            cfiRange: pending.cfiRange
        )
        annotations.addHighlight(highlight)
        clearPendingSelection()
        return highlight
    }

    /// Runs a chapter-scope AI action and opens the inspector to surface
    /// the streaming response, Stop, and Regenerate affordances. The
    /// result is ephemeral — not persisted as a highlight thread —
    /// because chapter analyses aren't tied to a specific passage.
    private func runChapterAIAction(label: String, prompt: String) {
        guard let chapter = currentChapter else { return }
        // Chapter-scope analyses use the whole-chapter context, not a
        // selected passage — clear any passage routed in from the iOS
        // selection bar so the inspector shows this analysis.
        inspectorSelection = nil
        showAIInspector = true
        threadState.resolvedSystemPrompt = resolvePromptFromSettings()
        threadState.runTracked {
            await threadState.startChapterAnalysis(
                label: label,
                prompt: prompt,
                chapter: chapter,
                book: book
            )
        }
    }

    private func handleMarginNoteAction(_ action: MarginNoteAction) {
        Task {
            switch action {
            case .commitHighlight(let highlightId):
                // Commit pending selection if it matches
                if pendingHighlightId == highlightId {
                    if let _ = commitPendingHighlight() {
                        try? await BookStorage.shared.saveAnnotations(annotations)
                    }
                }

            case .startThread(let highlightId):
                // Check if AI provider is configured
                guard threadState.isConfigured else {
                    // Show error to user instead of silent failure
                    let error = NSError(
                        domain: "Crux",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "No AI provider configured. Please configure a provider in Settings."]
                    )
                    threadState.error = error

                    // Set loading state to trigger margin note update with error
                    loadingHighlightId = highlightId
                    // Immediately clear to show error state
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                    loadingHighlightId = nil
                    return
                }

                // If this is a pending selection, commit it first
                var highlight: Highlight?
                if pendingHighlightId == highlightId {
                    highlight = commitPendingHighlight()
                    if highlight != nil {
                        try? await BookStorage.shared.saveAnnotations(annotations)
                    }
                } else {
                    highlight = annotations.highlights.first(where: { $0.id == highlightId })
                }

                guard let highlight = highlight else { return }

                // Clear any previous errors
                threadState.error = nil

                // Set loading state - triggers margin note update
                loadingHighlightId = highlightId

                if let thread = await threadState.startThread(
                    for: highlight,
                    book: book,
                    chapter: currentChapter,
                    bookId: annotations.bookId
                ) {
                    annotations.addThread(to: highlightId, thread: thread)
                    try? await BookStorage.shared.saveAnnotations(annotations)
                }

                // Clear loading state - triggers margin note update with content
                loadingHighlightId = nil

            case .sendFollowUp(let highlightId, let message):
                // Provider configuration check will happen in ThreadPanel
                guard threadState.isConfigured else {
                    return
                }

                guard let highlight = annotations.highlights.first(where: { $0.id == highlightId }) else { return }

                // Set loading state
                loadingHighlightId = highlightId

                // Get the existing thread from the highlight
                let existingThread = highlight.threads.first

                if let thread = await threadState.continueThread(
                    message: message,
                    highlight: highlight,
                    book: book,
                    existingThread: existingThread
                ) {
                    // Update the thread in annotations
                    if let highlightIndex = annotations.highlights.firstIndex(where: { $0.id == highlightId }),
                       let threadIndex = annotations.highlights[highlightIndex].threads.firstIndex(where: { $0.id == thread.id }) {
                        annotations.highlights[highlightIndex].threads[threadIndex] = thread
                        try? await BookStorage.shared.saveAnnotations(annotations)
                    }
                }

                // Clear loading state
                loadingHighlightId = nil

            case .openSettings:
                // Open Settings window using the standard keyboard shortcut
                #if os(macOS)
                if #available(macOS 13, *) {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } else {
                    NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                }
                #else
                // On iOS, the app structure should handle this
                // For now, we'll just log - this could be extended with a notification
                AppLog.ui.debug("Settings requested from reader view")
                #endif

            case .deleteHighlight(let highlightId):
                // If deleting a pending selection, just clear it
                if pendingHighlightId == highlightId {
                    clearPendingSelection()
                } else {
                    annotations.removeHighlight(id: highlightId)
                    try? await BookStorage.shared.saveAnnotations(annotations)
                }
            }
        }
    }

    /// Follow an internal EPUB hyperlink. Matches the link's last path
    /// component (and optional fragment) against the chapter list,
    /// pushes the current position onto the back stack, and navigates.
    ///
    /// EPUBs reference internal targets in three shapes:
    ///   1. `chapter02.xhtml`          → match by filePath only
    ///   2. `chapter02.xhtml#sec1`     → match by filePath + fragment
    ///   3. `#footnote-3`              → same-file fragment scroll
    ///
    /// Shape (3) leaves `path` empty (the URL's lastPathComponent is
    /// "/" when only the fragment changes — we treat empty as "same
    /// file" and scroll to the anchor without changing chapter.
    private func followInternalLink(path: String, fragment: String?) {
        // Same-file fragment-only navigation.
        if path.isEmpty || path == "/" {
            guard let fragment, !fragment.isEmpty else { return }
            pushNavigationHistory()
            let escaped = fragment.replacingOccurrences(of: "\\", with: "\\\\")
                                  .replacingOccurrences(of: "'", with: "\\'")
            evaluateJavaScript("CruxHighlighter.scrollToAnchor('\(escaped)');")
            return
        }

        // Find a chapter whose filePath ends with this path (the link's
        // last component). Prefer an exact match on filePath + fragment;
        // fall back to filePath alone.
        let needle = path.lowercased()
        var targetIndex: Int? = nil
        if let frag = fragment, !frag.isEmpty {
            targetIndex = book.chapters.firstIndex { chapter in
                chapter.filePath.lowercased().hasSuffix(needle)
                    && chapter.fragment?.lowercased() == frag.lowercased()
            }
        }
        if targetIndex == nil {
            targetIndex = book.chapters.firstIndex { chapter in
                chapter.filePath.lowercased().hasSuffix(needle)
            }
        }

        guard let targetIndex else {
            AppLog.reader.warning("Internal link target not found: \(path, privacy: .public)#\(fragment ?? "", privacy: .public)")
            return
        }

        pushNavigationHistory()
        navigateToChapter(targetIndex)

        // If the link had a fragment but it didn't disambiguate to a
        // dedicated chapter, still try to scroll to the anchor after the
        // page loads.
        if let frag = fragment, !frag.isEmpty,
           book.chapters[targetIndex].fragment != frag {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                let escaped = frag.replacingOccurrences(of: "\\", with: "\\\\")
                                  .replacingOccurrences(of: "'", with: "\\'")
                evaluateJavaScript("CruxHighlighter.scrollToAnchor('\(escaped)');")
            }
        }
    }

    private func pushNavigationHistory() {
        navigationHistory.append((chapterIndex: currentChapterIndex, scrollPosition: currentScrollPosition))
        if navigationHistory.count > Self.navigationHistoryLimit {
            navigationHistory.removeFirst(navigationHistory.count - Self.navigationHistoryLimit)
        }
    }

    private func popNavigationHistory() {
        guard let entry = navigationHistory.popLast() else { return }
        navigateToChapter(entry.chapterIndex)
        // Restore the scroll position the user had before following the
        // link, not just the chapter — important for long chapters
        // where the footnote may have been buried deep in the text.
        if entry.scrollPosition > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                pendingScrollPosition = entry.scrollPosition
                restoreScrollPositionIfNeeded()
            }
        }
    }

    private func navigateToChapter(_ index: Int) {
        guard index >= 0 && index < book.chapters.count else { return }
        clearPendingSelection()  // Discard uncommitted selection on chapter change

        // Set navigation guard to prevent scroll tracking feedback loop
        isNavigatingProgrammatically = true
        evaluateJavaScript("CruxViewportTracker.beginProgrammaticNavigation();")

        // Capture fragment and file path for scroll handling
        let newFilePath = book.chapters[index].filePath
        let sameFile = previousFilePath == newFilePath
        pendingFragment = book.chapters[index].fragment

        // If navigating within same file to a chapter without fragment, scroll to top
        if sameFile && pendingFragment == nil {
            pendingFragment = "__TOP__"  // Sentinel to trigger scroll to top
        }
        previousFilePath = newFilePath

        // Clear search state on chapter change (search again in new chapter)
        if searchState.isSearchActive && searchState.scope == .chapter {
            searchState.inChapterMatchCount = 0
            searchState.inChapterCurrentIndex = 0
        }

        // Animate chapter transition
        withAnimation(.easeInOut(duration: 0.25)) {
            currentChapterIndex = index
        }
        saveProgress()

        // End programmatic navigation after scroll settles
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isNavigatingProgrammatically = false
            evaluateJavaScript("CruxViewportTracker.endProgrammaticNavigation();")
        }
    }

    private func saveProgress() {
        guard let stored = storedBook else { return }
        stored.updateProgress(chapter: currentChapterIndex, total: book.chapters.count, scroll: currentScrollPosition)
        // Persist the element-level CFI so reopen restores precisely.
        // Always overwrite — an empty CFI means "we genuinely have no
        // better signal than scrollPosition right now," and the empty
        // string is the agreed sentinel for that case.
        stored.lastReadingCFI = currentReadingCFI
    }

    // MARK: - Bookmark Management

    private func addBookmark() {
        guard let chapter = currentChapter else { return }

        let bookmark = Bookmark(
            chapterId: chapter.id,
            chapterIndex: currentChapterIndex,
            chapterTitle: chapter.title,
            note: bookmarkNote.isEmpty ? nil : bookmarkNote,
            scrollPosition: currentScrollPosition
        )

        annotations.addBookmark(bookmark)

        // Save annotations
        Task {
            try? await BookStorage.shared.saveAnnotations(annotations)
        }

        // Clear the note for next time
        bookmarkNote = ""
    }

    private func deleteBookmark(id: UUID) {
        annotations.removeBookmark(id: id)

        // Save annotations
        Task {
            try? await BookStorage.shared.saveAnnotations(annotations)
        }
    }

    private func navigateToBookmark(_ bookmark: Bookmark) {
        // Navigate to the chapter
        navigateToChapter(bookmark.chapterIndex)

        // If there's a scroll position, restore it
        if bookmark.scrollPosition > 0 {
            // Delay to let chapter load first
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                pendingScrollPosition = bookmark.scrollPosition
                restoreScrollPositionIfNeeded()
            }
        }
    }

    // MARK: - Highlight Management

    private func deleteHighlight(id: UUID) {
        annotations.removeHighlight(id: id)

        // Save annotations
        Task {
            try? await BookStorage.shared.saveAnnotations(annotations)
        }
    }

    private func navigateToHighlight(_ highlight: Highlight) {
        // Find the chapter containing this highlight
        guard let chapterIndex = book.chapters.firstIndex(where: { $0.id == highlight.chapterId }) else {
            return
        }

        // Navigate to the chapter
        navigateToChapter(chapterIndex)

        // After chapter loads, scroll to the highlight
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            // Use CFI to scroll to highlight position
            guard let cfiRange = highlight.cfiRange else { return }
            let escaped = cfiRange.cfiString.replacingOccurrences(of: "'", with: "\\'")
            evaluateJavaScript("CruxHighlighter.scrollToCFI('\(escaped)');")
        }
    }

    private func scrollToFragmentOrTop() {
        guard let fragment = pendingFragment else { return }
        pendingFragment = nil

        if fragment == "__TOP__" {
            // Scroll to top of chapter
            evaluateJavaScript("window.scrollTo(0, 0);")
        } else {
            // Scroll to anchor
            let escaped = fragment.replacingOccurrences(of: "'", with: "\\'")
            evaluateJavaScript("CruxHighlighter.scrollToAnchor('\(escaped)');")
        }
    }

    private func handleVisibleSectionChange(_ chapterIndex: Int, scrollPosition: Double, cfi: String?) {
        // Always track scroll position
        currentScrollPosition = scrollPosition
        if let cfi = cfi, !cfi.isEmpty {
            currentReadingCFI = cfi
        }

        // Guard against feedback loops during programmatic navigation
        guard !isNavigatingProgrammatically else { return }

        // Update chapter if changed
        if chapterIndex != currentChapterIndex {
            guard chapterIndex >= 0 && chapterIndex < book.chapters.count else { return }
            currentChapterIndex = chapterIndex
            previousFilePath = book.chapters[chapterIndex].filePath
        }

        saveProgress()
    }

    private func initializeViewportTracking() {
        guard let chapter = currentChapter else { return }
        // Build anchor list for current file and initialize viewport tracker
        var anchors: [[String: Any]] = []

        for (index, ch) in book.chapters.enumerated() {
            guard ch.filePath == chapter.filePath else { continue }

            if let fragment = ch.fragment {
                anchors.append(["id": fragment, "chapterIndex": index, "isFileStart": false])
            } else {
                anchors.append(["id": "__crux_doc_start__", "chapterIndex": index, "isFileStart": true])
            }
        }

        guard !anchors.isEmpty,
              let jsonData = try? JSONSerialization.data(withJSONObject: anchors),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        evaluateJavaScript("CruxViewportTracker.init(\(jsonString));")
    }

    private func loadState() async {
        // Load saved chapter position and scroll
        if let stored = storedBook {
            currentChapterIndex = min(stored.currentChapterIndex, book.chapters.count - 1)
            pendingScrollPosition = stored.scrollPosition
            pendingReadingCFI = stored.lastReadingCFI
            currentReadingCFI = stored.lastReadingCFI

            // Backfill cached reading-time for books imported before
            // the field existed. We have the parsed chapters in hand;
            // computing once and saving avoids re-parsing every time the
            // library row asks.
            if stored.cachedReadingMinutes == 0 {
                let total = ReadingTimeEstimator.totalMinutes(
                    forChapters: book.chapters.map(\.content)
                )
                stored.cachedReadingMinutes = Int(total.rounded())
            }
        }

        // Initialize file path tracking
        if currentChapterIndex < book.chapters.count {
            previousFilePath = book.chapters[currentChapterIndex].filePath
        }

        // Load annotations
        do {
            annotations = try await BookStorage.shared.loadAnnotations(for: bookId)
        } catch {
            annotations = BookAnnotations(bookId: bookId)
        }
    }

    private func restoreScrollPositionIfNeeded() {
        // Prefer element-level CFI; fall back to scroll-percentage.
        let cfi = pendingReadingCFI
        let scrollPosition = pendingScrollPosition ?? 0
        let hasCFI = !cfi.isEmpty
        let hasScroll = scrollPosition > 0
        guard hasCFI || hasScroll else { return }
        pendingReadingCFI = ""
        pendingScrollPosition = nil

        // Set navigation guard to prevent the scroll from updating our saved position
        isNavigatingProgrammatically = true
        evaluateJavaScript("CruxViewportTracker.beginProgrammaticNavigation();")

        // Delay to ensure content is fully rendered before restoring position
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if hasCFI {
                // scrollToCFI returns true/false in JS; we don't read it
                // back here, but if it fails the page stays at the top
                // and `scrollPosition` (already persisted alongside)
                // remains the recovery anchor on a future reopen.
                let escaped = cfi.replacingOccurrences(of: "\\", with: "\\\\")
                                 .replacingOccurrences(of: "'", with: "\\'")
                evaluateJavaScript("CruxHighlighter.scrollToCFI('\(escaped)');")
            } else {
                evaluateJavaScript("CruxHighlighter.setScrollPosition(\(scrollPosition));")
            }

            // End programmatic navigation after scroll settles
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isNavigatingProgrammatically = false
                evaluateJavaScript("CruxViewportTracker.endProgrammaticNavigation();")
            }
        }
    }

    // MARK: - Search

    private func performInChapterSearch(_ query: String) {
        guard searchState.scope == .chapter else { return }
        let escaped = query.replacingOccurrences(of: "\\", with: "\\\\")
                          .replacingOccurrences(of: "'", with: "\\'")
        let js = "CruxSearch.search('\(escaped)');"
        evaluateJavaScript(js)
    }

    private func navigateSearchResult(forward: Bool) {
        if searchState.scope == .chapter {
            let js = forward ? "CruxSearch.nextMatch();" : "CruxSearch.previousMatch();"
            evaluateJavaScript(js)
        }
    }

    private func closeSearch() {
        evaluateJavaScript("CruxSearch.clearHighlights();")
        searchState.isSearchActive = false
        searchState.reset()
    }

    private func handleScopeChange(_ scope: SearchScope) {
        // Clear in-chapter highlights when switching scopes
        if scope == .book {
            evaluateJavaScript("CruxSearch.clearHighlights();")
            searchState.inChapterMatchCount = 0
            searchState.inChapterCurrentIndex = 0
            performBookSearch(searchState.query)
        } else {
            searchState.bookMatches = []
            // Re-run in-chapter search
            performInChapterSearch(searchState.query)
        }
    }

    /// Pre-build the per-book plain-text search index on a background
    /// priority Task so the first ⌘F doesn't pay the HTML-stripping
    /// cost mid-keystroke. Skipped for trivially small books where
    /// the lazy path was already fast enough.
    private func warmBookSearchIndex() async {
        guard book.chapters.count > 6, bookSearchIndex.chapters.isEmpty else { return }
        let chapters = book.chapters.enumerated().map { index, chapter in
            (index: index, id: chapter.id, title: chapter.title, html: chapter.content)
        }
        // BookSearchIndex is @MainActor — we hop back to main to write
        // the result, but the work itself is just iteration + string
        // operations and stays cheap even on the main queue. Wrapping
        // in `Task.detached(.utility)` would require lifting BookSearchIndex
        // off the main actor; not worth it for the size of work involved.
        await Task.yield()
        bookSearchIndex.build(from: chapters)
    }

    private func performBookSearch(_ query: String) {
        guard !query.isEmpty else {
            searchState.bookMatches = []
            return
        }

        // Index is normally pre-warmed by `.task`; this lazy fallback
        // covers tiny books that skipped warming or the first call
        // racing the warm-up Task.
        if bookSearchIndex.chapters.isEmpty {
            bookSearchIndex.build(from: book.chapters.enumerated().map { index, chapter in
                (index: index, id: chapter.id, title: chapter.title, html: chapter.content)
            })
        }

        let hits = bookSearchIndex.search(query)
        searchState.bookMatches = hits.map { hit in
            SearchMatch(
                text: hit.snippet,
                chapterId: hit.chapterId,
                chapterTitle: hit.chapterTitle,
                chapterIndex: hit.chapterIndex,
                matchIndex: hit.matchIndex
            )
        }

        // Save to search history if we got results
        if !searchState.bookMatches.isEmpty {
            appState.searchHistoryService.addSearch(
                query: query,
                bookId: bookId,
                resultCount: searchState.bookMatches.count
            )
        }
    }

    private func evaluateJavaScript(_ js: String) {
        // Access the webView through the view hierarchy
        // This is a workaround since we don't have direct access to the coordinator
        #if os(macOS)
        if let window = NSApplication.shared.keyWindow,
           let webView = findWebView(in: window.contentView) {
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
        #else
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let webView = findWebView(in: window) {
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
        #endif
    }

    #if os(macOS)
    private func findWebView(in view: NSView?) -> WKWebView? {
        guard let view = view else { return nil }
        if let webView = view as? WKWebView {
            return webView
        }
        for subview in view.subviews {
            if let found = findWebView(in: subview) {
                return found
            }
        }
        return nil
    }
    #else
    private func findWebView(in view: UIView?) -> WKWebView? {
        guard let view = view else { return nil }
        if let webView = view as? WKWebView {
            return webView
        }
        for subview in view.subviews {
            if let found = findWebView(in: subview) {
                return found
            }
        }
        return nil
    }
    #endif
}

// WebView for rendering EPUB HTML content
struct EPUBWebView: View {
    let chapter: Chapter
    let highlights: [Highlight]
    let marginNotes: [MarginNoteData]
    let onTextSelected: (SelectionData) -> Void
    let onHighlightTapped: (UUID) -> Void
    var onMarginNoteAction: ((MarginNoteAction) -> Void)? = nil
    var onSearchResults: ((Int, Int) -> Void)? = nil
    var onContentLoaded: (() -> Void)? = nil
    var onVisibleSection: ((Int, Double, String?) -> Void)? = nil
    var onContextMenuAction: ((SelectionData, SelectionContextAction) -> Void)? = nil
    var onInternalLink: ((String, String?) -> Void)? = nil

    @Query private var settings: [AppSettings]

    private var customCSS: String? {
        guard let appSettings = settings.first else { return nil }

        return ReaderResources.generateCustomCSS(
            fontFamily: appSettings.fontFamily,
            fontSize: appSettings.fontSize,
            lineHeight: appSettings.lineHeight,
            paragraphSpacing: appSettings.paragraphSpacing,
            marginWidth: appSettings.marginWidth,
            backgroundColor: appSettings.backgroundColor,
            textColor: appSettings.textColor
        )
    }

    var body: some View {
        EPUBWebViewRepresentable(
            html: chapter.content,
            highlights: highlights,
            marginNotes: marginNotes,
            customCSS: customCSS,
            onTextSelected: onTextSelected,
            onHighlightTapped: onHighlightTapped,
            onMarginNoteAction: onMarginNoteAction,
            onSearchResults: onSearchResults,
            onContentLoaded: onContentLoaded,
            onVisibleSection: onVisibleSection,
            onContextMenuAction: onContextMenuAction,
            onInternalLink: onInternalLink
        )
    }
}

// MARK: - Chapter Ask Sheet

/// Free-form composer for "Ask AI about this chapter" — sized like a
/// native compose sheet, autoexpands as the user types, ⌘Return commits.
struct ChapterAskSheet: View {
    let chapterTitle: String
    @Binding var question: String
    let onCancel: () -> Void
    let onSubmit: () -> Void

    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(LinearGradient(
                        colors: [Color.purple, Color.blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                Text("Ask about \(chapterTitle)")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }

            Text("Your question runs against the current chapter only. Use the AI Provider in Settings to switch models.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $question)
                .font(.body)
                .focused($fieldFocused)
                .frame(minHeight: 110, maxHeight: 220)
                .padding(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button {
                    onSubmit()
                } label: {
                    Label("Ask", systemImage: "arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        #if os(macOS)
        .frame(width: 480)
        #else
        .frame(maxWidth: .infinity)
        #endif
        .onAppear { fieldFocused = true }
    }
}
