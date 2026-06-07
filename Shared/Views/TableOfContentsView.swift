import SwiftUI

struct TableOfContentsView: View {
    let chapters: [Chapter]
    let currentChapterIndex: Int
    let onSelectChapter: (Int) -> Void

    @State private var searchQuery = ""

    private var filteredChapters: [(index: Int, chapter: Chapter)] {
        let indexed = chapters.enumerated().map { ($0, $1) }
        guard !searchQuery.isEmpty else { return indexed }

        return indexed.filter { _, chapter in
            chapter.title.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.3), Color.cyan.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 32, height: 32)

                        Image(systemName: "list.bullet.indent")
                            .font(.system(size: 14))
                            .foregroundStyle(.blue)
                    }

                    Text("Contents")
                        .font(.headline)
                }

                Spacer()

                // Chapter count badge
                HStack(spacing: 4) {
                    Text("\(filteredChapters.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    if !searchQuery.isEmpty {
                        Text("of \(chapters.count)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1))
                .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [Color.cruxControlBackground, Color.cruxControlBackground.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            Divider()

            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))

                TextField("Search chapters...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))

                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.cruxTextBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Chapter list
            if filteredChapters.isEmpty {
                ContentUnavailableView.search(text: searchQuery)
            } else {
                ScrollViewReader { proxy in
                    List(filteredChapters, id: \.index) { index, chapter in
                        ChapterRow(
                            chapter: chapter,
                            isCurrentChapter: index == currentChapterIndex,
                            onTap: {
                                onSelectChapter(index)
                            }
                        )
                        .id(index)
                        .listRowInsets(EdgeInsets(
                            top: 4,
                            leading: CGFloat(8 + (chapter.depth * 12)),
                            bottom: 4,
                            trailing: 8
                        ))
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .onAppear {
                        // Scroll to current chapter on appear
                        proxy.scrollTo(currentChapterIndex, anchor: .center)
                    }
                    .onChange(of: currentChapterIndex) { _, newIndex in
                        withAnimation {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            }
        }
    }
}

struct ChapterRow: View {
    let chapter: Chapter
    let isCurrentChapter: Bool
    let onTap: () -> Void

    @State private var isHovering = false

    /// Plain-text preview for the row subtitle. `chapter.content` is raw
    /// XHTML, so a naive `prefix` shows the `<html xmlns=…>` boilerplate
    /// instead of prose. Strip tags (and decode the few common entities)
    /// from a bounded prefix, collapse whitespace, then take a short lead.
    private func chapterSnippet(_ html: String) -> String? {
        let bounded = String(html.prefix(4000))
        var text = bounded.replacingOccurrences(
            of: "<[^>]+>", with: " ", options: .regularExpression
        )
        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&#39;": "'", "&quot;": "\""]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        text = text.replacingOccurrences(
            of: "\\s+", with: " ", options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return String(text.prefix(100))
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                // Current chapter indicator with gradient
                if isCurrentChapter {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.blue, Color.cyan],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 3)
                } else {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 3)
                }

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(chapter.title)
                            .font(.system(size: 13, weight: isCurrentChapter ? .semibold : .regular))
                            .foregroundStyle(isCurrentChapter ? Color.blue : Color.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        if let snippet = chapterSnippet(chapter.content), !snippet.isEmpty {
                            Text(snippet)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    if isCurrentChapter {
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

                            Image(systemName: "book.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.blue)
                        }
                    } else if isHovering {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            Group {
                if isCurrentChapter {
                    LinearGradient(
                        colors: [Color.blue.opacity(0.08), Color.cyan.opacity(0.08)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                } else if isHovering {
                    Color.secondary.opacity(0.05)
                } else {
                    Color.clear
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
}

#Preview {
    TableOfContentsView(
        chapters: [
            Chapter(id: "ch1", title: "Chapter 1: The Beginning", href: "ch1.xhtml", content: "Lorem ipsum dolor sit amet...", order: 0, depth: 0),
            Chapter(id: "ch2", title: "Chapter 2: The Journey", href: "ch2.xhtml", content: "Consectetur adipiscing elit...", order: 1, depth: 0),
            Chapter(id: "ch3", title: "Chapter 3: The Destination", href: "ch3.xhtml", content: "Sed do eiusmod tempor...", order: 2, depth: 0)
        ],
        currentChapterIndex: 1,
        onSelectChapter: { _ in }
    )
    .frame(width: 300, height: 600)
}
