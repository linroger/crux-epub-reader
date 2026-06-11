import SwiftUI

/// Books.app-style grid card: cover floats on a soft ground shadow,
/// info button reveals on hover, finished books get a green checkmark
/// badge anchored bottom-left.
///
/// Extracted from `LibraryView` to keep the parent file manageable.
struct BookGridCard: View {
    let book: StoredBook
    let stats: AnnotationStats?
    let onShowDetails: () -> Void
    @State private var isHovered = false

    private var progressFraction: Double {
        guard book.totalChapters > 0 else { return 0 }
        if book.isFinished { return 1.0 }
        return Double(book.currentChapterIndex) / Double(book.totalChapters)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                GeometryReader { geo in
                    CachedCoverView(
                        bookId: book.id,
                        data: book.coverImageData,
                        size: CGSize(width: geo.size.width, height: geo.size.width / 0.7),
                        cornerRadius: CruxMetrics.coverRadius
                    )
                    // Hairline edge keeps light covers from melting into
                    // the background; the shadow deepens and the cover
                    // lifts on hover for a tactile pick-me-up cue.
                    .overlay(
                        RoundedRectangle(cornerRadius: CruxMetrics.coverRadius)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(isHovered ? 0.22 : 0.12),
                            radius: isHovered ? 16 : 8,
                            x: 0,
                            y: isHovered ? 10 : 4)
                    .offset(y: isHovered ? -2 : 0)
                }
                .aspectRatio(0.7, contentMode: .fit)
                .accessibilityHidden(true)

                if isHovered {
                    Button {
                        onShowDetails()
                    } label: {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                            .background(
                                Circle()
                                    .fill(.black.opacity(0.45))
                                    .padding(-5)
                            )
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .help("Show book details")
                    .transition(.opacity.combined(with: .scale))
                }

                if book.isFinished {
                    VStack {
                        Spacer()
                        HStack {
                            FinishedBadge()
                                .padding(8)
                            Spacer()
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(book.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)

                if let author = book.author {
                    Text(author)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if book.totalChapters > 0 {
                    HStack(spacing: 6) {
                        CruxProgressBar(fraction: progressFraction, isFinished: book.isFinished)
                            .frame(height: 4)

                        Text(book.isFinished ? "Done" : "\(Int(progressFraction * 100))%")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(book.isFinished ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                            .monospacedDigit()
                    }
                    .padding(.top, 2)
                }

                if let stats = stats, stats.highlightCount > 0 {
                    HStack(spacing: 8) {
                        Label("\(stats.highlightCount)", systemImage: "highlighter")
                            .font(.caption2)
                            .foregroundStyle(Color.cruxAccent)

                        if stats.threadCount > 0 {
                            Label("\(stats.threadCount)", systemImage: "bubble.left.and.bubble.right")
                                .font(.caption2)
                                .foregroundStyle(.purple)
                        }
                    }
                }

                if let readingLabel = readingTimeLabel {
                    Text(readingLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel("Estimated reading time: \(readingLabel)")
                }
            }
            .padding(.horizontal, 2)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: CruxMetrics.cardRadius)
                .fill(isHovered ? Color.cruxAccentWash : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CruxMetrics.cardRadius)
                .strokeBorder(isHovered ? Color.cruxAccent.opacity(0.25) : Color.clear,
                              lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.015 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var readingTimeLabel: String? {
        guard book.cachedReadingMinutes > 0 else { return nil }
        return ReadingTimeEstimator.label(forMinutes: Double(book.cachedReadingMinutes))
    }
}

/// Small "checkmark in a green pill" badge overlay used on grid covers to
/// mark finished books at a glance, similar to Books.app's done indicator.
struct FinishedBadge: View {
    var body: some View {
        Label("Done", systemImage: "checkmark.circle.fill")
            .labelStyle(.iconOnly)
            .font(.system(size: 18))
            .foregroundStyle(.white)
            .padding(4)
            .background(
                Circle()
                    .fill(Color.green)
                    .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
            )
            .accessibilityLabel("Finished")
    }
}
