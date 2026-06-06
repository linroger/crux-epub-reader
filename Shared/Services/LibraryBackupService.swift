import Foundation
import SwiftData
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// Service for backing up and restoring the entire library
@MainActor
final class LibraryBackupService {
    static let shared = LibraryBackupService()

    private init() {}

    // MARK: - Backup Data Models

    struct LibraryBackup: Codable {
        let version: String = "1.0"
        let exportDate: Date
        let books: [BookBackupData]
        let collections: [CollectionBackupData]

        struct BookBackupData: Codable {
            let id: String
            let title: String
            let author: String?
            let addedAt: Date
            let lastOpenedAt: Date?
            let currentChapterIndex: Int
            let totalChapters: Int
            let isFinished: Bool
            let readingStatusRaw: String
            let scrollPosition: Double
            let language: String?
            let publisher: String?
            let bookDescription: String?
            let publicationYear: Int?
            let subjectsJSON: String?
            let tagsJSON: String?
            let collectionIds: [String]
        }

        struct CollectionBackupData: Codable {
            let id: String
            let name: String
            let colorHex: String
            let icon: String
            let createdAt: Date
            let sortOrder: Int
        }
    }

    // MARK: - Export Methods

    /// Create a backup of the entire library
    /// - Parameters:
    ///   - books: Array of StoredBook objects to backup
    ///   - collections: Array of BookCollection objects to backup
    /// - Returns: JSON data containing the library backup
    func createBackup(books: [StoredBook], collections: [BookCollection]) throws -> Data {
        // Convert books to backup data
        let bookBackups = books.map { book in
            LibraryBackup.BookBackupData(
                id: book.id.uuidString,
                title: book.title,
                author: book.author,
                addedAt: book.addedAt,
                lastOpenedAt: book.lastOpenedAt,
                currentChapterIndex: book.currentChapterIndex,
                totalChapters: book.totalChapters,
                isFinished: book.isFinished,
                readingStatusRaw: book.readingStatusRaw,
                scrollPosition: book.scrollPosition,
                language: book.language,
                publisher: book.publisher,
                bookDescription: book.bookDescription,
                publicationYear: book.publicationYear,
                subjectsJSON: book.subjectsJSON,
                tagsJSON: book.tagsJSON,
                collectionIds: (book.collections ?? []).map { $0.id.uuidString }
            )
        }

        // Convert collections to backup data
        let collectionBackups = collections.map { collection in
            LibraryBackup.CollectionBackupData(
                id: collection.id.uuidString,
                name: collection.name,
                colorHex: collection.colorHex,
                icon: collection.icon,
                createdAt: collection.createdAt,
                sortOrder: collection.sortOrder
            )
        }

        let backup = LibraryBackup(
            exportDate: Date(),
            books: bookBackups,
            collections: collectionBackups
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    /// Export library backup to a file
    /// - Parameters:
    ///   - books: Array of StoredBook objects to backup
    ///   - collections: Array of BookCollection objects to backup
    ///   - suggestedFilename: Optional custom filename
    /// - Returns: URL of the saved backup file, or nil if cancelled
    #if os(macOS)
    func exportBackupToFile(
        books: [StoredBook],
        collections: [BookCollection],
        suggestedFilename: String = "CruxLibraryBackup"
    ) async throws -> URL? {
        let backupData = try createBackup(books: books, collections: collections)

        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = suggestedFilename + "_\(formatDateForFilename(Date())).json"
        savePanel.allowedContentTypes = [.json]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false

        let response = await savePanel.begin()

        guard response == .OK, let url = savePanel.url else {
            return nil
        }

        try backupData.write(to: url)
        return url
    }
    #endif

    // MARK: - Import Methods

    /// Restore library from backup data
    /// - Parameters:
    ///   - data: JSON backup data
    ///   - modelContext: SwiftData model context
    ///   - mergeStrategy: How to handle existing books
    /// - Returns: Import statistics
    func restoreFromBackup(
        data: Data,
        modelContext: ModelContext,
        mergeStrategy: MergeStrategy = .skip
    ) throws -> ImportStats {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(LibraryBackup.self, from: data)

        var stats = ImportStats()

        // First, restore collections (books reference them)
        var collectionMap: [String: BookCollection] = [:]

        for collectionData in backup.collections {
            guard let uuid = UUID(uuidString: collectionData.id) else { continue }

            // Check if collection already exists
            let descriptor = FetchDescriptor<BookCollection>(
                predicate: #Predicate<BookCollection> { $0.id == uuid }
            )
            let existing = try? modelContext.fetch(descriptor).first

            if let existing = existing {
                // Update existing collection
                existing.name = collectionData.name
                existing.colorHex = collectionData.colorHex
                existing.icon = collectionData.icon
                existing.sortOrder = collectionData.sortOrder
                collectionMap[collectionData.id] = existing
                stats.collectionsUpdated += 1
            } else {
                // Create new collection
                let collection = BookCollection(
                    id: uuid,
                    name: collectionData.name,
                    colorHex: collectionData.colorHex,
                    icon: collectionData.icon,
                    createdAt: collectionData.createdAt,
                    sortOrder: collectionData.sortOrder
                )
                modelContext.insert(collection)
                collectionMap[collectionData.id] = collection
                stats.collectionsCreated += 1
            }
        }

        // Restore books
        for bookData in backup.books {
            guard let uuid = UUID(uuidString: bookData.id) else { continue }

            // Check if book already exists
            let descriptor = FetchDescriptor<StoredBook>(
                predicate: #Predicate<StoredBook> { $0.id == uuid }
            )
            let existing = try? modelContext.fetch(descriptor).first

            if let existing = existing {
                switch mergeStrategy {
                case .skip:
                    stats.booksSkipped += 1
                    continue
                case .overwrite:
                    // Update existing book
                    updateBookFromBackup(existing, from: bookData, collectionMap: collectionMap)
                    stats.booksUpdated += 1
                case .keepNewer:
                    // Only update if backup is newer
                    if bookData.lastOpenedAt ?? bookData.addedAt > existing.lastOpenedAt ?? existing.addedAt {
                        updateBookFromBackup(existing, from: bookData, collectionMap: collectionMap)
                        stats.booksUpdated += 1
                    } else {
                        stats.booksSkipped += 1
                    }
                }
            } else {
                // Create new book. `uuid` was already validated above, so
                // pass it through rather than re-parsing (and never crash on
                // untrusted backup contents).
                let book = createBookFromBackup(bookData, id: uuid, collectionMap: collectionMap)
                modelContext.insert(book)
                stats.booksCreated += 1
            }
        }

        try modelContext.save()
        return stats
    }

    #if os(macOS)
    /// Import library backup from a file
    /// - Parameters:
    ///   - modelContext: SwiftData model context
    ///   - mergeStrategy: How to handle existing books
    /// - Returns: Import statistics, or nil if cancelled
    func importBackupFromFile(
        modelContext: ModelContext,
        mergeStrategy: MergeStrategy = .skip
    ) async throws -> ImportStats? {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false

        let response = await openPanel.begin()

        guard response == .OK, let url = openPanel.url else {
            return nil
        }

        let data = try Data(contentsOf: url)
        return try restoreFromBackup(data: data, modelContext: modelContext, mergeStrategy: mergeStrategy)
    }
    #endif

    // MARK: - Helper Methods

    private func updateBookFromBackup(
        _ book: StoredBook,
        from backupData: LibraryBackup.BookBackupData,
        collectionMap: [String: BookCollection]
    ) {
        book.title = backupData.title
        book.author = backupData.author
        book.lastOpenedAt = backupData.lastOpenedAt
        book.currentChapterIndex = backupData.currentChapterIndex
        book.totalChapters = backupData.totalChapters
        book.isFinished = backupData.isFinished
        book.readingStatusRaw = backupData.readingStatusRaw
        book.scrollPosition = backupData.scrollPosition
        book.language = backupData.language
        book.publisher = backupData.publisher
        book.bookDescription = backupData.bookDescription
        book.publicationYear = backupData.publicationYear
        book.subjectsJSON = backupData.subjectsJSON
        book.tagsJSON = backupData.tagsJSON

        // Update collections
        book.collections = backupData.collectionIds.compactMap { collectionMap[$0] }
    }

    private func createBookFromBackup(
        _ backupData: LibraryBackup.BookBackupData,
        id uuid: UUID,
        collectionMap: [String: BookCollection]
    ) -> StoredBook {
        let book = StoredBook(
            id: uuid,
            title: backupData.title,
            author: backupData.author,
            addedAt: backupData.addedAt,
            currentChapterIndex: backupData.currentChapterIndex,
            totalChapters: backupData.totalChapters
        )

        book.lastOpenedAt = backupData.lastOpenedAt
        book.isFinished = backupData.isFinished
        book.readingStatusRaw = backupData.readingStatusRaw
        book.scrollPosition = backupData.scrollPosition
        book.language = backupData.language
        book.publisher = backupData.publisher
        book.bookDescription = backupData.bookDescription
        book.publicationYear = backupData.publicationYear
        book.subjectsJSON = backupData.subjectsJSON
        book.tagsJSON = backupData.tagsJSON

        // Assign collections
        book.collections = backupData.collectionIds.compactMap { collectionMap[$0] }

        return book
    }

    private func formatDateForFilename(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: date)
    }

    // MARK: - Supporting Types

    enum MergeStrategy {
        case skip          // Skip existing books
        case overwrite     // Overwrite existing books with backup data
        case keepNewer     // Keep whichever is newer based on lastOpenedAt
    }

    struct ImportStats {
        var booksCreated = 0
        var booksUpdated = 0
        var booksSkipped = 0
        var collectionsCreated = 0
        var collectionsUpdated = 0

        var totalBooks: Int {
            booksCreated + booksUpdated + booksSkipped
        }

        var totalCollections: Int {
            collectionsCreated + collectionsUpdated
        }
    }
}
