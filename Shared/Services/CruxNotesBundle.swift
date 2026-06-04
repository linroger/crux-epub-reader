import Foundation
import UniformTypeIdentifiers

/// A self-describing annotation bundle for sharing/backup of a user's
/// highlights, threads, and bookmarks across machines or with other
/// readers.
///
/// Format goals:
/// * **Self-contained.** The file carries enough book metadata that a
///   recipient can match it to a book in their own library without
///   having to ship the EPUB alongside.
/// * **Forward-compatible.** A `formatVersion` lets future fields land
///   without breaking older importers; unknown fields are tolerated by
///   `JSONDecoder` when the schema only adds.
/// * **Round-trippable.** Encode → decode → encode produces byte-identical
///   output for the same input (modulo timestamp); this is what the
///   unit tests assert.
struct CruxNotesBundle: Codable {
    /// Bumped when the schema changes in a way that older importers
    /// would mis-read. Importers refuse anything they don't understand.
    static let currentFormatVersion = 1

    let formatVersion: Int
    let bookId: UUID
    let bookTitle: String
    let bookAuthor: String?
    let exportedAt: Date
    let annotations: BookAnnotations

    init(
        bookId: UUID,
        bookTitle: String,
        bookAuthor: String?,
        annotations: BookAnnotations,
        exportedAt: Date = Date()
    ) {
        self.formatVersion = Self.currentFormatVersion
        self.bookId = bookId
        self.bookTitle = bookTitle
        self.bookAuthor = bookAuthor
        self.exportedAt = exportedAt
        self.annotations = annotations
    }
}

/// File-system I/O for `.cruxnotes` files. Kept separate from the
/// bundle type so the codable surface stays small and easy to test;
/// this actor just wraps `JSONEncoder` / `JSONDecoder` and `FileManager`.
actor CruxNotesIO {
    static let shared = CruxNotesIO()

    private init() {}

    enum ImportError: LocalizedError {
        case malformedFile(underlying: Error)
        case unsupportedVersion(Int)
        case noMatchingBook(title: String, author: String?)

        var errorDescription: String? {
            switch self {
            case .malformedFile(let underlying):
                return "Not a valid Crux notes file: \(underlying.localizedDescription)"
            case .unsupportedVersion(let v):
                return "This bundle uses format version \(v), which this version of Crux can't read. Try updating Crux."
            case .noMatchingBook(let title, let author):
                let authorClause = author.map { " by \($0)" } ?? ""
                return "Couldn't find \"\(title)\"\(authorClause) in your library. Import the EPUB first, then re-import the notes."
            }
        }
    }

    /// Serializes a bundle to pretty-printed JSON. Sorted keys keep
    /// the file diff-friendly so users can stash bundles in git if
    /// they want to.
    func encode(_ bundle: CruxNotesBundle) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(bundle)
    }

    func decode(_ data: Data) throws -> CruxNotesBundle {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let bundle = try decoder.decode(CruxNotesBundle.self, from: data)
            guard bundle.formatVersion <= CruxNotesBundle.currentFormatVersion else {
                throw ImportError.unsupportedVersion(bundle.formatVersion)
            }
            return bundle
        } catch let error as ImportError {
            throw error
        } catch {
            throw ImportError.malformedFile(underlying: error)
        }
    }

    func write(_ bundle: CruxNotesBundle, to url: URL) throws {
        let data = try encode(bundle)
        try data.write(to: url, options: [.atomic])
    }

    func read(from url: URL) throws -> CruxNotesBundle {
        let data = try Data(contentsOf: url)
        return try decode(data)
    }

    /// Merge an imported bundle's annotations into an existing
    /// `BookAnnotations`. De-duplicates by highlight `id` and bookmark
    /// `id` — collisions keep the existing entry (we assume the local
    /// copy is more recent unless the user explicitly wanted a wipe).
    ///
    /// Returns the merged annotations plus a small summary the UI can
    /// surface ("imported 12 highlights, 3 bookmarks; skipped 4
    /// duplicates"). Net non-destructive — never deletes anything.
    func merge(
        bundle: CruxNotesBundle,
        into existing: BookAnnotations
    ) -> (merged: BookAnnotations, summary: MergeSummary) {
        var merged = existing
        let existingHighlightIds = Set(existing.highlights.map(\.id))
        let existingBookmarkIds = Set(existing.bookmarks.map(\.id))
        var addedHighlights = 0
        var addedBookmarks = 0
        var skippedHighlights = 0
        var skippedBookmarks = 0

        for highlight in bundle.annotations.highlights {
            if existingHighlightIds.contains(highlight.id) {
                skippedHighlights += 1
                continue
            }
            merged.highlights.append(highlight)
            addedHighlights += 1
        }

        for bookmark in bundle.annotations.bookmarks {
            if existingBookmarkIds.contains(bookmark.id) {
                skippedBookmarks += 1
                continue
            }
            merged.bookmarks.append(bookmark)
            addedBookmarks += 1
        }

        // Re-sort bookmarks the way `BookAnnotations.addBookmark` does
        // so the merged file matches what addBookmark would have built.
        merged.bookmarks.sort { lhs, rhs in
            if lhs.chapterIndex == rhs.chapterIndex {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.chapterIndex < rhs.chapterIndex
        }

        return (merged, MergeSummary(
            addedHighlights: addedHighlights,
            addedBookmarks: addedBookmarks,
            skippedHighlights: skippedHighlights,
            skippedBookmarks: skippedBookmarks
        ))
    }

    struct MergeSummary {
        let addedHighlights: Int
        let addedBookmarks: Int
        let skippedHighlights: Int
        let skippedBookmarks: Int

        var humanReadable: String {
            var parts: [String] = []
            if addedHighlights > 0 {
                parts.append("\(addedHighlights) highlight\(addedHighlights == 1 ? "" : "s")")
            }
            if addedBookmarks > 0 {
                parts.append("\(addedBookmarks) bookmark\(addedBookmarks == 1 ? "" : "s")")
            }
            let added = parts.isEmpty ? "Nothing new added" : "Added " + parts.joined(separator: ", ")
            let skipped = (skippedHighlights + skippedBookmarks)
            if skipped == 0 { return added + "." }
            return "\(added); skipped \(skipped) duplicate\(skipped == 1 ? "" : "s")."
        }
    }
}

/// Custom UTType registered for the `.cruxnotes` extension. Lets
/// `NSSavePanel` / `NSOpenPanel` filter to bundle files and gives
/// Finder a meaningful description.
extension UTType {
    static let cruxNotesBundle = UTType(
        exportedAs: "com.crux.notes-bundle",
        conformingTo: .json
    )
}
