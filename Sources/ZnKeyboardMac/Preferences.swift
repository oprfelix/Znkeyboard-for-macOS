import Foundation
import Security

/// Where requests go: DeepSeek's or Google Gemini's built-in endpoint, or any OpenAI-compatible
/// server at a typed address (OpenAI, OpenRouter…). Each keeps its own key and model.
enum Provider: String, CaseIterable, Identifiable {
    case deepseek
    case gemini
    case openAICompatible = "openai"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .deepseek: "DeepSeek"
        case .gemini: "Google"
        case .openAICompatible: L.openAICompatible
        }
    }
    /// The models offered, as on iOS and Android: one fast, low-cost model for DeepSeek and the
    /// Flash-Lite ones for Google, first the default. Empty for a custom server: its own list.
    var models: [String] {
        switch self {
        case .deepseek: [Preferences.defaultDeepSeekModel]
        case .gemini: [Preferences.defaultModel, "gemini-3.1-flash-lite"]
        case .openAICompatible: []
        }
    }
    fileprivate var keychainAccount: String {
        switch self {
        case .deepseek: "deepseek-api-key"
        case .gemini: "gemini-api-key"
        case .openAICompatible: "openai-api-key"
        }
    }
}

/// Settings that persist across launches. API keys live in the Keychain, the rest in UserDefaults.
enum Preferences {
    static let defaultModel = "gemini-3.5-flash-lite"
    // Where the OpenAI-compatible provider's address starts before the user types their own.
    static let defaultOpenAIBaseURL = "https://api.openai.com/v1"
    static let deepSeekBaseURL = "https://api.deepseek.com"
    static let defaultDeepSeekModel = "deepseek-flash"
    private static let providerKey = "provider"
    private static let modelKey = "geminiModel"
    private static let openAIModelKey = "openAIModel"
    private static let openAIBaseURLKey = "openAIBaseURL"
    private static let deepSeekModelKey = "deepSeekModel"
    // Through 0.4.5 DeepSeek was a preset of the OpenAI-compatible provider, with one shared key.
    private static let legacyPresetKey = "apiPreset"
    private static let legacyPresetDeepSeek = "deepseek"
    private static let deepSeekSplitKey = "deepSeekPresetSplit"
    private static let targetKey = "translateTarget"
    private static let uiLanguageKey = "uiLanguage"
    private static let caretToolbarKey = "caretToolbar"
    private static let automaticUpdatesKey = "automaticUpdateChecks"
    private static let lastUpdateCheckKey = "lastUpdateCheck"
    private static let notifiedUpdateKey = "notifiedUpdate"
    private static let readingToolbarKey = "readingToolbar"
    private static let pinKey = "pinTranslationCard"

    static var provider: Provider {
        get { Provider(rawValue: UserDefaults.standard.string(forKey: providerKey) ?? "") ?? .gemini }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: providerKey) }
    }

    /// The AI 翻译 button next to text selected in a text box. On by default (since 0.4.0).
    static var caretToolbar: Bool {
        get { UserDefaults.standard.object(forKey: caretToolbarKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: caretToolbarKey) }
    }

    /// The 翻译为 button next to text selected while reading (web pages, documents): 划词翻译,
    /// which has no shortcut of its own. On by default (since 0.4.7).
    static var readingToolbar: Bool {
        get { UserDefaults.standard.object(forKey: readingToolbarKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: readingToolbarKey) }
    }

    /// Translation cards (reading, screenshot) stay open on clicks elsewhere. Remembered; off by default.
    static var pinTranslationCard: Bool {
        get { UserDefaults.standard.bool(forKey: pinKey) }
        set { UserDefaults.standard.set(newValue, forKey: pinKey) }
    }

    /// The anonymous daily ping behind the numbers on znkeyboard.2amz.com. On by default.
    /// Set once opening at login was turned on by default; from then on it is the user's choice.
    static var loginItemEnabledOnce: Bool {
        get { UserDefaults.standard.bool(forKey: "loginItemEnabledOnce") }
        set { UserDefaults.standard.set(newValue, forKey: "loginItemEnabledOnce") }
    }

    static var anonymousStats: Bool {
        get { UserDefaults.standard.object(forKey: "anonymousStats") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "anonymousStats") }
    }

    /// A random id made on this Mac for the ping, tied to nothing else.
    static var installID: String {
        if let id = UserDefaults.standard.string(forKey: "installID") { return id }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: "installID")
        return id
    }

    /// Polish and translate runs not yet reported.
    static var pendingUses: Int {
        get { UserDefaults.standard.integer(forKey: "pendingUses") }
        set { UserDefaults.standard.set(max(newValue, 0), forKey: "pendingUses") }
    }

    static var lastPing: Date {
        get { UserDefaults.standard.object(forKey: "lastPing") as? Date ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: "lastPing") }
    }

    /// A daily look for a new release. On by default.
    static var automaticUpdateChecks: Bool {
        get { UserDefaults.standard.object(forKey: automaticUpdatesKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: automaticUpdatesKey) }
    }

    static var lastUpdateCheck: Date {
        get { UserDefaults.standard.object(forKey: lastUpdateCheckKey) as? Date ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: lastUpdateCheckKey) }
    }

    /// The newest version already offered on its own, so each is offered once.
    static var notifiedUpdate: String? {
        get { UserDefaults.standard.string(forKey: notifiedUpdateKey) }
        set { UserDefaults.standard.set(newValue, forKey: notifiedUpdateKey) }
    }

    /// "system", "zh" or "en".
    static var uiLanguage: String {
        get { UserDefaults.standard.string(forKey: uiLanguageKey) ?? "system" }
        set { UserDefaults.standard.set(newValue, forKey: uiLanguageKey) }
    }

    /// The model for [provider]. DeepSeek and Google fall back to their default unless a listed model is saved.
    static func model(for provider: Provider) -> String {
        switch provider {
        case .gemini:
            let stored = UserDefaults.standard.string(forKey: modelKey) ?? ""
            return provider.models.contains(stored) ? stored : defaultModel
        case .deepseek:
            let stored = UserDefaults.standard.string(forKey: deepSeekModelKey)?.trimmingCharacters(in: .whitespaces) ?? ""
            return provider.models.contains(stored) ? stored : defaultDeepSeekModel
        case .openAICompatible:
            // No default: a model ID only means something on the address the user typed.
            return UserDefaults.standard.string(forKey: openAIModelKey)?.trimmingCharacters(in: .whitespaces) ?? ""
        }
    }

    static func setModel(_ model: String, for provider: Provider) {
        let key = switch provider {
        case .deepseek: deepSeekModelKey
        case .gemini: modelKey
        case .openAICompatible: openAIModelKey
        }
        UserDefaults.standard.set(model.trimmingCharacters(in: .whitespaces), forKey: key)
    }

    /// The address the OpenAI-compatible provider calls; the other providers have theirs built in.
    static var openAIBaseURL: String {
        get {
            let stored = UserDefaults.standard.string(forKey: openAIBaseURLKey)?.trimmingCharacters(in: .whitespaces) ?? ""
            return stored.isEmpty ? defaultOpenAIBaseURL : stored
        }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespaces), forKey: openAIBaseURLKey) }
    }

    /// One-time move of the DeepSeek preset to its own provider. 0.2.0–0.2.1 already stored
    /// "deepseek" as the provider, so those setups go through the preset first; the flag keeps a
    /// later launch from reading today's DeepSeek provider as that old one. DeepSeek's address
    /// counts too, typed before presets or under Custom, and so does no address with no preset.
    /// A key that is there but can't be read yet (a denied Keychain prompt) stops the move, and
    /// the old key is cleared only once the new one reads back, so neither can lose it.
    static func migrate() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: deepSeekSplitKey) else { return }
        let compatibleAccount = Provider.openAICompatible.keychainAccount
        let deepSeekAccount = Provider.deepseek.keychainAccount
        if defaults.string(forKey: providerKey) == Provider.deepseek.rawValue {
            let oldKey = Keychain.read(account: deepSeekAccount)
            guard oldKey != nil || !Keychain.exists(account: deepSeekAccount) else { return }
            if let oldKey, apiKey(for: .openAICompatible).isEmpty { setAPIKey(oldKey, for: .openAICompatible) }
            defaults.set(legacyPresetDeepSeek, forKey: legacyPresetKey)
            setModel(defaultDeepSeekModel, for: .openAICompatible)
            provider = .openAICompatible
            if oldKey != nil { Keychain.write("", account: deepSeekAccount) }
        }

        let typed = defaults.string(forKey: openAIBaseURLKey)?.trimmingCharacters(in: .whitespaces) ?? ""
        let onDeepSeek = typed.contains("api.deepseek.com")
            || defaults.string(forKey: legacyPresetKey).map { $0 == legacyPresetDeepSeek } ?? typed.isEmpty
        if onDeepSeek {
            let key = Keychain.read(account: compatibleAccount)
            guard key != nil || !Keychain.exists(account: compatibleAccount) else { return }
            if let key {
                setAPIKey(key, for: .deepseek)
                guard apiKey(for: .deepseek) == key.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
                Keychain.write("", account: compatibleAccount)
            }
            let model = defaults.string(forKey: openAIModelKey) ?? ""
            if model.hasPrefix("deepseek") { setModel(model, for: .deepseek) }
            defaults.removeObject(forKey: openAIModelKey)
            if typed.contains("api.deepseek.com") { defaults.removeObject(forKey: openAIBaseURLKey) }
            if provider == .openAICompatible { provider = .deepseek }
        }
        defaults.removeObject(forKey: legacyPresetKey)
        defaults.set(true, forKey: deepSeekSplitKey)
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

    /// The language translations to read go into, for text selected while reading and for screenshots;
    /// Simplified Chinese until changed. Kept under its 0.2 name.
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
        let baseURL = provider == .deepseek ? deepSeekBaseURL : openAIBaseURL
        return try AIClient(provider: provider, baseURL: baseURL, apiKey: apiKey(for: provider), model: model(for: provider))
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

    /// Whether an item is there, without touching its secret, so a denied read isn't taken for none.
    static func exists(account: String) -> Bool {
        SecItemCopyMatching(query(account) as CFDictionary, nil) == errSecSuccess
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
