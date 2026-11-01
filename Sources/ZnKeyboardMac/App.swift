import AppKit
import Carbon.HIToolbox
import SwiftUI

@main
enum Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

/// Menu bar item, global shortcuts, and the settings window. No Dock icon (LSUIElement).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let controller = Controller()
    private let caretToolbar = CaretToolbar()
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.migrate()
        installEditMenu()
        controller.openSettings = { [weak self] in self?.showSettings() }
        controller.onBusyChange = { [weak self] busy in self?.statusItem?.button?.image = MenuBarIcon.image(busy: busy) }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = MenuBarIcon.image()
        item.button?.toolTip = "ZnKeyboard"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        CaretLog.noteLaunch()
        for action in ShortcutAction.allCases {
            let ok = registerHotKey(action, Preferences.shortcut(for: action))
            CaretLog.note("shortcut \(action.rawValue) \(Preferences.shortcut(for: action).display) registered: \(ok)")
        }

        caretToolbar.isSuspended = { [weak self] in self?.controller.isPanelVisible ?? false }
        caretToolbar.onPolish = { [weak self] in self?.controller.run(.polish) }
        caretToolbar.onTranslate = { [weak self] in self?.controller.run(.translate(Preferences.translateTarget)) }
        caretToolbar.start()

        // First run: nothing works without a key and Accessibility, so start where they're set.
        if Preferences.apiKey(for: Preferences.provider).isEmpty || !TextBridge.isTrusted { showSettings() }
    }

    @discardableResult
    private func registerHotKey(_ action: ShortcutAction, _ shortcut: Shortcut) -> Bool {
        HotKeys.shared.register(id: action.hotKeyID, shortcut: shortcut) { [weak self] in
            switch action {
            case .polish: self?.controller.run(.polish)
            case .translate: self?.controller.run(.translate(Preferences.translateTarget))
            case .screenshot: self?.controller.runScreenshot()
            }
        }
    }

    /// Switches [action] to [shortcut] (its default when nil). On failure the old one stays.
    private func applyShortcut(_ action: ShortcutAction, _ shortcut: Shortcut?) -> ShortcutResult {
        let next = shortcut ?? action.defaultShortcut
        if action.others.contains(where: { next.collides(with: Preferences.shortcut(for: $0)) }) { return .usedByOther }
        let previous = Preferences.shortcut(for: action)
        guard registerHotKey(action, next) else {
            registerHotKey(action, previous)
            return .taken
        }
        Preferences.setShortcut(next, for: action)
        return .ok(next)
    }

    /// Rebuilt on every open so the translate item names the current language.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !TextBridge.isTrusted {
            let grant = NSMenuItem(title: L.needAccessibilityMenu, action: #selector(grantAccessibility), keyEquivalent: "")
            grant.image = Self.symbol("exclamationmark.triangle.fill")
            menu.addItem(grant)
            menu.addItem(.separator())
        }

        let polish = NSMenuItem(title: L.polishSelection, action: #selector(polish), keyEquivalent: "")
        polish.image = Self.symbol("sparkles")
        Self.showShortcut(Preferences.shortcut(for: .polish), on: polish)
        menu.addItem(polish)

        let target = Preferences.translateTarget
        let translate = NSMenuItem(title: L.translateTo(target), action: #selector(translate), keyEquivalent: "")
        translate.image = Self.symbol("translate")
        Self.showShortcut(Preferences.shortcut(for: .translate), on: translate)
        menu.addItem(translate)

        let screenshot = NSMenuItem(title: L.screenshotTranslate, action: #selector(screenshotTranslate), keyEquivalent: "")
        screenshot.image = Self.symbol("text.viewfinder")
        Self.showShortcut(Preferences.shortcut(for: .screenshot), on: screenshot)
        menu.addItem(screenshot)

        let languages = NSMenu()
        for language in Languages.all {
            let item = NSMenuItem(title: "\(language.code) · \(language.displayName)", action: #selector(chooseLanguage(_:)), keyEquivalent: "")
            item.representedObject = language.code
            item.state = language == target ? .on : .off
            languages.addItem(item)
        }
        let languagesItem = NSMenuItem(title: L.translateMenu, action: nil, keyEquivalent: "")
        languagesItem.image = Self.symbol("globe")
        languagesItem.submenu = languages
        menu.addItem(languagesItem)

        menu.addItem(.separator())
        let settings = NSMenuItem(title: L.settings, action: #selector(openSettings), keyEquivalent: ",")
        settings.image = Self.symbol("gearshape")
        menu.addItem(settings)
        let updates = NSMenuItem(title: L.checkForUpdates, action: #selector(checkForUpdates), keyEquivalent: "")
        updates.image = Self.symbol("arrow.down.circle")
        menu.addItem(updates)
        let about = NSMenuItem(title: L.about, action: #selector(showAbout), keyEquivalent: "")
        about.image = Self.symbol("info.circle")
        menu.addItem(about)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: L.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.image = Self.symbol("power")
        menu.addItem(quit)
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) && item.action != nil { item.target = self }
        for item in languages.items { item.target = self }
    }

    /// Shows a global shortcut beside its menu item; keys without a single character show none.
    private static func showShortcut(_ shortcut: Shortcut, on item: NSMenuItem) {
        guard shortcut.key.count == 1 else { return }
        item.keyEquivalent = shortcut.key.lowercased()
        var mask: NSEvent.ModifierFlags = []
        if shortcut.modifiers & cmdKey != 0 { mask.insert(.command) }
        if shortcut.modifiers & optionKey != 0 { mask.insert(.option) }
        if shortcut.modifiers & controlKey != 0 { mask.insert(.control) }
        if shortcut.modifiers & shiftKey != 0 { mask.insert(.shift) }
        item.keyEquivalentModifierMask = mask
    }

    // Menu clicks happen while the menu has focus; give the source app a moment to take it back.
    @objc private func polish() { runAfterMenuCloses(.polish) }

    @objc private func translate() { runAfterMenuCloses(.translate(Preferences.translateTarget)) }

    @objc private func chooseLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        Preferences.translateTarget = Languages.language(code: code)
    }

    @objc private func openSettings() { showSettings() }

    @objc private func grantAccessibility() {
        TextBridge.requestTrust()
        TextBridge.openAccessibilitySettings()
    }

    private static func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    @objc private func checkForUpdates() { Updates.check() }

    /// Waits for the menu to close so it isn't in the screenshot.
    @objc private func screenshotTranslate() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.controller.runScreenshot() }
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSMutableAttributedString(string: "oprfelix.github.io/znkeyboard", attributes: [
            .link: URL(string: "https://oprfelix.github.io/znkeyboard/")!,
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
        ])
        credits.setAlignment(.center, range: NSRange(location: 0, length: credits.length))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }


    private func runAfterMenuCloses(_ mode: RewriteMode) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.controller.run(mode) }
    }

    private func showSettings() {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView(
                // The window title is the open page's name, set by SettingsView.
                onChange: {},
                applyShortcut: { [weak self] action, shortcut in self?.applyShortcut(action, shortcut) ?? .taken }
            ))
            hosting.sizingOptions = .preferredContentSize
            let window = NSWindow(contentViewController: hosting)
            window.title = L.settingsTitle
            // The sidebar runs up under the title bar, as in System Settings; the page title shows in the toolbar.
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        // A menu-bar-only app is often refused activation, leaving the window behind others. Being a
        // regular app (with a Dock icon) while settings are open brings it to the front reliably.
        NSApp.setActivationPolicy(.regular)
        // After the status menu has finished closing, or the activation is lost to it.
        DispatchQueue.main.async { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.settingsWindow?.makeKeyAndOrderFront(nil)
            self?.settingsWindow?.orderFrontRegardless()
            NotificationCenter.default.post(name: .settingsShown, object: nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === settingsWindow else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    /// Clicking the Dock icon while settings are open brings them back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    /// A menu-bar app has no main menu, so ⌘V and friends would not work in the settings fields.
    private func installEditMenu() {
        let main = NSMenu()
        // While settings are open the app shows a menu bar; its first menu is the app menu.
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
}
