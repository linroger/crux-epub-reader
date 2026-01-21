import Foundation
import SwiftUI

/// Centralized error handling service for the app
@MainActor
@Observable
final class ErrorHandler {
    /// Singleton instance
    static let shared = ErrorHandler()

    /// Current error being displayed
    var currentError: AppError?

    /// Whether an error alert is shown
    var showingErrorAlert = false

    /// Toast message for non-critical feedback
    var toastMessage: ToastMessage?

    /// Whether a toast is shown
    var showingToast = false

    private init() {}

    /// Handle an error with appropriate UI feedback
    func handle(_ error: Error, context: String? = nil) {
        let appError: AppError

        if let existing = error as? AppError {
            appError = existing
        } else {
            appError = AppError(
                title: "An Error Occurred",
                message: error.localizedDescription,
                context: context,
                underlyingError: error
            )
        }

        // Log the error
        logError(appError)

        // Show UI feedback based on severity
        if appError.severity == .critical {
            showError(appError)
        } else {
            showToast(appError.toToastMessage())
        }
    }

    /// Show an error alert dialog
    func showError(_ error: AppError) {
        currentError = error
        showingErrorAlert = true
    }

    /// Show a toast notification
    func showToast(_ message: ToastMessage) {
        toastMessage = message
        showingToast = true

        // Auto-dismiss after duration
        Task {
            try? await Task.sleep(for: .seconds(message.duration))
            if toastMessage?.id == message.id {
                showingToast = false
                toastMessage = nil
            }
        }
    }

    /// Show a success toast
    func showSuccess(_ message: String) {
        showToast(ToastMessage(message: message, type: .success))
    }

    /// Show an info toast
    func showInfo(_ message: String) {
        showToast(ToastMessage(message: message, type: .info))
    }

    /// Show a warning toast
    func showWarning(_ message: String) {
        showToast(ToastMessage(message: message, type: .warning))
    }

    /// Dismiss the current error
    func dismissError() {
        showingErrorAlert = false
        currentError = nil
    }

    /// Dismiss the current toast
    func dismissToast() {
        showingToast = false
        toastMessage = nil
    }

    private func logError(_ error: AppError) {
        var logMessage = "[\(error.severity.rawValue.uppercased())] \(error.title)"

        if let context = error.context {
            logMessage += " - Context: \(context)"
        }

        logMessage += " - \(error.message)"

        if let underlying = error.underlyingError {
            logMessage += " - Underlying: \(underlying.localizedDescription)"
        }

        print(logMessage)
    }
}

// MARK: - App Error

struct AppError: Error, Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let context: String?
    let underlyingError: Error?
    let severity: Severity
    let recoverySuggestion: String?

    init(
        title: String,
        message: String,
        context: String? = nil,
        underlyingError: Error? = nil,
        severity: Severity = .error,
        recoverySuggestion: String? = nil
    ) {
        self.title = title
        self.message = message
        self.context = context
        self.underlyingError = underlyingError
        self.severity = severity
        self.recoverySuggestion = recoverySuggestion
    }

    enum Severity: String {
        case info
        case warning
        case error
        case critical
    }

    func toToastMessage() -> ToastMessage {
        let type: ToastMessage.MessageType
        switch severity {
        case .info: type = .info
        case .warning: type = .warning
        case .error, .critical: type = .error
        }

        return ToastMessage(
            message: "\(title): \(message)",
            type: type
        )
    }
}

// MARK: - Common App Errors

extension AppError {
    // EPUB Parsing Errors
    static func epubParsingFailed(_ reason: String) -> AppError {
        AppError(
            title: "Failed to Open Book",
            message: "Could not parse the EPUB file: \(reason)",
            severity: .error,
            recoverySuggestion: "Make sure the file is a valid EPUB and try again."
        )
    }

    static func epubNotFound() -> AppError {
        AppError(
            title: "Book Not Found",
            message: "The EPUB file could not be found on disk.",
            severity: .error,
            recoverySuggestion: "The file may have been moved or deleted. Try re-importing the book."
        )
    }

    // File Operation Errors
    static func fileOperationFailed(_ operation: String, reason: String) -> AppError {
        AppError(
            title: "File Operation Failed",
            message: "\(operation) failed: \(reason)",
            severity: .error,
            recoverySuggestion: "Check disk space and permissions, then try again."
        )
    }

    static func exportFailed(_ reason: String) -> AppError {
        AppError(
            title: "Export Failed",
            message: "Could not export the file: \(reason)",
            severity: .error,
            recoverySuggestion: "Check that you have write permission to the destination."
        )
    }

    // AI Service Errors
    static func aiRequestFailed(_ reason: String) -> AppError {
        AppError(
            title: "AI Request Failed",
            message: reason,
            severity: .error,
            recoverySuggestion: "Check your API key and network connection, then try again."
        )
    }

    static func aiApiKeyMissing() -> AppError {
        AppError(
            title: "AI API Key Missing",
            message: "No API key configured for the selected AI provider.",
            severity: .warning,
            recoverySuggestion: "Configure your API key in Settings to use AI features."
        )
    }

    // Data Persistence Errors
    static func dataLoadFailed(_ dataType: String) -> AppError {
        AppError(
            title: "Failed to Load Data",
            message: "Could not load \(dataType) from the database.",
            severity: .critical,
            recoverySuggestion: "The app may need to be restarted."
        )
    }

    static func dataSaveFailed(_ dataType: String) -> AppError {
        AppError(
            title: "Failed to Save Data",
            message: "Could not save \(dataType) to the database.",
            severity: .error,
            recoverySuggestion: "Changes may be lost. Try again or restart the app."
        )
    }

    // Backup/Restore Errors
    static func backupFailed(_ reason: String) -> AppError {
        AppError(
            title: "Backup Failed",
            message: reason,
            severity: .error,
            recoverySuggestion: "Check available disk space and try again."
        )
    }

    static func restoreFailed(_ reason: String) -> AppError {
        AppError(
            title: "Restore Failed",
            message: reason,
            severity: .error,
            recoverySuggestion: "Make sure the backup file is valid and try again."
        )
    }

    // Network Errors
    static func networkUnavailable() -> AppError {
        AppError(
            title: "No Network Connection",
            message: "Some features require an internet connection.",
            severity: .warning,
            recoverySuggestion: "Connect to the internet and try again."
        )
    }
}

// MARK: - Toast Message

struct ToastMessage: Identifiable {
    let id = UUID()
    let message: String
    let type: MessageType
    let duration: Double

    init(message: String, type: MessageType, duration: Double = 3.0) {
        self.message = message
        self.type = type
        self.duration = duration
    }

    enum MessageType {
        case success
        case info
        case warning
        case error

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .info: return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .success: return .green
            case .info: return .blue
            case .warning: return .orange
            case .error: return .red
            }
        }
    }
}

// MARK: - Error Alert View Modifier

struct ErrorAlertModifier: ViewModifier {
    @State private var errorHandler = ErrorHandler.shared

    func body(content: Content) -> some View {
        content
            .alert(
                errorHandler.currentError?.title ?? "Error",
                isPresented: $errorHandler.showingErrorAlert,
                presenting: errorHandler.currentError
            ) { error in
                Button("OK") {
                    errorHandler.dismissError()
                }

                if let suggestion = error.recoverySuggestion {
                    Button("Learn More") {
                        // Could open help or documentation
                        errorHandler.dismissError()
                    }
                }
            } message: { error in
                VStack(alignment: .leading, spacing: 8) {
                    Text(error.message)

                    if let suggestion = error.recoverySuggestion {
                        Text(suggestion)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
    }
}

// MARK: - Toast View Modifier

struct ToastModifier: ViewModifier {
    @State private var errorHandler = ErrorHandler.shared

    func body(content: Content) -> some View {
        ZStack {
            content

            if errorHandler.showingToast, let toast = errorHandler.toastMessage {
                VStack {
                    Spacer()

                    HStack(spacing: 12) {
                        Image(systemName: toast.type.icon)
                            .font(.title3)
                            .foregroundStyle(toast.type.color)

                        Text(toast.message)
                            .font(.subheadline)
                            .foregroundStyle(.primary)

                        Spacer()

                        Button {
                            errorHandler.dismissToast()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 8)
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.spring(), value: errorHandler.showingToast)
            }
        }
    }
}

// MARK: - View Extensions

extension View {
    /// Add error alert handling to a view
    func withErrorHandling() -> some View {
        modifier(ErrorAlertModifier())
    }

    /// Add toast notifications to a view
    func withToasts() -> some View {
        modifier(ToastModifier())
    }

    /// Add both error handling and toasts
    func withFeedback() -> some View {
        self
            .withErrorHandling()
            .withToasts()
    }
}
