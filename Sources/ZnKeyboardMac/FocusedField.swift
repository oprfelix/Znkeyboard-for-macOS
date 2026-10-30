import AppKit
import ApplicationServices

/// The text field the user is typing in, with its selection on screen. Built only when the app
/// exposes it through Accessibility; otherwise there is nothing to anchor the toolbar to.
struct FocusedField {
    let element: AXUIElement
    /// Changes whenever the text or selection changes; nothing of the text itself is kept.
    let signature: String
    /// The selection (or caret) in AppKit screen coordinates (origin bottom-left of the primary screen).
    let caretRect: NSRect
    /// Some text is selected, not just a caret.
    let hasSelection: Bool

    static func current(in app: NSRunningApplication) -> FocusedField? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        // A busy app must not stall the menu bar; give up quickly and try again next tick.
        AXUIElementSetMessagingTimeout(appElement, 0.15)
        guard let element = appElement.element(kAXFocusedUIElementAttribute) else {
            CaretLog.note("no focused element")
            return nil
        }
        let role = element.string(kAXRoleAttribute) ?? "?"
        guard element.string(kAXSubroleAttribute) != kAXSecureTextFieldSubrole as String, isEditable(element, role: role) else {
            CaretLog.note("not editable: \(role)")
            return nil
        }
        let text = element.string(kAXValueAttribute)
        if let text, text.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
            CaretLog.note("too short: \(role)")
            return nil
        }

        // Native text views report a character range; web pages (Chrome, Safari) often only text markers.
        if let selection = element.range(kAXSelectedTextRangeAttribute), let caret = caretRect(element, selection) {
            CaretLog.note("ok range: \(role), selected \(selection.length > 0)")
            let signature = "\(text?.hashValue ?? 0)|\(selection.location)|\(selection.length)"
            return FocusedField(element: element, signature: signature, caretRect: caret, hasSelection: selection.length > 0)
        }
        if let rect = markerSelectionBounds(element), let caret = convert(rect) {
            // The marker objects are new on every read, so the signature uses what they describe.
            let selectedCount = element.string(kAXSelectedTextAttribute)?.count ?? (rect.width > 3 ? Int(rect.width) : 0)
            CaretLog.note("ok markers: \(role), selected \(selectedCount > 0)")
            let signature = "\(text?.hashValue ?? 0)|\(selectedCount)|\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))"
            return FocusedField(element: element, signature: signature, caretRect: caret, hasSelection: selectedCount > 0)
        }
        CaretLog.note("no caret: \(role), value \(text == nil ? "missing" : "present")")
        return nil
    }

    enum SelectionState { case notEditable, empty, selected, unknown }

    /// Whether the focused field is editable and has a selection, without needing its position.
    /// Chrome often reports neither range nor bounds after a mouse selection: that is `unknown`.
    static func selectionState(in app: NSRunningApplication) -> SelectionState {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.15)
        guard let element = appElement.element(kAXFocusedUIElementAttribute) else { return .notEditable }
        let role = element.string(kAXRoleAttribute) ?? "?"
        guard element.string(kAXSubroleAttribute) != kAXSecureTextFieldSubrole as String,
              isEditable(element, role: role) else { return .notEditable }
        if let range = element.range(kAXSelectedTextRangeAttribute) { return range.length > 0 ? .selected : .empty }
        if let selected = element.string(kAXSelectedTextAttribute), !selected.isEmpty { return .selected }
        return .unknown
    }

    private static let textRoles: Set<String> = [
        kAXTextFieldRole as String, kAXTextAreaRole as String, kAXComboBoxRole as String, "AXSearchField",
    ]

    /// Text inputs, anything with a settable value, and rich editors in web pages (which sit under an
    /// editable ancestor).
    private static func isEditable(_ element: AXUIElement, role: String) -> Bool {
        if textRoles.contains(role) { return true }
        if role == kAXStaticTextRole as String { return element.value("AXEditableAncestor") != nil }
        return element.isSettable(kAXValueAttribute) || element.value("AXEditableAncestor") != nil
    }

    /// Bounds of the selection, or of the character before an empty caret (an empty range often has
    /// no bounds).
    private static func caretRect(_ element: AXUIElement, _ selection: CFRange) -> NSRect? {
        var rect = element.bounds(for: selection)
        if rect.map({ $0.width <= 0 && $0.height <= 0 }) ?? true, selection.location > 0 {
            if let previous = element.bounds(for: CFRange(location: selection.location - 1, length: 1)) {
                rect = CGRect(x: previous.maxX, y: previous.minY, width: 1, height: previous.height)
            }
        }
        return rect.flatMap(convert)
    }

    /// Bounds of the selection's text-marker range, as WebKit and Chromium report it.
    private static func markerSelectionBounds(_ element: AXUIElement) -> CGRect? {
        guard let markers = element.value("AXSelectedTextMarkerRange") else { return nil }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, "AXBoundsForTextMarkerRange" as CFString, markers, &result
        ) == .success, let result, CFGetTypeID(result) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(result as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }

    /// From Accessibility's top-left origin to AppKit's bottom-left one; nil if not a plausible caret.
    private static func convert(_ rect: CGRect) -> NSRect? {
        guard rect.height > 0, rect.height < 200,
              let primary = NSScreen.screens.first else { return nil }
        let converted = NSRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: max(rect.width, 1), height: rect.height)
        guard NSScreen.screens.contains(where: { $0.frame.intersects(converted) }) else { return nil }
        return converted
    }
}

extension AXUIElement {
    func value(_ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success ? value : nil
    }

    func string(_ attribute: String) -> String? { value(attribute) as? String }

    func element(_ attribute: String) -> AXUIElement? {
        guard let value = value(attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    func isSettable(_ attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(self, attribute as CFString, &settable) == .success && settable.boolValue
    }

    func range(_ attribute: String) -> CFRange? {
        guard let value = value(attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        return AXValueGetValue(value as! AXValue, .cfRange, &range) ? range : nil
    }

    func setRange(_ attribute: String, _ range: CFRange) -> Bool {
        var range = range
        guard let value = AXValueCreate(.cfRange, &range) else { return false }
        return AXUIElementSetAttributeValue(self, attribute as CFString, value) == .success
    }

    func bounds(for range: CFRange) -> CGRect? {
        var range = range
        guard let rangeValue = AXValueCreate(.cfRange, &range) else { return nil }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            self, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &result
        ) == .success, let result, CFGetTypeID(result) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        return AXValueGetValue(result as! AXValue, .cgRect, &rect) ? rect : nil
    }
}

/// Off unless `defaults write dev.zain.znkeyboard.mac debugCaret -bool true`: why the toolbar did or
/// didn't find a caret, one line per change, in ~/Library/Logs/ZnKeyboard/caret.log. Never any text.
enum CaretLog {
    private static var last = ""

    static func note(_ message: String) {
        guard UserDefaults.standard.bool(forKey: "debugCaret"), message != last else { return }
        last = message
        let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
        let line = "\(Date()) \(app) \(message)\n"
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/ZnKeyboard")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("caret.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}
