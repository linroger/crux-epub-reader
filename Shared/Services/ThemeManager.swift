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

    // NOTE: The reader page's CSS is generated in one place only —
    // `ReaderResources.generateCustomCSS` — and applied live via
    // `WebViewCoordinator.applyCustomCSS`. ThemeManager's old
    // `getReaderCSS`/`applyReaderTheme` duplicates (different variable
    // names, never wired to the WebView) were removed.
}
