import SwiftUI

/// View for selecting category and tags for annotations
struct CategoryTagSelector: View {
    @Binding var category: AnnotationCategory
    @Binding var tags: [String]

    let tagService: TagManagementService
    let suggestedTags: [String]

    @State private var newTagInput = ""
    @State private var showingTagSuggestions = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Category Picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Category")
                    .font(.subheadline)
                    .fontWeight(.medium)

                categoryPicker
            }

            // Tags Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Tags")
                    .font(.subheadline)
                    .fontWeight(.medium)

                // Existing tags
                if !tags.isEmpty {
                    tagChips
                }

                // Tag input
                tagInput

                // Tag suggestions
                if !suggestedTags.isEmpty && (isInputFocused || !newTagInput.isEmpty) {
                    tagSuggestions
                }
            }
        }
        .padding()
    }

    // MARK: - Category Picker

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(AnnotationCategory.allCases) { cat in
                    CategoryButton(
                        category: cat,
                        isSelected: category == cat
                    ) {
                        category = cat
                    }
                }
            }
        }
    }

    // MARK: - Tag Chips

    private var tagChips: some View {
        FlowLayout(spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                TagChip(
                    tag: tag,
                    onRemove: {
                        tags.removeAll { $0 == tag }
                    }
                )
            }
        }
    }

    // MARK: - Tag Input

    private var tagInput: some View {
        HStack(spacing: 8) {
            Image(systemName: "tag")
                .foregroundStyle(.secondary)

            TextField("Add tag...", text: $newTagInput)
                .textFieldStyle(.plain)
                .focused($isInputFocused)
                .onSubmit {
                    addTag()
                }

            if !newTagInput.isEmpty {
                Button {
                    addTag()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary)
        .cornerRadius(8)
    }

    // MARK: - Tag Suggestions

    private var tagSuggestions: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Suggestions")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(filteredSuggestions, id: \.self) { suggestion in
                        Button {
                            addSuggestedTag(suggestion)
                        } label: {
                            HStack(spacing: 4) {
                                Text(suggestion)
                                    .font(.caption)
                                Image(systemName: "plus.circle")
                                    .font(.caption2)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var filteredSuggestions: [String] {
        let normalized = tagService.normalizeTag(newTagInput)
        return suggestedTags.filter { suggestion in
            !tags.contains(suggestion) &&
            (normalized.isEmpty || suggestion.lowercased().contains(normalized))
        }
    }

    // MARK: - Actions

    private func addTag() {
        let normalized = tagService.normalizeTag(newTagInput)
        guard tagService.isValidTag(normalized),
              !tags.contains(normalized) else {
            newTagInput = ""
            return
        }

        tags.append(normalized)
        tagService.markTagAsUsed(normalized)
        newTagInput = ""
    }

    private func addSuggestedTag(_ tag: String) {
        guard !tags.contains(tag) else { return }
        tags.append(tag)
        tagService.markTagAsUsed(tag)
        newTagInput = ""
    }
}

// MARK: - Category Button

struct CategoryButton: View {
    let category: AnnotationCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.title2)
                    .foregroundStyle(
                        isSelected ?
                        Color(hex: category.color) ?? .blue :
                        Color.secondary
                    )

                Text(category.rawValue)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .frame(width: 70, height: 70)
            .background(
                isSelected ?
                (Color(hex: category.color) ?? .blue).opacity(0.15) :
                Color.clear
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isSelected ?
                        (Color(hex: category.color) ?? .blue) :
                        Color.secondary.opacity(0.2),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tag Chip

struct TagChip: View {
    let tag: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.caption)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary)
        .cornerRadius(6)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var category: AnnotationCategory = .quote
        @State private var tags: [String] = ["important", "chapter1"]
        let tagService = TagManagementService()

        var body: some View {
            CategoryTagSelector(
                category: $category,
                tags: $tags,
                tagService: tagService,
                suggestedTags: ["philosophy", "key-concept", "definition", "example"]
            )
            .frame(maxWidth: 400)
        }
    }

    return PreviewWrapper()
}
