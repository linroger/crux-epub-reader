import Foundation

/// Protocol for AI provider implementations
protocol AIProvider: Sendable {
    /// Unique identifier for the provider
    var id: UUID { get }

    /// Display name of the provider
    var name: String { get }

    /// Provider type
    var type: ProviderType { get }

    /// Whether this provider supports streaming responses
    var supportsStreaming: Bool { get }

    /// Generate a response for the given text selection
    /// - Parameters:
    ///   - selection: The selected text to analyze
    ///   - context: Optional surrounding context
    ///   - conversationHistory: Previous messages in the thread
    /// - Returns: Generated response text
    func generateResponse(
        for selection: String,
        context: String?,
        conversationHistory: [ThreadMessage]
    ) async throws -> String

    /// Stream a response for the given text selection (optional)
    /// - Parameters:
    ///   - selection: The selected text to analyze
    ///   - context: Optional surrounding context
    ///   - conversationHistory: Previous messages in the thread
    /// - Returns: Async stream of response chunks
    func streamResponse(
        for selection: String,
        context: String?,
        conversationHistory: [ThreadMessage]
    ) async throws -> AsyncThrowingStream<String, Error>
}

// MARK: - Default Streaming Implementation

extension AIProvider {
    /// Default implementation that falls back to non-streaming
    func streamResponse(
        for selection: String,
        context: String?,
        conversationHistory: [ThreadMessage]
    ) async throws -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let response = try await generateResponse(
                        for: selection,
                        context: context,
                        conversationHistory: conversationHistory
                    )
                    continuation.yield(response)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - AI Provider Errors

enum AIProviderError: LocalizedError {
    case invalidConfiguration
    case missingAPIKey
    case invalidBaseURL
    case networkError(Error)
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case rateLimitExceeded
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Provider configuration is invalid"
        case .missingAPIKey:
            return "API key is missing or empty"
        case .invalidBaseURL:
            return "Base URL is invalid or malformed"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Received invalid response from API"
        case .apiError(let statusCode, let message):
            return "API error (\(statusCode)): \(message)"
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please try again later."
        case .timeout:
            return "Request timed out. Please check your connection."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .invalidConfiguration:
            return "Check provider settings and try again"
        case .missingAPIKey:
            return "Add your API key in Settings > AI Providers"
        case .invalidBaseURL:
            return "Verify the base URL in provider settings"
        case .networkError:
            return "Check your internet connection and try again"
        case .invalidResponse:
            return "The API returned an unexpected format. Please try again."
        case .apiError:
            return "Check your API key and account status"
        case .rateLimitExceeded:
            return "Wait a few moments before sending another request"
        case .timeout:
            return "Check your internet connection and try again"
        }
    }
}

// MARK: - Provider Factory

actor AIProviderFactory {
    /// Create a provider instance from configuration
    static func createProvider(from config: AIProviderConfig) throws -> any AIProvider {
        guard config.isValid else {
            throw AIProviderError.invalidConfiguration
        }

        switch config.providerType {
        case .claude:
            return ClaudeProvider(
                id: config.id,
                name: config.name,
                apiKey: config.apiKey,
                baseURL: config.baseURL,
                model: config.model
            )

        case .openai:
            return OpenAIProvider(
                id: config.id,
                name: config.name,
                apiKey: config.apiKey,
                baseURL: config.baseURL,
                model: config.model
            )

        case .custom:
            guard let baseURL = config.baseURL else {
                throw AIProviderError.invalidBaseURL
            }
            return CustomProvider(
                id: config.id,
                name: config.name,
                apiKey: config.apiKey,
                baseURL: baseURL,
                model: config.model
            )
        }
    }
}
