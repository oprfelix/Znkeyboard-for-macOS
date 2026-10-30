import Foundation

/// UI text in Chinese when the system's first language is Chinese, English otherwise.
enum L {
    /// Follows the setting; "system" uses the Mac's first preferred language.
    static var isChinese: Bool {
        switch Preferences.uiLanguage {
        case "zh": true
        case "en": false
        default: Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
        }
    }

    private static func t(_ zh: String, _ en: String) -> String { isChinese ? zh : en }

    // Menu
    static var polish: String { t("润色", "Polish") }
    static func translateTo(_ language: TranslateLanguage) -> String {
        t("AI 翻译为 \(language.displayName)", "Translate to \(language.displayName)")
    }
    static var polishSelection: String { t("润色所选文字", "Polish Selected Text") }
    static var translateMenu: String { t("翻译成", "Translate To") }
    static var settings: String { t("设置…", "Settings…") }
    static var quit: String { t("退出 ZnKeyboard", "Quit ZnKeyboard") }

    // Review panel
    static var working: String { t("处理中…", "Working…") }
    static var replace: String { t("替换", "Replace") }
    static var copy: String { t("复制", "Copy") }
    static var cancel: String { t("取消", "Cancel") }
    static var openSettings: String { t("打开设置", "Open Settings") }

    // Errors
    static var needKey: String { t("请先在设置里填写 Gemini API Key。", "Add your Gemini API key in Settings first.") }
    static var noSelection: String { t("请先选中要处理的文字。", "Select some text first.") }
    static var tooLong: String { t("文字太长，请分段处理（最多 5000 字）。", "The text is too long; do it in parts (5,000 characters max).") }
    static var noChange: String { t("没有需要修改的地方。", "Nothing to change.") }
    static var keyRejected: String { t("请求被拒绝，请检查 API Key 和模型。", "The request was rejected. Check your API key and model.") }
    static var badResponse: String { t("AI 没有返回可用的结果，请再试一次。", "The AI returned nothing usable. Try again.") }
    static func requestFailed(_ code: Int, _ body: String) -> String {
        t("AI 请求失败（\(code)）。", "The AI request failed (\(code)).")
    }
    static var networkFailed: String { t("无法连接 Gemini，请检查网络。", "Couldn't reach Gemini. Check your connection.") }
    static var needAccessibility: String {
        t("需要「辅助功能」权限才能读取和替换选中的文字。", "ZnKeyboard needs Accessibility access to read and replace selected text.")
    }

    // Settings
    static var settingsTitle: String { t("ZnKeyboard 设置", "ZnKeyboard Settings") }
    static var uiLanguage: String { t("界面语言", "Language") }
    static var followSystem: String { t("跟随系统", "System") }
    static var apiKeySection: String { t("Gemini API Key", "Gemini API Key") }
    static var apiKeyPlaceholder: String { t("粘贴你的 API Key", "Paste your API key") }
    static var save: String { t("保存", "Save") }
    static var saved: String { t("已保存", "Saved") }
    static var apiKeyNote: String {
        t("Key 保存在系统钥匙串里。润色和翻译的文字会直接发给 Google Gemini。",
          "The key is kept in your Keychain. Text you polish or translate goes straight to Google Gemini.")
    }
    static var getKey: String { t("获取 API Key", "Get an API key") }
    static var model: String { t("模型", "Model") }
    static var recommended: String { t("推荐", "recommended") }
    static var modelNote: String {
        t("只提供 Flash-Lite 模型：速度快、成本低。", "Only Flash-Lite models: fast and low cost.")
    }
    static var refresh: String { t("刷新", "Refresh") }
    static var shortcuts: String { t("快捷键", "Shortcuts") }
    static var shortcutsNote: String {
        t("在任意 App 里选中文字后按快捷键，确认后替换原文。",
          "Select text in any app and press a shortcut; review the result before it replaces the original.")
    }
    static var permission: String { t("权限", "Permission") }
    static var accessibility: String { t("辅助功能", "Accessibility") }
    static var granted: String { t("已允许", "Allowed") }
    static var notGranted: String { t("未允许", "Not allowed") }
    static var grant: String { t("去允许", "Allow…") }
    static var accessibilityNote: String {
        t("在 系统设置 → 隐私与安全性 → 辅助功能 里打开 ZnKeyboard。",
          "Turn on ZnKeyboard in System Settings → Privacy & Security → Accessibility.")
    }
}
