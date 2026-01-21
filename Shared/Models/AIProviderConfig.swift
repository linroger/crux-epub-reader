import Foundation
import SwiftData

/// AI provider configuration stored in SwiftData
@Model
final class AIProviderConfig {
    @Attribute(.unique) var id: UUID
    var name: String
    var type: String // "claude", "openai", "custom"
    var apiKey: String
    var baseURL: String?
    var model: String?
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        type: ProviderType,
        apiKey: String,
        baseURL: String? = nil,
        model: String? = nil,
        isActive: Bool = false
    ) {
        self.id = id
        self.name = name
        self.type = type.rawValue
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
        self.isActive = isActive
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Provider type as enum
    var providerType: ProviderType {
        get { ProviderType(rawValue: type) ?? .custom }
        set { type = newValue.rawValue }
    }

    /// Mark as updated
    func markUpdated() {
        updatedAt = Date()
    }

    /// Validate configuration
    var isValid: Bool {
        !name.isEmpty && !apiKey.isEmpty &&
        (providerType != .custom || baseURL != nil)
    }
}

// MARK: - Provider Type Enum

enum ProviderType: String, CaseIterable, Identifiable, Codable {
    case claude = "claude"
    case openai = "openai"
    case custom = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Anthropic Claude"
        case .openai: return "OpenAI"
        case .custom: return "Custom Provider"
        }
    }

    var defaultBaseURL: String? {
        switch self {
        case .claude: return "https://api.anthropic.com/v1/messages"
        case .openai: return "https://api.openai.com/v1/chat/completions"
        case .custom: return nil
        }
    }

    var defaultModels: [String] {
        switch self {
        case .claude:
            return [
                "claude-opus-4-5-20251101",
                "claude-sonnet-4-5-20250929",
                "claude-sonnet-3-7-20250219",
                "claude-haiku-4-20250305"
            ]
        case .openai:
            return [
                "gpt-4o",
                "gpt-4o-mini",
                "gpt-4-turbo",
                "o1-preview",
                "o1-mini"
            ]
        case .custom:
            return []
        }
    }

    var requiresBaseURL: Bool {
        self == .custom
    }

    var supportsStreaming: Bool {
        true // All providers support streaming
    }
}

// MARK: - Provider Defaults

extension AIProviderConfig {
    /// Create default Claude provider configuration
    static func createDefaultClaude(apiKey: String) -> AIProviderConfig {
        AIProviderConfig(
            name: "Claude (Default)",
            type: .claude,
            apiKey: apiKey,
            baseURL: ProviderType.claude.defaultBaseURL,
            model: "claude-opus-4-5-20251101",
            isActive: true
        )
    }

    /// Create OpenAI provider configuration
    static func createOpenAI(apiKey: String, model: String = "gpt-4o") -> AIProviderConfig {
        AIProviderConfig(
            name: "OpenAI",
            type: .openai,
            apiKey: apiKey,
            baseURL: ProviderType.openai.defaultBaseURL,
            model: model,
            isActive: false
        )
    }

    /// Create custom provider configuration
    static func createCustom(
        name: String,
        apiKey: String,
        baseURL: String,
        model: String? = nil
    ) -> AIProviderConfig {
        AIProviderConfig(
            name: name,
            type: .custom,
            apiKey: apiKey,
            baseURL: baseURL,
            model: model,
            isActive: false
        )
    }
}
