import XCTest
@testable import Crux

final class ReadingTimeEstimatorTests: XCTestCase {

    // MARK: - Word counting

    func testWordCountIgnoresWhitespaceVariations() {
        XCTAssertEqual(ReadingTimeEstimator.wordCount(in: "one two three"), 3)
        XCTAssertEqual(ReadingTimeEstimator.wordCount(in: "  one   two\nthree\t\tfour "), 4)
    }

    func testWordCountEmptyInput() {
        XCTAssertEqual(ReadingTimeEstimator.wordCount(in: ""), 0)
        XCTAssertEqual(ReadingTimeEstimator.wordCount(in: "   \n\t   "), 0)
    }

    // MARK: - HTML stripping

    func testStripHTMLRemovesTagsButKeepsText() {
        let html = "<p>Hello <em>world</em></p><p>How <strong>are</strong> you?</p>"
        let stripped = ReadingTimeEstimator.stripHTML(html)
        XCTAssertEqual(stripped, "Hello world How are you?")
    }

    func testStripHTMLCollapsesEntitiesAndWhitespace() {
        let html = "<div>\n   line1   \n\n   line2   \n</div>"
        XCTAssertEqual(ReadingTimeEstimator.stripHTML(html), "line1 line2")
    }

    // MARK: - Estimates

    func testMinutesNilForEmpty() {
        XCTAssertNil(ReadingTimeEstimator.minutes(forText: ""))
        XCTAssertNil(ReadingTimeEstimator.minutes(forText: "<p></p>"))
    }

    func testMinutesAtDefaultWPM() {
        // 440 words / 220 wpm = 2 minutes
        let text = Array(repeating: "word", count: 440).joined(separator: " ")
        let minutes = ReadingTimeEstimator.minutes(forText: text)
        XCTAssertNotNil(minutes)
        XCTAssertEqual(minutes!, 2.0, accuracy: 0.001)
    }

    func testMinutesScalesWithWPM() {
        let text = Array(repeating: "word", count: 600).joined(separator: " ")
        // At 300 WPM that's 2 minutes
        XCTAssertEqual(ReadingTimeEstimator.minutes(forText: text, wordsPerMinute: 300)!, 2.0, accuracy: 0.001)
    }

    // MARK: - Labels

    func testLabelLessThanAMinute() {
        XCTAssertEqual(ReadingTimeEstimator.label(forMinutes: 0.4), "less than a minute")
    }

    func testLabelMinutesUnder60() {
        XCTAssertEqual(ReadingTimeEstimator.label(forMinutes: 12.0), "12 min read")
        XCTAssertEqual(ReadingTimeEstimator.label(forMinutes: 59.49), "59 min read")
    }

    func testLabelExactHour() {
        XCTAssertEqual(ReadingTimeEstimator.label(forMinutes: 60), "1 hr read")
    }

    func testLabelHoursAndMinutes() {
        XCTAssertEqual(ReadingTimeEstimator.label(forMinutes: 135), "2 hr 15 min read")
    }

    // MARK: - totalMinutes for chapters

    func testTotalMinutesSumsAcrossChapters() {
        let chapter1 = Array(repeating: "x", count: 110).joined(separator: " ") // 0.5 min
        let chapter2 = Array(repeating: "x", count: 220).joined(separator: " ") // 1.0 min
        let total = ReadingTimeEstimator.totalMinutes(forChapters: [chapter1, chapter2])
        XCTAssertEqual(total, 1.5, accuracy: 0.001)
    }
}
