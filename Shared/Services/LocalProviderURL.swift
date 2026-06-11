import Foundation

/// Small URL-building helpers shared by local AI providers (Ollama, LM Studio).
///
/// Kept internal so both `OllamaProvider` and `LMStudioProvider` can use the
/// same trimming / path-appending logic without each defining their own
/// fileprivate copy.
extension String {
    /// Returns the string with any trailing `/` characters removed.
    /// Idempotent and safe to call on already-trimmed input.
    var trimmedTrailingSlash: String {
        var copy = self
        while copy.hasSuffix("/") { copy.removeLast() }
        return copy
    }

    /// Concatenate a path component onto this URL string, ensuring exactly
    /// one `/` between them. The caller is responsible for already having
    /// trimmed trailing slashes if they want the join to feel symmetrical.
    func appendingPath(_ path: String) -> String {
        let suffix = path.hasPrefix("/") ? path : "/" + path
        return self + suffix
    }
}
