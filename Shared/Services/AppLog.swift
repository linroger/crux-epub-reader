import Foundation
import os

/// Centralized structured logging using `os.Logger`.
///
/// Replaces ad-hoc `print()` statements with categorized log channels so
/// developers can filter output by subsystem in Console.app or `log stream`.
///
/// Example:
/// ```swift
/// AppLog.ai.info("Generated response in \(elapsed) ms")
/// AppLog.parser.error("Failed to parse EPUB: \(error.localizedDescription, privacy: .public)")
/// ```
enum AppLog {
    /// Subsystem identifier shared by all loggers
    private static let subsystem = "com.crux.app"

    /// EPUB parsing, ZIP extraction, content normalization
    static let parser = Logger(subsystem: subsystem, category: "parser")

    /// AI provider requests, response parsing, retries
    static let ai = Logger(subsystem: subsystem, category: "ai")

    /// Book/annotation storage, file system operations
    static let storage = Logger(subsystem: subsystem, category: "storage")

    /// Keychain reads/writes, security operations
    static let security = Logger(subsystem: subsystem, category: "security")

    /// User-facing error reporting (paired with ErrorHandler toasts/alerts)
    static let errors = Logger(subsystem: subsystem, category: "errors")

    /// SwiftData, schema migrations, model contexts
    static let data = Logger(subsystem: subsystem, category: "data")

    /// Reader view, WebView bridge, CFI tracking
    static let reader = Logger(subsystem: subsystem, category: "reader")

    /// UI lifecycle, navigation, sheets
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
