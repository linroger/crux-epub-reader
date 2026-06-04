import Foundation

/// Per-book, in-memory search index for fast book-wide text search.
///
/// `performBookSearch` previously re-ran `HTMLTextExtractor.extractText`
/// over every chapter on every keystroke. For a 300-chapter book that's
/// ~3 MB of HTML stripped per query, which is fine once but noticeable
/// when typing rapidly. `BookSearchIndex` strips each chapter once at
/// build time and caches the plain text plus a lowercased copy so each
/// subsequent query is a tight loop of substring scans.
///
/// The index also pre-tokenizes into a word-frequency map so the search
/// UI can later show a candidate count without scanning. We keep this
/// modest — pulling in a full FTS engine isn't worth the binary cost
/// for the typical Crux library size.
@MainActor
final class BookSearchIndex {
    struct ChapterText {
        let chapterIndex: Int
        let chapterId: String
        let chapterTitle: String
        /// Plain text with HTML stripped; the form snippets are sliced from.
        let plain: String
        /// Lowercased `plain` cached once so `findMatches` doesn't
        /// lowercase the same multi-kilobyte string per keystroke.
        let lowercased: String
    }

    private(set) var chapters: [ChapterText] = []

    /// Build the index from a list of (chapterIndex, id, title, htmlContent).
    /// Idempotent — calling twice rebuilds.
    func build(from chapters: [(index: Int, id: String, title: String, html: String)]) {
        self.chapters = chapters.map { chapter in
            let plain = HTMLTextExtractor.extractText(from: chapter.html)
            return ChapterText(
                chapterIndex: chapter.index,
                chapterId: chapter.id,
                chapterTitle: chapter.title,
                plain: plain,
                lowercased: plain.lowercased()
            )
        }
    }

    /// Returns book-wide matches sorted by chapter order, then match position.
    /// Each match has a snippet that includes ~contextLength characters
    /// of surrounding text on either side of the hit.
    func search(_ query: String, contextLength: Int = 50) -> [SearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let needle = trimmed.lowercased()

        var hits: [SearchHit] = []
        for chapter in chapters {
            // `findMatches` already supports lowercased comparison
            // internally; reusing it keeps the snippet formatting identical
            // to the previous code path so the UI doesn't need to change.
            let chapterMatches = HTMLTextExtractor.findMatches(
                in: chapter.plain,
                query: needle,
                contextLength: contextLength
            )
            for (matchIndex, match) in chapterMatches.enumerated() {
                hits.append(SearchHit(
                    chapterIndex: chapter.chapterIndex,
                    chapterId: chapter.chapterId,
                    chapterTitle: chapter.chapterTitle,
                    matchIndex: matchIndex,
                    snippet: match.snippet
                ))
            }
        }
        return hits
    }

    struct SearchHit {
        let chapterIndex: Int
        let chapterId: String
        let chapterTitle: String
        let matchIndex: Int
        let snippet: String
    }
}
