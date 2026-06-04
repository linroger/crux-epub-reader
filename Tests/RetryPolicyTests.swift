import XCTest
@testable import Crux

final class RetryPolicyTests: XCTestCase {

    // MARK: - Transient classification

    func testTimeoutIsTransient() {
        XCTAssertTrue(RetryPolicy.isTransient(AIProviderError.timeout))
    }

    func testRateLimitIsTransient() {
        XCTAssertTrue(RetryPolicy.isTransient(AIProviderError.rateLimitExceeded))
    }

    func testNetworkErrorIsTransient() {
        let underlying = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        XCTAssertTrue(RetryPolicy.isTransient(AIProviderError.networkError(underlying)))
    }

    func testServerErrorsAreTransient() {
        XCTAssertTrue(RetryPolicy.isTransient(AIProviderError.apiError(statusCode: 500, message: "x")))
        XCTAssertTrue(RetryPolicy.isTransient(AIProviderError.apiError(statusCode: 502, message: "x")))
        XCTAssertTrue(RetryPolicy.isTransient(AIProviderError.apiError(statusCode: 503, message: "x")))
    }

    func testTooManyRequestsAndTimeoutHTTPAreTransient() {
        XCTAssertTrue(RetryPolicy.isTransient(AIProviderError.apiError(statusCode: 408, message: "x")))
        XCTAssertTrue(RetryPolicy.isTransient(AIProviderError.apiError(statusCode: 429, message: "x")))
    }

    func testClientErrorsAreNotTransient() {
        XCTAssertFalse(RetryPolicy.isTransient(AIProviderError.apiError(statusCode: 400, message: "x")))
        XCTAssertFalse(RetryPolicy.isTransient(AIProviderError.apiError(statusCode: 401, message: "x")))
        XCTAssertFalse(RetryPolicy.isTransient(AIProviderError.apiError(statusCode: 404, message: "x")))
    }

    func testConfigErrorsAreNotTransient() {
        XCTAssertFalse(RetryPolicy.isTransient(AIProviderError.invalidConfiguration))
        XCTAssertFalse(RetryPolicy.isTransient(AIProviderError.missingAPIKey))
        XCTAssertFalse(RetryPolicy.isTransient(AIProviderError.invalidBaseURL))
        XCTAssertFalse(RetryPolicy.isTransient(AIProviderError.invalidResponse))
    }

    func testURLErrorDomainTimeoutIsTransient() {
        let err = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        XCTAssertTrue(RetryPolicy.isTransient(err))
    }

    func testURLErrorDomainCancelIsNotTransient() {
        let err = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        XCTAssertFalse(RetryPolicy.isTransient(err))
    }

    // MARK: - execute()

    func testSucceedsImmediately() async throws {
        var attempts = 0
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: .milliseconds(1), maxDelay: .milliseconds(10))
        let result = try await policy.execute { () -> String in
            attempts += 1
            return "ok"
        }
        XCTAssertEqual(result, "ok")
        XCTAssertEqual(attempts, 1)
    }

    func testRetriesOnTransientThenSucceeds() async throws {
        var attempts = 0
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: .milliseconds(1), maxDelay: .milliseconds(10))
        let result = try await policy.execute { () -> String in
            attempts += 1
            if attempts < 2 { throw AIProviderError.timeout }
            return "ok"
        }
        XCTAssertEqual(result, "ok")
        XCTAssertEqual(attempts, 2)
    }

    func testGivesUpAfterMaxAttempts() async {
        var attempts = 0
        let policy = RetryPolicy(maxAttempts: 2, baseDelay: .milliseconds(1), maxDelay: .milliseconds(2))
        do {
            _ = try await policy.execute { () -> String in
                attempts += 1
                throw AIProviderError.timeout
            }
            XCTFail("expected to throw after exhausting retries")
        } catch {
            XCTAssertTrue(error is AIProviderError)
        }
        XCTAssertEqual(attempts, 2)
    }

    func testDoesNotRetryOnPermanentError() async {
        var attempts = 0
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: .milliseconds(1), maxDelay: .milliseconds(2))
        do {
            _ = try await policy.execute { () -> String in
                attempts += 1
                throw AIProviderError.missingAPIKey
            }
            XCTFail("expected to throw")
        } catch {}
        XCTAssertEqual(attempts, 1)
    }
}
