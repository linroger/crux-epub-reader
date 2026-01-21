import Foundation
import SwiftData
import Observation

/// Manages AI provider lifecycle and selection
@Observable
final class AIProviderManager {
    private(set) var providers: [AIProviderConfig] = []
    private(set) var activeProvider: (any AIProvider)?
    private var modelContext: ModelContext?

    init() {}

    /// Initialize with SwiftData model context
    func initialize(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadProviders()
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
                try? setActiveProvider(activeConfig)
            } else if let firstProvider = providers.first {
                // Auto-activate first provider if none active
                firstProvider.isActive = true
                try? context.save()
                try? setActiveProvider(firstProvider)
            }
        } catch {
            print("Failed to load providers: \(error)")
        }
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

        context.delete(config)
        try context.save()

        providers.removeAll { $0.id == config.id }

        // If we deleted the active provider, activate another one
        if wasActive {
            activeProvider = nil
            if let firstProvider = providers.first {
                firstProvider.isActive = true
                try setActiveProvider(firstProvider)
            }
        }
    }

    /// Set the active provider
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

    /// Generate response using the active provider
    func generateResponse(
        for selection: String,
        context: String?,
        conversationHistory: [ThreadMessage]
    ) async throws -> String {
        guard let provider = activeProvider else {
            throw AIProviderError.invalidConfiguration
        }

        return try await provider.generateResponse(
            for: selection,
            context: context,
            conversationHistory: conversationHistory
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

        print("Migrated legacy Claude API key to new provider system")
    }
}
