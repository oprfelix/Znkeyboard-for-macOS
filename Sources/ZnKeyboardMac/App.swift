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
        installEditMenu()
        controller.openSettings = { [weak self] in self?.showSettings() }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "ZnKeyboard")
        item.button?.image?.isTemplate = true
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        HotKeys.shared.register(id: 1, keyCode: kVK_ANSI_R, modifiers: cmdKey | optionKey) { [weak self] in
            self?.controller.run(.polish)
        }
        HotKeys.shared.register(id: 2, keyCode: kVK_ANSI_T, modifiers: cmdKey | optionKey) { [weak self] in
            self?.controller.run(.translate(Preferences.translateTarget))
        }

        caretToolbar.isSuspended = { [weak self] in self?.controller.isPanelVisible ?? false }
        caretToolbar.onPolish = { [weak self] in self?.controller.run(.polish) }
        caretToolbar.onTranslate = { [weak self] in self?.controller.run(.translate(Preferences.translateTarget)) }
        caretToolbar.start()

        // First run: nothing works without a key, so start where it goes.
        if Preferences.apiKey(for: Preferences.provider).isEmpty { showSettings() }
    }

    /// Rebuilt on every open so the translate item names the current language.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let polish = NSMenuItem(title: L.polishSelection, action: #selector(polish), keyEquivalent: "r")
        polish.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(polish)

        let target = Preferences.translateTarget
        let translate = NSMenuItem(title: L.translateTo(target), action: #selector(translate), keyEquivalent: "t")
        translate.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(translate)

        let languages = NSMenu()
        for language in Languages.all {
            let item = NSMenuItem(title: "\(language.code) · \(language.displayName)", action: #selector(chooseLanguage(_:)), keyEquivalent: "")
            item.representedObject = language.code
            item.state = language == target ? .on : .off
            languages.addItem(item)
        }
        let languagesItem = NSMenuItem(title: L.translateMenu, action: nil, keyEquivalent: "")
        languagesItem.submenu = languages
        menu.addItem(languagesItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L.settings, action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: L.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
        for item in languages.items { item.target = self }
    }

    // Menu clicks happen while the menu has focus; give the source app a moment to take it back.
    @objc private func polish() { runAfterMenuCloses(.polish) }

    @objc private func translate() { runAfterMenuCloses(.translate(Preferences.translateTarget)) }

    @objc private func chooseLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        Preferences.translateTarget = Languages.language(code: code)
    }

    @objc private func openSettings() { showSettings() }

    private func runAfterMenuCloses(_ mode: RewriteMode) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.controller.run(mode) }
    }

    private func showSettings() {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView(onChange: { [weak self] in
                self?.settingsWindow?.title = L.settingsTitle
            }))
            // The window follows the form's height as notes appear and disappear.
            hosting.sizingOptions = .preferredContentSize
            let window = NSWindow(contentViewController: hosting)
            window.title = L.settingsTitle
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        settingsWindow?.title = L.settingsTitle
        // A menu-bar-only app is often refused activation, leaving the window behind others. Being a
        // regular app (with a Dock icon) while settings are open brings it to the front reliably.
        NSApp.setActivationPolicy(.regular)
        // After the status menu has finished closing, or the activation is lost to it.
        DispatchQueue.main.async { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.settingsWindow?.makeKeyAndOrderFront(nil)
            self?.settingsWindow?.orderFrontRegardless()
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
