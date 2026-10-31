import SwiftUI

struct SettingsView: View {
    /// Called when something the menu or window title shows changes here.
    var onChange: () -> Void = {}
    /// Registers a new global shortcut (nil: the default) and reports whether it took.
    var applyShortcut: (ShortcutAction, Shortcut?) -> ShortcutResult = { _, shortcut in .ok(shortcut ?? .init(keyCode: 0, modifiers: 0, key: "")) }

    @State private var provider = Preferences.provider
    @State private var preset = Preferences.apiPreset
    @State private var baseURL = Preferences.openAIBaseURL
    @State private var apiKey = Preferences.apiKey(for: Preferences.provider)
    @State private var storedKey = Preferences.apiKey(for: Preferences.provider)
    @State private var models: [String] = []
    @State private var model = Preferences.model(for: Preferences.provider)
    @State private var target = Preferences.translateTarget.code
    @State private var caretToolbar = Preferences.caretToolbar
    @State private var uiLanguage = Preferences.uiLanguage
    @State private var trusted = TextBridge.isTrusted
    private let permissionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                Picker(L.provider, selection: Binding(get: { provider }, set: switchProvider)) {
                    ForEach(Provider.allCases) { Text($0.displayName).tag($0) }
                }

                if provider == .openAICompatible {
                    Picker(L.apiPreset, selection: Binding(get: { preset }, set: switchPreset)) {
                        ForEach(APIPreset.allCases) { Text($0.displayName).tag($0) }
                    }
                }

                if provider == .openAICompatible, preset == .custom {
                    LabeledContent(L.apiBaseURL) {
                        TextField(Preferences.defaultOpenAIBaseURL, text: $baseURL)
                            .labelsHidden()
                            .onSubmit(saveBaseURL)
                            .onChange(of: baseURL) { _, _ in saveBaseURL() }
                    }
                }

                LabeledContent(L.apiKey) {
                    HStack {
                        SecureField(L.apiKeyPlaceholder, text: $apiKey)
                            .labelsHidden()
                            .onSubmit(saveKey)
                        Button(L.save, action: saveKey)
                            .disabled(apiKey.trimmingCharacters(in: .whitespaces) == storedKey)
                    }
                }
                if storedKey.isEmpty, provider == .gemini {
                    HStack(spacing: 4) {
                        Text(L.noKeyYet).foregroundStyle(.secondary)
                        Link(L.getKey + " ↗", destination: URL(string: "https://aistudio.google.com/apikey")!)
                    }
                    .font(.caption)
                } else if !storedKey.isEmpty {
                    Label(L.keyStored, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                if provider == .gemini {
                    Picker(L.model, selection: $model) {
                        ForEach(modelOptions, id: \.self) { id in
                            Text(id == Preferences.defaultModel ? "\(id)（\(L.recommended)）" : id).tag(id)
                        }
                    }
                    .onChange(of: model) { _, value in Preferences.setModel(value, for: .gemini) }
                } else {
                    // Any model ID can be typed; the server's list, once loaded, is a shortcut.
                    LabeledContent(L.model) {
                        HStack {
                            TextField(L.modelIDPlaceholder, text: $model)
                                .labelsHidden()
                                .onChange(of: model) { _, value in Preferences.setModel(value, for: .openAICompatible) }
                            if !models.isEmpty {
                                Menu(L.chooseModel) {
                                    ForEach(models, id: \.self) { id in Button(id) { model = id } }
                                }
                                .fixedSize()
                            }
                        }
                    }
                }
            } header: {
                Text(L.aiSection)
            } footer: {
                let note = provider == .gemini ? L.modelNote : preset == .deepseek ? L.deepSeekNote : L.openAINote
                Text("\(note)\(L.isChinese ? "" : " ")\(L.privacyNote) \(L.keyPerProvider)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker(L.translateMenu, selection: $target) {
                    ForEach(Languages.all) { language in
                        Text("\(language.code) · \(language.displayName)").tag(language.code)
                    }
                }
                .onChange(of: target) { _, code in
                    Preferences.translateTarget = Languages.language(code: code)
                    onChange()
                }

                VStack(alignment: .leading, spacing: 4) {
                    Toggle(L.caretToolbar, isOn: $caretToolbar)
                        .onChange(of: caretToolbar) { _, value in Preferences.caretToolbar = value }
                    Text(L.caretToolbarNote).font(.caption).foregroundStyle(.secondary)
                }

                LabeledContent(L.polishShortcut) { ShortcutRecorder(action: .polish, apply: applyShortcut) }
                LabeledContent(L.translateShortcut) { ShortcutRecorder(action: .translate, apply: applyShortcut) }
            } header: {
                Text(L.usageSection)
            } footer: {
                Text(L.shortcutsNote).font(.caption).foregroundStyle(.secondary)
            }

            Section {
                LabeledContent(L.accessibility) {
                    HStack(spacing: 8) {
                        Label(trusted ? L.granted : L.notGranted, systemImage: trusted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(trusted ? .green : .orange)
                        if !trusted {
                            Button(L.grant) {
                                TextBridge.requestTrust()
                                TextBridge.openAccessibilitySettings()
                            }
                        }
                    }
                }
            } header: {
                Text(L.permission)
            } footer: {
                if !trusted {
                    Text(L.accessibilityNote).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section(L.generalSection) {
                // Saved before the state changes, so this redraw already uses the new language.
                Picker(L.uiLanguage, selection: Binding(
                    get: { uiLanguage },
                    set: { value in
                        Preferences.uiLanguage = value
                        uiLanguage = value
                        onChange()
                    }
                )) {
                    Text(L.followSystem).tag("system")
                    Text("中文").tag("zh")
                    Text("English").tag("en")
                }
                LabeledContent(L.version, value: Self.version)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .id(uiLanguage) // Rebuild every label in the new language.
        .onReceive(permissionTimer) { _ in trusted = TextBridge.isTrusted }
        .task(id: provider) { await loadModels() }
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }

    /// The live Lite list once loaded; until then the saved and recommended models.
    private var modelOptions: [String] {
        var options = models.isEmpty ? [Preferences.defaultModel] : models
        if !options.contains(model) { options.append(model) }
        return options
    }

    /// Loads the chosen provider's own key and model into the form.
    private func switchProvider(_ next: Provider) {
        Preferences.provider = next
        provider = next
        apiKey = Preferences.apiKey(for: next)
        storedKey = apiKey
        model = Preferences.model(for: next)
        models = []
        onChange()
    }

    /// DeepSeek's address is built in; a model typed for another service would not exist there.
    private func switchPreset(_ next: APIPreset) {
        Preferences.apiPreset = next
        preset = next
        if next == .deepseek, !model.hasPrefix("deepseek") {
            model = Preferences.defaultOpenAIModel
            Preferences.setModel(model, for: .openAICompatible)
        }
        models = []
        Task { await loadModels() }
    }

    private func saveBaseURL() {
        Preferences.openAIBaseURL = baseURL
    }

    private func saveKey() {
        Preferences.setAPIKey(apiKey, for: provider)
        apiKey = Preferences.apiKey(for: provider)
        storedKey = apiKey
        Task { await loadModels() }
    }

    private func loadModels() async {
        guard let client = try? Preferences.client(), !client.apiKey.isEmpty,
              let loaded = try? await client.models(), !loaded.isEmpty else { return }
        models = loaded
    }
}
