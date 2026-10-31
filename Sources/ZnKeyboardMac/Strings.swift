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
    static var screenshotTranslate: String { t("截图翻译", "Screenshot Translate") }
    static var screenshotTranslateTo: String { t("截图翻译为", "Screenshot to") }
    static var screenshotTarget: String { t("截图翻译成", "Screenshot translates to") }
    static var screenshotTargetNote: String {
        t("截到的文字如果本身就是中文，会翻译成英文。图片只在本机识别，不会上传，只有识别出的文字会发给服务商。",
          "Chinese text is translated into English instead. The image is read on this Mac and never uploaded; only the recognised text goes to the provider.")
    }
    static var originalText: String { t("原文", "Original") }
    static var copyOriginal: String { t("复制原文", "Copy Original") }
    static var copyTranslation: String { t("复制译文", "Copy Translation") }
    static var noTextFound: String { t("截图里没有识别到文字。", "No text found in the screenshot.") }
    static var ocrFailed: String { t("识别文字失败，请再试一次。", "Couldn't read the text. Try again.") }
    static var screenRecording: String { t("屏幕录制", "Screen Recording") }
    static var screenRecordingNote: String { t("只在截图翻译时使用，截图在本机识别。开启后需要重新打开 ZnKeyboard。", "Only for screenshot translate; the screenshot is read on this Mac. Reopen ZnKeyboard after turning it on.") }
    static var relaunch: String { t("重新打开 ZnKeyboard", "Reopen ZnKeyboard") }
    static var needScreenRecording: String {
        t("截图翻译需要「屏幕录制」权限。点「去授权」打开 ZnKeyboard 的开关，然后在设置的「权限」页点「重新打开 ZnKeyboard」。",
          "Screenshot translation needs Screen Recording access. Click Grant Access, turn on ZnKeyboard, then click Reopen ZnKeyboard on the Permission page in Settings.")
    }
    static var retry: String { t("重试", "Try Again") }
    static var regenerate: String { t("重新生成", "Regenerate") }
    static var closeHint: String { t("关闭（esc）", "Close (esc)") }
    static var copyHint: String { t("复制结果（⌘C）", "Copy the result (⌘C)") }
    static var about: String { t("关于 ZnKeyboard", "About ZnKeyboard") }
    static var checkForUpdates: String { t("检查更新…", "Check for Updates…") }
    static func updateAvailable(_ version: String) -> String { t("有新版本 \(version)", "ZnKeyboard \(version) is available") }
    static func updateAvailableNote(_ current: String) -> String {
        t("你正在使用 \(current)。下载后把新版拖进「应用程序」替换即可，设置和 API Key 都会保留。",
          "You have \(current). Download it and drag it into Applications to replace this one; your settings and API key stay.")
    }
    static var download: String { t("下载", "Download") }
    static var later: String { t("以后再说", "Later") }
    static func upToDate(_ current: String) -> String { t("ZnKeyboard \(current) 已是最新版本", "ZnKeyboard \(current) is up to date") }
    static var updateCheckFailed: String { t("无法检查更新", "Couldn't check for updates") }
    static var updateCheckFailedNote: String { t("请检查网络，或到 GitHub 发布页查看最新版本。", "Check your connection, or see the latest release on GitHub.") }
    static var openReleases: String { t("打开发布页", "Open Releases") }
    static var ok: String { t("好", "OK") }

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
        t("需要「辅助功能」权限才能读取和替换选中的文字。点「去授权」，在列表里打开 ZnKeyboard 的开关即可。", "ZnKeyboard needs Accessibility access to read and replace selected text. Click Grant Access and turn on ZnKeyboard.")
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
    static var chooseModel: String { t("选择模型", "Choose a model") }
    static var apiPreset: String { t("接口", "Endpoint") }
    static var customPreset: String { t("自定义", "Custom") }
    static var deepSeekNote: String {
        t("地址已内置，填好 API Key 就能用，国内可直连。润色或翻译时，选中的文字会发给 DeepSeek。",
          "The address is built in, so a key is all you need; fast in mainland China. When you polish or translate, the selected text is sent to DeepSeek.")
    }
    static var openAINote: String {
        t("可接 OpenAI、OpenRouter 等兼容服务，填写对方的 API 地址和模型。润色或翻译时，选中的文字会发给该服务。",
          "Works with OpenAI, OpenRouter and other compatible services: enter their API address and model. When you polish or translate, the selected text is sent to that service.")
    }
    static var keyChecking: String { t("正在验证 API Key…", "Checking the API key…") }
    static var keyWorks: String { t("API Key 可用", "API key works") }
    static var keyInvalid: String { t("API Key 无效或没有权限，请检查是否复制完整、是否已过期。", "This API key was rejected. Check it was copied in full and is still active.") }
    static func keyUnverified(_ reason: String) -> String { t("暂时无法验证 API Key：\(reason)", "Couldn't check the API key: \(reason)") }
    static var regionUnsupported: String {
        t("Gemini 在你所在的地区不可用，请改用 OpenAI 兼容（DeepSeek），或通过代理网络使用。", "Gemini isn't available in your region. Use OpenAI compatible (DeepSeek), or reach Gemini through a proxy.")
    }
    static var getDeepSeekKey: String { t("在 DeepSeek 开放平台获取", "Get one on the DeepSeek platform") }
    static var noKeyYet: String { t("还没有 Key？", "No key yet?") }
    static var getKey: String { t("在 Google AI Studio 免费获取", "Get one free in Google AI Studio") }
    static var model: String { t("模型", "Model") }
    static var recommended: String { t("推荐", "recommended") }
    static var modelNote: String {
        t("只提供速度快、费用低的 Flash-Lite 模型。润色或翻译时，选中的文字会发给 Google Gemini。",
          "Only the fast, low-cost Flash-Lite models. When you polish or translate, the selected text is sent to Google Gemini.")
    }

    static var usageSection: String { t("使用", "Usage") }
    static var caretToolbar: String { t("选中文字后显示按钮", "Show buttons on selected text") }
    static var caretToolbarNote: String {
        t("用鼠标拖选或按 ⌘A 全选后，旁边会出现「润色」和「AI 翻译为」按钮。",
          "Drag over text or press ⌘A, and Polish and Translate buttons appear beside it.")
    }
    static var clickOutsideCloses: String { t("点击空白处关闭截图翻译", "Click outside to close screenshot translation") }
    static var clickOutsideClosesNote: String {
        t("截图翻译的结果卡片显示后，点击卡片以外的任意位置即可关闭，不用点 ✕。",
          "Click anywhere outside the screenshot translation card to close it, instead of clicking ✕.")
    }
    static var shortcutsSection: String { t("快捷键", "Shortcuts") }
    static var polishShortcut: String { t("润色", "Polish") }
    static var translateShortcut: String { t("AI 翻译", "Translate") }
    static var screenshotShortcut: String { t("截图翻译", "Screenshot translate") }
    static var shortcutsNote: String {
        t("选中文字后按快捷键即可，按钮不出现的 App 也能用；截图翻译按下后拖出要翻译的区域。点击快捷键可以修改。",
          "Select text and press a shortcut; it works even where the buttons don't appear. For screenshot translate, drag over the area to translate. Click a shortcut to change it.")
    }
    static var pressShortcut: String { t("按下新快捷键…", "Press keys…") }
    static var shortcutHint: String { t("点击后按下新的组合键，Esc 取消", "Click, then press the new combination; Esc cancels") }
    static var resetDefault: String { t("恢复默认", "Reset") }
    static var needModifier: String { t("需要包含 ⌘、⌥ 或 ⌃ 中的至少一个。", "Include at least one of ⌘, ⌥ or ⌃.") }
    static var shortcutUsedByOther: String { t("另一个功能已在用这个快捷键。", "The other action already uses this shortcut.") }
    static var shortcutTaken: String { t("这个快捷键已被其他 App 占用，换一个试试。", "Another app already uses this shortcut. Try another.") }

    static var permission: String { t("权限", "Permission") }
    static var accessibility: String { t("辅助功能", "Accessibility") }
    static var granted: String { t("已开启", "On") }
    static var notGranted: String { t("未开启", "Off") }
    static var grant: String { t("去授权", "Grant Access…") }
    static var accessibilityNote: String {
        t("用来读取和替换你选中的文字，润色和翻译都需要。", "Reads and replaces the text you select; Polish and Translate need it.")
    }
    static var needAccessibilityMenu: String { t("需要开启辅助功能权限…", "Accessibility Access Needed…") }

    static var generalSection: String { t("通用", "General") }
    static var uiLanguage: String { t("界面语言", "Language") }
    static var followSystem: String { t("跟随系统", "System") }
    static var version: String { t("版本", "Version") }
}
