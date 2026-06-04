import SwiftUI

struct AnnotationExportView: View {
    @Environment(\.dismiss) private var dismiss

    let bookTitle: String
    let bookAuthor: String?
    let annotations: BookAnnotations

    @State private var selectedFormat: ExportFormat = .markdown
    @State private var isExporting = false
    @State private var exportSuccess = false
    @State private var exportError: String?
    @State private var errorHandler = ErrorHandler.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "book.closed.fill")
                                .foregroundStyle(.blue)
                            Text(bookTitle)
                                .font(.headline)
                        }

                        if let author = bookAuthor {
                            HStack {
                                Image(systemName: "person.fill")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                                Text(author)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Book")
                }

                Section {
                    HStack {
                        Image(systemName: "highlighter")
                            .foregroundStyle(.yellow)
                        Text("\(annotations.highlights.count) highlight\(annotations.highlights.count == 1 ? "" : "s")")
                    }

                    HStack {
                        Image(systemName: "bookmark.fill")
                            .foregroundStyle(.red)
                        Text("\(annotations.bookmarks.count) bookmark\(annotations.bookmarks.count == 1 ? "" : "s")")
                    }

                    let threadCount = annotations.highlights.reduce(0) { $0 + $1.threads.count }
                    HStack {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .foregroundStyle(.green)
                        Text("\(threadCount) AI conversation\(threadCount == 1 ? "" : "s")")
                    }
                } header: {
                    Text("Content")
                }

                Section {
                    Picker("Format", selection: $selectedFormat) {
                        ForEach([ExportFormat.markdown, .html, .plainText, .json, .cruxNotes], id: \.fileExtension) { format in
                            HStack {
                                Text(format.displayName)
                                Spacer()
                                Text(".\(format.fileExtension)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(format)
                        }
                    }
                    .pickerStyle(.inline)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("About this format:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(formatDescription)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Export Format")
                }
            }
            .navigationTitle("Export Annotations")
            #if os(macOS)
            .frame(minWidth: 500, minHeight: 500)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await performExport() }
                    } label: {
                        if isExporting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                    }
                    .disabled(isExporting)
                }
            }
        }
    }

    private var formatDescription: String {
        switch selectedFormat {
        case .markdown:
            return "Markdown format with headings, quotes, and lists. Perfect for note-taking apps like Obsidian, Notion, or Bear."
        case .html:
            return "Styled HTML page that can be opened in any web browser. Includes formatting and colors."
        case .plainText:
            return "Simple text file that works everywhere. No formatting, just your highlights and notes."
        case .json:
            return "Structured data format. Useful for developers or importing into other apps."
        case .cruxNotes:
            return "Self-contained Crux bundle (.cruxnotes) with book metadata. Re-importable into any Crux library on macOS/iOS."
        }
    }

    @MainActor
    private func performExport() async {
        isExporting = true
        defer { isExporting = false }

        do {
            if let url = try await AnnotationExportService.shared.saveToFile(
                bookTitle: bookTitle,
                bookAuthor: bookAuthor,
                annotations: annotations,
                format: selectedFormat
            ) {
                errorHandler.showSuccess("Annotations exported successfully")
                dismiss()
            } else {
                // User cancelled
            }
        } catch {
            errorHandler.handle(
                AppError.exportFailed(error.localizedDescription),
                context: "exportAnnotations"
            )
        }
    }
}

#Preview {
    let highlights = [
        Highlight(
            chapterId: "Chapter 1",
            selectedText: "It was the best of times, it was the worst of times.",
            surroundingContext: "It was the best of times, it was the worst of times, it was the age of wisdom, it was the age of foolishness...",
            annotation: "Classic opening line showing contrast and duality"
        ),
        Highlight(
            chapterId: "Chapter 3",
            selectedText: "Liberty, equality, fraternity",
            surroundingContext: "The cry of the revolution: Liberty, equality, fraternity, or death!",
            threads: [
                Thread(messages: [
                    ThreadMessage(role: .user, content: "What's the historical context?"),
                    ThreadMessage(role: .assistant, content: "This was the motto of the French Revolution, representing the core ideals that drove the revolutionary movement.")
                ])
            ]
        )
    ]

    let bookmarks = [
        Bookmark(
            chapterId: "chapter-1",
            chapterIndex: 0,
            chapterTitle: "The Period",
            note: "Important opening"
        ),
        Bookmark(
            chapterId: "chapter-5",
            chapterIndex: 4,
            chapterTitle: "The Wine-Shop",
            note: "Key scene with the spilled wine"
        )
    ]

    let annotations = BookAnnotations(
        bookId: UUID(),
        highlights: highlights,
        bookmarks: bookmarks
    )

    return AnnotationExportView(
        bookTitle: "A Tale of Two Cities",
        bookAuthor: "Charles Dickens",
        annotations: annotations
    )
}
