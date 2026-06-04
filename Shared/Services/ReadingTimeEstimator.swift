import Foundation

/// Estimates reading time for a book or chapter, in minutes.
///
/// We don't need to be precise — the value is shown as a friendly label
/// ("~12 min read"), so we pick a sensible default WPM (220 — average
/// adult reading speed) and let the user adjust later if needed.
///
/// Whitespace-tokenized word counts ignore HTML tags by stripping them
/// first. Counts are deliberately conservative: stripping markup means a
/// book with heavy formatting reports honestly shorter text than its raw
/// size implies.
enum ReadingTimeEstimator {
    /// Default reading speed in words per minute.
    static let defaultWordsPerMinute: Double = 220

    /// Estimate minutes to read the given HTML/plain text at the given WPM.
    /// Returns `nil` for empty input so callers can hide the label.
    static func minutes(forText text: String, wordsPerMinute wpm: Double = defaultWordsPerMinute) -> Double? {
        let plain = stripHTML(text)
        let count = wordCount(in: plain)
        guard count > 0 else { return nil }
        return Double(count) / wpm
    }

    /// Estimate cumulative minutes for an ordered list of chapter HTML
    /// strings. Used by the library/book-detail row to surface "~3 hr read".
    static func totalMinutes(forChapters chapters: [String], wordsPerMinute wpm: Double = defaultWordsPerMinute) -> Double {
        chapters.reduce(0.0) { partial, html in
            partial + (minutes(forText: html, wordsPerMinute: wpm) ?? 0)
        }
    }

    /// Format minutes as a short human label.
    /// 0–1     → "less than a minute"
    /// 1–60    → "12 min read"
    /// 60+     → "2 hr 15 min read"
    static func label(forMinutes minutes: Double) -> String {
        if minutes < 1 { return "less than a minute" }
        let total = Int(minutes.rounded())
        if total < 60 { return "\(total) min read" }
        let hours = total / 60
        let remainder = total % 60
        if remainder == 0 { return "\(hours) hr read" }
        return "\(hours) hr \(remainder) min read"
    }

    /// Convenience for "X min read" applied to a single chapter or block of HTML.
    static func label(forText text: String, wordsPerMinute wpm: Double = defaultWordsPerMinute) -> String? {
        guard let minutes = minutes(forText: text, wordsPerMinute: wpm) else { return nil }
        return label(forMinutes: minutes)
    }

    // MARK: - Helpers

    /// Quick & dirty HTML tag stripper. Good enough for word counts.
    /// Avoid pulling in a full parser here; chapters are sometimes
    /// megabytes of XHTML and we just need an approximation.
    static func stripHTML(_ html: String) -> String {
        // Remove tags first, then collapse whitespace.
        let withoutTags = html.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        return withoutTags.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Count whitespace-separated tokens. Cheaper and more predictable
    /// than `NSLinguisticTagger` for our use case.
    static func wordCount(in text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        return text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }
}
