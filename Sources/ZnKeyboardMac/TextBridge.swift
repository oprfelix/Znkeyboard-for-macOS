import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Reads the selected text in the frontmost app and replaces it. Both need Accessibility access:
/// reading asks the focused element first and falls back to a simulated ⌘C; replacing pastes,
/// which works in every app. The user's clipboard is restored afterwards.
enum TextBridge {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that leads to System Settings → Accessibility.
    static func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Selects the whole focused field when nothing is selected, so the toolbar can work on what was
    /// just typed. Uses Accessibility where the app allows it, ⌘A otherwise.
    static func selectWholeFieldIfNothingSelected() async {
        if let selected = accessibilitySelectedText(), !selected.isEmpty { return }
        let system = AXUIElementCreateSystemWide()
        if let field = system.element(kAXFocusedUIElementAttribute),
           let text = field.string(kAXValueAttribute),
           field.setRange(kAXSelectedTextRangeAttribute, CFRange(location: 0, length: (text as NSString).length)) {
            return
        }
        postShortcut(keyCode: kVK_ANSI_A)
        try? await Task.sleep(nanoseconds: 80_000_000)
    }

    static func selectedText() async -> String? {
        if let text = accessibilitySelectedText(), !text.isEmpty { return text }
        return await copySelection()
    }

    /// Puts [text] where the selection is, then gives the user their clipboard back.
    static func replaceSelection(with text: String) async {
        let pasteboard = NSPasteboard.general
        let saved = PasteboardSnapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        postShortcut(keyCode: kVK_ANSI_V)
        // The target app reads the clipboard asynchronously; give it time before restoring.
        try? await Task.sleep(nanoseconds: 600_000_000)
        saved.restore(to: pasteboard)
    }

    private static func accessibilitySelectedText() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused, CFGetTypeID(element) == AXUIElementGetTypeID() else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    /// Browsers and Electron apps often don't expose the selection; copying it always works.
    private static func copySelection() async -> String? {
        let pasteboard = NSPasteboard.general
        let saved = PasteboardSnapshot(pasteboard)
        let before = pasteboard.changeCount
        postShortcut(keyCode: kVK_ANSI_C)
        for _ in 0..<20 where pasteboard.changeCount == before {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        guard pasteboard.changeCount != before else { return nil }
        let text = pasteboard.string(forType: .string)
        saved.restore(to: pasteboard)
        return text
    }

    private static func postShortcut(keyCode: Int) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}

/// Every item and type on the clipboard, so a borrowed clipboard can be put back as it was.
private struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            var types: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { types[type] = data }
            }
            return types
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restored = items.map { types -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in types { item.setData(data, forType: type) }
            return item
        }
        if !restored.isEmpty { pasteboard.writeObjects(restored) }
    }
}
