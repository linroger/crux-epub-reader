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
}
