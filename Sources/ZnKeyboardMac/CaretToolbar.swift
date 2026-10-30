import AppKit
import SwiftUI

/// Shows 润色 | AI 翻译为 [EN ▾] next to the caret once typing pauses, in any app that exposes its
/// caret through Accessibility. Nothing is read or sent until a button is clicked.
@MainActor
final class CaretToolbar {
    var onPolish: () -> Void = {}
    var onTranslate: () -> Void = {}
    /// True while the review panel is up; the toolbar stays out of its way.
    var isSuspended: () -> Bool = { false }

    private let model = CaretToolbarModel()
    private var timer: Timer?
    private var lastSignature = ""
    private var unchangedSince = Date()
    private var accessibilityEnabledPIDs = Set<pid_t>()

    private static let pollInterval: TimeInterval = 0.3
    /// How long typing must pause before the toolbar appears.
    private static let idleDelay: TimeInterval = 0.9
    private static let chromiumBrowsers: Set<String> = [
        "com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser", "company.thebrowser.Browser",
        "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
    ]

    private lazy var panel: NSPanel = {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 32),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        model.onPolish = { [weak self] in self?.hide(); self?.onPolish() }
        model.onTranslate = { [weak self] in self?.hide(); self?.onTranslate() }
        model.onChooseLanguage = { [weak self] in self?.chooseLanguage() }
        panel.contentView = FirstClickHostingView(rootView: CaretToolbarView(model: model))
        return panel
    }()

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func hide() {
        if panel.isVisible { panel.orderOut(nil) }
    }

    private func tick() {
        guard Preferences.caretToolbar, TextBridge.isTrusted, !isSuspended(),
              let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            reset()
            return
        }
        enableAccessibility(for: app)
        guard let field = FocusedField.current(in: app) else {
            reset()
            return
        }
        // Any change in text, caret or position counts as typing: hide and restart the wait.
        let caret = field.caretRect
        let signature = "\(app.processIdentifier)|\(field.text.hashValue)|\(field.selection.location)|\(field.selection.length)|\(Int(caret.minX)),\(Int(caret.minY))"
        if signature != lastSignature {
            lastSignature = signature
            unchangedSince = Date()
            hide()
            return
        }
        guard Date().timeIntervalSince(unchangedSince) >= Self.idleDelay, !panel.isVisible else { return }
        model.language = Preferences.translateTarget.code
        show(below: caret)
    }

    private func reset() {
        lastSignature = ""
        hide()
    }

    /// Just below and right of the caret; above it when there is no room below.
    private func show(below caret: NSRect) {
        guard let content = panel.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let size = content.fittingSize
        let screen = NSScreen.screens.first { $0.frame.intersects(caret) }?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        var origin = NSPoint(x: caret.maxX + 6, y: caret.minY - 6 - size.height)
        if origin.y < screen.minY { origin.y = caret.maxY + 6 }
        origin.x = min(max(origin.x, screen.minX + 4), screen.maxX - size.width - 4)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    private func chooseLanguage() {
        let menu = NSMenu()
        let current = Preferences.translateTarget
        for language in Languages.all {
            let item = NSMenuItem(title: "\(language.code) · \(language.displayName)", action: #selector(LanguageMenuTarget.choose(_:)), keyEquivalent: "")
            item.target = LanguageMenuTarget.shared
            item.representedObject = language.code
            item.state = language == current ? .on : .off
            menu.addItem(item)
        }
        LanguageMenuTarget.shared.onChoose = { [weak self] code in
            Preferences.translateTarget = Languages.language(code: code)
            self?.model.language = code
        }
        menu.popUp(positioning: nil, at: NSPoint(x: panel.frame.maxX - 40, y: panel.frame.minY), in: nil)
    }

    /// Chromium browsers and Electron apps build their accessibility tree only when asked to.
    private func enableAccessibility(for app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard accessibilityEnabledPIDs.insert(pid).inserted else { return }
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        if let id = app.bundleIdentifier, Self.chromiumBrowsers.contains(id) {
            AXUIElementSetAttributeValue(element, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
    }
}

final class CaretToolbarModel: ObservableObject {
    @Published var language = "EN"
    var onPolish: () -> Void = {}
    var onTranslate: () -> Void = {}
    var onChooseLanguage: () -> Void = {}
}

private struct CaretToolbarView: View {
    @ObservedObject var model: CaretToolbarModel

    var body: some View {
        HStack(spacing: 2) {
            Button(action: model.onPolish) {
                Label(L.polish, systemImage: "sparkles")
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .contentShape(Rectangle())
            }
            Divider().frame(height: 16)
            Button(action: model.onTranslate) {
                Text(L.translateShort)
                    .padding(.leading, 8)
                    .padding(.trailing, 4)
                    .frame(height: 26)
                    .contentShape(Rectangle())
            }
            Button(action: model.onChooseLanguage) {
                Text("\(model.language) ▾")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(Color(red: 35 / 255, green: 64 / 255, blue: 128 / 255), in: Capsule())
            }
            .padding(.trailing, 4)
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 4)
        .frame(height: 32)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator))
        .fixedSize()
    }
}

/// The app never activates, so the first click must work without first focusing the panel.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class LanguageMenuTarget: NSObject {
    static let shared = LanguageMenuTarget()
    var onChoose: (String) -> Void = { _ in }

    @objc func choose(_ sender: NSMenuItem) {
        if let code = sender.representedObject as? String { onChoose(code) }
    }
}
