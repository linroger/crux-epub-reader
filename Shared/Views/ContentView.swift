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
    @State private var showingOnboarding = false
    #if os(iOS)
    @State private var showingDocumentPicker = false
    #endif

    private let parser = EPUBParser()
    private let storage = BookStorage.shared

    var body: some View {
        @Bindable var appState = appState

        Group {
            if let book = selectedBook, let bookId = appState.selectedBookId {
                // Reader view when a book is open.
                #if os(iOS)
                // iOS has no window toolbar host — without a NavigationStack
                // the reader's entire toolbar (back to library, chapters,
                // bookmarks, Ask AI) would silently vanish. The library has
                // its own NavigationStack, and the reader is a state-swapped
                // sibling here, so it needs its own.
                NavigationStack {
                    ReaderView(book: book, bookId: bookId)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button {
                                    appState.selectedBookId = nil
                                    selectedBook = nil
                                } label: {
                                    Label("Library", systemImage: "chevron.left")
                                }
                            }
                        }
                }
                #else
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
                #endif
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
        .onChange(of: appState.showImportNotesPanel) { _, show in
            if show {
                openNotesImportPanel()
                appState.showImportNotesPanel = false
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
        .sheet(isPresented: $showingOnboarding) {
            OnboardingView(onFinish: markOnboardingComplete)
        }
        .task {
            await recoverOrphanedBooks()

            // Initialize services
            appState.searchHistoryService.configure(modelContext: modelContext)
            appState.tagManagementService.configure(modelContext: modelContext)

            // Configure theme manager
            if let appSettings = settings.first {
                appState.themeManager.configure(settings: appSettings)
                showingOnboarding = !appSettings.hasSeenOnboarding
            } else {
                // First run: create default settings and show onboarding.
                let newSettings = AppSettings.createDefault()
                modelContext.insert(newSettings)
                try? modelContext.save()
                appState.themeManager.configure(settings: newSettings)
                showingOnboarding = true
            }
        }
    }

    private func markOnboardingComplete() {
        if let appSettings = settings.first {
            appSettings.hasSeenOnboarding = true
            try? modelContext.save()
        }
    }

    private func deleteBook(_ book: StoredBook) {
        let bookId = book.id
        Task {
            try? await BookStorage.shared.removeBook(bookId)
            await SpotlightIndexer.shared.unindexBook(id: bookId)
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

    /// Show an Open panel filtered to `.cruxnotes` files and import the
    /// chosen bundle. macOS-only — the panel uses `NSOpenPanel`. On iOS
    /// the same flow will live behind a `.fileImporter`, but the menu
    /// surface that triggers this is macOS-only today.
    private func openNotesImportPanel() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.cruxNotesBundle, .json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a .cruxnotes bundle to merge into your library"

        if panel.runModal() == .OK, let url = panel.url {
            Task { await importNotesBundle(from: url) }
        }
        #endif
    }

    private func importNotesBundle(from url: URL) async {
        do {
            let bundle = try await CruxNotesIO.shared.read(from: url)

            // Match the bundle to a book in the user's library. First try
            // bookId (the original export came from the same library),
            // then by case-insensitive title + author (different library,
            // but the user has imported the same EPUB).
            let matched: StoredBook? = {
                if let exact = storedBooks.first(where: { $0.id == bundle.bookId }) {
                    return exact
                }
                let title = bundle.bookTitle.lowercased()
                let author = bundle.bookAuthor?.lowercased()
                return storedBooks.first { book in
                    book.title.lowercased() == title
                        && (book.author?.lowercased() == author || author == nil)
                }
            }()

            guard let target = matched else {
                throw CruxNotesIO.ImportError.noMatchingBook(
                    title: bundle.bookTitle,
                    author: bundle.bookAuthor
                )
            }

            // Merge into the existing annotations for the matched book.
            let existing = (try? await BookStorage.shared.loadAnnotations(for: target.id))
                ?? BookAnnotations(bookId: target.id)
            let (merged, summary) = await CruxNotesIO.shared.merge(bundle: bundle, into: existing)
            try await BookStorage.shared.saveAnnotations(merged)

            errorHandler.showSuccess("\(summary.humanReadable) Imported into “\(target.title).”")
        } catch {
            errorHandler.handle(
                AppError.exportFailed(error.localizedDescription),
                context: "importNotesBundle"
            )
        }
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
            // Cache reading-time estimate so library rows can show
            // "~12 min read" without re-parsing every chapter.
            let totalMinutes = ReadingTimeEstimator.totalMinutes(
                forChapters: book.chapters.map(\.content)
            )
            storedBook.cachedReadingMinutes = Int(totalMinutes.rounded())
            modelContext.insert(storedBook)
            try modelContext.save()

            // Select the new book
            appState.selectedBookId = bookId

            // Surface in macOS Spotlight so the user can re-open the
            // book from anywhere; activation handled in CruxApp via
            // onContinueUserActivity.
            await SpotlightIndexer.shared.indexBook(storedBook)

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
                let totalMinutes = ReadingTimeEstimator.totalMinutes(
                    forChapters: book.chapters.map(\.content)
                )
                storedBook.cachedReadingMinutes = Int(totalMinutes.rounded())
                modelContext.insert(storedBook)
            }

            if !storedIds.isEmpty {
                try? modelContext.save()
            }

            // Reconcile Spotlight against the current library — covers
            // both the orphan-recovery path and any deletions that
            // happened with the app offline. Cheap (single batch
            // upsert + targeted deletes) so we run it on every launch.
            await reconcileSpotlightIndex()
        } catch {
            // Silent failure - recovery is best-effort
        }
    }

    /// Bring the Spotlight index in line with the current SwiftData
    /// library. Idempotent: `indexSearchableItems` upserts, so a re-run
    /// is harmless.
    func reconcileSpotlightIndex() async {
        await SpotlightIndexer.shared.indexBooks(storedBooks)
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
