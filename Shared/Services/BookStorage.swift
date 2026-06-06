import Foundation

/// Errors thrown by `BookStorage`. Distinguishing these from generic
/// `Foundation` errors lets the import UI show actionable messages
/// instead of "Operation failed because file already exists."
enum BookStorageError: LocalizedError {
    case insufficientDiskSpace(needed: Int64, available: Int64)
    case sourceNotReadable(URL)
    case copyFailed(URL, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .insufficientDiskSpace(let needed, let available):
            return "Not enough disk space — need \(formatBytes(needed)), have \(formatBytes(available))."
        case .sourceNotReadable(let url):
            return "Can't read \(url.lastPathComponent). Check sandbox/file permissions."
        case .copyFailed(let url, let underlying):
            return "Couldn't import \(url.lastPathComponent): \(underlying.localizedDescription)"
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

actor BookStorage {
    static let shared = BookStorage()

    private let fileManager = FileManager.default
    private let booksDirectory: URL
    private let annotationsDirectory: URL

    private init() {
        // The documents directory is always present on Apple platforms, but
        // fall back to the (always-available) temporary directory rather than
        // force-unwrapping and crashing the app on launch in the rare event
        // it can't be resolved.
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        booksDirectory = docs.appendingPathComponent("Books", isDirectory: true)
        annotationsDirectory = docs.appendingPathComponent("Annotations", isDirectory: true)

        // Ensure directories exist
        try? FileManager.default.createDirectory(at: booksDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: annotationsDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Book Storage

    /// Copies an EPUB file into the app's managed storage
    /// Returns the new URL and a generated UUID for the book
    func importBook(from sourceURL: URL) throws -> (storedURL: URL, bookId: UUID) {
        let bookId = UUID()
        let destinationURL = booksDirectory.appendingPathComponent("\(bookId.uuidString).epub")

        // Start accessing security-scoped resource if needed
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        // Pre-check disk space so we fail with a useful message
        // rather than mid-copy with an "operation could not be
        // completed" error. The safety margin (16 MB) handles
        // FS metadata + bookkeeping; SwiftData and the annotations
        // file both write into the same volume.
        let sourceSize = try fileSize(of: sourceURL)
        let available = freeBytes(at: booksDirectory)
        let needed = sourceSize + 16 * 1024 * 1024
        if available < needed {
            AppLog.storage.error("Refusing import: need \(needed), have \(available)")
            throw BookStorageError.insufficientDiskSpace(needed: needed, available: available)
        }

        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            AppLog.storage.error("Import copy failed: \(error.localizedDescription, privacy: .public)")
            // Clean up a partial destination so the next attempt
            // doesn't trip on "file already exists".
            try? fileManager.removeItem(at: destinationURL)
            throw BookStorageError.copyFailed(sourceURL, underlying: error)
        }
        return (destinationURL, bookId)
    }

    /// Size of a file in bytes, falling back to 0 if the attributes
    /// can't be read (best-effort — used for the import pre-check).
    private func fileSize(of url: URL) throws -> Int64 {
        let attrs = try fileManager.attributesOfItem(atPath: url.path)
        return (attrs[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// Bytes available on the volume backing `url`. Used to decide
    /// whether an import has any hope of succeeding before we start
    /// shoveling bits around.
    private func freeBytes(at url: URL) -> Int64 {
        do {
            let attrs = try fileManager.attributesOfFileSystem(forPath: url.path)
            return (attrs[.systemFreeSize] as? NSNumber)?.int64Value ?? .max
        } catch {
            // Couldn't measure — proceed and let the copy fail
            // naturally rather than block the user on a bad probe.
            return .max
        }
    }

    /// Returns the stored URL for a book by ID
    func bookURL(for bookId: UUID) -> URL {
        booksDirectory.appendingPathComponent("\(bookId.uuidString).epub")
    }

    /// Checks if a book exists in storage
    func bookExists(_ bookId: UUID) -> Bool {
        fileManager.fileExists(atPath: bookURL(for: bookId).path)
    }

    /// Removes a book from storage
    func removeBook(_ bookId: UUID) throws {
        let url = bookURL(for: bookId)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        // Also remove annotations
        try? removeAnnotations(for: bookId)
    }

    /// Lists all stored book IDs
    func listStoredBookIds() throws -> [UUID] {
        let contents = try fileManager.contentsOfDirectory(at: booksDirectory, includingPropertiesForKeys: nil)
        return contents.compactMap { url -> UUID? in
            guard url.pathExtension == "epub" else { return nil }
            return UUID(uuidString: url.deletingPathExtension().lastPathComponent)
        }
    }

    // MARK: - Annotations Storage

    func annotationsURL(for bookId: UUID) -> URL {
        annotationsDirectory.appendingPathComponent("\(bookId.uuidString).json")
    }

    /// Backup suffix used to keep the last-known-good annotation JSON next
    /// to the live file. We keep exactly one rolling backup — enough to
    /// recover from a single bad write without growing unbounded.
    private static let backupExtension = "json.bak"

    func loadAnnotations(for bookId: UUID) throws -> BookAnnotations {
        let url = annotationsURL(for: bookId)
        guard fileManager.fileExists(atPath: url.path) else {
            // Live file missing — see if the backup is salvageable before
            // returning an empty default. This rescues users from the
            // worst case of a partial-write crash.
            let backupURL = backupAnnotationsURL(for: bookId)
            if fileManager.fileExists(atPath: backupURL.path),
               let recovered = try? decodeAnnotations(from: backupURL) {
                AppLog.storage.notice("Recovered annotations for book \(bookId.uuidString, privacy: .public) from backup")
                return recovered
            }
            return BookAnnotations(bookId: bookId)
        }
        do {
            return try decodeAnnotations(from: url)
        } catch {
            // Live file corrupted — fall back to backup if available.
            AppLog.storage.error("Failed to decode annotations for \(bookId.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            let backupURL = backupAnnotationsURL(for: bookId)
            if fileManager.fileExists(atPath: backupURL.path),
               let recovered = try? decodeAnnotations(from: backupURL) {
                AppLog.storage.notice("Recovered from backup after live decode failure")
                return recovered
            }
            throw error
        }
    }

    /// Writes annotations atomically with a one-revision rollback file.
    ///
    /// Flow:
    ///   1. Write the new payload to `<id>.json.tmp`.
    ///   2. If the live `<id>.json` already exists, move it to
    ///      `<id>.json.bak` (overwriting any older backup).
    ///   3. Move `.tmp` into place.
    /// A crash between steps 2 and 3 leaves us with the backup, so a
    /// follow-up `loadAnnotations` can recover.
    func saveAnnotations(_ annotations: BookAnnotations) throws {
        let url = annotationsURL(for: annotations.bookId)
        let backupURL = backupAnnotationsURL(for: annotations.bookId)
        let tempURL = url.appendingPathExtension("tmp")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(annotations)

        // Step 1: write to temp.
        try data.write(to: tempURL, options: .atomic)

        // Step 2: rotate live → backup.
        if fileManager.fileExists(atPath: url.path) {
            if fileManager.fileExists(atPath: backupURL.path) {
                try? fileManager.removeItem(at: backupURL)
            }
            try? fileManager.moveItem(at: url, to: backupURL)
        }

        // Step 3: temp → live.
        do {
            try fileManager.moveItem(at: tempURL, to: url)
        } catch {
            // If the live move fails, try to recover the backup so we
            // don't leave the user with no live file at all.
            if fileManager.fileExists(atPath: backupURL.path),
               !fileManager.fileExists(atPath: url.path) {
                try? fileManager.moveItem(at: backupURL, to: url)
            }
            try? fileManager.removeItem(at: tempURL)
            throw error
        }
    }

    /// Decode an annotations JSON file from a URL using our shared decoder.
    private func decodeAnnotations(from url: URL) throws -> BookAnnotations {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BookAnnotations.self, from: data)
    }

    private func backupAnnotationsURL(for bookId: UUID) -> URL {
        annotationsDirectory.appendingPathComponent("\(bookId.uuidString).\(Self.backupExtension)")
    }

    func removeAnnotations(for bookId: UUID) throws {
        let url = annotationsURL(for: bookId)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        // Also delete the rolling backup so the directory doesn't grow
        // with orphaned `.bak` files after book removals.
        let backupURL = backupAnnotationsURL(for: bookId)
        if fileManager.fileExists(atPath: backupURL.path) {
            try? fileManager.removeItem(at: backupURL)
        }
    }

    // MARK: - Annotation Stats

    func loadAnnotationStats(for bookId: UUID) -> AnnotationStats {
        let url = annotationsURL(for: bookId)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return AnnotationStats(highlightCount: 0, threadCount: 0)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let annotations = try? decoder.decode(BookAnnotations.self, from: data) else {
            return AnnotationStats(highlightCount: 0, threadCount: 0)
        }

        let highlightCount = annotations.highlights.count
        let threadCount = annotations.highlights.reduce(0) { $0 + $1.threads.count }

        return AnnotationStats(highlightCount: highlightCount, threadCount: threadCount)
    }
}

struct AnnotationStats {
    let highlightCount: Int
    let threadCount: Int
}
