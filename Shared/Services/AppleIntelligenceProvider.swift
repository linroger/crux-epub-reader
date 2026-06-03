import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// AI Provider using Apple's on-device Foundation Models (Apple Intelligence)
/// Available on devices with Apple Intelligence support (macOS 26+, iOS 26+)
@available(macOS 26.0, iOS 26.0, *)
final class AppleIntelligenceProvider: AIProvider, @unchecked Sendable {
    let id: UUID
    let name: String
    let type: ProviderType = .appleIntelligence
    let supportsStreaming: Bool = true
    
    init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
    
    /// Check if Apple Intelligence is available on this device
    @MainActor
    static var isAvailable: Bool {
        let model = SystemLanguageModel.default
        if case .available = model.availability {
            return true
        }
        return false
    }
    
    /// Get availability status for UI display
    @MainActor
    static var availabilityStatus: AppleIntelligenceAvailability {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            return .notEnabled
        case .unavailable(.modelNotReady):
            return .modelNotReady
        case .unavailable:
            return .unavailable
        }
    }
    
    func generateResponse(
        for selection: String,
        context: String?,
        conversationHistory: [ThreadMessage],
        options: AIRequestOptions
    ) async throws -> String {
        // Create a new session with instructions for margin notes
        let instructions = options.systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? options.systemPrompt!
            : Self.defaultInstructions
        let session = LanguageModelSession(instructions: instructions)
        
        // Build the prompt with conversation history
        var prompt = ""
        
        if let context = context, !context.isEmpty {
            prompt += "Context from the book:\n\"\"\"\n\(context)\n\"\"\"\n\n"
        }
        
        // Add conversation history if present
        if !conversationHistory.isEmpty {
            prompt += "Previous discussion:\n"
            for message in conversationHistory {
                let roleLabel = message.role == .user ? "Reader" : "Assistant"
                prompt += "\(roleLabel): \(message.content)\n"
            }
            prompt += "\n"
        }
        
        prompt += "Highlighted passage:\n\"\(selection)\"\n\n"
        
        if conversationHistory.isEmpty {
            prompt += "Write a margin note for this passage."
        } else {
            prompt += "Continue the discussion."
        }
        
        let response = try await session.respond(to: prompt)
        return response.content
    }
    
    func streamResponse(
        for selection: String,
        context: String?,
        conversationHistory: [ThreadMessage],
        options: AIRequestOptions
    ) async throws -> AsyncThrowingStream<String, Error> {
        let instructions = options.systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? options.systemPrompt!
            : Self.defaultInstructions
        let session = LanguageModelSession(instructions: instructions)
        
        // Build the prompt
        var prompt = ""
        
        if let context = context, !context.isEmpty {
            prompt += "Context from the book:\n\"\"\"\n\(context)\n\"\"\"\n\n"
        }
        
        if !conversationHistory.isEmpty {
            prompt += "Previous discussion:\n"
            for message in conversationHistory {
                let roleLabel = message.role == .user ? "Reader" : "Assistant"
                prompt += "\(roleLabel): \(message.content)\n"
            }
            prompt += "\n"
        }
        
        prompt += "Highlighted passage:\n\"\(selection)\"\n\n"
        
        if conversationHistory.isEmpty {
            prompt += "Write a margin note for this passage."
        } else {
            prompt += "Continue the discussion."
        }
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let stream = session.streamResponse(to: prompt)
                    for try await partialResponse in stream {
                        continuation.yield(partialResponse.content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private static let defaultInstructions = """
    You are generating margin notes for an AI-powered book reader app. Your notes appear inline alongside highlighted text and can start discussion threads.

    Write concise, insightful margin notes in 2-4 sentences. Focus on:
    - Literal vs. figurative meaning, symbolic layers
    - Literary devices, formal techniques
    - Etymology, translation issues, textual variants
    - Historical, philosophical, or theological context
    - Connection to the work's broader argument or structure
    - Intertextual allusions or echoes

    Be terse and substantive. Skip surface-level observations. Assume literary familiarity.
    """
}
#endif

/// Availability status for Apple Intelligence
enum AppleIntelligenceAvailability {
    case available
    case deviceNotEligible
    case notEnabled
    case modelNotReady
    case unavailable
    
    var description: String {
        switch self {
        case .available:
            return "Apple Intelligence is available"
        case .deviceNotEligible:
            return "This device doesn't support Apple Intelligence"
        case .notEnabled:
            return "Apple Intelligence is not enabled. Enable it in System Settings."
        case .modelNotReady:
            return "Apple Intelligence is downloading or initializing..."
        case .unavailable:
            return "Apple Intelligence is currently unavailable"
        }
    }
    
    var canBeEnabled: Bool {
        self == .notEnabled
    }
}

// MARK: - Availability Helpers

/// Helper to check Apple Intelligence availability at runtime
enum AppleIntelligenceHelper {
    /// Check if Apple Intelligence is available on this device
    @MainActor
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            return AppleIntelligenceProvider.isAvailable
        }
        #endif
        return false
    }
    
    /// Get availability status for UI display
    @MainActor
    static var availabilityStatus: AppleIntelligenceAvailability {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            return AppleIntelligenceProvider.availabilityStatus
        }
        #endif
        return .unavailable
    }
}
