import SwiftUI
import SwiftData

struct CollectionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \BookCollection.sortOrder) private var collections: [BookCollection]

    @State private var showingAddCollection = false
    @State private var editingCollection: BookCollection?
    @State private var collectionToDelete: BookCollection?

    var body: some View {
        NavigationStack {
            Group {
                if collections.isEmpty {
                    ContentUnavailableView(
                        "No Collections",
                        systemImage: "folder",
                        description: Text("Create collections to organize your books")
                    )
                } else {
                    List {
                        ForEach(collections) { collection in
                            CollectionRow(
                                collection: collection,
                                onEdit: {
                                    editingCollection = collection
                                },
                                onDelete: {
                                    collectionToDelete = collection
                                }
                            )
                        }
                        .onMove(perform: moveCollections)
                    }
                    .listStyle(.inset)
                }
            }
            .navigationTitle("Collections")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddCollection = true
                    } label: {
                        Label("New Collection", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddCollection) {
                EditCollectionSheet(collection: nil, mode: .create) { newCollection in
                    modelContext.insert(newCollection)
                    try? modelContext.save()
                }
            }
            .sheet(item: $editingCollection) { collection in
                EditCollectionSheet(collection: collection, mode: .edit) { editedCollection in
                    collection.name = editedCollection.name
                    collection.colorHex = editedCollection.colorHex
                    collection.icon = editedCollection.icon
                    try? modelContext.save()
                }
            }
            .alert("Delete Collection", isPresented: .constant(collectionToDelete != nil)) {
                Button("Cancel", role: .cancel) {
                    collectionToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let collection = collectionToDelete {
                        deleteCollection(collection)
                    }
                }
            } message: {
                if let collection = collectionToDelete {
                    Text("Are you sure you want to delete \"\(collection.name)\"? Books will not be deleted, only removed from this collection.")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 400)
        #endif
    }

    private func moveCollections(from source: IndexSet, to destination: Int) {
        var reorderedCollections = collections
        reorderedCollections.move(fromOffsets: source, toOffset: destination)

        // Update sort order
        for (index, collection) in reorderedCollections.enumerated() {
            collection.sortOrder = index
        }

        try? modelContext.save()
    }

    private func deleteCollection(_ collection: BookCollection) {
        modelContext.delete(collection)
        try? modelContext.save()
        collectionToDelete = nil
    }
}

struct CollectionRow: View {
    let collection: BookCollection
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    private var color: Color {
        Color(hex: collection.colorHex) ?? .blue
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon with color
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.3), color.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)

                Image(systemName: collection.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(color)
            }

            // Collection info
            VStack(alignment: .leading, spacing: 4) {
                Text(collection.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)

                Text("\(collection.bookCount) \(collection.bookCount == 1 ? "book" : "books")")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Action buttons (show on hover)
            if isHovering {
                HStack(spacing: 8) {
                    Button {
                        onEdit()
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Edit collection")

                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Delete collection")
                }
                .padding(.horizontal, 8)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Edit Collection Sheet

enum CollectionEditMode {
    case create
    case edit
}

struct EditCollectionSheet: View {
    let collection: BookCollection?
    let mode: CollectionEditMode
    let onSave: (BookCollection) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var selectedColor: String
    @State private var selectedIcon: String

    init(collection: BookCollection?, mode: CollectionEditMode, onSave: @escaping (BookCollection) -> Void) {
        self.collection = collection
        self.mode = mode
        self.onSave = onSave

        _name = State(initialValue: collection?.name ?? "")
        _selectedColor = State(initialValue: collection?.colorHex ?? "007AFF")
        _selectedIcon = State(initialValue: collection?.icon ?? "folder.fill")
    }

    private let predefinedColors: [(name: String, hex: String)] = [
        ("Blue", "007AFF"),
        ("Purple", "AF52DE"),
        ("Pink", "FF2D55"),
        ("Red", "FF3B30"),
        ("Orange", "FF9500"),
        ("Yellow", "FFCC00"),
        ("Green", "34C759"),
        ("Teal", "5AC8FA"),
        ("Indigo", "5856D6"),
        ("Brown", "A2845E")
    ]

    private let predefinedIcons = [
        "folder.fill",
        "book.fill",
        "books.vertical.fill",
        "star.fill",
        "heart.fill",
        "bookmark.fill",
        "tag.fill",
        "flag.fill",
        "archivebox.fill",
        "tray.fill",
        "folder.badge.person.crop",
        "graduationcap.fill",
        "briefcase.fill",
        "house.fill",
        "lightbulb.fill"
    ]

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Collection Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(predefinedColors, id: \.hex) { colorOption in
                            Button {
                                selectedColor = colorOption.hex
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: colorOption.hex) ?? .blue)
                                        .frame(width: 44, height: 44)

                                    if selectedColor == colorOption.hex {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .help(colorOption.name)
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(predefinedIcons, id: \.self) { icon in
                            Button {
                                selectedIcon = icon
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(selectedIcon == icon ? Color(hex: selectedColor)?.opacity(0.2) ?? .blue.opacity(0.2) : .clear)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(selectedIcon == icon ? Color(hex: selectedColor) ?? .blue : .clear, lineWidth: 2)
                                        }
                                        .frame(width: 44, height: 44)

                                    Image(systemName: icon)
                                        .font(.system(size: 20))
                                        .foregroundStyle(selectedIcon == icon ? Color(hex: selectedColor) ?? .blue : .secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section("Preview") {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [(Color(hex: selectedColor) ?? .blue).opacity(0.3), (Color(hex: selectedColor) ?? .blue).opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 40, height: 40)

                            Image(systemName: selectedIcon)
                                .font(.system(size: 18))
                                .foregroundStyle(Color(hex: selectedColor) ?? .blue)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(name.isEmpty ? "Collection Name" : name)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(name.isEmpty ? .secondary : .primary)

                            Text("0 books")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(mode == .create ? "New Collection" : "Edit Collection")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(mode == .create ? "Create" : "Save") {
                        saveCollection()
                    }
                    .disabled(!isValid)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 500)
        #endif
    }

    private func saveCollection() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        if mode == .create {
            let newCollection = BookCollection(
                name: trimmedName,
                colorHex: selectedColor,
                icon: selectedIcon
            )
            onSave(newCollection)
        } else if let collection = collection {
            let edited = BookCollection(
                id: collection.id,
                name: trimmedName,
                colorHex: selectedColor,
                icon: selectedIcon
            )
            onSave(edited)
        }

        dismiss()
    }
}

#Preview {
    CollectionsView()
        .modelContainer(for: BookCollection.self, inMemory: true)
}
