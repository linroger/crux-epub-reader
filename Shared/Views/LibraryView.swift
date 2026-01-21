import SwiftUI
import SwiftData

// MARK: - Main Library View (full screen)

enum LibrarySortOption: String, CaseIterable, Identifiable {
    case title = "Title"
    case author = "Author"
    case dateAdded = "Date Added"
    case lastRead = "Last Read"
    case progress = "Progress"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .title: return "textformat"
        case .author: return "person"
        case .dateAdded: return "calendar.badge.plus"
        case .lastRead: return "clock"
        case .progress: return "chart.bar"
        }
    }
}

enum ReadingStatusFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case notStarted = "Not Started"
    case inProgress = "In Progress"
    case finished = "Finished"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .all: return "books.vertical"
        case .notStarted: return "book.closed"
        case .inProgress: return "book"
        case .finished: return "checkmark.circle"
        }
    }
}

struct LibraryMainView: View {
    let storedBooks: [StoredBook]
    let onSelectBook: (UUID) -> Void
    let onAddBook: () -> Void
    let onDeleteBook: (StoredBook) -> Void
    let onImportBook: (URL) async -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BookCollection.sortOrder) private var collections: [BookCollection]

    @State private var searchQuery = ""
    @State private var annotationStats: [UUID: AnnotationStats] = [:]
    @State private var sortOption: LibrarySortOption = .lastRead
    @State private var sortAscending = false
    @State private var viewMode: LibraryViewMode = .list

    // Filter state
    @State private var selectedAuthor: String?
    @State private var readingStatusFilter: ReadingStatusFilter = .all
    @State private var selectedCollection: BookCollection?

    // Advanced filter state
    @State private var showingAdvancedFilters = false
    @State private var yearRangeMin: String = ""
    @State private var yearRangeMax: String = ""
    @State private var selectedLanguage: String?
    @State private var selectedPublisher: String?
    @State private var selectedSubjects = Set<String>()
    @State private var selectedTags = Set<String>()

    // Collections state
    @State private var showingCollections = false

    // Settings state (iOS)
    #if os(iOS)
    @State private var showingSettings = false
    #endif

    // Book details state
    @State private var detailsBookId: UUID?
    @State private var detailsBook: Book?
    @State private var detailsStoredBook: StoredBook?
    @State private var isLoadingDetails = false
    @State private var showingBookDetails = false

    // Drag & drop state
    @State private var isDropTargeted = false

    // Batch operations state
    @State private var isSelectionMode = false
    @State private var selectedBooks = Set<UUID>()
    @State private var showingBatchCollectionPicker = false
    @State private var showingBatchStatusPicker = false
    @State private var showingBatchDeleteConfirmation = false

    // Backup/Restore state
    @State private var isBackingUp = false
    @State private var isRestoring = false
    @State private var backupMessage: String?
    @State private var showingBackupAlert = false
    @State private var showingRestoreStrategyPicker = false
    @State private var selectedMergeStrategy: LibraryBackupService.MergeStrategy = .skip

    @State private var errorHandler = ErrorHandler.shared

    private let parser = EPUBParser()
    private let storage = BookStorage.shared

    private var uniqueAuthors: [String] {
        let authors = Set(storedBooks.compactMap { $0.author?.trimmingCharacters(in: .whitespaces) })
        return authors.sorted()
    }

    private var uniqueLanguages: [String] {
        let languages = Set(storedBooks.compactMap { $0.language?.trimmingCharacters(in: .whitespaces) })
        return languages.sorted()
    }

    private var uniquePublishers: [String] {
        let publishers = Set(storedBooks.compactMap { $0.publisher?.trimmingCharacters(in: .whitespaces) })
        return publishers.sorted()
    }

    private var allSubjects: [String] {
        let subjects = Set(storedBooks.flatMap { $0.subjects })
        return subjects.sorted()
    }

    private var allTags: [String] {
        let tags = Set(storedBooks.flatMap { $0.tags })
        return tags.sorted()
    }

    private var hasActiveFilters: Bool {
        selectedAuthor != nil ||
        readingStatusFilter != .all ||
        selectedCollection != nil ||
        !yearRangeMin.isEmpty ||
        !yearRangeMax.isEmpty ||
        selectedLanguage != nil ||
        selectedPublisher != nil ||
        !selectedSubjects.isEmpty ||
        !selectedTags.isEmpty
    }

    private var hasAdvancedFilters: Bool {
        !yearRangeMin.isEmpty ||
        !yearRangeMax.isEmpty ||
        selectedLanguage != nil ||
        selectedPublisher != nil ||
        !selectedSubjects.isEmpty ||
        !selectedTags.isEmpty
    }

    private var recentBooks: [StoredBook] {
        storedBooks
            .filter { $0.lastOpenedAt != nil && !$0.isFinished }
            .sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
            .prefix(5)
            .map { $0 }
    }

    private var sortedAndFilteredBooks: [StoredBook] {
        // First apply search filter
        let searchFiltered: [StoredBook]
        if searchQuery.isEmpty {
            searchFiltered = storedBooks
        } else {
            let query = searchQuery.lowercased()
            searchFiltered = storedBooks.filter { book in
                book.title.lowercased().contains(query) ||
                (book.author?.lowercased().contains(query) ?? false) ||
                book.subjects.contains { $0.lowercased().contains(query) } ||
                book.tags.contains { $0.lowercased().contains(query) }
            }
        }

        // Apply author filter
        let authorFiltered: [StoredBook]
        if let author = selectedAuthor {
            authorFiltered = searchFiltered.filter { $0.author == author }
        } else {
            authorFiltered = searchFiltered
        }

        // Apply reading status filter
        let statusFiltered: [StoredBook]
        switch readingStatusFilter {
        case .all:
            statusFiltered = authorFiltered
        case .notStarted:
            statusFiltered = authorFiltered.filter { $0.currentChapterIndex == 0 && !$0.isFinished }
        case .inProgress:
            statusFiltered = authorFiltered.filter { $0.currentChapterIndex > 0 && !$0.isFinished }
        case .finished:
            statusFiltered = authorFiltered.filter { $0.isFinished }
        }

        // Apply collection filter
        let collectionFiltered: [StoredBook]
        if let collection = selectedCollection {
            collectionFiltered = statusFiltered.filter { book in
                book.collections?.contains(where: { $0.id == collection.id }) ?? false
            }
        } else {
            collectionFiltered = statusFiltered
        }

        // Apply publication year filter
        let yearFiltered: [StoredBook]
        let minYear = Int(yearRangeMin)
        let maxYear = Int(yearRangeMax)

        if minYear != nil || maxYear != nil {
            yearFiltered = collectionFiltered.filter { book in
                guard let year = book.publicationYear else { return false }
                if let min = minYear, year < min { return false }
                if let max = maxYear, year > max { return false }
                return true
            }
        } else {
            yearFiltered = collectionFiltered
        }

        // Apply language filter
        let languageFiltered: [StoredBook]
        if let language = selectedLanguage {
            languageFiltered = yearFiltered.filter { $0.language == language }
        } else {
            languageFiltered = yearFiltered
        }

        // Apply publisher filter
        let publisherFiltered: [StoredBook]
        if let publisher = selectedPublisher {
            publisherFiltered = languageFiltered.filter { $0.publisher == publisher }
        } else {
            publisherFiltered = languageFiltered
        }

        // Apply subjects filter
        let subjectsFiltered: [StoredBook]
        if !selectedSubjects.isEmpty {
            subjectsFiltered = publisherFiltered.filter { book in
                !Set(book.subjects).isDisjoint(with: selectedSubjects)
            }
        } else {
            subjectsFiltered = publisherFiltered
        }

        // Apply tags filter
        let tagsFiltered: [StoredBook]
        if !selectedTags.isEmpty {
            tagsFiltered = subjectsFiltered.filter { book in
                !Set(book.tags).isDisjoint(with: selectedTags)
            }
        } else {
            tagsFiltered = subjectsFiltered
        }

        let filtered = tagsFiltered

        return filtered.sorted { (lhs: StoredBook, rhs: StoredBook) -> Bool in
            let comparison: Bool
            switch sortOption {
            case .title:
                comparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case .author:
                let lhsAuthor = lhs.author ?? ""
                let rhsAuthor = rhs.author ?? ""
                comparison = lhsAuthor.localizedCaseInsensitiveCompare(rhsAuthor) == .orderedAscending
            case .dateAdded:
                comparison = lhs.addedAt < rhs.addedAt
            case .lastRead:
                comparison = (lhs.lastOpenedAt ?? .distantPast) < (rhs.lastOpenedAt ?? .distantPast)
            case .progress:
                let lhsProgress = lhs.totalChapters > 0 ? Double(lhs.currentChapterIndex) / Double(lhs.totalChapters) : 0
                let rhsProgress = rhs.totalChapters > 0 ? Double(rhs.currentChapterIndex) / Double(rhs.totalChapters) : 0
                comparison = lhsProgress < rhsProgress
            }
            return sortAscending ? comparison : !comparison
        }
    }

    var body: some View {
        NavigationStack {
            libraryContent
                .navigationTitle("Library")
                .toolbar {
                    toolbarContent
                }
                .task {
                    await loadAnnotationStats()
                }
                .onChange(of: storedBooks.count) { _, _ in
                    Task { await loadAnnotationStats() }
                }
                .onChange(of: detailsBookId) { _, newId in
                    handleDetailsChange(newId)
                }
                .sheet(isPresented: $showingBookDetails) {
                    bookDetailSheet
                }
                .sheet(isPresented: $showingCollections) {
                    CollectionsView()
                }
                .sheet(isPresented: $showingAdvancedFilters) {
                    AdvancedFiltersSheet(
                        yearRangeMin: $yearRangeMin,
                        yearRangeMax: $yearRangeMax,
                        selectedLanguage: $selectedLanguage,
                        selectedPublisher: $selectedPublisher,
                        selectedSubjects: $selectedSubjects,
                        selectedTags: $selectedTags,
                        uniqueLanguages: uniqueLanguages,
                        uniquePublishers: uniquePublishers,
                        allSubjects: allSubjects,
                        allTags: allTags
                    )
                }
                .sheet(isPresented: $showingRestoreStrategyPicker) {
                    RestoreStrategyPickerSheet(
                        selectedStrategy: $selectedMergeStrategy,
                        onRestore: {
                            Task { await performRestore() }
                        }
                    )
                }
                #if os(iOS)
                .sheet(isPresented: $showingSettings) {
                    iOSSettingsView()
                }
                #endif
                .confirmationDialog(
                    "Add \(selectedBooks.count) book\(selectedBooks.count == 1 ? "" : "s") to collection",
                    isPresented: $showingBatchCollectionPicker
                ) {
                    ForEach(collections) { collection in
                        Button(collection.name) {
                            batchAddToCollection(collection)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                }
                .confirmationDialog(
                    "Change status for \(selectedBooks.count) book\(selectedBooks.count == 1 ? "" : "s")",
                    isPresented: $showingBatchStatusPicker
                ) {
                    Button(ReadingStatus.wantToRead.rawValue) {
                        batchChangeStatus(.wantToRead)
                    }
                    Button(ReadingStatus.reading.rawValue) {
                        batchChangeStatus(.reading)
                    }
                    Button(ReadingStatus.finished.rawValue) {
                        batchChangeStatus(.finished)
                    }
                    Button("Cancel", role: .cancel) {}
                }
                .alert(
                    "Delete \(selectedBooks.count) book\(selectedBooks.count == 1 ? "" : "s")",
                    isPresented: $showingBatchDeleteConfirmation
                ) {
                    Button("Cancel", role: .cancel) {}
                    Button("Delete", role: .destructive) {
                        batchDelete()
                    }
                } message: {
                    Text("This will permanently remove \(selectedBooks.count) book\(selectedBooks.count == 1 ? "" : "s") from your library. This action cannot be undone.")
                }
                .alert(
                    "Backup & Restore",
                    isPresented: $showingBackupAlert
                ) {
                    Button("OK", role: .cancel) {}
                } message: {
                    if let message = backupMessage {
                        Text(message)
                    }
                }
                .withFeedback()
        }
    }

    @ViewBuilder
    private var libraryContent: some View {
        VStack(spacing: 0) {
            // Search bar
            if !storedBooks.isEmpty {
                LibrarySearchBar(query: $searchQuery)
            }

            // Content
            mainContent
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .overlay {
            // Drop target indicator
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.blue, lineWidth: 3, antialiased: true)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue.opacity(0.1))
                    )
                    .overlay {
                        VStack(spacing: 12) {
                            Image(systemName: "book.circle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.blue)

                            Text("Drop EPUB files here to import")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                    }
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            // Batch operations toolbar (when in selection mode)
            if isSelectionMode {
                batchOperationsToolbar
            } else {
                normalToolbar
            }
        }
    }

    @ViewBuilder
    private var normalToolbar: some View {
        // Selection mode toggle
        if !storedBooks.isEmpty {
            Button {
                isSelectionMode = true
            } label: {
                Label("Select", systemImage: "checkmark.circle")
            }
            .help("Select multiple books")
        }

        // View mode toggle
        Button {
            viewMode = viewMode == .list ? .grid : .list
        } label: {
            Label(
                viewMode == .list ? "Grid View" : "List View",
                systemImage: viewMode == .list ? "square.grid.2x2" : "list.bullet"
            )
        }

        // Sort direction toggle
        Button {
            sortAscending.toggle()
        } label: {
            Label(
                sortAscending ? "Sort Ascending" : "Sort Descending",
                systemImage: sortAscending ? "arrow.up" : "arrow.down"
            )
        }

        // Sort option menu
        Menu {
            Picker("Sort By", selection: $sortOption) {
                ForEach(LibrarySortOption.allCases) { option in
                    Label(option.rawValue, systemImage: option.systemImage)
                        .tag(option)
                }
            }
        } label: {
            Label("Sort: \(sortOption.rawValue)", systemImage: "arrow.up.arrow.down")
        }

        // Reading status filter
        Menu {
            Picker("Status", selection: $readingStatusFilter) {
                ForEach(ReadingStatusFilter.allCases) { status in
                    Label(status.rawValue, systemImage: status.systemImage)
                        .tag(status)
                }
            }
        } label: {
            Label(
                readingStatusFilter == .all ? "Filter: Status" : "Status: \(readingStatusFilter.rawValue)",
                systemImage: readingStatusFilter.systemImage
            )
        }
        .help("Filter by reading status")

        // Author filter
        if !uniqueAuthors.isEmpty {
            Menu {
                Button {
                    selectedAuthor = nil
                } label: {
                    Label("All Authors", systemImage: "person.2")
                }

                Divider()

                ForEach(uniqueAuthors, id: \.self) { author in
                    Button {
                        selectedAuthor = author
                    } label: {
                        HStack {
                            Label(author, systemImage: "person")
                            if selectedAuthor == author {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label(
                    selectedAuthor ?? "Filter: Author",
                    systemImage: "person"
                )
            }
            .help("Filter by author")
        }

        // Collection filter
        if !collections.isEmpty {
            Menu {
                Button {
                    selectedCollection = nil
                } label: {
                    Label("All Collections", systemImage: "folder.badge.gearshape")
                }

                Divider()

                ForEach(collections) { collection in
                    Button {
                        selectedCollection = collection
                    } label: {
                        HStack {
                            Image(systemName: collection.icon)
                                .foregroundStyle(Color(hex: collection.colorHex) ?? .blue)
                            Text(collection.name)
                            if selectedCollection?.id == collection.id {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label(
                    selectedCollection?.name ?? "Filter: Collection",
                    systemImage: selectedCollection?.icon ?? "folder"
                )
            }
            .help("Filter by collection")
        }

        // Advanced filters button
        Button {
            showingAdvancedFilters = true
        } label: {
            Label(
                hasAdvancedFilters ? "Advanced Filters •" : "Advanced Filters",
                systemImage: "line.3.horizontal.decrease.circle"
            )
        }
        .help("Advanced filter options")

        // Clear filters button (only show when filters are active)
        if hasActiveFilters {
            Button {
                selectedAuthor = nil
                readingStatusFilter = .all
                selectedCollection = nil
                yearRangeMin = ""
                yearRangeMax = ""
                selectedLanguage = nil
                selectedPublisher = nil
                selectedSubjects.removeAll()
                selectedTags.removeAll()
            } label: {
                Label("Clear Filters", systemImage: "xmark.circle")
            }
            .help("Clear all active filters")
        }

        // Collections manager button
        Button {
            showingCollections = true
        } label: {
            Label("Collections", systemImage: "folder.badge.gearshape")
        }
        .help("Manage collections")

        // Settings button (iOS only)
        #if os(iOS)
        Button {
            showingSettings = true
        } label: {
            Label("Settings", systemImage: "gearshape")
        }
        .help("App settings")
        #endif

        // Backup/Restore buttons (macOS only)
        #if os(macOS)
        Menu {
            Button {
                Task { await performBackup() }
            } label: {
                Label("Backup Library...", systemImage: "arrow.down.doc")
            }
            .disabled(storedBooks.isEmpty || isBackingUp || isRestoring)

            Button {
                showingRestoreStrategyPicker = true
            } label: {
                Label("Restore Library...", systemImage: "arrow.up.doc")
            }
            .disabled(isBackingUp || isRestoring)
        } label: {
            Label("Backup", systemImage: "archivebox")
        }
        .help("Backup or restore library")
        #endif

        // Add book button
        Button(action: onAddBook) {
            Label("Add Book", systemImage: "plus")
        }
        .help("Open EPUB file (⌘O)")
    }

    @ViewBuilder
    private var batchOperationsToolbar: some View {
        // Selection info
        Text("\(selectedBooks.count) selected")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)

        // Select all / Deselect all
        Button {
            if selectedBooks.count == sortedAndFilteredBooks.count {
                selectedBooks.removeAll()
            } else {
                selectedBooks = Set(sortedAndFilteredBooks.map { $0.id })
            }
        } label: {
            Label(
                selectedBooks.count == sortedAndFilteredBooks.count ? "Deselect All" : "Select All",
                systemImage: selectedBooks.count == sortedAndFilteredBooks.count ? "checkmark.circle.fill" : "circle"
            )
        }
        .disabled(sortedAndFilteredBooks.isEmpty)

        Divider()

        // Batch actions (only enabled when books are selected)
        if !selectedBooks.isEmpty {
            // Add to collection
            if !collections.isEmpty {
                Button {
                    showingBatchCollectionPicker = true
                } label: {
                    Label("Add to Collection", systemImage: "folder.badge.plus")
                }
            }

            // Change status
            Button {
                showingBatchStatusPicker = true
            } label: {
                Label("Change Status", systemImage: "book.circle")
            }

            // Delete
            Button(role: .destructive) {
                showingBatchDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }

        Divider()

        // Done button
        Button {
            isSelectionMode = false
            selectedBooks.removeAll()
        } label: {
            Text("Done")
                .fontWeight(.semibold)
        }
    }

    // MARK: - Batch Operations

    private func batchAddToCollection(_ collection: BookCollection) {
        let booksToUpdate = storedBooks.filter { selectedBooks.contains($0.id) }
        for book in booksToUpdate {
            if book.collections == nil {
                book.collections = []
            }
            // Only add if not already in collection
            if !(book.collections?.contains(where: { $0.id == collection.id }) ?? false) {
                book.collections?.append(collection)
            }
        }
        try? modelContext.save()

        // Exit selection mode after batch operation
        isSelectionMode = false
        selectedBooks.removeAll()
    }

    private func batchChangeStatus(_ status: ReadingStatus) {
        let booksToUpdate = storedBooks.filter { selectedBooks.contains($0.id) }
        for book in booksToUpdate {
            book.readingStatus = status
        }
        try? modelContext.save()

        // Exit selection mode after batch operation
        isSelectionMode = false
        selectedBooks.removeAll()
    }

    private func batchDelete() {
        let booksToDelete = storedBooks.filter { selectedBooks.contains($0.id) }
        for book in booksToDelete {
            // Remove from storage
            Task {
                try? await BookStorage.shared.removeBook(book.id)
            }
            // Remove from SwiftData
            modelContext.delete(book)
        }

        // Exit selection mode after batch operation
        isSelectionMode = false
        selectedBooks.removeAll()
    }

    // MARK: - Backup/Restore Functions

    #if os(macOS)
    private func performBackup() async {
        isBackingUp = true
        defer { isBackingUp = false }

        do {
            let url = try await LibraryBackupService.shared.exportBackupToFile(
                books: storedBooks,
                collections: collections
            )

            if let url = url {
                backupMessage = "Library backup saved successfully to:\n\(url.path)"
                errorHandler.showSuccess("Library backup saved successfully")
            } else {
                backupMessage = "Backup cancelled."
            }
        } catch {
            backupMessage = "Backup failed: \(error.localizedDescription)"
            errorHandler.handle(
                AppError.backupFailed(error.localizedDescription),
                context: "performBackup"
            )
        }

        showingBackupAlert = true
    }

    private func performRestore() async {
        isRestoring = true
        defer { isRestoring = false }

        do {
            let stats = try await LibraryBackupService.shared.importBackupFromFile(
                modelContext: modelContext,
                mergeStrategy: selectedMergeStrategy
            )

            if let stats = stats {
                let message = """
                Restore completed!

                Books: \(stats.booksCreated) created, \(stats.booksUpdated) updated, \(stats.booksSkipped) skipped
                Collections: \(stats.collectionsCreated) created, \(stats.collectionsUpdated) updated
                """
                backupMessage = message
                errorHandler.showSuccess("Library restored successfully")
            } else {
                backupMessage = "Restore cancelled."
            }
        } catch {
            backupMessage = "Restore failed: \(error.localizedDescription)"
            errorHandler.handle(
                AppError.restoreFailed(error.localizedDescription),
                context: "performRestore"
            )
        }

        showingBackupAlert = true
    }
    #endif

    private func handleDetailsChange(_ newId: UUID?) {
        if let newId {
            detailsStoredBook = storedBooks.first(where: { $0.id == newId })
            Task { await loadBookDetails(id: newId) }
        } else {
            detailsBook = nil
            detailsStoredBook = nil
            showingBookDetails = false
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if storedBooks.isEmpty {
            EmptyLibraryView(onAddBook: onAddBook)
        } else if sortedAndFilteredBooks.isEmpty {
            if !searchQuery.isEmpty {
                ContentUnavailableView.search(text: searchQuery)
            } else if hasActiveFilters {
                ContentUnavailableView(
                    "No books match your filters",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Try adjusting or clearing your filters to see more books")
                )
            } else {
                ContentUnavailableView(
                    "No books found",
                    systemImage: "book.closed"
                )
            }
        } else {
            VStack(spacing: 0) {
                // Recent books section (only show when not searching)
                if searchQuery.isEmpty && !recentBooks.isEmpty {
                    RecentBooksSection(
                        books: recentBooks,
                        onSelectBook: onSelectBook,
                        onShowDetails: { bookId in
                            detailsBookId = bookId
                        }
                    )
                    .padding(.bottom, 16)

                    Divider()
                        .padding(.bottom, 8)
                }

                // Active filters indicator
                if hasActiveFilters {
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                            .foregroundStyle(.blue)
                            .font(.system(size: 14))

                        Text("Active filters:")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)

                        // Status filter badge
                        if readingStatusFilter != .all {
                            FilterBadge(
                                text: readingStatusFilter.rawValue,
                                icon: readingStatusFilter.systemImage,
                                onRemove: { readingStatusFilter = .all }
                            )
                        }

                        // Author filter badge
                        if let author = selectedAuthor {
                            FilterBadge(
                                text: author,
                                icon: "person",
                                onRemove: { selectedAuthor = nil }
                            )
                        }

                        Spacer()

                        // Clear all filters button
                        Button {
                            selectedAuthor = nil
                            readingStatusFilter = .all
                            selectedCollection = nil
                            yearRangeMin = ""
                            yearRangeMax = ""
                            selectedLanguage = nil
                            selectedPublisher = nil
                            selectedSubjects.removeAll()
                            selectedTags.removeAll()
                        } label: {
                            Text("Clear All")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.05))

                    Divider()
                }

                // Main library view
                if viewMode == .list {
                    BookListView(
                        books: sortedAndFilteredBooks,
                        collections: collections,
                        annotationStats: annotationStats,
                        modelContext: modelContext,
                        isSelectionMode: isSelectionMode,
                        selectedBooks: $selectedBooks,
                        onSelectBook: onSelectBook,
                        onShowDetails: { bookId in
                            detailsBookId = bookId
                        },
                        onDeleteBook: onDeleteBook
                    )
                } else {
                    BookGridView(
                        books: sortedAndFilteredBooks,
                        collections: collections,
                        annotationStats: annotationStats,
                        modelContext: modelContext,
                        isSelectionMode: isSelectionMode,
                        selectedBooks: $selectedBooks,
                        onSelectBook: onSelectBook,
                        onShowDetails: { bookId in
                            detailsBookId = bookId
                        },
                        onDeleteBook: onDeleteBook
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var bookDetailSheet: some View {
        if let book = detailsBook, let storedBook = detailsStoredBook {
            BookDetailView(
                storedBook: storedBook,
                book: book,
                onOpenBook: {
                    let bookId = storedBook.id
                    showingBookDetails = false
                    detailsBookId = nil
                    onSelectBook(bookId)
                }
            )
        } else {
            ProgressView("Loading book details...")
                .frame(minWidth: 600, minHeight: 700)
        }
    }

    #if os(iOS)
    @ViewBuilder
    private func iOSSettingsView() -> some View {
        NavigationStack {
            Form {
                GeneralSettingsView()

                Section {
                    ReaderSettingsView()
                } header: {
                    Text("Reader")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showingSettings = false
                    }
                }
            }
        }
    }
    #endif

    private func loadAnnotationStats() async {
        for book in storedBooks {
            let stats = await BookStorage.shared.loadAnnotationStats(for: book.id)
            annotationStats[book.id] = stats
        }
    }

    private func loadBookDetails(id: UUID) async {
        isLoadingDetails = true
        defer { isLoadingDetails = false }

        do {
            let url = await storage.bookURL(for: id)
            let book = try await parser.parse(url: url)
            detailsBook = book
            showingBookDetails = true
        } catch {
            // If loading fails, reset state
            detailsBookId = nil
            detailsStoredBook = nil
            errorHandler.handle(
                AppError.epubParsingFailed(error.localizedDescription),
                context: "loadBookDetails"
            )
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        #if os(macOS)
        // Process each dropped item
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      url.pathExtension.lowercased() == "epub" else {
                    return
                }

                // Import the book on the main actor
                Task { @MainActor in
                    await onImportBook(url)
                }
            }
        }
        return true
        #else
        return false
        #endif
    }
}

struct LibrarySearchBar: View {
    @Binding var query: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search library...", text: $query)
                .textFieldStyle(.plain)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary)
        .cornerRadius(8)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct BookListView: View {
    let books: [StoredBook]
    let collections: [BookCollection]
    let annotationStats: [UUID: AnnotationStats]
    let modelContext: ModelContext
    let isSelectionMode: Bool
    @Binding var selectedBooks: Set<UUID>
    let onSelectBook: (UUID) -> Void
    let onShowDetails: (UUID) -> Void
    let onDeleteBook: (StoredBook) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(books) { book in
                    HStack(spacing: 12) {
                        // Selection checkbox (in selection mode)
                        if isSelectionMode {
                            Button {
                                toggleSelection(book.id)
                            } label: {
                                Image(systemName: selectedBooks.contains(book.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22))
                                    .foregroundStyle(selectedBooks.contains(book.id) ? .blue : .secondary)
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 16)
                        }

                        BookListRow(
                            book: book,
                            stats: annotationStats[book.id],
                            onShowDetails: {
                                onShowDetails(book.id)
                            }
                        )
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isSelectionMode {
                            toggleSelection(book.id)
                        } else {
                            onSelectBook(book.id)
                        }
                    }
                    .contextMenu {
                        // Disable context menu in selection mode
                        if !isSelectionMode {
                            Button {
                                onShowDetails(book.id)
                            } label: {
                                Label("Show Details", systemImage: "info.circle")
                            }

                            if !collections.isEmpty {
                                Menu {
                                    ForEach(collections) { collection in
                                        Button {
                                            toggleBookInCollection(book: book, collection: collection)
                                        } label: {
                                            HStack {
                                                Image(systemName: collection.icon)
                                                    .foregroundStyle(Color(hex: collection.colorHex) ?? .blue)
                                                Text(collection.name)
                                                Spacer()
                                                if book.collections?.contains(where: { $0.id == collection.id }) == true {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    Label("Collections", systemImage: "folder")
                                }
                            }

                            Button(role: .destructive) {
                                onDeleteBook(book)
                            } label: {
                                Label("Remove from Library", systemImage: "trash")
                            }
                        }
                    }

                    if book.id != books.last?.id {
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
    }

    private func toggleSelection(_ bookId: UUID) {
        if selectedBooks.contains(bookId) {
            selectedBooks.remove(bookId)
        } else {
            selectedBooks.insert(bookId)
        }
    }

    private func toggleBookInCollection(book: StoredBook, collection: BookCollection) {
        if let bookCollections = book.collections,
           bookCollections.contains(where: { $0.id == collection.id }) {
            // Remove from collection
            book.collections?.removeAll(where: { $0.id == collection.id })
        } else {
            // Add to collection
            if book.collections == nil {
                book.collections = []
            }
            book.collections?.append(collection)
        }
        try? modelContext.save()
    }
}

struct BookListRow: View {
    let book: StoredBook
    let stats: AnnotationStats?
    let onShowDetails: () -> Void
    @State private var isHovered = false

    private var progressFraction: Double {
        guard book.totalChapters > 0 else { return 0 }
        if book.isFinished { return 1.0 }
        return Double(book.currentChapterIndex) / Double(book.totalChapters)
    }

    private var progressPercent: Int {
        Int(progressFraction * 100)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Cover thumbnail
            if let coverData = book.coverImageData,
               let nsImage = NSImage(data: coverData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                // Fallback placeholder
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.4), .purple.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 60)
                    .overlay {
                        Image(systemName: "book.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.7))
                    }
            }

            VStack(alignment: .leading, spacing: 3) {
                // Line 1: Title + Info button + Added date
                HStack(alignment: .top) {
                    Text(book.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    if isHovered {
                        Button {
                            onShowDetails()
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Show book details")
                    }

                    Text("Added \(book.addedAt.relativeShort)")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                // Line 2: Author · Publisher · Year · Language
                MetadataLine(book: book)

                // Line 3: Progress bar + Chapter position + Last read
                ProgressLine(book: book, progressFraction: progressFraction, progressPercent: progressPercent)

                // Line 4: Annotations + Subjects
                AnnotationLine(stats: stats, subjects: book.subjects)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isHovered ? Color.primary.opacity(0.03) : Color.clear)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Row Components

struct MetadataLine: View {
    let book: StoredBook

    var body: some View {
        HStack(spacing: 0) {
            let parts = metadataParts
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                Text(part)
                if index < parts.count - 1 {
                    Text(" · ")
                        .foregroundStyle(.quaternary)
                }
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var metadataParts: [String] {
        var parts: [String] = []
        if let author = book.author, !author.isEmpty {
            parts.append(author)
        }
        if let publisher = book.publisher, !publisher.isEmpty {
            parts.append(publisher)
        }
        if let year = book.publicationYear {
            parts.append(String(year))
        }
        if let language = book.language, !language.isEmpty {
            parts.append(language.uppercased())
        }
        return parts
    }
}

struct ProgressLine: View {
    let book: StoredBook
    let progressFraction: Double
    let progressPercent: Int

    var body: some View {
        HStack(spacing: 8) {
            // Progress bar (flex width)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))

                    Capsule()
                        .fill(book.isFinished ? Color.green : Color.primary.opacity(0.4))
                        .frame(width: max(0, geo.size.width * progressFraction))
                }
            }
            .frame(height: 4)

            // Chapter progress
            if book.totalChapters > 0 {
                Text(chapterText)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(book.isFinished ? .green : .secondary)
            }

            // Last read
            if let lastOpened = book.lastOpenedAt {
                Text("·")
                    .foregroundStyle(.quaternary)
                Text("Read \(lastOpened.relativeShort)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var chapterText: String {
        if book.isFinished {
            return "Done"
        }
        return "Ch \(book.currentChapterIndex + 1)/\(book.totalChapters) (\(progressPercent)%)"
    }
}

struct AnnotationLine: View {
    let stats: AnnotationStats?
    let subjects: [String]

    var body: some View {
        HStack(spacing: 0) {
            // Annotation stats
            if let stats = stats, stats.highlightCount > 0 || stats.threadCount > 0 {
                HStack(spacing: 8) {
                    if stats.highlightCount > 0 {
                        Label("\(stats.highlightCount)", systemImage: "highlighter")
                            .font(.system(size: 11))
                    }
                    if stats.threadCount > 0 {
                        Label("\(stats.threadCount)", systemImage: "bubble.left")
                            .font(.system(size: 11))
                    }
                }
                .foregroundStyle(.tertiary)

                if !subjects.isEmpty {
                    Text(" · ")
                        .foregroundStyle(.quaternary)
                }
            }

            // Subjects
            if !subjects.isEmpty {
                Text(subjects.prefix(3).joined(separator: ", "))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Grid View

struct BookGridView: View {
    let books: [StoredBook]
    let collections: [BookCollection]
    let annotationStats: [UUID: AnnotationStats]
    let modelContext: ModelContext
    let isSelectionMode: Bool
    @Binding var selectedBooks: Set<UUID>
    let onSelectBook: (UUID) -> Void
    let onShowDetails: (UUID) -> Void
    let onDeleteBook: (StoredBook) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 200, maximum: 250), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(books) { book in
                    ZStack(alignment: .topLeading) {
                        BookGridCard(
                            book: book,
                            stats: annotationStats[book.id],
                            onShowDetails: {
                                onShowDetails(book.id)
                            }
                        )

                        // Selection checkbox overlay (in selection mode)
                        if isSelectionMode {
                            Button {
                                toggleSelection(book.id)
                            } label: {
                                Image(systemName: selectedBooks.contains(book.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 24))
                                    .foregroundStyle(selectedBooks.contains(book.id) ? .blue : .secondary)
                                    .background(
                                        Circle()
                                            .fill(.background)
                                            .padding(-4)
                                    )
                            }
                            .buttonStyle(.plain)
                            .padding(16)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isSelectionMode {
                            toggleSelection(book.id)
                        } else {
                            onSelectBook(book.id)
                        }
                    }
                    .contextMenu {
                        // Disable context menu in selection mode
                        if !isSelectionMode {
                            Button {
                                onShowDetails(book.id)
                            } label: {
                                Label("Show Details", systemImage: "info.circle")
                            }

                            if !collections.isEmpty {
                                Menu {
                                    ForEach(collections) { collection in
                                        Button {
                                            toggleBookInCollection(book: book, collection: collection)
                                        } label: {
                                            HStack {
                                                Image(systemName: collection.icon)
                                                    .foregroundStyle(Color(hex: collection.colorHex) ?? .blue)
                                                Text(collection.name)
                                                Spacer()
                                                if book.collections?.contains(where: { $0.id == collection.id }) == true {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    Label("Collections", systemImage: "folder")
                                }
                            }

                            Button(role: .destructive) {
                                onDeleteBook(book)
                            } label: {
                                Label("Remove from Library", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity)
    }

    private func toggleSelection(_ bookId: UUID) {
        if selectedBooks.contains(bookId) {
            selectedBooks.remove(bookId)
        } else {
            selectedBooks.insert(bookId)
        }
    }

    private func toggleBookInCollection(book: StoredBook, collection: BookCollection) {
        if let bookCollections = book.collections,
           bookCollections.contains(where: { $0.id == collection.id }) {
            // Remove from collection
            book.collections?.removeAll(where: { $0.id == collection.id })
        } else {
            // Add to collection
            if book.collections == nil {
                book.collections = []
            }
            book.collections?.append(collection)
        }
        try? modelContext.save()
    }
}

struct BookGridCard: View {
    let book: StoredBook
    let stats: AnnotationStats?
    let onShowDetails: () -> Void
    @State private var isHovered = false

    private var progressFraction: Double {
        guard book.totalChapters > 0 else { return 0 }
        if book.isFinished { return 1.0 }
        return Double(book.currentChapterIndex) / Double(book.totalChapters)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Book cover with info button
            ZStack(alignment: .topTrailing) {
                if let coverData = book.coverImageData,
                   let nsImage = NSImage(data: coverData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                        .aspectRatio(0.7, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    // Fallback placeholder
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.6), .purple.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .aspectRatio(0.7, contentMode: .fit)
                        .overlay {
                            Image(systemName: "book.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                }

                // Info button overlay (appears on hover)
                if isHovered {
                    Button {
                        onShowDetails()
                    } label: {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                            .background(
                                Circle()
                                    .fill(.black.opacity(0.3))
                                    .padding(-6)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .help("Show book details")
                }
            }

            // Book info
            VStack(alignment: .leading, spacing: 6) {
                Text(book.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                if let author = book.author {
                    Text(author)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // Progress indicator
                if book.totalChapters > 0 {
                    HStack(spacing: 6) {
                        ProgressView(value: progressFraction)
                            .tint(.accentColor)

                        Text("\(Int(progressFraction * 100))%")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                // Stats
                if let stats = stats, stats.highlightCount > 0 {
                    HStack(spacing: 8) {
                        Label("\(stats.highlightCount)", systemImage: "highlighter")
                            .font(.caption2)
                            .foregroundStyle(.blue)

                        if stats.threadCount > 0 {
                            Label("\(stats.threadCount)", systemImage: "bubble.left.and.bubble.right")
                                .font(.caption2)
                                .foregroundStyle(.purple)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(isHovered ? Color(.controlBackgroundColor) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: isHovered ? .black.opacity(0.1) : .clear, radius: 8, x: 0, y: 4)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Filter Badge

struct FilterBadge: View {
    let text: String
    let icon: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.blue)

            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Empty State

struct EmptyLibraryView: View {
    let onAddBook: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            // Hero icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.15), Color.purple.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)

                Image(systemName: "books.vertical")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.blue, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 12) {
                Text("Welcome to Crux")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Your AI-powered reading companion")
                    .font(.system(size: 16, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            // Quick start guide
            VStack(alignment: .leading, spacing: 16) {
                QuickStartTip(
                    icon: "plus.circle.fill",
                    title: "Add your first book",
                    description: "Click below or drag an EPUB file anywhere"
                )

                QuickStartTip(
                    icon: "keyboard",
                    title: "Keyboard shortcut",
                    description: "Press ⌘O to open a book quickly",
                    accentColor: .blue
                )

                QuickStartTip(
                    icon: "sparkles",
                    title: "AI annotations",
                    description: "Highlight text to get AI-powered insights",
                    accentColor: .purple
                )
            }
            .padding(24)
            .background(Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
            )
            .frame(maxWidth: 400)

            Button(action: onAddBook) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                    Text("Add Your First Book")
                        .font(.system(size: 16, weight: .semibold))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(
                LinearGradient(
                    colors: [Color.blue, Color.purple],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Quick Start Tip Component

struct QuickStartTip: View {
    let icon: String
    let title: String
    let description: String
    var accentColor: Color = .primary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Advanced Filters Sheet

struct AdvancedFiltersSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var yearRangeMin: String
    @Binding var yearRangeMax: String
    @Binding var selectedLanguage: String?
    @Binding var selectedPublisher: String?
    @Binding var selectedSubjects: Set<String>
    @Binding var selectedTags: Set<String>

    let uniqueLanguages: [String]
    let uniquePublishers: [String]
    let allSubjects: [String]
    let allTags: [String]

    private var hasActiveFilters: Bool {
        !yearRangeMin.isEmpty ||
        !yearRangeMax.isEmpty ||
        selectedLanguage != nil ||
        selectedPublisher != nil ||
        !selectedSubjects.isEmpty ||
        !selectedTags.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                // Publication Year Range
                Section {
                    HStack {
                        TextField("Min Year", text: $yearRangeMin)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: yearRangeMin) { _, newValue in
                                yearRangeMin = newValue.filter { $0.isNumber }
                            }
                            .frame(maxWidth: .infinity)

                        Text("to")
                            .foregroundStyle(.secondary)

                        TextField("Max Year", text: $yearRangeMax)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: yearRangeMax) { _, newValue in
                                yearRangeMax = newValue.filter { $0.isNumber }
                            }
                            .frame(maxWidth: .infinity)
                    }

                    if !yearRangeMin.isEmpty || !yearRangeMax.isEmpty {
                        Button("Clear Year Range") {
                            yearRangeMin = ""
                            yearRangeMax = ""
                        }
                        .foregroundStyle(.red)
                    }
                } header: {
                    Text("Publication Year Range")
                } footer: {
                    Text("Filter books by publication year. Leave blank to include all years.")
                }

                // Language Filter
                if !uniqueLanguages.isEmpty {
                    Section("Language") {
                        Picker("Language", selection: $selectedLanguage) {
                            Text("All Languages").tag(nil as String?)
                            ForEach(uniqueLanguages, id: \.self) { language in
                                Text(language).tag(language as String?)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                // Publisher Filter
                if !uniquePublishers.isEmpty {
                    Section("Publisher") {
                        Picker("Publisher", selection: $selectedPublisher) {
                            Text("All Publishers").tag(nil as String?)
                            ForEach(uniquePublishers, id: \.self) { publisher in
                                Text(publisher).tag(publisher as String?)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                // Subjects Filter
                if !allSubjects.isEmpty {
                    Section {
                        if selectedSubjects.isEmpty {
                            Text("Select subjects to filter")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 14))
                        } else {
                            // Show selected subjects
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Selected:")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.secondary)

                                FlowLayout(spacing: 8) {
                                    ForEach(Array(selectedSubjects).sorted(), id: \.self) { subject in
                                        HStack(spacing: 4) {
                                            Text(subject)
                                                .font(.system(size: 13))
                                            Button {
                                                selectedSubjects.remove(subject)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.system(size: 14))
                                            }
                                            .buttonStyle(.plain)
                                            .foregroundStyle(.secondary)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(12)
                                    }
                                }
                            }
                            .padding(.vertical, 4)

                            Button("Clear All Subjects") {
                                selectedSubjects.removeAll()
                            }
                            .foregroundStyle(.red)
                        }

                        Divider()

                        // Available subjects
                        ForEach(allSubjects, id: \.self) { subject in
                            Button {
                                if selectedSubjects.contains(subject) {
                                    selectedSubjects.remove(subject)
                                } else {
                                    selectedSubjects.insert(subject)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: selectedSubjects.contains(subject) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedSubjects.contains(subject) ? .blue : .secondary)
                                    Text(subject)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Subjects")
                    } footer: {
                        Text("Select one or more subjects. Books matching any selected subject will be shown.")
                    }
                }

                // Tags Filter
                if !allTags.isEmpty {
                    Section {
                        if selectedTags.isEmpty {
                            Text("Select tags to filter")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 14))
                        } else {
                            // Show selected tags
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Selected:")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.secondary)

                                FlowLayout(spacing: 8) {
                                    ForEach(Array(selectedTags).sorted(), id: \.self) { tag in
                                        HStack(spacing: 4) {
                                            Text(tag)
                                                .font(.system(size: 13))
                                            Button {
                                                selectedTags.remove(tag)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.system(size: 14))
                                            }
                                            .buttonStyle(.plain)
                                            .foregroundStyle(.secondary)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.purple.opacity(0.1))
                                        .cornerRadius(12)
                                    }
                                }
                            }
                            .padding(.vertical, 4)

                            Button("Clear All Tags") {
                                selectedTags.removeAll()
                            }
                            .foregroundStyle(.red)
                        }

                        Divider()

                        // Available tags
                        ForEach(allTags, id: \.self) { tag in
                            Button {
                                if selectedTags.contains(tag) {
                                    selectedTags.remove(tag)
                                } else {
                                    selectedTags.insert(tag)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: selectedTags.contains(tag) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedTags.contains(tag) ? .purple : .secondary)
                                    Text(tag)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Tags")
                    } footer: {
                        Text("Select one or more tags. Books matching any selected tag will be shown.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Advanced Filters")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                if hasActiveFilters {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Clear All") {
                            yearRangeMin = ""
                            yearRangeMax = ""
                            selectedLanguage = nil
                            selectedPublisher = nil
                            selectedSubjects.removeAll()
                            selectedTags.removeAll()
                        }
                        .foregroundStyle(.red)
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 600)
        #endif
    }
}

// MARK: - Restore Strategy Picker Sheet

struct RestoreStrategyPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedStrategy: LibraryBackupService.MergeStrategy
    let onRestore: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Choose how to handle books that already exist in your library:")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14))
                }

                Section {
                    Button {
                        selectedStrategy = .skip
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: selectedStrategy == .skip ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedStrategy == .skip ? .blue : .secondary)
                                    Text("Skip Existing")
                                        .foregroundStyle(.primary)
                                }
                                Text("Keep current library data, only add new books")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        selectedStrategy = .overwrite
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: selectedStrategy == .overwrite ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedStrategy == .overwrite ? .blue : .secondary)
                                    Text("Overwrite All")
                                        .foregroundStyle(.primary)
                                }
                                Text("Replace existing books with backup data")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        selectedStrategy = .keepNewer
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: selectedStrategy == .keepNewer ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedStrategy == .keepNewer ? .blue : .secondary)
                                    Text("Keep Newer")
                                        .foregroundStyle(.primary)
                                }
                                Text("Compare dates and keep the more recent version")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Merge Strategy")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.blue)
                            Text("Recommendation")
                                .fontWeight(.medium)
                        }
                        .font(.system(size: 13))

                        Text("Use **Skip Existing** for regular backups. Use **Keep Newer** when merging libraries from multiple devices. Use **Overwrite All** only if you want to completely replace your current library.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Restore Library")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Restore") {
                        dismiss()
                        onRestore()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 450)
        #endif
    }
}

#Preview {
    LibraryMainView(
        storedBooks: [],
        onSelectBook: { _ in },
        onAddBook: {},
        onDeleteBook: { _ in },
        onImportBook: { _ in }
    )
    .modelContainer(for: StoredBook.self, inMemory: true)
}
