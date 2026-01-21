import SwiftUI
import SwiftData
import WebKit

struct ReaderView: View {
    let book: Book
    let bookId: UUID

    @Environment(AppState.self) private var appState
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
    @State private var webViewCoordinator: WebViewCoordinator? = nil
    @State private var pendingFragment: String? = nil
    @State private var previousFilePath: String? = nil
    @State private var isNavigatingProgrammatically = false
    @State private var currentScrollPosition: Double = 0
    @State private var pendingScrollPosition: Double? = nil
    @State private var showTableOfContents = false
    @State private var showBookmarks = false
    @State private var showHighlights = false
    @State private var showAddBookmark = false
    @State private var showExportAnnotations = false
    @State private var bookmarkNote = ""
    @State private var sessionManager: ReadingSessionManager?

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

        // Add pending selection as a temporary highlight
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

        return highlights
    }

    /// Convert markdown text to HTML
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

    /// Build margin note data from current highlights for passing to WebView
    var currentMarginNotes: [MarginNoteData] {
        var notes: [MarginNoteData] = []

        // Add pending selection first (if any) - uncommitted
        if let pending = pendingSelection, let pendingId = pendingHighlightId {
            // Check if there's an error for this pending highlight
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

        // Add committed highlights for current chapter
        for highlight in currentChapterHighlights {
            let thread = highlight.threads.first
            let isLoading = loadingHighlightId == highlight.id

            // Check if there's an error for this highlight
            let errorMsg = (loadingHighlightId == highlight.id && threadState.error != nil)
                ? threadState.error?.localizedDescription
                : nil

            // Build thread content HTML if there are messages
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
                    onVisibleSection: { chapterIndex, scrollPosition in
                        handleVisibleSectionChange(chapterIndex, scrollPosition: scrollPosition)
                    }
                )
                .id(currentChapterIndex)  // Force view recreation on chapter change
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .trailing)),
                    removal: .opacity.combined(with: .move(edge: .leading))
                ))
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

            // Progress bar - shows chapter boundaries with current position
            GeometryReader { geo in
                let chapterWidth = geo.size.width / CGFloat(max(1, book.chapters.count))

                ZStack(alignment: .leading) {
                    // Background
                    Rectangle()
                        .fill(Color.secondary.opacity(0.15))

                    // Completed chapters
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.6))
                        .frame(width: chapterWidth * CGFloat(currentChapterIndex))

                    // Current chapter progress
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: chapterWidth * CGFloat(currentChapterIndex) + chapterWidth * currentScrollPosition)

                    // Chapter tick marks
                    HStack(spacing: 0) {
                        ForEach(0..<book.chapters.count, id: \.self) { i in
                            Rectangle()
                                .fill(Color.clear)
                                .frame(width: chapterWidth)
                                .overlay(alignment: .trailing) {
                                    if i < book.chapters.count - 1 {
                                        Rectangle()
                                            .fill(Color.primary.opacity(0.2))
                                            .frame(width: 1)
                                    }
                                }
                        }
                    }
                }
            }
            .frame(height: 4)
        }
        .navigationTitle(book.title)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                // View bookmarks
                Button {
                    showBookmarks = true
                } label: {
                    Label("Bookmarks", systemImage: "bookmark.fill")
                }

                // Add bookmark
                Button {
                    showAddBookmark = true
                } label: {
                    Label("Add Bookmark", systemImage: "bookmark.circle")
                }

                // Table of contents
                Button {
                    showTableOfContents = true
                } label: {
                    Label("Chapters", systemImage: "list.bullet")
                }

                // View highlights
                Button {
                    showHighlights = true
                } label: {
                    Label("Highlights", systemImage: "highlighter")
                }

                // Export annotations
                Button {
                    showExportAnnotations = true
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(annotations.highlights.isEmpty && annotations.bookmarks.isEmpty)
            }
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
        }
        .onAppear {
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
        storedBook?.updateProgress(chapter: currentChapterIndex, total: book.chapters.count, scroll: currentScrollPosition)
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

    private func handleVisibleSectionChange(_ chapterIndex: Int, scrollPosition: Double) {
        // Always track scroll position
        currentScrollPosition = scrollPosition

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
        guard let scrollPosition = pendingScrollPosition, scrollPosition > 0 else { return }
        pendingScrollPosition = nil

        // Set navigation guard to prevent the scroll from updating our saved position
        isNavigatingProgrammatically = true
        evaluateJavaScript("CruxViewportTracker.beginProgrammaticNavigation();")

        // Delay to ensure content is fully rendered before restoring position
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            evaluateJavaScript("CruxHighlighter.setScrollPosition(\(scrollPosition));")

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

    private func performBookSearch(_ query: String) {
        guard !query.isEmpty else {
            searchState.bookMatches = []
            return
        }

        var matches: [SearchMatch] = []

        for (index, chapter) in book.chapters.enumerated() {
            let plainText = HTMLTextExtractor.extractText(from: chapter.content)
            let chapterMatches = HTMLTextExtractor.findMatches(in: plainText, query: query)

            for (matchIndex, match) in chapterMatches.enumerated() {
                matches.append(SearchMatch(
                    text: match.snippet,
                    chapterId: chapter.id,
                    chapterTitle: chapter.title,
                    chapterIndex: index,
                    matchIndex: matchIndex
                ))
            }
        }

        searchState.bookMatches = matches

        // Save to search history if we got results
        if !matches.isEmpty {
            appState.searchHistoryService.addSearch(
                query: query,
                bookId: bookId,
                resultCount: matches.count
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
    var onVisibleSection: ((Int, Double) -> Void)? = nil

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
            onVisibleSection: onVisibleSection
        )
    }
}
