import SwiftUI
import SwiftData

/// Settings pane that lets users pick an AI prompt preset (Scholarly,
/// Casual, Socratic, …) or write their own. The active preset is stored
/// in `AppSettings.activePromptPresetId`; custom text in `customSystemPrompt`.
struct AIPromptSettingsView: View {
    @Query private var settings: [AppSettings]
    @Environment(\.modelContext) private var modelContext

    @State private var selectedPreset: AIPromptPreset = .scholarly
    @State private var customText: String = ""

    private var appSettings: AppSettings {
        if let existing = settings.first { return existing }
        let new = AppSettings.createDefault()
        modelContext.insert(new)
        try? modelContext.save()
        return new
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                Label("AI System Prompt", systemImage: "text.alignleft")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Choose how the AI annotates your highlights. Switch presets at any time, or pick **Custom** to write your own voice.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Preset list
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(AIPromptPreset.allCases) { preset in
                        PromptPresetRow(
                            preset: preset,
                            isSelected: selectedPreset == preset
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedPreset = preset
                            persist()
                        }
                    }
                }
            }
            .frame(maxHeight: 240)

            Divider()

            // Custom prompt editor — visible at all times so users see what
            // they'd be activating if they switched to "Custom".
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Custom Prompt")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    if selectedPreset == .custom {
                        Text("(active)")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Text("— activate by selecting **Custom** above")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Menu {
                        ForEach(AIPromptPreset.allCases.filter { $0 != .custom }) { preset in
                            Button("Use \(preset.displayName) as starting point") {
                                customText = preset.systemPrompt
                                persist()
                            }
                        }
                    } label: {
                        Label("Templates", systemImage: "doc.on.doc")
                    }
                    .menuStyle(.borderlessButton)
                    .controlSize(.small)
                    .fixedSize()
                }

                TextEditor(text: $customText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(Color.cruxTextBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .onChange(of: customText) { _, _ in persist() }

                if customText.isEmpty && selectedPreset == .custom {
                    Label("Provide instructions for the AI before activating this preset.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(20)
        .onAppear { loadFromSettings() }
    }

    // MARK: - Persistence

    private func loadFromSettings() {
        selectedPreset = AIPromptPreset(rawValue: appSettings.activePromptPresetId) ?? .scholarly
        customText = appSettings.customSystemPrompt
    }

    private func persist() {
        appSettings.activePromptPresetId = selectedPreset.id
        appSettings.customSystemPrompt = customText
        try? modelContext.save()
    }
}

// MARK: - Row

private struct PromptPresetRow: View {
    let preset: AIPromptPreset
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: preset.symbolName)
                .font(.system(size: 16, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(preset.displayName)
                    .font(.subheadline.weight(.semibold))
                Text(preset.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            // Selection indicator — keeps a quiet check rather than a colored
            // pill so the row reads cleanly in both light and dark modes.
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary.opacity(0.4)))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .cruxGlassCard(cornerRadius: 10, interactive: true)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(preset.displayName) preset")
        .accessibilityHint(preset.subtitle)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
