import Foundation
import SwiftUI
import SwiftData
import Observation

/// ViewModel for managing the notes/highlights view
@MainActor
@Observable
final class NotesViewModel {
    // MARK: - Properties

    /// All highlights from all books
    private(set) var allHighlights: [HighlightWithBookInfo] = []

    /// Filtered highlights based on current search and filter settings
    private(set) var filteredHighlights: [HighlightWithBookInfo] = []

    /// Current search text
    var searchText: String = "" {
        didSet {
            applyFiltersAndSort()
        }
    }

    /// Current filter option
    var filterOption: FilterOption = .all {
        didSet {
            applyFiltersAndSort()
        }
    }

    /// Current sort option
    var sortOption: SortOption = .dateDescending {
        didSet {
            applyFiltersAndSort()
        }
    }

    /// Loading state
    private(set) var isLoading = false

    /// Error state
    var error: Error?

    private let storage = BookStorage.shared
    private var modelContext: ModelContext?

    // MARK: - Filter and Sort Options

    enum FilterOption: String, CaseIterable, Identifiable {
        case all = "All"
        case withThreads = "With Threads"
        case withoutThreads = "Without Threads"
        case withAnnotations = "With Notes"

        var id: String { rawValue }
    }

    enum SortOption: String, CaseIterable, Identifiable {
        case dateDescending = "Newest First"
        case dateAscending = "Oldest First"
        case bookTitle = "Book Title"
        case textLength = "Text Length"

        var id: String { rawValue }
    }

    // MARK: - Initialization

    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
        if modelContext != nil {
            Task {
                await loadHighlights()
            }
        }
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        Task {
            await loadHighlights()
        }
    }

    // MARK: - Data Loading

    /// Load all highlights from all books
    func loadHighlights() async {
        guard let modelContext = modelContext else { return }

        isLoading = true
        error = nil

        do {
            // Query all stored books from SwiftData
            let descriptor = FetchDescriptor<StoredBook>()
            let books = try modelContext.fetch(descriptor)

            var highlights: [HighlightWithBookInfo] = []

            for book in books {
                // Load annotations for each book
                do {
                    let annotations = try await storage.loadAnnotations(for: book.id)

                    // Convert highlights to HighlightWithBookInfo
                    let bookHighlights = annotations.highlights.map { highlight in
                        HighlightWithBookInfo(
                            highlight: highlight,
                            bookId: book.id,
                            bookTitle: book.title,
                            bookAuthor: book.author ?? "Unknown Author"
                        )
                    }
                    highlights.append(contentsOf: bookHighlights)
                } catch {
                    // Skip books with no annotations
                    continue
                }
            }

            allHighlights = highlights
            applyFiltersAndSort()
            isLoading = false
        } catch {
            self.error = error
            isLoading = false
        }
    }

    /// Reload highlights (e.g., after making changes)
    func reload() async {
        await loadHighlights()
    }

    // MARK: - Filtering and Sorting

    private func applyFiltersAndSort() {
        var highlights = allHighlights

        // Apply search filter — covers highlight text, the user's own
        // note, book metadata, and the contents of every AI thread
        // message. The last one means a thread that discussed "kenosis"
        // surfaces even when that word doesn't appear in the original
        // passage.
        if !searchText.isEmpty {
            let needle = searchText
            highlights = highlights.filter { item in
                if item.highlight.selectedText.localizedCaseInsensitiveContains(needle) { return true }
                if item.highlight.annotation?.localizedCaseInsensitiveContains(needle) == true { return true }
                if item.bookTitle.localizedCaseInsensitiveContains(needle) { return true }
                if item.bookAuthor.localizedCaseInsensitiveContains(needle) { return true }
                // Search inside AI thread messages too.
                for thread in item.highlight.threads {
                    for message in thread.messages {
                        if message.content.localizedCaseInsensitiveContains(needle) {
                            return true
                        }
                    }
                }
                return false
            }
        }

        // Apply category filter
        switch filterOption {
        case .all:
            break // No additional filtering
        case .withThreads:
            highlights = highlights.filter { !$0.highlight.threads.isEmpty }
        case .withoutThreads:
            highlights = highlights.filter { $0.highlight.threads.isEmpty }
        case .withAnnotations:
            highlights = highlights.filter { $0.highlight.annotation != nil && !$0.highlight.annotation!.isEmpty }
        }

        // Apply sorting
        switch sortOption {
        case .dateDescending:
            highlights.sort { $0.highlight.createdAt > $1.highlight.createdAt }
        case .dateAscending:
            highlights.sort { $0.highlight.createdAt < $1.highlight.createdAt }
        case .bookTitle:
            highlights.sort {
                if $0.bookTitle == $1.bookTitle {
                    return $0.highlight.createdAt > $1.highlight.createdAt
                }
                return $0.bookTitle < $1.bookTitle
            }
        case .textLength:
            highlights.sort { $0.highlight.selectedText.count > $1.highlight.selectedText.count }
        }

        filteredHighlights = highlights
    }

    // MARK: - Highlight Operations

    /// Delete a highlight
    func deleteHighlight(_ item: HighlightWithBookInfo) async throws {
        // Load the book's annotations
        var annotations = try await storage.loadAnnotations(for: item.bookId)

        // Remove the highlight
        annotations.removeHighlight(id: item.highlight.id)

        // Save annotations
        try await storage.saveAnnotations(annotations)

        // Reload highlights
        await loadHighlights()
    }

    /// Update highlight annotation
    func updateAnnotation(for item: HighlightWithBookInfo, annotation: String) async throws {
        // Load the book's annotations
        var annotations = try await storage.loadAnnotations(for: item.bookId)

        // Find and update the highlight
        if let index = annotations.highlights.firstIndex(where: { $0.id == item.highlight.id }) {
            annotations.highlights[index].annotation = annotation
            annotations.highlights[index].updatedAt = Date()
        }

        // Save annotations
        try await storage.saveAnnotations(annotations)

        // Reload highlights
        await loadHighlights()
    }

    /// Delete a thread from a highlight
    func deleteThread(threadId: UUID, from item: HighlightWithBookInfo) async throws {
        // Load the book's annotations
        var annotations = try await storage.loadAnnotations(for: item.bookId)

        // Find and update the highlight
        if let index = annotations.highlights.firstIndex(where: { $0.id == item.highlight.id }) {
            annotations.highlights[index].threads.removeAll { $0.id == threadId }
        }

        // Save annotations
        try await storage.saveAnnotations(annotations)

        // Reload highlights
        await loadHighlights()
    }

    // MARK: - Statistics

    var totalHighlights: Int {
        allHighlights.count
    }

    var highlightsWithThreads: Int {
        allHighlights.filter { !$0.highlight.threads.isEmpty }.count
    }

    var highlightsWithAnnotations: Int {
        allHighlights.filter { $0.highlight.annotation != nil && !$0.highlight.annotation!.isEmpty }.count
    }

    var totalThreadMessages: Int {
        allHighlights.reduce(0) { total, item in
            total + item.highlight.threads.reduce(0) { $0 + $1.messages.count }
        }
    }
}
