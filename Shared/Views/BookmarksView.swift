import SwiftUI
#if os(macOS)
import UniformTypeIdentifiers
#endif

struct BookmarksView: View {
    let bookmarks: [Bookmark]
    let bookTitle: String
    let bookAuthor: String
    let onSelectBookmark: (Bookmark) -> Void
    let onDeleteBookmark: (UUID) -> Void

    @State private var showingExportSheet = false
    @State private var showingExportSuccess = false
    @State private var exportErrorMessage: String?

    var body: some View {
        Group {
            if bookmarks.isEmpty {
                ContentUnavailableView(
                    "No Bookmarks",
                    systemImage: "bookmark",
                    description: Text("Tap the bookmark button while reading to save your current position")
                )
            } else {
                List {
                    ForEach(bookmarks) { bookmark in
                        BookmarkRow(
                            bookmark: bookmark,
                            onTap: {
                                onSelectBookmark(bookmark)
                            }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                onDeleteBookmark(bookmark.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    showingExportSheet = true
                } label: {
                    Label("Export Bookmarks", systemImage: "square.and.arrow.up")
                }
                .disabled(bookmarks.isEmpty)
            }
        }
        .sheet(isPresented: $showingExportSheet) {
            BookmarkExportSheet(
                bookmarks: bookmarks,
                bookTitle: bookTitle,
                bookAuthor: bookAuthor,
                onExportSuccess: {
                    showingExportSuccess = true
                },
                onExportError: { error in
                    exportErrorMessage = error
                }
            )
        }
        .alert("Export Successful", isPresented: $showingExportSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your bookmarks have been exported successfully.")
        }
        .alert("Export Failed", isPresented: .constant(exportErrorMessage != nil)) {
            Button("OK", role: .cancel) {
                exportErrorMessage = nil
            }
        } message: {
            Text(exportErrorMessage ?? "An unknown error occurred.")
        }
    }
}

struct BookmarkRow: View {
    let bookmark: Bookmark
    let onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                // Accent bar
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue, Color.cyan],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3)
                    .opacity(isHovering ? 1.0 : 0.0)

                VStack(alignment: .leading, spacing: 8) {
                    // Chapter title with position indicator
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.blue.opacity(0.2), Color.cyan.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 24, height: 24)

                            Image(systemName: "bookmark.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.blue)
                        }

                        Text(bookmark.chapterTitle)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        Spacer()

                        if bookmark.scrollPosition > 0 {
                            Text("\(Int(bookmark.scrollPosition * 100))%")
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }

                    // User note if present
                    if let note = bookmark.note, !note.isEmpty {
                        HStack(spacing: 0) {
                            Rectangle()
                                .fill(Color.blue.opacity(0.3))
                                .frame(width: 2)

                            Text(note)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .padding(.leading, 8)
                        }
                        .padding(.leading, 12)
                    }

                    // Creation date
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)

                        Text(bookmark.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.leading, 12)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            isHovering
                ? Color.secondary.opacity(0.05)
                : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Bookmark Export Sheet

struct BookmarkExportSheet: View {
    let bookmarks: [Bookmark]
    let bookTitle: String
    let bookAuthor: String
    let onExportSuccess: () -> Void
    let onExportError: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedFormat: ExportFormat = .csv
    @State private var isExporting = false

    enum ExportFormat: String, CaseIterable, Identifiable {
        case csv = "CSV"
        case markdown = "Markdown"

        var id: String { rawValue }

        var fileExtension: String {
            switch self {
            case .csv:
                return "csv"
            case .markdown:
                return "md"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Format selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Export Format")
                        .font(.headline)

                    Picker("Format", selection: $selectedFormat) {
                        ForEach(ExportFormat.allCases) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }

                // Format descriptions
                VStack(alignment: .leading, spacing: 8) {
                    Text("Format Description")
                        .font(.headline)

                    Text(formatDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Statistics
                VStack(alignment: .leading, spacing: 8) {
                    Text("Export Statistics")
                        .font(.headline)

                    HStack(spacing: 16) {
                        statItem(label: "Total Bookmarks", value: "\(bookmarks.count)")
                        Divider()
                        statItem(label: "With Notes", value: "\(bookmarks.filter { $0.note != nil && !$0.note!.isEmpty }.count)")
                    }
                    .padding()
                    .background(.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Export Bookmarks")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") {
                        performExport()
                    }
                    .disabled(isExporting)
                }
            }
        }
        .frame(width: 500, height: 400)
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var formatDescription: String {
        switch selectedFormat {
        case .csv:
            return "Exports bookmarks as a CSV file with book title, author, chapter information, position, notes, and dates."
        case .markdown:
            return "Exports bookmarks in a formatted Markdown document with chapter titles, positions, and notes."
        }
    }

    private func performExport() {
        isExporting = true

        Task {
            do {
                let exportService = ExportService.shared
                let data: String

                switch selectedFormat {
                case .csv:
                    data = try exportService.exportBookmarksToCSV(
                        bookmarks: bookmarks,
                        bookTitle: bookTitle,
                        bookAuthor: bookAuthor
                    )
                case .markdown:
                    data = try exportService.exportBookmarksToMarkdown(
                        bookmarks: bookmarks,
                        bookTitle: bookTitle,
                        bookAuthor: bookAuthor
                    )
                }

                #if os(macOS)
                let timestamp = Date().formatted(.dateTime.year().month().day().hour().minute())
                let suggestedFilename = "Crux_Bookmarks_\(timestamp).\(selectedFormat.fileExtension)"

                if await exportService.saveToFile(
                    data: data,
                    suggestedFilename: suggestedFilename,
                    contentType: selectedFormat.fileExtension == "csv" ? .commaSeparatedText : .plainText
                ) != nil {
                    dismiss()
                    onExportSuccess()
                } else {
                    // User cancelled or save failed
                    isExporting = false
                }
                #else
                // iOS export would use share sheet
                isExporting = false
                dismiss()
                onExportSuccess()
                #endif
            } catch {
                isExporting = false
                onExportError(error.localizedDescription)
                dismiss()
            }
        }
    }
}

#Preview {
    NavigationStack {
        BookmarksView(
            bookmarks: [
                Bookmark(
                    chapterId: "ch1",
                    chapterIndex: 0,
                    chapterTitle: "Chapter 1: The Beginning",
                    note: "Important quote about the protagonist",
                    scrollPosition: 0.25
                ),
                Bookmark(
                    chapterId: "ch3",
                    chapterIndex: 2,
                    chapterTitle: "Chapter 3: The Journey Continues",
                    scrollPosition: 0.0
                ),
                Bookmark(
                    chapterId: "ch5",
                    chapterIndex: 4,
                    chapterTitle: "Chapter 5: Resolution",
                    note: "Climax of the story",
                    scrollPosition: 0.75
                )
            ],
            bookTitle: "Sample Book",
            bookAuthor: "John Doe",
            onSelectBookmark: { _ in },
            onDeleteBookmark: { _ in }
        )
        .navigationTitle("Bookmarks")
    }
}
