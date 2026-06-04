import Foundation
import SwiftData
import Observation

/// Manages AI provider lifecycle and selection
@Observable
final class AIProviderManager {
    private(set) var providers: [AIProviderConfig] = []
    private(set) var activeProvider: (any AIProvider)?
    private var modelContext: ModelContext?
    
    /// Track if Keychain migration has been performed
    private var keychainMigrationComplete = false

    init() {}

    /// Initialize with SwiftData model context
    func initialize(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadProviders()
        
        // Perform Keychain migration for existing API keys
        Task { @MainActor in
            await migrateAPIKeysToKeychain()
        }
    }

    /// Load all providers from SwiftData
    func loadProviders() {
        guard let context = modelContext else { return }

        do {
            let descriptor = FetchDescriptor<AIProviderConfig>(
                sortBy: [SortDescriptor(\.createdAt)]
            )
            providers = try context.fetch(descriptor)

            // Set active provider
            if let activeConfig = providers.first(where: { $0.isActive }) {
                Task {
                    try? await setActiveProviderAsync(activeConfig)
                }
            } else if let firstProvider = providers.first {
                // Auto-activate first provider if none active
                firstProvider.isActive = true
                try? context.save()
                Task {
                    try? await setActiveProviderAsync(firstProvider)
                }
            }
        } catch {
            AppLog.ai.error("Failed to load providers: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    // MARK: - Keychain Migration
    
    /// Migrate all existing API keys from SwiftData to Keychain
    @MainActor
    private func migrateAPIKeysToKeychain() async {
        guard !keychainMigrationComplete else { return }
        
        var migrationCount = 0
        for provider in providers {
            if !provider.apiKeyMigrated {
                await provider.migrateAPIKeyToKeychain()
                migrationCount += 1
            }
        }
        
        if migrationCount > 0 {
            AppLog.security.info("Migrated \(migrationCount, privacy: .public) API key(s) to Keychain")
            try? modelContext?.save()
        }
        
        keychainMigrationComplete = true
    }

    /// Create a new provider configuration
    func createProvider(_ config: AIProviderConfig) throws {
        guard let context = modelContext else {
            throw AIProviderError.invalidConfiguration
        }

        context.insert(config)
        try context.save()

        providers.append(config)

        // If this is the first provider, make it active
        if providers.count == 1 {
            config.isActive = true
            try setActiveProvider(config)
        }
    }

    /// Update an existing provider configuration
    func updateProvider(_ config: AIProviderConfig) throws {
        guard let context = modelContext else {
            throw AIProviderError.invalidConfiguration
        }

        config.markUpdated()
        try context.save()

        // Reload if this is the active provider
        if config.isActive {
            try setActiveProvider(config)
        }
    }

    /// Delete a provider configuration
    func deleteProvider(_ config: AIProviderConfig) throws {
        guard let context = modelContext else {
            throw AIProviderError.invalidConfiguration
        }

        let wasActive = config.isActive
        let providerId = config.id

        context.delete(config)
        try context.save()
        
        // Also delete API key from Keychain
        Task {
            try? await KeychainService.shared.deleteAPIKey(for: providerId)
        }

        providers.removeAll { $0.id == providerId }

        // If we deleted the active provider, activate another one
        if wasActive {
            activeProvider = nil
            if let firstProvider = providers.first {
                firstProvider.isActive = true
                Task {
                    try? await setActiveProviderAsync(firstProvider)
                }
            }
        }
    }

    /// Set the active provider (synchronous - legacy)
    func setActiveProvider(_ config: AIProviderConfig) throws {
        guard let context = modelContext else {
            throw AIProviderError.invalidConfiguration
        }

        // Deactivate all providers
        for provider in providers {
            provider.isActive = false
        }

        // Activate selected provider
        config.isActive = true
        try context.save()

        // Create provider instance
        activeProvider = try AIProviderFactory.createProvider(from: config)
    }
    
    /// Set the active provider (async - preferred)
    func setActiveProviderAsync(_ config: AIProviderConfig) async throws {
        guard let context = modelContext else {
            throw AIProviderError.invalidConfiguration
        }

        // Deactivate all providers
        for provider in providers {
            provider.isActive = false
        }

        // Activate selected provider
        config.isActive = true
        try context.save()

        // Create provider instance with async API key retrieval
        activeProvider = try await AIProviderFactory.createProviderAsync(from: config)
    }

    /// Test a provider configuration
    func testProvider(_ config: AIProviderConfig) async throws -> Bool {
        let provider = try AIProviderFactory.createProvider(from: config)

        // Try a simple test request
        let testSelection = "The quick brown fox jumps over the lazy dog."
        _ = try await provider.generateResponse(
            for: testSelection,
            context: nil,
            conversationHistory: []
        )

        return true
    }

    /// Discover models installed locally for Ollama / LM Studio.
    /// Returns an empty array for provider types that don't support discovery.
    /// Throws so the Settings UI can render a tailored error (e.g. "Ollama
    /// isn't running — start it with `ollama serve`").
    func discoverLocalModels(for config: AIProviderConfig) async throws -> [DiscoveredModel] {
        guard config.providerType.supportsModelDiscovery else { return [] }
        guard let baseURL = config.baseURL, !baseURL.isEmpty else {
            throw AIProviderError.invalidBaseURL
        }
        return try await LocalModelDiscovery.models(for: config.providerType, baseURL: baseURL)
    }

    /// Generate response using the active provider.
    ///
    /// Transient failures (network drops, 5xx, rate limits) are retried with
    /// exponential backoff so user-visible errors only surface for real
    /// problems (bad API key, malformed request, etc).
    func generateResponse(
        for selection: String,
        context: String?,
        conversationHistory: [ThreadMessage],
        options: AIRequestOptions = .default,
        retryPolicy: RetryPolicy = .default
    ) async throws -> String {
        guard let provider = activeProvider else {
            throw AIProviderError.invalidConfiguration
        }

        return try await retryPolicy.execute {
            try await provider.generateResponse(
                for: selection,
                context: context,
                conversationHistory: conversationHistory,
                options: options
            )
        }
    }

    /// Stream response using the active provider. Yields incremental
    /// completion chunks; the caller is expected to append them to the
    /// rendered text and finalize when the stream completes.
    ///
    /// Streaming requests don't go through `RetryPolicy` because partial
    /// chunks have already been shown to the user — retrying mid-stream
    /// would create duplicate or interleaved output. Callers can retry the
    /// whole request if needed.
    func streamResponse(
        for selection: String,
        context: String?,
        conversationHistory: [ThreadMessage],
        options: AIRequestOptions = .default
    ) async throws -> AsyncThrowingStream<String, Error> {
        guard let provider = activeProvider else {
            throw AIProviderError.invalidConfiguration
        }
        return try await provider.streamResponse(
            for: selection,
            context: context,
            conversationHistory: conversationHistory,
            options: options
        )
    }

    /// Check if any provider is configured
    var hasActiveProvider: Bool {
        activeProvider != nil
    }

    /// Get active provider name
    var activeProviderName: String? {
        providers.first(where: { $0.isActive })?.name
    }
}

// MARK: - Migration from Legacy ClaudeService

extension AIProviderManager {
    /// Migrate from legacy ClaudeService settings
    func migrateFromLegacySettings() throws {
        // Check if there's a legacy API key in UserDefaults or environment
        let legacyKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
            ?? UserDefaults.standard.string(forKey: "anthropicAPIKey")

        guard let apiKey = legacyKey, !apiKey.isEmpty, providers.isEmpty else {
            return // No migration needed
        }

        // Create a Claude provider from legacy settings
        let claudeProvider = AIProviderConfig.createDefaultClaude(apiKey: apiKey)
        try createProvider(claudeProvider)

        // Remove legacy key from UserDefaults
        UserDefaults.standard.removeObject(forKey: "anthropicAPIKey")

        AppLog.security.info("Migrated legacy Claude API key to new provider system")
    }
}
