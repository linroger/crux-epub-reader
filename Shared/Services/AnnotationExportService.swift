import Foundation
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum ExportFormat {
    case markdown
    case json
    case html
    case plainText
    /// Crux's own self-describing annotation bundle (carries book
    /// metadata + version stamp so a recipient can re-import into
    /// their library). See `CruxNotesBundle`.
    case cruxNotes

    var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .json: return "json"
        case .html: return "html"
        case .plainText: return "txt"
        case .cruxNotes: return "cruxnotes"
        }
    }

    var displayName: String {
        switch self {
        case .markdown: return "Markdown"
        case .json: return "JSON"
        case .html: return "HTML"
        case .plainText: return "Plain Text"
        case .cruxNotes: return "Crux Notes Bundle"
        }
    }
}

/// Service for exporting book annotations in various formats
actor AnnotationExportService {
    static let shared = AnnotationExportService()

    private init() {}

    /// Export annotations for a book to a string in the specified format.
    /// Async because the `.cruxNotes` branch hops to the `CruxNotesIO`
    /// actor to do the bundle encode; the other branches finish
    /// synchronously and the cost is a single hop on the actor switch.
    func exportAnnotations(
        bookTitle: String,
        bookAuthor: String?,
        annotations: BookAnnotations,
        format: ExportFormat
    ) async -> String {
        switch format {
        case .markdown:
            return exportAsMarkdown(bookTitle: bookTitle, bookAuthor: bookAuthor, annotations: annotations)
        case .json:
            return exportAsJSON(annotations: annotations)
        case .html:
            return exportAsHTML(bookTitle: bookTitle, bookAuthor: bookAuthor, annotations: annotations)
        case .plainText:
            return exportAsPlainText(bookTitle: bookTitle, bookAuthor: bookAuthor, annotations: annotations)
        case .cruxNotes:
            return await exportAsCruxNotes(bookTitle: bookTitle, bookAuthor: bookAuthor, annotations: annotations)
        }
    }

    /// Build a `CruxNotesBundle` and serialize it to a pretty-printed
    /// JSON string. Failures fall back to an empty object so the
    /// caller can show an export error rather than crashing on a
    /// bad encoder configuration that should never happen in practice.
    private func exportAsCruxNotes(
        bookTitle: String,
        bookAuthor: String?,
        annotations: BookAnnotations
    ) async -> String {
        let bundle = CruxNotesBundle(
            bookId: annotations.bookId,
            bookTitle: bookTitle,
            bookAuthor: bookAuthor,
            annotations: annotations
        )
        do {
            let data = try await CruxNotesIO.shared.encode(bundle)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            AppLog.errors.error("Failed to encode .cruxnotes bundle: \(error.localizedDescription, privacy: .public)")
            return "{}"
        }
    }

    /// Save exported annotations to a file
    @MainActor
    func saveToFile(
        bookTitle: String,
        bookAuthor: String?,
        annotations: BookAnnotations,
        format: ExportFormat
    ) async throws -> URL? {
        let content = await exportAnnotations(
            bookTitle: bookTitle,
            bookAuthor: bookAuthor,
            annotations: annotations,
            format: format
        )

        let sanitizedTitle = bookTitle.replacingOccurrences(of: "[^a-zA-Z0-9 ]", with: "", options: .regularExpression)
        let filename = "\(sanitizedTitle) - Annotations.\(format.fileExtension)"

        #if os(macOS)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename
        if let contentType = UTType(filenameExtension: format.fileExtension) {
            panel.allowedContentTypes = [contentType]
        }
        panel.canCreateDirectories = true

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else {
            return nil
        }

        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
        #else
        // iOS: Save to temporary directory and return URL for sharing
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(filename)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
        #endif
    }

    // MARK: - Format-Specific Export

    private func exportAsMarkdown(bookTitle: String, bookAuthor: String?, annotations: BookAnnotations) -> String {
        var markdown = "# \(bookTitle)\n\n"

        if let author = bookAuthor {
            markdown += "**Author:** \(author)\n\n"
        }

        markdown += "**Exported:** \(Date().formatted(date: .long, time: .shortened))\n\n"
        markdown += "---\n\n"

        // Highlights
        if !annotations.highlights.isEmpty {
            markdown += "## Highlights & Notes\n\n"

            for (index, highlight) in annotations.highlights.enumerated() {
                markdown += "### \(index + 1). Chapter: \(highlight.chapterId)\n\n"
                markdown += "> \(highlight.selectedText)\n\n"

                if let annotation = highlight.annotation {
                    markdown += "**My Note:** \(annotation)\n\n"
                }

                // AI Conversations
                if !highlight.threads.isEmpty {
                    markdown += "**AI Conversations:**\n\n"
                    for thread in highlight.threads {
                        for message in thread.messages {
                            let prefix = message.role == .user ? "Q:" : "A:"
                            markdown += "- **\(prefix)** \(message.content)\n"
                        }
                        markdown += "\n"
                    }
                }

                markdown += "---\n\n"
            }
        }

        // Bookmarks
        if !annotations.bookmarks.isEmpty {
            markdown += "## Bookmarks\n\n"

            for bookmark in annotations.bookmarks {
                markdown += "- **\(bookmark.chapterTitle)**"
                if let note = bookmark.note {
                    markdown += ": \(note)"
                }
                markdown += "\n"
            }
            markdown += "\n"
        }

        return markdown
    }

    private func exportAsJSON(annotations: BookAnnotations) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(annotations),
              let jsonString = String(data: data, encoding: .utf8) else {
            return "{}"
        }

        return jsonString
    }

    private func exportAsHTML(bookTitle: String, bookAuthor: String?, annotations: BookAnnotations) -> String {
        // All user-supplied strings are escaped at every interpolation point
        // because the exported file may be opened in a browser where script
        // or markup injection would otherwise execute.
        let safeTitle = bookTitle.htmlEscaped
        var html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:;">
            <title>\(safeTitle) - Annotations</title>
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
                    max-width: 800px;
                    margin: 40px auto;
                    padding: 0 20px;
                    line-height: 1.6;
                    color: #333;
                }
                h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 10px; }
                h2 { color: #34495e; margin-top: 30px; }
                .metadata { color: #7f8c8d; font-size: 0.9em; margin-bottom: 30px; }
                .highlight {
                    background: #f8f9fa;
                    border-left: 4px solid #3498db;
                    padding: 15px;
                    margin: 20px 0;
                    border-radius: 4px;
                }
                .quote {
                    font-style: italic;
                    color: #2c3e50;
                    margin-bottom: 10px;
                }
                .note {
                    background: #fff3cd;
                    padding: 10px;
                    border-radius: 4px;
                    margin-top: 10px;
                }
                .thread {
                    background: #e8f4f8;
                    padding: 10px;
                    border-radius: 4px;
                    margin-top: 10px;
                }
                .message { margin: 10px 0; }
                .user { font-weight: 600; color: #2980b9; }
                .assistant { font-weight: 600; color: #27ae60; }
                .bookmark {
                    padding: 8px;
                    border-left: 3px solid #e74c3c;
                    margin: 10px 0;
                }
            </style>
        </head>
        <body>
            <h1>\(safeTitle)</h1>
        """

        if let author = bookAuthor {
            html += "<p class=\"metadata\"><strong>Author:</strong> \(author.htmlEscaped)</p>"
        }

        html += "<p class=\"metadata\"><strong>Exported:</strong> \(Date().formatted(date: .long, time: .shortened))</p>"

        // Highlights
        if !annotations.highlights.isEmpty {
            html += "<h2>Highlights &amp; Notes</h2>"

            for (index, highlight) in annotations.highlights.enumerated() {
                html += """
                <div class="highlight">
                    <h3>\(index + 1). \(highlight.chapterId.htmlEscaped)</h3>
                    <div class="quote">\(highlight.selectedText.htmlEscaped)</div>
                """

                if let annotation = highlight.annotation {
                    html += "<div class=\"note\"><strong>My Note:</strong> \(annotation.htmlEscaped)</div>"
                }

                if !highlight.threads.isEmpty {
                    html += "<div class=\"thread\"><strong>AI Conversations:</strong>"
                    for thread in highlight.threads {
                        for message in thread.messages {
                            let roleClass = message.role == .user ? "user" : "assistant"
                            let prefix = message.role == .user ? "Q:" : "A:"
                            html += "<div class=\"message\"><span class=\"\(roleClass)\">\(prefix)</span> \(message.content.htmlEscaped)</div>"
                        }
                    }
                    html += "</div>"
                }

                html += "</div>"
            }
        }

        // Bookmarks
        if !annotations.bookmarks.isEmpty {
            html += "<h2>Bookmarks</h2>"
            for bookmark in annotations.bookmarks {
                html += "<div class=\"bookmark\"><strong>\(bookmark.chapterTitle.htmlEscaped)</strong>"
                if let note = bookmark.note {
                    html += ": \(note.htmlEscaped)"
                }
                html += "</div>"
            }
        }

        html += """
        </body>
        </html>
        """

        return html
    }

    private func exportAsPlainText(bookTitle: String, bookAuthor: String?, annotations: BookAnnotations) -> String {
        var text = "\(bookTitle)\n"
        text += String(repeating: "=", count: bookTitle.count) + "\n\n"

        if let author = bookAuthor {
            text += "Author: \(author)\n"
        }

        text += "Exported: \(Date().formatted(date: .long, time: .shortened))\n\n"
        text += String(repeating: "-", count: 60) + "\n\n"

        // Highlights
        if !annotations.highlights.isEmpty {
            text += "HIGHLIGHTS & NOTES\n\n"

            for (index, highlight) in annotations.highlights.enumerated() {
                text += "\(index + 1). \(highlight.chapterId)\n\n"
                text += "   \"\(highlight.selectedText)\"\n\n"

                if let annotation = highlight.annotation {
                    text += "   My Note: \(annotation)\n\n"
                }

                if !highlight.threads.isEmpty {
                    text += "   AI Conversations:\n"
                    for thread in highlight.threads {
                        for message in thread.messages {
                            let prefix = message.role == .user ? "Q:" : "A:"
                            text += "   - \(prefix) \(message.content)\n"
                        }
                    }
                    text += "\n"
                }

                text += String(repeating: "-", count: 60) + "\n\n"
            }
        }

        // Bookmarks
        if !annotations.bookmarks.isEmpty {
            text += "BOOKMARKS\n\n"

            for bookmark in annotations.bookmarks {
                text += "• \(bookmark.chapterTitle)"
                if let note = bookmark.note {
                    text += ": \(note)"
                }
                text += "\n"
            }
            text += "\n"
        }

        return text
    }
}

// MARK: - String Extension for HTML Escaping

private extension String {
    var htmlEscaped: String {
        self.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
