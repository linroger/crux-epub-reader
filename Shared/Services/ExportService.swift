import Foundation
import UniformTypeIdentifiers
import SwiftData

#if os(macOS)
import AppKit
#endif

/// Service for exporting highlights and annotations to various formats
@MainActor
final class ExportService {
    static let shared = ExportService()

    private init() {}

    // MARK: - CSV Export

    /// Export highlights to CSV format
    /// - Parameter highlights: Array of highlights with book info to export
    /// - Returns: CSV data as String
    func exportToCSV(highlights: [HighlightWithBookInfo]) throws -> String {
        var csv = ""

        // Header row
        let headers = [
            "Book Title",
            "Author",
            "Highlighted Text",
            "Personal Note",
            "Date Created",
            "Date Updated",
            "Thread Count",
            "Message Count",
            "Chapter ID"
        ]
        csv += headers.map { escapeCSVField($0) }.joined(separator: ",") + "\n"

        // Data rows
        for item in highlights {
            let row = [
                item.bookTitle,
                item.bookAuthor,
                item.highlight.selectedText,
                item.highlight.annotation ?? "",
                formatDate(item.highlight.createdAt),
                formatDate(item.highlight.updatedAt),
                "\(item.threadCount)",
                "\(item.messageCount)",
                item.highlight.chapterId
            ]
            csv += row.map { escapeCSVField($0) }.joined(separator: ",") + "\n"
        }

        return csv
    }

    /// Export highlights with full thread details to CSV format
    /// - Parameter highlights: Array of highlights with book info to export
    /// - Returns: CSV data as String with expanded thread information
    func exportToCSVWithThreads(highlights: [HighlightWithBookInfo]) throws -> String {
        var csv = ""

        // Header row
        let headers = [
            "Book Title",
            "Author",
            "Highlighted Text",
            "Personal Note",
            "Date Created",
            "Thread ID",
            "Thread Created",
            "Message Role",
            "Message Content",
            "Message Date"
        ]
        csv += headers.map { escapeCSVField($0) }.joined(separator: ",") + "\n"

        // Data rows - one row per message
        for item in highlights {
            if item.highlight.threads.isEmpty {
                // For highlights without threads, output one row with empty thread columns
                let row = [
                    item.bookTitle,
                    item.bookAuthor,
                    item.highlight.selectedText,
                    item.highlight.annotation ?? "",
                    formatDate(item.highlight.createdAt),
                    "", // Thread ID
                    "", // Thread Created
                    "", // Message Role
                    "", // Message Content
                    ""  // Message Date
                ]
                csv += row.map { escapeCSVField($0) }.joined(separator: ",") + "\n"
            } else {
                // For each thread and message, create a row
                for thread in item.highlight.threads {
                    for message in thread.messages {
                        let row = [
                            item.bookTitle,
                            item.bookAuthor,
                            item.highlight.selectedText,
                            item.highlight.annotation ?? "",
                            formatDate(item.highlight.createdAt),
                            thread.id.uuidString,
                            formatDate(thread.createdAt),
                            message.role.rawValue,
                            message.content,
                            formatDate(message.createdAt)
                        ]
                        csv += row.map { escapeCSVField($0) }.joined(separator: ",") + "\n"
                    }
                }
            }
        }

        return csv
    }

    // MARK: - Markdown Export

    /// Export highlights to Markdown format
    /// - Parameter highlights: Array of highlights with book info to export
    /// - Returns: Markdown data as String
    func exportToMarkdown(highlights: [HighlightWithBookInfo]) throws -> String {
        var markdown = "# Highlights Export\n\n"
        markdown += "Exported on \(formatDate(Date()))\n\n"

        // Group by book
        let groupedByBook = Dictionary(grouping: highlights) { $0.bookId }

        for (_, bookHighlights) in groupedByBook.sorted(by: { $0.value.first?.bookTitle ?? "" < $1.value.first?.bookTitle ?? "" }) {
            guard let first = bookHighlights.first else { continue }

            markdown += "## \(first.bookTitle)\n"
            markdown += "*by \(first.bookAuthor)*\n\n"

            for item in bookHighlights.sorted(by: { $0.highlight.createdAt < $1.highlight.createdAt }) {
                markdown += "### Highlight - \(formatDate(item.highlight.createdAt))\n\n"
                markdown += "> \(item.highlight.selectedText)\n\n"

                if let annotation = item.highlight.annotation, !annotation.isEmpty {
                    markdown += "**Personal Note:** \(annotation)\n\n"
                }

                if !item.highlight.threads.isEmpty {
                    markdown += "**AI Threads (\(item.threadCount)):**\n\n"
                    for thread in item.highlight.threads {
                        markdown += "- Thread from \(formatDate(thread.createdAt)) (\(thread.messages.count) messages)\n"
                    }
                    markdown += "\n"
                }

                markdown += "---\n\n"
            }
        }

        return markdown
    }

    // MARK: - Bookmark Export

    /// Export bookmarks to CSV format
    /// - Parameters:
    ///   - bookmarks: Array of bookmarks to export
    ///   - bookTitle: Title of the book
    ///   - bookAuthor: Author of the book
    /// - Returns: CSV data as String
    func exportBookmarksToCSV(bookmarks: [Bookmark], bookTitle: String, bookAuthor: String) throws -> String {
        var csv = ""

        // Header row
        let headers = [
            "Book Title",
            "Author",
            "Chapter Title",
            "Chapter Index",
            "Position (%)",
            "Note",
            "Date Created"
        ]
        csv += headers.map { escapeCSVField($0) }.joined(separator: ",") + "\n"

        // Data rows
        for bookmark in bookmarks {
            let row = [
                bookTitle,
                bookAuthor,
                bookmark.chapterTitle,
                "\(bookmark.chapterIndex + 1)",
                "\(Int(bookmark.scrollPosition * 100))",
                bookmark.note ?? "",
                formatDate(bookmark.createdAt)
            ]
            csv += row.map { escapeCSVField($0) }.joined(separator: ",") + "\n"
        }

        return csv
    }

    /// Export bookmarks to Markdown format
    /// - Parameters:
    ///   - bookmarks: Array of bookmarks to export
    ///   - bookTitle: Title of the book
    ///   - bookAuthor: Author of the book
    /// - Returns: Markdown data as String
    func exportBookmarksToMarkdown(bookmarks: [Bookmark], bookTitle: String, bookAuthor: String) throws -> String {
        var markdown = "# Bookmarks Export\n\n"
        markdown += "Exported on \(formatDate(Date()))\n\n"

        markdown += "## \(bookTitle)\n"
        markdown += "*by \(bookAuthor)*\n\n"

        for bookmark in bookmarks.sorted(by: { $0.createdAt < $1.createdAt }) {
            markdown += "### \(bookmark.chapterTitle)\n\n"
            markdown += "- **Position:** Chapter \(bookmark.chapterIndex + 1)"
            if bookmark.scrollPosition > 0 {
                markdown += " (\(Int(bookmark.scrollPosition * 100))%)"
            }
            markdown += "\n"
            markdown += "- **Date:** \(formatDate(bookmark.createdAt))\n"

            if let note = bookmark.note, !note.isEmpty {
                markdown += "\n**Note:**\n> \(note)\n"
            }

            markdown += "\n---\n\n"
        }

        return markdown
    }

    // MARK: - File Saving

    #if os(macOS)
    /// Save data to a file using NSSavePanel
    /// - Parameters:
    ///   - data: String data to save
    ///   - suggestedFilename: Suggested filename
    ///   - contentType: UTType for the file
    /// - Returns: URL of saved file, or nil if cancelled
    func saveToFile(data: String, suggestedFilename: String, contentType: UTType) async -> URL? {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = suggestedFilename
        savePanel.allowedContentTypes = [contentType]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false

        let response = await savePanel.begin()

        guard response == .OK, let url = savePanel.url else {
            return nil
        }

        do {
            try data.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            print("Failed to save file: \(error)")
            return nil
        }
    }
    #endif

    // MARK: - Helper Methods

    /// Escape a CSV field (handle quotes, commas, newlines)
    private func escapeCSVField(_ field: String) -> String {
        // If field contains comma, quote, or newline, wrap in quotes and escape internal quotes
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }

    /// Format date for export
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
