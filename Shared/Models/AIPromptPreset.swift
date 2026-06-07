import Foundation

/// Built-in system-prompt presets the user can pick from in
/// Settings → AI Prompt. Selecting a preset stores its `id` in
/// `AppSettings.activePromptPresetId` and the manager forwards the
/// resolved text to every provider request.
///
/// "Custom" is a sentinel preset that asks the manager to fall back to
/// `AppSettings.customSystemPrompt` so users can write their own voice
/// without losing the built-in presets.
enum AIPromptPreset: String, CaseIterable, Identifiable, Codable {
    case scholarly
    case casual
    case socratic
    case minimalist
    case technical
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .scholarly:  return "Scholarly"
        case .casual:     return "Casual"
        case .socratic:   return "Socratic"
        case .minimalist: return "Minimalist"
        case .technical:  return "Technical"
        case .custom:     return "Custom"
        }
    }

    var subtitle: String {
        switch self {
        case .scholarly:  return "Graduate-level depth; literary, philosophical, historical analysis."
        case .casual:     return "Friendly, conversational tone; clear and approachable."
        case .socratic:   return "Asks probing questions rather than declaring answers."
        case .minimalist: return "Tight notes — one or two precise sentences."
        case .technical:  return "Code, architecture, performance, and edge-cases focus."
        case .custom:     return "Edit your own system prompt below."
        }
    }

    /// SF Symbol used in the preset row.
    var symbolName: String {
        switch self {
        case .scholarly:  return "graduationcap.fill"
        case .casual:     return "bubble.left.and.bubble.right.fill"
        case .socratic:   return "questionmark.bubble.fill"
        case .minimalist: return "scissors"
        case .technical:  return "chevron.left.forwardslash.chevron.right"
        case .custom:     return "pencil.and.list.clipboard"
        }
    }

    /// Bundled system-prompt text for the preset.
    var systemPrompt: String {
        switch self {
        case .scholarly:
            // Shares the built-in default so "Scholarly" and the providers'
            // baseline behavior stay in lockstep. Content-first: explains the
            // substance, never critiques the prose.
            return AIPrompts.marginNote

        case .casual:
            return """
            You are a thoughtful reading companion. When the user highlights a passage, respond like a friend who has read this book and wants to share something interesting about it. Keep things warm and conversational. Two or three sentences is usually plenty. Avoid jargon; if the passage uses a term of art, explain it plainly. Don't lecture — share the kind of observation that makes someone say "huh, never thought of it that way."
            """

        case .socratic:
            return """
            You are a Socratic interlocutor. Instead of explaining what the passage means, respond with one or two probing questions that help the reader think more deeply about it. Your questions should target the passage's assumptions, its implications, its blind spots, or how it connects to broader ideas. Don't answer the questions; trust the reader to do that. Keep it brief (no more than three short questions). If a follow-up requires clarification, give a one-sentence neutral framing before posing the next question.
            """

        case .minimalist:
            return """
            You are a minimalist annotator. Read the highlighted passage and respond with one or two short sentences that capture its essence, surface a hidden assumption, or note a connection to something the reader might know. No preamble, no bullet lists, no quoting. Be tight, sharp, and quotable. Aim for under 40 words.
            """

        case .technical:
            return """
            You are a senior technical reviewer. When the user highlights code, design, or systems prose, focus on substance: correctness, edge cases, performance implications, architectural tradeoffs, and what could go wrong in production. Cite specific failure modes when they're real. Don't write "good observation" — write what the reader probably missed. Prose for non-code passages should still emphasize mechanism over commentary. 2-4 sentences typical; bullet lists are fine when comparing alternatives.
            """

        case .custom:
            // Custom resolves to AppSettings.customSystemPrompt at call time;
            // the value here is only used if the user hasn't typed anything.
            return ""
        }
    }
}
