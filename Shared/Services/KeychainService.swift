import Foundation
import Security

/// Thread-safe service for storing and retrieving sensitive data from the Keychain
/// Used primarily for API key storage for AI providers
actor KeychainService {
    /// Shared instance for app-wide use
    static let shared = KeychainService()
    
    /// Service identifier for Keychain items
    private let serviceIdentifier = "com.crux.aiProviders"
    
    /// Error types for Keychain operations
    enum KeychainError: LocalizedError {
        case saveFailed(OSStatus)
        case loadFailed(OSStatus)
        case deleteFailed(OSStatus)
        case dataConversionFailed
        case itemNotFound
        case unexpectedError(String)
        
        var errorDescription: String? {
            switch self {
            case .saveFailed(let status):
                return "Failed to save to Keychain (status: \(status))"
            case .loadFailed(let status):
                return "Failed to load from Keychain (status: \(status))"
            case .deleteFailed(let status):
                return "Failed to delete from Keychain (status: \(status))"
            case .dataConversionFailed:
                return "Failed to convert Keychain data"
            case .itemNotFound:
                return "Item not found in Keychain"
            case .unexpectedError(let message):
                return "Keychain error: \(message)"
            }
        }
    }
    
    // MARK: - API Key Operations
    
    /// Save an API key for a specific provider
    /// - Parameters:
    ///   - apiKey: The API key to store
    ///   - providerId: The unique identifier of the AI provider
    func saveAPIKey(_ apiKey: String, for providerId: UUID) throws {
        guard !apiKey.isEmpty else {
            // If empty, delete any existing key
            try? deleteAPIKey(for: providerId)
            return
        }
        
        guard let data = apiKey.data(using: .utf8) else {
            throw KeychainError.dataConversionFailed
        }
        
        let account = providerId.uuidString
        
        // Query for existing item
        let existingQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: account
        ]
        
        // Check if item already exists
        let existingStatus = SecItemCopyMatching(existingQuery as CFDictionary, nil)
        
        if existingStatus == errSecSuccess {
            // Update existing item
            let updateAttributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrModificationDate as String: Date()
            ]
            
            let updateStatus = SecItemUpdate(existingQuery as CFDictionary, updateAttributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.saveFailed(updateStatus)
            }
        } else if existingStatus == errSecItemNotFound {
            // Add new item
            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: serviceIdentifier,
                kSecAttrAccount as String: account,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
                kSecAttrCreationDate as String: Date(),
                kSecAttrModificationDate as String: Date(),
                kSecAttrLabel as String: "Crux AI Provider API Key",
                kSecAttrDescription as String: "API key for AI provider \(account)"
            ]
            
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.saveFailed(addStatus)
            }
        } else {
            throw KeychainError.saveFailed(existingStatus)
        }
    }
    
    /// Retrieve an API key for a specific provider
    /// - Parameter providerId: The unique identifier of the AI provider
    /// - Returns: The stored API key, or nil if not found
    func loadAPIKey(for providerId: UUID) throws -> String? {
        let account = providerId.uuidString
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let apiKey = String(data: data, encoding: .utf8) else {
                throw KeychainError.dataConversionFailed
            }
            return apiKey
            
        case errSecItemNotFound:
            return nil
            
        default:
            throw KeychainError.loadFailed(status)
        }
    }
    
    /// Delete an API key for a specific provider
    /// - Parameter providerId: The unique identifier of the AI provider
    func deleteAPIKey(for providerId: UUID) throws {
        let account = providerId.uuidString
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
    
    /// Check if an API key exists for a specific provider
    /// - Parameter providerId: The unique identifier of the AI provider
    /// - Returns: True if an API key exists
    func hasAPIKey(for providerId: UUID) -> Bool {
        let account = providerId.uuidString
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: account,
            kSecReturnData as String: false
        ]
        
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    // MARK: - Migration Support
    
    /// Migrate an API key from plain text storage to Keychain
    /// - Parameters:
    ///   - apiKey: The API key to migrate
    ///   - providerId: The provider's unique identifier
    /// - Returns: True if migration succeeded
    @discardableResult
    func migrateAPIKey(_ apiKey: String, for providerId: UUID) throws -> Bool {
        guard !apiKey.isEmpty else { return false }
        
        // Check if already migrated
        if hasAPIKey(for: providerId) {
            return true
        }
        
        try saveAPIKey(apiKey, for: providerId)
        return true
    }
    
    // MARK: - Cleanup
    
    /// Delete all stored API keys (for complete data reset)
    func deleteAllAPIKeys() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
    
    /// Get all provider IDs that have stored API keys
    /// - Returns: Array of provider UUIDs with stored keys
    func getAllStoredProviderIds() throws -> [UUID] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        switch status {
        case errSecSuccess:
            guard let items = result as? [[String: Any]] else {
                return []
            }
            return items.compactMap { item -> UUID? in
                guard let account = item[kSecAttrAccount as String] as? String else {
                    return nil
                }
                return UUID(uuidString: account)
            }
            
        case errSecItemNotFound:
            return []
            
        default:
            throw KeychainError.loadFailed(status)
        }
    }
}

// MARK: - Non-isolated Convenience Methods

extension KeychainService {
    /// Synchronous wrapper for loading API key (for use in non-async contexts)
    /// Note: This blocks the calling thread; prefer async version when possible
    nonisolated func loadAPIKeySync(for providerId: UUID) -> String? {
        var result: String?
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            result = try? await self.loadAPIKey(for: providerId)
            semaphore.signal()
        }
        
        semaphore.wait()
        return result
    }
}
