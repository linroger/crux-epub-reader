import Foundation

/// Loads reader resources from the app bundle for WKWebView
enum ReaderResources {

    /// Platform identifier for template substitution
    enum Platform: String {
        case macOS = "macos"
        case iOS = "ios"

        static var current: Platform {
            #if os(macOS)
            return .macOS
            #else
            return .iOS
            #endif
        }
    }

    /// Base URL for reader resources in bundle (for relative script/css loading)
    static var baseURL: URL? {
        Bundle.main.url(forResource: "reader-template", withExtension: "html")?
            .deletingLastPathComponent()
    }

    /// Loads a JavaScript file from the Reader bundle directory
    static func loadScript(named name: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return content
    }

    /// Loads the CSS file from the Reader bundle directory
    static func loadCSS() -> String? {
        guard let url = Bundle.main.url(forResource: "reader", withExtension: "css"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return content
    }

    /// Loads and populates the HTML template with content
    static func buildHTML(content: String, platform: Platform = .current, customCSS: String? = nil) -> String? {
        guard let templateURL = Bundle.main.url(forResource: "reader-template", withExtension: "html"),
              var template = try? String(contentsOf: templateURL, encoding: .utf8) else {
            return nil
        }

        template = template
            .replacingOccurrences(of: "{{PLATFORM}}", with: platform.rawValue)
            .replacingOccurrences(of: "{{CONTENT}}", with: content)

        // Inject custom CSS if provided. The style element carries a stable
        // id so appearance changes (theme, font, margins…) can be applied to
        // a *live* page by swapping its textContent from Swift — see
        // `WebViewCoordinator.applyCustomCSS` — instead of reloading the
        // chapter and losing the reading position.
        if let customCSS = customCSS {
            let styleTag = "<style id=\"crux-custom-css\">\n\(customCSS)\n</style>"
            // Insert before </head> tag
            if let headEnd = template.range(of: "</head>") {
                template.insert(contentsOf: styleTag, at: headEnd.lowerBound)
            }
        }

        return template
    }

    // MARK: - Reading Fonts

    /// Curated reading typefaces offered in the appearance popover.
    /// `cssStack` is `nil` for the default, which keeps reader.css's
    /// built-in literary serif stack (Iowan Old Style → Palatino → Georgia).
    struct ReadingFont: Identifiable, Equatable {
        let storedValue: String
        let displayName: String
        let cssStack: String?
        var id: String { storedValue }
    }

    static let readingFonts: [ReadingFont] = [
        ReadingFont(storedValue: "System", displayName: "Default (Iowan)", cssStack: nil),
        ReadingFont(storedValue: "New York", displayName: "New York",
                    cssStack: "ui-serif, \"New York\", Georgia, serif"),
        ReadingFont(storedValue: "Georgia", displayName: "Georgia",
                    cssStack: "Georgia, \"Times New Roman\", serif"),
        ReadingFont(storedValue: "Palatino", displayName: "Palatino",
                    cssStack: "\"Palatino Linotype\", Palatino, \"Book Antiqua\", Georgia, serif"),
        ReadingFont(storedValue: "Charter", displayName: "Charter",
                    cssStack: "Charter, \"Bitstream Charter\", Georgia, serif"),
        ReadingFont(storedValue: "Baskerville", displayName: "Baskerville",
                    cssStack: "Baskerville, \"Libre Baskerville\", Georgia, serif"),
        ReadingFont(storedValue: "Hoefler Text", displayName: "Hoefler Text",
                    cssStack: "\"Hoefler Text\", Georgia, serif"),
        ReadingFont(storedValue: "San Francisco", displayName: "San Francisco",
                    cssStack: "system-ui, -apple-system, BlinkMacSystemFont, sans-serif"),
        ReadingFont(storedValue: "Helvetica Neue", displayName: "Helvetica Neue",
                    cssStack: "\"Helvetica Neue\", Helvetica, Arial, sans-serif"),
        ReadingFont(storedValue: "Avenir Next", displayName: "Avenir Next",
                    cssStack: "\"Avenir Next\", Avenir, \"Helvetica Neue\", sans-serif")
    ]

    /// CSS font-family stack for a stored font value. Returns `nil` for the
    /// default (keep reader.css's serif stack). Unknown values — e.g. a name
    /// typed into Settings — fall back to quoting the name with a serif tail,
    /// preserving the old behavior.
    static func fontStack(for storedValue: String) -> String? {
        if let known = readingFonts.first(where: { $0.storedValue == storedValue }) {
            return known.cssStack
        }
        return "\"\(storedValue)\", Georgia, serif"
    }

    /// Generates custom CSS from reader settings.
    ///
    /// The result is baked into the initial HTML *and* swapped into the live
    /// page when settings change (`WebViewCoordinator.applyCustomCSS`), so
    /// every control — theme, font, size, spacing, margins — updates without
    /// a chapter reload or scroll-position loss.
    ///
    /// Color strategy:
    /// - `theme == .system` emits no palette, deferring to reader.css's
    ///   built-in light palette + `prefers-color-scheme: dark` override so
    ///   the page tracks OS appearance live.
    /// - Any explicit theme emits the full `--crux-*` variable set
    ///   (accent, rules, highlights included) so highlights and margin-note
    ///   chrome stay on-palette.
    /// - `backgroundColor`/`textColor` act as user overrides: they're only
    ///   emitted when they differ from the theme's own defaults (set via
    ///   Settings' custom color pickers).
    static func generateCustomCSS(
        fontFamily: String,
        fontSize: Double,
        lineHeight: Double,
        paragraphSpacing: Double,
        marginWidth: Double,
        theme: AppTheme,
        backgroundColor: String,
        textColor: String
    ) -> String {
        var rootVars: [String] = []

        if let stack = fontStack(for: fontFamily) {
            rootVars.append("--crux-font-body: \(stack);")
        }

        if let palette = theme.readerPalette {
            rootVars.append(contentsOf: [
                "--crux-bg: \(palette.background);",
                "--crux-text: \(palette.text);",
                "--crux-text-muted: \(palette.muted);",
                "--crux-accent: \(palette.accent);",
                "--crux-rule: \(palette.rule);",
                "--crux-selection: \(palette.selection);",
                "--crux-highlight: \(palette.highlight);",
                "--crux-highlight-hover: \(palette.highlightHover);"
            ])
        }

        // Custom color overrides from Settings' pickers. Compared against the
        // *theme's* defaults so picking a theme cleanly resets them, but a
        // hand-picked page color always wins.
        //
        // One guard: stores that predate the theme system hold the factory
        // values (#FFFFFF/#000000) without the user ever having touched a
        // picker. Treating those as deliberate overrides while following the
        // OS appearance would pin black-on-white into dark mode — so on the
        // System theme, factory values are ignored rather than emitted.
        let factoryBackground = "#FFFFFF"
        let factoryText = "#000000"
        let backgroundIsFactory = backgroundColor.caseInsensitiveCompare(factoryBackground) == .orderedSame
        let textIsFactory = textColor.caseInsensitiveCompare(factoryText) == .orderedSame

        if backgroundColor.caseInsensitiveCompare(theme.backgroundColor) != .orderedSame,
           !(theme == .system && backgroundIsFactory) {
            rootVars.append("--crux-bg: \(backgroundColor);")
        }
        if textColor.caseInsensitiveCompare(theme.textColor) != .orderedSame,
           !(theme == .system && textIsFactory) {
            rootVars.append("--crux-text: \(textColor);")
        }

        let rootBlock = rootVars.isEmpty ? "" : """
        :root {
            \(rootVars.joined(separator: "\n    "))
        }
        """

        // Margins are macOS-only: the iOS layout pins its own prose padding
        // (`:root[data-platform="ios"]`, plus the narrow-viewport media
        // query) and has no margin-notes gutter to balance against.
        let clampedMargin = max(0, min(400, Int(marginWidth)))

        return """
        \(rootBlock)

        .crux-content {
            font-size: \(fontSize)px;
            line-height: \(lineHeight);
        }

        :root[data-platform="macos"] .crux-content {
            padding-left: \(clampedMargin)px;
            padding-right: \(clampedMargin)px;
        }

        .crux-content p {
            margin-bottom: \(paragraphSpacing)em;
        }
        """
    }
}
