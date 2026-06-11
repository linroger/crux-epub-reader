import SwiftUI
import SwiftData

struct NotesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: NotesViewModel
    @State private var selectedHighlight: HighlightWithBookInfo?
    @State private var editingAnnotation: HighlightWithBookInfo?
    @State private var annotationText = ""
    @State private var showingDeleteConfirmation = false
    @State private var highlightToDelete: HighlightWithBookInfo?
    @State private var showingExportSheet = false
    @State private var exportErrorMessage: String?
    @State private var showingExportSuccess = false

    init() {
        _viewModel = State(initialValue: NotesViewModel())
    }

    var body: some View {
        NavigationSplitView {
            // Sidebar with list of highlights
            sidebarContent
                .navigationTitle("All Highlights")
                .navigationSplitViewColumnWidth(min: 300, ideal: 400, max: 500)
                .toolbar {
                    ToolbarItemGroup {
                        searchAndFilter
                    }
                }
        } detail: {
            // Detail view showing selected highlight
            if let selected = selectedHighlight {
                detailContent(for: selected)
            } else {
                emptyDetailView
            }
        }
        .onAppear {
            viewModel.setModelContext(modelContext)
        }
        .sheet(item: $editingAnnotation) { item in
            AnnotationEditView(
                highlight: item,
                annotation: item.highlight.annotation ?? "",
                onSave: { newAnnotation in
                    Task {
                        try? await viewModel.updateAnnotation(for: item, annotation: newAnnotation)
                    }
                }
            )
        }
        .alert("Delete Highlight?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let highlight = highlightToDelete {
                    Task {
                        try? await viewModel.deleteHighlight(highlight)
                        if selectedHighlight?.id == highlight.id {
                            selectedHighlight = nil
                        }
                    }
                }
            }
        } message: {
            Text("This will permanently delete this highlight and all associated threads.")
        }
        .sheet(isPresented: $showingExportSheet) {
            ExportSheet(
                highlights: viewModel.filteredHighlights,
                onExportSuccess: {
                    showingExportSuccess = true
                },
                onExportError: { error in
                    exportErrorMessage = error
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

    // MARK: - Sidebar

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            // Statistics bar
            statsBar

            Divider()

            // Highlights list
            if viewModel.isLoading {
                ProgressView("Loading highlights...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.filteredHighlights.isEmpty {
                emptyStateView
            } else {
                highlightsList
            }
        }
    }

    private var statsBar: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(.blue)
                Text("Overview")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
            }

            HStack(spacing: 12) {
                statCard(
                    icon: "highlighter",
                    label: "Total",
                    value: "\(viewModel.totalHighlights)",
                    color: .blue
                )
                statCard(
                    icon: "bubble.left.and.bubble.right",
                    label: "Threads",
                    value: "\(viewModel.highlightsWithThreads)",
                    color: .purple
                )
                statCard(
                    icon: "note.text",
                    label: "Notes",
                    value: "\(viewModel.highlightsWithAnnotations)",
                    color: .green
                )
            }
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Color.cruxControlBackground, Color.cruxControlBackground.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func statCard(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(color)
            }

            VStack(spacing: 2) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .monospacedDigit()
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.cruxWindowBackground.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var highlightsList: some View {
        List(selection: $selectedHighlight) {
            ForEach(viewModel.filteredHighlights) { item in
                NoteHighlightListRow(item: item)
                    .tag(item)
                    .contextMenu {
                        highlightContextMenu(for: item)
                    }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "quote.bubble")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            if viewModel.totalHighlights == 0 {
                Text("No Highlights Yet")
                    .font(.title3)
                Text("Highlights you create while reading will appear here")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No Matching Highlights")
                    .font(.title3)
                Text("Try adjusting your filters or search")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    private var searchAndFilter: some View {
        HStack {
            // Search field
            TextField("Search highlights...", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)

            // Filter menu
            Menu {
                Picker("Filter", selection: $viewModel.filterOption) {
                    ForEach(NotesViewModel.FilterOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
            } label: {
                Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
            }

            // Sort menu
            Menu {
                Picker("Sort", selection: $viewModel.sortOption) {
                    ForEach(NotesViewModel.SortOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }

            // Refresh button
            Button {
                Task {
                    await viewModel.reload()
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }

            // Export button
            Button {
                showingExportSheet = true
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(viewModel.filteredHighlights.isEmpty)
        }
    }

    // MARK: - Detail View

    private func detailContent(for item: HighlightWithBookInfo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Book info card with gradient background
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "book.closed.fill")
                            .font(.title)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.bookTitle)
                                .font(.title3)
                                .fontWeight(.semibold)
                            Text(item.bookAuthor)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }

                    HStack {
                        Image(systemName: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(item.relativeDate)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.cruxControlBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                )

                // Selected text with enhanced highlighting
                VStack(alignment: .leading, spacing: 12) {
                    Label("Highlighted Text", systemImage: "highlighter")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    HStack(alignment: .top, spacing: 12) {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [.yellow, .orange],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 4)
                            .clipShape(RoundedRectangle(cornerRadius: 2))

                        Text(item.highlight.selectedText)
                            .textSelection(.enabled)
                            .font(.body)
                            .lineSpacing(6)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.yellow.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }

                // Personal annotation with enhanced card design
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Personal Note", systemImage: "note.text")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Spacer()
                        Button {
                            editingAnnotation = item
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: item.hasAnnotation ? "pencil" : "plus.circle")
                                Text(item.hasAnnotation ? "Edit" : "Add Note")
                            }
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.1))
                            .foregroundColor(.accentColor)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    if let annotation = item.highlight.annotation, !annotation.isEmpty {
                        HStack(alignment: .top, spacing: 12) {
                            Rectangle()
                                .fill(Color.blue.opacity(0.6))
                                .frame(width: 4)
                                .clipShape(RoundedRectangle(cornerRadius: 2))

                            Text(annotation)
                                .textSelection(.enabled)
                                .font(.body)
                                .lineSpacing(6)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.blue.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    } else {
                        HStack {
                            Image(systemName: "note.text.badge.plus")
                                .foregroundStyle(.secondary)
                            Text("No personal note yet")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5]))
                                .foregroundColor(.secondary.opacity(0.2))
                        )
                    }
                }

                // Threads with enhanced presentation
                if !item.highlight.threads.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("AI Conversations", systemImage: "bubble.left.and.bubble.right.fill")
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Spacer()

                            Text("\(item.threadCount)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.purple.opacity(0.2))
                                .foregroundColor(.purple)
                                .clipShape(Capsule())
                        }

                        VStack(spacing: 12) {
                            ForEach(item.highlight.threads) { thread in
                                ThreadSummaryView(thread: thread)
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolbar {
            ToolbarItem {
                Button(role: .destructive) {
                    highlightToDelete = item
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private var emptyDetailView: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.quote")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Select a Highlight")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Context Menu

    private func highlightContextMenu(for item: HighlightWithBookInfo) -> some View {
        Group {
            Button {
                editingAnnotation = item
            } label: {
                Label(item.hasAnnotation ? "Edit Note" : "Add Note", systemImage: "pencil")
            }

            Button(role: .destructive) {
                highlightToDelete = item
                showingDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Supporting Views

struct NoteHighlightListRow: View {
    let item: HighlightWithBookInfo
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Book title and date header
            HStack(spacing: 8) {
                Image(systemName: "book.fill")
                    .font(.caption2)
                    .foregroundStyle(.blue)

                Text(item.bookTitle)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                Text(item.highlight.createdAt.relativeShort)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
            }

            // Highlighted text preview with highlight indicator
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(Color.yellow)
                    .frame(width: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 1.5))

                Text(item.textPreview)
                    .font(.body)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Metadata badges with enhanced styling
            HStack(spacing: 6) {
                if item.hasAnnotation {
                    metadataBadge(
                        icon: "note.text",
                        text: "Note",
                        color: .blue
                    )
                }

                if item.threadCount > 0 {
                    metadataBadge(
                        icon: "bubble.left.and.bubble.right",
                        text: "\(item.threadCount)",
                        color: .purple
                    )
                }

                if item.messageCount > 0 {
                    metadataBadge(
                        icon: "message",
                        text: "\(item.messageCount)",
                        color: .green
                    )
                }

                Spacer()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.cruxControlBackground : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private func metadataBadge(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption2)
        .fontWeight(.medium)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15))
        .foregroundColor(color)
        .clipShape(Capsule())
    }
}

struct ThreadSummaryView: View {
    let thread: Thread

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("\(thread.messages.count) messages", systemImage: "message")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(thread.createdAt.relativeShort)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if let firstMessage = thread.messages.first {
                Text(firstMessage.content)
                    .font(.caption)
                    .lineLimit(3)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding()
        .background(.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct AnnotationEditView: View {
    let highlight: HighlightWithBookInfo
    @State private var annotation: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    init(highlight: HighlightWithBookInfo, annotation: String, onSave: @escaping (String) -> Void) {
        self.highlight = highlight
        self._annotation = State(initialValue: annotation)
        self.onSave = onSave
    }

    /// Insert a template scaffold into the note. Appends to existing text
    /// (separated by a blank line) so users can stack templates rather
    /// than overwriting their progress.
    private func insertTemplate(_ template: NoteTemplate) {
        if annotation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            annotation = template.body
        } else {
            annotation += "\n\n" + template.body
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                // Show the highlighted text for context
                VStack(alignment: .leading, spacing: 8) {
                    Text("Highlighted Text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(highlight.highlight.selectedText)
                        .font(.body)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.yellow.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Annotation editor
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Your Note")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        // Template menu — inserts a scaffold for common
                        // note types. Picked from a menu so users who
                        // don't want one just keep typing.
                        Menu {
                            ForEach(NoteTemplate.allCases) { template in
                                Button {
                                    insertTemplate(template)
                                } label: {
                                    Label(template.displayName, systemImage: template.symbolName)
                                }
                            }
                        } label: {
                            Label("Templates", systemImage: "doc.on.doc")
                                .labelStyle(.titleAndIcon)
                        }
                        .menuStyle(.borderlessButton)
                        .controlSize(.small)
                        .fixedSize()
                    }

                    TextEditor(text: $annotation)
                        .font(.body)
                        .frame(minHeight: 100)
                        .padding(4)
                        .border(Color.gray.opacity(0.3), width: 1)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Edit Note")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(annotation)
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 500, height: 400)
    }
}

// MARK: - Export Sheet

struct ExportSheet: View {
    let highlights: [HighlightWithBookInfo]
    let onExportSuccess: () -> Void
    let onExportError: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedFormat: ExportFormat = .csvBasic
    @State private var isExporting = false

    enum ExportFormat: String, CaseIterable, Identifiable {
        case csvBasic = "CSV (Basic)"
        case csvWithThreads = "CSV (With Threads)"
        case markdown = "Markdown"

        var id: String { rawValue }

        var fileExtension: String {
            switch self {
            case .csvBasic, .csvWithThreads:
                return "csv"
            case .markdown:
                return "md"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Format selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Export Format")
                        .font(.headline)

                    Picker("Format", selection: $selectedFormat) {
                        ForEach(ExportFormat.allCases) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    // `.radioGroup` is macOS-only; iOS uses segmented.
                    #if os(macOS)
                    .pickerStyle(.radioGroup)
                    #else
                    .pickerStyle(.segmented)
                    #endif
                }

                // Format descriptions
                VStack(alignment: .leading, spacing: 8) {
                    Text("Format Description")
                        .font(.headline)

                    Text(formatDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Statistics
                VStack(alignment: .leading, spacing: 8) {
                    Text("Export Statistics")
                        .font(.headline)

                    HStack(spacing: 16) {
                        statItem(label: "Highlights", value: "\(highlights.count)")
                        Divider()
                        statItem(label: "With Threads", value: "\(highlights.filter { !$0.highlight.threads.isEmpty }.count)")
                        Divider()
                        statItem(label: "Total Messages", value: "\(totalMessageCount)")
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
        .frame(width: 500, height: 450)
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
        case .csvBasic:
            return "Exports highlights with basic information: book title, author, highlighted text, personal notes, dates. One row per highlight."
        case .csvWithThreads:
            return "Exports highlights with full thread details. Each message in each thread gets its own row, allowing complete conversation history export."
        case .markdown:
            return "Exports highlights in a formatted Markdown document, grouped by book. Includes personal notes and thread summaries."
        }
    }

    private var totalMessageCount: Int {
        highlights.reduce(0) { total, item in
            total + item.highlight.threads.reduce(0) { $0 + $1.messages.count }
        }
    }

    private func performExport() {
        isExporting = true

        Task {
            do {
                let exportService = ExportService.shared
                let data: String

                switch selectedFormat {
                case .csvBasic:
                    data = try exportService.exportToCSV(highlights: highlights)
                case .csvWithThreads:
                    data = try exportService.exportToCSVWithThreads(highlights: highlights)
                case .markdown:
                    data = try exportService.exportToMarkdown(highlights: highlights)
                }

                #if os(macOS)
                let timestamp = Date().formatted(.dateTime.year().month().day().hour().minute())
                let suggestedFilename = "Crux_Highlights_\(timestamp).\(selectedFormat.fileExtension)"

                if await exportService.saveToFile(
                    data: data,
                    suggestedFilename: suggestedFilename,
                    contentType: selectedFormat.fileExtension == "csv" ? .commaSeparatedText : .plainText
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
