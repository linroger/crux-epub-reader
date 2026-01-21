import SwiftUI

/// View for filtering annotations by category and tags
struct AnnotationFilterView: View {
    @Binding var selectedCategories: Set<AnnotationCategory>
    @Binding var selectedTags: Set<String>
    @Binding var showOnlyWithNotes: Bool

    let categoryStats: [AnnotationCategory: Int]
    let tagStats: [String: Int]

    @State private var showCategoryFilter = true
    @State private var showTagFilter = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Filter Header
                HStack {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.title2)
                        .foregroundStyle(.blue)

                    Text("Filter Annotations")
                        .font(.headline)

                    Spacer()

                    if hasActiveFilters {
                        Button("Clear All") {
                            clearFilters()
                        }
                        .font(.caption)
                        .foregroundStyle(.blue)
                    }
                }
                .padding(.bottom, 8)

                // Options Section
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Only show annotations with notes", isOn: $showOnlyWithNotes)
                        .font(.subheadline)
                }

                Divider()

                // Category Filter
                DisclosureGroup(
                    isExpanded: $showCategoryFilter
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(sortedCategories, id: \.category) { item in
                            CategoryFilterRow(
                                category: item.category,
                                count: item.count,
                                isSelected: selectedCategories.contains(item.category)
                            ) {
                                toggleCategory(item.category)
                            }
                        }

                        if !categoryStats.isEmpty {
                            Button(selectedCategories.isEmpty ? "Select All" : "Deselect All") {
                                if selectedCategories.isEmpty {
                                    selectedCategories = Set(categoryStats.keys)
                                } else {
                                    selectedCategories.removeAll()
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.blue)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    HStack {
                        Image(systemName: "square.grid.2x2")
                        Text("Category")
                            .fontWeight(.medium)

                        Spacer()

                        if !selectedCategories.isEmpty {
                            Text("\(selectedCategories.count)")
                                .font(.caption)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(.blue)
                                .cornerRadius(10)
                        }
                    }
                }

                Divider()

                // Tag Filter
                DisclosureGroup(
                    isExpanded: $showTagFilter
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        if sortedTags.isEmpty {
                            Text("No tags yet")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                        } else {
                            ForEach(sortedTags, id: \.tag) { item in
                                TagFilterRow(
                                    tag: item.tag,
                                    count: item.count,
                                    isSelected: selectedTags.contains(item.tag)
                                ) {
                                    toggleTag(item.tag)
                                }
                            }

                            Button(selectedTags.isEmpty ? "Select All" : "Deselect All") {
                                if selectedTags.isEmpty {
                                    selectedTags = Set(tagStats.keys)
                                } else {
                                    selectedTags.removeAll()
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.blue)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    HStack {
                        Image(systemName: "tag")
                        Text("Tags")
                            .fontWeight(.medium)

                        Spacer()

                        if !selectedTags.isEmpty {
                            Text("\(selectedTags.count)")
                                .font(.caption)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(.blue)
                                .cornerRadius(10)
                        }
                    }
                }
            }
            .padding()
        }
        .frame(minWidth: 280)
    }

    // MARK: - Computed Properties

    private var hasActiveFilters: Bool {
        !selectedCategories.isEmpty || !selectedTags.isEmpty || showOnlyWithNotes
    }

    private var sortedCategories: [(category: AnnotationCategory, count: Int)] {
        categoryStats
            .map { ($0.key, $0.value) }
            .sorted { $0.count > $1.count }
    }

    private var sortedTags: [(tag: String, count: Int)] {
        tagStats
            .map { ($0.key, $0.value) }
            .sorted { $0.count > $1.count }
    }

    // MARK: - Actions

    private func toggleCategory(_ category: AnnotationCategory) {
        if selectedCategories.contains(category) {
            selectedCategories.remove(category)
        } else {
            selectedCategories.insert(category)
        }
    }

    private func toggleTag(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }

    private func clearFilters() {
        selectedCategories.removeAll()
        selectedTags.removeAll()
        showOnlyWithNotes = false
    }
}

// MARK: - Category Filter Row

struct CategoryFilterRow: View {
    let category: AnnotationCategory
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Checkbox
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .font(.title3)

                // Category icon and name
                HStack(spacing: 8) {
                    Image(systemName: category.icon)
                        .foregroundStyle(Color(hex: category.color) ?? .blue)
                        .frame(width: 20)

                    Text(category.rawValue)
                        .font(.subheadline)

                    Spacer()

                    // Count badge
                    Text("\(count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .cornerRadius(10)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tag Filter Row

struct TagFilterRow: View {
    let tag: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Checkbox
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .font(.title3)

                // Tag name
                HStack {
                    Image(systemName: "tag.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(tag)
                        .font(.subheadline)

                    Spacer()

                    // Count badge
                    Text("\(count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .cornerRadius(10)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var selectedCategories: Set<AnnotationCategory> = [.quote, .important]
        @State private var selectedTags: Set<String> = ["philosophy"]
        @State private var showOnlyWithNotes = false

        var body: some View {
            AnnotationFilterView(
                selectedCategories: $selectedCategories,
                selectedTags: $selectedTags,
                showOnlyWithNotes: $showOnlyWithNotes,
                categoryStats: [
                    .quote: 12,
                    .analysis: 5,
                    .important: 8,
                    .question: 3
                ],
                tagStats: [
                    "philosophy": 10,
                    "key-concept": 7,
                    "chapter1": 15
                ]
            )
            .frame(width: 300, height: 600)
        }
    }

    return PreviewWrapper()
}
