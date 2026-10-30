import AppKit

/// One shortcut press: read the selection, ask Gemini, show the result, and replace on Return.
@MainActor
final class Controller {
    private let panel = ReviewPanelController()
    private var generation = 0
    var openSettings: () -> Void = {}

    var isPanelVisible: Bool { panel.isVisible }

    func run(_ mode: RewriteMode) {
        generation += 1
        let current = generation
        // A panel left open from the last request holds focus and would swallow the ⌘C below.
        panel.close()
        let title: String
        switch mode {
        case .polish: title = L.polish
        case .translate(let language): title = L.translateTo(language)
        }
        // The app whose text is selected; the paste must land there.
        let sourceApp = NSWorkspace.shared.frontmostApplication
        let showPanel = { [weak self] in
            self?.panel.show(
                title: title,
                onReplace: { text in
                    self?.panel.close()
                    sourceApp?.activate()
                    Task { await TextBridge.replaceSelection(with: text) }
                },
                onOpenSettings: {
                    self?.panel.close()
                    self?.openSettings()
                }
            )
        }

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
            // The shortcut's ⌥⌘ may still be held; let it go before simulating ⌘C. The panel only
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
            do {
                let result = try await client.rewrite(core, mode: mode)
                guard current == generation, panel.isVisible else { return }
                // Keep the selection's surrounding spaces and line breaks so the paste fits back in.
                panel.showResult(leading + result + trailing)
            } catch {
                guard current == generation, panel.isVisible else { return }
                let message = (error as? RewriteError)?.errorDescription
                    ?? ((error as? URLError) != nil ? L.networkFailed : error.localizedDescription)
                // Key, model or endpoint problems are fixed in Settings.
                let fixableInSettings: Bool = switch error as? RewriteError {
                case .missingKey, .badEndpoint, .http(400, _), .http(401, _), .http(403, _), .http(404, _): true
                default: false
                }
                panel.showError(message, offerSettings: fixableInSettings)
            }
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
