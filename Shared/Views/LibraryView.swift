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

struct LibraryMainView: View {
    let storedBooks: [StoredBook]
    let onSelectBook: (UUID) -> Void
    let onAddBook: () -> Void
    let onDeleteBook: (StoredBook) -> Void

    @State private var searchQuery = ""
    @State private var annotationStats: [UUID: AnnotationStats] = [:]
    @State private var sortOption: LibrarySortOption = .lastRead
    @State private var sortAscending = false
    @State private var viewMode: LibraryViewMode = .list

    // Book details state
    @State private var detailsBookId: UUID?
    @State private var detailsBook: Book?
    @State private var detailsStoredBook: StoredBook?
    @State private var isLoadingDetails = false
    @State private var showingBookDetails = false

    private let parser = EPUBParser()
    private let storage = BookStorage.shared

    private var recentBooks: [StoredBook] {
        storedBooks
            .filter { $0.lastOpenedAt != nil && !$0.isFinished }
            .sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
            .prefix(5)
            .map { $0 }
    }

    private var sortedAndFilteredBooks: [StoredBook] {
        let filtered: [StoredBook]
        if searchQuery.isEmpty {
            filtered = storedBooks
        } else {
            let query = searchQuery.lowercased()
            filtered = storedBooks.filter { book in
                book.title.lowercased().contains(query) ||
                (book.author?.lowercased().contains(query) ?? false) ||
                book.subjects.contains { $0.lowercased().contains(query) }
            }
        }

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
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
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

            // Add book button
            Button(action: onAddBook) {
                Label("Add Book", systemImage: "plus")
            }
        }
    }

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
            ContentUnavailableView.search(text: searchQuery)
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

                // Main library view
                if viewMode == .list {
                    BookListView(
                        books: sortedAndFilteredBooks,
                        annotationStats: annotationStats,
                        onSelectBook: onSelectBook,
                        onShowDetails: { bookId in
                            detailsBookId = bookId
                        },
                        onDeleteBook: onDeleteBook
                    )
                } else {
                    BookGridView(
                        books: sortedAndFilteredBooks,
                        annotationStats: annotationStats,
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
        }
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
    let annotationStats: [UUID: AnnotationStats]
    let onSelectBook: (UUID) -> Void
    let onShowDetails: (UUID) -> Void
    let onDeleteBook: (StoredBook) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(books) { book in
                    BookListRow(
                        book: book,
                        stats: annotationStats[book.id],
                        onShowDetails: {
                            onShowDetails(book.id)
                        }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onSelectBook(book.id)
                    }
                    .contextMenu {
                        Button {
                            onShowDetails(book.id)
                        } label: {
                            Label("Show Details", systemImage: "info.circle")
                        }

                        Button(role: .destructive) {
                            onDeleteBook(book)
                        } label: {
                            Label("Remove from Library", systemImage: "trash")
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
    let annotationStats: [UUID: AnnotationStats]
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
                    BookGridCard(
                        book: book,
                        stats: annotationStats[book.id],
                        onShowDetails: {
                            onShowDetails(book.id)
                        }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onSelectBook(book.id)
                    }
                    .contextMenu {
                        Button {
                            onShowDetails(book.id)
                        } label: {
                            Label("Show Details", systemImage: "info.circle")
                        }

                        Button(role: .destructive) {
                            onDeleteBook(book)
                        } label: {
                            Label("Remove from Library", systemImage: "trash")
                        }
                    }
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity)
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
            // Book cover placeholder with info button
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.6), .purple.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .aspectRatio(0.7, contentMode: .fit)

                Image(systemName: "book.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.white.opacity(0.8))

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

// MARK: - Empty State

struct EmptyLibraryView: View {
    let onAddBook: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Your library is empty")
                    .font(.system(size: 20, weight: .medium, design: .serif))
                    .foregroundStyle(.primary)

                Text("Add an EPUB to start reading")
                    .font(.system(size: 15, design: .serif))
                    .foregroundStyle(.secondary)
            }

            Button(action: onAddBook) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Add Book")
                        .font(.system(size: 14, weight: .medium))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.primary.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    LibraryMainView(
        storedBooks: [],
        onSelectBook: { _ in },
        onAddBook: {},
        onDeleteBook: { _ in }
    )
    .modelContainer(for: StoredBook.self, inMemory: true)
}
