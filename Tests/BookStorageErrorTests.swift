import XCTest
@testable import Crux

final class BookStorageErrorTests: XCTestCase {

    func testInsufficientDiskSpaceMessageIncludesBothSizes() {
        let error = BookStorageError.insufficientDiskSpace(
            needed: 100 * 1024 * 1024,
            available: 5 * 1024 * 1024
        )
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("MB"), "expected size formatting, got: \(description)")
        XCTAssertTrue(description.contains("space"), "expected human phrasing about disk space")
    }

    func testSourceNotReadableMessageNamesTheFile() {
        let url = URL(fileURLWithPath: "/tmp/example.epub")
        let error = BookStorageError.sourceNotReadable(url)
        XCTAssertTrue(error.errorDescription?.contains("example.epub") ?? false)
    }

    func testCopyFailedMessageIncludesUnderlying() {
        let url = URL(fileURLWithPath: "/tmp/example.epub")
        let underlying = NSError(
            domain: "test",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "Underlying boom"]
        )
        let error = BookStorageError.copyFailed(url, underlying: underlying)
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("example.epub"))
        XCTAssertTrue(description.contains("Underlying boom"))
    }
}
