import XCTest
@testable import Crux

final class CruxNotesBundleTests: XCTestCase {

    // MARK: - Round-trip

    func testEncodeDecodeRoundTrip() async throws {
        let bundle = makeBundle()
        let io = CruxNotesIO.shared
        let data = try await io.encode(bundle)
        let decoded = try await io.decode(data)

        XCTAssertEqual(decoded.formatVersion, bundle.formatVersion)
        XCTAssertEqual(decoded.bookId, bundle.bookId)
        XCTAssertEqual(decoded.bookTitle, bundle.bookTitle)
        XCTAssertEqual(decoded.bookAuthor, bundle.bookAuthor)
        XCTAssertEqual(decoded.annotations.bookId, bundle.annotations.bookId)
        XCTAssertEqual(decoded.annotations.highlights.count, bundle.annotations.highlights.count)
        XCTAssertEqual(decoded.annotations.bookmarks.count, bundle.annotations.bookmarks.count)
    }

    // MARK: - Format version

    func testRejectsFutureFormatVersion() async {
        // Hand-rolled JSON claiming a version higher than the current
        // import code understands.
        let future = CruxNotesBundle.currentFormatVersion + 5
        let json = """
        {
          "formatVersion": \(future),
          "bookId": "11111111-2222-3333-4444-555555555555",
          "bookTitle": "Some Book",
          "bookAuthor": null,
          "exportedAt": "2026-05-23T08:00:00Z",
          "annotations": { "bookId": "11111111-2222-3333-4444-555555555555", "highlights": [], "bookmarks": [], "updatedAt": "2026-05-23T08:00:00Z" }
        }
        """.data(using: .utf8)!

        do {
            _ = try await CruxNotesIO.shared.decode(json)
            XCTFail("expected an unsupportedVersion throw")
        } catch CruxNotesIO.ImportError.unsupportedVersion(let v) {
            XCTAssertEqual(v, future)
        } catch {
            XCTFail("expected unsupportedVersion, got \(error)")
        }
    }

    func testRejectsMalformedJSON() async {
        let junk = "this is not json".data(using: .utf8)!
        do {
            _ = try await CruxNotesIO.shared.decode(junk)
            XCTFail("expected a malformedFile throw")
        } catch CruxNotesIO.ImportError.malformedFile {
            // expected
        } catch {
            XCTFail("expected malformedFile, got \(error)")
        }
    }

    // MARK: - Merge

    func testMergeAddsNewHighlightsAndSkipsDuplicates() async {
        let bookId = UUID()
        let sharedHighlightId = UUID()
        let existing = BookAnnotations(
            bookId: bookId,
            highlights: [
                Highlight(
                    id: sharedHighlightId,
                    chapterId: "ch1",
                    selectedText: "shared",
                    surroundingContext: "shared context"
                )
            ]
        )
        let bundleAnnotations = BookAnnotations(
            bookId: bookId,
            highlights: [
                // Duplicate — same id as `existing`; should be skipped.
                Highlight(
                    id: sharedHighlightId,
                    chapterId: "ch1",
                    selectedText: "shared",
                    surroundingContext: "shared context"
                ),
                // New highlight; should be added.
                Highlight(
                    chapterId: "ch2",
                    selectedText: "new",
                    surroundingContext: "new context"
                )
            ]
        )
        let bundle = CruxNotesBundle(
            bookId: bookId,
            bookTitle: "Title",
            bookAuthor: "Author",
            annotations: bundleAnnotations
        )

        let (merged, summary) = await CruxNotesIO.shared.merge(bundle: bundle, into: existing)
        XCTAssertEqual(merged.highlights.count, 2)
        XCTAssertEqual(summary.addedHighlights, 1)
        XCTAssertEqual(summary.skippedHighlights, 1)
    }

    func testMergeSummaryHumanReadable() {
        let summary = CruxNotesIO.MergeSummary(
            addedHighlights: 3,
            addedBookmarks: 1,
            skippedHighlights: 2,
            skippedBookmarks: 0
        )
        let text = summary.humanReadable
        XCTAssertTrue(text.contains("3 highlights"))
        XCTAssertTrue(text.contains("1 bookmark"))
        XCTAssertTrue(text.contains("2 duplicate"))
    }

    func testMergeSummaryHumanReadableNothingAdded() {
        let summary = CruxNotesIO.MergeSummary(
            addedHighlights: 0,
            addedBookmarks: 0,
            skippedHighlights: 5,
            skippedBookmarks: 0
        )
        XCTAssertTrue(summary.humanReadable.contains("Nothing new added"))
        XCTAssertTrue(summary.humanReadable.contains("5 duplicate"))
    }

    // MARK: - Helpers

    private func makeBundle() -> CruxNotesBundle {
        let bookId = UUID()
        let annotations = BookAnnotations(
            bookId: bookId,
            highlights: [
                Highlight(
                    chapterId: "ch1",
                    selectedText: "Hello",
                    surroundingContext: "Hello, world.",
                    annotation: "First line"
                )
            ],
            bookmarks: [
                Bookmark(
                    chapterId: "ch1",
                    chapterIndex: 0,
                    chapterTitle: "Opening",
                    note: "page mark"
                )
            ]
        )
        return CruxNotesBundle(
            bookId: bookId,
            bookTitle: "A Tale of Two Tests",
            bookAuthor: "Author",
            annotations: annotations
        )
    }
}
