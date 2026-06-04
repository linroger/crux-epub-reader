import XCTest
@testable import Crux

final class LocalProviderURLTests: XCTestCase {

    func testTrimmedTrailingSlashRemovesSingle() {
        XCTAssertEqual("http://localhost:11434/".trimmedTrailingSlash, "http://localhost:11434")
    }

    func testTrimmedTrailingSlashRemovesMultiple() {
        XCTAssertEqual("http://localhost:11434///".trimmedTrailingSlash, "http://localhost:11434")
    }

    func testTrimmedTrailingSlashIdempotent() {
        XCTAssertEqual("http://localhost:11434".trimmedTrailingSlash, "http://localhost:11434")
    }

    func testAppendingPathHandlesLeadingSlash() {
        let base = "http://localhost:11434".trimmedTrailingSlash
        XCTAssertEqual(base.appendingPath("/api/tags"), "http://localhost:11434/api/tags")
    }

    func testAppendingPathAddsSlashWhenMissing() {
        let base = "http://localhost:11434".trimmedTrailingSlash
        XCTAssertEqual(base.appendingPath("api/tags"), "http://localhost:11434/api/tags")
    }
}
