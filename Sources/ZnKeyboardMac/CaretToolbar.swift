import AppKit
import SwiftUI

/// Shows 润色 | AI 翻译为 [EN ▾] next to text the user selects in an editable field. Keyboard
/// selections (⌘A, ⇧-arrows) are found through Accessibility and the toolbar sits under them;
/// mouse selections (drag, double or triple click) put it at the pointer, since browsers often
/// don't report where a mouse selection is. Nothing is read or sent until a button is clicked.
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
    private var monitors: [Any] = []
    private var mouseDownPoint: NSPoint?
    /// Set while the toolbar shows for a mouse selection; typing, clicking or switching apps ends it.
    private var mouseAnchorPID: pid_t?

    private static let pollInterval: TimeInterval = 0.3
    /// How long a selection must hold still (mid-drag it keeps changing) before the toolbar appears.
    private static let settleDelay: TimeInterval = 0.25
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
        // Events in other apps only; clicks on the toolbar itself never arrive here.
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
                MainActor.assumeIsolated { self?.mouseDown() }
            },
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
                MainActor.assumeIsolated { self?.mouseUp(clickCount: event.clickCount) }
            },
            NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
                MainActor.assumeIsolated { self?.endMouseAnchor() }
            },
        ].compactMap { $0 }
    }

    private func mouseDown() {
        mouseDownPoint = NSEvent.mouseLocation
        endMouseAnchor()
    }

    /// A drag, double click or triple click in an editable field likely selected text there.
    private func mouseUp(clickCount: Int) {
        let point = NSEvent.mouseLocation
        let dragged = mouseDownPoint.map { hypot($0.x - point.x, $0.y - point.y) >= 6 } ?? false
        guard dragged || clickCount >= 2 else { return }
        // Let the app finish updating its selection first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, Preferences.caretToolbar, TextBridge.isTrusted, !self.isSuspended(),
                  let app = NSWorkspace.shared.frontmostApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            self.enableAccessibility(for: app)
            let state = FocusedField.selectionState(in: app)
            CaretLog.note("mouse selection: \(state)")
            guard state == .selected || state == .unknown else { return }
            self.mouseAnchorPID = app.processIdentifier
            self.model.language = Preferences.translateTarget.code
            self.show(atPointer: point)
        }
    }

    private func endMouseAnchor() {
        guard mouseAnchorPID != nil else { return }
        mouseAnchorPID = nil
        hide()
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
        if let pid = mouseAnchorPID {
            // A mouse-anchored toolbar stays until the user moves on; switching apps counts.
            if pid != app.processIdentifier { endMouseAnchor() }
            return
        }
        guard let field = FocusedField.current(in: app), field.hasSelection else {
            reset()
            return
        }
        // A changing selection (dragging, extending with ⇧) hides the toolbar until it settles.
        let caret = field.caretRect
        let signature = "\(app.processIdentifier)|\(field.signature)|\(Int(caret.minX)),\(Int(caret.minY))"
        if signature != lastSignature {
            lastSignature = signature
            unchangedSince = Date()
            hide()
            return
        }
        guard Date().timeIntervalSince(unchangedSince) >= Self.settleDelay, !panel.isVisible else { return }
        model.language = Preferences.translateTarget.code
        show(below: caret)
    }

    private func reset() {
        lastSignature = ""
        mouseAnchorPID = nil
        hide()
    }

    /// Just below and right of where the mouse selection ended.
    private func show(atPointer point: NSPoint) {
        place(NSRect(x: point.x, y: point.y - 4, width: 1, height: 8))
    }

    private func show(below caret: NSRect) { place(caret) }

    /// Just below [anchor]'s end; above it when there is no room below.
    private func place(_ caret: NSRect) {
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
