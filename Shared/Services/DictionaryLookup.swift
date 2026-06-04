import Foundation

#if os(macOS)
import AppKit
#endif

/// Opens the system Dictionary.app for the given word.
///
/// We rely on the well-known `dict://` URL scheme that macOS routes to
/// Dictionary.app's lookup panel. The URL is percent-escaped against the
/// query-allowed character set so multi-word selections still resolve.
enum DictionaryLookup {
    /// Look up the trimmed first word/phrase of `text` in the system
    /// dictionary. Long passages are truncated to the first two words —
    /// Dictionary.app's lookup field doesn't handle full sentences well
    /// and the user usually wants the single term they highlighted.
    static func lookUp(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // Cap at the first two whitespace-separated tokens so users who
        // highlight an entire sentence still get a useful lookup.
        let words = trimmed.split(separator: " ").prefix(2).joined(separator: " ")
        guard let encoded = words.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "dict://" + encoded) else {
            return false
        }

        #if os(macOS)
        return NSWorkspace.shared.open(url)
        #else
        // iOS uses UIReferenceLibraryViewController which the caller
        // surfaces directly; no URL-scheme equivalent.
        return false
        #endif
    }
}
