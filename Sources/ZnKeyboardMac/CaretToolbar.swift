import AppKit
import Carbon.HIToolbox
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
    /// When ⌘A or ⇧ with an arrow, Home, End or Page key was last pressed. A selection that appears
    /// without one was made by the app (the address bar selecting its URL, Finder's rename, a Save
    /// dialog's file name) and gets no toolbar.
    private var lastSelectionKey = Date.distantPast
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
            NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                MainActor.assumeIsolated {
                    if Self.selectsText(event) { self?.lastSelectionKey = Date() }
                    self?.endMouseAnchor()
                }
            },
        ].compactMap { $0 }
    }

    private static let extendKeys: Set<Int> = [
        kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow, kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown,
    ]

    private static func selectsText(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if Int(event.keyCode) == kVK_ANSI_A, flags == .command { return true }
        return flags.contains(.shift) && extendKeys.contains(Int(event.keyCode))
    }

    private func mouseDown() {
        mouseDownPoint = NSEvent.mouseLocation
        endMouseAnchor()
    }

    /// A drag, double click or triple click in an editable field likely selected text there.
    private func mouseUp(clickCount: Int) {
        let point = NSEvent.mouseLocation
        let start = mouseDownPoint
        mouseDownPoint = nil
        let dragged = start.map { hypot($0.x - point.x, $0.y - point.y) >= 6 } ?? false
        // Screen y grows upward: a drag that ended higher than it began selected the lines below.
        let draggedUp = dragged && (start.map { point.y > $0.y + 6 } ?? false)
        guard dragged || clickCount >= 2 else { return }
        // Let the app finish updating its selection first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, Preferences.caretToolbar, TextBridge.isTrusted, !self.isSuspended(),
                  let app = NSWorkspace.shared.frontmostApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            self.enableAccessibility(for: app)
            // The field must be where the mouse was: an old selection stays put while a scrollbar or
            // title bar is dragged.
            let state = FocusedField.selectionState(in: app, mouseAt: [point, start].compactMap { $0 })
            CaretLog.note("mouse selection: \(state)")
            guard state == .selected || state == .unknown else { return }
            self.mouseAnchorPID = app.processIdentifier
            self.model.language = Preferences.translateTarget.code
            self.show(atPointer: point, above: draggedUp)
        }
    }

    private func endMouseAnchor() {
        guard mouseAnchorPID != nil else { return }
        mouseAnchorPID = nil
        hide()
    }

    /// Set while a fade-out runs; showing again cancels the pending orderOut.
    private var hiding: UUID?

    func hide() {
        guard panel.isVisible, hiding == nil else { return }
        let token = UUID()
        hiding = token
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.hiding == token else { return }
                self.hiding = nil
                self.panel.orderOut(nil)
            }
        })
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
        guard Date().timeIntervalSince(unchangedSince) >= Self.settleDelay, !panel.isVisible || hiding != nil,
              Date().timeIntervalSince(lastSelectionKey) < 2 else { return }
        model.language = Preferences.translateTarget.code
        show(below: caret)
    }

    private func reset() {
        lastSignature = ""
        mouseAnchorPID = nil
        hide()
    }

    /// Beside where the mouse selection ended: below it, or above when the drag went upward, so
    /// the toolbar covers neither the selected lines nor the pointer.
    private func show(atPointer point: NSPoint, above: Bool) {
        place(NSRect(x: point.x, y: point.y - 4, width: 1, height: 8), preferAbove: above)
    }

    private func show(below caret: NSRect) { place(caret, preferAbove: false) }

    /// Next to [caret]'s end, on the preferred side when there is room; fades in.
    private func place(_ caret: NSRect, preferAbove: Bool) {
        guard let content = panel.contentView else { return }
        model.shortcutHints = (Preferences.shortcut(for: .polish).display, Preferences.shortcut(for: .translate).display)
        content.layoutSubtreeIfNeeded()
        let size = content.fittingSize
        let screen = NSScreen.screens.first { $0.frame.intersects(caret) }?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let below = caret.minY - 6 - size.height
        let above = caret.maxY + 6
        var origin = NSPoint(x: caret.maxX + 6, y: preferAbove ? above : below)
        if preferAbove, origin.y + size.height > screen.maxY { origin.y = below }
        if !preferAbove, origin.y < screen.minY { origin.y = above }
        origin.x = min(max(origin.x, screen.minX + 4), screen.maxX - size.width - 4)
        hiding = nil
        let wasVisible = panel.isVisible
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        if !wasVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        // The shadow follows the capsule only once the glass has been drawn.
        DispatchQueue.main.async { [panel] in panel.invalidateShadow() }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 1
        }
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
    /// Shown in the buttons' tooltips, e.g. "⇧⌘R".
    @Published var shortcutHints = ("", "")
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
                    .padding(.horizontal, 10)
                    .frame(height: 26)
            }
            .help("\(L.polish)  \(model.shortcutHints.0)")
            Divider().frame(height: 16)
            HStack(spacing: 4) {
                Button(action: model.onTranslate) {
                    Label(L.translateShort, systemImage: "translate")
                        .padding(.leading, 10)
                        .padding(.trailing, 2)
                        .frame(height: 26)
                }
                .help("\(L.translateShort) \(model.language)  \(model.shortcutHints.1)")
                Button(action: model.onChooseLanguage) {
                    HStack(spacing: 2) {
                        Text(model.language)
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(Color.accentColor, in: Capsule())
                }
                .buttonStyle(PressableStyle(hover: false))
                .help(L.translateMenu)
                .padding(.trailing, 4)
            }
        }
        .buttonStyle(PressableStyle(hover: true))
        .labelStyle(.titleAndIcon)
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 3)
        .frame(height: 32)
        .modifier(PillBackground())
        .fixedSize()
    }
}

/// A plain button with the system's hover and pressed highlight.
private struct PressableStyle: ButtonStyle {
    let hover: Bool

    func makeBody(configuration: Configuration) -> some View {
        PressableBody(configuration: configuration, hover: hover)
    }

    private struct PressableBody: View {
        let configuration: ButtonStyleConfiguration
        let hover: Bool
        @State private var hovering = false

        var body: some View {
            configuration.label
                .contentShape(Capsule())
                .background {
                    if hover {
                        Capsule().fill(.primary.opacity(configuration.isPressed ? 0.14 : hovering ? 0.08 : 0))
                    }
                }
                .opacity(!hover && configuration.isPressed ? 0.8 : 1)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

/// Liquid Glass on macOS 26 and later; a material capsule with a hairline before that.
private struct PillBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.separator))
        }
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
