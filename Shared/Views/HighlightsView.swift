import SwiftUI

struct HighlightsView: View {
    let bookId: UUID
    let highlights: [Highlight]
    let bookTitle: String
    let bookAuthor: String
    let onSelectHighlight: (Highlight) -> Void
    let onDeleteHighlight: (UUID) -> Void

    @State private var showingExportSheet = false
    @State private var showingExportSuccess = false
    @State private var exportErrorMessage: String?

    var body: some View {
        Group {
            if highlights.isEmpty {
                ContentUnavailableView(
                    "No Highlights",
                    systemImage: "highlighter",
                    description: Text("Select text while reading to create highlights and annotations")
                )
            } else {
                List {
                    ForEach(highlights) { highlight in
                        BookHighlightRow(
                            highlight: highlight,
                            onTap: {
                                onSelectHighlight(highlight)
                            }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                onDeleteHighlight(highlight.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    showingExportSheet = true
                } label: {
                    Label("Export Highlights", systemImage: "square.and.arrow.up")
                }
                .disabled(highlights.isEmpty)
            }
        }
        .sheet(isPresented: $showingExportSheet) {
            ExportHighlightsSheet(
                bookId: bookId,
                highlights: highlights,
                bookTitle: bookTitle,
                bookAuthor: bookAuthor,
                onExportSuccess: {
                    showingExportSuccess = true
                },
                onExportError: { errorMessage in
                    exportErrorMessage = errorMessage
                }
            )
        }
        .alert("Export Successful", isPresented: $showingExportSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your highlights have been exported successfully.")
        }
        .alert("Export Failed", isPresented: .constant(exportErrorMessage != nil)) {
            Button("OK", role: .cancel) {
                exportErrorMessage = nil
            }
        } message: {
            Text(exportErrorMessage ?? "An unknown error occurred.")
        }
    }
}

struct BookHighlightRow: View {
    let highlight: Highlight
    let onTap: () -> Void

    @State private var isHovering = false
    @State private var showThreads = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                // Accent bar with blue/cyan gradient
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue, Color.cyan.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3)
                    .opacity(isHovering ? 1.0 : 0.6)

                VStack(alignment: .leading, spacing: 8) {
                    // Highlighted text
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.blue.opacity(0.3), Color.cyan.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 24, height: 24)

                            Image(systemName: "highlighter")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.blue)
                        }

                        Text(highlight.selectedText)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer()
                    }

                    // Annotation if present
                    if let annotation = highlight.annotation, !annotation.isEmpty {
                        HStack(spacing: 0) {
                            Rectangle()
                                .fill(Color.blue.opacity(0.4))
                                .frame(width: 2)

                            Text(annotation)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .padding(.leading, 8)
                        }
                        .padding(.leading, 12)
                    }

                    // Thread info if present
                    if !highlight.threads.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showThreads.toggle()
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: showThreads ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(.secondary)

                                    Image(systemName: "bubble.left.and.bubble.right.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.blue)

                                    let messageCount = highlight.threads.reduce(0) { $0 + $1.messages.count }
                                    Text("\(highlight.threads.count) thread\(highlight.threads.count == 1 ? "" : "s"), \(messageCount) message\(messageCount == 1 ? "" : "s")")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.secondary)

                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)

                            if showThreads {
                                ForEach(highlight.threads) { thread in
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(thread.messages) { message in
                                            HStack(alignment: .top, spacing: 8) {
                                                Image(systemName: message.role == .user ? "person.circle.fill" : "sparkles")
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(message.role == .user ? .blue : .purple)

                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(message.role == .user ? "You" : "AI")
                                                        .font(.system(size: 10, weight: .semibold))
                                                        .foregroundStyle(message.role == .user ? .blue : .purple)

                                                    Text(message.content)
                                                        .font(.system(size: 12))
                                                        .foregroundStyle(.primary)
                                                        .fixedSize(horizontal: false, vertical: true)
                                                }

                                                Spacer()
                                            }
                                            .padding(8)
                                            .background(
                                                message.role == .user
                                                    ? Color.blue.opacity(0.08)
                                                    : Color.purple.opacity(0.08)
                                            )
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                        }
                                    }
                                    .padding(.leading, 8)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                        }
                        .padding(.leading, 12)
                    }

                    // Creation date
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)

                        Text(highlight.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.leading, 12)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            isHovering
                ? Color.secondary.opacity(0.05)
                : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Export Sheet

enum HighlightExportFormat: String, CaseIterable, Identifiable {
    case csv = "CSV"
    case csvWithThreads = "CSV with Threads"

    var id: String { rawValue }

    var fileExtension: String {
        return "csv"
    }
}

struct ExportHighlightsSheet: View {
    let bookId: UUID
    let highlights: [Highlight]
    let bookTitle: String
    let bookAuthor: String
    let onExportSuccess: () -> Void
    let onExportError: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedFormat: HighlightExportFormat = .csv
    @State private var isExporting = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                // Format Selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Export Format")
                        .font(.headline)

                    Picker("Format", selection: $selectedFormat) {
                        ForEach(HighlightExportFormat.allCases) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(formatDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Statistics
                VStack(alignment: .leading, spacing: 8) {
                    Text("Export Statistics")
                        .font(.headline)

                    HStack(spacing: 16) {
                        statItem(label: "Total Highlights", value: "\(highlights.count)")
                        Divider()
                        statItem(label: "With Annotations", value: "\(highlights.filter { $0.annotation != nil && !$0.annotation!.isEmpty }.count)")
                        Divider()
                        statItem(label: "With Threads", value: "\(highlights.filter { !$0.threads.isEmpty }.count)")
                    }
                    .padding()
                    .background(.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Export Highlights")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") {
                        performExport()
                    }
                    .disabled(isExporting)
                }
            }
        }
        .frame(width: 500, height: 400)
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var formatDescription: String {
        switch selectedFormat {
        case .csv:
            return "Exports highlights as a CSV file with book title, author, highlighted text, annotations, and dates."
        case .csvWithThreads:
            return "Exports highlights with their AI conversation threads, including all questions and responses."
        }
    }

    private func performExport() {
        isExporting = true

        Task {
            do {
                let exportService = ExportService.shared

                // Convert highlights to HighlightWithBookInfo
                let highlightsWithInfo = highlights.map { highlight in
                    HighlightWithBookInfo(
                        highlight: highlight,
                        bookId: bookId,
                        bookTitle: bookTitle,
                        bookAuthor: bookAuthor
                    )
                }

                let data: String

                switch selectedFormat {
                case .csv:
                    data = try exportService.exportToCSV(highlights: highlightsWithInfo)
                case .csvWithThreads:
                    data = try exportService.exportToCSVWithThreads(highlights: highlightsWithInfo)
                }

                #if os(macOS)
                let timestamp = Date().formatted(.dateTime.year().month().day().hour().minute())
                let suggestedFilename = "Crux_Highlights_\(timestamp).\(selectedFormat.fileExtension)"

                if await exportService.saveToFile(
                    data: data,
                    suggestedFilename: suggestedFilename,
                    contentType: .commaSeparatedText
                ) != nil {
                    dismiss()
                    onExportSuccess()
                } else {
                    // User cancelled or save failed
                    isExporting = false
                }
                #else
                // iOS export would use share sheet
                isExporting = false
                dismiss()
                onExportSuccess()
                #endif
            } catch {
                isExporting = false
                onExportError(error.localizedDescription)
                dismiss()
            }
        }
    }
}

#Preview {
    NavigationStack {
        HighlightsView(
            bookId: UUID(),
            highlights: [
                Highlight(
                    chapterId: "ch1",
                    selectedText: "This is an important passage that deserves highlighting and careful consideration.",
                    surroundingContext: "Context before... This is an important passage that deserves highlighting and careful consideration. ...context after",
                    cfiRange: CFIRange(
                        startPath: "/1/2/3",
                        startOffset: 4,
                        endPath: "/1/2/3",
                        endOffset: 50
                    ),
                    annotation: "This reminds me of the earlier chapter where the author discussed similar themes."
                ),
                Highlight(
                    chapterId: "ch3",
                    selectedText: "A quote worth remembering.",
                    surroundingContext: "Some context... A quote worth remembering. ...more context",
                    cfiRange: CFIRange(
                        startPath: "/1/2/5",
                        startOffset: 10,
                        endPath: "/1/2/5",
                        endOffset: 35
                    )
                )
            ],
            bookTitle: "Sample Book",
            bookAuthor: "John Doe",
            onSelectHighlight: { _ in },
            onDeleteHighlight: { _ in }
        )
        .navigationTitle("Highlights")
    }
}
