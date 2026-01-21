import Foundation
import SwiftData

/// A saved search query with timestamp
@Model
final class SearchHistoryItem {
    var id: UUID
    var query: String
    var timestamp: Date
    var bookId: UUID?
    var resultCount: Int

    init(query: String, bookId: UUID? = nil, resultCount: Int = 0) {
        self.id = UUID()
        self.query = query
        self.timestamp = Date()
        self.bookId = bookId
        self.resultCount = resultCount
    }
}

/// Service for managing search history
@Observable
class SearchHistoryService {
    private let maxHistoryItems = 50
    private var modelContext: ModelContext?

    var recentSearches: [SearchHistoryItem] = []

    init() {}

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadRecentSearches()
    }

    /// Add a search to history (or update if it exists)
    func addSearch(query: String, bookId: UUID? = nil, resultCount: Int = 0) {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty,
              let context = modelContext else { return }

        // Check if this exact query already exists for this book
        let descriptor = FetchDescriptor<SearchHistoryItem>(
            predicate: #Predicate { item in
                item.query == query && item.bookId == bookId
            }
        )

        if let existingItems = try? context.fetch(descriptor), !existingItems.isEmpty {
            // Update timestamp and result count of existing item
            existingItems.first?.timestamp = Date()
            existingItems.first?.resultCount = resultCount
        } else {
            // Create new item
            let item = SearchHistoryItem(query: query, bookId: bookId, resultCount: resultCount)
            context.insert(item)
        }

        try? context.save()
        pruneOldItems()
        loadRecentSearches()
    }

    /// Get recent searches, optionally filtered by book
    func getRecentSearches(forBookId bookId: UUID? = nil, limit: Int = 10) -> [SearchHistoryItem] {
        guard let context = modelContext else { return [] }

        var descriptor: FetchDescriptor<SearchHistoryItem>

        if let bookId = bookId {
            descriptor = FetchDescriptor<SearchHistoryItem>(
                predicate: #Predicate { item in
                    item.bookId == bookId
                },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor<SearchHistoryItem>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
        }

        descriptor.fetchLimit = limit

        return (try? context.fetch(descriptor)) ?? []
    }

    /// Delete a specific search history item
    func deleteSearch(_ item: SearchHistoryItem) {
        guard let context = modelContext else { return }
        context.delete(item)
        try? context.save()
        loadRecentSearches()
    }

    /// Clear all search history
    func clearAll() {
        guard let context = modelContext else { return }

        let descriptor = FetchDescriptor<SearchHistoryItem>()
        if let allItems = try? context.fetch(descriptor) {
            allItems.forEach { context.delete($0) }
            try? context.save()
        }

        loadRecentSearches()
    }

    /// Clear search history for a specific book
    func clearHistory(forBookId bookId: UUID) {
        guard let context = modelContext else { return }

        let descriptor = FetchDescriptor<SearchHistoryItem>(
            predicate: #Predicate { item in
                item.bookId == bookId
            }
        )

        if let items = try? context.fetch(descriptor) {
            items.forEach { context.delete($0) }
            try? context.save()
        }

        loadRecentSearches()
    }

    // MARK: - Private

    private func loadRecentSearches() {
        recentSearches = getRecentSearches(limit: 10)
    }

    private func pruneOldItems() {
        guard let context = modelContext else { return }

        let descriptor = FetchDescriptor<SearchHistoryItem>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        guard let allItems = try? context.fetch(descriptor),
              allItems.count > maxHistoryItems else { return }

        // Delete oldest items beyond the limit
        let itemsToDelete = allItems.dropFirst(maxHistoryItems)
        itemsToDelete.forEach { context.delete($0) }
        try? context.save()
    }
}
