import Foundation

/// Built-in templates the user can insert when writing a highlight note.
///
/// Each template renders a small scaffold with question prompts so users
/// who haven't yet developed a personal annotation rhythm have something
/// useful to copy. Picked from a menu in the highlight note editor.
enum NoteTemplate: String, CaseIterable, Identifiable {
    case characterAnalysis
    case theme
    case citation
    case question
    case connection
    case vocabulary

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .characterAnalysis: return "Character Analysis"
        case .theme:             return "Theme"
        case .citation:          return "Citation"
        case .question:          return "Question"
        case .connection:        return "Connection"
        case .vocabulary:        return "Vocabulary"
        }
    }

    var symbolName: String {
        switch self {
        case .characterAnalysis: return "person.fill.questionmark"
        case .theme:             return "sparkles.rectangle.stack"
        case .citation:          return "quote.bubble"
        case .question:          return "questionmark.circle"
        case .connection:        return "link"
        case .vocabulary:        return "character.book.closed"
        }
    }

    /// Markdown scaffold inserted into the highlight note editor. The
    /// reader can then fill in the bracketed sections.
    var body: String {
        switch self {
        case .characterAnalysis:
            return """
            **Character:** [name]
            **Trait observed:** [trait]
            **Evidence in passage:** [quote / detail]
            **Significance:** [why it matters]
            """
        case .theme:
            return """
            **Theme:** [theme name]
            **Manifestation here:** [how the passage expresses it]
            **Echoed elsewhere:** [other passages]
            """
        case .citation:
            return """
            **Quote:** [passage text]
            **Page / location:** [reference]
            **Use case:** [paper / project this supports]
            """
        case .question:
            return """
            **Question:** [your question]
            **Why it matters:** [stakes]
            **Possible answer:** [your hypothesis]
            """
        case .connection:
            return """
            **Connects to:** [other text / idea]
            **Relationship:** [agree / contrast / extends]
            **Insight:** [what the comparison reveals]
            """
        case .vocabulary:
            return """
            **Term:** [word]
            **In context:** "[short quote]"
            **Definition:** [meaning here]
            **Worth remembering:** [why]
            """
        }
    }
}
