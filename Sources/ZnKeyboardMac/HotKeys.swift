import AppKit
import Carbon.HIToolbox
import Foundation

/// The actions a global shortcut can trigger.
enum ShortcutAction: String, CaseIterable {
    case polish
    case translate
    case screenshot

    var hotKeyID: UInt32 {
        switch self {
        case .polish: 1
        case .translate: 2
        case .screenshot: 3
        }
    }

    var others: [ShortcutAction] { Self.allCases.filter { $0 != self } }

    var defaultShortcut: Shortcut {
        switch self {
        case .polish: Shortcut(keyCode: kVK_ANSI_R, modifiers: cmdKey | shiftKey, key: "R")
        case .translate: Shortcut(keyCode: kVK_ANSI_T, modifiers: cmdKey | shiftKey, key: "T")
        case .screenshot: Shortcut(keyCode: kVK_ANSI_E, modifiers: cmdKey | shiftKey, key: "E")
        }
    }
}

/// A key with Carbon modifier masks, and the key's name as recorded ("R", "Space", "F5").
struct Shortcut: Codable, Equatable {
    var keyCode: Int
    var modifiers: Int
    var key: String

    /// "⌃⌥⇧⌘R", in the order macOS menus use.
    var display: String {
        var text = ""
        if modifiers & controlKey != 0 { text += "⌃" }
        if modifiers & optionKey != 0 { text += "⌥" }
        if modifiers & shiftKey != 0 { text += "⇧" }
        if modifiers & cmdKey != 0 { text += "⌘" }
        return text + key
    }

    /// Same key and modifiers, whatever the recorded name.
    func collides(with other: Shortcut) -> Bool { keyCode == other.keyCode && modifiers == other.modifiers }

    /// Null when the event is not a usable global shortcut: it needs ⌘, ⌥ or ⌃.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !flags.isDisjoint(with: [.command, .option, .control]) else { return nil }
        var modifiers = 0
        if flags.contains(.command) { modifiers |= cmdKey }
        if flags.contains(.option) { modifiers |= optionKey }
        if flags.contains(.control) { modifiers |= controlKey }
        if flags.contains(.shift) { modifiers |= shiftKey }
        self.init(keyCode: Int(event.keyCode), modifiers: modifiers, key: Self.name(for: event))
    }

    init(keyCode: Int, modifiers: Int, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    private static func name(for event: NSEvent) -> String {
        if let special = specialKeys[Int(event.keyCode)] { return special }
        // Without modifiers applied, so ⌥T reads "T" rather than "†".
        return (event.charactersIgnoringModifiers ?? "?").uppercased()
    }
}

/// System-wide shortcuts through Carbon's hot key API, which needs no special permission.
final class HotKeys {
    static let shared = HotKeys()

    private var actions: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlerInstalled = false
    /// Set while a new shortcut is being recorded, so pressing an existing one doesn't fire it.
    var isPaused = false

    /// Replaces whatever [id] had. Returns false if another app holds the combination.
    @discardableResult
    func register(id: UInt32, shortcut: Shortcut, action: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()
        unregister(id: id)
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5A4E_4B42), id: id) // "ZNKB"
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode), UInt32(shortcut.modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr, let ref else { return false }
        refs[id] = ref
        actions[id] = action
        return true
    }

    func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        actions[id] = nil
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            DispatchQueue.main.async {
                guard !HotKeys.shared.isPaused else { return }
                HotKeys.shared.actions[hotKeyID.id]?()
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
