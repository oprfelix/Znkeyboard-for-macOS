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
    @State private var keyCheck = KeyCheck.idle
    @State private var models: [String] = []
    @State private var model = Preferences.model(for: Preferences.provider)
    @State private var target = Preferences.translateTarget.code
    @State private var caretToolbar = Preferences.caretToolbar
    @State private var uiLanguage = Preferences.uiLanguage
    @State private var trusted = TextBridge.isTrusted
    @State private var screenTrusted = ScreenText.hasPermission
    @State private var screenshotTarget = Preferences.screenshotTarget.code
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

                // Saved shortly after typing or pasting stops, then checked against the provider.
                LabeledContent(L.apiKey) {
                    SecureField(L.apiKeyPlaceholder, text: $apiKey)
                        .labelsHidden()
                        .onSubmit(saveKey)
                }
                .task(id: apiKey) {
                    guard apiKey.trimmingCharacters(in: .whitespacesAndNewlines) != storedKey else { return }
                    try? await Task.sleep(for: .milliseconds(600))
                    if !Task.isCancelled { saveKey() }
                }
                if storedKey.isEmpty {
                    if provider == .gemini || preset == .deepseek {
                        HStack(spacing: 4) {
                            Text(L.noKeyYet).foregroundStyle(.secondary)
                            if provider == .gemini {
                                Link(L.getKey + " ↗", destination: URL(string: "https://aistudio.google.com/apikey")!)
                            } else {
                                Link(L.getDeepSeekKey + " ↗", destination: URL(string: "https://platform.deepseek.com/api_keys")!)
                            }
                        }
                        .font(.caption)
                    }
                } else {
                    keyCheckRow
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
                                Menu {
                                    ForEach(models, id: \.self) { id in Button(id) { model = id } }
                                } label: {
                                    Image(systemName: "chevron.down")
                                }
                                .menuStyle(.borderlessButton)
                                .menuIndicator(.hidden)
                                .fixedSize()
                                .help(L.chooseModel)
                            }
                        }
                    }
                }
            } header: {
                Text(L.aiSection)
            } footer: {
                Text(provider == .gemini ? L.modelNote : preset == .deepseek ? L.deepSeekNote : L.openAINote)
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
                    Picker(L.screenshotTarget, selection: $screenshotTarget) {
                        ForEach(Languages.all) { language in
                            Text("\(language.code) · \(language.displayName)").tag(language.code)
                        }
                    }
                    .onChange(of: screenshotTarget) { _, code in Preferences.screenshotTarget = Languages.language(code: code) }
                    Text(L.screenshotTargetNote).font(.caption).foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Toggle(L.caretToolbar, isOn: $caretToolbar)
                        .onChange(of: caretToolbar) { _, value in Preferences.caretToolbar = value }
                    Text(L.caretToolbarNote).font(.caption).foregroundStyle(.secondary)
                }

            } header: {
                Text(L.usageSection)
            }

            Section {
                LabeledContent(L.polishShortcut) { ShortcutRecorder(action: .polish, apply: applyShortcut) }
                LabeledContent(L.translateShortcut) { ShortcutRecorder(action: .translate, apply: applyShortcut) }
                LabeledContent(L.screenshotShortcut) { ShortcutRecorder(action: .screenshot, apply: applyShortcut) }
            } header: {
                Text(L.shortcutsSection)
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
                LabeledContent(L.screenRecording) {
                    HStack(spacing: 8) {
                        Label(screenTrusted ? L.granted : L.notGranted, systemImage: screenTrusted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(screenTrusted ? .green : .orange)
                        if !screenTrusted {
                            Button(L.grant) {
                                ScreenText.requestPermission()
                                ScreenText.openPermissionSettings()
                            }
                        }
                    }
                }
            } header: {
                Text(L.permission)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if !trusted {
                        Text(L.accessibilityNote)
                    }
                    if !screenTrusted {
                        Text(L.screenRecordingNote)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
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
                LabeledContent(L.version) {
                    HStack(spacing: 10) {
                        Text(Self.version).foregroundStyle(.secondary)
                        Button(L.checkForUpdates) { Updates.check() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .id(uiLanguage) // Rebuild every label in the new language.
        .onReceive(permissionTimer) { _ in
            trusted = TextBridge.isTrusted
            screenTrusted = ScreenText.hasPermission
        }
        .task(id: "\(provider.rawValue)|\(preset.rawValue)|\(baseURL)") {
            // A typed address settles before it is checked.
            if provider == .openAICompatible, preset == .custom { try? await Task.sleep(for: .milliseconds(600)) }
            if !Task.isCancelled { await loadModels() }
        }
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
    }

    private func saveBaseURL() {
        Preferences.openAIBaseURL = baseURL
    }

    private func saveKey() {
        guard apiKey.trimmingCharacters(in: .whitespacesAndNewlines) != storedKey else { return }
        Preferences.setAPIKey(apiKey, for: provider)
        storedKey = Preferences.apiKey(for: provider)
        Task { await loadModels() }
    }

    /// Loads the model list, which also checks the key.
    private func loadModels() async {
        guard let client = try? Preferences.client() else {
            keyCheck = .unverified(L.badEndpoint)
            return
        }
        guard !client.apiKey.isEmpty else {
            keyCheck = .idle
            return
        }
        keyCheck = .checking
        do {
            let loaded = try await client.models()
            keyCheck = .works
            if !loaded.isEmpty { models = loaded }
        } catch RewriteError.http(let code, let body) {
            if body.lowercased().contains("location is not supported") {
                keyCheck = .unverified(L.regionUnsupported)
            } else {
                keyCheck = [400, 401, 403].contains(code) ? .rejected : .unverified("HTTP \(code)")
            }
        } catch is CancellationError {
            // A newer check replaced this one.
        } catch {
            keyCheck = .unverified(L.networkFailed)
        }
    }

    /// A dot and a short line under the key: checking, works, or why not.
    @ViewBuilder private var keyCheckRow: some View {
        switch keyCheck {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text(L.keyChecking).foregroundStyle(.secondary)
            }
            .font(.caption)
        case .works:
            Label { Text(L.keyWorks) } icon: { Circle().fill(.green).frame(width: 8, height: 8) }
                .font(.caption)
                .foregroundStyle(.green)
        case .rejected:
            Label { Text(L.keyInvalid) } icon: { Circle().fill(.red).frame(width: 8, height: 8) }
                .font(.caption)
                .foregroundStyle(.red)
        case .unverified(let reason):
            Label { Text(L.keyUnverified(reason)) } icon: { Circle().fill(.red).frame(width: 8, height: 8) }
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}

/// The settings window's check of the saved key.
private enum KeyCheck: Equatable {
    case idle, checking, works, rejected
    case unverified(String)
}
