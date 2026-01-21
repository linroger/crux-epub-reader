import Foundation

/// OpenAI AI provider implementation (GPT-4, o1, etc.)
actor OpenAIProvider: AIProvider {
    let id: UUID
    let name: String
    let type: ProviderType = .openai
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
        self.baseURL = baseURL ?? "https://api.openai.com/v1/chat/completions"
        self.model = model ?? "gpt-4o"
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

            return try parseResponse(data)
        } catch let error as AIProviderError {
            throw error
        } catch {
            throw AIProviderError.networkError(error)
        }
    }

    // MARK: - Request Building

    private func buildRequest(
        selectedText: String,
        context: String?,
        conversationHistory: [ThreadMessage]
    ) throws -> URLRequest {
        guard let url = URL(string: baseURL) else {
            throw AIProviderError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        // Build messages array
        var messages: [[String: Any]] = []

        // System message for margin notes
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

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "max_tokens": 1024,
            "temperature": 0.7
        ]

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

        For biblical texts: engage as scholarship (historical-critical, literary), not devotionally.
        For poetry: form often is the observation.
        For philosophy/theology: name the tradition or debate being invoked.

        Think: what would you actually scribble in a margin?
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
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIProviderError.invalidResponse
        }
        return content
    }

    private func parseErrorMessage(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return nil
        }
        return message
    }
}
