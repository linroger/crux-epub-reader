import Foundation

/// Exponential-backoff retry helper for transient network/API failures.
///
/// Wraps an async throwing operation and retries it when it raises an
/// `AIProviderError` the policy classifies as transient (network, timeout,
/// rate limit, certain HTTP 5xx). Non-transient errors propagate
/// immediately so users see meaningful failures (bad API key, 4xx
/// validation errors, etc.).
struct RetryPolicy: Sendable {
    /// Maximum number of attempts including the initial try.
    var maxAttempts: Int = 3

    /// Base delay before the second attempt; doubles each subsequent retry.
    var baseDelay: Duration = .milliseconds(800)

    /// Upper bound to avoid pathological multi-minute waits.
    var maxDelay: Duration = .seconds(15)

    /// Default policy: 3 attempts, 0.8s → 1.6s → 3.2s with 15s ceiling.
    static let `default` = RetryPolicy()

    /// Policy disabled — single attempt, no retry.
    static let none = RetryPolicy(maxAttempts: 1)

    /// Execute the operation with the configured retry behavior.
    func execute<T>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        var attempt = 0
        var lastError: Error?

        while attempt < maxAttempts {
            attempt += 1
            do {
                return try await operation()
            } catch {
                lastError = error
                guard attempt < maxAttempts, Self.isTransient(error) else {
                    throw error
                }
                let delay = backoffDelay(for: attempt)
                AppLog.ai.info(
                    "Transient AI request error on attempt \(attempt, privacy: .public)/\(maxAttempts, privacy: .public); retrying in \(delay.components.seconds, privacy: .public)s. error=\(error.localizedDescription, privacy: .public)"
                )
                try await Task.sleep(for: delay)
            }
        }

        // Should be unreachable; only reach here if maxAttempts == 0.
        throw lastError ?? AIProviderError.invalidResponse
    }

    // MARK: - Helpers

    private func backoffDelay(for attempt: Int) -> Duration {
        // baseDelay * 2^(attempt-1), capped by maxDelay
        let multiplier = 1 << max(0, attempt - 1)
        let scaled = baseDelay * multiplier
        return scaled > maxDelay ? maxDelay : scaled
    }

    /// Classifies whether an error is worth retrying.
    static func isTransient(_ error: Error) -> Bool {
        if let providerError = error as? AIProviderError {
            switch providerError {
            case .networkError, .timeout, .rateLimitExceeded:
                return true
            case .apiError(let statusCode, _):
                // Retry on 5xx and 408/429
                return statusCode >= 500 || statusCode == 408 || statusCode == 429
            case .invalidConfiguration, .missingAPIKey, .invalidBaseURL, .invalidResponse:
                return false
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorTimedOut,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorNotConnectedToInternet,
                 NSURLErrorDNSLookupFailed:
                return true
            default:
                return false
            }
        }

        return false
    }
}

// Multiply Duration by an Int (Swift's Duration doesn't expose this directly).
private func * (lhs: Duration, rhs: Int) -> Duration {
    let value = lhs.components.seconds * Int64(rhs)
    let attoseconds = lhs.components.attoseconds * Int64(rhs)
    return Duration(secondsComponent: value, attosecondsComponent: attoseconds)
}
