import Foundation

/// Wrapper that combines a highlight with its book information
struct HighlightWithBookInfo: Identifiable, Hashable {
    let highlight: Highlight
    let bookId: UUID
    let bookTitle: String
    let bookAuthor: String

    var id: UUID { highlight.id }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: HighlightWithBookInfo, rhs: HighlightWithBookInfo) -> Bool {
        lhs.id == rhs.id
    }

    /// Formatted date string
    var formattedDate: String {
        highlight.createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    /// Relative date string (e.g., "2 hours ago")
    var relativeDate: String {
        highlight.createdAt.relativeFormatted
    }

    /// Preview of the selected text (truncated if too long)
    var textPreview: String {
        let maxLength = 150
        if highlight.selectedText.count <= maxLength {
            return highlight.selectedText
        }
        return String(highlight.selectedText.prefix(maxLength)) + "..."
    }

    /// Thread count
    var threadCount: Int {
        highlight.threads.count
    }

    /// Total messages across all threads
    var messageCount: Int {
        highlight.threads.reduce(0) { $0 + $1.messages.count }
    }

    /// Whether this highlight has an annotation
    var hasAnnotation: Bool {
        highlight.annotation != nil && !highlight.annotation!.isEmpty
    }
}
