import SwiftUI

struct KeyboardShortcutsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Library Section
                    ShortcutSection(title: "Library", shortcuts: [
                        ShortcutItem(key: "⌘O", description: "Open EPUB file"),
                        ShortcutItem(key: "⌘,", description: "Open Settings")
                    ])

                    // Reading Section
                    ShortcutSection(title: "Reading", shortcuts: [
                        ShortcutItem(key: "⌘F", description: "Find in book"),
                        ShortcutItem(key: "⌘T", description: "Toggle table of contents"),
                        ShortcutItem(key: "⌘B", description: "Toggle bookmarks"),
                        ShortcutItem(key: "⌘H", description: "Toggle highlights"),
                        ShortcutItem(key: "Left Arrow", description: "Previous page"),
                        ShortcutItem(key: "Right Arrow", description: "Next page"),
                        ShortcutItem(key: "⌘[", description: "Previous chapter"),
                        ShortcutItem(key: "⌘]", description: "Next chapter")
                    ])

                    // Search Section
                    ShortcutSection(title: "Search", shortcuts: [
                        ShortcutItem(key: "⌘↑", description: "Previous search result"),
                        ShortcutItem(key: "⌘↓", description: "Next search result"),
                        ShortcutItem(key: "Esc", description: "Close search")
                    ])

                    // Annotations Section
                    ShortcutSection(title: "Annotations", shortcuts: [
                        ShortcutItem(key: "⌘N", description: "Add note to selection"),
                        ShortcutItem(key: "⌘⇧H", description: "Highlight selection"),
                        ShortcutItem(key: "⌘⇧A", description: "Ask AI about selection")
                    ])

                    // Window Management
                    ShortcutSection(title: "Window Management", shortcuts: [
                        ShortcutItem(key: "⌘W", description: "Close window"),
                        ShortcutItem(key: "⌘M", description: "Minimize window")
                    ])
                }
                .padding(24)
            }
            .navigationTitle("Keyboard Shortcuts")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 600, height: 500)
    }
}

struct ShortcutSection: View {
    let title: String
    let shortcuts: [ShortcutItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            VStack(spacing: 8) {
                ForEach(shortcuts) { shortcut in
                    HStack(spacing: 16) {
                        // Key combination
                        Text(shortcut.key)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 120, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(6)

                        // Description
                        Text(shortcut.description)
                            .font(.body)
                            .foregroundStyle(.primary)

                        Spacer()
                    }
                }
            }
        }
    }
}

struct ShortcutItem: Identifiable {
    let id = UUID()
    let key: String
    let description: String
}

#Preview {
    KeyboardShortcutsView()
}
