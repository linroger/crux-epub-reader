import Foundation

/// One installed model returned by a local provider's discovery endpoint.
/// Unifies the slightly different shapes Ollama and LM Studio expose so the
/// UI can render a single list.
struct DiscoveredModel: Sendable, Equatable, Identifiable {
    let id: String          // model identifier as the provider expects it
    let displayName: String // pretty label (often same as id)
    let detail: String?     // secondary line — size, owner, etc.

    init(id: String, displayName: String? = nil, detail: String? = nil) {
        self.id = id
        self.displayName = displayName ?? id
        self.detail = detail
    }
}

/// Calls the right per-provider discovery endpoint and normalizes the
/// result. The SettingsView uses this when the user taps "Refresh installed
/// models".
enum LocalModelDiscovery {
    /// Returns the list of installed models for the given provider type.
    /// Throws `AIProviderError` for both "server not running" (networkError)
    /// and protocol errors so the caller can show specific feedback.
    static func models(for type: ProviderType, baseURL: String) async throws -> [DiscoveredModel] {
        switch type {
        case .ollama:
            let installed = try await OllamaProvider.discoverModels(baseURL: baseURL)
            return installed.map { model in
                DiscoveredModel(
                    id: model.name,
                    displayName: model.name,
                    detail: model.displaySize
                )
            }

        case .lmstudio:
            let installed = try await LMStudioProvider.discoverModels(baseURL: baseURL)
            return installed.map { model in
                DiscoveredModel(
                    id: model.id,
                    displayName: model.id,
                    detail: model.ownedBy
                )
            }

        default:
            // Other providers don't support local discovery; return empty
            // rather than throwing so callers can fall back to default lists.
            return []
        }
    }

    /// Fetches the list of available models from a cloud provider's
    /// OpenAI-/Anthropic-style `/models` endpoint. Powers Settings' "Fetch
    /// models" for cloud providers (OpenAI, DeepSeek, Kimi, Qwen, Claude, and
    /// custom OpenAI-compatible endpoints).
    static func remoteModels(for type: ProviderType, baseURL: String, apiKey: String) async throws -> [DiscoveredModel] {
        guard !apiKey.isEmpty else { throw AIProviderError.missingAPIKey }
        guard let modelsURL = modelsEndpoint(for: type, baseURL: baseURL) else {
            throw AIProviderError.invalidBaseURL
        }

        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 30

        if type == .claude {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIProviderError.invalidResponse
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            let message = body.isEmpty ? "HTTP \(http.statusCode)" : String(body.prefix(300))
            throw AIProviderError.apiError(statusCode: http.statusCode, message: message)
        }

        // OpenAI/Anthropic/DashScope all return { "data": [ { "id": … } ] }.
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["data"] as? [[String: Any]] else {
            throw AIProviderError.invalidResponse
        }

        let models = list.compactMap { entry -> DiscoveredModel? in
            guard let id = entry["id"] as? String, !id.isEmpty else { return nil }
            let owner = entry["owned_by"] as? String
            return DiscoveredModel(id: id, displayName: id, detail: (owner?.isEmpty == false) ? owner : nil)
        }
        return models.sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
    }

    /// Derives the `/models` listing URL from a provider's chat endpoint.
    private static func modelsEndpoint(for type: ProviderType, baseURL: String) -> URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // OpenAI-compatible: ".../v1/chat/completions" -> ".../v1/models"
        if let range = trimmed.range(of: "/chat/completions") {
            return URL(string: trimmed.replacingCharacters(in: range, with: "/models"))
        }
        // Anthropic: ".../v1/messages" -> ".../v1/models"
        if let range = trimmed.range(of: "/messages") {
            return URL(string: trimmed.replacingCharacters(in: range, with: "/models"))
        }
        // Fallback: append /models to the base, trimming a trailing slash.
        let base = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        return URL(string: base + "/models")
    }
}
