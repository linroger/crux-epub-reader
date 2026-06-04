import SwiftUI
import SwiftData

/// Service for managing app-wide theme and applying it to the interface
@Observable
class ThemeManager {
    private var settings: AppSettings?

    /// Current color scheme preference
    var colorScheme: ColorScheme? {
        guard let themeStr = settings?.theme else { return nil }
        let theme = AppTheme(rawValue: themeStr) ?? .system

        switch theme {
        case .light, .sepia:
            return .light
        case .dark, .night, .highContrast:
            // High contrast renders white-on-black, which fits the
            // dark color scheme so chrome reads correctly.
            return .dark
        case .system:
            return nil // Let system handle it
        }
    }

    /// Configure the theme manager with settings
    func configure(settings: AppSettings) {
        self.settings = settings
    }

    /// Apply theme colors to reader view
    func applyReaderTheme() -> (backgroundColor: Color, textColor: Color) {
        guard let settings = settings else {
            return (Color(hex: "#FFFFFF") ?? .white, Color(hex: "#000000") ?? .black)
        }

        return (
            Color(hex: settings.backgroundColor) ?? .white,
            Color(hex: settings.textColor) ?? .black
        )
    }

    /// Get CSS for reader web view based on current theme
    func getReaderCSS() -> String {
        guard let settings = settings else {
            return defaultReaderCSS()
        }

        return """
        :root {
            --background-color: \(settings.backgroundColor);
            --text-color: \(settings.textColor);
            --font-family: \(settings.fontFamily == "System" ? "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" : settings.fontFamily);
            --font-size: \(settings.fontSize)pt;
            --line-height: \(settings.lineHeight);
            --paragraph-spacing: \(settings.paragraphSpacing)em;
            --margin-width: \(settings.marginWidth)px;
        }

        body {
            background-color: var(--background-color);
            color: var(--text-color);
            font-family: var(--font-family);
            font-size: var(--font-size);
            line-height: var(--line-height);
            margin: var(--margin-width);
            padding: 0;
            transition: background-color 0.3s ease, color 0.3s ease;
        }

        p {
            margin-bottom: var(--paragraph-spacing);
        }

        a {
            color: var(--text-color);
            opacity: 0.8;
        }

        a:hover {
            opacity: 1;
        }

        /* Selection styling */
        ::selection {
            background-color: rgba(59, 130, 246, 0.3);
        }

        /* Smooth transitions for theme changes */
        * {
            transition: background-color 0.3s ease, color 0.3s ease;
        }
        """
    }

    private func defaultReaderCSS() -> String {
        return """
        body {
            background-color: #FFFFFF;
            color: #000000;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            font-size: 16pt;
            line-height: 1.6;
            margin: 60px;
        }

        p {
            margin-bottom: 1.2em;
        }
        """
    }
}
