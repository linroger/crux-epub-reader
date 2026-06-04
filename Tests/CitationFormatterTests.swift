import XCTest
@testable import Crux

final class CitationFormatterTests: XCTestCase {

    // MARK: - Helpers

    private func makeBook(
        title: String = "Pride and Prejudice",
        author: String? = "Jane Austen",
        publisher: String? = "T. Egerton",
        year: Int? = 1813
    ) -> Book {
        var metadata = BookMetadata()
        metadata.publisher = publisher
        if let year {
            var comps = DateComponents()
            comps.year = year
            metadata.publicationDate = Calendar(identifier: .gregorian).date(from: comps)
        }
        return Book(
            fileURL: URL(fileURLWithPath: "/tmp/test.epub"),
            title: title,
            author: author,
            metadata: metadata
        )
    }

    // MARK: - APA

    func testAPABasic() {
        let book = makeBook()
        let cite = CitationFormatter.citation(for: book, style: .apa)
        // "Austen, J. (1813). *Pride and Prejudice*. T. Egerton."
        XCTAssertTrue(cite.contains("Austen, J."), "missing inverted author: \(cite)")
        XCTAssertTrue(cite.contains("(1813)"), "missing year: \(cite)")
        XCTAssertTrue(cite.contains("*Pride and Prejudice*"), "missing italicized title: \(cite)")
        XCTAssertTrue(cite.contains("T. Egerton"), "missing publisher: \(cite)")
    }

    func testAPAUsesNDWhenYearMissing() {
        let book = makeBook(year: nil)
        let cite = CitationFormatter.citation(for: book, style: .apa)
        XCTAssertTrue(cite.contains("(n.d.)"))
    }

    func testAPAHandlesMissingAuthorGracefully() {
        let book = makeBook(author: nil)
        let cite = CitationFormatter.citation(for: book, style: .apa)
        XCTAssertFalse(cite.contains(", J.")) // no inverted-form leftovers
        XCTAssertTrue(cite.contains("*Pride and Prejudice*"))
    }

    // MARK: - MLA

    func testMLABasic() {
        let book = makeBook()
        let cite = CitationFormatter.citation(for: book, style: .mla)
        // "Austen, Jane. *Pride and Prejudice*. T. Egerton, 1813."
        XCTAssertTrue(cite.contains("Austen, Jane"))
        XCTAssertTrue(cite.contains("*Pride and Prejudice*"))
        XCTAssertTrue(cite.contains("T. Egerton, 1813"))
    }

    // MARK: - Chicago

    func testChicagoBasic() {
        let book = makeBook()
        let cite = CitationFormatter.citation(for: book, style: .chicago)
        // "Jane Austen, *Pride and Prejudice* (T. Egerton, 1813)."
        XCTAssertTrue(cite.contains("Jane Austen,"))
        XCTAssertTrue(cite.contains("*Pride and Prejudice*"))
        XCTAssertTrue(cite.contains("(T. Egerton, 1813)"))
    }

    // MARK: - BibTeX

    func testBibTeXBasic() {
        let book = makeBook()
        let cite = CitationFormatter.citation(for: book, style: .bibtex)
        // "@book{austen1813, …}"
        XCTAssertTrue(cite.hasPrefix("@book{austen1813,"), "wrong key: \(cite)")
        XCTAssertTrue(cite.contains("author = {Jane Austen}"))
        XCTAssertTrue(cite.contains("title = {Pride and Prejudice}"))
        XCTAssertTrue(cite.contains("publisher = {T. Egerton}"))
        XCTAssertTrue(cite.contains("year = {1813}"))
    }

    func testBibTeXKeyFallsBackToTitleWhenAuthorMissing() {
        let book = makeBook(author: nil)
        let cite = CitationFormatter.citation(for: book, style: .bibtex)
        // Slug from title; key shouldn't start with "@book{ ,"
        XCTAssertTrue(cite.hasPrefix("@book{"))
        XCTAssertFalse(cite.contains("austen"))
    }

    func testBibTeXMultipleAuthors() {
        let book = makeBook(author: "Jane Austen and Mary Shelley")
        let cite = CitationFormatter.citation(for: book, style: .bibtex)
        XCTAssertTrue(cite.contains("author = {Jane Austen and Mary Shelley}"))
    }
}
