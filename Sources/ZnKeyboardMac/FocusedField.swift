import AppKit
import ApplicationServices

/// The text field the user is typing in, with its caret on screen. Built only when the app exposes
/// all of it through Accessibility; otherwise there is nothing to anchor the toolbar to.
struct FocusedField {
    let element: AXUIElement
    let text: String
    let selection: CFRange
    /// In AppKit screen coordinates (origin bottom-left of the primary screen).
    let caretRect: NSRect

    static func current(in app: NSRunningApplication) -> FocusedField? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        // A busy app must not stall the menu bar; give up quickly and try again next tick.
        AXUIElementSetMessagingTimeout(appElement, 0.15)
        guard let element = appElement.element(kAXFocusedUIElementAttribute),
              element.string(kAXSubroleAttribute) != kAXSecureTextFieldSubrole as String,
              isEditable(element),
              let text = element.string(kAXValueAttribute),
              text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2,
              let selection = element.range(kAXSelectedTextRangeAttribute),
              let caret = caretRect(element, selection) else { return nil }
        return FocusedField(element: element, text: text, selection: selection, caretRect: caret)
    }

    private static let textRoles: Set<String> = [
        kAXTextFieldRole as String, kAXTextAreaRole as String, kAXComboBoxRole as String, "AXSearchField",
    ]

    private static func isEditable(_ element: AXUIElement) -> Bool {
        guard let role = element.string(kAXRoleAttribute) else { return false }
        return textRoles.contains(role) || (role != kAXStaticTextRole as String && element.isSettable(kAXValueAttribute))
    }

    /// Bounds of the selection, or of the character before an empty caret (an empty range often has
    /// no bounds). Converted from Accessibility's top-left origin to AppKit's bottom-left one.
    private static func caretRect(_ element: AXUIElement, _ selection: CFRange) -> NSRect? {
        var rect = element.bounds(for: selection)
        if rect.map({ $0.width <= 0 && $0.height <= 0 }) ?? true, selection.location > 0 {
            if let previous = element.bounds(for: CFRange(location: selection.location - 1, length: 1)) {
                rect = CGRect(x: previous.maxX, y: previous.minY, width: 1, height: previous.height)
            }
        }
        guard let rect, rect.height > 0, rect.height < 200,
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
