import Foundation

/// LM Studio provider — talks to LM Studio's local OpenAI-compatible server.
///
/// LM Studio exposes `GET /v1/models` (listing loaded models) and
/// `POST /v1/chat/completions` (OpenAI shape). The default port is 1234.
/// No API key is required; some builds expect any non-empty bearer token,
/// so we send a placeholder.
actor LMStudioProvider: AIProvider {
    let id: UUID
    let name: String
    let type: ProviderType = .lmstudio
    let supportsStreaming: Bool = true

    private let baseURL: String
    private let model: String

    init(
        id: UUID,
        name: String,
        baseURL: String? = nil,
        model: String? = nil
    ) {
        self.id = id
        self.name = name
        self.baseURL = (baseURL?.isEmpty == false ? baseURL! : "http://localhost:1234")
            .trimmingCharacters(in: .whitespaces)
            .trimmedTrailingSlash
        self.model = model?.isEmpty == false ? model! : ""
    }

    func generateResponse(
        for selection: String,
        context: String?,
        conversationHistory: [ThreadMessage],
        options: AIRequestOptions
    ) async throws -> String {
        let request = try buildChatRequest(
            selection: selection,
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
                let message = parseErrorMessage(data) ?? "LM Studio returned \(httpResponse.statusCode)"
                throw AIProviderError.apiError(statusCode: httpResponse.statusCode, message: message)
            }
            return try parseChatResponse(data)
        } catch let error as AIProviderError {
            throw error
        } catch {
            throw AIProviderError.networkError(error)
        }
    }

    // MARK: - Request construction

    private func buildChatRequest(
        selection: String,
        context: String?,
        conversationHistory: [ThreadMessage],
        options: AIRequestOptions,
        streaming: Bool = false
    ) throws -> URLRequest {
        let endpoint = baseURL.appendingPath("/v1/chat/completions")
        guard let url = URL(string: endpoint) else {
            throw AIProviderError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer lm-studio", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 300

        let systemPrompt = options.systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? options.systemPrompt!
            : buildSystemPrompt()

        var messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]
        for message in conversationHistory {
            messages.append(["role": message.role.rawValue, "content": message.content])
        }
        messages.append([
            "role": "user",
            "content": buildUserMessage(selectedText: selection, context: context)
        ])

        var body: [String: Any] = [
            "messages": messages,
            "max_tokens": 1024,
            "temperature": options.temperature ?? 0.7,
            "stream": streaming
        ]
        if !model.isEmpty {
            body["model"] = model
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func parseChatResponse(_ data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any] else {
            throw AIProviderError.invalidResponse
        }
        if let content = message["content"] as? String, !content.isEmpty {
            return content
        }
        // Some local builds emit reasoning_content instead of content.
        if let reasoning = message["reasoning_content"] as? String, !reasoning.isEmpty {
            return reasoning
        }
        throw AIProviderError.invalidResponse
    }

    private func parseErrorMessage(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)
        }
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        if let error = json["error"] as? String { return error }
        return nil
    }

    // MARK: - Native streaming (SSE, OpenAI-compatible)

    func streamResponse(
        for selection: String,
        context: String?,
        conversationHistory: [ThreadMessage],
        options: AIRequestOptions
    ) async throws -> AsyncThrowingStream<String, Error> {
        let request = try buildChatRequest(
            selection: selection,
            context: context,
            conversationHistory: conversationHistory,
            options: options,
            streaming: true
        )

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let (chunkStream, response) = try await URLSession.shared.dataChunks(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw AIProviderError.invalidResponse
                    }
                    if httpResponse.statusCode != 200 {
                        let collected = await chunkStream.collectBody()
                        let message = parseErrorMessage(collected) ?? "LM Studio returned \(httpResponse.statusCode)"
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
                        } else if let reasoning = delta["reasoning_content"] as? String, !reasoning.isEmpty {
                            continuation.yield(reasoning)
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

    // MARK: - Prompts

    private func buildSystemPrompt() -> String {
        """
        You are an expert analytical reader providing margin notes. Your annotations should be detailed, illuminating, insightful, incisive, and enlightening—revealing what a careful reader might miss on first pass.

        Provide a substantive margin note (2-5 sentences) that offers genuine insight. Engage deeply with the text at the level it demands.

        Style guidance:
        - Be precise and substantive—avoid generic observations
        - Assume an intelligent reader; don't explain the obvious
        - For dense passages, clarify what's actually being said
        - For deceptively simple passages, reveal the complexity
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
}

// MARK: - Model discovery

extension LMStudioProvider {
    /// A model currently loaded in LM Studio (returned by `GET /v1/models`).
    struct InstalledModel: Sendable, Equatable {
        let id: String
        let ownedBy: String?
    }

    /// Query LM Studio's `/v1/models` endpoint and return whatever it lists.
    /// LM Studio returns an `OpenAIObject`-style envelope `{ object: "list", data: [...] }`.
    static func discoverModels(baseURL: String) async throws -> [InstalledModel] {
        let trimmed = baseURL.trimmedTrailingSlash
        guard let url = URL(string: trimmed.appendingPath("/v1/models")) else {
            throw AIProviderError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer lm-studio", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 8

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIProviderError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw AIProviderError.apiError(
                statusCode: httpResponse.statusCode,
                message: "Unexpected status from LM Studio at \(trimmed)"
            )
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]] else {
            return []
        }
        let models: [InstalledModel] = dataArray.compactMap { entry in
            guard let id = entry["id"] as? String else { return nil }
            let ownedBy = entry["owned_by"] as? String
            return InstalledModel(id: id, ownedBy: ownedBy)
        }
        return models.sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
    }
}
