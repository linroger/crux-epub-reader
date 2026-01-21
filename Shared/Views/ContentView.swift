import SwiftUI
import SwiftData
#if os(iOS)
import UniformTypeIdentifiers
#endif

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoredBook.lastOpenedAt, order: .reverse) private var storedBooks: [StoredBook]
    @Query private var settings: [AppSettings]

    @State private var selectedBook: Book?
    @State private var isLoading = false
    @State private var errorHandler = ErrorHandler.shared
    #if os(iOS)
    @State private var showingDocumentPicker = false
    #endif

    private let parser = EPUBParser()
    private let storage = BookStorage.shared

    var body: some View {
        @Bindable var appState = appState

        Group {
            if let book = selectedBook, let bookId = appState.selectedBookId {
                // Reader view when a book is open
                ReaderView(book: book, bookId: bookId)
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            Button {
                                appState.selectedBookId = nil
                                selectedBook = nil
                            } label: {
                                Label("Library", systemImage: "chevron.left")
                            }
                        }
                    }
            } else {
                // Library view as main scene
                LibraryMainView(
                    storedBooks: storedBooks,
                    onSelectBook: { bookId in
                        appState.selectedBookId = bookId
                    },
                    onAddBook: { openFile() },
                    onDeleteBook: { book in
                        deleteBook(book)
                    },
                    onImportBook: { url in
                        await importBook(from: url)
                    }
                )
            }
        }
        .preferredColorScheme(appState.themeManager.colorScheme)
        .onChange(of: appState.selectedBookId) { _, newId in
            if let newId {
                Task { await loadBook(id: newId) }
            } else {
                selectedBook = nil
            }
        }
        .onChange(of: appState.showOpenPanel) { _, show in
            if show {
                openFile()
                appState.showOpenPanel = false
            }
        }
        .withFeedback()
        .overlay {
            if isLoading {
                ProgressView("Loading...")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showingDocumentPicker) {
            DocumentPicker { url in
                Task { await importBook(from: url) }
            }
        }
        #endif
        .task {
            await recoverOrphanedBooks()

            // Initialize services
            appState.searchHistoryService.configure(modelContext: modelContext)
            appState.tagManagementService.configure(modelContext: modelContext)

            // Configure theme manager
            if let appSettings = settings.first {
                appState.themeManager.configure(settings: appSettings)
            }
        }
    }

    private func deleteBook(_ book: StoredBook) {
        Task {
            try? await BookStorage.shared.removeBook(book.id)
        }
        if appState.selectedBookId == book.id {
            appState.selectedBookId = nil
        }
        modelContext.delete(book)
    }

    private func openFile() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.epub]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            Task { await importBook(from: url) }
        }
        #elseif os(iOS)
        showingDocumentPicker = true
        #endif
    }

    private func importBook(from url: URL) async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Copy to app storage
            let (storedURL, bookId) = try await storage.importBook(from: url)

            // Parse the book
            let book = try await parser.parse(url: storedURL)

            // Create SwiftData record with full metadata
            let storedBook = StoredBook(
                id: bookId,
                title: book.title,
                author: book.author,
                totalChapters: book.chapters.count
            )
            // Cache additional metadata
            storedBook.language = book.metadata.language
            storedBook.publisher = book.metadata.publisher
            storedBook.bookDescription = book.metadata.description
            storedBook.coverImageData = book.coverImage  // Cache cover image
            if let pubDate = book.metadata.publicationDate {
                storedBook.publicationYear = Calendar.current.component(.year, from: pubDate)
            }
            if !book.metadata.subjects.isEmpty,
               let jsonData = try? JSONEncoder().encode(book.metadata.subjects) {
                storedBook.subjectsJSON = String(data: jsonData, encoding: .utf8)
            }
            modelContext.insert(storedBook)
            try modelContext.save()

            // Select the new book
            appState.selectedBookId = bookId

            // Show success message
            errorHandler.showSuccess("Book imported successfully")
        } catch {
            errorHandler.handle(
                AppError.epubParsingFailed(error.localizedDescription),
                context: "importBook"
            )
        }
    }

    private func loadBook(id: UUID) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let url = await storage.bookURL(for: id)
            let book = try await parser.parse(url: url)

            // Update last opened time
            if let storedBook = storedBooks.first(where: { $0.id == id }) {
                storedBook.markOpened()
            }

            selectedBook = book
        } catch {
            errorHandler.handle(
                AppError.epubParsingFailed(error.localizedDescription),
                context: "loadBook"
            )
        }
    }

    /// Recovers books that exist in storage but not in SwiftData (e.g., after schema migration)
    private func recoverOrphanedBooks() async {
        do {
            let storedIds = try await storage.listStoredBookIds()
            let knownIds = Set(storedBooks.map { $0.id })

            for bookId in storedIds where !knownIds.contains(bookId) {
                // Parse the orphaned book
                let url = await storage.bookURL(for: bookId)
                guard let book = try? await parser.parse(url: url) else { continue }

                // Recreate SwiftData entry
                let storedBook = StoredBook(
                    id: bookId,
                    title: book.title,
                    author: book.author,
                    totalChapters: book.chapters.count
                )
                storedBook.language = book.metadata.language
                storedBook.publisher = book.metadata.publisher
                storedBook.bookDescription = book.metadata.description
                if let pubDate = book.metadata.publicationDate {
                    storedBook.publicationYear = Calendar.current.component(.year, from: pubDate)
                }
                if !book.metadata.subjects.isEmpty,
                   let jsonData = try? JSONEncoder().encode(book.metadata.subjects) {
                    storedBook.subjectsJSON = String(data: jsonData, encoding: .utf8)
                }
                modelContext.insert(storedBook)
            }

            if !storedIds.isEmpty {
                try? modelContext.save()
            }
        } catch {
            // Silent failure - recovery is best-effort
        }
    }
}

// MARK: - iOS Document Picker

#if os(iOS)
import UIKit

struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.epub])
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}
#endif

#Preview {
    ContentView()
        .environment(AppState())
        .modelContainer(for: StoredBook.self, inMemory: true)
}
