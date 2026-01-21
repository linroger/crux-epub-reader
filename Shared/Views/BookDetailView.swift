import SwiftUI
import SwiftData

struct BookDetailView: View {
    let storedBook: StoredBook
    let book: Book
    let onOpenBook: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var settings: [AppSettings]

    @State private var bookStats: BookReadingStatistics?
    @State private var sessionManager: ReadingSessionManager?

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
            }
            #endif
            .onAppear {
                loadStatistics()
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

                // Status badge
                HStack(spacing: 8) {
                    if storedBook.isFinished {
                        StatusBadge(text: "Finished", icon: "checkmark.circle.fill", color: .green)
                    } else if storedBook.currentChapterIndex > 0 {
                        StatusBadge(text: "In Progress", icon: "book.fill", color: .blue)
                    } else {
                        StatusBadge(text: "Not Started", icon: "book.closed", color: .gray)
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
                // TODO: Export book
            }) {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
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
}

// MARK: - Supporting Views

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
