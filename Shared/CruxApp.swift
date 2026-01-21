import SwiftUI
import SwiftData

@main
struct CruxApp: App {
    let modelContainer: ModelContainer
    @State private var appState = AppState()
    @State private var providerManager = AIProviderManager()
    @Environment(\.openWindow) private var openWindow

    init() {
        do {
            // Initialize SwiftData container with all models
            modelContainer = try ModelContainer(
                for: StoredBook.self,
                    AppSettings.self,
                    AIProviderConfig.self,
                    ReadingSession.self
            )
        } catch {
            fatalError("Failed to initialize SwiftData: \(error)")
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
        }
        .modelContainer(modelContainer)
        #if os(macOS)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open EPUB...") {
                    appState.showOpenPanel = true
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(replacing: .help) {
                Button("Reading Statistics") {
                    openWindow(id: "statistics")
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

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

        // Keyboard shortcuts window
        WindowGroup(id: "keyboard-shortcuts", for: Bool.self) { _ in
            KeyboardShortcutsView()
        }
        .defaultSize(width: 600, height: 500)
        .commandsRemoved()
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
    var selectedBookId: UUID?
}
