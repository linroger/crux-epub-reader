import SwiftUI
import SwiftData

/// Books-style "Aa" appearance panel for the reader: theme swatches, reading
/// font, text size, line spacing, and (macOS) page margins.
///
/// Every control writes straight into `AppSettings`; the reader's WebView
/// picks the change up through its `@Query` and swaps the page's custom
/// stylesheet in place (`WebViewCoordinator.applyCustomCSS`) — the page
/// restyles live, keeping the scroll position. Presented as a toolbar
/// popover on macOS and a detented sheet on iOS.
struct ReaderAppearanceView: View {
    @Query private var settings: [AppSettings]
    @Environment(\.modelContext) private var modelContext

    private var current: AppSettings? { settings.first }

    private var activeTheme: AppTheme {
        AppTheme(rawValue: current?.theme ?? "system") ?? .system
    }

    /// Swatch display order: reading themes first, System last.
    private static let themeOrder: [AppTheme] = [
        .light, .sepia, .dark, .night, .highContrast, .system
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // MARK: Theme
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Theme")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                          spacing: 8) {
                    ForEach(Self.themeOrder) { theme in
                        ThemeSwatch(theme: theme, isSelected: theme == activeTheme) {
                            select(theme: theme)
                        }
                    }
                }
            }

            Divider()

            // MARK: Font
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Font")
                Picker("Reading font", selection: fontBinding) {
                    ForEach(ReaderResources.readingFonts) { font in
                        Text(font.displayName).tag(font.storedValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityLabel("Reading font")
            }

            // MARK: Size
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Text Size")
                HStack(spacing: 0) {
                    sizeButton(symbol: "minus", delta: -1, label: "Decrease text size")
                    Spacer()
                    Text("\(Int(current?.fontSize ?? 16)) pt")
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Spacer()
                    sizeButton(symbol: "plus", delta: 1, label: "Increase text size")
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }

            // MARK: Line spacing
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    sectionLabel("Line Spacing")
                    Spacer()
                    Text(String(format: "%.2f×", current?.lineHeight ?? 1.6))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                Slider(value: doubleBinding(\.lineHeight, default: 1.6), in: 1.2...2.2, step: 0.05) {
                    Text("Line spacing")
                } minimumValueLabel: {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                } maximumValueLabel: {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
            }

            #if os(macOS)
            // MARK: Margins — macOS only; the iOS layout pins its own prose
            // padding for narrow screens (see reader.css).
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    sectionLabel("Margins")
                    Spacer()
                    Text("\(Int(current?.marginWidth ?? 60)) px")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                Slider(value: doubleBinding(\.marginWidth, default: 60), in: 0...160, step: 10) {
                    Text("Page margins")
                } minimumValueLabel: {
                    Image(systemName: "rectangle.compress.vertical")
                        .rotationEffect(.degrees(90))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                } maximumValueLabel: {
                    Image(systemName: "rectangle.expand.vertical")
                        .rotationEffect(.degrees(90))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            #endif

            Divider()

            Button {
                resetAppearance()
            } label: {
                Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("resetAppearance")
        }
        .padding(16)
        #if os(macOS)
        .frame(width: 300)
        #endif
    }

    // MARK: - Pieces

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func sizeButton(symbol: String, delta: Double, label: String) -> some View {
        Button {
            adjustFontSize(by: delta)
        } label: {
            Image(systemName: "textformat.size")
                .font(.system(size: delta < 0 ? 11 : 17, weight: .medium))
                .frame(width: 44, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(delta < 0 ? (current?.fontSize ?? 16) <= 10 : (current?.fontSize ?? 16) >= 32)
        .accessibilityLabel(label)
    }

    // MARK: - Mutations

    private func select(theme: AppTheme) {
        guard let current else { return }
        current.theme = theme.rawValue
        // Picking a theme is an explicit "use this palette" action, so it
        // also clears any custom page-color overrides from Settings —
        // otherwise an old hand-picked background would silently win over
        // every theme (see ReaderResources.generateCustomCSS).
        current.backgroundColor = theme.backgroundColor
        current.textColor = theme.textColor
        save()
    }

    private var fontBinding: Binding<String> {
        Binding(
            get: { current?.fontFamily ?? "System" },
            set: { newValue in
                current?.fontFamily = newValue
                save()
            }
        )
    }

    private func doubleBinding(_ keyPath: ReferenceWritableKeyPath<AppSettings, Double>,
                               default defaultValue: Double) -> Binding<Double> {
        Binding(
            get: { current?[keyPath: keyPath] ?? defaultValue },
            set: { newValue in
                current?[keyPath: keyPath] = newValue
                save()
            }
        )
    }

    private func adjustFontSize(by delta: Double) {
        guard let current else { return }
        current.fontSize = min(32, max(10, current.fontSize + delta))
        save()
    }

    private func resetAppearance() {
        guard let current else { return }
        current.resetReaderAppearance()
        current.theme = AppTheme.system.rawValue
        save()
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            AppLog.ui.error("Failed to save appearance settings: \(error.localizedDescription)")
        }
    }
}

// MARK: - Theme Swatch

/// One selectable theme tile: the theme's page color with an "Aa" specimen
/// in its text color, ringed with the accent when active. The System tile
/// splits light/dark diagonally to signal "follows the OS".
private struct ThemeSwatch: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    swatchBackground
                    Text("Aa")
                        .font(.system(size: 15, weight: .medium, design: .serif))
                        .foregroundStyle(specimenColor)
                }
                .frame(height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isSelected ? Color.cruxAccent : Color.primary.opacity(0.15),
                                      lineWidth: isSelected ? 2 : 1)
                )

                Text(shortName)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.cruxAccent : Color.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.displayName) theme")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var shortName: String {
        switch theme {
        case .highContrast: return "Contrast"
        case .night: return "Night"
        default: return theme.displayName
        }
    }

    @ViewBuilder
    private var swatchBackground: some View {
        if theme == .system {
            LinearGradient(
                stops: [
                    .init(color: Color(hex: AppTheme.light.backgroundColor) ?? .white, location: 0.49),
                    .init(color: Color(hex: AppTheme.dark.backgroundColor) ?? .black, location: 0.51)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            Color(hex: theme.backgroundColor) ?? .white
        }
    }

    private var specimenColor: Color {
        if theme == .system {
            return Color(hex: "#8B4513") ?? .brown
        }
        return Color(hex: theme.textColor) ?? .primary
    }
}
