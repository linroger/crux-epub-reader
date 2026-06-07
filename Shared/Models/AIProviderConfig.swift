import Foundation
import SwiftData

/// AI provider configuration stored in SwiftData
/// Note: API keys are now stored securely in Keychain, not in SwiftData
@Model
final class AIProviderConfig {
    @Attribute(.unique) var id: UUID
    var name: String
    var type: String // "claude", "openai", "appleIntelligence", "custom"
    
    /// Legacy field for migration - new keys stored in Keychain
    /// This field is kept for backward compatibility during migration
    /// After migration, this will be empty and the real key is in Keychain
    private var legacyApiKey: String = ""
    
    /// Flag indicating whether API key has been migrated to Keychain
    var apiKeyMigrated: Bool = false
    
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
        self.legacyApiKey = "" // Don't store in SwiftData anymore
        self.apiKeyMigrated = true // New configs are always "migrated"
        self.baseURL = baseURL
        self.model = model
        self.isActive = isActive
        self.createdAt = Date()
        self.updatedAt = Date()
        
        // Store API key in Keychain if provided
        if !apiKey.isEmpty {
            Task {
                try? await KeychainService.shared.saveAPIKey(apiKey, for: id)
            }
        }
    }
    
    // MARK: - API Key Access (via Keychain)
    
    /// Get the API key from Keychain
    /// - Returns: The API key or empty string if not found
    func getAPIKey() async -> String {
        // First, ensure migration is complete
        if !apiKeyMigrated && !legacyApiKey.isEmpty {
            await migrateAPIKeyToKeychain()
        }
        
        do {
            return try await KeychainService.shared.loadAPIKey(for: id) ?? ""
        } catch {
            AppLog.security.error("Failed to load API key from Keychain: \(error.localizedDescription, privacy: .public)")
            return ""
        }
    }
    
    /// Set the API key in Keychain
    /// - Parameter apiKey: The API key to store
    func setAPIKey(_ apiKey: String) async throws {
        try await KeychainService.shared.saveAPIKey(apiKey, for: id)
        apiKeyMigrated = true
        legacyApiKey = "" // Clear legacy storage
        markUpdated()
    }
    
    /// Check if API key exists (either in Keychain or legacy storage)
    func hasAPIKey() async -> Bool {
        // Check Keychain first
        if await KeychainService.shared.hasAPIKey(for: id) {
            return true
        }
        // Fall back to legacy storage (pre-migration)
        return !legacyApiKey.isEmpty
    }
    
    /// Migrate API key from legacy SwiftData storage to Keychain
    @MainActor
    func migrateAPIKeyToKeychain() async {
        guard !apiKeyMigrated, !legacyApiKey.isEmpty else { return }
        
        do {
            try await KeychainService.shared.saveAPIKey(legacyApiKey, for: id)
            legacyApiKey = "" // Clear from SwiftData
            apiKeyMigrated = true
            markUpdated()
        } catch {
            AppLog.security.error("Failed to migrate API key to Keychain: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    /// Delete the API key from Keychain
    func deleteAPIKey() async throws {
        try await KeychainService.shared.deleteAPIKey(for: id)
        legacyApiKey = ""
        apiKeyMigrated = true
    }
    
    // MARK: - Legacy Compatibility
    
    /// Computed property for backward compatibility
    /// Synchronously returns the legacy key or empty string
    /// Prefer using getAPIKey() async when possible
    var apiKey: String {
        get {
            // For synchronous access, return legacy key if available
            // or try sync Keychain access
            if !legacyApiKey.isEmpty && !apiKeyMigrated {
                return legacyApiKey
            }
            return KeychainService.shared.loadAPIKeySync(for: id) ?? ""
        }
        set {
            // Store in Keychain asynchronously
            Task {
                try? await setAPIKey(newValue)
            }
        }
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

    /// Validate configuration (synchronous, for UI binding)
    /// Note: Uses synchronous Keychain access; prefer isValidAsync() in async contexts
    var isValid: Bool {
        guard !name.isEmpty else { return false }

        switch providerType {
        case .appleIntelligence:
            // Apple Intelligence doesn't need an API key
            return true
        case .ollama, .lmstudio:
            // Local providers need a baseURL but no API key
            return !(baseURL?.isEmpty ?? true)
        case .custom:
            // Custom providers need API key and base URL
            return !apiKey.isEmpty && !(baseURL?.isEmpty ?? true)
        default:
            // Standard cloud providers need an API key
            return !apiKey.isEmpty
        }
    }

    /// Async validation - preferred for non-UI contexts
    func isValidAsync() async -> Bool {
        guard !name.isEmpty else { return false }

        switch providerType {
        case .appleIntelligence:
            return true
        case .ollama, .lmstudio:
            return !(baseURL?.isEmpty ?? true)
        case .custom:
            let hasKey = await hasAPIKey()
            return hasKey && !(baseURL?.isEmpty ?? true)
        default:
            return await hasAPIKey()
        }
    }
}

// MARK: - Provider Type Enum

enum ProviderType: String, CaseIterable, Identifiable, Codable {
    case claude = "claude"
    case openai = "openai"
    case appleIntelligence = "appleIntelligence"
    case ollama = "ollama"
    case lmstudio = "lmstudio"
    case deepseek = "deepseek"
    case minimax = "minimax"
    case kimi = "kimi"
    case qwen = "qwen"
    case custom = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Anthropic Claude"
        case .openai: return "OpenAI"
        case .appleIntelligence: return "Apple Intelligence"
        case .ollama: return "Ollama (local)"
        case .lmstudio: return "LM Studio (local)"
        case .deepseek: return "DeepSeek"
        case .minimax: return "MiniMax"
        case .kimi: return "Kimi (Moonshot)"
        case .qwen: return "Qwen (Alibaba)"
        case .custom: return "Custom Provider"
        }
    }

    /// One-line subtitle used in the picker — explains where the model runs.
    var subtitle: String {
        switch self {
        case .claude: return "Anthropic API · cloud"
        case .openai: return "OpenAI API · cloud"
        case .appleIntelligence: return "Foundation Models · on-device"
        case .ollama: return "Local server · ollama.com"
        case .lmstudio: return "Local server · lmstudio.ai"
        case .deepseek: return "DeepSeek API · cloud"
        case .minimax: return "MiniMax API · cloud"
        case .kimi: return "Moonshot AI · cloud"
        case .qwen: return "Alibaba DashScope · cloud"
        case .custom: return "Any OpenAI-compatible endpoint"
        }
    }

    var defaultBaseURL: String? {
        switch self {
        case .claude: return "https://api.anthropic.com/v1/messages"
        case .openai: return "https://api.openai.com/v1/chat/completions"
        case .appleIntelligence: return nil // On-device, no URL needed
        case .ollama: return "http://localhost:11434"
        case .lmstudio: return "http://localhost:1234"
        case .deepseek: return "https://api.deepseek.com/v1/chat/completions"
        case .minimax: return "https://api.minimax.io/v1/text/chatcompletion_v2"
        case .kimi: return "https://api.moonshot.ai/v1/chat/completions"
        case .qwen: return "https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions"
        case .custom: return nil
        }
    }

    /// Whether this provider requires an API key
    var requiresAPIKey: Bool {
        switch self {
        case .appleIntelligence, .ollama, .lmstudio: return false
        default: return true
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
        case .appleIntelligence:
            return ["on-device"] // Uses on-device Foundation Models
        case .ollama, .lmstudio:
            // Local providers expose the user's installed models via discovery.
            // The Settings UI fetches them lazily; no hardcoded defaults.
            return []
        case .deepseek:
            return [
                "deepseek-chat",      // DeepSeek-V3 (general)
                "deepseek-reasoner"   // DeepSeek-R1 (reasoning)
            ]
        case .minimax:
            return [
                "MiniMax-Text-01",
                "abab6.5s-chat"
            ]
        case .kimi:
            return [
                "kimi-k2-0711-preview",
                "kimi-latest",
                "moonshot-v1-128k",
                "moonshot-v1-32k",
                "moonshot-v1-8k"
            ]
        case .qwen:
            return [
                "qwen-plus",
                "qwen-max",
                "qwen-turbo",
                "qwen-max-latest",
                "qwen2.5-72b-instruct"
            ]
        case .custom:
            return []
        }
    }

    var requiresBaseURL: Bool {
        switch self {
        case .custom, .ollama, .lmstudio: return true
        default: return false
        }
    }

    /// Whether this provider runs on-device or on the user's local machine.
    /// Used to mark privacy posture in the UI and prefer offline fallbacks.
    var isOnDevice: Bool {
        switch self {
        case .appleIntelligence, .ollama, .lmstudio: return true
        default: return false
        }
    }

    /// True when model discovery against a local endpoint makes sense.
    var supportsModelDiscovery: Bool {
        switch self {
        case .ollama, .lmstudio: return true
        default: return false
        }
    }

    /// True when the provider exposes an OpenAI-/Anthropic-style `/models`
    /// listing endpoint we can query to pull the latest available models.
    /// Excludes local providers (handled by `supportsModelDiscovery`),
    /// Apple Intelligence (on-device), and MiniMax (non-standard endpoint).
    var canListRemoteModels: Bool {
        switch self {
        case .openai, .claude, .deepseek, .kimi, .qwen, .custom: return true
        default: return false
        }
    }

    var supportsStreaming: Bool {
        true // All providers support streaming
    }

    /// True when the provider's default models can accept image input, so
    /// the reader can forward EPUB figures alongside the selected passage.
    /// Conservative on purpose: text-only endpoints (DeepSeek, Kimi,
    /// MiniMax) are excluded so we never attach images a model would reject.
    /// `custom` and the local runners are included because the user picks
    /// the model there and modern local VLMs (llava, qwen2-vl, etc.) are
    /// common — the worst case is a model that ignores the image.
    var supportsVision: Bool {
        switch self {
        case .openai, .claude, .qwen, .ollama, .lmstudio, .custom: return true
        default: return false
        }
    }

    /// SF Symbol used in pickers and badges.
    var symbolName: String {
        switch self {
        case .claude: return "sparkle"
        case .openai: return "circle.hexagongrid"
        case .appleIntelligence: return "apple.intelligence"
        case .ollama: return "server.rack"
        case .lmstudio: return "laptopcomputer"
        case .deepseek: return "magnifyingglass.circle"
        case .minimax: return "waveform.circle"
        case .kimi: return "moon.stars"
        case .qwen: return "character.bubble"
        case .custom: return "puzzlepiece.extension"
        }
    }

    /// Brand icon asset name bundled in `Assets.xcassets`. Returns `nil` for
    /// providers without a bundled brand mark, so the UI falls back to
    /// `symbolName` (an SF Symbol).
    var iconAssetName: String? {
        switch self {
        case .claude: return "ai-claude"
        case .openai: return "ai-openai"
        case .appleIntelligence: return "ai-apple"
        case .ollama: return "ai-ollama"
        case .lmstudio: return "ai-lmstudio"
        case .deepseek: return "ai-deepseek"
        case .minimax: return "ai-minimax"
        case .kimi: return "ai-kimi"
        case .qwen: return "ai-qwen"
        case .custom: return nil
        }
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
    
    /// Create Apple Intelligence provider configuration
    /// This uses the on-device Foundation Models framework (macOS 26+, iOS 26+)
    static func createAppleIntelligence() -> AIProviderConfig {
        AIProviderConfig(
            name: "Apple Intelligence",
            type: .appleIntelligence,
            apiKey: "", // No API key needed for on-device
            baseURL: nil,
            model: "on-device",
            isActive: false
        )
    }

    /// Create an Ollama provider configuration (local server, default port 11434).
    /// Ollama runs entirely on-device; no API key required.
    static func createOllama(
        baseURL: String = ProviderType.ollama.defaultBaseURL ?? "http://localhost:11434",
        model: String? = nil
    ) -> AIProviderConfig {
        AIProviderConfig(
            name: "Ollama",
            type: .ollama,
            apiKey: "",
            baseURL: baseURL,
            model: model,
            isActive: false
        )
    }

    /// Create an LM Studio provider configuration (local server, default port 1234).
    /// LM Studio exposes an OpenAI-compatible API; no API key required.
    static func createLMStudio(
        baseURL: String = ProviderType.lmstudio.defaultBaseURL ?? "http://localhost:1234",
        model: String? = nil
    ) -> AIProviderConfig {
        AIProviderConfig(
            name: "LM Studio",
            type: .lmstudio,
            apiKey: "",
            baseURL: baseURL,
            model: model,
            isActive: false
        )
    }

    /// Create a DeepSeek provider configuration (OpenAI-compatible cloud API).
    static func createDeepSeek(apiKey: String, model: String = "deepseek-chat") -> AIProviderConfig {
        AIProviderConfig(
            name: "DeepSeek",
            type: .deepseek,
            apiKey: apiKey,
            baseURL: ProviderType.deepseek.defaultBaseURL,
            model: model,
            isActive: false
        )
    }

    /// Create a MiniMax provider configuration (OpenAI-compatible cloud API).
    static func createMiniMax(apiKey: String, model: String = "MiniMax-Text-01") -> AIProviderConfig {
        AIProviderConfig(
            name: "MiniMax",
            type: .minimax,
            apiKey: apiKey,
            baseURL: ProviderType.minimax.defaultBaseURL,
            model: model,
            isActive: false
        )
    }

    /// Create a Kimi / Moonshot provider configuration (OpenAI-compatible cloud API).
    static func createKimi(apiKey: String, model: String = "kimi-k2-0711-preview") -> AIProviderConfig {
        AIProviderConfig(
            name: "Kimi (Moonshot)",
            type: .kimi,
            apiKey: apiKey,
            baseURL: ProviderType.kimi.defaultBaseURL,
            model: model,
            isActive: false
        )
    }

    /// Create a Qwen (Alibaba DashScope) provider configuration.
    /// DashScope's OpenAI-compatible endpoint, so it routes through the
    /// shared OpenAI-compatible provider.
    static func createQwen(apiKey: String, model: String = "qwen-plus") -> AIProviderConfig {
        AIProviderConfig(
            name: "Qwen (Alibaba)",
            type: .qwen,
            apiKey: apiKey,
            baseURL: ProviderType.qwen.defaultBaseURL,
            model: model,
            isActive: false
        )
    }
}
