import Foundation
import SwiftData

/// Service for managing and organizing annotation tags
@Observable
class TagManagementService {
    private var modelContext: ModelContext?

    /// Recently used tags for quick access
    private(set) var recentTags: [String] = []

    /// All unique tags across all annotations in the library
    private(set) var allTags: [String] = []

    /// Configure the service with a model context
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        updateTagCache()
    }

    /// Extract all unique tags from book annotations
    func updateTagCache() {
        guard let modelContext = modelContext else { return }

        let storage = BookStorage.shared

        // Fetch all stored books
        let descriptor = FetchDescriptor<StoredBook>()
        guard let books = try? modelContext.fetch(descriptor) else { return }

        // Extract tags from each book's annotations
        Task {
            var tagSet = Set<String>()

            for book in books {
                if let annotations = try? await storage.loadAnnotations(for: book.id) {
                    // Collect tags from highlights
                    for highlight in annotations.highlights {
                        tagSet.formUnion(highlight.tags)
                    }

                    // Collect tags from bookmarks
                    for bookmark in annotations.bookmarks {
                        tagSet.formUnion(bookmark.tags)
                    }
                }
            }

            await MainActor.run {
                allTags = tagSet.sorted()
            }
        }
    }

    /// Get tags for a specific book
    func getTags(forBookId bookId: UUID) async -> Set<String> {
        let storage = BookStorage.shared
        guard let annotations = try? await storage.loadAnnotations(for: bookId) else {
            return []
        }

        var tags = Set<String>()
        for highlight in annotations.highlights {
            tags.formUnion(highlight.tags)
        }
        for bookmark in annotations.bookmarks {
            tags.formUnion(bookmark.tags)
        }

        return tags
    }

    /// Add a tag to recent tags list
    func markTagAsUsed(_ tag: String) {
        // Remove if already exists
        recentTags.removeAll { $0 == tag }

        // Add to front
        recentTags.insert(tag, at: 0)

        // Keep only 10 most recent
        if recentTags.count > 10 {
            recentTags = Array(recentTags.prefix(10))
        }
    }

    /// Get suggested tags based on partial input
    func suggestTags(matching query: String) -> [String] {
        let lowercaseQuery = query.lowercased()

        if lowercaseQuery.isEmpty {
            return Array(recentTags.prefix(5))
        }

        // Filter tags that contain the query
        let matches = allTags.filter { $0.lowercased().contains(lowercaseQuery) }

        // Sort by: exact match first, then starts with, then contains
        return matches.sorted { lhs, rhs in
            let lhsLower = lhs.lowercased()
            let rhsLower = rhs.lowercased()

            if lhsLower == lowercaseQuery { return true }
            if rhsLower == lowercaseQuery { return false }

            if lhsLower.hasPrefix(lowercaseQuery) && !rhsLower.hasPrefix(lowercaseQuery) {
                return true
            }
            if !lhsLower.hasPrefix(lowercaseQuery) && rhsLower.hasPrefix(lowercaseQuery) {
                return false
            }

            return lhs < rhs
        }
    }

    /// Get category statistics for a book
    func getCategoryStats(forBookId bookId: UUID) async -> [AnnotationCategory: Int] {
        let storage = BookStorage.shared
        guard let annotations = try? await storage.loadAnnotations(for: bookId) else {
            return [:]
        }

        var stats: [AnnotationCategory: Int] = [:]

        for highlight in annotations.highlights {
            stats[highlight.category, default: 0] += 1
        }

        for bookmark in annotations.bookmarks {
            stats[bookmark.category, default: 0] += 1
        }

        return stats
    }

    /// Get tag statistics for a book
    func getTagStats(forBookId bookId: UUID) async -> [String: Int] {
        let storage = BookStorage.shared
        guard let annotations = try? await storage.loadAnnotations(for: bookId) else {
            return [:]
        }

        var stats: [String: Int] = [:]

        for highlight in annotations.highlights {
            for tag in highlight.tags {
                stats[tag, default: 0] += 1
            }
        }

        for bookmark in annotations.bookmarks {
            for tag in bookmark.tags {
                stats[tag, default: 0] += 1
            }
        }

        return stats
    }

    /// Normalize tag format (lowercase, trim whitespace)
    func normalizeTag(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    /// Validate tag format
    func isValidTag(_ tag: String) -> Bool {
        let normalized = normalizeTag(tag)
        return !normalized.isEmpty && normalized.count <= 50
    }
}
