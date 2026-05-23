import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

/// Indexes the user's library into Apple's `CSSearchableIndex` so books
/// are reachable from macOS Spotlight (and iOS Spotlight on iPad/iPhone).
///
/// Each `StoredBook` is exposed as a `CSSearchableItem` whose unique
/// identifier round-trips the `UUID` we use internally. The Crux app
/// declares the matching `CSSearchableItemActionType` in
/// `application(_:continue:restorationHandler:)`/`onContinueUserActivity`
/// — selecting a Spotlight result re-opens the book in a fresh window.
///
/// Why `actor`: indexing performs blocking I/O (Spotlight is backed by
/// metadata-server XPC). Funneling writes through an actor keeps any
/// concurrent imports/deletes from racing on the same domain identifier.
actor SpotlightIndexer {
    static let shared = SpotlightIndexer()

    /// Domain identifier scoping items so we can wipe just our index
    /// instead of touching anything else the user has indexed.
    static let domainIdentifier = "com.crux.library"

    /// Activity type the app advertises when a book is the focus. The
    /// Spotlight result handoff lands here too.
    static let activityType = "com.crux.openBook"

    /// User-info key carrying the StoredBook.id UUID string through the
    /// NSUserActivity continuation path.
    static let userInfoBookIDKey = "bookID"

    private let index = CSSearchableIndex.default()

    private init() {}

    // MARK: - Index Writes

    func indexBook(_ book: StoredBook) async {
        let item = makeSearchableItem(for: book)
        do {
            try await index.indexSearchableItems([item])
            AppLog.storage.debug("Indexed book in Spotlight: \(book.title, privacy: .public)")
        } catch {
            AppLog.storage.error("Spotlight index failed for \(book.title, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func indexBooks(_ books: [StoredBook]) async {
        guard !books.isEmpty else { return }
        let items = books.map { makeSearchableItem(for: $0) }
        do {
            try await index.indexSearchableItems(items)
            AppLog.storage.info("Indexed \(books.count, privacy: .public) book(s) in Spotlight")
        } catch {
            AppLog.storage.error("Spotlight batch index failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func unindexBook(id: UUID) async {
        do {
            try await index.deleteSearchableItems(withIdentifiers: [id.uuidString])
            AppLog.storage.debug("Removed book \(id.uuidString, privacy: .public) from Spotlight")
        } catch {
            AppLog.storage.error("Spotlight delete failed for \(id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Drop every Crux-owned Spotlight entry. Useful when the user
    /// wipes their library or hits a "rebuild index" diagnostic.
    func clearAll() async {
        do {
            try await index.deleteSearchableItems(withDomainIdentifiers: [Self.domainIdentifier])
        } catch {
            AppLog.storage.error("Spotlight clear failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Item Construction

    private func makeSearchableItem(for book: StoredBook) -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: UTType.epub)
        attrs.title = book.title
        attrs.displayName = book.title
        attrs.contentDescription = compositeDescription(for: book)
        attrs.identifier = book.id.uuidString

        if let author = book.author, !author.isEmpty {
            attrs.authorNames = [author]
        }
        if let publisher = book.publisher, !publisher.isEmpty {
            attrs.publishers = [publisher]
        }
        if let year = book.publicationYear {
            // Construct an approximate content-creation date for the
            // year-based metadata so Spotlight sorts books temporally.
            var components = DateComponents()
            components.year = year
            components.month = 1
            components.day = 1
            if let date = Calendar(identifier: .gregorian).date(from: components) {
                attrs.contentCreationDate = date
            }
        }
        let subjectKeywords = book.subjects.filter { !$0.isEmpty }
        let tagKeywords = book.tags.filter { !$0.isEmpty }
        let allKeywords = subjectKeywords + tagKeywords
        if !allKeywords.isEmpty {
            attrs.keywords = Array(allKeywords.prefix(64))
        }
        if let cover = book.coverImageData {
            attrs.thumbnailData = cover
        }

        let item = CSSearchableItem(
            uniqueIdentifier: book.id.uuidString,
            domainIdentifier: Self.domainIdentifier,
            attributeSet: attrs
        )
        // Long lifetime — entries should survive between launches; the
        // index is rebuilt incrementally on import/delete and fully on
        // a forced reindex.
        item.expirationDate = Date.distantFuture
        return item
    }

    private func compositeDescription(for book: StoredBook) -> String {
        // Spotlight surfaces this body text in result rows. Lead with
        // the publisher's blurb when we have one, then fall back to a
        // synthesized description from authoring/year/progress so empty
        // EPUBs still get something legible.
        if let blurb = book.bookDescription, !blurb.isEmpty {
            return blurb
        }

        var parts: [String] = []
        if let author = book.author { parts.append("by \(author)") }
        if let year = book.publicationYear { parts.append("\(year)") }
        if book.isFinished {
            parts.append("Finished")
        } else if book.totalChapters > 0 {
            let percent = Int(Double(book.currentChapterIndex) / Double(book.totalChapters) * 100)
            parts.append("\(percent)% read")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - UTType convenience

private extension UTType {
    /// Spotlight needs the public EPUB type identifier — `UTType.epub`
    /// is defined on macOS 14+, but providing a defensive fallback
    /// keeps the project resilient if the SDK ever stops shipping it.
    static var epub: UTType {
        UTType("org.idpf.epub-container") ?? .data
    }
}
