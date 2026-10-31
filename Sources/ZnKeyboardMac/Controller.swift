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
        generation += 1
        let current = generation
        request = nil
        // A panel left open from the last request holds focus and would swallow the ⌘C below.
        panel.close(animated: false)
        // The app whose text is selected; the paste must land there.
        let sourceApp = NSWorkspace.shared.frontmostApplication
        let actions = ReviewPanelController.Actions(
            replace: { [weak self] text in
                self?.panel.close(animated: false)
                sourceApp?.activate()
                Task { await TextBridge.replaceSelection(with: text) }
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
        let showPanel = { [weak self] in self?.panel.show(mode: mode, actions: actions) }

        guard TextBridge.isTrusted else {
            TextBridge.requestTrust()
            showPanel()
            panel.showError(L.needAccessibility, offerSettings: true)
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
            // The shortcut's modifiers may still be held; let it go before simulating ⌘C. The panel only
            // appears after the selection is read: once it takes focus, ⌘C would copy from it instead.
            try? await Task.sleep(nanoseconds: 150_000_000)
            let selection = await TextBridge.selectedText()
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

    private func rewrite(mode: RewriteMode, generation current: Int) async {
        guard let request else { return }
        lastMode = mode
        onBusyChange(true)
        defer { if current == generation { onBusyChange(false) } }
        do {
            let result = try await request.client.rewrite(request.core, mode: mode)
            guard current == generation, panel.isVisible else { return }
            // Keep the selection's surrounding spaces and line breaks so the paste fits back in.
            panel.showResult(request.leading + result + request.trailing)
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
