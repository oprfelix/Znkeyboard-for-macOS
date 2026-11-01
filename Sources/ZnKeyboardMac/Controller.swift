import AppKit

/// One shortcut press: read the selection, ask the AI, show the result, and replace on Return.
/// The card can run the same text again (↻) or translate it into another language.
@MainActor
final class Controller {
    private let panel = ReviewPanelController()
    private var generation = 0
    /// The text being worked on, kept so ↻ and the language menu don't read the selection again.
    private var request: (leading: String, core: String, trailing: String, client: AIClient)?
    var openSettings: () -> Void = {}
    /// The menu bar icon fills in while a request is running.
    var onBusyChange: (Bool) -> Void = { _ in }

    var isPanelVisible: Bool { panel.isVisible }

    func run(_ mode: RewriteMode) {
        CaretLog.note("shortcut pressed (#\(generation + 1))")
        generation += 1
        let current = generation
        request = nil
        // A panel left open from the last request holds focus and would swallow the ⌘C below.
        panel.close(animated: false)
        // The app whose text is selected; the paste must land there.
        let sourceApp = NSWorkspace.shared.frontmostApplication
        let actions = ReviewPanelController.Actions(
            replace: { [weak self] text in
                let original = self?.request.map { $0.leading + $0.core + $0.trailing } ?? ""
                self?.panel.close(animated: false)
                sourceApp?.activate()
                Task { await TextBridge.replaceSelection(original, with: text) }
            },
            openSettings: { [weak self] in
                self?.panel.close()
                self?.openSettings()
            },
            retry: { [weak self] in self?.rerun(mode: nil) },
            changeLanguage: { [weak self] language in
                Preferences.translateTarget = language
                self?.rerun(mode: .translate(language))
            }
        )
        // Beside the selection when the app says where it is (⌘A leaves the pointer anywhere).
        let anchor = sourceApp.flatMap { FocusedField.current(in: $0) }.flatMap { $0.hasSelection ? $0.caretRect : nil }
        let showPanel = { [weak self] in self?.panel.show(mode: mode, actions: actions, anchor: anchor) }

        guard TextBridge.isTrusted else {
            // The button goes straight to System Settings → Accessibility, where ZnKeyboard is listed.
            var grant = actions
            grant.openSettings = { [weak self] in
                self?.panel.close()
                TextBridge.requestTrust()
                TextBridge.openAccessibilitySettings()
            }
            panel.show(mode: mode, actions: grant)
            panel.showError(L.needAccessibility, offerSettings: true, settingsTitle: L.grant)
            return
        }
        let client: AIClient
        do {
            client = try Preferences.client()
        } catch {
            showPanel()
            panel.showError(L.badEndpoint, offerSettings: true)
            return
        }
        guard !client.apiKey.isEmpty else {
            showPanel()
            panel.showError(L.needKey, offerSettings: true)
            return
        }

        Task {
            // The shortcut's modifiers may still be held; let them go before simulating ⌘C. The panel only
            // appears after the selection is read: once it takes focus, ⌘C would copy from it instead.
            CaretLog.note("shortcut #\(current): reading the selection")
            try? await Task.sleep(nanoseconds: 80_000_000)
            await TextBridge.waitForModifiersReleased()
            var selection = await TextBridge.selectedText()
            // Right after ⌘A some apps haven't settled their selection yet: look once more.
            if selection?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true, current == generation {
                try? await Task.sleep(nanoseconds: 250_000_000)
                selection = await TextBridge.selectedText()
            }
            CaretLog.note("shortcut #\(current): \(selection.map { "\($0.count) characters" } ?? "nothing")")
            guard current == generation else { return }
            showPanel()
            guard let selection, !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                panel.showError(L.noSelection)
                return
            }
            let (leading, core, trailing) = Self.splitWhitespace(selection)
            request = (leading, core, trailing, client)
            await rewrite(mode: mode, generation: current)
        }
    }

    /// Screenshot translation: drag over part of the screen, read its text on this Mac, and
    /// translate it to read. Text already in the reading language (Chinese by default) goes to
    /// English instead.
    func runScreenshot() {
        guard !capturing else { return }
        generation += 1
        let current = generation
        request = nil
        panel.close(animated: false)
        let actions = ReviewPanelController.Actions(
            replace: { [weak self] _ in self?.panel.close() },
            openSettings: { [weak self] in
                self?.panel.close()
                ScreenText.openPermissionSettings()
            },
            retry: { [weak self] in self?.rerun(mode: nil) },
            changeLanguage: { [weak self] language in
                Preferences.screenshotTarget = language
                self?.rerun(mode: .read(language))
            }
        )
        let target = Preferences.screenshotTarget

        guard ScreenText.hasPermission else {
            ScreenText.requestPermission()
            panel.show(mode: .read(target), actions: actions)
            panel.showError(L.needScreenRecording, offerSettings: true, settingsTitle: L.grant)
            return
        }
        // Key and address problems are fixed in ZnKeyboard's own settings, before any dragging.
        var settingsActions = actions
        settingsActions.openSettings = { [weak self] in
            self?.panel.close()
            self?.openSettings()
        }
        let client: AIClient
        do {
            client = try Preferences.client()
        } catch {
            panel.show(mode: .read(target), actions: settingsActions)
            panel.showError(L.badEndpoint, offerSettings: true)
            return
        }
        guard !client.apiKey.isEmpty else {
            panel.show(mode: .read(target), actions: settingsActions)
            panel.showError(L.needKey, offerSettings: true)
            return
        }

        capturing = true
        Task {
            let image = await ScreenText.captureRegion()
            capturing = false
            guard let image, current == generation else { return }
            var mode = RewriteMode.read(target)
            panel.show(mode: mode, actions: actions)
            let text: String
            do {
                text = try await ScreenText.recognize(image).trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                guard current == generation else { return }
                panel.showError(L.ocrFailed)
                return
            }
            guard current == generation else { return }
            guard !text.isEmpty else {
                panel.showError(L.noTextFound)
                return
            }
            if ["ZH", "TW"].contains(target.code), ScreenText.isMostlyChinese(text) {
                mode = .read(Languages.language(code: "EN"))
                panel.showLoading(mode: mode)
            }
            request = ("", text, "", client)
            await rewrite(mode: mode, generation: current)
        }
    }

    /// Runs the kept text again: the same mode (nil) or another translation target.
    private func rerun(mode next: RewriteMode?) {
        guard request != nil else { return }
        generation += 1
        let current = generation
        let mode = next ?? lastMode
        panel.showLoading(mode: mode)
        Task { await rewrite(mode: mode, generation: current) }
    }

    private var lastMode = RewriteMode.polish
    /// Set while macOS's screenshot selection is up; another ⇧⌘E then does nothing.
    private var capturing = false

    private func rewrite(mode: RewriteMode, generation current: Int) async {
        guard let request else { return }
        lastMode = mode
        onBusyChange(true)
        defer { if current == generation { onBusyChange(false) } }
        do {
            let result = try await request.client.rewrite(request.core, mode: mode)
            guard current == generation, panel.isVisible else { return }
            if case .read = mode {
                panel.showResult(result, original: request.core)
            } else {
                // Keep the selection's surrounding spaces and line breaks so the paste fits back in.
                panel.showResult(request.leading + result + request.trailing)
            }
        } catch {
            guard current == generation, panel.isVisible else { return }
            let message = (error as? RewriteError)?.errorDescription
                ?? ((error as? URLError) != nil ? L.networkFailed : error.localizedDescription)
            // Key, model or endpoint problems are fixed in Settings; anything else may pass on a retry.
            let fixableInSettings: Bool = switch error as? RewriteError {
            case .missingKey, .badEndpoint, .http(400, _), .http(401, _), .http(403, _), .http(404, _): true
            default: false
            }
            panel.showError(message, offerSettings: fixableInSettings, canRetry: !fixableInSettings)
        }
    }

    /// Splits off leading and trailing whitespace, which the model would drop.
    private static func splitWhitespace(_ text: String) -> (String, String, String) {
        let leading = String(text.prefix { $0.isWhitespace })
        let trailing = String(text.reversed().prefix { $0.isWhitespace }.reversed())
        let core = String(text.dropFirst(leading.count).dropLast(trailing.count))
        return (leading, core, trailing)
    }
}
