import SwiftUI

struct SettingsView: View {
    /// Called when the translate target changes here, so the menu can follow.
    var onChange: () -> Void = {}

    @State private var apiKey = Preferences.apiKey
    @State private var keySaved = false
    @State private var models: [String] = []
    @State private var model = Preferences.model
    @State private var target = Preferences.translateTarget.code
    @State private var trusted = TextBridge.isTrusted
    @State private var uiLanguage = Preferences.uiLanguage
    @State private var caretToolbar = Preferences.caretToolbar
    private let permissionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                Picker(L.uiLanguage, selection: $uiLanguage) {
                    Text(L.followSystem).tag("system")
                    Text("中文").tag("zh")
                    Text("English").tag("en")
                }
                .pickerStyle(.segmented)
                .onChange(of: uiLanguage) { _, value in
                    Preferences.uiLanguage = value
                    onChange()
                }
            }

            Section(L.apiKeySection) {
                HStack {
                    SecureField(L.apiKeyPlaceholder, text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(saveKey)
                    Button(keySaved ? L.saved : L.save, action: saveKey)
                        .disabled(apiKey == Preferences.apiKey && !apiKey.isEmpty)
                }
                Text(L.apiKeyNote).font(.caption).foregroundStyle(.secondary)
                Link(L.getKey, destination: URL(string: "https://aistudio.google.com/apikey")!)
                    .font(.caption)
            }

            Section {
                Picker(L.model, selection: $model) {
                    ForEach(modelOptions, id: \.self) { id in
                        Text(id == Preferences.defaultModel ? "\(id)（\(L.recommended)）" : id).tag(id)
                    }
                }
                .onChange(of: model) { _, value in Preferences.model = value }
                Text(L.modelNote).font(.caption).foregroundStyle(.secondary)
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
            }

            Section {
                Toggle(L.caretToolbar, isOn: $caretToolbar)
                    .onChange(of: caretToolbar) { _, value in Preferences.caretToolbar = value }
                Text(L.caretToolbarNote).font(.caption).foregroundStyle(.secondary)
            }

            Section(L.shortcuts) {
                LabeledContent(L.polish, value: "⌥⌘R")
                LabeledContent(L.translateTo(Languages.language(code: target)), value: "⌥⌘T")
                Text(L.shortcutsNote).font(.caption).foregroundStyle(.secondary)
            }

            Section(L.permission) {
                HStack {
                    Text(L.accessibility)
                    Spacer()
                    Text(trusted ? L.granted : L.notGranted)
                        .foregroundStyle(trusted ? .green : .orange)
                    if !trusted {
                        Button(L.grant) {
                            TextBridge.requestTrust()
                            TextBridge.openAccessibilitySettings()
                        }
                    }
                }
                if !trusted {
                    Text(L.accessibilityNote).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(permissionTimer) { _ in trusted = TextBridge.isTrusted }
        .task { await loadModels() }
    }

    /// The live Lite list once loaded; until then the saved and recommended models.
    private var modelOptions: [String] {
        var options = models.isEmpty ? [Preferences.defaultModel] : models
        if !options.contains(model) { options.append(model) }
        return options
    }

    private func saveKey() {
        Preferences.apiKey = apiKey
        apiKey = Preferences.apiKey
        keySaved = true
        Task {
            await loadModels()
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            keySaved = false
        }
    }

    private func loadModels() async {
        let key = Preferences.apiKey
        guard !key.isEmpty else { return }
        if let loaded = try? await GeminiClient(apiKey: key, model: model).liteModels(), !loaded.isEmpty {
            models = loaded
        }
    }
}
