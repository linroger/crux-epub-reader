import Foundation

/// Category for organizing annotations
enum AnnotationCategory: String, Codable, CaseIterable, Identifiable {
    case quote = "Quote"
    case analysis = "Analysis"
    case question = "Question"
    case important = "Important"
    case reference = "Reference"
    case definition = "Definition"
    case example = "Example"
    case personal = "Personal Note"
    case other = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .quote: return "quote.bubble"
        case .analysis: return "brain.head.profile"
        case .question: return "questionmark.circle"
        case .important: return "star.fill"
        case .reference: return "link"
        case .definition: return "book.closed"
        case .example: return "lightbulb"
        case .personal: return "person.fill"
        case .other: return "tag"
        }
    }

    var color: String {
        switch self {
        case .quote: return "#3B82F6"  // blue
        case .analysis: return "#8B5CF6"  // purple
        case .question: return "#F59E0B"  // amber
        case .important: return "#EF4444"  // red
        case .reference: return "#10B981"  // green
        case .definition: return "#06B6D4"  // cyan
        case .example: return "#F97316"  // orange
        case .personal: return "#EC4899"  // pink
        case .other: return "#6B7280"  // gray
        }
    }
}

/// Represents a CFI (Canonical Fragment Identifier) range within a chapter
/// CFI is the EPUB standard for referencing locations in content documents
struct CFIRange: Codable, Equatable {
    /// DOM path to start container (e.g., "/4/2/1")
    let startPath: String
    /// Character offset within start text node
    let startOffset: Int
    /// DOM path to end container
    let endPath: String
    /// Character offset within end text node
    let endOffset: Int

    /// Combined CFI string representation
    var cfiString: String {
        "\(startPath):\(startOffset),\(endPath):\(endOffset)"
    }
}

/// Data from a text selection in the WebView
struct SelectionData: Equatable {
    let text: String
    let cfiRange: CFIRange
    let context: String
    /// Source strings (inline `data:` URIs or absolute URLs) for images
    /// near the selection, captured so vision-capable models can analyze
    /// the figure a passage refers to. Empty for text-only selections.
    var images: [String] = []
}

/// Action from a margin note in the WebView
enum MarginNoteAction {
    case commitHighlight(highlightId: UUID)
    case startThread(highlightId: UUID)
    case sendFollowUp(highlightId: UUID, message: String)
    case deleteHighlight(highlightId: UUID)
    case openSettings
}

/// Data to send to JavaScript for rendering margin notes
struct MarginNoteData: Codable, Equatable {
    let highlightId: String
    let previewText: String
    let isCommitted: Bool  // Whether the highlight is saved (shows Highlight button if false)
    let hasThread: Bool
    let threadContent: String?  // HTML for thread messages
    let isLoading: Bool
    let errorMessage: String?  // Error message to display if annotation fails
}

/// All annotations for a single book, stored as JSON
struct BookAnnotations: Codable {
    let bookId: UUID
    var highlights: [Highlight]
    var bookmarks: [Bookmark]
    var updatedAt: Date

    init(bookId: UUID, highlights: [Highlight] = [], bookmarks: [Bookmark] = []) {
        self.bookId = bookId
        self.highlights = highlights
        self.bookmarks = bookmarks
        self.updatedAt = Date()
    }

    mutating func addHighlight(_ highlight: Highlight) {
        highlights.append(highlight)
        updatedAt = Date()
    }

    mutating func removeHighlight(id: UUID) {
        highlights.removeAll { $0.id == id }
        updatedAt = Date()
    }

    mutating func addThread(to highlightId: UUID, thread: Thread) {
        if let index = highlights.firstIndex(where: { $0.id == highlightId }) {
            highlights[index].threads.append(thread)
            updatedAt = Date()
        }
    }

    mutating func addBookmark(_ bookmark: Bookmark) {
        bookmarks.append(bookmark)
        // Sort bookmarks by chapter index and creation date
        bookmarks.sort { lhs, rhs in
            if lhs.chapterIndex == rhs.chapterIndex {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.chapterIndex < rhs.chapterIndex
        }
        updatedAt = Date()
    }

    mutating func removeBookmark(id: UUID) {
        bookmarks.removeAll { $0.id == id }
        updatedAt = Date()
    }
}

/// A highlighted passage in a book
struct Highlight: Codable, Identifiable {
    let id: UUID
    let chapterId: String
    let selectedText: String
    let surroundingContext: String
    let cfiRange: CFIRange?  // Optional for backwards compatibility with existing highlights
    var threads: [Thread]
    var annotation: String?  // User's personal note about this highlight
    var category: AnnotationCategory  // Category for organization
    var tags: [String]  // Custom tags for flexible organization
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        chapterId: String,
        selectedText: String,
        surroundingContext: String,
        cfiRange: CFIRange? = nil,
        threads: [Thread] = [],
        annotation: String? = nil,
        category: AnnotationCategory = .other,
        tags: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.chapterId = chapterId
        self.selectedText = selectedText
        self.surroundingContext = surroundingContext
        self.cfiRange = cfiRange
        self.threads = threads
        self.annotation = annotation
        self.category = category
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

/// An AI conversation thread attached to a highlight
struct Thread: Codable, Identifiable {
    let id: UUID
    var messages: [ThreadMessage]
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        messages: [ThreadMessage] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    mutating func addMessage(_ message: ThreadMessage) {
        messages.append(message)
        updatedAt = Date()
    }
}

/// A single message in a thread (user prompt or AI response)
struct ThreadMessage: Codable, Identifiable {
    let id: UUID
    let role: MessageRole
    let content: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

enum MessageRole: String, Codable {
    case user
    case assistant
}

/// A bookmark for quick navigation to a specific location in a book
struct Bookmark: Codable, Identifiable {
    let id: UUID
    let chapterId: String
    let chapterIndex: Int
    let chapterTitle: String
    let note: String?
    let scrollPosition: Double  // 0.0 to 1.0 representing position in chapter
    var category: AnnotationCategory  // Category for organization
    var tags: [String]  // Custom tags for flexible organization
    let createdAt: Date

    init(
        id: UUID = UUID(),
        chapterId: String,
        chapterIndex: Int,
        chapterTitle: String,
        note: String? = nil,
        scrollPosition: Double = 0.0,
        category: AnnotationCategory = .other,
        tags: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.chapterId = chapterId
        self.chapterIndex = chapterIndex
        self.chapterTitle = chapterTitle
        self.note = note
        self.scrollPosition = scrollPosition
        self.category = category
        self.tags = tags
        self.createdAt = createdAt
    }
}
