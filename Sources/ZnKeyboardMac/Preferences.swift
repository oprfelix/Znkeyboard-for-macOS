import Foundation
import Security

/// Settings that persist across launches. The API key lives in the Keychain, the rest in UserDefaults.
enum Preferences {
    static let defaultModel = "gemini-3.5-flash-lite"
    private static let modelKey = "geminiModel"
    private static let targetKey = "translateTarget"

    /// The saved Gemini model, or the default when none is saved or it is not a Lite model.
    static var model: String {
        get {
            let stored = UserDefaults.standard.string(forKey: modelKey) ?? defaultModel
            return GeminiModels.isLite(stored) ? stored : defaultModel
        }
        set { UserDefaults.standard.set(newValue, forKey: modelKey) }
    }

    static var translateTarget: TranslateLanguage {
        get { Languages.language(code: UserDefaults.standard.string(forKey: targetKey) ?? "EN") }
        set { UserDefaults.standard.set(newValue.code, forKey: targetKey) }
    }

    static var apiKey: String {
        get { Keychain.read() ?? "" }
        set { Keychain.write(newValue.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
}

/// The Gemini API key as a generic password item, readable only by this app.
enum Keychain {
    private static let service = "dev.zain.znkeyboard.mac"
    private static let account = "gemini-api-key"

    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func read() -> String? {
        var item: CFTypeRef?
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        guard SecItemCopyMatching(search as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String) {
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var item = query
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
