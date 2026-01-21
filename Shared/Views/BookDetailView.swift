import SwiftUI
import SwiftData

struct BookDetailView: View {
    let storedBook: StoredBook
    let book: Book
    let onOpenBook: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var settings: [AppSettings]
    @Query(sort: \BookCollection.sortOrder) private var collections: [BookCollection]

    @State private var bookStats: BookReadingStatistics?
    @State private var sessionManager: ReadingSessionManager?
    @State private var showingExportSheet = false
    @State private var showingEditSheet = false

    private var isTrackingEnabled: Bool {
        settings.first?.trackReadingTime ?? true
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header with cover and basic info
                    headerSection

                    // Reading progress
                    progressSection

                    // Quick actions
                    actionsSection

                    // Collections
                    if !collections.isEmpty {
                        collectionsSection
                    }

                    // Reading statistics
                    if isTrackingEnabled {
                        statisticsSection
                    }

                    // Metadata
                    metadataSection

                    // Description
                    if let description = book.metadata.description, !description.isEmpty {
                        descriptionSection(description)
                    }
                }
                .padding()
            }
            .navigationTitle("Book Details")
            #if os(macOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingEditSheet = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .help("Edit book metadata")
                }
            }
            #endif
            .onAppear {
                loadStatistics()
            }
            .sheet(isPresented: $showingExportSheet) {
                BookExportSheet(book: book, storedBook: storedBook)
            }
            .sheet(isPresented: $showingEditSheet) {
                EditBookMetadataSheet(storedBook: storedBook)
            }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 700)
        #endif
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 20) {
            // Cover image
            if let coverData = book.coverImage,
               let nsImage = NSImage(data: coverData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 180)
                    .cornerRadius(8)
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 120, height: 180)

                    Image(systemName: "book.closed")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                // Title
                Text(book.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .fixedSize(horizontal: false, vertical: true)

                // Author
                if let author = book.author {
                    HStack(spacing: 6) {
                        Image(systemName: "person.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(author)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                // Reading status picker
                HStack(spacing: 12) {
                    Menu {
                        ForEach([ReadingStatus.wantToRead, .reading, .finished], id: \.self) { status in
                            Button {
                                storedBook.readingStatus = status
                                try? modelContext.save()
                            } label: {
                                HStack {
                                    Image(systemName: status.systemImage)
                                    Text(status.rawValue)
                                    if storedBook.readingStatus == status {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: storedBook.readingStatus.systemImage)
                                .font(.caption)
                            Text(storedBook.readingStatus.rawValue)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(statusColor.opacity(0.15))
                        .foregroundStyle(statusColor)
                        .cornerRadius(8)
                    }

                    // Chapter count
                    HStack(spacing: 4) {
                        Image(systemName: "list.bullet")
                            .font(.caption2)
                        Text("\(storedBook.totalChapters) chapters")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(6)
                }

                var statusColor: Color {
                    switch storedBook.readingStatus {
                    case .wantToRead: return .gray
                    case .reading: return .blue
                    case .finished: return .green
                    }
                }
            }

            Spacer()
        }
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reading Progress")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Chapter \(storedBook.currentChapterIndex + 1) of \(storedBook.totalChapters)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(Int(storedBook.progress * 100))%")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                }

                ProgressView(value: storedBook.progress)
                    .tint(.blue)

                // Last opened
                if let lastOpened = storedBook.lastOpenedAt {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.caption2)
                        Text("Last opened \(lastOpened.relativeShort)")
                            .font(.caption)
                    }
                    .foregroundStyle(.tertiary)
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(10)
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        HStack(spacing: 12) {
            Button(action: {
                dismiss()
                onOpenBook()
            }) {
                Label(storedBook.currentChapterIndex > 0 ? "Continue Reading" : "Start Reading", systemImage: "book.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button(action: {
                showingExportSheet = true
            }) {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    // MARK: - Collections Section

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Collections")
                .font(.headline)
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 8) {
                ForEach(collections) { collection in
                    CollectionTag(
                        collection: collection,
                        isSelected: storedBook.collections?.contains(where: { $0.id == collection.id }) ?? false,
                        onTap: {
                            toggleBookInCollection(collection)
                        }
                    )
                }
            }
        }
    }

    // MARK: - Statistics Section

    private var statisticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reading Statistics")
                .font(.headline)
                .foregroundStyle(.secondary)

            if let stats = bookStats {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    StatBox(
                        title: "Total Time",
                        value: stats.formattedTotalTime,
                        icon: "clock.fill",
                        color: .blue
                    )

                    StatBox(
                        title: "Sessions",
                        value: "\(stats.sessionCount)",
                        icon: "book.fill",
                        color: .purple
                    )

                    StatBox(
                        title: "Avg. Session",
                        value: stats.formattedAverageSession,
                        icon: "timer",
                        color: .orange
                    )

                    StatBox(
                        title: "Current Streak",
                        value: "\(stats.currentStreak) \(stats.currentStreak == 1 ? "day" : "days")",
                        icon: "flame.fill",
                        color: .red
                    )
                }
            } else {
                Text("No reading sessions yet")
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(10)
            }
        }
    }

    // MARK: - Metadata Section

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                if let publisher = book.metadata.publisher {
                    MetadataRow(label: "Publisher", value: publisher)
                    Divider()
                }

                if let pubDate = book.metadata.publicationDate {
                    MetadataRow(label: "Published", value: formatDate(pubDate))
                    Divider()
                }

                if let language = book.metadata.language {
                    MetadataRow(label: "Language", value: language)
                    Divider()
                }

                MetadataRow(label: "Added", value: formatDate(storedBook.addedAt))

                if !book.metadata.subjects.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Subjects")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        FlowLayout(spacing: 6) {
                            ForEach(book.metadata.subjects, id: \.self) { subject in
                                Text(subject)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundStyle(.blue)
                                    .cornerRadius(6)
                            }
                        }
                    }
                    .padding()
                }

                if !storedBook.tags.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tags")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        FlowLayout(spacing: 6) {
                            ForEach(storedBook.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.purple.opacity(0.1))
                                    .foregroundStyle(.purple)
                                    .cornerRadius(6)
                            }
                        }
                    }
                    .padding()
                }
            }
            .background(Color(.controlBackgroundColor))
            .cornerRadius(10)
        }
    }

    // MARK: - Description Section

    private func descriptionSection(_ description: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Description")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(description)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(10)
        }
    }

    // MARK: - Helper Methods

    private func loadStatistics() {
        sessionManager = ReadingSessionManager(
            modelContext: modelContext,
            isTrackingEnabled: isTrackingEnabled
        )

        Task {
            let stats = await sessionManager?.getBookStatistics(bookId: storedBook.id)
            bookStats = stats
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func toggleBookInCollection(_ collection: BookCollection) {
        if let bookCollections = storedBook.collections,
           bookCollections.contains(where: { $0.id == collection.id }) {
            // Remove from collection
            storedBook.collections?.removeAll(where: { $0.id == collection.id })
        } else {
            // Add to collection
            if storedBook.collections == nil {
                storedBook.collections = []
            }
            storedBook.collections?.append(collection)
        }
        try? modelContext.save()
    }
}

// MARK: - Supporting Views

struct BookExportSheet: View {
    let book: Book
    let storedBook: StoredBook

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFormat: ExportFormat = .both
    @State private var isExporting = false
    @State private var exportError: String?

    enum ExportFormat: String, CaseIterable, Identifiable {
        case epubOnly = "EPUB File Only"
        case highlightsOnly = "Highlights & Notes Only"
        case both = "EPUB + Highlights"

        var id: String { self.rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Export Format", selection: $selectedFormat) {
                        ForEach(ExportFormat.allCases) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        switch selectedFormat {
                        case .epubOnly:
                            Label("Export the EPUB file to a location of your choice", systemImage: "doc.fill")
                        case .highlightsOnly:
                            Label("Export highlights and notes as Markdown", systemImage: "note.text")
                        case .both:
                            Label("Export EPUB file and highlights/notes", systemImage: "doc.on.doc.fill")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                if let error = exportError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Export Book")
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
        #if os(macOS)
        .frame(minWidth: 450, minHeight: 300)
        #endif
    }

    private func performExport() {
        isExporting = true
        exportError = nil

        Task {
            do {
                switch selectedFormat {
                case .epubOnly:
                    try await exportEPUB()
                case .highlightsOnly:
                    try await exportHighlights()
                case .both:
                    try await exportEPUB()
                    try await exportHighlights()
                }

                await MainActor.run {
                    isExporting = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    exportError = "Export failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func exportEPUB() async throws {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.epub]
        panel.nameFieldStringValue = "\(book.title).epub"
        panel.message = "Choose where to save the EPUB file"

        let response = await panel.begin()
        guard response == .OK, let url = panel.url else {
            throw ExportError.cancelled
        }

        // Copy EPUB file to chosen location
        let sourceURL = await BookStorage.shared.bookURL(for: storedBook.id)
        try FileManager.default.copyItem(at: sourceURL, to: url)
        #endif
    }

    private func exportHighlights() async throws {
        // Load annotations for this book
        let annotations = try await BookStorage.shared.loadAnnotations(for: storedBook.id)

        guard !annotations.highlights.isEmpty else {
            throw ExportError.noHighlights
        }

        // Generate Markdown content
        var markdown = "# \(book.title)\n\n"
        if let author = book.author {
            markdown += "**Author:** \(author)\n\n"
        }
        markdown += "---\n\n"
        markdown += "## Highlights & Notes\n\n"

        for (index, highlight) in annotations.highlights.enumerated() {
            markdown += "### Highlight \(index + 1)\n\n"
            markdown += "> \(highlight.selectedText)\n\n"
            if let note = highlight.annotation, !note.isEmpty {
                markdown += "**Note:** \(note)\n\n"
            }
            markdown += "---\n\n"
        }

        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(book.title) - Highlights.md"
        panel.message = "Choose where to save the highlights"

        let response = await panel.begin()
        guard response == .OK, let url = panel.url else {
            throw ExportError.cancelled
        }

        try markdown.write(to: url, atomically: true, encoding: String.Encoding.utf8)
        #endif
    }

    enum ExportError: LocalizedError {
        case cancelled
        case noHighlights

        var errorDescription: String? {
            switch self {
            case .cancelled:
                return "Export cancelled"
            case .noHighlights:
                return "No highlights or notes to export"
            }
        }
    }
}

struct StatusBadge: View {
    let text: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.15))
        .cornerRadius(8)
    }
}

struct StatBox: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(10)
    }
}

struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)

            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding()
    }
}

struct CollectionTag: View {
    let collection: BookCollection
    let isSelected: Bool
    let onTap: () -> Void

    private var color: Color {
        Color(hex: collection.colorHex) ?? .blue
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: collection.icon)
                    .font(.system(size: 12))
                Text(collection.name)
                    .font(.system(size: 13))
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? color.opacity(0.2) : Color.secondary.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? color : .clear, lineWidth: 1.5)
                    )
            )
            .foregroundStyle(isSelected ? color : .secondary)
        }
        .buttonStyle(.plain)
    }
}

// Simple flow layout for tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX,
                                     y: bounds.minY + result.frames[index].minY),
                         proposal: .unspecified)
        }
    }

    struct FlowResult {
        var frames: [CGRect] = []
        var size: CGSize = .zero

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }

                frames.append(CGRect(origin: CGPoint(x: currentX, y: currentY), size: size))

                currentX += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }

            self.size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}

// MARK: - Edit Book Metadata Sheet

struct EditBookMetadataSheet: View {
    let storedBook: StoredBook

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var author: String
    @State private var publisher: String
    @State private var language: String
    @State private var description: String
    @State private var publicationYear: String
    @State private var subjectsText: String
    @State private var tagsText: String

    init(storedBook: StoredBook) {
        self.storedBook = storedBook
        _title = State(initialValue: storedBook.title)
        _author = State(initialValue: storedBook.author ?? "")
        _publisher = State(initialValue: storedBook.publisher ?? "")
        _language = State(initialValue: storedBook.language ?? "")
        _description = State(initialValue: storedBook.bookDescription ?? "")
        _publicationYear = State(initialValue: storedBook.publicationYear.map { String($0) } ?? "")
        _subjectsText = State(initialValue: storedBook.subjects.joined(separator: ", "))
        _tagsText = State(initialValue: storedBook.tags.joined(separator: ", "))
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Information") {
                    TextField("Title", text: $title)
                        .textFieldStyle(.roundedBorder)

                    TextField("Author", text: $author)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Publication Details") {
                    TextField("Publisher", text: $publisher)
                        .textFieldStyle(.roundedBorder)

                    TextField("Publication Year", text: $publicationYear)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: publicationYear) { _, newValue in
                            // Filter to only allow digits
                            publicationYear = newValue.filter { $0.isNumber }
                        }

                    TextField("Language", text: $language)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Description") {
                    TextEditor(text: $description)
                        .frame(minHeight: 100)
                }

                Section {
                    TextField("Subjects (comma-separated)", text: $subjectsText)
                        .textFieldStyle(.roundedBorder)
                } header: {
                    Text("Subjects")
                } footer: {
                    Text("Separate multiple subjects with commas")
                }

                Section {
                    TextField("Tags (comma-separated)", text: $tagsText)
                        .textFieldStyle(.roundedBorder)
                } header: {
                    Text("Tags")
                } footer: {
                    Text("Add flexible tags for custom organization")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Book Metadata")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(!isValid)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 600)
        #endif
    }

    private func saveChanges() {
        // Update basic info
        storedBook.title = title.trimmingCharacters(in: .whitespaces)

        let trimmedAuthor = author.trimmingCharacters(in: .whitespaces)
        storedBook.author = trimmedAuthor.isEmpty ? nil : trimmedAuthor

        // Update publication details
        let trimmedPublisher = publisher.trimmingCharacters(in: .whitespaces)
        storedBook.publisher = trimmedPublisher.isEmpty ? nil : trimmedPublisher

        let trimmedLanguage = language.trimmingCharacters(in: .whitespaces)
        storedBook.language = trimmedLanguage.isEmpty ? nil : trimmedLanguage

        // Parse and update publication year
        if let year = Int(publicationYear.trimmingCharacters(in: .whitespaces)), year > 0 {
            storedBook.publicationYear = year
        } else {
            storedBook.publicationYear = nil
        }

        // Update description
        let trimmedDescription = description.trimmingCharacters(in: .whitespaces)
        storedBook.bookDescription = trimmedDescription.isEmpty ? nil : trimmedDescription

        // Parse and update subjects
        let subjects = subjectsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if !subjects.isEmpty,
           let jsonData = try? JSONEncoder().encode(subjects) {
            storedBook.subjectsJSON = String(data: jsonData, encoding: .utf8)
        } else {
            storedBook.subjectsJSON = nil
        }

        // Parse and update tags
        let tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        storedBook.setTags(tags)

        // Save to SwiftData
        try? modelContext.save()

        dismiss()
    }
}
