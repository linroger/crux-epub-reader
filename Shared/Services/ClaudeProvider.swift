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
        conversationHistory: [ThreadMessage],
        options: AIRequestOptions
    ) async throws -> String {
        guard !apiKey.isEmpty else {
            throw AIProviderError.missingAPIKey
        }

        let prompt = buildPrompt(
            selectedText: selection,
            context: context,
            conversationHistory: conversationHistory,
            customSystemPrompt: options.systemPrompt
        )

        let request = try buildRequest(prompt: prompt, conversationHistory: conversationHistory, temperature: options.temperature, images: options.images)

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
        conversationHistory: [ThreadMessage],
        customSystemPrompt: String?
    ) -> String {
        // If this is a follow-up in a conversation, return just the new user message
        if !conversationHistory.isEmpty {
            return selectedText
        }

        // Use the user's custom system prompt when supplied, otherwise the
        // built-in scholarly default.
        var prompt = (customSystemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                      ? customSystemPrompt!
                      : Self.builtInSystemPrompt) + "\n\n"

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
        """

        return prompt
    }

    private static let builtInSystemPrompt = AIPrompts.marginNote

    // MARK: - Request Building

    private func buildRequest(
        prompt: String,
        conversationHistory: [ThreadMessage],
        temperature: Double? = nil,
        images: [AIImageAttachment] = []
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

        // Add new user message. With images, Anthropic expects a content
        // array of typed blocks: image blocks first, then the text block.
        if images.isEmpty {
            messages.append([
                "role": "user",
                "content": prompt
            ])
        } else {
            var blocks: [[String: Any]] = []
            for image in images {
                if let parts = image.base64Components {
                    blocks.append([
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": parts.mediaType,
                            "data": parts.data
                        ]
                    ])
                } else if !image.isDataURI {
                    // Remote URL source (Anthropic supports url image sources).
                    blocks.append([
                        "type": "image",
                        "source": ["type": "url", "url": image.url]
                    ])
                }
            }
            blocks.append(["type": "text", "text": prompt])
            messages.append([
                "role": "user",
                "content": blocks
            ])
        }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "messages": messages
        ]
        if let temperature {
            body["temperature"] = temperature
        }

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

    // MARK: - Native streaming

    /// Anthropic streams via SSE with `content_block_delta` events whose
    /// `delta.text` field contains the next slice of tokens.
    func streamResponse(
        for selection: String,
        context: String?,
        conversationHistory: [ThreadMessage],
        options: AIRequestOptions
    ) async throws -> AsyncThrowingStream<String, Error> {
        guard !apiKey.isEmpty else {
            throw AIProviderError.missingAPIKey
        }
        let prompt = buildPrompt(
            selectedText: selection,
            context: context,
            conversationHistory: conversationHistory,
            customSystemPrompt: options.systemPrompt
        )
        var request = try buildRequest(prompt: prompt, conversationHistory: conversationHistory, temperature: options.temperature, images: options.images)
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
                        let collected = await chunkStream.collectBody()
                        let message = String(data: collected, encoding: .utf8) ?? "Unknown error"
                        throw AIProviderError.apiError(statusCode: httpResponse.statusCode, message: message)
                    }

                    let payloads = SSEParser.payloadStream(from: chunkStream)
                    for try await payload in payloads {
                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                            continue
                        }
                        let type = json["type"] as? String
                        switch type {
                        case "content_block_delta":
                            if let delta = json["delta"] as? [String: Any],
                               let text = delta["text"] as? String, !text.isEmpty {
                                continuation.yield(text)
                            }
                        case "message_stop", "error":
                            // message_stop terminates; explicit error events
                            // would carry detail in `error.message`.
                            if let err = json["error"] as? [String: Any],
                               let message = err["message"] as? String {
                                continuation.finish(throwing: AIProviderError.apiError(statusCode: 0, message: message))
                                return
                            }
                        default:
                            continue
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

// The legacy `ClaudeService` actor has been removed; migration of any
// pre-existing API key in UserDefaults / env happens once via
// `AIProviderManager.migrateFromLegacySettings()`.
