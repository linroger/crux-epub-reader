import SwiftUI
import SwiftData

#if os(macOS)

/// Standalone "book reader" scene that opens a single book in its own
/// window. Triggered from the library's context menu via:
/// `openWindow(id: "book-reader", value: bookId)`.
///
/// Each window holds its own ReaderView state (highlighted text, AI
/// thread, etc) so users can read two books side-by-side without one
/// stealing the other's selection or annotation.
struct BookWindowContent: View {
    let bookId: UUID

    @Environment(\.modelContext) private var modelContext
    @Query private var storedBooks: [StoredBook]
    @State private var book: Book?
    @State private var loadError: String?

    private let parser = EPUBParser()
    private let storage = BookStorage.shared

    var body: some View {
        Group {
            if let book {
                ReaderView(book: book, bookId: bookId)
            } else if let loadError {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.orange)
                    Text("Couldn't open book")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text(loadError)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                }
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Opening book…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: bookId) {
            await loadBook()
        }
    }

    private func loadBook() async {
        do {
            // Make sure SwiftData has a record for this book so per-book
            // settings (last position, status) survive across sessions.
            if !storedBooks.contains(where: { $0.id == bookId }) {
                loadError = "This book isn't in your library."
                return
            }
            let url = await storage.bookURL(for: bookId)
            let parsed = try await parser.parse(url: url)
            book = parsed
            // Mark the book as opened so the library reflects the action
            // even when launched from a context menu.
            if let stored = storedBooks.first(where: { $0.id == bookId }) {
                stored.markOpened()
                try? modelContext.save()
            }
        } catch {
            loadError = error.localizedDescription
        }
    }
}

#endif
