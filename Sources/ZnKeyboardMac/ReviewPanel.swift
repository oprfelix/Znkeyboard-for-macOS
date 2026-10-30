import AppKit
import SwiftUI

/// What the floating panel shows for one request.
final class ReviewModel: ObservableObject {
    enum State {
        case loading
        case result(String)
        case error(String, offerSettings: Bool)
    }

    @Published var title = ""
    @Published var state = State.loading
    var onReplace: (String) -> Void = { _ in }
    var onClose: () -> Void = {}
    var onOpenSettings: () -> Void = {}
}

/// A small panel near the pointer that takes Return / Esc without pulling focus from the app
/// whose text is being changed.
final class ReviewPanelController {
    private let model = ReviewModel()
    private lazy var panel: NSPanel = {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 160),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        // The rounded card is drawn by SwiftUI; the window itself stays invisible.
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: ReviewView(model: model))
        return panel
    }()

    func show(title: String, onReplace: @escaping (String) -> Void, onOpenSettings: @escaping () -> Void) {
        model.title = title
        model.state = .loading
        model.onReplace = onReplace
        model.onOpenSettings = onOpenSettings
        model.onClose = { [weak self] in self?.close() }
        place()
        panel.makeKeyAndOrderFront(nil)
    }

    func showResult(_ text: String) {
        model.state = .result(text)
        resize()
    }

    func showError(_ message: String, offerSettings: Bool = false) {
        model.state = .error(message, offerSettings: offerSettings)
        resize()
    }

    func close() {
        panel.orderOut(nil)
    }

    var isVisible: Bool { panel.isVisible }

    /// Top-left corner just below and right of the pointer, kept on screen.
    private func place() {
        resize()
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        var frame = panel.frame
        frame.origin = NSPoint(x: mouse.x + 12, y: mouse.y - 16 - frame.height)
        if let visible = screen?.visibleFrame {
            frame.origin.x = min(max(frame.origin.x, visible.minX + 8), visible.maxX - frame.width - 8)
            frame.origin.y = min(max(frame.origin.y, visible.minY + 8), visible.maxY - frame.height - 8)
        }
        panel.setFrame(frame, display: true)
    }

    /// Grows or shrinks to the content, keeping the top edge where it was.
    private func resize() {
        guard let content = panel.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let size = content.fittingSize
        var frame = panel.frame
        let top = frame.maxY
        frame.size = NSSize(width: 440, height: min(max(size.height, 96), 520))
        frame.origin.y = top - frame.height
        panel.setFrame(frame, display: true, animate: false)
    }
}

/// Non-activating panels can't become key by default; this one must, to receive Return and Esc.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct ReviewView: View {
    @ObservedObject var model: ReviewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.title)
                .font(.headline)
            switch model.state {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L.working).foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button(L.cancel) { model.onClose() }.keyboardShortcut(.cancelAction)
                }
            case .result(let text):
                ScrollView {
                    Text(text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 360)
                .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(L.copy) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        model.onClose()
                    }
                    .keyboardShortcut("c", modifiers: .command)
                    Spacer()
                    Button(L.cancel) { model.onClose() }.keyboardShortcut(.cancelAction)
                    Button(L.replace) { model.onReplace(text) }.keyboardShortcut(.defaultAction)
                }
            case .error(let message, let offerSettings):
                Text(message)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    if offerSettings {
                        Button(L.openSettings) { model.onOpenSettings() }
                    }
                    Button(L.cancel) { model.onClose() }.keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(16)
        .frame(width: 440, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator))
    }
}
