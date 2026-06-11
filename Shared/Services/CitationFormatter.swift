import Foundation

/// Produces citation strings for a book in the four formats students and
/// researchers most often need (APA, MLA, Chicago, BibTeX). All inputs are
/// optional so we degrade gracefully when EPUB metadata is sparse.
enum CitationStyle: String, CaseIterable, Identifiable {
    case apa = "APA"
    case mla = "MLA"
    case chicago = "Chicago"
    case bibtex = "BibTeX"

    var id: String { rawValue }

    var displayName: String { rawValue }
}

enum CitationFormatter {
    /// Generate a citation for the given book in the given style.
    static func citation(for book: Book, style: CitationStyle) -> String {
        let author = book.author?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = book.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let publisher = book.metadata.publisher?.trimmingCharacters(in: .whitespacesAndNewlines)
        let year = book.metadata.publicationDate.map { yearOnly(from: $0) }

        switch style {
        case .apa:    return apa(author: author, year: year, title: title, publisher: publisher)
        case .mla:    return mla(author: author, title: title, publisher: publisher, year: year)
        case .chicago: return chicago(author: author, title: title, publisher: publisher, year: year)
        case .bibtex: return bibtex(author: author, title: title, publisher: publisher, year: year)
        }
    }

    // MARK: - Style implementations

    /// APA 7: `Last, F. M. (Year). *Title*. Publisher.`
    private static func apa(author: String?, year: String?, title: String, publisher: String?) -> String {
        var parts: [String] = []
        if let author {
            parts.append(apaAuthor(author))
        }
        parts.append("(\(year ?? "n.d.")).")
        parts.append("*\(title)*.")
        if let publisher { parts.append("\(publisher).") }
        return parts.joined(separator: " ")
    }

    /// MLA 9: `Last, First. *Title*. Publisher, Year.`
    private static func mla(author: String?, title: String, publisher: String?, year: String?) -> String {
        var parts: [String] = []
        if let author {
            parts.append("\(mlaAuthor(author)).")
        }
        parts.append("*\(title)*.")
        var tail: [String] = []
        if let publisher { tail.append(publisher) }
        if let year { tail.append(year) }
        if !tail.isEmpty { parts.append(tail.joined(separator: ", ") + ".") }
        return parts.joined(separator: " ")
    }

    /// Chicago (notes-bibliography), book entry:
    /// `First Last, *Title* (Publisher, Year).`
    private static func chicago(author: String?, title: String, publisher: String?, year: String?) -> String {
        var lead: [String] = []
        if let author { lead.append("\(author),") }
        lead.append("*\(title)*")
        var paren: [String] = []
        if let publisher { paren.append(publisher) }
        if let year { paren.append(year) }
        if !paren.isEmpty {
            lead.append("(\(paren.joined(separator: ", "))).")
        } else {
            lead[lead.count - 1] += "."
        }
        return lead.joined(separator: " ")
    }

    /// BibTeX `@book{key, …}`. The citation key is generated from the
    /// first author's surname plus year, which is the most common shape.
    private static func bibtex(author: String?, title: String, publisher: String?, year: String?) -> String {
        let key = bibtexKey(author: author, year: year, title: title)
        var fields: [String] = []
        if let author { fields.append("  author = {\(author)}") }
        fields.append("  title = {\(title)}")
        if let publisher { fields.append("  publisher = {\(publisher)}") }
        if let year { fields.append("  year = {\(year)}") }
        let body = fields.joined(separator: ",\n")
        return "@book{\(key),\n\(body)\n}"
    }

    // MARK: - Helpers

    private static func yearOnly(from date: Date) -> String {
        let cal = Calendar.current
        return String(cal.component(.year, from: date))
    }

    /// "Jane Austen" → "Austen, J."
    /// Multi-author "Jane Austen and Mary Shelley" → "Austen, J., & Shelley, M."
    private static func apaAuthor(_ raw: String) -> String {
        let authors = splitAuthors(raw)
        let formatted = authors.compactMap { author -> String? in
            let parts = author.split(separator: " ").map(String.init)
            guard let last = parts.last else { return nil }
            let initials = parts.dropLast().compactMap { $0.first.map { "\($0)." } }
            let initialsString = initials.joined(separator: " ")
            return initialsString.isEmpty ? last : "\(last), \(initialsString)"
        }
        if formatted.count <= 1 { return formatted.first ?? raw }
        let head = formatted.dropLast().joined(separator: ", ")
        return "\(head), & \(formatted.last!)"
    }

    /// "Jane Austen" → "Austen, Jane"
    /// MLA expects only the first author in inverted form; trailing
    /// authors stay in natural order.
    private static func mlaAuthor(_ raw: String) -> String {
        let authors = splitAuthors(raw)
        guard let first = authors.first else { return raw }
        let parts = first.split(separator: " ").map(String.init)
        guard parts.count >= 2, let last = parts.last else { return first }
        let rest = parts.dropLast().joined(separator: " ")
        var head = "\(last), \(rest)"
        if authors.count > 1 {
            head += ", and " + authors.dropFirst().joined(separator: ", ")
        }
        return head
    }

    /// EPUB author fields sometimes encode multiple authors joined by
    /// "and", "&", or ";". Pick the most common separators.
    private static func splitAuthors(_ raw: String) -> [String] {
        var trimmed = raw
        for sep in [" and ", " & ", "; "] {
            trimmed = trimmed.replacingOccurrences(of: sep, with: "|")
        }
        return trimmed
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Build a BibTeX citation key from the first author's surname + year.
    /// Falls back to a slugified title prefix if author is unknown.
    private static func bibtexKey(author: String?, year: String?, title: String) -> String {
        let lastName: String? = author.flatMap { name in
            splitAuthors(name).first?.split(separator: " ").last.map(String.init)
        }
        let yearSuffix = year ?? "nd"
        if let lastName, !lastName.isEmpty {
            return "\(slugify(lastName))\(yearSuffix)"
        }
        return "\(slugify(String(title.prefix(20))))\(yearSuffix)"
    }

    private static func slugify(_ raw: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789")
        let scalars = raw.lowercased().unicodeScalars.filter { allowed.contains($0) }
        return String(String.UnicodeScalarView(scalars))
    }
}
