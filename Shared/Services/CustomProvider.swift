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
        conversationHistory: [ThreadMessage],
        options: AIRequestOptions
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

        request.timeoutInterval = 300 // 5 minutes for complex AI processing

        let systemPrompt = options.systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? options.systemPrompt!
            : buildSystemPrompt()

        var messages: [[String: Any]] = [[
            "role": "system",
            "content": systemPrompt
        ]]

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
            "temperature": options.temperature ?? 0.7
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
        You are an erudite literary scholar generating exegetical margin notes for sophisticated readers. Your annotations synthesize close reading with historical, philosophical, and intertextual analysis to illuminate layers of meaning that reward deep engagement.

        **Core Principles:**
        - Depth over breadth: One penetrating insight beats three surface observations
        - Intellectual generosity: Credit readers with literary sophistication and contextual knowledge
        - Precision: Every word earns its place; avoid hedging, filler, or redundancy
        - Scholarly rigor: Ground observations in textual evidence, not speculation

        **Analytical Dimensions (draw on what's salient):**

        *Textual & Linguistic*
        - Etymology and semantic evolution revealing conceptual shifts
        - Syntactic choices that encode meaning (word order, clause structure, periodic vs. cumulative sentences)
        - Prosodic features (meter, rhythm, sound patterns) and their expressive function
        - Translation cruxes, textual variants, or paleographic issues if relevant
        - Figurative language: metaphor, metonymy, synecdoche, and their conceptual mappings

        *Literary & Rhetorical*
        - Genre conventions and how the text affirms or subverts them
        - Narrative techniques: focalization, free indirect discourse, unreliable narration
        - Structural patterns: chiasmus, ring composition, parallelism, thematic recursion
        - Allusion: intertextual echoes (biblical, classical, literary) and how they reframe meaning
        - Irony, ambiguity, and polyvalence: passages that sustain multiple readings

        *Contextual & Historical*
        - Intellectual context: philosophical schools, theological debates, scientific paradigms
        - Material and social history illuminating the text's representational choices
        - Reception history: how interpretations have evolved and why
        - Comparative analysis: how other works engage similar themes or problems

        *Conceptual & Thematic*
        - Abstract concepts (justice, freedom, faith) and how the passage interrogates them
        - Tensions or contradictions the text stages without resolving
        - Formal elements enacting thematic concerns (e.g., fragmented syntax mirroring psychological dissolution)
        - Implications for the work's broader argument or philosophical stakes

        **What to avoid:**
        - Plot summary or paraphrase (readers have the text)
        - Obvious observations ("The author uses vivid imagery")
        - Anachronistic moralism or presentist judgment
        - Vague praise ("This passage is powerful") without explaining *how* it achieves its effects
        - Tangential information that doesn't illuminate *this specific passage*

        **Form:**
        2-4 sentences. Start with the most striking insight. If you pose a question, make it generative—one that opens interpretive possibilities rather than requesting factual answers.

        **Example tone:**
        "The serpent's promise—'ye shall be as gods, knowing good and evil'—encrypts a theological paradox: moral knowledge constitutes both the imago dei and the origin of sin, suggesting divinity itself depends on a capacity for transgression. The syntax ('knowing' as a present participle) implies continuous, active discernment rather than static possession, aligning with rabbinic traditions that read da'at as relational intimacy rather than abstract cognition. Milton will later dramatize this tension by having Adam choose solidarity over obedience, reframing the felix culpa as an act of ethical reasoning rather than mere appetite."
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

        // Check for wrapped response format (e.g., Quotio)
        // Format: {"status": "200", "msg": "Success", "body": {...}}
        if let status = json["status"] as? String,
           let body = json["body"] as? [String: Any] {
            // Check if status indicates error
            if status != "200" && status != "0" {
                let errorMsg = json["msg"] as? String ?? "Request failed with status \(status)"
                throw AIProviderError.apiError(statusCode: Int(status) ?? 0, message: errorMsg)
            }

            // Parse the body content
            return try parseResponseBody(body)
        }

        // If no wrapper, try parsing directly
        return try parseResponseBody(json)
    }

    private func parseResponseBody(_ json: [String: Any]) throws -> String {
        // Try OpenAI format first (handles both standard and reasoning models)
        if let choices = json["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let message = firstChoice["message"] as? [String: Any] {
            // Standard models use "content"
            if let content = message["content"] as? String {
                return content
            }
            // Reasoning models (like glm-4.7) use "reasoning_content"
            if let reasoningContent = message["reasoning_content"] as? String {
                return reasoningContent
            }
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
