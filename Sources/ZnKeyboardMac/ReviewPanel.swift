import AppKit
import SwiftUI

/// What the floating panel shows for one request.
final class ReviewModel: ObservableObject {
    enum State: Equatable {
        case loading
        case result(String)
        case error(String, offerSettings: Bool)
    }

    @Published var mode = RewriteMode.polish
    @Published var state = State.loading
    /// Screenshot translation shows the recognised text above the translation.
    @Published var original: String?
    /// Drives the appear animation.
    @Published var shown = false
    /// Whether there is a request to run again (not when the selection couldn't be read).
    @Published var canRetry = false
    var onReplace: (String) -> Void = { _ in }
    var onClose: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onRetry: () -> Void = {}
    var onChangeLanguage: (TranslateLanguage) -> Void = { _ in }
}

/// A small panel near the pointer that takes Return / Esc without pulling focus from the app
/// whose text is being changed. Styled after macOS Writing Tools.
final class ReviewPanelController {
    private let model = ReviewModel()
    /// Set while a fade-out runs; a show in the meantime cancels the pending orderOut.
    private var closing: UUID?
    private lazy var panel: NSPanel = {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 160),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        // The rounded card and its shadow are drawn by SwiftUI; the window itself stays invisible.
        // A window shadow would follow the window's rectangle, which shows around the round card
        // once the card fades in from transparent.
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: ReviewView(model: model))
        return panel
    }()

    struct Actions {
        var replace: (String) -> Void
        var openSettings: () -> Void
        var retry: () -> Void
        var changeLanguage: (TranslateLanguage) -> Void
    }

    func show(mode: RewriteMode, actions: Actions) {
        model.mode = mode
        model.state = .loading
        model.original = nil
        model.canRetry = false
        model.onReplace = actions.replace
        model.onOpenSettings = actions.openSettings
        model.onRetry = actions.retry
        model.onChangeLanguage = actions.changeLanguage
        model.onClose = { [weak self] in self?.close() }
        closing = nil
        panel.alphaValue = 1
        model.shown = false
        place()
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [model] in
            withAnimation(.spring(duration: 0.28, bounce: 0.18)) { model.shown = true }
        }
    }

    /// Back to the spinner for another try, keeping the panel where the user put it.
    func showLoading(mode: RewriteMode) {
        model.mode = mode
        animateResize { $0.state = .loading }
    }

    /// [original]: the recognised text, for screenshot translation.
    func showResult(_ text: String, original: String? = nil) {
        model.canRetry = true
        animateResize {
            $0.original = original
            $0.state = .result(text)
        }
    }

    func showError(_ message: String, offerSettings: Bool = false, canRetry: Bool = false) {
        model.canRetry = canRetry
        animateResize { $0.state = .error(message, offerSettings: offerSettings) }
    }

    /// Fades out; [animated] false hides at once, before focus goes back to the source app.
    func close(animated: Bool = true) {
        guard panel.isVisible else { return }
        guard animated else {
            closing = nil
            panel.orderOut(nil)
            panel.alphaValue = 1
            return
        }
        let token = UUID()
        closing = token
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.closing == token else { return }
            self.closing = nil
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1
        })
    }

    var isVisible: Bool { panel.isVisible && closing == nil }

    /// Top-left corner just below and right of the pointer, kept on screen.
    private func place() {
        resize()
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        var frame = panel.frame
        // The card sits inside a transparent margin that holds its shadow.
        frame.origin = NSPoint(x: mouse.x + 12 - Self.margin, y: mouse.y - 16 - frame.height + Self.margin)
        if let visible = screen?.visibleFrame {
            frame.origin.x = min(max(frame.origin.x, visible.minX + 8 - Self.margin), visible.maxX - frame.width - 8 + Self.margin)
            frame.origin.y = min(max(frame.origin.y, visible.minY + 8 - Self.margin), visible.maxY - frame.height - 8 + Self.margin)
        }
        panel.setFrame(frame, display: true)
    }

    private func animateResize(_ change: (ReviewModel) -> Void) {
        withAnimation(.easeOut(duration: 0.18)) { change(model) }
        resize(animate: true)
    }

    /// Grows or shrinks to the content, keeping the top edge where it was.
    private func resize(animate: Bool = false) {
        guard let content = panel.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let size = content.fittingSize
        var frame = panel.frame
        let top = frame.maxY
        frame.size = NSSize(width: Self.width + 2 * Self.margin, height: min(max(size.height, 96 + 2 * Self.margin), 560 + 2 * Self.margin))
        frame.origin.y = top - frame.height
        panel.setFrame(frame, display: true, animate: animate && panel.isVisible)
    }

    static let width: CGFloat = 460
    /// Transparent space around the card, wide enough that its shadow fades out before the edge.
    static let margin: CGFloat = 40
}

/// Non-activating panels can't become key by default; this one must, to receive Return and Esc.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct ReviewView: View {
    @ObservedObject var model: ReviewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            switch model.state {
            case .loading:
                ShimmerLines()
            case .result(let text):
                if let original = model.original {
                    originalSection(original)
                }
                ScrollView {
                    Text(text)
                        .font(.body)
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 360)
                .fixedSize(horizontal: false, vertical: true)
                if case .read = model.mode {
                    readActions(text)
                } else {
                    resultActions(text)
                }
            case .error(let message, let offerSettings):
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(message)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Spacer()
                    if model.canRetry {
                        Button(action: model.onRetry) { Label(L.retry, systemImage: "arrow.clockwise") }
                    }
                    if offerSettings {
                        Button(L.openSettings, action: model.onOpenSettings)
                            .buttonStyle(.borderedProminent)
                    }
                }
                .controlSize(.regular)
            }
        }
        .padding(16)
        .frame(width: ReviewPanelController.width, alignment: .leading)
        // Blank parts of the card drag the panel; buttons and the selectable text keep their clicks.
        .background(WindowDragArea())
        .modifier(CardBackground(cornerRadius: 18))
        // Like a macOS window shadow: a faint contact edge plus a soft, wide spread.
        .shadow(color: .black.opacity(0.08), radius: 1, y: 0.5)
        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
        .padding(ReviewPanelController.margin)
        .scaleEffect(model.shown ? 1 : 0.96, anchor: .top)
        .opacity(model.shown ? 1 : 0)
    }

    /// Icon, title (with the target language as a menu when translating) and a close button.
    private var header: some View {
        HStack(spacing: 6) {
            switch model.mode {
            case .polish:
                Image(systemName: "sparkles").foregroundStyle(Color.accentColor)
                Text(L.polish).font(.headline)
            case .read(let language):
                Image(systemName: "text.viewfinder").foregroundStyle(Color.accentColor)
                Text(L.screenshotTranslateTo).font(.headline)
                languageMenu(language)
            case .translate(let language):
                Image(systemName: "translate").foregroundStyle(Color.accentColor)
                Text(L.translateShort).font(.headline)
                languageMenu(language)
            }
            Spacer()
            Button(action: model.onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(.quaternary, in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help(L.closeHint)
        }
    }

    /// The target language as a menu; choosing one translates the same text again.
    private func languageMenu(_ language: TranslateLanguage) -> some View {
        Menu {
            ForEach(Languages.all) { option in
                Button {
                    model.onChangeLanguage(option)
                } label: {
                    if option == language {
                        Label("\(option.code) · \(option.displayName)", systemImage: "checkmark")
                    } else {
                        Text("\(option.code) · \(option.displayName)")
                    }
                }
            }
        } label: {
            Text(language.displayName).font(.headline)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(model.state == .loading)
    }

    /// The recognised text, smaller and muted, so the translation stays the focus.
    private func originalSection(_ original: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L.originalText).font(.caption).foregroundStyle(.secondary)
            ScrollView {
                Text(original)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 120)
            .fixedSize(horizontal: false, vertical: true)
            Divider().padding(.top, 4)
        }
    }

    /// Screenshot translation: nothing to replace, so the main action copies the translation.
    private func readActions(_ text: String) -> some View {
        HStack(spacing: 8) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(model.original ?? "", forType: .string)
                model.onClose()
            } label: {
                Label(L.copyOriginal, systemImage: "text.quote")
            }
            Button(action: model.onRetry) {
                Image(systemName: "arrow.clockwise")
            }
            .help(L.regenerate)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                model.onClose()
            } label: {
                HStack(spacing: 6) {
                    Text(L.copyTranslation)
                    Text("↩︎").opacity(0.7)
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .controlSize(.large)
    }

    private func resultActions(_ text: String) -> some View {
        HStack(spacing: 8) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                model.onClose()
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .keyboardShortcut("c", modifiers: .command)
            .help(L.copyHint)
            Button(action: model.onRetry) {
                Image(systemName: "arrow.clockwise")
            }
            .help(L.regenerate)
            Spacer()
            Button {
                model.onReplace(text)
            } label: {
                HStack(spacing: 6) {
                    Text(L.replace)
                    Text("↩︎").opacity(0.7)
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .controlSize(.large)
    }
}

/// Liquid Glass on macOS 26 and later; a material card with a hairline before that.
private struct CardBackground: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(.separator))
        }
    }
}

/// Placeholder lines with a moving highlight while the AI works.
private struct ShimmerLines: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach([1.0, 0.92, 0.6], id: \.self) { fraction in
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(.quaternary)
                        .frame(width: proxy.size.width * fraction)
                        .overlay {
                            LinearGradient(
                                colors: [.clear, Color.accentColor.opacity(0.35), .clear],
                                startPoint: .leading, endPoint: .trailing
                            )
                            .frame(width: proxy.size.width * 0.5)
                            .offset(x: proxy.size.width * phase)
                            .mask(RoundedRectangle(cornerRadius: 4, style: .continuous).frame(width: proxy.size.width * fraction))
                        }
                        .clipped()
                }
                .frame(height: 10)
            }
        }
        .padding(.vertical, 4)
        .accessibilityLabel(L.working)
        .onAppear {
            withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1.2 }
        }
    }
}

/// Moves its window when dragged. `isMovableByWindowBackground` alone doesn't reach through the
/// SwiftUI hosting view on newer macOS releases, so the drag is started explicitly.
private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
