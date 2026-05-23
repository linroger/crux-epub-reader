import SwiftUI
import MarkdownUI

@MainActor
@Observable
final class ThreadPanelState {
    var isLoading = false
    var currentHighlight: Highlight?
    var currentThread: Thread?
    var error: Error?

    /// Cached "active prompt" derived from the user's settings. Read on
    /// each request so changes from Settings → AI Prompt take effect for
    /// the next thread without a relaunch.
    var resolvedSystemPrompt: String?

    /// Live token buffer for streaming responses. Surfaced to the UI so
    /// the reader sees tokens appear in real time. Cleared whenever a
    /// new thread/turn starts or a stream completes.
    var streamingText: String = ""

    /// Captures the most recent failed AI action so the UI can offer a
    /// one-tap retry. Reset whenever the user moves to a new highlight or
    /// successfully completes a request.
    enum LastAction: Equatable {
        case startThread(highlightId: UUID, contextText: String, selection: String)
        case continueThread(highlightId: UUID, message: String)
        case chapterAnalysis(promptLabel: String, prompt: String, chapterContext: String)
    }
    var lastAction: LastAction?

    /// Active wrapper task for the in-flight streaming request. Held so
    /// the UI can offer a Stop affordance — cancelling it propagates
    /// through the async stream and the underlying URLSessionTask.
    var activeTask: Task<Void, Never>?

    private var providerManager: AIProviderManager?
    private let storage = BookStorage.shared

    var isConfigured: Bool {
        providerManager?.hasActiveProvider ?? false
    }

    /// Diagnostic label combining the provider name and configured model.
    /// Drives the small "model badge" in the loading/empty states.
    var activeModelLabel: String? {
        guard let providerManager else { return nil }
        guard let active = providerManager.providers.first(where: { $0.isActive }) else {
            return providerManager.activeProviderName
        }
        if let model = active.model, !model.isEmpty {
            return "\(active.name) · \(model)"
        }
        return active.name
    }

    func setProviderManager(_ manager: AIProviderManager) {
        self.providerManager = manager
    }

    /// True when the most recent error came from a transient class
    /// (network, timeout, 5xx). The retry button uses this to decide
    /// whether re-issuing the request is likely to help.
    var canRetry: Bool {
        guard let error else { return false }
        if let providerError = error as? AIProviderError {
            return RetryPolicy.isTransient(providerError)
        }
        return RetryPolicy.isTransient(error)
    }

    func startThread(
        for highlight: Highlight,
        book: Book,
        chapter: Chapter?,
        bookId: UUID,
        customPrompt: String? = nil
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
        var contextText = """
        From "\(book.title)" by \(book.author ?? "Unknown Author")
        Chapter: \(chapter?.title ?? "Unknown Chapter")

        \(highlight.surroundingContext)
        """
        
        // If a custom prompt is provided, prepend it to guide the AI
        if let customPrompt = customPrompt, !customPrompt.isEmpty {
            contextText = """
            User's Custom Instruction: \(customPrompt)
            
            \(contextText)
            """
        }

        // Capture context for potential retry before issuing the call.
        lastAction = .startThread(
            highlightId: highlight.id,
            contextText: contextText,
            selection: highlight.selectedText
        )

        let options = AIRequestOptions(systemPrompt: resolvedSystemPrompt)
        streamingText = ""

        do {
            // Prefer streaming when the provider supports it — gives the
            // reader incremental feedback instead of a 15-60s wait for
            // local models. We accumulate tokens into `streamingText` and
            // commit a single assistant message at the end.
            let stream = try await manager.streamResponse(
                for: highlight.selectedText,
                context: contextText,
                conversationHistory: [],
                options: options
            )

            var accumulated = ""
            for try await chunk in stream {
                accumulated = applyChunk(chunk, to: accumulated)
                streamingText = accumulated
            }

            thread.addMessage(ThreadMessage(role: .assistant, content: accumulated))
            currentThread = thread
            streamingText = ""
            isLoading = false
            lastAction = nil  // success — clear retry state
            activeTask = nil
            return thread
        } catch is CancellationError {
            streamingText = ""
            isLoading = false
            activeTask = nil
            return nil
        } catch {
            streamingText = ""
            self.error = error
            isLoading = false
            activeTask = nil
            return nil
        }
    }

    /// Merge a streamed chunk into the running accumulator.
    ///
    /// Providers don't agree on chunk semantics:
    ///   * Apple Intelligence's `streamResponse` and the protocol's
    ///     fallback yield *cumulative* partials (each chunk is the full
    ///     text so far).
    ///   * OpenAI / Anthropic / Ollama / LM Studio yield deltas (each
    ///     chunk is the next slice of new tokens).
    /// We detect cumulative-style streams by prefix-match and replace;
    /// otherwise we append.
    private func applyChunk(_ chunk: String, to accumulated: String) -> String {
        if !accumulated.isEmpty && chunk.hasPrefix(accumulated) {
            return chunk           // cumulative
        }
        if chunk.isEmpty {
            return accumulated
        }
        return accumulated + chunk // delta
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
        lastAction = .continueThread(highlightId: highlight.id, message: message)
        streamingText = ""

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
            let options = AIRequestOptions(systemPrompt: resolvedSystemPrompt)

            let stream = try await manager.streamResponse(
                for: message,
                context: contextText,
                conversationHistory: history,
                options: options
            )

            var accumulated = ""
            for try await chunk in stream {
                accumulated = applyChunk(chunk, to: accumulated)
                streamingText = accumulated
            }

            thread.addMessage(ThreadMessage(role: .assistant, content: accumulated))
            currentThread = thread
            streamingText = ""
            isLoading = false
            lastAction = nil
            activeTask = nil
            return thread
        } catch is CancellationError {
            // Roll back the optimistic user message so the next attempt
            // doesn't double it up; keep the partial assistant text
            // discarded since cancellation is a deliberate user action.
            if thread.messages.last?.role == .user {
                thread.messages.removeLast()
            }
            streamingText = ""
            isLoading = false
            activeTask = nil
            return nil
        } catch {
            if thread.messages.last?.role == .user {
                thread.messages.removeLast()
            }
            streamingText = ""
            self.error = error
            isLoading = false
            activeTask = nil
            return nil
        }
    }

    /// Re-issue whatever request just failed, when the failure is transient.
    func retryLastAction(book: Book, chapter: Chapter?) async {
        guard let lastAction, let manager = providerManager else { return }
        error = nil
        streamingText = ""
        switch lastAction {
        case .startThread(_, let contextText, let selection):
            isLoading = true
            do {
                let options = AIRequestOptions(systemPrompt: resolvedSystemPrompt)
                let stream = try await manager.streamResponse(
                    for: selection,
                    context: contextText,
                    conversationHistory: [],
                    options: options
                )
                var accumulated = ""
                for try await chunk in stream {
                    accumulated = applyChunk(chunk, to: accumulated)
                    streamingText = accumulated
                }
                var thread = currentThread ?? Thread()
                thread.addMessage(ThreadMessage(role: .assistant, content: accumulated))
                currentThread = thread
                self.lastAction = nil
            } catch is CancellationError {
                // Silent — user requested stop.
            } catch {
                self.error = error
            }
            streamingText = ""
            isLoading = false
            activeTask = nil

        case .continueThread(let highlightId, let message):
            guard let highlight = currentHighlight, highlight.id == highlightId else { return }
            _ = await continueThread(message: message, highlight: highlight, book: book)

        case .chapterAnalysis(let label, let prompt, let chapterContext):
            await runChapterAnalysis(label: label, prompt: prompt, chapterContext: chapterContext)
        }
    }

    // MARK: - Cancellation

    /// Cancel the in-flight AI request, if any. Used by the Stop button
    /// inside `AILoadingView`. Cancellation propagates through the
    /// `URLSession.bytes(for:)` stream to the underlying network task.
    func cancelCurrentRequest() {
        activeTask?.cancel()
        activeTask = nil
        isLoading = false
        streamingText = ""
    }

    /// Wrap caller-supplied async work in a tracked task so the user
    /// can cancel it from the UI. The caller is still responsible for
    /// awaiting and persisting any returned value inside the block.
    func runTracked(_ block: @escaping @MainActor () async -> Void) {
        cancelCurrentRequest()
        activeTask = Task { @MainActor in
            await block()
        }
    }

    // MARK: - Regenerate

    /// Pop the last assistant reply and re-issue the request that
    /// produced it. Works on both the first explication (no prior user
    /// turn yet) and on follow-ups (re-uses the last user message).
    func regenerateLastResponse(book: Book, chapter: Chapter?) async {
        guard var thread = currentThread else { return }
        guard let lastAssistantIdx = thread.messages.lastIndex(where: { $0.role == .assistant }) else { return }

        // Drop the assistant reply we're about to replace.
        thread.messages.remove(at: lastAssistantIdx)
        currentThread = thread

        if let priorUserIdx = thread.messages.lastIndex(where: { $0.role == .user }) {
            // Re-issue follow-up using the prior user prompt.
            let userMessage = thread.messages[priorUserIdx].content
            // Drop the user message too; continueThread re-adds it
            // optimistically, otherwise we'd duplicate.
            thread.messages.remove(at: priorUserIdx)
            currentThread = thread
            guard let highlight = currentHighlight else { return }
            _ = await continueThread(
                message: userMessage,
                highlight: highlight,
                book: book,
                existingThread: thread
            )
        } else if let highlight = currentHighlight, let chapter {
            // First reply: re-issue the initial explication.
            _ = await startThread(
                for: highlight,
                book: book,
                chapter: chapter,
                bookId: highlight.id
            )
        } else if case let .chapterAnalysis(label, prompt, chapterContext) = lastAction {
            // Chapter-scope analysis with no underlying highlight.
            await runChapterAnalysis(label: label, prompt: prompt, chapterContext: chapterContext)
        }
    }

    // MARK: - Chapter-Scope Analysis

    /// Ephemeral analysis at chapter scope. Runs `prompt` against the
    /// chapter text. Result is shown in the panel but not persisted into
    /// the book's annotations (no underlying highlight exists). Users
    /// can copy the output or start a new highlight to anchor follow-up
    /// threads.
    func startChapterAnalysis(label: String, prompt: String, chapter: Chapter, book: Book) async {
        let chapterContext = """
        From "\(book.title)" by \(book.author ?? "Unknown Author")
        Chapter: \(chapter.title)

        \(chapterPlainText(chapter))
        """

        // Reset thread state for ephemeral chapter analysis.
        currentHighlight = nil
        currentThread = Thread(messages: [ThreadMessage(role: .user, content: label)])

        await runChapterAnalysis(label: label, prompt: prompt, chapterContext: chapterContext)
    }

    private func runChapterAnalysis(label: String, prompt: String, chapterContext: String) async {
        guard let manager = providerManager else {
            self.error = NSError(domain: "ThreadPanel", code: 1, userInfo: [NSLocalizedDescriptionKey: "No AI provider configured"])
            return
        }
        isLoading = true
        error = nil
        streamingText = ""
        lastAction = .chapterAnalysis(promptLabel: label, prompt: prompt, chapterContext: chapterContext)

        let options = AIRequestOptions(systemPrompt: resolvedSystemPrompt)
        do {
            let stream = try await manager.streamResponse(
                for: prompt,
                context: chapterContext,
                conversationHistory: [],
                options: options
            )
            var accumulated = ""
            for try await chunk in stream {
                accumulated = applyChunk(chunk, to: accumulated)
                streamingText = accumulated
            }
            var thread = currentThread ?? Thread()
            thread.addMessage(ThreadMessage(role: .assistant, content: accumulated))
            currentThread = thread
            lastAction = nil
        } catch is CancellationError {
            // Drop the optimistic user-side label so retry doesn't keep stacking copies.
            if let last = currentThread?.messages.last, last.role == .user {
                currentThread?.messages.removeLast()
            }
        } catch {
            if let last = currentThread?.messages.last, last.role == .user {
                currentThread?.messages.removeLast()
            }
            self.error = error
        }
        streamingText = ""
        isLoading = false
        activeTask = nil
    }

    private func chapterPlainText(_ chapter: Chapter) -> String {
        // Strip HTML to give the model clean prose; collapse whitespace.
        let withoutTags = chapter.content.replacingOccurrences(
            of: "<[^>]+>", with: " ", options: .regularExpression
        )
        let collapsed = withoutTags.replacingOccurrences(
            of: "\\s+", with: " ", options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        // Cap at a generous but safe ceiling — most providers handle 20k
        // chars without trouble; truncate beyond to avoid context blowups.
        let cap = 20_000
        if collapsed.count > cap {
            let prefix = collapsed.prefix(cap)
            return String(prefix) + "\n\n[... chapter truncated for length ...]"
        }
        return collapsed
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

    private var activeProviderIsOnDevice: Bool {
        guard let active = providerManager.providers.first(where: { $0.isActive }) else { return false }
        return active.providerType.isOnDevice
    }

    private var headerView: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                headerIconView
                VStack(alignment: .leading, spacing: 1) {
                    Text("AI Thread")
                        .font(.headline)
                    if let model = state.activeModelLabel {
                        Text(model)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            Spacer()

            // Offline indicator — only shown when the active provider is
            // cloud-backed; on-device providers (Apple Intelligence,
            // Ollama, LM Studio) keep working without network.
            if !NetworkMonitor.shared.isOnline && !activeProviderIsOnDevice {
                Label("Offline", systemImage: "wifi.exclamationmark")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .foregroundStyle(.orange)
                    .background(Color.orange.opacity(0.12), in: Capsule())
                    .help("No network — switch to Apple Intelligence / Ollama / LM Studio to keep working.")
                    .accessibilityLabel("Offline. The active AI provider needs network access.")
            }

            closeButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        // Use the system bar material so the header feels attached to the
        // window chrome on both macOS 14 (bar material) and macOS 26
        // (Liquid Glass).
        .cruxGlassBar()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView

            ThreadContentView(
                pendingSelection: pendingSelection,
                book: book,
                chapter: chapter,
                state: state,
                annotations: $annotations,
                followUpText: $followUpText,
                providerManager: providerManager,
                onStartThread: { selection in
                    startNewThread(for: selection)
                },
                onSendFollowUp: sendFollowUp,
                onRegenerate: {
                    Task { @MainActor in
                        await state.regenerateLastResponse(book: book, chapter: chapter)
                    }
                }
            )
        }
        // The thread panel sits in a sidebar slot, so we use the regular
        // material as its base — visible against the WebView behind, but
        // clearly belonging to chrome rather than content.
        .background(.regularMaterial)
        .onAppear {
            state.setProviderManager(providerManager)
        }
    }

    private func startNewThread(for selection: SelectionData) {
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

        state.runTracked {
            if let thread = await state.startThread(for: highlight, book: book, chapter: chapter, bookId: annotations.bookId) {
                annotations.addThread(to: highlight.id, thread: thread)
                await saveAnnotations()
            }
        }
    }

    private func sendFollowUp() {
        guard !followUpText.isEmpty, let highlight = state.currentHighlight else { return }
        let message = followUpText
        followUpText = ""
        state.runTracked {
            if let thread = await state.continueThread(message: message, highlight: highlight, book: book) {
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
    let onRegenerate: () -> Void

    /// Anchor the ScrollView pins to whenever new tokens arrive.
    private let bottomAnchorID = "thread-bottom"

    /// Flashes the "Saved" affordance on the chapter-insight save bar
    /// when the user persists a chapter analysis as a bookmark.
    @State private var didJustSaveInsight = false

    var body: some View {
        ScrollViewReader { proxy in
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
                            StreamingResponseView(
                                providerName: state.activeModelLabel ?? providerManager.activeProviderName ?? "AI",
                                streamingText: state.streamingText,
                                onStop: { state.cancelCurrentRequest() }
                            )
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
                        ForEach(Array(thread.messages.enumerated()), id: \.element.id) { index, message in
                            ThreadMessageView(
                                message: message,
                                isLastAssistantMessage: !state.isLoading
                                    && index == thread.messages.count - 1
                                    && message.role == .assistant,
                                onRegenerate: onRegenerate
                            )
                        }

                        // Follow-up input — native composer styling
                        if !state.isLoading {
                            HStack(spacing: 8) {
                                HStack(spacing: 8) {
                                    Image(systemName: "text.bubble")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)

                                    TextField("Ask a follow-up…", text: $followUpText, axis: .vertical)
                                        .textFieldStyle(.plain)
                                        .lineLimit(1...4)
                                        .onSubmit {
                                            onSendFollowUp()
                                        }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .cruxGlassCard(cornerRadius: 10)

                                Button {
                                    onSendFollowUp()
                                } label: {
                                    Image(systemName: "arrow.up")
                                        .font(.system(size: 13, weight: .semibold))
                                        .frame(width: 28, height: 28)
                                        .foregroundStyle(followUpText.trimmingCharacters(in: .whitespaces).isEmpty
                                                         ? Color.secondary
                                                         : Color.white)
                                        .background(
                                            Circle().fill(
                                                followUpText.trimmingCharacters(in: .whitespaces).isEmpty
                                                ? Color.secondary.opacity(0.2)
                                                : Color.accentColor
                                            )
                                        )
                                }
                                .buttonStyle(.plain)
                                .disabled(followUpText.trimmingCharacters(in: .whitespaces).isEmpty)
                                .keyboardShortcut(.return, modifiers: .command)
                                .help("Send (⌘ Return)")
                            }
                        } else {
                            StreamingResponseView(
                                providerName: state.activeModelLabel ?? providerManager.activeProviderName ?? "AI",
                                streamingText: state.streamingText,
                                onStop: { state.cancelCurrentRequest() }
                            )
                        }

                        // Chapter-scope save affordance. Chapter analyses
                        // run with `currentHighlight == nil` and stay
                        // ephemeral unless the user explicitly captures
                        // them, since they aren't tied to a passage.
                        if state.currentHighlight == nil,
                           let chapter,
                           !state.isLoading,
                           thread.messages.contains(where: { $0.role == .assistant }) {
                            ChapterInsightSaveBar(
                                book: book,
                                chapter: chapter,
                                thread: thread,
                                annotations: $annotations,
                                didJustSave: $didJustSaveInsight
                            )
                        }
                    }

                    // Error display
                    if let error = state.error {
                        ThreadErrorCard(
                            error: error,
                            canRetry: state.canRetry,
                            onRetry: {
                                Task { await state.retryLastAction(book: book, chapter: chapter) }
                            },
                            onOpenSettings: {
                                #if os(macOS)
                                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                                #endif
                            }
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

                    // Invisible spacer the scroll-to target uses to pin
                    // the live tokens at the bottom of the panel.
                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchorID)
                }
                .padding()
            }
            // Pin the panel to its newest content as tokens stream in or
            // when a fresh message commits. `proxy.scrollTo(...)` is
            // cheap and idempotent; we throttle implicitly because
            // `streamingText` only fires when chunks land.
            .onChange(of: state.streamingText) { _, _ in
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
            .onChange(of: state.currentThread?.messages.count ?? 0) { _, _ in
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                }
            }
            .onChange(of: state.isLoading) { _, loading in
                if loading {
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                    }
                }
            }
        }
    }
}

// MARK: - Thread Message View

struct ThreadMessageView: View {
    let message: ThreadMessage
    var isLastAssistantMessage: Bool = false
    var onRegenerate: () -> Void = {}
    @Environment(AIProviderManager.self) private var providerManager

    @State private var isHovered = false
    @State private var didJustCopy = false

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

                    // Copy-on-hover affordance for assistant messages so
                    // users can pull margin notes into their own systems.
                    if message.role == .assistant && (isHovered || didJustCopy) {
                        Button(action: copyContent) {
                            Label(didJustCopy ? "Copied" : "Copy",
                                  systemImage: didJustCopy ? "checkmark" : "doc.on.doc")
                                .labelStyle(.titleAndIcon)
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.mini)
                        .transition(.opacity)
                    }

                    // Native macOS share — sends the assistant content
                    // into the system Share menu (Notes, Messages, Mail,
                    // shortcuts the user has installed, etc.).
                    #if os(macOS)
                    if message.role == .assistant && isHovered {
                        ShareMenuButton(content: message.content)
                            .controlSize(.mini)
                            .transition(.opacity)
                    }
                    #endif

                    // Regenerate is only offered on the most recent
                    // assistant reply — replacing earlier messages would
                    // detach the conversational chain the model relied on.
                    if isLastAssistantMessage && isHovered {
                        Button(action: onRegenerate) {
                            Label("Regenerate", systemImage: "arrow.clockwise")
                                .labelStyle(.titleAndIcon)
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.mini)
                        .help("Regenerate this response with the current settings")
                        .transition(.opacity)
                    }
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
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private func copyContent() {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(message.content, forType: .string)
        #else
        UIPasteboard.general.string = message.content
        #endif

        withAnimation(.easeInOut(duration: 0.2)) { didJustCopy = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) { didJustCopy = false }
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

// MARK: - Streaming Response View

/// Shows live AI tokens as they arrive, with a Stop affordance to
/// cancel the in-flight request. Falls back to `AILoadingView` while
/// the model hasn't emitted anything yet (typical for the first 1-3s
/// of a cloud call or 10-30s of cold-start local inference).
struct StreamingResponseView: View {
    let providerName: String
    let streamingText: String
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if streamingText.isEmpty {
                AILoadingView(providerName: providerName)
            } else {
                liveTokensCard
            }

            HStack {
                Spacer()
                Button(role: .destructive, action: onStop) {
                    Label("Stop", systemImage: "stop.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .keyboardShortcut(".", modifiers: .command)
                .help("Stop generation (⌘.)")
                .accessibilityLabel("Stop generating AI response")
            }
        }
    }

    private var liveTokensCard: some View {
        HStack(alignment: .top, spacing: 10) {
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
                    .symbolEffect(.variableColor.iterative, options: .repeating)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text(providerName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.purple)
                        .lineLimit(1)
                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("streaming")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // Render the live tokens as plain text instead of full
                // Markdown — partial fences/asterisks would re-layout on
                // every tick and produce flicker. The final committed
                // message renders Markdown normally via ThreadMessageView.
                Text(streamingText)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        LinearGradient(
                            colors: [Color.secondary.opacity(0.08), Color.secondary.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                    )
            }
        }
    }
}

// MARK: - AI Loading View

/// Calmer "AI is thinking" indicator.
///
/// Replaces the previous spinning-sparkle effect with three breathing dots
/// plus a small badge that surfaces the active model. The dots use a
/// staggered scale animation that's easier on the eye for long inferences
/// (Ollama / local models can take 15-60s the first run).
struct AILoadingView: View {
    let providerName: String

    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            // Three-dot breathing indicator. Respects Reduce Motion by
            // showing a static cluster instead of an animated pulse.
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.accentColor, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 8, height: 8)
                        .scaleEffect(reduceMotion ? 1 : scale(for: index))
                        .opacity(reduceMotion ? 0.7 : opacity(for: index))
                }
            }
            .frame(width: 50)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Thinking…")
                    .font(.system(size: 14, weight: .medium))
                Text(providerName)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.accentColor.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
        )
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("AI is thinking with \(providerName)")
    }

    private func scale(for index: Int) -> CGFloat {
        let stagger = CGFloat(index) * 0.2
        let raw = sin((phase * .pi * 2) + stagger * .pi)
        return 0.7 + max(0, raw) * 0.4
    }

    private func opacity(for index: Int) -> Double {
        let stagger = Double(index) * 0.2
        let raw = sin((Double(phase) * .pi * 2) + stagger * .pi)
        return 0.4 + max(0, raw) * 0.6
    }
}

// MARK: - Error Card

/// Distinct error treatment that distinguishes between
/// (a) "AI provider missing/misconfigured" → suggests opening Settings,
/// (b) transient network/server errors → offers Retry,
/// (c) anything else → shows the message with a copy affordance.
struct ThreadErrorCard: View {
    let error: Error
    let canRetry: Bool
    let onRetry: () -> Void
    let onOpenSettings: () -> Void

    private var isConfigurationError: Bool {
        if let providerError = error as? AIProviderError {
            switch providerError {
            case .invalidConfiguration, .missingAPIKey, .invalidBaseURL:
                return true
            default:
                return false
            }
        }
        let lower = error.localizedDescription.lowercased()
        return lower.contains("provider") && lower.contains("config")
    }

    private var recoverySuggestion: String? {
        (error as? AIProviderError)?.recoverySuggestion
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: isConfigurationError ? "gearshape.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.red)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(isConfigurationError ? "AI provider not configured" : "Couldn't get a response")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(error.localizedDescription)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
            }

            if let suggestion = recoverySuggestion, !isConfigurationError {
                Text(suggestion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 42)
            }

            HStack(spacing: 8) {
                if isConfigurationError {
                    #if os(macOS)
                    Button(action: onOpenSettings) {
                        Label("Open Settings", systemImage: "gearshape.fill")
                    }
                    .controlSize(.small)
                    #endif
                }

                if canRetry {
                    Button(action: onRetry) {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)
                }
                Spacer()
            }
            .padding(.leading, 42)
        }
        .padding(14)
        .background(Color.red.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.red.opacity(0.18), lineWidth: 1)
        )
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
            .cruxGlassCard(cornerRadius: 12)
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

// MARK: - Chapter Insight Save Bar

/// Captures a chapter-level AI analysis as a Bookmark so it survives
/// app relaunches and shows up in the Bookmarks list / global Notes
/// view. The Bookmark uses `category = .analysis` and stores the prompt
/// label + assistant text in the note body.
struct ChapterInsightSaveBar: View {
    let book: Book
    let chapter: Chapter
    let thread: Thread
    @Binding var annotations: BookAnnotations
    @Binding var didJustSave: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lightbulb")
                .font(.caption)
                .foregroundStyle(.yellow)
            Text("Save this insight to revisit later.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: saveInsight) {
                Label(didJustSave ? "Saved" : "Save as Note",
                      systemImage: didJustSave ? "checkmark" : "bookmark.fill")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .tint(didJustSave ? .green : .accentColor)
            .controlSize(.small)
            .disabled(didJustSave)
            .help("Save this AI analysis as a chapter bookmark")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.yellow.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.yellow.opacity(0.2), lineWidth: 1)
        )
    }

    private func saveInsight() {
        let assistantText = thread.messages
            .last(where: { $0.role == .assistant })?.content ?? ""
        guard !assistantText.isEmpty else { return }
        let label = thread.messages
            .first(where: { $0.role == .user })?.content
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Chapter Insight"
        let chapterIndex = book.chapters.firstIndex(where: { $0.id == chapter.id }) ?? 0

        let bookmark = Bookmark(
            chapterId: chapter.id,
            chapterIndex: chapterIndex,
            chapterTitle: chapter.title,
            note: "**\(label)**\n\n\(assistantText)",
            scrollPosition: 0,
            category: .analysis
        )
        annotations.addBookmark(bookmark)

        // Persist asynchronously; the bookmark is already in the UI
        // state by the time we hand off to BookStorage.
        let snapshot = annotations
        Task.detached(priority: .utility) {
            try? await BookStorage.shared.saveAnnotations(snapshot)
        }

        withAnimation(.easeInOut(duration: 0.2)) { didJustSave = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation(.easeInOut(duration: 0.2)) { didJustSave = false }
        }
    }
}


// MARK: - Share Menu Button

#if os(macOS)
/// Wraps `NSSharingServicePicker` so SwiftUI views can drop the system
/// share affordance into a hover toolbar. The picker anchors to the
/// hosting NSView so the popover lands on the right control.
import AppKit

struct ShareMenuButton: View {
    let content: String

    var body: some View {
        SharePickerHost(content: content)
            .frame(width: 22, height: 22)
            .help("Share this response (Notes, Mail, Messages…)")
            .accessibilityLabel("Share AI response")
    }
}

private struct SharePickerHost: NSViewRepresentable {
    let content: String

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.image = NSImage(
            systemSymbolName: "square.and.arrow.up",
            accessibilityDescription: "Share"
        )
        button.imagePosition = .imageOnly
        button.target = context.coordinator
        button.action = #selector(Coordinator.share(_:))
        context.coordinator.contentProvider = { content }
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.contentProvider = { content }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, NSSharingServicePickerDelegate {
        var contentProvider: (() -> String)?

        @objc func share(_ sender: NSButton) {
            let text = contentProvider?() ?? ""
            guard !text.isEmpty else { return }
            let picker = NSSharingServicePicker(items: [text])
            picker.delegate = self
            picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }
}
#endif
