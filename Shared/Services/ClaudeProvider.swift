import Foundation

/// Claude (Anthropic) AI provider implementation
actor ClaudeProvider: AIProvider {
    let id: UUID
    let name: String
    let type: ProviderType = .claude
    let supportsStreaming: Bool = true

    private let apiKey: String
    private let baseURL: String
    private let model: String

    init(
        id: UUID,
        name: String,
        apiKey: String,
        baseURL: String? = nil,
        model: String? = nil
    ) {
        self.id = id
        self.name = name
        self.apiKey = apiKey
        self.baseURL = baseURL ?? "https://api.anthropic.com/v1/messages"
        self.model = model ?? "claude-opus-4-5-20251101"
    }

    func generateResponse(
        for selection: String,
        context: String?,
        conversationHistory: [ThreadMessage]
    ) async throws -> String {
        guard !apiKey.isEmpty else {
            throw AIProviderError.missingAPIKey
        }

        let prompt = buildPrompt(
            selectedText: selection,
            context: context,
            conversationHistory: conversationHistory
        )

        let request = try buildRequest(prompt: prompt, conversationHistory: conversationHistory)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIProviderError.invalidResponse
            }

            if httpResponse.statusCode != 200 {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw AIProviderError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
            }

            return try parseResponse(data)
        } catch let error as AIProviderError {
            throw error
        } catch {
            throw AIProviderError.networkError(error)
        }
    }

    // MARK: - Prompt Building

    private func buildPrompt(
        selectedText: String,
        context: String?,
        conversationHistory: [ThreadMessage]
    ) -> String {
        // If this is a follow-up in a conversation, return just the new user message
        if !conversationHistory.isEmpty {
            return selectedText
        }

        // Initial margin note prompt
        var prompt = """
        You are generating margin notes for a book reader. Notes appear inline and can start discussion threads.

        """

        if let context = context, !context.isEmpty {
            prompt += """
            Context:
            ---
            \(context)
            ---

            """
        }

        prompt += """
        Highlighted passage:
        "\(selectedText)"

        Write a margin note. This is marginalia, not an essay—2-4 sentences, one pointed observation or question.

        Draw from what's relevant:
        - Literal vs. figurative meaning, symbolic layers
        - Literary devices, formal techniques, prosody
        - Philological notes: etymology, translation issues, textual variants
        - Historical, philosophical, or theological context
        - Connection to the work's broader argument or structure
        - Intertextual allusions or echoes

        But distill to the single most interesting thing. Be terse and substantive. Skip surface-level observations. Assume literary familiarity.

        For biblical texts: engage as scholarship (historical-critical, literary), not devotionally.
        For poetry: form often is the observation.
        For philosophy/theology: name the tradition or debate being invoked.

        Think: what would you actually scribble in a margin? Sometimes that's "cf. Romans 9" or "echoes Hyperion" or "watch the verb tense shift." Not everything needs unpacking—just marking.
        """

        return prompt
    }

    // MARK: - Request Building

    private func buildRequest(
        prompt: String,
        conversationHistory: [ThreadMessage]
    ) throws -> URLRequest {
        guard let url = URL(string: baseURL) else {
            throw AIProviderError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 30

        // Build messages array
        var messages: [[String: Any]] = []

        // Add conversation history
        for message in conversationHistory {
            messages.append([
                "role": message.role.rawValue,
                "content": message.content
            ])
        }

        // Add new user message
        messages.append([
            "role": "user",
            "content": prompt
        ])

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "messages": messages
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Response Parsing

    private func parseResponse(_ data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            throw AIProviderError.invalidResponse
        }
        return text
    }
}

// MARK: - Backward Compatibility with ClaudeService

extension ClaudeProvider {
    /// Create a provider from legacy ClaudeService settings
    static func createFromLegacySettings() -> ClaudeProvider? {
        let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
            ?? UserDefaults.standard.string(forKey: "anthropicAPIKey")

        guard let apiKey = apiKey, !apiKey.isEmpty else {
            return nil
        }

        return ClaudeProvider(
            id: UUID(),
            name: "Claude (Migrated)",
            apiKey: apiKey
        )
    }
}
