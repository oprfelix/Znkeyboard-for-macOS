import AppKit

/// One shortcut press: read the selection, ask Gemini, show the result, and replace on Return.
@MainActor
final class Controller {
    private let panel = ReviewPanelController()
    private var generation = 0
    var openSettings: () -> Void = {}

    var isPanelVisible: Bool { panel.isVisible }

    /// [wholeField]: from the caret toolbar, where nothing selected means the whole field.
    func run(_ mode: RewriteMode, wholeField: Bool = false) {
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
        let apiKey = Preferences.apiKey
        guard !apiKey.isEmpty else {
            showPanel()
            panel.showError(L.needKey, offerSettings: true)
            return
        }

        Task {
            // The shortcut's ⌥⌘ may still be held; let it go before simulating ⌘C. The panel only
            // appears after the selection is read: once it takes focus, ⌘C would copy from it instead.
            try? await Task.sleep(nanoseconds: 150_000_000)
            if wholeField { await TextBridge.selectWholeFieldIfNothingSelected() }
            let selection = await TextBridge.selectedText()
            guard current == generation else { return }
            showPanel()
            guard let selection, !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                panel.showError(L.noSelection)
                return
            }
            let (leading, core, trailing) = Self.splitWhitespace(selection)
            do {
                let result = try await GeminiClient(apiKey: apiKey, model: Preferences.model).rewrite(core, mode: mode)
                guard current == generation, panel.isVisible else { return }
                // Keep the selection's surrounding spaces and line breaks so the paste fits back in.
                panel.showResult(leading + result + trailing)
            } catch {
                guard current == generation, panel.isVisible else { return }
                let message = (error as? RewriteError)?.errorDescription
                    ?? ((error as? URLError) != nil ? L.networkFailed : error.localizedDescription)
                panel.showError(message, offerSettings: (error as? RewriteError).map { if case .missingKey = $0 { true } else { false } } ?? false)
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
