import SwiftUI
import SwiftData

// Liquid Glass shims live in `LiquidGlass.swift`. The "active provider"
// green ring is a thin overlay applied separately.

/// Adds a green hairline ring around the provider card when this is the
/// currently active provider. Pure presentation; doesn't depend on glass.
private struct ActiveProviderRing: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isActive ? Color.green.opacity(0.45) : Color.clear, lineWidth: 1.5)
        )
    }
}

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

            AIPromptSettingsView()
                .tabItem {
                    Label("AI Prompt", systemImage: "text.alignleft")
                }
                .tag(2)

            ReaderSettingsView()
                .tabItem {
                    Label("Reader", systemImage: "book")
                }
                .tag(3)

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(4)
        }
        // Native macOS Settings window: a slightly taller frame leaves
        // room for the longer AI Prompt editor without forcing scroll.
        .frame(minWidth: 620, idealWidth: 660, minHeight: 540, idealHeight: 600)
        .scenePadding(.horizontal)
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
                VStack(spacing: 18) {
                    ContentUnavailableView(
                        "No AI Providers",
                        systemImage: "cpu",
                        description: Text("Add an AI provider to enable intelligent margin notes and conversations")
                    )

                    // Quick-start chips for the three "no-setup" providers.
                    VStack(spacing: 8) {
                        Text("Quick start")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 32)

                        HStack(spacing: 10) {
                            QuickAddProviderChip(type: .appleIntelligence) {
                                addDefaultProvider(.appleIntelligence)
                            }
                            QuickAddProviderChip(type: .ollama) {
                                addDefaultProvider(.ollama)
                            }
                            QuickAddProviderChip(type: .lmstudio) {
                                addDefaultProvider(.lmstudio)
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }
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
                .cruxGlassButton()
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

    /// Quick-start helper: create a default-configured provider of the given
    /// type and immediately open the edit sheet so the user can adjust /
    /// run discovery. Used by the empty-state chips.
    private func addDefaultProvider(_ type: ProviderType) {
        let config: AIProviderConfig
        switch type {
        case .ollama:
            config = AIProviderConfig.createOllama()
        case .lmstudio:
            config = AIProviderConfig.createLMStudio()
        case .appleIntelligence:
            config = AIProviderConfig.createAppleIntelligence()
        default:
            return
        }
        do {
            try providerManager.createProvider(config)
            editingProvider = config
        } catch {
            // Silent fallback — the user can still use the manual "Add Provider" flow.
        }
    }
}

/// Small chip used in the AI Providers empty-state to one-click add a
/// default-configured local or on-device provider.
/// Renders a provider's brand mark from the bundled asset catalog, falling
/// back to its SF Symbol when no brand icon is available (e.g. Custom).
struct ProviderIcon: View {
    let type: ProviderType
    var size: CGFloat = 20

    var body: some View {
        Group {
            if let asset = type.iconAssetName {
                Image(asset)
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: type.symbolName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .padding(size * 0.08)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct QuickAddProviderChip: View {
    let type: ProviderType
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ProviderIcon(type: type, size: 28)
                Text(type.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(type.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 10)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(type.displayName)")
        .accessibilityHint(type.subtitle)
    }
}

struct ProviderRow: View {
    let provider: AIProviderConfig

    var body: some View {
        HStack(spacing: 12) {
            // Provider type icon with colored background — communicates
            // both activation state (green ring) and provider family (symbol).
            ZStack {
                Circle()
                    .fill(provider.isActive ? Color.green.opacity(0.15) : Color.secondary.opacity(0.1))
                    .frame(width: 40, height: 40)

                ProviderIcon(type: provider.providerType, size: 22)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(provider.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    if provider.providerType.isOnDevice {
                        Label("On device", systemImage: "lock.shield.fill")
                            .labelStyle(.iconOnly)
                            .font(.caption)
                            .foregroundStyle(.green)
                            .help("Runs locally; no network call required.")
                    }
                }

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

                    if let model = provider.model, !model.isEmpty {
                        Text("•")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text(model)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
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
        .cruxGlassCard(cornerRadius: 10, interactive: true)
        .modifier(ActiveProviderRing(isActive: provider.isActive))
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
    @State private var isLoadingKey = false

    // Local-model discovery (Ollama / LM Studio)
    @State private var discoveredModels: [DiscoveredModel] = []
    @State private var discoveryStatus: DiscoveryStatus = .idle

    enum DiscoveryStatus: Equatable {
        case idle
        case loading
        case loaded(count: Int)
        case empty
        case failed(message: String)
    }

    init(provider: AIProviderConfig?, providerManager: AIProviderManager) {
        self.provider = provider
        self.providerManager = providerManager

        _name = State(initialValue: provider?.name ?? "")
        _providerType = State(initialValue: provider?.providerType ?? .claude)
        _apiKey = State(initialValue: "") // Load asynchronously
        _baseURL = State(initialValue: provider?.baseURL ?? "")
        _model = State(initialValue: provider?.model ?? "")
        _isActive = State(initialValue: provider?.isActive ?? false)
        _isLoadingKey = State(initialValue: provider != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Information") {
                    TextField("Name", text: $name, prompt: Text("My AI Provider"))

                    Picker("Type", selection: $providerType) {
                        ForEach(ProviderType.allCases) { type in
                            HStack(spacing: 8) {
                                ProviderIcon(type: type, size: 20)
                                VStack(alignment: .leading) {
                                    Text(type.displayName)
                                    Text(type.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tag(type)
                        }
                    }
                    .onChange(of: providerType) { _, newType in
                        // Auto-fill defaults: only overwrite empty fields so
                        // the user's manual edits to baseURL/model survive
                        // a type toggle.
                        if baseURL.isEmpty {
                            baseURL = newType.defaultBaseURL ?? ""
                        }
                        if model.isEmpty && !newType.defaultModels.isEmpty {
                            model = newType.defaultModels.first ?? ""
                        }
                        if name.isEmpty {
                            name = newType.displayName
                        }
                        // Clear stale discovery state when switching types.
                        discoveredModels = []
                        discoveryStatus = .idle
                    }
                }

                // Only show authentication for providers that need API keys
                if providerType.requiresAPIKey {
                    Section("Authentication") {
                        if isLoadingKey {
                            HStack {
                                Text("API Key")
                                Spacer()
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                        } else {
                            SecureField("API Key", text: $apiKey, prompt: Text("sk-..."))
                        }

                        Text("API keys are stored securely in the system Keychain")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if providerType == .ollama || providerType == .lmstudio {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("No API key required")
                                    .fontWeight(.medium)
                                Text(providerType == .ollama
                                     ? "Ollama runs entirely on your Mac. Start it with `ollama serve` or via the menu-bar app."
                                     : "LM Studio's local server runs on your Mac — start it from the LM Studio app's Server tab.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "lock.shield.fill")
                                .foregroundStyle(.green)
                        }
                    } header: {
                        Text("Privacy")
                    }
                }

                // Show Apple Intelligence availability status
                if providerType == .appleIntelligence {
                    Section("Apple Intelligence") {
                        let status = AppleIntelligenceHelper.availabilityStatus
                        HStack {
                            Image(systemName: status == .available ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(status == .available ? .green : .orange)
                            Text(status.description)
                                .foregroundStyle(status == .available ? .primary : .secondary)
                        }

                        if status == .notEnabled {
                            Button("Open System Settings") {
                                #if os(macOS)
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.appleIntelligence") {
                                    NSWorkspace.shared.open(url)
                                }
                                #endif
                            }
                        }
                    }
                }

                Section("Configuration") {
                    if providerType.requiresBaseURL || !baseURL.isEmpty {
                        TextField("Base URL", text: $baseURL, prompt: Text(providerType.defaultBaseURL ?? "https://..."))
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            #endif

                        if let warning = baseURLWarning {
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .accessibilityLabel("URL warning: \(warning)")
                        }
                    }

                    // Model field: local providers populate from discovery;
                    // cloud providers offer an editable field with quick-pick
                    // suggestions so custom / newly-released model names still
                    // work even when they're not in our bundled list.
                    if providerType.supportsModelDiscovery {
                        installedModelsSection
                    } else {
                        TextField(
                            "Model",
                            text: $model,
                            prompt: Text(providerType.defaultModels.first ?? "gpt-4o")
                        )
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif

                        HStack {
                            if !providerType.defaultModels.isEmpty {
                                Menu {
                                    ForEach(providerType.defaultModels, id: \.self) { modelName in
                                        Button(modelName) { model = modelName }
                                    }
                                } label: {
                                    Label("Suggested models", systemImage: "list.bullet")
                                        .font(.caption)
                                }
                            }

                            // Pull the live model list straight from the
                            // provider's API (requires the key).
                            if providerType.canListRemoteModels {
                                Spacer()
                                Button {
                                    Task { await refreshRemoteModels() }
                                } label: {
                                    if discoveryStatus == .loading {
                                        HStack(spacing: 6) {
                                            ProgressView().scaleEffect(0.7)
                                            Text("Fetching…")
                                        }
                                    } else {
                                        Label("Fetch from API", systemImage: "arrow.down.circle")
                                            .font(.caption)
                                    }
                                }
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                                .disabled(apiKey.isEmpty || discoveryStatus == .loading)
                            }
                        }

                        if !discoveredModels.isEmpty {
                            Picker(selection: $model) {
                                ForEach(discoveredModels) { discovered in
                                    Text(discovered.displayName).tag(discovered.id)
                                }
                            } label: {
                                Text("Models from API")
                            }
                            .pickerStyle(.menu)
                            .accessibilityHint("Pick from \(discoveredModels.count) models reported by the API")
                        }

                        discoveryStatusFooter
                    }
                }

                Section("Activation") {
                    Toggle("Set as active provider", isOn: $isActive)
                }

                // Test connection section (not needed for Apple Intelligence)
                if providerType != .appleIntelligence {
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
        .task {
            // Load API key from Keychain asynchronously when editing existing provider
            if let provider = provider {
                isLoadingKey = true
                apiKey = await provider.getAPIKey()
                isLoadingKey = false
            }
        }
    }

    private var isValid: Bool {
        guard !name.isEmpty else { return false }

        switch providerType {
        case .appleIntelligence:
            return AppleIntelligenceHelper.isAvailable
        case .ollama, .lmstudio:
            // Local providers need a well-formed URL but no API key
            return !baseURL.isEmpty && isBaseURLWellFormed
        case .custom:
            return !apiKey.isEmpty && !baseURL.isEmpty && isBaseURLWellFormed
        default:
            // For Claude/OpenAI, allow user-overridden baseURL but require it to parse
            if baseURL.isEmpty { return !apiKey.isEmpty }
            return !apiKey.isEmpty && isBaseURLWellFormed
        }
    }

    // MARK: - Installed Models (Ollama / LM Studio)

    @ViewBuilder
    private var installedModelsSection: some View {
        // Header row with refresh button
        HStack(spacing: 8) {
            Text("Model")
            Spacer()
            Button {
                Task { await refreshInstalledModels() }
            } label: {
                if case .loading = discoveryStatus {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text("Loading…")
                    }
                } else {
                    Label("Refresh installed models", systemImage: "arrow.clockwise")
                        .labelStyle(.titleAndIcon)
                }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(!isBaseURLWellFormed || discoveryStatus == .loading)
        }

        if discoveredModels.isEmpty {
            // Free-form fallback so users can type a model name before discovery runs
            TextField("Model name", text: $model, prompt: Text(modelPlaceholder))
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
        } else {
            Picker(selection: $model) {
                ForEach(discoveredModels) { discovered in
                    HStack {
                        Text(discovered.displayName)
                        if let detail = discovered.detail {
                            Spacer()
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(discovered.id)
                }
            } label: {
                Text("Choose a model")
            }
            .pickerStyle(.menu)
            .accessibilityHint("Pick from \(discoveredModels.count) locally installed models")
        }

        discoveryStatusFooter
    }

    @ViewBuilder
    private var discoveryStatusFooter: some View {
        switch discoveryStatus {
        case .idle:
            EmptyView()
        case .loading:
            EmptyView() // already indicated next to the refresh button
        case .loaded(let count):
            Label("Found \(count) model\(count == 1 ? "" : "s").", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .empty:
            Label("No models installed yet. \(emptyHint)", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "xmark.octagon.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private var modelPlaceholder: String {
        switch providerType {
        case .ollama: return "e.g. llama3.2"
        case .lmstudio: return "e.g. mistral-7b-instruct"
        default: return ""
        }
    }

    private var emptyHint: String {
        switch providerType {
        case .ollama: return "Try `ollama pull llama3.2` then refresh."
        case .lmstudio: return "Download a model in LM Studio, then refresh."
        default: return ""
        }
    }

    private func refreshInstalledModels() async {
        discoveryStatus = .loading
        // Build a transient config that captures the user's current entries.
        let probe = AIProviderConfig(
            id: UUID(),
            name: "probe",
            type: providerType,
            apiKey: "",
            baseURL: baseURL.isEmpty ? nil : baseURL,
            model: nil,
            isActive: false
        )
        do {
            let models = try await providerManager.discoverLocalModels(for: probe)
            discoveredModels = models
            if models.isEmpty {
                discoveryStatus = .empty
            } else {
                discoveryStatus = .loaded(count: models.count)
                // If the user hasn't picked a model yet (or picked one no
                // longer present), prefer the first installed model.
                if !models.contains(where: { $0.id == model }) {
                    model = models.first?.id ?? model
                }
            }
        } catch let error as AIProviderError {
            switch error {
            case .networkError, .timeout:
                discoveryStatus = .failed(message: notRunningMessage)
            default:
                discoveryStatus = .failed(message: error.localizedDescription)
            }
        } catch {
            discoveryStatus = .failed(message: error.localizedDescription)
        }
    }

    /// Pulls the latest models from a cloud provider's `/models` endpoint.
    private func refreshRemoteModels() async {
        discoveryStatus = .loading
        do {
            let models = try await providerManager.discoverRemoteModels(
                type: providerType,
                baseURL: baseURL.isEmpty ? nil : baseURL,
                apiKey: apiKey
            )
            discoveredModels = models
            if models.isEmpty {
                discoveryStatus = .empty
            } else {
                discoveryStatus = .loaded(count: models.count)
                // Only auto-select when the user hasn't typed/chosen a model.
                if model.isEmpty {
                    model = models.first?.id ?? model
                }
            }
        } catch let error as AIProviderError {
            discoveryStatus = .failed(message: error.errorDescription ?? "Couldn't fetch models from the API.")
        } catch {
            discoveryStatus = .failed(message: error.localizedDescription)
        }
    }

    private var notRunningMessage: String {
        switch providerType {
        case .ollama:
            return "Ollama isn't responding at \(baseURL). Start it with `ollama serve` or the menu-bar app."
        case .lmstudio:
            return "LM Studio's server isn't responding at \(baseURL). Open LM Studio → Server tab and click Start."
        default:
            return "Service didn't respond at \(baseURL)."
        }
    }

    /// True if `baseURL` parses into a URL with an HTTP(S) scheme and host.
    private var isBaseURLWellFormed: Bool {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return false }
        guard let scheme = url.scheme?.lowercased(), let host = url.host, !host.isEmpty else {
            return false
        }
        return scheme == "https" || scheme == "http"
    }

    /// User-visible advisory: returns nil when the URL is fine, or a short
    /// message describing why the user should double-check the entry.
    private var baseURLWarning: String? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let url = URL(string: trimmed) else {
            return "URL is malformed — provide a complete address (e.g. https://api.example.com/v1)."
        }
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme.isEmpty || (scheme != "https" && scheme != "http") {
            return "URL must start with https:// (http:// only allowed for localhost during development)."
        }
        guard let host = url.host, !host.isEmpty else {
            return "URL must include a host (e.g. api.example.com)."
        }
        let isLocal = host == "localhost" || host == "127.0.0.1" || host.hasSuffix(".local")
        if scheme == "http" && !isLocal {
            return "HTTP is insecure — use HTTPS for any non-local provider."
        }
        return nil
    }

    private func testConnection() async {
        isTesting = true
        testResult = nil

        // Create a temporary test config with the current form values
        // We use a temporary config ID to store the API key for testing
        let testConfigId = UUID()
        
        do {
            // For testing, we need to temporarily store the API key
            if providerType.requiresAPIKey && !apiKey.isEmpty {
                try await KeychainService.shared.saveAPIKey(apiKey, for: testConfigId)
            }
            
            let testConfig = AIProviderConfig(
                id: testConfigId,
                name: name,
                type: providerType,
                apiKey: apiKey,
                baseURL: baseURL.isEmpty ? nil : baseURL,
                model: model.isEmpty ? nil : model
            )

            let success = try await providerManager.testProvider(testConfig)
            testResult = .success(success)
            
            // Clean up temporary test key
            try? await KeychainService.shared.deleteAPIKey(for: testConfigId)
        } catch {
            testResult = .failure(error)
            // Clean up temporary test key on error too
            try? await KeychainService.shared.deleteAPIKey(for: testConfigId)
        }

        isTesting = false
    }

    private func saveProvider() {
        Task {
            do {
                if let existing = provider {
                    existing.name = name
                    existing.providerType = providerType
                    existing.baseURL = baseURL.isEmpty ? nil : baseURL
                    existing.model = model.isEmpty ? nil : model
                    existing.isActive = isActive
                    
                    // Save API key to Keychain asynchronously
                    if providerType.requiresAPIKey {
                        try await existing.setAPIKey(apiKey)
                    }

                    try providerManager.updateProvider(existing)

                    if isActive {
                        try await providerManager.setActiveProviderAsync(existing)
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

                    // The initializer kicks off a best-effort Keychain save,
                    // but persist the key explicitly (and awaited) so it's
                    // guaranteed stored before we dismiss — and so a Keychain
                    // failure surfaces instead of silently losing the key.
                    if providerType.requiresAPIKey {
                        try await newProvider.setAPIKey(apiKey)
                    }

                    if isActive {
                        try await providerManager.setActiveProviderAsync(newProvider)
                    }
                }

                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    testResult = .failure(error)
                }
            }
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
    @Query private var settings: [AppSettings]
    @Environment(\.modelContext) private var modelContext
    @State private var showingOnboarding = false

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
            .background(Color.cruxControlBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)

            Spacer()

            // Links
            VStack(spacing: 12) {
                Button {
                    showingOnboarding = true
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Show Welcome Tour")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Replays the onboarding sheet shown on first launch")

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
        .background(Color.cruxWindowBackground.opacity(0.5))
        .sheet(isPresented: $showingOnboarding) {
            OnboardingView(onFinish: {
                if let appSettings = settings.first {
                    appSettings.hasSeenOnboarding = true
                    try? modelContext.save()
                }
            })
        }
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
        // Resolve a platform color so this extension compiles on both macOS
        // (NSColor) and iOS (UIColor). Without the iOS branch the whole
        // `extension Color` failed to type-check on iOS, which made
        // `init?(hex:)` invisible and broke every `Color(hex:)` call site.
        #if os(macOS)
        let cgColor = NSColor(self).cgColor
        #else
        let cgColor = UIColor(self).cgColor
        #endif
        guard let components = cgColor.components, components.count >= 3 else {
            return "#000000"
        }
        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        return String(format: "#%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
    }
}

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
