import SwiftUI
import SwiftData

struct BookMetadataEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let storedBook: StoredBook

    @State private var title: String
    @State private var author: String
    @State private var publisher: String
    @State private var publishedDate: String
    @State private var language: String
    @State private var isbn: String
    @State private var description: String
    @State private var subjects: [String]
    @State private var tags: [String]
    @State private var newSubject = ""
    @State private var newTag = ""
    @State private var showingImagePicker = false
    @State private var selectedImageURL: URL?

    init(storedBook: StoredBook) {
        self.storedBook = storedBook
        _title = State(initialValue: storedBook.title)
        _author = State(initialValue: storedBook.author ?? "")
        _publisher = State(initialValue: storedBook.publisher ?? "")
        _publishedDate = State(initialValue: storedBook.publishedDate ?? "")
        _language = State(initialValue: storedBook.language ?? "")
        _isbn = State(initialValue: storedBook.isbn ?? "")
        _description = State(initialValue: storedBook.bookDescription ?? "")
        _subjects = State(initialValue: storedBook.subjects)
        _tags = State(initialValue: storedBook.tags)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Basic Information
                Section {
                    TextField("Title", text: $title)
                    TextField("Author", text: $author)
                    TextField("Publisher", text: $publisher)
                } header: {
                    Text("Basic Information")
                }

                // Publication Details
                Section {
                    TextField("Published Date", text: $publishedDate)
                        .help("Format: YYYY-MM-DD or YYYY")
                    TextField("Language", text: $language)
                    TextField("ISBN", text: $isbn)
                } header: {
                    Text("Publication Details")
                }

                // Description
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        #if os(macOS)
                        TextEditor(text: $description)
                            .frame(minHeight: 100, maxHeight: 200)
                            .font(.body)
                        #else
                        TextEditor(text: $description)
                            .frame(height: 150)
                            .font(.body)
                        #endif
                    }
                }

                // Subjects
                Section {
                    ForEach(subjects.indices, id: \.self) { index in
                        HStack {
                            Text(subjects[index])
                            Spacer()
                            Button {
                                subjects.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack {
                        TextField("Add subject...", text: $newSubject)
                        Button {
                            addSubject()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.green)
                        }
                        .buttonStyle(.plain)
                        .disabled(newSubject.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Subjects")
                } footer: {
                    Text("Subjects categorize the book's content")
                }

                // Tags
                Section {
                    ForEach(tags.indices, id: \.self) { index in
                        HStack {
                            Text(tags[index])
                            Spacer()
                            Button {
                                tags.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack {
                        TextField("Add tag...", text: $newTag)
                        Button {
                            addTag()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.green)
                        }
                        .buttonStyle(.plain)
                        .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Tags")
                } footer: {
                    Text("Tags help organize and filter your library")
                }

                // Cover Image
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            if let coverPath = storedBook.coverImagePath,
                               let coverURL = BookStorage.shared.getCoverImageURL(for: coverPath) {
                                AsyncImage(url: coverURL) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                } placeholder: {
                                    ProgressView()
                                }
                                .frame(width: 100, height: 150)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: 100, height: 150)
                                    .overlay {
                                        Image(systemName: "book.closed")
                                            .font(.system(size: 40))
                                            .foregroundStyle(.secondary)
                                    }
                            }

                            Spacer()

                            Button {
                                showingImagePicker = true
                            } label: {
                                Label("Change Cover", systemImage: "photo")
                            }
                        }
                    }
                } header: {
                    Text("Cover Image")
                }

                // Warning
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.blue)
                        Text("Changes will be saved immediately when you tap Save")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Edit Metadata")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveMetadata()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 700)
        #endif
    }

    private func addSubject() {
        let trimmed = newSubject.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !subjects.contains(trimmed) else { return }
        subjects.append(trimmed)
        newSubject = ""
    }

    private func addTag() {
        let trimmed = newTag.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !tags.contains(trimmed) else { return }
        tags.append(trimmed)
        newTag = ""
    }

    private func saveMetadata() {
        // Update the stored book
        storedBook.title = title.trimmingCharacters(in: .whitespaces)
        storedBook.author = author.trimmingCharacters(in: .whitespaces).isEmpty ? nil : author.trimmingCharacters(in: .whitespaces)
        storedBook.publisher = publisher.trimmingCharacters(in: .whitespaces).isEmpty ? nil : publisher.trimmingCharacters(in: .whitespaces)
        storedBook.publishedDate = publishedDate.trimmingCharacters(in: .whitespaces).isEmpty ? nil : publishedDate.trimmingCharacters(in: .whitespaces)
        storedBook.language = language.trimmingCharacters(in: .whitespaces).isEmpty ? nil : language.trimmingCharacters(in: .whitespaces)
        storedBook.isbn = isbn.trimmingCharacters(in: .whitespaces).isEmpty ? nil : isbn.trimmingCharacters(in: .whitespaces)
        storedBook.bookDescription = description.trimmingCharacters(in: .whitespaces).isEmpty ? nil : description.trimmingCharacters(in: .whitespaces)
        storedBook.subjects = subjects
        storedBook.tags = tags

        // Save to context
        try? modelContext.save()

        dismiss()
    }
}

#Preview("Book Metadata Editor") {
    @Previewable @State var book = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: StoredBook.self,
            configurations: config
        )
        let b = StoredBook(
            id: UUID(),
            title: "Sample Book",
            author: "Sample Author",
            totalChapters: 10
        )
        container.mainContext.insert(b)
        return b
    }()

    BookMetadataEditorView(storedBook: book)
}
