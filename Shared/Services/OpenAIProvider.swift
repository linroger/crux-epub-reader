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
        conversationHistory: [ThreadMessage],
        options: AIRequestOptions
    ) async throws -> String {
        guard !apiKey.isEmpty else {
            throw AIProviderError.missingAPIKey
        }

        let request = try buildRequest(
            selectedText: selection,
            context: context,
            conversationHistory: conversationHistory,
            options: options
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
        conversationHistory: [ThreadMessage],
        options: AIRequestOptions
    ) throws -> URLRequest {
        guard let url = URL(string: baseURL) else {
            throw AIProviderError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        // System message for margin notes — honors user override
        let systemPrompt = options.systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? options.systemPrompt!
            : buildSystemPrompt()

        var messages: [[String: Any]] = [[
            "role": "system",
            "content": systemPrompt
        ]]

        for message in conversationHistory {
            messages.append([
                "role": message.role.rawValue,
                "content": message.content
            ])
        }

        messages.append([
            "role": "user",
            "content": buildUserMessage(selectedText: selectedText, context: context)
        ])

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "max_tokens": 1024,
            "temperature": options.temperature ?? 0.7
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Prompt Building

    private func buildSystemPrompt() -> String {
        """
        You are an expert analytical reader providing margin notes. Your annotations should be detailed, illuminating, insightful, incisive, and enlightening—revealing what a careful reader might miss on first pass.

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

    // MARK: - Native streaming

    /// Native SSE streaming via `/v1/chat/completions?stream=true`. Yields
    /// delta tokens as the server produces them so the UI can render
    /// incrementally instead of waiting for the full response.
    func streamResponse(
        for selection: String,
        context: String?,
        conversationHistory: [ThreadMessage],
        options: AIRequestOptions
    ) async throws -> AsyncThrowingStream<String, Error> {
        guard !apiKey.isEmpty else {
            throw AIProviderError.missingAPIKey
        }
        var request = try buildRequest(
            selectedText: selection,
            context: context,
            conversationHistory: conversationHistory,
            options: options
        )
        // Flip the body to streaming mode.
        if let oldBody = request.httpBody,
           var json = try? JSONSerialization.jsonObject(with: oldBody) as? [String: Any] {
            json["stream"] = true
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let (chunkStream, response) = try await URLSession.shared.dataChunks(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw AIProviderError.invalidResponse
                    }
                    if httpResponse.statusCode != 200 {
                        // Drain the byte stream so we get a proper error
                        // message rather than a generic non-200.
                        var collected = Data()
                        for try await chunk in chunkStream { collected.append(chunk) }
                        let message = parseErrorMessage(collected) ?? "Unknown error"
                        throw AIProviderError.apiError(statusCode: httpResponse.statusCode, message: message)
                    }

                    let payloads = SSEParser.payloadStream(from: chunkStream)
                    for try await payload in payloads {
                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let first = choices.first,
                              let delta = first["delta"] as? [String: Any] else {
                            continue
                        }
                        if let content = delta["content"] as? String, !content.isEmpty {
                            continuation.yield(content)
                        }
                    }
                    continuation.finish()
                } catch let error as AIProviderError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: AIProviderError.networkError(error))
                }
            }
        }
    }
}
