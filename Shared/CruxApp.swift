import SwiftUI
import SwiftData
import CoreSpotlight

@main
struct CruxApp: App {
    let modelContainer: ModelContainer
    @State private var appState = AppState()
    @State private var providerManager = AIProviderManager()
    @Environment(\.openWindow) private var openWindow

    init() {
        let schema = Schema([
            StoredBook.self,
            BookCollection.self,
            AppSettings.self,
            AIProviderConfig.self,
            ReadingSession.self,
            ReadingGoal.self,
            GoalAchievement.self,
            ReadingStreak.self,
            Achievement.self,
            SearchHistoryItem.self
        ])
        modelContainer = Self.makeModelContainer(schema: schema)
    }

    /// Builds the SwiftData container, recovering from a corrupt or
    /// schema-incompatible on-disk store rather than bricking the app.
    ///
    /// If the store can't be opened (common after an OS/app upgrade that
    /// changes the schema, or after SQLite corruption), we move the failed
    /// store aside and start fresh. This only loses SwiftData *metadata*
    /// (reading progress, collections, settings) — the imported EPUB files
    /// and the annotation JSON live outside SwiftData and are re-imported by
    /// `recoverOrphanedBooks()` on the next launch, so the user's library and
    /// highlights survive. A second failure is genuinely unrecoverable.
    private static func makeModelContainer(schema: Schema) -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema)
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            AppLog.storage.error("SwiftData init failed: \(error.localizedDescription, privacy: .public). Resetting store and retrying.")
            resetStore(at: configuration.url)
            do {
                return try ModelContainer(for: schema, configurations: configuration)
            } catch {
                fatalError("Failed to initialize SwiftData after store reset: \(error)")
            }
        }
    }

    /// Removes a SQLite-backed SwiftData store and its `-wal`/`-shm` sidecar
    /// files so a fresh container can be created in its place.
    private static func resetStore(at storeURL: URL) {
        let fileManager = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: storeURL.path + suffix)
            try? fileManager.removeItem(at: sidecar)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(providerManager)
                .task {
                    // Initialize provider manager with model context
                    let context = modelContainer.mainContext
                    providerManager.initialize(modelContext: context)

                    // Migrate legacy API key if needed
                    try? providerManager.migrateFromLegacySettings()
                }
                // Spotlight result selection — the user picked a Crux
                // book in macOS Spotlight (or via Handoff). The unique
                // identifier we set when indexing is the StoredBook UUID;
                // funnel it through AppState so ContentView's selection
                // binding picks it up.
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    if let uuidString = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                       let id = UUID(uuidString: uuidString) {
                        appState.selectedBookId = id
                    }
                }
                // Direct-open path used when the in-app advertised
                // activity (e.g. recently active book) is selected from
                // the System window menu / "Open Recent" surfaces.
                .onContinueUserActivity(SpotlightIndexer.activityType) { activity in
                    if let uuidString = activity.userInfo?[SpotlightIndexer.userInfoBookIDKey] as? String,
                       let id = UUID(uuidString: uuidString) {
                        appState.selectedBookId = id
                    }
                }
        }
        .modelContainer(modelContainer)
        #if os(macOS)
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified)
        #endif
        #if os(macOS)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open EPUB...") {
                    appState.showOpenPanel = true
                }
                .keyboardShortcut("o", modifiers: .command)

                Divider()

                Button("Import Annotations…") {
                    appState.showImportNotesPanel = true
                }
                .help("Import a .cruxnotes bundle exported from another Crux library")
            }

            CommandGroup(replacing: .help) {
                Button("Reading Statistics") {
                    openWindow(id: "statistics")
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Button("Reading Goals") {
                    openWindow(id: "reading-goals")
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])

                Button("Streaks & Achievements") {
                    openWindow(id: "streaks")
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Button("Keyboard Shortcuts") {
                    openWindow(id: "keyboard-shortcuts", value: true)
                }
                .keyboardShortcut("/", modifiers: .command)
            }
        }
        #endif

        #if os(macOS)
        // Notes window
        WindowGroup(id: "notes") {
            NotesView()
                .modelContainer(modelContainer)
        }
        .defaultSize(width: 900, height: 600)

        // Statistics window
        WindowGroup(id: "statistics") {
            StatisticsView()
                .modelContainer(modelContainer)
        }
        .defaultSize(width: 700, height: 600)

        // Reading goals window
        WindowGroup(id: "reading-goals") {
            ReadingGoalsView()
                .modelContainer(modelContainer)
        }
        .defaultSize(width: 600, height: 500)

        // Streaks window
        WindowGroup(id: "streaks") {
            StreaksView()
                .modelContainer(modelContainer)
        }
        .defaultSize(width: 700, height: 600)

        // Keyboard shortcuts window
        WindowGroup(id: "keyboard-shortcuts", for: Bool.self) { _ in
            KeyboardShortcutsView()
        }
        .defaultSize(width: 600, height: 500)
        .commandsRemoved()

        // Dedicated book-reader window — opened via the library context
        // menu "Open in New Window" so users can read multiple books at
        // the same time without one window's selection clobbering the
        // other's annotation state.
        WindowGroup(id: "book-reader", for: UUID.self) { $bookId in
            if let bookId {
                BookWindowContent(bookId: bookId)
                    .environment(appState)
                    .environment(providerManager)
            } else {
                Text("No book")
                    .foregroundStyle(.secondary)
            }
        }
        .defaultSize(width: 900, height: 700)
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(providerManager)
                .modelContainer(modelContainer)
        }
        #endif
    }
}

@Observable
final class AppState {
    var showOpenPanel = false
    /// Flips true when the user picks "File → Import Annotations…".
    /// `ContentView` watches this and runs the import flow on the
    /// main actor (file picker + decode + merge + save).
    var showImportNotesPanel = false
    var selectedBookId: UUID?
    var searchHistoryService = SearchHistoryService()
    var themeManager = ThemeManager()
    var tagManagementService = TagManagementService()
    // var ttsService = TextToSpeechService() // Temporarily disabled due to MLX dependency issues
}
