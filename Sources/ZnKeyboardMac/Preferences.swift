import Foundation
import Security

/// Where requests go: Google Gemini's built-in endpoint, or any OpenAI-compatible server
/// (OpenAI, DeepSeek, OpenRouter…). Each keeps its own key and model.
enum Provider: String, CaseIterable, Identifiable {
    case gemini
    case openAICompatible = "openai"

    var id: String { rawValue }
    var displayName: String { self == .gemini ? "Google Gemini" : L.openAICompatible }
    fileprivate var keychainAccount: String { self == .gemini ? "gemini-api-key" : "openai-api-key" }
}

/// Endpoints the OpenAI-compatible provider offers without typing an address.
enum APIPreset: String, CaseIterable, Identifiable {
    case deepseek
    case custom

    var id: String { rawValue }
    var displayName: String { self == .deepseek ? "DeepSeek" : L.customPreset }
    /// nil for custom: the typed address is used.
    var baseURL: String? { self == .deepseek ? "https://api.deepseek.com" : nil }
}

/// Settings that persist across launches. API keys live in the Keychain, the rest in UserDefaults.
enum Preferences {
    static let defaultModel = "gemini-3.5-flash-lite"
    // The OpenAI-compatible provider starts on the DeepSeek preset; a custom address starts here.
    static let defaultOpenAIBaseURL = "https://api.openai.com/v1"
    static let defaultOpenAIModel = "deepseek-flash"
    private static let providerKey = "provider"
    private static let modelKey = "geminiModel"
    private static let openAIModelKey = "openAIModel"
    private static let openAIBaseURLKey = "openAIBaseURL"
    private static let presetKey = "apiPreset"
    private static let targetKey = "translateTarget"
    private static let uiLanguageKey = "uiLanguage"
    private static let caretToolbarKey = "caretToolbar"
    private static let clickOutsideKey = "screenshotClickOutsideCloses"

    static var provider: Provider {
        get { Provider(rawValue: UserDefaults.standard.string(forKey: providerKey) ?? "") ?? .gemini }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: providerKey) }
    }

    /// The 润色 | AI 翻译 buttons next to selected text. Off by default; the shortcuts work without it.
    static var caretToolbar: Bool {
        get { UserDefaults.standard.object(forKey: caretToolbarKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: caretToolbarKey) }
    }

    /// Clicking anywhere outside the screenshot translation card closes it. On by default.
    static var screenshotClickOutsideCloses: Bool {
        get { UserDefaults.standard.object(forKey: clickOutsideKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: clickOutsideKey) }
    }

    /// "system", "zh" or "en".
    static var uiLanguage: String {
        get { UserDefaults.standard.string(forKey: uiLanguageKey) ?? "system" }
        set { UserDefaults.standard.set(newValue, forKey: uiLanguageKey) }
    }

    /// The model for [provider]. Gemini falls back to the default unless a Lite model is saved.
    static func model(for provider: Provider) -> String {
        switch provider {
        case .gemini:
            let stored = UserDefaults.standard.string(forKey: modelKey) ?? defaultModel
            return GeminiModels.isLite(stored) ? stored : defaultModel
        case .openAICompatible:
            let stored = UserDefaults.standard.string(forKey: openAIModelKey)?.trimmingCharacters(in: .whitespaces) ?? ""
            return stored.isEmpty ? defaultOpenAIModel : stored
        }
    }

    static func setModel(_ model: String, for provider: Provider) {
        UserDefaults.standard.set(model.trimmingCharacters(in: .whitespaces), forKey: provider == .gemini ? modelKey : openAIModelKey)
    }

    /// Before presets the address was typed, so DeepSeek's address (or none yet) reads as the
    /// DeepSeek preset and anything else as custom.
    static var apiPreset: APIPreset {
        get {
            if let stored = APIPreset(rawValue: UserDefaults.standard.string(forKey: presetKey) ?? "") { return stored }
            let typed = UserDefaults.standard.string(forKey: openAIBaseURLKey)?.trimmingCharacters(in: .whitespaces) ?? ""
            return typed.isEmpty || typed.contains("api.deepseek.com") ? .deepseek : .custom
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: presetKey) }
    }

    /// The address the OpenAI-compatible provider calls: the preset's, or the typed one.
    static var compatibleBaseURL: String { apiPreset.baseURL ?? openAIBaseURL }

    /// The typed address, used by the custom preset.
    static var openAIBaseURL: String {
        get {
            let stored = UserDefaults.standard.string(forKey: openAIBaseURLKey)?.trimmingCharacters(in: .whitespaces) ?? ""
            return stored.isEmpty ? defaultOpenAIBaseURL : stored
        }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespaces), forKey: openAIBaseURLKey) }
    }

    /// 0.2.0–0.2.1 had a fixed DeepSeek provider instead of the OpenAI-compatible one: it becomes
    /// the OpenAI-compatible provider pointed at DeepSeek, Keychain key included. The old key is
    /// removed only once it was read, so a denied Keychain prompt keeps it for the next launch.
    static func migrate() {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: providerKey) == "deepseek" else { return }
        let oldKey = Keychain.read(account: "deepseek-api-key")
        if let oldKey, apiKey(for: .openAICompatible).isEmpty { setAPIKey(oldKey, for: .openAICompatible) }
        apiPreset = .deepseek
        setModel(defaultOpenAIModel, for: .openAICompatible)
        provider = .openAICompatible
        if oldKey != nil { Keychain.write("", account: "deepseek-api-key") }
    }

    /// The global shortcut for [action], or its default.
    static func shortcut(for action: ShortcutAction) -> Shortcut {
        guard let data = UserDefaults.standard.data(forKey: "shortcut.\(action.rawValue)"),
              let shortcut = try? JSONDecoder().decode(Shortcut.self, from: data) else { return action.defaultShortcut }
        return shortcut
    }

    static func setShortcut(_ shortcut: Shortcut, for action: ShortcutAction) {
        UserDefaults.standard.set(try? JSONEncoder().encode(shortcut), forKey: "shortcut.\(action.rawValue)")
    }

    static var translateTarget: TranslateLanguage {
        get { Languages.language(code: UserDefaults.standard.string(forKey: targetKey) ?? "EN") }
        set { UserDefaults.standard.set(newValue.code, forKey: targetKey) }
    }

    /// The language screenshot translation reads into; Simplified Chinese until changed.
    static var screenshotTarget: TranslateLanguage {
        get { Languages.language(code: UserDefaults.standard.string(forKey: "screenshotTarget") ?? "ZH") }
        set { UserDefaults.standard.set(newValue.code, forKey: "screenshotTarget") }
    }

    static func apiKey(for provider: Provider) -> String { Keychain.read(account: provider.keychainAccount) ?? "" }

    static func setAPIKey(_ key: String, for provider: Provider) {
        Keychain.write(key.trimmingCharacters(in: .whitespacesAndNewlines), account: provider.keychainAccount)
    }

    /// The client for the selected provider and its key, model and endpoint.
    static func client() throws -> AIClient {
        let provider = provider
        return try AIClient(provider: provider, baseURL: compatibleBaseURL, apiKey: apiKey(for: provider), model: model(for: provider))
    }
}

/// API keys as generic password items, readable only by this app.
enum Keychain {
    private static let service = "dev.zain.znkeyboard.mac"

    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func read(account: String) -> String? {
        var item: CFTypeRef?
        var search = query(account)
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        guard SecItemCopyMatching(search as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String, account: String) {
        SecItemDelete(query(account) as CFDictionary)
        guard !value.isEmpty else { return }
        var item = query(account)
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}

/// Gemini is limited to Flash-Lite 2.5 and newer, as on Android: larger models cost many times more.
enum GeminiModels {
    static func isLite(_ id: String) -> Bool {
        let lower = id.lowercased()
        guard let match = lower.wholeMatch(of: #/gemini-(\d+(?:\.\d+)?)-flash-lite(?:-[a-z0-9-]+)?/#),
              let version = Double(match.1) else { return false }
        return version >= 2.5
    }

    /// Lite models from a /models listing, newest first, without previews whose stable release is listed.
    static func liteModels(from ids: [String]) -> [String] {
        let lite = Set(ids.map { $0.replacingOccurrences(of: "models/", with: "") }.filter(isLite))
        return lite
            .filter { !($0.hasSuffix("-preview") && lite.contains(String($0.dropLast("-preview".count)))) }
            .sorted { version(of: $0) > version(of: $1) || (version(of: $0) == version(of: $1) && $0 < $1) }
    }

    private static func version(of id: String) -> Double {
        Double(id.dropFirst("gemini-".count).prefix { $0 != "-" }) ?? 0
    }
}
