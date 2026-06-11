import Foundation
import SwiftData

enum ReadingStatus: String, Codable {
    case wantToRead = "Want to Read"
    case reading = "Reading"
    case finished = "Finished"

    var systemImage: String {
        switch self {
        case .wantToRead: return "book.closed"
        case .reading: return "book"
        case .finished: return "checkmark.circle.fill"
        }
    }

    var color: String {
        switch self {
        case .wantToRead: return "systemGray"
        case .reading: return "systemBlue"
        case .finished: return "systemGreen"
        }
    }
}

@Model
final class StoredBook {
    @Attribute(.unique) var id: UUID
    var title: String
    var author: String?
    var addedAt: Date
    var lastOpenedAt: Date?

    // Reading progress
    var currentChapterIndex: Int
    var totalChapters: Int
    var isFinished: Bool
    var readingStatusRaw: String = ReadingStatus.wantToRead.rawValue  // Backing property for SwiftData
    var scrollPosition: Double = 0  // 0.0-1.0 percentage within chapter

    /// Most recent CFI within the current chapter (EPUB Canonical Fragment
    /// Identifier). When set, the reader uses it to restore the user to
    /// the exact element they were on, not just a chapter-level
    /// `scrollPosition` approximation. Empty string means "no CFI cached
    /// yet — fall back to scrollPosition".
    var lastReadingCFI: String = ""

    /// Cached estimated reading time, in whole minutes, at the default
    /// reading speed (220 wpm). 0 means "not computed yet" — the field
    /// is populated during book import, and lazily on first reader
    /// open for books imported before this field existed.
    var cachedReadingMinutes: Int = 0

    var readingStatus: ReadingStatus {
        get { ReadingStatus(rawValue: readingStatusRaw) ?? .wantToRead }
        set { readingStatusRaw = newValue.rawValue }
    }

    // Cached metadata
    var language: String?
    var publisher: String?
    var bookDescription: String?
    var publicationYear: Int?
    var subjectsJSON: String?  // JSON-encoded [String] array
    var coverImageData: Data?  // Cached cover image
    var tagsJSON: String?  // JSON-encoded [String] array for flexible organization

    // Collections relationship
    @Relationship(deleteRule: .nullify, inverse: \BookCollection.books)
    var collections: [BookCollection]? = []

    var subjects: [String] {
        guard let json = subjectsJSON,
              let data = json.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return arr
    }

    var tags: [String] {
        guard let json = tagsJSON,
              let data = json.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return arr
    }

    func setTags(_ newTags: [String]) {
        let trimmedTags = newTags.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !trimmedTags.isEmpty,
           let jsonData = try? JSONEncoder().encode(trimmedTags) {
            tagsJSON = String(data: jsonData, encoding: .utf8)
        } else {
            tagsJSON = nil
        }
    }

    init(
        id: UUID,
        title: String,
        author: String? = nil,
        addedAt: Date = Date(),
        currentChapterIndex: Int = 0,
        totalChapters: Int = 0
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.addedAt = addedAt
        self.lastOpenedAt = nil
        self.currentChapterIndex = currentChapterIndex
        self.totalChapters = totalChapters
        self.isFinished = false
        self.scrollPosition = 0
    }

    var progress: Double {
        guard totalChapters > 0 else { return 0 }
        return Double(currentChapterIndex) / Double(totalChapters)
    }

    func markOpened() {
        lastOpenedAt = Date()
        // Auto-update reading status to "reading" when book is opened
        if readingStatus == .wantToRead {
            readingStatus = .reading
        }
    }

    func updateProgress(chapter: Int, total: Int, scroll: Double = 0) {
        currentChapterIndex = chapter
        totalChapters = total
        scrollPosition = scroll
        if chapter >= total - 1 && scroll > 0.9 {
            isFinished = true
            readingStatus = .finished
        } else if readingStatus == .wantToRead {
            readingStatus = .reading
        }
    }
}

@Model
final class BookCollection {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorHex: String  // Hex color for visual distinction
    var icon: String  // SF Symbol name
    var createdAt: Date
    var sortOrder: Int  // For custom ordering

    @Relationship(deleteRule: .nullify)
    var books: [StoredBook]? = []

    var bookCount: Int {
        books?.count ?? 0
    }

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = "007AFF",  // Default blue
        icon: String = "folder.fill",
        createdAt: Date = Date(),
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.icon = icon
        self.createdAt = createdAt
        self.sortOrder = sortOrder
    }
}
