import SwiftUI
import SwiftData

struct RecentBooksSection: View {
    let books: [StoredBook]
    let onSelectBook: (UUID) -> Void
    let onShowDetails: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.blue)

                Text("Continue Reading")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()
            }
            .padding(.horizontal)

            // Horizontal scrollable book cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(books) { book in
                        RecentBookCard(
                            book: book,
                            onTap: { onSelectBook(book.id) },
                            onShowDetails: { onShowDetails(book.id) }
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
    }
}

struct RecentBookCard: View {
    let book: StoredBook
    let onTap: () -> Void
    let onShowDetails: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Cover with progress overlay
                ZStack(alignment: .bottomLeading) {
                    // Cover image or placeholder — CachedCoverView is
                    // cross-platform (macOS/iOS) and reuses decoded thumbnails
                    // from CoverImageCache instead of re-decoding full-size data.
                    CachedCoverView(
                        bookId: book.id,
                        data: book.coverImageData,
                        size: CGSize(width: 120, height: 180),
                        cornerRadius: 8
                    )

                    // Info button overlay (show on hover)
                    if isHovering {
                        VStack {
                            HStack {
                                Spacer()
                                Button(action: onShowDetails) {
                                    Image(systemName: "info.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(.white)
                                        .background(
                                            Circle()
                                                .fill(.black.opacity(0.5))
                                                .padding(-4)
                                        )
                                }
                                .buttonStyle(.plain)
                                .help("Show book details")
                                .padding(6)
                            }
                            Spacer()
                        }
                    }

                    // Progress bar at bottom
                    VStack {
                        Spacer()
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(.black.opacity(0.3))
                                    .frame(height: 4)

                                Rectangle()
                                    .fill(.blue)
                                    .frame(width: geometry.size.width * book.progress, height: 4)
                            }
                        }
                        .frame(height: 4)
                    }
                }
                .frame(width: 120, height: 180)
                .shadow(color: .black.opacity(isHovering ? 0.3 : 0.15), radius: isHovering ? 12 : 8, x: 0, y: 4)
                .scaleEffect(isHovering ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isHovering)

                // Book info
                VStack(alignment: .leading, spacing: 4) {
                    Text(book.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .frame(width: 120, alignment: .leading)

                    if let author = book.author {
                        Text(author)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(width: 120, alignment: .leading)
                    }

                    // Progress percentage
                    Text("\(Int(book.progress * 100))% complete")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.blue)
                        .frame(width: 120, alignment: .leading)
                }
            }
            .frame(width: 120)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// Preview removed - StoredBook is a SwiftData model that requires a model context
