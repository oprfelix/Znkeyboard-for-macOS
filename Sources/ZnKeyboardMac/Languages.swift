import Foundation

/// A translation target. [name] goes into the prompt; [code] is shown on the menu and stored.
struct TranslateLanguage: Hashable, Identifiable {
    let code: String
    let name: String
    let chineseName: String

    var id: String { code }

    /// "英语" or "English", following the UI language.
    var displayName: String { L.isChinese ? chineseName : name }
}

/// Same list and order as ZnKeyboard for Android: by how widely each is used internationally.
enum Languages {
    static let all: [TranslateLanguage] = [
        TranslateLanguage(code: "EN", name: "English", chineseName: "英语"),
        TranslateLanguage(code: "ZH", name: "Simplified Chinese", chineseName: "简体中文"),
        TranslateLanguage(code: "TW", name: "Traditional Chinese", chineseName: "繁体中文"),
        TranslateLanguage(code: "ES", name: "Spanish", chineseName: "西班牙语"),
        TranslateLanguage(code: "FR", name: "French", chineseName: "法语"),
        TranslateLanguage(code: "AR", name: "Arabic", chineseName: "阿拉伯语"),
        TranslateLanguage(code: "RU", name: "Russian", chineseName: "俄语"),
        TranslateLanguage(code: "PT", name: "Portuguese", chineseName: "葡萄牙语"),
        TranslateLanguage(code: "DE", name: "German", chineseName: "德语"),
        TranslateLanguage(code: "JA", name: "Japanese", chineseName: "日语"),
        TranslateLanguage(code: "KO", name: "Korean", chineseName: "韩语"),
        TranslateLanguage(code: "ID", name: "Indonesian", chineseName: "印尼语"),
        TranslateLanguage(code: "VI", name: "Vietnamese", chineseName: "越南语"),
        TranslateLanguage(code: "TH", name: "Thai", chineseName: "泰语"),
    ]

    static func language(code: String) -> TranslateLanguage {
        all.first { $0.code == code } ?? all[0]
    }
}
