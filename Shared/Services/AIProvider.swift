import Foundation

/// A single image handed to a vision-capable model alongside the prompt.
/// Carries either an inline `data:<mime>;base64,…` URI (the common case —
/// EPUB figures are inlined as data URIs) or a remote `http(s)` URL.
struct AIImageAttachment: Sendable, Equatable {
    /// `data:<mime>;base64,<payload>` or an `http(s)://…` URL.
    let url: String

    init(url: String) { self.url = url }

    var isDataURI: Bool { url.hasPrefix("data:") }

    /// Splits a data URI into (mediaType, base64payload) for providers that
    /// need them separately (Anthropic's `image` block). Returns nil for
    /// remote URLs or malformed data URIs.
    var base64Components: (mediaType: String, data: String)? {
        guard isDataURI,
              let semi = url.firstIndex(of: ";"),
              let comma = url.firstIndex(of: ","),
              url.distance(from: url.startIndex, to: semi) > 5 else { return nil }
        let mediaType = String(url[url.index(url.startIndex, offsetBy: 5)..<semi])
        let payload = String(url[url.index(after: comma)...])
        guard !mediaType.isEmpty, !payload.isEmpty else { return nil }
        return (mediaType, payload)
    }
}

/// Bundle of optional knobs that the manager forwards to every provider
/// request. Lets us extend behavior (custom prompt, temperature, etc)
/// without breaking the protocol every time.
struct AIRequestOptions: Sendable {
    /// User-customized system prompt that overrides the provider's
    /// built-in default. `nil` means "use built-in".
    var systemPrompt: String?

    /// Sampling temperature override. `nil` means provider default.
    var temperature: Double?

    /// Images attached to the *first* user turn for vision-capable models.
    /// Empty for text-only requests. Callers should only populate this when
    /// the active provider reports `providerType.supportsVision`.
    var images: [AIImageAttachment]

    static let `default` = AIRequestOptions()

    init(systemPrompt: String? = nil, temperature: Double? = nil, images: [AIImageAttachment] = []) {
        self.systemPrompt = systemPrompt
        self.temperature = temperature
        self.images = images
    }
}

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
    ///   - options: Optional knobs (custom prompt, temperature, etc).
    /// - Returns: Generated response text
    func generateResponse(
        for selection: String,
        context: String?,
        conversationHistory: [ThreadMessage],
        options: AIRequestOptions
    ) async throws -> String

    /// Stream a response for the given text selection. The default
    /// implementation falls back to `generateResponse` and yields the full
    /// result as a single chunk; providers that natively support streaming
    /// override this to emit tokens as they arrive.
    func streamResponse(
        for selection: String,
        context: String?,
        conversationHistory: [ThreadMessage],
        options: AIRequestOptions
    ) async throws -> AsyncThrowingStream<String, Error>
}

// MARK: - Default implementations

extension AIProvider {
    /// Convenience overload used by callers that don't need to override
    /// the system prompt. Calls into the options-aware overload with the
    /// defaults.
    func generateResponse(
        for selection: String,
        context: String?,
        conversationHistory: [ThreadMessage]
    ) async throws -> String {
        try await generateResponse(
            for: selection,
            context: context,
            conversationHistory: conversationHistory,
            options: .default
        )
    }

    /// Default streaming implementation that just wraps `generateResponse`.
    /// Providers with native streaming should override this.
    func streamResponse(
        for selection: String,
        context: String?,
        conversationHistory: [ThreadMessage],
        options: AIRequestOptions
    ) async throws -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let response = try await generateResponse(
                        for: selection,
                        context: context,
                        conversationHistory: conversationHistory,
                        options: options
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
    /// Create a provider instance from configuration (synchronous - uses sync Keychain access)
    /// Prefer createProviderAsync() when possible
    static func createProvider(from config: AIProviderConfig) throws -> any AIProvider {
        guard config.isValid else {
            throw AIProviderError.invalidConfiguration
        }
        
        // Use synchronous API key access (blocks briefly)
        let apiKey = config.apiKey

        switch config.providerType {
        case .claude:
            return ClaudeProvider(
                id: config.id,
                name: config.name,
                apiKey: apiKey,
                baseURL: config.baseURL,
                model: config.model
            )

        case .openai:
            return OpenAIProvider(
                id: config.id,
                name: config.name,
                apiKey: apiKey,
                baseURL: config.baseURL,
                model: config.model
            )

        case .deepseek, .minimax, .kimi, .qwen:
            // OpenAI-compatible cloud APIs — reuse the OpenAI client with the
            // provider's endpoint and default model.
            return OpenAIProvider(
                id: config.id,
                name: config.name,
                apiKey: apiKey,
                baseURL: config.baseURL ?? config.providerType.defaultBaseURL,
                model: config.model ?? config.providerType.defaultModels.first
            )

        case .appleIntelligence:
            #if canImport(FoundationModels)
            if #available(macOS 26.0, iOS 26.0, *) {
                return AppleIntelligenceProvider(
                    id: config.id,
                    name: config.name
                )
            }
            #endif
            throw AIProviderError.invalidConfiguration

        case .ollama:
            return OllamaProvider(
                id: config.id,
                name: config.name,
                baseURL: config.baseURL,
                model: config.model
            )

        case .lmstudio:
            return LMStudioProvider(
                id: config.id,
                name: config.name,
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
                apiKey: apiKey,
                baseURL: baseURL,
                model: config.model
            )
        }
    }

    /// Create a provider instance from configuration (async - preferred)
    /// Uses proper async Keychain access without blocking
    static func createProviderAsync(from config: AIProviderConfig) async throws -> any AIProvider {
        guard await config.isValidAsync() else {
            throw AIProviderError.invalidConfiguration
        }
        
        // Use async API key access
        let apiKey = await config.getAPIKey()

        switch config.providerType {
        case .claude:
            guard !apiKey.isEmpty else {
                throw AIProviderError.missingAPIKey
            }
            return ClaudeProvider(
                id: config.id,
                name: config.name,
                apiKey: apiKey,
                baseURL: config.baseURL,
                model: config.model
            )

        case .openai:
            guard !apiKey.isEmpty else {
                throw AIProviderError.missingAPIKey
            }
            return OpenAIProvider(
                id: config.id,
                name: config.name,
                apiKey: apiKey,
                baseURL: config.baseURL,
                model: config.model
            )

        case .deepseek, .minimax, .kimi, .qwen:
            guard !apiKey.isEmpty else {
                throw AIProviderError.missingAPIKey
            }
            // OpenAI-compatible cloud APIs — reuse the OpenAI client with the
            // provider's endpoint and default model.
            return OpenAIProvider(
                id: config.id,
                name: config.name,
                apiKey: apiKey,
                baseURL: config.baseURL ?? config.providerType.defaultBaseURL,
                model: config.model ?? config.providerType.defaultModels.first
            )

        case .appleIntelligence:
            #if canImport(FoundationModels)
            if #available(macOS 26.0, iOS 26.0, *) {
                return AppleIntelligenceProvider(
                    id: config.id,
                    name: config.name
                )
            }
            #endif
            throw AIProviderError.invalidConfiguration

        case .ollama:
            return OllamaProvider(
                id: config.id,
                name: config.name,
                baseURL: config.baseURL,
                model: config.model
            )

        case .lmstudio:
            return LMStudioProvider(
                id: config.id,
                name: config.name,
                baseURL: config.baseURL,
                model: config.model
            )

        case .custom:
            guard let baseURL = config.baseURL else {
                throw AIProviderError.invalidBaseURL
            }
            guard !apiKey.isEmpty else {
                throw AIProviderError.missingAPIKey
            }
            return CustomProvider(
                id: config.id,
                name: config.name,
                apiKey: apiKey,
                baseURL: baseURL,
                model: config.model
            )
        }
    }
}
