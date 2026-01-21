import SwiftUI
import MarkdownUI

@MainActor
@Observable
final class ThreadPanelState {
    var isLoading = false
    var currentHighlight: Highlight?
    var currentThread: Thread?
    var error: Error?

    private var providerManager: AIProviderManager?
    private let storage = BookStorage.shared

    var isConfigured: Bool {
        providerManager?.hasActiveProvider ?? false
    }

    func setProviderManager(_ manager: AIProviderManager) {
        self.providerManager = manager
    }

    func startThread(
        for highlight: Highlight,
        book: Book,
        chapter: Chapter?,
        bookId: UUID
    ) async -> Thread? {
        isLoading = true
        error = nil

        // Create a new thread
        var thread = Thread()

        // Add initial assistant message (the explication)
        guard let manager = providerManager else {
            self.error = NSError(domain: "ThreadPanel", code: 1, userInfo: [NSLocalizedDescriptionKey: "No AI provider configured"])
            isLoading = false
            return nil
        }

        // Build context for AI provider
        let contextText = """
        From "\(book.title)" by \(book.author ?? "Unknown Author")
        Chapter: \(chapter?.title ?? "Unknown Chapter")

        \(highlight.surroundingContext)
        """

        do {
            let response = try await manager.generateResponse(
                for: highlight.selectedText,
                context: contextText,
                conversationHistory: []
            )

            thread.addMessage(ThreadMessage(role: .assistant, content: response))
            currentThread = thread
            isLoading = false
            return thread
        } catch {
            self.error = error
            isLoading = false
            return nil
        }
    }

    func continueThread(
        message: String,
        highlight: Highlight,
        book: Book,
        existingThread: Thread? = nil
    ) async -> Thread? {
        // Use provided thread, fall back to currentThread, or get from highlight
        guard var thread = existingThread ?? currentThread ?? highlight.threads.first else { return nil }

        guard let manager = providerManager else {
            self.error = NSError(domain: "ThreadPanel", code: 1, userInfo: [NSLocalizedDescriptionKey: "No AI provider configured"])
            return nil
        }

        isLoading = true
        error = nil

        // Add user message
        thread.addMessage(ThreadMessage(role: .user, content: message))

        // Build conversation context
        let contextText = """
        Continuing discussion about "\(book.title)" by \(book.author ?? "Unknown Author")
        Selected passage: "\(highlight.selectedText)"
        """

        do {
            // Pass conversation history (excluding the just-added user message temporarily)
            let history = Array(thread.messages.dropLast())

            let response = try await manager.generateResponse(
                for: message,
                context: contextText,
                conversationHistory: history
            )

            thread.addMessage(ThreadMessage(role: .assistant, content: response))
            currentThread = thread
            isLoading = false
            return thread
        } catch {
            self.error = error
            isLoading = false
            return nil
        }
    }
}

struct ThreadPanel: View {
    let pendingSelection: SelectionData?
    let book: Book
    let chapter: Chapter?
    @Bindable var state: ThreadPanelState
    @Binding var annotations: BookAnnotations
    let onDismiss: () -> Void

    @Environment(AIProviderManager.self) private var providerManager
    @State private var followUpText = ""

    private var headerIconView: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.purple.opacity(0.3), Color.blue.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 32, height: 32)

            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 14))
                .foregroundStyle(.purple)
        }
    }

    private var closeButton: some View {
        Button {
            onDismiss()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .buttonBorderShape(.circle)
    }

    private var headerGradient: some View {
        LinearGradient(
            colors: [Color(.controlBackgroundColor), Color(.controlBackgroundColor).opacity(0.8)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var headerView: some View {
        HStack {
            HStack(spacing: 8) {
                headerIconView
                Text("AI Thread")
                    .font(.headline)
            }

            Spacer()

            closeButton
        }
        .padding()
        .background(headerGradient)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            Divider()

            ThreadContentView(
                pendingSelection: pendingSelection,
                book: book,
                chapter: chapter,
                state: state,
                annotations: $annotations,
                followUpText: $followUpText,
                providerManager: providerManager,
                onStartThread: { selection in
                    Task {
                        await startNewThread(for: selection)
                    }
                },
                onSendFollowUp: sendFollowUp
            )
        }
        .background(.background)
        .onAppear {
            state.setProviderManager(providerManager)
        }
    }

    private func startNewThread(for selection: SelectionData) async {
        // Create or find highlight
        var highlight: Highlight
        if let existing = annotations.highlights.first(where: { $0.selectedText == selection.text && $0.cfiRange == selection.cfiRange }) {
            highlight = existing
        } else {
            highlight = Highlight(
                chapterId: chapter?.id ?? "",
                selectedText: selection.text,
                surroundingContext: selection.context,
                cfiRange: selection.cfiRange
            )
            annotations.addHighlight(highlight)
        }

        state.currentHighlight = highlight

        if let thread = await state.startThread(for: highlight, book: book, chapter: chapter, bookId: annotations.bookId) {
            // Save thread to annotations
            annotations.addThread(to: highlight.id, thread: thread)
            await saveAnnotations()
        }
    }

    private func sendFollowUp() {
        guard !followUpText.isEmpty, let highlight = state.currentHighlight else { return }
        let message = followUpText
        followUpText = ""
        Task {
            if let thread = await state.continueThread(message: message, highlight: highlight, book: book) {
                // Update thread in annotations
                if let highlightIndex = annotations.highlights.firstIndex(where: { $0.id == highlight.id }),
                   let threadIndex = annotations.highlights[highlightIndex].threads.firstIndex(where: { $0.id == thread.id }) {
                    annotations.highlights[highlightIndex].threads[threadIndex] = thread
                    await saveAnnotations()
                }
            }
        }
    }

    private func saveAnnotations() async {
        do {
            try await BookStorage.shared.saveAnnotations(annotations)
        } catch {
            state.error = error
        }
    }

    private func extractSurroundingText(for selectedText: String) -> String {
        guard let content = chapter?.content else { return "" }
        let stripped = content.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)

        if let range = stripped.range(of: selectedText) {
            let contextLength = 500
            let start = stripped.index(range.lowerBound, offsetBy: -contextLength, limitedBy: stripped.startIndex) ?? stripped.startIndex
            let end = stripped.index(range.upperBound, offsetBy: contextLength, limitedBy: stripped.endIndex) ?? stripped.endIndex
            return String(stripped[start..<end])
        }

        return String(stripped.prefix(1000))
    }
}

// MARK: - Thread Content View

struct ThreadContentView: View {
    let pendingSelection: SelectionData?
    let book: Book
    let chapter: Chapter?
    @Bindable var state: ThreadPanelState
    @Binding var annotations: BookAnnotations
    @Binding var followUpText: String
    let providerManager: AIProviderManager
    let onStartThread: (SelectionData) -> Void
    let onSendFollowUp: () -> Void

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let selection = pendingSelection {
                        // Selected text
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "quote.opening")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)

                                Text("Selected Passage")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 0) {
                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.blue, Color.purple],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(width: 4)

                                Text(selection.text)
                                    .font(.body)
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.blue.opacity(0.05))
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                            )
                        }

                        // Start thread button or loading state
                        if state.isLoading && state.currentThread == nil {
                            AILoadingView(providerName: providerManager.activeProviderName ?? "AI")
                        } else if state.currentThread == nil {
                            if state.isConfigured {
                                Button {
                                    onStartThread(selection)
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 14))

                                        Text("Start Thread")
                                            .fontWeight(.medium)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(
                                        LinearGradient(
                                            colors: [Color.blue, Color.purple],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
                                }
                                .buttonStyle(.plain)
                            } else {
                                VStack(spacing: 12) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundStyle(.orange)

                                        Text("No AI provider configured")
                                            .font(.caption)
                                            .foregroundStyle(.primary)
                                    }

                                    #if os(macOS)
                                    Button {
                                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "gearshape.fill")
                                                .font(.caption)

                                            Text("Open Settings")
                                                .font(.caption)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.orange.opacity(0.15))
                                        .foregroundStyle(.orange)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                    .buttonStyle(.plain)
                                    #else
                                    Text("Configure an AI provider in Settings")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    #endif
                                }
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.orange.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                                )
                            }
                        }
                    }

                    // Thread messages
                    if let thread = state.currentThread {
                        ForEach(thread.messages) { message in
                            ThreadMessageView(message: message)
                        }

                        // Follow-up input
                        if !state.isLoading {
                            HStack(spacing: 8) {
                                HStack {
                                    Image(systemName: "bubble.left")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    TextField("Ask a follow-up...", text: $followUpText)
                                        .textFieldStyle(.plain)
                                        .onSubmit {
                                            onSendFollowUp()
                                        }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color(.textBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                )

                                Button {
                                    onSendFollowUp()
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(
                                                LinearGradient(
                                                    colors: followUpText.isEmpty
                                                        ? [Color.secondary.opacity(0.1), Color.secondary.opacity(0.1)]
                                                        : [Color.blue, Color.purple],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .frame(width: 36, height: 36)

                                        Image(systemName: "arrow.up")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(followUpText.isEmpty ? Color.secondary : Color.white)
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(followUpText.isEmpty)
                            }
                        } else {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .scaleEffect(0.8)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Thinking...")
                                        .font(.caption)
                                        .foregroundStyle(.primary)

                                    Text(providerManager.activeProviderName ?? "AI")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.purple.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    // Error display
                    if let error = state.error {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(Color.red.opacity(0.15))
                                        .frame(width: 28, height: 28)

                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.red)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Error")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.red)

                                    Text(error.localizedDescription)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if error.localizedDescription.contains("provider") || error.localizedDescription.contains("configured") {
                                #if os(macOS)
                                Button {
                                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "gearshape.fill")
                                            .font(.caption)

                                        Text("Open Settings")
                                            .font(.caption)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.red.opacity(0.15))
                                    .foregroundStyle(.red)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                                #else
                                Text("Configure an AI provider in Settings")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                #endif
                            }
                        }
                        .padding()
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.red.opacity(0.2), lineWidth: 1)
                        )
                    }

                    // Empty state when no selection and no thread
                    let chapterHighlights = annotations.highlights.filter { $0.chapterId == chapter?.id }
                    if pendingSelection == nil && state.currentThread == nil && chapterHighlights.isEmpty {
                        ThreadEmptyStateView()
                    }

                    // Existing highlights for this chapter
                    if !chapterHighlights.isEmpty && pendingSelection == nil {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 6) {
                                Image(systemName: "highlighter")
                                    .font(.caption)
                                    .foregroundStyle(.blue)

                                Text("Highlights in this chapter")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)

                                Spacer()

                                Text("\(chapterHighlights.count)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                            .padding(.horizontal, 8)

                            ForEach(chapterHighlights) { highlight in
                                HighlightRow(highlight: highlight)
                            }
                        }
                        .padding(.top, 8)
                    }
                }
                .padding()
            }
        }
}

// MARK: - Thread Message View

struct ThreadMessageView: View {
    let message: ThreadMessage
    @Environment(AIProviderManager.self) private var providerManager

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .assistant {
                // AI Avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.2), Color.blue.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 28, height: 28)

                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.purple, Color.blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                HStack(spacing: 4) {
                    if message.role == .assistant {
                        Text(providerManager.activeProviderName ?? "AI")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.purple)
                    } else {
                        Text("You")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.blue)
                    }

                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(message.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Markdown(message.content)
                    .textSelection(.enabled)
                    .padding(12)
                    .background(
                        message.role == .user
                            ? LinearGradient(
                                colors: [Color.blue.opacity(0.15), Color.blue.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [Color.secondary.opacity(0.08), Color.secondary.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                message.role == .user ? Color.blue.opacity(0.2) : Color.secondary.opacity(0.1),
                                lineWidth: 1
                            )
                    )
            }
            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .user {
                // User Avatar
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 28, height: 28)

                    Image(systemName: "person.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.blue)
                }
            }
        }
    }
}

struct HighlightRow: View {
    let highlight: Highlight
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.purple.opacity(0.6), Color.blue.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 6) {
                Text(highlight.selectedText)
                    .font(.caption)
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    if !highlight.threads.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.purple)

                            Text("\(highlight.threads.count)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.1))
                        .clipShape(Capsule())
                    }

                    if let annotation = highlight.annotation, !annotation.isEmpty {
                        Image(systemName: "note.text")
                            .font(.system(size: 9))
                            .foregroundStyle(.green)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            isHovered
                ? Color.secondary.opacity(0.08)
                : Color.secondary.opacity(0.05)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: isHovered ? .black.opacity(0.05) : .clear, radius: 4, x: 0, y: 2)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - AI Loading View

struct AILoadingView: View {
    let providerName: String
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 16) {
            // Animated sparkles icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.15), Color.blue.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)

                Image(systemName: "sparkles")
                    .font(.system(size: 24))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.purple, Color.blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .rotationEffect(.degrees(isAnimating ? 360 : 0))
                    .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: isAnimating)
            }

            VStack(spacing: 6) {
                Text("Analyzing passage...")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)

                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                        .font(.system(size: 11))
                    Text(providerName)
                        .font(.system(size: 12))
                }
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.purple.opacity(0.08), Color.blue.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    LinearGradient(
                        colors: [Color.purple.opacity(0.2), Color.blue.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Thread Empty State View

struct ThreadEmptyStateView: View {
    var body: some View {
        VStack(spacing: 24) {
            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.1), Color.blue.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)

                Image(systemName: "text.bubble")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.purple, Color.blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 8) {
                Text("No Active Thread")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("Select text to start an AI conversation")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Tips
            VStack(alignment: .leading, spacing: 12) {
                EmptyStateTip(
                    icon: "hand.tap",
                    text: "Highlight any passage in the text"
                )

                EmptyStateTip(
                    icon: "sparkles",
                    text: "AI will provide contextual insights"
                )

                EmptyStateTip(
                    icon: "bubble.left.and.bubble.right",
                    text: "Continue the conversation with follow-ups"
                )
            }
            .padding(16)
            .background(Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

struct EmptyStateTip: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.blue)
                .frame(width: 20)

            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

