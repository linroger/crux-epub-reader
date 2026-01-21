import SwiftUI
import SwiftData

#if os(macOS)
struct SettingsView: View {
    @Environment(AIProviderManager.self) private var providerManager
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(0)

            AIProvidersSettingsView()
                .environment(providerManager)
                .tabItem {
                    Label("AI Providers", systemImage: "cpu")
                }
                .tag(1)

            ReaderSettingsView()
                .tabItem {
                    Label("Reader", systemImage: "book")
                }
                .tag(2)

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(3)
        }
        .frame(width: 600, height: 500)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @Query private var settings: [AppSettings]
    @Environment(\.modelContext) private var modelContext

    private var appSettings: AppSettings {
        if let existing = settings.first {
            return existing
        }
        let new = AppSettings.createDefault()
        modelContext.insert(new)
        try? modelContext.save()
        return new
    }

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: Binding(
                    get: { AppTheme(rawValue: appSettings.theme) ?? .system },
                    set: { appSettings.theme = $0.rawValue; save() }
                )) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Label("Appearance", systemImage: "paintbrush.fill")
                    .font(.headline)
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("View Mode")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Picker("View Mode", selection: Binding(
                        get: { LibraryViewMode(rawValue: appSettings.libraryViewMode) ?? .list },
                        set: { appSettings.libraryViewMode = $0.rawValue; save() }
                    )) {
                        ForEach(LibraryViewMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Divider()

                Picker("Sort By", selection: Binding(
                    get: { LibrarySortOrder(rawValue: appSettings.librarySortOrder) ?? .lastRead },
                    set: { appSettings.librarySortOrder = $0.rawValue; save() }
                )) {
                    ForEach(LibrarySortOrder.allCases) { order in
                        Text(order.displayName).tag(order)
                    }
                }

                Toggle("Sort Ascending", isOn: Binding(
                    get: { appSettings.librarySortAscending },
                    set: { appSettings.librarySortAscending = $0; save() }
                ))
            } header: {
                Label("Library", systemImage: "books.vertical.fill")
                    .font(.headline)
            }

            Section {
                Toggle("Confirm before deleting books", isOn: Binding(
                    get: { appSettings.confirmDelete },
                    set: { appSettings.confirmDelete = $0; save() }
                ))

                Toggle("Track reading time", isOn: Binding(
                    get: { appSettings.trackReadingTime },
                    set: { appSettings.trackReadingTime = $0; save() }
                ))

                Divider()

                HStack {
                    Text("Auto-save interval")
                    Spacer()
                    TextField("Seconds", value: Binding(
                        get: { appSettings.autoSaveInterval },
                        set: { appSettings.autoSaveInterval = $0; save() }
                    ), format: .number)
                    .frame(width: 60)
                    .textFieldStyle(.roundedBorder)
                    Text("seconds")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("Behavior", systemImage: "gearshape.fill")
                    .font(.headline)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func save() {
        try? modelContext.save()
    }
}

// MARK: - AI Providers Settings

struct AIProvidersSettingsView: View {
    @Environment(AIProviderManager.self) private var providerManager
    @State private var showingAddProvider = false
    @State private var editingProvider: AIProviderConfig?
    @State private var hoveredProvider: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("AI Providers", systemImage: "cpu.fill")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Spacer()

                    if let activeName = providerManager.activeProviderName {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                            Text(activeName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.1))
                        .clipShape(Capsule())
                    }
                }

                Text("Configure AI providers for margin notes and AI-powered annotations")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }

            Divider()

            // Providers list
            if providerManager.providers.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "No AI Providers",
                    systemImage: "cpu",
                    description: Text("Add an AI provider to enable intelligent margin notes and conversations")
                )
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(providerManager.providers) { provider in
                            ProviderRow(provider: provider)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    editingProvider = provider
                                }
                                .contextMenu {
                                    Button {
                                        editingProvider = provider
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }

                                    if !provider.isActive {
                                        Button {
                                            try? providerManager.setActiveProvider(provider)
                                        } label: {
                                            Label("Set as Active", systemImage: "checkmark.circle")
                                        }
                                    }

                                    Divider()

                                    Button(role: .destructive) {
                                        try? providerManager.deleteProvider(provider)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .onHover { isHovered in
                                    hoveredProvider = isHovered ? provider.id : nil
                                }
                                .scaleEffect(hoveredProvider == provider.id ? 1.02 : 1.0)
                                .animation(.easeInOut(duration: 0.2), value: hoveredProvider)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Spacer()

            // Action button
            HStack {
                Button {
                    showingAddProvider = true
                } label: {
                    Label("Add Provider", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Spacer()

                Text("\(providerManager.providers.count) provider\(providerManager.providers.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .sheet(isPresented: $showingAddProvider) {
            ProviderEditView(provider: nil, providerManager: providerManager)
        }
        .sheet(item: $editingProvider) { provider in
            ProviderEditView(provider: provider, providerManager: providerManager)
        }
    }
}

struct ProviderRow: View {
    let provider: AIProviderConfig

    var body: some View {
        HStack(spacing: 12) {
            // Status icon with colored background
            ZStack {
                Circle()
                    .fill(provider.isActive ? Color.green.opacity(0.15) : Color.secondary.opacity(0.1))
                    .frame(width: 40, height: 40)

                Image(systemName: provider.isActive ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(provider.isActive ? .green : .secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(provider.name)
                    .font(.headline)
                    .foregroundColor(.primary)

                HStack(spacing: 4) {
                    // Provider type badge
                    Text(provider.providerType.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.1))
                        .foregroundColor(.accentColor)
                        .clipShape(Capsule())

                    if let model = provider.model {
                        Text("•")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text(model)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Active badge
            if provider.isActive {
                Text("ACTIVE")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
        }
        .padding(12)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(provider.isActive ? Color.green.opacity(0.3) : Color.clear, lineWidth: 2)
        )
    }
}

// MARK: - Provider Edit View

struct ProviderEditView: View {
    @Environment(\.dismiss) private var dismiss
    let provider: AIProviderConfig?
    let providerManager: AIProviderManager

    @State private var name: String
    @State private var providerType: ProviderType
    @State private var apiKey: String
    @State private var baseURL: String
    @State private var model: String
    @State private var isActive: Bool
    @State private var isTesting = false
    @State private var testResult: Result<Bool, Error>?

    init(provider: AIProviderConfig?, providerManager: AIProviderManager) {
        self.provider = provider
        self.providerManager = providerManager

        _name = State(initialValue: provider?.name ?? "")
        _providerType = State(initialValue: provider?.providerType ?? .claude)
        _apiKey = State(initialValue: provider?.apiKey ?? "")
        _baseURL = State(initialValue: provider?.baseURL ?? "")
        _model = State(initialValue: provider?.model ?? "")
        _isActive = State(initialValue: provider?.isActive ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Information") {
                    TextField("Name", text: $name, prompt: Text("My AI Provider"))

                    Picker("Type", selection: $providerType) {
                        ForEach(ProviderType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .onChange(of: providerType) { _, newType in
                        // Auto-fill defaults
                        if baseURL.isEmpty {
                            baseURL = newType.defaultBaseURL ?? ""
                        }
                        if model.isEmpty && !newType.defaultModels.isEmpty {
                            model = newType.defaultModels.first ?? ""
                        }
                    }
                }

                Section("Authentication") {
                    SecureField("API Key", text: $apiKey, prompt: Text("sk-..."))
                }

                Section("Configuration") {
                    if providerType.requiresBaseURL || !baseURL.isEmpty {
                        TextField("Base URL", text: $baseURL, prompt: Text(providerType.defaultBaseURL ?? "https://..."))
                    }

                    if !providerType.defaultModels.isEmpty {
                        Picker("Model", selection: $model) {
                            ForEach(providerType.defaultModels, id: \.self) { modelName in
                                Text(modelName).tag(modelName)
                            }
                        }
                    } else {
                        TextField("Model (optional)", text: $model, prompt: Text("gpt-4o"))
                    }
                }

                Section("Activation") {
                    Toggle("Set as active provider", isOn: $isActive)
                }

                Section {
                    Button("Test Connection") {
                        Task {
                            await testConnection()
                        }
                    }
                    .disabled(isTesting || !isValid)

                    if let result = testResult {
                        switch result {
                        case .success:
                            Label("Connection successful", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .failure(let error):
                            Label(error.localizedDescription, systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                    }

                    if isTesting {
                        HStack {
                            ProgressView()
                            Text("Testing...")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(provider == nil ? "Add Provider" : "Edit Provider")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveProvider()
                    }
                    .disabled(!isValid)
                }
            }
        }
        .frame(width: 500, height: 600)
    }

    private var isValid: Bool {
        !name.isEmpty && !apiKey.isEmpty &&
        (providerType != .custom || !baseURL.isEmpty)
    }

    private func testConnection() async {
        isTesting = true
        testResult = nil

        let testConfig: AIProviderConfig
        if let existing = provider {
            testConfig = existing
            testConfig.name = name
            testConfig.providerType = providerType
            testConfig.apiKey = apiKey
            testConfig.baseURL = baseURL.isEmpty ? nil : baseURL
            testConfig.model = model.isEmpty ? nil : model
        } else {
            testConfig = AIProviderConfig(
                name: name,
                type: providerType,
                apiKey: apiKey,
                baseURL: baseURL.isEmpty ? nil : baseURL,
                model: model.isEmpty ? nil : model
            )
        }

        do {
            let success = try await providerManager.testProvider(testConfig)
            testResult = .success(success)
        } catch {
            testResult = .failure(error)
        }

        isTesting = false
    }

    private func saveProvider() {
        do {
            if let existing = provider {
                existing.name = name
                existing.providerType = providerType
                existing.apiKey = apiKey
                existing.baseURL = baseURL.isEmpty ? nil : baseURL
                existing.model = model.isEmpty ? nil : model
                existing.isActive = isActive

                try providerManager.updateProvider(existing)

                if isActive {
                    try providerManager.setActiveProvider(existing)
                }
            } else {
                let newProvider = AIProviderConfig(
                    name: name,
                    type: providerType,
                    apiKey: apiKey,
                    baseURL: baseURL.isEmpty ? nil : baseURL,
                    model: model.isEmpty ? nil : model,
                    isActive: isActive
                )

                try providerManager.createProvider(newProvider)

                if isActive {
                    try providerManager.setActiveProvider(newProvider)
                }
            }

            dismiss()
        } catch {
            testResult = .failure(error)
        }
    }
}

// MARK: - Reader Settings

struct ReaderSettingsView: View {
    @Query private var settings: [AppSettings]
    @Environment(\.modelContext) private var modelContext

    private var appSettings: AppSettings {
        if let existing = settings.first {
            return existing
        }
        let new = AppSettings.createDefault()
        modelContext.insert(new)
        try? modelContext.save()
        return new
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Font Family")
                    Spacer()
                    TextField("System", text: Binding(
                        get: { appSettings.fontFamily },
                        set: { appSettings.fontFamily = $0; save() }
                    ))
                    .frame(width: 180)
                    .textFieldStyle(.roundedBorder)
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Font Size")
                        Spacer()
                        Text("\(Int(appSettings.fontSize))pt")
                            .fontWeight(.medium)
                            .monospacedDigit()
                    }

                    Slider(
                        value: Binding(
                            get: { appSettings.fontSize },
                            set: { appSettings.fontSize = $0; save() }
                        ),
                        in: 8...32,
                        step: 1
                    )
                    .tint(.accentColor)

                    // Font size presets
                    HStack(spacing: 8) {
                        Text("Quick:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(FontSizePreset.allCases) { preset in
                            Button(preset.label) {
                                appSettings.fontSize = preset.size
                                save()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(abs(appSettings.fontSize - preset.size) < 1 ? .accentColor : nil)
                        }
                    }
                }
            } header: {
                Label("Typography", systemImage: "textformat")
                    .font(.headline)
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Line Height")
                        Spacer()
                        Text("\(appSettings.lineHeight, specifier: "%.1f")")
                            .fontWeight(.medium)
                            .monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { appSettings.lineHeight },
                            set: { appSettings.lineHeight = $0; save() }
                        ),
                        in: 1.0...3.0,
                        step: 0.1
                    )
                    .tint(.accentColor)
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Paragraph Spacing")
                        Spacer()
                        Text("\(appSettings.paragraphSpacing, specifier: "%.1f")em")
                            .fontWeight(.medium)
                            .monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { appSettings.paragraphSpacing },
                            set: { appSettings.paragraphSpacing = $0; save() }
                        ),
                        in: 0.5...3.0,
                        step: 0.1
                    )
                    .tint(.accentColor)
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Margin Width")
                        Spacer()
                        Text("\(Int(appSettings.marginWidth))px")
                            .fontWeight(.medium)
                            .monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { appSettings.marginWidth },
                            set: { appSettings.marginWidth = $0; save() }
                        ),
                        in: 20...200,
                        step: 10
                    )
                    .tint(.accentColor)
                }
            } header: {
                Label("Layout & Spacing", systemImage: "text.alignleft")
                    .font(.headline)
            }

            Section("Colors") {
                // Theme presets
                VStack(alignment: .leading, spacing: 12) {
                    Text("Theme Presets")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                        ForEach(ThemePreset.allCases) { theme in
                            Button {
                                theme.apply(to: appSettings)
                                save()
                            } label: {
                                VStack(spacing: 4) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color(hex: theme.backgroundColor) ?? .white)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                        )
                                        .frame(height: 30)
                                        .overlay(
                                            Text("Aa")
                                                .foregroundStyle(Color(hex: theme.textColor) ?? .black)
                                                .font(.caption)
                                        )

                                    Text(theme.label)
                                        .font(.caption2)
                                        .foregroundStyle(.primary)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .padding(8)
                            .background(theme.matches(appSettings) ? Color.accentColor.opacity(0.1) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .padding(.vertical, 8)

                Divider()

                ColorPicker("Background Color",
                    selection: Binding(
                        get: { Color(hex: appSettings.backgroundColor) ?? .white },
                        set: { appSettings.backgroundColor = $0.toHex(); save() }
                    ))

                ColorPicker("Text Color",
                    selection: Binding(
                        get: { Color(hex: appSettings.textColor) ?? .black },
                        set: { appSettings.textColor = $0.toHex(); save() }
                    ))
            }

            Section {
                Button("Reset to Defaults") {
                    appSettings.resetReaderAppearance()
                    save()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func save() {
        try? modelContext.save()
    }
}

// MARK: - About View

struct AboutView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // App icon and title
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .shadow(color: .blue.opacity(0.3), radius: 20, x: 0, y: 10)

                    Image(systemName: "book.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 8) {
                    Text("Crux")
                        .font(.system(size: 36, weight: .bold, design: .rounded))

                    Text("AI-Native EPUB Reader")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            // Version info card
            VStack(spacing: 12) {
                InfoRow(label: "Version", value: "1.0.0")
                Divider()
                InfoRow(label: "Build", value: "1")
                Divider()
                InfoRow(label: "Platform", value: "macOS 14.0+")
            }
            .padding(20)
            .frame(width: 300)
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)

            Spacer()

            // Links
            VStack(spacing: 12) {
                Link(destination: URL(string: "https://github.com/anthropics/claude-code")!) {
                    HStack {
                        Image(systemName: "book.fill")
                        Text("Documentation")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Link(destination: URL(string: "https://github.com/anthropics/claude-code/issues")!) {
                    HStack {
                        Image(systemName: "exclamationmark.bubble.fill")
                        Text("Report Issue")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            .frame(width: 300)

            // Copyright
            Text("© 2026 Crux  •  Made with Claude")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor).opacity(0.5))
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Color Extension

extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    func toHex() -> String {
        guard let components = NSColor(self).cgColor.components, components.count >= 3 else {
            return "#000000"
        }
        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        return String(format: "#%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
    }
}

#endif

// MARK: - Font Size Presets

enum FontSizePreset: CaseIterable, Identifiable {
    case small
    case medium
    case large
    case extraLarge

    var id: String { label }

    var label: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .extraLarge: return "X-Large"
        }
    }

    var size: Double {
        switch self {
        case .small: return 12
        case .medium: return 16
        case .large: return 20
        case .extraLarge: return 24
        }
    }
}

// MARK: - Theme Presets

enum ThemePreset: CaseIterable, Identifiable {
    case light
    case sepia
    case dark
    case highContrast

    var id: String { label }

    var label: String {
        switch self {
        case .light: return "Light"
        case .sepia: return "Sepia"
        case .dark: return "Dark"
        case .highContrast: return "High Contrast"
        }
    }

    var backgroundColor: String {
        switch self {
        case .light: return "#FFFFFF"
        case .sepia: return "#F4ECD8"
        case .dark: return "#1C1C1E"
        case .highContrast: return "#000000"
        }
    }

    var textColor: String {
        switch self {
        case .light: return "#000000"
        case .sepia: return "#5B4636"
        case .dark: return "#EBEBF5"
        case .highContrast: return "#FFFFFF"
        }
    }

    func apply(to settings: AppSettings) {
        settings.backgroundColor = backgroundColor
        settings.textColor = textColor
    }

    func matches(_ settings: AppSettings) -> Bool {
        settings.backgroundColor == backgroundColor && settings.textColor == textColor
    }
}
