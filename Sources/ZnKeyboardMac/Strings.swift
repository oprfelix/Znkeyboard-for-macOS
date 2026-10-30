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
    static var translateShort: String { t("AI 翻译为", "Translate") }
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
    static var needKey: String { t("请先在设置里填写 API Key。", "Add your API key in Settings first.") }
    static var badEndpoint: String {
        t("API 地址无效，请在设置里填写以 https:// 开头的地址。", "The API address is invalid. Enter one starting with https:// in Settings.")
    }
    static var noSelection: String { t("请先选中要处理的文字。", "Select some text first.") }
    static var tooLong: String { t("文字太长，请分段处理（最多 5000 字）。", "The text is too long; do it in parts (5,000 characters max).") }
    static var noChange: String { t("没有需要修改的地方。", "Nothing to change.") }
    static var keyRejected: String { t("请求被拒绝，请检查 API Key 和模型。", "The request was rejected. Check your API key and model.") }
    static var badResponse: String { t("AI 没有返回可用的结果，请再试一次。", "The AI returned nothing usable. Try again.") }
    static func requestFailed(_ code: Int, _ body: String) -> String {
        t("AI 请求失败（\(code)）。", "The AI request failed (\(code)).")
    }
    static var networkFailed: String { t("无法连接 AI 服务，请检查网络和 API 地址。", "Couldn't reach the AI service. Check your connection and API address.") }
    static var needAccessibility: String {
        t("需要「辅助功能」权限才能读取和替换选中的文字。", "ZnKeyboard needs Accessibility access to read and replace selected text.")
    }

    // Settings
    static var settingsTitle: String { t("ZnKeyboard 设置", "ZnKeyboard Settings") }

    static var aiSection: String { t("AI 服务", "AI service") }
    static var provider: String { t("服务商", "Provider") }
    static var openAICompatible: String { t("OpenAI 兼容", "OpenAI compatible") }
    static var apiBaseURL: String { t("API 地址", "API address") }
    static var apiKey: String { t("API Key", "API key") }
    static var apiKeyPlaceholder: String { t("输入 API Key", "Enter your API key") }
    static var modelIDPlaceholder: String { t("输入模型 ID", "Enter a model ID") }
    static var chooseModel: String { t("从列表选择", "Choose from list") }
    static var openAINote: String {
        t("支持 OpenAI、DeepSeek、OpenRouter 等兼容接口，例如 DeepSeek 填 https://api.deepseek.com、模型 deepseek-chat。",
          "Works with OpenAI, DeepSeek, OpenRouter and other compatible APIs, e.g. https://api.deepseek.com with model deepseek-chat.")
    }
    static var save: String { t("保存", "Save") }
    static var keyStored: String { t("已保存在本机钥匙串", "Saved in your Keychain") }
    static var noKeyYet: String { t("还没有 Key？", "No key yet?") }
    static var getKey: String { t("在 Google AI Studio 免费获取", "Get one free in Google AI Studio") }
    static var keyPerProvider: String { t("每个服务商的 Key 分开保存。", "Each provider keeps its own key.") }
    static var model: String { t("模型", "Model") }
    static var recommended: String { t("推荐", "recommended") }
    static var modelNote: String { t("仅提供 Flash-Lite 模型，速度快、费用低。", "Flash-Lite models only: fast and low cost.") }
    static var privacyNote: String {
        t("润色和翻译时，选中的文字会发送给所选的服务商。", "When you polish or translate, the selected text is sent to the selected provider.")
    }

    static var usageSection: String { t("使用", "Usage") }
    static var caretToolbar: String { t("选中文字后显示按钮", "Show buttons on selected text") }
    static var caretToolbarNote: String {
        t("在输入框里选中文字（如 ⌘A 全选）后，旁边出现「润色」和「AI 翻译为」。",
          "Select text in a text box (for example with ⌘A) and Polish and Translate appear beside it.")
    }
    static var polishShortcut: String { t("润色快捷键", "Polish shortcut") }
    static var translateShortcut: String { t("AI 翻译快捷键", "Translate shortcut") }
    static var shortcutsNote: String {
        t("在任意 App 选中文字后按快捷键，确认后替换原文。按钮不出现的 App 也能用。",
          "Select text in any app and press a shortcut, then confirm to replace it. Works even where the buttons don't appear.")
    }

    static var permission: String { t("权限", "Permission") }
    static var accessibility: String { t("辅助功能", "Accessibility") }
    static var granted: String { t("已开启", "On") }
    static var notGranted: String { t("未开启", "Off") }
    static var grant: String { t("去开启", "Turn On…") }
    static var accessibilityNote: String {
        t("用于读取和替换选中的文字。在 系统设置 → 隐私与安全性 → 辅助功能 里打开 ZnKeyboard。",
          "Needed to read and replace selected text. Turn on ZnKeyboard in System Settings → Privacy & Security → Accessibility.")
    }

    static var generalSection: String { t("通用", "General") }
    static var uiLanguage: String { t("界面语言", "Language") }
    static var followSystem: String { t("跟随系统", "System") }
    static var version: String { t("版本", "Version") }
}
