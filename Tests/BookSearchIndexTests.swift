import XCTest
@testable import Crux

@MainActor
final class BookSearchIndexTests: XCTestCase {

    func testEmptyIndexReturnsNoHits() {
        let index = BookSearchIndex()
        XCTAssertTrue(index.search("anything").isEmpty)
    }

    func testBuildPopulatesChapters() {
        let index = BookSearchIndex()
        index.build(from: [
            (index: 0, id: "ch1", title: "One", html: "<p>Hello world.</p>"),
            (index: 1, id: "ch2", title: "Two", html: "<p>Another chapter.</p>"),
        ])
        XCTAssertEqual(index.chapters.count, 2)
        XCTAssertEqual(index.chapters[0].chapterTitle, "One")
        XCTAssertEqual(index.chapters[1].chapterIndex, 1)
    }

    func testSearchFindsHitsAcrossChapters() {
        let index = BookSearchIndex()
        index.build(from: [
            (index: 0, id: "ch1", title: "One", html: "<p>The fox jumps.</p>"),
            (index: 1, id: "ch2", title: "Two", html: "<p>The fox dreams.</p>"),
        ])
        let hits = index.search("fox")
        XCTAssertEqual(hits.count, 2)
        XCTAssertEqual(hits[0].chapterIndex, 0)
        XCTAssertEqual(hits[1].chapterIndex, 1)
        XCTAssertTrue(hits[0].snippet.lowercased().contains("fox"))
    }

    func testSearchIsCaseInsensitive() {
        let index = BookSearchIndex()
        index.build(from: [
            (index: 0, id: "ch1", title: "One", html: "<p>SCREAMING capitalization!</p>")
        ])
        XCTAssertEqual(index.search("screaming").count, 1)
        XCTAssertEqual(index.search("SCREAMING").count, 1)
    }

    func testEmptyQueryReturnsNoHits() {
        let index = BookSearchIndex()
        index.build(from: [
            (index: 0, id: "ch1", title: "One", html: "<p>Content here.</p>")
        ])
        XCTAssertTrue(index.search("").isEmpty)
        XCTAssertTrue(index.search("   ").isEmpty)
    }

    func testSearchStripsHTMLBeforeMatching() {
        let index = BookSearchIndex()
        // Make sure the search index doesn't match against tag names —
        // a search for "p" must not return every <p> in the chapter.
        index.build(from: [
            (index: 0, id: "ch1", title: "One", html: "<p>just words</p><p>more words</p>")
        ])
        XCTAssertEqual(index.search("words").count, 2)
        // The plain text is "just words more words" — searching for
        // the literal tag should not match.
        let plain = index.chapters[0].plain
        XCTAssertFalse(plain.contains("<p>"))
    }
}
