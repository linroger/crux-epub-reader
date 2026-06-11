import SwiftUI

/// Single row in the library list view. Composed of four lines:
///  1. Title + Info-on-hover + Added date
///  2. Metadata strip (author · publisher · year · language)
///  3. Progress bar + chapter position + reading-time + last-read
///  4. Annotation counts + subject tags
///
/// Extracted from `LibraryView` to keep the parent file manageable.
struct BookListRow: View {
    let book: StoredBook
    let stats: AnnotationStats?
    let onShowDetails: () -> Void
    @State private var isHovered = false

    private var progressFraction: Double {
        guard book.totalChapters > 0 else { return 0 }
        if book.isFinished { return 1.0 }
        return Double(book.currentChapterIndex) / Double(book.totalChapters)
    }

    private var progressPercent: Int {
        Int(progressFraction * 100)
    }

    var body: some View {
        HStack(spacing: 12) {
            CachedCoverView(
                bookId: book.id,
                data: book.coverImageData,
                size: CGSize(width: 40, height: 60)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top) {
                    Text(book.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    if isHovered {
                        Button {
                            onShowDetails()
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Show book details")
                    }

                    Text("Added \(book.addedAt.relativeShort)")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                MetadataLine(book: book)
                ProgressLine(book: book, progressFraction: progressFraction, progressPercent: progressPercent)
                AnnotationLine(stats: stats, subjects: book.subjects)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.cruxAccentWash : Color.clear)
                .padding(.horizontal, 6)
        )
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Row Components

struct MetadataLine: View {
    let book: StoredBook

    var body: some View {
        HStack(spacing: 0) {
            let parts = metadataParts
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                Text(part)
                if index < parts.count - 1 {
                    Text(" · ")
                        .foregroundStyle(.quaternary)
                }
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var metadataParts: [String] {
        var parts: [String] = []
        if let author = book.author, !author.isEmpty {
            parts.append(author)
        }
        if let publisher = book.publisher, !publisher.isEmpty {
            parts.append(publisher)
        }
        if let year = book.publicationYear {
            parts.append(String(year))
        }
        if let language = book.language, !language.isEmpty {
            parts.append(language.uppercased())
        }
        return parts
    }
}

struct ProgressLine: View {
    let book: StoredBook
    let progressFraction: Double
    let progressPercent: Int

    var body: some View {
        HStack(spacing: 8) {
            CruxProgressBar(fraction: progressFraction, isFinished: book.isFinished)
                .frame(height: 4)

            if book.totalChapters > 0 {
                Text(chapterText)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(book.isFinished ? .green : .secondary)
            }

            // Reading-time estimate (~12 min / ~2 hr 15 min). Hidden when
            // we don't have a cached value yet — better than rendering
            // "less than a minute" for every freshly-imported book.
            if let readingLabel = readingTimeLabel {
                Text("·")
                    .foregroundStyle(.quaternary)
                Text(readingLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Estimated reading time: \(readingLabel)")
            }

            if let lastOpened = book.lastOpenedAt {
                Text("·")
                    .foregroundStyle(.quaternary)
                Text("Read \(lastOpened.relativeShort)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var chapterText: String {
        if book.isFinished {
            return "Done"
        }
        return "Ch \(book.currentChapterIndex + 1)/\(book.totalChapters) (\(progressPercent)%)"
    }

    private var readingTimeLabel: String? {
        guard book.cachedReadingMinutes > 0 else { return nil }
        return ReadingTimeEstimator.label(forMinutes: Double(book.cachedReadingMinutes))
    }
}

struct AnnotationLine: View {
    let stats: AnnotationStats?
    let subjects: [String]

    var body: some View {
        HStack(spacing: 0) {
            if let stats = stats, stats.highlightCount > 0 || stats.threadCount > 0 {
                HStack(spacing: 8) {
                    if stats.highlightCount > 0 {
                        Label("\(stats.highlightCount)", systemImage: "highlighter")
                            .font(.system(size: 11))
                    }
                    if stats.threadCount > 0 {
                        Label("\(stats.threadCount)", systemImage: "bubble.left")
                            .font(.system(size: 11))
                    }
                }
                .foregroundStyle(.tertiary)

                if !subjects.isEmpty {
                    Text(" · ")
                        .foregroundStyle(.quaternary)
                }
            }

            if !subjects.isEmpty {
                Text(subjects.prefix(3).joined(separator: ", "))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }
}
