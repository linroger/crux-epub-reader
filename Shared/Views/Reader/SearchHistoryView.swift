import SwiftUI

/// View showing recent search history with suggestions
struct SearchHistoryView: View {
    let searches: [SearchHistoryItem]
    let onSelectSearch: (String) -> Void
    let onDeleteSearch: (SearchHistoryItem) -> Void
    let onClearAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !searches.isEmpty {
                // Header
                HStack {
                    Text("Recent Searches")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Spacer()

                    Button("Clear All") {
                        onClearAll()
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                // Search items
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(searches) { item in
                            searchItemRow(item)
                        }
                    }
                }
            } else {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)

                    Text("No Recent Searches")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Text("Your search history will appear here")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
        .frame(maxHeight: 300)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
    }

    @ViewBuilder
    private func searchItemRow(_ item: SearchHistoryItem) -> some View {
        HStack(spacing: 12) {
            // Search icon
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
                .font(.caption)

            // Query text
            VStack(alignment: .leading, spacing: 2) {
                Text(item.query)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(item.timestamp, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if item.resultCount > 0 {
                        Text("•")
                            .foregroundStyle(.tertiary)
                            .font(.caption2)

                        Text("\(item.resultCount) \(item.resultCount == 1 ? "result" : "results")")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            // Delete button
            Button {
                onDeleteSearch(item)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .opacity(0.6)
            .hoverEffect()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectSearch(item.query)
        }
        .hoverEffect()
    }
}

// MARK: - Hover Effect Modifier

private extension View {
    func hoverEffect() -> some View {
        #if os(macOS)
        self.onHover { isHovered in
            if isHovered {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        #else
        self
        #endif
    }
}

#Preview {
    let sampleSearches = [
        SearchHistoryItem(query: "French Revolution", resultCount: 12),
        SearchHistoryItem(query: "Liberty, equality, fraternity", resultCount: 3),
        SearchHistoryItem(query: "wine-shop", resultCount: 1),
        SearchHistoryItem(query: "Madame Defarge", resultCount: 8),
        SearchHistoryItem(query: "guillotine", resultCount: 5)
    ]

    return SearchHistoryView(
        searches: sampleSearches,
        onSelectSearch: { query in
            print("Selected: \(query)")
        },
        onDeleteSearch: { item in
            print("Delete: \(item.query)")
        },
        onClearAll: {
            print("Clear all")
        }
    )
    .frame(width: 300)
    .padding()
}
