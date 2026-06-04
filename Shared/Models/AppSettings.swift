import Foundation
import SwiftData

/// Application-wide settings persisted via SwiftData
@Model
final class AppSettings {
    // MARK: - General Settings

    /// App theme preference
    var theme: String // "light", "dark", "system"

    /// Auto-save interval in seconds
    var autoSaveInterval: TimeInterval

    /// Whether to confirm before deleting books
    var confirmDelete: Bool

    /// Whether to track reading time
    var trackReadingTime: Bool

    // MARK: - Reader Appearance

    /// Font family name (e.g., "System", "Georgia", "Charter")
    var fontFamily: String

    /// Font size in points (8-32)
    var fontSize: Double

    /// Line height multiplier (1.0-3.0)
    var lineHeight: Double

    /// Paragraph spacing in em units
    var paragraphSpacing: Double

    /// Margin width in pixels
    var marginWidth: Double

    /// Background color (hex string, e.g., "#FFFFFF")
    var backgroundColor: String

    /// Text color (hex string)
    var textColor: String

    /// Highlight colors palette (JSON-encoded array of hex strings)
    var highlightColorsJSON: String

    var highlightColors: [String] {
        guard let data = highlightColorsJSON.data(using: .utf8),
              let colors = try? JSONDecoder().decode([String].self, from: data) else {
            return AppSettings.defaultHighlightColors
        }
        return colors
    }

    // MARK: - Library Preferences

    /// Library view mode: "list" or "grid"
    var libraryViewMode: String

    /// Default sort order: "title", "author", "progress", "lastRead", "added"
    var librarySortOrder: String

    /// Sort ascending or descending
    var librarySortAscending: Bool

    // MARK: - AI Provider

    /// Currently active AI provider ID
    var activeProviderId: UUID?

    // MARK: - Onboarding

    /// Whether the user has dismissed the first-launch welcome sheet.
    /// Defaults to `false` for fresh installs, but existing installs will
    /// have this default-initialized to `false` and get the sheet once.
    var hasSeenOnboarding: Bool = false

    // MARK: - AI Prompt Customization

    /// Identifier of the currently selected prompt preset (see
    /// `AIPromptPreset`). When empty, the active prompt is the bundled
    /// "Scholarly" default. The user can switch presets or pick "Custom"
    /// and provide their own text in `customSystemPrompt`.
    var activePromptPresetId: String = AIPromptPreset.scholarly.id

    /// User-edited system prompt. Only consulted when `activePromptPresetId`
    /// is `AIPromptPreset.custom.id`. Stored even when not active so users
    /// can toggle back without losing their text.
    var customSystemPrompt: String = ""

    // MARK: - Accessibility

    /// Whether to follow the system's "Reduce Motion" preference. Defaults
    /// to true so we honor accessibility settings unless the user opts in
    /// to animations. The reader/onboarding consults
    /// `\.accessibilityReduceMotion` directly; this flag exists for users
    /// who want to *override* the system default.
    var respectsReduceMotion: Bool = true

    // MARK: - Initialization

    init(
        theme: String = "system",
        autoSaveInterval: TimeInterval = 30,
        confirmDelete: Bool = true,
        trackReadingTime: Bool = true,
        fontFamily: String = "System",
        fontSize: Double = 16,
        lineHeight: Double = 1.6,
        paragraphSpacing: Double = 1.2,
        marginWidth: Double = 60,
        backgroundColor: String = "#FFFFFF",
        textColor: String = "#000000",
        highlightColorsJSON: String? = nil,
        libraryViewMode: String = "list",
        librarySortOrder: String = "lastRead",
        librarySortAscending: Bool = false,
        activeProviderId: UUID? = nil,
        hasSeenOnboarding: Bool = false
    ) {
        self.theme = theme
        self.autoSaveInterval = autoSaveInterval
        self.confirmDelete = confirmDelete
        self.trackReadingTime = trackReadingTime
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        self.paragraphSpacing = paragraphSpacing
        self.marginWidth = marginWidth
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.highlightColorsJSON = highlightColorsJSON ?? Self.defaultHighlightColorsJSON
        self.libraryViewMode = libraryViewMode
        self.librarySortOrder = librarySortOrder
        self.librarySortAscending = librarySortAscending
        self.activeProviderId = activeProviderId
        self.hasSeenOnboarding = hasSeenOnboarding
    }

    // MARK: - Defaults

    static let defaultHighlightColors = [
        "#FFEB3B", // Yellow
        "#FF9800", // Orange
        "#E91E63", // Pink
        "#9C27B0", // Purple
        "#2196F3", // Blue
        "#4CAF50"  // Green
    ]

    static let defaultHighlightColorsJSON: String = {
        let data = try! JSONEncoder().encode(defaultHighlightColors)
        return String(data: data, encoding: .utf8)!
    }()

    /// Factory method for default settings
    static func createDefault() -> AppSettings {
        return AppSettings()
    }

    // MARK: - Reset Methods

    /// Reset reader appearance to defaults
    func resetReaderAppearance() {
        fontFamily = "System"
        fontSize = 16
        lineHeight = 1.6
        paragraphSpacing = 1.2
        marginWidth = 60
        backgroundColor = "#FFFFFF"
        textColor = "#000000"
        highlightColorsJSON = Self.defaultHighlightColorsJSON
    }

    /// Reset all settings to defaults
    func resetToDefaults() {
        theme = "system"
        autoSaveInterval = 30
        confirmDelete = true
        trackReadingTime = true
        resetReaderAppearance()
        libraryViewMode = "list"
        librarySortOrder = "lastRead"
        librarySortAscending = false
    }
}

// MARK: - Theme Enum (for type safety in UI)

enum AppTheme: String, CaseIterable, Identifiable {
    case light = "light"
    case dark = "dark"
    case system = "system"
    case sepia = "sepia"
    case night = "night"
    case highContrast = "highContrast"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "System"
        case .sepia: return "Sepia"
        case .night: return "Night Mode"
        case .highContrast: return "High Contrast"
        }
    }

    var backgroundColor: String {
        switch self {
        case .light, .system: return "#FFFFFF"
        case .dark: return "#1E1E1E"
        case .sepia: return "#F4ECD8"
        case .night: return "#0A0A0A"
        case .highContrast: return "#000000"
        }
    }

    var textColor: String {
        switch self {
        case .light, .system: return "#000000"
        case .dark: return "#E0E0E0"
        case .sepia: return "#5C4B37"
        case .night: return "#CCCCCC"
        // Pure white on pure black exceeds WCAG AAA (21:1) — used by
        // readers who need maximum contrast (low vision, glare, etc).
        case .highContrast: return "#FFFFFF"
        }
    }
}

// MARK: - Library View Mode Enum

enum LibraryViewMode: String, CaseIterable, Identifiable {
    case list = "list"
    case grid = "grid"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .list: return "List"
        case .grid: return "Grid"
        }
    }
}

// MARK: - Library Sort Order Enum

enum LibrarySortOrder: String, CaseIterable, Identifiable {
    case title = "title"
    case author = "author"
    case progress = "progress"
    case lastRead = "lastRead"
    case added = "added"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .title: return "Title"
        case .author: return "Author"
        case .progress: return "Progress"
        case .lastRead: return "Last Read"
        case .added: return "Date Added"
        }
    }
}
