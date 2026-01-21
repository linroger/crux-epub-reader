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
        You are an expert analytical reader providing margin notes. Your annotations should be detailed, illuminating, insightful, incisive, and enlightening—revealing what a careful reader might miss on first pass.

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

        Provide a substantive margin note (2-5 sentences) that offers genuine insight. Engage deeply with the text at the level it demands:

        **For any text type, consider:**
        - What's the core claim, mechanism, or observation here? What makes it significant?
        - Unstated assumptions, implications, or tensions
        - How this connects to broader arguments, frameworks, or contexts
        - What's surprising, counterintuitive, or easily misread
        - Alternative interpretations or framings
        - Methodological approaches or epistemic questions

        **Genre-specific depth:**
        - **Literary**: rhetorical devices, symbolic layers, structural function, allusions, tonal shifts
        - **Academic/Scientific**: theoretical frameworks, methodological choices, empirical claims vs. interpretation, disciplinary context
        - **Philosophy**: conceptual distinctions, argumentative moves, historical lineage, overlooked objections
        - **Technical**: design decisions, edge cases, performance implications, architectural patterns
        - **Historical**: historiographical perspective, source reliability, contextual significance
        - **Journalistic**: framing choices, missing perspectives, evidential basis

        **Style guidance:**
        - Be precise and substantive—avoid generic observations
        - Assume an intelligent reader; don't explain the obvious
        - Sometimes the best note is a connection: "Contrast with [X]" or "Assumes [Y framework]"
        - For dense passages, clarify what's actually being said
        - For deceptively simple passages, reveal the complexity

        Think: what would an expert in this field notice and mark for deeper consideration?
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
