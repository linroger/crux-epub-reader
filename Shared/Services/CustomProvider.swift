import Foundation

/// Custom AI provider for user-defined APIs (OpenAI-compatible format)
actor CustomProvider: AIProvider {
    let id: UUID
    let name: String
    let type: ProviderType = .custom
    let supportsStreaming: Bool = false // Conservative default for unknown APIs

    private let apiKey: String
    private let baseURL: String
    private let model: String?

    init(
        id: UUID,
        name: String,
        apiKey: String,
        baseURL: String,
        model: String? = nil
    ) {
        self.id = id
        self.name = name
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
    }

    func generateResponse(
        for selection: String,
        context: String?,
        conversationHistory: [ThreadMessage]
    ) async throws -> String {
        guard !apiKey.isEmpty else {
            throw AIProviderError.missingAPIKey
        }

        let request = try buildRequest(
            selectedText: selection,
            context: context,
            conversationHistory: conversationHistory
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIProviderError.invalidResponse
            }

            if httpResponse.statusCode != 200 {
                let errorMessage = parseErrorMessage(data) ?? "Unknown error"
                throw AIProviderError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
            }

            // Try both OpenAI and Claude response formats
            return try parseResponse(data)
        } catch let error as AIProviderError {
            throw error
        } catch {
            throw AIProviderError.networkError(error)
        }
    }

    // MARK: - Request Building

    private func buildEndpointURL() -> String {
        var endpoint = baseURL

        // If the base URL doesn't already end with a specific endpoint path,
        // append the OpenAI-compatible chat completions endpoint
        if !endpoint.contains("/chat/completions") &&
           !endpoint.contains("/messages") &&
           !endpoint.hasSuffix("/completions") {
            // Remove trailing slash if present
            if endpoint.hasSuffix("/") {
                endpoint.removeLast()
            }
            // Append chat completions endpoint
            endpoint += "/chat/completions"
        }

        return endpoint
    }

    private func buildRequest(
        selectedText: String,
        context: String?,
        conversationHistory: [ThreadMessage]
    ) throws -> URLRequest {
        // Build full endpoint URL
        let endpoint = buildEndpointURL()
        guard let url = URL(string: endpoint) else {
            throw AIProviderError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Support both Bearer token (OpenAI-style) and x-api-key (Claude-style)
        if baseURL.contains("anthropic") {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        request.timeoutInterval = 30

        // Build messages array
        var messages: [[String: Any]] = []

        // System message for margin notes (OpenAI format)
        messages.append([
            "role": "system",
            "content": buildSystemPrompt()
        ])

        // Add conversation history
        for message in conversationHistory {
            messages.append([
                "role": message.role.rawValue,
                "content": message.content
            ])
        }

        // Add new user message with context
        let userMessage = buildUserMessage(selectedText: selectedText, context: context)
        messages.append([
            "role": "user",
            "content": userMessage
        ])

        // Build request body (OpenAI-compatible format)
        var body: [String: Any] = [
            "messages": messages,
            "max_tokens": 1024,
            "temperature": 0.7
        ]

        // Add model if specified
        if let model = model {
            body["model"] = model
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Prompt Building

    private func buildSystemPrompt() -> String {
        """
        You are generating margin notes for a book reader. Notes appear inline and can start discussion threads.

        Write margin notes that are:
        - Terse and substantive (2-4 sentences)
        - One pointed observation or question
        - Scholarly and insightful

        Draw from what's relevant:
        - Literal vs. figurative meaning, symbolic layers
        - Literary devices, formal techniques, prosody
        - Philological notes: etymology, translation issues, textual variants
        - Historical, philosophical, or theological context
        - Connection to the work's broader argument or structure
        - Intertextual allusions or echoes

        Skip surface-level observations. Assume literary familiarity.
        """
    }

    private func buildUserMessage(selectedText: String, context: String?) -> String {
        var message = ""

        if let context = context, !context.isEmpty {
            message += """
            Context:
            ---
            \(context)
            ---

            """
        }

        message += """
        Highlighted passage:
        "\(selectedText)"
        """

        return message
    }

    // MARK: - Response Parsing

    private func parseResponse(_ data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIProviderError.invalidResponse
        }

        // Try OpenAI format first
        if let choices = json["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let message = firstChoice["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }

        // Try Claude format
        if let content = json["content"] as? [[String: Any]],
           let firstContent = content.first,
           let text = firstContent["text"] as? String {
            return text
        }

        // Try simple text field (some APIs return directly)
        if let text = json["text"] as? String {
            return text
        }

        if let response = json["response"] as? String {
            return response
        }

        throw AIProviderError.invalidResponse
    }

    private func parseErrorMessage(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Try various error formats
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }

        if let message = json["message"] as? String {
            return message
        }

        if let detail = json["detail"] as? String {
            return detail
        }

        return nil
    }
}
