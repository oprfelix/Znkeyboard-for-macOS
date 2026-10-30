import SwiftUI

struct SettingsView: View {
    /// Called when something the menu or window title shows changes here.
    var onChange: () -> Void = {}

    @State private var apiKey = Preferences.apiKey
    @State private var storedKey = Preferences.apiKey
    @State private var models: [String] = []
    @State private var model = Preferences.model
    @State private var target = Preferences.translateTarget.code
    @State private var caretToolbar = Preferences.caretToolbar
    @State private var uiLanguage = Preferences.uiLanguage
    @State private var trusted = TextBridge.isTrusted
    private let permissionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                LabeledContent(L.apiKey) {
                    HStack {
                        SecureField(L.apiKeyPlaceholder, text: $apiKey)
                            .labelsHidden()
                            .onSubmit(saveKey)
                        Button(L.save, action: saveKey)
                            .disabled(apiKey.trimmingCharacters(in: .whitespaces) == storedKey)
                    }
                }
                if storedKey.isEmpty {
                    HStack(spacing: 4) {
                        Text(L.noKeyYet).foregroundStyle(.secondary)
                        Link(L.getKey + " ↗", destination: URL(string: "https://aistudio.google.com/apikey")!)
                    }
                    .font(.caption)
                } else {
                    Label(L.keyStored, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                Picker(L.model, selection: $model) {
                    ForEach(modelOptions, id: \.self) { id in
                        Text(id == Preferences.defaultModel ? "\(id)（\(L.recommended)）" : id).tag(id)
                    }
                }
                .onChange(of: model) { _, value in Preferences.model = value }
            } header: {
                Text(L.aiSection)
            } footer: {
                Text("\(L.modelNote)\(L.isChinese ? "" : " ")\(L.privacyNote)")
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

                LabeledContent(L.polishShortcut) { ShortcutText("⌥⌘R") }
                LabeledContent(L.translateShortcut) { ShortcutText("⌥⌘T") }
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
        .task { await loadModels() }
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

    private func saveKey() {
        Preferences.apiKey = apiKey
        apiKey = Preferences.apiKey
        storedKey = apiKey
        Task { await loadModels() }
    }

    private func loadModels() async {
        let key = Preferences.apiKey
        guard !key.isEmpty else { return }
        if let loaded = try? await GeminiClient(apiKey: key, model: model).liteModels(), !loaded.isEmpty {
            models = loaded
        }
    }
}

/// A shortcut shown like a key cap.
private struct ShortcutText: View {
    let keys: String
    init(_ keys: String) { self.keys = keys }

    var body: some View {
        Text(keys)
            .font(.system(.body, design: .rounded).weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
    }
}
