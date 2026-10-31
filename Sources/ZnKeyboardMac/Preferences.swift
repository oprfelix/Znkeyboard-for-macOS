import Foundation
import Security

/// Where requests go: Google Gemini or DeepSeek, both through their OpenAI-compatible endpoint.
/// Each keeps its own key.
enum Provider: String, CaseIterable, Identifiable {
    case gemini
    case deepseek

    var id: String { rawValue }
    var displayName: String { self == .gemini ? "Google Gemini" : "DeepSeek" }
    var baseURL: URL {
        URL(string: self == .gemini ? "https://generativelanguage.googleapis.com/v1beta/openai" : "https://api.deepseek.com")!
    }
    fileprivate var keychainAccount: String { self == .gemini ? "gemini-api-key" : "deepseek-api-key" }
}

/// Settings that persist across launches. API keys live in the Keychain, the rest in UserDefaults.
enum Preferences {
    static let defaultModel = "gemini-3.5-flash-lite"
    static let deepSeekModel = "deepseek-chat"
    private static let providerKey = "provider"
    private static let modelKey = "geminiModel"
    private static let targetKey = "translateTarget"
    private static let uiLanguageKey = "uiLanguage"
    private static let caretToolbarKey = "caretToolbar"

    static var provider: Provider {
        get { Provider(rawValue: UserDefaults.standard.string(forKey: providerKey) ?? "") ?? .gemini }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: providerKey) }
    }

    /// The 润色 | AI 翻译 buttons next to selected text. On by default.
    static var caretToolbar: Bool {
        get { UserDefaults.standard.object(forKey: caretToolbarKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: caretToolbarKey) }
    }

    /// "system", "zh" or "en".
    static var uiLanguage: String {
        get { UserDefaults.standard.string(forKey: uiLanguageKey) ?? "system" }
        set { UserDefaults.standard.set(newValue, forKey: uiLanguageKey) }
    }

    /// The model for [provider]. Gemini falls back to the default unless a Lite model is saved;
    /// DeepSeek always uses deepseek-chat.
    static func model(for provider: Provider) -> String {
        switch provider {
        case .gemini:
            let stored = UserDefaults.standard.string(forKey: modelKey) ?? defaultModel
            return GeminiModels.isLite(stored) ? stored : defaultModel
        case .deepseek:
            return deepSeekModel
        }
    }

    static func setGeminiModel(_ model: String) {
        UserDefaults.standard.set(model.trimmingCharacters(in: .whitespaces), forKey: modelKey)
    }

    /// 0.1.0 offered a free-form OpenAI-compatible provider. One pointed at DeepSeek becomes the
    /// DeepSeek provider with its key; any other falls back to Gemini.
    static func migrate() {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: providerKey) == "openai" else { return }
        let baseURL = defaults.string(forKey: "openAIBaseURL") ?? ""
        // Read fails if the Keychain prompt is denied; the old key then stays for the next launch.
        let oldKey = Keychain.read(account: "openai-api-key")
        if baseURL.contains("api.deepseek.com") {
            if apiKey(for: .deepseek).isEmpty, let oldKey { setAPIKey(oldKey, for: .deepseek) }
            provider = .deepseek
        } else {
            provider = .gemini
        }
        if oldKey != nil { Keychain.write("", account: "openai-api-key") }
        defaults.removeObject(forKey: "openAIBaseURL")
        defaults.removeObject(forKey: "openAIModel")
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

    static func apiKey(for provider: Provider) -> String { Keychain.read(account: provider.keychainAccount) ?? "" }

    static func setAPIKey(_ key: String, for provider: Provider) {
        Keychain.write(key.trimmingCharacters(in: .whitespacesAndNewlines), account: provider.keychainAccount)
    }

    /// The client for the selected provider and its key and model.
    static func client() -> AIClient {
        let provider = provider
        return AIClient(provider: provider, apiKey: apiKey(for: provider), model: model(for: provider))
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
