import Foundation

/// Ollama provider — talks to a locally-running `ollama serve` instance
/// (default `http://localhost:11434`).
///
/// Uses Ollama's native `/api/chat` endpoint because it gives us the
/// richest signal on errors. Model discovery hits `/api/tags`.
actor OllamaProvider: AIProvider {
    let id: UUID
    let name: String
    let type: ProviderType = .ollama
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
        self.baseURL = (baseURL?.isEmpty == false ? baseURL! : "http://localhost:11434")
            .trimmingCharacters(in: .whitespaces)
            .trimmedTrailingSlash
        // Don't default to a specific model — Ollama users have their own
        // installed set. If unset, the provider will surface a clear error
        // rather than asking for a model that may not be present.
        self.model = (model?.isEmpty == false ? model! : "llama3.2")
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
                let errorMessage = parseErrorMessage(data) ?? "Ollama returned \(httpResponse.statusCode)"
                if httpResponse.statusCode == 404 {
                    throw AIProviderError.apiError(
                        statusCode: 404,
                        message: "Model '\(model)' is not installed locally. Run 'ollama pull \(model)' or pick a different model in Settings."
                    )
                }
                throw AIProviderError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
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
        let endpoint = baseURL.appendingPath("/api/chat")
        guard let url = URL(string: endpoint) else {
            throw AIProviderError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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

        let temperature: Double = options.temperature ?? 0.7
        let ollamaOptions: [String: Any] = [
            "temperature": temperature,
            "num_predict": 1024
        ]
        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": streaming,
            "options": ollamaOptions
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func parseChatResponse(_ data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIProviderError.invalidResponse
        }
        if let message = json["message"] as? [String: Any],
           let content = message["content"] as? String,
           !content.isEmpty {
            return content
        }
        // Some older Ollama builds return the content under "response"
        if let content = json["response"] as? String, !content.isEmpty {
            return content
        }
        throw AIProviderError.invalidResponse
    }

    private func parseErrorMessage(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)
        }
        if let error = json["error"] as? String { return error }
        return nil
    }

    // MARK: - Native streaming (JSONL)

    /// Ollama's `/api/chat` with `stream: true` returns one JSON object
    /// per line, each containing a `message.content` chunk. The final
    /// object has `done: true` and may omit `message`.
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
                        var collected = Data()
                        for try await chunk in chunkStream { collected.append(chunk) }
                        let message = parseErrorMessage(collected) ?? "Ollama returned \(httpResponse.statusCode)"
                        throw AIProviderError.apiError(statusCode: httpResponse.statusCode, message: message)
                    }

                    var buffer = Data()
                    for try await chunk in chunkStream {
                        buffer.append(chunk)
                        // Split on \n; each line is a JSON object.
                        while let newlineRange = buffer.range(of: Data([0x0A])) {
                            let lineData = buffer.subdata(in: 0..<newlineRange.lowerBound)
                            buffer.removeSubrange(0..<newlineRange.upperBound)
                            if lineData.isEmpty { continue }

                            guard let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }
                            if let message = json["message"] as? [String: Any],
                               let content = message["content"] as? String, !content.isEmpty {
                                continuation.yield(content)
                            }
                            if let done = json["done"] as? Bool, done {
                                continuation.finish()
                                return
                            }
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

    // MARK: - Prompts (shared with cloud providers)

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

        **Style guidance:**
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

extension OllamaProvider {
    /// Represents a single installed Ollama model returned by `/api/tags`.
    struct InstalledModel: Sendable, Equatable {
        let name: String
        let sizeBytes: Int64?
        let modifiedAt: Date?

        /// Human-readable size such as "4.7 GB". Returns nil if size unknown.
        var displaySize: String? {
            guard let sizeBytes else { return nil }
            return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
        }
    }

    /// Hit the local Ollama server's `/api/tags` endpoint and return the
    /// installed models, sorted alphabetically by name.
    ///
    /// Throws `AIProviderError.networkError` when the server isn't reachable
    /// — the Settings UI catches that and shows an actionable "Ollama isn't
    /// running" message.
    static func discoverModels(baseURL: String) async throws -> [InstalledModel] {
        let trimmed = baseURL.trimmedTrailingSlash
        guard let url = URL(string: trimmed.appendingPath("/api/tags")) else {
            throw AIProviderError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8  // Discovery should be fast; local request

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
                message: "Unexpected status from Ollama at \(trimmed)"
            )
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modelsArray = json["models"] as? [[String: Any]] else {
            return []
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let formatterNoFraction = ISO8601DateFormatter()

        let models: [InstalledModel] = modelsArray.compactMap { entry in
            guard let name = entry["name"] as? String else { return nil }
            let size = entry["size"] as? Int64 ?? (entry["size"] as? NSNumber)?.int64Value
            let modified: Date? = {
                guard let raw = entry["modified_at"] as? String else { return nil }
                return formatter.date(from: raw) ?? formatterNoFraction.date(from: raw)
            }()
            return InstalledModel(name: name, sizeBytes: size, modifiedAt: modified)
        }
        return models.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// String URL helpers live in `LocalProviderURL.swift` and are shared with
// LMStudioProvider.
